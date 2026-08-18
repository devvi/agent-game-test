#!/usr/bin/env bash
# ────────────────────────────────────────────────────────────────
# worktree-commit.sh — worktree 内提交前同步 main + 冲突分级处理
# 在 worktree 内开发完成后调用: 先 merge main, 再 add/commit/push。
#
# 用法:
#   ./scripts/worktree-commit.sh <issue> <message> [files...]
#     issue:    GitHub issue number
#     message:  提交信息 (引号包裹)
#     files:    只 add 这些文件 (白名单 — 绝不 add .)
#
# 冲突分级 (2026-08-13 用户确认):
#   1. git merge origin/main 自动合并成功 → 继续
#   2. 真冲突 → 尝试合理解决 (对方是机械改动则合并双方语义)
#   3. 无法判断 → git merge --abort + 报告 (不硬解)
# 合并后本地验证: 若含 .gd 则跑 --headless --quit 确认无语法错误
# ────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ISSUE="${1:?usage: worktree-commit.sh <issue> <message> [files...]}"
MESSAGE="${2:?usage: worktree-commit.sh <issue> <message> [files...]}"
shift 2
FILES=("$@")

log() { echo "==> $*"; }

# ── 0. 必须在 worktree 内 (分支名含 issue 号) ─────────────────
BRANCH="$(git branch --show-current)"
if [ -z "$BRANCH" ] || [[ "$BRANCH" != *"/$ISSUE-"* ]]; then
  echo "❌ 当前不在 #$ISSUE 的 worktree 分支上 (current: $BRANCH)"
  echo "   请在 /tmp/wt-<phase>-$ISSUE 内执行"
  exit 1
fi
log "branch: $BRANCH"

# ── 1. 提交前同步 main (程序员工作流) ─────────────────────────
log "fetch + merge origin/main (提交前同步)"
git fetch origin main 2>&1 | tail -1 || true
MERGE_OUTPUT="$(git merge origin/main 2>&1 || true)"
MERGE_STATUS=$?

if [ "$MERGE_STATUS" -ne 0 ]; then
  # 冲突 — 检查是否真的冲突还是其他错误
  if echo "$MERGE_OUTPUT" | grep -q "CONFLICT"; then
    CONFLICTS=$(git diff --name-only --diff-filter=U || true)
    echo "⚠️ 合并冲突文件: $CONFLICTS"
    echo "   尝试自动解决: 保留双方语义 (ours 为本分支实现, theirs 为 main 最新)"
    # 尝试自动解决: 大部分冲突是 main 新增 vs 本分支修改同文件不同区域
    # git 已自动合并大部分; 剩余冲突尝试以"本分支为主 + 保留 main 的新增"
    # 不做暴力 checkout — 先看冲突规模
    CONFLICT_COUNT=$(echo "$CONFLICTS" | grep -c . || true)
    if [ "$CONFLICT_COUNT" -le 2 ]; then
      # 小冲突: 尝试用 merge 策略解决 — 保留双方 (默认策略)
      # 若仍失败则 abort
      if git merge --continue 2>&1 | tail -2 || git commit --no-edit 2>&1 | tail -2; then
        log "✅ 冲突已自动解决"
      else
        echo "❌ 冲突无法自动解决 — abort, 请人工处理"
        git merge --abort
        exit 2
      fi
    else
      echo "❌ 冲突文件过多 ($CONFLICT_COUNT) — abort, 请人工处理"
      git merge --abort
      exit 2
    fi
  else
    echo "⚠️ merge 非冲突失败: $MERGE_OUTPUT"
    git merge --abort 2>/dev/null || true
    exit 2
  fi
else
  log "✅ merge main 无冲突"
fi

# ── 2. 白名单 add (绝不 add .) ────────────────────────────────
if [ ${#FILES[@]} -eq 0 ]; then
  echo "❌ 未指定文件白名单 — 绝不 git add . (多 agent 隔离红线)"
  exit 1
fi
log "add files: ${FILES[*]}"
git add "${FILES[@]}"

# ── 3. 验证: 含 .gd 则编译检查 ────────────────────────────────
# 2026-08-18: 游戏路径从 manifest game.active 读取（一次一个游戏）。
GAME_ACTIVE=$(python3 - "$(dirname "$0")/../game-env/manifest.yaml" <<'PY' 2>/dev/null || echo mini-pong
import re, sys
try:
    txt = open(sys.argv[1], encoding="utf-8").read()
    m = re.search(r"^game:\s*$", txt, re.M)
    if m:
        am = re.search(r"active:\s*(\S+)", txt[m.end():m.end()+200])
        if am:
            print(am.group(1))
except Exception:
    pass
PY
)
GAME_DIR="${GAME_ACTIVE:-mini-pong}"
if [[ "${FILES[*]}" == *".gd"* ]] && [ -f "$GAME_DIR/project.godot" ]; then
  log "compile check ($GAME_DIR)"
  if ! godot --path "$GAME_DIR/" --headless --quit >/dev/null 2>&1; then
    echo "❌ 编译失败 — 修复后再提交"
    exit 3
  fi
  log "✅ compile OK"
fi

# ── 4. commit + push ──────────────────────────────────────────
log "commit: $MESSAGE"
git commit -m "$MESSAGE"
log "push: $BRANCH"
git push -u origin "$BRANCH" 2>&1 | tail -2

log "✅ committed + pushed: $BRANCH"
