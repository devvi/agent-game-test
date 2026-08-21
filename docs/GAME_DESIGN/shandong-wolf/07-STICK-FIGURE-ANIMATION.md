# 火柴人剪影骨架与关键帧动画 — Line2D 程序化骨架 + 11 态关键帧 + consume_state 契约 + additive 刀光 + 查询委托 API + 颈/膝骨架结构 + 24 帧步态循环 + REST_POSE 衔接规约 + facing 翻转接线（#574/#612/#681/#692/#683/#694）

> 落盘依据：PR #612（implement，已 merge 2026-08-19）← DESIGN `docs/DESIGN/574-stick-figure-silhouette-animation.md`；
> PRD `docs/PRD/574-stick-figure-silhouette-animation.md`（research PR #603，已 merge）。
> 上游：#572 逻辑地基（constants/StateMachineBase/Game autoload）、#584 调参面板（05-DEBUG-CANVAS.md）、
> #573 输入层（06-INPUT-CONTROLLER.md）——本层**只消费状态、不读输入**。

## 1. 设计意图

shandong-wolf 经 #572 已有逻辑地基（WolfConstants # DRAFT 分区 / StateMachineBase / Game autoload）与标题场景，
但 `scenes/` 无角色场景、`gdscripts/` 无角色脚本、`assets/` 空——**玩家没有任何「看得见的自己」**。
本 issue 交付 = **玩家火柴人骨架（程序化构建）+ 11 态关键帧动画 + consume_state 消费契约 + 帧节奏 DRAFT 值入库
+ E2E 截图用户裁决**。它是视觉核心 issue：后续 #575 状态机、#577 判定、#579 反馈、#580 处决、#578 复活
全部在本 issue 的「看得见的角色」上呈现。

**四条设计哲学（互相咬合）：**
1. **零美术资产（AC5）**——骨架几何全部 `.gd` 代码构建；**动画资源运行时动态生成**（Animation 对象代码构建、
   关键帧时间戳从 constants 派生），零 `.tres` 动画资源文件。比「预置 clip + 时间戳校验」更彻底地满足 AC5。
2. **动画只消费状态（issue 输入驱动契约）**——不读 Input、不订阅 #573 信号；唯一入口
   `consume_state(state: String)`。canonical 11 态集合权威归 #575，本层只做**镜像映射表**（单点同步 + 单测枚举保护）。
3. **帧节奏集中（AC3）**——`FRAME_ANIM_*` 全系列进 constants.gd `# DRAFT` 分区，继承 #572 注释规范
   （候补值 + 影响什么 + 情感断言）；与既有 `FRAME_ATTACK_RECOVERY=14` 的冲突值（10 vs 14）**双值共存互引注释，
   禁止实现期二选一偷定**，定稿归 #584。
4. **视觉/逻辑解耦（AC2）**——刀光 = SwordArc（Polygon2D additive）独立纯视觉节点，节点树无任何碰撞类型；
   判定归 #577，反馈归 #579。

## 2. 架构决策（PRD §4 方案裁决，四项全部方案 A）

| 决策点 | 方案 A（采纳） | 否决方案 | 否决理由 |
|--------|---------------|---------|---------|
| 骨架构建 | Line2D/Polygon2D 程序化骨架 + AnimationPlayer 关键帧摆姿 | B：Skeleton2D 蒙皮；C：Sprite2D 序列帧 | B 零资产前提下权重程序化复杂度过高；C 违反 AC5 零美术资产红线 |
| 帧节奏 | constants.gd `FRAME_ANIM_*` # DRAFT 分区 | 动画内硬编码 | 违反 AC3 数值集中 |
| 消费接口 | `StickFigureController.consume_state(state)` 状态名→clip 映射 | 直读 #573 输入信号 | 违反 issue body 输入驱动契约 |
| 刀光 | `SwordArc` Polygon2D additive 独立节点 | 并入动画 clip | 无法独立调参且 #579 无法复用 |

> **开源调研（PRD §6.2）：** GitHub API + Asset Library 检索 6 项候选（Godot-2d-Bridge / godot-skeleton2d-helper /
> Stick-Figure-Battle 等）+ Skeleton2D 系——**无满足「程序化零资产 + Line2D 关键帧」的成熟开源组件**（候选均为
> 完整游戏架构不可剥离，或编辑器工具依赖美术资产管线）。按 issue「开源优先，找不到再自行实现」采用方案 A 自行实现。

## 3. 组件定义

### 3.1 `StickFigure`（gdscripts/stick_figure.gd，Node2D）— 程序化骨架

`_ready()` 用代码构建火柴人骨架节点树（零 tscn 资源依赖、零美术资产）；`@export` 几何参数默认值从
`WolfConstants` 读取（`const C = preload("res://gdscripts/constants.gd")`）；`_validate_geometry()` 非法参数
→ push_warning + 回退默认值，不崩溃。

```
StickFigure (Node2D)                    [script: stick_figure.gd]  ← scale.x = facing（#683 facing 接线，§3.5）
├── TorsoPivot (Node2D) ──── Line2D (躯干, BODY_TORSO_LENGTH × BODY_LIMB_WIDTH, BODY_COLOR)
│   ├── NeckPivot (Node2D) ─ Line2D (颈, BODY_NECK_LENGTH, BODY_COLOR)   ← #683 新增
│   │   └── HeadPivot (Node2D) ── Polygon2D (头圆, BODY_HEAD_RADIUS, BODY_COLOR)
│   │                            └── [可选] HeadOutline (Polygon2D 冷白环, HEAD_OUTLINE_*, #683 实验 1)
│   ├── ArmLPivot (Node2D) ── Line2D (左臂, BODY_ARM_LENGTH, BODY_COLOR)
│   ├── ArmRPivot (Node2D) ── Line2D (右臂, BODY_ARM_LENGTH, BODY_COLOR)
│   └── SwordPivot (Node2D) ─ Line2D (刀, SWORD_LENGTH × SWORD_WIDTH, SWORD_COLOR)
│                             └── SwordArc (Polygon2D, additive 刀光 — §3.4)
├── LegLPivot (Node2D) ── Line2D (左大腿, BODY_LEG_UPPER_LENGTH) ── LegKPivot (Node2D) ── Line2D (左小腿, BODY_LEG_LOWER_LENGTH)
└── LegRPivot (Node2D) ── Line2D (右大腿, BODY_LEG_UPPER_LENGTH) ── LegKPivot (Node2D) ── Line2D (右小腿, BODY_LEG_LOWER_LENGTH)
```

10 个 pivot（torso/head/neck/arm_l/arm_r/sword/leg_l/leg_r/leg_k_l/leg_k_r），供 AnimationPlayer 关键帧寻址 + 单测断言。
**原画接入点（PRD §4.1）：** 预留 `set_sprite_slot(sprite)` 与命名子节点位 `sprite_slot`——后续正式原画
换 Sprite2D 层时保留骨架结构，零重构。

### 3.2 `StickFigureController`（gdscripts/stick_figure_controller.gd，Node2D 根）— consume_state 契约 + 11 态→clip 映射

场景根；持有 StickFigure + AnimationPlayer；**唯一动画入口**（issue 输入驱动契约：不读 Input、不订阅 #573 信号）。

```gdscript
func consume_state(state: String) -> void
# 1. state 先过映射表（canonical 11 态 + 别名），映射失败 → 降级 idle + push_warning
# 2. 目标 clip == 当前 clip → 同态重入：重置到该 clip 前摇首帧（连招语义）
# 3. AnimationPlayer.play(clip, custom_blend) —— 过渡策略见下
# 4. 播放前 stop 旧 clip（防叠播）
```

**状态名→clip 镜像映射表（与 #575 canonical 逐条对齐；run/parry 为 issue body 声明的别名）：**

| canonical 状态（#575 权威） | clip 名 | 备注 |
|:---:|:---:|------|
| idle | `anim_idle` | 待机呼吸（微幅上下浮动） |
| move | `anim_move` | 步态循环（FRAME_ANIM_MOVE_CYCLE=24 帧，contact/pass 关键姿态；#683 重排）；**run 别名 → move**（issue body 明文） |
| attack | `anim_attack` | 三段：前摇 8 / 暴发 4 / 收招 10（时间戳从 constants 派生） |
| heavy_attack | `anim_heavy_attack` | 重砍（蓄力感更强的前摇；帧数 DRAFT 候补，与 attack 同分区） |
| guard | `anim_guard` | 横刀胸前；**parry 别名 → guard**（格挡/弹反共用姿态，issue body 明文） |
| parry_success | `anim_parry_success` | 弹反成功硬直帧（#577 结果事件的视觉回报） |
| stagger | `anim_stagger` | 受击后仰（与 idle 尾帧跳变大 → 触发插值 fallback） |
| stance_break | `anim_stance_break` | 架势崩解失衡 |
| execute | `anim_execute` | 处决上撩→斩落（FRAME_ANIM_EXECUTE_TOTAL=5 帧；流程驱动归 #580） |
| revive | `anim_revive` | 起身关键帧（驱动归 #578） |
| dead | `anim_dead` | 倒地帧（驱动归 #578） |

**过渡 ≤2 帧策略（AC1）：** 主策略 = 直接 `play()` + 「clip 首帧姿态 = 上一状态尾帧姿态」设计约定
（idle→move→attack→guard→stagger 链路上逐 clip 对齐，引擎同帧切换即满足 ≤2 帧，无需 blend）；
兜底策略（跳变大的转移如 stagger→idle、stance_break→idle）= 2 帧手动姿态插值（tween pivot rotation
→ 目标 clip 首帧姿态，时长 = FRAME_ANIM_TRANSITION_MAX/60s）。

**#683 姿态衔接规约（REST_POSE 公共基准，docs/DESIGN/683 §2.3）：** 定义 REST_POSE 自然站姿
（torso 0° / head 0° / arm_l 178° / arm_r 172° / sword 160° / leg 0° / 膝 0°）作公共基准——
R1 动作型 clip（idle/move/attack/heavy_attack/execute/revive）首/尾帧 = REST_POSE（≤5°）；
R2 hold 型 clip（guard/parry_success/stagger/stance_break/dead）首帧 = REST_POSE + 尾部
`FRAME_ANIM_*_EXIT` 归位段（2–4 帧）收敛回 REST_POSE。配合 `consume_state` 直接 play + seek(0)
（无 crossfade），任意合法转移对的关节角差 ≤ POSE_DELTA_MAX_DEG=15°（AC3 单测枚举断言）。

**#683 步频速度同步（set_move_speed，docs/DESIGN/683 §2.4）：** 仅 `anim_move` 播放时生效，
`speed_scale = clamp(|v|/MOVE_MAX_SPEED, MOVE_PLAYBACK_SPEED_MIN, MOVE_PLAYBACK_SPEED_MAX)`
——匀速段（300px/s）每步位移 ≈ 步幅，消除脚滑步；非 move clip 调用为 no-op。

**#683 视觉 facing 翻转（docs/DESIGN/683 §3.4）：** `main_battle.gd._sync_visual_facing()` 每帧
轮询 `CombatEntity.facing`（玩家输入轴同步 / 敌人 AI 同步），变化时设 `StickFigure.scale.x = facing`
（仅视觉子节点，物理根/controller 根 scale 恒 1.0——#577 判定方向与视觉一致）。

**动画资源动态生成（零 .tres，AC3/AC5）：** `_build_clip(name, keyframes)` 运行时构建 Animation 对象——
`length = 总帧数 / FRAME_RHYTHM_BASE`，关键帧时间戳 = 帧数/60（帧数全部来自 `FRAME_ANIM_*` 常量），
track 路径 = 骨架 pivot NodePath；注册进 AnimationPlayer 默认库。11 个 clip 与映射表一一对应。

### 3.3 动画状态对象集（gdscripts/stick_figure_anim_states.gd）— 派生 StateMachineBase

基于 `StateMachineBase` 派生的一组动画状态对象（RefCounted，每态一个内部类，11 个）：
`AnimStateIdle` / `AnimStateMove` / `AnimStateAttack` / `AnimStateHeavyAttack` / `AnimStateGuard` /
`AnimStateParrySuccess` / `AnimStateStagger` / `AnimStateStanceBreak` / `AnimStateExecute` /
`AnimStateRevive` / `AnimStateDead`。

**职责边界：** 本文件**不是战斗状态机**（权威归 #575）。本层 = 「动画层最小调度」：每态 `enter()` 调
`controller.play_clip(clip)`；`update(delta)` 转发给 AnimationPlayer 推进（Attack 态维护 phase 0/1/2 阶段标记，
供 SwordArc 在暴发段触发）。薄契约，接口替换成本低。

```gdscript
class AnimStateAttack:
    extends RefCounted
    var controller: Object            # StickFigureController 引用
    var phase: int = 0                # 0=前摇 1=暴发 2=收招
    func enter() -> void:
        controller.play_clip("anim_attack")   # 时间戳来自 constants，播放即含三段
        phase = 0
    func update(delta: float) -> void:
        # 依据 AnimationPlayer 当前时间推进 phase；暴发段首帧 → controller.trigger_sword_arc()
```

### 3.4 `SwordArc`（gdscripts/sword_arc.gd，Polygon2D）— additive 刀光弧线

挂在 SwordPivot 下随刀旋转；**纯视觉层——节点树无 Area2D/CollisionShape2D**（判定归 #577，零交集）。
材质 `CanvasItemMaterial` + `blend_mode = BLEND_MODE_ADD`（additive 合成，代码设置，零 .tres）。

```gdscript
func _build_polygon() -> void:
    # 以 SwordPivot 为圆心：半径 SWORD_ARC_RADIUS，张角 SWORD_ARC_SWEEP_DEG(120°)
    # 分 SWORD_ARC_RINGS(4) 环，环间 alpha 从 SWORD_ARC_ALPHA_START(0.6) 线性衰减到 0
    # polygon = PackedVector2Array（弧扇顶点）；vertex_colors = PackedColorArray（逐顶点 alpha）
func trigger_burst() -> void:
    # 暴发段首帧调用: visible=true + _fade_frames = FRAME_ANIM_SWORD_ARC_FADE(4)
    # _process: _fade_frames 递减 → modulate.a 线性衰减 → 归零隐藏（短衰减 ≈4 帧，反页游光效）
```

集成：**#579 打击反馈直接复用本节点**（火花叠加 / hit-stop 锚点），零重构。

### 3.5 场景装配 + E2E 截图像具

**`scenes/player_stick_figure.tscn`**（最小化声明，骨架仍由代码构建）：根 `PlayerStickFigure`
[script: stick_figure_controller.gd] + `StickFigure` [script: stick_figure.gd] + `AnimationPlayer`
（动画库运行时动态注册）。独立场景，**不嵌入 Main.tscn**（PRD §1.1 红线）。

**`scenes/e2e_stick_figure_capture.tscn` + `gdscripts/e2e_stick_figure_capture.gd`（AC4）：**
CaptureRig 截图专用场景 = 深冷底色（反差裁决用）+ Player 实例 + 驱动：
- `current_state: int` 属性（12 值：IDLE=0 … DEAD=11）——shot plan 的 `state_node`/`state_property` 轮询目标
- digit 键 1-9/0 映射 → `consume_state(...)`（press 注入驱动）；attack 三段 = 3 个独立 shot state
- **auto_cycle 兜底**：e2e_capture.gd 的 press 注入不支持 digit 键（`_keycode_for` 仅 enter/space/esc/方向键），
  DESIGN §2.7 回退路径——capture 脚本自循环状态序列 + 定时自截图（经 autoplay.tweaks 开启）
- `e2e_shots.json` 填充顶层 `main_scene` + `stick_figure` shot group（12 态 shot，attack 3 段独立截图）

## 4. 常量定义（#574 追加，全部 `# DRAFT` 候补值，待 #584 定稿）

文件：`shandong-wolf/gdscripts/constants.gd`（§3.2 帧节奏分区内追加，+ 新「刀光弧线参数」分区，见 02-CONSTANTS.md §3.3）。

### 4.1 动画帧节奏（FRAME_ANIM_*，7 个）

| 常量 | 值 | 说明 |
|------|----|------|
| `FRAME_ANIM_ATTACK_WINDUP` | `8` | 攻击前摇（与 FRAME_ATTACK_WINDUP=8 对齐互引） |
| `FRAME_ANIM_ATTACK_BURST` | `4` | 挥刀暴发（刀光在此段触发） |
| `FRAME_ANIM_ATTACK_RECOVERY` | `10` | ⚠️ 与 FRAME_ATTACK_RECOVERY=14 冲突，双值共存互引，定稿归 #584 |
| `FRAME_ANIM_TRANSITION_MAX` | `2` | AC1 过渡上限（2 帧 @60fps = 0.033s） |
| `FRAME_ANIM_MOVE_STEP` | `4` | 步态摆臂循环 4 帧 |
| `FRAME_ANIM_EXECUTE_TOTAL` | `5` | 处决上撩→斩落 5 帧 |
| `FRAME_ANIM_SWORD_ARC_FADE` | `4` | 刀光存在/衰减帧数 |

### 4.2 骨骼几何与配色（BODY_* / SWORD_*，9 个）

| 常量 | 值 | 说明 |
|------|----|------|
| `BODY_COLOR` | `#2b2b2b` | issue body 指定墨色剪影 |
| `SWORD_COLOR` | `#c0c8d0` | 冷白刀身，雪夜反差点 |
| `BODY_HEAD_RADIUS` | `16.0` | 头圆半径 |
| `BODY_TORSO_LENGTH` | `44.0` | 躯干长（头:躯干:臂:腿 ≈ 1:2.5:1.9:2.2） |
| `BODY_ARM_LENGTH` | `34.0` | 臂长 |
| `BODY_LEG_LENGTH` | `40.0` | 腿长 |
| `BODY_LIMB_WIDTH` | `6.0` | Line2D width |
| `SWORD_LENGTH` | `88.0` | 长刀，视觉焦点 |
| `SWORD_WIDTH` | `5.0` | 刀宽 |

### 4.3 刀光弧线参数（SWORD_ARC_*，4 个）

| 常量 | 值 | 说明 |
|------|----|------|
| `SWORD_ARC_SWEEP_DEG` | `120.0` | 张角（PRD 实验 2 预期最佳值） |
| `SWORD_ARC_RADIUS` | `70.0` | 弧半径 |
| `SWORD_ARC_RINGS` | `4` | 径向透明度衰减环数 |
| `SWORD_ARC_ALPHA_START` | `0.6` | 起始 alpha |

> 全部经 #584 调参面板可运行时 override（仅进程内生效，不破坏 DRAFT 纪律，见 05-DEBUG-CANVAS.md §4）。

## 5. 数据流

### Flow 1: 动画消费（正常路径）

```
#575 战斗状态机（后续 issue，权威状态源；当前为测试桩/最小调度）
    │  transition_to(attack)
    ▼
StickFigureController.consume_state("attack")
    │  ① 映射表: attack → anim_attack（#575 canonical，run→move / parry→guard 别名）
    │  ② 同态检查: 当前 clip==anim_attack → 重置前摇首帧（连招语义）; 否则继续
    │  ③ stop 旧 clip → AnimationPlayer.play("anim_attack")
    ▼
AnimationPlayer 播放 anim_attack（运行时动态生成的 Animation，时间戳=constants 帧数/60）
    ├─ [0, 8/60]     前摇: TorsoPivot 下沉蓄力（FRAME_ANIM_ATTACK_WINDUP=8）
    ├─ [8/60, 12/60] 暴发: SwordPivot 挥砍旋转 + SwordArc.trigger_burst()（FRAME_ANIM_ATTACK_BURST=4）
    └─ [12/60, 22/60] 收招: 滞刀回位（FRAME_ANIM_ATTACK_RECOVERY=10）
            └──► 下一状态 consume_state → 过渡 ≤2 帧（直接 play + 首帧姿态约定 / 插值兜底）
```

### Flow 2: 动画资源动态生成（零 .tres，AC3/AC5）

```
_ready() → _build_all_clips()
  对 11 个状态: _build_clip(name, keyframes)
    ├─ length = Σ帧数 / FRAME_RHYTHM_BASE(60)
    ├─ 每 track = 骨架 pivot NodePath + 关键帧（rotation/position），时间戳 = 帧数/60（全部来自 FRAME_ANIM_*）
    └─ animation_player.get_animation_library("").add_animation(name, anim)
校验: 单测读 clip 关键帧时间戳 vs constants 值，容差 ±1 帧（Scenario E/I）
```

### Flow 3: 未知状态降级

```
consume_state("unknown_state")
    → 映射表无命中 → push_warning → 播放 anim_idle（不崩溃、不卡死动画）
    → 映射表注释标明 #575 为权威源；run/parry 别名显式处理
```

### Flow 4: E2E 截图流（AC4 用户裁决）

```
CI/本地: run-e2e-review.sh --with-visual
  → resolve_plan.py 读 e2e_shots.json（main_scene=capture 场景）→ 解析 stick_figure group
  → e2e_capture.gd 启动 capture 场景 → 轮询 /root/CaptureRig.current_state
  → 每 shot: digit 键 / auto_cycle 驱动 → CaptureRig 调 consume_state → 等 state 到位 + settle_frames → 截图
  → 11 态 PNG 落盘 docs/e2e-evidence/574-* → 提交用户裁决「小小系列干净力量感 + 雪夜水墨和谐」
  → 不通过 → taste-draft 领域: 调摆姿/帧节奏候补值重提交，机械接口不受影响
```

## 6. 边界情况与错误处理

| Edge Case | Mitigation |
|-----------|------------|
| 未知状态名（#575 canonical 漂移或调用方传错） | 映射表无命中 → 降级 idle + push_warning，不崩溃（Scenario H） |
| 别名/大小写漂移（run/move、parry/guard 混用） | 只认 canonical 11 态；run→move、parry→guard 显式别名映射并注释 |
| 快速连续切换（attack 未播完再 attack） | 同态重入：重置到该 clip 前摇首帧而非从头重播（连招语义，Scenario G） |
| constants 冲突值（10 vs 14） | 双值共存互引注释，禁止实现期二选一偷定；#584 裁决后统一（Scenario E） |
| 跳变大的转移（stagger→idle 等） | 2 帧手动姿态插值兜底（tween pivot rotation → 目标首帧） |
| 旧 clip 叠播 | AnimationPlayer.play 前 stop 旧 clip（Scenario I 断言无叠播） |
| 动态生成 Animation 失败（clip 缺失） | consume_state 映射到缺失 clip → push_warning + 降级 idle（Scenario I） |
| 骨架几何参数非法（负长度/零宽度） | `_validate_geometry()` push_warning + 默认值兜底，不崩溃（Scenario L） |
| headless/CI 环境 | 动画单测不依赖真实渲染（仅节点树 + AnimationPlayer 时间戳断言）；E2E 截图 --with-visual 显式开启 |
| E2E 截图用户裁决不通过 | taste-draft 领域：摆姿/帧节奏候补值可调重提交；机械实现（骨架/接口/单测）先行不受影响 |

## 7. 集成点

| Integration | Our Component | Target Issue | How | Status |
|-------------|:---:|:---:|-----|:---:|
| 状态消费 | `StickFigureController.consume_state(state)` | #575 | 战斗状态机 transition → consume_state（canonical 11 态，本层镜像映射） | ⬜ pending |
| 输入契约对齐 | consume_state 不读输入 | #573 | #573 只发意图事件给 #575，不直连本层（issue body 输入驱动契约） | ⬜ pending |
| 判定视觉回报 | `anim_guard` / `anim_parry_success` | #577 | 弹反结果事件 → parry_success 硬直帧播放 | ⬜ pending |
| 刀光复用 | `SwordArc` | #579 | 火花/hit-stop 叠加在刀光节点上（additive 合成），零重构 | ⬜ pending |
| 处决帧 | `anim_execute` | #580 | 处决流程驱动 execute clip（上撩→斩落 5 帧） | ⬜ pending |
| 复活/倒地帧 | `anim_revive` / `anim_dead` | #578 | 两条命流程驱动起身/倒地关键帧 | ⬜ pending |
| 数值定稿 | `FRAME_ANIM_*` # DRAFT 分区 | #584 | 候补值 → 用户定稿（替换值 + 去标记）；冲突值 10vs14 由 #584 裁决 | ⬜ pending |
| 原画接入点 | `StickFigure.set_sprite_slot()` | 后续原画 | 换 Sprite2D 层，保留骨架结构（PRD §4.1） | ⬜ pending |
| 单测挂载 | run_tests.gd | 本 issue | `_run("res://tests/test_stick_figure_animation.gd", ...)` | ✅ done |
| 动画状态对象 | stick_figure_anim_states.gd | 本 issue | 最小调度驱动（#575 落地前可独立运行） | ✅ done |
| E2E 截图 | capture 场景 + e2e_shots.json | 本 issue | --with-visual 跑 shot plan → docs/e2e-evidence/ → 用户裁决 | ⬜ pending（交用户） |

## 8. 测试（test_stick_figure_animation.gd，Scenario A–L）

- **A 映射与别名**：canonical 抽查 5 态 + run→move / parry→guard 别名
- **B 11 态映射完整性**：全态枚举断言（防 #575 状态名漂移漏映射）
- **C 过渡 ≤2 帧（AC1）**：idle→move→attack→guard→stagger 全链 t1-t0 断言；跳变大转移插值兜底
- **D 刀光 additive 无碰撞（AC2）**：SwordArc 子树无 Area2D/CollisionShape2D + blend_mode == BLEND_MODE_ADD
- **E constants 派生（AC3）**：attack 三段时间戳 vs 常量 ±1 帧；10vs14 双值并存；# DRAFT 三要素注释
- **F 骨架构建**：7 pivot 存在、几何参数与颜色 == BODY_*/SWORD_* 常量
- **G 同态重入**：attack 重入重置回前摇首帧（时间 == 0）
- **H 未知状态降级**：播放 anim_idle + push_warning，无崩溃
- **I 零资源无叠播**：11 clip 全注册；无新增 .tres/.res；连续切换无叠播
- **J 三入口回归**：check_compile / smoke / run_tests 退出 0（pass==0 → 非 0 防静默绿）
- **K E2E 截图用户裁决（AC4）**：stick_figure group 12 shot 全覆盖 + 落盘 docs/e2e-evidence/574-*.png
- **L 非法参数兜底**：负长度/零宽度 → push_warning + 默认值，骨架仍构建成功

## 9. 相关 Issue 记录

| Issue | 内容 | 状态 |
|-------|------|------|
| #574 | 火柴人剪影骨架与关键帧动画（本文件所属） | 已合并（#612） |
| #575 | 战斗状态机（consume_state 权威状态源，canonical 11 态） | 待实现 |
| #573 | 输入映射与玩家控制器（本层不读输入，只消费状态） | 已合并（#611） |
| #584 | 帧节奏/骨骼几何/刀光参数 # DRAFT 定稿（含 10vs14 裁决） | 草稿已合并（#609），待用户定稿 |
| #681 | 攻击查询委托补漏（StickFigureController +2 查询方法，本文件 §10） | 已合并（#692） |
| #683 | 火柴人结构完整化（颈/膝骨架 + 24 帧步态 + REST_POSE 衔接 + facing 翻转，本文件 §3.1/§3.2 更新） | 已合并（#694） |

## 10. 查询委托 API（#681 补漏，2026-08-21 合并 #692）

### 10.1 背景与意图

**问题本质是「调用方契约已写死、实现方缺失」的一侧缺口（half-implemented contract）：** #574 实现期在
**调用方**——`stick_figure_anim_states.gd:111`（AnimStateAttack.update 每帧）与 `e2e_stick_figure_capture.gd:129-130`
（E2E 截图像具轮询）——自创并直接调用了 `get_animation_position()` / `is_animation_playing()` 两个方法名，但漏掉了
在 **StickFigureController 上实现这两个 callee**。运行时每次攻击（键盘 J / 鼠标左键，input map 同一 action 双绑定）
→ AnimStateAttack.update 每帧调用缺失方法 → 稳定 SCRIPT ERROR：`Invalid call. Nonexistent function 'get_animation_position'`，
attack 三段 phase（0 前摇 / 1 暴发 / 2 收招）判定完全失效，E2E 攻击三段截图（WINDUP/BURST/RECOVERY）同步崩。

**修复哲学：只补 callee，不动 caller 契约；与 `play_clip()` 既有委托风格逐字一致。** 调用方契约是既成事实不可修改
（改动 = 扩散 diff + 违背「最小修复面」）；callee 薄委托 `_anim`、不暴露 AnimationPlayer 本体；null-guard 是硬性要求
（`_anim` 可能为 null，`_ready()` 已 push_warning）。**一处实现、两路受益**——AnimStateAttack 主路径（每次攻击）与
E2E capture 路径（截图轮询）同时被满足。

### 10.2 方法定义（`gdscripts/stick_figure_controller.gd`，置于 `play_clip()` 附近）

查询方法与播放方法同区，供动画状态对象 / E2E 截图像具消费。

```gdscript
func get_animation_position() -> float:
    ## 供动画状态对象 / E2E 截图像具查询 AnimationPlayer 当前播放位置（秒）
    if _anim == null:
        return 0.0
    return _anim.current_animation_position

func is_animation_playing() -> bool:
    ## 供 E2E 截图像具查询动画是否在播（null-guard）
    if _anim == null:
        return false
    return _anim.is_playing()
```

### 10.3 参数与语义

| 方法 | 委托目标 | null-guard 默认值 | 语义要点 |
|------|---------|:---:|------|
| `get_animation_position() -> float` | `_anim.current_animation_position` | `0.0` | 只读无副作用；`seek()` 后同步反映新位置（同态重入：play_clip 内部 seek(0.0) → 下一帧查询 ≈ 0 → phase 回 0，连招语义保持） |
| `is_animation_playing() -> bool` | `_anim.is_playing()` | `false` | 只读；E2E capture 判断「动画播完 → 回 IDLE」 |

### 10.4 消费方与数据流

| 消费方 | 位置 | 用途 |
|--------|------|------|
| AnimStateAttack.update | `stick_figure_anim_states.gd:111` | 每帧 `var pos = controller.get_animation_position()` → 三段 phase 判定：pos < 8/60 前摇（0）/ < 12/60 暴发（1）/ ≥ 12/60 收招（2） |
| e2e capture 轮询 | `e2e_stick_figure_capture.gd:129-130` | `get_animation_position()` + `is_animation_playing()` → WINDUP / BURST / RECOVERY / IDLE 截图态派生（播完回退 IDLE） |

**红线（DESIGN #681 §10 转述）：** 只加这两个方法——不修改 AnimStateAttack.update 调用契约（方法名 / 返回 float 保持）、
不新增动画状态、不碰 #575 战斗状态机、不改 constants 时间戳（FRAME_ANIM_ATTACK_WINDUP/BURST/RECOVERY 8/4/10 帧保持）、
不新增动画入口（consume_state 唯一入口契约保持）。
