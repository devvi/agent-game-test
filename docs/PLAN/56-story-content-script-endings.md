# Plan Index: #56 — Story Content

> Parent Issue: #56
> Branch: plan/56-story-content-script-endings

## Deliverables

| Document | Path | Status |
|----------|------|--------|
| PRD | `docs/PRD/56-story-content-script-endings.md` | ✅ Merged via PR #97 |
| DESIGN | `docs/DESIGN/56-story-content-script-endings.md` | ✅ Complete |
| TASKS | `docs/TASKS/56-story-content-script-endings.md` | ✅ Complete (17 tasks, 6 phases) |

## Design Summary

Approach A (direct content fill) to expand all 7 dialogue JSON files from 30→62 nodes, add 4 new intertextual echoes (total 7), and deepen 3 endings with 5+ node emotional arcs each. No code changes needed to runtime engine.

## Task Structure (17 tasks, 6 phases)

- **Phase 1** (Day 1): Thin files first — bridge_homeless (1→7 nodes), subway_ending (4→17 nodes)
- **Phase 2** (Day 2-3): Enrich existing files — office_door (3→5), lobby_stranger (5→7), lobby_guard (3→5), store_clerk (10→14), underpass_echo (4→7)
- **Phase 3** (Day 3): New echoes — 4 new echo IDs + handlers in narrative_manager.gd
- **Phase 4** (Day 3-4): Environmental text verification + Hemingway audit
- **Phase 5** (Day 4): 15 test cases covering all content
- **Phase 6** (Day 4-5): Final walkthrough and polish

## Next Step

Advance to **workflow/implement** — implement dialogue content per TASKS doc.
