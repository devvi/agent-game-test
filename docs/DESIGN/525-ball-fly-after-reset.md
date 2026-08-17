# DESIGN: [Bug] 游戏重置后，无操作下，有小球意料之外飞行

> **Parent Issue:** #525
> **Agent:** game-plan-agent
> **Date:** 2026-08-17
> **Approach:** A — FSM 独占发球编排 + SCORED 冻结球（确认 PRD §4 推荐方案；light 修复，无方案分歧。否决方案 B：新增 API + 观感属品味域；否决方案 C：serve() 内 frozen=false 覆盖冻结，无效）
> **Reference PRD:** docs/PRD/525-ball-fly-after-reset.md（research PR #531，已合并）
> **所有权:** `content_ownership: mechanical`（确定性时序修复：发球编排竞态 = 机械可测，无品味决策）
> **深度:** light（Issue body「工作深度: light（简单修复，快速完成）」；无 depth/ 标签，按 body 声明）—— 文件域 2（ball.gd / game_state_machine.gd）+ 1 个新测试文件描述，无新组件、无迁移、无弃用 → **不产 TASKS 文档**（低于 skill 阈值）
> **基线:** main @ f94f0aa（PRD 基线 e7fd26c 之后的 workflow 修复提交；本设计逐条核实的代码事实与 PRD 一致）

---

## 1. 架构概述

### 1.1 设计核心

**根因是双发球竞态（double-serve race）：`ball.gd` 得分路径自调 `serve()`（#287「ball 自管发球」遗留），与 FSM 的 SCORED→SERVING 重发球编排（#294）叠加 —— 球出界得分后 0.5s（`SERVE_DELAY`）即自行起飞，此时 FSM 处于 SCORED/SERVING、挡板冻结，球在无任何输入下自由飞行 ~1.5s（用户所见「有小球落下」），直到 FSM 的 `serve()` 在 ~2.0s 将其拉回中心。违反 DESIGN #294 状态表：SCORED/SERVING 两态 Ball Moving = **No**。**

修复 = 4 行改动，让实现回归 #294 设计：

```
                     ★ Issue #525 修复（Approach A，2 个文件）
        ┌────────────────────────────────────┴────────────────────────────────────┐
        │ 修复点 1: ball 不再自管发球（ball.gd）                   修复点 2: SCORED 冻结球（game_state_machine.gd）
        ▼                                                              ▼
  _process 上出界分支 (:180)  删 serve()          SCORED enter_state 在 _freeze_paddles(true) 后
  _process 下出界分支 (:184)  删 serve()          新增 _freeze_ball(true)（注释 #525 + #294 设计表）
  _on_score_zone      (:193)  删 serve()          （_freeze_ball helper 已存在 :227，has_method 守卫）
  ── 只保留 score.emit(side) ──                   ── SERVING 的 serve()（:120）是既有解冻入口 ──
```

设计哲学：

1. **发球编排单一调用方（FSM）** — #294 的设计意图就是「FSM 集中编排发球」（当年已移除 scoring_manager 的发球逻辑）；ball 得分路径自调 serve() 是同款遗留。A 是补完迁移，非新机制。
2. **回归设计表而非新增机制** — DESIGN #294 状态表本就规定 SCORED/SERVING Ball Moving = No；SCORED 实现遗漏了球冻结，本次让实现对齐设计。
3. **软冻结复用 #296 约定** — 用 `set_frozen()` 软冻结（不动 SceneTree pause），与 #508 MENU 冻结、#391 GAME_OVER 冻结同模式；`_freeze_ball` helper 已存在（has_method 守卫，mock ball 安全）。
4. **解冻契约不破坏** — `serve()` 内 `frozen = false`（ball.gd:93，#391 AC4）是唯一解冻入口，方案 A 不触碰该方法本体；这正是方案 C 无效的原因（得分路径的 serve() 会把 SCORED 冻结覆盖掉）。
5. **最小变更（light）** — 4 行改动 + 1 个新回归测试文件，0.5 天；无新 API（方案 B 的 `reset_for_serve()` 增加改动面且观感增益属品味域，超出 light 范围）。

### 1.2 PRD 断言 vs 实际代码交叉对照（plan agent 已逐条核实源码，main @ f94f0aa）

| PRD 断言 | 实际代码 | 设计裁决 |
|---------|---------|---------|
| ball.gd 得分路径 3 处自调 serve() | ✅ 核实一致：`_process` 上出界分支 :180（`score.emit(0)` 后）、下出界分支 :184（`score.emit(1)` 后）、`_on_score_zone` :193（`score.emit(side)` 后） | 删除这 3 处调用，只保留 emit；**保留** :84 `_ready()` 的首发球调用 |
| serve() 内 `frozen = false`（防御性复位） | ✅ ball.gd:93 `frozen = false  # #391 AC4：防御性复位——新发球/新 run 永不携带陈旧冻结` | 保留（#391 AC4 解冻契约）；方案 C 因它被否决（得分路径 serve() 会覆盖 SCORED 冻结） |
| FSM SCORED enter 无球冻结 | ✅ game_state_machine.gd:150-163：SCORED 分支仅 `_set_ui("hud")` + `_freeze_paddles(true)` + 1s 计时，无 `_freeze_ball` | SCORED enter 新增 `_freeze_ball(true)`（裁决 1） |
| `_freeze_ball()` helper 已存在 | ✅ game_state_machine.gd:227-229，`has_method("set_frozen")` 守卫（#296 约定） | 直接复用，无需新增方法 |
| GAME_OVER 已有冻结/解冻 | ✅ :166 `_freeze_ball(true)`（#391 AC4）、exit_state :175 `_freeze_ball(false)` | 与 SCORED 冻结幂等叠加，无改动 |
| SERVING 由 FSM 调 serve() | ✅ game_state_machine.gd:120 `ball.serve()`（has_method 守卫）+ :122-123 `_wait_for_serve()` | 发球编排保持 FSM 独占，不动 |
| test_ball TC-E1/E2 只断言 score 信号 | ✅ test_ball.gd:329-365：仅收集 score 信号并断言 side，无「得分后位置复位」断言 | 删 serve() 调用不影响；TC-F1-F4 直接调 serve() 方法本体，同样不受影响 |
| FSM 测试用无 serve() 的 mock ball | ✅ test_game_state_machine.gd:97 `"ball": Area2D.new()`（无 serve/set_frozen）；test_failure_screen.gd 的 mock 有 set_frozen（#391 模式） | `has_method` 守卫跳过 → 零影响；test_failure_screen 的 GAME_OVER 断言不受 SCORED 新增冻结影响 |
| scoring_manager 信号流不变 | ✅ scoring_manager.gd:58-72：`_on_ball_score` → `add_score(...)` + `scored.emit(winner)`（出界分才触发，拆砖分不触发） | 无改动；竞态消除后 add_score 天然单次（AC3） |
| e2e AC3-T5 的 `_crossed_wall` 断言仍成立 | ✅ e2e_playthrough.gd:127-130：信号在 serve() 复位前同步触发 | 方案 A 下复位更晚（FSM t=2.0），断言更稳 |

### 1.3 设计裁决（PRD 缺口闭合 — plan agent 独立裁决）

**裁决 1（SCORED 冻结位置）：`enter_state(SCORED)` 内 `_freeze_paddles(true)` 之后加 `_freeze_ball(true)`。** 不放 `exit_state(SCORED)` —— SCORED 只有两个出口：① →SERVING（serve() 解冻回中，天然接管）；② →GAME_OVER（enter 再 `_freeze_ball(true)`，幂等）。exit 加解冻反而引入「SERVING 1s 等待期内球可动」的窗口。注释标注 `#525` + `#294 设计表`。

**裁决 2（新增回归测试归属）：新建独立测试文件 `tests/test_ball_fsm_serve_race.gd`（真实 ball.gd + 真实 FSM mini-tree，复用 PRD §1.1.1 复现脚本模式），并在 run_tests.gd 注册。** 理由：PRD §8 建议的断言（「PLAYING 出界 → SCORED/SERVING 期间 ball.position 恒定 + frozen=true + 单次计分」）需要真实 `ball._process` 时序 —— test_integration_fsm.gd 是 RefCounted mock 驱动（无 tree、无真实 ball），承载不了；test_ball.gd 无 FSM。独立文件隔离时序断言最清晰（§9 Scenario A/B/C）。测试**描述**见 §9，可运行代码由 implement agent 编写。

**裁决 3（PAUSED 不修）：** PAUSED enter 无 `_freeze_ball`（game_state_machine.gd:142-148，#296 软冻结只冻挡板）→ 球暂停期继续移动，出界时 FSM 忽略 scored（warning）。这是**关联面**（PRD §5.2-6），非本 issue 范围，列为 follow-up 候选（§10）。

**裁决 4（失败路径原子性）：** 「删 3 处 serve() 调用」与「SCORED 加冻结」必须**同 PR 同改** —— 只删调用不加冻结 → 球带速度停在出界位，下帧再次触发出界 → 重复 `score.emit` + `add_score`（分数膨胀）；只加冻结不删调用（方案 C）→ 得分路径 serve() 把 frozen 复位 → 修复无效。方案 A 是原子修复。

---

## 2. 新组件

无新文件/新节点/新常量。修复全部内聚于既有 `ball.gd` 与 `game_state_machine.gd`。

| 文件 | 说明 |
|------|------|
| （无） | light 修复，PRD §3.2 确认无新组件 |

---

## 3. 既有组件修改

### 3.1 修改文件

| 文件 | 变更 | 理由 |
|------|------|------|
| `mini-pong/gdscripts/ball.gd` | 删除 3 处得分路径的 `serve()` 调用（:180 / :184 / :193），只保留 `score.emit(side)` | 发球编排收归 FSM 独占（#294），消除双发球竞态 |
| `mini-pong/gdscripts/game_state_machine.gd` | `State.SCORED` enter_state 在 `_freeze_paddles(true)` 后新增 `_freeze_ball(true)`（带注释） | SCORED 期间球静止，回归 DESIGN #294 状态表 |

**ball.gd 精确 diff（按行）：**

```gdscript
# _process Y 边界分支（现状 :176-185 → 修复后）
if position.y < -BALL_RADIUS:
    if not _scored_this_frame:
        score.emit(0)  # Player scores (ball exited top past AI)
        # serve() 移除 (#525): 发球编排归 FSM SCORED→SERVING，消除双发球竞态
elif position.y > screen_height + BALL_RADIUS:
    if not _scored_this_frame:
        score.emit(1)  # AI scores (ball exited bottom past player)
        # serve() 移除 (#525)

# _on_score_zone（现状 :189-194 → 修复后）
func _on_score_zone(side: int) -> void:
    if _scored_this_frame:
        return
    _scored_this_frame = true
    score.emit(side)
    # serve() 移除 (#525)
```

**保留清单（红线，implement agent 不得触碰）：**
- `serve()` 方法本体（ball.gd:87-119）—— FSM 仍调用
- `_ready()` 内的 `serve()`（ball.gd:84）—— 首发球
- `frozen = false` 行（ball.gd:93）—— #391 AC4 解冻契约
- `_is_serving` 契约与 `_wait_for_serve()` 轮询（game_state_machine.gd:250-256）

**game_state_machine.gd 精确 diff（伪代码）：**

```gdscript
State.SCORED:
    _set_ui("hud")
    _freeze_paddles(true)
    _freeze_ball(true)   # #525: SCORED 冻结球 — 回归 #294 设计表 (SCORED/SERVING Ball Moving = No)
                         #      解冻由 SERVING 的 serve() 内 frozen=false (#391 AC4) 接管
    _scored_timer_active = true
    await _timer_1s()
    ...
```

### 3.2 受影响测试文件（只列描述，不写代码）

| 测试文件 | 影响 | 处理 |
|---------|------|------|
| `tests/test_ball.gd` | TC-E1/E2 只断言 score 信号；TC-F1-F4 直接调 serve() 方法本体 | 无改动，应保持通过 |
| `tests/test_game_state_machine.gd` | mock ball 无 set_frozen/serve → `_freeze_ball`/`has_method` 守卫跳过 | 无改动 |
| `tests/test_integration_fsm.gd` | RefCounted mock 驱动，不实例化真实 ball | 无改动 |
| `tests/auto_play_test.gd` | 已绕开 `ball._process`（手动物理） | 无改动 |
| `tests/e2e_playthrough.gd` | 重发球走 FSM SCORED→SERVING 路径；AC3-T5 `_crossed_wall` 断言在 serve() 复位前同步触发 | 无改动（复位更晚，断言更稳） |
| `tests/test_failure_screen.gd` | GAME_OVER 冻结断言（D-1/D-2）；SCORED 新增冻结不改变 GAME_OVER enter 语义（幂等） | 无改动 |
| `tests/run_tests.gd` | 新测试文件需注册 | **新增一行注册**：`_run("res://tests/test_ball_fsm_serve_race.gd", "Ball Serve Race")` |
| **新增** `tests/test_ball_fsm_serve_race.gd` | 新回归测试（§9 Scenario A/B/C） | implement agent 创建（只写测试，本阶段不落码） |

### 3.3 移除/弃用文件

无。

---

## 4. 数据流

### Flow 1: 正常路径 — 出界得分 → 重发球（AC1/AC2）

```
Ball._process 出界（或 ScoreZone area_entered）
    │  score.emit(side)                        ← serve() 已移除（原在此处自起飞）
    ▼
ScoringManager._on_ball_score(side)
    ├── GameManager.add_score(winner, amount, kind)   ← 单次（球已冻结，无重复出界）
    └── scored.emit(winner)
            ▼
FSM._on_scored(winner)  [仅 PLAYING 时响应]
    └── transition_to(SCORED)
            ├── _freeze_paddles(true)
            ├── _freeze_ball(true)                    ← 新增（#525）: 球静止在出界位
            └── 1s → is_run_over() ? GAME_OVER : SERVING
                    └── SERVING: 1s → ball.serve()（回中 + frozen=false + _is_serving + 0.5s 起飞）
                            └── _wait_for_serve() → PLAYING（挡板解冻）
```

时间线（对照 PRD §1.1.1 修复前实测表）：t=0.00 出界得分 → SCORED 冻结；t=0~2.0 SCORED/SERVING 全程 `ball.frozen==true`、`position` 恒定（不再有 t=0.5 自行起飞）；t=2.0 serve() 回中解冻；t=2.5 PLAYING 恢复对打。

### Flow 2: 终局路径 — 21 分 → GAME_OVER → MENU 重开

```
SCORED（球冻结）→ 1s → is_run_over()==true → GAME_OVER
    ├── enter: _freeze_paddles(true) + _freeze_ball(true)   ← 与 SCORED 冻结幂等叠加
    └── exit:  _freeze_ball(false)                           ← #391 AC4: 解冻供下一 run
            → MENU（previous==GAME_OVER → 不再冻结，#508 世界隐藏，球不可见）
            → SPACE → SERVING → ball.serve() 回中 → PLAYING
```

### Flow 3: headless / mini-tree（AC4 测试面）

```
headless 测试（无 SceneTree）:
    ball.serve() → tree==null 立即路径（设 velocity + _is_serving=false）—— serve() 本体不变，不受影响
    FSM 测试 mock ball 无 serve()/set_frozen → has_method 守卫跳过 —— 零影响
    run_tests.gd 全量 → 基线 2354 passed（main @ e7fd26c）; 方案 A 版 2367 passed / 0 failed（PRD §5.1 实测）
```

---

## 5. 边界情况与错误处理

| # | 边界情况 | 缓解 |
|---|---------|------|
| 1 | MENU 开局首次发球（MENU→SERVING） | serve() 仍由 FSM 调用（game_state_machine.gd:119-120），`_ready()` 首发球（ball.gd:84）不受影响 —— 方案 A 只删得分路径调用 |
| 2 | 终局分（21 分）→ SCORED → GAME_OVER | SCORED 冻结与 GAME_OVER 冻结（:166）幂等叠加；GAME_OVER exit 解冻（:175，#391 AC4）供下一 run |
| 3 | GAME_OVER→MENU 重开 | 球停在出界位、MENU 中不可见（#508 世界隐藏）；SPACE→SERVING 时 serve() 回中 —— 与现状一致，非回归 |
| 4 | ScoreZone 路径（area_entered 计分）| 与 Y 边界路径同样删 serve()、同样被 SCORED 冻结 —— 两条计分路径行为一致 |
| 5 | 只删调用不加冻结（方案 A 原子性）| 球带速度停在出界位 → 下帧再触发出界 → 重复 score.emit + add_score（分数膨胀）→ 「删调用 + 冻结」必须同 PR 同改 |
| 6 | 只加冻结不删调用（方案 C）| 得分路径 serve() 内 `frozen=false` 覆盖冻结 → 球照常起飞，修复无效（PRD §4 源码推理否决）|
| 7 | PAUSED 出界（关联面，不修）| PAUSED enter 无 `_freeze_ball`（#296 只冻挡板）→ 球暂停期继续移动，出界时 FSM 忽略 scored（warning）—— 既有行为，follow-up 候选（§10）|
| 8 | 重复计分防护 | 修复后球冻结，出界事件单次；`_scored_this_frame` 帧守卫（#295）继续兜底双触发 |
| 9 | 误改 serve()/`_is_serving` 契约 | 保留 serve() 本体与 `_wait_for_serve()` 轮询不变 —— 破坏则 SERVING 卡死无法进 PLAYING |

---

## 6. 按场景/组件配置

无场景/配置改动：无 `.tscn`/`.tres` 修改、无新常量（`SERVE_DELAY` 0.5s、SCORED 1s + SERVING 1s 节奏均不变，AC2）。竖屏几何（720x1280，#383）不变。

---

## 7. 集成点

> **状态约定：** ✅ = 既有/保持不变；⬜ = 本 issue 新增待实现。implement agent 完成后将 ⬜ 置 ✅。

| 集成 | 我方组件 | 目标 Issue | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| 发球编排 | FSM SERVING → `ball.serve()` | #294 | 既有调用（game_state_machine.gd:120，has_method 守卫） | ✅ 既有 |
| 计分信号链 | `ball.score` → ScoringManager → `scored.emit` | #385 | 既有信号流，不变 | ✅ 既有 |
| SCORED 球冻结 | FSM SCORED enter → `ball.set_frozen(true)` | #525 | 新增 `_freeze_ball(true)` 调用（复用 :227 helper） | ✅ 已实现 |
| 解冻契约 | `ball.serve()` 内 `frozen=false` | #391 AC4 | 保持（唯一解冻入口） | ✅ 既有 |
| MENU 球冻结 | FSM MENU enter → `ball.set_frozen(true)` | #508 | 既有（previous==MENU 守卫），不变 | ✅ 既有 |
| 得分路径发球 | `ball.gd` 3 处 `serve()` 调用 | #287→#525 | **删除**（回归 #294 编排收权） | ✅ 已实现 |

---

## 8. 实现阶段

| 阶段 | 优先级 | 组件 | 估计 |
|:----:|:------:|------|:----:|
| Phase 1 | P0 | ball.gd 删 3 处 serve() 调用；game_state_machine.gd SCORED 加 `_freeze_ball(true)` | 0.5 天 |
| Phase 2 | P0 | 新增 tests/test_ball_fsm_serve_race.gd + run_tests.gd 注册；全量回归 | 0.5 天 |

单 issue 原子修复（裁决 4），无跨阶段依赖。

---

## 9. 测试用例描述（实现阶段据此编写，不在此写可运行代码）

> 基线对照：修复前 main @ e7fd26c 全量 2354 passed / 0 failed；PRD §5.1 已实测方案 A 版 2367 passed / 0 failed（含 E2E playthrough、Auto-Play 100/100）。implement agent 在合并后 main 上重跑确认。

### Scenario A: 出界得分后球不自行飞行（AC1）—— 新测试文件 `tests/test_ball_fsm_serve_race.gd`
- **Test A-1（底部出界）**: 真实 ball.gd + 真实 FSM mini-tree，FSM 强制 PLAYING，球置 (360,330) 下落 → 强制 y=1300 出界（阈值 1290）。断言：`score` 信号触发 1 次（side==1）；进入 SCORED 后 `ball.frozen == true`；SCORED+SERVING 全程（≥2.0s，逐帧采样）`ball.position` 恒定（修复前对照：t=0.5 起自行位移）。
- **Test A-2（顶部出界）**: 同构，球向上出界 → `score` side==0，SCORED/SERVING 期间 position 恒定。
- **Test A-3（ScoreZone 路径）**: 经 `_on_score_zone`（area_entered）计分路径 → 同 A-1 断言（两条计分路径行为一致，PRD 边界 4）。

### Scenario B: 重发球时序不变（AC2）
- **Test B-1（时序）**: 出界后 t≈2.0s FSM `serve()` 回中（`position == (360, 640)`、`frozen == false`、`_is_serving == true`）；t≈2.5s 进 PLAYING、球起飞（速度非零）。
- **Test B-2（首次发球）**: MENU→SPACE→SERVING 流程（或等价 mini-tree）：serve() 由 FSM 调用，`_ready()` 首发球路径不受影响，球正常进入对打。

### Scenario C: 单次计分（AC3）
- **Test C-1（事件计数）**: 出界后 SCORED/SERVING 期间推进多帧 → `score` 信号仅 emit 1 次、`GameManager.add_score` 仅调用 1 次（比分与事件计数一致）。
- **Test C-2（无告警）**: 全程无 `scored signal received in state … ignoring` 告警（修复前实测出现 2 次，PRD §1.1.1）。

### Scenario D: 终局与重开回归
- **Test D-1（终局冻结）**: 21 分终局 → GAME_OVER，ball frozen（既有 test_failure_screen D-1/D-2 保持通过）。
- **Test D-2（重开解冻）**: GAME_OVER→MENU→SPACE 重开 → 球可动（#391 AC4 解冻契约保持）。

### Scenario E: 既有测试全量回归（AC4）
- **Test E-1**: `godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿（重点 watch：test_ball TC-E1/E2、test_game_state_machine、test_integration_fsm、auto_play、e2e_playthrough）。
- **Test E-2**: 新测试文件已在 run_tests.gd 注册并纳入统计（预期总数 2367+，以实际为准）。

---

## 10. 延续上下文（implement agent 交接）

### 系统状态

- **根因**：双发球竞态。`ball.gd` 得分路径自调 `serve()`（#287 遗留）与 FSM SCORED→SERVING 编排（#294）叠加 → 球在 SCORED/SERVING（挡板冻结）期间自行起飞飞行 ~1.5s。违反 DESIGN #294 状态表（SCORED/SERVING Ball Moving = No）。
- **基线**：main @ f94f0aa；PRD §5.1 实测：main @ e7fd26c 全量 2354 passed / 0 failed；方案 A scratch 应用版 2367 passed / 0 failed（含 E2E playthrough 91 passed、Auto-Play 100/100）。
- **Obsidian 知识搜索**（research 已完成）：vault 无 mini-pong 发球/重置设计笔记；发球交互设计意图以 DESIGN #294 为权威源（SPACE 仅 MENU/GAME_OVER；分间自动发球）。

### 修复指引（Approach A，已实测验证）

1. `mini-pong/gdscripts/ball.gd`：删除 3 处 `serve()` 调用（:180 上出界分支、:184 下出界分支、:193 `_on_score_zone`），只保留 `score.emit`。**不删 serve() 方法本体、不改 :84 `_ready()` 调用、不改 :93 `frozen = false` 行（#391 AC4 解冻契约）。**
2. `mini-pong/gdscripts/game_state_machine.gd`：`State.SCORED` enter_state 在 `_freeze_paddles(true)` 后加 `_freeze_ball(true)`（注释标注 #525 + #294 设计表）。
3. 新增 `tests/test_ball_fsm_serve_race.gd`（§9 Scenario A/B/C 描述）+ run_tests.gd 注册一行。
4. **回归验证**：`godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿；重点 watch test_ball（TC-E1/E2）、test_game_state_machine、test_integration_fsm、auto_play、e2e_playthrough。

### 红线

- ❌ 不删 `serve()` 方法本体 / 不改 `_ready()` 首发球 / 不改 `frozen=false` 行 / 不改 `_wait_for_serve()` 轮询
- ❌ 不修 PAUSED 冻结（关联面 #296，follow-up 候选，非本 issue）
- ❌ 不改变发球时序常量（SCORED 1s + SERVING 1s + SERVE_DELAY 0.5s，AC2）
- ✅ 「删 3 处调用」与「SCORED 冻结」必须同 PR 同改（裁决 4 原子性）

### 相关文档

- `docs/PRD/525-ball-fly-after-reset.md`（本设计父文档；含 headless 复现时间线 §1.1.1 与方案对比 §4）
- `docs/DESIGN/294-game-state-machine.md`（发球编排权威源；状态表 Ball Moving=No）
- `docs/DESIGN/287-ball-physics.md`（ball 自管 serve 来源）
- `docs/PRD/508-title-screen-world-bleed.md`（#508 MENU 冻结球 —— 同源「非 PLAYING 球失控」模式）
- `docs/DESIGN/385-dual-scoring-system.md`（出界分 → SCORED 流）
