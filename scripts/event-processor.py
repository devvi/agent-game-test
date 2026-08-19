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
  STALLED: merge-pr,pr=N,branch=...    → non-impl PR CI done, merge it (2026-08-13)
  SPAWN: <agent>,issue=N,...           → spawn directive
  P2: issues.labeled,issue=N,...      → labeled events follow

File modification:
  - REMOVES from file: pull_request.*, check_run.created, any non-actionable,
    check_run.completed on non-impl (research/plan) branches (2026-08-13:
    consumed as STALLED: merge-pr or dropped; NEVER emitted as P1)
  - KEEPS in file: check_run.completed (impl/*), issues.labeled (for LLM to process)

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

# ── Develop-mode structured logging (2026-08-15) ─────────────────
# 2026-08-15 重构失败教训: 每次诊断都靠猜(时间线重建/grep 推断),
# 没有系统性可观测性。引入 append-only JSONL event log:
#   ~/.hermes/workflow-events.jsonl  ← 每个 action 一行 JSON(核心)
# 写入时机: action 发生时立即写(不是 tick 末汇总) — crash 后最后
# 一条 log 就是崩溃点, 不丢。
# develop 模式(workflow-config "mode": "develop")额外输出 stdout
# 一行摘要(人眼可读); production 只写 error/warn 级。
_DEVLOG_PATH = os.path.expanduser("~/.hermes/workflow-events.jsonl")
_DEVLOG_MAX = 5 * 1024 * 1024  # 5MB rotation
_DEVLOG_KEEP = 3


def _workflow_mode() -> str:
    """Read workflow-config mode: 'develop' or 'production' (default)."""
    try:
        cfg = json.load(open(os.path.expanduser("~/.hermes/workflow-config.json")))
        return cfg.get("mode", "production")
    except Exception:
        return "production"


def _devlog(event: str, level: str = "info", **fields) -> None:
    """Append one JSON line to the devlog (always for info+, stdout summary
    only in develop mode). Called at action time, never at tick end."""
    import time as _t
    rec = {"ts": _t.strftime("%Y-%m-%dT%H:%M:%S"), "event": event, "level": level}
    rec.update(fields)
    try:
        os.makedirs(os.path.dirname(_DEVLOG_PATH), exist_ok=True)
        with open(_DEVLOG_PATH, "a") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
        # rotation: >5MB → shift .1/.2/.3
        if os.path.getsize(_DEVLOG_PATH) > _DEVLOG_MAX:
            for i in range(_DEVLOG_KEEP, 0, -1):
                src = f"{_DEVLOG_PATH}.{i-1}" if i > 1 else _DEVLOG_PATH
                dst = f"{_DEVLOG_PATH}.{i}"
                if os.path.exists(src):
                    os.replace(src, dst)
    except Exception:
        pass  # devlog is best-effort; never break the pipeline
    if _workflow_mode() == "develop":
        _sum = " ".join(f"{k}={v}" for k, v in fields.items())
        print(f"[DEV] {event} {_sum}")


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


# ── Closed-issues cache (2026-08-13) ──────────────────────────────
# `gh issue list --state open` only sees open issues. A dependency missing
# from that cache is CLOSED — but "closed" ≠ "resolved" (status/done).
# #384/#390 were closed early WITHOUT status/done while their code only
# landed in the still-unmerged #444; treating them as resolved let #393
# advance on un-landed work. Lazy-fetch closed issues once per tick to
# distinguish legit completion from suspicious early closure.
_CLOSED_ISSUES_CACHE: dict = {}


def _ensure_closed_issues_cache(force_refresh=False) -> dict:
    """Map of closed issue number → label names (cached, 30s TTL)."""
    now = time.time()
    cached = _CLOSED_ISSUES_CACHE.get("issues")
    fetched_at = _CLOSED_ISSUES_CACHE.get("fetched_at", 0)
    if not force_refresh and cached and (now - fetched_at) < _GH_CACHE_TTL:
        return cached
    result = {}
    raw = gh("issue", "list", "--state", "closed",
             "--json", "number,labels", "--limit", "100")
    if raw:
        try:
            for iss in json.loads(raw):
                result[iss["number"]] = [l.get("name", "") for l in iss.get("labels", [])]
        except (json.JSONDecodeError, KeyError):
            pass
    _CLOSED_ISSUES_CACHE["issues"] = result
    _CLOSED_ISSUES_CACHE["fetched_at"] = now
    return result


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
            # 2026-08-13: closed ≠ resolved. A closed dep WITHOUT status/done
            # (or status/human-review 定稿) is a suspicious early closure
            # (e.g. #384/#390 closed while their code only landed in the
            # unmerged #444). Block dependents — do NOT advance on un-landed
            # work. This closes the "CLOSED Dependency = Resolved" hole
            # documented in event-processor-dependency-parsing.
            closed_labels = _ensure_closed_issues_cache().get(dep_num, [])
            if "status/done" in closed_labels or "status/human-review" in closed_labels:
                continue  # legitimately completed
            unresolved.append({**dep, "closed_without_done": True})
            continue
        
        # Got cached data — check labels
        dep_labels = [l.get("name","") for l in cached.get("labels",[])]
        
        # status/done = resolved
        if "status/done" in dep_labels:
            continue
        
        # status/human-review = taste-draft 草稿已 merge，等待人定稿 —
        # human Issue 不进依赖链（v4 队列模式，2026-08-11）。
        # 语义: 草稿 merge 即依赖满足，下游机械 Issue 不等人的定稿速度，
        # 定稿后由用户增量替换。
        if "status/human-review" in dep_labels:
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


def _pr_matches_issue(pr: dict, issue: int) -> bool:
    """Client-side PR↔issue match: branch-prefix convention OR body/title
    reference. GitHub's `--search head:...` qualifier is unreliable
    (Patch 59, 2026-07-29: returns [] even for existing PRs), so all
    PR-exists checks must use this deterministic matcher instead."""
    head = pr.get("headRefName", "") or ""
    body = pr.get("body", "") or ""
    title = pr.get("title", "") or ""
    if f"/{issue}-" in head or f"/{issue}/" in head or head.endswith(f"/{issue}"):
        return True
    if re.search(rf"(?:Parent|Closes|parent)\s*#{issue}\b", body):
        return True
    if re.search(rf"\(\s*#{issue}\s*\)|\b#{issue}\b", title):
        return True
    return False


def _pr_exists_for_issue(stage: str, issue: int) -> bool:
    """Check if a GitHub PR already exists for this stage+issue combination.
    Returns True if a PR exists (SPAWN should be skipped).
    Uses deterministic client-side matching over `gh pr list --state all`
    (no --search qualifier — unreliable per Patch 59). The gh() 30s cache
    makes repeated calls within a tick cheap.
    On error (gh unavailable, timeout), returns False so spawn still happens."""
    prefix = STAGE_BRANCH_PREFIX.get(stage)
    if not prefix:
        return False
    raw = gh("pr", "list", "--state", "all",
             "--json", "number,headRefName,body,title,state",
             "--limit", "100")
    if not raw:
        return False
    try:
        prs = json.loads(raw)
    except json.JSONDecodeError:
        return False
    return any(_pr_matches_issue(p, issue) for p in prs)


WORKDIR = os.path.expanduser("~/workspace/agent-game-test")

# ── Game Environment ─────────────────────────────────────────
# 2026-08-19 (CI 修复): manifest 查找不再依赖 macOS 硬编码路径 — CI (ubuntu)
# 上 ~/workspace/agent-game-test 不存在 → _load_manifest() 走 fallback →
# ACTIVE_GAME 永远 mini-pong → picker 的 game= 断言全红 (pipeline-tests 自
# 08-18 16:27 连续红, E2E_RUNNER 同类 bug 2026-08-17 已修, 此处同样处理)。
# 推导顺序: __file__ (repo scripts/ 或 ~/.hermes/scripts/) → cwd → 硬编码兜底。
MANIFEST_PATH = os.path.join(WORKDIR, "game-env", "manifest.yaml")
for _cand in (
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "game-env", "manifest.yaml")),
    os.path.abspath(os.path.join(os.getcwd(), "game-env", "manifest.yaml")),
):
    if os.path.exists(_cand):
        MANIFEST_PATH = _cand
        break

def _load_manifest() -> dict:
    """Load game environment manifest. Falls back to project defaults.

    2026-08-18: 不再依赖 yaml 库 — 系统 python3 无 yaml, 旧逻辑 import yaml
    抛异常 → 永远返回 default → manifest 参数化(repo/分支/game.active)全部
    失效走 fallback。改为纯正则解析关键字段(够用且零依赖)。
    """
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
            txt = f.read()
        # 先试 yaml（venv 环境有）
        try:
            import yaml
            return {**default, **yaml.safe_load(txt)}
        except ImportError:
            pass
        # 纯正则 fallback：解析本项目用到的关键字段
        out: dict = dict(default)
        m = re.search(r"^repo:\s*(\S+)", txt, re.M)
        if m:
            out["project"] = {"repo": m.group(1)}
        m = re.search(r"^engine:\s*\n(?:.*\n)*?\s*name:\s*(\S+)", txt, re.M)
        if m:
            out["engine"] = {**out.get("engine", {}), "name": m.group(1)}
        m = re.search(r"^  default_branch:\s*(\S+)", txt, re.M)
        if m:
            out["git"] = {**out.get("git", {}), "default_branch": m.group(1)}
        # game.active + game.subprojects.<active>.path
        gm = re.search(r"^game:\s*$", txt, re.M)
        if gm:
            gblock = txt[gm.end():]
            am = re.search(r"active:\s*(\S+)", gblock[:200])
            if am:
                active = am.group(1)
                game_cfg: dict = {"active": active, "subprojects": {}}
                sm = re.search(r"subprojects:\s*\n(.*?)(?=\n\S|\Z)", gblock, re.S)
                if sm:
                    pm = re.search(
                        r"^\s*" + re.escape(active) + r":\s*\n(.*?)(?=\n\s{4}\S|\Z)",
                        sm.group(1), re.S | re.M)
                    if pm:
                        pm2 = re.search(r"path:\s*(\S+)", pm.group(1))
                        if pm2:
                            game_cfg["subprojects"][active] = {"path": pm2.group(1)}
                out["game"] = game_cfg
        # source.subprojects 列表
        sm2 = re.search(r"^  subprojects:\s*$", txt, re.M)
        if sm2:
            subs: list = []
            for line in txt[sm2.end():].splitlines():
                s = line.strip()
                if s.startswith("- "):
                    subs.append(s[2:].strip())
                elif s and not s.startswith("#"):
                    break
            if subs:
                out["source"] = {**out.get("source", {}), "subprojects": subs}
        return out
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

# ── 活跃游戏（2026-08-18, 一次一个游戏）──────────────────────────
# 读 manifest game.active；SPAWN 指令携带 game= 让 agent 明确为哪个游戏干活。
ACTIVE_GAME = (
    MANIFEST.get("game", {}).get("active")
    or MANIFEST.get("source", {}).get("subprojects", [""])[0]
    or "mini-pong"
)
ACTIVE_GAME_PATH = (
    MANIFEST.get("game", {}).get("subprojects", {})
    .get(ACTIVE_GAME, {}).get("path")
    or f"{ACTIVE_GAME}/"
)

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
    """Count phase agents (research/plan/implement) that are ACTUALLY running.

    2026-08-17 (#525/#526/#527 实测): label-based counting was WRONG —
    labels are milestones (persist after the agent finished), not liveness.
    workflow-chain advances labels on PR merge but stale/duplicate label
    writes (multi-agent) left all open issues with phase labels →
    active_phase=4 while 0 agents ran → every new SPAWN silently capped →
    pipeline stalled. Count from state.db async_delegations (state=running)
    instead. Falls back to label count on any DB error (rare duplicate >
    silent stall — matches the existing gate-error philosophy).
    """
    try:
        import sqlite3 as _sqlite
        db = os.path.expanduser("~/.hermes/state.db")
        if not os.path.exists(db):
            return 0
        con = _sqlite.connect(f"file:{db}?mode=ro", uri=True)
        try:
            n = con.execute(
                "SELECT COUNT(*) FROM async_delegations WHERE state='running'"
            ).fetchone()[0]
        finally:
            con.close()
        return int(n)
    except Exception:
        # Fallback: label count (conservative — prefer rare duplicate over stall)
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


# ── 版本目标 (2026-08-19 用户拍板): 用户指定当前版本, 做完即停 ─────
# workflow-config.json `version_target`: "mvp" | "v1" | "v2" | 缺失
# - 无目标 → 不拣 (停止, 安全默认)
# - 目标版本全 CLOSED → 停止 (等用户切换)
# - 版本依赖链: v1 需 mvp 全 CLOSED, v2 需 mvp+v1 全 CLOSED
_VERSION_ORDER = ["mvp", "v1", "v2"]

def _version_target() -> Optional[str]:
    """Read version_target from workflow-config.json (null = 停止)."""
    try:
        with open(WORKFLOW_CONFIG) as f:
            cfg = json.load(f)
        t = cfg.get("version_target")
        return t if t in _VERSION_ORDER else None
    except (OSError, ValueError):
        return None

def _version_open_count(version: str, issues: list) -> int:
    """Count open issues carrying version/<version> label (cache = open only)."""
    return sum(
        1 for i in issues
        if f"version/{version}" in [l.get("name", "") for l in i.get("labels", [])]
    )

def _version_target_satisfied(target: str, issues: list) -> bool:
    """前置版本全 CLOSED 才允许拣选 target (缓存只含 open → open 数为 0)."""
    for prev in _VERSION_ORDER[:_VERSION_ORDER.index(target)]:
        if _version_open_count(prev, issues) > 0:
            return False
    return True


def _pick_candidates(limit: int) -> list[int]:
    """Scan backlog and pick up to `limit` best candidates (from cache).

    Criteria (in order):
    1. In workflow/backlog (not already at workflow/available)
    2. Has priority label (critical > high > medium > low)
    3. Dependencies resolved
    4. No file conflict with current implement-stage issues

    5. **版本目标 (2026-08-19 用户拍板)**: 用户指定当前版本 (workflow-config.json
       `version_target`) → 只拣目标版本 issue; 无目标 → 不拣 (停止);
       目标版本全 CLOSED → 停止 (等用户切换); 目标依赖版本未完成 (v1 需 mvp,
       v2 需 mvp+v1 全 CLOSED) → 不拣 + 告警。
    """
    active_files = _get_active_issue_target_files()

    issues = _ensure_issues_cache()
    if not issues:
        return []

    # ── 版本目标门控 (2026-08-19) ──────────────────────────────
    target = _version_target()
    if target is None:
        _devlog("version-target-none",
                detail="无 version_target — 停止拣选 (安全默认)")
        return []
    if _version_open_count(target, issues) == 0:
        # 目标版本全 CLOSED → 完成, 停止 (等用户切换 version_target)
        _devlog("version-target-completed", target=target,
                detail="目标版本全部完成 — workflow 停止, 切换后继续")
        return []
    if not _version_target_satisfied(target, issues):
        _devlog("version-target-blocked", target=target,
                detail="前置版本未全部完成 — 依赖版本全 CLOSED 才可拣选")
        return []

    # Collect all backlog candidates
    backlog_candidates = []
    for iss in issues:
        label_names = [l.get("name", "") for l in iss.get("labels", [])]
        if "workflow/backlog" not in label_names:
            continue
        if "workflow/available" in label_names:
            continue
        # 版本目标过滤: 只拣目标版本
        if f"version/{target}" not in label_names:
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
#
# 2026-08-13: the gate now ALSO covers the webhook/reconcile SPAWN path in
# preprocess() (see _spawn_gate calls there). The picker path was gated but
# reconcile() re-injected issues.labeled events every tick, so the label
# path re-emitted SPAWN every tick → 5 research + 3 plan + 6 implement
# spawns for #393 in 30 min (07:15-07:45 audit). Shared gate = one spawn
# per (issue, stage) per TTL regardless of which path fires first.
_SPAWN_STATE_FILE = os.path.expanduser("~/.hermes/.spawned-state.json")
# Stage-aware TTL: research agents routinely take 30-70 min to push a PR.
# A uniform 30-min TTL would re-spawn a live-but-slow research agent. PR
# existence stops spawning permanently (deterministic check, see
# _pr_exists_for_issue).
_SPAWN_TTL_BY_STAGE = {
    "research": 5400,      # 90 min
    "plan": 3600,          # 60 min
    "implement": 3600,     # 60 min
    "self-correct": 1800,  # 30 min
    "conflict": 1800,      # 30 min — CONFLICTING PR 冲突解决 delegate 去重 (#542, 2026-08-17)
    # review-resend 已移除 (2026-08-17 方案 X): E2E-done 的 review 改为
    # one-shot 派发 + emitted_at 标记, 不再重发 — 重发 + 消费即删 = 死循环
    # (#494 157-task / #511 24-agent)。漏派发兜底 = watchdog review-stuck。
    "research-resend": 300,  # 5 min — swallowed research SPAWN re-emit
}
_SPAWN_TTL_SECONDS = _SPAWN_TTL_BY_STAGE["plan"]  # legacy uniform value (tests)


# ── Stage ordering (2026-08-13, stale-stage guard) ─────────────────
STAGE_ORDER = {
    "workflow/available": 0,
    "workflow/research": 1,
    "workflow/plan": 2,
    "workflow/implement": 3,
    "workflow/self-correct": 4,
}


def _current_issue_labels(issue_num: int) -> list:
    """Current labels for an open issue from the per-tick cache.
    Defensive: on gh failure (e.g. mocked-down in tests, transient API
    error) return [] so the stale-stage guard never blocks preprocess."""
    try:
        for iss in _ensure_issues_cache():
            if iss.get("number") == issue_num:
                return [l.get("name", "") for l in iss.get("labels", [])]
    except Exception:
        pass
    return []


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


# ── Stage → issue lifecycle label (2026-08-19: 恢复脚本化推进) ────────────
# 历史: ebc0897 (08-14) 加 _advance_issue_label — kanban task 创建时确定性
# 推进 label (available → research → plan → implement), 用户靠 label 管理
# issue 生命周期。c5f8d03 (08-15) kanban 重构失败回滚时丢失, 标注"后续增量
# 重做"却未做 → 回到依赖 cron LLM 自觉推进 (SPAWN label= 字段), v4-flash
# 实测不执行 → #559/#572 停在 workflow/available (#572 实测, 2026-08-19)。
# 修复: SPAWN 发出时 (spawn gate 通过后) 由脚本层确定性推进, 不依赖 LLM。
# 安全: label 写失败 best-effort 吞掉, 绝不阻塞 SPAWN 发出 (workflow 红线)。
# 与 workflow-chain.yml 不冲突: chain 在 PR merge 时推进 (research→plan→
# implement→done), 本函数在 SPAWN 时推进 (available→research 等), 时刻不同。
_STAGE_LABEL = {
    "research": "workflow/research",
    "plan": "workflow/plan",
    "implement": "workflow/implement",
    # self-correct/review/conflict: None — 不推进 (同 ebc0897 原实现)
}

_STAGE_LABEL_PREV = {
    "research": "workflow/available",
    "plan": "workflow/research",
    "implement": "workflow/plan",
}


def _advance_issue_label(stage: str, issue: int) -> None:
    """Advance the issue's workflow lifecycle label at SPAWN time.

    Deterministic: adds the stage label, removes the previous stage label.
    Best-effort: any gh failure is swallowed — SPAWN emission proceeds
    regardless (never block the workflow on a label write).
    """
    add = _STAGE_LABEL.get(stage)
    if not add:
        return
    try:
        gh("issue", "edit", str(issue), "--add-label", add)
        prev = _STAGE_LABEL_PREV.get(stage)
        if prev:
            gh("issue", "edit", str(issue), "--remove-label", prev)
        _invalidate_issues_cache_for(issue)
    except Exception:
        pass  # label advance is best-effort; spawn proceeds


def _spawn_gate(issue: int, stage: str) -> bool:
    """Return True if issue+stage may emit SPAWN now (dedup within TTL).

    Writes the (issue, stage, ts) marker on first call, so a second call
    within TTL returns False. On any state-file error, returns True
    (prefer a rare duplicate over a silent stall)."""
    try:
        state = _read_spawn_state()
        prev = state.get(str(issue), {})
        now = time.time()
        ttl = _SPAWN_TTL_BY_STAGE.get(stage, _SPAWN_TTL_SECONDS)
        if prev.get("stage") == stage and now - prev.get("ts", 0) < ttl:
            _devlog("skip", issue=issue, stage=stage, reason="gate-ttl",
                    ttl_left=int(ttl - (now - prev.get("ts", 0))))
            return False
        state[str(issue)] = {"stage": stage, "ts": now}
        _write_spawn_state(state)
        return True
    except Exception:
        _devlog("skip", issue=issue, stage=stage, reason="gate-error", level="warn")
        return True


def _dead_spawn_recovery(issue: int, stage: str) -> bool:
    """Dead-agent recovery: re-emit SPAWN when the gate recorded a spawn
    but no PR ever appeared AND half the gate TTL has elapsed.

    Context (2026-08-14): cron LLM received `SPAWN: plan,issue=476` at
    11:07 but hit `TimeoutError: idle 92s > 90s` while delegating → the
    SPAWN was consumed (gate marked) but no agent was ever created, and
    the gate TTL (1h) plus the occupied slot count blocked re-emission
    for a full hour. Recovery: if the gate marker is stale (older than
    TTL/2) and the issue still has no PR, allow one re-spawn regardless
    of gate. The PR-exists check is the real dedup here — a live agent
    will have a PR (or branch) within TTL/2; an agent that died or was
    never created won't.

    Only called for plan/implement (stages whose agent creates a PR).
    Returns True to allow re-emission (and refresh the gate marker).
    """
    try:
        state = _read_spawn_state()
        prev = state.get(str(issue), {})
        now = time.time()
        if prev.get("stage") != stage:
            return False  # gate never recorded this stage — normal path handles it
        ttl = _SPAWN_TTL_BY_STAGE.get(stage, _SPAWN_TTL_SECONDS)
        if now - prev.get("ts", 0) < ttl / 2:
            return False  # too soon — real agent may still be starting up
        # Stale gate marker + no PR → dead spawn. Refresh marker so the
        # next re-emission also needs to wait TTL/2 (no per-tick spam).
        state[str(issue)] = {"stage": stage, "ts": now}
        _write_spawn_state(state)
        return True
    except Exception:
        return False


def pick_next_issue() -> list:
    """Entry point: called after slot freed or at window entry.
    Fills up to MAX_CONCURRENT issues.
    Emits SPAWN lines for newly promoted issues (research), for
    plan/implement issues without a PR yet, and for issues stuck at
    workflow/available (dead-agent rescan). Returns the SPAWN line list
    (no printing — main() owns the output via the unified lines pipeline)."""
    spawn_lines: list = []
    if is_paused():
        return spawn_lines
    
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
            # Direct research spawn (2026-08-13): the scheduler emits SPAWN
            # itself right after promoting backlog → available — no longer
            # relying on the webhook echo round-trip. The shared gate dedups
            # against the webhook/reconcile label path.
            if _spawn_gate(n, "research") or _dead_spawn_recovery(n, "research"):
                _advance_issue_label("research", n)
                spawn_lines.append(f"SPAWN: research,issue={n},label=workflow/research,game={ACTIVE_GAME}")
                _devlog("spawn", issue=n, stage="research", source="backlog-promotion")
    
    # Also emit SPAWN for issues at plan/implement/available with no PR yet
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
                if _spawn_gate(n, "plan") or _dead_spawn_recovery(n, "plan"):
                    _advance_issue_label("plan", n)
                    spawn_lines.append(f"SPAWN: plan,issue={n},label=workflow/plan,game={ACTIVE_GAME}")
                    _devlog("spawn", issue=n, stage="plan", source="picker")
        elif "workflow/implement" in labels:
            existing = gh("pr", "list", "--state", "all",
                          "--search", f"head:impl/{n}- in:headRefName",
                          "--json", "number,state",
                          "--jq", "length")
            if existing is None or int(existing) == 0:
                if _spawn_gate(n, "implement") or _dead_spawn_recovery(n, "implement"):
                    # ── Key-path OpenCode gate (2026-08-13) ──
                    # OpenCode is implement's ONLY code path. Check at the
                    # moment of spawn (not every tick): if it's down, don't
                    # emit SPAWN — an implement agent without OpenCode falls
                    # back to manual writes, burns the call budget, and
                    # stalls with a dirty worktree (#466). Auto-pause and
                    # surface [CRITICAL] instead; human fixes + resumes.
                    if not opencode_healthy():
                        _pause_workflow(f"opencode-down (implement spawn blocked, issue {n})")
                        _devlog("blocked", issue=n, stage="implement", reason="opencode-down", level="warn")
                        spawn_lines.append(f"BLOCKED: implement,issue={n},reason=opencode-down — workflow auto-paused, fix OpenCode Serve and `/workflow resume`")
                    else:
                        _advance_issue_label("implement", n)
                        spawn_lines.append(f"SPAWN: implement,issue={n},label=workflow/implement,game={ACTIVE_GAME}")
                        _devlog("spawn", issue=n, stage="implement", source="picker")
        elif "workflow/available" in labels:
            # Available rescan (2026-08-13): deterministic dead-agent recovery.
            # An issue stuck at workflow/available with no research PR (agent
            # died, label event lost) is re-spawned after the gate TTL.
            # 2026-08-14: also try _dead_spawn_recovery — a SPAWN consumed by
            # cron timeout (#480: 45 min stall) must re-emit after TTL/2.
            # 2026-08-17 (#525/#526/#527 实测): REMOVED the `research-resend`
            # OR branch — it was an UNCONDITIONAL re-emitter (independent
            # 5-min marker always fresh) → same issue re-spawned every ~3-4min,
            # producing 3 concurrent research agents per issue (PR #528 merged
            # while duplicates still running). _dead_spawn_recovery (TTL/2)
            # is the deterministic recovery path; swallowed-SPAWN recovery
            # latency is 45min instead of 5min — correctness over speed.
            if not _pr_exists_for_issue("research", n):
                if (_spawn_gate(n, "research")
                        or _dead_spawn_recovery(n, "research")):
                    _advance_issue_label("research", n)
                    spawn_lines.append(f"SPAWN: research,issue={n},label=workflow/research,game={ACTIVE_GAME}")
                    _devlog("spawn", issue=n, stage="research", source="available-rescan")

    return spawn_lines


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
            # 2026-08-19 (#572 缺陷 A): sha 幂等键 — 与 webhook 路径一致,
            # fresh_ci 靠它区分重放 (同 sha) 与真新 commit (不同 sha)。
            "sha": sha,
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
                # ── E2E scripted front-load (2026-08-14, plan ②) ──
                # Don't spawn review directly: kick off the E2E runner as a
                # background SCRIPT first (zero agent calls), so the review
                # agent gets a ready summary instead of burning 30-40 calls
                # running the harness itself. The orchestrator returns either
                # progress lines (running) or a SPAWN: review line once the
                # summary is harvested.
                # 2026-08-17 (方案 X): fresh_ci=True — 这是 check_run.completed
                # 事件路径, 新 CI 完成 = 新轮次 (重置状态, kill 旧 runner)。
                # 2026-08-19 (#572 缺陷 A): 事件带 sha — e2e_orchestrator 用
                # 它区分"重放 (同 sha)"与"真新 commit (不同 sha)"。
                e2e_lines = e2e_orchestrator(pr_num, branch, fresh_ci=True,
                                             sha=event.get("sha", ""))
                if e2e_lines:
                    output_lines.extend(e2e_lines)
                # One-shot consumption (see self-correct SPAWN note above).
                discarded_keys.add(event.get("_key", ""))
            else:
                # ── Non-impl branch (research/plan/*) — 2026-08-13 ──
                # check_run.completed 对非 impl 分支的语义是"前置阶段 PR 的
                # CI 完成",推进动作是 merge(workflow-chain 在 PR merge 后才
                # 推进 label)。旧行为把事件输出成 P1 让 cron LLM"决策"→
                # cron 花 4 分钟调查一个已完成的推进(181544 trace,plan PR
                # #462 CI 成功 → 全链已推进 → cron 白跑 4 分钟阻塞后续 tick)。
                # 改为输出确定性 STALLED: merge-pr 指令(与 _quick_stalled_scan
                # 同格式,cron prompt 已有对应 handler,一条 gh 命令执行完)。
                # 其余情况(非 research/plan 前缀、非 success)对 cron 无可
                # 操作项:静默消费 + audit,stalled scan 兜底复查。
                if conclusion == "success" and (
                    branch.startswith("research/") or branch.startswith("plan/")
                ):
                    _devlog("merge-request", pr=int(issue), branch=branch, source="check_run")
                    output_lines.append(
                        f"STALLED: merge-pr,pr={issue},branch={branch}"
                    )
                else:
                    _audit(
                        event="check_run.dropped",
                        issue=issue,
                        branch=branch,
                        conclusion=conclusion,
                        reason="non-impl-noop",
                    )
                # Consume either way: never re-emit a non-impl check_run.
                discarded_keys.add(event.get("_key", ""))
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
                # ── Stale-stage guard (2026-08-13) ──
                # A label event for an EARLIER stage than the issue's current
                # stage is stale — e.g. workflow/available lingering while the
                # issue is already at workflow/implement (workflow-chain.yml
                # only removed the immediate previous stage). Never spawn a
                # backward stage (observed: phantom `SPAWN: research` for #393
                # at 07:31 while the issue was already at plan/implement).
                cur_stage = max(
                    (STAGE_ORDER.get(l, -1) for l in _current_issue_labels(issue_int)),
                    default=-1,
                )
                if STAGE_ORDER.get(label, -1) < cur_stage:
                    event_key = event.get("_key", "")
                    if event_key:
                        discarded_keys.add(event_key)
                    continue
                if _pr_exists_for_issue(stage, issue_int):
                    # PR already exists — skip spawn, let flow continue via PR.
                    # Clean up from pending to avoid re-processing.
                    event_key = event.get("_key", "")
                    if event_key:
                        discarded_keys.add(event_key)
                    continue
                # ── Spawn gate (2026-08-13) ──
                # reconcile() re-injects label events; without a shared gate
                # this path re-emits SPAWN every tick → duplicate agents
                # (observed: 5 research + 3 plan + 6 implement spawns for
                # #393, 07:15-07:45 audit). The picker path was already gated
                # (canary #358); the webhook/reconcile path must share it.
                if not _spawn_gate(issue_int, stage):
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
                # ── Key-path OpenCode gate (2026-08-13) ──
                # Same gate as the picker: check OpenCode exactly when an
                # implement spawn is about to be emitted. OpenCode down →
                # don't emit SPAWN, auto-pause, surface BLOCKED for the LLM.
                if stage == "implement" and not opencode_healthy():
                    _pause_workflow(f"opencode-down (implement spawn blocked, issue {issue_int})")
                    output_lines.append(f"BLOCKED: implement,issue={issue_int},reason=opencode-down — workflow auto-paused, fix OpenCode Serve and `/workflow resume`")
                    event_key = event.get("_key", "")
                    if event_key:
                        discarded_keys.add(event_key)
                    continue
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
    output_lines.sort(key=_output_sort_key)
    return output_lines


def _output_sort_key(line: str) -> tuple:
    """Shared output sort: SPAWN lines first (review/self-correct SPAWNs
    before other SPAWNs), then P1/P2/STALLED lines. Used by preprocess()
    and by main() when merging picker lines into the lines pipeline."""
    return (0 if line.startswith("SPAWN:") else 1,
            0 if "review" in line or "self-correct" in line else
            1 if line.startswith("SPAWN:") else 2)


def _quick_stalled_scan():
    """Deterministic stalled PR scan. Outputs explicit STALLED commands.

    Runs in <5 seconds (gh API only, no godot, no file reads).
    NOTE (2026-08-13): the `--search head:... in:headRefName` qualifier is
    unreliable (Patch 59 — returns [] even for existing PRs, intermittently).
    A plain `gh pr list --state open` + client-side prefix filter is used so
    impl PRs like #444 are never missed by the review re-spawn fallback."""
    cmds = []

    # 1. Fetch open PRs once, filter client-side by branch prefix
    raw = gh("pr", "list", "--state", "open",
             "--json", "number,headRefName,mergeable,labels,body,title,state",
             "--limit", "100")
    if not raw:
        return cmds
    try:
        prs = json.loads(raw)
    except json.JSONDecodeError:
        return cmds
    for pr in prs:
        # 🛡️ Verify PR is actually still OPEN (API caching may return stale merged PRs)
        if pr.get("state") != "OPEN":
            continue
        branch = pr.get("headRefName", "")
        labels = [l["name"] for l in pr.get("labels", [])]
        pr_num = pr["number"]

        if branch.startswith("research/") or branch.startswith("plan/") \
                or branch.startswith("docs/"):
            # Stalled research/plan PR — merge if mergeable.
            # 2026-08-19 (post-merge 阶段落地): docs/ 前缀 = post-merge agent
            # 创建的 GDD 更新 PR (docs/gdd-<N>) — 同样自动 merge (merge 归脚本
            # 层, post-merge agent 绝不自己 merge)。GDD 是纯 docs, 不进 CI,
            # 不触碰"可运行游戏"红线; PR 形态保证 main 只进 PR + 可追溯。
            if pr.get("mergeable") == "MERGEABLE":
                cmds.append(
                    f"STALLED: merge-pr,pr={pr_num},"
                    f"branch={branch}"
                )
                _devlog("merge-request", pr=pr_num, branch=branch, source="stalled-scan")
        elif branch.startswith("impl/"):
            # Stalled impl PR — check CI status, then review or self-correct.
            # All STALLED emissions go through _spawn_gate: the same PR must
            # not re-emit STALLED every tick (3b59ede exposed the ungated
            # per-tick review re-spawn hole). Gate is the ONLY dedup —
            # review/self-correct each fire once per TTL per PR.
            if pr.get("mergeable") == "CONFLICTING":
                # ── Conflict detection (2026-08-17, #542) ──
                # A CONFLICTING impl PR is a deadlock: review/merge cannot
                # proceed, e2e-state may be a terminal "reviewed" (E2E ran on
                # the pre-conflict commit), and _pr_exists_for_issue() treats
                # the PR as "implement done" → never re-spawned. Recovery =
                # delegate an implement agent (check-conflict) to merge main
                # into the branch, resolve conflicts, push → CI synchronize →
                # fresh_ci resets e2e → new review round (link auto-heals).
                # Priority: conflict first — blocked/self-correct/e2e paths
                # are all meaningless while the branch cannot merge.
                if _spawn_gate(pr_num, "conflict"):
                    cmds.append(f"STALLED: check-conflict,pr={pr_num},branch={branch}")
                    _devlog("conflict-request", pr=pr_num, branch=branch)
                continue  # 冲突未解决前不做任何其他处理 (含 e2e/review)
            if "status/blocked" in labels:
                # ── Blocked PR handling (2026-08-14 rework) ──
                # A blocked PR has TWO independent recovery paths that must
                # coexist, not be mutually exclusive:
                #
                # 1. check-unblock: the PR is blocked on PRE-EXISTING main
                #    failures tracked by a fix issue. Recovery = fix issue
                #    merges → main green → remove status/blocked → update-branch.
                #    The old check-unblock ran `godot run_tests.gd` and
                #    unblocked on 0 FAILED — WRONG for visual/L3 blocks (logic
                #    tests pass while rendering is broken). Now it checks the
                #    fix issue's merged state instead (see cron prompt).
                #
                # 2. check-self-correct: the PR ALSO has its own code defects
                #    (class D) that the review agent flagged via
                #    workflow/self-correct on the parent issue. Those must be
                #    fixed in the worktree by the self-correct agent — they do
                #    NOT wait on the fix issue.
                #
                # Both are emitted when applicable. The self-correct path is
                # independent and can proceed immediately (doesn't depend on
                # the fix issue merging).
                parent = _extract_parent_issue(pr_num)
                parent_self_correct = False
                if parent:
                    p_labels = _current_issue_labels(parent)
                    parent_self_correct = "workflow/self-correct" in p_labels
                if _spawn_gate(pr_num, "unblock"):
                    cmds.append(f"STALLED: check-unblock,pr={pr_num},branch={branch}")
                    _devlog("unblock-request", pr=pr_num, branch=branch)
                if parent_self_correct and _spawn_gate(pr_num, "self-correct"):
                    cmds.append(f"STALLED: check-self-correct,pr={pr_num},branch={branch}")
            else:
                # Self-correct awareness: the parent issue was already flagged
                # workflow/self-correct by the review agent (local e2e failure,
                # CI possibly green) → go straight to self-correct instead of
                # burning another review round.
                parent = _extract_parent_issue(pr_num)  # PR body Parent/Closes #N
                if parent:
                    p_labels = _current_issue_labels(parent)
                    if "workflow/self-correct" in p_labels:
                        if _spawn_gate(pr_num, "self-correct"):
                            cmds.append(f"STALLED: check-self-correct,pr={pr_num},branch={branch}")
                        continue
                # ── E2E scripted front-load (2026-08-14, plan ②) ──
                # Parent unresolved / no self-correct label → review, but the
                # E2E runner runs FIRST as a background script (zero agent
                # calls). The orchestrator emits either progress lines
                # (running), SPAWN: review (done, until a conclusion file
                # appears), or nothing (failed).
                # NOTE: the orchestrator is called UNCONDITIONALLY here — its
                # done-branch re-emits SPAWN every tick until the review
                # conclusion file exists (2026-08-14 16:10 trace: SPAWN
                # swallowed by busy cron, gate TTL suppressed re-emission for
                # 40 min). Gating would skip the done-branch re-emit.
                e2e_lines = e2e_orchestrator(pr_num, branch)
                if e2e_lines:
                    cmds.extend(e2e_lines)

    return cmds


def main():
    try:
        cfg = read_workflow_config()
        
        # Pause check
        if is_paused():
            _audit(tick="end", in_window=False, paused=True, output="[PAUSED]")
            _devlog("tick_summary", in_window=False, paused=True, idle=True)
            return

        # Flush per-tick caches ──
        # These caches are valid only within one tick.
        # The gh() call cache (30s TTL) is separate and persists
        # for cross-call dedup within the tick.
        _ISSUES_CACHE.clear()
        _BODY_CACHE.clear()
        _CLOSED_ISSUES_CACHE.clear()
        
        # Window entry detection: if we just entered work hours, pick + health check
        was_outside = False
        try:
            state_file = os.path.expanduser("~/.hermes/.workflow-state.json")
            if os.path.exists(state_file):
                with open(state_file) as f:
                    state = json.load(f)
                was_outside = state.get("last_hour", -1) != datetime.datetime.now().hour
        except Exception:
            pass
        
        # Picker SPAWN lines join the unified lines pipeline (2026-08-13).
        # All picker calls accumulate here; main() merges them with
        # preprocess() output, then applies sort → cap → audit → print.
        picker_lines: list = []
        in_window = _time_in_window(cfg)
        if in_window and was_outside:
            # Just entered work hours → health check
            hc = health_check()
            print(hc, file=sys.stderr)
            picker_lines += pick_next_issue() or []
        
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
        # operations (picker, preprocess, stalled scan). Only cost:
        # 1 gh issue list call + 1 local file read per tick.
        events = []
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
                    # 2026-08-15: devlog too — distinguish idle from dead.
                    _devlog("tick_summary", in_window=in_window, paused=False,
                            pending=0, raw_lines=0, spawn=0, blocked=0,
                            stalled=0, phase_slots=0, active_phase=0,
                            idle=True)
                    print("[SILENT]")
                    return

        # Outside hours → only process pipeline events, block picker + available
        if not in_window:
            # Only process pipeline events via standard preprocess
            pass  # fall through to preprocess with proper filtering
        
        # Pick from backlog FIRST (fast, gh API only for picker)
        # Then preprocess (may be slower). Picker lines and preprocess lines
        # share one output pipeline: sort → cap → audit → print.
        if in_window and not is_paused():
            picker_lines += pick_next_issue() or []
        
        lines = preprocess()
        lines = lines + picker_lines
        # 2026-08-19 (#572 deadlock 修复): stalled scan 无条件每 tick 执行。
        # 原实现只在 pending==0 (无事件分支) 跑 — 但 P2 issues.labeled
        # (workflow/backlog) 事件设计保留滞留 pending → pending 恒非空 →
        # stalled scan 饿死 → E2E 僵尸态 (status=running + pid 已死, e.g.
        # fresh_ci 重放误启 runner 即死) 无人收割 → SPAWN review 永不发出
        # → pipeline 冻结 (#572/#599 实证, 2026-08-19)。
        # 安全性: _quick_stalled_scan 内部所有 SPAWN/STALLED 均过 _spawn_gate
        # 去重 (test_stalled_scan_gated) — 每 tick 跑不会重复派发。
        if in_window and not is_paused():
            lines = lines + (_quick_stalled_scan() or [])
        # SPAWN lines must come first — LLM reads top-to-bottom
        lines.sort(key=_output_sort_key)
        
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

        # ── Tick summary (2026-08-15, develop mode) ──
        # One-line per-tick digest so any run is auditable without grepping
        # the JSONL: pending count, spawn/skip/blocked/merge totals, phase
        # slots, anomalies. Written to the JSONL as event=tick_summary AND
        # printed in develop mode.
        _devlog(
            "tick_summary",
            in_window=in_window,
            paused=is_paused(),
            pending=len(events),
            raw_lines=len(lines_pre_cap),
            spawn=sum(1 for l in lines if l.startswith("SPAWN:")),
            blocked=sum(1 for l in lines if l.startswith("BLOCKED:")),
            stalled=sum(1 for l in lines if l.startswith("STALLED:")),
            phase_slots=available_phase_slots,
            active_phase=active_phase,
        )
        
        if lines:
            print("\n".join(lines))
            
            # If there was a status/done event, trigger picker to fill slot
            # — its SPAWN lines merge into this tick's output.
            if in_window and any("status/done" in l for l in lines):
                extra_lines = pick_next_issue() or []
                if extra_lines:
                    print("\n".join(extra_lines))
        else:
            # No pending events → fallback picker only.
            # 2026-08-19 (#572): stalled scan 已在上方统一 pipeline 无条件
            # 执行, 这里不再重复调用 (否则 pending==0 时每 tick 跑两次)。
            if in_window and not is_paused():
                picker_lines2 = pick_next_issue() or []
                if picker_lines2:
                    print("\n".join(picker_lines2))
                else:
                    print("[SILENT]")
            else:
                print("[SILENT]")

        # ── Review follow-through (2026-08-14): deterministic script layer ──
        # The review agent's conclusion is a STRUCTURED JSON file written to
        # REVIEW_CONCLUSIONS_DIR/<pr>.json (see game-review-agent SKILL.md).
        # This is deliberately NOT left to the agent's call budget: the agent
        # may run out of iterations mid-E2E and never get to label/comment/
        # fix-issue (happened 2× on #466/#475). Here the script layer performs
        # the mechanical follow-up — idempotent, retryable, zero LLM calls:
        #   verdict=blocked  → status/blocked on PR + parent issue
        #   fix_issue        → create fix issue (fset dedup) if missing
        #   comment          → post conclusion comment with evidence
        # After processing, the file is removed (idempotent).
        if in_window and not is_paused():
            followup_lines = review_followup()
            if followup_lines:
                print("\n".join(followup_lines))
            # 2026-08-19 (post-merge 阶段落地): approved merge 的同 tick 发射
            # SPAWN: post-merge — review_followup 刚创建的 pending 状态在这里
            # 被扫描到, 下个 cron tick 的 LLM delegate post-merge agent。
            post_merge_lines = post_merge_emitter()
            if post_merge_lines:
                print("\n".join(post_merge_lines))
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


OPENCODE_HEALTH_URL = "http://127.0.0.1:18765/global/health"
OPENCODE_CRITICAL_FILE = os.path.expanduser("~/.hermes/.opencode-critical")

# ── Review follow-through (2026-08-14) ───────────────────────────
# Deterministic script layer for review conclusions. The review agent writes
# ~/.hermes/review-conclusions/<pr>.json as its LAST action (see SKILL.md);
# the script layer here performs the mechanical aftermath (labels, fix issue,
# comment) so a call-budget-exhausted agent never leaves a blocked PR with no
# label / fix issue / comment (happened 2×: #466 then #475).
REVIEW_CONCLUSIONS_DIR = os.path.expanduser("~/.hermes/review-conclusions")
E2E_STATE_DIR = os.path.expanduser("~/.hermes/e2e-state")
# 2026-08-19 (post-merge 阶段落地): approved merge 后的 post-merge 任务状态。
# review_followup 在 _try_merge 成功后创建 {status: pending}; post_merge_emitter
# 每 tick 扫描, pending+无 emitted_at → SPAWN: post-merge (one-shot); post-merge
# agent 完成后写 status=done; 超时未 done → workflow-watchdog post-merge-stuck 告警。
POST_MERGE_STATE_DIR = os.path.expanduser("~/.hermes/post-merge-state")
# Runner lives in the project scripts/ dir. When event-processor runs from the
# cron copy (~/.hermes/scripts/), __file__ points there — the runner may not
# be synced (2026-08-14: `bash: .../run-e2e-review.sh: No such file or
# directory`). Fall back to the project repo path.
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
# 2026-08-17 (pipeline-tests CI 修复): E2E runner 查找不再依赖 macOS
# 硬编码路径 — CI (ubuntu) 上 ~/workspace/agent-game-test 不存在 → 测试
# 的 E2E launch 全部 Errno 2 (main 7+ 次 pipeline-tests 全红)。
# _SCRIPT_DIR 在 CI checkout 下即 repo 的 scripts/, 直接存在; fallback
# 改为从 repo 根推导 (BASH_SOURCE 语义), 覆盖同步副本 (~/.hermes/scripts/)。
E2E_RUNNER = os.path.join(_SCRIPT_DIR, "run-e2e-review.sh")
if not os.path.exists(E2E_RUNNER):
    _repo_root = os.path.dirname(_SCRIPT_DIR)  # scripts/ 上一级
    for _cand in (
        os.path.join(_repo_root, "scripts", "run-e2e-review.sh"),
        os.path.expanduser("~/workspace/agent-game-test/scripts/run-e2e-review.sh"),
    ):
        if os.path.exists(_cand):
            E2E_RUNNER = _cand
            break


def _e2e_state_path(pr: int) -> str:
    return os.path.join(E2E_STATE_DIR, f"{pr}.json")


def _read_e2e_state(pr: int) -> dict:
    try:
        with open(_e2e_state_path(pr)) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}


def _write_e2e_state(pr: int, data: dict) -> None:
    try:
        os.makedirs(E2E_STATE_DIR, exist_ok=True)
        with open(_e2e_state_path(pr), "w") as f:
            json.dump(data, f, indent=1)
    except OSError:
        pass


# ── Post-merge state (2026-08-19) ─────────────────────────────────
# 方案 X (merge 脚本化) 后, review agent 会话在写结论文件后即结束, merge 由
# review_followup/_try_merge 在下一个 cron tick 执行 → skill 的 post-merge
# GDD 步骤在 review 会话内不可达 (#562/#566 实测, GDD 成无主责任)。
# 修复: merge 事件 → post-merge 任务状态 → SPAWN: post-merge (one-shot) →
# post-merge agent (game-post-merge-agent skill) 执行 GDD/PROJECT.md/通知/board。
# 触发归脚本 (确定性), 写作归 LLM —— 符合"LLM 只做判定, 机械归脚本"铁律。
def _post_merge_state_path(pr: int) -> str:
    return os.path.join(POST_MERGE_STATE_DIR, f"{pr}.json")


def _read_post_merge_state(pr: int) -> dict:
    try:
        with open(_post_merge_state_path(pr)) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}


def _write_post_merge_state(pr: int, data: dict) -> None:
    try:
        os.makedirs(POST_MERGE_STATE_DIR, exist_ok=True)
        tmp = _post_merge_state_path(pr) + ".tmp"
        with open(tmp, "w") as f:
            json.dump(data, f, indent=1)
        os.replace(tmp, _post_merge_state_path(pr))
    except OSError:
        pass


def _ensure_post_merge_state(pr: int, issue) -> None:
    """review_followup 在 approved→merged 成功后调用。幂等: 已存在不覆盖。"""
    if _read_post_merge_state(pr).get("status") == "done":
        return
    _write_post_merge_state(pr, {
        "pr": pr,
        "issue": int(issue) if issue else 0,
        "status": "pending",
        "created_at": time.time(),
    })


def post_merge_emitter() -> list:
    """Emit `SPAWN: post-merge,pr=N,issue=M` ONCE per merged PR.

    One-shot semantics mirror the review SPAWN (e2e-state emitted_at marker):
    pending + no emitted_at → emit + stamp; emitted_at → silent; done → silent.
    A dropped delegation is surfaced by workflow-watchdog's post-merge-stuck
    check (告警, 不自动重发), same as review-stuck.
    """
    lines = []
    try:
        entries = sorted(os.listdir(POST_MERGE_STATE_DIR))
    except OSError:
        return lines
    for fn in entries:
        if not fn.endswith(".json"):
            continue
        try:
            pr = int(fn[:-5])
        except ValueError:
            continue
        state = _read_post_merge_state(pr)
        if state.get("status") == "done":
            continue
        if state.get("emitted_at"):
            continue  # one-shot
        issue = state.get("issue") or 0
        lines.append(f"SPAWN: post-merge,pr={pr},issue={issue}")
        state["emitted_at"] = time.time()
        _write_post_merge_state(pr, state)
        _devlog("post-merge-spawn", pr=pr, issue=issue)
    return lines


def _pid_alive(pid: int) -> bool:
    if not pid:
        return False
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, ProcessLookupError, ValueError):
        return False


def _kill_runner(pid: int) -> None:
    """Terminate a background E2E runner (whole process group).

    2026-08-17 (方案 X): a fresh CI round must not leave the previous
    round's runner alive — two runners concurrently building/deleting the
    same /tmp/wt-impl-<pr> worktree is exactly the #511 conflict source.
    SIGTERM then wait briefly for exit, escalate to SIGKILL on timeout.
    """
    import signal as _sig
    pid = int(pid)
    try:
        os.killpg(os.getpgid(pid), _sig.SIGTERM)
    except (OSError, ProcessLookupError, ValueError):
        try:
            os.kill(pid, _sig.SIGTERM)
        except (OSError, ProcessLookupError, ValueError):
            return
    deadline = time.time() + 2.0
    while time.time() < deadline:
        if not _pid_alive(pid):
            return
        time.sleep(0.05)
    try:
        os.killpg(os.getpgid(pid), _sig.SIGKILL)
    except (OSError, ProcessLookupError, ValueError):
        try:
            os.kill(pid, _sig.SIGKILL)
        except (OSError, ProcessLookupError, ValueError):
            pass


def e2e_orchestrator(pr: int, branch: str, fresh_ci: bool = False,
                     sha: str = "") -> list:
    """E2E scripted front-load (2026-08-14, plan ②).

    Instead of spawning the review agent and letting IT run the E2E runner
    (burning 30-40 of its 50-call budget on mechanical verification — the
    root cause of review agents exhausting budget before labeling/commenting,
    seen 2× on #466/#475), the event-processor orchestrates the runner as a
    background SCRIPT (zero LLM calls) and hands the agent a ready summary.

    State machine (persisted in ~/.hermes/e2e-state/<pr>.json):
      absent        → launch runner in background, write {status: running}
      running+alive → report progress ("still running Xm") — status is
                       VISIBLE, so a long E2E on a big project never looks
                       like a stall
      running+dead  → read summary.json, transition to done/failed
      done          → emit SPAWN: review ONCE (one-shot, emitted_at marker)
                       with e2e_summary=... for the agent to interpret (it
                       does NOT re-run the runner); silent afterwards
      failed        → silent (self-correct owns it)

    fresh_ci=True (2026-08-17, 方案 X): the caller is a check_run.completed
    event — a NEW CI round (webhook + reconcile dedup by sha, so an event
    ≈ a new commit's CI conclusion). Any existing state is reset (old runner
    killed to avoid concurrent worktree conflicts) and a fresh round starts.
    This is the ONLY reset path: without it, done+emitted_at would silently
    swallow re-review of new commits.

    2026-08-19 (#572 缺陷 A): sha 幂等 — GitHub webhook 投递失败会重试
    (指数退避, 最多 8 次), 同一 check_run.completed 事件可能被投递两次。
    fresh_ci + 同 sha + 上次已终态 → 这是重放, 跳过重置 (否则误 kill
    已完成轮次、误启第二个 runner — #599 实证: E2E #2 启动即死, 状态卡
    running)。真新 commit (sha 不同) 才重置。sha 为空 (旧事件/无 sha)
    → 保持原行为 (重置), 不破坏向后兼容。

    Returns output lines for the tick.
    """
    lines = []
    state = _read_e2e_state(pr)
    status = state.get("status")

    # 2026-08-17 (方案 X): fresh CI event → fresh round. Kill any runner
    # still alive from the previous round (concurrent worktrees = the #511
    # conflict source), reset state, fall through to the absent launch path.
    # 2026-08-19 (#572 缺陷 A): 同 sha 重放 → 不重置, 走正常状态机
    # (running+dead → 收割; done → one-shot 静默)。
    if fresh_ci:
        prev_sha = state.get("sha", "")
        if sha and prev_sha and sha == prev_sha \
                and status in ("done", "failed", "reviewed"):
            lines.append(f"E2E: pr={pr} duplicate check_run (same sha {sha[:8]}) — skip reset")
            return lines
        old_pid = int(state.get("pid") or 0)
        if old_pid and _pid_alive(old_pid):
            _kill_runner(old_pid)
        state = {}
        status = None

    if status == "running":
        if _pid_alive(int(state.get("pid") or 0)):
            mins = int((time.time() - state.get("started_at", time.time())) / 60)
            lines.append(f"E2E: pr={pr} still running ({mins}m) — {branch}")
            return lines
        # runner died — harvest result. CRITICAL (2026-08-14): the summary
        # path may hold a STALE file from a previous review round (same
        # /tmp/e2e-<pr>/ dir). Only accept a summary written AFTER this
        # runner started; otherwise treat as failed with no evidence.
        summary = state.get("summary") or f"/tmp/e2e-{pr}/summary.json"
        started = state.get("started_at", 0)
        verdict = "failed"
        if not os.path.exists(summary):
            # 2026-08-15: NO summary at all = infra failure (runner died
            # before producing evidence — e.g. P1 worktree add failed because
            # the implement agent's worktree still holds the branch). Not a
            # content failure. Reset to absent so the next tick relaunches
            # (the implement agent eventually cleans up / frees the branch).
            # Without this, verdict=failed + silent = deadlock: CI is green
            # (no check_run.failure → no self-correct) and review never
            # spawns (#494 trace, #507 same).
            lines.append(f"E2E: pr={pr} infra-error (no summary — worktree conflict?) — will retry")
            state["status"] = "absent"
            state["retry_at"] = time.time() + 300  # 5-min cooldown
            _write_e2e_state(pr, state)
            return lines
        if os.path.exists(summary):
            try:
                mtime = os.path.getmtime(summary)
                if mtime >= started:
                    with open(summary) as f:
                        sd = json.load(f)
                    layers = sd.get("layers", {})
                    # Layer values: L0-L2 are exit codes (0=pass, 1=fail,
                    # 2=unavailable), L3_visual is "pass"/"fail"/"skip".
                    # Accept "0" (exit 0), "pass" AND "skip" as green —
                    # 2026-08-15: visual layer default-skipped (deepseek
                    # has no multimodal; L3 adds complexity without value).
                    def _green(v):
                        s = str(v).strip().lower()
                        return s in ("0", "pass", "true", "yes", "skip")
                    if all(_green(v) for v in layers.values()):
                        verdict = "done"
                else:
                    lines.append(f"E2E: pr={pr} summary stale (mtime {mtime:.0f} < start {started:.0f})")
            except (json.JSONDecodeError, OSError):
                verdict = "failed"
        state["status"] = verdict
        state["finished_at"] = time.time()
        if verdict in ("done", "failed"):
            # 2026-08-17 (方案 X 复盘): failed 也派发 review — 原设计
            # (PLAN-e2e-verification-v2 §5.1): 本地 E2E 失败由 review agent
            # 判类 → D 类打 workflow/self-correct label → event-processor
            # label 规则 (L1428) SPAWN self-correct → 本地收敛循环 (2 轮上限)。
            # 方案② 迁移时 failed 静默 → review agent 不在场 → 没人打 label
            # → 死锁 (#516 实证: E2E failed + CI 假绿 = 永久卡 workflow/implement)。
            state["emitted_at"] = time.time()
        _write_e2e_state(pr, state)
        lines.append(f"E2E: pr={pr} {verdict} (summary {summary})")
        if verdict in ("done", "failed"):
            # 2026-08-19 (P2 骨架): SPAWN review 前预生成结论骨架 —
            # review agent 只填受控字段, 不自由写 JSON (#562 根治)。
            _ensure_conclusion_skeleton(pr)
            lines.append(f"SPAWN: review,issue={pr},pr={pr},branch={branch},e2e_summary={summary}")
        return lines

    if status in ("done", "failed", "reviewed"):
        # 2026-08-17 (方案 X): one-shot 派发, 不再重发。
        # 历史教训: done 分支"每 5 分钟重发直到结论文件出现"(ce03bd2/
        # 80d6aaa) 与 review_followup"消费即删"互相抵消 → review 无限循环
        # (#494 157-task, #511 24-agent, worktree 冲突为次生症状)。
        # SPAWN 只发一次; 漏派发的兜底 = workflow-watchdog review-stuck
        # 检测 (告警, 不自动重发)。
        # 2026-08-17 (复盘): done 与 failed 同权 — failed 也由 review agent
        # 判类 (原设计 §5.1), 所以 failed 的防御补发与 done 一致。
        # reviewed (2026-08-17): 终态 — review_followup 已消费结论。
        # 必须静默返回, 否则落进 absent 分支会重启 E2E (stalled scan 每
        # tick 扫到就启动新 runner, 无限轮次)。新 commit 由 fresh_ci 重置。
        if status == "reviewed":
            return lines  # 终态: 已 review, 静默 (不重启)
        if _read_review_conclusions_file(pr):
            return lines  # 结论在 → review_followup 将消费, 等待
        if state.get("emitted_at"):
            return lines  # 已派发过 → one-shot, 静默
        # 防御性补发: harvest 路径已写 emitted_at, 这里只覆盖历史残留
        # 状态 (08-17 之前的 e2e-state 无 emitted_at 字段)。
        _ensure_conclusion_skeleton(pr)
        lines.append(f"SPAWN: review,issue={pr},pr={pr},branch={branch},e2e_summary={state.get('summary', '')}")
        state["emitted_at"] = time.time()
        _write_e2e_state(pr, state)
        return lines

    # absent → launch background runner (--no-comment: evidence posted by
    # review agent after interpreting, avoids double-posting)
    # 2026-08-15: infra-error cooldown — after a no-summary failure (e.g.
    # worktree conflict), wait 5 min before relaunching so the implement
    # agent can free the branch; prevents per-tick relaunch spam.
    _retry_at = state.get("retry_at", 0)
    if _retry_at and time.time() < _retry_at:
        return lines
    try:
        os.makedirs(E2E_STATE_DIR, exist_ok=True)
        log_path = f"/tmp/e2e-{pr}-orchestrator.log"
        runner = E2E_RUNNER
        # nohup-style background launch via subprocess.Popen (detached).
        # CRITICAL (2026-08-14): when the runner lives in the cron copy
        # (~/.hermes/scripts/), its REPO_ROOT derivation (BASH_SOURCE/..) is
        # WRONG (~/.hermes/), breaking git remote → GH_REPO → gh pr view →
        # branch fallback (impl/475). Pass E2E_REPO_ROOT explicitly and run
        # with cwd=project so git/gh resolve correctly.
        # 2026-08-17 (pipeline-tests CI 修复): 硬编码 macOS 路径在 ubuntu CI
        # 上不存在 → Popen(cwd=...) FileNotFoundError → launch failed Errno 2
        # (main 7+ 次 pipeline-tests 全红)。改为从脚本位置推导 repo 根
        # (scripts/ 上一级), 支持环境变量覆盖 (测试注入)。
        import subprocess as _sp
        # 2026-08-17 (PR #538/#540/#541 实测): cron 副本从 ~/.hermes/scripts/ 运行,
        # _SCRIPT_DIR 上级 (~/.hermes) 无 .git → 旧逻辑 repo 探测失败走 else 分支,
        # E2E_REPO_ROOT/E2E_BRANCH 全不注入 → runner 的 git remote 失败 → GH_REPO 空
        # → gh pr view 失败 → 回退 impl/<PR_NUM> 错误分支 → P0 branch fetch failed。
        # 修复: 无条件注入, repo 根用 manifest.project.repo 推导 (有 GH_TOKEN 即可
        # 用 gh, 不依赖本地 .git)。E2E_BRANCH 由 orchestrator 从事件/PR 拿到, 必传。
        _repo = os.environ.get("E2E_REPO_ROOT_FALLBACK")
        if not _repo or not os.path.exists(os.path.join(_repo, ".git")):
            # 从 PROJECT_REPO (manifest) 推导 repo 本地路径: 优先 ~/workspace/<name>
            import pathlib
            _name = PROJECT_REPO.split("/")[-1] if PROJECT_REPO else "agent-game-test"
            for cand in (os.path.expanduser(f"~/workspace/{_name}"),
                         os.path.expanduser(f"~/workspace/agent-game-test"),
                         os.getcwd()):
                if os.path.exists(os.path.join(cand, ".git")):
                    _repo = cand
                    break
        _env = dict(os.environ)
        if _repo and os.path.exists(os.path.join(_repo, ".git")):
            _env["E2E_REPO_ROOT"] = _repo
        # GH_REPO 已在模块级 setdefault (manifest.project.repo) — runner 依赖它
        # 做 gh pr view --repo; 显式兜底确保存在。
        _env.setdefault("GH_REPO", PROJECT_REPO or "")
        # 2026-08-17: 显式传 E2E_BRANCH — runner 优先用它, 不再回退 impl/<PR_NUM>。
        _env["E2E_BRANCH"] = branch
        proc = _sp.Popen(
            ["bash", runner, str(pr), "--no-comment", "--skip-visual"],
            stdout=open(log_path, "w"), stderr=_sp.STDOUT,
            start_new_session=True, cwd=_repo, env=_env,
        )
        _write_e2e_state(pr, {
            "status": "running",
            "pid": proc.pid,
            "started_at": time.time(),
            "branch": branch,
            "summary": f"/tmp/e2e-{pr}/summary.json",
            "log": log_path,
            # 2026-08-19 (#572 缺陷 A): 记录本次轮次的 commit sha —
            # fresh_ci 重放检测靠它 (同 sha + 已终态 → 跳过重置)。
            "sha": sha,
        })
        lines.append(f"E2E: pr={pr} started (pid {proc.pid}) — {branch} (log {log_path})")
    except Exception as e:
        lines.append(f"E2E: pr={pr} launch failed: {e}")
        # fall back to agent-driven review so we never stall
        lines.append(f"SPAWN: review,issue={pr},pr={pr},branch={branch}")
    return lines


def _read_review_conclusions_file(pr: int) -> bool:
    """True if a pending review-conclusion file exists for this PR."""
    try:
        os.makedirs(REVIEW_CONCLUSIONS_DIR, exist_ok=True)
        return os.path.exists(os.path.join(REVIEW_CONCLUSIONS_DIR, f"{pr}.json"))
    except OSError:
        return False


# 2026-08-19 (P2 骨架): 结论文件 verdict 规范枚举 — 骨架注释与校验共用。
# 脚本完整接受集含历史变体 (approve/changes_requested/reject/no_merge),
# 骨架只引导 agent 写规范四值。
REVIEW_VERDICTS = ("approved", "blocked", "self_correct", "request_changes")


def _ensure_conclusion_skeleton(pr: int) -> None:
    """2026-08-19 (P2 骨架生成): SPAWN review 时预生成结论文件骨架。

    根治 #516/#562 自由文本契约: review agent 不再从零写 JSON,
    只填受控字段 (verdict/class/evidence)。骨架已存在的 (重审) 不覆盖。
    """
    try:
        os.makedirs(REVIEW_CONCLUSIONS_DIR, exist_ok=True)
        path = os.path.join(REVIEW_CONCLUSIONS_DIR, f"{pr}.json")
        if os.path.exists(path):
            return
        with open(path, "w") as f:
            json.dump({
                "pr": pr,
                "verdict": None,   # 填: approved | blocked | self_correct | request_changes
                "class": None,     # 填: A | B | C | D (failure class)
                "parent_issue": None,
                "fix_issue": None,
                "evidence": "",
            }, f, indent=2)
        _devlog("conclusion-skeleton", pr=pr, path=path)
    except OSError:
        pass


def _mark_reviewed(pr: int) -> None:
    """2026-08-17 (方案 X): 结论已消费 → e2e-state 标记 reviewed.

    watchdog 的 review-stuck 检测只盯 status==done 的 PR — 消费后若不
    标记, done+emitted_at+无结论文件会让已 review 的 PR 误报"卡住"。
    fresh_ci 重置 (新 commit) 会覆盖此状态, 开始新轮次。
    """
    try:
        path = _e2e_state_path(pr)
        if os.path.exists(path):
            st = _read_e2e_state(pr)
            st["status"] = "reviewed"
            _write_e2e_state(pr, st)
    except OSError:
        pass


def _try_merge(pr: int) -> bool:
    """Deterministic approve-merge (2026-08-17, 方案 X #2 配套).

    The review agent only JUDGES (writes the conclusion file); the mechanical
    merge is executed here — LLM 只做判定, merge 必须脚本化 (用户铁律).
    Returns True on success or when the PR is already merged/closed; False on
    conflict/error, in which case the caller keeps the conclusion file and
    retries next tick (a new commit meanwhile triggers fresh_ci reset, which
    starts a new review round on the updated branch — self-healing).
    """
    try:
        raw = gh("pr", "view", str(pr), "--json", "state,mergeable")
        if not raw:
            return False
        info = json.loads(raw)
        if info.get("state") != "OPEN":
            return True  # already merged/closed — nothing to do
        if info.get("mergeable") != "MERGEABLE":
            return False
        return bool(gh("pr", "merge", str(pr), "--squash", "--delete-branch"))
    except Exception:
        return False


def _read_review_conclusions() -> list:
    """Read all pending review-conclusion JSON files.

    2026-08-19 (#562 根治): JSON 解析失败的文件不再静默跳过 —
    devlog 告警 review-verdict-invalid (校验器层, 防非法文件滞留不被发现)。
    """
    out = []
    try:
        os.makedirs(REVIEW_CONCLUSIONS_DIR, exist_ok=True)
        for fn in sorted(os.listdir(REVIEW_CONCLUSIONS_DIR)):
            if not fn.endswith(".json"):
                continue
            path = os.path.join(REVIEW_CONCLUSIONS_DIR, fn)
            try:
                with open(path) as f:
                    data = json.load(f)
                out.append((fn, data))
            except (json.JSONDecodeError, OSError) as e:
                _devlog("review-verdict-invalid", file=fn, reason=str(e),
                        level="warning")
                continue
    except OSError:
        return out
    return out


def _has_blocked_label(target: str, num: int) -> bool:
    """Check if PR/issue already has status/blocked."""
    raw = gh(target, "view", str(num), "--json", "labels", "--jq", ".labels[].name")
    return bool(raw) and "status/blocked" in raw


def _find_fix_issue(fset_hash: str):
    """Search for an existing open fix issue with this fset hash."""
    raw = gh("issue", "list", "--search", f"[fset:{fset_hash}] in:title",
             "--state", "open", "--json", "number", "--jq", ".[0].number")
    try:
        return int(raw) if raw and raw.strip() else None
    except (ValueError, TypeError):
        return None


def review_followup() -> list:
    """Deterministic review follow-through. Returns output lines."""
    lines = []
    for fn, data in _read_review_conclusions():
        try:
            pr = int(data.get("pr", 0))
            # 2026-08-19 (P2 骨架, 3738e82): verdict=null = 骨架预生成待 review
            # agent 填值 — 合法瞬态, 不归一化不告警不消费 (watchdog 对滞留骨架
            # 单独告警)。实测 #567/#570: 骨架 13:46 生成 → review agent 13:52
            # 填值消费, 旧逻辑每 tick devlog review-verdict-unknown 刷屏。
            if data.get("verdict") is None:
                continue
            # 2026-08-19 (#562 死锁修复): review agent 可能写复合值
            # ("approve / merge"、"approved, with notes") → 取第一段再匹配。
            # 旧实现只 strip+lower → "approve / merge" 落 else → 提前终态死锁。
            verdict = str(data.get("verdict", "")).strip().lower()
            verdict = re.split(r"[/|,，;；]", verdict)[0].strip()
            parent = data.get("parent_issue")
            fix = data.get("fix_issue") or {}
            evidence = data.get("evidence", "")
            if pr <= 0:
                continue

            if verdict == "blocked":
                if not _has_blocked_label("pr", pr):
                    gh("pr", "edit", str(pr), "--add-label", "status/blocked")
                    lines.append(f"FOLLOWUP: pr={pr} +status/blocked")
                if parent:
                    if not _has_blocked_label("issue", int(parent)):
                        gh("issue", "edit", str(parent), "--add-label", "status/blocked")
                        lines.append(f"FOLLOWUP: issue={parent} +status/blocked")
                fix_num = None
                if fix and fix.get("title"):
                    failures = fix.get("failures") or []
                    fset_str = "|".join(sorted(failures)) if failures else f"pr{pr}"
                    import hashlib
                    fset_hash = hashlib.md5(fset_str.encode()).hexdigest()[:8]
                    existing = _find_fix_issue(fset_hash)
                    fix_num = existing
                    if existing is None:
                        body = (f"**Blocked PR:** #{pr}\n\n"
                                f"**Pre-existing failures:**\n"
                                + "\n".join(f"- {f}" for f in failures)
                                + f"\n\n**Source:** review conclusion {fn}")
                        title = fix.get("title",
                                        f"Fix pre-existing failures on main [fset:{fset_hash}]")
                        created = gh("issue", "create", "--title", title,
                                     "--label", "bug", "--label", "workflow/available",
                                     "--label", "priority/high", "--body", body)
                        if created:
                            # gh issue create returns the URL — extract number
                            m = re.search(r"/(\d+)/?$", str(created).strip())
                            if m:
                                fix_num = int(m.group(1))
                            lines.append(f"FOLLOWUP: pr={pr} fix issue created #{fix_num}")
                    else:
                        lines.append(f"FOLLOWUP: pr={pr} fix issue exists #{existing} (dedup)")
                comment = (f"## Review Follow-Through (automated)\n\n"
                           f"**结论:** blocked (class {data.get('class', '?')})\n\n{evidence}\n")
                if fix and fix.get("title") and fix_num:
                    # CRITICAL (2026-08-14): the comment MUST carry the real
                    # fix-issue number — check-unblock relies on reading
                    # "Blocked → tracked by #FIX" from the PR comments to find
                    # the actual blocker. Without it, unblock resolved the
                    # WRONG (stale) fix issue (#476 instead of #480).
                    comment += f"\nBlocked → tracked by #{fix_num} (pre-existing)\n"
                gh("pr", "comment", str(pr), "--body", comment)
                lines.append(f"FOLLOWUP: pr={pr} comment posted")
                _mark_reviewed(pr)
            elif verdict in ("approved", "approve"):
                # 2026-08-17 (方案 X #2 配套): approve 的 merge 由脚本执行
                # (确定性, LLM 只判定)。verdict 归一化为小写, "approve"/
                # "approved" 变体都接受 (#516 实证: LLM 写 decision=approve
                # 但 verdict 字段非严格 "approved" → 严格匹配漏 merge)。
                # 成功 → 删文件; 失败 → 保留文件下 tick 幂等重试 — 新
                # commit 会触发 fresh_ci 重置自愈。
                if _try_merge(pr):
                    lines.append(f"FOLLOWUP: pr={pr} approved → merged")
                    _mark_reviewed(pr)
                    # 2026-08-19 (post-merge 阶段落地): merge 事件绑定 post-merge
                    # 任务 — 脚本层创建 pending 状态, post_merge_emitter 同 tick
                    # 发射 SPAWN: post-merge (one-shot) → post-merge agent 写 GDD。
                    _ensure_post_merge_state(pr, parent)
                else:
                    lines.append(f"FOLLOWUP: pr={pr} approved but merge FAILED — file kept, retry next tick")
                    continue  # 不消费, 重试
            else:
                if verdict in ("self_correct", "request_changes",
                               "changes_requested", "reject", "no_merge"):
                    # 已知非 merge verdict: 消费 + 记录。其机械后续
                    # (self-correct label 等) 由 review agent 自行完成;
                    # _mark_reviewed 安全 — 新 commit 会 fresh_ci 重置新轮。
                    lines.append(f"FOLLOWUP: pr={pr} verdict={verdict} recorded")
                    _mark_reviewed(pr)
                else:
                    # 2026-08-19 (#562 死锁修复): 完全未知 verdict 绝不提前
                    # 终态。旧实现: 记录 + _mark_reviewed + 删文件 → reviewed
                    # 终态抑制一切后续 → PR 永不 merge (#562 实测:
                    # verdict="approve / merge" 落 else 死锁)。
                    # 新行为: 保留结论文件 (归一化后下 tick 重试) + devlog
                    # 告警 (不入 lines 避免 cron 刷屏)。持续未知 → watchdog
                    # 检测 review-verdict-unknown → 人工介入。
                    _devlog("review-verdict-unknown", pr=pr, verdict=verdict,
                            file=fn, level="warning")
                    continue  # 不消费、不标记终态
            try:
                os.remove(os.path.join(REVIEW_CONCLUSIONS_DIR, fn))
            except OSError:
                pass
        except Exception as e:
            lines.append(f"FOLLOWUP: ERROR processing {fn}: {e}")
    return lines


def opencode_healthy() -> bool:
    """True when OpenCode Serve is up AND its provider can be reached.

    Uses /global/health (returns JSON {healthy:bool}) — /health returns HTML
    (200 even when the LLM backend is broken), so it can't distinguish.
    """
    try:
        with urllib.request.urlopen(OPENCODE_HEALTH_URL, timeout=3) as r:
            d = json.loads(r.read().decode())
            return bool(d.get("healthy"))
    except Exception:
        return False


def _pause_workflow(reason: str) -> bool:
    """Auto-pause workflow (writes workflow-config.json enabled=false).

    Introduced 2026-08-13 (A+C revert follow-up): OpenCode is the MANDATORY
    path for implement. If it goes down mid-flight, agents fall back to manual
    writes, burn the call budget, and stall with dirty worktrees. Instead of
    letting that happen, a critical infra failure pauses the whole workflow
    until a human fixes the dependency.
    """
    try:
        cfg_path = WORKFLOW_CONFIG
        cfg = {}
        if os.path.exists(cfg_path):
            with open(cfg_path) as f:
                cfg = json.load(f)
        cfg["enabled"] = False
        cfg["paused_reason"] = reason
        cfg["paused_at"] = datetime.datetime.now().isoformat()
        with open(cfg_path, "w") as f:
            json.dump(cfg, f, indent=2)
        # marker file for cross-tick visibility (watchdog reads it)
        with open(OPENCODE_CRITICAL_FILE, "w") as f:
            f.write(reason)
        return True
    except Exception:
        return False


def health_check() -> str:
    """One-line health check. Returns e.g. [HEALTH] gateway=200 ngrok=UP webhook=OK.

    OpenCode is a HARD dependency (implement's only code path). If it is down:
      - auto-pause the workflow (write workflow-config.json enabled=false)
      - emit [CRITICAL] so the cron LLM surfaces it to the user immediately
    """
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
    if opencode_healthy():
        parts.append("opencode=UP")
    else:
        parts.append("opencode=DOWN")
        _pause_workflow("opencode-down (auto-paused by health_check)")
    parts.append("webhook=OK" if check_webhook_connectivity() else "webhook=FAIL")
    line = f"[HEALTH] {' '.join(parts)}"
    if "opencode=DOWN" in line:
        return line + " [CRITICAL] OpenCode down — workflow auto-paused. Fix `~/.config/opencode/opencode.jsonc` / restart serve, then `/workflow resume`."
    return line


if __name__ == "__main__":
    main()
