# PRD #683 — [Feature] 角色绘制修正：火柴人结构完整化（缺头 / 走路动画异常）

> **Parent Issue:** #683（feature / workflow/research / priority/high / graphics / version/mvp）
> **Agent:** game-research-agent（预调查 workflow，Patch 10 — issue 声称逐条核对当前源码）
> **游戏:** shandong-wolf（manifest `game.active`）｜**引擎:** Godot 4.7.1（viewport 1280×720）
> **深度:** 无 depth label → standard（§1–6 + §8 必写；§7 因视觉调参需实证而保留）
> **日期:** 2026-08-21
> **结论一句话:** issue 三项指控中「缺头」**结构上不成立但观感成立**（头 Polygon2D 已存在且被单测覆盖，实际问题是低对比 + 头身重叠 + 比例偏离 GDD + 移动抖动中头部视觉丢失）；「走路动画异常」**属实**（4 帧循环 = 0.067s/周期过快、单段腿无膝盖、步频与 MOVE_MAX_SPEED 不匹配、且**视觉无 facing 翻转**——向左移动时角色倒走）；「各状态骨架一致性」**属实**（各 clip 摆姿为独立 DRAFT 值，无公共基准姿态，idle→guard 单帧跳变 177°+）。

---

## 1. 问题定义

### 1.1 预调查结论（issue 声称 vs 当前 main 源码，2026-08-21 侦查）

| # | Issue 声称 | 预调查结果 | 证据 |
|---|-----------|-----------|------|
| 1 | 角色「没有头」 | ⚠️ **Stale（结构）— 但观感问题真实** | 头 = Polygon2D 实心圆，`stick_figure.gd:65-70`（HeadPivot @ (0,-44) + `_make_head()`）、`:118-121`（16 段圆，`BODY_HEAD_RADIUS=16`）；单测 F1/F2 断言头存在且半径==常量（`tests/test_stick_figure_animation.gd:384-435`）。**结构上从未缺头**。观感缺失根因见 §1.2-A |
| 2 | 走路动画不对 | ✅ **属实 — 结构性异常** | `_build_move_spec()`：`frames = FRAME_ANIM_MOVE_STEP = 4` → 循环周期 **0.067s@60fps**；腿 ±25° 仅 2 帧间距（50°/33ms = 抖动而非步态）；无膝盖关节（单段 Line2D 腿）；动画播放速度固定 1.0，与 `MOVE_MAX_SPEED=300px/s` 无任何同步（脚滑步）；**全仓无 `scale.x` 翻转**——`CombatEntity.facing` 仅用于判定（`combat_judge.gd:84,94,101`），视觉从不应用（`main_battle.gd:131-147` 装配无 facing→scale 接线）→ 向左移动=倒走 |
| 3 | idle/攻击/格挡等状态骨架异常（拉伸/错位/抖动） | ✅ **属实 — clip 间姿态跳变** | 各 clip 摆姿为独立手摆 DRAFT 值，无公共基准姿态：idle 尾帧 `ArmRPivot=172° / SwordPivot=160°` → guard 首帧 `ArmRPivot=-5° / SwordPivot=-85°`（**单帧跳变 177°/245°**，视觉=肢体瞬移）；`play_clip()` 直接 `play()+seek(0)`，无跨 clip 姿态衔接规约；C1 单测只断言**切换耗时** ≤2 帧（`test_stick_figure_animation.gd:229-260`），不断言**姿态连续性** |

### 1.2 真实根因分析（按验收标准三分）

**A. 「缺头」的观感根因（结构已在，为何看不见）：**

| 根因 | 证据 | 影响 |
|------|------|------|
| 头与躯干深度重叠 | 头圆中心 (0,-44)，半径 16 → 圆范围 y∈[-60,-28]；躯干线 y∈[0,-44] → **重叠 16px**（头近半埋在躯干里），无颈部过渡 → 剪影读作「躯干顶个鼓包」而非「头」 | 静止时头不清晰 |
| 低对比 | `BODY_COLOR #2b2b2b` 全暗色剪影，雪夜背景同为暗色系（ink_wash 水墨夜景）→ 头（最小实心块）最先在视觉上消失 | 动态时头丢失 |
| 比例偏离 GDD | GDD 02-CONSTANTS:118 目标「总高 ≈150px、头:躯干:臂:腿 ≈ 1:2.5:1.9:2.2」；实际 40+44+32=**116px**，头径 32 : 躯干 44 = 1:1.375（头偏小） | 头占比不足 |
| 移动抖动叠加 | 4 帧步态循环下头随躯干每 2 帧 ±4px 弹跳 + ±2° 摆动（15Hz 高频）→ 小圆盘在运动中无法被视觉锁定 | 移动时头完全丢失 |

**B. 走路动画异常根因：**

1. **循环帧数 = 4（0.067s）**：`FRAME_ANIM_MOVE_STEP=4`（constants.gd:106，# DRAFT「配方 §6.5」字面沿用）。配方原文「移动摆臂步态（4 帧循环）」应解读为**4 个关键姿态**（contact/pass/contact/pass），而非整个循环仅 4 帧；自然步态周期 @60fps ≈ 24–32 帧（0.4–0.53s）。当前实现 = 腿每 33ms 摆动 50° → 视觉为「振动」。
2. **单段腿无膝盖**：腿=hip pivot + 单 Line2D（`_make_limb`），旋转只能「剪刀式」扫摆，脚离地画弧+滑步，无支撑相/摆动相（小小系列火柴人带膝盖关节）。
3. **步频与速度不匹配**：动画固定 1.0 倍速，`MOVE_MAX_SPEED=300px/s` 下每循环仅位移 ~20px，而腿摆幅 ~34px → 脚相对地面滑动；起步加速期（ACCEL=1200px/s²）腿部已满速摆动而身体未动。
4. **无 facing 翻转**：见 §1.1 #2 末项。倒走 + 挥刀方向与移动方向相反 = 「整体观感奇怪」主因之一。

**C. 骨架一致性根因：** 11 个 clip 的摆姿数值是 #574 实现期手摆 DRAFT（`_build_*_spec()`），无「公共基准姿态」约定、无「相邻状态首尾帧姿态差 ≤N°」约束；状态机允许的转移对（combat_state_table.gd:23-32）中多对存在大跳变（idle→guard 177°、guard→parry_success 25°、stagger→idle 22° 等）。

### 1.3 验收条件（issue body → 本 PRD 保障）

| # | 验收条件 | 本 PRD 保障措施 |
|---|---------|----------------|
| AC1 | 角色有清晰的头部 | §4.1：颈部线段 + 头径/位置比例修正 + 可选的头部冷白细轮廓（决策点交 E2E 截图裁决）；§5.1 AC1 含比例断言与 E2E 头可读性截图 |
| AC2 | 走路动画自然（步伐与速度匹配、摆臂合理） | §4.2：膝盖关节（腿两段化）+ 24–32 帧步态循环 + 摆臂反向同频 + 播放速度随实际速度同步；§4.3：facing→scale.x 翻转接线；§5.1 AC2 含循环时长/脚不滑步断言 |
| AC3 | 攻击/格挡/被击各状态骨架正常（不拉伸/错位/抖动） | §4.4：公共基准姿态 + 跨 clip 首尾帧衔接规约 + 姿态连续性单测（新增，C1 现有测试只查耗时）；§5.1 AC3 |

### 1.4 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 玩家游玩移动 | 每次运行 | 玩家看到火柴人**有头**、朝向与移动方向一致、步态自然（腿有膝盖、摆臂反向、无滑步），雪夜背景下剪影可读 |
| B | 战斗状态切换 | 每次交锋 | idle→attack→guard→stagger 切换时肢体不瞬移、不抖动，姿态连续 |
| C | 用户裁决（taste-draft） | E2E 截图 | 提交修正后 idle/move/attack/guard/stagger 截图，裁决头部清晰度、步态自然度、姿态连贯性；几何/帧数候选值定稿 |

### 1.5 范围边界（与既有 PRD/Issue 去冲突，Patch 14）

| Issue / PRD | 覆盖范围 | 本 PRD 不重复覆盖 |
|------------|---------|------------------|
| #574（merged #612） | 火柴人骨架 + 11 态关键帧动画 + consume_state 契约 | ❌ 不重建骨架/动画框架；在其上**补结构**（颈/膝盖）+ **修摆姿与节奏** |
| #584（OPEN，status/human-review） | 战斗数值 DRAFT 集中表（弹反窗口/架势/伤害，只狼基准） | ❌ 不碰战斗数值；本 PRD 只涉及**动画帧节奏与骨架几何**（#584 body 的调参优先级清单不含步态帧数）；新值仍按 # DRAFT 规范标注「候补值+影响+情感断言」，定稿协议归 #584 管线 |
| #573（merged） | 输入映射 + PlayerController 移动 | ❌ 不改移动物理；只消费 `MOVE_MAX_SPEED` 做步频匹配 + 读 facing 做视觉翻转 |
| #575（merged） | 战斗状态机权威 | ❌ 不定义状态；沿用 canonical 11 态与 consume_state 契约 |
| #585/#586/#661/#662/#678（merged） | MVP 战斗闭环组装 / E2E 剧本 / E2E 截图链路修复 | ❌ 不改 E2E 管线；复用已修复链路产出裁决截图（shot plan 微调见 §5.1） |
| 原画替换路径 | `set_sprite_slot()` 换 Sprite2D 层 | ❌ 本期零贴图（AC：保持程序化剪影）；结构修正不影响原画接入点 |

### 1.6 知识检索

- **Obsidian 知识库**（`/Volumes/Obsidian/Knowledge Ocean/`）：wiki/raw 全量 grep「火柴人/走路/步态/剪影」**无直接命中**（vault 文章以游戏叙事/系统设计笔记为主）；#574 PRD 同期检索结论相同。
- **程序化视觉配方**：`agents/skills/game-to-issues/references/visual-implementation-path.md` §6.5（小小系列参考坐标：关键帧摆姿 + 帧节奏「起势慢→爆发快→收招滞」；「4 帧循环」字面 vs 本 PRD 解读为 4 关键姿态，见 §4.2）。
- **GDD**：`docs/GAME_DESIGN/shandong-wolf/02-CONSTANTS.md:118`（总高 ≈150px、比例 头:躯干:臂:腿 ≈ 1:2.5:1.9:2.2）；`07-STICK-FIGURE-ANIMATION.md`（#574 落地文档）。
- **同链 issues**：#574（源 issue）、#584（DRAFT 定稿）、#585（装配，已 merged #666——本 issue 影响其在 main_battle.gd 的装配处）、#661/#662/#678（E2E 截图链路，已 merged——支撑本 issue 的视觉裁决）。

---

## 2. 设计意图

### 2.1 现状为何如此

| 现象 | 成因（issue/commit） | 说明 |
|------|---------------------|------|
| 头观感缺失 | #574 实现（#612） | 骨架按「最小结构」落地：头圆直接叠躯干顶端、无颈部；几何参数 DRAFT 未按 GDD 比例校准；配色沿用纯剪影 #2b2b2b，未针对暗夜景做可读性处理 |
| 走路动画异常 | #574 实现 + 配方字面 | `FRAME_ANIM_MOVE_STEP=4` 直接取自配方 §6.5 字面「4 帧循环」，未做步态学换算；骨架无膝盖关节（最小结构决策）；facing 翻转是**设计缺口**——#574 DESIGN 全文无 facing 章节，视觉层从未接线 |
| 骨架跳变 | #574 实现 | 11 clip 摆姿为手摆 DRAFT，无公共基准姿态规约；C1 验收只定义「耗时 ≤2 帧」，未定义「姿态差上限」 |

### 2.2 为什么现在改

1. **用户本地试玩反馈**（issue body 来源）：视觉缺陷已阻断 MVP 手感验收——角色「不像人」直接损害 #585 组装的可玩版本观感。
2. **E2E 截图链路已可用**（#661/#662/#678 合并）：视觉裁决路径打通，本 issue 的「清晰头部/自然步态」可量化截图验收（#574 时代截图链路未就绪，DRAFT 摆姿未被用户裁决过）。
3. **改动面收敛**：全部改动落在 `stick_figure.gd`（结构）/`stick_figure_controller.gd`（摆姿与节奏）/`main_battle.gd`（facing 接线）/`constants.gd`（# DRAFT 几何与帧数），不触碰战斗逻辑（#575/#577/#580 已合并且稳定）。

### 2.3 前置约束（继承 issue 与既有系统）

| 约束 | 详情 |
|------|------|
| 零美术资产 | AC5 红线（#574）：仅 .gd/.tscn 程序化生成，禁止贴图；头部轮廓方案必须是程序化 Line2D/Polygon2D |
| 剪影风格 | 单色剪影语义（实心填充）；「禁止页游光效堆砌」——头部可读性方案不得引入辉光/渐变 |
| 动画只消费状态 | consume_state 契约不变（#574）；本 issue 不改输入驱动链 |
| 帧节奏 DRAFT 协议 | 新帧数/几何值全部进 constants.gd # DRAFT 分区，注释含「候补值+影响什么+情感断言」；定稿归 #584 管线 |
| 过渡上限 | #574 AC1 保留：状态切换耗时 ≤2 帧（FRAME_ANIM_TRANSITION_MAX=2）——姿态连续性方案不得破坏该上限 |
| 战斗判定依赖 facing | #577 判定用 `CombatEntity.facing` 校验命中方向——**视觉 facing 必须与逻辑 facing 一致**，否则玩家看到「朝左挥刀却判定朝右命中」 |
| 敌人复用同场景 | `main_battle.gd` 敌我均实例化 `player_stick_figure.tscn` → 结构修正（头/膝盖/facing 接线）一次改动双端生效 |

---

## 3. 影响分析

### 3.1 直接影响的文件

| 文件 | 模块 | 改动性质 |
|------|------|---------|
| `shandong-wolf/gdscripts/stick_figure.gd` | 骨架构建 | **改**：加 NeckPivot（颈部线段）+ 腿两段化（膝 pivot：LegUPivot→LegLPivot→shin Line2D，或等效结构）；头径/头位按比例修正 |
| `shandong-wolf/gdscripts/stick_figure_controller.gd` | 动画摆姿 | **改**：move clip 重排为 24–32 帧步态关键姿态（contact/pass ×2）；攻击/格挡/硬直等 clip 摆姿按公共基准姿态校准；play_clip 加姿态衔接处理 |
| `shandong-wolf/gdscripts/constants.gd` | # DRAFT 参数 | **改**：新增/修订 `BODY_NECK_LENGTH`、`BODY_HEAD_RADIUS`、`FRAME_ANIM_MOVE_STEP`（或新增 MOVE 周期常量）、膝盖相关几何、头部轮廓开关参数——全部 # DRAFT 注释 |
| `shandong-wolf/gdscripts/main_battle.gd` | 装配 | **改**：玩家/敌人 facing→视觉翻转接线（facing 变化时设 `StickFigure.scale.x = facing`；敌人侧读 EnemyAI.facing） |
| `shandong-wolf/tests/test_stick_figure_animation.gd` | 动画单测 | **改/增**：头比例断言（AC1）、move 周期/脚不滑步断言（AC2）、跨 clip 姿态连续性断言（AC3，新增用例） |
| `shandong-wolf/e2e_shots.json` | E2E shot plan | **改**：move 组增加定格姿态 shot（contact/pass），保证截图可裁决步态；新增头部可读性对比 shot |

### 3.2 新增文件

| 文件 | 用途 |
|------|------|
| 无新增 .gd（结构改动在既有文件内完成；如膝关节点复杂可拆 `stick_figure_leg.gd`，由 implement agent 视复杂度决定） | — |

### 3.3 间接影响

| 文件 | 影响 |
|------|------|
| `combat_entity.gd` / `enemy_ai.gd` | 不改；仅其 `facing` 属性被 main_battle.gd 新接线消费 |
| `combat_judge.gd` | 不改；facing 判定逻辑不变，视觉对齐后玩家可正确理解命中方向 |
| `e2e_stick_figure_capture.gd` | 不改；rig 驱动契约不变，仅截图内容变化 |
| `docs/GAME_DESIGN/shandong-wolf/07-STICK-FIGURE-ANIMATION.md` | 需更新（骨架节点树加颈/膝、move 摆姿描述、facing 章节） |

### 3.4 数据流影响

```
CombatEntity.facing (逻辑朝向, #575/#577 判定源)
    │  (main_battle.gd 新接线: state/facing 变化)
    ▼
PlayerStickFigure (StickFigure.scale.x = facing)  ← 视觉翻转（本 issue 新增）
    │
StickFigureController.consume_state(state)  [契约不变]
    ▼
AnimationPlayer → anim_move (24–32 帧步态循环, 速度同步) / anim_attack / anim_guard ...
    ▼
StickFigure 骨架: TorsoPivot ─ HeadPivot(颈)─头圆  / ArmL/R / Sword / LegU→LegL(膝)
```

### 3.5 需更新的文档

- [x] `docs/GAME_DESIGN/shandong-wolf/07-STICK-FIGURE-ANIMATION.md`（骨架树/步态/facing 章节）
- [x] `docs/GAME_DESIGN/shandong-wolf/02-CONSTANTS.md`（新增 # DRAFT 常量行）
- [ ] `docs/PRD/683-stick-figure-structure-fix.md`（本文件，plan 阶段入口）
- [ ] `docs/DESIGN/683-*.md`（plan 阶段产出）

---

## 4. 方案对比

### 4.1 头部可读性（AC1）

| 方案 | 描述 | Pros | Cons | Risk | Effort |
|------|------|------|------|:----:|:------:|
| **A：颈线 + 比例校准 + 可选冷白头轮廓** | ① 新增 NeckPivot+Line2D 颈段（≈8px，连接躯干顶与头）；② 头位抬高至与颈衔接、重叠 ≤4px；③ 头径按 GDD 比例校准（候选 18–20，总高 → ~135px）；④ 可选：头加 1–2px 冷白细轮廓环（`SWORD_COLOR` 系，程序化 Polygon2D 描边或外扩圆环）——仅头部，不破坏剪影主体 | 结构完整（真·火柴人头颈）、比例回归 GDD、轮廓方案给暗夜背景下的最小可读性锚点；零贴图 | 轮廓选项偏离「纯单色剪影」语义（需用户裁决）；几何改动牵动全部 clip 视觉 | Med | 1–2 周 |
| B：仅调比例 | 只改 `BODY_HEAD_RADIUS`/头位，不加颈不加轮廓 | 改动最小 | 头身仍重叠、暗夜下仍不可读——不解决观感根因 | Med | <1 周 |
| C：Sprite2D 圆贴图 | 头换成程序生成的纹理圆 | 对比度可控 | **违反零美术资产红线（AC5）**；破坏「保留 Line2D 骨架」结构语义 | High | — |

**推荐 A**：颈+比例是结构完整化本体（issue 标题「结构完整化」），轮廓作为 taste 决策点交 E2E 截图裁决（§7 实验 1）。

### 4.2 走路动画（AC2）

| 方案 | 描述 | Pros | Cons | Risk | Effort |
|------|------|------|------|:----:|:------:|
| **A：膝盖关节 + 24–32 帧步态循环 + 速度同步** | ① 腿两段化（髋→膝→踝，膝 pivot 受动画驱动，走路时屈膝抬脚，攻击/格挡时屈膝蓄力）；② move clip 重排：周期 24–32 帧（0.4–0.53s，2 步），关键姿态 contact(0)→pass(6)→contact(12)→pass(18)→contact(24)，帧间距不对称（支撑相长/摆动相短）；③ 摆臂与腿反向同频（幅度候选 20–35°）；④ 播放速度随实际速度缩放（`playback_speed = clamp(v/MAX, 0.3, 1.2)` 或按速度档位切换），消除滑步 | 步态学正确、脚不滑步、与速度匹配（AC2 字面）；膝盖提升攻击/格挡姿态质量（AC3 连带收益）；符合小小系列参考 | 骨架结构改动（膝 pivot）影响全部既有 clip 的腿关键帧路径（需批量校准）；工作量最大 | Med | 2–3 周 |
| B：仅延长循环帧数 | 保持单段腿，循环改 24 帧、腿摆幅降为 ±15° | 改动小、风险低 | 无膝盖的剪刀摆腿+脚滑步仍存在——「自然」打折扣；AC2 只过一半 | Med | <1 周 |
| C：程序化 IK 步态（sin 驱动） | 腿用数学 IK 解算代替关键帧 | 理论上最自然 | 违反「关键帧摆姿」配方红线（recipe §6.5）；实现复杂度高、与 AnimationPlayer 体系冲突 | High | 3+ 周 |

**推荐 A**（骨架结构为本 issue 主线）；若 implement 阶段工期紧张，B 为可接受的最小过渡（但 AC2 判定不完整）。

### 4.3 视觉 facing 翻转（AC2/AC3 前提）

| 方案 | 描述 | Pros | Cons | Risk | Effort |
|------|------|------|------|:----:|:------:|
| **A：`StickFigure.scale.x = facing` 接线** | main_battle.gd 在 facing 变化时设视觉翻转（玩家读 `CombatEntity.facing`，敌人读 `EnemyAI.facing`；翻转作用于 StickFigure 根节点，Line2D/Polygon2D 全子树自动镜像） | 一行接线 + 信号监听；视觉与判定一致（#577 命中方向可读）；移动方向/挥刀方向正确 | 镜像后刀在身体另一侧（几何对称，摆姿无需改）；E2E 截图 rig 无 facing 变化（默认 +1，不受影响） | Low | <0.5 周 |
| B：不翻转（维持现状） | — | 零改动 | 倒走 + 反向挥刀继续存在——AC2「整体观感」不达标 | High | — |
| C：翻转整个 PlayerController 根 | scale 作用于 CharacterBody2D 根 | 视觉同 A | **会翻转碰撞体/输入坐标系**（move_and_slide 方向反转），破坏移动物理 | High | — |

**推荐 A**：作用于视觉子节点 StickFigure，物理层零影响。

### 4.4 跨状态骨架一致性（AC3）

| 方案 | 描述 | Pros | Cons | Risk | Effort |
|------|------|------|------|:----:|:------:|
| **A：公共基准姿态 + 首尾帧衔接规约 + 姿态差单测** | ① 定义 REST_POSE（自然站姿，全部关节角度）作公共基准；② 规约：状态表中相邻转移对（combat_state_table.gd:23-32）的 clip 首帧=前态尾帧姿态（差值 ≤15°/关节，或首帧直接归 REST_POSE 再动画化）；③ 新增单测：枚举相邻状态对断言最大关节角差 ≤阈值；④ 保留「耗时 ≤2 帧」既有上限 | 根治瞬移/抖动；测试可回归；不引入插值复杂度（延续 #574「首帧衔接」主策略） | 需重摆 11 clip 关键帧（与 §4.2 的腿结构改动叠加，工作量合并计算） | Med | 1–2 周（与 4.2 合并） |
| B：全 clip 加 2 帧 crossfade | `AnimationPlayer.play(custom_blend=2/60)` | 实现简单 | 破坏「直接 play + 首帧衔接」设计约定；crossfade 期间双 clip 叠加，攻击/格挡等姿态差异大时出现「残影」；与连招重入语义（同态重入重置首帧）冲突 | Med | 1 周 |
| C：保持现状 | — | 零改动 | AC3 明确不达标 | High | — |

**推荐 A**：符合 #574 既定「首帧衔接为主」策略的延续，且用单测把「骨架正常」从观感变成可回归断言。

### 4.5 推荐组合

| 子系统 | 推荐方案 | 核心改动点 |
|--------|---------|-----------|
| 头部可读性 | A：颈线 + 比例 + 可选轮廓（taste 裁决） | `stick_figure.gd` / `constants.gd` |
| 走路动画 | A：膝盖 + 24–32 帧步态 + 速度同步 | `stick_figure.gd` / `stick_figure_controller.gd` / `constants.gd` |
| 视觉 facing | A：scale.x 翻转接线 | `main_battle.gd` |
| 姿态一致性 | A：REST_POSE + 衔接规约 + 单测 | `stick_figure_controller.gd` / 测试 |

组合理由：四个子项共享同一批文件与同一次 clip 重摆工作，合并实现避免重复返工；全部为结构/机械改动，taste 决策点仅「头轮廓」一项，交 E2E 截图用户裁决。

---

## 5. 边界条件与验收标准

### 5.1 正常路径（AC 检查表）

- [x] **AC1: 角色有清晰的头部**
  - 静止 idle 帧：头圆与躯干由颈段分离，重叠 ≤4px；头径与躯干长比例在 GDD 目标 ±10%（候选 头径:躯干 ≈ 1:2.2–2.5 半径比）
  - E2E 截图（雪夜背景）：头部轮廓在截图缩放后可辨识（新增「头部可读性」shot，白底对比照可选）
  - 若采用轮廓方案：头轮廓 1–2px、颜色 `SWORD_COLOR` 系、无辉光
- [x] **AC2: 走路动画自然（步伐与速度匹配、摆臂合理）**
  - move 循环周期 ∈ [24,32] 帧（0.4–0.53s）；腿有关节（膝 pivot 存在且随动画屈伸）
  - 步频与速度匹配：匀速段（300px/s）每步位移 ≈ 步幅，脚不滑步（脚触点帧位移差 ≤2px）
  - 摆臂与腿反向同频，幅度 ∈ [20°,35°]
  - facing 翻转：`StickFigure.scale.x == CombatEntity.facing`（玩家）/ `EnemyAI.facing`（敌人）；向左移动时角色面左
- [x] **AC3: 攻击/格挡/被击各状态骨架正常（不拉伸/错位/抖动）**
  - 状态表相邻转移对（idle↔move/attack/guard/stagger、attack→idle、guard→idle/parry_success、stagger→idle 等）关节角差 ≤15°（新单测枚举断言）
  - 切换耗时仍 ≤2 帧（既有 C1 断言保持绿）
  - 无 clip 播放期间关节角度超出物理范围（膝/肘单向弯曲，候选 ±90° 内）

### 5.2 边界情况

1. **起步/急停**：速度 <30% 时步态应过渡到 idle（播放速度下限 0.3 或直接切 idle），不得出现「原地跑步」
2. **反向移动**：facing 翻转瞬间（scale.x 变号），动画不重置、姿态连续（翻转是镜像，无姿态跳变）
3. **敌人 facing**：敌人初始 facing=-1（e2e_main_assembly_capture.gd:218 已设）→ 翻转后敌人面左持刀，判定方向（#577）与视觉一致
4. **连招重入**：同态重入（attack→attack）重置前摇首帧语义不变（#574 §5-3），重摆后 clip 首帧仍等于该态「前摇首帧」
5. **headless/CI**：新断言不依赖渲染（节点树 + 角度数值断言）；E2E 截图仅在 --with-visual 下跑（#559 既定）
6. **guard→parry_success→move 链**：三态相邻，姿态差全部 ≤15°
7. **不同步速**：播放速度随实际速度缩放时，动画结束/循环边界不得跳帧（loop 模式下播放速度连续变化）

### 5.3 失败路径

1. **膝盖结构改动破坏既有 clip**：腿路径从 `LegLPivot:rotation` 变为多段——实现期必须全量回归 11 clip + 既有 F 系列单测（F1 pivot 列表需更新：leg 相关断言适配膝结构）
2. **头轮廓被判定破坏剪影**：E2E 截图裁决不通过 → 回退轮廓（保留颈+比例），仅一次 taste 决策，不阻塞 AC1 主体
3. **facing 接线误作用物理层**：接线目标必须是 `StickFigure` 子节点而非 PlayerController 根（§4.3-C 否决）；若误改物理根 → 移动反向 bug，单测（移动方向断言）应拦截

---

## 6. 依赖与阻塞

| 依赖 | 状态 | 风险 |
|------|:----:|:----:|
| #574 骨架/动画框架（#612 merged） | ✅ | 无——本 PRD 在其上扩展 |
| #585 MVP 战斗闭环（#666 merged） | ✅ | 低——main_battle.gd 装配处为本 PRD facing 接线点 |
| #661/#662/#678 E2E 截图链路修复 | ✅ | 无——裁决截图依赖此链路 |
| #584 帧节奏 DRAFT 定稿 | 🟡 OPEN（status/human-review） | 中——本 PRD 新增 # DRAFT 值仍按候补协议标注；若 #584 先定稿，需对齐其最终协议（不冲突：584 不覆盖步态帧数） |
| #586 E2E 剧本验收（#669/#673 merged） | ✅ | 低——shot plan 微调需过剧本格式约束 |

**依赖链：**

```
#572 地基 ──► #574 骨架/动画 ──► #585 战斗闭环 ──► #683 结构修正（本 PRD）
                                      │
#661/#662/#678 E2E 截图链路修复 ───────┘（裁决基础设施）
#584 数值 DRAFT 定稿（并行，只影响定稿协议，不阻塞实现）
```

**准备事项：** 实现前确认 #584 是否已定稿（若已定稿，新帧数值需按定稿表标注）；准备雪夜背景 + 白底两组 E2E 截图环境。

---

## 7. Spike / 实验（保留 — 视觉调参需实证，参照 #661/#662 先例）

| # | 问题 | 方法 | 预期结果 | 对方案影响 |
|---|------|------|---------|-----------|
| 1 | 头部轮廓是否必要？（剪影语义 vs 暗夜可读性） | E2E 截图对比：方案 A 带轮廓 vs 仅颈+比例，雪夜背景下各截 1 帧 idle | 带轮廓可读性明显提升 → 保留轮廓；否则回退纯剪影 | 决定 4.1-A 的轮廓选项去留 |
| 2 | 步态循环帧数落在 24 还是 32？（节奏感） | 同一 move 姿态序列按 24/28/32 帧各录 E2E 截图/录像，对比「步伐与 300px/s 速度」匹配度 | 帧数与滑步量呈反比；取滑步 <2px 的最小帧数 | 决定 4.2-A 的 FRAME_ANIM_MOVE 周期定值 |
| 3 | 播放速度同步策略：连续缩放 vs 两档切换 | 实现两版在 30%/70%/100% 速度下跑 move，观察起步/急停过渡 | 连续缩放起步更顺、无跳帧 → 连续；否则两档 | 决定 4.2-A 的速度同步实现细节 |

---

## 8. 交接上下文

**系统状态（plan agent 接手时）：** 当前 main 为 MVP 可玩版（#585 组装完毕，E2E 截图链路 #678 已修复）。火柴人骨架 = 7 pivot（torso/head/arm_l/arm_r/sword/leg_l/leg_r），头 Polygon2D 已存在但观感缺失；11 态动画 clip 运行时动态生成（零 .tres），帧数全部来自 constants.gd # DRAFT；`CombatEntity.facing`/`EnemyAI.facing` 逻辑完备但**视觉未接线**；敌人与玩家共用 `player_stick_figure.tscn`。

**主要风险：**
1. 腿两段化（膝 pivot）改动波及全部 11 clip 的腿关键帧路径 + F 系列单测——实现期全量回归（§5.3-1）
2. 头部轮廓为 taste 决策点——E2E 截图须提交用户裁决（#574 AC4 同款协议），不能自行定稿
3. #584 并行定稿可能影响新 # DRAFT 值的标注协议——实现前先查 #584 状态

**下一步（plan agent）：**
1. 按 §4.5 组合方案产出 DESIGN（骨架树：TorsoPivot+NeckPivot+头 / LegU→LegL 膝结构 / REST_POSE 定义）
2. TASKS 拆分建议：① constants # DRAFT 新值（颈长/头径/步态帧数/膝几何）→ ② stick_figure.gd 结构（颈+膝）→ ③ controller 摆姿重排（move 步态 + 各 clip 按 REST_POSE 校准）→ ④ main_battle.gd facing 接线 → ⑤ 单测（比例/步态/姿态差）→ ⑥ E2E shot plan 微调 + 截图裁决
3. 实施完成前确认 #584 状态，对齐帧数值定稿协议
