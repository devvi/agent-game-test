# PRD #576 — [UI] 血条与架势条极简 HUD（两段式血条 / 玩家与敌人架势条 / 击杀与处决提示）

> **Issue:** #576
> **标签:** enhancement, ui, content, workflow/research, version/mvp（分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=5）
> **深度:** light（分解 JSON id=5 标注 `depth: light` → §1–5 + §8 必填；§6 本 PRD 含精简版——issue body 强制「开源调研结果在 PR 中说明」需落文档；§7 跳过）
> **Agent:** game-research-agent
> **日期:** 2026-08-19
> **所有权:** `content_ownership: taste-draft`（B3 视觉方向 + B2 UI 文案：agent 出带 taste 方向的草稿，草稿达标即 merge——PR 用 `Parent #576` 不写 Closes，review agent 打 `status/human-review` + assign 用户定稿；数值阈值进 constants # DRAFT 不裁决，机制/结构机械定稿）
> **引擎/目录约束:** Godot 4.7.1 / `shandong-wolf/`（manifest `game.active: shandong-wolf` + subprojects.path 单一事实源；本 PRD 全部路径前缀 `shandong-wolf/`，零 `mini-pong/` 写死）
> **研究选项:** Obsidian 知识库已搜索（`/Volumes/Obsidian/Knowledge Ocean/`：wiki grep HUD/界面 → `wiki/体验引擎——游戏设计全景探秘.md` §8 界面「**如果界面被注意到，它就失败了**」+ 信号 vs 噪声（界面必须区分关键信息与背景细节）、`wiki/体验引擎-游戏设计框架.md` 09 界面「隐形 UI / 隐形式界面：控制融入本能」；wiki grep 只狼 → `wiki/游戏设计理念.md`（只狼=灵感来源，克制美学）；raw grep 弹反/架势 → `raw/Bear/JRPG 战斗系统研究 - 最终综合报告.md`（「弹反/闪避 = 时机判定」动作进阶层——架势条是拼刀循环的可视化依据）；vault 无 HUD 专项笔记，视觉推导自 issue 审美坐标 + 只狼调参基准（`agents/skills/game-to-issues/references/sekiro-tuning-reference.md`：两条命=20 格→半管、架势条语义）+ 同链 issues（#575 已合入信号契约 / #577 判定事件 / #580 处决契约 / #582 vignette 消费端 / #585 组装）+ 开源调研（GitHub API 检索 godot health bar / hud 模板，见 §6.2））
> **来源:** backlog-promotion（`docs/RAW/game-to-issues-shandong-wolf.json` id=5，estimate 1d，priority medium）
> **前置依赖:** #575（✅ merged #618：CombatEntity 信号契约）、#584（✅ merged #609：数值 # DRAFT 只读）、#582（⛔ PR #613 OPEN：血色 vignette 消费端 `set_low_health()` 已建）、#577/#580（⛔ 未开始：判定/处决事件源）、#585（⛔ 未开始：组装接线）

---

## 1. 问题定义

### 1.1 现状（2026-08-19 侦查 @ origin/main 1bdb6c7，含 #618/#619）

| 文件 | 状态 | 说明 |
|------|:----:|------|
| `shandong-wolf/gdscripts/combat_entity.gd` | ✅ 已交付（#575/#618，215 行） | `CombatEntity extends Node2D`：@export 变体参数（is_player/life_total/life_1_max/life_2_abs/stance_max）+ hp_1/hp_2/stance/facing + take_damage/take_stance_damage/break_stance/die/revive + request_transition；**6 信号契约**：`hp_changed(hp_1, hp_2, active_life)` / `stance_changed(stance, stance_max)` / `stance_broken(entity)` / `state_changed(from, to)` / `died(entity, final)` / `revived(entity)`——HUD 的数据与事件源**全部就绪** |
| `shandong-wolf/gdscripts/constants.gd` | ✅ 已交付（#584/#609 + #575 追加） | `LIFE_1_MAX=100` / `LIFE_2_ABS=50`（半管）/ `POSTURE_BREAK_THRESHOLD=100` / `STANCE_BREAK_RECOVERY_SEC=3.0` / `REVIVE_SECONDS=1.0` 等全量 # DRAFT——本层只读消费，**追加 HUD 分区常量（不删改既有行）** |
| `shandong-wolf/scenes/Main.tscn` | ✅ 标题场景（#562/#563/#570） | CanvasLayer **layer=1** + CenterContainer + 4 个 Label（标题/副标题/版本/post-merge probe）；零 HUD、零 StyleBoxFlat；**本 issue 不修改它（红线，实例化归 #585）** |
| `shandong-wolf/gdscripts/` | ❌ 无任何 UI 代码 | 无 hud.gd、无 ProgressBar/StyleBoxFlat 先例（shandong-wolf 内零 UI 资产）——本 issue 全部新建 |
| `#582`（SW-011 雪夜氛围） | ⛔ PR #613 OPEN（impl/582 分支） | `blood_vignette.gd`（extends CanvasLayer，layer=10，`set_low_health(enabled)` / `debug_trigger_low_health()` / `get_visual_alpha()`）+ `atmosphere_controller.gd.set_low_health()`——**消费端已建、信号源缺失**（#582 PRD 曾计划 #575 实体发 low_health，实际合入的 #575 无此信号 → 缺口见 §1.4） |
| `shandong-wolf/e2e_shots.json` | ✅ 已有（#574 剧本） | 当前仅 stick-figure 12 态 capture（`e2e_stick_figure_capture.tscn` + `/root/CaptureRig.current_state`）；无 HUD 截图组——本 issue 追加 |
| `shandong-wolf/tests/` | ✅ 三入口（#572） | run_tests.gd 已挂 state_machine/constants/debug_canvas/combat_entity 等单测；本 issue 追加 test_hud.gd |

**核心缺口：** 战斗数据层（#575）已落地，信号契约完整，但**UI 层零存在**——玩家两段式血条、玩家/敌人架势条、击杀与处决提示文字全部缺失；同时存在一个**信号源缺口**：低血 vignette（AC2）的消费端（#582 `set_low_health()`）已建，但没有任何一方发「低血」信号——issue body 明示「HUD 仅发信号」，本 issue 恰好补位。另注：**「当前锁定敌人」无锁定系统**（MVP 输入集无 lock-on 键，#573 契约无锁定事件）——「锁定」的 MVP 语义 = `set_target_enemy()` 注入的当前战斗目标（单敌人战场即唯一敌人）。

### 1.2 预期行为（验收条件，源自 Issue #576 body，映射到本 PRD 保障）

| # | 验收条件 | 本 PRD 的保障措施 |
|---|---------|------------------|
| AC1 | HUD 可在 1280x720 下正确定位，血条两段式与架势条分开显示 | §4.1（两段式单条双段）+ §4.2（玩家架势条=血条下方 / 敌人架势条=顶部中央）+ §5.1 AC1：锚点断言（左上角血条区块 + 顶部中央敌人架势条）+ 两段条结构断言 |
| AC2 | 玩家血条低于 30% 时出现血色 vignette 提示（由 SW-011 渲染层实现，HUD 仅发信号） | §4.3 方案 A：HUD 订阅 hp_changed 计算活性条 < 30% → emit `low_health_changed(enabled)` 信号（零依赖 atmosphere 节点）；#585 组装接线到 `set_low_health()`；§5.1 AC2：阈值单测断言信号发射 |
| AC3 | E2E 截图提交用户裁决：HUD 观感克制、与雪夜水墨背景融为一体（禁止光效/圆角/饱和堆砌） | §4.5 方案 A（StyleBoxFlat 1px 细线）+ §8.2：e2e_hud_capture 场景 + e2e_shots.json 新 hud 组（正常/低血/处决提示/击杀提示 4 帧）交用户裁决；#586 组装 E2E 补实景帧 |
| AC4 | 无外部 UI 图像资源 | §4.5 方案 A（纯 Control + StyleBoxFlat 程序化绘制，零贴图）+ §5.1 AC4：静态断言 hud.gd 无 `load("res://...png")` / Texture 引用 |

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 玩家实机战斗（MVP 战斗闭环） | 每次游玩 | 左上角细线血条随受击逐段扣减（两段式：第一段满管 100，第二段半管 50）；血条下方玩家架势条随格挡/受击涨落；顶部中央敌人架势条随拼刀上涨，满条崩解 → 出现「按攻击键处决」提示 → 处决完成 → 击杀提示淡入淡出 |
| B | 低血危机（命悬一线） | 每局数次 | 活性血条 < 30% → HUD 发 low_health_changed(true) → SW-011 血色 vignette 0.5s 渐显（alpha 0→0.35），血条填充色转血色点缀；复活后（hp_2 半管接管）条件不满足 → vignette 渐隐 |
| C | 开发者 headless 验证 / E2E 裁决 | 每次 impl PR | `godot --path shandong-wolf/ --headless --script tests/run_tests.gd` 全绿（信号驱动断言，零场景依赖）；e2e_hud_capture 截图 4 帧提交用户裁决观感 |

### 1.4 范围边界（Patch 14 去冲突 + 信号源缺口裁决）

| PRD / Issue | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|------------------|
| #575（战斗实体，merged #618） | CombatEntity 数据 + 6 信号契约 | ❌ 不修改 combat_entity.gd；本层是**纯信号消费者**（hp_changed/stance_changed/stance_broken/died） |
| #582（雪夜氛围，PR #613 OPEN） | 血色 vignette **渲染**（CanvasLayer layer=10，`set_low_health()` 契约） | ❌ 不实现 vignette 渲染；本层只**发 low_health_changed 信号**（issue body 字面「HUD 仅发信号」）；⚠️ **信号源缺口裁决**：#582 PRD 计划 #575 实体发 low_health，实际合入代码无此信号 → 低血判定归属本层（HUD 是 hp_changed 的唯一消费方，issue 明示 HUD 发信号），`#585` 负责把信号接到 `set_low_health()` |
| #577（判定，未开始） | 弹反/拼刀/架势伤害判定 + 结果事件（parry_success/hit_landed/stance_broken/clash） | ❌ 不做判定；本层只显示（订阅 stance_broken 显示处决提示，判定与「何时崩解」归 #577） |
| #580（处决，未开始） | 处决触发/无敌/敌人淡出（攻击键=处决键，靠近崩解敌人自动衔接） | ❌ 不做处决判定与距离语义；本层只显示「按攻击键处决」提示（显示窗口 = stance_broken → 敌人 died/超时）；提示的触发判定细节归 #580 |
| #584（数值 DRAFT，merged） | 手感数值候补值与调参面板 | ❌ 不裁决数值；# DRAFT 只读（提示时长用 STANCE_BREAK_RECOVERY_SEC；血条上限读 LIFE_1_MAX/LIFE_2_ABS）；新增 HUD 阈值也标 # DRAFT 待用户裁决 |
| #585（组装，未开始） | HUD 实例化进战斗场景 + low_health_changed→set_low_health 接线 + target_enemy 注入 | ❌ 不做场景组装；本层交付可独立实例化/单测的组件与信号契约 |
| mini-pong #292/#392/#448（HUD 先例） | 三区霓虹 HUD/球速 HUD（信号驱动零轮询、StyleBoxFlat、代码创建控件） | ❌ 不复制代码（游戏隔离红线）；仅作**模式参考**（信号驱动/TF-1 零轮询静态断言/代码创建 Label 免编辑 tscn） |

**红线（issue body 审美坐标）：** 禁止页游浮夸 UI、禁止红点、禁止自动战斗按钮；1px 细线、半透明填充、无圆角光效、低饱和（苍白月白 #e8e6e3 与墨黑）、低血时少量血色点缀。

---

## 2. 设计意图

### 2.1 为什么现在做

1. **战斗层已合入（#618）→ 信号契约就绪**：hp_changed/stance_changed/stance_broken/died 全部可订阅，HUD 是拼刀循环的「读数面」，只差 UI 层落地——issue body 明示本 issue 是 #575 的直接下游。
2. **审美坐标可执行**：brief §审美坐标（参考作品：只狼拼刀/弹反/架势崩解/处决 + 抗战黑白电影水墨；反例：页游感光效堆砌/浮夸 UI/红点充值）+ Obsidian 体验引擎「如果界面被注意到，它就失败了」「信号 vs 噪声」+ sekiro-tuning-reference（两条命 20 格→半管、架势条=士气条）——克制 HUD 的设计约束全部明确。
3. **taste-draft v4 队列机制就绪**：本 issue 是品味内容（B3 视觉 + B2 文案），草稿达标即 merge（不阻塞 #585 组装），review agent 打 `status/human-review` + assign 用户攒批定稿——管线不停等用户。

### 2.2 为什么是本层（历史成因）

| 约束 | 来源 | 详情 |
|------|------|------|
| 信号契约由 #575 交付 | #575 PRD/DESIGN §8.3 | HUD 按契约消费 6 信号；**契约无 low_health 信号**——低血判定必须由消费方（本层）自算，issue 字面「HUD 仅发信号」恰好授权 |
| 数值 # DRAFT 只读 | #584 交付 | 血条/架势条比例从 constants 读（LIFE_1_MAX/LIFE_2_ABS/STANCE_BREAK_RECOVERY_SEC），不裁决 |
| vignette 消费端已建 | #582 PR #613 | `set_low_health(enabled)` 契约存在但无人发信号 → 本层补发射端（low_health_changed 信号） |
| 「锁定」系统不存在 | #573 输入契约 | MVP 输入集无 lock-on；「当前锁定敌人」= set_target_enemy 注入的战斗目标（#585 组装时注入单敌人实例） |
| 零贴图约束 | issue body 画面实现路径 | 全部 UI = Godot Control + StyleBoxFlat 程序化绘制 → 技术栈唯一可行解（§4.5） |

### 2.3 本层设计意图

- **HUD 是纯消费方**：只读信号画条 + 发一个低血信号，零判定逻辑（不写战斗规则、不探测距离、不驱动状态）——克制从架构层开始。
- **信号驱动、零 `_process` 轮询**：沿用 mini-pong #392/#448 项目先例（TF-1 静态断言源码无 `_process(`），所有更新由信号/Tween/Timer 驱动——「HUD 不抢戏」的机器守卫。
- **一条线一个信息**：血条=两段式单条（第一段满管 + 第二段半管同轴），架势条=细条（玩家：血条下方；敌人：顶部中央）——信息密度克制（体验引擎「信号 vs 噪声」）。
- **低血是唯一色彩例外**：常态月白 #e8e6e3 + 墨黑，低血时血色点缀 + low_health_changed 信号 → SW-011 vignette——「克制不是无色，是颜色只在该出现时出现」。

---

## 3. 影响分析

### 3.1 直接影响的模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `shandong-wolf/gdscripts/hud.gd` | **新增** | `class_name Hud extends CanvasLayer`（layer=1）：代码创建全部 Control（零 tscn 依赖、headless 可测）；订阅信号画血条/架势条/提示文字；emit `low_health_changed`；`set_target_enemy()` API |
| `shandong-wolf/gdscripts/constants.gd` | 修改 | **追加** `# ── HUD (#576) ──` 分区：`HUD_LOW_HP_RATIO=0.30`（# DRAFT，taste 阈值）、布局常量（HUD_PLAYER_BAR_MARGIN/HUD_STANCE_GAP 等）、配色常量（HUD_MOON_WHITE #e8e6e3 / HUD_INK_BLACK / HUD_BLOOD_RED 低血点缀）——不删改既有行 |
| `shandong-wolf/tests/test_hud.gd` | **新增** | 信号驱动断言：两段条比例/低血阈值发射/敌人架势条显隐/提示文字显隐/零贴图静态断言/零 `_process(` 静态断言 |
| `shandong-wolf/tests/run_tests.gd` | 修改 | 注册 test_hud.gd |
| `shandong-wolf/scenes/e2e_hud_capture.tscn` + `shandong-wolf/gdscripts/e2e_hud_capture.gd` | **新增** | E2E 驱动场景（复用 #574 CaptureRig 模式：`/root/CaptureRig.current_state` 轮询 + auto_cycle 兜底），驱动 HUD 进入 4 态（正常/低血/处决提示/击杀提示）供截图 |
| `shandong-wolf/e2e_shots.json` | 修改 | 追加 `hud` group（4 shots，main_scene 指向 e2e_hud_capture.tscn） |

### 3.2 间接受影响的模块（下游消费者，本次不改）

| 文件/系统 | 影响 | 消费方式 |
|-----------|------|---------|
| #585 组装（未开始） | 实例化 Hud + `low_health_changed` → `AtmosphereController.set_low_health()` 接线 + `set_target_enemy(enemy)` 注入 | 实例化 + 信号接线 |
| #582 blood_vignette（PR #613） | 低血信号源就位（此前只有 debug_trigger） | 经 #585 接线消费 `low_health_changed` |
| #577/#580（未开始） | 事件源：stance_broken/died 驱动提示显示 | 信号订阅（本层只显示） |
| #586 E2E 剧本（未开始） | 战斗实景帧将含 HUD（组装后） | 截图帧 |

### 3.3 数据流图

```
#575 CombatEntity（玩家/敌人各一实例）
    │  hp_changed(hp_1, hp_2, active_life)
    ├──► Hud._on_player_hp_changed ──► 两段血条重绘（段1=hp_1/LIFE_1_MAX，段2=hp_2/LIFE_2_ABS）
    │         └── 活性条 < 30%×上限？──是──► emit low_health_changed(true) ──(#585 接线)──► #582 set_low_health(true) → vignette
    │         └── 恢复 ≥30% ──► emit low_health_changed(false) → vignette 渐隐
    │  stance_changed(stance, stance_max)
    ├──► Hud._on_player_stance_changed ──► 玩家架势条（血条下方）
    │  stance_changed(stance, stance_max)  [enemy = target_enemy]
    ├──► Hud._on_enemy_stance_changed ──► 敌人架势条（顶部中央）
    │  stance_broken(enemy)
    ├──► 显示「按攻击键处决」提示（3s = STANCE_BREAK_RECOVERY_SEC，或敌人 died/玩家攻击时提前隐藏）
    │  died(enemy, final=true)
    ├──► 显示击杀提示（1.5s fade）＋ 隐藏处决提示
    │  died(player, final) / revived(player)
    └──► 血条归零态/回生后半管接管（段1 清空、段2 亮起）
```

### 3.4 需更新的文档

- [ ] `docs/GAME_DESIGN/shandong-wolf/` 新增 HUD 章节（post-merge agent 落盘）
- [ ] `PROJECT.md` UI 进度更新
- [ ] `docs/TASTE.md` 品味档案：击杀/处决文案候选 + 用户裁决结果（B2）

---

## 4. 方案对比

### 4.1 两段式血条布局（AC1 核心）

**方案 A：单条双段（同轴两段，段1 全宽 + 段2 半宽）—— 推荐**

一条横向血条：段1（hp_1，宽度 = LIFE_1_MAX 比例，满管 100）与段2（hp_2，宽度 = LIFE_2_ABS 比例，半管 50）首尾相接同一轴线；活性段高亮（月白填充），非活性段暗显（墨黑半透明）；回生（active_life 1→2）时段1 清空变暗、段2 亮起。实现：外层 Control `_draw()` 自绘（~40 行）或两个 ProgressBar 精确排列。

- Pros：单条 = 信息密度最低（只狼单条血条语义，「血条是画面组成不是干扰」）；「第二条命只剩半管」宽度差一目了然（50/100 同轴对比）；回生瞬间无条长突变（段2 已在位）。
- Cons：段2 半宽需自绘或双 ProgressBar 拼合（引擎 ProgressBar 原生单值）。
- Risk：**Low**。Effort：0.5d。

**方案 B：上下两行独立条（满管行 + 半管行）**

- Pros：两个原生 ProgressBar 零自绘。
- Cons：两行视觉重量翻倍（页游感风险，违背克制坐标）；两条长度不同像「两条不同的血条」而非「两条命」；左上角纵向空间被占满（架势条没位置）。
- Risk：Med（审美偏离）。Effort：0.2d。

**方案 C：只狼式单条全宽，回生后条变短**

- Pros：与只狼一致。
- Cons：违背 issue 字面「两段式」；回生瞬间条长突变 = 视觉干扰（体验引擎「界面被注意到就失败了」）。
- Risk：Med（字面偏离）。Effort：0.2d。

**推荐 A。** 理由：①克制坐标（单条）；②「两段式，第二条为半管」字面满足；③回生状态无突变。

### 4.2 敌人架势条布局（AC1「玩家与当前锁定敌人」）

**方案 A：屏幕顶部中央细条（只狼首领条语义）—— 推荐**

敌人架势条独立于玩家区块，锚定顶部中央（宽 ~240px、高 ~6px 细条），仅当 `set_target_enemy()` 已注入时显示。

- Pros：不遮挡战斗读图（细条+中央空白区）；位置语义清晰（「正在交战的敌人」）；与玩家架势条（左上角）空间分离——谁是谁的架势一目了然。
- Cons：与敌人空间位置解绑（MVP 单敌人战场可接受；多敌人/锁定系统是 v1 话题）。
- Risk：**Low**。Effort：0.2d。

**方案 B：敌人头顶跟随条**

- Pros：空间绑定直观（只狼杂兵式）。
- Cons：敌人移动 → 条抖动（克制破坏）；敌人离场/死亡时条消失突兀；MVP 单敌人战场下「头顶跟随」无增益。
- Risk：Med（抖动/干扰）。Effort：0.4d。

**方案 C：并入左上角玩家区块（第二根）**

- Cons：敌人架势放玩家区块 = 信息归属混乱（谁的架势？）；左上角三根条 = 信息密度爆表。
- Risk：High（违背克制）。Effort：0.1d。

**推荐 A。** MVP 无锁定系统，「当前锁定敌人」= set_target_enemy 注入的单目标（#585 组装）；多目标/锁定 UI 明确归 v1（§8.4 风险 4）。

### 4.3 低血 vignette 信号契约（AC2，信号源缺口裁决）

**方案 A：HUD 发 `low_health_changed(enabled)` 信号，#585 组装接线到 `set_low_health()` —— 推荐**

Hud 订阅玩家 hp_changed → 计算当前活性条（active_life=1 时 hp_1 / LIFE_1_MAX；active_life=2 时 hp_2 / LIFE_2_ABS）< `HUD_LOW_HP_RATIO`（0.30，# DRAFT）→ emit `low_health_changed(true/false)`（边沿触发，避免每帧重发）。Hud 零引用 atmosphere 节点（信号无监听者时安全 no-op）。

- Pros：issue 字面「HUD 仅发信号」逐字一致；与 #582 消费端契约（`set_low_health(enabled)`）干净对接；#582 未合入时 HUD 独立可测（信号无消费者不崩溃）；组装接线归 #585（胶水层职责）。
- Cons：接线前 vignette 不显示（依赖链预期，#585 才闭环）。
- Risk：**Low**。Effort：0.1d。

**方案 B：HUD 直接持有 AtmosphereController 引用调用 set_low_health()**

- Cons：HUD 耦合渲染层（违背「仅发信号」）；#582 未合入时 hud.gd 编译依赖不存在节点（headless 测试需 mock）；组装职责泄漏进组件。
- Risk：Med（耦合/编译时序）。Effort：0.1d。

**方案 C：改 #575 实体发 low_health（#582 PRD 原计划）**

- Cons：侵入已合入代码（战斗层回归面）；实体是数据容器，低血判定是「展示阈值」（taste 域）——放实体违背 #584「数值归属」纪律；issue 字面明确 HUD 发信号。
- Risk：Med（侵入已合入代码）。Effort：0.3d（含回归）。

**推荐 A。** 理由：①issue 字面；②#582 契约现成；③零耦合可独立测试；④缺口补位自然（HUD 是 hp_changed 唯一消费方）。

### 4.4 提示文字机制（击杀提示 / 处决提示）

**方案 A：Label + 信号驱动显隐 + Tween 淡入淡出 —— 推荐**

两个隐藏 Label（`KillPromptLabel` / `ExecutePromptLabel`，中文，16px，墨黑底 1px 月白描边）。处决提示：订阅敌人 `stance_broken` → 显示 3s（`STANCE_BREAK_RECOVERY_SEC` # DRAFT 只读）或敌人 died/玩家 attack 时提前隐藏；击杀提示：订阅敌人 `died(final=true)` → 显示 1.5s fade（Timer 驱动隐藏，零 `_process`）。

- Pros：信号驱动 = 零轮询（mini-pong TF-1 模式）；Tween 淡入淡出 = 克制（不闪烁不弹跳）；文案独立可替换（B2 候选清单）。
- Cons：显隐节奏需要 taste 裁决（时长/文案由用户定稿）。
- Risk：**Low**。Effort：0.3d。

**方案 B：常驻状态文字开关（state_label 常显当前状态）**

- Cons：常驻文字 = 干扰（页游「技能提示」感）；状态文本由 state_changed 驱动易与 #574 动画状态重复显示。
- Risk：Med（审美偏离）。Effort：0.2d。

**方案 C：动画序列演出（Label 弹出+放大+消失）**

- Cons：动效堆砌违背克制坐标（「禁止光效/圆角/饱和堆砌」的精神延伸）。
- Risk：Med。Effort：0.4d。

**推荐 A。** 文案为 B2 taste-draft：击杀提示候选「击毙 / 斩杀 / 击杀 / 肃清 / 取敌」、处决提示候选「按攻击键处决 / 趁势处决 / 了结他 / 就地正法 / 下手吧」——implement 选 1 草稿 + 候选清单交用户定稿（TASTE.md）。

### 4.5 渲染技术栈（AC4 零贴图）

**方案 A：纯 Control + StyleBoxFlat 程序化绘制 —— 推荐（issue body 明示路径）**

血条/架势条用 ProgressBar（自定义 `StyleBoxFlat`：1px 月白描边 `border_width=1`、半透明填充 `bg_color`、`corner_radius=0` 无圆角）或 Control `_draw()`；全部代码创建，零资源文件。

- Pros：issue 字面「全部 UI 用 Godot Control 节点 + StyleBoxFlat 程序化绘制，无贴图」；headless 可测（StyleBoxFlat 属性可断言）；mini-pong 同构先例（#392/#448 代码创建 Label + NeonStyle）。
- Cons：自绘代码需小心（~80 行）。
- Risk：**Low**。Effort：0.5d。

**方案 B：TextureProgressBar + 贴图资源**

- ❌ 直接违反 AC4「无外部 UI 图像资源」与 issue 画面实现路径。
- Risk：High（红线违反）。Effort：0.2d。

**方案 C：第三方 HUD addon（如 godot-segmented-bar）**

- ❌ §6.2 调研：候选 addon 全部 ≤19⭐、texture/编辑器节点型、无水墨极简先例；#572 已裁决不引入第三方 addon（FSM 同例）；引入 = 违反零贴图约束（多数基于 TextureProgress）。
- Risk：High（架构裁决违反）。Effort：0.5-1d（含集成）。

**推荐 A。** 理由：issue 明示 + 零资产 + 可断言可测试。

### 4.6 推荐汇总表

| 决策点 | 推荐 | 核心依据 |
|--------|------|---------|
| 两段式血条 | A：单条双段（段1 全宽 + 段2 半宽同轴） | 克制坐标 + issue 字面 + 回生无突变 |
| 敌人架势条 | A：顶部中央细条（set_target_enemy 注入） | 信息归属清晰 + 不遮挡读图；锁定系统归 v1 |
| 低血 vignette | A：HUD 发 low_health_changed 信号，#585 接线 | issue「HUD 仅发信号」字面 + #582 契约现成 + 零耦合 |
| 提示文字 | A：Label + 信号驱动 + Tween（文案 5 选 1 待用户定稿） | 零轮询 + 克制 + B2 流程 |
| 渲染技术栈 | A：纯 Control + StyleBoxFlat | issue 明示 + AC4 零贴图 + 可断言 |
| HUD 层级 | CanvasLayer **layer=1**（与标题 UI 同层约定） | #582 层约定：2=水墨、3-5=雪幕、10=vignette；水墨晕染盖于 HUD 之上 = 融为一体 |

---

## 5. 边界条件与验收

### 5.1 验收清单（源自 issue body 4 条 AC）

- [x] **AC1: 1280x720 定位 + 两段式血条 + 架势条分开显示** — 玩家血条区块锚定左上角（margin 16,16）；玩家架势条在血条正下方（间距 6px）；敌人架势条锚定顶部中央；窗口 1280x720 固定（resizable=false）下全可见
  - 验证：test_hud.gd 断言锚点/位置/尺寸；两段条结构（段1 宽=hp_1 比例、段2 宽=hp_2 比例、同轴）
- [x] **AC2: 低血 vignette（HUD 仅发信号）** — 活性血条 < 30% 上限 → 恰好一次 `low_health_changed(true)`（边沿触发）；恢复 ≥30% → `low_health_changed(false)`；信号携带 enabled: bool
  - 验证：test_hud.gd 阈值边界断言（29.9% 发 / 30% 不发，或按定稿语义）；#585 接线说明写入 §8.3
- [x] **AC3: E2E 截图提交用户裁决** — e2e_hud_capture 4 帧（normal / low_hp / execute_hint / kill_hint），观感克制（1px 细线、无圆角、低饱和、无光效）
  - 验证：`scripts/run-e2e-review.sh` 截图 → PR comment 嵌入 → assign 用户裁决（taste-draft 定稿机制）
- [x] **AC4: 无外部 UI 图像资源** — hud.gd 全部控件程序化创建，零贴图
  - 验证：test_hud.gd 静态断言源码无 `load("res://*.png")` / `Texture2D` / `Image` 引用

### 5.2 边界条件

1. **无 target_enemy** — set_target_enemy 未注入或敌人已释放 → 敌人架势条隐藏、相关订阅断开，不报错（null 防护 + `CONNECT_REFERENCE_COUNTED`）
2. **回生切换（active_life 1→2）** — hp_changed(0, 50, 2)：段1 清空变暗、段2 亮起；血条总视觉长度不变（段2 已在位）——无跳变无闪烁
3. **低血阈值边界** — 恰好 30%：按「< 30%」严格小于（HUD_LOW_HP_RATIO 常量 + 单测锁死语义，防浮点抖动用 0.001 容差）
4. **处决提示重复触发** — 敌人多次 stance_broken（理论单次，防御）→ 提示幂等重显示（重置 3s 计时），不叠加不闪烁
5. **击杀提示与处决提示竞争** — 敌人 died 时处决提示立即隐藏、击杀提示显示（优先级：击杀 > 处决）
6. **敌人 died(final=false)（复活类敌人，MVP 无）** — 击杀提示仅 final=true 触发；final=false 不显示击杀文字
7. **玩家死亡/复活** — 玩家 died → 血条归零态（不显示失败字幕，归 SW-015/#585）；revived → 段2 半管亮起
8. **数值异常** — hp/stance 为负/NaN（防御 clamp 已由 #575 保证）→ 条宽 clamp [0,1]，不除零不崩溃
9. **多实例** — HUD 单例（战斗场景一个）；重复实例化时第二实例退出（`get_tree().get_first_node_in_group("hud")` 存在则 queue_free）

### 5.3 失败路径

1. **#582 未合入（vignette 消费端缺失）** — low_health_changed 无监听者：Godot 信号安全 no-op，HUD 功能不受影响；vignette 不显示 = 依赖链预期（#585 接线后闭环）；不阻塞本 issue 合入
2. **实体提前释放（敌人被处决淡出）** — 信号连接随对象释放断开（`CONNECT_REFERENCE_COUNTED` + `_exit_tree` 主动断开）；HUD 不持有悬垂引用（target_enemy 置 null + 隐藏敌人架势条）
3. **文案长度溢出** — 提示 Label 定宽（处决提示 ~220px / 击杀提示 ~120px）+ `text_overrun_behavior = TRIM_ELLIPSIS`；超长候选文案不破坏布局
4. **E2E 截图依赖状态机未就绪** — e2e_hud_capture 用 CaptureRig 模式（#574 已验证）：auto_cycle 兜底 + settle_frames 覆盖 Tween 时长；HUD 驱动不依赖战斗场景（直接 emit 信号）

---

## 6. 依赖与阻塞

### 6.1 依赖链

| 依赖 | 状态 | 风险 | 说明 |
|------|:----:|:----:|------|
| #575（战斗实体） | ✅ merged #618 | 无 | 6 信号契约（hp_changed/stance_changed/stance_broken/died/state_changed/revived）——数据与事件源 |
| #584（数值 DRAFT） | ✅ merged #609 | 无 | LIFE_1_MAX/LIFE_2_ABS/POSTURE_BREAK_THRESHOLD/STANCE_BREAK_RECOVERY_SEC 只读 |
| #582（雪夜氛围） | ⛔ PR #613 OPEN | 中 | 低血 vignette 消费端（set_low_health）；合入前 vignette 不可见（信号安全 no-op）；接线归 #585 |
| #577（判定） | ⛔ 未开始 | 低 | stance_broken 事件源（本层只显示）；HUD 不阻塞 |
| #580（处决） | ⛔ 未开始 | 低 | 处决提示的触发判定语义（靠近/自动衔接）归 #580；本层提示显示契约先行 |
| #585（组装） | ⛔ 未开始 | 中 | 实例化 Hud + low_health_changed→set_low_health 接线 + set_target_enemy 注入 |
| mini-pong #392/#448 | ✅ CLOSED | 无 | 模式参考（零轮询/TF-1/StyleBoxFlat 程序化）——不复制代码 |

```
#575 ──► #576（本 issue）──► #585 组装 ──► #586 E2E
#582 ──┘（set_low_health 消费端）      │
#577/#580（事件源，并行不阻塞）────────┘
```

### 6.2 开源调研（issue body 要求「开源优先，成熟方案优先复用，找不到再自行实现，并在 PR 中说明调研结果」）

2026-08-19 检索，GitHub API（按 star 排序）+ Godot Asset Library 认知：

| 候选 | Star | 调研结论 |
|------|------|---------|
| Astridson/godot-segmented-bar | ⭐19 | SegmentedBar 节点（Godot 4）——分段条，但基于 texture/绘制节点，无 StyleBoxFlat 水墨风格；功能超出 MVP（分段动画）；引入 = 违反零贴图 + #572 不引入 addon 裁决 |
| vi4hu/godot_health_bar_2d | ⭐10 | 编辑器 addon（HealthBar2D 节点）——编辑器资产型，headless 测试不可用 |
| JarLowrey/TextureProgressOfSubunits | ⭐8 | TextureProgress 子单位——贴图驱动，违反 AC4 零贴图 |
| 01rasmus/moba-health-bars-godot / resultant-gamedev/godot-resource-bar | ⭐2 | 示例项目 / 引擎 module——个人习作，无复用价值 |
| Niekvdm/godot-plugins-gtml | ⭐87 | GTML 标记语言（HTML/CSS 风格 UI）——非 health bar 组件，引入重依赖 |
| youssouf20/flashpoint | ⭐0 | toast 通知节点——仅提示文字子集，但零维护 |

**结论：** 无成熟、克制、零贴图的 HUD 方案可复用（候选全部 texture/编辑器节点型且 ≤19⭐）。按 issue 允许「找不到再自行实现」→ **自研**：Godot 内建 ProgressBar + StyleBoxFlat（1px 描边/半透明填充/零圆角）——内建能力零第三方依赖，且 mini-pong 项目内已有同构先例。implement PR 须引用本调研结论。

### 6.3 前置准备

- [ ] implement 前确认 origin/main 已含 #618（CombatEntity 6 信号契约）——本 PRD 侦查基准 1bdb6c7 已含
- [ ] #582（#613）合入与否不影响本 issue 实现（信号安全），但影响 E2E 低血帧的 vignette 观感——若 #582 未合入，E2E 低血帧仅截 HUD 本体

---

## 7. Spike / 实验

**Skipped per depth/light label.**（分解 JSON id=5 `depth: light`；技术不确定性低——StyleBoxFlat + ProgressBar 为 Godot 内建能力，mini-pong #392/#448 同构先例已验证 headless 可编译可断言；无需要实验裁决的架构分叉。）

---

## 8. 交接上下文（plan agent 交接）

### 8.1 系统现状快照

- origin/main @ 1bdb6c7（#619 已合入）：CombatEntity（215 行，6 信号契约，§1.1 表）、WolfConstants 全量 # DRAFT、Game/InputController autoload、PlayerController、StickFigureController.consume_state（11 态）、debug_canvas（#584 调参面板）
- UI 层**零存在**：无 hud.gd、无 StyleBoxFlat 使用、Main.tscn 纯标题场景（layer=1）
- #582（vignette 消费端）PR #613 OPEN：`blood_vignette.gd.set_low_health(enabled)` 契约已建；`atmosphere_controller.gd.set_low_health()` 存在
- E2E 设施就绪：#574 CaptureRig 模式（e2e_stick_figure_capture.tscn + e2e_shots.json groups）

### 8.2 交付物清单（按实现顺序）

| 顺序 | 文件 | 内容 |
|:----:|------|------|
| 1 | `constants.gd`（修改） | 追加 `# ── HUD (#576) ──` 分区：HUD_LOW_HP_RATIO=0.30（# DRAFT，taste 阈值）、布局常量（margin/gap/尺寸）、配色常量（HUD_MOON_WHITE #e8e6e3 / HUD_INK_BLACK / HUD_BLOOD_RED）——不删改既有行 |
| 2 | `hud.gd`（新增） | `class_name Hud extends CanvasLayer`（layer=1）：代码创建两段血条（段1=hp_1/LIFE_1_MAX、段2=hp_2/LIFE_2_ABS 同轴）、玩家架势条（血条下方）、敌人架势条（顶部中央）、KillPromptLabel/ExecutePromptLabel；订阅玩家实体信号 + `set_target_enemy()` 订阅敌人信号；emit `low_health_changed(enabled)`（边沿触发）；Tween 淡入淡出 + Timer 隐藏（**零 `_process`**） |
| 3 | `test_hud.gd`（新增） | AC1-4 断言 + 边界用例（§5.2/§5.3）：两段条比例、低血阈值边沿、target_enemy null、回生切换、提示竞争、零贴图静态断言、零 `_process(` 静态断言（TF-1 模式） |
| 4 | `run_tests.gd`（修改） | 注册 test_hud.gd |
| 5 | `e2e_hud_capture.tscn` + `e2e_hud_capture.gd`（新增） | CaptureRig 模式驱动 HUD 4 态（normal/low_hp/execute_hint/kill_hint），auto_cycle + settle_frames 覆盖 Tween 时长 |
| 6 | `e2e_shots.json`（修改） | 追加 `hud` group（4 shots，main_scene=e2e_hud_capture.tscn） |

### 8.3 契约 API（下游消费面 + 组装接线）

```gdscript
## Hud（class_name，extends CanvasLayer，layer=1）
func set_target_enemy(entity: CombatEntity) -> void   # #585 组装注入；null 安全（敌人释放自动断开）
func set_debug_hp(hp_1: float, hp_2: float, active_life: int) -> void   # E2E 驱动（CaptureRig 用）
func set_debug_stance(stance: float, stance_max: float) -> void
func show_debug_hint(kind: String) -> void            # "execute" | "kill"（E2E 驱动）

signal low_health_changed(enabled: bool)              # #585 接线 → AtmosphereController.set_low_health()

## 消费的信号（#575 CombatEntity，只读）
hp_changed(hp_1: float, hp_2: float, active_life: int)   # 两段血条 + 低血判定
stance_changed(stance: float, stance_max: float)         # 玩家/敌人架势条
stance_broken(entity: CombatEntity)                      # 处决提示显示（3s = STANCE_BREAK_RECOVERY_SEC）
died(entity: CombatEntity, final: bool)                  # 敌人 final=true → 击杀提示 + 隐藏处决提示

## 只读常量（constants.gd # DRAFT，不裁决）
LIFE_1_MAX=100 / LIFE_2_ABS=50 / POSTURE_BREAK_THRESHOLD=100 / STANCE_BREAK_RECOVERY_SEC=3.0 / HUD_LOW_HP_RATIO=0.30
```

### 8.4 主要风险与裁决点

1. **#582 合入时序**：vignette 消费端未合入时低血帧无 vignette——不影响 HUD 功能（信号安全），E2E 低血帧可只截 HUD 本体；#585 组装时闭环
2. **处决提示的距离语义**：本层显示窗口 = stance_broken → 敌人 died/3s 超时；「靠近崩解敌人自动衔接」的距离判定归 #580（MVP 单敌人战场，提示出现即可处决，误差可接受）
3. **文案定稿（B2）**：击杀/处决文案候选 5 选 1（§4.4）交用户定稿，implement 选 1 草稿 + 候选清单进 PR；结果记 `docs/TASTE.md`
4. **「当前锁定敌人」语义**：MVP = set_target_enemy 注入单目标（无锁定系统）；多目标选择/锁定 UI 明确归 v1（#585 组装时若战场多敌人，注入最近敌人即可，不扩展本层）
5. **HUD_LOW_HP_RATIO 阈值**：# DRAFT 候补（0.30），用户裁决可改（调参面板 #584 可扩展挂入，非本层职责）

### 8.5 红线（implement agent 禁止）

- ❌ 不引入任何 UI 贴图/外部图像资源（AC4；纯 Control + StyleBoxFlat）
- ❌ 不修改 `scenes/Main.tscn`（标题场景红线；组装归 #585）
- ❌ 不修改 `combat_entity.gd` / `input_controller.gd` 等已合入代码（纯消费方）
- ❌ 不写战斗判定逻辑（弹反/拼刀/距离/崩解判定归 #577/#580）
- ❌ 不裁决 # DRAFT 数值（只读 constants；新 HUD 常量标 # DRAFT 待用户裁决）
- ❌ 不引入第三方 addon（#572 裁决 + §6.2 调研）
- ❌ 不修改 mini-pong/ 任何文件（游戏隔离红线）
- ❌ 不加 `_process(` / `_physics_process(` 轮询（零轮询契约，TF-1 静态断言兜底）
