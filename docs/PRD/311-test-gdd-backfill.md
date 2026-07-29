# PRD: [Fix] 补全 #288 #289 的测试覆盖与 GDD 条目

> **Issue:** #311
> **标签:** enhancement, workflow/research, depth/standard, priority/high, version/mvp, estimate/medium
> **Agent:** game-research-agent
> **日期:** 2026-07-29
> **前置依赖:** #288 (✅ MERGED — Player Paddle), #289 (✅ MERGED — Neon Visual), #301 (✅ MERGED — Scaffold)

---

## 1. 问题定义

### 当前状态

PR #309 (#288 Paddle) 和 PR #310 (#289 Neon Visual) 已合并到 `main` 分支，代码编译通过、功能正常运行。但两个 PR **绕过了 review agent 管线**，直接合并，导致三项关键交付缺失：

| 交付物 | #288 Paddle | #289 Neon Visual |
|--------|:-----------:|:----------------:|
| 代码 | ✅ 已合并 | ✅ 已合并 |
| DESIGN 文档 | ✅ `docs/DESIGN/288-player-paddle.md` | ✅ `docs/DESIGN/289-neon-visual.md` |
| PRD 文档 | ✅ `docs/PRD/288-player-paddle.md` | ✅ `docs/PRD/289-neon-visual.md` |
| **测试文件** | ❌ 缺失 | ❌ 缺失 |
| **GDD 条目** | ❌ 缺失 | ❌ 缺失 |
| **review agent 审核** | ❌ 未经过 | ❌ 未经过 |

### 缺失的具体内容

1. **测试文件 — 零覆盖：** `tests/` 目录不存在。DESIGN 文档中有详细的测试用例描述（#288：TC-A1~E3 共 14 个， #289：TC1~TC17 共 17 个），但没有对应的 GDScript 测试文件。CI 仅有 `godot --path mini-pong/ --headless --quit` 编译检查，无运行时测试。

2. **GDD 条目 — 无记录：** `docs/GAME_DESIGN/INDEX.md` 只列出第 10 章（3D Scene Layout），没有 Paddle 系统和 Neon Visual 系统的章节。代码中的架构决策、常量定义、数据流没有收敛到 GDD 中。

3. **Pipeline 完整性 — 绕过：** 两个 PR 从未经过 review agent，代码质量和测试覆盖没有自动化保障。

### 预期行为（本 Issue 的交付物）

1. **创建测试文件** — 从 DESIGN doc 的测试用例描述转换为可运行的 GDScript 测试
2. **创建 GDD 章节** — 为 Paddle 系统和 Neon Visual 系统编写 GDD 文档
3. **通过完整 CI → review → merge 管线** — 验证 pipeline 修复后能正常工作

### 范围边界

| 包括 | 不包括 |
|------|--------|
| 基于现有 DESIGN 创建 GDScript 测试文件 | 修改现有源代码（`paddle.gd`、`ball_trail.gd` 等） |
| 为 Paddle 和 Neon Visual 编写 GDD 章节 | 重新设计或重构任何系统 |
| 测试文件通过 Godot headless 运行 | 在编辑器中手动运行视觉测试 |
| 将测试文件集成到现有 CI | 修改 CI pipeline 本身（仅添加测试步骤） |
| 初始化 `tests/` 目录 + 测试运行器 | 为其他待实现系统（Ball、AI、Score）编写测试 |

---

## 2. 设计意图

### 为什么是现在

两个 PR 合并后，代码已进入 `main` 分支，但缺少自动化测试保护。任何后续 Issue（#290 Ball、#295 Main Scene）的代码变更都可能破坏现有行为且无人知道。在累积更多未测试代码之前建立测试基础设施，是保持项目健康的必要步骤。

### 设计原则

1. **测试先行回填：** 从现有 DESIGN doc 的测试用例描述直接转换，不新增测试用例。DESIGN 已由 plan agent 产出，测试用例经过详细设计 — 本 Issue 的任务是**实现**这些测试，不是设计新的。
2. **GDScript 测试（非 Python/pytest）：** 所有测试在 Godot headless 模式下运行，使用 `extends SceneTree` + `_init()` 入口 + 自实现 assert 辅助函数。不使用 GUT/gdUnit4。
3. **测试覆盖分层：** 可自动化的逻辑（InputMap、移动、clamp、编译、脚本语法）在 headless 中测试；视觉效果（neon glow、粒子拖尾、得分闪烁动画）标记为手动验证。
4. **GDD 收敛：** GDD 章节从 DESIGN doc 提取架构决策、常量定义、数据流，不包含测试用例和实施细节。
5. **不修改现有代码：** 本 Issue 仅新建文件，不修改 `mini-pong/gdscripts/`、`mini-pong/scenes/`、`mini-pong/assets/` 中的任何文件。

---

## 3. 代码审计

### 3.1 #288 Paddle — 文件清单

| 文件 | DESIGN §7 要求 | 实际状态 | 内容验证 |
|------|:---:|:---:|------|
| `mini-pong/gdscripts/paddle.gd` | CREATE | ✅ 存在 (60 行) | Area2D extends，InputMap 绑定，`_process` 移动+clamp |
| `mini-pong/scenes/player_paddle.tscn` | CREATE | ✅ 存在 (19 行) | Area2D 根 + ColorRect(20×120) + CollisionShape2D(RectangleShape2D) |

**代码关键词验证：**
- `const SPEED: float = 400.0` — ✅
- `const PADDLE_HEIGHT: float = 120.0` — ✅
- `const FALLBACK_VIEWPORT_Y: float = 720.0` — ✅
- `InputMap.has_action("paddle_up")` — ✅ 防重复绑定
- `InputMap.has_action("paddle_down")` — ✅ 防重复绑定
- 同时按下 W+S 取消 — ✅ `up and not down` / `down and not up`
- `clamp(position.y, min_y, max_y)` — ✅ `_process` 末尾
- Headless fallback (viewport.y == 0 → 720.0) — ✅

### 3.2 #289 Neon Visual — 文件清单

| 文件 | DESIGN §7 要求 | 实际状态 | 内容验证 |
|------|:---:|:---:|------|
| `mini-pong/gdscripts/neon_glow.gdshader` | CREATE | ✅ 存在 (23 行) | `shader_type canvas_item`，外发光边缘检测 |
| `mini-pong/gdscripts/ball_trail.gd` | CREATE | ✅ 存在 (36 行) | `@onready var particles`，速度阈值 20.0/600.0 |
| `mini-pong/gdscripts/score_flash.gd` | CREATE | ✅ 存在 (48 行) | `create_tween()` 0.2s 淡出，信号注释保留 |
| `mini-pong/assets/gradient_neon.tres` | CREATE | ✅ 存在 (8 行) | GradientTexture1D，蓝#4a90d9→紫#8833ff |
| `mini-pong/assets/particle_material.tres` | CREATE | ✅ 存在 (16 行) | ParticleProcessMaterial，lifetime=0.5，amount=50 |
| `mini-pong/scenes/world_environment.tscn` | MODIFY | ✅ 已更新 (11 行) | glow_bloom=0.8 ✅，background_color ✅ |
| `mini-pong/project.godot` | MODIFY | ✅ 已更新 (12 行) | default_clear_color=Color(0.039, 0.039, 0.071, 1) ✅ |

**代码关键词验证：**
- `shader_type canvas_item` — ✅
- `MIN_SPEED_FOR_TRAIL: float = 20.0` — ✅
- `MAX_SPEED_FOR_TRAIL: float = 600.0` — ✅
- `create_tween()` + `tween_property` — ✅
- `if _flash_tween and _flash_tween.is_valid(): _flash_tween.kill()` — ✅
- `glow_bloom = 0.8` — ✅
- `background_color = Color(0.039, 0.039, 0.071, 1)` — ✅

### 3.3 审计结论

所有 7 个文件（2+5 新建 + 2 修改）均存在且与 DESIGN doc 一致。代码质量良好 — 无拼写错误、无遗漏的常量、边界条件通过 `push_warning` 优雅降级。

---

## 4. 缺口分析

| 类别 | 需求 | 当前状态 | 缺口 |
|------|------|:---:|------|
| **测试目录** | `mini-pong/tests/` 存在 | ❌ 不存在 | 创建目录 |
| **测试运行器** | `tests/run_tests.gd` | ❌ 不存在 | 创建统一入口测试运行器 |
| **Paddle — Scenario A (InputMap)** | TC-A1~A3 (3 个测试) | ❌ 未实现 | 测试 InputMap action 创建/键绑定/防重复 |
| **Paddle — Scenario B (Movement)** | TC-B1~B4 (4 个测试) | ❌ 未实现 | 测试上下移动/同时取消/无输入 |
| **Paddle — Scenario C (Clamping)** | TC-C1~C3 (3 个测试) | ❌ 未实现 | 测试顶部/底部 clamp/启动 clamp |
| **Paddle — Scenario D (Headless)** | TC-D1~D2 (2 个验证) | ❌ 未实现 | 测试编译零错误（现有 CI 部分覆盖） |
| **Paddle — Scenario E (Scene)** | TC-E1~E3 (3 个测试) | ❌ 未实现 | 测试节点树/shape 非空/脚本挂载 |
| **Neon — Scenario A (WorldEnv 编译)** | TC1~TC4 (4 个测试) | ❌ 未实现 | 测试 headless 编译/grep 验证配置值 |
| **Neon — Scenario B (资源文件)** | TC5~TC7 (3 个测试) | ❌ 未实现 | 测试 .gdshader/.tres 文件存在且有效 |
| **Neon — Scenario C (脚本编译)** | TC8~TC9 (2 个测试) | ❌ 未实现 | 测试 ball_trail.gd/score_flash.gd 语法有效 |
| **Neon — Scenario D (视觉)** | TC10~TC17 (8 个测试) | ❌ 手动验证 | headless 无法验证 — 标记为 manual-only |
| **GDD — INDEX** | 更新索引表 | ❌ 未包含新章节 | 添加两行 |
| **GDD — Paddle 章节** | `docs/GAME_DESIGN/11-PLAYER-PADDLE.md` | ❌ 不存在 | 创建 GDD 章节 |
| **GDD — Neon 章节** | `docs/GAME_DESIGN/12-NEON-VISUAL.md` | ❌ 不存在 | 创建 GDD 章节 |

---

## 5. 解决方案

### 5.1 交付物概述

| # | 文件 | 类型 | 用途 |
|---|------|------|------|
| 1 | `mini-pong/tests/run_tests.gd` | GDScript | 统一测试运行器入口 |
| 2 | `mini-pong/tests/test_paddle.gd` | GDScript | #288 Paddle 自动化测试 |
| 3 | `mini-pong/tests/test_neon.gd` | GDScript | #289 Neon 编译/资源验证测试 |
| 4 | `docs/GAME_DESIGN/11-PLAYER-PADDLE.md` | Markdown | Paddle 系统 GDD 章节 |
| 5 | `docs/GAME_DESIGN/12-NEON-VISUAL.md` | Markdown | Neon Visual 系统 GDD 章节 |
| 6 | `docs/GAME_DESIGN/INDEX.md` | Markdown (MODIFY) | 添加两行索引 |

### 5.2 测试运行器架构

```
mini-pong/tests/
├── run_tests.gd        ← 入口: extends SceneTree, _init() 调用各套件
├── test_paddle.gd      ← Paddle 测试套件 (RefCounted, 公共属性 passed/failed)
└── test_neon.gd        ← Neon 测试套件 (RefCounted, 公共属性 passed/failed)
```

**运行命令：**
```bash
godot --path mini-pong/ --headless --script tests/run_tests.gd
```

### 5.3 测试模式

使用 `extends RefCounted` 的套件脚本模式（参考 `godot-headless-test-patterns` §Pattern 1-4）：

- **每个套件**暴露 `var passed: int = 0` 和 `var failed: int = 0`（公共属性，非 `_passed`）
- **每个套件**提供 `func run() -> void` 方法
- **运行器** `load("res://tests/test_xxx.gd").new()` 创建实例，调用 `.run()`，汇总计数
- **辅助断言** `func _assert(condition: bool, name: String) -> void` 不打印通过项（避免 CI pipe buffer 死锁）
- **退出** `quit(1 if _fail > 0 else 0)`

### 5.4 Paddle 测试实现策略

| 测试类别 | DESIGN 用例 | 测试策略 | 关键技术点 |
|---------|------------|---------|-----------|
| A (InputMap) | TC-A1~A3 | `extends SceneTree`，调用 `_ready()` 触发生成 InputMap | `InputMap.has_action()`, `action_get_events()` |
| B (Movement) | TC-B1~B4 | 加载 paddle.gd 脚本，手动设置 position、调用 `_process(delta)` | 不依赖 Input 实际按键（headless 限制） |
| C (Clamping) | TC-C1~C3 | 直接设置 position 超出边界，调用 `_process(delta)` | `clamp()` 在 `_process()` 末尾执行 |
| D (Headless) | TC-D1~D2 | 由 CI `--headless --quit` 覆盖 — 测试运行器自身即是验证 | 测试运行器编译通过 = TC-D2 通过 |
| E (Scene) | TC-E1~E3 | `load("res://scenes/player_paddle.tscn")` → `instantiate()` → 检查节点树 | `PackedScene.instantiate()` 在 `--script` 模式可用 |

**Movement 测试的 headless 特殊处理：**

在 `--script` 模式下，`Input.is_action_pressed()` 始终返回 `false`（InputMap 事件数组为空）。因此 Movement 测试不通过实际按键输入，而是：
1. 加载 paddle.gd 脚本
2. 调用 `_ready()` 创建 InputMap action 和边界
3. **直接设置 position.y** 作为起始位置
4. **直接调用 `_process(delta)`** 传入不同的 `delta` 值
5. 检查 position 变化

对于"模拟按键"的需求，由于 headless 限制无法实现，改为测试 `_process` 中的方向逻辑：设置 `up=true, down=false` → position 减少 → 验证 `move` 逻辑正确。实际上更简单的做法是：直接验证速度公式 `position.y += move * SPEED * delta` 的数值结果。

**推荐简化策略：** 使用 `Node.new()` + `set_script(load("res://gdscripts/paddle.gd"))` 创建测试实例（参考 `godot-headless-test-patterns` §Pattern 2），直接调用其方法验证数值行为。

### 5.5 Neon 测试实现策略

| 测试类别 | DESIGN 用例 | 测试策略 | 自动化 |
|---------|------------|---------|:---:|
| A (WorldEnv 编译) | TC1~TC4 | TC1: `--headless --quit` = 0（CI 已有）；TC2-4: 文件内容 grep 验证 | ✅ |
| B (资源文件) | TC5~TC7 | `ResourceLoader.exists()` 或 `load()` 验证文件存在且格式有效 | ✅ |
| C (脚本编译) | TC8~TC9 | `load("res://gdscripts/ball_trail.gd")` 非 null → 编译通过 | ✅ |
| D (视觉) | TC10~TC17 | headless 无法验证渲染效果 — 输出 MANUAL ONLY 标记 | ❌ |

**TC5-7 资源文件验证：**
```gdscript
# .gdshader 通过 load() 验证
var shader = load("res://gdscripts/neon_glow.gdshader")
_assert(shader != null, "neon_glow.gdshader loads")

# .tres 同样通过 load() 验证
var gradient = load("res://assets/gradient_neon.tres")
_assert(gradient != null, "gradient_neon.tres loads")
```

**TC8-9 脚本编译验证：**
- `ball_trail.gd` 包含 `as CharacterBody2D` 类型转换 — 运行时返回 null 但不影响编译
- `score_flash.gd` 使用 `create_tween()` 而非 `Tween.new()` — Godot 4 正确模式
- 两个脚本都有 `push_warning` 优雅降级

### 5.6 GDD 章节结构

遵循 AGENTS.md 中定义的 GDD 模板约定（`framework/templates/GDD_TEMPLATE.md`，模板文件暂不存在，但规范已在 AGENTS.md §GDD 明确定义）：

> GDD 章节内容收敛自 DESIGN doc 的架构决策/常量/数据流。写作风格 "人读得懂，LLM 查得到"：叙事体、层次编号、代码块放定义、表格放参数、段落讲意图。

**11-PLAYER-PADDLE.md 内容映射：**

| GDD 章节 | 来源 |
|---------|------|
| 系统概述 | DESIGN §1 架构概述 + §2 设计理念 |
| 节点树 | DESIGN §1 + `player_paddle.tscn` 实际内容 |
| 核心常量 | DESIGN §2.1 常量表 |
| InputMap 绑定 | DESIGN §2.1 `_ready()` 逻辑 |
| 移动与边界 | DESIGN §2.1 `_process(delta)` 逻辑 |
| 数据流 | DESIGN §3 数据流图 |
| 边界条件 | DESIGN §4 边界条件表 |
| 集成点 | DESIGN §5 集成点表 |

**12-NEON-VISUAL.md 内容映射：**

| GDD 章节 | 来源 |
|---------|------|
| 系统概述 | DESIGN §1 架构图 + §2 设计原则 |
| 颜色常量 | DESIGN §8 颜色常量表 |
| WorldEnvironment | DESIGN §3.1 world_environment.tscn 当前状态 |
| 外发光 Shader | DESIGN §2.1 neon_glow.gdshader |
| 球拖尾系统 | DESIGN §2.2 ball_trail.gd + §2.4/2.5 .tres 文件 |
| 得分闪烁 | DESIGN §2.3 score_flash.gd |
| 数据流 | DESIGN §4 数据流图 |
| 集成点 | DESIGN §6 集成点表 + 信号合约 |
| 视觉验证（手动） | DESIGN §7 Scenario D |

---

## 6. 边界条件与验收标准

### 6.1 可自动化测试

- [ ] **AC1: Paddle InputMap 创建** — `InputMap.has_action("paddle_up")` 和 `InputMap.has_action("paddle_down")` 为 true
- [ ] **AC2: Paddle 键绑定** — `action_get_events("paddle_up")` 包含 KEY_W 和 KEY_UP
- [ ] **AC3: Paddle 防重复绑定** — 多次调用 `_ready()` 不崩溃，action 仍存在
- [ ] **AC4: Paddle 移动逻辑** — `_process(delta)` 中 `position.y` 变化符合 `move * SPEED * delta`
- [ ] **AC5: Paddle 同时按下取消** — up+down 同时 true → position 不变
- [ ] **AC6: Paddle 顶部 clamp** — position.y = -1000, `_process(0.016)` → position.y = min_y
- [ ] **AC7: Paddle 底部 clamp** — position.y = 2000, `_process(0.016)` → position.y = max_y
- [ ] **AC8: Paddle 启动 clamp** — `_ready()` 后 position.y 在 [min_y, max_y] 内
- [ ] **AC9: 场景节点层级** — `player_paddle.tscn` root 是 Area2D，两个子节点是 ColorRect 和 CollisionShape2D
- [ ] **AC10: CollisionShape2D 非空** — shape 是 RectangleShape2D 且 size > 0
- [ ] **AC11: 脚本挂载** — Area2D root 的 script 指向 paddle.gd
- [ ] **AC12: Neon headless 编译** — `godot --path mini-pong/ --headless --quit` 退出码 0
- [ ] **AC13: Neon 配置文件** — world_environment.tscn 包含 `glow_bloom = 0.8` 和 `background_color`
- [ ] **AC14: Neon shader 加载** — `load("res://gdscripts/neon_glow.gdshader")` 非 null
- [ ] **AC15: Neon 资源加载** — gradient_neon.tres 和 particle_material.tres 可加载
- [ ] **AC16: Neon 脚本编译** — ball_trail.gd 和 score_flash.gd `load()` 非 null
- [ ] **AC17: GDD INDEX 更新** — INDEX.md 包含 11-PLAYER-PADDLE 和 12-NEON-VISUAL 行
- [ ] **AC18: GDD 章节存在** — 11-PLAYER-PADDLE.md 和 12-NEON-VISUAL.md 文件存在
- [ ] **AC19: 测试运行器退出码** — `run_tests.gd` 在全部通过时返回 0

### 6.2 手动验证（headless 不可测试）

- [ ] **AC-M1: Neon 视觉效果** — 在编辑器中打开 mini-pong 项目，确认背景深色 (#0a0a12)、bloom 配置生效
- [ ] **AC-M2: 球拖尾可见** — 球运动时 GPUParticles2D 发射渐变粒子（需要球场景存在后验证）
- [ ] **AC-M3: 得分闪烁** — ColorRect overlay 0.2s 淡出（需要计分系统 #TBD 后验证）
- [ ] **AC-M4: 发光轮廓** — ShaderMaterial 在球/球拍上生效（需要 ShaderMaterial 挂载后验证）

### 6.3 边缘情况

| # | 场景 | 预期行为 |
|---|------|---------|
| 1 | `tests/` 目录不存在 | `run_tests.gd` 创建时自动创建目录 |
| 2 | `load("res://gdscripts/paddle.gd")` 返回 null | 测试报告文件不存在，提示检查路径 |
| 3 | 同时运行多个测试套件 | 每个套件独立 `new()`，无共享状态 |
| 4 | GDD INDEX 格式不一致 | 严格遵循现有 INDEX 格式（markdown table） |
| 5 | CI 运行测试时 Godot 未安装 | CI 已有 `setup-godot@v2` — 本 Issue 不新增 CI infrastructure |
| 6 | `--script` 模式下 `class_name` 不解析 | 测试文件使用 `load()` 不依赖 `class_name`，符合 godot-headless-test-patterns §Pattern 1 |

---

## 7. 依赖与阻碍

### 依赖关系

```
#288 (Player Paddle — ✅ MERGED) ──┐
                                   ├──► #311 (Test + GDD Backfill — 本 Issue)
#289 (Neon Visual — ✅ MERGED) ────┘
                                   │
                                   ▼
                              后续 Issues (#290 Ball, #295 Main Scene, ...)
```

| 依赖 | 状态 | 风险 | 说明 |
|------|:----:|:----:|------|
| #288 Paddle 代码 | ✅ 已合并 | 无 | 代码完整，可直接测试 |
| #289 Neon Visual 代码 | ✅ 已合并 | 无 | 代码完整，资源文件可加载验证 |
| DESIGN docs (288/289) | ✅ 存在 | 无 | 测试用例描述完整 |
| Godot 4.7 headless | ✅ 可用 | 低 | CI 已验证可用 |
| `tests/` 目录 | ❌ 不存在 | 低 | 本 Issue 创建 |

### 被阻碍

本 Issue **不阻碍**后续功能开发 — 代码已在 main 分支。但完成本 Issue 后：
- 后续 Implement agent 可以运行 `godot --headless --script tests/run_tests.gd` 验证未破坏现有行为
- Review agent 可以检查测试通过状态

---

## 8. 延续上下文（Implement Agent 交接）

### 当前系统状态

- `mini-pong/` 子项目完整，包含 #288 (Paddle) + #289 (Neon Visual) 代码
- `tests/` 目录不存在 — 需创建
- CI 已有 `godot --path mini-pong/ --headless --quit` 编译检查
- `docs/GAME_DESIGN/` 有 INDEX.md 和 10-SCENE-LAYOUT.md
- 默认分支：`main`

### 实施注意事项

1. **测试目录创建顺序：**
   ```bash
   mkdir -p mini-pong/tests
   ```

2. **测试运行器入口 `run_tests.gd`：**
   ```gdscript
   extends SceneTree
   var _pass: int = 0
   var _fail: int = 0

   func _init() -> void:
       _run("test_paddle.gd", "Paddle")
       _run("test_neon.gd", "Neon Visual")
       print("\n=== TOTAL: %d passed, %d failed ===" % [_pass, _fail])
       quit(1 if _fail > 0 else 0)

   func _run(path: String, name: String) -> void:
       print("=== %s Tests ===" % name)
       var script = load("res://tests/" + path)
       if script == null:
           print("  SKIP: %s not found" % path)
           return
       var tester = script.new()
       tester.run()
       _pass += tester.passed
       _fail += tester.failed
       print("  %s: %d passed, %d failed" % [name, tester.passed, tester.failed])
   ```

3. **Paddle 测试套件 `test_paddle.gd`：**
   - `extends RefCounted`，公共属性 `var passed: int = 0`, `var failed: int = 0`
   - `func run() -> void` 调用各测试用例
   - `func _assert(c: bool, m: String) -> void` — 仅打印失败
   - 对 Movement 测试（TC-B1~B4），headless 模式下 `Input.is_action_pressed()` 始终返回 false。改为直接验证 `_process(delta)` 的数值计算：创建实例 → 设置 position → 设置 `_process` 中的 `up`/`down` 状态 → 验证结果。最干净的方案是使用 `set_script()` 模式 + 直接调用 `_process(delta)` 方法。
   - 对于 TC-D1/D2（headless 编译），测试套件自身编译通过即证明，无需额外测试代码。

4. **Neon 测试套件 `test_neon.gd`：**
   - 资源文件验证：`load("res://gdscripts/neon_glow.gdshader")` 非 null
   - 配置值验证：读取文件内容 `FileAccess.get_file_as_string()` 或结构验证
   - 脚本编译：`load("res://gdscripts/ball_trail.gd")` 等非 null
   - Manual tests 输出 "MANUAL ONLY: TC10-TC17 — verify in Godot editor"

5. **GDD 章节写作：**
   - `11-PLAYER-PADDLE.md`：提取 DESIGN §1/§2.1/§3/§4/§5
   - `12-NEON-VISUAL.md`：提取 DESIGN §1/§2/§4/§6/§8
   - 更新 `INDEX.md` table 添加两行

6. **验证命令：**
   ```bash
   # 运行所有测试
   godot --path mini-pong/ --headless --script tests/run_tests.gd
   echo "Exit: $?"
   
   # 编译检查（已有 CI）
   godot --path mini-pong/ --headless --quit
   echo "Exit: $?"
   ```

### 关键技术参考

| 问题 | 参考技能 | 模式/章节 |
|------|---------|---------|
| `--script` 模式入口点 | `godot-headless-testing` | Entry Point Contract |
| Node 子类实例化 | `godot-headless-test-patterns` | §Pattern 2 (set_script) |
| class_name 在 `--script` 不解析 | `godot-headless-test-patterns` | §Pattern 1 |
| load() vs preload() | `godot-headless-test-patterns` | §Pattern 3 |
| CI pipe buffer 死锁 | `godot-headless-testing` | Pitfalls §CI pipe buffer |
| 公共属性 `passed`/`failed` | `godot-headless-testing` | Sub-test Runner Convention |
| TSCN 格式验证 | `godot-scene-format` | §7 Ad-hoc Verification |
| `Input.is_action_pressed()` headless 限制 | `godot-headless-testing` | Pitfalls §InputMap |
| `_ready()` 在 `--script` 中不触发 | `godot-headless-testing` | Pitfalls |
| 视觉测试 headless 限制 | `godot-headless-testing` | Full Engine Mode Playthrough Testing |

### 已知风险

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|:------:|:----:|---------|
| Movement 测试中 Input 始终为 false | 高（已验证） | 中 — 无法端到端测试按键 | 改为测试 `_process` 数值逻辑，绕过 Input |
| `set_script()` 后 `@export var` 不可写 | 低 | 中 — paddle.gd 无 `@export`，无影响 | paddle.gd 使用 const + 局部 var，安全 |
| `load()` 返回 null 导致 `_init()` 挂起 | 中 | 高 — 测试永不退出 | 在 `_run()` 中 null-check 再调用 `.new()` |
| `load()` 返回 null 静默跳过测试 | 中 | 中 — 漏测 | 打印 `SKIP: ... not found` 到 stdout |
| CI 中 Godot `--headless --quit` 因无 main scene 挂起 | 高（已知 bug） | 中 | 现有 CI 使用 `continue-on-error: true`；测试使用 `--script` 模式不依赖 main scene |
| TSCN scene 验证在 `--script` 模式不可用 | 低 | 低 | `PackedScene.instantiate()` 在 `--script` 模式可用，已验证 |

### 设计决策记录

| 决策 | 选择 | 理由 |
|------|------|------|
| 测试框架 | 自实现 assert + `extends RefCounted` | 最小依赖，CI 兼容性好；不使用 GUT — 测试规模不需要 |
| Movement 测试策略 | 测试 `_process` 数值逻辑 | headless 中 `Input.is_action_pressed()` 始终 false |
| 套件脚本类型 | `extends RefCounted` | 可 `new()` 实例化，无 SceneTree 依赖 |
| 运行器脚本类型 | `extends SceneTree` | 必须 — `--script` 入口必须是 SceneTree |
| GDD 模板 | 遵循 AGENTS.md 约定 | 模板文件暂不存在，AGENTS.md §GDD 已定义规范 |
| 视觉测试 | 输出 MANUAL ONLY | headless 模式使用 dummy 渲染驱动 |
| 测试文件命名 | `test_paddle.gd` / `test_neon.gd` | 与 run_tests.gd 同目录，matches `--script` 模式的 load() 路径 |

---

## 9. 延续上下文 — GDD 更新指南

本 Issue 的 GDD 更新遵循 AGENTS.md 中定义的增量更新规则：

> **增量更新：** Review agent 在每个 implement PR merge 后，读取 DESIGN doc 的架构决策/常量/数据流，写入对应 GDD 章节。
> **不写入 GDD 的：** 代码 diff、测试用例、实施阶段 — 留在 PRD/DESIGN 中。

由于这两个 PR 绕过了 review agent，本 Issue 手动执行 review agent 的 GDD 更新职责。

**每个 GDD 章节包含：**
- **系统概述** — 一句话定义 + 节点树/组件构成图
- **核心常量** — 代码块，所有 `const` 定义
- **数据流** — 每个关键流程的步骤描述
- **集成点** — 与哪些其他系统交互
- **参数表** — 决策记录表

**不包含：**
- 实现细节（如 `set_script()` 的具体使用方式）
- 测试用例（留在 DESIGN doc）
- Issue 编号、PR 编号
- 实施阶段的决策过程
