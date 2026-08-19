# PRD #574 — [Feature] 火柴人剪影骨架与关键帧动画（Line2D/Polygon2D 程序化 + AnimationPlayer 摆姿）

> **Issue:** #574
> **标签:** enhancement, graphics, content, version/mvp, workflow/research（research 阶段）
> **深度:** deep（分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=3 标注 `depth: deep` → §1–8 全必填，§7 含 ≥3 实验）
> **Agent:** game-research-agent
> **日期:** 2026-08-19
> **所有权:** `content_ownership: mechanical`（渲染实现=mechanical；构图/配色裁决=taste-draft，E2E 截图交用户定稿）
> **引擎/目录约束:** Godot 4.7.1 / `shandong-wolf/`（manifest `game.active: shandong-wolf` + subprojects.path 单一事实源；本 PRD 全部路径前缀 `shandong-wolf/`，零 `mini-pong/` 写死）
> **研究选项:** Obsidian 知识库已搜索（`/Volumes/Obsidian/Knowledge Ocean/`，wiki+raw 全量 grep 火柴人/剪影/关键帧/动画/弹反/Stagger）+ 设计 brief（`docs/RAW/shandong-wolf-brief.md`）+ GDD（`docs/GAME_DESIGN/shandong-wolf/01-OVERVIEW.md`）+ 程序化视觉配方（`agents/skills/game-to-issues/references/visual-implementation-path.md` §6.5 火柴人动作视觉）+ 开源调研（GitHub API 检索 火柴人/Skeleton2D/2D 骨架动画方案，见 §6.2）+ 同链 issues（#573 输入 / #575 战斗状态机 / #577 判定 / #579 打击反馈 / #580 处决 / #578 复活）
> **来源:** backlog-promotion（`docs/RAW/game-to-issues-shandong-wolf.json` id=3，estimate 3d，priority high）
> **前置依赖:** #572（已 merged：#572 落地 constants.gd + state_machine.gd + game.gd autoload，本 PRD 全部文件在其上扩展，不重建）

---

## 1. 问题定义

### 1.1 现状（2026-08-19 侦查）

| 文件 | 状态 | 说明 |
|------|:----:|------|
| `shandong-wolf/gdscripts/constants.gd` | ✅ 已落地（#572） | `WolfConstants`（RefCounted + class_name），已含 `# DRAFT` 分区：弹反窗口（PARRY_WINDOW_FRAMES=12）、架势回复、两条命、刀伤害、**帧节奏（FRAME_ATTACK_WINDUP=8 / FRAME_ATTACK_RECOVERY=14 / FRAME_RHYTHM_BASE=60）**；机械常量 SCREEN_WIDTH/HEIGHT；注释规范「候补值 + 影响什么 + 情感断言」已确立 |
| `shandong-wolf/gdscripts/state_machine.gd` | ✅ 已落地（#572） | `StateMachineBase`（RefCounted + class_name）：状态对象 enter()/exit()/update(delta) 三接口 + transition_to()（同态守卫 + 防重入锁）——#574 动画状态对象直接派生于此 |
| `shandong-wolf/gdscripts/game.gd` | ✅ 已落地（#572） | `Game` autoload（project.godot `[autoload] Game="*res://gdscripts/game.gd"`），预加载 constants，后续系统挂接点 |
| `shandong-wolf/scenes/Main.tscn` | ✅ 存在（#562/#563/#570） | 纯声明式标题场景（标题/副标题/版本号/探针），零脚本零资源；**本 issue 的火柴人节点为新增独立场景/节点，不嵌入标题场景** |
| `shandong-wolf/scenes/` | ⚠️ 仅 Main.tscn | 无角色场景文件——本 issue 需新增 `player_stick_figure.tscn`（或程序化构建节点） |
| `shandong-wolf/gdscripts/` | ⚠️ 三个地基脚本 | 无任何角色/动画脚本——本 issue 新增火柴人骨架与动画控制器 |
| `shandong-wolf/tests/` | ✅ 三入口可用（#572） | check_compile 自动扫描新脚本；run_tests.gd 已挂载 state_machine 单测——本 issue 追加动画单测 |
| `shandong-wolf/assets/` | ✅ 空 | 程序化生成路径，零美术资产红线（AC5） |

**核心缺口：** shandong-wolf 有工程地基（constants/状态机/autoload）与标题场景，但**没有任何角色视觉**——玩家没有可看到的「自己」。本 issue 交付 = 玩家火柴人骨架（Line2D/Polygon2D 程序化构建，头=圆、躯干/四肢=线、刀=长线）+ AnimationPlayer 关键帧动画（对齐 #575 canonical 状态集合）+ 动画只消费状态的输入契约接口 + 帧节奏 DRAFT 值入库。它是视觉核心 issue（E2E 截图须交用户裁决）。

### 1.2 验收条件（源自 Issue #574 body，映射到各阶段 agent）

| # | 验收条件 | 负责阶段 | 本 PRD 的保障措施 |
|---|---------|---------|------------------|
| AC1 | 玩家火柴人可在 idle→run→attack→parry→stagger 间切换，动画过渡 h 时长 ≤2 帧 | implement | §4.1 方案 A：动画状态对象 + 过渡策略；§5.1 AC1 含帧级断言（AnimationPlayer 时间戳 / blend 时长 ≤ 2/60s） |
| AC2 | attack 动画包含刀光弧线轨迹（additive），不影响碰撞判定（判定在 #577） | implement | §4.4 方案 A：刀光 = Polygon2D additive 独立子节点，纯视觉层与碰撞体解耦；§5.1 AC2 断言刀光节点不在碰撞层 |
| AC3 | 所有帧节奏数值来自 constants.gd # DRAFT 且注释含候补值 | implement | §4.2：`FRAME_ANIM_*` 系列全部进 constants.gd `# DRAFT` 分区（继承 #572 注释规范：候补值+影响+情感断言），禁止实现期硬编码 |
| AC4 | E2E 截图提交用户裁决：火柴人摆姿/剪影是否具有『小小系列』的干净力量感，且与雪夜水墨背景和谐 | implement/CI | §5.4：E2E shot plan 注入各动画状态（含 attack 前摇/暴发/收招 3 帧），截图落盘 `docs/e2e-evidence/` 交用户 |
| AC5 | 无外部美术文件，仅 .gd 程序生成 | implement | §8 红线：零资源文件（仅 .gd/.tscn），骨架几何全部代码构建 |

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 玩家游玩（MVP 战斗闭环前置） | 每次运行 | 玩家看到自己的火柴人剪影：idle 待机呼吸 → move 步态摆动 → attack 前摇蓄力/暴发挥砍/收招滞刀 → guard 横刀胸前 → stagger 受击后仰——动作「有力度」，雪夜背景下剪影与背景反差成立 |
| B | 后续战斗系统消费（#575/#577/#579/#580/#578） | 每次 impl PR | 战斗状态机把 canonical 状态名喂给本 issue 的动画消费接口 → 对应关键帧播放；判定/反馈系统叠加刀光、hit-stop、火花 |
| C | 用户裁决（taste-draft） | E2E 截图 | 提交截图判定：火柴人摆姿/剪影是否干净有力、与雪夜水墨和谐；帧节奏 DRAFT 候补值（前摇 8 / 暴发 4 / 收招 10）可否定稿 |

### 1.4 范围边界（与同链 issues / 既有 PRD 去冲突，Patch 14）

| Issue / PRD | 覆盖范围 | 本 PRD 不重复覆盖 |
|------------|---------|------------------|
| #572（地基，merged） | constants.gd / state_machine.gd / game.gd autoload | ❌ 不重建；在其上**扩展** FRAME_ANIM_* DRAFT 分区 + 派生动画状态对象 |
| #573（输入映射，research 中） | Input Map + 玩家控制器 + 意图事件信号（attack_pressed 等） | ❌ 不碰输入；本 issue 动画**只消费状态，不读输入**（输入契约，见 §1.5） |
| #575（战斗实体基类与状态机，OPEN） | CombatEntity + canonical 状态机（idle/move/.../dead 11 态唯一权威） | ❌ 不定义状态、不建战斗状态机；本 issue 只**消费状态名播放动画**，状态机权威归 #575 |
| #577（拼刀/弹反判定，OPEN） | 弹反窗口判定、拼刀、架势崩解 → 判定逻辑 | ❌ 不做判定；只提供 guard 共用格挡姿态动画 + parry_success 硬直帧（对应 #577 的 parry_success 结果事件） |
| #579（打击反馈，OPEN） | 火花 / hit-stop / 屏震 / 慢动作 | ❌ 不做反馈系统；只做 **attack 刀光弧线轨迹（additive）**——纯视觉轨迹，反馈层归 #579 |
| #580（处决系统，OPEN） | 处决特写（#579 反馈 + 镜头） | ❌ 不实现处决流程；只提供 execute 关键帧动画（上撩→斩落），驱动归 #580 |
| #578（两条命复活，OPEN） | 原地复活流程 | ❌ 不实现复活逻辑；只提供 revive 起身关键帧动画 + dead 倒地帧，驱动归 #578 |
| mini-pong 全部 | mini-pong 游戏逻辑 | ❌ 不复制；`mini-pong/gdscripts/` 动画先例仅作模式参考 |

### 1.5 输入驱动契约（2026-08-19 issue body 强制，动画层唯一输入）

```
#2(#573) 输入意图事件 ──► #4(#575) 战斗状态机 ──► 本 Issue 动画层
attack_pressed                 idle/move/attack/           StickFigureController
heavy_attack_pressed           heavy_attack/guard/          .consume_state(state_name)
guard_pressed/guard_held       parry_success/stagger/       └─► AnimationPlayer
dash_pressed/jump_pressed      stance_break/execute/           播放对应关键帧 clip
revive_pressed                 revive/dead
```

- 动画层**不直接读输入**（不监听 Input 事件、不订阅 #573 信号）——只暴露 `consume_state(state: String)`（或等效接口）消费 canonical 状态名。
- 攻击前摇帧 = 输入后进入 attack 状态后立即播放的动画（与 #573 输入缓冲衔接；缓冲队列语义归 #573）。
- 格挡/弹反共用 guard 姿态动画；弹反成功播 parry_success 硬直帧（对应 #577 的 parry_success 结果事件）。
- run 不单独成态：归入 move 动画变体（canonical 11 态无 run，issue body 明确）。

### 1.6 Obsidian 知识检索

- **Vault 直接读取成功**（`/Volumes/Obsidian/Knowledge Ocean/`，wiki + raw 全量 grep：火柴人/剪影/关键帧/动画/弹反/Stagger/时机判定/骨骼）。
- **命中笔记：**
  - **《JRPG 战斗系统研究 - 最终综合报告》**（raw/Bear/）：FF16 **Stagger 系统 = 破防增伤**、**弹反/闪避 = 时机判定**（动作游戏）、难度分层模型「基础动作 → 进阶连招/弹反/闪避」→ 佐证 #574 的帧节奏三阶段（前摇可读 8 帧 → 暴发瞬间 4 帧 → 收招滞刀 10 帧）是「时机判定」类动作的核心手感载体；弹反成功帧（parry_success 硬直）是判定成功的视觉回报。
  - **《技术笔记》§Mecanim 动画系统**：*「状态机设计、大型动画列表播放优化」*（Unity 语境）→ 佐证**动画状态与逻辑状态解耦**：动画层消费状态名、按需播放 clip，不持有判定/输入逻辑——支撑本 PRD 的 consume_state 契约设计。
- **Vault 无火柴人/剪影专属动画笔记**（命中均为通用动作设计原则）→ 视觉权威源 = `agents/skills/game-to-issues/references/visual-implementation-path.md` **§6.5 火柴人动作视觉**（2026-08-19 用户指定《小小系列》Flash 火柴人为参考坐标）+ issue body 审美坐标（墨色 #2b2b2b 剪影、前摇 8/暴发 4/收招 10、禁止页游光效、禁止日式浮夸）。

---

## 2. 设计意图

### 2.1 现状为何存在

| 事实 | 来源 | 说明 |
|------|------|------|
| 无角色视觉 | #562/#563/#570 只做了标题场景 | shandong-wolf 管线冒烟链以「场景能渲染」为界，从未涉及游戏内角色 |
| 地基先行 | #572 设计 | 骨架期刻意「先地基后玩法」：constants/状态机/autoload 先行，具体视觉/玩法 issue 后置（#574-#580 依赖 #572） |
| 程序化零资产 | brief §9.6 + visual-implementation-path.md | AI 无绘画能力 → 视觉 issue 一律程序化生成；「占位即最终形态的骨架」：几何形状/比例 = 正式原画接入点 |
| 动画状态名 canonical 化 | #575 状态契约（2026-08-19 三方对齐） | 11 态集合在 #2/#3/#4/#6/#7/#9 统一引用，禁止各 issue 自造状态名（parry 单列、run 代替 move 均被禁止） |

### 2.2 为何现在做

1. **#572 已落地**（constants.gd 帧节奏分区 + StateMachineBase + autoload）——动画 DRAFT 值有库可入、动画状态对象有基类可派生，本 issue 的依赖全部就绪（前置依赖仅 #572）。
2. **#573 输入层已进入 research**——输入契约（意图事件信号集）已定稿，动画层可提前按「只消费状态」契约设计接口，避免 #573 落地后返工。
3. **视觉是战斗手感闭环的必经之路**：#575 状态机、#577 判定、#579 反馈最终都要在「看得见的角色」上呈现；火柴人先行 = 后续系统有渲染载体（#579 的刀光轨迹直接消费本 issue 的刀光节点）。
4. **MVP 完成定义要求**：brief「MVP（核心玩法优先）= 可玩动作系统验证：移动/攻击/弹反/架势崩解/处决/两条命/基础 AI/单场景战斗 + **雪夜像素氛围成立**」——火柴人剪影是氛围成立的第一块视觉拼图。

### 2.3 既有约束（必须继承）

| 约束 | 详情 | 来源 |
|------|------|------|
| 零美术资产 | 仅 .gd/.tscn 程序化生成，禁止外部美术文件/像素帧图 | issue AC5 + brief §9.6 |
| 帧节奏集中 | 所有帧节奏数值进 constants.gd `# DRAFT` 分区 + 注释含候补值 + 「影响什么/情感断言」 | issue AC3 + #572 注释规范 |
| 动画只消费状态 | 不读输入；状态名 = #575 canonical 11 态 | issue 输入驱动契约（2026-08-19） |
| 审美红线 | 墨色 #2b2b2b / 剪影黑；禁止页游光效堆砌；禁止日式武士道浮夸动作 | issue 上下文 |
| 过渡 ≤2 帧 | idle→run→attack→parry→stagger 动画过渡 h ≤2 帧 | issue AC1 |
| 正式原画接入点 | 换 Sprite2D 层，保留现有 Line2D 骨架结构 | issue 画面实现路径 |
| 游戏目录参数化 | 所有路径前缀 `shandong-wolf/`，禁止 `mini-pong/` 写死 | manifest + #559 先例 |

---

## 3. 影响分析

### 3.1 直接影响模块

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `shandong-wolf/gdscripts/constants.gd` | WolfConstants | **修改**：新增 `FRAME_ANIM_*` # DRAFT 分区（各状态帧节奏 + 骨骼几何参数 + 颜色），继承既有注释规范 |
| `shandong-wolf/gdscripts/stick_figure.gd` | 火柴人骨架构建 | **新建**：Line2D/Polygon2D 程序化构建（头圆 + 躯干/四肢线 + 刀长线），@export 几何参数从 constants 读取 |
| `shandong-wolf/gdscripts/stick_figure_controller.gd` | 动画状态消费控制器 | **新建**：`consume_state(state)` 接口 + AnimationPlayer 调度 + 状态名→clip 映射（对齐 #575 canonical）+ 过渡 ≤2 帧策略 |
| `shandong-wolf/gdscripts/stick_figure_anim_states.gd` | 动画状态对象 | **新建**：基于 StateMachineBase 的状态对象集（idle/move/attack/…/dead 的 enter/exit/update），供 #575 战斗状态机挂接（或本层最小调度） |
| `shandong-wolf/gdscripts/sword_arc.gd` | 刀光弧线 | **新建**：Polygon2D additive 弧线轨迹，随挥砍旋转，纯视觉（不参与碰撞） |
| `shandong-wolf/scenes/player_stick_figure.tscn` | 场景装配 | **新建**：根 Node2D + StickFigure + AnimationPlayer + SwordArc（或纯代码构建，二选一由 implement 按 §4.1 定） |
| `shandong-wolf/tests/test_stick_figure_animation.gd` | 动画单测 | **新建**：状态→clip 映射、过渡时长 ≤2 帧断言、刀光 additive 层断言、consume_state 未知状态降级 |
| `shandong-wolf/tests/run_tests.gd` | 测试入口 | **修改**：挂载新动画单测 |
| `shandong-wolf/e2e_shots.json` | E2E shot plan | **修改**：注入动画状态 shot（idle/move/attack 3 段/guard/stagger + 截图提交用户裁决） |

### 3.2 新增文件清单

| 文件 | 用途 | 归属 |
|------|------|------|
| `gdscripts/stick_figure.gd` | 骨架构建 + 几何参数 | #574 |
| `gdscripts/stick_figure_controller.gd` | consume_state 契约 + AnimationPlayer 调度 | #574 |
| `gdscripts/stick_figure_anim_states.gd` | 动画状态对象（派生 StateMachineBase） | #574 |
| `gdscripts/sword_arc.gd` | 刀光弧线（additive） | #574 |
| `scenes/player_stick_figure.tscn` | 角色场景（可选，或代码构建） | #574 |
| `tests/test_stick_figure_animation.gd` | 单测 | #574 |

### 3.3 间接影响模块

| 文件/系统 | 影响 | 说明 |
|-----------|------|------|
| `gdscripts/state_machine.gd`（#572） | 无改动，被派生 | 动画状态对象复用其 enter/exit/update 契约 |
| `gdscripts/game.gd`（#572 autoload） | 无改动，可挂接 | 后续 #575/#577 经 Game 单例引用角色控制器 |
| `project.godot` | 无改动（除非需注册场景/autoload） | 若场景文件化则无需注册；若控制器需全局则讨论，默认不注册 |
| #575 战斗状态机 | 消费方 | 其状态转移 → consume_state 驱动动画 |
| #579 打击反馈 | 消费方 | 刀光节点复用 + 火花/hit-stop 叠加（不冲突） |
| #577 拼刀判定 | 消费方 | guard/parry_success 动画帧 = 判定结果的视觉表现 |

### 3.4 数据流影响

```
#575 战斗状态机（后续 issue，权威状态源）
    │  transition_to(attack)
    ▼
StickFigureController.consume_state("attack")
    │  状态名→clip 映射（11 态 ↔ AnimationPlayer clip）
    ▼
AnimationPlayer.play("attack")
    ├── 前摇帧（FRAME_ANIM_ATTACK_WINDUP=8）  ← constants.gd # DRAFT
    ├── 暴发帧（FRAME_ANIM_ATTACK_BURST=4）   ← 刀光弧线随挥旋转（SwordArc，additive）
    └── 收招帧（FRAME_ANIM_ATTACK_RECOVERY=10）
            └──► 过渡 ≤2 帧 到下一状态 clip
```

### 3.5 需更新的文档

- [ ] `docs/PRD/574-stick-figure-silhouette-animation.md`（本 PRD）
- [ ] `docs/GAME_DESIGN/shandong-wolf/`（post-merge agent 在 implement PR 后按功能域填充）
- [ ] `docs/RAW/game-to-issues-shandong-wolf.json`（issue 状态由 workflow 推进，非本 PRD 直接改）
- [ ] `shandong-wolf/e2e_shots.json`（shot plan 扩展，implement 阶段）

---

## 4. 方案对比

### 4.1 骨架构建方案（角色怎么「长出来」）

#### 方案 A：Line2D/Polygon2D 程序化骨架 + AnimationPlayer 关键帧摆姿（issue 指定 + 配方 §6.5）

- **描述**：火柴人 = 节点组：头（Polygon2D 圆或 CircleShape 视觉）+ 躯干（Line2D）+ 双臂/双腿（各 Line2D）+ 刀（长 Line2D 冷白 #c0c8d0 刀身）。骨架由 `stick_figure.gd` 在 `_ready()` 用代码构建（零 tscn 资源依赖）；AnimationPlayer 对骨架各节点写**关键帧摆姿**（起势→发力→击中→收招，帧间距不对称：前摇 8 帧 / 暴发 4 帧 / 收招 10 帧）；动画 clip 按 canonical 状态命名（idle/move/attack/.../dead）。
- **Pros**：零美术资产满足 AC5；与配方 §6.5 完全一致（2026-08-19 用户指定参考）；Line2D 摆姿 = 移动节点坐标/rotation，关键帧直观；换正式原画 = 换 Sprite2D 层（保留骨架结构）的接入点天然存在；帧节奏直接由 AnimationPlayer 关键帧时间戳承载，可测可断言。
- **Cons**：逐段 Line2D 摆姿需要手动规划关节联动（挥刀时手臂/躯干/刀同步）；复杂姿态（stance_break 失衡、execute 上撩斩落）关键帧较多。
- **Risk**：Low（配方已在 mini-pong 视觉体系实弹验证「程序化视觉成立」）
- **Effort**：2-3 周（骨架 + 11 clip 关键帧 + 单测 + E2E）

#### 方案 B：Skeleton2D + Bone2D 骨骼系统

- **描述**：用 Godot 内置 Skeleton2D/Bone2D 建骨骼，Polygon2D 蒙皮绑定骨骼权重，Bone2D 旋转驱动姿态。
- **Pros**：骨骼动画是 2D 角色动画「正统」方案；姿态插值由引擎骨骼系统处理，关节联动更自然。
- **Cons**：**Skeleton2D 的 Polygon2D 蒙皮需要预生成 mesh + 权重数据**——程序化生成权重绑定复杂度高；对「纯剪影线条」角色（无填充面片）骨骼蒙皮优势不明显；与配方 §6.5「关键帧摆姿不是逐帧画」的精神不符；零资产前提下收益为零。
- **Risk**：Med（蒙皮权重程序化生成易出错；过度设计）
- **Effort**：4-5 周（权重生成 + 骨骼装配 + 调试）

#### 方案 C：Sprite2D 预渲染逐帧序列

- **描述**：预渲染多张火柴人姿态图，Sprite2D + AnimatedSprite2D 播放。
- **Pros**：实现最简单。
- **Cons**：**违反 AC5 无外部美术文件红线**；逐帧图片 = 美术资产；「程序化生成零资产」路径被破坏。
- **Risk**：High（红线违规，直接 AC 失败）
- **Effort**：1-2 周（但不可接受）

#### 推荐：**方案 A**。理由：① 唯一满足全部 AC（AC5 零资产 + AC1 帧级可测 + 原画接入点）；② 与配方 §6.5（用户指定的《小小系列》参考坐标）逐条对应；③ 帧节奏 = AnimationPlayer 时间戳，天然可断言（AC1/AC3）；④ #579 刀光、#577 判定视觉表现直接挂接。

### 4.2 帧节奏与 DRAFT 值组织方案

#### 方案 A：constants.gd 新增 `FRAME_ANIM_*` 分区（推荐）

- **描述**：在 `WolfConstants` 增加「── 动画帧节奏（# DRAFT 候补值，待 #584 定稿）──」分区：
  - `FRAME_ANIM_ATTACK_WINDUP: int = 8`（issue 指定前摇 8 帧；与既有 FRAME_ATTACK_WINDUP=8 对齐，注释互引）
  - `FRAME_ANIM_ATTACK_BURST: int = 4`（issue 指定挥刀暴发 4 帧；**新值，既有 constants 无**）
  - `FRAME_ANIM_ATTACK_RECOVERY: int = 10`（issue 指定收招 10 帧；**与既有 FRAME_ATTACK_RECOVERY=14 候补值不一致** → 双值共存注释互引，定稿归 #584 裁决）
  - `FRAME_ANIM_TRANSITION_MAX: int = 2`（AC1 过渡上限；2 帧 @60fps = 0.033s）
  - `FRAME_ANIM_MOVE_STEP: int = 4`（步态摆臂循环 4 帧，配方 §6.5）
  - 骨骼几何参数：`BODY_COLOR = Color("#2b2b2b")`、`SWORD_COLOR = Color("#c0c8d0")`、肢体长度/厚度等（DRAFT 候补 + 情感断言注释）
- **Pros**：AC3 直接满足；#572 注释规范延续（候补值+影响+情感断言）；#584 一次性调参面板可直接消费；与既有 FRAME_ATTACK_* 冲突显式暴露给 #584 裁决而非实现期偷定。
- **Cons**：DRAFT 值多（需克制，只入必要值）。
- **Risk**：Low；**Effort**：0.5 周

#### 方案 B：动画内硬编码

- **描述**：关键帧时间戳直接写在 AnimationPlayer 动画资源里。
- **Pros**：实现最快。
- **Cons**：**违反 AC3**（数值必须来自 constants.gd # DRAFT）；#584 调参面板无法消费；手感调整需改动画资源。
- **Risk**：High（AC 失败 + taste 域越权）；**Effort**：1 周

#### 推荐：**方案 A**（AC3 是硬验收，无悬念；冲突值显式标注交 #584）。

### 4.3 动画状态消费接口方案（consume_state 契约）

#### 方案 A：独立控制器 + 状态名→clip 映射表（推荐）

- **描述**：`StickFigureController`（Node）暴露 `consume_state(state: String)`；内部维护 11 态 ↔ AnimationPlayer clip 映射（#575 canonical 状态名 → 本层 clip 名，可同构命名：`anim_idle`/`anim_move`/`anim_attack`…）；未知状态降级为 idle（push_warning，不崩溃）；映射表可注入/可单测。
- **Pros**：契约最薄（只吃字符串状态名）；#575 状态机落地前可独立开发/测试（用测试桩直接调 consume_state）；与输入完全解耦（AC 输入契约）；未知状态降级防未来状态名漂移。
- **Cons**：映射表需与 #575 canonical 保持同步（#575 是唯一权威——本层只做镜像映射并注释来源）。
- **Risk**：Low；**Effort**：0.5-1 周

#### 方案 B：直接监听 #573 输入信号

- **描述**：控制器订阅 attack_pressed/guard_pressed 等输入意图信号直接播动画。
- **Pros**：链短。
- **Cons**：**违反 issue 输入契约**（动画只消费状态不读输入）；#573 尚未实现无法联调；输入缓冲/判定时序（前摇衔接）错位。
- **Risk**：High（契约违规）；**Effort**：0.5 周

#### 推荐：**方案 A**。契约即 issue body 明文（2026-08-19 输入驱动契约），方案 B 直接出局。

### 4.4 刀光弧线方案（AC2）

#### 方案 A：独立 Polygon2D additive 节点（推荐）

- **描述**：`SwordArc`（Polygon2D，material blend_mode=additive，独立子节点挂在刀尖参考点）：attack 暴发帧随刀旋转绘制弧线（参数化：弧半径/张角/透明度衰减/存在时长，DRAFT 值入 constants）；**纯视觉层**，无 Area2D/CollisionShape——碰撞判定归 #577。
- **Pros**：AC2 直接满足（additive + 不影响碰撞）；参数化可调（#584 可裁决弧线观感）；#579 打击反馈可直接复用/叠加。
- **Cons**：弧线几何需程序化生成（Polygon2D.Polygon 动态计算），实现量适中。
- **Risk**：Low；**Effort**：0.5 周

#### 方案 B：把刀光并入攻击动画关键帧

- **描述**：刀光作为挥砍动画的一部分（刀身残影/轨迹直接画进 clip）。
- **Pros**：实现最少。
- **Cons**：视觉与动画强耦合，无法独立调参；additive 合成不易；#579 无法复用。
- **Risk**：Med；**Effort**：0.5 周

#### 推荐：**方案 A**（AC2 明文要求 additive + 不影响碰撞判定，独立节点是唯一干净解）。

---

## 5. 边界条件与验收标准

### 5.1 正常路径（AC 清单）

- [x] **AC1: 状态切换动画过渡 ≤2 帧** — idle→run→attack→parry→stagger 全链
  - consume_state 连续调用不同状态时，AnimationPlayer 过渡时长 ≤ `FRAME_ANIM_TRANSITION_MAX`（2 帧 = 2/60s）
  - 断言方式：单测记录切换时刻 t0 与目标 clip 实际生效时刻 t1，t1-t0 ≤ 0.034s；或 AnimationPlayer 无内置 blend 时采用「同帧切换 + 起始姿态插值」策略并断言首帧姿态偏差
- [x] **AC2: attack 刀光弧线（additive）不影响碰撞** — 刀光 = SwordArc（Polygon2D additive）
  - SwordArc 节点下无 CollisionShape2D/Area2D；角色碰撞体（若有，归后续 issue）与刀光节点树分离
  - 单测断言：SwordArc 及其子节点不含碰撞类型
- [x] **AC3: 帧节奏数值全部来自 constants.gd # DRAFT** — 动画关键帧时间戳必须由 `WolfConstants.FRAME_ANIM_*` 派生
  - 单测断言：读取 constants 值并校验 AnimationPlayer clip 关键帧时间戳与之匹配（容差 ±1 帧）
  - 每个 FRAME_ANIM_* 常量注释含：候补值、影响什么、情感断言（#572 规范）
- [x] **AC4: E2E 截图提交用户裁决** — shot plan 覆盖动画状态
  - e2e_shots.json 注入：idle 待机 / move 步态 / attack 前摇+暴发+收招 3 帧 / guard / stagger /（可含 parry_success）
  - 截图落盘 `docs/e2e-evidence/`，PR 中提交用户判定「小小系列干净力量感 + 雪夜水墨和谐」
- [x] **AC5: 无外部美术文件** — 仅 .gd/.tscn
  - check_compile 全绿；`shandong-wolf/assets/` 保持空；PR diff 无图片/字体/序列帧资源

### 5.2 边界情况

1. **未知状态名**：consume_state("unknown_state") → 降级 idle + push_warning（不崩溃、不卡死动画）；映射表注释引用 #575 为权威源。
2. **状态名大小写/变体漂移**：run/move、parry/guard 混用 → 映射表只认 canonical 11 态；run/parry 别名显式映射到 move/guard 并注释（issue body 已声明 run 归 move）。
3. **快速连续切换（连招节奏）**：attack 未播完即 consume_state("attack") 或 move → 前摇可打断（#573 输入缓冲语义）→ 同态重入：若同 clip 重播，重置到前摇首帧而非从头播完整 clip；过渡仍 ≤2 帧。
4. **transition 冲突（#575 未就绪）**：本层独立状态调度时遇到非法转移 → 降级保持当前动画 + push_warning；#575 落地后由 #575 状态机合法性检查兜底。
5. **constants 与既有值冲突**（RECOVERY 10 vs 14）→ 双值共存互引注释，禁止实现期二选一偷定；#584 裁决后统一。
6. **headless/CI 环境**：动画单测不依赖真实渲染（仅节点树 + AnimationPlayer 时间戳断言）；E2E 截图依赖渲染（CI 有截图能力，#559 已验证）。
7. **窗口比例变化**：1280x720 固定窗口（#572 机械常量），骨架锚定原点居中，不依赖屏幕尺寸。
8. **复用时旧 clip 未清理**：AnimationPlayer 播放新 clip 前 stop 旧 clip（防叠播）。

### 5.3 失败路径

1. **AnimationPlayer 关键帧与 constants 失配**（实现期硬编码）→ 单测断言失败 → 修复为从 constants 派生。
2. **骨架构建抛错**（几何参数非法）→ stick_figure.gd 参数校验 + 默认值兜底；单测覆盖非法参数。
3. **E2E 截图不达标**（用户裁决不通过）→ 不合并（taste-draft 领域）；调整关键帧摆姿/帧节奏候补值重提交；机械实现（骨架/接口）不受影响可先行。
4. **#575 状态名后续变更**（canonical 漂移）→ 映射表单点修改；单测保护映射完整性（枚举断言 11 态全映射）。

---

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 |
|------|------|------|
| #572（constants.gd / state_machine.gd / autoload） | ✅ merged | 无——本 PRD 全部文件在其上扩展 |
| #573（输入意图事件信号集） | 🔄 research 中 | Low——契约已定稿（issue body 2026-08-19），本层只依赖其**契约文本**而非代码；动画层不订阅信号 |
| #575（canonical 状态集合） | 🔄 OPEN | Low——11 态集合已在 #573/#574/#575/#577 三方对齐（issue body），本层按契约实现 consume_state |
| #584（战斗数值 DRAFT 定稿） | 🔄 OPEN | Low——本层只入库 DRAFT 候补值，定稿归 #584；冲突值显式暴露 |

```
#572（merged）──► #574（本 issue）──► #575（战斗状态机，消费动画）
                                  ├──► #577（判定，消费 guard/parry_success 帧）
                                  ├──► #579（打击反馈，复用刀光节点）
                                  ├──► #580（处决，消费 execute 帧）
                                  └──► #578（复活，消费 revive/dead 帧）
```

### 6.2 开源调研（issue 强制「开源优先」，2026-08-19 GitHub API 检索）

| 候选 | Stars | 结论 |
|------|-------|------|
| `Tor-Kai/Godot-2d-Bridge-1.0.0`（Blender→Godot Skeleton2D 导出） | 15 | ❌ 需 Blender 资产管线，与零资产红线冲突；编辑器/工具链而非运行时组件 |
| `folt-a/godot-skeleton2d-helper`（Skeleton2D Mesh 骨骼动画编辑器插件） | 12 | ❌ 编辑器插件，依赖预生成 mesh+权重；对程序化纯线条火柴人无收益（§4.1 方案 B 同类） |
| `JoschkaSchulz/godot-learning-2dSkeleton` | 2 | ❌ 学习 demo，非可复用组件 |
| `LesterYHZ/Stick-Figure-Battle`（Godot 火柴人射击） | 1 | ❌ 完整游戏而非组件，架构不可剥离 |
| `stickcastledev/stick-castle-defense`（火柴人塔防） | 0 | ❌ 同上 |
| `0xjc22/stick-fighter`（Godot 4.4 火柴人格斗） | 0 | ❌ 3D 项目，不适用 2D 横板 |
| Godot Asset Library 检索（stick figure / skeleton 2d / line animation） | — | ❌ 无满足「程序化零资产 + Line2D 关键帧」的成熟插件 |

**调研结论：** 无成熟开源方案可复用——火柴人相关仓库均为完整游戏（不可剥离架构）或编辑器工具（依赖美术资产管线）；Skeleton2D 系方案（§4.1 方案 B）需要 mesh+权重数据，与「零美术资产、纯 .gd 程序生成」的 AC5 直接冲突。**按 issue 指示「找不到再自行实现」**：采用 §4.1 方案 A（Line2D/Polygon2D + AnimationPlayer 关键帧），并在 implement PR 中附本调研表说明。

### 6.3 阻塞

| 被阻塞方 | 优先级 | 说明 |
|---------|--------|------|
| #575 战斗实体状态机 | High | 依赖 #573+#574——动画消费接口是状态机视觉输出端 |
| #579 打击反馈 | High | 刀光节点/挥砍时序是火花/hit-stop 的锚点 |
| #577 拼刀判定 | Med | guard/parry_success 帧是判定成功的视觉回报 |

### 6.4 准备工作

- [ ] 确认 #573/#575 契约文本不再变更（canonical 11 态 + 输入事件集）
- [ ] constants.gd FRAME_ANIM_* 分区命名与 #584 调参面板消费格式对齐（#584 尚未 research，仅保持 DRAFT 注释规范即可）
- [ ] 确认 CI E2E 截图流程可注入多状态 shot（#559 已验证基础能力）

---

## 7. Spike / 实验（depth/deep 必填，≥3 实验）

### 实验 1：Line2D 摆姿关键帧的可控性验证

- **要回答的问题**：Line2D 逐段节点（头/躯干/四肢/刀）用 AnimationPlayer 摆姿，能否在**帧间距不对称**（前摇 8 / 暴发 4 / 收招 10）下表达《小小系列》式的「起势慢→爆发快→收招滞」力度感？
- **方法**：原型实现 attack clip（3 段帧节奏），对骨架节点写关键帧（rotation/position）；用慢动作回放 + 截图对比前摇/暴发/收招姿态；同时验证「关键帧时间戳从 constants 派生」的可行性（动态生成 Animation 资源 vs 预置动画资源再改时间戳——选更优者）。
- **预期结果**：Line2D 关节 rotation 摆姿足以表达力度感；时间戳可从 constants 派生（动态生成 Animation 资源路径优先——零 .tres 资产，AC5 友好）。
- **对方案的影响**：确认 §4.1 方案 A 可行；若动态生成 Animation 不可行则退回「预置 clip + 时间戳校验断言」（仍满足 AC3）。

### 实验 2：刀光弧线 Polygon2D additive 的参数化绘制

- **要回答的问题**：SwordArc 弧线（半径/张角/透明度衰减）参数化生成后，additive 合成在雪夜暗背景（冷蓝灰基调）上是否醒目而不刺眼（反页游光效）？
- **方法**：实现 SwordArc 动态 Polygon 生成（扇形弧 + 渐变透明度）；attack 暴发帧触发，用 2-3 组参数（张角 90°/120°/150°、衰减时长）各截 1 帧对比；验证与碰撞体完全解耦（节点树无碰撞类型）。
- **预期结果**：120° 张角 + 短衰减（≈4 帧）视觉最佳；additive 不产生碰撞；参数入 FRAME_ANIM_* DRAFT。
- **对方案的影响**：确认 §4.4 方案 A；参数初值写进 constants 供 #584 裁决。

### 实验 3：动画过渡 ≤2 帧的实现策略

- **要回答的问题**：Godot 4.7 AnimationPlayer 直接 play 切换 clip 时，姿态跳变能否控制在 ≤2 帧内（AC1）？是否需要 AnimationTree/手动插值？
- **方法**：实现 3 种过渡策略对比：① 直接 play（同帧切换）② AnimationTree 交叉淡化（crossfade 0.03s）③ 手动姿态插值（当前姿态→目标 clip 首帧 2 帧内插值）；各跑 idle→move、move→attack、attack→guard 三组，用帧采样断言过渡完成时刻。
- **预期结果**：策略 ① 在「clip 首帧姿态 = 上一状态尾帧姿态」的设计约定下即可满足 ≤2 帧（最简单）；② 作为 fallback；③ 仅在个别跳变大的转移（stagger→idle）需要。
- **对方案的影响**：决定 §4.1 动画调度实现（推荐 ①+约定，复杂度最低且可测）。

---

## 8. 交接上下文（Continuation Context）

### 8.1 系统状态（plan agent 接手时）

- **已存在（#572 merged，勿重建）**：`shandong-wolf/gdscripts/constants.gd`（WolfConstants，# DRAFT 分区含弹反/架势/两条命/刀伤/帧节奏）、`state_machine.gd`（StateMachineBase：enter/exit/update + transition_to 防重入）、`game.gd`（Game autoload）；`tests/` 三入口绿；`scenes/Main.tscn` 标题场景（勿动）。
- **本 PRD 交付物（plan 需设计、implement 需实现）**：
  1. `constants.gd` 新增 `FRAME_ANIM_*` # DRAFT 分区（attack 前摇 8 / 暴发 4 / 收招 10 冲突值 10 vs 14 双存互引、过渡 ≤2、步态 4 帧、骨骼几何参数、BODY_COLOR #2b2b2b / SWORD_COLOR #c0c8d0）——**禁止实现期硬编码帧节奏**
  2. `stick_figure.gd`：Line2D/Polygon2D 程序化骨架（头圆+躯干/四肢线+刀长线）
  3. `stick_figure_controller.gd`：`consume_state(state)` 契约 + 11 态→clip 映射（canonical 权威 = #575）+ 过渡 ≤2 帧策略
  4. `stick_figure_anim_states.gd`：动画状态对象（派生 StateMachineBase，enter/exit/update）
  5. `sword_arc.gd`：Polygon2D additive 刀光弧线（纯视觉，无碰撞）
  6. `tests/test_stick_figure_animation.gd` + run_tests.gd 挂载
  7. `e2e_shots.json`：动画状态 shot 注入（idle/move/attack 3 段/guard/stagger）
- **关键文件已读**：constants.gd（§帧节奏）、state_machine.gd（三接口）、game.gd（autoload 挂接点）、Main.tscn（标题场景勿动）、visual-implementation-path.md §6.5（火柴人配方，implement 必读）。

### 8.2 主要风险

| 风险 | 缓解 |
|------|------|
| FRAME_ANIM_ATTACK_RECOVERY 10 与既有 FRAME_ATTACK_RECOVERY 14 冲突 | 双值共存互引注释，#584 裁决；实现禁止二选一 |
| #575 canonical 状态名未来漂移 | 映射表单点 + 单测枚举断言 11 态全覆盖 |
| 动画过渡 ≤2 帧在跳变大转移（stagger→idle）难达标 | 实验 3 验证 + 手动插值 fallback |
| E2E 截图用户裁决不通过 | taste-draft 领域：摆姿/帧节奏候补值可调；机械接口先行 |

### 8.3 下一步（plan agent）

1. 按 §4 推荐（方案 A × 3）设计具体文件结构与 AnimationPlayer 动画资源组织（动态生成 vs 预置 + 时间戳校验）。
2. 设计 consume_state 契约签名与映射表（与 #575 契约文本逐条对齐）。
3. 设计单测断言（过渡时长 / 刀光无碰撞 / constants 派生 / 未知状态降级）。
4. 设计 E2E shot 注入方案（如何把角色摆进 Main.tscn 或独立测试场景供截图）。
5. 红线：零 `mini-pong/` 写死；零美术资源；帧节奏不硬编码；不修改 Main.tscn 标题场景（除非设计确认新增角色层，需在 DESIGN 中显式说明）。

---

*PRD 由 game-research-agent 产出（2026-08-19），依据 game-research-agent skill（profile-level，含 Patch 1-20）流程：issue 读取 → Obsidian 检索 → 代码侦查 → 开源调研 → PRD 撰写 → research PR。*
