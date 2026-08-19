---
name: game-post-merge-agent
description: "Execute post-merge duties after an implement PR merges: GDD update + PROJECT.md + Feishu notification + board sync. Spawned by SPAWN: post-merge (merge-event bound) — the fix for the 方案 X orphan gap (#562/#566)."
tags: ["workflow", "post-merge", "gdd", "docs"]
---

# Game Post-Merge Agent

> Triggered by `SPAWN: post-merge,pr=N,issue=M` — emitted by event-processor's
> `post_merge_emitter()` ONCE per merged PR (one-shot, `emitted_at` marker, same
> semantics as the review SPAWN). Runs AFTER the implement PR has merged to main
> by the script layer (`review_followup`/`_try_merge`).

## Why This Agent Exists（2026-08-19, 方案 X 结构性缺口修复）

方案 X（merge 脚本化, 2026-08-17）把 merge 从 review agent 会话移到脚本层 → review
会话在写结论文件后即结束、merge 在下一个 cron tick 才发生 → review skill 的
post-merge GDD 步骤在会话内物理不可达 → GDD 更新成无主责任（#562/#566 实测：
两个 review agent 都没写 GDD；#562 甚至把 post-merge handoff 给父代理结果落空）。

修复：merge 事件 → `_ensure_post_merge_state` + `SPAWN: post-merge` → 本 agent。
**触发归脚本（确定性），写作归 LLM** —— 符合"LLM 只做判定，机械归脚本"铁律。
完整证据链：`game-review-agent` skill 的 references/gdd-orphan-post-merge-gap.md。

## 实测验证（2026-08-19 #567, 首次端到端 100% 通过）

测试 issue #567 全链路零人工介入成功：impl #570 merge → SPAWN: post-merge
(one-shot) → 本 agent 写 GDD → docs/gdd-570 PR #571 → stalled scan 自动 merge
→ status=done → #567 自动 CLOSED。终态证据 + 过程中发现修复的 3 个跨阶段问题
(P2 骨架误报 / 测试泄漏 / MANIFEST_PATH 硬编码) + 可复用的 no_agent 监控模式:
**`references/post-merge-verification-567.md`**。

## ⛔ 核心红线：GDD 走 docs/ PR，绝不直接 push main（用户拍板 2026-08-19）

- 更新写进 **`docs/gdd-<N>` 分支**（worktree 隔离）+ 创建 PR
- merge 由 stalled scan 的 `STALLED: merge-pr` **自动执行**（`docs/` 前缀已加入
  `_quick_stalled_scan`，merge 归脚本层）
- **绝不自己 `gh pr merge`，绝不直接 push 到 main** —— main 只进 PR（用户红线）
- 完成标记时机：**docs PR 确认 MERGED 后才写 `status=done`**（轮询，超时 10 分钟
  仍未 merge → 保持 pending → watchdog post-merge-stuck 告警，不静默丢）

## Steps

### 0. 读取上下文

```bash
source ~/.hermes/.env   # GH_TOKEN 等
GAME_DIR=$(python3 -c "import re; txt=open('game-env/manifest.yaml',encoding='utf-8').read(); m=re.search(r'^game:\s*$',txt,re.M); am=re.search(r'active:\s*(\S+)',txt[m.end():m.end()+200]) if m else None; print(am.group(1) if am else 'mini-pong')")
echo "当前游戏: $GAME_DIR"
# SPAWN 行里的 pr=N 是已 merge 的 implement PR；issue=M 是其父 issue
```

### 1. 读 DESIGN doc 确定 GDD 更新内容

```bash
ls docs/DESIGN/<N>-*.md        # N = 父 issue 号（SPAWN 的 issue= 字段）
# 读 DESIGN 的架构决策/常量/数据流 → 写入对应 GDD 章节（见下）
gh pr view <N> --json title,mergedAt --jq '.title'   # PR 标题 = 功能名
```

### 2. Worktree 隔离（红线：不碰主工作区）

```bash
git fetch origin main
git worktree add /tmp/wt-post-merge-<N> -b docs/gdd-<N> origin/main
cd /tmp/wt-post-merge-<N>
# 完成后: git worktree remove /tmp/wt-post-merge-<N> --force
```

### 3. GDD 更新（docs/GAME_DESIGN/<GAME_DIR>/）

**多游戏分目录（P3 参数化, 2026-08-19）：** 当前游戏的 GDD 写到
`docs/GAME_DESIGN/<GAME_DIR>/` 子目录，每个游戏自己的 `INDEX.md` 与编号
（01-09+ 按功能域）。mini-pong 遗留 GDD 在根目录（历史单游戏时期），新游戏一律分目录。

- 章节不存在 → 新建编号文件（读子目录 INDEX.md 找最大 NN 前缀 +1），
  命名 `NN-FEATURE-NAME.md`，INDEX.md 表内路径用子目录内相对路径
- 章节已存在 → `patch` 追加新小节，不要整体覆写
- **写作风格**：叙事体、层次编号、代码块放定义（signal/enum/方法签名）、
  表格放参数、段落讲意图 —— 人读得懂，LLM 查得到
- **`patch` 陷阱：markdown 管道表会被模糊匹配破坏成 `|||`** —— 编辑后必须：
  ```bash
  grep -n '|||' docs/GAME_DESIGN/ docs/GAME_DESIGN/$GAME_DIR/ 2>/dev/null
  # INDEX.md 新增行用 write_file 整体重写（文件小），避免 patch
  ```

### 4. PROJECT.md 更新

L1 状态表（最近构建/开放 Issues）→ L2 模块表（新模块加行）→ L3 功能表（新功能加行）
→ L4 已知问题。同样警惕管道表 `|||` 损坏。

### 5. 提交（白名单 add）→ push → 创建 PR

```bash
cd /tmp/wt-post-merge-<N>
git add docs/GAME_DESIGN/ docs/PROJECT.md
# ⛔ 白名单红线: git add 只允许上述两个路径; 提交前自检:
git status --short
git diff --cached --name-only | grep -v -E '^docs/(GAME_DESIGN/|PROJECT\.md$)' && echo "❌ 白名单外文件, 停止" || echo "✅ 白名单内"
git commit -m "docs: update GDD + PROJECT.md for <feature> (#<N>)"
git push origin docs/gdd-<N>
gh pr create --title "docs: GDD update after #<N> merged" \
  --body "Post-merge 文档更新（game-post-merge-agent）\n\n**Source PR:** #<N>（已 merge）\n**Parent:** #<M>\n\n- GDD: docs/GAME_DESIGN/<GAME_DIR>/\n- PROJECT.md\n\nmerge 由 stalled scan 自动执行（docs/ 分支）。" \
  --base main --head docs/gdd-<N>
```

### 6. 轮询 docs PR merge → 标记完成

```bash
# 轮询直到 MERGED（上限 ~10 分钟; stalled scan 每 tick 自动 merge docs/ PR）
for i in $(seq 1 20); do
  S=$(gh pr view <DOCS_PR_NUM> --json state --jq '.state' 2>/dev/null)
  [ "$S" = "MERGED" ] && break
  sleep 30
done
# 无论结果, 更新状态文件 (实测 #567: 记录 gdd_chapters 供审计):
python3 - <<'PYEOF'
import json, os
p = os.path.expanduser("~/.hermes/post-merge-state/<N>.json")
if os.path.exists(p):
    d = json.load(open(p))
    d["status"] = "done"
    d["docs_pr"] = <DOCS_PR_NUM>
    d["docs_pr_url"] = "https://github.com/<owner>/<repo>/pull/<DOCS_PR_NUM>"
    d["gdd_chapters"] = ["docs/GAME_DESIGN/<GAME_DIR>/<NN-FILE>.md (说明)",
                         "docs/GAME_DESIGN/<GAME_DIR>/INDEX.md (填充)"]
    d["finished_at"] = __import__("time").time()
    json.dump(d, open(p, "w"), indent=1)
PYEOF
```

**⚠️ 若 docs PR 未 merge（CONFLICTING 等）**：状态文件**保持 pending**（不写
done），watchdog post-merge-stuck 会告警 → 人工介入。不要在状态文件里伪造完成。

### 7. Feishu 通知 + board sync（机械收尾）

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"msg_type":"text","content":{"text":"📝 #<N> → GDD 已更新（docs PR #<DOCS_PR_NUM>）"}}' \
  https://open.feishu.cn/open-apis/bot/v2/hook/76101281-b359-49ab-ae2f-fc486bf65958

# Project board: 父 issue 是否在 board → Status 字段设置。
# ⚠️ v4 语义: taste-draft / human-review 的 issue 设 "In review"（保持 open 等用户
# 定稿, 避免 automation 误关）; 机械 issue 设 "Done"。判定: 父 issue body 是否
# content_ownership: taste-draft, 或父 issue 是否带 status/human-review label。
# 若父 issue 已 close + status/done（review_followup 已处理机械收尾）, 跳过 board。
```

### 8. 清理 worktree

```bash
cd ~/workspace/<repo>
git worktree remove /tmp/wt-post-merge-<N> --force
```

## Taste-Draft 定稿确认（若父 issue 带 status/human-review）

若 `issue=M` 的父 issue 带 `status/human-review`（草稿已 merge、用户已裁决并
push 定稿 → 本次是定稿 PR）：merge 后**不要 close、不要打 status/done、不要动
label** —— close 归用户（close 即定稿）。GDD 照常更新（记录定稿差异到
`docs/TASTE.md` 品味档案：| 日期 | Issue | 领域 | 草稿值 | 定稿值 | 方向 | 理由 |）。

## 验收自检（提交前）

- [ ] `git diff --cached --name-only` ⊆ `docs/GAME_DESIGN/` + `docs/PROJECT.md`
- [ ] 无 `|||` 管道表损坏（grep 过）
- [ ] INDEX.md 表与新增章节一致
- [ ] 未 merge 自己的 PR、未 push 到 main
- [ ] 状态文件写 done（仅当 docs PR 已 MERGED）

## Environment

- `GH_TOKEN` — GitHub PAT（在 `~/.hermes/.env`）
- 默认分支: `game-env/manifest.yaml` 的 `default_branch`（常见 main/master）
- 工作区红线：全阶段 worktree 隔离，主工作区零污染
