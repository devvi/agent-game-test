#!/usr/bin/env bash
# Sync project scripts → ~/.hermes/scripts/
# Run after editing scripts/ in the project
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "Syncing project scripts to ~/.hermes/scripts/..."
for f in event-processor.py event_processor_lib.py stage-gate.py workflow-dispatcher.py workflow-watchdog.py workflow-metrics.py create-issues.py run-e2e-review.sh e2e/analyze_bmp.py e2e/resolve_plan.py; do
  if [ -f "$SCRIPT_DIR/$f" ]; then
    mkdir -p "$HOME/.hermes/scripts/$(dirname "$f")"
    cp "$SCRIPT_DIR/$f" "$HOME/.hermes/scripts/$f"
    echo "  ✅ $f"
  fi
done
echo "Done. Cron scripts updated."
