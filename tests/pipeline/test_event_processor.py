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
import importlib.util
import json
import os
import sys
import tempfile
import unittest
from unittest import mock

_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
_SCRIPT_PATH = os.path.join(_REPO_ROOT, "scripts", "event-processor.py")

_spec = importlib.util.spec_from_file_location("event_processor", _SCRIPT_PATH)
ep = importlib.util.module_from_spec(_spec)
assert _spec is not None and _spec.loader is not None
_spec.loader.exec_module(ep)


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
                        issue_cache=None):
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
             mock.patch.object(ep, "_GH_CACHE", {}):
            return ep.preprocess()

    def test_check_run_failure_spawns_self_correct(self):
        ev = {"_key": "check_run.completed#154", "type": "check_run",
              "issue": 154, "branch": "impl/154-x", "conclusion": "failure"}
        out = self._run_preprocess(self._events(ev))
        self.assertTrue(any(l.startswith("SPAWN: self-correct,issue=154") for l in out),
                        f"unexpected output: {out}")

    def test_check_run_success_spawns_review(self):
        ev = {"_key": "check_run.completed#155", "type": "check_run",
              "issue": 155, "branch": "impl/155-y", "conclusion": "success"}
        out = self._run_preprocess(self._events(ev))
        self.assertTrue(any(l.startswith("SPAWN: review,issue=155") for l in out),
                        f"unexpected output: {out}")

    def test_non_impl_branch_passes_to_llm(self):
        ev = {"_key": "check_run.completed#156", "type": "check_run",
              "issue": 156, "branch": "plan/156-z", "conclusion": "success"}
        out = self._run_preprocess(self._events(ev))
        self.assertTrue(any(l.startswith("P1: check_run.completed,issue=156") for l in out))

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
             mock.patch.object(ep, "reconcile"), \
             mock.patch.object(ep, "pick_next_issue") as pick, \
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
             mock.patch.object(ep, "reconcile"), \
             mock.patch.object(ep, "pick_next_issue") as pick, \
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
             mock.patch("subprocess.run", fake_run), \
             mock.patch("sys.stdout") as out:
            ep.pick_next_issue()
            first = "".join(str(c.args[0]) for c in out.write.call_args_list)
            out.reset_mock()
            ep.pick_next_issue()
            second = "".join(str(c.args[0]) for c in out.write.call_args_list)
        self.assertIn("SPAWN: plan,issue=358", first)
        self.assertNotIn("SPAWN: plan,issue=358", second,
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
             mock.patch("subprocess.run", fake_run), \
             mock.patch("sys.stdout") as out:
            ep.pick_next_issue()  # t=now → emits, records marker
            out.reset_mock()
            # advance clock past TTL
            old_time = ep.time.time
            ep.time.time = lambda: old_time() + ep._SPAWN_TTL_SECONDS + 10
            try:
                ep.pick_next_issue()
            finally:
                ep.time.time = old_time
            after_ttl = "".join(str(c.args[0]) for c in out.write.call_args_list)
        self.assertIn("SPAWN: plan,issue=359", after_ttl,
                      "TTL expiry must allow re-spawn")

    def test_group_keeps_highest_priority_only(self):
        """Same issue with both a labeled event and a check_run event →
        only the check_run (P1) survives."""
        ev_high = {"_key": "check_run.completed#160", "type": "check_run",
                   "issue": 160, "branch": "impl/160-a", "conclusion": "success"}
        ev_low = {"_key": "issues.labeled#160:workflow/implement", "type": "issues.labeled",
                  "issue": 160, "label": "workflow/implement"}
        out = self._run_preprocess(self._events(ev_high, ev_low))
        self.assertEqual(len(out), 1, f"expected 1 SPAWN, got {out}")
        self.assertIn("SPAWN: review,issue=160", out[0])

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
        self.assertIn("SPAWN: review", out[0])

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

    def test_reconcile_injects_label_event_once(self):
        """reconcile() must not re-inject the same label event every tick
        (it re-emitted SPAWN every tick → 14 duplicate spawns for #393).
        Label state is tracked: an injected label is not re-injected within
        RECONCILE_REINJECT_AGE."""
        issue = {"number": 393, "labels": [{"name": "workflow/implement"}]}
        written = []
        with tempfile.TemporaryDirectory() as td, \
             mock.patch.object(ep, "RECONCILE_LABEL_STATE_FILE",
                               os.path.join(td, "reconcile-labels.json")), \
             mock.patch.object(ep, "read_pending", return_value=[]), \
             mock.patch.object(ep, "_ensure_issues_cache", return_value=[issue]), \
             mock.patch.object(ep, "write_pending", side_effect=written.append):
            ep.reconcile()
            first_count = len(written[-1]) if written else 0
            written.clear()
            ep.reconcile()
        self.assertEqual(first_count, 1, "first reconcile injects the label event")
        self.assertEqual(len(written), 0, "second reconcile must NOT re-inject")

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
        with mock.patch.object(ep, "gh", side_effect=fake_gh):
            cmds = ep._quick_stalled_scan()
        self.assertTrue(any("STALLED: check-review,pr=444" in c for c in cmds),
                        f"stalled scan must see impl PR: {cmds}")

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

    def test_picks_backlog_with_resolved_deps(self):
        issues = [
            self._issue(1, ["workflow/backlog"]),
            self._issue(2, ["workflow/backlog", "priority/high"]),
            self._issue(3, ["workflow/available"]),  # not backlog → skip
        ]
        with mock.patch.object(ep, "_ensure_issues_cache", return_value=issues), \
             mock.patch.object(ep, "_get_active_issue_target_files", return_value=set()), \
             mock.patch.object(ep, "_has_unresolved_dependencies", return_value=[]), \
             mock.patch.object(ep, "_has_file_conflict", return_value=False):
            picked = ep._pick_candidates(4)
        self.assertEqual(picked, [2, 1])  # priority/high sorts first

    def test_skips_unresolved_deps_and_conflicts(self):
        issues = [
            self._issue(10, ["workflow/backlog"]),
            self._issue(11, ["workflow/backlog"]),
        ]
        with mock.patch.object(ep, "_ensure_issues_cache", return_value=issues), \
             mock.patch.object(ep, "_get_active_issue_target_files", return_value=set()):
            with mock.patch.object(ep, "_has_unresolved_dependencies",
                                   side_effect=[[{"issue": 5, "type": "full"}], []]):
                # Conflict check only runs for candidates that PASS the dep
                # check (issue 11). Issue 10 never reaches it.
                with mock.patch.object(ep, "_has_file_conflict", return_value=False):
                    picked = ep._pick_candidates(4)
        self.assertEqual(picked, [11])

    def test_respects_limit(self):
        issues = [self._issue(n, ["workflow/backlog"]) for n in range(20, 26)]
        with mock.patch.object(ep, "_ensure_issues_cache", return_value=issues), \
             mock.patch.object(ep, "_get_active_issue_target_files", return_value=set()), \
             mock.patch.object(ep, "_has_unresolved_dependencies", return_value=[]), \
             mock.patch.object(ep, "_has_file_conflict", return_value=False):
            picked = ep._pick_candidates(2)
        self.assertEqual(len(picked), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
