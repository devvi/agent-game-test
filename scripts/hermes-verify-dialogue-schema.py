#!/usr/bin/env python3
"""Ad-hoc verification: validate all 7 dialogue JSON files against the DialogueParser schema."""
import json
import os
import sys

DIALOGUES_DIR = "/Users/devvi/workspace/agent-game-test/dialogues"
EXPECTED_FILES = [
    "office_door.json",
    "lobby_stranger.json",
    "lobby_guard.json",
    "store_clerk.json",
    "bridge_homeless.json",
    "underpass_stranger_echo.json",
    "subway_ending.json",
]

errors = 0
passes = 0

for fname in EXPECTED_FILES:
    path = os.path.join(DIALOGUES_DIR, fname)
    try:
        with open(path, "r") as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"[FAIL] {fname} — file not found")
        errors += 1
        continue
    except json.JSONDecodeError as e:
        print(f"[FAIL] {fname} — invalid JSON: {e}")
        errors += 1
        continue

    checks = []
    checks.append(("entry_node_id present", "entry_node_id" in data))
    checks.append(("nodes is dict", isinstance(data.get("nodes"), dict)))

    if isinstance(data.get("nodes"), dict) and data["nodes"]:
        entry = data.get("entry_node_id")
        checks.append((f"entry_node '{entry}' exists", entry in data["nodes"]))
        for nid, node in data["nodes"].items():
            checks.append((f"node '{nid}': speaker str", isinstance(node.get("speaker"), str)))
            checks.append((f"node '{nid}': text str", isinstance(node.get("text"), str)))
            if "choices" in node:
                checks.append((f"node '{nid}': choices is array", isinstance(node["choices"], list)))
                for i, c in enumerate(node.get("choices", [])):
                    checks.append((f"node '{nid}' choice[{i}]: is dict", isinstance(c, dict)))
                    if isinstance(c, dict) and c.get("next_node"):
                        checks.append((f"node '{nid}' choice[{i}]: next_node exists", c["next_node"] in data["nodes"]))
                    if isinstance(c, dict) and "condition" in c and c["condition"] is not None:
                        checks.append((f"node '{nid}' choice[{i}]: condition is dict", isinstance(c["condition"], dict)))

    failed = [msg for msg, ok in checks if not ok]
    if failed:
        print(f"[FAIL] {fname} — {len(failed)} check(s) failed:")
        for f in failed:
            print(f"       ✗ {f}")
        errors += len(failed)
    else:
        print(f"[PASS] {fname} — {len(checks)} schema checks OK")
        passes += len(checks)

print(f"\n=== Dialogue JSON Validation: {passes} passed, {errors} failed ===")
sys.exit(1 if errors > 0 else 0)
