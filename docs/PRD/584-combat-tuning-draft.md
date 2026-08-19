# PRD #584 — [Taste] 战斗数值 DRAFT 集中表（手感候补值 + 一次性调参面板）

> **Issue:** #584
> **标签:** enhancement, gameplay, content, version/mvp, workflow/research
> **深度:** standard（GitHub 无 depth label；分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=13 标注 `depth: standard` → §1–6 + §8 必填；§7 含实验——调参面板方案需实证，参照 #572 先例）
> **Agent:** game-research-agent
> **日期:** 2026-08-19
> **所有权:** `content_ownership: taste-draft`（人机共做 v4：agent 生成带只狼 taste 方向的草稿，review 达标后 merge——PR 用 `parent #584` 不写 Closes——assign 用户定稿；规范见 game-to-issues references/taste-ownership-domains.md）
> **引擎/目录约束:** Godot 4.7.1 / `shandong-wolf/`（manifest `game.active: shandong-wolf` 单一事实源；本 PRD 全部路径前缀 `shandong-wolf/`）
> **数值基准:** 只狼体系（game-to-issues skill `references/sekiro-tuning-reference.md`，2026-08-19 用户拍板）——每个 DRAFT 值标注「只狼基准 → 本项目候选」，偏离写理由
> **研究选项:** Obsidian 知识库已搜索（`~/Documents/Obsidian Vault/`，wiki+raw grep 弹反/架势/格挡/调参/只狼/手感）+ 设计 brief（`docs/RAW/shandong-wolf-brief.md` §校准偏好）+ #572 已落地骨架源码审计（Patch 16 实施）+ 开源插件调研（GitHub API 检索 4 组关键词，见 §4.2）
> **来源:** backlog-promotion（`docs/RAW/game-to-issues-shandong-wolf.json`，id=13，estimate 2d，priority medium，milestone mvp）
> **前置依赖:** #572（CLOSED/status/done，#599 merged）— constants.gd 5 个 # DRAFT 分区骨架 + 候补占位已落地，本 issue 负责**定稿候选值 + 调参面板**

---

## 1. 问题定义

### 1.1 现状（#572 落地后 constants.gd 占位值 vs 只狼基准差距，2026-08-19 源码审计）

| 参数（constants.gd 现有 const） | #572 占位值 | 只狼基准 | Issue #584 候选范围 | 差距判定 |
|---|---|---|---|---|
| `PARRY_WINDOW_FRAMES` | 12 | ~12 帧（0.2s @60fps） | [8, 10, 12, 14] | ✅ 同量级，但缺候选集与出处标注 |
| `POSTURE_RECOVERY_PER_SEC` | 0.8/s | 20-35/s（脱战 1.5s 延迟后回复） | 20-35/s | ❌ 差 1.5 个数量级——占位拍脑袋，必须重写 |
| `POSTURE_BLOCK_COST` | 10.0 | 中（8-12/次） | 8-12 | ⚠️ 数值接近但无出处标注 |
| `POSTURE_BREAK_THRESHOLD` | 100.0 | = 当前 HP 上限（100） | 100（= LIFE_1_MAX） | ✅ 符合只狼铁律，需联动约束（§5.2-7） |
| `LIFE_1_MAX` | 100.0 | 100% | 100 | ✅ 一致 |
| `LIFE_2_MAX_RATIO` | 0.5 | 回生后约半血 | 40-60（绝对血量） | ⚠️ 只狼为「回生后约半血」，本项目候选 40-60 |
| `SWORD_DAMAGE_LIGHT` | 10.0 | 轻击连段 | 10-15 | ✅ 范围内 |
| `SWORD_DAMAGE_HEAVY` | 25.0 | 重击 | 25-40 | ⚠️ 处于候选下限，需候选集 |
| `SWORD_DAMAGE_EXECUTE` | 999.0 | 忍杀 = 一击必杀 | 处决 = 无视架势 | ✅ 机械语义正确 |

**核心缺口 1 — 数值无出处：** #572 骨架按「禁止实现期顺手定稿」落地了占位值，但占位值本身拍脑袋（最明显：架势回复 0.8/s 与只狼基准 20-35/s 差 25-43 倍），且**没有「只狼基准 → 本项目候选」双栏标注**、没有候选集、没有偏离理由。后续 #575（战斗实体）/#577（拼刀判定）若直接消费这些占位值，手感基调在实现期被锁死——补救成本远高于现在定稿。

**核心缺口 2 — 无调参手段：** 项目无任何运行中调参工具。constants.gd 是 `const` 静态值（#572 DESIGN 方案 A：preload 静态访问），改一个参数 = 改代码重编译 + 重启 + 目测。issue 要求 F1 DebugCanvas 调参面板（≥10 参数热更新 + 候选对比导出），把「3 组候选对比手感差异」从「改代码重启 N 次」降为「运行中滑杆切换」。

**核心缺口 3 — 缺失参数：** issue body 要求的**受击扣架势（30-40）、弹反扣架势（0-2）、敌人攻击前摇（12-18 帧）、处决触发距离（1.2m）、慢动作系数、架势回复延迟（1.5s）** 在 #572 骨架中不存在——需新增分区/常量。

### 1.2 验收条件（源自 Issue #584 body，映射到各阶段 agent）

| # | 验收条件 | 负责阶段 | 本 PRD 的保障措施 |
|---|---------|---------|------------------|
| AC1 | constants.gd 内含完整 # DRAFT 数值表，每项标注「只狼基准 → 本项目候选」或偏离理由，禁止无出处数值 | implement | §4.1 方案 A 统一三行注释格式 + §5.1 AC1 逐项核查断言 |
| AC2 | F1 调参面板运行时可修改 ≥10 个核心参数并实时生效 | implement | §4.2/4.3：程序化 Control 面板 + override dict 热更新链路；参数清单 14 项（§4.3） |
| AC3 | 调参面板仅 debug build 可见，release 不编译 | implement | §4.4 方案 A：`OS.is_debug_build()` 判定 + 条件实例化；test_debug_canvas.gd 断言 release 路径不建节点 |
| AC4 | PR 中附调参对比说明（至少 3 组候选对比手感差异） | implement | §4.5 方案 C：JSON dump + E2E 截图双证据；3 组对比（基准/宽容/严苛）见 §4.5 |
| AC5 | 最终数值由用户 E2E 实机裁决后从 # DRAFT 转为正式值 | 用户（队列） | taste-draft 生命周期：草稿 merge（不 Closes）→ assign 用户 → 用户定稿 commit → close（§2.3） |

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 用户实机裁决数值 | 定稿时 1 次+ | 用户打开游戏，F1 调参面板切换候选值，实机打一场，从「弹反容错 / 架势节奏 / 两条命紧张感」裁决每项定稿值 |
| B | 实现期手感自检 | 每次调参 | #575/#577 实现 agent 用面板在 debug 下快速试「太简单 / 太难」两端，代替改代码重启 |
| C | 后续 feature issue 消费 | 每次 impl PR | #573-578 直接读 constants.gd DRAFT 值（`const C = preload(...)` → `C.NAME`），无需理解出处 |

### 1.4 范围边界（与既有 PRD / 后续 issue 去冲突，Patch 14）

| PRD / Issue | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----------|---------|------------------|
| #572（scaffold，CLOSED） | constants.gd 分区**骨架** + 机械常量 + 占位值 | ❌ 不重写分区结构/消费模式；只**定稿候选值** + 新增缺失分区 |
| #575（战斗实体基类与状态机，backlog） | 战斗实体**具体**状态机 | ❌ 不设计任何战斗状态；调参面板只调 constants 数值，不编排战斗逻辑 |
| #577（拼刀判定，backlog） | 弹反/格挡/识破的**判定逻辑** | ❌ 不实现判定；只提供判定要消费的 DRAFT 数值（弹反窗口/格挡代价/危攻击前摇） |
| #367（mini-pong A1 手感定稿，closed） | mini-pong 11 参数定稿 + TASTE.md 档案格式 | ❌ 不复制 mini-pong 数值；其 TASTE.md「候补值表 + 试玩剧本 + 定稿差异记录」三件套格式为**模式参考**（§8 建议 shandong-wolf TASTE.md 按此建档） |
| 战斗**玩法设计**（机制/招式/敌人设计） | 机制层 | ❌ 本 issue 只做**数值层** DRAFT 表 + 调参面板，机制设计归 brief/GDD |

### 1.5 预期行为（最小语义）

1. `shandong-wolf/gdscripts/constants.gd`：5 个既有分区全部改为「只狼基准 → 本项目候选」双栏标注 + 候选集 + 偏离理由；新增「受击 / 敌人 / 处决」分区（受击扣架势 30-40、弹反扣架势 0-2、敌人攻击前摇 12-18 帧、处决触发距离 1.2m、慢动作系数、架势回复延迟 1.5s）。
2. `shandong-wolf/gdscripts/debug_canvas.gd`（新）：纯 Control 节点程序化构建的调参面板（StyleBox 空白背景 + 写字板字体，零 UI 图片），F1 物理键 toggle，仅 debug build 实例化。
3. 热更新链路：面板改值 → 运行时 override dict → 消费方读值函数（debug 返回 override，release 回落 const 默认）——向后兼容 #572 的 const 消费模式。
4. 候选对比导出：面板内一键 dump 当前参数 JSON + 复用 e2e 截图管线，产出 ≥3 组候选对比证据（AC4）。
5. 三入口测试全绿 + 新增断言（每项有出处标注 / 候选集非空 / 无定稿标记 / release 不实例化）。

### 1.6 Obsidian 知识检索

- **Vault 直接读取成功**（`~/Documents/Obsidian Vault/`，wiki + raw 全量 grep：`弹反|架势|格挡|调参|只狼|手感`）。
- **命中笔记：**
  - **《JRPG 战斗系统研究 - 最终综合报告》**（raw/Bear/）：*「弹反/闪避 = 时机判定（动作游戏）」*；FF16 **Stagger 系统 = 破防增伤**；难度分层 *「基础：简单动作系统 → 进阶：连招/弹反/闪避 → 策略：属性/状态」* → 佐证 DRAFT 值围绕**时机窗口（弹反/前摇）、资源节奏（架势回复/受击）、血量结构（两条命）** 三轴组织，与只狼基准表结构吻合（§4.1 分区依据）。
  - **《游戏设计理念.md》**（wiki/）：*「《艾迪芬奇的记忆》和《只狼》……机制都做得克制，我游玩之后的情绪都很强烈」* → **只狼基准的审美坐标证据**：克制 = 参数少而精、每项可感知；情绪强烈 = 弹反成功 / 架势崩解 / 回生必须制造情绪峰值（§2.1 情感断言依据）。
  - **《CUSGA 2026 游戏评选笔记》**：*「设计简洁有新意」* → 调参面板克制原则：只暴露 14 个核心参数，不堆通用 debug 工具（§4.2 范围）。
- **Vault 无 shandong-wolf 专属战斗数值笔记**（命中均为通用原则/其他项目）→ 数值权威源 = 只狼基准表 + brief §校准偏好 + issue body 候选值。

---

## 2. 设计意图

### 2.1 现状为何存在

| Issue/文档 | 贡献 | 留下的缺口 |
|-----------|------|-----------|
| #572（scaffold，#599 merged） | constants.gd 骨架 + 5 分区 + 占位值 + test_constants.gd「防误定稿」守卫 | 占位值拍脑袋（无只狼出处）、无候选集、缺 6 个 issue 要求参数 |
| brief §校准偏好 | 定「A1 数值手感 → 用户定稿」、草稿规范（constants.gd + # DRAFT + 候补值） | 未给具体候选值——正是本 issue 的填充物 |
| sekiro-tuning-reference.md（2026-08-19 用户拍板） | 权威数值基准（弹反 12 帧 / 架势上限=HP / 回复 20-35/s / 两条命 / 轻重击 / 前摇 12-18 帧） | 是「机制骨架 + 数量级」参考，需落到本项目 constants.gd 候选值 |

### 2.2 为什么现在做

#572 刚交付数值集中地（2026-08-19 #599 merged），#575/#577 尚未开始实现——**这是填充 DRAFT 候选值、建立调参基础设施的唯一低成本窗口**。若错过：下一批 feature issue 直接消费拍脑袋占位值 → 手感基调锁死 → 定稿成本放大数倍（改 const = 改消费方 + 回归测试）。

### 2.3 品味裁决模型（taste-draft 队列，v4）

本 issue 是 A1「数值即表达」领域（T1✅ T2✅ T3✅ 全通过 = 人机共做）。执行 v4 队列模式：

```
1. 本 research PRD → 2. plan DESIGN → 3. implement 生成带只狼 taste 方向的草稿
   （constants.gd 全量 DRAFT 候选值 + DebugCanvas 调参面板）
4. review 定稿就绪检查（结构完整 + 只狼方向对齐：对照 sekiro-tuning-reference.md 逐项比对）
   → 达标 → 草稿 PR merge 进 main（PR body: parent #584，不写 Closes）
5. assignee=用户 + label=status/human-review（issue 保持 open）
6. 用户实机裁决（F1 面板 + E2E 截图）→ 微调 → push 定稿 → close #584
7. 定稿差异记录进 docs/TASTE.md（shandong-wolf 建档，mini-pong 三件套格式）
```

**红线（taste-draft）：** implement 阶段**禁止**把 DRAFT 候选值「顺手定稿」（无用户裁决）；AC1 的「定稿」= 候选值完整 + 出处标注完整，不等于用户定稿。

### 2.4 既有约束（#572 消费模式，不可破坏）

| 约束 | 详情 | 本 PRD 的应对 |
|------|------|--------------|
| const 静态消费 | `const C = preload("res://gdscripts/constants.gd")` → `C.PARRY_WINDOW_FRAMES` | const 保留为**默认值**；热更新走 override dict（§4.3 方案 A），release 零开销 |
| test_constants.gd 防误定稿守卫 | 断言 5 分区存在 + 无定稿标记 | 扩展断言：每项有「只狼基准→候选」标注 + 候选集非空（§5.1 AC1） |
| 零外部美术资产 | 无 UI 图片（issue body 画面实现路径） | 面板纯 StyleBox + 写字板字体（§4.2 方案 A） |
| 三入口测试全绿 | compile / smoke / run | 新增脚本自动纳入 check_compile；run_tests.gd 挂载 test_constants / test_debug_canvas |

---

## 3. 影响分析

### 3.1 直接影响的文件

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `shandong-wolf/gdscripts/constants.gd` | 数值单一事实源 | 改：5 分区候选值定稿标注 + 新增分区（受击/敌人/处决） |
| `shandong-wolf/gdscripts/debug_canvas.gd` | 调参面板（新） | 新：F1 toggle + 参数表驱动 UI + override dict + JSON dump |
| `shandong-wolf/tests/test_constants.gd` | 数值守卫 | 改：加出处标注 / 候选集断言 |
| `shandong-wolf/tests/test_debug_canvas.gd` | 面板守卫（新） | 新：release 不实例化断言 + override 回落断言 + 参数名一致性自检 |
| `shandong-wolf/tests/run_tests.gd` | 测试挂载 | 改：挂载 test_debug_canvas.gd |

### 3.2 新建文件

| 文件 | 用途 |
|------|------|
| `shandong-wolf/gdscripts/debug_canvas.gd` | 调参面板（纯代码构建，零 tscn 零图片） |
| `shandong-wolf/tests/test_debug_canvas.gd` | 面板守卫单测 |

### 3.3 间接影响

| 模块 | 影响 | 说明 |
|------|------|------|
| #575 战斗实体 / #577 拼刀判定 | 消费方 | 读值走 `C.NAME`（默认）或 tuning override——读值约定见 §8 |
| `shandong-wolf/project.godot` | 无改动 | F1 用 `_unhandled_input` 物理键检测，不占 InputMap（避免与未来按键冲突） |
| E2E 截图管线（e2e_shots.json） | 证据链 | 面板可被 E2E 截图捕获（截图前强制面板隐藏，保证确定性） |

### 3.4 数据流影响

```
用户按 F1（debug build）
    │
    ▼
DebugCanvas._unhandled_input  →  面板 toggle（CanvasLayer 显示/隐藏）
    │
    ▼
面板 UI（14 个 HSlider/SpinBox，StyleBox 白底 + 写字板字体）
    │  修改值
    ▼
DebugCanvas.override_values: Dictionary（参数名 → 候选值）
    │
    ├──► 消费方（#575/#577 实体）: Tuning.get_value("PARRY_WINDOW_FRAMES", C.PARRY_WINDOW_FRAMES)
    │        ├── debug: 返回 override（实时生效）  ← 热更新链路
    │        └── release: 回落 const 默认（零开销）
    │
    └──► 导出按钮: dump 当前参数 JSON 到 user://tuning_dump_<ts>.json
              └──► E2E 截图（e2e_shots.json）→ 3 组候选对比证据（AC4）
```

### 3.5 文档更新清单

- [x] `docs/PRD/584-combat-tuning-draft.md`（本文件）
- [ ] `docs/TASTE.md`：shandong-wolf 建档（候补值表三件套）——implement/review 阶段更新草稿、用户定稿后记录差异
- [ ] `docs/RAW/shandong-wolf-brief.md`：如需回填基准出处链接（可选）

---

## 4. 方案对比

### 4.1 DRAFT 值组织与标注格式

**方案 A：内联 const + 三行注释（推荐）**
- 每个候选值 = `const NAME: TYPE = 默认候选` + 上方三行注释：`只狼基准:` / `候选集:` / `偏离理由:`（无偏离写「与只狼一致」）
- 消费方零改动（`C.NAME` 照旧），候选集写在注释里供实现/用户参考

```
# PARRY_WINDOW_FRAMES
#   只狼基准: ~12 帧（0.2s @60fps，偏宽松=容错手感来源）
#   候选集: [8, 10, 12, 14]（默认 12 = 只狼基准）
#   偏离理由: 无——只狼基准直接采纳；8/14 为容错两极备选
const PARRY_WINDOW_FRAMES: int = 12   # # DRAFT
```

- Pros: 与 #572 消费模式完全兼容；出处可读；diff 可审查
- Cons: 注释占行多（14 参数 × 4 行 ≈ 60 行）
- Risk: Low；Effort: 0.5-1d

**方案 B：外部 JSON 配置 + 运行时加载**
- Pros: 数值与代码分离、可热加载
- Cons: 破坏 const 静态访问模式（#572 消费约定作废）；实现期多一层 IO/校验
- Risk: Med；Effort: 1-2d
- **否决理由:** 与 #572 DESIGN 方案 A（RefCounted + preload const）直接冲突，骨架期过度设计。

**方案 C：enum + Dictionary 集中表**
- Pros: 元数据（候选集/出处）可程序化读取，面板可自动生成
- Cons: 改变消费语法（`C.TUNING[PARRY]`），且 GDScript 无 enum→const 双向映射，复杂度不降
- Risk: Med；Effort: 1d
- **否决理由:** 收益（面板自动生成）可由 §4.2 方案 A 的面板内显式参数表实现，不必改数据组织。

**推荐：方案 A。** 出处与候选集直接长在代码里（taste 草稿的可审查性 > 运行时灵活性）。

### 4.2 调参面板实现（开源调研结论）

**开源调研（2026-08-19，GitHub API 检索 4 组关键词）：**

| 仓库 | ⭐ | 能力 | 结论 |
|------|----|------|------|
| godot-extended-libraries/godot-debug-menu | 670 | FPS/性能/硬件指标显示 | ❌ 只读监控，无参数修改能力 |
| awfullycrispy/GodotDebugMenu | 1 | 基础变量修改菜单 | ⚠️ 功能接近但 1⭐ 未维护、无发布版、Godot 4.x 兼容性无保证 |
| godot "tunable parameters" 检索 | — | 无成熟候选 | ❌ 生态空白 |
| monitor_overlay / debug_draw_3d 等 | 237-1046 | 调试绘制/监控叠加 | ❌ 均为显示类，非调参 |

**结论：无成熟的开源运行中调参面板插件 → 自研最小实现**（issue body 的「🔍 开源优先」要求已尽调，找不到再自行实现，PR 中附本表）。

**方案 A：纯 Control 节点程序化自研（推荐）**
- `DebugCanvas`（Node2D）→ CanvasLayer → PanelContainer（StyleBoxFlat 白底 80% 透明度）+ VBoxContainer + 14 行 HSlider/SpinBox + Label（参数名/当前值/候选集）
- 写字板字体：Godot 4.7 默认字体含 CJK（#562 已验证）；如需要「写字板感」用 SystemFont 指定系统字体候选——**不引入图片资产**
- 参数表驱动：`const PARAMS: Array[Dictionary]`（name/range/step/候选集）→ 面板循环生成 UI，杜绝手写 14 份样板
- 面板打开时游戏不暂停（实时感受变化）；F1 再按隐藏
- Pros: 零依赖零资产；完全受控；符合 issue 画面实现路径
- Cons: 自研约 200-300 行
- Risk: Low；Effort: 1-2d

**方案 B：fork awfullycrispy/GodotDebugMenu**
- Pros: 少写代码
- Cons: 1⭐ 无维护、API 未验证、仍需改造（参数表驱动/导出对比都不具备）
- Risk: Med-High；Effort: 2-3d（改造量 ≥ 自研）
- **否决理由:** 改造量不低于自研，且引入外部不稳定依赖。

**推荐：方案 A**（自研纯 Control 面板）。

### 4.3 运行中热更新机制

**方案 A：override dict + 读值函数（推荐）**
- `DebugCanvas.override_values: Dictionary`（参数名 → 值）
- 消费方统一走 `Tuning.get_value(param_name, default)`（静态函数或 Game autoload 方法）：
  - debug + override 存在 → 返回 override
  - 否则 → 返回 `C.NAME` 默认
- 未来 #575/#577 消费方一行接入：`var window := Tuning.get_value("PARRY_WINDOW_FRAMES", C.PARRY_WINDOW_FRAMES)`
- Pros: 向后兼容 const 模式；release 路径零分支开销（函数内 `if not OS.is_debug_build(): return default`）；面板无需碰消费方
- Cons: 消费方要从 `C.NAME` 改为 `Tuning.get_value(...)`（约定 + 少量 diff）
- Risk: Low；Effort: 1d

**方案 B：运行时改写 const（不可行）**
- GDScript const 编译期绑定，运行中不可写
- **否决理由:** 语言层面不可能。

**方案 C：全局单例可变属性（Game autoload 暴露每个参数）**
- Pros: 类型安全
- Cons: 14 个属性样板代码；面板/消费方耦合 autoload 生命周期；未来加参数要改两处
- Risk: Med；Effort: 1d
- **否决理由:** Dictionary 方案的灵活性足够，样板更少。

**推荐：方案 A。**

### 4.4 Debug-only 可见性

**方案 A：`OS.is_debug_build()` 运行时判定（推荐）**
- `DebugCanvas` 脚本顶层：`if not OS.is_debug_build(): return`（不实例化任何节点）
- 面板节点由 Main 场景或 Game autoload 条件 `add_child`（debug 才创建）
- 导出 release 模板时 Godot 自动裁剪不可达路径（GDScript 无预编译宏，靠运行时判定；「release 不编译」的语义 = release 包内不创建节点、不处理 F1）
- Pros: 单一判定点；模板导出无需额外配置
- Cons: 代码仍在包里（仅不执行）——issue AC3「release 不编译」按「不实例化」解释（GDScript 无宏，这是语言现实）
- Risk: Low；Effort: 0.5d

**方案 B：导出预设 + 特性标签（custom build）**
- 维护 debug/release 两套导出预设，release 排除 debug_canvas.gd
- Pros: 字节级裁剪
- Cons: 项目尚无导出预设体系；CI 无 release 构建任务；过度工程
- Risk: Med；Effort: 1-2d

**推荐：方案 A**（+ test_debug_canvas.gd 断言 release 判定路径不实例化）。

### 4.5 候选对比证据（AC4）

**方案 A：JSON dump 仅**
- 面板按钮导出 `user://tuning_dump_<ts>.json`（全部 14 参数当前值）
- Pros: 简单
- Cons: 无画面证据，「手感差异」说不清

**方案 B：E2E 截图仅**
- 复用 e2e_shots.json 管线截面板 + 战斗画面
- Pros: 视觉证据
- Cons: 数值本身不可读

**方案 C：JSON dump + E2E 截图（推荐）**
- 调参对比说明 = 每候选组：JSON 参数快照 + 对应战斗画面截图 + 手感描述（弹反容错 / 架势节奏 / 紧张感）
- 至少 3 组：**基准组**（全默认 = 只狼基准）/ **宽容组**（弹反 14 + 回复 35 + 受击 30）/ **严苛组**（弹反 8 + 回复 20 + 受击 40）
- Pros: 数值 + 画面双证据，用户裁决成本最低
- Cons: E2E 截图需先有可打斗场景（#575/#577 前用静态演练场景替代，见 §5.3-4）
- Risk: Med；Effort: 1d

**推荐：方案 C。**

### 4.6 推荐汇总

| 子系统 | 推荐 | 核心文件 |
|--------|------|---------|
| DRAFT 值组织 | A: 内联 const + 三行注释 | `constants.gd` |
| 调参面板 | A: 纯 Control 程序化自研 | `debug_canvas.gd` |
| 热更新 | A: override dict + 读值函数 | `debug_canvas.gd` + 消费方约定 |
| Debug-only | A: `OS.is_debug_build()` 判定 | `debug_canvas.gd` |
| 对比证据 | C: JSON dump + E2E 截图 | 面板导出 + e2e 管线 |

---

## 5. 边界条件与验收

### 5.1 验收条件（映射 issue body）

- [x] **AC1: DRAFT 数值表完整且带出处** — constants.gd 全量 # DRAFT 值每项含「只狼基准 → 本项目候选」双栏标注；候选集非空；偏离只狼处有理由；禁止无出处数值
  - 验证：test_constants.gd 新增断言（每项注释含「只狼基准」或「偏离」+ 候选集含 ≥2 值）+ 人工 review diff
- [x] **AC2: F1 面板 ≥10 参数热更新** — 14 个核心参数（弹反窗口/架势回复/回复延迟/格挡扣架势/弹反扣架势/受击扣架势/架势上限/第一条命/回生血量/轻击/重击/敌人前摇/处决距离/慢动作系数）运行中可改并实时生效
  - 验证：debug 下 F1 开面板 → 改弹反窗口 → 消费方读值函数返回新值（test_debug_canvas.gd 模拟消费方断言）
- [x] **AC3: 仅 debug build 可见** — release 模板运行不创建面板节点、F1 无响应
  - 验证：test_debug_canvas.gd 断言 `OS.is_debug_build()==false` 路径不实例化（headless 测试）
- [x] **AC4: 调参对比说明 ≥3 组** — PR 附 3 组候选对比（基准/宽容/严苛）+ JSON dump + 截图/手感描述
  - 验证：PR 描述包含对比表（§4.5 方案 C 产物）
- [x] **AC5: 用户实机裁决后转正式值** — 草稿 merge 后 assign 用户 + status/human-review；用户裁决后 DRAFT 标记移除、TASTE.md 记录差异、close
  - 验证：issue 生命周期（assignee/label/close 事件）

### 5.2 边界情况

1. **F1 与未来战斗按键冲突**：F1 不在 InputMap 登记，走 `_unhandled_input` 物理键直判；若未来战斗用 F1，改 InputMap 动作 `toggle_debug_canvas`（集中改名点）
2. **参数越界**：弹反窗口 < 1 帧（判定不可能命中）/ > 60 帧（无脑弹反）；面板 SpinBox 硬性 range 约束（min/max/step），越界值拒绝写入 override
3. **面板打开时游戏状态**：面板不暂停游戏（实时手感），但**处决演出/慢动作（Engine.time_scale）期间**面板值修改应延迟到 time_scale 恢复后生效（或改值时同时重置 time_scale）——避免调参中途时间轴错乱
4. **E2E 截图时面板遮挡**：截图脚本在面板隐藏态执行；面板可见性由 F1 状态决定，E2E 前强制 `visible=false`（确定性）
5. **慢动作系数 = 0**：`Engine.time_scale=0` 会冻结游戏（含面板输入）；实现期 clamp 下限 0.1
6. **override 残留**：面板改值后未导出直接退出 → override 不持久化（user:// 只存 dump 不自动加载）；如需持久化，显式「加载上次 dump」按钮（v2 可选，MVP 不做）
7. **两条命联动**：架势上限 = 当前 HP 上限（只狼铁律）——面板改 LIFE_1_MAX 时 POSTURE_BREAK_THRESHOLD 须联动（实现期在 Tuning.get_value 内做派生规则或面板 UI 标注联动关系）

### 5.3 失败路径

1. **OS.is_debug_build() 误判**（如 CI headless 也返回 true）→ 面板在 CI 截图乱入：test 断言 + e2e 前置强制隐藏兜底
2. **override dict 参数名拼写错误** → 读值函数返回默认值（静默回落）；test_debug_canvas.gd 断言全部 14 个参数名与 constants 中 const 名一致（启动自检）
3. **面板 UI 超出 1280x720**（14 行控件）→ VBoxContainer + ScrollContainer 包裹；行高紧凑（28px），全高 ≈ 400px 可容纳
4. **#575/#577 未实现导致无战斗画面可截** → 对比证据先用**演练场景**（测试用假人战斗/数值棋盘展示，见 §7 实验 2）；AC4 的截图在战斗可用后补拍

---

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 |
|------|------|------|
| #572（scaffold 骨架，#599 merged） | ✅ CLOSED | 无——constants.gd 分区/消费模式已落地，本 issue 在其上定稿 |
| 只狼基准表（sekiro-tuning-reference.md） | ✅ 存在（skill references） | 低——权威基准，2026-08-19 用户拍板 |
| e2e 截图管线（e2e_shots.json） | ✅ 存在（#559 打通） | 低——面板截图复用现有机制 |
| #575/#577（战斗实体/拼刀判定） | ⏳ backlog | 中——消费方未实现，面板「实时生效」先用读值函数 + 测试验证，战斗内生效待消费方落地 |

### 6.2 依赖链

```
#572 骨架（CLOSED，#599 merged）
   │  constants.gd 分区 + 消费模式
   ▼
#584 本 issue：DRAFT 候选值定稿 + DebugCanvas 调参面板
   │
   ├──► #573-#578（feature issue，消费定稿数值）
   └──► #575（战斗实体状态机）/ #577（拼刀判定）← 读 Tuning.get_value(...)
```

### 6.3 准备清单

- [x] 只狼基准表读取（本 PRD §1.1 差距表）
- [x] 开源插件尽调（§4.2）
- [x] Obsidian 知识检索（§1.6）
- [ ] implement 阶段：确认 #572 的 test_constants.gd 现有断言，扩展不破坏

---

## 7. Spike / 实验

> depth/standard 下 §7 可选；本 issue 的调参面板方案含 3 个未验证假设，参照 #572 先例纳入实验（implement 期首个任务执行）。

### 实验 1：F1 物理键 + debug 判定在 Godot 4.7 的行为

- **问题**：`_unhandled_input` 捕获物理 F1 在窗口聚焦/无焦点时是否可靠；`OS.is_debug_build()` 在 `--headless` 测试与导出 release 模板下的返回值
- **方法**：最小脚本打印 `OS.is_debug_build()` + F1 keycode；headless 跑一次 + GUI 跑一次；导出 release 模板验证
- **预期结果**：debug 返回 true；F1 物理键在 `_unhandled_input` 稳定捕获；导出 release 后判定为 false → 方案 4.4-A 可行
- **对方案影响**：若 F1 捕获不可靠 → 改 InputMap 动作 + 快捷键绑定（集中改名点不变）

### 实验 2：纯 Control 面板布局在 1280x720 的可行性

- **问题**：14 行 HSlider/SpinBox + Label 在 1280x720、stretch `canvas_items` 下的可读性与布局稳定性
- **方法**：程序化构建 VBoxContainer + ScrollContainer 原型，截图验证；检查 StyleBoxFlat 半透明白底 + 默认字体的 CJK 渲染
- **预期结果**：全高 ≤ 400px 可容纳；CJK 正常；无图片资产
- **对方案影响**：若字体观感不达标 → SystemFont 指定「写字板」风格系统字体（仍零图片资产）

### 实验 3：override dict 热更新链路端到端验证

- **问题**：`Tuning.get_value()` 在 debug 下返回 override、release 回落 const 的链路是否真实生效（消费方读取时机）
- **方法**：构造假消费方（测试脚本）每帧读取 `PARRY_WINDOW_FRAMES`，面板改值后断言下一帧读值变化；模拟 release（强制走回落分支）断言返回 const
- **预期结果**：热更新即时生效；回落分支无异常；14 个参数名与 constants 一致性自检通过
- **对方案影响**：若消费方读值时机有缓存 → 读值函数禁止缓存，每次实时查 dict

---

## 8. 延续上下文（给 plan agent）

### 系统状态
- `shandong-wolf/gdscripts/constants.gd`：#572 已落地 5 分区 + 机械常量（占位值拍脑袋，无出处标注）；`state_machine.gd`/`game.gd`（Game autoload）已就绪；三入口测试绿（#599 merged）
- 消费约定（#572 DESIGN §2.1）：`const C = preload("res://gdscripts/constants.gd")` → `C.NAME`
- E2E 管线：#559 打通，e2e_shots.json 可扩展面板截图

### 下一步（plan agent 清单）
1. DESIGN 须明确：constants.gd 全量 DRAFT 值表（§4.1-A 格式，14+ 参数，含 §1.1 差距表全部修正）+ DebugCanvas 面板结构（§4.2-A）+ 读值函数签名 `Tuning.get_value(name, default)` 及消费方迁移约定（§4.3-A）
2. 新增参数清单（#572 缺失）：`POSTURE_HIT_COST` 30-40、`PARRY_COST` 0-2、`POSTURE_RECOVERY_DELAY` 1.5s、`ENEMY_ATTACK_WINDUP` 12-18 帧、`EXECUTE_RANGE` 1.2m、`SLOWMO_COEFF` 0.1-0.3、`LIFE_2_ABS` 40-60（绝对血量，替代/并存 LIFE_2_MAX_RATIO）
3. 面板参数表（14 项）驱动 UI；F1 走 `_unhandled_input`；`OS.is_debug_build()` 判定
4. test_constants.gd 扩展（出处标注/候选集断言）+ 新增 test_debug_canvas.gd（release 不实例化/回落断言/参数名一致性）
5. 对比证据：3 组候选（基准/宽容/严苛）JSON dump + E2E 截图；战斗场景未就绪前用演练场景替代（§5.3-4）
6. 红线：**禁止 implement 期把 DRAFT 值「顺手定稿」**（taste-draft v4）；PR body `parent #584` 不写 Closes；merge 后 assign 用户 + status/human-review

### 主要风险
- 消费方迁移（`C.NAME` → `Tuning.get_value()`）在 #575/#577 实现前是「约定」——DESIGN 要给出最小迁移示例代码，避免后续 agent 理解偏差
- E2E 截图在无战斗场景时的替代证据（演练场景）需在 DESIGN 明确范围，防止 implement 期跑偏去搭战斗 demo
