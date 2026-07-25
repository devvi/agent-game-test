# Design: #216 — 集成 godot-minimal-theme UI 主题

> Parent Issue: #216
> Agent: plan-agent
> Date: 2026-07-25

---

## 1. Architecture Overview

### Core Idea

Create a centralized `Theme` resource (`assets/themes/neon_theme.tres`) that defines all UI component colors, StyleBoxes, fonts, and custom constants for the MVP game. Each of the 5 existing UI scenes is migrated from scattered `theme_override_*` / inline SubResource styles to inherit from this single Theme resource.

This approach (Approach A from the PRD) avoids affecting the `addons/dialogue_manager/` plugin's internal UI, since Theme inheritance is per-scene rather than global.

### Theme Resource Hierarchy

```
assets/themes/neon_theme.tres  (Theme)
    │
    ├── Color Schemes (per Control type)
    │   ├── Label         → font_color, font_color_shadow
    │   ├── Button        → font_color, font_color_hover, font_color_pressed, font_color_disabled
    │   ├── RichTextLabel → font_color, font_color_shadow
    │   ├── Panel         → (via StyleBox — no direct color on Panel)
    │   ├── LineEdit      → font_color, font_color_cursor, font_color_placeholder
    │   ├── CheckBox      → font_color
    │   ├── ScrollBar     → (via StyleBox)
    │   ├── HSlider/VSlider → (via StyleBox)
    │   └── OptionButton  → font_color
    │
    ├── StyleBoxes (StyleBoxFlat per Control type + state)
    │   ├── Panel         → panel (bg_panel, corner_radius=8)
    │   ├── Button        → normal, hover, pressed, disabled, focus
    │   ├── LineEdit      → normal, focus, readonly
    │   ├── CheckBox      → normal, hover, pressed, disabled
    │   ├── HScrollBar    → grabber, grabber_highlight, scroll
    │   ├── VScrollBar    → grabber, grabber_highlight, scroll
    │   ├── HSlider       → grabber, grabber_highlight
    │   ├── VSlider       → grabber, grabber_highlight
    │   ├── Tree          → panel, focus, selected, selected_focus
    │   └── TooltipPanel  → panel
    │
    ├── Fonts → pixel_font.tres (all Control types)
    │
    └── Custom Constants → theme.get_color("neon_blue", "Custom")
        ├── neon_blue    = #4a90d9
        ├── neon_red     = #ff3355
        ├── bg_dark      = #0a0a12
        ├── bg_panel     = #141420
        └── text_primary = #d0d0e0
```

### Theme Inheritance Model

```
Scene Root (e.g., title_screen Root → theme = neon_theme.tres)
    │
    └── All Control children inherit automatically
         │
         ├── Panel (gets StyleBox from theme Panel/panel)
         ├── Label (gets font_color from theme Label/font_color)
         ├── Button (gets font_color + all StyleBox states)
         └── RichTextLabel (gets font_color)
```

> In Godot 4.x, Theme inheritance is automatic via the scene tree. Setting `theme` on the root Control node cascades to all descendants. Control nodes can still have per-node `theme_override_*` which takes priority over the inherited Theme — all existing `theme_override_*` must be removed during migration.

---

## 2. Color Token System

### Master Color Palette

| Token | Hex | RGB | Use |
|-------|-----|-----|-----|
| `bg_dark` | `#0a0a12` | `Color(0.039, 0.039, 0.071)` | Global background (title screen, panel backgrounds) |
| `bg_panel` | `#141420` | `Color(0.078, 0.078, 0.125)` | Panel/bubble background surfaces |
| `bg_surface` | `#1c1c2e` | `Color(0.110, 0.110, 0.180)` | Button/input/dropdown backgrounds |
| `bg_hover` | `#24243b` | `Color(0.141, 0.141, 0.231)` | Button hover/input focus background |
| `neon_blue` | `#4a90d9` | `Color(0.290, 0.565, 0.851)` | Primary accent — selected state, links, focus borders |
| `neon_red` | `#ff3355` | `Color(1.0, 0.200, 0.333)` | Warning/accent — special markers |
| `text_primary` | `#d0d0e0` | `Color(0.816, 0.816, 0.878)` | Main body text (Label, Button text) |
| `text_secondary` | `#808098` | `Color(0.502, 0.502, 0.596)` | Secondary/disabled/muted text |
| `text_link` | `#4a90d9` | `Color(0.290, 0.565, 0.851)` | Link/interactive text (same as neon_blue) |
| `border_default` | `#2a2a3e` | `Color(0.165, 0.165, 0.243)` | Default border for unfocused inputs |
| `border_focus` | `#4a90d9` | `Color(0.290, 0.565, 0.851)` | Focus border (same as neon_blue) |

### Derived Style Constants

| Constant | Value | Notes |
|----------|-------|-------|
| `corner_radius` | `8` | All StyleBoxFlat corner radius |
| `border_width` | `1` | All StyleBoxFlat border width |
| `font_size_body` | `16` | Body text size (Label, Button, RichTextLabel) |
| `font_size_small` | `12` | Secondary/helper text |
| `font_size_title` | `48` | Title screen heading |
| `panel_opacity` | `0.9` | Panel/StyleBox background alpha |

### Color Application Matrix

| Control Type | Property | Token |
|-------------|----------|-------|
| Label | font_color | text_primary |
| Label | font_color_shadow | bg_dark (with alpha) |
| Button | font_color | text_primary |
| Button | font_color_hover | neon_blue |
| Button | font_color_pressed | neon_blue (darker) |
| Button | font_color_disabled | text_secondary |
| RichTextLabel | font_color | text_primary |
| LineEdit | font_color | text_primary |
| LineEdit | font_color_cursor | neon_blue |
| LineEdit | font_color_placeholder | text_secondary |
| CheckBox | font_color | text_primary |

---

## 3. StyleBox Design

### StyleBoxFlat Parameters

All StyleBox definitions use these base parameters unless overridden:

```gdscript
# Base StyleBoxFlat config
corner_radius_top_left = 8
corner_radius_top_right = 8
corner_radius_bottom_right = 8
corner_radius_bottom_left = 8
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
content_margin_* = 8  # left/right/top/bottom
```

### Per-Control StyleBox Configurations

| Control | State | bg_color | border_color | Notes |
|---------|-------|----------|-------------|-------|
| **Panel** | panel | bg_panel | border_default | Main container surface |
| **Button** | normal | bg_surface | border_default | |
| **Button** | hover | bg_hover | neon_blue | Border highlights on hover |
| **Button** | pressed | neon_blue (dim) | neon_blue | Filled accent on press |
| **Button** | disabled | bg_surface | border_default (0.5α) | Dimmed border |
| **Button** | focus | bg_surface | border_focus | Matches hover border |
| **LineEdit** | normal | bg_surface | border_default | |
| **LineEdit** | focus | bg_surface | border_focus | |
| **LineEdit** | readonly | bg_surface | border_default (0.5α) | |
| **CheckBox** | normal | transparent | — | CheckBox uses minimal style |
| **CheckBox** | hover | bg_hover | — | Subtle background fill |
| **ScrollBar** | grabber | neon_blue | — | Thin accent bar |
| **ScrollBar** | grabber_highlight | neon_blue (bright) | — | Brighter on hover |
| **ScrollBar** | scroll | bg_surface | — | Track background |
| **HSlider** | grabber | neon_blue | — | Circle grabber |
| **HSlider** | grabber_highlight | neon_blue (bright) | — | |
| **VSlider** | grabber | neon_blue | — | |
| **VSlider** | grabber_highlight | neon_blue (bright) | — | |
| **TooltipPanel** | panel | bg_panel | border_focus | Tooltip background |

---

## 4. Migration Strategy

### Scene-by-Scene Migration Order

```
Phase 1: Theme Resource Creation
    └── assets/themes/neon_theme.tres (new)

Phase 2: Scene Migration (ordered by risk)
    ├── 1. title_screen.tscn       [LOW RISK] — empty Theme subresource, clear overrides
    ├── 2. dialogue_panel.tscn     [LOW RISK] — simple StyleBoxFlat + color overrides
    ├── 3. dialogue_balloon.tscn   [MEDIUM RISK] — warm brown → neon transition
    ├── 4. response_panel.tscn     [LOW RISK] — no existing overrides
    └── 5. status_bar.tscn         [LOW RISK] — only font reference, keep colors

Phase 3: Validation
    ├── Headless compile test (no errors)
    └── Visual consistency check
```

### Migration Checklist per Scene

Each migrated scene must pass these checks:

1. **Remove all `theme_override_*` entries** from every Control node
2. **Remove SubResource Theme definitions** (empty placeholder themes)
3. **Set `theme = preload("res://assets/themes/neon_theme.tres")`** on the root Control node
4. **Verify no orphaned SubResources** remain in the `.tscn` file
5. **Verify dialogue_balloon warm brown override**: `Color(0.58, 0.44, 0.22)` must be replaced or overridden by the Theme's `text_primary` color
6. **Run `godot --headless --quit`** to confirm no errors

### Status Bar Exception

The status bar (`scenes/ui/status_bar.tscn`) uses a distinct Hopper-inspired color scheme (amber `#FFB000` / dark blue `#2A2A4A`). Per the PRD decision, it **keeps its independent colors** but should reference the Theme's pixel_font for text consistency. The status bar's `theme_override` for font only is acceptable — the color identity is intentional.

---

## 5. GDScript Integration Points

### theme.get_color() Usage

Scripts that need runtime access to theme colors should use the standard Godot API:

```gdscript
# In any Control-derived script:
var neon_blue = get_theme_color("neon_blue", "Custom")
var bg_panel = get_theme_color("bg_panel", "Custom")
```

### Theme Change Propagation

If Theme needs to change at runtime (e.g., color shifts based on game state):

```gdscript
# On the scene root Control node:
var new_theme = preload("res://assets/themes/neon_theme.tres")
new_theme.set_color("neon_blue", "Custom", Color.hex(0x6ab0ff))
theme = new_theme
```

> **Note:** Theme updates after scene load require explicit reassignment to propagate to children. Simply mutating the Theme resource does NOT cascade.

### Dialog Balloon Color Override

The `dialogue_balloon.tscn` has hardcoded warm brown in its Panel StyleBox. The implementation strategy is:

1. Set the Panel's `theme` to the neon theme (or inherit from parent)
2. Remove the hardcoded `Color(0.58, 0.44, 0.22)` SubResource
3. If the dialogue_manager plugin's balloon template refuses theme inheritance, override via `theme_override` in the scene in `_ready()`:
   ```gdscript
   $Balloon/BalloonPanel.add_theme_stylebox_override("panel", my_neon_stylebox)
   ```

---

## 6. File Structure Changes

### New Files

| File | Purpose | Est. Size |
|------|---------|-----------|
| `assets/themes/neon_theme.tres` | Main Theme resource | ~150 lines |
| `assets/themes/` | Directory for Theme resources | — |

### Modified Files

| File | Changes |
|------|---------|
| `scenes/title_screen.tscn` | Remove SubResource Theme_4a6q1; remove theme_override_* on VBoxContainer, Label, Button; set root theme |
| `scenes/dialogue/dialogue_panel.tscn` | Remove SubResource StyleBoxFlat; remove theme_override(font_color, font, panel); set root theme |
| `scenes/dialogue/dialogue_balloon.tscn` | Replace warm brown Color(0.58, 0.44, 0.22); remove SubResource StyleBoxFlat; set root theme |
| `scenes/dialogue/response_panel.tscn` | Set root theme; no overrides to remove |
| `scenes/ui/status_bar.tscn` | Optional: add root theme (or keep independent — font reference only) |

### Files NOT Modified

| File | Reason |
|------|--------|
| `addons/dialogue_manager/*` | Theme is per-scene; addon internals unaffected |
| `rainy-night-prometheus/*` | Sub-project will inherit via symlink if same path; no changes needed here |
| `project.godot` | Not using global theme setting (Approach B rejected) |

---

## 7. Testing Strategy

### Headless Validation

```bash
# Main project — must pass with zero errors
godot --headless --quit

# Sub-project — must also pass with zero errors
godot --path rainy-night-prometheus/ --headless --quit
```

### Visual Verification Points (Manual)

| Element | Expected Color | Check |
|---------|---------------|-------|
| Title screen background | #0a0a12 | Panel bg |
| Title screen label text | #d0d0e0 | Label font_color |
| Title screen button normal | bg_surface bg, border_default border | Button normal |
| Title screen button hover | bg_hover bg, neon_blue border | Button hover |
| Dialogue panel background | #141420 | Panel bg |
| Dialogue label text | #d0d0e0 | RichTextLabel font_color |
| Dialogue balloon background | #141420 | Panel bg (was warm brown) |
| Dialogue balloon character name | #d0d0e0 | Label font_color |
| Dialogue balloon dialogue text | #d0d0e0 | Label font_color |
| Response button normal | bg_surface bg | Button normal |
| Status bar | amber #FFB000 + dark blue #2A2A4A | Unchanged (Hopper style) |
| LineEdit cursor | #4a90d9 | font_color_cursor |
| ScrollBar grabber | #4a90d9 | grabber bg |

---

## 8. Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| `theme_override_*` priority over Theme | Style not applied | High | Remove all theme_override_* entries during migration |
| dialogue_balloon warm brown persists | Wrong color shown | Medium | Explicitly check and replace Color(0.58, 0.44, 0.22) |
| dialogue_manager addon uses overrides | Inconsistent look | Low | Per-scene Theme doesn't affect addon; verify on case-by-case |
| StyleBoxFlat + Glow post-process conflict | UI too bright | Low | CanvasLayer UI not affected by WorldEnvironment Glow |
| Sub-project `res://` path mismatch | Theme not found | Medium | Verify symlink structure; test with `--path rainy-night-prometheus/` |
| Theme resource not committed | CI fails on clone | Low | Ensure `git add assets/themes/` before commit |
| New scenes forget Theme reference | Inconsistent look | Medium | Add to checklists and onboarding docs |

---

## 9. Future Considerations

- **Runtime Theme switching**: Architecture supports swapping Theme at runtime for accessibility (high-contrast mode) or visual states (damage vignette, underwater filter)
- **Theme variants**: Future issues could add `neon_theme_hc.tres` (high contrast) or `neon_theme_sepia.tres` for specific narrative sequences
- **GDScript ThemeBuilder**: If runtime flexibility is needed later, the centralized `.tres` approach can be wrapped by a `theme_builder.gd` autoload without breaking existing scenes
- **Theming in sub-projects**: The symlink structure from #213 means `rainy-night-prometheus/` can reference the same `res://assets/themes/neon_theme.tres` path — but the Theme resource must be explicitly added to the sub-project's `.godot` import cache
