# Design: [Bug] 敌人出生点距玩家仅 60px（< HITBOX_RANGE 80px）——出生即在攻击范围内，挥剑空气命中

> **Parent Issue:** #713（bug / workflow/plan / priority/high / gameplay / version/mvp）
> **Agent:** game-plan-agent
> **Date:** 2026-08-21
> **Approach:** PRD §4 **方案 A 确认采纳** —— 仅改 `battle_stage.tscn` 中 EnemySpawnA 坐标 `Vector2(700,560)` → `Vector2(1000,560)`（距玩家 360px，余量 4.5×HITBOX_RANGE），并新增 1 条出生间距测试断言（> HITBOX_RANGE + 50px 硬门槛）。方案 B（HITBOX_RANGE 调至 50-60）否决理由同 PRD §4（前提误判——80 本就是 SWORD_LENGTH=88 派生近似，且破坏 ENEMY_ATTACK_RANGE=80 双向对称）；方案 C（A+B 组合）否决理由同 PRD §4（不对称问题仍在，改动面失控）。
> **Reference PRD:** `docs/PRD/713-enemy-spawn-distance-hitbox.md`（research PR #714 已合并 2026-08-21）
> **上游方案:** `docs/DESIGN/583-*`/GDD `14-SCENE-BATTLE-STAGE.md`（出生点 Marker2D ×3 + .tscn 声明式坐标契约）；`docs/DESIGN/585-*`（main_battle.gd 消费 spawn 定位 + waypoints 数据源）；`docs/DESIGN/703-enemy-ai-driver-wiring.md`（#710 已交付——运行时驱动链，AC3 前提）；`docs/DESIGN/581-enemy-ai.md`（Chase 停距 ENEMY_ATTACK_RANGE=80 契约）
> **所有权:** `content_ownership: mechanical`（出生点坐标 + 间距断言 = 纯机械工程，可自动验证；**无 taste 环节** —— 360px 出生距离的观感归用户 E2E 截图裁决，本设计不预判）
> **深度:** standard（GitHub 无 depth 标签；PRD 头标注 depth: standard）—— 涉及文件 **2**（1 .tscn 坐标 + 1 测试断言）+ 2 项实现子任务同属场景布局单子系统 → **不产出 TASKS 文档**（skill standard 阈值未触发：文件 <10、无迁移、子任务 <5 且不跨子系统，照 #704 先例）
> **并行上下文:** worktree 隔离（/tmp/wt-plan-713，branch `plan/713-enemy-spawn-distance-hitbox`）；**无并行 issue 冲突面**（2026-08-21 核验：零 open PR，无其他分支触碰 `battle_stage.tscn`）；**#584（OPEN, status/human-review）并行定稿 DRAFT 数值** —— 本设计零新增常量、零数值裁决（HITBOX_RANGE/ENEMY_ATTACK_RANGE 冻结只读）；`mini-pong/`、`.github/workflows/`、`scripts/`、`framework/`、`game-env/manifest.yaml` 零影响
> **红线:** 只动 PRD §3.1 列出的 2 文件；**生产改动仅 1 处**（`battle_stage.tscn` EnemySpawnA 坐标）；`constants.gd`（HITBOX_RANGE=80 / ENEMY_ATTACK_RANGE=80 / ENEMY_SENSE_RANGE_PX=600 全部冻结）；`combat_judge.gd`（距离挥空判定逻辑零改动）；`enemy_ai.gd`/`enemy_ai_states.gd`/`main_battle.gd`（行为/装配契约零改动）；`e2e_shots.json` 零改动；**不写可运行测试文件**（测试用例描述归本 DESIGN §8，测试代码归 implement agent）；PR body 用 `Parent #713`（不带冒号）

---

## 1. 架构总览

**问题本质是「出生布局与攻击判定范围的错配」，而非判定层 bug：** 玩家出生点 `PlayerSpawn=(640,560)` 与敌人出生点 `EnemySpawnA=(700,560)` **相距仅 60px**，而 `combat_judge.gd:85` 的距离挥空判定阈值为 `HITBOX_RANGE=80px`（纯 X 轴：`|defender.x - attacker.x| > 80 → 挥空`）。60 < 80 → **敌人出生即在玩家攻击范围内** → 开局不移动挥剑即判定命中 → 用户感知「空气命中」。根因在输入侧（出生布局），不在判定侧——判定逻辑本身正确（>80 挥空），`HITBOX_RANGE=80` 是 #575/#577 按只狼「刀长近身判定」+ `SWORD_LENGTH=88` 派生的正确值。

**设计哲学：修布局不修判定 —— 一行坐标消除充分条件，判定契约整体冻结。** bug 的充分必要条件是「出生间距 ≤ 判定范围」；把间距改为 360px（> 80px）直接消除充分条件，判定层无需任何改动。同时 `HITBOX_RANGE=80 = ENEMY_ATTACK_RANGE=80` 是 #575/#577/#581/#703 共同建立的**双向对称接战距离契约**（玩家 80px 打得到、敌人停 80px 出招），方案 A 完全冻结该契约——这是选择方案 A 而非 B/C 的决定性理由。

```text
★ Issue #713 本设计（EnemySpawnA 坐标 700 → 1000，其余零改动）
┌─────────────────────────────────────────────────────────────────┐
│ 修改前（错误）                    修改后（正确）                     │
│   PlayerSpawn   @ (640,560)       PlayerSpawn   @ (640,560)      │
│   EnemySpawnA   @ (700,560)       EnemySpawnA   @ (1000,560)     │
│     │dx| = 60px < HITBOX_RANGE=80   │dx| = 360px > HITBOX_RANGE=80│
│   → 开局挥剑即命中（空气命中）        → 开局挥剑挥空（AC1 ✓）          │
│   waypoints = [700, 1720]          waypoints = [1000, 1720]（自动跟随）│
│   HITBOX_RANGE=80 = ENEMY_ATTACK_RANGE=80（冻结，零改动）           │
└─────────────────────────────────────────────────────────────────┘
```

### 1.1 既有实现状态（Prior Implementation Status）

| 系统（文件） | Issue | 状态 | 本设计的处理 |
|------|:---:|:---:|------|
| 出生点 Marker2D ×3（`battle_stage.tscn`，PlayerSpawn 640 / EnemySpawnA 700 / EnemySpawnB 1720） | #583（#646 merged）/ GDD 14 | ✅ | **改**：EnemySpawnA 坐标 `(700,560)` → `(1000,560)`（唯一生产改动；.tscn 声明式坐标 = 唯一事实源） |
| `HITBOX_RANGE=80.0`（`constants.gd:306`） | #575/#577 | ✅ | **零改动**（冻结）——值本身正确，非 bug 源 |
| 距离挥空判定（`combat_judge.gd:85` `absf(dx) > C.HITBOX_RANGE → 挥空`） | #577/#626 | ✅ | **零改动**——逻辑正确，问题在输入布局 |
| spawn→定位+waypoints（`main_battle.gd:181-188` `enemy.position = spawn_a.position`、`waypoints=[spawnA, spawnB]`） | #585（#666 merged） | ✅ | **零改动**——直接消费 .tscn 坐标，改坐标自动跟随 |
| Chase 停距 `ENEMY_ATTACK_RANGE=80`（`enemy_ai_states.gd:132-137`） | #581/#703 | ✅ | **零改动**——与 HITBOX_RANGE 双向对称契约冻结 |
| `ENEMY_SENSE_RANGE_PX=600`（`constants.gd:422`） | #581/#638 | ✅ | **零改动**——感知 600 > 出生距离 360 → 开局即索敌（AC3 前提） |
| B3 出生点布局测试（`test_battle_stage.gd:247`，Marker2D 存在性 + 物件包围盒无交集） | #583/#646 | ✅ | **回归验证**——新坐标 1000 须继续通过 B3（树包围盒 x∈[840,960]，1000 在外）；**新增 B4 间距断言**（§8 Scenario AC1） |
| E2E battle_stage 组 shot plan（`e2e_shots.json`） | #586/#661/#662 | ✅ | **零改动**——CaptureRig 全景模式，无 spawn 坐标依赖（PRD §3.3 已 grep 核验） |

### 1.2 核心缺口与修复决策（codebase 勘探确认）

| PRD 断言 | 实际代码 | 结论 |
|---------|---------|------|
| `battle_stage.tscn`: PlayerSpawn=(640,560)，EnemySpawnA=(700,560) 相距 60px | `battle_stage.tscn:113/116` `Vector2(640,560)` / `Vector2(700,560)`，`|dx|=60` ✓ | 属实——修复本体 |
| `constants.gd`: HITBOX_RANGE=80px | `constants.gd:306` `const HITBOX_RANGE: float = 80.0`；`combat_judge.gd:85` 消费 ✓ | 属实——冻结（非 bug 源） |
| 60 < 80 → 敌人一出生即在攻击范围内 | `main_battle.gd:185` `enemy.position = spawn_a.position`，无出生缓冲校验 ✓ | 属实——无「开局距离」保障层 |
| 建议 1：EnemySpawnA 移到攻击范围外（如 x≥900 距玩家 ≥260px） | `battle_stage.tscn:87` TreeLeft @ (900,560) → **900 与树视觉重叠且落入 B3 树包围盒 x∈[840,960]**；x=1000 规避（距树 100px、距玩家 360px）✓ | 采纳——**定稿 1000**（PRD §7 实验 1 结论） |
| 建议 2：HITBOX_RANGE 调至 50-60 | `constants.gd:304` 注释「80 = SWORD_LENGTH=88 派生近似」；`enemy_ai_states.gd:132-137` `ENEMY_ATTACK_RANGE=80` 对称 ✓ | **否决**——前提误判 + 破坏双向对称（PRD §4 方案 B） |
| 验收：开局挥剑打不到 / 走近后命中 / #703 后 AI 节奏正常 | #710 已合并（AI 驱动链生效）；`test_combat_judge.gd:175` 50px 命中用例存在 ✓ | 属实——§8 逐条保障 |

> **与 PRD 的差异说明（0 处）：** 本设计全项采纳 PRD §4 方案 A + §7 实验 1 定稿坐标 1000。唯一补充（PRD §8 允许的落地选择）：间距断言落在 `test_battle_stage.gd`（与既有 B3 同文件、同属场景布局断言域），不落 `test_main_assembly.gd`。

---

## 2. 新布局规格（EnemySpawnA → (1000,560)）—— 详细设计

> 本 issue **无全新文件**（PRD §3.2：无新 .gd/.tscn）。以下为目标坐标规格与选择论证。

### 2.1 EnemySpawnA 目标坐标

- **归属文件:** `shandong-wolf/scenes/battle_stage.tscn`（`:116` `[node name="EnemySpawnA" type="Marker2D" parent="."]`）
- **目标值:** `position = Vector2(700, 560)` → **`Vector2(1000, 560)`**
- **修改后节点树（坐标表，.tscn 唯一事实源）:**

```text
battle_stage.tscn（Marker2D ×3，本次仅改 EnemySpawnA）
├── PlayerSpawn   (Marker2D @ (640, 560))    ← 零改动
├── EnemySpawnA   (Marker2D @ (1000, 560))   ← (700,560) → (1000,560) ★本次
└── EnemySpawnB   (Marker2D @ (1720, 560))   ← 零改动
```

### 2.2 坐标选择论证（x=1000 定稿理由）

| 维度 | 值 | 论证 |
|------|-----|------|
| 距玩家间距 | **360px**（1000-640） | 余量 **4.5×** HITBOX_RANGE=80；字面满足 AC1「敌人 A 初始在攻击范围外」；距 80px 边界余量 280px |
| TreeLeft 视觉/包围盒 | 树 @ (900,560) | x=900 与树重叠，且落入 B3 测试树包围盒 `Rect2(900-60, 560-150, 120, 300)` = x∈[840,960] → **B3 会红**；x=1000 在盒外（距 100px）→ B3 继续绿 |
| 距 EnemySpawnB | 720px（1720-1000） | 巡逻路径 [1000,1720] 区间 720px，`ENEMY_PATROL_SPEED=80px/s` 下节奏正常（#581 契约） |
| 开局接战耗时 | ~1.56s | (1000-640-80)/`ENEMY_CHASE_SPEED=180` ≈ 1.56s（PRD §7 实验 1：x=1100 需 2.1s 略拖、x=900 与树重叠） |
| StageCamera 视野 | x∈[0,2400] | limits 0-2400、窗口 1280px 中心 1200 → 敌人 A 出生即可见（战斗可读性） |
| 感知前提 | 360 < 600 | `ENEMY_SENSE_RANGE_PX=600` > 出生距离 360 → 开局即索敌 Chase（AC3 成立） |

### 2.3 自动跟随链（零代码改动的下游）

- `main_battle.gd:181-188` 读 `.tscn` 坐标 → `enemy.position = (1000,560)`、`waypoints=[(1000,560),(1720,560)]` —— **自动跟随，无需改代码**（PRD §3.3 核验）
- `enemy_ai.gd` 巡逻/追击 FSM 与坐标解耦（#581/#703 交付物）—— 起点变化不影响行为逻辑

---

## 3. 既有组件修改

### 3.1 `shandong-wolf/scenes/battle_stage.tscn`（唯一生产改动）

| 位置 | 变更 | 伪代码 |
|------|------|--------|
| `:116` EnemySpawnA | `position = Vector2(700, 560)` → `Vector2(1000, 560)` | `[node name="EnemySpawnA" type="Marker2D" parent="."]` 下 `position = Vector2(1000, 560)`（1 行） |

> **红线:** 不动 PlayerSpawn(640,560)、EnemySpawnB(1720,560)、StageCamera、任何物件/碰撞/图层。

### 3.2 `shandong-wolf/tests/test_battle_stage.gd`（新增 1 条断言）

| 位置 | 变更 | 说明 |
|------|------|------|
| B3 之后新增 **B4**（或并入 B3 尾段） | **出生间距断言**：`abs(PlayerSpawn.position.x - EnemySpawnA.position.x) > C.HITBOX_RANGE + 50.0`（硬门槛 ≥130px） | AC1 防回归兜底——任何后续场景编辑把间距缩回 ≤130px 即 CI 红（PRD §5.3 失败路径 1 兜底）；**不写绝对值断言**（避免与具体坐标耦合，只锁间距），与既有 B3「存在性 + 包围盒」风格一致 |

> **零改动文件:** `constants.gd`、`combat_judge.gd`、`enemy_ai.gd`、`enemy_ai_states.gd`、`main_battle.gd`、`e2e_shots.json`、`test_combat_judge.gd`（50px 命中用例继续通过）、`test_main_assembly.gd`（A3 相对定位断言不受影响）。

### 3.3 文件变更汇总

- **修改文件（2）:** `shandong-wolf/scenes/battle_stage.tscn`（1 行坐标）、`shandong-wolf/tests/test_battle_stage.gd`（1 条间距断言）
- **新文件（0）:** 无
- **删除/弃用文件（0）:** 无
- **受影响测试文件（1）:** `test_battle_stage.gd`（新增 B4；B3 回归验证）
- **文档（可选，不阻塞）:** `docs/GAME_DESIGN/shandong-wolf/14-SCENE-BATTLE-STAGE.md`「出生点」条目补一句「间距须 > HITBOX_RANGE」约束（PRD §3.5 建议，implement 阶段顺带）

---

## 4. 数据流

**Flow 1: 开局接战（正常路径 —— 修复后）**
```text
battle_stage.tscn 坐标（唯一事实源）
    ├── PlayerSpawn(640,560)  → main_battle.gd:83-85  player.position = (640,560)
    └── EnemySpawnA(1000,560) → main_battle.gd:181-188 enemy.position = (1000,560)
                                   waypoints = [(1000,560), (1720,560)]
    ▼
enemy_ai.gd _physics_process（#703 驱动链，#710 已合并）
    ├── 感知: |dx|=360 < ENEMY_SENSE_RANGE_PX=600 → 开局即 Chase（AC3）
    └── 逼近: ENEMY_CHASE_SPEED=180px/s → 停距 ENEMY_ATTACK_RANGE=80 出招（~1.56s 接战）
    ▼
combat_judge.gd:85 距离挥空判定（零改动）
    ├── 开局 |dx|=360 > HITBOX_RANGE=80 → 挥空（不发射事件）✓ AC1
    └── 走近 |dx| ≤ 80 → 命中（AC2 不变）
```

**Flow 2: 开局不动挥剑（bug 场景 —— 修复前后对照）**
```text
修复前: 敌人 @700 → |dx|=60 ≤ 80 → 命中 → 空气击杀 ✗
修复后: 敌人 @1000 → |dx|=360 > 80 → 挥空 ✓（视觉未接触 = 无判定）
```

**Flow 3: 巡逻路径（正交路径 —— 自动跟随）**
```text
waypoints = [EnemySpawnA(1000), EnemySpawnB(1720)]（main_battle.gd 读 .tscn 坐标）
    → enemy_ai patrol: 1000 ↔ 1720 ping-pong（#581 契约，720px 区间 @ 80px/s）
```

---

## 5. 边界情况与错误处理

| # | 边界情况 | 处理 |
|---|---------|------|
| 1 | **TreeLeft 视觉/包围盒重叠**（树 @ 900,560） | x=1000 规避：距树 100px；B3 树包围盒 x∈[840,960] 在外 → B3 继续绿（若误选 900，B3 红 + 视觉重叠） |
| 2 | 巡逻路径变化（waypoints [700,1720] → [1000,1720]） | 区间 720px @ `ENEMY_PATROL_SPEED=80px/s` 节奏正常；空数组/单点降级逻辑不受影响（#581 契约） |
| 3 | EnemySpawnB 不变（1720） | 不参与本 bug（MVP 单敌人场景用 A）；距新 A 720px、距玩家 1080px 均合理 |
| 4 | **|dx| 恰为 80 边界** | 命中（`> 80 才挥空`）——符合「80=接战距离契约」设计意图；issue 要求「> 判定范围」不含等于，AC1 的 360px 远超边界 |
| 5 | 攻击窗口 4 帧内位移改变距离 | 开局余量 280px（360-80）；帧内位移 ≤ 300px/s × 0.067s ≈ 20px/帧，4 帧内不可能跨越 280px 净距 |
| 6 | StageCamera 视野 | x=1000 在 limits 0-2400 内、窗口中心 1200 → 敌人 A 出生可见（战斗可读性） |
| 7 | 玩家初始 facing 背对敌人 | `combat_judge.gd:88-92` `rel_dir != w.direction → 挥空` 兜底（不发射事件）——与出生距离正交，零改动 |
| 8 | 玩家感知/索敌不回归（AC3） | 感知 600 > 出生 360 → 开局即 Chase；停距 80px 出招不变（#581/#703 契约零改动） |

**失败路径（≥3）:**

| # | 失败场景 | 兜底 |
|---|---------|------|
| 1 | 坐标改动被后续场景编辑覆盖（并发/手改） | B4 间距断言（> HITBOX_RANGE + 50）CI 兜底，间距缩回 ≤130px 即红（PRD §5.3 失败路径 1） |
| 2 | waypoints 空数组降级（spawn 节点丢失） | `enemy_ai` 原地等待不报错（#581 失败路径 2）——与坐标值无关，不回归 |
| 3 | 并发 agent 改 .tscn 冲突 | worktree 隔离（2026-08-13 红线）+ worktree-commit.sh 冲突分级（机械改动自动合并，无法判断则 abort 报告）；当前零 open PR 无冲突面 |
| 4 | 修复未生效（E2E 仍空气命中） | 重跑 headless 单测（B4 + 全量基线）+ E2E battle_stage 组截图站位验证 |

---

## 6. 集成点

> **状态约定:** ⬜ = 待实现（implement agent 接线）；✅ = 已连接（implement agent 验证后更新）。review agent 在 merge 前核对全部 ⬜ 已解决或显式延后。

| 集成 | 我们的组件 | 目标 Issue | 方式 | 状态 |
|-------------|:---:|:---:|-----|:---:|
| EnemySpawnA 坐标外移 | `battle_stage.tscn` `:116` | #713 | `position = Vector2(700,560)` → `Vector2(1000,560)`（1 行） | ⬜ 待实现 |
| 出生间距断言 | `test_battle_stage.gd`（B4） | #713 | `abs(PlayerSpawn.x - EnemySpawnA.x) > HITBOX_RANGE + 50`（≥130px 硬门槛） | ⬜ 待实现 |
| waypoints 自动跟随验证 | `main_battle.gd:181-188` | #713 | 零改动；验证 `enemy.waypoints == [(1000,560),(1720,560)]`（test_main_assembly A3 相对断言回归） | ⬜ 待验证 |
| 开局索敌节奏 | `enemy_ai.gd` 驱动链（#710 已合） | #703/#713 | 零改动；headless 验证感知→Chase→停距 80px（AC3） | ⬜ 待验证 |
| E2E 站位截图 | `e2e_shots.json` battle_stage 组 | #713 | shot plan 零增删；截图人工裁决敌人 A 在剑弧（SWORD_ARC_RADIUS=70）外 | ⬜ 待验证 |

---

## 7. 实现阶段

| 阶段 | 优先级 | 组件 | 估计 |
|:-----:|:--------:|-----------|:--------:|
| Phase 1 | P0 | `battle_stage.tscn` EnemySpawnA 坐标 (700,560) → (1000,560) | 0.1 天 |
| Phase 2 | P0 | `test_battle_stage.gd` 新增 B4 间距断言（> HITBOX_RANGE + 50） | 0.1 天 |
| Phase 3 | P0 | headless 全量单测（1314 基线 + B4）+ E2E battle_stage 组截图站位验证 + 实机手测 AC1-AC3 | 0.25 天 |

> 合计约 0.45 天（与 PRD §4 方案 A 估计 0.5 天一致）。单依赖链：Phase 1 → Phase 2 → Phase 3。

---

## 8. 测试用例描述

> 只描述测试场景，不写可运行代码（测试代码归 implement agent）。

### Scenario AC1: 开局挥剑打不到敌人（issue AC1 —— 核心回归防护）

- **T1（B4 出生间距断言，新增）:** 实例化 `battle_stage.tscn`，读取 `PlayerSpawn`/`EnemySpawnA` Marker2D 位置，断言 `abs(PlayerSpawn.position.x - EnemySpawnA.position.x) > C.HITBOX_RANGE + 50.0`（即 >130px 硬门槛）。前置：场景可实例化。预期：间距 360px → 断言绿；任何后续编辑把间距缩回 ≤130px 即红（失败路径 1 兜底）。
- **T2（B3 回归）:** 既有 B3 全套（Marker2D ×3 存在性 + 与草屋/枯树包围盒无交集）在新坐标下继续通过。前置：EnemySpawnA=(1000,560)。预期：x=1000 在树包围盒 x∈[840,960] 之外 → B3 绿（若误选 900 则红——B3 兼作坐标选址守卫）。
- **T3（开局挥剑挥空，行为验证）:** headless 模拟或实机：玩家不移动原地挥剑，断言 `combat_judge` 不发射命中事件（挥空路径：`|dx|=360 > 80 → mark resolved + return`）。前置：敌人已按新坐标生成。预期：零命中事件（修复前该用例红——60 ≤ 80 命中）。

### Scenario AC2: 走近到攻击范围后挥剑正常命中（issue AC2）

- **T4（判定层回归，零改动）:** 既有 `test_combat_judge.gd:175` 50px 命中用例（`|dx|=50 ≤ HITBOX_RANGE=80 → 命中`）继续通过。前置：`constants.gd`/`combat_judge.gd` 零改动。预期：全绿——验证「修布局不修判定」红线。
- **T5（走近命中，行为验证）:** 实机手测：玩家移动至敌人 80px 内挥剑 → 正常命中/受击反馈。预期：与修复前一致（AC2 无回归）。

### Scenario AC3: 敌人 AI 追击/接战节奏正常（issue AC3，#703 前提）

- **T6（感知→Chase 起点）:** headless 驱动链（#710）：敌人生成于 (1000,560)，断言 `|dx|=360 < ENEMY_SENSE_RANGE_PX=600` → 开局即进入 Chase 状态（而非 patrol 无感）。前置：`_physics_process` 运行时驱动（#703 已修）。预期：开局即索敌。
- **T7（停距出招契约）:** Chase 逼近后断言敌人停在距玩家 `ENEMY_ATTACK_RANGE=80` 处出招（`enemy_ai_states.gd:132-137` 既有契约）。前置：行为 FSM 零改动。预期：接战节奏 ~1.56s 后进入攻击，不因出生距离变化而异常。

### Scenario R: 回归

- **T8（全量单测）:** `godot --headless --path shandong-wolf -s tests/run_tests.gd` 全绿（现有 1314 单测基线 + B4 新增，零修改既有用例）。前置：constants/combat_judge/enemy_ai/main_battle 零改动。预期：全绿。
- **T9（E2E 站位截图）:** battle_stage 组既有 shot（全景/平台近景/月亮构图，shot plan 零增删）产出；人工裁决：敌人 A 位于玩家右侧 360px、剑弧（`SWORD_ARC_RADIUS=70`）不触及敌人（AC1 视觉证据，交用户 taste 裁决）。

---

## 9. 验收条件映射（issue body + PRD §5.1）

| # | 验收条件 | 设计落点 | 验证方式 |
|---|---------|---------|---------|
| AC1 | 开局挥剑（不移动）打不到敌人（敌人 A 初始在攻击范围外） | §2.1（EnemySpawnA → 1000，间距 360 > 80）+ §3.1 | T1（B4 间距断言）+ T3（挥空行为）+ T9（E2E 站位截图） |
| AC2 | 走近到攻击范围后挥剑正常命中 | 判定层零改动（§3.2 冻结清单） | T4（50px 命中用例回归）+ T5（实机手测） |
| AC3 | 敌人 AI 修复后（#703）追击/接战节奏正常（出生距离不影响 AI 索敌） | 感知 600 > 360 → 开局 Chase（§2.2）+ 行为契约零改动 | T6/T7（headless 驱动链断言）+ 实机观察 ~1.56s 接战 |

---

## 10. 明确不修改（与 PRD §3.3/§8 红线对齐）

- ❌ `shandong-wolf/gdscripts/constants.gd`（`HITBOX_RANGE=80.0`、`ENEMY_ATTACK_RANGE=80.0`、`ENEMY_SENSE_RANGE_PX=600.0`、`SWORD_ARC_RADIUS=70.0` 等零改动——#584 数值 DRAFT 区保护，本 issue 零数值裁决）
- ❌ `shandong-wolf/gdscripts/combat_judge.gd`（距离挥空判定 `:85`、facing 校验 `:88-92`、弹反判定逻辑全部零改动）
- ❌ `shandong-wolf/gdscripts/enemy_ai.gd` / `enemy_ai_states.gd`（#581/#703 行为 FSM、Chase 停距 80px、感知 600px 契约零改动）
- ❌ `shandong-wolf/gdscripts/main_battle.gd`（spawn 消费 + waypoints 自动跟随——改坐标即自动生效，零代码改动）
- ❌ `shandong-wolf/tests/test_combat_judge.gd` / `test_main_assembly.gd`（既有用例零改动继续通过）
- ❌ `shandong-wolf/e2e_shots.json`（battle_stage 组 shot plan 无增删，截图内容自动变正确）
- ❌ `project.godot`、`game-env/manifest.yaml`、`mini-pong/`、`.github/workflows/`、`scripts/`、`framework/`（跨游戏/管线红线）
- ❌ 任何贴图 / Sprite2D / shader 美术资产（零美术资产改动）
- ❌ 任何可运行测试文件（本阶段只产出 DESIGN 文档 + 测试用例描述；测试代码归 implement agent）
- ✅ 既有 `test_battle_stage.gd` B3 全套零改动继续通过（B4 为新增，非改写）
