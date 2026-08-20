# Design: [Rendering] 打击反馈系统（火花 / hit-stop / 屏震 / 慢动作 / 白闪）

> **Parent Issue:** #579
> **Agent:** game-plan-agent
> **Date:** 2026-08-20
> **Approach:** PRD §4.6 推荐组合**逐项确认采纳，无分歧** —— 控制器 A（ReactionController 单入口事件驱动）/ 火花 A（GPUParticles2D one_shot burst，代码创建零 .tres）/ 时间缩放 A（TimeScaleStack 栈式 + 墙钟兜底）/ 屏震 A（Camera2D offset trauma² 衰减）/ 白闪 A（实体 modulate 闪 + CanvasLayer 全屏淡闪双通道，S 级刀光复用 SwordArc）；方案 B/C 显式否决，理由同 PRD §4（AC2 同帧无法保证 / 职责耦合违规 / 不引 addon 红线）
> **Reference PRD:** `docs/PRD/579-combat-feedback-system.md`（research PR #641 已合并 2026-08-20）
> **上游方案:** `docs/DESIGN/577-parry-clash-stance-break.md`（#577 五结果事件契约 + bind 参数个数纪律）；`docs/DESIGN/575-combat-entity-state-machine.md`（6 信号契约）；`docs/DESIGN/574-stick-figure-silhouette-animation.md`（SwordArc + E2E CaptureRig 模式）；`docs/DESIGN/572-scaffold-main-entry.md`（constants.gd 分区格式 + run_tests 挂载 + test_constants 守卫模式）
> **所有权:** `content_ownership: mechanical`（反馈机制实现=机械工程——信号订阅/组合触发/时间栈/碰撞点推导；强度参数= taste-draft——时长/幅度/粒子数/颜色全部 FEEDBACK_ 前缀 `# DRAFT` 候补值，定稿归 #584/用户，**实现期禁止把 DRAFT 值「顺手定稿」**）
> **深度:** deep（分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=8 标注 depth: deep → PRD §1–8 全必填；GitHub 无 depth 标签）—— 10 文件（7 新建 + 3 修改）/ 5 反馈子系统 + E2E rig = 8+ 独立子任务 → **产出 DESIGN + TASKS 文档**
> **并行上下文:** worktree 隔离（/tmp/wt-plan-579，branch `plan/579-combat-feedback-system`）；constants.gd 反馈分区追加在**文件尾部**（#582 氛围分区已在前部，同文件不同区域，main 侧无代码冲突预期）；E2E rig 场景名 `e2e_feedback_capture.tscn` 与 #574 `e2e_stick_figure_capture.tscn` 并列，不触碰既有 rig
> **⚠️ Issue 状态说明（R5 已知问题）:** issue #579 当前为 CLOSED——research PR #641 body 末尾误写 `Closes #579` 触发 GitHub 自动关闭（R5 已知问题，非本阶段关闭）；**本 PR body 只写 `Parent #579`，禁止 Closes/Fixes/Resolves 关键词**；issue 重开归 R5 专项，不影响本设计推进
> **红线:** 只动 `shandong-wolf/` 下 10 文件（见 §3.1）；**绝不触碰** `combat_entity.gd` / `combat_states.gd` / `combat_state_table.gd`（#575 契约红线）、`sword_arc.gd`（只调用 trigger_burst）、`scenes/Main.tscn`（标题场景红线）、`mini-pong/`、`game-env/manifest.yaml`、`.github/workflows/`、`docs/GAME_DESIGN/`、`shandong-wolf/tests/check_compile.gd`、`shandong-wolf/tests/smoke_test.gd`；零第三方 addon（timeflow/trauma-gd 只借鉴模型不自研）；`Engine.time_scale` 只经 TimeScaleStack 写入；全屏闪白仅限 A- 级 100ms 低 alpha；不做判定/处决逻辑（#577/#580 职责）、不发声（#593 职责，只留 feedback_played hook）

---

## 1. 架构总览

**问题本质是「战斗事件的信号源全齐，但消费信号渲染分级反馈的执行层零存在」。** #575 已交付 CombatEntity（6 信号 + 11 态状态机）、#577 已 merged（#626）交付 CombatJudge 五结果事件（parry_success / block_held / hit_landed / clash / stance_broken）、#574 已交付 SwordArc 刀光——但玩家弹反/格挡/被击时画面上**毫无回应**。本 issue 交付 = **ReactionController 统一消费信号 + 分级事件矩阵（S/A/A-/B/C 六级）+ 五个瞬态效果组件（火花/hit-stop/屏震/白闪/刀光）+ 参数集中 constants.gd 反馈分区（# DRAFT）+ E2E 同帧截图 rig**。只狼手感的 50% 来自『打铁』节奏：每个事件有精准、克制的反馈组合，80-100ms 内四要素同步完成（AC2）——本设计的结构性保证是**单一入口 `trigger_feedback(event, data)` 在同一帧内组合触发全部效果组件**。

**设计哲学：事件驱动消费 + 组合触发 + 参数单一事实源。** 反馈层**只消费信号，不做判定**（#577 判定已 merged，五结果事件是现成触发入口）；所有效果组件是轻量 Node，由 ReactionController 编排（不是 autoload 单例——避免 AC2 同帧无法保证）；所有数值进 constants.gd `FEEDBACK_` 前缀分区（`# DRAFT` 候补值，格式照 #572，定稿归 #584/用户）；与场景解耦（`@export camera_path` + 战斗场景/E2E rig 各自实例化）。

```
★ Issue #579 本设计（shandong-wolf 打击反馈五子系统 + E2E rig）
┌─────────────────────────────────────────────────────────────────────────┐
│ 新建（7 文件，全部 shandong-wolf/ 下）                                      │
│  gdscripts/reaction_controller.gd   ReactionController（Node，组合触发核心）│
│    ├─ FEEDBACK_MATRIX 分级矩阵（event→等级→参数包，查 constants FEEDBACK_*）│
│    ├─ trigger_feedback(event, data) 公开 API（#577/#580/测试唯一注入点）     │
│    ├─ bind_judge(judge) 五结果事件直连 + subscribe_entity(entity) 信号订阅  │
│    ├─ _derive_impact_point() 刀与刀交点推导（SwordPivot 中点，AC3）          │
│    └─ signal feedback_played(event, level, data)（#593 音效 hook）          │
│  gdscripts/feedback_spark.gd        FeedbackSpark（GPUParticles2D，one_shot│
│                                     burst，位置/法线/等级参数化，#ffd9a0）  │
│  gdscripts/time_scale_stack.gd      TimeScaleStack（RefCounted，push/pop +  │
│                                     墙钟兜底，Engine.time_scale 唯一写入口）│
│  gdscripts/screen_shake.gd          ScreenShake（Node，Camera2D offset     │
│                                     trauma² 衰减 + 方向沿攻击向量）         │
│  gdscripts/flash_effect.gd          FlashEffect（Node，实体 modulate 白闪 + │
│                                     CanvasLayer 全屏淡闪双通道）            │
│  gdscripts/e2e_feedback_capture.gd   E2E rig 驱动（inject_feedback + 冻结   │
│  scenes/e2e_feedback_capture.tscn    效果帧模式 + current_state 轮询）      │
│  tests/test_reaction_controller.gd   五组用例（矩阵/时间栈/火花/屏震/白闪）  │
└─────────────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────────────┐
│ 修改（3 文件）                                                            │
│  gdscripts/constants.gd   追加「反馈分区」FEEDBACK_ 前缀 # DRAFT 常量（文件尾）│
│  tests/run_tests.gd       注册 test_reaction_controller.gd                 │
│  e2e_shots.json           追加反馈 shot group（parry_success/stance_break/ │
│                           execute 三档）                                  │
└─────────────────────────────────────────────────────────────────────────┘
事件源（只读消费，零修改）: CombatEntity 信号（#575） + CombatJudge 五结果事件（#577/#626）
                        + execute 事件（#580 未来/测试注入）
```

### 1.1 既有实现状态（Prior Implementation Status）

| 系统 | 状态 | 本设计的消费方式 |
|------|:----:|-----------------|
| `combat_entity.gd`（#575/#618） | ✅ 已交付 | 只订阅 6 信号；`state_changed(from, to)` **仅 2 参、不带实体**——连接时 bind 捕获实体（§2.1 设计决策 D2） |
| `combat_judge.gd`（#577/#626） | ✅ 已交付 | 5 信号**带实体引用、无位置参数**——碰撞点由 `_derive_impact_point` 推导（§2.1 设计决策 D3） |
| `sword_arc.gd`（#574/#612） | ✅ 已交付 | S 级处决直接调用 `trigger_burst()`，不改实现 |
| `combat_attack_window.gd`（#577） | ✅ 已交付 | `direction: int (-1/1)` = 攻击方向快照，火花法线推导的方向数据源 |
| `stick_figure_controller.gd`（#574） | ✅ 已交付 | `TorsoPivot/SwordPivot` 全局位置 = 刀交点推导锚点（已核实节点路径存在） |
| `constants.gd`（#572/#584/#582） | ✅ 已交付 | **无反馈分区**——本 issue 在文件尾部追加 FEEDBACK_ 分区（§3.2） |
| `tests/run_tests.gd` | ✅ 已交付 | 已挂 12 套件；追加 `test_reaction_controller.gd`（§3.3） |
| `e2e_stick_figure_capture.gd/.tscn`（#574） | ✅ 已交付 | CaptureRig 模式（current_state 轮询 + digit 键 + auto_cycle）；本 issue 仿照新建独立 rig，不触碰既有 rig |
| `e2e_shots.json` | ✅ 已交付 | dict 结构（states/autoplay/theme_color…）；追加反馈 shot group（§3.4） |
| Camera2D 实例 | ❌ 不存在 | E2E rig 自带一个；战斗场景 #583 挂载（`@export camera_path` 已解耦） |

## 2. 新组件 — 详细设计

### 2.1 reaction_controller.gd — 组合触发核心（PRD §4.1 方案 A）

- **File:** `shandong-wolf/gdscripts/reaction_controller.gd`
- **Node structure:**

```
ReactionController (Node2D, class_name ReactionController)
├── FeedbackSpark (GPUParticles2D, 代码创建, z_index < 角色层)
├── ScreenShake (Node, @export camera_path)
├── FlashEffect (Node)
└── [TimeScaleStack 为 RefCounted，由本节点 _process 驱动 tick]
```

- **Signals:** `signal feedback_played(event: String, level: String, data: Dictionary)` —— #593 音效系统消费（本 issue 只发信号不发声）。
- **State Properties:**
  - `const C = preload("res://gdscripts/constants.gd")`
  - `@export var camera_path: NodePath` —— 屏震目标相机（战斗场景 #583 / E2E rig 注入；null 时 ScreenShake no-op）
  - `_spark: FeedbackSpark`、`_shake: ScreenShake`、`_flash: FlashEffect`、`_time_stack: TimeScaleStack`
  - `_judge_bound: bool = false`、`_entities: Array`（已订阅实体，防重复订阅）
- **Key Methods:**

```gdscript
## 事件注入唯一入口（#577 判定 / #580 处决 / 测试 / E2E rig 共用）
func trigger_feedback(event: String, data: Dictionary = {}) -> void
#   event ∈ {"parry_success","block_held","hit_landed","stance_broken","clash",
#            "execute","player_hit","revive","death"}
#   data 键约定（§8.3 PRD 契约）:
#     position: Vector2      # 刀与刀交点（AC3；缺省 → _derive_impact_point 推导）
#     normal: Vector2        # 刀面法线（AC3；缺省 → 攻击方向法线推导）
#     target_entity: Node    # 受击实体（敌人白闪用）
#     attacker_entity: Node  # 攻击方（方向兜底用）
#     source: String         # "combat_entity" | "judgment" | "test"
#   流程: 查 FEEDBACK_MATRIX[event] → 无映射 push_warning + no-op（边界 6）
#        → 组合触发: spark.burst_at() / time_stack.push() / shake.shake() /
#                    flash.flash_entity() 或 flash_screen() / SwordArc 复用（S 级）
#        → emit feedback_played(event, level, data)   # 音效 hook

func bind_judge(judge: Node) -> void
#   judge.parry_success.connect(_on_parry_success)        # (defender, attacker, stance_damage)
#   judge.block_held.connect(_on_block_held)              # (defender, attacker, stance_cost)
#   judge.hit_landed.connect(_on_hit_landed)              # (defender, attacker, hp, stance)
#   judge.clash.connect(_on_clash)                        # (a, b, stance_cost)
#   judge.stance_broken.connect(_on_judge_stance_broken)  # (entity)
#   每个 handler → trigger_feedback(event, {target_entity, attacker_entity, source:"judgment"})
#   连接前 has_signal 防护（与 combat_judge.bind_input 同模式）

func subscribe_entity(entity: CombatEntity) -> void
#   防重复订阅（_entities 查重）
#   entity.state_changed.connect(func(from, to): _on_state_changed(from, to, entity))
#   entity.stance_broken.connect(func(e): _on_stance_broken(e))
#   entity.died.connect(func(e, final): _on_died(e, final))
#   entity.revived.connect(func(e): _on_revived(e))

func _process(_delta: float) -> void
#   _time_stack.tick(Time.get_ticks_msec())   # 墙钟兜底轮询（AC4 机械保证）

func _derive_impact_point(attacker: Node, defender: Node, direction: int) -> Dictionary
#   返回 {position: Vector2, normal: Vector2}
#   a_pivot = attacker.get_node_or_null("TorsoPivot/SwordPivot")
#   d_pivot = defender.get_node_or_null("TorsoPivot/SwordPivot")
#   两者都有效 → position = (a_pivot.global_position + d_pivot.global_position) / 2
#   normal = 攻击方向 direction 的法线: Vector2(0, -direction)（刀面朝向，# DRAFT）
#   推导失败（无 pivot）→ position = attacker.global_position,
#     normal = Vector2(direction, 0)（facing 兜底）+ push_warning（边界 8）
```

- **设计决策（代码库核查产出的三个 gap 决议，implement agent 必须照此落地）：**

| PRD 断言 | 实际代码库 | 设计决议 |
|---------|-----------|---------|
| `state_changed(from, to)` 可区分发射实体 | `combat_entity.gd` 信号仅 2 参 `(from: String, to: String)`，**无实体参数** | **D2：`subscribe_entity` 用闭包捕获实体**（`connect(func(from,to): _on_state_changed(from,to,entity))`），与 `combat_judge._on_entity_state_changed` 的 bind 纪律一致（#577 先例：参数个数不匹配会报错，闭包是安全解法） |
| #577 结果事件携带碰撞位置 | 五结果事件均**无位置参数**（只带实体引用） | **D3：`_derive_impact_point(attacker, defender, direction)` 从 `SwordPivot` 全局位置推导刀交点**（节点路径已核实存在于 stick_figure_controller），AC3「非角色中心」的结构保证；#577 事件无 position 是 PRD 已预期的契约差异（PRD §8.4-1），无需改 #577 |
| `state_changed → stagger` 需区分玩家/敌人 | 信号无身份信息 | **D4：`subscribe_entity(entity)` 传入的实体即身份**——由组装层（#585）用玩家实体调 `subscribe_entity(player)`、敌人实体调 `subscribe_entity(enemy)`；`_on_state_changed` 内 `if entity == _player_ref` 判定 player_hit（C 级）vs 敌人 stagger（C 级同参） |

- **矩阵表（FEEDBACK_MATRIX，数据全部指向 constants FEEDBACK_*，# DRAFT）：**

| 事件 | 等级 | 火花 | hit-stop | 屏震 | 慢动作 | 白闪/其他 | 事件信号源 |
|------|:----:|------|----------|------|--------|-----------|-----------|
| execute | S | SwordArc.trigger_burst() + 血粒子 | 150ms | 4px | 0.05x 500ms | 无（构图留白） | execute 事件（#580/测试注入） |
| parry_success | A | 16-20 粒 | 90ms | 3px | 0.3x 200ms 渐变恢复 | 敌人白闪 | #577 parry_success / state_changed→parry_success |
| stance_broken | A- | 无火花 | 100ms | 3px | 0.5x 300ms | 全屏淡白闪 + 敌人持续白闪 | #577 stance_broken / 实体信号 |
| block_held | B | 6 粒最小 | 30ms | 1px | 无 | 无 | #577 block_held / state_changed→guard |
| hit_landed | C | 8 粒小火花 | 50ms | 2px 沿攻击方向 | 无 | 敌人硬直（#574 stagger 动画） | #577 hit_landed / state_changed→stagger |
| player_hit | C | 无火花 | 60ms | 4px | 无 | 玩家后仰（#574 stagger 动画） | state_changed→stagger（D4 判定玩家） |
| clash | B+ | 12 粒 | 60ms | 2px | 无 | 双方小硬直 | #577 clash |
| revive | C- | 无 | 无 | 1px | 无 | 复活演出反馈（参数 # DRAFT） | revived 信号 |
| death | C | 无火花 | 60ms | 4px | 无 | 玩家受击反馈（不触发慢动作） | died 信号（final 时） |

> 矩阵单调性（AC5）：粒子数/时长/幅度 S≥A≥A-≥B≥C，慢动作仅 S/A/A- 级启用；`clash`/`revive`/`death` 为 PRD 契约事件名的补充映射（等级取相邻档，参数 # DRAFT）。

### 2.2 feedback_spark.gd — 火花粒子（PRD §4.2 方案 A）

- **File:** `shandong-wolf/gdscripts/feedback_spark.gd`
- **Node structure:** `FeedbackSpark (GPUParticles2D, class_name FeedbackSpark)` —— 直接 extends GPUParticles2D，材质代码创建（零 .tres，与项目零美术资产红线一致）。
- **State Properties:**
  - `one_shot = true`（burst 语义）；`emitting = false`（默认不喷）
  - `z_index`：读 `C.FEEDBACK_SPARK_Z_INDEX`（默认 -1，**低于角色层**——issue 粒子不盖角色红线）
  - 材质 `ParticleProcessMaterial`：`color_ramp` 苍白金渐变（`C.FEEDBACK_SPARK_COLOR` #ffd9a0 → 略暗尾色，禁橙色）；`direction`/`initial_velocity_min`/`max`/`lifetime` 来自等级参数包
- **Key Methods:**

```gdscript
func burst_at(world_pos: Vector2, normal: Vector2, level: String) -> void
#   global_position = world_pos                    # AC3: 碰撞点直传，无中心猜测
#   material.direction = normal                    # AC3: 方向沿刀面法线
#   amount = C.FEEDBACK_SPARK_COUNT[level]         # {S:14, A:18, B:6, C:8}（A 16-20 取 18）
#   velocity/lifetime 读 C.FEEDBACK_SPARK_VELOCITY[level] / LIFETIME[level]（# DRAFT）
#   restart(); emitting = true                     # 标准 burst 序列（PRD §5.3-2）
#   重复触发: one_shot restart 覆盖旧 burst（边界 1，不叠加粒子池）
```

### 2.3 time_scale_stack.gd — 时间缩放栈（PRD §4.3 方案 A，AC4 核心）

- **File:** `shandong-wolf/gdscripts/time_scale_stack.gd`
- **Node structure:** `class_name TimeScaleStack extends RefCounted`（纯逻辑，无场景节点；由 ReactionController._process 驱动 tick）。
- **State Properties:**
  - `_layers: Array[Dictionary]` —— 每层 `{scale: float, deadline_ms: int}`
  - `const MAX_STACK_DEPTH: int = 3`（读 `C.FEEDBACK_TIME_MAX_STACK`，超限丢弃新 push 保旧恢复——边界 1）
- **Key Methods:**

```gdscript
func push(scale: float, duration_ms: int) -> void
#   if _layers.size() >= MAX_STACK_DEPTH: push_warning + 丢弃（保旧恢复）
#   _layers.append({scale: scale, deadline_ms: Time.get_ticks_msec() + duration_ms})
#   _apply()

func pop() -> void
#   if _layers.is_empty(): return
#   _layers.pop_back(); _apply()

func tick(now_ms: int) -> void
#   墙钟兜底（AC4 机械保证，PRD §5.3-1）: 从栈底起移除 deadline 已过的层（到期强制 pop）
#   → 变化则 _apply()

func _apply() -> void
#   设计决策 D1: Engine.time_scale = 栈内最小 scale（PRD §4.3-A「取最小」语义落定）
#   —— 最慢层主导: hit-stop 0.05 期间慢动作 0.3 push 不会稀释顿帧感；
#      hit-stop pop 后 0.3 慢动作继续，逐层恢复 1.0
#   hit-stop 用 0.05 而非 0（0 冻结引擎处理，墙钟兜底失效风险——PRD §8.4-3）
```

> **D1 说明（对 PRD §7 实验 1 措辞的落定）:** PRD 实验 1 预期「嵌套中间值 = 栈顶缩放」，与 §4.3-A「取最小」机制定义存在措辞张力。本设计落定**取最小**（hit-stop 0.05 → slowmo 0.3 → 中间值 **0.05**，hit-stop pop 后 0.3，逐层恢复 1.0）——这是『叮！』顿帧不被慢动作稀释的手感要求；实验 1 断言按此语义写（§8 Scenario B）。

### 2.4 screen_shake.gd — 屏震（PRD §4.4 方案 A）

- **File:** `shandong-wolf/gdscripts/screen_shake.gd`
- **Node structure:** `ScreenShake (Node, class_name ScreenShake)`。
- **State Properties:**
  - `@export var camera_path: NodePath` —— 场景自持 Camera2D（#583 战斗场景 / E2E rig 注入；null/失效 → no-op + push_warning 一次，边界 2）
  - `_trauma: float = 0.0`（0-1）；`_direction: Vector2`（沿攻击向量）；`_max_offset_px: float`
  - 衰减曲线：`_decay_per_sec`（# DRAFT，指数衰减 trauma -= trauma * decay * delta）
- **Key Methods:**

```gdscript
func shake(max_offset_px: float, direction: Vector2) -> void
#   _trauma = min(1.0, _trauma + 0.6)   # 叠加取 max 语义（边界 1: 不叠加爆震）
#   _max_offset_px = max(_max_offset_px, max_offset_px)
#   _direction = direction if direction != Vector2.ZERO else 上次方向

func _process(delta: float) -> void
#   cam = camera_path 解析（null → return，no-op）
#   if _trauma <= 0.01: cam.offset = Vector2.ZERO; return
#   noise = Vector2(randf_range(-1,1), randf_range(-1,1)).normalized() * _direction.sign() 混合
#   cam.offset = noise * (_trauma * _trauma) * _max_offset_px   # trauma² 指数衰减（trauma-gd 同款）
#   _trauma -= _trauma * _decay_per_sec * delta                 # 单调衰减，终值 0（实验 2）
```

### 2.5 flash_effect.gd — 白闪双通道（PRD §4.5 方案 A）

- **File:** `shandong-wolf/gdscripts/flash_effect.gd`
- **Node structure:** `FlashEffect (Node, class_name FlashEffect)`，含子节点 `CanvasLayer (layer=0) → ColorRect`（全屏淡闪通道，代码创建）。
- **Key Methods:**

```gdscript
func flash_entity(entity: Node, alpha: float, duration_ms: int) -> void
#   实体白闪（AC2 敌人白闪）: 
#   if not is_instance_valid(entity): return                 # 边界 7（实体已 free 跳过）
#   tween: entity.modulate → Color(5,5,5) 保持 duration_ms → 渐回 Color.WHITE
#   高倍乘算 + 显示钳制 = 深色火柴人（#2b2b2b）也冲白；系数 # DRAFT（taste 域）
#   注意: 不动实体动画层（#574 职责），只动 modulate 外层

func flash_screen(alpha: float, duration_ms: int) -> void
#   全屏淡白闪（仅 A- 架势崩解使用——AC5/AC6 页游感红线）:
#   CanvasLayer(layer=0) → ColorRect 全屏 Color(1,1,1,alpha) 淡入 → duration_ms 后淡出
#   alpha/duration 读 C.FEEDBACK_FLASH["A_"]（{alpha:0.25, ms:100}，# DRAFT）
#   层序: 低于 UI(1)/氛围(2-10)——只盖世界画面，不遮 HUD（§1 层级约定）
```

### 2.6 e2e_feedback_capture.gd/.tscn — E2E 同帧截图 rig（PRD §7 实验 4）

- **Files:** `shandong-wolf/gdscripts/e2e_feedback_capture.gd` + `shandong-wolf/scenes/e2e_feedback_capture.tscn`
- **Node structure:**

```
E2EFeedbackCapture (Node2D, class_name E2EFeedbackCapture)
├── Camera2D                     # 屏震目标（本 rig 自带，#583 落地前验证通道）
├── ReactionController           # @export camera_path → Camera2D
├── PlayerStickFigure (player_stick_figure.tscn)   # 攻击方
├── EnemyStickFigure (player_stick_figure.tscn)    # 防守方（复用同一 tscn，零新美术）
└── FeedbackSpark / ScreenShake / FlashEffect      # 效果组件（或由 ReactionController 代码创建）
```

- **驱动契约（与 #574 CaptureRig 兼容）:**
  - `current_state: int` 属性（IDLE=0 … EXECUTE=…）——shot plan 的 state_node/state_property 轮询目标
  - `inject_feedback(event: String)` 公开方法——被 shot plan autoplay.tweaks 或 digit 键调用，转 `_controller.trigger_feedback(event, {position, normal, target_entity, attacker_entity, source: "test"})`
  - digit 键映射（`_unhandled_input`，沿用 #574 模式）: 4→parry_success、6→stance_broken、7→execute、2→hit_landed
  - **冻结效果帧模式（AC2 决定性兜底，PRD §5.3-3/§7 实验 4）:** `freeze_effects: bool`——开启后时间栈墙钟不推进（hit-stop 保持 0.05x 停留），火花/白闪停留在画面中供截图；shot plan 在效果窗口内开启

## 3. 既有组件修改

### 3.1 文件清单总表

| 类别 | 文件 | 变更 |
|------|------|------|
| 新增 | `shandong-wolf/gdscripts/reaction_controller.gd` | §2.1 |
| 新增 | `shandong-wolf/gdscripts/feedback_spark.gd` | §2.2 |
| 新增 | `shandong-wolf/gdscripts/time_scale_stack.gd` | §2.3 |
| 新增 | `shandong-wolf/gdscripts/screen_shake.gd` | §2.4 |
| 新增 | `shandong-wolf/gdscripts/flash_effect.gd` | §2.5 |
| 新增 | `shandong-wolf/gdscripts/e2e_feedback_capture.gd` | §2.6 |
| 新增 | `shandong-wolf/scenes/e2e_feedback_capture.tscn` | §2.6 |
| 新增 | `shandong-wolf/tests/test_reaction_controller.gd` | §8 |
| 修改 | `shandong-wolf/gdscripts/constants.gd` | 追加反馈分区（§3.2） |
| 修改 | `shandong-wolf/tests/run_tests.gd` | 注册新套件（§3.3） |
| 修改 | `shandong-wolf/e2e_shots.json` | 追加 shot group（§3.4） |
| 只读 | `combat_entity.gd` / `combat_judge.gd` / `sword_arc.gd` / `stick_figure_controller.gd` / `combat_attack_window.gd` | 零修改 |

### 3.2 constants.gd — 追加「反馈分区」（文件尾部，格式照 #572 既有分区）

```gdscript
# ── 反馈分区（# DRAFT 候补值，定稿 = #584 用户裁决；#579 消费方，禁止实现期定稿）──
# FEEDBACK_SPARK_COUNT:  {S:14, A:18, B:6, C:8}          # 粒子数（issue 矩阵 A 16-20 取 18）
const FEEDBACK_SPARK_COUNT: Dictionary = {"S": 14, "A": 18, "B": 6, "C": 8}
# FEEDBACK_SPARK_COLOR:  Color("#ffd9a0")  # 苍白金（issue 禁橙色页游爆焰）
const FEEDBACK_SPARK_COLOR: Color = Color("#ffd9a0")
# FEEDBACK_HITSTOP_MS:   {S:150, A:90, A_:100, B:30, C:50, PH:60}   # 顿帧时长（≤100ms 不黏腻，S 例外）
const FEEDBACK_HITSTOP_MS: Dictionary = {"S": 150, "A": 90, "A_": 100, "B": 30, "C": 50, "PH": 60}
# FEEDBACK_SHAKE_PX:     {S:4.0, A:3.0, A_:3.0, B:1.0, C:2.0, PH:4.0}  # 屏震幅值（沿攻击方向）
const FEEDBACK_SHAKE_PX: Dictionary = {"S": 4.0, "A": 3.0, "A_": 3.0, "B": 1.0, "C": 2.0, "PH": 4.0}
# FEEDBACK_SLOWMO:       {S:{scale:0.05, ms:500}, A:{scale:0.3, ms:200}, A_:{scale:0.5, ms:300}}
#                        # 慢动作仅 S/A/A- 级（issue: 滥用失去重量 = AC5）
const FEEDBACK_SLOWMO: Dictionary = {
    "S": {"scale": 0.05, "ms": 500},
    "A": {"scale": 0.3,  "ms": 200},
    "A_": {"scale": 0.5, "ms": 300},
}
# FEEDBACK_FLASH:        {A:{alpha:0.35, ms:120}, A_:{alpha:0.25, ms:100}}  # 实体闪/全屏淡闪
const FEEDBACK_FLASH: Dictionary = {"A": {"alpha": 0.35, "ms": 120}, "A_": {"alpha": 0.25, "ms": 100}}
# FEEDBACK_TIME_MAX_STACK: 3    # 时间栈深度上限（超限丢弃新 push 保旧恢复）
const FEEDBACK_TIME_MAX_STACK: int = 3
# FEEDBACK_SPARK_Z_INDEX: -1     # 火花层级 < 角色层（粒子不盖角色红线，单测断言）
const FEEDBACK_SPARK_Z_INDEX: int = -1
# FEEDBACK_SPARK_VELOCITY/LIFETIME/SHAKE_DECAY/ENTITY_FLASH_FACTOR: # DRAFT 候补值（taste 域，同分区追加）
```

> 全部 `# DRAFT` + 候补值注释，禁止实现期定稿（taste-draft 红线）；`test_constants.gd` 的防误定稿守卫由 #584 既有套件覆盖（本分区常量同样被扫描）。

### 3.3 tests/run_tests.gd — 注册新套件

在 `_run_tests()` 末尾追加一行（现有 12 套件之后）：
```gdscript
_run("res://tests/test_reaction_controller.gd", "ReactionController")
```

### 3.4 e2e_shots.json — 追加反馈 shot group

在 `states` 组内追加三个 shot（格式照 #574 既有条目）：

| shot name | 注入 | 预期捕获 | settle 说明 |
|-----------|------|---------|-------------|
| `fb_parry_success` | inject `parry_success`（A 级） | 四要素同帧：火花亮斑 + 屏震 offset 非零 + 敌人白闪 + hit-stop 时间标签 | 开启冻结效果帧模式，settle_frames 覆盖 90ms 效果窗口（AC2） |
| `fb_stance_break` | inject `stance_broken`（A- 级） | 全屏淡白闪 + 敌人持续白闪 + 慢动作 0.5x | 同冻结模式 |
| `fb_execute` | inject `execute`（S 级） | 刀光弧线 + 血粒子 + 0.05x 特写 | 同冻结模式（AC6 用户裁决输入） |

## 4. 数据流

### Flow 1: 弹反成功组合触发（正常路径，AC2 核心）

```
CombatJudge.resolve_attack() → emit parry_success(defender, attacker, stance_damage)
  → ReactionController._on_parry_success（bind_judge 连接）
  → trigger_feedback("parry_success", {target_entity: defender, attacker_entity: attacker,
                                       source: "judgment"})
  → FEEDBACK_MATRIX 查表 → 等级 A
  → 同帧并行组合（单帧内完成 = AC2 结构性保证）:
      ├─ FeedbackSpark.burst_at(_derive_impact_point(attacker, defender, dir), "A")
      │     # 16-20 粒 @ 刀与刀交点，方向沿刀面法线（AC3）
      ├─ TimeScaleStack.push(0.05, 90)     # hit-stop 顿帧
      ├─ TimeScaleStack.push(0.3, 200)     # 慢动作渐变（D1: 有效值 = min = 0.05 先主导）
      ├─ ScreenShake.shake(3.0, 攻击向量)   # 3px 屏震
      ├─ FlashEffect.flash_entity(defender, 0.35, 120)  # 敌人白闪
      └─ emit feedback_played("parry_success", "A", data)   # #593 音效 hook
  → 墙钟到期: TimeScaleStack.tick() 逐层 pop → Engine.time_scale 恢复 1.0
  → 敌人硬直 1.2s 由 #574 动画承担（本层不编排）
```

### Flow 2: 处决 S 级嵌套时间缩放（AC4 主场景）

```
execute 事件（#580 未来 / 测试注入）
  → trigger_feedback("execute", {...})
  → 等级 S:
      ├─ SwordArc.trigger_burst()（复用 #574，刀光弧线）
      ├─ FeedbackSpark.burst_at(交点, normal, "S")   # 血粒子 10-14 粒（# DRAFT）
      ├─ TimeScaleStack.push(0.05, 150)   # hit-stop 先 push
      ├─ TimeScaleStack.push(0.05, 500)   # 0.05x 特写慢动作后 push（两层同值嵌套）
      ├─ ScreenShake.shake(4.0, 方向)      # 4px 强震
      └─ 无白闪（构图留白，issue 矩阵）
  → 逐层 pop → 1.0（无卡死，墙钟兜底双保险）
```

### Flow 3: 降级路径（#577 未连接时，PRD §5.3-4）

```
无 bind_judge（_judge_bound == false）→ CombatEntity 状态信号独立驱动:
  subscribe_entity(entity) 已订阅 → state_changed(from, to, entity):
    to == "guard"        → trigger_feedback("block_held", ...)      # B 级
    to == "parry_success"→ trigger_feedback("parry_success", ...)   # A 级
    to == "stagger"      → entity 是玩家 ? player_hit : hit_landed  # C 级（D4）
  stance_broken(entity)  → trigger_feedback("stance_broken", ...)   # A- 级
#577 bind_judge 连接后（组装层 #585 调用），judgment 源事件自动增强（幂等，无重复计数）
```

### Flow 4: 失败/兜底路径（AC4 卡死红线）

```
漏 pop 场景: push(0.05, 150) 后逻辑层忘记 pop
  → ReactionController._process 每帧调 TimeScaleStack.tick(now_ms)
  → 检测 deadline (push 时记录 Time.get_ticks_msec() + 150) 已过
  → 强制移除该层 + _apply() → Engine.time_scale 恢复（墙钟不受 time_scale 影响，机械保证）
```

## 5. 边界情况与错误处理

| # | 边界情形 | 缓解措施 |
|---|---------|---------|
| 1 | 重复事件连发（连招中连续 hit_landed） | 火花 one_shot `restart()` 覆盖旧 burst 不叠加粒子池；时间栈 `MAX_STACK_DEPTH=3` 超限丢弃新 push 保旧恢复；屏震 trauma 取 max 不叠加（§2.4） |
| 2 | 事件发生时场景无 Camera2D（headless 测试） | ScreenShake 对 null/失效 camera no-op + push_warning 一次，不崩 |
| 3 | hit-stop 期间新事件到达（0.05x 中弹反） | 时间栈嵌套 push（D1 min 语义）；火花/屏震照常（视觉不冻结，time_scale 只影响逻辑 delta） |
| 4 | 处决慢动作 0.05x 期间玩家死亡 | C 级玩家受击反馈 + 时间栈外层恢复；death 本身不触发慢动作（防叠加卡顿，矩阵无 death 慢动作项） |
| 5 | 粒子层级盖角色（20 粒上限附近） | `FEEDBACK_SPARK_Z_INDEX = -1` 硬约束（火花 < 角色层）+ 粒子数上限常量；单测断言 z_index 配置 |
| 6 | event 未知/无等级映射 | `trigger_feedback` push_warning + no-op（矩阵表外拒绝），状态不漂移 |
| 7 | 实体引用失效（敌人已 free 后白闪） | `flash_entity` 首行 `is_instance_valid(entity)` 检查，失效跳过实体闪只保留屏震/火花 |
| 8 | 屏震方向/normal data 缺失（#577 早期契约） | `_derive_impact_point` 回退 attacker.global_position + facing 方向 + push_warning，不崩 |
| 9 | 全屏淡白闪滥用（AC5/AC6 页游感红线） | `flash_screen` 仅 A- 级路径可达（矩阵表唯一调用点），100ms 低 alpha 0.25，单测断言调用点 |
| 10 | 同实体重复 subscribe_entity | `_entities` 查重，防信号双连导致反馈翻倍 |

**失败路径（PRD §5.3）:**
1. 时间栈漏 pop → 墙钟兜底 `tick()` 强制恢复（Flow 4，实验 1 验证）
2. GPUParticles2D one_shot 不触发 → `restart()` + `emitting = true` 标准序列，单测断言 `emitting == true`
3. E2E 截图抓不到同帧 → 冻结效果帧模式（时间栈墙钟暂停，火花/白闪停留画面，§2.6）
4. #577 事件未连接 → 降级路径 state_changed 驱动（Flow 3），bind_judge 后自动增强

## 6. 集成点

| 集成 | 本设计组件 | 目标 Issue | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| 判定系统 | ReactionController.bind_judge() | #577 | 五结果事件直连（parry_success/block_held/hit_landed/clash/stance_broken）→ trigger_feedback | ⬜ pending |
| 战斗实体 | ReactionController.subscribe_entity() | #575 | 6 信号订阅（state_changed 闭包捕获实体，D2/D4） | ⬜ pending |
| 处决系统 | trigger_feedback("execute") | #580 | execute 事件 → S 级组合（#580 未实现期由测试/E2E 注入） | ⬜ pending |
| 战斗场景 | ReactionController @export camera_path | #583 | 战斗场景挂 Camera2D + 实例化 ReactionController | ⬜ pending |
| 组装闭环 | bind_judge + subscribe_entity + 场景实例化 | #585 | 组装层 #585 接线（本 issue 交付组件与契约） | ⬜ pending |
| 音效系统 | signal feedback_played(event, level, data) | #593 | #593 消费 hook；本 issue 只发信号不发声 | ⬜ pending |
| E2E 截图 | e2e_feedback_capture + e2e_shots.json | #574 模式沿用 | 三档 shot（parry_success/stance_break/execute）供用户裁决 | ⬜ pending |

## 7. 实现阶段

| 阶段 | 优先级 | 组件 | 估算 |
|:----:|:------:|------|:----:|
| Phase 1 | P0 | constants.gd 反馈分区（§3.2，全部 FEEDBACK_ # DRAFT） | 0.5d |
| Phase 2 | P0 | time_scale_stack.gd（D1 min 语义 + 墙钟兜底） | 0.5d |
| Phase 3 | P0 | feedback_spark.gd（burst 参数化 + z_index） | 0.5d |
| Phase 4 | P0 | screen_shake.gd（trauma² + camera_path 解耦） | 0.5d |
| Phase 5 | P0 | flash_effect.gd（双通道 + is_instance_valid 防护） | 0.5d |
| Phase 6 | P0 | reaction_controller.gd（矩阵 + trigger_feedback + bind_judge + subscribe_entity + _derive_impact_point） | 1d |
| Phase 7 | P0 | test_reaction_controller.gd + run_tests.gd 注册（§8 五组用例） | 0.75d |
| Phase 8 | P1 | e2e_feedback_capture.gd/.tscn + e2e_shots.json 三档 shot | 0.75d |
| **合计** | | | **~5d**（PRD estimate 3d 上浮：含 E2E rig 与边界用例；核心机制 3d 对齐） |

## 8. 测试用例描述

> 全部为**测试描述**（场景 + 前置 + 预期），实现期由 implement agent 写成 `test_reaction_controller.gd`（extends Object + run()/_assert 模式，照 #584 先例）；不写可运行测试文件。

### Scenario A: 分级矩阵映射与单调性（AC1/AC5）
- Test 1: 矩阵完备性 —— 前置：加载 constants 反馈分区 + FEEDBACK_MATRIX；遍历 6 主事件（parry_success/block_held/hit_landed/stance_broken/execute/player_hit）断言每事件有等级映射且参数包 6 维（火花/hit-stop/屏震/慢动作/白闪）非空。预期：全部非空。
- Test 2: 等级单调性 —— 粒子数/时长/幅值按 S≥A≥A-≥B≥C 单调（AC5「反馈与奖励成正比」数值断言）。预期：单调成立。
- Test 3: 慢动作仅限 S/A/A- —— 遍历矩阵断言 B/C 级慢动作参数为禁用。预期：B/C 无慢动作。
- Test 4: 反页游断言 —— 全屏闪白路径仅 stance_broken(A-) 可达；grep 断言无散落硬编码（FEEDBACK_ 前缀集中）。预期：唯一调用点 + 零硬编码。
- Test 5: 未知事件 —— `trigger_feedback("nonexistent")`。预期：push_warning + no-op，Engine.time_scale 不变。

### Scenario B: 时间缩放栈三路径（AC4）
- Test 1: 单层 push→pop —— push(0.05, 150) → 断言 Engine.time_scale == 0.05 → pop → == 1.0。
- Test 2: 两层嵌套（D1 min 语义）—— push(0.05, 150) → push(0.3, 200) → 断言中间值 **0.05**（最慢层主导，非栈顶 0.3）→ pop → 0.3 → pop → 1.0。
- Test 3: 墙钟兜底 —— push(0.05, 50) 后不 pop，模拟推进墙钟（sleep/注入 now_ms）超 deadline → tick() 强制恢复 1.0。
- Test 4: 栈深上限 —— 连续 push 4 次 → 第 4 次被丢弃（MAX_STACK_DEPTH=3），恢复路径完整。
- Test 5: hit-stop 用 0.05 非 0 —— 矩阵参数断言无 0 值（0 冻结引擎处理，兜底失效红线）。

### Scenario C: 火花 burst（AC3）
- Test 1: 碰撞点直传 —— burst_at(注入 position, normal, "A") → 断言 `global_position == 注入值`（无中心猜测代码路径，AC3 结构断言）。
- Test 2: 方向 —— 断言 ParticleProcessMaterial.direction == 注入 normal。
- Test 3: 粒子数 —— amount ∈ 等级区间（A: 16-20，按常量 18）；`emitting == true`（one_shot 触发序列，PRD §5.3-2）。
- Test 4: 层级 —— 断言 `z_index == C.FEEDBACK_SPARK_Z_INDEX`（< 角色层，粒子不盖角色红线）。
- Test 5: 颜色 —— 断言 color_ramp 主色 == `Color("#ffd9a0")`（禁橙色）。

### Scenario D: 屏震衰减（实验 2）
- Test 1: 单调衰减 —— shake(3.0, dir) 后逐帧采样 offset 幅值 → 断言单调递减、终值回 0（trauma² 指数衰减）。
- Test 2: 方向 —— 断言 offset 方向与攻击向量一致（C 级 2px 沿攻击方向可感知）。
- Test 3: 无相机 no-op —— camera_path 空 → shake 调用不崩 + push_warning。
- Test 4: 叠加取 max —— 两次 shake 同帧 → trauma 不超 1.0、不线性叠加爆震。

### Scenario E: 白闪双通道
- Test 1: 实体白闪 —— flash_entity(有效实体) → modulate 冲高（Color(5,5,5)）→ 渐回 WHITE（tween 完整）。
- Test 2: 失效实体防护 —— flash_entity(freed 实体) → 跳过实体闪，无报错。
- Test 3: 全屏淡闪仅 A- —— 断言 flash_screen 唯一调用点在 stance_broken 处理路径；alpha/时长 == 常量（0.25/100ms）。
- Test 4: 层序 —— CanvasLayer layer == 0（低于 UI/氛围层，不遮 HUD）。

### Scenario F: 弹反成功四要素同帧（AC2 决定性）
- Test 1: 组合触发 —— `trigger_feedback("parry_success", {position, normal, target_entity, attacker_entity})` 单帧内：火花 emitting==true + time_scale == 0.05（min 语义）+ 屏震 trauma > 0 + 敌人 modulate 冲高。预期：四要素同一帧全部激活。
- Test 2: feedback_played 信号 —— 断言收到 (event="parry_success", level="A", data)（#593 hook 契约）。

### Scenario G: 碰撞点推导（AC3/边界 8）
- Test 1: 正常推导 —— 双实体含 SwordPivot → `_derive_impact_point` 返回两 pivot 中点 + 法线。
- Test 2: 无 pivot 回退 —— 剥离 pivot 节点 → 回退 attacker.global_position + facing 方向 + push_warning，不崩。
- Test 3: 信号订阅身份（D4）—— subscribe_entity(player/enemy) 后 state_changed→stagger 分别映射 player_hit / hit_landed。

### Scenario H: E2E rig 三档截图（AC2/AC6）
- Test 1: inject_feedback 契约 —— rig.inject("parry_success") → ReactionController 收到事件、矩阵 A 级、四要素激活（冻结模式截图可捕获）。
- Test 2: 三档 shot —— e2e_shots.json 含 fb_parry_success / fb_stance_break / fb_execute，settle_frames 覆盖效果窗口（冻结模式）。
- Test 3: current_state 轮询兼容 —— rig 暴露 current_state 整数属性，e2e_capture 驱动可轮询。

## 9. 验收条件映射（源自 Issue #579 body）

| AC | 验收条件 | 设计保障 | 验证 |
|:--:|---------|---------|------|
| AC1 | 反馈分级矩阵完整实现：S/A/B/C 六级事件各有独立反馈组合，参数集中 constants.gd # DRAFT | §2.1 矩阵 9 事件 × 6 维度；§3.2 FEEDBACK_ 分区全集中 | Scenario A Test 1/4 |
| AC2 | 弹反成功四要素同步（火花 16-20 粒 + hit-stop 80-100ms + 屏震 3px + 敌人白闪/硬直 1.2s）E2E 截图同帧捕获 | §2.1 单入口单帧组合触发 + §2.6 冻结效果帧 rig | Scenario F Test 1 + Scenario H |
| AC3 | 火花碰撞点位于刀与刀交点（非角色中心），方向沿刀面法线，颜色 #ffd9a0 系 | §2.1 _derive_impact_point（SwordPivot 中点）+ §2.2 位置/方向直传 | Scenario C Test 1/2/5 + Scenario G |
| AC4 | hit-stop 与慢动作时间缩放可安全嵌套恢复（处决 0.05x 特写结束恢复 1.0，无卡死） | §2.3 TimeScaleStack 栈 + 墙钟兜底（D1 min 语义） | Scenario B Test 2/3 + Flow 2/4 |
| AC5 | 反馈强度与事件奖励成正比（处决>弹反>格挡>命中），滥用慢动作/满屏特效=AC 失败 | §2.1 矩阵单调 + 慢动作仅 S/A/A- + 全屏闪仅 A- | Scenario A Test 2/3/4 |
| AC6 | E2E 截图提交用户裁决：『刀锋相撞』重量感成立，未破坏雪夜水墨宁静基调 | §3.4 三档 shot + 冻结模式 + 参数 # DRAFT 走 #584 通道 | Scenario H + review agent 提交用户 |

## 10. 明确不修改（与 PRD §8.5 红线对齐）

- ❌ `combat_entity.gd` / `combat_states.gd` / `combat_state_table.gd`（#575 契约红线——只订阅信号，改一个字节都不行）
- ❌ `sword_arc.gd`（只调用 `trigger_burst()`，不改实现）
- ❌ `scenes/Main.tscn`（标题场景红线）
- ❌ `mini-pong/` 任何文件（游戏隔离红线）
- ❌ `game-env/manifest.yaml` / `.github/workflows/` / `docs/GAME_DESIGN/` / `tests/check_compile.gd` / `tests/smoke_test.gd`
- ❌ 引入第三方 addon（#572 裁决；timeflow/trauma-gd 只借鉴模型）
- ❌ 任何 `# DRAFT` 数值定稿（FEEDBACK_ 常量定稿归 #584/用户）
- ❌ 判定/处决逻辑（#577/#580 职责）、音效发声（#593 职责，只留 feedback_played hook）
- ❌ `Engine.time_scale` 散落赋值（只经 TimeScaleStack 写入——AC4 卡死红线）
- ❌ 全屏闪白滥用（仅 A- 级 100ms 低 alpha）、橙色火花/页游光效叠加（AC6 红线）
