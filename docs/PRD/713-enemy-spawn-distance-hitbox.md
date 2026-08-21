# PRD #713 — [Bug] 敌人出生点距玩家仅 60px（< HITBOX_RANGE 80px）——出生即在攻击范围内，挥剑空气命中

> **Issue:** #713
> **标签:** bug, workflow/research, priority/high, gameplay, version/mvp（issue 无 `depth/*` 标签，参照 #682/#703 先例取 `depth: standard` → §1–6 + §8 必填；§7 可选，本 PRD 含 3 实验提升交接质量）
> **Agent:** game-research-agent
> **日期:** 2026-08-21
> **所有权:** `content_ownership: mechanical`（出生点坐标/判定距离=机械工程；视觉感受归用户 E2E 裁决）
> **引擎/目录约束:** Godot 4.7.1 / `shandong-wolf/`（manifest `game.active: shandong-wolf` + 默认分支 `main` 单一事实源；本 PRD 全部路径前缀 `shandong-wolf/`，零 `mini-pong/` 写死）
> **研究选项:** Obsidian 知识库已搜索（`/Volumes/Obsidian/Knowledge Ocean/` + `~/Documents/Obsidian Vault/`：wiki/raw grep「攻击距离/命中判定/判定范围/接战/站位」→ **零直接命中**；间接相关 `raw/Bear/JRPG 战斗系统研究 - 最终综合报告.md` 仅「弹反/闪避=时机判定」范式——本次问题本质是**空间判定与出生布局的错配**（空间层），知识库无空间布局/攻击距离设计条目，无直接可用知识）+ 同链 PRD/DESIGN（#583/#585/#682/#703 全读）+ GDD（`docs/GAME_DESIGN/shandong-wolf/14-SCENE-BATTLE-STAGE.md` 出生点契约）+ origin/main 源码实测（e9bba05，battle_stage.tscn / constants.gd / combat_judge.gd / main_battle.gd / enemy_ai_states.gd 逐行核对）
> **来源:** 用户实机验证反馈（2026-08-21）：没有接触敌人，挥剑敌人也会被击毙（空气命中）。#682/#683 合并后回归（E2E 截图只验证视觉状态，未验证行为/站位）。
> **前置依赖:** #583（CLOSED，场景出生点契约）、#585（CLOSED，PR #666 merged，组装消费 spawn 坐标）、#703（CLOSED，PR #710 merged 2026-08-21 —— 敌人 AI 运行时驱动链已生效，本 issue AC3 前提满足）——全部满足

---

## 1. 问题定义

### 1.1 现状（2026-08-21 worktree 侦查 @ origin/main e9bba05）

**一句话现状：** 玩家出生点 `PlayerSpawn=(640,560)` 与敌人出生点 `EnemySpawnA=(700,560)` **相距仅 60px**，而玩家攻击判定 `HITBOX_RANGE=80px`（`combat_judge.gd:85` 纯 X 轴距离判定：`|defender.x - attacker.x| > HITBOX_RANGE → 挥空`）。60 < 80 → **敌人出生即在玩家攻击范围内** → 开局不移动挥剑即判定命中 → 用户感知「空气命中」。敌人被 `main_battle.gd:185` 直接定位在 EnemySpawnA，无任何缓冲距离校验。

| 组件（文件） | Issue | 当前状态 | 与 #713 的差距 |
|------|-------|:-------:|------|
| `scenes/battle_stage.tscn`（PlayerSpawn 640,560 / EnemySpawnA 700,560） | #583/#646 | ✅ 三个 Marker2D 声明式坐标（.tscn 唯一事实源） | ❌ **出生间距 60px < HITBOX_RANGE 80px** —— 无「出生间距 > 攻击判定范围」校验 |
| `gdscripts/constants.gd:306`（HITBOX_RANGE=80.0） | #575/#577 | ✅ 候选集 [60,80,100]，默认 80 = SWORD_LENGTH=88 派生近似（只狼基准「刀长近身判定」） | ⚠️ 值本身合理（与视觉剑长对齐）——**不是 bug 源**，issue 建议 2 的前提误判（见 §4 方案 B） |
| `gdscripts/combat_judge.gd:85`（距离挥空判定） | #577/#626 | ✅ 判定逻辑正确（>80 挥空） | ⚠️ 逻辑无误，问题在**输入布局**（出生距离）而非判定本身 |
| `gdscripts/main_battle.gd:181-188`（spawn→定位+waypoints） | #585/#666 | ✅ enemy.position = spawn_a.position；waypoints=[spawnA, spawnB] | ⚠️ 直接消费 .tscn 坐标（改坐标自动跟随，零代码改动） |
| `gdscripts/enemy_ai_states.gd:132-137`（Chase 停距 ENEMY_ATTACK_RANGE=80） | #581/#703 | ✅ 敌人停 80px 出招 | ✅ 与 HITBOX_RANGE=80 **双向对称**（接战距离契约，方案 B 不可单边破坏） |
| `gdscripts/constants.gd:422`（ENEMY_SENSE_RANGE_PX=600） | #581/#638 | ✅ 感知范围 600px | ✅ 出生距离 360px < 600px → 敌人开局即索敌 Chase（AC3 前提成立） |

### 1.2 预调查表（bug-pre-investigation-workflow §Patch 10）

| Issue 声明 | 预调查结果 |
|-----------|-----------|
| `battle_stage.tscn`: PlayerSpawn=(640,560)，EnemySpawnA=(700,560)——相距 60px | ✅ **属实**（.tscn 实测 Vector2(640,560) / Vector2(700,560)，|dx|=60） |
| `constants.gd`: HITBOX_RANGE=80px（judge 的距离判定） | ✅ **属实**（constants.gd:306 `const HITBOX_RANGE: float = 80.0`；combat_judge.gd:85 消费） |
| 60 < 80 → 敌人一出生就在玩家攻击范围内 → 挥剑（视觉没碰到）判定命中 | ✅ **属实**（纯 X 轴距离判定，无出生缓冲校验；敌人实例化即定位 spawn，无任何「开局距离」保障） |
| 建议 1：拉开出生距离（EnemySpawnA 移到攻击范围外，如 x≥900 距玩家 ≥260px） | ✅ **采纳**——唯一干净方案（§4 方案 A 推荐） |
| 建议 2：HITBOX_RANGE 调至 50-60（与剑视觉长度对齐） | ⚠️ **部分不成立**——HITBOX_RANGE=80 本来就是 SWORD_LENGTH=88 的派生近似（constants.gd:304 注释），已与视觉剑长对齐；且 `ENEMY_ATTACK_RANGE=80`（敌人停距/出招）与之对称，单边调小 → 敌人停 80px 出招、玩家 80px 打不到敌人 → **不对称玩家吃亏**（详见 §4 方案 B） |
| 验收：开局挥剑打不到敌人 / 走近后正常命中 / #703 修复后 AI 节奏正常 | ✅ 本 PRD §5 逐条保障（#703 已 merge #710，AI 索敌已生效） |

**无 stale claims**——issue body 的现象、根因、验收全部与当前代码一致（e9bba05）。

### 1.3 验收条件（issue body 3 条 → 本 PRD 保障）

| # | 验收条件 | 现状 | 本 PRD 保障 |
|---|---------|:----:|------------|
| AC1 | 开局挥剑（不移动）打不到敌人（敌人 A 初始在攻击范围外） | ❌ 开局即命中 | §5.1 AC1：EnemySpawnA 移至 x=1000（距玩家 360px > 80px，余量 4.5×）+ 新增测试断言出生间距 > HITBOX_RANGE |
| AC2 | 走近到攻击范围后挥剑正常命中 | ✅ 判定逻辑正常 | §5.1 AC2：判定层零改动（现有 test_combat_judge 50px 命中用例覆盖） |
| AC3 | 敌人 AI 修复后（#703）追击/接战节奏正常（出生距离不影响 AI 索敌） | ✅ #710 已合并 | §5.1 AC3：感知 600px > 出生距离 360px → 开局即 Chase 逼近（280px @ 180px/s ≈ 1.6s 接战），停距 80px 出招不变 |

### 1.4 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 开局接战（核心闭环） | 每次游玩 | 玩家出生 640 → 敌人 A 出生 1000（相距 360px）→ 敌人开局感知（600px）→ Chase 逼近 → 停距 80px 出招 → 玩家弹反/受击 → 战斗闭环 |
| B | 开局不动挥剑（bug 场景） | 高频复现（现状） | 敌人出生 700（60px）→ 玩家原地挥剑 → 判定 60 ≤ 80 命中 → 空气击杀（修复后：360 > 80 挥空 ✓） |
| C | 敌人 B 参战（备用） | 中频 | EnemySpawnB=1720 不变；A/B 巡逻路径 1000↔1720 ping-pong（#581 waypoints 契约） |

## 2. 设计意图

### 2.1 为什么现状存在

| 原因 | 说明 |
|------|------|
| #583 场景契约只定义「命名」不定义「间距」 | PRD #583 规定 `PlayerSpawn/EnemySpawnA/EnemySpawnB` Marker2D ×3、坐标进 .tscn（§4.5 汇总表），**从未校验「出生间距 > 攻击判定范围」**——GDD 14 同样只写「坐标/尺寸的 .tscn 手填坐标与常量一致」，无双源校验 |
| #585 组装直接消费坐标 | `main_battle.gd:185 enemy.position = spawn_a.position`——场景给什么坐标就用什么，无开局距离保障层 |
| 判定层设计合理但被布局绕过 | HITBOX_RANGE=80 是 #575/#577 按只狼「刀长近身判定」+ SWORD_LENGTH=88 派生的**正确值**；问题在输入侧（出生布局），不在判定侧 |

### 2.2 为什么现在改

1. **回归已实锤**：#682/#683 合并后用户实机验证发现空气命中（E2E 截图未覆盖行为/站位验证——issue body 自述漏网原因）。
2. **#703 已修复 AI**（#710 merged）：敌人现在会主动索敌追击 → 出生距离直接决定接战节奏与开局体验 → 现在修收益最大、改动最小。
3. **改动面极小**：1 行 .tscn 坐标 + 1 条测试断言，零判定契约破坏。

### 2.3 之前约束（保持不破）

| 约束 | 详情 |
|------|------|
| 出生点声明式红线 | GDD 14「坐标 .tscn 声明，禁止脚本写死」——改坐标只动 .tscn，脚本零改动 |
| Marker2D 命名契约 | `PlayerSpawn/EnemySpawnA/EnemySpawnB` ×3 保持不变（test_battle_stage.gd:247 断言存在性） |
| 接战距离双向对称 | HITBOX_RANGE=80 = ENEMY_ATTACK_RANGE=80——**本 PRD 不动任何一方** |
| waypoints 数据源 | EnemySpawnA/B 坐标即 EnemyAI.waypoints（main_battle.gd:179-188）——改坐标自动更新巡逻路径 |

## 3. 影响分析

### 3.1 直接影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `shandong-wolf/scenes/battle_stage.tscn` | 战斗舞台场景 | **修改**：EnemySpawnA `Vector2(700,560)` → `Vector2(1000,560)`（唯一生产改动） |
| `shandong-wolf/tests/test_battle_stage.gd` 或 `test_main_assembly.gd` | 测试 | **新增断言**：PlayerSpawn↔EnemySpawnA 间距 > HITBOX_RANGE + 50px 余量（AC1 防回归） |

### 3.2 新文件

无（测试断言加在现有测试文件；不新增 .gd/.tscn）。

### 3.3 间接影响模块（已核验零改动）

| 文件 | 影响 | 核验 |
|------|------|------|
| `main_battle.gd` | waypoints/定位自动跟随 spawn 坐标 | ✅ 代码读 .tscn 坐标（181-188 行），无需改 |
| `enemy_ai.gd` / `enemy_ai_states.gd` | 巡逻路径起点变化（1000↔1720）；Chase/Attack 逻辑不变 | ✅ 行为 FSM 与坐标解耦 |
| `combat_judge.gd` / `constants.gd` | **判定契约冻结**（HITBOX_RANGE/ENEMY_ATTACK_RANGE 不动） | ✅ 本 PRD 不触碰 |
| `e2e_shots.json`（battle_stage 组） | 截图像具场景 `e2e_battle_stage_capture.tscn` 为 CaptureRig 模式，不依赖 spawn 坐标 | ✅ 已 grep 核验零坐标依赖 |
| `test_combat_judge.gd:175` | 50px 命中用例（`|dx|=50 ≤ HITBOX_RANGE=80`）不受影响 | ✅ 判定层零改动 |

### 3.4 数据流影响（ASCII）

```
battle_stage.tscn 坐标（唯一事实源）
    │
    ├──► main_battle.gd:83-85  Player.position = PlayerSpawn(640,560)
    ├──► main_battle.gd:181-188 enemy.position = EnemySpawnA(1000,560)  +  waypoints=[A(1000),B(1720)]
    │
    ▼
combat_judge.gd:85  距离挥空判定: |defender.x - attacker.x| > HITBOX_RANGE(80) → 挥空
    │
    ├──► 开局 |dx| = 360  → 挥空 ✓（修复后；现状 60 → 命中 ✗）
    └──► 走近 |dx| ≤ 80   → 命中（AC2 不变）
```

### 3.5 文档更新清单

- [x] `docs/PRD/713-enemy-spawn-distance-hitbox.md`（本 PRD）
- [ ] `docs/GAME_DESIGN/shandong-wolf/14-SCENE-BATTLE-STAGE.md` —— 坐标声明在 .tscn，GDD 无需改坐标值；可在「出生点」条目补一句「间距须 > HITBOX_RANGE」约束（可选，建议 implement 阶段顺带）
- [ ] `docs/PROJECT.md` —— 战斗节奏段落提及出生间距 360px（可选）

## 4. 方案比较

### 方案 A：拉开出生距离（EnemySpawnA 700 → 1000，距玩家 360px）

**描述：** 仅改 `battle_stage.tscn` 中 EnemySpawnA 一个坐标。候选 x∈{900, 950, 1000, 1100}（issue 建议 x≥900、距玩家 ≥260px）。**推荐 1000**：距玩家 360px（余量 4.5×）、避开 TreeLeft(900,560) 视觉重叠、距 EnemySpawnB(1720) 720px（巡逻路径合理）、在 StageCamera limits(0-2400) 视野内。

| 维度 | 评估 |
|------|------|
| Pros | ① 1 行 .tscn 改动 + 1 条测试断言，最小改动；② 零判定契约破坏（HITBOX_RANGE/ENEMY_ATTACK_RANGE 双向对称冻结）；③ 字面满足 AC1「敌人 A 初始在攻击范围外」；④ 战斗节奏合理（玩家需主动走近接战，符合 brief「压迫感来源」）；⑤ waypoints 自动跟随，无连锁改动 |
| Cons | EnemySpawnA 需避开 TreeLeft(900) 视觉重叠（选 1000 解决）；开局敌人 Chase 逼近耗时 ~1.6s（280px @ 180px/s），比 60px 时多 1.5s 接战（节奏上更合理而非缺陷） |
| Risk | **Low** |
| Effort | **0.5 天**（坐标 + 测试 + E2E 截图验证） |

### 方案 B：调小 HITBOX_RANGE 至 50-60（issue 建议 2）

**描述：** 修改 `constants.gd:306` HITBOX_RANGE 80 → 50/60，使判定「更保守」、与剑视觉「对齐」。

| 维度 | 评估 |
|------|------|
| Pros | 判定更严苛，挥空更频繁（部分玩家可能认为「更真实」） |
| Cons | ① **前提误判**：80 本来就是 SWORD_LENGTH=88 的派生近似（constants.gd:304 注释明示），已与视觉剑长对齐——「判定/视觉对齐」诉求已满足；② **破坏双向对称**：ENEMY_ATTACK_RANGE=80（enemy_ai_states.gd:132-137 敌人停距/出招）不动 → 敌人停在 80px 出招、玩家 80px 打不到敌人 → 不对称玩家吃亏；③ 牵连 test_combat_judge.gd:175（50px 用例余量归零，需同步改）与弹反/挥空全域手感（#584 调参域污染）；④ 即使调小，**仍必须同时拉开出生距离**（issue 自述「出生距离仍应 > 判定范围」）→ 不是替代方案而是叠加方案 |
| Risk | **High** |
| Effort | **1-2 天**（常量 + 对称性连带 + 测试 + 手感回归） |

### 方案 C：A+B 组合（拉开距离 + 判定微调 70）

**描述：** 拉开出生距离的同时把 HITBOX_RANGE 微调至 70（更保守）。

| 维度 | 评估 |
|------|------|
| Pros | 双保险，视觉余量更大 |
| Cons | 方案 B 的不对称问题仍在（除非同步改 ENEMY_ATTACK_RANGE → 牵连 #581/#703 行为契约，改动面失控）；收益与风险不成比例 |
| Risk | **Med-High** |
| Effort | **1-2 天** |

### 推荐：方案 A（EnemySpawnA → (1000,560)）

**理由：**
1. **根因在布局不在判定**：bug 的充分必要条件是「出生间距 ≤ 判定范围」。修布局（间距 360 > 80）直接消除充分条件，判定层无需动。
2. **契约零破坏**：80=80 双向对称是 #575/#577/#581/#703 共同建立的接战距离契约，方案 A 完全冻结它；方案 B/C 必然破坏或牵连。
3. **改动面最小**：1 行 .tscn + 1 断言，风险 Low；方案 B/C 是 1-2 天的手感全域回归。
4. **验收字面满足**：AC1「敌人 A 初始在攻击范围外」= 出生间距 > HITBOX_RANGE，方案 A 直接对应。

## 5. 边界条件与验收标准

### 5.1 正常路径（AC 检查表，映射 issue body）

- [x] **AC1: 开局挥剑（不移动）打不到敌人** — EnemySpawnA=(1000,560)，|dx|=360 > 80 → combat_judge.gd:85 挥空不发射事件；验证：新增测试断言 `abs(PlayerSpawn.x - EnemySpawnA.x) > HITBOX_RANGE + 50`（≥130px 硬门槛）
- [x] **AC2: 走近到攻击范围后挥剑正常命中** — 判定层零改动；玩家移动至 |dx| ≤ 80 → 命中；验证：现有 test_combat_judge.gd 50px 命中用例 + 实机手测
- [x] **AC3: 敌人 AI 追击/接战节奏正常** — 感知 600px > 出生距离 360px → 开局即 Chase；停距 80px 出招（enemy_ai_states.gd:132-137）；验证：headless 测试（#703/#710 现有驱动链）+ 实机观察接战 ~1.6s

### 5.2 边界情况

1. **TreeLeft 视觉重叠**：树在 (900,560)，EnemySpawnA 若取 900 与树重叠 → 取 1000（距树 100px）规避。
2. **敌人巡逻 ping-pong 路径**：waypoints 变 [1000, 1720]（原 [700, 1720]）——巡逻区间 720px，ENEMY_PATROL_SPEED=80px/s 下节奏正常（#581 契约，空数组/单点降级逻辑不受影响）。
3. **EnemySpawnB 不变**：1720 距新 A(1000) 720px、距玩家 1080px——B 不参与本 bug（MVP 单敌人场景用 A）。
4. **玩家出生朝向**：若玩家初始 facing 背对敌人，combat_judge.gd:88-92 的 `rel_dir != w.direction` 挥空校验兜底（不发射事件）——与出生距离正交，无需改动。
5. **距离恰为 80 边界**：|dx| = 80 → 不挥空（命中），符合「80=接战距离契约」设计意图（issue 要求 > 判定范围，不含等于）。
6. **窗口 4 帧 active 内移动**：攻击窗口期间玩家/敌人位移可能改变距离——但开局 360px 余量 4.5×，帧内位移（≤300px/s × 0.067s ≈ 20px/帧）不可能在 4 帧内跨越 280px 净距。
7. **StageCamera 视野**：x=1000 在 camera limits 0-2400 内、窗口 1280px 中心 1200 → 敌人 A 出生即可见（战斗可读性）。

### 5.3 失败路径

1. **坐标改动被后续场景编辑覆盖**（并发/手改）→ 新增测试断言兜底（5.1 AC1），CI 失败即暴露。
2. **waypoints 空数组降级**（若 spawn 节点丢失）：enemy_ai 原地等待不报错（#581 失败路径 2）——与坐标值无关，不回归。
3. **并发 agent 改 .tscn 冲突**：worktree 隔离（2026-08-13 红线）+ worktree-commit.sh 冲突分级（机械改动自动合并，无法判断则 abort 报告）。

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 |
|------|:----:|:----:|
| #583（battle_stage.tscn 出生点契约） | CLOSED（PR #646 merged） | 无 |
| #585（main_battle.gd 消费 spawn 定位/waypoints） | CLOSED（PR #666 merged） | 无 |
| #703（敌人 AI 运行时驱动链——AC3 前提） | CLOSED（PR #710 merged 2026-08-21） | 无 |
| #682/#683（回归来源，已合并） | CLOSED | 无（本 PRD 修复其暴露的回归） |

### 6.2 依赖链（ASCII）

```
#575/#577 (判定层 HITBOX_RANGE=80) ──► #581 (ENEMY_ATTACK_RANGE=80 / 感知600)
        │                                   │
#583 (出生点契约, 坐标.tscn) ──► #585 (组装消费 spawn) ──► #703 (AI 驱动链, #710)
        │                                   │                   │
        └──────────────► 本 issue #713（出生间距 60 < 80 回归）◄──┘
                          修复 = 布局侧 1 行坐标（判定契约冻结）
```

### 6.3 阻塞

无（独立 bug 修复，不阻塞/不被阻塞）。

### 6.4 准备清单

- [x] 核验 EnemySpawnA 目标坐标避开 TreeLeft(900)（选 1000）
- [x] 核验 e2e_shots.json 无 spawn 坐标依赖
- [x] 核验现有测试无坐标绝对值断言（test_battle_stage 只断言存在性；test_main_assembly A3 为相对定位断言）
- [ ] implement 阶段：改 .tscn 1 行 + 新增间距断言 + E2E battle_stage 组截图验证站位

## 7. Spike / 实验（depth/standard 可选——保留 3 实验提升交接质量，参照 #703 先例）

### 实验 1：出生距离最小安全值测定

- **Question:** EnemySpawnA 取 x∈{900, 950, 1000, 1100} 时，开局接战节奏与视觉站位哪个最优？
- **Method:** headless 模拟——敌人感知(600px) → Chase 逼近到 80px 停距的耗时 = (x-640-80)/180px/s；视觉重叠检查（TreeLeft@900）。
- **Expected Result:** x=1000 → 逼近耗时 (1000-720)/180 ≈ 1.56s，节奏紧凑不拖沓；x=900 与树重叠、x=1100 逼近 2.1s 略拖。
- **Impact on Approach:** 定稿推荐坐标 1000（方案 A）。

### 实验 2：判定对称性契约验证

- **Question:** 调小 HITBOX_RANGE 是否必然破坏玩家/敌人接战对称？
- **Method:** grep ENEMY_ATTACK_RANGE 全部消费点（enemy_ai_states.gd:132/137/222/241 共 4 处）与 combat_judge.gd:85 对照；模拟玩家 70px 处面对停距 80px 的敌人。
- **Expected Result:** 敌人停 80px 出招而玩家 70px 打不到 → 不对称成立 → 方案 B 否决。
- **Impact on Approach:** 确认方案 A 唯一性，判定契约冻结。

### 实验 3：E2E 开局站位截图验证

- **Question:** 修复后开局画面敌人 A 是否在玩家攻击弧视觉范围外？
- **Method:** e2e battle_stage 组加 1 shot（CaptureRig 全景模式，不依赖坐标）或实机截图；人工/自动判读敌人与玩家间距。
- **Expected Result:** 敌人 A 位于玩家右侧 360px，剑弧(SWORD_ARC_RADIUS=70)不触及。
- **Impact on Approach:** AC1 视觉证据，交用户裁决（taste 域）。

## 8. 交接上下文（Continuation Context）

**系统状态（2026-08-21, main @ e9bba05）：** 战斗闭环完整可玩；#703（PR #710）敌人 AI 驱动链已生效（敌人会索敌/追击/出招）；出生点坐标为 .tscn 唯一事实源；判定契约 HITBOX_RANGE=80 = ENEMY_ATTACK_RANGE=80 双向对称。

**给 plan agent 的核心指令：**
1. **生产改动仅 1 处**：`shandong-wolf/scenes/battle_stage.tscn` EnemySpawnA `Vector2(700,560)` → `Vector2(1000,560)`。**不要**碰 constants.gd（HITBOX_RANGE/ENEMY_ATTACK_RANGE 冻结）、combat_judge.gd、enemy_ai*（判定/行为契约零改动）。
2. **新增 1 条测试断言**（test_battle_stage.gd 或 test_main_assembly.gd）：PlayerSpawn↔EnemySpawnA 间距 > HITBOX_RANGE + 50px 硬门槛，防回归（AC1 兜底）。
3. **验证**：headless 测试全绿（现有 1314 单测基线 + 新断言）；E2E battle_stage 组截图（站位）；实机手测 AC1/AC2/AC3。
4. **边界提醒**：TreeLeft@900 → 不得选 900；EnemySpawnB(1720) 与 waypoints 自动跟随，无需改代码。

**风险：** 并发 agent 对 .tscn 的修改（worktree 隔离 + 冲突分级）；用户对 360px 出生距离的观感（taste 域，E2E 截图裁决）。

**下一步（plan → implement → verify）：** DESIGN（1 行坐标 + 测试断言规格）→ implement（.tscn + 测试）→ E2E 截图 + 实机验证 AC1-AC3 → 关闭 #713。
