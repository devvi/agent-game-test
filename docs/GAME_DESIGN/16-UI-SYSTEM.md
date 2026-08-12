# UI System — Menus, HUD, and Game Over

> Reference: ../DESIGN/292-ui-system.md
> Parent Issue: #292

## Overview

The UI system provides three CanvasLayer scenes that form the complete display layer for Mini Pong:
- **StartMenu** — Neon title screen with pulsing glow and SPACE-to-start prompt
- **GameHUD** — Top-center score display for player and AI
- **GameOverScreen** — Winner announcement with SPACE-to-restart

Layers consume signals from the `GameManager` autoload and use the neon color palette from #289.

## Architecture

Three independent CanvasLayer nodes embedded in `game.tscn`, each driven by its own GDScript:

| Layer | Scene File | Script | Layer | Initial Visible |
|-------|-----------|--------|-------|----------------|
| StartMenu | `ui_start_menu.tscn` | `start_menu.gd` | 1 | true |
| GameHUD | `ui_game_hud.tscn` | `game_hud.gd` | 1 | false |
| GameOverScreen | `ui_game_over.tscn` | `game_over_screen.gd` | 1 | false |

Only one CanvasLayer is visible at any time. Transitions are driven by SPACE key input and `GameManager` signals.

## State Transitions

```
StartMenu  ──SPACE──►  GameHUD  ──match_over──►  GameOverScreen
     ▲                                                │
     └──────────── SPACE ────────────────────────────┘
```

## Signal Wiring

| Connection | Source | Target | When |
|-----------|--------|--------|------|
| `score_changed(p, a)` → label update | GameManager | game_hud.gd | On `_ready()` |
| `match_over(winner)` → winner display | GameManager | game_over_screen.gd | On `_ready()` |
| `brick_scored(side)` → 拆砖子区 | GameManager | game_hud.gd | `_bump_count` 之后、`score_changed` 之前（#392） |
| `pierce_scored(side)` → 穿墙子区 | GameManager | game_hud.gd | 同上（#392） |
| `wave_started(idx)` → 信息条 | GameManager | game_hud.gd | 波次切换（帧末 call_deferred 回退读剩余砖数） |
| `brick_destroyed` / `wall_cleared` / `wall_generated` → 剩余砖数 | BreakoutGrid (#384) | game_hud.gd | has_signal 守卫，容错（#393 接线后生效） |
| `scored.emit()` → `GameManager.add_score()` | ScoringManager | GameManager | On ball score |

The critical bridge is a 1-line addition in `scoring_manager.gd:_on_ball_score()`:
```gdscript
GameManager.add_score(winner)
```
Without this, GameManager signals never fire and the HUD never updates.

## Scene Design

### StartMenu

- **TitleLabel**: "PONG://NEON" at 64px, centered, neon blue (#4a90d9) — text finalized by user decision (#378, 2026-08-11)
- **PromptLabel**: "按 SPACE 开始" at 28px, centered, blue at 70% alpha
- **VersionLabel**: "v1.0.0" at 16px, bottom-left anchored (16px left / 12px bottom margin), neon blue (#4a90d9) at 60% alpha — text sourced from `GameConstants.GAME_VERSION` (single source of truth, set in `start_menu.gd:_ready()`; static .tscn text is only a fallback)
- **Animation**: Title alpha pulses between 0.6–1.0 (1.5s cycle), prompt blinks (0.8s cycle)
- **Input**: SPACE key triggers `_on_start_pressed()` → hides menu, shows HUD, calls `GameManager.reset_match()`

### GameHUD（三区霓虹布局 #392）

- **顶部 AI 红区**（y∈[12,84]，全宽）：`AIScoreLabel`（28px）+ 拆砖/穿墙双子区 `AIBrickLabel` / `AIPierceLabel`（20px），霓虹红 #ff3355
- **中立信息条** `InfoBar`（y∈[88,112]）：「第 N 波 · 剩余 x」单条，`HUD_INFO_COLOR` 中性色，16px
- **底部玩家蓝区**（y∈[1252,1280]，玩家挡板下方单行）：`PlayerScoreLabel` + `PlayerBrickLabel` / `PlayerPierceLabel`，霓虹蓝 #4a90d9
- **样式**: 全部数字 Label 经 `NeonStyle.apply()`（`gdscripts/ui_neon_style.gd`）设置描边（`outline_size=6`）+ 微投影（`shadow_offset=2`，半透明黑），默认字体 + 主题覆盖，headless 安全（AC1）
- **信号驱动（AC5，零轮询）**: `score_changed` / `brick_scored` / `pierce_scored` / `wave_started`（GameManager）+ `brick_destroyed` / `wall_cleared` / `wall_generated`（BreakoutGrid #384 契约，容错消费：未接线显示「—」占位 + push_warning 一次）
- **单份定义**: Main.tscn 实例化 `ui_game_hud.tscn`（节点名 `GameHUD` 不变，layer=1），消除 #292 双份 HUD 定义

### GameOverScreen（终局屏 win/fail 双分支 #391）

- **WinnerLabel**: "YOU WIN!" at 72px, blue — win 分支（winner == "player"）专属宣告
- **FailurePhraseLabel**: 失败短句 at 36px — fail 分支（winner == "ai"）显示；隐藏胜者宣告
- **RunStatsLabel**: 玩家单侧三项 run 数据 at 28px — `波次 %d · 拆砖 %d · 穿墙 %d`（#391 AC2）
- **RestartPromptLabel**: "按 SPACE 重新开始" at 28px with alpha-pulse animation（双分支保留）
- **Animation**: win 分支 Winner text pulses（1.0s cycle，#292 保留）；fail 分支克制、无脉冲（Issue「保持克制、不堆特效」）
- **数据源**: 全部来自 GameManager 查询 API（`get_wave_index()` / `get_brick_count("player")` / `get_pierce_count("player")`），无本地缓存
- **短句**: `res://content/wave_failure_text.json` 只读消费（schema `wave-failure-text/v1`），按 wave_index 分档（<=2→fp1；<=5→fp2；>=6→fp3；else→fp4 兜底），档内 recommended 优先；JSON 全链路失败 → `FAILURE_TEXT_DEFAULT_PHRASE`（GDD 21 契约）
- **Input**: SPACE key triggers restart → returns to StartMenu, calls `GameManager.reset_match()`

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Signal source for HUD | GameManager (not ScoringManager) | Autoload available everywhere |
| Glow effect | Tween modulate alpha | No ShaderMaterial needed |
| Font | Godot system_font | Readable at 24px+ without custom font |
| Debounce | `_transitioning` bool flag | Prevents double-trigger on rapid SPACE |
| Headless safety | `if get_tree():` guard | CI validation without crash |
| Sibling references | `get_parent().get_node_or_null()` | No exported NodePath vars |
| Fail 分支呈现 (#391) | 隐藏胜者宣告 + 分档短句 + run 数据，无脉冲 | 克制呈现（Issue「保持克制、不堆特效」），失败=叙事生产 (GDD 21) |
| 短句单一事实源 (#391) | `wave_failure_text.json` 只读 + schema 校验 + 逐级兜底 | 文案值归 #396 taste-draft，机械消费 (GDD 21 契约) |
| Run 数据来源 (#391) | GameManager 查询 API（`get_wave_index`/`get_brick_count`/`get_pierce_count`） | 数据单一来源、无本地缓存，测试可注入 |
| 新节点引用容错 (#391) | `get_node_or_null()` 引用 FailurePhraseLabel/RunStatsLabel | #385 容错模式延续，节点缺失静默跳过 |

## Edge Cases

| # | Case | Mitigation |
|---|------|------------|
| 1 | Headless mode: `get_tree()` returns null | All scripts guard with `if get_tree():` before creating tweens |
| 2 | GameManager autoload missing | `_ready()` checks `is_instance_valid(GameManager)` before connecting |
| 3 | Initial state — no signals emitted yet | HUD seeds labels from `GameManager.player_score` / `ai_score` |
| 4 | Rapid SPACE double-press | `_transitioning` bool prevents second trigger |
| 5 | Signal while layer invisible | `_on_score_changed()` updates text unconditionally |
| 6 | Font missing | Godot falls back to system_font |
| 7 | Sibling CanvasLayer not found | `get_node_or_null()` returns null safely |
| 8 | Tween conflict | `_kill_tween()` called before creating new animation |
| 9 | Invalid winner string | `match` falls through without action |
| 10 | wave_failure_text.json 缺失/损坏/schema 不符 (#391) | warn-once + `FAILURE_TEXT_DEFAULT_PHRASE` 兜底，不崩溃 |
| 11 | FailurePhraseLabel/RunStatsLabel 节点缺失 (#391) | `get_node_or_null` 静默跳过，fail 分支仍正常显示 |
| 12 | 首波未开始即败 wave_index==0 (#391) | `_pick_tier` 落入 fp4 兜底档（边界 1 定稿，优先于 §2.3 伪代码） |

## Testing Notes

- **Theme override access** — Tests that verify `Label` font sizes from `.tscn` files must use `label.get("theme_override_font_sizes/font_size")` instead of `label.get_theme_font_size("font_size")`, which returns 0 in headless mode. This was the root cause of 6 pre-existing failures fixed in PRs #353 and #355.


## Files

| File | Role |
|------|------|
| `gdscripts/start_menu.gd` | StartMenu controller (107 lines) |
| `gdscripts/game_hud.gd` | HUD 三区霓虹控制器（信号驱动，~190 lines, #392） |
| `gdscripts/ui_neon_style.gd` | 霓虹 Label 样式单一事实源（描边+微投影, #392） |
| `gdscripts/game_over_screen.gd` | 终局屏 controller — win/fail 双分支 + 分档短句 + run 数据 (~190 lines, #391) |
| `scenes/ui_start_menu.tscn` | StartMenu scene |
| `scenes/ui_game_hud.tscn` | GameHUD scene |
| `scenes/ui_game_over.tscn` | GameOverScreen scene |
| `scenes/game.tscn` | Modified: 3 CanvasLayer instances added |
| `gdscripts/scoring_manager.gd` | Modified: 1-line bridge to GameManager |
| `tests/test_ui_system.gd` | 84 test cases (see #353, #355) |
| `tests/test_failure_screen.gd` | 失败屏测试套件 — DESIGN §8 Scenarios A-G（#391, 449 lines） |

## Dependencies

All dependencies are closed:
- #301 (Scaffold) — directory structure
- #291 (Scoring) — signals emit
- #293 (GameManager) — autoload registered
- #289 (Neon Visual) — color constants defined
