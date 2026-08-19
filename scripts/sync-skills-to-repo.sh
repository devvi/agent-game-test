#!/usr/bin/env bash
# sync-skills-to-repo.sh — 将 ~/.hermes/skills/ 中的 agent skills 同步到仓库 agents/skills/
# 方向: Hermes 运行时 → Git 备份
# 目的: 保证每次 skill_manage 修改后能提交到版本控制
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HERMES_SKILLS="$HOME/.hermes/skills/autonomous-ai-agents"

echo "Syncing agent skills from Hermes runtime to Git repo..."
echo "  Source: $HERMES_SKILLS"
echo "  Target: $REPO_ROOT/agents/skills/"

SKILLS=(
  "game-research-agent"
  "game-plan-agent"
  "game-implement-agent"
  "game-review-agent"
  "game-post-merge-agent"
)

for skill in "${SKILLS[@]}"; do
  src="$HERMES_SKILLS/$skill/SKILL.md"
  dst="$REPO_ROOT/agents/skills/$skill/SKILL.md"

  if [ -f "$src" ]; then
    mkdir -p "$(dirname "$dst")"
    if ! diff -q "$src" "$dst" 2>/dev/null; then
      cp "$src" "$dst"
      echo "  ✅ $skill (updated)"
    else
      echo "  ⏭️  $skill (unchanged)"
    fi
  else
    echo "  ⚠️  $skill SKILL.md not found at $src (skip)"
  fi
done

echo "Done. Run 'git add agents/skills/ && git commit && git push' to save."
