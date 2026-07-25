# Tasks: #216 — 集成 godot-minimal-theme UI 主题

> Parent Issue: #216
> Agent: plan-agent
> Date: 2026-07-25

---

## Task Breakdown

### Phase 1: Theme Resource Creation

| # | Task | Description | Est. Effort | Who |
|---|------|-------------|-------------|-----|
| 1.1 | Create `assets/themes/` directory | `mkdir -p assets/themes/` | ~1 min | Implement |
| 1.2 | Create `assets/themes/neon_theme.tres` | Write the complete Theme resource with all color constants, StyleBoxFlat definitions per Control type, font references, and custom constants. See DESIGN doc Section 2 for color tokens and Section 3 for StyleBox parameters. | ~20 min | Implement |
| 1.3 | Add custom color constants | Define `neon_blue`, `neon_red`, `bg_dark`, `bg_panel`, `text_primary` as custom constants via `theme.set_color()` or Theme resource editor | ~5 min | Implement |
| 1.4 | Reference pixel_font.tres | Set `default_font` on all Control types in the Theme to `preload("res://assets/fonts/pixel_font.tres")` | ~3 min | Implement |

### Phase 2: Scene Migration

| # | Task | Description | Est. Effort | Who |
|---|------|-------------|-------------|-----|
| 2.1 | Migrate `title_screen.tscn` | Remove empty SubResource Theme (`Theme_4a6q1` if present); remove all `theme_override_*` on VBoxContainer, Labels, Buttons; set root node `theme = neon_theme.tres` | ~10 min | Implement |
| 2.2 | Migrate `dialogue_panel.tscn` | Remove SubResource StyleBoxFlat definitions; remove `theme_override_styles/panel`, `theme_override_colors/font_color`, `theme_override_fonts/font` on Panel and Label children; set root `theme = neon_theme.tres` | ~8 min | Implement |
| 2.3 | Migrate `dialogue_balloon.tscn` | Replace warm brown `Color(0.58, 0.44, 0.22)` with Theme inheritance; remove SubResource StyleBoxFlat; remove `theme_override_*` on CharacterLabel, DialogueLabel, ResponseButton; set root node `theme = neon_theme.tres` | ~12 min | Implement |
| 2.4 | Migrate `response_panel.tscn` | Add root node `theme = neon_theme.tres`; no overrides to remove (verify none exist) | ~3 min | Implement |
| 2.5 | Verify `status_bar.tscn` | Confirm status bar retains its Hopper colors (amber #FFB000 / dark blue #2A2A4A). Optionally add theme for font reference only. No migration needed if colors are independent. | ~3 min | Implement |

### Phase 3: Validation & Testing

| # | Task | Description | Est. Effort | Who |
|---|------|-------------|-------------|-----|
| 3.1 | Run headless compile test (main project) | `godot --headless --quit` — must show zero errors/warnings | ~10 sec | Implement |
| 3.2 | Run headless compile test (sub-project) | `godot --path rainy-night-prometheus/ --headless --quit` — must show zero errors | ~10 sec | Implement |
| 3.3 | Visual verification — title_screen | Open scene in editor; confirm bg_dark background, text_primary labels, neon_blue button hover | ~2 min | Implement |
| 3.4 | Visual verification — dialogue_panel | Open scene in editor; confirm bg_panel surface, text_primary text | ~2 min | Implement |
| 3.5 | Visual verification — dialogue_balloon | Open scene in editor; confirm warm brown replaced by bg_panel + text_primary | ~2 min | Implement |
| 3.6 | Visual verification — response_panel | Open scene in editor; confirm buttons get neon_blue accent | ~2 min | Implement |
| 3.7 | Visual verification — status_bar | Confirm Hopper colors intact (not accidentally overridden) | ~1 min | Implement |

### Phase 4: Cleanup & Merge

| # | Task | Description | Est. Effort | Who |
|---|------|-------------|-------------|-----|
| 4.1 | `git add assets/themes/` | Track the new Theme resource directory | ~1 min | Implement |
| 4.2 | Git commit and push | Commit with message: `feat(ui): implement neon_theme.tres and migrate 5 UI scenes (#216)` | ~1 min | Implement |
| 4.3 | Open PR | Create PR from `impl/216-godot-minimal-theme` → `main` with body "Parent #216" | ~1 min | Implement |
| 4.4 | Update GDD | Add Theme architecture section to `docs/GAME_DESIGN/03-GODOT-SETUP.md` | ~5 min | Separate Issue |

---

## Dependencies Between Tasks

```
Phase 1: Theme Resource
│
1.1 (Create theme directory)
  └── 1.2 (Create neon_theme.tres)
       ├── 1.3 (Add custom constants)
       └── 1.4 (Reference pixel_font)
            │
            ▼
Phase 2: Scene Migration
│
2.1 (title_screen) ── 2.2 (dialogue_panel) ── 2.3 (dialogue_balloon)
   └── 2.4 (response_panel) ── 2.5 (status_bar verification)
                                  │
                                  ▼
Phase 3: Validation
│
3.1 (Headless main) ── 3.2 (Headless sub-project)
   ├── 3.3 (Visual: title_screen)
   ├── 3.4 (Visual: dialogue_panel)
   ├── 3.5 (Visual: dialogue_balloon)
   ├── 3.6 (Visual: response_panel)
   └── 3.7 (Visual: status_bar)
        │
        ▼
Phase 4: Cleanup & Merge
│
4.1 (git add themes/) ── 4.2 (Commit) ── 4.3 (Open PR)
```

> **Note:** Tasks 2.1–2.5 can be done in parallel if the Theme resource (Phase 1) is complete, but sequential migration (title_screen first as the simplest) is recommended for reduced risk.

---

## Acceptance Criteria Mapping

| AC | Description | Verified By |
|----|-------------|-------------|
| AC1 | Theme resource exists and loads without errors | Task 3.1 |
| AC2 | Color scheme matches neon spec (#0a0a12, #4a90d9, #ff3355) | Tasks 3.3–3.7 |
| AC3 | Built-in UI components display correct theme colors | Tasks 3.3, 3.4, 3.5, 3.6 |
| AC4 | Custom UI (dialogue_balloon) uses theme colors (no warm brown) | Task 3.5 |
| AC5 | No engine errors in headless mode (main + sub-project) | Tasks 3.1, 3.2 |

---

## Effort Summary

| Phase | Tasks | Est. Total Time |
|-------|-------|----------------|
| Phase 1: Theme Resource | 4 tasks | ~29 min |
| Phase 2: Scene Migration | 5 tasks | ~36 min |
| Phase 3: Validation | 7 tasks | ~9 min 20 sec |
| Phase 4: Cleanup & Merge | 4 tasks | ~8 min |
| **Total** | **20 tasks** | **~82 min (~1.5 hrs)** |
