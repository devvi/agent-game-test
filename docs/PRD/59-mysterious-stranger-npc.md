# Research: Mysterious Stranger NPC (三层真相对话树)

> Parent Issue: #59
> Agent: game-research-agent
> Date: 2026-07-23

---

## 1. 问题定义

### 当前行为

Stranger NPC 已初步实现三次出场，但对话深度不足：

1. **大厅（lobby_stranger.json）** — 简单问候对话，2–3 个选择分支，设置 `met_stranger` 标志
2. **地下通道（underpass_stranger_echo.json）** — 仅含 3 个选项的回声对话（雨主题），每个选项导向一个终点
3. **地铁站（subway_ending.json）** — Stranger 在 Keep Walking 结局中说「下次再见」

当前 Stranger 的对话仅覆盖「神秘帮手/对手」的浅层，缺乏中层（玩家镜像）和深层（自我投射/游戏即隐喻）的分层叙事结构。对话选择对结局的分支影响较弱，未充分利用现有三轴状态系统（hope/conviction/will）。

### 期望行为

实现三层真相对话树，让 Stranger 成为真正的叙事核心：

- **浅层（Shallow）**：Stranger 在地下通道提供 3 条不同对话路径，各导向不同结局方向
- **中层（Middle）**：玩家在办公室、便利店、天桥的先前选择影响 Stranger 台词和态度
- **深层（Deep）**：第二周目（或特定标志触发时）Stranger 揭示「我就是你」——游戏即隐喻的元叙事层

### 用户场景

- **场景 A：** 首次游玩玩家进入地下通道，触发 Stranger 回声对话，看到浅层 3 条路径
- **场景 B：** 玩家在不同场景做出不同选择后（如便利店买咖啡提升 hope，天桥低 conviction 触发侵入性想法），Stranger 对话内容动态变化
- **场景 C：** 玩家开启第二周目（或达成特定条件）后，Stranger 对话解锁第四层元叙事选择
- **频率：** 每次游戏必然触发（Stranger 是核心叙事 NPC），但内容因状态和标志大幅变化

---

## 2. 设计意图

### 为什么现有行为存在

原始实现（Issue #45 叙事架构）将 Stranger 设计为「玩家内心状态物理投射」，定义了 3 种外观状态（hope 高/中/低）和 3 次出场时机。但该阶段的目标是建立叙事骨架，对话树的深层内容留给了后续迭代（即当前 Issue #59）。

### 为什么现在修改

叙事架构（#45）、对话引擎（#46/#52）、地下通道场景（#58）已完成。前置依赖全部就绪。Stranger 作为游戏最核心的 NPC，其对话深度直接决定了叙事体验的完成度。

### 先前约束

- 场景线性顺序不可更改（办公室→大厅→便利店→天桥→地下通道→地铁站）
- 三轴状态系统（hope/conviction/will，0–10）是唯一的状态驱动机制
- 对话必须使用现有 JSON 格式 + Condition DSL（slider/flag/choice_made/and/or/not）
- Hemingway 风格先行：每句 ≤25 字符，每节点 ≤3 句
- 支持 2D/3D 双显示路径

---

## 3. 影响分析

### 直接影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `dialogues/underpass_stranger_echo.json` | 对话数据 | **重写** — 从 3 选项回声扩展为三层真相对话树 |
| `dialogues/lobby_stranger.json` | 对话数据 | **扩展** — 添加更多状态感知分支 |
| `dialogues/subway_ending.json` | 对话数据 | **扩展** — 添加 Stranger 对话与三层选择的映射 |
| `gdscripts/underpass.gd` | 场景脚本 | **修改** — 添加多层对话触发逻辑、状态感知入口 |
| `gdscripts/narrative_manager.gd` | 叙事管理器 | **扩展** — 添加第二周目检测、元标志传递 |

### 间接影响模块

| 文件 | 模块 | 原因 |
|------|------|------|
| `gdscripts/game_manager.gd` | 游戏管理器 | 可能需要添加 `new_game_plus` 标志或 `playthrough_count` |
| `gdscripts/state_system.gd` | 状态系统 | 可能需要添加 `playthrough` 轴或元标志支持 |
| `docs/GAME_DESIGN/06-NARRATIVE.md` | 设计文档 | 需要更新 Stranger 对话设计细节 |

### 数据流影响

```
玩家进入地下通道 → StateSystem.get_state()（三轴状态）
                  → GameManager.choices_history（先前选择记录）
                  → NarrativeManager.echo_flags（回声触发状态）
                  → 对话引擎根据状态 + 标志 + 周目过滤对话节点
                  → 显示三层真相树中的一个或多个分支
                  → 选择影响三轴状态和结局判定
```

### 需更新的文档

- [x] `docs/GAME_DESIGN/06-NARRATIVE.md`（Stranger 对话设计章节）
- [ ] `docs/PRD/59-mysterious-stranger-npc.md`（本文档）
- [ ] `dialogues/` 下相关 JSON 文件

---

## 4. 方案比较

### 方案 A：单文件三层对话树

- **描述：** 将三个真相层全部放入 `underpass_stranger_echo.json`，通过 Condition DSL 控制隐藏/显示
- **优点：**
  - 单一文件，管理简单
  - 完整对话树一目了然
  - 条件分支已由引擎支持
- **缺点：**
  - 文件可能过大（3 层 × 3 路径 = 大量节点）
  - 元叙事层（AC3）需要特殊标志传递
- **风险：** 低 — 完全基于现有引擎能力
- **工作量：** 中等（~150 行 JSON + 场景脚本调整）

### 方案 B：多层文件 + 动态加载

- **描述：** 每层拆分为独立 JSON 文件（`underpass_stranger_shallow.json`, `underpass_stranger_middle.json`, `underpass_stranger_deep.json`），由场景脚本动态加载
- **优点：**
  - 文件模块化，易于维护
  - 深层次完全隐藏，防止数据挖掘
- **缺点：**
  - 跨层条件传递复杂（需要场景脚本协调多个对话实例）
  - 对话历史追踪困难
  - 增加场景脚本复杂度
- **风险：** 中 — 对话引擎支持单次 `start_dialogue`，多文件切换需要新工作流
- **工作量：** 高（~3 文件 + 新场景逻辑）

### 推荐

→ **方案 A**（单文件三层对话树），因为：
1. 对话引擎已支持 Condition DSL，可以优雅地在单文件内控制分支可见性
2. `start_dialogue` 设计为一次会话一个入口点，多文件切换会引入不必要的复杂性
3. 条件嵌套（`and`/`or`/`not`）足以表达三层筛选逻辑
4. AC3 的「第二周目」可通过 GameManager 的 `playthrough_count` 标志实现，对话引擎的 `flag` 条件直接支持

---

## 5. 边界条件与验收条件

### 正常路径

1. 玩家经过办公室→大厅→便利店→天桥，到达地下通道
2. 点击 Stranger 回声触发区，启动对话
3. 根据当前三轴状态 + `met_stranger` 标志，显示浅层对话入口
4. 根据先前选择（`bought_coffee`, `chatted_with_clerk`, 办公室/天桥选择记录），显示中层条件分支
5. 如果 `playthrough_count >= 2`（或特定触发条件），显示深层元叙事分支
6. 选择决定对话结束时的状态变化，最终影响地铁站结局

### 边缘情况

1. **跳过前置场景：** 如果玩家绕过某些场景（技术上不可能，因为场景线性固定），对话应有合理的默认文本
2. **极低/极高状态值：** hope ≤ 2 或 hope ≥ 9 时，Stranger 的对话应出现特殊变体（不仅是原设计 3 段外观）
3. **回声先触发：** 如果雨回声（rain_echo）已被触发，Stranger 的对话应引用之前的回声内容；如果未触发，对话应略有不同
4. **全负面选择路径：** 玩家在所有前置场景中选择负面选项（降低 hope/conviction/will），Stranger 对话应为最黑暗的变体

### 故障路径

1. **对话文件加载失败：** 场景脚本应优雅回退到默认的环境文本，不崩溃
2. **状态系统不可用：** 所有条件应默认为 `false`，显示最中性的对话分支

> 这些直接成为 Plan 阶段的测试用例骨架。

---

## 6. 依赖与阻塞

### 依赖项

| 依赖 | 状态 | 风险 |
|------|------|------|
| 地下通道场景（#58） | ✅ 已合并 | 低 |
| 对话引擎（#46/#52） | ✅ 已合并 | 低 |
| 叙事架构（#45） | ✅ 已合并 | 低 |
| 大厅 Stranger 首次相遇（#54） | ✅ 已合并 | 低 |
| 状态系统三轴 | ✅ 已存在 | 低 |

### 阻塞项

无。所有前置依赖已完成。

### 准备事项

- [x] 对话 JSON 格式与 Condition DSL 已文档化（05-DIALOGUE.md）
- [x] Stranger 角色设计已文档化（06-NARRATIVE.md 第 6 节）
- [x] 地下通道场景结构已就绪（underpass.gd, underpass.tscn）

---

## 7. Spike / 实验

### 实验 1：对话树的节点密度估算

- **待回答问题：** 三层 × 每层 3 条路径需要多少对话节点？是否在引擎「每节点最多 3 次访问」限制内？
- **方法：** 使用对话引擎现有格式，手写一个最小三层数据结构草图，计算节点数和最差遍历深度
- **预期结果：**
  - 浅层（Shallow）：~8 节点（入口 + 3 路径 × 2–3 节点/路径）
  - 中层（Middle）：~12 节点（每个前置场景增加 1–2 个条件节点 + 跨场景引用）
  - 深层（Deep）：~4 节点（触发 + 揭示 + 选择 + 反馈）
  - 总计 ~24 节点，最差遍历深度 ~8，远低于 MAX_NODE_VISITS=3 的限制（每个节点独立计数，而非对话总步数）
- **对方案的影响：** 确认单文件方案可行；如果超过 50 节点，考虑拆分为浅层+中层合并、深层独立

### 实验 2：状态传递机制原型

- **待回答问题：** 如何将玩家在 office/store/bridge 的选择传递给地下通道的 Stranger 对话？
- **方法：** 遍历现有对话 JSON，识别 office_door.json / store_clerk.json / bridge_homeless.json 中设置的 flags 和 slider_delta
  - office_door.json — 玩家离开办公室时的选择
  - store_clerk.json — 设置 `bought_coffee`, `chatted_with_clerk`, `clerk_comforted` 等标志
  - bridge_homeless.json — 需要查看其设置的 flags
  - lobby_stranger.json — 设置 `met_stranger` 标志
- **预期结果：**
  - 已有 6+ 个可追踪的 flag（`met_stranger`, `bought_coffee`, `chatted_with_clerk`, `clerk_comforted` 等）
  - 三轴状态（hope/conviction/will）本身也是前置选择的聚合器
  - **结论：** 中层对话可通过 `and` 条件的组合——`flag`（特定选择）+ `slider`（聚合状态）实现
- **对方案的影响：** 确认对话引擎条件 DSL 足够表达中层筛选逻辑，无需扩展 Condition 类型

### 实验 3：第二周目（AC3）触发机制

- **待回答问题：** 如何让引擎知道这是第二周目？
- **方法：** 检查 GameManager 和 StateSystem 的 reset() 方法，设计一个全局计数器
  - GameManager 目前有 `scene_visited`（存储已访问场景）和 `choices_history`
  - 可以在 GameManager 中添加 `playthrough_count: int`，默认为 0
  - `start_game()` 时递增
  - 对话引擎的 `flag` 条件可以检查 `playthrough_count >= 2`
- **预期结果：**
  - 修改 GameManager.gd：添加 `playthrough_count` 属性和 `reset()` 时递增逻辑
  - 对话引擎无需修改——`condition: {"type": "flag", "flag": "is_new_game_plus", "value": true}` 即可
  - 场景脚本在对话启动前设置 `is_new_game_plus` 标志
- **对方案的影响：** 低风险，对 GameManager 的修改很小。如果不想修改 GameManager，可以改用 `completed_endings` 检测（`ending_keep_walking` / `ending_turn_back` / `ending_stay` 至少一个为 true 时解锁深层对话）

---

## 8. 延续上下文

> *本节是 activeForm 传递给下一个 agent（plan → implement）的手签信息。*

Stranger NPC 对话区域目前位于 `scenes/underpass/`，通过 `underpass.gd` 管理。该场景已有：
- `stranger_echo_trigger`（Area3D）— 触发 Stranger 对话入口
- `NarrativeManager.trigger_echo("rain_echo")` — 在对话前触发回声
- `start_dialogue("res://dialogues/underpass_stranger_echo.json", "underpass_stranger_echo")` — 启动对话

现有 `underpass_stranger_echo.json` 是一个简单的 3 选项回声对话（73 行），将被重写为三层真相对话树。新对话树使用现有的 Condition DSL（`slider`, `flag`, `choice_made`, `and`, `or`, `not`）进行分支控制。

中层条件利用 GameManager 中已有标志：`met_stranger`, `bought_coffee`, `chatted_with_clerk`, `clerk_comforted` 等。

深层条件需要 GameManager 中添加 `playthrough_count` 属性（或通过 `completed_endings` 标志组合检测）。

三轴滑块作用（stranger_echo 选择的 effects）：
- Keep Walking 路径：`hope +1, conviction +1, will +1`
- Stay 路径：`hope +0, conviction -0.5, will +0`
- Turn Back 路径：`hope -1, conviction -1, will -0.5`

主要风险是对话树的复杂度控制——需确保每节点不超过 Hemingway 约束（3 句 × 25 字符）且对玩家不产生认知过载。
