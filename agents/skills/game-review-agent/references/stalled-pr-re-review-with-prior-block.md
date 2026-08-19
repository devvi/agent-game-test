# Stalled PR Re-Review: Prior Block from Pre-Existing Failures

> Session trace: 2026-07-24 — PR #193 (impl/151-scene-spatial-layout), Issue #151
> Skill: game-review-agent
> Reference for: When a stalled-PR scan finds an `impl/*` PR whose prior review recommended "Do NOT merge" due to pre-existing test failures

## Scenario

A stalled PR has:
- CI passed (`test-and-report` = SUCCESS)
- A prior review comment from a previous game-review-agent run that documented pre-existing test failures and said "Cannot merge"
- PR is still OPEN, mergeable is MERGEABLE
- PR is classified as scene-layout/asset-only (`.tscn` changes only, no GDScript)

## The Tension

The game-review-agent's merge decision table says:
> Pre-existing failures on feature PR: Do NOT merge. Escalate.

But the scene-layout/asset-only classification section says:
> The PR's test verification is the existing test suite — if all existing tests pass (or only pre-existing failures), the placement does not break anything.

The scene-layout exception was added after the prior review ran. The prior review's block was correct per the general rule at the time.

## Resolution Steps

### 1. Re-confirm Pre-Existing Failures

Run the pre-existing failure check **on `main`** — do not trust the prior review's finding without re-verifying. The failures may have been fixed since:

```bash
git checkout main
git pull origin main
/Applications/Godot.app/Contents/MacOS/Godot --headless --script tests/run_tests.gd > /tmp/main_test_output.txt 2>&1
grep -E '(❌|Passed:|Failed:)' /tmp/main_test_output.txt | tail -10
git checkout -
```

Compare: the same failure count must appear on both the PR branch and `main`. If `main` now has fewer failures, the situation may have changed.

### 2. Confirm PR Classification

```bash
gh pr diff <N> --name-only
```

If all changed files are `.tscn`, `.tres`, `.png`, `.glb`, `.wav` (no `.gd`, `.js`, `.ts`, `.py`) → **scene-layout/asset-only PR**. The scene-layout exception applies.

### 3. Verify DESIGN Doc

```bash
ls docs/DESIGN/<N>-*.md
```

The DESIGN doc must pre-exist and list exact coordinates/parameters. Compare each coordinate from the DESIGN doc against the diff — all must match.

### 4. Submit Review with Override Rationale

Since the review agent's `GH_TOKEN` matches the PR author (same GitHub user), use `--comment` (not `--approve`):

```bash
gh pr review <N> --comment --body '## Review Summary (#<N>)

### Checks
- **Tests**: N passed, N failed ⚠️
  - ❌ [list failing tests]
  - **Pre-existing**: All <N> failures reproduce identically on `main` — confirmed re-verification.
- **Test files**: N/A — scene-layout-only PR (`.tscn` only).
- **Design docs**: ✅ Verified — coordinates match DESIGN doc exactly.
- **Code quality**: ✅ Clean — no GDScript changes.

### Verdict
Scene-layout PR, pre-existing failures confirmed on `main`, no regressions from this PR. Prior review block overridden per scene-layout/asset-only exception. Merging.'
```

### 5. Merge

```bash
git checkout <branch>
git stash
gh pr merge <N> --squash --delete-branch
gh pr view <N> --json state --jq '.state'  # verify MERGED
git checkout main
git pull origin main
```

### 6. Post-Merge

Proceed with the standard post-merge workflow:
- GDD update: skip for scene-layout PRs (unless the placement introduces a new gameplay-affecting system)
- Project board sync: add issue to board → Stage=Done → Progress=100%
- Feishu notification

## Key Differences from Standard Stalled-PR Handling

| Aspect | Standard stalled PR handling | This scenario |
|--------|------------------------------|---------------|
| Root cause | Merge conflicts, skipped CI, stale branch | Prior review blocking on pre-existing failures |
| CI status | Never ran / cancelled / stuck | ✅ PASSED (SUCCESS) |
| Local branch | Needs conflict resolution | Clean — no conflict |
| Decision | Diagnose → resolve → re-trigger CI → merge | Re-evaluate classification → override prior block → merge |
| Prior review | Not relevant (no prior review exists) | Must be explicitly addressed in the new review comment |

## Pitfalls

- **The prior review's "Do NOT merge" was correct for its time.** Do not characterize the prior review as wrong. Frame the override as a re-evaluation under the updated scene-layout exception.
- **Pre-existing failures may have been fixed on `main`** since the prior review ran. Always re-verify before using the exception.
- **Do NOT skip the test run** just because the prior review already ran tests. Run them fresh — the `main` branch may have changed since then.
- **The scene-layout exception requires a pre-existing DESIGN doc.** If no DESIGN doc exists for this issue, the PR is not scene-layout — it's a feature PR missing design documentation, and the prior block stands.
