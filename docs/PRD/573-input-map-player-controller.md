# PRD #573 — [Feature] 输入映射与玩家控制器（Input Map + 意图事件 + 输入缓冲）

> **Issue:** #573
> **标签:** enhancement, gameplay, workflow/research, version/mvp（GitHub 现状；分解 JSON 源标签 enhancement/gameplay/workflow/backlog）
> **深度:** standard（GitHub 无 depth label；分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=2 标注 `depth: standard` → §1–6 + §8 必填，§7 含 3 个轻量实验）
> **Agent:** game-research-agent
> **日期:** 2026-08-19
> **所有权:** `content_ownership: mechanical`（输入层为机械工程，无品味裁决空间；弹反窗口/帧节奏等手感数值定稿归 #584 / 分解 id 13，本 issue 只读取不裁决）
> **引擎/目录约束:** Godot 4.7.1 / `shandong-wolf/`（manifest `game.active: shandong-wolf` + subprojects.path 单一事实源；本 PRD 全部路径前缀 `shandong-wolf/`，零 `mini-pong/` 写死）
> **研究选项:** Obsidian 知识库已搜索（`~/Documents/Obsidian Vault/`，wiki grep 只狼 → `wiki/游戏设计理念.md`（只狼列为灵感来源）；raw grep 弹反/格挡/架势 → `raw/Bear/JRPG 战斗系统研究 - 最终综合报告.md`（「弹反/闪避 = 时机判定」动作游戏进阶层））+ 设计 brief（`docs/RAW/shandong-wolf-brief.md`）+ 分解 JSON id=2（本 issue 源定义，github_number=573）+ GDD（`docs/GAME_DESIGN/shandong-wolf/01-OVERVIEW.md`）+ 只狼调参基准（`agents/skills/game-to-issues/references/sekiro-tuning-reference.md`）+ 开源插件调研（GitHub API 检索 6 个候选，见 §6.2）
> **来源:** backlog-promotion（`docs/RAW/game-to-issues-shandong-wolf.json` id=2，estimate 2d，priority high）
> **前置依赖:** #572（merged，research #597 → plan #598 → impl #599 → GDD #600；`constants.gd` / `state_machine.gd` / `Game` autoload 已交付）

---

## 1. 问题定义

### 1.1 现状（shandong-wolf/ 输入层状态，2026-08-19 worktree 侦查 @ origin/main 7736855）

| 文件 | 状态 | 说明 |
|------|:----:|------|
| `shandong-wolf/project.godot` | ⚠️ 无 `[input]` 段 | 仅 `[application]/[display]/[autoload]`（Game 已注册）；**零 Input Map 定义**——移动/攻击/格挡等全部动作不存在，`Input.is_action_pressed("game_*")` 会直接报错 |
| `shandong-wolf/gdscripts/constants.gd` | ✅ 已交付（#599） | 已有 `PARRY_WINDOW_FRAMES=12`（# DRAFT，候选 [8,10,12,14] 内）、`FRAME_ATTACK_WINDUP=8`、`FRAME_ATTACK_RECOVERY=14`、`FRAME_RHYTHM_BASE=60`；**无输入层分区**（无缓冲窗口、无移动加速度/最高速度参数） |
| `shandong-wolf/gdscripts/game.gd` | ✅ 已交付（#599） | `Game` autoload 锚点，注释明言「后续系统（**输入**/战斗/音频）挂接于此」——输入控制器挂载点已预留 |
| `shandong-wolf/gdscripts/state_machine.gd` | ✅ 已交付（#599） | `StateMachineBase`（enter/exit/update + transition_to 防重入），#575 战斗状态机派生用 |
| `shandong-wolf/gdscripts/` 玩家实体 | ❌ 不存在 | 无 player 脚本、无 `is_in_group("player")`、无 `body_entered/body_exited` 近距探测（Patch 9 检查：shandong-wolf 全空）；无 addons 目录，无 dialogue 插件 → Space 键无冲突 |
| `shandong-wolf/scenes/Main.tscn` | ✅ 标题场景（#562/#563/#570） | 纯声明式标题，无玩家节点；#573 不修改它（红线） |
| `shandong-wolf/tests/` | ⚠️ 三入口占位 | run_tests.gd 尚未挂载输入相关测试；smoke_test.gd 为骨架探针 |

**核心缺口：** shandong-wolf 有地基（constants/state_machine/Game autoload）但**输入层零存在**——无 Input Map（`game_` 前缀动作全部缺失）、无输入缓冲（连招/快速连按会丢输入）、无意图事件契约（后续 #3 动画、#6 判定无从消费输入）。本 issue 交付 = Input Map 定义 + InputController（意图事件发射 + 输入缓冲）+ PlayerController（移动实体）+ smoke 可断言。

### 1.2 验收条件（源自 Issue #573 body，映射到本 PRD 保障）

| # | 验收条件 | 本 PRD 的保障措施 |
|---|---------|------------------|
| AC1 | Input Map 完整：移动 A/D、轻击 J、重砍 K、格挡/弹反 L（同键）、垫步 Shift、跳 Space、交互 E、复活 F——project.godot 可查见 | §4.1 方案 A + §5.1 AC1：`game_` 前缀动作全清单，含 ←/→ 与鼠标左右键候选 |
| AC2 | 格挡=弹反同键验证：按住=格挡姿态（持续有效），弹反窗口内按下=弹反（窗口从 constants.gd 读取，只狼基准 10-14 帧） | §4.2 + §5.1 AC2：`guard_pressed`（按下时机+时间戳）与 `guard_held`（按住持续）语义分离；窗口只读 `PARRY_WINDOW_FRAMES`，判定归 #6（本 issue 不判定） |
| AC3 | 处决自动衔接：靠近架势崩解敌人按攻击自动进入处决（不额外按键） | §5.1 AC3：**处决不新增映射**——复用 `attack_pressed`；完整闭环依赖 #6 消费事件（跨系统 AC，见 §8 交接） |
| AC4 | 输入缓冲：收招前 100-200ms 内输入自动衔接下一动作（smoke test 可断言） | §4.2 方案 A：时间戳缓冲队列，窗口 `INPUT_BUFFER_WINDOW_MS`（# DRAFT 150ms ∈ [100,200]） |
| AC5 | 快速连按不丢输入：300ms 内 3 连击全部生效（缓冲队列 ≥1，无吞噬） | §4.2 + §5.1 AC5：队列无覆盖语义，3 连击全入队全可消费 |
| AC6 | smoke test：模拟按键可驱动玩家 2 秒内位移 ≥100px，攻击/格挡/垫步事件信号均可被捕获 | §4.3 方案 A + §5.1 AC6：`Input.action_press` 驱动 + 位移断言 + 信号捕获断言 |

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 玩家实机操作 | 每次游玩 | 横板左右移动 + 轻/重攻击 + L 按住格挡 / 时机弹反 + Shift 轻按垫步 / 按住冲刺 + Space 跳 + E 交互 + F 复活；按键「少而精，一键有深度」（只狼哲学） |
| B | 后续 feature issue（分解 id 3/6/13） | 每次 impl PR | 动画（#3）消费意图事件播关键帧；弹反判定（#6）消费 `guard_pressed`（含时间戳）对齐攻击帧；数值定稿（#13）接管 constants # DRAFT——本 issue 的事件契约是它们的前置输入 |
| C | 开发者 smoke 验证 | 每次 impl PR | `godot --path shandong-wolf/ --headless --script tests/smoke_test.gd` 模拟按键驱动玩家位移 + 捕获事件信号，输入层可回归 |

### 1.4 范围边界（Patch 14 去冲突）

| PRD / 分解 id | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|------------------|
| #572（scaffold-main-entry，merged） | constants.gd / state_machine.gd / Game autoload 地基 | ❌ 不重写地基；只在 `Game` autoload 下挂 `InputController` 子节点 + 给 constants.gd 追加输入层 # DRAFT 分区 |
| 分解 id 3（火柴人剪影骨架） | 动画消费**状态**（非输入），播放攻击/格挡/弹反关键帧 | ❌ 不做任何视觉/动画；只保证意图事件信号可达 |
| 分解 id 6（拼刀/弹反/架势判定） | 消费 `guard_pressed` 时间戳做弹反窗口判定、消费 `guard_held` 做格挡判定 | ❌ 不做判定逻辑；本 issue 的 `guard_pressed` = 原始按下事件（仅含时间戳），判定归 #6 |
| 分解 id 13 / #584（数值 DRAFT 定稿） | 弹反窗口/架势/帧节奏定稿 + F1 调参面板 | ❌ 不裁决数值；`PARRY_WINDOW_FRAMES` 等只读不改，新增输入层参数也标 # DRAFT 待定稿 |
| mini-pong 先例（paddle.gd 直接轮询按键） | 迷你乒乓的即时键盘轮询 | ❌ 不采用轮询模式（无缓冲无事件，违反只狼输入哲学）——仅作反例参考 |

---

## 2. 设计意图

### 2.1 为什么现状如此

| 约束来源 | 说明 |
|---------|------|
| #572 只交付地基 | 分解链 id 1（#572）范围 = constants + state_machine + autoload 锚点；输入层是 id 2（本 issue）的第一块拼图，Game autoload 注释已预留挂接点 |
| mini-pong 输入先例是轮询 | mini-pong 为休闲乒乓，`paddle.gd` 直接 `Input.is_action_pressed` 轮询——无缓冲、无事件、无多义键；类只狼动作游戏必须事件化 + 缓冲化 |
| 分解契约先行 | 分解 JSON 已定义「输入契约（2026-08-19 对齐 #2）」：`attack_pressed/heavy_attack_pressed/guard_pressed/guard_held/dash_pressed/jump_pressed/interact_pressed/revive_pressed` 信号清单 + `guard_pressed` 仅含时间戳不做判定 + 弹反窗口读 constants.gd——本 PRD 落地的正是这份契约 |

### 2.2 为什么现在做

- #572 已合并（#599 交付地基），#573 是分解链中紧随其后的输入层 issue（estimate 2d，priority high）；
- 2026-08-19 用户拍板：**玩家主要操作对标只狼**——按键少而精、一键多义（格挡=弹反、攻击=处决、垫步轻按/按住双义）；
- 输入事件契约是 #3（动画）与 #6（判定）的前置——契约不先落地，下游消费方无从实现。

### 2.3 前序约束（本 issue 必须遵守）

| 约束 | 详情 |
|------|------|
| 只狼输入哲学（强制） | ①同键多义：格挡键=弹反键（按住防御/时机弹反），攻击键=处决键；②输入缓冲：收招前 100-200ms 输入自动衔接；③无输入吞噬：缓冲队列 ≥1；④前摇可取消：攻击前摇可取消为垫步 |
| 控制器不直接访问战斗逻辑 | 通过信号发射意图事件；`guard_pressed` = 原始按下事件（仅含时间戳），弹反判定由 #6 消费完成 |
| 输入映射名统一前缀 | 所有动作名 `game_` 前缀（§3.1 全清单） |
| 弹反窗口只读 constants.gd | `PARRY_WINDOW_FRAMES=12`（# DRAFT，只狼基准 10-14 帧候选 [8,10,12,14]）；本 issue 读取不修改、不判定 |
| 视觉表现归 #3 | 本 issue 只做逻辑输入层，零渲染零美术资产 |
| 禁页游式 | 禁止自动寻路/自动战斗/一键技能；无输入时玩家静止 |
| 帧节奏参考 | 攻击帧 6-8 帧、移动起步 2 帧、加速度大（「冷冽干脆」）——移动参数落 constants.gd # DRAFT |

---

## 3. 影响分析

### 3.1 直接影响的模块（全部位于 `shandong-wolf/`）

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `project.godot` | Input Map | **修改**：新增 `[input]` 段，8 个 `game_` 前缀动作（§3.1.1） |
| `gdscripts/input_controller.gd` | InputController（新文件） | **新建**：意图事件发射 + 输入缓冲队列；挂 `Game` autoload 下 |
| `gdscripts/player_controller.gd` | PlayerController（新文件） | **新建**：CharacterBody2D 玩家实体，消费移动意图 + 转发事件 |
| `gdscripts/constants.gd` | WolfConstants | **修改**：追加输入层 # DRAFT 分区（缓冲窗口/移动加速度/最高速度/垫步长按阈值/队列上限） |
| `tests/test_input_controller.gd` | 单测（新文件） | **新建**：缓冲无吞噬、同键双义、时间戳语义 |
| `tests/test_player_controller.gd` | 单测（新文件） | **新建**：位移断言、事件捕获 |
| `tests/run_tests.gd` | 测试入口 | **修改**：挂载两个新测试套件（现为占位） |

#### 3.1.1 Input Map 动作全清单（`game_` 前缀，AC1 交付物）

| 动作名 | 主键 | 候选键 | 语义 |
|--------|------|--------|------|
| `game_move_left` | A | ← | 横板左移（轴） |
| `game_move_right` | D | → | 横板右移（轴） |
| `game_light_attack` | J | 鼠标左键 | 轻击 |
| `game_heavy_attack` | K | 鼠标右键 | 重砍（蓄力预留） |
| `game_guard` | **L** | — | 同键双义：按住=格挡姿态 / 按下时机=弹反输入 |
| `game_dash` | **Shift** | — | 轻按=垫步 / 按住=冲刺（时长阈值区分） |
| `game_jump` | Space | — | 跳跃 |
| `game_interact` | E | — | 交互/捡刀 |
| `game_revive` | F | — | 两条命倒地提示时复活 |

> **键位裁决（表格歧义澄清）：** issue 映射表中格挡/弹反键位写「L/Shift」，而垫步/冲刺为 Shift（轻按/按住双义）。若 guard 与 dash 共用 Shift，同帧「按住」语义冲突（按住=格挡姿态 vs 按住=冲刺，无法共存）。**以 AC1 为准裁决：`game_guard`=L 独键，`game_dash`=Shift**（轻按/按住双义）。此裁决写入 PR 说明与 GDD 补记。

### 3.2 数据流影响（意图事件链）

```
物理按键 (A/D/J/K/L/Shift/Space/E/F)
    │  Input Map (game_*) — project.godot [input]
    ▼
InputController (Game autoload 子节点)
    ├── 连续轴: game_move_left/right ──► PlayerController.velocity（加速度模型）──► 位移
    ├── 边沿事件: attack/heavy_attack/guard/dash/jump/interact/revive_pressed
    │       └── 输入缓冲队列（时间戳, 窗口 INPUT_BUFFER_WINDOW_MS）— 无吞噬
    ├── guard_pressed(timestamp) ──► #6 弹反判定（本 issue 不判定, 只发原始按下事件）
    ├── guard_held(持续) ──► #6 格挡判定 / #4 状态机格挡姿态
    ├── attack_pressed ──► #4 状态机 attack 状态（处决复用此键, 上下文判定归 #6）
    └── 全部意图事件 ──► #3 火柴人动画（消费状态, 不读输入）
```

### 3.3 间接受影响的模块

| 模块 | 影响 |
|------|------|
| `state_machine.gd`（#572 交付） | 不修改；#575 战斗状态机将消费意图事件驱动状态迁移 |
| `scenes/Main.tscn` | 不修改（红线）；玩家实体的场景挂接由后续战斗场景 issue 负责，smoke 测试程序化实例化 PlayerController |
| 测试三入口（compile/smoke/run） | check_compile 自动纳入新 .gd；smoke 扩展输入断言；run_tests 挂载新单测 |
| `game-env/manifest.yaml` | 不修改 |

### 3.4 需更新的文档

- [x] `docs/PRD/573-input-map-player-controller.md`（本 PRD）
- [ ] GDD 补记（post-merge agent）：输入映射表 + 意图事件契约 + InputController 接口
- [ ] `docs/RAW/shandong-wolf-brief.md`（只读参考，不修改）

---

## 4. 方案对比

### 4.1 输入层架构（InputController 形态）

| | 方案 A：独立 InputController + 信号意图事件（推荐） | 方案 B：PlayerController 内直接轮询 | 方案 C：第三方输入插件 |
|--|----------------------------------------------|----------------------------------|----------------------|
| 描述 | `InputController`（Node，挂 Game autoload 下）：读取 Input Map，边沿检测 → 发射意图事件信号；连续轴 → 供 PlayerController 查询；内部含输入缓冲队列 | PlayerController 的 `_unhandled_input` 里直接轮询 `Input.is_action_*` 并自行驱动状态 | 引入 `drkitt/godot-input-buffer`（61⭐）等插件提供缓冲 |
| 优点 | 精确满足 issue「控制器不直接访问战斗逻辑，通过信号发射意图事件」硬性契约；#3/#6 可独立监听；Game autoload 注释「输入系统挂接于此」；可单测 | 代码最少；无中间层 | 缓冲逻辑现成 |
| 缺点 | 多一个文件（~150 行） | **违反 issue 契约**（控制器直连战斗逻辑）；#6 判定、#3 动画无法独立消费事件；缓冲需自行塞进 PlayerController，职责混乱 | 插件不提供本项目契约信号（`guard_pressed` 时间戳语义等）；引入 .godot 插件导入链与版本兼容风险（#572 红线「不引入插件 addon」）；缓冲本身 ~40-60 行，轮子过小 |
| 风险 | Low | Med（架构违约，下游重做） | Med-High（兼容性 + 契约不匹配） |
| 工作量 | 2-3 天（含单测） | 1 天 | 1-2 天（+集成调试） |

### 4.2 输入缓冲实现（AC4/AC5 核心）

| | 方案 A：时间戳缓冲队列（推荐） | 方案 B：单槽覆盖（只存最近一次） | 方案 C：插件缓冲库 |
|--|------------------------------|------------------------------|------------------|
| 描述 | `Array[Dictionary]`（{action, timestamp_ms}），每帧清理超窗条目，消费出队；队列上限 `INPUT_BUFFER_MAX`（# DRAFT 8） | 新输入覆盖旧输入 | drkitt/godot-input-buffer 等 |
| 优点 | **无吞噬**（AC5：300ms 3 连击全保留）；窗口参数化（100-200ms 可调）；消费方（#6 弹反判定）可按时间戳对齐攻击帧 | 实现 10 行 | 现成 |
| 缺点 | ~50 行 + 边界处理（过期清理/上限） | **丢输入**——直接违反 AC5 | 契约不匹配（信号名/时间戳自定义）；插件依赖 |
| 风险 | Low | High（AC5 必挂） | Med |
| 工作量 | 1 天 | 0.5 天 | 1 天 |

### 4.3 玩家移动实体（AC6）

| | 方案 A：CharacterBody2D + 加速度模型（推荐） | 方案 B：Node2D 直接改 position | 方案 C：平台跳跃控制器插件 |
|--|--------------------------------------------|------------------------------|--------------------------|
| 描述 | CharacterBody2D，`velocity.x = move_toward(velocity.x, dir * MAX_SPEED, ACCELERATION * delta)`；无重力（横板侧视，战斗判定面）；起步 2 帧、加速度大（冷冽干脆） | 无物理体，直接 `position += dir * speed * delta` | Drumstickz64/godot_2d_platformer_controller（5⭐）等 |
| 优点 | 为 #6 物理命中窗口、#575 战斗实体基类预留；`move_and_slide` 后续可加碰撞/地面；标准 Godot 模式 | 最简单；位移可精确断言 | 现成 |
| 缺点 | 需 `velocity` 初始化（无重力时手动归零） | 后续加碰撞/判定要重构为物理体；无 `is_in_group("player")` 基础设施（#6 需要） | 平台跳跃语义（重力/跳跃缓冲/土狼时间）与本项目横板动作不匹配；插件依赖 |
| 风险 | Low | Med（后续重构） | Med |
| 工作量 | 1 天 | 0.5 天 | 1 天 |

### 4.4 推荐组合（结论表）

| 子系统 | 推荐方案 | 核心文件 |
|--------|---------|---------|
| 输入层架构 | A：InputController + 信号意图事件 | `shandong-wolf/gdscripts/input_controller.gd` |
| 输入缓冲 | A：时间戳缓冲队列（窗口 constants.gd 参数化） | `input_controller.gd` 内 `_buffer` + `INPUT_BUFFER_WINDOW_MS` |
| 玩家移动 | A：CharacterBody2D + 加速度模型 | `shandong-wolf/gdscripts/player_controller.gd` |
| Input Map | 8 个 `game_` 前缀动作（§3.1.1） | `shandong-wolf/project.godot [input]` |

**推荐理由：** ① 方案 A 全部满足 issue 硬性契约（信号清单、`guard_pressed` 时间戳语义、缓冲 ≥1 无吞噬、`game_` 前缀、只读 constants.gd）；② 零插件零美术资产，符合 #572 红线与骨架期最小化；③ 每个 AC 都有对应单测/smoke 断言（§5），回归成本低；④ 为 #3/#6/#575 建立无歧义的事件契约，后续 plan 无需重新侦查。

---

## 5. 边界条件与验收标准

### 5.1 正常路径（AC 清单，映射 issue body 验收条件）

- [x] **AC1: Input Map 完整** — `project.godot [input]` 段含 §3.1.1 全部 8 个 `game_` 前缀动作（A/D/←/→ 移动、J/左键轻击、K/右键重砍、L 格挡/弹反、Shift 垫步/冲刺、Space 跳、E 交互、F 复活）
  - 验证：`grep -A2 '^game_' shandong-wolf/project.godot` 全清单可查见；check_compile 通过
- [x] **AC2: 格挡=弹反同键** — `game_guard` 按下边沿 → `guard_pressed(timestamp)`（仅一次，原始按下事件）；按住持续 → `guard_held` 连续；窗口只读 `constants.gd PARRY_WINDOW_FRAMES`（本 issue 不判定，判定归 #6）
  - 验证：单测 `test_input_controller.gd`：action_press(L) 不 release，断言 guard_pressed 恰 1 次 + guard_held 连续 ≥2 帧；读 `WolfConstants.PARRY_WINDOW_FRAMES == 12` 不修改
- [x] **AC3: 处决不额外按键** — 无 `game_execute` 映射；`attack_pressed` 事件任意时刻可达（复用攻击键）；「靠近架势崩解敌人 → 自动处决」的上下文判定闭环归 #6（本 PR 交付输入侧保障：attack 事件不因场景状态被吞）
  - 验证：smoke 断言 `attack_pressed` 信号可捕获；PR 说明中标注跨系统 AC 依赖 #6
- [x] **AC4: 输入缓冲 100-200ms** — `INPUT_BUFFER_WINDOW_MS`（# DRAFT 150ms ∈ [100,200]）；收招前窗口内输入自动衔接（消费方 poll 到缓冲输入）
  - 验证：单测：action_press(attack) 后 100ms 内 poll 仍可取到；200ms 后过期清理
- [x] **AC5: 快速连按不丢输入** — 缓冲队列无覆盖语义；300ms 内 3 连击全部入队、全部可消费（队列 ≥1）
  - 验证：单测：间隔 100ms 连按 3 次 attack → 队列 3 条 → 消费 3 次全成功；`INPUT_BUFFER_MAX` 上限不丢已入队条目（只拒超额新条目）
- [x] **AC6: smoke test** — `Input.action_press(game_move_right)` 2 秒 → PlayerController 位移 ≥100px；attack/guard/dash 事件信号均被捕获
  - 验证：`godot --path shandong-wolf/ --headless --script tests/smoke_test.gd` 退出码 0；位移断言 + 信号捕获断言

### 5.2 边界情况（≥5）

1. **左右同帧同按**：`game_move_left` + `game_move_right` 同帧 → 移动向量归零（velocity.x=0，横板惯例），不 panic
2. **Shift 轻按 vs 长按（垫步/冲刺双义）**：按下 → 计时；释放 < `DASH_HOLD_THRESHOLD_MS`（# DRAFT 200ms）→ `dash_pressed`（垫步）；按住 ≥ 阈值 → 冲刺态（持续位移）；阈值参数落 constants.gd # DRAFT
3. **guard 键同帧多事件**：按住 L 时按下时机只有 1 次 `guard_pressed`（边沿检测防重复发射），`guard_held` 每帧持续——两事件语义互不覆盖
4. **缓冲窗口内多个输入**：窗口 150ms 内 attack+guard 连续按下 → 队列按序保留两者，消费顺序 = 入队顺序（FIFO）
5. **300ms 3 连击**：3 条全部入队（无吞噬）；第 4 击超出 `INPUT_BUFFER_MAX`（8）时拒绝新条目但**不丢已有条目**
6. **缓冲条目过期**：超窗（>150ms）条目每帧清理，清理不算吞噬（已过窗口的输入本就不该衔接）
7. **移动与事件同帧**：移动是连续轴（不进缓冲队列）；`game_left/right` 用 `Input.get_axis` 读取，与边沿事件互不干扰
8. **无输入静止**：无按键时 velocity 按加速度模型衰减到 0（`move_toward` 归零），不漂移
9. **复活 F 无提示时**：InputController 无状态判定（机械层），`revive_pressed` 照发；「提示出现时有效」由消费方（两条命系统）裁决——本 issue 不吞事件
10. **弹反窗口值异常**：`PARRY_WINDOW_FRAMES` 若被误改为 ≤0，`guard_pressed` 仍照发（输入层不依赖窗口值做判定，读取仅传递）

### 5.3 失败路径（≥3）

1. **Input Map 缺失 `game_*` 动作**：InputController `_ready()` 校验 `InputMap.has_action("game_*")`，缺失 → `push_error` 列出缺失动作 + 降级运行（不 crash）；单测断言校验函数对缺失动作报错
2. **Game autoload 未注册 / 加载顺序破坏**：`[autoload]` 段被误改 → 场景启动即失败；check_compile 覆盖（`Game` 单例访问失败即编译期暴露）；smoke 探针守护
3. **意图事件无消费方**（#3/#6 尚未实现）：Godot 信号无监听者安全 no-op；smoke 用显式 `connect` 捕获验证发射（发射与消费解耦，下游未接不 crash）
4. **缓冲窗口/阈值参数被误设为非法值**（0/负/NaN）：`clampf` 到合法范围（≥1 帧 / ≥1ms），参数异常不崩
5. **多人并发生成冲突**（多 agent 工作流）：本 PR 文件白名单提交（worktree-commit.sh 强制），`docs/PRD/573-*.md` 与 `shandong-wolf/gdscripts/input_controller.gd` 等互不重叠

---

## 6. 依赖与阻塞

### 6.1 依赖表

| 依赖 | 状态 | 风险 |
|------|------|:----:|
| #572（scaffold：constants.gd / state_machine.gd / Game autoload） | ✅ merged（#599，GDD #600） | Low |
| `constants.gd` `PARRY_WINDOW_FRAMES=12`（# DRAFT 只狼基准） | ✅ 已存在（#599 交付） | Low（只读不修改） |
| 分解 id 3（火柴人动画，消费意图事件） | ⏳ 未创建 GitHub issue | Low（事件契约先行，下游不阻塞本 issue） |
| 分解 id 6（拼刀/弹反/架势判定，消费 guard_pressed/guard_held） | ⏳ 未创建 GitHub issue | Low（同上；AC3 闭环依赖它，见 §8） |
| 分解 id 13 / #584（数值 DRAFT 定稿 + 调参面板） | ⏳ 未创建 GitHub issue | Low（本 issue 新增参数保持 # DRAFT） |
| Godot 4.7.1 运行时 + 三入口测试命令 | ✅ 环境就绪 | Low |
| 第三方 addon | ❌ 不引入（§6.2 调研结论） | — |

### 6.2 开源调研记录（issue「开源优先」要求，2026-08-19 GitHub API 实测）

| 候选 | Stars | 评估 | 结论 |
|------|-------|------|------|
| drkitt/godot-input-buffer | 61 | 通用输入缓冲库（时间戳缓冲），但**不提供本项目信号契约**（guard_pressed 时间戳语义等）；插件导入链 | ❌ 不引入；模式（时间戳+窗口）作为设计参考 |
| wokidoo/GoInputBuffer | 5 | 输入缓冲，文档稀少，契约同样不匹配 | ❌ |
| dragonforge-dev/example-input-buffer | 1 | Godot 论坛「如何做输入缓冲」官方问答示例（缓冲窗口惯用实现，~40 行） | ✅ **设计模式参考（零依赖）** |
| PantheraDigital/Modular-Character-Controller-for-Godot | 49 | 通用模块化控制器（3D/第一人称向），非 2D 横板动作 | ❌ 领域不匹配 |
| ursacascadia/godot-2d-crpg-character-controller | 20 | CRPG（Disco Elysium 式）点选移动控制器 | ❌ 领域不匹配（且禁页游式自动移动） |
| Drumstickz64/godot_2d_platformer_controller | 5 | 2D 平台跳跃控制器（重力/土狼时间语义） | ❌ 平台跳跃语义不匹配横板动作 |

**调研结论：均不采纳插件。** 理由：① issue 验收的是**自定义契约**——8 个意图事件信号名 + `guard_pressed` 仅含时间戳 + 缓冲窗口读 constants.gd，第三方缓冲库无法满足自定义信号与常量耦合；② 输入缓冲核心逻辑仅 ~40-60 行 GDScript（dragonforge 示例即公开惯用实现），「轮子」过小，引入插件反而带来 .godot 插件导入链与 Godot 4.7.1 兼容风险（#572 红线「不引入任何插件 addon」）；③ Godot 4.7 无内置输入缓冲，自研与引擎版本解耦，后续 #584 调参面板可直接改 constants.gd 参数。**复用成熟方案的设计模式（时间戳+窗口+FIFO 队列），而非引入其插件。**

### 6.3 依赖链

```
#572（地基: constants/state_machine/Game autoload, merged）
    └──→ ★ #573（本 issue: Input Map + InputController + PlayerController）
            ├──→ 分解 id 3（火柴人动画: 消费意图事件 → 关键帧）
            ├──→ 分解 id 6（拼刀/弹反判定: 消费 guard_pressed(timestamp)/guard_held）
            ├──→ #575（战斗实体状态机: 消费意图事件驱动迁移）
            └──→ #584 / 分解 id 13（数值 DRAFT 定稿: 接管输入层 # DRAFT 参数）
```

### 6.4 准备清单

- [ ] implement agent 先读本 PRD §3.1 文件清单 + §4.4 推荐组合 + §5.3 失败路径
- [ ] implement agent 读 `shandong-wolf/gdscripts/constants.gd`（# DRAFT 注释风格）、`shandong-wolf/gdscripts/game.gd`（autoload 挂接点）、`shandong-wolf/gdscripts/state_machine.gd`（#575 后续消费）
- [ ] implement agent 参考（只读）：`dragonforge-dev/example-input-buffer` 缓冲窗口模式；`mini-pong/gdscripts/paddle.gd`（轮询**反例**，不采用）
- [ ] 无阻塞项（#572 已 merged；下游均为事件消费方，契约先行）

---

## 7. Spike / 实验（standard 深度，含 3 个轻量实验）

### 实验 E1：输入缓冲无吞噬验证（AC5 前置验证）

- **要回答的问题**：时间戳 FIFO 队列能否在 300ms 内 3 连击下零丢失？
- **方法**：单测脚本 `test_input_controller.gd`：`Input.action_press(game_light_attack)` 间隔 100ms 共 3 次，断言缓冲队列 3 条全在、消费 3 次全成功、FIFO 顺序正确
- **预期结果**：队列 ≥1 无覆盖；超窗条目清理不影响窗口内条目
- **对方案的影响**：若队列方案失败 → 退化为单槽（违反 AC5）或插件（违反红线），故本实验是方案 A 的守门实验

### 实验 E2：同键双义语义分离（AC2 前置验证）

- **要回答的问题**：`game_guard` 能否同时产出「按下时机」与「按住持续」两种语义而不互相污染？
- **方法**：`Input.action_press(game_guard)` 后保持 1 秒不 release；断言 `guard_pressed` 恰发射 1 次（边沿）且 `guard_held` 每帧持续发射；释放后再按，`guard_pressed` 再次发射
- **预期结果**：边沿事件与持续事件独立计数，无重复/丢失
- **对方案的影响**：决定 InputController 是否需要对每个动作做 pressed 边沿跟踪（`_was_pressed` 状态表）

### 实验 E3：移动手感参数标定（AC6 前置验证）

- **要回答的问题**：加速度模型在「冷冽干脆」约束下能否满足 2 秒 ≥100px 且起步 2 帧？
- **方法**：`Input.action_press(game_move_right)` 驱动 2 秒，测位移；以 `ACCELERATION`（# DRAFT 1200 px/s²）、`MAX_SPEED`（# DRAFT 300 px/s）起步 2 帧达标为准，参数超界则调整候选值
- **预期结果**：位移 ≥100px；velocity 达 MAX_SPEED 时间 ≤ 起步 2 帧 + 加速度曲线无拖泥带水
- **对方案的影响**：锁定 constants.gd 输入层 # DRAFT 参数初值（待 #584 定稿）

---

## 8. 交接上下文（Continuation Context）

**系统状态（plan agent 接手时）：** #572 全链路已 merged（constants.gd 含 PARRY_WINDOW_FRAMES=12 等 # DRAFT 分区；state_machine.gd 的 StateMachineBase；Game autoload 锚点注释「输入系统挂接于此」）；shandong-wolf/ 无 `[input]` 段、无玩家实体、无 addons。本 PRD 已定：**project.godot 新增 `[input]` 段（8 个 `game_` 动作）+ 新建 `input_controller.gd`（意图事件 + 时间戳缓冲队列）+ 新建 `player_controller.gd`（CharacterBody2D 加速度模型）+ constants.gd 追加输入层 # DRAFT 分区 + 两个测试文件 + run_tests.gd 挂载**。

**plan agent 下一步：**
1. 读本 PRD §4.4 推荐组合表——直接按推荐方案出 DESIGN，无需重新对比方案。
2. 文件落点（白名单）：`shandong-wolf/gdscripts/input_controller.gd`、`shandong-wolf/gdscripts/player_controller.gd`、`shandong-wolf/gdscripts/constants.gd`（追加分区）、`shandong-wolf/project.godot`（`[input]` 段）、`shandong-wolf/tests/test_input_controller.gd`、`shandong-wolf/tests/test_player_controller.gd`、`shandong-wolf/tests/run_tests.gd`（挂载）。
3. 红线（implement 必须遵守）：
   - ❌ 绝不触碰 `mini-pong/` 任何文件；❌ 绝不 `git add .`（白名单提交）
   - ❌ 不修改 `shandong-wolf/scenes/Main.tscn`（含 PostMergeProbeLabel）；玩家实体由测试/后续战斗场景程序化实例化
   - ❌ 不引入任何插件 addon / 美术资产 / 像素帧（§6.2 调研结论：自研 ~50 行缓冲，不引插件）
   - ✅ 输入映射名统一 `game_` 前缀；`guard`=L 独键、`dash`=Shift（§3.1.1 裁决）
   - ✅ constants.gd 所有输入层手感值保持 `# DRAFT` + 候补值，定稿归 #584 / 分解 id 13；`PARRY_WINDOW_FRAMES` 只读不改
   - ✅ 三入口命令本地实测全绿后才提交
4. 参考文件（只读）：`shandong-wolf/gdscripts/constants.gd`（# DRAFT 注释风格）、`shandong-wolf/gdscripts/game.gd`（autoload 挂接点）、`dragonforge-dev/example-input-buffer`（缓冲窗口惯用模式）、`mini-pong/gdscripts/paddle.gd`（轮询**反例**，不采用）、`agents/skills/game-to-issues/references/sekiro-tuning-reference.md`（数值语义）。
5. 后续 issue 衔接：分解 id 3（动画消费意图事件）→ 需在本 issue merged 后创建 GitHub issue；分解 id 6（弹反判定消费 `guard_pressed(timestamp)`/`guard_held`）→ **AC3 处决闭环依赖它**，本 issue 只交付输入侧保障（attack_pressed 可达、无独立 execute 键）；#575 战斗状态机消费意图事件驱动迁移；#584 接管 # DRAFT 定稿并建 F1 调参面板。
6. 合并后：post-merge agent 补记 GDD（输入映射表 + 意图事件契约 + InputController 接口 + guard/dash 键位裁决）；workflow-chain.yml 自动推进 label（research → plan）；本 PR 由脚本层合并，research agent 不自行 merge。
