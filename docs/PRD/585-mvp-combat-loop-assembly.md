# PRD #585 — [Integration] 组装 MVP 战斗闭环（可玩版本）

> **深度:** standard（分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=14 标注 `depth: standard` → §1–6 + §8 必填；§7 含 3 个轻量实验）
> **Agent:** game-research-agent
> **日期:** 2026-08-20
> **所有权:** `content_ownership: mechanical`（组装 = 机械工程：场景装配/信号接线/状态编排；失败字幕文案（B5 失败表达）与教学提示文案 = taste-draft 候选清单，进 PR 待用户定稿，本 PRD 不裁决）
> **引擎/目录约束:** Godot 4.7.1 / `shandong-wolf/`（manifest `game.active: shandong-wolf` + subprojects.path 单一事实源；本 PRD 全部路径前缀 `shandong-wolf/`，零 `mini-pong/` 写死）
> **研究选项:** Obsidian 知识库已搜索（`/Volumes/Obsidian/Knowledge Ocean/`：wiki 全量 grep 组装/装配/战斗循环/情绪弧/开场/教学/失败 → 无直接技术笔记；最接近的权威源 = `wiki/游戏设计理念.md`（「游戏机制是超越文本的修辞手段」——组装是情绪弧的第一次完整呈现）、`wiki/体验引擎-patterns.md`（氛围开场：低技能情绪触发器维持学习期参与度）、`wiki/肯塔基零号公路—案例分析.md`（五幕结构/环形开场）、`wiki/游戏目标与叙事收束.md`（收束感））+ 设计 brief（`docs/RAW/shandong-wolf-brief.md` §审美坐标/§核心机制/§完成定义「MVP：可玩动作系统验证…单场景战斗 + 雪夜像素氛围成立」）+ GDD（`docs/GAME_DESIGN/shandong-wolf/` 16 章）+ 只狼调参基准（`agents/skills/game-to-issues/references/sekiro-tuning-reference.md`：处决=奖励不是补刀、崩解惩罚清晰）+ 视觉配方（`references/visual-implementation-path.md` §7 处决特写）+ 同链 issues 全部 PRD/DESIGN + origin/main 源码实测（17 组件接口逐一核对）+ 开源调研（GitHub API 检索 scene composition / game loop 模板，见 §6.2）
> **来源:** backlog-promotion（`docs/RAW/game-to-issues-shandong-wolf.json` id=14，estimate 3d，priority critical）
> **前置依赖:** #573/#574/#575/#576/#577/#578/#579/#580/#581/#583/#584（9 CLOSED/status/done；#576/#582/#584 为 taste-draft 草稿已 merge、`status/human-review` 等用户定稿——v4 规则：human Issue 不进依赖链，视为已满足）

## 1. Problem Definition

### 1.1 当前行为：17 个组件全部独立交付、零接线，游戏不可玩

`scenes/Main.tscn` 仍是 #572 的 77 行纯声明式标题场景（标题 + 版本标签 + Atmosphere 实例）。战斗闭环所需的全部组件已由 #573–#584 逐个交付并通过单测，但彼此没有场景级接线：玩家不存在于场景中、敌人无出生点消费、判定器无人 bind、HUD 无人注入、处决编排器无人连接。**当前 `godot --path shandong-wolf/` 启动 = 一张静态标题画面。**

组件现状与组装缺口（gap 分析，源码实测）：

| 组件（文件/场景） | Issue | 当前状态 | 组装缺口 |
|------|-------|:-------:|---------|
| `scenes/Main.tscn` | #572 | ✅ 77 行标题场景 + Atmosphere 实例 | ❌ 无玩家/敌人/判定/HUD/反馈/失败态——本 PRD 的挂接目标 |
| `gdscripts/player_controller.gd` | #573 | ✅ CharacterBody2D 移动实体（组 `player`） | ❌ 未实例化、未定位到 PlayerSpawn |
| `gdscripts/input_controller.gd` | #573 | ✅ InputController autoload | ✅ 已注册，消费方直接订阅信号 |
| `scenes/player_stick_figure.tscn` | #574 | ✅ StickFigureController + StickFigure + AnimationPlayer | ❌ 未挂接；需与 PlayerController/CombatEntity 组合成完整玩家 |
| `gdscripts/combat_entity.gd` | #575 | ✅ CombatEntity（is_player/life_total/6 信号 + bind_input_controller） | ❌ 未实例化；玩家/敌人实体均需创建 + bind |
| `gdscripts/hud.gd` | #576 | ✅ HUD（bind_player/set_target_enemy/处决+击杀提示/`low_health_changed` 信号） | ❌ 未实例化、未挂 CanvasLayer、未 bind 双实体 |
| `gdscripts/combat_judge.gd` | #577 | ✅ CombatJudge（parry_success/block_held/hit_landed/clash/stance_broken） | ❌ 未实例化；需 `bind_entities(p,e)` + `bind_input(ic)` |
| `gdscripts/revive_orchestrator.gd` | #578 | ✅ 两条命复活编排（bind_player/is_armed） | ❌ 未实例化；需 bind 玩家实体 |
| `gdscripts/reaction_controller.gd` | #579 | ✅ 反馈矩阵（bind_judge/subscribe_entity/camera_path export） | ❌ 未实例化；需 bind_judge + subscribe 双实体 + 注入 camera_path |
| `gdscripts/execution_orchestrator.gd` | #580 | ✅ 处决触发链路已交付（stance_broken→armed→attack_pressed→execute+execute_kill+淡出） | ❌ 未实例化；需 bind_player/enemy/judge/input/feedback |
| `gdscripts/enemy_ai.gd` | #581 | ✅ EnemyAI（waypoints/player/judge export + bind_entity） | ❌ 未实例化；需 bind_entity + 注入 player/judge 引用 + 放置 EnemySpawnA |
| `scenes/battle_stage.tscn` | #583 | ✅ 2400px 舞台 + PlayerSpawn/EnemySpawnA/B + StageCamera | ❌ 未挂入 Main；三个出生点 Marker 无人消费 |
| `gdscripts/atmosphere_controller.gd` | #582 | ✅ 氛围层（`set_low_health(enabled)`） | ⚠️ Main 已实例 Atmosphere；❌ low_health 边沿信号（HUD→氛围）无人接线 |
| `gdscripts/smoke_test.gd` | #573 | ✅ 输入/移动链路（AC6） | ❌ 无完整战斗闭环场景（AC4 要求 smoke 自动跑通） |
| `e2e_shots.json` | #574+ | ✅ 组件级截图组 | ❌ 无 assembly 组（可玩闭环证据，review agent 依赖） |

### 1.2 预期行为（issue 验收条件）

1. **AC1 完整闭环无软锁**：玩家出生 → 遇敌 → 攻击/弹反 → 敌人崩解 → 处决 → 击杀，任意阶段输入/状态可恢复
2. **AC2 失败字幕**：玩家两条命耗尽 → 显示失败字幕（文案候选：『雪落无声。村口只剩你。』）
3. **AC3 击杀后 5s 余韵**：击杀敌人后场景内至少空闲 5s，雪花持续飘落
4. **AC4 5-10 分钟 MVP**：smoke test 自动跑通完整流程
5. **AC5 全绿无 pending**：compile/run 测试全绿，无 pending 组件

### 1.3 用户场景

| 场景 | 频率 | 说明 |
|------|------|------|
| A 首次游玩 | 每次 | 开场（雪夜村口，玩家持刀）→ 教学提示浮现 → 遇敌 → 弹反 → 处决 → 余韵 |
| B 死亡 | 每局 0-2 次 | 第 1 条血归零 → 原地复活（半管血）→ 第 2 条耗尽 → 失败字幕 |
| C 击杀 | 每局 ≥1 次 | 敌人崩解 → 处决 → 杀敌提示 → 5s 余韵（雪幕持续） |

## 2. Design Intent

### 2.1 为什么现状如此

- **组件"接口完备但无场景接线"是刻意设计**：分解 JSON 将 MVP 拆为 16 个独立 issue（#572–#584），每个组件交付时都预留了 `bind_*` / `subscribe_*` / `bind_entities` 程序化注入契约——这些契约就是为组装准备的。`#573` PRD 明确红线「Main.tscn 不修改；玩家实体的场景挂接由后续战斗场景 issue 负责」——**#585 就是那个"后续"**。
- **处决触发链路曾是真缺口，已被 #580 补上**：#580（feat #660）交付 `execution_orchestrator.gd`（stance_broken → armed 窗口 → attack_pressed + 距离判定 → execute + execute_kill + S 级反馈 + 崩解淡出）。组装只剩 bind 接线，无需重造。

### 2.2 为什么现在

- 11 个依赖全部满足（9 `CLOSED/status/done` + 3 taste-draft 草稿已 merge，v4 规则视为满足）；组件层单测 15 套全绿。
- 审美坐标要求"组装是情绪弧的第一次完整呈现"（开场→教学→弹反→处决→余韵），这是 MVP 收官 Issue——**组装完成即游戏可玩**（AC4：5-10 分钟可验证核心玩法）。

### 2.3 既有约束（继承自 issue body + 同链 PRD）

| 约束 | 详情 |
|------|------|
| 组装不新增视觉资产 | issue body：全部复用已有程序化组件；发现组件缺失 → 回退对应 Issue 修复，不绕过 |
| Main.tscn 改动最小化 | #573 红线精神延续：挂接优先走程序化编排脚本，场景文件只加 1 个脚本节点 |
| 零美术资产 | 程序化生成（Polygon2D/Line2D/GPUParticles2D/shader） |
| 文案 taste 不裁决 | 失败字幕（B5 失败表达）、教学提示文案 = 候选清单进 PR，用户定稿 |
| 开源优先 | issue body 强制：先调研 scene composition / game loop 模板，成熟方案优先复用，调研结果在 PR 中说明（见 §6.2） |

## 3. Impact Analysis

### 3.1 直接修改/新建

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `scenes/Main.tscn` | 主场景 | **修改**：挂接 BattleStage 实例 + 1 个 `MainBattle` 脚本节点（其余全部程序化） |
| `gdscripts/main_battle.gd` | 组装编排（新） | **新建**：实例化/定位/接线/游戏状态编排（出生→战斗→处决→击杀→余韵→失败） |
| `tests/test_main_assembly.gd` | 组装测试（新） | **新建**：闭环冒烟（挂载完整性/信号链连通/失败路径） |
| `tests/smoke_test.gd` | smoke（修改） | **修改**：追加 AC4 完整闭环场景 |
| `e2e_shots.json` | shot plan（修改） | **修改**：追加 assembly 组（可玩闭环截图证据） |

### 3.2 间接影响（只接线、零代码修改）

`hud.gd` / `combat_judge.gd` / `enemy_ai.gd` / `reaction_controller.gd` / `revive_orchestrator.gd` / `execution_orchestrator.gd` / `atmosphere_controller.gd` / `player_controller.gd` / `combat_entity.gd` / `stick_figure_controller.gd`：**不修改**（若接线中发现组件缺口 → 回退对应 Issue，红线）。`project.godot` 不修改（autoload 已注册）。`constants.gd` 不修改（只读 # DRAFT；失败字幕/余韵时序若需新常量 → 追加 # DRAFT 分区，定稿归 #584）。

### 3.3 数据流（完整战斗循环信号链，✅=已连接 / ⚠️=已声明缺消费者 / ❌=未连接）

```
InputController (autoload)
    │ attack_pressed / guard_pressed / dash_pressed
    ▼
PlayerController (移动) ── CombatEntity(玩家, is_player=true, bind_input_controller)
    │  state_changed ──► StickFigureController.consume_state  ← ✅（#574 契约）
    │
EnemyAI ── CombatEntity(敌人, life_total=1)
    │  register_attack_window ──► CombatJudge (bind_entities(p,e) + bind_input)
    │       │ parry_success / block_held / hit_landed / clash ──► ReactionController (bind_judge + subscribe 双实体) ← ❌ 组装接线
    │       │ stance_broken ──► ExecutionOrchestrator (bind_enemy) → armed → attack_pressed → execute ──► 敌人 execute_kill ──► died(final=true) ← ✅ #580 已交付，❌ 组装 bind
    │
CombatEntity.died / revived / hp_changed / stance_changed ──► HUD (bind_player / set_target_enemy) ← ❌ 组装接线
    │  low_health_changed (边沿) ──► Atmosphere.set_low_health ← ❌ 组装接线
    │
CombatEntity.died(final=true) ──► ❌ 无人监听 → 失败字幕（本 PRD §4.2 填补）
Enemy died(final=true) ──► ❌ 无人编排 → 5s 余韵 Timer（本 PRD §4.3 填补）
    │
ReviveOrchestrator (bind_player) ← ✅ #578 契约，❌ 组装 bind；died(false)→revive()→revived→HUD/反馈 ← ✅ 组件内已接
```

### 3.4 文档更新

- [x] 本 PRD → plan agent 交接（§8）
- [ ] GDD 新章节「MVP 战斗闭环组装」——post-merge agent 自动（`docs/gdd-<N>` PR）
- [ ] `docs/GAME_DESIGN/shandong-wolf/INDEX.md` 章节登记——post-merge 同批
## 4. Solution Comparison

> 按 Assembly PRD 规则：前置 Issue 已覆盖的组件设计一律不重复分析；本节只比较**组装策略**与**真正缺失的 3 个子系统**（失败字幕/余韵编排/低血接线）。

### 4.1 组装策略（核心决策）

**Approach A（推荐）：单一编排脚本 `main_battle.gd`（BattleAssembler）**
Main.tscn 挂一个 `Node2D` + `main_battle.gd`，`_ready()` 内程序化完成：实例化 BattleStage（或 Main 直接 instance）→ 消费 `PlayerSpawn`/`EnemySpawnA` 定位 → 构建玩家（PlayerStickFigure 场景 + PlayerController + CombatEntity + 视觉挂接）→ 构建敌人（CombatEntity + EnemyAI + 放置）→ 实例化 Judge/HUD/Reaction/Revive/Execution 并逐一 bind → 游戏状态编排（idle→combat→kill→afterglow→fail）。
- Pros：与组件全部程序化 bind 契约风格一致（judge/player 引用无法纯声明注入）；接线集中在一个可单测脚本；与现有测试模式（程序化实例化，test_battle_stage/test_enemy_ai 同构）天然对齐；Main.tscn 改动最小（+1 节点 + 1 场景实例）
- Cons：场景树运行时创建，静态可读性略低
- Risk：**Low**；Effort：1–1.5 周

**Approach B：全声明式 Main.tscn（手写节点树 + 信号连接）**
- Pros：场景树静态可读
- Cons：17+ 处信号接线手写易错；组件 `bind_*` 契约（player/judge 引用、Camera2D path）无法纯声明满足，仍需代码兜底；测试难驱动；与全组件测试模式冲突
- Risk：**Med-High**；Effort：1.5–2 周

**Approach C：新建独立战斗场景 + Main 切换**
- Pros：标题场景与战斗场景职责分离
- Cons：MVP 单场景无切换需求；标题场景已含 Atmosphere 需迁移；增加场景切换复杂度与软锁面
- Risk：**Med**；Effort：2 周

**推荐 A**，理由：1) 组件契约 100% 程序化 bind 风格（唯一可行的注入方式）；2) 组装逻辑可被 `test_main_assembly.gd` 程序化驱动做闭环冒烟（AC4 的前提）；3) 红线历史（Main.tscn 曾被 #573 明令不修改）要求最小侵入。

### 4.2 失败字幕（缺失子系统 1）

**A（推荐）：`main_battle.gd` 内监听 `player.died(final=true)` → 复用 Main 现有 CanvasLayer 程序化 Label 淡入**
- 时序：死亡反馈（白闪/屏震，#579 已订阅）播完后 ≥0.5s 字幕淡入 1s（参数进 constants # DRAFT）
- 文案：候选 5 选 1 进 PR 待用户定稿——『雪落无声。村口只剩你。』『雪还在下。村口没人了。』『灯灭了。雪落无声。』『村口只剩下雪。』『刀还在。你没了。』（B5 失败表达，taste-draft）
- 同时：冻结玩家输入（InputController 暂停或 PlayerController 禁用）、停止敌人 AI
- Pros：零新场景；与 Main CanvasLayer 现有结构一致；字幕淡入可单测/E2E 截图
- Cons：无（MVP 单字幕足够）
- Risk：**Low**；Effort：0.5 天

**B：独立 `game_over.tscn` 场景**——Pros：可复用扩展；Cons：MVP 过重，且需场景切换状态机；Risk：Med
**C：HUD 扩展承担失败态**——越权（HUD 管战斗条/提示，不管全局失败编排）；Risk：Med

### 4.3 击杀后 5s 余韵编排（缺失子系统 2）

**A（推荐）：`main_battle.gd` 内轻量状态机 + Timer**
- `enemy.died(final=true)` → 杀敌提示（HUD kill 提示）→ 进入 afterglow 态：5s Timer（常量 `AFTERGLOW_SECONDS = 5.0` # DRAFT）→ 期间雪花持续（Atmosphere 不干预，天然持续）→ 到期回 idle（等待下一波/再战；敌人重生不在 MVP 范围——AC3 只要求"至少空闲 5s"）
- 玩家在余韵期间可自由移动（只读输入），攻击无目标自然落空（无软锁验证点）
- Pros：编排集中在组装脚本；可单测（时序断言）；与 AC3 逐字对应
- Cons：无
- Risk：**Low**；Effort：0.5 天

**B：独立 StageController 节点**——多一层抽象，MVP 单场景不需要；Risk：Low-Med
**C：裸 Timer 无状态**——可读性差、难断言；Risk：Med

### 4.4 低血氛围接线（缺失子系统 3，⚠️→✅）

- HUD 已发出 `low_health_changed(enabled)` 边沿信号（#576 契约），Atmosphere 已有 `set_low_health(enabled)`（#582 契约）——**只差一行连接**：组装时 `hud.low_health_changed.connect(atmosphere.set_low_health)`。
- 无方案竞争（单一接线路径），列为组装清单第 10 步，test_main_assembly 断言边沿触发恰好一次。

### 4.5 推荐组合表

| 子系统 | 推荐 | 核心文件 |
|--------|------|---------|
| 组装策略 | A：BattleAssembler 编排脚本 | `gdscripts/main_battle.gd`（新） |
| 处决触发 | 复用 #580 `execution_orchestrator.gd`（bind 接线，零改动） | `main_battle.gd` bind 5 项 |
| 失败字幕 | A：CanvasLayer Label 淡入 + 输入冻结 | `main_battle.gd`（复用 Main CanvasLayer） |
| 余韵 5s | A：assembler 内状态机 + Timer | `main_battle.gd` |
| 低血氛围 | 单点接线 `low_health_changed → set_low_health` | `main_battle.gd` |

## 5. Boundary Conditions & Acceptance Criteria

### 5.1 AC 映射（issue 5 条）

- [x] **AC1 完整闭环无软锁**——smoke 场景程序化驱动：出生→接近→敌人攻击→弹反→崩解→处决→击杀；每阶段断言状态可达、输入可恢复
  - 验证：test_main_assembly 闭环用例 + smoke 场景
- [x] **AC2 失败字幕**——玩家 life_total=2 双死 → 字幕 Label 可见且文案 ∈ 候选清单
  - 验证：test_main_assembly 失败路径用例（died(true) → Label.visible + 文案断言）
- [x] **AC3 击杀后 5s 余韵**——敌人 final death 后 afterglow 态持续 ≥5s，雪花粒子持续（Atmosphere 无暂停路径）
  - 验证：时序断言（Timer 到期前状态不变、到期后回 idle）
- [x] **AC4 5-10 分钟 MVP**——smoke test 自动跑通完整闭环（headless，`godot --headless --script tests/smoke_test.gd` exit 0）
  - 验证：CI smoke job
- [x] **AC5 全绿无 pending**——`run_tests.gd` 15 套既有 + 新增套件全绿；场景内无未接线组件（test 断言每个 bind 目标非 null）

### 5.2 边界条件（≥5）

1. **execute 态再按攻击**——`execution_orchestrator` armed 已清除 + `request_transition("execute")` 幂等（#580 已实现，组装验证即可）
2. **复活无敌期受击**——`CombatEntity.take_damage` 无敌期 no-op 双保险（#578 已实现），组装验证接线后仍生效
3. **处决演出期间玩家受击**——`take_damage` execute 态 no-op 守卫（#575 已实现）
4. **敌人 final death 后 AI**——`enemy_ai._dead=true` 全禁（#581 已实现）；execution_orchestrator `_on_enemy_died` 自动解绑防 queue_free 后访问（#580 已实现）
5. **低血边沿恰好一次**——HUD 边沿触发语义（#576），组装接线后不得重入/漏发（test 断言）
6. **余韵期间无目标攻击**——自然落空，无错误/无软锁（AC1 延伸）
7. **失败字幕出现后再输入**——输入已冻结，无状态迁移（无软锁）
8. **组装顺序依赖**——先 bind 后驱动（如 judge.bind_entities 必须先于首帧 resolve），test 按顺序驱动断言

### 5.3 失败路径（≥3）

1. **漏接线**（如 judge 未 bind_input）→ test_main_assembly 信号链连通断言红，CI 拦截
2. **处决窗口错过** → stance_break 自动回 idle + `recover_from_break()`（#580 双保险）→ 敌人架势恢复再战，无软锁
3. **玩家双死** → 失败字幕 + 输入冻结 + AI 停止，无卡死
4. **Main.tscn 资源路径错误** → test 场景加载断言红
## 6. Dependencies & Blockers

### 6.1 依赖表

| 依赖 | 状态 | 风险 |
|------|------|------|
| #573 输入映射/玩家控制器 | ✅ CLOSED/status/done | 无 |
| #574 火柴人剪影动画 | ✅ CLOSED/status/done | 无 |
| #575 战斗实体+状态机 | ✅ CLOSED/status/done | 无 |
| #576 HUD 架势条 | ⏸ OPEN/status/human-review（taste-draft 草稿 merged） | 低：v4 视为满足；文案定稿不阻塞机械组装 |
| #577 弹反/格挡/崩解判定 | ✅ CLOSED/status/done | 无 |
| #578 两条命复活 | ✅ CLOSED/status/done | 无 |
| #579 打击反馈 | ✅ CLOSED/status/done | 无 |
| #580 处决系统 | ✅ CLOSED/status/done（execution_orchestrator 已合入 origin/main） | 无：组装只 bind |
| #581 敌人 AI | ✅ CLOSED/status/done | 无 |
| #583 雪夜山东村战斗场景 | ✅ CLOSED/status/done | 无 |
| #584 战斗数值草稿 | ⏸ OPEN/status/human-review（草稿 merged） | 低：只读 # DRAFT 不裁决 |
| #582 雪夜氛围（不在 issue 依赖表；Main 已实例 Atmosphere） | ⏸ OPEN/status/human-review | 低：接线已含 |

### 6.2 开源调研（issue body 强制，结论进 PR 说明）

GitHub API 检索 3 组（2026-08-20）：
- **godot 2d combat template**：`old-man77/combat-core-template-godot` ★7（2D 战斗系统基础模板）——信号驱动/组合式架构与本项目一致，但其组件未覆盖本项目 11 态 FSM 与只狼体系，**不引入**，编排模式作参考
- **godot scene composition**：`willnationsdev/godot-skills` ★44（场景即技能组合系统）——组合思想与本项目 StickFigure/CombatEntity 分层一致，**不引入**
- **godot game loop template**：`ArneshDorsatwar/godot-rpg-kids-template` ★0（完整 game loop：战斗/敌人/HUD/game over）——验证"失败字幕+余韵"是标配闭环元素，**不引入**

**结论**：成熟模板均为独立完整方案，与已有 17 组件契约冲突（引入 = 重写全部组件，违反"组装不新增/不重造"红线）；本组装按 Approach A 复用全部自有组件（零新资产），编排模式借鉴信号驱动/组合式场景树。→ 该结论由 implement 阶段在 PR 中说明。

### 6.3 依赖链

```
#573 输入/移动 ──► #575 战斗实体 ──► #577 判定 ──► #580 处决（execution_orchestrator）
     └──► #574 玩家视觉 ────────────────────────────┘
#578 两条命复活 ───────────────────────────────────────┐
#583 战斗场景（出生点 Marker）──────────────────────────┤
#576 HUD + #579 反馈 + #582 氛围 ──────────────────────┤→  #585 组装（本 PRD）
#581 敌人 AI + #584 数值（只读）────────────────────────┘
```

### 6.4 准备清单

- [x] origin/main 已 pull（worktree 基于最新 origin/main，#580 处决已合入）
- [x] 组件接口逐一核对（bind 签名/信号名/export 名）
- [ ] plan agent：读 §8 接线清单 + 各组件 DESIGN（#575/#577/#578/#579/#580/#581）

## 7. Spike / Experiment（depth/standard 含实验）

1. **组装顺序与时序**——Question：`_ready()` 内实例化+bind 的先后是否影响首帧判定（judge 未 bind 前首帧 resolve）？Method：test_main_assembly 按 §8 接线顺序程序化驱动 120 帧闭环；Expected：顺序敏感点 0 个（bind 全在 _ready 同步完成，首帧前就绪）；Impact：决定 §4.1 方案 A 的接线顺序契约
2. **失败字幕时序**——Question：died(final=true)→字幕淡入是否与死亡反馈（白闪/屏震）视觉打架？Method：E2E assembly 组 fail shot（e2e_capture.gd 驱动）；Expected：死亡反馈后 ≥0.5s 字幕淡入 1s，截图可辨；Impact：决定 §4.2 延时参数（constants # DRAFT 追加）
3. **余韵 5s 状态边界**——Question：击杀后 5s 内玩家移动/攻击是否破坏余韵或触发错误？Method：smoke 场景时序断言（afterglow 期间注入 move/attack）；Expected：只读输入不打断、无目标攻击落空无报错；Impact：决定 §4.3 状态机边界（回 idle 条件）

## 8. Continuation Context

**系统状态**：shandong-wolf 17 组件全部交付（含 #580 execution_orchestrator 处决链路），15 套单测全绿；Main.tscn 为 77 行标题场景；worktree 分支 `research/585-mvp-combat-loop-assembly` 含本 PRD。

**接线清单（plan agent 逐项落地，顺序即依赖顺序）**：
1. Main.tscn：instance `battle_stage.tscn`（放 Main 下）+ 挂 `Node2D` + `main_battle.gd`
2. 玩家：`player_stick_figure.tscn` 实例 + `PlayerController`（CharacterBody2D，组 player）+ `CombatEntity(is_player=true, life_total=2, bind_input_controller(InputController))` + 视觉挂接（StickFigureController.consume_state ← entity.state_changed）
3. 玩家定位：BattleStage/PlayerSpawn 坐标
4. 敌人：`CombatEntity(life_total=1)` + `EnemyAI`（bind_entity + player/judge 注入）+ 放置 EnemySpawnA（EnemySpawnB 备用）
5. Judge：`bind_entities(player, enemy)` + `bind_input(InputController)`；敌人攻击窗口经 EnemyAI.register_attack_window
6. HUD：实例挂 CanvasLayer；`bind_player(player)` + `set_target_enemy(enemy)`
7. ReactionController：`bind_judge(judge)` + `subscribe_entity(player/enemy)` + `camera_path = BattleStage/StageCamera`
8. ReviveOrchestrator：`bind_player(player)`
9. ExecutionOrchestrator：`bind_player/bind_enemy/bind_judge/bind_input/bind_feedback`（#580 契约，5 项全 bind）
10. 低血氛围：`hud.low_health_changed → atmosphere.set_low_health`（单点连接）
11. 失败字幕：监听 `player.died(final=true)` → CanvasLayer Label 淡入（文案候选清单 §4.2）+ 输入冻结 + AI 停止
12. 余韵编排：监听 `enemy.died(final=true)` → 杀敌提示 → afterglow 5s Timer → 回 idle
13. 教学提示（开场情绪弧）：开局 3s 内浮现操作提示（移动/攻击/格挡键位），文案 taste 候选，可并入 HUD 或 assembler 轻量实现

**风险**：1) 接线顺序敏感（§7 实验 1 验证）；2) 失败字幕/余韵时序参数需追加 constants # DRAFT（不裁决，定稿归 #584）；3) taste 文案（失败字幕/教学提示）候选清单需随 PR 提交供用户定稿。

**测试面**：新增 `test_main_assembly.gd`（挂载完整性/信号链连通/闭环冒烟/失败路径）+ smoke_test.gd 追加 AC4 场景 + e2e_shots.json 追加 assembly 组（闭环/处决/失败/余韵截图）。跑法：`godot --path shandong-wolf/ --headless --script tests/run_tests.gd` 与 `tests/smoke_test.gd`。

**下一步**：plan agent 依据本 PRD §8 接线清单产出 DESIGN（含测试用例描述），implement agent 落地 `main_battle.gd` 后按 CI 验证；review agent 本地 E2E 截图（assembly 组）作为 merge 证据；post-merge 更新 GDD。
