#!/usr/bin/env bash
# ────────────────────────────────────────────────────────────────
# worktree-setup.sh — 阶段隔离 + 提交前同步 main
# 所有阶段 agent (research/plan/implement) 的统一 worktree 入口。
# 解决: 多 agent 并发共用主工作区 → 互相污染 (2026-08-13 根因)。
#
# 用法:
#   ./scripts/worktree-setup.sh <phase> <issue> <slug> [--pre-merge]
#     phase:   research | plan | implement
#     issue:   GitHub issue number
#     slug:    分支 slug (如 feel-calibration-draft)
#     --pre-merge: 创建后立即 merge origin/main (默认: 提交前由
#                  worktree-commit.sh 做, 传此 flag 则创建即同步)
#
# 输出:
#   - 创建 /tmp/wt-<phase>-<N> worktree, 基于最新 origin/main
#   - 分支 research/<N>-<slug> / plan/<N>-<slug> / impl/<N>-<slug>
#   - 打印 worktree 路径 (agent 后续 cd 到此处工作)
#
# 安全: 所有操作在主仓库目录执行, worktree 内容与主工作区物理隔离。
# ────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PHASE="${1:?usage: worktree-setup.sh <phase> <issue> <slug> [--pre-merge]}"
ISSUE="${2:?usage: worktree-setup.sh <phase> <issue> <slug> [--pre-merge]}"
SLUG="${3:?usage: worktree-setup.sh <phase> <issue> <slug> [--pre-merge]}"
PRE_MERGE="${4:-}"

BRANCH_PREFIX=""
case "$PHASE" in
  research)  BRANCH_PREFIX="research" ;;
  plan)      BRANCH_PREFIX="plan" ;;
  implement) BRANCH_PREFIX="impl" ;;
  *) echo "❌ unknown phase: $PHASE (research|plan|implement)"; exit 1 ;;
esac

BRANCH="$BRANCH_PREFIX/$ISSUE-$SLUG"
WT="/tmp/wt-$PHASE-$ISSUE"

log() { echo "==> $*"; }

cd "$REPO_ROOT"

# ── 1. 确保 main 最新 ─────────────────────────────────────────
log "fetch origin"
git fetch origin main 2>&1 | tail -1 || true

# ── 2. 防重复: worktree 已存在则复用 ─────────────────────────
if git worktree list | grep -q " $WT "; then
  log "worktree already exists: $WT — reusing (sync main)"
  git -C "$WT" fetch origin main 2>&1 | tail -1 || true
  if [ "$PRE_MERGE" = "--pre-merge" ]; then
    git -C "$WT" merge origin/main 2>&1 | tail -3 || true
  fi
  echo "$WT"
  exit 0
fi

# ── 3. 基于最新 main 创建 worktree + 分支 ─────────────────────
log "worktree add $WT @ $BRANCH (from origin/main)"
git worktree add -b "$BRANCH" "$WT" origin/main 2>&1 | tail -2

# ── 4. 可选 pre-merge (创建即同步) ────────────────────────────
if [ "$PRE_MERGE" = "--pre-merge" ]; then
  log "pre-merge origin/main into $BRANCH"
  git -C "$WT" merge origin/main 2>&1 | tail -3 || true
fi

log "✅ worktree ready: $WT (branch: $BRANCH)"
echo "$WT"
