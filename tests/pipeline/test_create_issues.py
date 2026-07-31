#!/usr/bin/env python3
"""Unit tests for scripts/create-issues.py (game-to-issues Step 6 fix)."""
import importlib.util
import json
import os
import tempfile
import unittest
from unittest import mock

_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
_SCRIPT_PATH = os.path.join(_REPO_ROOT, "scripts", "create-issues.py")

_spec = importlib.util.spec_from_file_location("create_issues", _SCRIPT_PATH)
ci = importlib.util.module_from_spec(_spec)
assert _spec is not None and _spec.loader is not None
_spec.loader.exec_module(ci)


SAMPLE_ISSUES = [
    {"id": 1, "title": "[Feature] A", "description": "d", "context": "c",
     "milestone": "mvp", "labels": ["enhancement", "workflow/backlog"],
     "acceptance_criteria": ["a"], "dependencies": []},
    {"id": 2, "title": "[Feature] B", "description": "d", "context": "c",
     "milestone": "mvp", "labels": ["enhancement", "workflow/backlog"],
     "acceptance_criteria": ["a"], "dependencies": [1]},
    {"id": 3, "title": "[Feature] C", "description": "d", "context": "c",
     "milestone": "v1", "labels": ["enhancement", "workflow/backlog"],
     "acceptance_criteria": ["a"], "dependencies": [2, 1]},
]


class TestTopoSort(unittest.TestCase):
    def test_dependencies_first(self):
        ordered = ci.topo_sort(SAMPLE_ISSUES)
        ids = [i["id"] for i in ordered]
        self.assertLess(ids.index(1), ids.index(2))
        self.assertLess(ids.index(2), ids.index(3))

    def test_cycle_detected(self):
        cyclic = [
            {"id": 1, "dependencies": [2]},
            {"id": 2, "dependencies": [1]},
        ]
        with self.assertRaises(RuntimeError):
            ci.topo_sort(cyclic)

    def test_missing_dep_ignored(self):
        issues = [
            {"id": 1, "dependencies": []},
            {"id": 2, "dependencies": [99]},  # 99 doesn't exist
        ]
        ordered = ci.topo_sort(issues)
        self.assertEqual([i["id"] for i in ordered], [1, 2])


class TestResolveRepo(unittest.TestCase):
    def test_manifest_wins(self):
        with tempfile.TemporaryDirectory() as tmp:
            os.makedirs(os.path.join(tmp, "game-env"))
            manifest_body = "project:\n  repo: devvi/from-manifest\n"
            with open(os.path.join(tmp, "game-env", "manifest.yaml"), "w") as f:
                f.write(manifest_body)
            real_open = open
            with mock.patch("os.getcwd", return_value=tmp), \
                 mock.patch("os.path.exists", return_value=True), \
                 mock.patch("builtins.open", side_effect=lambda p, *a, **k: real_open(p, *a, **k)):
                self.assertEqual(ci.resolve_repo(), "devvi/from-manifest")

    def test_cli_repo_wins(self):
        self.assertEqual(ci.resolve_repo("devvi/cli"), "devvi/cli")

    def test_fallback(self):
        with mock.patch("subprocess.run", return_value=mock.Mock(stdout="")):
            self.assertEqual(ci.resolve_repo(), "devvi/agent-game-test")


class TestCreateFlow(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.plan = os.path.join(self.tmp.name, "plan.json")
        self.data = {"meta": {"status": "draft"}, "issues": json.loads(json.dumps(SAMPLE_ISSUES))}
        with open(self.plan, "w") as f:
            json.dump(self.data, f, ensure_ascii=False)

    def tearDown(self):
        self.tmp.cleanup()

    def test_creates_in_topo_order_with_real_numbers(self):
        """gh returns increasing URLs; bodies must reference real GitHub
        numbers (#40, #41...) not JSON ids (1, 2...)."""
        created_bodies = []

        def fake_run(cmd, **kwargs):
            # git remote get-url → empty (only used when manifest missing)
            if cmd[:2] == ["git", "remote"]:
                return mock.Mock(returncode=0, stdout="")
            # gh issue create → simulate GitHub numbering: A→#40, B→#41, C→#42
            title = cmd[cmd.index("--title") + 1]
            body = cmd[cmd.index("--body") + 1]
            created_bodies.append((title, body))
            num = {"[Feature] A": 40, "[Feature] B": 41, "[Feature] C": 42}[title]
            return mock.Mock(returncode=0,
                             stdout=f"https://github.com/devvi/agent-game-test/issues/{num}\n")

        with mock.patch("subprocess.run", side_effect=fake_run), \
             mock.patch("sys.argv", ["create-issues.py", self.plan, "--repo", "devvi/test"]):
            ci.main()

        # JSON ids → GitHub numbers in dependency bodies
        bodies_by_title = dict(created_bodies)
        self.assertNotIn("## 前置依赖", bodies_by_title["[Feature] A"])
        self.assertIn("## 前置依赖\n#40", bodies_by_title["[Feature] B"])
        # C depends on [2, 1] → mapped to [#41, #40] (topological id order preserved)
        self.assertIn("## 前置依赖\n#41, #40", bodies_by_title["[Feature] C"])
        self.assertNotIn("#2", bodies_by_title["[Feature] C"].split("## 前置依赖")[1])

        # github_number written back
        with open(self.plan) as f:
            saved = json.load(f)
        nums = {i["title"]: i["github_number"] for i in saved["issues"]}
        self.assertEqual(nums["[Feature] A"], 40)
        self.assertEqual(nums["[Feature] C"], 42)
        self.assertEqual(saved["meta"]["status"], "created")

    def test_cycle_exits_1(self):
        cyclic = {"meta": {}, "issues": [
            {"id": 1, "title": "x", "description": "", "context": "",
             "labels": [], "acceptance_criteria": [], "dependencies": [2]},
            {"id": 2, "title": "y", "description": "", "context": "",
             "labels": [], "acceptance_criteria": [], "dependencies": [1]},
        ]}
        with open(self.plan, "w") as f:
            json.dump(cyclic, f)
        with mock.patch("sys.argv", ["create-issues.py", self.plan]), \
             self.assertRaises(SystemExit) as cm:
            ci.main()
        self.assertEqual(cm.exception.code, 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
