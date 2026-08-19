# Design: [Feature] 火柴人剪影骨架与关键帧动画（Line2D/Polygon2D 程序化 + AnimationPlayer 摆姿）

> **Parent Issue:** #574
> **Agent:** game-plan-agent
> **Date:** 2026-08-19
> **Approach:** PRD §4 推荐组合 —— **四项全部确认采纳方案 A**：①骨架构建 = Line2D/Polygon2D 程序化骨架 + AnimationPlayer 关键帧摆姿（否决方案 B Skeleton2D 蒙皮：零资产前提下权重程序化生成复杂度过高；否决方案 C Sprite2D 序列帧：违反 AC5 零美术资产红线）；②帧节奏 = constants.gd 新增 `FRAME_ANIM_*` # DRAFT 分区（否决动画内硬编码：违反 AC3）；③消费接口 = `StickFigureController.consume_state(state)` 状态名→clip 映射（否决直读 #573 输入信号：违反 issue body 输入驱动契约）；④刀光 = `SwordArc` Polygon2D additive 独立节点（否决并入动画 clip：无法独立调参且 #579 无法复用）
> **Reference PRD:** `docs/PRD/574-stick-figure-silhouette-animation.md`（research PR #603 已合并 2026-08-19）
> **上游方案:** `docs/DESIGN/572-scaffold-main-entry.md`（WolfConstants # DRAFT 分区注释规范「候补值+影响什么+情感断言」、StateMachineBase 三接口派生、run_tests.gd `_run()` 挂载模式、DESIGN 文档结构）；`agents/skills/game-to-issues/references/visual-implementation-path.md` §6.5 火柴人动作视觉配方（2026-08-19 用户指定《小小系列》Flash 火柴人为参考坐标：关键帧摆姿 + 帧节奏「起势慢→爆发快→收招滞」）
> **所有权:** `content_ownership: mechanical`（骨架构建/动画调度/consume_state 接口 = 机械实现，无品味裁决空间；摆姿观感/帧节奏候补值 = taste-draft，E2E 截图交用户定稿，数值定稿归 #584）
> **深度:** deep（分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=3 标注 depth: deep；GitHub 无 depth 标签，同 #572 先例）—— 10 文件 / 5 子系统（骨架/动画资源/调度/刀光/E2E 截图像具）+ 用户裁决环节 → **产出 DESIGN + TASKS 文档**（skill deep 必填）
> **并行上下文:** worktree 并行 —— constants.gd 为**追加式新增分区**（FRAME_ANIM_* 不触碰既有 5 分区常量行，与 #573/#584 无同区改写冲突）；新文件全部独立命名（`stick_figure*` / `sword_arc*` / `player_stick_figure.tscn` / `e2e_stick_figure_capture*`），与 #573（input_map/player_controller）无共享文件；唯一共享文件 = `e2e_shots.json`（当前占位，本 issue 填充，后续 issue 追加 group 不冲突）

---

## 1. 架构总览

**问题本质是「有地基、无角色视觉」。** shandong-wolf 经 #572 已具备逻辑地基（WolfConstants # DRAFT 分区 / StateMachineBase / Game autoload）与标题场景（#562/#563/#570），但 `scenes/` 无角色场景、`gdscripts/` 无角色脚本、`assets/` 空——玩家没有任何「看得见的自己」。本 issue 交付 = **玩家火柴人骨架（程序化构建）+ 11 态关键帧动画 + consume_state 消费契约 + 帧节奏 DRAFT 值入库 + E2E 截图用户裁决**。它是视觉核心 issue：后续 #575 状态机、#577 判定、#579 反馈、#580 处决、#578 复活全部在本 issue 的「看得见的角色」上呈现。

**设计哲学：零资产 + 只消费状态 + 数值集中 + 视觉/逻辑解耦。**
1. **零美术资产（AC5）**：骨架几何全部 `.gd` 代码构建；**动画资源运行时动态生成**（Animation 对象代码构建、关键帧时间戳从 constants 派生），零 `.tres` 动画资源文件——比「预置 clip + 时间戳校验」更彻底地满足 AC5，且 AC3 的「数值来自 constants」由构造方式直接保证（PRD 实验 1 推荐路径）。
2. **动画只消费状态（issue 输入驱动契约）**：不读 Input、不订阅 #573 信号；唯一入口 `consume_state(state: String)`。canonical 11 态集合权威归 #575，本层只做**镜像映射表**（单点同步 + 单测枚举保护）。
3. **帧节奏集中（AC3）**：`FRAME_ANIM_*` 全系列进 constants.gd `# DRAFT` 分区，继承 #572 注释规范（候补值 + 影响什么 + 情感断言）；与既有 `FRAME_ATTACK_RECOVERY=14` 的冲突值（10 vs 14）**双值共存互引注释，禁止实现期二选一偷定**，定稿归 #584。
4. **视觉/逻辑解耦（AC2）**：刀光 = SwordArc（Polygon2D additive）独立纯视觉节点，节点树无任何碰撞类型；判定归 #577，反馈归 #579。

```
                    ★ Issue #574 本设计（shandong-wolf 角色视觉层）
┌──────────────────────────────────────────────────────────────────────────────┐
│ 新建（8 文件，全部 shandong-wolf/ 下）                                          │
│  gdscripts/stick_figure.gd              StickFigure（Node2D）—— 程序化骨架     │
│  gdscripts/stick_figure_controller.gd   StickFigureController（Node2D 根）      │
│                                         —— consume_state 契约 + 11态→clip 映射  │
│  gdscripts/stick_figure_anim_states.gd  动画状态对象集（派生 StateMachineBase）  │
│  gdscripts/sword_arc.gd                 SwordArc（Polygon2D）—— additive 刀光   │
│  gdscripts/e2e_stick_figure_capture.gd  E2E 截图像具驱动（digit key → consume）  │
│  scenes/player_stick_figure.tscn        角色场景（根 + 脚本，骨架代码构建）      │
│  scenes/e2e_stick_figure_capture.tscn   截图专用场景（深色底 + 角色 + 驱动）     │
│  tests/test_stick_figure_animation.gd   动画单测（§8 用例描述）                  │
├──────────────────────────────────────────────────────────────────────────────┤
│ 修改（3 文件）                                                                │
│  gdscripts/constants.gd                  追加 FRAME_ANIM_* # DRAFT 分区（§2.1） │
│  e2e_shots.json                          占位 → main_scene + stick_figure 组    │
│  tests/run_tests.gd                      追加 _run(test_stick_figure_animation) │
├──────────────────────────────────────────────────────────────────────────────┤
│ 消费方（0 改动，后续 issue 挂接）                                               │
│  #575 战斗状态机 → consume_state；#579 复用 SwordArc；#577 消费 guard/parry 帧   │
│  #584 调参面板消费 FRAME_ANIM_*；#578/#580 消费 revive/dead/execute 帧          │
└───────────────────────────────────┬──────────────────────────────────────────┘
                                    ▼
      consume_state("attack") → AnimationPlayer.play("anim_attack")
        ├─ 前摇 8 帧（FRAME_ANIM_ATTACK_WINDUP）    ← 时间戳 = 8/60s（constants 派生）
        ├─ 暴发 4 帧（FRAME_ANIM_ATTACK_BURST）     ← SwordArc 随 SwordPivot 旋转触发
        └─ 收招 10 帧（FRAME_ANIM_ATTACK_RECOVERY） ← 过渡 ≤2 帧到下一状态 clip
```

**与 PRD 方案裁决的一致性：** PRD §4.1/§4.2/§4.3/§4.4 各推荐方案 A，本设计逐项确认采纳，无分歧。PRD §7 三个 Spike（Line2D 摆姿可控性 / 刀光参数化绘制 / 过渡 ≤2 帧策略）为 implement Phase 0 执行项，其**预期结论已直接内化为本设计决策**：① 动态生成 Animation 资源（零 .tres）优先；② 刀光 120° 张角 + 4 帧衰减为初值入 constants；③ 过渡策略 = 直接 play + 「clip 首帧姿态 = 上一状态尾帧姿态」设计约定（复杂度最低且可测），跳变大的转移用 2 帧手动姿态插值兜底。若 Spike 实测推翻任一内化结论，implement 需在 PR 中说明偏离及理由。

### 1.1 既有实现状态（Prior Implementation Status）

| 文件 | 当前状态（2026-08-19 侦查，plan agent 已逐条核实） | 与 #574 的差距 |
|------|--------------------------------------------------|---------------|
| `shandong-wolf/gdscripts/constants.gd` | ✅ `WolfConstants`（RefCounted + class_name），5 个 # DRAFT 分区（弹反窗口/架势回复/两条命/刀伤/帧节奏）；帧节奏区已有 `FRAME_ATTACK_WINDUP=8`、`FRAME_ATTACK_RECOVERY=14`、`FRAME_RHYTHM_BASE=60`；注释规范「候补值+影响什么+情感断言」已确立 | ❌ 无动画专属分区（FRAME_ANIM_*）、无骨骼几何参数、无颜色常量、无刀光参数 |
| `shandong-wolf/gdscripts/state_machine.gd` | ✅ `StateMachineBase`（RefCounted + class_name）：状态对象 enter/exit/update 三接口 + transition_to（同态守卫 + 防重入锁） | ✅ 可直接派生动画状态对象（§2.4），零改动 |
| `shandong-wolf/gdscripts/game.gd` | ✅ `Game` autoload（project.godot `[autoload]` 已注册），preload constants | 无改动；后续 #575 经 Game 引用角色控制器 |
| `shandong-wolf/scenes/Main.tscn` | ✅ 纯声明式标题场景（#562/#563/#570）：Main→CanvasLayer→CenterContainer/VBox→Title/Subtitle/Version/PostMergeProbe | **不修改**；火柴人 = 独立场景（PRD §1.1 明文「不嵌入标题场景」） |
| `shandong-wolf/scenes/` | ⚠️ 仅 Main.tscn + .gitkeep | ❌ 需新增 `player_stick_figure.tscn` + `e2e_stick_figure_capture.tscn` |
| `shandong-wolf/tests/run_tests.gd` | ✅ 已挂载 test_state_machine + test_constants（#572），`_run()` 模式可用 | ❌ 追加挂载 test_stick_figure_animation |
| `shandong-wolf/tests/check_compile.gd` / `smoke_test.gd` | ✅ 自动扫描 gdscripts/+tests/；冒烟绿 | 零改动（新脚本自动纳入编译检查） |
| `shandong-wolf/e2e_shots.json` | ⚠️ 占位（states 空、groups 空） | ❌ 填充 main_scene + stick_figure shot group（AC4） |
| `shandong-wolf/assets/` | ✅ 空 | 保持空（AC5 红线：零美术资源） |
| `mini-pong/` | ✅ 视觉体系先例（程序化视觉已实弹验证） | 仅作模式参考，**不复制**（跨游戏红线） |

### 1.2 PRD 断言 vs 实际代码交叉对照

| PRD 断言 | 实际代码（核实结果） | 设计裁决 |
|---------|---------------------|---------|
| constants.gd 帧节奏区已有 FRAME_ATTACK_WINDUP=8 / FRAME_ATTACK_RECOVERY=14 | ✅ 属实（§帧节奏 3 常量） | FRAME_ANIM_ATTACK_WINDUP=8 与既有对齐互引；FRAME_ANIM_ATTACK_RECOVERY=10 与既有 14 **双值共存互引**，#584 裁决 |
| constants.gd 无动画专属分区 | ✅ 属实（5 分区无动画） | 追加式新增 FRAME_ANIM_* 分区（§2.1），不动既有行 |
| StateMachineBase 三接口 + 防重入可直接派生 | ✅ 属实（enter/exit/update + _transition_locked） | stick_figure_anim_states.gd 直接派生（§2.4） |
| Main.tscn 为纯声明式标题场景，勿动 | ✅ 属实（零脚本零 ext_resource） | 保持零改动；火柴人独立场景（§2.6） |
| e2e_shots.json 为占位（states/groups 空） | ✅ 属实 | 填充（§2.7），resolve_plan.py 顶层字段白名单**含 `main_scene`**（已核实 scripts/e2e/resolve_plan.py L23），可覆盖截图主场景 |
| scenes/ 无角色场景 | ✅ 属实（仅 Main.tscn） | 新建 player_stick_figure.tscn |
| 测试入口可挂载新套件 | ✅ 属实（_run() 模式 + call_deferred） | 追加 _run 行（§3.1） |
| PRD §4.1 方案 A 的「正式原画接入点 = 换 Sprite2D 层保留骨架」 | 无现存 Sprite2D 层（骨架期） | 骨架根节点预留 `sprite_slot` 命名子节点位（§2.2），后续原画接入零重构 |

---

## 2. 新组件 — 详细设计

### 2.1 `shandong-wolf/gdscripts/constants.gd`（修改：追加 FRAME_ANIM_* # DRAFT 分区）

- **位置：** 文件末尾追加新分区（**不修改**既有 5 分区任何行；追加式新增 = 零冲突面，worktree 并行安全）
- **分区头注释沿用 #572 规范：** 「── 动画帧节奏（# DRAFT 候补值，待 #584 定稿）──」+ 每常量三行注释（候补值 / 该值影响什么 / 情感断言）
- **新增常量清单（全部 # DRAFT 标记）：**

```gdscript
# ── 动画帧节奏与骨骼几何（# DRAFT 候补值，待 #584 定稿）──
#   候补值: 攻击前摇 8 / 暴发 4 / 收招 10；过渡上限 2 帧；步态循环 4 帧；处决 5 帧
#   该值影响什么: 《小小系列》式「起势慢→爆发快→收招滞」的力度感全部由这三段帧数承载；
#                过渡上限是 AC1 硬约束（2 帧 @60fps = 0.033s）
#   情感断言: 干净力量感——前摇可读蓄力、暴发瞬间爆发、收招滞刀有余韵（禁止页游光效堆砌）
const FRAME_ANIM_ATTACK_WINDUP: int = 8    # # DRAFT（与 FRAME_ATTACK_WINDUP=8 对齐互引）
const FRAME_ANIM_ATTACK_BURST: int = 4     # # DRAFT（新值；挥刀暴发，刀光在此段触发）
const FRAME_ANIM_ATTACK_RECOVERY: int = 10 # # DRAFT（⚠️ 与 FRAME_ATTACK_RECOVERY=14 冲突，双值共存互引，禁止实现期二选一，定稿归 #584）
const FRAME_ANIM_TRANSITION_MAX: int = 2   # # DRAFT（AC1 过渡上限；2 帧 @60fps = 0.033s）
const FRAME_ANIM_MOVE_STEP: int = 4        # # DRAFT（步态摆臂循环 4 帧，配方 §6.5）
const FRAME_ANIM_EXECUTE_TOTAL: int = 5    # # DRAFT（处决上撩→斩落 5 帧，配方 §7）
const FRAME_ANIM_SWORD_ARC_FADE: int = 4   # # DRAFT（刀光存在/衰减帧数，PRD 实验 2 预期值）

# ── 骨骼几何与配色（# DRAFT 候补值，待 #584 定稿）──
#   候补值: 墨色剪影 #2b2b2b（issue body 指定）/ 冷白刀身 #c0c8d0（雪夜反差）；肢体比例头:躯干:臂:腿 ≈ 1:2.5:1.9:2.2
#   该值影响什么: 剪影可读性（角色总高 ≈150px @720p 画布）与雪夜水墨背景的反差（AC4 用户裁决项）
#   情感断言: 单色剪影的干净力量感——无贴图细节，靠摆姿与比例说话
const BODY_COLOR: Color = Color("#2b2b2b")      # # DRAFT（issue body 墨色）
const SWORD_COLOR: Color = Color("#c0c8d0")     # # DRAFT（冷白刀身，雪夜反差点）
const BODY_HEAD_RADIUS: float = 16.0            # # DRAFT
const BODY_TORSO_LENGTH: float = 44.0           # # DRAFT
const BODY_ARM_LENGTH: float = 34.0             # # DRAFT
const BODY_LEG_LENGTH: float = 40.0             # # DRAFT
const BODY_LIMB_WIDTH: float = 6.0              # # DRAFT（Line2D width）
const SWORD_LENGTH: float = 88.0                # # DRAFT（长刀，视觉焦点）
const SWORD_WIDTH: float = 5.0                  # # DRAFT

# ── 刀光弧线参数（# DRAFT 候补值，待 #584 定稿）──
#   候补值: 张角 120°（PRD 实验 2 预期）/ 半径 70 / 4 环透明度衰减 / 起始 alpha 0.6
#   该值影响什么: 挥砍轨迹的可读性——张角过大刺眼（反页游光效）、过小看不清轨迹
#   情感断言: 一刀见痕的爽快——轨迹醒目但不喧宾夺主（角色退后、刀是视觉焦点，配方 §6.5）
const SWORD_ARC_SWEEP_DEG: float = 120.0        # # DRAFT（实验 2 预期最佳值）
const SWORD_ARC_RADIUS: float = 70.0            # # DRAFT
const SWORD_ARC_RINGS: int = 4                  # # DRAFT（径向透明度衰减环数）
const SWORD_ARC_ALPHA_START: float = 0.6        # # DRAFT
```

- **集成说明：** check_compile 自动纳入；#584 调参面板按「候补值 + 影响 + 情感断言」三行注释直接消费；test_constants.gd 既有断言（≥5 个 # DRAFT 标记）自动覆盖新分区（数量只增不减，不破坏）。

### 2.2 `shandong-wolf/gdscripts/stick_figure.gd`（新建：程序化骨架构建）

- **文件:** `shandong-wolf/gdscripts/stick_figure.gd`
- **类:** `class_name StickFigure`，`extends Node2D`
- **职责:** 在 `_ready()` 用代码构建火柴人骨架节点树（零 tscn 资源依赖、零美术资产）；`@export` 几何参数默认值从 `WolfConstants` 读取（`const C = preload("res://gdscripts/constants.gd")`）；参数校验 + 默认值兜底（非法几何参数 → push_warning + 回退默认值，不崩溃）。
- **节点树（pivot 摆姿结构）：** 每个肢体 = 一个 Node2D pivot（关键帧旋转/位移的锚点）+ 子 Line2D（线段本体）；头 = Polygon2D 圆（剪影填充而非描边——「剪影」语义要求实心）：

```
StickFigure (Node2D)                    [script: stick_figure.gd]
├── TorsoPivot (Node2D) ──── Line2D (躯干, BODY_TORSO_LENGTH × BODY_LIMB_WIDTH, BODY_COLOR)
│   ├── HeadPivot (Node2D) ── Polygon2D (头圆, BODY_HEAD_RADIUS, BODY_COLOR)
│   ├── ArmLPivot (Node2D) ── Line2D (左臂, BODY_ARM_LENGTH, BODY_COLOR)
│   ├── ArmRPivot (Node2D) ── Line2D (右臂, BODY_ARM_LENGTH, BODY_COLOR)
│   └── SwordPivot (Node2D) ─ Line2D (刀, SWORD_LENGTH × SWORD_WIDTH, SWORD_COLOR)
│                             └── SwordArc (Polygon2D, additive 刀光 — §2.5)
├── LegLPivot (Node2D) ── Line2D (左腿, BODY_LEG_LENGTH, BODY_COLOR)
└── LegRPivot (Node2D) ── Line2D (右腿, BODY_LEG_LENGTH, BODY_COLOR)
```

- **关键方法（伪代码）：**
```gdscript
func _ready() -> void:
    _build_skeleton()                    # 按 §2.2 节点树构建全部 pivot + Line2D/Polygon2D
    _validate_geometry()                 # 非法参数 → push_warning + 默认值兜底（§5-8）

func _make_limb(name: String, length: float, width: float, color: Color) -> Node2D:
    # 创建 pivot Node2D（position=0），add_child(Line2D 自 pivot 原点向 -Y 延伸 length)
    # Line2D points = [Vector2.ZERO, Vector2(0, -length)]，default_color=color，width=width

func _make_head() -> Polygon2D:
    # 圆多边形（BODY_HEAD_RADIUS，16 段），color=BODY_COLOR，挂在 HeadPivot

func get_pivot(part: String) -> Node2D:
    # 按名取 pivot（"torso"/"head"/"arm_l"/"arm_r"/"sword"/"leg_l"/"leg_r"）
    # 供 AnimationPlayer 关键帧寻址 + 单测断言

func set_sprite_slot(sprite: Node2D) -> void:
    # 正式原画接入点（PRD §4.1）：替换视觉层为 Sprite2D，保留骨架结构
    # 本期不实现，仅预留命名子节点位 sprite_slot（§1.2 交叉对照末行）
```
- **集成说明：** check_compile 自动覆盖；单测直接实例化断言节点树完整性（§8 Scenario F）。

### 2.3 `shandong-wolf/gdscripts/stick_figure_controller.gd`（新建：consume_state 契约 + 动画调度）

- **文件:** `shandong-wolf/gdscripts/stick_figure_controller.gd`
- **类:** `class_name StickFigureController`，`extends Node2D`（player_stick_figure.tscn 根节点）
- **职责:** 场景根；持有 StickFigure + AnimationPlayer；暴露 `consume_state(state: String)` 契约；维护 11 态→clip 镜像映射表（canonical 权威 = #575，注释来源）；过渡 ≤2 帧策略；同态重入处理；未知状态降级。

**契约签名：**
```gdscript
func consume_state(state: String) -> void
# 唯一动画入口（issue 输入驱动契约：不读 Input、不订阅 #573 信号）
# 语义:
#   1. state 先过映射表（canonical 11 态 + 别名），映射失败 → 降级 idle + push_warning（§5-1）
#   2. 目标 clip == 当前 clip → 同态重入：重置到该 clip 前摇首帧（连招语义，§5-3）
#   3. AnimationPlayer.play(clip, custom_blend) —— 过渡策略见下
#   4. 播放前 stop 旧 clip（防叠播，§5-8）
```

**状态名→clip 映射表（11 态全映射，与 #575 canonical 逐条对齐；run/parry 为 issue body 声明的别名）：**

| canonical 状态（#575 权威） | clip 名 | 备注 |
|:---:|:---:|------|
| idle | `anim_idle` | 待机呼吸（微幅上下浮动，配方 §6.5 前摇可读基准） |
| move | `anim_move` | 步态摆臂 4 帧循环（FRAME_ANIM_MOVE_STEP）；**run 别名 → move**（issue body 明文） |
| attack | `anim_attack` | 三段：前摇 8 / 暴发 4 / 收招 10（时间戳从 constants 派生） |
| heavy_attack | `anim_heavy_attack` | 重砍（蓄力感更强的前摇；帧数 DRAFT 候补，与 attack 同分区） |
| guard | `anim_guard` | 横刀胸前；**parry 别名 → guard**（格挡/弹反共用姿态，issue body 明文） |
| parry_success | `anim_parry_success` | 弹反成功硬直帧（#577 结果事件的视觉回报） |
| stagger | `anim_stagger` | 受击后仰（与 idle 尾帧跳变大 → 触发插值 fallback，§2.3 过渡策略） |
| stance_break | `anim_stance_break` | 架势崩解失衡 |
| execute | `anim_execute` | 处决上撩→斩落（FRAME_ANIM_EXECUTE_TOTAL=5 帧；流程驱动归 #580） |
| revive | `anim_revive` | 起身关键帧（驱动归 #578） |
| dead | `anim_dead` | 倒地帧（驱动归 #578） |

**过渡 ≤2 帧策略（AC1，PRD 实验 3 推荐 ①+约定）：**
- **主策略：直接 `play()` + 「clip 首帧姿态 = 上一状态尾帧姿态」设计约定**。即 idle→move→attack→guard→stagger 链路上，每个 clip 的首帧与前一 clip 尾帧姿态对齐（关键帧规划时保证），引擎同帧切换即满足 ≤2 帧，无需 blend。
- **兜底策略（跳变大的转移，如 stagger→idle、stance_break→idle）：** 2 帧手动姿态插值（tween 当前各 pivot rotation → 目标 clip 首帧姿态，时长 = FRAME_ANIM_TRANSITION_MAX/60s），插值完成后 play 目标 clip。
- **可测性：** 单测记录 t0（consume_state 调用）与 t1（目标 clip 实际生效帧）断言 t1-t0 ≤ 2/60s（§8 Scenario C）。

**动画资源动态生成（零 .tres，AC3/AC5）：**
```gdscript
func _build_clip(name: String, keyframes: Dictionary) -> Animation:
    # 运行时构建 Animation 对象（零 .tres 文件）：
    #   length = 总帧数 / FRAME_RHYTHM_BASE
    #   每个 pivot 的 rotation/position 关键帧时间戳 = 帧数 / 60（帧数全部来自 FRAME_ANIM_* 常量）
    #   track 路径 = 骨架节点 NodePath（如 "StickFigure/TorsoPivot:rotation"）
    # 注册进 AnimationPlayer 默认库（animation_player.get_animation_library("").add_animation(name, anim)）
```
- **动画 clip 清单：** `anim_idle` / `anim_move` / `anim_attack` / `anim_heavy_attack` / `anim_guard` / `anim_parry_success` / `anim_stagger` / `anim_stance_break` / `anim_execute` / `anim_revive` / `anim_dead`（11 个，与映射表一一对应）。
- **attack clip 三段时间戳（示例，全部 constants 派生）：** 前摇段 [0, 8/60]（蓄力下沉）→ 暴发段 [8/60, 12/60]（挥砍 + SwordArc 触发点）→ 收招段 [12/60, 22/60]（滞刀回位）。帧间距不对称 = 「起势慢→爆发快→收招滞」力度感（配方 §6.5）。
- **集成说明：** #575 战斗状态机落地后把状态转移喂给 consume_state 即可，本层零改动；单测可脱离 #575 用测试桩直接调用（§8 Scenario A/B/C）。

### 2.4 `shandong-wolf/gdscripts/stick_figure_anim_states.gd`（新建：动画状态对象集）

- **文件:** `shandong-wolf/gdscripts/stick_figure_anim_states.gd`
- **类:** 基于 `StateMachineBase` 派生的一组动画状态对象（RefCounted，每态一个内部类）：`AnimStateIdle` / `AnimStateMove` / `AnimStateAttack` / `AnimStateHeavyAttack` / `AnimStateGuard` / `AnimStateParrySuccess` / `AnimStateStagger` / `AnimStateStanceBreak` / `AnimStateExecute` / `AnimStateRevive` / `AnimStateDead`。
- **职责边界（重要）：** 本文件**不是战斗状态机**（战斗状态机权威归 #575）。本层状态对象 = 「动画层最小调度」：每态 `enter()` 调 `controller.play_clip(clip)`（或经 consume_state 内部路径）；`update(delta)` 转发给 AnimationPlayer 推进（Attack 态可推进 windup→burst→recovery 的阶段标记，供 SwordArc 在暴发段触发）。
- **三接口实现（伪代码）：**
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
- **集成说明：** 本期由 controller 内最小调度驱动（单测直接驱动）；#575 落地后其战斗状态对象可复用本文件姿态命名/阶段标记（注释互引），或整体替换——本文件接口保持薄契约，替换成本低。

### 2.5 `shandong-wolf/gdscripts/sword_arc.gd`（新建：additive 刀光弧线）

- **文件:** `shandong-wolf/gdscripts/sword_arc.gd`
- **类:** `class_name SwordArc`，`extends Polygon2D`（挂在 SwordPivot 下，随刀旋转）
- **职责（AC2）：** attack 暴发段触发，绘制挥砍弧线轨迹；**纯视觉层**——节点树无 Area2D/CollisionShape2D，碰撞判定归 #577（零交集）。
- **材质：** `CanvasItemMaterial`，`blend_mode = BLEND_MODE_ADD`（additive 合成，代码设置，零 .tres）。
- **几何（程序化生成）：** 扇形弧 + 径向透明度衰减环：
```gdscript
func _build_polygon() -> void:
    # 以 SwordPivot 为圆心：半径 SWORD_ARC_RADIUS，张角 SWORD_ARC_SWEEP_DEG(120°)
    # 分 SWORD_ARC_RINGS(4) 环，环间 alpha 从 SWORD_ARC_ALPHA_START(0.6) 线性衰减到 0
    # polygon = PackedVector2Array（弧扇顶点）；vertex_colors = PackedColorArray（逐顶点 alpha）
    # 视觉锚点: 弧线中轴对齐挥砍方向（随 SwordPivot.rotation 旋转）
func trigger_burst() -> void:
    # 暴发段首帧调用: visible=true + _fade_frames = FRAME_ANIM_SWORD_ARC_FADE(4)
func _process(delta: float) -> void:
    # _fade_frames 递减 → modulate.a 线性衰减 → 归零隐藏（短衰减 ≈4 帧，反页游光效）
```
- **集成说明：** #579 打击反馈直接复用本节点（火花叠加 / hit-stop 锚点），零重构；参数全部 constants DRAFT，供 #584 裁决（张角/半径/alpha 观感）。

### 2.6 `shandong-wolf/scenes/player_stick_figure.tscn`（新建：角色场景装配）

- **文件:** `shandong-wolf/scenes/player_stick_figure.tscn`
- **结构（最小化声明，骨架仍由代码构建——AC5 友好）：**
```
PlayerStickFigure (Node2D)   [script: stick_figure_controller.gd]
├── StickFigure (Node2D)     [script: stick_figure.gd]   ← _ready() 程序化构建骨架
├── AnimationPlayer (AnimationPlayer)                    ← 动画库运行时动态注册
└── (SwordArc 由 stick_figure.gd 在 SwordPivot 下创建)
```
- **集成说明：** 独立场景，**不嵌入 Main.tscn**（PRD §1.1 红线）；后续 #575（战斗实体）/ #579 / #580 / #578 实例化消费；E2E capture 场景实例化消费。

### 2.7 `shandong-wolf/scenes/e2e_stick_figure_capture.tscn` + `e2e_stick_figure_capture.gd`（新建：E2E 截图像具）

- **文件:** `shandong-wolf/scenes/e2e_stick_figure_capture.tscn`（+ `gdscripts/e2e_stick_figure_capture.gd`）
- **目的（AC4）：** 提供「可被 e2e_capture.gd 驱动」的截图场景——角色摆进画面、每个动画状态可注入触发、状态可轮询。**不修改 Main.tscn**（PRD §8.3 下一步 4 的「独立测试场景」选项）。
- **结构：**
```
CaptureRig (Node2D)          [script: e2e_stick_figure_capture.gd]
├── Backdrop (ColorRect)     ← 中性深冷底色（反差裁决用；雪夜氛围特效归 #582，本 issue 不实现）
├── Player (PlayerStickFigure 实例)   ← player_stick_figure.tscn
└── (驱动: _unhandled_input + current_state 属性)
```
- **驱动契约（与 e2e_capture.gd 模板兼容——模板只读属性 + press 注入，零游戏代码改动）：**
  - `current_state: int` 属性（`IDLE=0, MOVE=1, ATTACK_WINDUP=2, ATTACK_BURST=3, ATTACK_RECOVERY=4, GUARD=5, PARRY_SUCCESS=6, STAGGER=7, STANCE_BREAK=8, EXECUTE=9, REVIVE=10, DEAD=11`）——shot plan 的 `state_node`/`state_property` 轮询目标
  - digit 键 1-9/0 映射 → `consume_state(...)`（press 注入驱动）；attack 三段用 3 个独立 shot state（windup/burst/recovery 各截图，PRD AC4 要求 attack 3 帧）
- **e2e_shots.json 集成（§3.1）：** 顶层加 `main_scene: "res://scenes/e2e_stick_figure_capture.tscn"`（resolve_plan.py 白名单已含 main_scene，已核实）+ `stick_figure` shot group（match: `gdscripts/stick_figure.*\.gd`、`gdscripts/sword_arc\.gd`、`scenes/player_stick_figure.*\.tscn`），shots 覆盖 11 态（attack 3 段独立 shot）。
- **回退路径（implement 期 Spike 验证项）：** 若 e2e_capture.gd 的 press/require 机制对 digit 键驱动不兼容 → capture 脚本自循环状态序列（每态停留 N 帧）+ 定时自截图（不依赖 press），并在 PR 说明。截图落盘 `docs/e2e-evidence/` 提交用户裁决。

### 2.8 测试文件（新建，仅用例描述——plan 阶段不写可运行测试代码）

- **`shandong-wolf/tests/test_stick_figure_animation.gd`:** extends Object，`run()` + `_assert` 计数模式（test_state_machine.gd 同款结构）。用例描述见 §8 Scenario A–L。
- **`shandong-wolf/tests/run_tests.gd`（修改）:** `_run_tests()` 追加 `_run("res://tests/test_stick_figure_animation.gd", "StickFigureAnimation")`。

---

## 3. 既有组件修改

### 3.1 修改文件

| 文件 | 变更 | 性质 | 伪代码/说明 |
|------|------|------|------------|
| `shandong-wolf/gdscripts/constants.gd` | 文件末尾**追加** `FRAME_ANIM_*` + 骨骼几何 + 刀光参数 3 个 # DRAFT 分区（§2.1 全清单） | 追加式新增（不动既有 5 分区任何行） | 见 §2.1 代码块；每个常量带三行注释（候补值/影响/情感断言） |
| `shandong-wolf/e2e_shots.json` | 占位 → 顶层 `main_scene` + `state_node/state_property/states` + `stick_figure` shot group | 占位填充 | 顶层加 `"main_scene": "res://scenes/e2e_stick_figure_capture.tscn"`；`"state_node": "/root/CaptureRig"`、`"state_property": "current_state"`、states 枚举（§2.7 12 值）；group `stick_figure` match `["gdscripts/stick_figure.*\\.gd", "gdscripts/sword_arc\\.gd", "scenes/player_stick_figure.*\\.tscn"]`，shots 覆盖 idle/move/attack×3/guard/parry_success/stagger/stance_break/execute/revive/dead（settle_frames 各自 ≥ 对应动画时长×60 帧） |
| `shandong-wolf/tests/run_tests.gd` | `_run_tests()` 追加挂载动画套件 | 追加一行 | `_run("res://tests/test_stick_figure_animation.gd", "StickFigureAnimation")` |

### 3.2 新文件清单

| 文件 | 说明 | 归属 |
|------|------|------|
| `shandong-wolf/gdscripts/stick_figure.gd` | 程序化骨架构建（§2.2） | #574 |
| `shandong-wolf/gdscripts/stick_figure_controller.gd` | consume_state 契约 + 11 态→clip 映射 + 过渡策略 + 动画资源动态生成（§2.3） | #574 |
| `shandong-wolf/gdscripts/stick_figure_anim_states.gd` | 动画状态对象集（派生 StateMachineBase，§2.4） | #574 |
| `shandong-wolf/gdscripts/sword_arc.gd` | additive 刀光弧线（§2.5） | #574 |
| `shandong-wolf/gdscripts/e2e_stick_figure_capture.gd` | E2E 截图像具驱动（§2.7） | #574 |
| `shandong-wolf/scenes/player_stick_figure.tscn` | 角色场景装配（§2.6） | #574 |
| `shandong-wolf/scenes/e2e_stick_figure_capture.tscn` | 截图专用场景（§2.7） | #574 |
| `shandong-wolf/tests/test_stick_figure_animation.gd` | 动画单测（§8 用例描述） | #574 |

### 3.3 不修改（显式声明，防越界）

| 文件 | 原因 |
|------|------|
| `shandong-wolf/scenes/Main.tscn` | 标题场景零改动（PRD §1.1「不嵌入标题场景」+ §8 红线）；E2E 用独立 capture 场景（§2.7） |
| `shandong-wolf/gdscripts/state_machine.gd` / `game.gd` | 被派生/被挂接，零改动（§1.1） |
| `shandong-wolf/project.godot` | 无新增 autoload/场景注册需求（角色场景按需实例化，非主场景） |
| `shandong-wolf/tests/check_compile.gd` / `smoke_test.gd` | 自动覆盖新脚本；零改动 |
| `shandong-wolf/assets/` | 保持空（AC5 红线） |
| `mini-pong/` 全部 | 跨游戏红线（PRD §1.4/§8） |
| `game-env/manifest.yaml` / `.github/workflows/` / `scripts/` | 管线配置非本 issue 职责（已参数化自动跟随） |
| `docs/GAME_DESIGN/` | GDD 补记是 post-merge agent 职责 |

---

## 4. 数据流

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
    ├─ [0, 8/60]   前摇: TorsoPivot 下沉蓄力（FRAME_ANIM_ATTACK_WINDUP=8）
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
校验: 单测读 clip 关键帧时间戳 vs constants 值，容差 ±1 帧（§8 Scenario E/I）
```

### Flow 3: 未知状态 / 非法转移（降级路径）
```
consume_state("unknown_state")
    → 映射表无命中 → push_warning("StickFigureController: unknown state 'unknown_state', fallback idle")
    → 播放 anim_idle（不崩溃、不卡死动画）
    → 映射表注释标明 #575 为权威源；run/parry 别名显式处理（§5-1/§5-2）
```

### Flow 4: E2E 截图流（AC4 用户裁决）
```
CI/本地: run-e2e-review.sh --with-visual
  → resolve_plan.py 读 e2e_shots.json（main_scene=capture 场景）→ 解析 stick_figure group
  → e2e_capture.gd 启动 capture 场景 → 轮询 /root/CaptureRig.current_state
  → 每 shot: press digit 键 → CaptureRig 调 consume_state → 等 state 到位 + settle_frames → 截图
  → 11 态 PNG 落盘 docs/e2e-evidence/574-* → 提交用户裁决「小小系列干净力量感 + 雪夜水墨和谐」
  → 不通过 → taste-draft 领域: 调摆姿/帧节奏候补值重提交（PRD §5.3-3），机械接口不受影响
```

### Flow 5: 骨架构建（正常/异常）
```
正常: stick_figure.gd._ready() → _build_skeleton() 逐 pivot 构建 → 骨架就绪 → controller 注册
异常: 几何参数非法（负长度/零宽度）→ _validate_geometry() push_warning + 回退默认值 → 继续构建
      Animation 动态生成失败 → clip 缺失 → consume_state 映射到缺失 clip → push_warning + 降级 idle（§5-9）
```

---

## 5. 边界情况与错误处理

| Edge Case | Mitigation |
|-----------|------------|
| 1. 未知状态名（#575 canonical 漂移或调用方传错） | 映射表无命中 → 降级 idle + push_warning，不崩溃（§8 Scenario H）；映射表注释引用 #575 为权威源 |
| 2. 状态名别名/大小写漂移（run/move、parry/guard 混用） | 映射表只认 canonical 11 态；run→move、parry→guard 显式别名映射并注释（issue body 已声明） |
| 3. 快速连续切换（连招节奏：attack 未播完再 consume_state("attack")） | 同态重入：重置到该 clip 前摇首帧而非从头播完整 clip（输入缓冲语义归 #573，本层只保证视觉衔接）；过渡仍 ≤2 帧（§8 Scenario G） |
| 4. transition 冲突（#575 战斗状态机未就绪） | 本层最小调度遇非法转移 → 保持当前动画 + push_warning；#575 落地后由其合法性检查兜底（PRD §5.2-4） |
| 5. constants 冲突值（FRAME_ANIM_ATTACK_RECOVERY=10 vs FRAME_ATTACK_RECOVERY=14） | 双值共存互引注释（§2.1），**禁止实现期二选一偷定**；#584 裁决后统一（§8 Scenario E 断言双值并存） |
| 6. headless/CI 环境 | 动画单测不依赖真实渲染（仅节点树 + AnimationPlayer 时间戳断言）；E2E 截图依赖渲染（--with-visual 显式开启，CI 截图能力 #559 已验证） |
| 7. 窗口比例变化 | 1280x720 固定窗口（#572 机械常量，project.godot resizable=false）；骨架锚定原点居中，不依赖屏幕尺寸 |
| 8. 旧 clip 未清理叠播 | AnimationPlayer.play 前 stop 旧 clip（§2.3 语义 ④；§8 Scenario I 断言无叠播） |
| 9. 动态生成 Animation 失败（clip 缺失） | consume_state 映射到缺失 clip → push_warning + 降级 idle；单测断言 11 clip 全部注册成功（§8 Scenario I） |
| 10. 骨架几何参数非法 | _validate_geometry() push_warning + 默认值兜底，不崩溃（§2.2；§8 Scenario L） |
| 11. clip 首帧姿态与上一状态尾帧不衔接（跳变大的转移） | 过渡兜底：2 帧手动姿态插值（tween pivot rotation → 目标首帧），时长 = FRAME_ANIM_TRANSITION_MAX/60s（§2.3；§8 Scenario C） |
| 12. E2E 截图用户裁决不通过 | taste-draft 领域：摆姿/帧节奏候补值可调重提交；机械实现（骨架/接口/单测）不受影响可先行（PRD §5.3-3） |

---

## 6. 集成点

> **Status 约定:** ⬜ = 待 implement 接线；✅ = implement 已连接。implement agent 必须更新本表。

| Integration | Our Component | Target Issue | How | Status |
|-------------|:---:|:---:|-----|:---:|
| 状态消费 | `StickFigureController.consume_state(state)` | #575 | 战斗状态机 transition → consume_state（canonical 11 态，本层镜像映射） | ⬜ pending |
| 输入契约对齐 | consume_state 不读输入 | #573 | #573 只发意图事件给 #575，不直连本层（issue body 输入驱动契约） | ⬜ pending |
| 判定视觉回报 | `anim_guard` / `anim_parry_success` | #577 | #577 弹反结果事件 → parry_success 硬直帧播放 | ⬜ pending |
| 刀光复用 | `SwordArc` | #579 | 火花/hit-stop 叠加在刀光节点上（additive 合成），零重构 | ⬜ pending |
| 处决帧 | `anim_execute` | #580 | #580 处决流程驱动 execute clip（上撩→斩落 5 帧） | ⬜ pending |
| 复活/倒地帧 | `anim_revive` / `anim_dead` | #578 | #578 两条命流程驱动起身/倒地关键帧 | ⬜ pending |
| 数值定稿 | `FRAME_ANIM_*` # DRAFT 分区 | #584 | 候补值 → 用户定稿（替换值 + 去 # DRAFT 标记，走 #584 PR）；冲突值 10vs14 由 #584 裁决 | ⬜ pending |
| 原画接入点 | `StickFigure.set_sprite_slot()` | 后续原画 | 换 Sprite2D 层，保留骨架结构（PRD §4.1） | ⬜ pending |
| 单测挂载 | run_tests.gd | 本 issue | `_run("res://tests/test_stick_figure_animation.gd", ...)` | ✅ done |
| E2E 截图 | capture 场景 + e2e_shots.json | 本 issue | --with-visual 跑 shot plan → docs/e2e-evidence/ → 用户裁决（场景/plan 已落地，截图由 CI 执行） | ✅ done |
| 动画状态对象 | stick_figure_anim_states.gd | 本 issue | 最小调度驱动（#575 落地前可独立运行） | ✅ done |

---

## 7. 实现阶段

| Phase | Priority | Components | Estimate |
|:-----:|:--------:|-----------|:--------:|
| Phase 0 | P0 | PRD §7 三个 Spike 验证（Line2D 摆姿可控性 / 刀光参数化 / 过渡 ≤2 帧策略）——预期结论已内化（§1），实测推翻需 PR 说明 | 0.5d |
| Phase 1 | P0 | `constants.gd` 追加 FRAME_ANIM_* + 骨骼几何 + 刀光 3 个 # DRAFT 分区（§2.1） | 0.25d |
| Phase 2 | P0 | `stick_figure.gd` 程序化骨架（§2.2）+ 参数校验 | 0.5d |
| Phase 3 | P0 | 动画资源动态生成 + `stick_figure_anim_states.gd`（§2.3/§2.4，11 clip） | 1d |
| Phase 4 | P0 | `stick_figure_controller.gd` consume_state + 映射表 + 过渡策略 + 同态重入（§2.3） | 0.5d |
| Phase 5 | P0 | `sword_arc.gd` additive 刀光（§2.5） | 0.25d |
| Phase 6 | P0 | `player_stick_figure.tscn` + `test_stick_figure_animation.gd` + run_tests 挂载（§2.6/§2.8/§3.1） | 0.5d |
| Phase 7 | P0 | E2E capture 场景 + e2e_shots.json 填充 + 截图落盘 docs/e2e-evidence/ + 提交用户裁决（§2.7） | 0.5d |

> 依赖序：Phase 1 无依赖先行；Phase 2 依赖 1（几何参数）；Phase 3 依赖 1（帧节奏）+ 2（pivot 寻址）；Phase 4 依赖 2+3；Phase 5 依赖 2（SwordPivot）；Phase 6 依赖 2-5；Phase 7 依赖 6。总估 **3.5d**（PRD estimate 3d 偏乐观，含 Spike 0.5d + E2E 截图用户裁决等待；机械实现部分与用户裁决解耦可并行推进）。

---

## 8. 测试用例描述

> 仅描述测试场景，不写可运行测试代码（plan 阶段红线；实现由 implement agent 完成）。全部用例进 `shandong-wolf/tests/test_stick_figure_animation.gd`（extends Object + run() + _assert 模式，同 test_state_machine.gd 结构）。

### Scenario A: consume_state 映射与别名（test_stick_figure_animation.gd）
- **A1（canonical 映射）**: `consume_state("attack")` → AnimationPlayer 当前动画 == `anim_attack`；`consume_state("guard")` → `anim_guard`；抽查 5 个代表性状态（idle/move/heavy_attack/stagger/dead）。
- **A2（别名映射）**: `consume_state("run")` → 播放 `anim_move`（run 归 move，issue body 明文）；`consume_state("parry")` → 播放 `anim_guard`（格挡/弹反共用姿态）。

### Scenario B: 11 态映射完整性（test_stick_figure_animation.gd）
- **B1（全态枚举）**: 断言映射表对 canonical 11 态（idle/move/attack/heavy_attack/guard/parry_success/stagger/stance_break/execute/revive/dead）**全部**有映射且 clip 已注册（防 #575 状态名漂移导致漏映射；PRD §5.3-4）。

### Scenario C: 过渡时长 ≤2 帧（AC1，test_stick_figure_animation.gd）
- **C1（idle→move→attack→guard→stagger 全链）**: 依次 consume_state，记录每对切换 t0（consume 调用）与 t1（目标 clip 首帧生效），断言 t1-t0 ≤ `FRAME_ANIM_TRANSITION_MAX/60`（0.033s）。主策略（直接 play + 首帧姿态约定）下应全部通过。
- **C2（跳变大转移插值兜底）**: stagger→idle 触发插值路径 → 断言插值时长 == 2/60s 且插值完成后目标 clip 生效（若 implement 采用纯直接 play 且首帧衔接达标，本用例降级为可选回归）。

### Scenario D: 刀光 additive 无碰撞（AC2，test_stick_figure_animation.gd）
- **D1（节点树无碰撞类型）**: 遍历 SwordArc 及其全部子节点，断言无 Area2D/CollisionShape2D/任何碰撞层节点（判定归 #577，视觉/逻辑解耦）。
- **D2（additive 材质）**: 断言 SwordArc 材质为 CanvasItemMaterial 且 blend_mode == BLEND_MODE_ADD。

### Scenario E: constants 派生（AC3，test_stick_figure_animation.gd）
- **E1（关键帧时间戳 vs constants）**: 读 `anim_attack` 关键帧时间戳，断言前摇段末帧 == `FRAME_ANIM_ATTACK_WINDUP/60`、暴发段末帧 == `(WINDUP+BURST)/60`、收招段末帧 == `(WINDUP+BURST+RECOVERY)/60`（容差 ±1 帧 = 1/60s）。
- **E2（冲突值双存）**: 断言 `FRAME_ANIM_ATTACK_RECOVERY == 10` 且 `FRAME_ATTACK_RECOVERY == 14` 同时存在（互引注释，禁止实现期二选一偷定）。
- **E3（# DRAFT 标记）**: constants.gd 源码含 ≥5 处 `# DRAFT`（既有断言自动覆盖新分区）；新常量注释含「候补值/影响/情感断言」三要素（抽查 3 个）。

### Scenario F: 骨架构建（test_stick_figure_animation.gd）
- **F1（节点树完整）**: 实例化 StickFigure 后，7 个 pivot（torso/head/arm_l/arm_r/sword/leg_l/leg_r）全部存在；头为 Polygon2D、四肢/躯干/刀为 Line2D。
- **F2（几何参数来自 constants）**: 各 Line2D length/width、头半径、刀长 == 对应 `BODY_*`/`SWORD_*` 常量值（容差 0.01）。
- **F3（剪影配色）**: 骨架线条/头部颜色 == `BODY_COLOR`、刀身 == `SWORD_COLOR`。

### Scenario G: 同态重入（连招语义，test_stick_figure_animation.gd）
- **G1（attack 重入重置前摇）**: attack 播到暴发段时再次 `consume_state("attack")` → 断言动画重置回前摇首帧（时间 == 0），非从头完整重播的既有行为差异点。

### Scenario H: 未知状态降级（test_stick_figure_animation.gd）
- **H1（未知状态）**: `consume_state("unknown_state")` → 播放 `anim_idle` + push_warning 已发，无崩溃、无卡死动画（映射表注释引用 #575 权威源）。

### Scenario I: 动画资源动态生成（零 .tres，test_stick_figure_animation.gd）
- **I1（11 clip 全注册）**: AnimationPlayer 动画库含 11 个 `anim_*` clip（与映射表一一对应），缺失任一 FAIL。
- **I2（零资源文件）**: 工程扫描无新增 `.tres`/`.res` 动画资源（AC5）；断言 gdscripts 外新增文件仅 .tscn（player_stick_figure / e2e_stick_figure_capture）。
- **I3（无叠播）**: 连续 consume_state 两个不同状态 → 断言前一 clip 已 stop（无两个 clip 同时播放）。

### Scenario J: 三入口回归（CI / 本地）
- **J1（check_compile）**: `godot --path shandong-wolf/ --headless --script tests/check_compile.gd` 退出 0，输出覆盖新增 5 gdscripts 脚本。
- **J2（smoke）**: `... --script tests/smoke_test.gd` 退出 0（autoload + 主场景兼容）。
- **J3（run_tests）**: `... --script tests/run_tests.gd` 退出 0，输出「TESTS: N passed, 0 failed」且 N ≥ 既有用例数 + 本套件用例数（A–I 场景全过）；pass==0 → 退出非 0（防挂载遗漏静默绿）。
- **J4（主场景冒烟）**: `godot --path shandong-wolf/ --headless --quit` 退出 0（Main.tscn 未被破坏——本 issue 零改动，回归验证）。

### Scenario K: E2E 截图用户裁决（AC4，CI --with-visual）
- **K1（11 态 shot 覆盖）**: e2e_shots.json `stick_figure` group 的 shots 覆盖 idle/move/attack×3 段/guard/parry_success/stagger/stance_break/execute/revive/dead，每 shot 截图成功落盘 `docs/e2e-evidence/574-*.png`（attack 3 段 = AC4 明文的 前摇/暴发/收招 3 帧）。
- **K2（用户裁决）**: 截图提交用户判定「火柴人摆姿/剪影是否具有《小小系列》的干净力量感，且与雪夜水墨背景和谐」；不通过 → taste-draft 领域调整候补值重提交（机械接口先行不受影响）。

### Scenario L: 非法参数兜底（test_stick_figure_animation.gd）
- **L1（负长度/零宽度）**: 构造非法几何参数（如 BODY_TORSO_LENGTH=-1、BODY_LIMB_WIDTH=0）→ push_warning + 回退默认值，骨架仍构建成功不崩溃。

---

## 9. 验收条件映射（源自 Issue #574 body）

| # | 验收条件 | 设计落点 | 验证方式 |
|---|---------|---------|---------|
| AC1 | 玩家火柴人可在 idle→run→attack→parry→stagger 间切换，动画过渡 h 时长 ≤2 帧 | §2.3 过渡策略（直接 play + 首帧姿态约定 + 插值兜底）；§2.2 骨架 pivot 摆姿 | C1/C2（t1-t0 ≤ 2/60s 帧级断言） |
| AC2 | attack 动画包含刀光弧线轨迹（additive），不影响碰撞判定（判定在 SW-006=#577） | §2.5 SwordArc（Polygon2D additive 独立节点，无碰撞类型） | D1/D2（节点树无碰撞 + blend_mode 断言） |
| AC3 | 所有帧节奏数值来自 constants.gd # DRAFT 且注释含候补值 | §2.1 FRAME_ANIM_* 分区（时间戳由 constants 派生构造）；冲突值 10vs14 双存互引 | E1/E2/E3（时间戳 vs constants ±1 帧 + 双值并存 + # DRAFT 三要素注释） |
| AC4 | E2E 截图提交用户裁决：火柴人摆姿/剪影是否具有『小小系列』的干净力量感，且与雪夜水墨背景和谐 | §2.7 capture 场景 + e2e_shots.json（11 态 shot，attack 3 段）+ 深冷底色供反差裁决 | K1/K2（shots 全覆盖 + 用户裁决，落盘 docs/e2e-evidence/） |
| AC5 | 无外部美术文件，仅 .gd 程序生成 | §2.2 骨架代码构建 + §2.3 动画资源动态生成（零 .tres）+ assets/ 保持空 | I2（零资源文件扫描）+ implement PR diff 核查（无 .png/.jpg/.tres） |

---

## 10. 明确不修改（与 PRD §8 红线对齐）

- ❌ `mini-pong/` 任何文件（跨游戏红线；视觉先例仅作模式参考）
- ❌ `shandong-wolf/scenes/Main.tscn`（标题场景，含 PostMergeProbeLabel；E2E 用独立 capture 场景）
- ❌ `shandong-wolf/project.godot`（无新增 autoload/主场景变更）
- ❌ `shandong-wolf/gdscripts/state_machine.gd` / `game.gd`（被派生/被挂接，零改动）
- ❌ `game-env/manifest.yaml`、`.github/workflows/`、`scripts/`（管线参数化已自动跟随）
- ❌ `docs/GAME_DESIGN/`（post-merge agent 职责）
- ❌ 任何美术资产 / 插件 addon / 像素帧 / `.tres` 动画资源（AC5；动画资源运行时动态生成）
- ❌ constants.gd 既有 5 个 # DRAFT 分区任何行（只追加新分区）
- ❌ 帧节奏二选一偷定（FRAME_ANIM_ATTACK_RECOVERY=10 与 FRAME_ATTACK_RECOVERY=14 双存互引，定稿归 #584）

---

## 附：开源调研结论（PRD §6.2 已调研，implement PR 须附说明）

PRD §6.2 已用 GitHub API 检索火柴人/Skeleton2D/2D 骨架动画开源方案（Tor-Kai/Godot-2d-Bridge、folt-a/godot-skeleton2d-helper、Stick-Figure-Battle、stick-castle-defense、stick-fighter 等 6 项 + Asset Library），结论：**无满足「程序化零资产 + Line2D 关键帧」的成熟开源组件可复用**（候选均为完整游戏或依赖美术资产管线的编辑器工具）。按 issue「开源优先，找不到再自行实现」指示，采用 PRD §4.1 方案 A 自行实现；implement PR 中附本调研表说明（不重复调研，引用 PRD §6.2）。
