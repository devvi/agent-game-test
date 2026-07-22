# GDD §05 — Dialogue Engine: Data Model, Conditional Branching, Runtime

> Updated: 2026-07-22 — Added intertextuality pattern documentation

---

## 1. Dialogue Data Model

Each dialogue file is a JSON object with an `entry_node_id` and a `nodes` dictionary:

```json
{
  "entry_node_id": "node_id",
  "nodes": {
    "node_id": {
      "speaker": "Character Name",
      "text": "Dialogue text.",
      "choices": [
        {
          "text": "Choice text.",
          "condition": null,
          "effects": [],
          "next_node": "next_id",
          "scene": "res://path/to/scene.tscn"
        }
      ]
    }
  }
}
```

### Node Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `speaker` | String | Yes | Character name or "Narrator" / "Inner Voice" |
| `text` | String | Yes | Dialogue text. Use `\n` for line breaks. Hemingway: ≤25 chars/sentence, ≤3 sentences/paragraph |
| `choices` | Array | No | Array of choice objects. Empty or absent = terminal node |
| `on_enter` | Array | No | Effects applied when entering the node |
| `tags` | Array | No | Metadata tags (e.g., "bartender", "night_1") |

### Choice Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `text` | String | Yes | Choice label shown to player |
| `condition` | Object | No | Condition dict (see below). null/unset = always available |
| `effects` | Array | No | Effect dicts applied when chosen |
| `next_node` | String | No | Next node ID. null/absent/missing = end conversation |
| `scene` | String | No | Scene path to transition to. If set, overrides next_node |
| `default` | Boolean | No | If true, this choice is a fallback when no other choices reachable |

---

## 2. Condition Evaluation

Conditions use the `DialogueConditionEvaluator`:

```json
{
  "type": "slider",
  "axis": "hope",
  "op": "gte",
  "value": 7
}
```

### Supported Operators

| Operator | Meaning |
|----------|---------|
| `gte` | Greater than or equal |
| `gt` | Greater than |
| `lte` | Less than or equal |
| `lt` | Less than |
| `eq` | Equal |

### Flag Conditions

```json
{
  "type": "flag",
  "flag": "asked_about_stranger",
  "value": true
}
```

---

## 3. Effects System

Effects are applied when a choice is made or on node entry:

| Type | Parameters | Description |
|------|------------|-------------|
| `slider_delta` | `axis`, `delta` | Modify a slider (hope, conviction, will, despair) |
| `set_flag` | `flag`, `value` | Set a boolean flag |
| `trigger_event` | `event` | Future: trigger game events |
| `advance_clock` | — | Future: advance game clock |

---

## 4. Intertextuality Patterns (Issue #56)

The game uses ≥7 cross-scene repeated phrases (intertextual echoes). Each echo appears in a first context (where its meaning is established) and a later context (where the meaning shifts).

### Pattern 1: Direct Repetition

A phrase is repeated verbatim in a new context. The meaning shifts because of accumulated player experience.

**Example:** "Check the door" — Office desk note (instruction) → Underpass wall poster (existential reminder).

### Pattern 2: Fragmentary Echo

A phrase appears as a partial fragment, recognizable but eroded, mirroring the theme of decay.

**Example:** "ELM ST." → "el m... t... s st..." — the concrete street name has fragmented in the underpass.

### Pattern 3: Inversion

A phrase is inverted to reveal its opposite meaning.

**Example:** "this too shall pass" (street graffiti, comforting) → "this too shall not pass" (Stay ending, some things remain).

### Pattern 4: Tone Shift

The same words but a different emotional tone due to context.

**Example:** "YOU'RE STILL HERE" — neon sign (welcome/recognition) → Turn Back ending (accusation/hollowness).

### Implementation in Dialogue JSONs

Intertextual echoes are encoded in text with `⌈...⌋` markers to indicate cross-scene references:

```json
{
  "text": "The neon sign is dark.\n⌈YOU'RE STILL HERE⌋\nbut the light is gone."
}
```

### Echo Reference Table

| # | Phrase | First Scene | Reappearance |
|---|--------|-------------|--------------|
| 1 | "Check the door" | Office desk note (static) | Underpass wall poster (static) |
| 2 | "YOU'RE STILL HERE" | Street neon sign (conviction-variant) | Turn Back ending (dialogue) |
| 3 | "i was here" | Street graffiti (hope-variant) | Underpass floor (conviction-variant) + Stay ending |
| 4 | "ELM ST." | Street sign (static) | Underpass graffiti (hope-variant, faded) |
| 5 | "this too shall pass" | Street graffiti (hope ≥ 6) | Stay ending (inverted: "shall not pass") |
| 6 | "Take care" | Clerk farewell dialogue | Narrator epilogue (all endings) |
| 7 | "the same streets" | Office window text (all variants) | Underpass graffiti (hope-variant) |

---

## 5. Hemingway Constraints

All authored text must satisfy:
- **Sentence length**: ≤25 characters per sentence
- **Paragraph length**: ≤3 sentences per paragraph

These are enforced by `hemingway_enforcer.gd` (loadable as `@tool`). Run on any dialogue JSON:

```gdscript
var result = HemingwayEnforcer.truncate(text)
if result.was_truncated:
    print("Violation in node X: ", result.original_text)
```

---

## 6. Scene Transition Flow

```
Dialogue Choice → {effects applied} → {
  if choice.scene: SceneManager.trigger_scene_change(scene)
  elif choice.next_node: DialogueRunner.enter_node(next_node)
  else: DialogueRunner._end_conversation()
}
```

The `scene` field in a choice triggers a fade-to-black transition via `SceneManager`, which persists dialogue state to `GameManager.choices_history` before the scene change.

---

## 7. Full Dialogue File Inventory

| File | Purpose | Nodes | Entry Node |
|------|---------|-------|------------|
| `dialogues/office_door.json` | Office door + store entrance | 4 | `office_door_prompt` |
| `dialogues/store_clerk.json` | Clerk 3-branch conversation | 9 | `clerk_greet` |
| `dialogues/bartender.json` | Optional street bar encounter | 4 | `npc_bartender_greet` |
| `dialogues/underpass.json` | Underpass arrival + final 3-choice | 4 | `underpass_arrival` |
| `dialogues/ending_keep_walking.json` | Faith ending monologue | 4 | `keep_walking_01` |
| `dialogues/ending_turn_back.json` | Give-up ending monologue | 4 | `turn_back_01` |
| `dialogues/ending_stay.json` | Acceptance ending monologue | 4 | `stay_01` |
