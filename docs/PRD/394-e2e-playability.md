# PRD: [Test] 端到端可玩验证 — E2E Playability Verification (AI vs AI 全链路自动对打)

> **Issue:** #394
> **标签:** enhancement, testing, version/mvp, workflow/research
> **Agent:** game-research-agent
> **日期:** 2026-08-13
> **深度:** depth/standard（Issue 无 depth 标签，按 #372/#393 惯例按 standard 处理：Section 1–6 + 8 必填，Section 7 以研究期已执行的实验/基线证据补齐）
> **所有权:** `content_ownership: mechanical`（纯测试基建，无品味决策；全部断言/场景/注册均为机械实现）
> **前置依赖:** #393（CLOSED，主场景组装已 merge 落地）
> **上游方案:** `docs/PLAN-e2e-verification-v2.md`（四层验证模型 L0-L3 + run-e2e-review.sh）、`docs/DESIGN/297-ai-auto-play-test.md`（既有 auto_play 先例）
> **参考先例:** `docs/PRD/297-ai-auto-play-test.md`、`docs/PRD/372-e2e-harness-fixes.md`、`tests/auto_play_test.gd`（100 局 AI vs AI 基线）、`tests/test_integration_393.gd`（组装集成 10 局循环）

---

## 1. 问题定义

### 1.1 当前状态

**核心发现：项目已有「打到 21 分的 AI vs AI 自动对打测试」（auto_play_test.gd，100 局）与「组装集成循环测试」（test_integration_393.gd，10 局），但两者都无法满足 #394 的验收——auto_play_test.gd 早于砖墙系统落地（无墙 harness，只测出界分），test_integration_393.gd 是手动驱动砖块销毁（不经过真实球物理），且两者均不覆盖穿墙计分、拆砖计分一致性、升级应用后的参数变化生效。**

#### 既有测试资产盘点（2026-08-13 源码核查）

| 测试 | 覆盖 | 缺口（相对 #394 AC） |
|------|------|---------------------|
| `auto_play_test.gd`（#297/#385） | 100 局 AI vs AI 打到 21 分；手动物理模拟（非真实引擎物理）；仅出界分（无砖墙 harness，文件头自述） | ❌ 无砖墙/无波次/无升级；手动碰撞判定与真实物理漂移 |
| `test_integration_393.gd`（#393 组装集成） | 10 局真实 BreakoutGrid + WaveController + GameManager 循环；墙生成→逐砖销毁→结算→升级确认推进→新墙更厚 | ⚠️ 砖块由测试**手动调用 destroy**，非球物理击碎；❌ 不覆盖拆砖/穿墙计分与事件计数一致性；❌ 不覆盖升级参数变化断言 |
| `test_wave_cycle.gd` / `test_breakout_grid.gd` / `test_upgrade_pool.gd` / `test_upgrade_pick_ui.gd` | 各子系统单元/契约测试 | 单点覆盖，非端到端 |
| `e2e_shots.json` + `run-e2e-review.sh` L3 | 真实渲染截图（01_title/02_midgame/03_gameover），autoplay 双 AI | 视觉证据层，无脚本化计分/升级断言 |
| `run-e2e-review.sh` L2 | `tests/playthrough_test.tscn` 运行时层 | ❌ **文件不存在 → L2 恒为 unavailable**（warn-only，不阻塞 exit 0 但层缺失） |

**关键代码事实（计分/升级契约，源码核实）：**
- `constants.gd`：`BRICK_SCORE=1`（拆砖分，最后触球方 +1）、`PIERCE_SCORE=3`（穿墙分，穿越墙带后出界 +3）、`WIN_SCORE=21`、出界兜底 `amount=1`（`scoring_manager.gd _on_ball_score` 非 crossed 分支）
- `game_manager.gd`：`player_score/ai_score` 总分 + `player_brick_count/ai_brick_count/player_pierce_count/ai_pierce_count` 事件计数（`_bump_count`），`add_score(winner, amount, kind)` 统一入口，`_check_run_end` 先到 21 者胜
- `upgrade_pool.gd`：`rng` 可 `seed()`（确定性抽取）、`get_candidates(3)`、`apply(id)` → `upgrade_applied` 信号 + `stacks` 计数；`_build_ctx` 注入 ball/paddle/grid 引用
- `upgrade_defs.gd`：6/9 升级机械完整（long_arm→挡板宽、fireball→球速+炸砖、battering_ram→炸邻砖、magnet_core→磁吸、slow_time→缓时、pre_hole→预开洞），3 桩（twin/stardust/phantom）
- `wave_controller.gd`：`wall_cleared` → `settle_wave()` → `wave_settled` 信号 →（`settle_hold=false` 自动推进 / `true` 等 `advance_settlement()`）→ `begin_wave()` 新墙更厚
- `e2e_shots.json` autoplay：双挡板 `mode=1`（AI）+ `ai_position_error=200` 实测可打完 21 分（#372 修复后 03_gameover 300s 内可达）

### 1.2 预期行为（验收条件，源自 Issue #394）

1. [ ] **AC1** 新增 e2e 测试场景，AI vs AI 可自动打完一局到 21 分
2. [ ] **AC2** 断言每波生成砖墙且打空后触发升级 UI 数据流
3. [ ] **AC3** 断言拆砖 +1、穿墙 +3 的最终总分与事件计数一致
4. [ ] **AC4** 覆盖至少 3 个升级在测试局中被应用后参数变化生效
5. [ ] **AC5** `run-e2e-review.sh` 全部层通过且 exit code 0（L0/L1 必过；L2 若提供 playthrough_test.tscn 则同时激活）

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 回归防线（每次 impl PR merge 后） | 每次 | review agent 跑 run-e2e-review.sh：L1 全量含新 e2e 场景，21 分完整局 + 计分一致性 + 升级生效一次验完 |
| B | 组装回归（#393 之后的主场景改动） | 每次场景/波次/升级改动 | 新 e2e 场景用真实组件 + 真实物理，任何破坏「可玩闭环」的改动直接红 |
| C | 手工验证替代 | 按需 | 制作者想看「一局自动打完」的证据：截图 + 脚本化断言双通道 |

### 1.4 技术约束（继承自 Issue #394 + 项目基线）

| 约束 | 细节 |
|------|------|
| 引擎 | Godot 4.7.1（`godot --path mini-pong/ --headless --script tests/run_tests.gd`） |
| 目录 | `mini-pong/` 子项目（`game-env/manifest.yaml`） |
| 测试范式 | `extends RefCounted` + `run()` 方法 + `run_tests.gd` 注册（既有 24 套件惯例）；异步用 `_run_async` |
| 测试基线 | 2137 passed / 0 failed（2026-08-13 实跑，本 PRD 研究期基线） |
| 不改动 | 游戏代码（`gdscripts/`、`scenes/`、`project.godot`）——本 Issue 是纯测试，零游戏代码改动 |
| 语言 | GDScript（Godot 4.7 headless） |

---

## 2. 设计意图

### 2.1 为什么当前行为存在

| 现象 | 来源 Issue/PR | 原因 |
|------|--------------|------|
| auto_play_test.gd 无砖墙 | #297（2026-07-30，早于 #384/#393） | 当时砖墙系统未落地；测试文件头自述「无砖墙 harness → 只有出界分」 |
| 组装集成测试手动销毁砖块 | #393（test_integration_393.gd） | 目标是验证**波次编排循环**（AC2/AC5），非球物理击碎路径；手动 destroy 快且确定 |
| L2 playthrough_test.tscn 缺失 | 一直缺失 | 从未有 Issue 要求创建运行时场景；run-e2e-review.sh 对缺失层 warn-only 不阻塞 |
| 无计分一致性/升级生效断言 | 无先例 | 拆砖/穿墙计分（#385）与升级池（#387）各自有单元测试，但从未在「完整一局」中联动断言 |

### 2.2 为什么现在改

#393 组装已 merge（PR #444）——Main.tscn 现已包含 BreakoutGrid、WaveController、WaveTransition、UpgradePickUI、GameHUD 全部组件，**可玩闭环首次真实存在**。但没有任何一个测试用**真实球物理 + 真实 AI 对打**把这一局打完并断言计分/升级。GDD 09-TESTING 的 auto-play 描述（"100 rounds AI-vs-AI"）已落后于砖墙时代。用自动化锁定可玩闭环（issue 上下文原话），正是 #394 的目的：这是 MVP 的验收性测试，也是后续所有波次/升级改动的回归防线。

### 2.3 先前约束（沿用）

| 约束 | 细节 |
|------|------|
| RefCounted + run() 范式 | 与 24 套件一致，`run_tests.gd` 统一聚合 |
| headless 优先 | 全部断言跑 `--headless`，无渲染依赖 |
| 真实组件优先 | 新 e2e 场景用真实 BreakoutGrid/WaveController/ScoringManager/UpgradePool（非 mock），与 test_integration_393 同构 |
| AI vs AI | 双挡板 `mode=1`，`ai_position_error` 参照 e2e_shots.json（200）保证 21 分可达且帧数可控 |
| 零游戏代码改动 | 纯测试文件 + run_tests.gd 注册；若需确定性可注入 seed（UpgradePool.seed() 已支持） |

---

## 3. 影响分析

### 3.1 直接受影响模块

| 文件 | 模块 | 改动性质 |
|------|------|---------|
| `mini-pong/tests/e2e_playthrough.gd` | **新建** e2e 场景测试 | **CREATE** — AI vs AI 完整一局（真实物理 + 真实组件），AC1-AC4 断言 |
| `mini-pong/tests/playthrough_test.tscn` | L2 运行时场景 | **CREATE（推荐）** — 激活 run-e2e-review.sh L2 层（AC5「全部通过」更完整） |
| `mini-pong/tests/run_tests.gd` | 测试 runner | **MODIFY** — 注册新套件（`_run_async("res://tests/e2e_playthrough.gd", "E2E Playthrough")`） |
| `mini-pong/e2e_shots.json` | L3 shot plan | **可能 MODIFY** — 若新场景暴露 03_gameover 帧数问题，调整 autoplay 参数（非必需） |
| `docs/GAME_DESIGN/09-TESTING.md` | GDD 测试章节 | **MODIFY（可选）** — 同步新套件到测试清单 |

### 3.2 新建文件

| 文件 | 用途 |
|------|------|
| `mini-pong/tests/e2e_playthrough.gd` | 主交付物：完整一局端到端测试（~300-400 行，参照 test_integration_393 + auto_play_test 混合范式） |
| `mini-pong/tests/playthrough_test.tscn` | L2 载体：极薄场景（挂 e2e 驱动脚本或 Main.tscn 实例 + autoplay），供 run-e2e-review.sh L2 使用 |

### 3.3 间接影响

- `run-e2e-review.sh`：L1 时延增加（新增套件跑一局真实物理）；L2 从 unavailable → 实际执行（若创建 tscn）
- 全量测试时长：2137 断言基线 + 新套件（一局真实物理 AI vs AI，参照 e2e_shots 03_gameover 上限 300s，实际应远快于上限）

### 3.4 数据流（测试断言骨架）

```
新 e2e 场景（tests/e2e_playthrough.gd, headless）
    │  组装真实组件（参照 Main.tscn 接线 + test_integration_393 模式）
    ▼
Ball (真实 ball.tscn) ── 物理击砖 ──► BreakoutGrid.brick_destroyed(brick, pos)
    │                                    │
    │                                    ▼
    │                          ScoringManager._on_brick_destroyed
    │                                    └─► GameManager.add_score(触球方, 1, "brick")   ← AC3 拆砖 +1
    │
    ├── 穿越墙带出界 ──► ScoringManager._on_ball_score(crossed=true)
    │                        └─► GameManager.add_score(winner, 3, "pierce")        ← AC3 穿墙 +3
    │
    └── 普通出界 ──► ScoringManager._on_ball_score(crossed=false)
                         └─► GameManager.add_score(winner, 1, "boundary")

WaveController._on_wall_cleared ──► GameManager.settle_wave() → wave_settled       ← AC2 数据流
    ├── UpgradePickUI 打开（get_candidates(3)）→ apply(id) → upgrade_applied       ← AC2/AC4
    │        └─► 参数变化：paddle.paddle_width / ball 速度 / grid hole              ← AC4
    └── advance_settlement() → begin_wave() → 新墙（更厚）                          ← AC2 每波生成墙

GameManager._check_run_end ── 任一方 ≥21 ──► match_over → GAME_OVER               ← AC1
    └─► 断言：player_score == brick*1 + pierce*3 + boundary*1 且与计数一致           ← AC3
```

### 3.5 文档更新

- [ ] `docs/GAME_DESIGN/09-TESTING.md` — 新增 E2E Playthrough 套件条目（可选，与 #393 先例一致在实现期同步）

---

## 4. 方案对比（e2e 测试实现策略）

### 4.1 Approach A：扩展 auto_play_test.gd（手动物理模拟加砖墙）

在既有手动物理模拟（手动碰撞判定）中加入砖墙碰撞、波次、升级逻辑。

- Pros：复用 100 局框架；速度快（无真实物理开销）
- Cons：**手动碰撞判定需重写砖墙/穿墙判定**，与真实引擎物理（StaticBody2D 碰撞、bounce 逻辑）漂移风险高；测试即实现复刻，失去「验证真实游戏」的意义；穿墙判定（`_crossed_wall` 由真实 ball.gd 设置）在手动模拟下不可信
- Risk: High ／ Effort: 2-3 天
- **否决**——手动物理模拟无法验证真实引擎的砖墙/穿墙/计分链路

### 4.2 Approach B：新建真实物理 e2e 场景测试（推荐）

新建 `tests/e2e_playthrough.gd`：组装**真实组件**（ball.tscn、player_paddle.tscn×2 均 mode=1、真实 BreakoutGrid、ScoringManager、WaveController、GameManager autoload、UpgradePool autoload），用**真实引擎物理帧**驱动（`await physics_frame` 或 process_frame 循环，参照 test_integration_393 的场景组装 + auto_play_test 的对打驱动），跑到任一方 21 分 `GAME_OVER`，然后断言：

- **AC1**：`GameManager.is_run_over()==true` 且胜者存在（`get_winner()` 非空）；总帧数 < 上限（防死循环）
- **AC2**：每波 `wave_started`/`wall_generated` 触发且砖数 > 0；`wall_cleared` → `wave_settled` → 升级 UI 数据流（`wave_settled` 信号 → `UpgradePool.get_candidates(3)` 返回 3 个 → `apply(id)` 成功）；`advance_settlement` 推进下一波（settle_hold=true 时显式调用，或默认自动推进路径断言 `begin_wave` 再次触发）
- **AC3**：局末 `player_score == player_brick_count*1 + player_pierce_count*3 + (player_score - brick*1 - pierce*3)`（boundary 余项 ≥ 0）且**信号计数一致**（监听 `brick_scored`/`pierce_scored`/`score_changed`，断言监听计数 == GameManager 计数 == 总分重构值）；AI 侧同样断言
- **AC4**：监听 `upgrade_applied` 收集 id，断言 **≥3 个不同升级**被应用；对每个机械完整升级断言参数变化（如 long_arm → `paddle.paddle_width` 增大；fireball → 球速倍率生效；pre_hole → grid 洞数增加；battering_ram → blast 调用记录）；`UpgradePool.seed()` 固定种子保证可复现
- 注册进 `run_tests.gd`（L1）；可选创建 `playthrough_test.tscn` 供 L2

- Pros：**验证真实游戏闭环**（真实物理击砖、真实计分链路、真实升级参数）；与 #393 组装集成测试同构（真实组件组装模式已验证）；确定性可控（seed + 帧上限）；AC1-AC4 全覆盖；L1 层自动纳入 run-e2e-review.sh
- Cons：真实物理一局耗时高于手动物理（参照 e2e_shots 03_gameover 上限 300s，实测应远快）；AI 随机性需 seed/参数调优保证砖墙可被击碎且 21 分可达（参照 e2e_shots autoplay ai_position_error=200 已实测可达）
- Risk: Low-Med ／ Effort: 1-2 天

### 4.3 Approach C：仅建 L2 playthrough_test.tscn，不做脚本化断言

只创建运行时场景给 run-e2e-review.sh L2 层跑真实渲染/运行时，不做计分/升级脚本断言。

- Pros：激活 L2 层；实现最小
- Cons：**AC2/AC3/AC4 全部无法满足**（无脚本化断言）；L2 退出码只反映「跑完没崩」，不反映计分/升级正确性
- Risk: High（验收不通过） ／ Effort: 0.5 天
- **否决**

### 4.4 推荐组合

| 决策点 | 推荐 | 依据 |
|--------|------|------|
| 主交付物 | Approach B：`e2e_playthrough.gd` 真实物理完整一局 | 唯一能同时满足 AC1-AC4 且验证真实游戏闭环的方案 |
| L2 激活 | Approach B 附赠 `playthrough_test.tscn`（薄场景，可选） | AC5 完整性：L2 从 unavailable 变实际执行；非阻塞（缺失时 warn-only） |
| 确定性 | `UpgradePool.seed()` 固定种子 + 帧数上限 + ai_position_error 参照 e2e_shots（200） | 可复现断言；防死循环 |
| 注册 | `run_tests.gd` 新增 1 条 `_run_async` 条目 | 全量回归自动包含；L1 纳入 run-e2e-review.sh |
| 游戏代码 | **零改动** | 纯测试 Issue；所有断言基于既有公开 API/信号 |

---

## 5. 边界条件与验收

### 5.1 正常路径（AC 检查清单，映射 Issue body）

| AC | 检查方式 |
|----|---------|
| AC1 自动打完一局到 21 分 | `e2e_playthrough.gd`：真实物理驱动至 `is_run_over()==true`；`get_winner()` 非空；帧数 < 上限 |
| AC2 每波生成砖墙 + 打空触发升级 UI 数据流 | 每波 `wave_started`/`wall_generated` 断言砖数 > 0；`wall_cleared` → `wave_settled` → `get_candidates(3)` 恰好 3 个 → `apply` 成功 → 下一波 |
| AC3 拆砖 +1 / 穿墙 +3 总分与事件计数一致 | 局末 `player_score == brick*1 + pierce*3 + boundary余项`；信号监听计数 == GameManager 计数；AI 侧同断言 |
| AC4 ≥3 个升级应用后参数变化生效 | `upgrade_applied` 收集 ≥3 个不同 id；机械完整升级逐一断言参数变化（挡板宽/球速/洞数/blast 调用） |
| AC5 run-e2e-review.sh exit 0 | L0 check_compile ✅、L1 run_tests.gd 全绿（含新套件）✅、L2（若建 tscn）✅、L3 视觉 ✅；`OVERALL=0` |

### 5.2 边界情况（Edge Cases）

| # | 场景 | 处理 |
|---|------|------|
| 1 | AI 互怼死循环（球永不落） | 帧数上限（如 60k 帧）超限即 fail；`ai_position_error=200` 参照 e2e_shots 已实测 21 分可达 |
| 2 | 砖墙打空但无人到 21（波次推进中） | 属正常路径：结算 → 升级 → 新墙，断言 wave_index 递增且新墙砖数 ≥ 旧墙 |
| 3 | 拆砖与出界同帧 | ScoringManager 帧守卫已实现（#385 AC4），断言总分仍 == 计数重构值即可 |
| 4 | 升级候选不足 3 个（池耗尽） | `get_candidates` 回退链已实现（#387），断言返回非空即可；AC4 只要求 ≥3 个不同升级被应用 |
| 5 | 桩升级（twin/stardust/phantom）被抽中 | 桩效果标记 `stub_activated` 可断言「被应用」，但参数变化断言只针对 6 个机械完整升级；seed 固定避免不确定性 |
| 6 | 21 分在升级窗口打开期间达到 | WaveController `end_wave_cycle` 分支（#388 边界 5），断言不生成新墙、match_over 触发 |
| 7 | headless 无渲染资源 | 全部断言纯逻辑/信号，无渲染依赖（既有 24 套件同范式已验证） |

### 5.3 失败路径（Failure Paths）

| # | 场景 | 处理 |
|---|------|------|
| 1 | 组件未接线（守卫生效） | 消费方 get_node_or_null + has_signal/has_method 双守卫（#384/#393 惯例），测试组装错误会以断言失败暴露而非静默 |
| 2 | 终局后残留事件 | GameManager `_is_run_over` 守卫 return（#385），测试在 match_over 后停止驱动 |
| 3 | 超时/死循环 | 帧数上限 fail + 打印当前分数/波次便于诊断 |
| 4 | 一局内升级未被应用（随机性） | seed 固定 + ai_position_error 调优保证波次循环触发；若仍不稳，允许测试内直接调 `UpgradePool.apply` 补足 AC4 覆盖（作为降级路径，需注释说明） |

---

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 说明 |
|------|:----:|------|
| #393 主场景组装 | ✅ CLOSED（PR #444 merged） | BreakoutGrid/WaveController/WaveTransition/UpgradePickUI 全部落地并接线——本 Issue 的测试对象已真实存在 |
| #384/#385/#386/#387/#388 契约 | ✅ 全部落地 | 砖墙/双得分/波次/升级池/升级 UI 均可在真实组件下驱动 |
| Godot 4.7.1 | ✅ | 本机 `/usr/local/bin/godot`（4.7.1.stable）实测 |
| 测试基线 | ✅ | 2137 passed / 0 failed（2026-08-13 实跑，研究期基线） |
| run-e2e-review.sh | ✅ | L0/L1/L3 已就绪；L2 缺失（warn-only） |

### 6.2 依赖链

```
#384 砖墙 → #385 双得分 → #386 波次 → #387 升级池 → #388 升级UI
                                                    ↓
                                    #393 主场景组装（CLOSED, PR #444）
                                                    ↓
                                    #394 端到端可玩验证（本 Issue）
```

### 6.3 阻塞

无阻塞。L2 playthrough_test.tscn 缺失是**可选补齐项**（AC5 在 L2 unavailable 时仍可 exit 0），不阻塞主交付。

---

## 7. Spike / 实验

按 depth/standard 惯例（#372/#393 同例）跳过独立 spike，研究期已执行以下基线证据：

1. **全量测试基线**：`godot --path mini-pong/ --headless --script tests/run_tests.gd` → **2137 passed / 0 failed**（含 Auto-Play 100 局 + Assembly Integration 10 局）——AC5 的改造前对照
2. **真实物理 21 分可达性**：`e2e_shots.json` autoplay 配置（双 AI + ai_position_error=200）在 #372 修复后已实测 03_gameover 300s 内可达 → 真实物理一局到 21 分**可行**，新测试沿用该参数族
3. **升级参数可断言性**：`upgrade_defs.gd` 6/9 机械完整升级均有可观测参数（paddle_width/球速/grid hole/blast），`upgrade_pool.gd apply()` 返回 bool + `upgrade_applied` 信号 → AC4 断言路径全部打通

---

## 8. 延续上下文（交给 plan agent）

### 系统状态

Main.tscn 组装完成（#393），可玩闭环真实存在但**无真实物理端到端测试**。现有 auto_play_test.gd（100 局无墙）与 test_integration_393.gd（手动销毁砖块）都无法满足 #394 AC1-AC4。本 PRD 推荐 Approach B：新建 `tests/e2e_playthrough.gd` 真实物理完整一局测试。

### 关键文件清单（plan agent 需要产出 DESIGN/TASKS 的文件）

| 优先级 | 文件 | 操作 |
|:------:|------|------|
| P0 | `mini-pong/tests/e2e_playthrough.gd` | **CREATE** — 真实物理 AI vs AI 完整一局（AC1-AC4 断言，~300-400 行） |
| P0 | `mini-pong/tests/run_tests.gd` | **MODIFY** — 注册 `_run_async("res://tests/e2e_playthrough.gd", "E2E Playthrough")` |
| P1 | `mini-pong/tests/playthrough_test.tscn` | **CREATE（可选）** — L2 薄场景，激活 run-e2e-review.sh L2 层 |
| P2 | `docs/GAME_DESIGN/09-TESTING.md` | **MODIFY（可选）** — 测试清单同步 |

### 实施顺序（推荐）

```
Phase 1: e2e_playthrough.gd 场景组装
  1. 参照 test_integration_393.gd 组装模式 + auto_play_test.gd 对打驱动：
     ball.tscn + player_paddle.tscn×2(mode=1, ai_position_error≈200) + 真实 BreakoutGrid
     + ScoringManager + WaveController + GameManager/UpgradePool(autoload)
  2. UpgradePool.seed() 固定种子；帧数上限常量；settle 延时按 test_wave_cycle 惯例注入短值
  3. 驱动循环：await physics_frame 直至 is_run_over() 或帧上限

Phase 2: 断言实现（AC1-AC4）
  1. AC1: is_run_over + get_winner 非空 + 帧数上限
  2. AC2: wave_started/wall_generated 每波触发 + wall_cleared→wave_settled→get_candidates(3)→apply
  3. AC3: 局末总分 == brick*1 + pierce*3 + boundary余项；信号计数 == GameManager 计数（双侧）
  4. AC4: upgrade_applied ≥3 不同 id + 机械完整升级参数变化断言

Phase 3: 注册 + 全量回归
  1. run_tests.gd 注册 → godot --path mini-pong/ --headless --script tests/run_tests.gd 全绿
  2. （可选）playthrough_test.tscn + run-e2e-review.sh 本地跑一遍确认 L2 激活且 exit 0

Phase 4: AC5 验证
  scripts/run-e2e-review.sh <PR_NUM> --subproject mini-pong（或按 review agent 惯例）→ OVERALL=0
```

### 主要风险与缓解

| 风险 | 缓解 |
|------|------|
| 真实物理一局耗时不可控 | ai_position_error 参照 e2e_shots（200）+ 帧数上限 + settle 短延时注入；e2e_shots 已实测 300s 内可达 21 分 |
| AI 随机性导致砖墙打不空/升级不触发 | UpgradePool.seed() + 多局（如 3 局）任选一局断言升级；最坏降级路径：直接调 apply 补足 AC4 |
| 与既有 auto_play_test.gd 语义重叠 | 新套件是**真实物理 + 砖墙 + 波次 + 升级**全链路；auto_play_test 保留为无墙手动物理基线（#297 契约），两者互补不互替 |

### 交给 plan agent 的硬性要求

- DESIGN 中必须给出：场景组装节点树、驱动循环伪代码、AC1-AC4 每条的断言函数签名、seed 值、帧数上限常量
- 测试用例描述（§9 场景）需覆盖 §5.1 全部 AC + §5.2/§5.3 边界与失败路径
- 不写可运行测试文件（DESIGN/TASKS 只描述，实现期新建 e2e_playthrough.gd）
- 零游戏代码改动红线：只新增 tests/ 文件 + run_tests.gd 注册行
