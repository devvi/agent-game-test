# Reference: Pre-Created DESIGN Doc Scenario

> Scenario documented from PR #176 review (Issue #149 — Player Character)
> Date: 2026-07-23

## Situation

The plan-phase workflow created and merged the DESIGN doc (`docs/DESIGN/149-player-character.md`) in a **separate PR** (#173) *before* the implement PR (#176) was opened. The implement PR's diff contained no doc changes — but the design was fully documented.

## How the review handled it

1. **Step 4 (Verify Design Docs)**: `gh pr diff 176 --name-only | grep -E 'docs/'` returned nothing. This could be mistaken for a missing-doc-blocker.

2. **Resolution**: Checked whether the DESIGN doc for the parent issue already existed:
   ```bash
   ls docs/DESIGN/149-*.md 2>/dev/null
   ```
   It existed and accurately described the feature. No doc changes in the PR diff were needed — the design was already finalized.

3. **GDD update (post-merge)**: The GDD file `08-PLAYER-CONTROLLER.md` already existed from #142 (the initial player controller PR). Instead of creating a new file, the GDD was updated by patching the existing file with new sections describing the node tree builder and collision shape added in #149.

## Lesson

Not all feature PRs carry doc changes in their diff. When the DESIGN doc was pre-created in a plan-phase or design-only PR, the implement PR just executes the design. Check for the pre-existing doc rather than flagging missing doc changes.

Similarly, the GDD file may already exist from a prior implement PR that built the base system. Incremental PRs on the same feature should patch the existing GDD file with new sections, not create duplicates.
