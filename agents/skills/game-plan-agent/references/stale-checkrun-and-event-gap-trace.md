# 2026-07-24 Session Trace: Stale check_run & Event-Processor Gap

## Context
This was a cron tick for the `dev-workflow-dispatcher` workflow system. The event-processor.py produced:
```
P1: check_run.completed,issue=240,branch=research/213-rainy-night-prometheus-scaffold,conclusion=success
P2: issues.labeled,issue=214,label=workflow/backlog
P2: issues.labeled,issue=215,label=workflow/backlog
P2: issues.labeled,issue=238,label=workflow/backlog
```

## Finding 1: Stale check_run Event
PR #240 (branch: `research/213-rainy-night-prometheus-scaffold`) was already **merged** at 15:21:41Z. The check_run event arrived after the merge. The P1 handler at "verify PR is OPEN and branch starts with impl/" skipped it correctly (research prefix), but the branch check alone is insufficient — the PR could have been any prefix including `impl/`.

**Lesson:** Always verify `gh pr view <N> --json state,mergedAt` before acting on any check_run event, regardless of branch prefix. If `state == "MERGED"`, the event is stale.

**Root cause:** The route script writes the check_run event to the pending file as soon as the webhook arrives. If the PR was auto-merged (research/plan auto-merge pattern) before the webhook was processed, the event is stale.

## Finding 2: Event-Processor Script Omitted Actionable Event
The pending file contained `issues.labeled#213:workflow/plan` but the script output did NOT include it. The script grouped by `issue` (the event's numeric field):

- `check_run.completed#240:success` had `issue=240` (the PR number)
- `issues.labeled#213:workflow/plan` had `issue=213`

The script treated these as different issue groups and only surfaced `#240` and the backlog events #214, #215, #238. But PR #240's body referenced `parent #13` (actually the research PR for issue #213), and the `issues.labeled#213` event was actionable: label `workflow/plan` was current, research PR was merged, no plan PR existed.

**Lesson:** After processing script output events, always re-read the full pending file. The script's per-issue grouping may miss events that reference the same workflow through different issue numbers (e.g., a check_run with `issue=240` that is the PR for parent issue #213).

**Fix applied in this session:**
1. Verified stale check_run event → removed from pending file
2. Read remaining pending file → found `issues.labeled#213:workflow/plan`
3. Verified label current on GitHub, research PR merged
4. Spawned plan agent via delegate_task
5. Sent Feishu notification: `📋 #213 → plan (deep)`
6. Cleaned pending file to empty

## Finding 3: Default branch is `main`, not `master`
The `dev-workflow-dispatcher` skill hardcodes `master` as the default branch. This repo uses `main`. All phase agents must detect the default branch dynamically:
```bash
gh repo view devvi/agent-game-test --json defaultBranchRef --jq '.defaultBranchRef.name'
# Returns: main
```

The `workflow-branch-naming` skill already documents this for the experiment project.
