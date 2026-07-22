# Research: Lo-Fi 3D Text Rendering

> Parent Issue: #44
> Agent: game-research-agent
> Date: 2026-07-22

---

## 1. Problem Definition

### Current Behavior
The project currently has no 3D text rendering capability. The existing scaffold (`scenes/main.tscn`) uses a 2D Label node for a basic "Hello World" message. There is no Label3D setup, no shader material pipeline, and no visual effects infrastructure for rendering text in 3D space with atmospheric effects.

### Expected Behavior
A working Label3D system in Godot 4.7.1 that:
- Displays text in 3D space with a **lo-fi, atmospheric feel** inspired by the '九十年代素材与文化参考' aesthetic (urban desolation, UFO pulp, neon signs, rain-slicked streets)
- Supports **dynamic text changes** driven by game state (hope/despair slider, dialogue text)
- Can simulate **rain streaks** and **neon glow** via custom fragment shaders
- Achieves **minimum 30 FPS** with 100 simultaneous text labels on macOS/Linux
- Documents the chosen shader approach and alternative methods

### User Scenarios
- **Scenario A (Dialogue display):** Dialogue text floats in 3D space with a subtle neon glow, shimmering like a wet street reflection. When player's hope/despair state changes, the text color shifts from cyan (hope) to magenta/decayed (despair).
- **Scenario B (Environmental text):** Neon signs, rain-puddle reflections, street-lamp text, office-window messages — all rendered with Label3D + ShaderMaterial that responds to game state via shader parameters.
- **Scenario C (Dynamic update):** Text content changes mid-scene (e.g., dialogue advancing) without re-creating the Label3D node. Shader parameters (glow intensity, rain distortion, color shift) update via `material.set_shader_parameter()`.
- **Frequency:** Every scene with environmental text or dialogue — core visual mechanic of the game.

---

## 2. Design Intent (Feature)

### Why Do We Need This?
The game "Urban Night Walker" is a **literary CRPG** whose emotional core is conveyed through environmental text — neon signs, rain-slicked puddles, street lamps, and floating dialogue. The 90s Chinese urban desolation aesthetic requires text that feels **embedded in the world**, not overlaid as 2D UI. Raw Label3D nodes produce flat, untextured text that breaks the atmospheric spell. We need shader-driven visual effects to:
1. **Create atmosphere** — neon glow, rain distortion, color bleeding
2. **Reflect emotional state** — text appearance shifts with hope/despair
3. **Achieve lo-fi character** — intentionally imperfect rendering that evokes 90s nostalgia

### Why Change Now?
This is issue #44 (mapped from original issue #2 in the game-to-issues plan). It's part of the **MVP milestone** and is a dependency for issue #49 (Text Component Library) and issue #46 (Dialogue Engine runtime). It can only proceed after issue #42 (Theme-Mechanic Mapping) is complete, which defines the relationship between game state and visual presentation.

### Previous Constraints
- Godot **4.7.1** engine — must use Label3D API and shader system available in this version
- Forward+ rendering (`renderer/rendering_method="forward_plus"`) — enables spatial shaders with advanced post-processing
- macOS/Linux target — shaders must be compatible with Metal (macOS) and Vulkan (Linux) render paths
- No custom C++/GDExtension — use GDScript + Godot shader language only
- Text must be **dynamically updatable** via GDScript — shader parameters and text content both mutable at runtime

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `scenes/components/text_label_3d.tscn` | Label3D scene | **New** — Reusable Label3D base scene with shader material |
| `gdscripts/components/text_label_3d.gd` | Label3D controller | **New** — GDScript to update text and shader parameters at runtime |
| `shaders/lofi_text.gdshader` | Spatial fragment shader | **New** — Custom shader for neon glow + rain distortion |
| `shaders/lofi_text.gdshaderinc` | Shader include | **New** — Shared utility functions for color blending, noise |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/game_manager.gd` | Game state | May need to emit signals for shader parameter updates |
| `scenes/main.tscn` | Main scene | Will eventually contain Label3D instances instead of 2D Label |
| `docs/PRD/49-text-component-library.md` | Text Components | Depends on this PRD for base rendering approach |
| `docs/GAME_DESIGN/` | GDD | Should document visual text approach when review merges |

### Data Flow Impact
```
GameState (hope/despair change)
    → signal emitted
    → text_label_3d.gd._on_state_changed()
    → text_label_3d.text = new_text
    → material.set_shader_parameter("glow_intensity", value)
    → material.set_shader_parameter("rain_distortion", value)
    → material.set_shader_parameter("color_tint", color)
    → GPU executes spatial fragment shader
    → Text rendered with neon glow + rain streaks
```

### Documents to Update
- [x] `docs/PRD/44-lofi-3d-text-rendering.md` (this document)
- [ ] `docs/DESIGN/44-lofi-3d-text-rendering.md` (Plan phase)
- [ ] `docs/GAME_DESIGN/` (post-merge GDD update by review agent)

---

## 4. Solution Comparison

### Approach A: Label3D + Custom Spatial ShaderMaterial (Recommended)

- **Description:** Use Godot's built-in `Label3D` node with `material_override` set to a custom `ShaderMaterial` using a spatial (3D) fragment shader. The shader handles:
  - **Neon glow** — Gaussian-like blur with additive blending on text edges, controlled by `glow_intensity` and `glow_color` uniforms
  - **Rain streaks** — Animated UV distortion using a simplex noise or sine-wave function, combined with vertical alpha streaks that scroll downward in screen space
  - **Color blending** — Lerp between two color palettes (hope cyan/gold vs despair magenta/grey) based on a `blend_factor` uniform
  - **Lo-fi texture** — Optional chromatic aberration or posterization for retro feel
- **Pros:**
  - Native Label3D: text rendering, font, pixel_size, billboard, and offset all work out of the box
  - Material override approach means no custom mesh or viewport needed
  - Shader parameters are updatable via `material.set_shader_parameter()` at runtime
  - Single draw call per label (efficient with Forward+ batching)
  - Uses Godot's built-in text atlas rendering — font caching is already optimized
- **Cons:**
  - Shader complexity is moderate: need to work with `TEXTURE`, `UV`, `COLOR` in spatial shader context
  - Label3D uses atlas-based font rendering; shader must preserve text legibility while adding effects
  - Rain streaks may look uniform across all labels if noise seed is shared
- **Risk:** Low — Godot 4.x Label3D + ShaderMaterial is well-documented and stable
- **Effort:** ~3 files (1 scene, 1 script, 1 shader), ~200 lines total

### Approach B: SubViewport + 2D Label + CanvasItem Shader → ViewportTexture

- **Description:** Render a 2D Label with a CanvasItem shader (neon glow, rain) onto a `SubViewport`, then display the `SubViewport`'s texture as a `ViewportTexture` on a `QuadMesh` in 3D space using a `StandardMaterial3D`.
- **Pros:**
  - CanvasItem shaders are simpler to write than spatial shaders (2D UV space)
  - 2D Label has richer text formatting options (BBcode, rich text)
  - Rain effect can use full-screen texture coordinate manipulation
- **Cons:**
  - **Two draw calls** per text label (viewport render + quad render) — doubles GPU cost
  - SubViewport has resolution limits; text can become blurry when scaled
  - ViewportTexture setup is more complex in scene tree
  - Billboard behavior must be manually implemented on the QuadMesh
  - Dynamic text update requires re-rendering the SubViewport each frame
- **Risk:** Medium — performance risk at 100 instances due to double rendering
- **Effort:** ~4 files (viewport scene, 2D label, canvas shader, quad material), ~250 lines

### Approach C: Pre-rendered Text Textures + Billboard Sprites

- **Description:** Pre-render all text strings as textures (offline or on load) using a Viewport, then display them as `Sprite3D` billboards with a custom shader for glow effects.
- **Pros:**
  - Most performant for fixed text (static environmental signs)
  - Can use high-quality pre-processing (real Gaussian blur, full post-processing)
- **Cons:**
  - **Cannot support dynamic text changes** without re-rendering → defeats game-state responsiveness
  - Pre-rendering pipeline adds complexity to asset loading
  - Memory cost: each text string becomes a texture
  - No font-instance sharing per pixel_size variant
- **Risk:** High — incompatible with core requirement of dynamic text from game state
- **Effort:** ~3 files, significant runtime overhead for dynamic case

### Recommendation
→ **Approach A** because it satisfies all acceptance criteria with minimal complexity:
- Native Label3D handles text layout, font rendering, billboarding, and pixel sizing — no need to reimplement any of this
- Single ShaderMaterial per label means one draw call, making 100-instance performance achievable
- `material.set_shader_parameter()` provides the dynamic game-state coupling required
- The spatial shader approach is the standard Godot 4.x pattern for 3D text effects
- Approach B is a fallback if spatial shader limitations are encountered; Approach C is ruled out by the dynamic text requirement

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path
1. Label3D node with `material_override = ShaderMaterial` using `lofi_text.gdshader` 
2. Shader uniforms: `glow_intensity (float)`, `glow_color (vec4)`, `rain_distortion (float)`, `color_tint (vec4)`, `blend_factor (float)`, `time (float, auto)`
3. Text content updates via `$Label3D.text = new_text` — text re-renders immediately
4. Shader parameter updates via `$Label3D.material_override.set_shader_parameter("glow_intensity", 0.8)`
5. Camera-facing billboard (Label3D's default `billboard = Billboard.ENABLED`)
6. 100 Label3D instances in a scene → stable 30+ FPS on macOS (Apple Silicon) and Linux (Vulkan)

### Edge Cases
1. **Empty text string:** Label3D with empty text should not crash; shader should handle zero-area fragment gracefully
2. **Rapid text updates (every frame):** `text` setter causes text atlas re-generation; GDScript should throttle updates to avoid per-frame atlas rebuilds
3. **Non-ASCII / CJK characters:** Project's setting is English but CJK fallback font support may be needed; font must be set explicitly in Label3D's `font` property
4. **Shader parameter out of range:** `blend_factor` clamped to [0.0, 1.0] in shader; `glow_intensity` clamped to [0.0, 2.0]
5. **Multi-line text:** Label3D supports `\n`; shader must not assume single-line UV layout
6. **Very long text (>200 chars):** Label3D has `autowrap_mode`; performance impact of large text atlases should be profiled

### Failure Paths
1. **Shader compilation error:** Godot shows error in Output panel; label renders as flat white text with error material. The .gdshader file should be validated in-editor before use.
2. **Missing shader parameter:** `set_shader_parameter()` on non-existent uniform logs a warning but doesn't crash; use `has_shader_parameter()` as guard.
3. **Performance regression on Linux (Vulkan):** If Forward+ renderer on Linux drops below 30 FPS at 100 labels, reduce shader complexity (disable chromatic aberration, use fewer noise octaves) or switch to Approach B for fallback.
4. **macOS Metal compatibility:** Godot's Metal renderer may have different precision for `texture()` or `fwidth()` calls; test specifically on macOS before considering complete.

> These directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| Issue #42 — Theme-Mechanic Mapping | Not started | High — defines how game state maps to visual parameters |
| Godot 4.7.1 Forward+ renderer | Stable | Low — already configured in project.godot |
| Label3D node | Available | Low — built-in Godot 4.x class |
| ShaderMaterial + spatial shaders | Available | Low — standard Godot 4.x feature |

### Blocks

| Future Work | Priority |
|-------------|----------|
| Issue #49 — Text Component Library (rain, neon signs, puddles, street lamps) | P0 — needs base Label3D+shader approach |
| Issue #46 — Dialogue Engine runtime (3D text display) | P0 — uses Label3D for dialogue rendering |
| Issue #47 — UI System (3D floating labels) | P0 — builds on Label3D approach |

### Preparation Needed
- [ ] Confirm Godot 4.7.1 can compile spatial `.gdshader` files on this machine (editor open test)
- [ ] Create `shaders/` directory in project root
- [ ] Create `gdscripts/components/` directory for reusable components
- [ ] Set up a test scene with 100 Label3D instances for performance benchmarking
- [ ] Test macOS Metal rendering of Label3D with custom shaders

---

## 7. Spike / Experiment (Optional — depth/deep only)

This issue is `depth/standard`, so spike is optional. However, a minimal shader prototype is recommended during Plan/Implement.

### Question to Answer
Can a Label3D spatial shader access per-pixel UV coordinates of the rendered text glyph? (Neon glow requires edge detection on the text alpha channel, which needs the per-glyph UV inside the font atlas.)

### Method
In Godot 4.x Label3D, the `TEXTURE` built-in in a spatial shader gives access to the rendered text texture (a single-channel alpha or RGBA atlas). The `UV` built-in gives per-fragment UV in texture space. Edge detection can be done via:
```glsl
float alpha = texture(TEXTURE, UV).a;
float edge = fwidth(alpha); // or smoothstep-based edge detection
```

However, `fwidth()` in spatial shaders on the `TEXTURE` built-in works differently than in CanvasItem shaders. A prototype should verify this works in Godot 4.7.1 with Forward+/Metal.

### Result
*To be determined in Plan phase.*

### Impact on Approach
If `fwidth()` edge detection doesn't work in spatial shaders on Label3D, the neon glow approach shifts to a simpler option: pre-compute a blurred version of the text in the shader using multi-sample `texture()` lookups in a small kernel around each UV coordinate, or use the `screen_texture` (full-screen glow) approach with a bloom post-processing pass.

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*
> *It captures the current state of the feature area so the next agent can pick up*
> *without re-scanning all source files.*

The project currently has no 3D text rendering infrastructure. The existing main scene uses a 2D Label node. The game "Urban Night Walker" requires Label3D-based text in 3D space with atmospheric shader effects (neon glow, rain streaks, color blending) driven by game state.

The recommended approach (Approach A) builds on Godot 4.7.1's native Label3D node with `material_override` set to a custom `ShaderMaterial` using a spatial fragment shader. This gives us:
- Single draw call per label (text + effects in one pass)
- Runtime-updatable text (`Label3D.text = ...`) and shader parameters (`set_shader_parameter()`)
- Billboard support built into Label3D
- Font atlas rendering with built-in caching

The shader (`shaders/lofi_text.gdshader`) needs to implement:
1. Neon glow via edge detection + additive blending
2. Rain streaks via animated UV noise distortion
3. Color blending between hope/despair palettes

Key risks:
- `fwidth()`-based edge detection on Label3D texture may not work in spatial shaders on Metal backend — this needs prototyping during Plan phase
- 100-instance performance target is achievable but depends on shader complexity (avoid expensive loops)
- Font selection (CJK support) may need explicit `font.tres` resource if CJK text is used

The main risk is that `fwidth()` edge detection on the Label3D's font atlas texture in spatial shader context produces unexpected results on macOS Metal. If so, the glow approach falls back to either (a) a simple screen-space bloom (post-process), or (b) a multi-tap texture sample kernel in the fragment shader (more expensive but guaranteed to work on all backends).
