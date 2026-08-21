# Design: [Graphics] 角色绘制修正：火柴人结构完整化（缺头 / 走路动画异常 / 骨架一致性）

> **Parent Issue:** #683（feature / workflow/plan / priority/high / graphics / version/mvp）
> **Agent:** game-plan-agent
> **Date:** 2026-08-21
> **Approach:** PRD §4 **方案 A 全项确认采纳** —— 4.1-A 颈线 + 比例校准 + 可选冷白头轮廓（taste 决策点）/ 4.2-A 膝关节点 + 24–32 帧步态循环 + 播放速度同步 / 4.3-A `StickFigure.scale.x = facing` 翻转接线（视觉子节点，物理层零影响）/ 4.4-A REST_POSE 公共基准 + 首尾帧衔接规约 + 姿态差单测。方案 B（仅调比例/仅延长循环/不翻转/全 clip crossfade）与方案 C（Sprite2D 贴图/程序化 IK/翻转物理根）否决理由同 PRD §4。
> **Reference PRD:** `docs/PRD/683-stick-figure-structure-fix.md`（research PR #688 已合并 2026-08-21）
> **上游方案:** `docs/DESIGN/574-stick-figure-silhouette-animation.md`（骨架 + 11 态关键帧动画 + consume_state 契约，本设计在其上**补结构 + 修摆姿与节奏**，不重建框架）；`docs/GAME_DESIGN/shandong-wolf/07-STICK-FIGURE-ANIMATION.md`（#574 落地文档，本 issue 需更新）；`docs/GAME_DESIGN/shandong-wolf/02-CONSTANTS.md`（# DRAFT 常量表，本 issue 需增行）
> **所有权:** `content_ownership: mechanical`（颈/膝节点结构、facing 接线、衔接规约、比例与帧数断言全部机械可验；**唯一 taste 环节 = 头部轮廓去留（实验 1）+ 步态循环帧数定值（实验 2）+ 速度同步策略（实验 3），交 E2E 截图用户裁决，agent 禁止替用户定稿**——#584 同款协议）
> **深度:** standard（GitHub 无 depth 标签；PRD 头标注 depth: standard）—— 涉及文件 **6**（4 .gd + 1 测试 + 1 e2e_shots.json）+ 2 GDD 文档 + **6 项实现子任务跨 4 子系统**（常量 / 骨架 / 动画摆姿 / 装配接线 / 测试 / E2E）→ **产出 DESIGN + TASKS 文档**（触发 skill standard 阈值：5+ 独立子任务跨多子系统，照 #661 先例）
> **并行上下文:** worktree 隔离（/tmp/wt-plan-683，branch `plan/683-stick-figure-structure-fix`）；**#584（OPEN, status/human-review）并行定稿帧节奏 DRAFT** —— 本设计全部新值按「候补值+影响+情感断言」# DRAFT 协议标注，实现前须查 #584 状态；**#585 装配（#666 merged）的 main_battle.gd 为本设计 facing 接线点**；`mini-pong/`、`.github/workflows/`、`scripts/`、`framework/` 零影响；战斗判定（combat_entity/combat_judge/enemy_ai）**零改动**——facing 只被本设计消费、不被修改
> **红线:** 只动 PRD §3.1 列出的 6 文件 + 2 GDD 文档；**绝不触碰** `combat_entity.gd` / `combat_judge.gd` / `enemy_ai.gd`（#575/#577 交付物为保护文件，facing 逻辑判定不变）；`project.godot`、`game-env/manifest.yaml`、`mini-pong/` 不改；**不写可运行测试文件**（只产出 DESIGN/TASKS 文档 + 测试用例描述）；PR body 用 `Parent #683`（不带冒号）

---

## 1. 架构总览

**问题本质是「#574 最小结构落地 + 配方字面解读」造成的三类视觉缺陷：** ① 头 Polygon2D 结构上一直存在（单测 F1/F2 锁定），但头圆半埋躯干（重叠 16px）+ 低对比（#2b2b2b 对暗夜景）+ 比例偏离 GDD + 移动 15Hz 高频抖动叠加 → 观感「没头」；② move clip 按配方字面「4 帧循环」实现（0.067s/周期 = 腿每 33ms 摆 50° = 振动而非步态），单段腿无膝盖、播放速度固定 1.0 与 `MOVE_MAX_SPEED=300` 无同步（滑步），且全仓无 facing→scale.x 翻转接线（向左移动 = 倒走）；③ 11 个 clip 摆姿为独立手摆 DRAFT 值，无公共基准姿态，idle→guard 单帧跳变 177°/245°（肢体瞬移）。

**设计哲学：结构修正为主、审美微调归 taste 通道；四子项共享同一批文件与同一次 clip 重摆工作，合并实现避免重复返工。**

1. **头可读性 = 结构分离 + 比例回归 + 最小对比锚点**——颈线把「头」从躯干里分离出来（真·火柴人头颈），头径按 GDD 比例校准，冷白细轮廓作为**可回退**的 taste 决策点（E2E 截图裁决，不通过则回退纯剪影）；
2. **走路自然 = 膝盖关节 + 步态学循环 + 速度同步**——腿两段化（髋→膝→踝），move 重排为 24–32 帧完整步态（contact/pass 关键姿态，支撑相长/摆动相短），播放速度随实际速度缩放（消除滑步），摆臂与腿反向同频；
3. **朝向正确 = 视觉 facing 翻转接线**——`StickFigure.scale.x` 跟随逻辑 facing（玩家读 `CombatEntity.facing`，敌人读 `EnemyAI.facing` 同步后的 `enemy_entity.facing`），作用于**视觉子节点**而非物理根（#577 判定方向与视觉一致，移动物理零影响）；
4. **骨架一致 = REST_POSE 公共基准 + 首尾帧衔接规约 + 姿态差单测**——延续 #574「直接 play + 首帧衔接」主策略（否决 crossfade 残影），把「骨架正常」从观感变成可回归断言（≤15°/关节，枚举状态机合法转移对）。

```
★ Issue #683 本设计（shandong-wolf 火柴人结构完整化）
┌──────────────────────────────────────────────────────────────────────┐
│ 修改后骨架节点树（stick_figure.gd，纯程序化，零 tscn/贴图）                 │
│   StickFigure (scale.x = facing ← main_battle.gd 新接线 §3.4)          │
│   ├─ TorsoPivot ── Line2D 躯干                                          │
│   │    ├─ NeckPivot ── Line2D 颈（BODY_NECK_LENGTH 候选 10px）          │
│   │    │    └─ HeadPivot ── Polygon2D 头圆（半径候选 9–10 = GDD 比例）    │
│   │    │                      └─ [可选] HeadOutline Polygon2D 冷白环    │
│   │    ├─ ArmLPivot / ArmRPivot ── Line2D 臂（摆臂反向同频）             │
│   │    └─ SwordPivot ── Line2D 刀 + SwordArc（不改）                    │
│   ├─ LegLPivot(髋) ── Line2D 大腿 ── LegKPivot(膝) ── Line2D 小腿        │
│   └─ LegRPivot(髋) ── Line2D 大腿 ── LegKPivot(膝) ── Line2D 小腿        │
│                                                                        │
│ 动画（stick_figure_controller.gd，运行时动态生成，零 .tres）                │
│   anim_move: 24–32 帧步态 contact(0)→pass(6)→contact(12)→pass(18)→…    │
│              + 膝 track（摆动相屈膝抬脚）+ 播放速度随速度缩放               │
│   其余 10 clip: 首/尾帧按 REST_POSE 衔接规约重摆（≤15°/关节）              │
│                                                                        │
│ 数据流（§4）: CombatEntity.facing → main_battle._sync_visual_facing()   │
│   → StickFigure.scale.x；实际速度 → controller.set_move_speed() →       │
│   AnimationPlayer.speed_scale（仅 anim_move 生效）                      │
└──────────────────────────────────────────────────────────────────────┘
```

### 1.1 既有实现状态（Prior Implementation Status）

| 系统（文件） | Issue | 状态 | 本设计的处理 |
|------|:---:|:---:|------|
| 火柴人骨架 7 pivot（`stick_figure.gd`，头 Polygon2D 已存在） | #574（#612 merged） | ✅ | **改**：加 NeckPivot + 腿两段化（膝 pivot）；头径/头位按 GDD 校准 |
| 11 态关键帧动画 + consume_state（`stick_figure_controller.gd`） | #574 | ✅ | **改**：move 重排 24–32 帧步态；各 clip 按 REST_POSE 衔接规约重摆；新增 set_move_speed() |
| `FRAME_ANIM_*`/`BODY_*`/`SWORD_*` # DRAFT 常量（`constants.gd`） | #574 + #584 协议 | ✅ | **改**：新增颈/膝/步态/衔接常量（# DRAFT 三要素注释）；`FRAME_ANIM_MOVE_STEP` 语义修订 |
| 战斗闭环装配（`main_battle.gd`） | #585（#666 merged） | ✅ | **改**：facing→scale.x 接线 + set_move_speed 接线（新增 _process 同步，零组件改动） |
| `CombatEntity.facing` / `EnemyAI.facing`（逻辑朝向） | #575/#577 | ✅ | **零改动**——只被 main_battle.gd 新接线**消费** |
| `test_stick_figure_animation.gd`（F1/F2 断言 7 pivot 与几何） | #574 | ✅ | **改/增**：F1/F2 适配颈/膝结构；新增 AC1/AC2/AC3 用例 |
| `test_main_assembly.gd`（装配测试） | #585 | ✅ | **增**：facing 翻转断言（scale.x == entity.facing） |
| `e2e_shots.json` stick_figure 组（12 态 shot） | #574 | ✅ | **改**：move 组增定格 shot + 新增头可读性 shot |
| E2E 截图链路（#661/#662/#678） | merged | ✅ | **零改动**——裁决截图依赖此链路，rig 驱动契约不变 |
| GDD `07-STICK-FIGURE-ANIMATION.md` / `02-CONSTANTS.md` | #574 | ✅ | **改**（implement 期）：骨架树/步态/facing 章节 + 新常量行 |

### 1.2 核心缺口与修复决策（codebase 勘探确认）

| PRD 断言 | 实际代码 | 结论 |
|---------|---------|------|
| 头圆与躯干重叠 16px | `stick_figure.gd:65-70` HeadPivot @ (0,-44)，`_make_head()` 半径 16 → 圆范围 y∈[-60,-28]；躯干线 y∈[0,-44] → 重叠 16px ✓ | 属实——颈线分离是结构修复本体 |
| move 循环 4 帧 = 0.067s | `_build_move_spec()` frames = `FRAME_ANIM_MOVE_STEP`=4（constants.gd），腿 ±25° 仅 2 帧间距 ✓ | 属实——重排 24–32 帧步态 + 膝 track |
| 单段腿无膝盖 | `_make_limb("LegLPivot", body_leg_length…)` 单 Line2D，无膝 pivot ✓ | 属实——腿两段化 |
| 播放速度固定 1.0、无速度同步 | controller 无 speed_scale/playback 相关代码；`play_clip()` 直接 `play()+seek(0)` ✓ | 属实——新增 `set_move_speed(v)` 仅对 anim_move 生效 |
| 全仓无 facing→视觉翻转 | grep `scale.x`：仅 snow_curtain parallax（无关）；main_battle 装配（:131-147）无 facing 接线 ✓ | 属实——新增 `_sync_visual_facing()` |
| idle→guard 单帧跳变 177°/245° | idle 尾帧 `ArmRPivot=172° / SwordPivot=160°` vs guard 首帧 `-5° / -85°` ✓ | 属实——REST_POSE 衔接规约重摆 |
| C1 单测只断言切换耗时 | `test_stick_figure_animation.gd:229-260` 只测 elapsed ≤ 2 帧，不断言姿态连续性 ✓ | 属实——新增姿态差单测（枚举 TRANSITIONS 合法对） |
| 敌人初始 facing=-1 | `e2e_main_assembly_capture.gd:218` `enemy_entity.facing = -1` ✓ | 属实——翻转后敌人面左持刀，判定与视觉一致 |
| 战斗判定依赖 facing | `combat_judge.gd:84,94,101` 用 facing 校验命中方向 ✓ | **视觉 facing 必须与逻辑 facing 一致**——翻转作用于 StickFigure 子节点（红线 §4.3-C） |

> **与 PRD 的差异说明（1 处）:** PRD §4.4-A 规约原文「clip 首帧=前态尾帧姿态」在**多源进入**场景（如 idle 可由 move/attack/guard/stagger/parry_success/stance_break/revive 进入，单一首帧无法同时衔接所有源）下需要细化。本设计将规约落实为 **REST_POSE 基准 + 出口归位段**（详见 §2.3）：动作型 clip 首/尾帧 = REST_POSE；hold 型 clip（guard/stagger 等）尾部追加 2–4 帧**归位段**收敛到 REST_POSE（帧数扩展仍 # DRAFT），使任意合法转移对的关节角差 ≤15° 可由单测枚举断言。这是 PRD 4.4-A「或首帧直接归 REST_POSE 再动画化」分支的完整化，不改变其「无 crossfade、首帧衔接为主」主策略。

---

## 2. 新结构详细设计

> 本 issue **无全新 .gd 文件**（PRD §3.2：膝关节点复杂时可拆 `stick_figure_leg.gd`，由 implement agent 视复杂度决定——本设计按「不拆、既有文件内完成」规划，拆文件为可选变体）。以下为新结构单元设计。

### 2.1 NeckPivot（颈部线段）—— 头身分离

- **归属文件:** `shandong-wolf/gdscripts/stick_figure.gd`（`_build_skeleton()` 修改）
- **节点结构:**

```
TorsoPivot (Node2D @ (0,0))
└── NeckPivot (Node2D @ (0, -body_torso_length))   ← 新增
    ├── Line2D 颈段: points=[ZERO, (0,-BODY_NECK_LENGTH)]，width=BODY_LIMB_WIDTH，color=BODY_COLOR
    └── HeadPivot (Node2D @ (0, -BODY_NECK_LENGTH))  ← 从 TorsoPivot 直子改为 NeckPivot 子
        └── Polygon2D 头圆（半径 = BODY_HEAD_RADIUS，16 段）
```

- **关键参数（全部 # DRAFT 候补）:**
  - `BODY_NECK_LENGTH: float = 10.0`（候选 8–12；影响：头与躯干视觉分离度，太小仍粘连、太大头离身）
  - `BODY_HEAD_RADIUS: float = 16.0 → 候选 9.0–10.0`（修订：GDD 头径:躯干 ≈ 1:2.2–2.5；头圆最低点与躯干顶重叠 ≤4px）
  - 头圆中心 y = -(torso + neck + head_radius)（结构推导，不新增独立常量）
- **集成注意:** `get_pivot("head")` 返回的 HeadPivot 节点路径从 `TorsoPivot/HeadPivot` 变为 `TorsoPivot/NeckPivot/HeadPivot`——**F1 单测与所有 clip 的 `TorsoPivot/HeadPivot:rotation` track 路径必须同步更新**（§3.6）；头径缩小后头圆不再与躯干视觉重叠，idle 静止帧头可读（AC1）。
- **可选项（taste 决策点，实验 1）:** `HEAD_OUTLINE_ENABLED: bool = false`（候选 true/false）+ `HEAD_OUTLINE_WIDTH: float = 2.0`（候选 1–2）+ `HEAD_OUTLINE_COLOR: Color = SWORD_COLOR 系`。实现：HeadPivot 下追加 Polygon2D 圆环（polygon=外圆半径 head_r+outline_w，holes=[内圆半径 head_r]，颜色冷白）——**仅头部、无辉光/渐变**（剪影红线）；E2E 截图裁决不通过 → 回退纯剪影（仅删轮廓节点，颈+比例保留）。

### 2.2 膝关节点（腿两段化）—— 步态结构基础

- **归属文件:** `shandong-wolf/gdscripts/stick_figure.gd`（`_build_skeleton()` 修改）
- **节点结构（左右对称）:**

```
LegLPivot (Node2D @ (-4,0))  ← 保留原 pivot 名（髋 pivot，兼容 get_pivot("leg_l")）
├── Line2D 大腿: points=[ZERO, (0,+BODY_LEG_UPPER_LENGTH)]，width=BODY_LIMB_WIDTH
└── LegKPivot (Node2D @ (0,+BODY_LEG_UPPER_LENGTH))  ← 新增膝 pivot（膝 pivot 名 leg_k_l / leg_k_r）
    └── Line2D 小腿: points=[ZERO, (0,+BODY_LEG_LOWER_LENGTH)]，width=BODY_LIMB_WIDTH
```

- **关键参数（# DRAFT 候补）:** `BODY_LEG_UPPER_LENGTH: float = 20.0` / `BODY_LEG_LOWER_LENGTH: float = 20.0`（候选 18–22；两段和保持 ≈ 现 BODY_LEG_LENGTH=40，总高不突变）；`MOVE_KNEE_BEND_DEG: float = 40.0`（候选 30–50，摆动相屈膝抬脚）；`KNEE_BEND_MAX_DEG: float = 90.0`（机械上限——AC3「膝单向弯曲 ±90° 内」断言用）。
- **动画契约:** 髋摆仍走 `LegLPivot:rotation`（现有 track 路径**保持**）；新增膝 track `LegLPivot/LegKPivot:rotation`（膝 pivot 在髋 pivot 子树内，动画路径前缀不变）。膝屈曲方向约定：**单向**（向后摆腿方向，抬脚离地），摆动相屈膝、支撑相 0°。
- **F1/F2 影响（§5.3-1 预登记）:** F1 `PIVOT_PARTS` 需增 `leg_k_l`/`leg_k_r`（+ neck 相关）；F2 腿长断言从 `BODY_LEG_LENGTH` 改为大腿长 `BODY_LEG_UPPER_LENGTH`（小腿长另断言）。

### 2.3 REST_POSE 公共基准 + 首尾帧衔接规约 —— AC3 骨架一致性

- **归属文件:** `shandong-wolf/gdscripts/stick_figure_controller.gd`
- **REST_POSE 定义（自然站姿，与现有 idle 摆姿对齐的候选值）:**

| 关节 | 角度（度） | 说明 |
|------|:---:|------|
| TorsoPivot | 0 | 直立 |
| TorsoPivot/HeadPivot | 0 | 头正 |
| TorsoPivot/ArmLPivot | 178 | 自然下垂（Line2D 向 -Y，≈180°） |
| TorsoPivot/ArmRPivot | 172 | 自然下垂（持刀手微抬） |
| TorsoPivot/SwordPivot | 160 | 刀自然下垂 |
| LegLPivot / LegRPivot | 0 | 自然下垂（Line2D 向 +Y） |
| LegLPivot/LegKPivot / LegRPivot/LegKPivot | 0 | 膝伸直（小腿 Line2D 向 +Y） |

- **衔接规约（本设计对 PRD 4.4-A 的落实，见 §1.2 差异说明）:**
  - **R1（动作型 clip）:** idle / move / attack / heavy_attack / execute / revive 首帧与尾帧均 = REST_POSE（各关节差 ≤5°）；move 循环回环自然；同态重入（attack→attack）重置前摇首帧语义不变（前摇首帧 = REST_POSE 起点）。
  - **R2（hold 型 clip）:** guard / parry_success / stagger / stance_break / dead 首帧 = REST_POSE（≤5°），姿态帧保持该状态摆姿，**尾部追加 2–4 帧归位段**收敛到 REST_POSE（`FRAME_ANIM_*_EXIT` 帧数 # DRAFT 候选 2–4；视觉 = 受击后仰自然回位、收刀回位，不瞬移）。
  - **R3（阈值）:** 对 `combat_state_table.gd` TRANSITIONS 的**每个合法转移对 (from,to)**：`|to.clip.首帧 - from.clip.尾帧| ≤ POSE_DELTA_MAX_DEG=15°`（逐关节）；由新增单测枚举断言（§8 AC3）。
  - **R4（保持）:** 切换耗时 ≤2 帧（`FRAME_ANIM_TRANSITION_MAX`，既有 C1 断言保持绿）；**不引入 crossfade/插值**（#574 首帧衔接主策略延续，否决方案 B 残影问题）。
- **新增常量:** `POSE_DELTA_MAX_DEG: float = 15.0`（# DRAFT，AC3 阈值）；各 clip 归位段帧数（# DRAFT 候选 2–4）。

### 2.4 set_move_speed(v) —— 步频与速度同步（AC2）

- **归属文件:** `shandong-wolf/gdscripts/stick_figure_controller.gd`（新增公开方法，**consume_state 契约不变**）
- **签名与逻辑:**
```gdscript
func set_move_speed(v: float) -> void:
    ## 步频速度同步: 仅 anim_move 生效；speed_scale = clamp(|v|/MOVE_MAX_SPEED, MIN, MAX)
    if _anim == null or _anim.current_animation != "anim_move":
        return
    var ratio: float = absf(v) / C.MOVE_MAX_SPEED
    _anim.speed_scale = clampf(ratio, C.MOVE_PLAYBACK_SPEED_MIN, C.MOVE_PLAYBACK_SPEED_MAX)
```
- **新增常量:** `MOVE_PLAYBACK_SPEED_MIN: float = 0.3` / `MOVE_PLAYBACK_SPEED_MAX: float = 1.2`（# DRAFT，实验 3 候选：连续缩放 vs 两档切换——默认连续缩放，起步/急停顺滑）。
- **接线:** main_battle.gd `_process` 内对玩家/敌人各调一次（仅当实体处于 move 状态时生效；速度 <30% 时下限 0.3，配合状态机 move↔idle 转移（combat_entity.gd:215-219）消除「原地跑步」）。
- **不变量:** loop 模式下 speed_scale 连续变化不跳帧（Godot loop 循环边界无缝）；非 move clip 时调用为 no-op（不影响攻击/格挡节奏）。

### 2.5 move 步态循环重排（anim_move 规格）

- **归属文件:** `stick_figure_controller.gd`（`_build_move_spec()` 重写）
- **规格（# DRAFT 候选，实验 2 裁决 24/28/32）:**

| 属性 | 值 | 说明 |
|------|----|------|
| frames | `FRAME_ANIM_MOVE_CYCLE: int = 24`（候选 24/28/32 = 0.4–0.53s，2 步） | 完整步态周期；`FRAME_ANIM_MOVE_STEP` 语义修订为「关键姿态数 = 4」（contact/pass ×2） |
| 关键姿态帧 | contact(0) → pass(6) → contact(12) → pass(18) → contact(24=0) | 帧间距不对称（支撑相 6 / 摆动相 6，可调 7/5），姿态分布见下 |
| 腿髋摆幅 | ±`MOVE_SWING_LEG_DEG: float = 25.0`（候选 20–30） | contact 前腿 +25/后腿 -25；pass 收腿回 0 |
| 膝屈曲 | pass 摆动腿屈 `MOVE_KNEE_BEND_DEG`（候选 40）；contact 0° | 抬脚离地、消除拖地 |
| 摆臂 | 与对侧腿**反向同频**，幅度 ±`MOVE_SWING_ARM_DEG: float = 25.0`（候选 20–35） | ArmL 与 LegR 同相、ArmR 与 LegL 同相 |
| 躯干起伏 | contact y=0 → pass y=-4 → contact y=0（沿用现 -4） | 身体随步态自然起伏 |
| 头微摆 | ±2°（沿用现摆幅） | 与躯干起伏同频 |

- **track 清单:** 既有 7 条 rotation track 保持路径 + 新增 2 条膝 track（`LegLPivot/LegKPivot:rotation`、`LegRPivot/LegKPivot:rotation`）；TorsoPivot position track 保持。
- **滑步消除判据（AC2）:** 匀速段（300px/s）每步位移 ≈ 步幅（24 帧 = 0.4s × 300px/s = 120px/2 步 = 60px/步）；脚触点帧（contact）位移差 ≤2px（§8 AC2-T3 断言：contact 帧脚点相对地面静止）。

---

## 3. 既有组件修改

### 3.1 `shandong-wolf/gdscripts/constants.gd`（# DRAFT 分区增/修）

| 常量 | 值（候选） | 说明 |
|------|-----------|------|
| `BODY_NECK_LENGTH` | 10.0（候选 8–12） | 新增——颈段长（§2.1） |
| `BODY_HEAD_RADIUS` | 16.0 → **9.5（候选 9–10）** | 修订——GDD 头径:躯干 ≈ 1:2.2–2.5（§2.1） |
| `BODY_LEG_UPPER_LENGTH` / `BODY_LEG_LOWER_LENGTH` | 20.0 / 20.0（候选 18–22） | 新增——腿两段（§2.2） |
| `HEAD_OUTLINE_ENABLED` / `HEAD_OUTLINE_WIDTH` / `HEAD_OUTLINE_COLOR` | false / 2.0 / SWORD_COLOR 系 | 新增——taste 决策点（实验 1） |
| `FRAME_ANIM_MOVE_CYCLE` | 24（候选 24/28/32） | 新增——步态周期（实验 2） |
| `FRAME_ANIM_MOVE_STEP` | 4（**语义修订**：循环总帧数 → 关键姿态数） | 修订——注释更新，三要素保留（E3 断言依赖） |
| `MOVE_SWING_LEG_DEG` / `MOVE_SWING_ARM_DEG` / `MOVE_KNEE_BEND_DEG` | 25.0 / 25.0 / 40.0 | 新增——步态摆幅（候选区间见 §2.5） |
| `KNEE_BEND_MAX_DEG` | 90.0 | 新增——膝机械上限（AC3） |
| `POSE_DELTA_MAX_DEG` | 15.0 | 新增——衔接阈值（AC3） |
| `MOVE_PLAYBACK_SPEED_MIN` / `MOVE_PLAYBACK_SPEED_MAX` | 0.3 / 1.2 | 新增——速度同步（实验 3） |
| `FRAME_ANIM_*_EXIT`（guard/parry_success/stagger/stance_break/dead 归位段） | 2–4 | 新增——hold 型 clip 出口归位帧数（§2.3 R2） |

> 全部新值带「候补值+影响什么+情感断言」三要素 # DRAFT 注释（E3 抽查协议）；**禁止实现期二选一偷定**，定稿归 #584 管线。

### 3.2 `shandong-wolf/gdscripts/stick_figure.gd`（骨架构建）

```gdscript
# _build_skeleton() 修改点:
# ① 头部: TorsoPivot 下新增 NeckPivot（Node2D @ (0,-body_torso_length)）+ 颈 Line2D；
#    HeadPivot 改挂 NeckPivot 下 @ (0,-BODY_NECK_LENGTH)；头圆半径默认值改 C.BODY_HEAD_RADIUS（修订值）
# ② 腿: LegLPivot/LegRPivot 保持（髋 pivot），新增子膝 pivot LegKPivot（@ (0,-BODY_LEG_UPPER_LENGTH)）
#    + 小腿 Line2D；大腿 Line2D 长度 = BODY_LEG_UPPER_LENGTH
# ③ 头轮廓（HEAD_OUTLINE_ENABLED 时）: HeadPivot 下追加圆环 Polygon2D（外圆 head_r+outline_w, holes=[内圆]）
# ④ get_pivot() 增 "neck" / "leg_k_l" / "leg_k_r" 键
```
- `_validate_geometry()` defaults 表同步增新导出（neck/leg upper/lower）；`@export` 增 `body_neck_length` / `body_leg_upper_length` / `body_leg_lower_length`。
- **不破坏:** `set_sprite_slot()` 原画接入点、SwordArc、sprite_slot 命名位零改动。

### 3.3 `shandong-wolf/gdscripts/stick_figure_controller.gd`（摆姿与节奏）

```gdscript
# ① _build_move_spec() 重写: frames = C.FRAME_ANIM_MOVE_CYCLE；contact/pass 关键姿态（§2.5）；
#    新增 2 条膝 rotation track
# ② 其余 10 个 _build_*_spec() 按 §2.3 规约重摆:
#    动作型: 首/尾帧 = REST_POSE（≤5°）；hold 型: 首帧 = REST_POSE + 尾部归位段（FRAME_ANIM_*_EXIT 帧）
# ③ 新增 REST_POSE 常量表（Dictionary，§2.3 表）+ set_move_speed(v)（§2.4）
# ④ play_clip() 零改动（衔接靠摆姿数据本身，不加 crossfade；同态重入 seek(0) 语义保持）
# ⑤ 所有 clip 的 HeadPivot track 路径前缀同步为 "TorsoPivot/NeckPivot/HeadPivot"（§2.1 结构变化）
```

### 3.4 `shandong-wolf/gdscripts/main_battle.gd`（装配接线）

```gdscript
# _build_player()/_build_enemy() 内: 保存 stick 引用为成员
#   _player_stick_figure = stick（PlayerStickFigure 根）/ _enemy_stick_figure = stick
#   （翻转目标 = stick.get_node("StickFigure") 子节点——红线: 绝不 scale 物理根/controller 根）
# 新增 _process 同步（每帧轮询，零信号依赖——facing 可能从多源变化: combat_entity._process /
#   enemy_ai_states 转向，轮询最稳）:
#   _last_player_facing / _last_enemy_facing 缓存，变化时设 StickFigure.scale.x = float(facing)
#   _sync_move_speed(): player 实体状态为 move 时 _player_stick_figure.set_move_speed(player.velocity.x)
#     （enemy 同: enemy.velocity.x；非 move 状态 set_move_speed 内部 no-op，可不判状态直接调）
```
- **数据源:** 玩家 facing = `player_entity.facing`（combat_entity.gd:219 输入轴同步）；敌人 facing = `enemy_entity.facing`（enemy_ai_states.gd:128 已把 AI facing 同步到 entity.facing）——单一事实源，避免读 enemy_ai 私有状态。
- **初始翻转:** 装配完成即按当前 facing 设一次 scale.x（防首帧朝向错误）。

### 3.5 `shandong-wolf/e2e_shots.json`（shot plan 微调）

| Shot | 变化 | 用途 |
|------|------|------|
| `02_move` | 拆为 `02a_move_contact` / `02b_move_pass`（at_frame 定格步态周期内 contact=0 与 pass=6/60s 帧） | 步态可裁决（AC2） |
| 新增 `03_head_readability` | idle 定格 + settle 拉长（白底对比照可选） | 头部可读性裁决（AC1，实验 1） |
| 其余 12 态 shot | 不变（attack 三段等保持） | 回归 |

> 具体 at_frame/settle 数值由 implement agent 按 e2e rig 契约（#586/#661 格式）落地；E2E 截图仅 --with-visual 下跑（#559 既定）。

### 3.6 测试文件（描述见 §8，不写可运行代码）

| 文件 | 变化 |
|------|------|
| `shandong-wolf/tests/test_stick_figure_animation.gd` | F1/F2 适配颈/膝结构（PIVOT_PARTS 增 neck/leg_k_l/leg_k_r；腿长断言改 BODY_LEG_UPPER_LENGTH）；新增 AC1（头身分离/比例）、AC2（步态周期/膝 track/摆臂反向）、AC3（姿态差枚举）用例 |
| `shandong-wolf/tests/test_main_assembly.gd` | 新增 facing 翻转断言（设 entity.facing → 驱动 _process → 断言 StickFigure.scale.x == facing） |

### 3.7 需更新的 GDD 文档（implement 期，plan 不落盘）

- [ ] `docs/GAME_DESIGN/shandong-wolf/07-STICK-FIGURE-ANIMATION.md`——骨架节点树加颈/膝、move 步态摆姿描述、facing 章节（§2.1 新接线）
- [ ] `docs/GAME_DESIGN/shandong-wolf/02-CONSTANTS.md`——新增 # DRAFT 常量行（§3.1 表）

---

## 4. 数据流

**Flow 1: 朝向翻转（正常路径）**
```
CombatEntity.facing（玩家: 输入轴同步 combat_entity.gd:219；敌人: enemy_ai_states.gd:128 同步）
    │  main_battle._process → _sync_visual_facing()（每帧轮询，缓存比对）
    ▼
StickFigure.scale.x = float(facing)   ← 仅视觉子节点（PlayerStickFigure/StickFigure）
    │  Line2D/Polygon2D 全子树自动镜像（刀/臂/头同步翻转，几何对称，摆姿无需改）
    ▼
玩家看到: 面左走左、挥刀方向与判定一致（#577 命中方向可读）
```

**Flow 2: 步频速度同步（正常路径）**
```
player.velocity.x（PlayerController 加速度模型, MOVE_ACCELERATION=1200）
    │  main_battle._process → _player_stick_figure.set_move_speed(v)
    ▼
StickFigureController.set_move_speed: 仅 current_animation=="anim_move" 时
    speed_scale = clamp(|v|/300, 0.3, 1.2)
    ▼
anim_move 24–32 帧步态按实际速度缩放播放 → 脚不滑步（匀速段每步位移 ≈ 步幅）
```

**Flow 3: 姿态衔接（状态切换）**
```
combat_state_table 合法转移 (from→to)   [状态机权威 #575，本层镜像]
    │  consume_state(to) → play_clip(to_clip)（契约不变，直接 play + seek(0)）
    ▼
目标 clip 首帧 = REST_POSE（动作型）或源 clip 尾帧 ≤15°（hold 型出口归位段已收敛）
    ▼
单测枚举全部合法对断言关节角差 ≤ POSE_DELTA_MAX_DEG —— AC3 从观感变可回归断言
```

---

## 5. 边界情况与错误处理

| # | 边界情况 | 处理 |
|---|---------|------|
| 1 | 起步/急停（速度 <30%） | `set_move_speed` 下限 0.3（不归零不静止）；状态机 move↔idle 转移（combat_entity.gd:215-219）已按输入轴切换——无「原地跑步」 |
| 2 | 反向移动瞬间（facing 变号） | scale.x 翻转是纯镜像，动画不重置、姿态连续（无姿态跳变）；轮询缓存比对保证翻转恰好一次 |
| 3 | 敌人 facing（初始 -1） | 装配即按当前 facing 设一次 scale.x；敌人面左持刀，判定方向（#577）与视觉一致 |
| 4 | 连招重入（attack→attack） | 同态重入重置前摇首帧语义不变（#574 §5-3）；重摆后 attack 首帧仍 = REST_POSE 起点 |
| 5 | headless/CI | 新断言全部节点树 + 角度数值断言，零渲染依赖；E2E 截图仅 --with-visual（#559 既定） |
| 6 | guard→parry_success→move 链 | 三态相邻：guard 尾帧（归位段后）→ parry_success 首帧 ≤15°；parry_success 尾帧 → move 首帧（REST_POSE）≤15°——单测覆盖该链 |
| 7 | 不同步速（speed_scale 连续变化） | loop 模式循环边界无缝（Godot loop 语义）；非 move clip 调用 set_move_speed 为 no-op，攻击/格挡节奏不受影响 |
| 8 | 膝结构改动破坏既有 clip（§5.3-1 失败路径） | 全量回归 11 clip + F 系列单测；F1 pivot 列表 / F2 腿长断言适配膝结构（§3.6）——若腿路径不兼容则 abort 报告，不硬解 |
| 9 | 头轮廓被裁决破坏剪影（taste 失败） | 回退轮廓（HEAD_OUTLINE_ENABLED=false，仅删轮廓节点），颈+比例保留——一次 taste 决策，不阻塞 AC1 主体 |
| 10 | facing 接线误作用物理层 | 接线目标硬约束 = `StickFigure` 子节点（§4.3-C 否决物理根）；新增装配单测（设 facing → 断言 scale.x 且 PlayerController.velocity 方向不受 scale 影响）拦截 |
| 11 | `FRAME_ANIM_MOVE_STEP` 语义修订破坏 E3 | 常量**保留**（值 4 不变，注释语义改「关键姿态数」），E3 三要素抽查继续通过——不删除常量 |
| 12 | 头径缩小导致头「更小看不清」（比例 vs 可读性张力） | 可读性由**颈分离 + 轮廓（可选）** 承载而非头径大小；头径候选 9–10 由实验 1/2 截图裁决，若裁决认为过小可回退 11–12（仍 ≤ GDD ±10%） |

---

## 6. 集成点

> **状态约定:** ⬜ = pending（实现期接线）；✅ = connected（implement agent 验证后更新）。review agent 在合并前核查全部 ⬜ 已解决或被显式推迟。

| 集成 | 本设计组件 | 目标系统 | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| facing → 视觉翻转 | main_battle `_sync_visual_facing()` | `CombatEntity.facing` / `enemy_entity.facing` | _process 轮询 + `StickFigure.scale.x` | ✅ |
| 步频 → 速度同步 | controller `set_move_speed(v)` | `PlayerController.velocity` / `EnemyAI.velocity` | main_battle._process 调用 | ✅ |
| 动画路径更新 | controller 各 clip track | StickFigure 新节点树（NeckPivot/LegKPivot） | track 路径 `TorsoPivot/NeckPivot/HeadPivot`、`LegLPivot/LegKPivot:rotation` | ✅ |
| 姿态衔接断言 | 新增 AC3 单测 | `combat_state_table.gd` TRANSITIONS | 枚举合法对 vs clip 首/尾帧关键帧 | ✅ |
| 步态裁决截图 | e2e_shots.json move 组 | E2E 截图链路（#661/#662/#678） | at_frame 定格 shot | ✅ |
| 头轮廓 taste 裁决 | HEAD_OUTLINE_* 常量 | E2E 截图对比（实验 1） | 带/不带轮廓双 shot 用户裁决 | ✅ |
| 帧数值定稿 | 新 # DRAFT 常量 | #584 定稿管线 | 候补值注释协议，实现前查 #584 状态 | ✅ |

---

## 7. 实现阶段

| Phase | 优先级 | 组件 | 估计 |
|:-----:|:------:|------|:----:|
| Phase 1 | P0 | `constants.gd` # DRAFT 新值/修订（§3.1） | 0.5 人日 |
| Phase 2 | P0 | `stick_figure.gd` 结构（颈 + 膝 + 头径/轮廓 + get_pivot 扩展） | 1–1.5 人日 |
| Phase 3 | P0 | `stick_figure_controller.gd`（move 步态重排 + 11 clip REST_POSE 重摆 + set_move_speed + track 路径更新） | 2–3 人日 |
| Phase 4 | P0 | `main_battle.gd` facing + set_move_speed 接线 | 0.5 人日 |
| Phase 5 | P0 | 单测（F1/F2 适配 + AC1/AC2/AC3 新增 + 装配 facing 断言） | 1–1.5 人日 |
| Phase 6 | P1 | `e2e_shots.json` shot plan + E2E 截图裁决 + GDD 文档更新 | 1 人日 |

> 依赖顺序：1→2→3（骨架结构是动画摆姿前提）→4（接线依赖 controller API）→5（依赖 2/3/4）→6（依赖 3 的步态定稿候选）。Phase 3 与 Phase 2 合并工作量最大（clip 重摆与膝结构叠加，PRD §4.4-A 已声明合并计算）。

---

## 8. 测试用例描述

> **说明:** 本阶段只写测试**描述**，不写可运行测试文件（plan 阶段红线）。用例编号 T 起；`test_stick_figure_animation.gd` 沿用既有 F/E/C 系列命名风格，新增 AC 系列；`test_main_assembly.gd` 增 MA 系列。全部 headless 可跑（节点树 + 数值断言，零渲染）。

### Scenario AC1: 头部可读性（issue AC1）

- **T1 头身分离**: 实例化 player_stick_figure.tscn，读取骨架节点树，断言 `NeckPivot` 存在、其下 Line2D 长度 == `BODY_NECK_LENGTH`（容差 0.01）、`HeadPivot` 为 NeckPivot 子节点。前置：Phase 2。预期：通过。
- **T2 头身重叠 ≤4px**: 由头圆最低点（HeadPivot.position.y - BODY_HEAD_RADIUS）与躯干顶（-BODY_TORSO_LENGTH）计算重叠量，断言 ≤4px。前置：Phase 2。预期：通过（修复前 = 16px）。
- **T3 头径比例 ∈ GDD ±10%**: 断言 `2×BODY_HEAD_RADIUS / BODY_TORSO_LENGTH ∈ [1/2.75, 1/2.25]`（GDD 头:躯干 = 1:2.5 ±10%）。前置：Phase 1。预期：通过（头径 18–20 / 躯干 44 ≈ 1:2.2–2.44）。
- **T4 头轮廓开关（可选）**: `HEAD_OUTLINE_ENABLED=true` 时 HeadPivot 下有圆环 Polygon2D（polygon 外圆半径 == head_r + outline_w，holes 内圆 == head_r）；false 时无。前置：Phase 2。预期：随常量走。
- **T5 E2E 头可读性截图（渲染级）**: `03_head_readability` shot 在雪夜背景截图，缩放后头部轮廓可辨识（review 侧人工/像素辅助裁决）。前置：Phase 6。预期：通过或触发轮廓 taste 决策（实验 1）。

### Scenario AC2: 走路动画（issue AC2）

- **T1 步态周期 ∈ [24,32] 帧**: 读取 anim_move 的 `length`，断言 `length × 60 ∈ [24, 32]`（容差 ±1 帧）。前置：Phase 3。预期：24（默认候选）。
- **T2 膝 pivot 存在且受动画驱动**: 断言 `get_pivot("leg_k_l")` 非 null；anim_move 含 `LegLPivot/LegKPivot:rotation` track 且关键帧数 ≥3（contact/pass/contact）。前置：Phase 2+3。预期：通过。
- **T3 步态循环内脚不滑步（关键姿态断言）**: 断言 contact 帧两腿髋摆幅 == `MOVE_SWING_LEG_DEG`、膝屈曲 == 0；pass 帧摆动腿膝屈曲 == `MOVE_KNEE_BEND_DEG`；配合速度同步（T4）匀速段位移 ≈ 步幅。前置：Phase 3。预期：通过。
- **T4 播放速度同步**: 构造 move 状态，调 `set_move_speed(300)` → `speed_scale == 1.0`；`set_move_speed(90)` → `== 0.3`（下限）；`set_move_speed(400)` → `== 1.2`（上限）；非 move clip 时调用 → speed_scale 不变（no-op）。前置：Phase 3+4。预期：通过。
- **T5 摆臂反向同频**: 断言 anim_move 中 ArmLPivot 与 LegRPivot 同相、ArmRPivot 与 LegLPivot 同相（关键帧角度符号相反）。前置：Phase 3。预期：通过。
- **T6 facing 翻转（装配级，test_main_assembly.gd MA 系列）**: 实例化 MainBattle，设 `player_entity.facing = -1`，驱动 `_process`，断言 `PlayerStickFigure/StickFigure.scale.x == -1`；设回 1 → scale.x == 1；同时断言 `PlayerController` 根 scale 未变（物理层零影响红线）。前置：Phase 4。预期：通过。
- **T7 敌人 facing 翻转**: 同 T6 敌人侧（`enemy_entity.facing = -1` → EnemyStickFigure/StickFigure.scale.x == -1，e2e rig 初始值场景）。前置：Phase 4。预期：通过。
- **T8 E2E 步态定格截图（渲染级）**: `02a_move_contact` / `02b_move_pass` 截图可裁决（contact 支撑相脚着地、pass 摆动腿屈膝抬脚）。前置：Phase 6。预期：通过或触发实验 2/3 裁决。

### Scenario AC3: 骨架一致性（issue AC3）

- **T1 姿态差 ≤15° 枚举**: 读 `combat_state_table.gd` TRANSITIONS 全部合法转移对 (from,to)，对每对断言目标 clip 首帧与源 clip 尾帧各关节角差 ≤ `POSE_DELTA_MAX_DEG`（逐关节枚举：torso/head/arm_l/arm_r/sword/leg_l/leg_r + 膝）。前置：Phase 3。预期：全对通过（重摆后）。
- **T2 既有 C1 保持**: idle→move→attack→guard→stagger 全链切换耗时 ≤ `FRAME_ANIM_TRANSITION_MAX`/60（既有断言保持绿，不因重摆回归）。前置：Phase 3。预期：通过。
- **T3 膝单向弯曲上限**: 全部 clip 的膝 track 关键帧角度绝对值 ≤ `KNEE_BEND_MAX_DEG`（90°）。前置：Phase 3。预期：通过。
- **T4 同态重入语义保持**: attack→attack 重入后 clip 播放位置 == 前摇首帧（既有 G1 断言保持）。前置：Phase 3。预期：通过。
- **T5 关键链专项**: guard→parry_success→move 三态相邻对姿态差 ≤15°（显式枚举该链，T1 全覆盖的抽验）。前置：Phase 3。预期：通过。

### Scenario R: 回归（既有测试保持/适配）

- **R1 F1 pivot 树适配**: PIVOT_PARTS 增 `neck`/`leg_k_l`/`leg_k_r`；头仍 Polygon2D、其余 Line2D；新 pivot 子节点类型断言（neck Line2D、膝下小腿 Line2D）。前置：Phase 2。预期：通过。
- **R2 F2 几何参数适配**: 腿长断言改为大腿 `BODY_LEG_UPPER_LENGTH` + 小腿 `BODY_LEG_LOWER_LENGTH`；颈长 == `BODY_NECK_LENGTH`；其余（torso/arm/sword/头半径）不变。前置：Phase 1+2。预期：通过。
- **R3 E3 # DRAFT 三要素保持**: `FRAME_ANIM_MOVE_STEP`（语义修订后）注释块仍含「候补值/该值影响什么/情感断言」。前置：Phase 1。预期：通过。
- **R4 E1 attack 时间戳保持**: anim_attack 三段时间戳 == FRAME_ANIM_ATTACK_* /60（重摆不破坏三段结构）。前置：Phase 3。预期：通过。
- **R5 全量测试套件**: `godot --path shandong-wolf/ --headless --script tests/run_tests.gd` 全绿（19 套件 + 新增用例）。前置：Phase 5。预期：0 fail。

### 既有用例影响清单

| 用例 | 影响 | 处置 |
|------|------|------|
| F1（7 pivot 树） | 结构变化（颈/膝新增，HeadPivot 层级变化） | 适配（R1） |
| F2（几何参数） | 腿长/头径断言值变化 | 适配（R2） |
| C1（切换耗时） | 无（play 机制不变） | 保持 |
| C2（stagger→idle 兜底） | 无（主策略保持） | 保持 |
| E1/E2/E3（constants 派生） | E3 依赖 FRAME_ANIM_MOVE_STEP 常量存在 | 保持（常量保留语义修订，R3） |
| G1（同态重入）/ H1（未知态）/ I1-I3（clip 注册） | 无（consume_state 契约不变） | 保持 |
| test_main_assembly A/B 系列 | 无（装配契约不变，仅新增 facing 断言） | 保持 + 新增 MA 系列 |

---

## 9. 验收条件映射（issue body + PRD §5.1）

| # | 验收条件 | 设计落点 | 验证方式 |
|---|---------|---------|---------|
| AC1 | 角色有清晰的头部 | §2.1（颈 + 比例 + 可选轮廓） | T1/T2/T3（结构断言）+ T5（E2E 截图） |
| AC2 | 走路动画自然（步伐与速度匹配、摆臂合理） | §2.2/§2.4/§2.5（膝 + 24–32 帧步态 + 速度同步）+ §3.4（facing 接线） | T1–T5（步态断言）+ T6/T7（facing）+ T8（E2E 截图） |
| AC3 | 攻击/格挡/被击各状态骨架正常（不拉伸/错位/抖动） | §2.3（REST_POSE + 衔接规约） | T1–T5（姿态差枚举 + C1 保持） |
| — | 结构修正为主，审美微调归 taste 通道 | 头轮廓/帧数/幅度全部 # DRAFT 候选 + E2E 裁决 | 实验 1/2/3 截图用户裁决 |
| — | 零美术资产 / 剪影风格保持 | 全部程序化 Line2D/Polygon2D，无贴图无辉光 | R1（节点类型断言）+ diff 守卫 |

### 实现 PR 的 E2E gate（PRD §8 交接上下文转述）

1. 全量单测绿（R5，含新增 AC 系列）
2. E2E stick_figure 组截图：`02a_move_contact` / `02b_move_pass` / `03_head_readability` 产出（--with-visual）
3. 用户裁决：头部轮廓去留（实验 1）、步态帧数 24/28/32（实验 2）、速度同步策略（实验 3）
4. 实现前确认 #584 状态，对齐帧数值定稿协议

---

## 10. 明确不修改（与 PRD §3.3/§8 红线对齐）

- ❌ `shandong-wolf/gdscripts/combat_entity.gd` / `combat_judge.gd` / `enemy_ai.gd`（#575/#577 交付物保护；facing 只被消费不修改）
- ❌ `shandong-wolf/gdscripts/player_controller.gd`（移动物理 #573 交付物；只消费 velocity）
- ❌ `shandong-wolf/gdscripts/sword_arc.gd` / `reaction_controller.gd` / `execution_orchestrator.gd` / `revive_orchestrator.gd` / `hud.gd` / `atmosphere.gd` 等其余组件（零改动）
- ❌ `shandong-wolf/gdscripts/stick_figure_anim_states.gd` / `state_machine.gd`（动画状态对象机制 #574 交付物）
- ❌ `project.godot`、`game-env/manifest.yaml`、`mini-pong/`、`.github/workflows/`、`scripts/`、`framework/`（跨游戏/管线红线）
- ❌ 任何贴图 / Sprite2D 美术资产（零美术资产红线 AC5；原画接入点 set_sprite_slot 保持预留）
- ❌ 任何可运行测试文件（本阶段只产出 DESIGN/TASKS 文档 + 测试用例描述；测试代码归 implement agent）
- ✅ `e2e_stick_figure_capture.gd`（rig 驱动契约不变，仅截图内容变化）/ `scenes/player_stick_figure.tscn`（节点结构零改动，脚本内程序化构建）
