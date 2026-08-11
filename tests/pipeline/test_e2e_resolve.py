#!/usr/bin/env python3
"""Unit tests for scripts/e2e/resolve_plan.py — diff-driven archetype selection.

Covers: group activation by diff match, default-archetype fallback, multi-group
activation, shot flattening/dedup, and group-key promotion (transcript,
state_trajectory, fidelity, mode).

Run locally:  python3 -m unittest discover -s tests/pipeline -v
"""
import importlib.util
import os
import unittest

_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
_spec = importlib.util.spec_from_file_location(
    "resolve_plan", os.path.join(_REPO_ROOT, "scripts", "e2e", "resolve_plan.py"))
rp = importlib.util.module_from_spec(_spec)
assert _spec is not None and _spec.loader is not None
_spec.loader.exec_module(rp)

PLAN = {
    "game": "mini-pong",
    "default_archetype": "loop",
    "state_node": "/root/Main/GameStateMachine",
    "state_property": "current_state",
    "groups": {
        "loop": {
            "match": [r"gdscripts/.*\.gd", r"scenes/.*\.tscn"],
            "shots": [
                {"name": "01_title", "state": "MENU"},
                {"name": "02_midgame", "state": "PLAYING"},
            ],
        },
        "visual_pause": {
            "match": [r"gdscripts/pause_overlay\.gd"],
            "shots": [{"name": "04_paused", "state": "PAUSED"}],
        },
        "journey": {
            "match": [r"dialogue/.*\.json", r"scenes/scene.*\.tscn"],
            "mode": "journey",
            "path": "neutral",
            "transcript": {"node": "/root/HUD/DialogueLabel", "prop": "text"},
            "state_trajectory": True,
            "shots": [{"name": "j_open", "state": "SCENE_1"}],
        },
    },
}


class TestSelectGroups(unittest.TestCase):
    def test_default_archetype_when_no_match(self):
        self.assertEqual(rp.select_groups(PLAN, ["README.md"]), ["loop"])

    def test_content_diff_activates_journey(self):
        self.assertEqual(
            rp.select_groups(PLAN, ["dialogue/scene2.json"]), ["journey"])

    def test_multiple_groups_activate(self):
        groups = rp.select_groups(
            PLAN, ["gdscripts/ball.gd", "gdscripts/pause_overlay.gd"])
        self.assertEqual(groups, ["loop", "visual_pause"])

    def test_empty_diff_uses_default(self):
        self.assertEqual(rp.select_groups(PLAN, []), ["loop"])

    def test_scene_diff_hits_both_loop_and_journey(self):
        groups = rp.select_groups(PLAN, ["scenes/scene2.tscn"])
        self.assertIn("journey", groups)
        self.assertIn("loop", groups)

    def test_unknown_default_falls_back_first_group(self):
        plan = dict(PLAN, default_archetype="nope")
        self.assertEqual(rp.select_groups(plan, ["README.md"]), ["loop"])


class TestResolve(unittest.TestCase):
    def test_resolve_flattens_and_dedupes(self):
        resolved = rp.resolve(
            PLAN, ["gdscripts/ball.gd", "gdscripts/pause_overlay.gd"])
        names = [s["name"] for s in resolved["shots"]]
        self.assertEqual(names, ["01_title", "02_midgame", "04_paused"])
        self.assertEqual(len(names), len(set(names)), "no duplicate shots")

    def test_resolve_promotes_group_keys(self):
        resolved = rp.resolve(PLAN, ["dialogue/scene2.json"])
        self.assertEqual(resolved["mode"], "journey")
        self.assertEqual(resolved["path"], "neutral")
        self.assertTrue(resolved["state_trajectory"])
        self.assertEqual(resolved["transcript"]["prop"], "text")
        self.assertEqual(resolved["groups_activated"], ["journey"])

    def test_resolve_passthrough_top_level(self):
        resolved = rp.resolve(PLAN, [])
        self.assertEqual(resolved["game"], "mini-pong")
        self.assertEqual(resolved["state_property"], "current_state")


if __name__ == "__main__":
    unittest.main()


class TestDeadlinePassthrough(unittest.TestCase):
    """#372 T6: per-shot deadline_s must survive resolution untouched.

    resolve_plan.py appends shot dicts as-is (no code change needed for
    #372) — this test LOCKS that behavior so a future refactor that strips
    unknown shot keys breaks loudly. Shots WITHOUT deadline_s must not gain
    the key either.
    """

    def test_deadline_s_passthrough(self):
        plan = {
            "game": "mini-pong",
            "default_archetype": "loop",
            "max_wall_seconds": 120,
            "groups": {
                "loop": {
                    "match": [r"gdscripts/.*\.gd"],
                    "shots": [
                        {"name": "01_title", "state": "MENU"},
                        {"name": "02_midgame", "state": "PLAYING",
                         "require": {"node": "/root/GameManager", "prop": "player_score", "min": 1}},
                        {"name": "03_gameover", "state": "GAME_OVER",
                         "settle_frames": 10, "deadline_s": 300},
                    ],
                }
            },
        }
        resolved = rp.resolve(plan, ["mini-pong/gdscripts/ball.gd"])
        by_name = {s["name"]: s for s in resolved["shots"]}
        self.assertIn("03_gameover", by_name)
        self.assertEqual(by_name["03_gameover"].get("deadline_s"), 300)
        self.assertEqual(by_name["03_gameover"].get("settle_frames"), 10)
        # shots without the field must not gain the key
        self.assertNotIn("deadline_s", by_name["01_title"])
        self.assertNotIn("deadline_s", by_name["02_midgame"])

    def test_global_max_wall_seconds_still_passthrough(self):
        plan = {
            "game": "mini-pong",
            "default_archetype": "loop",
            "max_wall_seconds": 120,
            "groups": {"loop": {"match": [r"gdscripts/.*\.gd"],
                                "shots": [{"name": "01_title", "state": "MENU"}]}},
        }
        resolved = rp.resolve(plan, ["mini-pong/gdscripts/ball.gd"])
        self.assertEqual(resolved["max_wall_seconds"], 120)
