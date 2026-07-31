#!/usr/bin/env bash
# new-game-scaffold.sh — P4a: bootstrap a new game project from the framework.
#
# Usage:
#   ./scripts/new-game-scaffold.sh <project-name> [<github-owner/repo>]
#
# Creates in the CURRENT directory:
#   project.godot            — Godot 4.7 project (headless-friendly defaults)
#   game-env/manifest.yaml   — project config (single source of truth)
#   gdscripts/ scenes/ tests/ docs/ framework/ — standard layout
#   .github/workflows/       — CI: opencode-review + workflow-chain + deploy
#   README.md                — pointer to framework docs
#
# Post-steps (printed at the end, manual):
#   git init + first commit + push to GitHub
#   create labels (scripts/setup-labels.sh)
#   create webhook (hermes webhook subscribe + webhook-sync.py discovers repo)
#   create cron godot-workflow-poller with workdir=<project path>
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "❌ Usage: $0 <project-name> [<owner/repo>]" >&2
  exit 1
fi

PROJECT_NAME="$1"
REPO="${2:-}"
SLUG="$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g')"
HERE="$(cd "$(dirname "$0")" && pwd)"
FRAMEWORK="$(cd "$HERE/../framework" && pwd)"

mkdir -p "$SLUG"
cd "$SLUG"

# ── project.godot (Godot 4.7, headless-friendly) ──────────────
cat > project.godot <<'EOF'
; Engine configuration file (Godot 4.7)
config_version=5

[application]
config/name="PLACEHOLDER_NAME"
config/features=PackedStringArray("4.7")

[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/size/resizable=false

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
EOF
sed -i '' "s/PLACEHOLDER_NAME/$PROJECT_NAME/" project.godot 2>/dev/null || \
  sed -i "s/PLACEHOLDER_NAME/$PROJECT_NAME/" project.godot

# ── game-env/manifest.yaml ─────────────────────────────────────
mkdir -p game-env
cat > game-env/manifest.yaml <<EOF
# Project manifest — single source of truth (P3 parameterization)
project:
  name: $PROJECT_NAME
  repo: ${REPO:-devvi/$SLUG}
  description: "Godot 4.7 game — $PROJECT_NAME"

engine:
  name: godot
  runner: godot
  version: 4.7.1

source:
  dir: gdscripts/

test:
  dir: tests/
  framework: gdscript
  entry: tests/run_tests.gd
  smoke: tests/smoke_test.gd

code_gen:
  language: gdscript
  engine: opencode
  endpoint: http://127.0.0.1:18765

git:
  default_branch: main
  branch_prefixes:
    research: research/
    plan: plan/
    implement: impl/

workflow:
  max_concurrent_issues: 4
  max_phase_slots: 4
EOF

# ── Standard layout ────────────────────────────────────────────
mkdir -p gdscripts scenes tests docs/GAME_DESIGN framework

# Empty test runner stub (compile-checkable)
cat > tests/run_tests.gd <<'EOF'
extends SceneTree
# Test runner stub — replace with real assertions.
# Convention: _assert(condition, name) must increment counters.
var passed := 0
var failed := 0

func _assert(cond: bool, name: String) -> void:
    if cond:
        passed += 1
    else:
        failed += 1
        push_error("FAIL: " + name)

func _init() -> void:
    _assert(true, "stub test")
    print("PASSED=%d FAILED=%d" % [passed, failed])
    quit(1 if failed > 0 else 0)
EOF

# ── CI workflows ───────────────────────────────────────────────
mkdir -p .github/workflows
if [ -d "$FRAMEWORK/cicd" ]; then
  cp "$FRAMEWORK/cicd/"*.yml .github/workflows/ 2>/dev/null || true
fi
if [ ! -f .github/workflows/opencode-review.yml ]; then
  echo "⚠️  framework/cicd missing — copy opencode-review.yml / workflow-chain.yml"
  echo "   manually from an existing project (agent-game-test/.github/workflows/)."
fi

# ── Framework reference ────────────────────────────────────────
cp "$FRAMEWORK/ARCHITECTURE.md" framework/ARCHITECTURE.md 2>/dev/null || true
cp "$FRAMEWORK/quickstart.md" framework/quickstart.md 2>/dev/null || true

# ── README ─────────────────────────────────────────────────────
cat > README.md <<EOF
# $PROJECT_NAME

Godot 4.7 game developed with the agent-game workflow.

- Architecture: \`framework/ARCHITECTURE.md\`
- Quickstart: \`framework/quickstart.md\`
- Project config: \`game-env/manifest.yaml\`
EOF

echo ""
echo "✅ Scaffolded '$SLUG' (project: $PROJECT_NAME, repo: ${REPO:-devvi/$SLUG})"
echo ""
echo "Next steps (manual):"
echo "  1. cd $SLUG && git init && git add -A && git commit -m 'scaffold' && git push"
echo "  2. cp scripts from an existing project: event-processor.py, stage-gate.py,"
echo "     workflow-dispatcher.py, sync-to-hermes.sh (+ tests/pipeline/)"
echo "  3. bash scripts/sync-to-hermes.sh   (syncs cron scripts)"
echo "  4. Create GitHub labels: bash scripts/setup-labels.sh"
echo "  5. Webhook: hermes webhook subscribe github-dev-workflow --script workflow-dispatcher.py"
echo "     (webhook-sync.py auto-discovers this repo via game-env/manifest.yaml)"
echo "  6. Cron: godot-workflow-poller with workdir=$(pwd)"
echo "  7. First manual GDD draft + docs/GAME_DESIGN/INDEX.md"
