#!/usr/bin/env python3
"""Unit tests for workflow-watchdog.py (P2 silent-SPAWN detection)."""
import importlib.util
import io
import json
import os
import tempfile
import time
import unittest
from unittest import mock

_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
_SCRIPT_PATH = os.path.join(_REPO_ROOT, "scripts", "workflow-watchdog.py")

_spec = importlib.util.spec_from_file_location("workflow_watchdog", _SCRIPT_PATH)
wd = importlib.util.module_from_spec(_spec)
assert _spec is not None and _spec.loader is not None
_spec.loader.exec_module(wd)


class WatchdogTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = self.tmp.name
        wd.PENDING_FILE = os.path.join(self.base, "workflow-pending.json")
        wd.STATE_FILE = os.path.join(self.base, "workflow-watchdog-state.json")
        wd.AUDIT_FILE = os.path.join(self.base, "workflow-audit.jsonl")
        wd.E2E_STATE_DIR = os.path.join(self.base, "e2e-state")
        wd.REVIEW_CONCLUSIONS_DIR = os.path.join(self.base, "review-conclusions")
        wd.FEISHU_WEBHOOK = "http://127.0.0.1:1/x"  # unreachable → POST fails, print path runs

        # Real machine config is enabled:false; force enabled for these tests.
        real_read_json = wd.read_json

        def fake_read_json(path, default):
            if path.endswith("workflow-config.json"):
                return {"enabled": True}
            return real_read_json(path, default)

        self._real_read_json = real_read_json
        wd.read_json = fake_read_json
        self._fake_read_json = fake_read_json

    def tearDown(self):
        wd.read_json = self._real_read_json
        self.tmp.cleanup()

    def _write_pending(self, events):
        with open(wd.PENDING_FILE, "w") as f:
            json.dump({"events": events}, f)

    def _write_audit(self, outputs):
        with open(wd.AUDIT_FILE, "w") as f:
            for out in outputs:
                f.write(json.dumps({"ts": "x", "tick": "end", "output": out}) + "\n")

    def _write_state(self, last_alert_ts):
        with open(wd.STATE_FILE, "w") as f:
            json.dump({"last_alert_ts": last_alert_ts}, f)

    def _run(self):
        buf = io.StringIO()
        with mock.patch("sys.stdout", buf):
            wd.main()
        return buf.getvalue()

    def test_no_pending_events_silent(self):
        self._write_pending([])
        self.assertEqual(self._run(), "")

    def test_pending_plus_all_silent_alerts(self):
        self._write_pending([{"type": "issues.labeled", "issue": 1}])
        self._write_audit(["[SILENT]"] * 6)
        self._write_state(0)
        self.assertIn("沉默", self._run())

    def test_paused_config_silent(self):
        """Workflow config enabled:false → silence is by design, no alert."""
        self._write_pending([{"type": "issues.labeled", "issue": 1}])
        self._write_audit(["[SILENT]"] * 6)
        self._write_state(0)
        # Override fake: config disabled
        def disabled_cfg(path, default):
            if path.endswith("workflow-config.json"):
                return {"enabled": False}
            return self._real_read_json(path, default)

        wd.read_json = disabled_cfg
        try:
            self.assertEqual(self._run(), "")
        finally:
            wd.read_json = self._fake_read_json

    def test_rate_limited_silent(self):
        self._write_pending([{"type": "issues.labeled", "issue": 1}])
        self._write_audit(["[SILENT]"] * 6)
        self._write_state(time.time())  # alert just fired
        self.assertEqual(self._run(), "")

    def test_spawn_seen_silent(self):
        self._write_pending([{"type": "issues.labeled", "issue": 1}])
        self._write_audit(["[SILENT]"] * 5 + ["SPAWN: review,issue=1,pr=2,branch=impl/1"])
        self._write_state(0)
        self.assertEqual(self._run(), "")

    # ── 2026-08-17 (方案 X 兜底): review-stuck / conclusion-stale ──

    def test_review_stuck_alerts(self):
        """e2e done + emitted_at 超时 + 无结论文件 → 告警 (SPAWN 被吞 /
        review agent 失败)。one-shot 不自动重发, 必须告警暴露。"""
        os.makedirs(wd.E2E_STATE_DIR, exist_ok=True)
        with open(os.path.join(wd.E2E_STATE_DIR, "511.json"), "w") as f:
            json.dump({"status": "done", "emitted_at": time.time() - 3600}, f)
        self._write_state(0)
        self.assertIn("review 卡住", self._run())

    def test_review_stuck_skips_reviewed_state(self):
        """status=reviewed (结论已消费) → 不告警 (防误报)。"""
        os.makedirs(wd.E2E_STATE_DIR, exist_ok=True)
        with open(os.path.join(wd.E2E_STATE_DIR, "511.json"), "w") as f:
            json.dump({"status": "reviewed", "emitted_at": time.time() - 3600}, f)
        self._write_state(0)
        self.assertEqual(self._run(), "")

    def test_review_stuck_skips_recent_emission(self):
        """emitted_at 未超时 (30min 内) → 等 review agent, 不告警。"""
        os.makedirs(wd.E2E_STATE_DIR, exist_ok=True)
        with open(os.path.join(wd.E2E_STATE_DIR, "511.json"), "w") as f:
            json.dump({"status": "done", "emitted_at": time.time() - 60}, f)
        self._write_state(0)
        self.assertEqual(self._run(), "")

    def test_conclusion_stale_alerts(self):
        """结论文件滞留 > 60min (followup 未消费 / merge 失败卡住) → 告警。"""
        os.makedirs(wd.REVIEW_CONCLUSIONS_DIR, exist_ok=True)
        p = os.path.join(wd.REVIEW_CONCLUSIONS_DIR, "511.json")
        with open(p, "w") as f:
            json.dump({"pr": 511, "verdict": "approved"}, f)
        old = time.time() - 7200
        os.utime(p, (old, old))
        self._write_state(0)
        self.assertIn("结论文件滞留", self._run())

    def test_conclusion_invalid_verdict_alerts_immediately(self):
        """2026-08-19 (#562 根治): verdict 归一化后仍非法 (自由文本如
        "pending") → 立即告警, 不等 60min 滞留 (review_followup 不消费
        非法文件)。注意 "approve / merge" 归一化后 = "approve" 已合法
        (修复效果), 不会被此检查命中。"""
        os.makedirs(wd.REVIEW_CONCLUSIONS_DIR, exist_ok=True)
        p = os.path.join(wd.REVIEW_CONCLUSIONS_DIR, "562.json")
        with open(p, "w") as f:
            json.dump({"pr": 562, "verdict": "pending"}, f)  # 新鲜文件
        self._write_state(0)
        out = self._run()
        self.assertIn("verdict 非法", out)
        self.assertNotIn("结论文件滞留", out, "非法 verdict 已告警, 不重复报滞留")

    def test_conclusion_invalid_json_alerts_immediately(self):
        """2026-08-19 (#562 根治): JSON 解析失败 → 立即告警。"""
        os.makedirs(wd.REVIEW_CONCLUSIONS_DIR, exist_ok=True)
        p = os.path.join(wd.REVIEW_CONCLUSIONS_DIR, "999.json")
        with open(p, "w") as f:
            f.write("{not valid json")
        self._write_state(0)
        self.assertIn("JSON 非法", self._run())


if __name__ == "__main__":
    unittest.main(verbosity=2)
