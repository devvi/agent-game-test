---
name: game-plan-agent
description: "Plan phase agent for the game dev workflow. Converts PRD → DESIGN doc with architecture decisions, data flow, key constants, and test case descriptions. Creates branch, commits, PRs, and auto-merges."
---

# Game Plan Agent

## 🛠️ WORKTREE 工作流（强制, 2026-08-13 起 — 多 agent 隔离红线）

> **必须在独立 worktree 中开发, 禁止在主工作区操作。** 根因: 多 agent 并发共用
> 主工作区导致 PR 互相污染 (#440 混入 #387 文件等)。方案见 docs/PLAN-worktree-isolation.md。

```bash
# 1. 创建 worktree (基于最新 origin/main, 幂等)
WT=$(./scripts/worktree-setup.sh plan <N> <slug>)

# 2. 所有文件操作在 worktree 内 (绝对路径)
#    写 DESIGN:  $WT/docs/DESIGN/<N>-<slug>.md
#    写 TASKS:   $WT/docs/TASKS/<N>-<slug>.md

# 3. 完成 → 提交 (脚本自动: 提交前 merge main + 冲突分级 + 白名单 add)
./scripts/worktree-commit.sh <N> "docs(plan): add DESIGN doc for #<N>" \
  "$WT/docs/DESIGN/<N>-<slug>.md" "$WT/docs/TASKS/<N>-<slug>.md"

# 4. PR 创建 (worktree 内)
cd "$WT" && gh pr create --base main --head plan/<N>-<slug> --title "docs(plan): DESIGN for #<N>" --body "parent #<N>"

# 5. 清理
git worktree remove "$WT" --force
```

**红线:**
- ❌ 绝不 `git add .` — worktree-commit.sh 强制白名单
- ❌ 绝不 `git stash` — worktree 隔离后不需要 (stash 是污染时代的遗产)
- ✅ merge 冲突: 脚本自动尝试合并, 失败则 abort + 报告, 不硬解

> Triggered by `workflow/plan` label advancement (from cron poller or operator agent). Converts the Research PRD into a detailed DESIGN document, optionally a TASKS document, then branches, commits, pushes, creates a PR, and auto-merges.

**This skill provides the standard prompt template and context structure for spawning a plan agent via `delegate_task`.**

## When to Use

- The cron poller receives a `SPAWN: plan,issue=N` or `P2: issues.labeled,issue=N,label=workflow/plan` instruction
- The issue label `workflow/plan` is current on GitHub
- The research PR (branch prefix `research/`) is **merged** — verify before spawning
- No plan branch or PR already exists for this issue (check with `gh pr list --state all --search "plan/<N> in:headRefName"`)
- For `depth/deep`: spawn via `delegate_task` with rich context
- For `depth/light` or `depth/standard`: the operator agent handles the plan phase directly without a sub-agent

## Pre-Spawn Validation Checklist

Before spawning, verify:

1. **Label current** — `gh issue view <N> --json labels` — must show `workflow/plan`
2. **Research PR merged** — `gh pr list --state all --json headRefName,state --search "research/<N> in:headRefName"` — must have a MERGED PR
3. **No plan PR/duplicate** — `gh pr list --state all --json headRefName,state --search "plan/<N> in:headRefName"` — must be empty (no existing plan PR)
4. **PRD exists** — confirm `docs/PRD/<N>-*.md` exists and is non-empty
   > **⚠️ PRD may live under a different issue number.** When the implementation issue (N) follows a separate research issue (R), the PRD file lives under the **research** issue's number: `docs/PRD/<R>-*.md`. Check both paths:
   > ```bash
   > ls docs/PRD/<N>-* 2>/dev/null || ls docs/PRD/<R>-* 2>/dev/null
   > ```
   > To discover R when unsure, examine the issue's linked PRs or the issue body for `Parent #R` / `Closes #R` references.
5. **Default branch** — Check dynamically: `gh repo view <owner>/<repo> --json defaultBranchRef --jq '.defaultBranchRef.name'` or `git remote show origin | grep HEAD`. Do NOT hardcode `master` — the repo may use `main` or another name.

## Delegate Task Context Template

```python
delegate_task(
    goal="Execute the Plan phase for Issue #N: <title>. Read the PRD, create DESIGN doc, optionally TASKS doc, branch from default branch, commit, push, create PR, and auto-merge.",
    context=f"""
## Issue #N - <title>
Status: OPEN, workflow/plan, depth/<depth>
Research PR #R: MERGED (branch: research/<R>-<slug>)
PRD: docs/PRD/<R>-*.md (<lines> lines)   # <R> = research issue number (may differ from N)

## Project Info
- Repo: <owner>/<repo>
- Default branch: <dynamic — check gh repo view>
- Working directory: ~/workspace/<repo-name>
- Source ~/.hermes/.env for GH_TOKEN before any gh commands
- Git has uncommitted changes? Check first: git status. If so: git stash before branching, git stash pop after.
- Godot <version> engine (check game-env/manifest.yaml)

## PRD Summary
<2-3 paragraphs summarizing the PRD's problem, solution recommendation, and key constraints>

## Key Constraints
1. PR body format: "Parent #N" (space between Parent and #, NO colon)
2. Branch prefix: plan/ (e.g., plan/<N>-<slug>)
3. Branch FROM <default-branch> (NOT master unless that's the actual default)
4. Design doc goes to docs/DESIGN/<N>-*.md
5. TASKS doc goes to docs/TASKS/<N>-*.md (optional — only for depth/deep)
6. Test descriptions only in DESIGN doc — do NOT write runnable test files
7. Create PR via gh CLI, then auto-merge: gh pr merge <N> --auto --squash --delete-branch
   ⚠️ If uncommitted changes exist: git stash → branch → work → commit → PR → git stash pop
8. Use `gh pr list --state all --search "plan/<N> in:headRefName"` to check for existing PR before creating (prevent duplicates)
9. For Godot projects: verify project.godot is valid with godot --headless --quit if applicable

## Notification Format
Post one-line notification to Feishu webhook on phase completion:
curl -s -X POST -H "Content-Type: application/json" \
  -d '{{"msg_type":"text","content":{{"text":"📋 #N → plan complete"}}}}' \
  https://open.feishu.cn/open-apis/bot/v2/hook/76101281-b359-49ab-ae2f-fc486bf65958

## Labels to use
ONLY use existing workflow labels. Do NOT create new labels.

## Project Board
After creating the PR, add issue to the project board (project 5) and update Stage/Progress:
- gh project item-list 5 --owner <owner> --format json --limit 50 --jq '.items[] | select(.content.number==N) | .id'
- If found: update Stage to "Plan" (bd32d7fd), Progress to 40%
- If not on board: skip (the item may not be added yet)
"""
)
```

## Pre-Writing: Codebase Exploration

Before writing the DESIGN doc, read ALL relevant codebase files to understand the current architecture. The PRD describes what should change, but the codebase reveals what actually exists — and the gap between them is where design work happens.

### Step 0: Read the Issue Body Directly

Before diving into files, read the issue itself. The PRD scopes the *solution recommendation*, but the issue body holds the *acceptance criteria* which may be broader or different:

```bash
gh issue view <N> --json number,title,labels,body
```

The issue body may list ACs not reflected in the PRD (e.g., ACs about visual appearance, Decal colors, hallucination-driven variants). Document these alongside the PRD's scope in the DESIGN doc.

### Must-Read File Categories

| Category | Why | What to look for |
|----------|-----|-----------------|
| **PRD** (already read) | Solution recommendation, constraints, edge cases | Approach chosen, risk levels, dependency chain |
| **Affected .gd scripts** | Current implementation details, method signatures, signal contracts | What exists vs what the PRD assumes exists |
| **Related tests** | Expected behavior surface area, constructor patterns | Edge cases already covered, test gaps |
| **Scene .tscn files** | Node hierarchy, existing ExitZone/trigger placement | Where to place new nodes, existing visual config |
| **Existing DESIGN docs** | Convention alignment, section depth, language patterns | How other plan agents structured similar features |
| **constants.gd** | Existing thresholds, enums, path constants | Where to add new navigation/fallback constants |

> **Reference:** See `references/trigger-zone-patterns.md` for a consolidated map of the four trigger zone archetypes found across this project's scenes (Area3D+input_event, Area3D+EKeyTrigger, ExitZone, NPC.tscn). This saves reading every TSCN file from scratch.

### Codebase Gap Discovery

During codebase exploration, you may find that existing code **references methods or signals that don't exist yet**. For example:
- `ExitZone._transition()` calls `sm.trigger_zone_transition()` but that method may not be implemented in `SceneManager`
- The PRD may describe an ideal flow that the actual codebase can't support without new methods
- `@export` variables are referenced in TSCN files but the corresponding script may not define them
- The PRD's signal table lists signals that don't exist in the actual `.gd` file (e.g., PRD asserts `PlayerController` has `interactable_hovered` when it only has `interaction_requested`)

**When you find gaps:** Document them explicitly in the DESIGN doc's "Existing Component Modifications" section using a cross-reference table like:

| PRD Assertion | Actual Codebase | Design Resolution |
|---------------|----------------|-------------------|
| `PlayerController` has `interactable_hovered` signal | Does NOT exist; has only `interaction_requested`, `dialogue_mode_changed`, `navigation_hint_requested` | Add new signal as optional enhancement, or route through existing signals |

These are design requirements, not bugs — the implement agent needs to know what backbone methods to add.

> **Reference:** See `references/implementation-gap-analysis.md` for a worked example of the gap analysis applied to #221→#226, including a full classification table and the `Current State vs Target State` template.

### Discovering Partial Implementations from Related Issues

During codebase exploration, related issues (particularly when the PRD references a different issue number than the current plan issue) may already have **partial implementations** — dialogue files, test scripts, scene modifications, or state additions from a prior research or implement phase. These are easy to miss because:

- Files may live under the related issue's naming convention (e.g., `docs/PRD/59-*.md` for Issue #223, `docs/DESIGN/59-*.md`)
- Test files may already exist with the related issue's tests (`tests/test_stranger_dialogue.gd`, `tests/test_stranger_scene.gd`)
- The live `.dialogue` files may already be expanded even if the backup `.json` files match a different design

**Pattern to follow:**

```
1. Identify the related issue number(s) from the PRD's "Parent Issue" header
2. Search for files matching that issue number across the codebase:
   ls docs/DESIGN/<R>-* 2>/dev/null
   ls tests/test_<topic>* 2>/dev/null
   ls dialogues/*<topic>* 2>/dev/null
3. Read all found files — they represent existing work that the plan must acknowledge:
   - Existing tests: Add test case references in the DESIGN doc rather than planning duplicate tests
   - Existing dialogue files: Note which nodes already exist vs which need to be added
   - Existing scene scripts: Note which methods/handlers already exist (e.g., underpass.gd already sets is_new_game_plus flag)
4. In the DESIGN doc, add a "Prior Implementation Status" subsection under Architecture Overview listing what already exists and what still needs work
```

**Example from a real session:** The plan for Issue #223 (full-scene NPC framework) found that Issue #59's PRD and DESIGN doc already defined the three-layer dialogue tree, and test files `test_stranger_dialogue.gd` and `test_stranger_scene.gd` already existed with 14 test cases. The DESIGN doc referenced these as TC1–TC14 and added new TC15–TC25 on top, rather than redefining the entire test plan.

### Common Integration Patterns

When designing a new component that must coexist with existing Area3D subclasses (ExitZone, NPC InteractionTrigger, EKeyTrigger), the plan agent must choose between three integration patterns. Document the chosen pattern in the DESIGN doc's "Existing Component Modifications" section.

**Pattern 1 — Sibling (Recommended for additive features)**
Add the new component as a sibling/child of the existing trigger node, not replacing it. The existing Area3D subclass keeps its own signal wiring. The new component independently handles its new responsibility (e.g., visual feedback).
*When to use:* New feature is additive (visual feedback, sound effects, animation) and must not break existing signal wiring.
*Example:* `InteractiveArea` as child of `NPC.tscn` root alongside the existing `InteractionTrigger` Area3D. NPCNode keeps `body_entered`/`body_exited` for label visibility; InteractiveArea adds `mouse_entered`/`mouse_exited` for visual feedback.

**Pattern 2 — Wrapper/Replacement**
Replace the existing plain `Area3D` trigger with the new component (which extends Area3D). The new component's `input_event`, `mouse_entered`, `body_entered` etc. replace or forward to the original handler.
*When to use:* The new component fully supersedes the old trigger's functionality.
*Example:* Replacing an inline `Area3D` trigger in a TSCN with `InteractiveArea` that has both hover detection AND click gating, where the scene script connects to `interactive_clicked` instead of the raw `input_event`.

**Pattern 3 — Subclass**
Make the existing class extend the new component class (or vice versa). The child class inherits all signals, exports, and methods.
*When to use:* The new component IS a superset of the old class's behavior, and the subclass IS-A relationship is semantically correct.
*Example:* `ExitZone extends InteractiveArea` — ExitZone inherits hover visual feedback while adding its own `_transition()` method. NOT recommended when ExitZone already has its own well-defined contract that could be polluted by visual feedback concerns.

**Decision heuristic:** Start with Pattern 1 (Sibling) for additive visual/audio features. Only use Pattern 3 (Subclass) when the new component truly generalizes the old class's role.

```python
step 1: Read PRD at docs/PRD/<N>-*.md (or docs/PRD/<R>-*.md if R != N — see checklist step 4)
step 2: Find all related .gd files (search for class names, method names from PRD)
step 3: Read each .gd file fully (not just the PRD's listed files — read their dependencies)
step 4: Find related test files, read them
step 5: Check project.godot for input map actions / autoloads
step 6: Read constants.gd for relevant constants
step 7: Cross-reference PRD assertions against actual code (note discrepancies)
```

## Plan Phase Deliverables

**⚠️ Scope boundary (Patch 55, 2026-07-28):** The plan agent produces **documentation only**. Deliverables are exactly: DESIGN doc (required) and TASKS doc (optional, depth/deep). You MUST NOT:
- Write, modify, or stub **implementation files** (`.gd`, `.tscn`, `.tres`, source code) — no code stubs, no skeleton scripts
- Write or modify **runnable test files** (`tests/run_tests.gd`, `tests/test_*.gd`, etc.) — test *descriptions* go in the DESIGN doc, actual test code is the implement agent's job
- Modify `project.godot`, scenes, or any non-doc file

If you find yourself about to create anything under `gdscripts/`, `scenes/`, or `tests/`, stop — it does not belong in the plan phase. **Real trace:** a plan agent that wrote test files and code stubs forced the implement agent to reconcile conflicting files; the DESIGN doc alone is the contract.

### DESIGN Doc (`docs/DESIGN/<N>-<slug>.md`)

The DESIGN doc is the main deliverable. Its depth should match the feature's complexity — a simple refactor might be 100 lines, a multi-component navigation system might be 700+. **Use the following as a guide, not a rigid template. Adapt to what the feature needs.**

For complex features (multiple new components, cross-cutting changes to 5+ files, player-visible data flows), use this richer structure:

```markdown
# Design: <Feature Title>

> Parent Issue: #N
> Agent: game-plan-agent
> Date: <date>
> Approach: <Approach letter from PRD — confirm or explain divergence>

---

## 1. Architecture Overview

<High-level system diagram (ASCII or textual) showing new components,
existing components, and their relationships. Describe the design philosophy
— what principle guides each major decision.>

<Reference the PRD's recommended Approach and confirm it, or explain why
the design diverges.>

## 2. New Components — Detailed Design

<For each new node/script/class, provide:>
- **File:** path
- **Node structure:** (ASCII tree showing node hierarchy)
- **Signals:** emitted signals with parameter types
- **State Properties:** member variables with initial values
- **Key Methods:** method signatures and logic pseudocode
- **Integration notes:** how it connects to existing systems

> One subsection per new component. This is the bulk of the doc for
> greenfield features.

## 3. Existing Component Modifications

| File | Change | Why |
|------|--------|-----|
| `path/to/file` | What changes (method signatures, new exports, new signals) | Motivation |

> For each modified file, include pseudocode showing the new/changed methods.
> The implement agent should be able to write the code from this section alone.

Include separate sub-tables for:
- **New files** — scenes, scripts, resources, config files
- **Modified files** — existing files that need edits
- **Removed/Deprecated files** — files to delete or mark as deprecated
- **Affected test files** — test scripts that need rewriting/adaptation (list them with the nature of change so the implement agent knows which to touch)



## 4. Data Flow

<Full ASCII or numbered-step flow for each major operation. Include:>
- Flow 1: Normal path (happy path — scene transition, etc.)
- Flow 2: Fallback / error path
- Flow 3: Edge-case flow

> For complex features with multiple state transitions, include separate
> diagrams (e.g., Scene Transition Flow vs Fallback Flow vs Condition Flow).

## 5. Edge Cases & Error Handling

| Edge Case | Mitigation |
|-----------|------------|
| What scenario | How the system handles it |

> Table format preferred. Include at minimum 5 edge cases for any feature
> that touches player input or scene transitions. Common mitigation patterns:
> one-shot flags (prevent re-trigger), cooldown timers (debounce), timer
> resets (on scene re-entry), fallback counters (loop prevention).
> See §8 (Continuation Context) of the PRD for the PRD's own edge case
> inventory — adopt any the PRD already identified, then add your own.

## 6. Per-Scene / Per-Component Configuration

<For features requiring per-scene configuration (environmental guidance,
ExitZone placement, NPC posture), include a configuration table:>

| Scene | Exit(s) | Guidance Type | Configuration Notes |
|:-----:|:-------:|:-------------:|---------------------|

## 7. Integration Points

> **Status convention:** ⬜ = pending (resource created, not yet connected to its target).
> ✅ = connected (verified by implement agent). The implement agent MUST update this
> table when wiring integration points. The review agent verifies all ⬜ are resolved
> or explicitly deferred before merge.

| Integration | Our Component | Target Issue | How | Status |
|-------------|:---:|:---:|-----|:---:|
| System A | Comp B | #N | Signal wiring | ⬜ pending |

> Map every cross-component integration so the implement agent knows what
> to connect to what. Include signal names and method signatures.

## 8. Implementation Phases

| Phase | Priority | Components | Estimate |
|:-----:|:--------:|-----------|:--------:|
| Phase 1 | P0 | Core engine changes | X days |
| Phase 2 | P0 | Scene-level configuration | X days |

> Only for features complex enough to warrant phased delivery. Group by
> dependency order (things that block others go in earlier phases).

## 9. Test Case Descriptions

<Describe test scenarios — do NOT write runnable test code. Group by scenario.>

### Scenario A: <Description>
- Test 1: <what to test, preconditions, expected result>
- Test 2: <what to test, preconditions, expected result>

### Scenario B: <Description>
- Test 1: ...
```

For simpler features (single file change, no new components), the compact 6-section template is sufficient. Use your judgment on which format fits the feature's complexity — a one-file config change doesn't need 9 sections, but a multi-component system with 5+ file changes does.

### TASKS Doc (`docs/TASKS/<N>-<slug>.md`) — Optional

First, read the issue's `depth/` label (check via `gh issue view N --json labels`). This determines whether a TASKS doc is required or discretionary:

- **`depth/deep`**: REQUIRED — always create a TASKS doc
- **`depth/standard`**: Author one when **any** of these thresholds are met:
  - 10+ files affected by the change
  - 5+ files that must be migrated from one format/system to another
  - 5+ distinct implementation subtasks in different subsystems
  - The feature replaces or deprecates an existing feature (requires cleanup phase)
- **`depth/light`**: SKIP — no TASKS doc needed

A checklist of implementation tasks:

```markdown
# Tasks: <Feature Title>

> Parent Issue: #N

## Phase 1: <Module/Area>
- [ ] Task 1 (<file>): <description>
- [ ] Task 2 (<file>): <description>

## Phase 2: <Module/Area>
- [ ] Task 3 (<file>): <description>
```

## Workflow Invariants (from dev-workflow-dispatcher)

1. **Branch isolation** — Branch from the **default branch only** (check dynamically). Never branch from another issue's branch.
2. **Plan confirms Research** — DESIGN MUST reference the PRD's solution decision (Approach A/B/C) and either adopt it or explain why it's different.
3. **PR body `Parent #N`** — No colon. `Parent #N` (space) or `Closes #N`. This is required by `workflow-chain.yml` for label advancement.
4. **Issue stays open** — Do NOT close the parent issue. Only the implement PR merge or operator agent may close it.

### PR Body Verification (Post-Creation)

After creating the PR, verify the body contains the exact expected reference before submitting to auto-merge. This catches formatting errors (e.g., accidental colon after "Parent") that would break workflow-chain.yml label advancement:

```bash
gh pr view <PR_NUMBER> --json body | python3 -c "
import sys, json
body = json.load(sys.stdin)['body']
if 'Parent #N' in body:
    print('✓ Parent #N found')
    if 'Parent #N:' in body:
        print('✗ Has colon after Parent — expected \"Parent #N\" (no colon)')
    else:
        print('✓ No colon after Parent — correct')
else:
    print('✗ Missing expected reference')
"
```

## Pitfalls

### Shell-state persistence across terminal calls (CRITICAL)

**Hermes' `terminal` tool launches a fresh sub-shell per call.** A `git checkout -b` that succeeds in one terminal call may NOT persist to the next — `git branch --show-current` in a subsequent call can show a completely different branch. This was directly observed in session 2026-07-25: `git checkout -b plan/227-skill-check-system` confirmed the new branch, but the very next terminal call for `git status` showed the old `plan/216-*` branch.

**Mitigation — use the hybrid single-call pattern for all git operations:**

1. Write DESIGN/TASKS files first via `write_file` (Hermes tool — filesystem-level, survives branch switches)
2. Do **all** git ops (checkout, add, commit) in **one** terminal call:

```bash
# HYBRID PATTERN — use this every time. Do NOT split across terminal calls.
git checkout -B plan/<N>-<slug> main && \
git branch --show-current && \
git add docs/DESIGN/<N>-*.md docs/TASKS/<N>-*.md && \
git commit -m "docs(plan): add DESIGN doc for #<N>"
```

**Why `-B` instead of `-b`:** `-B` force-resets the branch to the target base, handling stale local branches. Without it, `git checkout -b` silently fails when a stale branch exists.

**Why one call:** Verified-by-call patterns (`git checkout -b && git branch --show-current`) are NOT reliable — even when the same call shows the correct branch, a subsequent terminal call for `git add` may land on the old branch. The single call is the only reliable mitigation.

**Recovery when split calls already happened (files staged on wrong branch):**
```bash
git restore --staged <files>           # unstage
git branch -D <wrong-branch>           # clean up stale branch
git checkout main && git pull origin main
git checkout -B plan/<N>-<slug> main
git branch --show-current              # verify
# Then git add + git commit — all in ONE more call
```

### Stale check_run events
The `check_run.completed` event for a research branch may arrive after the PR is already merged. Always verify PR state with `gh` before taking action. A PR with `state: "MERGED"` is not actionable — skip and check if label advancement is needed.

### Default branch varies by project
Do NOT hardcode `master`. Check dynamically with `gh repo view` or `git remote show`. The skill `dev-workflow-dispatcher` previously hardcoded `master` everywhere — this session discovered the repo uses `main` instead.

### `gh pr list --head` shell glob expansion
Do NOT use `gh pr list --head plan/<N>-*` — the shell expands the glob before `gh` sees it. Use `--search "plan/<N> in:headRefName"` instead.

### Stash pop may fail when branch or working tree changed
`git stash pop` can fail with "your local changes to the following files would be overwritten by merge" when:
- The stash was created on a different branch than the current one
- Files tracked by the stash were modified while the stash was stashed (e.g., by a concurrent git op or another Hermes session)

**Mitigation:**
```bash
# Before branch creation: stash once, note what was saved
git stash push -m "pre-plan-<N>"  # Named stash for clarity

# After plan PR is merged: try pop, fall back gracefully
git stash pop || {
  echo "Stash pop failed — attempting drop or manual restore"
  # Option A: drop the stash if nothing important was stashed
  git stash drop
  # Option B: list and inspect
  git stash show -p
}
```
If the stash contained *only* untracked/new files (DESIGN docs, test fixtures, scene files), those files still exist on disk — the stash was redundant and safe to drop. The `git stash drop` in the fallback is safe when `write_file` created the files independently.

### PR creation API failure
`gh pr create` (GraphQL) or the REST API may return persistent HTTP 500 errors — a server-side issue, not an input error. When it fails after 2-3 retries with short delays (3-10s):
1. Verify the branch was pushed: `git push origin plan/<N>-<slug>` (if not pushed yet)
2. Try the REST API fallback (sometimes GraphQL fails but REST works):
   ```
   curl -s -X POST \
     -H "Authorization: Bearer $GH_TOKEN" \
     -H "Accept: application/vnd.github+json" \
     "https://api.github.com/repos/<owner>/<repo>/pulls" \
     -d '{"title":"docs: PLAN for #N","head":"plan/<N>-<slug>","base":"<default-branch>","body":"Parent #N"}'
   ```
3. If REST also returns 500, provide the manual URL:
   `https://github.com/<owner>/<repo>/pull/new/plan/<N>-<slug>`
   The PR body must be `Parent #N` (no colon) for workflow-chain.yml compatibility.
   Do NOT report this as a blocker — the branch and commits are on GitHub, the PR just needs a click via the URL above.

### Missing game-plan-agent skill
This skill (`game-plan-agent`) was missing from the skill registry as of 2026-07-24. The cron poller had to inline the plan agent instructions. If you're reading this, the skill exists now — use it.

### DESIGN doc already exists (prior partial plan run)

The DESIGN doc (`docs/DESIGN/<N>-*.md`) may already exist from a prior (aborted or incomplete) plan agent run. The pre-spawn validation only checks for plan PRs — not for DESIGN files. An existing DESIGN file with substantive content is NOT a reason to skip the plan phase. Instead:

1. **Read the existing DESIGN fully** — assess what's present and what's missing
2. **Cross-reference against the skill's DESIGN template** — identify missing sections (commonly: Edge Cases, Integration Points, Per-Scene Configuration)
3. **Enhance with targeted patches, do NOT rewrite from scratch** — use `patch` with `old_string`/`new_string` to insert missing sections. Rewriting loses quality and risks introducing errors in already-good content.
4. **Renumber subsequent sections after insertion** — when inserting a new top-level section (e.g., adding §6 between §5 and old-§6), patch every subsequent top-level header (`## N.` → `## N+1.`) and their cross-references. Don't forget to update the header comment (`Depth: standard (sections X–Y)`) if present.
5. **Update header metadata** — at minimum, set the `Date:` to the current date so the next reader knows this plan was revisited.

**Example from #292:** The DESIGN doc had 753 lines with complete pseudocode, scene designs, signal wiring, and 10 test cases but was missing the §5 Edge Cases section required by the skill. The agent inserted §6 (Edge Cases) via one patch, then renumbered §§6–9 → 7–10 via six additional patches, and updated the header comment from `sections 1–6 + 9` to `sections 1–10 + appendices`.

### PRD invisible from stale working branch (research merged, but agent on different branch)

When the research PR has already been merged to `main`, the PRD file **exists on the default branch** but may be **invisible from the agent's current branch** via `read_file` or `search_files` — those tools search the *filesystem working tree*, not git history.

This hit in session 2026-07-25: the agent was on `pr-266` (a stale feature branch) when `search_files("docs/PRD/*217*", ...)` returned 0 results. The PRD existed on `main` (merged via PR #268) but simply wasn't on the working tree.

**Detect this case:**

```bash
# When search_files fails to find the PRD on the working tree,
# check if it exists on main:
git ls-tree -r origin/main --name-only | grep "docs/PRD/<issue>-"
# Or try reading it directly:
git show origin/main:docs/PRD/<issue>-*.md 2>/dev/null | head -5
```

**Then read it via git show (safe — no branch checkout needed):**

```bash
git show origin/main:docs/PRD/<issue>-<slug>.md
```

**Key distinction from cross-branch reading in `feature-plan-documentation`:**
- `feature-plan-documentation` covers `origin/research/<branch>` (PR **not yet merged**, file on research branch)
- This pitfall covers `origin/main` (PR **already merged**, file on main, but working tree is on a stale/incompatible branch)
- Both use `git show` to read without checking out the target branch, but the source ref is different (`origin/main` vs `origin/research/<branch>`)

**Root cause:** `search_files`/`read_file` search the filesystem only. Files that exist only in git history on a different branch won't appear. Use `git ls-tree` + `git show` as the primary way to discover and read git-tracked files across branches.
