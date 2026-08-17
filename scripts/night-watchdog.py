#!/usr/bin/env python3
"""night-watchdog.py — 夜间 workflow 监控（只读 + 失控自动停机）

用户睡觉期间运行（每 10 min cron）。原则：
  - 只读检测：绝不触发 workflow、绝不建 PR/merge/打 label
  - 失控判定 → 写 ~/.hermes/workflow-pause 停机 + 输出告警（cron no_agent
    模式把 stdout 原样发给 Feishu）
  - 轻微异常 → 仅记录到 JSONL，不动作

失控阈值（2026-08-17 定）：
  T1  poller 连续 FAILED >= 3            (API 超时/网关问题)
  T2  同一 issue 的 running delegate > 2  (重复 spawn 失控)
  T3  全局 running delegate > 6          (并发堆积)
  T4  e2e-state 卡 running > 60min       (E2E 死锁)
  T5  GitHub 状态为 major_outage         (外部中断, 停流防 gh 写失败风暴)

用法: python3 night-watchdog.py [--dry-run]
输出: 失控 → 打印告警(→Feishu); 正常 → 空输出(静默)
"""
import json
import os
import sys
import time
import glob

HOME = os.path.expanduser("~/.hermes")
CRON_DIR = os.path.join(HOME, "cron", "output", "83fee8577195")
PAUSE_FILE = os.path.join(HOME, "workflow-pause")
STATE_DB = os.path.join(HOME, "state.db")
E2E_STATE_DIR = os.path.join(HOME, "e2e-state")
LOG = os.path.join(HOME, "night-watchdog.jsonl")

# 复用 workflow-watchdog 的 Feishu bot webhook (失控告警直接推手机)
FEISHU_WEBHOOK = "https://open.feishu.cn/open-apis/bot/v2/hook/76101281-b359-49ab-ae2f-fc486bf65958"

DRY = "--dry-run" in sys.argv


def post_feishu(text: str) -> bool:
    """Send alert to Feishu bot. Returns True on success (fire-and-forget)."""
    try:
        import urllib.request
        payload = json.dumps({"msg_type": "text",
                              "content": {"text": text}}).encode()
        req = urllib.request.Request(FEISHU_WEBHOOK, data=payload,
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=8) as r:
            return r.status == 200
    except Exception as e:
        log({"level": "warn", "event": "feishu-fail", "detail": str(e)})
        return False


def log(entry: dict) -> None:
    entry["ts"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    with open(LOG, "a") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


def poller_failed_count() -> int:
    """最近 3 个 tick 中 FAILED 的数量。"""
    files = sorted(glob.glob(os.path.join(CRON_DIR, "*.md")))[-3:]
    fails = 0
    for f in files:
        try:
            with open(f) as fh:
                if "FAILED" in fh.read():
                    fails += 1
        except OSError:
            pass
    return fails


def running_delegates() -> list:
    """state.db 中 running 的 delegate 列表 [(id, goal_prefix)]。"""
    try:
        import sqlite3
        con = sqlite3.connect(f"file:{STATE_DB}?mode=ro", uri=True)
        try:
            rows = con.execute(
                "SELECT delegation_id, task_json FROM async_delegations "
                "WHERE state='running'").fetchall()
        finally:
            con.close()
        out = []
        for rid, tj in rows:
            goal = ""
            try:
                goals = json.loads(tj).get("goals") or []
                goal = goals[0][:60] if goals else ""
            except Exception:
                pass
            out.append((rid, goal))
        return out
    except Exception as e:
        log({"level": "warn", "event": "db-read-fail", "detail": str(e)})
        return []


def issue_of_goal(goal: str) -> str:
    import re
    m = re.search(r"issue #(\d+)", goal)
    return m.group(1) if m else "?"


def e2e_stuck_count(max_min: int = 60) -> int:
    """e2e-state 卡 running 超过 max_min 的 PR 数。

    排除僵尸: pid 已死 + 卡 running 是"收割未执行"的残留 (orchestrator 下个
    tick 会收割转 done), 不是失控。只有 pid 仍存活但超时才算真卡死。
    """
    stuck = 0
    now = time.time()
    for f in glob.glob(os.path.join(E2E_STATE_DIR, "*.json")):
        try:
            with open(f) as fh:
                d = json.load(fh)
            if d.get("status") == "running":
                started = d.get("started_at", 0)
                pid = d.get("pid", 0)
                if not started or now - started <= max_min * 60:
                    continue
                # 超时了 → 看进程是否还活着 (真卡死) 还是僵尸 (收割未执行)
                alive = False
                try:
                    os.kill(pid, 0)
                    alive = True
                except (OSError, ProcessLookupError, ValueError):
                    alive = False
                if alive:
                    stuck += 1
        except (OSError, json.JSONDecodeError):
            pass
    return stuck


def github_status() -> str:
    """GitHub 状态页概括；失败返回空串（不误报）。"""
    try:
        import urllib.request
        req = urllib.request.Request(
            "https://www.githubstatus.com/api/v2/status.json",
            headers={"User-Agent": "night-watchdog"})
        with urllib.request.urlopen(req, timeout=8) as r:
            d = json.loads(r.read().decode())
        return d.get("status", {}).get("description", "")
    except Exception:
        return ""


def main() -> int:
    alerts = []
    abnormal = []

    # T1: poller 连续 FAILED
    fails = poller_failed_count()
    if fails >= 3:
        alerts.append(f"T1 poller 连续 {fails} tick FAILED")
    elif fails > 0:
        abnormal.append(f"poller {fails} tick FAILED (未达阈值)")

    # T2/T3: running delegates
    dels = running_delegates()
    if len(dels) > 6:
        alerts.append(f"T3 running delegates={len(dels)} (阈值 6)")
    elif len(dels) > 3:
        abnormal.append(f"running delegates={len(dels)}")
    by_issue = {}
    for rid, goal in dels:
        by_issue.setdefault(issue_of_goal(goal), []).append(rid)
    for iss, rids in by_issue.items():
        if iss != "?" and len(rids) > 2:
            alerts.append(f"T2 issue #{iss} 有 {len(rids)} 个 running delegate 重复")

    # T4: E2E 卡死
    stuck = e2e_stuck_count()
    if stuck >= 1:
        alerts.append(f"T4 {stuck} 个 E2E 卡 running >60min")

    # T5: GitHub 状态 — 外部中断只告警不停机 (停了对恢复无益, 事件照常堆积;
    # 等 GitHub 恢复后 pipeline 自愈)。仅 major_outage 且同时有其他失控信号
    # 时才参与停机判定。
    gs = github_status()
    if gs and "outage" in gs.lower():
        abnormal.append(f"github-status: {gs}")
        if not alerts:
            log({"level": "warn", "event": "github-outage", "status": gs})

    if alerts:
        msg = "🚨 workflow 失控告警:\n" + "\n".join(f"- {a}" for a in alerts)
        msg += f"\n\n→ 已写入 {PAUSE_FILE} 停机（事件累积，恢复后 /workflow resume）"
        log({"level": "alert", "event": "shutdown", "alerts": alerts})
        if not DRY:
            with open(PAUSE_FILE, "w") as f:
                f.write(time.strftime("%Y-%m-%dT%H:%M:%S%z"))
        print(msg)
        if not DRY:
            post_feishu(msg)  # 直接推手机 (cron deliver=local 不投递 stdout)
        return 1

    if abnormal:
        log({"level": "warn", "event": "watch", "detail": abnormal})
        # 轻微异常不打印 → 静默（避免夜间打扰）
        return 0

    log({"level": "ok", "event": "watch", "delegates": len(dels),
         "poller_failed": fails})
    return 0


if __name__ == "__main__":
    sys.exit(main())
