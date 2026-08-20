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


class TestGroupKeyPromotion(unittest.TestCase):
    """#586 gap 1: group-level main_scene/state_node/state_property/states promotion.

    _GROUP_PROMOTED grows by 4 keys (main_scene, state_node, state_property,
    states) so group-scoped scene keys are no longer silently dropped by
    resolve_plan.py. These tests LOCK that behavior (first activated group wins,
    consistent with existing group-key semantics).
    """

    def test_group_main_scene_promoted(self):
        plan = {
            "game": "mini-pong",
            "default_archetype": "loop",
            "groups": {
                "loop": {
                    "match": [r"gdscripts/.*\.gd"],
                    "shots": [{"name": "01_title", "state": "MENU"}],
                },
                "journey": {
                    "match": [r"dialogue/.*\.json"],
                    "main_scene": "res://scenes/Journey.tscn",
                    "state_node": "/root/Main/JourneyStateMachine",
                    "state_property": "scene_state",
                    "shots": [{"name": "j_open", "state": "SCENE_1"}],
                },
            },
        }
        resolved = rp.resolve(plan, ["dialogue/scene2.json"])
        self.assertEqual(resolved["groups_activated"], ["journey"])
        self.assertEqual(resolved["main_scene"], "res://scenes/Journey.tscn")
        self.assertEqual(resolved["state_node"], "/root/Main/JourneyStateMachine")
        self.assertEqual(resolved["state_property"], "scene_state")
        # a group that does not declare these keys must not introduce them
        # when the top-level plan lacks them either
        resolved = rp.resolve(plan, ["gdscripts/ball.gd"])
        self.assertEqual(resolved["groups_activated"], ["loop"])
        self.assertNotIn("main_scene", resolved)
        self.assertNotIn("state_node", resolved)
        self.assertNotIn("state_property", resolved)

    def test_group_states_promoted(self):
        plan = {
            "game": "mini-pong",
            "default_archetype": "loop",
            "groups": {
                "loop": {
                    "match": [r"gdscripts/.*\.gd"],
                    "shots": [{"name": "01_title", "state": "IDLE"}],
                },
                "journey": {
                    "match": [r"dialogue/.*\.json"],
                    "states": {"IDLE": 0, "MOVE": 1},
                    "shots": [{"name": "j_open", "state": 0}],
                },
            },
        }
        resolved = rp.resolve(plan, ["dialogue/scene2.json"])
        self.assertEqual(resolved["groups_activated"], ["journey"])
        self.assertEqual(resolved["states"], {"IDLE": 0, "MOVE": 1})
        # a group that does not declare states must not introduce the key
        resolved = rp.resolve(plan, ["gdscripts/ball.gd"])
        self.assertEqual(resolved["groups_activated"], ["loop"])
        self.assertNotIn("states", resolved)

    def test_group_overrides_top_level_scene(self):
        # shandong-wolf reality: top-level declares a main_scene, but the
        # activated e2e_script group declares its own rig scene. Group value
        # must win (gap 1 fix: previously the passthrough top-level key
        # blocked promotion so shots ran against the wrong rig).
        plan = {
            "game": "shandong-wolf",
            "default_archetype": "loop",
            "main_scene": "res://scenes/e2e_stick_figure_capture.tscn",
            "state_node": "/root/CaptureRig",
            "state_property": "current_state",
            "groups": {
                "loop": {
                    "match": [r"gdscripts/.*\.gd"],
                    "shots": [{"name": "01_title", "state": "MENU"}],
                },
                "e2e_script": {
                    "match": [r"gdscripts/e2e_main_assembly_capture\.gd"],
                    "main_scene": "res://scenes/e2e_main_assembly_capture.tscn",
                    "state_node": "/root/CaptureRig",
                    "state_property": "current_state",
                    "shots": [{"name": "01_village_open", "state": 0}],
                },
            },
        }
        resolved = rp.resolve(plan, ["gdscripts/e2e_main_assembly_capture.gd"])
        self.assertIn("e2e_script", resolved["groups_activated"])
        self.assertEqual(
            resolved["main_scene"], "res://scenes/e2e_main_assembly_capture.tscn")
        self.assertEqual(resolved["state_node"], "/root/CaptureRig")
        self.assertEqual(resolved["state_property"], "current_state")
        # loop-only diff keeps the top-level scene untouched
        resolved = rp.resolve(plan, ["gdscripts/stick_figure.gd"])
        self.assertIn("loop", resolved["groups_activated"])
        self.assertNotIn("e2e_script", resolved["groups_activated"])
        self.assertEqual(
            resolved["main_scene"], "res://scenes/e2e_stick_figure_capture.tscn")

    def test_first_activated_group_wins(self):
        plan = {
            "game": "mini-pong",
            "default_archetype": "loop",
            "groups": {
                "journey": {
                    "match": [r"dialogue/.*\.json"],
                    "main_scene": "res://scenes/Journey.tscn",
                    "shots": [{"name": "j_open", "state": "SCENE_1"}],
                },
                "alt": {
                    "match": [r"alt/.*\.json"],
                    "main_scene": "res://scenes/Alt.tscn",
                    "shots": [{"name": "a_open", "state": "SCENE_2"}],
                },
            },
        }
        resolved = rp.resolve(plan, ["dialogue/scene2.json", "alt/scene.json"])
        self.assertEqual(resolved["groups_activated"], ["journey", "alt"])
        self.assertEqual(resolved["main_scene"], "res://scenes/Journey.tscn")
