# Design: #56 — [Content] Story Content — Script for All Scenes + 3 Endings

> Parent Issue: #56
> Agent: plan-agent
> Date: 2026-07-22

---

## 1. Architecture Overview

### Core Idea

Write the game's complete narrative content using **Approach A (Top-Down Script-First)**: author the full script as `docs/GAME_DESIGN/06-STORY.md`, then manually extract dialogue JSON files from it. The script covers all five scenes (Office, Street, Convenience Store, Underpass/Subway Station) and three endings (Keep Walking / Turn Back / Stay), with layered narration (shallow + middle for every node, deep for key moments), ≥7 intertextual echoes, and Hemingway-constrained text.

### Narrative Flow

```
Office Scene
  ├── Door dialogue (leave/stay) → conviction tracked
  ├── Window text (hope-variant)
  └── Desk note (static, intertextual anchor)
        │
        ▼
Street Scene
  ├── Neon sign (conviction-variant glow)
  ├── Graffiti (hope-variant)
  ├── Street sign (static, intertextual anchor)
  ├── Bartender encounter (optional, if approached)
  └── Store entrance choice (enter or walk away)
        │
        ▼
Convenience Store Scene
  ├── OPEN sign (hope+conviction variant, Stranger foreshadowing)
  ├── Shelf labels (static)
  └── Clerk dialogue (3 branches + Stranger hints)
        │
        ▼
Underpass / Subway Station (NEW)
  ├── Tunnel graffiti (intertextual echoes #1, #3, #4, #7)
  ├── Subway sign (static, intertextual anchor)
  ├── Floor text (conviction-variant, echo #3)
  ├── Wall poster (echo #1 callback)
  └── Final 3-choice branch → ending
        │
        ├──► Keep Walking (faith) — CanvasLayer text overlay
        ├──► Turn Back (give up) — CanvasLayer text overlay
        └──► Stay (acceptance) — CanvasLayer text overlay
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Content authorship approach | **Approach A** — Script-first design doc, manual JSON extraction | ~36 nodes across 7 files; tool-building overhead exceeds manual effort at this scale |
| Ending presentation | **CanvasLayer overlay** (Spike 2 recommendation) | No new 3D scenes needed; match game's VN DNA; ~50 lines in EndingController.gd |
| Dialogue JSON structure | **One file per scene/encounter** | Modular; each ending gets own JSON; loaded by EndingController on final choice |
| Intertextuality tracking | **Matrix in design doc** (Section 5.2 of PRD) | 7 documented echoes across scenes; verified during implementation audit |
| Hemingway enforcement | **Manual audit** on authored text + optional `@tool` validator | Existing `hemingway_enforcer.gd` can be run manually; CI integration deferred |
| Underpass scene geometry | **CSGBox3D** patterns (same as office/street/store) | No complex meshes; keep scope minimal — tunnel, bench, text nodes, dim lighting |
| Bartender integration | **Keep existing structure**; integrate via street scene trigger zone | Already has dialogue JSON (4 nodes); just needs scene trigger connection |
| State system | **Existing GameManager + StateSystem** autoloads | hope/conviction/will tracked per scene; persistence across transitions already works |

---

## 2. Content Architecture

### 2.1 Scene-by-Scene Script Outline

The full annotated script lives in `docs/GAME_DESIGN/06-STORY.md`. Below is the structural summary:

#### Scene 1: Office

| Element | Type | State Variants | Intertextual Echo |
|---------|------|----------------|-------------------|
| Window text | LoFiText3D (Billboard) | hope >=7 / >=4 / <4 | Anchor: "Somewhere out there..." |
| Desk note | LoFiText3D (Flat Sign) | Static | Echo #1: "Check the door" |
| Office door dialogue | JSON (office_door.json) | 2 nodes: prompt + stay | Conviction tracking on leave |

#### Scene 2: Street

| Element | Type | State Variants | Intertextual Echo |
|---------|------|----------------|-------------------|
| Neon sign | LoFiText3D (Emissive) | conviction >=7 / >=4 / <4 | Echo #2: "YOU'RE STILL HERE" |
| Graffiti | LoFiText3D (Flat Sign) | hope >=6 / <6 | Echo #3: "i was here" |
| Street sign | LoFiText3D (Billboard) | Static | Echo #4: "ELM ST." |
| Store entrance dialogue | JSON (office_door.json) | 2 nodes: enter/walk away | — |
| Bartender dialogue | JSON (bartender.json) | 3 branches (optional) | — |

#### Scene 3: Convenience Store

| Element | Type | State Variants | Intertextual Echo |
|---------|------|----------------|-------------------|
| OPEN sign | LoFiText3D (Emissive) | hope>=5 && conviction>=4 | Stranger foreshadowing text |
| Shelf labels | LoFiText3D (Flat Sign) | Static | Echo #5: "instant" vs "lasting" |
| Clerk dialogue | JSON (store_clerk.json) | 3 branches + stranger hints | Echo #6: "Take care" |

#### Scene 4: Underpass / Subway Station (NEW)

| Element | Type | State Variants | Intertextual Echo |
|---------|------|----------------|-------------------|
| Tunnel wall graffiti | LoFiText3D (Flat Sign) | hope >=5 / <5 | Echoes #1, #4, #7 |
| Subway sign | LoFiText3D (Billboard) | Static | "NEXT TRAIN" — thematic |
| Floor text | LoFiText3D (Flat Sign) | conviction >=7 / <7 | Echo #3: "i was here" |
| Wall poster | LoFiText3D (Billboard) | Static | Echo #1 callback: "Check the door" |
| Final choice dialogue | JSON (underpass.json) | 3-ending branch | — |

#### Endings (CanvasLayer Overlay)

| Ending | Emotional Arc | State Effects | Intertextual Callbacks |
|--------|---------------|---------------|------------------------|
| Keep Walking (Faith) | Uncertainty → Determination → Faith | hope+2, conviction+2, will+1 | — |
| Turn Back (Give Up) | Exhaustion → Resignation → Surrender | hope-2, conviction-2, will-1 | Echo #2 (dead sign), Echo #1 callback |
| Stay (Acceptance) | Struggle → Stillness → Peace | hope+1, will+2 | Echo #3 inverted, Echo #5 inverted |

### 2.2 Intertextuality Matrix (7 Instances)

| # | Phrase | First Appearance | Reappearance | Meaning Shift |
|---|--------|-----------------|---------------|---------------|
| 1 | "Check the door" | Office desk note | Underpass wall poster | Instruction → existential reminder |
| 2 | "YOU'RE STILL HERE" | Street neon sign | Turn Back ending (dark sign) | Welcome → accusation |
| 3 | "i was here" | Street graffiti | Underpass floor / Stay ending | Ephemeral → permanent |
| 4 | "ELM ST." | Street sign | Underpass graffiti fragment | Concrete → eroded memory |
| 5 | "this too shall pass" | Street graffiti | Stay ending wall (inverted) | Platitude → inverted truth |
| 6 | "Take care" | Clerk farewell | Narrator epilogue (all endings) | Farewell → thematic command |
| 7 | "the same streets" | Office window text | Underpass graffiti | Description → existential loop |

### 2.3 Dialogue JSON Landscape

| File | Purpose | Est. Nodes |
|------|---------|------------|
| `dialogues/office_door.json` | Office door + store entrance | 8 (minor expansion) |
| `dialogues/store_clerk.json` | Clerk 3-branch conversation | 8 (minor expansion) |
| `dialogues/bartender.json` | Optional street bar encounter | 4 (unmodified, integrate) |
| `dialogues/underpass.json` | Underpass arrival + final 3-choice | 4 (new) |
| `dialogues/ending_keep_walking.json` | Faith ending monologue | 4 (new) |
| `dialogues/ending_turn_back.json` | Give-up ending monologue | 4 (new) |
| `dialogues/ending_stay.json` | Acceptance ending monologue | 4 (new) |
| **Total** | | **~36** |

---

## 3. Scene / Node Tree Layer

### 3.1 New Scenes

#### `scenes/underpass/underpass.tscn` — **New**

Minimal 3D environment for the penultimate scene:

```
UnderpassRoot (Node3D)
├── Camera3D ("MainCamera") — facing the tunnel interior
├── WorldEnvironment — dim ambient (#0a0a14), cold color tone
├── DirectionalLight3D — dim, cool
├── OmniLight3D — flickering fluorescent
├── TunnelGeometry (StaticBody3D)
│   ├── CSGBox3D (walls, floor, ceiling)
│   ├── CSGBox3D (bench — single, against wall)
│   └── CSGCombiner3D — tunnel shape
├── LoFiText3D ("Graffiti_Wall") — Flat Sign, hope-variant
├── LoFiText3D ("SubwaySign") — Billboard, static
├── LoFiText3D ("FloorText") — Flat Sign, conviction-variant
├── LoFiText3D ("WallPoster") — Billboard, static
├── InteractionZones
│   └── Area3D ("final_choice_trigger") — triggers underpass.json dialogue
└── CanvasLayer ("DialogueUI")
    ├── DialoguePanel (DialogueRunner.gd)
    └── FadeCurtain (ColorRect + AnimationPlayer)
```

### 3.2 New Script: `gdscripts/ending_controller.gd`

**Extends:** `Node`

**Purpose:** Orchestrates ending sequences as CanvasLayer text overlays. Loaded by scene manager when player makes a final choice. ~50-80 lines of GDScript.

**Structure:**
```gdscript
extends Node

@onready var overlay: CanvasLayer = $EndingOverlay
@onready var text_label: Label3D = $EndingOverlay/TextLabel
@onready var fade_anim: AnimationPlayer = $EndingOverlay/FadeAnimation

func start_ending(ending_id: String) -> void:
    # Load dialogue JSON for this ending
    # Play sequence: fade in → show text → wait → next text → fade out → credits
    pass
```

### 3.3 Existing Scene Modifications

| Scene | Change |
|-------|--------|
| `scenes/street/street.tscn` | Add bartender NPC trigger area (if bar area exists) or integrate into existing interaction zones |
| `scenes/store/convenience_store.tscn` | After clerk dialogue ends, trigger automatic transition to underpass.tscn |

---

## 4. GDScript / Logic Layer

### 4.1 New Script Summary

| Script | Purpose | Est. Lines |
|--------|---------|------------|
| `gdscripts/ending_controller.gd` | CanvasLayer overlay ending sequences | ~60 |
| `gdscripts/underpass.gd` | Underpass scene init + environmental text config | ~40 |

### 4.2 Modified Scripts

| Script | Change | Est. Lines |
|--------|--------|------------|
| `gdscripts/store.gd` | Add after-clerk-dialogue transition logic → underpass.tscn | ~10 |
| `gdscripts/street.gd` | Add bartender NPC trigger integration (if needed) | ~15 |
| `gdscripts/office.gd` | Minor text variant expansions (if any) | ~5 |

### 4.3 EndingController.gd Design (Approach C — CanvasLayer Overlay)

The recommended approach per Spike 2:

- **No new scenes** — endings play as CanvasLayer overlays on top of Underpass scene
- **Text-driven** — each ending is 4 dialogue nodes shown as full-screen text
- **Fade effects** — AnimationPlayer for text entry/exit + final fade to black/white
- **Credits trigger** — after ending dialogue, emit signal to show credits / return to menu

---

## 5. Validation & Testing

### 5.1 Content Validation Checklist

- [ ] Every dialogue node has `shallow` + `middle` layer annotations
- [ ] Ending sequences and Stranger-related nodes have `deep` layer annotations
- [ ] All sentences ≤ 25 characters (Hemingway constraint)
- [ ] All paragraphs ≤ 3 sentences (Hemingway constraint)
- [ ] All 7 intertextual echoes are present and correctly cross-referenced
- [ ] State threshold coverage: hope 0-10, conviction 0-10 all have matching variants
- [ ] Dialogue JSONs pass `dialogue_parser.gd` schema validation
- [ ] Fallback/default choices exist for gated nodes

### 5.2 Test Cases

| Test | What It Verifies |
|------|-----------------|
| Office door → Street transition | Dialogue choice triggers correct scene change |
| Store clerk 3-branch dialogue | All branches reachable based on hope/conviction state |
| Underpass final choice → 3 endings | All three ending paths trigger correct CanvasLayer overlay |
| Environmental text state variants | Window/neon/graffiti/OPEN text changes with hope/conviction |
| Intertextuality audit script | Script/checklist confirms all 7 echoes present |
| Hemingway constraint pass | Manual review of every text field |
| All-edge-states environmental text | hope=0, hope=10, conviction=0, conviction=10 have matching text |

---

## 6. Implementation Plan (Task Summary)

| Phase | Tasks | Dependencies |
|-------|-------|-------------|
| P0: Underpass Scene | Create `underpass.tscn`, `underpass.gd`, LoFiText nodes | None |
| P0: EndingController | Create `ending_controller.gd` CanvasLayer overlay | None |
| P0: Story Design Doc | Write `docs/GAME_DESIGN/06-STORY.md` full annotated script | None |
| P1: Dialogue JSON Expansion | Expand/create 7 dialogue JSON files from design doc | Story Design Doc (P0) |
| P1: Store → Underpass Transition | Add after-clerk dialogue transition in `store.gd` | Underpass Scene (P0) |
| P1: Bartender Integration | Connect bartender.json trigger in street scene | Dialogue JSON Expansion (P1) |
| P1: Intertextuality Audit | Cross-scene verification of all 7 echoes | All Dialogue JSONs (P1) |
| P2: GDD Update | Update `docs/GAME_DESIGN/INDEX.md` + `05-DIALOGUE.md` | All content complete |
| P2: Hemingway Validator | Optional @tool validator for automated checking | Dialogue JSONs (P1) |

---

## 7. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Underpass scope creep | Medium | Medium | Keep geometry minimal — CSGBox3D tunnel only |
| Hemingway violations in authored text | Medium | Low | Manual audit + optional validator |
| Dialogue JSON / design doc drift | Low | Medium | JSONs extracted manually from single source |
| Missing intertextual echo | Low | Medium | Matrix checklist during implementation |
| Bartender scene integration friction | Low | Low | Keep existing 4 nodes; integrate as trigger zone |
