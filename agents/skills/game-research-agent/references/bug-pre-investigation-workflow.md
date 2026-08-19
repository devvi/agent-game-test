# Bug Pre-Investigation Workflow

## When This Is Needed

When assigned a `bug`-labeled issue (not a feature request), before running technical debugging tools (compiler checks, error traces), do a **workflow-level pre-investigation** to determine whether the described bug has been partially or fully addressed by prior PRs. This prevents re-investigating already-fixed code and surfaces the actual remaining issues.

## Procedure

### Step 1 — Gather Context

Read the issue body first to extract the key claims:

```bash
gh issue view <N> --json title,body,labels,state,assignees
```

Extract:
- What specific file + line is mentioned (e.g., `scene_manager.gd:32`)
- What specific error message is described (e.g., `"add_child() failed"`)
- What specific fix is proposed (e.g., "use call_deferred()")
- Each acceptance criterion as a separate concern

### Step 2 — Check Current Source

Read the exact file + line mentioned in the issue. If the fix already exists in the current source, the issue is partially stale — log it as **Already Fixed** and proceed to find what's actually still broken.

```bash
read_file path/to/file.gd
```

### Step 3 — Find the Fixing Commit

```bash
# Search commit messages for the issue number or file
git log --oneline --all | grep -i "<issue-N>"
git log --oneline -- <path/to/file.gd>

# Read the fix commit diff
git show <commit-hash> -- <path/to/file.gd>
git show <commit-hash> --stat   # What other files were touched
```

The commit message and diff tell you:
- Which other files were changed in the same fix (siblings worth checking)
- Whether the fix was complete or addressed only one symptom
- Whether the fix was part of a larger batch PR (e.g., fixing N errors at once)

### Step 4 — Cross-Reference Against Existing Docs

Check PRDs, DESIGN docs, and TASKS docs that mention the same system. The bug may have been anticipated and partially addressed in prior planning.

```bash
search_files("<system-name>", target="content", path="docs/")
```

Look for:
- Prior PRDs that catalogued this bug as a known issue
- Design docs that describe the fix strategy
- Tasks docs that list this fix under a specific task ID
- Notes about remaining work not yet done

### Step 5 — Map the Bug's Non-Obvious Surface Area

The issue describes ONE symptom. The real problem may be broader.

**Scene/file inventory:**
```bash
# Find all scenes that use the affected system
grep -l "SceneManager\|FadeCurtain" scenes/*/*.tscn

# Categorize each scene: does it have the relevant node or not?
grep -c "FadeCurtain" scenes/*/*.tscn
# 0 = no (uses programmatic creation), N>0 = yes (has pre-existing node)
```

**Cross-file call-chain inventory:**
```bash
# Find ALL callers of the affected functions
grep -rn "trigger_scene_change\|fade_in\|fade_out" gdscripts/

# Find ALL references to the affected node by name
grep -rn "\"FadeCurtain\"\|get_node.*FadeCurtain" gdscripts/
```

**Over-fix detection:** If the issue title mentions a symptom that doesn't exist in current code (e.g., "get_node('FadeCurtain') returning null" but the only call is guarded by `has_node`), note this in the PRD as a stale claim.

### Step 6 — Identify the REAL Remaining Bug

After Steps 1–5, what's actually broken? Often the deepest issue is NOT what the issue title describes. Build a table:

| Issue Title Claim | Pre-Investigation Result |
|-------------------|--------------------------|
| "add_child during node setup in line 32" | ✅ Already fixed (commit 3a7242c) |
| "get_node('FadeCurtain') returning null" | ❌ No unguarded get_node calls exist |
| Acceptance: "No add_child error on launch" | ✅ Already satisfied by prior fix |
| Acceptance: "Fade curtain appears correctly" | ❌ Still broken — **this is the real bug** |

The real bug is often a **secondary effect** of the original fix — the fix corrected one symptom but the deeper behavioral issue remains (e.g., `call_deferred` avoided the race, but the fade-in guard prevents animation from playing on the new scene).

### Step 7 — Document in the PRD

In the PRD's Problem Definition section, include a table that separates:
1. **Already fixed** — what was done and in which commit/PR
2. **Still broken** — what remains, with evidence from code reading
3. **Stale claims** — issue title/body claims that don't match current code

This gives the plan agent a correct starting point and prevents re-fixing.

## Edge Cases

| Case | Scenario | Handling |
|------|----------|----------|
| Issue created before fix PR merged | Issue describes pre-fix state, title mentions already-fixed symptom | Document as partially stale; investigate for remaining behavioral issues |
| Fix commit is part of batch PR | Multiple errors fixed together, some may remain unaddressed | Check each file in the batch PR for completeness of the fix |
| No git history found | Fresh repo with no prior fix commits | Proceed with standard bug investigation (see other references) |
| Issue is reopened after previous close | Fix was incomplete or introduced regression | Read the original fix commit AND the reopen reason |
| **Issue body already contains root cause analysis** | Issue creator pre-investigated: includes failure table (Test × Expected × Actual), reproduction command, and blocked PRs listing | **Skip Steps 1–6.** Verify each claim against current source (one round of `read_file` on each affected file), then go directly to Step 7 (PRD). The issue body IS the pre-investigation — your job is confirming and structuring, not re-discovering. Example: Issue #340's body contained a 5-row failure table with exact test names, expected vs actual values, and headless reproduction command. |

## PRD Structure for Test-Only Fix Bugs

When the pre-investigation reveals that ALL failures are in test code (not production code), the PRD follows a modified structure. This is distinct from standard bug PRDs where the fix is in production code.

### Detection

A test-only fix bug has ALL of these signals:
- Root cause: production code behavior changed correctly (via merged PRs) but tests weren't updated
- Zero production code changes needed — the fix is assertion updates or test harness fixes
- The issue's `Expected` column matches current production behavior, not old test expectations

### Solution Comparison Structure

Standard bug PRDs compare fix approaches for production code. Test-only fix PRDs compare **test maintenance strategies**:

| Approach | Description | When to Use |
|----------|-------------|-------------|
| **A: Fix tests only** (default) | Update assertions to match current production behavior. No prod code changes. | When production behavior is correct — tests are stale, not wrong |
| **B: Add headless/prod fallbacks in production code** | Modify production code to add test-only code paths (e.g. `if not is_inside_tree(): …`) | Almost never — violates "don't change production code for tests" |
| **C: Rewrite tests with scene trees** | Move from pure headless (`Node.new() + set_script()`) to full scene loading | Only when headless sync behavior fundamentally can't test the feature (rare) |

Approach A is recommended by default for test-only fix bugs. The key rationale to document in the PRD: "production behavior was validated correct by prior PRs — tests are the lagging artifact."

### Headless-Specific Root Causes

Common headless test failure patterns in Godot 4.x projects (add to Problem Definition table):

| Root Cause Pattern | Symptom | Affected Code |
|-------------------|---------|---------------|
| `await timer` skipped in headless | State transitions complete synchronously, breaking test assumptions about intermediate states | `_timer_1s()`, any `await get_tree().create_timer()` |
| `Engine.register_singleton()` with `RefCounted` | Singleton registration silently fails — `get_singleton()` returns null | Test suites extending `extends RefCounted` |
| `@onready` var initialization skipped | Mock-assigned vars from `set_script()` override may differ from scene-tree `_ready()` behavior | Any test using `Node.new() + set_script()` + manual `@onready` assignment |
| No-op'd methods after refactor | Method body changed to `pass` after another component took over responsibility | `_pause_and_serve()` → `pass` after FSM #294 took serve timing |

### PRD §1 Table Format

For test-only fix PRDs, the Problem Definition failure table should include a **Root Cause** column linking each failure to the production code line that caused it:

```markdown
| # | Test | Suite | Expected | Actual | Root Cause |
|---|------|-------|----------|--------|------------|
| TC11 | `_test_tc11_headless_no_tree` | Scoring | serve_count>0 | serve_count=0 | scoring_manager.gd:105-108 — `_pause_and_serve()` → `pass` after FSM #294 |
```

This lets the implement agent understand WHY the test broke without re-reading the entire source file.
