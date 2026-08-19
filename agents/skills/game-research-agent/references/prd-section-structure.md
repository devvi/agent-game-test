# PRD Section Structure (Agent Game Test Project)

## Overview

The PRDs in this project follow a specific 8-section structure that differs from
the generic `templates/PRD_TEMPLATE.md`. The structure evolved across Issues #5,
#42, #45, #46, #48, #50, and #47. Each new PRD should match this established
format for consistency.

## 8 Sections

| # | Section | Content | Required For |
|---|---------|---------|--------------|
| 1 | **Problem Definition** | Current behavior (table of affected systems), Expected behavior (numbered list), User Scenarios (A/B/C with Frequency) | All depths |
| 2 | **Design Intent** | Why current behavior exists (table of issues that created it), Why change now, Previous constraints (table: Constraint × Detail) | All depths |
| 3 | **Impact Analysis** | Directly affected modules (table: File × Module × Nature of Change), New files needed (table), Indirectly affected modules (table), Data flow impact (ASCII diagram), Documents to update (checklist) | All depths |
| 4 | **Solution Comparison** | ≥2 approaches. Each: Description, table/narrative, Pros, Cons, Risk (Low/Med/High), Effort. Then Recommendation with numbered rationale. | All depths |
| 5 | **Boundary Conditions & Acceptance Criteria** | Normal path (AC checklist), Edge cases (numbered, ≥5), Failure paths (numbered, ≥3). ACs are checklists mapping to issue body. | All depths |
| 6 | **Dependencies & Blockers** | Depends on (table: Dependency × Status × Risk), Blocks (table: Future Work × Priority), Preparation needed (checklist). Include dependency chain ASCII map. | All depths |
| 7 | **Spike / Experiment** | Optional for `depth/standard`. Mandatory for `depth/deep`. When included, ≥3 experiments each with: Question to Answer, Method, Expected Result, Impact on Approach. If skipped, add note: "Skipped per {depth} label." | `depth/deep` only |
| 8 | **Continuation Context** | Handoff summary for plan agent. System state, main risks, next steps. Required for ALL depths. | All depths — always |

## Key Formatting Patterns

### Tables
- Use markdown tables with pipe separators
- First column = identifier (file name, approach name, dependency name)
- Last column = judgment (risk level, priority, nature of change)

### ASCII Data Flow Diagrams
```
Source emits signal
    │
    ├──► First consumer reads value
    │       └──► Transforms and re-emits
    │
    └──► Second consumer
            └──→ Action
```
Use `│ ├── └──` connectors. Use `→` for actions, `►` for signal emissions.

### AC Format
- Each acceptance criterion from the issue body gets a checkbox line:
  `[x] **AC1: Name** — Detail`
- Under each AC, list verification conditions as bullet points
- Edge cases and failure paths are numbered: `1.`, `2.`, etc.

### Depth Label Handling
- Check `gh issue view <N> --json labels` for `depth/standard` vs `depth/deep`
- `depth/standard`: Sections 1–6 + 8 required. Section 7 gets "Skipped per depth/standard label" note.
- `depth/deep`: All 8 sections required. Section 7 must have ≥3 concrete experiments.

## Examples

| PRD | Issue | Depth | Length | Notable |
|-----|-------|-------|--------|---------|
| `48-sound-system.md` | #48 | standard | 304 lines | Good Data Flow Impact diagram. Strong Problem Definition with system-gap table. |
| `50-state-world-feedback.md` | #50 | deep | 549 lines | Best example of deep PRD — full Spike section with 3 experiments. Detailed Table of Contents-length AC section. |
| `45-narrative-architecture.md` | #45 | standard | 358 lines | Chinese-language PRD (matching issue body). Narrative/scene-based Solution Comparison. |
| `47-gamestate-system.md` | #47 | standard | 589 lines | Most recent. Strong Impact Analysis with current-state fragmentation table. Approach A recommended for consolidation. |
| `5-crpg-core-mechanics.md` | #5 | deep | 444 lines | Early PRD. Established the Solution Comparison format (A/B/C with theme-binding analysis). |

## Common Pitfalls

- **Skipping Section 8 (Continuation Context):** This section is the handoff to the plan agent. Without it, the plan agent must re-scan all source files. Always include it, even for `depth/light`.
- **Overlapping Problem Definition with Design Intent:** Problem Definition describes WHAT is broken/missing. Design Intent explains WHY the broken state exists and WHY now is the right time to fix it. Don't merge these.
- **Missing dependency chain map:** The Dependencies section should include an ASCII diagram showing how this issue's dependencies chain together (e.g., Issue A → Issue B → This Issue). This helps the plan agent understand ordering constraints.
- **Vague Solution Comparison:** Each approach must have explicit Risk (Low/Med/High) and Effort (X-Y weeks) labels. Approaches without these are non-actionable.
