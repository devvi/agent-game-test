# Local E2E Failure Protocol (design-agreed 2026-07-31)

> Canonical plan: `docs/PLAN-e2e-verification-v2.md` in the agent-game-test repo.
> Status: DESIGN-AGREED, NOT YET IMPLEMENTED (rollout Phase 3 pending). The
> event-processor SPAWN rule below does NOT exist yet — do not assume it fires.

## Core principle: convergence criterion must match detection domain

Local e2e failures happen when CI is GREEN (CI green is what spawns review).
`SPAWN: self-correct` only fires from `check_run.completed(failure)` — so a local
failure produces NO event. Routing it into the CI-driven self-correct loop creates
an infinite loop: fix → push → CI green again (CI on ubuntu/headless cannot see
local real-rendering bugs) → review re-spawns → local fails again. Never converges,
burns full cost per round.

**Rule: the loop that detects a bug must be the same loop that verifies it.**
CI-caught bugs verify via CI; locally-caught bugs verify via a local e2e re-run.

## Failure classification (evidence-first, before any action)

| Class | Definition | Owner | Path | Counts as cycle? |
|-------|-----------|-------|------|-------------------|
| A. Infra | harness broke (black shots, timeout, worktree conflict, caffeinate lost) | review/pipeline | fix harness or degrade L3=unavailable; file infra issue | NO |
| B. Pre-existing | reproduces on main | existing | status/blocked + fix issue (existing path) | NO (blocked chain) |
| C. Spec/aesthetic | runs but doesn't match DESIGN (layout/color/mood) | HUMAN/producer | REQUEST_CHANGES + evidence; merge needs human confirm | NO |
| D. Code defect | crash, broken physics, loop hang | implement agent | local convergence loop below | YES |

## Local convergence loop (class D)

1. Retry once before classifying (live-machine flake protection: display/timing/resource contention)
2. Review labels `workflow/self-correct` + evidence comment (shots/logs/observed root cause;
   NO fix recipe — giving "how to fix" steers the fixer; give observations only)
3. event-processor needs a NEW pure-logic rule (+1 pipeline test):
   `workflow/self-correct` label seen AND no pending check_run(failure) →
   emit `SPAWN: self-correct,issue=N,pr=N,source=local-e2e`
   (This also fixes the existing blind spot: review REQUEST_CHANGES had no
   deterministic event to re-spawn implement — stalled scan was the heuristic catch-all.)
4. self-correct agent fixes IN A WORKTREE and self-verifies with run-e2e-review.sh
   (same evidence domain as detection)
5. push → CI green = regression protection only, NOT the convergence criterion
6. check_run(success) → review re-spawns → re-runs local e2e ← THE convergence criterion
7. Green → merge; red → next round. **Cap: 2 local rounds → escalate to human**
   with full evidence bundle (PR link, classification, shots, logs, tried fixes, decision needed)

## Cost governance

- Local cycles reuse `count_self_correct_cycles` (🔄 markers in comments) +
  `SELF_CORRECT_THRESHOLD=3` → implement depth=light downgrade
- Local cap is 2 (deep problems auto-fix poorly; the 3rd contact must be human;
  also protects DAG throughput — a stuck issue blocks its dependency chain)
- Class A never counts; gets its own infra issue

## Observability

- Every local e2e result → `workflow-audit.jsonl` (watchdog + dashboard already read it)
  + Feishu: `🔴 #N → 本地 e2e 失败 [分类:D, 第1/2轮]` — fixes the "why is review slow" blind spot
- Review comment always carries the e2e summary — never silent

## Rejected alternative (do not resurrect)

Review posting a `local-e2e` failed check_run to reuse the check_run machinery:
dead end — CI re-runs never re-trigger the local check, and review posting a success
check_run would self-trigger SPAWN: review. Event-source pollution.

## Related design (same plan doc)

- Verification archetypes: loop / journey / walkthrough / visual / scaffold — selected by
  `gh pr diff --name-only` ∩ shot-plan group.match; default loop, content diffs default journey
- Journey = full playthrough + shots + dialogue transcript + state trajectory (the producer's
  "全部跑一遍" instinct, bounded); evidence defaults to human confirmation (content = taste)
- Content-issue acceptance: L1 structure (schema/hemingway/completeness) + L3 presentation
  (screenshots + data↔screen fidelity: in-process `Label.text` == JSON node text) + L4 taste (human)
