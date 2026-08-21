# Design: [Bug] StickFigureController 补 get_animation_position() / is_animation_playing() 委托方法

> **Parent Issue:** #681（bug / priority/high / gameplay / version/mvp）
> **Agent:** game-plan-agent
> **Date:** 2026-08-21
> **Approach:** PRD §4 **方案 A 确认采纳** —— 在 `StickFigureController` 新增两个薄委托方法 `get_animation_position() -> float` 与 `is_animation_playing() -> bool`（null-guard 委托 `_anim`），一处实现同时修复 AnimStateAttack 主路径与 E2E capture 路径；否决方案 B（状态对象直持 AnimationPlayer = 破坏 #574 §2.4 薄契约）与方案 C（信号广播 = 过度设计，与轮询模型冲突）
> **Reference PRD:** `docs/PRD/681-attack-get-animation-position.md`（research PR #686 已合并 2026-08-21）
> **上游方案:** `docs/DESIGN/574-stick-figure-silhouette-animation.md` §2.3（consume_state 唯一入口 + play_clip 委托风格）、§2.4（动画状态对象只依赖 controller 接口——薄契约）；`docs/DESIGN/575-combat-entity-state-machine.md`（战斗状态机权威归 #575）
> **所有权:** `content_ownership: mechanical`（两个查询委托方法 = 纯机械工程：方法签名、null-guard 语义、返回类型全部机械可验；零 taste 环节——不改摆姿、不改关键帧、不改时间戳）
> **深度:** standard（无 depth label；PRD 头按 standard 处理）—— 涉及文件 **2**（controller + 测试，< 10 文件、无迁移、无跨子系统子任务）→ **仅产出 DESIGN，不产 TASKS**（照 #662/#624 先例）
> **并行上下文:** worktree 隔离（/tmp/wt-plan-681，branch `plan/681-attack-get-animation-position`）；改动仅落在 `stick_figure_controller.gd`（+2 方法）与 `tests/test_stick_figure_animation.gd`（+Scenario J 用例）；constants.gd / scenes / e2e 脚本 / 战斗状态机零改动（#575 触发链路不动）

---

## 1. 架构总览

**问题本质是「调用方契约已写死、实现方缺失」的一侧缺口（half-implemented contract）：** #574 实现期（commit `e70dcb2`，PR #612）在**调用方**——`stick_figure_anim_states.gd:111`（AnimStateAttack.update 每帧）与 `e2e_stick_figure_capture.gd:129-130`（E2E 截图像具轮询）——自创并直接调用了 `get_animation_position()` / `is_animation_playing()` 两个方法名，但漏掉了在 **StickFigureController 上实现**这两个 callee。运行时每次攻击（键盘 J / 鼠标左键，input map 同一 action 双绑定）→ AnimStateAttack.update 每帧调用缺失方法 → 稳定 SCRIPT ERROR：`Invalid call. Nonexistent function 'get_animation_position'`，攻击三段 phase（0 前摇 / 1 暴发 / 2 收招）判定因拿不到位置而完全失效。

**设计哲学：只补 callee，不动 caller 契约；与 #574 既有委托风格逐字一致。**

1. **调用方契约是既成事实，不可修改**——AnimStateAttack.update 与 e2e capture 已按 `get_animation_position()` / `is_animation_playing()` 写好，改动调用方 = 扩散 diff + 违背「最小修复面」；
2. **callee 用与 `play_clip()` 完全相同的委托风格**——`play_clip()` 已有 `_anim.stop() → _anim.play() → _anim.seek(0.0)` 先例，新方法同样薄委托 `_anim`，不暴露 AnimationPlayer 本体；
3. **null-guard 是硬性要求**——`_anim` 可能为 null（scene 缺 AnimationPlayer 子节点时 `_ready()` 已 push_warning），查询方法必须返回安全默认值（0.0 / false）而非报错；
4. **一处实现、两路受益**——AnimStateAttack 主路径（每次攻击）与 E2E capture 路径（截图轮询）同时被满足。

```
                    ★ Issue #681 本设计（shandong-wolf 动画层补漏）
┌────────────────────────────────────────────────────────────────────────────┐
│ 修复前（caller 契约已写死，callee 缺失）                                      │
│   AnimStateAttack.update()  ──►  controller.get_animation_position()  ✗ 不存在│
│   e2e_stick_figure_capture  ──►  get_animation_position() / is_animation_playing() ✗│
│     → 每次攻击每帧 SCRIPT ERROR，phase 判定失效                                │
├────────────────────────────────────────────────────────────────────────────┤
│ 修复后（方案 A：controller 补 2 个薄委托方法）                                  │
│   StickFigureController.get_animation_position() -> float                    │
│       _anim == null ? 0.0 : _anim.current_animation_position                 │
│   StickFigureController.is_animation_playing() -> bool                       │
│       _anim == null ? false : _anim.is_playing()                             │
│   AnimStateAttack.update()  ──►  委托生效 → pos 推进 phase 0→1→2 ✅            │
│   e2e capture 轮询        ──►  委托生效 → WINDUP/BURST/RECOVERY 截图态恢复 ✅  │
└────────────────────────────────────────────────────────────────────────────┘
```

### 1.1 既有实现状态（Prior Implementation Status）

| 系统（文件） | Issue | 状态 | 本设计的处理 |
|------|:---:|:---:|------|
| `StickFigureController`（`gdscripts/stick_figure_controller.gd`） | #574 | ✅ merged（#612） | **+2 委托方法**（本 issue 主修改文件） |
| `AnimStateAttack`（`gdscripts/stick_figure_anim_states.gd:111`） | #574 | ✅ merged（调用方 e70dcb2） | **零改动**——调用契约被满足即修复 |
| `e2e_stick_figure_capture.gd:129-130`（攻击三段截图轮询） | #574 | ✅ merged（同样调用缺失方法） | **零改动**——同根因兄弟缺陷一并修复 |
| `StateMachineBase`（`gdscripts/state_machine.gd`） | #572 | ✅ merged（#599） | **零改动**——update() 转发契约已具备 |
| `CombatEntity` 战斗状态机 | #575 | ✅ merged | **零改动**——触发链路完整，非本 bug 范围 |
| `constants.gd` FRAME_ANIM_ATTACK_*（8/4/10 帧） | #574 | ✅ merged | **零改动**——时间边界已存在（attack_windup_end / attack_burst_end），本设计只消费不修改 |
| `tests/test_stick_figure_animation.gd`（G1 等 19 用例） | #574 | ✅ merged | **+Scenario J**（本 issue 测试补充，见 §8） |

### 1.2 核心缺口与修复决策（codebase 勘探确认，无 plan 新增缺口）

| PRD 断言 | 实际代码 | 结论 |
|---------|---------|------|
| `stick_figure_anim_states.gd:111` 调用 `get_animation_position()` | AnimStateAttack.update 每帧 `var pos: float = controller.get_animation_position()` | ✅ 属实，调用方存在 |
| StickFigureController 从未实现该方法 | 全文件 func 清单核对：play_clip / consume_state / trigger_sword_arc / _build_* 等，无 get_animation_position / is_animation_playing | ✅ 属实，callee 缺失 |
| e2e capture 额外调用 `is_animation_playing()` | e2e_stick_figure_capture.gd:129-130 `_player.get_animation_position()` + `_player.is_animation_playing()` | ✅ 属实，同根因兄弟缺陷 |
| 三段时间边界已存在 | controller `attack_windup_end` / `attack_burst_end` / `attack_total_end`（constants 派生，8/60、12/60、22/60） | ✅ 属实，本设计只消费 |
| 测试未覆盖 `_process → _anim_fsm.update` 路径 | G1 直接读 `anim.current_animation_position` + `anim.seek()`，不驱动 `_process` | ✅ 属实——bug 漏网原因，新测试必须驱动 `_process`（§8 J 系列） |

**结论：PRD 与代码完全一致，无 stale claims、无已修复部分、无 plan 需要补的缺口。**

---

## 2. 修复设计 — 详细设计

> 本 issue 无新组件、无新文件、无场景改动——修复 = 在既有 `StickFigureController` 上补 2 个查询委托方法 + 补测试覆盖。

### 2.1 `StickFigureController.get_animation_position() -> float`

**文件:** `shandong-wolf/gdscripts/stick_figure_controller.gd`（新增方法，置于 `play_clip()` 附近——查询方法与播放方法同区，供动画状态对象 / E2E 截图像具消费）

**签名与语义（AC1）：**

```gdscript
func get_animation_position() -> float:
    ## 供动画状态对象 / E2E 截图像具查询 AnimationPlayer 当前播放位置（秒）
    if _anim == null:
        return 0.0
    return _anim.current_animation_position
```

**设计要点：**
- **委托 `_anim.current_animation_position`**（Godot 4.x AnimationPlayer 属性，秒）——与 DESIGN #574 §2.4「依据 AnimationPlayer 当前时间推进 phase」的设计意图逐字一致；
- **null-guard**：`_anim == null`（scene 缺子节点）时返回 `0.0`，不报错、不崩溃（对齐 `play_clip()` 的 null 早退风格）；
- **只读无副作用**：不修改播放器状态；`seek()` 后 `current_animation_position` 同步反映新位置（同态重入场景：play_clip 内部 seek(0.0) → 下一帧查询 ≈ 0 → phase 回 0，§5 边界 3）；
- **不暴露 `_anim` 本体**：状态对象 / capture 只能经 controller 查询，保持薄契约（替换成本低，§2.3 约束）。

### 2.2 `StickFigureController.is_animation_playing() -> bool`

**文件:** 同上（紧邻 `get_animation_position()` 定义）

**签名与语义（E2E capture 依赖，兄弟缺陷修复）：**

```gdscript
func is_animation_playing() -> bool:
    ## 供 E2E 截图像具查询动画是否在播（null-guard）
    if _anim == null:
        return false
    return _anim.is_playing()
```

**设计要点：**
- **委托 `_anim.is_playing()`**——E2E capture `_update_attack_phase()` 用它判断「动画播完 → 回 IDLE」；
- **null-guard**：`_anim == null` 时返回 `false`（capture 走 IDLE 回退，不崩，§5 边界 6）；
- **只读**：不改变播放状态。

> ⚠️ **实现红线（PRD §8 转述）：** 只加这两个方法。**不修改** AnimStateAttack.update 调用契约（方法名 / 返回 float 保持）、**不新增**动画状态、**不碰** #575 战斗状态机、**不改** constants 时间戳、**不新增**动画入口（consume_state 唯一入口契约保持）。

---

## 3. 既有组件修改

### 3.1 修改文件清单

| 文件 | 修改 | 动机 |
|------|------|------|
| `shandong-wolf/gdscripts/stick_figure_controller.gd` | +`get_animation_position()`、+`is_animation_playing()`（各 ~4 行，null-guard 委托 `_anim`） | AC1：补 callee，满足 AnimStateAttack 与 e2e capture 的已写死调用契约 |
| `shandong-wolf/tests/test_stick_figure_animation.gd` | +Scenario J（攻击 phase 推进：驱动 `_process` 断言 phase 0→1→2 + 同态重入重置 + null 安全 + 播放状态查询） | AC2/AC3：覆盖 `_process → _anim_fsm.update → AnimStateAttack.update` 路径（bug 漏网原因） |

### 3.2 需新建的文件

无（纯补方法 + 补测试，PRD §3.2）。

### 3.3 影响分析

| 文件/系统 | 影响 | 风险 |
|-----------|------|:----:|
| `gdscripts/stick_figure_anim_states.gd`（AnimStateAttack） | **零改动**——调用契约（方法名 + 返回 float）被满足即修复 | 无 |
| `gdscripts/e2e_stick_figure_capture.gd:129-130` | **零改动**——两个缺失调用被满足，E2E 攻击三段截图恢复 | 无 |
| `gdscripts/main_battle.gd:145`（state_changed → consume_state） | **零改动**——链路不变，仅不再报错 | 无 |
| `gdscripts/state_machine.gd`（StateMachineBase） | **零改动**——update() 转发契约已具备 | 无 |
| `constants.gd`（FRAME_ANIM_ATTACK_*） | **零改动**——时间戳 8/4/10 帧保持 | 无 |
| `tests/test_stick_figure_animation.gd` 既有 19 用例（A-L） | 全部保持——新用例 J 系列追加，不改既有断言 | 无 |
| `scenes/player_stick_figure.tscn` | **零改动**——AnimationPlayer 子节点已存在（G1 可实例化验证） | 无 |

### 3.4 需更新的文档

- `docs/GAME_DESIGN/` / `docs/PROJECT.md` — 无需（纯 bug 修复，无设计变更；post-merge agent 按惯例判断）
- 本 PRD 即研究产出，无额外文档

---

## 4. 数据流

### Flow 1: 正常路径（攻击三段 phase 推进，修复后）

```
玩家按 J / 鼠标左键（InputController game_light_attack 双绑定）
    │
    ▼
attack_pressed 信号 → CombatEntity 状态机（#575）进入 attack
    │
    ▼
main_battle.gd state_changed → stick.consume_state("attack")
    │  （唯一动画入口，契约不变）
    ▼
AnimStateAttack.enter() → play_clip("anim_attack") → _anim.play + seek(0.0)
    │
    ▼
StickFigureController._process(delta) → _anim_fsm.update(delta)   ← StateMachineBase 转发
    │
    ▼
AnimStateAttack.update(_delta):
    pos = controller.get_animation_position()      ← 修复点: 委托 _anim.current_animation_position
    pos >= _burst_end (12/60)  → phase = 2 (收招)
    pos >= _burst_start (8/60) → phase = 1 (暴发)
    否则                        → phase = 0 (前摇)
    │
    ▼
无 SCRIPT ERROR；phase 按动画位置正确推进（AC2/AC3）
```

### Flow 2: E2E 截图像具路径（兄弟缺陷同步修复）

```
e2e_stick_figure_capture.gd:_process → _update_attack_phase()
    │  _player.get_animation_position() + _player.is_animation_playing()   ← 修复点: 同一委托
    ▼
is_animation_playing() == false → _attack_seq_active = false, current_state = IDLE（播完回退）
pos < attack_windup_end (8/60)   → ATTACK_WINDUP
pos < attack_burst_end  (12/60)  → ATTACK_BURST
否则                              → ATTACK_RECOVERY
    │
    ▼
WINDUP / BURST / RECOVERY / IDLE 截图态派生恢复（E2E 剧本不再崩）
```

### Flow 3: 失败路径（null / 边界，均安全降级）

```
若 _anim == null（scene 缺 AnimationPlayer 子节点）:
    get_animation_position() → 0.0（不报错）
    is_animation_playing()   → false（不报错）
    AnimStateAttack.update: pos=0.0 < _burst_start → phase 保持 0（不崩）
    e2e capture: is_animation_playing=false → 回 IDLE（不崩）

若动画播放完毕（is_animation_playing() == false）:
    AnimStateAttack.update 仍被调用，pos 停在末尾 ≥ _burst_end → phase 保持 2
    （直到战斗状态机切换状态；phase 2 收招语义正确）

若同态重入（attack 中再 consume_state("attack")）:
    play_clip 内部 seek(0.0) → 下一帧 get_animation_position() ≈ 0 → phase 回 0
    （连招语义 §5-3 保持）
```

---

## 5. 边界情况与错误处理

| 边界情况 | 缓解 |
|---------|------|
| `_anim == null`（scene 缺 AnimationPlayer 子节点，`_ready()` 已 push_warning） | `get_animation_position()` 返回 0.0、`is_animation_playing()` 返回 false——null-guard 硬性要求，不报错不崩溃（PRD §5.3-1） |
| 动画播放完毕（`is_animation_playing() == false`） | AnimStateAttack.update 仍被调用，pos 停在末尾 ≥ burst_end → phase 保持 2（收招语义正确），直到状态切换（PRD §5.3-2） |
| 同态重入（attack 中再 consume_state("attack")） | play_clip 内部 `seek(0.0)` → 下一帧 get_animation_position ≈ 0 → phase 回 0（连招语义，§5-3）（PRD §5.3-3） |
| clip 缺失降级 anim_idle（§5-9 设计） | get_animation_position 返回 idle 位置（可能 ≥ burst_end）→ phase 2，不报错（PRD §5.3-4） |
| seek 在暴发中段后立即查询 | `current_animation_position` 反映 seek 后的值（Godot 4.x 同步更新；G1 测试语义一致）（PRD §5.3-5） |
| `_anim` stop 后查询位置 | 委托只读，不修改播放器状态，无副作用（PRD §5.4-1） |
| 测试驱动 `_process` 时 AnimStateAttack 未进入（current_state 为 idle） | StateMachineBase.update 空状态安全（no-op），无影响（PRD §5.4-2） |
| E2E capture 在无 AnimationPlayer 的场景实例化 | null-guard 返回 false/0.0 → capture 走 IDLE 回退，不崩（PRD §5.4-3） |
| phase 可见性（测试断言路径） | `phase` 是 AnimStateAttack 内部状态对象属性——测试经 `controller._anim_fsm.current_state.phase` 访问（GDScript 允许）；可选：实现期在 controller 暴露只读 `get_attack_phase()`（**超出本 issue AC 范围，非必需**，见 §8 注） |

---

## 6. 集成点

> **Status 约定:** ⬜ = 待 implement agent 接线；✅ = implement 完成并验证。实现后须更新此表。

| 集成 | 本组件 | 目标 | How | Status |
|------|:---:|:---:|-----|:---:|
| 攻击 phase 推进 | StickFigureController.get_animation_position() | AnimStateAttack.update（stick_figure_anim_states.gd） | 方法委托（caller 契约已写死，callee 补齐即通） | ✅ implement #681 |
| E2E 截图轮询 | StickFigureController.get_animation_position() + is_animation_playing() | e2e_stick_figure_capture.gd:_update_attack_phase() | 方法委托（同根因兄弟缺陷一并修复） | ✅ implement #681 |
| 动画播放调度 | StickFigureController._process → _anim_fsm.update | StateMachineBase（#572）→ AnimStateAttack.update | 既有链路零改动，新方法使其不再报错 | ✅ 已有 |
| 攻击触发链路 | consume_state("attack") | CombatEntity（#575）→ main_battle.gd:145 | 既有链路零改动 | ✅ 已有 |

---

## 7. 实现阶段

| 阶段 | 优先级 | 组件 | 工作量 |
|:----:|:------:|------|:------:|
| Phase 1（唯一） | P0 | `stick_figure_controller.gd` +2 方法（§2.1 + §2.2） | 0.5 人日 |
| Phase 2 | P0 | `tests/test_stick_figure_animation.gd` +Scenario J（§8） | 0.5 人日 |

> 两阶段有依赖顺序（先方法后测试——测试驱动 `_process` 依赖方法存在），但可单次提交。实现 PR 的验证 gate 见 §9 验证清单。

---

## 8. 测试用例描述

> **说明:** 本阶段只写测试**描述**，不写可运行测试文件（plan 阶段红线）。用例编号 J1 起（追加到既有 Scenario A–L 之后，文件头注释同步补「Scenario J」），便于 implement agent 对号入座。
>
> **测试驱动方式（关键，bug 漏网原因）：** 既有 G1 直接读 `anim.current_animation_position` 并 `anim.seek()`，**不驱动** `_process` → `_anim_fsm.update()`——因此未覆盖 AnimStateAttack.update 路径。新用例必须**调用 `controller._process(delta)`**（或对私有 `_anim_fsm` 直接调 `update()`）以触发 `AnimStateAttack.update`，从而复现并验证 phase 推进。
>
> **phase 断言路径：** `controller._anim_fsm.current_state.phase`（StateMachineBase.current_state 为公开 var；AnimStateAttack.phase 为公开 var——GDScript 允许跨对象访问）。可选增强：实现期在 controller 暴露只读 `get_attack_phase()`（**超出 AC 范围，非必需**，若加则 J 系列断言路径更稳）。

### Scenario J: 攻击 phase 推进（`_process` 驱动，AC2/AC3 核心）

- **J1 前摇 phase 0（无 SCRIPT ERROR）**: `_make_controller()` 实例化 `player_stick_figure.tscn` → `consume_state("attack")` → `controller._process(0.016)`（一帧）→ 断言无 error 输出（Godot push_error 捕获：测试框架记录运行期 error 数，本用例前后 error 计数不变）且 `_anim_fsm.current_state.phase == 0`。前置：§2.1 方法存在。预期：无报错 + phase 0（pos≈0 < 8/60）。
- **J2 暴发 phase 1**: 接 J1 状态，`anim.seek(0.10)`（8/60=0.1333 < 0.10 < 12/60=0.2 区间内）→ `controller._process(0.016)` → 断言 `phase == 1`。预期：pos 0.10 ≥ _burst_start(8/60) 且 < _burst_end(12/60) → phase 1。
- **J3 收招 phase 2**: 接 J2 状态，`anim.seek(0.21)`（≥ 12/60=0.2）→ `controller._process(0.016)` → 断言 `phase == 2`。预期：pos ≥ _burst_end → phase 2。
- **J4 同态重入 phase 重置 0**: attack 播到暴发中段（seek 0.10）→ 再次 `consume_state("attack")`（同态重入，play_clip 内部 seek(0.0)）→ `controller._process(0.016)` → 断言 `phase == 0` 且 `anim.current_animation_position < 0.001`。预期：连招语义——重入重置前摇首帧，phase 从 0 重新推进（AC3 同态重入分支）。
- **J5 播完 phase 保持 2**: `anim.seek(0.30)`（≥ attack_total_end=22/60≈0.3667？——注意 0.30 < 0.3667 仍在收招内）→ 改用 `anim.seek(0.40)`（> clip 长度 22/60≈0.3667，Godot 自动 clamp 到末尾）→ `controller._process(0.016)` → 断言 `phase == 2` 且 `anim.is_playing() == false`。预期：播完 pos 停在末尾 ≥ burst_end → phase 2，直到状态切换（PRD §5.3-2）。
- **J6 get_animation_position 委托正确性（AC1）**: `consume_state("attack")` → `anim.seek(0.13)` → `controller.get_animation_position()` ≈ 0.13（`abs(diff) < 0.001`）。预期：委托 `_anim.current_animation_position`，seek 后同步反映（PRD §7 spike 建议落地）。
- **J7 is_animation_playing 委托正确性**: 播放中（consume_state 后未播完）→ `controller.is_animation_playing() == true`；`anim.stop()` → `controller.is_animation_playing() == false`。预期：委托 `_anim.is_playing()`。
- **J8 null _anim 安全（PRD §5.3-1）**: 构造无 AnimationPlayer 子节点的 controller（如 `StickFigureController.new()` 裸实例或手工构建无子节点场景）→ `get_animation_position() == 0.0`、`is_animation_playing() == false`，不报错不崩溃。预期：null-guard 生效。
- **J9 未知状态降级不崩（回归 H1 交互）**: `consume_state("unknown_state")` → `controller._process(0.016)` 多帧 → 无 error、anim 播放 anim_idle。预期：未知状态降级 idle 后 AnimStateAttack 未进入（current_state 为 AnimStateIdle，update 为 no-op 或 idle 逻辑），不触发缺失方法路径。

### Scenario R: 回归（既有测试保持）

- **R1 G1 同态重入保持**: 既有 `_test_g1_same_state_reentry` 仍通过（直接读 `anim.current_animation_position` 的断言不受新方法影响）。前置：未改动 G1。预期：通过。
- **R2 全套件全绿**: 运行项目测试套件（`godot --headless --path shandong-wolf --script res://tests/run_tests.gd`），1314+ 用例全部通过（新增 J1-J9 后计数增加）。预期：全绿。
- **R3 冒烟**: `godot --path shandong-wolf/ --headless --quit` 退出 0——controller 加方法不破坏场景加载与首启链。预期：退出码 0。

### 既有用例影响清单

| 用例 | 影响 | 处置 |
|------|------|------|
| test_stick_figure_animation.gd A-L 全部 19 用例 | 无（未改动既有断言） | 保持 |
| test_state_machine / test_player_controller / test_combat_entity 等其余套件 | 无（未触碰任何相关 .gd 逻辑） | 保持 |
| e2e_stick_figure_capture（E2E 剧本） | 间接受益（缺失方法被满足，攻击三段截图恢复） | 保持（无需改脚本） |

---

## 9. 验收条件映射（源自 Issue #681 body + PRD §5.1）

| # | 验收条件 | 设计落点 | 验证方式 |
|---|---------|---------|---------|
| AC1 | StickFigureController 实现 `get_animation_position() -> float`（返回 AnimationPlayer 当前播放位置） | §2.1 | J6（委托正确性）+ 代码审查 |
| AC2 | 攻击不再有 SCRIPT ERROR（J / 鼠标左键攻击，控制台无 `Invalid call. Nonexistent function 'get_animation_position'`） | §2.1 + §2.2 | J1（error 计数不变）+ R2 全套件 + 手动运行按 J 攻击无报错 |
| AC3 | 三段 phase（attack_windup_end / attack_burst_end）按动画位置正确推进 | §2.1（委托供给 pos） | J1/J2/J3（0→1→2 边界）+ J4（同态重入重置 0）+ J5（播完保持 2） |
| 附加（PRD 扩展） | E2E capture 依赖的 `is_animation_playing()` 一并修复（兄弟缺陷） | §2.2 | J7 + Flow 2 推演 |

### 实现 PR 的验证 gate（PRD §8 转述）

1. `godot --headless --path shandong-wolf --script res://tests/run_tests.gd` → 全绿（新增 J 系列通过，1314+ 计数）
2. 手动/脚本驱动：`consume_state("attack")` + `_process` 多帧 → 无 `Invalid call. Nonexistent function` error
3. E2E capture 场景 attack 驱动 → WINDUP/BURST/RECOVERY 三态轮询正常（`is_animation_playing` 不再缺失）
4. `git diff` 确认仅 `stick_figure_controller.gd` + `tests/test_stick_figure_animation.gd` 两文件变更（红线守卫，§10）

---

## 10. 明确不修改（与 PRD §8 红线对齐）

- ❌ `shandong-wolf/gdscripts/stick_figure_anim_states.gd`（AnimStateAttack.update 调用契约——方法名 + 返回 float 保持，零改动）
- ❌ `shandong-wolf/gdscripts/combat_states.gd` / `combat_entity.gd` 等（#575 战斗状态机，权威源不动）
- ❌ `shandong-wolf/gdscripts/constants.gd`（FRAME_ANIM_ATTACK_WINDUP/BURST/RECOVERY 时间戳保持，不二选一、不改值）
- ❌ `shandong-wolf/gdscripts/e2e_stick_figure_capture.gd`（零改动——委托被满足即修复）
- ❌ `shandong-wolf/scenes/`（player_stick_figure.tscn 零改动——AnimationPlayer 子节点已存在）
- ❌ 其他测试文件（仅 test_stick_figure_animation.gd 追加 Scenario J；不改 A-L 既有断言）
- ❌ `mini-pong/`、`game-env/manifest.yaml`、`.github/workflows/`、`scripts/`、`framework/`、`docs/GAME_DESIGN/`（跨游戏/管线红线）
- ✅ `stick_figure_controller.gd` 仅新增 §2.1/§2.2 两个方法——其余方法（consume_state / play_clip / trigger_sword_arc / _build_* / _attack_bounds_from_constants）零改动
