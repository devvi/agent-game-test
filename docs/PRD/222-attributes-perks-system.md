# Research: 属性与Perk系统 — 洞察/共情/坚韧 + Perk机制

> Parent Issue: #222
> Agent: research-agent
> Date: 2026-07-25

---

## 1. Problem Definition

### Current Behavior

项目现有以下与角色状态相关的系统，但**不具有角色属性（Character Attributes）或 Perk 机制**：

1. **StateSystem** (`gdscripts/state_system.gd`) — 三轴心境状态管理器（`hope_despair` -10~+10, `conviction` 0~10, `will` 0~10）。这些是**情绪/心境状态（emotional states）**，随对话选择和叙事事件波动，非角色固有属性。

2. **DialogueConditionEvaluator** (`gdscripts/dialogue_condition_evaluator.gd`) — 条件求值器支持 slider 滑块比较、flag 检查、choice_made 历史、AND/OR/NOT 组合。条件基于 StateSystem 的状态值，无属性（Insight/Empathy/Tenacity）感知。

3. **DialogueBalloon + godot_dialogue_manager** — 对话系统使用 `.dialogue` 文件编写，支持 `using StateSystem` 访问状态，支持 `if StateSystem.hope_despair >= 2` 条件分支和 `do StateSystem.apply_choice(...)` 效果应用。对话分支基于即时状态值，无属性系统参与。

4. **NPCNode** (`gdscripts/npc_node.gd`) — NPC 框架支持 `personality_layers` 基于状态匹配不同的对话版本。NPC 交互后未记录属性增长机制。

5. **SkillCheckManager** — **尚未实现**。PRD #227（检定系统）已定义骰子检定公式（`D20 + attribute_value + hallucination_offset vs difficulty`），但属性系统的输入接口尚未定义——属性名、取值范围、初始值、增长机制均为空白。

6. **Hallucination System** — 叙事管理器（`narrative_manager.gd`）管理幻觉等级（0-10），受场景位置和 hope 值影响。Perk 系统可能影响幻觉抵抗值——目前无玩家侧机制可降低或抵抗幻觉。

**关键缺失：**

- 没有角色属性系统（Insight/Empathy/Tenacity 三个属性的值存储、增长、界面展示）
- 没有 Perk 系统（Perk 定义、解锁条件、效果触发、UI 展示）
- 没有属性增长机制（NPC 交互后如何增长属性）
- 没有属性面板 UI
- 无 Perk 对检定/幻觉抵抗的影响链路
- 属性系统是 PRD #227（检定系统）的前置依赖

### Expected Behavior

一套完整的**属性与 Perk 系统（Attributes & Perks System）**，满足以下核心需求：

1. **3 个基础属性（洞察/共情/坚韧）** — 每个属性值范围 1-10，初始值 1。属性是角色的固有特质，通过 NPC 交互和关键选择增长。

2. **Perk 系统** — 至少 4 个可解锁 Perk，不同故事路线可获得不同 Perk。Perk 提供被动加成（检定加成、幻觉抵抗、对话选项解锁等）。

3. **属性面板 UI** — 简约风格 UI，显示洞察/共情/坚韧三条属性值 + 可用 Perk 点数。

4. **NPC 交互后属性增长** — 与特定 NPC 对话后，玩家可选择增长一个属性（1 点），但不能超过 10。

5. **Perk 影响对话检定结果或幻觉抵抗值** — Perk 提供可感知的游戏效果，让属性感知有意义。

6. **与现有系统兼容** — 属性系统需暴露给 godot_dialogue_manager 的 `using` 接口，供对话条件（`if`）和效果（`do`）使用。同时与 SkillCheckManager（#227 的检定系统）对接。

### User Scenarios

- **Scenario A（核心体验）:** 玩家在游戏中与自己对话选择模式一致地发展角色。与便利店店员深入交流（共情选择）→ 共情值 +1。在天桥与流浪汉对话中敏锐观察细节（洞察选择）→ 洞察值 +1。在压力面前不退缩（坚韧选择）→ 坚韧值 +1。玩家的选择模式定义角色特质。

- **Scenario B（Perk 解锁）:** 玩家走\"共情路线\"（共情值达到 5）后，解锁 Perk \"敏锐直觉\"（Empathic Insight）——对话中自动感知 NPC 的真实情绪。另一个路线的玩家坚韧值达到 7，解锁 Perk \"雨夜行者\"（Night Walker）——幻觉抵抗值 +2。

- **Scenario C（Perk 影响检定）:** 玩家触发洞察检定，洞察值为 6，难度为 12。因拥有 Perk \"冷静头脑\"（Clear Mind），获得 +2 检定加成。最终骰子结果：13（骰子 7 + 洞察 6 + Perk 2 = 15 vs 难度 12 → 成功）。

- **Scenario D（Perk 影响幻觉）:** 玩家场景基础幻觉等级为 7（下城区），因 Perk \"雨夜行者\" 提供幻觉抵抗 +2，实际生效幻觉等级降为 5——幻觉偏移范围缩小，叙事文本更可靠。

- **Frequency:** 属性点增长——每次关键 NPC 对话（MVP 阶段约 5-8 次）。Perk 解锁——属性里程碑（每达到 3/5/7/10 各一次）。Perk 效果——每次检定、每次幻觉等级应用。

### Scope Boundaries vs Overlapping PRDs

| PRD | Covers | NOT covered（留给此 PRD） |
|-----|--------|--------------------------|
| #5 (CRPG 核心机制) | 定义了\"对话即检定\"的概念——状态值区间匹配决定对话分支 | ❌ 无角色属性系统、无 Perk、无属性增长 |
| #47 (GameState 系统) | 三轴状态管理器（hope_despair/conviction/will） | ❌ 心境状态 vs 角色属性是不同的概念层 |
| #214 (叙事架构) | 叙事回声、幻觉系统、结局判定 | ❌ 幻觉系统为高层叙事系统，Perk 影响幻觉抵抗为玩家侧机制 |
| #215 (godot_dialogue_manager 集成) | 替换自定义对话引擎为 godot_dialogue_manager | ❌ 对话引擎无属性系统概念，但需暴露属性接口供对话使用 |
| #227 (检定系统) | 骰子检定公式（D20 + 属性 + 幻觉偏移 vs 难度） | ❌ 定义了检定*如何用属性*，但未定义属性*是什么* |

**此 PRD 是「属性与 Perk 系统」**——聚焦于 3 属性（洞察/共情/坚韧）的定义、增长机制、Perk 定义和解锁、属性面板 UI。它为 #227 的检定系统提供输入接口。它不重新分析心境状态系统（已由 #5/#47 覆盖）、不重新设计对话系统（由 #215 覆盖）、不重新设计 UI 系统（由 #53 覆盖）。

---

## 2. Design Intent

### 为什么当前没有属性/Perk 系统？

项目到目前的系统聚焦于**心境状态（Hope/Despair, Conviction, Will）**——这些是《雨夜普罗摩茨》的叙事核心：玩家的情绪随对话选择波动，世界通过情绪滤镜呈现。心境状态是**短周期变化**的。

但 CRPG 需要**角色特质（Character Traits）**——玩家在游戏中的选择模式塑造的角色能力方向。与心境不同，属性是**长周期积累**的，代表了\"这个玩家是谁\"而非\"这个玩家此刻感觉如何\"。

从 PRD #5（CRPG 核心机制）中可以看到，最初的设计讨论中三轴滑条（希望-绝望/热情-倦怠/信念-动摇）扮演了角色能力的角色。但随着项目演进，这些被实现为心境状态（StateSystem），而角色属性（洞察/共情/坚韧）作为独立的概念层被提出。

### 为什么现在需要属性/Perk 系统？

1. **为检定系统提供输入** — PRD #227 的检定公式 `D20 + attribute_value + hallucination_offset vs difficulty` 需要属性值作为核心输入。没有属性系统，检定无法运行。

2. **为玩家提供长期进展感** — 心境状态的波动（hope 从 5→3→6→4）让玩家感觉\"我的心在变\"，但缺乏\"我的角色在成长\"的成就感。属性增长提供了这种长期进展。

3. **区分心境与特质的概念层** — 心境状态（StateSystem）是**环境/叙事驱动的、短周期的、变化频繁的**。角色属性是**玩家选择驱动的、长周期的、相对稳定的**。两者共存创造了更丰富的角色表达：
   - 玩家可以有\"高洞察但低希望\"（看透了一切但绝望）
   - 或者\"低坚韧但高信念\"（内心坚定但容易被打倒）
   - 这些组合创造了独特的叙事可能性

4. **多周目价值** — 不同的属性分配方向导致不同的 Perk 解锁，产生可重玩的角色配置。

5. **Perk 的叙事意义** — Perk 不仅是数值加成，也是叙事标签。\"你获得了 Perk：雨夜行者\"本身就是一次角色定义时刻。

### 属性 vs 心境状态的概念对比

| 维度 | 心境状态（StateSystem） | 角色属性（本 PRD） |
|------|----------------------|-------------------|
| **范围** | hope_despair -10~+10, conviction 0~10, will 0~10 | 洞察/共情/坚韧 1~10 |
| **变化速度** | 频繁（每次对话可能变化） | 缓慢（每次 NPC 交互 +1） |
| **驱动因素** | 叙事事件、对话选择、环境 | NPC 交互中的选择模式 |
| **方向性** | 双向波动（可升可降） | 单向增长（只升不降） |
| **上限** | 有自然限制（两极抵抗） | 1~10 硬上限 |
| **代表** | 此刻的感受 | 长期的特质 |
| **访问方式** | `StateSystem.hope` / `StateSystem.conviction` | `AttributeSystem.insight` / `.empathy` / `.tenacity` |

### Previous Constraints

| 约束 | 详情 |
|------|------|
| 引擎 | Godot **4.7.1** / GDScript 2.0（静态类型） |
| 渲染器 | `forward_plus` with Glow pass |
| 分辨率 | 1920×1080, Allow HiDPI |
| 主题 | Edward Hopper 都市夜晚 — 暖琥珀色/冷暗色基底 |
| 对话引擎 | godot_dialogue_manager v3.10.5（#215 已合并） |
| 状态系统 | StateSystem（hope_despair -10~+10, conviction 0~10, will 0~10） |
| 检定系统 | PRD #227 定义公式 `D20 + attribute + hallucination_offset vs difficulty`（待实现） |
| 视觉风格 | LoFiText3D（像素化、受限色深、扫描线、自发光）+ Hopper 简约 UI |
| 写作风格 | 海明威约束（25 字符/句，3 句/段限制） |
| 平台 | macOS / Linux |
| 用户输入 | 键盘操作 + 鼠标点击（NPC 交互、UI 导航） |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `gdscripts/attribute_system.gd` | 属性系统管理器 | **新建** — 3 属性 + Perk 存储的核心类，Autoload 注册 |
| `gdscripts/perk_manager.gd` | Perk 管理器 | **新建** — Perk 定义、解锁条件检查、被动效果注册 |
| `scenes/ui/attribute_panel.tscn` | 属性面板 UI 场景 | **新建** — 属性面板 UI（CanvasLayer） |
| `gdscripts/attribute_panel.gd` | 属性面板脚本 | **新建** — 属性面板逻辑（显示、更新、动画） |
| `gdscripts/npc_node.gd` | NPC 框架 | **扩展** — NPC 交互后触发属性增长选择的接口 |
| `gdscripts/state_system.gd` | 状态系统 | **扩展** — 可选：在状态字典中包含属性快照（供对话条件使用） |
| `dialogues/*.dialogue` | 对话文件 | **扩展** — 部分对话中增加属性增长选项（NPC 交互后的选择） |
| `gdscripts/game_manager.gd` | 游戏管理器 | **扩展** — 引用 AttributeSystem autoload，提供 get_attribute() 等委托方法 |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/skill_check_manager.gd` | 检定系统（#227） | 接收 AttributeSystem 作为检定输入，Perk 提供检定加成 |
| `gdscripts/narrative_manager.gd` | 叙事管理器 | Perk 影响幻觉抵抗值（hallucination_level 计算逻辑） |
| `gdscripts/dialogue_condition_evaluator.gd` | 条件求值器 | 可能需要支持属性条件类型（如 `"attribute"` type 替代 `"slider"`） |
| `docs/GAME_DESIGN/05-DIALOGUE.md` | 对话设计文档 | 需更新 NPC 对话中属性增长选择的规范 |
| `gdscripts/status_bar.gd` | 状态栏 | 可能集成属性查看入口 |

### Data Flow Impact

```
[游戏启动]
    ↓
AttributeSystem._ready() → 初始化 3 属性为 1, 0 Perk Points, 0 Perks
    ↓
[NPC 交互完成]
    ↓
AttributeSystem.offer_attribute_growth(npc_id, context)
    ├── 根据 NPC 类型和对话上下文，显示可增长的属性选项
    ├── 玩家选择增长方向 → attribute.insight/empathy/tenacity += 1
    ├── 检查 Perk 解锁条件（里程碑触发）
    └── attribute_changed 信号广播
        ↓
[AttributePanel UI]
    ├── 属性值动画更新（数字渐变动画）
    ├── Perk Point 数量更新
    └── 新 Perk 解锁弹出提示（如已触发）
        ↓
[对话/检定系统接收变化]
    ├── dialogue_condition 可使用 attribute.insight >= 3 条件
    ├── SkillCheckManager 获取 attribute 值进行检定计算
    └── Perk 被动效果（检定加成/幻觉抵抗）自动生效
```

### Documents to Update

- [ ] `docs/PRD/222-attributes-perks-system.md` — **本文档**
- [ ] `docs/GAME_DESIGN/05-DIALOGUE.md` — 添加属性增长选择规范
- [ ] `docs/DESIGN/222-attributes-perks-system.md` — 后续 Plan 阶段输出

---

## 4. Solution Comparison

### Approach A: 独立属性系统管理器 + 对话内增长触发（**推荐**）

**描述：**

新建 `AttributeSystem` 类（扩展 `Node`，注册为 Autoload），作为集中式属性和 Perk 管理器。它封装了三个属性值的存储、增长逻辑、Perk 解锁条件检查、以及 Perk 效果查询。

NPC 交互方面，`NPCNode` 在对话结束后发射信号，`AttributeSystem` 显示增长选择 UI。玩家选择后在 `.dialogue` 文件的 `do` 语句中通过 `using AttributeSystem` 应用增长。

Perk 定义为一个外部资源文件（`.tres` 或 JSON），由 `PerkManager` 加载和管理。`SkillCheckManager` 通过 `AttributeSystem.get_perk_modifier(check_type)` 查询 Perk 加成。

**组件：**
- `AttributeSystem.gd` — Autoload，存储 3 属性、Perk Points、Perk 列表，提供增长/查询/Perk 解锁 API
- `PerkManager.gd` — 可选内部组件，管理 Perk 定义和效果注册
- `AttributePanel.gd` + `attribute_panel.tscn` — CanvasLayer 属性面板 UI
- `AttributeGrowthPrompt.gd` + `attribute_growth_prompt.tscn` — NPC 交互后属性增长选择弹窗

**Pros:**
- **职责清晰** — 属性状态独立于心境状态，概念层分离，长期可维护
- **易于测试** — Autoload 在 headless 模式下可访问，可直接写单元测试验证增长和 Perk 解锁
- **godot_dialogue_manager 兼容** — 通过 `using AttributeSystem` 暴露，对话 DSL 可直接调用 `AttributeSystem.add_attribute_point("insight")` 和 `if AttributeSystem.insight >= 5`
- **与 SkillCheckManager 集成预留** — Perk 加成通过查询接口注入检定系统，低耦合
- **可扩展** — 未来可添加更多属性（如\"直觉\"、\"表达\"）或更多 Perk 而不影响现有接口
- **UI 独立** — 属性面板作为独立 UI 层，可在任何场景显示/隐藏

**Cons:**
- 新增一个 Autoload（增加项目启动 load）
- 需要设计 Perk 定义的数据格式和加载机制

**Risk:** Low — 属性系统的架构与 StateSystem 类似，已验证模式。

**Effort:** Medium（3-5 天）

---

### Approach B: 在 StateSystem 中扩展属性字段

**描述：**

不新建 Autoload，而是在 `StateSystem` 中新增 `insight`, `empathy`, `tenacity` 三个 float 字段。Perk 作为 StateSystem 的 `perks` Array 存储。NPC 交互后直接调整 StateSystem 的属性字段。

**Pros:**
- 无需新增 Autoload（减少 Godot 的 autoload 注册）
- 现有对话条件系统可直接使用属性（`StateSystem.insight >= 5` — 变量名一致）
- StateSystem 已有 save/load 功能，属性/Perk 自动序列化

**Cons:**
- **概念混淆** — 心境状态和角色属性混用同一个类，心智模型不清。`StateSystem` 将来需要区分\"心境值\"和\"属性值\"，命名冲突（`StateSystem.hope` vs `StateSystem.insight` 语义不同）
- **Perk 逻辑膨胀** — Perk 解锁条件检查、Perk 效果查询的逻辑与状态管理混在一起，StateSystem 职责膨胀
- **StateSystem 已超 300 行** — 再添加属性 + Perk 逻辑会使文件难以维护
- **Perk 定义数据格式与 save/load 耦合** — Perk 数据存储在 save 字典中，格式变更影响存档兼容性

**Risk:** Medium — 概念耦合，长期维护成本高

**Effort:** Small（1-2 天）但维护成本高

---

### Approach C: 纯 Dialogue-level 属性系统

**描述：**

不在 GDScript 侧定义属性系统。使用 godot_dialogue_manager 的 `set` 语句在对话文件中管理属性和 Perk。对话条件中内联检查。NPC 交互后通过 `do set $insight = $insight + 1` 增长属性。属性面板通过读取 `DialogueBalloon` 的自定义变量显示。

**Pros:**
- 无需新增任何 GDScript（纯对话 DSL 配置）
- 原型阶段验证速度快

**Cons:**
- 对话文件间的数据共享困难（每个 `.dialogue` 文件的变量作用域有限）
- GodotDialogueManager 的变量存储不持久化（场景切换可能丢失）
- 无 save/load（除非完全通过 StateSystem 代理）
- Perk 效果逻辑无法在 GDScript 中实现（无法挂钩到 SkillCheckManager）
- 不可测试（headless 模式下无法验证 Perk 解锁）
- 严重违反 DRY — 每个对话文件重复编写属性增长逻辑
- 属性面板 UI 无法可靠读取对话变量

**Risk:** High — 对话引擎的变量系统不适合作为持久化角色属性存储

**Effort:** Low（1 天原型）但强耦合对话引擎私有 API

---

### Recommendation

→ **Approach A（独立属性系统管理器 + 对话内增长触发）** 因为：

1. **概念分离** — 心境状态（StateSystem）和角色属性（AttributeSystem）是不同的概念层，用不同的类管理维护了清晰的系统边界
2. **可测试性** — 属性增长、Perk 解锁、Perk 效果可以在 headless 模式下通过 `--script` 测试验证
3. **SRP（单一职责）** — StateSystem 已管理心境状态 + flags + choice_history + save/load，属性/Perk 逻辑不应再膨胀其职责
4. **检定系统集成** — SkillCheckManager（#227）可以通过 `AttributeSystem.get_attributes()` 和 `AttributeSystem.get_perk_modifiers()` 低耦合获取输入
5. **未来扩展性** — 后续可以添加更多属性、Perk 树、重置点数等功能而不影响现有心境状态
6. **Autoload 模式已验证** — StateSystem、GameManager、NarrativeManager 都是 Autoload，AttributeSystem 沿用相同模式

**关键设计决策：**
- AttributeSystem 注册为 Autoload，名称为 `AttributeSystem`
- 属性值通过 `using AttributeSystem` 暴露给 godot_dialogue_manager 对话框
- Perk 定义使用 Resource 文件（`.tres`）或硬编码字典（MVP 阶段硬编码足够）
- Perk 效果通过 `AttributeSystem.get_active_perks()` 查询接口，SkillCheckManager 轮询或订阅信号

---

## 5. Boundary Conditions & Acceptance Criteria

### 5.1 属性定义

| 属性 | 中文 | 英文 | 范围 | 初始值 | 叙事含义 |
|------|------|------|------|--------|----------|
| 洞察 | 洞察 (Insight) | `insight` | 1-10 | 1 | 看透事物本质、察觉隐藏细节。影响：检定成功率、对话中看到隐藏选项 |
| 共情 | 共情 (Empathy) | `empathy` | 1-10 | 1 | 理解他人感受、建立情感连接。影响：NPC 态度、获得额外对话内容 |
| 坚韧 | 坚韧 (Tenacity) | `tenacity` | 1-10 | 1 | 承受压力和痛苦的能力。影响：幻觉抵抗、压力环境下的选择稳定性 |

**属性增长规则：**
- 每次关键 NPC 交互完成后，玩家可选择**一个**属性增长 1 点
- 属性不可超过 10
- 属性不可降低（只单向增长）
- 初始值 1（代表\"有但不突出\"）
- 建议 MVP 阶段每个场景提供 1-2 个属性增长机会（总计约 5-8 次增长机会）
- 部分关键叙事选择也可触发属性增长（如在地下道面对恐惧时选\"面对\"→ 坚韧 +1）

### 5.2 Perk 定义（MVP 阶段至少 4 个）

#### MVP Perk 列表（建议）

| # | Perk 名称 | 中文 | 解锁条件 | 效果 |
|---|-----------|------|----------|------|
| 1 | **Clear Mind** | 冷静头脑 | 洞察 ≥ 3 | 洞察检定 +1 加成 |
| 2 | **Empathic Insight** | 敏锐直觉 | 共情 ≥ 3 | 对话中自动获得 NPC 情绪相关的额外文本 |
| 3 | **Night Walker** | 雨夜行者 | 坚韧 ≥ 3 | 幻觉抵抗值 +2（降低生效的幻觉等级） |
| 4 | **Lucid Gaze** | 清澈目光 | 洞察 + 坚韧 ≥ 8 | 幻觉等级 ≥ 7 时减少跳跃偏移 50% |
| 5 | **Compassionate Heart** | 仁心 | 共情 ≥ 5 | NPC 态度改善一级（获得更多对话选项） |
| 6 | **Unbreakable Will** | 不屈意志 | 坚韧 ≥ 5 | 当 hope_despair ≤ -6 时，检定 +2（绝望中的反弹力） |

**解锁条件类型：**
- **单属性阈值** — `insight >= 3`（最简单的解锁）
- **复合属性阈值** — `insight + tenacity >= 8`（跨属性协同）
- **属性 + 心境状态** — `empathy >= 5 AND StateSystem.hope_despair >= 0`（属性 + 当前状态）
- **属性 + 剧情 flag** — `tenacity >= 5 AND has_flag(\"chatted_with_clerk\")`（属性 + 叙事进度）

**不同路线可获得不同 Perk 的建议：**
- **共情路线**（高共情）：Perk #2（敏锐直觉）、Perk #5（仁心）
- **洞察路线**（高洞察）：Perk #1（冷静头脑）、Perk #4（清澈目光）
- **坚韧路线**（高坚韧）：Perk #3（雨夜行者）、Perk #6（不屈意志）
- **平衡路线**：Perk #4 需要复合条件，鼓励不偏科

### 5.3 属性面板 UI 规范

- **显示内容：** 三条属性条形图 + 属性名称 + 当前值（1-10 数字）+ Perk 点数（如属于该路线的 Perk 已解锁，显示效果描述）
- **风格：** Hopper 简约风格 — 无边框 Panel，半透明背景，LoFiText3D 风格的文字，与 `status_bar.tscn` 视觉一致
- **交互：** 按 `C` 键或通过状态栏入口打开/关闭属性面板
- **定位：** 屏幕右下角或左下角，不遮挡主对话区域
- **属性增长时动画：** 数值从旧值渐变到新值（~0.5 秒），条形图宽度对应变化
- **Perk 解锁弹窗：** 当 Perk 解锁条件刚满足时，在屏幕中央显示 Perk 名称和效果描述（~3 秒自动消失）
- **视觉参考：** 参照 `status_bar.tscn` (1920×1080 布局) 和现有的 `ui_config.gd`

### 5.4 Normal Path

1. 游戏启动 → AttributeSystem 初始化（洞察=1, 共情=1, 坚韧=1, Perk Points=0, Perk 列表空）
2. 玩家与 NPC 开始对话 → DialogueBalloon 正常运行
3. NPC 对话结束（END 节点到达） → DialogueBalloon 触发 `dialogue_ended` 信号
4. NPCNode 收到信号 → 发射 `npc_interacted` + 检查是否触发属性增长机会
5. 属性增长提示弹出 → 显示可增长的属性选项（根据 NPC 类型和对话上下文过滤）
   - 便利店店员（共情关联）：可选择增长洞察或共情
   - 天桥流浪汉（坚韧关联）：可选择增长洞察或坚韧
   - 大厅保安（平衡）：可选增长任意属性
6. 玩家选择 → `AttributeSystem.increase_attribute("empathy")` → empathy 从 2 变为 3
7. 触发 Perk 解锁检查 → `AttributeSystem.check_perk_unlocks()`
8. 如果 empathy == 3 → 符合条件的 Perk #2（敏锐直觉）自动解锁 → Perk 解锁弹窗显示
9. 属性面板实时更新 → 条形图动画、新 Perk 标记、Perk Points 更新
10. 后续检定中 → Perk 效果自动生效（检定加成/幻觉抵抗）

### 5.5 Edge Cases

1. **属性已达上限（10）:** 增长选择时不显示已达上限的属性选项。如果所有属性都达上限，不弹出增长提示。
2. **同时满足多个 Perk 解锁条件:** 按 Perk 优先级依次解锁。如果条件相同（如同为 insight >= 3），按 Perk 定义顺序解锁。
3. **Perk 效果叠加:** 多个 Perk 提供相同类型的加成时，效果叠加（如 Perk A +1 洞察检定 + Perk B +1 洞察检定 = 总计 +2）。
4. **幻觉抵抗溢出:** 幻觉抵抗值使幻觉等级降低到负值 → 钳制为 0。Perk 导致的抵抗不应使幻觉等级低于场景基础值 0。
5. **属性增长选择超时:** 玩家属性增长弹窗显示时，如果 60 秒无操作 → 自动关闭，不增长任何属性（避免游戏卡死）。
6. **Perk 在已有声望路径中冲突:** 不同路线可能解锁同一个 Perk → 第二次解锁不重复添加，显示\"已拥有\"标记。
7. **AttributeSystem 未注册 Autoload（headless 测试）:** 提供空安全的 null 检查，测试使用 mock 提供属性值。
8. **存档/读档:** 属性值和 Perk 列表已序列化到存档。读档后 AttributeSystem 完全恢复。

### 5.6 Failure Paths

1. **godot_dialogue_manager 的 `using` 不支持调用方法:** 如果 `do AttributeSystem.increase_attribute("insight")` 不可用 → 替代方案：在 dialogue 文件中使用 `do StateSystem.set_flag("growth_empathy", true)`，对话结束后由 NPCNode 检查 flag 并调用 AttributeSystem 方法。
2. **属性面板资源未加载（资源缺失）:** 不显示面板，不影响核心游戏。Perk 效果静默生效。
3. **Perk 定义文件未找到（Resource 加载失败）:** 回退到硬编码默认 Perk 列表（MVP 阶段 Perk 直接在代码中定义，不依赖外部文件）。

> 这些直接成为 Plan 阶段的测试用例骨架。

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| #213 — 雨夜普罗摩茨项目骨架 | ✅ CLOSED | Low — 子项目目录结构已建立 |
| #215 — godot_dialogue_manager 集成 | ✅ CLOSED | Low — 对话系统已稳定，`using` DSL 可用 |
| Godot 4.7.1 Autoload 模式 | Stable | Low — StateSystem/GameManager 已验证 |

### Blocks

| Future Work | Priority |
|-------------|----------|
| #227 — 检定系统实现 | P0 — 属性系统是检定系统的输入接口（`D20 + attribute + offset vs difficulty`） |
| Perk 效果在 SkillCheckManager 中的集成 | P1 — Perk 提供检定加成和幻觉抵抗 |
| 终端对话文件的属性增长选项落地 | P1 — 对话作者需在 NPC 对话中添加增长触发点 |
| 多路线 Perk 分配 | P2 — 不同路线 Perk 组合的平衡性验证 |

### Preparation Needed

- [ ] 确定属性系统接口（属性名、类型、范围、增长方法）—— **本文档已定义**
- [ ] 验证 godot_dialogue_manager 的 `using` DSL 是否能调用新增 Autoload（AttributeSystem）的属性
- [ ] 验证 `do AttributeSystem.increase_attribute("insight")` 在 .dialogue 文件中是否可执行
- [ ] 设计属性面板 UI 稿（Hopper 简约风格，~3 种布局方案供选择）
- [ ] 确定 Perk 定义格式（硬编码 vs Resource 文件）
- [ ] 与 PRD #227 协作确认属性→检定系统的接口契约（`get_attributes()` Dictionary 格式）

---

## 7. Spike / Experiment

### 实验 1：Autoload AttributeSystem 在 godot_dialogue_manager 中的可访问性验证

**待回答问题：** 新增的 `AttributeSystem` Autoload 能否在 `.dialogue` 文件中通过 `using AttributeSystem` 被访问？能否读取属性和调用方法？

**方法：**
1. 在 Godot 项目中创建最小 `attribute_system.gd`（仅封装 3 个 int 属性 + `get_attribute()` 方法）
2. 注册 `AttributeSystem` 为 Autoload
3. 在 `.dialogue` 文件中编写测试：`[if AttributeSystem.insight >= 3]` 和 `do AttributeSystem.increase_attribute("insight")`
4. 运行 `godot --headless --quit` 验证无编译错误

**预期结果：**
GodotDialogueManager 的 `using` 语法支持访问任意 Autoload 的属性和方法。`if AttributeSystem.insight >= 3` 作为条件分支可用。`do AttributeSystem.increase_attribute(...)` 作为效果语句可用。

**影响：**
→ 验证通过则确认 Approach A 的对话集成方案可行。如果 `do` 不支持调用方法，回退到 flag 中继方案（NPCNode 检查 StateSystem flag 后调用 AttributeSystem）。

---

### 实验 2：属性面板 UI 的最小可行原型

**待回答问题：** 属性面板 UI 在 1920×1080 分辨率、Hopper 简约风格下，能否在现有 UI 系统（`status_bar.tscn` + `ui_config.gd`）中自然融入？

**方法：**
1. 创建一个 CanvasLayer 场景（`attribute_panel.tscn`），使用 ColorRect + RTLLabel 显示三条属性
2. 设置半透明背景、简约风格（无边框、与 status_bar 一致的字体/配色）
3. 通过 `ui_config.gd` 读取配置，确保视觉一致
4. 用键盘 `C` 键切换显示/隐藏
5. 模拟属性增长动画（数值渐变 + 条形图宽度变化）

**预期结果：**
属性面板可在 2 小时内完成基本原型。视觉风格与现有 UI 一致。Panel 不遮挡主对话区域。

**影响：**
→ 确认 UI 实现难度低。如果发现与现有 UI 风格不兼容，需要在 Plan 阶段调整设计。

---

### 实验 3：Perk 解锁条件评估机制

**待回答问题：** 在 AttributeSystem 中使用什么机制评估 Perk 解锁条件？需要支持单属性阈值、复合属性阈值、属性+mood 组合。

**方法：**
1. 在 AttributeSystem 中定义 Perk 数据格式：`{id, name, effect_desc, condition: Dictionary}`
2. 条件格式参考 `DialogueConditionEvaluator` 的 DSL：`{"type": "attribute", "attr": "insight", "op": "gte", "value": 3}` 和 `{"type": "and", "conditions": [...]}`
3. 每次属性增长后遍历 Perk 列表，检查所有未解锁 Perk 的条件
4. 条件调用 `_evaluate_perk_condition(condition)` 递归求值

**预期结果：**
DialogueConditionEvaluator 的条件 DSL 可以直接复用到 Perk 解锁条件求值。只需新增一种 `"attribute"` 类型替代原有的 `"slider"` 类型。复用条件求值器减少代码重复。

**影响：**
→ 确认 Perk 条件评估机制可复用已有基础设施。无需为 Perk 单独编写条件引擎。

---

### 实验 4：Perk 效果对幻觉抵抗的影响验证

**待回答问题：** Perk \"Night Walker\"（雨夜行者）的幻觉抵抗 +2 效果应如何集成到 `narrative_manager.gd` 的 `get_hallucination_level()` 方法中？

**方法：**
1. 在 `narrative_manager.gd` 的 `get_hallucination_level()` 中添加属性系统查询：`var perk_resist = AttributeSystem.get_hallucination_resistance() if has_attr_system else 0`
2. 公式变为：`hallucination = clampi(base + modifier - perk_resist, MIN, MAX)`
3. 测试不同 Perk 配置下幻觉等级的输出

**预期结果：**
通过一个新 `perk_modifier` 参数传递到 `get_hallucination_level()`，Perk 幻觉抵抗作为额外的减项。无需修改 `narrative_manager.gd` 的核心逻辑。

**影响：**
→ 确认 Perk 对幻觉系统的影响可实现为低侵入式的参数修改。`narrative_manager.gd` 只需增加一行减算。

---

### 实验 5：存档兼容验证

**待回答问题：** 如果玩家从未保存触发 AttributeSystem 的存档，然后升级到包含属性系统的版本，读取旧存档后会怎样？

**方法：**
1. 创建无属性系统的旧存档
2. 在 AttributeSystem Autoload 的 `_ready()` 中检查存档数据中是否有属性值
3. 缺失属性值时使用默认值（所有属性=1，空 Perk 列表）
4. 验证加载后属性系统正常运行

**预期结果：**
旧存档缺失属性字段 → `_from_save_dict()` 中为缺失字段提供默认值。加载后属性系统正常运行，玩家获得默认属性配置。

**影响：**
→ 确认属性系统支持向前兼容。旧存档在升级后自动获得初始化的属性/Perk 配置。

---

## 8. Continuation Context

> *此 Section 是 Plan 阶段的 handoff，记录当前系统状态和下一步起点。*

属性与 Perk 系统是项目中首个**角色特质层**系统，与现有的心境状态系统（StateSystem）互补。当前 StateSystem 管理情绪波动（hope_despair/conviction/will），属性系统管理角色长期特质（insight/empathy/tenacity）。

**当前状态：**
- 对话引擎：✅ 集成完成（godot_dialogue_manager + DialogueBalloon）
- 心境状态系统：✅ 三轴 + 双极 hope_despair（StateSystem，~340 行）
- 属性系统：⏳ 此项（#222，尚未实现）
- Perk 系统：⏳ 此项（#222，尚未实现）
- 检定系统：🔄 设计中（#227，骰子检定公式已定但等待属性输入）
- 幻觉系统：✅ 叙事管理器内置（`get_hallucination_level()` 方法）
- 属性面板 UI：⏳ 尚未实现

**关键设计决策：**
- **架构：** Approach A — 独立 AttributeSystem Autoload + PerkManager（内部组件）
- **属性范围：** 洞察/共情/坚韧 1-10，初始值 1，单向增长
- **Perk 数量：** MVP 至少 4 个（建议 6 个）
- **Perk 解锁条件：** 复用 DialogueConditionEvaluator DSL（单属性阈值、复合条件、属性+心境组合）
- **Perk 效果类型：** 检定加成、幻觉抵抗、对话选项解锁
- **UI 风格：** Hopper 简约风格，与 status_bar 视觉一致
- **增长时机：** NPC 交互后弹出增长选择（根据 NPC 类型过滤可选属性）
- **对话集成方式：** `using AttributeSystem` + `do AttributeSystem.increase_attribute("insight")`
- **存档集成：** 属性/Perk/Perk Points 序列化到存档字典

**主要风险：**
1. godot_dialogue_manager 的 `using` / `do` 是否支持调用带参方法（需 Spike 验证）
2. 属性增长选择的 UI 实现可能与现有视觉主题不完全一致（需 UI 原型调整）
3. Perk 平衡性——多路线 Perk 的数值平衡需要在 Plan 阶段论证
4. 属性系统的 save/load 需要与 StateSystem 的存档协调（建议 AttributeSystem 独立序列化）

**下一阶段（Plan agent）需产出：**
1. `docs/DESIGN/222-attributes-perks-system.md` — 完整设计文档（含 GDScript 类图、数据流、UI 规范）
2. `attribute_system.gd` 骨架代码（3 属性 + Perk 存储 + 增长 API + Perk 解锁）
3. `attribute_panel.tscn` + `attribute_panel.gd` 骨架
4. `attribute_growth_prompt.tscn` + 相关脚本骨架
5. Perk 定义的 Resource 或硬编码数据结构
6. `narrative_manager.gd` 中集成 Perk 幻觉抵抗的修改方案
7. 至少 1 个 NPC 对话文件中增加属性增长触发点的示例
8. `godot --headless --quit --script` 测试脚本验证属性系统 autoload 可用
