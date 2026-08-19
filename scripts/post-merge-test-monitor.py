#!/usr/bin/env python3
"""post-merge 阶段回归测试 (#567) 监控脚本 — 全程测试监控.

Cron no_agent 模式 (every 15m): stdout 非空 → 投递 Feishu; 空 → 静默.
- 粗粒度状态变化 (label 链 / PR 状态 / post-merge-state / docs PR / GDD 章节)
  变化才输出 (hash 比较), 避免刷屏。
- 卡住 (post-merge pending + emitted > 45min) 无条件输出告警。

2026-08-19: 验证 eabb294/0f18c45 落地的 post-merge 阶段全链路。
"""
import hashlib
import json
import os
import subprocess
import sys
import time

ISSUE = 567
HOME = os.path.expanduser("~")
STATE_FILE = os.path.join(HOME, ".hermes", "post-merge-monitor-state.json")
POST_MERGE_STATE_DIR = os.path.join(HOME, ".hermes", "post-merge-state")
GDD_DIR = os.path.expanduser("~/workspace/agent-game-test/docs/GAME_DESIGN/shandong-wolf")
STUCK_TIMEOUT = 2700  # 45 min, 与 workflow-watchdog 一致
REPO_DIR = os.path.expanduser("~/workspace/agent-game-test")


def gh(*args):
    try:
        r = subprocess.run(["gh"] + list(args), capture_output=True,
                           text=True, timeout=30, cwd=REPO_DIR)
        return r.stdout.strip()
    except Exception:
        return ""


def main():
    out = []
    stuck = []

    # 1. issue label 链 (workflow/research → plan → implement → status/done)
    labels = gh("issue", "view", str(ISSUE), "--json", "labels",
                "--jq", ".labels[].name").replace("\n", ",")
    stage = "no-label"
    for s in ("workflow/available", "workflow/research", "workflow/plan",
              "workflow/implement", "status/done", "status/blocked",
              "status/human-review"):
        if s in labels:
            stage = s
    out.append(f"issue#{ISSUE} stage={stage} labels={labels or 'none'}")

    # 2. 关联 implement PR
    prs = gh("pr", "list", "--state", "all", "--search",
             f"{ISSUE} in:body head:impl/", "--json",
             "number,title,state,mergedAt", "--limit", "5")
    impl_pr = "none"
    try:
        for p in json.loads(prs or "[]"):
            impl_pr = f"#{p['number']}:{p['state']}"
            if p.get("mergedAt"):
                impl_pr += "(merged)"
            break
    except Exception:
        pass
    out.append(f"impl PR {impl_pr}")

    # 3. post-merge-state (merge 后出现)
    pm = []
    if os.path.isdir(POST_MERGE_STATE_DIR):
        for fn in sorted(os.listdir(POST_MERGE_STATE_DIR)):
            try:
                st = json.load(open(os.path.join(POST_MERGE_STATE_DIR, fn)))
            except Exception:
                continue
            pr = fn[:-5]
            s = st.get("status", "?")
            tag = f"#{pr}:{s}"
            if st.get("docs_pr"):
                tag += f"(docs#{st['docs_pr']})"
            pm.append(tag)
            if s != "done" and st.get("emitted_at"):
                age = time.time() - st["emitted_at"]
                if age > STUCK_TIMEOUT:
                    stuck.append(f"⚠️ post-merge 卡住 #{pr}: 派发 "
                                 f"{int(age / 60)} 分钟未完成 (docs PR 未 merge)")
    out.append("post-merge-state: " + ("; ".join(pm) if pm else "none"))

    # 4. GDD 章节 (post-merge agent 产出)
    gdd = []
    if os.path.isdir(GDD_DIR):
        gdd = [f for f in sorted(os.listdir(GDD_DIR)) if f.endswith(".md")]
    out.append("GDD shandong-wolf: " + (", ".join(gdd) if gdd else "none"))

    # 5. docs/ PR (stalled scan 自动 merge 的目标)
    docs_pr = gh("pr", "list", "--state", "all", "--search", "head:docs/",
                 "--json", "number,title,state", "--limit", "5")
    docs = []
    try:
        for p in json.loads(docs_pr or "[]"):
            docs.append(f"#{p['number']}:{p['state']}")
    except Exception:
        pass
    out.append("docs PR: " + ("; ".join(docs) if docs else "none"))

    status = "\n".join(out)

    # 卡住: 无条件输出 (即使粗状态没变, 也必须告警)
    if stuck:
        print(status + "\n" + "\n".join(stuck))
        return

    # 变化检测
    h = hashlib.md5(status.encode()).hexdigest()[:10]
    last = {}
    try:
        last = json.load(open(STATE_FILE))
    except Exception:
        pass
    if last.get("hash") == h:
        sys.exit(0)  # 无变化 → 静默
    try:
        json.dump({"hash": h, "ts": time.time()}, open(STATE_FILE, "w"))
    except OSError:
        pass
    print(status)


if __name__ == "__main__":
    main()
