# Design: [Bug] 角色腿画反/与躯干重叠：腿 Line2D 方向修正（-Y → +Y）

> **Parent Issue:** #704（bug / workflow/plan / priority/high / graphics / version/mvp）
> **Agent:** game-plan-agent
> **Date:** 2026-08-21
> **Approach:** PRD §4 **方案 A 确认采纳** —— 腿/膝 Line2D 反向为 +Y（大腿 `points=[ZERO,(0,+UPPER)]`、膝 pivot 移至 `(0,+UPPER)`、小腿 `points=[ZERO,(0,+LOWER)]`），动画 rotation track 路径与数值**零改动**（0=向下自然垂腿语义自动成立）。方案 B（pivot 默认 rotation=PI，11 个 clip 腿/膝 track 全量重摆）否决理由同 PRD §4（High 风险、测试断言语义漂移）；方案 C（`_make_limb` 加 direction 参数）不单独采纳，但 PRD 允许「A+C 合并」作为实现层可选写法 —— 本设计推荐 points 直接反向（最直白、断言语义真实），direction 参数化视为可选重构，红线不变：**动画 track 数值零改动**。
> **Reference PRD:** `docs/PRD/704-leg-direction-fix.md`（research PR #706 已合并 2026-08-21）
> **上游方案:** `docs/DESIGN/683-stick-figure-structure-fix.md` §2.2/§2.3（腿两段化骨架与 REST_POSE —— 本次**勘误其 -Y 几何约定**）；`docs/DESIGN/574-stick-figure-silhouette-animation.md` §2.2（-Y 肢体约定源头，不动）
> **所有权:** `content_ownership: mechanical`（方向几何断言、膝 pivot 位置、注释勘误全部机械可验；**无 taste 环节** —— 动画数值零改动，E2E 截图仅作 AC4 视觉确认，无候选值需用户裁决）
> **深度:** standard（GitHub 无 depth 标签；PRD 头标注 depth: standard）—— 涉及文件 **3**（2 .gd + 1 已有 DESIGN 勘误）+ 可选 1 测试断言；实现子任务 4 项集中于骨架构建单文件、跨 1 子系统 → **不产出 TASKS 文档**（未触发 skill standard 阈值：<10 文件 / <5 独立子系统，照 #704 PRD §3.2「改动量 <10 行」判断）
> **并行上下文:** worktree 隔离（/tmp/wt-plan-704，branch `plan/704-leg-direction-fix`）；**无并行 issue 冲突面** —— 不动 constants.gd（#584 数值 DRAFT 区零触碰）、不动 e2e_shots.json（shot plan 无增删）；`mini-pong/`、`.github/workflows/`、`scripts/`、`framework/` 零影响
> **红线:** 只动 PRD §3.1 列出的 2 个 .gd 文件 + DESIGN #683 勘误；**动画 track 路径与数值零改动**（controller 11 个 clip 的腿/膝 rotation 关键帧一律不动——AC2-T3/T5 断言依赖）；`constants.gd` 零改动；`e2e_shots.json` 零改动；**不写可运行测试文件**（测试用例描述归本 DESIGN §8，测试代码归 implement agent）；PR body 用 `Parent #704`（不带冒号）

---

## 1. 架构总览

**问题本质是「#574 的 -Y 肢体几何约定 + 腿 pivot 位置语义错配」造成的单点视觉缺陷：** `_make_limb()`（stick_figure.gd:135）统一让 Line2D 自 pivot 向 **-Y（向上）** 延伸 `points=[ZERO,(0,-length)]`。躯干/颈/臂/刀的 pivot 都位于肢体**顶端**（-Y 延伸即「向上生长」），配合 rotation 翻转语义正确；唯独**腿的 pivot（髋）也位于肢体顶端**，但腿的语义是「从髋**向下**延伸」——`leg_l/leg_r` rotation 默认 0，大腿 Line2D 从髋 (0,0) 向 (0,-20) 向上延伸，与躯干线 y∈[0,-44] **整段重叠**，膝 pivot 同样挂在 -Y 侧 `(0,-20)`、小腿再向上 20px，视觉上「大腿根部在胸前」。该错误继承自 #683 DESIGN 自身：§2.2 写 `points=[ZERO,(0,-BODY_LEG_UPPER_LENGTH)]`（-Y 几何）而 §2.3 REST_POSE 表写「LegLPivot 0=直立」——设计与自身约定自相矛盾，PR #694 忠实实现了 -Y 几何，AC 验收集中在步态节奏/姿态差，腿方向漏网。

**设计哲学：一行几何、全动画受益 —— 翻几何不翻动画。** 动画 rotation 与 Line2D 几何方向**解耦**（动画只写 pivot rotation，不写 points），因此把腿/膝几何翻向 +Y 后，rotation 语义「0=向下垂腿」自动成立，11 个 clip 的腿/膝关键帧数值（0 基准、±12° 摆动、40° 屈膝）**零改动**。改动面严格限定在错误面：腿/膝两处 Line2D points + 膝 pivot 位置 + controller 注释勘误 + DESIGN #683 勘误。这是典型「一行几何错误 → 一行几何修复」，不做任何结构性重构。

```text
★ Issue #704 本设计（腿/膝几何方向修正，其余骨架零改动）
┌─────────────────────────────────────────────────────────────────┐
│ 修改前（错误）                    修改后（正确）                     │
│   LegLPivot @(-4,0)               LegLPivot @(-4,0)              │
│   ├─ 大腿: [ZERO,(0,-20)]  ←-Y    ├─ 大腿: [ZERO,(0,+20)] ←+Y   │
│   └─ LegKPivot @(0,-20)  ←-Y      └─ LegKPivot @(0,+20)  ←+Y    │
│       └─ 小腿: [ZERO,(0,-20)]         └─ 小腿: [ZERO,(0,+20)]    │
│   大腿 (0,0)→(0,-20) 与躯干 [0,-44] 重叠  大腿 (0,0)→(0,+20) 自髋下垂 │
│   （大腿根部视觉在胸前）                （膝 @ +20、踝 @ +40 自然两段）  │
│                                                                  │
│ 动画（stick_figure_controller.gd 11 clip，数值零改动）               │
│   LegLPivot:rotation ∈ {0, ±MOVE_SWING_LEG_DEG=12}               │
│     0 = 垂腿基准（原语义「直立」→ 勘误为「自然下垂」）                 │
│   LegKPivot:rotation ∈ {0, MOVE_KNEE_BEND_DEG=40}（摆动相向后屈膝） │
└─────────────────────────────────────────────────────────────────┘
```

### 1.1 既有实现状态（Prior Implementation Status）

| 系统（文件） | Issue | 状态 | 本设计的处理 |
|------|:---:|:---:|------|
| `_make_limb()` 统一 -Y 工厂（`stick_figure.gd`） | #574（#612 merged） | ✅ | **改**：腿/膝调用点几何反向 +Y（工厂本体不动；direction 参数化为可选重构） |
| 腿两段化骨架（膝 pivot，`stick_figure.gd`） | #683（#694 merged） | ✅ | **改**：膝 pivot 位置 `(0,-UPPER)` → `(0,+UPPER)`；小腿 points 反向 +Y |
| 11 态关键帧动画 + REST_POSE（`stick_figure_controller.gd`） | #574/#683 | ✅ | **零改动（数值）**：仅勘误 L~244 摆姿注释 |
| `FRAME_ANIM_*`/`BODY_*` 常量（`constants.gd`） | #574/#683/#584 | ✅ | **零改动**——腿长/摆幅/屈膝常量全部保持 |
| F1/F2 单测（`test_stick_figure_animation.gd`） | #574/#683 | ✅ | **零改动（可选增）**：`_assert_limb_length` 用 `points[1].length()` 方向无关 → 继续通过；可选新增 3 条方向断言（§8 Scenario D） |
| E2E stick_figure 组 shot plan（`e2e_shots.json`） | #586/#661/#662/#678 | ✅ | **零改动**——01_idle/02a/02b 截图内容自动变正确 |
| DESIGN #683（`docs/DESIGN/683-*.md`） | #683 | ✅ | **改（勘误）**：§2.2 腿/膝几何 -Y → +Y；§2.3 REST_POSE「0=直立」→「0=自然下垂」 |

### 1.2 核心缺口与修复决策（codebase 勘探确认）

| PRD 断言 | 实际代码 | 结论 |
|---------|---------|------|
| `_make_limb()` 统一让 Line2D 向 -Y 延伸 | `stick_figure.gd:135` `line.points = PackedVector2Array([Vector2.ZERO, Vector2(0, -length)])` ✓ | 属实——根因工厂 |
| 腿 pivot 默认 rotation=0 → 大腿自髋向 -Y 与躯干重叠 | `stick_figure.gd:110-121` `leg_l.position=(-4,0)`、`leg_r.position=(4,0)`，rotation 默认 0；躯干线 y∈[0,-44] → 大腿 (0,0)→(0,-20) 整段重叠 ✓ | 属实——修复本体 |
| 膝 pivot 也在 -Y 侧，小腿同样向上 | `_make_knee_pivot()`（:143-146）`knee.position = Vector2(0, -body_leg_upper_length)` ✓ | 属实——须成对修改 |
| controller 注释「legs rotation=0 即直立」与实现矛盾 | `stick_figure_controller.gd:244` 摆姿注释块「肢体 Line2D 自 pivot 向 -Y 延伸（…legs rotation=0 即直立）」——按 -Y 几何 rotation=0 的腿指向 -Y（向上叠躯干）✓ | 属实——注释勘误 |
| 修复后 MOVE ±12° 摆动基准不变（0=向下） | `constants.gd:137` `MOVE_SWING_LEG_DEG=12.0`；`_build_move_spec()`（controller :290-293）只写 pivot rotation；动画与 Line2D 几何方向解耦 ✓ | 前提成立——几何翻向 +Y 后 rotation 语义「0=向下」成立，track 数值零改动 |
| F1/F2 测试方向无关，翻向后继续通过 | `test_stick_figure_animation.gd:480-486` `_assert_limb_length` 取 `points[1].length()`（不检查方向）✓ | 属实——回归面为零 |
| 错误继承自 DESIGN #683 自身矛盾 | `docs/DESIGN/683-*.md:116-118` 腿 Line2D `points=[ZERO,(0,-UPPER)]`、膝 pivot @ `(0,-UPPER)`；:137 REST_POSE 表「LegLPivot 0=直立」✓ | 属实——DESIGN 勘误一并交付 |

> **与 PRD 的差异说明（0 处）：** 本设计全项采纳 PRD §4 方案 A。唯一实现层自由度（PRD 明确允许）：`_make_limb` 是否顺带加 direction 参数（A+C 合并写法）由 implement agent 决定——本设计推荐 points 直接反向（约 4–6 行），不强制参数化。

---

## 2. 新几何规格（腿/膝 +Y）—— 详细设计

> 本 issue **无全新 .gd 文件**（PRD §3.2：不拆 `stick_figure_leg.gd`，改动量 <10 行）。以下为修改后的目标几何规格。

### 2.1 大腿 Line2D 反向 +Y

- **归属文件:** `shandong-wolf/gdscripts/stick_figure.gd`（`_build_skeleton()` 中 `leg_l`/`leg_r` 构造处）
- **目标几何:** 大腿 Line2D `points = [Vector2.ZERO, Vector2(0, +body_leg_upper_length)]`（原 `(0, -…)`）
- **推荐实现写法（A）:** `_make_limb` 返回 pivot 后取其子 Line2D 反向 points：
  ```gdscript
  var leg_l: Node2D = _make_limb("LegLPivot", body_leg_upper_length, body_limb_width, C.BODY_COLOR)
  leg_l.position = Vector2(-4, 0)
  _reverse_limb(leg_l)                      # 新增私有辅助: 子 Line2D points[1].y → +length
  leg_l.add_child(_make_knee_pivot("LegKPivot", body_leg_lower_length))
  ```
  （`_reverse_limb` 为可选辅助函数：取第一个 Line2D 子节点，`points[1] = Vector2(0, points[1].length())`；或直接内联两行赋值。）
- **可选写法（A+C 合并，PRD 允许）:** 给 `_make_limb` 增加 `direction: Vector2 = Vector2(0, -1)` 参数，`points = [ZERO, direction * length]`；腿/膝调用传 `Vector2(0, 1)`。改动面大（8 调用点）但方向语义显式化。**二选一即可，动画影响等价。**
- **等价但禁用写法:** 保持 points -Y 而设 `Line2D.rotation = PI` —— 视觉等价但 `_assert_limb_length` 断言语义失真（PRD §5.2 #7 明示推荐 points 反向）。
- **rotation 语义（修改后）:** `LegLPivot:rotation = 0` → 大腿自髋 (0,0) 向 (0,+20) 自然下垂；±`MOVE_SWING_LEG_DEG` 绕「向下」基准前后摆动。

### 2.2 膝 pivot 位置 + 小腿 Line2D 反向 +Y

- **归属文件:** `shandong-wolf/gdscripts/stick_figure.gd`（`_make_knee_pivot()`，:143-146）
- **目标几何:**
  - `knee.position = Vector2(0, -body_leg_upper_length)` → **`Vector2(0, +body_leg_upper_length)`**（膝 pivot 移到 +Y 侧，即大腿末端）
  - 膝 pivot 内部小腿 Line2D 同大腿反向：`points = [ZERO, (0, +body_leg_lower_length)]`
- **rotation 语义（修改后）:** `LegKPivot:rotation = 0` → 小腿自膝 (0,+20) 向 (0,+40) 下垂，膝在腿中部；摆动相 `MOVE_KNEE_BEND_DEG=40` 单向向后屈（小腿向后上方抬，脚离地）。
- **修改后节点树（左右对称，pivot 名不变 → `get_pivot("leg_l"/"leg_r"/"leg_k_l"/"leg_k_r")` 契约兼容）:**

```text
LegLPivot (Node2D @ (-4,0))  ← 髋 pivot（名不变）
├── Line2D 大腿: points=[ZERO, (0,+BODY_LEG_UPPER_LENGTH=20)]   ← -Y → +Y
└── LegKPivot (Node2D @ (0,+20))  ← 位置 -Y → +Y（名 leg_k_l）
    └── Line2D 小腿: points=[ZERO, (0,+BODY_LEG_LOWER_LENGTH=20)]  ← -Y → +Y
```

- **集成注意:** 修改后踝点世界坐标 = 髋 (0,0) → 膝 (0,+20) → 踝 (0,+40)，与躯干 y∈[0,-44] 无重叠区间（AC1）；腿总长 40px 不变（AC3）。

---

## 3. 既有组件修改

### 3.1 `shandong-wolf/gdscripts/stick_figure.gd`（骨架构建 —— 修复本体）

| 位置 | 变更 | 伪代码 |
|------|------|--------|
| `_build_skeleton()` leg_l/leg_r 构造（:110-121） | 大腿 Line2D points 反向 +Y | `line.points = [Vector2.ZERO, Vector2(0, +body_leg_upper_length)]`（或经 `_reverse_limb` 辅助） |
| `_make_knee_pivot()`（:143-146） | 膝 pivot 位置 `(0,-UPPER)` → `(0,+UPPER)`；小腿 points 反向 +Y | `knee.position = Vector2(0, +body_leg_upper_length)`；`line.points = [ZERO, Vector2(0, +shin_length)]` |
| （可选）`_make_limb()`（:130-135） | 加 `direction` 参数（A+C 合并写法，可选） | `func _make_limb(name, length, width, color, direction := Vector2(0,-1)) -> Node2D:` / `line.points = [ZERO, direction * length]` |

> **红线提醒（PRD §8）:** 躯干/颈/臂/刀调用点**不动**（pivot 在顶端，-Y 正确）；`leg_l.position = Vector2(-4,0)`、`leg_r.position = Vector2(4,0)` 髋间距**不动**。

### 3.2 `shandong-wolf/gdscripts/stick_figure_controller.gd`（注释勘误）

| 位置 | 变更 | 原因 |
|------|------|------|
| L~244 摆姿注释块（`# ── clip 摆姿规格` 上方两行） | 「肢体 Line2D 自 pivot 向 -Y 延伸（arms/sword rotation≈180° 即自然下垂；legs rotation=0 即直立）」→ **「肢体 Line2D 自 pivot 向 ±Y 延伸（躯干/颈/臂/刀 -Y；腿/膝 +Y —— legs rotation=0 即自然下垂）」** | 消除注释与实现的矛盾（issue 指控 #3）；「直立」表述只在 +Y 几何下成立 |

> **红线:** 11 个 clip 的腿/膝 rotation track 路径（`LegLPivot:rotation`、`LegLPivot/LegKPivot:rotation` 等）与关键帧数值**一律不动**（含 idle/move/attack/guard/parry/stagger/stance_break/execute/revive/dead）。

### 3.3 `docs/DESIGN/683-stick-figure-structure-fix.md`（设计文档勘误）

| 位置 | 变更 | 原因 |
|------|------|------|
| §2.2 膝关节点节点结构图（:116-118） | 大腿 `points=[ZERO,(0,-UPPER)]` → `(0,+UPPER)`；膝 pivot `@ (0,-UPPER)` → `@ (0,+UPPER)`；小腿同反向 | 勘误 -Y 几何约定（错误源头之一） |
| §2.3 REST_POSE 表（:137） | 「LegLPivot/LegRPivot \| 0 \| 直立」→「0 \| 自然下垂（Line2D 向 +Y）」；膝行同理 | 勘误与几何矛盾的语义表述 |

> **原因:** PRD §1.1 预调查关键发现——错误继承自 DESIGN #683 自身（-Y 几何与 REST_POSE「直立」表述自相矛盾）。实现修复的同时勘误设计文档，防止后续 issue 再次继承错误约定。

### 3.4 测试文件（implement 期可选，本阶段只描述不落盘）

| 文件 | 变更性质 | 说明 |
|------|---------|------|
| `shandong-wolf/tests/test_stick_figure_animation.gd` | 零改动（既有 F1/F2 方向无关断言继续通过）；**可选新增** 3 条方向断言 | §8 Scenario D：`leg_l`/`leg_k_l` Line2D `points[1].y > 0` + 膝 pivot `position.y > 0`；新增为推荐（AC1 回归保障），缺失不阻塞（F2 已锁长度） |

### 3.5 文件变更汇总

- **修改文件（3）:** `stick_figure.gd`（骨架几何 +Y）、`stick_figure_controller.gd`（注释勘误）、`docs/DESIGN/683-stick-figure-structure-fix.md`（几何/REST_POSE 勘误）
- **新文件（0）:** 无（不拆 `stick_figure_leg.gd`）
- **删除/弃用文件（0）:** 无
- **受影响测试文件（1，可选增）:** `test_stick_figure_animation.gd`（方向断言 3 条，implement agent 自决）

---

## 4. 数据流

**Flow 1: 骨架构建（正常路径 —— 修复后）**
```text
_build_skeleton() (stick_figure.gd)
    ├── torso/neck/head/arm/sword: _make_limb(..., -Y)  ← 不变（pivot 在顶端，向上正确）
    └── leg_l/leg_r: _make_limb(..., +Y) ◄── 本次修复
            │   髋 pivot @ (±4,0), rotation=0 → 大腿自髋向下 (0,+20)
            └── LegKPivot @ (0,+20) ◄── 本次修复（原 -20）
                    └── 小腿 Line2D 向 +Y（膝 pivot 在顶端，向下延伸 (0,+40)）
```

**Flow 2: 动画 rotation（零改动路径 —— 解耦验证）**
```text
controller 11 clip 腿/膝 rotation track（数值/路径零改动）
    LegLPivot:rotation ∈ {0, ±MOVE_SWING_LEG_DEG=12}
    LegKPivot:rotation ∈ {0, MOVE_KNEE_BEND_DEG=40}
        │  动画只写 pivot rotation，与 Line2D 几何方向解耦
        ▼
    几何翻向 +Y 后: rotation=0 → 大腿自髋向下（AC1 垂腿）
    ±12° → 绕「向下」基准前后摆动（AC2 步态）
    40° → 摆动相向后屈膝抬脚（AC2 抬脚离地）
```

**Flow 3: facing 翻转（正交路径 —— 不受影响）**
```text
CombatEntity.facing / EnemyAI.facing → StickFigure.scale.x（#683 已接线）
    │  scale.x=-1 镜像整个节点子树
    ▼
    Line2D 局部 points 语义不变（+Y 仍是「向下」），镜像后腿仍自髋向下（§5 #1）
```

---

## 5. 边界情况与错误处理

| # | 边界情况 | 处理 |
|---|---------|------|
| 1 | facing 翻转（scale.x=-1） | 镜像作用于整个子树，Line2D 局部 points 语义不变，腿仍向下——无需特判（#683 正交） |
| 2 | **膝 pivot 漏改**（只翻大腿） | 大腿 (0,0)→(0,+20)、小腿 (0,-20)→(0,-40) 向上 → 两段错位呈「V 形折返」。**必须成对修改**（大腿 points + 膝 pivot 位置 + 小腿 points，三处一体）；§8 Scenario D 方向断言兜底 |
| 3 | move 摆动对称性 | `LegL=+12/LegR=-12` 镜像对称，翻向后符号语义不变（正=逆时针，从向下基准看仍是前后摆腿）——AC2-T5 符号相反断言继续成立 |
| 4 | 屈膝方向（摆动相 40°） | 单向向后屈（DESIGN 683 §2.2 约定），翻向后为「向后上方抬小腿」，仍符合步态（脚离地）——track 数值不用改 |
| 5 | revive/dead/execute 躺倒 clip | 这些 clip 的腿 rotation 值（如 revive 摆腿 15°）在「向下基准」下语义自然成立——无需重摆 |
| 6 | `_validate_geometry()` 参数校验 | 非法参数回退默认值只影响**长度**不影响**方向**——回退路径不变，翻向后无新分支 |
| 7 | F2 测试兼容 | `_assert_limb_length` 取 `points[1].length()` 方向无关——翻向后继续通过；若实现误用 `Line2D.rotation=PI` 写法测试也过，但推荐 points 反向使断言语义真实 |

**失败路径（≥3）:**

| # | 失败场景 | 兜底 |
|---|---------|------|
| 1 | 只改大腿漏改膝 | 腿呈 V 形折返，E2E 截图（AC4）+ 方向断言（Scenario D）捕获 |
| 2 | 误改动画 track（方案 B 思路） | AC2-T3/T5 断言破坏 + 摆动方向错误——红线：**动画 track 数值零改动**，code review 检查 |
| 3 | 修复未生效（E2E 仍重叠） | worktree 未同步 main 或几何未翻——重跑 headless 单测 + E2E 组截图验证 |

---

## 6. 集成点

> **状态约定:** ⬜ = 待实现（implement agent 接线）；✅ = 已连接（implement agent 验证后更新）。review agent 在 merge 前核对全部 ⬜ 已解决或显式延后。

| 集成 | 我们的组件 | 目标 Issue | 方式 | 状态 |
|-------------|:---:|:---:|-----|:---:|
| 大腿几何反向 | `stick_figure.gd` `_build_skeleton()` | #704 | `leg_l`/`leg_r` Line2D points `(0,-UPPER)` → `(0,+UPPER)` | ✅ 已连接 |
| 膝 pivot 位置 + 小腿反向 | `stick_figure.gd` `_make_knee_pivot()` | #704 | `knee.position` `(0,-UPPER)` → `(0,+UPPER)`；小腿 points +Y | ✅ 已连接 |
| 摆姿注释勘误 | `stick_figure_controller.gd` L~244 | #704 | 「legs rotation=0 即自然下垂（腿/膝 Line2D 向 +Y）」 | ✅ 已连接 |
| DESIGN #683 勘误 | `docs/DESIGN/683-*.md` §2.2/§2.3 | #704 | 腿/膝几何 -Y → +Y；REST_POSE「直立」→「自然下垂」 | ✅ 已连接 |
| 方向断言（可选） | `test_stick_figure_animation.gd` | #704 | 新增 3 条 `points[1].y > 0` / `position.y > 0` 断言 | ✅ 已连接（推荐） |

---

## 7. 实现阶段

| 阶段 | 优先级 | 组件 | 估计 |
|:-----:|:--------:|-----------|:--------:|
| Phase 1 | P0 | `stick_figure.gd` 骨架几何反向（大腿 + 膝 pivot + 小腿三处一体） | 0.25 天 |
| Phase 2 | P0 | `stick_figure_controller.gd` 注释勘误 + `docs/DESIGN/683` 勘误 | 0.1 天 |
| Phase 3 | P0 | （可选）方向断言 3 条 + headless 单测 + E2E 截图验证 | 0.15 天 |

> 合计约 0.5 天（与 PRD §4 方案 A 估计一致）。单依赖链：Phase 1 → Phase 3 验证；Phase 2 可与 Phase 1 并行。

---

## 8. 测试用例描述

> 只描述测试场景，不写可运行代码（测试代码归 implement agent）。

### Scenario AC1: 静止/idle 垂腿（issue AC1）

- **T1（几何方向断言）:** 构造 `StickFigure` 后取 `get_pivot("leg_l")`/`get_pivot("leg_r")` 的子 Line2D，断言 `points[1].y > 0`（大腿自髋向下）；膝 pivot `leg_k_l`/`leg_k_r` 断言 `position.y > 0` 且其子 Line2D `points[1].y > 0`（小腿向下）。前置：`_ready()` 完成。预期：3×2 条方向断言全绿。
- **T2（idle 垂腿无重叠）:** play `anim_idle` 首帧，计算大腿/小腿线段世界坐标（髋 (0,0)→膝 (0,+20)→踝 (0,+40)）与躯干线段（y∈[0,-44]），断言无 y 区间重叠。前置：controller 装配完成。预期：腿完全位于躯干下方（AC1「腿从髋自然向下垂」）。
- **T3（膝位置）:** 断言 `leg_k_l.position == Vector2(0, +BODY_LEG_UPPER_LENGTH)`（膝在腿中部 +20 处）。预期：膝在腿中部，两段可见。

### Scenario AC2: move 步态摆动基准（issue AC2）

- **T4（摆动基准不变）:** 复用既有 AC2-T3（hip contact 摆幅 ±`MOVE_SWING_LEG_DEG`）与 AC2-T5（LegL/LegR 符号相反）——**断言 clip rotation 关键帧数值，与几何方向无关**，翻向后必须继续全绿。前置：几何已反向。预期：数值断言零改动通过（回归红线验证）。
- **T5（屈膝语义）:** 摆动相（pass）膝 rotation = `MOVE_KNEE_BEND_DEG`（40°），contact 膝 = 0。前置：`_build_move_spec()` 未改动。预期：track 数值不变（验证「动画零改动」红线）。

### Scenario AC3: 比例保持（issue AC3）

- **T6（长度不变）:** 既有 F1/F2 全套（`_assert_limb_length`：腿 `BODY_LEG_UPPER/LOWER_LENGTH=20/20`、总长 40、躯干 44）继续通过。前置：constants.gd 零改动。预期：F1（pivot 树 10 节点）+ F2（长度/宽度断言）全绿——验证「只改方向不改长度」。

### Scenario D: 方向几何断言（新增，推荐）

- **T7（三处一体方向）:** 同 T1 的 6 条方向断言合并为独立用例（或并入 F2 后段）。前置：几何反向完成。预期：全绿；若红 → 定位膝 pivot 漏改（失败路径 #1 兜底）。

### Scenario R: 回归

- **T8（全量单测）:** `godot --headless --path shandong-wolf -s tests/run_tests.gd` 全绿（含 F1/F2/AC1-AC3/C1-C2/E1-E3 既有全套，零修改）。
- **T9（E2E 截图）:** stick_figure 组 01_idle / 02a_move_contact / 02b_move_pass 截图产出；人工裁决：idle 双腿自髋下垂两段可见、contact 支撑腿垂直、pass 摆动腿屈膝抬脚（AC4）。

---

## 9. 验收条件映射（issue body + PRD §5.1）

| # | 验收条件 | 设计落点 | 验证方式 |
|---|---------|---------|---------|
| AC1 | 静止/idle 时：腿从髋自然向下垂（不重叠躯干） | §2.1/§2.2（腿/膝几何 +Y）+ §3.1 | T1/T2/T3（方向 + 无重叠断言）+ T9（E2E idle 截图） |
| AC2 | 走路时：腿在向下基准上 ±12° 摆动（步态自然） | §2.1 rotation 语义（0=下垂，±12° 绕向下基准）+ 动画零改动 | T4/T5（clip 数值断言零改动回归）+ T9（E2E contact/pass） |
| AC3 | 头/颈/躯干/手臂比例正常（腿长 40px vs 躯干 44px 保持） | 只改方向不改长度（§3.1 无常量变更） | T6（F1/F2 长度断言）+ diff 守卫（constants.gd 零改动） |
| AC4 | E2E 截图（stick_figure 组）腿视觉正确 | 几何修复自动反映到既有 shot plan（§1.1 e2e_shots.json 零改动） | T9（E2E 截图人工裁决） |

---

## 10. 明确不修改（与 PRD §3.3/§8 红线对齐）

- ❌ `shandong-wolf/gdscripts/constants.gd`（`BODY_LEG_UPPER/LOWER_LENGTH=20/20`、`BODY_LEG_LENGTH=40`、`MOVE_SWING_LEG_DEG=12`、`MOVE_KNEE_BEND_DEG=40` 等零改动——#584 数值 DRAFT 区保护）
- ❌ `stick_figure_controller.gd` 全部 11 个 clip 的腿/膝 rotation **track 路径与关键帧数值**（只勘误 L~244 注释；动画数据零改动是红线）
- ❌ `stick_figure.gd` 躯干/颈/臂/刀构造与 `_make_limb()` 工厂本体（-Y 约定对它们是正确语义；direction 参数化为可选，不做强制重构）
- ❌ `combat_entity.gd` / `combat_judge.gd` / `enemy_ai.gd` / `player_controller.gd` / `main_battle.gd`（战斗闭环与装配 #575/#577/#585 交付物，facing 接线 #683 已合，零改动）
- ❌ `shandong-wolf/e2e_shots.json`（stick_figure 组 shot plan 无增删，截图内容自动变正确）
- ❌ `project.godot`、`game-env/manifest.yaml`、`mini-pong/`、`.github/workflows/`、`scripts/`、`framework/`（跨游戏/管线红线）
- ❌ 任何贴图 / Sprite2D 美术资产（零美术资产红线；原画接入点 `set_sprite_slot` 保持预留）
- ❌ 任何可运行测试文件（本阶段只产出 DESIGN 文档 + 测试用例描述；测试代码归 implement agent）
- ✅ 既有 `test_stick_figure_animation.gd` F1/F2/AC2 全套零改动继续通过（可选新增方向断言归 implement agent 自决）
