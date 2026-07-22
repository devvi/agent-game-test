# Research: Story Content — 全场景剧本 + 三结局 (#56)

> Parent Issue: #56
> Agent: game-research-agent
> Date: 2026-07-23

---

## 1. Problem Definition

### Current Behavior

叙事架构（Issue #45, PR #96）已完全实现：NarrativeManager 管理6场景线性序列、三轴状态系统（hope/conviction/will）、回声系统、结局判定引擎。对话引擎（Issue #46, #52）已实现数据模型、条件分支运行时、3D 显示层。7个 JSON 对话文件已就位。

**但剧本内容尚不完整：**
- 对话 JSON 文件已有基础结构，但部分文件偏短（如 `bridge_homeless.json` 仅1个节点），缺少深层文本层
- 环境文本已有三态变体（hope/neutral/despair 等），但覆盖率需要审核和扩充
- 互文性（Intertextuality）目前仅2个回声（rain_echo, screensaver_echo），未达到5处的要求
- 三结局已有基础文本，但情感弧线不够鲜明，需按「Keep Walking=信念」「Turn Back=放弃」「Stay=接纳」深化
- Hemingway 约束（最多3句、每句最多25字符）需在所有文本中落地执行

### Expected Behavior

按 Issue #56 验收条件：

1. **AC1 (Shallow):** 所有6场景实现对话和环境文本100%覆盖。每个场景的每个交互点都有对应的文本内容。
2. **AC2 (Middle):** 至少5处互文性（跨场景的台词或意象重现），超越现有2个回声。
3. **AC3 (Deep):** 三结局各有鲜明情感弧线：
   - Keep Walking = 信念（faith）
   - Turn Back = 放弃（give up）
   - Stay = 接纳（acceptance）

### User Scenarios

- **场景 A:** 玩家从头到尾完整游玩一次，希望每个交互点都有内容反馈，没有空白
- **场景 B:** 玩家在不同状态下触发相同交互，看到不同文本（三态变体生效）
- **场景 C:** 玩家在不同结局中感受到不同情感体验，而非仅仅是文字变化
- **频率:** 每次游玩 — 这是核心内容产出，不是边缘功能

---

## 2. Design Intent

### Why Does Current Behavior Exist?

Issue #45 和 #52 专注于建立叙事架构和对话引擎的**技术基础设施**（代码、管线、数据格式）。实际的剧本内容填充计划在 Issue #56 中进行，这是按路线图划分的合理阶段分离。

### Why Change Now?

基础设施已完成。现在需要内容来驱动基础设施。没有完整的剧本，游戏体验不完整，无法进行有效的 QA 测试。Issue #56 是 content 标签的最后一个关键内容产出。

### Previous Constraints

以下约束仍然有效：
- **Hemingway 约束:** 每句最多25字符，每节点最多3句。由 `HemingwayEnforcer.gd` 运行时执行
- **分层表达:** 每行至少要有 shallow（字面层）和 middle（暗图层）两层；deep 层对关键节点推荐（但不是强制）
- **三轴状态系统:** 玩家选择改变 hope/conviction/will 值，场景文本根据状态变化
- **对话引擎数据格式:** `dialogues/*.json`，使用现有 condition DSL 和 effect 系统
- **叙事体中文为主:** NPC 中文对话（Stranger 中文），Narrator 英文叙述保持混合模式

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `dialogues/office_door.json` | 对话数据 | 扩充内容，增加深层节点 |
| `dialogues/lobby_stranger.json` | 对话数据 | 扩充内容，增加状态分支 |
| `dialogues/lobby_guard.json` | 对话数据 | 扩充内容 |
| `dialogues/store_clerk.json` | 对话数据 | 扩充内容，增加环境描写 |
| `dialogues/bridge_homeless.json` | 对话数据 | **大幅扩充** — 目前只有1个节点 |
| `dialogues/underpass_stranger_echo.json` | 对话数据 | 扩充回声变体文本 |
| `dialogues/subway_ending.json` | 对话数据 | **大幅扩充** — 深化三结局情感弧线 |
| `gdscripts/store.gd` | 场景脚本 | 添加更多环境文本交互点（货架、窗外） |
| `gdscripts/office.gd` | 场景脚本 | 可能增加更多环境文本节点 |
| `gdscripts/bridge.gd` | 场景脚本 | 验证现有环境文本完整性 |
| `gdscripts/underpass.gd` | 场景脚本 | 验证回声触发完整性 |
| `gdscripts/subway_station.gd` | 场景脚本 | 验证结局触发完整性 |
| `gdscripts/narrative_manager.gd` | 叙事控制器 | 可能增加新的回声 ID |
| `gdscripts/constants.gd` | 常量 | 添加新的回声/对话路径常量 |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/dialogue_runner.gd` | 对话运行时 | 可能需要支持更复杂的条件组合 |
| `tests/test_narrative_architecture.gd` | 测试 | 需要更新测试用例以匹配新内容 |
| `docs/GAME_DESIGN/06-NARRATIVE.md` | 设计文档 | 需更新回声表和对话表 |

### Data Flow Impact

数据流仍然是线性的：`dialogue JSON → DialogueParser → DialogueRunner → DialogueDisplay3D`。内容变更不会改变数据流动方向，只需更新 JSON 文件内容即可。环境文本继续通过场景脚本的 `_configure_environmental_text()` 方法配置，从 StateSystem 读取状态值。

### Documents to Update

- [x] `docs/PRD/56-story-content-script-endings.md` (本文档)
- [ ] `docs/GAME_DESIGN/06-NARRATIVE.md` — 更新回声表、对话表
- [ ] `docs/GAME_DESIGN/05-DIALOGUE.md` — 如有新 effect 类型或条件类型
- [ ] `README.md` — 如有必要

---

## 4. Solution Comparison

### Approach A: 直接填充 — 逐文件扩展现有对话

- **Description:** 逐个编辑7个 JSON 对话文件，按照 GDD 06-NARRATIVE.md 中的叙事需求，为每个交互节点添加更多内容、状态分支和深层文本。同时更新场景脚本以增加更多交互点。
- **Pros:**
  - 直接，无需额外架构工作
  - 利用现有引擎能力，无需修改运行时
  - 容易验证覆盖率（每个场景文件对应现有交互）
- **Cons:**
  - 需要大量中文创作工作
  - 互文性需要跨文件协调
  - 需要确保 Hemingway 约束在全文中一致性
- **Risk:** Low — 内容填充风险低，主要是创作质量和一致性
- **Effort:** 3–5 个工作日（内容创作 + 审核 + JSON 编辑）

### Approach B: 先做叙事设计文档 → 再填充内容

- **Description:** 先写一份详细的剧本蓝图（每个场景的完整台词表、互文性映射表、三结局情感弧线大纲），经过 review 后再逐个文件填充到 JSON。
- **Pros:**
  - 更好的全局一致性
  - 互文性更容易规划
  - 在填充前即可审查情感弧线合理性
- **Cons:**
  - 多一步文档工作，但对 content 任务来说是合理的
  - 本质上 Approach A 也需要先做设计思考
- **Risk:** Low — 多出的步骤是预防性而非必要性
- **Effort:** 4–6 个工作日（设计文档 + 填充）

### Recommendation

→ **Approach A** 因为：现有的 GDD（06-NARRATIVE.md、05-DIALOGUE.md）已经提供了足够的叙事设计上下文。不需要额外蓝图。关键是将 AC 拆解为可执行的任务，直接逐文件扩充。需要特别注意：

1. 创作时先规划互文性映射（5+处），再写台词
2. 每段对话都检查 Hemingway 约束
3. 三结局单独编写，确保情感弧线差异化

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path (按场景顺序填充)

1. **办公室 (office_door.json):** 门对话已完整（3节点），丰富 Narrator 叙述文本和环境文本
2. **大厅 (lobby_stranger.json, lobby_guard.json):** 扩充 Stranger 初次对话的深层选择；增加保安闲聊节点
3. **便利店 (store_clerk.json):** 当前最完整（8节点），但仍需增加更多状态分支和 Stranger 前兆文本
4. **天桥 (bridge_homeless.json):** **重点扩充** — 当前仅1节点。流浪汉作为镜像对话需要多个节点
5. **地下通道 (underpass_stranger_echo.json):** 回声对话已基本完整，增加状态相关变体
6. **地铁站 (subway_ending.json):** **重点扩充** — 三结局需要各自5+节点以建立情感弧线

### 互文性至少5处（AC2目标）

| # | ID | 源点 | 重现 | 说明 |
|---|-----|------|------|------|
| 1 | rain_echo | 便利店 Stranger "雨这么大…" | 地下通道 Stranger 回声 | ✅ 已实现 |
| 2 | screensaver_echo | 办公室屏保"你做游戏有什么用？" | 天桥流浪汉 / 地下通道 | ✅ 已实现（流入流浪汉对话） |
| 3 | 时钟回声 | 办公室 Desktop "Deadline: Day X/90" | 地铁站 Clock "11:47 PM" | 新 — 跨越时间感的标尺重现 |
| 4 | 门回声 | 办公室 "门很重" | 地铁站 "检票口" 或 大厅 "出口" | 新 — 门的意象从起点到终点 |
| 5 | 雨意象 | 办公室 "Rain on the glass" | 便利店窗外 / 天桥 / 地下通道 | 新 — 雨作为贯穿意象的多重变奏 |
| 6 | Stranger 点头 | 大厅 "You nod" | 地铁站 "She nods" | 新 — 首尾呼应的 Stranger 动作 |
| 7 | 咖啡回声 | 便利店买咖啡 | 结局前的 Stranger 提到"那杯咖啡" | 新 — 玩家选择在叙事中回响 |

### 三结局情感弧线（AC3详细规划）

#### Keep Walking（信念 / Faith）

```
情感曲线: 疲惫 → 接受 → 决心 → 平静的向前
核心意象: 列车、轨道、前方灯光
Stranger 作用: 微笑告别 "下次再见"
环境: 月台温暖灯光、列车进站、雨变小或停止
Narrator 文本基调: 中性的向前叙事，带一丝温暖
```

#### Turn Back（放弃 / Give Up）

```
情感曲线: 犹豫 → 恐惧 → 自我否定 → 空洞的返回
核心意象: 关闭的门、雨中的出口、黑暗的街道
Stranger 作用: 站在隧道入口 "你确定？" — 姿态与初见一致
环境: 检票口 CLOSED、灯光变暗、雨声增强
Narrator 文本基调: 压抑的循环叙事，暗示回到原点
```

#### Stay（接纳 / Acceptance）

```
情感曲线: 迷茫 → 停顿 → 内省 → 安静的接纳
核心意象: 长椅、最后一班车、空月台
Stranger 作用: 静坐在旁，然后走入维修隧道 — 留下玩家一人
环境: 月台逐渐变空、广播渐弱、钟声回荡
Narrator 文本基调: 安静的内省叙事，非悲伤非喜悦，而是平静
```

### Edge Cases

1. **状态值在边界:** 当 hope=6.0 或 conviction=3.0 等边界值时，确保文本选择是 inclusive（>= 或 >）并合理
2. **未触发回声场景:** 如果玩家在便利店未与 Stranger 对话就直接去天桥，rain_echo 默认从中性变体触发
3. **状态值极端统一:** 当三轴均为 10.0 或均为 1.0 时，所有场景文本应合理反映极端状态
4. **击杀所有可用节点后触发剧情:** 对话引擎有 MAX_NODE_VISITS=3 保护，不能陷入循环

### Failure Paths

1. **JSON 文件名或 ID 引用错误:** 对话引擎启动时静默失败 — 必须在 PR merge 前用 `dialogue_parser.gd` 验证所有 JSON
2. **Hemingway 超限被截断:** 不是致命错误，但句子被截断后语义可能变化 — 要求所有文本创作时即满足约束

> 这些 directly become test case skeletons in Plan phase.

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|------|
| #45 — 叙事架构 | ✅ 已合并 (PR #96) | None |
| #50 — 大厅+便利店场景 | ✅ 已合并 | None |
| #51 — 天桥+地下通道+地铁站场景 | ✅ 已合并 | None |
| #55 — 办公室门+街道+便利店完整 | ✅ 已合并 | None |
| #13 — 天气系统 + 雨控制器 | ✅ 已合并 | None |
| Dialogue Engine (#46, #52) | ✅ 已合并 | None |
| HemingwayEnforcer | ✅ 已实现 | None |

### Blocks

| Future Work | Priority |
|-------------|----------|
| 无 — 这是 content 线最后一个 Issue | 最高 |

### Preparation Needed

- [ ] 确认现有 dialogue JSON 文件语言混合模式（中文 NPC / 英文 Narrator）是否与 AC 一致
- [ ] 确认 StateSystem 轴值范围 [0, 10] 和中间值 5.0 的文本映射

---

## 7. Spike / Experiment (深度要求 — 至少3项)

### Spike A: 文本密度估算 — 每场景所需台词数

**待解答问题:** 要满足「100%覆盖率」，每场景实际需要多少个对话节点和环境文本变体？

**方法:** 遍历6个场景脚本的 `_ready()` 和交互触发函数，统计当前交互点数量。结合 GDD 06-NARRATIVE.md 中的场景交互表，估算每个交互点需要的对话节点数（基础节点 + 状态分支节点）。

**预期结果:**

| 场景 | 交互点 | 当前节点数 | 目标节点数 | 环境文本变体数 |
|------|--------|-----------|-----------|--------------|
| 办公室 | 门、窗、屏保、桌面 | 3 | 3–5 | 3 (hope/neutral/despair) |
| 大厅 | 保安、Stranger、出口 | 6 | 8–12 | 3 (fear/defiant/neutral) |
| 便利店 | 店员、货架、窗外 | 8 | 10–14 | 2–3 |
| 天桥 | 栏杆、流浪汉、出口 | 4 | 6–10 | 3 (tired/determined/neutral) |
| 地下通道 | 涂鸦、Stranger回声、出口 | 5 | 6–8 | 3 (despair/resolute/neutral) |
| 地铁站 | 检票口、转身、长椅 | 6 | 10–15 | 3 (forward/backward/waiting) |

**影响:** 如果估算显示某个场景需要大量新节点，需要优先安排该场景的创作。

---

### Spike B: 互文性映射草稿

**待解答问题:** 5+处互文性如何在不重复的前提下，让玩家在不同场景感受到「命运在呼应」？

**方法:** 为每个回声 ID 写简短的三态变体表（高状态/中状态/低状态文本），确保同一回声在不同状态下给玩家不同感受。

**预期结果:**

**回声3: 时钟回声** — 办公室桌面计时 → 地铁站时钟

| 状态 | 办公室文本 (已有) | 地铁站文本 (新) |
|------|-----------------|----------------|
| hope高 | "Deadline: Day X/90 — 还有时间" | "11:47 PM — The train is coming" |
| hope中 | "Deadline: Day X/90" | "11:47 PM — The clock ticks" |
| hope低 | "Deadline: Day X/90 — 来不及了" | "11:47 PM — Too late" |

**回声4: 门回声** — 办公室重门 → 地铁站检票口

| 状态 | 办公室文本 (已有) | 地铁站文本 (新) |
|------|-----------------|----------------|
| conviction高 | "The door is heavy. You open it." | "The gate opens. One way forward." |
| conviction中 | "The door is heavy." | "The gate stands before you." |
| conviction低 | "The door is heavy. You hesitate." | "The gate reads CLOSED." |

**回声5: 雨意象** — 持续贯穿全6场景

| 场景 | 环境文本雨引用 |
|------|--------------|
| 办公室 | "Rain on the glass" |
| 大厅（新） | "Rain drums on the lobby windows" |
| 便利店 | "Rain streams down the glass" |
| 天桥 | "Rain falls steadily" / "The rain is heavier here" |
| 地下通道（新） | "The sound of rain echoes through the tunnel" |
| 地铁站（新） | "The rain fades as you descend underground" |

**影响:** 一旦互文映射表完成，每个对话文件的创作就有了跨场景锚点，确保一致性。

---

### Spike C: 结局情感弧线原型

**待解答问题:** 如何在对话引擎限制下（3句/节点、25字/句）让三结局各有鲜明情感弧线？

**方法:** 为每结局写一个5+节点的对话链，用条件分支和效果系统构建情感曲线。在 PRD 阶段用伪 JSON 模拟，验证引擎能否承载。

**预期结果 — Keep Walking 原型链:**

```json
{
  "entry_node_id": "kw_arrive",
  "nodes": {
    "kw_arrive": {
      "speaker": "Narrator",
      "text": "The train hums in the distance.\nThe platform is nearly empty.\nYou can hear your own footsteps.",
      "choices": [{
        "text": "走向月台边缘",
        "next_node": "kw_edge",
        "effects": [{ "type": "slider_delta", "axis": "will", "delta": 0.5 }]
      }]
    },
    "kw_edge": {
      "speaker": "Stranger",
      "text": "下次再见。",
      "choices": [{
        "text": "「再见。」",
        "next_node": "kw_final",
        "effects": [{ "type": "set_flag", "flag": "ending_keep_walking", "value": true }]
      }]
    },
    "kw_final": {
      "speaker": "Narrator",
      "text": "The doors slide open.\nYou step in and find a seat.\nThe rain streaks past as the train pulls away.",
      "choices": [{ "text": "(End)", "next_node": null }]
    }
  }
}
```

**影响:** 如果原型验证可行，每条结局线都将按此模式构建5+节点链，通过 choice 和 effect 系统驱动情感曲线。

---

## 8. Continuation Context

> *This section is the activeForm handoff to the next agent (plan → implement).*

当前叙事内容系统有6个场景脚本、7个对话 JSON 文件和完整的叙事架构基础设施。场景脚本通过 `_configure_environmental_text()` 配置三态环境文本，通过 `start_dialogue()` 触发对话。对话引擎使用 JSON 格式的条件分支系统，支持 slider 检查、flag 设置、slider_delta 效果和组合条件。Hemingway 约束由 `HemingwayEnforcer.gd` 运行时强制。

待实施的内容填充工作将主要修改 `dialogues/` 目录下的7个 JSON 文件，以及可能扩展 `gdscripts/store.gd` 的交互点。主要风险是：

1. **跨文件互文性一致性** — 5+处回声需要在不同 JSON 文件中使用一致的台词片段。建议在创作时同时打开所有相关文件，确保用词一致
2. **Hemingway 约束下的情感表达** — 25字符/句的限制对中文台词特别严格。建议创作时以短语为单位，而非完整句子
3. **三结局情感弧线差异化** — 三条线共享同一个叙事框架但需要完全不同的情感基调。建议每条线单独编写，最后统一验证

实施顺序建议：
1. 先扩充 bridge_homeless.json 和 subway_ending.json（最薄弱的两个）
2. 再扩展现有其他对话文件
3. 最后添加新的互文性回声（3–5）
4. 全局验证 Hemingway 约束和状态变体覆盖率
