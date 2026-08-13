# Tasks: [Feature] 拆砖专属音效 — 砖块碎裂音 (brick_break)

> **Parent Issue:** #450
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Design:** docs/DESIGN/450-brick-break-sound.md
> **深度:** depth/standard（文件域 4 个、单一音频子系统，未达 skill TASKS 阈值；按 operator 指引产出精简 TASKS —— worktree 并行测试 T3 需明确 AUDIO 区边界）
> **所有权:** `content_ownership: mechanical` — 合成音机制/触发接线/常量定义机械实现；音色/时长数值 = taste-draft（human-review 定稿，调参零代码改动）

---

## Phase 1: 常量 — AUDIO 区（P0，地基）
- [ ] Task 1 (`mini-pong/gdscripts/constants.gd`): **文件末尾**追加 `# ── Audio (#450) ──` 区（Ball Speed HUD #448 区之后）：`BRICK_BREAK_DURATION: float = 0.08`、`BRICK_BREAK_VOLUME: float = 0.7`、`BRICK_BREAK_DECAY_TAU: float = 0.02`（τ=duration/4）、`BRICK_BREAK_SEED: int = 450`（DESIGN §3.1）
  - **T3 并行红线**：只追加 AUDIO 区，既有 99 个 const / 16+ 分区逐字节不动（T1 #448 HUD 区、T2 #449 BG 区已在 main，提交前 merge main 自动合并）

## Phase 2: AudioEngine 第 5 个合成音（P0，核心）
- [ ] Task 2 (`mini-pong/gdscripts/audio_engine.gd`): 新增内部 `_play_noise_burst(duration: float, volume: float, seed: int) -> void`（与 `_play_tone` 对称：`_enabled`/`_playback` 双守卫 + `stream_paused` 恢复/暂停切换；`RandomNumberGenerator` 固定 seed；`samples = int(SAMPLE_RATE * duration)`；包络 `envelope = volume * exp(-t / tau)`，`tau = duration / 4.0`；`sample = (rng.randf() * 2.0 - 1.0) * envelope`；`_playback.push_frame(Vector2(v, v))`）（DESIGN §3.2）
- [ ] Task 3 (`mini-pong/gdscripts/audio_engine.gd`): 新增 public `play_brick_break() -> void`（置于 `play_game_over()` 之后、`── Internal ──` 之前），调 `_play_noise_burst(GameConstants.BRICK_BREAK_DURATION, GameConstants.BRICK_BREAK_VOLUME, GameConstants.BRICK_BREAK_SEED)`（constants.gd 已 `class_name GameConstants` 全局可见，零新增 import；DESIGN §2 gap 决议）；文件头注释「4 sound effects」→「5 sound effects」并注明 #450（可选，不阻塞）

## Phase 3: brick.gd null-safe 触发（P0）
- [ ] Task 4 (`mini-pong/gdscripts/brick.gd`): `destroy()` 内、grid 通知之后、`queue_free()` 之前插入 `if is_instance_valid(AudioEngine): AudioEngine.play_brick_break()`（不动既有两行；`_destroyed` 幂等 → 音效恰好一次）（DESIGN §3.3）

## Phase 4: 测试 — TC14–TC17（P0）
- [ ] Task 5 (`mini-pong/tests/test_audio_engine.gd`): 新增 4 用例（沿用 `_make_audio_engine()` 工厂 + `_approx_eq`；**不新建测试文件、不改 run_tests.gd**，L30 注册自动纳入）：TC14 帧数 ≈ `int(44100 × BRICK_BREAK_DURATION)`（tolerance 0.02，沿 TC8.2）；TC15 衰减包络 early 均值 > late 均值 × 3；TC16 同 seed 两次调用逐帧相等（确定性）；TC17 `_enabled=false` 时调用不崩不产帧（沿 TC12）（DESIGN §7 Scenario B）

## Phase 5: 验证与提交（P0）
- [ ] Task 6 (验收): `godot --path mini-pong/ --headless --quit` 无脚本错误；`godot --headless --script res://tests/run_tests.gd` 全绿（基线 2216 passed / 0 failed 不回退，新增 TC 后 ≥ 2220）；`test_breakout_grid.gd` 既有 destroy 用例零回归（headless 下触发 no-op）
- [ ] Task 7 (提交): `./scripts/worktree-commit.sh 450 "<msg>" <4 个白名单文件>`（提交前自动 merge origin/main → T3 并行 constants 区自动合并；冲突按脚本分级处理，不硬解）→ PR → CI

## 明确不做（范围边界）
- ❌ `mini-pong/gdscripts/breakout_grid.gd` / `ball.gd` / `game_manager.gd` 等域外文件
- ❌ `mini-pong/gdscripts/constants.gd` 既有 16+ 分区（只追加 AUDIO 区）
- ❌ `mini-pong/tests/run_tests.gd`（L30 已注册，零改动）
- ❌ 新增任何文件（含测试文件）；❌ 引入 wav/ogg 音频资产（纯 AudioStreamGenerator 合成）
- ❌ 写 runnable 测试文件于本 PR（测试代码归 implement PR）
- ❌ taste 调音（更脆/更闷/更长）→ 后续 taste-draft PR 改 `BRICK_BREAK_*` 值
