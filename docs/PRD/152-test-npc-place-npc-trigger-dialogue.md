# Research: [Feature] Test NPC — Place NPC + Trigger Dialogue

> Parent Issue: #152
> Agent: game-research-agent
> Date: 2026-07-23

---

## 1. 问题定义

### 当前行为

对话引擎（DialogueRunner + DialogueDisplay3D + DialogueParser + ConditionEvaluator）已完成，NPC 框架（NPCNode + NPC.tscn）也已实现，但现有的 NPC 都在场景脚本中硬编码触发逻辑：

| NPC | 场景 | 触发方式 | 当前状态 |
|-----|------|---------|---------|
| 保安 | lobby | Area3D `input_event` → `dialogue_runner.start()` | 硬编码在 lobby.gd |
| Store Clerk | store | Area3D `input_event` → `dialogue_runner.start()` | 硬编码在 store.gd |
| Stranger | lobby/underpass | Area3D `input_event` → `dialogue_runner.start()` | 硬编码 |
| Homeless | bridge | Area3D `input_event` → `dialogue_runner.start()` | 硬编码 |
| 待添加 NPC | street | **尚无 NPC** | 缺失 |

关键问题是：

1. **Street 场景没有任何 NPC** — 玩家进入街道场景时没有任何交互对象
2. **NPC 框架虽然存在但尚未应用于 street 场景** — `NPC.tscn` 组件已经可重用，但 street 场景还没有实例化它
3. **E 键交互通路尚未与 NPC 框架集成** — `e_key_trigger.gd`（EKeyTrigger）和 `player_controller.gd` 的 `interaction_requested` 信号已实现，但 NPCNode 目前使用鼠标点击（`input_event`）而非 E 键
4. **没有端到端的测试 NPC** — 缺少一个简单的、独立的测试 NPC 来验证完整的「接近 → E 键 → 对话 → 对话结束」循环

### 期望行为

在 Street 场景中放置一个测试 NPC，实现完整的交互闭环：

1. **物理存在** — NPC 在街道场景中有明确的 3D 位置（房间坐标）
2. **接近检测** — 玩家走进 NPC 时显示名字标签和交互提示
3. **E 键交互** — 玩家按 E（而非鼠标点击）触发对话
4. **对话展示** — DialogueRunner 加载测试对话 JSON，通过 DialogueDisplay3D 展示
5. **对话推进** — 再次按 E 推进对话或关闭

### 用户场景

- **场景 A（开发者测试）：** 开发者加载 Street 场景，走向 NPC，按 E 看到测试对话，确认对话引擎 + NPC 框架 + E 键交互链路正常工作
- **场景 B（后续 NPC 模板）：** 测试 NPC 成为后续添加 NPC 的参考模板 — 明确的 E 键交互模式，清晰的 NPC.tscn 实例化方式
- **频率：** 每次添加 NPC 时参考。测试 NPC 本身只用于验证，后续可能替换或移除

---

## 2. 设计意图

### 为什么现有行为存在

项目增量构建：最早场景在 NPC 框架（#54）之前完成，因此所有现有 NPC 都使用「场景脚本 + Area3D trigger + input_event」模式。`e_key_trigger.gd`（#151）和 `npc_node.gd`（#54）是独立开发的，尚未在同一个场景中协同工作。

### 为什么现在修改

1. **#149（PlayerController）和 #151（EKeyTrigger）已合并** — E 键交互基础设施就绪
2. **NPC 框架（#54）已合并** — NPCNode + NPC.tscn 就绪
3. **Street 场景是验证的最佳地点** — 线性场景序列中玩家必然经过街道，且 street 脚本简单（62 行），修改风险低
4. **需要端到端验证** — 在走完「接近 → E 键 → 对话」之前，无法确认所有组件协同工作

### 先前约束

| 约束 | 详情 |
|------|------|
| 引擎 | Godot 4.7 / GDScript 2.0 |
| NPC 框架 | NPCNode (`npc_node.gd`) + NPC.tscn (`scenes/components/NPC.tscn`) |
| E 键交互 | EKeyTrigger (`e_key_trigger.gd`) + PlayerController `interaction_requested` 信号 |
| 对话格式 | JSON，由 DialogueRunner 懒加载 |
| 对话显示 | DialogueDisplay3D（billboarded 3D labels）|
| 场景模板 | SceneBase `_instantiate_player()` 自动创建 PlayerController |
| 坐标参考 | Street 场景半径 ~6m（CSGBox3D 道路 12×10）|
| 交互距离 | PlayerController `interaction_range = 2.0m` |
| 街道场景当前 NPC 槽位 | 无 NPC 实例，只有 StoreEntranceTrigger（场景切换用）|
| 写作风格 | Hemingway — 每句 ≤25 字符，每节点 ≤3 句 |

---

## 3. 影响分析

### 直接影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `scenes/street/street.tscn` | Street 场景 | **修改** — 添加 NPC.tscn 实例 + EKeyTrigger 子节点 |
| `dialogues/npc_test.json` | 测试对话 | **新建** — 简单的 2-3 节点测试对话 JSON |
| `gdscripts/street.gd` | Street 场景脚本 | **修改** — 添加少量 E-key → NPC 的连接逻辑 |

### 间接影响模块

| 文件 | 模块 | 原因 |
|------|------|------|
| `gdscripts/npc_node.gd` | NPC 框架 | 可能需要在 NPCNode 中添加 `start_npc_interaction()` 方法以支持 SceneBase 的 E 键回调 |
| `gdscripts/constants.gd` | 常量 | 可添加 `DIALOGUE_NPC_TEST` 常量 |
| `docs/GAME_DESIGN/05-DIALOGUE.md` | GDD | 可记录 E 键 + NPC 框架集成模式 |

### 数据流影响

```
玩家进入 Street 场景
    │
    ├── SceneBase._ready()
    │   ├── _instantiate_player() → PlayerController 创建
    │   └── NPCNode._ready() → 连接 Area3D 信号
    │
    ├── 玩家接近 NPC（< 2.0m）
    │   ├── EKeyTrigger.body_entered(player)
    │   ├── EKeyTrigger 连接到 player.interaction_requested
    │   └── NPCNode VisualName + InteractionPrompt 可见
    │
    ├── 玩家按 E
    │   ├── PlayerController._try_interact()
    │   ├── interaction_requested.emit(EKeyTrigger)
    │   ├── EKeyTrigger.e_key_interacted.emit()
    │   └── → NPCNode / SceneBase 处理 → dialogue_runner.start()
    │
    ├── DialogueRunner 加载 npc_test.json
    │   ├── node_changed → DialogueDisplay3D.on_node_changed()
    │   └── choices_available → DialogueDisplay3D.on_choices_available()
    │
    └── 对话结束
        ├── dialogue_ended → NPCNode COOLDOWN → IDLE
        └── 玩家可重复交互
```

### 需更新的文档

- [ ] **本文档:** `docs/PRD/152-test-npc-place-npc-trigger-dialogue.md`
- [ ] `docs/GAME_DESIGN/05-DIALOGUE.md` — 可选，记录 E 键 + NPC 框架集成模式
- [ ] `docs/GAME_DESIGN/08-PLAYER-CONTROLLER.md` — 可选，更新交互路径

---

## 4. 方案比较

### 方案 A：NPCNode + NPC.tscn + EKeyTrigger 子节点（推荐）

**描述：**

在 Street 场景中实例化 `NPC.tscn`，并在其 `InteractionTrigger` 下添加 `EKeyTrigger` 子节点。NPCNode 负责所有标准 NPC 行为（标签、状态机、cooldown），EKeyTrigger 提供 E 键交互能力。

**场景树结构：**

```
StreetRoot (SceneBase)
├── Environments
│   └── ...（现有对象）
├── InteractionZones
│   ├── StoreEntranceTrigger（现有）
│   └── TestNPC (NPC.tscn 实例)
│       ├── InteractionTrigger (Area3D)
│       │   ├── CollisionShape3D
│       │   └── EKeyTrigger (EKeyTrigger) ← 新增
│       ├── VisualName (Label3D)
│       ├── InteractionPrompt (Label3D)
│       └── CooldownTimer (Timer)
├── SceneManager
└── CanvasLayer
    ├── DialoguePanel (DialogueRunner)
    ├── Dialogue3D (DialogueDisplay3D)
    └── FadeCurtain
```

**对话 JSON (`dialogues/npc_test.json`):**

```json
{
  "entry_node_id": "test_greet",
  "nodes": {
    "test_greet": {
      "speaker": "???",
      "text": "Hey.\\nYou're still here.",
      "choices": [
        {
          "text": "Who are you?",
          "next_node": "test_answer",
          "condition": null,
          "effects": []
        },
        {
          "text": "...",
          "next_node": null,
          "effects": []
        }
      ]
    },
    "test_answer": {
      "speaker": "???",
      "text": "Just a test.\\nNothing more.",
      "choices": [
        {
          "text": "...",
          "next_node": null,
          "effects": []
        }
      ]
    }
  }
}
```

**连接方案：** EKeyTrigger.e_key_interacted → StreetScene 方法 → NPCNode.start_npc_interaction() → DialogueRunner.start()

需在 NPCNode 中添加一个公开方法 `start_npc_interaction()`，复制 `_on_interaction` 的核心逻辑（评估 personality layer、设置 TALKING 状态、调用 dialogue_runner.start()）：

```gdscript
func start_npc_interaction() -> void:
    if not is_interactable():
        return
    evaluate_personality_layer()
    set_state(NPCState.TALKING)
    update_name_label()
    if _dialogue_runner:
        _dialogue_runner.start(dialogue_file, dialogue_id, _greeting_override)
    npc_interacted.emit(name)
```

这样 `EKeyTrigger.e_key_interacted` → `SceneBase._on_player_interaction(target)` → NPCNode 有 `start_npc_interaction()` → 标准对话流程。

**优点：**
- **框架完整** — 所有现有 NPC 功能（标签、状态机、personality layers、cooldown）不变
- **E 键和鼠标点击双路径** — 两种交互方式共存，玩家可任选其一
- **最小化侵入** — 仅往 NPCNode 添加一个方法，street.gd 只需少量连线代码
- **场景树干净** — NPC.tscn 实例 + 一个 EKeyTrigger 子节点，无需额外节点

**缺点：**
- 需要修改 NPCNode（添加一个方法）
- EKeyTrigger 只能通过 `e_key_interacted` 发出信号

**风险：** 低 — 添加一个公开方法 + 少量连线
**工作量：** 小（~1 天：NPCNode 添加方法 + street.tscn 修改 + 测试对话 JSON）

---

### 方案 B：纯 EKeyTrigger + 直连 DialogueRunner

**描述：**

不修改 NPCNode，完全绕过 NPC 框架。在 street 场景中新建一个独立的 Area3D + EKeyTrigger + Label3D，EKeyTrigger 直连 `dialogue_runner.start()`。

**优点：**
- 无需修改 NPCNode
- 完全独立的测试路径

**缺点：**
- **不利用现有 NPC 框架** — 重复实现名称标签、proximity 检测、cooldown、状态机
- **为测试创建一个特殊的「非 NPC」交互点** — 与后续实际 NPC 的实现方式不同
- **验证价值低** — 测试的是 EKeyTrigger + DialogueRunner 链路，不是完整的 NPC 交互

**风险：** 低
**工作量：** 小（~1 天）

---

### 方案 C：仅在 main.gd 中添加 F9 测试对话

**描述：**

在 main.gd（目前已有 F9 触发 bartender 对话）中添加第二种测试对话，不放置物理 NPC。

**缺点：**
- **没有物理 NPC** — 无法测试「接近 NPC → E 键 → 对话」的空间互动循环
- **仅测试对话引擎** — 不测试 NPC 框架、E 键交互、场景集成
- **不符合 Issue #152 的 AC** — 明确要求模型在特定坐标

**风险：** 低
**工作量：** 极小（~0.5 天）

---

### 推荐

→ **方案 A（NPCNode + EKeyTrigger + start_npc_interaction）** 因为：

1. **验证「完整闭环」** — 玩家 → 物理 NPC → E 键 → 对话引擎，所有组件协同工作
2. **利用框架** — 而非绕过它；测试 NPC 成为真正的框架验收测试
3. **最小侵入** — 只需在 NPCNode 中添加 `start_npc_interaction()` 方法，scene.gd 中少量连线代码
4. **可保留或移除** — 测试 NPC 可以作为后续 NPC 的模板，也可在功能完成后轻松移除
5. **验证 E 键 + NPC 集成** — 这是现有代码库中缺失的关键通路

**关键设计决策：**

1. NPCNode 添加 `start_npc_interaction()` 公开方法 — EKeyTrigger/SceneBase 可以无侵入调用
2. NPC 放置在 `InteractionZones/TestNPC` 命名空间下
3. NPC 坐标：`Vector3(4, 0, 0)` — 商店入口附近，玩家必经之处
4. 测试对话 JSON 严格遵循 Hemingway 约束（≤1 句/节点，≤25 字符/句）
5. EKeyTrigger 作为 NPC.tscn 的子节点（非组件原生）— 保持 NPC.tscn 纯框架，E 键交互作为场景级扩展

---

## 5. 边界条件与验收条件

### 正常路径

1. **场景加载：** `street.tscn` 加载 → NPCNode `_ready()` 初始化 → InteractionTrigger 连接 body_entered/body_exited → EKeyTrigger 连接 player.interaction_requested
2. **玩家接近：** 玩家走入 NPC 的 `proximity_distance`（3.0m）→ NPCNode 显示 VisualName（「Test NPC」）+ InteractionPrompt（「⌈Talk⌋」）
3. **玩家按 E：** 玩家在 NPC 的 `interaction_range`（2.0m）内按 E → PlayerController `_try_interact()` → `interaction_requested.emit(EKeyTrigger)` → NPCNode `start_npc_interaction()` → `dialogue_runner.start("res://dialogues/npc_test.json", "npc_test")`
4. **对话展示：** DialogueRunner 加载 JSON → `dialogue_started` 信号 → DialogueDisplay3D `show_dialogue()` → 显示 speaker「???」+ 文本「Hey. You're still here.」
5. **对话推进：** 玩家按 E（在对话模式下路由到 `dialogue_select`）→ 选择当前高亮选项 → 进入下一节点或结束
6. **对话结束：** `dialogue_ended` 信号 → NPCNode `_on_dialogue_ended()` → state = COOLDOWN → 2s 后 → state = IDLE

### AC 验收条件（Issue #152）

- [ ] **AC1:** NPC model（简单 3D 形状 + 标签）放置在 Street 场景的特定坐标
  - NPC.tscn 实例位于 `InteractionZones/TestNPC`
  - 坐标：`Vector3(4, 0, 0)`（商店入口附近）
  - VisualName 标签显示「Test NPC」或「???」
- [ ] **AC2:** Area3D 触发区域围绕 NPC
  - NPC.tscn 原生包含 InteractionTrigger（Area3D + CollisionShape3D）
  - 触发半径与 proximity_distance（3.0m）一致
- [ ] **AC3:** 在 NPC 附近按 E 显示对话文本
  - EKeyTrigger 子节点在 NPC 触发器区域内
  - e_key_interacted 连接到对话启动
  - DialogueRunner 加载 dialogues/npc_test.json
  - DialogueDisplay3D 展示对话
- [ ] **AC4:** 再次按 E 推进或关闭对话
  - 对话模式下 E 路由到 dialogue_select
  - 选择当前选项 → 推进到下一节点
  - 如果当前选项 next_node: null → 对话结束

### 边缘情况

1. **快速重复按 E：** 在 dialogue_active = true 时按 E → 应在对话模式下路由到 dialogue_select，不重复触发 dialogue_runner.start()
2. **对话中走远：** 玩家在对话中走出 EKeyTrigger 范围 → EKeyTrigger 断开 interaction_requested 连接 → 对话继续（已在进行中，不受影响）
3. **Cooldown 期间按 E：** 对话结束后 2s cooldown 内 → NPCNode state = COOLDOWN → is_interactable() 返回 false → E 键不触发对话
4. **场景切换后重新进入：** 玩家离开 Street 再返回 → SceneBase._ready() 重新初始化 → NPCNode 状态回归 IDLE → 可再次交互

### 故障路径

1. **对话文件缺失：** npc_test.json 不存在 → DialogueParser.load_dialogue() 返回 {ok: false} → push_error 但游戏不崩溃
2. **EKeyTrigger 未连接：** 子节点不存在或有命名拼写错误 → get_node_or_null() 返回 null → if 保护，无错误
3. **PlayerController 不在 group「player」中：** EKeyTrigger 的 body_entered 检查 body.is_in_group("player") → 不匹配则不连接

> 这些直接成为 Plan 阶段的测试用例骨架。

---

## 6. 依赖与阻塞

### 依赖项

| 依赖 | 状态 | 风险 |
|------|------|------|
| PlayerController（#149） | ✅ 已合并 | 低 |
| EKeyTrigger E 键交互（#151） | ✅ 已合并 | 低 |
| NPC 框架 NPCNode + NPC.tscn（#54） | ✅ 已合并 | 低 |
| DialogueRunner / DialogueDisplay3D（#52） | ✅ 已合并 | 低 |
| Street 场景（#45） | ✅ 已合并 | 低 |

### 阻塞项

| 阻塞未来工作 | 优先级 |
|-------------|--------|
| 后续 NPC 的 E 键集成模式 | 中等 |
| 测试 NPC 可能被替换为正式 NPC（如 Bartender） | 低 |

### 准备事项

- [x] NPCNode 已实现（`gdscripts/npc_node.gd`）
- [x] NPC.tscn 已存在（`scenes/components/NPC.tscn`）
- [x] EKeyTrigger 已实现（`gdscripts/e_key_trigger.gd`）
- [x] PlayerController 提供 interaction_requested 信号
- [x] Street 场景已就绪（包含 InteractionZones 节点）
- [x] DialogueRunner 完全可用，支持懒加载 JSON
- [x] 对话 JSON 格式已文档化（bartender.json 可作为参考）
- [ ] **待确认：** NPCNode 目前没有 start_npc_interaction() 公开方法 — Plan 阶段需要添加

---

## 7. Spike / 实验（depth/standard 可选）

### 实验 1：NPCNode E 键集成可行性验证

- **待回答问题：** NPCNode 的 `_on_body_entered`（`_player_nearby` 标志）和 EKeyTrigger 的 `body_entered`（`interaction_requested` 连接）是否冲突？
- **方法：** 阅读 NPCNode 和 EKeyTrigger 的 body_entered 逻辑。
  - NPCNode：设置 `_player_nearby = true`，更新标签可见性。
  - EKeyTrigger：连接 `player.interaction_requested`。
  - **两者不冲突** — `_player_nearby` 只控制 UI 可见性，EKeyTrigger 只处理交互信号。
- **结果：** 玩家按 E → `interaction_requested.emit(target)` → `_try_interact()` 从 LIFO 栈中弹出最近的 interactable 对象。EKeyTrigger 在 group "interactable" 中。SceneBase 的 `_on_player_interaction(target)` 检查 `target.start_npc_interaction()`。
- **对方案的影响：** ✅ 确认方案 A 可行。NPCNode 需要 `start_npc_interaction()` 方法。

### 实验 2：测试对话 JSON 的最简结构

- **待回答问题：** 一个满足 Hemingway 约束、合适的测试对话应该有几个节点？
- **方法：** 参考 bartender.json（4 节点，83 行），设计更精简的版本。
- **预期结果：** 2 节点足够：入口问候 + 回应/结束。
- **对方案的影响：** 确认最小结构，对话 JSON 文件约 30-50 行。

### 实验 3：NPC 坐标选择

- **待回答问题：** Street 场景中哪个坐标最适合放置测试 NPC？
- **方法：** 检查 street.tscn 的 CSGBox3D 布局（道路 12×10m），StoreEntranceTrigger 在 Vector3(4.5, 0.5, 1)，玩家从 office 场景进入 street 时的初始位置。
- **预期坐标：** Vector3(4, 0, 0) — 商店入口右侧，玩家到达 street 后必经。
- **对方案的影响：** 低 — 坐标在实现时可在 street.tscn 中微调。

---

## 8. 延续上下文

> *本节是 activeForm 传递给下一个 agent（plan → implement）的手签信息。*

NPC 框架（NPCNode + NPC.tscn）和 E 键交互（EKeyTrigger）目前是**独立存在但未集成**的两个系统。Issue #152 要求将两者在 Street 场景中结合，创建一个端到端的测试 NPC。

Street 场景目前有：
- `InteractionZones/StoreEntranceTrigger`（Area3D）— 通过 `input_event` + 鼠标点击触发到商店的场景切换
- `street.gd` — 场景脚本，62 行，管理环境文本 + 场景切换

需要添加：
1. `NPCNode.start_npc_interaction()` — 一个新的公开方法，可被 EKeyTrigger 或 SceneBase 调用
2. `scenes/street/street.tscn`: `InteractionZones/TestNPC` — NPC.tscn 实例
3. `InteractionTrigger` 下的 `EKeyTrigger` 子节点
4. `dialogues/npc_test.json` — 2 节点测试对话 JSON
5. `street.gd` 中的若干行连线代码

主要风险是 **NPCNode 的原始设计使用 input_event（鼠标点击）**，E 键集成需要在 NPCNode 中添加一个公开方法。如果不想修改 NPCNode，方案 B 可作为回退方案（纯 EKeyTrigger + 直连 DialogueRunner，不经过 NPC 框架），但验证价值较低。

测试 NPC 的坐标建议在 `Vector3(4, 0, 0)`（商店入口右侧，玩家到达 Street 后必然会经过的位置）。建议对话文本用「???」作为 speaker 名以暗示其测试性质。
