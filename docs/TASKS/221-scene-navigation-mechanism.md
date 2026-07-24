# Tasks: #221 — 场景间导航机制设计 (Scene Navigation Mechanism Design)

> Parent Issue: #221
> Agent: plan-agent
> Date: 2026-07-25
> Priority: high
> Estimated Duration: 5–6 days (P0+P1: 5 days, P2: 1 day)
> Prerequisites: #214 (Narrative Architecture ✅), #156 (ExitZone ✅), #142 (PlayerController ✅)
> Design Reference: `docs/DESIGN/221-scene-navigation-mechanism.md`

---

## Task Breakdown

### Phase 1: 核心引擎扩展 (Core Engine Extension) — P0 MVP Required

**Rationale:** The foundational components (title card overlay, fallback detection, extended SceneManager/GameManager) must exist before any scene-level configuration. All other work depends on these.

| # | Task | Description | Files | Dependencies | Estimate |
|:-:|------|-------------|-------|:-----------:|:--------:|
| 1.1 | Add navigation constants | Add NAV_STAY_THRESHOLD, NAV_WRONG_DIR_THRESHOLD, NAV_STUCK_VELOCITY_THRESHOLD, NAV_STUCK_DURATION, NAV_HINT_COOLDOWN, NAV_HINT_DISPLAY_DURATION, NAV_TITLE_DISPLAY_DURATION, NAV_FALLBACK_Y_THRESHOLD, NAV_FALLBACK_MAX, NAV_FALLBACK_FADE_DURATION to constants.gd | `gdscripts/constants.gd` | — | 0.25 h |
| 1.2 | Create SceneTitleOverlay node | Create CanvasLayer with ColorRect + TitleLabel + SubtitleLabel + AnimationPlayer. Implement show_title(scene_id, route_context) + hide_title(). Fade-in/out animations synchronized with 0.5s curtain. Auto-destroy after display_duration. | `gdscripts/scene_title_overlay.gd` | 1.1 | 1.5 h |
| 1.3 | Extend SceneManager — trigger_zone_transition() | Add trigger_zone_transition() method matching ExitZone call pattern. Reads NavigationContext from GameManager. Calls _show_title_overlay() during fade. | `gdscripts/scene_manager.gd` | 1.2 | 0.5 h |
| 1.4 | Create NavFallback node | Implement height detection (< -10), velocity-stuck detection (< 0.01 for 3s), fallback teleport to SpawnPoint, fallback counter (max 3 → title_screen), fallback text display. Quick fade-in/out (0.3s). | `gdscripts/nav_fallback.gd` | 1.1, 1.3 | 1.5 h |
| 1.5 | Extend GameManager — navigation state | Add navigation_context Dictionary, fallback_count int. Extend reset() to clear both. | `gdscripts/game_manager.gd` | — | 0.25 h |
| 1.6 | Extend ExitZone — navigation context | Add exit_label (String) and route_hint (String) exports. Modify _transition() to set navigation_context on GameManager before calling trigger_zone_transition(). | `gdscripts/exit_zone.gd` | 1.5 | 0.25 h |
| 1.7 | Extend PlayerController — H-key binding | Add navigate_hint input action (KEY_H), navigation_hint_requested signal. Process in _input() when not in dialogue. | `gdscripts/player_controller.gd` | 1.1 | 0.25 h |
| 1.8 | Add navigate_hint to InputMap verification | Update GameManager._verify_input_map() and PlayerController._setup_input_actions() to include "navigate_hint" action. | `gdscripts/game_manager.gd`, `gdscripts/player_controller.gd` | 1.7 | 0.1 h |
| 1.9 | Verify Phase 1 with headless test | Run `godot --headless --quit` to confirm no parse/runtime errors. Write basic GDScript test for SceneTitleOverlay creation and NavFallback detection. | `tests/unit/test_navigation_core.gd` | 1.1–1.8 | 0.5 h |

**Phase 1 Total:** ~4.6 hours (0.6 days)

---

### Phase 2: 环境引导配置 (Environmental Guidance Configuration) — P0 MVP Required

**Rationale:** Each scene needs ExitZone placement, environmental lighting/text modifications, and navigation hook-up. This is per-scene configuration work layered on the Phase 1 core.

| # | Task | Description | Files | Dependencies | Estimate |
|:-:|------|-------------|-------|:-----------:|:--------:|
| 2.1 | Extend SceneBase — navigation setup | Add export vars (enable_navigation, scene_title_chinese). Add _setup_navigation() in _ready(). Add virtual methods: _show_navigation_hint(text), _on_condition_text_updated(hint). Wire NavigationController creation and signal connections. | `gdscripts/scene_base.gd` | 1.4, 1.6, 1.7 | 1 h |
| 2.2 | Configure office scene | Place ExitZone at door (AUTO mode, target lobby). Add door crack light glow (OmniLight3D). Add EXIT sign text. Set scene_title_chinese = "办公室". Override _on_condition_text_updated() and _show_navigation_hint(). | `scenes/office/office.tscn`, `gdscripts/office.gd` | 2.1 | 0.75 h |
| 2.3 | Configure lobby scene | Place ExitZone at side door (AUTO, target store) and return ExitZone to office (EKEY). Add Stranger posture guidance. Add warm/cool light at exits. Set scene_title_chinese = "大厅". | `scenes/lobby/lobby.tscn`, `gdscripts/lobby.gd` | 2.1 | 0.75 h |
| 2.4 | Configure convenience_store scene | Place ExitZone at back door (AUTO, target bridge) and street exit (EKEY). Add green exit light at back door. Add street sound seepage. Set scene_title_chinese = "便利店". | `scenes/store/convenience_store.tscn`, `gdscripts/store.gd` | 2.1 | 0.75 h |
| 2.5 | Configure bridge scene | Place ExitZone at far end (AUTO, target underpass) and near end (AUTO, target store). Add city skyline glow at far end. Set scene_title_chinese = "天桥". | `scenes/bridge/bridge.tscn`, `gdscripts/bridge.gd` | 2.1 | 0.75 h |
| 2.6 | Configure underpass scene | Place ExitZone at far end (AUTO, target subway_station) and near end (AUTO, target bridge). Add exit light circles at both ends. Set scene_title_chinese = "地下通道". | `scenes/underpass/underpass.tscn`, `gdscripts/underpass.gd` | 2.1 | 0.75 h |
| 2.7 | Configure subway_station scene | Place ExitZone at platform (AUTO, triggers ending). Add platform lights, Stranger at platform edge. Set scene_title_chinese = "地铁站". | `scenes/subway_station/subway_station.tscn`, `gdscripts/subway_station.gd` | 2.1 | 0.5 h |
| 2.8 | Verify Phase 2 with flow test | Run Godot headless. Walk through all 6 scene transitions. Verify each ExitZone transitions correctly. Verify scene title cards appear during fade. | `tests/unit/test_navigation_scenes.gd` | 2.2–2.7 | 0.5 h |

**Phase 2 Total:** ~5.75 hours (0.75 days)

---

### Phase 3: 条件触发检测与提示键 (Condition Detection & Hint Key) — P1 MVP Recommended

**Rationale:** The NavigationController (stay timer, direction detection, H-key hint) adds player assistance without breaking immersion. This phase directly implements the "conditional trigger" part of Approach C.

| # | Task | Description | Files | Dependencies | Estimate |
|:-:|------|-------------|-------|:-----------:|:--------:|
| 3.1 | Create NavigationController node | Full implementation: per-scene stay timer (>60s), wrong-direction timer (>30s), stuck timer (>3s), H-key hint routing. Raycast-based exit direction detection. One-shot condition flags. Hint cooldown. Signal emissions for all conditions. Register navigate_hint input. | `gdscripts/navigation_controller.gd` | 2.1 | 2 h |
| 3.2 | Implement scene hint text tables | Define all 6 scenes × 3 route archetypes hint texts (18 variants) in NavigationController. Route determination from tone lookup. Hemingway-constrained (≤25 chars/sentence, ≤3 sentences). | `gdscripts/navigation_controller.gd` | 3.1 | 0.5 h |
| 3.3 | Implement condition-triggered text display | Connect NavigationController.condition_text_updated → SceneBase._on_condition_text_updated → scene-specific text node update. Auto-revert to tone-based text after 5s. | `gdscripts/scene_base.gd`, all scene subclasses | 3.1 | 0.5 h |
| 3.4 | Implement H-key hint overlay | Create CanvasLayer-based hint text display (semi-transparent, bottom-center). Connected to NavigationController.navigation_hint_requested. Auto-dismiss after NAV_HINT_DISPLAY_DURATION. Hemingway-constrained. | `gdscripts/scene_base.gd` (inline CanvasLayer creation) | 3.1, 3.2 | 0.5 h |
| 3.5 | Verify condition triggers | Write headless tests: simulate player staying >60s, facing wrong direction >30s, pressing H key. Verify signal emissions and text updates. | `tests/unit/test_navigation_conditions.gd` | 3.1–3.4 | 0.5 h |

**Phase 3 Total:** ~4 hours (0.5 days)

---

### Phase 4: 路线感知导航差异化 (Route-Aware Navigation Differentiation) — P2 Post-MVP

**Rationale:** Route-aware text differentiation enriches the narrative but is not required for MVP gameplay. Can be deferred without blocking the player.

| # | Task | Description | Files | Dependencies | Estimate |
|:-:|------|-------------|-------|:-----------:|:--------:|
| 4.1 | Implement per-tone navigation text | Map all 17 tones (from SCENE_TONES) to navigation text templates. NavigationController.get_exit_hint_text() selects template based on current scene tone from NarrativeManager. | `gdscripts/navigation_controller.gd` | 3.2 | 1 h |
| 4.2 | Implement route indicator in title card | SceneTitleOverlay reads route context from NavigationContext.route_hint. Displays route-appropriate subtitle on title card. | `gdscripts/scene_title_overlay.gd` | 1.2, 4.1 | 0.25 h |
| 4.3 | Verify route-aware text chain | Test all 3 route archetypes across all 6 scenes. Verify tone-derived text matches expected route narrative arc. Check Hemingway constraint adherence. | `tests/unit/test_navigation_routes.gd` | 4.1–4.2 | 0.5 h |

**Phase 4 Total:** ~1.75 hours (0.25 days)

---

## Dependencies Between Tasks

```
Phase 1 (Core Engine)
├── 1.1 (Constants)
├── 1.2 (SceneTitleOverlay) ── 1.3 (SceneManager trigger_zone_transition)
├── 1.4 (NavFallback)
├── 1.5 (GameManager nav state) ── 1.6 (ExitZone nav context)
├── 1.7 (PlayerController H-key) ── 1.8 (InputMap verification)
└── 1.9 (Verify Phase 1)

Phase 2 (Environmental Guidance) ← Phase 1 core
├── 2.1 (SceneBase nav setup)
├── 2.2 (Office) ── 2.3 (Lobby) ── 2.4 (Store)
│                   └── 2.5 (Bridge) ── 2.6 (Underpass) ── 2.7 (Subway)
└── 2.8 (Verify Phase 2)

Phase 3 (Condition Detection) ← Phase 2 SceneBase + PlayerController
├── 3.1 (NavigationController)
├── 3.2 (Hint text tables) ── 3.3 (Condition-triggered display)
│                           └─ 3.4 (H-key overlay)
└── 3.5 (Verify Phase 3)

Phase 4 (Route-Aware) ← Phase 3 NavigationController
├── 4.1 (Per-tone text) ── 4.2 (Route in title card)
└── 4.3 (Verify Phase 4)
```

## Implementation Order

Recommended implementation order within each phase:

1. **Phase 1:** 1.1 → 1.5 → 1.2 → 1.3 → 1.4 → 1.6 → 1.7 → 1.8 → 1.9
2. **Phase 2:** 2.1 → 2.2 → 2.3 → 2.4 → 2.5 → 2.6 → 2.7 → 2.8
3. **Phase 3:** 3.1 → 3.2 → 3.3 → 3.4 → 3.5
4. **Phase 4:** 4.1 → 4.2 → 4.3

## Verification Strategy

### Per-Task Verification
- Each GDScript file: run `godot --headless --quit` to check compile errors
- Each scene: load in headless mode, verify no null reference errors

### Phase Verification
- **Phase 1:** 6-scene transition chain works with title cards during fades. Fallback triggers on y < -10.
- **Phase 2:** Every scene has ExitZone placed at correct exit. Player can walk through all 6 scenes.
- **Phase 3:** Stay >60s triggers text update. Wrong direction >30s triggers text. H key shows hint.
- **Phase 4:** Title card text differs by route. Hint text changes with NarrativeManager tone.

### Full Integration
- Run complete playthrough (office → subway_station) with navigation enabled
- Test fallback by walking player off-map
- Test H-key hint at each scene
- Verify no conflicts with dialogue engine, hallucination system, worldview filter
