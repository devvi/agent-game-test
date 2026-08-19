# 两条命原地复活系统 — ReviveOrchestrator + ReviveFX（#578）

> 落盘依据：PR #637（implement，已 merge 2026-08-19）← DESIGN `docs/DESIGN/578-two-life-revive.md`。
> 上游：#575 战斗实体（die()/revive() 机械语义 + died/revived 信号 + dead→revive 转移 + `_invincible_until_sec`）、
> #573/#575 输入桥 F 键手动复活路径、#574 动画（anim_revive/anim_dead 位）、#584 数值 DRAFT 表（REVIVE_SECONDS 等只读）。
> 下游：#585 组装（编排器 + FX 三行接线挂战斗场景）、SW-015 结局失败（消费 died(final=true) 契约）。
> 归属：`content_ownership: mechanical`——复活编排 = 信号订阅 + 计时 + 幂等收敛；FX 演出 = 参数化机械实现，零美术资产；
> 演出数值全量 `# DRAFT` 归 #584 定稿；复活瞬间构图/配色情绪（AC5「硬汉再起 vs 日式中二觉醒」）归用户裁决 → docs/TASTE.md。

## 1. 设计意图

**问题本质是「机械层 100% 就绪，『谁计时驱动』与『演出长什么样』双缺」。** #575 已交付两段血语义
（active_life=1 且 life_total=2 → `died(self, false)` 可复活死）、revive() 全部机械语义（hp_2=50 接管、
架势清空、无敌开启、dead→revive 转移 + revived 广播）、11 态转移表 dead→[revive] 停摆拓扑，但
`gdscripts/` 没有任何自动复活驱动：died(final=false) 信号无人监听计时（当时只有 F 键手动路径），
scenes/Main.tscn 零 CanvasModulate、零 GPUParticles2D——复活 FX 层零存在。本层 = 复活编排器（机械驱动）
+ 复活 FX（演出层）+ SW-015 契约固化，是 #585 组装（战斗闭环）的最后一个机械组件。

**六条设计哲学：**
1. **消费信号不修改实体（红线）**：#575 注释三处预留（die()「#578 接管」/ revive()「#578 驱动」/ revive 态「#578 契约」）——本层**零修改** combat_entity.gd / combat_state_table.gd / combat_states.gd，只做「订阅信号 + 计时 + 调 revive()」，禁止重写 hp/架势/无敌逻辑。
2. **编排与演出双层解耦**：ReviveOrchestrator（机械层：谁在 1s 后调 revive()）与 ReviveFX（演出层：墨点/闪屏/慢动作/闪烁）**各自独立订阅实体信号**——编排器订阅 `died(final=false)`，FX 订阅 `revived`；单向数据流：entity 信号 → 两个消费者，两组件之间零耦合（FX 不依赖编排器），可分别 headless 单测。
3. **双路径幂等收敛**：F 键手动路径（输入桥 `revive_pressed` → entity.revive()，#573/#575 已交付）与自动路径（编排器计时 → entity.revive()）在 revive() 处收敛——dead 停摆只允许 revive 出 + 同态重入 restart 钩子静默返回 = 天然防双触发；编排器再加「收到 revived 即取消 pending」，彻底消除竞争窗口。
4. **headless 确定性**：编排器计时用 `_process(delta)` 累加（对齐 test_combat_entity.gd `_advance()` 手动推进模式），不依赖 SceneTreeTimer——测试同步推进、CI 无渲染/无树依赖。
5. **演出全参数化 + 零字面量**：FX 全部参数进 constants.gd「复活 FX 分区」12 常量（# DRAFT 候选集，定稿归 #584），FX 代码零硬编码。
6. **瞬态与常驻解耦**：闪屏 CanvasModulate 为**瞬态演出节点**（Tween 白→血→复原，结束恢复自身默认 color），与 #582 常驻冷月光 CanvasModulate **节点分离共存**，互不覆盖 color。

## 2. 架构决策

| 决策点 | 方案 A（采纳） | 否决方案 | 否决理由 |
|--------|--------------|---------|---------|
| 计时器实现 | 自管理 `_process(delta)` 累加 | SceneTreeTimer | headless 确定性——测试手动推进零树依赖（对齐 test_combat_entity `_advance` 模式）；PRD 方案 A 明言二选一 |
| 自动复活驱动 | 独立 ReviveOrchestrator 监听 `died(final=false)` | 实体内部自计时 / 挂载层回调 | 消费信号不修改实体红线；编排器 = revive() 第二调用方，与 F 键路径幂等收敛 |
| 无敌闪烁 | 父节点 modulate 传播（bind_player_visual 注入 StickFigure 根） | 逐 Line2D 遍历 | modulate 自动作用于全部 Line2D 肢体 + Polygon2D 头，原子且零遍历成本 |
| FX 挂载位置（#585 前出 AC5 证据） | capture rig（e2e_stick_figure_capture.tscn）挂 FX + REVIVE 态 trigger | Main.tscn 挂载 | 标题场景红线（#572）；游戏内挂载归 #585 组装，impl 期不写死 |
| 闪屏与 #582 共存 | 瞬态节点后挂/高 layer 覆盖 + Tween 结束复原自身 color（零残留） | 复用 #582 常驻节点改色 | 各自 color 互不覆盖；瞬态节点独立性（#582 常驻色温为长期状态） |
| SW-015 终态契约 | died(final=true) 事件契约固化（编排器不启动计时、revive() 被拒） | 本层实现失败结算 | 失败/结算归 SW-015；本层只保证并文档化事件契约 |

## 3. 组件定义

### 3.1 ReviveOrchestrator（`shandong-wolf/gdscripts/revive_orchestrator.gd`，class_name ReviveOrchestrator，extends Node）

自包含脚本节点，无子节点；#585 组装期挂战斗场景 root（add_child 即生效，零配置）。

**状态属性：**

| 变量 | 类型 | 初值 | 说明 |
|------|------|------|------|
| `_player` | Object (CombatEntity) | null | 绑定玩家实体（bind_player 注入；只绑 is_player==true 且 life_total==2 实体，敌人 life_total=1 永不绑定） |
| `_armed` | bool | false | 计时进行中标志（died(false) 置位，revived/unbind/到期清除）——防重入 + 供测试断言（is_armed()） |
| `_elapsed` | float | 0.0 | 自管理计时累加（_process(delta) 推进，headless 可手动驱动） |

**关键方法：**

```gdscript
func bind_player(entity: Object) -> void   # 幂等接线: 先解绑旧实体（disconnect died/revived 防泄漏），再订阅新实体
func unbind_player() -> void               # 场景切换/实体销毁前调用: bind_player(null) 解绑 + 清 pending
func is_armed() -> bool                    # 可观测性: 计时进行中标志（供测试断言）
func _on_entity_died(ent: Object, final: bool) -> void  # 仅 final=false 且为绑定实体 → 启动计时（_armed 防重入双保险）
func _on_entity_revived(ent: Object) -> void            # F 键手动 revive() 先触发时取消自动 pending（消除竞争窗口）
func _process(delta: float) -> void        # 累加至 REVIVE_SECONDS → _player.revive()（唯一驱动点）
```

实现细节两处：`_process` **不判 `_player == null`**（Godot 4 已 free 对象 == null 为 true，会提前 return 导致 pending 永不结算——实体销毁守卫由到期分支 `is_instance_valid(_player)` 承担）；终态/life_total<2 时 revive() 内部 no-op + push_warning（失败路径）。

**SW-015 契约（AC3 证据，本编排器唯一数据源）：**

| 事件 | 参数 | 语义 | 消费者 |
|------|------|------|--------|
| `died(entity, false)` | final=false | 可复活死：第一条血耗尽（life_total=2 玩家），编排器计时 REVIVE_SECONDS(1s) 后 revive() | 本层 ReviveOrchestrator |
| `died(entity, true)` | final=true | 终态：第二条血耗尽（life_total=2）或任意 life_total=1 实体，`_is_final_dead` 置位、revive() 被拒 | SW-015 结局与失败结算（未来 issue） |

### 3.2 ReviveFX（`shandong-wolf/gdscripts/revive_fx.gd`，class_name ReviveFX，extends Node2D）

`_ready()` 代码构建全部子节点（**零 tscn / 零美术资产**，对齐 stick_figure.gd 模式；headless 可 new + 入树断言节点存在）：

```
ReviveFX (Node2D, script=revive_fx.gd)
├── InkBurst (GPUParticles2D)      # one_shot 墨点 burst（40 黑点，朝上半球径向爆开）
└── FlashLayer (CanvasModulate)    # 瞬态闪屏（白 #e8e6e3 → 血 #5a1e1e → 复原 Color.WHITE）
    # 无敌闪烁目标 = bind_player_visual() 注入的 StickFigure 根节点（modulate.a 循环，父节点传播到全部 Line2D 子肢体）
    # 慢动作 = Engine.time_scale 全局短促降速（无节点）
```

**状态属性：**

| 变量 | 类型 | 初值 | 说明 |
|------|------|------|------|
| `_entity` | Object (CombatEntity) | null | 绑定实体（bind_player 注入，订阅 revived → trigger） |
| `_visual_root` | Node2D | null | 玩家剪影根节点（bind_player_visual 注入，无敌闪烁 modulate 目标） |
| `_flash_layer` | CanvasModulate | null | _ready 构建（FlashLayer） |
| `_ink_burst` | GPUParticles2D | null | _ready 构建（InkBurst） |
| `_flash_tween` | Tween | null | 闪屏 Tween 句柄（重复触发先 kill，防叠层） |
| `_flicker_elapsed` | float | 0.0 | 无敌闪烁相位累加（_process 驱动） |
| `_flicker_active` | bool | false | revived 置位，INVINCIBLE_SECONDS 到期清除 |
| `_slowmo_until_sec` | float | 0.0 | 慢动作截止时间戳（Time.get_ticks_msec()/1000.0 比较） |
| `_slowmo_set` | bool | false | 本组件是否设置过 time_scale（仅设置者恢复 1.0，防覆盖他人） |

**关键方法：**

```gdscript
func bind_player(entity: Object) -> void      # 订阅 revived → _on_entity_revived → trigger()（与编排器零耦合）
func bind_player_visual(root: Node2D) -> void # 注入无敌闪烁目标（#585 组装传 Player/StickFigure 根节点）
func trigger() -> void                        # 演出四件套（参数全读 constants，各节点缺失时降级不崩溃）
func _start_flash_tween() -> void             # 白 → 血(FLASH_SECONDS) → 停留(FLASH_HOLD_SECONDS) → 复原(FLASH_SECONDS)；先 kill 旧 Tween
func _start_slowmo() -> void                  # time_scale = maxf(SLOWMO_COEFF, 0.1)（clamp 下限防冻结）；_slowmo_set 防嵌套
func _process(delta: float) -> void           # ① 慢动作到期恢复 1.0 ② 闪烁 modulate.a = lerpf(1.0, ALPHA_MIN, |sin(2π·HZ·t)|)，INVINCIBLE_SECONDS 到期复原 1.0
func _build_ink_texture() -> Texture2D        # 程序化 8x8 圆点 texture（4.7 无 draw_circle → set_pixel 距离判定）；失败返回 null → 默认方形粒子降级
```

演出四件套细节：
- **墨点 burst**：GPUParticles2D `one_shot=true`、`amount=INK_BURST_COUNT(40)`、`lifetime=INK_BURST_LIFETIME(0.4)`；4.x 无直属 direction/spread/color → ParticleProcessMaterial——direction=(0,-1,0) 朝上半球（脚底/刀尖向上爆开）、spread=180°、initial_velocity_min/max=180、gravity=0（向外爆开不受重力下落）、color=INK_COLOR(#141414)；发射位置 = `_visual_root.global_position`。
- **闪屏**：独立 CanvasModulate 瞬态节点；Tween 白 → 血 → 复原自身默认 color（白=恒等），**零残留**——不覆盖 #582 常驻色温（红线）；挂载层级约定：瞬态节点后挂/高 layer（§7）。
- **慢动作**：全局 `Engine.time_scale = maxf(SLOWMO_COEFF, 0.1)`（复用 #577 处决慢动作同源节奏语言，clamp 下限 0.1 防冻结），SLOWMO_HOLD_SECONDS(0.4) 后恢复 1.0；`_slowmo_set` 仅首次设置、仅设置者恢复，重叠触发防嵌套。
- **无敌闪烁**：父节点 modulate 传播——`_visual_root.modulate.a = lerpf(1.0, INVINCIBLE_FLICKER_ALPHA_MIN, absf(sin(phase)))`（8Hz 循环），INVINCIBLE_SECONDS 到期复原 1.0（硬汉第二次机会可读性，禁止残留半透明）。

## 4. 常量参数（constants.gd「复活 FX 分区」，12 常量，全 # DRAFT 定稿归 #584）

| 常量 | 值 | 说明 |
|------|----|------|
| `INK_BURST_COUNT` | 40 | 墨点数量（issue body「30-50 黑点」基准） |
| `INK_BURST_SPEED` | 180.0 | 径向扩散速度（px/s） |
| `INK_BURST_LIFETIME` | 0.4 | 粒子存活时长（0.4s 内淡出不粘连） |
| `INK_COLOR` | Color("#141414") | 墨点色（= HUD_INK_BLACK 同值互引，禁彩色粒子） |
| `INK_BURST_SPREAD_DEG` | 180.0 | 发射张角（脚底发射半球爆开） |
| `FLASH_WHITE` | Color("#e8e6e3") | 闪屏起始色（= HUD_MOON_WHITE 同值互引，苍白月白） |
| `FLASH_BLOOD` | Color("#5a1e1e") | 闪屏目标色（偏暗红不发亮，禁警报红） |
| `FLASH_SECONDS` | 0.2 | 闪白→血色时长（≤0.2s 短促） |
| `FLASH_HOLD_SECONDS` | 0.2 | 血色停留时长（克制停留不拖沓） |
| `SLOWMO_HOLD_SECONDS` | 0.4 | 全局降速时长（复用 SLOWMO_COEFF=0.2 节奏语言） |
| `INVINCIBLE_FLICKER_HZ` | 8.0 | 闪烁频率（8Hz 呼吸感可读，<10Hz 安全区） |
| `INVINCIBLE_FLICKER_ALPHA_MIN` | 0.3 | 闪烁谷值（可读不刺眼） |

## 5. 数据流

### Flow 1：自动复活正常路径（AC1/AC4）

```
take_damage (hp_1 ≤ 0, life_total=2)
  → die(): emit died(entity, final=false) → request_transition("dead") → anim_dead 倒地
  → ReviveOrchestrator._on_entity_died(false): _armed=true, _elapsed=0
  → _process 累加至 REVIVE_SECONDS(1.0s)
  → entity.revive(): hp_2=50 接管 · stance=0 · 无敌 1s · dead→revive 转移
      ├─ emit revived(entity) → ReviveFX.trigger(): 墨点 burst + 闪屏 Tween + time_scale 降速 + 闪烁启动
      ├─ emit state_changed(dead→revive) → anim_revive 起身动画
      └─ 编排器 _on_entity_revived: 取消 pending（本路径计时已到期，无实际影响）
  → revive 态 REVIVE_SECONDS 后自动 → idle（#575 已实现）→ 无敌期结束 → 正常战斗
```

### Flow 2：F 键手动路径与自动路径竞争（边界 3）

```
路径 A（自动）: died(false) → 编排器计时 1s → revive()
路径 B（手动）: 玩家按 F → input_controller.revive_pressed → entity._on_bridge_revive_pressed → revive()

B 先于 A 到期: B 的 revive() 成功（dead→revive）→ revived 广播 → 编排器 _on_entity_revived 取消 pending
             → A 到期时 _armed=false，不再二次调 revive()（无重复广播）
A 先触发:     A 的 revive() 成功 → 玩家再按 F → revive() 同态重入 → restart 钩子静默返回（无 state_changed 二次广播）
结论: 两路径经 revive() 幂等收敛，任何时序下 revived/died 均恰一次（T15/T16 锁定）
```

### Flow 3：第二次死亡终态（AC3 / SW-015 契约）

```
take_damage (hp_2 ≤ 0, active_life=2)
  → die(): _is_final_dead=true → emit died(entity, final=true) → request_transition("dead") 终态停摆
  → ReviveOrchestrator._on_entity_died(true): final==true → 不启动计时（SW-015 契约消费方）
  → 后续 revive() 被拒（push_warning + no-op，#575 已实现）——编排器不重试不死循环（单次信号驱动）
  → SW-015（未来 issue）订阅 died(final=true) 进入失败判定
```

## 6. 边界与错误处理

| # | 边界情况 | 缓解 |
|---|---------|------|
| 1 | F 键手动 vs 自动编排竞争 | revive() 幂等收敛 + `_on_entity_revived` 取消 pending（Flow 2；T15/T16） |
| 2 | 敌人（life_total=1）误绑 | bind_player 只接受 is_player==true 实体；died(final=true) 不启动计时（T4/T8） |
| 3 | 实体在计时期间销毁/场景切换 | 到期回调 `is_instance_valid(_player)` 守卫 + unbind 清 pending（T17/T18） |
| 4 | headless / 无 FX 节点环境 | trigger() 内节点判空防御（_ink_burst/_flash_layer null 时 no-op 不崩溃，T20） |
| 5 | FX texture 生成失败 | _build_ink_texture() 返回 null → GPUParticles2D 默认方形粒子降级，不阻塞 trigger（T21） |
| 6 | 慢动作重叠触发 | _slowmo_set 防嵌套——仅首次设置 time_scale，末次到期恢复 1.0（T22） |
| 7 | 闪屏与 #582 冷月光并存 | 瞬态节点与常驻色温节点分离；Tween 结束复原自身 color 零残留（T12） |
| 8 | 无敌闪烁期间视觉根节点被释放 | `_process` 内 is_instance_valid(_visual_root) 守卫，失效即停（T17 同族） |
| 9 | 编排器重复 bind | 幂等：先 disconnect 旧实体信号再订阅新实体（T19） |
| 10 | dead 停摆期再次受击 / revive 期间受击 | #575 take_damage dead/revive 态 no-op + #577 判定器无敌期 no-op 双保险（回归） |

## 7. 挂载约定（#585 组装契约）

| 场景 | 组件 | 挂载 | 配置 | 归属 |
|------|------|------|------|------|
| 战斗场景（未建，#585 组装） | ReviveOrchestrator | root 子节点 | `orchestrator.bind_player(player_entity)` | #585 |
| 战斗场景（未建，#585 组装） | ReviveFX | root 子节点（**后挂/高 layer**，覆盖 #582 常驻色温之上） | `fx.bind_player(player_entity)` + `fx.bind_player_visual(player/StickFigure)` | #585 |
| `scenes/e2e_stick_figure_capture.tscn` | ReviveFX | CaptureRig 子节点 | REVIVE 态进入 → `fx.trigger()`（AC5 证据路径） | #637 已交付 |
| `scenes/Main.tscn` | — | **不挂载** | 标题场景红线（#572） | — |

> 两组件均自包含（new + bind 即生效，零场景依赖）；#585 只做「add_child + bind_player + bind_player_visual」三行接线。

## 8. 测试覆盖（test_revive_orchestrator.gd，run_tests.gd 第 10 套件）

24 用例分 7 场景：A 编排主路径（died(false) 契约恰一次/1s 自动复活 state 序列 dead→revive→idle/未到期不复活/敌人不误绑）、
B 复活后无敌 + 架势清空（stance==0/无敌期双伤害 no-op/无敌到期恢复）、C SW-015 终态契约（died(final=true) 恰一次 + revive 被拒 + 编排器不误启）、
D FX 演出（节点存在 + 零字面量断言/墨点 one_shot/闪屏复原无残留/慢动作恢复/闪烁谷值采样）、E 双路径兼容（F 先于自动 / 自动先于 F，revived 恰一次）、
F 边界失败（实体销毁守卫/unbind/重复 bind/FX 节点缺失/texture 生成失败/慢动作重叠）、G 回归基线（test_combat_entity e1-e6 零改动 + 全量 10 套件全绿）。

## 9. 明确不修改（与 PRD/DESIGN 红线对齐）

- ❌ 不改 combat_entity.gd / combat_state_table.gd / combat_states.gd（#575 契约只读：die/revive 接口、dead→revive 转移、revive 态自动退出、无敌机制全部零改动）
- ❌ 不在编排器/FX 中重写 hp/架势/无敌逻辑（#575 注释三处预留的「#578 接管/驱动/契约」= 消费信号 + 调用 revive()，禁止语义复制）
- ❌ 不裁决 # DRAFT 数值（REVIVE_SECONDS 等只读；新 FX 分区 12 常量同样标 # DRAFT 候选集，定稿归 #584）
- ❌ 不修改 scenes/Main.tscn（标题场景红线，#572）；游戏内挂载接线归 #585 组装
- ❌ 不做失败场景/失败结算（SW-015 职责；本层只保证并文档化 died(final=true) 事件契约）
- ❌ 不做氛围层（#582 职责：常驻色温/雪幕/水墨晕染/低血 vignette；本层闪屏为瞬态演出节点，分离共存）
- ❌ 不重做动画（#574 职责：anim_revive/anim_dead 动画位已交付，本层仅触发状态流转）
- ❌ 不修改 mini-pong/ 任何文件（游戏隔离红线）
