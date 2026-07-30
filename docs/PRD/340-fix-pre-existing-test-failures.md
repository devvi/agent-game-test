# PRD: [Bug] 修复 main 分支上 5 个预存测试失败

> **Issue:** #340
> **标签:** bug, workflow/research, depth/standard, priority/high, version/v1
> **Agent:** game-research-agent
> **日期:** 2026-07-30
> **前置依赖:** #294 (Game State Machine — CLOSED ✅), #291 (Scoring System — CLOSED ✅), #293 (GameManager — CLOSED ✅)

---

## 1. 问题定义

### 当前状态

在 main 分支（fset:a84c7a6b）运行 `godot --path mini-pong/ --headless --script tests/run_tests.gd` 结果：**874 passed, 5 failed**。

5 个失败测试分布在两个测试套件中：

| # | 测试 | 套件 | 预期 | 实际 | 根因 |
|---|------|------|------|------|------|
| TC11 | `_test_tc11_headless_no_tree` | test_scoring_manager.gd | `ball.serve()` 被调用（serve_count>0） | serve_count=0 | `scoring_manager._pause_and_serve()` 现在是 no-op（`pass`），因为 FSM #294 接管了发球时机 |
| TC6.1 | `_test_tc6_on_scored_in_playing` | test_game_state_machine.gd | `current_state == SCORED` 在 scored 信号后 | current_state 变为 SERVING | 在 headless 模式（节点不在场景树中），`enter_state(SCORED)` 跳过 `await _timer_1s()`，SCORED→SERVING 同步发生 |
| TC8.1 | `_test_tc8_double_space_transition_lock` | test_game_state_machine.gd | 第一次 SPACE 后 `_transition_lock == true` | lock 为 false | `_input()` 设置 lock=true，然后调用 `transition_to(SERVING)` → `enter_state(SERVING)` 末尾 `_transition_lock = false` — headless 中同步完成 |
| TC8.2 | `_test_tc8_double_space_transition_lock` | test_game_state_machine.gd | 第二次 SPACE 被锁阻挡 | 第二次 SPACE 未被阻挡 | 与 TC8.1 相同：lock 已被 `enter_state(SERVING)` 重置 |
| TC16.1 | `_test_tc16_reset_match_on_serving` | test_game_state_machine.gd | `GameManager.reset_match()` 在进入 SERVING 时被调用 | reset_match 未被调用 | `Engine.register_singleton("__test_fsm__", self)` 失败 — 测试套件继承 `RefCounted`，Godot 4.x 不支持 RefCounted 单例 |

### 预调查结果

以下表格汇总了预调查中的根因分析：

| 失败测试 | 涉及生产代码 | 生产代码行 | 机制 | Headless 特殊行为 |
|---------|-------------|-----------|------|------------------|
| TC11 | scoring_manager.gd | L105-108 | `_pause_and_serve()` → `pass` | N/A — 代码就是 no-op |
| TC6.1 | game_state_machine.gd | L129-140 | `enter_state(SCORED)` → `await _timer_1s()` → `transition_to(SERVING)` | `_timer_1s()` 在 headless 中跳过 await，SCORED→SERVING 同步 |
| TC8.1/8.2 | game_state_machine.gd | L70-72, L109 | `_input()` lock=true → `transition_to(SERVING)` → `enter_state` lock=false | SERVING 进入在 headless 中同步重置 lock |
| TC16.1 | game_state_machine.gd | L101-102 + test L145 | `enter_state(SERVING)` → `GameManager.reset_match()` | 测试中 `RefCounted` 单例注册失败 |

### 预期行为

1. **全部 5 个测试通过** — 测试套件回归绿色
2. **测试反映当前代码行为** — 不恢复已废弃的生产代码逻辑（如 `_pause_and_serve()` 中的 ball.serve()），因为该逻辑已被 FSM #294 替代
3. **生产代码行为不变** — 仅修改测试，不改动 `scoring_manager.gd` 或 `game_state_machine.gd` 的功能路径
4. **Headless 测试友好** — 测试必须能在 `--headless --script` 模式下正确执行

### 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | CI 运行测试 | 每次提交/PR | 所有测试通过，无假阳性 |
| B | 开发者本地运行测试 | 日常 | `godot --headless --script tests/run_tests.gd` 输出 `879 passed, 0 failed` |
| C | 新贡献者添加测试 | 偶尔 | 测试套件模式清晰，易于复制和扩展 |

### 范围边界

| 包括 | 不包括 |
|------|--------|
| 修复 TC11, TC6.1, TC8.1, TC8.2, TC16.1 | 添加新测试覆盖 #294 或 #291 功能 |
| 更新测试以匹配当前代码行为 | 修改生产代码（scoring_manager.gd, game_state_machine.gd） |
| 确保 headless 测试模式正常工作 | 运行时/场景树测试 |
| 修复测试套件基类（RefCounted → Object） | 重构测试框架 |

### 范围边界 vs 重叠 PRD

| PRD | Covers | NOT covered (left to this PRD) |
|-----|--------|--------------------------------|
| #294 游戏状态机 | FSM 实现 — 5 状态枚举、`enter_state`/`exit_state`、输入门控 | ❌ FSM 测试的维护 — #294 的测试编写时假设了运行时行为，未考虑 headless 同步执行 |
| #291 计分系统 | ScoringManager 实现 — `_on_ball_score()`、`_win_game()`、信号链 | ❌ ScoringManager 测试的维护 — #291 后续 FSM #294 移除了 `_pause_and_serve()` 中的 `ball.serve()`，但测试未更新 |
| #293 GameManager | 全局状态 autoload — `reset_match()`、`get_winner()`、`add_score()` | ❌ 测试中 GameManager 的 mock 机制 |

**本 PRD 是测试维护任务** — 它不涉及功能开发或架构设计。它只修复因 FSM #294 和计分系统 #291 的实现导致测试与当前代码行为不同步的 5 个测试失败。

---

## 2. 设计意图

### 为什么当前行为存在

这些测试是在 FSM #294 和计分重构 #291 之前编写的。测试编写时假设了以下行为，但这些行为已被后续 PR 的代码修改打破：

| 变更来源 | Issue | 对测试的影响 |
|---------|-------|------------|
| FSM 接管发球时机 | #294 | `scoring_manager._pause_and_serve()` 从 `await timer → ball.serve()` 变为 `pass`（no-op）。FSM 的 `enter_state(SERVING)` 现在负责 `ball.serve()` 调用（game_state_machine.gd:104-105） |
| FSM 在 headless 中同步执行 | #294 | `_timer_1s()` 在 headless 模式跳过 await（game_state_machine.gd:193-197），导致 SCORED→SERVING 在 `_on_scored()` 返回前同步完成 |
| FSM `enter_state(SERVING)` 重置 `_transition_lock` | #294 | `_transition_lock = false` 在 line 109 执行，在 `await _timer_1s()` 和 `ball.serve()` 之后 — headless 中这些同步执行，lock 立即重置 |
| Godot 4.x 不支持 RefCounted 单例 | Godot 4.x | `Engine.register_singleton(name, refcounted_instance)` 静默失败，返回的 `Engine.get_singleton()` 为 null |

### 为什么现在修复

1. **Blocked PRs:** #338 (impl/296-pause-and-sound) 和 #339 (impl/295-main-scene-assembly) 被这 5 个测试失败阻塞。修复这些测试后，stalled scan 将检测到 main 分支变绿，重新触发 blocked PR 审查
2. **CI 可靠性:** 5 个假阳性失败降低了 CI 的信噪比 — 开发者必须手动区分"真正的回归"和"已知的测试不同步"
3. **技术债务:** 测试与代码行为脱节会随着更多 PR 合并而恶化。每次新增功能都可能引入额外的测试-代码同步问题

### 先前约束

| 约束 | 详情 |
|------|------|
| **不修改生产代码功能路径** | FSM #294 和计分系统 #291 的行为已被游戏测试验证正确。修复方向是更新测试，不回溯生产代码 |
| **Headless 测试兼容** | 测试必须在 `--headless --script` 下运行。任何依赖 `await`/`get_tree()` 的测试逻辑必须处理 headless 同步回退 |
| **测试套件继承限制** | Godot 4.x 不支持 RefCounted 单例。测试套件应继承 `Object` 而非 `RefCounted`（如果使用 `Engine.register_singleton()`） |
| **向后兼容** | 修复不应破坏已有通过的测试（874 个测试保持通过） |

---

## 3. 影响分析

### 直接受影响的模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `tests/test_scoring_manager.gd` | Scoring Manager 测试套件 | TC11 断言逻辑修改 — 移除 `ball.serve()` 调用预期 |
| `tests/test_game_state_machine.gd` | Game State Machine 测试套件 | TC6.1/TC8.1/TC8.2 断言修改；TC16.1 mock 机制重写 |
| `tests/test_scoring_manager.gd` L1 | 测试套件基类 | 无需变更（该套件继承 RefCounted 但不使用单例） |

### 需新建的文件

无。仅修改现有测试文件。

### 间接受影响的模块

无 — 改动仅限测试文件，不影响生产代码。

### 数据流影响

**当前测试数据流（TC8.1/8.2 锁测试 — 已中断）：**

```
测试调用 fsm._input(event)
    │
    ├── _input() 设置 _transition_lock = true (line 71)
    ├── _input() 调用 transition_to(State.SERVING) (line 72)
    │       └── enter_state(State.SERVING)
    │           ├── _set_ui("hud")
    │           ├── _freeze_paddles(true)
    │           ├── GameManager.reset_match()
    │           ├── await _timer_1s()              ← headless: 跳过
    │           ├── ball.serve()                   ← headless: 立即执行（若 ball mock 有 serve）
    │           └── _transition_lock = false       ← headless: 立即执行，在 _input 返回前
    │
    └── 测试检查 _transition_lock == true  ← ❌ 失败：lock 已是 false
```

**修复后的测试数据流：**

```
测试调用 fsm._input(event)
    │
    ├── _input() 设置 _transition_lock = true
    ├── _input() 调用 transition_to(State.SERVING)
    │       └── enter_state(State.SERVING) — 同步重置 lock
    │
    └── 测试检查 fsm.current_state == State.SERVING  ← ✅ 验证转换已发生
    └── 测试检查 lock 在进入 SERVING 后被重置  ← ✅ 验证预期的 FSM 行为
```

### 需更新的文档

- [x] `docs/PRD/340-fix-pre-existing-test-failures.md` — 本 PRD
- [ ] `docs/GAME_DESIGN/INDEX.md` — 无需更新（无新功能）
- [ ] `mini-pong/tests/run_tests.gd` — 无需更新（测试数量不变）

---

## 4. 解决方案比较

### 方法 A：仅修复测试（推荐）

**描述：** 更新测试以反映 headless 模式下 FSM 和 ScoringManager 的实际运行时行为。不改动任何生产代码。

**每个失败的修复方案：**

| 测试 | 修复策略 | 具体改动 |
|------|---------|---------|
| TC11 | 移除对 `ball.serve()` 调用的断言 | 将该测试改为验证 `_pause_and_serve()` 不崩溃（no-op 是正确的行为），或者移除该测试 |
| TC6.1 | 更改断言以检查 `current_state == SERVING` | 在 headless 中 SCORED→SERVING 同步发生 — 检查最终状态而非瞬时状态 |
| TC8.1 | 更改断言以验证 `_transition_lock == false` | lock 在 `enter_state(SERVING)` 中同步重置 — 这是正确的 FSM 行为 |
| TC8.2 | 更改断言以验证 `current_state == SERVING` | 第二次 SPACE 不应被阻挡（因为 lock 已被重置）— 验证状态已是 SERVING |
| TC16.1 | 将测试套件基类从 `RefCounted` 改为 `Object` | Godot 4.x 不支持 RefCounted 单例 — 继承 `Object` 使 `Engine.register_singleton()` 成功 |

**优点：**
- 零风险 — 不改动生产代码
- 测试反映实际代码行为，消除假阳性
- 改动范围极小（~15 行断言修改 + 1 行基类修改）
- 符合 PRD #294 的架构决定（FSM 负责发球时机）

**缺点：**
- TC8.1/8.2 不再验证 SPACE 双重按压保护 — 但该保护在生产环境中靠 `await _timer_1s()` 实现，在 headless 中不存在此延迟
- 失去了对 `_transition_lock` 中间状态的测试覆盖 — 但可以通过新的 headless 感知测试单独添加

**风险：** 低
**工作量：** <1 小时

### 方法 B：在生产代码中添加 headless 回退

**描述：** 修改 `scoring_manager.gd` 和 `game_state_machine.gd`，添加 headless 模式检测，使测试能通过而不改变运行时行为。

| 测试 | 修复策略 |
|------|---------|
| TC11 | 在 `_pause_and_serve()` 中添加 `if not is_inside_tree(): ball.serve()` 回退 |
| TC6.1 | 在 `enter_state(SCORED)` 中添加 headless 标志，延迟 SCORED→SERVING 转换 |
| TC8.1/8.2 | 在 `_input()` 或 `enter_state(SERVING)` 中保留 `_transition_lock`，如果 headless |
| TC16.1 | 在测试中保留 RefCounted，改用回调注入代替单例 |

**优点：**
- 测试不改动（或改动更少）
- 保留了 `_transition_lock` 的中间状态验证

**缺点：**
- **生产代码中引入仅用于测试的条件分支** — 违反"测试不应改变生产代码结构"原则
- 增加 `is_inside_tree()` / headless 模式检测的维护负担
- 生产代码中的测试专用路径可能与实际游戏行为偏离
- FSM #294 明确将发球时机移到 FSM — 在 ScoringManager 恢复此逻辑违反了架构意图

**风险：** 中（可能引入仅在 headless 路径中存在的 bug）
**工作量：** 2-3 小时

### 方法 C：重写测试使用场景树（启动 mini-pong 主场景）

**描述：** 将测试从纯 headless 模式改为启动 `Main.tscn`，在完整场景树中运行测试，消除 headless vs 运行时行为差异。

**优点：**
- 测试环境与实际运行环境一致
- 不需要特殊 headless 处理
- `await` 行为与生产环境完全一致

**缺点：**
- **大幅增加测试复杂度** — 需要加载完整场景、等待节点就绪、管理场景生命周期
- 测试运行时间显著增加（每次测试需要加载场景 + await 定时器）
- 需要重写所有 FSM 测试（~400 行）
- CI 运行时间从秒级变为分钟级

**风险：** 高（大规模重写）
**工作量：** 1-2 天

### 推荐方案

**推荐方法 A：仅修复测试。**

理由：
1. **最小改动原则** — 5 个失败源于测试与代码不同步，而非代码逻辑错误
2. **FSM #294 架构正确** — `_pause_and_serve()` 变为 no-op 是正确的；发球时机属于 FSM 职责。恢复旧逻辑会违反架构边界
3. **Headless 同步行为是预期行为** — `_timer_1s()` 设计为在 headless 中跳过（game_state_machine.gd:197 注释："Headless: skip timer, proceed immediately"）。测试应反映此预期
4. **TC16.1 的修复（RefCounted → Object）是必要的工程修复** — 与当前代码行为无关，而是 Godot 4.x API 使用错误
5. **方法 C 过度工程** — headless 测试的价值正是其速度和简单性；加载完整场景破坏了这一优势

---

## 5. 边界条件与验收标准

### 验收标准

- [ ] **AC1: TC11 通过** — `test_scoring_manager.gd` 中所有测试通过（0 failed）
  - TC11 改为验证 `_pause_and_serve()` 正确执行 no-op（不崩溃）
  - 或者移除 TC11（因为 `_pause_and_serve()` 的旧行为已被 FSM #294 替代）
- [ ] **AC2: TC6.1 通过** — SCORED 信号后 `current_state` 验证为 `SERVING`（headless 中同步转换）
- [ ] **AC3: TC8.1 通过** — 第一次 SPACE 后验证 `_transition_lock == false`（已被 `enter_state(SERVING)` 重置）或验证 `current_state == SERVING`
- [ ] **AC4: TC8.2 通过** — 第二次 SPACE 验证状态已为 `SERVING`（不被锁阻挡）
- [ ] **AC5: TC16.1 通过** — `GameManager.reset_match()` 在进入 SERVING 时正确调用
  - 测试套件基类从 `RefCounted` 改为 `Object`
  - `Engine.register_singleton("__test_fsm__", self)` 成功
- [ ] **AC6: 所有现有测试保持通过** — `godot --path mini-pong/ --headless --script tests/run_tests.gd` 输出 `879 passed, 0 failed`
- [ ] **AC7: 编译检查通过** — `godot --path mini-pong/ --headless --quit` 无脚本错误

### 边界情况

1. **TC8 测试逻辑变更：** TC8.1/8.2 原始目的是验证 SPACE 双重按压保护。修复后的测试应验证：MENU 状态下按 SPACE → 成功转换到 SERVING。可在注释中标注 headless 中 `_transition_lock` 的中间状态无法测试
2. **TC11 替代验证：** 如果移除 TC11，应添加注释说明 `_pause_and_serve()` 的 `ball.serve()` 调用已被 FSM #294 `enter_state(SERVING)` 替代
3. **基类变更副作用：** `test_game_state_machine.gd` 类从 `RefCounted` 改为 `Object` — 需要验证不使用 RefCounted 特有的 API（如 `reference()`/`unreference()`）
4. **其他继承 RefCounted 的测试套件：** `test_scoring_manager.gd` 也继承 `RefCounted`，但不使用 `Engine.register_singleton()` — 不需要修改
5. **Mock GM 清理：** `_teardown_gm_mock()` 重新注册真实 GameManager — 需要验证 `Object` 基类不影响此清理逻辑

### 失败路径

1. **基类从 RefCounted 改为 Object 后，现有测试行为改变** — 如果任何测试无意中依赖 RefCounted 的引用计数行为（如期望 `free()` 后对象被自动清理），行为可能改变。缓解措施：检查所有使用 `self` 的测试逻辑
2. **`Engine.register_singleton()` 在 Object 子类上仍然失败** — 如果 Godot 4.x 有其他单例注册限制。缓解措施：测试 `Engine.has_singleton("__test_fsm__")` 并在失败时使用回调注入作为回退
3. **修改后出现新测试失败** — 由于测试间无意的状态泄漏。缓解措施：运行完整测试套件 3 次验证一致性

---

## 6. 依赖与阻塞

### 依赖关系

| 依赖 | 状态 | 风险 | 说明 |
|------|:----:|------|------|
| #294 Game State Machine | ✅ CLOSED | 无 | FSM 是 TC6.1/TC8.1/TC8.2/TC16.1 的行为来源 |
| #291 Scoring System | ✅ CLOSED | 无 | 计分系统是 TC11 的行为来源 |
| #293 GameManager | ✅ CLOSED | 无 | GameManager 是 TC16.1 中 `reset_match()` 的调用目标 |
| #295 Main Scene Assembly | ✅ CLOSED | 无 | 测试不依赖主场景 |
| #296 Pause and Sound | ✅ CLOSED | 无 | 不依赖暂停功能 |

**依赖链：**

```
#287 Ball Physics ──→ #291 Scoring System ──→ #293 GameManager
                                     │
                                     └──→ #294 Game State Machine
                                                  │
                                                  └──→ #340 本 PRD（修复预存测试失败）
```

### 阻塞项

| 被阻塞项 | 优先级 | 说明 |
|---------|:------:|------|
| #338 (impl/296-pause-and-sound) | P0 | 被 5 个测试失败阻塞 — 需等待 main 变绿 |
| #339 (impl/295-main-scene-assembly) | P0 | 被 5 个测试失败阻塞 — 需等待 main 变绿 |

### 前置准备

- [x] 确认 5 个失败在 main 分支上可复现
- [x] 完成根因分析（预调查结果已提供）
- [x] 确认不修改生产代码功能路径
- [ ] 运行完整测试套件基线（`godot --path mini-pong/ --headless --script tests/run_tests.gd`）

---

## 7. Spike / 实验

**跳过节 depth/standard 标签。**

---

## 8. 延续上下文

### 系统状态

- **5 个测试失败** 已通过根因分析完全理解
- **生产代码行为** 已验证正确（FSM #294 和计分系统 #291 的游戏测试通过）
- **修复范围确定** — 仅修改测试文件，不改动生产代码

### 给实施代理的关键信息

**TC11（test_scoring_manager.gd:247-257）：**
- `_pause_and_serve()` 现在是 `pass`（scoring_manager.gd:105-108）
- 旧行为（`await timer → ball.serve()`）已被 FSM #294 `enter_state(SERVING)` 替代（game_state_machine.gd:104-105）
- **修复选项：** 将 TC11 改为验证 `_pause_and_serve()` 不崩溃，或完全移除该测试并添加注释

**TC6.1（test_game_state_machine.gd:251-263）：**
- `enter_state(SCORED)` 调用 `await _timer_1s()` → `transition_to(SERVING)`（game_state_machine.gd:129-140）
- `_timer_1s()` 在 headless 中跳过 await（game_state_machine.gd:193-197）
- **修复：** 将断言从 `current_state == SCORED` 改为 `current_state == SERVING`

**TC8.1/TC8.2（test_game_state_machine.gd:283-306）：**
- `_input()` 设置 lock=true → `transition_to(SERVING)` → `enter_state(SERVING)` 重置 lock=false（line 109）
- headless 中此流程同步执行
- **修复：** 将断言改为验证 `current_state == SERVING` 且 `_transition_lock == false`（正确的最终状态）

**TC16.1（test_game_state_machine.gd:395-419）：**
- 测试套件继承 `RefCounted` — Godot 4.x 不支持 RefCounted 单例
- `Engine.register_singleton("__test_fsm__", self)` 静默失败
- **修复：** 将 L1 从 `extends RefCounted` 改为 `extends Object`

### 实施顺序

1. 运行测试基线确认 5 个失败
2. 修改 `test_scoring_manager.gd`（TC11）
3. 修改 `test_game_state_machine.gd`（TC6.1, TC8.1, TC8.2, TC16.1 + 基类）
4. 运行完整测试套件验证
5. 提交并创建实施 PR

### 验证命令

```bash
# 基线
godot --path mini-pong/ --headless --script tests/run_tests.gd
# 预期: 874 passed, 5 failed

# 修复后
godot --path mini-pong/ --headless --script tests/run_tests.gd
# 预期: 879 passed, 0 failed

# 编译检查
godot --path mini-pong/ --headless --quit
# 预期: 退出码 0
```

### 风险

- **低风险：** 改动仅限于测试断言行和测试套件基类声明
- **唯一技术风险：** `RefCounted → Object` 基类变更可能暴露现有测试中对 RefCounted 引用计数的依赖（检查 `test_game_state_machine.gd` 中无 `reference()`/`unreference()` 调用 — 确认没有）

### 后续问题

本 PRD 修复后，可考虑这些增强（非阻塞）：

| 后续工作 | 优先级 | 说明 |
|---------|:------:|------|
| 添加 headless 感知的 SPACE 双重按压测试 | P3 | 使用 mock 在 `_input()` 和 `enter_state()` 之间注入断言 |
| 统一测试套件基类 | P3 | 全部测试套件使用 `extends Object`，建立一致性 |
| 改进 headless `_timer_1s()` 的测试模拟 | P4 | 可注入的 timer mock，代替硬编码的 `get_tree()` 检测 |
