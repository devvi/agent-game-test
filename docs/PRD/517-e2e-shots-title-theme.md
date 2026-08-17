# PRD: [Follow-up] e2e_shots.json 01_title 断言过时 — 世界隐藏后无 theme 色

> **Issue:** #517
> **标签:** bug, workflow/available → workflow/research（available-rescan 分配）
> **Agent:** game-research-agent
> **日期:** 2026-08-17
> **深度:** light（Issue body「工作深度: light」；depth/light 标签：Section 1–5 + 8 必填；6/7 跳过并注明）
> **所有权:** `content_ownership: mechanical`（测试 fixture 断言维护 = 机械可测，无品味决策）
> **来源:** available-rescan（workflow/available → workflow/research）
> **前置依赖:** #508（PR #511 已 merge — MENU 隐藏游戏世界的行为变更）、#358（e2e_shots.json 引入全局 theme_color）、#466/#476（L3 断言体系）
> **参考先例:** `docs/PRD/508-title-screen-world-bleed.md`（同 class：bug + light + mechanical）、`docs/PRD/500-harness-capture-src-fix.md`（runner 修复结构）

---

## 1. 问题定义

### 1.1 当前状态

**核心发现：L3 视觉层把顶层 `theme_color: "4a90d9"` 应用到**每一个 **shot（`run-e2e-review.sh:253-257` 单值 THEME → 逐 PNG 传 `--theme`）。#508 修复（commit `34fdf21`，PR #511）后 MENU 状态通过 `game_world` 组隐藏整个游戏世界 → `01_title`（MENU）截帧中 theme 像素 = 0 → `analyze_bmp.py` 报 `theme #4a90d9 NOT found` → **L3 伪失败**（修复本身生效，断言过时）。**

| 事实 | 证据 |
|------|------|
| theme_color 是顶层全局键，无 shot 级覆盖机制 | `mini-pong/e2e_shots.json:9`；`resolve_plan.py:24` 仅透传顶层；`run-e2e-review.sh:253-257` 单值 THEME 应用于所有 PNG |
| #508 修复后 MENU 隐藏 game_world 组（含 BgPulse + RainCurtain + 球 + 双拍） | `Main.tscn:33,57,60,63,67` 组归属；`game_state_machine.gd:_set_world_visible()`（commit `34fdf21`）；`test_world_visibility.gd`（275 行新测试） |
| #4a90d9 的两个来源都在 game_world 组内 | `constants.gd:100` PLAYER_NEON_BLUE（玩家板）、`constants.gd:208` BG_PULSE_TINT（BgPulse 呼吸层，AtmosphereLayer 下） |
| 01_title 实测 0 个 theme 像素（PR 分支）vs main 1328 个 | Issue body（#511 实证）：修复生效 = 0 像素；原 bug = 1328 像素 |
| StartMenu UI 无 #4a90d9 系色 | `start_menu.gd` / Main.tscn StartMenu 段 grep 无 PLAYER_NEON_BLUE 引用（标题/提示/版本号为 neon 青/白系，距离 #4a90d9 超容差 32） |

#### 预调查结果（bug pre-investigation，Patch 8/10 — issue body 已含根因，逐条验证源码）

| # | Issue 声明 | 状态 | 证据 |
|---|-----------|------|------|
| 1 | `01_title` 仍断言 theme 色存在（#358 引入的全局 `theme_color`） | ✅ **确认（未修复）** | `e2e_shots.json:9` 顶层键；`run-e2e-review.sh:253-257` 无 shot 级分支，全部 PNG 都带 `--theme 4a90d9` |
| 2 | #508 修复后 title 画面无 theme 像素 | ✅ **确认** | `game_world` 组含 AtmosphereLayer（BgPulse/RainCurtain 全隐藏）+ 球拍；两处 #4a90d9 常量（`constants.gd:100,208`）均在组内节点上 |
| 3 | main 上 1328 个 theme 像素 = 原 bug 画面 | ✅ **确认（历史态）** | 修复前 MENU 世界可见，BgPulse 全屏脉冲 + 玩家板均染 #4a90d9 |
| 4 | 02_midgame / 03_gameover 不受影响 | ✅ **确认** | PLAYING/GAME_OVER 状态不隐藏世界（`enter_state` 仅 MENU 调 `_set_world_visible(false)`；MENU 退出恢复 true） |

**无 stale claims** — issue 为 #511 follow-up，描述与当前源码一致；「反向断言」与「shot 级覆盖」两个候选方案均需小规模 runner/analyzer 改动（见 §4）。

### 1.2 Obsidian 知识库搜索结果

| 检索范围 | 命中文档 | 结论 |
|---------|---------|------|
| `/Volumes/Obsidian/Knowledge Ocean/wiki/`（WebDAV 已挂载，2026-08-17 实时搜索）grep：e2e / 视觉回归 / 截图 / 断言 / theme_color / 4a90d9 / visual | 仅泛义命中：「Claude Fable 5与Mythos 5」（AI 模型评测）、「技术道德中立论」（哲学）、「体验引擎-glossary」（游戏设计术语）、「九十年代素材与文化参考」（文化素材） | 均非本项目测试基建笔记，无断言/截帧设计约束 |
| 同上 grep：title / pong / 网球 | 「赛博增殖：网球与绒毛」（2026-06 AI 开发网球游戏事件记录）、「原始材料-开发笔记」（剪藏笔记） | 无 E2E 断言或 title 屏测试设计 |

**结论：Obsidian 知识库无本项目 E2E 断言体系设计笔记，知识搜索无新增约束。** 降级说明：设计意图以仓库内 `docs/PLAN-e2e-verification-v2.md`（L0-L3 模型）、PRD #466/#476（L3 断言体系）、PRD #508（世界隐藏行为）为准，见第 2 节。

### 1.3 预期行为（验收条件，源自 Issue #517）

1. [ ] **AC1** L3 视觉层全绿：`01_title` 通过非黑/颜色数/帧差/assert_text + **世界隐藏断言**（theme 容差像素 ≈ 0 反向断言，或 shot 级 theme_color 覆盖）
2. [ ] **AC2** `02_midgame` / `03_gameover` 不受影响：世界保持可见，theme 正断言（如保留）继续生效
3. [ ] **AC3** 用 `scripts/run-e2e-review.sh --with-visual` 显式重跑至 L3 全绿验证
4. [ ] **AC4** 既有 pipeline 单测（test_e2e_analyze / test_e2e_runner / test_e2e_resolve）不回归

### 1.4 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| 1 | 任意 impl PR 带 `--with-visual` 跑 L3 | 每次视觉相关 PR | 01_title 恒红 → review agent 手动豁免或误判回归，消耗人力 |
| 2 | 未来 MENU 相关改动（如 title 屏重设计） | 偶发 | 同样的「世界隐藏」行为变化会再次触发同一伪失败 |
| 3 | 世界隐藏逻辑回归（世界在 MENU 重现） | 罕见 | 若无世界隐藏断言，此回归不会被 L3 捕获（当前 theme 断言恰好能抓到，但以伪失败方式） |

## 2. 设计意图

### 2.1 为什么当前状态存在

| 贡献者 | 决策 | 后果 |
|--------|------|------|
| #358（PR #361/#377） | 引入全局 `theme_color`，对所有 shot 断言主题色存在 | 当时 title 画面世界可见，theme 断言语义成立；「每 shot 都验」的简化设计 |
| #466 / #476 | L3 四断言模型（非黑/色数/theme/帧差），theme 用容差 32 采样验证 | #466 已记录 post-#464 后 theme 断言「元素存在」语义弱化（板=#00e5ff、砖=#ff9d45），但未移除——保留仍能验「世界在渲染」 |
| #508（PR #511） | MENU 状态 `_set_world_visible(false)` 隐藏 game_world 组 | 行为正确变更，但 fixture 未同步：01_title 世界隐藏后 theme 断言失去判定对象 → 伪失败 |

### 2.2 为什么现在改

- #517 为 #511 的 follow-up，明确报告 L3 伪失败（实测 0 vs 1328 px），light 深度
- L3 伪失败阻塞后续所有视觉 impl PR 的合入（run-e2e-review.sh 是 impl 阶段强制验证）
- 断言过时 = 测试资产债务：不改则每次跑都红，review 逐渐习惯性豁免 → 断言失效

### 2.3 既有约束

| 约束 | 细节 |
|------|------|
| 断言模型固定 | `analyze_bmp.py` 4 断言均为 flag-gated，纯 stdlib，CI（ubuntu）+ Mac 双跑；新增 flag 需保持纯 stdlib |
| theme 采样语义 | `_theme_present()` 按 stride 5 采样、容差 32/通道；反向断言应复用同一采样逻辑（对称性） |
| runner 单值 THEME | `run-e2e-review.sh:253` 只读 plan.json 顶层 `theme_color`；shot 级配置需新增读取（PNG 文件名 = shot name，`e2e_capture.gd` `_capture(shot_name)`） |
| resolve 透传 | `resolve_plan.py` 的 shots 原样透传 → shot 级字段天然可达 runner，无需改 resolve（仅改消费端） |
| 模板同构 | `framework/templates/e2e_shots.json` 同构（顶层 theme_color）；本 issue 只要求 mini-pong 副本，模板可选同步 |
| capture 不用 theme | `e2e_capture.gd` 不消费 theme_color（仅 runner/analyze 用）→ 改动不触及 capture |

## 3. 影响分析

### 3.1 直接受影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `mini-pong/e2e_shots.json` | shot 计划 fixture | 01_title 增加世界隐藏断言配置（shot 级） |
| `scripts/run-e2e-review.sh` | L3 视觉层 | THEME 取值从「顶层单值」改为「shot 级优先 + 顶层回退」；支持反向断言 flag 透传 |
| `scripts/e2e/analyze_bmp.py` | 视觉断言 | （方案 B）新增 `--theme-absent` 反向断言 flag |
| `tests/pipeline/test_e2e_analyze.py` | 单测 | （方案 B）反向断言正/反用例 |
| `tests/pipeline/test_e2e_runner.py` | 单测 | shot 级 theme 配置解析用例（fake godot 像素生成逻辑同步） |

### 3.2 新增文件

无（light 深度；不新增脚本，只在既有文件内扩展）。

### 3.3 间接影响

| 文件 | 影响 |
|------|------|
| `framework/templates/e2e_shots.json` | 可选：模板保持同构（不强制，避免扩大 PR 面；记录为后续一致性事项） |
| `docs/PLAN-e2e-verification-v2.md` | 可选：L3 断言描述补充反向断言能力（文档级，非阻塞） |
| 其他 game 子项目（若有 e2e_shots.json） | 无：改动限定 mini-pong 副本 + runner 通用逻辑（向后兼容：shot 无字段时回退全局行为） |

### 3.4 数据流影响

```
mini-pong/e2e_shots.json (shot 级 theme 配置)
    │
    ▼
resolve_plan.py (shots 原样透传, 顶层 theme_color 透传)
    │  plan.json
    ▼
run-e2e-review.sh L3 (逐 PNG: 读 shot 配置 → 决定 --theme / --theme-absent / 无)
    │
    ▼
analyze_bmp.py (flag-gated 断言)
    ├── 非黑 / 色数 / 帧差  ← 全 shot 不变
    ├── --theme 4a90d9      ← 02_midgame / 03_gameover（世界可见, 正断言）
    └── --theme-absent 4a90d9 ← 01_title（世界隐藏, 反向断言）
```

### 3.5 需更新文档

- [ ] （可选）`docs/PLAN-e2e-verification-v2.md` — L3 断言清单补充反向断言
- [x] 本 PRD 即 research 交付物（无其他强制文档）

## 4. 方案对比

> 本 issue 为 **test-fixture-only 修复**（生产代码行为已被 #508 验证正确，测试断言是滞后工件）→ 按 bug pre-investigation 的「Test-Only Fix Bugs」结构对比**断言维护策略**，而非生产代码修复方案。

### 4.1 Approach A: shot 级 `theme_color: null` 覆盖（跳过 theme 断言）

**描述：** e2e_shots.json 的 01_title 增加 `"theme_color": null`；runner L3 对每个 PNG 先查 shot 级配置，null/缺失 → 不传 `--theme`（其余 3 断言照旧）。

| 维度 | 评估 |
|------|------|
| Pros | 改动最小（fixture 1 行 + runner ~10 行）；JSON 直观；向后兼容（无字段 shot 回退全局）；不碰 analyze_bmp.py |
| Cons | 「跳过」≠「验证隐藏」——若未来世界在 MENU 重现，01_title 的 theme 断言不会红（仅剩非黑/色数/帧差兜底，BgPulse 蓝色大面积重现时色数/非黑可能仍过） |
| Risk | Low（机制风险低；覆盖语义弱是设计取舍） |
| Effort | 0.5-1 天 |

### 4.2 Approach B: 反向断言（`analyze_bmp.py` 新增 `--theme-absent`，01_title 指定）— **推荐**

**描述：** analyze_bmp.py 新增 `--theme-absent RRGGBB`：与 `_theme_present()` 同 stride 5 / 容差 32 采样，**命中 0 个采样点才通过**（阈值：0 命中；实现为 `not _theme_present(...)` 的镜像函数，语义「世界隐藏」）。e2e_shots.json 01_title 增加 `"theme_absent": "4a90d9"`；runner 逐 shot 解析 `theme_absent` → 传 `--theme-absent`（与 `theme_color` 互斥，同 shot 同时出现则报错）。

| 维度 | 评估 |
|------|------|
| Pros | 直接编码 AC1「世界隐藏断言」语义；未来 MENU 世界重现（回归）会红——把伪失败变成真回归检测；改动量仍小（analyze +~20 行、runner +~10 行、fixture 1 行、单测 2 处） |
| Cons | 新增 CLI flag + 单测；与正向断言共享容差/采样参数，需明确「0 命中」阈值；未来 title 屏若引入 #4a90d9 系 UI 元素（如按钮高亮）会误报——需在边界条件中处理 |
| Risk | Med（误报风险可控：当前 StartMenu 无 #4a90d9 系色，实测 0 像素基线；容差 32 远小于 UI 霓虹青/白与 #4a90d9 的色距） |
| Effort | 1-1.5 天 |

### 4.3 Approach C: 全局移除 `theme_color`

**描述：** 从 e2e_shots.json 删除顶层 theme_color（runner 不再传 --theme）。

| 维度 | 评估 |
|------|------|
| Pros | 一行改动 |
| Cons | 02_midgame/03_gameover 失去「世界在渲染」正断言（#466 已记录语义弱化但保留仍验证 BgPulse/板系色存在）；模板与其他 game 副本同受影响；破坏 #358 引入的通用机制而非修 shot 粒度 |
| Risk | Low-Med（覆盖退化是主要风险） |
| Effort | <0.5 天 |

### 4.4 推荐汇总

| 方案 | 语义强度 | 改动量 | 风险 | 推荐 |
|------|---------|--------|------|------|
| A: shot 级覆盖跳过 | 弱（跳过） | 最小 | Low | 备选（保底） |
| **B: 反向断言世界隐藏** | **强（断言隐藏）** | 小 | Med（可控） | **✅ 推荐** |
| C: 全局移除 | 无（移除） | 最小 | 覆盖退化 | ❌ 不推荐 |

**推荐 B 的理由（编号）：**
1. Issue body 明确「理想做法：断言『世界隐藏』——theme 容差像素 ≈ 0（反向断言）」——B 直接满足 AC1 的最强语义，A 是降级形式。
2. 实测基线干净（title 0 个 theme 像素，StartMenu 无同系色）→ 反向断言当前不会误报；容差 32 与 #4a90d9 到 UI 霓虹青（#00e5ff）/白（#ffffff）的通道距离（≥74/0…实际 ≥74）相比足够安全。
3. 把「伪失败」转化为「真回归检测」：世界隐藏逻辑（#508）未来的回归会触发 01_title 反向断言变红——正是该断言应有的职责。
4. 改动面仍符合 light 深度：1 个 fixture shot + 1 个 analyzer flag + runner 逐 shot 解析 + 2 处单测，无新增文件、无生产代码改动。
5. 与既有 4 断言模型兼容（新增 flag-gated 第 5 项，纯 stdlib，CI 双平台不变）。

**降级路径：** 若实现期评估 B 的 runner 逐 shot 解析复杂度超预期，可退化为 A（fixture + runner 小改），但 AC1 的世界隐藏断言语义需在 impl PR 说明中明确降级理由。

## 5. 边界条件与验收标准

### 5.1 正常路径（AC 检查表）

- [x] **AC1: L3 全绿 — 01_title 世界隐藏断言**
  - 01_title PNG 通过：非黑（黑占比 ≤ 50%）、色数 ≥ 3、帧差（与 02 的 Δluma ≥ 5.0 / diff-ratio ≥ 0.005 语义不变）、assert_text（VersionLabel 含 v1.0.0）
  - `--theme-absent 4a90d9` 通过（0 个采样点命中，stride 5 / 容差 32）
- [x] **AC2: 02_midgame / 03_gameover 不受影响**
  - 两 shot 仍走 `--theme 4a90d9` 正断言（世界可见 → theme 像素存在 → 通过）
  - 两 shot 其他断言（非黑/色数/帧差）不变
- [x] **AC3: `scripts/run-e2e-review.sh --with-visual` 显式重跑至 L3 全绿**
  - 验证命令：`scripts/run-e2e-review.sh <PR_NUM> --subproject mini-pong --with-visual`
  - 结论表中 L3 视觉 = pass
- [x] **AC4: pipeline 单测不回归**
  - `tests/pipeline/test_e2e_analyze.py`（含新反向断言正/反用例）
  - `tests/pipeline/test_e2e_runner.py`（shot 级配置解析）
  - `tests/pipeline/test_e2e_resolve.py`（不透传变化，仅确认无回归）

### 5.2 边界情况

1. **title 屏未来引入 #4a90d9 系 UI 元素**（如按钮高亮复用 PLAYER_NEON_BLUE）→ 反向断言误报。处理：以当前 0 像素为基线；UI 改色时同步更新/移除 01_title 的 theme_absent（在 Continuation Context 记录该耦合）。
2. **stride 5 采样漏检/误检孤点** → 反向断言与正向断言共用同一采样实现（对称性），行为可预期；阈值固定为「0 命中」。
3. **shot 无 theme_absent / theme_color 字段** → 回退现有全局行为（顶层 theme_color 正断言），向后兼容。
4. **同 shot 同时声明 theme_color 与 theme_absent** → runner 校验互斥并报错（fail-fast），防止配置矛盾。
5. **shot 级字段拼写错误**（如 theme_abset）→ runner 遇到未知 shot 级键应告警（不静默忽略），避免配置失效无感知。
6. **PAUSED 或未来新增 MENU 系 shot** → 机制天然可复用（shot 级配置随 shot 走，resolve 去重后仍保留）。
7. **模板 `framework/templates/e2e_shots.json` 同步** → 不强制（本 issue 只要求 mini-pong）；留待模板使用者遇到同问题时按本 PRD 模式处理。

### 5.3 失败路径

1. **analyze_bmp.py 无 `--theme-absent` 参数**（runner 与 analyzer 版本不同步）→ argparse 未知参数报错，L3 fail 且日志明确；CI 与本地共用同一 repo 源码，实际不会发生，但 runner 应先 `--help` 探测或直接依赖同仓文件。
2. **容差/采样过松导致世界未隐藏仍通过** → 单测覆盖正反用例（构造含 theme patch 的图：正断言过、反向断言 fail；纯背景图：反向断言过）。
3. **runner 读不到 plan.json shots**（plan 结构变化）→ 保持现状全局 THEME 回退（不崩溃），并在日志 warning 提示 shot 级配置未应用。
4. **世界隐藏回归（MENU 世界重现）** → 01_title 反向断言变红 = 正确捕获回归（这正是 B 优于 A 的价值点），impl 阶段按真 bug 处理而非豁免。

## 6. 依赖与阻塞

Skipped per `depth/light` label（依赖已在头部列出：#508/#511 merged 提供行为变更，#358 提供机制，#466/#476 提供断言体系；无阻塞项）。

## 7. Spike / 实验

Skipped per `depth/light` label。研究期已完成的验证：Main.tscn 组归属核对、constants.gd 色值核对、runner/analyze 源码路径核对、issue body 实测像素数据（0 vs 1328）采纳。无需额外 spike。

## 8. 延续上下文（Continuation Context）

**给 plan agent 的手递交接力：**

**系统状态：** #508（PR #511）已 merge 到 main，`game_state_machine.gd` 含 `_set_world_visible()`（MENU 隐藏 game_world 组，含 AtmosphereLayer/BgPulse/RainCurtain + 球 + 双拍）；`mini-pong/e2e_shots.json` 顶层 `theme_color: "4a90d9"` 仍对全部 3 个 shot 生效 → L3 在 01_title 伪失败。issue #517 已带 `workflow/research` 标签，本 PRD merge 后由 workflow-chain 推进到 `workflow/plan`。

**推荐方案（§4.4）：Approach B 反向断言。** plan 阶段需产出的 DESIGN 要点：

1. **analyze_bmp.py**：新增 `--theme-absent RRGGBB` flag（与 `--theme` 互斥校验），实现镜像 `_theme_present()` 的 `_theme_absent()`（stride 5、容差 32、0 命中才过）；更新文件头文档字符串。
2. **run-e2e-review.sh L3 段**：从 plan.json 读 shots 数组，按 PNG 文件名（= shot name）查 shot 级配置：`theme_absent` → 传 `--theme-absent`；`theme_color: null` → 不传 theme；缺省 → 顶层 THEME 回退（现状）。互斥/未知键校验。
3. **e2e_shots.json**：01_title 增加 `"theme_absent": "4a90d9"`（保留 assert_text 等既有字段）；02/03 不动。
4. **单测**：test_e2e_analyze.py 增加反向断言正/反用例；test_e2e_runner.py 增加 shot 级配置解析用例（fake godot 像素逻辑按 shot 配置生成）。
5. **验证命令**：`scripts/run-e2e-review.sh <PR_NUM> --subproject mini-pong --with-visual`（--with-visual 显式开启 L3）；pipeline 单测全绿。

**主要风险：** title 屏未来引入 #4a90d9 系 UI 色 → 反向断言误报（§5.2-1，改 UI 色时同步维护）；runner 与 analyzer 版本不同步（§5.3-1，同仓文件，风险低）。

**边界红线：** 不修改生产代码（ball/paddle/fsm 均不动）；不修改 02/03 shot 断言；不全局移除 theme_color；白名单提交仅限上述文件（worktree-commit.sh 强制）。
