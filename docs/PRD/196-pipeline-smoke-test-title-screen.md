# Research: Pipeline Smoke Test — Update Title Screen Version to v0.2.0

> Parent Issue: #196
> Agent: research-agent
> Date: 2026-07-24

---

## 1. Problem Definition

### Current Behavior

The title screen in `gdscripts/title_screen.gd` (line 25) displays:

```
version_label.text = "v0.1.0 — Literary Micro CRPG"
```

This is the original version string set during project scaffold. No version bump has been performed since the initial setup, meaning the visible version lags behind the actual project state.

### Expected Behavior

After the change, the title screen should display:

```
version_label.text = "v0.2.0 — Literary Micro CRPG"
```

The version string should reflect the semantic version increment from v0.1.0 to v0.2.0 for all players who see the title screen.

### User Scenarios

- **Scenario A (player-facing):** A player launches the game and sees the title screen. The version label in the bottom-right corner reads "v0.2.0 — Literary Micro CRPG" instead of the old "v0.1.0 — Literary Micro CRPG".
- **Scenario B (dev-facing):** Developer CI/CD dashboards and build artifacts reference the correct version. The visible string at title screen is the canonical source of truth for version reporting.
- **Frequency:** Every launch — the title screen is the first scene every user sees.

---

## 2. Design Intent

### Why Does Current Behavior Exist?

The v0.1.0 string was set during initial project scaffolding (Issue #6) and has not been revisited since. No pipeline smoke test has ever validated the end-to-end workflow from backlog → research → plan → implement → CI → review → merge.

### Why Change Now?

This is not a functional feature but a **pipeline smoke test**. The goal is to verify that every stage of the development workflow operates correctly:

1. Research agent can create a PRD and open a research/ PR
2. Plan agent can produce a DESIGN doc
3. Implement agent can make the one-line code change
4. CI tests (96 smoke tests) pass
5. Review agent can approve and merge
6. The issue auto-closes

Version v0.2.0 is chosen as the target because it's a trivial, unambiguous change — if any step fails, it's the pipeline, not the code.

### Previous Constraints

- Depth/light label means no Obsidian search or deep design analysis is required.
- Lock-mbot label indicates an mbot instance holds the workflow lock.

---

## 3. Impact Analysis

### Affected Modules

| Module | File | Change Type |
|--------|------|-------------|
| Title Screen (UI) | `gdscripts/title_screen.gd` | One-line string literal replacement |

### New Files Needed

- `docs/PRD/196-pipeline-smoke-test-title-screen.md` (this document)

### Data Flow

```
gdscripts/title_screen.gd:_ready()
    └─ version_label.text = "v0.2.0 — Literary Micro CRPG"
         └─ Rendered on CanvasLayer in scenes/title_screen.tscn
```

No data flow dependencies. This is a pure presentation-layer string change.

### Potential Side Effects

- None — the version label is purely cosmetic, read-only, and drives no logic or branching.

---

## 4. Solution Comparison

### Approach A: Inline String Replacement (Recommended)

**Description:** Change the string literal directly at line 25 of `gdscripts/title_screen.gd`.

```gdscript
version_label.text = "v0.2.0 — Literary Micro CRPG"
```

**Risk:** ✅ None — single character change.
**Effort:** 🟢 Trivial (< 1 minute).
**Why preferred:** Only one line needs changing; there is no version constant, config file, or build-time variable in the current codebase.

### Approach B: Centralized Version Constant

**Description:** Extract the version string to a global constant (e.g., `const VERSION: String = "v0.2.0 — Literary Micro CRPG"` in a dedicated `version.gd` or `constants.gd`).

**Risk:** ⚠️ Medium — introduces a new file and indirection for a smoke test that should be as minimal as possible.
**Effort:** 🟡 Small (~5 minutes).
**Why not preferred:** This is a pipeline smoke test, not a refactoring. Introducing new abstractions would add complexity beyond the scope of the issue and pollute the signal of whether the pipeline works.

---

## 5. Boundary Conditions & Acceptance Criteria

### Acceptance Checklist

| # | Criterion | Verification Method |
|---|-----------|--------------------|
| 1 | PRD PR (research/) is created, reviewed, and merged | `gh pr view` / CI passing |
| 2 | DESIGN doc PR (plan/) is created, reviewed, and merged | `gh pr view` / CI passing |
| 3 | implement PR changes `version_label.text` to `v0.2.0` | Diff inspection |
| 4 | CI smoke tests (96 items) all pass | CI status check |
| 5 | Review agent approves PR | PR review status |
| 6 | Implement PR merges to main | Merge commit on main |
| 7 | Issue #196 auto-closes on merge | Issue state = CLOSED |

### Edge Cases

- **Empty scene:** If `version_label` node is missing from the scene tree, the `@onready var` will error. This is not introduced by this issue — it's a pre-existing setup concern.
- **Encoding:** The em dash (—) and special characters are already present in the current string; no new encoding concerns are introduced.
- **Multiple version strings:** A search of the codebase confirms `v0.1.0` appears only on line 25 of `title_screen.gd`.

---

## 6. Dependencies & Blockers

### Dependency Chain

```
#196 (this issue) — no upstream dependencies

Downstream:
  └─ (none — this is a standalone smoke test that does not block any feature)
```

### Blockers

- None. The `workflow/research` and `workflow/lock-mbot` labels are already set. The issue is in OPEN state. All preconditions for the research stage are met.

---

## 7. Spike/Experiment

**Skipped per depth/light label.**

This is a trivial one-line string change with no technical uncertainty. No spike or experiment is required.

---

## 8. Continuation Context

### Handoff for Plan Agent

**Next agent:** plan-agent

**Given context:**
1. PRD is approved and merged (`docs/PRD/196-pipeline-smoke-test-title-screen.md`)
2. Required change is a single line in `gdscripts/title_screen.gd`:
   - `version_label.text = "v0.1.0 — Literary Micro CRPG"` → `version_label.text = "v0.2.0 — Literary Micro CRPG"`
3. Depth/light — no Obsidian search or deep analysis needed
4. The implement agent only needs to change this one line

**Plan agent should:**
1. Create a `plan/` branch from main
2. Write a minimal DESIGN doc at `docs/DESIGN/196-pipeline-smoke-test-title-screen.md`
3. Open a plan/ PR, get it merged
4. Hand off to implement agent

**Plan agent should NOT:**
- Add new files, refactorings, or abstractions
- Touch any other module
- Perform version string extraction to a shared constant (that's scope creep for a smoke test)
