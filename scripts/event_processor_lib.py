#!/usr/bin/env python3
"""Pure-logic core of the workflow event preprocessor.

Split from event-processor.py (2026-07-31, P1-7) so the deterministic
decision functions are unit-testable in isolation and the main script
becomes a thin orchestrator (IO + gh + scheduling).

This module MUST NOT:
  - call gh / subprocess / network
  - read or write the pending file
  - depend on the ~/.hermes environment at import time

The only file access is read_workflow_config() reading the config JSON
(mocked in tests via WORKFLOW_CONFIG override).
"""
from __future__ import annotations

import datetime
import json
import os
import re

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

WORKFLOW_CONFIG = os.path.expanduser("~/.hermes/workflow-config.json")


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
        # Multi-window presets (e.g. best-deepseek) are authoritative — a single
        # [start, end] pair cannot express non-contiguous windows, so explicit
        # work_start_hour/work_end_hour in the file must NOT clobber them.
        # (2026-07-31 fix: previously explicit hours silently disabled windows.)
        if "work_windows" in preset:
            config["work_windows"] = preset["work_windows"]
        # Simple presets: explicit file hours override preset defaults
        elif "work_start_hour" not in config or config["work_start_hour"] == DEFAULT_CONFIG["work_start_hour"]:
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


# ── Priority definitions ───────────────────────────────────────────
# Lower number = higher priority
PRIORITY = {
    "check_run.completed": 1,  # CI finished — most urgent
    "issues.labeled": 2,       # Phase start — important
}
PRIORITY_MAX = 99  # For events that should be discarded


# ── Priority labels ───────────────────────────────────────────
PRIORITY_LABEL_ORDER = [
    "priority/critical",
    "priority/high",
    "priority/medium",
    "priority/low",
]


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


# ── Cost governance (P4b, 2026-07-31) ──────────────────────────
# Budget control: count how many self-correct cycles an issue has burned.
# Each cycle ≈ one full diagnose→fix→CI→review round (the expensive part of
# the pipeline). Beyond the threshold, subsequent implement SPAWNs are
# forced to depth=light to cap spend. Pure logic — counting happens in
# event-processor.py (needs gh), the decision lives here.
SELF_CORRECT_THRESHOLD = 3  # cycles before forced downgrade
DOWNGRADE_DEPTH = "light"

# Notification markers used to count cycles (kept in sync with the operator
# agent's Feishu/comment format: "🔄 #N → self-correct")
SELF_CORRECT_MARKERS = ["🔄", "self-correct"]


def depth_for_issue(self_correct_cycles: int, current_depth: str = "standard") -> str:
    """Return the effective depth for an issue given its self-correct burn.

    Rules:
      - current_depth is 'deep' and cycles >= threshold → downgrade to light
      - current_depth is 'standard' and cycles >= threshold → downgrade to light
      - otherwise keep current_depth
    The downgrade is sticky for the rest of the issue's life (implement phase
    is the most expensive; research/plan docs don't need deep depth).
    """
    if self_correct_cycles >= SELF_CORRECT_THRESHOLD:
        return DOWNGRADE_DEPTH
    return current_depth


def count_self_correct_cycles(comments: list) -> int:
    """Count self-correct cycles from an issue's comment bodies.

    A cycle is counted once per comment that mentions a self-correct marker.
    (The operator posts one notification per phase advancement, so each
    self-correct entry is one comment.)
    """
    cycles = 0
    for c in comments:
        body = c.get("body", "") if isinstance(c, dict) else str(c)
        if any(marker in body for marker in SELF_CORRECT_MARKERS):
            cycles += 1
    return cycles
