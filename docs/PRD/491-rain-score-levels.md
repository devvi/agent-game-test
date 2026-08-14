# PRD: [Test] 雨幕动态雨量可视化 — 按分数阈值切换雨量强度

> **Issue:** #491
> **标签:** enhancement, workflow/available, priority/medium
> **Agent:** game-research-agent
> **日期:** 2026-08-14
> **深度:** depth/standard（Issue 无 depth 标签，按 #389/#485 惯例按 standard 处理：Section 1–6 + 8 必填；Section 7 因存在真实技术不确定性（档位步长取值、E2E 大雨档可达性）而包含 2 个轻量实验）
> **所有权:** `content_ownership: mechanical`（分数→档位映射 = 机械可测；档位步长数值 = taste-draft 候补，human-review 定稿）
> **上游方案:** `docs/PLAN-rogue-pong.md` §3.2 动态雨量公式（2026-08-13 已确认）— 本 Issue 在该公式上增加**分数档位因子**维度
> **前置依赖:** #389（✅ CLOSED — 动态雨幕公式引擎已落地 main）、#465（✅ CLOSED — 雨幕粒子发射修复已落地 main）

---

## 1. 问题定义

### 1.1 当前状态（含预调查 — bug pre-investigation, Patch 10）

**核心发现：Issue 声称「雨幕系统(bg_rain)当前雨量固定」是 STALE CLAIM — rain_curtain.gd（#389，已合并）的雨量已经是公式驱动的动态值。真正的缺口是「按玩家绝对分数阈值分档」这一维度完全不存在：当前 player_score 只用于紧张因子（比分差 ≤ 2 → +0.2），没有任何分数档位因子。**

| 项 | 详情 |
|----|------|
| 预调查 1：`rain_curtain.gd` 已动态 | `compute_target_rain(speed, wave_index, pulse, breathing, player_score, ai_score)` = clamp(base 0.3 + 球速因子(0→0.3) + 波次因子(0.1/波) + 紧张因子(比分差≤2→+0.2) + 事件脉冲 − 喘息, 0.1, 1.0)；指数平滑 τ=0.15s（0.5s 达 95%）；调制 initial_velocity/scale/alpha，**禁写 amount**（#389 红线：改 amount 重启粒子系统→跳变） |
| 预调查 2：分数输入已接线 | `_update_inputs()` 每帧读 `/root/GameManager` 的 player_score/ai_score（rain_curtain.gd:113-120），公式引擎已消费 player_score — **数据管道已通，缺的是档位因子本身** |
| 预调查 3：Issue 命名「bg_rain」 | Issue body 称「雨幕系统(bg_rain)」— 实际仓库文件为 `mini-pong/gdscripts/rain_curtain.gd` + `scenes/rain_curtain.tscn`，Main.tscn 节点 `AtmosphereLayer/RainCurtain`（L0 氛围层）。**映射：bg_rain = RainCurtain 节点 = rain_curtain.gd**（Patch 4：Issue 文件域命名可异于实际文件，需在 PRD 显式映射） |
| 预调查 4：L2 测试设施 | `test_rain.gd`（327 行，70 断言全绿）已覆盖 clamp 边界/公式单调性/紧张因子等号/平滑无跳变/脉冲回落/契约默认值/NaN 防护/资源完整性/#465 发射配置 — **无分数档位断言**（因档位逻辑不存在） |
| 预调查 5：L3 视觉断言设施 | main 的 `analyze_bmp.py`（340 行）仅 4 重基础断言（非黑/色数/主题色/帧间差异）；**区域/雨签/覆盖率断言（#466/#480/#485 设计）仅存在于未合并的 impl/466 分支**，PR #475 关闭未合入，#466/#480/#485 已在 2026-08-14 重构清理中关闭 — **main 无像素级雨量断言能力**，本 Issue 的 L3 必须在 main 现有设施（require 节点属性门 + 帧间差异）上设计 |
| 预调查 6：E2E 播放可达性 | e2e_shots.json autoplay AI-vs-AI（PlayerPaddle error 24 vs AIPaddle error 200 → 玩家侧显著占优），03_gameover shot 以 300s deadline 等待整局打完（score 0→21）— **分数单调爬升，20+ 档位可达**；capture 驱动 `require` 支持读任意节点数值属性（含 RainCurtain.current_rain） |

### 1.2 预期行为（验收条件，源自 Issue #491）

1. **雨量按玩家分数阈值分档** — 0-9 分 = 小雨（档位 0），10-19 分 = 中雨（档位 1），20+ 分 = 大雨（档位 2）；档位因子单调递增地叠加到现有雨量公式
2. **雨量参数随分数单调递增** — 分数 0→21 爬升时，雨量目标值非递减（档位边界 +0.15/档，taste-draft 候选），调制参数（密度/速率语义 = initial_velocity 速率 + scale/alpha 视觉密度）随 current_rain 单调上升（既有调制映射已保证）
3. **变化平滑无跳变** — 档位切换（9→10、19→20）是目标值阶跃，由既有指数平滑（τ=0.15s）在 0.5s 内收敛，无单帧跳变 >20%（复用 AC4 机制）
4. **L2 逻辑测试：3 个阈值段的雨量参数断言通过** — test_rain.gd 新增档位边界/单调性/平滑断言
5. **L3 视觉断言：e2e_shots.json 增加雨量档位截图** — 新增 02_rain_light（小雨档）/ 02_rain_heavy（大雨档）两 shot，帧间差异断言可测两档差异；大雨档 shot 以 `current_rain ≥ 0.55` 节点属性门保证截到的确实是高雨量帧
6. **CI 三层全绿** — L0 编译（check_compile.gd）/ L1 逻辑（run_tests.gd 含 test_rain.gd）/ L2 运行时（playthrough_test.tscn）全部通过

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 开局（0-9 分） | 每次开局 | 细雨开场：雨量 = base+球速+紧张（档位 0 无加成），与 #389 情境表「波次开始 0.3」一致 |
| B | 中盘（10-19 分） | 每局中期 | 中雨：档位 1 叠加 +0.15，配合球速/紧张因子，雨幕明显加密 |
| C | 终盘（20-21 分） | 每局末段 | 大雨：档位 2 叠加 +0.30，接近 clamp 上限，雨幕最密集 — 「最后一击」的视觉高潮 |

### 1.4 技术约束（继承自 Issue #491 + PLAN §3.2 + #389/#465）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，本项目 = `mini-pong/`（自有 project.godot）；`gdscripts/` 为源码目录 |
| 画幅 | 720×1280 竖屏（#383）；雨幕全屏发射（#465 已修复 visibility_rect/emission_rect_extents） |
| 公式 | PLAN §3.2 确认版为基底；本 Issue 新增「分数档位因子」维度；clamp(0.1, 1.0) 不变 |
| 档位映射 | 0-9 → 档位 0（+0）、10-19 → 档位 1（+0.15）、20+ → 档位 2（+0.30）；**机械可测**；步长 = taste-draft 候补 |
| 平滑 | 档位切换经既有指数平滑（τ=0.15s），0.5s 收敛，无跳变；**禁写 amount**（#389 红线不变） |
| 输入接线 | 只读 GameManager.player_score（已接线）；不改 scoring_manager/game_manager/FSM/物理 |
| 不变项 | `compute_target_rain` 签名不变（player_score 已是参数）；调制通道（velocity/scale/alpha）不变；`set_intensity` 调试口语义不变（<0 = 公式模式） |
| 测试即验收 | L2 断言进 `test_rain.gd`（run_tests.gd 已注册）；L3 走 e2e_shots.json + run-e2e-review.sh P5 |
| 深度 | standard（无 depth 标签）→ Section 1-6 + 8；Section 7 含 2 个轻量实验 |

### 1.5 范围界定（与既有 PRD 去冲突 — Patch 14）

| 相关 PRD | 覆盖范围 | 本 PRD 不重复覆盖 |
|---------|---------|------------------|
| #389（动态雨幕，已合并） | 雨量公式引擎 + 粒子调制 + 平滑 + 契约 API | ❌ 不重设计公式/调制/平滑；只在公式上**叠加档位因子** |
| #465（雨幕粒子修复，已合并） | 发射几何/可视窗口/数量 | ❌ 不改发射配置 |
| #466/#480/#485（L3 区域断言，关闭未合并） | 像素级 rain_signature/区域/覆盖率断言 | ⚠️ **不复活**；L3 用 main 现有设施（require 节点属性门 + 帧间差异）满足「两档差异可测」，在 §4 说明理由 |
| #476（clear_color 修复，已合并） | L3 断言 bg 语义 | ❌ 不涉及（无区域断言） |

---

## 2. 设计意图

### 2.1 为什么当前状态存在

| 现状来源 | Issue | 贡献 |
|---------|-------|------|
| 雨量公式引擎（base+球速+波次+紧张+脉冲−喘息） | #389 | 公式已在 main 落地并测试全绿；player_score 仅用于紧张因子（比分差维度） |
| 「分数阈值分档」从未被设计 | PLAN §3.2 情境表 | 情境表按「球速/胶着/穿墙/升级/失败」驱动，**没有按玩家绝对分数分档的条目** — 本 Issue 是 PLAN 未覆盖的新需求，不是回归 |
| L3 区域断言被关闭 | #466/#480/#485（2026-08-14 重构清理） | 像素级 rain_signature 机器未合入 main；本 Issue 的 L3 必须兼容 main 现状 |

### 2.2 为什么现在改

1. **情绪仪表盘缺「绝对进度」维度**：PLAN §3.2 明确「雨是情绪仪表盘」，但当前公式只反映「相对紧张度」（比分差/球速），不反映「玩家离胜利多近」。分数档位让雨幕成为**进度可视化**：越接近 21 分，雨越密 — 与 PONG://21 的终局高潮（20+ 大雨）形成叙事闭环。
2. **Issue 是 [Test] 型**：DoD 的重心是「可被视觉 E2E 断言验证」— 档位逻辑（机械可测）+ L2 三段断言 + L3 两档截图，三者构成完整验证链。当前缺档位逻辑，L2/L3 无从谈起。
3. **改动面收敛**：公式引擎/平滑/调制/数据管道全部就绪，只需在 `compute_target_rain` 增加档位因子 + 常量 + 测试 + e2e_shots 两 shot — 成本最低的时刻。
4. **main L3 设施已确认可承载**：capture 驱动的 `require` 能读 `RainCurtain.current_rain`（节点属性门），帧间差异断言（--diff-with）已存在 — 「两档差异可测」不需要复活 #466 像素机器。

### 2.3 先前约束

| 约束 | 详情 |
|------|------|
| #389 公式 | `clamp(base + 球速 + 波次 + 紧张 + 脉冲 − 喘息, 0.1, 1.0)`；RAIN_MIN/RAIN_MAX 唯一边界源；禁写 amount |
| #389 平滑 | τ=0.15s 指数平滑；0.5s 收敛 95%+；单帧变化 ≤ 20% of range（TC-smooth-1） |
| #465 发射 | visibility_rect = Rect2(-360,-640,720,1280)；emission_rect_extents = Vector2(360,640)；amount=600 — **不改** |
| WIN_SCORE | 21 分制（constants.gd:84）；档位 2 覆盖 20-21 分（21 = 终局） |
| 只读比分 | 不改 scoring_manager/game_manager 信号链；rain_curtain 每帧读属性即可 |
| 测试即验收 | test_rain.gd 风格（_make_curtain 纯逻辑实例 + 文件内容断言）；e2e_shots.json 走 loop 组（gdscripts/.*\.gd 命中） |
| 平滑/单调验收 | 「变化平滑无跳变」+「雨量参数随分数单调递增」= 本 Issue 验收标准，测试必须钉死 |

---

## 3. 影响分析

### 3.1 直接改动文件

| 文件 | 模块 | 改动性质 |
|------|------|---------|
| `mini-pong/gdscripts/rain_curtain.gd` | 公式引擎 | **修改** — `compute_target_rain` 增加档位因子：`score_band = clampi(player_score / 10, 0, 2)`（0-9→0, 10-19→1, 20+→2），`raw += float(score_band) * CONSTS.RAIN_SCORE_BAND_STEP`；新增纯函数 `score_band_for(score: int) -> int`（headless 可单测） |
| `mini-pong/gdscripts/constants.gd` | 常量 | **修改** — 新增 `RAIN_SCORE_BAND_STEP: float = 0.15`（taste-draft 候选，human-review 定稿）、`RAIN_SCORE_BAND_1: int = 10`、`RAIN_SCORE_BAND_2: int = 20`（档位边界，机械固定） |
| `mini-pong/tests/test_rain.gd` | L2 测试 | **修改** — 新增 `_test_score_bands()`：档位边界（9→0, 10→1, 19→1, 20→2, 21→2）、步长值（+0.15/+0.30）、0→21 单调不减（固定其他输入）、档位切换平滑无跳变（9→10 阶跃复用 TC-smooth 模式）、调制参数随档位单调（_apply_to_particles 于档位 0 vs 2） |
| `mini-pong/e2e_shots.json` | L3 shot 计划 | **修改** — loop 组新增 2 shot：`02_rain_light`（state PLAYING, require player_score ≥ 1, settle_frames 60）与 `02_rain_heavy`（state PLAYING, require `RainCurtain.current_rain ≥ 0.55`, settle_frames 60, deadline_s 300） |
| `scripts/run-e2e-review.sh` | E2E runner | **修改（最小）** — P5 capture 后检查 `$OUT/shots/results.json` 的 `missed` 数组非空 → VISUAL_FAIL（**missed-shot 判 fail**：防大雨档 shot 因 AI 意外先胜而静默漏截 — 复活 #480 AC4 的最小实现，见 §4.3 方案 B 论证） |

### 3.2 新文件

| 文件 | 用途 |
|------|------|
| 无 | 全部改动落在既有文件（与 #485 同款 class：逻辑 + 测试 + 配置 + runner 一行检查） |

### 3.3 间接影响（需回归验证）

| 文件 | 影响 | 处理 |
|------|------|------|
| `mini-pong/tests/e2e_playthrough.gd` | 真实物理整局到 21 分 — 分数爬升期间 rain 档位变化不影响物理/信号断言 | 零改动；L1 全绿验证 |
| `mini-pong/tests/playthrough_driver.gd`（L2 运行时） | Main.tscn 实例化含 RainCurtain — 档位逻辑运行期间不报错即可 | 零改动；L2 运行时绿验证 |
| `mini-pong/tests/test_main_scene.gd` | Main.tscn 结构断言（AtmosphereLayer/RainCurtain 存在） | 零改动（节点未动） |
| `scripts/e2e/analyze_bmp.py` | **不改** — L3 用既有帧间差异 + require 节点属性门，不引入区域/雨签断言 | 零改动（向后兼容红线自动满足） |
| `framework/templates/e2e_capture.gd` | **不改** — `require` 单条件 `{node, prop, min}` 已够用（main 现状），无需数组化 | 零改动（模板级兼容红线自动满足） |
| `docs/GAME_DESIGN/` | 雨量公式新增档位维度 | 实现 PR merge 后由 review agent 按 GDD 维护规则增量更新 |

### 3.4 数据流影响

```
GameManager.player_score（autoload，只读）
    │  每帧 _update_inputs() 读取（已接线）
    ▼
rain_curtain.gd compute_target_rain(..., player_score, ai_score)
    ├── 既有因子: base(0.3) + 球速(0→0.3) + 波次(0.1/波) + 紧张(比分差≤2→+0.2) + 脉冲 − 喘息
    ├── 新增因子: score_band = clampi(player_score/10, 0, 2)   # 0-9→0, 10-19→1, 20+→2
    │              raw += score_band * RAIN_SCORE_BAND_STEP(0.15)   # +0 / +0.15 / +0.30
    ▼
target = clamp(raw, 0.1, 1.0)
    ▼
指数平滑（τ=0.15s）: current += (target − current) × (1 − exp(−delta/τ))   # 档位阶跃平滑收敛
    ▼
粒子调制（不改 amount）: initial_velocity ×(0.6+0.8r) / scale ×(0.5+0.7r) / alpha 0.15+0.25r
    ▼
L2: test_rain.gd 断言档位边界/单调/平滑
L3: e2e_shots.json 02_rain_light(小雨) ──帧间差异──► 02_rain_heavy(大雨, require current_rain≥0.55)
```

### 3.5 文档更新

- [ ] `docs/PRD/491-rain-score-levels.md`（本文件）
- [ ] `docs/GAME_DESIGN/` — 实现 PR merge 后由 review agent 增量更新（雨量公式档位维度）
- [ ] 本 PRD merge 后自动推进 Issue #491 → `workflow/plan`（workflow-chain）

---

## 4. 方案对比

### 4.1 方案 A：离散分数档位因子（推荐）

**描述：** `compute_target_rain` 新增 `score_band = clampi(player_score/10, 0, 2)`，每档叠加 `RAIN_SCORE_BAND_STEP`（0.15，taste-draft）到 raw 后统一 clamp。纯函数 `score_band_for()` 可 headless 单测。L3 用 main 现有设施（require 节点属性门 + 帧间差异）验证两档差异。

| 维度 | 评估 |
|------|------|
| Pros | ① 完全匹配 Issue「按分数阈值切换」语义（离散档位而非连续渐变）② 公式改动最小（raw += 一行 + 一个纯函数），签名不变 ③ 单调性由构造保证（档位随分数非递减，步长 > 0）④ 平滑复用既有 τ=0.15s，无新机制 ⑤ L2/L3 全部落在既有测试设施 ⑥ 不复活已关闭的 #466 像素机器，尊重重构清理决策 |
| Cons | ① 档位步长 0.15 是 taste-draft 候选，需 human-review 定稿（可调）② 档位内雨量平坦（仅球速/紧张微调），非连续渐变 — 但 Issue 明示「阈值切换」，离散即意图 |
| Risk | **Low** — 纯公式叠加，既有 70 断言全部保持（档位 0 时 raw 不变 → 既有 TC 不破坏）；E2E 大雨档可达性需 Spike 2 实证 |
| Effort | 0.5 天（逻辑）+ 0.5 天（测试）+ 0.5 天（e2e 配置/runner 检查） |

### 4.2 方案 B：连续分数斜坡因子（player_score/21 × max）

**描述：** 档位改为连续斜坡：`score_factor = player_score / WIN_SCORE * RAIN_SCORE_MAX_CONTRIB`，雨量随分数连续上升。

| 维度 | 评估 |
|------|------|
| Pros | ① 连续无阶跃，视觉上更顺滑 ② 无需档位边界常量 |
| Cons | ① **违反 Issue 明示语义**「0-9 分小雨,10-19 中雨,20+ 大雨」— 这是离散阈值定义，连续斜坡没有「档位」概念 ② DoD 3 的「两档差异可测」需要可区分的档位截图，连续斜坡下 02_rain_light（分数 1）与 02_rain_heavy（分数 20）差异仍可测但无档位语义 ③ 测试「3 个阈值段的雨量参数断言」无明确边界可断言 |
| Risk | **Med** — 与 Issue 验收语义冲突 |
| Effort | 0.5 天 |

### 4.3 方案 C：复活 #466 像素级 rain_signature/覆盖率断言

**描述：** 把 impl/466 分支的 rain_signature + rain_grid_coverage + shot 级 visual 配置移植到 main，L3 用像素覆盖率断言两档差异。

| 维度 | 评估 |
|------|------|
| Pros | ① 像素级雨量证据最强（覆盖率直接测雨幕）② #485 已设计动态 bg 采样解决相位假阳性 |
| Cons | ① **复活已关闭工作**（#466/#480/#485 在 2026-08-14 重构清理中明确关闭，PR #475 关闭未合入）— 与用户决策冲突 ② 依赖 impl/466 分支未合入代码，基线脆弱 ③ 需同步引入 #485 动态 bg 采样（BgPulse 相位问题，否则 rain 假阳性）— 范围膨胀 ④ analyze_bmp.py 改动大（+150 行），违反「main 设施够用则不加新机器」的克制原则 |
| Risk | **High** — 重新打开已关闭的 scope + BgPulse 相位回归风险 |
| Effort | 2-3 天 |

### 4.4 推荐

**方案 A（离散分数档位因子）+ 方案 A 的 L3 最小配套（runner missed-shot 检查）。**

理由：
1. **语义完全匹配**：Issue 明确定义「0-9 小雨 / 10-19 中雨 / 20+ 大雨」离散阈值 — 方案 A 的档位因子就是这条规则的直接实现；方案 B 违反语义，方案 C 超出需求。
2. **机械可测**：档位映射 = `clampi(score/10, 0, 2)` 纯函数，L2 可对边界（9/10/19/20/21）穷举断言；单调性由构造保证；平滑复用既有机制 — 全部符合「机器管结构」原则。
3. **L3 在 main 设施内自洽**：capture 驱动 `require` 能读 `RainCurtain.current_rain`（节点属性门）— 大雨档 shot 只有在雨量真实达到 0.55+ 才截图，这是**运行时雨量状态证据**（比像素覆盖率更直接）；两 shot 帧间差异断言（--diff-with, Δluma ≥ 5 或 ratio ≥ 0.5%）满足「两档差异可测」。方案 C 的像素机器是更强的证据，但复活关闭工作 + BgPulse 相位风险不划算。
4. **DoD 4 的三层 CI 已有承载**：L0 编译（rain_curtain.gd 语法）、L1 逻辑（test_rain.gd 新增断言）、L2 运行时（playthrough 不回归）— 全部在 run-e2e-review.sh 既有流程内。
5. **runner missed-shot 检查是 DoD 3 的诚实性要求**：main 的 P5 目前 capture 退出码只 log 不判 fail（#480 已知缺口）— 若 AI 意外先胜（player 未到 20），02_rain_heavy 会静默漏截导致假绿。加 3-5 行检查（读 results.json missed）即闭合，这是 #480 AC4 的最小实现，不复活其完整 runner 重构。

---

## 5. 边界条件与验收

### 正常路径（AC 检查清单，映射 Issue body DoD）

- [ ] **AC1（DoD 1）: rain_curtain.gd 新增雨量分级逻辑（分数阈值驱动）** — `score_band_for(score)` 纯函数 + `compute_target_rain` 叠加档位因子；`clampi(score/10, 0, 2)` 映射 0-9→0 / 10-19→1 / 20+→2；常量 `RAIN_SCORE_BAND_1=10` / `RAIN_SCORE_BAND_2=20` / `RAIN_SCORE_BAND_STEP=0.15`
  - 验证：score_band_for 边界穷举（9→0, 10→1, 19→1, 20→2, 21→2, 0→0, 负数→0）；档位 0 时 raw 与现状逐位一致（既有 70 断言不破坏）
- [ ] **AC2（DoD 2）: L2 逻辑测试 3 个阈值段断言通过** — `_test_score_bands()` 新增 ≥8 断言：
  - 档位边界：9→0、10→1、19→1、20→2、21→2（clamp 到 2）
  - 步长值：档位 1 相对档位 0 目标差 = +0.15；档位 2 相对档位 0 = +0.30（固定其他输入）
  - 单调不减：player_score 0→21 全扫，compute_target_rain 非递减（固定 speed/wave/pulse/breathing）
  - 平滑无跳变：档位阶跃（9→10）后 _process 步进，单帧变化 ≤ 20% of range（复用 TC-smooth-1 模式）
  - 调制单调：档位 0 vs 2 下 `_apply_to_particles` 的 velocity/alpha 单调上升
- [ ] **AC3（DoD 3）: L3 视觉断言 — e2e_shots.json 增加雨量档位截图（小雨/大雨两档差异可测）** — loop 组新增：
  - `02_rain_light`: state PLAYING, require player_score ≥ 1（首分即触发，分数 1-3 = 档位 0）, settle_frames 60（雨量平滑收敛）
  - `02_rain_heavy`: state PLAYING, require `/root/Game/AtmosphereLayer/RainCurtain` `current_rain` ≥ 0.55（**节点属性门**：仅当雨量真实达到大雨级才截图）, settle_frames 60, deadline_s 300（整局可达）
  - 验证：两 shot 相邻帧间差异断言通过（Δluma ≥ 5.0 或 ratio ≥ 0.5%，--diff-with）；results.json missed 为空（runner 检查）
- [ ] **AC4（DoD 4）: CI 三层全绿** — `godot --path mini-pong/ --headless --script tests/check_compile.gd`（L0）、`run_tests.gd`（L1，含新增档位断言）、`tests/playthrough_test.tscn`（L2 运行时）全部 exit 0
- [ ] **AC5（DoD 5）: review agent 本地 E2E 验证通过后 merge** — 由 workflow 流水线执行（本 PRD 不 merge）

### 边界情况（Edge Cases）

1. **档位 2 的上界**：WIN_SCORE=21，分数 20-21 属档位 2；`clampi(score/10, 0, 2)` 对 21 也返回 2（不越界）；终局后分数冻结，档位不再变
2. **负分/异常分数**：score < 0 → clampi 返回 0（档位 0）；NaN 防护沿用既有（player_score 是 int，无 NaN 面）
3. **档位阶跃与平滑**：9→10 时 target 阶跃 +0.15，current 以 τ=0.15s 平滑收敛 — 不产生单帧跳变（TC-smooth 复用）；若分数跳档（如连得 3 分跨 2 档），平滑同样收敛，无跳变
4. **档位 0 的既有行为不变**：0-9 分时 raw 与 #389 公式逐位一致 — 既有 70 断言（TC-clamp/TC-mono/TC-tension/TC-default 等）全部保持，防回归
5. **clamp 边界**：档位 2 + 球速上限 + 紧张 + 脉冲（0.3+0.3+0.2+0.3+0.4 = 1.5）→ clamp 到 1.0；RAIN_MAX 仍为唯一边界源
6. **L3 大雨档 shot 的可达性**：AI-vs-AI（player error 24 vs AI error 200）玩家侧显著占优，player_score 通常先到 20；若 AI 意外先胜（player 未到 20），current_rain 可能达不到 0.55 → 02_rain_heavy missed → **runner missed-shot 检查判 fail**（诚实失败，非假绿）；Spike 2 实证可达性后按实测校准阈值
7. **settle_frames 与平滑**：雨量从当前值向档位目标收敛需 ~0.5s（30 帧 @60fps）— settle_frames 60 留双倍裕量；截图时 current_rain 已接近档位目标
8. **其他 shot 不受影响**：01_title（MENU 雨量 = base 档位 0）/ 02_midgame（分数 ≥ 1）/ 03_gameover 逻辑不变；新增 shot 不改变既有 shot 的 require 语义

### 失败路径（Failure Paths）

1. **档位因子破坏既有公式断言** → 档位 0 时 raw 必须逐位等于现状；test_rain.gd 既有 70 断言作为回归网，任何偏差立即暴露
2. **L3 大雨档 shot 静默漏截（假绿）** → runner 增加 results.json missed 检查（VISUAL_FAIL）；review agent 本地 E2E 复核截图像素
3. **current_rain ≥ 0.55 门不可达**（AI 先胜或分数未到）→ Spike 2 实证后校准阈值（如 0.45）或改 require player_score ≥ 20（分数门替代雨量门）；不得删除门（门是「两档差异可测」的运行时证据）
4. **e2e_shots.json require 节点路径错误** → capture 打 `require node not found` 并 shot 永不 ready → deadline → missed → runner 判 fail（诚实暴露）；路径 `/root/Game/AtmosphereLayer/RainCurtain` 已按 Main.tscn 节点树核实
5. **taste-draft 步长被 future 误改** → 常量 RAIN_SCORE_BAND_STEP 单点定义 + test_rain.gd 断言钉值；human-review 定稿后进常量快照

---

## 6. 依赖与阻塞

### 依赖

| 依赖 | 状态 | 风险 |
|------|------|:----:|
| #389 动态雨幕公式引擎 | ✅ CLOSED（main 已含） | None — 公式基底就绪 |
| #465 雨幕粒子发射修复 | ✅ CLOSED（main 已含） | None — 发射配置不动 |
| #383 竖屏 720×1280 | ✅ CLOSED | None — 坐标就绪 |
| PLAN-rogue-pong §3.2 公式 | ✅ 已确认 | None — 唯一公式权威源 |
| main L3 设施（require 属性门 + 帧间差异） | ✅ 已在 main | Low — 需 Spike 2 实证 current_rain 门可达性 |
| runner results.json missed 检查 | ⚠️ main 缺失（#480 关闭未合入） | Low — 3-5 行最小实现（§4.4 论证），不复活完整 #480 |

### 阻塞（Blocks）

| 后续工作 | 优先级 | 说明 |
|---------|:---:|------|
| （无） | — | 本 Issue 不阻塞其他流水线；档位因子为纯增量 |

### 依赖链

```
PLAN-rogue-pong.md §3.2（2026-08-13 确认公式）
        │
        ▼
#389 动态雨幕（✅ main）─► #465 粒子修复（✅ main）─► #491 分数档位因子（本 Issue）
                                                          │
                                                          ├──► L2: test_rain.gd 档位断言（run_tests.gd 注册）
                                                          └──► L3: e2e_shots.json 02_rain_light/02_rain_heavy
                                                                 + runner missed-shot 检查
```

---

## 7. Spike / 实验

> depth/standard 下 Section 7 非必填，但存在两项真实技术不确定性（档位步长取值、L3 大雨档可达性），故包含 2 个轻量实验，成本各 ≤0.5 天：

### 实验 1：档位步长与既有情境表的视觉区分度

- **问题**：RAIN_SCORE_BAND_STEP = 0.15 是否让「小雨/中雨/大雨」三档在屏幕上可感知区分，且不破坏 #389 情境表（0.3 平静 → 1.0 宣泄）的比例感？
- **方法**：headless 下对 `compute_target_rain` 全输入空间采样（档位 0/1/2 × 球速 330/500/627 × 紧张 0/1），输出调制参数（velocity/alpha）的档位间 delta；对比既有 speed/tension 因子量级，确认档位贡献不淹没情境因子
- **预期结果**：档位 delta（+0.15/+0.30 → alpha +0.0375/+0.075，velocity +12%/+24%）与 speed/tension 同量级，可感知且不抢戏；若 0.15 过弱，调至 0.2 并在 PRD §8 记录
- **对方案影响**：定稿 RAIN_SCORE_BAND_STEP 数值（taste-draft 交 human-review）

### 实验 2：L3 大雨档 shot 可达性实证（AI-vs-AI 真实播放）

- **问题**：02_rain_heavy 的 `current_rain ≥ 0.55` 门在 AI-vs-AI（error 24 vs 200）整局中是否必然可达？AI 先胜时是否漏截？
- **方法**：本地真实渲染跑 run-e2e-review.sh P5（display macos + opengl3），带新增 2 shot 的 e2e_shots.json，观察：player_score 是否先到 20、current_rain 峰值、02_rain_heavy 是否成功截到、results.json missed 是否为空；连跑 3 次验证稳定性
- **预期结果**：player 侧占优（error 24 vs 200）→ 20+ 可达，current_rain 峰值 ≥ 0.7，shot 3/3 成功；若 0.55 门不可达，校准阈值（0.45）或改 require player_score ≥ 20
- **对方案影响**：定稿 L3 shot 配置（require 阈值/deadline）；若 AI 先胜概率显著，考虑 runner missed 检查必然触发 → 诚实失败可接受

---

## 8. 延续上下文（交给 plan agent）

### 系统状态

- Issue #491 当前 `workflow/available`，本 PRD merge 后 workflow-chain 推进 → `workflow/plan`
- 基线：`main` HEAD = `a31aa60`；L1 逻辑套件当前全绿（2274 passed, 0 failed，含 Rain Curtain 70 断言）；pipeline 测试 162 全绿
- 上游方案已确认：`docs/PLAN-rogue-pong.md` §3.2（公式权威源）；本 PRD 在其上叠加档位因子维度
- **已核实的关键事实（plan agent 直接继承，无需重查）**：
  - `rain_curtain.gd:61` `compute_target_rain(speed, wave_index, pulse, breathing, player_score, ai_score)` — player_score 已是参数；`_update_inputs()`（:100-120）每帧读 `/root/GameManager` 比分
  - `constants.gd:136-146` RAIN_* 组（BASE 0.3 / MIN 0.1 / MAX 1.0 / TAU 0.15 / SPEED 0.3 / TENSION_THRESHOLD 2 / TENSION_BONUS 0.2 / WAVE_STEP 0.1 / PULSE_PIERCE 0.4 / BREATHING_DROP 0.15）
  - `test_rain.gd` 70 断言全绿；`_make_curtain()` 纯逻辑实例模式（@onready null → 公式层可单测）
  - `e2e_shots.json` loop 组 3 shot（01_title/02_midgame/03_gameover）；capture `_require_ok` 支持 `{node, prop, min}` 单条件（main 现状，无数组化）
  - Main.tscn 节点：`AtmosphereLayer`（CanvasLayer, parent="."）→ `RainCurtain`（rain_curtain.tscn 实例）；GameManager 为 autoload（`/root/GameManager`）
  - run-e2e-review.sh P5：capture 退出码只 log 不判 fail（#480 缺口）→ 需加 results.json missed 检查

### 关键决策（plan agent 必须继承）

1. **方案 A：离散分数档位因子** — `score_band = clampi(player_score/10, 0, 2)`，`raw += score_band * RAIN_SCORE_BAND_STEP`；纯函数 `score_band_for(score)` 独立可测；`compute_target_rain` 签名不变
2. **常量**：`RAIN_SCORE_BAND_STEP = 0.15`（taste-draft 候选，Spike 1 实证 + human-review 定稿）、`RAIN_SCORE_BAND_1 = 10`、`RAIN_SCORE_BAND_2 = 20`（机械固定）— 进 constants.gd RAIN_* 组
3. **L2 测试**：test_rain.gd 新增 `_test_score_bands()`（≥8 断言：边界穷举 9/10/19/20/21、步长值、0→21 单调不减、9→10 阶跃平滑无跳变、调制参数档位单调）；档位 0 时既有断言不破坏（回归网）
4. **L3**：e2e_shots.json loop 组新增 `02_rain_light`（require player_score ≥ 1, settle 60）与 `02_rain_heavy`（require `RainCurtain.current_rain ≥ 0.55`, settle 60, deadline_s 300）；**不改** analyze_bmp.py / e2e_capture.gd（main 设施够用）
5. **runner 最小配套**：run-e2e-review.sh P5 capture 后读 `$OUT/shots/results.json`，`missed` 非空 → VISUAL_FAIL（3-5 行；#480 AC4 最小实现，不复活其完整重构）
6. **档位 0 逐位不变**：0-9 分 raw 与 #389 公式一致 → 既有 70 断言全部保持
7. **禁写 amount / 只读比分 / 不改 FSM/物理** — #389 红线不变
8. **taste-draft 交接**：档位步长数值与「小雨/中雨/大雨」视觉浓度曲线走 human-review 定稿（用户哲学：机器管结构，人管味道）

### 实现顺序建议（plan agent 参考）

1. `constants.gd`（RAIN_SCORE_BAND_* 常量）→ 2. `rain_curtain.gd`（score_band_for + compute_target_rain 叠加）→ 3. `test_rain.gd`（_test_score_bands + run_tests.gd 已注册，无需改注册）→ 4. 本地 headless L1 全绿（含既有 70 断言回归）→ 5. `e2e_shots.json`（2 新 shot）→ 6. `run-e2e-review.sh`（missed 检查 3-5 行）→ 7. Spike 2 实证 L3 大雨档可达性（本地真实渲染 P5 连跑 3 次）→ 8. L0/L1/L2 三层 + pipeline 测试全绿

### 主要风险

- 档位步长 taste 值不合适 → Spike 1 实证 + human-review 定稿
- L3 大雨档 shot 不可达/漏截 → Spike 2 实证 + 阈值校准；runner missed 检查保证诚实失败
- 既有公式断言回归 → 档位 0 逐位不变原则 + 70 断言回归网

### 交接清单

- [ ] 本 PRD 文件 `docs/PRD/491-rain-score-levels.md`
- [ ] 上游方案 `docs/PLAN-rogue-pong.md` §3.2（公式权威源）
- [ ] 预调查证据：rain_curtain.gd:61-88（公式/计算入口）、:100-120（比分读取）、constants.gd:136-146（RAIN_* 组）、test_rain.gd（70 断言基线）、e2e_shots.json（loop 组现状）、run-e2e-review.sh P5（missed 缺口）
- [ ] 实测基线：`godot --path mini-pong/ --headless --script tests/run_tests.gd` 当前全绿（2274 passed, 0 failed）— 实现前可复跑对照
