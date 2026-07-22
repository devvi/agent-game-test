#!/usr/bin/env python3
"""Ad-hoc verification: validate key GDScript files + TSCN + project config exist."""
import re, os, sys

BASE = "/Users/devvi/workspace/agent-game-test"
KEY_FILES = [
    "gdscripts/narrative_manager.gd", "gdscripts/scene_base.gd",
    "gdscripts/state_system.gd", "gdscripts/game_manager.gd", "gdscripts/constants.gd",
    "gdscripts/office.gd", "gdscripts/lobby.gd", "gdscripts/store.gd",
    "gdscripts/bridge.gd", "gdscripts/underpass.gd", "gdscripts/subway_station.gd",
    "gdscripts/dialogue_runner.gd", "gdscripts/dialogue_parser.gd", "gdscripts/dialogue_condition_evaluator.gd",
]
KEY_TSCN = [
    "scenes/office/office.tscn", "scenes/lobby/lobby.tscn",
    "scenes/store/convenience_store.tscn", "scenes/bridge/bridge.tscn",
    "scenes/underpass/underpass.tscn", "scenes/subway_station/subway_station.tscn",
]

errors = 0
passes = 0

for relpath in KEY_FILES:
    path = os.path.join(BASE, relpath)
    if not os.path.exists(path):
        print(f"[FAIL] {relpath} — file not found"); errors += 1; continue
    with open(path) as f:
        content = f.read()
    if "extends" in content:
        print(f"[PASS] {relpath} — exists, has extends"); passes += 1
    else:
        print(f"[FAIL] {relpath} — missing extends"); errors += 1

for relpath in KEY_TSCN:
    path = os.path.join(BASE, relpath)
    if not os.path.exists(path):
        print(f"[FAIL] {relpath} — not found"); errors += 1; continue
    with open(path) as f:
        c = f.read()
    ok = c.startswith("[gd_scene") and "ext_resource" in c
    print(f"[{'PASS' if ok else 'FAIL'}] {relpath} — valid TSCN"); passes += ok; errors += 0 if ok else 1

proj_path = os.path.join(BASE, "project.godot")
with open(proj_path) as f:
    proj = f.read()
if 'NarrativeManager="*res://gdscripts/narrative_manager.gd"' in proj:
    print(f"[PASS] project.godot — NarrativeManager autoload"); passes += 1
else:
    print(f"[FAIL] project.godot — missing NarrativeManager"); errors += 1

with open(os.path.join(BASE, "gdscripts/constants.gd")) as f:
    consts = f.read()
for c in ["SCENE_ORDER", "SCENE_PATHS", "ENDING_KEEP_WALKING_HOPE",
          "ENDING_TURN_BACK_CONVICTION", "ECHO_RAIN", "ECHO_SCREENSAVER"]:
    if c in consts:
        passes += 1
    else:
        print(f"[FAIL] constants.gd — missing {c}"); errors += 1

with open(os.path.join(BASE, "gdscripts/narrative_manager.gd")) as f:
    nm = f.read()
for sig in ["scene_text_changed", "echo_triggered", "ending_determined"]:
    if f"signal {sig}" in nm:
        passes += 1
    else:
        print(f"[FAIL] narrative_manager.gd — missing signal {sig}"); errors += 1

with open(os.path.join(BASE, "gdscripts/state_system.gd")) as f:
    ss = f.read()
if "get_state_tier" in ss:
    print(f"[PASS] state_system.gd — has get_state_tier()"); passes += 1
else:
    print(f"[FAIL] state_system.gd — missing get_state_tier()"); errors += 1

tests_path = os.path.join(BASE, "tests/test_narrative_architecture.gd")
if os.path.exists(tests_path):
    with open(tests_path) as f:
        tests = f.read()
    test_fns = re.findall(r'func test_(\w+)', tests)
    print(f"[PASS] test_narrative_architecture.gd — {len(test_fns)} tests: {', '.join(test_fns[:6])}..."); passes += 1
else:
    print(f"[FAIL] test_narrative_architecture.gd — not found"); errors += 1

print(f"\n=== Structure Validation: {passes} passed, {errors} failed ===")
sys.exit(1 if errors > 0 else 0)
