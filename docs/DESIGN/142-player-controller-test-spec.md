# Test Specifications: #142 — Player Controller

> Parent Issue: #142
> Type: Test Specification (unit + integration)
> Generated from: docs/DESIGN/142-player-controller.md

---

## 1. Coverage Requirements

| Area | Normal Path | Edge Cases | Failure Paths |
|------|-------------|------------|---------------|
| WASD Movement | ✅ 4 | ✅ 5 | ✅ 3 |
| Mouse Look (click-drag) | ✅ 3 | ✅ 4 | ✅ 2 |
| E-key Interaction | ✅ 4 | ✅ 5 | ✅ 4 |
| Dialogue Mode Blocking | ✅ 3 | ✅ 3 | ✅ 2 |
| Scene Transition Persistence | ✅ 3 | ✅ 3 | ✅ 3 |
| NPCNode Proximity (group) | ✅ 2 | ✅ 2 | ✅ 1 |
| Collision | ✅ 2 | ✅ 3 | ✅ 2 |
| EKeyTrigger Component | ✅ 3 | ✅ 3 | ✅ 2 |
| Input Map | ✅ 2 | ✅ 2 | ✅ 1 |
| LIFO Interactable Stack | ✅ 2 | ✅ 3 | ✅ 2 |
| Fall Recovery | ✅ 1 | ✅ 2 | ✅ 2 |

**Total: 33 Normal Path, 35 Edge Cases, 24 Failure Paths = 92 test cases**

---

## 2. Test File: `tests/unit/test_player_controller.gd`

### TC-PC-N (Normal Path) — PlayerController Unit Tests

**TC-PC-N-1: PlayerController instantiates and is in "player" group**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-PC-N-1-1 | Create PlayerController | Instantiate new PlayerController | Node exists | `_assert(instance != null)` |
| TC-PC-N-1-2 | Check player group | After _ready() | is_in_group("player") returns true | `_assert(instance.is_in_group("player"))` |
| TC-PC-N-1-3 | Check class_name | instanceof check | Is PlayerController | `_assert(instance is PlayerController)` |

**TC-PC-N-2: WASD movement produces expected velocity**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-PC-N-2-1 | Move forward only | Simulate Input.get_vector() for move_forward=1.0 | velocity.z = -walk_speed (forward in -Z) | `_assert(velocity.z < 0)` |
| TC-PC-N-2-2 | Move backward only | Input: move_backward=1.0 | velocity.z = +walk_speed | `_assert(velocity.z > 0)` |
| TC-PC-N-2-3 | Move left only | Input: move_left=1.0 | velocity.x = -walk_speed | `_assert(velocity.x < 0)` |
| TC-PC-N-2-4 | Move right only | Input: move_right=1.0 | velocity.x = +walk_speed | `_assert(velocity.x > 0)` |
| TC-PC-N-2-5 | Diagonal movement | Input: move_forward + move_right (both 1.0) | velocity length ≈ walk_speed (normalized) | `_assert(abs(velocity.length() - 2.5) < 0.01)` |

**TC-PC-N-3: Movement direction is camera-relative**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-PC-N-3-1 | Forward after 90° yaw | Rotate body 90°, press W | Player moves along world +X | Check velocity direction after rotation |
| TC-PC-N-3-2 | Forward after 180° yaw | Rotate body 180°, press W | Player moves along world +Z | Check velocity direction |
| TC-PC-N-3-3 | No input | All input zero | velocity = Vector3.ZERO | `_assert(velocity == Vector3.ZERO)` |

**TC-PC-N-4: Mouse look rotates camera**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-PC-N-4-1 | Horizontal look | Drag mouse right 100px with left button held | Body rotation.y decreased | `_assert(rotation.y < initial_rotation.y)` |
| TC-PC-N-4-2 | Vertical look | Drag mouse up 100px with left button held | Head rotation.x increased | `_assert(head.rotation.x > initial_head_rot)` |
| TC-PC-N-4-3 | Vertical look clamp up | Drag mouse up 2000px (extreme) | Head rotation.x clamped to +60° | `_assert(head.rotation.x <= deg_to_rad(60))` |
| TC-PC-N-4-4 | Vertical look clamp down | Drag mouse down 2000px (extreme) | Head rotation.x clamped to -60° | `_assert(head.rotation.x >= deg_to_rad(-60))` |

**TC-PC-N-5: E-key interaction fires signal**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-PC-N-5-1 | E-key with nearby interactable | Add body to _nearby_interactables, simulate E press | interaction_requested emitted | Signal received with target == body |
| TC-PC-N-5-2 | E-key LIFO order | Enter A, enter B, press E | interaction_requested emitted for B | Signal received with target == B |
| TC-PC-N-5-3 | E-key with no interactable | Empty _nearby_interactables, simulate E press | No interaction_requested emitted | Signal not emitted |

**TC-PC-N-6: Camera current=false on duplicate cameras**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-PC-N-6-1 | Camera becomes current | PlayerController._ready() called | Head/Camera3D.current == true | `_assert(camera.current == true)` |

**TC-PC-N-7: Walk speed matches export (2.5 m/s)**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-PC-N-7-1 | Default walk speed | Instance created | walk_speed == 2.5 | `_assert(walk_speed == 2.5)` |
| TC-PC-N-7-2 | Move for 1 second | Simulate 60 frames at 1/60 delta with forward input | Position delta ≈ 2.5 units | `_assert(abs(global_position.z - (-2.5)) < 0.1)` |

---

### TC-PC-E (Edge Cases) — PlayerController Unit Tests

**TC-PC-E-1: Multiple overlapping interactables / LIFO stack**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-PC-E-1-1 | Enter A, enter B, enter C | Three bodies enter in order | Stack = [A, B, C] | `_assert(instance._nearby_interactables.size() == 3)` |
| TC-PC-E-1-2 | Press E with 3 stacked | C last, press E | interaction_requested for C | Signal target == C |
| TC-PC-E-1-3 | Exit C, press E | C exits, press E | interaction_requested for B | Signal target == B |
| TC-PC-E-1-4 | Exit all, press E | All exit, press E | No interaction_requested | Signal not emitted |
| TC-PC-E-1-5 | Duplicate body_entered | Same body enters twice | No duplicate in stack | Stack size unchanged, no error |

**TC-PC-E-2: Scene change during movement**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-PC-E-2-1 | Move then scene unload | Start forward, queue_free() | No crash, graceful cleanup | `_exit_tree()` runs without error |
| TC-PC-E-2-2 | Player position saved | queue_free() while at Vector3(3, 0, 4) | GameManager.player_position == (3, 0, 4) | Mock GameManager updated |

**TC-PC-E-3: Mouse drag interrupted**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-PC-E-3-1 | Escape during drag | Left mouse held, then release button | _mouse_dragging == false | `_assert(instance._mouse_dragging == false)` |
| TC-PC-E-3-2 | Mouse motion after release | Release button, then move mouse | No rotation change | Body rotation unchanged |

**TC-PC-E-4: Camera tilt offset applied correctly**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-PC-E-4-1 | Default tilt | After _ready() | head.rotation.x ≈ -5° | `_assert(abs(head.rotation.x - deg_to_rad(-5)) < 0.01)` |

**TC-PC-E-5: PlayerController not in "player" group before _ready()**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-PC-E-5-1 | Group membership pre-_ready | After new(), before _ready() | Not in "player" group | `_assert(not instance.is_in_group("player"))` |

---

### TC-PC-F (Failure Paths) — PlayerController Unit Tests

**TC-PC-F-1: GameManager not present (headless test)**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-PC-F-1-1 | No GameManager autoload | Instantiate in headless test | No crash | _ready() completes without error |
| TC-PC-F-1-2 | Restore position with no GM | GM returns null | Position stays at initialization point | Position == Vector3.ZERO |

**TC-PC-F-2: Dialogue runner missing from scene**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-PC-F-2-1 | No dialogue runner | Scene root has no CanvasLayer/DialoguePanel | _dialogue_active stays false | `_assert(instance._dialogue_active == false)` |
| TC-PC-F-2-2 | Signal connection fails | Null runner, connect attempt | No error | Null-safe guard prevents crash |

**TC-PC-F-3: Interaction target freed mid-stack**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-PC-F-3-1 | Target freed, then E pressed | Add body to stack, free it, press E | Silently skip freed target, try next | interaction_requested for valid target or no emit |
| TC-PC-F-3-2 | All targets freed | Add 3 bodies, free all, press E | No interaction_requested | Signal not emitted |

**TC-PC-F-4: Camera path changed or missing**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-PC-F-4-1 | Head node missing | Remove Head node, call _ready() | No crash | Null check in _handle_mouse_look() prevents crash |
| TC-PC-F-4-2 | Camera3D below Head missing | Remove Camera3D, call _ready() | No crash | @onready var camera is null, skipped |

---

## 3. Test File: `tests/unit/test_e_key_trigger.gd`

### TC-EK-N (Normal Path) — EKeyTrigger Unit Tests

**TC-EK-N-1: EKeyTrigger adds to "interactable" group**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-EK-N-1-1 | Instance added to group | After _ready() | is_in_group("interactable") | `_assert(trigger.is_in_group("interactable"))` |
| TC-EK-N-1-2 | body_entered connects signal | PlayerController enters trigger | interaction_requested connected | `_assert(player.interaction_requested.is_connected(func))` |

**TC-EK-N-2: E-key interaction fires signal**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-EK-N-2-1 | Player body enters, then E pressed | Player enters, simulate E via interaction_requested | e_key_interacted emitted | Signal received |
| TC-EK-N-2-2 | Body not player | Non-player body enters | No signal connection | e_key_interacted not emitted |

**TC-EK-N-3: Disconnection on body_exited**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-EK-N-3-1 | Player exits, E pressed | Player enters, exits, press E | e_key_interacted not emitted | Signal not received |

### TC-EK-E (Edge Cases) — EKeyTrigger

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-EK-E-1 | Double body_entered | Player enters twice | Only one connection | `_assert(connection_count == 1)` |
| TC-EK-E-2 | body_exited without body_entered | Player exits without entering | No error | `_exit_tree()` or disconnect guard |
| TC-EK-E-3 | Trigger freed during interaction | Queue free while connected | No crash on next signal | `is_instance_valid(self)` guard |

### TC-EK-F (Failure Paths) — EKeyTrigger

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-EK-F-1 | PlayerController has no interaction_requested signal | Trigger body_entered with plain Node | No connection | Check with `player.has_signal("interaction_requested")` |
| TC-EK-F-2 | PlayerController freed before trigger | PlayerController queue_free'd, then E pressed | No crash | `is_instance_valid(target)` guard |

---

## 4. Test File: `tests/integration/test_player_in_scene.gd`

### TC-INT-N (Normal Path) — Integration Tests

**TC-INT-N-1: PlayerController instantiation in scene**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-INT-N-1-1 | Scene loads with player | Create scene root with SceneBase, call _ready() | PlayerController instance exists as child | `_assert(scene_root.get_node_or_null("PlayerController") != null)` |
| TC-INT-N-1-2 | Player group in NPC proximity | NPCNode in scene, player instantiated | NPCNode._on_body_entered detects player | Check NPCNode._player_nearby after instantiation |

**TC-INT-N-2: Mouse click triggers still work**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-INT-N-2-1 | Click on existing Area3D | Simulate input_event on door trigger | Existing handler fires | `_assert(handler_called == true)` |

**TC-INT-N-3: Dialogue mode blocks WASD**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-INT-N-3-1 | Dialogue started, WASD frozen | Emit dialogue_started signal, simulate W press | velocity == Vector3.ZERO | `_assert(player.velocity.x == 0 && player.velocity.z == 0)` |
| TC-INT-N-3-2 | Dialogue ended, WASD resumes | Emit dialogue_ended, simulate W press | velocity.z != 0 | `_assert(player.velocity.z < 0)` |

**TC-INT-N-4: NPCNode detects player group**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-INT-N-4-1 | NPC.body_entered called | PlayerController in scene, call NPCNode._on_body_entered(player) | _player_nearby == true | `_assert(npc._player_nearby == true)` |
| TC-INT-N-4-2 | NPC.body_exited called | Call NPCNode._on_body_exited(player) | _player_nearby == false, labels hidden | `_assert(npc._player_nearby == false)` |

### TC-INT-E (Edge Cases) — Integration Tests

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-INT-E-1 | Two scenes, position persists | Load scene A, move to (5, 0, 3), change to scene B | Scene B player at (5, 0, 3) | Check position after scene change |
| TC-INT-E-2 | Rotation persists | Scene A: rotate 90° yaw, change to B | Scene B: rotation.y ≈ 90° | `_assert(abs(rotation.y - 1.57) < 0.1)` |
| TC-INT-E-3 | Head rotation persists | Scene A: look up 30°, change to B | Head rotation.x ≈ 30° | `_assert(abs(head_rot_x - 0.524) < 0.1)` |

### TC-INT-F (Failure Paths) — Integration Tests

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-INT-F-1 | No SpawnPoint marker | Scene has no SpawnPoint | Player spawns at origin | `_assert(player.global_position == Vector3.ZERO)` |
| TC-INT-F-2 | Interaction with freed NPCNode | NPCNode freed between body_entered and E press | Silent skip, no crash | No error, signal not emitted for freed node |
| TC-INT-F-3 | Camera conflict resolution | Two PlayerControllers somehow present | Only last instantiated has current=true | Check both cameras' current property |

---

## 5. Test File: `tests/unit/test_scene_base_player.gd`

### TC-SB-N (Normal Path) — SceneBase Player Extension

**TC-SB-N-1: SceneBase instantiates PlayerController**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-SB-N-1-1 | _instantiate_player called | Create SceneBase inheritor, call _ready() | PlayerController added as child | `get_node("PlayerController")` exists |
| TC-SB-N-1-2 | InteractionRequested connected | PlayerController emits signal | SceneBase._on_player_interaction called | Handler fired |

**TC-SB-N-2: Player state saved on _exit_tree**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-SB-N-2-1 | Position saved | Move player to (3, 0, 5), call _exit_tree | GameManager.player_position == (3, 0, 5) | Check mock GM |
| TC-SB-N-2-2 | No GM present | Remove autoload, _exit_tree | No crash | Script completes without error |

### TC-SB-E (Edge Cases) — SceneBase Player

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-SB-E-1 | _instantiate_player called twice | Call _instantiate_player twice | No duplicate PlayerController | Only one child named "PlayerController" |
| TC-SB-E-2 | Fall reset position matches spawn | SpawnPoint at (2, 0, 3) | PlayerController._fall_reset_position == (2, 0, 3) | `_assert(reset_pos == Vector3(2, 0, 3))` |

### TC-SB-F (Failure Paths) — SceneBase Player

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-SB-F-1 | PlayerController script not found | Preload fails | Graceful fallback | _instantiate_player returns early, no crash |
| TC-SB-F-2 | player_position contains bad data | GM.player_position = null | Vector3.ZERO fallback | Player spawns at origin |

---

## 6. Test File: `tests/unit/test_game_manager_player.gd`

### TC-GM-N (Normal Path) — GameManager Extensions

**TC-GM-N-1: Player state variables exist**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-GM-N-1-1 | player_position accessible | New GameManager instance | Has player_position property | `_assert(\"player_position\" in gm)` |
| TC-GM-N-1-2 | player_rotation accessible | New GameManager instance | Has player_rotation property | `_assert(\"player_rotation\" in gm)` |
| TC-GM-N-1-3 | player_head_rotation accessible | New GameManager instance | Has player_head_rotation property | `_assert(\"player_head_rotation\" in gm)` |

**TC-GM-N-2: Set and get player state**

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-GM-N-2-1 | Set position | gm.player_position = Vector3(1, 2, 3) | gm.player_position == (1, 2, 3) | `_assert(gm.player_position == Vector3(1, 2, 3))` |
| TC-GM-N-2-2 | Set rotation | gm.player_rotation = Vector3(0, 1.57, 0) | gm.player_rotation.y ≈ 1.57 | `_assert(abs(gm.player_rotation.y - 1.57) < 0.01)` |

---

## 7. Input Map Validation Tests

### TC-IM-N (Normal Path) — Input Map Verification

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-IM-N-1 | move_forward exists | Check InputMap | Action registered | `InputMap.has_action("move_forward")` == true |
| TC-IM-N-2 | move_backward exists | Check InputMap | Action registered | `InputMap.has_action("move_backward")` == true |
| TC-IM-N-3 | move_left exists | Check InputMap | Action registered | `InputMap.has_action("move_left")` == true |
| TC-IM-N-4 | move_right exists | Check InputMap | Action registered | `InputMap.has_action("move_right")` == true |
| TC-IM-N-5 | interact exists | Check InputMap | Action registered | `InputMap.has_action("interact")` == true |

### TC-IM-E (Edge Cases) — Input Map Edges

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-IM-E-1 | interact action not E key | Change action key binding | PlayerController ignores non-E | No interaction_requested on different key |
| TC-IM-E-2 | Actions missing in test | No input map (headless) | PlayerController handles gracefully | Null check prevents crash |

### TC-IM-F (Failure Path) — Input Map Failure

| # | Scenario | Input/Setup | Expected Behavior | Verification |
|---|----------|-------------|-------------------|-------------|
| TC-IM-F-1 | interact action undefined | Remove action from InputMap | No crash | _input() receives nothing for undefined action |

---

## 8. Edge Case Test Matrix (Comprehensive)

| # | Category | Scenario | Expected | Test File |
|---|----------|----------|----------|-----------|
| EC01 | Movement | Move into wall at 2.5 m/s | Player stops at wall (slide along it) | integration |
| EC02 | Movement | Rapid direction change (W→S in 1 frame) | Instant velocity reversal | unit |
| EC03 | Movement | Walk speed 0 (export changed) | No movement, no error | unit |
| EC04 | Movement | Alt+Tab while moving forward | Movement stops (Input.get_vector returns zero) | unit |
| EC05 | Movement | Very high delta (lag spike) | move_toward clamps, no velocity explosion | unit |
| EC06 | Look | Drag off-screen | No crash, mouse position clamped | unit |
| EC07 | Look | Drag with both mouse buttons | Only left button triggers look | unit |
| EC08 | Look | Head tilt + look up = clamped at combined offset | Clamp at -60+(-5)=-65° to +60+(-5)=+55° | unit |
| EC09 | Interaction | NPC node freed while in stack | Skip freed, try next valid | unit |
| EC10 | Interaction | Press E exactly on frame boundary of body_entered | Interaction should work (same frame) | integration |
| EC11 | Interaction | NPC area overlaps trigger area | Both detected; LIFO handles priority | integration |
| EC12 | Dialogue | Dialogue started then immediately ended (0-length) | _dialogue_active false after end | unit |
| EC13 | Dialogue | Dialogue runner emits multiple dialogue_started | No double-toggle (use bool guard) | unit |
| EC14 | Transition | Scene change during dialogue | Dialogue ends, player state saved | integration |
| EC15 | Transition | Scene change exactly at same time as Physics tick | Player position saved before scene unload | integration |
| EC16 | Collision | Player wedged between wall and wall | move_and_slide() resolves without velocity explosion | integration |
| EC17 | Collision | Player standing on tilted surface | Slide along surface (no gravity, so stationary) | integration |
| EC18 | Head | Head node very large rotation from saved state | Clamped on restore | unit |
| EC19 | EKeyTrigger | Multiple EKeyTrigger children on same Area3D | Each fires independently | unit |
| EC20 | Fall | Player falls off at edge but returns to walkable | FallDetector triggers, position reset | integration |

---

## 9. Verification Script Flow (Manual Playtest)

### Playtest: Shallow Verification

```
1. Launch game → PlayerController appears at office spawn
2. Press W → Move forward toward office door
3. Press S → Move backward
4. Press A → Strafe left
5. Press D → Strafe right
6. Left-click drag → Look around (yaw/pitch)
7. Release left-click → Look stops
8. Walk near NPC (guard in lobby) → Name + prompt label appears
9. Press E → Dialogue starts
10. During dialogue → WASD does nothing
11. Press Space → Select dialogue choice
12. Dialogue ends → WASD resumes
13. Walk away from NPC → Labels disappear
14. Click on door trigger (legacy) → Door dialogue works
15. Fall off world edge → Reset to spawn point
```

### Playtest: Checklist

See `tests/playtest/checklist-shallow.yaml` for extended playtest checklist with Pass/Fail tracking per AC.

---

## 10. Pass/Fail Criteria

All tests **MUST** pass before PR can merge:

- **Unit tests (PlayerController):** Min 45 tests, 100% pass
- **Unit tests (EKeyTrigger):** Min 8 tests, 100% pass
- **Unit tests (SceneBase extension):** Min 6 tests, 100% pass
- **Unit tests (GameManager extension):** Min 5 tests, 100% pass
- **Integration tests:** Min 12 tests, 100% pass
- **Input Map validation:** Min 8 tests, 100% pass
- **Playtest shallow checklist:** All items Pass

### Test Runner Command

```bash
cd /Users/devvi/workspace/agent-game-test
godot --headless --script res://tests/run_tests.gd
```

Expected output: "ALL TESTS PASSED" with 0 failures.
