# DESIGN: [Feature] 拆砖专属音效 — 砖块碎裂音 (brick_break)

> **Parent Issue:** #450
> **Agent:** game-plan-agent
> **Date:** 2026-08-13
> **Approach:** B — 噪声突发 + 快速指数衰减包络（确认 PRD §4 推荐：`_play_noise_burst` 与 `_play_tone` 对称；不采用纯 sin 波方案 A、不采用多频簇方案 C）
> **Reference PRD:** docs/PRD/450-brick-break-sound.md（research PR #453，已合并）
> **上游方案:** docs/DESIGN/296-pause-and-sound.md §2.2（AudioEngine 合成音架构）+ docs/DESIGN/384-breakout-grid-brick-wall.md §4.1（brick.gd destroy() 语义）；PRD #384 §Stretch（play_brick_break 列为可选 Stretch，本 Issue 兑现延期链）
> **所有权:** `content_ownership: mechanical`（合成音参数/触发接线 = 机械可测；音色/时长数值 = taste-draft，全部收敛于 `BRICK_BREAK_*` 常量交由 human-review 定稿，调参零代码改动）
> **深度:** depth/standard —— 产出 DESIGN 文档 + 精简 TASKS 文档（operator 指引：worktree 并行测试 T3 需明确 AUDIO 区边界；文件域 4 个、无迁移/弃用、单一音频子系统，未达 skill TASKS 阈值）；测试仅描述不写代码
> **并行上下文:** worktree 并行测试 T3 —— T1 #448（HUD 区，plan PR #454 已合并）/ T2 #449（BG 区）与本 Issue（AUDIO 区）同改 `constants.gd` 不同区，验证「提交前 merge main」自动合并。本 DESIGN 只改 docs，无代码冲突面

---

## 1. 概述

Mini Pong 的 AudioEngine（#296 autoload）已有 4 个合成音效（paddle_hit / wall_bounce / score / game_over），全部基于 `AudioStreamGenerator` + sin 波包络。**砖块碎裂没有专属音效**：brick.gd `destroy()` 目前只通知 grid + `queue_free()`，拆砖瞬间完全无声。本设计以**最小增量**兑现 PRD #384 延期的 `play_brick_break()`：AudioEngine 新增第 5 个合成音（噪声突发 + 指数衰减 = 碎裂「啪」感），brick.gd `destroy()` 内 null-safe 触发，参数全部进 constants.gd 新增 AUDIO 区。

**Plan 阶段边界**：本阶段只产出本文档，不碰任何 `.gd` / `.tscn` / `.json` 文件 —— 下列全部内容为 implement agent 的契约。

### 设计哲学

1. **与 `_play_tone` 对称**：新增内部 `_play_noise_burst(duration, volume, seed)`，复用 `_enabled`/`_playback` 双守卫、`stream_paused` 暂停切换、`SAMPLE_RATE` 常量、`push_frame(Vector2(v,v))` 立体声同相推送 —— 与 `_play_tone` 完全同构，只把 sin 波换成固定种子噪声 × 指数包络。
2. **碎裂感来自噪声**：纯 sin 波听感是「哔」而非「啪/咔」（PRD §4 方案 A 否决理由）；白噪声突发 + τ=duration/4 快速指数衰减 = 典型破裂/碎裂声，与既有 4 音（全 sin 波）音色维度完全错开。
3. **确定性可测**：`RandomNumberGenerator` 固定 seed（`BRICK_BREAK_SEED = 450`）→ 同种子两次合成逐帧一致，CI 测试可复现（spike S1 已实测 `determinism: true`）。
4. **null-safe 触发**：brick.gd 在无 autoload 环境（编辑器单跑/测试隔离）静默跳过，不崩不报错 —— `is_instance_valid(AudioEngine)` 守卫。
5. **幂等即恰好一次**：brick.gd `destroy()` 的 `_destroyed` 标志保证音效恰好触发一次，无重复播放；升级 blast_neighbors（#387）批量路径每砖各自 destroy() → 各自触发，零额外接线。
6. **文件域红线（AC5/T3）**：实现 PR 只允许 4 文件 —— `gdscripts/audio_engine.gd` + `gdscripts/brick.gd` + `gdscripts/constants.gd`（仅追加 AUDIO 区）+ `tests/test_audio_engine.gd`；用 `worktree-commit.sh` 白名单 add，绝不 `git add .`。

---

## 2. 现状核实（plan agent 已对照源码确认）

| 文件 | 现状（已核实，2026-08-13） |
|------|---------------------------|
| `mini-pong/gdscripts/audio_engine.gd` | 133 行；`const SAMPLE_RATE := 44100`；`_setup_generator()`（AudioStreamGenerator mix_rate=44100 buffer=0.5s + stream_paused=true 省 CPU）；`_ready()` 守卫链：`AudioServer` 缺失 → push_warning 降级 / GameManager 单例缺失 → 跳过信号连接；public API：`play_paddle_hit()`（200Hz/0.05s/0.8）、`play_wall_bounce()`（100Hz/0.12s/0.6）、`play_score()`（C5→E5→G5 三连音）、`play_game_over()`（440Hz/1s/fade_out）；内部 `_play_tone(freq, duration, volume, fade_out)`：`if not _enabled or not _playback: return` 守卫 → 恢复 stream → 逐帧 `_playback.push_frame(Vector2(v,v))` → 暂停 stream。**无 `play_brick_break()`、无 `_play_noise_burst()`、无常量引用（音效参数硬编码字面量）** |
| `mini-pong/gdscripts/brick.gd` | 28 行；extends StaticBody2D；group `bricks`、collision_layer=2、collision_mask=0；`destroy()` 幂等（`_destroyed` 标志）：通知 `grid._on_brick_destroyed(self)`（grid 非空 + has_method 双守卫）→ `queue_free()`。**无音效触发** |
| `mini-pong/gdscripts/constants.gd` | `class_name GameConstants`（L12）；99 个 const；分区：Screen/Version/Ball/Paddle/AI/Scoring/Dual Scoring(#385)/Wave Cycle(#386)/Colors/Brick Wall(#384)/Wave Transition(#390)/Rain/Neon HUD(#392)/Upgrade Pool(#387)/Failure Screen(#391)/Upgrade Pick UI(#388)/Background Pulse(#449)/Ball Speed HUD(#448)；**无 AUDIO 分区**；文件以 `HUD_SPEED_LABEL_PREFIX`（L~195，Ball Speed HUD #448 区）结尾 |
| `mini-pong/tests/test_audio_engine.gd` | 245 行；TC8–TC13（paddle_hit 帧数 / wall_bounce 频率 / score 三连音 / game_over fade-out / headless no-op / null-safety）；`_make_audio_engine()` 工厂（load audio_engine.gd + mock playback 捕获帧）+ `_approx_eq(a,b,tol)` 断言助手；run_tests.gd L30 已注册 |
| `mini-pong/tests/test_breakout_grid.gd` | destroy 幂等 / brick_destroyed 信号用例（L37/L41 等）；brick 在测试中 destroy() → 若触发音效需 null-safe 守卫生效（本环境 AudioEngine autoload 存在但 headless `_enabled=false` → 静默 no-op） |
| `mini-pong/tests/run_tests.gd` | L30 `_run("res://tests/test_audio_engine.gd", "AudioEngine")`、L31 `_run(..., "Constants")`；**无需改动**（新 TC 进 test_audio_engine.gd 自动纳入） |
| `mini-pong/tests/test_constants.gd` | 无「常量数量/分区计数」硬编码断言（已核实 grep count/size/分区 无命中）→ 新增 AUDIO 区零破坏 |
| `mini-pong/project.godot` | `[autoload]` L18：GameManager / **AudioEngine** / UpgradePool 三个 autoload（L20-22）；AudioEngine 引用 `*res://gdscripts/audio_engine.gd` |
| 当前 `origin/main` | HEAD = `1a2b5a3`（review 分流修复）；#448 HUD 区 / #449 BG 区已进 main → T3 提交前 merge main 需自动合并三个并行 issue 的 constants.gd 不同区 |

### PRD 断言 vs 实际代码库（gap 核查）

| PRD 断言 | 实际代码库 | 设计决议 |
|---------|-----------|---------|
| audio_engine.gd「文件已 import 模式：const CONSTS = preload(...)」 | **无** —— audio_engine.gd 顶部无 `const CONSTS = preload("res://gdscripts/constants.gd")`，4 个音效参数全部硬编码字面量 | 新增方法直接引用 `GameConstants.BRICK_BREAK_*`（constants.gd 已声明 `class_name GameConstants`，全工程全局可见，无需 preload）；如需与既有风格一致可加 `const CONSTS = preload(...)`，二选一，实现 agent 任选（推荐 GameConstants 直接引用，零新增 import） |
| brick.gd「destroy() 中通知 grid 之后、queue_free() 之前」插入触发 | 一致（L26-28 结构完全吻合） | 按 PRD 位置插入 null-safe 触发，不动既有两行 |
| test_audio_engine.gd 沿用 `_make_audio_engine` 工厂 | 一致（L37-64 工厂 + mock playback 捕获帧数组） | TC14–TC17 复用该工厂，无新测试文件 |
| 基线 2216 passed / 0 failed | PRD 实测值；本 agent 未复跑（docs-only，无代码变更） | 实现后验证清单重跑，不得回退 |

---

## 3. 核心设计（implement 契约）

### 3.1 `mini-pong/gdscripts/constants.gd` — 追加 AUDIO 区（文件末尾）

在文件**末尾**（Ball Speed HUD #448 区之后）追加，既有区逐字节不动：

```gdscript
# ── Audio (#450) ──
# 拆砖专属音效 (PRD #450 方案 B: 噪声突发 + 指数衰减; 机制/常量 = mechanical,
# 音色/时长数值 = taste-draft, human-review 定稿, 调参零代码改动)
const BRICK_BREAK_DURATION: float = 0.08    # 80ms 短促碎裂音
const BRICK_BREAK_VOLUME: float = 0.7       # <1.0 防削波 (spike peak 0.689 验证)
const BRICK_BREAK_DECAY_TAU: float = 0.02   # τ = duration/4 快速指数衰减
const BRICK_BREAK_SEED: int = 450           # 固定种子 → 合成确定性 (CI 可复现)
```

**红线**：不触碰已有分区任何一行（T3 并行：T1 #448 HUD 区 / T2 #449 BG 区已在 main，merge 自动合并）。

### 3.2 `mini-pong/gdscripts/audio_engine.gd` — 新增第 5 个合成音

**文件头注释**更新为「5 sound effects」并注明 #450 归属（可选项，不阻塞）。

**新增 public 方法**（置于 `play_game_over()` 之后、`── Internal ──` 注释之前）：

```gdscript
func play_brick_break() -> void:
	"""拆砖碎裂音: 噪声突发 + 快速指数衰减 (~80ms)。#450"""
	_play_noise_burst(
		GameConstants.BRICK_BREAK_DURATION,
		GameConstants.BRICK_BREAK_VOLUME,
		GameConstants.BRICK_BREAK_SEED
	)
```

**新增内部方法**（与 `_play_tone` 并列，置于其下）：

```gdscript
func _play_noise_burst(duration: float, volume: float, seed: int) -> void:
	"""固定种子白噪声 × 指数衰减包络 exp(-t/τ)，τ = duration/4。"""
	if not _enabled or not _playback:
		return

	var samples := int(SAMPLE_RATE * duration)
	var tau := duration / 4.0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	if _stream_player:
		_stream_player.stream_paused = false

	for i in range(samples):
		var t := float(i) / SAMPLE_RATE
		var envelope := volume * exp(-t / tau)
		var sample_val := (rng.randf() * 2.0 - 1.0) * envelope
		_playback.push_frame(Vector2(sample_val, sample_val))

	if _stream_player:
		_stream_player.stream_paused = true
```

**要点（对齐 `_play_tone` 既有模式）**：
- `_enabled`/`_playback` 双守卫 → headless `_enabled=false` 时 no-op（AC1/AC4）
- `stream_paused` 恢复/暂停切换与 `_play_tone` 相同（省 CPU 纪律 #296）
- `rng.seed = seed` 固定种子 → 同种子两次调用逐帧一致（TC16 断言依据，spike 实测）
- 包络 `exp(-t/τ)`：t=0 → volume（0.7），t=duration → exp(-4)≈0.018 → 尾部≈0，碎裂「啪」感（spike：early_avg 0.31 vs late_avg 0.009，衰减 35×）
- 采样值 `rng.randf() * 2.0 - 1.0` ∈ [-1,1] × envelope ≤ 0.7 → 不削波（spike peak 0.689）
- **常量引用方式**：`GameConstants.BRICK_BREAK_*`（class_name 全局可见，零新增 import；见 §2 gap 决议）

### 3.3 `mini-pong/gdscripts/brick.gd` — null-safe 触发

`destroy()` 内、grid 通知之后、`queue_free()` 之前插入（**不动既有两行**）：

```gdscript
func destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	if grid != null and is_instance_valid(grid) and grid.has_method("_on_brick_destroyed"):
		grid._on_brick_destroyed(self)
	if is_instance_valid(AudioEngine):   # #450 null-safe: 无 autoload 环境静默跳过
		AudioEngine.play_brick_break()
	queue_free()
```

**要点**：
- `is_instance_valid(AudioEngine)` 守卫：测试/编辑器/隔离环境无 autoload → 静默跳过不崩（AC2）
- `_destroyed` 幂等 → 音效恰好一次（destroy() 二次调用直接 return）
- headless 下 AudioEngine autoload 存在但 `_enabled=false` → `play_brick_break()` no-op，不产生帧（test_breakout_grid 既有用例不受影响）
- 升级 blast_neighbors（#387）批量路径：每砖各自 destroy() → 各自触发，零额外接线（PRD §3 数据流）

### 3.4 文件域清单

| 类别 | 文件 | 动作 |
|------|------|------|
| 修改 | `mini-pong/gdscripts/audio_engine.gd` | 新增 `play_brick_break()` + `_play_noise_burst()` |
| 修改 | `mini-pong/gdscripts/brick.gd` | `destroy()` 内追加 null-safe 触发 |
| 修改 | `mini-pong/gdscripts/constants.gd` | 文件末尾追加 `# ── Audio (#450) ──` 区（4 常量） |
| 修改 | `mini-pong/tests/test_audio_engine.gd` | 新增 TC14–TC17（见 §7） |
| 新增 | — | **无**（零新文件，AC5/T3 红线） |
| 不修改 | `mini-pong/tests/run_tests.gd` | 已注册 test_audio_engine.gd（L30），新 TC 自动纳入 |
| 不修改 | `mini-pong/gdscripts/breakout_grid.gd` | blast_neighbors 经 brick.destroy() 自动获得音效 |

---

## 4. 数据流

```
Ball._on_body_entered (bricks 分支, #384)
    │ body.destroy()  ← brick.gd destroy()（幂等, _destroyed 标志）
    │   ├── grid._on_brick_destroyed(self)   ← 既有（网格计数/信号）
    │   ├── [新增 #450] is_instance_valid(AudioEngine)
    │   │        └── AudioEngine.play_brick_break()
    │   │              └── _play_noise_burst(BRICK_BREAK_DURATION,
    │   │                       BRICK_BREAK_VOLUME, BRICK_BREAK_SEED)
    │   │                    ├── 守卫: _enabled/_playback (headless → return)
    │   │                    ├── rng.seed = 450 → 固定种子噪声
    │   │                    ├── 逐帧: envelope = volume·exp(-t/τ)
    │   │                    │         sample = (randf·2-1)·envelope
    │   │                    │         _playback.push_frame(Vector2(v,v))
    │   │                    └── stream_paused 恢复→推送→暂停
    │   └── queue_free()
    └── (网格 blast_neighbors 批量路径 #387: 每砖各自 destroy() → 各自触发)
```

**时序**：球击中砖 → destroy() → grid 计数（既有，顺序不变）→ 音效合成入 0.5s buffer → 帧释放。音效触发不阻塞物理/网格逻辑（合成 ~3528 帧为 CPU 微秒级，spike 实测 headless 无崩溃）。

---

## 5. 边界情况与错误处理

| 边界情况 | 缓解 |
|---------|------|
| headless / CI 无 AudioServer | `_ready()` 守卫链 push_warning 降级 → `_enabled=false` → `play_brick_break()`/`_play_noise_burst()` 首行守卫 return，不崩不报错（AC4） |
| brick 在无 AudioEngine autoload 环境（编辑器单跑/测试隔离）被 destroy() | `is_instance_valid(AudioEngine)` 为 false → 静默跳过（AC2） |
| destroy() 被二次调用（幂等重入） | `_destroyed` 标志 → 直接 return，音效恰好一次，无重复播放（#384 既有语义，未改动） |
| blast_neighbors 同帧多砖碎裂 | 每砖独立 destroy() → 各自合成入 buffer，帧序列叠加（0.5s buffer 足够容纳，44100Hz × 0.5s） |
| 噪声合成峰值削波 | volume=0.7 < 1.0，spike 实测 peak 0.689 < 1.0 → 无削波 |
| 测试环境 mock playback（test_audio_engine.gd 工厂） | mock 实现 `push_frame`/`get_frames_available`/`clear_buffer`，与 `_play_tone` 用例同构，TC14–TC17 直接复用 |
| test_breakout_grid.gd 既有 destroy 用例 | 测试运行于 headless → AudioEngine `_enabled=false` → brick 触发 no-op；`is_instance_valid(AudioEngine)` 为 true（autoload 注册）但 play 内部守卫拦截 → 零影响 |
| 数值调优需求（更脆/更闷/更长） | 全部收敛于 `BRICK_BREAK_*` 常量，taste-draft PR 改值即生效，零代码改动 |
| constants.gd 与 T1 #448 / T2 #449 并行区冲突 | 各 issue 只追加各自新区（HUD/BG/AUDIO），worktree-commit.sh 提交前 merge origin/main 自动合并；若真冲突按脚本冲突分级处理 |

---

## 6. 集成点

> **Status 约定:** ⬜ = pending（由 implement agent 接线）；✅ = 已由实现验证。implement agent 完成接线后须更新本表；review agent 合并前验证所有 ⬜ 已解决或显式延期。

| Integration | Our Component | Target | How | Status |
|-------------|:---:|:---:|-----|:---:|
| 常量供给 | audio_engine.gd | constants.gd `BRICK_BREAK_*` | `GameConstants.BRICK_BREAK_*` 直接引用（class_name 全局可见；或 `const CONSTS = preload(...)`，二选一） | ⬜ pending |
| 音效触发 | brick.gd `destroy()` | AudioEngine autoload | `if is_instance_valid(AudioEngine): AudioEngine.play_brick_break()`（grid 通知后、queue_free 前） | ⬜ pending |
| 合成管道 | `_play_noise_burst()` | `_playback`（AudioStreamGenerator） | 复用 `_setup_generator()` 产出的 `_playback.push_frame` + `stream_paused` 切换 | ⬜ pending |
| 批量碎砖 | brick.gd | breakout_grid blast_neighbors（#387） | 被动集成：每砖 destroy() 自带触发，零额外接线 | ✅ n/a（零代码改动） |
| 测试域 | test_audio_engine.gd TC14–TC17 | run_tests.gd | 新 TC 进既有文件，L30 注册自动纳入；**不改 run_tests.gd** | ⬜ pending |

---

## 7. 测试策略与用例描述

**红线（AC5）**：不新增测试文件、不改 `run_tests.gd`；新用例进 `test_audio_engine.gd`（沿用 `_make_audio_engine()` 工厂 + `_approx_eq`）。以下为 implement agent 的用例**描述**（非可运行代码，测试代码由 implement agent 编写）。

### Scenario A：headless 健康（AC4）
- Test A1：`godot --path mini-pong/ --headless --quit` 退出码 0、无脚本错误（audio_engine.gd 新增方法加载/解析正确、brick.gd 触发语法正确）
- Test A2：`run_tests.gd` 全绿 —— 基线 2216 passed / 0 failed 不回退；新增 TC14–TC17 后 ≥ 2220

### Scenario B：brick_break 合成正确性（test_audio_engine.gd 新增 TC14–TC17）
- **TC14 帧数**：`_make_audio_engine()` → `play_brick_break()` → mock playback 捕获帧数 ≈ `int(44100 × BRICK_BREAK_DURATION)`（0.08s → 3528 帧，tolerance 0.02，沿 TC8.2 模式）
- **TC15 衰减包络**：帧序列 early 段均值 > late 段均值 × 3（沿 spike S1 断言：early_avg 0.31 vs late_avg 0.009，35×）；验证指数衰减「啪」感成立
- **TC16 确定性**：同 seed 两次调用逐帧相等（`frames_a[i] == frames_b[i]`，i ∈ [0, frames.size())）；验证固定种子可复现
- **TC17 headless no-op**：`_enabled=false`（`_playback=null`）时调用 `play_brick_break()` 不崩不产帧（沿 TC12 模式）

### Scenario C：brick 触发 null-safe（AC2）
- Test C1：`test_breakout_grid.gd` 既有 destroy 幂等/信号用例全绿（brick destroy() 内新增触发在 headless 下 no-op，不破坏 #384 语义）
- Test C2：手动/脚本验证：无 AudioEngine autoload 环境（模拟 `is_instance_valid(null)`）destroy() 静默跳过不崩（沿 TC13 模式）

---

## 8. 实现阶段

| Phase | Priority | 内容 | 文件 | 估计 |
|:-----:|:--------:|------|------|:----:|
| Phase 1 | P0 | 追加 `BRICK_BREAK_*` 常量区（文件末尾，既有区逐字节不动） | `gdscripts/constants.gd` | 0.05 天 |
| Phase 2 | P0 | 新增 `_play_noise_burst()` + public `play_brick_break()`（复用 `_play_tone` 模式） | `gdscripts/audio_engine.gd` | 0.2 天 |
| Phase 3 | P0 | `destroy()` 内 null-safe 触发（grid 通知后、queue_free 前，一行） | `gdscripts/brick.gd` | 0.05 天 |
| Phase 4 | P0 | 新增 TC14–TC17（帧数/衰减/确定性/headless no-op） | `tests/test_audio_engine.gd` | 0.2 天 |
| Phase 5 | P0 | 验证：headless `--quit` + run_tests 全绿；`worktree-commit.sh` 白名单提交（提交前 merge main 自动合并 T1/T2 的 constants 区） | — | 0.2 天 |

**实现顺序建议（继承 PRD §8）：** constants → audio_engine.gd（_play_noise_burst → play_brick_break）→ brick.gd 触发 → TC14–TC17 → headless 验证 → `worktree-commit.sh 450 "<msg>" <4 个白名单文件>` → PR + CI。taste 调音（更脆/更闷/更长）→ 后续 taste-draft PR 改 `BRICK_BREAK_*` 值，本 Issue 只定机械结构。

---

## 9. 验收条件映射（AC checklist，源自 Issue #450 body）

| AC | 内容 | 设计落实 |
|----|------|---------|
| AC1 | AudioEngine 新增 play_brick_break()（AudioStreamGenerator 合成短促碎裂音） | §3.2 `_play_noise_burst` + `play_brick_break()`；复用 `_setup_generator` 管道；`_enabled=false` 时 no-op（TC17） |
| AC2 | brick.gd 碎裂时调用 play_brick_break（null-safe） | §3.3 `is_instance_valid(AudioEngine)` 守卫，置于 grid 通知后、queue_free 前；无 autoload 环境静默跳过（§7 Scenario C） |
| AC3 | constants.gd 新增 AUDIO 区常量（BRICK_BREAK_*），不影响现有常量 | §3.1 文件末尾追加 4 常量；既有 99 const 逐字节不动；test_constants 无计数断言（已核实） |
| AC4 | --headless --quit 无脚本错误，run_tests.gd 全绿 | §7 Scenario A；基线 2216 passed / 0 failed 不回退，新增 TC 后 ≥ 2220 |
| AC5 | PR files 仅含本 Issue 文件域 | 白名单 = `audio_engine.gd` + `brick.gd` + `constants.gd` + `test_audio_engine.gd`；worktree-commit.sh 白名单 add；绝不 add .（T3 并行红线） |

### 明确不修改（继承 PRD §1.4/§3.3/§8）

- `mini-pong/gdscripts/breakout_grid.gd`、`ball.gd`、`game_manager.gd` 等域外文件
- `mini-pong/gdscripts/constants.gd` 既有 14+ 分区（只追加 AUDIO 区）
- `mini-pong/tests/run_tests.gd`（L30 已注册，零改动）
- 不新增任何文件（含测试文件）；不引入 wav/ogg 音频资产
- 其他 issue 文件（#448 HUD 区 / #449 BG 区已在 main，T3 merge 自动合并）
