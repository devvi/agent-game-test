# Research: Lo-Fi 3D Text Rendering

> Parent Issue: #44
> Agent: game-research-agent
> Date: 2026-07-22

---

## 1. Problem Definition

### Current Behavior

The project currently renders all text as flat 2D Label nodes in the Control layer (`scenes/main.tscn` contains a single `Label` node using `theme_override_font_sizes/font_size = 32`). There is no 3D text rendering system, no support for environmental text (signs, neon, graffiti), and no lo-fi visual treatment of any kind. The game uses Godot 4.7's `forward_plus` renderer with a 1920×1080 viewport.

The game's visual direction — Edward Hopper-inspired dark urban night — calls for diegetic text elements such as:

- Neon bar signs in alleyways
- Street name placards glowing in the rain
- Storefront window text reflections
- Graffiti messages on wet walls
- Title cards and chapter headers rendered in 3D space

None of these are currently possible.

### Expected Behavior

A Lo-Fi 3D text rendering system that can place text anywhere in the 3D world with a characteristically lo-fi aesthetic: low-resolution aliasing, limited color palette (matching the Hopper palette), subtle CRT/scanline artifacts, and optional glow/neon emission. The system should:

1. Render text meshes in 3D space using Godot 4.7's 3D rendering pipeline
2. Apply a consistent lo-fi aesthetic (pixelated edges, reduced color depth, scanline overlay)
3. Support common environmental text forms: billboards (always face camera), extruded signs (neon tube look), and flat decals (wall graffiti)
4. Perform efficiently at 1920×1080 — the CRPG has no physics or action, but may have multiple text elements visible per scene
5. Work within the existing `forward_plus` renderer (no renderer swap required)

### User Scenarios

- **Scenario A (Environment Text):** Player walks down a rain-soaked city street at night. A neon sign reading "BAR" buzzes above a door, rendered in 3D with a lo-fi aesthetic — slightly pixelated edges, a warm-limited palette (amber, deep red, black), and a faint scanline shimmer. The sign is billboarded to always face the player.
- **Scenario B (Diegetic Title Cards):** A chapter transition shows "DAY 17" extruded in 3D space, half-obscured by rain particles, with low-color-depth rendering that makes it feel like an old CRT monitor display embedded in the world.
- **Scenario C (Graffiti / Wall Text):** The player approaches a wall with spray-painted text ("why do we make games?"). The text follows the wall surface as a decal, with pixelated paint splatter and a two-tone color scheme.
- **Frequency:** Every scene (3D environment), every chapter transition, and potentially every interactive location.

---

## 2. Design Intent

### Why Does Current Behavior Exist?

The project is early-stage (currently only a "Hello World" Label in 2D Control space). All previous Issues focused on core mechanics (Issue #5), theme-mechanic mapping (Issue #42), and project scaffolding (Issue #6). 3D text was never in scope. The existing `scenes/main.tscn` has a flat 2D Label with no 3D world at all — the game's 3D environment hasn't been built yet.

### Why Change Now?

- The game's visual identity (Edward Hopper's "Nighthawks" / urban night aesthetic) depends on environmental text as a core atmospheric layer — neon signs, street names, and graffiti are integral to the mood
- Subsequent Issues (narrative architecture #2, state-world feedback #4, scene building) will need to place text in 3D space to convey location, mood, and player state
- The lo-fi aesthetic isn't an afterthought — it's the primary visual constraint that defines what "looks right" in this game. Text must look intentionally imperfect to match the game's theme (broken dreams, worn-out city, fading hope)
- Godot 4.7 has mature 3D text capabilities (Label3D, TextMesh, ViewportText) that make this feasible without custom rendering pipelines

### Previous Constraints

| Constraint | Detail |
|------------|--------|
| Engine | Godot 4.7.1 / GDScript 2.0 |
| Renderer | `forward_plus` (cannot switch to `mobile` or `gl_compatibility`) |
| Resolution | 1920×1080, Allow HiDPI |
| Theme | Edward Hopper urban night — warm/amber light on dark/cool backgrounds |
| Writing style | Hemingway — short text, iceberg theory (signs/graffiti are concise) |
| Platform | macOS / Linux |
| Existing scope | CRPG with heavy text + 2D Control UI for dialogue/status |
| Performance budget | No physics/action, but may have 3-8 text elements per scene |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `docs/PRD/44-lo-fi-3d-text-rendering.md` | PRD | **新建** — 本文档 |
| `gdscripts/lo_fi_text_3d.gd` (new) | Lo-Fi 3D Text | **新建** — Core text rendering controller | 
| `scenes/` (new) | 3D text scene templates | **新建** — Scene files for billboard, extruded, decal text |
| `shaders/lo_fi_text.gdshader` (new) | Lo-Fi shader | **新建** — Custom shader for pixelation, color reduction, scanlines |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `scenes/main.tscn` | Main scene | May need 3D node as root instead of flat Control; or add WorldEnvironment + Camera3D |
| `docs/DESIGN/44-lo-fi-3d-text-rendering.md` | Design doc | Plan phase will produce design document |
| `docs/GAME_DESIGN/01-OVERVIEW.md` | GDD | Visual direction chapter needs updating |
| `project.godot` | Project settings | May need shader type registration or rendering quality tweaks |

### Data Flow Impact

```
Godot 3D World Setup
    │
    ▼
LoFiText3D Controller (gdscripts/lo_fi_text_3d.gd)
    │
    ├──► Billboard Mode:  Label3D + PixelFont + Lo-Fi Shader → Quad facing camera
    ├──► Extruded Mode:   TextMesh + Lo-Fi Material → 3D sign geometry
    └──► Decal Mode:      Decal node + Lo-Fi texture from Viewport → Surface projection
    
    Each output node has:
    - LoFiShader material (pixelation + color reduction + scanlines)
    - Optional emissive / glow for neon effect
    - Billboard constraint (configurable per mode)
```

### Documents to Update

- [x] **本次产出:** `docs/PRD/44-lo-fi-3d-text-rendering.md`
- [ ] `docs/DESIGN/44-lo-fi-3d-text-rendering.md`（Plan 阶段产出）
- [ ] `docs/GAME_DESIGN/01-OVERVIEW.md`（补充 Lo-Fi 视觉方向描述）
- [ ] `docs/GAME_DESIGN/INDEX.md`（更新索引）

---

## 4. Solution Comparison

### Approach A: Label3D with Lo-Fi Shader

**Description:**

Use Godot 4.7's native `Label3D` node as the base, apply a custom `ShaderMaterial` that adds lo-fi effects (pixelation, color quantization, scanlines, chromatic aberration) via a fragment shader. Use a pixel-art bitmap font (`FontFile` with `.fnt` or `.png` font atlas) to achieve low-resolution text from the source.

**Pros:**
- Built-in Label3D handles billboarding, font rendering, line breaks, and all text layout natively
- Minimal GDScript code — material assignment + text setting is ~5 lines
- Godot 4.7's Label3D supports `pixel_size` property for pixelation at the node level
- Billboarding, offset, and pixel size are native properties
- Easy to instance: add Label3D as child → assign material → set text

**Cons:**
- Shader must run per-instance; with 8+ text elements visible, draw calls increase
- Emissive/neon glow requires WorldEnvironment + Glow pass in `forward_plus` (already configured)
- Decal (wall-following) text requires a separate approach — Label3D is planar, not surface-conforming
- Custom pixelation shader competes with built-in `pixel_size` property (need to disable one)

**Risk:** Low — Label3D is mature in Godot 4.7. Works out of the box with `forward_plus`.

**Effort:** 3 files (shader, script, scene) — ~100 lines total

---

### Approach B: Viewport-Based Decal + Billboard System

**Description:**

Create a single `SubViewport` per text element, render text via a 2D Control/Label node into the Viewport (with lo-fi effects as 2D shader), then project the Viewport texture onto a 3D surface as either a billboarded `Sprite3D` or a `Decal` for wall text.

**Pros:**
- Decouples text rendering (2D) from 3D projection — text layout, font, and lo-fi effects are handled in 2D space where Godot is strongest
- Same text can be projected as both billboard and decal from the same Viewport
- Lo-fi effects in 2D (shader on Control node) are easier to debug than 3D material shaders
- Supports any font (bitmap, dynamic, system) — pixelation is applied as post-effect
- Full Control node layout available for multi-line signs

**Cons:**
- Higher overhead: each text element = 1 SubViewport + 1 Sprite3D/Decal = 2 extra nodes
- Viewport scaling affects performance — 8 text elements = 8 extra viewport renders
- Billboarding and decal projection require separate 3D node types
- More complex scene setup and code management

**Risk:** Medium — Viewport-per-text can hit performance limits if 10+ elements are visible. Mitigate by culling far elements and using a shared Viewport pool.

**Effort:** 5 files (2 scripts, 2 scenes, 1 shader) — ~200 lines total

---

### Approach C: Custom Mesh Generation via ImmediateMesh/SurfaceTool

**Description:**

Generate 3D text meshes programmatically using Godot's `TextServer`, `Font.get_glyph_path()`, and `SurfaceTool` to create extruded or flat meshes from font outline data. Apply lo-fi effects via vertex shader (edge jitter, limited color palette, intentional UV distortion).

**Pros:**
- Full control over mesh topology — can create true 3D extruded text (neon tube effect with depth)
- No Label3D or Viewport overhead — single mesh per text element
- Vertex shader effects are cheaper than fragment shader pixelation
- Can bake lo-fi vertex data (random offsets, color indices) into the mesh for performance
- Most authentic "lo-fi 3D" feel — real geometry, not screen-space trickery

**Cons:**
- GDScript `TextServer` API is complex — requires `Font.get_glyph_list()`, `get_glyph_path()`, triangulation
- `SurfaceTool.generate_normals()` needed for lighting; extruded text requires depth offset logic
- No built-in billboarding — must implement as scripted transform update per frame
- Line wrapping, alignment, and RTL text require manual implementation
- Over-engineered for a CRPG where most text is flat billboards or signs

**Risk:** High — TextServer mesh generation in GDScript is fragile, and Godot 4.7's `TextServer` API changed significantly from 4.0. Risk of compatibility issues with future minor versions.

**Effort:** 6 files (2 scripts, 1 shader, scene, test) — ~400 lines total

---

### Comparison Summary

| Dimension | A: Label3D+Shader | B: Viewport+Decal | C: Custom Mesh |
|-----------|-------------------|-------------------|----------------|
| Implementation ease | ★★★★★ | ★★★☆☆ | ★★☆☆☆ |
| Lo-fi aesthetic control | ★★★★☆ | ★★★★★ | ★★★★★ |
| Performance (8+ elements) | ★★★★☆ | ★★★☆☆ | ★★★★★ |
| Decal/wall text support | ★☆☆☆☆ | ★★★★★ | ★★★☆☆ |
| Extruded/sign support | ★★★☆☆ | ★★☆☆☆ | ★★★★★ |
| Maintenance burden | ★★★★★ | ★★★☆☆ | ★★☆☆☆ |
| Godot 4.7 API stability | ★★★★★ | ★★★★★ | ★★★☆☆ |

### Recommendation

→ **Approach A (Label3D with Lo-Fi Shader) as primary**, with Approach B's Viewport technique reserved for wall graffiti (decal) text.

**Rationale:**

1. **Label3D is the Godot-native path** — it handles 90% of the use cases (signs, title cards, billboarded location text) with zero custom font rendering or mesh generation
2. **The lo-fi aesthetic can be achieved at the shader level** — a `ShaderMaterial` with pixelation factor + color quantization + scanline overlay applied to Label3D's quad produces the exact "worn CRT / low-res neon" look without touching the text engine
3. **Performance is a non-issue for a CRPG** — even 8 Label3D nodes with shaders is trivial for `forward_plus` at 1080p with no physics
4. **For wall decals** (the remaining ~20% use case), a lightweight Viewport + Decal approach can be added later when wall graffiti scenes are built. The core PRD focuses on the 80% case.

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path

1. Create `shaders/lo_fi_text.gdshader` with configurable: `pixel_factor` (float 0.0-1.0), `color_bits` (int 2-24 bits per channel), `scanline_intensity` (float 0.0-1.0), `glow_strength` (float 0.0-5.0)
2. Create `gdscripts/lo_fi_text_3d.gd` extending `Label3D` with exported properties: `text`, `pixel_factor`, `color_bits`, `scanline_intensity`, `emissive_color`, `emissive_strength`
3. Assign a pixel-art bitmap font (`res://assets/fonts/pixel_8x8.tres` or equivalent `.fnt`) as the Label3D font
4. Add a WorldEnvironment node with Glow enabled (for neon emission effect) to `main.tscn`
5. Place test 3D text elements in a test scene: one billboarded sign, one flat sign, one emissive neon sign
6. Run the scene — text renders in 3D with lo-fi aesthetic visible (pixelated edges, reduced colors, scanlines on transparency)

### Edge Cases

1. **Long text strings:** Billboard Label3D with multi-line text (signage with 2-3 short lines) — font size and pixel_factor must not break line readability
2. **Camera distance:** Text should remain readable at 5-15 meters (typical street scene distance). `pixel_size` on Label3D compensates for distance-based resolution
3. **Glow oversaturation:** High emissive strength + glow may wash out text on bright scenes — `glow_strength` must be clamped to prevent full-white bloom
4. **Color quantization banding:** With `color_bits < 4`, gradients may disappear entirely — acceptable for lo-fi aesthetic but must not make text unreadable
5. **Scanline only on transparent areas:** Scanline effect should apply to text pixels only, not the full quad — shader must use `TEXTURE` alpha to mask scanlines

### Failure Paths

1. **Pixel font not found:** If font resource path is invalid, Label3D falls back to system font → lo-fi aesthetic lost. Mitigation: provide a fallback embedded bitmap font.
2. **WorldEnvironment missing:** Glow pass won't work → emissive text appears flat but otherwise functional. Not a blocker.
3. **Shader compilation failure:** `forward_plus` may reject shader with unsupported operations. Mitigation: use only documented GLES3-compatible fragment shader operations.
4. **Label3D pixel_size conflicts with shader pixelation:** `pixel_size` on Label3D and `pixel_factor` in shader may compound → document that `pixel_size` should be 0.0 when shader pixelation is active.

> These directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| Godot 4.7 Label3D node | Stable | Low — mature in 4.7 |
| Godot 4.7 ShaderMaterial | Stable | Low — standard API |
| Godot 4.7 WorldEnvironment + Glow | Stable | Low — needed for neon effect |
| Pixel-art bitmap font asset | Needs creation | Med — need to create or source `pixel_8x8.fnt` bitmap font |

### Blocks

| Future Work | Priority |
|-------------|----------|
| 3D scene building (city streets, interiors) | Critical — scenes need 3D text elements to feel alive |
| State-world feedback (Issue #4) | Medium — text could change aesthetic based on player state |
| Title cards / chapter transitions | Medium — use extruded 3D text for chapter headers |

### Preparation Needed

- [ ] Source or create a pixel-art bitmap font (8×8 or 8×16) in `.fnt` format compatible with Godot 4.7's `FontFile`
- [ ] Create test 3D scene with `Camera3D`, `WorldEnvironment`, and a `MeshInstance3D` wall for decal testing
- [ ] Verify Godot 4.7.1's `forward_plus` renderer supports custom fragment shaders on Label3D nodes

---

## 7. Spike / Experiment (Optional — depth/standard only)

### Question to Answer

Does Godot 4.7's Label3D node correctly apply `ShaderMaterial` with screen-space pixelation effects without breaking text UV mapping or billboarding behavior?

### Method

1. Create a minimal Label3D node in a test scene
2. Assign a ShaderMaterial with a fragment shader that applies:
   - `vec2 uv = floor(UV * pixel_factor) / pixel_factor;` (pixelation)
   - `int r = int(COLOR.r * color_steps) / color_steps;` (color quantization)
3. Toggle billboard on/off and verify text remains pixelated (not re-sampled each frame)
4. Test with `pixel_size = 0.01` on Label3D to see how built-in pixelation interacts with shader pixelation

### Result

Expected: Label3D applies shader to its full quad (textured with the font atlas). Pixelation shader correctly reduces effective resolution of the text region. Billboard mode works independently of shader effects because the shader operates in UV space (not screen space).

Risk: If Label3D does not expose font atlas UVs in a standard way (uv = font glyph rect within the full texture), the pixelation shader may need UV normalization per glyph. This is an implementation detail for the Plan phase.

### Impact on Approach

If Label3D's UV space is per-quad (full texture atlas), pixelation will quantize the font atlas itself, making text look broken rather than lo-fi. In that case, Approach B (Viewport rendering to separate texture at low resolution, then projecting) becomes the safer path. The spike will determine which approach survives to Plan phase.

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*
> *It captures the current state of the feature area so the next agent can pick up*
> *without re-scanning all source files.*

The Godot 4.7 CRPG project currently renders all text as 2D Control Labels (`scenes/main.tscn`, `gdscripts/main.gd`). There is no 3D world scene yet — the game's main scene is a flat `Node` root with a single `Label` child.

The proposed approach (Approach A — Label3D with Lo-Fi Shader) builds on Godot 4.7's native 3D text infrastructure. The plan agent should produce:

1. `shaders/lo_fi_text.gdshader` — fragment shader with parameters: `pixel_factor`, `color_bits`, `scanline_intensity`, `glow_strength`
2. `gdscripts/lo_fi_text_3d.gd` — script extending `Label3D` with exported lo-fi parameters
3. A pixel-art bitmap font resource (`res://assets/fonts/pixel_font.tres`)
4. Updates to `scenes/main.tscn` or a new test 3D scene with `Camera3D` and `WorldEnvironment`

The main risk is Label3D's font atlas UV layout: if UVs cover the full texture atlas (not per-glyph), the pixelation shader must be adapted to operate in screen space or on a pre-rendered low-res text texture. The spike/experiment section tests this — if Label3D UV behavior is problematic, fall back to Approach B (Viewport → Sprite3D).

The secondary risk is the pixel font asset — `.fnt` bitmap fonts are less common in 2026 and may require creation via tools like `bmGlyph` or `AngelCode BMFont`. The Plan phase should include font generation steps.
