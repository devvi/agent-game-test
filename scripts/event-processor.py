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

# gh() call cache — avoids redundant API calls within a single tick
_GH_CACHE: dict = {}
_GH_CACHE_TTL = 30

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

# ── Workflow config defaults ────────────────────────────────────
DEFAULT_CONFIG = {
    "enabled": True,
    "work_start_hour": 8,
    "work_end_hour": 22,
    "preset": "daytime",
}

# ── Presets ─────────────────────────────────────────────────────
# Presets can define either:
#   work_start_hour + work_end_hour — single contiguous window
#   work_windows: [[start, end], ...] — multiple non-contiguous windows
WORK_HOUR_PRESETS = {
    "daytime": {"work_start_hour": 8, "work_end_hour": 22},
    "night-owl": {"work_start_hour": 23, "work_end_hour": 8},
    "always": {"work_start_hour": 0, "work_end_hour": 24},
    # DeepSeek peak/off-peak pricing (UTC+8):
    #   Peak (2x): 9-12, 14-18
    #   Valley (1x): 0-9, 12-14, 18-24
    "best-deepseek": {"work_windows": [[0, 9], [12, 14], [18, 24]]},
}


def read_workflow_config() -> dict:
    """Read workflow config, falling back to env vars then defaults.
    If a preset is named, its hours are applied as defaults before
    file-specified hours override them."""
    config = dict(DEFAULT_CONFIG)
    try:
        with open(WORKFLOW_CONFIG) as f:
            config.update(json.load(f))
    except (FileNotFoundError, json.JSONDecodeError, IOError):
        pass
    # Apply preset hours if a preset is set (but allow explicit hours to override)
    preset_name = config.get("preset")
    if preset_name and preset_name in WORK_HOUR_PRESETS:
        preset = WORK_HOUR_PRESETS[preset_name]
        # Only apply preset hours if no explicit hours set in file
        if "work_start_hour" not in config or config["work_start_hour"] == DEFAULT_CONFIG["work_start_hour"]:
            if "work_windows" in preset:
                config["work_windows"] = preset["work_windows"]
            elif "work_start_hour" in preset:
                config["work_start_hour"] = preset["work_start_hour"]
                config["work_end_hour"] = preset.get("work_end_hour", DEFAULT_CONFIG["work_end_hour"])
    # Env vars override file config
    if "WORK_START_HOUR" in os.environ:
        config["work_start_hour"] = int(os.environ["WORK_START_HOUR"])
    if "WORK_END_HOUR" in os.environ:
        config["work_end_hour"] = int(os.environ["WORK_END_HOUR"])
    if "WORKFLOW_DISABLED" in os.environ:
        config["enabled"] = not os.environ["WORKFLOW_DISABLED"].lower() in ("1", "true")
    return config


def is_work_hours(cfg: dict = None) -> bool:
    """Check if current time is within configured work hours."""
    if cfg is None:
        cfg = read_workflow_config()
    if not cfg.get("enabled", True):
        return False
    return _time_in_window(cfg)


def _time_in_window(cfg: dict) -> bool:
    """Pure time check — does NOT check enabled flag.
    
    Supports two modes:
    1. work_windows: list of [start, end] ranges (for non-contiguous windows)
    2. work_start_hour/work_end_hour: single contiguous range (with wrap support)
    """
    hour = datetime.datetime.now().hour
    # Mode 1: multiple windows (e.g. best-deepseek valley periods)
    windows = cfg.get("work_windows")
    if windows:
        for start, end in windows:
            if start <= end:
                if start <= hour < end:
                    return True
            else:
                # Wrapping window (e.g. 23-8)
                if hour >= start or hour < end:
                    return True
        return False
    # Mode 2: single contiguous range
    start = cfg.get("work_start_hour", 8)
    end = cfg.get("work_end_hour", 22)
    if start <= end:
        return start <= hour < end
    else:
        # Wrapping: e.g. 14-2 means afternoon to late night
        return hour >= start or hour < end


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


# ── Priority labels ───────────────────────────────────────────
PRIORITY_LABEL_ORDER = [
    "priority/critical",
    "priority/high",
    "priority/medium",
    "priority/low",
]


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

# ── Priority definitions ───────────────────────────────────────────
# Lower number = higher priority
PRIORITY = {
    "check_run.completed": 1,  # CI finished — most urgent
    "issues.labeled": 2,       # Phase start — important
}
PRIORITY_MAX = 99  # For events that should be discarded


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


def _event_action(event):
    """Extract action from event _key (e.g., 'check_run.completed' from 'check_run.completed#154')."""
    key = event.get("_key", "")
    return key.split("#")[0]  # "check_run.completed"


def event_priority(event):
    """Return numeric priority for an event. Lower = higher priority."""
    etype = event.get("type", "")
    action = _event_action(event)

    # check_run.completed — P1 (urgent)
    # Only actionable if branch and conclusion are present
    if etype == "check_run" and action == "check_run.completed":
        branch = event.get("branch", "")
        conclusion = event.get("conclusion", "")
        if branch and conclusion in ("success", "failure"):
            return PRIORITY["check_run.completed"]
        # has some data but incomplete — still forward to LLM for fallback query
        if branch or conclusion:
            return PRIORITY["check_run.completed"] + 1
        # completely empty — treat as discard
        return PRIORITY_MAX

    # issues.labeled — P2 (phase start)
    if etype == "issues.labeled":
        label = event.get("label", "")
        if label.startswith("workflow/"):
            # lock labels are coordination, not workflow phases
            if label.startswith("workflow/lock-"):
                return PRIORITY_MAX
            return PRIORITY["issues.labeled"]
        # non-workflow labels — not actionable
        return PRIORITY_MAX

    # Everything else: pull_request.*, check_run.created, check_run.skipped,
    # issues.opened, issues.closed, issues.unlabeled, etc.
    return PRIORITY_MAX


def should_discard(event):
    """Return True if this event should be REMOVED from the pending file."""
    return event_priority(event) == PRIORITY_MAX


def validate_check_run(event):
    """Surface-level validation: branch exists, conclusion is actionable.
    Returns True if the event is potentially actionable (LLM still does
    final validation via gh)."""
    etype = event.get("type", "")
    action = _event_action(event)
    if etype != "check_run" or action != "check_run.completed":
        return True  # not a check_run, skip validation
    branch = event.get("branch", "")
    conclusion = event.get("conclusion", "")
    if not branch:
        return False  # can't determine which PR this is for
    if conclusion not in ("success", "failure"):
        return False  # not actionable
    return True


# ── Stage → branch prefix mapping ─────────────────────────────────
STAGE_BRANCH_PREFIX = {
    "research": "research/",
    "plan": "plan/",
    "implement": "impl/",
    "self-correct": "self-correct/",
}


def gh(*args: str) -> str:
    """Run gh command, return stdout. Returns empty string on error.
    Results cached for 30s within a single tick."""
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


def parse_dependencies(body: str) -> list[dict]:
    """Parse ## Dependencies section from issue body.

    Matches:
      Depends on: #42              → full dependency
      Depends on (design): #49     → design-only dependency

    Returns [{"issue": 42, "type": "full"}, {"issue": 49, "type": "design"}]
    """
    deps = []
    in_deps_section = False
    for line in body.split("\n"):
        stripped = line.strip()
        # Detect ## Dependencies or ## 前置依赖 heading (case-insensitive)
        if re.match(r'^#{2,3}\s+(?:Dependencies|前置依赖)', stripped, re.IGNORECASE):
            in_deps_section = True
            continue
        # Exit section at next heading (## or deeper)
        if in_deps_section and re.match(r'^#{2,}\s', stripped):
            break
        if not in_deps_section:
            continue
        # Match: Depends on: #42  or  Depends on (design): #49
        m = re.match(
            r'Depends on\s*(?:\((\w+)\))?\s*:\s*#(\d+)',
            stripped, re.IGNORECASE
        )
        if m:
            dep_type = m.group(1).lower() if m.group(1) else "full"
            if dep_type not in ("full", "design"):
                dep_type = "full"  # unknown type → treat as full
            deps.append({"issue": int(m.group(2)), "type": dep_type})
        # Fallback: bare #N references inside deps section (Chinese format: #42, #43)
        elif re.search(r'#\d+', stripped):
            refs = re.findall(r'#(\d+)', stripped)
            for ref in refs:
                if not any(d["issue"] == int(ref) for d in deps):
                    deps.append({"issue": int(ref), "type": "full"})
    return deps


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
    On gh error, returns False (conservative: allow event through).
    """
    raw = gh("pr", "view", str(pr_num), "--json", "state")
    if not raw:
        return False
    try:
        state = json.loads(raw).get("state", "")
        return state in ("MERGED", "CLOSED")
    except (json.JSONDecodeError, KeyError):
        return False


def _is_issue_closed(issue_num: int) -> bool:
    """Check if an issue is already closed.
    
    Returns True if closed (event is stale). On gh error, returns False.
    """
    raw = gh("issue", "view", str(issue_num), "--json", "state")
    if not raw:
        return False
    try:
        return json.loads(raw).get("state", "") == "CLOSED"
    except (json.JSONDecodeError, KeyError):
        return False


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


WORKDIR = os.path.expanduser("~/workspace/.pda/perfect-dev-agent-workflow")

# ── Game Environment ─────────────────────────────────────────
MANIFEST_PATH = os.path.join(WORKDIR, "game-env", "manifest.yaml")

def _load_manifest() -> dict:
    """Load game environment manifest. Falls back to snake defaults."""
    default = {
        "engine": {"name": "web", "runner": "node"},
        "source": {"dir": "public/src/"},
        "test": {"dir": "tests/", "framework": "vitest"},
        "code_gen": {"language": "javascript"},
        "git": {"default_branch": "master"},
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
DEFAULT_BRANCH = MANIFEST.get("git", {}).get("default_branch", "master")

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

# ── Distributed lock (multi-agent coordination) ────────────────────
# Each cron instance has a unique label (workflow/lock-{id}).
# Lock is acquired before SPAWN, released by the spawned agent.
# TTL = 300s; expired locks are cleaned by reconcile().
INSTANCE_ID = os.environ.get("WORKFLOW_INSTANCE_ID", "pi").lower()
LOCK_LABEL = f"workflow/lock-{INSTANCE_ID}"
OTHER_LOCK_LABEL = "workflow/lock-pi" if INSTANCE_ID == "mbot" else "workflow/lock-mbot"
LOCK_TTL = 300  # 5 minutes
LOCK_STATE_FILE = os.path.expanduser("~/.hermes/lock-state.json")

def _read_lock_state() -> dict:
    if os.path.exists(LOCK_STATE_FILE):
        try:
            with open(LOCK_STATE_FILE) as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            return {}
    return {}

def _write_lock_state(state: dict):
    with open(LOCK_STATE_FILE, "w") as f:
        json.dump(state, f)

def _try_acquire_lock(issue_num: int) -> bool:
    """Try to acquire a distributed lock on the given issue.
    Returns True if lock acquired, False if held by another instance.
    """
    now = time.time()
    
    # Fetch current issue labels
    raw = gh("issue", "view", str(issue_num), "--json", "labels")
    if not raw:
        # gh unavailable — grant lock to avoid deadlock.
        # A duplicate spawn is better than a permanent stall.
        return True
    try:
        labels = [l["name"] for l in json.loads(raw).get("labels", [])]
    except (json.JSONDecodeError, KeyError):
        return False
    
    state = _read_lock_state()
    locked_at = state.get(str(issue_num), 0)
    
    # Check if other instance holds a live lock
    if OTHER_LOCK_LABEL in labels:
        if locked_at and (now - locked_at) < LOCK_TTL:
            return False  # Other instance holds a valid lock
        # Lock expired — clean it
        try:
            subprocess.run(
                ["gh", "issue", "edit", str(issue_num),
                 "--remove-label", OTHER_LOCK_LABEL],
                check=True, capture_output=True, timeout=10
            )
        except: pass
        del state[str(issue_num)]
    
    # Add our own lock label
    try:
        subprocess.run(
            ["gh", "issue", "edit", str(issue_num),
             "--add-label", LOCK_LABEL],
            check=True, capture_output=True, timeout=10
        )
    except subprocess.CalledProcessError:
        return False
    
    # Post-lock confirmation: if both locks exist (race), keep ours — the lock
    # state file on our side is authoritative. If we already proceeded to SPAWN,
    # duplicate output is handled by downstream dedup.
    # The other instance's reconcile() will clean up its redundant lock later.
    
    # Record lock time
    state[str(issue_num)] = now
    _write_lock_state(state)
    return True

def _release_lock(issue_num: int):
    """Release the distributed lock for this issue."""
    state = _read_lock_state()
    if str(issue_num) in state:
        del state[str(issue_num)]
        _write_lock_state(state)
    try:
        subprocess.run(
            ["gh", "issue", "edit", str(issue_num),
             "--remove-label", LOCK_LABEL],
            check=True, capture_output=True, timeout=10
        )
    except: pass

def _clean_expired_locks():
    """Remove expired lock labels and state (called by reconcile)."""
    raw = gh("issue", "list", "--state", "open", "--label", LOCK_LABEL, "--json", "number")
    if not raw:
        return
    try:
        locked_issues = json.loads(raw)
    except json.JSONDecodeError:
        return
    state = _read_lock_state()
    changed = False
    for iss in locked_issues:
        n = str(iss["number"])
        locked_at = state.get(n, 0)
        if locked_at and (time.time() - locked_at) >= LOCK_TTL:
            try:
                subprocess.run(
                    ["gh", "issue", "edit", n, "--remove-label", LOCK_LABEL],
                    check=True, capture_output=True, timeout=10
                )
            except: pass
            if n in state:
                del state[n]
                changed = True
    if changed:
        _write_lock_state(state)

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
                print(f"SPAWN: plan,issue={n},label=workflow/plan")
        elif "workflow/implement" in labels:
            existing = gh("pr", "list", "--state", "all",
                          "--search", f"head:impl/{n}- in:headRefName",
                          "--json", "number,state",
                          "--jq", "length")
            if existing is None or int(existing) == 0:
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
                    "repo": "devvi/agent-game-test",
                    "ts": time.time(),
                    "label": label,
                })
    
    if events:
        write_pending(events)


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
                output_lines.append(
                    f"SPAWN: {stage},issue={issue},label={spawn_label}"
                )
            else:
                output_lines.append(
                    f"P2: issues.labeled,issue={issue},label={label}"
                )

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
            return

        # ── Flush per-tick caches ──
        # These caches are valid only within one tick.
        # The gh() call cache (30s TTL) is separate and persists
        # for cross-call dedup within the tick.
        _ISSUES_CACHE.clear()
        _BODY_CACHE.clear()

        # Clean expired locks unconditionally (every tick, regardless of work hours)
        _clean_expired_locks()
        
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
        
        # Save current hour for window entry detection
        try:
            with open(os.path.expanduser("~/.hermes/.workflow-state.json"), "w") as f:
                json.dump({"last_hour": datetime.datetime.now().hour, "window_open": in_window}, f)
        except Exception:
            pass
        
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
        
        # Acquire distributed locks for phase SPAWN lines
        # (review/self-correct don't need locks — they're fast operations)
        locked_lines = []
        for line in lines:
            if line.startswith("SPAWN: review") or line.startswith("SPAWN: self-correct"):
                locked_lines.append(line)
                continue
            if line.startswith("SPAWN:"):
                # Extract issue number from SPAWN
                m = re.search(r'issue=(\d+)', line)
                if m:
                    issue_num = int(m.group(1))
                    if _try_acquire_lock(issue_num):
                        locked_lines.append(line)
                    # else: skip — other instance processing this issue
                else:
                    locked_lines.append(line)
            else:
                locked_lines.append(line)
        lines = locked_lines
        
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
        print(f"[event-processor error: {e}]", file=sys.stderr)


def check_webhook_connectivity() -> bool:
    """Ping GitHub webhook, return True if 200."""
    try:
        token = os.environ.get("GH_TOKEN", "")
        if not token:
            return False
        url = "https://api.github.com/repos/devvi/agent-game-test/hooks"
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}", "User-Agent": "Hermes"})
        with urllib.request.urlopen(req, timeout=10) as r:
            hooks = json.loads(r.read().decode())
        if not hooks:
            return False
        hid = hooks[0]["id"]
        ping_req = urllib.request.Request(
            f"https://api.github.com/repos/devvi/agent-game-test/hooks/{hid}/pings",
            method="POST", headers={"Authorization": f"Bearer {token}", "User-Agent": "Hermes"})
        urllib.request.urlopen(ping_req, timeout=10)
        import time as _t; _t.sleep(2)
        del_req = urllib.request.Request(
            f"https://api.github.com/repos/devvi/agent-game-test/hooks/{hid}/deliveries?per_page=1",
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
