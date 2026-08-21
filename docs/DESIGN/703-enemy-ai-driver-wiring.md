# Design: [Bug] 敌人 AI 运行时驱动链接线 — EnemyAI.decide() 从未被调用（FSM 从未推进）

> **Parent Issue:** #703（bug / workflow/plan / priority/high / gameplay / version/mvp）
> **Agent:** game-plan-agent
> **Date:** 2026-08-21
> **Approach:** PRD §4 **方案 A 全项确认采纳** —— ① `_physics_process` 建立「先 decide 后 _apply_movement」运行时驱动链；② `decide()` 内部移除 `_apply_movement(delta)` 调用（职责分离，decide 回归纯决策，杜绝每帧双重位移）；③ 测试 `_tick` 驱动改走 `_physics_process`（运行时路径），门控用例保留手动调 decide。方案 B（只调 decide）否决理由同 PRD §4.2（击退失效，AC3 破坏）；方案 C（main_battle 驱动）否决理由同 PRD §4.3（职责外移、多敌人扩展性差）。
> **Reference PRD:** `docs/PRD/703-enemy-ai-decide-not-called.md`（research PR #705 已合并 2026-08-21）
> **上游方案:** `docs/DESIGN/581-enemy-ai.md`（decide 纯决策入口设计契约，#638 已交付）；`docs/DESIGN/682-elite-boss-ai.md`（elite_mode/击退路径，#695 已交付——**本设计唯一硬约束：击退执行路径不得回归**）
> **所有权:** `content_ownership: mechanical`（驱动链接线 + 职责分离 = 纯机械工程：两处调用点增删 + 一处测试驱动方式替换，零 taste 环节；行为数值全部 `# DRAFT` 只读，定稿归 #584）
> **深度:** standard（GitHub 无 depth 标签；PRD 头标注 depth: standard）—— 涉及文件 **2**（`enemy_ai.gd` 2 处修改 + `test_enemy_ai.gd` _tick 与新增用例）+ **3 项实现子任务同属 1 子系统**（驱动链接线 / decide 职责分离 / 测试驱动迁移）→ **只产出 DESIGN 文档，不产出 TASKS 文档**（skill standard 阈值未触发：文件 <10、无迁移、子任务 <5 且不跨子系统）
> **并行上下文:** worktree 隔离（/tmp/wt-plan-703，branch `plan/703-enemy-ai-driver-wiring`）；**#584（OPEN, status/human-review）并行定稿 DRAFT 数值** —— 本设计零新增常量、零数值裁决；**#704（research 分支进行中）并行改动 StickFigure 腿方向** —— 与 `enemy_ai.gd`/`test_enemy_ai.gd` 零文件交集，无冲突面；`mini-pong/`、`.github/workflows/`、`scripts/`、`framework/`、`game-env/manifest.yaml` 零影响；**main_battle.gd / enemy_ai_states.gd / combat_entity.gd / combat_judge.gd / constants.gd / hud.gd 零改动**
> **红线:** 只动 PRD §3.1 列出的 2 文件；**绝不修改既有公有 API 签名**——`decide(delta)` / `move_intent()` / `_apply_movement(delta)` / `bind_entity()` 签名保持原样（测试兼容）；**不修改 decide() 门控语义**（entity null/死亡/非 idle-move/弹反抑制窗四道门控原样保留）；**不修改 11 态 CANONICAL_STATES / consume_state 契约**；**不裁决 `# DRAFT` 数值**；**运行时位移每帧恰一次**（杜绝 decide 内 + _physics_process 双重位移）；**不写可运行测试文件**（只产出 DESIGN 文档 + 测试用例描述）；PR body 用 `Parent #703`（不带冒号）

---

## 1. 架构总览

**问题本质是「生产驱动链从未接线」的集成缺口，而非 decide/_apply_movement 的实现 bug：** `decide(delta)` 设计为纯决策入口（headless 测试手动驱动），但游戏运行时无人调用——`enemy_ai.gd` 的 `_physics_process` 只调 `_apply_movement()`（消费 `_move_intent` 做位移），`main_battle.gd` 也未驱动。`_move_intent` 恒为 `Vector2.ZERO` → 行为 FSM（patrol/chase/attack/retreat）永不推进 → 敌人站着不动。#682 精英化（蓄力重斩/击退/脱战恢复）全部建立在 decide 驱动链之上，一并失效。测试长期「手动调 decide」驱动，恰好掩盖了运行时无人驱动的断点——这是 #695 E2E 只验视觉漏网的根因。

**设计哲学：接线而非重写——两处调用点增删 + 一处测试驱动方式替换，零新逻辑、零新文件、零签名变更。**

1. **运行时驱动链 = EnemyAI 自驱动**——EnemyAI 是 CharacterBody2D 自驱动节点，AI 行为驱动职责归属自身（`_physics_process`），与 PlayerController 输入驱动对称（#573 范式）。`_physics_process(delta)` 改为：先 `decide(delta)`（纯决策：门控 + `_ai_fsm.update` 推进 FSM、写 `_move_intent`），再 `_apply_movement(delta)`（位移执行，每帧恰一次）。
2. **decide 职责分离**——从 `decide()` 内部移除 `_apply_movement(delta)` 调用（现第 110 行），使 decide 真正成为「纯决策入口」——与 #581 注释宣称的语义一致，消除「注释说纯决策、实现含位移」的文档-实现漂移。位移统一由 `_physics_process` 无条件执行，**同时保住 #682 击退**（decide 门控分支提前 return 不影响击退——击退在 `_apply_movement` 内、`_physics_process` 无条件可达）。
3. **测试驱动对齐运行时**——`test_enemy_ai.gd` 的 `_tick` 从 `ai.decide(TEST_FRAME_SEC)` 改为 `ai._physics_process(TEST_FRAME_SEC)`（运行时路径驱动，与实机一致）；**门控类用例保留手动调 decide**（纯决策语义验证）。

```ascii
★ Issue #703 本设计（enemy_ai.gd 运行时驱动链，纯接线零新组件）
┌──────────────────────────────────────────────────────────────┐
│ EnemyAI._physics_process(delta)   ← 运行时驱动链（本次接线）    │
│   ├── decide(delta)               纯决策（门控 + FSM 推进）     │
│   │     ├── 门控① entity null/_dead → 清 intent 返回           │
│   │     ├── 门控② 非 idle/move 态 → 清 intent 返回             │
│   │     ├── 门控③ 弹反抑制窗内 → 清 intent 返回                │
│   │     └── _ai_fsm.update(delta)  patrol/chase/attack/retreat │
│   │           ├── 写 ai._move_intent                          │
│   │           └── entity.request_transition("attack"/...)      │
│   │                                                           │
│   └── _apply_movement(delta)      位移执行（每帧恰一次）         │
│         ├── 击退分支（#682）: stagger 期 _knockback_vel 位移     │
│         │   + DECAY 衰减 + STAGE_WIDTH clamp  ← 无条件可达      │
│         └── 正常分支: _move_intent 加速度模型 → move_and_slide   │
└──────────────────────────────────────────────────────────────┘
         ▲ 测试侧（test_enemy_ai.gd）
         │ _tick: ai._physics_process(TEST_FRAME_SEC)  ← 驱动方式替换
         │ 门控用例: ai.decide(TEST_FRAME_SEC) 手动调用不变
```

### 1.1 既有实现状态（Prior Implementation Status）

| 组件（文件） | Issue | 状态 | 本设计的处理 |
|------|:---:|:---:|------|
| `enemy_ai.gd` `_physics_process`（现第 200-203 行，仅调 `_apply_movement`） | #581（#638 merged） | ✅ | **改（+1 行）**：前置 `decide(delta)` 调用 |
| `enemy_ai.gd` `decide()`（现第 88-111 行，门控 + FSM 推进 + **内部含 `_apply_movement` 第 110 行**） | #581 | ✅ | **改（-1 行）**：移除第 110 行 `_apply_movement(delta)`，decide 回归纯决策 |
| `enemy_ai.gd` `_apply_movement`（位移 + #682 击退分支） | #581/#682 | ✅ | **零改动**（击退/位移逻辑原样保留） |
| `test_enemy_ai.gd` `_tick`（第 167-175 行，`ai.decide(TEST_FRAME_SEC)` 驱动） | #581 | ✅ | **改**：驱动改 `ai._physics_process(TEST_FRAME_SEC)`（运行时路径）；位移断言语义不变 |
| `test_enemy_ai.gd` 击退用例（第 1150+ 行，已手动 `_physics_process` 5 帧） | #682 | ✅ | **零改动**（已走运行时路径，天然兼容新驱动链） |
| `main_battle.gd` `_build_enemy`（第 159-189 行装配，_process 仅 facing/speed 同步） | #585/#682 | ✅ | **零改动**（方案 A：EnemyAI 自驱动，敌人行为经运行时驱动链自动激活） |

**与 PRD 断言对照（gap 分析）：** PRD 全部断言经 origin/main 实测属实（c056b91 → ab38b03），无发现「PRD 声称存在但代码不存在」的缺口。唯一需 implement agent 注意的既有事实：`decide()` 现第 110 行 `_apply_movement(delta)` 位于 `if _ai_fsm != null:` 块内、`_ai_fsm.update(delta)` 之前——移除时只删该行，不得改动门控与 FSM 推进顺序。

## 2. 核心改动设计（无新组件，2 处既有方法修改）

> 本 issue 为接线修复，**无新组件、无新文件**。以下为两处方法级改动的完整设计，implement agent 应能仅凭本节 + §3 写出代码。

### 2.1 EnemyAI._physics_process — 建立运行时驱动链

- **文件:** `shandong-wolf/gdscripts/enemy_ai.gd`
- **现状（第 200-203 行）:**
  ```gdscript
  func _physics_process(delta: float) -> void:
      ## 位移执行（仿 #573 加速度模型）: 只消费 _move_intent
      _apply_movement(delta)
  ```
- **目标:**
  ```gdscript
  func _physics_process(delta: float) -> void:
      ## 运行时驱动链（#703）: 先决策（decide 纯决策：门控 + FSM 推进写 _move_intent），
      ## 后位移（_apply_movement 每帧恰一次执行；击退分支无条件可达——decide 门控
      ## 提前 return 不影响击退，AC3 保障）
      decide(delta)
      _apply_movement(delta)
  ```
- **关键点:**
  - `decide()` 在前：门控清理 `_move_intent` 后，`_apply_movement` 消费的是「本帧决策结果」——与测试 `_tick`（先 enemy._process 后 ai 驱动）时序对齐。
  - `_apply_movement()` 无条件执行（不再依赖 decide 门控通过）：实体非 idle/move 态（attack/stagger）时 decide 清 intent，但 **击退仍执行**（#682 击退分支在 `_apply_movement` 内、仅依赖 `entity.state_name == "stagger"` 与 `_knockback_vel`）——这是方案 B 被否决的核心差异点。
  - `main_battle.gd` 第 302 行 `enemy.set_physics_process(false)`（场景收尾禁用）不受影响——运行时驱动链随节点 physics processing 启停。

### 2.2 EnemyAI.decide — 移除内部位移调用（职责分离）

- **文件:** `shandong-wolf/gdscripts/enemy_ai.gd`
- **现状（第 108-111 行）:**
  ```gdscript
  	if _ai_fsm != null:
  		_apply_movement(delta)
  		_ai_fsm.update(delta)
  ```
- **目标:**
  ```gdscript
  	if _ai_fsm != null:
  		_ai_fsm.update(delta)
  ```
- **关键点:**
  - **只删 `_apply_movement(delta)` 一行**，四道门控（entity null/死亡/非 idle-move/弹反抑制窗）与 `_ai_fsm.update(delta)` 原样保留。
  - decide 语义回归「纯决策」：headless 手动调 decide 只推进 FSM、写 `_move_intent`，**不再产生位移**——位移断言用例必须改走 `_physics_process` 驱动（§8 测试用例）。
  - **门控行为不变**：门控命中时清 `_move_intent` 并提前 return（不触达 FSM 推进）——测试断言 `_move_intent == Vector2.ZERO` 的用例不受影响。
  - 弹反抑制窗门控（Time.get_ticks_msec 比较）与 #682 击退正交：抑制窗内 decide 清 intent（AI 不决策），但 `_physics_process` 仍调 `_apply_movement`——若 `_knockback_vel > 0` 且实体 stagger，击退照常执行。

## 3. 既有组件修改

### 3.1 修改文件清单

| 文件 | 变更 | 为什么 |
|------|------|--------|
| `shandong-wolf/gdscripts/enemy_ai.gd` | `_physics_process`: 新增 `decide(delta)` 调用（先决策后位移） | 运行时驱动链接线（AC1/AC2 根因修复） |
| `shandong-wolf/gdscripts/enemy_ai.gd` | `decide()`: 移除第 110 行 `_apply_movement(delta)` | 职责分离——decide 回归纯决策；杜绝双重位移（AC5） |
| `shandong-wolf/tests/test_enemy_ai.gd` | `_tick`（第 167-175 行）: `ai.decide(TEST_FRAME_SEC)` → `ai._physics_process(TEST_FRAME_SEC)` | 测试驱动对齐运行时路径（补 #695 E2E 漏网根因） |

### 3.2 新文件

无。

### 3.3 移除/弃用文件

无。

### 3.4 受影响测试文件

| 测试文件 | 变更性质 | 说明 |
|---------|---------|------|
| `shandong-wolf/tests/test_enemy_ai.gd` | **修改（驱动方式迁移 + 新增用例）** | `_tick` 驱动改 `_physics_process`；**位移断言用例**（现基于 `ai.decide` 驱动的，如第 216-222/248-262/616-618/745-759 行附近的 position 断言）随 `_tick` 自动走运行时路径；**门控用例**（断言 `_move_intent == ZERO` / 状态不转移，现直接调 `ai.decide` 的，如第 778/1118 行附近）**保留手动调 decide**（纯决策语义不变）；新增 3 用例（§8） |

> **implement agent 注意（PRD §8.2 风险 1 缓解）:** `_tick` 全局替换后，个别仍直接调 `ai.decide` 且**断言位移**的用例（若有）会因 decide 不再产生位移而失败——处理方式：该用例改为走 `_physics_process` 驱动（属预期测试更新），**不要**改回手动 decide 后补位移。迁移清单以 `grep -n "ai.decide(" tests/test_enemy_ai.gd` 逐一核对（现状命中：第 174/778/1118 行）。

## 4. 数据流

### Flow 1: 正常路径（运行时驱动链 — 索敌/追击/出招）

```
Godot 物理帧
  ▼
EnemyAI._physics_process(delta)
  ├── decide(delta)
  │     ├── 门控全过（entity 非空、非死亡、idle/move 态、抑制窗外）
  │     └── _ai_fsm.update(delta)
  │           ├── PatrolState: 空 waypoints → 原地等待（写 intent=ZERO）
  │           ├── ChaseState: can_sense_player() 真 → 写 intent=±ENEMY_CHASE_SPEED 逼近
  │           │     玩家距离 ≤ ENEMY_ATTACK_RANGE(80px) → 转移 AttackState
  │           ├── AttackState: elite_mode → 三选一（三连砍/突刺/蓄力重斩 20 帧前摇）
  │           │     entity.request_transition("attack"/"heavy_attack")
  │           └── RetreatState: 掷骰 5% 触发 → 远离玩家
  │
  └── _apply_movement(delta)
        ├── _knockback_vel ≈ 0 → 正常分支: velocity.x = move_toward(→ _move_intent.x)
        │     move_and_slide()（场景树内）/ position += velocity*delta（headless 免树）
        └── 结果: 敌人 position 持续接近玩家（AC1）→ 进入攻击范围出招（AC2）
```

### Flow 2: 击退/硬直路径（#682 保障，AC3）

```
玩家弹反成功 → judge.parry_success(defender=本敌人)
  ▼
_on_judge_parry_success: _parry_stun_until_sec = now + ENEMY_PARRY_STUN_SECONDS(0.5s)
  ▼（玩家攻击命中 → judge.hit_landed）
_on_judge_hit_landed: _knockback_dir = 远离攻击者; _knockback_vel = ENEMY_KNOCKBACK_PX(40)
  ▼ 后续每物理帧
_physics_process
  ├── decide: 门控③弹反抑制窗命中 → 清 intent 提前 return（AI 不决策、FSM 不推进）
  └── _apply_movement: |_knockback_vel|>0.001 且 entity.state_name=="stagger"
        → velocity.x = dir*vel; 位移 + ENEMY_KNOCKBACK_DECAY(3) 衰减; STAGE_WIDTH clamp
  ▼ stagger 结束（entity 离开 stagger 态）
_apply_movement 守卫: 立即清零 _knockback_vel → 正常位移路径（Chase 恢复，无弹簧抖动）
```

> **对比方案 B（否决路径）:** 若 `_physics_process` 只调 decide（decide 内保留位移）——门控③命中时 decide **提前 return 不执行位移** → stagger 期间击退完全不执行，AC3 破坏。本设计 `_apply_movement` 无条件可达，击退正交于决策门控。

### Flow 3: headless 测试路径（AC4）

```
godot --path shandong-wolf/ --headless --script tests/run_tests.gd
  ▼
test_enemy_ai.gd _tick(s, seconds): 每帧
  enemy._process(TEST_FRAME_SEC)          # 实体战斗 FSM 推进（不变）
  ai._physics_process(TEST_FRAME_SEC)     # ← 本次从 ai.decide 迁移（运行时路径）
        ├── decide: 门控 + _ai_fsm.update（免树分支照常）
        └── _apply_movement: is_inside_tree()==false → 手动积分 position += velocity*delta
  ▼ 断言: ai.position.x 接近玩家 / 行为态转移 / 位移单次（与运行时语义一致）
```

## 5. 边界情况与错误处理

| # | 边界情况 | 缓解措施 |
|---|---------|---------|
| 1 | enemy/entity 为 null（装配前帧） | decide 门控①返回清 intent；`_apply_movement` 正常分支消费 `_move_intent`（=ZERO 无位移）；击退分支守卫 entity null → 清零 `_knockback_vel`（既有行为） |
| 2 | 敌人死亡（_dead=true） | decide 门控①返回；`_apply_movement` 无位移意图；`set_physics_process(false)`（main_battle 第 302 行）后驱动链整体停摆（既有行为） |
| 3 | 实体处于 attack/stagger 等非 idle/move 态 | decide 门控②返回清 intent（FSM 不抢戏）；**击退仍由 `_apply_movement` 无条件执行**（本设计关键保障——方案 A 优于方案 B 的核心） |
| 4 | 弹反抑制窗内（Time 门控） | decide 门控③清 intent；位移零（抑制窗语义不变）；若同时受击 → 击退照常执行（正交） |
| 5 | 空 waypoints / 单 waypoint（#581 边界） | Patrol 原地等待不报错；intent=ZERO 无位移（既有测试覆盖） |
| 6 | headless 免树（--script 测试） | `_physics_process` 手动调用：`is_inside_tree()` 分支走手动积分（既有第 780 行模式，`move_and_slide` 在无物理空间时报错） |
| 7 | 多帧叠加双重位移（速度翻倍） | 移除 decide 内第 110 行后自然消除；AC5 专项用例（§8 Scenario C）断言每帧位移恰一次 |
| 8 | decide 内位移移除导致位移断言用例失败（测试迁移遗漏） | `_tick` 全局改 `_physics_process` 后位移断言语义不变；`grep ai.decide(` 逐一核对（现 3 处：174/778/1118）；若个别用例仍直接调 decide 断言位移 → 改走 `_physics_process`（预期更新） |
| 9 | #682 击退回归（stagger 不位移） | `_apply_movement` 零改动 + AC3 专项用例（§8 Scenario B）兜底；若回归 → 检查是否误把击退移入 decide |
| 10 | 并行 #704（StickFigure 腿方向）merge 冲突 | 文件交集为零（#704 改 scenes/stick_figure 相关）；worktree-commit.sh 提交前 merge main 自动处理 |

## 6. 集成点

> **状态约定:** ⬜ = 待接线（资源已就绪未连目标）；✅ = 已连接（implement agent 验证后更新）。implement agent 必须在本表接线完成时更新状态；review agent merge 前核查全部 ⬜ 已解决或明确推迟。

| 集成点 | 我们的组件 | 目标 Issue | 方式 | 状态 |
|-------------|:---:|:---:|-----|:---:|
| 运行时驱动链 | `EnemyAI._physics_process` → `decide(delta)` | #703 | 方法内先决策后位移（本次接线） | ⬜ pending |
| 决策-位移解耦 | `EnemyAI.decide` 移除 `_apply_movement(delta)` | #703 | 位移统一由 `_physics_process` 执行 | ⬜ pending |
| 测试驱动对齐 | `test_enemy_ai.gd._tick` → `ai._physics_process` | #703 | 运行时路径驱动（与实机一致） | ⬜ pending |
| 击退路径保持 | `_physics_process` → `_apply_movement` 无条件可达 | #682（#695 merged） | 击退分支零改动、每帧可达 | ⬜ pending（回归保障） |
| 行为 FSM 推进 | `decide` → `_ai_fsm.update(delta)` | #581（#638 merged） | 既有调用保留（仅删位移行） | ⬜ pending（不回归） |
| 装配层 | `main_battle.gd._build_enemy` → EnemyAI 装配 | #585（#666 merged） | **零改动**（方案 A 自驱动） | ✅ 无需接线 |

## 7. 实现阶段

> 本 issue 改动极小（2 文件 3 处），单阶段交付即可，无需分阶段。

| 阶段 | 优先级 | 组件 | 估计 |
|:-----:|:--------:|-----------|:--------:|
| 阶段 1 | P0 | `enemy_ai.gd`: `_physics_process` 加 `decide(delta)` + `decide()` 删第 110 行位移调用 | 0.5 人日 |
| 阶段 2 | P0 | `test_enemy_ai.gd`: `_tick` 驱动迁移 + 新增 3 用例（§8）+ `grep ai.decide(` 迁移核对 | 0.5 人日 |

## 8. 测试用例描述

> 只描述测试场景，**不写可运行测试代码**（implement agent 职责）。新增用例编号 TC703-1 ~ TC703-3；既有 44 用例（test_enemy_ai.gd）基线全部保留。

### Scenario A: 运行时驱动链（AC1/AC2 核心 — 新 TC703-1）

- **TC703-1: `_physics_process` 驱动下敌人自动索敌追击（不手动调 decide）**
  - 前置: 构造 enemy+player（player 在感知范围内 120° 视线 6m 内、攻击范围外）、`_ready()` 初始化 FSM；**不手动调 decide**
  - 操作: `ai._physics_process(TEST_FRAME_SEC)` 驱动 N 帧
  - 预期: `_behavior` 从 "patrol" → "chase"；`ai.position.x` 持续逼近 `player.position.x`（ENEMY_CHASE_SPEED 180 px/s 量级）；无需手动 decide 即产生位移——证明运行时驱动链成立

- **TC703-2: 进入攻击范围后 FSM 推进 AttackState 出招（elite_mode 路径）**
  - 前置: elite_mode=true，player 逼近至 ENEMY_ATTACK_RANGE(80px) 内
  - 操作: `_physics_process` 驱动至攻击冷却结束
  - 预期: `_behavior` → "attack"；`entity.request_transition("attack"/"heavy_attack")` 被调用（蓄力重斩 20 帧前摇路径可经 entity 状态断言）；攻击冷却 1.5s 循环

### Scenario B: 击退/硬直不回归（AC3 — 既有 44 用例 + 新 TC703-3）

- **TC703-3: stagger 期间 `_physics_process` 驱动下击退位移照常执行（decide 门控不阻断）**
  - 前置: 实体进入 stagger 态（非 idle/move），`_knockback_vel = ENEMY_KNOCKBACK_PX(40)`、`_knockback_dir` 已设；**弹反抑制窗内**（`_parry_stun_until_sec` 未来时刻，decide 门控③命中）
  - 操作: `ai._physics_process(TEST_FRAME_SEC)` 驱动 5 帧
  - 预期: 每帧 `ai.position.x` 沿受击反向变化（击退位移执行，DECAY 衰减）；`_move_intent` 保持 ZERO（decide 门控清 intent 但位移仍执行）——证明击退正交于决策门控（方案 A 关键保障）
  - 既有用例（第 1150+ 行 #682 击退用例，已手动 `_physics_process` 5 帧）保持全绿

- **回归用例（迁移核对）:** 门控类用例（entity null / 死亡 / 非 idle-move / 抑制窗 → 断言 `_move_intent == Vector2.ZERO`、FSM 不转移，第 778/1118 行附近）**保留手动调 decide**，断言不变；位移断言用例（第 216-222/248-262/616-618/745-759 行附近）随 `_tick` 迁移自动走 `_physics_process`，断言语义不变

### Scenario C: 位移单次执行（AC5 — 新 TC703-4）

- **TC703-4: 每物理帧 `_apply_movement` 恰执行一次（无双重位移）**
  - 前置: 常规 chase 场景（player 在感知范围内）
  - 操作: `_physics_process` 驱动固定帧数（如 60 帧），记录 position 总位移；对照「单次位移预期值」（ENEMY_CHASE_SPEED × 帧时长，考虑加速度逼近）
  - 预期: 总位移 ≈ 单次位移预期（**非 2 倍**）——证明 decide 内位移调用已移除、无速度翻倍；若总位移 ≈ 2× 预期 → decide 内残留位移调用（失败信号）
  - 可选强化: 测试计数（`_apply_movement` 调用计数 / 帧数 == 1）直接断言

### Scenario D: headless 全量回归（AC4）

- **TC703-5: `godot --path shandong-wolf/ --headless --script tests/run_tests.gd` 全绿**
  - 前置: 上述迁移 + 新增用例完成
  - 预期: 1314 单测基线 + 新增用例零失败；`decide` 纯决策入口保持可手动调用（门控用例覆盖证明）

## 9. 验收条件映射（issue body 4 条 + PRD 补充）

| # | 验收条件 | 设计保障 | 对应测试 |
|---|---------|---------|---------|
| AC1 | 实机（Main.tscn）敌人会主动索敌接近玩家 | §2.1 `_physics_process` 驱动 decide → Chase 逼近（ENEMY_CHASE_SPEED 180 px/s） | TC703-1 |
| AC2 | 进入攻击范围后敌人出招（含蓄力重斩——elite_mode） | FSM 推进 AttackState → elite 三选一（含 ENEMY_CHARGE_WINDUP 20 帧蓄力重斩） | TC703-2 |
| AC3 | 玩家弹反/受击击退时敌人行为正确（stagger 不位移→击退位移、无弹簧抖动） | `_apply_movement` 无条件可达（decide 门控解耦）；击退分支零改动；stagger 结束守卫清零 | TC703-3 + 既有 #682 击退用例 |
| AC4 | headless 测试仍全绿（decide 纯入口不变） | decide 保持纯决策入口；`_tick` 走运行时路径；门控用例保留手动 decide | TC703-5 |
| AC5（PRD 补） | 位移单次执行（每帧 `_apply_movement` 恰一次） | decide 内位移调用移除（§2.2） | TC703-4 |
| AC6（建议，非阻塞） | E2E 增加「敌人 position 随时间变化」行为断言（补 #695 漏网根因） | 列入建议，不属于本 issue 强制范围（PRD §5.1 AC5 注） | — |

## 10. 明确不修改（与 PRD §1.4/§8 红线对齐）

| 文件/契约 | 不修改原因 |
|----------|-----------|
| `main_battle.gd` | 方案 A 自驱动——装配层零改动（PRD §3.3） |
| `enemy_ai_states.gd` | Patrol/Chase/Attack/Retreat 状态对象照常被 `_ai_fsm.update` 推进（PRD §3.3） |
| `combat_entity.gd` / `combat_judge.gd` / `combat_states.gd` | decide 门控读取 entity.state_name 的既有契约不变；11 态 CANONICAL_STATES 不动 |
| `constants.gd` | 零新增常量、零数值裁决（全部 `# DRAFT` 只读，定稿归 #584） |
| `hud.gd` / 血条 UI | #684 范围，不触碰 |
| `project.godot` / `game-env/manifest.yaml` / `.github/workflows/` / `scripts/` / `framework/` | 非本 issue 范围 |
| `decide()` 门控语义 / 公有 API 签名 / `_apply_movement` 击退分支 | 红线——只删 decide 内位移调用，其余原样 |
| `mini-pong/` | 非 active 游戏，零影响 |
