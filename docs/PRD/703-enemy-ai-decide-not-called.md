# PRD #703 — [Bug] 敌人 AI 不行动：EnemyAI.decide() 从未被调用（FSM 从未推进，站着不动）

> **Issue:** #703
> **标签:** bug, workflow/research, priority/high, gameplay, version/mvp（issue 无 `depth/*` 标签，参照 #682 先例取 `depth: standard` → §1–6 + §8 必填；§7 可选，本 PRD 含 2 实验提升交接质量）
> **Agent:** game-research-agent
> **日期:** 2026-08-21
> **所有权:** `content_ownership: mechanical`（AI 驱动接线=机械工程；行为数值全部 # DRAFT 只读，定稿归 #584）
> **引擎/目录约束:** Godot 4.7.1 / `shandong-wolf/`（manifest `game.active: shandong-wolf` + `default_branch: main` 单一事实源；本 PRD 全部路径前缀 `shandong-wolf/`，零 `mini-pong/` 写死）
> **研究选项:** Obsidian 知识库已搜索（`/Volumes/Obsidian/Knowledge Ocean/` + `~/Documents/Obsidian Vault/`：wiki grep 敌人/AI/Boss → `wiki/JRPG战斗系统演变.md`（模块化难度/Boss 战戏剧性）、`wiki/游戏设计理念.md`；raw grep 决策/FSM → `raw/Bear/JRPG 战斗系统研究 - 最终综合报告.md`（「条件→行动」FSM 决策范式、AI 辅助强度可调）、`raw/Bear/state machine.md`（状态机记录范式））+ 设计 brief（`docs/RAW/shandong-wolf-brief.md`：敌人=『压迫感』来源、MVP「手感验证优先」）+ 同链 PRD/DESIGN（#581/#682/#684/#585 全读）+ origin/main 源码实测（c056b91，enemy_ai.gd / main_battle.gd / test_enemy_ai.gd 逐行核对）
> **来源:** 用户实机验证反馈（2026-08-21）：敌人站着不动，无 AI 行为。#682（PR #695）已 merge 但行为不生效——E2E 截图只验证视觉状态，未验证行为驱动（issue body 自述漏网原因）
> **前置依赖:** #581（CLOSED，PR #638 merged）、#682（CLOSED，PR #695 merged 2026-08-21T04:22Z）、#585（CLOSED，PR #666 merged）——全部满足

---

## 1. 问题定义

### 1.1 现状（2026-08-21 worktree 侦查 @ origin/main c056b91）

**一句话现状：** 敌人 AI 的决策入口 `decide(delta)` 在生产代码中**零调用点**——`enemy_ai.gd` 的 `_physics_process` 只调 `_apply_movement()`（消费 `_move_intent` 做位移），`main_battle.gd` 也未驱动。`_move_intent` 恒为 `Vector2.ZERO` → 行为 FSM（patrol/chase/attack/retreat）永不推进 → 敌人站着不动。#682 精英化（蓄力重斩/击退/脱战恢复）全部建立在 `decide()` 驱动之上，因此一并失效。

| 组件（文件） | Issue | 当前状态 | 与 #703 的差距 |
|------|-------|:-------:|------|
| `gdscripts/enemy_ai.gd`（_physics_process，第 200-203 行） | #581/#638 | ✅ 每物理帧调 `_apply_movement(delta)` | ❌ **不调 `decide()`** —— 决策链断点 |
| `gdscripts/enemy_ai.gd`（decide，第 88-111 行） | #581/#638 | ✅ 纯决策入口（门控 + `_ai_fsm.update`），**内部已含 `_apply_movement(delta)` 调用（第 110 行）** | ⚠️ 若 `_physics_process` 照 issue 建议「先 decide 再 _apply_movement」→ 每帧双重位移 |
| `gdscripts/enemy_ai.gd`（_apply_movement，第 112-142 行） | #581/#682 | ✅ 位移执行 + #682 击退分支（stagger 期间沿受击反向，DECAY 衰减） | ⚠️ 击退依赖 `_physics_process` **无条件**调用；`decide()` 门控分支（非 idle/move 态）提前 return 不执行位移——若只调 decide 则击退失效 |
| `gdscripts/main_battle.gd`（_build_enemy，第 159-189 行） | #585/#682 | ✅ 装配 EnemyAI + bind_entity + player/judge 注入 + elite_mode=true | ❌ **未驱动 decide()**（其 _process 只做 facing/speed 视觉同步，第 215-219 行） |
| `tests/test_enemy_ai.gd`（_tick，第 167-175 行） | #581 | ✅ headless 手动调 `ai.decide(TEST_FRAME_SEC)` 驱动，位移断言基于 position | ⚠️ 测试走的是「手动调 decide」路径，**从未覆盖运行时 `_physics_process` 驱动链**——这是漏网根因 |

**核心缺口（本 PRD 的增量工作，共 1 项 + 1 个约束处理）：**
1. **运行时驱动链缺失**：`decide()` 无人调用 → FSM 永不推进 → 敌人不动。修复 = 在 `_physics_process` 建立「先决策、后位移」的运行时驱动链。
2. **约束：decide() 内部已含位移调用**（第 110 行 `_apply_movement(delta)`）。直接照 issue 字面建议（`_physics_process` 调 decide 后再调 _apply_movement）→ 每帧 `_apply_movement` 执行两次 → 敌人速度翻倍。必须重构职责分离：decide 变纯决策，位移统一由 `_physics_process` 无条件执行（同时保住 #682 击退）。

### 1.2 预调查表（bug-pre-investigation-workflow §7）

| Issue 声明 | 预调查结果 |
|-----------|-----------|
| `decide()` 在整个项目中没有任何调用点 | ✅ **属实**（grep 全仓：仅 `test_enemy_ai.gd` 手动调用，生产代码零调用） |
| `_physics_process` 只调 `_apply_movement()` | ✅ **属实**（第 200-203 行） |
| `main_battle.gd` 也未接 | ✅ **属实**（其 _process 仅 facing/speed 视觉同步） |
| `_move_intent` 恒为 ZERO → 敌人不动 | ✅ **属实**（decide 不跑 → 无人写 _move_intent） |
| 修复建议：`_physics_process` 先 decide 再 _apply_movement | ⚠️ **方向正确但需修正**——decide 内部第 110 行已调 _apply_movement，直接照搬=双重位移；需先移除 decide 内位移调用 |
| #682（PR #695）已 merge 但行为不生效 | ✅ **属实**（PR #695 MERGED 2026-08-21T04:22Z；E2E 只验视觉） |
| 保持 headless 测试的纯函数入口不变 | ✅ **采纳**——decide 仍为纯决策入口（无物理依赖、手动可调）；位移断言测试改经 `_physics_process` 驱动（与运行时一致） |

**无 stale claims**——issue body 的根因分析全部与当前代码一致（c056b91）。

### 1.3 验收条件（issue body 4 条 → 本 PRD 保障）

| # | 验收条件 | 现状 | 本 PRD 保障 |
|---|---------|:----:|------------|
| AC1 | 实机（Main.tscn）敌人会主动索敌接近玩家 | ❌ 站着不动 | §5.1 AC1：`_physics_process` 驱动 decide → Chase 逼近（ENEMY_CHASE_SPEED 180 px/s） |
| AC2 | 进入攻击范围后敌人出招（含蓄力重斩——elite_mode） | ❌ 无出招 | §5.1 AC2：FSM 推进到 AttackState → elite 三选一（含 ENEMY_CHARGE_WINDUP 20 帧蓄力重斩） |
| AC3 | 玩家弹反/受击击退时敌人行为正确（stagger 不位移） | ❌ 未生效 | §5.1 AC3：击退仍由 `_physics_process` 无条件执行（decide 门控与位移执行解耦后不受影响） |
| AC4 | headless 测试仍全绿（decide 纯入口不变） | ✅ 目前全绿（1314 单测基线） | §5.1 AC4：decide 保持纯决策入口；`_tick` 驱动改走 `_physics_process`（运行时路径），断言不变 |

### 1.4 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 实机战斗（MVP 核心闭环） | 每次游玩 | 雪夜村口：敌人巡逻/原地等待 → 玩家进入 120° 视线 6m → Chase 逼近 → 停距 80px → AttackState 三选一出招（三连砍/突刺/蓄力重斩）→ 玩家弹反成功 → 敌人硬直 + 击退位移 → 架势上涨 → 崩解 → 处决 |
| B | 开发者 headless 验证 | 每次 impl PR | `godot --path shandong-wolf/ --headless --script tests/run_tests.gd`：断言运行时路径（_physics_process 驱动）下 patrol/chase/attack/retreat 全链行为 + 击退 + 门控，全绿 |
| C | E2E 行为验证（补 #695 漏网） | 每次 impl PR | e2e 截图前先断言敌人 position 随时间变化（行为驱动成立），再截图视觉状态 |

### 1.5 范围边界（Patch 14 去冲突）

| PRD / Issue | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|------------------|
| #581 小兵 AI（CLOSED，#638 merged） | 行为 FSM 四态 + 感知 + decide 设计 | ❌ 不重写状态机/感知/门控逻辑；只**接线运行时驱动链**（decide 内位移调用移除属职责重构，非行为变更） |
| #682 精英 Boss AI（CLOSED，#695 merged） | elite_mode/蓄力重斩/击退/脱战恢复/血条 | ❌ 不新增精英能力；**#682 的击退在本次接线中必须保持不回归**（击退执行路径不变） |
| #684 敌人血条 UI（CLOSED，#702 merged） | EnemyHealthBar | ❌ 不触碰 HUD |
| #585 组装（CLOSED，#666 merged） | main_battle.gd 装配 | ❌ 不改装配结构；仅确认「驱动职责归 EnemyAI 自身」（方案 A）或驱动注入点（备选方案） |

**红线（继承 + 新增）：**
- ❌ 不改 `decide()` 的门控语义（entity null/死亡/非 idle-move/弹反抑制窗）与 FSM 状态转移逻辑
- ❌ 不改 11 态 `CANONICAL_STATES` / `consume_state` 契约（#575 权威集）
- ❌ 不裁决 # DRAFT 数值（全部只读，定稿归 #584）
- ❌ 不修改既有接口签名（decide/move_intent/_apply_movement 保持公开，测试兼容）
- ✅ 新增红线：**运行时位移每帧仅执行一次**（杜绝 decide 内 + _physics_process 双重位移）

---

## 2. 设计意图

### 2.1 为什么现状如此

| Issue | 创建了什么 | 留下的结构后果 |
|-------|-----------|---------------|
| #581（PR #638） | 设计 `decide()` 为「纯决策入口」：headless 测试手动驱动、无物理依赖，`_physics_process` 只消费 `_move_intent` | **驱动链缺口**：decide 设计为可测入口，但从未规定「运行时由谁调用」。测试长期手动驱动 → 运行时无人驱动的问题被测试路径掩盖 |
| #682（PR #695） | elite_mode/蓄力重斩/击退/脱战恢复，全部消费 decide 驱动链 | 在断掉的驱动链上叠加能力 → 精英化一并失效；E2E 只验视觉 → 漏网 |

**根因定性：** 这不是 decide 或 _apply_movement 的实现 bug，而是**「生产驱动链从未接线」的集成缺口**——测试替生产代码承担了驱动职责，掩盖了断点。

### 2.2 为什么现在改

- 用户实机验证（2026-08-21）明确反馈：敌人站着不动 = MVP 核心战斗闭环不可玩（无法验证弹反/架势/处决）
- #682 已 merge 但行为不生效，优先级 high——修复驱动链后 #682 全部能力一次性激活
- 改造成本低：接线 + 职责分离重构，不触碰任何行为逻辑

### 2.3 既有约束

| 约束 | 详情 |
|------|------|
| decide 纯入口（#581 设计契约） | headless 测试手动调 decide 验证决策；无物理依赖 |
| 击退执行路径（#682） | `_apply_movement` 的击退分支必须**每帧无条件可达**（stagger 期间 _move_intent=0 但击退仍需执行）——decide 门控会提前 return，故击退绝不能移入 decide 内 |
| 位移单次执行 | 每物理帧位移应用恰一次（否则速度/击退翻倍） |
| 测试全绿 | 1314 单测基线不回归；位移断言改经运行时路径后语义不变 |

---

## 3. 影响分析

### 3.1 直接影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `shandong-wolf/gdscripts/enemy_ai.gd` | EnemyAI._physics_process | **修改**：加 `decide(delta)` 调用（先决策后位移） |
| `shandong-wolf/gdscripts/enemy_ai.gd` | EnemyAI.decide | **修改**：移除第 110 行 `_apply_movement(delta)`（职责分离——decide 变纯决策；位移统一由 _physics_process 执行） |
| `shandong-wolf/gdscripts/enemy_ai.gd` | EnemyAI._apply_movement | **零改动**（击退/位移逻辑原样保留） |
| `shandong-wolf/tests/test_enemy_ai.gd` | _tick 驱动辅助（第 167-175 行） | **修改**：`ai.decide(TEST_FRAME_SEC)` → `ai._physics_process(TEST_FRAME_SEC)`（运行时路径驱动）；decide 仍保留手动调用覆盖门控用例 |

### 3.2 新文件

无（纯接线 + 职责重构）。

### 3.3 间接影响模块

| 文件 | 影响 |
|------|------|
| `shandong-wolf/gdscripts/main_battle.gd` | 零改动（方案 A：EnemyAI 自驱动）。敌人行为经运行时驱动链自动激活 |
| `shandong-wolf/gdscripts/enemy_ai_states.gd` | 零改动（Patrol/Chase/Attack/Retreat 状态对象照常被 `_ai_fsm.update` 推进） |
| `shandong-wolf/gdscripts/combat_entity.gd` | 零改动（decide 门控读取 entity.state_name 的既有契约不变） |
| E2E 截图脚本 | 建议后续补「行为驱动断言」（position 随时间变化）——见 §5.1 AC5（非阻塞） |

### 3.4 数据流（修复后）

```
Godot 物理帧
    │
    ▼
EnemyAI._physics_process(delta)          ← 运行时驱动链（本次接线）
    ├── decide(delta)                     纯决策：门控（null/死亡/非idle-move/弹反抑制窗）
    │       └── _ai_fsm.update(delta)     patrol/chase/attack/retreat 状态对象
    │               ├── 写 ai._move_intent
    │               └── entity.request_transition("attack"/"heavy_attack")
    │
    └── _apply_movement(delta)            位移执行（每帧恰一次）
            ├── 击退分支（#682）: stagger 期间 _knockback_vel → 位移 + DECAY 衰减  ← 无条件可达
            └── 正常分支: _move_intent 加速度模型 → move_and_slide / 手动积分
```

### 3.5 需更新的文档

- [x] `docs/PRD/703-enemy-ai-decide-not-called.md`（本 PRD）
- [ ] `docs/DESIGN/703-*.md`（plan 阶段产出）
- [ ] `docs/RAW/shandong-wolf-brief.md`（如需记录驱动链设计决策——可选）

---

## 4. 方案对比

### 4.1 方案 A：运行时驱动链接线 + decide 职责分离（推荐）

**描述：** `_physics_process(delta)` 改为：先 `decide(delta)`（纯决策：门控 + `_ai_fsm.update` 推进 FSM、写 _move_intent），再 `_apply_movement(delta)`（位移执行）。同时从 `decide()` 内部移除 `_apply_movement(delta)` 调用（第 110 行），使 decide 真正成为「纯决策入口」——与 #581 注释宣称的语义一致。测试 `_tick` 改走 `_physics_process` 驱动（运行时路径），门控断言用例保留手动调 decide。

```gdscript
# enemy_ai.gd
func decide(delta: float) -> void:
    # ...门控不变...
    if _ai_fsm != null:
        _ai_fsm.update(delta)          # ← 移除 _apply_movement(delta)（原第 110 行）

func _physics_process(delta: float) -> void:
    decide(delta)                       # ← 新增：运行时决策驱动
    _apply_movement(delta)              # ← 位移执行（每帧恰一次；击退无条件可达）
```

| 维度 | 评价 |
|------|------|
| Pros | 运行时驱动链成立（AC1/AC2）；位移每帧恰一次；击退路径无条件可达（AC3）；decide 语义回归「纯决策」与注释/设计契约一致；改动局部（2 处 + 测试 1 处）；main_battle 零改动 |
| Cons | 测试 _tick 驱动方式需更新（位移断言改经 _physics_process——与运行时一致，语义更强）；decide 内位移调用移除属行为面变更（需测试全绿验证） |
| Risk | **Low**——纯接线 + 职责重构，无新逻辑；回归风险集中在「位移单次执行」与「击退不回归」，均有测试覆盖 |
| Effort | 小（≈0.5 人日含测试更新） |

### 4.2 方案 B：_physics_process 只调 decide（最小字面改动，不推荐）

**描述：** 照 issue 字面「由 main_battle.gd 驱动或 _physics_process 先 decide」的一半——`_physics_process` 只调 `decide(delta)`，不再单独调 `_apply_movement`（decide 内部已有位移调用）。

| 维度 | 评价 |
|------|------|
| Pros | 改动最小（1 行）；decide 内部逻辑不动 |
| Cons | **❌ 击退失效**：decide 门控分支（entity 非 idle/move 态=stagger/attack 等）提前 return，不执行位移 → #682 受击击退（stagger 期间必须位移）完全不执行，AC3 破坏；❌ 位移依赖 decide 门控通过才执行——门控期间敌人「钉死」 |
| Risk | **High**——直接回归 #682 击退与受击反馈 |
| Effort | 极小 |
| **裁决** | **否决**——破坏 #682 已验证行为，不可接受 |

### 4.3 方案 C：main_battle.gd 驱动 decide（备选）

**描述：** 在 `main_battle.gd` 的 `_process/_physics_process` 中调 `enemy.decide(delta)`（issue 建议的「或由 main_battle.gd 驱动」）。

| 维度 | 评价 |
|------|------|
| Pros | 驱动点集中在装配层，便于观察 |
| Cons | 敌人 AI 行为驱动职责外移出 EnemyAI 自身（封装破坏）；main_battle._process 已做 facing/speed 同步，职责混杂；若 decide 内位移调用保留则同样双重位移（需同步移除）；未来多敌人时 main_battle 需逐个驱动（扩展性差）；测试需构造 main_battle 场景 |
| Risk | **Med**——职责分散，未来多敌人扩展性差；改动面更大 |
| Effort | 中 |
| **裁决** | 备选——单敌人 MVP 可用，但不如 A 自驱动干净；#589 军曹/#590 Boss 多敌人场景下 A 的「AI 自驱动」模式明显更优 |

### 4.4 推荐（方案 A）

1. EnemyAI 是 CharacterBody2D 自驱动节点，AI 行为驱动职责应归属自身（`_physics_process`），与 PlayerController 的输入驱动对称（#573 范式）
2. 位移每帧恰一次 + 击退无条件可达 = 同时满足 AC1/AC2/AC3，且 #682 行为零回归
3. decide 语义回归「纯决策」——消除「注释说纯决策、实现含位移」的文档-实现漂移，headless 测试入口更纯粹
4. 测试驱动改走运行时路径后，headless 覆盖与实机行为一致（补 #695 E2E 漏网根因）
5. main_battle 零改动，改动面最小且无职责外移

---

## 5. 边界条件与验收标准

### 5.1 正常路径（AC 清单，映射 issue body）

- [ ] **AC1** 实机 Main.tscn：敌人巡逻/原地等待 → 玩家进入感知（120° 视线 6m）→ Chase 逼近（180 px/s）→ 敌人 position 持续接近玩家
- [ ] **AC2** 进入 ENEMY_ATTACK_RANGE（80px）→ AttackState 出招：elite_mode=true 三选一（三连砍/突刺/蓄力重斩 20 帧前摇），冷却 1.5s 循环
- [ ] **AC3** 玩家弹反成功 → 敌人 0.5s 抑制窗（不决策不位移）+ 击退位移（ENEMY_KNOCKBACK_PX 沿受击反向、DECAY 衰减）；stagger 期间 _move_intent=0 但击退照常执行；stagger 结束 → 击退归零 → Chase 恢复（无弹簧抖动）
- [ ] **AC4** headless 测试全绿：`godot --path shandong-wolf/ --headless --script tests/run_tests.gd`，1314 单测基线 + 新增驱动链用例零失败
- [ ] **AC5（补）** 位移单次执行：运行时每物理帧 `_apply_movement` 恰一次（无双重位移——速度不翻倍）

### 5.2 边界情况（≥5）

| # | 边界 | 预期 |
|---|------|------|
| 1 | enemy/entity 为 null（装配前帧） | decide 门控返回清 intent；_apply_movement 无 entity 时仍消费 _move_intent（既有分支） |
| 2 | 敌人死亡（_dead=true） | decide 门控返回；_apply_movement 无位移（既有测试覆盖） |
| 3 | 实体处于 attack/stagger 等非 idle/move 态 | decide 门控返回清 intent（FSM 不抢戏）；**击退仍由 _apply_movement 执行**（本 PRD 关键保障） |
| 4 | 弹反抑制窗内（Time 门控） | decide 清 intent；位移零（抑制窗语义不变） |
| 5 | 空 waypoints / 单 waypoint（#581 边界） | Patrol 原地等待不报错；位移零 |
| 6 | headless 免树（--script 测试） | `_physics_process` 手动调用：is_inside_tree() 分支走手动积分（既有第 780 行模式） |
| 7 | 多帧叠加 | 每帧恰一次位移应用，速度/击退不翻倍（assert 或测试计数验证） |

### 5.3 失败路径（≥3）

| # | 失败 | 处理 |
|---|------|------|
| 1 | 修复后测试位移断言失败（decide 内位移移除影响） | _tick 驱动改 `_physics_process` 后断言语义不变；若个别用例仍直接调 decide 断言位移 → 该用例改为走 _physics_process（属预期测试更新） |
| 2 | 击退回归（stagger 不位移） | _apply_movement 击退分支零改动 + AC3 专项用例保障；若回归 → 检查是否误把击退移入 decide |
| 3 | 双重位移（速度翻倍） | 运行时断言/测试计数 `_apply_movement` 每帧恰一次；若翻倍 → 检查 decide 内残留位移调用 |

---

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 |
|------|------|:----:|
| #581 敌人 AI 基底（enemy_ai.gd / enemy_ai_states.gd） | CLOSED（PR #638 merged） | 无 |
| #682 精英 Boss AI（elite_mode/击退/蓄力重斩） | CLOSED（PR #695 merged） | **击退路径不得回归**（本 PRD 核心保障） |
| #585 组装（main_battle.gd 装配） | CLOSED（PR #666 merged） | 无（零改动） |
| #684 敌人血条 UI | CLOSED（PR #702 merged） | 无 |
| 测试基线（test_enemy_ai.gd 等，1314 单测） | 全绿 | 驱动方式更新需全绿验证 |

### 6.2 阻塞

无。

### 6.3 准备清单

- [ ] 实机冒烟：Main.tscn 运行 10s，观察敌人索敌/追击/出招（AC1/AC2 目视）
- [ ] headless 全量测试回归（AC4）
- [ ] 专项断言：位移单次执行 + 击退不回归（AC3/AC5）

---

## 7. Spike / 实验

> 本 PRD 含 2 实验（depth: standard 可选，参照 #682 先例提升交接质量）。

### 实验 1：双重位移验证（方案 A 的职责分离必要性）

- **问题:** 若照 issue 字面建议（_physics_process 先 decide 再 _apply_movement，不移除 decide 内位移调用），位移是否翻倍？
- **方法:** 临时构造「decide 内含位移 + _physics_process 再调 _apply_movement」版本，headless 手动跑 60 帧，测量 position 增量 vs 单次位移版本
- **预期结果:** 60 帧位移 = 单次版本 2 倍（速度翻倍）→ 证实必须移除 decide 内位移调用
- **对方案影响:** 证实方案 A 的职责分离是**必要**而非可选优化

### 实验 2：击退路径可达性验证（方案 B 否决依据）

- **问题:** _physics_process 只调 decide（方案 B）时，stagger 期间击退是否失效？
- **方法:** headless 构造 stagger 态敌人 + _knockback_vel>0，只调 decide 跑 5 帧，断言 position 是否变化
- **预期结果:** position 不变（decide 门控提前 return，不执行 _apply_movement）→ 击退失效
- **对方案影响:** 证实方案 B 破坏 #682 击退（AC3），否决依据成立

---

## 8. 延续上下文（交接给 plan agent）

### 8.1 系统状态

- origin/main @ c056b91（#702 merged），分支 `research/703-enemy-ai-decide-not-called`
- `enemy_ai.gd` 177+ 行：decide（门控 + FSM 推进 + **内部位移调用第 110 行**）、_physics_process（仅 _apply_movement）、_apply_movement（位移 + #682 击退）
- `test_enemy_ai.gd`：_tick 手动调 decide 驱动（第 167-175 行）；位移断言基于 ai.position.x（第 216-222/248-262/616-618/745-759 行）
- #682 击退用例已在测试中（第 1150 行手动 _physics_process 5 帧）

### 8.2 主要风险

| 风险 | 等级 | 缓解 |
|------|:----:|------|
| decide 内位移移除 → 位移断言测试更新遗漏 | Med | _tick 全局改 _physics_process；grep `ai.decide(` 逐一核对 |
| 击退回归（stagger 不位移） | Med | _apply_movement 零改动 + AC3 专项用例 |
| 双重位移（速度翻倍） | Low | 移除第 110 行后自然消除；AC5 断言兜底 |

### 8.3 下一步（plan agent）

1. **DESIGN 文档**：按方案 A 输出 `docs/DESIGN/703-enemy-ai-driver-wiring.md`——enemy_ai.gd 两处修改（_physics_process 加 decide；decide 移除 _apply_movement）+ 测试 _tick 更新；新增 2 个测试用例（运行时驱动链、位移单次执行）
2. **实现范围**：仅 `enemy_ai.gd`（2 处）+ `test_enemy_ai.gd`（_tick + 新增用例）；main_battle.gd / enemy_ai_states.gd / combat_entity.gd / constants.gd **零改动**
3. **验收**：AC1-AC5 清单（§5.1）+ headless 全绿 + 实机冒烟
4. **E2E 补强（建议）**：#695 漏网根因 = E2E 只验视觉——后续 E2E 增加「敌人 position 随时间变化」的行为断言（非本 issue 强制范围，列入建议）
5. **交接红线**：decide 门控语义、CANONICAL_STATES、# DRAFT 数值全部不动；#682 击退路径不回归
