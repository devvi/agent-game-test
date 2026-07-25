# Tasks: Interactive Area Visual Feedback System

> Parent Issue: #218

## Phase 1: Core Component

- [ ] Create `gdscripts/interactive_area.gd` (`InteractiveArea` class, extends `Area3D`):
  - Export: `feedback_mode` enum, `is_interactable`, `parent_mesh`, `decal_size`, `light_energy`, `indicator_texture`, `indicator_size`, `fade_in_duration`, `fade_out_duration`, `pulse_duration`, `scale_pulse_intensity`, `glow_color`, `proximity_distance`
  - Internal: `_hover_decal`, `_proximity_light`, `_indicator_sprite`, `_parent_node`, `_is_hovered`, `_is_nearby` tracking
  - Methods: `_ready()`, `_build_hover_decal()`, `_build_proximity_light()`, `_build_indicator_sprite()`, `_on_mouse_entered()`, `_on_mouse_exited()`, `_on_body_entered()`, `_on_body_exited()`, `_on_input_event()`, `_tween_hover_decal()`, `_tween_proximity_light()`, `_tween_scale_pulse()`, `_start_indicator_pulse()`, `_exit_tree()`
  - Tween-based fade-in/out for decal alpha and light energy
  - Indicator sprite persistent pulse (0.4→0.8 alpha)
  - Click gating via `is_interactable` bool
  - Graceful signal disconnection in `_exit_tree()`
  - `push_warning` for missing CollisionShape3D or null texture
- [ ] Create `gdscripts/npc_indicator.gd` (optional standalone Sprite3D controller with alpha pulse and bob)
- [ ] Create `gdscripts/interactive_feedback.gdshader` (optional edge-outline shader for MeshInstance3D)

## Phase 2: Asset Textures

- [ ] Create `assets/textures/glow_amber.webp` (256×256 radial gradient, amber center → transparent edge)
- [ ] Create `assets/textures/icon_interact.webp` (64×64 teal chevron/arrow for NPC indicator)
- [ ] Create `assets/textures/icon_important.webp` (64×64 deep amber diamond for key items)

## Phase 3: NPCNode Integration

- [ ] `gdscripts/npc_node.gd`: In `_ready()`, create `InteractiveArea` instance as child:
  - Set `feedback_mode = BOTH`, `indicator_texture = icon_interact`, `glow_color = #AAFFDD`
  - Wire `interactable_clicked` to NPC's existing interaction path
  - In `set_state()`: set `_feedback_area.is_interactable = (current_state == IDLE)`
  - Suppress visual feedback during TALKING/COOLDOWN/EXHAUSTED states

## Phase 4: Scene TSCN Modifications

- [ ] `scenes/office/office.tscn`: Add InteractiveArea as child of `OfficeDoorTrigger`:
  - `feedback_mode = HOVER_ONLY`, `decal_size = (0.8, 0.8)`
  - Wire `interactable_clicked` → `_start_door_dialogue()` (or connect via office.gd)
- [ ] `scenes/store/convenience_store.tscn`: Add InteractiveArea to `StoreExitTrigger`
- [ ] `scenes/street/street.tscn`: Add InteractiveArea to `StoreEntranceTrigger`, `ExitZoneToOffice`, `ExitZoneToStore` (as sibling nodes)
- [ ] `scenes/lobby/lobby.tscn`: Add InteractiveArea to `SecurityGuardTrigger`, `StrangerTrigger`, `ExitTrigger`
- [ ] `scenes/bridge/bridge.tscn`: Add InteractiveArea to `RailingTrigger`, `HomelessTrigger`, `BridgeExitTrigger`
- [ ] `scenes/underpass/underpass.tscn`: Add InteractiveArea to `GraffitiTrigger`, `StrangerEchoTrigger`, `UnderpassExitTrigger`
- [ ] `scenes/subway_station/subway_station.tscn`: Add InteractiveArea to `TicketGateTrigger`, `TurnBackTrigger`, `BenchTrigger`

## Phase 5: Player Controller Enhancement (Optional)

- [ ] `gdscripts/player_controller.gd`: Add `interactable_hovered` signal (optional — for future mouse-highlight integration)
- [ ] Wire hover state from scene triggers to PlayerController for centralized awareness

## Phase 6: Testing

- [ ] New: `tests/unit/test_interactive_area.gd`: Unit tests for InteractiveArea:
  - Construction with all feedback modes
  - Hover signal emission
  - Proximity signal emission
  - Click gating (`is_interactable` true/false)
  - Edge cases (rapid mouse movement, overlapping zones, player spawns inside zone)
- [ ] `tests/unit/test_npc_node.gd`: Add tests for InteractiveArea child creation and state-dependent gating
- [ ] `tests/unit/test_player_controller.gd`: Add tests for optional `interactable_hovered` signal
