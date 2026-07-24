# Design: #220 — 核心主题→机制映射研究 (Core Theme→Mechanism Mapping)

> Parent Issue: #220
> Agent: plan-agent
> Date: 2026-07-25

---

## 1. Architecture Overview

### Core Idea

Define a **bidirectional affinity matrix** (3 themes × 12 mechanisms × 5 dimensions) supplemented by **narrative paragraphs** describing the player action layer for each mapping chain (Approach C from PRD §4). This design document operationalizes the PRD's findings into a structured, actionable reference that answers—for every mechanism—how it expresses each theme, how strongly, and whether it could be replaced or removed.

**Design Principles:**

1. **Scoring transparency** — Every entry in the 12×3×5 matrix is explicitly graded on five dimensions (D1–D5), with no hidden weighting.
2. **Bidirectional traceability** — From any theme, find all carriers and their strength. From any mechanism, find all themes it expresses.
3. **Elimination candidacy** — Low-scoring entries are flagged with explicit replacement/removal candidates and documented rationale.
4. **Runtime verifiability** — Each mapping chain is testable in playtest via a structured checklist (see §5).

### Data Flow

```ascii
PRD #220 Research (theme→mechanism hypothesis)
     │
     ▼
DESIGN #220 (this doc — bidirectional affinity matrix + narrative chains)
     │
     ├──► Theme Coverage Map (§2)         — which themes need which mechanisms
     ├──► Mechanism→Player→Theme Chains (§3) — 12 full mapping chains
     ├──► Combined Scoring Matrix (§4)     — 3×12×5 quantitative scoring
     └──► Runtime Validation (§5)          — playtest checklist & spike results
             │
             ▼
     TASKS #220 (implementation plan)
             │
             ▼
     GDD updates: docs/GAME_DESIGN/01-OVERVIEW.md (§3 mapping summary)
     Content priorities: dialogue JSON fill order
     Elimination decisions: M05 clock deprecation or retention
```

### Scope

| Scope | Boundary |
|-------|----------|
| **In scope** | 12 existing mechanisms (M01–M12) vs. 3 core themes (T1–T3) |
| **In scope** | 5 eliminated candidate mechanisms with rationale |
| **In scope** | Substitution tests for M07 hallucination engine (3 target games) |
| **Out of scope** | New mechanism proposals |
| **Out of scope** | New theme proposals |
| **Out of scope** | Code changes — this is an analytical/referential design doc |

---

## 2. Theme Coverage Map

### 2.1 Carrier Intensity by Theme

| Theme | Total Score (max 300) | Primary Carriers (≥20/25) | Secondary Carriers (16-19/25) | Coverage Pattern |
|:-----|:--------------------:|:--------------------------:|:----------------------------:|:----------------:|
| **T1 都市疏离** | 223 | M03(24), M04(23), M01(22), M02(21), M12(21), M10(20), M11(20) | M09(19), M06(16) | **Distributed** — many carriers, no single dependency |
| **T2 博尔赫斯克式不确定性** | 224 | M07(25), M08(24), M02(23), M06(22), M03(21) | M01(19), M09(19), M10(16), M11(16), M12(16) | **Concentrated** — M07+M08 are critical |
| **T3 幻觉/现实模糊** | 222 | M07(25), M10(23), M03(21), M08(21), M02(20), M06(20), M09(20) | M12(18), M01(16), M04(16), M11(14) | **Bimodal** — M07 dominant, M10 strong, rest moderate |

### 2.2 Critical Dependency Analysis

The three themes have **near-equal total scores** (223/224/222), but their structural health differs dramatically:

- **T1** has **7 mechanisms** scoring ≥20/25 — removing any single mechanism drops T1 by at most 5 points (M03 at 24 → 199). **Resilient.**
- **T2** has **5 mechanisms** ≥20/25, but M07(25) + M08(24) + M02(23) account for 72/224 = 32% of T2's score. Removing M07 drops T2 from 224 → 199 (-11%). **Moderately reliant.**
- **T3** is most vulnerable: M07(25) + M10(23) + M03(21) = 69/222 = 31%. Removing M07 drops T3 to 197 (-11%). **Vulnerable — M07 backup needed.**

### 2.3 Theme Coverage Gaps

| Gap | Severity | Mitigation |
|:----|:--------:|:-----------|
| T2 lacks a P0-tier (≥23) carrier beyond M07/M08/M02 | Medium | M06(22) is close; M02 is already P0 |
| T3's D3 (uniqueness) scores low for non-M07 mechanisms | High | M10(4/5) is the strongest backup for T3 |
| M05 clock scores 8/25 on T3 — near zero contribution | Low | Acceptable for a toggleable system |
| M04 scores 10/25 on T2 — rain has no uncertainty expression | Low | Not every mechanism needs all three themes |

---

## 3. Full Mapping Chains (Mechanism → Player Action → Theme)

### 3.1 Mapping Chain Template

Every chain follows the form:

```ascii
mechanism: <mechanism name and technical operation>
    ↓
player action: <what the player does or experiences>
    ↓
expressed themes: <themes with narrative explanation>
```

### 3.2 M01: Three-Axis Slider System

**Chain:**
```
mechanism: Tri-axis slider (hope 0-10 / conviction 0-10 / will 0-10)
    ↓
player action: Player makes dialogue choices or exploration interactions
              → state values change (e.g., "revise again" → hope -0.5)
              → UI updates reflect emotional drift
    ↓
T1 Urban Alienation: Lower hope = colder world. The slider is the measure of
    "how long you've survived this city."
T2 Borgesian Uncertainty: Changes are non-linear — a choice that raises hope
    lowers conviction. The player questions who they really are.
T3 Hallucination/Reality: State modifiers adjust hallucination level
    (hope ≥ 8 → -1, hope ≤ 2 → +1). Emotion directly distorts perception.
```

### 3.3 M02: Dialogue-as-State-Check

**Chain:**
```
mechanism: dialogue_condition_evaluator selects branches based on state values
    ↓
player action: Player encounters NPCs; dialogue branches auto-select based on
              current state → player sees their inner state projected, not chosen
    ↓
T1 Urban Alienation: Low state = colder NPC responses. Alienation is
    determined by mental state, not player choice.
T2 Borgesian Uncertainty: Same NPC says different things at different states.
    Who is real — the NPC, or the player projecting themselves?
T3 Hallucination/Reality: Player can't directly control dialogue branches.
    The hidden state determines everything — agency is an illusion.
```

### 3.4 M03: Worldview Filter / 5-State Environment Text

**Chain:**
```
mechanism: Text components (lamppost, neon, puddle, rain) switch variants
           based on state ID (1-5)
    ↓
player action: Player walks through scenes and sees environmental text change
              automatically → "the world changes with my mood"
    ↓
T1 Urban Alienation: Despair-mode lamps say "Elm Street — nowhere,"
    puddles read "The street drowns." The city reflects loneliness.
T2 Borgesian Uncertainty: Same location shows different text after a state
    shift — is it the same place? The player is never sure.
T3 Hallucination/Reality: State 1 (Despair) doubles rain text glow — the
    external world becomes a projection of the internal.
```

### 3.5 M04: Rain Pressure System

**Chain:**
```
mechanism: Rain intensity = f(conviction, scene base rain) + heavy rain
           increases burnout accumulation
    ↓
player action: Conviction drops → rain intensifies → player seeks shelter
              → forced introspection during sheltering
    ↓
T1 Urban Alienation: Alone in the rain, seeing distant lit windows — urban
    solitude amplified by sound.
T3 Hallucination/Reality: Rain syncs with inner state — it's not weather,
    it's an emotional barometer.
T2 Borgesian Uncertainty: (Weak — 10/25) Rain is too literal to create
    uncertainty; it reinforces atmosphere but doesn't create doubt.
```

### 3.6 M05: 3-Month Clock System

**Chain:**
```
mechanism: Each interaction consumes game days; day 90 triggers deadline
    ↓
player action: Dialogue/exploration → in-game days advance → deadline
              reminder events → player senses time slipping away
    ↓
T1 Urban Alienation: Time keeps passing, and the player remains isolated.
    The deadline is the city's cold reminder of "no results."
T2 Borgesian Uncertainty: Pace is irregular (0.5-3 days per interaction) —
    the player can't accurately gauge remaining time.
T3 Hallucination/Reality: (Very weak — 8/25) The clock is too mechanical to
    create reality blur. Conceptual link exists but runtime perceptibility is low.
```

### 3.7 M06: Echo System

**Chain:**
```
mechanism: Lines/images recur across scenes with state-dependent variants
    ↓
player action: Player hears scene A's dialogue replayed in scene B
              (e.g., "Rain so heavy…" from convenience store in underpass)
    ↓
T2 Borgesian Uncertainty: Same words in different contexts with different
    variants — is this a loop, or different entrances to the same space?
T3 Hallucination/Reality: The echo chain's "real" source is unreliable.
    Was it the NPC or the player's memory?
T1 Urban Alienation: Rare connections echo in memory — sparse human contact
    becomes the only island in isolation.
```

### 3.8 M07: Hallucination Engine

**Chain:**
```
mechanism: Physical distance (office→subway) → hallucination level (0→10)
           with scene base + state modifier
    ↓
player action: Player walks the route; vignette darkens, rain thickens,
              lights flicker, text drifts, camera destabilizes
    ↓
T3 Hallucination/Reality: Core mapping — distance is hallucination.
    The longer the walk, the more reality dissolves.
T2 Borgesian Uncertainty: Hallucination is non-monotonic (hope-adjusted) —
    the player can never trust their senses.
T1 Urban Alienation: (Weak — 11/25) Hallucination is an internal phenomenon,
    not an urban one. The link to "city loneliness" is indirect.
```

### 3.9 M08: Borgesian Constraints (B1-B6)

**Chain:**
```
mechanism: 6 constraints (unreliable narration B1, mirror/labyrinth B2,
           boundary blur B3, recursion B4, text overlay B5, infinite paradox B6)
    ↓
player action: Player reads ambiguous text ("Didn't I push this door before?")
              and cannot determine the story's truth
    ↓
T2 Borgesian Uncertainty: Core mapping — all 6 constraints serve
    "reality is unknowable."
T3 Hallucination/Reality: B1 requires ≥70% ambiguous text when hallucination ≥5
    — unreliable narration directly supports reality blur.
T1 Urban Alienation: (Weak — 11/25) Constraints are structural, not
    atmospheric. No direct alienation expression.
```

### 3.10 M09: Route Flags / Three-Ending System

**Chain:**
```
mechanism: Subway station ending determined by hope/conviction/will values
           → Keep Walking / Turn Back / Stay
    ↓
player action: Player reaches the station → system selects ending
              based on accumulated state, not final choice
              → player sees "results of the journey," not a last-minute decision
    ↓
T1 Urban Alienation: Turn Back = returning to the empty office — the
    ultimate consolidation of isolation.
T2 Borgesian Uncertainty: Turn Back implies a loop — returning to start
    is a labyrinth.
T3 Hallucination/Reality: Stay — neither leaving nor returning, reality and
    hallucination merge on the platform.
```

### 3.11 M10: Stranger NPC

**Chain:**
```
mechanism: Stranger's appearance/voice changes with hope (hope ≥ 7 clear &
           warm → hope ≤ 3 shadowed face, hollow voice)
    ↓
player action: Player meets Stranger in 3 scenes (lobby/underpass/subway)
              → appearance reflects player's inner state
              → player suspects "this NPC might be me"
    ↓
T3 Hallucination/Reality: Core mapping — the Stranger is the player's inner
    state physically projected. The engine's personification.
T1 Urban Alienation: Even when talking to the Stranger, the player talks to
    themselves. The only "understanding" in the city is an imagined self.
T2 Borgesian Uncertainty: The Stranger's shifting appearance creates
    identity uncertainty — who is the stranger really?
```

### 3.12 M11: Hemingway Writing Constraints

**Chain:**
```
mechanism: Runtime text length/sentence limits + auto-truncation + editor warnings
    ↓
player action: All text (dialogue/narration/labels/choices) obeys constraints
              → short, precise, restrained pacing
    ↓
T1 Urban Alienation: Short sentences + iceberg theory = unsaid words matter
    more than said ones. Loneliness lives in the whitespace.
T2 Borgesian Uncertainty: Constrained narration leaves much unsaid —
    the player fills gaps, but their fills may be wrong.
T3 Hallucination/Reality: (Moderate — 14/25) Brevity contributes to
    reality blur indirectly (unreliable narration from lack of detail), but
    direct hallucination expression is weak.
```

### 3.13 M12: Lo-Fi 3D Text Rendering

**Chain:**
```
mechanism: Pixelated edges, constrained color depth, CRT scanlines, neon glow
    ↓
player action: Player reads imperfect text on dark scenes — pixel edges,
              flicker, dim glow → "this world is worn, limited"
    ↓
T1 Urban Alienation: Dim lights, faded signs — the city isn't glamorous;
    it's faded and forgotten.
T3 Hallucination/Reality: Scanlines + pixelation = reality itself is
    "low-resolution." The player shouldn't trust what they see.
T2 Borgesian Uncertainty: Constrained visuals mean constrained information
    — the player never sees the full picture.
```

---

## 4. Combined Scoring Matrix

### 4.1 Dimension Definitions

| Dim | Name | 1 Point | 5 Points |
|:---:|------|---------|----------|
| D1 | Thematic Fit | Mechanism is unrelated to theme | Mechanism is a **primary carrier** of the theme |
| D2 | Player Perceptibility | Player never notices | Player feels it without thinking |
| D3 | Mechanism Uniqueness | Easily replaced by other mechanisms | Irreplaceable for this theme |
| D4 | Implementation Efficiency | High cost, weak expression | Low cost, strong expression |
| D5 | Narrative Consistency | Breaks narrative atmosphere | Strengthens narrative unity |

### 4.2 Full Matrix: 12 Mechanisms × 3 Themes × 5 Dimensions

| # | Mechanism | Theme | D1 | D2 | D3 | D4 | D5 | Total |
|:-:|-----------|:----:|:--:|:--:|:--:|:--:|:--:|:----:|
| M01 | Three-Axis Slider | T1 | 5 | 4 | 4 | 4 | 5 | **22** |
| M01 | Three-Axis Slider | T2 | 4 | 3 | 3 | 4 | 5 | **19** |
| M01 | Three-Axis Slider | T3 | 3 | 3 | 2 | 4 | 4 | **16** |
| M02 | Dialogue-as-Check | T1 | 4 | 4 | 3 | 5 | 5 | **21** |
| M02 | Dialogue-as-Check | T2 | 5 | 4 | 4 | 5 | 5 | **23** |
| M02 | Dialogue-as-Check | T3 | 4 | 3 | 3 | 5 | 5 | **20** |
| M03 | Worldview Filter | T1 | 5 | 5 | 4 | 5 | 5 | **24** |
| M03 | Worldview Filter | T2 | 4 | 4 | 3 | 5 | 5 | **21** |
| M03 | Worldview Filter | T3 | 4 | 4 | 3 | 5 | 5 | **21** |
| M04 | Rain Pressure | T1 | 5 | 5 | 4 | 4 | 5 | **23** |
| M04 | Rain Pressure | T2 | 1 | 1 | 1 | 4 | 3 | **10** |
| M04 | Rain Pressure | T3 | 3 | 3 | 2 | 4 | 4 | **16** |
| M05 | 3-Month Clock | T1 | 3 | 3 | 2 | 3 | 4 | **15** |
| M05 | 3-Month Clock | T2 | 3 | 2 | 2 | 3 | 3 | **13** |
| M05 | 3-Month Clock | T3 | 1 | 1 | 1 | 3 | 2 | **8** |
| M06 | Echo System | T1 | 3 | 3 | 2 | 4 | 4 | **16** |
| M06 | Echo System | T2 | 5 | 4 | 4 | 4 | 5 | **22** |
| M06 | Echo System | T3 | 4 | 4 | 3 | 4 | 5 | **20** |
| M07 | Hallucination Engine | T1 | 2 | 2 | 1 | 3 | 3 | **11** |
| M07 | Hallucination Engine | T2 | 5 | 5 | 5 | 5 | 5 | **25** |
| M07 | Hallucination Engine | T3 | 5 | 5 | 5 | 5 | 5 | **25** |
| M08 | Borgesian Constraints | T1 | 2 | 1 | 1 | 4 | 3 | **11** |
| M08 | Borgesian Constraints | T2 | 5 | 4 | 5 | 5 | 5 | **24** |
| M08 | Borgesian Constraints | T3 | 4 | 3 | 4 | 5 | 5 | **21** |
| M09 | Route Flags/Endings | T1 | 3 | 4 | 3 | 4 | 5 | **19** |
| M09 | Route Flags/Endings | T2 | 3 | 4 | 3 | 4 | 5 | **19** |
| M09 | Route Flags/Endings | T3 | 4 | 4 | 3 | 4 | 5 | **20** |
| M10 | Stranger NPC | T1 | 4 | 4 | 3 | 4 | 5 | **20** |
| M10 | Stranger NPC | T2 | 3 | 3 | 2 | 4 | 4 | **16** |
| M10 | Stranger NPC | T3 | 5 | 5 | 4 | 4 | 5 | **23** |
| M11 | Hemingway Constraints | T1 | 4 | 3 | 3 | 5 | 5 | **20** |
| M11 | Hemingway Constraints | T2 | 3 | 2 | 2 | 5 | 4 | **16** |
| M11 | Hemingway Constraints | T3 | 2 | 2 | 1 | 5 | 4 | **14** |
| M12 | Lo-Fi 3D Text | T1 | 4 | 4 | 3 | 5 | 5 | **21** |
| M12 | Lo-Fi 3D Text | T2 | 3 | 2 | 2 | 5 | 4 | **16** |
| M12 | Lo-Fi 3D Text | T3 | 3 | 3 | 2 | 5 | 5 | **18** |

### 4.3 Summary Rankings

| Rank | Mechanism | T1 | T2 | T3 | Total | Priority |
|:----:|-----------|:--:|:--:|:--:|:-----:|:--------:|
| 1 | M03 Worldview Filter | 24 | 21 | 21 | **66** | P0 |
| 2 | M02 Dialogue-as-Check | 21 | 23 | 20 | **64** | P0 |
| 3 | M07 Hallucination Engine | 11 | 25 | 25 | **61** | P0 |
| 4 | M10 Stranger NPC | 20 | 16 | 23 | **59** | P0 |
| 5 | M06 Echo System | 16 | 22 | 20 | **58** | P1 |
| 6 | M09 Three-Ending System | 19 | 19 | 20 | **58** | P1 |
| 7 | M01 Three-Axis Slider | 22 | 19 | 16 | **57** | P0 |
| 8 | M08 Borgesian Constraints | 11 | 24 | 21 | **56** | P1 |
| 9 | M12 Lo-Fi Rendering | 21 | 16 | 18 | **55** | P1 |
| 10 | M11 Hemingway Constraints | 20 | 16 | 14 | **50** | P1 |
| 11 | M04 Rain Pressure | 23 | 10 | 16 | **49** | P2 |
| 12 | M05 3-Month Clock | 15 | 13 | 8 | **36** | P3 |

### 4.4 Key Design Decisions from Scores

**Decision 1: M05 (Clock) is a removal candidate.**
At 36/75, it's 13 points below the next lowest (M04 at 49). Its T3 score (8/25) is near-zero. The clock was designed for a previous theme set (despair/hope/identity); with the new themes (alienation/uncertainty/hallucination), it has no strong mapping. **Recommendation:** Remove M05 post-MVP or keep toggleable as a niche atmospheric element.

**Decision 2: M07 Hallucination Engine needs a D3 backup.**
M07 has D3=5 for both T2 and T3 — without it, both themes lose ~25 points. M08 (Borgesian Constraints) is the strongest existing backup for T2 (D3=5). For T3, M10 (Stranger NPC, D3=4) is the closest. **Recommendation:** Bolster M10's T3 expression to cover M07's potential absence during playtest.

**Decision 3: T2 and T3 are structurally fragile despite equal totals.**
All three themes score ~223/300, but T2 and T3 rely heavily on 2-3 mechanisms. T1 has 7 mechanisms ≥20/25. Any development or playtest feedback that weakens M07 or M08 will disproportionately harm T2/T3. **Recommendation:** Ensure M06 (Echo, T2=22) and M10 (Stranger, T3=23) are fully operational before playtest.

**Decision 4: M04 (Rain) should not attempt to cover T2.**
M04's T2 score is 10/25 with D1=1 and D3=1 — rain has no natural link to uncertainty. **Recommendation:** Accept this gap. Not every mechanism needs all three themes.

---

## 5. Runtime Validation Strategy

### 5.1 Playtest Coverage Checklist

Each playtest session should verify at least one mapping chain per theme:

| Theme | Min. Mechanisms to Verify | Verification Method |
|:------|:-------------------------:|:--------------------|
| T1 Urban Alienation | M03, M04, M01 | Player survey: "Did you feel alone in the city?" |
| T2 Borgesian Uncertainty | M07, M08, M02 | Player survey: "Were you ever unsure what was real?" |
| T3 Hallucination/Reality | M07, M10, M03 | Player survey: "Did you question your own perception?" |

### 5.2 Spike Results Integration

Three spikes were proposed in PRD §7:

| Spike | Status | Impact on Design |
|:------|:------:|:-----------------|
| S1: M07 removal impact on T2/T3 | Not yet run | If T2/T3 survival >50%, M07 becomes P1. If <30%, M07 stays P0. |
| S2: Hemingway constraint perceptibility | Not yet run | If perceived gap <0.5, M11 D2 scores may need revision. |
| S3: Elimination "bounce-back" risk | Not yet run | If any eliminated mechanism has ≤1 conflict point, reconsider. |

These spikes should be prioritized before the full playtest phase.

### 5.3 Mapping Chain Drift Prevention

When a mechanism is modified in future code changes, the corresponding mapping chain must be re-verified:

- **Minor change** (e.g., M06 echo variant count): No re-validation needed.
- **Major change** (e.g., M07 hallucination formula): Re-validate affected chains in development environment.
- **New mechanism**: Must have a mapping chain written and scored before merge — gate on code review.

---

## 6. Files & Architecture Impact

### Directly Affected

| File | Change |
|:-----|:-------|
| `docs/DESIGN/220-theme-mechanism-mapping.md` | **NEW** — this document |
| `docs/TASKS/220-theme-mechanism-mapping.md` | **NEW** — task breakdown (TASKS document) |

### Indirectly Affected

| File | Change |
|:-----|:-------|
| `docs/GAME_DESIGN/01-OVERVIEW.md` | Add theme→mechanism mapping summary (§3) |
| `docs/GAME_DESIGN/06-NARRATIVE.md` | Add mapping chain references |
| `docs/PRD/42-theme-mechanic-mapping.md` | Superseded by #220 for new theme set |

---

## 7. Edge Cases & Failure Paths

### Edge Cases

1. **Mapping conflict:** M04 rain expresses T1 strongly (23) but T2 weakly (10) — accept this as a design tradeoff; rain is not an uncertainty mechanism.
2. **Mechanism stacking:** M01+M02+M03+M10 can activate simultaneously in a single scene — blur test: player should feel a **composite** thematic experience, not sensory overload.
3. **Score plateau trap:** All three themes score ~223/300 — this can mislead into believing coverage is equal across themes. In reality, T2/T3 have structural fragility.

### Failure Paths

1. **Mapping chain decoupling:** A mechanism continues working but drifts from its intended theme → establish mapping review during code review.
2. **Chain obsolescence:** New mechanisms merged without mapping chains → gate by code review requirement.
3. **Over-reliance on M07:** Its 25/25 for T2 and T3 makes removal catastrophic → develop M08→T3 and M10→T3 as backup routes.

---

> *This design document operationalizes Approach C (双向结合度矩阵 + 叙事段落) for the core theme→mechanism mapping of the three themes across 12 existing mechanisms. It provides a structured scoring matrix, narrative mapping chains, elimination candidacy analysis, and a runtime validation strategy. The TASKS document will convert these findings into actionable implementation steps.*
