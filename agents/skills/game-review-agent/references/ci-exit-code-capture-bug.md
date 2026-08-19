# CI Exit Code Capture Bug: `$?` After Pipe Captures `tee`, Not Godot

> Discovered during PR #193 review (scene spatial layout). Three Bridge/Underpass tests (`TC-B1-0`, `TC-B3-1`, `TC-B3-2`) were silently failing in CI while CI reported `conclusion=success`.

## The Bug

In GitHub Actions workflows using `continue-on-error: true`, a common pipe pattern silently swallows test failures:

```yaml
- name: Run GDScript tests
  run: |
    godot --headless --script tests/run_tests.gd 2>&1 | tee test-output.log
    echo "exit_code=$?" >> $GITHUB_OUTPUT   # ❌ BUG: $? = tee's exit code
```

`$?` after a shell pipeline captures the exit code of the **last command** in the pipeline — `tee`, not `godot`. `tee` exits 0 unless disk is full, so `exit_code` is always `0`, and the gate step never fires.

## The Fix

Use `PIPESTATUS` (Bash) or `pipestatus` (Zsh) to capture the exit code of the first pipe command:

```yaml
- name: Run GDScript tests
  run: |
    godot --headless --script tests/run_tests.gd 2>&1 | tee test-output.log
    echo "exit_code=${PIPESTATUS[0]}" >> $GITHUB_OUTPUT   # ✅ Correct — godot's exit code
```

## How to Detect

Check the CI workflow YAML (typically `.github/workflows/opencode-review.yml` or `.github/workflows/test.yml`):

```bash
grep -n '\$?' .github/workflows/*.yml
```

Flag any occurrence where `$?` follows a pipe (`|`). The fix is `${PIPESTATUS[0]}`.

## Combined with `continue-on-error: true`

When `continue-on-error: true` is set on the test step AND the exit code is captured from `tee`, the workflow reports a successful pipeline even when Godot tests fail. The test output artifact exists (`test-output.log`) but no gate validates it.

## Real-world Impact (from PR #193)

```
Passed: 783
Failed: 3
❌ Some tests FAILED
  ❌ FAIL: TC-B1-0: bridge has _get_tone method
  ❌ FAIL: TC-B3-1: underpass has _get_tone method
  ❌ FAIL: TC-B3-2: _get_tone exists
Bridge/Underpass — Passed: 12 Failed: 3
```

These 3 failures were present in CI for multiple PRs — each showed `conclusion=success` while 3 tests silently failed. The review agent's local test run caught them, but the decision gate then blocked all subsequent merges (pre-existing failures policy). Fixing either the CI exit code or the broken tests unblocks the pipeline.

## Shell Portability Note

- **Bash** (`shell: bash` in GHA): `PIPESTATUS` is an array variable. `${PIPESTATUS[0]}` gets the first command's exit code.
- **Zsh** (macOS default, `shell: zsh --no-rcs`): Use `pipestatus[1]` instead (1-indexed).
- **POSIX sh** (e.g. Alpine/Docker `sh`): Neither `PIPESTATUS` nor `pipestatus` exists. Use a temporary file approach or restructure to avoid pipes when exit codes matter.
