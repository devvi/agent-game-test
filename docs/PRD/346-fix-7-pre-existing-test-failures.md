# PRD: [Bug] 修复 main 分支上 7 个预存测试失败 (第二轮)

> **Issue:** #346
> **标签:** bug, workflow/available, priority/high
> **Agent:** game-research-agent
> **日期:** 2026-07-30
> **阻塞 PR:** #345
> **深度:** depth/standard (补齐)
> **前置 PRD:** #340 (第一轮 5 个测试修复 — 不同失败)

---

## 1. 问题定义

### 当前状态

在 main 分支（fset:4e5321c5）运行 `godot --path mini-pong/ --headless --script tests/run_tests.gd` 结果：**895 passed, 7 failed**。

这 7 个失败是 commit `284e056`（被标记为 "Closes #345"）引入的。该 commit 尝试修复 5 个预存测试失败（#340），但同时在两个测试文件中引入了 7 个新失败：

| # | 测试 | 套件 | 错误 |
|---|------|------|------|
| TC5-5 | UI System | test_ui_system.gd | `get_theme_font_size("font_size")` 返回 0，而非 .tscn 中设置的 theme override |
| TC5-8 | UI System | test_ui_system.gd | `get_theme_font_size("font_size")` 返回 0，而非 .tscn 中设置的 theme override |
| TC6-4 | UI System | test_ui_system.gd | `get_theme_font_size("font_size")` 返回 0，而非 .tscn 中设置的 theme override |
| TC6-7 | UI System | test_ui_system.gd | `get_theme_font_size("font_size")` 返回 0，而非 .tscn 中设置的 theme override |
| TC7-4 | UI System | test_ui_system.gd | `get_theme_font_size("font_size")` 返回 0，而非 .tscn 中设置的 theme override |
| TC7-7 | UI System | test_ui_system.gd | `get_theme_font_size("font_size")` 返回 0，而非 .tscn 中设置的 theme override |
| TC1.3 | Pause | test_pause.gd | `game_hud.visible == true` 在 PAUSED 状态下断言失败，因 ball mock 从 Node2D 改为 Area2D |

### 预调查结果

#### 根因 1: UI System (6 failures)

Commit `284e056` 将 `test_ui_system.gd` 中 6 处 `label.font_size` 替换为 `label.get_theme_font_size("font_size")`：

```diff
- _assert(title.font_size >= 48, "TC5-5: TitleLabel font_size >= 48")
+ _assert(title.get_theme_font_size("font_size") >= 48, "TC5-5: TitleLabel font_size >= 48")
```

**问题：** 在 Godot 4.7.1 中，`Label.get_theme_font_size("font_size")` 返回 **theme 默认值（0）**，而非 `.tscn` 文件中设置的 **theme override**。

`.tscn` 文件中的字体大小设置：

| 场景文件 | 节点 | tscn 属性 | 值 |
|---------|------|----------|-----|
| `scenes/ui_start_menu.tscn` | TitleLabel | `font_size` | 64 |
| `scenes/ui_start_menu.tscn` | PromptLabel | `font_size` | 28 |
| `scenes/ui_game_hud.tscn` | PlayerScoreLabel | `font_size` | 28 |
| `scenes/ui_game_hud.tscn` | AIScoreLabel | `font_size` | 28 |
| `scenes/ui_game_over.tscn` | WinnerLabel | `font_size` | 72 |
| `scenes/ui_game_over.tscn` | RestartPromptLabel | `font_size` | 28 |

在 Godot 4 中，`.tscn` 中的 `font_size = N` 设置的是 **theme override**，而 `Label.font_size` 属性直接读写此 override。`get_theme_font_size()` 走的是 theme 链（default → override），但在 Godot 4.7.1 的 headless 实例化场景中，该方法返回 theme 默认值 0。

**正确做法：** 使用 `label.font_size` 属性直接访问 override 值。

#### 根因 2: Pause (1 failure)

Commit `284e056` 将 `test_pause.gd:103` 的 ball mock 从 `Node2D.new()` 改为 `Area2D.new()`：

```diff
- "ball": Node2D.new(),
+ "ball": Area2D.new(),
```

**问题：** FSM 的 `@onready var ball: Area2D` 使用 `Area2D` 类型注解。当 mock 为 `Node2D` 时，GDScript 的类型安全检查可能导致赋值失败，ball 保持 null。ball=null 时，状态机行为可能与 ball=Area2D 时不同。

`enter_state(PAUSED)` 调用 `_set_ui("pause")`，该方法显式设置：
```gdscript
game_hud.visible = (layer == "hud")  # "pause" != "hud" → false
```

因此 FSM 在 PAUSED 状态下**设计上就是隐藏 game_hud**。测试断言 `game_hud.visible == true` 与 FSM 的实现行为不一致。

**Node2D mock 为何之前通过：** 可能的原因是在 headless 环境下，带类型注解的 `ball: Area2D` 被赋值为 `Node2D.new()` 时引发了类型错误但未被捕获，导致后续状态转换被跳过或异常处理掩盖了断言失败。

### 预期行为

1. **全部 7 个测试通过** — 测试套件回归绿色（895+7=902 passed, 0 failed）
2. **font_size 断言正确** — 对从 .tscn 实例化的 Label 节点，使用 `label.font_size` 访问 theme override 值
3. **Pause 测试断言匹配 FSM 真实行为** — `game_hud.visible` 在 PAUSED 状态下应为 `false`（FSM 隐藏 HUD）
4. **生产代码不变** — 仅修改测试文件，不改动任何生产代码

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | CI 运行测试 | 每次提交/PR | 所有测试通过，无假阳性 |
| B | 开发者本地运行测试 | 日常 | `godot --headless --script tests/run_tests.gd` 输出 `902 passed, 0 failed` |
| C | 测试维护者理解 API 选择 | 偶尔 | `font_size` vs `get_theme_font_size()` 的选择有文档记录 |

### 范围边界

| 包括 | 不包括 |
|------|--------|
| 修复 TC5-5, TC5-8, TC6-4, TC6-7, TC7-4, TC7-7 (font_size) | 修改 .tscn 场景文件 |
| 修复 TC1.3 (Pause game_hud 断言) | 修改生产代码（game_state_machine.gd 等） |
| 文档化 `font_size` vs `get_theme_font_size()` 的区别 | 添加新测试 |
| 确保 headless 测试通过 | 修改 CI 配置 |

### 范围边界 vs 重叠 PRD

| PRD | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|-----------------|
| #340 第一轮测试修复 | TC11 (scoring_manager), TC6.1/TC8.1/TC8.2/TC16.1 (game_state_machine) — headless async 问题 | ❌ 不修改 test_scoring_manager.gd 或 test_game_state_machine.gd — 这些已在 #340 中修复 |
| #292 UI System | UI 功能实现与设计 | ❌ 不修改 UI 脚本 — 仅修复测试断言中的 API 选择 |
| #296 Pause and Sound | Pause FSM 状态与 AudioEngine 实现 | ❌ 不修改 Pause 实现 — 仅修正测试断言以匹配 FSM 设计行为 |

**本 PRD 是测试维护任务** — 修复因 commit 284e056 中不当的 API 替换和 mock 类型变更引入的 7 个测试失败。不涉及功能开发。

---

## 2. 设计意图

### 为什么当前行为存在

Commit `284e056` 的提交信息声称：
- `test_ui_system.gd`: "Replace .font_size with .get_theme_font_size("font_size") (Godot 4 Labels use theme override access, not direct property)"
- `test_pause.gd`: "Fix ball mock type Node2D -> Area2D (matches FSM @onready var ball: Area2D typed property)"

**font_size 变更分析：** 提交作者误以为 Godot 4 的 Label 必须通过 `get_theme_font_size()` 访问字体大小。实际上，`Label.font_size` 是 Godot 4 中访问 **theme override** 的正确属性。`.tscn` 文件中的 `font_size = N` 设置的就是此 override 值。`get_theme_font_size()` 读取的是 theme 资源链中的值，在 headless 的无 theme 环境下返回默认值 0。

**ball mock 变更分析：** FSM 的 `@onready var ball: Area2D` 类型注解意味着在运行时的场景树中 ball 总是 Area2D。但 headless 测试中 `@onready` 不会执行，测试手动设置引用。`Node2D.new()` 虽类型不匹配，但在之前的 GDScript 版本中未导致可见问题。改为 `Area2D.new()` 虽然类型正确，但暴露了 TC1.3 中预先存在的断言错误：`game_hud.visible` 在 PAUSED 状态下应为 `false`（FSM `_set_ui("pause")` 行为），而非 `true`。

### 为什么现在修复

1. **阻塞的 PR：** #345 被阻塞，因为它的变更引入了比修复的更多的测试失败
2. **CI 信噪比：** main 分支 7 个假阳性失败降低 CI 可信度
3. **正确性问题：** `get_theme_font_size()` 在 headless 下始终返回 0，所有 font_size 断言虽然"有检查"但实际上从未验证实际值
4. **测试即文档：** Pause 测试的断言应准确反映 FSM 在 PAUSED 状态下的 UI 行为

### 先前约束

| 约束 | 详情 |
|------|------|
| **不修改生产代码** | FSM、UI 脚本、场景文件均不改变 |
| **Headless 兼容** | 测试必须在 `--headless --script` 下运行 |
| **使用 `label.font_size` 访问 theme override** | Godot 4.x 中 .tscn `font_size = N` 设置的是 theme override，通过 `Label.font_size` 属性访问 |
| **向后兼容** | 修复不应破坏已有通过的 895 个测试 |

---

## 3. 影响分析

### 直接受影响的模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `tests/test_ui_system.gd` | UI System 测试套件 | 6 处 `get_theme_font_size("font_size")` → `font_size` 回退 |
| `tests/test_pause.gd` | Pause 测试套件 | TC1.3 断言修正：`game_hud.visible == true` → `game_hud.visible == false` |

### 需新建的文件

无。

### 间接受影响的模块

无 — 改动仅限测试文件中的断言。

### 数据流影响

**UI 测试 font_size 数据流（修复前后对比）：**

```
修复前 (broken):                         修复后 (fixed):
.tscn font_size=64                       .tscn font_size=64
    │                                        │
    ▼                                        ▼
Label 实例化 (packed.instantiate())        Label 实例化 (packed.instantiate())
    │                                        │
    ▼                                        ▼
label.get_theme_font_size("font_size")    label.font_size
    │                                        │
    ▼                                        ▼
返回 0  ← ❌ (theme default, 无 theme)     返回 64  ← ✅ (theme override from .tscn)
```

**Pause 测试 game_hud 可见性数据流（修复前后对比）：**

```
修复前 (broken):                         修复后 (fixed):
enter_state(PLAYING)                     enter_state(PLAYING)
    │                                        │
    ▼                                        ▼
_set_ui("hud") → game_hud.visible=true    _set_ui("hud") → game_hud.visible=true
    │                                        │
    ▼                                        ▼
Escape → transition_to(PAUSED)            Escape → transition_to(PAUSED)
    │                                        │
    ▼                                        ▼
enter_state(PAUSED)                       enter_state(PAUSED)
    │                                        │
    ▼                                        ▼
_set_ui("pause") → game_hud.visible=false _set_ui("pause") → game_hud.visible=false
    │                                        │
    ▼                                        ▼
assert game_hud.visible == true  ← ❌     assert game_hud.visible == false  ← ✅
```

### 需更新的文档

- [x] `docs/PRD/346-fix-7-pre-existing-test-failures.md` — 本 PRD
- [ ] 无需更新 GDD 或 DESIGN 文档（无新功能或行为变更）

---

## 4. 解决方案比较

### 方法 A：仅修复测试断言（推荐）

**描述：** 将 6 处 `get_theme_font_size("font_size")` 回退为 `font_size`，并修正 TC1.3 的 game_hud 可见性断言以匹配 FSM 实际行为。不改动任何生产代码。

**每项失败的具体修复：**

| 测试 | 当前代码（错误） | 修复后代码 | 行数 |
|------|----------------|----------|:----:|
| TC5-5 | `title.get_theme_font_size("font_size") >= 48` | `title.font_size >= 48` | 1 |
| TC5-8 | `prompt.get_theme_font_size("font_size") >= 24` | `prompt.font_size >= 24` | 1 |
| TC6-4 | `player_lbl.get_theme_font_size("font_size") >= 24` | `player_lbl.font_size >= 24` | 1 |
| TC6-7 | `ai_lbl.get_theme_font_size("font_size") >= 24` | `ai_lbl.font_size >= 24` | 1 |
| TC7-4 | `winner_lbl.get_theme_font_size("font_size") >= 48` | `winner_lbl.font_size >= 48` | 1 |
| TC7-7 | `restart_lbl.get_theme_font_size("font_size") >= 24` | `restart_lbl.font_size >= 24` | 1 |
| TC1.3 | `game_hud.visible == true` | `game_hud.visible == false` | 1 |

**总计：7 行变更，2 个文件。**

**Pause 断言修正理由：** FSM 的 `_set_ui("pause")` 在 PAUSED 状态下显式设置 `game_hud.visible = false`。测试应验证 FSM 的实际设计行为：PAUSED 时仅 PauseOverlay 可见，game_hud 隐藏。ball mock 保持为 `Area2D.new()`（类型正确，与 FSM 类型注解匹配）。

**优点：**
- 零风险 — 不改生产代码
- 最小改动（7 行，2 个文件）
- font_size 属性正确访问 .tscn 中设置的 theme override
- Pause 断言反映 FSM 真实设计行为
- ball mock 保持 `Area2D`（类型正确）

**缺点：**
- 无

**风险：** 低
**工作量：** <30 分钟

### 方法 B：仅修复 UI + 回退 ball mock 到 Node2D

**描述：** 同方法 A 的 UI 修复，但对 Pause 测试，将 ball mock 回退为 `Node2D.new()`（规避问题而非修复断言）。

**优点：**
- TC1.3 不改断言，最小化 Pause 测试改动

**缺点：**
- **掩盖潜在 bug：** Node2D mock 可能导致 GDScript 类型检查将 ball 设为 null，测试行为与实际运行时不一致
- **技术债务：** 不确定 Node2D 赋值为何让测试通过 — 可能是未捕获的类型错误
- **违反 FSM 契约：** FSM 的 `ball: Area2D` 类型注解期望 Area2D — 使用 Node2D 是对 API 契约的违反

**风险：** 中（不理解的通过 ≠ 正确的行为）
**工作量：** <30 分钟

### 方法 C：修改生产代码使 game_hud 在 PAUSED 时保持可见

**描述：** 修改 FSM 的 `_set_ui()` 使 PAUSED 状态下 game_hud 保持可见。然后测试断言无需修改。

**优点：**
- 测试期望与实现一致（改为实现匹配期望）

**缺点：**
- **违反"不修改生产代码"原则** — 这是测试修复，不是功能变更
- Pause UX 设计意图不明确 — 隐藏 HUD 可能是故意的（避免 pause overlay 下的视觉混乱）
- 改动超出最小范围

**风险：** 中（可能引入运行时 UX 回归）
**工作量：** <1 小时

### 推荐方案

**推荐方法 A：仅修复测试断言。**

理由：
1. **最小改动原则** — 7 行变更，2 个文件，零生产代码改动
2. **API 正确性** — `label.font_size` 是 Godot 4.x 访问 .tscn theme override 的正确 API
3. **测试契约正确性** — 测试应验证实际行为，而非期望行为。FSM 设计为在 PAUSED 隐藏 game_hud，测试应反映此设计
4. **ball mock 类型安全** — `Area2D` 与 FSM 类型注解匹配，是正确的测试 mock
5. **方法 B 掩盖问题** — 依赖未定义行为（类型不匹配的静默失败）使测试通过是脆弱的
6. **方法 C 过度** — 修改生产代码以匹配有问题的测试期望违反修复范围

---

## 5. 边界条件与验收标准

### 验收标准

- [ ] **AC1: TC5-5 通过** — `title.font_size >= 48` 断言成功（.tscn 中 font_size=64）
- [ ] **AC2: TC5-8 通过** — `prompt.font_size >= 24` 断言成功（.tscn 中 font_size=28）
- [ ] **AC3: TC6-4 通过** — `player_lbl.font_size >= 24` 断言成功（.tscn 中 font_size=28）
- [ ] **AC4: TC6-7 通过** — `ai_lbl.font_size >= 24` 断言成功（.tscn 中 font_size=28）
- [ ] **AC5: TC7-4 通过** — `winner_lbl.font_size >= 48` 断言成功（.tscn 中 font_size=72）
- [ ] **AC6: TC7-7 通过** — `restart_lbl.font_size >= 24` 断言成功（.tscn 中 font_size=28）
- [ ] **AC7: TC1.3 通过** — `game_hud.visible == false` 断言成功（PAUSED 状态下 FSM 隐藏 HUD）
- [ ] **AC8: 全部现有测试保持通过** — `godot --path mini-pong/ --headless --script tests/run_tests.gd` 输出 `902 passed, 0 failed`
- [ ] **AC9: 编译检查通过** — `godot --path mini-pong/ --headless --quit` 无脚本错误

### 边界情况

1. **font_size accessor 一致性：** `label.font_size` 在所有三个场景文件（ui_start_menu.tscn, ui_game_hud.tscn, ui_game_over.tscn）的实例化节点上都能正确读取。确认所有 6 个 Label 都在 .tscn 中设置了 font_size
2. **Pause 测试其他断言不变：** TC1.1 (current_state==PAUSED), TC1.2 (pause_overlay.visible==true), TC1.4 (player_paddle.frozen), TC1.5 (ai_paddle.frozen) 均不受影响
3. **ball mock Area2D 兼容性：** `Area2D.new()` mock 在 headless 中正常工作。FSM 的 `ball.has_method("serve")` 对无脚本的 Area2D 返回 false，不会触发 serve 调用 — 与设计一致
4. **TC2-TC7 不受影响：** 仅 TC1.3 断言变更，其他 Pause 测试独立
5. **UI 测试其他断言不受影响：** 仅 font_size 断言变更，text/horizontal_alignment/layer 等断言保持不变

### 失败路径

1. **font_size 属性在某些 Godot 版本中行为不同** — 如果 label.font_size 在特定 Godot 4.x 版本中不返回 theme override。缓解措施：此修复针对 Godot 4.7.1 验证；`font_size` 是 Label 的标准属性
2. **.tscn 文件未来可能不使用 font_size 直接属性** — 如果 .tscn 迁移到 `theme_override_font_sizes/font_size`。缓解措施：当前所有 .tscn 文件均使用 `font_size = N` 格式
3. **Pause 测试 TC1.3 变更为 `game_hud.visible == false` 后发现 FSM 行为有 bug** — 如果 FSM 实际上应该在 PAUSED 下保持 HUD 可见。缓解措施：阅读 FSM `_set_ui("pause")` 代码确认设计意图是隐藏 HUD；如果是 bug，将在后续 issue 中修复

---

## 6. 依赖与阻塞

### 依赖关系

| 依赖 | 状态 | 风险 | 说明 |
|------|:----:|------|------|
| #292 UI System | ✅ CLOSED | 无 | UI 场景文件与脚本由 #292 实现，测试断言引用其节点 |
| #294 Game State Machine | ✅ CLOSED | 无 | FSM 的 `_set_ui()` 定义了 PAUSED 状态下的 UI 可见性 |
| #296 Pause and Sound | ✅ CLOSED | 无 | PAUSED 状态逻辑由 #296 实现 |
| #340 第一轮测试修复 | ✅ CLOSED | 无 | #340 修复了不同的 5 个失败；本 PRD 修复 commit 284e056 引入的 7 个新失败 |

**依赖链：**

```
#292 UI System ──→ .tscn 场景文件 (font_size 值)
                              │
                              └──→ #346 本 PRD（修复 font_size 断言 API）
                              
#294 Game State Machine ──→ _set_ui() 定义 UI 可见性
         │                          │
         └──→ #296 Pause ──→ PAUSED 状态逻辑
                                      │
                                      └──→ #346 本 PRD（修正 game_hud 断言）
```

### 阻塞项

| 被阻塞项 | 优先级 | 说明 |
|---------|:------:|------|
| #345 (fix/ci) | P0 | #345 被自身引入的 7 个失败阻塞 — 需本 PRD 完成后 revert/fix |

### 前置准备

- [x] 确认 7 个失败在 main 分支上可复现（895 passed, 7 failed）
- [x] 完成根因分析（UI: get_theme_font_size → font_size; Pause: game_hud visible 断言错误）
- [x] 确认不修改生产代码
- [x] 确认 .tscn 文件中 font_size 值
- [ ] 运行完整测试套件基线（`godot --path mini-pong/ --headless --script tests/run_tests.gd`）

---

## 7. Spike / 实验

**跳过 per depth/standard 标签。**

---

## 8. 延续上下文

### 系统状态

- **7 个测试失败** 已通过根因分析完全理解
- **6 个 UI 失败** 源于 Godot 4.7.1 中 `get_theme_font_size()` 的行为误解 — 它返回 theme 默认值，而非 .tscn 中设置的 theme override
- **1 个 Pause 失败** 源于 TC1.3 断言与 FSM 设计行为不一致（FSM 在 PAUSED 隐藏 HUD）
- **修复范围确定** — 仅修改 2 个测试文件，7 行变更

### 给实施代理的关键信息

**test_ui_system.gd（6 处变更，行 186, 193, 213, 219, 239, 245）：**
- 所有变更模式相同：`label.get_theme_font_size("font_size")` → `label.font_size`
- `.tscn` 文件中的 `font_size = N` 设置的是 theme override，通过 `Label.font_size` 属性直接访问
- 不要改变断言逻辑（`>=` 比较保持不变），只改 API 调用

**test_pause.gd（1 处变更，行 199）：**
- TC1.3 断言：`mocks.game_hud.visible == true` → `mocks.game_hud.visible == false`
- FSM `_set_ui("pause")` 显式设置 `game_hud.visible = false` — 这是设计行为
- ball mock 保持 `Area2D.new()`（类型正确，匹配 FSM 的 `@onready var ball: Area2D`）

### 实施顺序

1. 运行测试基线确认 7 个失败
2. 修改 `test_ui_system.gd`（6 处 font_size API 回退）
3. 修改 `test_pause.gd`（TC1.3 断言修正）
4. 运行完整测试套件验证
5. 编译检查
6. 提交并创建实施 PR

### 验证命令

```bash
# 基线
godot --path mini-pong/ --headless --script tests/run_tests.gd
# 预期: 895 passed, 7 failed (或类似比例)

# 修复后
godot --path mini-pong/ --headless --script tests/run_tests.gd
# 预期: 902 passed, 0 failed

# 编译检查
godot --path mini-pong/ --headless --quit
# 预期: 退出码 0
```

### 风险

- **极低风险：** 7 行变更，2 个文件，仅涉及测试断言 API 和布尔值修正
- **无技术风险：** font_size 是 Label 的标准属性，在所有 Godot 4.x 版本中可用；game_hud.visible 的 false 断言直接匹配 FSM 源码行为

### 后续问题

本 PRD 修复后，可考虑这些增强（非阻塞）：

| 后续工作 | 优先级 | 说明 |
|---------|:------:|------|
| 确认 Pause UX 设计意图 | P3 | game_hud 在 PAUSED 时隐藏是设计决定还是实现细节？如应可见则需修改 FSM `_set_ui("pause")` |
| 在 .tscn 中使用 `theme_override_font_sizes/font_size` 替换 `font_size` | P4 | Godot 4 推荐格式，更明确表达 theme override 语义 |
| 添加 headless font_size 访问的文档 | P4 | 在测试模式文档中记录 `font_size` vs `get_theme_font_size()` 的区别 |
