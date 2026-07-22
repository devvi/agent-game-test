# Research: 对话引擎数据模型 — 节点 + 条件分支

> Parent Issue: #46
> Agent: game-research-agent
> Date: 2026-07-22

---

## 1. Problem Definition

### Current Behavior

项目目前没有对话引擎。当前存在的代码仅限于：

| 文件 | 当前状态 |
|------|---------|
| `gdscripts/main.gd` | 显示 "Hello World" Label，打印 "Main scene ready." |
| `gdscripts/game_manager.gd` | 空骨架 Autoload，仅有 `game_started: bool` 状态 |
| `scenes/main.tscn` | 根 Node + 一个 Label 节点 |

**没有任何对话数据结构、序列化格式或运行时分支逻辑。** 对话系统需要从零构建数据模型层。

Issue #43（项目脚手架）尚未完成实现，因此对话引擎的基础设施（输入映射、音频总线、场景结构）尚未就位。Issue #45（叙事架构）正在进行 research 阶段，定义了场景流程但尚未输出具体数据结构。

### Expected Behavior

实现对话引擎的**数据模型层**，包含以下能力：

1. **对话节点（Dialogue Node）**：一个可序列化的数据结构，表示单段对话文本及其关联选项
2. **多选项分支（Choice Branching）**：每个对话节点可包含多个选项，每个选项可以指向下一个节点
3. **条件谓词（Condition Predicate）**：选项的可见/可用性由运行时计算的条件决定
4. **GameState 感知**：条件系统能读取三组滑条值（希望/绝望、热情/倦怠、信念/动摇）、flags 和历史选择
5. **序列化/反序列化**：对话树可通过 JSON 或嵌套字典格式从资源文件加载

### User Scenarios

- **Scenario A（文案策划）：** 写一段对话 JSON，定义 NPC 的三层文本变体和条件分支，放入 `assets/dialogues/` 目录，对话引擎自动加载
- **Scenario B（玩家）：** 游戏进行到便利店场景，当前希望值 = 3（低希望），店员对话自动匹配「冷漠版本」文本，选项也因信念值不同而过滤
- **Scenario C（开发者）：** 将对话树导出为 JSON → 修改文本 → 重新加载 → 验证对话条件逻辑
- **Frequency：** 每次对话交互（整个游戏的核心交互模式）

---

## 2. Design Intent (Feature)

### Why Does Current Behavior Exist?

项目处于初始化阶段。已完成的 Issues：
- Issue #6 (GitHub #1): Hello World Label — 验证 workflow 跑通，最小代码改动
- Issue #5 (PRD 产出，待 Plan): CRPG 核心机制设计 — 定义了 3 轴滑条系统，但尚未进入实现

对话引擎的数据模型依赖两个前置条件：
1. **GameState 系统定义（Issue #47）**：对话条件系统需要知道 GameState 的 API 结构（滑条范围、flag 类型、历史记录格式）
2. **叙事架构定义（Issue #45）**：对话树的结构需要对应场景流程（Office → Street → Store → Bridge → Underpass）

这两个前置条件都处于 Definition 或 Research 阶段，因此对话数据模型目前无法接地到具体场景内容。

### Why Change Now?

对话引擎是游戏的**核心交互层**。在 CRPG 中，对话不是"点缀"，而是"游戏本身"——每个场景推进、每个 NPC 互动、每个内心独白，都通过对话系统呈现。

根据依赖链（来自 `docs/RAW/game-to-issues-urban-night-walker.json`）：

```
Issue #45 (叙事架构) ─┬─ Issue #46 (对话引擎数据模型) ─┬─ Issue #52 (对话引擎运行时)
                      │                              │
                      ├─ Issue #51 (Hemingway约束)     ├─ Issue #53 (UI 系统)
                      │                              │
                      └─ Issue #50 (状态-世界反馈)      ├─ Issue #54 (NPC 框架)
                                                       └─ Issue #55 (场景序列)
```

Issue #46 是对话系统（#52、#53、#54）和所有场景内容（#55、#56、#58）的前置依赖。

**最关键的时间点：** 当 Issue #43（项目脚手架）和 Issue #47（GameState 系统）实现后，对话数据模型是立即需要的下一个模块。如果不提前设计好这个模型，Plan 和 Implement agent 将无法并行开发其他对话相关功能。

### Previous Constraints

- **引擎**：Godot 4.7.1 / GDScript 2.0（`@export` 属性、信号系统、Resources）
- **语言**：GDScript 2.0（静态类型）
- **对话结构来源**：Issue #45 定义的叙事架构（3 层结构：浅层/中层/深层）
- **状态系统来源**：Issue #5 定义的 3 轴滑条（希望-绝望 / 热情-倦怠 / 信念-动摇）
- **滑条范围**：1-10（每组滑条和 = 10）
- **写作约束**：海明威风格（最大 25 字符/句，最大 3 句/段）
- **序列化格式**：JSON（人类可读写，Godot 内置 `JSON` 类支持）
- **Godot Resource**：也可使用 Godot 原生的 `Resource` 系统（`.tres` / `.res`），但 JSON 更适合外部工具编辑和版本控制 diff

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `gdscripts/dialogue_engine.gd` | Dialogue Engine (新建) | 核心对话数据模型结构体/类定义 |
| `gdscripts/dialogue_condition.gd` | Condition System (新建) | 条件谓词求值器 |
| `gdscripts/dialogue_loader.gd` | Dialogue Loader (新建) | JSON/Resource 文件加载与校验 |
| `assets/dialogues/` | Dialogue data files (新建目录) | 存放 `.json` 对话树文件 |
| `gdscripts/game_state.gd` | GameState (Issue #47) | 需提供条件系统可读的 API |

**核心文件职责划分：**

```
gdscripts/
├── dialogue_engine.gd      ← 对话节点数据类（DialogueNode, Choice, Condition）
├── dialogue_condition.gd   ← 条件谓词定义 + 运行时求值
├── dialogue_loader.gd      ← JSON/Resource → DialogueNode 反序列化
└── game_state.gd           ← (Issue #47) 被条件系统读取，不在此 Issue 修改
```

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/game_state.gd` | GameState | 需要暴露条件系统所需的 API（get_slider, get_flag, get_choice_history） |
| `docs/GAME_DESIGN/INDEX.md` | GDD | 对话系统架构需在后续更新 |
| `docs/DESIGN/` | Design docs | 数据模型层需要被 Plan agent 转化为具体代码 |
| `tests/run_tests.gd` | Test framework | 需要条件系统单元测试 |

### Data Flow Impact

```
对话 JSON 文件 (assets/dialogues/*.json)
    │
    ▼
dialogue_loader.gd — 反序列化 → 校验 → DialogueNode[]
    │
    ▼
dialogue_engine.gd — 运行时持有当前节点
    │                │
    │                ├── 渲染当前文本
    │                ├── 调用 dialogue_condition.gd 过滤可见选项
    │                └── 玩家选择 → 更新 GameState → 切换节点
    │
    ▼
game_state.gd (Issue #47)
    ├── slider_get(SliderType.HOPE) → int
    ├── flag_get(key: String) → bool
    ├── choice_history() → Array[String]
    └── slider_modify(SliderType.HOPE, delta) → void
```

### Documents to Update

- [x] **本次产出:** `docs/PRD/46-dialogue-engine-data-model.md`（本文档）
- [ ] `docs/DESIGN/46-dialogue-engine-data-model.md` — 后续 Plan 阶段输出
- [ ] `docs/GAME_DESIGN/INDEX.md` — 添加对话系统章节
- [ ] `README.md` — 更新项目架构图

---

## 4. Solution Comparison

### Approach A: 纯 JSON 数据驱动 — 嵌套字典对话树

**Description:**

所有对话数据存储在外部 JSON 文件中，运行时通过 `dialogue_loader.gd` 反序列化为 GDScript [Dictionary] 或自定义 Resource。对话节点是轻量级数据类，不包含任何运行时逻辑。条件谓词作为字符串表达式存储，由独立的 `dialogue_condition.gd` 在运行时求值。

**数据结构设计：**

```gdscript
# 核心数据结构 — GDScript 2.0

# 条件谓词 — 基本比较单元
enum Comparator { EQ, NEQ, GT, GTE, LT, LTE, CONTAINS }

# 条件单元：可读取滑块、flag 或历史
# left_operand 决定操作数类型
# 例如: ["hope", "GT", 5] 或 ["flag", "met_stranger", "EQ", true]
struct Condition {
    left_operand: Variant  # "hope" | "vigor" | "conviction" | "flag:<key>" | "choice:<key>"
    comparator: Comparator
    right_operand: Variant  # int | bool | String
}

# 条件集合 — AND/OR 组合
enum ConditionOperator { AND, OR }

struct ConditionSet {
    operator: ConditionOperator
    conditions: Array[Condition]
}

# 一个对话选项
struct Choice {
    text: String              # 选项文字（显示给玩家）
    next_node_id: String      # 选择后跳转到的节点 ID
    condition: ConditionSet   # 可选 — 此选项的可见/可用条件
    effects: Array[Effect]    # 选择后的状态影响
    tags: Array[String]       # 标签（用于历史追踪）
}

# 一个对话节点的状态影响
struct Effect {
    target: String            # "hope" | "vigor" | "conviction" | "flag:<key>"
    delta: Variant            # int (滑条变化) | bool (flag 设置)
}

# 对话节点 — 单段话 + 选项
struct DialogueNode {
    id: String
    speaker: String           # 说话者（"Narrator" | "Clerk" | "Stranger" | "Self"）
    text: String              # 对话文本
    condition: ConditionSet   # 可选 — 此节点的可见条件
    choices: Array[Choice]    # 选项列表
    on_enter: Array[Effect]   # 进入该节点时的状态影响
    tags: Array[String]       # 标签
}
```

**序列化格式（JSON）：**

```json
{
  "dialogue_id": "convenience_store_greeting",
  "nodes": [
    {
      "id": "enter",
      "speaker": "Clerk",
      "text": "欢迎。这么晚了还在外面？",
      "choices": [
        {
          "text": "刚下班，路过买杯咖啡",
          "next_node_id": "coffee_response",
          "effects": [
            {"target": "hope", "delta": 1}
          ],
          "tags": ["told_truth", "showed_fatigue"]
        },
        {
          "text": "随便看看",
          "next_node_id": "browsing",
          "condition": {
            "operator": "AND",
            "conditions": [
              ["vigor", "GT", 4],
              ["flag:daily_coffee_bought", "EQ", false]
            ]
          },
          "effects": [
            {"target": "flag:daily_coffee_bought", "delta": true}
          ],
          "tags": ["chose_avoidance"]
        },
        {
          "text": "（沉默地走向货架）",
          "next_node_id": "silent_browsing",
          "condition": {
            "operator": "AND",
            "conditions": [
              ["vigor", "LTE", 4]
            ]
          },
          "effects": [
            {"target": "hope", "delta": -1},
            {"target": "flag:clerk_noticed_silence", "delta": true}
          ],
          "tags": ["chose_silence"]
        }
      ],
      "on_enter": [
        {"target": "flag:entered_store", "delta": true}
      ],
      "tags": ["first_time"]
    }
  ]
}
```

**Pros:**

- JSON 对文案人员友好：可以用 VS Code 乃至任何文本编辑器直接编辑
- Git diff 清晰：每一行 JSON 的变化都能在 PR 中看到
- 与 Godot 引擎无关：对话数据可以在游戏外编辑，甚至由外部工具生成
- 条件系统独立可测试：`dialogue_condition.gd` 可以单独单元测试
- 支持热加载：修改 JSON 后在游戏中 reload（开发阶段调试方便）

**Cons:**

- JSON 无类型校验：运行时才能发现 JSON 结构错误
- 嵌套深度大：大型对话树文件可能变得冗长
- GDScript struct 不支持序列化：需要手写 `to_dict()` / `from_dict()` 转换方法
- Godot 原生 Resource 系统有更好的编辑器集成（JSON 无）

**Risk:** Low — 项目已有 JSON 使用先例（`docs/RAW/game-to-issues-urban-night-walker.json`），Godot 4.7 的 `JSON` 类稳定

**Effort:** ~3-4 个文件，~250-350 行 GDScript

---

### Approach B: Godot Resource 原生数据模型

**Description:**

使用 Godot 4.7 的 `Resource` 系统定义对话数据结构。每个对话节点是一个 `@tool` 脚本中 `extends Resource` 的自定义资源，支持编辑器内直接编辑。序列化使用 `.tres`（文本）或 `.res`（二进制）格式。

```gdscript
# DialogueNode.gd
@tool
extends Resource
class_name DialogueNode

@export var id: String
@export var speaker: String
@export_multiline var text: String
@export var condition_set: ConditionSet
@export var choices: Array[Choice]
@export var on_enter: Array[Effect]
@export var tags: PackedStringArray
```

**Pros:**

- Godot 编辑器原生支持：Resource 可以在编辑器文件系统面板中创建和编辑
- @export 直接在 Inspector 中编辑对话数据，无需手动写 JSON
- 类型安全：GDScript 编译时验证类型（`PackedStringArray` vs `Array[String]`）
- Resource 继承已实现序列化/反序列化（`save()` / `load()` / `ResourceLoader`）
- 支持子资源嵌套：`ConditionSet` 可以是另一个 Resource

**Cons:**

- 编辑器外部编辑困难：`.tres` 虽然可读但不如 JSON 清晰
- Git 协作困难：多人编辑同一个 `.tres` 文件时 diff 不直观
- 对文案人员不友好：需要在 Godot 编辑器中操作才能编辑对话内容
- Resource 文件可能有编辑器版本兼容问题
- 热加载不如 JSON 直接

**Risk:** Medium — Resource 系统本身稳定，但工作流约束大（所有编辑必须在 Godot 编辑器内完成）

**Effort:** ~3-4 个 Resource 类，~200-300 行 GDScript + 编辑器配置

---

### Approach C: 混合模式 — JSON 编辑 + Godot Resource 运行时

**Description:**

吸取 Approach A 和 B 的优点：对话数据以 JSON 格式存储（方便编辑和版本控制），但在运行时转换为 Godot Resource 对象。提供一个 `dialogue_converter.gd` 工具脚本（`@tool`）在场景加载时将 JSON 编译为 Godot Resource，缓存起来供运行时使用。

**Pros:**

- 结合了 JSON 的编辑便利性和 Resource 的运行时性能
- 开发阶段可以修改 JSON 并热加载
- 发布构建时预编译为 Resource，提升加载速度
- Git diff 友好（JSON 格式）

**Cons:**

- 多了一层转换：增加了代码复杂度和维护负担
- 需要维护 JSON ↔ Resource 的双向映射
- 对于小项目来说过度工程化
- 前两个 Approach 的折中方案两头不讨好

**Risk:** Low-Medium — 额外转换层可能引入 bug

**Effort:** ~5 个文件，~350-500 行 GDScript

---

### Recommendation

→ **Approach A（纯 JSON 数据驱动）** 因为：

1. **文案先行的工作流**：游戏的核心内容是对话文本。文案人员需要能在不打开 Godot 的情况下编辑内容。JSON 是通用格式，VS Code / Vim / 任何文本编辑器都能编辑。
2. **Git 协作**：团队协作时 JSON 的 diff 可读性远高于 `.tres`，代码审查更高效。
3. **热加载调试**：开发阶段可以直接修改 JSON 文件并在运行时重新加载，迭代速度快。
4. **与现有资产兼容**：项目已有 JSON 使用实践（`docs/RAW/`），技能栈一致。
5. **条件系统独立可测**：条件谓词定义在 JSON 中作为字符串/数字数组，`dialogue_condition.gd` 可以脱离 Godot 引擎独立测试。
6. **3 轴滑条系统的 JSON 表达简单直接**：`["hope", "GT", 5]` 比 Godot Resource 中嵌套类实例更清晰。

**但需在 Plan 阶段注意：**
- 需要实现 JSON schema 校验（在 `dialogue_loader.gd` 中）
- 需要实现清晰的错误报告（哪行 JSON 格式不对）
- 对于大型对话树，建议按场景拆分 JSON 文件，而不是一个巨型文件

---

## 5. Boundary Conditions & Acceptance Criteria

### 5.1 条件谓词系统设计

**核心条件类型：**

| 条件类型 | 语法示例 | 语义 |
|---------|---------|------|
| 滑条比较 | `["hope", "GT", 5]` | 希望值 > 5 时条件满足 |
| Flag 检查 | `["flag:met_stranger", "EQ", true]` | `met_stranger` 为 true 时满足 |
| 历史选择 | `["choice:gave_help", "EQ", true]` | 之前选择过 `gave_help` 选项时满足 |
| 滑条区间 | `["hope", "BETWEEN", [3, 7]]` | 希望值在 3~7 之间时满足 |

**条件组合规则 (ConditionSet)：**
- `operator: "AND"` + 条件数组 → 所有条件满足才通过
- `operator: "OR"` + 条件数组 → 任一条件满足即通过
- 支持无限嵌套（`ConditionSet.conditions[]` 可包含子 `ConditionSet`）

**条件求值流程：**
```
输入: ConditionSet + GameState
  1. 如果 ConditionSet.conditions 为空 → 通过（无条件）
  2. 解析每个 Condition 的 left_operand
  3. 从 GameState 读取对应值
  4. 用 Comparator 比较读取值和 right_operand
  5. 按 operator (AND/OR) 组合结果
```

### 5.2 对话节点设计约束

| 属性 | 约束 |
|------|------|
| `id` | 必须唯一，在同一对话文件中不能重复 |
| `speaker` | 至少支持 "Narrator", "Self", "Clerk", "Stranger" 四个值 |
| `text` | 最大 75 字符（25 字/句 × 3 句）；海明威约束在运行时由 #52 强制执行 |
| `choices` | 最少 1 个，最多 4 个（UI 限制） |
| `condition` | 可选 — 缺失表示无条件 |
| `on_enter` | 可选 — 缺失表示无影响 |
| `tags` | 可选 — 用于追踪玩家选择的标签数组 |

### 5.3 序列化/反序列化

**加载流程：**
```
dialogue_loader.gd._load(file_path: String) → DialogueTree | Error

1. FileAccess.open(path, READ) → 读取文件内容
2. JSON.parse_string(content) → 解析为 Dictionary
3. 校验顶层字段（dialogue_id, nodes 存在）
4. 逐个节点校验字段完整性
5. 构建 DialogueNode[] 数组
6. 校验 next_node_id 引用合法性（是否存在对应节点）
7. 返回 DialogueTree 对象
```

**错误处理：**

| 错误类型 | 返回 | 严重程度 |
|---------|------|---------|
| JSON 解析失败 | Error("Invalid JSON syntax") | Fatal — 对话不可用 |
| 缺少必填字段 | Error("Node X missing field 'speaker'") | Fatal |
| next_node_id 指向不存在的节点 | Error("Node X: next_node_id 'Y' not found") | Fatal |
| 条件谓词格式错误 | Error("Node X choice Y: invalid condition format") | Warning — 该选项失效 |
| 条件引用未知键 | Warning("Node X: unknown condition target 'speed'") | Warning — 条件求值时视为 false |

**引用完整性校验：**
- 加载时扫描所有 `next_node_id`，确保每个 ID 在节点列表中可找到
- 如果有 `condition`，校验其格式
- 如果有 `effects`，校验 `target` 字段（必须是 `hope` / `vigor` / `conviction` 或以 `flag:` 开头）

### 5.4 Acceptance Criteria

#### AC1: 对话节点支持多选项分支与条件谓词

**验收条件：**
- [x] 对话节点数据结构包含 `choices: Array[Choice]`
- [x] 每个 `Choice` 包含 `text`, `next_node_id`, `condition` (可选)
- [x] `condition` 支持滑条比较（`["hope", "GT", 5]`）
- [x] `condition` 支持 Flag 检查（`["flag:met_stranger", "EQ", true]`）
- [x] `condition` 支持之前选择追踪（`["choice:gave_help", "EQ", true]`）
- [x] 条件系统支持 AND/OR 组合多个条件
- [x] 无条件选项总是可见

**验证方法：**
- 创建测试 JSON 对话文件，包含 1 个节点 + 3 个选项（1 个无条件、1 个有条件满足、1 个有条件不满足）
- 在测试中手动设置 GameState，验证只有符合条件的选项出现

#### AC2: 条件可读取希望/绝望滑条、Flags 和之前选择

**验收条件：**
- [x] 条件可以读取 `hope` 滑条值（范围 1-10）
- [x] 条件可以读取 `despair` 等价映射（hope 的反向）
- [x] 条件可以读取 `vigor` / `conviction` 滑条值
- [x] 条件可以读取任意 `flag:<key>` 布尔值
- [x] 条件可以读取 `choice:<tag>` 是否曾被选择
- [x] 支持的比较器: EQ, NEQ, GT, GTE, LT, LTE, BETWEEN, CONTAINS

**验证方法：**
- 单元测试覆盖每个条件类型 + 每个比较器
- 边界值测试（GT 5：测试 5 不通过、6 通过）

#### AC3: 从资源文件序列化/反序列化对话

**验收条件：**
- [x] 从 `assets/dialogues/test_dialogue.json` 加载对话树
- [x] 加载后正确解析所有节点和选项
- [x] 反序列化结果可以导航（`get_node("enter")` 返回对应节点）
- [x] 文件缺失时返回错误（不崩溃）
- [x] JSON 格式错误时返回具体错误信息

**验证方法：**
- 创建 3 个测试 JSON 文件：1 个合法、1 个格式错误、1 个缺失字段
- 运行 `dialogue_loader.gd` 测试函数，验证结果正确性

### 5.5 Normal Path

1. 游戏启动 → `dialogue_loader.gd` 加载场景对应的 JSON 对话文件
2. 校验 JSON 格式和引用完整性 → 构建 DialogueNode[] 索引
3. 进入对话 → `dialogue_engine.gd` 获取当前节点 → 渲染文本
4. `dialogue_condition.gd` 遍历当前节点的选项 → 读取 GameState → 过滤可见选项
5. 玩家看到符合条件的选项 → 选择 → `effects` 应用到 GameState → 跳转 next_node_id
6. 如果 next_node_id 为空 → 对话结束

### 5.6 Edge Cases

1. **条件引用未知字段：** 如果 `condition` 引用了不存在的滑条或 flag（如 `["speed", "GT", 5]`），条件求值返回 `false`，打印 warning，不崩溃
2. **循环引用：** `next_node_id` 指向自己的父节点形成循环 → 这不是数据模型层问题，由运行时 (#52) 的步数限制防止死循环
3. **空选项列表：** 如果节点的所有选项都被条件过滤掉 → 自动添加一个"继续"选项（无条件，指向 null，结束对话）
4. **超大文件：** 单 JSON 文件若超过 500KB → `dialogue_loader.gd` 应能处理（Godot `JSON.parse_string` 的容量上限远超此值）
5. **节点 ID 冲突：** 同一对话文件中两个节点 ID 相同 → 加载时检测并报错
6. **缺失 speaker：** 如果 speaker 字段缺失 → 默认使用 "Narrator"，打印 warning

### 5.7 Failure Paths

1. **JSON 文件缺失：** `assets/dialogues/scene_xx.json` 不存在 → 返回 Error → 游戏不崩溃，但该场景不触发对话
2. **JSON 解析失败：** 文件编码问题或语法错误 → 返回带行号/位置信息的 Error
3. **引用断裂：** 某个 `next_node_id` 引用了不存在的节点 → 加载时检测到并报错
4. **条件谓词格式错误：** `["hope"]` 只有 1 个元素，非 [operand, comparator, value] → 加载时检测并 warning，该选项视为无条件

> These directly become test case skeletons in Plan phase.

### 5.8 完整示例场景 — 便利店收银台对话

**场景：** 玩家进入便利店，走到收银台。当前状态值：
- 希望 = 3（低希望）
- 热情 = 6（中高）
- 信念 = 4（开始动摇）
- flag: entered_store = false（第一次进入）

**对话文件（`assets/dialogues/convenience_store.json`）：**

```json
{
  "dialogue_id": "convenience_store",
  "nodes": [
    {
      "id": "enter",
      "speaker": "Clerk",
      "text": "欢迎。这么晚了还在外面？",
      "condition": {
        "operator": "AND",
        "conditions": [
          ["hope", "GT", 5]
        ]
      },
      "choices": [
        {"text": "刚下班", "next_node_id": "coffee_talk", "effects": [{"target": "hope", "delta": 1}], "tags": ["chose_honest"]},
        {"text": "睡不着", "next_node_id": "sleepless_talk", "effects": [{"target": "vigor", "delta": -1}], "tags": ["chose_sleepless"]}
      ],
      "on_enter": [{"target": "flag:entered_store", "delta": true}],
      "tags": ["first_meet"]
    },
    {
      "id": "enter",
      "speaker": "Clerk",
      "text": "……又来买咖啡？",
      "condition": {
        "operator": "AND",
        "conditions": [
          ["hope", "LTE", 5]
        ]
      },
      "choices": [
        {"text": "嗯，加班", "next_node_id": "coffee_talk", "effects": [{"target": "hope", "delta": -1}], "tags": ["chose_fatigue"]},
        {"text": "……（点头）", "next_node_id": "silent_coffee", "effects": [{"target": "hope", "delta": -2}], "tags": ["chose_silence"]},
        {"text": "不是，我——", "next_node_id": "denial_talk", "condition": {"operator": "AND", "conditions": [["vigor", "GT", 5]]}, "effects": [{"target": "conviction", "delta": 1}], "tags": ["chose_defiance"]}
      ],
      "on_enter": [{"flag": "entered_store", "delta": true}],
      "tags": ["first_meet"]
    },
    {
      "id": "coffee_talk",
      "speaker": "Clerk",
      "text": "咖啡机刚洗了。",
      "choices": [
        {"text": "……那算了", "next_node_id": "farewell", "effects": [{"target": "hope", "delta": -1}], "tags": ["chose_give_up"]},
        {"text": "有茶吗？", "next_node_id": "tea_talk", "effects": [{"target": "hope", "delta": 1}], "tags": ["chose_adapt"]}
      ]
    },
    {
      "id": "silent_coffee",
      "speaker": "Clerk",
      "text": "……",
      "choices": [
        {"text": "（放下钱，离开）", "next_node_id": "farewell", "effects": [{"target": "hope", "delta": 0}], "tags": ["chose_quiet_leave"]}
      ]
    },
    {
      "id": "sleepless_talk",
      "speaker": "Clerk",
      "text": "都一样。",
      "choices": [
        {"text": "你也是？", "next_node_id": "clerk_story", "effects": [{"target": "hope", "delta": 1}], "tags": ["chose_empathy"]},
        {"text": "……嗯", "next_node_id": "farewell", "effects": [{"target": "hope", "delta": 0}], "tags": ["chose_retreat"]}
      ]
    },
    {
      "id": "denial_talk",
      "speaker": "Clerk",
      "text": "？",
      "choices": [
        {"text": "我不是来买咖啡的", "next_node_id": "clerk_story", "effects": [{"target": "conviction", "delta": 1}], "tags": ["chose_truth"]},
        {"text": "……算了", "next_node_id": "farewell", "effects": [{"target": "hope", "delta": -1}], "tags": ["chose_retreat"]}
      ]
    },
    {
      "id": "tea_talk",
      "speaker": "Clerk",
      "text": "只有袋泡茶。",
      "choices": [
        {"text": "行", "next_node_id": "clerk_story", "effects": [{"target": "hope", "delta": 1}], "tags": ["chose_accept"]},
        {"text": "那算了", "next_node_id": "farewell", "effects": [{"target": "hope", "delta": -1}], "tags": ["chose_reject"]}
      ]
    },
    {
      "id": "clerk_story",
      "speaker": "Clerk",
      "text": "我以前也做游戏的。",
      "choices": [
        {"text": "……", "next_node_id": "farewell", "effects": [{"target": "hope", "delta": 1}], "tags": ["chose_connection"]},
        {"text": "现在呢？", "next_node_id": "farewell", "effects": [{"target": "hope", "delta": 2}], "tags": ["chose_deeper_connection"]}
      ]
    },
    {
      "id": "farewell",
      "speaker": "Clerk",
      "text": "走好。",
      "choices": []
    }
  ]
}
```

**预期运行时行为（希望 = 3 时）：**

1. 加载 —— `dialogue_loader` 解析 JSON，构建节点索引
2. 进入 `enter` 节点 —— 两个 `enter` ID 相同但条件不同：
   - 第一个 `enter`：condition 要求 `hope > 5` → 希望=3 → 不通过，跳过
   - 第二个 `enter`：condition 要求 `hope <= 5` → 希望=3 → 通过，使用此版本
3. 显示：「……又来买咖啡？」
4. 选项过滤（信念=4，热情=6）：
   - "嗯，加班"（无条件）→ 可见
   - "……（点头）"（无条件）→ 可见
   - "不是，我——"（condition: vigor > 5 → 6>5 → 通过）→ 可见
5. 玩家选择 → 应用 effects → 跳转 next_node_id

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| Issue #43 — 项目脚手架 | `workflow/research` | High — 如果脚手架延迟，对话数据模型无法对接输入/场景系统 |
| Issue #45 — 叙事架构 | `workflow/research` | Medium — 对话树结构需对齐场景流程定义，但数据模型本身可先独立设计 |
| Issue #47 — GameState 系统 | `workflow/backlog` | High — 条件系统直接依赖 GameState 的 API（slider_get, flag_get, choice_history） |
| GDScript 2.0 struct/class 支持 | Stable | Low — Godot 4.7 原生支持静态类型 |

### Blocks

| Future Work | Priority |
|-------------|----------|
| Issue #52 — 对话引擎运行时 + 视觉呈现 | P0 — 直接依赖本 Issue 的数据模型 |
| Issue #53 — UI 系统 | P0 — 需要对话引擎的数据接口才能设计选择列表 UI |
| Issue #54 — NPC 框架 + 便利店店员 | P0 — NPC 对话直接使用本 Issue 的数据模型 |
| Issue #56 — 神秘陌生人 NPC | P0 — 依赖 NPC 框架 + 对话数据模型 |
| Issue #55 — Office → Store 场景 | P0 — 场景内容需要对话数据模型驱动 |
| Issue #58 — 故事内容 | P1 — 所有对话文本放在 JSON 文件中 |

### Preparation Needed

- [ ] Issue #43 (Project Scaffold) 完成实现（输入映射、场景结构）
- [ ] Issue #45 (Narrative Architecture) 完成 research，输出场景流程定义
- [ ] Issue #47 (GameState System) 完成实现，暴露条件系统所需 API
- [ ] 确定 JSON 文件的存放目录：`assets/dialogues/`
- [ ] 确定 JSON schema 校验方案：纯手动校验（Plan 阶段）vs JSON Schema 库（Implement 阶段）

---

## 7. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*
> *It captures the current state of the feature area so the next agent can pick up*
> *without re-scanning all source files.*

对话引擎数据模型目前处于设计定义阶段。项目的核心机制（3 轴滑条系统）已在 PRD #5 中定义，但尚未实现任何 GameState 代码。`gdscripts/game_manager.gd` 仍是最小 Autoload（仅 15 行）。

现有代码结构：
- **`gdscripts/main.gd`**（7 行）— 仅显示 Hello World Label
- **`gdscripts/game_manager.gd`**（15 行）— 空 Autoload，`game_started: bool`
- **`scenes/main.tscn`** — 根 Node + Label
- **`docs/PRD/5-crpg-core-mechanics.md`** — 定义了 3 轴机制设计（希望-绝望 / 热情-倦怠 / 信念-动摇），对话检定为"状态值区间匹配"而非传统分支树

提案采用 Approach A（纯 JSON 数据驱动），核心设计为：

1. `DialogueNode` — 包含 id, speaker, text, condition, choices[], on_enter[], tags[]
2. `Choice` — 包含 text, next_node_id, condition, effects[], tags[]
3. `ConditionSet` — AND/OR 组合的 `Condition[]`，每个 Condition 为 [operand, comparator, value]
4. `Effect` — 目标 (`hope`/`vigor`/`conviction`/`flag:<key>`) + 变化值
5. 序列化格式：JSON（每个场景一个独立文件，放在 `assets/dialogues/`）
6. 反序列化在 `dialogue_loader.gd` 中完成，包含引用完整性校验

主要风险：
- **JSON 无类型校验**：需要在加载器中实现严格的错误报告，不能运行时才暴露格式错误
- **GameState API 尚未定义**：条件系统假设 GameState 有 `get_slider(type)`, `get_flag(key)`, `has_chosen(tag)` 三个方法，Plan 阶段需要确认这些 API 签名
- **同 ID 多条件节点**：示例中同一场景有不同的条件变体（`enter` 节点有两个版本，按希望值区间选择），这个模式需要在数据模型层有明确约定（加载时按条件排序，运行时选择第一个条件通过的版本）

**下一阶段（Plan agent）需产出：**
1. `docs/DESIGN/46-dialogue-engine-data-model.md` — 对应 PRD 的详细设计文档
2. `gdscripts/dialogue_engine.gd` — DialogueNode / Choice / Condition 数据类定义
3. `gdscripts/dialogue_condition.gd` — Condition 解析 + 求值器
4. `gdscripts/dialogue_loader.gd` — JSON 加载 + 校验 + 引用完整性检查
5. `assets/dialogues/` 目录 + 一个最小测试对话 JSON 文件
6. `tests/` 中的条件系统和加载器单元测试
7. 明确 GameState API 签名约定（与 Issue #47 对齐）
