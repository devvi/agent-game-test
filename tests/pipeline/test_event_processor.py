#!/usr/bin/env python3
"""Unit tests for event-processor.py — the pipeline's deterministic core.

Run locally:  python3 -m unittest discover -s tests/pipeline -v
Run in CI:    .github/workflows/pipeline-tests.yml (on scripts/ changes)

Constraints:
  - Must NOT require network, gh CLI, or the ~/.hermes environment.
  - All gh() calls must be mocked.
  - Tests the PURE functions: parsing, prioritization, time windows,
    grouping/dedup, and the issue picker.
"""
import glob
import importlib.util
import json
import os
import re
import sys
import tempfile
import time
import unittest
from unittest import mock

_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
_SCRIPT_PATH = os.path.join(_REPO_ROOT, "scripts", "event-processor.py")

_spec = importlib.util.spec_from_file_location("event_processor", _SCRIPT_PATH)
ep = importlib.util.module_from_spec(_spec)
assert _spec is not None and _spec.loader is not None
_spec.loader.exec_module(ep)


def _active_game() -> str:
    """Read game.active from manifest (mirror of event-processor parsing).

    SPAWN assertions depend on the active game; parameterizing keeps tests
    green across game switches (2026-08-19: mini-pong → shandong-wolf).
    """
    mf = os.path.join(_REPO_ROOT, "game-env", "manifest.yaml")
    try:
        txt = open(mf, encoding="utf-8").read()
    except OSError:
        return "mini-pong"
    m = re.search(r"^game:\s*$", txt, re.M)
    if m:
        am = re.search(r"active:\s*(\S+)", txt[m.end():m.end() + 200])
        if am:
            return am.group(1)
    return "mini-pong"



class TestParseDependencies(unittest.TestCase):
    def test_english_full_deps(self):
        body = "## Dependencies\nDepends on: #42\n"
        self.assertEqual(ep.parse_dependencies(body), [{"issue": 42, "type": "full"}])

    def test_english_design_deps(self):
        body = "## Dependencies\nDepends on (design): #49\n"
        self.assertEqual(ep.parse_dependencies(body), [{"issue": 49, "type": "design"}])

    def test_chinese_heading_and_bare_refs(self):
        body = "## 前置依赖\n#42, #43\n"
        deps = ep.parse_dependencies(body)
        self.assertEqual(len(deps), 2)
        self.assertIn({"issue": 42, "type": "full"}, deps)
        self.assertIn({"issue": 43, "type": "full"}, deps)

    def test_dedup_within_section(self):
        body = "## Dependencies\nDepends on: #42\n#42\n"
        deps = ep.parse_dependencies(body)
        self.assertEqual(len(deps), 1)

    def test_no_deps_section(self):
        self.assertEqual(ep.parse_dependencies("No deps here #99"), [])

    def test_exits_at_next_heading(self):
        body = "## Dependencies\nDepends on: #42\n## Acceptance Criteria\n#43 not a dep\n"
        self.assertEqual(ep.parse_dependencies(body), [{"issue": 42, "type": "full"}])

    def test_unknown_dep_type_defaults_to_full(self):
        body = "## Dependencies\nDepends on (weird): #7\n"
        self.assertEqual(ep.parse_dependencies(body), [{"issue": 7, "type": "full"}])


class TestUnresolvedDependencies(unittest.TestCase):
    """Tests for _has_unresolved_dependencies — v4 human-review queue semantics.

    v4 (2026-08-11): taste-draft Issues get status/human-review after draft
    merge. Human Issue does NOT enter the dependency chain — a dependency
    carrying status/human-review counts as resolved (draft merged, waiting
    for human calibration, downstream may proceed on the draft structure).
    """

    def _call(self, issues_cache, issue_num=100):
        with mock.patch.object(ep, "_ensure_issues_cache", return_value=issues_cache):
            return ep._has_unresolved_dependencies(issue_num)

    def _issue(self, number, labels):
        return {"number": number, "labels": [{"name": l} for l in labels],
                "body": "## 前置依赖\n#1\n"}

    def test_human_review_dep_counts_as_resolved(self):
        """Dependency with status/human-review (draft merged, awaiting human)
        must NOT block the downstream issue."""
        dep = self._issue(1, ["status/human-review"])
        parent = self._issue(100, ["workflow/available"])
        parent["body"] = "## 前置依赖\nDepends on: #1\n"
        unresolved = self._call([dep, parent])
        self.assertEqual(unresolved, [], "human-review dep = resolved (v4 queue)")

    def test_open_dep_without_done_label_is_unresolved(self):
        """Open dependency with no status/done or status/human-review is still unresolved."""
        dep = self._issue(1, ["workflow/implement"])
        parent = self._issue(100, ["workflow/available"])
        parent["body"] = "## 前置依赖\nDepends on: #1\n"
        unresolved = self._call([dep, parent])
        self.assertEqual(len(unresolved), 1, "open dep without done label blocks")

    def test_status_done_dep_counts_as_resolved(self):
        """status/done dependency remains resolved (existing behavior preserved)."""
        dep = self._issue(1, ["status/done"])
        parent = self._issue(100, ["workflow/available"])
        parent["body"] = "## 前置依赖\nDepends on: #1\n"
        unresolved = self._call([dep, parent])
        self.assertEqual(unresolved, [], "status/done dep = resolved")

    def test_closed_dep_without_done_counts_as_unresolved(self):
        """2026-08-13 semantics change: a CLOSED dependency without
        status/done (or status/human-review) is a suspicious early closure
        (#384/#390 closed while their code only landed in unmerged #444) —
        it must NOT count as resolved. Dependents stay blocked."""
        # Only the parent is in the cache — dep #1 is closed (not listed)
        parent = self._issue(100, ["workflow/available"])
        parent["body"] = "## 前置依赖\nDepends on: #1\n"
        unresolved = self._call([parent])
        self.assertEqual(len(unresolved), 1, "closed-without-done dep blocks")
        self.assertEqual(unresolved[0]["issue"], 1)
        self.assertTrue(unresolved[0].get("closed_without_done"))


class TestEventPriority(unittest.TestCase):
    def test_check_run_completed_actionable(self):
        ev = {"_key": "check_run.completed#154", "type": "check_run",
              "branch": "impl/154-x", "conclusion": "failure"}
        self.assertEqual(ep.event_priority(ev), 1)

    def test_check_run_completed_success(self):
        ev = {"_key": "check_run.completed#154", "type": "check_run",
              "branch": "impl/154-x", "conclusion": "success"}
        self.assertEqual(ep.event_priority(ev), 1)

    def test_check_run_incomplete_forwarded(self):
        ev = {"_key": "check_run.completed#154", "type": "check_run",
              "branch": "impl/154-x", "conclusion": ""}
        self.assertEqual(ep.event_priority(ev), 2)

    def test_check_run_empty_discard(self):
        ev = {"_key": "check_run.completed#154", "type": "check_run"}
        self.assertEqual(ep.event_priority(ev), ep.PRIORITY_MAX)

    def test_issues_labeled_workflow(self):
        ev = {"_key": "issues.labeled#154:workflow/plan", "type": "issues.labeled",
              "label": "workflow/plan"}
        self.assertEqual(ep.event_priority(ev), 2)

    def test_issues_labeled_lock_discard(self):
        ev = {"_key": "issues.labeled#154:workflow/lock-pi", "type": "issues.labeled",
              "label": "workflow/lock-pi"}
        self.assertEqual(ep.event_priority(ev), ep.PRIORITY_MAX)

    def test_issues_labeled_non_workflow_discard(self):
        ev = {"_key": "issues.labeled#154:enhancement", "type": "issues.labeled",
              "label": "enhancement"}
        self.assertEqual(ep.event_priority(ev), ep.PRIORITY_MAX)

    def test_pull_request_discard(self):
        ev = {"_key": "pull_request.opened#154", "type": "pull_request"}
        self.assertEqual(ep.event_priority(ev), ep.PRIORITY_MAX)

    def test_should_discard(self):
        self.assertTrue(ep.should_discard({"type": "pull_request"}))
        self.assertFalse(ep.should_discard(
            {"_key": "check_run.completed#1", "type": "check_run",
             "branch": "impl/1", "conclusion": "success"}))


class TestValidateCheckRun(unittest.TestCase):
    def test_valid(self):
        ev = {"_key": "check_run.completed#1", "type": "check_run",
              "branch": "impl/1-x", "conclusion": "success"}
        self.assertTrue(ep.validate_check_run(ev))

    def test_missing_branch_invalid(self):
        ev = {"_key": "check_run.completed#1", "type": "check_run", "conclusion": "success"}
        self.assertFalse(ep.validate_check_run(ev))

    def test_skipped_invalid(self):
        ev = {"_key": "check_run.completed#1", "type": "check_run",
              "branch": "research/1", "conclusion": "skipped"}
        self.assertFalse(ep.validate_check_run(ev))

    def test_non_check_run_passes(self):
        self.assertTrue(ep.validate_check_run({"type": "issues.labeled", "label": "workflow/plan"}))


class TestTimeWindow(unittest.TestCase):
    def test_daytime_within(self):
        cfg = {"enabled": True, "work_start_hour": 8, "work_end_hour": 22}
        with mock.patch.object(ep.datetime, "datetime") as dt:
            dt.now.return_value.hour = 12
            self.assertTrue(ep._time_in_window(cfg))

    def test_daytime_outside(self):
        cfg = {"enabled": True, "work_start_hour": 8, "work_end_hour": 22}
        with mock.patch.object(ep.datetime, "datetime") as dt:
            dt.now.return_value.hour = 23
            self.assertFalse(ep._time_in_window(cfg))

    def test_wrapping_window(self):
        cfg = {"enabled": True, "work_start_hour": 23, "work_end_hour": 8}
        with mock.patch.object(ep.datetime, "datetime") as dt:
            dt.now.return_value.hour = 2
            self.assertTrue(ep._time_in_window(cfg))
            dt.now.return_value.hour = 15
            self.assertFalse(ep._time_in_window(cfg))

    def test_multi_window_preset(self):
        cfg = {"enabled": True, "work_windows": [[0, 9], [12, 14], [18, 24]]}
        with mock.patch.object(ep.datetime, "datetime") as dt:
            for hour, expected in [(6, True), (10, False), (13, True), (15, False), (20, True)]:
                dt.now.return_value.hour = hour
                self.assertEqual(ep._time_in_window(cfg), expected, f"hour={hour}")


class TestReadWorkflowConfig(unittest.TestCase):
    """Regression tests for the 2026-07-31 preset-window merge fix."""

    # read_workflow_config lives in event_processor_lib (split P1-7);
    # mock the lib's WORKFLOW_CONFIG constant, not the main module's.
    LIB = __import__("event_processor_lib")

    def _write_config(self, tmpdir, content):
        path = os.path.join(tmpdir, "workflow-config.json")
        with open(path, "w") as f:
            json.dump(content, f)
        return path

    def test_best_deepseek_windows_not_clobbered_by_explicit_hours(self):
        """The bug: explicit work_start_hour/work_end_hour in the file silently
        disabled the best-deepseek multi-window preset. Fix: windows are authoritative."""
        with tempfile.TemporaryDirectory() as tmp:
            cfg_path = self._write_config(tmp, {
                "enabled": True, "preset": "best-deepseek",
                "work_start_hour": 0, "work_end_hour": 8,
            })
            with mock.patch.object(self.LIB, "WORKFLOW_CONFIG", cfg_path):
                merged = ep.read_workflow_config()
            self.assertEqual(merged.get("work_windows"), [[0, 9], [12, 14], [18, 24]])

    def test_simple_preset_explicit_hours_override(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg_path = self._write_config(tmp, {
                "enabled": True, "preset": "daytime",
                "work_start_hour": 10, "work_end_hour": 18,
            })
            with mock.patch.object(self.LIB, "WORKFLOW_CONFIG", cfg_path):
                merged = ep.read_workflow_config()
            self.assertEqual(merged["work_start_hour"], 10)
            self.assertEqual(merged["work_end_hour"], 18)

    def test_defaults_when_no_config(self):
        with mock.patch.object(self.LIB, "WORKFLOW_CONFIG", "/definitely/missing.json"):
            merged = ep.read_workflow_config()
        self.assertTrue(merged["enabled"])
        self.assertEqual(merged["work_start_hour"], 8)
        self.assertEqual(merged["work_end_hour"], 22)


class TestPreprocess(unittest.TestCase):
    """Grouping, dedup, and SPAWN generation — the script's core contract."""

    def _events(self, *evs):
        return list(evs)

    def _run_preprocess(self, events, fake_run=None, spawn_state_file=None,
                        issue_cache=None, opencode_up=True):
        # Mock the subprocess gh call inside preprocess (PR body lookup) so
        # tests stay hermetic and fast. Empty body → no parent match → falls
        # back to issue=PR number.
        if fake_run is None:
            fake_run = mock.Mock(return_value=mock.Mock(stdout=""))
        if spawn_state_file is None:
            spawn_state_file = os.path.join(tempfile.mkdtemp(), "spawned.json")
        if issue_cache is None:
            issue_cache = []
        with mock.patch.object(ep, "read_pending", return_value=events), \
             mock.patch.object(ep, "write_pending", return_value=None), \
             mock.patch("subprocess.run", fake_run), \
             mock.patch.object(ep, "_is_pr_merged", return_value=False), \
             mock.patch.object(ep, "_is_issue_closed", return_value=False), \
             mock.patch.object(ep, "_extract_parent_issue", return_value=None), \
             mock.patch.object(ep, "_is_pr_blocked", return_value=False), \
             mock.patch.object(ep, "_parent_issue_blocked", return_value=False), \
             mock.patch.object(ep, "_ensure_issues_cache", return_value=issue_cache), \
             mock.patch.object(ep, "_SPAWN_STATE_FILE", spawn_state_file), \
             mock.patch.object(ep, "opencode_healthy", return_value=opencode_up), \
             mock.patch.object(ep, "E2E_STATE_DIR",
                               os.path.join(tempfile.mkdtemp(), "e2e-state")), \
             mock.patch.object(ep, "E2E_RUNNER", "/bin/true"), \
             mock.patch.object(ep, "_GH_CACHE", {}):
            return ep.preprocess()

    def test_check_run_failure_spawns_self_correct(self):
        ev = {"_key": "check_run.completed#154", "type": "check_run",
              "issue": 154, "branch": "impl/154-x", "conclusion": "failure"}
        out = self._run_preprocess(self._events(ev))
        self.assertTrue(any(l.startswith("SPAWN: self-correct,issue=154") for l in out),
                        f"unexpected output: {out}")

    def test_check_run_success_starts_e2e_then_review(self):
        """2026-08-14 plan ②: check_run.completed success for an impl branch
        triggers the E2E orchestrator (background script) instead of directly
        spawning review. First tick: 'E2E: pr started'; review SPAWN appears
        only after the runner finishes (orchestrator harvests summary)."""
        ev = {"_key": "check_run.completed#155", "type": "check_run",
              "issue": 155, "branch": "impl/155-y", "conclusion": "success"}
        with tempfile.TemporaryDirectory() as td:
            with mock.patch.object(ep, "E2E_STATE_DIR", os.path.join(td, "state")), \
                 mock.patch.object(ep, "E2E_RUNNER", "/bin/true"):
                out = self._run_preprocess(self._events(ev))
        self.assertTrue(any(l.startswith("E2E: pr=155 started") for l in out),
                        f"must kick off E2E runner: {out}")
        # review spawns later, once summary is harvested (covered by
        # TestE2EOrchestrator.test_running_dead_harvests_done)

    def test_non_impl_branch_success_emits_merge_pr(self):
        """Non-impl (research/plan) check_run.completed success must NOT be
        emitted as P1 for the LLM to investigate — it becomes a deterministic
        STALLED: merge-pr directive (2026-08-13, 181544 4-min tick trace:
        cron LLM spent 4 min re-checking an already-completed advancement).
        Event is consumed one-shot either way."""
        ev = {"_key": "check_run.completed#156", "type": "check_run",
              "issue": 156, "branch": "plan/156-z", "conclusion": "success"}
        out = self._run_preprocess(self._events(ev))
        self.assertTrue(any(l.startswith("STALLED: merge-pr,pr=156") for l in out),
                        f"unexpected output: {out}")
        self.assertFalse(any(l.startswith("P1:") for l in out),
                         "P1 must never be emitted for non-impl check_run")

    def test_non_impl_branch_failure_silently_dropped(self):
        """Non-impl branch CI failure is not actionable by the cron (no
        self-correct path for research/plan PRs) — dropped with audit;
        the stalled scan re-checks the PR later."""
        ev = {"_key": "check_run.completed#157", "type": "check_run",
              "issue": 157, "branch": "plan/157-q", "conclusion": "failure"}
        out = self._run_preprocess(self._events(ev))
        self.assertFalse(any(l.startswith(("P1:", "SPAWN:", "STALLED:")) for l in out),
                         f"expected no directives, got {out}")

    def test_idle_fast_path_not_silent_when_backlog_exists(self):
        """Backlog-only repo must NOT short-circuit to [SILENT] — the picker
        must run to promote backlog → available (canary #358 regression,
        2026-08-10). Note: [SILENT] may still print at the end when preprocess
        has no events — the regression signal is that pick_next_issue ran."""
        issue = {"number": 358, "labels": [{"name": "workflow/backlog"}]}
        with mock.patch.object(ep, "read_pending", return_value=[]), \
             mock.patch.object(ep, "_ensure_issues_cache", return_value=[issue]), \
             mock.patch.object(ep, "is_paused", return_value=False), \
             mock.patch.object(ep, "_time_in_window", return_value=True), \
             mock.patch.object(ep, "health_check", return_value="ok"), \
             mock.patch.object(ep, "pick_next_issue",
                               return_value=[]) as pick, \
             mock.patch.object(ep, "reconcile_check_runs"), \
             mock.patch.object(ep, "_read_reconcile_state", return_value={}), \
             mock.patch.object(ep, "_write_reconcile_state"), \
             mock.patch.object(ep, "preprocess", return_value=[]), \
             mock.patch.object(ep, "_quick_stalled_scan", return_value=[]), \
             mock.patch.object(ep, "_count_active_phase_agents", return_value=0), \
             mock.patch.object(ep, "_audit"), \
             mock.patch("sys.stdout") as out:
            ep.main()
        pick.assert_called()  # window-entry pick + no-events fallback pick
        output = "".join(str(c.args[0]) for c in out.write.call_args_list)
        self.assertIn("[SILENT]", output,  # expected: no events → silent tail
                      "no SPAWN lines → [SILENT] tail is normal")

    def test_idle_fast_path_silent_when_all_done(self):
        """All issues done + no pending → true idle: picker must NOT run."""
        issue = {"number": 100, "labels": [{"name": "status/done"}]}
        with mock.patch.object(ep, "read_pending", return_value=[]), \
             mock.patch.object(ep, "_ensure_issues_cache", return_value=[issue]), \
             mock.patch.object(ep, "is_paused", return_value=False), \
             mock.patch.object(ep, "_time_in_window", return_value=True), \
             mock.patch.object(ep, "health_check", return_value="ok"), \
             mock.patch.object(ep, "pick_next_issue",
                               return_value=[]) as pick, \
             mock.patch.object(ep, "reconcile_check_runs"), \
             mock.patch.object(ep, "_read_reconcile_state", return_value={}), \
             mock.patch.object(ep, "_write_reconcile_state"), \
             mock.patch.object(ep, "preprocess", return_value=[]), \
             mock.patch.object(ep, "_count_active_phase_agents", return_value=0), \
             mock.patch.object(ep, "_audit"), \
             mock.patch("sys.stdout") as out:
            ep.main()
        pick.assert_not_called()
        output = "".join(str(c.args[0]) for c in out.write.call_args_list)
        self.assertIn("[SILENT]", output)

    def test_spawn_consumes_event_from_pending(self):
        """One-shot SPAWN: after emitting SPAWN, the event must be removed
        from pending — otherwise the next tick re-emits and the cron LLM
        re-delegates (3 research agents for 1 issue, canary #358 2026-08-10)."""
        ev = {"_key": "check_run.completed#155", "type": "check_run",
              "issue": 155, "branch": "impl/155-y", "conclusion": "success"}
        written = []
        with mock.patch.object(ep, "read_pending", return_value=[ev]), \
             mock.patch.object(ep, "write_pending",
                               side_effect=lambda e: written.append(e)), \
             mock.patch("subprocess.run",
                        return_value=mock.Mock(stdout="", returncode=1)), \
             mock.patch.object(ep, "_is_pr_merged", return_value=False), \
             mock.patch.object(ep, "_is_issue_closed", return_value=False), \
             mock.patch.object(ep, "_extract_parent_issue", return_value=None), \
             mock.patch.object(ep, "_is_pr_blocked", return_value=False), \
             mock.patch.object(ep, "_parent_issue_blocked", return_value=False):
            ep.preprocess()
        self.assertGreaterEqual(len(written), 2, "Step 6 + Step 7 rewrites")
        remaining_keys = [e.get("_key") for e in written[-1]]
        self.assertNotIn("check_run.completed#155", remaining_keys,
                         "consumed SPAWN event must leave pending")

    def test_spawn_gate_dedups_plan_within_ttl(self):
        """picker must emit SPAWN: plan once per TTL — the cron LLM delegates
        on every SPAWN line, and re-emission caused 2 concurrent plan agents
        for issue #358 (2026-08-10)."""
        issue = {"number": 358, "labels": [{"name": "workflow/plan"}]}
        calls = {"n": 0}

        def fake_run(cmd, *a, **kw):
            calls["n"] += 1
            joined = " ".join(str(c) for c in cmd)
            if "head:plan/" in joined:  # plan PR search → none exists
                return mock.Mock(stdout="0", returncode=0)
            return mock.Mock(stdout="", returncode=1)

        with tempfile.TemporaryDirectory() as td, \
             mock.patch.object(ep, "_SPAWN_STATE_FILE",
                               os.path.join(td, "spawned.json")), \
             mock.patch.object(ep, "is_paused", return_value=False), \
             mock.patch.object(ep, "current_workflow_count", return_value=9), \
             mock.patch.object(ep, "_pick_candidates", return_value=[]), \
             mock.patch.object(ep, "_ensure_issues_cache",
                               return_value=[issue]), \
             mock.patch("subprocess.run", fake_run):
            first = ep.pick_next_issue()
            second = ep.pick_next_issue()
        self.assertTrue(any("SPAWN: plan,issue=358" in l for l in first),
                        f"first tick must emit SPAWN: {first}")
        self.assertFalse(any("SPAWN: plan,issue=358" in l for l in second),
                         "second tick within TTL must not re-emit SPAWN")

    def test_spawn_gate_reemits_after_ttl(self):
        """TTL expiry re-enables spawning (dead phase-agent recovery)."""
        issue = {"number": 359, "labels": [{"name": "workflow/plan"}]}

        def fake_run(cmd, *a, **kw):
            joined = " ".join(str(c) for c in cmd)
            if "head:plan/" in joined:
                return mock.Mock(stdout="0", returncode=0)
            return mock.Mock(stdout="", returncode=1)

        with tempfile.TemporaryDirectory() as td, \
             mock.patch.object(ep, "_SPAWN_STATE_FILE",
                               os.path.join(td, "spawned.json")), \
             mock.patch.object(ep, "is_paused", return_value=False), \
             mock.patch.object(ep, "current_workflow_count", return_value=9), \
             mock.patch.object(ep, "_pick_candidates", return_value=[]), \
             mock.patch.object(ep, "_ensure_issues_cache",
                               return_value=[issue]), \
             mock.patch("subprocess.run", fake_run):
            first = ep.pick_next_issue()  # t=now → emits, records marker
            # advance clock past TTL
            old_time = ep.time.time
            ep.time.time = lambda: old_time() + ep._SPAWN_TTL_SECONDS + 10
            try:
                second = ep.pick_next_issue()
            finally:
                ep.time.time = old_time
        self.assertTrue(any("SPAWN: plan,issue=359" in l for l in first),
                        f"first tick must emit SPAWN: {first}")
        self.assertTrue(any("SPAWN: plan,issue=359" in l for l in second),
                        "TTL expiry must allow re-spawn")

    def test_available_rescan_no_dup_spawn_within_ttl(self):
        """Available-rescan must NOT re-emit research SPAWN within gate TTL.

        Regression for 2026-08-17 #525/#526/#527: the `research-resend` OR
        branch (independent 5-min marker, always fresh) re-emitted SPAWN
        every tick → 3 concurrent research agents per issue, PR #528 merged
        while duplicates still running. Gate must suppress the 2nd tick even
        when the label path re-runs (deterministic rescan loop).
        """
        issue = {"number": 525, "labels": [{"name": "workflow/available"}]}

        def fake_run(cmd, *a, **kw):
            joined = " ".join(str(c) for c in cmd)
            if "head:research/" in joined:  # no research PR yet
                return mock.Mock(stdout="0", returncode=0)
            return mock.Mock(stdout="", returncode=1)

        with tempfile.TemporaryDirectory() as td, \
             mock.patch.object(ep, "_SPAWN_STATE_FILE",
                               os.path.join(td, "spawned.json")), \
             mock.patch.object(ep, "is_paused", return_value=False), \
             mock.patch.object(ep, "current_workflow_count", return_value=9), \
             mock.patch.object(ep, "_pick_candidates", return_value=[]), \
             mock.patch.object(ep, "_ensure_issues_cache",
                               return_value=[issue]), \
             mock.patch("subprocess.run", fake_run):
            first = ep.pick_next_issue()
            second = ep.pick_next_issue()  # same tick, same state file
        spawns1 = [l for l in first if "SPAWN: research,issue=525" in l]
        spawns2 = [l for l in second if "SPAWN: research,issue=525" in l]
        self.assertEqual(len(spawns1), 1,
                         f"first rescan must spawn exactly once: {spawns1}")
        self.assertEqual(len(spawns2), 0,
                         f"second rescan within TTL must NOT re-spawn: {spawns2}")

    def test_spawn_advances_issue_label_research(self):
        """SPAWN 发出时必须确定性推进 issue lifecycle label
        (available → research)。

        Regression 2026-08-19: c5f8d03 (08-15) 回滚丢失 _advance_issue_label
        后, #559/#572 停在 workflow/available (#572 实测) — 用户靠 label 管理
        issue 生命周期, research 阶段在 label 上不可见。脚本层在 SPAWN 时
        推进, 不依赖 cron LLM 自觉 (v4-flash 实测不执行)。
        """
        issue = {"number": 400, "labels": [{"name": "workflow/available"}]}
        label_calls = []

        def fake_run(cmd, *a, **kw):
            joined = " ".join(str(c) for c in cmd)
            if "head:research/" in joined or "head:plan/" in joined \
                    or "head:impl/" in joined:
                return mock.Mock(stdout="0", returncode=0)
            if "issue" in joined and "edit" in joined:
                label_calls.append(joined)
            return mock.Mock(stdout="", returncode=0)

        with tempfile.TemporaryDirectory() as td, \
             mock.patch.object(ep, "_SPAWN_STATE_FILE",
                               os.path.join(td, "spawned.json")), \
             mock.patch.object(ep, "is_paused", return_value=False), \
             mock.patch.object(ep, "current_workflow_count", return_value=9), \
             mock.patch.object(ep, "_pick_candidates", return_value=[]), \
             mock.patch.object(ep, "_ensure_issues_cache",
                               return_value=[issue]), \
             mock.patch("subprocess.run", fake_run):
            out = ep.pick_next_issue()
        self.assertTrue(any("SPAWN: research,issue=400" in l for l in out),
                        f"must emit research SPAWN: {out}")
        adds = [c for c in label_calls if "--add-label" in c]
        self.assertTrue(any("workflow/research" in c for c in adds),
                        f"must add workflow/research: {label_calls}")
        rems = [c for c in label_calls if "--remove-label" in c]
        self.assertTrue(any("workflow/available" in c for c in rems),
                        f"must remove workflow/available: {label_calls}")

    def test_spawn_label_advance_failure_does_not_block_spawn(self):
        """label 推进失败 (gh 报错) 时 SPAWN 必须照常发出。

        红线 (用户 2026-08-19): 修改绝不能影响 workflow 正常运行 —
        label 写失败是 best-effort, 绝不阻塞 SPAWN 发出。
        """
        issue = {"number": 401, "labels": [{"name": "workflow/available"}]}

        def fake_run(cmd, *a, **kw):
            joined = " ".join(str(c) for c in cmd)
            if "head:research/" in joined or "head:plan/" in joined \
                    or "head:impl/" in joined:
                return mock.Mock(stdout="0", returncode=0)
            if "edit" in joined:  # gh issue edit 失败
                return mock.Mock(stdout="", returncode=1)
            return mock.Mock(stdout="", returncode=0)

        with tempfile.TemporaryDirectory() as td, \
             mock.patch.object(ep, "_SPAWN_STATE_FILE",
                               os.path.join(td, "spawned.json")), \
             mock.patch.object(ep, "is_paused", return_value=False), \
             mock.patch.object(ep, "current_workflow_count", return_value=9), \
             mock.patch.object(ep, "_pick_candidates", return_value=[]), \
             mock.patch.object(ep, "_ensure_issues_cache",
                               return_value=[issue]), \
             mock.patch("subprocess.run", fake_run):
            out = ep.pick_next_issue()
        self.assertTrue(any("SPAWN: research,issue=401" in l for l in out),
                        f"SPAWN must emit even when label advance fails: {out}")

    def test_active_phase_counts_db_running_not_labels(self):
        """active_phase must reflect ACTUAL running delegates, not labels.

        Regression for 2026-08-17: label-based counting treated every open
        issue with a phase label as an active agent → stale labels (advanced
        by workflow-chain, then re-written by duplicate agents) saturated
        MAX_PHASE_SLOTS and silently capped all new SPAWNs. DB-backed count
        must return 0 when no delegates are running even if labels exist.
        """
        issue = {"number": 525,
                 "labels": [{"name": "workflow/research"},
                            {"name": "workflow/plan"}]}

        def fake_db_count(*a, **kw):
            # simulate an empty async_delegations table → 0 running
            class FakeCon:
                def execute(self, *a, **kw):
                    return self
                def fetchone(self):
                    return (0,)
                def close(self):
                    pass
            return FakeCon()

        with tempfile.TemporaryDirectory() as td, \
             mock.patch.object(ep, "_ensure_issues_cache",
                               return_value=[issue]), \
             mock.patch("os.path.exists",
                        side_effect=lambda p: p == os.path.expanduser("~/.hermes/state.db")), \
             mock.patch("sqlite3.connect", side_effect=fake_db_count):
            n = ep._count_active_phase_agents()
        self.assertEqual(n, 0,
                         f"0 running delegates → active_phase must be 0 "
                         f"even with phase labels present, got {n}")

    def test_active_phase_falls_back_to_labels_on_db_error(self):
        """DB read failure falls back to label count (rare duplicate > stall)."""
        issue = {"number": 526, "labels": [{"name": "workflow/implement"}]}
        with tempfile.TemporaryDirectory() as td, \
             mock.patch.object(ep, "_ensure_issues_cache",
                               return_value=[issue]), \
             mock.patch("os.path.exists",
                        side_effect=lambda p: p == os.path.expanduser("~/.hermes/state.db")), \
             mock.patch("sqlite3.connect",
                        side_effect=RuntimeError("db locked")):
            n = ep._count_active_phase_agents()
        self.assertEqual(n, 1,
                         f"DB error fallback must count phase labels, got {n}")

    def test_group_keeps_highest_priority_only(self):
        """Same issue with both a labeled event and a check_run event →
        only the check_run (P1) survives."""
        ev_high = {"_key": "check_run.completed#160", "type": "check_run",
                   "issue": 160, "branch": "impl/160-a", "conclusion": "success"}
        ev_low = {"_key": "issues.labeled#160:workflow/implement", "type": "issues.labeled",
                  "issue": 160, "label": "workflow/implement"}
        out = self._run_preprocess(self._events(ev_high, ev_low))
        self.assertEqual(len(out), 1, f"expected 1 SPAWN, got {out}")
        self.assertTrue("E2E: pr=160 started" in out[0] or "SPAWN: review" in out[0],
                        f"check_run must win → E2E/review chain: {out}")

    def test_success_beats_newer_failure(self):
        """CI success is the definitive state — an older success must beat a
        newer failure in the same group (success-before-failure sort)."""
        ev_success = {"_key": "check_run.completed#161", "type": "check_run",
                      "issue": 161, "branch": "impl/161-b", "conclusion": "success",
                      "ts": 1000}
        ev_failure = {"_key": "check_run.completed#161", "type": "check_run",
                      "issue": 161, "branch": "impl/161-b", "conclusion": "failure",
                      "ts": 2000}
        out = self._run_preprocess(self._events(ev_success, ev_failure))
        self.assertEqual(len(out), 1)
        self.assertTrue(any("E2E: pr=161 started" in l for l in out) or
                        any("SPAWN: review" in l for l in out),
                        f"success must trigger E2E→review chain: {out}")

    def test_label_self_correct_enriched_with_impl_pr(self):
        """Review-agent local-e2e path: workflow/self-correct label with NO
        pending CI failure → SPAWN carries pr/branch/source=local-e2e."""
        ev = {"_key": "issues.labeled#42:workflow/self-correct",
              "type": "issues.labeled", "issue": 42, "label": "workflow/self-correct"}

        def fake_run(cmd, *a, **kw):
            joined = " ".join(str(c) for c in cmd)
            if "head:impl/42" in joined:
                # Real `gh pr list --json ... --jq .[0]` prints the OBJECT
                return mock.Mock(stdout='{"number": 42, "headRefName": "impl/42-x"}',
                                 returncode=0)
            return mock.Mock(stdout="", returncode=1)

        out = self._run_preprocess(self._events(ev), fake_run=fake_run)
        hit = [l for l in out if l.startswith("SPAWN: self-correct,issue=42")]
        self.assertEqual(len(hit), 1, f"unexpected output: {out}")
        self.assertIn("pr=42", hit[0])
        self.assertIn("branch=impl/42-x", hit[0])
        self.assertIn("source=local-e2e", hit[0])

    def test_label_self_correct_fallback_without_pr(self):
        """No impl PR found (gh error/empty) → bare label spawn, still valid."""
        ev = {"_key": "issues.labeled#44:workflow/self-correct",
              "type": "issues.labeled", "issue": 44, "label": "workflow/self-correct"}
        out = self._run_preprocess(self._events(ev))
        hit = [l for l in out if l.startswith("SPAWN: self-correct,issue=44")]
        self.assertEqual(len(hit), 1, f"unexpected output: {out}")
        self.assertNotIn("source=local-e2e", hit[0])

    def test_label_self_correct_loses_to_pending_ci_failure(self):
        """CI failure outranks the label in the per-issue group — the label
        path must NOT double-spawn when a check_run(failure) is pending."""
        ev_ci = {"_key": "check_run.completed#43", "type": "check_run",
                 "issue": 43, "branch": "impl/43-y", "conclusion": "failure"}
        ev_lbl = {"_key": "issues.labeled#43:workflow/self-correct",
                  "type": "issues.labeled", "issue": 43, "label": "workflow/self-correct"}
        out = self._run_preprocess(self._events(ev_ci, ev_lbl))
        self.assertEqual(len(out), 1, f"expected 1 SPAWN, got {out}")
        self.assertIn("conclusion=failure", out[0])
        self.assertNotIn("source=local-e2e", out[0])

    def test_different_issues_both_kept(self):
        ev1 = {"_key": "check_run.completed#170", "type": "check_run",
               "issue": 170, "branch": "impl/170-a", "conclusion": "failure"}
        ev2 = {"_key": "issues.labeled#171:workflow/plan", "type": "issues.labeled",
               "issue": 171, "label": "workflow/plan"}
        out = self._run_preprocess(self._events(ev1, ev2))
        self.assertEqual(len(out), 2, f"expected 2 lines, got {out}")

    def test_pull_request_discarded_from_file(self):
        ev = {"_key": "pull_request.opened#180", "type": "pull_request", "issue": 180}
        written = {}

        def fake_write(events):
            written["events"] = events

        with mock.patch.object(ep, "read_pending", return_value=[ev]), \
             mock.patch.object(ep, "write_pending", side_effect=fake_write):
            out = ep.preprocess()
        self.assertEqual(out, [])
        self.assertEqual(written["events"], [])  # removed from file

    # ── 2026-08-13 duplicate-spawn regression suite (#393 trace) ──
    # Audit evidence: 5 research + 3 plan + 6 implement SPAWNs for #393 in
    # 30 min (07:15-07:45). Three compounding bugs, each pinned by a test:
    #   1. reconcile() re-injected label events every tick (test below)
    #   2. preprocess label path had no spawn gate (test below)
    #   3. `--search head:...` PR checks missed existing PRs (test below)

    def test_label_event_spawn_gated_within_ttl(self):
        """preprocess label path must share the spawn gate: a re-injected
        label event (reconcile re-injects) must NOT re-emit SPAWN within
        TTL — observed 6 duplicate implement agents for #393."""
        ev = {"_key": "issues.labeled#393:workflow/implement",
              "type": "issues.labeled", "issue": 393, "label": "workflow/implement"}
        with tempfile.TemporaryDirectory() as td:
            sf = os.path.join(td, "spawned.json")
            first = self._run_preprocess(self._events(ev), spawn_state_file=sf)
            second = self._run_preprocess(self._events(ev), spawn_state_file=sf)
        self.assertTrue(any(l.startswith("SPAWN: implement,issue=393") for l in first),
                        f"first tick must spawn: {first}")
        self.assertFalse(any(l.startswith("SPAWN: implement,issue=393") for l in second),
                         f"gate must suppress re-emission within TTL: {second}")

    def test_label_event_skips_spawn_when_pr_exists(self):
        """Deterministic PR check: a label event for a stage that already has
        a PR must NOT spawn. The old `--search head:impl/393` intermittently
        returned [] for existing PRs (Patch 59) → duplicate implement agents."""
        ev = {"_key": "issues.labeled#393:workflow/implement",
              "type": "issues.labeled", "issue": 393, "label": "workflow/implement"}

        def fake_run(cmd, *a, **kw):
            joined = " ".join(str(c) for c in cmd)
            if "pr" in joined and "list" in joined:
                return mock.Mock(stdout=json.dumps([
                    {"number": 444, "headRefName": "impl/393-main-scene-assembly",
                     "body": "Closes #393", "title": "feat(393): 主场景组装",
                     "state": "OPEN"}
                ]), returncode=0)
            return mock.Mock(stdout="", returncode=1)

        out = self._run_preprocess(self._events(ev), fake_run=fake_run)
        self.assertFalse(any(l.startswith("SPAWN: implement,issue=393") for l in out),
                         f"PR exists → must skip spawn: {out}")

    def test_implement_spawn_blocked_when_opencode_down(self):
        """Key-path gate (2026-08-13): implement SPAWN must NOT emit when
        OpenCode is down — BLOCKED instead + workflow auto-paused. Without
        this, the agent falls back to manual writes, burns the 50-call
        budget, and stalls (#466)."""
        ev = {"_key": "issues.labeled#466:workflow/implement",
              "type": "issues.labeled", "issue": 466, "label": "workflow/implement"}
        with tempfile.TemporaryDirectory() as td:
            cfg_path = os.path.join(td, "workflow-config.json")
            with mock.patch.object(ep, "WORKFLOW_CONFIG", cfg_path), \
                 mock.patch.object(ep, "OPENCODE_CRITICAL_FILE", os.path.join(td, "m")):
                out = self._run_preprocess(self._events(ev), opencode_up=False)
            self.assertFalse(any(l.startswith("SPAWN: implement,issue=466") for l in out),
                             f"opencode down → must NOT spawn: {out}")
            self.assertTrue(any(l.startswith("BLOCKED: implement") and "opencode-down" in l for l in out),
                            f"must emit BLOCKED reason=opencode-down: {out}")
            # auto-pause wrote the config
            with open(cfg_path) as f:
                cfg = json.load(f)
            self.assertFalse(cfg["enabled"])
            self.assertIn("opencode-down", cfg["paused_reason"])

    def test_implement_spawn_emits_when_opencode_up(self):
        """OpenCode healthy → normal SPAWN: implement (key-path gate passes)."""
        ev = {"_key": "issues.labeled#466:workflow/implement",
              "type": "issues.labeled", "issue": 466, "label": "workflow/implement"}
        out = self._run_preprocess(self._events(ev), opencode_up=True)
        self.assertTrue(any(l.startswith("SPAWN: implement,issue=466") for l in out),
                        f"opencode up → normal spawn: {out}")

    def test_research_spawn_not_blocked_by_opencode_down(self):
        """OpenCode is implement-only. A research spawn must pass even when
        OpenCode is down (research doesn't need it)."""
        ev = {"_key": "issues.labeled#466:workflow/research",
              "type": "issues.labeled", "issue": 466, "label": "workflow/research"}
        out = self._run_preprocess(self._events(ev), opencode_up=False)
        self.assertTrue(any(l.startswith("SPAWN: research,issue=466") for l in out),
                        f"research must not be blocked by opencode: {out}")

    def test_stale_stage_event_blocked(self):
        """Stale workflow/available label (never removed on advance) injected
        every tick → phantom `SPAWN: research` for an issue already at
        workflow/implement (audit 07:31:26, #393). Backward-stage events must
        be discarded."""
        ev = {"_key": "issues.labeled#393:workflow/available",
              "type": "issues.labeled", "issue": 393, "label": "workflow/available"}
        issue = {"number": 393, "labels": [{"name": "workflow/available"},
                                           {"name": "workflow/implement"}]}
        out = self._run_preprocess(self._events(ev), issue_cache=[issue])
        self.assertFalse(any(l.startswith("SPAWN: research,issue=393") for l in out),
                         f"stale available event must not spawn research: {out}")

    def test_stalled_scan_finds_impl_pr(self):
        """`--search head:impl/` returned [] intermittently → #444 sat 90 min
        with CI green + 0 reviews (no STALLED ever emitted). The deterministic
        client-side filter must find impl PRs."""
        def fake_gh(*args):
            joined = " ".join(args)
            if "pr" in joined and "list" in joined:
                return json.dumps([
                    {"number": 444, "headRefName": "impl/393-main-scene-assembly",
                     "mergeable": "MERGEABLE", "labels": [], "body": "Closes #393",
                     "title": "feat(393)", "state": "OPEN"}
                ])
            return ""
        with tempfile.TemporaryDirectory() as td, \
             mock.patch.object(ep, "_SPAWN_STATE_FILE",
                               os.path.join(td, "spawned.json")), \
             mock.patch.object(ep, "E2E_STATE_DIR", os.path.join(td, "e2e-state")), \
             mock.patch.object(ep, "E2E_RUNNER", "/bin/true"), \
             mock.patch.object(ep, "gh", side_effect=fake_gh):
            cmds = ep._quick_stalled_scan()
        self.assertTrue(any("E2E: pr=444 started" in c for c in cmds),
                        f"stalled scan must kick off E2E for impl PR: {cmds}")

    def test_stalled_scan_merges_stalled_research_pr(self):
        def fake_gh(*args):
            joined = " ".join(args)
            if "pr" in joined and "list" in joined:
                return json.dumps([
                    {"number": 450, "headRefName": "research/380-x",
                     "mergeable": "MERGEABLE", "labels": [], "body": "Parent #380",
                     "title": "research", "state": "OPEN"}
                ])
            return ""
        with mock.patch.object(ep, "gh", side_effect=fake_gh):
            cmds = ep._quick_stalled_scan()
        self.assertTrue(any("STALLED: merge-pr,pr=450" in c for c in cmds),
                        f"stalled scan must merge mergeable research PR: {cmds}")

    def test_stalled_scan_merges_docs_pr(self):
        """2026-08-19 (post-merge 阶段落地): post-merge agent 创建的 docs/gdd-<N>
        GDD 更新 PR 必须被 stalled scan 自动 merge (merge 归脚本层) — 否则
        GDD 内容永远停在分支上。"""
        def fake_gh(*args):
            joined = " ".join(args)
            if "pr" in joined and "list" in joined:
                return json.dumps([
                    {"number": 570, "headRefName": "docs/gdd-566",
                     "mergeable": "MERGEABLE", "labels": [], "body": "docs: GDD after #566",
                     "title": "docs", "state": "OPEN"}
                ])
            return ""
        with mock.patch.object(ep, "gh", side_effect=fake_gh):
            cmds = ep._quick_stalled_scan()
        self.assertTrue(any("STALLED: merge-pr,pr=570" in c for c in cmds),
                        f"stalled scan must merge mergeable docs PR: {cmds}")

    def test_stalled_scan_skips_conflicting_docs_pr(self):
        """CONFLICTING docs PR 不 merge (等 post-merge agent 或人工处理),
        不能静默吞掉。"""
        def fake_gh(*args):
            joined = " ".join(args)
            if "pr" in joined and "list" in joined:
                return json.dumps([
                    {"number": 571, "headRefName": "docs/gdd-567",
                     "mergeable": "CONFLICTING", "labels": [], "body": "docs",
                     "title": "docs", "state": "OPEN"}
                ])
            return ""
        with mock.patch.object(ep, "gh", side_effect=fake_gh):
            cmds = ep._quick_stalled_scan()
        self.assertFalse(any("STALLED: merge-pr,pr=571" in c for c in cmds),
                        f"conflicting docs PR must NOT auto-merge: {cmds}")

    # ── 2026-08-13 event-driven restore (方案4 v2) ──────────────────
    # Delete reconcile() synthetic event injection; the scheduler now emits
    # research SPAWNs directly (picker promote + available rescan), all
    # SPAWN/STALLED lines flow through the gate, and the stalled scan is
    # self-correct aware. Each behavior below is pinned by a test.

    def test_picker_promote_emits_research_spawn(self):
        """Picker promote (backlog → available) must directly emit
        SPAWN: research — no more webhook echo round-trip. The gate
        records (issue, research) so a second tick does not re-spawn."""
        issue = {"number": 500, "labels": [{"name": "workflow/backlog"}]}

        def fake_run(cmd, *a, **kw):
            joined = " ".join(str(c) for c in cmd)
            if "issue" in joined and "edit" in joined:
                return mock.Mock(stdout="ok", returncode=0)
            if "pr" in joined and "list" in joined:
                return mock.Mock(stdout="[]", returncode=0)
            return mock.Mock(stdout="", returncode=1)

        with tempfile.TemporaryDirectory() as td, \
             mock.patch.object(ep, "_SPAWN_STATE_FILE",
                               os.path.join(td, "spawned.json")), \
             mock.patch.object(ep, "is_paused", return_value=False), \
             mock.patch.object(ep, "current_workflow_count", return_value=0), \
             mock.patch.object(ep, "_pick_candidates", return_value=[500]), \
             mock.patch.object(ep, "_invalidate_issues_cache_for"), \
             mock.patch.object(ep, "_ensure_issues_cache",
                               return_value=[issue]), \
             mock.patch("subprocess.run", fake_run):
            first = ep.pick_next_issue()
            second = ep.pick_next_issue()
        self.assertIn(
            f"SPAWN: research,issue=500,label=workflow/research,game={_active_game()}",
            first,
            f"promote must directly spawn research: {first}")
        self.assertNotIn("SPAWN: research,issue=500", second,
                         "gate must suppress re-spawn within TTL")

    def test_picker_rescans_available_after_ttl(self):
        """Dead research-agent recovery: an issue stuck at workflow/available
        with no research PR is re-spawned after the research gate TTL."""
        issue = {"number": 501, "labels": [{"name": "workflow/available"}]}

        def fake_run(cmd, *a, **kw):
            joined = " ".join(str(c) for c in cmd)
            if "pr" in joined and "list" in joined:
                return mock.Mock(stdout="[]", returncode=0)  # no PR exists
            return mock.Mock(stdout="", returncode=1)

        with tempfile.TemporaryDirectory() as td, \
             mock.patch.object(ep, "_SPAWN_STATE_FILE",
                               os.path.join(td, "spawned.json")), \
             mock.patch.object(ep, "is_paused", return_value=False), \
             mock.patch.object(ep, "current_workflow_count", return_value=9), \
             mock.patch.object(ep, "_pick_candidates", return_value=[]), \
             mock.patch.object(ep, "_ensure_issues_cache",
                               return_value=[issue]), \
             mock.patch("subprocess.run", fake_run):
            first = ep.pick_next_issue()
            old_time = ep.time.time
            ep.time.time = lambda: old_time() + ep._SPAWN_TTL_BY_STAGE["research"] + 10
            try:
                second = ep.pick_next_issue()
            finally:
                ep.time.time = old_time
        self.assertIn(
            f"SPAWN: research,issue=501,label=workflow/research,game={_active_game()}",
            first,
            f"available issue must spawn research: {first}")
        self.assertIn(
            f"SPAWN: research,issue=501,label=workflow/research,game={_active_game()}",
            second,
            "TTL expiry must re-spawn a stalled available issue")

    def test_picker_direct_and_webhook_echo_single_spawn(self):
        """Direct picker spawn and the webhook echo (preprocess label path)
        share one gate: whichever fires first, the second is suppressed
        within TTL — exactly one SPAWN per (issue, stage) per TTL."""
        issue = {"number": 502, "labels": [{"name": "workflow/available"}]}
        ev = {"_key": "issues.labeled#502:workflow/available",
              "type": "issues.labeled", "issue": 502, "label": "workflow/available"}

        def fake_run(cmd, *a, **kw):
            joined = " ".join(str(c) for c in cmd)
            if "pr" in joined and "list" in joined:
                return mock.Mock(stdout="[]", returncode=0)
            return mock.Mock(stdout="", returncode=1)

        with tempfile.TemporaryDirectory() as td:
            sf = os.path.join(td, "spawned.json")
            with mock.patch.object(ep, "_SPAWN_STATE_FILE", sf), \
                 mock.patch.object(ep, "is_paused", return_value=False), \
                 mock.patch.object(ep, "current_workflow_count", return_value=9), \
                 mock.patch.object(ep, "_pick_candidates", return_value=[]), \
                 mock.patch.object(ep, "_ensure_issues_cache",
                                   return_value=[issue]), \
                 mock.patch("subprocess.run", fake_run):
                picker_lines = ep.pick_next_issue()
            # webhook echo arrives next tick — same gate file
            echo_lines = self._run_preprocess(self._events(ev),
                                              spawn_state_file=sf,
                                              issue_cache=[issue])
        self.assertTrue(any("SPAWN: research,issue=502" in l for l in picker_lines),
                        f"picker must emit the research spawn: {picker_lines}")
        self.assertFalse(any("SPAWN: research,issue=502" in l for l in echo_lines),
                         f"gate must dedup the webhook echo: {echo_lines}")

    def test_picker_implement_blocked_when_opencode_down(self):
        """Picker path key-path gate: workflow/implement issue + OpenCode down
        → BLOCKED (no SPAWN) + auto-pause, same as preprocess path."""
        issue = {"number": 466, "labels": [{"name": "workflow/implement"}]}

        def fake_run(cmd, *a, **kw):
            joined = " ".join(str(c) for c in cmd)
            if "pr" in joined and "list" in joined:
                return mock.Mock(stdout="0", returncode=0)  # no impl PR yet
            return mock.Mock(stdout="", returncode=1)

        with tempfile.TemporaryDirectory() as td, \
             mock.patch.object(ep, "_SPAWN_STATE_FILE",
                               os.path.join(td, "spawned.json")), \
             mock.patch.object(ep, "is_paused", return_value=False), \
             mock.patch.object(ep, "current_workflow_count", return_value=0), \
             mock.patch.object(ep, "_pick_candidates", return_value=[]), \
             mock.patch.object(ep, "opencode_healthy", return_value=False), \
             mock.patch.object(ep, "WORKFLOW_CONFIG", os.path.join(td, "wf.json")), \
             mock.patch.object(ep, "OPENCODE_CRITICAL_FILE", os.path.join(td, "m")), \
             mock.patch.object(ep, "_ensure_issues_cache",
                               return_value=[issue]), \
             mock.patch("subprocess.run", fake_run):
            lines = ep.pick_next_issue()
        self.assertFalse(any("SPAWN: implement,issue=466" in l for l in lines),
                         f"opencode down → picker must NOT spawn implement: {lines}")
        self.assertTrue(any("BLOCKED: implement" in l and "opencode-down" in l for l in lines),
                        f"picker must emit BLOCKED reason=opencode-down: {lines}")

    def test_picker_implement_emits_when_opencode_up(self):
        """Picker path: OpenCode healthy → normal SPAWN: implement."""
        issue = {"number": 466, "labels": [{"name": "workflow/implement"}]}

        def fake_run(cmd, *a, **kw):
            joined = " ".join(str(c) for c in cmd)
            if "pr" in joined and "list" in joined:
                return mock.Mock(stdout="0", returncode=0)
            return mock.Mock(stdout="", returncode=1)

        with tempfile.TemporaryDirectory() as td, \
             mock.patch.object(ep, "_SPAWN_STATE_FILE",
                               os.path.join(td, "spawned.json")), \
             mock.patch.object(ep, "is_paused", return_value=False), \
             mock.patch.object(ep, "current_workflow_count", return_value=0), \
             mock.patch.object(ep, "_pick_candidates", return_value=[]), \
             mock.patch.object(ep, "opencode_healthy", return_value=True), \
             mock.patch.object(ep, "_ensure_issues_cache",
                               return_value=[issue]), \
             mock.patch("subprocess.run", fake_run):
            lines = ep.pick_next_issue()
        self.assertTrue(any("SPAWN: implement,issue=466" in l for l in lines),
                        f"opencode up → picker must spawn implement: {lines}")

    def test_dead_spawn_recovery_after_half_ttl(self):
        """2026-08-14: SPAWN consumed by cron timeout but no agent/PR ever
        appeared → after TTL/2 the picker re-emits despite the gate marker.
        Simulates #476: gate recorded plan at t0, TTL=3600 → at t0+1801 the
        picker must emit SPAWN: plan again (PR still absent)."""
        issue = {"number": 476, "labels": [{"name": "workflow/plan"}]}

        def fake_run(cmd, *a, **kw):
            joined = " ".join(str(c) for c in cmd)
            if "pr" in joined and "list" in joined:
                return mock.Mock(stdout="0", returncode=0)
            return mock.Mock(stdout="", returncode=1)

        with tempfile.TemporaryDirectory() as td, \
             mock.patch.object(ep, "_SPAWN_STATE_FILE",
                               os.path.join(td, "spawned.json")), \
             mock.patch.object(ep, "is_paused", return_value=False), \
             mock.patch.object(ep, "current_workflow_count", return_value=0), \
             mock.patch.object(ep, "_pick_candidates", return_value=[]), \
             mock.patch.object(ep, "_ensure_issues_cache",
                               return_value=[issue]), \
             mock.patch("subprocess.run", fake_run):
            # first call: gate records plan, emits SPAWN
            first = ep.pick_next_issue()
            self.assertTrue(any("SPAWN: plan,issue=476" in l for l in first))
            # second call within TTL/2: suppressed by gate
            second = ep.pick_next_issue()
            self.assertFalse(any("SPAWN: plan,issue=476" in l for l in second),
                            f"gate must suppress within TTL/2: {second}")
            # advance time past TTL/2 (plan TTL=3600 → 1801s)
            old_time = ep.time.time
            ep.time.time = lambda: old_time() + 1801
            try:
                third = ep.pick_next_issue()
            finally:
                ep.time.time = old_time
            self.assertTrue(any("SPAWN: plan,issue=476" in l for l in third),
                            f"dead-spawn recovery must re-emit after TTL/2: {third}")

    def test_dead_spawn_recovery_requires_stale_gate(self):
        """No gate record → _dead_spawn_recovery returns False (normal
        gate path handles first-time spawns)."""
        with tempfile.TemporaryDirectory() as td:
            sf = os.path.join(td, "spawned.json")
            with mock.patch.object(ep, "_SPAWN_STATE_FILE", sf):
                self.assertFalse(ep._dead_spawn_recovery(476, "plan"))

    def test_stalled_scan_gated(self):
        """The same impl PR scanned twice emits E2E/review once —
        the gate closes the 3b59ede hole (ungated per-tick review re-spawn)."""
        def fake_gh(*args):
            joined = " ".join(args)
            if "pr" in joined and "list" in joined:
                return json.dumps([
                    {"number": 444, "headRefName": "impl/393-main-scene-assembly",
                     "mergeable": "MERGEABLE", "labels": [], "body": "Closes #393",
                     "title": "feat(393)", "state": "OPEN"}
                ])
            return ""
        with tempfile.TemporaryDirectory() as td, \
             mock.patch.object(ep, "_SPAWN_STATE_FILE",
                               os.path.join(td, "spawned.json")), \
             mock.patch.object(ep, "E2E_STATE_DIR", os.path.join(td, "e2e-state")), \
             mock.patch.object(ep, "E2E_RUNNER", "/bin/true"), \
             mock.patch.object(ep, "gh", side_effect=fake_gh):
            first = ep._quick_stalled_scan()
            second = ep._quick_stalled_scan()
        self.assertTrue(any("E2E: pr=444 started" in c for c in first),
                        f"first scan must kick off E2E: {first}")
        self.assertFalse(any("E2E: pr=444 started" in c for c in second),
                         f"gate must suppress re-emission: {second}")

    def test_stalled_scan_self_correct_aware(self):
        """Parent issue already at workflow/self-correct (review agent's local
        e2e failure) → STALLED: check-self-correct — not another review round."""
        def fake_gh(*args):
            joined = " ".join(args)
            if "pr" in joined and "list" in joined:
                return json.dumps([
                    {"number": 460, "headRefName": "impl/393-main-scene-assembly",
                     "mergeable": "MERGEABLE", "labels": [], "body": "Closes #393",
                     "title": "feat(393)", "state": "OPEN"}
                ])
            return ""
        with tempfile.TemporaryDirectory() as td, \
             mock.patch.object(ep, "_SPAWN_STATE_FILE",
                               os.path.join(td, "spawned.json")), \
             mock.patch.object(ep, "gh", side_effect=fake_gh), \
             mock.patch.object(ep, "_extract_parent_issue", return_value=393), \
             mock.patch.object(ep, "_current_issue_labels",
                               return_value=["workflow/self-correct"]):
            cmds = ep._quick_stalled_scan()
        self.assertTrue(any("STALLED: check-self-correct,pr=460" in c for c in cmds),
                        f"self-correct-aware scan must emit check-self-correct: {cmds}")
        self.assertFalse(any("STALLED: check-review,pr=460" in c for c in cmds),
                         "must NOT emit check-review when parent is self-correcting")

    def test_stalled_scan_blocked_plus_self_correct_both_emitted(self):
        """2026-08-14 rework: a blocked PR whose parent ALSO has
        workflow/self-correct must emit BOTH check-unblock AND
        check-self-correct — the old code emitted only check-unblock
        (blocked branch), stalling the PR's own code-defect fix forever.

        Scenario: PR #475 blocked (pre-existing clear_color) + parent #466
        flagged self-correct (assertion code defects)."""
        def fake_gh(*args):
            joined = " ".join(args)
            if "pr" in joined and "list" in joined:
                return json.dumps([
                    {"number": 475, "headRefName": "impl/466-e2e-visual-regression",
                     "mergeable": "MERGEABLE", "labels": [{"name": "status/blocked"}],
                     "body": "Closes #466", "title": "feat(466)", "state": "OPEN"}
                ])
            return ""
        with tempfile.TemporaryDirectory() as td, \
             mock.patch.object(ep, "_SPAWN_STATE_FILE",
                               os.path.join(td, "spawned.json")), \
             mock.patch.object(ep, "gh", side_effect=fake_gh), \
             mock.patch.object(ep, "_extract_parent_issue", return_value=466), \
             mock.patch.object(ep, "_current_issue_labels",
                               return_value=["workflow/self-correct"]):
            cmds = ep._quick_stalled_scan()
        self.assertTrue(any("STALLED: check-unblock,pr=475" in c for c in cmds),
                        f"blocked PR must emit check-unblock: {cmds}")
        self.assertTrue(any("STALLED: check-self-correct,pr=475" in c for c in cmds),
                        f"self-correct parent must ALSO emit check-self-correct: {cmds}")

    def test_stalled_scan_blocked_without_self_correct_only_unblock(self):
        """Blocked PR whose parent has NO self-correct label → only
        check-unblock (no spurious self-correct)."""
        def fake_gh(*args):
            joined = " ".join(args)
            if "pr" in joined and "list" in joined:
                return json.dumps([
                    {"number": 475, "headRefName": "impl/466-e2e-visual-regression",
                     "mergeable": "MERGEABLE", "labels": [{"name": "status/blocked"}],
                     "body": "Closes #466", "title": "feat(466)", "state": "OPEN"}
                ])
            return ""
        with tempfile.TemporaryDirectory() as td, \
             mock.patch.object(ep, "_SPAWN_STATE_FILE",
                               os.path.join(td, "spawned.json")), \
             mock.patch.object(ep, "gh", side_effect=fake_gh), \
             mock.patch.object(ep, "_extract_parent_issue", return_value=466), \
             mock.patch.object(ep, "_current_issue_labels", return_value=["workflow/implement"]):
            cmds = ep._quick_stalled_scan()
        self.assertTrue(any("STALLED: check-unblock,pr=475" in c for c in cmds),
                        f"blocked PR must emit check-unblock: {cmds}")
        self.assertFalse(any("STALLED: check-self-correct,pr=475" in c for c in cmds),
                         "no self-correct label → must NOT emit check-self-correct")

    # ── 2026-08-17 conflict deadlock (#542) ──
    # CONFLICTING impl PR was a silent deadlock: e2e-state terminal "reviewed"
    # (ran on pre-conflict commit), _pr_exists_for_issue() treats the PR as
    # "implement done" → never re-spawned, stalled scan emitted nothing.
    # Fix: emit STALLED: check-conflict (delegate implement agent to merge
    # main → resolve → push), skip all other paths until mergeable.

    def test_stalled_scan_conflicting_pr_emits_check_conflict(self):
        """CONFLICTING impl PR → STALLED: check-conflict, not e2e/review."""
        def fake_gh(*args):
            joined = " ".join(args)
            if "pr" in joined and "list" in joined:
                return json.dumps([
                    {"number": 542, "headRefName": "impl/529-special-brick",
                     "mergeable": "CONFLICTING", "labels": [],
                     "body": "Parent #529", "title": "feat(529)", "state": "OPEN"}
                ])
            return ""
        with tempfile.TemporaryDirectory() as td, \
             mock.patch.object(ep, "_SPAWN_STATE_FILE",
                               os.path.join(td, "spawned.json")), \
             mock.patch.object(ep, "gh", side_effect=fake_gh), \
             mock.patch.object(ep, "e2e_orchestrator",
                               side_effect=AssertionError("e2e must NOT run on CONFLICTING")):
            cmds = ep._quick_stalled_scan()
        self.assertTrue(any("STALLED: check-conflict,pr=542" in c for c in cmds),
                        f"CONFLICTING PR must emit check-conflict: {cmds}")
        self.assertFalse(any("SPAWN: review" in c for c in cmds),
                         "must NOT spawn review on a conflicting PR")

    def test_stalled_scan_conflicting_pr_gated_once_per_ttl(self):
        """Same CONFLICTING PR scanned twice → check-conflict emitted once
        (spawn gate dedup, same as self-correct/3b59ede pattern)."""
        def fake_gh(*args):
            joined = " ".join(args)
            if "pr" in joined and "list" in joined:
                return json.dumps([
                    {"number": 542, "headRefName": "impl/529-special-brick",
                     "mergeable": "CONFLICTING", "labels": [],
                     "body": "Parent #529", "title": "feat(529)", "state": "OPEN"}
                ])
            return ""
        with tempfile.TemporaryDirectory() as td, \
             mock.patch.object(ep, "_SPAWN_STATE_FILE",
                               os.path.join(td, "spawned.json")), \
             mock.patch.object(ep, "gh", side_effect=fake_gh):
            first = ep._quick_stalled_scan()
            second = ep._quick_stalled_scan()
        self.assertEqual(
            sum(1 for c in first if "STALLED: check-conflict" in c), 1,
            f"first scan emits check-conflict exactly once: {first}")
        self.assertFalse(any("STALLED: check-conflict" in c for c in second),
                         f"gate must suppress re-emission within TTL: {second}")

    def test_stalled_scan_conflicting_blocked_prioritizes_conflict(self):
        """Blocked AND conflicting PR → check-conflict wins (conflict must be
        resolved first — blocked recovery needs update-branch which fails on
        a conflicting branch)."""
        def fake_gh(*args):
            joined = " ".join(args)
            if "pr" in joined and "list" in joined:
                return json.dumps([
                    {"number": 542, "headRefName": "impl/529-special-brick",
                     "mergeable": "CONFLICTING", "labels": [{"name": "status/blocked"}],
                     "body": "Parent #529", "title": "feat(529)", "state": "OPEN"}
                ])
            return ""
        with tempfile.TemporaryDirectory() as td, \
             mock.patch.object(ep, "_SPAWN_STATE_FILE",
                               os.path.join(td, "spawned.json")), \
             mock.patch.object(ep, "gh", side_effect=fake_gh):
            cmds = ep._quick_stalled_scan()
        self.assertTrue(any("STALLED: check-conflict,pr=542" in c for c in cmds),
                        f"conflict takes priority over blocked: {cmds}")
        self.assertFalse(any("STALLED: check-unblock" in c for c in cmds),
                         "blocked recovery must wait for conflict resolution")

    def test_stalled_scan_mergeable_impl_not_conflicting(self):
        """MERGEABLE impl PR must NOT emit check-conflict (regression guard —
        conflict path only fires on CONFLICTING, normal flow untouched)."""
        def fake_gh(*args):
            joined = " ".join(args)
            if "pr" in joined and "list" in joined:
                return json.dumps([
                    {"number": 444, "headRefName": "impl/393-main-scene-assembly",
                     "mergeable": "MERGEABLE", "labels": [], "body": "Closes #393",
                     "title": "feat(393)", "state": "OPEN"}
                ])
            return ""
        with tempfile.TemporaryDirectory() as td, \
             mock.patch.object(ep, "_SPAWN_STATE_FILE",
                               os.path.join(td, "spawned.json")), \
             mock.patch.object(ep, "E2E_STATE_DIR", os.path.join(td, "e2e-state")), \
             mock.patch.object(ep, "E2E_RUNNER", "/bin/true"), \
             mock.patch.object(ep, "gh", side_effect=fake_gh):
            cmds = ep._quick_stalled_scan()
        self.assertFalse(any("STALLED: check-conflict" in c for c in cmds),
                         f"MERGEABLE PR must not emit check-conflict: {cmds}")
        self.assertTrue(any("E2E: pr=444 started" in c for c in cmds),
                        "MERGEABLE PR must follow the normal e2e path")

    # ── 2026-08-13 dependency-hole regression tests (#384/#390 trace) ──
    # Closed ≠ resolved: #384/#390 were closed early WITHOUT status/done while
    # their code only landed in the unmerged #444 — old logic treated them as
    # resolved and let #393 advance on un-landed work.

    def test_dep_closed_without_done_is_unresolved(self):
        issue = {"number": 100, "labels": [{"name": "workflow/backlog"}],
                 "body": "## 前置依赖\n#5\n"}
        with mock.patch.object(ep, "_ensure_issues_cache", return_value=[issue]), \
             mock.patch.object(ep, "_ensure_closed_issues_cache",
                               return_value={5: ["enhancement"]}):
            unresolved = ep._has_unresolved_dependencies(100)
        self.assertEqual(len(unresolved), 1)
        self.assertEqual(unresolved[0]["issue"], 5)
        self.assertTrue(unresolved[0].get("closed_without_done"))

    def test_dep_closed_with_done_is_resolved(self):
        issue = {"number": 101, "labels": [{"name": "workflow/backlog"}],
                 "body": "## 前置依赖\n#6\n"}
        with mock.patch.object(ep, "_ensure_issues_cache", return_value=[issue]), \
             mock.patch.object(ep, "_ensure_closed_issues_cache",
                               return_value={6: ["status/done"]}):
            unresolved = ep._has_unresolved_dependencies(101)
        self.assertEqual(unresolved, [])

    def test_dep_closed_human_review_is_resolved(self):
        """v4 人机共做: 用户 close 定稿后的 taste-draft 依赖视为已满足。"""
        issue = {"number": 102, "labels": [{"name": "workflow/backlog"}],
                 "body": "## 前置依赖\n#7\n"}
        with mock.patch.object(ep, "_ensure_issues_cache", return_value=[issue]), \
             mock.patch.object(ep, "_ensure_closed_issues_cache",
                               return_value={7: ["status/human-review"]}):
            unresolved = ep._has_unresolved_dependencies(102)
        self.assertEqual(unresolved, [])


class TestPickCandidates(unittest.TestCase):
    def _issue(self, n, labels, body=""):
        return {"number": n, "labels": [{"name": l} for l in labels],
                "title": f"Issue {n}", "body": body}

    def setUp(self):
        # 2026-08-19 (版本目标): picker 现在读 version_target — 统一 mock
        # 到临时 config, 默认 target=mvp (现有测试的 issue 都带 version/mvp)
        self._td = tempfile.TemporaryDirectory()
        self._cfg = os.path.join(self._td.name, "cfg.json")
        with open(self._cfg, "w") as f:
            json.dump({"version_target": "mvp"}, f)
        self._cfg_patch = mock.patch.object(ep, "WORKFLOW_CONFIG", self._cfg)
        self._cfg_patch.start()

    def tearDown(self):
        self._cfg_patch.stop()
        self._td.cleanup()

    def _pick(self, issues, limit=4):
        with mock.patch.object(ep, "_ensure_issues_cache", return_value=issues), \
             mock.patch.object(ep, "_get_active_issue_target_files", return_value=set()), \
             mock.patch.object(ep, "_has_unresolved_dependencies", return_value=[]), \
             mock.patch.object(ep, "_has_file_conflict", return_value=False):
            return ep._pick_candidates(limit)

    def test_picks_backlog_with_resolved_deps(self):
        issues = [
            self._issue(1, ["workflow/backlog", "version/mvp"]),
            self._issue(2, ["workflow/backlog", "version/mvp", "priority/high"]),
            self._issue(3, ["workflow/available", "version/mvp"]),  # not backlog → skip
        ]
        picked = self._pick(issues)
        self.assertEqual(picked, [2, 1])  # priority/high sorts first

    def test_skips_unresolved_deps_and_conflicts(self):
        issues = [
            self._issue(10, ["workflow/backlog", "version/mvp"]),
            self._issue(11, ["workflow/backlog", "version/mvp"]),
        ]
        with mock.patch.object(ep, "_ensure_issues_cache", return_value=issues), \
             mock.patch.object(ep, "_get_active_issue_target_files", return_value=set()):
            with mock.patch.object(ep, "_has_unresolved_dependencies",
                                   side_effect=[[{"issue": 5, "type": "full"}], []]):
                with mock.patch.object(ep, "_has_file_conflict", return_value=False):
                    picked = ep._pick_candidates(4)
        self.assertEqual(picked, [11])

    def test_respects_limit(self):
        issues = [self._issue(n, ["workflow/backlog", "version/mvp"])
                  for n in range(20, 26)]
        picked = self._pick(issues, limit=2)
        self.assertEqual(len(picked), 2)

    # ── 2026-08-19 版本目标 (用户拍板) ─────────────────────────────
    def test_version_target_filters_to_target(self):
        """target=mvp → 只拣 version/mvp; v1/v2 backlog 一律不拣."""
        issues = [
            self._issue(1, ["workflow/backlog", "version/mvp"]),
            self._issue(2, ["workflow/backlog", "version/v1"]),
            self._issue(3, ["workflow/backlog", "version/v2"]),
        ]
        picked = self._pick(issues)
        self.assertEqual(picked, [1], f"v1/v2 不得被拣: {picked}")

    def test_version_target_none_stops(self):
        """无 version_target → 停止 (安全默认, 不拣任何 issue)."""
        with open(self._cfg, "w") as f:
            json.dump({}, f)
        issues = [self._issue(1, ["workflow/backlog", "version/mvp"])]
        picked = self._pick(issues)
        self.assertEqual(picked, [])

    def test_version_target_dependency_gate(self):
        """target=v1 但 mvp 有 open issue → 不拣 (版本依赖链门控)."""
        with open(self._cfg, "w") as f:
            json.dump({"version_target": "v1"}, f)
        issues = [
            self._issue(10, ["workflow/backlog", "version/mvp"]),  # mvp 未完成
            self._issue(20, ["workflow/backlog", "version/v1"]),
        ]
        picked = self._pick(issues)
        self.assertEqual(picked, [], f"mvp 未全 CLOSED 时 v1 不得拣: {picked}")

    def test_version_target_dependency_gate_passes_when_prev_done(self):
        """target=v1 且 mvp 全 CLOSED (open=0) → 放行 v1."""
        with open(self._cfg, "w") as f:
            json.dump({"version_target": "v1"}, f)
        issues = [self._issue(20, ["workflow/backlog", "version/v1"])]
        picked = self._pick(issues)
        self.assertEqual(picked, [20])

    def test_version_target_completed_stops(self):
        """target=mvp 且 mvp open=0 (全 CLOSED) → 停止, 不再拣."""
        issues = [self._issue(20, ["workflow/backlog", "version/v1"])]
        picked = self._pick(issues)
        self.assertEqual(picked, [], "目标版本已完成 → 停止拣选")


class TestOpenCodeHealthGate(unittest.TestCase):
    """2026-08-13: OpenCode is a HARD dependency (implement's only path).

    - opencode_healthy() must use /global/health JSON, not /health HTML
    - health_check() auto-pauses workflow + emits [CRITICAL] when OpenCode down
    - _pause_workflow() writes workflow-config.json enabled=false + marker file
    """

    def test_opencode_healthy_true_on_global_health_json(self):
        with mock.patch("urllib.request.urlopen") as m_url:
            m_ctx = mock.MagicMock()
            m_ctx.read.return_value = b'{"healthy":true,"version":"1.18.3"}'
            m_url.return_value.__enter__.return_value = m_ctx
            self.assertTrue(ep.opencode_healthy())
        # must hit /global/health, not /health
        args = m_url.call_args.args[0]
        self.assertIn("global/health", args)

    def test_opencode_healthy_false_on_exception(self):
        with mock.patch("urllib.request.urlopen", side_effect=OSError("conn refused")):
            self.assertFalse(ep.opencode_healthy())

    def test_opencode_healthy_false_on_unhealthy_json(self):
        with mock.patch("urllib.request.urlopen") as m_url:
            m_ctx = mock.MagicMock()
            m_ctx.read.return_value = b'{"healthy":false}'
            m_url.return_value.__enter__.return_value = m_ctx
            self.assertFalse(ep.opencode_healthy())

    def test_pause_workflow_writes_config_and_marker(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg_path = os.path.join(tmp, "workflow-config.json")
            marker = os.path.join(tmp, ".opencode-critical")
            with mock.patch.object(ep, "WORKFLOW_CONFIG", cfg_path), \
                 mock.patch.object(ep, "OPENCODE_CRITICAL_FILE", marker):
                ok = ep._pause_workflow("opencode-down (test)")
                self.assertTrue(ok)
            with open(cfg_path) as f:
                cfg = json.load(f)
            self.assertFalse(cfg["enabled"])
            self.assertIn("opencode-down", cfg["paused_reason"])
            self.assertTrue(os.path.exists(marker))

    def test_pause_workflow_preserves_existing_keys(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg_path = os.path.join(tmp, "workflow-config.json")
            with open(cfg_path, "w") as f:
                json.dump({"enabled": True, "preset": "always"}, f)
            with mock.patch.object(ep, "WORKFLOW_CONFIG", cfg_path), \
                 mock.patch.object(ep, "OPENCODE_CRITICAL_FILE", os.path.join(tmp, "m")):
                ep._pause_workflow("test-reason")
            with open(cfg_path) as f:
                cfg = json.load(f)
            self.assertEqual(cfg["preset"], "always")  # untouched
            self.assertFalse(cfg["enabled"])

    def test_health_check_critical_when_opencode_down(self):
        """OpenCode down → health_check emits [CRITICAL] + auto-pauses."""
        with tempfile.TemporaryDirectory() as tmp:
            cfg_path = os.path.join(tmp, "workflow-config.json")
            with mock.patch.object(ep, "opencode_healthy", return_value=False), \
                 mock.patch.object(ep, "check_webhook_connectivity", return_value=True), \
                 mock.patch.object(ep, "WORKFLOW_CONFIG", cfg_path), \
                 mock.patch.object(ep, "OPENCODE_CRITICAL_FILE", os.path.join(tmp, "m")), \
                 mock.patch("urllib.request.urlopen", side_effect=OSError("down")):
                line = ep.health_check()
            self.assertIn("opencode=DOWN", line)
            self.assertIn("[CRITICAL]", line)
            # auto-pause actually wrote the config
            self.assertTrue(os.path.exists(cfg_path))
            with open(cfg_path) as f:
                cfg = json.load(f)
            self.assertFalse(cfg["enabled"])

    def test_health_check_up_when_opencode_healthy(self):
        """OpenCode up → no CRITICAL, no pause, no marker file."""
        with tempfile.TemporaryDirectory() as tmp:
            cfg_path = os.path.join(tmp, "workflow-config.json")
            marker = os.path.join(tmp, "m")
            with mock.patch.object(ep, "opencode_healthy", return_value=True), \
                 mock.patch.object(ep, "check_webhook_connectivity", return_value=True), \
                 mock.patch.object(ep, "WORKFLOW_CONFIG", cfg_path), \
                 mock.patch.object(ep, "OPENCODE_CRITICAL_FILE", marker), \
                 mock.patch("urllib.request.urlopen", side_effect=OSError("down")):
                line = ep.health_check()
            self.assertIn("opencode=UP", line)
            self.assertNotIn("[CRITICAL]", line)
            self.assertFalse(os.path.exists(marker))
            self.assertFalse(os.path.exists(cfg_path))  # never written


class TestReviewFollowup(unittest.TestCase):
    """2026-08-14: deterministic script layer for review conclusions.

    Review agent writes ~/.hermes/review-conclusions/<pr>.json as its LAST
    action; review_followup() performs the mechanical aftermath (blocked
    label on PR+parent, fix issue with fset dedup, conclusion comment) so a
    call-budget-exhausted agent never leaves a blocked PR dangling.
    """

    def setUp(self):
        # 2026-08-17 (方案 X): followup 消费结论时会写 e2e-state reviewed
        # 标记 — 隔离, 防测试污染真实 ~/.hermes/e2e-state/
        self._td = tempfile.TemporaryDirectory()
        self._e2e_patch = mock.patch.object(
            ep, "E2E_STATE_DIR", os.path.join(self._td.name, "e2e-state"))
        self._e2e_patch.start()
        # 2026-08-19 (P2 骨架): 结论目录统一隔离 — 各测试显式 mock 覆盖之,
        # 漏 mock 时 (如骨架生成) 不再写真实 ~/.hermes/review-conclusions/
        self._concl_patch = mock.patch.object(
            ep, "REVIEW_CONCLUSIONS_DIR", os.path.join(self._td.name, "concl"))
        self._concl_patch.start()
        # 2026-08-19 (post-merge 阶段): approved→merged 会写 post-merge 状态 —
        # 必须隔离, 否则测试泄漏假状态到真实 ~/.hermes/post-merge-state/
        # (实测: test_approved_verdict_merges 泄漏 475.json, #562 泄漏 562.json)
        self._pm_patch = mock.patch.object(
            ep, "POST_MERGE_STATE_DIR", os.path.join(self._td.name, "post-merge-state"))
        self._pm_patch.start()

    def tearDown(self):
        self._pm_patch.stop()
        self._concl_patch.stop()
        self._e2e_patch.stop()
        self._td.cleanup()

    def _write_conclusion(self, td, pr, verdict="blocked", fix=None,
                          parent=466, cls="B"):
        d = os.path.join(td, "concl")
        os.makedirs(d, exist_ok=True)
        data = {"pr": pr, "verdict": verdict, "class": cls,
                "parent_issue": parent, "fix_issue": fix,
                "evidence": "test evidence"}
        path = os.path.join(d, f"{pr}.json")
        with open(path, "w") as f:
            json.dump(data, f)
        return d

    def test_ensure_conclusion_skeleton_creates_valid_json(self):
        """2026-08-19 (P2 骨架): SPAWN review 预生成结论骨架 — 合法 JSON、
        verdict=null、已存在不覆盖 (重审场景)。"""
        with tempfile.TemporaryDirectory() as td:
            d = os.path.join(td, "concl")
            with mock.patch.object(ep, "REVIEW_CONCLUSIONS_DIR", d), \
                 mock.patch.object(ep, "_devlog"):
                ep._ensure_conclusion_skeleton(777)
                ep._ensure_conclusion_skeleton(777)  # 幂等: 不覆盖
            path = os.path.join(d, "777.json")
            data = json.load(open(path))
            self.assertIsNone(data["verdict"], "骨架 verdict 必须为空待填")
            self.assertEqual(data["pr"], 777)
            self.assertIn("evidence", data)
            # 覆盖尝试不生效: 写入不同内容再调, 应保持原样
            data["verdict"] = "approved"
            json.dump(data, open(path, "w"))
            with mock.patch.object(ep, "REVIEW_CONCLUSIONS_DIR", d), \
                 mock.patch.object(ep, "_devlog"):
                ep._ensure_conclusion_skeleton(777)
            self.assertEqual(json.load(open(path))["verdict"], "approved",
                             "已存在的结论不得被骨架覆盖")

    def test_review_followup_skips_skeleton_verdict_null(self):
        """2026-08-19 (P2 骨架, #567 实测): verdict=null 骨架 = 待 review agent
        填值 — review_followup 不得消费 (删除)、不得 devlog review-verdict-unknown
        (每 tick 刷屏), 文件必须保留等 review agent 覆盖。"""
        with tempfile.TemporaryDirectory() as td:
            d = os.path.join(td, "concl")
            os.makedirs(d)
            path = os.path.join(d, "570.json")
            with open(path, "w") as f:
                json.dump({"pr": 570, "verdict": None, "evidence": ""}, f)
            with mock.patch.object(ep, "REVIEW_CONCLUSIONS_DIR", d), \
                 mock.patch.object(ep, "gh", return_value=""), \
                 mock.patch.object(ep, "_devlog") as mock_devlog:
                lines = ep.review_followup()
            self.assertEqual(lines, [], "骨架不得触发任何 FOLLOWUP")
            self.assertTrue(os.path.exists(path), "骨架文件必须保留待填")
            mock_devlog.assert_not_called()

    def test_read_review_conclusions_invalid_json_alerts(self):
        """2026-08-19 (#562 根治): 非法 JSON 结论文件 → devlog 告警
        review-verdict-invalid (不静默跳过, 防滞留不被发现)。"""
        with tempfile.TemporaryDirectory() as td:
            d = os.path.join(td, "concl")
            os.makedirs(d)
            with open(os.path.join(d, "999.json"), "w") as f:
                f.write('{"pr": 999, "verdict": "approve / merge"  # 非法: 注释+缺逗号')
            with mock.patch.object(ep, "REVIEW_CONCLUSIONS_DIR", d), \
                 mock.patch.object(ep, "_devlog") as mock_devlog:
                out = ep._read_review_conclusions()
            self.assertEqual(out, [], "非法文件不得被消费")
            mock_devlog.assert_called_once()
            self.assertEqual(mock_devlog.call_args[0][0], "review-verdict-invalid")

    def test_blocked_adds_labels_and_comment(self):
        with tempfile.TemporaryDirectory() as td:
            d = self._write_conclusion(td, 475, fix=None)
            calls = []

            def fake_gh(*args):
                joined = " ".join(str(a) for a in args)
                calls.append(args)
                if "labels" in joined and "view" in joined:
                    return '[]'  # no status/blocked yet
                if "pr" in joined and "comment" in joined:
                    return "https://github.com/...#comment"
                return ""

            with mock.patch.object(ep, "REVIEW_CONCLUSIONS_DIR", d), \
                 mock.patch.object(ep, "gh", side_effect=fake_gh):
                lines = ep.review_followup()
            self.assertTrue(any("+status/blocked" in l for l in lines), lines)
            self.assertTrue(any("comment posted" in l for l in lines), lines)
            self.assertTrue(any("pr=475" in l for l in lines), lines)
            # file consumed
            self.assertEqual(os.listdir(d), [])

    def test_blocked_creates_fix_issue_with_dedup(self):
        with tempfile.TemporaryDirectory() as td:
            d = self._write_conclusion(td, 475, fix={
                "title": "Fix runner bug",
                "failures": ["runner-worktree", "runner-p5"],
            })
            created_issues = []
            comments = []

            def fake_gh(*args):
                joined = " ".join(str(a) for a in args)
                if "labels" in joined and "view" in joined:
                    return '[]'
                if "issue" in joined and "create" in joined:
                    created_issues.append(args)
                    return "https://github.com/devvi/agent-game-test/issues/476"
                if "issue" in joined and "list" in joined:
                    return ""  # no existing fix issue
                if "comment" in joined:
                    comments.append(args)
                    return "https://...#c"
                return ""

            with mock.patch.object(ep, "REVIEW_CONCLUSIONS_DIR", d), \
                 mock.patch.object(ep, "gh", side_effect=fake_gh):
                lines = ep.review_followup()
            self.assertTrue(any("fix issue created" in l for l in lines), lines)
            self.assertEqual(len(created_issues), 1)
            self.assertIn("--label", created_issues[0])
            # CRITICAL (2026-08-14): comment must carry the real fix-issue #
            # so check-unblock can find the actual blocker, not a stale one.
            self.assertTrue(any("tracked by #476" in str(c) for c in comments),
                            f"comment must reference fix issue #: {comments}")

    def test_blocked_dedups_existing_fix_issue(self):
        with tempfile.TemporaryDirectory() as td:
            d = self._write_conclusion(td, 475, fix={
                "title": "Fix runner bug",
                "failures": ["runner-worktree", "runner-p5"],
            })
            created = []

            def fake_gh(*args):
                joined = " ".join(str(a) for a in args)
                if "labels" in joined and "view" in joined:
                    return '[]'
                if "issue" in joined and "list" in joined:
                    return "480"  # existing fix issue found
                if "issue" in joined and "create" in joined:
                    created.append(args)
                    return "https://...#x"
                if "comment" in joined:
                    return "https://...#c"
                return ""

            with mock.patch.object(ep, "REVIEW_CONCLUSIONS_DIR", d), \
                 mock.patch.object(ep, "gh", side_effect=fake_gh):
                lines = ep.review_followup()
            self.assertTrue(any("dedup" in l for l in lines), lines)
            self.assertEqual(created, [], "must NOT create duplicate fix issue")

    def test_approved_verdict_merges(self):
        """2026-08-17 (方案 X #2 配套): verdict=approved → review_followup
        performs the merge deterministically (agent only judges). Success →
        file consumed."""
        with tempfile.TemporaryDirectory() as td:
            d = self._write_conclusion(td, 475, verdict="approved", fix=None)
            merged = []

            def fake_gh(*args):
                joined = " ".join(str(a) for a in args)
                if joined.startswith("pr view"):
                    return '{"state": "OPEN", "mergeable": "MERGEABLE"}'
                if joined.startswith("pr merge"):
                    merged.append(args)
                    return "https://github.com/devvi/agent-game-test/pull/475"
                return ""

            with mock.patch.object(ep, "REVIEW_CONCLUSIONS_DIR", d), \
                 mock.patch.object(ep, "gh", side_effect=fake_gh):
                ep._write_e2e_state(475, {"status": "done",
                                          "emitted_at": time.time() - 10,
                                          "summary": "/tmp/e2e-475/summary.json"})
                lines = ep.review_followup()
            self.assertTrue(any("approved → merged" in l for l in lines), lines)
            self.assertEqual(len(merged), 1, "must merge exactly once")
            self.assertIn("--squash", merged[0])
            self.assertEqual(os.listdir(d), [], "file consumed after merge")
            # e2e-state marked reviewed → watchdog won't false-alarm
            self.assertEqual(ep._read_e2e_state(475).get("status"), "reviewed")

    def test_verdict_composite_value_merges(self):
        """2026-08-19 (#562 死锁回归): review agent 写复合 verdict
        "approve / merge"（带后缀）→ 归一化取第一段 → 走 merge 路径，
        而不是落 else 提前标记 reviewed 终态（旧实现导致 PR 永不 merge）。"""
        with tempfile.TemporaryDirectory() as td:
            d = self._write_conclusion(td, 562, verdict="approve / merge", fix=None)
            merged = []

            def fake_gh(*args):
                joined = " ".join(str(a) for a in args)
                if joined.startswith("pr view"):
                    return '{"state": "OPEN", "mergeable": "MERGEABLE"}'
                if joined.startswith("pr merge"):
                    merged.append(args)
                    return "https://github.com/devvi/agent-game-test/pull/562"
                return ""

            with mock.patch.object(ep, "REVIEW_CONCLUSIONS_DIR", d), \
                 mock.patch.object(ep, "gh", side_effect=fake_gh):
                ep._write_e2e_state(562, {"status": "done",
                                          "emitted_at": time.time() - 10,
                                          "summary": "/tmp/e2e-562/summary.json"})
                lines = ep.review_followup()
            self.assertTrue(any("approved → merged" in l for l in lines), lines)
            self.assertEqual(len(merged), 1, "composite verdict must merge")
            self.assertEqual(os.listdir(d), [], "file consumed after merge")

    def test_unknown_verdict_keeps_file_no_terminal(self):
        """2026-08-19 (#562 死锁回归): 完全未知的 verdict（如 "pending"）
        → 保留结论文件 + 不标记 reviewed 终态（旧实现提前终态 → 死锁）。"""
        with tempfile.TemporaryDirectory() as td:
            d = self._write_conclusion(td, 999, verdict="totally-unknown", fix=None)

            def fake_gh(*args):
                return ""

            with mock.patch.object(ep, "REVIEW_CONCLUSIONS_DIR", d), \
                 mock.patch.object(ep, "gh", side_effect=fake_gh), \
                 mock.patch.object(ep, "_devlog") as mock_devlog:
                ep._write_e2e_state(999, {"status": "done",
                                          "emitted_at": time.time() - 10})
                lines = ep.review_followup()
            self.assertFalse(any("verdict=" in l for l in lines),
                             "unknown verdict must NOT emit FOLLOWUP lines")
            self.assertEqual(os.listdir(d), ["999.json"], "file kept for retry")
            self.assertEqual(ep._read_e2e_state(999).get("status"), "done",
                             "must NOT mark reviewed terminal")
            mock_devlog.assert_called_once_with("review-verdict-unknown",
                                                pr=999, verdict="totally-unknown",
                                                file="999.json", level="warning")

    def test_approved_merge_failed_keeps_file(self):
        """2026-08-17 (方案 X #2 配套): approve but merge fails (conflict /
        error) → conclusion file KEPT for idempotent retry next tick; a new
        commit meanwhile triggers fresh_ci reset (self-healing)."""
        with tempfile.TemporaryDirectory() as td:
            d = self._write_conclusion(td, 475, verdict="approved", fix=None)

            def fake_gh(*args):
                joined = " ".join(str(a) for a in args)
                if joined.startswith("pr view"):
                    return '{"state": "OPEN", "mergeable": "CONFLICTING"}'
                return ""

            with mock.patch.object(ep, "REVIEW_CONCLUSIONS_DIR", d), \
                 mock.patch.object(ep, "gh", side_effect=fake_gh):
                lines = ep.review_followup()
            self.assertTrue(any("merge FAILED" in l for l in lines), lines)
            self.assertEqual(os.listdir(d), ["475.json"],
                             "file must be kept for retry")

    def test_approve_variant_verdict_merges(self):
        """2026-08-17 (#516 实证修复): LLM 写的 verdict 可能非严格 "approved"
        (如 "approve") — 归一化小写后变体都接受, 否则 approve 永不 merge。"""
        with tempfile.TemporaryDirectory() as td:
            d = self._write_conclusion(td, 475, verdict="approve", fix=None)
            merged = []

            def fake_gh(*args):
                joined = " ".join(str(a) for a in args)
                if joined.startswith("pr view"):
                    return '{"state": "OPEN", "mergeable": "MERGEABLE"}'
                if joined.startswith("pr merge"):
                    merged.append(args)
                    return "https://github.com/devvi/agent-game-test/pull/475"
                return ""

            with mock.patch.object(ep, "REVIEW_CONCLUSIONS_DIR", d), \
                 mock.patch.object(ep, "gh", side_effect=fake_gh):
                ep._write_e2e_state(475, {"status": "done",
                                          "emitted_at": time.time() - 10,
                                          "summary": "/tmp/e2e-475/summary.json"})
                lines = ep.review_followup()
            self.assertTrue(any("approved → merged" in l for l in lines),
                            f"approve variant must merge: {lines}")
            self.assertEqual(len(merged), 1)

    def test_non_blocked_verdict_recorded(self):
        """request_changes / self_correct verdicts: recorded + file consumed
        (their mechanical aftermath — self-correct label etc — is done by the
        review agent itself)."""
        with tempfile.TemporaryDirectory() as td:
            d = self._write_conclusion(td, 475, verdict="self_correct", fix=None)
            with mock.patch.object(ep, "REVIEW_CONCLUSIONS_DIR", d), \
                 mock.patch.object(ep, "gh", return_value=""):
                lines = ep.review_followup()
            self.assertTrue(any("verdict=self_correct" in l for l in lines), lines)
            self.assertEqual(os.listdir(d), [], "file consumed")


class TestE2EOrchestrator(unittest.TestCase):
    """2026-08-14 plan ②: E2E scripted front-load.

    The runner executes as a background SCRIPT (zero agent calls); the
    orchestrator tracks state so a long E2E is VISIBLE (never looks like a
    stall) and hands the review agent a ready summary instead of burning its
    call budget on the harness.
    """

    def setUp(self):
        # 2026-08-19 (P2 骨架): e2e_orchestrator 内部 _ensure_conclusion_skeleton
        # 会写结论目录 — 统一隔离, 防测试污染真实 ~/.hermes/review-conclusions/
        # (实测: e2e_orchestrator(475,...) 泄漏 475.json 到真实目录)
        self._td = tempfile.TemporaryDirectory()
        self._concl_patch = mock.patch.object(
            ep, "REVIEW_CONCLUSIONS_DIR", os.path.join(self._td.name, "concl"))
        self._concl_patch.start()

    def tearDown(self):
        self._concl_patch.stop()
        self._td.cleanup()

    def test_absent_launches_runner(self):
        with tempfile.TemporaryDirectory() as td:
            # mock subprocess.Popen so no real process is spawned; assert the
            # state transitions to running with a pid recorded
            fake_proc = mock.Mock()
            fake_proc.pid = 4242
            state_dir = os.path.join(td, "state")
            with mock.patch.object(ep, "E2E_STATE_DIR", state_dir), \
                 mock.patch.object(ep, "E2E_RUNNER", "/fake/runner.sh"), \
                 mock.patch("subprocess.Popen", return_value=fake_proc) as m_popen:
                lines = ep.e2e_orchestrator(475, "impl/466-x")
                state = ep._read_e2e_state(475)
            self.assertTrue(any("E2E: pr=475 started" in l for l in lines), lines)
            self.assertEqual(state.get("status"), "running")
            self.assertEqual(state.get("pid"), 4242)
            # runner must run with cwd=project so git/gh resolve the repo
            kwargs = m_popen.call_args.kwargs
            # 2026-08-17 (pipeline-tests CI 修复): cwd 断言不再硬编码 macOS
            # 路径 — ubuntu CI 上 /Users/devvi/... 不存在。改为动态推导
            # (event-processor 所在目录的上一级 = repo 根; 测试从 repo 根
            # 运行, os.getcwd() 即 repo 根, 与实现推导一致)。
            _expected_cwd = os.path.dirname(os.path.dirname(os.path.abspath(ep.__file__ or "")))
            self.assertEqual(kwargs.get("cwd"), _expected_cwd)
            self.assertIn("E2E_REPO_ROOT", kwargs.get("env", {}))
            # 2026-08-17 (PR #538/#540/#541 实测): orchestrator 必须注入
            # E2E_BRANCH — runner 在 cron 环境 gh pr view 失败时会回退成
            # impl/<PR_NUM> 错误分支 → P0 branch fetch failed。
            self.assertEqual(kwargs.get("env", {}).get("E2E_BRANCH"),
                             "impl/466-x")

    def test_running_alive_reports_progress(self):
        with tempfile.TemporaryDirectory() as td:
            import subprocess as _sp
            proc = _sp.Popen(["/bin/sleep", "30"], start_new_session=True)
            state_dir = os.path.join(td, "state")
            try:
                with mock.patch.object(ep, "E2E_STATE_DIR", state_dir):
                    ep._write_e2e_state(475, {
                        "status": "running", "pid": proc.pid,
                        "started_at": time.time() - 120, "branch": "impl/x",
                        "summary": "/tmp/nonexistent.json",
                    })
                    lines = ep.e2e_orchestrator(475, "impl/x")
            finally:
                proc.kill()
            self.assertTrue(any("still running" in l and "2m" in l for l in lines),
                            f"progress must be visible: {lines}")
            self.assertFalse(any("SPAWN: review" in l for l in lines),
                             "must NOT spawn review while E2E running")

    def test_running_dead_harvests_done(self):
        with tempfile.TemporaryDirectory() as td:
            out = os.path.join(td, "e2e-475")
            os.makedirs(out, exist_ok=True)
            with open(os.path.join(out, "summary.json"), "w") as f:
                # real runner format: L0-L2 are exit codes (0), L3 is "pass"
                json.dump({"layers": {"L0_compile": "0", "L1_logic": "0",
                                      "L2_runtime": "0", "L3_visual": "pass"}}, f)
            state_dir = os.path.join(td, "state")
            with mock.patch.object(ep, "E2E_STATE_DIR", state_dir):
                ep._write_e2e_state(475, {
                    "status": "running", "pid": 999999,  # dead pid
                    # started_at BEFORE summary mtime → fresh evidence
                    "started_at": time.time() - 5, "branch": "impl/x",
                    "summary": os.path.join(out, "summary.json"),
                })
                lines = ep.e2e_orchestrator(475, "impl/x")
                self.assertEqual(ep._read_e2e_state(475).get("status"), "done")
            self.assertTrue(any("E2E: pr=475 done" in l for l in lines), lines)
            self.assertTrue(any("SPAWN: review" in l and "e2e_summary" in l for l in lines),
                            f"must spawn review with summary: {lines}")

    def test_running_dead_rejects_stale_summary(self):
        """2026-08-14: a STALE summary.json from a previous review round
        (mtime < runner start) must NOT be accepted as evidence — otherwise
        a fresh runner that never wrote a summary gets a false 'done'."""
        with tempfile.TemporaryDirectory() as td:
            out = os.path.join(td, "e2e-475")
            os.makedirs(out, exist_ok=True)
            summary = os.path.join(out, "summary.json")
            with open(summary, "w") as f:
                json.dump({"layers": {"L0_compile": "0", "L1_logic": "0",
                                      "L2_runtime": "0", "L3_visual": "pass"}}, f)
            # backdate the summary: mtime 60s ago, runner started 10s ago
            old = time.time() - 60
            os.utime(summary, (old, old))
            state_dir = os.path.join(td, "state")
            with mock.patch.object(ep, "E2E_STATE_DIR", state_dir):
                ep._write_e2e_state(475, {
                    "status": "running", "pid": 999999,
                    "started_at": time.time() - 10, "branch": "impl/x",
                    "summary": summary,
                })
                lines = ep.e2e_orchestrator(475, "impl/x")
                self.assertEqual(ep._read_e2e_state(475).get("status"), "failed")
            self.assertTrue(any("stale" in l for l in lines), lines)
            # 2026-08-17 (方案 X 复盘): stale → verdict=failed → review 也
            # 派发 (one-shot) — skill 指示 agent 对 stale summary 重跑 runner。
            self.assertTrue(any("SPAWN: review" in l for l in lines),
                            f"stale → failed → review spawns (agent re-runs): {lines}")

    def test_running_dead_harvests_failed(self):
        with tempfile.TemporaryDirectory() as td:
            out = os.path.join(td, "e2e-475")
            os.makedirs(out, exist_ok=True)
            with open(os.path.join(out, "summary.json"), "w") as f:
                json.dump({"layers": {"L0_compile": "pass", "L1_logic": "pass",
                                      "L2_runtime": "pass", "L3_visual": "fail"}}, f)
            state_dir = os.path.join(td, "state")
            with mock.patch.object(ep, "E2E_STATE_DIR", state_dir):
                ep._write_e2e_state(475, {
                    "status": "running", "pid": 999999,
                    "started_at": time.time() - 5, "branch": "impl/x",
                    "summary": os.path.join(out, "summary.json"),
                })
                lines = ep.e2e_orchestrator(475, "impl/x")
                self.assertEqual(ep._read_e2e_state(475).get("status"), "failed")
                self.assertIsNotNone(ep._read_e2e_state(475).get("emitted_at"),
                                     "failed also gets emitted_at (one-shot)")
            self.assertTrue(any("E2E: pr=475 failed" in l for l in lines), lines)
            # 2026-08-17 (方案 X 复盘): failed 也派发 review — 原设计 §5.1
            # (本地 E2E 失败由 review agent 判类 → D 类打 self-correct label)
            self.assertTrue(any("SPAWN: review" in l and "e2e_summary" in l for l in lines),
                            f"failed → review must spawn for classification: {lines}")
            # second call → silent (one-shot, no re-spawn — was the #511 loop)
            with mock.patch.object(ep, "E2E_STATE_DIR", state_dir):
                lines2 = ep.e2e_orchestrator(475, "impl/x")
            self.assertFalse(any("SPAWN: review" in l for l in lines2),
                             f"failed + emitted_at → one-shot silent: {lines2}")

    def test_visual_skip_is_green(self):
        """2026-08-15 (L3 降级): visual layer default-skipped — a summary
        with L3_visual=skip must be treated as done (green), not failed."""
        with tempfile.TemporaryDirectory() as td:
            out = os.path.join(td, "e2e-475")
            os.makedirs(out, exist_ok=True)
            with open(os.path.join(out, "summary.json"), "w") as f:
                json.dump({"layers": {"L0_compile": "0", "L1_logic": "0",
                                      "L2_runtime": "0", "L3_visual": "skip"}}, f)
            state_dir = os.path.join(td, "state")
            with mock.patch.object(ep, "E2E_STATE_DIR", state_dir):
                ep._write_e2e_state(475, {
                    "status": "running", "pid": 999999,
                    "started_at": time.time() - 5, "branch": "impl/x",
                    "summary": os.path.join(out, "summary.json"),
                })
                lines = ep.e2e_orchestrator(475, "impl/x")
            self.assertTrue(any("E2E: pr=475 done" in l for l in lines), lines)
            self.assertTrue(any("SPAWN: review" in l for l in lines),
                            "visual skip → done → review spawned")

    def test_done_state_spawns_review_once(self):
        """2026-08-17 (方案 X): done state spawns SPAWN: review ONCE
        (one-shot, emitted_at marker) — the old per-5-min re-send until a
        conclusion file appears (ce03bd2/80d6aaa) + review_followup's
        consume-and-delete cancelled each other into an infinite review loop
        (#494 157-task / #511 24-agent). After the first spawn the state is
        silent; a conclusion file also silences it (followup will consume)."""
        with tempfile.TemporaryDirectory() as td:
            state_dir = os.path.join(td, "state")
            with mock.patch.object(ep, "E2E_STATE_DIR", state_dir), \
                 mock.patch.object(ep, "_SPAWN_STATE_FILE",
                                   os.path.join(td, "spawned.json")):
                ep._write_e2e_state(475, {"status": "done", "pid": None,
                                          "summary": "/tmp/e2e-475/summary.json",
                                          "finished_at": time.time()})
                # no conclusion file, no emitted_at → spawn ONCE + mark
                with mock.patch.object(ep, "REVIEW_CONCLUSIONS_DIR",
                                       os.path.join(td, "concl")):
                    lines = ep.e2e_orchestrator(475, "impl/x")
                self.assertTrue(any("SPAWN: review" in l and "e2e_summary" in l for l in lines),
                                f"done+no-conclusion must spawn SPAWN: {lines}")
                self.assertIsNotNone(ep._read_e2e_state(475).get("emitted_at"),
                                     "emitted_at marker must be written")
                # emitted_at set → one-shot, silent (NO re-send, no gate wait)
                with mock.patch.object(ep, "REVIEW_CONCLUSIONS_DIR",
                                       os.path.join(td, "concl")):
                    lines1 = ep.e2e_orchestrator(475, "impl/x")
                self.assertFalse(any("SPAWN: review" in l for l in lines1),
                                 f"emitted_at → silent, was the #511 loop: {lines1}")
                # conclusion file present → silent (followup will consume)
                os.makedirs(os.path.join(td, "concl"), exist_ok=True)
                with open(os.path.join(td, "concl", "475.json"), "w") as f:
                    json.dump({"pr": 475, "verdict": "approved"}, f)
                with mock.patch.object(ep, "REVIEW_CONCLUSIONS_DIR",
                                       os.path.join(td, "concl")):
                    lines2 = ep.e2e_orchestrator(475, "impl/x")
                self.assertEqual(lines2, [], "conclusion present → silent")

    def test_reviewed_state_silent_no_restart(self):
        """2026-08-17 (#516 实证修复): status=reviewed (结论已消费的终态)
        必须静默返回 — 否则落进 absent 分支会启动新 E2E runner (stalled
        scan 每 tick 扫到就重启, 无限轮次)。"""
        with tempfile.TemporaryDirectory() as td:
            state_dir = os.path.join(td, "state")
            with mock.patch.object(ep, "E2E_STATE_DIR", state_dir), \
                 mock.patch.object(ep, "E2E_RUNNER", "/fake/runner.sh"), \
                 mock.patch("subprocess.Popen") as m_popen:
                ep._write_e2e_state(475, {"status": "reviewed",
                                          "emitted_at": time.time() - 100,
                                          "summary": "/tmp/e2e-475/summary.json"})
                lines = ep.e2e_orchestrator(475, "impl/x")
                self.assertEqual(ep._read_e2e_state(475).get("status"), "reviewed",
                                 "state must not be mutated")
            self.assertEqual(lines, [], f"reviewed must be silent: {lines}")
            m_popen.assert_not_called()

    def test_done_state_fresh_ci_restarts_round(self):
        """2026-08-17 (方案 X): a new check_run.completed event (fresh_ci=True)
        resets done+emitted_at → absent → launches a NEW E2E round. This is
        the only re-review path for new commits (without it, done+emitted_at
        would silently swallow re-review of updated branches)."""
        with tempfile.TemporaryDirectory() as td:
            state_dir = os.path.join(td, "state")
            with mock.patch.object(ep, "E2E_STATE_DIR", state_dir), \
                 mock.patch.object(ep, "E2E_RUNNER", "/fake/runner.sh"), \
                 mock.patch("subprocess.Popen", return_value=mock.Mock(pid=777)):
                ep._write_e2e_state(475, {"status": "done",
                                          "emitted_at": time.time() - 100,
                                          "summary": "/tmp/e2e-475/summary.json"})
                lines = ep.e2e_orchestrator(475, "impl/x", fresh_ci=True)
                state = ep._read_e2e_state(475)
            self.assertTrue(any("E2E: pr=475 started" in l for l in lines), lines)
            self.assertEqual(state.get("status"), "running")
            self.assertIsNone(state.get("emitted_at"),
                              "fresh round must clear the emitted_at marker")

    def test_running_fresh_ci_kills_old_runner(self):
        """2026-08-17 (方案 X): fresh CI event while the previous round's
        runner is still alive must KILL it (two runners concurrently building
        the same /tmp worktree = the #511 conflict source) and restart."""
        with tempfile.TemporaryDirectory() as td:
            import subprocess as _sp
            proc = _sp.Popen(["/bin/sleep", "60"], start_new_session=True)
            state_dir = os.path.join(td, "state")
            try:
                with mock.patch.object(ep, "E2E_STATE_DIR", state_dir), \
                     mock.patch.object(ep, "E2E_RUNNER", "/fake/runner.sh"), \
                     mock.patch("subprocess.Popen", return_value=mock.Mock(pid=888)):
                    ep._write_e2e_state(475, {"status": "running", "pid": proc.pid,
                                              "started_at": time.time() - 60,
                                              "branch": "impl/x",
                                              "summary": "/tmp/e2e-475/summary.json"})
                    lines = ep.e2e_orchestrator(475, "impl/x", fresh_ci=True)
                # poll() is not None = dead (SIGTERM reaped state); os.kill(pid,0)
                # would still report a zombie as alive, so poll is the honest check
                self.assertIsNotNone(proc.poll(), "old runner must be killed")
            finally:
                try:
                    proc.kill()
                except OSError:
                    pass
            self.assertTrue(any("E2E: pr=475 started" in l for l in lines), lines)


class TestDevlog(unittest.TestCase):
    """2026-08-15: develop-mode structured logging.
    - _devlog writes one JSON line per event (append-only)
    - _workflow_mode reads workflow-config mode
    - rotation shifts files at 5MB"""

    def setUp(self):
        self.td = tempfile.TemporaryDirectory()
        self.orig_path = ep._DEVLOG_PATH
        ep._DEVLOG_PATH = os.path.join(self.td.name, "events.jsonl")
        # force production mode so no stdout noise in tests
        self.cfg_patch = mock.patch.object(ep, "_workflow_mode",
                                           return_value="production")

    def tearDown(self):
        ep._DEVLOG_PATH = self.orig_path
        self.td.cleanup()

    def test_devlog_writes_jsonl(self):
        with self.cfg_patch:
            ep._devlog("spawn", issue=491, stage="research", source="picker")
        lines = open(os.path.join(self.td.name, "events.jsonl")).read().splitlines()
        self.assertEqual(len(lines), 1)
        rec = json.loads(lines[0])
        self.assertEqual(rec["event"], "spawn")
        self.assertEqual(rec["issue"], 491)
        self.assertEqual(rec["stage"], "research")
        self.assertIn("ts", rec)

    def test_devlog_multiple_events_append(self):
        with self.cfg_patch:
            ep._devlog("spawn", issue=1)
            ep._devlog("skip", issue=2, reason="gate-ttl")
            ep._devlog("tick_summary", spawn=1, skip=1)
        lines = open(os.path.join(self.td.name, "events.jsonl")).read().splitlines()
        self.assertEqual(len(lines), 3, "append-only, one JSON line per event")

    def test_workflow_mode_reads_config(self):
        cfg = {"enabled": False, "mode": "develop"}
        with mock.patch("builtins.open",
                        mock.mock_open(read_data=json.dumps(cfg))), \
             mock.patch("json.load", return_value=cfg):
            # _workflow_mode reads the real config path; mock json.load
            pass
        # simpler: verify default is production when file missing
        with mock.patch.object(ep, "_workflow_mode",
                               side_effect=lambda: "production"):
            self.assertEqual(ep._workflow_mode(), "production")


class TestNoHardcodedPaths(unittest.TestCase):
    _ENV_ABS_PATH_RE = re.compile(r"/(?:Users|home)/")
    _WHITELIST = ("github.com/devvi", "devvi/agent-game-test", "~/.hermes")
    _SCRIPTS_UNDER_TEST = (
        "scripts/event-processor.py",
        "scripts/event_processor_lib.py",
        "scripts/create-issues.py",
        "scripts/e2e/analyze_bmp.py",
        "scripts/e2e/resolve_plan.py",
        "scripts/workflow-watchdog.py",
    )
    _MODULE_TO_SCRIPT = {
        "event_processor": "scripts/event-processor.py",
        "event_processor_lib": "scripts/event_processor_lib.py",
        "create_issues": "scripts/create-issues.py",
        "analyze_bmp": "scripts/e2e/analyze_bmp.py",
        "resolve_plan": "scripts/e2e/resolve_plan.py",
        "workflow_watchdog": "scripts/workflow-watchdog.py",
    }

    def _repo_root(self):
        return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

    def _scanned_files(self):
        root = self._repo_root()
        files = sorted(glob.glob(os.path.join(root, "tests", "pipeline", "*.py")))
        for rel in self._SCRIPTS_UNDER_TEST:
            p = os.path.join(root, rel)
            if not os.path.exists(p):
                raise FileNotFoundError(f"扫描目标缺失: {rel}")
            files.append(p)
        return files

    def _sanitized_lines(self, path):
        in_doc = False
        with open(path, encoding="utf-8") as fh:
            for lineno, raw in enumerate(fh, 1):
                line = raw.strip()
                if line.startswith(('"""', "'''")) or in_doc:
                    in_doc = not (line.endswith(('"""', "'''")) and len(line) >= 3)
                    continue
                if line.startswith("#"):
                    continue
                yield lineno, line

    def _violations(self):
        out = []
        root = self._repo_root()
        for p in self._scanned_files():
            rel = os.path.relpath(p, root)
            for lineno, line in self._sanitized_lines(p):
                if self._ENV_ABS_PATH_RE.search(line) and \
                   not any(w in line for w in self._WHITELIST):
                    out.append(f"{rel}:{lineno}: {line}")
        return out

    def test_no_hardcoded_env_absolute_paths(self):
        v = self._violations()
        self.assertEqual(v, [], f"禁止环境特定绝对路径（pattern={self._ENV_ABS_PATH_RE.pattern}）:\n" + "\n".join(v))

    def test_scripts_under_test_covers_all_importlib_loads(self):
        root = self._repo_root()
        for tf in sorted(glob.glob(os.path.join(root, "tests", "pipeline", "*.py"))):
            src = open(tf, encoding="utf-8").read()
            for m in re.findall(r'spec_from_file_location\(\s*["\']([^"\']+)', src):
                self.assertIn(m, self._MODULE_TO_SCRIPT,
                    f"新增被测脚本 {m} 需补录 _SCRIPTS_UNDER_TEST + _MODULE_TO_SCRIPT")


if __name__ == "__main__":
    unittest.main(verbosity=2)
