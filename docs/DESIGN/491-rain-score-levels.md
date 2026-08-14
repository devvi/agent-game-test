# DESIGN: [Test] 雨幕动态雨量可视化 — 按分数阈值切换雨量强度

> **Parent Issue:** #491
> **Agent:** game-plan-agent
> **Date:** 2026-08-14
> **Approach:** A — 离散分数档位因子（`score_band = clampi(score/RAIN_SCORE_BAND_1, 0, RAIN_SCORE_BAND_2/RAIN_SCORE_BAND_1)`，`raw += score_band × RAIN_SCORE_BAND_STEP`）—— 确认 PRD §4.4 推荐组合；否决 B（连续斜坡违反 Issue「0-9/10-19/20+」离散阈值语义）与 C（复活 #466 像素机器 + BgPulse 相位风险）
> **Reference PRD:** docs/PRD/491-rain-score-levels.md（research PR #492，已合并）
> **上游方案:** docs/PLAN-rogue-pong.md §3.2（公式权威源）、docs/DESIGN/389-dynamic-rain-curtain.md §3（公式引擎契约）
> **所有权:** `content_ownership: mechanical`（分数→档位映射 + L2 断言 + L3 门 = 机械可测；`RAIN_SCORE_BAND_STEP` 数值 = taste-draft 候补，human-review 定稿）
> **深度:** depth/standard（Issue 无 depth 标签，按 #389/#485 惯例）—— 文件域 6 个（constants.gd / rain_curtain.gd / test_rain.gd / e2e_shots.json / run-e2e-review.sh / test_e2e_runner.py），跨 gdscripts / mini-pong 配置 / scripts-e2e / tests-pipeline 3+ 子系统 → 产出精简 TASKS 文档
> **并行上下文:** 全部改动落在 main 既有文件（公式引擎/测试/runner/流水线测试均已在 main）；无未合并分支依赖（#466/#480/#485 已关闭，L3 用 main 设施）；constants.gd 改动面 = RAIN_* 组内新增 3 常量（RAIN_SCORE_BAND_*），与 #448/#449/#450 常量分区（BALL/HUD/BG/AUDIO 组）零冲突

---

## 1. 架构概述

### 1.1 设计核心

**在既有雨量公式上叠加「分数档位因子」，不改公式引擎/平滑/调制任何既有机制：**

```
既有（#389，已合并）:
  raw = base(0.3) + 球速(0→0.3) + 波次(0.1/波) + 紧张(比分差≤2→+0.2) + 脉冲 − 喘息
  target = clamp(raw, 0.1, 1.0)

新增（本 Issue）:
  score_band = clampi(player_score / RAIN_SCORE_BAND_1, 0, RAIN_SCORE_BAND_2 / RAIN_SCORE_BAND_1)
             = clampi(score/10, 0, 2)                    # 0-9→0, 10-19→1, 20+→2
  raw += float(score_band) × RAIN_SCORE_BAND_STEP         # +0 / +0.15 / +0.30
```

设计哲学：
1. **机械可测优先** — 档位映射是纯函数（`score_band_for(score) -> int`），边界穷举可 headless 单测；单调性由构造保证（档位随分数非递减 × 步长 > 0）；平滑复用既有 τ=0.15s 指数平滑（档位阶跃 = 目标值阶跃，0.5s 收敛，无单帧跳变）。
2. **档位 0 逐位不变（零回归红线）** — 0-9 分时 score_band = 0 → raw 与 #389 公式逐位一致 → 既有 70 断言全部保持。这是方案 A 相对方案 B/C 的决定性优势。
3. **L3 用 main 设施自洽** — capture 驱动 `require` 已支持任意节点数值属性门（`framework/templates/e2e_capture.gd:275-285`，float 比较）→ `RainCurtain.current_rain ≥ 0.55` 是**运行时雨量状态证据**；两 shot 帧间差异（`--diff-with`，Δluma ≥ 5.0 或 ratio ≥ 0.5%）满足「两档差异可测」。不复活 #466/#480/#485 像素机器（尊重 2026-08-14 重构清理决策）。
4. **runner missed-shot 判 fail 是 DoD 3 的诚实性要求** — main 的 P5 目前 capture 退出码只 log 不判 fail（#480 已知缺口，`scripts/run-e2e-review.sh:217-218` 实测确认）→ 若 AI 意外先胜，02_rain_heavy 静默漏截 → 假绿。加 ~6 行 results.json missed 检查闭合，同时补流水线单测（用户哲学：pipeline bugs must be caught by tests，PRD §3.1 未列此测试文件，本设计补上）。

### 1.2 PRD 断言 vs 实际代码交叉对照（plan agent 已逐条核实源码）

| PRD 断言 | 实际代码（main @ 16333de） | 设计裁决 |
|---------|--------------------------|---------|
| `compute_target_rain` 签名含 player_score（rain_curtain.gd:61） | ✅ `compute_target_rain(speed, wave_index, pulse, breathing, player_score, ai_score)` 已存在 | 签名不变，只在函数体叠加档位因子 |
| `_update_inputs()` 每帧读 `/root/GameManager` 比分（:100-120） | ✅ :113-120 读 `player_score`/`ai_score`，`int(ps)` 转换 | 数据管道已通，零改动 |
| 常量 RAIN_* 组在 constants.gd:136-146 | ✅ RAIN_BASE 0.3 / MIN 0.1 / MAX 1.0 / TAU 0.15 / SPEED 0.3 / TENSION_TH 2 / TENSION_BONUS 0.2 / WAVE_STEP 0.1 / PULSE 0.4 / BREATHING 0.15 | 组内追加 RAIN_SCORE_BAND_* 3 常量 |
| 紧张因子 = 比分差 ≤ 2 → +0.2 | ✅ :71-72 `abs(player_score - ai_score) <= CONSTS.RAIN_TENSION_THRESHOLD` | ⚠️ **单调性测试陷阱**（见 §1.3）：测试必须固定 ai_score = player_score 使紧张因子恒定 |
| `_make_curtain()` 纯逻辑实例模式 | ✅ test_rain.gd:36-42（@onready null → 公式层可单测） | `_test_score_bands()` 沿用 |
| e2e_shots.json loop 组 3 shot | ✅ 01_title / 02_midgame / 03_gameover；`require: {node, prop, min}` 单条件 | loop 组追加 2 shot（02_rain_light / 02_rain_heavy） |
| capture `require` 支持节点属性门 | ✅ `_require_ok`（e2e_capture.gd:275-285）`typeof(v) == TYPE_INT or TYPE_FLOAT` → `float(v) >= float(min)` | `current_rain`（float）可直接读；路径 `/root/Game/AtmosphereLayer/RainCurtain` 已按 Main.tscn 核实 |
| Main.tscn 节点路径 | ✅ Main.tscn:33 `AtmosphereLayer`（CanvasLayer, parent="."）→ :43 `RainCurtain`（rain_curtain.tscn 实例） | `require.node = "/root/Game/AtmosphereLayer/RainCurtain"` 成立 |
| run-e2e-review.sh P5 capture 退出码只 log 不判 fail | ✅ :217-218 `local_capture=$?` 仅 log；零 PNG 才 fail（:222-224） | P5 capture 后加 results.json missed 检查（§3.4） |
| runner 测试设施 | ⚠️ PRD §3.1 未列 pipeline 测试；实际有 `tests/pipeline/test_e2e_runner.py`（fake godot + FAKE_CONFIG 驱动，`test_visual_fail_when_no_pngs` 先例 :230） | **补** `test_e2e_runner.py` 修改（missed-shot 检查的 fake-godot 用例），闭合 PRD 缺口 |
| `wave_controller.gd` 已接线雨量波次因子 | ✅ wave_controller.gd:72-73 `rain_curtain.set_wave_factor(GameManager.wave_index)` | 分数 20+ 时 wave_index 已高（+0.1/波）→ 帮助 L3 大雨档可达（见 §1.3-2） |

### 1.3 设计裁决（PRD 缺口闭合 — plan agent 独立发现）

**裁决 1：单调性测试的输入夹具必须钉死。** PRD AC2 写「player_score 0→21 全扫，compute_target_rain 非递减（固定 speed/wave/pulse/breathing）」，但**未指定 ai_score** — 若 ai_score 固定为 3，紧张因子在 player 5→9 时关闭（|5-3|=2≤2 开 → |9-3|=6 关），雨量 0.5→0.3 **非单调**，测试必红。**设计定案：单调性扫描用 `ai_score = player_score`（差恒 0 → 紧张因子恒 +0.2 恒定）**，使唯一变量 = 分数档位；目标值序列 0.5 / 0.65 / 0.8 严格单调。步长断言同理（固定 ai_score = player_score）。

**裁决 2：L3 大雨档可达性由「档位 + 波次 + 球速」三重因子共同保证。** current_rain ≥ 0.55 门在 AI-vs-AI（player error 24 vs AI error 200）整局中：player 先到 20 分时 wave_index 已 ≥ 2（每波 +0.1）+ 球速因子（0→0.3）+ 档位 2（+0.30）→ target 常态 ≥ 0.7，current 收敛后 ≥ 0.55 稳达；且 03_gameover 既以 300s deadline 等到 21 分（先例证实整局可达），02_rain_heavy 同 deadline 可靠。**门不可达 → runner missed 检查判 fail（诚实失败），不降门槛掩盖**（PRD §5 失败路径 3 一致）。

**裁决 3：档位阶跃的平滑断言以「步长本身」为范围基准。** 既有 TC-smooth-1 用 `0.2 × step_range`（0.3→1.0 的 0.7 范围）；档位阶跃 9→10 的范围 = 0.15（步长）。单帧最大 delta = 0.15 × (1−exp(−1/60/0.15)) ≈ 0.0158 ≤ 0.2×0.15=0.03 ✓。复用同一模式、同一阈值语义。

**裁决 4：runner missed 检查必须带流水线单测。** 用户红线「Pipeline bugs must be caught by tests, not production」+ 集成测试强制 — PRD 把 run-e2e-review.sh 列入直接改动文件但漏了对应测试。本设计在 `tests/pipeline/test_e2e_runner.py` 新增 fake-godot 用例（FAKE_CONFIG 驱动 results.json missed 注入），先例 = `test_visual_fail_when_no_pngs`（:230）。

---

## 2. 新组件

无新文件（与 #485 同款 class：逻辑 + 测试 + 配置 + runner 检查，全部落在既有文件）。新增逻辑组件 = **纯函数 `score_band_for()`**：

### 2.1 `score_band_for(score: int) -> int`（rain_curtain.gd 新增）

- **文件:** `mini-pong/gdscripts/rain_curtain.gd`（新增方法，无新文件）
- **签名:** `func score_band_for(score: int) -> int`
- **逻辑:**
  ```gdscript
  func score_band_for(score: int) -> int:
      # 0-9→0, 10-19→1, 20+→2；负分 → clampi 钳 0；常量单点定义边界
      return clampi(score / CONSTS.RAIN_SCORE_BAND_1,
                    0, CONSTS.RAIN_SCORE_BAND_2 / CONSTS.RAIN_SCORE_BAND_1)
  ```
- **性质:** 纯函数（无状态、无场景依赖）→ headless 单测直接调用；`RAIN_SCORE_BAND_2 / RAIN_SCORE_BAND_1 = 2` 派生最大档位，边界常量单点可调（如改 8/16 → 自动 0-7/8-15/16+）
- **边界:** score ∈ {…,-1} → 0；9→0；10→1；19→1；20→2；21→2（WIN_SCORE=21 终局不越界）；整数除法（GDScript int/int 截断）

### 2.2 `compute_target_rain` 档位因子叠加（rain_curtain.gd 修改）

```gdscript
func compute_target_rain(speed, wave_index, pulse, breathing, player_score, ai_score) -> float:
    ...  # 既有 speed_factor / wave_factor / tension / breathing_drop 不动
    var score_band: int = score_band_for(player_score)               # 新增 1 行
    var raw: float = base_intensity + speed_factor + wave_factor + tension \
                     + float(score_band) * CONSTS.RAIN_SCORE_BAND_STEP \
                     + pulse - breathing_drop                        # 修改 1 行（插入 band 项）
    return clamp(raw, CONSTS.RAIN_MIN, CONSTS.RAIN_MAX)
```

- 签名/返回值语义不变；`set_intensity` 调试口不变（`_target_override >= 0` 直接短路公式，档位不影响调试口）
- 档位 0 时 `float(0) × STEP = 0` → raw 逐位等于现状（零回归）

---

## 3. 既有组件修改

| 文件 | 改动 | 为什么 |
|------|------|--------|
| `mini-pong/gdscripts/constants.gd` | RAIN_* 组追加 `RAIN_SCORE_BAND_STEP: float = 0.15`（taste-draft 候补）、`RAIN_SCORE_BAND_1: int = 10`、`RAIN_SCORE_BAND_2: int = 20` | 档位边界/步长单点定义；机械边界（10/20）与 taste 数值（0.15）分离 |
| `mini-pong/gdscripts/rain_curtain.gd` | 新增 `score_band_for()`；`compute_target_rain` raw 叠加 band 项（§2.2） | 需求核心（DoD 1） |
| `mini-pong/tests/test_rain.gd` | `run()` 注册 `_test_score_bands()`；新增 `_test_score_bands()`（≥9 断言，§9 Scenario A） | DoD 2 |
| `mini-pong/e2e_shots.json` | loop 组追加 `02_rain_light` / `02_rain_heavy` 2 shot（§3.3） | DoD 3 |
| `scripts/run-e2e-review.sh` | P5 capture 后加 results.json missed 检查（§3.4，~6 行） | DoD 3 诚实性 + #480 AC4 最小实现 |
| `tests/pipeline/test_e2e_runner.py` | fake godot 支持 `fake_missed_shots` 配置；新增 2 用例（§9 Scenario C） | 用户红线：pipeline 改动必须被测试捕获（PRD 缺口闭合） |

### 3.1 `mini-pong/gdscripts/constants.gd`（修改）

RAIN_* 组（:134-146）内、`RAIN_BREATHING_DROP` 之后追加：

```gdscript
const RAIN_SCORE_BAND_STEP: float = 0.15   # 分数档位步长（taste-draft 候补, human-review 定稿; 0.15 → alpha +0.0375, velocity +12%）
const RAIN_SCORE_BAND_1: int = 10          # 档位边界 1: 0-9 → 档位 0
const RAIN_SCORE_BAND_2: int = 20          # 档位边界 2: 10-19 → 档位 1, 20+ → 档位 2 (WIN_SCORE=21)
```

### 3.2 `mini-pong/gdscripts/rain_curtain.gd`（修改）

新增 `score_band_for()`（§2.1）+ `compute_target_rain` raw 叠加（§2.2）。伪代码即实现；改动面 = +7 行（1 纯函数 + 1 行叠加 + 1 行局部变量）。

### 3.3 `mini-pong/e2e_shots.json`（修改）

loop 组 shots 数组，`02_midgame` 之后插入：

```json
{ "name": "02_rain_light", "state": "PLAYING",
  "require": { "node": "/root/GameManager", "prop": "player_score", "min": 1 },
  "settle_frames": 60 },
{ "name": "02_rain_heavy", "state": "PLAYING",
  "require": { "node": "/root/Game/AtmosphereLayer/RainCurtain", "prop": "current_rain", "min": 0.55 },
  "settle_frames": 60, "deadline_s": 300 }
```

- **位置在 02_midgame 之后**：02_midgame 带 `press: enter` 驱动 MENU→PLAYING；rain shots 依赖 PLAYING 状态，置于其后保证先触发 press（capture 按数组序检查 ready）
- **02_rain_light**：score ≥ 1（首分即触发，实测分数 1-3 = 档位 0）；settle 60 = 1s ≥ 平滑收敛 0.5s 的 2 倍裕量 → 截图时 current_rain 已收敛到档位 0 目标
- **02_rain_heavy**：`current_rain ≥ 0.55` 节点属性门（运行时雨量状态证据，非像素推断）；settle 60；deadline 300（整局可达，03_gameover 先例）
- **文件名排序（隐式 diff 链）**：glob 排序 `01_title < 02_midgame < 02_rain_heavy < 02_rain_light < 03_gameover` → 帧间差异断言链 `(title,midgame)` / `(midgame,rain_heavy)` / `(rain_heavy,rain_light)` / `(rain_light,gameover)` — 其中 `(midgame, rain_heavy)` = 档位 0 vs 档位 2 的**两档差异证据对**（Δluma ≥ 5 或 ratio ≥ 0.5% 必过：雨幕密度 + 分数 HUD 双变），`(rain_heavy, rain_light)` = 反向证据对（大雨 vs 小雨）

### 3.4 `scripts/run-e2e-review.sh`（修改，P5 capture 之后 ~6 行）

```bash
# ── #491: missed-shot 判 fail（#480 AC4 最小实现；防大雨档 shot 静默漏截假绿）──
if [ -f "$OUT/shots/results.json" ]; then
  MISSED=$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1])).get("missed",[])))' "$OUT/shots/results.json" 2>/dev/null || echo 1)
  if [ "$MISSED" != "0" ]; then
    log "❌ $MISSED shot(s) missed — VISUAL_FAIL (results.json)"
    VISUAL_FAIL=1
  else
    log "✅ results.json: 0 missed"
  fi
fi
```

- **位置**：P5 的 `local_capture=$?` log 之后、零 PNG 检查之前（:218 与 :222 之间）— 与既有零 PNG 检查互补（零 PNG 抓崩溃、missed 抓静默漏截）
- **容错**：results.json 缺失不判 fail（fake godot 测试不写该文件 → 既有用例不回归；真实 capture 必写 → 生产路径完整）
- **不复活 #480**：仅 6 行检查，不改 capture 模板 / resolve_plan / analyze_bmp

### 3.5 文件清单汇总

- **新文件:** 无
- **修改文件:** 6 — constants.gd / rain_curtain.gd / test_rain.gd / e2e_shots.json / run-e2e-review.sh / test_e2e_runner.py
- **删除/弃用:** 无
- **受影响测试:** test_rain.gd（新增 _test_score_bands，run_tests.gd 已注册无需改）；test_e2e_runner.py（新增 2 用例，既有用例不回归）

---

## 4. 数据流

### Flow 1: 正常路径（分数 → 档位 → 雨量）

```
GameManager.player_score（autoload，只读）
    │ 每帧 _update_inputs()（:113-120，已接线）
    ▼
compute_target_rain(..., player_score, ai_score)
    ├── speed_factor / wave_factor / tension / breathing_drop   # 既有，不动
    ├── score_band = clampi(player_score/10, 0, 2)              # 新增
    ├── raw += score_band × RAIN_SCORE_BAND_STEP(0.15)          # +0/+0.15/+0.30
    ▼
target = clamp(raw, 0.1, 1.0)
    ▼
smooth_step(current, target, 1/60)   # τ=0.15 指数平滑，档位阶跃 0.5s 收敛
    ▼
_apply_to_particles()                # velocity ×(0.6+0.8r) / scale ×(0.5+0.7r) / alpha 0.15+0.25r（禁写 amount）
```

### Flow 2: L3 视觉断言路径

```
run-e2e-review.sh P5 → resolve_plan.py（loop 组命中 gdscripts/.*\.gd → 5 shot 全含）
    ▼
capture.gd（真实渲染）: 01_title(MENU) → 02_midgame(press enter→PLAYING, score≥1)
    → 02_rain_light(score≥1, settle 60) → 02_rain_heavy(current_rain≥0.55, settle 60)
    → 03_gameover(300s deadline)
    ▼
analyze_bmp.py 4 重断言 × 5 PNG（--diff-with 相邻）: (midgame,rain_heavy) = 两档差异证据对
    ▼
results.json missed 检查: 非空 → VISUAL_FAIL（诚实失败）
```

### Flow 3: 失败路径（大雨档 shot 漏截）

```
AI 意外先胜（player 未到 20）→ current_rain 达不到 0.55 → 02_rain_heavy 永不 ready
    → deadline 300s 到 → capture 记 missed → results.json.missed = ["02_rain_heavy"]
    → runner missed 检查判 VISUAL_FAIL → L3=fail → 诚实暴露（非假绿）
    → review agent 复核截图像素后按实测校准（PRD §5 失败路径 3）
```

### Flow 4: 边界路径（档位阶跃平滑）

```
player_score 9→10（连得 1 分跨档）: target 0.5→0.65（阶跃 +0.15）
    → current_rain 以 τ=0.15s 平滑收敛（单帧 delta ≈ 0.0158 ≤ 0.2×0.15）
    → 无单帧跳变（复用 TC-smooth-1 模式验证）
跨 2 档（连得 3 分 9→12）: 同机制收敛，无新风险
```

---

## 5. 边界情况与错误处理

| 边界情况 | 缓解措施 |
|---------|---------|
| 档位 2 上界（score 20-21） | `clampi(score/10, 0, 2)` 对 21 返回 2 不越界；WIN_SCORE=21 终局后分数冻结，档位不再变 |
| 负分 / 异常分数 | `score_band_for` 整数除法 + clampi → 负分钳 0；player_score 是 int，无 NaN 面 |
| 档位阶跃 9→10 / 19→20 | target 阶跃 +0.15，τ=0.15s 平滑 0.5s 收敛；单帧 delta ≤ 20% of step（§1.3 裁决 3） |
| 档位 0 既有行为回归 | score_band=0 → raw 逐位等于 #389 → 既有 70 断言作回归网，任何偏差立即暴露 |
| clamp 边界（档位 2 + 球速上限 + 紧张 + 脉冲 ≈ 1.5） | clamp 到 RAIN_MAX 1.0；RAIN_MIN/RAIN_MAX 仍为唯一边界源 |
| L3 大雨档不可达（AI 先胜） | runner missed 检查判 fail（诚实失败）；Spike 2 实证后按实测校准阈值（0.45 或改 require player_score ≥ 20）——**不得删除门** |
| require 节点路径错误 | capture 打 `node not found` → shot 永不 ready → deadline → missed → runner fail（诚实暴露） |
| settle_frames 与平滑收敛 | 收敛需 ~0.5s（30 帧@60fps）→ settle 60 双倍裕量 |
| 其他 shot 不受影响 | 01_title（MENU 档位 0）/ 02_midgame / 03_gameover require 语义不变；新增 shot 不改变既有 shot |
| taste-draft 步长被 future 误改 | RAIN_SCORE_BAND_STEP 单点常量 + test_rain.gd 断言钉值（TC-band-6/7） |
| e2e_shots.json 两 shot 顺序依赖 press | 置于 02_midgame 之后（数组序 = ready 检查序），press 先触发 PLAYING |

---

## 6. 逐组件配置（implement 契约速查）

| 位置 | 配置 | 值 |
|------|------|-----|
| constants.gd RAIN_* 组 | `RAIN_SCORE_BAND_STEP` | `0.15`（taste-draft，human-review 定稿） |
| constants.gd RAIN_* 组 | `RAIN_SCORE_BAND_1` / `RAIN_SCORE_BAND_2` | `10` / `20`（机械固定） |
| rain_curtain.gd | `score_band_for(score)` | `clampi(score / RAIN_SCORE_BAND_1, 0, RAIN_SCORE_BAND_2 / RAIN_SCORE_BAND_1)` |
| rain_curtain.gd | `compute_target_rain` raw | 插入 `+ float(score_band_for(player_score)) * CONSTS.RAIN_SCORE_BAND_STEP` |
| e2e_shots.json loop 组 | `02_rain_light` | PLAYING / require score≥1 / settle 60 |
| e2e_shots.json loop 组 | `02_rain_heavy` | PLAYING / require current_rain≥0.55 / settle 60 / deadline_s 300 |
| run-e2e-review.sh P5 | missed 检查 | capture 后读 `$OUT/shots/results.json`，missed 非空 → VISUAL_FAIL |

---

## 7. 集成点

> **状态约定:** ⬜ = 待 implement agent 接线；✅ = implement agent 验证后更新。review agent 合并前核验无 ⬜ 残留。

| 集成 | 我方组件 | 目标 Issue/系统 | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| GameManager.player_score → rain_curtain | compute_target_rain(player_score) | #389 已接线 | 每帧 `_update_inputs()` 读 autoload 属性（已存在，零改动） | ✅ 已有 |
| wave_controller → rain_curtain | set_wave_factor(wave_index) | #389 已接线 | Main.tscn 场景树（wave_controller.gd:72-73） | ✅ 已有 |
| score_band_for → compute_target_rain | 纯函数调用 | 本 Issue | 函数内联调用（§2.2） | ⬜ 新增 |
| e2e 02_rain_light shot | require 门 | e2e_capture.gd `_require_ok` | `{node, prop, min}` 单条件（已支持） | ⬜ 配置新增 |
| e2e 02_rain_heavy shot | require 门（current_rain≥0.55） | e2e_capture.gd `_require_ok` | `{node, prop, min}` float 比较（已支持） | ⬜ 配置新增 |
| runner P5 → results.json | missed 检查 | e2e_capture.gd `_write_results` | 6 行 shell 检查（§3.4） | ⬜ 新增 |
| pipeline 测试 → runner | fake godot missed 注入 | test_e2e_runner.py FAKE_CONFIG | `fake_missed_shots` 键驱动（§9 Scenario C） | ⬜ 新增 |
| GDD 文档 | 雨量公式档位维度 | docs/GAME_DESIGN/ | 实现 PR merge 后 review agent 增量更新 | ⬜ 延后 |

---

## 8. 实施阶段

| 阶段 | 优先级 | 组件 | 估算 |
|:----:|:------:|------|:----:|
| Phase 1 | P0 | constants.gd 3 常量 + rain_curtain.gd score_band_for + compute_target_rain 叠加 | 0.5 天 |
| Phase 2 | P0 | test_rain.gd `_test_score_bands()`（≥9 断言）+ headless L1 全绿（含既有 70 断言回归） | 0.5 天 |
| Phase 3 | P0 | e2e_shots.json 2 shot + run-e2e-review.sh missed 检查 + test_e2e_runner.py 2 用例 + pipeline 测试全绿 | 0.5 天 |
| Phase 4 | P1 | Spike 2 实证：本地真实渲染 P5 连跑 3 次，确认 02_rain_heavy 可达、missed 为空、阈值校准 | 0.5 天 |
| Phase 5 | P1 | L0 编译 + L1 逻辑 + L2 运行时三层 + pipeline 全绿；review agent 本地 E2E 验收 | 0.5 天 |

依赖序：Phase 1 → 2 → 3 → 4 → 5（常量先行，测试跟随实现，e2e/runner 最后）。

---

## 9. 测试用例描述

### Scenario A: L2 分数档位逻辑（`_test_score_bands()`，test_rain.gd，≥9 断言）

> 夹具：`_make_curtain()` 纯逻辑实例；**单调/步长断言统一 `ai_score = player_score`**（紧张因子恒定 +0.2，唯一变量 = 档位 — 裁决 1）。

- **Test 1**（档位边界穷举）：`score_band_for(0)==0`、`(9)==0`、`(10)==1`、`(19)==1`、`(20)==2`、`(21)==2`、`(-5)==0` — 7 断言，边界 9/10/19/20/21 全覆盖 + 负分钳 0
- **Test 2**（档位 0 零回归）：`compute_target_rain(330, 0, 0.0, false, 0, 0)` 与 PRD 公式基线逐位一致（差 < 0.0001）—— 档位 0 无加成
- **Test 3**（步长值 band 1）：`target(score=10, ai=10) − target(score=0, ai=0) == RAIN_SCORE_BAND_STEP`（+0.15，固定 speed/wave/pulse）
- **Test 4**（步长值 band 2）：`target(score=20, ai=20) − target(score=0, ai=0) == 2 × RAIN_SCORE_BAND_STEP`（+0.30）
- **Test 5**（0→21 单调不减）：player_score 0..21 全扫（ai_score=player_score，speed=627 上限、wave=0、pulse=0、breathing=false），断言 `target` 非递减（档位内平坦、跨档 +0.15）
- **Test 6**（档位阶跃平滑无跳变）：`current_rain=target(9)`，改 `_player_score=10/_ai_score=10` 后 `_process(1/60)` 步进 30 帧，单帧 delta ≤ 0.2 × RAIN_SCORE_BAND_STEP（复用 TC-smooth-1 模式）
- **Test 7**（调制参数档位单调）：`_material = ParticleProcessMaterial.new()`，band 0 目标（r≈0.5）vs band 2 目标（r≈0.8）调 `_apply_to_particles()`，断言 velocity_min/max 与 alpha 单调上升（velocity +12%/+24%，alpha +0.0375/+0.075）
- **Test 8**（常量钉值）：`RAIN_SCORE_BAND_STEP == 0.15`、`RAIN_SCORE_BAND_1 == 10`、`RAIN_SCORE_BAND_2 == 20`
- **Test 9**（clamp 上限回归）：档位 2 + 球速上限 + 紧张 + 脉冲 → 仍 clamp 到 RAIN_MAX 1.0（RAIN_MAX 唯一边界源不破）

### Scenario B: L2 既有回归（不改动，验证网）

- 既有 12 个 _test_* 函数 70 断言全部保持（档位 0 逐位不变原则 → 天然全绿）；`run_tests.gd` 已注册 test_rain.gd（:35），零改动

### Scenario C: pipeline 测试（test_e2e_runner.py 新增 2 用例）

- **Test 1**（missed → L3 fail）：FAKE_CONFIG 注入 `{"fake_missed_shots": ["02_rain_heavy"]}` → fake godot 不写该 PNG 且写 `results.json` 含 missed → runner exit 1、summary L3_visual=fail
- **Test 2**（无 missed → L3 pass）：FAKE_CONFIG 空 missed（或 fake godot 默认不写 results.json）→ runner exit 0、L3_visual=pass（回归 `test_all_layers_pass_and_worktree_cleaned` 既有语义）

### Scenario D: L3 视觉（e2e_shots.json + run-e2e-review.sh）

- **Test 1**（两档差异证据对）：本地真实渲染 P5 连跑 3 次，`(02_midgame, 02_rain_heavy)` 帧间差异断言通过（Δluma ≥ 5 或 ratio ≥ 0.5%）；`02_rain_heavy` PNG 存在且非空
- **Test 2**（雨量门证据）：02_rain_heavy 截图前 `current_rain ≥ 0.55` 已被 capture 验证（shot ready 前置条件，日志可见）
- **Test 3**（诚实失败路径）：`results.json` missed 非空 → VISUAL_FAIL（Scenario C Test 1 的 shell 层验证）
- **Test 4**（settle 裕量）：settle_frames 60 ≥ 平滑收敛 0.5s（30 帧）2 倍 — 截图时雨量已收敛到档位目标

---

## 10. 验收条件映射（AC checklist，源自 Issue #491 body）

| AC | 内容 | 设计落实 |
|----|------|---------|
| DoD 1 | rain_curtain.gd 新增雨量分级逻辑（分数阈值驱动） | §2.1 score_band_for + §2.2 compute_target_rain 叠加；常量 RAIN_SCORE_BAND_1/2/STEP（§3.1） |
| DoD 2 | L2 逻辑测试：3 个阈值段的雨量参数断言通过 | §9 Scenario A Test 1-9（档位边界/步长/单调/平滑/调制/常量，≥9 断言） |
| DoD 3 | L3 视觉断言：e2e_shots.json 增加雨量档位截图（小雨/大雨两档差异可测） | §3.3 2 shot + §3.4 runner missed 检查；两档差异证据对 = (midgame, rain_heavy) 帧间差异 |
| DoD 4 | CI 三层全绿（L0 编译/L1 静态/L2 运行时 playthrough） | §8 Phase 5：check_compile.gd / run_tests.gd / playthrough_test.tscn 全绿 + pipeline 测试 |
| DoD 5 | review agent 本地 E2E 验证通过后 merge | 由 workflow 流水线执行（本 DESIGN 不 merge） |
| AC-验收 1 | 分数 0→21，雨幕从稀疏变密集，变化平滑无跳变 | §4 Flow 1/4：档位阶跃经 τ=0.15s 平滑收敛，单帧 ≤ 20% of step |
| AC-验收 2 | 雨量参数（密度/速率）随分数单调递增 | §1.3 裁决 1（ai_score=player_score 夹具下 0.5/0.65/0.8 严格单调）+ Test 5/7 |

### 明确不修改（继承 PRD §2.3/§3.1/§8）

- `compute_target_rain` 签名 / `set_intensity` 调试口 / `smooth_step` / `_apply_to_particles` 调制公式 — 全部不动
- `scenes/rain_curtain.tscn`（发射几何/amount=600/visibility_rect）— #465 配置不动（禁写 amount 红线不变）
- `scoring_manager.gd` / `game_manager.gd` / FSM / 物理 — 只读比分，零改动
- `scripts/e2e/analyze_bmp.py` / `framework/templates/e2e_capture.gd` — main 设施够用，零改动（向后兼容红线自动满足）
- 不复活 #466/#480/#485（区域/rain_signature/覆盖率像素机器 — 2026-08-14 重构清理已关闭）
- 不新增任何文件（含测试文件：新增用例落在既有 test_rain.gd / test_e2e_runner.py）
- 不引入新依赖（无 PIL/网络/新引擎特性）
