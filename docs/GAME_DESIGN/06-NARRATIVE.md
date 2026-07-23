# 06. 叙事架构（Narrative Architecture）

> Issue: #45 — 叙事架构
> 状态: ✅ 已合并 (PR #96)
> 实现时间: 2026-07-22

---

## 1. 架构总览

采用**线性场景图 + 状态感知分支**模式。物理路径固定为 6 场景线性序列，但叙事体验通过三轴状态值（hope / conviction / will）动态变化。玩家在相同场景中看到的文本、感受到的氛围各不相同，取决于其内心状态。

### 核心设计原则（「体验引擎」世界叙事模式）

1. **系统即叙事** — 环境变化不由脚本驱动，而由玩家状态驱动（状态 → 世界滤镜 → 新文本）
2. **决策产生系统，不产生剧情** — 玩家的选择改变「世界如何被感知」，而非「接下来发生什么」
3. **叙事密度靠环境细节，不靠对白量** — 雨量、灯光颜色、NPC 站位、影子长度均为叙事工具

### 状态系统

三轴滑条（0–10，初始值 5.0）：

| 轴 | 意义 | 高值（≥7） | 低值（≤3） |
|----|------|-----------|-----------|
| hope | 希望 | 温暖、积极的环境描述 | 绝望、灰暗的环境描述 |
| conviction | 信念 | 坚定、对抗性 NPC 语气 | 顺从、恐惧的 NPC 反应 |
| will | 意志 | 清脆、快速的动作描述 | 沉重、迟缓的动作描述 |
| hope_despair | 双极情绪 (Issue #50) | +6~+10 → Hope | -10~-6 → Despair |

> **注意：** Issue #50 将场景文本基调从 3 态扩展为 5 态，统一使用 `hope` 轴（派生自 `hope_despair`）计算状态 ID。原本不同场景使用不同轴（lobby→conviction, bridge→will）的机制已废弃。

---

## 2. 场景序列

6 个场景按固定顺序排列，构成从办公室到地铁站的一夜步行：

```
办公室 (office)
  │ 出口 → 触发 door_dialogue → 场景切换
  ▼
大厅 (lobby)
  │ 交互: 保安(闲聊)、Stranger(第一次对话)、出口
  ▼
便利店 (convenience_store)
  │ 交互: 店员(能量补给)、货架(探索)、窗外(看雨)
  ▼
天桥 (bridge)
  │ 交互: 栏杆(俯瞰车流)、流浪汉(镜像对话)、雨(压力增强)
  ▼
地下通道 (underpass)
  │ 交互: Stranger(回声对话)、涂鸦墙(回忆闪回)、出口
  ▼
|地铁站 (subway_station) ═══ 终局
  │ 结局: 基于三轴状态判定
  ├── Keep Walking   ─┐
  ├── Turn Back       ├──→ end_credits.tscn → 显示结局标题 + 尾声文字 → GameManager.reset()
  └── Stay           ─┘    → StateSystem.reset() → main.tscn (重新开始)
```

---

## 3. 核心脚本

### 3.1 NarrativeManager（`gdscripts/narrative_manager.gd`）

叙事架构核心控制器，Autoload 注册。

**职责：**
- 管理场景序列（current_scene_index, SCENE_ORDER）
- 监听 StateSystem.state_changed 信号，计算场景文本基调
- 终点判定引擎（determine_ending）
- 回声系统（trigger_echo, echo 变体计算）

**信号：**
| 信号 | 参数 | 用途 |
|------|------|------|
| scene_text_changed | scene_id: String, tone: String | 场景文本变体切换 |
| echo_triggered | echo_id: String, variant: int | 回声触发通知 |
| ending_determined | ending: String | 结局判定通知 |

**结局判定优先级：**
1. **Turn Back** — conviction ≤ 3（优先级最高，低信念优先捕获）
2. **Keep Walking** — hope ≥ 6 AND will ≥ 5
3. **Stay** — hope ≤ 4 AND conviction ≤ 4 AND will ≤ 4（或 fallthrough）

### 3.1a 五态场景基调表（Issue #50）

6 个场景 × 5 个离散状态 = 30 条基调定义，统一使用 `hope` 派生状态 ID：

| 场景 | 状态 1 (Despair) | 状态 2 (Low) | 状态 3 (Neutral) | 状态 4 (Buoyant) | 状态 5 (Hope) |
|------|-------------------|---------------|-------------------|-------------------|----------------|
| Office | "despair" | "low" | "neutral" | "buoyant" | "hope" |
| Lobby | "fear" | "uneasy" | "neutral" | "curious" | "defiant" |
| Convenience Store | "cold" | "distant" | "neutral" | "warm" | "glowing" |
| Bridge | "tired" | "heavy" | "neutral" | "hopeful" | "determined" |
| Underpass | "despair" | "hollow" | "neutral" | "resolute" | "transcendent" |
| Subway Station | "backward" | "hesitant" | "waiting" | "forward" | "forward" |

### 3.2 SceneBase（`gdscripts/scene_base.gd` — class_name SceneBase）

所有场景脚本的基类，提供公共行为。

**公共方法：**
| 方法 | 说明 |
|------|------|
| `_configure_environmental_text()` | 子类重写：配置状态感知环境文本 |
| `_restore_dialogue_state()` | 从 GameManager 恢复对话历史 |
| `get_state_tier(axis: String) -> String` | 获取状态区间标签（delegate to StateSystem） |
| `get_state() -> Dictionary` | 获取当前状态字典 |
| `start_dialogue(file_path, dialogue_id)` | 启动对话面板 |

**生命周期：**
```gdscript
func _ready():
    scene_manager.fade_in()          # 场景入场淡入
    _configure_environmental_text()  # 状态感知文本配置
    _restore_dialogue_state()        # 对话状态恢复
```

### 3.3 场景脚本

| 脚本 | 继承自 | 场景 | 关键交互 |
|------|--------|------|---------|
| office.gd | SceneBase | 办公室 | 门(door_dialogue)、窗(状态感知)、屏保(echo源点) |
| lobby.gd | SceneBase | 大厅 | 保安(闲聊)、Stranger(关键选择)、出口 |
| store.gd | SceneBase | 便利店 | NPC.tscn (店员: 咖啡/聊天/3层人格)、Stranger 脚印文本 |
| bridge.gd | SceneBase | 天桥 | 栏杆(俯瞰)、流浪汉(echo镜像)、低信念内心独白 |
|| underpass.gd | SceneBase | 地下通道 | 涂鸦(回忆)、Stranger(echo对话)、出口 |
|| subway_station.gd | SceneBase | 地铁站 | 检票口(KW)、转身(TB)、长椅(Stay) |
|| end_credits.gd | Node3D (class_name EndCredits) | 片尾 | 3 个 Label3D（标题、尾声、The End）、Timer 自动返回、鼠标点击返回 |

---

## 4. 回声系统

叙事回声（Echo）是跨越场景的台词或意象重现，产生「命运在呼应自己」的感受。

### 定义的回声（Issue #50 更新为 5 变体）

| 回声 ID | 源点场景 | 源点文本 | 重现场景 | 变体数 |
|---------|---------|---------|---------|-------|
| rain_echo | 便利店 | Stranger 「雨这么大…」 | 地下通道 | 5（希望→绝望） |
| screensaver_echo | 办公室 | 屏保「你做游戏有什么用？」 | 天桥 | 5（坚定→沉默） |
| clock_echo | 办公室 | 时钟滴答声 | 天桥 | 5 |
| door_echo | 办公室 | 门开关声 | 地下通道 | 5 |
| rain_variation_echo | 便利店 | 雨声变化 | 天桥 | 5 |
| stranger_echo | 大厅 | Stranger 对话 | 地下通道 | 5 |

变体映射：state 5 (Hope) → variant 0, state 4 → 1, state 3 → 2, state 2 → 3, state 1 (Despair) → variant 4。

### 触发机制

```gdscript
# 每个回声仅触发一次（echo_flags 防止重复）
func trigger_echo(echo_id: String) -> void:
    if echo_flags.get(echo_id, false):
        return  # 已触发，静默返回
    echo_flags[echo_id] = true
    echo_variants[echo_id] = _calculate_echo_variant(echo_id)
    echo_triggered.emit(echo_id, echo_variants[echo_id])
```

---

## 5. 对话系统

	10 个 JSON 对话文件，使用现有对话引擎格式（Issue #46），支持状态条件分支。7 个原有 + 3 个出口对话（Issue #155）：

| 文件 | 对话 | NPC | 场景 |
|------|------|-----|------|
| office_door.json | 办公室出口 | Narrator | 办公室 |
| lobby_stranger.json | 初次相遇 | Stranger | 大厅 |
| lobby_guard.json | 保安闲聊 | Security Guard | 大厅 |
| lobby_exit.json | 大厅 → 便利店出口 | Narrator | 大厅 |
| store_clerk.json | 店员对话 (3层人格 — Tired Worker/Cynical Veteran/Systemic Exhaustion + 办公室引用) | Store Clerk | 便利店 |
| bridge_homeless.json | 流浪汉回声 | Homeless Person | 天桥 |
| bridge_exit.json | 天桥 → 地下通道出口 | Narrator | 天桥 |
| underpass_stranger_echo.json | 回声对话 | Stranger | 地下通道 |
| underpass_exit.json | 地下通道 → 地铁站出口 | Narrator | 地下通道 |
| subway_ending.json | 终局三结局 | Narrator/Stranger | 地铁站 |

### 条件选择示例（store_clerk.json）

```json
{
  "text": "「今天过得不好。」",
  "next_node": "clerk_comfort",
  "condition": {
    "type": "slider",
    "axis": "hope",
    "op": "gte",
    "value": 6
  }
}
```

---

## 6. Stranger NPC 设计

Stranger 不是普通 NPC，而是玩家内心状态的物理投射。

| 状态区间 | 外观 | 语气 |
|---------|------|------|
| hope ≥ 7 | 清晰轮廓，棕色风衣 | 平静、温暖 |
| 3 < hope < 7 | 半清晰，浅色外套 | 中性、模糊 |
| hope ≤ 3 | 面部阴影覆盖 | 空洞、遥远 |

### 三出场时机

| 场景 | 叙事功能 |
|------|---------|
| 大厅（首次） | 引入 Stranger：又一个加班的？ |
| 地下通道（回声） | 核心回声音韵：重复/变形之前的雨台词 |
| 地铁站（终局） | 告别：三结局各有不同行为 |

---

## 7. 文件清单

| 文件 | 类型 | 行数 |
|------|------|------|
| gdscripts/narrative_manager.gd | 核心控制器 | 179 |
| gdscripts/scene_base.gd | 场景基类 | 52 |
| gdscripts/office.gd | 场景脚本 | 66 |
| gdscripts/lobby.gd | 场景脚本 | 67 |
| gdscripts/store.gd | 场景脚本 | 50 |
| gdscripts/bridge.gd | 场景脚本 | 87 |
| gdscripts/underpass.gd | 场景脚本 | 104 |
| gdscripts/subway_station.gd | 场景脚本 | 116 |
|| gdscripts/end_credits.gd | 片尾场景脚本 | 75 |
|| gdscripts/constants.gd (扩展) | 常量 | 119 |
|| gdscripts/npc_node.gd | NPC 框架核心脚本 | 201 |
|| scenes/end_credits.tscn | 片尾场景 | ~20 |
|| scenes/components/NPC.tscn | NPC 组件场景 | 33 |
|| dialogues/*.json (10 个) | 对话数据 | ~830 |
|| dialogues/store_clerk.json (扩展) | 店员对话 (3层人格) | ~536 |
|| dialogues/lobby_exit.json | 大厅出口对话 | 32 |
|| dialogues/bridge_exit.json | 天桥出口对话 | 16 |
|| dialogues/underpass_exit.json | 地下通道出口对话 | 16 |
|| tests/test_narrative_architecture.gd | 测试 | 281 |
|| tests/unit/test_exit_dialogues.gd | 出口对话 JSON 测试 | 199 |
|| tests/unit/test_end_credits.gd | 片尾场景测试 | 107 |
