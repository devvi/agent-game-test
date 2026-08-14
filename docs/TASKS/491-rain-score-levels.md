# Tasks: [Test] 雨幕动态雨量可视化 — 按分数阈值切换雨量强度

> Parent Issue: #491
> 深度: depth/standard（6 文件 / 3+ 子系统；#485 同款「逻辑+测试+配置+runner+流水线测试」class → 精简版）
> 依据: `docs/DESIGN/491-rain-score-levels.md`
> 基线: main HEAD = 16333de（PRD #492 已合并）；L1 逻辑 2274 passed 0 failed（含 Rain Curtain 70 断言）；pipeline 测试 162 OK

> **⚠️ implement 硬性约束:**
> 1. 全部改动在既有文件，**不新增任何文件**（含测试文件）。
> 2. **禁写 amount / 只读比分 / 不改 FSM/物理/场景文件** — #389 红线不变。
> 3. **单调/步长断言的输入夹具必须 `ai_score = player_score`**（紧张因子恒定，唯一变量 = 档位）— 否则测试必红（DESIGN §1.3 裁决 1）。
> 4. worktree 隔离：`./scripts/worktree-setup.sh implement 491 rain-score-levels`；白名单提交 `./scripts/worktree-commit.sh 491 "<msg>" <files...>`。
> 5. 本地 headless 验证链：L0 `godot --path mini-pong/ --headless --script tests/check_compile.gd` → L1 `tests/run_tests.gd` → L2 `tests/playthrough_test.tscn`；pipeline `python3 -m unittest discover -s tests/pipeline -v`。

## Phase 1: 常量 + 公式引擎（P0）
- [ ] Task 1 (`mini-pong/gdscripts/constants.gd`): RAIN_* 组追加 `RAIN_SCORE_BAND_STEP: float = 0.15`、`RAIN_SCORE_BAND_1: int = 10`、`RAIN_SCORE_BAND_2: int = 20`（DESIGN §3.1）
- [ ] Task 2 (`mini-pong/gdscripts/rain_curtain.gd`): 新增纯函数 `score_band_for(score: int) -> int` = `clampi(score / CONSTS.RAIN_SCORE_BAND_1, 0, CONSTS.RAIN_SCORE_BAND_2 / CONSTS.RAIN_SCORE_BAND_1)`（DESIGN §2.1）
- [ ] Task 3 (`mini-pong/gdscripts/rain_curtain.gd`): `compute_target_rain` raw 叠加 `float(score_band_for(player_score)) * CONSTS.RAIN_SCORE_BAND_STEP`（DESIGN §2.2）；签名/调制/平滑不动

## Phase 2: L2 测试（P0）
- [ ] Task 4 (`mini-pong/tests/test_rain.gd`): `run()` 注册 `_test_score_bands()`；新增 `_test_score_bands()` ≥9 断言（边界穷举 0/9/10/19/20/21/-5、档位 0 零回归、步长 +0.15/+0.30、0→21 单调不减（ai=player）、9→10 阶跃平滑 ≤20% of step、调制参数档位单调、常量钉值、clamp 上限回归）（DESIGN §9 Scenario A）
- [ ] Task 5 (验证): L1 headless 全绿 —— 新增 ≥9 断言 + 既有 70 断言（档位 0 逐位不变 → 零回归）

## Phase 3: L3 配置 + runner + pipeline 测试（P0）
- [ ] Task 6 (`mini-pong/e2e_shots.json`): loop 组 `02_midgame` 后插入 `02_rain_light`（PLAYING / require score≥1 / settle 60）与 `02_rain_heavy`（PLAYING / require `/root/Game/AtmosphereLayer/RainCurtain` current_rain≥0.55 / settle 60 / deadline_s 300）（DESIGN §3.3）
- [ ] Task 7 (`scripts/run-e2e-review.sh`): P5 capture 后（`local_capture` log 与零 PNG 检查之间）加 ~6 行 results.json missed 检查（missed 非空 → VISUAL_FAIL；文件缺失不判 fail）（DESIGN §3.4）
- [ ] Task 8 (`tests/pipeline/test_e2e_runner.py`): fake godot 支持 `fake_missed_shots` 配置键（不写该 PNG + results.json 含 missed）；新增 2 用例：missed → L3 fail / 无 missed → L3 pass（DESIGN §9 Scenario C）
- [ ] Task 9 (验证): `python3 -m unittest discover -s tests/pipeline -v` 全绿 —— 新增 2 用例 + 既有用例（test_e2e_runner 含 test_visual_fail_when_no_pngs 等）不回归

## Phase 4: 真机验收 + 文档同步（P1）
- [ ] Task 10 (AC-验收 1 真机): 本地真实渲染连跑 3 次 `scripts/run-e2e-review.sh`（分支含 e2e_shots.json 改动），每次 `grep "P5 visual: pass"` 命中 3/3；`results.json` missed 为空；02_rain_heavy 成功截到（current_rain ≥ 0.55 门通过）—— Spike 2 实证（DESIGN §8 Phase 4）
- [ ] Task 11 (阈值校准): 若 02_rain_heavy 门不可达（AI 先胜/雨量不足），按实测校准（0.45 或改 require player_score ≥ 20）并在 PR body 注明实测数据（DESIGN §5 边界 6）
- [ ] Task 12 (`docs/GAME_DESIGN/`): 雨量公式档位维度增量更新 —— 由 review agent 在实现 PR merge 后按 GDD 维护规则执行（本 issue 不直接改）

## 验收门（全部满足才提交 review）
- [ ] L0 编译 / L1 逻辑（含新增档位断言）/ L2 运行时 三层全绿
- [ ] pipeline 测试全绿（python3 -m unittest discover -s tests/pipeline -v）
- [ ] 既有 70 Rain Curtain 断言零回归（档位 0 逐位不变）
- [ ] 真机 P5 3/3 pass + missed 为空
