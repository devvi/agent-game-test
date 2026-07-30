---
name: game-review-agent
description: "Review implement PRs, make merge decisions, and update GDD post-merge. Triggered by check_run.completed (conclusion=success) on impl/* branches as the final gate before merge."
tags: ["workflow", "code-review", "gdd", "merge-gate"]
---

# Game Review Agent

> The **final quality gate** before an implement PR merges. Triggered by `check_run.completed` (conclusion=success) on an `impl/*` branch. Runs code quality review, verifies tests and docs, then either merges or escalates.

## Variant: Pipeline Output Audit (Manual Invocation)

**When a user says "review all outputs of Issue #N"** — they want an end-to-end audit of the pipeline's deliverable chain, not a single PR diff review. This is a *post-hoc* quality check on a completed issue (research → plan → implement all done).

The protocol traces: Issue → PRD → DESIGN → Implementation → CI **running locally** → GDD completeness. See `references/pipeline-output-audit.md` for the full protocol, report template, and the common bug patterns it catches (CI hangs, missing gate conditions, bypassed-CI gaps, unverifiable acceptance criteria).

## Critical Prerequisite: Gateway Rate Limit

**The review agent cannot be triggered if the gateway is rate-limiting `check_run` events.**

The gateway defaults to **30 requests/minute** per webhook route. When CI completes on multiple PRs simultaneously, `check_run.completed` events are dropped with HTTP 429 → review agent never spawns.

**Before investigating any review agent failure, always check:**
```bash
HOOK_ID=$(gh api repos/<owner>/<repo>/hooks --jq '.[0].id')
gh api repos/<owner>/<repo>/hooks/$HOOK_ID/deliveries?per_page=5 \
  --jq '.[] | "\(.event): HTTP \(.status_code)"'
```

If `check_run` events show HTTP 429:
```bash
hermes config set platforms.webhook.extra.rate_limit 120
hermes gateway restart
```

## How It's Triggered

The review agent is NOT label-driven — it has no workflow label. It is triggered by:

1. **`SPAWN: review`** — From `event-processor.py` script output, which processes `check_run.completed#N:success` events
2. **Stalled PR detection** — When a stalled scan finds an `impl/*` PR with CI success but no review agent activity
3. **`delegate_task`** — Spawned by the cron poller with full context

**⚠️ Operator race condition (2026-07-23):** The operator agent may merge implement PRs before the check_run webhook triggers this review agent. Two manifestations:

**A. PR is merged** (state=MERGED): Detectable via `gh pr view <N> --json state --jq '.state'`.
1. Report "PR already merged, review skipped" in the session log
2. **Skip the review and pre-merge checklist** — the merge already happened, these are moot
3. **Do NOT skip post-merge tasks** — GDD update, Feishu notification, and project board sync are about keeping project state consistent regardless of who merged. Run them as usual
4. **⚠️ GDD/PROJECT.md may already be updated.** The merge commit may have included GDD and PROJECT.md changes (the implement agent often bundles them). Always **read the files first** before editing — if they already describe the merged feature, skip the GDD/PROJECT.md update step and move to notification + board sync. The goal is consistency, not redundant edits.

**B. Content on main, but PR still shows OPEN with CONFLICTING merge status**: The operator force-merged the squashed commit directly, bypassing `gh pr merge`. The impl branch (local + remote) and PR all still exist, but `gh pr merge` fails with "Base branch was modified" or "Pull Request has merge conflicts".

Detect this:
```bash
# Pick a file from the PR and check if its commit is on main
gh pr diff <N> --name-only | head -1 | xargs -I{} git log --oneline --all -- "{}" | head -1 | grep -q main
```

If yes (the design doc, e.g., docs/DESIGN/154-*.md, appears in `git log --oneline main`), the content was already force-merged. Handle it:
1. Run tests still (they verify the merged content). If they fail, this is pre-existing — document and skip.
2. **Skip the merge attempt** — `gh pr merge` will fail on conflicts.
3. **Close the PR** with a comment documenting the operator pre-merge:
   ```bash
   gh pr close <N> --comment "PR already merged to main by operator. Content verified: tests pass. Closing."
   ```
4. **Do NOT skip post-merge tasks** (GDD update, Feishu notification, project board sync).
5. **Delete the impl branch** to keep the repo clean:
   ```bash
   git branch -D impl/<branch-name> 2>/dev/null
   git push origin --delete impl/<branch-name> 2>/dev/null || true
   ```

The root fix is in the operator's merge logic (depth-check), not in this agent. See `references/review-agent-race-condition.md`.

**C. Implementation on main, PR OPEN + MERGEABLE (2026-07-29):** A subsequent PR already merged the same implementation files (e.g. PR #321 folded in PR #322's paddle.gd changes). `gh pr diff <N> --name-only` shows only additive files (tests), `gh pr view` says MERGEABLE.

Detect this:
```bash
gh pr diff <N> --name-only  # shows only test/asset files
git diff main impl/<branch> --name-only  # matches gh pr diff
git log --oneline impl/<branch> -- <implementation-file>  # commit not on main
```

Handle it:
1. Run tests on main (baseline) and on PR branch (verify new tests)
2. **Merge normally** via `gh pr merge <N> --squash --delete-branch` — the squash adds test files cleanly
3. **Do NOT close the PR** — unlike variant B, the PR is MERGEABLE and adds value
4. **Do NOT skip post-merge tasks**

See `references/race-condition-variant-c.md` for detection patterns and verification checklist.

## Pre-Merge Checklist (ALL blocking)

Verify these before merging. Any failure = document in PR comment, do NOT merge.

### 0. Verify Implement Agent Skill Integrity (NEW — 2026-07-29)

**Before any review, verify the implement agent skill exists.** If the skill file
was created via `write_file` but never committed to git, it may have been lost from
disk with symlinks silently broken. When `game-implement-agent` is missing, the PR
was generated without TDD constraints — test files, code quality, and merge
prohibition were all absent from the agent's guidance.

```bash
# Check that game-implement-agent skill is loadable
find ~/.hermes/skills -type d -name "game-implement-agent" | head -1

# Check for broken symlinks in skill directories
find ~/.hermes/skills -type l ! -exec test -e {} \; -print | grep implement
```

If the implement agent skill is missing: **do NOT proceed with the review.**
Escalate to user immediately. The PR was generated without skill guidance and
must be re-created with proper TDD constraints after restoring the skill.
See `references/missing-implement-agent-skills-trace.md` for the full trace.

### 1. Verify PR State
```bash
gh pr view <N> --json state,headRefName,baseRefName,mergeable,body,reviews
```
- PR must be OPEN
- Branch must start with `impl/`
- Must reference parent issue: body contains `Parent #N` or `Closes #N`
- Base branch must match the project's default branch (check `game-env/manifest.yaml` for override)
- mergeable must not be CONFLICTING

**⚠️ Pitfall: mergeable returns UNKNOWN on first call.** GitHub may not have computed mergeability yet. `mergeable: UNKNOWN` is GitHub's placeholder, not a real state. Confirm with a second call:
```bash
gh pr view <N> --json mergeable --jq '.mergeable'
```
If it returns `MERGEABLE` or `CONFLICTING`, that's authoritative. If still `UNKNOWN`, wait 2s and retry.

### 2. Run Tests Locally (Unit + Smoke)

Run both the unit test suite and the E2E playthrough smoke test:

```bash
# Unit tests — capture results, avoid pipe deadlock with > redirect
godot --headless --script tests/run_tests.gd > /tmp/godot_unit_output.txt 2>&1
echo "Unit exit: $?"
grep -E '(===|✅|❌|Passed:|Failed:|All tests|Results)' /tmp/godot_unit_output.txt | tail -80

# Smoke test — verifies full playthrough integrity
godot --headless --script tests/smoke_test.gd > /tmp/godot_smoke_output.txt 2>&1
echo "Smoke exit: $?"
grep -E '(❌|Passed:|Failed)' /tmp/godot_smoke_output.txt

# JS/Node projects:
npx vitest run 2>&1 | tail -5
```

**⚠️ Pitfall: `godot` binary not on PATH.** On macOS, Godot installs as an `.app` bundle. If `godot` is not on PATH, use the full path:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --script tests/run_tests.gd
```
Consider adding a symlink for convenience: `sudo ln -s /Applications/Godot.app/Contents/MacOS/Godot /usr/local/bin/godot`

**⚠️ Pitfall: grep pattern width.** The old pattern `(PASS|FAIL|passed|failed|Test|Summary)` misses section headers (`=== MVP Integration Test ===`), individual test markers (`✅`), and section delimiter lines. The wider pattern above captures everything between the test output and the leak warnings emitted at headless-mode exit. Pipe the full output to a file first if you need to search for unexpected errors.

**⚠️ Pitfall: test command timeout via pipe.** A long pipe chain (`godot | grep | tail`) can timeout the terminal call if the Godot process takes more than the default timeout. The pipe's `grep + tail` processing doesn't block indefinitely — the real issue is that the tool waits for the pipeline to produce output. When Godot starts and then outputs nothing matching the grep pattern for a while, the terminal may report timeout on the overall command even though Godot eventually finishes.

**More reliable approach — tee to file first:**
```bash
# Capture ALL output, then grep from file
/Applications/Godot.app/Contents/MacOS/Godot --headless --script tests/run_tests.gd 2>&1 \
  | tee /tmp/godot_test_output.txt \
  | grep -E '(===|✅|❌|Passed:|Failed:|All tests|Results)' \
  | tail -80
```
The `tee` keeps the pipeline flowing and saves the full output to `/tmp/godot_test_output.txt` for post-mortem debugging. If even this times out, separate the capture and grep:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --script tests/run_tests.gd > /tmp/godot_test_output.txt 2>&1
grep -E '(===|✅|❌|Passed:|Failed:|All tests|Results)' /tmp/godot_test_output.txt | tail -80
```
This guarantees no pipe-blocking delays regardless of Godot runtime.

**⚠️ Pitfall: full test suite hangs / exceeds timeout (>180s).** Even with the separated capture-and-grep approach above, the entire `run_tests.gd` suite may time out (>180s) in headless mode. This is a **pre-existing infrastructure issue** — the runner loads many 3D-heavy test suites sequentially, and some suites (integration tests with scene instantiation, 3D node creation) hang when no rendering context is available.

Do NOT spend tool time debugging the full-suite timeout — it predates the PR. Instead, run a **focused test** on only the test files changed by the PR.

**⚠️ Pitfall: writing temp scripts into the repo.** Creating `tests/hermes-verify-<PR>.gd` in the repo's test directory triggers the system's "unverified file write" detection, which produces persistent warnings across subsequent turns even after the file is deleted. Always use `/tmp` via `mktemp` for ad-hoc verification scripts.

**⚠️ Pitfall: RefCounted test files can't run directly.** Many test suites extend `RefCounted` (not `SceneTree`), so `godot --headless --script test_foo.gd` fails or hangs. The test runner instantiates them via `script.new().run()` inside a `SceneTree`. The wrapper must also use `call_deferred` to let autoloads initialize before tests run.

```bash
# Create in /tmp, not the repo — avoids unverified-file warnings
TMPFILE=$(mktemp /tmp/hermes-verify-XXXXXX.gd)
cat > "$TMPFILE" << 'GDS'
extends SceneTree
var _pass: int = 0
var _fail: int = 0
func _init() -> void: call_deferred("_run")
func _run() -> void:
	var t = load("res://tests/<relevant-test>.gd").new()
	t.run()
	_pass = t.passed; _fail = t.failed
	print("\n=== VERIFY: %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
GDS

godot --path <sub-project>/ --headless --script "$TMPFILE" 2>&1 | grep -E '(===|FAIL|passed|failed|SKIP)' | tail -20
rm -f "$TMPFILE"
```

This completes in seconds rather than minutes. If the focused tests pass and CI on the PR branch already passed, the full-suite timeout is not a merge blocker — note it in the review as pre-existing, but proceed.

### ⚠️ Critical: Static load tests miss runtime failures

**Postmortem lesson (2026-07-24):** A unit test checking `ResourceLoader.exists("scene.tscn")` can pass while the scene has:
- CollisionShape3D with `shape = null` => player falls through floor
- Label3D at `position = Vector3(0,0,0)` => text piles up at origin
- Broken sub-resource IDs => parse error at instantiation

**Always run runtime verification** when the PR touches `.tscn` files, collision, or layout. Use `godot --headless --script tests/verify_runtime.gd` to load+instantiate each scene and assert collision shapes exist, Label3D nodes have non-zero positions, and no parse errors occur at instantiation.

See `references/runtime-verification-methodology.md` for the full methodology and reusable GDScript test template.

- **Smoke test is mandatory.** `tests/smoke_test.gd` exists in the repo (96 checks, covers full playthrough). It runs in CI for every `impl/*` PR push and blocks merge on failure. Always run it locally during review.

- **⚠️ Custom resource formats (`.dialogue`, `.story`) in headless mode.** `ResourceLoader.exists()` and `load()` fail for addon-registered resource formats in `--headless --script` mode because the plugin's `ResourceFormatLoader` isn't initialized. If the smoke test shows 12+ `DF:` failures for files that exist on disk with custom extensions, see `references/custom-resource-loader-headless.md` for workarounds. Do NOT block merge on these — verify via the addon's own test suite or `FileAccess.file_exists()` instead.

### Check If Failures Are Pre-Existing

If tests fail during local verification, check if the same failures reproduce on the default branch before escalating:

```bash
# Save the current branch name explicitly — git checkout - is unreliable
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
git stash push -m "pre-existing-check-$(date +%s)" 2>/dev/null || true
git checkout <default-branch>
# Run tests on default branch
godot --headless --script tests/run_tests.gd > /tmp/godot_main_output.txt 2>&1
echo "Main exit: $?"
grep -E '(❌|FAILED|Passed:|Failed:)' /tmp/godot_main_output.txt | tail -10
# Return by EXPLICIT branch name, not git checkout -
git checkout "$CURRENT_BRANCH"
# Only pop if stash exists AND we're back on the right branch
if git stash list | grep -q 'pre-existing-check'; then
  if [ "$(git rev-parse --abbrev-ref HEAD)" = "$CURRENT_BRANCH" ]; then
    git stash pop 2>/dev/null || true
  else
    echo "WARNING: on wrong branch after checkout; stash preserved as pre-existing-check"
  fi
fi
```

**⚠️ Pitfall: `git checkout -` does NOT reliably return to the previous branch.** When switching branches to test on `main`, `git checkout -` can silently stay on `main` instead of returning to the impl branch — especially if the stash was a no-op (no local changes) or if the previous-branch reference was lost during the stash operation. Always save the branch name explicitly with `git rev-parse --abbrev-ref HEAD` before switching, and use that saved name to return.

**⚠️ Pitfall: Stash pop can restore impl-branch file content onto main.** When the impl branch has different file content than main (e.g. `narrative_manager.gd` was modified by the PR), a no-op `git stash` followed by `git checkout main` then `git checkout -` then `git stash pop` can apply the impl-branch file versions onto main's working tree as local modifications. This happens because the stash entry contained a snapshot of the impl branch's working tree (even when no files were "staged"). The explicit branch-name pattern above avoids this by guarding the pop with a branch-name check.

If the same failures appear: **pre-existing infrastructure issue**, not caused by the PR. Document in PR comment.

If failures are NEW (only appear on the PR branch): **blocking**. Document in PR comment, do NOT merge.

- All tests must pass (unit tests + smoke test — 96 checks across scene loading, dialogue integrity, state system, and ending logic)
- If tests fail: check if failures reproduce on the default branch (see above). If they do -> pre-existing. **For feature PRs**: do NOT merge. Document and escalate. **For scene-layout/asset-only PRs**: merge proceeds — the placement introduces no regressions (see merge decision table in Step 6).

### 3. Verify Test Files Updated
```bash
gh pr diff <N> --name-only | grep -i test
```
- At least one test file should be in the diff — **except for bugfix/compile-fix PRs and scene-layout/asset-only PRs**
- **Bugfix/compile-fix PRs** (e.g. title says "Fix N compile-blocking errors", "fix typos", "fix API migration"): no test changes is acceptable. The fix IS making the project compile so existing tests can run. Run the existing tests instead as verification — if they all pass, the fix is validated.
- **Scene layout / asset-only PRs** (diff only contains `.tscn`, `.tres`, `.png`, `.glb`, `.wav`, or other non-script files): no test changes is acceptable. The component scenes being placed were already tested in prior PRs. Verification is via existing test suite + DESIGN doc coordinate inspection. See "Known Pitfalls — PR Type Classification" for identification rules.
- **Feature PRs**: test changes are mandatory. If no test changes: add blocking comment on PR, do NOT merge.

#### ⚠️ Pitfall: Greenfield Projects with No Test Infrastructure

When the project has **zero test infrastructure** (no `tests/` directory, no `tests/smoke_test.gd`, no test runner scripts — `ls tests/ 2>/dev/null` returns empty or the directory doesn't exist):

- The first implement PR in a greenfield project cannot have test changes. This is a project-level gap, not a PR-level gap.
- **Verification substitute**: Run ad-hoc runtime verification (instantiate all new scenes, check CollisionShape3D shapes, confirm no parse errors). Document this as the verification proxy.
- **Do NOT block the merge on missing test files.** Flag the need for a test infrastructure issue as a follow-up, not a blocker.
- Greenfield-first-feature PRs are treated like scene-layout PRs for test-file purposes: verification is via runtime checks, not unit tests.

### 4. Verify Design Docs Updated (if applicable)
```bash
gh pr diff <N> --name-only | grep -E 'docs/(PRD|DESIGN|GAME_DESIGN)'
```
- If the PR diff contains doc changes, review them for accuracy
- **If the diff has NO doc changes**, it may still be valid:

  **Scenario A — DESIGN doc was pre-created** (created in a separate plan-phase PR before the implement PR). Check if the parent issue's DESIGN doc already exists:
  ```bash
  ls docs/DESIGN/<N>-*.md 2>/dev/null
  ```
  If the DESIGN doc exists and accurately describes the feature being implemented, doc changes in the diff are NOT required. The design was already documented; the implement PR only executes it.

  **Scenario B — genuinely missing**. If neither the diff nor any existing DESIGN doc covers the feature's design, this is a blocking gap. Add a blocking comment, do NOT merge.

- **Feature PRs**: missing doc updates (Scenario B) = blocking comment, do NOT merge
- **Bugfix/compile-fix PRs**: no design doc changes are expected — the design hasn't changed, only the implementation was corrected. Skip this check, move to step 5.

### 5. Code Quality Spot-Check
- **GDScript: `get_node_or_null()` patterns** for graceful null handling when autoloads or siblings may not exist in headless tests
- **GDScript: signal lifecycle hygiene** — verify `connect()` in `_ready()` / `body_entered` has a corresponding `disconnect()` in `body_exited` / cleanup to prevent dangling signal connections
- **GDScript: `var` shadowing** — inside a function body, `var x = ...` creates a local variable that shadows the member `x`. It does NOT reset the member. Common in `reset()` functions, where `var target_spawn_point = Vector3.ZERO` silently does nothing while the real member stays unchanged. The correct pattern is `x = ...` (no `var`).
- **GDScript: `Node.get()` only accepts 1 argument.** Unlike `Dictionary.get(key, default)`, calling `gm.get("player_position", null)` on a Node causes a parse error: *"Too many arguments for get() call"*. Always scan for this pattern — it's a silent crash that causes all SceneBase inheritors to fail at load time. The fix: guard with `"key" in node` then access directly: `node.some_property`.
- **GDScript: verify physics completeness.** In `_physics_process(delta)`, check that `velocity.y -= gravity * delta` is present for CharacterBody3D scripts. Missing gravity causes the player to float above the ground — a behavioral omission that unit tests don't catch.
- **GDScript: camera/visual system changes — verify first-person mode is still usable.** If the PR changes camera system or adds a player visual, check that `camera_mode = "first_person"` still works. A third-person camera with a player capsule in front of the camera blocks all scene visibility — this is a silent experience regression.
- **GDScript: scene loading chain integrity.** Check that `change_scene_to_file()` isn't called in the same `_ready()` that just wired up signal connections — the scene replace destroys all connections made in that same `_ready()`. If the scene is a bootstrap (wires signals then loads a game scene), the signals should be wired in the game scene directly, not in the transient bootstrap scene.
- **GDScript/Scene: CollisionShape3D shape must not be null.** When a PR touches `.tscn` files, check every CollisionShape3D node has a `shape = SubResource(...)` assignment. Missing shapes cause the player to fall through floors with zero parse errors — a completely silent failure that static tests never catch. See `game-to-issues` Section 7.2.1 for the full specification table.
- **GDScript/Scene: `.tscn` structural integrity check.** Beyond null shapes, verify these Godot 4.7 format-3 structural rules when a PR adds or modifies `.tscn` files:

  **`load_steps` vs resource count**: `load_steps=N` must equal the total count of `[ext_resource]` + `[sub_resource]` + `[built_in_resource]` blocks. An undercount silently drops sub-resources. Error symptom:
  ```
  ERROR: Condition "!int_resources.has(id)" is true.  (scene/resources/resource_format_text.cpp:114)
  ERROR: Parse Error: Invalid parameter. [Resource file xxx.tscn:LINE]
  ```
  **Fix**: Count all resources and update `load_steps`, or better yet, **omit `load_steps` entirely** — Godot auto-calculates when absent, eliminating this bug class.

  **SubResource ordering**: All `[sub_resource]` blocks must appear **before** the first `[node]` tag. A sub_resource after the first node is silently ignored.

  **SubResource ID format**: Use string-based IDs (e.g. `id="box_floor"`, `id="box_wall"`) in format 3. These are more robust than bare integers and survive re-ordering of sections.

  See the `godot-scene-format` skill for a comprehensive reference on tscn structural verification.

  **Fix-and-continue pattern**: When review finds a fixable bug — `.tscn` structural issues (missing shapes, load_steps, SubResource ordering), or `.gd` test assertion drift (e.g. enum value shifts from added states, stale expected values) — fix it on the PR branch, push, and re-verify rather than rejecting the PR. This is allowed because the review agent is the final quality gate:
  ```bash
  git checkout <impl-branch>
  # fix the file(s)
  git add <fixed-file>
  git commit -m "fix: correct <issue> in <file>"
  git push origin <impl-branch>
  # re-run verification
  ```
  Include the fix in the review summary with explicit documentation of what was wrong and how it was fixed.
- **GDScript/Scene: autoload compatibility check.** When a DESIGN doc specifies autoloads but the PR `project.godot` deviates, verify the excluded scripts are actually autoload-compatible:
  - **`extends RefCounted`** — Cannot be autoloads. Autoloads require `Node`-based scripts. Scripts like `DialogueParser` that extend `RefCounted` should be preloaded, not registered as singletons.
  - **`@onready` vars referencing node paths** — Will fail in autoload context because the node tree doesn't exist. Scripts like `SceneBase` with `@onready var scene_manager: Node = $SceneManager` can't be autoloads — the `$SceneManager` path won't resolve at singleton load time.
  - Document justified deviations in the review comment as intentional divergence from the DESIGN doc.
- **GDScript/Scene: scene UID collision check.** When a PR adds or modifies multiple `.tscn` or `.tres` files, check that each has a **unique** `uid://` identifier. Duplicate UIDs (e.g., two scenes sharing `uid://bn7mpk7g1w8fy`) cause Godot resource cache conflicts at load time. Scan with:
  ```bash
  gh pr diff <N> --name-only | grep -E '\.(tscn|tres)$' | xargs grep -h 'uid=' 2>/dev/null \
    | sed 's/.*uid="\([^"]*\)".*/\1/' | sort | uniq -d
  ```
  If duplicates are found, flag as a non-blocking issue for scaffold/placeholder scenes, but block if the scenes reference different scripts and will be loaded simultaneously.
- **Sub-project scaffold verification.** When the PR creates a new Godot sub-project (a directory with its own `project.godot`, e.g. `rainy-night-prometheus/`), run a dedicated headless validation:
  ```bash
  godot --path <sub-project-dir>/ --headless --quit
  ```
  Run any test scripts inside the sub-project's `tests/` directory too:
  ```bash
  godot --path <sub-project-dir>/ --headless --script <sub-project-dir>/tests/verify_scaffold.gd
  ```
  Verify that all symlinks are tracked with `120000` mode:
  ```bash
  git ls-files -s <sub-project-dir>/gdscripts/
  ```
- GDScript: class_name declarations, static typing, signal patterns, no hardcoded paths
- JS: no console.log, proper error handling, no dead code
- Check for any obvious anti-patterns or security issues

### 5. Submit PR Review Comment

Before merging, leave a review comment summarizing findings:

```bash
gh pr review <N> --approve --body "## Review Summary

### Checks
- Tests: ✅ passed
- Test files: ✅ updated (or N/A for bugfix)
- Design docs: ✅ verified (or N/A for bugfix)
- Code quality: ✅ no issues

### Verdict
Approved. Merging.
```"
```

- All checks pass → APPROVE with summary, then merge

  **⚠️ Pitfall: cannot approve own PR.** When the agent's `GH_TOKEN` belongs to the same GitHub user who authored the PR (common in single-dev repos), `gh pr review --approve` fails with `GraphQL: Review Can not approve your own pull request`. This is a hard GitHub constraint, not a config issue. Do NOT silently skip — leave a `--comment` review with the full summary so the PR has a review trail:

  ```bash
  gh pr review <N> --comment --body "## Review Summary

  ### Checks
  - Tests: ✅ passed
  - Test files: ✅ updated
  - Design docs: ✅ verified
  - Code quality: ✅ no issues

  ### Verdict
  All checks pass. Merging."
  ```

Then proceed directly to the merge step. The review comment on the PR + the session log together serve as the review record.
- Issues found → REQUEST_CHANGES with specific items, do NOT merge

### 6. Merge Decision

| Condition | Action |
|-----------|--------|
| All checks pass | Merge via gh pr merge N --squash --delete-branch |
| Pre-existing failures on ANY PR type | Add PR comment documenting findings. Do NOT merge. Escalate. All pre-existing failures must be fixed before merge - no exceptions. |
| CI failure (should not happen - review is only called on success) | Do NOT merge. Report to user. |
| PR merge conflicts | Report. Skip. |

Policy rationale: Pre-existing failures on the default branch mean the project cannot pass its own tests. Allowing a merge with the main branch red compounds the problem. The only way to heal is to fix the failures on main first, then merge the PR. See AGENTS.md for the formal rule.

### ⚠️ Block Is Permanent Until Main Is Green

When the review agent blocks a PR due to pre-existing failures on main, **that block is STICKY.** The review agent will NOT be re-spawned on this PR (the event-processor enforces this — see `event-processor.py` block gate).

**The only path to unblock:** The fix issue merges → main tests pass → the stalled scan detects main is green → removes `status/blocked` from the PR + parent issue → runs `gh pr update-branch` to sync the impl branch with main → CI re-runs → `check_run.completed` spawns a fresh review agent.

**The review agent must NEVER change its mind on a blocked PR.** There is no "delegator override." If a delegator directs you to "proceed if clean," that directive itself is the bug — the block is not about the PR's cleanliness, it's about the main branch being broken. A green main is the only valid override.

See `references/pre-existing-failure-block-bypass-trace.md` for the 2026-07-30 failure trace that motivated this rule (2 PRs merged with `status/blocked` still on, 5 pre-existing failures unfixed).

### Block Follow-Through: Creating a Fix Issue

After blocking a PR, the review agent must create a **fix issue** so the pre-existing failures have an owner and enter the normal pipeline. This prevents the block from becoming permanent deadlock — the fix issue goes through research → plan → implement → merge, main turns green, and blocked PRs auto-unblock.

#### Fix Issue Format

```
Title: Fix {N} pre-existing test failures on main [fset:{8-char-hex}]
Labels: bug, workflow/available, priority/high
Body:
  **Blocked PRs:** #{PR1}, #{PR2}, ...
  **Pre-existing failures:**
  | Test | Suite | Error |
  |------|-------|-------|
  | TC6.1 | GameStateMachine | current_state == SCORED... |
  ...
```

#### Deduplication: Failure-Set Hash

Multiple review agents may block different PRs for overlapping sets of pre-existing failures. To prevent duplicate fix issues, each fix issue carries a **failure-set hash** (fset) in its title — a unique fingerprint of the exact failure names being addressed.

**Computing the hash:**
```bash
# Sort failure names alphabetically, join with pipe, compute md5 prefix
FAILURES="TC6.1|TC8.1|TC8.2|TC11|TC16.1"
FSET_HASH=$(echo -n "$FAILURES" | md5 | cut -c1-8)
# → "a3f8c2d1"
```

**Dedup flow before creating a fix issue:**

```
1. Collect failure names → sorted set S
2. Compute fset_hash = md5("name1|name2|...")[:8]
3. Search: gh issue list --search "[fset:{fset_hash}] in:title" --state open
4. If found → link blocked PR to existing fix issue, do NOT create new
   gh issue comment <existing> --body "Also blocks PR #{N}"
5. If not found → check existing fix issues for subset coverage:
   for each open issue with title "Fix * pre-existing*":
     parse body table → existing failure names E
     if S ⊆ E → this fix issue already covers our failures → link, skip
     if E ⊂ S → update existing issue to include new failures + new hash
   If no match → create new fix issue
```

**Full block checklist (in order):**
1. Run full review (tests, code quality, design docs)
2. If pre-existing failures confirmed on main:
   a. Set `status/blocked` on PR AND parent issue via REST API
   b. Leave blocking PR comment with failure table
   c. Compute fset_hash + search for existing fix issue
   d. If no existing fix issue covers these failures → create fix issue
   e. Link this PR's comment: "Blocked → tracked by #<fix-issue>"
   f. Post Feishu: `❌ #N → blocked: <N> pre-existing failures (fix: #<FIX>)`
   g. Remove event from pending file
3. Do NOT merge. Do NOT re-evaluate.

### ⚠️ Pitfall: Self-approval Constraint

See the pitfall under **Step 5: Submit PR Review Comment** above for the `--comment` workaround when `GH_TOKEN` matches the PR author.

### Merge Pitfall: Stash First

```bash
# gh pr merge tries to check out the target branch locally.
# If there are uncommitted changes, it fails.
git stash
gh pr merge <N> --squash --delete-branch
git stash pop 2>/dev/null
```

### ⚠️ Pitfall: Verify Merge Success

`gh pr merge` succeeds silently — it does not print a confirmation message. Always verify the merge actually happened before proceeding to the GDD update:

```bash
gh pr view <N> --json state --jq '.state'
```

Expected output: `MERGED`. If it returns `OPEN`, the merge silently failed (e.g. branch protection rules, CI still running).

### ⚠️ Pitfall: Stash Pop Can Restore Wrong Branch

The `git stash pop` after merge restores whatever branch you were on before `git stash`. If you were on an `impl/*` branch (which `gh pr merge --delete-branch` just deleted), `git stash pop` can restore a **different** branch's working tree — especially if the stash was created on top of an unrelated branch's modifications.

After the stash pop, ALWAYS verify which branch you're on before making GDD edits:

```bash
git branch --show-current
git pull origin $(git branch --show-current)
```

If you're on the wrong branch, `git checkout <default-branch>` and cherry-pick or re-apply the GDD changes.

**⚠️ Recovery: `git pull` blocked by stash-pop pollution.** When the stash pop restores the impl branch's working tree (modified + untracked files), `git pull` fails with "local changes would be overwritten by merge". The impl branch's files now conflict with the just-merged content on main. Fix:

```bash
git reset --hard origin/main
```

This discards the stash-pop pollution and aligns the working tree with the merged state. No `git checkout` or cherry-pick is needed — the merge already landed on origin/main. After reset, proceed with GDD edits as normal.

### ⚠️ Pitfall: gh pr diff -- <file> syntax limitation

`gh pr diff <N> --name-only` lists changed files (single arg). But `gh pr diff <N> -- <filepath>` does NOT work — it errors with `accepts at most 1 arg(s)`. To inspect a specific file's diff, either:
- Pipe the full diff to `head` and scan for the file
- Use `git diff` on the fetched PR branch after checkout

## Post-Merge: GDD Update

After the PR merges, update the Game Design Document (GDD) in `docs/GAME_DESIGN/`. The review agent is the ONLY agent that updates the GDD — it happens AFTER merge, not before.

### Which GDD Files to Update

Read the DESIGN doc (`docs/DESIGN/<N>-*.md`) for the specific feature. It mentions which GDD files need updating. Common targets:

| GDD File | Covers | Check When |
|----------|--------|------------|
| `01-OVERVIEW.md` | Game overview, elevator pitch | Any major feature |
| `02-WORKFLOW.md` | Agent workflow — development pipeline | Workflow or pipeline changes |
| `03-GODOT-SETUP.md` | Godot engine config, scene management, code style | Engine config or project setup changes |
| `04-RENDERING.md` | Visual rendering — shaders, Label3D, pixel fonts | Visual changes |
| `05-DIALOGUE.md` | Dialogue engine — data model, branching, runtime | Dialogue, NPC features |
| `06-NARRATIVE.md` | Narrative architecture — scene sequence, echoes, endings | Story scenes, NPC interactions |
| `07-AUDIO.md` | Audio system — ambient loops, state modulation, transitions | Audio changes |
| `08-PLAYER-CONTROLLER.md` | Player controller — WASD, mouse look, E-key, persistence | Player movement or input changes |
| `09-TESTING.md` | Testing system — headless runner, integration test suite | Test infrastructure changes |
| `INDEX.md` | Table of contents | Any GDD file change |

**Decision: patch existing vs. create new**:
- **GDD file already exists** for this feature (e.g. `08-PLAYER-CONTROLLER.md` from a prior implement PR that built the base system): read the existing file, then use `patch` to add new sections describing what the current PR adds. Do NOT overwrite the whole file.
- **GDD file does not exist yet**: create a new numbered file (see below).

**New section needed?** If the feature doesn't cleanly fit any existing file above (e.g. a player controller, an inventory system, a map system), create a new numbered GDD file. Determine the next available number (read INDEX.md's table, find the highest `NN-` prefix, add 1). Name it `NN-FEATURE-NAME.md` in `SCREAMING-KEBAB-CASE` and add a row to INDEX.md's table. Match the existing table's pipe formatting exactly (`| [NN-NAME](NN-NAME.md) | description |`).

### GDD Writing Style

- **Narrative, not code-dump** — Describe the system at the design level, not the implementation level
- **Tables for parameters** — Constants, limits, ranges
- **Code blocks only for definitions** — Signal signatures, enum values, method signatures
- **Paragraphs for intent** — Explain WHY the system works this way
- **Human-readable, LLM-searchable** — Structure for both readers

### GDD Commit Convention

```bash
git add docs/GAME_DESIGN/
git commit -m "docs: update GDD for <feature name> (#N)"
git push origin <default-branch>
```

**⚠️ Pitfall: GDD update branches from master.** The GDD update commit is based on the default branch (which now includes the merged PR). This is safe because the review agent merges first, THEN commits the GDD update on top.

**⚠️ Pitfall: GDD-only commits can accidentally revert** the implement PR's code if the review agent does the merge within the same script session without updating the working tree. Fix:
```bash
# After merging, update the working tree to match origin
git checkout <default-branch>
git pull origin <default-branch>
# NOW make GDD changes
```

### ⚠️ GDD Pipe-Table Corruption with `patch`

The `patch` tool's fuzzy matching can produce `|||` (triple pipes) instead of `||` (double pipes) when editing GDD files that contain markdown pipe tables. This affects:

- **INDEX.md** — When adding a new row to the table of contents, use `write_file` to rewrite the entire file (INDEX.md is small, ~25 lines). When editing an existing row (e.g. updating a description), `patch` works but ALWAYS verify afterward — the fuzzy matcher can add an extra `|` prefix to the row. After patching INDEX.md, run:
  ```bash
  grep -n '|||' docs/GAME_DESIGN/INDEX.md
  ```
  If triple-pipes appear, fix with a second `patch` replacing `|||` with `||`.
- **Any GDD file with pipe tables** — When adding a new section that contains a pipe table (e.g. adding a parameter table to `08-PLAYER-CONTROLLER.md`), fuzzy matching can corrupt existing table rows by adding an extra `|`. After using `patch`, ALWAYS verify GDD tables by scanning for `|||` in the edited file:

```bash
grep -n '|||' docs/GAME_DESIGN/*.md
```

If triple-pipes appear, fix with a second `patch` that replaces `|||` with `||` for the affected rows.

## Post-Merge: PROJECT.md Update

After GDD update, also update `docs/PROJECT.md` — the living project overview document readable by both humans and agents. This is a **hierarchical project document** with four layers:

### L1: Project Status

Update the status table at the top:

```markdown
## 项目状态

| 指标 | 状态 |
|------|:----:|
| 编译 | ✅ 通过 |
| 可运行 | ✅ 能启动 |
| 可玩 | ⚠️ 有标题画面和移动控制 |
| 最近构建 | `{date}` |
| 开放 Issues | {N} |
```

### L2: Module Map

If the PR added a new module/script, add a row to the module map table:

```markdown
| 模块 | 文件 | 状态 | 设计文档 |
|------|------|:----:|:--------:|
| NewSystem | `gdscripts/new_system.gd` | ✅ | GDD |
```

### L3: Features

If the PR implemented a new feature, add a row to the features table:

```markdown
| # | 功能 | 状态 | 文档 |
|:-:|------|:----:|:----:|
| 12 | 新功能 | ✅ 已合并 | GDD |
```

### L4: Known Issues

If the PR fixed or introduced a known issue, update the known issues table.

### Commit Convention

```bash
git add docs/PROJECT.md
git commit -m "docs: update PROJECT.md for <feature name> (#N)"
git push origin <default-branch>
```

**⚠️ Pitfall:** Same as GDD — always `git pull origin <default-branch>` before editing PROJECT.md to avoid reverting content from parallel PRs.

**⚠️ Pitfall: PROJECT.md pipe-table corruption.** The PROJECT.md module map and features tables use markdown pipe tables. Using `patch` to add rows or edit content can produce `|||` (triple pipes) instead of `||` (double pipes). Same root cause as the GDD pipe-table corruption. After editing PROJECT.md, always verify:
```bash
grep -n '|||' docs/PROJECT.md
```
If triple-pipes appear, fix with `patch` replacing `|||` with `||` for the affected rows. Consider using `write_file` to rewrite PROJECT.md entirely if the changes touch multiple table rows — the file is small (~100 lines) and `write_file` avoids pipe-table corruption entirely.

## Notification

After merging and GDD update, POST a Feishu notification:

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"msg_type":"text","content":{"text":"✅ #N → <feature name> merged → 🚀"}}' \
  https://open.feishu.cn/open-apis/bot/v2/hook/76101281-b359-49ab-ae2f-fc486bf65958
```

Format: One line, emoji prefix, no explanations.

## Post-Merge: Issue Label Cleanup

After merging, remove stale workflow labels from the parent issue and PR that no longer apply. Common stale labels to check:

- `workflow/self-correct` — remove (the self-correct cycle has completed with merge)
- `status/blocked` — remove (the block has been resolved, either by fix or delegator override)
- `status/review` — remove if present (review is complete)

```bash
# Remove individual labels via REST API
gh api repos/<owner>/<repo>/issues/<ISSUE_NUM>/labels/workflow%2Fself-correct -X DELETE
gh api repos/<owner>/<repo>/issues/<ISSUE_NUM>/labels/status%2Fblocked -X DELETE

# Verify remaining labels
gh issue view <N> --json labels --jq '.labels[].name'
```

**Do NOT remove `status/done`** — that label should remain (or be added if missing) to indicate the issue is complete.

## Project Board Sync

After merging and GDD update, sync the GitHub Project board to reflect the completed state:

### 1. Check if the Issue Exists on the Board

**⚠️ Pitfall: project number ≠ GraphQL node ID.** `gh project list` returns a project number (e.g., `5`), but GraphQL mutations require the project's opaque global node ID (e.g., `PVT_kwHOABFv7s4Bd7mL`). Resolve it with:

```bash
gh api graphql -f query='
  query($owner:String!,$number:Int!) {
    user(login:$owner) {
      projectV2(number:$number) { id title }
    }
  }' -f owner="devvi" -F number=5 --jq '.data.user.projectV2.id'
```

See `references/project-board-graphql-id-discovery.md` for the full discovery workflow.

```bash
gh project item-list <project-number> --owner "@me" --format json \
  | python3 -c "import json,sys; data=json.load(sys.stdin); [print(f'Item: {i[\"id\"]}') for i in data['items'] if i.get('content',{}).get('number')==<N>]"
```
If no output, the issue is not on the board — add it first:

```bash
ISSUE_NODE=$(gh issue view <N> --json id --jq '.id')
gh api graphql -f query='
  mutation($project:ID!,$content:ID!) {
    addProjectV2ItemById(input:{projectId:$project,contentId:$content}) { item { id } }
  }' -f project="<project-id>" -f content="$ISSUE_NODE"
```

### 2. Set Status to "Done"

**⚠️ Pitfall: field name is not always `Status`.** Project boards created by different templates use different field names: `Status`, `Stage`, `State`, or custom labels. Always discover the field name dynamically:

```bash
# List all single-select fields and their names
gh project field-list <project-number> --owner "@me" --format json \
  | python3 -c "import json,sys; data=json.load(sys.stdin); [print(f\"{f['name']}: {f['id']}\") for f in data['fields'] if f.get('type')=='ProjectV2SingleSelectField']"
```

Then use the discovered field name in subsequent commands. The `Stage` name in the examples below is a placeholder — substitute the actual field name.

```bash
# First, find the field options (replace 'Status' with the discovered name):
gh project field-list <project-number> --owner "@me" --format json \
  | python3 -c "import json,sys; data=json.load(sys.stdin); field=next(f for f in data['fields'] if f['name']=='Status'); [print(f'{o[\"name\"]}: {o[\"id\"]}') for o in field['options']]"

# Then set it to "Done" (replace 'Status' with the discovered field name):
gh project item-edit --project-id "<project-id>" \
  --id "<item-id>" \
  --field Status --single-select "Done"
```

**⚠️ Pitfall: `gh project item-edit --field Status --single-select "Done"` may fail** if the project uses a GraphQL-based field ID. Fall back to raw GraphQL:
```bash
ITEM_NODE=$(gh project item-list <number> --owner "@me" --format json \
  | python3 -c "import json,sys; data=json.load(sys.stdin); items=[i for i in data['items'] if i.get('content',{}).get('number')==<N>]; print(items[0]['id'] if items else '')")
gh api graphql -f query='
  mutation($project:ID!,$item:ID!,$field:ID!,$value:String!) {
    updateProjectV2ItemFieldValue(input:{
      projectId:$project,itemId:$item,fieldId:$field,
      value:{singleSelectOptionId:$value}
    }) { projectV2Item { id } }
  }' \
  -f project="<project-id>" \
  -f item="$ITEM_NODE" \
  -f field="<stage-field-id>" \
  -f value="<done-option-id>"
```

### 3. Set Progress to 100% (if the Progress field exists)

**⚠️ Pitfall: Progress is a Float field, not String.** The GraphQL mutation for a number field rejects string values like `"100"` with *"Could not coerce value to Float"*. Use `-F` (raw field, no quotes) instead of `-f`:

```bash
# ❌ Wrong — string coercion error:
gh api graphql -f value="100" ...

# ✅ Correct — raw float:
gh api graphql -F value=100 ...
```

Omit this step if the project board does not have a Progress or percentage field.

## Known Pitfalls

### PR Type Classification (Feature vs Bugfix vs Scene Layout / Asset-Only)

Not all `impl/*` PRs are feature PRs. Three categories with different expectations:

**Bugfix/compile-fix PRs** (e.g. "Fix N compile-blocking errors", "Fix Godot 3→4 API migration"):
- Test files in diff: not required — the existing tests are the verification
- Design doc / GDD updates: not required — the design hasn't changed
- GDD update post-merge: skip — compile fixes don't change design
- **How to identify**: PR title/branch/DESIGN doc keywords like "Fix", "compile", "migration", "error", "broken". Parent issue `bug` label.

**Scene layout / asset-only PRs** (e.g. "Add 4 component instances to street.tscn at authored coordinates") — PRs containing **only** `.tscn`, `.tres`, `.png`, `.glb`, `.wav`, or other non-script asset files, with zero GDScript/JS changes:
- Test files in diff: **not required** — the component scenes being placed were already tested in prior PRs (e.g. `test_text_component_library.gd` covers the component behavior). Coordinates and positions are verified by the editor / DESIGN doc inspection.
- The PR's test verification is the existing test suite — if all existing tests pass (or only pre-existing failures), the placement does not break anything.
- Design doc / DESIGN doc: **still required** — the DESIGN doc must pre-exist and list the exact coordinates/parameters being authored. The implement PR is a config-placement exercise, not a design decision.
- GDD update post-merge: depends on significance — adding instances of existing components to a scene usually does not warrant GDD changes. Only create GDD entries if the placement introduces a new gameplay-affecting system.
- **How to identify**: `gh pr diff <N> --name-only` returns only asset/scene files. No `.gd`, `.js`, `.ts`, `.py` files in the diff. The PR title often says "place", "add", "position", "layout", "arrange".

**Feature PRs** (anything not covered above):
- Test files in diff: mandatory — at least one test file must change
- Design doc / GDD updates: mandatory unless DESIGN doc was pre-created (Scenario A)
- GDD update post-merge: required after merge

See `references/compile-fix-pr-example.md` for a concrete walkthrough of a compile-fix PR review (PR #133, Issue #130).

### Pre-Existing CI Failures

If CI was configured with `continue-on-error: true`, plan-phase tests may have bugs that never ran. The review agent's test run may reveal these. They are NOT the implement PR's fault. Document and escalate — do NOT merge around them.

### ⚠️ Pre-Existing Failures from a DIFFERENT Sub-Project

**Multi-project repos (2026-07-25):** The repo may contain multiple Godot sub-projects
(e.g. `urban-night-walker/` and `rainy-night-prometheus/`). When a PR for one sub-project
causes CI failures that originate ENTIRELY from another sub-project's test suite, the
standard "do NOT merge" rule should be reconsidered.

**Identification:**
```bash
# Check which sub-project's tests failed
gh run view <RUN_ID> --log 2>&1 | grep -E "FAILED|SCRIPT ERROR" | head -10
```

**Exception rule:** If ALL failures are:
1. Pre-existing (reproduce on `main` with identical errors)
2. AND originate from a different sub-project's test suite (the PR being reviewed
   neither creates nor modifies the failing test files)
3. AND the PR's own sub-project validates cleanly (`godot --path <sub-project> --headless --quit`)

→ Merge may proceed with documented exception in the review comment.
Post a Feishu notification with `⚠️` prefix.

**Rationale:** Blocking an entire project's pipeline because of an unrelated sub-project's
broken tests creates deadlock — neither project can merge until the other's tests are fixed,
but neither owns the other's tests. Sub-project isolation + clean-scaffold validation
provides sufficient safety.

### Pre-Existing Failure — Cron-Mode Escalation

When the review agent runs in cron/headless mode (no user present to receive an in-chat escalation), implement the full escalation procedure after detecting pre-existing failures:

1. **Add a detailed review comment** on the PR documenting:
   - Which test suites passed/failed
   - Whether failures are confirmed pre-existing on `main`
   - The PR's own new tests pass (if any)
   - Code quality verdict
   - Explicit statement: "Pre-existing failures block merge for feature PRs — do NOT merge."

2. **Set `status/blocked` on the PR AND the parent issue** — use REST API (no `read:org` scope needed):
   ```bash
   gh api repos/<owner>/<repo>/issues/<PR_NUM>/labels -X POST --input - <<<'{"labels":["status/blocked"]}'
   gh api repos/<owner>/<repo>/issues/<ISSUE_NUM>/labels -X POST --input - <<<'{"labels":["status/blocked"]}'
   ```
   The default-branch label (`status/blocked`) keeps the label discoverable even if the PR branch is deleted. Labeling the parent issue makes it visible in issue-tracker views.

3. **Post Feishu notification** with the blocked status, including the pre-existing failure count and that the PR's own code is clean:
   ```bash
   curl -X POST -H "Content-Type: application/json" \
     -d '{"msg_type":"text","content":{"text":"❌ #N → blocked: <N> pre-existing failures (PR code clean)"}}' \
     https://open.feishu.cn/open-apis/bot/v2/hook/76101281-b359-49ab-ae2f-fc486bf65958
   ```

4. **Remove the event from the pending file** — call `python3` inline to delete the specific `_key` from `~/.hermes/workflow-pending.json` so the same event is not re-processed on the next tick:
   ```bash
   python3 -c "
   import json
   with open('/Users/devvi/.hermes/workflow-pending.json') as f:
       data = json.load(f)
   data['events'] = [e for e in data['events'] if e['_key'] not in {'<key1>', '<key2>'}]
   data['processed_at'] = '<timestamp>'
   with open('/Users/devvi/.hermes/workflow-pending.json', 'w') as f:
       json.dump(data, f, indent=2)
   "
   ```

5. **Do NOT close the issue** — the parent issue stays open so the blocked status is visible and a future fix-issue can unblock it.

See `dev-workflow-dispatcher` skill's "Pre-Spawn Validation Checklist" for the companion pattern: when a blocked issue's pre-existing failures are fixed, the stalled-phase-detection scan re-discovers it and spawns the next phase agent.

**⚠️ Pitfall: CI exit code captured from pipe, not Godot.** A common bug in GitHub Actions workflows:

```yaml
- name: Run GDScript tests
  run: |
    godot --headless --script tests/run_tests.gd 2>&1 | tee test-output.log
    echo "exit_code=$?" >> $GITHUB_OUTPUT   # ❌ Captures tee's exit, not godot's!
```

`$?` after a pipe captures the **last** command (`tee`), which always exits 0. Use `${PIPESTATUS[0]}` instead to capture the first command in the pipeline:

```yaml
- name: Run GDScript tests
  run: |
    godot --headless --script tests/run_tests.gd 2>&1 | tee test-output.log
    echo "exit_code=${PIPESTATUS[0]}" >> $GITHUB_OUTPUT   # ✅ Correct
```

This is a silent-failure mode: test failures are logged but never block the workflow. Always check the CI workflow file for this pattern when CI shows success but local tests fail. See `references/ci-exit-code-capture-bug.md`.

### ⚠️ Pitfall: CI SKIP-As-Pass — gate passes when tests never ran (2026-07-29)

A CI step that checks for a file and SKIPs when not found, but sets `exit_code=0`,
creates a **false-pass gate**: the test gate is green but zero tests executed.

```yaml
# ❌ False-pass pattern:
- name: Run GDScript tests
  run: |
    if [ -f tests/run_tests.gd ]; then
      godot --headless --script tests/run_tests.gd
      echo "exit_code=$?" >> $GITHUB_OUTPUT
    else
      echo "SKIP: tests/run_tests.gd not found"
      echo "exit_code=0" >> $GITHUB_OUTPUT   # ← Gate passes!
    fi
```

**Real case (PR #315, 2026-07-29):** CI searched `tests/run_tests.gd` at repo root,
found nothing, output `SKIP`, set `exit_code=0`. The test gate passed. But the actual
tests were at `mini-pong/tests/run_tests.gd` — never executed. **43 tests existed on
disk and passed locally, but CI reported nothing.**

**How to detect during review:**

1. **Read the CI log** — look for `SKIP:` lines in the test step output:
   ```bash
   gh run view <RUN_ID> --log 2>&1 | grep -i "SKIP"
   ```

2. **Check if test files exist in sub-project directories:**
   ```bash
   find . -name "run_tests.gd" -not -path "./tests/*"
   ```

3. **If the CI skipped but tests exist in a sub-project**, the sub-project needs
   its own test step with `--path`:
   ```yaml
   - name: Run Mini Pong tests
     run: |
       if [ -f mini-pong/tests/run_tests.gd ]; then
         godot --path mini-pong/ --headless --script tests/run_tests.gd
         echo "exit_code=$?" >> $GITHUB_OUTPUT
       fi
   ```

4. **Run the sub-project tests locally** as the review agent:
   ```bash
   godot --path <sub-project>/ --headless --script tests/run_tests.gd
   ```

**Merge decision:** If tests exist in a sub-project but CI didn't run them, and
they pass locally → pre-existing CI infrastructure gap, NOT the PR's fault. Merge
proceeds, but flag the CI gap as a follow-up issue.

### ⚠️ Pitfall: CI Timeout from Per-File `--check-only` Loops (2026-07-29)

A compile-check CI step that loops over `.gd` files with individual `godot --check-only`
calls starts a full Godot process per file. With 10+ files and ~15-30s per launch,
the total exceeds `timeout-minutes: 10` and the CI is **cancelled** — not failed,
just killed. The test gate passes (no non-zero exit code was reached).

**Real case (PR #321, 2026-07-29):** The Mini Pong pre-flight compile check used:
```bash
for script in $(find mini-pong/gdscripts/ mini-pong/tests/ -name '*.gd'); do
  godot --path mini-pong/ --headless --check-only "$script"
done
```
12 files × ~25s each = ~5 minutes worst-case... but GitHub Actions runners vary
and the step was cancelled at ~10 minutes. The `review` workflow showed red despite
all tests passing locally.

**Fix: single-process compile check script.** Use `godot --headless --script` to
load all scripts in one Godot process (~0.3s total):
```gdscript
# tests/check_compile.gd — loads all .gd/.gdshader via DirAccess
extends SceneTree
func _init() -> void:
    for d in ["res://gdscripts/", "res://tests/"]:
        var dir = DirAccess.open(d)
        dir.list_dir_begin()
        var fname = dir.get_next()
        while fname != "":
            if fname.ends_with(".gd") or fname.ends_with(".gdshader"):
                var res = load(d + fname)
                if res == null: _fail += 1
            fname = dir.get_next()
    quit(1 if _fail > 0 else 0)
```
CI invocation: `godot --path <sub-project>/ --headless --script tests/check_compile.gd`
Use `DirAccess` to auto-discover files — no hardcoded file list to maintain.

**Detection:** If a CI run shows `cancelled` status (not `failure`) and the last
step output is "The operation was canceled", check for per-file loops that
accumulate time. Single-shot `--script` or `--quit` calls are O(1) launches.

### ⚠️ Pitfall: PR content doesn't match issue specification — content validation

The review agent must validate that the PR's actual deliverable matches what the parent issue requested. CI passing does NOT mean the PR is correct — PR #300 (impl/286-scaffold-ci) had all CI pass but produced a Vite web project + Snake game instead of Godot 4.7 Mini Pong.

**Pre-review content validation:**

```bash
PARENT=$(gh pr view <N> --json body --jq '.body' | grep -oP '(?<=Parent )#\d+|(?<=parent )#\d+|(?<=Closes )#\d+' | grep -oP '\d+')
ISSUE_TITLE=$(gh issue view $PARENT --json title --jq '.title')
PR_FILES=$(gh pr diff <N> --name-only)
```

**Block merge signals:**
| Signal | Example (PR #300) |
|--------|-------------------|
| Wrong tech stack | Issue: Godot → PR adds package.json, vite |
| Wrong directory | Issue: mini-pong/ → PR adds to root |
| Scope creep | Issue: scaffold → PR adds Snake game |
| Unauthorized CI changes | PR rewrites deploy.yml from Godot export to Vite build |
| Unjustified deps | PR adds 1100-line package-lock.json for a scaffold |

When two implement PRs merge close together, their GDD updates can conflict. Each review agent should read the current GDD before writing, not the version at the time their PR was created. Use `git pull origin <default-branch>` before editing GDD files.

### Post-Merge Working Tree

After `gh pr merge --squash --delete-branch`, the local git state has:
- Default branch checked out
- But the working tree still shows the old content until `git pull`

Always do `git pull origin <default-branch>` before editing GDD files.

### ⚠️ Pitfall: Cross-Issue Enum Shift Breaks Test Assertions (2026-07-30)

When a PR for issue #N includes changes from a dependent issue #N+1 (e.g., PR #295 adding PAUSED state from #296), enum value insertions shift existing enum indices — SCORED 3→4, GAME_OVER 4→5. Tests that assert `State.SCORED == 3` break silently on the PR branch but pass on main (where the new state doesn't exist yet).

**Detection:** Failures in TC2.x-style enum-value assertion tests that don't appear on main.

**Fix:** Update test assertion values to match the new enum ordering. Add a test for the new enum member. Push the fix as part of the review (see Fix-and-continue pattern in §5).

## Environment

- `GITHUB_TOKEN` — GitHub PAT with repo scope (in `~/.hermes/.env`)
- `GH_TOKEN` — same token (gh CLI fallback)
- Default branch: check `game-env/manifest.yaml` for override (common: `main`, `master`)
