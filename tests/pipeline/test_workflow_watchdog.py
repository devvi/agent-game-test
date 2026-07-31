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


if __name__ == "__main__":
    unittest.main(verbosity=2)
