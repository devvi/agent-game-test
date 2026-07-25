# Research: 检定系统 — 属性对比 + 骰子检定的叙事分支机制

> Parent Issue: #227
> Agent: game-research-agent
> Date: 2026-07-25

---

## 1. Problem Definition

### Current Behavior

项目当前已有以下与"检定"相关的系统，但均为**条件门控（Conditional Gating）而非骰子检定（Dice Roll Check）**：

1. **DialogueConditionEvaluator** (`gdscripts/dialogue_condition_evaluator.gd`) — 纯静态条件判断：检查滑块值、Flag 状态、历史选择。条件固定返回 true/false，无随机性。

2. **DialogueRunner / godot_dialogue_manager** — 对话分支基于条件求值选择可见分支。玩家看到的选项由当前状态决定，无需掷骰。

3. **StateSystem** (`gdscripts/state_system.gd`) — 三轴状态管理器（hope_despair -10~+10, conviction 0~10, will 0~10）。无属性系统（洞察/共情/坚韧），无随机数接口，无检定结果处理。

4. **场景脚本**（`office.gd`, `lobby.gd`, `street.gd`, `store.gd` 等）— 所有对话通过 `_show_dialogue_balloon()` 启动，使用 godot_dialogue_manager 运行时。目前无任何检定触发点。

5. **NPC 对话文件**（`dialogues/*.dialogue`）— 条件分支依赖静态状态对比，无骰子检定节点。

**关键缺失：**

- 没有骰子系统（D20 / D100 / 自定义骰子）
- 没有属性对比（属性值 + 骰子结果 vs 难度值）
- 没有检定结果的分支路由（成功→分支A，失败→分支B）
- 没有检定UI视觉反馈（成功/失败动画差异）
- 没有幻觉等级（Hallucination Level）对随机性的影响

### Expected Behavior

一套完整的**检定系统（Skill-Check System）**，满足以下核心需求：

1. **属性对比检定** — 玩家的属性值（洞察/共情/坚韧，来自 Issue #222）+ 骰子结果 ≥ 难度值 = 成功；否则失败
2. **检定失败不阻塞流程** — 失败走不同叙事分支（非 Game Over / 非死锁）
3. **检定UI视觉反馈** — 成功/失败有差异化的动画效果（颜色、文字、发光差异）
4. **幻觉等级影响不可预测性** — 幻觉等级高时，骰子结果偏移增大（随机性增强）
5. **路线选择中至少1个检定点** — MVP 至少有一个路线分支需要检定

### User Scenarios

- **Scenario A（核心检定体验）:** 玩家在便利店与店员对话时，触发「共情检定」：`1D20 + 共情值(6) vs 难度(12)`。骰子滚动动画结束后结果为 18（成功），UI 呈现成功效果（绿色闪光），对话进入"温暖回应"分支。信念 +1。

- **Scenario B（检定失败分支）:** 玩家在天桥与流浪汉对话，触发「洞察检定」：`1D20 + 洞察值(3) vs 难度(10)`。结果为 7（失败），UI 呈现失败效果（红色抖动+衰减），对话进入"无法理解"分支——流浪汉说出不同的台词，但游戏继续。

- **Scenario C（幻觉影响）:** 玩家的幻觉等级为 7/10，触发「坚韧检定」时，骰子结果额外增加一个随机偏移 `randf_range(-3, +3)`（幻觉等级越高偏移范围越大）。玩家可能因为幻觉获得意外的高结果或低结果。

- **Frequency:** MVP 阶段至少 1 个检定点；完整版预期每路线 2-3 个检定点，每次 3-5 秒的检定动画回放。

### Scope Boundaries vs Overlapping PRDs

| PRD | Covers | NOT covered（留给此 PRD） |
|-----|--------|--------------------------|
| #5 (CRPG 核心机制) | 定义了"对话即检定"的概念——状态值区间匹配决定对话分支 | ❌ 无骰子机制、无属性对比、无视觉反馈、无幻觉影响随机性 |
| #42 (主题-机制映射) | 将"对话即检定"映射到主题表达（身份焦虑、自我否定） | ❌ 分析的是检定*表达什么主题*，而非检定*如何实现* |
| #46 (对话引擎数据模型) | 对话数据模型、条件 DSL（slider/flag/choice_made） | ❌ 条件求值是纯静态的，无随机数、无骰子 |
| #47 (GameState 系统) | 三轴状态管理器（hope_despair/conviction/will） | ❌ 无属性系统（洞察/共情/坚韧）、无骰子结果存储、无检定历史 |
| #52 (对话运行时+视觉) | 3D 对话文字显示、选择导航、海明威约束 | ❌ 无检定 UI（滚动动画、成功/失败效果） |
| #53 (UI 系统) | 状态栏、响应式布局、Hopper 风格 | ❌ 无检定动画层、无检定结果特效 |
| #215 (godot_dialogue_manager 集成) | 替换自定义对话引擎为 godot_dialogue_manager | ❌ godot_dialogue_manager 无内置骰子系统。集成后仍需额外检定模块 |
| #222 (属性与 Perk 系统) | 添加 3 属性（洞察/共情/坚韧）+ Perk 系统 | ❌ 定义了属性*是什么*但未定义属性*如何用于检定* |

**此 PRD 是「检定系统」** — 聚焦于骰子机制、属性对比、成功率计算、幻觉影响随机性、检定 UI 动画和失败分支路由。它不重新分析对话条件门控（已由 #46 和 #215 覆盖）、不重新定义属性系统（由 #222 覆盖）、不重新设计 UI 风格（由 #53 覆盖）。

---

## 2. Design Intent

### 为什么当前没有骰子系统？

项目前期遵循"系统即叙事"（体验引擎）理念——对话分支由玩家状态决定，状态值高→更好结果，状态值低→更差结果。这是一种**确定性检定**：玩家的历史选择直接决定可达分支。

但 Issue #5 的 PRD 中"对话即检定"概念并未排除随机性。原文提到「信念 ≥ 5 时，你可以坦然回答」——这是一个**阈值对比**，但不含骰子。该 PRD 的 Spike 2（检定区间原型）也只是测试区间匹配的效率，未涉及随机数。

### 为什么现在需要骰子系统？

1. **叙事张力需求** — 纯状态值决定的确定性分支让玩家感觉"我的历史选择已经注定了结局"，而骰子系统引入了不可预测性（risk/reward dynamics），增强每次检定时刻的张力。

2. **属性系统的意义** — Issue #222 将添加 3 属性（洞察/共情/坚韧），如果属性只影响对话条件门控，则属性和现有状态轴（conviction/will）功能重叠。骰子系统赋予属性独特价值：属性值越高 → 骰子通过概率越高，但永远不能确保成功。

3. **幻觉系统的意义** — Issue #215 引入的幻觉等级（hallucination_level）需要一个系统来表达"高幻觉 = 不可预测"的叙事意图。骰子偏移是完美的表达——高幻觉时，检定可能意外成功或意外失败，体现认知失真（cognitive distortion）的主题。

4. **多周目价值** — 纯确定性的对话分支在一次完整游玩后失去 surprise。骰子检定的随机性让多周目仍然有不确定性。

### Previous Constraints

| 约束 | 详情 |
|------|------|
| 引擎 | Godot 4.7.1 / GDScript 2.0（静态类型） |
| 渲染器 | `forward_plus` with Glow pass |
| 分辨率 | 1920×1080, Allow HiDPI |
| 主题 | Edward Hopper 都市夜晚 — 暖琥珀色/冷暗色基底 |
| 对话引擎 | godot_dialogue_manager v3.10.5（Issue #215 已合并） |
| 状态系统 | StateSystem（hope_despair -10~+10, conviction 0~10, will 0~10） |
| 属性系统 | Issue #222 将添加 3 属性（洞察/共情/坚韧）+ Perk 系统（尚未实现） |
| 视觉风格 | LoFiText3D（像素化、受限色深、扫描线、自发光） |
| 写作风格 | 海明威约束（25 字符/句，3 句/段限制） |
| 平台 | macOS / Linux |
| 用户输入 | 键盘操作（方向键选择、Enter 确认） |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `gdscripts/skill_check_manager.gd` | 检定管理器 | **新建** — 核心检定逻辑：骰子生成、属性对比、成功率计算、幻觉偏移 |
| `gdscripts/skill_check_ui.gd` | 检定 UI | **新建** — 检定动画：骰子滚动、成功/失败效果、文字/颜色反馈 |
| `scenes/ui/skill_check_ui.tscn` | 检定 UI 场景 | **新建** — 检定 UI 场景（CanvasLayer） |
| `gdscripts/narrative_manager.gd` | 叙事管理器 | **扩展** — 增加检定节点路由表（成功/失败分支映射） |
| `dialogues/*.dialogue` | 对话文件 | **扩展** — 对话中嵌入检定节点（使用 godot_dialogue_manager 的 custom event 或函数调用） |
| `gdscripts/state_system.gd` | 状态系统 | **扩展** — 可能需要存储检定历史（成功/失败记录） |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/scene_base.gd` | 场景基类 | 可能需要触发检定的通用方法 |
| `gdscripts/dialogue_condition_evaluator.gd` | 条件求值器 | 可能需要支持"上次检定是否成功"条件类型 |
| `docs/GAME_DESIGN/05-DIALOGUE.md` | 对话设计文档 | 需新增检定节点描述和对话 DSL 扩展 |
| `gdscripts/status_bar.gd` | 状态栏 | 检定结果可能在状态栏短暂显示（可选） |

### Data Flow Impact

```
[对话节点触发检定]
    ↓
SkillCheckManager.resolve_check(attribute, difficulty, hallucination_level)
    ├── 计算基础成功率 = max(1, attribute - difficulty) × 5 + 50% (D20 公式)
    ├── 掷骰: roll = randi() % 20 + 1
    ├── 应用幻觉偏移: offset = randf_range(-hallucination_level * 0.5, +hallucination_level * 0.5)
    ├── 最终结果: result = roll + attribute + offset
    ├── 判定: result >= difficulty → success / failure
    └── 返回: {success: bool, roll: int, attribute: int, difficulty: int, result: float}
        ↓
SkillCheckUI.play_animation(result)
    ├── 成功: 绿色闪光 + 上升文本 + "✓ 成功" + 音效
    └── 失败: 红色抖动 + 衰减效果 + "✗ 失败" + 低沉音效
        ↓
NarrativeManager.route_check_result(check_result)
    ├── 成功 → 对话进入 success_branch
    └── 失败 → 对话进入 failure_branch（非 Game Over）
```

### Documents to Update

- [ ] `docs/GAME_DESIGN/05-DIALOGUE.md` — 添加检定节点规范和对话 DSL 扩展
- [ ] `docs/PRD/227-skill-check-system.md` — **本文档**

---

## 4. Solution Comparison

### Approach A: 独立检定管理器（SkillCheckManager）

**描述：** 新建一个 GDScript 类 `SkillCheckManager`（扩展 `Node`，可选 autoload），作为集中式检定引擎。它封装了骰子逻辑、属性对比、幻觉偏移计算。对话文件通过 godot_dialogue_manager 的 `custom` 事件或函数调用触发检定，管理器返回结果后对话根据结果路由到不同分支。

**组件：**
- `SkillCheckManager.gd` — 核心检定引擎
- `SkillCheckUI.gd` + `skill_check_ui.tscn` — CanvasLayer 检定动画
- `CheckResult` 数据类（success, roll, attribute_value, difficulty, hallucination_offset）

**Pros:**
- 职责清晰，跨对话文件复用（一次实现，多处调用）
- 容易测试（抽离 UI 后可以在 headless 模式测试逻辑）
- 幻觉影响集中在一处（修改公式不影响其他系统）
- 可添加 Perk 影响检定（从 #222 的 Perk 系统读取加成）

**Cons:**
- 需要 godot_dialogue_manager 支持外部函数调用（需确认 API：`using` 语句能否调用非 getter 方法）
- 对话文件编写者需要理解 DSL 扩展语法

**Risk:** Low — godot_dialogue_manager 的 `using` 语法支持调用 autoload 方法，技能可枚举。

**Effort:** 中等（3-5 天）

### Approach B: 对话內联检定（Inline Check in Dialogue）

**描述：** 不创建独立管理器，而是在每个需要检定的对话文件中通过 godot_dialogue_manager 的状态条件表达式直接实现检定逻辑。使用 `randi()` 内联在对话条件中。

**Pros:**
- 无需新增脚本类（纯对话 DSL 配置）
- 原型阶段快速验证

**Cons:**
- 每个检定点重复编写骰子表达式（违反 DRY）
- `randi()` 在条件表达式中每次求值结果不同（不可调试）
- 无法复用检定 UI 动画（每个检定点需要自己管理 UI）
- 无法统一处理幻觉偏移（每个对话文件独立处理）
- 不可测试（headless 模式下无法验证检定逻辑）

**Risk:** High — 对话条件 DSL 不支持任意 GDScript 表达式，`randi()` 可能在框架层面被缓存或禁止。

**Effort:** 低（1 天原型）但维护成本高

### Approach C: DialogueBalloon 子类扩展

**描述：** 继承或扩展 `DialogueBalloon`（godot_dialogue_manager 的对话气泡脚本），在气泡流程中嵌入检定阶段。当对话遇到 `[check]` 标记时，暂停对话流程，弹出检定 UI，根据结果恢复对应分支。

**Pros:**
- 与 godot_dialogue_manager 深度集成（无需外部调用）
- 利用 DialogueBalloon 已有的 CanvasLayer 生命周期管理

**Cons:**
- 强耦合到 GodotDialogueManager 的私有 API（升级 addon 时 break risk）
- 需要读取 godot_dialogue_manager 源码理解 internal 状态机
- 自定义对话标记（`[check]`）需要修改 dialogue ballon 的解析逻辑

**Risk:** Medium — 耦合度高，升级风险

**Effort:** 中等（3-4 天）

### Recommendation

→ **Approach A（独立检定管理器）** 因为：

1. **跨场景复用性** — 检定系统不仅在对话中使用，未来可扩展到环境交互（如"调查涂鸦：洞察检定"）、物品互动等
2. **可测试性** — `SkillCheckManager` 可在 headless 模式下使用 `--script` 测试，验证骰子分布和幻觉偏移公式
3. **Perk 集成预留** — Issue #222 的 Perk 系统可以通过 `SkillCheckManager.add_perk_modifier()` 接口无缝集成
4. **叙事完整性** — 检定结果可以写入 StateSystem 的 flags 或新增 check_history，供后续条件门控使用（如"如果你上次洞察检定失败，这里出现额外选项"）
5. **godot_dialogue_manager 兼容性** — 通过 `using StateSystem` 或 `extra_game_states` 暴露管理器方法，对话 DSL 直接调用 `SkillCheckManager.roll_check("insight", 12)`

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path

1. 对话进行到某个节点，检定点触发 → 对话暂停（dialogue balloon 保持可见但不可交互）
2. 检定 UI 显示：属性名 + 难度值 + 骰子动画
3. 骰子动画播放（~1.5 秒）：数字快速变换后停在最终值
4. 结果计算：`D20 + 属性值 + 幻觉偏移 vs 难度`
5. 成功/失败视觉反馈（0.5 秒动画）
6. 对话继续：根据结果路由到 success_branch 或 failure_branch
7. 检定结果记录到 StateSystem（Flag 或 check_history）
8. 玩家可继续正常对话交互

### Edge Cases

1. **属性值为 0（未加点）:** 检定公式变为 `D20 + 0 + 偏移 vs 难度` — 纯靠运气。应显示 "属性未分配" 提示。
2. **幻觉等级为 0（无影响）:** 偏移为 0，检定完全由属性值和骰子决定。
3. **幻觉等级为 10（最大）:** 偏移范围为 `[-5, +5]` — 检定结果高度不可预测，可能属性低成功或属性高失败。
4. **难度值超出 [1, 20] 范围:** 会计时到有效范围并 push_warning。
5. **骰子结果 = 自然 20（暴击成功）:** 无论属性值/难度值多少，直接成功（和 D&D 暴击规则一致）。
6. **骰子结果 = 自然 1（大失败）:** 无论属性值/难度值多少，直接失败。
7. **多个连续检定:** 前一个检定 UI 播放完毕后才触发下一个（排队机制）。
8. **检定中切换场景:** 检定中的对话被 `change_scene_to_file()` 中断 → 检定应安全取消（skip animation, 走默认分支）。
9. **Perk 加成:** Perk 系统提供额外加成（如 "+2 洞察检定"）应叠加到属性值上。
10. **对话中途退出:** 玩家在检定动画播放时按 ESC → 跳过动画，直接走失败分支（惩罚性退出策略）。

### Failure Paths

1. **godot_dialogue_manager 不执行外部方法:** 如果 DSL 不支持调用 `SkillCheckManager.roll_check()` → 回退：对话中嵌入条件分支，检定结果通过修改 StateSystem 的临时 flag 传递。
2. **检定 UI 未加载（资源缺失）:** 跳过动画，直接静默计算检定结果并路由分支。
3. **骰子系统在多帧中不一致:** `randi()` 在 `_process` 中每次调用返回不同值 → 检定结果应在单帧中计算并缓存，避免重复调用。

> 这些直接成为 Plan 阶段的测试用例骨架。

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| #215 — godot_dialogue_manager 集成 | ✅ CLOSED | Low — 已确定 `extra_game_states` 接口可用 |
| #222 — 属性与 Perk 系统 | 🔄 OPEN (research) | Medium — 属性（洞察/共情/坚韧）定义是检定系统的输入。需先锁定属性名、取值范围、初始值 |
| godot_dialogue_manager `using` API 确认 | ⚠️ 需验证 | Low — 需确认能否调用 autoload 方法并返回结果到对话分支 |

### Blocks

| Future Work | Priority |
|-------------|----------|
| 路线选择中的检定点落地 | P0 — MVP |
| Perk 对检定结果的加成实现 | P1 — 与 #222 集成 |
| 多路线多检定点的完整路线配置 | P2 |

### Preparation Needed

- [ ] Issue #222 先完成或锁定属性接口（属性名、类型、范围）
- [ ] 验证 godot_dialogue_manager 的 `using` / `extra_game_states` 是否能调用带参数方法
- [ ] 确认骰子公式：D20 + 属性 vs 难度（基础版）、是否引入 D100（扩展版）
- [ ] 设计 3 套检定 UI 视觉稿（成功/失败/进行中）

---

## 8. Continuation Context

> *此 Section 是 Plan 阶段的 handoff，记录当前系统状态和下一步起点。*

检定系统是项目中首个引入随机性的机制，与现有确定性状态系统（StateSystem）互补。当前 DialogueConditionEvaluator 只支持静态条件求值，SkillCheckManager 将作为独立层叠加在对话引擎之上。

**当前状态：**
- 对话引擎：✅ 集成完成（godot_dialogue_manager + DialogueBalloon）
- 状态系统：✅ 三轴 + 双极 hope_despair（StateSystem）
- 属性系统：🔄 开发中（#222 — 洞察/共情/坚韧）
- Perk 系统：🔄 设计中（#222 — 至少 4 个 Perk）
- 检定系统：⏳ 此项（#227，尚未实现）

**关键设计决策：**
- 检定公式：`D20 + attribute_value + hallucination_offset vs difficulty`（D20 基础 + 属性 + 幻觉偏移）
- 幻觉偏移公式：`randf_range(-hallucination_level * 0.5, +hallucination_level * 0.5)`（幻觉 0→无偏移，幻觉 10→±5 偏移）
- 推荐架构：Approach A — 独立 SkillCheckManager（autoload 或手动注册）
- 检定结果路由：godot_dialogue_manager 的 `using StateSystem` 调用 `SkillCheckManager.roll_check()` → 返回 `{success/branch_id}` → 对话条件分支匹配

**主要风险：**
1. godot_dialogue_manager 的 `using` 调用方法的能力需通过原型验证
2. #222 的属性接口尚未定稿，检定系统的输入接口需预留兼容层
3. 幻觉等级在 StateSystem 中的存储位置：当前 StateSystem 无 hallucination_level 字段——需确认 #215 的实现或新增
