# Design: [Feature] 两条命原地复活系统

> **Parent Issue:** #578
> **Agent:** game-plan-agent
> **Date:** 2026-08-20
> **Approach:** PRD §4 **方案 A 全采纳** —— ① 复活编排 = 独立 ReviveOrchestrator（监听 `died(final=false)` → REVIVE_SECONDS 计时 → `entity.revive()`，与 F 键输入桥双路径兼容）；② 墨点 burst = GPUParticles2D one_shot；③ 闪屏 = 瞬态 CanvasModulate Tween；④ 慢动作 = `Engine.time_scale` 短促降速。两处实现细节裁决（见附：风险裁决点）：计时器选自管理 `_process(delta)` 累加（保 headless 确定性，PRD 方案 A 明言「SceneTreeTimer/自管理计时器」二选一）、无敌闪烁用**父节点 modulate 传播**（替代逐 Line2D 遍历，原子且省遍历）
> **Reference PRD:** `docs/PRD/578-two-life-revive.md`（research PR #635 已合并 2026-08-20）
> **上游方案:** `docs/DESIGN/575-combat-entity-state-machine.md`（die/revive 接口 + died/revived 信号 + dead→revive 转移 + `_invincible_until_sec` + 输入桥预留位）；`docs/DESIGN/577-parry-clash-stance-break.md`（判定器无敌期 no-op 双保险）；`docs/DESIGN/574-stick-figure-silhouette-animation.md`（anim_revive/anim_dead 动画位 + 骨架节点树 + 零资产代码构建模式）；`docs/DESIGN/584-combat-tuning-draft.md`（REVIVE_SECONDS / INVINCIBLE_SECONDS / SLOWMO_COEFF # DRAFT 只读）
> **所有权:** `content_ownership: mechanical`（复活编排 = 机械工程：信号订阅 + 计时 + 幂等收敛；FX 演出 = 参数化机械实现，零美术资产；演出数值全量 # DRAFT **只读不裁决**，新增 FX 分区常量同样标 # DRAFT 候选集，定稿归 #584；构图/配色情绪 = AC5 用户裁决 → docs/TASTE.md）
> **深度:** deep（PRD 标注 depth: deep；GitHub 无 depth label，参照 #581/#577 先例）—— 2 新组件 + 1 常量分区（10 常量）+ 1 测试套件 + run_tests 追加 + E2E capture 接线 → **产出 DESIGN + TASKS 文档**
> **并行上下文:** worktree 并行 —— constants.gd 为**追加式新增「复活 FX 分区」**（不触碰既有 9 分区任何常量行，与 #584 调参面板无同区改写冲突）；新文件全部独立命名（`revive_orchestrator.gd` / `revive_fx.gd` / `test_revive_orchestrator.gd`）；唯一共享文件 = `tests/run_tests.gd`（追加一行 `_run()`；当前唯一 open PR #613 为 impl/582 雪夜氛围，不涉及 run_tests.gd，无并发改写）

---

## 1. 架构总览

**问题本质是「机械层 100% 就绪，『谁计时驱动』与『演出长什么样』双缺」。** shandong-wolf 经 #575/#577/#574/#584 已交付复活全链路原料：CombatEntity.die() 两段血语义（active_life=1 且 life_total=2 → `died(self, false)` 可复活死）、revive() 全部机械语义（hp_2=50 独立接管、架势清空、`_invincible_until_sec` 无敌开启、dead→revive 转移 + revived/hp_changed/stance_changed 广播）、11 态转移表 dead→[revive] 停摆拓扑、revive 态 REVIVE_SECONDS 后自动回 idle、anim_revive/anim_dead 动画位、REVIVE_SECONDS/INVINCIBLE_SECONDS/SLOWMO_COEFF 常量。但 `gdscripts/` 无任何自动复活驱动：`died(self, false)` 信号**无人监听计时**（当前只有 F 键手动路径 `revive_pressed` → `_on_bridge_revive_pressed`，注释明言「自动路径由 #578 监听 died(final=false) 计时后调 revive()」）；`scenes/Main.tscn` 零 CanvasModulate、零 GPUParticles2D——复活 FX 层零存在。**本 issue 交付 = 复活编排器（机械驱动）+ 复活 FX（演出层）+ SW-015 契约固化，是 #585 组装（战斗闭环）的最后一个机械组件。**

**设计哲学：消费信号不修改实体、编排与演出双层解耦、双路径幂等收敛、headless 确定性、演出全参数化、瞬态与常驻解耦。**

1. **消费信号不修改实体（红线）**：#575 代码注释三处预留（`die()`「#578 接管」、`revive()`「#578 驱动」、combat_states revive 态「#578 契约」）——本 issue **零修改** combat_entity.gd / combat_state_table.gd / combat_states.gd，所有机械语义已在 #575 交付，本层只做「订阅信号 + 计时 + 调 revive()」。禁止在编排器/FX 中重写 hp/架势/无敌逻辑。
2. **编排与演出双层解耦**：ReviveOrchestrator（机械层：谁在 1s 后调 revive()）与 ReviveFX（演出层：墨点/闪屏/慢动作/闪烁）**各自独立订阅实体信号**——编排器订阅 `died(final=false)`，FX 订阅 `revived`。单向数据流：entity 信号 → 两个消费者；两组件之间零耦合（FX 不依赖编排器，编排器不管演出），可分别 headless 单测。
3. **双路径幂等收敛**：F 键手动路径（输入桥 `revive_pressed` → entity.revive()，#573/#575 已交付）与自动路径（编排器计时 → entity.revive()）在 `revive()` 处收敛——dead 停摆只允许 revive 出 + 同态重入 restart 钩子静默返回 = 天然防双触发；编排器再加**计时取消**（收到 `revived` 即取消 pending），彻底消除竞争窗口。
4. **headless 确定性**：编排器计时用 `_process(delta)` 累加（与 test_combat_entity.gd `_advance()` 手动推进模式一致），不依赖 SceneTreeTimer——测试同步推进、CI 无渲染/无树依赖。
5. **演出全参数化 + 零字面量**：FX 全部参数（墨点数量/速度/生命周期/颜色、闪屏色值/时长、慢动作时长、闪烁频率/最低 alpha）进 constants.gd 新增「复活 FX 分区」# DRAFT，FX 代码零硬编码。
6. **瞬态与常驻解耦**：闪屏 CanvasModulate 为**瞬态演出节点**（Tween 白→血→复原，结束恢复自身默认 color），与 #582 常驻冷月光 CanvasModulate **节点分离共存**，互不覆盖 color——瞬态节点挂载层级约定见 §6。

```
                    ★ Issue #578 本设计（shandong-wolf 复活编排 + 演出层）
┌──────────────────────────────────────────────────────────────────────────────┐
│ 新建（3 文件，全部 shandong-wolf/ 下）                                          │
│  gdscripts/revive_orchestrator.gd   ReviveOrchestrator（Node）                 │
│                                     —— 监听 died(final=false) → 1s 计时 → revive() │
│  gdscripts/revive_fx.gd             ReviveFX（Node2D，_ready 代码构建子节点）    │
│                                     —— 墨点 burst + 闪屏 + 慢动作 + 无敌闪烁      │
│  tests/test_revive_orchestrator.gd  AC1-AC5 主路径 + 双路径竞争 + SW-015 契约 + 回归 │
├──────────────────────────────────────────────────────────────────────────────┤
│ 修改（4 文件，全部 additive，不动任何既有接口/信号/转移/裁决）                     │
│  gdscripts/constants.gd                  追加「复活 FX 分区」10 个 # DRAFT 常量（§3.2）│
│  tests/run_tests.gd                      追加一行 _run(test_revive_orchestrator)   │
│  scenes/e2e_stick_figure_capture.tscn    挂 ReviveFX 节点（P1，AC5 证据路径）       │
│  gdscripts/e2e_stick_figure_capture.gd   REVIVE 态进入时调 fx.trigger()（additive） │
├──────────────────────────────────────────────────────────────────────────────┤
│ 消费方（0 改动，后续 issue 挂接）                                               │
│  #575 CombatEntity ──► died(final=false)/revived 信号（本 issue 唯一数据源）     │
│  #573/#575 输入桥   ──► revive_pressed → revive() 手动路径（并行，不改）          │
│  #585 组装          ──► 编排器 + FX 挂载战斗场景 + bind 接线（§6 约定）           │
│  #582 雪夜氛围      ──► 瞬态闪屏 CanvasModulate 与常驻色温节点分离共存            │
│  SW-015 结局失败    ──► died(final=true) 事件契约（§7 契约表）                    │
│  AC5 E2E            ──► e2e_shots.json REVIVE shot 复用 + FX 接线（P1）          │
└───────────────────────────────────┬──────────────────────────────────────────┘
                                    ▼
        entity.take_damage (hp_1 ≤ 0, life_total=2)
            │ die(): emit died(entity, final=false) + dead 态
            ▼
   ┌──────────────────┐        ┌──────────────────┐
   │ ReviveOrchestrator│        │   ReviveFX       │
   │  _on_died(false)  │        │  _on_revived()   │
   │  计时 REVIVE_SEC  │        │  trigger()       │
   │  到期 → revive()  │◄───────┤  墨点/闪屏/慢动作/闪烁│
   └──────────────────┘  revived│──────────────────┘
            │                    │
            ▼                    ▼
   entity.revive(): hp_2=50 接管 · stance=0 · 无敌 1s · dead→revive → revive 态 1s 后自动 idle
```

### 1.1 既有实现状态（Prior Implementation Status，plan agent 已逐条核实 origin/main dfac218）

| 文件 | 状态 | 核实结论 |
|------|:----:|---------|
| `gdscripts/combat_entity.gd` | ✅ #575/#618 | `die()` 两段血语义完整；`revive()` 机械语义完整；`revive()` 唯一调用点 = `_on_bridge_revive_pressed`（F 键），注释明言「自动路径由 #578 监听 died(final=false) 计时后调 revive()」——**与 PRD §1.1 逐字一致** |
| `gdscripts/combat_state_table.gd` | ✅ #575/#618 | `dead → [revive]` 停摆拓扑 + `revive → [idle]`，转移表 121 对与测试镜像一致 |
| `gdscripts/combat_states.gd` | ✅ #575/#618 | CombatStateRevive 累计 REVIVE_SECONDS 自动退出 → idle（注释「hp_2 初始化/无敌开启在 entity.revive() 完成，#578 契约」）；CombatStateDead 停摆不自动退出 |
| `gdscripts/constants.gd` | ✅ #584/#609 | REVIVE_SECONDS=1.0 / INVINCIBLE_SECONDS=1.0 / LIFE_TOTAL=2 / LIFE_1_MAX=100 / LIFE_2_ABS=50 / SLOWMO_COEFF=0.2 / HUD_MOON_WHITE=#e8e6e3 / HUD_INK_BLACK=#141414 均在；**缺复活 FX 专用常量**（无 INK_*/FLASH_*/SLOWMO_HOLD_*/INVINCIBLE_FLICKER_*） |
| `gdscripts/input_controller.gd` | ✅ #573/#612 | `signal revive_pressed` + `game_revive` 输入动作存在，F 键手动路径已接通 |
| `gdscripts/stick_figure_anim_states.gd` | ✅ #574/#612 | `ANIM_CLIP_NAMES` 含 `"revive": "anim_revive"` / `"dead": "anim_dead"`；consume_state 播放（166/173 行）——动画位就绪，本 issue 不做动画 |
| `scenes/Main.tscn` | ✅ #572 | 纯标题场景（CanvasLayer layer=1 + 3 Label）；**零 CanvasModulate、零 GPUParticles2D**——FX 层零存在，与 PRD 一致 |
| `scenes/e2e_stick_figure_capture.tscn` + `gdscripts/e2e_stick_figure_capture.gd` | ✅ #574 | CaptureRig 轮询 current_state + auto_cycle 12 态；REVIVE=10 / DEAD=11 shot 已配置——E2E 机制可拍复活瞬间 |
| `tests/test_combat_entity.gd` | ✅ #575 | e1-e6 已覆盖：died(false)→revive 流程、无敌期 999 no-op、life_total=1 终态、终态拒复活、state 序列——**无编排器计时路径测试**（无「died 后 1s 自动 revive」用例） |
| `tests/run_tests.gd` | ✅ #572+ | 9 套件挂载（StateMachine/Constants/StickFigureAnimation/InputController/PlayerController/DebugCanvas/CombatEntity/CombatJudge/Hud），`_run()` 模式追加 |
| `e2e_shots.json` | ✅ #574 | 12 态含 REVIVE(10)/DEAD(11)，AC5 直接复用 |

**缺口确认（PRD 断言 vs 实测，全部吻合）：**

| PRD 断言 | 实测 | 设计处置 |
|---------|------|---------|
| `revive()` 只被输入桥 F 键路径调用 | ✅ 确认（`_on_bridge_revive_pressed` 唯一调用点） | 编排器 = 第二调用方（自动路径），两者经 revive() 幂等收敛 |
| Main.tscn 零 CanvasModulate / 零 GPUParticles2D | ✅ 确认 | FX 层全新构建，零场景依赖（_ready 代码建节点，对齐 stick_figure.gd 零资产模式） |
| constants.gd 缺复活 FX 专用常量 | ✅ 确认（grep 无 INK_*/FLASH_*/SLOWMO_HOLD_*/INVINCIBLE_FLICKER_*） | §3.2 追加「复活 FX 分区」10 常量（# DRAFT） |
| 无编排器计时路径测试 | ✅ 确认（test_combat_entity.gd 无 timer 用例） | §9 Scenario A-E 新增 24 用例描述（测试代码归 implement） |
| e2e_shots.json REVIVE shot 可复用 | ✅ 确认（state 10 + auto_cycle） | AC5：capture rig 挂 FX + REVIVE 态 trigger（§3.3，additive） |

---

## 2. 新组件详细设计

### 2.1 ReviveOrchestrator（`shandong-wolf/gdscripts/revive_orchestrator.gd`，新增）

- **File:** `shandong-wolf/gdscripts/revive_orchestrator.gd`
- **Class:** `class_name ReviveOrchestrator extends Node`
- **Node structure:** 自包含脚本节点，无子节点；#585 组装期挂到战斗场景 root（`add_child` 即生效，零配置）

```
ReviveOrchestrator (Node, script=revive_orchestrator.gd)
└── （无子节点；依赖注入：bind_player(entity) 持有 CombatEntity 引用）
```

- **State Properties:**

| 变量 | 类型 | 初值 | 说明 |
|------|------|------|------|
| `_player` | Object (CombatEntity) | `null` | 绑定的玩家实体（bind_player 注入；只绑玩家，禁止误绑敌人） |
| `_armed` | bool | `false` | 计时进行中标志（died(false) 置位，revived/unbind/到期 清除）——防重入 + 供测试断言 |
| `_elapsed` | float | `0.0` | 自管理计时累加（_process(delta) 推进，headless 可手动驱动） |

- **Signals:** 无输出信号（只消费 entity 信号；可观测性由 `is_armed()` 提供）
- **Key Methods:**

```gdscript
func bind_player(entity: Object) -> void:
    ## 幂等接线: 先解绑旧实体（若已绑），再订阅新实体 died/revived 信号
    ## 只接受 is_player==true 且 life_total==2 的实体（敌人 life_total=1 永不绑定，边界 4）
    if _player != null:
        _player.disconnect("died", _on_entity_died)      # 旧实体解绑（防泄漏）
        _player.disconnect("revived", _on_entity_revived)
    _player = entity
    _armed = false; _elapsed = 0.0
    if entity == null: return
    entity.died.connect(_on_entity_died)
    entity.revived.connect(_on_entity_revived)

func unbind_player() -> void:
    ## 场景切换/实体销毁前调用（#585 组装约定）: 解绑 + 清 pending
    bind_player(null)

func _on_entity_died(ent: Object, final: bool) -> void:
    ## 自动复活路径唯一入口: 仅 final=false（第一条血耗尽）且为绑定实体 → 启动计时
    ## final=true（第二条血耗尽/life_total=1）不启动——SW-015 终态由契约消费（§7）
    if ent != _player or final: return
    if _armed: return                          # 防重入（died 天然单次，双保险）
    _armed = true; _elapsed = 0.0

func _on_entity_revived(ent: Object) -> void:
    ## 幂等收敛钩子: F 键手动 revive() 先触发时，取消自动 pending——
    ## 消除双路径竞争窗口（边界 3），revived 只发一次，天然单次
    if ent == _player:
        _armed = false; _elapsed = 0.0

func _process(delta: float) -> void:
    ## 自管理计时（PRD 方案 A「SceneTreeTimer/自管理计时器」二选一，裁决取后者:
    ## headless 确定性——测试经 _process(1/60) 同步推进，零树依赖）
    if not _armed or _player == null: return
    _elapsed += delta
    if _elapsed >= float(C.REVIVE_SECONDS):
        _armed = false; _elapsed = 0.0
        if is_instance_valid(_player):
            _player.revive()                   # 唯一驱动点；终态/life_total<2 时 revive() 内部 no-op + push_warning（失败路径 2）
```

- **Integration notes:**
  - 与 F 键输入桥并行：两者都调 `entity.revive()`；dead 停摆只允许 revive 出 + 同态重入 restart 静默返回 = 天然防双触发；编排器 `_on_entity_revived` 取消 pending 收窄竞争窗口。
  - headless 测试：`new()` + `bind_player(e)` + 手动 `_process(delta)` 推进（对齐 test_combat_entity.gd `_advance()` 模式）；实体销毁守卫 `is_instance_valid`。
  - **SW-015 契约（AC3 证据，PRD §4.3 输出固化于此）：**

| 事件 | 参数 | 语义 | 消费者 |
|------|------|------|--------|
| `died(entity, false)` | final=false | 可复活死：第一条血耗尽（life_total=2 玩家），编排器计时 1s 后 revive() | 本 issue ReviveOrchestrator |
| `died(entity, true)` | final=true | 终态：第二条血耗尽（life_total=2）或任意 life_total=1 实体，`_is_final_dead` 置位、revive() 被拒 | SW-015 结局与失败结算（未来 issue） |

### 2.2 ReviveFX（`shandong-wolf/gdscripts/revive_fx.gd`，新增）

- **File:** `shandong-wolf/gdscripts/revive_fx.gd`
- **Class:** `class_name ReviveFX extends Node2D`
- **Node structure:** `_ready()` 代码构建全部子节点（**零 tscn / 零美术资产**，对齐 stick_figure.gd 模式；headless 可 new + add 到树断言节点存在）：

```
ReviveFX (Node2D, script=revive_fx.gd)
├── InkBurst (GPUParticles2D)      # one_shot 墨点 burst（30-50 黑点，径向扩散）
└── FlashLayer (CanvasModulate)    # 瞬态闪屏（白 #e8e6e3 → 血 #5a1e1e → 复原）
    # 无敌闪烁目标 = bind_player_visual() 注入的 StickFigure 根节点（modulate.a 循环，父节点传播到全部 Line2D 子肢体）
    # 慢动作 = Engine.time_scale 全局短促降速（无节点）
```

- **State Properties:**

| 变量 | 类型 | 初值 | 说明 |
|------|------|------|------|
| `_entity` | Object (CombatEntity) | `null` | 绑定实体（bind_player 注入，订阅 revived） |
| `_visual_root` | Node2D | `null` | 玩家剪影根节点（bind_player_visual 注入，无敌闪烁 modulate 目标） |
| `_flash_layer` | CanvasModulate | `null` | _ready 构建（get_node_or_null 防御） |
| `_ink_burst` | GPUParticles2D | `null` | _ready 构建 |
| `_flicker_elapsed` | float | `0.0` | 无敌闪烁相位累加（_process 驱动） |
| `_flicker_active` | bool | `false` | revived 置位，INVINCIBLE_SECONDS 到期清除 |
| `_slowmo_until_sec` | float | `0.0` | 慢动作截止时间戳（Time.get_ticks_msec()/1000.0 比较，与 #575 无敌机制同源） |
| `_slowmo_set` | bool | `false` | 本组件是否设置过 time_scale（仅设置者恢复，防覆盖他人，边界 8） |

- **Signals:** 无（单向消费 revived）
- **Key Methods:**

```gdscript
func bind_player(entity: Object) -> void:
    ## 订阅 revived → trigger()（编排器/FX 各自独立订阅，零耦合）
    if _entity != null:
        _entity.disconnect("revived", _on_entity_revived)
    _entity = entity
    if entity != null:
        entity.revived.connect(_on_entity_revived)

func bind_player_visual(root: Node2D) -> void:
    ## 注入无敌闪烁目标（#585 组装传 Player/StickFigure 根节点；#574 骨架根节点 modulate
    ## 传播到全部 Line2D 子肢体——替代逐 Line2D 遍历，原子且零遍历成本，裁决点 3）
    _visual_root = root

func _on_entity_revived(ent: Object) -> void:
    if ent == _entity:
        trigger()

func trigger() -> void:
    ## 演出四件套（全部参数读 constants，零字面量；各节点缺失时降级不崩溃）
    _ink_burst.emitting = true                       # ① 墨点 one_shot burst
    _start_flash_tween()                             # ② 瞬态 CanvasModulate 闪屏
    _start_slowmo()                                  # ③ Engine.time_scale 短促降速
    _flicker_active = true; _flicker_elapsed = 0.0   # ④ 无敌闪烁（modulate.a 循环）

func _start_flash_tween() -> void:
    ## 白 → 血（FLASH_SECONDS）→ 停留（FLASH_HOLD_SECONDS）→ 复原（FLASH_SECONDS）
    ## 瞬态语义: Tween 结束必须恢复自身默认 color（白=恒等），不残留覆盖 #582 常驻色温（红线）
    var tween = create_tween()
    tween.tween_property(_flash_layer, "color", C.FLASH_BLOOD, C.FLASH_SECONDS)
    tween.tween_interval(C.FLASH_HOLD_SECONDS)
    tween.tween_property(_flash_layer, "color", Color.WHITE, C.FLASH_SECONDS)

func _start_slowmo() -> void:
    ## 全局 time_scale 短促降速（复用 SLOWMO_COEFF=0.2，与 #577 处决慢动作同源节奏语言）
    ## clamp 下限 0.1 防冻结（#584 注释既有约束）；重叠触发防嵌套: 仅首次设置 _slowmo_set
    if not _slowmo_set:
        Engine.time_scale = C.SLOWMO_COEFF
        _slowmo_set = true
    _slowmo_until_sec = Time.get_ticks_msec() / 1000.0 + float(C.SLOWMO_HOLD_SECONDS)

func _process(delta: float) -> void:
    ## 无敌闪烁: modulate.a = lerp(1.0, ALPHA_MIN, |sin(2π·HZ·t)|) 循环；
    ## INVINCIBLE_SECONDS 到期复原 1.0（硬汉第二次机会可读性，禁止残留半透明）
    if not _flicker_active or _visual_root == null:
        return
    _flicker_elapsed += delta
    if _flicker_elapsed >= float(C.INVINCIBLE_SECONDS):
        _flicker_active = false
        _visual_root.modulate.a = 1.0
        return
    var phase: float = _flicker_elapsed * float(C.INVINCIBLE_FLICKER_HZ) * TAU
    _visual_root.modulate.a = lerpf(1.0, C.INVINCIBLE_FLICKER_ALPHA_MIN, absf(sin(phase)))

func _build_ink_texture() -> Texture2D:
    ## 程序化 8x8 圆点 texture（零美术资产；失败 → null → GPUParticles2D 退化为默认方形粒子，不阻塞 trigger）
    ## Image.create(8, 8) → 画实心圆 → ImageTexture.create_from_image；try/异常兜底返回 null
    pass  # 实现细节归 implement agent（DESIGN §2.2 契约: 返回 Texture2D 或 null）
```

- **Integration notes:**
  - **墨点 burst（PRD §4.2 方案 A）**：GPUParticles2D `one_shot=true`、`amount=INK_BURST_COUNT`、`lifetime=INK_BURST_LIFETIME`、径向扩散（spread 180° 或方向速度 + 随机）、`color=INK_COLOR`；发射位置 = 玩家脚底/刀尖（`global_position` 取自 _visual_root，impl 期定锚点，实验 1 定参）。
  - **闪屏（PRD §4.3 方案 A）**：独立 CanvasModulate 瞬态节点；与 #582 常驻冷月光 CanvasModulate **节点分离**（各自 color 互不覆盖）；挂载层级约定 §6（瞬态节点后挂/高 layer 覆盖，Tween 复原后无残留）。
  - **慢动作（PRD §4.4 方案 A）**：全局 time_scale，时长 SLOWMO_HOLD_SECONDS（实验 3 定参）；影响敌人 AI/粒子 0.4s 内可接受，clamp 下限 0.1。
  - **无敌闪烁（PRD §4.3 方案 A）**：父节点 modulate 传播（裁决点 3）——`_visual_root` 即 PlayerStickFigure/StickFigure 根，其 modulate.a 变化自动作用于全部 Line2D 肢体 + Polygon2D 头。
  - **headless**：节点缺失时 `trigger()` 内 get_node_or_null 防御（边界 6）；测试断言节点存在 + 参数来自 constants（零硬编码）。

---

## 3. 既有组件修改

### 3.1 文件清单

**新文件：**

| 文件 | 内容 | 归属 |
|------|------|------|
| `shandong-wolf/gdscripts/revive_orchestrator.gd` | 复活编排器（§2.1） | 本 issue |
| `shandong-wolf/gdscripts/revive_fx.gd` | 复活演出层（§2.2） | 本 issue |
| `shandong-wolf/tests/test_revive_orchestrator.gd` | §9 Scenario A-G 24 用例描述落地 | 本 issue（测试代码归 implement） |

**修改文件（全部 additive）：**

| 文件 | 变更 | 为什么 |
|------|------|--------|
| `shandong-wolf/gdscripts/constants.gd` | 追加「复活 FX 分区」10 常量（§3.2，全 # DRAFT） | 演出全参数化红线：FX 代码零字面量 |
| `shandong-wolf/tests/run_tests.gd` | 追加 `_run("res://tests/test_revive_orchestrator.gd", "ReviveOrchestrator")` | 挂载新套件（现有模式逐字对齐） |
| `shandong-wolf/scenes/e2e_stick_figure_capture.tscn` | 挂 ReviveFX 节点（子节点）+ 接线（§3.3） | AC5 证据路径：E2E 截图含 FX 才能提交用户裁决 |
| `shandong-wolf/gdscripts/e2e_stick_figure_capture.gd` | REVIVE 态进入时调 `fx.trigger()` + `bind_player_visual`（additive 钩子） | 同上 |

**删除/弃用文件：** 无

**受影响测试文件：** `tests/test_combat_entity.gd` **不改**（e1-e6 已是实体语义回归基线，本 issue 零改动实体；编排器计时路径进新套件）。

### 3.2 constants.gd 复活 FX 分区（# DRAFT，10 常量，全部「issue body/只狼基准 → 候选 + 影响 + 情感断言」注释，定稿归 #584）

| 常量 | 默认值 | 候选集 | 来源/基准 | 影响 |
|------|--------|--------|-----------|------|
| `INK_BURST_COUNT` | 40 | [30, 40, 50] | issue body「30-50 黑点」 | 墨点密度——太少无爆开感，太多粘连成雾（实验 1） |
| `INK_BURST_SPEED` | 180.0 | [120, 180, 240] | 实验 1 候选（径向 px/s） | 扩散速度——太慢成黑雾，太快成烟火（实验 1） |
| `INK_BURST_LIFETIME` | 0.4 | [0.3, 0.4, 0.5] | PRD §4.2「0.3-0.5s」 | 粒子存活——0.4s 内淡出，快速衰减不粘连（实验 1） |
| `INK_COLOR` | Color("#141414") | —（= HUD_INK_BLACK 同值互引） | issue body「墨色」 | 墨点色——墨黑，禁止彩色粒子（反页游） |
| `INK_BURST_SPREAD_DEG` | 180.0 | [120, 180, 360] | 径向爆开语义 | 发射张角——180° 半球爆开（脚底发射），360° 全向（实验 1） |
| `FLASH_WHITE` | Color("#e8e6e3") | —（= HUD_MOON_WHITE 同值互引） | issue body「白 #e8e6e3」 | 闪屏起始色——苍白月白（复用 HUD 色值，零新色相） |
| `FLASH_BLOOD` | Color("#5a1e1e") | —（issue body 指定） | issue body「血 #5a1e1e」 | 闪屏目标色——偏暗红不发亮（禁警报红，实验 2） |
| `FLASH_SECONDS` | 0.2 | [0.1, 0.2, 0.3] | issue body「0.2s 内」 | 闪白→血色时长——≤0.2s 短促（实验 2） |
| `FLASH_HOLD_SECONDS` | 0.2 | [0.2, 0.3] | 实验 2 候选 | 血色停留——克制停留 0.2-0.3s，不拖沓（实验 2） |
| `SLOWMO_HOLD_SECONDS` | 0.4 | [0.3, 0.4, 0.5] | 实验 3 候选（复用 SLOWMO_COEFF=0.2） | 全局降速时长——0.4s 足够读清「刀尖点地」帧（实验 3） |
| `INVINCIBLE_FLICKER_HZ` | 8.0 | [6, 8, 10] | 实验 4 候选 | 闪烁频率——8Hz 呼吸感可读，<10Hz 安全区（实验 4） |
| `INVINCIBLE_FLICKER_ALPHA_MIN` | 0.3 | [0.2, 0.3, 0.4] | 实验 4 候选 | 闪烁谷值——0.3 可读不刺眼（实验 4） |

> 注释格式对齐既有分区（#584 范本）：每常量带「issue body/基准 → 候选 + 该值影响什么 + 情感断言」四行注释；`# DRAFT` 标记 + 定稿归 #584。

### 3.3 e2e capture 接线（additive，AC5 证据路径）

```gdscript
## e2e_stick_figure_capture.gd（additive 钩子，不动 auto_cycle 既有逻辑）
# ① _ready: 构建 ReviveFX 节点（或 tscn 内挂子节点）+ bind_player_visual(Player/StickFigure)
# ② 状态进入 REVIVE（state == 10）时: fx.trigger()（同步墨点/闪屏/慢动作/闪烁到截图帧）
# ③ 其他 11 态: FX 节点 inert（emitting=false、modulate 恒等、time_scale 不触发）
```

- 目的：`e2e_shots.json` 的 REVIVE shot 复用（state 10），截图含 FX 才能提交 AC5 用户裁决（『硬汉再起』 vs 『日式中二觉醒』）。
- **红线**：`scenes/Main.tscn`（标题场景）**不修改**；capture 场景是测试 harness，挂 FX 属于测试证据路径，非游戏组装——游戏内挂载归 #585（§6 约定）。

---

## 4. 数据流

### Flow 1：自动复活正常路径（AC1/AC4）

```
take_damage (hp_1 ≤ 0, life_total=2)
  → die(): emit died(entity, final=false) → request_transition("dead") → anim_dead 倒地（1s）
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

竞争窗口处理:
  B 先于 A 到期:  B 的 revive() 成功（dead→revive）→ revived 广播 → 编排器 _on_entity_revived 取消 pending
                 → A 到期时 _armed=false，不再二次调 revive()（无重复广播）
  A 先触发:       A 的 revive() 成功 → 玩家再按 F → revive() 同态重入 → restart 钩子静默返回
                 （revive 态无 restart 实现 → request_transition 同态路径静默 true，无 state_changed 二次广播）
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

### Flow 4：失败/边界路径

```
a) 计时期间实体销毁/场景切换: _process 到期回调 is_instance_valid(_player)==false → 静默跳过（不崩溃）
b) FX 节点缺失（headless/未挂载）: trigger() 内 get_node_or_null 防御 → 墨点/闪屏 no-op，复活主链路不受阻
c) 慢动作重叠（两次 revive < SLOWMO_HOLD_SECONDS）: _slowmo_set 防嵌套——仅首次设置，末次恢复 1.0
d) 墨点 texture 生成失败: _build_ink_texture() 返回 null → GPUParticles2D 默认方形粒子（降级），不阻塞 trigger
```

---

## 5. 边界情况与错误处理

| # | 边界情况 | 缓解 |
|---|---------|------|
| 1 | dead 停摆期再次受击 | #575 take_damage 在 dead 态 no-op + #577 判定器跳过 dead/revive/execute 实体（双保险，回归测试 T24） |
| 2 | revive 期间再次受击 | #575 take_damage/take_stance_damage 在 revive 态 no-op（回归测试 T6） |
| 3 | F 键手动 vs 自动编排竞争 | revive() 幂等收敛 + 编排器 `_on_entity_revived` 取消 pending（Flow 2；T15/T16） |
| 4 | 敌人（life_total=1）误绑 | `bind_player` 只接受 is_player==true 实体；died(final=true) 不启动计时（T4/T8） |
| 5 | 闪屏与 #582 冷月光并存 | 瞬态 CanvasModulate 与常驻色温节点分离；Tween 结束恢复自身默认 color，不残留覆盖（T12；§6 挂载层级） |
| 6 | headless / 无 FX 节点环境 | trigger() get_node_or_null 防御；测试纯逻辑断言（T20） |
| 7 | REVIVE_SECONDS 与 anim_dead 时长对齐 | 倒地动画 clip 时长应 ≥1s 覆盖复活窗口（impl 期核对 #574 参数，非本 issue 改动） |
| 8 | 慢动作影响全局 | time_scale 0.2 持续 0.4s 内敌人 AI/粒子同步降速（可接受，实验 3 验证；clamp 下限 0.1；_slowmo_set 防嵌套，T22） |
| 9 | 实体在计时期间被销毁/场景切换 | 回调 `is_instance_valid(entity)` 守卫 + unbind 清 pending（T17/T18） |
| 10 | FX texture 生成失败 | _build_ink_texture 返回 null → 默认粒子降级，不阻塞复活主链路（T21） |
| 11 | 编排器重复 bind | 幂等：先 disconnect 旧实体信号再订阅新实体（T19） |
| 12 | 无敌闪烁期间视觉根节点被释放 | `_process` 内 is_instance_valid(_visual_root) 守卫，失效即停（T17 同族） |

---

## 6. 每场景/每组件配置（挂载约定）

| 场景 | 组件 | 挂载 | 配置 | 归属 |
|------|------|------|------|------|
| 战斗场景（未建，#585 组装） | ReviveOrchestrator | root 子节点 | `orchestrator.bind_player(player_entity)` | #585 |
| 战斗场景（未建，#585 组装） | ReviveFX | root 子节点（**后挂/高 layer**，覆盖 #582 常驻色温之上） | `fx.bind_player(player_entity)` + `fx.bind_player_visual(player/StickFigure)` | #585 |
| `scenes/e2e_stick_figure_capture.tscn` | ReviveFX | CaptureRig 子节点 | REVIVE 态进入 → `fx.trigger()`（§3.3） | 本 issue P1（AC5） |
| `scenes/Main.tscn` | — | **不挂载** | 标题场景红线（#572）；挂载细节 #585 前不写死 | — |

> **#585 组装契约**：编排器 + FX 均为自包含组件（new + bind 即生效，零场景依赖）；#585 只做「add_child + bind_player + bind_player_visual」三行接线。impl 期**不得在 #585 之前**在 Main.tscn 或任何游戏场景写死组装细节（PRD §8 延续上下文红线）。

---

## 7. 集成点

> **状态约定:** ⬜ = 待接线（组件交付但未连到目标）；✅ = 已连接（#575/#577 已交付）。implement 须更新本表；review agent 验证 ⬜ 全部解决或显式延期。

| 集成 | 本组件 | 目标 | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| `entity.died(final=false)` → 编排器计时 | ReviveOrchestrator | #575 | 信号订阅（bind_player 内 connect） | ✅（本 issue 交付） |
| `entity.revived` → FX 演出 | ReviveFX | #575 | 信号订阅（bind_player 内 connect） | ✅（本 issue 交付） |
| `entity.revived` → 编排器取消 pending | ReviveOrchestrator | #575 | 信号订阅（双路径幂等） | ✅（本 issue 交付） |
| F 键手动复活路径 | 输入桥 `revive_pressed` → entity.revive() | #573/#575 | 已交付（本 issue 不改，回归） | ✅ |
| 无敌期判定 no-op 双保险 | CombatEntity take_damage + CombatJudge | #575/#577 | 已交付（回归测试） | ✅ |
| 无敌闪烁 modulate | FX → StickFigure 根节点 | #574 | `bind_player_visual` 节点引用（父 modulate 传播） | ✅（本 issue 交付） |
| 闪屏与 #582 常驻色温共存 | FX FlashLayer ↔ #582 CanvasModulate | #582 | 节点分离 + Tween 复原 + 挂载层级（§6） | ⬜（显式延期 #582，未合并） |
| 战斗场景挂载接线 | Orchestrator/FX → 战斗场景 | #585 | #585 组装期（new + bind 三行接线） | ⬜（显式延期 #585） |
| `died(final=true)` 契约消费 | entity → SW-015 | SW-015 | 事件契约（§2.1 契约表） | ✅（契约固化于编排器注释 + T8/T9；消费归 SW-015） |
| E2E REVIVE shot（AC5） | e2e_shots.json + capture rig + FX | 用户裁决 | 截图 + docs/TASTE.md 记录 | ✅（capture rig 已接线；用户裁决待 review 阶段） |

---

## 8. 实现阶段

| Phase | 优先级 | 组件 | 估计 |
|:-----:|:------:|------|:----:|
| Phase 1 | P0 | constants.gd 复活 FX 分区（§3.2，10 常量 # DRAFT） | 0.5h |
| Phase 2 | P0 | `revive_orchestrator.gd`（§2.1，含 SW-015 契约注释） | 0.5-1 天 |
| Phase 3 | P0 | `revive_fx.gd`（§2.2，墨点/闪屏/慢动作/闪烁 + 程序化 texture） | 1 天 |
| Phase 4 | P1 | `test_revive_orchestrator.gd`（§9 24 用例）+ run_tests.gd 追加 + e2e capture 接线（§3.3）+ 全量回归 | 1 天 |

> 依赖序：Phase 1 先行（FX 代码零字面量依赖常量）；Phase 2/3 互不依赖可并行；Phase 4 依赖 1-3。

---

## 9. 测试用例描述

> 测试代码归 implement agent（本 phase 只写描述，不写可运行测试）。套件：`tests/test_revive_orchestrator.gd`（headless 免树，new + 手动 _process 推进，对齐 test_combat_entity.gd 范本：禁 `:=` 类型推断、class_name 经 load() 访问、信号日志成员变量记录）。

### Scenario A：编排主路径（AC1）

- Test 1 首血归零信号契约：玩家（life_total=2）`take_damage(100)` → `died(final=false)` 恰一次、state_name=="dead"、hp_1==0
- Test 2 自动复活计时：`died(false)` 后编排器 `_armed==true`；手动推进 `_process(1/60)×60`（≈1.0s ≥ REVIVE_SECONDS）→ `entity.revive()` 被调 → state 序列 `dead→revive→idle`、hp_2==50.0、hp_1==0.0（第二条血独立计数，不补第一条）、`_armed==false`
- Test 3 计时未到期不复活：推进 30 帧（0.5s）→ `state_name` 仍为 "dead"、revived 未广播
- Test 4 敌人不误绑：`bind_player` 拒绝 life_total=1 实体（或绑定后 `died(final=true)` 不启动计时）→ 无 revive 调用

### Scenario B：复活后无敌 + 架势清空（AC2）

- Test 5 复活后姿态：revive 后 `stance==0.0`、`is_stance_broken==false`（#575 语义回归，编排器路径下同样成立）
- Test 6 无敌期双伤害 no-op：revive 后无敌期内 `take_damage(999)` 与 `take_stance_damage(999)` 均 no-op（hp_2/stance 不变；#577 判定器无敌期 no-op 为第二重保险，回归 test_combat_judge）
- Test 7 无敌到期恢复：`_invincible_until_sec` 过期（或手动清零）后 `take_damage(10)` → hp_2==40.0（受击恢复正常）

### Scenario C：SW-015 契约（AC3）

- Test 8 终态契约：hp_2 归零 → `died(final=true)` 恰一次、`_is_final_dead==true`、后续 `revive()` 被拒（state 保持 "dead"、revived 不广播）、编排器不再计时（`_armed==false`）
- Test 9 契约表逐项：final=false 路径可复活（T2）；final=true 路径终态（T8）——两分支互斥且覆盖 §2.1 契约表两行

### Scenario D：FX（AC4）

- Test 10 节点存在 + 零字面量：ReviveFX `_ready` 后 InkBurst（GPUParticles2D）/ FlashLayer（CanvasModulate）存在；`amount/lifetime/color/spread`、闪屏色值/时长、慢动作时长、闪烁频率/最低 alpha 全部等于 constants 对应常量（代码 review 项：FX 路径零硬编码）
- Test 11 墨点 burst：`revived` 触发 → `InkBurst.emitting==true` 且 one_shot；amount==INK_BURST_COUNT、lifetime==INK_BURST_LIFETIME、color==INK_COLOR（40 黑点基准）
- Test 12 闪屏 Tween：触发后 FlashLayer.color 从 FLASH_WHITE（#e8e6e3）→ FLASH_BLOOD（#5a1e1e，FLASH_SECONDS 内）→ 停留 FLASH_HOLD_SECONDS → 复原默认（Color.WHITE）——**断言复原无残留**（#582 共存红线）
- Test 13 慢动作：触发后 `Engine.time_scale==SLOWMO_COEFF`（0.2）；SLOWMO_HOLD_SECONDS 后恢复 1.0
- Test 14 无敌闪烁：触发后 _visual_root.modulate.a 在 [INVINCIBLE_FLICKER_ALPHA_MIN, 1.0] 区间按 INVINCIBLE_FLICKER_HZ 循环（采样 ≥3 帧验证谷值命中）；INVINCIBLE_SECONDS 到期复原 1.0

### Scenario E：双路径兼容（边界 3）

- Test 15 F 键先于自动计时：died(false) → 手动 `entity.revive()`（模拟 F 键）→ revived 广播 → 编排器取消 pending → 推进至 REVIVE_SECONDS 后**不再**二次调 revive（revived 恰一次）
- Test 16 自动先触发后手动重入：编排器计时到期 revive() 成功 → 再手动 `entity.revive()` → 同态重入静默返回（revived 恰一次、无 state_changed 二次广播）

### Scenario F：边界与失败（§5）

- Test 17 实体销毁守卫：计时期间 `entity.free()` → 推进至到期 → 回调 `is_instance_valid` 守卫静默跳过（不崩溃、无 revived）
- Test 18 unbind 后不触发：`unbind_player()` 后实体 died(false) → `_armed==false`（不启动计时）
- Test 19 重复 bind 幂等：bind A → bind B → A 的 died(false) 不触发计时（旧实体已解绑），B 的 died(false) 正常触发
- Test 20 FX 节点缺失：trigger() 在 InkBurst/FlashLayer 为 null 时 no-op 不崩溃（get_node_or_null 防御）
- Test 21 texture 生成失败：`_build_ink_texture()` 返回 null → InkBurst 无 texture 降级默认粒子，trigger 正常完成（复活链路不受阻）
- Test 22 慢动作重叠：两次 trigger 间隔 < SLOWMO_HOLD_SECONDS → time_scale 不嵌套破坏（末次到期恢复 1.0；期间保持 0.2）

### Scenario G：回归基线

- Test 23 实体语义零改动：既有 `test_combat_entity.gd` e1-e6 全绿（die/revive/无敌/终态契约逐字节不变）
- Test 24 全量回归：`godot --path shandong-wolf/ --headless --script tests/run_tests.gd` → 10 套件全绿；`smoke_test.gd` 通过

---

## 10. 验收条件映射（源自 Issue #578 body）

| # | 验收条件 | 本设计保障 | 覆盖用例 |
|---|---------|-----------|:-------:|
| AC1 | 第一条血归零时进入 revive 状态，1s 后原地复活并切至半管第二条血 | §2.1 编排器（died(false) → REVIVE_SECONDS 计时 → entity.revive()）；hp_2=50 由 #575 revive() 交付（只读消费） | T1-T3 |
| AC2 | 复活后 1s 无敌时间且架势条清空 | 复用 #575 `_invincible_until_sec`（INVINCIBLE_SECONDS）+ #577 判定器无敌期 no-op 双保险；stance=0 由 revive() 交付 | T5-T7 |
| AC3 | 第二条血归零才触发玩家死亡事件（供 SW-015 消费） | §2.1 SW-015 契约表 + 测试锁定：hp_2 归零 → died(final=true) 恰一次、_is_final_dead 置位、后续 revive() 被拒、编排器不误启 | T8-T9 |
| AC4 | 复活动画触发 GPUParticles2D 墨点 burst 与 CanvasModulate 闪屏 | §2.2 ReviveFX（墨点 one_shot + 瞬态闪屏 Tween + 慢动作 + 闪烁）；参数全部来自 constants 复活 FX 分区（零字面量） | T10-T14 |
| AC5 | E2E 截图提交用户裁决：复活瞬间画面情绪「硬汉再起」vs「日式中二觉醒」 | §3.3 capture rig 接线（REVIVE shot 复用 + FX 入镜）；裁决结果进 docs/TASTE.md（brief §校准偏好 B3 流程） | T24 + E2E |

## 11. 明确不修改（与 PRD §1.4/§8 红线对齐）

- ❌ 不改 `combat_entity.gd` / `combat_state_table.gd` / `combat_states.gd`（#575 契约只读：die/revive 接口、dead→revive 转移、revive 态自动退出、无敌机制全部零改动）
- ❌ 不在编排器/FX 中重写 hp/架势/无敌逻辑（#575 注释三处预留的「#578 接管/驱动/契约」= 消费信号 + 调用 revive()，禁止语义复制）
- ❌ 不裁决 # DRAFT 数值（REVIVE_SECONDS 等只读；新 FX 分区常量同样标 # DRAFT 候选集，定稿归 #584）
- ❌ 不修改 `scenes/Main.tscn`（标题场景红线，#572）；挂载接线归 #585 组装，impl 期不写死
- ❌ 不做失败场景/失败结算（SW-015 职责；本 issue 只保证并文档化 died(final=true) 事件契约）
- ❌ 不做氛围层（#582 职责：常驻色温/雪幕/水墨晕染/低血 vignette；本层闪屏为瞬态演出节点）
- ❌ 不重做动画（#574 职责：anim_revive/anim_dead 动画位已交付，本层仅触发状态流转）
- ❌ 不修改 mini-pong/ 任何文件（游戏隔离红线）
- ❌ 不写可运行实现/测试代码（本 phase 仅 DESIGN + TASKS 文档；测试代码归 implement agent）

## 附：风险裁决点采纳（PRD §8 延续上下文）

| # | 裁决点 | 本设计采纳 |
|---|--------|-----------|
| 1 | 计时器实现：SceneTreeTimer vs 自管理 | **自管理 `_process(delta)` 累加**——headless 确定性（测试手动推进，对齐 test_combat_entity._advance 模式），零树依赖；PRD 方案 A 明言二选一 |
| 2 | FX 挂载位置（#585 前如何出 AC5 截图证据） | capture rig（e2e_stick_figure_capture.tscn）挂 FX + REVIVE 态 trigger（测试 harness，additive）；游戏内挂载归 #585，Main.tscn 不碰 |
| 3 | 无敌闪烁实现：遍历 Line2D vs 父节点 modulate | **父节点 modulate 传播**（bind_player_visual 注入 StickFigure 根）——modulate 自动作用于全部 Line2D 肢体 + Polygon2D 头，原子且零遍历成本；`_process` 相位累加保确定性 |
| 4 | 闪屏与 #582 常驻色温层叠 | 瞬态节点后挂/高 layer 覆盖 + Tween 结束复原自身 color（零残留）；#582 为常驻色温节点，两者各自 color 互不覆盖（PRD §1.4 红线逐字对齐） |
| 5 | anim_dead clip 时长核对 | 倒地动画 clip 时长应 ≥ REVIVE_SECONDS（1s）覆盖复活窗口——impl 期核对 #574 参数，不改动画（若不足，报 #574 域偏差记录） |
| 6 | 慢动作全局影响 | SLOWMO_HOLD_SECONDS=0.4 基准（实验 3 定参）；`_slowmo_set` 防嵌套 + clamp 0.1；若用户裁决敌人节奏受损 → 降级路径 = PRD §4.4 方案 B（局部 hit-stop，归 #579 域） |

## 附：开源调研结论（PRD §6.2 已调研，implement PR 须附说明）

PRD §6.2 结论直接引用：GitHub API 五组查询（godot respawn / godot 4 respawn / godot revive system / godot checkpoints / godot player death）均无成熟 Godot 4.x 两条命语义开源方案；本项目核心语义已在 #575 交付（两段血 + die/revive + 无敌 + 信号契约），「不重复造轮子」由**项目内复用**满足；本 issue 只新增编排（计时驱动）+ 演出（GPUParticles2D/CanvasModulate/Tween/Engine.time_scale 标准节点组合），无第三方依赖。implement PR 须引用本调研结论，无需重复调研。
