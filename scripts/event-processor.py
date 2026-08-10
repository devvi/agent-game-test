#!/usr/bin/env python3
"""Deterministic event preprocessor for workflow-pending-poller cron.

Reads ~/.hermes/workflow-pending.json, applies deterministic rules:
  - Groups events by issue number
  - Keeps only the highest-priority event per issue
  - Validates check_run.completed fields (branch, conclusion)
  - Removes non-actionable events from the file
  - Outputs simplified actionable event list for LLM

This script runs BEFORE the LLM agent in the cron tick.
Its stdout is injected into the LLM's context.

Output format (to stdout):
  Empty                                → no actionable events
  P1: check_run.completed,issue=N,...  → one per line, sorted P1 first
  P2: issues.labeled,issue=N,...      → labeled events follow

File modification:
  - REMOVES from file: pull_request.*, check_run.created, any non-actionable
  - KEEPS in file: check_run.completed, issues.labeled (for LLM to process)

Uses atomic write (tempfile + rename) to avoid sibling-agent races.
"""

import datetime
import json
import os
import re
import subprocess
import sys
import time
import urllib.request

# ── Bootstrap GH_TOKEN from .env (cron stripped env) ──────────────────
_ENV_FILE = os.path.expanduser("~/.hermes/.env")
if os.path.exists(_ENV_FILE) and not os.environ.get("GH_TOKEN"):
    try:
        with open(_ENV_FILE) as _f:
            for _line in _f:
                _line = _line.strip()
                if _line.startswith("#") or "=" not in _line:
                    continue
                _k, _v = _line.split("=", 1)
                _k = _k.strip(); _v = _v.strip().strip('\"').strip("'")
                if _k in ("GH_TOKEN", "GITHUB_TOKEN") and not os.environ.get(_k):
                    os.environ[_k] = _v
    except Exception:
        pass
from typing import Optional
from collections import defaultdict

# ── Pure-logic core (split 2026-07-31, P1-7) ───────────────────
# Deterministic decision functions live in event_processor_lib.py so they
# can be unit-tested in isolation (tests/pipeline/test_event_processor.py).
# This file keeps: IO (pending file), gh calls, caches, scheduling.
# Ensure the lib (sibling file) is importable both as a script (cron runs
# `python3 ~/.hermes/scripts/event-processor.py`) and via importlib (tests).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from event_processor_lib import (
    DEFAULT_CONFIG,
    WORK_HOUR_PRESETS,
    PRIORITY,
    PRIORITY_MAX,
    PRIORITY_LABEL_ORDER,
    read_workflow_config,
    is_work_hours,
    _time_in_window,
    _event_action,
    event_priority,
    should_discard,
    validate_check_run,
    parse_dependencies,
    depth_for_issue,
    count_self_correct_cycles,
)

PENDING_FILE = os.environ.get("EVENT_PROCESSOR_PENDING_FILE") or os.path.expanduser("~/.hermes/workflow-pending.json")
WORKFLOW_CONFIG = os.path.expanduser("~/.hermes/workflow-config.json")

# gh() call cache — avoids redundant API calls within a single tick
_GH_CACHE: dict = {}
_GH_CACHE_TTL = 30

# ── Audit log (P2 metrics, 2026-07-31) ─────────────────────────
# One JSONL line per tick decision. Consumed by workflow-watchdog.py
# (silent-SPAWN detection) and the dashboard. Never raises.
AUDIT_FILE = os.path.expanduser("~/.hermes/workflow-audit.jsonl")


def _audit(**fields):
    """Append one JSONL audit record. Best-effort — failures are swallowed."""
    try:
        record = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"), **fields}
        with open(AUDIT_FILE, "a") as f:
            f.write(json.dumps(record) + "\n")
    except Exception:
        pass

# ── Issue list cache: fetch ALL open issues once per tick ────────────
# Replaces N separate `gh issue list --label <x>` calls with one fetch
# and in-memory filtering. Dramatically reduces gh API latency.
_ISSUES_CACHE: dict = {}  # {"fetched_at": ts, "issues": [...]}

def _ensure_issues_cache(force_refresh=False) -> list:
    """Fetch ALL open issues once per tick, return list of issue dicts.
    
    Each dict: {"number": N, "labels": [...], "title": "..."}
    """
    now = time.time()
    cached = _ISSUES_CACHE.get("issues")
    fetched_at = _ISSUES_CACHE.get("fetched_at", 0)
    if not force_refresh and cached and (now - fetched_at) < _GH_CACHE_TTL:
        return cached
    raw = gh(
        "issue", "list", "--state", "open",
        "--json", "number,labels,title,body",
        "--limit", "100",
    )
    if not raw:
        _ISSUES_CACHE["issues"] = []
        _ISSUES_CACHE["fetched_at"] = now
        return []
    try:
        issues = json.loads(raw)
    except json.JSONDecodeError:
        issues = []
    _ISSUES_CACHE["issues"] = issues
    _ISSUES_CACHE["fetched_at"] = now
    return issues


def _invalidate_issues_cache_for(issue_num: int):
    """Update the issue's label in cache after advancement.
    Does NOT remove the issue — dependency checks need it.
    Prevents _pick_candidate() from re-picking by ensuring
    it no longer has workflow/backlog label."""
    cached = _ISSUES_CACHE.get("issues")
    if cached is None:
        return
    for iss in cached:
        if iss.get("number") == issue_num:
            # Update labels in-place so dependency checks still find this issue
            labels = iss.get("labels", [])
            # Remove workflow/backlog, add workflow/available
            labels = [l for l in labels if l.get("name") != "workflow/backlog"]
            labels.append({"name": "workflow/available"})
            iss["labels"] = labels
            break


PENDING_FILE = os.environ.get("EVENT_PROCESSOR_PENDING_FILE") or os.path.expanduser("~/.hermes/workflow-pending.json")
WORKFLOW_CONFIG = os.path.expanduser("~/.hermes/workflow-config.json")

def is_paused() -> bool:
    """Check if workflow is paused via pause file OR workflow-config.json."""
    # Check pause file first (fastest)
    if os.path.exists(os.path.expanduser("~/.hermes/workflow-pause")):
        return True
    # Fall back to workflow-config.json (written by /workflow pause)
    try:
        cfg_path = os.path.expanduser("~/.hermes/workflow-config.json")
        if os.path.exists(cfg_path):
            with open(cfg_path) as f:
                cfg = json.load(f)
            return not cfg.get("enabled", True)
    except Exception:
        pass
    return False


def should_process_event(event_type: str, label: str = "") -> bool:
    """Determine if an event should be processed now.
    
    Outside work hours:
      - CI results (check_run) → YES (pipeline must finish)
      - Phase labels (workflow/research/plan/implement/self-correct) → YES
      - status/done → YES
      - Picker (new issue entry) → NO
      - workflow/available → NO
    """
    if is_work_hours():
        return True
    if is_paused():
        return False
    # Always process pipeline events even outside work hours
    if event_type in ("check_run",):
        return True
    if label.startswith("workflow/") and label not in ("workflow/available", "workflow/backlog"):
        return True  # research, plan, implement, self-correct, status/done
    # Block everything else (available, picker)
    return False


def issue_priority_sort_key(issue_num: int) -> int:
    """Return sort index for an issue's priority label. Lower = higher priority.
    Uses cached open issues first; falls back to gh view for closed issues."""
    # Check open issues cache first (saves a gh call)
    try:
        issues = _ensure_issues_cache()
        for iss in issues:
            if iss["number"] == issue_num:
                label_names = [l.get("name", "") for l in iss.get("labels", [])]
                for idx, p in enumerate(PRIORITY_LABEL_ORDER):
                    if p in label_names:
                        return idx
                return PRIORITY_LABEL_ORDER.index("priority/medium")
    except Exception:
        pass
    # Fallback: direct gh view (for closed issues not in cache)
    raw = gh("issue", "view", str(issue_num), "--json", "labels")
    if not raw:
        return PRIORITY_LABEL_ORDER.index("priority/medium")
    try:
        data = json.loads(raw)
        label_names = [l.get("name", "") for l in data.get("labels", [])]
        for idx, p in enumerate(PRIORITY_LABEL_ORDER):
            if p in label_names:
                return idx
        return PRIORITY_LABEL_ORDER.index("priority/medium")
    except (json.JSONDecodeError, ValueError):
        return PRIORITY_LABEL_ORDER.index("priority/medium")

def read_pending():
    """Read the pending file, return events list."""
    if not os.path.exists(PENDING_FILE):
        return []
    try:
        with open(PENDING_FILE) as f:
            data = json.load(f)
        return data.get("events", [])
    except (json.JSONDecodeError, IOError):
        return []


def write_pending(events):
    """Write events back to pending file using fcntl lock.

    Uses fcntl.flock() to coordinate with the webhook dispatcher's
    concurrent writes. Atomic rename (shutil.move) was unsafe because
    it replaces the directory entry, orphaning the webhook writer's fd
    and causing silent event loss.
    """
    import fcntl
    data = {"events": events, "processed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    # Must open with 'w' first to create if not exists, then re-open with 'r+'
    # for the lock-protected write. 'r+' on a missing file raises FileNotFoundError.
    if not os.path.exists(PENDING_FILE):
        with open(PENDING_FILE, 'w') as f:
            json.dump(data, f, indent=2)
        return
    with open(PENDING_FILE, 'r+') as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            f.seek(0)
            json.dump(data, f, indent=2)
            f.truncate()
            f.flush()
            os.fsync(f.fileno())
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)


# ── Stage → branch prefix mapping ─────────────────────────────────
STAGE_BRANCH_PREFIX = {
    "research": "research/",
    "plan": "plan/",
    "implement": "impl/",
    "self-correct": "self-correct/",
}


def gh(*args: str) -> str:
    """Run gh command, return stdout. Returns empty string on error.
    Results cached for 30s within a single tick.
    NOTE: GH_REPO is set process-wide at module load (manifest project.repo)
    so gh never depends on cwd (cron runs scripts from ~/.hermes/scripts/)."""
    cache_key = "|".join(str(a) for a in args)
    cached = _GH_CACHE.get(cache_key)
    if cached and time.time() - cached["ts"] < _GH_CACHE_TTL:
        return cached["data"]
    try:
        result = subprocess.run(["gh"] + list(args),
                                capture_output=True, text=True, timeout=10)
        data = result.stdout.strip() if result.returncode == 0 else ""
        _GH_CACHE[cache_key] = {"data": data, "ts": time.time()}
        if len(_GH_CACHE) > 200:
            now = time.time()
            for k in list(_GH_CACHE):
                if now - _GH_CACHE[k]["ts"] > _GH_CACHE_TTL:
                    del _GH_CACHE[k]
        return data
    except (subprocess.TimeoutExpired, OSError):
        return ""


def get_issue_body(issue_num: int) -> str:
    """Fetch issue body via gh CLI (cached per tick)."""
    return _get_issue_body_cached(issue_num)


# ── Body cache: avoid redundant gh issue view calls within one tick ────
_BODY_CACHE: dict = {}

def _get_issue_body_cached(issue_num: int) -> str:
    """Fetch issue body with tick-level caching."""
    if issue_num in _BODY_CACHE:
        return _BODY_CACHE[issue_num]
    body = gh("issue", "view", str(issue_num), "--json", "body", "--jq", ".body")
    _BODY_CACHE[issue_num] = body
    return body


def check_dependency_resolved(dep: dict) -> bool:
    """Check if a single dependency is satisfied.

    full: target issue has status/done or is CLOSED
    design: target issue is at workflow/plan stage or beyond
    """
    raw = gh("issue", "view", str(dep["issue"]),
             "--json", "state,labels")
    if not raw:
        return False  # conservative: treat as unresolved
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return False

    # Closed issue = always resolved
    if data.get("state", "").lower() == "closed":
        return True

    labels = [l.get("name", "") for l in data.get("labels", [])]

    if dep["type"] == "full":
        return "status/done" in labels

    if dep["type"] == "design":
        for wf in ("workflow/plan", "workflow/implement", "workflow/self-correct"):
            if wf in labels:
                return True
        return False

    return False


def _has_unresolved_dependencies(issue_num: int) -> list[dict]:
    """Check if an issue has unresolved dependencies.
    Uses cached issue data (body + labels) instead of gh API calls.
    Returns list of unresolved deps, or empty list if none.
    """
    issues = _ensure_issues_cache()
    issue_map = {i["number"]: i for i in issues}
    cached = issue_map.get(issue_num)
    if not cached:
        return []
    body = cached.get("body", "")
    if not body:
        return []
    deps = parse_dependencies(body)
    if not deps:
        return []
    # Use cached issue labels to check resolution status
    issues = _ensure_issues_cache()
    issue_map = {i["number"]: i for i in issues}
    unresolved = []
    for dep in deps:
        dep_num = dep["issue"]
        dep_type = dep.get("type", "full")
        cached = issue_map.get(dep_num)
        
        # If dependency issue is NOT in the open-issues cache, it must be
        # CLOSED — only open issues are returned by --state open.
        if cached is None:
            continue  # closed = resolved
        
        # Got cached data — check labels
        dep_labels = [l.get("name","") for l in cached.get("labels",[])]
        
        # status/done = resolved
        if "status/done" in dep_labels:
            continue
        
        # design dependency: plan/implement stages = resolved
        if dep_type == "design":
            if any(l.startswith("workflow/plan") or l.startswith("workflow/implement") for l in dep_labels):
                continue
        
        # Not resolved yet
        unresolved.append(dep)
    return unresolved


def _is_pr_blocked(pr_num: int) -> bool:
    """Check if a PR has status/blocked label.

    Returns True if blocked (review should NOT be spawned).
    On gh error, returns False (conservative: allow spawn).
    """
    raw = gh("pr", "view", str(pr_num), "--json", "labels")
    if not raw:
        return False
    try:
        labels = [l["name"] for l in json.loads(raw).get("labels", [])]
        return "status/blocked" in labels
    except (json.JSONDecodeError, KeyError):
        return False


def _parent_issue_blocked(pr_num: int) -> bool:
    """Check if the parent issue of a PR has status/blocked.

    Extracts parent issue from PR body (Parent #N or Closes #N).
    Returns True if parent issue has status/blocked.
    On gh error or if parent can't be determined, returns False.
    """
    body = gh("pr", "view", str(pr_num), "--json", "body", "--jq", ".body")
    if not body:
        return False
    m = re.search(r'(?:Closes|parent|Parent)\s*#(\d+)', body)
    if not m:
        return False
    parent = int(m.group(1))
    raw = gh("issue", "view", str(parent), "--json", "labels")
    if not raw:
        return False
    try:
        labels = [l["name"] for l in json.loads(raw).get("labels", [])]
        return "status/blocked" in labels
    except (json.JSONDecodeError, KeyError):
        return False


def _is_pr_merged(pr_num: int) -> bool:
    """Check if a PR is already merged or closed.
    
    Returns True if the PR no longer needs processing (merged/closed).
    Retries up to 3 times on gh failure — during cron ticks with many
    concurrent gh calls, individual commands may intermittently
    timeout or get rate-limited. A single failure should not let
    a stale event spawn a redundant agent.
    """
    for attempt in range(3):
        raw = gh("pr", "view", str(pr_num), "--json", "state")
        if raw:
            try:
                state = json.loads(raw).get("state", "")
                return state in ("MERGED", "CLOSED")
            except (json.JSONDecodeError, KeyError):
                return False
        if attempt < 2:
            time.sleep(1)
    # All 3 attempts failed — fall back to issue state check below
    return False


def _is_issue_closed(issue_num: int) -> bool:
    """Check if an issue is already closed.
    
    Returns True if closed (event is stale). Retries 3x on gh failure.
    """
    for attempt in range(3):
        raw = gh("issue", "view", str(issue_num), "--json", "state")
        if raw:
            try:
                return json.loads(raw).get("state", "") == "CLOSED"
            except (json.JSONDecodeError, KeyError):
                return False
        if attempt < 2:
            time.sleep(1)
    return False


def _extract_parent_issue(pr_num: int) -> Optional[int]:
    """Extract parent issue number from a PR's body.

    Parses 'Parent #N' or 'Closes #N' from the PR body via gh CLI.
    Returns None if the extraction fails or the PR can't be fetched.
    Uses cached gh() call per tick.
    """
    raw = gh("pr", "view", str(pr_num), "--json", "body", "--jq", ".body")
    if not raw:
        return None
    m = re.search(r'(?:Closes|parent|Parent)\s*#(\d+)', raw)
    if m:
        return int(m.group(1))
    return None


def _pr_exists_for_issue(stage: str, issue: int) -> bool:
    """Check if a GitHub PR already exists for this stage+issue combination.
    Returns True if a PR exists (SPAWN should be skipped).
    On error (gh unavailable, timeout), returns False so spawn still happens."""
    prefix = STAGE_BRANCH_PREFIX.get(stage)
    if not prefix:
        return False
    branch = f"{prefix}{issue}"
    try:
        result = subprocess.run(
            ["gh", "pr", "list",
             "--search", f"head:{branch}",
             "--json", "number",
             "--jq", "length",
             "--limit", "1"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            count = int(result.stdout.strip() or "0")
            return count > 0
    except (subprocess.TimeoutExpired, ValueError, OSError):
        pass
    return False  # on error, spawn anyway (cautious)


WORKDIR = os.path.expanduser("~/workspace/agent-game-test")

# ── Game Environment ─────────────────────────────────────────
MANIFEST_PATH = os.path.join(WORKDIR, "game-env", "manifest.yaml")

def _load_manifest() -> dict:
    """Load game environment manifest. Falls back to project defaults."""
    default = {
        "engine": {"name": "godot", "runner": "godot"},
        "source": {"dir": "gdscripts/"},
        "test": {"dir": "tests/", "framework": "gdscript"},
        "code_gen": {"language": "gdscript"},
        "git": {"default_branch": "main"},
    }
    if not os.path.exists(MANIFEST_PATH):
        return default
    try:
        with open(MANIFEST_PATH) as f:
            import yaml
            return {**default, **yaml.safe_load(f)}
    except Exception:
        return default

MANIFEST = _load_manifest()
SRC_DIR = MANIFEST.get("source", {}).get("dir", "public/src/")
TEST_DIR = MANIFEST.get("test", {}).get("dir", "tests/")
DEFAULT_BRANCH = MANIFEST.get("git", {}).get("default_branch", "main")
# Project repo (P3 parameterization, 2026-07-31): from manifest, not hardcoded.
PROJECT_REPO = (
    MANIFEST.get("project", {}).get("repo")
    or MANIFEST.get("workflow", {}).get("repo")
    or "devvi/agent-game-test"
)
WEBHOOK_BASE = f"https://api.github.com/repos/{PROJECT_REPO}/hooks"
# gh needs repo context; cron scripts run with cwd=~/.hermes/scripts/ so
# cwd-based detection fails. Set GH_REPO process-wide at load time so EVERY
# gh invocation (gh() helper AND direct subprocess.run(["gh", ...])) works.
os.environ.setdefault("GH_REPO", PROJECT_REPO)

# ── Issue Picker ─────────────────────────────────────────────────
# Reads backlog, picks candidate, adds workflow/available label.

MAX_CONCURRENT = int(os.environ.get("MAX_CONCURRENT_ISSUES", "4"))
# MAX_SPAWN_PER_TICK removed 2026-07-29 — dead code.
# Phase agents capped by MAX_PHASE_SLOTS; review/self-correct pass unconditionally (reserved slots).
# Was 4 to allow review/self-correct alongside phase agents, but the reserved-slot
# mechanism (line ~1027) already handles this correctly.
MAX_PHASE_SLOTS = int(os.environ.get("MAX_PHASE_SLOTS", "4"))
# Phase agents (research/plan/implement) capped at MAX_PHASE_SLOTS.
# Review and self-correct don't count toward this cap (reserved slots).
# Concurrency control: MAX_CONCURRENT_ISSUES + MAX_PHASE_SLOTS + pre-spawn
# duplicate checks. Distributed label locks (workflow/lock-*) were REMOVED
# 2026-07-29 — the label-based lock code was dead weight and is gone.

# Stage labels that count toward concurrency limit
ACTIVE_STAGE_LABELS = [
    "workflow/research", "workflow/plan", "workflow/implement",
    "workflow/self-correct",
]
WORKFLOW_LABELS = set(ACTIVE_STAGE_LABELS + ["workflow/available", "workflow/backlog", "status/done"])


def current_workflow_count() -> int:
    """Count how many issues are currently in active stages (from cache).
    Excludes lock-mbot issues (already have dedicated agents)."""
    issues = _ensure_issues_cache()
    return sum(
        1 for iss in issues
        if any(l.get("name", "") in ACTIVE_STAGE_LABELS for l in iss.get("labels", []))
        and "workflow/lock-mbot" not in [l.get("name", "") for l in iss.get("labels", [])]
    )


def get_issue_target_files(issue_num: int) -> set:
    """Get files that this issue's implement phase will modify.
    Reads DESIGN doc if available, otherwise returns empty set."""
    try:
        import glob
        design_files = glob.glob(
            os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         "..", "docs", "DESIGN", f"{issue_num}-*.md")
        )
        if design_files:
            with open(design_files[0]) as f:
                content = f.read()
            files = set()
            for m in re.finditer(r'\`([^\`]+?\.(?:js|html|css|yml|json))\`', content):
                files.add(m.group(1))
            return files
    except Exception:
        pass
    return set()


def _get_active_issue_target_files() -> set:
    """Get target files for all currently active (impl stage) issues (from cache)."""
    issues = _ensure_issues_cache()
    all_files = set()
    for iss in issues:
        labels = [l.get("name", "") for l in iss.get("labels", [])]
        if any(l in ACTIVE_STAGE_LABELS for l in labels):
            all_files |= get_issue_target_files(iss["number"])
    return all_files


def _count_active_phase_agents() -> int:
    """Count phase agents (research/plan/implement) from cache.
    Excludes issues with lock-mbot (already has an agent assigned)."""
    issues = _ensure_issues_cache()
    phase_labels = {"workflow/research", "workflow/plan", "workflow/implement"}
    return sum(
        1 for iss in issues
        if any(l.get("name", "") in phase_labels for l in iss.get("labels", []))
        and "workflow/lock-mbot" not in [l.get("name", "") for l in iss.get("labels", [])]
    )


def _has_file_conflict(issue_num: int, active_files: set) -> bool:
    """Check if this issue's target files overlap with currently active issues."""
    if not active_files:
        return False
    target = get_issue_target_files(issue_num)
    if not target:
        return False  # no DESIGN doc yet → conservative: assume no conflict
    return bool(target & active_files)


def _pick_candidates(limit: int) -> list[int]:
    """Scan backlog and pick up to `limit` best candidates (from cache).

    Criteria (in order):
    1. In workflow/backlog (not already at workflow/available)
    2. Has priority label (critical > high > medium > low)
    3. Dependencies resolved
    4. No file conflict with current implement-stage issues

    Returns list of issue numbers ready for workflow/available.
    """
    active_files = _get_active_issue_target_files()

    issues = _ensure_issues_cache()
    if not issues:
        return []

    # Collect all backlog candidates
    backlog_candidates = []
    for iss in issues:
        label_names = [l.get("name", "") for l in iss.get("labels", [])]
        if "workflow/backlog" not in label_names:
            continue
        if "workflow/available" in label_names:
            continue
        backlog_candidates.append(iss)

    if not backlog_candidates:
        return []

    # Sort by priority label
    def _sort_key(iss):
        label_names = [l.get("name", "") for l in iss.get("labels", [])]
        for idx, p in enumerate(PRIORITY_LABEL_ORDER):
            if p in label_names:
                return idx
        return len(PRIORITY_LABEL_ORDER)

    backlog_candidates.sort(key=_sort_key)

    # Pick up to `limit` valid candidates
    picked = []
    for candidate in backlog_candidates:
        if len(picked) >= limit:
            break
        n = candidate["number"]
        unresolved = _has_unresolved_dependencies(n)
        if unresolved:
            continue
        if _has_file_conflict(n, active_files):
            continue
        picked.append(n)

    return picked


# ── Per-issue spawn dedup (2026-08-10, canary #358) ─────────────────
# pick_next_issue() emits SPAWN: plan/implement every tick while the issue
# has the label and no PR yet. The cron LLM delegates every tick it sees a
# SPAWN → TWO concurrent plan agents for one issue (18:52 + 18:54). The
# spawn gate records (issue, stage, ts) and suppresses re-emission within
# TTL, so a phase agent gets ONE spawn per attempt. If the agent dies, the
# TTL expiry re-enables spawning; PR creation stops it permanently.
_SPAWN_STATE_FILE = os.path.expanduser("~/.hermes/.spawned-state.json")
_SPAWN_TTL_SECONDS = 1800  # 30 min


def _read_spawn_state() -> dict:
    try:
        with open(_SPAWN_STATE_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


def _write_spawn_state(state: dict) -> None:
    try:
        tmp = _SPAWN_STATE_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(state, f)
        os.replace(tmp, _SPAWN_STATE_FILE)
    except Exception:
        pass  # state file is best-effort; never block spawning on write failure


def _spawn_gate(issue: int, stage: str) -> bool:
    """Return True if issue+stage may emit SPAWN now (dedup within TTL).

    Writes the (issue, stage, ts) marker on first call, so a second call
    within TTL returns False. On any state-file error, returns True
    (prefer a rare duplicate over a silent stall)."""
    try:
        state = _read_spawn_state()
        prev = state.get(str(issue), {})
        now = time.time()
        if prev.get("stage") == stage and now - prev.get("ts", 0) < _SPAWN_TTL_SECONDS:
            return False
        state[str(issue)] = {"stage": stage, "ts": now}
        _write_spawn_state(state)
        return True
    except Exception:
        return True


def pick_next_issue():
    """Entry point: called after slot freed or at window entry.
    Fills up to MAX_CONCURRENT issues.
    For research phase, directly creates the PR (deterministic).
    For plan/implement phases, outputs SPAWN for each issue at
    those labels that doesn't have a corresponding PR yet."""
    if is_paused():
        return
    
    # Pick from backlog — batch up to MAX_CONCURRENT at once
    current = current_workflow_count()
    available = max(0, MAX_CONCURRENT - current)
    if available > 0:
        candidates = _pick_candidates(available)
        for n in candidates:
            # Verify gh commands succeed before patching cache.
            # Silent gh failure + cache patch = issue stuck in backlog forever.
            r1 = gh("issue", "edit", str(n), "--add-label", "workflow/available")
            r2 = gh("issue", "edit", str(n), "--remove-label", "workflow/backlog")
            if not r1 or not r2:
                continue  # gh unavailable — retry next tick, don't corrupt cache
            _invalidate_issues_cache_for(n)
            # Do NOT output SPAWN here — let webhook → pending → preprocess handle it.
            # Preprocess() reads workflow/available events and outputs:
            #   SPAWN: research,issue=N,label=workflow/research
    
    # Also output SPAWN for issues at plan/implement with no PR yet
    issues = _ensure_issues_cache()
    for iss in issues:
        labels = [l.get("name", "") for l in iss.get("labels", [])]
        n = iss["number"]
        if "workflow/plan" in labels:
            existing = gh("pr", "list", "--state", "all",
                          "--search", f"head:plan/{n}- in:headRefName",
                          "--json", "number,state",
                          "--jq", "length")
            if existing is None or int(existing) == 0:
                if _spawn_gate(n, "plan"):
                    print(f"SPAWN: plan,issue={n},label=workflow/plan")
        elif "workflow/implement" in labels:
            existing = gh("pr", "list", "--state", "all",
                          "--search", f"head:impl/{n}- in:headRefName",
                          "--json", "number,state",
                          "--jq", "length")
            if existing is None or int(existing) == 0:
                if _spawn_gate(n, "implement"):
                    print(f"SPAWN: implement,issue={n},label=workflow/implement")


def reconcile():
    """After crash or pause resume: check GitHub state vs pending events.
    Uses cached issue list — iterates open issues once instead of
    5 separate gh issue list calls."""
    events = []
    try:
        events = read_pending()
    except Exception:
        pass
    existing_keys = {e.get("_key") for e in events}
    
    reconcile_labels = [
        "workflow/available", "workflow/research", "workflow/plan",
        "workflow/implement", "workflow/self-correct",
    ]
    
    issues = _ensure_issues_cache()
    for iss in issues:
        label_names = [l.get("name", "") for l in iss.get("labels", [])]
        n = iss["number"]
        for label in reconcile_labels:
            if label not in label_names:
                continue
            event_key = f"issues.labeled#{n}:{label}"
            if event_key not in existing_keys:
                events.append({
                    "_key": event_key,
                    "type": "issues.labeled",
                    "issue": n,
                    "repo": PROJECT_REPO,
                    "ts": time.time(),
                    "label": label,
                })
    
    if events:
        write_pending(events)


# ── Check-run reconcile (P3b, 2026-07-31) ───────────────────────
# Webhook events can be lost (ngrok restart, gateway crash, route script
# failure). The stalled scan catches *unspawned agents*, but the gap between
# CI completion and event arrival could be minutes. This reconciles CI
# results directly from GitHub as a second data source: any open impl/* PR
# whose head-sha CI has concluded is re-emitted as a check_run.completed
# pending event (deduped via a local state file keyed by pr+sha).
RECONCILE_STATE_FILE = os.path.expanduser("~/.hermes/workflow-reconcile-state.json")


def _read_reconcile_state() -> dict:
    try:
        with open(RECONCILE_STATE_FILE) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}


def _write_reconcile_state(state: dict):
    try:
        with open(RECONCILE_STATE_FILE, "w") as f:
            json.dump(state, f, indent=2)
    except OSError:
        pass


def reconcile_check_runs():
    """Re-emit check_run.completed events for open impl/* PRs whose CI has
    concluded but whose webhook event never arrived.

    Runs on a slow cadence (every N ticks) — see main(). Cheap: one
    `gh pr list` + one `gh api` per open impl PR with an unrecorded sha.
    """
    try:
        state = _read_reconcile_state()
        raw = gh("pr", "list", "--state", "open", "--json",
                 "number,headRefName,headRefOid")
        if not raw:
            return
        prs = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        return

    events = read_pending()
    existing_keys = {e.get("_key") for e in events}
    changed = False

    for pr in prs:
        branch = pr.get("headRefName", "")
        if not branch.startswith("impl/"):
            continue  # research/plan auto-merge; no review gate needed
        pr_num = pr["number"]
        sha = pr.get("headRefOid", "")

        # Already reconciled for this sha?
        prev = state.get(str(pr_num), {})
        if prev.get("sha") == sha:
            continue

        # Get CI conclusion for this exact sha
        try:
            checks_raw = gh("api",
                            f"repos/{PROJECT_REPO}/commits/{sha}/check-runs",
                            "--jq", ".check_runs[] | select(.name==\"test-and-report\") | .conclusion")
        except Exception:
            continue
        if not checks_raw:
            continue  # CI not run yet for this sha — wait
        conclusions = [c.strip() for c in checks_raw.splitlines() if c.strip()]
        if not conclusions:
            continue
        conclusion = conclusions[0]  # newest run for the sha
        if conclusion not in ("success", "failure"):
            continue  # pending/queued/skipped — wait

        key = f"check_run.completed#{pr_num}"
        if key in existing_keys:
            # Event already pending — just record sha so we don't re-add
            state[str(pr_num)] = {"sha": sha, "conclusion": conclusion}
            changed = True
            continue

        # Event lost — re-emit it
        events.append({
            "_key": key,
            "type": "check_run",
            "issue": pr_num,
            "pr": pr_num,
            "repo": PROJECT_REPO,
            "ts": time.time(),
            "branch": branch,
            "conclusion": conclusion,
        })
        existing_keys.add(key)
        state[str(pr_num)] = {"sha": sha, "conclusion": conclusion}
        changed = True

    # Drop state entries for merged/closed PRs (they no longer need reconcile)
    open_prs = {str(p["number"]) for p in prs}
    for n in list(state.keys()):
        if n not in open_prs:
            del state[n]
            changed = True

    if changed:
        write_pending(events)
        _write_reconcile_state(state)


def preprocess():
    """Main preprocessing logic. Returns list of actionable event summaries."""
    events = read_pending()
    if not events:
        return []  # no output, LLM sees nothing

    # Step 1: Group by issue number
    groups = defaultdict(list)
    for event in events:
        issue = event.get("issue")
        if issue is None:
            # Events without issue number — can't group, check individually
            groups["__unknown__"].append(event)
        else:
            groups[str(issue)].append(event)

    # Step 2: For each group, keep only highest-priority event
    # For check_run events with same priority, keep the LATEST (by ts)
    kept = []
    discarded_keys = set()
    for issue_id, group_events in groups.items():
        if issue_id == "__unknown__":
            # Events without issue number — unlikely to be actionable
            for ev in group_events:
                if not should_discard(ev):
                    kept.append(ev)
                else:
                    discarded_keys.add(ev.get("_key", ""))
            continue

        # Sort by priority first, then success-before-failure, then newest first.
        # Without success-before-failure, a newer failure would beat an older
        # success (timestamp tiebreaker), causing review to be skipped.
        # CI success is the definitive state — it means the PR is passing and
        # needs review. A failure from an earlier CI run is stale.
        def _group_sort_key(e):
            is_success = (
                e.get("type") == "check_run"
                and _event_action(e) == "check_run.completed"
                and e.get("conclusion") == "success"
            )
            return (event_priority(e), 0 if is_success else 1, -e.get('ts', 0))
        group_events.sort(key=_group_sort_key)
        best = group_events[0]

        if should_discard(best):
            # Even the best event in this group is discardable
            for ev in group_events:
                discarded_keys.add(ev.get("_key", ""))
        else:
            # Keep the best, discard the rest
            kept.append(best)
            for ev in group_events[1:]:
                discarded_keys.add(ev.get("_key", ""))

    # Step 3: Sort kept events by priority (P1 first), then by issue priority label
    def _sort_key(e):
        ep = event_priority(e)
        if e.get("type") == "issues.labeled":
            issue_num = int(e.get("issue", 0))
            return (ep, issue_priority_sort_key(issue_num))
        return (ep, 2)  # non-labeled events at same priority as medium
    kept.sort(key=_sort_key)

    # Step 4: Validate check_run events
    valid_kept = [e for e in kept if validate_check_run(e)]

    # Step 5: Filter out invalid check_run events (they go to discard pile)
    for e in kept:
        if not validate_check_run(e):
            discarded_keys.add(e.get("_key", ""))

    # Step 6: Write updated file (remove discarded events)
    remaining = [e for e in events if e.get("_key", "") not in discarded_keys]
    write_pending(remaining)

    # Step 7: Generate imperative output for LLM
    # Format: SPAWN:<agent>,issue=N,pr=N,branch=xxx,conclusion=xxx
    # The LLM MUST execute SPAWN instructions — do NOT output [SILENT]
    output_lines = []
    for event in valid_kept:
        etype = event.get("type", "")
        action = _event_action(event)
        issue = event.get("issue", "")
        
        # Universal staleness guard: discard if PR/issue already closed
        if issue:
            n = int(issue) if not isinstance(issue, int) else issue
            if etype == "check_run" and _is_pr_merged(n):
                discarded_keys.add(event.get("_key", ""))
                continue
            if etype == "issues.labeled" and _is_issue_closed(n):
                discarded_keys.add(event.get("_key", ""))
                continue
        # Defense-in-depth: for check_run on impl/* PRs, also verify
        # the parent issue isn't already closed. This catches the
        # check-after-merge race where CI completes right before/after
        # the PR is merged, making the event stale regardless of PR state.
        if etype == "check_run" and event.get("branch", "").startswith("impl/"):
            parent = _extract_parent_issue(event.get("issue", 0))
            if parent and _is_issue_closed(parent):
                discarded_keys.add(event.get("_key", ""))
                continue
        
        if etype == "check_run" and action == "check_run.completed":
            branch = event.get('branch', '')
            conclusion = event.get('conclusion', '')
            if branch.startswith("impl/") and conclusion == "failure":
                # Look up the parent issue from the PR body
                parent_issue = issue  # fallback to PR number
                try:
                    pr_body = subprocess.run(
                        ["gh", "pr", "view", str(issue), "--json", "body", "--jq", ".body"],
                        capture_output=True, text=True, timeout=10
                    ).stdout.strip()
                    m = re.search(r'(?:Closes|parent|Parent)\s*#(\d+)', pr_body)
                    if m:
                        parent_issue = int(m.group(1))
                except Exception:
                    pass
                output_lines.append(
                    f"SPAWN: self-correct,issue={parent_issue},"
                    f"pr={issue},branch={branch},conclusion={conclusion}"
                )
                # SPAWN is one-shot: consume the event immediately. Keeping it
                # in pending re-emits the SPAWN every tick → the cron LLM
                # re-delegates every tick (3 research agents spawned for one
                # issue, 2026-08-10 canary #358). The LLM's "delegate now"
                # directive is immediate; loss risk is covered by the stalled
                # scan / watchdog.
                discarded_keys.add(event.get("_key", ""))
            elif branch.startswith("impl/") and conclusion == "success":
                parent_issue = issue  # fallback to PR number
                try:
                    pr_body = subprocess.run(
                        ["gh", "pr", "view", str(issue), "--json", "body", "--jq", ".body"],
                        capture_output=True, text=True, timeout=10
                    ).stdout.strip()
                    m = re.search(r'(?:Closes|parent|Parent)\s*#(\d+)', pr_body)
                    if m:
                        parent_issue = int(m.group(1))
                except Exception:
                    pass
                # ── Block gate: skip review if PR or parent issue is blocked ──
                # status/blocked means the review agent previously found pre-existing
                # failures on main and deliberately blocked this PR. Do NOT re-spawn
                # review until the block is lifted (main tests pass → stalled scan
                # removes status/blocked and triggers update-branch).
                pr_num = int(issue)
                if _is_pr_blocked(pr_num) or _parent_issue_blocked(pr_num):
                    discarded_keys.add(event.get("_key", ""))
                    continue
                output_lines.append(
                    f"SPAWN: review,issue={parent_issue},"
                    f"pr={issue},branch={branch},conclusion={conclusion}"
                )
                # One-shot consumption (see self-correct SPAWN note above).
                discarded_keys.add(event.get("_key", ""))
            else:
                # Non-impl branch or unknown conclusion — let LLM decide
                output_lines.append(
                    f"P1: check_run.completed,issue={issue},"
                    f"branch={branch},conclusion={conclusion}"
                )
        elif etype == "issues.labeled":
            label = event.get("label", "")
            stage_map = {
                "workflow/available": "research",   # picker label → start research
                "workflow/research": "research",
                "workflow/plan": "plan",
                "workflow/implement": "implement",
                "workflow/self-correct": "self-correct",
            }
            stage = stage_map.get(label)
            if stage:
                # ── Dependency check ──
                # For workflow/available, check if the issue has unresolved
                # dependencies before allowing research phase to start.
                if label == "workflow/available":
                    issue_int = int(issue) if not isinstance(issue, int) else issue
                    unresolved = _has_unresolved_dependencies(issue_int)
                    if unresolved:
                        dep_str = ",".join(
                            f"#{d['issue']}({d['type']})" for d in unresolved
                        )
                        output_lines.append(
                            f"BLOCKED: issue={issue_int},depends-on={dep_str}"
                        )
                        continue
                # Dedup: check if a PR already exists for this stage+issue
                # before generating SPAWN (prevents redundant re-spawns).
                issue_int = int(issue) if not isinstance(issue, int) else issue
                if _pr_exists_for_issue(stage, issue_int):
                    # PR already exists — skip spawn, let flow continue via PR.
                    # Clean up from pending to avoid re-processing.
                    event_key = event.get("_key", "")
                    if event_key:
                        discarded_keys.add(event_key)
                    continue
                # Map raw label → LLM-expected label in SPAWN output
                # workflow/available → workflow/research (picker sets available,
                # but LLM prompt expects the phase label for routing)
                spawn_label_map = {
                    "workflow/available": "workflow/research",
                }
                spawn_label = spawn_label_map.get(label, label)
                spawn_line = f"SPAWN: {stage},issue={issue},label={spawn_label}"
                # ── Cost governance (P4b): implement after repeated self-correct
                # cycles burns the most tokens. Force depth=light beyond the
                # threshold so the implement agent skips deep TASKS docs and
                # keeps the diff minimal.
                if stage == "implement":
                    try:
                        comments_raw = gh(
                            "issue", "view", str(issue_int),
                            "--json", "comments", "--jq", ".comments"
                        )
                        if comments_raw:
                            import json as _json
                            comments = _json.loads(comments_raw)
                            cycles = count_self_correct_cycles(comments)
                            effective = depth_for_issue(cycles)
                            if effective != "standard":
                                spawn_line += f",depth={effective}"
                    except Exception:
                        pass  # budget check is best-effort; never block the spawn
                # ── Local-e2e context enrichment (2026-07-31) ──
                # A workflow/self-correct label WITHOUT a pending check_run(failure)
                # event means the review agent flagged the issue after a LOCAL e2e
                # failure (CI is green — the label is the only trigger; a CI-driven
                # self-correct always arrives as check_run.completed(failure), which
                # outranks the label in the per-issue group and is handled above).
                # Attach the impl PR context + source so the self-correct agent
                # knows which PR to fix and the cycle is attributable.
                if stage == "self-correct":
                    try:
                        pr_json = gh(
                            "pr", "list",
                            "--search", f"head:impl/{issue_int}",
                            "--json", "number,headRefName",
                            "--jq", ".[0]",
                        )
                        # Real gh --jq ".[0]" prints the object (or "null").
                        # Defensive: also accept an array or None.
                        if pr_json and pr_json != "null":
                            import json as _json
                            pr_info = _json.loads(pr_json)
                            if isinstance(pr_info, list):
                                pr_info = pr_info[0] if pr_info else None
                            if isinstance(pr_info, dict):
                                spawn_line += (
                                    f",pr={pr_info.get('number', issue_int)}"
                                    f",branch={pr_info.get('headRefName', '')}"
                                    ",source=local-e2e"
                                )
                    except Exception:
                        pass  # best-effort enrichment — bare label spawn stays valid
                output_lines.append(spawn_line)
                # One-shot consumption (see check_run SPAWN note above).
                discarded_keys.add(event.get("_key", ""))
            else:
                output_lines.append(
                    f"P2: issues.labeled,issue={issue},label={label}"
                )

    # Re-write pending file if staleness guard discarded additional events.
    # Step 6 above wrote the file based on initial discarded_keys only;
    # the staleness guard added more keys but never persisted them —
    # causing the same stale events to be re-processed every tick.
    if discarded_keys:
        remaining = [e for e in events if e.get("_key", "") not in discarded_keys]
        write_pending(remaining)

    # SPAWN lines must come first — LLM reads top-to-bottom
    output_lines.sort(key=lambda l: (0 if l.startswith("SPAWN:") else 1,
                                     0 if "review" in l or "self-correct" in l else
                                     1 if l.startswith("SPAWN:") else 2))
    return output_lines


def _quick_stalled_scan():
    """Deterministic stalled PR scan. Outputs explicit STALLED commands.
    
    Runs in <5 seconds (gh API only, no godot, no file reads).
    Returns list of STALLED lines for the cron agent to execute.
    """
    cmds = []
    
    # 1. Check for stalled research/plan PRs (open + mergeable → merge)
    for prefix in ("research/", "plan/"):
        raw = gh("pr", "list", "--state", "open",
                 "--search", f"head:{prefix} in:headRefName",
                 "--json", "number,headRefName,mergeable", "--limit", "10")
        if not raw:
            continue
        try:
            prs = json.loads(raw)
        except json.JSONDecodeError:
            continue
        for pr in prs:
            if pr.get("mergeable") == "MERGEABLE":
                cmds.append(
                    f"STALLED: merge-pr,pr={pr['number']},"
                    f"branch={pr['headRefName']}"
                )

    # 2. Check for stalled impl/* PRs
    raw = gh("pr", "list", "--state", "open",
             "--search", "head:impl/ in:headRefName",
             "--json", "number,headRefName,labels", "--limit", "10")
    if raw:
        try:
            prs = json.loads(raw)
        except json.JSONDecodeError:
            prs = []
        for pr in prs:
            labels = [l["name"] for l in pr.get("labels", [])]
            branch = pr["headRefName"]
            pr_num = pr["number"]
            
            if "status/blocked" in labels:
                # Blocked PR — needs unblock check (run main tests)
                cmds.append(
                    f"STALLED: check-unblock,pr={pr_num},branch={branch}"
                )
            else:
                # Normal impl PR — check if CI green, spawn review if so
                cmds.append(
                    f"STALLED: check-review,pr={pr_num},branch={branch}"
                )
    
    return cmds


def main():
    try:
        cfg = read_workflow_config()
        
        # Pause check
        if is_paused():
            _audit(tick="end", in_window=False, paused=True, output="[PAUSED]")
            return

        # Flush per-tick caches ──
        # These caches are valid only within one tick.
        # The gh() call cache (30s TTL) is separate and persists
        # for cross-call dedup within the tick.
        _ISSUES_CACHE.clear()
        _BODY_CACHE.clear()
        
        # Window entry detection: if we just entered work hours, reconcile + pick
        was_outside = False
        try:
            state_file = os.path.expanduser("~/.hermes/.workflow-state.json")
            if os.path.exists(state_file):
                with open(state_file) as f:
                    state = json.load(f)
                was_outside = state.get("last_hour", -1) != datetime.datetime.now().hour
        except Exception:
            pass
        
        in_window = _time_in_window(cfg)
        if in_window and was_outside:
            # Just entered work hours → health check
            hc = health_check()
            print(hc, file=sys.stderr)
            reconcile()
            pick_next_issue()
        
        # ── Check-run reconcile (P3b): slow-cadence webhook-loss fallback ──
        # Runs every 5th tick (~5 min) regardless of work hours, so a lost
        # check_run.completed event is re-emitted even outside the window.
        try:
            tick_count = int(_read_reconcile_state().get("_ticks", 0))
        except Exception:
            tick_count = 0
        if tick_count % 5 == 0:
            reconcile_check_runs()
        _write_reconcile_state({**_read_reconcile_state(), "_ticks": tick_count + 1})
        
        # Save current hour for window entry detection
        try:
            with open(os.path.expanduser("~/.hermes/.workflow-state.json"), "w") as f:
                json.dump({"last_hour": datetime.datetime.now().hour, "window_open": in_window}, f)
        except Exception:
            pass

        # ── Idle fast path: pending empty + no active workflow issues → SILENT ──
        # When all issues are done and no events are queued, skip all expensive
        # operations (reconcile, picker, preprocess, stalled scan). Only cost:
        # 1 gh issue list call + 1 local file read per tick.
        if in_window and not is_paused():
            events = read_pending()
            if not events:
                issues = _ensure_issues_cache()
                active_labels = {
                    "workflow/available", "workflow/research",
                    "workflow/plan", "workflow/implement",
                    "workflow/self-correct",
                }
                has_active = any(
                    any(l.get("name", "") in active_labels
                        for l in iss.get("labels", []))
                    for iss in issues
                )
                # A backlog-only repo is NOT idle: the picker must run to
                # promote backlog → available. Without this check, backlog
                # issues never enter the pipeline (canary #358, 2026-08-10).
                if not has_active:
                    has_active = any(
                        any(l.get("name", "") == "workflow/backlog"
                            for l in iss.get("labels", []))
                        for iss in issues
                    )
                if not has_active:
                    # Fast-path return must STILL write the audit record —
                    # otherwise the watchdog/dashboard sees a silent gap and
                    # cannot distinguish "idle" from "dead tick" (canary #358,
                    # 2026-08-10: audit stalled at 17:58 while cron kept
                    # running empty ticks).
                    _audit(tick="end", in_window=in_window, paused=False,
                           silent_fast_path=True, output="[SILENT]")
                    print("[SILENT]")
                    return

        # Outside hours → only process pipeline events, block picker + available
        if not in_window:
            # Only process pipeline events via standard preprocess
            pass  # fall through to preprocess with proper filtering
        
        # Pick from backlog FIRST (fast, gh API only for picker)
        # Then reconcile + preprocess (may be slower)
        if in_window and not is_paused():
            pick_next_issue()
        
        # Reconcile every in-window tick
        if in_window:
            reconcile()
        
        lines = preprocess()
        
        # Filter lines by window/pause state
        if not in_window or is_paused():
            # Remove SPAWN for available/since it's blocked outside hours
            filtered = []
            for line in lines:
                if line.startswith("SPAWN:") and "workflow/available" in line:
                    continue
                if line.startswith("SPAWN:"):
                    filtered.append(line)
                elif line.startswith("BLOCKED:"):
                    filtered.append(line)
                elif line.startswith("P1:") or line.startswith("P2:"):
                    filtered.append(line)
            lines = filtered
        
        # Cap: phase agents (research/plan/implement) at MAX_PHASE_SLOTS
        # Review and self-correct don't count (reserved slots).
        # First count what's already running on GitHub.
        active_phase = _count_active_phase_agents()
        available_phase_slots = max(0, MAX_PHASE_SLOTS - active_phase)
        lines_pre_cap = lines  # P2 audit: how many lines before slot capping
        
        phase_count = 0
        capped = []
        for line in lines:
            if line.startswith("SPAWN: review") or line.startswith("SPAWN: self-correct"):
                # Reserved slots — always pass
                capped.append(line)
            elif line.startswith("SPAWN:"):
                # Phase agent — count against available phase slots
                is_phase = False
                for ph in ("research", "plan", "implement"):
                    if line.startswith(f"SPAWN: {ph}"):
                        is_phase = True
                        if phase_count < available_phase_slots:
                            phase_count += 1
                            capped.append(line)
                        # else: silently drop, no slot available
                        break
                if not is_phase:
                    # Unknown SPAWN type — let through
                    capped.append(line)
            else:
                capped.append(line)
        lines = capped
        
        # ── Audit (P2): record tick outcome for watchdog/dashboard ──
        _audit(
            tick="end",
            in_window=in_window,
            paused=is_paused(),
            raw_lines=len(lines_pre_cap),
            spawn_lines=sum(1 for l in lines if l.startswith("SPAWN:")),
            blocked_lines=sum(1 for l in lines if l.startswith("BLOCKED:")),
            stalled_lines=sum(1 for l in lines if l.startswith("STALLED:")),
            phase_slots=available_phase_slots,
            active_phase=active_phase,
            output="\n".join(lines)[:200] if lines else "[SILENT]",
        )
        
        if lines:
            print("\n".join(lines))
            
            # If there was a status/done event, trigger picker to fill slot
            if in_window and any("status/done" in l for l in lines):
                pick_next_issue()
        else:
            # No pending events → run quick stalled scan + picker
            if in_window and not is_paused():
                pick_next_issue()
                stalled = _quick_stalled_scan()
                if stalled:
                    print("\n".join(stalled))
                else:
                    print("[SILENT]")
            else:
                print("[SILENT]")
    except Exception as e:
        _audit(tick="end", in_window=False, error=str(e)[:200], output="[ERROR]")
        print(f"[event-processor error: {e}]", file=sys.stderr)


def check_webhook_connectivity() -> bool:
    """Ping GitHub webhook, return True if 200."""
    try:
        token = os.environ.get("GH_TOKEN", "")
        if not token:
            return False
        url = WEBHOOK_BASE
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}", "User-Agent": "Hermes"})
        with urllib.request.urlopen(req, timeout=10) as r:
            hooks = json.loads(r.read().decode())
        if not hooks:
            return False
        hid = hooks[0]["id"]
        ping_req = urllib.request.Request(
            f"{WEBHOOK_BASE}/{hid}/pings",
            method="POST", headers={"Authorization": f"Bearer {token}", "User-Agent": "Hermes"})
        urllib.request.urlopen(ping_req, timeout=10)
        import time as _t; _t.sleep(2)
        del_req = urllib.request.Request(
            f"{WEBHOOK_BASE}/{hid}/deliveries?per_page=1",
            headers={"Authorization": f"Bearer {token}", "User-Agent": "Hermes"})
        with urllib.request.urlopen(del_req, timeout=10) as r:
            dl = json.loads(r.read().decode())
        return bool(dl and dl[0].get("status") == "OK")
    except Exception:
        return False


def health_check() -> str:
    """One-line health check. Returns e.g. [HEALTH] gateway=200 ngrok=UP webhook=OK"""
    parts = []
    try:
        with urllib.request.urlopen("http://127.0.0.1:8644/", timeout=3) as r:
            parts.append(f"gateway={r.status}")
    except: parts.append("gateway=DOWN")
    try:
        with urllib.request.urlopen("http://127.0.0.1:4040/api/tunnels", timeout=3) as r:
            d = json.loads(r.read().decode())
            parts.append("ngrok=UP" if d.get("tunnels") else "ngrok=NOPATH")
    except: parts.append("ngrok=DOWN")
    try:
        with urllib.request.urlopen("http://127.0.0.1:18765/health", timeout=3) as r:
            parts.append(f"opencode={r.status}")
    except: parts.append("opencode=DOWN")
    parts.append("webhook=OK" if check_webhook_connectivity() else "webhook=FAIL")
    return f"[HEALTH] {' '.join(parts)}"


if __name__ == "__main__":
    main()
