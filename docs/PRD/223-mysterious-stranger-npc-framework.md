# Research: 神秘人角色框架 — 全场景NPC系统 (Mysterious Stranger NPC Framework)

> Parent Issue: #223
> Agent: game-research-agent
> Date: 2026-07-25

---

## 1. Problem Definition

### Current Behavior

项目中已存在神秘人NPC的部分实现，但仅限于两个场景的孤立触发器，缺乏统一的跨场景框架：

#### 已有神秘人内容

| 场景 | 文件名 | 触发方式 | 内容形态 |
|------|--------|---------|---------|
| Lobby | `dialogues/lobby_stranger.dialogue` | Area3D `input_event` → `start_dialogue()` | 完整对话树（~68行），6+分支，条件判定基于StateSystem |
| Underpass | `dialogues/underpass_stranger_echo.dialogue` | Area3D `input_event` → `start_dialogue()` | 完整对话树（~176行），12+分支，含meta层揭示 |
| Office | — | 无 | 无神秘人NPC |
| Street | — | 无 | 无神秘人NPC |
| Convenience Store | — | 无 | 无神秘人NPC |
| Bridge | — | 无 | 无神秘人NPC |
| Subway Station | — | 无 | 无神秘人NPC |

#### 现有基础设施

| 系统 | 文件 | 状态 | 说明 |
|------|------|------|------|
| NPC框架 | `gdscripts/npc_node.gd` (220行) | ✅ 已实现 | NPCNode类：状态机、触发区域、人格层、对话启动 |
| NPC场景 | `scenes/components/NPC.tscn` | ✅ 已实现 | Node3D + InteractionTrigger + Label3D + Timer |
| 对话管理器 | `gdscripts/dialogue_balloon.gd` | ✅ 已实现 | godot_dialogue_manager 集成完成 |
| 状态系统 | `gdscripts/state_system.gd` (339行) | ✅ 已实现 | hope_despair(-10~+10), conviction(0-10), will(0-10), flags |
| 幻觉等级系统 | `gdscripts/narrative_manager.gd` | ✅ 已实现 | 0-10级幻级别, 每场景基础值, hope调制, 视觉参数映射 |
| 叙事管理器 | `gdscripts/narrative_manager.gd` | ✅ 已实现 | 场景序列、色调表(5态×6场景=30条)、回响系统 |
| 场景基类 | `gdscripts/scene_base.gd` | ✅ 已实现 | 玩家实例化、色调查询、对话气球启动 |

#### 幻觉等级系统现状

`NarrativeManager.get_hallucination_level()` 定义了每场景基础幻觉值：

| 场景 | 基础幻觉等级 | 状态调制 |
|------|------------|---------|
| Office | 0 | hope≥8 → -1, hope≤2 → +1 |
| Lobby | 1 | 同上 |
| Convenience Store | 2 | 同上 |
| Bridge | 4 | 同上 |
| Underpass | 7 | 同上 |
| Subway Station | 9 | 同上 |

幻觉参数映射系统 (`get_hallucination_params()`) 可输出 vigenette, rain_density, light_flicker, text_drift, view_instability 五个参数——但当前**没有任何NPC或视觉元素在运行时消费这些参数**。

#### 当前局限

1. **神秘人仅出现在2/7场景** — Lobby和Underpass有神秘人对话，但Office、Street、Convenience Store、Bridge、Subway Station没有
2. **无跨场景NPC持久化** — 每个场景独立实例化神秘人，没有「神秘人记忆」系统（玩家之前的互动不改变后续场景的神秘人行为）
3. **对话不按幻觉等级分变体** — 当前对话使用 hope_despair 条件分支，但无法根据NarrativeManager的幻觉等级（0-10）选择3+变体版本
4. **无视觉/Decal颜色变化** — 神秘人外观固定，不随幻觉等级微妙变化
5. **终局行为无转变** — 神秘人在Subway Station没有与幻觉等级/路线对应的决定性行为变化
6. **NPCNode非跨场景设计** — NPCNode是静态场景编辑器放置的节点，没有跨场景数据传递和状态恢复机制

### Expected Behavior

一个**全场景神秘人NPC框架**，满足：

1. **AC1: 全场景覆盖** — 神秘人作为跟随NPC，在 Office、Lobby、Street、Convenience Store、Bridge、Underpass、Subway Station **每个场景中以不同形态/位置出现**
2. **AC2: 三级对话变体** — 神秘人对话按幻觉等级分为至少3个变体版本（低幻觉/中幻觉/高幻觉），对话内容反映幻觉程度的变化
3. **AC3: 视觉微妙变化** — 神秘人的外观（模型颜色、Decal颜色、标签色调）随幻觉等级微妙变化，玩家能感知但不会突兀
4. **AC4: 终局行为转变** — 神秘人在Subway Station终局场景有决定性行为转变，与该场景的路线判定（Keep Walking / Turn Back / Stay）联动

### User Scenarios

- **Scenario A（首次游玩玩家）:** 玩家在Office窗口外看到神秘人的模糊剪影，Lobby遇到「另一个加班者」并对话，Street上雨帘中再次看到，Convenience Store门口出现，Bridge上神秘人站在栏杆旁，Underpass深入对话揭示真相，Subway Station做出最终选择。神秘人随幻觉加深逐渐从「模糊轮廓」变为「清晰自我投射」。

- **Scenario B（多周目玩家）:** 玩家带着第2周目的flag（`is_new_game_plus`）进入游戏。神秘人在Office就以更清晰形态出现，对话提前出现meta层（"我就是你"揭示）。幻觉等级因场景提前升高，对话变体直接跳至高幻觉版。

- **Scenario C（低保真幻觉玩家）:** 玩家希望值一直很低（hope≤2），幻觉等级始终偏高。神秘人从Office开始就以扭曲/破碎形态出现，对话充满不安和镜像暗示。终局Stay路线时神秘人变为主角唯一不变的陪伴。

- **Frequency:** 每场景至少1次互动，全流程7+次。幻觉等级变化（每场景不同等级）触发不同的对话变体和外观参数。

### Scope Boundaries vs Overlapping PRDs

| PRD | Covers | NOT covered (left to this PRD) |
|-----|--------|--------------------------------|
| #214 叙事架构 | 博尔赫斯约束、三层表达、距离-幻觉映射表、路线弧线 | ❌ 不涉及神秘人NPC的具体场景分布、对话变体实现、跨场景NPC持久化机制 |
| #215 对话管理器集成 | godot_dialogue_manager集成，`.dialogue`格式迁移，DialogueBalloon | ❌ 不涉及NPC跨场景框架、幻觉等级驱动的对话变体选择、NPC外观参数 |
| #152 测试NPC | 测试NPC放置、E键交互整合、端到端对话循环 | ❌ 不涉及跨场景NPC跟随系统、NPC状态持久化 |
| #154 状态-世界反馈 | 5态环境文本扩展、`TextComponentBase`动态更新 | ❌ 不涉及NPC对话变体选择、NPC视觉外观参数 |
| #59 神秘人NPC（原设计） | Underpass场景的3层神秘人对话树、3分支结局路线 | ❌ 仅覆盖underpass单个场景，不涉及全场景跨场景框架 |
| #220 主题-机制映射 | 三个核心主题的机制覆盖分析 | ❌ 不涉及神秘人NPC的实现架构 |

**This PRD is the 神秘人角色框架 — 全场景NPC系统 — it focuses on building a cross-scene NPC framework where the mysterious stranger appears in every scene. It does NOT re-analyze Borgesian constraints (covered by #214), dialogue format choices (covered by #215), or the general NPCNode framework architecture (covered by #54/#152).**

---

## 2. Design Intent

### Why Does Current Behavior Exist?

| 原因 | 说明 | 相关Issue |
|------|------|-----------|
| 场景逐步构建 | 6场景按线性顺序开发，神秘人最初设计仅覆盖underpass（作为终局NPC） | #59, #58 |
| 无跨场景系统需求 | 早期设计将神秘人视为单一场景NPC，而非贯穿全程的跟随角色 | #45 #214 |
| 幻觉系统晚于NPC | 幻觉等级系统（#214）和NPC框架（#54/#59）在不同时间线开发，整合尚未完成 | #214 vs #54/#59 |
| 对话管理器集成中 | #215（godot_dialogue_manager集成）正在进行，对话格式从JSON迁移到`.dialogue` | #215 |

### Why Change Now?

1. **幻觉等级系统已完善** — `NarrativeManager`的幻觉等级计算（0-10级，每场景基础值 + hope调制 + 视觉参数映射）已就绪，但没有任何NPC消费这些参数。神秘人是将幻觉等级"可视化"的最佳载体
2. **NPC框架已成熟** — `NPCNode` (220行) + `NPC.tscn` 已跨场景可用，只需扩展跨场景持久化和幻觉等级参数
3. **对话管理器集成完成** — `godot_dialogue_manager` 的 `.dialogue` 格式和条件表达式系统已集成（#215），支持运行时条件求值
4. **叙事架构已定义** — 三条路线（Keep Walking / Turn Back / Stay）和神秘人作为「内心投射」的定义（#214）为终局行为转变提供了设计基础
5. **环境文本已5态化** — #154 将环境文本扩展至5态，神秘人作为三轴状态的"可视化角色"可以复用相似的5态映射
6. **玩家体验缺口** — 从Office到Subway Station的旅程中，神秘人是叙事核心的"锚点"。当前2/7的覆盖率和无幻觉响应，使得这个核心锚点在大半旅程中缺席

### Previous Constraints

| 约束 | 详情 | 来源 |
|------|------|------|
| 引擎 | Godot 4.7.1 / GDScript 2.0 | project.godot |
| NPC框架 | NPCNode (`npc_node.gd`) + NPC.tscn — 状态机(IDLE/TALKING/COOLDOWN/EXHAUSTED/SPECIAL) | #54 |
| 对话格式 | `.dialogue` (godot_dialogue_manager格式) | #215 |
| 状态系统 | 三轴: hope_despair(-10~+10), conviction(0-10), will(0-10) + flags | StateSystem |
| 幻觉等级 | 0-10级, 每场景基础值 + hope调制, 5类视觉参数 | NarrativeManager |
| 博尔赫斯约束 | B3: 无元叙事标签 — 不能出现"幻觉"、"梦境"等词汇 | #214 |
| 写作风格 | Hemingway — ≤25字符/句, ≤3句/节点 | #51 |
| 终端转变 | Subway Station 根据 hope/conviction/will 判定三条路线 | #214 |
| 视觉风格 | Edward Hopper urban night — 深色(#1a1a2e), 暖琥珀色光, lo-fi像素文字 | GDD |
| 场景序列 | office → lobby → convenience_store → bridge → underpass → subway_station | NarrativeManager |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `gdscripts/stranger_manager.gd` | StrangerManager | **New** — 跨场景神秘人管理器：场景分布定义、形态/位置映射、幻觉等级驱动的对话变体选择、跨场景记忆/状态持久化 |
| `gdscripts/stranger_npc.gd` | StrangerNPC | **New** — 扩展NPCNode：增加幻觉等级参数映射（vigenette、text_drift应用到NPC外观）、Decal颜色动态更新、3+对话变体选择 |
| `gdscripts/npc_node.gd` | NPCNode | **Modified** — 扩展`evaluate_personality_layer()`支持幻觉等级条件；增加`hallucination_aware`模式；增加跨场景持久化钩子 |
| `gdscripts/narrative_manager.gd` | NarrativeManager | **Modified** — 可能增加`stranger_state_changed`信号；扩展`get_hallucination_params()`到NPC视觉参数映射 |
| `scenes/components/stranger_npc.tscn` | StrangerNPC场景 | **New** — 基于NPC.tscn扩展的Stranger专属场景，含Decal、灯光、Label3D |
| `scenes/office/office.tscn` | Office场景 | **Modified** — 添加神秘人NPC实例(窗外模糊剪影) |
| `scenes/lobby/lobby.tscn` | Lobby场景 | **Modified** — 替换当前硬编码触发器为StrangerNPC实例(另一个加班者) |
| `scenes/street/street.tscn` | Street场景 | **Modified** — 添加神秘人NPC实例(雨帘中模糊身影) |
| `scenes/store/convenience_store.tscn` | Store场景 | **Modified** — 添加神秘人NPC实例(门口倒影) |
| `scenes/bridge/bridge.tscn` | Bridge场景 | **Modified** — 添加神秘人NPC实例(栏杆旁影子) |
| `scenes/underpass/underpass.tscn` | Underpass场景 | **Modified** — 替换当前硬编码触发器为StrangerNPC实例(隧道尽头身影) |
| `scenes/subway_station/subway_station.tscn` | Subway Station场景 | **Modified** — 添加神秘人NPC实例(终局决定性转变) |
| `dialogues/lobby_stranger.dialogue` | 对话数据 | **Modified** — 扩展为3+幻觉等级变体 |
| `dialogues/underpass_stranger_echo.dialogue` | 对话数据 | **Modified** — 整合为StrangerManager驱动的3+变体 |
| `dialogues/office_stranger.dialogue` | 对话数据 | **New** — Office场景神秘人对话(窗外剪影) |
| `dialogues/street_stranger.dialogue` | 对话数据 | **New** — Street场景神秘人对话(雨身影) |
| `dialogues/store_stranger.dialogue` | 对话数据 | **New** — Store场景神秘人对话(门口倒影) |
| `dialogues/bridge_stranger.dialogue` | 对话数据 | **New** — Bridge场景神秘人对话(栏杆旁) |
| `dialogues/subway_stranger.dialogue` | 对话数据 | **New** — Subway Station终局决定性转变对话 |
| `tests/test_stranger_cross_scene.gd` | 测试 | **New** — 跨场景神秘人系统端到端测试 |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/scene_base.gd` | SceneBase | 可能增加StrangerManager初始化调用；场景切换时传递神秘人状态 |
| `gdscripts/scene_manager.gd` | SceneManager | 场景过渡时可能需要保存/恢复StrangerManager状态 |
| `gdscripts/game_manager.gd` | GameManager | 可能增加stranger_memory字段用于跨场景持久化 |
| `gdscripts/player_controller.gd` | PlayerController | 玩家接近神秘人时的特殊交互处理（可选） |
| `scenes/main.tscn` | Main | 可能增加StrangerManager autoload注册 |

### Data Flow Impact

```
NarrativeManager.get_hallucination_level(scene_id, state)
    │
    ├──► StrangerManager._on_scene_entered(scene_id)
    │       ├── 查询场景定义表 → StrangerAppearanceConfig (形态、位置、对话ID)
    │       ├── 查询跨场景记忆 → 恢复对话状态、flags、已触发的meta层
    │       ├── 计算幻觉等级 → 选择对话变体等级(low/mid/high)
    │       └── 配置StrangerNPC实例
    │
    ├──► StrangerNPC (场景中实例)
    │       ├── appearance: 形态/位置 (每场景不同)
    │       ├── dialogue_variant: 基于幻觉等级的对话变体
    │       ├── decal_color: 随幻觉等级微妙变化
    │       └── visual_params: vignette/text_drift 映射到NPC材质
    │
    └──► 终局场景 (Subway Station)
            ├── StrangerManager.check_ending_transition()
            ├── determine_ending() → keep_walking / turn_back / stay
            └── StrangerNPC._execute_ending_behavior(ending_type)
                    ├── Keep Walking: 神秘人融入光芒,消失
                    ├── Turn Back: 神秘人变为扭曲镜像
                    └── Stay: 神秘人停留在原地,与主角并坐
```

### Documents to Update

- [x] **本次产出:** `docs/PRD/223-mysterious-stranger-npc-framework.md`
- [ ] `docs/DESIGN/223-mysterious-stranger-npc-framework.md` (Plan阶段)
- [ ] `docs/GAME_DESIGN/05-DIALOGUE.md` (更新NPC章节)
- [ ] `docs/GAME_DESIGN/06-NARRATIVE.md` (更新神秘人叙事角色)

---

## 4. Solution Comparison

### Approach A: StrangerManager 单例 + StrangerNPC 扩展

- **Description:** 创建一个 `StrangerManager` 全局单例（autoload），管理神秘人跨场景状态和幻觉等级驱动的行为选择。创建一个 `StrangerNPC` 类（扩展 NPCNode），集成视觉参数映射和对话变体选择。每场景放置 StrangerNPC 实例，StrangerManager 在场景进入时配置其形态、对话ID、视觉参数。

  ```
  StrangerManager (autoload)
    ├── scene_configs: Dictionary — 每场景的形态、位置、对话ID、基础视觉参数
    ├── cross_scene_state: {flags, meta_unlocked, interactions_history}
    ├── hallucination_config: {dialogue_variant_map, visual_params_map}
    │
    └── StrangerNPC (per-scene, extends NPCNode)
          ├── _set_appearance_for_scene(scene_id)
          ├── _select_dialogue_variant(hallucination_level)
          ├── _update_visual_params(hallucination_level)
          └── _execute_ending_behavior(ending_type)
  ```

- **Pros:**
  - 清晰的关注点分离：StrangerManager 管理跨场景状态，StrangerNPC 管理单场景表现
  - autoload 模式在场景切换时自动存活，天然支持跨场景状态
  - 复用现有 NPCNode 框架（220行已验证），只需扩展幻觉等级和视觉参数
  - 与 godot_dialogue_manager 的 `using StateSystem` 模式兼容
  - 每场景配置为数据驱动（Dictionary），易扩展新场景

- **Cons:**
  - 需要增加一个 autoload（增加启动加载项）
  - StrangerNPC 需要与每场景现有的交互触发器协调（避免冲突）
  - 每场景的形态/位置需要 TSCN 编辑器的修改
  - 幻觉等级变化不能实时反映在NPC外观上（只在场景进入时计算）

- **Risk:** Low — 已有 NPCNode 和 autoload 模式验证，增量修改风险低
- **Effort:** Medium (estimated 3-4 days)

### Approach B: 纯数据驱动的NPC配置系统

- **Description:** 不创建专门的StrangerManager或StrangerNPC类，而是扩展 `NPCNode` 的 `personality_layers` 系统支持"场景感知"模式。使用资源文件（.tres）定义每场景的神秘人配置（形态、对话变体、视觉参数），NPCNode 在 `_ready()` 时根据场景ID和幻觉等级选择配置。

- **Pros:**
  - 无需新增 autoload，架构更薄
  - 资源文件可热加载、可复用
  - NPCNode 的 `personality_layers` 已支持条件型人格层切换

- **Cons:**
  - `personality_layers` 设计为单场景感知层切换，不支持跨场景记忆
  - 跨场景状态（meta_unlocked, interactions_history）无存储位置——需要在GameManager或StateSystem中额外增加字段
  - 幻觉等级计算和NPC视觉参数逻辑散落在各NPCNode实例中，难以维护和调试
  - 每场景形态/位置需在多个.tres资源文件中定义，配置分散
  - terminal转变逻辑需要在Subway Station的NPCNode中特殊处理，增加场景脚本复杂度

- **Risk:** Medium — 跨场景状态分散存储可能导致不一致
- **Effort:** Medium (estimated 3-4 days, similar to A but with higher maintenance cost)

### Recommendation

→ **Approach A** 因为：
1. 跨场景NPC的核心需求（持久化、状态恢复、连续性）天然需要一个跨场景的管理器
2. StrangerManager作为autoload在场景切换时存活，是最简单的跨场景状态保存方式
3. 隐藏层揭示（meta_unlocked）和互动历史是神秘人角色的核心叙事特征，必须全局维护
4. 幻觉等级驱动的视觉参数映射是独立逻辑，不应散落在6+场景的NPC实例中
5. Approach B的"分散存储"风险在终局转变场景将被放大——subway_station的决策需要读取所有前面场景的互动历史，这在B中需要复杂的跨场景查询
6. Autoload增加的启动成本可忽略不计（StrangerManager 预计<100行核心逻辑）

**选择A的代价可控：** 增加1个autoload + 1个扩展类 + 7场景的`Node3D`子节点放置。所有场景脚本只需要在`_ready()`中调用 `StrangerManager.register_scene_stranger(stranger_npc_instance)`。

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path

1. **场景进入** — 玩家通过场景过渡进入新场景（如从Office到Lobby）
2. **StrangerManager检测** — `_on_scene_entered(scene_id)` 触发，查询该场景的StrangerAppearanceConfig
3. **StrangerNPC配置** — StrangerNPC实例设置形态/位置、标签文本和交互提示
4. **幻觉等级计算** — `NarrativeManager.get_hallucination_level(scene_id, state)` 返回0-10级
5. **对话变体选择** — 幻觉等级映射到变体等级（low: 0-3, mid: 4-6, high: 7-10），设置对话ID
6. **视觉参数应用** — 幻觉参数（vignette, text_drift等）映射到NPC材质参数（emissive强度、色温、透明度）
7. **Decal颜色调整** — NPC的Decal颜色根据幻觉等级从「写实」(低幻觉)平滑过渡到「鲜艳/扭曲」(高幻觉)
8. **玩家互动** — 玩家接近→看到名字标签→E键/点击→StrangerNPC启动对应变体的对话
9. **跨场景记忆** — `dialogue_completed` 信号更新StrangerManager的状态（flags, meta_unlocked, interactions_history）
10. **终局转变** — Subway Station场景：神秘人行为根据`NarrativeManager.determine_ending()`变化

### 每场景神秘人形态设计

| 场景 | 形态/位置 | 形态描述（低幻觉→高幻觉） | 对话变体主题 |
|------|----------|-------------------------|------------|
| Office | 窗外剪影 | 站立的模糊人影 → 扭曲拉伸的倒影 | 旁观、观察、第一声 |
| Lobby | 另一个加班者 | 正常NPC → 镜像抽搐 | 询问、日常、第一次对话 |
| Street | 雨帘中身影 | 撑伞的人影 → 雨中没有影子 | 跟踪、暗示、环境音 |
| Convenience Store | 门口倒映 | 玻璃反射的正常人影 → 玻璃反射里没有你 | 购买、隐喻、镜子 |
| Bridge | 栏杆旁影子 | 凭栏远眺的人 → 栏杆上只有一只手 | 边缘、临界点、选择 |
| Underpass | 隧道尽头身影 | 站立的人 → 漂浮/扭曲的存在 | 真相、揭示、"我就是你" |
| Subway Station | 月台上等待 | 正常等待的人 → 融入光芒/扭曲成镜像 | 告别、选择、转变 |

### Edge Cases

1. **第一次进入场景时幻觉等级已高（low → high跳变）:** 神秘人在Office就以高幻觉变体出现，形态扭曲，对话直接跳到深层。StrangerManager应记录`first_encounter_level`，用于追踪神秘人的"衰老"程度。

2. **返回已访问场景（理论上不可能当前架构）:** 当前场景序列为线性(6场景一次通过)，但设计上应支持未来可能的回访。StrangerManager按场景ID记录互动状态，回访时恢复。

3. **多周目（is_new_game_plus）:** 第2周目时，`is_new_game_plus` flag使神秘人在Office就以更高幻觉形态出现，对话提前包含meta层。StrangerManager检测`load()`后的playthrough count。

4. **幻觉等级在场景中途变化:** 玩家与神秘人对话中做出选择导致hope变化→幻觉等级变化。此时对话树已在执行，不应中断。视觉参数可在对话结束后再更新。

5. **终局路线判定与神秘人行为不一致:** 如果NarrativeManager判定"Keep Walking"但玩家的互动历史显示从未与神秘人互动——StrangerManager应有fallback行为（如神秘人保持沉默）。

6. **玩家跳过所有神秘人互动:** StrangerManager记录`interaction_count=0`。终局时神秘人不认识玩家，对话变为"我们一直在等某个人"——陌生感本身就是叙事工具。

7. **极端状态（hope≥8 & hope≤2 同时meta修饰）:** hope≥8使幻觉等级-1, hope≤2使幻觉等级+1。极端状态下，StrangerNPC的视觉效果可能达到阈值上限/下限——应clamp且不溢出。

8. **新场景尚未构建（如Subway Station未完成时测试）:** StrangerManager的`scene_configs`应包含`is_available: bool`标志。不可用场景不会实例化StrangerNPC，避免场景加载错误。

### Failure Paths

1. **StrangerManager autoload启动失败:** 如果StrangerManager的`_ready()`未能注册到NarrativeManager，会导致幻觉等级始终为0。回退：StrangerNPC使用NPCNode的默认`personality_layers`行为，使用hope_despair条件分支而非幻觉等级条件。

2. **对话资源文件缺失:** 如果场景的Stranger对话`.dialogue`文件不存在，StrangerNPC应该使用NPCNode的默认IDLE行为（显示名字标签但不提供交互入口），并打印警告。

3. **跨场景状态保存失败（save/load边界）:** 如果`StrangerManager.save_state()`因JSON序列化失败，应在写入时捕获异常并记录`save_failed` flag。Load时如果detect到`save_failed`，使用默认状态初始化。

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| #215 — godot_dialogue_manager集成 | ✅ Merged (7/25) | Low — 已就绪 |
| NarrativeManager幻觉等级系统 (#214) | ✅ Merged | Low — `get_hallucination_level()` 可用 |
| NPCNode框架 (#54/#59) | ✅ Merged | Low — NPCNode 220行已验证 |
| 场景序列完成 (Office, Lobby, ... Subway Station) | ✅ 6场景已构建 | Low — 所有TSCN存在 |
| StateSystem三轴状态 | ✅ Merged | Low — `hope_despair/-10..+10` 可用 |
| StateSystem flags系统 | ✅ Merged | Low — `set_flag/has_flag` 可用 |

### Blocks

| Future Work | Priority |
|-------------|----------|
| #155 — Minimal Ending (神秘人终局行为集成) | P0 |
| #157 — Ambient Sound (神秘人专属音效) | P1 |
| #56 — Story Content (全场景对话内容填充) | P1 |
| #158 — MVP Integration Test (端到端神秘人流程验证) | P1 |

### Preparation Needed

- [ ] 验证 #215 (.dialogue格式) 在 NPCNode 的 `start_npc_interaction()` 中工作正常
- [ ] 确认 NarrativeManager.`get_hallucination_params()` 的视觉参数映射表是否足够NPC使用，或需要新增 NPC-specific 参数
- [ ] 确定 StrangerManager 是否作为 autoload 或 SceneManager child（取决于是否需要独立于主菜单的生命周期）
- [ ] 确定每场景 StrangerNPC 的形态视觉设计（模型/剪影/Decal的具体美术资源需求）
- [ ] 读取 `docs/GAME_DESIGN/` 获取更详细的神秘人角色设定和艺术参考

---

## 7. Spike / Experiment

> Required for depth/standard? No. Section 7 is required for depth/deep only.
> This issue is depth/standard, so §7 is omitted per template rules.
> (The template says: "Section 7 rule: Only required when the issue carries the depth/deep label.")

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*

### Current State

神秘人系统当前处于「多场景孤立实现、无幻觉等级感知、无跨场景框架」的状态：

- **已有2个场景的神秘人对话文件**（lobby_stranger.dialogue, underpass_stranger_echo.dialogue），都在godot_dialogue_manager的`.dialogue`格式中
- **NPCNode** (`npc_node.gd`) 提供了状态机、人格层、对话启动的基础，但所有NPC实例是静态放置的
- **NarrativeManager** 提供了完整的幻觉等级系统（0-10级）和视觉参数映射（5类参数），但没有任何NPC消费这些参数
- **StateSystem** 三轴状态（hope_despair, conviction, will）+ flags + choice_history 可用于跨场景记忆

### Recommended Approach

**Approach A** — StrangerManager autoload + StrangerNPC 扩展类:

1. **StrangerManager (New autoload, ~80-100行)**
   - `scene_configs: Dictionary` — 每场景配置（形态、位置、对话ID、基础视觉参数）
   - `_cross_scene_state: Dictionary` — `{flags, meta_unlocked, interactions, first_encounter_level, last_scene_id}`
   - `register_scene_stranger(stranger_npc)` / `_on_scene_entered(scene_id)` 接口
   - `get_dialogue_variant(hallucination_level) -> int` 映射 0-10级到3变体
   - `check_ending_transition(hallucination_level, ending_type) -> Dictionary` 终局行为参数

2. **StrangerNPC (New class, extends NPCNode, ~80-100行)**
   - `_set_appearance_for_scene(scene_id: String)` — 配置形态/位置
   - `_select_dialogue_variant(hallucination_level: int)` — 根据等级选择对话ID后缀（_low/_mid/_high）
   - `_update_visual_params(hallucination_level: int)` — 将幻觉参数（vignette, text_drift）映射到NPC材质参数
   - `_execute_ending_behavior(ending_type: String)` — 终局行为（Keep Walking: 消散; Turn Back: 扭曲; Stay: 停留）

3. **扩展NPCNode (`npc_node.gd`, ~+30行)**
   - 添加 `hallucination_aware: bool` export 变量
   - 在 `evaluate_personality_layer()` 中增加 `condition.type == "hallucination"` 支持
   - 添加 `cross_scene_id: String` 用于StrangerManager的持久化键

4. **对话文件扩展（当前文件 + 新建文件）**
   - 当前 `lobby_stranger.dialogue` 和 `underpass_stranger_echo.dialogue` 保留并作为"中幻觉"变体
   - 新增5个场景的对话文件（office, street, store, bridge, subway）
   - 每对话文件需要3个入口标题（`_low`, `_mid`, `_high`）对应3级幻觉变体
   - 或采用单一文件 + 条件前缀的模式（推荐，避免文件爆炸）

5. **每场景TSCN修改（7场景）**
   - 每场景放置 StrangerNPC 实例
   - 配置形态节点（Label3D、Decal、灯光）
   - 连接交互信号（E键/点击）

### Main Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| 多周目状态与 save/load conflict | Low | StrangerManager状态存入StateSystem save dict |
| 幻觉等级在对话中变化导致视觉不连贯 | Medium | 仅在对话结束后更新视觉参数 |
| NPCNode的 interaction_requested 与现有 Area3D `input_event` 冲突 | Medium | 每场景移除旧的硬编码 Area3D input_event，统一通过NPCNode启动 |
| 终局Subway Station的ending transition与当前场景逻辑耦合 | Low | SubwayScene扩展`_on_narrative_tone_changed`包装StrangerManager终局行为 |

### Key Design Decisions Pending

1. **autoload vs SceneManager child:** StrangerManager 是否需要独立于主菜单的生命周期？如果主菜单不展示神秘人，autoload在标题场景也在运行，浪费资源。但作为SceneManager child需要场景切换时手动管理保存/恢复——复杂化。**推荐：autoload + 惰性初始化**（主菜单场景跳过StrangerManager初始化）。
2. **对话变体策略:** 单一`.dialogue`文件 + 3个标题前缀（`~ stranger_low`, `~ stranger_mid`, `~ stranger_high`） vs 3个独立文件。**推荐：单一文件 + 条件前缀**，减少文件管理和资源加载开销。
3. **幻觉等级是否保存到save file:** 是。StrangerManager的跨场景状态（包括幻觉等级历史）应序列化到StateSystem的save dict或独立的save slot。
