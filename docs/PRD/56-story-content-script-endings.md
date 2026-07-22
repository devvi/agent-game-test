# Research: Story Content — Script for All Scenes + 3 Endings

> Parent Issue: #56
> Agent: game-research-agent
> Date: 2026-07-22

---

## 1. Problem Definition

### Current Behavior

The scene infrastructure for **Office → Street → Convenience Store** (Issue #55) is fully implemented and merged (PR #82). The three scenes exist as Godot `.tscn` files with:

- **Scene transitions**: `SceneManager.gd` handles fade-to-black scene swaps, dialogue state persistence via `GameManager.choices_history`.
- **Environmental text**: Office window text, neon sign, graffiti, street sign, store OPEN sign — all with state-dependent variants (hope/conviction thresholds).
- **Dialogue data files**: `office_door.json` (door leave/stay, store entrance prompt), `store_clerk.json` (3 branches + Stranger hints).
- **NPC dialogue**: Store clerk has 3 branches (upbeat/neutral/concern) gated by hope slider.
- **Stranger foreshadowing**: Seeded in store OPEN sign subtitle and clerk dialogue.
- **Dialogue engine**: Fully implemented (Parser, Runner, ConditionEvaluator, Display3D, HemingwayEnforcer).

However, **the game has no complete script**. Specifically:

1. **No full dialogue coverage** — Only 2 dialogue files exist covering ~3 interactions. Scenes with NPCs (bartender) have dialogue JSON but no scene integration.
2. **No environmental text completeness** — Not all scenes have all variants documented/implemented.
3. **No ending sequences** — The game has no conclusion. Three endings are defined (Keep Walking / Turn Back / Stay) but none exist as content.
4. **No intertextuality** — Zero cross-scene repeated phrases (AC2 requires at least 5).
5. **No layered narrative depth** — Lines are written at single layer; AC requires at least shallow + middle for every line.

### Expected Behavior

A complete authored script covering:

1. **All scenes**: Office, Street, Convenience Store, Underpass/Subway Station (new), and the three ending sequences.
2. **All dialogue nodes**: Every NPC interaction fully written with Hemingway-constrained text.
3. **All environmental text**: Every LoFiText3D node in every scene has complete state-variant text.
4. **Three endings**: Keep Walking (faith), Turn Back (give up), Stay (acceptance) — each with distinct emotional arc.
5. **Layered narration**: Every line has at least shallow (plot action) and middle (character subtext) layers. Deep layer (thematic metaphor) for key moments.
6. **Intertextuality**: ≥5 repeated phrases that echo across different scenes with shifted meaning.
7. **Integration**: All script content is authored as dialogue JSON files ready for the existing dialogue engine.

### User Scenarios

- **Scenario A (First-time player):** Plays through office → street → store → underpass → ending. Encounters dialogue at every interaction point. Environmental text changes subtly based on state. The ending they reach feels emotionally coherent with their choices.
- **Scenario B (Replay):** Player makes different choices → reaches a different ending. Intertextual echoes are noticed on replay (a phrase from the office appears in the underpass with reversed meaning). Each ending provides a distinct emotional resolution.
- **Scenario C (Designer/Writer):** Opens dialogue JSON files to review or modify dialogue. Every node has proper layers (shallow/middle/deep). Hemingway constraints are pre-applied. Cross-scene echoes are clearly documented.
- **Frequency:** Every playthrough. This is the entire narrative content of the game.

---

## 2. Design Intent (Feature)

### Why Does Current Behavior Exist?

The project was built in layered dependency order:
1. **Issues #42, #43** — Theme-Mechanic Mapping and scaffold.
2. **Issues #44, #46** — LoFi text rendering and dialogue engine.
3. **Issue #55** — Scene sequence architecture (Office → Street → Store).
4. **Issue #51** — Hemingway constraints (designed but not yet enforced in authored content).
5. **Issue #45** — Narrative Architecture (designed the ending graph but didn't write the actual lines).

Each layer built infrastructure. Issue #56 is the **content creation layer** — it fills the infrastructure with actual authored text.

### Why Change Now?

1. **Infrastructure is stable** — All three scenes, the dialogue engine, state system, and scene transitions are merged and tested.
2. **Narrative architecture is designed** — Issue #45 defined the ending graph and narrative echoes. The design exists; the content doesn't.
3. **Hemingway constraints are ready** — Issue #51 designed the constraint system; `hemingway_enforcer.gd` exists and is tested. The content just needs to be written to spec.
4. **Dependency chain is complete** — #55 (scenes) and #52 (dialogue runtime) are both merged. Nothing blocks content authorship.
5. **Endings are the game's climax** — Without endings, the game has no resolution. This is the highest-priority content issue (label: `priority/critical`).

### Previous Constraints

| Constraint | Detail |
|------------|--------|
| Engine | Godot 4.7.1 / GDScript 2.0 |
| Dialogue format | JSON-based, loaded by DialogueParser |
| Hemingway | Max 25 chars per sentence, max 3 sentences per paragraph; enforced by `hemingway_enforcer.gd` |
| Slider range | Hope, conviction, will — 0–10 each (5 = neutral) |
| Scene flow | Office → Street → Convenience Store → Underpass → Ending |
| Ending names | Keep Walking (faith), Turn Back (give up), Stay (acceptance) |
| Narrative layers | Shallow (plot), Middle (subtext/character), Deep (thematic metaphor) |
| Intertextuality | ≥5 repeated phrases across scenes with shifted meaning |
| Visual style | Edward Hopper urban night — dark base, warm amber light, lo-fi pixel text |
| Dialogue engine | Signal-based; JSON nodes with conditions, effects, and `"scene"` transition keys |
| Scene transitions | `change_scene_to_file()` with fade curtain |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `dialogues/office_door.json` | Office Door Dialogue | **Modified** — Expand to full layered script with all nodes |
| `dialogues/store_clerk.json` | Store Clerk Dialogue | **Modified** — Expand to full layered script with all nodes |
| `dialogues/bartender.json` | Bartender Dialogue | **Modified** — Integrate into street scene with layered narrative |
| `dialogues/underpass.json` | Underpass Dialogue | **New** — Full underpass/subway station encounter script |
| `dialogues/ending_keep_walking.json` | Ending: Keep Walking | **New** — Faith-ending dialogue and environmental text |
| `dialogues/ending_turn_back.json` | Ending: Turn Back | **New** — Give-up-ending dialogue and environmental text |
| `dialogues/ending_stay.json` | Ending: Stay | **New** — Acceptance-ending dialogue and environmental text |
| `dialogues/environmental_text_master.json` | Environmental Text | **New** — Central registry of all environmental text variants across all scenes |
| `scenes/underpass/underpass.tscn` | Underpass Scene | **New** — Subway/underpass 3D environment with LoFi text nodes |
| `scenes/underpass/underpass.gd` | Underpass Script | **New** — Configure environmental text, trigger ending choice |
| `gdscripts/ending_controller.gd` | Ending Controller | **New** — Orchestrates ending sequence: final monologue, credits trigger |
| `docs/GAME_DESIGN/06-STORY.md` | GDD | **New** — Story script documentation |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/hemingway_enforcer.gd` | Hemingway Enforcer | May need to validate authoring-time constraints (if used as `@tool`) |
| `gdscripts/scene_manager.gd` | Scene Manager | Ending sequences may need extended transition behavior (longer fades, text overlays) |
| `gdscripts/game_manager.gd` | Game Manager | May need extended `choices_history` for ending resolution |
| `scenes/main.tscn` | Main Scene | If ending sequence triggers return-to-menu |
| `tests/` | Test Suite | New dialogue JSON files need validation tests |

### Data Flow Impact

```
Player Playthrough
    │
    ├── Office Scene
    │   ├── Office door dialogue (leave/stay)
    │   ├── Window text (hope-variant)
    │   ├── Desk note (static)
    │   └── → Street (dialogue-triggered scene change)
    │
    ├── Street Scene
    │   ├── Neon sign (conviction-variant glow)
    │   ├── Graffiti (hope-variant text)
    │   ├── Street sign (static with intertextual echo)
    │   ├── Bartender encounter (optional, from bar dialogue)
    │   └── → Store entrance or walk away (choice point)
    │
    ├── Convenience Store Scene
    │   ├── OPEN sign (hope+conviction variant, Stranger foreshadowing)
    │   ├── Shelf labels (static)
    │   ├── Clerk dialogue (3 branches + Stranger hints)
    │   └── → Underpass/Station (dialogue-triggered scene change)
    │
    ├── Underpass / Subway Station Scene
    │   ├── Station sign / graffiti (intertextual echoes)
    │   ├── The Stranger apparition (final encounter, deferred to #57)
    │   ├── Final choice point (3-ending branch)
    │   └── → Ending scene based on choice
    │
    └── Endings
        ├── Keep Walking (faith) → credits
        ├── Turn Back (give up) → credits
        └── Stay (acceptance) → credits
```

### Documents to Update

- [x] **This output:** `docs/PRD/56-story-content-script-endings.md`
- [ ] `docs/DESIGN/56-story-content-script-endings.md` — Plan phase output
- [ ] `docs/GAME_DESIGN/06-STORY.md` — New GDD section: story script documentation
- [ ] `docs/GAME_DESIGN/INDEX.md` — Add 06-STORY
- [ ] `docs/GAME_DESIGN/05-DIALOGUE.md` — Add intertextuality pattern documentation

---

## 4. Solution Comparison

### Approach A: Top-Down Script-First — Write Complete Script as Design Doc, Then Fragment into Dialogue JSONs

**Description:**

Write the entire game script as a single design document (`docs/GAME_DESIGN/06-STORY.md`) covering every scene, every dialogue node, every environmental text variant, and all three endings. The document is organized by scene and structured as:

```
## Scene: Office
### Dialogue: Office Door
#### Node: office_door_prompt
- Speaker: Narrator
- Text: "The door looms in front of you. Leave the office?"
- Shallow layer: Player is at the door
- Middle layer: Hesitation before action
- Choices: [...]
### Environmental Text: Window
- Hope >= 7: "The city glitters..."
- Hope 4-6: "Rain on the glass..."
- Hope < 4: "The streetlights blur..."
```

Once the design doc is complete and reviewed, the dialogue JSON files are mechanically extracted from it (one JSON per scene/interaction). The JSONs are validated with `dialogue_parser.gd`'s schema.

**Pros:**
- Author writes once in a human-readable format — no JSON boilerplate during creative writing
- Full document can be reviewed holistically (intertextuality is visible across scenes)
- Layered annotations (shallow/middle/deep) are explicit in the doc
- Hemingway constraints can be checked on the raw text before JSON conversion
- Single source of truth for all narrative content

**Cons:**
- Two artifacts to maintain (design doc + JSON files)
- JSON extraction is a manual or semi-automated step
- The design doc doesn't directly run in the game — duplication risk
- If the design doc drifts from the JSONs, bugs emerge silently

**Risk:** Low — simple content pipeline, well-defined schema
**Effort:** 2-3 weeks (write script doc + extract to JSONs + validate + test)

---

### Approach B: Bottom-Up — Write Dialogue JSONs Directly, Annotate Layers in Comments

**Description:**

Skip the intermediate design doc. Author each dialogue JSON file directly, using JSON comments (or a `"notes"` field) to annotate layers, intertextuality markers, and Hemingway validation notes. The JSON files ARE the source of truth.

Each node carries layer metadata:
```json
{
  "id": "n_01",
  "speaker": "Narrator",
  "text": "The door looms in front of you.\nLeave the office?",
  "layers": {
    "shallow": "Player interacts with door to progress",
    "middle": "Threshold anxiety — leaving safety for the unknown",
    "deep": "The door as metaphor for every major life decision"
  },
  "choices": [...]
}
```

Intertextuality is tracked via a `"echoes"` field connecting nodes across files:
```json
{
  "echoes": [
    {"type": "phrase", "target": "store_clerk.json/clerk_greet", "phrase": "the same streets"}
  ]
}
```

**Pros:**
- Single artifact — the JSONs ARE the content, immediately runnable
- No translation/duplication step — what you write is what the game reads
- Faster iteration — edit JSON, reload game, see changes
- Layer annotations live with the data they describe

**Cons:**
- JSON is harder to read during creative writing sessions
- Cross-scene intertextuality is harder to review (must grep across files)
- Hemingway constraints must be checked after writing, not during
- No single document that "tells the whole story" for reviewer

**Risk:** Low-Medium — ergonomics are the main concern
**Effort:** 2-3 weeks (write JSONs directly + validate + test)

---

### Approach C: Hybrid — Script-First Design Doc, Auto-Extract JSONs via Tool

**Description:**

Write the full script as a formatted markdown document (Approach A). Then create a `@tool` GDScript or Python script (`scripts/extract_dialogue.py`) that parses the markdown and emits the JSON files automatically.

The markdown format is structured so it's both human-readable and machine-parseable:

```markdown
## [office_door] Office Door
### Node: office_door_prompt
Speaker: Narrator
Text: The door looms in front of you. Leave the office?
Shallow: Player interacts with door
Middle: Threshold anxiety
Choice: Step outside → office_door_leave (effect: conviction+0.5, scene: street)
Choice: Stay a while longer → office_stay
```

The extraction script validates Hemingway constraints, checks layer completeness, and flags missing cross-references before emitting JSON.

**Pros:**
- Best of both approaches — author in markdown, run tool, get JSONs
- Validation happens at conversion time (Hemingway, layers, echoes)
- Single source of truth (markdown design doc)
- Can integrate into CI: markdown change → tool runs → JSON diff in PR

**Cons:**
- Most complex pipeline — markdown parser + JSON emitter to build and maintain
- Markdown format must be rigid enough for parsing but flexible enough for creative writing
- Tool development adds 1-2 days to the effort estimate
- Edge cases in markdown parsing can silently produce bad JSON

**Risk:** Medium — pipeline complexity, but each piece is small
**Effort:** 3-4 weeks (write script + build extractor + validate + test)

---

### Recommendation

**→ Approach A (Top-Down Script-First)** with the following refinements:

1. **Single design doc as source of truth:** Write `docs/GAME_DESIGN/06-STORY.md` with the complete script, organized by scene, with explicit layer annotations and intertextuality markers.
2. **Manual JSON extraction:** After the design doc is written, manually create dialogue JSON files from it. At this project scale (~7 dialogue files, ~40-50 nodes total), tool-building overhead exceeds manual effort.
3. **Validation pass:** After extraction, validate each JSON with `dialogue_parser.gd`'s `@tool` mode, then run a Hemingway check manually before committing.
4. **Layer completeness checklist:** After all JSONs are written, do a layer audit — every node must have shallow + middle layers documented in the design doc. Deep layer is required for ending sequences and Stranger-related nodes.

**Why not Approach B?** Writing directly in JSON is fine for a single scene but breaks creative flow when writing the entire story. A designer needs to see the full arc across all scenes, which a prose document provides.

**Why not Approach C?** The project has ~14-21 major interactions (from Issue #5 spike). At this scale, a JSON extraction tool saves at most 1-2 hours of work but adds 1-2 days of development. Manual extraction is simpler and more transparent.

---

## 5. Boundary Conditions & Acceptance Criteria

### 5.1 Scene-by-Scene Script Outline

#### Scene 1: Office

**Environmental Text:**
- **Window text** (LoFiText3D, Billboard mode, front wall):
  - `hope >= 7`: "The city glitters through the rain. Tonight could be different."
  - `hope >= 4, < 7`: "Rain on the glass. Another night at the office."
  - `hope < 4`: "The streetlights blur. One more night. One more."
  - *(All variants include intertextual anchor: "Somewhere out there...")*
  
- **Desk note** (LoFiText3D, Flat Sign mode, on desk):
  - Static: "⌈Remember:⌋ Check the door."
  - *(Intertextual echo #1: "Check the door" reappears in Underpass)*

**Dialogue — Office Door:**
- `office_door_prompt` (Narrator): "The door looms in front of you. Leave the office?"
  - Choice A: "Step outside." → scene: street.tscn, effect: conviction+0.5
  - Choice B: "Stay a while longer." → `office_stay`
  
- `office_stay` (Narrator): "You sit back down. The rain taps at the window. The door is still there."
  - Choice A: "Step outside." → scene: street.tscn, effect: conviction+0.3
  - Choice B: "Not yet." → null (end)
  
- *Layers: Shallow=player decides to leave or stay. Middle=fear of change vs comfort of routine. Deep=the door as boundary between stasis and journey.*

#### Scene 2: Street

**Environmental Text:**
- **Neon sign** (LoFiText3D, Emissive, warm amber):
  - `conviction >= 7`: "YOU'RE STILL HERE" — warm amber, steady
  - `conviction >= 4, < 7`: "YOU'RE STILL HERE" — dim amber, flickering
  - `conviction < 4`: "YOU'RE STILL HERE" — dim red, barely lit
  - *(Intertextual echo #2: "YOU'RE STILL HERE" — constant across conviction levels, but the emotional TONE shifts)*

- **Graffiti** (LoFiText3D, Flat Sign, wall):
  - `hope >= 6`: "this too shall pass" — faded but legible
  - `hope < 6`: "i was here" — partially scratched
  - *(Intertextual echo #3: "i was here" reappears in Underpass)*

- **Street sign** (LoFiText3D, Billboard):
  - Static: "ELM ST."
  - *(Intertextual echo #4: "ELM ST." is the only named location; its letters are echoed in the Underpass graffiti as "ELM...")*

**Dialogue — Store Entrance:**
- `store_entrance_prompt` (Narrator): "The convenience store glows through the rain. Enter?"
  - Choice A: "Go in." → scene: store.tscn
  - Choice B: "Keep walking." → `street_walk_away`
  
- `street_walk_away` (Narrator): "You walk past. The rain keeps falling. The neon sign flickers behind you. ⌈YOU'RE STILL HERE.⌋"
  - Choice: "..." → null (end)

**Dialogue — Bartender (Optional Encounter):**
- Triggered if player approaches the bar area in the street scene
- `npc_bartender_greet` (Bartender): "You again. Same as usual?"
  - Choice A (unconditional): "Yeah, the usual." → `npc_bartender_drink` (effect: hope+1)
  - Choice B (despair ≤ 5): "Not tonight." → `npc_bartender_leave` 
  - Choice C (despair ≥ 7): "... " → `npc_bartender_silent` (effect: despair+1)

- `npc_bartender_drink` (Bartender): "One glass of warm sake, coming up."
  - Choice: "Thanks." → null (effect: hope+1)

- `npc_bartender_leave` (Bartender): "Suit yourself."
  - Choice: "See you." → null

- `npc_bartender_silent` (Bartender): "... Right."
  - Choice: "..." → null

#### Scene 3: Convenience Store

**Environmental Text:**
- **OPEN sign** (LoFiText3D, Emissive):
  - `hope >= 5 and conviction >= 4`: "OPEN ⌈He was here tonight.⌋"
  - Otherwise: "OPEN"
  
- **Shelf labels** (LoFiText3D, Flat Sign):
  - Static: "⌈Instant noodles / Canned coffee⌋"
  - *(Intertextual echo #5: "instant" vs "lasting" — the shelf goods are instant, the ending is lasting)*

**Dialogue — Store Clerk:**
- `clerk_greet` (Clerk): "Evening."
  - Choice A (hope ≥ 7): upbeat branch → `clerk_upbeat`
  - Choice B (hope ≥ 4): neutral branch → `clerk_neutral`
  - Choice C (hope < 4): concern branch → `clerk_concern`
  - Choice D (fallback): silent branch → `clerk_silent`

- `clerk_upbeat` (Clerk): "You look... actually okay tonight."
  - Choice A: "Yeah. It's a good night." → `clerk_upbeat_choice` (hope+0.5)
  - Choice B: "Thanks. Just passing through." → `clerk_farewell`

- `clerk_upbeat_choice` (Clerk): "Good to hear. You know, most people who come in this late don't say that. ⌈He was here earlier. Said the same thing.⌋"
  - Choice A: "He? Who?" → `clerk_stranger_hint` (flag: asked_about_stranger)
  - Choice B: "I should get going." → `clerk_farewell`

- `clerk_stranger_hint` (Clerk): "Just a regular. Tall. Wears a coat even inside. ⌈You'll know him when you see him.⌋"
  - Choice: "... Right." → `clerk_farewell` (flag: stranger_hint_received)

- `clerk_neutral` (Clerk): "Evening. The usual?"
  - Choice A: "Yeah. Same as always." → `clerk_farewell` (hope+0.3)
  - Choice B: "Not tonight. Just looking." → `clerk_farewell`

- `clerk_concern` (Clerk): "Rough night? You look tired."
  - Choice A: "You have no idea." → `clerk_farewell` (hope+0.5)
  - Choice B: "I'm fine." → `clerk_farewell`
  - Choice C: "... " → `clerk_silent` (despair+0.3)

- `clerk_silent` (Clerk): "... Right."
  - Choice: "... " → null

- `clerk_farewell` (Clerk): "Take care."
  - Choice: "You too." → null
  - *(Deep layer: "Take care" is both a farewell and a thematic instruction — from here the player will need to "take care" of their own path)*

- **After clerk dialogue ends**, scene transitions to Underpass:
  - *(In store.gd: after dialogue_ended signal, transition to underpass.tscn)*

#### Scene 4: Underpass / Subway Station (New Scene)

> A new 3D environment: tunnel walls, dim fluorescent lights, a single bench. The Stranger is absent (deferred to #57) but their presence is felt — a coat draped over the bench, footsteps echoing. The player faces themselves.

**Environmental Text:**
- **Tunnel wall graffiti** (LoFiText3D, Flat Sign):
  - `hope >= 5`: "the same streets / the same night" — white chalk, clear
  - `hope < 5`: "el m... / t... s... st..." — partially faded
  - *(Intertextual echo #1: "the same streets" from office window. Echo #4: "ELM" fragments from street sign)*

- **Subway sign** (LoFiText3D, Billboard, dim):
  - Static: "⌈NEXT TRAIN⌋ — Platform 3"
  - *(Intertextual echo: "NEXT" vs the choice to Keep Walking or Turn Back)*

- **Floor text** (LoFiText3D, Flat Sign, at feet):
  - `conviction >= 7`: "i was here" — carved into the floor
  - `conviction < 7`: "i w s here" — worn away
  - *(Intertextual echo #3: "i was here" from street graffiti)*

- **Wall poster** (LoFiText3D, Billboard):
  - Static: "⌈Check the door before leaving⌋" — a faded maintenance notice
  - *(Intertextual echo #1 callback: "Check the door" from office desk note — now with reversed meaning: leaving is the point)*

**Dialogue — Final Choice (The Crossroads):**

- `underpass_arrival` (Inner Voice): "The tunnel splits three ways. The rain echoes behind you. Ahead, the dark swallows the light."
  - *(Deep layer: Three paths = three approaches to existential crisis)*
  - Choice A: "Keep walking." → `ending_keep_walking_intro` (scene: ending_keep_walking)
  - Choice B: "Turn back." → `ending_turn_back_intro` (scene: ending_turn_back)
  - Choice C: "Sit down. Stay." → `ending_stay_intro` (scene: ending_stay)

#### Ending 1: Keep Walking (Faith)

> Emotional arc: *Uncertainty → Determination → Faith*. The player walks into the dark tunnel. The path is unclear, the destination unknown. But they keep moving.

**Environmental Text:**
- Tunnel walls: "⌈One foot after another.⌋" — looping, encouraging
- As player walks: flickering lights, then a faint glow ahead

**Dialogue Sequence:**
- `keep_walking_01` (Inner Voice): "The tunnel stretches. You can't see the end. But your feet keep moving."
  - Choice: "... Keep walking." → `keep_walking_02`

- `keep_walking_02` (Inner Voice): "You remember the office. The window. The rain. You remember why you left."
  - Choice: "Because staying wasn't living." → `keep_walking_03`

- `keep_walking_03` (Inner Voice): "The glow ahead grows brighter. You don't know what's there. But you believe it's worth reaching."
  - Choice: "I believe." → `keep_walking_end`
  - *(Deep layer: Faith = action without certainty. The player chooses to move despite not knowing.)*

- `keep_walking_end` (Narrator): "You step into the light. The rain stops. Somewhere, a door opens."
  - *Scene fades to white.*
  - *Credits roll.*
  - *(Deep layer: Faith is not about answers — it's about continuing the question.)*

**State Effects:**
- `hope +2`, `conviction +2`, `will +1`
- Flag: `ending_keep_walking`

#### Ending 2: Turn Back (Give Up)

> Emotional arc: *Exhaustion → Resignation → Surrender*. The player cannot face the dark tunnel. They turn and walk back the way they came, through the scenes they already visited, now empty and hollowed.

**Environmental Text:**
- Reversed street: neon sign is dark. Graffiti: "it's over"
- Reversed office: door is locked from the outside

**Dialogue Sequence:**
- `turn_back_01` (Inner Voice): "You turn. The street looks the same. But everything is different."
  - Choice: "... This was a mistake." → `turn_back_02`

- `turn_back_02` (Inner Voice): "The neon sign is dark. ⌈YOU'RE STILL HERE⌋ — but the light is gone."
  - Choice: "I can't do this." → `turn_back_03`
  - *(Intertextual echo #2: "YOU'RE STILL HERE" — now spoken by a dead sign)*

- `turn_back_03` (Inner Voice): "The office door is locked. From the outside. You can't go home again."
  - Choice: "There's nowhere left." → `turn_back_end`
  - *(Intertextual echo #1 callback: "Check the door" — but now you can't go back in)*

- `turn_back_end` (Narrator): "You sit on the curb. The rain falls. The street stretches empty. You don't get up."
  - *Scene fades to black.*
  - *Credits roll.*
  - *(Deep layer: Giving up is not failure — it's a choice too. The tragedy is that the door is locked.)*

**State Effects:**
- `hope -2`, `conviction -2`, `will -1`
- Flag: `ending_turn_back`

#### Ending 3: Stay (Acceptance)

> Emotional arc: *Struggle → Stillness → Acceptance*. The player sits in the underpass. The Stranger does not come. The train does not arrive. Nothing happens — and that is the point.

**Environmental Text:**
- Floor: "i am here" carved beneath the player
- Wall: "this too shall not pass" — the graffiti has changed
  - *(Intertextual echo #3 inverted: "this too shall pass" → "this too shall not pass")*

**Dialogue Sequence:**
- `stay_01` (Inner Voice): "You sit. The concrete is cold. The tunnel is quiet. Nothing happens."
  - Choice: "... I'll wait." → `stay_02`

- `stay_02` (Inner Voice): "Minutes pass. Or hours. The train doesn't come. The Stranger doesn't come."
  - Choice: "I'm not waiting for anything." → `stay_03`
  - *(Deep layer: Waiting without expectation = acceptance)*

- `stay_03` (Inner Voice): "The rain stops. The neon sign flickers off somewhere above. You're still here. And that's enough."
  - Choice: "Yes. This is enough." → `stay_end`

- `stay_end` (Narrator): "You close your eyes. The tunnel hums. Not with trains — with silence. You breathe. You are here. You stay."
  - *Scene slowly fades to black.*
  - *Credits roll.*
  - *(Deep layer: Acceptance is the hardest kind of faith — to be still without needing to go anywhere or be anyone.)*

**State Effects:**
- `hope +1`, `will +2`, `conviction 0`
- Flag: `ending_stay`

### 5.2 Intertextuality Matrix (AC2 — ≥5 Instances)

| # | Phrase | First Appearance | Reappearance | Meaning Shift |
|---|--------|-----------------|---------------|---------------|
| 1 | "Check the door" | Office desk note (instruction to leave) | Underpass wall poster (maintenance notice) | Safety instruction → existential reminder that leaving was the right choice |
| 2 | "YOU'RE STILL HERE" | Street neon sign (conviction-variant glow) | Turn Back ending (sign is dark, phrase is hollow) | Welcome → accusation. The same words, now spoken by darkness |
| 3 | "i was here" | Street graffiti (hope-variant) | Underpass floor (conviction-variant) + Stay ending floor | Ephemeral claim of existence → permanent record of experience |
| 4 | "ELM ST." | Street sign (static, named location) | Underpass graffiti ("el m... t... s st..." fragment) | Concrete place name → eroded memory of a place |
| 5 | "this too shall pass" | Street graffiti (hope ≥ 6 variant) | Stay ending wall ("this too shall not pass") | Comforting platitude → inverted: some things stay. The moment, the pain, the self |
| 6 | "Take care" | Clerk farewell dialogue | Narrator epilogue in all three endings | Casual farewell → thematic command: take care of yourself, take care of your choice |
| 7 | "the same streets" | Office window text (all variants, intertextual anchor) | Underpass graffiti ("the same streets / the same night") | Physical description → existential loop — are you walking different streets or the same ones forever? |

### 5.3 Normal Path

1. **AC1 (Shallow — 100% coverage):** Player starts in Office → interacts with door (dialogue fires) → Street → interacts with store entrance (dialogue fires) → Store → interacts with clerk (dialogue fires) → after clerk dialogue ends, transition to Underpass → final choice → one of three endings. Every single scene has dialogue and environmental text. Zero scenes are silent.
2. **AC2 (Middle — 5+ intertextual instances):** During a playthrough, the player encounters at least 5 intertextual echoes. A replay reveals more (the graffiti "i was here" is noticed on second play). The echoes are not Easter eggs — they are central to the narrative structure.
3. **AC3 (Deep — 3 distinct emotional arcs):** D1 Keep Walking: faith arc (uncertainty → determination → belief). D2 Turn Back: give-up arc (exhaustion → resignation → surrender). D3 Stay: acceptance arc (struggle → stillness → peace).

### 5.4 Edge Cases

1. **State at ending thresholds:** If hope = 0 or hope = 10, all environmental text variants still have a matching threshold (boundaries use >= and <).
2. **All clerk choices gated:** If player state satisfies zero conditions for current clerk node, fallback default choice is used. If no default exists, conversation ends gracefully.
3. **Player skips store clerk dialogue entirely:** The game still proceeds to Underpass via a "walk past" trigger. Clerk dialogue is not mandatory for reaching endings.
4. **Player triggered bartender but skipped store:** All three endings remain reachable regardless of which optional NPCs were encountered.
5. **Rapid ending selection:** Underpass final choice has a 1-second confirmation delay (prevent accidental ending selection).
6. **Ending replay:** After credits, player returns to main menu or last save. Global ending flags persist for New Game+ awareness.

### 5.5 Failure Paths

1. **Missing dialogue JSON for a scene:** If any dialogue JSON file is missing at runtime, `DialogueRunner.start()` returns false. The scene script handles this by showing fallback environmental text and allowing progression via proximity triggers (no deadlock).
2. **Underpass scene file missing:** If `underpass.tscn` doesn't exist, the clerk dialogue's `after_dialogue` transition can't fire. Mitigation: store.gd checks for the file existence before emitting the scene transition signal.
3. **Ending scene files missing:** Three ending `.tscn` files needed. If one is missing, the player cannot choose that ending path. Mitigation: all three paths converge to a single fallback ending (Stay) with an error log.
4. **Hemingway violation in authored text:** Any line exceeding 25 chars per sentence or 3 sentences per paragraph must be flagged. The design doc is pre-checked; JSON extraction includes a manual Hemingway audit.

> These directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| Issue #55 — Scene sequence (Office → Street → Store) | ✅ Merged (PR #82) | **Low** — Scenes exist and work |
| Issue #52 — Dialogue Runtime + Visual | ✅ Merged (PR #83) | **Low** — Dialogue engine fully functional |
| Issue #51 — Hemingway Constraints | ☑️ Designed, not implemented | **Low-Medium** — `hemingway_enforcer.gd` exists and is tested; content just needs to adhere to it |
| Issue #45 — Narrative Architecture | ☑️ Designed, PRD exists | **Low** — Ending graph is designed; this issue produces the actual content |
| Issue #40 (or #42) — Theme-Mechanic Mapping | ✅ Merged | **Low** — Mapping defined |
| Godot 4.7.1 | Stable | **Low** |

**Dependency chain map:**
```
#45 Narrative Architecture (ending graph design)
  └── #51 Hemingway Constraints (writing rules)
        └── #55 Scene Sequence (3D environments)
              ├── #52 Dialogue Runtime (display engine)
              └── #56 (this issue) ← produces the actual content
```

### Blocks

| Future Work | Priority |
|-------------|----------|
| Issue #57 — Stranger NPC Encounter | **Critical** — This issue seeds Stranger foreshadowing (store clerk dialogue, OPEN sign), which #57's full encounter depends on |
| Issue #59 — Game menu / title screen | Medium — Not blocked |
| Localization / i18n | Low — Content must be finalized before translation |

### Preparation Needed

- [ ] **Underpass scene creation:** New `scenes/underpass/underpass.tscn` with tunnel geometry, lighting, and environmental text Label3D nodes.
- [ ] **Ending scene files:** Three minimal scenes or sequences for Keep Walking (white fade), Turn Back (black fade), Stay (slow fade).
- [ ] **EndingController.gd:** New script that triggers the ending sequence: play final monologue, apply final state changes, roll credits, return to menu.
- [ ] **Dialogue JSON expansion:** Expand `office_door.json` with final nodes; expand `store_clerk.json` with after-dialogue transition to underpass; create `underpass.json` and three ending JSON files.
- [ ] **Documentation:** `docs/GAME_DESIGN/06-STORY.md` — the full script document.
- [ ] **Intertextuality audit:** After all JSONs are written, verify all 7 intertextual echoes are present.

---

## 7. Spike / Experiment (Mandatory — depth/deep)

### Spike 1: Environmental Text Readability in Underpass Lighting

**Question to Answer:**

The Underpass scene uses dim fluorescent lighting (low ambient, cold color temperature). Can LoFiText3D labels with low contrast (faded graffiti, dim text) still be readable at typical camera distance (2-4 meters)?

**Method:**

1. Create a minimal test scene (`scenes/test_underpass_lighting.tscn`) with tunnel-like lighting: ambient = `#0a0a14`, a single OmniLight3D with cold color (0.3, 0.4, 0.6) at low energy (0.3).
2. Place 3 LoFiText3D labels at distances 2m, 3m, 4m with the proposed environmental texts.
3. Open in Godot editor, evaluate readability at the intended camera position.
4. Test three contrast levels: `modulate = Color(0.8, 0.8, 0.9, 0.8)` (bright), `Color(0.5, 0.5, 0.6, 0.6)` (medium/faded), `Color(0.3, 0.3, 0.4, 0.4)` (barely visible).
5. Screenshot each variant and assess text legibility.

**Expected Result:**

- Medium contrast (0.5, 0.5, 0.6, 0.6) with emissive glow enabled is readable at 3m.
- Barely-visible variant (0.3, 0.3, 0.4, 0.4) may need emissive boost or should be reserved for high-conviction-only variants.
- Recommendation: Set Underpass text modulate to `>= 0.5` alpha with emissive glow enabled on all texts.

**Impact on Approach:**

If text is unreadable at intended distances, we may need to:
- Move camera closer in Underpass scene
- Use Billboard mode exclusively (instead of Flat Sign for wall graffiti)
- Increase LoFiText3D pixel size for Underpass only
- Add a subtle glow behind text (a separate emissive plane)

This would increase Underpass scene complexity but not change the script content.

---

### Spike 2: Ending Sequence Transition Pattern

**Question to Answer:**

What is the cleanest implementation pattern for the ending sequences — a separate scene per ending, or an in-place cinematic in the underpass scene?

**Method:**

1. Prototype three approaches in GDScript:
   - **Approach A (Separate scenes):** Three `.tscn` files (`ending_keep_walking.tscn`, etc.), each with its own 3D environment, camera path, and text nodes. Transition via `change_scene_to_file()`.
   - **Approach B (In-place with camera animation):** All three endings play out in the underpass scene. The camera path changes based on choice (look down tunnel, look back, stay seated). Text overlays update via script.
   - **Approach C (CanvasLayer overlay):** The ending plays as a full-screen text overlay (CanvasLayer) on top of the underpass scene. No scene change, no camera movement — pure text + fade.

2. Test each prototype with the "Keep Walking" ending script (3-4 dialogue nodes).
3. Measure: implementation effort (lines of code), visual quality, and maintenance burden.

**Expected Result:**

- **Approach A** is cleanest for content separation but requires 3 new scenes with environment setup.
- **Approach B** is most immersive but requires complex camera animation and per-ending conditional logic in the same script.
- **Approach C** is simplest (no new scenes, no camera work) but feels the least like a 3D game ending.

**Expected recommendation:** Approach C (CanvasLayer overlay) for endings, because:
- The endings are text-driven (dialogue + environmental narration)
- Full-screen text with fade effects matches the game's interactive fiction / visual novel DNA
- Zero scene load time and no 3D environment overhead
- Can be implemented in ~50 lines of GDScript in `EndingController.gd`

**Impact on Approach:**

If Approach C is chosen, the Plan phase can skip creating 3 ending `.tscn` files and instead focus on `EndingController.gd` + CanvasLayer text sequences. This reduces scene count from 4 (underpass + 3 endings) to 1 (underpass).

---

### Spike 3: Dialogue JSON Schema Validation for Hemingway + Layers

**Question to Answer:**

Can we validate all acceptance criteria (Hemingway constraints, layer completeness, intertextuality references) at dialogue JSON load time using the existing `DialogueParser.gd` infrastructure?

**Method:**

1. Extend `dialogue_parser.gd` (or create a new `dialogue_validator.gd` `@tool` script) with validation functions:
   - `validate_hemingway(dialogue_data)` → returns list of violations (node_id, sentence, character count)
   - `validate_layers(dialogue_data)` → checks every node has `layers.shallow` and `layers.middle` fields
   - `validate_intertextuality(dialogue_data, all_dialogues)` → checks that referenced echo targets exist

2. Test against `office_door.json`:
   - Add Hemingway-violating line ("The door looms in front of you and it seems to stretch up into the darkness forever, a monolith of wood and paint and time." — 96 chars)
   - Verify the validator catches it

3. Test with a valid file and confirm zero false positives.

**Expected Result:**

The validator correctly:
- Detects all Hemingway violations (per-line char count, per-node sentence count)
- Flags nodes missing layer annotations
- Detects dangling intertextual references (echo target node doesn't exist)

**Impact on Approach:**

If validation can be automated, it becomes part of the CI pipeline (run on PR creation). This reduces the manual audit burden from "exhaustive" to "spot-check." If not feasible (GDScript tool limitations), validation remains a manual checklist in the Plan phase.

**Recommendation:** Build the validator regardless — even if not CI-integrated immediately, running it locally during content authorship catches 90% of issues before they reach the game.

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*

The game currently has three fully-implemented scenes (Office, Street, Convenience Store) with scene transitions, state-aware environmental text, and NPC dialogue. The dialogue engine is complete with JSON-driven nodes, condition evaluation, and Hemingway enforcement.

**What exists now:**
- `dialogues/office_door.json` — Office door + store entrance (8 nodes, mostly for scene transitions)
- `dialogues/store_clerk.json` — Clerk dialogue (8 nodes, 3 branches, Stranger hints)
- `dialogues/bartender.json` — Bartender dialogue (4 nodes, not yet integrated into a scene)
- `scenes/office/` — Office 3D environment (desk, window, door, lighting, trigger zones)
- `scenes/street/` — Street 3D environment (buildings, neon, graffiti, store entrance)
- `scenes/store/` — Store 3D environment (counter, shelving, OPEN sign, clerk NPC)
- `gdscripts/office.gd`, `street.gd`, `store.gd` — Per-scene scripts for environmental text and triggers
- `gdscripts/scene_manager.gd` — Fade transitions, dialogue state persistence

**What needs to be built:**
1. **Underpass scene** — New 3D environment with tunnel walls, dim lighting, graffiti/sign text nodes
2. **Ending sequence infrastructure** — `EndingController.gd` for CanvasLayer text overlays (Spike 2 recommendation)
3. **Dialogue JSON files** — Expanded/created for all 7 interactions across the full scene flow
4. **Story design doc** — `docs/GAME_DESIGN/06-STORY.md` with full annotated script

**The complete dialogue JSON landscape after this issue:**

| File | Purpose | Node Count (est.) |
|------|---------|-------------------|
| `dialogues/office_door.json` | Office door leave/stay + store entrance | 8 (minor expansion) |
| `dialogues/store_clerk.json` | Clerk 3-branch conversation | 8 (minor expansion) |
| `dialogues/bartender.json` | Optional street bar encounter | 4 (unmodified, integrate) |
| `dialogues/underpass.json` | Underpass arrival + final 3-choice branch | 4 (new) |
| `dialogues/ending_keep_walking.json` | Faith ending monologue | 4 (new) |
| `dialogues/ending_turn_back.json` | Give-up ending monologue | 4 (new) |
| `dialogues/ending_stay.json` | Acceptance ending monologue | 4 (new) |
| **Total** | | **~36 nodes** |

**Key design decisions for the Plan agent:**
1. **Underpass scene geometry** — Use existing CSGBox3D patterns (like office/street/store) for tunnel walls, floor, and ceiling. No complex meshes needed.
2. **EndingController.gd design** — CanvasLayer overlay approach: full-screen ColorRect for fade, Label3D for monologue text, AnimationPlayer for timing. ~50-80 lines of GDScript.
3. **Bartender integration** — Either add bar geometry to the street scene or keep it as a separate optional encounter zone.
4. **Dialogue JSON structure** — Each ending gets its own JSON file for modularity, loaded by EndingsController when the player makes their final choice.
5. **Intertextuality enforcement** — Use the intertextuality matrix (Section 5.2) as a checklist during implementation. Each echo must be verified in the authored JSON.

**The main risk** is scope creep on the Underpass scene (wanting to make it too complex). Keep it simple: a tunnel with walls, floor, ceiling, one bench, a few text nodes, and dim lighting. The endings themselves are CanvasLayer text overlays — no new 3D environments needed for them.
