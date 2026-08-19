# Pipeline Output Audit: End-to-End Issue Review

> **When to use:** A user asks you to "review all outputs of Issue #N" — an issue that has already progressed through the full research→plan→implement pipeline (or any subset). Not a standard PR diff review — this is a **post-pipeline quality audit** tracing deliverables back to the source Issue.

## Protocol

### Phase 1: Gather All Artifacts in Parallel

```bash
# 1. The parent issue
gh issue view <N> --json title,body,labels,state,createdAt,comments

# 2. Linked PRs (search by issue number in title/body)
gh pr list --state merged --search "<N> in:title or <N> in:body" \
  --json number,title,state,mergeCommit,files,additions,deletions

# 3. Design docs on disk
ls docs/PRD/<N>-*.md 2>/dev/null
ls docs/DESIGN/<N>-*.md 2>/dev/null
ls docs/TASKS/<N>-*.md 2>/dev/null
```

### Phase 2: Trace the Deliverable Chain

| Step | Check | Signal |
|------|-------|--------|
| Issue → PRD | Does the PRD cover ALL acceptance criteria from the Issue? | Missing sections in PRD |
| PRD → DESIGN | Does the DESIGN implement every requirement from the PRD? | Scope drift, forgotten items |
| DESIGN → Code | Does the actual code match the DESIGN spec? | Config values wrong, missing files |
| Code → CI | Does the CI step actually work on real Godot? | Commands that hang or timeout |

### Phase 3: Execute CI Steps Locally

**Critical:** Don't just check that files exist — run the actual CI commands. This catches latent bugs that file-level review misses.

```bash
# For Godot sub-project validation:
godot --path <sub-project>/ --headless --quit 2>&1
echo "EXIT: $?"

# For GDScript compile checks:
godot --headless --check-only <script.gd> 2>&1 | grep "SCRIPT ERROR"

# For full test suite:
godot --headless --script tests/run_tests.gd > /tmp/test-output.log 2>&1
grep -E '(Passed:|Failed:|❌|✅)' /tmp/test-output.log | tail -20
```

**Known hang case:** `godot --path <sub-project> --headless --quit` hangs when `run/main_scene=""` is empty. See `godot-headless-testing` skill's pitfall section for details on detection and fix.

### Phase 4: Check for Missing Artifacts

```bash
# GDD update — was one expected?
ls docs/GAME_DESIGN/INDEX.md 2>/dev/null && grep -i "<feature-name>" docs/GAME_DESIGN/INDEX.md

# CI artifacts — were test logs, output artifacts correctly wired?
grep -n "upload-artifact\|path:" .github/workflows/<ci-file>.yml | grep -A1 "<sub-project>"

# Test gate — is the new step included in the merge-block condition?
grep "steps\..*\.outputs.exit_code != '0'" .github/workflows/<ci-file>.yml
```

### Phase 5: Report Structure

Use a table for the deliverable checklist:

```
## 🔍 Issue #N Review — [Title]

### Deliverable Trace

| Deliverable | Location | Status |
|-------------|----------|--------|
| PRD | `docs/PRD/N-slug.md` | ✅ (PR #M, research agent) |
| DESIGN | `docs/DESIGN/N-slug.md` | ✅ (PR #M, plan agent) |
| Implementation | `<paths>` | ✅ created/✅ verified |
| CI validation | `<ci-file>` | ✅ / ❌ bug found |
| GDD entry | `docs/GAME_DESIGN/...` | ✅ / 🟡 missing |

### Acceptance Criteria Verification

| # | Criterion | Status | Notes |
|---|-----------|--------|-------|
| 1 | `x` exists | ✅ | Verified |
| 2 | `y` property set to `z` | ✅ | Verified |
| 3 | `godot --path ... --headless --quit` exit 0 | ❌ / 🟡 | Hangs — see below |

### Issues Found

- 🔴 **Critical:** [description with evidence]
- 🟡 **Minor:** [description]

### GDD Audit

- ✅ / 🟡 GDD updated / missing entry
- Suggested follow-up: [if any]
```

## Common Bugs This Audit Catches

| Bug | How It Surfaces | Example |
|-----|----------------|---------|
| **CI command hangs** | Running the CLI step locally reveals Godot blocking on `run/main_scene=""` | This session: `godot --path mini-pong/ --headless --quit` hangs |
| **CI step wired but gate missing** | `Validate X` step exists but `steps.X.outputs.exit_code` not in the merge-block `if:` condition | New step ignored by test gate |
| **Artifact path not updated** | `Upload test output` step references old path for the new step's log file | mini-pong-output.log missing from upload |
| **Files created but never tested** | CI only runs on `impl/` branches — `plan/` or `research/` PRs bypass CI entirely | Scaffold created in PR #303, CI never ran |
| **Acceptance criteria unverifiable** | Criterion says "exit code 0" but the command can never produce 0 | `run/main_scene=""` guarantees non-zero exit |
