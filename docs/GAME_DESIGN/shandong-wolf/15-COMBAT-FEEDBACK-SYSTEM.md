# 打击反馈系统 — 火花 / hit-stop / 屏震 / 慢动作 / 白闪（#579/#654/#675/#661）

> 落盘依据：PR **#654**（feat(579) 打击反馈系统，已 merge 2026-08-20）← DESIGN
> `docs/DESIGN/579-combat-feedback-system.md`（plan PR #653 已 merge）。
> 上游：#575 战斗实体（6 信号）、#577 判定层（五结果事件，PR #626）、#574 火柴人动画
> （SwordArc 刀光 + E2E CaptureRig 模式）、#572 constants.gd 分区格式。
> ✅ 代码状态：#654 已合并，`reaction_controller.gd` / `feedback_spark.gd` /
> `time_scale_stack.gd` / `screen_shake.gd` / `flash_effect.gd` /
> `e2e_feedback_capture.gd/.tscn` / `test_reaction_controller.gd` 与 constants.gd「反馈分区」、
> run_tests.gd 注册、e2e_shots.json feedback 组全部落地 **main**（2026-08-20）。
> 全部强度参数为 `# DRAFT` 候补值，定稿归 #584/用户（taste 域）。

## 1. 设计意图

**问题本质是「战斗事件的信号源全齐，但消费信号渲染分级反馈的执行层零存在」。**
#575 已交付 CombatEntity（6 信号）、#577 已交付 CombatJudge 五结果事件
（parry_success / block_held / hit_landed / clash / stance_broken）、#574 已交付
SwordArc 刀光——但玩家弹反/格挡/被击时画面上**毫无回应**。本系统交付 =
**ReactionController 统一消费信号 + 分级事件矩阵（S/A/A-/B/C 六级）+ 五个瞬态效果组件
（火花/hit-stop/屏震/白闪/刀光）+ 参数集中 constants.gd「反馈分区」（# DRAFT）+
E2E 同帧截图 rig**。只狼手感的 50% 来自『打铁』节奏：每个事件有精准、克制的反馈组合，
80-100ms 内四要素同步完成（AC2）。

设计哲学三条（与 PRD §4 推荐方案逐项对齐，无分歧）：

1. **事件驱动消费**：反馈层只消费信号，不做判定（#577 职责）；单一入口
   `trigger_feedback(event, data)` 在同一帧内组合触发全部效果组件——AC2「四要素同帧」
   的结构性保证。
2. **轻量 Node 编排**：五个效果组件是轻量 Node，由 ReactionController 编排（不是 autoload
   单例——避免 AC2 同帧无法保证）；`@export camera_path` 与场景解耦（战斗场景 #583 /
   E2E rig 各自实例化）。
3. **参数单一事实源**：所有数值进 constants.gd `FEEDBACK_` 前缀分区（`# DRAFT` 候补值，
   格式照 #572）；FEEDBACK_MATRIX 只引用常量，零散落硬编码（A4 anti-arcade 断言）。

## 2. 架构决策

| 决策点 | 采纳方案 | 否决方案 | 否决理由 |
|--------|---------|---------|---------|
| 编排器形态 | A：ReactionController（Node2D，单入口 `trigger_feedback` 事件驱动，组合触发） | B：autoload 单例 | AC2 同帧无法保证；职责耦合违规（PRD §4） |
| 时间缩放 | A：TimeScaleStack 栈式 + 墙钟兜底（D1 min 语义，`Engine.time_scale` 唯一写入口） | 直接赋值/单层 timer | AC4 卡死红线：漏 pop 也必须恢复；hit-stop 与慢动作可安全嵌套 |
| 火花 | A：GPUParticles2D one_shot burst，代码创建零 .tres，苍白金 #ffd9a0 | 美术粒子资产/橙色爆焰 | 项目零美术资产红线；issue 禁橙色页游爆焰（AC6） |
| 屏震 | A：Camera2D offset trauma² 指数衰减，方向沿攻击向量 | 无相机抖动/线性衰减 | 只有 Camera2D 解耦才能在 E2E rig 与战斗场景复用（D1/D2 STRICT 测试可断言） |
| 白闪 | A：实体 modulate 冲高 + CanvasLayer 全屏淡闪双通道（S 级刀光复用 SwordArc） | 单通道/改动画层 | 实体闪覆盖深色火柴人（×5 冲白）；全屏淡闪仅 A- 级路径可达（AC5/AC6 页游感红线） |
| 碰撞点 | D3：`_derive_impact_point` 从两 SwordPivot 全局位置取中点（刀与刀交点） | 角色中心猜测 | AC3「非角色中心」的结构保证；#577 事件无 position 参数（契约差异已预期） |
| 实体身份 | D2/D4：`subscribe_entity` 闭包捕获实体；`entity.is_player` 判定玩家/敌人 | 信号带身份参数 | #575 `state_changed(from,to)` 仅 2 参无实体；闭包是 #577 先例验证的安全解法 |

## 3. 组件结构

### 3.1 reaction_controller.gd — 组合触发核心

`ReactionController (Node2D, class_name ReactionController)` —— 唯一入口，_ready 代码创建
子组件（零 .tres；TimeScaleStack 为 RefCounted 不挂节点树）：

```text
ReactionController (Node2D, class_name ReactionController)
├── FeedbackSpark (GPUParticles2D, 代码创建, z_index = FEEDBACK_SPARK_Z_INDEX = -1)
├── ScreenShake (Node, @export camera_path → Camera2D)
├── FlashEffect (Node, 代码创建 CanvasLayer(layer=0) → ColorRect 全屏淡闪通道)
└── TimeScaleStack (RefCounted, 不挂树, 由 _process 驱动 tick)
```

**分级矩阵 FEEDBACK_MATRIX**（9 事件 × 6 维，数据全部引用 constants FEEDBACK_*）：

| 事件 | 等级 | 火花 | hit-stop | 屏震 | 慢动作 | 白闪/其他 | 事件信号源 |
|------|:----:|------|----------|------|--------|-----------|-----------|
| execute | S | SwordArc.trigger_burst() + 血粒子 | 150ms | 4px | 0.05x 500ms | 无（构图留白） | execute 事件（#580 未来/测试注入） |
| parry_success | A | 18 粒 | 90ms | 3px | 0.3x 200ms | 敌人白闪（α0.35/120ms） | #577 parry_success / state_changed→parry_success |
| stance_broken | A- | 无 | 100ms | 3px | 0.5x 300ms | 全屏淡白闪（α0.25/100ms）+ 敌人白闪 | #577 stance_broken / 实体信号 |
| block_held | B | 6 粒 | 30ms | 1px | 无 | 无 | #577 block_held / state_changed→guard |
| hit_landed | C | 8 粒 | 50ms | 2px | 无 | 敌人硬直（#574 stagger 动画） | #577 hit_landed / state_changed→stagger |
| player_hit | C (tier PH) | 无 | 60ms | 4px | 无 | 玩家后仰（#574 stagger 动画） | state_changed→stagger（D4 判玩家） |
| clash | B | 12 粒 | 60ms | 2px | 无 | 双方小硬直 | #577 clash |
| revive | C | 无 | 无 | 1px | 无 | 复活演出反馈（参数 # DRAFT） | revived 信号 |
| death | C (tier PH) | 无 | 60ms | 4px | 无 | 玩家受击反馈（不触发慢动作） | died 信号（final 时） |

> 单调性（AC5）：粒子数/时长/幅值 S≥A≥A-≥B≥C；慢动作仅 S/A/A- 级；全屏淡白闪仅
> stance_broken(A-) 路径可达。player_hit/death 走 **PH tier**（FEEDBACK_* 的 PH 键：
> 60ms/4px，非 C 档）——矩阵表 `tier` 字段覆盖默认等级参数。

**关键 API（定义）：**

```gdscript
signal feedback_played(event: String, level: String, data: Dictionary)  # #593 音效 hook（只发信号不发声）

func trigger_feedback(event: String, data: Dictionary = {}) -> void
#   event ∈ FEEDBACK_MATRIX 键集；未知事件 → push_warning + no-op（边界 6）
#   data 键约定: position/normal（AC3 直传，缺省 → _derive_impact_point 推导）/
#     target_entity（白闪目标）/ attacker_entity（方向兜底）/ direction（facing）/
#     direction_vec（屏震方向覆盖）/ source
#   组合触发顺序（单帧完成 AC2）: spark.burst_at → TimeScaleStack.push(0.05, hitstop)
#     → push(slowmo)（嵌套，D1 min）→ shake.shake → flash（实体/全屏）→ execute 刀光
#     → emit feedback_played

func bind_judge(judge: Node) -> void
#   五结果事件直连（has_signal 防护）: parry_success/block_held/hit_landed/clash/
#     stance_broken → trigger_feedback(source:"judgment")

func subscribe_entity(entity: Node) -> void
#   6 信号订阅（_entities 查重防双连）: state_changed 闭包捕获实体（D2/D4）/
#     stance_broken / died(final) / revived
#   降级路径（#577 未连接时驱动）: guard→block_held / parry_success→parry_success /
#     stagger→player_hit|hit_landed（is_player 判定）/ stance_break→stance_broken

func _derive_impact_point(attacker, defender, direction: int) -> Dictionary
#   两 SwordPivot 全局位置中点 = 刀与刀交点（AC3）+ 法线 Vector2(0, -direction)
#   推导失败 → 回退 attacker.global_position + facing 方向 + push_warning（边界 8）
```

### 3.2 time_scale_stack.gd — 时间缩放栈（AC4 核心）

`class_name TimeScaleStack extends RefCounted`（纯逻辑，ReactionController._process 驱动）。

- **D1 min 语义**：有效 `Engine.time_scale` = 栈内最小 scale（最慢层主导）——hit-stop
  0.05 期间慢动作 0.3 push 不稀释顿帧；hit-stop pop 后 0.3 继续，逐层恢复 1.0。
- **墙钟兜底（AC4 机械保证）**：每层记录 `deadline_ms = push 时墙钟 + duration_ms`；
  `tick(now_ms)` 到期强制移除（墙钟不受 time_scale 影响），漏 pop 也不会卡死。
- **hit-stop 用 0.05 而非 0**：0 冻结引擎处理 → 墙钟兜底失效红线（PRD §8.4-3）。
- **pop 语义**：移除**最早到期**层（hit-stop 先 pop、慢动作层保留——非 LIFO 栈顶）。
- **边界 1**：栈深超限 `FEEDBACK_TIME_MAX_STACK=3` → push_warning + 丢弃新层保旧恢复。
- E2E 冻结模式：`freeze_time_stack` 开启 → _process 跳过 tick（hit-stop 保持冻结供截图）。

### 3.3 feedback_spark.gd — 火花粒子（AC3）

`FeedbackSpark (GPUParticles2D, class_name FeedbackSpark)` —— 材质代码创建
（ParticleProcessMaterial + GradientTexture1D 苍白金渐变，零 .tres）。

```gdscript
func burst_at(world_pos: Vector2, normal: Vector2, level: String) -> void
#   global_position = world_pos（AC3: 碰撞点直传，无中心猜测）
#   material.direction = normal（方向沿刀面法线）
#   amount = FEEDBACK_SPARK_COUNT[level]（S:14 / A:18 / B:6 / C:8）
#   velocity/lifetime 读 FEEDBACK_SPARK_VELOCITY/LIFETIME（# DRAFT）
#   restart() + emitting = true 标准 burst 序列；one_shot restart 覆盖旧 burst 不叠加（边界 1）
```

- 颜色 `FEEDBACK_SPARK_COLOR = #ffd9a0` 苍白金 → 尾色 `#d3b188`（禁橙色页游爆焰）。
- `z_index = FEEDBACK_SPARK_Z_INDEX = -1` < 角色层（粒子不盖角色红线，单测断言）。

### 3.4 screen_shake.gd — 屏震（PRD 实验 2）

`ScreenShake (Node, class_name ScreenShake)` —— `@export camera_path` 解耦。

- `shake(max_offset_px, direction)`：trauma 增量 0.6 叠加取 max（cap 1.0，不爆震）；
  每次 shake 重采样恒定噪声（_noise_mag/_noise_sign，确定性包络——非逐帧随机，
  单调衰减可断言）。
- `_process`：`cam.offset = direction × sign × mag × trauma² × max_offset`；
  `trauma -= trauma × FEEDBACK_SHAKE_DECAY × delta`（指数衰减，终值回 0）。
- 相机缺失/失效 → no-op + push_warning 一次（边界 2，headless 测试不崩）。

### 3.5 flash_effect.gd — 白闪双通道（AC2/AC5）

`FlashEffect (Node, class_name FlashEffect)`。

- **实体白闪**：`flash_entity(entity, alpha, ms)` —— 同步冲高 `modulate = Color(5,5,5)`
  （`FEEDBACK_ENTITY_FLASH_FACTOR=5.0`，高倍乘算 = 深色火柴人 #2b2b2b 也冲白）→ 保持
  duration_ms → 0.2s 渐回 WHITE；首行 `is_instance_valid` 防护（边界 7：实体已 free
  跳过，无报错）；只动 modulate 外层不动动画层（#574 职责）。
- **全屏淡闪**：`flash_screen(alpha, ms)` —— 代码创建 `CanvasLayer(layer=0) → ColorRect`
  全屏（鼠标穿透）；同步置 alpha → 保持 → 0.25s 淡出归零；层序低于 UI(1)/氛围(2-10)，
  不遮 HUD；**仅 A- 级（stance_broken）路径可达**（矩阵唯一调用点，AC5/AC6 红线）。

### 3.6 e2e_feedback_capture.gd/.tscn — E2E 同帧截图 rig（AC2/AC6）

`E2EFeedbackCapture (Node2D, class_name E2EFeedbackCapture)` —— 双火柴人
（复用 player_stick_figure.tscn 零新美术）+ ReactionController + Camera2D（屏震目标）。

- 驱动契约（与 #574 CaptureRig 兼容）：`current_state: int`（IDLE=0 /
  PARRY_SUCCESS=1 / STANCE_BREAK=2 / EXECUTE=3 / HIT_LANDED=4）可轮询；
  `inject_feedback(event)` 公开方法推导刀与刀交点 + 法线转 controller。
- digit 键（_unhandled_input，沿用 #574 模式）：4→parry_success / 6→stance_broken /
  7→execute / 2→hit_landed；auto_cycle 兜底（CYCLE_SEQUENCE = IDLE→三档→IDLE）。
- **冻结效果帧模式**（AC2 决定性兜底）：`freeze_effects` 开启 → 时间栈墙钟不推进，
  火花/白闪停留画面供截图（shot plan 在效果窗口内开启）。
- **组级 autoplay 冻结接线**（#661，2026-08-21 merge）：e2e_shots.json feedback 组声明组级
  `autoplay`（resolve_plan 提升契约）→ tweaks 设 `/root/CaptureRig.freeze_effects=true` +
  `auto_cycle_frames=200`（> 最大 settle 120，settle 期间不跨态）——冻结效果帧模式由 shot plan
  tweak 数据通道落地；顶层 autoplay 放 freeze tweak 会对无此属性的 stick rig 报错，组级隔离
  是唯一干净通道（GDD 18 §9）。
- e2e_shots.json `groups.feedback` 组 3 shot：fb_parry_success（settle 90 帧）/
  fb_stance_break（100 帧）/ fb_execute（120 帧），供用户 AC6 裁决。

## 4. 常量（constants.gd「反馈分区」，文件尾部追加，全部 # DRAFT）

| 常量 | 值 | 说明 |
|------|-----|------|
| FEEDBACK_SPARK_COUNT | {S:14, A:18, B:6, C:8} | 粒子数（issue 矩阵 A 16-20 取 18） |
| FEEDBACK_SPARK_COLOR | Color("#ffd9a0") | 苍白金（禁橙色页游爆焰） |
| FEEDBACK_HITSTOP_MS | {S:150, A:90, A_:100, B:30, C:50, PH:60} | 顿帧时长（≤100ms 不黏腻，S 例外） |
| FEEDBACK_SHAKE_PX | {S:4.0, A:3.0, A_:3.0, B:1.0, C:2.0, PH:4.0} | 屏震幅值（沿攻击方向） |
| FEEDBACK_SLOWMO | {S:{0.05,500ms}, A:{0.3,200ms}, A_:{0.5,300ms}} | 慢动作仅 S/A/A- 级 |
| FEEDBACK_FLASH | {A:{α0.35,120ms}, A_:{α0.25,100ms}} | 实体闪/全屏淡闪 |
| FEEDBACK_TIME_MAX_STACK | 3 | 时间栈深度上限（超限丢弃新 push 保旧恢复） |
| FEEDBACK_SPARK_Z_INDEX | -1 | 火花层级 < 角色层 |
| FEEDBACK_SPARK_VELOCITY/LIFETIME | {S:260/0.5, A:240/0.45, B:140/0.3, C:170/0.35} | 速度/寿命（# DRAFT） |
| FEEDBACK_SHAKE_DECAY | 3.0 | 屏震指数衰减系数 |
| FEEDBACK_ENTITY_FLASH_FACTOR | 5.0 | 实体白闪 modulate 倍乘 |

> 全部 `# DRAFT` 候补值，**禁止实现期定稿**（taste 域，定稿归 #584/用户）；
> test_constants.gd 防误定稿守卫覆盖本分区。

## 5. 数据流

### Flow 1: 弹反成功组合触发（正常路径，AC2 核心）

```
CombatJudge.resolve_attack() → emit parry_success(defender, attacker, stance_damage)
  → ReactionController._on_parry_success（bind_judge 连接）
  → trigger_feedback("parry_success", {target_entity, attacker_entity, source:"judgment"})
  → FEEDBACK_MATRIX 查表 → 等级 A
  → 同帧并行组合（单帧内完成 = AC2 结构性保证）:
      ├─ FeedbackSpark.burst_at(_derive_impact_point(...), "A")   # 18 粒 @ 刀与刀交点
      ├─ TimeScaleStack.push(0.05, 90)    # hit-stop 顿帧
      ├─ TimeScaleStack.push(0.3, 200)    # 慢动作渐变（D1: 有效值 = min = 0.05 先主导）
      ├─ ScreenShake.shake(3.0, 攻击向量)  # 3px 屏震
      ├─ FlashEffect.flash_entity(defender, 0.35, 120)  # 敌人白闪
      └─ emit feedback_played("parry_success", "A", data)  # #593 音效 hook
  → 墙钟到期: TimeScaleStack.tick() 逐层 pop → Engine.time_scale 恢复 1.0
  → 敌人硬直 1.2s 由 #574 动画承担（本层不编排）
```

### Flow 2: 降级路径（#577 未连接时，PRD §5.3-4）

```
无 bind_judge（_judge_bound == false）→ CombatEntity 状态信号独立驱动:
  subscribe_entity(entity) 已订阅 → state_changed(from, to, entity):
    to == "guard"         → trigger_feedback("block_held", ...)     # B 级
    to == "parry_success" → trigger_feedback("parry_success", ...)  # A 级
    to == "stagger"       → entity.is_player ? player_hit : hit_landed  # C 级（D4）
  stance_broken(entity)   → trigger_feedback("stance_broken", ...)  # A- 级
#577 bind_judge 连接后（组装层 #585 调用），judgment 源事件自动增强（幂等，无重复计数）
```

### Flow 3: 失败/兜底路径（AC4 卡死红线）

```
漏 pop 场景: push(0.05, 150) 后逻辑层忘记 pop
  → ReactionController._process 每帧调 TimeScaleStack.tick(now_ms)
  → 检测 deadline (push 时记录 Time.get_ticks_msec() + 150) 已过
  → 强制移除该层 + _apply() → Engine.time_scale 恢复（墙钟不受 time_scale 影响，机械保证）
```

## 6. 集成点

| 集成 | 本系统组件 | 目标 Issue | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| 判定系统 | ReactionController.bind_judge() | #577 | 五结果事件直连 → trigger_feedback | ✅ 已交付（#654） |
| 战斗实体 | ReactionController.subscribe_entity() | #575 | 6 信号订阅（state_changed 闭包捕获 D2/D4） | ✅ 已交付（#654） |
| 处决系统 | trigger_feedback("execute") | #580 | S 级组合（#580 未实现期由测试/E2E 注入） | ⬜ pending |
| 战斗场景 | ReactionController @export camera_path | #583 | 战斗场景挂 Camera2D + 实例化 ReactionController | ⬜ pending |
| 组装闭环 | bind_judge + subscribe_entity + 场景实例化 | #585 | 组装层 #585 接线（本系统交付组件与契约） | ⬜ pending |
| 音效系统 | signal feedback_played(event, level, data) | #593 | #593 消费 hook；本系统只发信号不发声 | ⬜ pending |
| E2E 截图 | e2e_feedback_capture + e2e_shots.json | #574 模式沿用 | 三档 shot（parry_success/stance_break/execute）供用户裁决 | ✅ 已交付（#654） |

## 7. 测试（test_reaction_controller.gd，28 用例，run_tests.gd 第 13 套件）

| Scenario | 覆盖 | 关键断言 |
|:--------:|------|---------|
| A | 分级矩阵映射与单调性（AC1/AC5） | 9 事件 6 维非空；S≥A≥A-≥B≥C 单调；B/C 无慢动作；全屏闪唯一调用点；未知事件 no-op |
| B | 时间缩放栈三路径（AC4） | 单层 push→pop；两层嵌套 D1 min（0.05 非栈顶 0.3）；墙钟兜底强制恢复；栈深上限 3；无 0 值 |
| C | 火花 burst（AC3） | 碰撞点直传 global_position；方向==法线；amount 按等级；z_index==-1；颜色 #ffd9a0 |
| D | 屏震衰减（实验 2） | 单调衰减终值回 0；方向沿攻击向量；无相机 no-op；叠加取 max 不爆震 |
| E | 白闪双通道 | 实体 modulate 冲高→回 WHITE；失效实体跳过；全屏闪仅 A-；CanvasLayer layer==0 |
| F | 弹反四要素同帧（AC2 决定性） | 单帧内火花+time_scale 0.05+trauma>0+modulate 冲高；feedback_played 信号契约 |
| G | 碰撞点推导（AC3/边界 8） | 双 SwordPivot 中点+法线；无 pivot 回退 facing+push_warning；D4 身份映射 |

## 8. 红线（与 DESIGN §10 对齐）

- ❌ `Engine.time_scale` 散落赋值（只经 TimeScaleStack 写入——AC4 卡死红线）
- ❌ 全屏淡白闪滥用（仅 A- 级 100ms 低 alpha；矩阵唯一调用点）
- ❌ 橙色火花/页游光效叠加（苍白金 #ffd9a0，AC6 红线）；粒子盖角色（z_index=-1 硬约束）
- ❌ 修改 #575/#577 契约文件（combat_entity.gd / combat_judge.gd / sword_arc.gd 零修改，
  只订阅/调用）
- ❌ 任何 `# DRAFT` 数值定稿（FEEDBACK_ 定稿归 #584/用户）
- ❌ 判定/处决逻辑（#577/#580 职责）、音效发声（#593 职责，只留 feedback_played hook）
- ❌ 引入第三方 addon（timeflow/trauma-gd 只借鉴模型）


## 9. 层级约定：背景 < 火花 < 角色（#675，2026-08-20 merge）

> 落盘依据：PR **#675**（feat(662) backdrop z_index=-2 so combat spark visible，已 merge
> 2026-08-20）← DESIGN `docs/DESIGN/662-e2e-feedback-backdrop-z.md`（plan PR #674 已 merge）。
> 性质：bug 修复 —— #654 rig / #666 Main.tscn 引入全屏背景 ColorRect 时未设 z_index
> （Godot 默认 0），同一 CanvasLayer（layer 0）内按 z_index 升序绘制，不透明背景完整盖住
> 火花（z=-1）→ **官方 E2E 截图永远截不到火花（AC6 素材无法产出）+ 真实战斗玩家看不到打击火花**。

**层级约定（CanvasLayer 0 内 z_index 升序绘制，本 issue 固化）：**

| 层 | z_index | 节点 | 文件 | 状态 |
|:---:|:---:|------|------|:---:|
| 背景 | `-2` | Backdrop（ColorRect） | `shandong-wolf/scenes/e2e_feedback_capture.tscn` | #675 加（原 0） |
| 背景 | `-2` | WorldBackdrop（ColorRect） | `shandong-wolf/scenes/Main.tscn` | #675 加（原 0） |
| 火花 | `-1` | FeedbackSpark（GPUParticles2D） | `gdscripts/feedback_spark.gd`（`FEEDBACK_SPARK_Z_INDEX`，constants.gd） | #579 硬约束，**零改动** |
| 角色 | `0` | 火柴人 stick figure | 战斗场景 | #579 起默认，**零改动** |

**设计要点：**

1. **只动背景层级，不动火花/角色**——火花 -1 是 constants.gd + feedback_spark.gd + C4 单测
   三方锁定的硬约束（「粒子不盖角色」红线）；角色 z=0 保持；仅背景 0 → -2。
2. **z 必须严格 -2，不能 -1**：若设 -1 与火花同层，同层按树序绘制——Backdrop 在场景树中
   先于 ReactionController 声明的火花（代码创建），背景仍会盖住火花（DESIGN §2 失败路径）。
3. **风格统一**：与 battle_stage.tscn 既有 `PlatformSilhouetteMid/Back` 负层级先例
   （z=-1/-2，#583）一致；两处修改均为 .tscn 声明式单属性，零 .gd / tests / e2e_shots.json 改动。
4. **E2E 与真实游戏同时修复**：Main.tscn WorldBackdrop 是玩家实际战斗画面（#585 assembly
   instance Main.tscn 自动继承）——非仅截图问题。

**维护条款（DESIGN §5 边界情况固化）：** 未来新增 E2E rig / 全屏背景节点，默认
`z_index=-2`（低于火花 -1）；「背景 < 火花 < 角色」三层约定是本系统与组装场景的公共契约。
