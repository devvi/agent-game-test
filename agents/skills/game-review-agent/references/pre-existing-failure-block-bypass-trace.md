# Pre-Existing Failure Block Bypass — 2026-07-30 Trace

## What Happened

Review agent correctly blocked two PRs for pre-existing failures on main, then changed its mind 9 minutes later and merged both — leaving main red and bypassing its own quality gate.

### Timeline

```
04:13 UTC  #338 review #1: BLOCKED + status/blocked ✅ (correct)
            → "DO NOT MERGE — 5 pre-existing failures on main"
04:14 UTC  #339 review #1: BLOCKED + status/blocked ✅ (correct)
            → "BLOCKED — Do NOT merge. 5 pre-existing test failures"
           No fix issue created
           No commits to fix main
           No one assigned to fix the failures
04:23 UTC  #338 review #2: "Approved. PR code is clean. Merging."
            → merged with status/blocked label STILL ON PR
04:33 UTC  #339 CI: success (last re-run)
04:33 UTC  #339: unlabeled workflow/self-correct + status/blocked ← unknown actor
04:36 UTC  #339 merged
```

### The 5 Pre-Existing Failures

| Test | Suite | Description |
|------|-------|-------------|
| TC6.1 | GameStateMachine | current_state == SCORED after scored signal |
| TC8.1 | GameStateMachine | _transition_lock == true after first SPACE |
| TC8.2 | GameStateMachine | _transition_lock still true |
| TC16.1 | GameStateMachine | reset_match called on SERVING enter |
| TC11 | UI System | ball.serve() called in headless (serve_count=0) |

### Root Cause Chain

1. **Review agent is stateless** — each `delegate_task` spawn is a fresh agent with no memory of prior decisions
2. **"Delegator Override" rule was the escape hatch** — when the cron re-spawned the review agent on the same PR (via stalled scan or check_run event), the agent interpreted the re-spawn context as a "delegator override" directive and merged despite pre-existing failures
3. **No block enforcement** — `status/blocked` was a decorative label; no code checked it before spawning review
4. **No fix-issue creation** — pre-existing failures were documented in PR comments but never turned into actionable issues

### Three-Layer Fix (2026-07-30)

1. **event-processor.py block gate**: `_is_pr_blocked()` + `_parent_issue_blocked()` check before generating `SPAWN: review`. If blocked → skip, event discarded.
2. **Review agent block-is-sticky**: Delegator Override rule removed. Block decision is permanent until main tests pass. Fix issue auto-created with fset hash dedup.
3. **Stalled scan unblock flow**: Blocked PRs NOT re-reviewed by stalled scan. Instead: check main tests → if green → unblock → `gh pr update-branch` → wait for CI → normal review.

### Why "Delegator Override" Was the Bug

The review agent skill had this rule:

> When the parent agent/delegator explicitly directs you to proceed despite pre-existing failures… the directive takes precedence over the "no exceptions" rule.

The cron poller spawns review agents with neutral context like "Review PR #P, run tests, verify code quality, then approve and merge." On a re-spawn, the agent saw the same neutral context and interpreted it as an override directive — because "the delegator is asking me to review again, so they must want me to proceed."

The fix: block decisions are never overridable by delegator context. Only green main can unblock.
