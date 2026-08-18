# PRD #559 — [Test] shandong-wolf 管线冒烟验证 — Main.tscn 标题场景 + 解耦配置回归

> **Issue:** #559
> **标签:** enhancement, version/mvp, workflow/available（research 阶段认领）, 无 depth 标签 → 按 light 处理
> **Agent:** game-research-agent
> **日期:** 2026-08-19
> **深度:** light（§1–5 + §8 必填，§6 简述，§7 跳过并注明）
> **所有权:** `content_ownership: mechanical`（标题场景 = 管线冒烟验证物，无品味裁决；审美坐标见 §1.6 Obsidian/brief）
> **引擎/目录约束:** Godot 4.7.1 / `shandong-wolf/`（manifest `game.active: shandong-wolf` + subprojects.path 单一事实源；本 PRD 全部路径前缀 `shandong-wolf/`，无 `mini-pong/` 写死）
> **研究选项:** Obsidian 知识库已搜索（`~/Documents/Obsidian Vault`，wiki+raw 全量 grep 山东/抗日/只狼/雪夜/标题/主菜单/开场/像素）+ 设计 brief（`docs/RAW/shandong-wolf-brief.md`）+ GDD 分目录（`docs/GAME_DESIGN/shandong-wolf/`）
> **来源:** 任务指派（game-research-agent）
> **前置依赖:** #75a057a（P3 参数化收尾，已 merged）— manifest game.active 全链路参数化；mini-pong 标题场景参考实现（#508/#517 沉淀于 `mini-pong/scenes/Main.tscn` StartMenu 结构，仅作模式参考，不复制代码）

---

## 1. 问题定义

### 1.1 现状（shandong-wolf/ 骨架状态，2026-08-19 侦查）

| 文件 | 状态 | 说明 |
|------|:----:|------|
| `shandong-wolf/project.godot` | ⚠️ 半成品 | `config/name="山东抗日之狼"` 已设；**`run/main_scene=""` 为空** → `godot --path shandong-wolf/` 启动无场景可加载；窗口 1280x720、stretch canvas_items 已设 |
| `shandong-wolf/scenes/` | ❌ 空 | 仅 `.gitkeep`；无 Main.tscn |
| `shandong-wolf/gdscripts/` | ❌ 空 | 仅 `.gitkeep`；无任何脚本 |
| `shandong-wolf/assets/` | ❌ 空 | 仅 `.gitkeep`（程序化生成路径，零美术资产） |
| `shandong-wolf/tests/run_tests.gd` | ✅ 占位 | 「skeleton — no tests yet」，退出码 0 |
| `shandong-wolf/tests/smoke_test.gd` | ✅ 占位 | 「SMOKE OK: shandong-wolf skeleton loads」 |
| `shandong-wolf/tests/check_compile.gd` | ✅ 可用 | 遍历 gdscripts/ + tests/ 逐个 load 校验 |
| `shandong-wolf/e2e_shots.json` | ⚠️ 占位 | `states: {}`、`state_node: ""` — 无真实 shot plan |

**核心缺口：** shandong-wolf 无主场景（Main.tscn），`run/main_scene` 未指向任何场景 → 游戏进程无画面可渲染；管线冒烟只能验证「工程能加载/编译」，无法验证「渲染出可见内容」。本 issue 的最小交付 = 创建一个**启动即显示标题『山东抗日之狼』+ 版本标签 v0.1.0** 的 Main.tscn，作为解耦配置（75a057a）在真实管线中的第一个落地物。

### 1.2 验收条件（源自 Issue #559 body，映射到各阶段 agent）

| # | 验收条件 | 负责阶段 | 本 PRD 的保障措施 |
|---|---------|---------|------------------|
| AC1 | SPAWN 指令携带 game=shandong-wolf | dispatcher | event-processor.py:1059 从 manifest game.active 读 ACTIVE_GAME（已核实代码），与 PRD 无关，无改动 |
| AC2 | research agent 侦查命令使用 $GAME_DIR（PRD 引用路径全为 shandong-wolf/） | research | ✅ 本 PRD 全部代码路径前缀 `shandong-wolf/`，零 `mini-pong/` 写死（§3/§8 同） |
| AC3 | implement PR 的 diff 只落在 shandong-wolf/ 下 | plan/implement | §8 红线：只建 `shandong-wolf/scenes/Main.tscn`（+ 可选 `gdscripts/main_title.gd`），改 `shandong-wolf/project.godot` 一行；绝不触碰 `mini-pong/` |
| AC4 | CI 日志显示 GAME_DIR=shandong-wolf | CI | opencode-review.yml L44-50 已从 manifest 解析 GAME_DIR（已核实），随 game.active 自动跟随，无改动；implement PR 合入后 CI 日志即含 `active game: shandong-wolf (dir: shandong-wolf)` |
| AC5 | review E2E 截图可见标题『山东抗日之狼』（非默认灰屏） | review | §5.2 边界 #1：Main.tscn 标题**启动即默认可见**（不依赖按键/状态机），任何启动截图即命中 |
| AC6 | review post-merge GDD 写入 docs/GAME_DESIGN/shandong-wolf/（分目录生效） | review | GDD INDEX.md 已声明「首个 implement PR merge 后由 review agent 填充」；本 PRD 不写 GDD |

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | CI L2（opencode-review.yml compile/test/smoke） | 每次 impl PR | `godot --path shandong-wolf/ ...` 必须能解析主场景并渲染；当前 run/main_scene 为空 → `--quit` 冒烟通过但无渲染证据 |
| B | review E2E 截图（run-e2e-review.sh） | 每次 impl PR | 需默认可见的标题画面作为「非灰屏」证据；当前无场景可截 |
| C | 玩家/用户首启 | 手动 | `godot --path shandong-wolf/` 启动即见『山东抗日之狼』+ v0.1.0，验证 P3 解耦（manifest 切到 shandong-wolf 后全链路跟随） |

### 1.4 范围边界（与 P3 收尾去冲突，Patch 14）

| PRD / 变更 | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----------|---------|------------------|
| 75a057a（P3 参数化收尾，已 merged） | manifest 单一事实源：event-processor/CI/worktree-commit/SPAWN 全部消费方参数化 | ❌ 不改 manifest、不改 CI workflow、不改 event-processor — 只**验证**消费方已跟随 |
| mini-pong `scenes/Main.tscn`（#508/#517 标题沉淀） | mini-pong 完整 StartMenu（状态机 + 模式选择 + 游戏 HUD 等） | ❌ 不复制 mini-pong 游戏逻辑/UI 树 — 只参考其「TitleLabel + VersionLabel」最小结构模式 |
| 本 PRD（#559） | shandong-wolf 首个落地物：Main.tscn 标题场景 + run/main_scene 指向 | 版本标签 v0.1.0 骨架期硬编码可接受；constants.gd/入场动画/主菜单交互留给后续 issue（§8 注明） |

### 1.5 预期行为（最小冒烟语义）

1. [ ] `godot --path shandong-wolf/`（无参数）启动 → 渲染 1280x720 画面，居中大标题『山东抗日之狼』，左下角版本标签 v0.1.0
2. [ ] `project.godot` `run/main_scene="res://scenes/Main.tscn"` — 主场景可解析、可加载、可渲染
3. [ ] CI 三命令（check_compile / run_tests / smoke_test）仍全绿（不破坏骨架占位测试）

### 1.6 Obsidian 知识检索

- **Vault 直接读取成功**（`~/Documents/Obsidian Vault/`，wiki + raw 全量 grep：`山东|抗日|只狼|雪夜|标题|主菜单|开场|像素|教程|菜单`）。
- **命中笔记：**
  - **《独立游戏开发讨论》§四「雪夜项目的教训」**（本项目前身即「雪夜大刀」）：*「机制类游戏：核心系统做完、一轮游戏能跑就立住了」*、*「不用憋太久，做 20-50% 就可以放出去」* → **直接支撑本 issue 的最小冒烟策略**：标题场景只做「能跑」的验证物，不追求完整主菜单/开场演出。
  - **《游戏设计理念》§教程设计**（raw/Evernote/完美的一天/什么是好的教程？）：*「当玩家的需求涌现出来的时候，再解决玩家有效的信息，是好的教程」*、*「更少文字，使用互动的方式」*、*「Context Sensitive Information」* → 标题场景**克制**：一个大标题 + 版本标签，不堆副文案；后续交互引导（「按任意键开始」等）等需求涌现时再加。
  - **《CUSGA 2026 游戏评选笔记》**：横版叙事像素类作品评估语境（遗愿清单等）→ 佐证 brief「横板像素动作」审美定位。
- **Vault 无 shandong-wolf 专属标题/主菜单设计笔记**（命中均为通用设计原则）→ 标题场景的设计权威源 = `docs/RAW/shandong-wolf-brief.md`（审美坐标：雪夜、水墨、黄土、血色、苍白；文字质感：短句、克制、乡土）+ 反例约束（页游感光效堆砌/浮夸 UI → 版本标签低调不抢戏）。

---

## 2. 设计意图

### 2.1 现状为何存在

| 约束 | 来源 | 说明 |
|------|------|------|
| shandong-wolf/ 为骨架空壳 | `scripts/new-game-scaffold.sh` | 新游戏注册 = 目录骨架 + project.godot + 占位测试 + e2e 占位；首个 implement issue 落地首个真实文件 |
| run/main_scene 为空 | scaffold 默认 | 等待首个场景落地；当前 `--quit` 冒烟只验「工程可加载」 |
| 占位测试全绿 | scaffold 占位 | run_tests/smoke 无真实断言，退出码 0 |

### 2.2 为什么现在改

75a057a（2026-08-19）完成 P3 参数化收尾：manifest `game.active` 成为全链路（SPAWN/CI/worktree-commit/Skills 消费方）单一事实源。但**参数化本身未在真实管线验证**——mini-pong 时代所有消费方都「恰好在读 mini-pong」；切到 shandong-wolf 后，第一个能证明「消费方真的跟随了新游戏」的落地物就是 shandong-wolf 自己的主场景。本 issue 即该验证的最小载体：Main.tscn 一出现，CI 的 GAME_DIR 解析、implement 的 worktree 路径、review 的 E2E 截图全部首次对 shandong-wolf 生效。

### 2.3 先前约束（继承，Patch 19）

| 约束 | 详情 |
|------|------|
| 引擎版本 | Godot 4.7.1（manifest engine.version；project.godot `config/features=PackedStringArray("4.7")`） |
| 游戏目录 | `shandong-wolf/`（manifest subprojects.shandong-wolf.path；**绝不写死 mini-pong/**） |
| 窗口规格 | 1280x720、`window/stretch/mode="canvas_items"`、resizable=false（project.godot 已设，继承） |
| 资产策略 | 程序化生成（零美术资产）为主（brief §画面实现路径）→ 标题用 Label/默认字体即可，不引外部字体 |
| 验收命令 | `godot --path shandong-wolf/ --headless --script tests/{check_compile,run_tests,smoke_test}.gd`（CI L2 同命令族） |
| 冒烟语义 | 启动即渲染可见标题（E2E 截图不需要按键/状态机驱动） |

---

## 3. 影响分析

### 3.1 新文件

| 文件 | 用途 | 变更性质 |
|------|------|---------|
| `shandong-wolf/scenes/Main.tscn` | 主场景：标题『山东抗日之狼』（居中大 Label）+ 版本标签 v0.1.0（左下小 Label） | 新建（方案 A 零脚本；或方案 B 挂 `main_title.gd`） |
| `shandong-wolf/gdscripts/main_title.gd` | 版本号/标题参数化（@export），可选入场淡入 | 新建（仅方案 B；方案 A 不需要） |

### 3.2 修改文件

| 文件 | 变更 | 性质 |
|------|------|------|
| `shandong-wolf/project.godot` | `run/main_scene="res://scenes/Main.tscn"`（一行） | 修改（必需） |
| `shandong-wolf/e2e_shots.json` | 可选：补 `01_title` 真实 shot（state "" + theme_absent + assert_text 版本标签）或保留占位 | 修改（可选，建议 plan 阶段一并落真实 shot 计划，见 §8） |

### 3.3 间接影响

| 文件/系统 | 影响 |
|----------|------|
| CI `opencode-review.yml` | **零改动**（L44-50 已 manifest 参数化）；implement PR 合入后 compile/test/smoke 首次对 shandong-wolf/ 真实执行 |
| `docs/GAME_DESIGN/shandong-wolf/` | 零改动（review agent merge 后按 INDEX.md 声明填充 GDD 章节） |
| `mini-pong/` | **零改动**（红线：不触碰；其 Main.tscn 仅作结构参考） |
| `scripts/event-processor.py` | 零改动（SPAWN 已携带 game=shandong-wolf，AC1 由 dispatcher 验证） |

### 3.4 数据流影响（启动链）

```
godot --path shandong-wolf/   （无参数）
    │
    ▼
project.godot run/main_scene = "res://scenes/Main.tscn"   ← 本次必改（当前为空）
    │
    ▼
Main.tscn 实例化（根节点 Main, CanvasLayer → CenterContainer）
    ├── TitleLabel（山东抗日之狼, font_size 64, 居中）        ← 启动默认可见
    └── VersionLabel（v0.1.0, font_size 16, 左下锚点）        ← 低调（Obsidian「克制」反例约束）
    │
    ▼
CI smoke（--headless --quit 退出码 0）／ review E2E 截图（首帧即含标题，非灰屏）
```

### 3.5 需更新的文档

- [x] 本 PRD（`docs/PRD/559-shandong-wolf-pipeline-smoke.md`）
- [ ] `docs/GAME_DESIGN/shandong-wolf/` — review agent 在首个 implement PR merge 后按 INDEX.md 约定填充（本 PRD 不写）
- [ ] `shandong-wolf/e2e_shots.json` — 可选真实 shot plan（§8 建议）

---

## 4. 方案对比

### 方案 A：纯场景静态标题（零脚本）

`Main.tscn` 内直接声明节点树（仿 mini-pong StartMenu 最小结构，但去掉状态机/交互）：CanvasLayer → CenterContainer → VBoxContainer → TitleLabel（text=山东抗日之狼, font_size 64）+ VersionLabel（text=v0.1.0, font_size 16, anchors 左下）。project.godot 补 run/main_scene 一行。无 .gd 文件。

- **优点**: 改动面最小（1 新 tscn + 1 行 project.godot）；零脚本零编译风险；CI/headless 全兼容；标题默认可见满足 E2E 截图；完全落在 shandong-wolf/ 内
- **缺点**: 版本号硬编码在 tscn（后续引入 constants.gd 时需迁移）；无入场动画（冒烟期不需要）
- **风险**: Low；**Effort**: 0.5 天以内（含 E2E 截图验证）

### 方案 B：场景 + 轻量脚本（标题参数化 + 淡入）

方案 A 基础上新增 `shandong-wolf/gdscripts/main_title.gd`：`@export var title_text`、`@export var version_text`、`@export var version`，`_ready()` 中写入 Label 并做 0.5s modulate 淡入。

- **优点**: 版本号/标题参数化（为后续 constants.gd/多语言留口）；入场淡入提升首帧观感（E2E 截图仍可见）
- **缺点**: 多一个 .gd 文件 = 多一份编译/加载面；淡入动画属「视觉微调」范畴，骨架期无必要（克制纪律）
- **风险**: Low；**Effort**: 1 天以内

### 方案 C：移植 mini-pong StartMenu 完整结构（状态机 + 模式选择）

把 `mini-pong` 的 start_menu.gd + ModeSelect + 「按 SPACE 开始」整套移植到 shandong-wolf。

- **优点**: 一步到位有交互主菜单
- **缺点**: **明显过度**——shandong-wolf MVP 是核心动作系统（brief §MVP 策略），主菜单交互在核心玩法之后才有意义；复制 mini-pong 代码违反「不写死 mini-pong」精神且扩大 diff 面（AC3 红线压力）；冒烟验证不需要交互
- **风险**: Med（范围膨胀）；**Effort**: 2 天+

### 推荐

**方案 A（主），方案 B 的入场动画作为后续视觉 issue 的可选扩展。**

1. **A 满足全部 AC 且零风险**：冒烟验证的最小语义 = 「启动能渲染出标题 + 版本」；纯 tscn 声明即可达成，CI/headless/E2E 全兼容。
2. **版本标签 v0.1.0 骨架期硬编码可接受**：项目尚无 constants.gd（gdscripts/ 为空），为单值引入脚本层是本末倒置；plan agent 在 implement 时若顺手建 constants.gd 则可参数化（不强求）。
3. **克制纪律（Obsidian 反例约束 + brief 文字质感）**：标题场景只做标题 + 版本，不堆副文案/不抢戏；「按任意键开始」等交互引导等需求涌现再加（教程设计原则）。
4. **不复制 mini-pong 代码（方案 C 否决）**：本 issue 是 shandong-wolf 的第一个落地物，复制旧游戏代码既违反解耦验证初衷，也埋下后续重构负担。

---

## 5. 边界条件与验收

### 5.1 正常路径（AC 检查清单，映射 Issue body）

- [ ] **AC1: SPAWN 携带 game=shandong-wolf** — dispatcher/event-processor 输出可查（本 PRD 零改动，验证项）
- [ ] **AC2: research 侦查全 $GAME_DIR** — 本 PRD 代码路径全为 `shandong-wolf/`，无 `mini-pong/` 写死（可 grep 校验：`grep -rn "mini-pong" docs/PRD/559-*.md` 仅命中参考说明，不命中任何代码路径）
- [ ] **AC3: implement diff 只落 shandong-wolf/** — 红线：`shandong-wolf/scenes/Main.tscn`（新建）+ `shandong-wolf/project.godot`（一行）+ 可选 `shandong-wolf/e2e_shots.json`
- [ ] **AC4: CI 日志 GAME_DIR=shandong-wolf** — implement PR 合入后 opencode-review.yml 输出 `active game: shandong-wolf (dir: shandong-wolf)`，compile/test/smoke 均跑 shandong-wolf/
- [ ] **AC5: review E2E 截图可见标题** — 首帧截图含『山东抗日之狼』（非默认灰屏）；截图前无需按键
- [ ] **AC6: post-merge GDD 写入分目录** — review agent 写 `docs/GAME_DESIGN/shandong-wolf/`（INDEX.md 已就位）

### 5.2 边界情况

| # | 场景 | 处理 |
|---|------|------|
| 1 | E2E 截图发生在启动早期（标题未渲染完成） | TitleLabel 无动画（方案 A）→ 首帧即可见；若 plan 选了方案 B 淡入，settle_frames ≥ 10（仿 mini-pong 01_title shot） |
| 2 | headless 模式（CI）下 Label 渲染 | headless 仍实例化场景树，`--quit` 冒烟通过即可；渲染正确性由 review E2E 截图保证 |
| 3 | 中文字体缺失导致标题豆腐块 | Godot 4.x 内置默认字体含 CJK（mini-pong 已用中文「暂停」等 Label 验证）；若截图发现缺字 → 引入程序化位图字体（generate_pixel_font.py 已有），列为 review 期修复项 |
| 4 | `run/main_scene` 路径写错 | implement 后本地 `godot --path shandong-wolf/ --headless --quit` 必跑；路径错误会报 `Cannot open file` 直接失败 |
| 5 | e2e_shots.json 占位（states 空）导致 review 无 shot 可跑 | review agent 用 run-e2e-review.sh 默认捕获；plan 阶段建议补 `01_title` shot（state ""、theme_absent、assert_text 版本标签）使 L3 视觉断言自动化 |
| 6 | 窗口 1280x720 下标题字号溢出 | font_size 64 居中 + 长标题 6 字 ≈ 384px < 1280 宽，无溢出；版式验收以 E2E 截图为准 |
| 7 | 并发 agent 污染 worktree | worktree-commit.sh 白名单 add（只 add 本 PRD 文件），本阶段不触碰主工作区 |

### 5.3 失败路径

| # | 场景 | 处理 |
|---|------|------|
| 1 | implement 误改 mini-pong/ 或 manifest | stage-gate + review diff 检查拦截；红线条款在 §8 明示 |
| 2 | CI 上 GAME_DIR 解析异常（manifest 未随 active 更新） | opencode-review.yml 已参数化（L44-50），若日志仍显示 mini-pong 则属 P3 回归，需回查 manifest；本 issue 验证项 |
| 3 | E2E 截图灰屏/黑屏（场景加载失败） | 检查 run/main_scene 指向与 tscn 格式（gd_scene format=3）；`--headless --quit` 退出码 0 仅是加载通过，渲染层问题以截图证据裁决 |

---

## 6. 依赖与阻塞（light：简述）

| 依赖 | 状态 | 说明 |
|------|:----:|------|
| 75a057a（P3 参数化收尾） | ✅ merged（2026-08-19） | 本 issue 验证其消费方跟随；无阻塞 |
| manifest `game.active: shandong-wolf` | ✅ 已生效 | SPAWN/CI/worktree 全链路已指向 shandong-wolf |
| mini-pong 标题参考（#508/#517） | ✅ 已落地 | 仅模式参考（TitleLabel + VersionLabel 结构） |
| CI workflow（opencode-review.yml） | ✅ 已参数化 | 零改动，随 game.active 自动跟随 |

无阻塞项。

---

## 7. Spike / 实验

Skipped per light 深度（issue 无 depth/ 标签，机械冒烟验证物；标题场景无未决技术风险，Godot 4.7 Label/CanvasLayer 均为成熟 API，mini-pong 已有同构实现佐证）。

---

## 8. 交接上下文（Continuation Context）

**给 plan agent 的交接：**

**系统现状：** `shandong-wolf/` 为骨架空壳：project.godot（name=山东抗日之狼，**run/main_scene="" 为空**）、scenes/gdscripts/assets 全空（.gitkeep）、tests 为占位全绿、e2e_shots.json 占位（states 空）。本次要落第一个真实文件 = 主场景标题画面。

**关键代码位点（plan 必读）：**
- `shandong-wolf/project.godot` — `run/main_scene=""`（**必改**为 `res://scenes/Main.tscn`）；窗口 1280x720 / stretch canvas_items 已设
- `mini-pong/scenes/Main.tscn` — StartMenu 段（TitleLabel font_size 64 + VersionLabel font_size 16 左下锚点）为**结构参考**，只取模式不复制代码
- `shandong-wolf/e2e_shots.json` — 占位（state_node ""/states {}）；建议补 `01_title` shot（theme_absent + assert_text 版本标签 v0.1.0）使 L3 视觉断言自动化；不补则 review 以默认截图为准
- `shandong-wolf/tests/*.gd` — 占位测试**不要改**（AC 未要求），保持全绿

**推荐实现路径（方案 A）：**
1. 新建 `shandong-wolf/scenes/Main.tscn`（gd_scene format=3）：根节点 `Main`（Node2D）→ CanvasLayer → CenterContainer（全屏锚点）→ VBoxContainer → TitleLabel（text=山东抗日之狼, font_size 64, 居中）+ VersionLabel（text=v0.1.0, font_size 16, 左下锚点 anchors_preset=2）
2. `shandong-wolf/project.godot` 改一行：`run/main_scene="res://scenes/Main.tscn"`
3. 本地验证：`godot --path shandong-wolf/ --headless --quit`（退出码 0）＋ `godot --path shandong-wolf/ --headless --script tests/run_tests.gd`（全绿）
4. 可选：`e2e_shots.json` 补 `01_title` shot
5. 提交时只 add `shandong-wolf/` 下文件（红线），PR body 用 `parent #559`

**主要风险：** ① 误改 mini-pong//manifest（红线：diff 只落 shandong-wolf/，AC3 由 stage-gate/review 拦截）；② 中文字体缺字（内置默认字体含 CJK，截图裁决）；③ E2E 占位 shot 计划导致视觉断言缺失（建议补 01_title shot，最坏情况 review 手动截图）。

**红线：** 只动 `shandong-wolf/`（新建 scenes/Main.tscn、改 project.godot 一行、可选 e2e_shots.json）；**绝不触碰 `mini-pong/`、`game-env/manifest.yaml`、`.github/workflows/`**；标题启动即默认可见（E2E 截图不依赖按键）；PR body 用 `parent #559`。
