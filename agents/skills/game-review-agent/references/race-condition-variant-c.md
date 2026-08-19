# Race Condition — Variant C: MERGEABLE with implementation on main

> **Date:** 2026-07-29
> **Real case:** PR #322 (impl/290-ai-opponent) — implementation files (paddle.gd, game.tscn)
> already on main via scoring PR #321, but PR still OPEN + MERGEABLE with test-only diff.

## Detection

The two existing race-condition variants (A: MERGED, B: OPEN+CONFLICTING) don't cover this:

```
gh pr diff <N> --name-only
# Returns: only test files, or a subset of what git log says the PR commit changed

git log --oneline impl/<branch> -- <key-implementation-file>
# Returns: PR commit (e.g. a6fd3bf feat(...)) NOT on main

git diff main impl/<branch> -- <key-implementation-file>
# Returns: empty (files are identical — already on main via another PR)

gh pr view <N> --json mergeable --jq '.mergeable'
# Returns: MERGEABLE (not CONFLICTING)
```

**Symptom chain:** `gh pr diff` shows fewer files than the PR commit actually changed → the missing files are identical on both branches → the implementation was already merged via another channel (e.g., a subsequent PR that incorporated the same changes).

## How It Happens

In multi-PR pipelines, one implement PR's code may be folded into a subsequent PR's changes. When PR #321 (scoring) modifies `paddle.gd` and `game.tscn`, and PR #322 (AI opponent) also modifies those files, the merge order matters. If #321 merges first carrying #322's implementation changes, then #322's diff against main only shows the files that #321 didn't touch (the test files).

## Action

| Step | Action |
|------|--------|
| 1. Confirm | `git diff main impl/<branch> --name-only` shows only additive files |
| 2. Verify | Run tests on main (implementation already there) + on PR branch (tests added) |
| 3. Merge | Merge normally via `gh pr merge <N> --squash --delete-branch` — the squash adds test files cleanly |
| 4. Post-merge | GDD update, PROJECT.md, Feishu, project board — all run as usual |

**Do NOT close the PR.** Unlike variant B, the PR is MERGEABLE and adds value (tests). Closing would discard the test coverage.

**Do NOT skip post-merge.** The implementation is already live on main, so all state-keeping tasks (GDD, PROJECT.md, board sync) must run to reflect completion.

## Verification Checklist

```bash
# 1. Confirm implementation files are identical
gh pr diff <N> --name-only          # should show test-only files
git diff main impl/<branch> --name-only  # should match gh pr diff

# 2. Run tests on main (baseline) — implementation should work
godot --path <sub-project>/ --headless --script tests/run_tests.gd

# 3. Run tests on PR branch — new tests should pass
git checkout impl/<branch>
godot --path <sub-project>/ --headless --script tests/run_tests.gd

# 4. Merge adds tests cleanly
git checkout main && git pull
gh pr merge <N> --squash --delete-branch
```

## Relationship to Other Variants

| Variant | PR State | mergeable | Action |
|---------|----------|-----------|--------|
| A | MERGED | N/A | Skip review, do post-merge |
| B | OPEN | CONFLICTING | Close PR, do post-merge |
| **C** | OPEN | **MERGEABLE** | **Merge normally**, do post-merge |
