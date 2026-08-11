# DESIGN: [Content] Mini Pong 手感校准草稿 — 球速/反弹角/AI强度 (A1)

> **Parent Issue:** #367
> **Agent:** game-plan-agent
> **Date:** 2026-08-11
> **Approach:** A + A（PRD §4.1-A 草稿值内联 `constants.gd`；§4.2-A 新建 `docs/TASTE.md` 承载校准接口）— 确认 PRD 推荐，无分歧
> **Reference PRD:** docs/PRD/367-feel-calibration-draft.md
> **所有权:** `content_ownership: taste-draft`（人机共做 v4）— 草稿达标即 merge；PR body 用 `Parent #367`（不写 Closes）；merge 后由 review agent 打 `status/human-review` 并 assign 用户定稿
> **深度:** depth/light — 无 TASKS doc

---

## 1. 概述

本 Issue 是 A1「数值即表达」的 taste-draft 内容 Issue —— **实现即草稿值**。当前 `constants.gd` 的 11 个手感参数全是"物理正确"的默认值（`BALL_INITIAL_SPEED=300.0`、`AI_SPEED_BOOST=1.2` …），无任何 taste 注入。本设计把 PRD §4.3 的草稿值集合固化为 implement 的**唯一契约**：11 个参数改为带 taste 方向的草稿值，每条带 `# DRAFT` 注释（该值影响什么 + 2–3 候补值 + 情感断言）；同时新建 `docs/TASTE.md` 作为品味档案初版（候补值表 + 试玩剧本 + 情感断言 = 校准接口三件套）；机械部分（测试字面量）随草稿值同步更新，**无 `# DRAFT` 残留**。

**消费链（已核实，改常量即改手感）：**

```
GameConstants（constants.gd，# DRAFT 草稿值 + 影响 + 候补 + 情感断言注释）
    │  const → @export 默认值（ball.gd L8-24 / paddle.gd L18-22，场景 Main.tscn 无导出覆盖）
    ▼
运行时手感（球速曲线 / 反弹角 / AI 强度 / 操控响应）
    │
    ├──► 玩家试玩：自动对打（auto_play_test.gd 100 局）+ 手动一局（图形模式）
    ▼
docs/TASTE.md（候补值表 + 情感断言 + 试玩剧本）← 校准接口（用户定稿对照物）
```

**Plan 阶段边界**：本阶段只产出本文档（`docs/DESIGN/367-*.md`），不写任何 `.gd` / `.tscn` / 测试代码 —— 下列所有修改清单是给 implement agent 的契约。

---

## 2. 草稿值集合（核心契约）

> 来源：PRD §4.3（research 建议）。implement **必须**按此表填值，可微调但不得违反 §6 边界 1（单次 rally 跳变 ≤20%）与三要素（影响/候补/情感断言）齐全要求。

| # | 参数 | 现值（物理正确） | **DRAFT 草稿值** | 候补值 | 该值影响什么 | 情感断言（体验引擎） |
|---|------|:---:|:---:|:---:|------|------|
| 1 | `BALL_INITIAL_SPEED` | 300.0 | **330.0** | 320.0 / 340.0 | 开局节奏与横穿时间（1280px：300→4.3s，330→3.9s） | 利落开局——第一拍就有街机速度感 |
| 2 | `BALL_SPEED_INCREMENT` | 1.05 | **1.07** | 1.06 / 1.08 | 每次击打加速幅度（指数曲线斜率；1.07^10≈1.97 恰好触顶） | 每一次反弹都更紧迫（单次 +7%，远低于 20% 廉价感红线） |
| 3 | `BALL_MAX_SPEED_MULTIPLIER` | 2.0 | **1.9** | 1.8 / 2.0 | 速度上限（330×1.9≈627 px/s ≈ 2.0s 横穿）——上限越高越易"突然失控" | 高压但可控——紧张峰值不越过"失控"阈值 |
| 4 | `BALL_MAX_BOUNCE_ANGLE` | 60.0 | **55.0** | 50.0 / 60.0 | 边缘击打的锐利度（影响偏移 → 角度线性映射斜率） | 利落击打感——角度干脆但不刁钻到不可救 |
| 5 | `BALL_SERVE_ANGLE_RANGE` | 45.0 | **30.0** | 25.0 / 35.0 | 发球散布宽度——随机性对开局的主导权 | 可控性优先——发球不靠随机坑人，胜负交给 rally |
| 6 | `PADDLE_SPEED` | 400.0 | **430.0** | 420.0 / 450.0 | 玩家操控响应速度（球速加快后必须跟得上） | 跟手——玩家感到"够得着"，挫败来自判断而非操作延迟 |
| 7 | `AI_REACTION_DELAY_MIN` | 0.1 | **0.15** | 0.12 / 0.2 | AI 反应下限（0.1s ≈ 人类顶尖反应，显作弊） | 挑战但不作弊——快但可被读 |
| 8 | `AI_REACTION_DELAY_MAX` | 0.3 | **0.4** | 0.35 / 0.45 | AI 反应上限 = 玩家喘息窗口 | 给玩家呼吸空间——紧张与放松交替（张力曲线） |
| 9 | `AI_POSITION_ERROR` | 20.0 | **24.0** | 20.0 / 28.0 | AI 失误幅度（可见可预期的犯错空间）；**连带影响**：`paddle.gd` 速度切换阈值 = `error × 2`（40→48px，见 §3.3） | 人可战胜——失误是"人性"，不是 bug |
| 10 | `AI_SPEED_BOOST` | 1.2 | **1.25** | 1.2 / 1.3 | AI 远距离追击速度 | 紧咬比分——压力渐进（隐式难度选择：玩家越快 AI 越咬） |
| 11 | `AI_SPEED_SLOW` | 0.8 | **0.75** | 0.7 / 0.8 | AI 接近目标后的缓速（精准度） | 精准但不机械——到位后不抽搐 |

**20% 红线校验**：单次 rally 速度跳变 = `BALL_SPEED_INCREMENT - 1` = 7% ≤ 20% ✅；`AI_SPEED_BOOST` 1.25（+25%）是 AI 追击速度而非球速，不属红线范围（红线只约束球速曲线）。

### constants.gd 注释格式模板（implement 按此写，每条参数 4 行）

```gdscript
# ── Ball Physics ──
# DRAFT BALL_INITIAL_SPEED = 330.0（草稿值，待用户定稿）
#   该值影响什么: 开局节奏与横穿时间（1280px: 300→4.3s, 330→3.9s）
#   候补值: 320.0 / 340.0
#   情感断言: 利落开局——第一拍就有街机速度感
const BALL_INITIAL_SPEED: float = 330.0
```

---

## 3. 组件修改清单

### 3.1 修改：`mini-pong/gdscripts/constants.gd`（手感参数单一事实源）

- 按 §2 表将 11 个参数的值替换为 DRAFT 草稿值，每条附 4 行注释（`# DRAFT` + 该值影响什么 + 候补值 + 情感断言），注释用中文，格式对齐现有注释风格
- **不改、不标 DRAFT 的常量**（机械部分）：`SCREEN_WIDTH/HEIGHT`、`GAME_VERSION`、`BALL_RADIUS`、`PADDLE_WIDTH/HEIGHT`、`POINTS_TO_WIN_GAME`、`GAMES_TO_WIN_MATCH`、三个 Color
- 保留文件头 `class_name GameConstants` 与 `# ── 分区 ──` 注释结构；`# DRAFT` 只出现在手感参数区

### 3.2 修改：`mini-pong/tests/test_constants.gd`（TC6 字面量同步）

`TC6` 中以下断言的字面量随 §2 草稿值更新（断言名保持 `TC6-N` 编号不变，消息文本更新为新值）：

| 断言 | 现值 | 新草稿值 |
|------|:---:|:---:|
| TC6-4 `BALL_INITIAL_SPEED` | 300.0 | 330.0 |
| TC6-5 `BALL_MAX_SPEED_MULTIPLIER` | 2.0 | 1.9 |
| TC6-6 `BALL_SPEED_INCREMENT` | 1.05 | 1.07 |
| TC6-7 `BALL_MAX_BOUNCE_ANGLE` | 60.0 | 55.0 |
| TC6-8 `BALL_SERVE_ANGLE_RANGE` | 45.0 | 30.0 |
| TC6-10 `PADDLE_SPEED` | 400.0 | 430.0 |
| TC6-13 `AI_REACTION_DELAY_MIN` | 0.1 | 0.15 |
| TC6-14 `AI_REACTION_DELAY_MAX` | 0.3 | 0.4 |
| TC6-15 `AI_POSITION_ERROR` | 20.0 | 24.0 |
| TC6-16 `AI_SPEED_BOOST` | 1.2 | 1.25 |
| TC6-17 `AI_SPEED_SLOW` | 0.8 | 0.75 |

其余断言（SCREEN / COLORS / SCORING / VERSION / RADIUS / PADDLE_W/H）不动。机械部分禁止 `# DRAFT` 注释。

### 3.3 修改：`mini-pong/tests/test_ai_paddle.gd`（**PRD 之外的 gap 发现**）

PRD 只点名 TC-B2/3/4，但全文件扫描发现**更多硬编码断言引用草稿参数**，必须一并更新，否则全红：

**Gap 1 — 速度切换阈值随 `AI_POSITION_ERROR` 漂移**（`paddle.gd:133`：`threshold = ai_position_error * 2.0`）：
- 现值 20 → 阈值 40px；草稿值 24 → 阈值 **48px**
- TC-B2（dist=140 ≥ 阈值 → boost）、TC-B3（dist=20 < 阈值 → slow）语义不变，但期望值公式更新：`430.0 * 1.25 * 0.016`（boost）/ `430.0 * 0.75 * 0.016`（slow）
- **TC-B4（dist==40）语义反转**：40 < 48 → 现在走 slow 分支！必须重写用例（如 dist==48 断言 boost、dist==40 断言 slow），阈值从 `CONSTS.AI_POSITION_ERROR * 2.0` 读取而非硬编码 40
- 建议：TC-B2/3/4 期望值全部改为从 CONSTS 计算（`CONSTS.PADDLE_SPEED * CONSTS.AI_SPEED_BOOST * delta`），消除字面量漂移

**Gap 2 — 区间断言硬编码草稿参数边界**：

| 用例 | 现值断言 | 草稿值后 |
|------|------|------|
| TC-C2 目标 y 范围 | `[480.0, 520.0]`（ball.y 500 ± 20） | `[476.0, 524.0]`（± AI_POSITION_ERROR=24） |
| TC-C3 延迟范围 | `[0.1, 0.3]` | `[0.15, 0.4]`（AI_REACTION_DELAY_MIN/MAX） |
| TC-D1 误差偏移范围 | `[-20.0, 20.0]` | `[-24.0, 24.0]`（± AI_POSITION_ERROR） |

### 3.4 新增：`docs/TASTE.md`（品味档案初版，结构见 §4）

### 3.5 不改的文件（明确排除）

| 文件 | 原因 |
|------|------|
| `mini-pong/gdscripts/ball.gd` / `paddle.gd` | 零代码改动 —— `const`→`@export` 默认值自动跟随 CONSTS（已核实 ball.gd L8-24 / paddle.gd L18-22） |
| `mini-pong/tests/test_ball.gd` | 本地 `const`（300.0 等）是测试夹具构造值，非断言目标 —— 不动 |
| `mini-pong/tests/auto_play_test.gd` | 纯消费者，草稿值变化后自动在新参数下跑 100 局 |
| `mini-pong/tests/run_tests.gd` | 套件入口不变 |
| `e2e_shots.json` | `ai_position_error=200` 仅 E2E 截图 tweak，与草稿值正交 |
| GDD `13-BALL-PHYSICS.md` | 草稿值会变，GDD 不记录过程值；定稿后由 review agent 按需更新 |

---

## 4. docs/TASTE.md 结构（校准接口三件套）

> 初版语义 = **草稿表 + 试玩剧本**（记录 agent 草稿），不是"定稿差异记录"；文件头须注明，避免与 v4 的"定稿差异回写"语义混淆（PRD §5 边界 6）。

```markdown
# TASTE.md — Mini Pong 品味档案（初版：草稿表，待用户定稿）

## 1. 候补值表          ← 三件套①：参数 × 现值 × 草稿值 × 候补值 × 影响 × 情感断言（= 本文档 §2 表）
## 2. 试玩剧本          ← 三件套②：
##    ① 自动对打: godot --path mini-pong/ --headless --script tests/run_tests.gd
##       （Auto-Play 套件 100 局，观察无崩溃/无卡死，逐项打勾）
##    ② 手动一局: godot --path mini-pong/（图形模式）→ SPACE 开始 → 打一局 vs AI
##       → 按体验清单逐项打勾（开局速度感 / 每拍紧迫感 / 反弹可控性 / AI 压迫感 / 失误可见性）
## 3. 情感断言清单       ← 三件套③：每条草稿值的体验引擎词汇（利落击打感 / 逐渐加压的紧张感 / 可控性优先 / 挑战但不作弊…）
## 4. 定稿记录（占位）   ← 用户定稿差异回写处（本次不填）
```

---

## 5. 数据流

**Flow 1 — 正常路径（草稿值生效）**：
1. implement 改 `constants.gd` 11 参数为 §2 草稿值（带 `# DRAFT` 注释）
2. `ball.gd`/`paddle.gd` 的 `const`→`@export` 默认值自动取新值；Main.tscn 无覆盖 → 运行时手感直接变化
3. implement 同步更新 TC6 / TC-B2/3/4 + TC-C2/C3/D1 字面量 → `run_tests.gd` 全绿
4. 新建 `docs/TASTE.md`（§4 结构）→ 校准接口三件套就位
5. review agent 定稿就绪检查（结构完整 + taste 对齐 + 机械无 DRAFT 残留）→ merge → 打 `status/human-review` + assign 用户

**Flow 2 — 用户定稿路径（v4 队列，非本 PR 范围）**：用户打开 Issue → 对照 TASTE.md 候补值表微调 constants.gd → push 定稿 → close → 差异回写 TASTE.md §4。

**Flow 3 — 失败路径（测试红）**：漏改任一字面量（§3.2/§3.3 任一断言）→ 套件红 → implement 回查 §3 清单补齐。

---

## 6. 边界条件与错误处理

| # | 边界/风险 | 缓解 |
|---|-----------|------|
| 1 | **20% 红线**：单次 rally 球速跳变 >20% = 廉价感，违反情感断言 | 草稿 `BALL_SPEED_INCREMENT=1.07`（+7%）远低于红线；review 逐参数校验；任何候补值 >1.20 直接打回 |
| 2 | **测试字面量漏改**（TC6 / TC-B2/3/4 / TC-C2/C3/D1）→ 全红 | 同一次提交内改常量 + 改测试；review 以 AC5 全绿卡口 |
| 3 | **TC-B4 语义反转**（阈值 40→48，dist==40 从 boost 变 slow）| §3.3 Gap 1：重写 TC-B4 断言（dist==48→boost / dist==40→slow），阈值从 CONSTS 计算 |
| 4 | **headless vs 图形**：手动一局需图形环境；headless 只能跑自动对打 | 试玩剧本区分两种模式；headless 步骤不依赖图形输入 |
| 5 | **`test_ball.gd` 夹具误改**：其本地 const 是场景构造值，非断言目标 | §3.5 明确排除；implement 不得触碰 |
| 6 | **E2E autoplay 覆盖**：`e2e_shots.json` 的 `ai_position_error=200` 与草稿值正交 | 不改草稿值迁就 E2E，也不删 E2E tweak |
| 7 | **TASTE.md 初版语义混淆**（草稿表 ≠ 定稿记录）| 文件头注明初版语义；定稿差异回写占位 §4 |
| 8 | **非手感参数误标 DRAFT**（SCREEN / VERSION / RADIUS / SCORING / COLORS）| §3.1 明确排除清单；`grep -c "# DRAFT" constants.gd` 应恰为 11 |
| 9 | **并发 agent 同改 constants.gd** | 本 PR 只动 mini-pong/ + docs/TASTE.md；merge 前 `git pull origin main` 复查 |
| 10 | **机械部分 DRAFT 残留**（AC4）| `grep -rn "# DRAFT" mini-pong/ --include="*.gd" | grep -v constants.gd` 必须为空 |

---

## 7. 集成点

| 集成 | 本组件 | 目标 | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| 手感参数 | `constants.gd` 11 草稿值 | `ball.gd` / `paddle.gd` | `const`→`@export` 默认值（已存在，零代码） | ⬜ 待 implement 填值 |
| 校准接口 | `docs/TASTE.md` | 用户定稿（Assigned to me） | 候补值表 + 试玩剧本 + 情感断言 | ⬜ 待 implement 新建 |
| 机械测试 | TC6 / TC-B2/3/4 / TC-C2/C3/D1 | 草稿值 | 字面量同步/从 CONSTS 计算 | ⬜ 待 implement 更新 |
| 试玩剧本 | 自动对打 | `auto_play_test.gd`（#297） | 复用，零改动 | ✅ 已存在 |
| 视觉基线 | 草稿方向 | #289 霓虹赛博 | 审美坐标注入（暗底 #0a0a12 已落地） | ✅ 已落地 |

---

## 8. 实施阶段

| 阶段 | 优先级 | 内容 | 估算 |
|:-----|:------:|------|:----:|
| Phase 1 | P0 | `constants.gd` 11 草稿值 + 4 行注释（§2 模板） | 0.5 天 |
| Phase 2 | P0 | 测试同步：TC6（§3.2）+ test_ai_paddle TC-B2/3/4 重写 + TC-C2/C3/D1（§3.3） | 0.5 天 |
| Phase 3 | P0 | 新建 `docs/TASTE.md`（§4 三件套） | 0.5 天 |
| Phase 4 | P0 | 验证：`godot --path mini-pong/ --headless --quit` 无脚本错误 + `run_tests.gd` 全绿 + `grep -c "# DRAFT"` == 11 | 0.25 天 |

单次提交完成（PRD §8 下一步 3：constants.gd + 测试同步 + TASTE.md 一次提交）。

---

## 9. 测试用例描述（仅描述，不写代码）

### Scenario A：草稿值落位（test_constants.gd TC6 更新）
- **Test A1**（TC6-4/5/6/7/8）：加载 `constants.gd`，断言 5 个球速/反弹角参数 == §2 草稿值（330.0 / 1.9 / 1.07 / 55.0 / 30.0）。前置：constants.gd 已改。期望：全过。
- **Test A2**（TC6-10）：`PADDLE_SPEED == 430.0`。
- **Test A3**（TC6-13..17）：5 个 AI 参数 == 草稿值（0.15 / 0.4 / 24.0 / 1.25 / 0.75）。
- **Test A4**（TC6-其余）：SCREEN / COLORS / SCORING / VERSION / RADIUS 断言**不变**仍全过 —— 证明机械部分未被动到。

### Scenario B：AI 移动速度随草稿值（test_ai_paddle.gd 更新）
- **Test B1**（TC-B2，dist=140 ≥ 阈值 48）：期望位移 == `CONSTS.PADDLE_SPEED × CONSTS.AI_SPEED_BOOST × delta`（430 × 1.25 × 0.016 = 8.6）。期望值**从 CONSTS 计算**，不硬编码。
- **Test B2**（TC-B3，dist=20 < 阈值 48）：期望位移 == `430 × 0.75 × 0.016 = 5.16`。
- **Test B3**（TC-B4 重写）：dist==48（==阈值）→ boost 分支；dist==40（<阈值）→ slow 分支 —— 覆盖阈值漂移后的边界两侧。
- **Test B4**（TC-C3）：100 次迭代断言 `_ai_delay_timer ∈ [0.15, 0.4]`。
- **Test B5**（TC-D1）：100 次迭代断言误差偏移 ∈ [-24.0, 24.0]。
- **Test B6**（TC-C2）：目标 y 落在 ball.y ± 24 内（476.0–524.0）。

### Scenario C：校准接口三件套（文档检查，review 卡口）
- **Test C1**：`docs/TASTE.md` 存在且含三节（候补值表 / 试玩剧本 / 情感断言）。
- **Test C2**：候补值表覆盖 §2 全部 11 参数，列齐全（参数/现值/草稿/候补/影响/情感断言）。
- **Test C3**：试玩剧本含自动对打命令与手动一局步骤清单，headless/图形模式区分明确。

### Scenario D：机械完整性（AC4/AC5 验证）
- **Test D1**：`grep -c "# DRAFT" mini-pong/gdscripts/constants.gd` == 11；`grep -rn "# DRAFT" mini-pong/ --include="*.gd" | grep -v constants.gd` 为空。
- **Test D2**：`godot --path mini-pong/ --headless --quit` 退出码 0、无 push_error/脚本错误。
- **Test D3**：`godot --path mini-pong/ --headless --script tests/run_tests.gd` 全绿（含更新后的 TC6 / TC-B/C/D 系列 + auto_play_test 100 局无崩溃）。

---

## 10. 验收标准映射（Issue 5 条 AC）

| AC | 本设计对应 | 验证方式 |
|----|-----------|---------|
| AC1 手感参数集中 constants.gd，带 `# DRAFT` + 影响 + 2–3 候补值 | §2 表 + §3.1 注释模板 | `grep -c "# DRAFT"` == 11；抽查 3 条三要素齐全 |
| AC2 每条草稿值附情感断言 | §2 表"情感断言"列 + 注释模板第 4 行 | `grep -c "情感断言"` ≥ 11；TASTE.md §3 齐全 |
| AC3 校准接口三件套（试玩剧本 + 候补值表 + 情感断言）| §4 TASTE.md 结构 | 三节齐全（Test C1–C3） |
| AC4 机械部分无 `# DRAFT` 残留 | §3.2/3.3 测试同步 + §6 边界 10 | Test D1 |
| AC5 `--headless --quit` 无脚本错误 + run_tests.gd 全绿 | §8 Phase 4 | Test D2/D3 |
