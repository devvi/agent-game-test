# PRD Scope Deconfliction Examples

> Companion to Patch 14 in SKILL.md. Records real overlap cases from the
> agent-game-test project so future research agents can recognize when a
> PRD must shift its scope angle.

## Case 1: #156 (Scene Transition System) vs #221 (Scene Navigation UX)

| | PRD #156 | PRD #221 |
|---|---|---|
| **Title** | Scene Transition System — Walking between areas | 场景间导航机制设计 |
| **Focus** | Technical: ExitZone Area3D component, spawn point forwarding, AUTO/EKEY modes | Design/UX: Route sequence maps, environmental guidance, fallback for stuck/death |
| **Overlap signal** | Both mention "scene transition" / "导航" | |
| **Deconfliction** | #156's Problem Definition established that dialogue-only transitions were the issue. #221's Problem Definition explicitly stated "tech transition exists" and focused on the UNCOVERED layer: player guidance, route visualization, and failure recovery. | |
| **#221's boundary statement** | `PRD #156 already covered the technical ExitZone mechanism. This PRD focuses on the higher-level navigation design: how the player knows where to go, route sequence maps per narrative arc, and fallbacks for stuck/death.` | |

### What worked well

1. #221's Problem Definition table ("Current Behavior" → "Missing navigation design") immediately distinguished it from #156's "dialogue-only transitions"
2. #221 referenced #156 mechanically ("Using the ExitZone from PRD #156's Approach A") without re-listing #156's 3 approaches
3. The Solution Comparison focused on GUIDANCE approaches (environmental vs UI overlay vs hybrid), not transition mechanics (which #156 already covered)

### Pitfall avoided

Had #221 re-listed #156's approaches (A: ExitZone, B: Per-scene logic, C: SceneRouter), the PRD would have been redundant. Instead it referenced them in one sentence and moved on.

---

## Case 2: Template — Use for future overlap discoveries

| | Existing PRD #{M} | New PRD #{N} |
|---|---|---|
| **Title** | | |
| **Focus** | | |
| **Overlap signal** | | |
| **Deconfliction** | | |

---

## Quick Reference: Scope Layers (mechanic → design ladder)

A feature often needs PRDs at multiple layers. Recognizing which layer a PRD
covers prevents scope collision:

```
Layer 4: UX/Player Experience     ← #221 (guidance design)
Layer 3: System Architecture      ← (cross-scene orchestration)
Layer 2: Component Implementation ← #156 (ExitZone, spawn points)
Layer 1: Data Model               ← (dialogue data format)
```

Each PRD should name its layer in the Problem Definition so the next layer's
PRD can reference it by name.
