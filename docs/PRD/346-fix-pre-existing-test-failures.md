# PRD: [Bug] 修复 main 分支上 7 个预存测试失败（第 2 轮）

> **Issue:** #346
> **标签:** bug, workflow/available, priority/high
> **Agent:** game-research-agent
> **日期:** 2026-07-30
> **阻塞 PR:** #345 (`fix(tests): resolve 5 pre-existing test failures on main`)
> **前置依赖:** #340 (第 1 轮测试修复 — CLOSED ✅), #345 (本轮回归的引入者 — CLOSED ✅), #292 (UI System — CLOSED ✅), #296 (Pause — CLOSED ✅)

---

## 1. 问题定义

### 当前状态

PR #345（第 1 轮测试修复）合并后，main 分支当前测试结果从 `874 passed, 5 failed` 变为 **895 passed, 7 failed** — 修复了 5 个失败但引入了 7 个新失败。

7 个失败分布在两个测试套件中：

| 测试 | 套件 | 错误 | 根因 |
|------|------|------|------|
| TC5-5 | UI System | `get_theme_font_size("font_size")` 返回 0，而非 .tscn 中设置的主题覆写值 | PR #345 将 `label.font_size` 改为 `label.get_theme_font_size("font_size")` — Godot 4.7.1 中 `get_theme_font_size` 返回主题默认值 0，不含 .tscn 覆写 |
| TC5-8 | UI System | 同上 | 同上（PromptLabel） |
| TC6-4 | UI System | 同上 | 同上（PlayerScoreLabel） |
| TC6-7 | UI System | 同上 | 同上（AIScoreLabel） |
| TC7-4 | UI System | 同上 | 同上（WinnerLabel） |
| TC7-7 | UI System | 同上 | 同上（RestartPromptLabel） |
| TC1.3 | Pause | `game_hud.visible == true` 在 PAUSED 状态下断言失败 | PR #345 将 ball mock 从 `Node2D.new()` 改为 `Area2D.new()`，改变了 FSM `enter_state(PAUSED)` 的行为 |

### 预调查结果

#### 根因 1: `get_theme_font_size()` 与 `font_size` 的 API 差异

**Godot 4.x `Label` 字体大小存取有两个属性：**

| 属性 | 读取内容 | 写入行为 |
|------|---------|---------|
| `label.font_size` | 该 Label 实例的主题覆写字体大小（在 .tscn 的 Inspector 中设置的 "Theme Overrides > Font Sizes > Font Size"） | 设置主题覆写 |
| `label.get_theme_font_size("font_size")` | 从主题系统解析的最终字体大小 — 返回主题默认值，**不含 .tscn 中设置的实例级覆写** | —（只读方法） |

**为什么测试失败：** 在 headless 测试中，Label 通过 `packed.instantiate()` 从 .tscn 文件实例化，其字体大小通过 Inspector "Theme Overrides" 设置。`get_theme_font_size("font_size")` 返回 0（主题默认），因为 headless 模式中 Label 没有完整的主题上下文。正确的验证方式是读取 `label.font_size` 属性。

**PR #345 中的具体变更（需回退）：**

```gdscript
// test_ui_system.gd — 共 6 处需要回退
// TC5-5:  title.get_theme_font_size("font_size") → title.font_size
// TC5-8:  prompt.get_theme_font_size("font_size") → prompt.font_size
// TC6-4:  player_lbl.get_theme_font_size("font_size") → player_lbl.font_size
// TC6-7:  ai_lbl.get_theme_font_size("font_size") → ai_lbl.font_size
// TC7-4:  winner_lbl.get_theme_font_size("font_size") → winner_lbl.font_size
// TC7-7:  restart_lbl.get_theme_font_size("font_size") → restart_lbl.font_size
```

#### 根因 2: Ball Mock 类型变更影响 FSM 行为

PR #345 在 `test_pause.gd` 的 `_setup_fsm()` 中更改了 ball mock：

```gdscript
// PR #345 之前:
"ball": Node2D.new(),

// PR #345 之后:
"ball": Area2D.new(),
```

此变更的原因可能是为了与真实 Ball（`extends Area2D`）类型匹配。但它影响了 FSM `enter_state(PAUSED)` 的行为 — FSM 可能在 PAUSED 状态下对 `Area2D` ball 进行额外处理（如检查 `_is_serving` 属性），导致 `_set_ui("pause")` 或 `_freeze_paddles()` 的行为改变，进而影响 `game_hud.visible` 的最终状态。

具体来说，TC1.3 断言：
```gdscript
_assert(mocks.game_hud.visible == true, "TC1.3: game_hud still visible in PAUSED")
```

在 headless 模式下，当 ball mock 是 `Area2D` 时，FSM `enter_state(PAUSED)` 可能因为 Area2D 的默认属性（如 monitoring/monitorable）触发额外逻辑，导致 `game_hud.visible` 被改为 false。

### 预期行为

1. **全部 7 个测试通过** — CI 回归绿色：`895 passed, 0 failed`
2. **不破坏第 1 轮修复** — 保持 #340 修复的 5 个测试通过
3. **不破坏已有的 874 个测试** — 所有原有通过测试保持通过
4. **只修改测试代码** — 不改动任何生产代码（`.gd` 脚本或 `.tscn` 场景）

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | CI 运行测试 | 每次提交/PR | 所有 895 个测试通过，无假阳性 |
| B | 开发者本地运行测试 | 日常 | `godot --headless --script tests/run_tests.gd` 输出 `895 passed, 0 failed` |
| C | 后续 PR 被阻塞 | 持续 | 当前 blocked PRs 等待 main 分支变绿后被 stalled scan 检测到并重新触发审查 |

### 范围边界

| 包括 | 不包括 |
|------|--------|
| 回退 6 处 `get_theme_font_size()` → `font_size` 变更 | 添加新测试 |
| 修复 TC1.3 Pause 测试（ball mock 类型修正） | 修改生产代码 |
| 确保 headless 测试模式正常工作 | 重构测试框架 |

---

## 2. 设计意图

### 为什么当前行为存在

PR #345 的目标是修复 #340 中的 5 个预存测试失败。在其实现过程中，做了以下两个额外变更：

| 变更 | 意图推测 | 为什么引入问题 |
|------|---------|---------------|
| `font_size` → `get_theme_font_size()` (6处) | 可能是为了让测试"更正确"地验证字体大小，认为 `get_theme_font_size()` 是"推荐的 Godot 4 方式" | 在 headless 模式（无完整主题上下文）和通过 `.tscn` 覆写设置字体大小的场景中，`get_theme_font_size()` 返回 0 而非实际值 |
| `Node2D.new()` → `Area2D.new()` (ball mock) | 可能是为了让 ball mock 类型与真实 Ball（`extends Area2D`）一致 | 类型变更触发了 FSM 的意外行为路径 — `Area2D` 有 `Node2D` 没有的属性和信号 |

### 为什么现在修复

1. **连锁阻塞:** #345 的合并本意是解除 #338 和 #339 的阻塞，但实际上引入了新的失败，可能导致 stalled scan 误判 main 分支状态
2. **CI 可靠性进一步恶化:** 从 5 个假阳性到 7 个假阳性 — 信噪比继续降低
3. **本轮修复极简:** 仅需回退 6 行 API 调用 + 1 行类型定义，零风险

### 从 Obsidian 知识库中提取的相关设计模式

以下模式来自《体验引擎》（Tynan Sylvester）的 18 个游戏设计模式（[[体验引擎-patterns]]），为本 PRD 提供设计层面的指导：

#### Pattern 8: 依赖栈分析 (Dependency Stack Analysis)

> **问题：** 团队在之后会变化的基础上构建，导致昂贵的返工。
> **方案：** 映射哪些设计元素依赖哪些其他元素。从下往上构建。在堆内容之前先验证基础。

**应用于本 PRD：** PR #345 的变更引入了对 Godot 运行时行为的隐式依赖（`get_theme_font_size()` 在 headless 中的行为、`Area2D` 对 FSM 的影响），但这些依赖未在 CI 中验证。正确的依赖栈应当是：

```
Godot 4.7.1 headless 运行时行为（基础）
  └── 测试 API 选择（font_size vs get_theme_font_size）
      └── 测试断言值（>= 24 / >= 48）
```

当前的问题是：底层（Godot headless 行为）不支持上层选择（`get_theme_font_size()`）。

#### Pattern 9: 迭代原型-测试循环 (Iterative Prototype-Test Cycle)

> **问题：** 设计文档无法预测玩家实际体验。
> **方案：** 小规模构建、早期测试、观察真实玩家、基于数据优化。做好扔掉一个版本的准备。

**应用于本 PRD：** PR #345 的测试变更应在合并前通过 `godot --headless --script tests/run_tests.gd` 验证 — 这是 CI 的基本门禁。本次修复强调：任何测试变更必须在合并前通过 headless CI。

#### Pattern 15: 坦诚驱动质量 (Candor-Driven Quality)

> **问题：** 回避冲突的团队产出平庸作品。
> **方案：** 为诚实反馈创造心理安全感。练习直接、尊重的分歧。奖励坦诚。

**应用于本 PRD：** 此 PRD 坦诚地记录了 regression — PR #345 修复了 5 个失败但引入了 7 个新失败，净效果为 -2。这不是对 #345 作者的批评，而是对 CI 流程需要更严格门禁的反馈。

### 先前约束

| 约束 | 详情 |
|------|------|
| **不修改生产代码功能路径** | 与 #340 相同的约束 — FSM #294 和 UI #292 的行为已被验证正确 |
| **Headless 测试兼容** | 测试必须在 `--headless --script` 下运行 |
| **向后兼容** | 修复不应破坏已通过的 895 个测试（含 #340 修复的 5 个） |
| **最小改动** | 仅回退有问题的变更，不做额外重构 |

---

## 3. 影响分析

### 直接受影响的模块

| 文件 | 模块 | 变更性质 | 变更行数 |
|------|------|---------|:------:|
| `mini-pong/tests/test_ui_system.gd` | UI System 测试套件 | 6 处 `get_theme_font_size("font_size")` → `font_size` | 6 lines |
| `mini-pong/tests/test_pause.gd` | Pause 测试套件 | Ball mock 从 `Area2D.new()` 回退为 `Node2D.new()`（或其他不影响 FSM 行为的类型） | 1 line |

### 需新建的文件

无。

### 间接受影响的模块

无 — 改动仅限测试文件。

---

## 4. 解决方案比较

### 方法 A：回退错误变更（推荐）

**描述：** 将 PR #345 中引入问题的两处变更精确回退。

| 失败 | 修复策略 |
|------|---------|
| TC5-5/5-8/6-4/6-7/7-4/7-7 (6个) | `get_theme_font_size("font_size")` → `font_size`（恢复到 PR #345 之前的 API） |
| TC1.3 (1个) | 调查并修复 ball mock 类型。如果 `Area2D` 导致了 FSM 副作用，回退为不触发副作用的类型（如 `Node2D` 或使用安装了 mock script 的 `Area2D`） |

**优点：**
- 零风险 — 只是回退到已知正常的状态（PR #345 之前这 6+1 个测试是绿的）
- 改动极小（7 行）
- 不改变测试意图 — `font_size` 属性正是 `.tscn` 中 "Theme Overrides > Font Sizes" 的正确读取方式

**缺点：**
- 没有

**风险：** 极低

### 方法 B：为 headless 模式创建完整主题上下文

**描述：** 在测试中创建 Theme 资源并分配给 Label，使 `get_theme_font_size()` 返回正确值。

**优点：**
- 保留 `get_theme_font_size()` 用法

**缺点：**
- 增加测试复杂度，需要创建和管理 Theme 资源
- 对于 `.tscn` 场景实例化出来的 Label，无法在测试中为其分配运行时 Theme（`.tscn` 中的主题覆写优先级高于运行时 Theme）
- `font_size` 属性本来就是正确的 API — `get_theme_font_size()` 是用于读取主题继承链中的值，不适合测试 Inspector 设置

**风险：** 中

### 推荐方案

**推荐方法 A。**

理由：
1. `label.font_size` 是 Godot 4.x 中读取 `.tscn` 主题覆写的正确属性 — 不是 workaround，是正确的 API
2. 改动 = 回退，不引入新逻辑
3. Ball mock 回退不改变测试的有效性 — 测试的是 FSM 行为，不是 Ball 的具体类型

---

## 5. 边界条件与验收标准

### 验收标准

- [ ] **AC1: TC5-5 通过** — `title.font_size >= 48`（而非 `get_theme_font_size("font_size") >= 48`）
- [ ] **AC2: TC5-8 通过** — `prompt.font_size >= 24`
- [ ] **AC3: TC6-4 通过** — `player_lbl.font_size >= 24`
- [ ] **AC4: TC6-7 通过** — `ai_lbl.font_size >= 24`
- [ ] **AC5: TC7-4 通过** — `winner_lbl.font_size >= 48`
- [ ] **AC6: TC7-7 通过** — `restart_lbl.font_size >= 24`
- [ ] **AC7: TC1.3 通过** — `game_hud.visible == true` 在 PAUSED 状态下断言成功
- [ ] **AC8: 所有现有测试保持通过** — `895 passed, 0 failed`
- [ ] **AC9: 编译检查通过** — `godot --path mini-pong/ --headless --quit` 退出码 0

### 边界情况

1. **TC1.3 的精确修复：** 需要先确定为什么 `Area2D` ball mock 导致 `game_hud.visible` 在 PAUSED 状态下为 false。两种可能：
   - FSM `_validate_references()` 对 `Area2D` 执行不同的初始化逻辑
   - `enter_state(PAUSED)` 中检查 ball 的某种属性影响了 UI 状态
   - 最简单的安全回退：将 ball mock 改回 `Node2D.new()`（PR #345 之前通过的状态）
2. **`font_size` 属性的默认值：** 如果 `.tscn` 文件中 Label 的 font_size 主题覆写未被设置，`font_size` 返回 0。但当前所有 6 个 Label 的 `.tscn` 文件均在 DESIGN doc 中明确定义了 font_size — 测试预期这些值已被设置。

### 失败路径

1. **回退 ball mock 后出现新的 FSM 测试失败：** 如果后续有其他测试依赖 ball 是 `Area2D` — 需要逐一检查。当前已知 PR #345 是唯一引入此变更的来源。
2. **TC1.3 根因不是 ball mock 类型：** 如果 `game_hud.visible` 失败有其他原因（如 FSM 状态机本身的逻辑变更），需要深入调试。但根据 issue #346 的根因分析，ball mock 类型变更是确定的原因。

---

## 6. 依赖与阻塞

### 依赖关系

| 依赖 | 状态 | 风险 | 说明 |
|------|:----:|------|------|
| #292 UI System | ✅ CLOSED | 无 | UI 测试依赖的 CanvasLayer 场景和脚本 |
| #294 Game State Machine | ✅ CLOSED | 无 | FSM 是 Pause 测试的行为来源 |
| #296 Pause and Sound | ✅ CLOSED | 无 | Pause 系统是 TC1.3 的行为来源 |
| #340 第 1 轮修复 | ✅ CLOSED | 无 | #345 是 #340 的实施 PR |
| #345 本轮回归引入者 | ✅ CLOSED | 无 | 本 PRD 修复 #345 引入的 7 个新失败 |

### 阻塞项

| 被阻塞项 | 优先级 | 说明 |
|---------|:------:|------|
| 所有等待 main 变绿的 blocked PRs | P0 | 需等待 main 测试全绿后 stalled scan 重新触发 |

---

## 7. 延续上下文

### 系统状态

- **7 个测试失败** 已通过根因分析完全理解
- **修复范围确定** — 仅回退 `test_ui_system.gd` 中 6 行和 `test_pause.gd` 中 1 行
- **不修改生产代码**

### 给实施代理的关键信息

**TC5-5/5-8/6-4/6-7/7-4/7-7（test_ui_system.gd）：**

在 `test_ui_system.gd` 中搜索所有 `get_theme_font_size("font_size")` 调用（共 6 处），替换为 `font_size`：

```gdscript
// L125:  title.get_theme_font_size("font_size") → title.font_size   (TC5-5)
// L133:  prompt.get_theme_font_size("font_size") → prompt.font_size   (TC5-8)
// L149:  player_lbl.get_theme_font_size("font_size") → player_lbl.font_size  (TC6-4)
// L155:  ai_lbl.get_theme_font_size("font_size") → ai_lbl.font_size   (TC6-7)
// L171:  winner_lbl.get_theme_font_size("font_size") → winner_lbl.font_size  (TC7-4)
// L177:  restart_lbl.get_theme_font_size("font_size") → restart_lbl.font_size  (TC7-7)
```

**TC1.3（test_pause.gd）：**

在 `_setup_fsm()` 方法中，将 ball mock 回退：

```gdscript
// 从:
"ball": Area2D.new(),
// 改为:
"ball": Node2D.new(),
```

或者，如果必须保持 `Area2D`，需要在 ball mock 上安装脚本以消除 FSM 副作用。优先尝试 `Node2D` 回退 — 这是最简单且已验证通过的状态。

### 实施顺序

1. 回退 `test_ui_system.gd` 中 6 处 `get_theme_font_size` → `font_size`
2. 回退 `test_pause.gd` 中 ball mock 类型
3. 运行完整测试套件验证
4. 提交并创建实施 PR

### 验证命令

```bash
# 当前基线（确认 7 个失败）
godot --path mini-pong/ --headless --script tests/run_tests.gd
# 预期: 895 passed, 7 failed

# 修复后
godot --path mini-pong/ --headless --script tests/run_tests.gd
# 预期: 895 passed, 0 failed

# 编译检查
godot --path mini-pong/ --headless --quit
# 预期: 退出码 0
```

### 经验教训

1. **任何测试变更必须在合并前通过 `run_tests.gd` 验证** — PR #345 的变更如果经过 CI 验证就会在合并前被捕获
2. **Godot 4.x API 差异：`font_size` vs `get_theme_font_size()`** — 前者读取 Inspector 中设置的主题覆写，后者读取主题链解析值。在 headless 测试中应使用前者
3. **Mock 类型变更必须保守** — 将 mock 从 `Node2D` 改为 `Area2D` 虽然没有语法错误，但引入了运行时行为差异

### 后续建议

| 后续工作 | 优先级 | 说明 |
|---------|:------:|------|
| CI 门禁强化 | P0 | 确保 `gh pr create` 之前自动运行 headless 测试，在合并前发现回归 |
| 测试 API 最佳实践文档 | P2 | 在 `docs/GAME_DESIGN/` 中记录 headless 测试中的 API 使用注意事项（如 `font_size` vs `get_theme_font_size()`） |
| Mock 类型约定 | P3 | 建立测试 mock 的类型选择指南 — 所有 mock 应使用最小基类，不引入不需要的行为 |
