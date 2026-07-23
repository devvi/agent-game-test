# Research: Basic UI — Title Screen + Start Prompt

> Parent Issue: #147
> Agent: research-agent
> Date: 2026-07-23

---

## 1. Problem Definition

### Current Behavior

The game currently launches directly into the office scene (`scenes/office/office.tscn`) with no title screen, menu, or orientation. The flow is:

1. `scenes/main.tscn` loads with `gdscripts/main.gd`
2. `Main._ready()` connects dialogue signals and status bar
3. `_load_starting_scene()` calls `get_tree().change_scene_to_file("res://scenes/office/office.tscn")`
4. The player is dropped into the office with zero context about the game

There is no title/logo text, no start prompt, and no atmospheric "landing" moment before gameplay begins. The player receives no game name, no orientation, and no clear starting action.

**Existing UI infrastructure that IS already available:**
- `UIConfig` autoload (`gdscripts/ui_config.gd`) — responsive layout parameters, `auto_font_scale`, `recalculate()`
- `StatusBar` (`gdscripts/status_bar.gd`, `scenes/ui/status_bar.tscn`) — CanvasLayer-based hope/despair bar
- `SceneManager` (`gdscripts/scene_manager.gd`) — scene transition with fade-to-black and fade-in
- `LoFiText3D` (`gdscripts/lo_fi_text_3d.gd`) — Label3D with lo-fi shader parameters
- `RainController` (`gdscripts/rain_controller.gd`) — rain intensity tied to hope/despair (for atmospheric background effect)
- Input actions exist for `ui_accept`, `dialogue_select` (Space/Enter) — can be reused for start prompt

### Expected Behavior

When the game launches, the player should first see a **title screen**:

1. **Game title text** — "都市夜行者" or "Urban Night Walker" displayed prominently, in the game's lo-fi pixel font, centered on screen
2. **Start prompt** — "Press Space to Start" text below the title, gently pulsing/animating to indicate interaction
3. **Atmospheric background** — A dark gradient or rain effect as backdrop, establishing the game's Hopper-inspired urban night aesthetic
4. **Transition** — Pressing Space (or Enter) triggers a fade transition to the main game scene (office.tscn)

### User Scenarios

- **Scenario A (First Launch):** Player launches the game. Instead of abrupt scene load, sees the title screen for 1-3 seconds of atmospheric buildup, then presses Space to begin. The title screen sets the game's tone: rainy, nocturnal, contemplative.
- **Scenario B (Return Player):** Player returns to the game. The title screen provides a clear starting ritual before re-entering the narrative. Consistent with CRPG conventions.
- **Frequency:** Every game launch. Title screen displays once per session.

---

## 2. Design Intent

### Why Does Current Behavior Exist?

The game was built feature-by-feature following the MVP pipeline. The title screen was intentionally deferred because:

1. **Scene-first development** — Issues #55 (Office → Street → Store) and #58 (Store → Bridge → Underpass) focused on building playable 3D scenes. The title screen is a polish/orientation layer that depends on the scenes existing.
2. **Player controller dependency** — Issue #142 (Player Controller) recently introduced WASD movement, which makes the title→gameplay transition meaningful. Without a player body to control, a title screen had less purpose.
3. **Core mechanics came first** — Dialogue engine, GameState, text components, and scene transitions were all prerequisite or co-requisite systems. The title screen is a thin UI layer that wraps these systems.

### Why Change Now?

1. **UX completeness** — The game now has a player controller, scene transitions, atmospheric audio, and status UI. The title screen is the last missing piece of the basic UX flow: Title → Explore → Dialogue → Progress → Ending.
2. **First impression** — A title screen with the game's title and atmospheric background establishes the game's identity and tone before gameplay begins. This is standard CRPG convention.
3. **Pipeline milestone** — Adding the title screen completes the basic UI layer (Issue #53 StatusBar + Issue #147 TitleScreen) and makes the game feel like a complete product rather than a test scene.

### Previous Constraints

| Constraint | Detail |
|------------|--------|
| Engine | Godot 4.7.1 / GDScript 2.0 (static typing) |
| Renderer | `forward_plus` with Glow pass enabled |
| Resolution | 1920×1080, Allow HiDPI |
| Theme | Edward Hopper urban night — warm/amber on dark/cool backgrounds |
| Text rendering | LoFiText3D (Label3D + lo-fi shader) or Label (Control) with pixel font |
| UI layer | CanvasLayer at layer 128 (above world, same as StatusBar) |
| Scene transition | SceneManager with fade-to-black (0.5s), fade-in (0.5s) |
| Input | Keyboard-only (Space/Enter for start) |
| Existing fonts | Pixel font `.fnt` at `assets/fonts/pixel_font.*` |
| Platform | macOS / Linux |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `gdscripts/title_screen.gd` | Title Screen Controller | **New** — CanvasLayer script: title text, start prompt, background, input handling |
| `scenes/ui/title_screen.tscn` | Title Screen Scene | **New** — CanvasLayer scene with Label nodes and background ColorRect |
| `scenes/main.tscn` | Main Scene | **Modified** — Add TitleScreen node; remove direct scene loading |
| `gdscripts/main.gd` | Main Entry Script | **Modified** — Replace `_load_starting_scene()` with title screen display logic; connect title screen start signal to scene transition |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/scene_manager.gd` | Scene Manager | Title screen fades to office scene — uses existing fade transition API |
| `gdscripts/rain_controller.gd` | Rain Controller | Could optionally drive rain animation on title screen background (non-blocking for MVP) |
| `gdscripts/ui_config.gd` | UI Config | May need additional properties for title screen responsive layout (title font scale factor, vertical centering offset) |
| `docs/GAME_DESIGN/03-UI.md` | GDD | Should document title screen as part of UI system (future — out of scope for this PRD) |

### Data Flow Impact

```
Game Launch
    │
    ├──► Main._ready()
    │        │
    │        ├──► Configure StatusBar, DialogueDisplay, SceneManager
    │        ├──► TitleScreen.show_title()
    │        │        ├──► Display title text (lo-fi font, centered)
    │        │        ├──► Display "Press Space" prompt (pulsing animation)
    │        │        └──► Show atmospheric background (dark gradient ColorRect)
    │        │
    │        └──► Wait for Space/Enter input (title_screen input handler)
    │
    ├──► TitleScreen emits start_requested signal
    │        │
    │        ├──► Main._on_start_requested()
    │        │        ├──► Fade out (SceneManager.fade_out)
    │        │        └──► change_scene_to_file("res://scenes/office/office.tscn")
    │        │
    │        └──► Office scene loads
    │                 ├──► SceneBase._ready() instantiates PlayerController
    │                 ├──► StatusBar persists (autoload)
    │                 └──► Game loop begins
```

### Documents to Update

- [x] **This output:** `docs/PRD/147-title-screen-start-prompt.md`
- [ ] `docs/DESIGN/147-title-screen-start-prompt.md` — Plan phase output

---

## 4. Solution Comparison

### Approach A: CanvasLayer Title Screen (Label + ColorRect)

**Description:**

Create a new `CanvasLayer` scene (`scenes/ui/title_screen.tscn`) with:
- Root: `CanvasLayer` with `TitleScreen` script (`gdscripts/title_screen.gd`), layer = 128
- `Background` — `ColorRect` sized to full screen, dark gradient (top: #0a0a1a, bottom: #1a1a2e) — can be done with a `GradientTexture2D`
- `TitleLabel` — `Label` node (Control), large pixel font, centered text "Urban Night Walker" with a subtle amber (#FFB000) tint
- `StartPrompt` — `Label` node (Control), smaller pixel font, centered text "Press Space to Start" below the title, with a pulsing modulate animation (opacity tween 0.4 → 1.0 loop)

**Title Screen Flow:**
1. `Main._ready()` instantiates TitleScreen (already in scene tree per main.tscn)
2. TitleScreen starts pulsing animation on the start prompt
3. On Space/Enter press, TitleScreen emits `start_requested` signal with `fade_duration` parameter
4. `Main._on_start_requested()` calls `SceneManager.trigger_scene_change("res://scenes/office/office.tscn")`
5. SceneManager fades out → loads office scene → fades in

**Pros:**
- Uses standard Godot 2D Control nodes — reliable, auto-anchors, no 3D complications
- CanvasLayer ensures the title screen always renders on top
- Dark gradient ColorRect produces the atmospheric background with zero asset overhead
- Pulsing animation via simple modulate tween — minimal code
- Signal-driven architecture decouples title screen from scene loading logic
- Reuses existing `SceneManager` fade transitions — no new transition system needed

**Cons:**
- Title screen uses 2D Control labels while the game's aesthetic is 3D lo-fi text — slight visual mismatch
- No diegetic integration (title floats as an overlay, separate from the game world)
- Requires the game title string to be hardcoded or configurable via a constant

**Risk:** Low — CanvasLayer overlay with Label nodes is the simplest and most reliable approach in Godot.

**Effort:** 2 new files (scene + script) + 1 modified file (main.gd) ≈ 80–100 lines

---

### Approach B: 3D Title Screen Scene (World Space)

**Description:**

Create a dedicated 3D title scene (`scenes/title/title_screen.tscn`) with:
- Root: `Node3D` with a Camera3D
- `TitleLabel` — `LoFiText3D` (Label3D with lo-fi shader), positioned in world space at camera height, large pixel_size
- `StartPrompt` — `LoFiText3D` below the title, with pulsing emissive animation
- `Background` — A large plane with dark gradient `ShaderMaterial` or a `WorldEnvironment` with fog
- Optional: `RainController`-driven particle system for rain effect

**Title Screen Flow:**
1. `Main._ready()` sets the title scene as current via `change_scene_to_file()`
2. Title scene handles Space input directly
3. On start, emits `start_requested` → transitions to office scene

**Pros:**
- Fully diegetic — title exists in 3D world space, consistent with the game's lo-fi aesthetic
- Title text gets the LoFiText3D shader treatment (pixelation, scanlines, emissive glow) — matches in-game text visually
- Atmospheric effects (rain particles, fog, volumetric lighting) work natively
- No 2D/3D visual mismatch — everything uses the same rendering pipeline

**Cons:**
- **Over-engineered for a title screen** — a dedicated 3D scene with camera, environment, and particles for what is essentially a 2D overlay
- Requires creating a separate 3D scene and managing it as part of the scene flow
- SceneManager currently expects to transition between game scenes — adding a title scene as the first scene breaks the pattern
- More complex input handling (3D scene must capture input before the main scene takes over)
- Title screen's 3D nature means it can be occluded or affected by camera/world settings
- Larger memory footprint (3D scene + environment + particles vs 2 ColorRect nodes)

**Risk:** Medium — 3D title scene introduces unnecessary complexity for a simple UI overlay.

**Effort:** 2 new files (scene + script) + modifications to main.gd + scene flow restructuring ≈ 150–200 lines

---

### Approach C: Embedded Title as Main Scene Logo (Minimal)

**Description:**

Instead of a separate title screen, modify `scenes/main.tscn` to show a brief animated logo/intro before transitioning to the office scene. Use the existing `StatusBar` CanvasLayer pattern but with a large centered Label node that fades in, holds for 2 seconds, then fades out and transitions.

**Title Flow:**
1. `Main._ready()` shows the title via a CanvasLayer node that's always in main.tscn but hidden
2. A timer controls: show title (0s) → wait (2s) → fade out (0.5s) → transition to office
3. Pressing Space during the wait period skips remaining wait time

**Pros:**
- Minimal code — no new scene files, no scene flow restructuring
- Title can auto-dismiss after a brief pause for a faster launch experience
- Reuses the exact same CanvasLayer infrastructure as the StatusBar
- Skip mechanic is natural (Space to skip)

**Cons:**
- No persistent title screen — the title is a splash that auto-dismisses, not a screen the player can "sit on"
- Does not meet AC "Press Space to transition" — the press behavior is a skip, not a deliberate start action
- The main scene currently uses `call_deferred("_load_starting_scene")` — would need to delay that call
- Less atmospheric buildup — the title is a fade-in/fade-out flash rather than a dedicated screen

**Risk:** Low — but fails to meet the acceptance criteria for a proper title screen with deliberate start action.

**Effort:** 1 modified file (main.gd) + potentially 1 new hidden CanvasLayer node in main.tscn ≈ 40–60 lines

---

### Comparison Summary

| Dimension | A: CanvasLayer Title | B: 3D Title Scene | C: Embedded Splash |
|-----------|---------------------|-------------------|--------------------|
| Meets all ACs | ★★★★★ | ★★★★★ | ★★☆☆☆ |
| Implementation ease | ★★★★★ | ★★☆☆☆ | ★★★★★ |
| Visual consistency | ★★★☆☆ | ★★★★★ | ★★★☆☆ |
| Reuses existing infra | ★★★★★ | ★★☆☆☆ | ★★★★★ |
| Performance | ★★★★★ | ★★★☆☆ | ★★★★★ |
| Maintenance | ★★★★★ | ★★★☆☆ | ★★★★★ |
| Godot 4.7 idiomatic | ★★★★★ | ★★★☆☆ | ★★★★★ |

### Recommendation

→ **Approach A (CanvasLayer Title Screen)** because:

1. **Simplicity and reliability** — A CanvasLayer with two Label nodes and one ColorRect is the most Godot-idiomatic way to create a title screen. It requires zero 3D setup, zero physics, and zero asset imports.
2. **Meets all ACs** — Shows game name + "Press Space" prompt, transitions on Space press, and has an atmospheric dark gradient background.
3. **Reuses existing infrastructure** — Uses the same CanvasLayer pattern as the existing `StatusBar` (layer 128). The `SceneManager` fade transition API is already built and tested.
4. **Signal-driven decoupling** — The TitleScreen emits a `start_requested` signal, keeping the title screen logic fully independent of scene loading.
5. **Incremental upgrade path** — If a rain effect or more complex background animation is desired later, a `ShaderMaterial` can be applied to the background ColorRect (gradient animation, rain overlay) without changing the scene structure.

**Title Visual Design (Hopper-inspired):**
- Background: Vertical gradient ColorRect — top `#050510` (very dark blue-black) to bottom `#1a1a2e` (dark night blue)
- Title text: "Urban Night Walker" in pixel font, font_size 48 (scaled via UIConfig), color `#FFB000` (warm amber)
- Subtitle (optional): "都市夜行者" in same font, font_size 32, color `#B8B8B8` (muted silver)
- Start prompt: "Press Space to Start" in pixel font, font_size 18, color `#888888` with pulsing modulate tween (0.4 → 1.0 → 0.4, ~2s period)
- Layout: Title centered horizontally, positioned at ~40% from top. Subtitle below. Start prompt at ~65% from top.

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path

1. **Game launch:** `main.tscn` loads. `Main._ready()` connects all systems. The TitleScreen CanvasLayer is shown (visible by default).
2. **Title display:** "Urban Night Walker" text is centered, rendered in pixel font with amber color. "Press Space to Start" pulses below it.
3. **Dark background:** A full-screen gradient ColorRect provides the atmospheric backdrop (dark blue-black to night blue).
4. **Player presses Space:** TitleScreen detects the Space/Enter input and emits `start_requested`.
5. **Fade transition:** `Main._on_start_requested()` calls SceneManager to trigger `change_scene_to_file("res://scenes/office/office.tscn")` with fade-out animation (0.5s).
6. **Office scene loads:** SceneManager fade-in completes. PlayerController, StatusBar, and dialogue systems activate normally.
7. **Title screen hidden:** TitleScreen CanvasLayer is hidden after start (or destroyed by scene change).

### Edge Cases

1. **Rapid space press during fade:** If player rapidly presses Space multiple times while fade is already in progress, `transition_in_progress` in SceneManager prevents duplicate scene changes. No crash.
2. **Title screen visibility after scene change:** After `change_scene_to_file()`, the entire main scene (including TitleScreen) is unloaded. The office scene's SceneManager handles fade-in. The title screen does not persist.
3. **Very long or short window sizes:** Title and prompt are Label nodes (Control) with center anchor. `UIConfig.recalculate()` provides font scaling. At ultra-wide 21:9, the text stays centered. At 4:3, text may be slightly larger but still legible — suggest clamping font scale to [0.5, 2.0] per existing UIConfig behavior.
4. **No UIConfig available:** TitleScreen falls back to hardcoded default font sizes (48/32/18) — still functional, just not responsive.

### Failure Paths

1. **SceneManager not available during start:** Main._ready() should check `scene_manager != null` before calling scene change. If null, use `get_tree().change_scene_to_file()` directly as fallback.
2. **Input capture conflict:** Title screen must consume the Space event (`get_viewport().set_input_as_handled()`) to prevent double-firing (e.g., Space triggering both title start AND dialogue_select in the office scene). Since title screen is in a separate scene lifecycle, this is naturally handled — the title scene is fully unloaded before office loads.
3. **ColorRect gradient resource missing:** If GradientTexture2D resource fails to load, fall back to a solid ColorRect with a single dark color. Still functional, less atmospheric.
4. **Title scene fails to instantiate:** If main.tscn is missing the TitleScreen node, `Main._ready()` simply transitions directly to office (current behavior). Graceful degradation.

> These directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| Godot 4.7 CanvasLayer + Control nodes | Stable | Low — mature API |
| Pixel font (.fnt) at `assets/fonts/pixel_font.*` | Stable | Low — existing from UI System (Issue #53) |
| SceneManager transitions (`gdscripts/scene_manager.gd`) | Stable | Low — fade_out/fade_in pattern is tested |
| `scenes/main.tscn` | Stable | Low — exists and loads successfully |
| Issue #53 — UI System (UIConfig, StatusBar) | **Completed** | Low — UIConfig autoload exists; TitleScreen can use `auto_font_scale` |

### Blocks

| Future Work | Priority |
|-------------|----------|
| None — title screen is the first UX touchpoint | — |

### Preparation Needed

- [ ] Confirm the game's display title string: "Urban Night Walker" (English) and/or "都市夜行者" (Chinese)
- [ ] Define the dark gradient colors: `#050510` (top) → `#1a1a2e` (bottom)
- [ ] Verify pixel font is accessible at `assets/fonts/pixel_font.*` and can be used in Control Label nodes
- [ ] Verify `SceneManager.trigger_scene_change()` works correctly when called from main.gd (not from a scene's own SceneManager)

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*
> *It captures the current state of the feature area so the next agent can pick up*
> *without re-scanning all source files.*

The project currently launches directly into the office scene with no title screen. The existing `main.tscn` (`scenes/main.tscn`) has:
- `Main.gd` — connects StateSystem, StatusBar, DialogueDisplay3D, dialogue runner; calls `_load_starting_scene()` in `call_deferred()`
- `CanvasLayer/UI/Overlay` — existing CanvasLayer container used for UI elements
- `StatusBar` — CanvasLayer-based hope/despair indicator at layer 128
- `SceneManager` — handles fade-to-black transitions (already has `trigger_scene_change()` and fade animation system using `AnimationLibrary` in Godot 4 API)

The proposed approach (Approach A) adds:
1. **`gdscripts/title_screen.gd`** — Title screen controller:
   - Extends `CanvasLayer`
   - `@onready var _title_label: Label`, `_subtitle_label: Label`, `_prompt_label: Label`, `_background: ColorRect`
   - `signal start_requested(fade_duration: float)`
   - `func _ready()` — configure text, colors, fonts, start pulsing tween
   - `func _input(event: InputEvent)` — detect Space/Enter, emit signal
   - `func _start_pulse_tween()` — create looping tween on prompt modulate
   - Constants: `TITLE_STRING = "Urban Night Walker"`, `SUBTITLE_STRING = "都市夜行者"`, `PROMPT_STRING = "Press Space to Start"`
   - Color constants matching Hopper palette

2. **`scenes/ui/title_screen.tscn`** — CanvasLayer scene:
   - Root: CanvasLayer (TitleScreen script), layer = 128
   - `Background` — ColorRect, full screen anchor, GradientTexture2D or solid dark color
   - `TitleLabel` — Label, center anchor, pixel font, font_size 48, color `#FFB000`
   - `SubtitleLabel` — Label (optional), center anchor, pixel font, font_size 32, color `#B8B8B8`
   - `StartPrompt` — Label, center anchor, pixel font, font_size 18, color `#888888`

3. **Modifications to `scenes/main.tscn`**:
   - Add TitleScreen instance as child of root node (or as CanvasLayer child)
   - Ensure TitleScreen is visible by default (`visible = true`)

4. **Modifications to `gdscripts/main.gd`**:
   - Add `@onready var title_screen: CanvasLayer = $TitleScreen`
   - Remove or defer `_load_starting_scene()` — do NOT call it in `_ready()`
   - Connect `title_screen.start_requested` to `_on_start_requested(fade_duration)`
   - In `_on_start_requested()`: call `scene_manager.trigger_scene_change("res://scenes/office/office.tscn")`
   - Keep all other connections (StatusBar, dialogue, UIConfig) — they activate on scene change

### Key Risks

1. **Space/Enter input conflict with dialogue system:** The title screen exists in main.tscn, which is unloaded on scene change. Space input during title screen is handled by TitleScreen._input(). After scene change, the office scene handles its own input. No conflict.
2. **SceneManager not finding fade curtain in main scene:** SceneManager's `_setup_fade_curtain()` looks for `get_tree().current_scene`. When main.tscn is current, it will create the fade curtain as a child of the Main node. This should work — same pattern as per-scene SceneManagers.
3. **StatusBar appearing behind title screen:** StatusBar is at CanvasLayer layer 128, same as TitleScreen. The TitleScreen's CanvasLayer should be layer 129 (above StatusBar) to ensure it renders on top. After title screen hides, StatusBar at layer 128 becomes visible.
4. **Font scaling edge case:** TitleScreen Label nodes get `UIConfig.auto_font_scale` via the autoload. If UIConfig isn't ready at TitleScreen._ready() time, fall back to base font size and connect to `size_changed` on next frame.

### Design Decisions for Plan Agent

1. Title screen uses **CanvasLayer (2D)**, not a dedicated 3D scene — simplest, most reliable approach
2. Title screen layer = 129 (above StatusBar layer 128) — ensures it renders on top of all other UI
3. Start input is **Space or Enter** — reuses existing `ui_accept` / `dialogue_select` actions from Input Map
4. Transition uses **existing SceneManager fade** — no new transition system needed
5. Background uses a **ColorRect with dark gradient** — no external assets required; can be enhanced with ShaderMaterial later
6. Title screen is a **child of main.tscn** — loaded before any game scene, then naturally unloaded on scene change
7. No skip timer — player must deliberately press Space (meets AC requirement)
8. Font: use the project's existing pixel font from `assets/fonts/pixel_font.*` for all labels
