# PRD #681 — [Bug] 攻击状态机调用不存在的 get_animation_position()（按 J / 鼠标左键攻击稳定触发报错）

> **前置依赖:** #574（merged #612：StickFigureController + 动画状态对象集 + E2E 截图像具）、#572（merged #599：StateMachineBase）
> **游戏目录:** `shandong-wolf/`（manifest `game.active: shandong-wolf`，2026-08-21）
> **引擎:** Godot 4.7.1（headless 验证通过，1314 tests passed）

## 1. 问题定义

### 1.1 现状（2026-08-21 预调查 @ origin/main 88bb3fc）

| 文件 | 行 | 调用 | 当前状态 |
|------|----|------|:--------:|
| `shandong-wolf/gdscripts/stick_figure_anim_states.gd` | 111 | `controller.get_animation_position()`（AnimStateAttack.update 每帧） | ❌ 方法不存在 |
| `shandong-wolf/gdscripts/e2e_stick_figure_capture.gd` | 129–130 | `_player.get_animation_position()` + `_player.is_animation_playing()` | ❌ 两个方法都不存在 |
| `shandong-wolf/gdscripts/stick_figure_controller.gd` | 全文件 | `get_animation_position()` / `is_animation_playing()` 实现 | ❌ 从未实现 |

**触发链路（键盘 J / 鼠标左键）：**

```
InputController (game_light_attack: KEY_J + MouseButton左)
    → attack_pressed 信号
    → CombatEntity 状态机（#575）进入 attack
    → main_battle.gd:145 state_changed → stick.consume_state("attack")
    → AnimStateAttack.enter() → play_clip("anim_attack")
    → StickFigureController._process → _anim_fsm.update(delta)
    → AnimStateAttack.update() → controller.get_animation_position()  ← SCRIPT ERROR
```

**SCRIPT ERROR 文本：** `Invalid call. Nonexistent function 'get_animation_position' in base 'Node2D (StickFigureController)'`（每次攻击每帧稳定触发；攻击三段 phase 判定因 pos 拿不到值而完全失效）。

### 1.2 预调查结果（Bug Pre-Investigation Workflow）

| Issue 声明 | 预调查结论 |
|------------|-----------|
| 「AnimStateAttack.update 调用不存在的 get_animation_position()」 | ✅ **属实** — `stick_figure_anim_states.gd:111` 调用，controller 无此方法（全文件 func 清单核对） |
| 「每次攻击（J / 鼠标左键）稳定触发报错」 | ✅ **属实** — 触发链路已核实（input map → combat FSM → consume_state → AnimStateAttack.update） |
| 「来源：#574 实现漏掉该方法」 | ✅ **属实** — 调用方由 commit `e70dcb2`（feat 574，PR #612）引入，controller 从未实现 |
| 「E2E 剧本渲染时暴露（CLASH 态必崩）」 | ✅ **属实 + 扩展** — E2E 截图像具还额外调用了 `is_animation_playing()`（e2e_stick_figure_capture.gd:130），**同样是缺失方法**，为同根因的兄弟缺陷 |

**Already fixed:** 无 — `git log --all --grep 681` 无结果；`git ls-remote origin refs/heads/research/681*` 无既有分支；本 issue 尚无人处理。
**Still broken:** 上述两处缺失方法调用（AnimStateAttack.update 主路径 + E2E 截图像具路径）。
**Stale claims:** 无 — issue 描述与当前代码完全一致，无过时声明。

### 1.3 根因分析

DESIGN #574 §2.4 伪代码只写了「依据 AnimationPlayer 当前时间推进 phase」（未给具体方法名），实现期 implement agent 在**调用方**（AnimStateAttack.update 与 e2e capture）自创了 `get_animation_position()` / `is_animation_playing()` 两个方法名并直接调用，但漏掉了在 **StickFigureController 上实现**这两个委托方法。即：调用方契约（caller contract）已写死，实现方（callee）缺失。

### 1.4 预期行为

1. `StickFigureController.get_animation_position() -> float` 返回 AnimationPlayer 当前播放位置（`current_animation_position`，秒）
2. 攻击期间不再有 SCRIPT ERROR
3. 攻击三段 phase（0 前摇 / 1 暴发 / 2 收招）依据 `attack_windup_end` / `attack_burst_end` 正确推进

### 1.5 用户场景

| 场景 | 频率 | 说明 |
|------|------|------|
| A: 玩家按 J 发起普通攻击 | 高（每场战斗多次） | 蓄力→暴发→收招三段节奏正确呈现，无控制台报错 |
| B: 玩家鼠标左键发起普通攻击 | 高 | 与 J 键等价（input map 同一 action 双绑定） |
| C: 连招（attack 中再按 attack，同态重入） | 中 | consume_state 同态重入重置前摇首帧，phase 从 0 重新推进 |
| D: E2E 剧本渲染攻击三段截图 | 低（管线/验收） | capture 脚本轮询动画位置派生 WINDUP/BURST/RECOVERY 截图态，不崩 |

### 1.6 范围边界（Patch 14 去冲突）

| 相邻 PRD | 覆盖范围 | 本 PRD 不重复覆盖 |
|----------|---------|------------------|
| #574（动画层，merged #612） | 火柴人骨架 + 11 态关键帧 + consume_state 契约 | ❌ 不重设计动画 clip/骨架；只补 controller 缺失的 2 个查询委托方法 |
| #575（战斗状态机，merged） | CombatEntity 11 态战斗 FSM（状态权威来源） | ❌ 不碰战斗状态机；本 bug 在动画层调度（AnimStateAttack） |
| #661/#662（E2E 链路修复，merged） | E2E 截图链路/backdrop z 层级 | ❌ 不碰 e2e 管线；只补 capture 脚本依赖的 controller 查询方法 |

本 PRD 唯一范围：**在 StickFigureController 上实现 `get_animation_position()` 与 `is_animation_playing()` 两个委托方法，并补测试覆盖**。

## 2. 设计意图

### 2.1 为什么当前行为存在

| Issue / Commit | 做了什么 | 后果 |
|----------------|----------|------|
| #574 DESIGN §2.4 | 伪代码只描述「依据 AnimationPlayer 当前时间推进 phase」，未定义具体方法名 | 实现期方法名自创，无实现约束 |
| `e70dcb2`（#574 实现，PR #612） | 在 AnimStateAttack.update 与 e2e capture 中直接调用 `get_animation_position()` / `is_animation_playing()` | 调用方契约写死，callee 从未实现 → 每次攻击 SCRIPT ERROR |
| #574 测试（test_stick_figure_animation.gd） | G1 测试直接读 `anim.current_animation_position`，不驱动 `_process` → `_anim_fsm.update()` | 测试未覆盖该路径 → 1314 tests 全绿但 bug 在真实运行时必现 |

### 2.2 为什么现在修复

- **priority/high + version/mvp**：攻击是 MVP 核心玩法，每次攻击稳定报错直接破坏可玩性与 E2E 剧本验收
- 修复面极小（2 个委托方法 + 测试），无架构风险
- #575 战斗状态机已落地，攻击链路完整（input → combat → anim），只差这层查询方法

### 2.3 先前约束

| 约束 | 详情 |
|------|------|
| consume_state 唯一动画入口 | 本修复不新增动画入口，只补查询方法（不读 Input、不订阅信号） |
| controller 持有 `_anim: AnimationPlayer`（私有） | 查询方法直接委托 `_anim`，不暴露 AnimationPlayer 本身 |
| `_anim` 可能为 null（缺子节点时 push_warning） | 查询方法必须 null-guard，返回安全默认值（0.0 / false） |
| 11 态 canonical 名权威归 #575 | 本修复不新增状态、不改状态名 |
| 三段时间戳来自 constants（8/60 前摇、4/60 暴发、10/60 收招） | 时间边界值已存在（attack_windup_end / attack_burst_end / attack_total_end），本修复只消费不修改 |

## 3. 影响分析

### 3.1 直接受影响的模块

| 文件 | 模块 | 变更性质 |
|------|------|----------|
| `shandong-wolf/gdscripts/stick_figure_controller.gd` | StickFigureController | 新增 2 个方法：`get_animation_position()` + `is_animation_playing()`（各 ~4 行，null-guard 委托 `_anim`） |
| `shandong-wolf/tests/test_stick_figure_animation.gd` | 动画层单测 | 新增测试：驱动 `_process` 走 AnimStateAttack.update，断言无报错 + phase 按位置推进 |

### 3.2 需新建的文件

无（纯补方法 + 补测试）。

### 3.3 间接受影响的模块

| 文件 | 影响 |
|------|------|
| `shandong-wolf/gdscripts/stick_figure_anim_states.gd` | 零改动 — AnimStateAttack.update 的调用契约（方法名 + 返回 float）现在被满足 |
| `shandong-wolf/gdscripts/e2e_stick_figure_capture.gd` | 零改动 — 129–130 行两个缺失调用（get_animation_position / is_animation_playing）被满足，E2E 攻击三段截图恢复 |
| `shandong-wolf/gdscripts/main_battle.gd` | 零改动 — state_changed → consume_state 链路不变，仅不再报错 |

### 3.4 数据流影响

```
StickFigureController._process(delta)
    │
    ▼
_anim_fsm.update(delta)  (StateMachineBase, RefCounted)
    │
    ▼
AnimStateAttack.update(_delta)
    │  controller.get_animation_position()  ← 修复点: 委托 _anim.current_animation_position
    ▼
pos >= _burst_end (12/60) → phase = 2 (收招)
pos >= _burst_start (8/60) → phase = 1 (暴发)
否则                        → phase = 0 (前摇)

e2e_stick_figure_capture.gd:_update_attack_phase()
    │  _player.get_animation_position() + _player.is_animation_playing()  ← 修复点: 同一委托
    ▼
WINDUP / BURST / RECOVERY / IDLE 截图态派生
```

### 3.5 需更新的文档

- [ ] `docs/GDD*.md` / `docs/PROJECT.md` — 无需（纯 bug 修复，无设计变更；如流水线惯例要求可在 PR 说明）
- [ ] 本 PRD 即研究产出，无额外文档

## 4. 解决方案比较

### 4.1 方法 A：controller 委托 `_anim`（推荐）

在 `StickFigureController` 新增两个薄委托方法：

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

- **描述：** 与 DESIGN #574 §2.4「依据 AnimationPlayer 当前时间推进 phase」的设计意图完全一致；`play_clip()` 已有 `_anim.stop()` → `_anim.play()` → `_anim.seek(0.0)` 的先例，委托风格统一。
- **Pros：** 最小改动（~10 行）；不破坏 consume_state 唯一入口契约；调用方零改动；E2E 与 AnimStateAttack 两处调用同时被满足；`current_animation_position` 在 seek 后立即反映新位置（同态重入场景正确）。
- **Cons：** 需 null-guard（`_anim` 缺失时返回 0.0/false 而非报错）。
- **Risk：** Low
- **Effort：** 0.5–1 天（含测试）

### 4.2 方法 B：AnimStateAttack 直接持有 AnimationPlayer

修改 AnimStateAttack 构造时注入 AnimationPlayer 引用，update 直接读 `_anim.current_animation_position`；E2E capture 同理。

- **描述：** 绕开 controller 中介，状态对象直接访问动画播放器。
- **Pros：** 少一层方法委托。
- **Cons：** ❌ 违反 #574 DESIGN §2.4 的薄契约设计（状态对象只依赖 controller 接口，替换成本低）；E2E capture 与 AnimStateAttack 两处都要改；`is_animation_playing` 仍需要在 controller 或 capture 侧另想办法；改动面更大。
- **Risk：** Med
- **Effort：** 1–2 天

### 4.3 方法 C：consume_state 契约改为返回位置（信号/回调）

让 controller 在播放时通过信号广播当前位置，状态对象订阅。

- **描述：** 事件驱动替代轮询。
- **Pros：** 状态对象无需查询。
- **Cons：** ❌ 过度设计 — 每帧广播信号开销 + 订阅管理复杂度；与现有 `update(delta)` 轮询模型冲突；E2E 轮询契约（`state_property` 轮询）不兼容；改动最大。
- **Risk：** High
- **Effort：** 2–3 天

### 4.4 推荐结论

**方法 A。** 理由：(1) 与 #574 原始设计意图逐字一致（「依据 AnimationPlayer 当前时间推进 phase」）；(2) 调用方契约已写死（e70dcb2），实现 callee 是唯一缺口；(3) 一处实现同时修复 AnimStateAttack 主路径与 E2E capture 路径；(4) 零架构风险，符合 MVP 修复的最小面原则。

## 5. 边界条件与验收标准

### 5.1 验收标准（映射 Issue #681 body）

- [x] **AC1: StickFigureController 实现 `get_animation_position() -> float`** — 返回 AnimationPlayer 当前播放位置
  - 实现委托 `_anim.current_animation_position`（秒）
  - `_anim == null` 时返回 `0.0`（不报错）
- [x] **AC2: 攻击不再有 SCRIPT ERROR** — 按 J / 鼠标左键攻击，控制台无 `Invalid call. Nonexistent function 'get_animation_position'`
  - 验证：headless 驱动 consume_state("attack") + `_process` 多帧，无 error 输出
- [x] **AC3: 三段 phase 按动画位置正确推进** — `attack_windup_end` / `attack_burst_end` 边界生效
  - pos < 8/60 → phase 0（前摇）
  - 8/60 ≤ pos < 12/60 → phase 1（暴发）
  - pos ≥ 12/60 → phase 2（收招）
  - 同态重入（attack 中再 attack）→ seek 回 0，phase 重置为 0

### 5.2 正常路径

- [ ] consume_state("attack") → anim_attack 播放 → 每帧 `_process` 无 error
- [ ] E2E capture 场景 attack 驱动 → WINDUP/BURST/RECOVERY 三态轮询正常（`is_animation_playing` 不再缺失）

### 5.3 边界情况

1. `_anim == null`（scene 缺 AnimationPlayer 子节点）→ get_animation_position 返回 0.0、is_animation_playing 返回 false，不崩溃
2. 动画播放完毕（`is_animation_playing() == false`）→ AnimStateAttack.update 仍被调用，pos 停在末尾 ≥ burst_end → phase 保持 2，直到状态切换
3. 同态重入（attack 中再 consume_state("attack")）→ play_clip 内部 seek(0.0)，下一帧 get_animation_position 返回 ~0 → phase 回 0
4. clip 缺失降级 anim_idle（§5-9 设计）→ get_animation_position 返回 idle 位置（可能 ≥ burst_end）→ phase 2，不报错
5. `seek()` 在暴发中段后立即查询 → `current_animation_position` 反映 seek 后的值（G1 测试语义一致）

### 5.4 失败路径

1. 若 `_anim.current_animation_position` 在 stop 后返回异常值 → 委托只读，不修改播放器状态，无副作用
2. 若测试驱动 `_process` 时 AnimStateAttack 未进入（current_state 为 idle）→ StateMachineBase.update 空状态安全（no-op），无影响
3. 若 E2E capture 在无 AnimationPlayer 的场景实例化 → null-guard 返回 false/0.0，capture 走 IDLE 回退，不崩

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 |
|------|:----:|:----:|
| #574（merged #612）— StickFigureController + AnimStateAttack | ✅ 已合并 | 无 — 本次修复的宿主代码 |
| #572（merged #599）— StateMachineBase | ✅ 已合并 | 无 |
| #575（merged）— CombatEntity 战斗状态机 | ✅ 已合并 | 无 — 触发链路完整 |

依赖链：`#572 → #574 → #575 → 本 issue（#681，动画层补漏）`

### 6.2 阻塞

| 未来工作 | 优先级 | 说明 |
|----------|:------:|------|
| #577 攻击判定（命中窗口消费 phase） | 高 | phase 正确推进后，判定层可消费前摇/暴发窗口（当前 phase 失效阻塞该消费） |
| E2E 剧本 attack 三段截图重新验收 | 中 | capture 脚本两处缺失方法修复后恢复 |

### 6.3 准备

- [ ] implement 前确认 `stick_figure_controller.gd` 当前版本与 origin/main 一致（本 PRD 侦查基于 88bb3fc）

## 7. Spike / 实验

Skipped per depth/standard label（Issue #681 无 depth 标签，按 standard 处理：Section 7 可选）。

若 implement 阶段想验证「seek 后 current_animation_position 立即反映新位置」的假设，可在 G1 测试基础上加一行：`consume_state("attack") → anim.seek(0.13) → get_animation_position() ≈ 0.13`（Godot 4.x AnimationPlayer.seek 同步更新 current_animation_position，预期通过）。

## 8. 延续上下文

### 系统状态

- **Bug 根因已确认**：`stick_figure_anim_states.gd:111`（AnimStateAttack.update）与 `e2e_stick_figure_capture.gd:129–130` 调用 `get_animation_position()` / `is_animation_playing()`，但 `stick_figure_controller.gd` 从未实现这两个方法（commit e70dcb2 引入调用方、漏掉实现方）
- **触发链路**：J / 鼠标左键 → InputController → CombatEntity（#575）→ consume_state("attack") → AnimStateAttack.enter + 每帧 update → SCRIPT ERROR
- **修复面**：仅 `stick_figure_controller.gd` 加 2 个委托方法（各 ~4 行，null-guard）；测试文件加攻击 phase 推进用例
- **测试现状**：1314 tests 全绿，但**未覆盖** `_process → _anim_fsm.update → AnimStateAttack.update` 路径（G1 直接读 AnimationPlayer，不驱动 FSM update）— 这是 bug 漏网原因，新测试必须驱动 `_process`

### 主要风险

- 测试驱动方式：新测试需调用 `controller._process(delta)` 触发 `_anim_fsm.update()`（或对私有 `_anim_fsm` 直接调 update），否则无法复现/验证 phase 推进
- phase 的可见性：`phase` 是 AnimStateAttack 内部状态对象属性，测试断言需通过 `controller._anim_fsm.current_state.phase` 访问（GDScript 允许）或建议实现期在 controller 暴露只读 `get_attack_phase()`（可选，超出本 issue AC 范围）

### 下一步（plan agent 交接）

1. DESIGN 文档：`docs/DESIGN/681-attack-get-animation-position.md` — 两个方法签名 + null-guard 语义 + 测试用例清单
2. 实现清单：
   - `stick_figure_controller.gd`：+`get_animation_position()`、+`is_animation_playing()`
   - `tests/test_stick_figure_animation.gd`：+Scenario J（攻击 phase 推进：consume_state("attack") → `_process` 多帧 → 断言 phase 0→1→2；+同态重入 phase 重置；+null _anim 安全）
3. 验证：`godot --headless --path shandong-wolf --script res://tests/run_tests.gd` 全绿；手动运行按 J 攻击无控制台报错
4. 边界红线：不修改 AnimStateAttack.update 调用契约、不新增动画状态、不碰 #575 战斗状态机、不改 constants 时间戳
