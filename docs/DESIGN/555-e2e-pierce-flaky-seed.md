# DESIGN: [Bug] E2E Playthrough 随机对局 flaky — 全局 RNG seed + 确定性穿墙微检查（AC3-T5 / AC4-T7 根治）

> **Parent Issue:** #555
> **Agent:** game-plan-agent
> **Date:** 2026-08-18
> **Approach:** PRD §4 推荐组合 —— **方案 A**（测试侧固定全局 RNG seed，Issue 任务 1）+ **方案 C**（确定性穿墙微检查直接触发 `_crossed_wall` 路径，Issue 任务 3）；**方案 B** 轻量采纳（跨局 pierce 记录打印，不断言，Issue 任务 2 的可观测性部分）
> **Reference PRD:** `docs/PRD/555-e2e-pierce-flaky-seed.md`（research PR #556 MERGED）
> **所有权:** `content_ownership: mechanical`（测试确定性/断言改造 = 纯机械逻辑，无品味决策）
> **深度:** light（`depth/light` 标签）—— 单文件测试改造 + 1 处历史文档表述修正，无新文件、无迁移、无弃用 → **不产 TASKS 文档**（低于阈值）
> **红线:** 零游戏代码改动（`gdscripts/` `scenes/` `project.godot` 不碰，#394 §1.4 红线延续）；只改 `mini-pong/tests/e2e_playthrough.gd` + `docs/DESIGN/394-e2e-playability.md` 文档一致性

---

## 1. 架构概述

### 1.1 设计核心

**双机制根治两个独立 flaky 根因（均为 pre-existing 测试设计缺陷，与任何 PR 内容无关）：**

```text
（修复后）mini-pong/tests/e2e_playthrough.gd
  ├── 方案 A: _reset_pool() 首行 seed(SEED_GLOBAL + _attempt_no)
  │      └─► 全局 RNG（PCG32）确定化
  │            ├─► ball.serve() 角度/方向（ball.gd:104/106/114/116）
  │            ├─► paddle AI 反应延迟/位置误差（paddle.gd:223/317/318）
  │            ├─► breakout_grid.generate_wave 每波 seed(rng_seed)（grid:62-64，仍确定）
  │            └─► _open_hole_now 洞列选择（grid:171-180）
  ├── 方案 C: 新增 _test_pierce_deterministic()（AC3-T5 承接）
  │      └─► 独立场景 + 清墙 + 移除挡板 + 冻结球 (360,700) 向上速度
  │            └─► 真实物理穿墙带（_crossed_wall 边沿触发）→ 出顶界
  │                  └─► score.emit(0) → ScoringManager → add_score(3,"pierce")
  │                        └─► pierce_scored 信号 → 路径/计数/分值断言（必然执行，零随机依赖）
  ├── 配套: AC4-T7 两处断言容忍缝列洞（_is_gap_column c%5==4 → 洞开在空列 = 合法行为）
  └── 收尾: run() 末尾 randomize() 还原全局 RNG（防污染 auto_play 等后续套件）
```

### 1.2 设计哲学

1. **确定性优先（兑现 #394 承诺）** — #394 只 seed 了 UpgradePool 的局部 RNG 实例（升级抽取序列），serve/AI/波次/洞列的**全局** RNG 从未 seed。方案 A 一行补齐，使整局轨迹可复现。
2. **断言必然执行（不靠运气）** — 整局 pierce ≥ 1 依赖随机轨迹（退化族：AI 全漏 → 21:0 仅 163 帧 → 0 pierce，实测 2/3 对局落入退化族），「统计上极罕见」假设已被 #555 研究证伪。方案 C 让 AC3-T5 的 pierce 计分链在任何轨迹下都被确定性验证——AC1 的 3 连绿不依赖运气。
3. **合法游戏行为容忍（AC4-T7）** — 洞列命中 GAPS 缝列（{4,9}）时移除 0 砖属**合法游戏行为**（洞开在空列上无可见效果）；断言应区分「非缝列洞 → 砖数减少」与「全缝列洞 → 砖数不变」，而非一律要求 `remaining < expected`。
4. **零游戏代码改动红线延续** — 所有修复在测试侧：seed 从测试注入全局 RNG，游戏代码无感知（ball/paddle/breakout_grid 零改动）。
5. **改动面最小化** — 全部落在 `e2e_playthrough.gd` 单文件内（微检查仿 F3/F4 既有模式，不新增文件、不动 `run_tests.gd` 注册）。

### 1.3 PRD 断言 vs 实际代码交叉对照（plan agent 已逐条核实 main 源码）

| PRD 断言 | 实际代码 | 核实结果 |
|----------|---------|---------|
| `_reset_pool()` 在 `e2e_playthrough.gd:184`，每局起始调用 | ✅ `_play_match()` L308 在 `_make_fx()` 之前调用（`reset_match → _reset_pool → _reset_tracking → _make_fx`） | 方案 A 注入点成立，先于任何 serve/AI 随机消费 |
| AC3-T5 整局断言 `e2e_playthrough.gd:442-443`（`pierce_total >= 1`） | ✅ `_assert_ac3()` 内 L442-443 | 方案 C 取代（降级为信息打印） |
| 重试循环 `run()` L579-588，good 条件含 `pierce_total > 0` | ✅ run() 内 `while true` 循环（attempts ≤ 3） | 方案 B：pierce 条件移除、记录打印 |
| `_on_wall_generated` pre_hole 断言 L103-106（`remaining < expected`） | ✅ `_pre_hole_pending` 分支两断言 | AC4-T7 断言点 1，改走共享 helper |
| `_assert_ac4` 降级路径 L522-529（`remaining_bricks < _expected_bricks(1)`） | ✅ `_pre_hole_pending` 分支三断言 | AC4-T7 断言点 2，改走共享 helper |
| `ball.gd:104/106/114/116` serve 用 `randf_range`/`randi()` | ✅ 确认（headless 直发 + timer 延时双路径均消费全局 RNG） | 方案 A 治理对象 |
| `paddle.gd:223/317/318` AI 延迟/误差用 `randf_range` | ✅ 确认（`_ai_delay_timer` 初始化 + `_ai_process` 刷新） | 方案 A 治理对象 |
| `breakout_grid.gd:62-64` 每波 `seed(rng_seed)` 重置全局序列 | ✅ 确认（`generate_wave` 内 `rng_seed = randi()` 后 `seed(rng_seed)`） | seed 必须每局起始注入（任何随机消费之前） |
| `_open_hole_now`（grid:171-180）`randi_range` 选洞列不排除缝列；`_is_gap_column`（grid:249）`c % 5 == 4` | ✅ 确认；`layout` 默认 `BrickLayout.GAPS`（grid:33）；`BreakoutGrid.BrickLayout` 枚举 `{GAPS, OFFSET, HOLES, MIXED}`（grid:16） | 测试侧复制缝列判定（经实例枚举引用，不引入魔法数） |
| 微检查参照 F3 清墙模式（L625-640） | ✅ `_test_f3_endgame_race` 遍历 `grid.get_children()` destroy bricks | 方案 C 构造参照 |
| `ball.gd:169-183` `_crossed_wall` 边沿触发 + `score.emit(0)` 出顶界 | ✅ 确认（`not _crossed_wall and not _was_in_wall_band and in_band` → 置位；出顶界 `score.emit(0)` 玩家得分） | 微检查物理路径成立；墙带 y∈[618,662]（`GRID_WALL_Y=640` ± `WALL_BAND_HALF_HEIGHT=22`，constants.gd:85-86），球置 (360,700) 在带外下方 → 上移必触发 |
| `scoring_manager.gd:68-71` `crossed → add_score(winner, 3, "pierce")` | ✅ 确认 | 微检查分值断言依据（+3） |
| 后续套件 auto_play 在 E2E 之后运行（run_tests.gd） | ✅ 确认（`e2e_playthrough` → `auto_play_test` 顺序） | `randomize()` 还原为必做收尾 |
| 394 DESIGN §5 失败路径 5「统计上极罕见」 | ❌ **Stale**（docs/DESIGN/394-e2e-playability.md L260）— #554 两次运行各失败一次 + 本 PRD 研究 2/3 对局 0 pierce | 本次一并修正表述（PRD §3.5 可选清单） |

---

## 2. 修改点详细设计（全部在 `mini-pong/tests/e2e_playthrough.gd` 内）

### 2.1 方案 A — 全局 RNG seed 注入（`_reset_pool()`，现 L184）

```gdscript
const SEED_GLOBAL: int = 20260818   # 新增常量：全局 RNG 固定种子（与 SEED 区分；取值 issue 日期，
                                    # implement 实证若轨迹退化可调整 — 见 §5 边界 1）

var _attempt_no: int = 0            # 新增成员：重试局计数（seed 多元化用）

func _reset_pool() -> void:
    seed(SEED_GLOBAL + _attempt_no) # 新增首行：全局 RNG 确定性注入（serve/AI/波次/洞列全部确定化）
    UpgradePool.rng.seed = SEED
    ...
```

- **注入位置语义**：`_reset_pool()` 在 `_play_match()` 每局起始调用、先于 `_make_fx()`（AIPaddle `_ready` 消费 `randf_range` 与 serve timer）——满足 PRD §1.2 机制 1「必须在任何随机消费之前注入」。
- **每局多元化**：`run()` 重试循环内 `_attempt_no = attempts`（attempts 自增后赋值），第 n 局 seed = `SEED_GLOBAL + n` → 3 局轨迹各异但确定。
- **F3/F4 卫生**：`_test_f3_endgame_race` / `_test_f4_restart_no_leak` 各自在 `_reset_pool()` 前加 `_attempt_no = 0`（一行），保证其 seed 确定且独立（F3 注入计分走 `_injecting_score` 跳过 crossed_wall 断言，不受影响；F4 无 pierce 断言）。
- **不引入 `randomize()` 于局内**：`generate_wave` 每波 `seed(rng_seed)` 会覆盖全局序列，但 rng_seed 本身来自已 seed 的全局 RNG → 整局仍确定（PRD §3.4 数据流已确认）。

### 2.2 方案 C — 确定性穿墙微检查 `_test_pierce_deterministic()`（新增，AC3-T5 承接）

```gdscript
## 方案 C：确定性穿墙微检查 — 零随机依赖，必然触发 pierce 计分链（AC3-T5 承接）
func _test_pierce_deterministic() -> void:
    print("\n  -- G: 确定性穿墙微检查（AC3-T5 承接）--")
    GameManager.reset_match()
    _attempt_no = 0
    _reset_pool()
    _reset_tracking()
    var fx = _make_fx()
    _fx = fx
    # 不连接 wall_cleared/wall_generated（微检查无真实波次；避免 _on_cleared 的 AC2 断言误触发）
    # 防御性清墙（本场景未 start_first_wave 天然无砖；清墙幂等防前序残留）
    for child in fx.grid.get_children():
        if child.is_in_group("bricks"):
            child.destroy()
    await _tree().process_frame
    # 移除两挡板（球直上出顶界；防 AI 挡板拦截反弹破坏路径；ScoringManager 相对路径不依赖挡板）
    fx.paddle.queue_free()
    fx.paddle_top.queue_free()
    # 冻结球置于墙带下方 (360,700)（墙带 y∈[618,662]），设向上速度
    fx.ball.frozen = true
    fx.ball.position = Vector2(360.0, 700.0)
    fx.ball.velocity = Vector2(0.0, -fx.ball.speed)
    await _tree().process_frame
    fx.ball.frozen = false
    # 真实物理驱动至 pierce 计分或 10s 超时（700→0 距离约 2s，余量充足）
    var t0: int = Time.get_ticks_msec()
    while _pierce_scored.get("player", 0) == 0 and Time.get_ticks_msec() - t0 < 10000:
        await _tree().process_frame
    _assert(_pierce_scored.get("player", 0) == 1,
        "G-T3: 穿墙计分触发（player pierce=%d）" % _pierce_scored.get("player", 0))
    _assert(GameManager.player_pierce_count == 1,
        "G-T5: GameManager pierce 计数 == 1 (got %d)" % GameManager.player_pierce_count)
    _assert(GameManager.player_score == 3,
        "G-T6: 穿墙 +3 分 (got %d)" % GameManager.player_score)
    await _cleanup(fx)
```

- **路径断言自动生效**：`_on_pierce_scored`（L123-130）在 `_injecting_score == false` 时断言 `ball._crossed_wall` —— 微检查未设注入标志 → 信号触发瞬间同步断言「pierce 经 `_crossed_wall` 路径」（G-T4）。
- **调用位置**：`run()` 末尾，`_test_f3_endgame_race()` 与 `_test_f4_restart_no_leak()` 之后、`randomize()` 之前。
- **为何不连接 wall 信号**：若连接，清墙会触发 `wall_cleared → _on_cleared`，其中断言 `wave_state == SETTLED` 等 AC2 条件（微检查未 start_first_wave，wave_state 为 IDLE）→ 误失败。微检查只依赖 GameManager 计分信号（`_connect_signals` 已连）。
- **挡板移除安全性**：`ScoringManager` 通过 `../Ball`、`../BreakoutGrid` 相对路径解析（_make_fx 内注释确认），不依赖挡板节点；`GameManager` 计分链路（`add_score`）无挡板依赖。

### 2.3 方案 B（轻量）— AC3-T5 整局断言降级 + 各局 pierce 记录

- **`_assert_ac3()`（L442-443）**：删除 `pierce_total >= 1` 断言，改为信息打印：
  ```gdscript
  print("  AC3-T5: 整局 pierce 由确定性微检查覆盖（本局 pierce_total=%d）" % int(o.get("pierce_total", 0)))
  ```
  AC3 其余断言（T1/T2 总分重构余项 ≥ 0、T3 信号计数 == GameManager 计数、T4 拆砖归属 last_toucher）**全部保留**（AC2 验收：覆盖不降）。
- **`run()` 重试循环（L579-588）**：
  ```gdscript
  var _pierce_totals: Array = []     # 新增成员：各局 pierce 数（可观测性）
  ...
  while true:
      attempts += 1
      _attempt_no = attempts
      outcome = await _play_match(MAX_FRAMES)
      _pierce_totals.append(int(outcome.get("pierce_total", 0)))
      var good: bool = bool(outcome.get("completed", false)) \
          and int(outcome.get("settled_count", 0)) > 0
      if good or attempts >= 3:
          break
      print("  ⚠ 本局零结算，重试 %d/3" % (attempts + 1))
      await _cleanup(outcome.get("fx"))
  ...
  print("  pierce 各局: %s" % str(_pierce_totals))   # run() 末尾信息输出
  ```
  `pierce_total > 0` 从 good 条件移除（微检查已兜底 AC3-T5，重试不再为 pierce 服务）；`completed` + `settled_count` 条件保留（双闸防死循环语义不变）。
- **注意 `_attempt_no` 与 attempts 同步**：`_play_match` 内部不感知 attempts；run() 循环在调用前赋值 `_attempt_no`，`_reset_pool()` 读取 → seed 多元化生效。

### 2.4 配套 — AC4-T7 缝列洞容忍（两处断言点，共享 helper）

新增两个辅助函数（测试侧复制 `_is_gap_column` 语义，经实例枚举引用避免魔法数）：

```gdscript
## 缝列判定（复制 breakout_grid.gd:249 _is_gap_column 语义；经实例枚举引用）
func _is_seam_column_test(c: int, layout: int) -> bool:
    return (layout == fx_grid().BrickLayout.GAPS or layout == fx_grid().BrickLayout.MIXED) \
        and c % 5 == 4

## 洞列中是否存在「非缝列洞」（非缝列洞才移除砖）
func _hole_has_visible_effect(grid: Node2D) -> bool:
    for c in grid._hole_columns:
        if not _is_seam_column_test(int(c), grid.layout):
            return true
    return false

## AC4-T7 统一断言：非缝列洞 ≥ 1 → 砖数减少；全缝列洞 → 砖数不变（合法行为）
func _assert_hole_brick_count(grid: Node2D, remaining: int, expected: int, tag: String) -> void:
    if _hole_has_visible_effect(grid):
        _assert(remaining < expected,
            "%s: 洞墙砖数 < 无洞期望 (got %d, 期望 %d)" % [tag, remaining, expected])
    else:
        _assert(remaining == expected,
            "%s: 洞全在缝列 → 砖数不变 (got %d, 期望 %d)" % [tag, remaining, expected])
```

- **断言点 1 — `_on_wall_generated` pre_hole 分支（L103-106）**：`_assert(remaining < expected, "AC4-T7: 洞墙砖数 < 无洞期望 …")` → 替换为 `_assert_hole_brick_count(fx_grid(), remaining, expected, "AC4-T7")`；保留 `_hole_columns.size() >= 1` 洞存在断言。
- **断言点 2 — `_assert_ac4` 降级路径（L522-529）**：`_assert(fx.grid.remaining_bricks < _expected_bricks(1), "AC4-T7: 洞墙砖数 < 无洞期望 …")` → 替换为 `_assert_hole_brick_count(fx.grid, fx.grid.remaining_bricks, _expected_bricks(1), "AC4-T7(降级)")`；保留挂起洞消费与洞存在断言。
- **语义**：`_hole_columns` 中只要存在 ≥1 个非缝列洞 → 至少移除 `thickness` 砖 → `remaining < expected` 仍成立；全部为缝列洞 → `remaining == expected` 属合法（洞开在空列无可见效果），断言通过而非失败。

### 2.5 收尾 — 全局 RNG 还原（`run()` 末尾）

```gdscript
    # 防污染后续套件（auto_play 等）：还原全局 RNG（PRD §5.2 边界 7）
    randomize()
    _disconnect_signals()
```

置于 `run()` 末尾（`_test_f4_restart_no_leak` 之后、`_disconnect_signals` 之前）。auto_play 驱动 100 局不依赖随机多样性（无墙 harness，只有出界分），但显式还原消除一切跨套件耦合疑虑。

### 2.6 文档一致性（可选清单，PRD §3.5）

`docs/DESIGN/394-e2e-playability.md` L260（失败路径 5）：「若整局 0 pierce（统计上极罕见），…再断言 pierce ≥ 1」→ 改为：

> | 5 | 零穿墙分（pierce 未发生） | `ai_position_error=200` 下 AI 漏接 → 穿越墙带后出界概率高；整局 0 pierce 并非「极罕见」（#555 研究实测 2/3 对局 0 pierce）——AC3-T5 的 pierce 覆盖由 #555 的确定性穿墙微检查承接（全局 RNG seed + `_test_pierce_deterministic`），本行不再依赖重试兜底 |

---

## 3. 文件改动清单

| 类别 | 文件 | 改动 | 说明 |
|------|------|------|------|
| **Modified** | `mini-pong/tests/e2e_playthrough.gd` | §2.1-2.5 全部修改点（seed 注入 / AC3-T5 降级 / 重试条件 / AC4-T7 helper / 微检查 / randomize） | 唯一实现修改文件（~+70 行净增） |
| **Modified** | `docs/DESIGN/394-e2e-playability.md` | §2.6 失败路径 5 表述修正 | 文档一致性（PRD §3.5 可选清单） |
| **New** | （无） | — | 微检查作为 e2e_playthrough.gd 内部函数（仿 F3/F4 模式），不新增文件 |
| **Removed/Deprecated** | （无） | — | — |
| **Affected tests（implement 改造面）** | `mini-pong/tests/e2e_playthrough.gd` | 全部改造点集中于此 | 其余 24 套件零改动；`run_tests.gd` 零改动（微检查并入既有注册行） |
| **零改动红线** | `gdscripts/` `scenes/` `project.godot` `run_tests.gd` | 不碰 | #394 红线延续 |

---

## 4. 数据流

### Flow 1：方案 A — 全局 RNG seed 注入（每局起始）

```
run() 重试循环 (attempts=n)
  └─ _attempt_no = n
      └─ _play_match()
          └─ _reset_pool(): seed(SEED_GLOBAL + n)          ← 任何随机消费之前
              ├─► ball.serve() randf_range/randi → 发球轨迹确定
              ├─► paddle _ready/_ai_process randf_range → AI 行为确定
              ├─► generate_wave: rng_seed=randi() → seed(rng_seed) → 波次/洞列确定
              └─► _open_hole_now randi_range → 洞列确定
```

### Flow 2：方案 C — 确定性穿墙微检查（AC3-T5 承接）

```
_test_pierce_deterministic()
  ├─ reset_match + _reset_pool(seed 确定) + _make_fx()
  ├─ 清墙（幂等）→ 无砖可挡
  ├─ queue_free 两挡板 → 无拦截反弹
  ├─ ball.frozen=true; position=(360,700); velocity=(0,-speed) → 解冻
  ├─ 真实物理: 球上移 → 进入墙带 y∈[618,662]（带外→带内边沿触发）
  │     └─ _crossed_wall = true（ball.gd:169-174）
  ├─ 球出顶界 → score.emit(0)（ball.gd:179）
  │     └─ ScoringManager._on_ball_score(crossed=true)
  │           └─ GameManager.add_score("player", 3, "pierce")
  │                 ├─ player_score += 3 / player_pierce_count += 1
  │                 └─ pierce_scored("player") 信号
  │                       └─ _on_pierce_scored: 断言 ball._crossed_wall（路径，同步触发）
  └─ 断言: pierce_scored==1 / player_pierce_count==1 / player_score==3
```

### Flow 3：AC4-T7 洞列断言（两处统一语义）

```
_on_wall_generated / _assert_ac4 降级路径
  └─ _assert_hole_brick_count(grid, remaining, expected, tag)
      ├─ _hole_has_visible_effect(grid)?
      │     ├─ 是（存在非缝列洞）→ 断言 remaining < expected（原语义保持）
      │     └─ 否（全缝列洞 c%5==4 ∈ {4,9}）→ 断言 remaining == expected（合法行为）
```

---

## 5. 边界情况与错误处理

| # | 边界场景 | 处理 |
|---|----------|------|
| 1 | 固定 seed 的轨迹族退化（整局 0 pierce） | 方案 C 兜底：AC3-T5 由微检查保证，与整局轨迹无关；`_pierce_totals` 打印供观察。若退化同时影响对局完成度/升级覆盖（AC1/AC2/AC4），implement 实证后调整 `SEED_GLOBAL` 常量（以验收命令 3 连绿为准） |
| 2 | 全局 seed 污染后续套件（auto_play 在 E2E 之后） | `run()` 末尾 `randomize()` 还原；验收命令即回归验证 |
| 3 | `generate_wave` 每波 `seed(rng_seed)` 覆盖全局序列 | seed 在每局起始（任何随机消费前）注入；`_reset_pool()` 位置满足（先于 `_make_fx()` 的 AIPaddle._ready 与 serve timer） |
| 4 | 微检查球路径撞砖墙 | 不调用 `start_first_wave`（天然无墙）+ 防御性 destroy 清墙（幂等，仿 F3 清墙法） |
| 5 | 微检查与 F3 `_injecting_score` 互扰 | 微检查独立 `_make_fx()` 场景 + `_injecting_score` 保持 false（F3 在微检查之前已 cleanup）；信号连接/清理复用 `_connect_signals`/`_cleanup` 惯例 |
| 6 | headless 视口 0 | 微检查沿用 `_make_fx()` 的 screen 尺寸注入（SCREEN_W/H）与真实物理帧驱动，无渲染依赖 |
| 7 | 微检查球被 AI 挡板拦截反弹 | 显式 `queue_free` 两挡板（ScoringManager/GameManager 计分链无挡板依赖） |
| 8 | 洞列全命中缝列（{4,9}，无砖可移除） | `remaining == expected` 属合法游戏行为 → 断言通过（不再误报 flaky） |
| 9 | 真实时间耦合使轨迹非逐位可复现（serve 0.5s timer、AI 延迟按 delta 递减） | 验收只要求 3 连绿（AC1）；方案 C 吸收整局轨迹发散对 AC3-T5 的影响 |
| 10 | `_attempt_no` 在 F3/F4 泄漏非 0 值 | F3/F4 各自前置 `_attempt_no = 0`（§2.1），seed 确定且独立 |
| 11 | 微检查 10s 超时未触发 pierce | 断言失败 + 打印 `ball.position` / `_crossed_wall` / `_was_in_wall_band` / 帧数（对齐 ball.gd:141-146 边沿触发语义排查） |

---

## 6. 集成点

> **Status 约定：** ⬜ = pending（implement agent 接线后更新）；✅ = 已有连接（复用）。

| 集成 | 组件 | 关联 | 方式 | 状态 |
|-------|:---:|:---:|------|:---:|
| 全局 RNG seed | e2e_playthrough `_reset_pool` | ball.serve / paddle AI / breakout_grid 波次洞列 | `seed(SEED_GLOBAL + _attempt_no)` 注入（零游戏代码改动） | ⬜ 由本 PR 实现 |
| pierce 计分链 | 微检查球出顶界 | ScoringManager → GameManager | `score.emit(0)` → `_on_ball_score(crossed)` → `add_score(3,"pierce")` | ✅ 既有链路复用 |
| 路径断言 | `_on_pierce_scored` | ball `_crossed_wall` | 信号同步触发时断言（`_injecting_score=false`） | ✅ 既有断言复用 |
| 信号追踪 | `_connect_signals` | GameManager 计分/波次信号 | run() 起始连接、末尾断开 | ✅ 既有惯例复用 |
| AC4-T7 洞列语义 | `_assert_hole_brick_count` | `grid._hole_columns` / `grid.layout` / `BreakoutGrid.BrickLayout` | 测试侧复制 `_is_gap_column` 语义（经实例枚举引用） | ⬜ 由本 PR 实现 |
| 跨套件卫生 | run() 末尾 `randomize()` | auto_play_test（后续套件） | 还原全局 RNG | ⬜ 由本 PR 实现 |
| 文档一致性 | 394 DESIGN 失败路径 5 | #555 承接说明 | 表述修正（§2.6） | ⬜ 由本 PR 实现 |

---

## 7. 实现阶段

| 阶段 | 优先级 | 内容 | 依赖 |
|:----:|:------:|------|------|
| Phase 1 | P0 | 方案 A：`SEED_GLOBAL` + `_attempt_no` + `_reset_pool()` seed 注入 + run() 循环同步 | 无 |
| Phase 2 | P0 | 配套：AC4-T7 共享 helper + 两处断言点替换（**先于/同步 A**，防 A 使缝列洞确定性红） | Phase 1 |
| Phase 3 | P0 | 方案 C：`_test_pierce_deterministic()` + AC3-T5 降级 + `_pierce_totals` 记录 | Phase 2 |
| Phase 4 | P0 | 收尾：`randomize()` 还原 + 394 DESIGN 表述修正 | Phase 3 |
| Phase 5 | P0 | 实证验证：连续 3 次验收命令全绿；检查 auto_play 不受全局 seed 影响 | Phase 4 |

单文件测试改造，无跨组件依赖，Phase 1-4 可在一次实现会话内完成；Phase 5 为验收门槛。

---

## 8. 测试用例描述（不写可运行测试文件，implement agent 依此实现）

> 复用既有 `_assert`/`_connect_signals`/`_cleanup` 惯例；新断言全部落在 `e2e_playthrough.gd` 内。

### Scenario A：全局 RNG seed 确定性注入（方案 A）

- **A-T1（seed 注入位点）**：前置：`_reset_pool()` 被 `_play_match()` 每局起始调用且先于 `_make_fx()`。验证：`_reset_pool()` 首行执行 `seed(SEED_GLOBAL + _attempt_no)`（代码审查级；运行时以整局可复现性间接验证）。
- **A-T2（重试多元化）**：前置：第 1 局非 good（零结算），进入第 2 局。验证：第 2 局 `_attempt_no == 2` → seed = `SEED_GLOBAL + 2`；3 局 seed 各异（`_pierce_totals` 打印可见）。
- **A-T3（F3/F4 隔离）**：前置：`run()` 主循环后 `_attempt_no` 非 0。验证：F3/F4 各自前置 `_attempt_no = 0`，其 `_reset_pool()` seed 为 `SEED_GLOBAL`（确定且独立）。

### Scenario B：AC3-T5 整局断言改造（方案 B 轻量）

- **B-T1（断言降级）**：验证：`_assert_ac3()` 不再有 `pierce_total >= 1` 断言；整局 pierce 以 print 输出（含 `pierce_total` 值）。
- **B-T2（重试条件）**：验证：`run()` good 条件 = `completed && settled_count > 0`（不含 pierce）；`_pierce_totals` 记录各局 pierce 数并在 run() 末尾打印。
- **B-T3（覆盖不降）**：验证：AC3-T1/T2（总分重构余项 ≥ 0）、T3（信号计数 == GameManager 计数）、T4（拆砖归属 last_toucher）断言原样保留。

### Scenario C：AC4-T7 缝列洞容忍（配套必做）

- **C-T1（非缝列洞）**：前置：`_pre_hole_pending` 且 `_hole_columns` 含 ≥1 非缝列洞。验证：`remaining < expected`（原语义保持）。
- **C-T2（全缝列洞）**：前置：`_hole_columns` 全为缝列（`c % 5 == 4`，layout GAPS/MIXED）。验证：`remaining == expected` 通过（合法行为，不再误报 flaky）。
- **C-T3（两断言点一致）**：验证：`_on_wall_generated` 与 `_assert_ac4` 降级路径两处均走 `_assert_hole_brick_count`，行为一致；洞存在断言（`_hole_columns.size() >= 1`）保留。

### Scenario D：确定性穿墙微检查（方案 C 核心，AC3-T5 承接）

- **D-T1（场景就绪）**：前置：微检查场景创建完成。验证：组 `bricks` 节点数为 0（无砖可挡）；两挡板已移除。
- **D-T2（球位姿）**：验证：`ball.position == (360, 700)`、`ball.frozen == true`、`velocity.y < 0`（向上）；解冻后真实物理帧驱动。
- **D-T3（计分触发）**：验证：≤10s 内 `_pierce_scored["player"] == 1`（pierce_scored 信号触发）。
- **D-T4（路径断言）**：验证：触发瞬间 `ball._crossed_wall == true`（`_on_pierce_scored` 既有断言，`_injecting_score=false`）。
- **D-T5（计数一致性）**：验证：`_pierce_scored["player"] == GameManager.player_pierce_count == 1`。
- **D-T6（分值）**：验证：`GameManager.player_score == 3`（`add_score(3, "pierce")` 契约）。
- **D-T7（无终局误触发）**：验证：微检查期间 `match_over` 未触发、`is_run_over()` 为 false（21 分远未达到）。

### Scenario E：全局 RNG 还原（跨套件卫生）

- **E-T1（randomize 还原）**：验证：`run()` 末尾 `randomize()` 调用存在（`_disconnect_signals` 之前）；验收命令全绿时 auto_play 100 局 0 failed（全局 seed 未污染后续套件）。

### Scenario F：回归 — 既有断言结构不动

- **F-T1（AC1/AC2/AC4 保留）**：验证：AC1-T1..T4、AC2-T1..T8、AC4-T1..T8 断言结构原样（仅 AC3-T5 与 AC4-T7 两处按本设计改造）；场景组装/信号追踪/双闸不变。

### Scenario G：验收（映射 Issue AC1/AC2）

- **G-T1（3 连绿）**：连续 3 次 `godot --path mini-pong/ --headless --script tests/run_tests.gd`，每次 E2E Playthrough 0 failed（TOTAL 0 failed）。
- **G-T2（确定性红免疫）**：即使固定 seed 轨迹退化（整局 0 pierce，`_pierce_totals` 含 0），全套件仍全绿（方案 C 兜底生效）。

---

## 9. 风险与缓解

| 风险 | 等级 | 缓解 |
|------|:----:|------|
| 固定 seed 轨迹退化 → 确定性红 | Med | 方案 C 兜底 AC3-T5；AC4-T7 已容忍缝列洞；`SEED_GLOBAL` 可实证调整（§5 边界 1） |
| 全局 seed 污染后续套件 | Low | `randomize()` 还原 + 验收命令回归 |
| 微检查构造错误（球未穿墙带/撞砖/被挡板拦截） | Low | 清墙 + 移除挡板 + 断言信息带球位置/`_crossed_wall`/`_was_in_wall_band` 状态（§5 边界 11） |
| 真实时间耦合使轨迹非逐位可复现 | Low | 验收只要求 3 连绿；方案 C 吸收发散 |
| 3 连绿在 CI（Linux）与本地（macOS）表现不一 | Low | 全局 RNG PCG32 跨平台稳定；C 兜底吸收真实时间差异 |
