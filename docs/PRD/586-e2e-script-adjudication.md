# PRD #586 — [Test] 端到端验证（E2E 剧本 + 用户裁决）

> **Issue:** #586（labels: enhancement, workflow/research, testing, version/mvp）
> **深度:** standard（GitHub 无 depth label；分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=15 标注 `depth: standard` → §1–6 + §8 必填；§7 含 3 个轻量实验——E2E 管线有真实未知（clash 帧确定性/移动注入/Movie Maker 保真），参照 #585 先例）
> **Agent:** game-research-agent
> **日期:** 2026-08-20
> **所有权:** `content_ownership: mechanical`（E2E 剧本/管线/报告 = 机械工程：JSON 剧本组 + rig 状态扩展 + 元数据 schema；**用户对 6 帧的手感与审美裁决是唯一 taste 环节，agent 禁止替用户裁决**——issue 明文「禁止自动化通过替代用户裁决」）
> **引擎/目录约束:** Godot 4.7.1 / `shandong-wolf/`（manifest `game.active: shandong-wolf` + subprojects.path 单一事实源；本 PRD 全部路径前缀 `shandong-wolf/`，零 `mini-pong/` 写死）
> **研究选项:** Obsidian 知识库已搜索（`/Users/devvi/Documents/Obsidian Vault/`，wiki grep 情绪弧/开场/氛围/手感 → 最接近权威源 = `wiki/体验引擎-patterns.md` §4「情绪维持：低技能情绪触发器维持学习期参与度」与「氛围开场」（BioShock 案例）、`wiki/体验引擎-glossary.md`「Atmosphere = 弥漫在整个体验中的情感背景」）——与 #585 引用的审美坐标一致：6 帧覆盖情感弧（冷静开场 → 动作张力 → 高潮 → 余韵）+ 设计 brief（`docs/RAW/shandong-wolf-brief.md` §审美坐标）+ 源码审计（origin/main b8ce226 实测 9 文件，含 #666 merged 的 assembly 组与 rig）+ 同链 PRD/DESIGN（#585/#584/#555）+ 开源调研（GitHub API 检索 godot headless screenshot / gdUnit4 / GUT / movie maker，见 §4.4）
> **来源:** backlog-promotion（`docs/RAW/game-to-issues-shandong-wolf.json` id=15，estimate 2d，priority critical，milestone mvp）
> **前置依赖:** #585（CLOSED，PR #666 merged 2026-08-20，commit b8ce226——组装闭环已可玩，本 issue 在其上做 E2E 剧本）

---

## 1. Problem Definition

### 1.1 当前行为：E2E 截图管线已就位，但无 6 帧剧本、无用户裁决闭环、无测试报告机制

#585（#666 merged）交付了**可玩的 MVP 战斗闭环**（`main_battle.gd` BattleAssembler 342 行 + `e2e_main_assembly_capture.gd` 196 行 + `test_main_assembly.gd` 745 行 + smoke AC4 场景），E2E 截图管线（`run-e2e-review.sh` → `resolve_plan.py` → `e2e_capture.gd`）可对 `shandong-wolf/e2e_shots.json` 的 7 个 shot 组产出 1280x720 PNG。但 issue #586 要求的「6 帧情感弧剧本 + 用户裁决 + 测试报告」尚未落地：

**现有 shot 组盘点（origin/main 实测）：**

| 组 | 来源 Issue | 帧数 | 用途 |
|----|-----------|:---:|------|
| stick_figure | #574 | 12 | 火柴人 12 态动画摆拍（rig 注入，非实战） |
| snow_night | #582 | 1 | 雪夜氛围单帧（at_frame=30） |
| hud | #576 | 4 | HUD 4 态（debug API 驱动，零战斗依赖） |
| battle_stage | #583 | 3 | 舞台全景/平台/月亮构图 |
| feedback | #579 | 3 | 打击反馈三档（parry_success/stance_broken/execute 注入） |
| execution | #580 | 2 | 处决斩落 + 淡出 |
| assembly | #585 | 4 | 闭环证据（spawn_combat/parry_execute/fail_subtitle/afterglow） |

**6 剧本帧 vs 现有覆盖的差距分析（gap 表）：**

| 剧本帧（情感弧） | 现有覆盖 | 差距判定 |
|------|---------|:-------:|
| ① 雪夜村口开场（冷静） | assembly `01_spawn_combat`（rig 驱动 Main 实场景）+ snow_night（静态氛围） | ⚠️ 构图素材有，但无「场景描述/触发条件/期望构图」文字字段（AC1 缺口），且非剧本连贯第一镜 |
| ② 玩家移动 | stick_figure `02_move`（摆拍 rig，无真实玩家实体移动） | ❌ 无**真实游戏内**移动帧——需 press 注入（`e2e_capture.gd` 已支持方向键/action 注入，见 §3） |
| ③ 首次弹反火花（张力） | feedback `fb_parry_success`（注入）+ assembly `02_parry_execute`（一镜到底含后续崩解） | ⚠️ 有注入帧但非「首次弹反」独立剧本镜，构图无文字契约 |
| ④ 拼刀 | **无**——states 枚举（IDLE..DEAD 12 态）无 CLASH；无任何组覆盖 | ❌ **完全缺失**。`reaction_controller.gd` 已实现 clash 反馈（level B + spark，行 29/132-175 经 judge.clash 信号触发），rig 无对应驱动态 |
| ⑤ 敌人崩解 + 处决特写（高潮） | execution `01_execute_strike`/`02_execute_fade` + feedback `fb_stance_break` | ⚠️ 素材齐备但散落多组，非剧本连贯镜头 |
| ⑥ 失败字幕（余韵） | assembly `03_fail_subtitle`（BattleAssembler FAIL 态 → Label 淡入） | ✅ 已覆盖（文案候选『雪落无声。村口只剩你。』待用户定稿，#585 约定） |

**核心缺口 1 — AC1 剧本契约缺失：** 现有 7 组 29 帧全部是**组件级 AC 裁决素材**（「这个组件长这样，你裁决」），没有 issue 要求的「6 个剧本帧，每条含**场景描述/触发条件/期望构图（文字描述）**」。`e2e_shots.json` 的 shot 对象只有 `name/state/settle_frames/theme_color`，无剧本文字字段。

**核心缺口 2 — 截图管线非真正 headless：** issue 要求「自动截图管线可 headless 运行」（AC2）。Godot 4.7 的 `--headless` 是 dummy DisplayServer **无渲染能力**（截图=黑图/空图），本项目 `e2e_capture.gd` 头注释明确「Runs NON-headless (real rendering) via --script with a display driver」——现状是 `--display-driver macos --rendering-driver opengl3 --resolution 1280x720` 实渲染。需要研究 Movie Maker（`--write-movie`）等 Godot 原生确定性截图路径，并把「无人值守可运行」明确为 headless 语义（CI 无窗口环境等价物，见 §4.4 开源调研）。

**核心缺口 3 — 元数据不完整：** `results.json` 每帧只有 `{name, saved, frame, state}`，无剧本帧的 trigger/composition 元数据（AC2「JSON 元数据」缺口）。

**核心缺口 4 — 无用户裁决工作流与测试报告：** 无「6 帧 1-5 星评分 → 平均 ≥4 星 → 打回/通过 → 报告回填 acceptance」机制（AC4/AC5 缺口）；无「全部单元测试 + smoke 测试通过 + 测试报告产出」的脚本化入口（AC3 缺口）。

### 1.2 预期行为（issue 验收条件）

1. **AC1** `e2e_shots.json` 含 6 个剧本帧，每条含场景描述/触发条件/期望构图（文字描述）
2. **AC2** 自动截图管线可 headless 运行，输出 1280x720 PNG 与 JSON 元数据
3. **AC3** 全部单元测试（状态机/弹反/两条命/AI）与 smoke 测试通过，产出测试报告
4. **AC4** 用户对 6 张截图的裁决结果平均分 ≥4 星（否则对应 Issue 打回重做）
5. **AC5** 测试报告记录裁决意见并回填到对应 Issue 的 acceptance 中

### 1.3 用户场景

| 场景 | 频率 | 说明 |
|------|------|------|
| A 裁决者（首次验收） | 每次 E2E 通过后 | 看 6 帧截图 → 每张 1-5 星 → 平均分 ≥4 通过；<4 打回对应视觉 issue |
| B 玩家（手感侧证） | 每次 | 实机试玩 5-10 分钟，对照截图判断「图 vs 手感」一致性（截图只是 taste 裁决通道的一半） |
| C 维护者 | 每次管线改动 | 跑全量单测 + smoke + E2E，确认回归全绿后进入裁决队列 |

## 2. Design Intent

### 2.1 为什么现状如此

- **组件级 rig 是逐 issue AC 裁决的刻意产物**：#574/#576/#579/#580/#583/#585 各自交付独立截图 rig（rig 注入状态、零战斗依赖、确定性截图），服务「该组件/该系统的观感裁决」。这些 rig 按 issue 边界隔离，天然不成叙事剧本。
- **#585 是第一个「闭环证据」但只有 4 态**：assembly 组（spawn_combat/parry_execute/fail_subtitle/afterglow）证明「游戏可玩」，rig 驱动 BattleAssembler 状态——它是 #586 剧本组的**地基**（真实 Main.tscn 实例 + 真实组件装配），但 4 态 ≠ issue 要求的 6 帧情感弧。
- **审美坐标早就定调**：issue 上下文「E2E 是 taste-draft 的裁决通道——所有 visual 的行不行最终由用户看截图决定」，6 镜覆盖情感弧（冷静开场 → 动作张力 → 高潮 → 余韵）。这与 Obsidian 知识库的设计理念一致（氛围开场维持学习期参与度；Atmosphere 是弥漫的情感背景）——**#586 是把散落的组件证据编排成情感弧验收剧本**。

### 2.2 为什么现在改

- **MVP 闭环可玩是前置条件，已满足**：#666 merged（b8ce226）后 `godot --path shandong-wolf/` 是可玩战斗；E2E 从「组件 AC 证据」升级为「情感弧验收」的时机成熟。
- **#584 调参候选值等待用户实机裁决**：#584（taste-draft，已 merge 待定稿）的 AC5「最终数值由用户 E2E 实机裁决后从 # DRAFT 转正式」——**本 issue 就是那个裁决通道**。没有 #586，taste-draft 的验收闭环永远悬空。
- **回归保险**：#624（雪夜氛围回归）证明视觉验收需要可重复的截图基准；6 帧剧本组将成为 MVP 收尾的**最终视觉验收契约**。

### 2.3 前置约束（继承自 issue + 项目约定）

| 约束 | 详情 |
|------|------|
| 引擎/目录 | Godot 4.7.1 / `shandong-wolf/`（manifest 单一事实源） |
| 分辨率 | 截图 1280x720（e2e_capture.gd `--resolution 1280x720` 既有） |
| 画面伦理 | 截图不得人为后处理，如实提交引擎渲染帧 |
| 裁决伦理 | 禁止自动化替代用户裁决（agent 只产出素材与报告，不评星） |
| 开源优先 | 先调研 Godot headless screenshot / GUT / gdUnit，成熟方案优先复用（§4.4） |
| 确定性 | E2E 须确定性（#555 全局 RNG seed 先例）——剧本帧捕获不得依赖 AI 随机时序 |
| 失败文案 | 文案候选随 #585 已交付，用户定稿归 #584/用户，本 issue 不裁决文案 |

## 3. Impact Analysis

### 3.1 直接受影响文件

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `shandong-wolf/e2e_shots.json` | E2E 剧本 | **修改**：新增 `e2e_script` 剧本组（6 帧，每帧含 `scene_description`/`trigger`/`composition` 文字字段）；shot schema 扩展（向后兼容既有组） |
| `shandong-wolf/gdscripts/e2e_main_assembly_capture.gd` | E2E rig | **修改**：4 态 → 6 态（新增 MOVE/CLASH；PARRY_EXECUTE 拆分） |
| `framework/templates/e2e_capture.gd` | 截图驱动器 | **修改（可选小改）**：results.json 追加剧本元数据（trigger/composition 透传）；如需 Movie Maker 模式加 `--write-movie` 分支 |
| `scripts/run-e2e-review.sh` | 管线 | **修改（可选）**：headless 语义文档化 / movie 模式开关 / 测试报告汇总入口 |
| `shandong-wolf/tests/run_tests.gd` + `smoke_test.gd` | 测试 | **不改**（AC3 只需「跑通 + 报告」，测试套件已全绿基线） |
| `docs/TEST/`（新增） | 测试报告 | **新增**：E2E 剧本执行报告模板（6 帧 PNG + 元数据 + 单测/smoke 结果 + 裁决表） |

### 3.2 间接影响

- `shandong-wolf/gdscripts/reaction_controller.gd`：**零改动**——clash 反馈（level B + spark）已实现，rig 只消费 `trigger_feedback("clash")` 或 judge.clash 信号路径（行 132-175 已接线）
- `shandong-wolf/gdscripts/main_battle.gd`：**零改动**——rig 只经公有成员驱动（player/enemy/judge/reaction/fail_label），#585 驱动契约不变
- `.github/workflows/pipeline-tests.yml`：可选挂载 E2E 剧本组到 CI（非必须，本地 run-e2e-review.sh 已可跑）

### 3.3 数据流（剧本帧 → 用户裁决）

```
e2e_shots.json（新增 e2e_script 组 6 帧，含文字契约）
    │  resolve_plan.py 按 diff/组选择 + 扁平化
    ▼
run-e2e-review.sh（--subproject shandong-wolf）
    │  godot --display-driver <os> --rendering-driver opengl3
    │       --resolution 1280x720 --script e2e_capture.gd -- plan.json
    ▼
e2e_capture.gd（轮询 CaptureRig.current_state / press 注入 / deadline 兜底）
    ├── shots/01_village_open.png … 06_fail_subtitle.png（1280x720 如实帧）
    └── results.json（name/saved/frame/state + trigger/composition 元数据）
            ▼
测试报告（docs/TEST/586-*.md：单测全绿 + smoke 全绿 + 6 帧 + 裁决表）
            ▼
用户裁决（6 帧 1-5 星，平均 ≥4 通过；<4 打回对应 Issue）
            ▼
裁决意见回填对应 Issue acceptance（AC5）
```

### 3.4 需更新的文档

- [x] `shandong-wolf/e2e_shots.json`（剧本组 + schema 扩展）
- [ ] `docs/GAME_DESIGN/shandong-wolf/`（若 GDD 有 E2E 验收章节则追加 6 帧契约；无则跳过）
- [ ] `framework/templates/e2e_shots.json`（模板补文字字段示例，供未来游戏复用）

## 4. Solution Comparison

### 4.1 Approach A — 扩展 assembly rig 至 6 态（推荐）

**描述：** 在 `e2e_main_assembly_capture.gd` 现有 4 态基础上扩为 6 态，直接对应 6 剧本帧；rig 仍实例化真实 Main.tscn（BattleAssembler 闭环），各态经 assembler 公有成员 + 既有组件公开接口驱动：

| 态 | 剧本帧 | 驱动路径 |
|----|--------|---------|
| SPAWN_COMBAT=0 | ① 雪夜村口开场 | 现有（出生遇敌构图，settle_frames 对齐雪花飘落） |
| MOVE=4（新） | ② 玩家移动 | press 注入方向键/`game_move_right` action 持续 N 帧后截图（e2e_capture.gd 已支持 `{"action":...}` 与 `{"key":"right"}`，行 164-177） |
| PARRY=1（拆） | ③ 首次弹反火花 | 复用 parry_success 注入（feedback rig 同款手法）+ 火花特写构图（StageCamera 推近） |
| CLASH=5（新） | ④ 拼刀 | 双攻击窗口同帧注入 → judge.clash 信号 → reaction 火花（既有链路，零新组件）；或直接 `trigger_feedback("clash")` |
| EXECUTE=2（拆） | ⑤ 敌人崩解 + 处决特写 | 现有 PARRY_EXECUTE 拆出崩解定格 + 处决斩落两镜（execution rig 构图先例） |
| FAIL_SUBTITLE=3 | ⑥ 失败字幕 | 现有（BattleAssembler FAIL → Label 淡入） |

- **Pros:** 单一 rig 场景、确定性最强（rig 注入 = 零 AI 随机）；与 #585 驱动契约完全兼容（零组件改动）；clash 复用既有反馈链路；MOVE 态顺带验证 press 注入能力（为未来真机剧本铺路）
- **Cons:** rig 代码增长（4→6 态）；②③④ 是「注入帧」而非「实战帧」——用户裁决的是 rig 编排构图，不是自由游玩瞬间（与「如实提交引擎渲染帧」不冲突——帧本身是真实渲染，构图是编排的）
- **Risk:** Low（确定性路径，无新机制）
- **Effort:** 1-1.5d（rig 扩展 + 剧本 JSON + 元数据）

### 4.2 Approach B — 真机输入剧本（纯 press/require 驱动真实游玩）

**描述：** 不用 rig 态注入，改由 e2e_capture.gd 的 press/require 能力在真实 Main.tscn 里「演剧本」：注入移动 → 触发 AI 攻击 → 玩家弹反 → … → 双死失败字幕，每帧靠 `require {node, prop, min}` 或 state 轮询对齐。

- **Pros:** 截图即真实游玩瞬间（用户裁决的就是实际手感画面）；顺带端到端验证战斗闭环本身
- **Cons:** **时序脆弱**——弹反/拼刀依赖帧窗口（PARRY_WINDOW_FRAMES≈12）与 AI 行为时序，不加全局 RNG seed + 确定性注入必 flaky（#555 教训：pierce 断言依赖未 seed 随机导致 CI 回归）；实现成本高（需新驱动编排层）；MVP 时间窗（2d estimate）风险大
- **Risk:** High（确定性缺口 + flaky 历史 + 调试成本）
- **Effort:** 2-3d（超 estimate）

### 4.3 Approach C — Movie Maker 模式录制 + 人工选帧

**描述：** 用 Godot 原生 `--write-movie out.png`（Movie Maker，输出 PNG 序列）录制一段实机游玩，人工/脚本从序列中挑 6 帧。

- **Pros:** Godot 原生能力（零自研）；可同时产出视频证据；最高保真（真渲染帧）
- **Cons:** 录制 = 需要真实输入源（人工或脚本宏），回放不确定性高；「人工选帧」与 issue 的自动化剧本精神冲突（AC1 要求剧本帧在 e2e_shots.json 中声明、管线自动产出）；Movie Maker 在 `--headless` 下同样无渲染（依赖 display driver），并未解决 headless 语义问题
- **Risk:** Med（不确定性 + 与 AC1 自动剧本契约冲突）
- **Effort:** 1-2d（但交付物形态不符）

### 4.4 开源调研结论（issue「开源优先」要求，供 implement PR 引用）

| 方案 | 结论 | 依据 |
|------|------|------|
| Godot `--headless` 截图 | ❌ 不可行 | Godot 4.x headless = dummy DisplayServer，无渲染管线；本项目 e2e_capture.gd 头注释已实证「必须 real rendering + display driver」 |
| Godot Movie Maker（`--write-movie`） | ⚠️ 备选 | 原生 PNG 序列输出；确定性录制需固定输入源；作为 §7 E3 实验对象 |
| GUT（bitwes/Gut） | ❌ 不引入 | 项目已有自定义 gdscript runner（tests/run_tests.gd + 15+ 个 test_*.gd，exit-code 契约）；迁移成本 > 收益，与「成熟方案优先复用」的评估结论相反——**自研 runner 已是成熟方案** |
| gdUnit4（godot-gdunit-labs/gdUnit4 ⭐1207） | ❌ 不引入 | 同上；且 GDScript 单测能力与现 runner 重叠 |
| 本项目 `run-e2e-review.sh` + `e2e_capture.gd` | ✅ 复用 | 已支持 1280x720 / press 注入 / deadline 兜底 / 4 重防假帧断言——本 PRD 的 6 帧剧本直接建于其上 |

### 4.5 推荐

**Approach A 为主，吸收 B 的 press 注入（MOVE 态）与 C 的 Movie Maker 作为 §7 实验对象。** 理由：
1. **确定性压倒一切**——E2E 是验收通道，flaky 管线会瘫痪裁决队列（#555 直接教训）；
2. **零组件改动**——clash/parry/execute 反馈链路全部已实现，rig 只加驱动态；
3. **headless 语义**——「headless 可运行」按「无人值守 + CI 等价（display driver/xvfb）+ 可选 --write-movie」三档落地，PR 中说明调研结果（issue 要求）；
4. **机械所有权**——rig/JSON/报告都是 mechanical；唯一 taste 环节（评星）留给用户，符合 issue 红线。

## 5. Boundary Conditions + Acceptance Criteria

### 5.1 正常路径（AC 映射，源自 issue body）

- [x] **AC1: 6 个剧本帧 + 文字契约** — `e2e_shots.json` 新增 `e2e_script` 组，6 帧（village_open / player_move / first_parry / clash / execute_closeup / fail_subtitle），每帧含 `scene_description`（场景描述）/ `trigger`（触发条件）/ `composition`（期望构图，文字）三字段
  - 验证：解析 JSON 断言 6 帧 × 3 字段非空；组内 shot 名与 §1.1 差距表一一对应
- [x] **AC2: headless 可运行 + 1280x720 PNG + JSON 元数据** — 管线在无用户交互环境跑通 6 帧；`results.json` 每帧含 name/saved/frame/state/trigger/composition
  - 验证：`--dry-run` 语法通过 + 实跑产出 6 PNG（1280x720）+ results.json 元数据齐全；headless 语义与 Movie Maker 调研结论写入 implement PR 说明
- [x] **AC3: 全量单测 + smoke 通过 + 测试报告** — `godot --path shandong-wolf/ --headless --script tests/run_tests.gd` 与 `smoke_test.gd` exit 0；报告（docs/TEST/ 或 PR 评论）汇总单测/smoke/E2E 三项结果
  - 验证：两项 exit code = 0；报告含通过/失败计数与 6 帧截图链接
- [x] **AC4: 用户裁决 ≥4 星平均** — 6 帧 + 实机手感交用户 1-5 星评分；平均 ≥4 通过，<4 打回对应视觉 issue（#582/#583/#579/#580/#574 等）
  - 验证：裁决表（帧 × 星数 × 意见）存档；本 PRD 不执行裁决（用户环节）
- [x] **AC5: 报告回填** — 裁决意见回填到对应 Issue 的 acceptance（如 #582 雪夜、#579 反馈、#580 处决）
  - 验证：回填后的 issue acceptance 含裁决结论与平均分

### 5.2 边界条件（edge cases，≥5）

1. **clash 双窗口同帧注入失败**（窗口错帧 → 无 clash 信号）：rig 应 fallback 到直接 `trigger_feedback("clash")` 构图（帧内容一致，来源不同），并在 results.json 标注驱动来源
2. **MOVE 态 press 注入与 auto_cycle 冲突**：press 注入期间禁 auto_cycle 切态（driver 现有 press 优先序）；位移断言（≥100px，参照 smoke I1）失败则该帧标记 missed 而非产出假帧
3. **失败字幕淡入时序**：FAIL_SUBTITLE 态 settle_frames 须 ≥ 字幕 Tween 淡入时长（#585 `_fade_in_fail_subtitle`），否则截到半透明字幕
4. **雪夜黑帧**：theme_color 断言（6e7684 口径，照 #582/#585）防「全黑 = 渲染失败」假通过
5. **headless 误用**：`--headless` 直接截图 = 空渲染；管线须显式选择 display driver，不得静默 fallback
6. **剧本组与既有组共存**：e2e_script 组 `match` 正则须与 assembly 组互斥（或明确优先级），避免一次 diff 命中两组重复截图

### 5.3 失败路径（≥3）

1. **截图黑屏/全白**：4 重防假帧断言（现有）拦截 → results.json reason=invalid → 管线 exit 1 → 报告标注该帧失败，不进入裁决队列
2. **裁决 <4 星**：报告记录每帧星数与意见 → 对应视觉 issue 打回重做（#582/#583/#579/#580/#574…）→ 重做后重跑 E2E 再裁决（循环上限不设——taste 不封顶，但每次重跑须附差异帧对比）
3. **管线超时/死锁**：max_wall_seconds 兜底（现有）+ shot 级 deadline_s 覆盖；任一帧 deadline 失败 → 整体 exit 1，报告标注原因（照 #555 flaky 排查先例定位）

## 6. Dependencies + Blockers

### 6.1 依赖

| 依赖 | 状态 | 风险 |
|------|------|------|
| #585 组装闭环（PR #666, b8ce226） | ✅ merged 2026-08-20 | 低——rig 驱动契约已实测 |
| #580 处决系统（#660） | ✅ merged | 低——execution rig 构图先例 |
| #579 打击反馈（#654） | ✅ merged | 低——clash/parry 反馈链路已实现 |
| #577 拼刀判定 | ✅ merged | 低——judge.clash 信号已接线 reaction |
| #584 调参候选值 | ⚠️ taste-draft 待用户定稿 | 中——本 issue 是其裁决通道；候选值未定稿不影响 6 帧构图（构图不依赖具体数值） |
| #582/#583 雪夜/舞台 | ✅ merged | 低——snow_night/battle_stage 组可复用构图 |
| 开源方案（GUT/gdUnit4/Movie Maker） | ✅ 调研完成 | 低——结论：不引入框架，复用现管线（§4.4） |

### 6.2 依赖链

```
#573-#584（16 组件，全部 merged）
    └──► #585 组装闭环（#666 merged）──► 本 issue #586 E2E 剧本 + 用户裁决
                                            └──► #584 数值定稿（消费裁决结果）
                                            └──► 打回通道：视觉 issue（#582/#583/#579/#580/#574…）
```

### 6.3 准备清单

- [x] origin/main 已含 #585 实现（b8ce226）——worktree 基线确认
- [x] clash 反馈链路确认（reaction_controller.gd 行 29/132-175）
- [x] press 注入能力确认（e2e_capture.gd 方向键/action 注入）
- [x] 开源调研完成（§4.4）
- [ ] implement 前：确认 #584 文案候选清单可随裁决流程一并提交（不阻塞）

## 7. Spike / Experiment（standard 深度——按 #585 先例含 3 个轻量实验）

### E1: clash 帧确定性捕获
- **问题:** 双攻击窗口同帧注入能否稳定产出 judge.clash 信号 → 火花构图帧？
- **方法:** rig 内同步 `request_transition("attack")` 双实体 → 监听 clash 信号 → 冻结效果帧截图；失败则 fallback `trigger_feedback("clash")`
- **预期:** 同帧注入路径成功率 ≥90%；fallback 路径 100%（构图一致）
- **影响:** 决定 ④ 拼刀帧的驱动实现与 results.json 驱动来源标注

### E2: MOVE 态 press 注入稳定性
- **问题:** e2e_capture.gd 方向键/action 注入在 rig 场景下能否稳定驱动玩家位移 ≥100px？
- **方法:** `{"action":"game_move_right"}` 注入 120 帧 → 位移断言（照 smoke I1 口径）
- **预期:** 位移达标率 100%（确定性场景）；若 <100px 则改用 rig 直接设位置 + 移动帧构图
- **影响:** 决定 ② 玩家移动帧走 press 注入还是 rig 构图

### E3: Movie Maker（--write-movie）保真与可复用性
- **问题:** Movie Maker PNG 序列与 rig 截图在 1280x720 下渲染一致性如何？能否作为 headless 语义的补充路径？
- **方法:** 同场景双跑（rig 截图 vs --write-movie 输出）→ 逐像素对比
- **预期:** 同帧渲染一致（同一引擎同一管线）；若成立，Movie Maker 作为「录制实机证据」备选写入管线文档
- **影响:** 决定 AC2 的 headless 落地形态（display driver / xvfb / movie 三档）与 PR 调研说明内容

## 8. Continuation Context

**系统状态（plan agent 接手时）：**
- 游戏可玩（#666 merged）：`main_battle.gd` 342 行编排器、4 态 assembly rig、smoke AC4 场景、test_main_assembly 745 行——全部在 origin/main（b8ce226），worktree 基线已同步
- E2E 管线成熟：`run-e2e-review.sh` + `resolve_plan.py` + `e2e_capture.gd`（1280x720 / press 注入 / deadline 兜底 / 4 重防假帧）
- 差距已定位：6 帧剧本契约（AC1）、MOVE/CLASH 两个缺失态、results.json 元数据、headless 语义、裁决/报告机制

**主要风险：**
1. clash 帧确定性（E1 实验前置）——fallback 已设计（trigger_feedback 注入），不阻塞
2. 真机 vs rig 构图差异——rig 注入帧是编排构图，用户若质疑「不是实战瞬间」，由 E2 实验证据 + 报告说明回应（帧为真实渲染，构图经编排）
3. 裁决 <4 星打回链条——需在报告模板中预设打回循环（差异帧对比），避免无限重跑

**下一步（plan agent → DESIGN 文档覆盖范围）：**
1. `e2e_shots.json` 新增 `e2e_script` 组 schema：6 帧 ×（name/state/scene_description/trigger/composition/settle_frames/theme_color），与既有组字段向后兼容
2. `e2e_main_assembly_capture.gd` 4→6 态扩展：MOVE（press 注入）、CLASH（judge 双窗口或 feedback 注入）、PARRY/EXECUTE 拆分；驱动契约（current_state 轮询 / auto_cycle / digit 键）保持不变
3. `framework/templates/e2e_capture.gd` results.json 元数据透传（trigger/composition）+ 可选 movie 模式分支
4. 测试报告模板（docs/TEST/586-*.md 或 PR 评论）：单测/smoke/E2E 三栏 + 6 帧图 + 裁决表（帧 × 1-5 星 × 意见）
5. 用户裁决工作流：6 帧提交用户 → 平均 ≥4 通过 / <4 打回 → 意见回填对应 issue acceptance（AC5）
6. implement PR 附开源调研说明（§4.4 表格）——issue「开源优先」的显式要求
7. E2E 剧本组接入 run-e2e-review.sh 的组选择机制（match 正则与 assembly 组互斥），确保回归时自动命中

**交接红线：** 本 issue 的 taste 环节只有用户评星；agent 产出 6 帧、管线、报告、打回建议，**不评星、不裁决文案、不替用户定稿**。打回目标 issue 清单：视觉类 #582/#583/#579/#580/#574（依 6 帧归属），数值类 #584。
