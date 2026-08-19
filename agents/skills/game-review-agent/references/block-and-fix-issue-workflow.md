# Block & Fix Issue Workflow

> Reference for the three-layer block enforcement system designed after the
> #338/#339 review-agent bypass incident (2026-07-30). The review agent
> correctly blocked both PRs for 5 pre-existing failures on main, then
> re-spawned 9 minutes later and changed its mind — merging both PRs with
> `status/blocked` still attached.

## Design Principle

> **Block is permanent until the root cause (pre-existing failures on main) is actually fixed.**

The review agent is stateless (spawned fresh each time via `delegate_task`).
Without external enforcement, it can re-evaluate a blocked PR and reach a
different conclusion. The fix is three-layer defense:

## Three-Layer Defense

| Layer | Where | What |
|-------|-------|------|
| 1 | `event-processor.py` | Block gate: `_is_pr_blocked()` checks PR/parent labels before generating `SPAWN: review` |
| 2 | cron stalled scan | Unblock flow: checks if main is green → if yes, unblocks → `update-branch` → waits for CI |
| 3 | game-review-agent SKILL | No "delegator override." Block is sticky. Creates fix issue with fset hash dedup. |

## Failure-Set Hash (fset) Dedup

Multiple review agents may block different PRs for overlapping sets of
pre-existing failures. To prevent duplicate fix issues, each fix issue
carries a failure-set hash.

### Computing the Hash

```bash
# Sort failure names alphabetically, join with pipe, md5 first 8 chars
FAILURES="TC6.1|TC8.1|TC8.2|TC11|TC16.1"
FSET_HASH=$(echo -n "$FAILURES" | md5 | cut -c1-8)
# → "a84c7a6b"
```

### Fix Issue Title Format

```
Fix {N} pre-existing test failures on main [fset:{hash}]
```

### Dedup Algorithm

```
1. Collect failure names → sort → set S
2. Compute fset_hash
3. Search: gh issue list --search "[fset:{hash}] in:title" --state open
4. If exact match found:
   → Link: gh issue comment <existing> --body "Also blocks PR #{N}"
   → Skip creation
5. If not found → check existing fix issues for superset coverage:
   for each open issue with title "Fix * pre-existing*":
     parse body failure table → existing set E
     if S ⊆ E: this fix issue already covers our failures → link, skip
     if E ⊂ S: update existing issue to include new failures + new hash
6. If no match → create new fix issue
```

### Edge Cases

| Scenario | Handling |
|----------|----------|
| Exact duplicate (same failures, different PR) | `gh issue list --search "[fset:<hash>] in:title"` finds it |
| Subset (current failures ⊂ existing fix issue) | Parse body table, detect subset, link to existing |
| Superset (current failures ⊃ existing fix issue) | Update existing issue with new failures + new hash |
| Race condition (two agents create simultaneously) | Pipeline handles: second issue's research agent detects main is green, closes as "Already fixed by #N" |

## Unblock Flow (Stalled Scan)

When the stalled scan finds an `impl/*` PR with `status/blocked`:

```
1. Check main tests
2. If main is green:
   a. Remove status/blocked from PR + parent issue
   b. gh pr update-branch <N>  (merge main → impl branch, push → retrigger CI)
   c. Post Feishu: 🔓 #N → unblocked
   d. Do NOT spawn review — wait for CI check_run.completed
3. If main is NOT green:
   a. Skip
   b. Post reminder every 30min: ⏳ #N → still blocked
4. If update-branch fails (merge conflict):
   a. Keep blocked
   b. Post Feishu: ⛔ #N → merge conflict, manual resolution needed
```

## Incident Trace: #338 / #339 (2026-07-30)

```
04:13 #338 review #1: blocked ✅ → status/blocked
04:14 #339 review #1: blocked ✅ → status/blocked
04:23 #338 review #2: "Approved. PR code is clean. Merging."
     → merged with status/blocked still on
04:33 #339: unlabeled workflow/self-correct + status/blocked
04:36 #339 merged
```

Root cause: Review agent was re-spawned on the same PR, re-evaluated
without memory of its prior block decision, and changed its mind.

Fix: Three-layer defense (this document). The review agent can no longer
be re-spawned on a blocked PR, and the only path to unblock is through
the stalled scan detecting a green main branch.
