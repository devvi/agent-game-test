# Review Agent Race Condition (2026-07-23)

## Problem Evolution

Three generations of the race condition were found and fixed:

### Gen 1: Operator Merges by Depth (Fixed 2026-07-23 ~10:00)

Operator agent merges implement PRs of any depth. `check_run.completed`
webhook arrives 17-80s after the merge. `SPAWN: review` finds PR already merged → skips.

Timeline for PR #133 (impl/130, depth/deep):
```
Operator merges PR              04:47:20 UTC
check_run webhook arrives       04:47:37 UTC  (+17s)
event-processor → SPAWN: review
LLM: "PR is OPEN?" — NO, merged → skip
```

**Fix:** Added depth check — depth/deep issues are NOT auto-merged.

### Gen 2: Stalled Scan Merges Before Step 4 Guard (Fixed 2026-07-23 ~14:30)

The stalled scan has:
```
Step 2: gh pr merge <N> --squash (applies to ALL PRs)
...
Step 4: Do NOT touch impl/* branches
```
LLM reads linearly — merges at Step 2 before reaching Step 4.

**Fix:** Added `❗ Skip if branch starts with impl/` directly on Step 2's merge line.

### Gen 3: `gh pr merge --auto` Re-Enables Auto-Merge (Fixed 2026-07-23 ~15:00)

Stage-gate.py correctly disables auto-merge (`auto_merge=false`). But the operator's code block runs `gh pr merge --auto --squash --delete-branch` which RE-ENABLES it. When CI passes, GitHub auto-merges immediately.

Trace from PR #175 (impl/148):
```
10:04:01  PR #175 MERGED by GitHub auto-merge
10:04:14  check_run.completed webhook delivered (HTTP 200, too late)
```

**Fix:** Added `if [[ "$BRANCH" != impl/* ]]; then gh pr merge --auto ...` guard.

### Gen 4 (Unfixed): Stalled Scan Advances Backlog Issues

The stalled scan's "proactive label advancement" was advancing `workflow/backlog` issues, ignoring the dependency-aware picker. Fixed by adding explicit constraint: "Never advance issues from workflow/backlog or workflow/available."

## Verification

- `gh pr view <N> --json reviews` → > 0 reviews = review agent worked
- `gh pr view <N> --json mergedBy` → review agent's session should have merged
- `gh api repos/.../hooks/.../deliveries?per_page=5` — check_run events HTTP 200 (not blocked)

## See Also

- `review-agent-diagnostics` skill — full 5-layer diagnostic
- `auto-merge-race-20260723.md` in `review-agent-diagnostics` references — complete timeline
