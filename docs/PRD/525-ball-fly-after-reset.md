# PRD: [Bug] 游戏重置后，无操作下，有小球意料之外飞行

> **Issue:** #525
> **标签:** bug, workflow/research（任务指派：workflow/available → workflow/research，2026-08-17 认领）
> **Agent:** game-research-agent
> **日期:** 2026-08-17
> **深度:** light（Issue body「工作深度: light（简单修复，快速完成）」；无 depth/ 标签，按 body 声明 light：Section 1–5 + 8 必填；6/7 跳过并注明）
> **所有权:** `content_ownership: mechanical`（确定性时序修复：发球编排竞态 = 机械可测，无品味决策）
> **来源:** 任务指派（game-research-agent）
> **前置依赖:** 无（独立 bug；依赖既有 FSM #294、球物理 #287、双得分 #385、#508 MENU 冻结球上下文）

---

## 1. 问题定义

### 1.1 当前状态

**核心发现：双发球竞态（double-serve race）—— ball.gd 的得分路径自己调用 `serve()`（#287 球自管发球遗留），与 FSM 的 SCORED→SERVING 重发球编排（#294）叠加：球出界得分后 0.5s（`SERVE_DELAY`）即自行起飞，此时 FSM 正处于 SCORED/SERVING、挡板冻结，球在无任何输入下自由飞行 ~1.5s（本实测中向下坠落 → 即报告所述「有小球落下」），直到 FSM 的 `serve()` 在 ~2.0s 将其拉回中心重新发球。违反 DESIGN #294 状态表：SCORED/SERVING 两态 Ball Moving = **No**（`_is_serving`）。**

#### 预调查结果（bug pre-investigation，Patch 10 — 逐条核对 issue 声明 vs 当前源码 + headless 实测）

| # | Issue 声明 | 状态 | 证据 |
|---|-----------|------|------|
| 1 | 球飞出后游戏局重置 | ✅ **确认** | 出界 → `ball.score(side)` → ScoringManager → `scored` → FSM SCORED（#385 边界 8：出界分走 SCORED→重发球流）。`scoring_manager.gd:72` |
| 2 | 没有任何操作，有小球落下 | ✅ **确认（根因）** | 双 serve 竞态：`ball.gd` 得分路径自调 `serve()`（`_process` 上下出界分支 :178-184、`_on_score_zone` :189-193，均为 #287 遗留）；serve() 0.5s 后自动起飞。headless 实测（真实 ball.gd + 真实 FSM，2026-08-17）时间线见 §1.1.1 |
| 3 | 再按 space 可开球 | ⚠️ **澄清（非缺陷）** | SPACE（ui_accept）仅在 MENU / GAME_OVER 生效（#294 输入路由，`game_state_machine.gd:66-86`）；分间发球为**自动**（街机节奏，#294 设计表 SERVING 无输入）。「space 可开球」对应 MENU/GAME_OVER 流程，正常。若诉求是「分间也按 space 开球」（经典乒乓操作），属设计变更，超出本 light bug 修复范围 → 见 §8 follow-up |
| 4 | 工作深度 light | ✅ 确认 | 按 light 处理（Section 1–5 + 8） |
| 5 | Depends on: #（空） | ✅ 确认 | 无前置依赖 |

#### 1.1.1 Headless 实测复现（真实 ball.gd + game_state_machine.gd，主场景同构 mini-tree，2026-08-17）

场景：FSM 强制 PLAYING、球以 (0,330) 下落 → 强制 y=1300 出界（阈值 1290）→ 观察 3.5s。**修复前（main @ e7fd26c）：**

| t (s) | FSM 状态 | 球位置 | 球速 | 挡板 | 说明 |
|-------|---------|--------|------|------|------|
| 0.00 | SCORED | (360,640) | 0 | 冻结 | 出界得分 0:1，ball 自 serve() 回中 |
| 0.50 | SCORED | (351,659) | -139 | 冻结 | **ball 自 serve 定时器触发，自行起飞** |
| 1.00 | SCORED | (279,813) | -139 | 冻结 | 飞行中（无输入、挡板冻结） |
| 1.50 | SERVING | (208,964) | -139 | 冻结 | 继续下落 → 「有小球落下」 |
| 2.00 | SERVING | (360,640) | 0 | 冻结 | FSM serve() 拉回中心 |
| 2.50 | PLAYING | (370,660) | 150 | 解冻 | 重发球，恢复对打 |

用户可见行为 = 报告描述：「球飞出 → 重置 → 无操作下球自行落下 → （2.5s 后）重新开球」。此外实测 v1（未注入屏幕尺寸）还捕获到 **SCORED/SERVING 期间重复 score 事件**（`FSM: scored signal received in state 4/1 — ignoring` 告警 ×2）→ 存在重复计分风险（本实测几何下被 t=2.0 回中恰好化解，非可靠保证）。

### 1.2 预期行为（验收条件，源自 Issue #525）

1. [ ] **AC1** 出界得分后、重发球前，球不自行飞行（SCORED/SERVING 全程球静止/停在出界位，挡板冻结期无任何球位移）
2. [ ] **AC2** 分间自动重发球时序不变（SCORED 1s → SERVING 1s → serve 0.5s → PLAYING，~2.5s 恢复对打）
3. [ ] **AC3** 一球只计一次分：无 SCORED/SERVING 期间重复出界事件、无重复 add_score（比分与事件计数一致）
4. [ ] **AC4** 完整 run 可达 21 分终局（回归：auto-play 100 局 / E2E playthrough 通过）

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| 1 | 玩家失误丢分 | 每局多次 | 球飞出底线 → 重置期球自行下落/飞行，玩家误以为游戏失控或球未复位 |
| 2 | AI 丢分 | 每局多次 | 球飞出顶线 → 同上（向上飞行） |
| 3 | 重置期与球交互 | 每次重置 | 玩家尝试按 space 开球（无响应——SCORED 无输入）或尝试接球（挡板冻结）→ 挫败感 |

---

## 2. 设计意图

### 2.1 为什么当前状态存在

| 贡献者 | 决策 | 后果 |
|--------|------|------|
| #287（ball 自管物理+发球） | `ball.gd` 得分路径自调 `serve()`（出界即回中+0.5s 后起飞） | 发球权留在 ball 内部——球自己决定何时起飞 |
| #294（FSM 集中编排） | 移除 `scoring_manager._pause_and_serve()` 的发球逻辑，发球编排收归 FSM（SCORED→SERVING→serve()）；DESIGN 表明确 SCORED/SERVING Ball Moving = No | 发球编排出现**双调用方**：FSM 的 SERVING serve() 与 ball 得分路径的 serve() 竞争；且 SCORED 实现只冻结挡板、未落实「球不移动」 |
| #294 实现遗漏 | SCORED enter_state 仅 `_freeze_paddles(true)`，无 `_freeze_ball` | 球在 SCORED 期间保留速度，一旦被 serve() 触发即自由飞行 |
| #508（MENU 冻结球，2026-08-17） | 只修了初始 MENU（previous==MENU）冻结球；GAME_OVER→MENU 路径按 #391 AC4 不冻结 | 与本 issue 同源模式：球状态机在非 PLAYING 状态失控，本次是 SCORED/SERVING 面 |

### 2.2 为什么现在改

1. **用户报告**（#525）——重置期无操作球自行飞行，直接违背 #294 设计表「SCORED/SERVING Ball Moving = No」
2. **修复面极小**（3 处删除 + 1 行冻结，方案 A）——light 深度下可快速完成
3. **潜在分数正确性风险**——竞态窗口内重复 score 事件可能导致重复计分（§1.1.1）
4. **与 #508 同源**——都是「球在非 PLAYING 状态失控」，修复模式可复用（软冻结）

### 2.3 既有约束

| 约束 | 详情 |
|------|------|
| #294 发球编排归 FSM | 发球节奏（SCORED 1s + SERVING 1s + SERVE_DELAY 0.5s）不得改变（AC2） |
| #391 AC4 | GAME_OVER 退出必须解冻球（SPACE → MENU → 新 run 球可动）；`serve()` 内 `frozen=false` 是解冻唯一入口，不得移除 |
| #508 | 初始 MENU（previous==MENU）冻结球；GAME_OVER→MENU 不冻结——维持现状 |
| #385 双得分制 | 出界分走 SCORED→重发球流；`scored` 信号语义不变 |
| #383 竖屏 | 发球/出界几何（720x1280）不变 |
| 测试兼容 | test_ball TC-E1/E2 仅断言 score 信号（无 serve 后位置断言）；auto_play 已绕开 `ball._process`；FSM 测试用无 serve 方法的 mock ball——均不受方案 A 影响 |

---

## 3. 影响分析

### 3.1 直接修改文件

| 文件 | 模块 | 改动性质 |
|------|------|---------|
| `mini-pong/gdscripts/ball.gd` | 球物理 | 删除 3 处得分路径的 `serve()` 调用（`_process` 出界上分支 :180、下分支 :184、`_on_score_zone` :193），只保留 `score.emit(side)`；`serve()` 方法本体与 `_ready()` 调用不变（FSM 仍调用） |
| `mini-pong/gdscripts/game_state_machine.gd` | FSM | `SCORED` enter_state 新增 1 行 `_freeze_ball(true)`（对齐 #294 设计表；serve() 内 `frozen=false` 在 SERVING 重发球时解冻） |

### 3.2 新文件

无。

### 3.3 间接影响

| 模块 | 影响 |
|------|------|
| `scoring_manager.gd` | 无改动。信号流 `ball.score → _on_ball_score → add_score + scored.emit` 不变；SCORED 冻结后球不再产生重复出界事件（修复副收益） |
| `game_manager.gd` | 无改动。add_score 调用次数由 ScoringManager 决定，竞态消除后天然单次 |
| `test_ball.gd` | TC-E1/E2 只断言 score 信号，删除 serve() 调用不影响（无「得分后位置复位」断言） |
| `test_game_state_machine.gd` / `test_integration_fsm.gd` | mock ball 无 serve() 方法，FSM 分支走 `has_method` 守卫——不受影响 |
| `auto_play_test.gd` | 已绕开 `ball._process`（手动物理），不受影响 |
| `e2e_playthrough.gd`（真实 Main.tscn 全链路） | 重发球经 FSM SCORED→SERVING 路径，方案 A 下球在 SCORED 冻结、SERVING 由 serve() 解冻回中——行为等价且更干净；AC3-T5 的 `_crossed_wall` 断言（信号在 serve() 复位前同步触发）仍成立（复位更晚，更稳） |
| `GAME_OVER→MENU→SERVING` 重开路径 | 终局分后 serve() 未跑 → 球冻结在出界位；GAME_OVER exit 解冻（#391 AC4）→ MENU 中球不可见（#508 世界隐藏）且 SERVING 的 serve() 会回中——与现状一致，非回归 |

### 3.4 数据流（修复后）

```
Ball._process 出界（或 ScoreZone area_entered）
    │  score.emit(side)                        ← serve() 已移除（原在此处自起飞）
    ▼
ScoringManager._on_ball_score(side)
    ├── GameManager.add_score(winner, amount, kind)   ← 单次（球已冻结，无重复出界）
    └── scored.emit(winner)
            ▼
FSM._on_scored(winner)  [PLAYING 时]
    └── SCORED: 挡板冻结 + 球冻结（新增）→ 1s
            └── SERVING: 1s → ball.serve()（回中 + frozen=false + 0.5s 起飞）
                    └── _wait_for_serve() → PLAYING（挡板解冻）
```

### 3.5 文档更新

- [x] 本 PRD（docs/PRD/525-ball-fly-after-reset.md）
- [ ] DESIGN #294 无改动（设计表本就是 Ball Moving=No——本次是让实现回归设计）
- [ ] GDD 无改动（无新系统/新常量）

---

## 4. 方案对比

### Approach A：FSM 独占发球编排 + SCORED 冻结球（推荐）

**描述：** 完成 #294 的编排收权——ball 得分路径不再自调 `serve()`（只 emit 信号）；FSM `SCORED` 状态冻结球（与 #508 MENU 冻结同模式）。修复 = ball.gd 删 3 处调用 + FSM 加 1 行。

**Pros:**
- 根治竞态：发球调用方唯一（FSM），与 #294「集中编排」哲学一致（#294 当年已移除 scoring_manager 的发球逻辑，ball 自身调用是同款遗留）
- 严格回归 #294 设计表（SCORED/SERVING Ball Moving = No）
- 修复面最小（4 行），light 深度匹配
- 消除重复计分风险与 SCORED 期间撞砖副作用（球冻结后无位移）

**Cons:**
- SCORED 期间球停在出界位（屏幕外），玩家看不到「球在中心等待」——视觉上球消失 ~2s 后回中重发（经典乒乓球出界即离场，可接受）

**Risk:** Low（改动面 4 行；SERVING 的 serve() 是既有解冻入口；测试面分析见 §3.3）
**Effort:** 0.5–1 天（含回归测试）

### Approach B：得分路径改为「待发球态」（新增 reset_for_serve()）

**描述：** ball 得分路径调用新方法 `reset_for_serve()`（回中 + 零速 + `_is_serving=true`，不自动起飞），由 FSM 的 serve() 完成最终起飞。

**Pros:**
- SCORED 期间球可见停在中心（经典乒乓观感，比 A 更「好看」）

**Cons:**
- 新增 API + 2 处调用替换，改动面 > A
- 仍需 SCORED 冻结兜底（否则 `_process` 中 `_is_serving` 之外的位移路径…实际零速+_is_serving 已够，但防御性冻结更稳）
- 观感差异是品味问题（`content_ownership: mechanical` 边界外），light 修复不宜引入

**Risk:** Low-Med（新增代码路径需测试覆盖）
**Effort:** 1 天

### Approach C：仅 SCORED 加冻结、不删 ball 自 serve（**不可行**）

**描述：** 只在 FSM SCORED 加 `_freeze_ball(true)`。

**验证结论（源码推理）：** `serve()` 内 `frozen = false`（ball.gd:93，防御性复位）——SCORED 冻结发生在 `score.emit` 信号链内，随后 ball 得分路径的 `serve()` 立即把 `frozen` 复位为 false → 0.5s 后照常起飞，**冻结被覆盖，方案无效**。若要生效需改 serve() 语义（破坏 #391 AC4 解冻契约）或改调用顺序（复杂化）。

**Risk:** High（无效或引入回归）
**Effort:** —（否决）

### 推荐：Approach A

1. 根因对齐：#294 的设计意图就是「FSM 编排发球」——A 是补完迁移，非新机制
2. 最小改动（4 行），light 深度、机械可测
3. 实测验证：scratch worktree 应用 A 后 headless 复跑同一场景，SCORED/SERVING 全程球静止（frozen=true、位置恒定），t=2.0 回中、t=2.5 PLAYING，比分 0:1 单次计分——修复有效（§5.1 证据）
4. 方案 C 经源码推理否决；方案 B 的观感增益属品味域，留给后续 taste issue（§8 follow-up）

---

## 5. 边界条件与验收标准

### 5.1 正常路径（AC 映射）

- [x] **AC1（球不自行飞行）** — 出界得分 → SCORED 冻结 → SERVING 保持冻结 → 无任何位移。验证：headless 复现脚本 3.5s 观察，SCORED/SERVING 期间 `ball.position` 恒定、`ball.frozen == true`（修复后实测通过，§1.1.1 对照表）
- [x] **AC2（重发球时序不变）** — t=2.0 FSM serve() 回中+解冻，t=2.5 起飞进 PLAYING（修复后实测：t=2.00 pos=(360,640) serving=true → t=2.50 PLAYING）✓
- [x] **AC3（单次计分）** — 修复后实测比分 0:1，无重复 score 事件（对照：修复前 v1 实测出现 2 次 `scored signal received in state … ignoring` 告警）
- [x] **AC4（21 分 run 完整）** — 回归验证：`godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿——基线 2354 passed / 0 failed（main @ e7fd26c）；方案 A scratch 应用版 2367 passed / 0 failed（含 E2E playthrough 91 passed、Auto-Play 100/100，2026-08-17 实测）

### 5.2 边界情况

1. **MENU 开局首次发球**（MENU→SERVING）：serve() 仍由 FSM 调用（`game_state_machine.gd:119-120`），`_ready()` 的首发球不受影响——方案 A 只删得分路径调用
2. **终局分（21 分）→ SCORED → GAME_OVER**：SCORED 冻结与 GAME_OVER 冻结幂等叠加；GAME_OVER exit 解冻（#391 AC4）供下一 run
3. **GAME_OVER→MENU 重开**：球停在出界位、MENU 中不可见（#508 世界隐藏）；SPACE→SERVING 时 serve() 回中——行为与现状一致（非回归）
4. **ScoreZone 路径**（area_entered 计分）：与 Y 边界路径同样删除 serve()、同样冻结——两条计分路径行为一致
5. **headless 测试**：serve() 无 tree 立即路径不受影响（移除的是调用点，非 serve 本体）；FSM 测试 mock ball 无 serve() → `has_method` 守卫跳过
6. **PAUSED 出界**（关联面，不修）：PAUSED enter 无 `_freeze_ball`（`game_state_machine.gd:128-133`），球暂停期继续移动（#296 软冻结只冻挡板）；出界时 FSM 忽略 scored（warning）——既有行为，建议 follow-up（§8）
7. **重复计分防护**：修复后球冻结，出界事件单次——`_scored_this_frame` 帧守卫继续兜底双触发

### 5.3 失败路径

1. **只加 SCORED 冻结、不删 ball 自 serve（方案 C）** → `serve()` 内 `frozen=false` 覆盖冻结 → 球照常起飞，修复无效（源码推理否决，§4）
2. **只删 ball 自 serve、不加 SCORED 冻结** → 球带速度停在出界位，下一帧 `_process` 再次触发出界 → 重复 `score.emit` + `add_score`（FSM 忽略但分数膨胀）→ 必须「删调用 + 冻结」同改（方案 A 原子性）
3. **破坏 `_wait_for_serve()` 轮询**（若误改 serve() 的 `_is_serving` 语义）→ SERVING 卡死无法进 PLAYING → 保留 `serve()` 本体与 `_is_serving` 契约不变（方案 A 不触碰）

---

## 6. 依赖与阻塞

> **Skipped per depth/light label**（§8 延续上下文已含实现所需全部信息；无跨 issue 依赖——独立 bug，依赖既有 #294/#385/#508 基础设施均已合入 main）

---

## 7. Spike / 实验

> **Skipped per depth/light label。** 研究期已执行等价实验：headless 真实组件复现（修复前/后对照，§1.1.1/§5.1）+ 方案 C 源码推理否决（§4）。无需额外 spike。

---

## 8. 延续上下文（plan agent 交接）

### 系统状态

- **根因**：双发球竞态。`ball.gd` 得分路径自调 `serve()`（#287 遗留）与 FSM SCORED→SERVING 编排（#294）叠加 → 球在 SCORED/SERVING（挡板冻结）期间自行起飞飞行 ~1.5s。违反 DESIGN #294 状态表（SCORED/SERVING Ball Moving = No）。
- **Obsidian 知识搜索**（任务要求，2026-08-17）：vault `~/Documents/Obsidian Vault/wiki/` 搜索「乒乓/pong/发球/serve/开球/小球/重置/游戏节奏」——无 mini-pong 发球/重置相关设计笔记（仅命中无关概念「小球=猫兵」及 CUSGA 笔记）；发球交互设计意图以仓库 DESIGN #294 为权威源（SPACE 仅 MENU/GAME_OVER；分间自动发球）。
- **基线**：main @ e7fd26c 全量测试 2354 passed / 0 failed；**方案 A scratch 应用版全量测试 2367 passed / 0 failed**（2026-08-17 实测，含 E2E playthrough + Auto-Play 100/100）。

### 修复指引（Approach A，已实测验证）

1. `mini-pong/gdscripts/ball.gd`：删除 3 处 `serve()` 调用——`_process` 顶部出界分支（`score.emit(0)` 后）、底部出界分支（`score.emit(1)` 后）、`_on_score_zone`（`score.emit(side)` 后）。只保留 emit。**不删 `serve()` 方法本体、不改 `_ready()` 调用、不改 `frozen=false` 行（#391 AC4 解冻契约）。**
2. `mini-pong/gdscripts/game_state_machine.gd`：`State.SCORED` enter_state 在 `_freeze_paddles(true)` 后加 `_freeze_ball(true)`（注释标注 #525 + #294 设计表）。
3. **回归验证**：`godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿；重点 watch test_ball（TC-E1/E2）、test_game_state_machine、test_integration_fsm、auto_play、e2e_playthrough。
4. **新增回归测试建议**（plan agent 决定归属）：headless 场景「PLAYING 出界 → SCORED/SERVING 期间 `ball.position` 恒定 + `frozen=true` + 单次计分」断言（本 PRD 复现脚本模式可移植）。

### 主要风险

- 低：改动 4 行，测试面已分析（§3.3）；SERVING serve() 是既有解冻入口，时序不变（AC2 实测保持）
- 中（关联面，非本 issue）：PAUSED 未冻结球（#296）——ball 暂停期继续移动，出界时 FSM 忽略计分；建议 follow-up issue（若用户在意）
- 设计问题（follow-up 候选）：分间发球是否改为「按 SPACE 开球」（经典乒乓）——当前为自动（#294 街机节奏）；若采纳需设计变更，建议单独 taste/design issue

### 相关文档

- `docs/DESIGN/294-game-state-machine.md`（发球编排权威源；状态表 Ball Moving=No）
- `docs/DESIGN/287-ball-physics.md`（ball 自管 serve 来源）
- `docs/PRD/508-title-screen-world-bleed.md`（#508 MENU 冻结球——同源模式）
- `docs/DESIGN/385-dual-scoring-system.md`（出界分 → SCORED 流）
