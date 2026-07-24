# Research: 场景间导航机制设计 (#221)

> Parent Issue: #221
> Agent: game-research-agent
> Date: 2026-07-25

---

## 1. Problem Definition

### Current Behavior

《雨夜普罗摩茨》当前已实现两层场景切换机制：

1. **对话驱动切换（Issue #55, #156）**：玩家点击 Area3D 触发器 → 对话面板打开 → 选择携带 `"scene"` 元数据的对话选项 → `SceneManager.trigger_scene_change()` 触发过渡动画（0.5s 淡出 → `change_scene_to_file()` → 0.5s 淡入）

2. **ExitZone 区域过渡（Issue #156）**：`ExitZone` Area3D 组件支持 AUTO（走入即触发）和 EKEY（走近按 E 键触发）两种模式，通过 `GameManager.target_spawn_point` 设置目标位置

3. **场景序列**：由 `NarrativeManager.SCENE_ORDER` 定义：`office → lobby → convenience_store → bridge → underpass → subway_station`

4. **三条叙事路线**（Issue #214）：Keep Walking（向前走）、Turn Back（回头）、Stay（停留），由 `NarrativeManager.determine_ending()` 在 subway_station 根据 hope/conviction/will 阈值判定

**但当前系统缺乏以下核心导航设计：**

| 缺失项 | 说明 | 影响 |
|--------|------|------|
| **玩家导引** | 玩家进入新场景后，没有任何视觉或文本指示告知「下一步该往哪走」 | 玩家在3D空间中迷路，不知道门/出口位置 |
| **路线可视化** | 没有路径图、场景缩略图或文本描述来展示整体场景序列和路线分支 | 玩家无法感知「旅程」的全局结构 |
| **卡住/死亡回退** | 玩家掉出地图、卡在几何体、或进入不正常状态时，没有任何 fallback 机制 | 玩家被迫重启游戏 |
| **导航与叙事结合** | 场景切换时没有过渡文本（如场景名称、路线指示） | 场景切换缺乏叙事连贯性 |
| **路线分歧的前置展示** | 三条路线的分歧点（C04 天桥的选择）没有前置提示玩家即将面临路线选择 | 玩家可能无意识地进入一条路线 |

### Expected Behavior

根据 Issue #221 验收条件：

1. **AC1:** 输出本文档 `docs/PRD/221-scene-navigation-mechanism.md`
2. **AC2:** 定义玩家如何从场景 A 到场景 B 的导航方式——点击路径点 / 选择按钮 / 自动推进 / 物理行走的混合模式
3. **AC3:** 每条路线的场景序列地图——每个场景的进入/退出条件
4. **AC4:** 导航可视化方案——路径示意图 / 场景缩略图 / 纯文本描述的选择与设计
5. **AC5:** 定义死后/卡住时的 fallback 方案

### User Scenarios

- **Scenario A（首次游玩）:** 玩家从办公室开始，不知道门在哪、不知道去哪。需要微妙的导引——既不破坏沉浸感，又能让玩家自然地走向出口。
- **Scenario B（多周目玩家）:** 玩家已经知道整体路径，但有意识地选择不同的路线。需要看到路线分歧位置和当前路线状态。
- **Scenario C（卡住/死亡）:** 玩家掉出商店场景的地面边界、或在天桥边缘卡住。需要优雅的 fallback，不破坏叙事流。
- **Frequency:** 每次场景切换都会触发导航系统。每条游玩流程约 6+ 次场景切换。

---

## 2. Design Intent

### Why Does Current Behavior Exist?

当前导航设计的缺失源于以下历史原因：

| 原因 | 说明 | 相关 Issue |
|------|------|-----------|
| 场景过渡优先于导航 | 先实现了"怎么切换场景"（ExitZone），还没设计"怎么引导玩家到出口" | #156 |
| 3D 空间尚未完成 | 各场景的 3D 布局（街道宽度、门的位置、出口标记）仍在建设中，无法提前设计导引 | #151 |
| 叙事架构刚完成 | 三条路线和叙事弧线的设计（#214）刚刚交付，路线感知的导航需基于此设计 | #214 |
| PlayerController 刚就绪 | WASD 移动 + 鼠标视角（#142）刚完成，自由的 3D 移动带来了导航需求 | #142 |

### Why Change Now?

1. **叙事路线已定义** — Issue #214 明确了三条路线的场景序列和关键选择点。导航系统可以基于此设计路线感知的引导。

2. **场景空间布局已定义** — 各场景的 3D 空间布局和出口位置已有设计（#151），可以为每个出口设计导引标识。

3. **MVP 即将整合** — Issue #158 MVP 集成测试需要完整的游玩流程，导航是玩家体验的核心环节。

4. **卡死 bug 影响测试** — 没有 fallback 机制，玩家卡住时只能重启，严重影响 playtest 效率。

### Previous Constraints

| 约束 | 说明 | 来源 |
|------|------|------|
| 博尔赫斯风格约束 | 导航引导不能破坏「不可靠叙述」（B1）——不能有明确的「→ 出口」箭头或元游戏提示 | #214 (B1-B6) |
| 玩家自由度 | 玩家可以自由移动（WASD）和视角控制（鼠标），不能强制玩家沿固定路径前进 | #142 |
| Hemingway 约束 | 任何导航文本必须遵循 25 字符/句、3 句/节点限制 | #51 |
| 三层表达 | 导航设计必须支持 L1（字面出口指示）、L2（暗示性导引）、L3（象征性路径）三层 | #214 |
| 场景切换机制 | 必须使用現有 `SceneManager` fade-out/fade-in 管道和 `ExitZone` 机制 | #156 |
| 现有过渡通道 | ExitZone 已采用 AUTO / EKEY 双模式，导航设计需在此之上构建引导 | #156 |
| 叙事一致性 | 每条路线的导航风格应该与路线的情感基调匹配（Keep Walking → 向前指引；Turn Back → 暗示后退） | #214 |

---

## 3. Impact Analysis

### Directly Affected Modules

| File | Module | Nature of Change |
|------|--------|------------------|
| `gdscripts/scene_base.gd` | SceneBase | **修改** — `_ready()` 中增加进入场景时的导航文案显示（场景名、区域描述、暗示性方向） |
| `gdscripts/scene_manager.gd` | SceneManager | **修改** — `trigger_zone_transition()` 和 `trigger_scene_change()` 增加过渡时的场景名称展示（淡出期间的场景标题卡） |
| `docs/DESIGN/2-narrative-architecture.md` | 叙事设计文档 | **新建** — 导航设计作为叙事架构的一部分纳入设计文档 |
| `scenes/office/office.tscn` | 办公室 | **修改** — 添加出口视觉引导（灯光/环境装饰暗示出口方向） |
| `scenes/street/street.tscn` | 街道 | **修改** — 添加路径引导元素 |
| `scenes/store/convenience_store.tscn` | 便利店 | **修改** — 添加出口视觉引导 |
| `scenes/bridge/bridge.tscn` | 天桥 | **修改** — 添加方向引导（天桥两端分别指向 store 和 underpass） |
| `scenes/underpass/underpass.tscn` | 地下通道 | **修改** — 添加出口光引导 |
| `scenes/subway_station/subway_station.tscn` | 地铁站 | **修改** — 路线分歧终点视觉设计 |
| `scenes/lobby/lobby.tscn` | 大厅 | **修改** — 添加 Stranger 引导（Stranger 位置暗示前进方向） |

### New Files Needed

| File | Purpose |
|------|---------|
| `gdscripts/scene_title_overlay.gd` | **新建** — 场景切换时的过渡覆盖层：显示场景名、当前路线状态、简短描述 |
| `gdscripts/navigation_fallback.gd` | **新建** — 检测玩家卡住/掉落，触发回退重定位 |
| `references/scene-flow-diagrams.md` | 路线场景序列的 ASCII 路径图参考 |

### Indirectly Affected Modules

| File | Module | Why Affected |
|------|--------|--------------|
| `gdscripts/player_controller.gd` | PlayerController | 可能需增加 fallback 检测（检测高度阈值、速度异常） |
| `gdscripts/game_manager.gd` | GameManager | 可能需要存储"上次场景名"和"当前导航提示" |
| `gdscripts/exitzone.gd` | ExitZone | 可能需增加 `exit_label: String` 属性，用于过渡场景标题 |
| `dialogues/*.json` | 对话数据 | NPC 对话中可加入方向性提示（间接导航） |

### Data Flow Impact

**当前场景过渡流程：**

```
玩家走入 ExitZone（或选择对话选项）
  → body_entered / _on_choice_made
    → GameManager.target_spawn_point = zone.spawn_point（ExitZone 模式）
    → SceneManager.trigger_scene_change(target_scene)
      → fade_out (0.5s) → change_scene_to_file → fade_in (0.5s)
      → SceneBase._instantiate_player() at SpawnPoint
```

**添加导航后的过渡流程：**

```
玩家走入 ExitZone
  → body_entered
    → ExitZone 设置 GameManager.navigation_context = {exit_label, route_hint, next_scene}
    → GameManager.target_spawn_point = zone.spawn_point
    → SceneManager.trigger_scene_change(target_scene)
      → fade_out (0.5s)
        → SceneTitleOverlay 显示场景名 + 路线上下文（淡出期间）
      → change_scene_to_file
      → fade_in (0.5s)
      → SceneBase._ready()
        → 根据 scene_id 显示环境引导文案
        → _instantiate_player() at SpawnPoint
        → 如果 scene_id 为关键选择点场景 → 显示路线分歧提示（可选）
```

### Documents to Update

- [x] **本文档:** `docs/PRD/221-scene-navigation-mechanism.md`
- [ ] `docs/DESIGN/2-narrative-architecture.md` — 将导航设计纳入叙事架构设计文档
- [ ] `docs/GAME_DESIGN/02-WORKFLOW.md` — 添加导航系统说明
- [ ] `references/scene-flow-diagrams.md` — 新创建 ASCII 场景流图

---

## 4. Solution Comparison

### Approach A: 环境嵌入式导引（微妙的视觉引导 + 环境文本）

**描述：**

利用 3D 环境的视觉元素引导玩家自然走向出口，不依赖 UI 箭头或元游戏提示。每种场景使用符合氛围的引导手法：

- **光源引导：** 出口方向设置更亮的光源（路灯、室内灯光透过门缝、隧道出口的光晕）
- **环境文本引导：** 出口附近的环境文本包含方向性暗示（「门上的牌子写着 EXIT」「地上的箭头形裂纹」）
- **NPC 间接引导：** NPC 对话中包含方向提示（「他指了指街道尽头」「那扇门通向外面」）
- **声音引导：** 出口方向有环境声渐变（雨声渐强/弱、街道声音接近）

场景切换时，在淡出期间显示简短场景标题卡（例如：「— 街道 — / 雨夜的东区街道 / 便利店的光在前方闪烁」），在叙事上连接场景。

**视觉引导方案细节：**

| 场景 | 出口位置 | 引导手法 | 具体实现 |
|:----:|:--------:|---------|---------|
| 办公室 | 门 | 光源 + 文本 | 门缝透光、门上 EXIT 标牌、窗外的路灯映照 |
| 大厅 | Stranger 旁的门 | NPC 姿态引导 | Stranger 朝向出口站立、目光方向引导 |
| 便利店 | 后门/街道出口 | 光源 + 声音 | 后门安全出口绿光、街道声音渗透 |
| 天桥 | 两端 | 光源 + 视觉焦点 | 一端城市灯光、一端广告牌光晕 |
| 地下通道 | 两端出口 | 光源 + 声音渐变 | 出口光晕逐渐增大、回声音调变化 |
| 地铁站 | 月台/出口 | 多层引导 | 站牌指示、往月台的箭头地砖、列车声音 |

**Pros:**
- 完全符合博尔赫斯风格——没有破坏沉浸感的 UI 元素
- 利用现有场景组件（灯光、文本、NPC），无需大量新资源
- 三层表达自然实现：L1（灯光）、L2（环境文本暗示）、L3（路线主题与光的关系）
- 每条路线可以有不同的引导风格（Keep Walking → 光向前；Turn Back → 光向后）
- 无需新增 UI 系统，对现有代码侵入最小
- 对无导航障碍的玩家（多次游玩）完全无干扰

**Cons:**
- 视觉障碍玩家可能无法感知环境引导（需要补充音频描述）
- 对不熟悉 3D 游戏的玩家可能不够明显
- 需要每个场景手动调整灯光和文本位置
- 引导效果依赖场景美术完成度，场景未完成时引导不可用
- 无法在纯文本模式（如无障碍模式）下使用

**Risk:** 🟢 Low — 充分利用现有环境组件，仅需配置和少量脚本修改。不改变核心切换逻辑。

**Effort:** Medium（3-5天用于所有场景的引导配置 + 过渡覆盖层 + fallback 系统）

---

### Approach B: UI 叠加式导引（路径点 + 场景缩略图 + 文本导航）

**描述：**

在游戏 UI 层面添加显式导航元素，類似步行模拟器的导航系统：

- **方向指示器：** 画面边缘的淡入/淡出箭头指向最近的出口或路径点
- **场景缩略图导航菜单：** 按 Tab/M 键打开半透明场景缩略图（俯视图或示意图），显示所有出口和玩家位置
- **文本路线描述：** 场景加载时在 CanvasLayer 上显示「左边是便利店后门，前方通向天桥」的文本描述
- **路径点标记：** 场景中放置半透明发光路径点 Marker3D（类似「检查点」标记）

**Pros:**
- 对所有玩家清晰可见，降低迷路概率
- 无障碍友好（视觉、文本、音频多通道输出）
- 场景缩略图可以作为叙事工具（L3：地图上的标记变化反映玩家状态）
- 多周目玩家可以直接导航到目标场景
- 实现不依赖场景美术完成度

**Cons:**
- **与博尔赫斯风格冲突** — 明确的 UI 路径点破坏「不可靠叙述」和现实-幻觉界限模糊。一条不可靠的路径展示路径点会削弱叙事张力。
- UI 叠加增加新系统（mini-map、路径点渲染、缩略图生成），增加 MVP 的 scope
- 场景缩略图需要为每个场景创建俯视图或等轴测图——额外美术工作
- 缩略图在路线分歧场景会显示路径分支，提前剧透路线结构
- 多周目玩家的路径点标记可能破坏首次游玩的「迷失感」——这正是游戏叙事想要的体验

**Risk:** 🟡 Medium — 与现有叙事风格冲突，需要权衡引导强度和沉浸破坏。额外的 UI 系统增加维护负担。

**Effort:** High（5-8天用于 UI 系统、路径点渲染、缩略图制作、场景集成）

---

### Approach C: 混合模式 — 环境引导为主 + 条件性文本辅助

**描述：**

结合 Approach A 和 B 的优势，以环境引导为主，在特定条件下提供文本辅助：

**默认状态（环境引导模式）：**
- 完全依赖 Approach A 的光源、文本、NPC 引导
- 场景切换时仅显示场景标题卡
- 不显示 Mini-map 或箭头

**触发条件启用文本辅助：**
- 玩家在场景中停留超过 60 秒 → 画面边缘出现微弱光晕指向出口方向
- 玩家面向错误方向超过 30 秒 → 环境文本更新为更明确的指示（如涂鸦改为「there, that way」）
- 玩家按 H（提示键）→ 当前场景的简短文字描述（「门在你身后的方向 / 便利店的光在街道尽头」）
- 卡住检测触发 → 显示「按 X 回到安全位置」的提示

**路线感知的文本辅助：**
- Keep Walking 路线：文本推动向前（「前方是街道尽头」「再走一段」）
- Turn Back 路线：文本暗示不确定（「也许该回头？」「前面……似乎没有路了」）
- Stay 路线：文本中立（「这里也可以」「停一停，看一看」）

**Pros:**
- 默认状态下 100% 符合博尔赫斯风格——没有破坏性 UI
- 条件触发机制只在玩家需要时提供辅助，不影响沉浸感
- 提示键（H）给玩家控制权——想迷路的玩家可以不按
- 路线感知的文本辅助强化叙事一致性
- 卡住检测提供显式 fallback，不需要 UI 系统
- 可使用现有 `TextComponentBase` 和 `lamppost_text` 系统

**Cons:**
- 条件检测逻辑增加复杂度（方向检测、停留时间、卡住检测）
- 60 秒/30 秒阈值需要在 playtest 中调优
- 环境引导（光、声音）仍然依赖场景完成度
- 按 H 提示需要实现一个新的信号/输入绑定
- 无障碍玩家可能需要更明确的辅助（如屏幕阅读器输出）

**Risk:** 🟢 Low — 每个子组件都已在现有系统中找到对应模式（`EKeyTrigger` 的 proximity 检测、`ExitZone` 的条件触发、`TextComponentBase` 的文本更新）。

**Effort:** Medium（4-6天 — 环境引导配置 + 条件检测脚本 + 提示键文本 + fallback 系统）

---

### Recommendation

→ **Approach C（混合模式）** 因为：

1. **叙事一致性优先** — 默认无 UI 的环境引导完全符合博尔赫斯风格的「不可靠叙述」（B1）和「现实-幻觉界限模糊」（B3）。明确的 UI 导航会破坏游戏的核心美学。

2. **玩家可选的辅助** — 提示键（H）让需要导航的玩家主动获取帮助，不干扰不需要的玩家。这与游戏「文学实验」的定位一致——不是所有玩家都需要或想要导航。

3. **路线感知的差异化** — 三条路线的情感弧线不同，导航文本应反映这一点。Keep Walking 的「向前推」、Turn Back 的「暗示回头」、Stay 的「允许停留」——这些通过环境文本的变化自然实现，不需要额外的系统。

4. **卡住回退的必需性** — 无论选择哪种引导方案，fallback 机制（检测掉落/卡住 → 重定位到 SpawnPoint）都是必需的。Approach C 的卡住检测逻辑同时服务于导航辅助和回退需求。

5. **渐进实现路径** — 可以分阶段实现：
   - **Phase 1（MVP 必需）:** 场景标题卡 + 卡住回退
   - **Phase 2（MVP 推荐）:** 环境引导配置（灯光/文本） + 条件检测
   - **Phase 3（后续）:** 提示键文本 + 路线感知差异化

**关键设计决策：**

| 决策 | 选择 | 理由 |
|:----:|:----:|:----:|
| 导航默认状态 | 无 UI | 保持沉浸感，符合博尔赫斯风格 |
| 辅助触发条件 | 停留 >60s / 错误方向 >30s / 按 H 键 | 玩家控制权 + 防止迷路 |
| 卡住检测方式 | 高度阈值 + 速度异常检测 | 复用 PlayerController 的物理检测 |
| 场景标题卡 | 淡出期间显示（0.5s） | 利用现有 fade 动画窗口，不增加加载时间 |
| 路线感知 | 通过 SceneBase 的 tone 系统驱动 | 现有 5-state tone 系统可直接扩展 |
| 关键选择点提示 | 场景入口处的沉浸式环境文本 | 不破坏选择点的自然感 |

---

## 5. Boundary Conditions & Acceptance Criteria

### Normal Path

- [x] **AC1: 定义导航方式** — 输出本文档
- [x] **AC2: 场景 A → B 导航** — 混合模式：默认环境引导（光/文本/NPC），条件触发文本辅助（60s/30s/H键）
- [x] **AC3: 场景序列地图** — 以下 Route Sequence Maps 详细定义每条路线的场景顺序和进入/退出条件
- [x] **AC4: 导航可视化方案** — 采用路径示意图（ASCII）和场景标题卡，不使用 UI 缩略图
- [x] **AC5: 死亡/卡住 fallback** — 检测高度阈值 (< -10) 或速度异常（连续 5s < 0.01 m/s 且非对话中）→ 重定位到场景 SpawnPoint + 淡入回退

### Route Sequence Maps

#### 路线 A: Keep Walking（向前走）

| # | 场景 ID | 进入条件 | 退出条件 | 出口位置 | 导航引导 |
|:-:|:--------:|:--------:|:--------:|:--------:|:--------:|
| 1 | office | 游戏开始 | 对门对话选择「出去」或走近门 E 键 | 办公室门 | 门缝光、窗外路灯、EXIT 标牌 |
| 2 | lobby | office 出口自动 | 走近 Stranger 旁的门 | 大厅侧门 | Stranger 朝向暗示、出口光 |
| 3 | street | lobby 出口自动 | 走近便利店入口 | 便利店门 | 便利店灯光、街道尽头光、门头招牌 |
| 4 | convenience_store | 进入便利店门 | 走近后门出口 | 后门 / 街道门 | 后门安全出口绿光、街道声音渗透 |
| 5 | bridge | 经过天桥入口 | 走到天桥另一端 | 天桥另一端 | 前方城市灯光、桥的线性引导 |
| 6 | underpass | 天桥另一端 Auto | 走到隧道另一端 | 隧道另一端 | 出口光晕、回声音调变化 |
| 7 | subway_station | 隧道出口 Auto | 与 Stranger 对话 → 选择结局 | — | Stranger 在月台的姿态、列车灯光 |

#### 路线 B: Turn Back（回头）

| # | 场景 ID | 进入条件 | 退出条件 | 出口位置 | 导航引导 |
|:-:|:--------:|:--------:|:--------:|:--------:|:--------:|
| 1 | office | 游戏开始 | 对门对话选择「再看一眼窗外」或犹豫 | 办公室门 | 窗的天空、反方向的室内灯光 |
| 2 | lobby | office 出口 | 绕过 Stranger 继续前进 | 返回办公室的门 | 来路的光、脚步声的回响 |
| 3 | street | lobby 出口 | 到达天桥中部后选择回头 | — | 回头时来路的光特别亮 |
| 4 | underpass (回溯) | 天桥回头后 | 走回办公室 | 返回 office | 回声变异、Stranger 质疑 |
| 5 | office (终点) | 回溯结束 | — | — | 时钟同时间、循环暗示 |

#### 路线 C: Stay（停留）

| # | 场景 ID | 进入条件 | 退出条件 | 出口位置 | 导航引导 |
|:-:|:--------:|:--------:|:--------:|:--------:|:--------:|
| 1 | office | 游戏开始 | 缓慢走向门 | 办公室门 | 中性的光、安静的环境 |
| 2 | lobby | office 出口 | 在中途停留观察 | — | 停留本身是选择 |
| 3 | street | 继续前进 | 在街道中段停下 | — | 场景中的长椅、安静角落 |
| 4 | convenience_store | 进入 | 在店内停留 | — | 店员安静注视、雨声成背景 |
| 5 | bridge | 继续前进至天桥 | 在天桥中部停下 | 天桥栏杆 | 雨落栏杆的节奏、两侧灯光 |
| 6 | underpass | 走过天桥 | 不再寻找出口 | — | 通道回声不在恐怖 |
| 7 | subway_station | 继续走到终点 | 不上下车 | — | 空月台、长椅、最后一班车的广播 |

### Edge Cases

1. **玩家进入场景后立即回头：** 玩家走进新场景，转身就走回 ExitZone。ExitZone 的 0.5s 延迟监控 + transition_in_progress 防止重复触发。应允许反向过渡正常触发（不抑制）。

2. **多出口场景中玩家选择错误出口：** 例如在 street 应该去 store 但走向了 bridge 方向。当前场景序列没有阻止玩家反向走的逻辑。如果玩家到达终点场景（subway_station）时未满足路线条件，NarrativeManager 应有默认路线（Stay）。

3. **场景中没有可见出口（美术未完成）：** 环境引导不可靠。此时卡住检测 + 提示键（H）提供文本描述作为保险。

4. **玩家在场景切换动画期间移动输入：** fade-out 期间玩家的移动输入不应影响场景加载。PlayerController 在 dialogue_active = true 时已禁用移动，但场景过渡期间可能状态不对。需确保 transition_in_progress 时禁用输入处理。

5. **玩家在 ExitZone 边界来回走（快速 A/D 摇摆）：** body_entered/body_exited 会频繁触发。EKEY 模式下，prompt 闪烁。**缓解：** EKEY 模式的 prompt 显示后 1s 内不消失，即使 body_exited 也延迟隐藏。

6. **三条路线在 subway_station 的结局触发条件重叠：** 当前 `NarrativeManager.determine_ending()` 的优先级顺序（Turn Back > Keep Walking > Stay）可能在一个转折点上产生非预期结果。导航系统的路线感知只反映 NarrativeManager 的判定，不应自行决定路线归属。

7. **无障碍玩家无法感知环境引导：** 视觉引导（灯光、文本）对视力障碍玩家不可用。提示键（H）的文本输出应同时通过音频通道传达。

### Failure Paths

1. **玩家掉落出地图边界：** PlayerController 的 `global_position.y < -10` 检测 → 触发 `SceneBase._on_player_fell()` → 淡出 → 重定位到场景 SpawnPoint → 显示回退文本「……刚才有些恍惚？/ 我已经站在这里了。」→ 淡入。

2. **玩家卡在几何体内部：** PhysicsBody 的 `move_and_slide()` 已处理多数几何体卡住。极端情况（两个碰撞体之间的缝隙）可通过连续 3s 速度 < 0.01 m/s 检测触发回退。回退前检查 `dialogue_active`（对话中不触发）。

3. **ExitZone 目标场景文件不存在：** 目前 `SceneManager.trigger_scene_change()` 已有 `FileAccess.file_exists(target_scene)` 检查。如果场景不存在，日志错误 + transition_in_progress = false，玩家留在当前场景。

4. **回退循环（fallback 后又立即掉落）：** 如果 SpawnPoint 本身在掉落区域（场景 layout bug），回退会导致无限循环。**缓解：** fallback 计数器。连续 3 次 fallback 后，强制加载到 `title_screen.tscn`。

---

## 6. Dependencies & Blockers

### Depends On

| Dependency | Status | Risk |
|------------|--------|:----:|
| `SceneManager` — fade 管道和触发机制 | Stable | Low |
| `SceneBase` — `_instantiate_player()`, `_get_player_spawn_position()` | Stable | Low |
| `ExitZone` — 区域检测、AUTO/EKEY 模式 | Stable | Low |
| `PlayerController` — WASD移动、fallback检测接入点 | Stable | Low |
| `GameManager` — `target_spawn_point`, `transition_in_progress` | Stable | Low |
| `NarrativeManager.SCENE_ORDER` — 场景序列定义 | Stable | Low |
| `NarrativeManager.determine_ending()` — 路线判定 | Stable | Low |
| Issue #214 — 叙事架构（3条路线、5-state tone、关键选择点） | **CLOSED** ✅ | None |
| Issue #156 — ExitZone 场景过渡系统 | **MERGED** ✅ | None |
| 所有 8 个场景 `.tscn` 文件 | Stable | Low |
| Issue #151 — 场景空间布局（出口位置、碰撞体） | 可能未完成 | **High** — 无出口位置则无法放置引导 |

### Blocks

| Future Work | Priority |
|-------------|:--------:|
| 场景过渡时的叙事文案（场景名、路线上下文） | P0（MVP 必需） |
| 卡住/掉落 fallback 回退 | P0（MVP 必需） |
| 环境引导配置（各场景灯光/文本修改） | P0（MVP 必需） |
| 条件触发检测（停留>60s / 错误方向>30s） | P1（MVP 推荐） |
| 提示键（H）文本辅助 | P1（MVP 推荐） |
| 路线感知的导航文本差异化 | P2（后续） |
| 场景缩略图导航菜单 | P3（后续，非 MVP） |

### Dependencies Chain

```
#214 叙事架构（三条路线、5-state tone、选择点）
  → #156 ExitZone 场景过渡
    → #151 场景空间布局
      → #142 PlayerController WASD 移动
        → #221 场景导航机制 ← YOU ARE HERE
          → #158 MVP 集成测试（需要完整导航路径）
```

### Preparation Needed

- [ ] 确认各场景的出口位置 3D 坐标（为 ExitZone 配置）
- [ ] 确认 fade-out/fade-in 动画期间有足够的 hook 点插入场景标题卡
- [ ] 确认 PlayerController 有 `velocity` 可读属性用于卡住检测
- [ ] 定义场景标题卡的具体文案（每个场景的中文名 + 路线提示）
- [ ] 编写 fallback 检测逻辑（高度阈值 -10、速度异常检测、连续检测窗口）
- [ ] 定义「提示键（H）」的输入绑定，避免与现有输入冲突

---

## 7. Spike / Experiment（Optional — depth/standard only）

Skipped per depth/standard label. 导航系统的技术不确定性低——ExitZone 模式已成熟，环境引导是配置问题而非引擎问题，fallback 检测可以基于现有的 PhysicsBody 属性。

---

## 8. Continuation Context

> *本节是向 plan agent 的活跃交接（activeForm handoff）。*
> *它捕捉功能区域的当前状态，使 plan agent 无需重新扫描所有源文件即可接手。*

### 当前状态

《雨夜普罗摩茨》的导航系统目前处于**基础设施就绪但设计空白**的状态：

- **场景过渡健全：** `SceneManager`（淡出/淡入，0.5s）、`SceneBase`（instantiate_player + spawn point）、`ExitZone`（AUTO/EKEY 双模式）、`GameManager`（状态持久化）——全部稳定运行
- **叙事序列已知：** `NarrativeManager.SCENE_ORDER` → 6 场景线性序列 + lobby 分支 → 3 路线结局
- **导航设计空白：** 玩家进入场景后没有引导、没有路线可视化、没有 fallback 机制

### 实施代理的关键事实

- **6+1 场景**（office, lobby, street, convenience_store, bridge, underpass, subway_station），每个场景继承 `SceneBase`
- **ExitZone** 已配置在部分场景（如 street→store 方向），但并非所有场景都有双向 ExitZone
- **PlayerController** 已有 `_dialogue_active` 状态、`velocity`（从 `CharacterBody3D` 继承）、`interaction_requested` signal
- **SceneManager** 在每个场景中是子节点（非 autoload），通过 `$SceneManager` 访问
- **transition_in_progress** 通过 `GameManager` 传播（#148 修复）
- **5-state tone** 系统（#50）——scene_text_changed signal → 动态更新环境文本——可作为路线感知导航的基础

### 核心架构决策（Approach C）

1. **默认无 UI** — 使用环境光、文本、NPC 姿态作为隐式导引
2. **条件辅助** — 玩家停留 >60s / 面向错误方向 >30s / 按 H 键 → 显示文本提示
3. **路线感知** — 文本内容联动 `NarrativeManager` 的路线判定
4. **Fallback** — 高度检测 (< -10) + 速度异常 → 淡出 → SpawnPoint 重定位 → 淡入

### 主風險

1. **场景出口位置未定义（#151 可能未完成）** — ExitZone 的放置位置未确定之前，环境引导的灯光/文本无法配置。这是最大的瓶颈。
2. **条件触发的阈值调优** — 60s/30s 阈值需要在 playtest 中验证。太短则频繁触发破坏沉浸感，太长则对迷路玩家无帮助。
3. **路线感知与叙事一致性** — 导航文本的内容必须与 `NarrativeManager._calculate_tone_for_scene()` 输出的 tone 一致，否则产生叙事矛盾。

### 下一步

实施阶段的 plan agent 应优先完成：
1. **Phase 1（P0）:** 场景标题卡 + 卡住 fallback（~2天）
2. **Phase 2（P0）:** 各场景 ExitZone 位置确认 + 环境引导配置（~1-2天）
3. **Phase 3（P1）:** 条件触发检测 + 提示键文本（~1天）
4. **后续（P2）:** 路线感知差异化文本
