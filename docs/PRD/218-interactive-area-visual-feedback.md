# Research: 交互区域视觉反馈系统 (Interactive Area Visual Feedback)

> Parent Issue: #218
> Agent: game-research-agent
> Date: 2026-07-25

---

## 1. Problem Definition

### Current Behavior

The game has **zero visual feedback** when the player's cursor hovers over or walks near an interactive object.

The existing interaction model relies entirely on invisible Area3D triggers and label3D visibility:

| System | Detection Method | Visual Feedback | Gap |
|--------|-----------------|-----------------|-----|
| **NPCNode** (`npc_node.gd`) | `body_entered`/`body_exited` on Area3D trigger | Shows/hides Label3D name + prompt text | No highlight on the NPC mesh or trigger zone itself |
| **EKeyTrigger** (`e_key_trigger.gd`) | `body_entered` → connect `interaction_requested` signal | None — purely event-driven | No visual indicator that this object is interactable |
| **PlayerController** (`player_controller.gd`) | `_nearby_interactables` LIFO stack via `interaction_area` Area3D | Emits `interaction_requested` signal only | No highlight on the player's targeted object |
| **Scene click triggers** (`office.gd`, `store.gd`, etc.) | `input_event` on Area3D with `MOUSE_BUTTON_LEFT` | None — relies on Label3D text in scene | Player clicks blind; no hover feedback to distinguish interactable from non-interactable |
| **ExitZone** (`exit_zone.gd`) | `body_entered` on Area3D | Optional Label3D prompt text only | No glow/pulse on the exit zone itself |

**Concrete problems:**

1. **No hover highlight** — When the mouse cursor passes over an interactive object (door, NPC, phone, laptop, deadline date), there is zero visual change. The player must click blindly to discover what is interactive.

2. **No proximity glow** — When the player walks near an interactable object, the object itself has no glow, pulse, or outline. The only feedback is a Label3D appearing above it, which is text-only and easy to miss in a dark 3D scene.

3. **No distinction between interactable and non-interactable** — All objects in the scene look identical under the cursor. Non-interactive background objects (walls, floors, tables, chairs) receive the same cursor as interactive objects (doors, NPCs, phones).

4. **No NPC visual indicator** — NPCs do not have a persistent visual cue (pulse, arrow, floating icon) to distinguish them from environmental objects. The clerk behind the counter is visually just a Label3D; the guard in the lobby has no indicator at all.

5. **Key interaction points lack visual prominence** — Phones, tablets, deadline dates, and other critical narrative interaction points have no special visual treatment. They blend into the scene's dark ambient aesthetic.

### Expected Behavior

Interactive objects provide clear, diegetic visual feedback:

1. **Hover highlight**: When the mouse cursor hovers over an interactive object, the object emits a visible glow, outline highlight, or scale pulse that follows the neon visual style.

2. **Proximity glow**: When the player walks within interaction range of an interactive object, the object shows a subtle, pulsing glow or edge highlight.

3. **Click gating**: Non-interactive areas do not respond to clicks. Only objects with the `interactable` group (or equivalent) show feedback and accept input.

4. **NPC indicators**: NPCs have a subtle persistent visual indicator — a floating icon, pulse light, or subtle arrow — making them distinguishable as interaction targets from across the scene.

5. **Key interaction points**: Phones, tablets, deadline dates, and critical story items have clear visual prompts (glowing outlines, floating icons) that make them stand out against the dark environment.

6. **Visual style consistency**: All feedback effects follow the Edward Hopper urban-night visual language — warm amber/neon glow, lo-fi pixel texture, subtle CRT/scanline overlay treatment.

### Scope Boundaries vs Overlapping PRDs

| PRD | Covers | NOT covered (left to #218) |
|-----|--------|---------------------------|
| **#54 (NPC Framework)** | NPCNode state machine, proximity detection, Label3D visibility, personality layers | ❌ Does NOT cover hover highlights, glow effects, pulse lights, outline shaders, visual feedback on NPC meshes |
| **#156 (Scene Transition)** | ExitZone Area3D, scene transition mechanics, spawn points | ❌ Does NOT cover exit zone visual indicators (glow on doorways). Mentions "exit zone animation (door opening, glow highlight)" as P3 future work — #218 takes that scope |
| **#142 (Player Controller)** | WASD movement, mouse look, E-key interaction, `_nearby_interactables` tracking | ❌ Does NOT cover visual feedback on interactable objects. PlayerController tracks proximity but emits no visual output |
| **#50 / #154 (State-World Feedback)** | Environmental text (5-state variants), emissive color shifts on LoFiText3D, neon sign state | ❌ Covers text content/color changes driven by hope slider, NOT object-level highlight/glow pulse on hover |
| **#44 (Lo-Fi 3D Text Rendering)** | LoFiText3D shader, pixelation, scanlines, emissive glow | ✅ Provides the rendering foundation (emissive shader params, glow pipeline) that #218 builds upon |

**This PRD is the VISUAL FEEDBACK LAYER** — it focuses on rendering techniques (Decal glow, outline shader, scale pulse, indicator sprites) applied to interactive objects. It does NOT re-analyze proximity detection (PRD #54), scene transitions (PRD #156), or player input (PRD #142).

### User Scenarios

- **Scenario A (Hover highlight on door):** Player moves mouse cursor over the office door. The door's outline glows amber-white (emissive edge highlight). Player knows this is interactable. Player clicks → dialogue triggers. Player moves cursor away → glow fades.

- **Scenario B (Proximity glow on NPC):** Player walks toward the convenience store clerk. As the player enters the NPC's `proximity_distance` (3.0m), the clerk's area shows a subtle pulsing amber ring at their feet or a glow around the trigger zone edge. The effect pulses slowly (1s cycle). Player walks away → glow fades.

- **Scenario C (Non-interactive area rejection):** Player clicks on the office wall or desk. No feedback appears — the object has no `interactable` group or InteractiveArea component. Click is silently dropped. No error, no visual response.

- **Scenario D (NPC indicator from distance):** Player enters the convenience store from the street. From 8m away, they see a faint floating arrow/chevron above the clerk, pulsing slowly (2s cycle). This distinguishes the NPC from the shelves and counter.

- **Scenario E (Key interaction point prominence):** Player approaches the deadline date on the office desk. The date text shows a glowing envelope/ring with a stronger amber emission than standard hover feedback. This communicates "important story item."

- **Frequency:** Every mouse move (hover), every proximity event, every click attempt.

---

## 2. Solution

### Recommended Approach: InteractiveArea Component + Decal/Shader Feedback System

Create a **reusable `InteractiveArea` component** (extends Area3D) that:
1. Detects mouse hover via `mouse_entered`/`mouse_exited` signals
2. Detects player body proximity via `body_entered`/`body_exited`
3. Applies configurable visual feedback effects:
   - **Decal glow** — A projected Decal node with warm amber circular texture, visible on hover or proximity
   - **Outline glow** — A shader-based outline effect on the parent mesh (optional, requires MeshInstance3D parent)
   - **Scale pulse** — A Tween-based scale animation on the parent node
   - **Indicator icon** — A billboarded Sprite3D (floating arrow, icon, or light)
4. Provides a `is_interactable: bool` gate that controls whether click events are processed

### Component Architecture

```
InteractiveArea (Area3D — root, replaces inline Area3D triggers)
├── CollisionShape3D (BoxShape3D or CylinderShape3D — interaction zone)
├── HoverDecal (Decal — projected glow on hover, optional)
│   └── [Decal material with amber glow texture, additive blend]
├── ProximityLight (OmniLight3D — pulsing light on proximity, optional)
├── IndicatorIcon (Sprite3D — billboarded floating icon, optional)
│   └── [Arrow / Chevron / Dot texture, billboarded]
└── VisualFeedbackController (AnimationPlayer / Tween — scale/pulse orchestration)
```

### Rendering Pipeline Integration

The visual feedback system builds on the existing rendering infrastructure:

| Existing Component | How #218 Uses It |
|-------------------|------------------|
| `LoFiText3D` (emissive_color + emissive_strength) | Increase emission on hover (shader param update) |
| `lo_fi_text.gdshader` (emissive blend in fragment) | Reuse emissive pipeline for Decal glow |
| Godot 4.7 `Decal` node | Project glow texture onto surfaces below interactive objects |
| Godot 4.7 `OmniLight3D` | Pulsing proximity light with warm amber color |
| Godot 4.7 `AnimationPlayer` / `Tween` | Scale pulse animation (1.0→1.05→1.0 cycle) |
| `WorldEnvironment` Glow pass (if enabled) | Post-process bloom enhances decal glow naturally |

### Visual Palette

| Effect | Color | Intensity | Duration / Cycle |
|--------|-------|-----------|------------------|
| Hover Decal Glow | `#FFAA55` (warm amber) | Alpha 0.3–0.6 | 0.2s fade-in, 0.3s fade-out |
| Proximity Pulse Light | `#FFAA55` | Energy 0.5–2.0 | 1.5s pulse cycle (ease-in-out) |
| Outline Glow | `#FFCC88` | Alpha 0.2–0.5 | 0.2s fade-in |
| Scale Pulse | — | 1.0 → 1.05 → 1.0 | 1.0s cycle (bounce ease-out) |
| NPC Indicator Arrow | `#AAFFDD` (teal-white) | Alpha 0.4–0.8 | 2.0s slow pulse, persistent |
| Key Item Indicator | `#FF8833` (deep amber) | Alpha 0.5–0.9 | 1.2s stronger pulse, persistent |

---

## 3. Approaches Considered

### Approach A: InteractiveArea Component + Decal/Shader Feedback (Recommended)

**Description:** A single reusable `InteractiveArea.gd` class that extends Area3D, combining interaction detection with configurable visual feedback. The component manages its own Decal, Light, Sprite3D, and Tween children.

**Pros:**
- **Reusable** — Drop into any scene as a child of the interactable mesh. Set `feedback_type` export (hover_only, proximity_only, both), configure visual params.
- **Composable** — Each visual effect (Decal, Light, Sprite, Scale) is optional; turn off what you don't need.
- **Hooks into existing systems** — `mouse_entered` is built into Area3D (Godot 4.7 supports it natively). PlayerController's `_nearby_interactables` already exists for proximity.
- **Non-destructive** — Existing scene scripts need minimal changes: replace inline Area3D triggers with InteractiveArea instances.
- **Diegetic** — Decal glow on the floor surface looks natural in the dark neon aesthetic. Warm amber matches the game's palette.
- **Backward compatible** — `mouse_entered`/`mouse_exited` fire in addition to existing `input_event` and `body_entered`. No signal wiring breaks.

**Cons:**
- **Decal projection complexity** — Decals need correct size, orientation, and surface alignment. Floor-projected decals work well; wall-projected decals need manual angle adjustment.
- **Shader-based outline needs a MeshInstance3D** — Objects without visual meshes (pure Area3D triggers) can only use Decal glow or Light pulse, not edge outline.
- **Performance on many interactables** — Each InteractiveArea creates 1–3 visual child nodes. With ~20 interactables per scene, this is fine. With 100+, consider pooling.

**Risk:** 🟢 Low — All techniques (Decal, Light3D, Sprite3D, Tween) are standard Godot 4.7 primitives. `mouse_entered`/`mouse_exited` on Area3D is built-in.

**Effort:** Medium (~2–3 days for component + integration into 8 scenes)

### Approach B: Shader-Only Feedback (Material Override Per Interactable)

**Description:** Create a custom `interactive_feedback.gdshader` that renders an outline/glow effect on any MeshInstance3D marked as interactable. The shader reads a uniform `hover_state` (0 = none, 1 = hovered, 2 = proximity) and blends in an edge glow. No Decal, no Light3D.

**Pros:**
- **Elegant rendering** — Single shader handles all visual feedback on the mesh itself
- **No extra nodes** — Just a material override on the MeshInstance3D
- **Edge highlight is precise** — Follows mesh geometry exactly (no Decal projection misalignment)

**Cons:**
- **Requires MeshInstance3D** — Pure Area3D triggers (door zones, exit zones with no mesh) cannot show any shader effect
- **Per-object shader material** — Every interactable needs a unique material override (or instanced shader params)
- **No floor/world-space glow** — The glow is only on the object mesh; no projected light onto surrounding surfaces
- **Forward+ renderer overhead** — Custom spatial shaders on many objects may impact fill rate
- **Harder to tune per scene** — Shader parameters are less intuitive than exported component properties

**Risk:** 🟡 Medium — Works for meshed objects but fails for invisible trigger zones.

**Effort:** Medium (~2–3 days for shader + per-object setup)

### Approach C: Screen-Space Overlay (UI Layer Hover Detection)

**Description:** Use a CanvasLayer overlay that detects which 3D object is under the mouse cursor via raycasting from the current Camera3D. When the ray hits an `interactable` object, the overlay draws a screen-space highlight (outline or icon) at the object's screen position.

**Pros:**
- **No 3D scene changes** — All feedback is in 2D UI space, no Decal/Light nodes needed
- **Works with any object type** — No MeshInstance3D dependency
- **Easier to style** — 2D UI textures are simpler to create and animate

**Cons:**
- **No diegetic feedback** — Screen-space overlays break immersion. The highlight is on the screen, not in the world.
- **Raycasting per frame** — Continuous `intersect_ray` from camera to mouse position every frame is more expensive than Area3D's built-in `mouse_entered` signal
- **Depth sorting** — Overlay must be depth-tested to avoid highlighting objects behind walls
- **No world-space glow** — Decal and light effects on the floor/surface can't be replicated in 2D
- **Camera dependency** — Breaks if camera changes or if multiple viewports exist

**Risk:** 🟡 Medium — Works but fights the visual design (diegetic world-space feedback is preferred for neon aesthetic).

**Effort:** Medium (~2–3 days for ScreenSpaceOverlay script + per-scene integration)

### Comparison Summary

| Criterion | A: InteractiveArea Component | B: Shader-Only | C: Screen-Space |
|-----------|------------------------------|---------------|-----------------|
| Diegetic world-space feedback | ✅ Yes (Decal/Light/Sprite3D) | ✅ Yes (mesh glow) | ❌ Screen overlay |
| Works with non-mesh triggers | ✅ Yes (Decal + Light) | ❌ Mesh required | ✅ Yes |
| Reusable across scenes | ✅ Drop-in component | ⚠️ Per-object material | ⚠️ Global script |
| Visual quality (edge precision) | ⚠️ Decal projection | ✅ Mesh geometry | ⚠️ Screen projection |
| Performance | ✅ Good (~3 nodes/interactable) | ✅ Good (single shader pass) | ⚠️ Per-frame raycast |
| Integration effort | Medium (replace Area3D triggers) | Medium (material assignment) | Medium (raycast logic) |
| Matches neon aesthetic | ✅ Decal glow on surfaces is natural | ✅ Mesh glow, no surface effect | ❌ Feels like UI overlay |

### Recommendation

→ **Approach A (InteractiveArea Component)** because:

1. **Diegetic feedback is core to the game's visual identity** — World-space glow (Decal on the floor, Light3D pulse, Sprite3D indicator) matches the Edward Hopper neon aesthetic. Screen overlays (Approach C) break immersion.

2. **Both meshed and non-meshed interactables work** — Area3D triggers (doors, exit zones, clickable spots) get Decal glow + Light3D. Mesh-based NPCs get optional outline shader through a material override. No object type is excluded.

3. **Built-in Area3D signals** — `mouse_entered`/`mouse_exited` are free with Area3D in Godot 4.7. No per-frame raycasting needed.

4. **Composable visual effects** — Each scene can tune the feedback type: a door uses Decal glow + scale pulse, an NPC uses Light3D pulse + indicator icon, a phone uses outline emission only.

5. **No existing system is broken** — Existing `input_event` handlers, `body_entered`/`body_exited` signals, and `_nearby_interactables` stack continue to work. InteractiveArea is additive.

6. **Gradual adoption** — Start with the office door and store clerk (high-visibility interactions), then expand to all 8 scenes.

**Key design decisions:**

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Feedback type detection | `mouse_entered` for hover, `body_entered` for proximity | Two independent feedback channels; both can be active simultaneously |
| Default feedback | Decal glow on hover + Light3D pulse on proximity | Covers both mouse-only and walk-up interaction models |
| Decal shape | Circular gradient (256×256, center-feather) | Soft edge matches ambient neon reflection on wet ground |
| Decal orientation | Project downward onto floor surface | Works for floor-standing objects; wall decals need manual `cframe` |
| Light3D color | Warm amber `#FFAA55` | Matches existing neon/emissive color palette |
| Scale pulse | Only on objects with a visual parent (MeshInstance3D) | Avoids scaling invisible Area3Ds (no visual effect) |
| NPC indicator | Billboarded Sprite3D with pulsing alpha (0.4→0.8→0.4) | Subtle enough to not distract, visible enough to distinguish |
| click gating | `input_event` guarded by `is_interactable` flag | Same pattern as NPCNode's `is_interactable()` check |

---

## 4. Implementation Plan

### New Files

| File | Type | Description |
|------|------|-------------|
| `gdscripts/interactive_area.gd` | **New** | InteractiveArea class: `extends Area3D`, feedback management, hover/proximity detection, decal/light/sprite/tween orchestration |
| `gdscripts/interactive_feedback.gdshader` | **New** | Optional edge-outline shader for MeshInstance3D interactables (separate from Decal-based feedback) |
| `gdscripts/npc_indicator.gd` | **New** | Billboarded Sprite3D controller for NPC persistent indicator (pulse alpha, float bob) |
| `assets/textures/glow_amber.webp` | **New** | 256×256 radial gradient glow texture for Decal (warm amber center → transparent edge) |
| `assets/textures/icon_interact.webp` | **New** | 64×64 interaction icon texture (teal chevron or arrow) for NPC indicator |
| `assets/textures/icon_important.webp` | **New** | 64×64 important-item icon texture (deep amber diamond) for key objects |

### Modified Files

| File | Nature of Change |
|------|------------------|
| `gdscripts/npc_node.gd` | **Minor** — Add `interactive_area` child reference, forward hover/proximity state to NPC name label emission |
| `gdscripts/player_controller.gd` | **Minor** — Add `interactable_hovered` signal emission when mouse ray intersects `_nearby_interactables` (optional enhancement) |
| `scenes/office/office.tscn` | **Modified** — Replace door Area3D trigger with InteractiveArea; add Decal + Light feedback |
| `scenes/store/convenience_store.tscn` | **Modified** — Replace clerk trigger Area3D with InteractiveArea; add NPC indicator + proximity light |
| `scenes/street/street.tscn` | **Modified** — Add InteractiveArea to store door + underpass entrance |
| `scenes/lobby/lobby.tscn` | **Modified** — Add InteractiveArea to guard interaction point |
| `scenes/bridge/bridge.tscn` | **Modified** — Add InteractiveArea to homeless person trigger + store exit |
| `scenes/underpass/underpass.tscn` | **Modified** — Add InteractiveArea to stranger trigger + subway entrance |
| `scenes/subway_station/subway_station.tscn` | **Modified** — Add InteractiveArea to ticket gate + broadcast point |

### Core Implementation Sketch: `interactive_area.gd`

```gdscript
extends Area3D
class_name InteractiveArea

# ── Feedback Mode ──
enum FeedbackMode { HOVER_ONLY, PROXIMITY_ONLY, BOTH, INDICATOR_ONLY }
@export var feedback_mode: int = FeedbackMode.BOTH
@export var is_interactable: bool = true

# ── Visual References ──
@export var parent_mesh: NodePath = ""            # Optional: parent MeshInstance3D for scale pulse + outline
@export var decal_size: Vector2 = Vector2(0.8, 0.8)  # Decal projection size
@export var light_energy: float = 1.5             # OmniLight3D energy
@export var indicator_texture: Texture2D           # Sprite3D texture for indicator
@export var indicator_size: float = 0.3            # Sprite3D size

# ── Timing ──
@export_range(0.1, 2.0, 0.1) var fade_in_duration: float = 0.2
@export_range(0.1, 2.0, 0.1) var fade_out_duration: float = 0.3
@export_range(0.5, 5.0, 0.1) var pulse_duration: float = 1.5
@export var scale_pulse_intensity: float = 0.05    # 1.0 → 1.0 ± intensity

# ── Color ──
@export var glow_color: Color = Color(1.0, 0.667, 0.333, 0.5)  # #FFAA55 amber

# ── Nodes (created in _ready if feature is enabled) ──
var _hover_decal: Decal = null
var _proximity_light: OmniLight3D = null
var _indicator_sprite: Sprite3D = null
var _parent_node: Node3D = null
var _is_hovered: bool = false
var _is_nearby: bool = false
var _tween: Tween

# ── Signals ──
signal hovered()
signal unhovered()
signal proximity_entered()
signal proximity_exited()
signal interactable_clicked()

func _ready() -> void:
    # Resolve parent mesh (for scale pulse)
    if not parent_mesh.is_empty():
        _parent_node = get_node(parent_mesh) as Node3D

    # Build decal if feedback_mode supports hover
    if feedback_mode in [FeedbackMode.HOVER_ONLY, FeedbackMode.BOTH]:
        _build_hover_decal()
        mouse_entered.connect(_on_mouse_entered)
        mouse_exited.connect(_on_mouse_exited)

    # Build proximity light
    if feedback_mode in [FeedbackMode.PROXIMITY_ONLY, FeedbackMode.BOTH]:
        _build_proximity_light()
        body_entered.connect(_on_body_entered)
        body_exited.connect(_on_body_exited)

    # Build indicator sprite
    if feedback_mode == FeedbackMode.INDICATOR_ONLY or indicator_texture:
        _build_indicator_sprite()

    # Guard input_event for click gating
    input_event.connect(_on_input_event)

    # Start indicator pulse if applicable
    if _indicator_sprite:
        _start_indicator_pulse()

func _build_hover_decal() -> void:
    _hover_decal = Decal.new()
    _hover_decal.name = "HoverDecal"
    _hover_decal.size = Vector3(decal_size.x, 2.0, decal_size.y)
    _hover_decal.cull_mask = 1 << 0  # layer 1
    # Load glow texture
    var tex: Texture2D = preload("res://assets/textures/glow_amber.webp")
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(glow_color.r, glow_color.g, glow_color.b, 0.0)
    mat.albedo_texture = tex
    mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
    _hover_decal.set_material(mat)
    # Position: project downward from area center to floor
    _hover_decal.position = Vector3(0, -0.5, 0)
    _hover_decal.visible = false
    add_child(_hover_decal)

func _build_proximity_light() -> void:
    _proximity_light = OmniLight3D.new()
    _proximity_light.name = "ProximityLight"
    _proximity_light.light_color = glow_color
    _proximity_light.light_energy = 0.0
    _proximity_light.omni_range = proximity_distance if 'proximity_distance' in self else 2.0
    _proximity_light.visible = false
    add_child(_proximity_light)

func _build_indicator_sprite() -> void:
    _indicator_sprite = Sprite3D.new()
    _indicator_sprite.name = "IndicatorIcon"
    _indicator_sprite.texture = indicator_texture
    _indicator_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    _indicator_sprite.pixel_size = 0.01
    _indicator_sprite.position = Vector3(0, 2.0, 0)  # Above object
    _indicator_sprite.modulate = Color(glow_color.r, glow_color.g, glow_color.b, 0.4)
    add_child(_indicator_sprite)

func _on_mouse_entered() -> void:
    _is_hovered = true
    if _hover_decal:
        _tween_hover_decal(glow_color.a)  # Fade in
    if _parent_node:
        _tween_scale_pulse(true)
    hovered.emit()

func _on_mouse_exited() -> void:
    _is_hovered = false
    if _hover_decal:
        _tween_hover_decal(0.0)  # Fade out
    if _parent_node:
        _tween_scale_pulse(false)
    unhovered.emit()

func _on_body_entered(body: Node) -> void:
    if body.is_in_group("player"):
        _is_nearby = true
        _tween_proximity_light(light_energy)  # Fade in
        proximity_entered.emit()

func _on_body_exited(body: Node) -> void:
    if body.is_in_group("player"):
        _is_nearby = false
        _tween_proximity_light(0.0)  # Fade out
        proximity_exited.emit()

func _on_input_event(camera: Camera3D, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int) -> void:
    if not is_interactable:
        return  # Silent rejection
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        interactable_clicked.emit()

func _tween_hover_decal(target_alpha: float) -> void:
    if _tween and _tween.is_valid():
        _tween.kill()
    _tween = create_tween()
    _tween.set_parallel(true)
    var mat := _hover_decal.get_material() as StandardMaterial3D
    var duration := fade_in_duration if target_alpha > 0 else fade_out_duration
    _tween.tween_method(func(a): mat.albedo_color.a = a, mat.albedo_color.a, target_alpha, duration)
    _tween.tween_property(_hover_decal, "visible", target_alpha > 0, 0.0)

func _tween_proximity_light(target_energy: float) -> void:
    if _tween and _tween.is_valid():
        _tween.kill()
    _tween = create_tween()
    _tween.set_parallel(true)
    _tween.tween_property(_proximity_light, "light_energy", target_energy, fade_in_duration if target_energy > 0 else fade_out_duration)

func _tween_scale_pulse(active: bool) -> void:
    if not _parent_node:
        return
    if _tween and _tween.is_valid():
        _tween.kill()
    if active:
        _tween = create_tween()
        _tween.set_loops()
        _tween.tween_property(_parent_node, "scale", Vector3.ONE * (1.0 + scale_pulse_intensity), pulse_duration * 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
        _tween.tween_property(_parent_node, "scale", Vector3.ONE * (1.0 - scale_pulse_intensity), pulse_duration * 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
    else:
        if _tween and _tween.is_valid():
            _tween.kill()
        _parent_node.scale = Vector3.ONE

func _start_indicator_pulse() -> void:
    if not _indicator_sprite:
        return
    var tween := create_tween()
    tween.set_loops()
    tween.tween_property(_indicator_sprite, "modulate:a", 0.8, pulse_duration * 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
    tween.tween_property(_indicator_sprite, "modulate:a", 0.4, pulse_duration * 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

func _exit_tree() -> void:
    if mouse_entered.is_connected(_on_mouse_entered):
        mouse_entered.disconnect(_on_mouse_entered)
    if mouse_exited.is_connected(_on_mouse_exited):
        mouse_exited.disconnect(_on_mouse_exited)
    if body_entered.is_connected(_on_body_entered):
        body_entered.disconnect(_on_body_entered)
    if body_exited.is_connected(_on_body_exited):
        body_exited.disconnect(_on_body_exited)
    if input_event.is_connected(_on_input_event):
        input_event.disconnect(_on_input_event)
```

### NPCNode Integration

Add to `npc_node.gd`:

```gdscript
# In _ready():
var feedback := InteractiveArea.new()
feedback.feedback_mode = InteractiveArea.FeedbackMode.BOTH
feedback.indicator_texture = preload("res://assets/textures/icon_interact.webp")
feedback.glow_color = Color(0.667, 1.0, 0.867, 0.5)  # Teal-white for NPCs
feedback.proximity_distance = proximity_distance
add_child(feedback)

# When NPC enters TALKING state, feedback is suppressed:
func set_state(new_state: int) -> void:
    current_state = new_state
    # Suppress visual feedback during dialogue
    if _feedback_area:
        _feedback_area.is_interactable = current_state == NPCState.IDLE
```

### Decal Glow Shader (optional visual enhancement)

```gdshader
// interactive_glow.gdshader — glow overlay for MeshInstance3D interactables
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back;

uniform vec4 glow_color : source_color = vec4(1.0, 0.667, 0.333, 0.3);
uniform float glow_intensity : hint_range(0.0, 1.0) = 0.3;
uniform float outline_width : hint_range(0.001, 0.1) = 0.02;

void fragment() {
    // Fresnel-based edge glow (outline on mesh geometry)
    float fresnel = 1.0 - abs(dot(NORMAL, VIEW));
    float outline = smoothstep(1.0 - outline_width * 4.0, 1.0, fresnel);
    vec3 glow = glow_color.rgb * glow_intensity * outline;
    ALBEDO = vec3(0.0);
    EMISSION = glow;
    ALPHA = outline * glow_color.a;
}
```

---

## 5. Edge Cases and Error Handling

### Normal Path

1. **Hover highlight on interactable:** Player moves cursor over InteractiveArea → `mouse_entered` fires → Decal alpha tweens to 0.5 (0.2s) → Optional scale pulse starts on parent mesh. Player moves cursor away → `mouse_exited` fires → Decal fades out (0.3s) → scale returns to 1.0.

2. **Proximity glow on approach:** Player walks into InteractiveArea collision → `body_entered` fires (player group check) → OmniLight3D energy tweens to 1.5 (0.2s). Player walks away → light fades to 0.0.

3. **Click on interactive object:** `input_event` fires → `is_interactable` is true → `interactable_clicked` signal emitted → scene script routes to dialogue_runner.start(). Visual feedback returns to normal.

4. **Click on non-interactive object:** `input_event` fires → `is_interactable` is false → return silently. No error, no visual change, no sound.

5. **NPC indicator persistent visibility:** NPC hat Sprite3D indicator (teal chevron) pulses at 2.0s cycle. Visible from up to 15m away. Does not require hover or proximity.

### Edge Cases

1. **Rapid mouse movement across multiple interactables:** Player swipes cursor across 3 trigger zones in 0.5s. Each `mouse_entered` fires sequentially. `mouse_exited` from previous zone fires. Tween chain ensures clean fade-in/fade-out without visual flickering. **Mitigation:** Each InteractiveArea manages its own Tween — no global state.

2. **Player inside interactable zone at scene load:** If `body_entered` fires during `_ready()` (player spawns inside trigger zone), the proximity light activates immediately. **Mitigation:** Add a 0.5s delay before enabling body monitoring: `set_deferred("monitoring", true)` or check `transition_in_progress` on GameManager.

3. **Overlapping InteractiveAreas:** Two InteractiveAreas overlap spatially (door zone + NPC zone). Both `mouse_entered` fire. Both Decals show. Player sees two glows. This is correct behavior — both are interactive. **Mitigation:** None needed. If overlap is undesirable, the scene author should move zones apart.

4. **Dialogue active during hover:** Player hovers over an interactable while dialogue is active. The `mouse_entered` still fires — visual feedback shows. But click is suppressed by dialogue runner. **Mitigation:** `is_interactable` set to false during dialogue via PlayerController's `dialogue_mode_changed` signal connection.

5. **NPC in TALKING state + hover:** NPC is in dialogue with player. Mouse hovers over NPC Area3D. Feedback should be suppressed to avoid visual confusion. **Mitigation:** NPCNode sets `is_interactable = false` on its InteractiveArea when state != IDLE.

6. **Scale pulse on zero-scale or tiny objects:** `scale_pulse_intensity = 0.05` on an object with scale = Vector3(0.1, 0.1, 0.1) → final scale = 0.105. Negligible effect. **Mitigation:** Clamp minimum scale delta to 0.01.

7. **Decal on non-horizontal surface:** Decal is configured for floor projection. If placed on a wall, the `cframe` projection may render incorrectly. **Mitigation:** Export `decal_cframe: Vector3` to manually orient decal rotation. Default projects downward.

8. **Multiple players (split-screen, future):** `body_entered` fires once per player body. `player` group check ensures only the local player triggers feedback. **Mitigation:** None needed for single-player.

### Failure Paths

1. **Glow texture not found:** Decal material loads with null `albedo_texture`. Decal renders as flat colored quad. **Mitigation:** Check texture at `_ready()`: `if not tex: push_warning("InteractiveArea: glow texture missing")`.

2. **Parent mesh removed at runtime:** Object that was interactable is freed during gameplay (rare). `_parent_node` reference becomes dangling. **Mitigation:** All scale pulse operations check `is_instance_valid(_parent_node)`.

3. **InteractiveArea without CollisionShape3D:** `mouse_entered`/`body_entered` never fire. Visual feedback never activates. Object is effectively non-interactive. **Mitigation:** Add `_ready()` check: `if find_children("*", "CollisionShape3D", false).size() == 0: push_warning("InteractiveArea: no CollisionShape3D child — no feedback will fire")`.

4. **OmniLight3D in scenes without WorldEnvironment:** Light renders but has no indirect/bounce. Still visible as point light. **Mitigation:** Acceptable — point light glow is visible even without GI.

5. **Memory on scene unload:** InteractiveArea and all children (Decal, Light, Sprite, Tween) are freed with their parent scene via `change_scene_to_file()`. No orphan nodes. **Mitigation:** Already correct — no special cleanup needed.

> These directly become test case skeletons in Plan phase.

---

## 6. Future Considerations (Out of Scope for This Phase)

| Feature | Priority | Notes |
|---------|----------|-------|
| Pulse glow on exit zones (door outline) | P3 | Mentioned in PRD #156 as future work — should use same InteractiveArea component |
| Lootable/Intractable item shimmer | P3 | Special sparkle effect for key items |
| Audio feedback on hover (soft chime) | P4 | Could tie into existing AudioManager |
| Controller input highlight (gamepad cursor) | P4 | InteractiveArea's `mouse_entered` won't fire on gamepad — needs alternative detection |
| State-dependent feedback (hope slider influences glow color) | P4 | Glow color shifts based on hope/despair: amber at high hope, desaturated at low hope |
| Haptic feedback on click (vibration) | P4 | Requires platform-specific API |
| Accessibility: highlight size increase mode | P4 | Larger Decal glow for visually impaired players |
| Pooled InteractiveArea system (100+ interactables) | P4 | Object pooling for very dense scenes |

---

## 7. References

### Existing Infrastructure

| Reference | File | Relevance |
|-----------|------|-----------|
| NPCNode | `gdscripts/npc_node.gd` | Existing interactable pattern: proximity_distance, is_interactable(), input_event handling |
| PlayerController | `gdscripts/player_controller.gd` | `_nearby_interactables` stack, `interaction_requested` signal, `dialogue_mode_changed` signal |
| LoFiText3D | `gdscripts/lo_fi_text_3d.gd` | emissive_color + emissive_strength via shader param — pattern for glow control |
| lo_fi_text.gdshader | `shaders/lo_fi_text.gdshader` | Emissive blend in fragment shader — precedent for additive glow rendering |
| TextComponentBase | `gdscripts/text_component_base.gd` | Tween-based transitions (fade in/out) — same pattern used by InteractiveArea |
| NeonSign | `gdscripts/neon_sign.gd` | Uses conviction axis for neon color — neon aesthetic reference |
| ExitZone pattern | `gdscripts/exit_zone.gd` | Existing Area3D trigger class — structural model for InteractiveArea |

### Related PRDs

| PRD | Topic | Relationship |
|-----|-------|-------------|
| #54 | NPC Framework | Proximity detection, label visibility — #218 adds visual feedback layer |
| #142 | Player Controller | `_nearby_interactables` — #218 consumes this for proximity detection |
| #156 | Scene Transition | ExitZone triggers — #218's InteractiveArea can replace ExitZone's Area3D |
| #44 | Lo-Fi 3D Text Rendering | LoFiText3D shader, emissive pipeline — foundation for glow effects |
| #50 / #154 | State-World Feedback | Environmental text 5-state variants — separate from object-level feedback |

### Godot 4.7 Documentation

| Feature | Docs Link |
|---------|-----------|
| Area3D `mouse_entered`/`mouse_exited` | https://docs.godotengine.org/en/4.7/classes/class_area3d.html#class-area3d-signal-mouse-entered |
| Decal node | https://docs.godotengine.org/en/4.7/classes/class_decal.html |
| OmniLight3D | https://docs.godotengine.org/en/4.7/classes/class_omnilight3d.html |
| Sprite3D (billboard) | https://docs.godotengine.org/en/4.7/classes/class_sprite3d.html |
| Tween (animation) | https://docs.godotengine.org/en/4.7/classes/class_tween.html |
| Custom spatial shaders | https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html |

### Visual Design References

- Edward Hopper, "Nighthawks" (1942) — warm amber interior glow against dark exterior
- Blade Runner (1982) — neon glow on wet surfaces, diegetic light indicators
- Disco Elysium (2019) — subtle interactable highlight via white outline on hover, white dot indicator for interactable objects
