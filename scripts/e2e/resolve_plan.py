#!/usr/bin/env python3
"""Resolve a game shot plan into a flat capture plan for a PR diff (v2, 2026-07-31).

Diff-driven archetype selection (P4: framework owns machinery, game owns script):
  - A group activates when ANY of its `match` regexes matches ANY diff file.
  - If no group matches, the `default_archetype` group is used.
  - Activated groups' shots are flattened into the resolved plan (deduped by name).

Usage:
  resolve_plan.py <shot-plan.json> <diff-files.txt> <out-plan.json>

The output is consumed by e2e_capture.gd (framework/templates). Pure logic —
unit-tested in tests/pipeline/test_e2e_resolve.py.
"""
from __future__ import annotations

import json
import re
import sys

# Top-level keys passed through to the capture driver untouched.
_PASSTHROUGH = (
    "game", "main_scene", "max_wall_seconds", "state_node", "state_property",
    "states", "theme_color", "autoplay",
)
# Group-level keys promoted to the resolved plan (first activated group wins).
# 2026-08-20 (#586 gap 1): scene keys joined so group-scoped main_scene /
# state_node / state_property / states are no longer silently dropped.
_GROUP_PROMOTED = (
    "mode", "path", "transcript", "state_trajectory", "fidelity",
    "main_scene", "state_node", "state_property", "states",
)


def select_groups(plan: dict, diff_files: list[str]) -> list[str]:
    """Return activated group names (order preserved from the plan)."""
    groups: dict = plan.get("groups", {})
    if not groups:
        return []
    hit = [str(gname) for gname, g in groups.items()
           if _group_matches(g, diff_files)]
    if hit:
        return hit
    default = plan.get("default_archetype")
    if default in groups:
        return [default]
    return [next(iter(groups))]


def _group_matches(group: dict, diff_files: list[str]) -> bool:
    patterns: list[str] = group.get("match", [])
    if not patterns or not diff_files:
        return False
    return any(re.search(p, f) for p in patterns for f in diff_files)


def resolve(plan: dict, diff_files: list[str]) -> dict:
    activated = select_groups(plan, diff_files)
    groups: dict = plan.get("groups", {})
    resolved: dict = {k: plan[k] for k in _PASSTHROUGH if k in plan}
    shots: list[dict] = []
    seen: set[str] = set()
    # Keys already promoted by an earlier activated group. First activated group
    # wins, and a group-scoped value overrides the top-level passthrough default
    # (e.g. e2e_script declares its own main_scene over the global one).
    group_promoted: set[str] = set()
    for gname in activated:
        g = groups.get(gname, {})
        for s in g.get("shots", []):
            name = s.get("name", "")
            if name and name in seen:
                continue
            if name:
                seen.add(name)
            shots.append(s)
        for k in _GROUP_PROMOTED:
            if k in g and k not in group_promoted:
                resolved[k] = g[k]
                group_promoted.add(k)
    resolved["shots"] = shots
    resolved["groups_activated"] = activated
    return resolved


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__)
        return 2
    plan_path, diff_path, out_path = sys.argv[1:4]
    with open(plan_path, encoding="utf-8") as f:
        plan = json.load(f)
    diff_files = [ln.strip() for ln in open(diff_path, encoding="utf-8") if ln.strip()]
    resolved = resolve(plan, diff_files)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(resolved, f, indent=2, ensure_ascii=False)
    print("activated groups: %s" % ", ".join(resolved["groups_activated"]))
    print("shots: %d" % len(resolved["shots"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
