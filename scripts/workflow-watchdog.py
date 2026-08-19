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
import re
import time
import urllib.request

HOME = os.path.expanduser("~")
PENDING_FILE = os.path.join(HOME, ".hermes", "workflow-pending.json")
AUDIT_FILE = os.path.join(HOME, ".hermes", "workflow-audit.jsonl")
STATE_FILE = os.path.join(HOME, ".hermes", "workflow-watchdog-state.json")
E2E_STATE_DIR = os.path.join(HOME, ".hermes", "e2e-state")
REVIEW_CONCLUSIONS_DIR = os.path.join(HOME, ".hermes", "review-conclusions")
FEISHU_WEBHOOK = "https://open.feishu.cn/open-apis/bot/v2/hook/76101281-b359-49ab-ae2f-fc486bf65958"
LOOKBACK_TICKS = 6  # ~6 minutes of 1m ticks
ALERT_COOLDOWN = 3600  # seconds
REVIEW_SENT_TIMEOUT = 1800  # 30 min: review 派发后应有结论文件
CONCLUSION_STALE_TIMEOUT = 3600  # 60 min: followup 应消费结论文件
SKELETON_FILL_TIMEOUT = 1200  # 20 min: P2 骨架 (verdict=null) 生成后 review agent 应填值
# 2026-08-19 (post-merge 阶段): emitted 后应有 docs PR 创建并 merge。
# agent 轮询上限 ~10min + stalled scan merge 往返 ~几分钟 → 45min 合理。
POST_MERGE_STATE_DIR = os.path.join(HOME, ".hermes", "post-merge-state")
POST_MERGE_TIMEOUT = 2700  # 45 min


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


def check_review_stuck(now):
    """2026-08-17 (方案 X 兜底): e2e done + emitted_at 超时无结论文件 → 告警.

    one-shot 派发机制不自动重发 (历史教训: 重发 + 消费即删 = 死循环),
    所以 SPAWN 丢失 / review agent 失败必须靠这个检测暴露, 人工介入。
    """
    alerts = []
    try:
        if not os.path.isdir(E2E_STATE_DIR):
            return alerts
        for fn in sorted(os.listdir(E2E_STATE_DIR)):
            if not fn.endswith(".json"):
                continue
            path = os.path.join(E2E_STATE_DIR, fn)
            try:
                with open(path) as f:
                    st = json.load(f)
            except (OSError, json.JSONDecodeError):
                continue
            pr = fn[:-5]
            emitted = st.get("emitted_at") or 0
            if st.get("status") != "done" or not emitted:
                continue
            if now - emitted < REVIEW_SENT_TIMEOUT:
                continue
            if os.path.exists(os.path.join(REVIEW_CONCLUSIONS_DIR, f"{pr}.json")):
                continue  # 结论在, followup 处理中 — 不是卡住
            alerts.append(
                f"⚠️ review 卡住: PR #{pr} 的 review 已派发 "
                f"{int((now - emitted) / 60)} 分钟仍无结论文件 "
                f"(SPAWN 被吞 / review agent 失败)。one-shot 不自动重发, 需人工介入。")
    except OSError:
        pass
    return alerts


def check_conclusion_stale(now):
    """2026-08-19 (#562 根治): 结论文件滞留 + verdict 非法 → 告警.

    - verdict 非法 (不在规范枚举 / JSON 解析失败): 立即告警, 不等 60min —
      review_followup 不消费非法文件 (校验器保留 + devlog), 这类文件
      滞留说明 review agent 写了自由文本 (#562: "approve / merge")。
    - 滞留 60 分钟: review_followup 未消费 (approve 后 merge 失败卡住等)。
    """
    alerts = []
    try:
        if not os.path.isdir(REVIEW_CONCLUSIONS_DIR):
            return alerts
        for fn in sorted(os.listdir(REVIEW_CONCLUSIONS_DIR)):
            if not fn.endswith(".json"):
                continue
            path = os.path.join(REVIEW_CONCLUSIONS_DIR, fn)
            # ── verdict 合法性快速检测 (2026-08-19) ──
            try:
                with open(path) as f:
                    data = json.load(f)
                if data.get("verdict") is None:
                    # P2 骨架 (3738e82): verdict=null = 预生成待 review agent 填值
                    # — 合法瞬态, 立即告警是误报 (#567 实测: 骨架 13:46 生成 →
                    # review agent 13:52 填值消费, 旧逻辑对用户刷 Feishu 告警)。
                    # 只对滞留骨架 (>SKELETON_FILL_TIMEOUT 仍未填) 告警 — 那才
                    # 是 review agent 没跑/没写的真问题。
                    try:
                        age = now - os.path.getmtime(path)
                    except OSError:
                        continue
                    if age <= SKELETON_FILL_TIMEOUT:
                        continue
                    alerts.append(
                        f"⚠️ 结论骨架未填: {fn} 存在 {int(age / 60)} 分钟 "
                        f"verdict 仍为 null (review agent 未写结论 / 会话失败)。")
                    continue
                verdict = str(data.get("verdict", "")).strip().lower()
                verdict = re.split(r"[/|,，;；]", verdict)[0].strip()
                valid = verdict in ("approved", "approve", "blocked",
                                    "self_correct", "request_changes",
                                    "changes_requested", "reject", "no_merge")
                if not valid:
                    alerts.append(
                        f"⚠️ 结论文件 verdict 非法: {fn} verdict={data.get('verdict')!r} "
                        f"(规范四值: approved | blocked | self_correct | request_changes) — "
                        f"review agent 自由文本, 需人工修正或重写。")
                    continue  # 已告警, 不重复报滞留
            except (json.JSONDecodeError, OSError):
                alerts.append(
                    f"⚠️ 结论文件 JSON 非法: {fn} — 解析失败, review_followup "
                    f"不会消费, 需人工修正。")
                continue
            # ── 滞留检测 (原有) ──
            try:
                age = now - os.path.getmtime(path)
            except OSError:
                continue
            if age > CONCLUSION_STALE_TIMEOUT:
                alerts.append(
                    f"⚠️ 结论文件滞留: {fn} 存在 {int(age / 60)} 分钟未被消费 "
                    f"(review_followup 卡住 / approve 后 merge 失败)。")
    except OSError:
        pass
    return alerts


def check_post_merge_stuck(now):
    """2026-08-19 (post-merge 阶段兜底): post-merge 任务派发后超时未完成 → 告警.

    状态机 (~/.hermes/post-merge-state/<pr>.json): pending → (emitted_at 标记)
    → post-merge agent 建 docs PR → 脚本层 merge → agent 写 status=done。
    任何一环断裂 (SPAWN 被吞 / agent 失败 / docs PR conflict 挂住) 都会让
    状态停在 pending+emitted_at —— 这是 GDD 无主责任 (#562/#566) 的终局兜底,
    不能静默。
    """
    alerts = []
    try:
        if not os.path.isdir(POST_MERGE_STATE_DIR):
            return alerts
        for fn in sorted(os.listdir(POST_MERGE_STATE_DIR)):
            if not fn.endswith(".json"):
                continue
            path = os.path.join(POST_MERGE_STATE_DIR, fn)
            try:
                with open(path) as f:
                    st = json.load(f)
            except (OSError, json.JSONDecodeError):
                continue
            pr = fn[:-5]
            if st.get("status") == "done":
                continue
            emitted = st.get("emitted_at") or 0
            if not emitted:
                continue  # 尚未派发, 正常瞬态
            if now - emitted < POST_MERGE_TIMEOUT:
                continue
            docs_pr = st.get("docs_pr") or "?"
            alerts.append(
                f"⚠️ post-merge 卡住: PR #{pr} 的 post-merge 已派发 "
                f"{int((now - emitted) / 60)} 分钟仍未完成 "
                f"(docs PR {docs_pr} 未 merge / agent 失败)。"
                f"GDD 更新悬空, 需人工介入。")
    except OSError:
        pass
    return alerts


def main():
    now = time.time()
    state = read_json(STATE_FILE, {})

    # Workflow paused? If the config says disabled, silence is EXPECTED.
    cfg = read_json(os.path.join(HOME, ".hermes", "workflow-config.json"), {})
    if not cfg.get("enabled", True):
        return  # paused/disabled — silence is by design

    # 2026-08-17 (方案 X 兜底): review 卡住 / 结论滞留检测 — 独立于 pending,
    # 无条件跑 (one-shot 派发后不自动重发, 这类故障只能靠告警暴露)。
    # 2026-08-19: + post-merge 卡住检测 (GDD 无主责任的终局兜底)。
    for cls, alerts in (
        ("review-stuck", check_review_stuck(now)),
        ("conclusion-stale", check_conclusion_stale(now)),
        ("post-merge-stuck", check_post_merge_stuck(now)),
    ):
        if not alerts:
            continue
        last = state.get(f"last_alert_ts_{cls}", 0)
        if now - last < ALERT_COOLDOWN:
            continue
        state[f"last_alert_ts_{cls}"] = now
        try:
            with open(STATE_FILE, "w") as f:
                json.dump(state, f)
        except OSError:
            pass
        msg = "\n".join(alerts[:3])
        ok = post_feishu(msg)
        print(msg if ok else f"[watchdog] alert POST failed: {msg}")

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
