# PRD: [Feature] 拆砖专属音效 — 砖块碎裂音 (brick_break)

> **Issue:** #450
> **标签:** enhancement, audio, version/v1, workflow/research（research 进行中）
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/standard（Issue 无 depth 标签，按 #358/#378/#383/#384/#385/#386 惯例按 standard 处理：Section 1–6 + 8 必填，Section 7 以研究期实际执行的 spike 补齐）
> **所有权:** `content_ownership: mechanical`（合成音效参数为机械常量，数值定稿归 taste 流程；本 Issue 只做机械合成与接线）
> **引擎/目录约束:** Godot 4.7.1（本机 4.7.1.stable），`mini-pong/` 子项目（`mini-pong/gdscripts/`、`mini-pong/tests/`）
> **工作流约束:** worktree 并行测试 T3（2026-08-13）——三个并行 issue 刻意都改 `constants.gd` 不同区域，验证提交前 merge main 的自动合并。本 issue 文件域: `audio_engine.gd`、`brick.gd`、`test_audio_engine.gd`、`constants.gd` 新增 AUDIO 区（白名单纪律，绝不越界）
> **上游方案:** `docs/DESIGN/296-pause-and-sound.md` §2.2（AudioEngine 合成音架构）；`docs/DESIGN/384-breakout-grid-brick-wall.md` §4.1（brick.gd destroy() 语义）；`docs/DESIGN/385-dual-scoring.md`（play_brick_break 延期归属）；PRD #384 §Stretch（play_brick_break 列为可选 Stretch）

---

## 1. 问题定义

### 当前状态

Mini Pong 的 AudioEngine（#296 autoload）已有 4 个合成音效（paddle_hit / wall_bounce / score / game_over），全部基于 `AudioStreamGenerator` + sin 波包络。**砖块碎裂没有专属音效**：brick.gd `destroy()` 目前只通知 grid + `queue_free()`，拆砖瞬间完全无声。PRD #384 把 `play_brick_break()` 明确列为**可选 Stretch**（非 AC 阻塞项），DESIGN #384/#385/#393 均注明「play_brick_break 归 #392 或延期」——**从未落地**。本 Issue 是这条延期链的兑现点。

| 文件/资源 | 当前状态 | 与 #450 需求的差距 |
|------|---------|------------------|
| `mini-pong/gdscripts/audio_engine.gd` | ✅ AudioEngine autoload（#296）：`_setup_generator()` 建 AudioStreamGenerator（44100Hz / 0.5s buffer）+ `_play_tone(freq, duration, volume, fade_out)` 内部合成器；4 个 public `play_*()`；`_enabled`/`_playback` 双守卫 + headless 优雅降级（`AudioServer` 不存在时 push_warning 且不崩） | ❌ 无 `play_brick_break()`——需新增第 5 个合成音（短促碎裂音），且**不能用纯 sin 波**（碎裂感需要噪声/快速衰减包络） |
| `mini-pong/gdscripts/brick.gd` | ✅ #384 单砖（StaticBody2D，group `bricks`，collision_layer=2）：`destroy()` 幂等（`_destroyed` 标志）→ 通知 `grid._on_brick_destroyed(self)` → `queue_free()` | ❌ destroy() 中无音效调用——需在碎裂瞬间触发 `play_brick_break()`（null-safe，因 brick 可脱离 autoload 环境被实例化，如测试/编辑器） |
| `mini-pong/gdscripts/constants.gd` | ✅ 单一声明源（class_name GameConstants），现有 14 个分区（Screen/Version/Ball Physics/Paddle/AI/Scoring/Dual Scoring/Wave Cycle/Colors/Brick Wall/Wave Transition/Rain Curtain/Neon HUD/Upgrade Pool/Failure Screen/Upgrade Pick UI），**无 AUDIO 分区** | ❌ 需新增 `# ── Audio (#450) ──` 区：`BRICK_BREAK_*` 参数（时长/音量/衰减/噪声种子等），不得影响现有常量 |
| `mini-pong/tests/test_audio_engine.gd` | ✅ #296 测试套件（TC8–TC13）：mock playback 捕获帧、零交叉计数、帧数断言；`_make_audio_engine()` 工厂 + `_approx_eq` | ❌ 无 brick_break 用例——需新增 TC（帧数/衰减包络/确定性/headless no-op）并注册进 run_tests.gd 已有 `_run("res://tests/test_audio_engine.gd", "AudioEngine")` |
| `mini-pong/tests/test_breakout_grid.gd` | ✅ #384 网格测试（destroy 幂等、brick_destroyed 信号） | ⚠️ 若 brick.gd 触发音效，需验证**不破坏**现有测试（brick 在测试中无 AudioEngine autoload → null-safe 守卫必须生效） |

### 期望行为

1. **AudioEngine 新增 `play_brick_break()`**：基于 AudioStreamGenerator 合成**短促碎裂音**（噪声突发 + 快速指数衰减包络，~80ms），复用 `_setup_generator()` 的现有管道，沿用 `_play_tone` 的 `_enabled`/`_playback` 守卫与 headless 降级语义。
2. **brick.gd 碎裂时触发**：`destroy()` 中（通知 grid 之后、`queue_free()` 之前）调用 `play_brick_break()`，**null-safe**（`is_instance_valid(AudioEngine)` 守卫）——测试/编辑器等无 autoload 环境下静默跳过，不崩。
3. **constants.gd 新增 AUDIO 区**：`BRICK_BREAK_*` 机械参数（duration/volume/decay/seed），与现有常量零冲突（新分区追加，不改动已有 14 区）。
4. **全绿**：`--headless --quit` 无脚本错误；`run_tests.gd` 全绿（基线 2216 passed / 0 failed，研究期实测）。
5. **文件域纪律**：PR 仅含 `audio_engine.gd`、`brick.gd`、`test_audio_engine.gd`、`constants.gd` 四个文件（worktree 白名单提交，绝不 add .）。

### 范围边界（与重叠 PRD 去冲突）

| PRD | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|------------------|
| #296 暂停与音效 | AudioEngine 整体架构（合成管道、4 个既有音效、暂停语义） | ❌ 不重构合成管道——只新增第 5 个音效方法，复用 `_setup_generator`/`_play_tone` 模式 |
| #384 砖墙 | brick.gd 结构、destroy() 语义、网格回调 | ❌ 不改 destroy() 生命周期/幂等——只在现有 destroy() 内**追加一行音效触发**（null-safe） |
| #385 双得分制 | 计分/穿墙/21 分终局 | ❌ 不触碰计分逻辑——play_brick_break 的延期归属在此兑现 |
| #392 霓虹 UI 升级 | HUD/视觉层 | ❌ 不涉及视觉——DESIGN #385/#393 曾把 play_brick_break 归 #392，本 Issue 正式接管该延期项（#392 无音频范围） |
| #389 动态雨帘 | 雨量/视觉氛围 | ❌ 不涉及雨帘——音效与视觉氛围分离，各自独立 |

本 PRD 是**拆砖专属音效（brick_break）**——聚焦 AudioEngine 第 5 个合成音、brick.gd 的 null-safe 触发、constants.gd AUDIO 新区。它**不重新分析** #296 的合成架构、#384 的砖墙物理、#385 的计分机制、#392 的视觉升级。

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 拆砖成功（球击中砖块 → destroy()） | 每波高频（单砖命中即触发） | 砖块碎裂瞬间播放短促碎裂音，与 paddle_hit/wall_bounce 形成差异化反馈 |
| B | 升级 blast_neighbors 批量碎砖（#387） | 中频 | 多砖同时 destroy() → 多砖各自触发（brick.gd 内聚，网格批量路径自动获得音效） |
| C | headless 测试/CI | 每次测试 | brick.gd 无 AudioEngine autoload 环境 → null-safe 静默跳过，不崩不报错 |

---

## 2. 设计意图

### 为什么当前行为如此

AudioEngine（#296）设计为**纯合成音效引擎**（零音频资产，运行时生成），当时只覆盖 4 个核心反馈音。砖墙系统（#384）落地时把拆砖音明确列为 **Stretch**（PRD #384 §Stretch：「可选（Stretch）新增 play_brick_break() 合成音效；非 AC 阻塞项」），DESIGN #384/#385/#393 反复注明「play_brick_break 归 #392 / 延期」——因为砖墙核心（物理/网格/组装）优先，音效是体验收尾项。现在砖墙、双得分、波次、升级全部落地，**拆砖音是砖墙体验闭环的最后一个缺失反馈**：拆砖是核心循环动作（高频），目前只有视觉（砖消失）无听觉反馈，与 paddle_hit（击球音）形成反馈不对称。

### 为什么现在改

- 砖墙系统已全量落地（#384→#393 组装），拆砖是玩家最高频的交互动作之一，听觉反馈缺口显著。
- 本 Issue 属于 worktree 并行测试 T3（2026-08-13）：刻意与两个并行 issue 同改 `constants.gd` 不同区域，验证提交前 merge main 的自动合并——**文件域纪律是 AC5 的硬约束**。
- 合成音方案与 #296 既有架构零摩擦：复用 AudioStreamGenerator 管道，新增一个方法 + 一组常量 + 一组测试即可，无外部资产、无新依赖。

### 既往约束

| 约束 | 详情 |
|------|------|
| 纯合成音（零资产） | #296 架构：AudioStreamGenerator 运行时生成，不引入 wav/ogg 资产（Issue 原文「合成音」） |
| Headless 优雅降级 | AudioServer 不可用 → `_enabled=false`，play_*() 全 no-op；brick.gd 触发必须 null-safe（`is_instance_valid(AudioEngine)`） |
| 幂等 destroy() | #384：`_destroyed` 标志保证 destroy() 只执行一次 → 音效恰好触发一次，无重复播放 |
| 测试确定性 | 帧数断言沿用 TC8 模式（`int(44100 * duration)`）；噪声合成需**固定种子**保证测试可复现（spike 已实测同种子帧值一致） |
| 机械参数 | `BRICK_BREAK_*` 为机械常量（时长/音量/衰减），数值调优（如音色更脆/更闷）归 taste 流程，不阻塞本 Issue |
| 文件域白名单 | 只改 4 个文件（AC5），绝不动其他 issue 的文件（T3 并行红线） |
| 单一声明源 | 音效参数必须进 constants.gd AUDIO 区，不得散落硬编码（spike 原型中的字面量须常量化） |

---

## 3. 影响分析

### 直接影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `mini-pong/gdscripts/audio_engine.gd` | AudioEngine | **修改**：新增 public `play_brick_break()` + 内部噪声合成（复用 `_playback.push_frame` 管道）；建议抽 `_play_noise_burst(duration, volume, seed)` 内部方法（与 `_play_tone` 对称），`play_brick_break()` 调它并读 constants |
| `mini-pong/gdscripts/brick.gd` | 单砖 | **修改**：`destroy()` 内新增 null-safe 触发：`if is_instance_valid(AudioEngine): AudioEngine.play_brick_break()`（置于 grid 通知后、queue_free 前） |
| `mini-pong/gdscripts/constants.gd` | 全局常量 | **修改**：文件**末尾新增** `# ── Audio (#450) ──` 区：`BRICK_BREAK_DURATION`、`BRICK_BREAK_VOLUME`、`BRICK_BREAK_DECAY_TAU`、`BRICK_BREAK_SEED`（数值见 §4 推荐，均为机械占位，taste-draft 可调） |
| `mini-pong/tests/test_audio_engine.gd` | 音效测试 | **修改**：新增 TC14（brick_break 帧数 ≈ 44100×duration）、TC15（衰减包络：early 振幅 > late 振幅）、TC16（同种子确定性：两次调用帧序列一致）、TC17（headless no-op：`_enabled=false` 不崩） |

### 新增文件

无（零新文件——4 文件修改域内完成，符合 AC5 与 T3 并行红线）。

### 间接影响模块

| 文件 | 影响 |
|------|------|
| `mini-pong/tests/test_breakout_grid.gd` | destroy 幂等/信号用例不受影响（brick 测试环境无 AudioEngine autoload → null-safe 守卫静默跳过）；运行验证为准 |
| `mini-pong/gdscripts/breakout_grid.gd` | 不直接改动；其 blast_neighbors 批量路径（#387）经 brick.destroy() 自动获得音效，零额外接线 |
| `mini-pong/tests/run_tests.gd` | 已注册 `test_audio_engine.gd`（line 30），新 TC 自动纳入；**无需改 run_tests.gd**（文件域外，保持零改动） |
| `mini-pong/tests/test_constants.gd` | 若断言常量数量/特定分区，需确认新增 AUDIO 区不破坏（基线实测为准；研究期未见硬编码分区计数断言） |

### 数据流

```
Ball._on_body_entered (bricks 分支, #384)
    │ body.destroy()  ← brick.gd destroy()（幂等, _destroyed 标志）
    │   ├── grid._on_brick_destroyed(self)   ← 既有（网格计数/信号）
    │   ├── [新增] is_instance_valid(AudioEngine) → AudioEngine.play_brick_break()
    │   │        └── _play_noise_burst(BRICK_BREAK_*) → _playback.push_frame(噪声×衰减包络)
    │   └── queue_free()
    └── (网格 blast_neighbors 批量路径 #387: 每砖各自 destroy() → 各自触发)
```

---

## 4. 方案比较

### 方案 A：纯 sin 波短音（复用 `_play_tone`，零新代码）

`play_brick_break()` 直接调 `_play_tone(高频率, 0.08, 0.7)`（如 900Hz 短促音）。

| 维度 | 评价 |
|------|------|
| Pros | 零新增合成逻辑；与 4 个既有音效完全同构；测试可完全复用 TC8 帧数模式 |
| Cons | **纯 sin 波不像碎裂音**——听感是「哔」而非「啪/咔」；与 paddle_hit（200Hz blip）音色区分度低，反馈差异化目标落空；Issue 明确要求「碎裂音」，纯音不满足 |
| Risk | 低（技术零风险），但**验收意图不达标**（碎裂感缺失） |
| Effort | ~15 行 + 常量 |

### 方案 B：噪声突发 + 快速指数衰减包络（推荐，spike 已实测）

`play_brick_break()` 用固定种子 RNG 生成 44100×duration 帧噪声样本，乘以指数衰减包络（τ ≈ duration/4），经 `_playback.push_frame` 推送。参数（duration/volume/decay/seed）全部读 constants.gd AUDIO 区。

| 维度 | 评价 |
|------|------|
| Pros | **听感正确**——白噪声突发 + 快衰减 = 典型碎裂/破裂声；与既有 4 音（全 sin 波）音色维度完全错开，拆砖反馈辨识度最高；spike 实测：80ms → 3528 帧、peak≈0.69、early_avg 0.31 vs late_avg 0.009（衰减 35×，包络正确）、同种子逐帧确定（`determinism: true`）；headless 下 mock playback 全通 |
| Cons | 新增噪声合成路径（与 `_play_tone` 平行的 `_play_noise_burst`）；测试断言需适配（帧数断言沿用 TC8，包络断言用早/晚段均值比，确定性断言用同种子两次调用逐帧相等）——spike 已给出全部断言依据 |
| Risk | 低（spike 全绿）；需注意 `AudioServer` 真实播放时噪声不会削波（volume ≤ 0.7，spike peak 0.69 < 1.0） |
| Effort | ~30 行（方法 + 内部合成器）+ 4 常量 + 4 TC（spike 已验证可行） |

### 方案 C：多频叠加「玻璃碎」音（3-4 个失谐 sin 波簇）

用多个接近但不同频率的短 sin 波叠加 + 快衰减，模拟玻璃/瓷砖碎裂的「多频拍频」感。

| 维度 | 评价 |
|------|------|
| Pros | 仍走 sin 波路径（与既有架构同构度高）；多频拍频有「碎」的质感 |
| Cons | 音色偏「玻璃/金属」而非「砖块」；实现复杂度高于 B（需管理频簇数组）；测试断言更复杂（多段零交叉计数） |
| Risk | 中（拍频参数难一次到位，可能需要多轮调参） |
| Effort | ~50 行 + 5+ 常量 + 复杂测试 |

### 推荐结论

| 方案 | 推荐 | 核心依据 |
|------|------|---------|
| A 纯 sin 波 | ❌ | 听感不达「碎裂音」验收意图 |
| **B 噪声突发+指数衰减** | ✅ **推荐** | spike 实测全绿（帧数/包络/确定性/headless）；听感正确；实现最简；参数全部机械化进 constants |
| C 多频簇 | ⚠️ 备选 | 若 B 的音色在真实播放中不够「砖」，C 作为 taste 阶段的调音选项 |

**推荐常量值（机械占位，taste-draft 可调）:** `BRICK_BREAK_DURATION = 0.08`（80ms 短促）、`BRICK_BREAK_VOLUME = 0.7`（<1.0 防削波，spike peak 0.69 验证）、`BRICK_BREAK_DECAY_TAU = 0.02`（τ=duration/4，快速衰减）、`BRICK_BREAK_SEED = 450`（固定种子，测试确定性；同种子两次合成逐帧一致，spike 实测）。

---

## 5. 边界条件与验收标准

### 验收标准（映射 Issue AC）

| # | AC | 验证方式 | 边界条件 |
|---|----|---------|---------|
| AC1 | AudioEngine 新增 `play_brick_break()`（AudioStreamGenerator 合成短促碎裂音） | 新增方法存在；spike 原型已实测 3528 帧/80ms、衰减包络正确 | 复用 `_setup_generator` 管道；`_enabled=false` 时 no-op（沿 TC12 模式） |
| AC2 | brick.gd 碎裂时调用 `play_brick_break`（null-safe） | destroy() 内 `is_instance_valid(AudioEngine)` 守卫后调用；无 autoload 环境静默跳过 | 幂等 destroy() → 音效恰好一次；测试环境不崩 |
| AC3 | constants.gd 新增 AUDIO 区（BRICK_BREAK_*），不影响现有常量 | 文件末尾追加新区；基线 run_tests.gd 全绿证明零破坏 | 不改动已有 14 区任何一行 |
| AC4 | `--headless --quit` 无脚本错误；run_tests.gd 全绿 | 研究期基线实测 2216 passed / 0 failed；实现后重跑须全绿 | headless 降级路径（AudioServer 缺失 push_warning 不崩） |
| AC5 | PR 文件仅含本 issue 文件域 | worktree-commit.sh 白名单提交（4 文件），绝不 add . | T3 并行红线：不混入其他 issue 文件（尤其 constants.gd 只加 AUDIO 区） |

### 边界条件

- **零资产**：不引入 wav/ogg/导入资源（纯 AudioStreamGenerator 合成）。
- **零新增文件**：4 文件修改域内完成（含测试，新 TC 进 test_audio_engine.gd，不新建测试文件、不改 run_tests.gd）。
- **确定性**：噪声合成必须固定种子（BRICK_BREAK_SEED），保证 CI 测试可复现。
- **不削波**：音量常量 < 1.0（spike peak 0.69 为上限参考）。
- **文件域**：constants.gd 仅追加 AUDIO 区（T3 三个并行 issue 各改不同区域，merge main 自动合并——worktree-commit.sh 提交前 merge origin/main 处理）。
- **taste 分离**：数值调优（音色/时长）归 taste 流程，机械常量值可后续 PR 调整，不阻塞本 Issue。

---

## 6. 依赖与阻塞

| 依赖 | 状态 | 说明 |
|------|------|------|
| #296 AudioEngine | ✅ 已合并（既有 autoload） | 复用其合成管道与守卫模式，无新依赖 |
| #384 砖墙系统 | ✅ 已合并（brick.gd 存在） | destroy() 语义稳定，只追加触发行 |
| #385/#387/#393 | ✅ 已合并 | 双得分/升级/组装已落地；play_brick_break 延期归属在本 Issue 兑现 |
| constants.gd 现状 | ✅ 稳定 | 新增 AUDIO 区为纯追加，基线测试证明无破坏 |
| 外部资产/插件 | ✅ 无 | 纯合成方案，无需 Godot Asset Library / 第三方音频资产（Issue「开源优先」调研结论：合成音满足需求，复用成本 > 自研成本——合成音本就是零资产架构的一部分，无成熟插件可「复用」替代一个 30 行方法） |
| 阻塞项 | ✅ 无 | 无 |

---

## 7. Spike / 实验

> depth/standard：Section 7 非强制，但研究期实际执行了合成可行性 spike（见下），结果已进入 §4 推荐依据。

### Spike S1：噪声突发碎裂音合成可行性（2026-08-13 实测）

**目的:** 验证方案 B（噪声突发 + 指数衰减）在 AudioEngine 管道（mock playback）下 headless 可合成、包络正确、可确定性复现。

**方法:** 临时脚本（`/tmp/spike_brick_break.gd`，不入库）实例化 audio_engine.gd + mock playback（沿用 test_audio_engine.gd 模式），以 `BRICK_BREAK_*` 原型值（duration=0.08, volume=0.7, seed=450）合成 80ms 噪声突发。

**结果（全绿）:**

| 断言 | 实测 | 结论 |
|------|------|------|
| 帧数 = 44100×0.08 | 3528 / 3528 | ✅ 与 TC8 帧数断言模式一致 |
| 峰值振幅 < 1.0（防削波） | 0.689 | ✅ volume=0.7 安全 |
| 衰减包络（early > late×3） | 0.3055 vs 0.0087（35×） | ✅ 快速衰减，碎裂「啪」感成立 |
| 同种子确定性（两次调用逐帧相等） | true | ✅ 测试可复现 |
| headless 无崩溃 | 仅退出时引擎级资源告警（既有噪音） | ✅ |

**结论:** 方案 B 全部可行性断言通过，无技术风险；实现阶段按 §4 常量值与 §5 AC 落地即可。

---

## 8. 交接上下文（Continuation Context）

### 给 plan agent 的交付物

**已定:** 方案 B（噪声突发 + 快速指数衰减），零新文件，4 文件修改域。

### 实现要点（file-by-file）

1. **`mini-pong/gdscripts/constants.gd`** — 文件**末尾**追加 `# ── Audio (#450) ──` 区：
   - `const BRICK_BREAK_DURATION: float = 0.08`
   - `const BRICK_BREAK_VOLUME: float = 0.7`
   - `const BRICK_BREAK_DECAY_TAU: float = 0.02`（τ = duration/4）
   - `const BRICK_BREAK_SEED: int = 450`
   - 不触碰已有 14 区（T3 并行红线）。
2. **`mini-pong/gdscripts/audio_engine.gd`** —
   - 新增 public `play_brick_break() -> void`（沿 `play_paddle_hit` 等文档注释风格）。
   - 新增内部 `_play_noise_burst(duration: float, volume: float, seed: int) -> void`（与 `_play_tone` 对称）：`RandomNumberGenerator` 固定 seed → `SAMPLE_RATE*duration` 帧 → `exp(-t/τ)` 包络 → `push_frame(Vector2(v,v))`；复用 `_enabled`/`_playback` 守卫与 stream_paused 切换逻辑（与 `_play_tone` 相同）。
   - 常量读取：`preload("res://gdscripts/constants.gd")`（文件已 import 模式：`const CONSTS = preload(...)`）。
3. **`mini-pong/gdscripts/brick.gd`** — `destroy()` 内、grid 通知后、`queue_free()` 前追加：
   ```gdscript
   if is_instance_valid(AudioEngine):
       AudioEngine.play_brick_break()
   ```
   （null-safe；无 autoload 环境静默跳过，AC2）
4. **`mini-pong/tests/test_audio_engine.gd`** — 新增 TC14–TC17（沿用 `_make_audio_engine` 工厂）：
   - TC14 帧数：`play_brick_break()` 后 frames.size() ≈ `44100 × BRICK_BREAK_DURATION`（tolerance 0.02，沿 TC8.2）。
   - TC15 衰减：early 段均值 > late 段均值 × 3（沿 spike 断言）。
   - TC16 确定性：同 seed 两次调用逐帧相等（`frames_a[i] == frames_b[i]`）。
   - TC17 headless no-op：`_enabled=false` 时调用不崩（沿 TC12 模式）。
   - **不修改 run_tests.gd**（已注册该文件，line 30）。

### 验证清单（implement 后必须全绿）

```bash
cd mini-pong
godot --headless --quit                          # 无脚本错误
godot --headless --script res://tests/run_tests.gd   # 全绿（基线 2216 passed / 0 failed，新增 TC 后 ≥2220）
```

### 边界重申（防止越界）

- ❌ 不新增文件（含测试文件）；❌ 不改 run_tests.gd；❌ 不改 grid/ball/game_manager 等域外文件。
- ❌ 不引入音频资产；❌ 不改 constants.gd 既有 14 区。
- ✅ worktree 提交走 `scripts/worktree-commit.sh 450 "<msg>" <4 个白名单文件>`（提交前自动 merge origin/main，处理 T3 并行 constants.gd 改动）。
- taste 调音（更脆/更闷/更长）→ 后续 taste-draft PR 改 `BRICK_BREAK_*` 值，本 Issue 只定机械结构。
