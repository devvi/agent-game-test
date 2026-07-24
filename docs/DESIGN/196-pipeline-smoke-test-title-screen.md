# Design: Pipeline Smoke Test — Update Title Screen Version to v0.2.0

> Parent Issue: #196
> Agent: plan-agent
> Date: 2026-07-24
> Depth: light

## Summary

One-line string replacement in `gdscripts/title_screen.gd` to bump the displayed version from `v0.1.0` to `v0.2.0` as a pipeline smoke test.

## Change

| File | Line | Current Text | New Text |
|------|------|-------------|----------|
| `gdscripts/title_screen.gd` | 25 | `version_label.text = "v0.1.0 — Literary Micro CRPG"` | `version_label.text = "v0.2.0 — Literary Micro CRPG"` |

## Approach

**Inline string replacement** (Approach A from PRD). No new files, no refactoring, no centralized constants — this is a pipeline smoke test, and minimalism is the goal.

## Acceptance Criteria

1. Implementation PR changes only the single line above
2. 96 CI smoke tests pass
3. PR is reviewed and merged
4. Issue #196 auto-closes on merge

## Design Decisions

- **Why Approach A over B:** The PRD evaluated centralized version constants (Approach B) but rejected it as scope creep. A smoke test should change exactly one thing with zero risk. Refactoring can happen in a follow-up issue if needed.
- **No new abstractions:** Adding a `version.gd` constant file would introduce indirection that confuses the smoke test signal — if the pipeline breaks, we'd have to debug whether it's the constant file or the pipeline stage.
