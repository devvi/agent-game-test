# PRD #704 — [Bug] 角色腿画反/与躯干重叠：腿 Line2D 默认向 -Y（向上）延伸（大腿根部在胸前）

> **Parent Issue:** #704（bug / workflow/research / priority/high / graphics / version/mvp）
> **Agent:** game-research-agent（预调查 workflow，Patch 10 — issue body 已含根因分析 → 逐条核对当前源码后直接产出 PRD）
> **游戏:** shandong-wolf（manifest `game.active`）｜**引擎:** Godot 4.7.1（viewport 1280×720）
> **深度:** 无 depth label → standard（§1–6 + §8 必写；§7 因视觉 bug 需实证而保留）
> **日期:** 2026-08-21
> **结论一句话:** issue 根因分析**全部属实**——`_make_limb()`（stick_figure.gd:135）统一让 Line2D 向 **-Y** 延伸，躯干/颈/臂/刀 pivot 在肢体顶端所以 -Y 正确，但**腿 pivot（髋）也在顶端**，rotation=0 时大腿从髋向 **-Y 向上延伸 20px** 与躯干（0→-44）完全重叠（膝 pivot 亦在 -Y 侧），大腿根部视觉落在胸前；该错误继承自 #683 DESIGN 的 -Y 几何约定（DESIGN 683 §2.2 `points=[ZERO,(0,-BODY_LEG_UPPER_LENGTH)]` 与同一文档 REST_POSE 表「LegLPivot 0=直立」自相矛盾），PR #694 实现了几何却未修正方向语义。最小修复 = **腿/膝 Line2D 反向为 +Y**（动画 ±12° 摆动基准不变，0=向下自然垂腿）。

---

## 1. 问题定义

### 1.1 预调查结论（issue 声称 vs 当前 main 源码，2026-08-21 侦查）

| # | Issue 声称 | 预调查结果 | 证据（源码/文档逐条核对） |
|---|-----------|-----------|--------------------------|
| 1 | `_make_limb()` 统一让 Line2D 自 pivot 向 **-Y（向上）** 延伸 | ✅ **属实** | `stick_figure.gd:135` `line.points = PackedVector2Array([Vector2.ZERO, Vector2(0, -length)])`；`_build_skeleton()` 内躯干/颈/臂/刀/腿全部经 `_make_limb` 构建 |
| 2 | 腿也应「向下」但默认 rotation=0 无 180° 翻转 → 腿从髋向 -Y 延伸与躯干重叠 | ✅ **属实** | `stick_figure.gd:110-121`：`leg_l.position = Vector2(-4, 0)`、`leg_r.position = Vector2(4, 0)`，rotation 默认 0 → 大腿 Line2D 从髋 (0,0) 向 (0,-20) 向上；躯干 Line2D 覆盖 y∈[0,-44] → **大腿整段与躯干重叠**（髋 pivot 恰在躯干根部）；`_make_knee_pivot`（:143-146）膝 pivot 位置 `(0, -body_leg_upper_length)` 也在 -Y 侧，小腿同样向上 |
| 3 | `stick_figure_controller.gd` L244 注释声称「legs rotation=0 即直立」与实现矛盾 | ✅ **属实** | 控制器 clip 摆姿注释（L~252 区段）：「肢体 Line2D 自 pivot 向 -Y 延伸（arms/sword rotation≈180° 即自然下垂；legs rotation=0 即直立）」——按 -Y 几何，rotation=0 的腿指向 **-Y（向上叠躯干）**，注释与几何矛盾；注释的「直立」语义只在 +Y 几何下成立 |
| 4 | 修复后 MOVE ±12° 摆动基准不变（0=直立向下） | ✅ **前提成立** | `constants.gd:137` `MOVE_SWING_LEG_DEG=12.0`；`_build_move_spec()`（:290-293）腿髋 track 围绕 0° 摆动 ±swing_leg、膝 track 摆动相屈 `MOVE_KNEE_BEND_DEG=40`；动画只写 pivot **rotation**，与 Line2D 几何方向解耦 → 几何翻向 +Y 后 rotation 语义「0=向下」成立，所有 clip track 数值**零改动** |
| 5 | #683（PR #694）已 merge 但腿方向问题漏网 | ✅ **属实** | `git log`：`f440434 feat(683)…(#694)` 增颈/膝骨架 + 24 帧步态 + REST_POSE 衔接 + facing 翻转；`42b732b fix(683): AC3 姿态差修复 — move 摆臂改 REST_POSE 相对偏移` 只调摆臂；两提交均未触碰腿 Line2D 方向 |
| 6 | 腿长 40px vs 躯干 44px 比例保持 | ✅ **属实（修复后仍成立）** | `constants.gd:112,114,131-132`：`BODY_TORSO_LENGTH=44`、`BODY_LEG_LENGTH=40`（#683 保留）、`BODY_LEG_UPPER/LOWER_LENGTH=20/20`；修复只改方向不改长度 |

**预调查关键发现（issue 之外）：** 错误**继承自 #683 的设计文档本身**——`docs/DESIGN/683-stick-figure-structure-fix.md:116` 规定 `Line2D 大腿: points=[ZERO, (0,-BODY_LEG_UPPER_LENGTH)]`（-Y），而同一文档 :137 REST_POSE 表写「LegLPivot/LegRPivot | 0 | 直立」。设计与自身约定矛盾，实现忠实于 -Y 几何 → 视觉错误。因此本 PRD 除修代码外还须**勘误 DESIGN #683 的 REST_POSE 语义表述**（§3.2）。

### 1.2 真实根因分析（几何约定不对称）

**肢体方向约定的不对称性是根因：**

| 肢体 | pivot 位置（相对根） | -Y 延伸语义 | rotation=0 视觉结果 |
|------|--------------------|------------|--------------------|
| 躯干 | 根部 (0,0) | 向上正确（躯干在髋上方） | ✅ 直立 |
| 颈/头 | 躯干顶端 (0,-44) | 向上正确 | ✅ 头在躯干上 |
| 臂 | 肩部 (±5,-44) | 向上 + rotation≈180° 翻转为下垂 | ✅ 自然垂臂（idle 178°/-172°） |
| 刀 | 肩部 (5,-44) | 向上 + rotation≈160° 斜持 | ✅ 持刀 |
| **腿** | **髋部 (±4,0)（顶端）** | **向上 = 错误**（腿应从髋**向下**） | ❌ **大腿叠躯干、大腿根部在胸前** |

躯干/颈/臂/刀的 pivot 都在肢体**顶端**，-Y 延伸（向远离 pivot 的上方）配合 rotation 翻转即可；唯独**腿的 pivot（髋）也在顶端**，但腿的语义是「从髋**向下**延伸」——需要 +Y 或 rotation=PI 翻转，而 #574/#683 实现均未给腿做翻转，`_make_limb` 又是无方向参数的统一工厂 → 腿沿 -Y 直冲躯干。

### 1.3 验收条件（issue body → 本 PRD 保障）

| # | 验收条件 | 本 PRD 保障措施 |
|---|---------|----------------|
| AC1 | 静止/idle 时：腿从髋自然向下垂（不重叠躯干） | §4.1 方案 A：腿/膝 Line2D 反向 +Y + 膝 pivot 移至 +Y 侧；idle clip 腿 rotation 全 0（track 值不动）→ 垂腿 |
| AC2 | 走路时：腿在向下基准上 ±12° 摆动（步态自然） | 几何方向与动画 rotation 解耦：±`MOVE_SWING_LEG_DEG` 摆动语义不变；§5.1 AC2 断言 contact/pass 关键帧 rotation 值不变 |
| AC3 | 头/颈/躯干/手臂比例正常（腿长 40px vs 躯干 44px 保持） | 只改方向不改长度常量；F2 单测（方向无关断言）继续通过；§5.1 AC3 |
| AC4 | E2E 截图（stick_figure 组）腿视觉正确 | §7 实验 2：01_idle/02a_contact/02b_pass 截图腿可见且自髋向下；E2E shot plan 无需改动 |

### 1.4 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 玩家进入战斗待机 | 每次运行 | 火柴人双腿自髋自然下垂（大腿根部在髋、不在胸前），剪影可读 |
| B | 玩家移动 | 每次移动 | 腿在向下基准 ±12° 摆动、摆动相屈膝抬脚，步态自然 |
| C | 用户裁决（E2E） | 修复后一次 | stick_figure 组截图（idle/move contact/pass）腿方向正确、无重叠 |

### 1.5 范围边界（与既有 PRD/Issue 去冲突，Patch 14）

| Issue / PRD | 覆盖范围 | 本 PRD 不重复覆盖 |
|------------|---------|------------------|
| #574（merged #612） | 火柴人骨架 + 11 态关键帧动画框架 | ❌ 不重建骨架/动画框架；只修**腿几何方向** |
| #683（merged #694） | 颈/膝骨架 + 24 帧步态 + REST_POSE 衔接 + facing 翻转 | ❌ 不重做步态节奏/骨架结构（已 merge）；本 PRD 修其**遗留的腿方向** + 勘误其 DESIGN 的 REST_POSE 语义表述 |
| #582/#613（merged） | 雪夜氛围/背景 | ❌ 不碰氛围；仅 E2E 截图复用其链路 |
| #586/#661/#662/#678（merged） | E2E 剧本/截图链路 | ❌ 不改 E2E 管线；复用 stick_figure 组 shot plan（shot 无需增删） |
| 原画替换路径 | `set_sprite_slot()` 换 Sprite2D 层 | ❌ 本期零贴图；方向修正不影响原画接入点（sprite 挂 pivot 下，pivot rotation 语义不变） |

### 1.6 知识检索

- **Obsidian 知识库**（`/Volumes/Obsidian/Knowledge Ocean/`）：wiki/raw 目录 grep「火柴人 / stick figure / 步态 / 肢体」**无直接命中**（vault 文章以游戏叙事/系统设计笔记为主）；与 #683 PRD 同期检索结论一致。
- **GDD**：`docs/GAME_DESIGN/shandong-wolf/07-STICK-FIGURE-ANIMATION.md:58-59`（腿两段结构图：`LegLPivot ── Line2D 大腿 ── LegKPivot ── Line2D 小腿`，无方向表述，无需改）；`:195-197`（`BODY_TORSO_LENGTH=44`、`BODY_LEG_LENGTH=40`，头:躯干:臂:腿 ≈ 1:2.5:1.9:2.2）。
- **DESIGN #683**：`docs/DESIGN/683-stick-figure-structure-fix.md:116-118`（腿 Line2D `points=[ZERO,(0,-UPPER)]`、膝 pivot @ `(0,-UPPER)`）——**方向错误源头**；:137（REST_POSE 表「LegLPivot 0=直立」）——**与几何矛盾的表述**。
- **同链 issues**：#574（骨架源）、#683（上一修复，已 merge #694）、#584（数值 DRAFT 定稿，与动画几何无关）。

---

## 2. 设计意图

### 2.1 现状为何如此

| 成因 | 详情 |
|------|------|
| #574 的 -Y 肢体约定 | `_make_limb` 无方向参数，统一 `(0,-length)`；躯干/颈/臂/刀 pivot 均在肢体顶端，-Y 配合 rotation 翻转正确（DESIGN 574 §2.2 遗留约定） |
| 腿未获得「向下」特判 | 腿 pivot（髋）同样在肢体顶端，但腿的语义是向下延伸——实现未给腿 rotation=PI 翻转、也未让腿 Line2D 反向；`leg_l/leg_r` rotation 默认 0 |
| #683 DESIGN 自相矛盾 | DESIGN 683 §2.2 写 `points=[ZERO,(0,-UPPER)]`（-Y 几何），REST_POSE 表却写「rotation 0 = 直立」——实现忠实于 -Y 几何，注释沿用「直立」表述 → 注释与实现矛盾（issue #3 指控） |
| PR #694 只补结构不补方向 | `f440434` 增膝 pivot/步态/翻转，`42b732b` 只调摆臂——腿几何方向漏网（AC 验收集中在步态节奏/姿态差，未覆盖腿方向） |

### 2.2 为何现在修

1. **实机验证暴露（2026-08-21）**：用户实测发现「大腿根部到了胸前」，MVP 角色视觉核心缺陷；
2. **优先级 high / version mvp**：剪影可读性是 #574 的核心卖点，腿叠躯干直接破坏角色剪影；
3. **修复成本极低**：动画 rotation track 与 Line2D 几何方向解耦（§1.1 #4），翻向 +Y 后所有 clip 数值零改动——典型「一行几何、全动画受益」。

### 2.3 先前约束（修复必须遵守）

| 约束 | 详情 |
|------|------|
| 动画 track 路径不变 | `LegLPivot:rotation`、`LegLPivot/LegKPivot:rotation` 等 9 条关节 track 路径（controller 全部 clip）禁止改动 |
| rotation 数值语义不变 | 各 clip 腿/膝 rotation 关键帧值（0 基准、±12° 摆动、40° 屈膝）**零改动**——几何翻向后语义自然正确 |
| 腿长常量不变 | `BODY_LEG_UPPER/LOWER_LENGTH=20/20`、`BODY_LEG_LENGTH=40` 保持（F2 测试与 GDD 比例依赖） |
| 测试方向无关性成立 | `_assert_limb_length`（test_stick_figure_animation.gd）用 `points[1].length()` 断言长度——**不检查方向**，翻向后 F1/F2 继续通过 |
| facing 翻转不受影响 | 视觉翻转走 `scale.x`（#683），与 Line2D 局部几何方向正交 |

---

## 3. 影响分析

### 3.1 直接影响的模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `shandong-wolf/gdscripts/stick_figure.gd` | 骨架构建 `_build_skeleton()` / `_make_limb()` / `_make_knee_pivot()` | **改**：腿/膝 Line2D 反向 +Y；膝 pivot 位置 `(0,-UPPER)` → `(0,+UPPER)`（约 4–6 行） |
| `shandong-wolf/gdscripts/stick_figure_controller.gd` | clip 摆姿注释（L~252「legs rotation=0 即直立」） | **改**：注释勘误为「legs rotation=0 即自然下垂（Line2D 向 +Y）」，消除与实现的矛盾 |
| `docs/DESIGN/683-stick-figure-structure-fix.md` | §2.2 腿结构 / §4 REST_POSE 表 | **改**：勘误 `points=[ZERO,(0,-UPPER)]` → `(0,+UPPER)`、膝 pivot `(0,-UPPER)` → `(0,+UPPER)`、REST_POSE 表「0=直立」→「0=自然下垂」 |

### 3.2 新文件

无（修复在既有文件内完成；不拆 `stick_figure_leg.gd`——#683 的可选拆文件变体不适用，改动量 <10 行）。

### 3.3 间接受影响的模块

| 文件 | 影响 | 是否需要改动 |
|------|------|------------|
| `shandong-wolf/tests/test_stick_figure_animation.gd` | F1/F2 方向无关断言（`points[1].length()`）；AC2-T3/T5 断言 clip rotation 值（不随几何变化） | ❌ 不改；建议新增一条方向断言（§7 实验 1，plan agent 决策） |
| `shandong-wolf/gdscripts/constants.gd` | 腿长常量 | ❌ 不改 |
| `shandong-wolf/e2e_shots.json` | stick_figure 组 01_idle/02a/02b shot | ❌ 不改（截图内容自动变正确） |
| `docs/GAME_DESIGN/shandong-wolf/07-STICK-FIGURE-ANIMATION.md` | 腿两段结构图无方向表述 | ❌ 不改 |

### 3.4 数据流影响

```
_build_skeleton() (stick_figure.gd)
    │
    ├── torso/neck/head/arm/sword: _make_limb(..., -Y)  ← 不变（pivot 在顶端，向上正确）
    │
    └── leg_l/leg_r: _make_limb(..., -Y)  → 改为 +Y ◄── 本次修复
            │   hip pivot @ (±4, 0), rotation=0 → 大腿自髋向下 20px
            └── LegKPivot @ (0,-UPPER)  → 改为 (0,+UPPER) ◄── 本次修复
                    └── 小腿 Line2D 向 +Y（膝 pivot 在顶端，向下延伸 20px）
                            ↓
    AnimationPlayer rotation tracks（controller 11 clip，数值零改动）
        LegLPivot:rotation ∈ {0, ±12} → 绕「向下」基准摆动 ✅
        LegKPivot:rotation ∈ {0, 40}  → 摆动相向后屈膝 ✅
```

### 3.5 文档更新清单

- [x] 本 PRD（#704）
- [ ] `docs/DESIGN/683-stick-figure-structure-fix.md` §2.2/§4 勘误（腿/膝 +Y、REST_POSE 语义）
- [ ] `stick_figure_controller.gd` 注释勘误

---

## 4. 方案对比

### 方案 A：腿/膝 Line2D 反向为 +Y（points 反向或 Line2D rotation=PI）

**描述：** 腿的 Line2D 几何从 `(0,-length)` 反转为 `(0,+length)`（实现细节：直接改 points 数据，或在 `_make_limb` 返回后把 Line2D 的 rotation 置 PI——两者等价，points 反向更直白）；`_make_knee_pivot` 的 pivot 位置从 `(0,-UPPER)` 改为 `(0,+UPPER)`，其内部小腿 Line2D 同样 +Y。controller 注释同步勘误。

| 维度 | 评估 |
|------|------|
| 改动范围 | stick_figure.gd ~4–6 行 + controller 注释 1 行 + DESIGN 勘误 |
| 动画影响 | **零**——rotation track 数值/路径全不动，0=向下语义自动成立 |
| 风险 | **Low**——纯几何局部改动；F1/F2 方向无关断言继续通过 |
| 工作量 | 0.5 天（含 E2E 截图验证） |

**Pros：** 最小改动；不动动画数据（无回归面）；语义最直观（0=垂腿）。
**Cons：** 需记得**同时**翻转膝 pivot（漏改则小腿仍向上）；`_make_limb` 仍是无方向参数的工厂（后续新肢体易再踩坑——可接受，骨架已冻结）。

### 方案 B：腿 pivot 默认 rotation=PI（180° 翻转）

**描述：** 保持 Line2D -Y 几何，把 `leg_l/leg_r`（以及 `LegKPivot`）的默认 rotation 设为 PI，使 -Y 几何经翻转后指向 +Y。

| 维度 | 评估 |
|------|------|
| 改动范围 | 髋/膝 pivot 初始化 rotation + **11 个 clip 全部腿/膝 rotation track 数值翻转语义**（idle 0→0 恰好不变，但 move/attack/guard/parry/stagger/stance_break/execute/revive/dead 中腿/膝的 ±12°/40° 值全部需按 PI 偏移重算） |
| 动画影响 | **大**——所有 clip 腿/膝关键帧需重摆；AC2-T3/T5 单测断言的 rotation 值语义变化，测试需同步改 |
| 风险 | **High**——track 数值翻转易漏（parry/revive/dead 等非常用 clip），且单测断言（`absf(absf(hip_contact)-swing_deg)<=0.5`）与几何解耦反而被破坏 |
| 工作量 | 1–2 天 |

**Pros：** 不动 `_make_limb` 几何约定。
**Cons：** 动画数据大面积返工；测试断言语义漂移；与 issue 建议（方案 1）相悖。**不推荐。**

### 方案 C：`_make_limb` 增加 direction 参数（躯干/臂 -Y，腿/膝 +Y）

**描述：** `_make_limb(name, length, width, color, direction := Vector2(0,-1))`，`line.points = [ZERO, direction * length]`；腿/膝调用传 `Vector2(0,1)`；膝 pivot 位置参数化。

| 维度 | 评估 |
|------|------|
| 改动范围 | stick_figure.gd 工厂签名 + 全部调用点（8 处）+ 膝 pivot ~10–14 行 + 注释勘误 |
| 动画影响 | **零**（同方案 A） |
| 风险 | **Low–Med**——签名改动波及 8 个调用点，但均为机械传参 |
| 工作量 | 0.5–1 天 |

**Pros：** 方向语义显式化，杜绝同类错误复发；可读性最好。
**Cons：** 改动面比 A 大（8 调用点）；对已冻结的骨架属于「顺手重构」。

### 推荐

**方案 A（首选）**，理由：

1. **最小改动、最小回归面**：仅腿/膝两处几何 + 膝 pivot 位置，动画数据零触碰——对「一行几何错误」的 bug 修复，改动面应严格限定在错误面；
2. **满足全部 4 条验收标准**：0=垂腿（AC1）、±12° 摆动基准不变（AC2）、长度/比例不变（AC3）、E2E 截图自动正确（AC4）；
3. **与 issue 的修复建议一致**（issue 建议方案 1 = 本方案 A）；
4. 方案 C 的价值（方向参数化）可留作**可选实现细节**：若 implement agent 认为顺带加 direction 参数更清晰，可采纳 C 的写法——两者动画影响等价，本 PRD 允许实现层在 A 与「A+C 合并」间选择（红线：不动动画 track 数值）。

---

## 5. 边界条件与验收标准

### 5.1 验收标准（issue body 4 条 AC → 检查清单）

- [x] **AC1: 静止/idle 时腿从髋自然向下垂（不重叠躯干）**
  - [ ] `stick_figure.gd` 腿/膝 Line2D `points[1].y > 0`（几何断言，§7 实验 1）
  - [ ] idle clip 腿/膝 rotation track 全 0 → 大腿自髋 (0,0) 向 (0,+20)、膝 @ (0,+20) 向 (0,+40)，与躯干 [0,-44] 无重叠区间
- [x] **AC2: 走路时腿在向下基准上 ±12° 摆动**
  - [ ] `_build_move_spec()` 腿髋 track 关键帧数值不变（contact ±12、pass 收 0、膝屈 40）——回归断言复用现有 AC2-T3/T5
  - [ ] 摆动语义：rotation=0 为垂腿基准，±12° 绕向下方向摆动
- [x] **AC3: 头/颈/躯干/手臂比例正常（腿长 40px vs 躯干 44px 保持）**
  - [ ] F1/F2 单测继续通过（长度断言方向无关，`points[1].length()`）
  - [ ] 常量零改动：`BODY_LEG_UPPER/LOWER_LENGTH=20/20`、`BODY_LEG_LENGTH=40`、`BODY_TORSO_LENGTH=44`
- [x] **AC4: E2E 截图（stick_figure 组）腿视觉正确**
  - [ ] `01_idle`：双腿自髋下垂、可见大腿+小腿两段、膝在腿中部
  - [ ] `02a_move_contact`：支撑腿垂直、摆动腿 ±12°
  - [ ] `02b_move_pass`：摆动腿屈膝抬脚（膝弯曲可见）

### 5.2 边界情况（≥5）

1. **facing 翻转**：`scale.x=-1` 镜像时腿几何随节点整体镜像，方向仍向下（scale 翻转不改变局部 points 语义）——无需特判；
2. **膝 pivot 漏改**：若只翻大腿不翻膝 pivot 位置，小腿将从 (0,-20) 向上延伸、大腿从 (0,0) 向下——两段错位；实现时必须**成对**修改（大腿 points + 膝 pivot 位置 + 小腿 points）；
3. **move 摆动对称性**：`LegL=+12/LegR=-12` 镜像对称，翻向后符号语义不变（正=逆时针，从向下基准看仍是前后摆腿）——AC2-T5 符号相反断言继续成立；
4. **屈膝方向**：摆动相膝 `MOVE_KNEE_BEND_DEG=40` 单向向后屈（DESIGN 683 §2.2 约定）——几何翻向后屈膝方向为「向后上方抬小腿」，仍符合步态（脚离地），无需改 track；
5. **revive/dead/execute 躺倒 clip**：这些 clip 的腿 rotation 值（如 revive 摆腿 15°）在向下基准下语义自然成立，无需重摆；
6. **参数校验路径**：`_validate_geometry()` 非法参数回退默认值（负长度等）——只影响长度不影响方向，翻向后回退路径不变；
7. **F2 测试兼容**：`_assert_limb_length` 取 `points[1].length()`——若实现改为 `Line2D.rotation=PI` 写法（points 仍 -Y），测试仍通过，但**推荐 points 反向**使断言语义更真实。

### 5.3 失败路径（≥3）

1. **只改大腿漏改膝**：大腿向下、小腿仍向上 → 腿呈「V 形折返」，E2E 截图可捕获——验收 AC4 兜底；
2. **误改动画 track**：若实现者误以为要同步改 clip rotation 值（方案 B 思路），将破坏 AC2-T3/T5 断言且引入摆动方向错误——红线：**动画 track 数值零改动**；
3. **回归：E2E 截图仍显示重叠**：修复未生效或 worktree 未同步 main——重跑 headless 单测 + E2E 组截图验证。

---

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 |
|------|------|------|
| #574 骨架框架（merged #612） | ✅ 已合并 | 无——本修复在其几何约定上做局部修正 |
| #683 腿两段化结构（merged #694） | ✅ 已合并 | 无——膝 pivot 已存在，只需翻方向 |
| E2E 截图链路（#586/#661/#662/#678） | ✅ 已合并 | 无——stick_figure 组 shot plan 可直接复用 |

### 6.2 阻塞

| 未来工作 | 优先级 | 说明 |
|---------|--------|------|
| #584 战斗数值定稿 | 无阻塞 | 动画几何与数值正交 |
| 原画替换（`set_sprite_slot`） | 无阻塞 | sprite 挂 pivot 下，pivot rotation 语义不变 |

### 6.3 准备清单

- [ ] 确认 `stick_figure.gd` 当前 HEAD 包含 #694 的膝骨架（已确认：`f440434` 在 main）
- [ ] 修复后跑 headless 单测：`shandong-wolf/tests/test_stick_figure_animation.gd`（F1/F2/AC2 全套）
- [ ] 跑 E2E stick_figure 组截图（01_idle/02a/02b）人工裁决

### 6.4 依赖链

```
#574 (骨架+11 态动画, #612) ──► #683 (颈/膝+步态+翻转, #694) ──► #704 (本修复: 腿方向)
                                                                        └──► E2E 截图验证
```

---

## 7. Spike / 实验

> 深度 standard → §7 可选；因本 bug 属视觉缺陷、验收依赖实证，保留 2 个低成本实验（均为验证性，非探索性）。

### 实验 1：腿几何方向断言（单元级）

- **要回答的问题：** 修复后腿/膝 Line2D 是否确实指向 +Y（向下）？
- **方法：** 在 `test_stick_figure_animation.gd` 新增断言：`figure.get_pivot("leg_l")` 的 Line2D `points[1].y > 0`（大腿）、`leg_k_l` 同理、膝 pivot `position.y > 0`；headless 运行。
- **预期结果：** 3 条方向断言全绿；既有 F1/F2/AC2 全绿（无回归）。
- **对方案的影响：** 通过 → 方案 A 几何正确；失败 → 检查膝 pivot 是否漏改。

### 实验 2：E2E 截图视觉裁决（用户/截图级）

- **要回答的问题：** 腿在静止与步态两态下视觉是否自然（不重叠、有膝盖、摆动正确）？
- **方法：** 复用 `shandong-wolf/e2e_shots.json` stick_figure 组（01_idle、02a_move_contact、02b_move_pass），E2E 截图后人工/视觉比对。
- **预期结果：** idle 腿自髋下垂两段可见；contact 支撑腿垂直；pass 摆动腿屈膝抬脚。
- **对方案的影响：** 通过 → AC1/AC2/AC4 达成；失败 → 若方向已对但观感仍怪，交回本 PRD §5.2 边界复核（如屈膝方向）。

---

## 8. 延续上下文（交接给 plan agent）

**系统现状：** shandong-wolf 火柴人骨架由 `stick_figure.gd` 程序化构建（零 tscn），`stick_figure_controller.gd` 持有 11 个 clip 的 rotation 关键帧；`_make_limb()`（:130-135）统一 -Y 延伸是腿重叠躯干的根因；动画 rotation 与 Line2D 几何方向**解耦**——翻几何不翻动画。

**修复要点（实现红线）：**
1. `stick_figure.gd` `_build_skeleton()`：`leg_l/leg_r` 的 Line2D points 改 `(0,+BODY_LEG_UPPER_LENGTH)`；`_make_knee_pivot()` pivot 位置改 `(0,+body_leg_upper_length)` 且小腿 points `(0,+BODY_LEG_LOWER_LENGTH)`（推荐 points 反向写法；可选 `Line2D.rotation=PI`，但 points 反向更直白）；
2. **动画零改动**：controller 11 个 clip 的腿/膝 rotation track 路径与数值一律不动；
3. `stick_figure_controller.gd` L~252 注释勘误：「legs rotation=0 即自然下垂（Line2D 向 +Y）」；
4. `docs/DESIGN/683-stick-figure-structure-fix.md` §2.2/§4 勘误（`(0,-UPPER)` → `(0,+UPPER)`、REST_POSE「0=直立」→「0=自然下垂」）；
5. 常量零改动；tests 零改动（可选新增方向断言，见 §7 实验 1）。

**验证命令：**
```bash
# headless 单测（F1/F2/AC2 全套）
godot --headless --path shandong-wolf -s tests/run_tests.gd
# E2E stick_figure 组截图
# （复用现有 E2E 管线，shot plan 无需改动）
```

**主要风险：** 膝 pivot 漏改导致大腿/小腿错位（§5.2 #2，成对修改即可规避）；误改动画 track（红线 2，禁止）。

**下一步：** plan agent 依据本 PRD 产出 DESIGN（预计改动 2 个 .gd 文件 + 1 个 DESIGN 勘误 + 可选 1 条测试断言）；实现后按 §5.1 清单验收。
