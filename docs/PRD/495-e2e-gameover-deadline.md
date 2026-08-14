# PRD: [Fix] e2e 03_gameover deadline 校准 — 根因是升级窗口冻结，非得分慢

> **Issue:** #495
> **标签:** bug, workflow/research, priority/medium
> **Agent:** game-research-agent
> **日期:** 2026-08-15
> **深度:** depth/standard（Issue 无 depth 标签，按 #491/#372 惯例按 standard 处理：Section 1–6 + 8；Section 7 含 3 个已完成实验）
> **所有权:** `content_ownership: mechanical`（harness 行为 = 机械可测；无品味决策）
> **来源:** PR #494 review（game-review-agent, 2026-08-15）。**不 block 该 PR** — 此为 follow-up 跟踪（Class A infra, pre-existing harness flake）。
> **约束:** class A 基建 —— 只改 `framework/templates/`、`mini-pong/e2e_shots.json` 等测试基建文件，**不改游戏代码**（`mini-pong/gdscripts/`、`scenes/`）

---

## 1. 问题定义

### 1.1 当前状态（含预调查 — bug pre-investigation, Patch 10）

**核心发现：Issue 声称「autoplay 下 capture 得分慢，300s 内约 12 分 < WIN_SCORE 21，因此 03_gameover 不可达」是 STALE/错误根因。实测证据链（本 PRD §7 三实验）证明：同配置下 GAME_OVER 本可在 ~14-94s 内到达（headless 与 rendered-with-confirmation 均验证），真实失败机制是「升级窗口冻结」—— 一局中某波砖墙被清空时 `UpgradePickUI.open()` 置 `get_tree().paused = true`，而 capture harness 从不喂 `ui_accept` → 游戏永久停在升级窗口 → GAME_OVER 状态永不可达 → 03_gameover shot 命中 deadline 漏截。**

| # | Issue 声明 | 预调查结果 | 证据 |
|---|-----------|-----------|------|
| 1 | autoplay 配置 (mode=1/1, ai_position_error=200) 下 capture 得分慢，02_midgame 在 frame 1432 ≈ 24s/分 | ⚠️ **部分错误** | capture 实际运行 **~120fps**（诚实 run `elapsed_ms=300001, frame=35959` → 119.9fps），frame 1432 ≈ **11.9s**（非 24s — Issue 按 60fps 估算错 2 倍）。线性外推 12s/分 → 300s 内可达 ~25 分 > 21，**线性得分假设下 deadline 本就够** |
| 2 | 300s 内游戏未到 21 分 → 03_gameover 漏截 | ✅ **确认漏截但机制错误** | 诚实 run（/tmp/wt491b/e2e-494/shots/results.json）：02_rain_light 在 frame 1492 后**再无 shot**，直到 35959（300s）—— 得分**停止**而非变慢（若线性 12s/分，GAME_OVER 应 ~frame 30000 触发） |
| 3 | L2 playthrough 703 frames/16s 到终局 → 可达性无问题 | ✅ **确认** | 本 PRD §7 实验：headless 4 连跑均 GAME_OVER（604-884 frames / 12.8-19.5s，含 21:15/17:21/18:21/21:14）；L2 诚实证据 656 frames/14.4s PASS |
| 4 | 配置 main 与 PR 相同 → pre-existing | ✅ **确认** | PR #494 diff 未改 autoplay 块（只加 2 个 shot + missed 检查） |
| 5 | missed 检查（PR #494 新增）正确判 fail | ✅ **确认** | 诚实 run L3=fail；runner 已含 stale-PNG 清理 + missed 检查（#494） |
| 6 | 校准方案 a: ai_position_error 200→400 加速得分 | ❌ **不能根治** | 加速得分不解决冻结：墙清空发生在「21 分前」与否是 RNG 赛跑，加速只是提高胜率，不消除冻结窗口；且风险 02_rain_heavy 门（Issue 自述） |
| 7 | 校准方案 b: deadline_s 300→600 | ❌ **完全无效** | 冻结 = 游戏暂停（paused=true），非慢速。延长 deadline 只是对着冻结画面空等。**§7 实验 2 直接证明** |

**根因链（代码级，已核实）：**

```
BreakoutGrid.wall_cleared（某波砖墙全部击碎，RNG 决定何时发生）
    │
    ▼
WaveController._on_wall_cleared()  [wave_controller.gd:35-50]
    │  GameManager.settle_wave() → 发 wave_settled 信号
    ▼
UpgradePickUI.open()  [upgrade_pick_ui.gd:52-70]
    │  get_tree().paused = true（AC4 树级暂停等待玩家选择）
    │  _set_settle_hold(true)（WaveController 停止自动推进）
    ▼
e2e_capture.gd 主循环  [framework/templates/e2e_capture.gd:109-147]
    │  只对带 "press" 字段的 shot 注入按键（仅 02_midgame 有）
    │  从不检测 UpgradePickUI.visible → 永不喂 ui_accept
    ▼
游戏永久暂停 → FSM 停在 PLAYING → GAME_OVER 永不进入
    ▼
03_gameover shot 300s deadline 到期 → missed（诚实报 fail）
```

**为什么是间歇性（Spike 2 run1/run2 全捕获、run3 漏截）：** 墙清空与 21 分是**赛跑**——球路/穿墙分 (+3) 是 RNG，取决于哪件事先发生。若 21 分先到（墙未清空，无升级窗口）→ GAME_OVER 可达 → 03_gameover 捕获成功；若某波墙先被清空（升级窗口打开 → 冻结）→ 必漏截。真实概率 ~1/3（run3 + review 重跑连续 2 次 miss）。

### 1.2 预期行为（验收条件，源自 Issue #495）

1. **03_gameover 在本地 e2e 中 3/3 次可靠捕获**（或按本 PRD §4 方案 A 校准路径调整 — **不得删除门**）
2. **校准方案**：capture harness 在升级窗口可见时自动喂 `ui_accept`（镜像 L2 playthrough_driver.gd 既有行为），使游戏能打完升级窗口 → 继续推进 → GAME_OVER 自然到达
3. **pipeline 测试覆盖**：`test_e2e_runner.py` 用例保持绿
4. **L0/L1/L2 + pipeline 全绿**
5. **02_rain_heavy（current_rain≥0.55）与 02_rain_light 两档差异断言不受影响**

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 墙未清空先到 21 分 | ~2/3 | 现有行为：GAME_OVER 可达，03_gameover 正常捕获（Spike 2 run1/run2） |
| B | 某波墙先清空（升级窗口冻结） | ~1/3 | 现有行为：游戏永久暂停 → 03_gameover 漏截 → L3 fail（run3 + review 重跑） |
| C | 修复后任意一局 | 期望 3/3 | 升级窗口自动确认 → 游戏打完 → GAME_OVER 可达 → 03_gameover 稳定捕获 |

### 1.4 技术约束（继承自 Issue #495 + #372 + #491 + #388）

| 约束 | 细节 |
|------|------|
| 引擎/目录 | Godot 4.7.1，本项目 = `mini-pong/`；`gdscripts/` 为游戏代码（**红线：不改**） |
| 基建范围 | `framework/templates/e2e_capture.gd`（共享模板）、`mini-pong/e2e_shots.json`（项目配置）、`scripts/e2e/resolve_plan.py`（若需透传新字段） |
| 升级窗口机制 | `UpgradePickUI`（CanvasLayer, PROCESS_MODE_ALWAYS）在 `wave_settled` 时 `open()` → `paused=true` + `settle_hold=true`；`ui_accept` 确认（SELECTING→REVEALING→CLOSED），REVEALING 输入锁定（#388 设计） |
| L2 先例 | `playthrough_driver.gd:57-59` 已实现「升级窗口可见 → 喂 ui_accept」—— capture 模板应镜像该行为 |
| 复用 | `_inject_press`/`_emit_key`/`Input.action_press` 既有注入设施可直接复用 |
| 兼容 | 新行为必须**配置驱动**（shot plan 显式开启），缺省时行为与现状逐字节一致（模板级兼容，防其他项目回归） |
| 测试即验收 | pipeline 走 `tests/pipeline/test_e2e_runner.py`（fake godot 不执行 capture 逻辑 → 模板改动不破坏既有用例）；真实验证走本地 run-e2e-review.sh |

### 1.5 范围界定（与既有 PRD 去冲突 — Patch 14）

| 既有 PRD | 覆盖范围 | 本 PRD 不重复覆盖 |
|---------|---------|-----------------|
| #372 e2e harness fixes | per-shot deadline 机制（`deadline_s` 引入）、P6 gist 上传、frozen 阈值 | ❌ 不改 deadline 语义；本 PRD 解决「deadline 内状态不可达」的冻结根因 |
| #466/#480/#485 visual regression | 区域/阈值断言、runner 锁、bg 采样 | ❌ 不碰 analyze_bmp.py / runner 锁；本 PRD 只补 capture 驱动能力 |
| #491 rain score levels | 雨量分数档位因子 + e2e_shots 加 02_rain_light/02_rain_heavy | ❌ 不改雨量公式与档位门；本 PRD 让 03_gameover 与既有 5-shot 组都能稳定跑完 |
| #494（OPEN，父 PR） | #491 实现 + missed 检查 + stale-PNG 清理 | ❌ 不触碰 PR #494 代码；本 PRD 是它的 follow-up 基建修复 |

---

## 2. 设计意图

### 2.1 为什么当前行为存在

| Issue/PR | 引入 | 后果 |
|---------|------|------|
| #358 E2E canary | capture 驱动只读节点属性、注入 press 开赛 | 「press 驱动状态」的设计只覆盖 MENU→PLAYING（02_midgame），未覆盖波间升级窗口 |
| #372 per-shot deadline | 03_gameover 单独 300s deadline（5 分制不够 → 延长） | 隐含假设「延长 deadline = 更可达」，但若状态机冻结，deadline 再长也无效 |
| #386/#388 波次循环 + 升级 UI | `wave_settled → UpgradePickUI.open() → paused=true` 等待玩家 | 玩家游戏中由人确认；capture 无人确认 → 永久冻结 |
| #394 E2E playthrough（L2） | `playthrough_driver.gd` 显式处理升级窗口（`ui.visible → _feed_accept()`） | **L2 不受冻结影响**（14.4s 到终局）；L3 capture 缺同一能力 → 暴露差异 |

### 2.2 为什么现在改

1. **PR #494 的 missed 检查把 flake 变成诚实失败**（此前 stale PNG 假绿掩盖）— 基建现在能如实暴露问题，是修复的前提（#494 已合入该检查）
2. **根因已定位**（本 PRD §7 三实验，非猜测）：冻结机制明确，修复面小（capture 模板 + 配置各 1 处）
3. **Issue 两个候选方案均被证伪**（§1.1 表 #6/#7）— 需要正确的第三个方案，避免 implement agent 落地无效修复
4. 03_gameover 是 L3 视觉验证的**终局证据 shot**（GameOver 画面 = 完整游戏闭环的视觉证明），不可删除（Issue 明确「不得删除门」）

### 2.3 既有约束（不变项）

| 约束 | 详情 |
|------|------|
| 游戏代码零改动 | 只改 `framework/templates/` + `mini-pong/e2e_shots.json`（class A 基建红线，同 #372） |
| deadline 语义不变 | 300s 保留（修复后实测 ~94s 到终局，300s 是安全余量）；不改成 600s |
| missed 检查保留 | 诚实报 fail 机制是防假绿的生命线（#494） |
| 模板向后兼容 | 新自动确认行为由 shot plan 字段显式开启；缺省 = 现状逐字节一致 |
| 雨量档位断言不受影响 | 02_rain_heavy/02_rain_light 在 GAME_OVER 之前早已捕获（诚实 run: frame 257/1492 vs 03_gameover 冻结前）—— 修复只影响 03_gameover 之后的推进 |

---

## 3. 影响分析

### 3.1 直接影响的文件

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `framework/templates/e2e_capture.gd` | capture 驱动模板 | **修改** — 新增配置驱动的「升级窗口自动确认」：每帧检测 plan 指定的确认节点 visible → 注入 `ui_accept`（复用 `_inject_press` 设施） |
| `mini-pong/e2e_shots.json` | shot plan（项目配置） | **修改** — autoplay 块加自动确认配置（如 `"confirm_upgrade": {"node": "/root/Game/UpgradePickUI", "action": "ui_accept"}`） |

### 3.2 新建文件

| 文件 | 用途 |
|------|------|
| 无 | 全部改动落在既有文件（模板 + 配置） |

### 3.3 间接受影响的文件

| 文件 | 影响 |
|------|------|
| `scripts/e2e/resolve_plan.py` | **只读确认**：`autoplay` 块已在透传白名单（第 24 行 `"states", "theme_color", "autoplay"`）— 新字段随 autoplay 自动透传，**大概率无需改动**（implement agent 验证即可） |
| `tests/pipeline/test_e2e_runner.py` | **无需改动**（fake godot 只写 PNG，不执行 capture 逻辑；既有 8 用例继续绿）— 可选：加 1 个「plan 含 confirm_upgrade 字段时透传」断言（若 resolve_plan 需动） |
| `mini-pong/tests/playthrough_driver.gd` | **不改**（已实现同样的自动确认，作为参照先例） |
| `docs/DESIGN/466-visual-regression-e2e.md` | 校准记录（可选，按 #466 惯例回填实测值） |

### 3.4 数据流影响

```
e2e_shots.json autoplay.confirm_upgrade
    │  resolve_plan.py 透传（白名单已含 autoplay）
    ▼
e2e_capture.gd 主循环（每帧，新增 1 个检查）
    ├── 检查 confirm_upgrade 节点（UpgradePickUI）
    │     └── visible == true？
    │           ├── 是 → 注入 ui_accept（Input.action_press，复用 _inject_press）
    │           │        └── UpgradePickUI SELECTING→REVEALING（0.8s reveal）→ CLOSED
    │           │              └── get_tree().paused = false + advance_settlement()
    │           │                    └── WaveController 推进下一波 → 游戏继续
    │           └── 否 → 无操作（现状行为）
    ▼
游戏推进 → FSM 到达 GAME_OVER → 03_gameover shot ready → 捕获 PNG
```

**REVEALING 输入锁定（#388 设计）保证幂等**：升级窗口打开期间每帧喂 `ui_accept` 只生效一次（SELECTING 态），REVEALING/CLOSED 态忽略 → 不会重复确认/跳过。

### 3.5 需更新的文档

- [x] `docs/PRD/495-e2e-gameover-deadline.md`（本 PRD）
- [ ] `docs/DESIGN/394-e2e-playability.md` L3 层一行（可选，描述 capture 升级窗口自动确认）
- [ ] `docs/PROJECT.md` known-issue 段（#495 解决后移除）

---

## 4. 方案对比

### 方案 A：capture harness 升级窗口自动确认（推荐，已实证）

**描述：** `e2e_capture.gd` 主循环每帧检测 plan 配置的确认节点（`autoplay.confirm_upgrade`），visible 时注入 `ui_accept`。镜像 `playthrough_driver.gd:57-59` 的 L2 既有行为。shot plan 显式开启，缺省兼容。

**实测（§7 实验 3）：** rendered 120fps 下 GAME_OVER 于 **93.7s（21:7）** 到达，升级窗口自动确认 1 次（93 帧可见 ≈ reveal 时长），远小于 300s deadline → **3/3 可靠性可达成**。

| 维度 | 评估 |
|------|------|
| Pros | 根治冻结（游戏不再永久暂停）；镜像 L2 已验证行为（无新机制发明）；改动小（模板 1 处 + 配置 1 处）；配置驱动向后兼容；不动 deadline/不动 autoplay 参数 → 02_rain_heavy 门零风险 |
| Cons | 模板行为增加一个「每帧 visible 检查」（开销可忽略）；需要 implement agent 验证 resolve_plan 透传 |
| Risk | **Low** — 行为已实证；REVEALING 输入锁定保证幂等；缺省兼容防回归 |
| Effort | 0.5-1 天 |

### 方案 B：deadline_s 300→600（Issue 候选 b — 拒绝）

**描述：** 延长 03_gameover 的 deadline。

**实测否决（§7 实验 2）：** 冻结时 `paused=true`，游戏已暂停 —— **任何 deadline 长度都等不到 GAME_OVER**。延长只增加无效等待时间（300s→600s 每次 e2e 翻倍），且间歇性 flake 概率不变（~1/3 冻结）。

| 维度 | 评估 |
|------|------|
| Pros | 改动一行 |
| Cons | **不解决根因**（冻结 ≠ 慢速）；单次 e2e 时长翻倍；flake 仍间歇性出现 |
| Risk | **High**（无效修复，验收 3/3 必失败） |
| Effort | <0.1 天 |

### 方案 C：autoplay ai_position_error 200→400（Issue 候选 a — 拒绝）

**描述：** 增大 AI 位置误差 → AI 更菜 → 玩家得分更快 → 21 分更可能先于墙清空到达。

**否决理由：**
1. **不消除冻结**：仍是赛跑，只是改变概率。墙清空先发生的那 ~1/3 局照样冻结漏截
2. **02_rain_heavy 门风险**（Issue 自述）：`current_rain≥0.55` 依赖速度/波次/档位因子；得分过快可能关闭紧张因子（`|p-a|≤2`），或让档位爬升过快改变雨量曲线 —— 破坏 #491 的两档差异断言
3. **改变被测对象**：autoplay 参数是游戏的「测试环境」，调参治标不治本，掩盖 harness 缺陷

| 维度 | 评估 |
|------|------|
| Pros | 可能提高非冻结局占比 |
| Cons | 不根治；改变测试环境语义；雨量门回归风险；无法验收 3/3 |
| Risk | **Med-High** |
| Effort | 0.1-0.3 天 |

### 方案 D：组合（A + 保守 deadline 微调）— 不推荐单独使用

方案 A 已实证 94s << 300s，deadline 无需动。若 implement agent 想加保险可把 03_gameover 的 `settle_frames` 提高（与 deadline 无关），但**不需要**。**结论：只做 A。**

### 推荐

**方案 A**，理由：
1. **根治**：冻结机制消除，GAME_OVER 确定性可达（实测 93.7s）
2. **零新机制**：镜像 L2 playthrough_driver.gd 已验证 3 个月的既有行为
3. **零游戏代码改动**：符合 class A 基建红线
4. **配置驱动向后兼容**：其他项目（模板消费者）不受影响
5. **验收可达成**：3/3 捕获（修复后实测一局 94s < 300s，余量 3x）

---

## 5. 边界条件与验收标准

### 5.1 正常路径（AC 检查表，映射 Issue 完成定义）

- [ ] **AC1: 03_gameover 本地 e2e 3/3 可靠捕获** — 本地跑 run-e2e-review.sh（或直接 capture）3 次，03_gameover 全捕获（不得删除门）
  - 验证：3 次 results.json missed 均为空；P5-visual.log 显示 `saved ...03_gameover.png`
- [ ] **AC2: 升级窗口自动确认生效** — capture 日志/轨迹显示升级窗口出现后被确认（paused 恢复、波次推进）
  - 验证：`trajectory.txt` 或 probe 输出显示 wave 推进不冻结；或跑修复后 capture 观察 GAME_OVER 在 <120s 内到达
- [ ] **AC3: test_e2e_runner.py 保持绿** — `python3 -m unittest discover -s tests/pipeline` 全绿（8 用例）
- [ ] **AC4: L0/L1/L2 + pipeline 全绿** — check_compile.gd / run_tests.gd / playthrough_test.tscn / pipeline 全通过
- [ ] **AC5: 02_rain_heavy 与 02_rain_light 差异断言不受影响** — 5-shot 组全捕获（含两档 rain shot），Δluma 差异断言 pass

### 5.2 边界情况

1. **升级窗口在 03_gameover 捕获后才打开**（21 分后无新窗口 — `open()` 有 `is_run_over()` 守卫）→ 自动确认不影响终局
2. **REVEALING 期间继续喂 ui_accept** → 输入锁定（#388 设计）→ 幂等，无重复确认
3. **confirm_upgrade 节点路径不存在**（其他项目模板消费者未配置）→ 缺省关闭，行为与现状一致
4. **窗口打开瞬间游戏已 run_over**（21 分与墙清空同帧竞态）→ `open()` 的 `is_run_over()` 守卫跳过 → 无冻结
5. **多窗口连开**（波次连续推进）→ 每帧检测 + 注入天然处理（每窗口确认一次）
6. **升级候选不足 3 张** → `open()` 失败路径 1 静默跳过，不暂停 → 自动确认无操作（现状一致）
7. **headless 模式跑 capture**（理论场景）→ paused 语义不变，注入照常工作（与 L2 同）

### 5.3 失败路径

1. **confirm_upgrade 字段解析失败 / 配置错误** → 模板缺省关闭 + `printerr` 告警（不崩）；验收时 L3 明确 fail（诚实暴露配置错误）
2. **自动确认后游戏仍未达 GAME_OVER**（极端 RNG：21 分前多波墙清空拖时）→ 300s deadline 兜底 → missed 诚实报 fail（门不删除，机制兜底不变）
3. **resolve_plan 未透传新字段**（implement agent 未验证）→ capture 收不到配置 → 行为回退现状 → 03_gameover 仍 flake → pipeline 测试/本地 e2e 暴露，回修 resolve_plan 白名单

---

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 |
|------|------|------|
| PR #494（impl/491-rain-score-levels） | OPEN（review APPROVED, 待 merge） | **低** — 本 PRD 修复独立于 #494 代码；但 #494 的 missed 检查/残留清理是本修复的「诚实暴露」前提。建议 #494 先 merge，或并行无冲突（改动文件不重叠：本 PRD 改 capture 模板 + e2e_shots.json autoplay 块；#494 改 e2e_shots.json shots 组 + runner） |
| #388 UpgradePickUI 三态机 | ✅ merged（main） | 低 — REVEALING 输入锁定是本方案幂等的依据 |
| #372 per-shot deadline | ✅ merged（main） | 低 — deadline 机制保留，不修改 |

### 6.2 依赖链

```
#386 波次循环 (main) → #388 升级 UI (main) → #394 L2 playthrough (main)
                                          ↓ 先例：playthrough_driver.gd 自动确认
#491 雨量档位 → PR #494 (OPEN, missed 检查暴露 flake) → #495 本修复 (capture 自动确认)
```

### 6.3 准备工作

- [ ] 确认 PR #494 merge 状态（避免 e2e_shots.json 行冲突；冲突时以 merge 后为准 rebase）
- [ ] 本地准备 run-e2e-review.sh 跑 3 次的耗时预算（每次含 300s deadline 上限 ≈ 5min+ → 3 次 ≈ 15-20min）

---

## 7. Spike / 实验（3 个已完成 — 本次研究的实证基础）

> Issue 无 depth 标签，按 standard 处理（Section 7 可选）。因根因存在真实不确定性（Issue 自身根因分析错误），本 PRD 已先完成 3 个决定性实验，直接作为方案选择的证据。

### 实验 1：headless 可达性 — 同配置下 GAME_OVER 是否可达？

- **问题**：Issue 声称「capture 得分慢 → 300s 不可达」。同 autoplay 配置（mode=1/1, ai_position_error=200）下，游戏到底能不能到 21 分？
- **方法**：`probe_495_capture_eq.gd`（headless, 镜像 capture tweaks + 单次 enter 开局, 60s 上限），连跑 4 次
- **结果**：
  ```
  GAME_OVER frame=681 elapsed=15294ms player=21 ai=15 upgrade_seen=false
  GAME_OVER frame=701 elapsed=15116ms player=17 ai=21 upgrade_seen=false
  GAME_OVER frame=884 elapsed=19526ms player=18 ai=21 upgrade_seen=false
  GAME_OVER frame=604 elapsed=12787ms player=21 ai=14 upgrade_seen=false
  ```
  4/4 均在 12.8-19.5s 到达 GAME_OVER（21:15/17:21/18:21/21:14）。**可达性无问题，Issue「得分慢不可达」假设被否。**
- **影响**：根因不在得分速率；转向「为什么 capture 环境不同」→ 实验 2

### 实验 2：rendered capture 冻结复现 — 升级窗口是否冻结游戏？

- **问题**：capture（rendered, 120fps, 不喂升级确认）到底发生了什么？
- **方法**：`probe_495_freeze.gd`（rendered 720x1280, 镜像 capture tweaks + 检测 UpgradePickUI.visible + paused, 120s 上限）
- **结果**：
  ```
  PROBE: t=87s frame=10500 state=2 paused=false score=14:8 ui_vis=false
  PROBE: FREEZE@frame=10507 t=87698ms state=2 score=14:8 upgrade_visible=true
  ```
  游戏在 t=87s、score 14:8 时**升级窗口打开 → paused=true → 永久冻结**，GAME_OVER 永不可达。
- **影响**：**根因确认** — 升级窗口冻结，非得分慢。Issue 方案 b（延长 deadline）对冻结无效 → 被否。

### 实验 3：修复验证 — 喂 ui_accept 后是否解除冻结？

- **问题**：capture 在升级窗口可见时喂 `ui_accept`（镜像 L2），游戏能否打完到 GAME_OVER？
- **方法**：`probe_495_fix.gd`（rendered 720x1280, capture tweaks + 每帧检测 UpgradePickUI.visible → 注入 ui_accept, 120s 上限）
- **结果**：
  ```
  PROBE: confirmed upgrade #93 at t=87568ms score=20:5
  PROBE: GAME_OVER frame=11231 elapsed=93743ms score=21:7 upgrades=93
  ```
  升级窗口确认 1 次后游戏继续推进，**GAME_OVER 于 93.7s（21:7）到达**，远小于 300s deadline。
- **影响**：**方案 A 实证有效** — 自动确认解除冻结，3/3 可靠性可达成。deadline 无需改动。

---

## 8. 延续上下文（handoff 给 plan agent）

### 系统状态

- **游戏代码零改动**（红线）。全部改动落在 `framework/templates/e2e_capture.gd` + `mini-pong/e2e_shots.json`
- **根因（已实证）**：升级窗口冻结 —— `UpgradePickUI.open()` 置 `get_tree().paused=true` 等待 ui_accept；capture 从不喂 → 游戏永久暂停 → GAME_OVER 不可达 → 03_gameover 漏截。间歇性（~1/3）因「墙清空 vs 21 分」赛跑是 RNG
- **Issue 两个候选方案被证伪**：deadline 300→600 对冻结无效（实验 2）；ai_position_error 200→400 不根治且有雨量门风险
- **方案 A 已实证**（实验 3）：升级窗口自动确认 → GAME_OVER 93.7s 到达
- **PR #494 状态**：OPEN（review APPROVED，待 operator merge）。本 PRD 与其改动不重叠；implement 前确认其 merge 状态以避免 e2e_shots.json 行冲突

### 主要风险

| 风险 | 缓解 |
|------|------|
| resolve_plan.py 未透传 autoplay.confirm_upgrade | 白名单第 24 行已含 `"autoplay"` → 大概率自动透传；implement 验证（§5.3 失败路径 3） |
| 模板行为影响其他项目 | 配置驱动缺省关闭 + 兼容说明（§5.2 边界 3） |
| 03_gameover 仍 flake（极端 RNG） | 300s deadline 兜底 + missed 诚实报 fail（门不删除，§5.3 失败路径 2） |

### 下一步（plan agent）

1. 读 `framework/templates/e2e_capture.gd:109-147`（主循环）+ `mini-pong/tests/playthrough_driver.gd:30-59`（L2 自动确认先例）—— 方案 A 的落点与参照
2. 在 capture 主循环加「每帧检查 plan.autoplay.confirm_upgrade → 节点 visible → 注入 ui_accept」（复用 `_inject_press`/`Input.action_press`）
3. `mini-pong/e2e_shots.json` autoplay 块加 `"confirm_upgrade": {"node": "/root/Game/UpgradePickUI", "action": "ui_accept"}`
4. 验证 resolve_plan.py 透传（跑一次 resolve 看 plan.json 是否含新字段）
5. 本地跑 run-e2e-review.sh 3 次验证 AC1（3/3 全捕获）；pipeline + L0/L1/L2 全绿（AC3/AC4）
6. 可选：回填 docs/DESIGN/394 与 PROJECT.md（§3.5）
