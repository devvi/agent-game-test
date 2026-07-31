#!/usr/bin/env python3
"""Silent-SPAWN watchdog (P2, 2026-07-31).

Detects the failure class documented in workflow-token-diagnostics:
  pending events exist, but event-processor.py keeps outputting
  [SILENT] / [PAUSED] / [ERROR] instead of SPAWN instructions.

Runs as a no-agent cron (every 5m). Outputs NOTHING when healthy
(empty stdout = silent, per no_agent semantics). When the failure
is detected it POSTs one Feishu alert and prints a short line.

Detection logic:
  1. Read ~/.hermes/workflow-pending.json — any events?
  2. Read the last N audit records (~/.hermes/workflow-audit.jsonl)
  3. If pending has events AND all recent ticks emitted no SPAWN
     (silent/paused/error) AND workflow is not paused → ALERT.
  4. Rate-limit: at most one alert per 60 min per detection class.
"""
import json
import os
import time
import urllib.request

HOME = os.path.expanduser("~")
PENDING_FILE = os.path.join(HOME, ".hermes", "workflow-pending.json")
AUDIT_FILE = os.path.join(HOME, ".hermes", "workflow-audit.jsonl")
STATE_FILE = os.path.join(HOME, ".hermes", "workflow-watchdog-state.json")
FEISHU_WEBHOOK = "https://open.feishu.cn/open-apis/bot/v2/hook/76101281-b359-49ab-ae2f-fc486bf65958"
LOOKBACK_TICKS = 6  # ~6 minutes of 1m ticks
ALERT_COOLDOWN = 3600  # seconds


def read_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return default


def read_audit_tail(n):
    try:
        with open(AUDIT_FILE) as f:
            lines = f.readlines()[-n:]
        return [json.loads(l) for l in lines if l.strip()]
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return []


def post_feishu(text):
    payload = json.dumps({"msg_type": "text", "content": {"text": text}}).encode()
    req = urllib.request.Request(
        FEISHU_WEBHOOK, data=payload,
        headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status == 200
    except Exception:
        return False


def main():
    now = time.time()
    state = read_json(STATE_FILE, {})

    # Workflow paused? If the config says disabled, silence is EXPECTED.
    cfg = read_json(os.path.join(HOME, ".hermes", "workflow-config.json"), {})
    if not cfg.get("enabled", True):
        return  # paused/disabled — silence is by design

    pending = read_json(PENDING_FILE, {"events": []})
    events = pending.get("events", [])
    if not events:
        return  # nothing pending — silence is correct

    tail = read_audit_tail(LOOKBACK_TICKS)
    if not tail:
        return  # no audit data yet — can't judge

    # Are all recent ticks non-SPAWN (silent/paused/error)?
    silent_all = all(
        r.get("output", "") in ("[SILENT]", "[PAUSED]", "[ERROR]")
        and r.get("tick") == "end"
        for r in tail
    )
    if not silent_all:
        return  # some tick produced output — pipeline is alive

    # Dedup / rate-limit
    last = state.get("last_alert_ts", 0)
    if now - last < ALERT_COOLDOWN:
        return
    state["last_alert_ts"] = now
    state["last_pending_count"] = len(events)
    try:
        with open(STATE_FILE, "w") as f:
            json.dump(state, f)
    except OSError:
        pass

    kinds = sorted({r.get("output", "?") for r in tail})
    msg = (f"⚠️ 沉默 SPAWN 检测: pending 有 {len(events)} 个事件, "
           f"但最近 {len(tail)} 个 tick 均无 SPAWN 输出 ({'/'.join(kinds)}). "
           f"检查 GH_TOKEN/限流或 cron last_status。")
    ok = post_feishu(msg)
    print(msg if ok else f"[watchdog] alert POST failed: {msg}")


if __name__ == "__main__":
    main()
