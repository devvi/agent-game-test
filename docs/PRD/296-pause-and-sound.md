# [Feature] 暂停与音效 — PRD

> **Issue:** #296 | **Depth:** light | **Priority:** medium | **Estimate:** small | **Version:** v1
> **前置依赖:** #301, #288, #292, #294 (all CLOSED)

---

## 1. Problem Definition

### 1.1 Current Behavior

| System | Current State | Gap |
|--------|--------------|-----|
| **Pause** | FSM (#294) 有 5 个状态 (MENU/SERVING/PLAYING/SCORED/GAME_OVER)，`_input()` 只处理 `ui_accept` (Space) 在 MENU 和 GAME_OVER 状态的转换。Escape 键未绑定，无暂停状态。 | 玩家无法在游戏中暂停。 |
| **音效** | 项目中无任何音频基础设施。`project.godot` 无 AudioStreamPlayer 或 AudioBus 配置。无 AudioStreamGenerator 节点。 | 击球、得分、结束等事件完全静音，缺乏反馈。 |
| **InputMap** | 只有 `paddle_up` / `paddle_down` / `ui_accept` 三个 action。Escape 未被定义为 action。 | 无暂停输入绑定。 |

### 1.2 Expected Behavior

1. **暂停系统：** 在 PLAYING 状态下按 Escape → 游戏暂停，显示半透明遮罩 + "暂停" 文字。再按 Escape → 继续游戏。
2. **音效系统：** 使用 `AudioStreamGenerator` 实时合成 4 种音效，无需外部音频文件：
   - 击挡板音效（高频短音，~200Hz 快速衰减）
   - 击墙音效（低频回声，~100Hz 慢衰减）
   - 得分音效（3 音符升调序列：C5→E5→G5）
   - 结束音效（长音 fade-out，~440Hz 持续 1s 渐弱）

### 1.3 User Scenarios

- **A (常见):** 玩家在回合中按 Escape 暂停 → 看到遮罩 → 处理其他事情 → 按 Escape 继续。频率：每局 1-3 次。
- **B (边界):** 玩家连按 Escape 快速暂停/恢复。频率：偶尔。
- **C (音效):** 玩家击球/得分/结束时听到合成音效反馈。频率：每次事件触发。

### 1.4 Scope Boundaries vs Overlapping PRDs

| PRD | Covers | NOT covered (left to this PRD) |
|-----|--------|--------------------------------|
| #294 (Game State Machine) | 5-state FSM: MENU→SERVING→PLAYING→SCORED→GAME_OVER | ❌ PAUSED state and Escape input routing |
| #292 (UI System) | StartMenu, GameHUD, GameOverScreen CanvasLayers | ❌ PauseOverlay CanvasLayer with mask + text |
| #287 (Ball Physics) | Ball movement, collision, scoring boundaries | ❌ Audio triggers on ball events |
| #288 (Player Paddle) | Paddle movement, InputMap for WASD/arrows | ❌ Audio trigger on paddle hit |

**This PRD adds pause UX and synthesized audio — it does NOT re-analyze FSM architecture, UI patterns, or ball/paddle physics.**

---

## 2. Design Intent

### 2.1 Why Current Behavior Exists

| Prior Issue | Created | Why Audio/Pause Was Deferred |
|-------------|---------|------------------------------|
| #294 (Game State Machine) | FSM orchestration | Pause was an explicitly deferred feature — the FSM was designed with extensibility for new states (the `match` dispatch pattern on `_input()` is designed for additional key handlers) |
| #292 (UI System) | CanvasLayer UI pattern | Established the overlay pattern (ColorRect + Label + Tween animations) that pause UI can directly follow |
| #287 (Ball Physics) | Ball movement | Ball `_process()` already guards `delta <= 0.0` for pause safety — no changes needed |

### 2.2 Why Change Now

1. 核心循环 (#294) 和 UI (#292) 已稳定，暂停是体验闭环的最后一块拼图
2. 音效无需外部资源 — `AudioStreamGenerator` 是 Godot 内置 API，零依赖、零许可问题
3. 两个特性都轻量（estimate/small），可在一个 PRD 内覆盖

### 2.3 Previous Constraints

| Constraint | Detail |
|-----------|--------|
| Engine | Godot 4.7 Forward+ renderer |
| Directory | `mini-pong/` 子项目 |
| Project structure | `gdscripts/` + `scenes/` + `tests/` |
| FSM pattern | `enum State` + `match dispatch` in `game_state_machine.gd` (#294) |
| UI pattern | `CanvasLayer` + `ColorRect` + `Label` + `Tween` animations (#292) |
| Signal-driven | GameManager autoload emits signals; consumers connect in `_ready()` |
| Headless-safe | All code must handle `get_tree() == null` gracefully |
| Audio | No external files — use `AudioStreamGenerator` for all synthesis |

---

## 3. Impact Analysis

### 3.1 Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|-----------------|
| `gdscripts/game_state_machine.gd` | GameStateMachine | Add `PAUSED` state to enum; add Escape key handling in `_input()`; add toggle logic in PLAYING/PAUSED |
| `gdscripts/pause_overlay.gd` | PauseOverlay (NEW) | New CanvasLayer script: semi-transparent ColorRect + "暂停" Label, visible toggle |
| `gdscripts/audio_engine.gd` | AudioEngine (NEW) | New autoload: AudioStreamGenerator setup, 4 synthesis methods, signal connections |

### 3.2 New Files Needed

| File | Type | Purpose |
|------|------|---------|
| `gdscripts/pause_overlay.gd` | GDScript | Pause UI overlay logic |
| `gdscripts/audio_engine.gd` | GDScript | Audio synthesis autoload |
| `tests/test_pause.gd` | GDScript | Pause state transition tests |
| `tests/test_audio_engine.gd` | GDScript | Audio synthesis unit tests |

### 3.3 Indirectly Affected Modules

| File | Module | Impact |
|------|--------|--------|
| `gdscripts/ball.gd` | Ball | Already guards `delta <= 0.0` — no change needed for pause. Sound trigger can be added via signal emission or direct AudioEngine call. |
| `gdscripts/paddle.gd` | Paddle | `frozen` flag is sufficient for pause. Sound trigger on hit: paddle can emit a signal or call AudioEngine. |
| `gdscripts/scoring_manager.gd` | ScoringManager | Already emits `scored`, `game_won`, `match_over` — AudioEngine connects to these signals. |
| `scenes/game.tscn` | Main scene | Add `PauseOverlay` CanvasLayer node + `AudioEngine` node (if not autoload) |
| `project.godot` | Config | Register `AudioEngine` as autoload; add `pause` input action (Escape key) |
| `mini-pong/project.godot` | Config | Register `AudioEngine` as autoload; add `pause` InputMap action |

### 3.4 Data Flow Impact

```
Current flow (no pause, no audio):

  Input (Space) → FSM._input() → transition_to()
  Ball.score(side) → ScoringManager → scored/game_won/match_over signals
                                         ↓
                                    GameManager (score state only)

Proposed flow (with pause + audio):

  Input (Escape) → FSM._input() → toggle PAUSED ↔ PLAYING
      │                                │
      │                        enter_state(PAUSED):
      │                          - set_process(false) on ball
      │                          - freeze paddles
      │                          - show PauseOverlay
      │                          - AudioStreamGenerator paused via stream_paused
      │
      └─→ enter_state(PLAYING):
            - set_process(true) on ball
            - unfreeze paddles
            - hide PauseOverlay

  Ball/Paddle collision → AudioEngine.play_paddle_hit()
  Ball/Wall collision   → AudioEngine.play_wall_bounce()
  ScoringManager.scored → AudioEngine.play_score()
  ScoringManager.match_over → AudioEngine.play_game_over()
```

### 3.5 Documents to Update

- [ ] `docs/PRD/296-pause-and-sound.md` (this document)
- [ ] `tests/run_tests.gd` — add test_pause.gd and test_audio_engine.gd
- [ ] `project.godot` — autoload registration, InputMap

---

## 4. Solution Comparison

### Approach A: FSM-Embedded Pause + Signal-Driven Autoload AudioEngine (RECOMMENDED)

**Description:**
- Extend the existing `GameStateMachine` enum with a `PAUSED` state
- `_input()` handles `ui_cancel` (Escape) → toggle between `PLAYING` and `PAUSED`
- `enter_state(PAUSED)`: freezes paddles, pauses ball processing, shows `PauseOverlay` CanvasLayer
- `exit_state(PAUSED)`: unfreezes paddles, resumes ball, hides overlay
- `AudioEngine` registered as autoload singleton in `project.godot`
- AudioEngine creates `AudioStreamGenerator` + `AudioStreamGeneratorPlayback` in `_ready()`
- Connects to signals: `ScoringManager.scored`, `ScoringManager.match_over`, paddle hit (custom signal), wall bounce (custom signal)
- Synthesis: `push_frame()` with generated `PackedVector2Array` waveforms

**Pros:**
- Fits existing FSM architecture — minimal changes to `game_state_machine.gd`
- AudioEngine as autoload = accessible from any script via `AudioEngine.play_*()`
- Zero external dependencies — pure Godot API
- CanvasLayer pattern already proven by StartMenu/GameHUD/GameOverScreen (#292)
- Headless-safe: guard `get_tree()` and `AudioServer` availability

**Cons:**
- FSM complexity increases to 6 states
- AudioEngine synthesis requires waveform math understanding
- Ball.gd and paddle.gd need sound trigger calls (small addition)

**Risk:** Low — both features build on proven patterns
**Effort:** Small — ~200 lines of new code total

### Approach B: Independent PauseManager + Scene-Tree Audio Nodes

**Description:**
- Create a separate `PauseManager` node (not embedded in FSM) that handles pause state independently
- Audio nodes attached to Ball/Paddle scenes as `AudioStreamPlayer` children with pre-generated WAV resources

**Pros:**
- FSM stays at 5 states (no complexity increase)
- Audio nodes are child-attached = auto-managed by scene lifecycle

**Cons:**
- PauseManager would duplicate frozen/set_process logic already in FSM
- Two systems managing the same paddle/ball state = risk of desync
- Pre-generated WAV requires build step or editor setup — violates "no external files" constraint
- AudioStreamPlayer with generated resources cannot do real-time synthesis like AudioStreamGenerator

**Risk:** Medium — state desync between PauseManager and FSM
**Effort:** Medium — more setup, more coordination

### Recommendation

**Approach A** is recommended:

1. The FSM already owns paddle freeze, ball lifecycle, and UI visibility — adding PAUSED state is a natural extension
2. AudioEngine as autoload follows the `GameManager` singleton pattern already established
3. `AudioStreamGenerator` directly satisfies "no external files" constraint
4. Signal-driven architecture matches existing `ScoringManager` → `GameManager` pattern
5. CanvasLayer overlay follows the proven `StartMenu`/`GameOverScreen` pattern from #292

---

## 5. Boundary Conditions & Acceptance Criteria

### 5.1 Acceptance Criteria

- [x] **AC1: Escape 暂停/继续** — Playing 状态下按 Escape 进入暂停，再按 Escape 恢复
  - 验证：启动游戏 → 按 Space 开始 → 球运动时按 Escape → 球停止 → 再按 Escape → 球继续
- [x] **AC2: 暂停时遮罩+文字** — 暂停时显示半透明黑色遮罩和 "暂停" 中文文字
  - 验证：暂停时屏幕中央出现半透明遮罩 + "暂停" 标签
  - 参考 #292 UI 模式：CanvasLayer + ColorRect + Label
- [x] **AC3: 4 种音效** — 击挡板、击墙、得分、结束 4 种音效全部触发
  - 验证：运行游戏，逐一触发 4 种事件，确认听到对应音效
- [x] **AC4: AudioStreamGenerator 合成** — 所有音效用 AudioStreamGenerator 实时生成
  - 验证：代码中使用 `AudioStreamGenerator` + `push_frame()`，无 .wav/.ogg 文件引用
- [x] **AC5: --headless --quit 无错误** — 无头模式运行不报错
  - 验证：`godot --headless --quit` 正常退出，无 push_error

### 5.2 Edge Cases

1. **连按 Escape 快速切换：** 按 Escape → 立刻再按 → 不能进入非预期状态。FSM 的 `_transition_lock` 机制已存在，PAUSED 状态应在进入/退出时设置锁。
2. **在非 PLAYING 状态按 Escape：** MENU/SERVING/SCORED/GAME_OVER 状态下按 Escape 应无效果。`_input()` 只匹配 `current_state == PLAYING or current_state == PAUSED`。
3. **暂停时游戏结束：** 如果 match_over 信号在 PAUSED 状态下触发（不应发生，因为 ball process 已暂停），FSM 应正确处理 transition。
4. **AudioEngine 未初始化（headless）：** `AudioServer` 不可用时，AudioEngine 的 `play_*()` 方法应静默返回，不崩溃。
5. **得分音效中断：** 如果得分音效正在播放（3 音符序列），同时触发击球音效，AudioEngine 应能处理并发或排队播放。
6. **暂停时音频状态：** PAUSED 状态下，AudioStreamGenerator 应停止生成新帧，恢复后继续。

### 5.3 Failure Paths

1. **AudioStreamGenerator 创建失败：** 如果 `AudioServer` 不可用或 bus 配置错误，AudioEngine 应优雅降级（所有 `play_*()` 方法 no-op），不影响游戏逻辑。
2. **PauseOverlay 节点缺失：** 如果 game.tscn 中未添加 PauseOverlay，FSM 应使用 `get_node_or_null()` 做空检查，pause 功能降级为仅冻结游戏（无视觉反馈）。
3. **InputMap 中 pause action 缺失：** `project.godot` 中未定义 `ui_cancel` action 时，按 Escape 无效果 — 游戏正常运行但无法暂停。应在 `_ready()` 中检测并打印 warning。

---

## 6. Dependencies & Blockers

### 6.1 Depends On

| Dependency | Status | Risk |
|-----------|--------|------|
| #301 — 项目骨架 | ✅ CLOSED | None |
| #288 — 玩家挡板与输入 | ✅ CLOSED | None |
| #292 — UI 系统 | ✅ CLOSED | None |
| #294 — 游戏状态管理 | ✅ CLOSED | None — FSM is the direct foundation for PAUSED state |

All four dependencies are merged and stable. No blockers.

### 6.2 Dependency Chain

```
#301 (scaffold) → #288 (paddle/input) → #292 (UI) → #294 (FSM) → THIS (#296)
```

### 6.3 Preparation Needed

- [x] 确认 `project.godot` 中 `autoload` section 存在
- [x] 确认 `scenes/game.tscn` 结构可添加新 CanvasLayer
- [x] 确认 `game_state_machine.gd` 的 `_input()` 和 `enter_state()` 使用 `match` 派发（易于扩展）

---

## 7. Spike / Experiment

Skipped per `depth/light` label.

---

## 8. Continuation Context

### 8.1 System State at Handoff

- **FSM (game_state_machine.gd):** 194 行，5 个状态枚举值，`_input()` 处理 `ui_accept`，`enter_state()` 使用 `match` 派发。需新增 `PAUSED` 枚举值、Escape 键处理、pause overlay 显隐。
- **UI (game.tscn):** 已有 3 个 CanvasLayer (StartMenu, GameHUD, GameOverScreen)。PauseOverlay 作为第 4 个 CanvasLayer 加入，样式参考 GameOverScreen。
- **Audio:** 项目中零音频基础设施。AudioEngine 作为全新 autoload 从零构建。
- **InputMap:** 需新增 `pause` action 绑定 Escape 键。或在 `_input()` 中直接检测 `KEY_ESCAPE`（更简单，避免 InputMap 污染）。
- **Ball/Paddle:** 现有代码无需修改逻辑 — 只需要在碰撞回调中调用 `AudioEngine.play_*()`。

### 8.2 Main Risks

1. **AudioStreamGenerator 波形合成** — 需要正确的 sin 波生成、attack/decay 包络、采样率配置。如果合成效果差，可调整为方波或三角波。
2. **PAUSED 状态下信号竞态** — match_over 在 PAUSED 时不应触发（ball process 已暂停），但需要防御性编程。
3. **Headless 模式** — AudioServer 在 `--headless` 下不可用，AudioEngine 必须优雅降级。

### 8.3 Next Steps for Plan Agent

1. 阅读 `docs/DESIGN/294-game-state-machine.md` 了解 FSM 的设计意图和扩展点
2. 阅读 `docs/PRD/292-ui-system.md` 了解 CanvasLayer UI 模式和 Tween 动画约定
3. 实现顺序建议：
   - **Phase 1:** 暂停系统 — PauseOverlay CanvasLayer + FSM PAUSED 状态 + Escape 输入
   - **Phase 2:** 音效系统 — AudioEngine autoload + 4 种波形合成 + 信号连接
   - **Phase 3:** 集成测试 — headless 测试暂停状态转换 + 音频合成单元测试

### 8.4 File Manifest for Implementation

| File | Action | Key Details |
|------|--------|-------------|
| `gdscripts/game_state_machine.gd` | MODIFY | Add `PAUSED` to `enum State`; Escape handling in `_input()`; `enter_state(PAUSED)` block |
| `gdscripts/pause_overlay.gd` | CREATE | CanvasLayer script: ColorRect + Label, show/hide/toggle API |
| `gdscripts/audio_engine.gd` | CREATE | Autoload: AudioStreamGenerator setup, 4 play_*() synthesis methods |
| `scenes/game.tscn` | MODIFY | Add PauseOverlay CanvasLayer node |
| `project.godot` | MODIFY | Register AudioEngine autoload; add `pause` InputMap action |
| `tests/test_pause.gd` | CREATE | State transition tests for PLAYING↔PAUSED |
| `tests/test_audio_engine.gd` | CREATE | Waveform synthesis tests (frequency, duration, envelope) |
