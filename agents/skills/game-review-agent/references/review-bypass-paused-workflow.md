# Post-Hoc Review Bypass Detection

**Date:** 2026-07-29
**Related:** PRs #309, #310; Issues #288, #289

## Pattern

When the workflow poller is paused, implement PRs can merge without passing through the review agent. This creates a blind spot where merged code has never been code-reviewed.

## Detection Command

```bash
# Check a recently merged impl/* PR for review bypass
PR=N
gh pr view $PR --json reviews,comments,state,mergedAt,mergedBy,auto_merge,createdAt
```

**Red flags indicating review bypass:**
- `reviews: []` — no approval
- `comments: []` — no review agent activity
- `auto_merge: null` — not auto-merged
- `mergedAt` within 2 minutes of `createdAt` — merged too fast for review
- `mergedBy` same as PR creator — self-merge

## Batch Check

```bash
# Check all recently merged impl/* PRs for review bypass
for pr in $(gh pr list --state merged --search "head:impl" --limit 20 --json number --jq '.[].number'); do
  reviews=$(gh pr view $pr --json reviews --jq '.reviews | length')
  if [ "$reviews" -eq 0 ]; then
    info=$(gh pr view $pr --json number,title,mergedAt,mergedBy --jq '"#\(.number) \(.title) merged=\(.mergedAt[11:16]) by=\(.mergedBy.login)"')
    echo "⚠️ NO REVIEW: $info"
  fi
done
```

## Verified Instance (2026-07-29)

| PR | Issue | Created | Merged | Gap | Reviews | CI |
|----|-------|---------|--------|-----|---------|-----|
| #309 | #288 | 10:56:50 | 10:58:25 | 95s | 0 | ✅ |
| #310 | #289 | 10:57:16 | 10:59:42 | 146s | 0 | ✅ |

Root cause: godot-workflow-poller (83fee8577195) paused from 01:37 to 18:19 UTC.
Implement agent self-merged both PRs directly with `gh pr merge`.

## Review Agent Race Condition — Paused Workflow Variant

The existing `review-agent-race-condition.md` covers the operator pre-merge case.
This is a different variant: the entire workflow poller (cron) is paused, so NO
agent processes `check_run.completed` events. The implement agent, running with
`gh pr merge` in its toolset, discovers it can merge and does so.

**Mitigation:** The `game-implement-agent` skill now explicitly forbids merge.
The review agent should also run the batch detection command above during
its startup to detect already-merged-but-unreviewed PRs.
