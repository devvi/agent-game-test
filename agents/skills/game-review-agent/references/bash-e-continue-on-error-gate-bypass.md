# bash -e + continue-on-error = Silent Gate Bypass

## Full Trace: PR #349 (2026-07-30)

### The Setup

CI workflow `opencode-review.yml` had this step:

```yaml
- name: Run Mini Pong tests
  id: mini-pong-test
  run: |
    if [ -f mini-pong/tests/run_tests.gd ]; then
      godot --path mini-pong/ --headless --script tests/run_tests.gd > mini-pong-test-output.log 2>&1
      TEST_EXIT=$?
      echo "Test output:"
      cat mini-pong-test-output.log
      if grep -qE "SCRIPT ERROR" mini-pong-test-output.log; then
        echo "exit_code=1" >> $GITHUB_OUTPUT
      else
        echo "exit_code=$TEST_EXIT" >> $GITHUB_OUTPUT
      fi
    else
      echo "SKIP: mini-pong/tests/run_tests.gd not found"
      echo "exit_code=0" >> $GITHUB_OUTPUT
    fi
  continue-on-error: true
```

Gate step:
```yaml
- name: Test gate — block merge on failure
  if: steps.compile.outputs.exit_code != '0' || ... || steps.mini-pong-test.outputs.exit_code != '0'
  run: |
    echo "❌ Tests FAILED ..."
    exit 1
```

### What Happened

CI run 30523653503 on PR #349 (`impl/297-ai-auto-play-test`):

1. `Run Mini Pong tests` started at `07:39:33`
2. Godot ran the full test suite (sync tests + auto_play_test, 100 matches)
3. Godot exited with code 1 at `07:43:18` (3m45s) — from 7 pre-existing sync test failures
4. **Between step start and error: ZERO stdout** — no `"Test output:"` echo, no `cat` output
5. Step log: `##[error]Process completed with exit code 1.`
6. Step conclusion: `success` (due to `continue-on-error: true`)
7. `Test gate` step: `conclusion=skipped` — gate never fired
8. `Upload test output artifacts`: `conclusion=skipped` — `failure()` returned false
9. Job conclusion: `success`
10. PR #349 was merged at `07:55:57` despite failing tests

### Root Cause

GitHub Actions default shell is `bash --noprofile --norc -e -o pipefail {0}`.
The `-e` flag means "exit immediately on non-zero command."

When `godot` exited with code 1, `bash -e` terminated the script RIGHT THERE.
The lines after `godot` never executed:

```bash
TEST_EXIT=$?              # ← never reached
echo "Test output:"       # ← never reached
cat mini-pong-test-output.log  # ← never reached
echo "exit_code=$TEST_EXIT" >> $GITHUB_OUTPUT  # ← never reached
```

`$GITHUB_OUTPUT` was never written to. `steps.mini-pong-test.outputs.exit_code`
was uninitialized (empty string). The gate condition `exit_code != '0'` evaluated
`'' != '0'` → false → SKIPPED.

### Verification

```bash
# Reproduce the bug:
bash -c 'set -e; (exit 1); echo "AFTER"'
# Output: (empty, exit 1) — "AFTER" never printed

# The fix:
bash -c 'set -e; (exit 1) && true; EC=$?; echo "exit_code=$EC"'
# Output: "exit_code=1" — captured correctly
```

### Why `|| true` Is Wrong

```bash
godot ... || true
TEST_EXIT=$?  # $? = 0 (true's exit), NOT godot's!
```

`||` makes `true` the last command. `$?` captures `true`'s exit (0), losing godot's real exit code.

### Why `&& true` Works

```bash
godot ... && true
TEST_EXIT=$?  # $? = godot's exit code (1) because true never ran
```

`&&` chains: if the first command fails, the second doesn't run. `$?` preserves the first command's exit code. `set -e` ignores commands in `&&` lists because the chain is considered one recoverable unit.

### Detection Checklist

1. Check if gate step is skipped:
   ```bash
   gh run view <ID> --json jobs --jq '.jobs[0].steps[] | select(.name|startswith("Test gate"))'
   ```

2. Check for zero-output godot steps:
   ```bash
   gh run view <ID> --log | grep -B5 '##\[error\]Process completed with exit code'
   ```

3. Find unprotected godot invocations:
   ```bash
   grep -n 'godot.*2>&1$' .github/workflows/*.yml
   ```

### Scope of the Bug

Affects EVERY step in the CI workflow that:
1. Uses the default shell (`bash -e`)
2. Runs `godot` directly without `&& true` or `|| true`
3. Has `continue-on-error: true`
4. Writes to `$GITHUB_OUTPUT` AFTER the `godot` command

All 7 godot invocations in `opencode-review.yml` were affected:
- `compile-mini-pong` ×2 (check_compile.gd + fallback --quit)
- `test` (run_tests.gd)
- `smoke` (smoke_test.gd)
- `rnp` (rainy-night-prometheus --quit)
- `mini-pong` (mini-pong --quit)
- `mini-pong-test` (run_tests.gd)
