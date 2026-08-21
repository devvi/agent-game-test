# PRD #684 — [Feature] 敌人 Boss 血条 UI（只狼式顶部血条 + 架势条组合）

> **Issue:** #684
> **标签:** workflow/research, priority/high, feature, ui, version/mvp（issue 无 `depth/*` 标签，参照 #682 先例取 `depth: standard` → §1–6 + §8 必填；§7 含 2 实验提升交接质量）
> **Agent:** game-research-agent
> **日期:** 2026-08-21
> **所有权:** `content_ownership: mechanical`（UI 结构/布局锚点/信号接线/分档 API = 机械工程；敌人名字文案、闪白/碎裂的色值与时长候选 = taste 通道，全部标 `# DRAFT` 只读，定稿归 #584/#576 human-review 通道）
> **引擎/目录约束:** Godot 4.7.1 / `shandong-wolf/`（manifest `game.active: shandong-wolf` + `default_branch: main` 单一事实源；本 PRD 全部路径前缀 `shandong-wolf/`，零 `mini-pong/` 写死）
> **研究选项:** Obsidian 知识库（`~/Documents/Obsidian Vault/`）→ `wiki/游戏设计理念.md` §UI 与交互设计（UI = 玩家最常看见的互动、最值得发力的点；引自 `raw/Bear/关于游戏UI的思考.md`：拟物 vs 抽象两方向）、`wiki/体验引擎-patterns.md` §1 隐形界面（最小化 HUD、「如果界面被注意到，它就失败了」——#576 同源引用）+ sekiro 调参基准（`agents/skills/game-to-issues/references/sekiro-tuning-reference.md`：「架势崩解必须惩罚清晰：失衡硬直 2-3s + **白闪**」「处决是奖励不是补刀」「Boss（汉奸）多管架势 2 阶段 × 架势 180-240（v1）」——AC3 闪白直接依据）+ 同链 PRD/DESIGN 全读（#576/#580/#582/#584/#682）+ origin/main 源码实测（2180765，hud.gd 444 行逐函数核对）
> **来源:** 用户拍板（2026-08-21）：敌人需血条/架势条设计，从 #682 补充时拆分——「UI 结构 agent 全权，视觉色值归 taste 通道」
> **前置依赖:** #682（CLOSED，PR #695 merged 2026-08-21）——敌人 HP/架势数据与 EnemyHealthBar 基底已交付；#576（草稿 merged，`status/human-review` 等用户定稿——v4 规则：human Issue 不进依赖链，视为已满足）；#580（CLOSED，PR #660 merged，`stance_broken` 信号源）；#584（草稿 merged，human-review，`# DRAFT` 数值定稿通道）——全部满足，无阻塞

---

## 1. 问题定义

### 1.1 现状（2026-08-21 worktree 侦查 @ origin/main 2180765）

**一句话现状：** #695（#682 实现）已把「顶部血条 + 架势条组合」主体交付——`EnemyHealthBar`（顶部中央 240×10 暗红粗条，offset_top=12）+ `EnemyStanceBar`（下移至 26..32），`hp_changed`/`stance_changed` 信号实时驱动、`died` 双条联动隐藏、`main_battle.gd` 消费 `ENEMY_HP_MAX=80`。**#684 验收 4 条中 AC1（布局）/AC2（实时更新）/AC4（风格）已实质满足**；剩余增量 = **敌人名字 Label（缺失）**、**架势崩解条级视觉反馈（缺失，现仅有文字提示）**、**Boss/杂兵呈现分档（未设计）**、**HP 百分比呈现方式（未裁决）**。

**基线审计表（Patch 16/21 流程：#695 已交付 vs #684 差距）：**

| 组件（`shandong-wolf/` 文件） | #682 DESIGN §2.5 要求 | origin/main 实测（2180765） | 状态 | 与 #684 的差距 |
|------|------|:-------:|:---:|------|
| `gdscripts/hud.gd` EnemyHealthBar | 顶部中央 240×10 暗红粗条（血条上方） | L78-86 创建（offset_top=`HUD_ENEMY_BAR_TOP`=12，`set_fill_color(HUD_BLOOD_RED)`）；L169 订阅 `hp_changed`；L225-228 `_on_enemy_hp_changed` 实时重绘；L160/L243 显隐联动 | ✅ 已交付 | 无（布局即 #684 AC1 主体） |
| `gdscripts/hud.gd` EnemyStanceBar | 血条下方组合（间距 4） | L89-96 下移至 26..32；L221-223 `_on_enemy_stance_changed` 实时重绘 | ✅ 已交付 | 无 |
| `gdscripts/main_battle.gd` 敌人装配 | 消费 `ENEMY_HP_MAX` | L159 `CombatEntityScript.new({..., "life_1_max": C.ENEMY_HP_MAX})`（80） | ✅ 已交付 | 无 |
| `gdscripts/constants.gd` | `HUD_ENEMY_HP_GAP`=4 | L332 已定义（`# DRAFT`） | ✅ 已交付 | 无 |
| `tests/test_hud.gd` | T5 布局同步 + B 组用例 | T5 断言 offset_top=26（L184）；B1/B2 EnemyHealthBar 用例（L515-539） | ✅ 已交付 | 无 |
| `gdscripts/hud.gd` 敌人名字 Label | ❌ 未设计 | ❌ 不存在 | ❌ 缺失 | **名字显示（issue「敌人名字 + 大血条」前半）** |
| `gdscripts/hud.gd` 崩解条级反馈 | ❌ 未设计 | ❌ L230-232 `_on_enemy_stance_broken` 仅 `_show_execute_hint()` | ❌ 缺失 | **AC3 闪白/色变（sekiro 基准「崩解白闪」）** |
| `gdscripts/hud.gd` Boss/杂兵分档 | ❌ 未设计 | ❌ 所有敌人统一顶部双条（`set_target_enemy` 无分档参数） | ❌ 缺失 | **issue「非 Boss 杂兵可沿用小架势条，不强制顶部」** |
| HP 百分比呈现 | ❌ 未裁决 | ❌ 纯条无数字 | ⚠️ 待裁决 | **issue「大血条（HP 百分比）」语义** |

**信号链路现状（全部就绪——#684 零新增信号源，只增消费端）：**

```
CombatEntity（敌人，#575/#682）
    hp_changed(hp_1, hp_2, active_life)  ──► Hud._on_enemy_hp_changed ──► EnemyHealthBar.set_segments  ✅ #695
    stance_changed(stance, stance_max)   ──► Hud._on_enemy_stance_changed ──► EnemyStanceBar.set_segments ✅ #695
    stance_broken(entity)                ──► Hud._on_enemy_stance_broken ──► _show_execute_hint()       ⚠️ 仅文字提示，条无反馈（#684 增量点）
    died(entity, final)                  ──► Hud._on_enemy_died ──► 双条隐藏/清空 + 击杀提示          ✅ #695
```

### 1.2 验收条件（issue body 4 条 → 本 PRD 保障）

| # | 验收条件 | 现状 | 本 PRD 保障 |
|---|---------|:----:|------------|
| AC1 | 顶部显示敌人血条 + 架势条（只狼式布局） | ✅ #695 已交付（顶部中央双条组合） | §5.1 AC1：布局维持；**补敌人名字 Label**（issue 字面「敌人名字 + 大血条」） |
| AC2 | 血条随伤害减少、架势随积攒/恢复实时更新 | ✅ #695 已交付（信号驱动） | §5.1 AC2：维持，零改动（唯一注意：架势「恢复」走 `stance_changed` 同路径，自动覆盖） |
| AC3 | 架势崩解时条有视觉反馈（闪白/色变） | ❌ 仅文字提示，条无反馈 | §5.1 AC3：**EnemyStanceBar 崩解闪白**（机械，sekiro「崩解白闪」）+ 碎裂提示候选（taste） |
| AC4 | 风格与 #576 HUD 一致（程序化绘制、同一色板） | ✅ 基底一致（_HudBar 自绘 + HUD_* 色板） | §5.1 AC4：新增元素沿用同构；新常量全部标 `# DRAFT` 只读 |

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 精英遭遇战读图（Boss 条） | 每次游玩 | 雪夜村口遇精英：顶部中央出现「敌人名字 + 大血条 + 架势条」组合；受击时血条缩短、弹反/受击时架势条缩短；架势崩解 → 架势条**白闪** + 「处决」文字提示 → 处决一击 |
| B | 慢线磨血观察 | 每次游玩 | 玩家不弹反、纯削血：血条逐刀缩短（12/刀 × 7 刀 ≈ 80 血），架势条因无弹反几乎不动——「双轨」在 UI 上可读 |
| C | 崩解反馈瞬间 | 每次游玩 | 第 4 次弹反崩解瞬间：架势条闪白（0.15s 级）+ 处决提示同时出现；白闪不遮挡战斗画面（克制、条级反馈） |
| D | 未来杂兵/多敌人 | v1（#589 后） | 非 Boss 杂兵：不显示顶部大条与名字，仅保留既有小架势条（EnemyStanceBar 位置）——MVP 期 API 先行，呈现分档由注入方决定 |

### 1.4 范围边界（Patch 14 去冲突）

| PRD / Issue | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|------------------|
| #576 HUD（草稿 merged，human-review） | 玩家双段血条/玩家架势条/敌人架势条/提示文字/低血信号 | ❌ 不改玩家区块、不改提示文字显隐逻辑、不改 `_HudBar` 核心；只在其上 **additive** 加名字 Label + 崩解闪白 + 分档 |
| #682 精英 AI（CLOSED，#695 merged） | 敌人 HP 数据慢线 + EnemyHealthBar 基底 + 蓄力/击退/恢复 | ❌ 不重设计条布局（已有）；不碰 AI/数值；#684 = **UI 呈现层增量**（名字/反馈/分档），数据源只读消费 |
| #580 处决（CLOSED，#660 merged） | stance_broken → 处决窗口/演出 | ❌ 不动编排器；只消费 `stance_broken` 信号做条级反馈（与文字提示正交） |
| #584 数值 DRAFT（草稿 merged，human-review） | 全量 `# DRAFT` 数值 + 调参面板 | ❌ 不裁决数值；本 PRD 新常量（名字字号/闪白时长等）全部标 `# DRAFT` + 候选集只读引用 |
| #589 军曹 / #590 汉奸 Boss（backlog OPEN） | 具体内容精英/Boss：危攻击/多管架势/二阶段 | ❌ 不实现 Boss 内容；Boss/杂兵**分档 API** 为其铺路（呈现开关），内容归未来 issue |
| #682 DESIGN §2.5（EnemyHealthBar 设计） | 血条+架势条组合的布局/接线 | ✅ 本 PRD 以此为**已交付基底**引用，不再复述其设计理由 |

**红线（继承 + 新增）：**
- ❌ 不修改既有接口签名——`set_target_enemy(entity)` / `bind_player(entity)` / `set_debug_*` / `show_debug_hint` 保持原样（#682 红线延续，main_battle.gd L185-187 与全部现有测试必须零改动）
- ❌ 不引入 `_process` 轮询、不引入贴图/tscn（#576 零贴图契约 + TF-1 静态断言延续）
- ❌ 不裁决 `# DRAFT` 数值（新常量全部候选集 + 只读，定稿归 #584/taste 通道）
- ❌ 不新增战斗信号源——只消费既有 6 信号

---

## 2. 设计意图

### 2.1 为什么当前状态如此（历史成因）

| 现状 | 成因 Issue | 说明 |
|------|-----------|------|
| 敌人无 HP UI（曾） | #576 范围 | #576 只做玩家血条 + 敌人**架势**条（顶部细条），敌人 HP 条不在其范围 |
| 敌人 HP 数据形同虚设（曾） | #682 拆分 | 用户 8-21 实机「一击毙命」反馈 → #682 补 HP 慢线（装配消费）+ 顺带实现 EnemyHealthBar（AC6） |
| EnemyHealthBar 已存在 | #695（#682 实现） | 血条+架势条组合、信号驱动、测试齐全——#684 的核心布局需求已被覆盖 |
| 名字/崩解反馈/分档缺失 | #684 拆分时机 | 用户拍板把「血条/架势条 UI 设计」从 #682 补充中**拆分**为独立 issue：#682 交付数据与基底，UI 呈现细节（名字/反馈/分档）归 #684 |

### 2.2 为何现在做

1. **数据与信号源全部就绪**：`hp_changed` / `stance_changed` / `stance_broken` / `died` 四信号在 #695 后已全部接线到 Hud——名字、闪白、分档全部是**既有信号的纯消费端增量**，无新数据管道要建。
2. **#684 是 #682 的自然 UI 收尾**：#682 AC6 只保证「血条可见」，Boss 战的完整读图体验（名字 + 崩解反馈）是 issue body 明示的增量；不做则「血条存在但无 Boss 战氛围」。
3. **分档 API 现在设计成本最低**：MVP 只有一个精英敌人，注入方（main_battle.gd）改动面最小；等 #589 军曹/#590 汉奸落地时再改 Hud 签名会牵动更多调用方。
4. **sekiro 基准明确**：「架势崩解必须惩罚清晰（硬直 + 白闪）」——崩解瞬间的条级白闪是只狼式反馈的必要项，非锦上添花。

### 2.3 既有约束（继承）

| 约束 | 详情 | 来源 |
|------|------|------|
| HUD 层级 | CanvasLayer layer=1（#562 同层约定） | #576 DESIGN |
| 渲染技术栈 | 纯 Control + `_draw()` 程序化绘制，零贴图零 tscn | #576 AC4 / #576 DESIGN |
| 信号驱动 | 零 `_process` 轮询；更新全部由信号 + Tween/Timer 驱动 | #576 TF-1 静态断言 |
| 色板 | `HUD_MOON_WHITE #e8e6e3` / `HUD_INK_BLACK #141414` / `HUD_BLOOD_RED #8c2f2f`；低血/危险 = 血红，常态 = 月白 | #576 constants |
| 数值纪律 | 新数值全部 `# DRAFT` + 候选集，定稿归 #584/taste | #682 红线 |
| 接口稳定 | 不修改既有公有 API 签名；additive 扩展 | #682 红线 |

---

## 3. 影响分析

### 3.1 直接影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `shandong-wolf/gdscripts/hud.gd` | Hud（敌人区） | 修改（additive）：`EnemyNameLabel` 创建 + 显隐联动；`_HudBar.set_break_flash()` 或等价崩解闪白状态；`set_boss_mode()` / `set_enemy_display_name()` 分档 API；`_on_enemy_stance_broken` 增订闪白触发 |
| `shandong-wolf/gdscripts/constants.gd` | HUD 分区 | 修改（追加 `# DRAFT` 常量）：名字字号/上边距、闪白时长/颜色候选等（候选集只读） |
| `shandong-wolf/tests/test_hud.gd` | HUD 测试 | 修改：名字 Label 布局/显隐断言、崩解闪白状态断言（Tween 驱动可 headless 断言状态变量）、boss/minion 分档断言 |
| `shandong-wolf/gdscripts/e2e_hud_capture.gd` | E2E 截图驱动 | 修改：新增截图态（BOSS_BAR / STANCE_BREAK_FLASH / MINION_MODE），沿用 debug API + auto_cycle 模式 |
| `shandong-wolf/e2e_shots.json` | shot plan | 修改：hud group 追加 shots（名字可见帧 / 闪白帧 / 杂兵档帧） |

### 3.2 新建文件

| 文件 | 说明 |
|------|------|
| 无 | 全部增量落在既有 4 文件内（hud.gd / constants.gd / test_hud.gd / e2e_hud_capture.gd + e2e_shots.json）——与 #682「无新文件」先例一致 |

### 3.3 间接影响模块

| 文件 | 影响 |
|------|------|
| `shandong-wolf/gdscripts/main_battle.gd` | ⚠️ 唯一可选触碰点：若采用「注入方声明 Boss 档」设计，则 L187 `set_target_enemy` 后追加一行 `hud.set_boss_mode(true)` + `hud.set_enemy_display_name(...)`——**两行新增，零签名改动** |
| `shandong-wolf/gdscripts/combat_entity.gd` / `enemy_ai.gd` | 零改动（纯数据源，本 PRD 只读消费） |
| `shandong-wolf/tests/test_main_assembly.gd` | 若 main_battle 追加两行，装配测试补断言（可选） |

### 3.4 数据流影响

```
【Boss 档（MVP 唯一敌人 = 精英）】
main_battle._build_enemy
    ├─► hud.set_target_enemy(enemy_entity)          # 既有，零改动
    ├─► hud.set_boss_mode(true)                     # 新：名字+血条+架势条 全显
    └─► hud.set_enemy_display_name("…")             # 新：taste 文案（# DRAFT 候选）

CombatEntity 信号 ──► Hud
    hp_changed ──► EnemyHealthBar.set_segments        ✅ 既有
    stance_changed ──► EnemyStanceBar.set_segments    ✅ 既有
    stance_broken ──► EnemyStanceBar 白闪(Tween 0.15s级) + _show_execute_hint()   ← 新增条级反馈
    died(final) ──► 名字隐藏 + 双条隐藏 + 击杀提示      ← 名字联动新增

【杂兵档（未来 #589 后）】
set_target_enemy(enemy) + set_boss_mode(false)
    ──► EnemyNameLabel.visible = false
    ──► EnemyHealthBar.visible = false
    ──► EnemyStanceBar 维持顶部细条（现状位置）
```

### 3.5 需更新的文档

- [ ] `docs/GAME_DESIGN/` 对应战斗章节（post-merge agent 在 merge 后更新，research 阶段不碰）
- [x] 本 PRD（`docs/PRD/684-boss-hp-bar-ui.md`）

---

## 4. 方案对比

### 4.1 敌人名字呈现

**方案 A：独立名字 Label（推荐）** — `EnemyNameLabel`（Label 控件，`_make_hint_label` 同构但无底框或极简底框），顶部中央、血条上方（offset_top 候选 0..4），锚点 0.5；`set_enemy_display_name(name)` 注入，boss 档显示、杂兵档隐藏。
- Pros：只狼式「名字在条上方」经典布局；零 tscn 零贴图；显隐独立于条，分档干净；超长名走 `OVERRUN_TRIM_ELLIPSIS`（既有 `_make_hint_label` 能力）
- Cons：多一个节点；文案内容属 taste 通道（名字本身待用户给）
- Risk：Low ｜ Effort：0.5-1 天

**方案 B：名字嵌入血条内部** — 名字绘制在 EnemyHealthBar 条内左侧。
- Pros：省一个节点
- Cons：240×10 的细条内放文字可读性差；血条缩短时文字与填充重叠；违反「一条线一个信息」（#576 哲学）
- Risk：Med ｜ Effort：0.5-1 天

**方案 C：不做名字** — 维持纯条。
- Pros：零改动
- Cons：不满足 issue 字面「敌人名字 + 大血条」；Boss 战氛围缺一角
- Risk：— ｜ Effort：0

**推荐：A**（理由：①只狼式读图基准即名字在条上；②克制风格下名字是信息层必要项；③与分档 API 正交，杂兵档直接隐藏）

### 4.2 架势崩解条级反馈

**方案 A：条级白闪 Tween（推荐，机械）** — `_HudBar` 新增 `set_break_flash()` 状态：崩解瞬间填充/描边转 `HUD_MOON_WHITE`（候选闪白时长 0.12-0.25s，sekiro「崩解白闪」），Tween 淡出回常态；`_on_enemy_stance_broken` 触发。零 `_process`（复用 `_kill_tween` + `create_tween` 既有模式）。
- Pros：直接对应 sekiro 基准「崩解必须惩罚清晰：白闪」；条级反馈与文字提示正交（AC3 字面满足）；headless 可测（状态变量断言）
- Cons：视觉效果强度有限（克制风格下恰好合适）
- Risk：Low ｜ Effort：1 天

**方案 B：碎裂提示（taste 候选，不机械定稿）** — 崩解时条上绘制碎裂裂纹（`_draw` 折线）或碎裂像素粒子（#579 GPUParticles 风格）。
- Pros：只狼「架势条碎裂」经典表现，反馈最强
- Cons：视觉强度/色相/粒子数全属 taste 通道（issue 明示「视觉色值归 taste」）；超出结构 agent 全权范围；MVP 克制风格下可能过重
- Risk：Med（审美裁决悬置）｜ Effort：1.5-2 天
- **处置：** 本 PRD 推荐 A 落地（机械），B 作为 `# DRAFT` 候选进 PR 供用户定稿（taste 通道），implement 不实现 B

**方案 C：维持现状（仅文字提示）** — 不满足 AC3，弃。

**推荐：A + B 候选清单**（理由：sekiro 基准字面「白闪」；A 机械可交付，B 留 taste 裁决；两者不互斥——B 定稿后可叠加在 A 之上）

### 4.3 Boss / 杂兵呈现分档

**方案 A：Hud 新增分档 API（推荐）** — 保持 `set_target_enemy(entity)` 签名不变，新增 `set_boss_mode(enabled: bool)`：true → 名字+血条+架势条全显；false → 血条+名字隐藏、仅保留小架势条（现状位置）。`set_target_enemy(null)` 幂等隐藏全部。
- Pros：零签名破坏（红线满足）；main_battle 只加两行；杂兵档天然获得（#589 后注入方传 false 即可）；测试可 headless 断言三态显隐
- Cons：Hud 内部多一个布尔状态（需与 `set_target_enemy` 显隐逻辑合并维护）
- Risk：Low ｜ Effort：1 天

**方案 B：修改 `set_target_enemy(entity, is_boss)` 签名** — 参数进既有方法。
- Pros：单一入口
- Cons：破坏 #682 红线「不修改既有接口签名」；main_battle L187 与 test_hud B1/B2 全部要改；多 agent 并行期改动面大
- Risk：Med ｜ Effort：0.5 天 + 回归面

**方案 C：独立 HudBossBar 组件类** — 新类承载 Boss 条组合。
- Pros：隔离干净
- Cons：与 Hud 既有 `EnemyHealthBar`/`EnemyStanceBar` 重复维护；#576「单 Hud 全 UI」架构哲学违背；测试/E2E 双份
- Risk：Med ｜ Effort：2 天

**推荐：A**（理由：①红线字面满足；②MVP 期注入方改动最小；③为 #589/#590 铺路——未来 Boss/杂兵共存时注入方按实体声明档位）

### 4.4 HP 百分比呈现

**方案 A：纯条不显数字（推荐）** — 血条长度即百分比（`set_segments([hp_1],[life_1_max])` 天然百分比语义）。
- Pros：只狼式读图（Sekiro 自身不显数字百分比）；#576「一条线一个信息」哲学；零新增节点
- Cons：精确血量不可读（克制风格下可接受）
- Risk：Low ｜ Effort：0

**方案 B：条尾百分比文本** — 小号 `Label` 显示 `87%`。
- Pros：精确读图
- Cons：信息密度上升（#576 克制哲学反对）；百分比文本在 240px 条上属噪声；taste 通道大概率否决
- Risk：Low（审美）｜ Effort：0.5 天

**推荐：A，B 作为 `# DRAFT` 候选进 PR 供用户定稿**（理由：issue「大血条（HP 百分比）」语义 = 条反映百分比，非必须数字文本；taste 通道裁决权保留）

### 4.5 推荐组合

| 决策点 | 推荐 | 核心落点 |
|--------|------|---------|
| 名字呈现 | A：独立 Label | `EnemyNameLabel` + `set_enemy_display_name()` |
| 崩解反馈 | A：条级白闪（B 碎裂留 taste） | `_HudBar.set_break_flash()` + `_on_enemy_stance_broken` 增订 |
| 分档 | A：`set_boss_mode(bool)` 新 API | Hud 三态显隐（boss/minion/null） |
| HP 百分比 | A：纯条（数字文本留 taste） | 零改动 |

---

## 5. 边界条件与验收标准

### 5.1 验收标准（映射 issue AC）

- [x] **AC1: 顶部显示敌人血条 + 架势条（只狼式布局）** — 布局已由 #695 交付（EnemyHealthBar 240×10 @12 + EnemyStanceBar @26）
  - 验证：test_hud B1/B2 既有断言全绿；新增名字 Label 布局断言（锚点 0.5、血条上方、boss 档可见）
- [x] **AC2: 血条随伤害减少、架势随积攒/恢复实时更新** — 已由 #695 交付（信号驱动）
  - 验证：既有信号用例全绿；不新增逻辑
- [ ] **AC3: 架势崩解时条有视觉反馈（闪白/色变）**
  - 验证：headless 单测——注入 `stance_broken` → 断言 EnemyStanceBar 进入 flash 态（状态变量）+ Tween 结束后回常态；E2E 截图——STANCE_BREAK_FLASH 态闪白帧可见（非纯黑、色数断言）
  - 视觉强度候选（`# DRAFT`）：白闪时长 0.12s / 0.18s / 0.25s；颜色 `HUD_MOON_WHITE` / 血红描边白填充
- [ ] **AC4: 风格与 #576 HUD 一致（程序化绘制、同一色板）**
  - 验证：新元素零贴图零 tscn（代码审查 + TF-1 静态断言延续）；新常量引用既有 `HUD_*` 色板，无新色相（除 `# DRAFT` 候选）

**Issue 补充范围（非硬 AC，但 issue body 明示）：**
- [ ] **敌人名字显示** — boss 档 `EnemyNameLabel` 可见、杂兵档隐藏；文案 `# DRAFT` 候选进 PR 待用户定稿
- [ ] **Boss/杂兵分档** — `set_boss_mode(true)` 全显 / `false` 仅小架势条；`set_target_enemy(null)` 全隐
- [ ] **HP 百分比** — 纯条呈现（推荐）；数字文本 `# DRAFT` 候选

### 5.2 边界情况

1. `set_target_enemy(null)` → 名字 + 血条 + 架势条全部隐藏（三态联动，与 #695 双条隐藏逻辑合并）
2. `died(entity, final=true)` → 名字 + 双条隐藏、击杀提示（final=false 防御分支 → 名字清空 + 双条清 0）
3. `stance_broken` 与处决文字同时触发 → 条级白闪与文字提示正交（互不遮挡，白闪仅条内）
4. 崩解后 `stance_changed(0, max)` 与 flash Tween 竞争 → flash 覆盖填充色，Tween 结束后 `set_segments` 重绘接管（`_draw` 读状态变量，无竞态）
5. 名字超长 → `OVERRUN_TRIM_ELLIPSIS` 省略（复用 `_make_hint_label` 能力）
6. 杂兵档下 `stance_broken` → 小架势条同样闪白（反馈一致性；或按 taste 决定杂兵是否降级为仅文字）
7. 非有限值 hp/stance（NaN/Inf）→ `get_segment_fractions` 既有防御返回 0.0，flash 状态不受影响
8. 重复 `set_boss_mode(true)` 幂等（同值早退）；`set_boss_mode` 在 `set_target_enemy` 之前调用 → 以注入时状态为准（`set_target_enemy` 重读档位）
9. flash Tween 被 died 打断 → `_kill_tween` 复用（既有模式），不留残影
10. 窗口缩放/低分辨率 → 锚点 0.5 + offsets 相对布局（既有设计），名字 Label 同锚点自适应

### 5.3 失败路径

1. **Tween 泄漏/残影**：连续崩解或 died 打断 flash → 复用 `_kill_tween` 统一清理（#576 既有模式），单测断言 Tween 结束后状态复位
2. **E2E 闪白帧不稳定**：真实 Tween 0.12-0.25s 内截图可能错过峰值 → E2E 走 debug API 直接置 flash 态（`show_debug_hint` 同构：`set_debug_stance_break()` 之类），不依赖真实 Tween 时序
3. **分档状态与注入顺序错乱**：`set_boss_mode(false)` 后 `set_target_enemy(entity)` 又把血条显示出来 → 显隐逻辑统一收敛到「注入时按档位初始化」（§5.2-8），单测覆盖三种调用顺序
4. **名字残留**：boss 档换目标/敌人死亡后名字未清 → `set_target_enemy` null 分支 + `died` 分支统一清名字

---

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 |
|------|:----:|:----:|
| #682 敌人 AI + HP 数据（#695 merged） | ✅ 已合入 origin/main | 无——数据源与 EnemyHealthBar 基底全部就绪 |
| #576 HUD 体系（草稿 merged，human-review） | ✅ 已合入（定稿等用户） | Low——风格母体已存在；视觉定稿差异经 human-review 通道吸收 |
| #580 处决（#660 merged） | ✅ 已合入 | 无——`stance_broken` 信号源就绪 |
| #584 数值 DRAFT（草稿 merged，human-review） | ✅ 已合入（定稿等用户） | Low——新常量 `# DRAFT` 候选走该通道定稿 |
| #589 军曹 / #590 汉奸 Boss | ⏳ backlog OPEN | 无——本 PRD 分档 API 为其铺路，不阻塞 |

```
#580（处决/stance_broken） ──► #682（精英 AI + HP 数据）──► #695 merged ──► #684（本 PRD，UI 呈现层）
                                          ▲
#576（HUD 体系）──────────────────────────┘
#584（数值 DRAFT）──► 新常量 # DRAFT 候选 ──►（taste 定稿通道）
```

### 6.2 阻塞

无。数据、信号、基底全部就绪；唯一悬置项（名字文案、闪白强度、碎裂、百分比文本）均为 taste 通道裁决，不阻塞 implement。

### 6.3 准备清单

- [ ] implement 前确认 origin/main 已含 #695（EnemyHealthBar）——本 PRD 基线即 origin/main 2180765
- [ ] 向用户（taste 通道）索取/确认敌人名字文案候选（`# DRAFT`）
- [ ] 确认 flash 时长/颜色候选集随 PR 提交（implement 选默认值，候选清单进 PR）

---

## 7. Spike / 实验

> 按 `depth: standard`，§7 可选；本 PRD 含 2 实验提升交接质量（#682 先例）。

### 实验 E1：崩解闪白的参数域与可测性

- **问题：** 白闪时长/颜色取什么值既满足「惩罚清晰」又不破坏克制风格？headless 下如何稳定断言？
- **方法：** ①单测层——`set_break_flash()` 用状态变量而非直接依赖 Tween 回调，headless 断言「注入 stance_broken → flash 态 true → tween.finished → false」；②E2E 层——debug API 直接置 flash 态截图（绕开时序），analyze_bmp 断言闪白帧与常态帧色数/主题色差异；③视觉候选（0.12/0.18/0.25s × 纯白/月白）进 PR 供 taste 裁决
- **预期结果：** flash 态可 headless 稳定断言；E2E 截图能区分闪白帧（色数下降或主题色偏移）；时长候选集产出
- **影响：** 决定 AC3 的机械实现形态（状态变量 + Tween 的边界划分）

### 实验 E2：分档 API 形态（布尔参数 vs 独立方法）的单测裁决

- **问题：** `set_boss_mode(bool)` 独立方法与 `set_target_enemy(entity, is_boss)` 签名扩展哪个更符合「零签名破坏」红线？
- **方法：** ①grep 既有调用方与测试：`set_target_enemy` 的调用点（main_battle L187 + test_hud B1/B2）——签名扩展需全部同步改；②静态验证独立方法形态下既有测试零改动；③单测覆盖三种调用顺序（先档后注入 / 先注入后档 / 反复切换）断言三态显隐
- **预期结果：** 独立方法形态下既有测试零 diff；顺序覆盖用例全绿 → 方案 A 成立
- **影响：** 决定 §4.3 推荐方案的落地细节（独立方法 + 注入时读档）

---

## 8. 交接上下文

### 8.1 系统状态（plan agent 接手时）

- origin/main @ 2180765（或更新）：#695 已合入——`EnemyHealthBar`（240×10 @12 暗红）+ `EnemyStanceBar`（@26）+ `main_battle.gd` L159 消费 `ENEMY_HP_MAX=80` + test_hud T5/B 组用例全绿
- 本 PRD 增量：名字 Label、崩解闪白、boss/minion 分档、HP 百分比裁决——全部落在 hud.gd / constants.gd / test_hud.gd / e2e_hud_capture.gd / e2e_shots.json，**无新文件**

### 8.2 接口契约（新增，全部 additive）

| 接口 | 签名 | 语义 |
|------|------|------|
| `Hud.set_boss_mode(enabled: bool)` | 新 | true=名字+血条+架势条全显；false=仅小架势条；幂等；注入时读取 |
| `Hud.set_enemy_display_name(name: String)` | 新 | 设置 `EnemyNameLabel.text`；空串隐藏 |
| `_HudBar.set_break_flash()`（或等价内部状态） | 新 | 填充/描边转白（候选时长），Tween 淡出回常态；`_draw` 读状态 |
| `_on_enemy_stance_broken` | 修改（内部） | 增订：触发 EnemyStanceBar flash（既有 `_show_execute_hint()` 保留） |
| `_on_enemy_died` / `set_target_enemy(null)` | 修改（内部） | 增订：名字显隐联动 |
| `Hud.set_debug_stance_break()`（E2E 驱动，命名可调） | 新 | debug API：直接置 flash 态供截图（`show_debug_hint` 同构） |

**消费方（main_battle.gd）增量（≤2 行）：**
```gdscript
hud.set_target_enemy(enemy_entity)   # 既有
hud.set_boss_mode(true)              # 新增：MVP 唯一敌人 = 精英 → Boss 档
hud.set_enemy_display_name("…")      # 新增：taste 文案（# DRAFT 候选）
```

### 8.3 测试与 E2E 计划

- `test_hud.gd` 新增：EnemyNameLabel 布局/显隐（boss/minion/null 三态）、flash 状态机（注入→置位→Tween 结束复位）、分档顺序覆盖（§5.2-8 三序）
- `e2e_hud_capture.gd` 新增态：BOSS_BAR（名字+双条可见）/ STANCE_BREAK_FLASH（debug 置位）/ MINION_MODE（仅小条）；`e2e_shots.json` hud group 追加 3 shots
- 装配测试（可选）：main_battle 两行新增后补断言

### 8.4 主要风险

| 风险 | 等级 | 缓解 |
|------|:----:|------|
| 名字文案未定（taste 通道） | Low | `# DRAFT` 候选 + 默认占位；不阻塞结构实现 |
| 闪白视觉强度审美分歧 | Low | 机械实现 + 候选集进 PR 供用户定稿；E2E 截图提供裁决证据 |
| 分档显隐状态机遗漏（注入顺序） | Low | §5.2-8 三序单测覆盖 |
| 并行 agent 冲突（hud.gd 共享） | Med | worktree 隔离 + additive 修改 + 提交前 merge main（worktree-commit.sh 自动） |

### 8.5 下一步（plan agent）

1. 读 `docs/DESIGN/682-elite-boss-ai.md` §2.5（EnemyHealthBar 既有设计的完整上下文）与本 PRD §4 推荐组合
2. 产出 DESIGN：hud.gd 增量的节点结构（名字 Label / flash 状态 / 分档布尔）、constants 新增 `# DRAFT` 候选常量、test_hud 用例清单、E2E 新态清单
3. 红线核对：零签名破坏、零 `_process`、零贴图、`# DRAFT` 只读
