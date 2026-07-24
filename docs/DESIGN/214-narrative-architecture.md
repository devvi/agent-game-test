# Design: #214 — 叙事架构 — 博尔赫斯风格约束与三层表达 (Narrative Architecture)

> Parent Issue: #214
> Agent: plan-agent
> Date: 2026-07-25

---

## 1. Architecture Overview

### Core Idea

为《雨夜普罗摩茨》定义完整的叙事架构设计蓝图——包含博尔赫斯风格约束规范（B1–B6）、三层表达模型（L1 字面/L2 暗图/L3 象征）、距离-幻觉映射表（0–10 级）以及三条路线的叙事弧线设计。本文档是后续所有内容创作（对话 JSON、环境文本、视觉参数）的约束框架。

**核心原则：**
1. **约束驱动创作** — 6 条博尔赫斯风格约束为所有叙事文本提供风格边界
2. **距离即幻觉** — 物理距离（办公室→地铁站）映射为幻觉强度（0→10），营造渐进式现实瓦解
3. **三层递进** — 每段文本至少包含 L1（字面）和 L2（暗图）两层，关键节点通过回声系统实现 L3（象征）
4. **状态感知分支** — 玩家的 hope/conviction/will 三轴状态值修正基础幻觉等级并影响文本变体选择

### Data Flow

```ascii
叙事架构设计文档（本文档）
    │
    ├──► 约束规范 B1–B6
    │       └──► 对话创作指南 (dialogues/*.json)
    │
    ├──► 三层表达模型 L1–L3
    │       ├──► L1: 所有玩家可见文本 (Hemingway 约束)
    │       ├──► L2: 潜台词/用词暗示 (不增加额外文本)
    │       └──► L3: 回声系统跨场景象征 (EchoManager 触发)
    │
    ├──► 距离-幻觉映射表 (0–10)
    │       ├──► 场景基础等级: office=0 → subway=9
    │       ├──► 状态修正: hope±1
    │       └──► 视觉参数: Vignette, 雨粒子, 灯光闪烁, 文字漂移
    │
    └──► 路线弧线 A/B/C
            ├──► Keep Walking (信念)   — 平静向前
            ├──► Turn Back (放弃)      — 空洞循环
            └──► Stay (接纳)           — 安静驻足
                    │
                    ▼
            7个关键选择点 C01–C07
                    │
                    ▼
            叙事引擎运行时 (NarrativeManager + WorldviewController)
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| 约束数量下限 | 6 条 (B1–B6) | 超过 AC2 最低要求 (5条)，确保充分覆盖博尔赫斯风格 |
| 幻觉等级范围 | 0–10 (11级) | 与三轴状态系统 (0–10) 保持一致，方便状态乘法映射 |
| 场景基础等级 | 固定值 per 场景 | 路线不变场景变，状态只做 ±1 修正。简单、可预测 |
| 三层表达实现方式 | L1/L2 纯文本 → L3 需回声系统 | L1/L2 无需代码改动；L3 依赖现有 EchoManager |
| 路线分支点 | 唯一关卡：C07 地铁站入口 | 三条路线共享前 6 场景的线性序列，末点三分支 |
| 不可靠叙述度量 | B1 约束：30%/70% 模糊台词比例 | 30% (基线) / 70% (幻觉≥5) 的 Narrator 台词包含歧义/矛盾 |
| 回声音量 | ≥5 处跨场景互文性回声 | 满足 L3 象征层所需的最低密度 |

---

## 2. 博尔赫斯风格约束规范 (B1–B6)

### 约束总表

| ID | 约束名称 | 规范描述 | 违反后果 | 实施方式 |
|:--:|---------|---------|---------|---------|
| B1 | **不可靠叙述** | Narrator 文本不能 100% 可靠。幻觉 <5 时 ≥30% 台词含歧义/矛盾/省略；幻觉 ≥5 时 ≥70% | 玩家对 Narrator 过度信任则破坏博尔赫斯风格 | 创作时标记每段 Narrator 台词的 reliability 标签 |
| B2 | **镜像/迷宫意象** | 每场景至少 1 处镜像/迷宫意象。地铁站至少 3 处。镜像可以是物理（水面倒影、玻璃反射）或叙事（NPC 复述玩家想法、场景结构重复） | 缺少镜像意象则无法构建「现实的复制」主题 | 场景环境文本 + NPC 对话中嵌入镜像主题词 |
| B3 | **现实与幻觉界限模糊** | 不能明确标记哪些是现实、哪些是幻觉。NPC 不应直接告诉玩家「这是幻觉」 | 明确标注幻觉破坏博尔赫斯特有的悬疑 | 所有幻觉元素仅通过语境暗示，无元叙事标签 |
| B4 | **循环与递归** | 至少一处文本/意象在多个场景中以变化形式重复出现。三结局中至少一个暗示「循环继续」而非「故事结束」 | 线性叙事结构不符合博尔赫斯对无限循环的执念 | 回声系统实现意象的重复/变异；Turn Back 结局强制循环暗示 |
| B5 | **文本叠加与层叠** | 环境文本应产生「层叠」效果——同一位置的文本在不同状态下叠加而非替换 | 干净替换文本破坏「记忆叠加」的主题 | 回声系统自然实现；每个交互点保留历次触发文本 |
| B6 | **无限与有限的悖论** | 叙事应触及无限/有限的矛盾。至少一处在对话或环境文本中明确引用「无限」与「有限」的对比 | 没有悖论元素的叙事太「正常」，不符合博尔赫斯 | 关键对话节点（Stranger、便利店）嵌入悖论用语 |

### 约束兼容性矩阵 (Spike A 验证结果)

| 场景 | B1 不可靠 | B2 镜像/迷宫 | B3 现实/幻觉 | B4 循环 | B5 文本层叠 | B6 有限/无限 |
|:----:|:---------:|:-----------:|:-----------:|:-------:|:----------:|:----------:|
| 办公室 | ✅ 文本 | ⚠️ 需玻璃反射 | ⚠️ 需视觉 | ✅ 时钟 | ✅ 屏保残影 | ✅ 倒计时 |
| 大厅 | ✅ 文本 | ✅ 玻璃+地面 | ⚠️ 需视觉 | ✅ 文本 | ✅ 文本 | ⚠️ 需视觉 |
| 便利店 | ⚠️ 需视觉 | ✅ 货架+玻璃 | ✅ 灯光 | ⚠️ 需文本 | ✅ 文本 | ⚠️ 需文本 |
| 天桥 | ✅ 文本 | ✅ 栏杆+水面 | ✅ 雨+夜色 | ✅ 文本 | ✅ 文本 | ✅ 文本 |
| 地下通道 | ✅ 回声 | ✅ **天然** | ✅ **天然** | ✅ 文本 | ✅ 回声 | ✅ 文本 |
| 地铁站 | ✅ 广播 | ✅ 轨道 | ✅ **天然** | ✅ **天然** | ✅ 文本 | ✅ **天然** |

所有场景无需修改几何布局即可承载约束要求。办公室+便利店需要更多视觉辅助。

---

## 3. 三层表达模型 (L1–L3)

### 层级定义

| 层 | 名称 | 定义 | 约束 | 目标读者 | 实现方式 |
|:--:|------|------|------|---------|---------|
| **L1** | 字面层 (Shallow) | 场景中可见可交互的文本内容。NPC 对话、环境文字、选项文本 | Hemingway 约束 (25字符/句，3句/节点) | 所有玩家 | 现有对话系统 |
| **L2** | 暗图层 (Middle) | 字面层之下的暗示和潜台词。未直接写出的情感、关联、双关、文化引用 | 不增加额外文本；每段 L1 至少含 1 处 L2 可解读元素 | 注意到细节的玩家 | 用词选择 (创作阶段) |
| **L3** | 象征层 (Deep) | 跨场景的象征系统。意象重复/变异/呼应构成更深层叙事 | ≥5 处互文性回声；回声触发与玩家状态相关 | 多次游玩/深入分析的玩家 | EchoManager 回声系统 |

### 三层关系图

```ascii
L3 (象征层) ← 意象重复/变异 → EchoManager.echo_triggered
    ↑
L2 (暗图层) ← 用词选择/潜台词 → 创作阶段标记
    ↑
L1 (字面层) ← 可见文本 → HemingwayEnforcer 运行时约束
```

### 三层表达示例 (天桥栏杆交互点)

**L1 — 字面层 (所有玩家可见)：**
> Narrator: "The railing is wet. / Your hand leaves an imprint. / Rain runs along the metal."

**L2 — 暗图层 (通过用词选择暗示)：**
> Narrator: "The railing catches your reflection. / A blurred version of yourself. / The rain distorts it further."
> → 关键词「blurred version」「distort」暗示自我认知模糊

**L3 — 象征层 (前提：玩家在办公室摸过窗玻璃，在大厅见过 Stranger 倒影)：**
> Narrator: "Your handprint from the office window / has followed you here. / The stranger passes on the other side."
> → 字面不可能，但象征上玩家的「印记」和 Stranger 的「镜像」汇聚天桥

**L3 状态变体：**

| 状态 | L3 文本变体 | 象征含义 |
|:----:|-----------|---------|
| Hope≥8 | "Your handprint glows faintly. / A mark of something left behind. / Not all traces are lost." | 希望尚存 |
| Hope≤2 | "Your handprint smears and fades. / The rain is taking it back. / Soon there will be no trace at all." | 绝望侵蚀 |
| Conviction≥8 | "Your handprint is still there. / Through rain and wind it stays. / Something in you refuses to let go." | 信念坚定 |
| Conviction≤2 | "The handprint is gone. / You look for it but the railing says nothing. / You wonder if you were ever here at all." | 信念丧失 |

---

## 4. 距离-幻觉映射表 (0–10)

### 场景基础幻觉等级

| 场景 | 基础等级 | 距地铁站 | 实施优先级 |
|:----:|:-------:|:--------:|:---------:|
| 办公室 (office) | 0 | 出发 | MVP |
| 大厅 (lobby) | 1 | 近距离 | MVP |
| 便利店 (convenience_store) | 2 | 近距离 | MVP |
| 天桥 (bridge) | 4 | 中距 | MVP |
| 地下通道 (underpass) | 7 | 近距 | 后 MVP |
| 地铁站 (subway_station) | 9 | 到达 | 后 MVP |

### 每级规范

| 等级 | 距地铁站 | 视觉变化 | 文本变化 | 色调状态 | NPC 行为 |
|:----:|:--------:|---------|---------|:--------:|---------|
| 0 | 出发（办公室） | 正常 3D 渲染，雨正常 | Narrator 线性叙述，无幻觉元素 | 常规 | NPC 正常对话 |
| 1 | 大厅 | 轻微暗角 | 偶尔出现「可能」「似乎」等模糊词 | 常规 | 保安对话正常，Stranger 首次出现 |
| 2 | 便利店 | 暗角加重，雨声音渐强 | Narrator 开始使用矛盾描述（「安静但嘈杂」） | 轻微偏移 | 店员话语开始含混 |
| 3 | 便利店→天桥 | 灯光闪烁 | 环境文本出现双重解读可能 | 开始偏移 | 便利店 Stranger 留下模糊警告 |
| 4 | 天桥 | 雨粒子增多，光照失真 | Narrator 连续使用不确定性措辞 | 偏移明显 | 流浪汉的话似乎知道玩家内心想法 |
| 5 | 天桥中段 | **界限模糊**：霓虹闪烁频率异常 | 文本中出现镜像/倒装句式 | 中段 | 流浪汉对话开始与先前 NPC 台词重叠 |
| 6 | 天桥→地下通道 | 光影不可预测，雨从各方向落下 | 句子中出现明显重复结构 | 中高段 | 幻觉性 NPC 重现 |
| 7 | 地下通道 | 墙壁文字似乎在移动，隧道无限延伸 | Narrator 与玩家内心独白难以区分 | 高段 | Stranger 回声出现，话语变异 |
| 8 | 地下通道深处 | 地面倒影显示不同场景，视角不稳定 | 文本层叠：同一位置叠加多时间文本 | 极高段 | 涂鸦文字变为玩家先前的选择记录 |
| 9 | 地铁站入口 | 站牌文字内容变化，时空错乱 | 时间标记混乱（白天/黑夜交错） | 接近临界 | 车站广播播放不存在的信息 |
| 10 | 地铁站月台 | **完全幻觉**：多个可能性叠加 | 叙事断裂：段落间逻辑不连续但情感连贯 | 临界/结局 | Stranger 以多种形态同时存在 |

### 映射规则

- 场景的「基础幻觉等级」由场景位置决定（见上表）
- 玩家的 hope/conviction/will 状态对基础等级有 ±1 修正：**high hope = -1, low hope = +1**
- 等级 ≥5 时，NarrativeManager 应允许「幻觉闪切」——短暂切换到另一个场景的文本碎片

### 引擎实现参数映射

| 幻觉等级 | 可调参数 | 当前状态 | 所需改动 |
|:-------:|---------|:-------:|---------|
| 0–2 | 雨粒子密度、相机 Vignette | ✅ RainController 存在 | 添加 Vignette 强度参数到 worldview |
| 3–4 | 灯光闪烁频率、色调偏移 | ⚠️ 部分存在 | 添加随机灯光调制器 |
| 5–6 | 雨方向随机化、纹理偏移 | ❌ 不存在 | 添加 rain_direction_noise 参数 |
| 7–8 | 文字漂移、倒影异常 | ❌ 不存在 | 在 Label3D 中实现文字抖动 shader |
| 9–10 | 场景叠加、多重视角 | ❌ 不存在 | 需要 SubViewport 叠加 |

---

## 5. 三条路线叙事弧线

### 路线 A：Keep Walking（信念 / Faith）

| 阶段 | 场景 | 叙事弧线 | 情感基调 | 关键文本意象 |
|:----:|:----:|---------|:--------:|------------|
| 开始 | 办公室 | 从封闭空间走出 | 压抑但决然 | 重门、敲击的雨、倒计时 |
| 发展 | 大厅 | 遇到 Stranger 给出选择 | 好奇 + 警惕 | 出口的光、Stranger 的伞、水的倒影 |
| 发展 | 便利店 | 日常生活最后一次 | 温暖 + 疏离 | 热咖啡、便利店灯光、窗外的雨 |
| 转折 | 天桥 | 看到城市全景 + 流浪汉 | 疲惫但坚定 | 桥下车流、雨中城市灯光、流浪汉的沉默 |
| 高潮 | 地下通道 | Stranger 回声 — 坚定版本 | 决心 + 释然 | 隧道尽头的光、回声的肯定、脚步声同步 |
| 结局 | 地铁站 | 列车到来，坐上列车 | 平静的向前 | 月台灯光、列车前灯、Stranger 微笑告别 |

**情感曲线:** 压抑 → 好奇 → 温暖 → 疲惫 → 决心 → 平静

### 路线 B：Turn Back（放弃 / Give Up）

| 阶段 | 场景 | 叙事弧线 | 情感基调 | 关键文本意象 |
|:----:|:----:|---------|:--------:|------------|
| 开始 | 办公室 | 一开始就犹豫 | 摇摆 + 不安 | 半开的门、犹豫的脚步、模糊的窗外 |
| 发展 | 大厅 | 尝试继续但被恐惧侵蚀 | 恐惧 + 自我怀疑 | 大厅空旷、Stranger 影子拉长、回声变调 |
| 发展 | 便利店 | 放弃前最后一次温暖 | 痛苦 + 依恋 | 咖啡变冷、店员不再注视、灯光刺眼 |
| 转折 | 天桥 | 决定回头 | 失败感 + 解脱 | 桥中间停步、雨变急、回头看不到来路 |
| 高潮 | 地下通道 | Stranger 回声 — 质疑版本 | 内疚 + 空洞 | 隧道黑暗加深、Stranger 问「你确定？」 |
| 结局 | 回到原点 | 回到起点，循环暗示 | 空洞的循环 | 办公室门又出现、时钟同时间、雨无止境 |

**情感曲线:** 犹豫 → 恐惧 → 痛苦 → 失败感 → 内疚 → 空洞循环

### 路线 C：Stay（接纳 / Acceptance）

| 阶段 | 场景 | 叙事弧线 | 情感基调 | 关键文本意象 |
|:----:|:----:|---------|:--------:|------------|
| 开始 | 办公室 | 已疲惫但不放弃 | 迷茫 + 坚持 | 办公室的安静、雨声像白噪音 |
| 发展 | 大厅 | 既不前进也不后退 | 观察 + 内省 | 在大厅停留、观察 Stranger 的姿态 |
| 发展 | 便利店 | 日常的琐碎成为安宁 | 接纳 + 释然 | 便利店的机械声音、雨声成为背景 |
| 转折 | 天桥 | 停在中间，看着两侧 | 停顿 + 观望 | 天桥栏杆、雨落在栏杆上的节奏、车流灯光 |
| 高潮 | 地下通道 | 不再寻找出口 | 平静 + 融入 | 通道中回声不再恐怖、Stranger 静坐一旁 |
| 结局 | 地铁站 | 不上列车也不回去，驻足 | 安静的接纳 | 空月台、长椅、最后一班车广播、钟声 |

**情感曲线:** 迷茫 → 内省 → 释然 → 停顿 → 平静 → 安静的接纳

### 7 个关键选择点

| # | 场景 | 触发条件 | 选择 A | 选择 B | 选择 C | 影响轴 |
|:-:|:----:|:--------:|:------:|:------:|:------:|:------:|
| C01 | 办公室 | 走到门口 | 开门 → 继续 | 再看一眼窗外 → 犹豫 | — | will ± |
| C02 | 大厅 | 见到 Stranger | 走向 Stranger → 接触 | 绕过 Stranger → 回避 | — | hope ±, conviction ± |
| C03 | 便利店 | 买咖啡时 | 与店员闲聊 → 温暖 | 沉默购买 → 疏离 | — | hope ± |
| C04 | 天桥 | 遇到流浪汉 | 停下对话 → 倾听 | 继续走 → 忽略 | — | conviction ±, hope ± |
| C05 | 天桥中部 | 看到城市夜景 | 停下来看 → 回忆 | 低头快步 → 逃避 | — | will ± |
| C06 | 地下通道 | Stranger 回声触发 | 回应回声 → 面对 | 闭眼走过 → 压制 | — | conviction ±, hope ± |
| C07 | 地铁站入口 | 到达检票口 | 走进检票口 → **Keep Walking** | 转身离开 → **Turn Back** | 停在入口 → **Stay** | 路线决定 |

---

## 6. API Contracts

### 现有 API 扩展计划

以下 API 扩展将在实施阶段添加到现有脚本中。此处仅定义接口契约，不包含完整实现。

#### NarrativeManager 扩展

```gdscript
# 新增信号
signal hallucination_level_changed(new_level: int)
signal reality_flashback(flashback_scene: String, flashback_text: String)

# 新增方法
func get_hallucination_level() -> int:
    # 返回当前场景的幻觉等级 (0-10)
    # 计算逻辑: scene_base_level + state_modifier
    # state_modifier = -1 if hope >= 8 else +1 if hope <= 2 else 0
    pass

func get_hallucination_params() -> Dictionary:
    # 返回幻觉参数映射字典
    # {vignette: float, rain_density: float, light_flicker: float,
    #  text_drift: float, view_instability: float}
    pass

func trigger_reality_flashback(target_scene: String) -> void:
    # 幻觉 >= 5 时触发幻觉闪切
    pass

func evaluate_borgesian_rule(rule_id: String, text: String) -> bool:
    # 运行时检查文本是否违反博尔赫斯约束
    # 主要用于创作验证，非运行时强制
    pass
```

#### WorldviewController 扩展

```gdscript
# 新增方法
func apply_hallucination_effects(level: int) -> void:
    # 将幻觉等级映射为环境视觉参数
    # 修改: rain_controller.rain_density, camera.vignette_intensity,
    #       light_node.flicker_frequency, Label3D.drift_amount
    pass

func get_hallucination_tone_map() -> Dictionary:
    # 返回幻觉等级到视觉参数的完整映射字典
    # 用于调试和测试验证
    pass
```

### 信号连接

```gdscript
# StateSystem → NarrativeManager
StateSystem.state_changed.connect(_on_state_changed)
# NarrativeManager 在 _on_state_changed 中重新计算幻觉等级

# NarrativeManager → WorldviewController
NarrativeManager.hallucination_level_changed.connect(_on_hallucination_level_changed)
# WorldviewController 在 _on_hallucination_level_changed 中应用视觉参数

# EchoManager → NarrativeManager
EchoManager.echo_triggered.connect(_on_echo_triggered)
# NarrativeManager 在 _on_echo_triggered 中检查 L3 象征一致性
```

---

## 7. 测试用例描述 (Test Case Descriptions)

> **注意:** 以下为测试用例描述，不包含可运行测试文件。Implement 阶段将根据这些描述创建实际 GDScript 测试。

### 测试覆盖要求

| 领域 | 正常路径 | 边界/边缘 | 失败路径 |
|:----:|:-------:|:---------:|:-------:|
| 博尔赫斯约束验证 | ≥2 | ≥3 | ≥1 |
| 幻觉等级计算 | ≥2 | ≥3 | ≥1 |
| 三层表达验证 | ≥2 | ≥2 | ≥1 |
| 路线选择逻辑 | ≥2 | ≥2 | ≥1 |
| 引擎参数映射 | ≥1 | ≥2 | ≥1 |

### TC-1: B1 约束验证 — 不可靠叙述比例

| Field | Value |
|-------|-------|
| **ID** | `narrative-tc-01` |
| **Type** | Normal |
| **Description** | 验证所有场景的 Narrator 台词中不可靠叙述比例满足 B1 约束 |
| **Setup** | 6 个场景的对话 JSON 文件已写入，Narrator 台词含 reliability 标签 |
| **Steps** | ① 加载 6 个场景的对话 JSON ② 统计每个场景 Narrator 台词总数 ③ 统计「reliable: false」台词数 ④ 计算比例 |
| **Expected** | 幻觉 <5 的场景 (office/lobby/store/bridge)：不可靠比例 ≥30%。幻觉 ≥5 的场景 (underpass/subway)：不可靠比例 ≥70% |
| **Verification** | `python3 -c "check_unreliable_ratio(dialogues)"` 或等效 GDScript 测试 |

### TC-2: B2 约束验证 — 镜像/迷宫意象密度

| Field | Value |
|-------|-------|
| **ID** | `narrative-tc-02` |
| **Type** | Normal |
| **Description** | 验证每场景至少 1 处镜像/迷宫意象，地铁站至少 3 处 |
| **Setup** | 所有场景对话和环境文本已按约束规范创作 |
| **Steps** | ① 定义镜像/迷宫关键词集合 (mirror, reflection, double, maze, labyrinth, copy, echo) ② 扫描每个场景文本 ③ 统计匹配数 |
| **Expected** | 每场景 ≥1 处匹配；地铁站 ≥3 处 |
| **Verification** | GDScript text scanner 遍历对话 JSON |

### TC-3: B3 约束验证 — 无元叙事标签

| Field | Value |
|-------|-------|
| **ID** | `narrative-tc-03` |
| **Type** | Edge |
| **Description** | 验证没有任何对话或 Narrator 台词语句直接告诉玩家「这是幻觉」 |
| **Setup** | 6 场景对话文件 |
| **Steps** | ① 定义禁止词集合 (hallucination, illusion, not real, dream, imagination) ② 扫描全文 |
| **Expected** | 无任何禁止词出现在 Narrator 或 NPC 台词中 |
| **Verification** | 正则扫描 `\b(hallucination|illusion|not.real|dream|imagination)\b` |

### TC-4: B4 约束验证 — 循环元素存在性

| Field | Value |
|-------|-------|
| **ID** | `narrative-tc-04` |
| **Type** | Normal |
| **Description** | 验证至少一处文本/意象在多个场景重复出现，且 Turn Back 结局包含循环暗示 |
| **Setup** | 6 场景对话 + 3 路线结局文本 |
| **Steps** | ① 扫描 6 场景查找重复/变异文本模式 ② 检查 Turn Back 结局文本是否暗示循环 |
| **Expected** | 发现 ≥1 处跨场景重复意象。Turn Back 结局包含「循环继续」语义 (如办公室门重现、时钟同时间) |
| **Verification** | 文本模式匹配 + 人工确认 |

### TC-5: B6 约束验证 — 无限/有限悖论引用

| Field | Value |
|-------|-------|
| **ID** | `narrative-tc-05` |
| **Type** | Normal |
| **Description** | 验证至少一处文本明确引用「无限」与「有限」的对比 |
| **Setup** | 6 场景对话 + Stranger 台词 |
| **Steps** | ① 定义悖论关键词 (infinite, finite, endless, limit, forever, never) ② 扫描全文③ 检查是否至少一处同时包含无限和有限语义 |
| **Expected** | ≥1 处同时包含 infinite/finite 语义对比 |
| **Verification** | 悖论模式匹配 |

### TC-6: 幻觉等级计算 — 基础等级正确性

| Field | Value |
|-------|-------|
| **ID** | `narrative-tc-06` |
| **Type** | Normal |
| **Description** | 验证每个场景的基础幻觉等级与映射表一致 |
| **Setup** | `NarrativeManager` 实例已创建，`hallucination_levels.gd` 定义了场景→等级映射 |
| **Steps** | ① 设置状态为中间值 (hope=5, conviction=5, will=5) ② 对 6 个场景分别调用 `get_hallucination_level()` ③ 记录结果 |
| **Expected** | office=0, lobby=1, store=2, bridge=4, underpass=7, subway=9 |
| **Verification** | `assert_equal(manager.get_hallucination_level(), expected)` |

### TC-7: 幻觉等级计算 — 状态修正

| Field | Value |
|-------|-------|
| **ID** | `narrative-tc-07` |
| **Type** | Edge |
| **Description** | 验证 high hope (-1) 和 low hope (+1) 对基础等级的修正 |
| **Setup** | 同上，修改状态值 |
| **Steps** | ① 设置 hope=9 (high) → 检查 lobby 等级是否为 0 ② 设置 hope=1 (low) → 检查 lobby 等级是否为 2 |
| **Expected** | high hope 修正为 0 (1-1)，low hope 修正为 2 (1+1) |
| **Verification** | `assert_equal` 两次调用 |

### TC-8: 幻觉等级边界条件 — 夹紧

| Field | Value |
|-------|-------|
| **ID** | `narrative-tc-08` |
| **Type** | Edge |
| **Description** | 验证幻觉等级修正后不会超出 0–10 范围 |
| **Setup** | NarrativeManager 实例 |
| **Steps** | ① 设置 hope=10 (状态 high) → 检查 office 等级不低于 0 ② 设置 hope=0 (状态 low) → 检查 subway 等级不高于 10 |
| **Expected** | office 在 hope=10 时等级为 0 (夹紧)，subway 在 hope=0 时等级为 10 (夹紧) |
| **Verification** | `assert_greater_equal`, `assert_less_equal` |

### TC-9: 三层表达 — L1 字面层可读性

| Field | Value |
|-------|-------|
| **ID** | `narrative-tc-09` |
| **Type** | Normal |
| **Description** | 验证所有场景文本满足 Hemingway 约束 |
| **Setup** | 6 场景对话 JSON，HemingwayEnforcer 实例 |
| **Steps** | ① 对每个对话节点调用 `HemingwayEnforcer.check_node(text)` ② 记录违规节点数 |
| **Expected** | 0 违规（所有节点满足：每句 ≤25 字符，每节点 ≤3 句） |
| **Verification** | `HemingwayEnforcer.check_node(text).passes == true` |

### TC-10: 三层表达 — L2 暗图层元素检测

| Field | Value |
|-------|-------|
| **ID** | `narrative-tc-10` |
| **Type** | Normal |
| **Description** | 验证每段 L1 文本至少包含 1 处可被解读为 L2 的元素 |
| **Setup** | 对话 JSON，每段文本附带 L2 注释标记 |
| **Steps** | ① 读取每个对话节点的 L2 标记 ② 统计无 L2 标记的节点 |
| **Expected** | 0 节点无 L2 标记 |
| **Verification** | 静态 JSON 结构检查 |

### TC-11: 三层表达 — L3 跨场景回声校验

| Field | Value |
|-------|-------|
| **ID** | `narrative-tc-11` |
| **Type** | Edge |
| **Description** | 验证 ≥5 处互文性回声 (L3 象征层) 定义在回声表中 |
| **Setup** | 回声表 (echo_table.json 或 constants.gd 中的 echo_definitions) |
| **Steps** | ① 读取回声定义列表 ② 统计唯一回声数量 ③ 检查每个回声的 source_scene 和 target_scene 不同 |
| **Expected** | 回声数量 ≥5，每处回声跨至少 2 个场景 |
| **Verification** | 静态配置检查 |

### TC-12: C07 路线分支 — 三分支触发

| Field | Value |
|-------|-------|
| **ID** | `narrative-tc-12` |
| **Type** | Normal |
| **Description** | 验证 C07 选择点正确触发三条路线之一 |
| **Setup** | DialogueRunner + 地铁站对话 JSON |
| **Steps** | ① 模拟选择「走进检票口」→ 检查 route_flag == 'keep_walking' ② 模拟选择「转身离开」→ 检查 route_flag == 'turn_back' ③ 模拟选择「停在入口」→ 检查 route_flag == 'stay' |
| **Expected** | 三种选择分别设置正确的 route_flag |
| **Verification** | `assert_equal(state_system.get_route_flag(), expected)` |

### TC-13: 路线 A 结局文本正确性

| Field | Value |
|-------|-------|
| **ID** | `narrative-tc-13` |
| **Type** | Normal |
| **Description** | 验证 Keep Walking 路线的 6 阶段文本链完整且情感曲线正确 |
| **Setup** | 路线 A 对话 JSON |
| **Steps** | ① 加载路线 A 的 6 场景对话链 ② 检查每个场景的 tone 标记是否匹配情感曲线 |
| **Expected** | 场景 1 tone=压抑 → 2=好奇 → 3=温暖 → 4=疲惫 → 5=决心 → 6=平静 |
| **Verification** | JSON tone 字段 → 情感曲线表对比 |

### TC-14: 路线 B 结局文本 — 循环暗示

| Field | Value |
|-------|-------|
| **ID** | `narrative-tc-14` |
| **Type** | Edge |
| **Description** | 验证 Turn Back 路线的结局文本包含「回到办公室」和「时钟同时间」的循环暗示 |
| **Setup** | 路线 B 结局对话节点 |
| **Steps** | ① 检查结局场景 = office (回到原点) ② 检查时间戳标记 = 21:00 (与开场一致) ③ 检查文本包含循环关键词 |
| **Expected** | 结局回到办公室场景，时间与开场一致，文本暗示循环 |
| **Verification** | 场景名检查 + 时间戳比对 + 关键词匹配 |

### TC-15: 幻觉 ≥5 时 — 闪切触发

| Field | Value |
|-------|-------|
| **ID** | `narrative-tc-15` |
| **Type** | Edge |
| **Description** | 验证幻觉等级 ≥5 的场景中允许闪切到其他场景文本碎片 |
| **Setup** | NarrativeManager，设置幻觉等级为 5+ |
| **Steps** | ① 设置场景等级为 5 (天桥中段) ② 触发闪切条件 (随机事件/状态变化) ③ 检查否触发 `reality_flashback` 信号 |
| **Expected** | 幻觉 ≥5 时闪切触发概率 > 0%，且闪切文本来自不同场景 |
| **Verification** | `signal_was_emitted` 检查 + 闪切源场景确认 |

### TC-16: 幻觉参数映射 — Vignette 强度

| Field | Value |
|-------|-------|
| **ID** | `narrative-tc-16` |
| **Type** | Failure |
| **Description** | 验证幻觉等级 0–10 映射到 Vignette 强度值在合理范围内 |
| **Setup** | WorldviewController，模拟场景切换 |
| **Steps** | ① 遍历幻觉等级 0–10 ② 调用 `get_hallucination_params()` ③ 检查 vignette 字段值 |
| **Expected** | vignette 值在 [0.0, 1.0] 范围内，随等级单调递增 |
| **Verification** | `assert_between(vignette, 0.0, 1.0)` + 单调性检查 |

### TC-17: 对话约束兼容性 — 所有场景

| Field | Value |
|-------|-------|
| **ID** | `narrative-tc-17` |
| **Type** | Edge |
| **Description** | 验证所有对话 JSON 同时满足 B1–B6 和 Hemingway 约束 |
| **Setup** | 6 场景对话 JSON 完整 |
| **Steps** | ① 对每个 JSON 运行 B1–B6 检查 ② 运行 Hemingway 检查 ③ 汇总违规数 |
| **Expected** | 0 约束违规。每约束至少被 1 个场景的文本满足 |
| **Verification** | 综合约束扫描脚本 |

---

## 8. Files Changed

### Modified Files (后续实施阶段)

| File | Type | Change | Est. Lines |
|------|------|--------|:----------:|
| `gdscripts/narrative_manager.gd` | Modify | 添加幻觉等级计算、幻觉闪切触发、B1 约束跟踪 | +40 |
| `gdscripts/worldview_controller.gd` | Modify | 添加幻觉→视觉参数映射、apply_hallucination_effects() | +35 |
| `gdscripts/constants.gd` | Modify | 添加幻觉等级常量、路线 ID 常量、回声定义常量 | +15 |
| `dialogues/*.json` | Modify | 按约束规范重写对话文本（6 场景 × 3 路线） | 大量 |
| `scenes/*.tscn` | Modify | 添加幻觉相关视觉参数 (Vignette, 灯光), 5+ 场景 | 视需要 |

### New Files (后续实施阶段)

| File | Type | Role | Est. Lines |
|------|------|------|:----------:|
| `docs/DESIGN/214-narrative-architecture.md` | **New** | 本文档 - 设计蓝图 | — |
| `docs/TASKS/214-narrative-architecture.md` | **New** | 任务分解文档 | — |

---

## 9. Verification Checklist

- [ ] **AC1 (DESIGN doc):** `docs/DESIGN/214-narrative-architecture.md` 包含完整叙事架构设计
- [ ] **AC2 (Borgesian constraints):** 至少 5 条博尔赫斯风格约束 (B1–B6)，含不可靠叙述、镜像/迷宫意象、现实/幻觉模糊
- [ ] **AC3 (Distance-Illusion map):** 0–10 级距离-幻觉映射表，含视觉/文本变化规范
- [ ] **AC4 (Route arcs):** 3 条路线 (Keep Walking / Turn Back / Stay) 含 6 阶段弧线 + 7 个关键选择点
- [ ] **AC5 (Three-layer expression):** L1/L2/L3 定义 + 每层至少 1 场景示例
- [ ] **Test plan:** ≥15 个测试用例描述 (TC1–TC17)，覆盖正常/边缘/失败路径
- [ ] **Test descriptions only:** 无可运行测试文件
- [ ] 所有约束兼容性经 Spike A 验证（无需修改场景几何布局）
- [ ] 引擎实现可行性经 Spike B 分析（0–4 级 MVP 可行，5+ 需后 MVP）

---

## 10. 对 PRD 的补充与修正 (Corrections to PRD)

**Correction 1 — DESIGN doc 路径：**
- PRD 中引用路径为 `docs/DESIGN/2-narrative-architecture.md`
- 实际路径为 `docs/DESIGN/214-narrative-architecture.md` (使用 GitHub Issue #214 编号)
- 所有跨文档引用应使用实际路径

**Correction 2 — 无需修改的文件：**
- PRD 列出了 `gdscripts/rain_controller.gd` 和 `gdscripts/neon_sign.gd` 作为间接影响模块
- 根据 Spike B 分析，幻觉级别 0–4 (MVP 范围) 仅需要简单的参数调整，不需要修改这些脚本的接口
- 视觉参数映射将集中在 `WorldviewController` 中，不将幻觉逻辑侵入各子系统
- 修正：推荐方法 (先实现 0–4 MVP) 不需要修改 rain_controller 或 neon_sign 的接口
