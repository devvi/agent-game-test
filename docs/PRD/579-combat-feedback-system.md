# PRD #579 — [Rendering] 打击反馈系统（火花 / hit-stop / 屏震 / 慢动作）

> **Issue:** #579
> **标签:** enhancement, graphics, workflow/research, version/mvp（分解 JSON `docs/RAW/game-to-issues-shandong-wolf.json` id=8）
> **深度:** deep（分解 JSON id=8 标注 `depth: deep` → §1–8 全必填，§7 含 ≥3 实验）
> **Agent:** game-research-agent
> **日期:** 2026-08-20
> **所有权:** `content_ownership: mechanical`（反馈机制实现=机械工程；强度参数/时长/幅度/粒子数= taste-draft，constants.gd # DRAFT + 候补值 + E2E 截图用户裁决，不在本 issue 定稿）
> **引擎/目录约束:** Godot 4.7.1 / `shandong-wolf/`（manifest `game.active: shandong-wolf` + subprojects.path 单一事实源；本 PRD 全部路径前缀 `shandong-wolf/`，零 `mini-pong/` 写死）
> **研究选项:** Obsidian 知识库已搜索（`~/Documents/Obsidian Vault/`（OBSIDIAN_VAULT_PATH=/Volumes/Obsidian）：wiki grep 只狼 → `wiki/游戏设计理念.md`（只狼为灵感来源、「游戏机制是超越文本的修辞手段」）；raw grep 弹反/格挡/架势/打击反馈 → `raw/Bear/JRPG 战斗系统研究 - 最终综合报告.md`（「弹反/闪避 = 时机判定」动作进阶层 + 分层设计：基础层→进阶层→策略层）、`raw/Bear/feedback.md`（反馈设计原始材料，弱相关）；wiki grep 反馈/顿帧 → `wiki/体验引擎-glossary.md`（Candor 坦诚=诚实直接的反馈，设计理念层面佐证「反馈必须诚实=分级与奖励成正比」））+ 设计 brief（`docs/RAW/shandong-wolf-brief.md` §审美坐标/§核心机制/§校准偏好）+ 只狼调参基准（`agents/skills/game-to-issues/references/sekiro-tuning-reference.md`：弹反成功必须比格挡爽=火花+hit-stop+硬直 1.2s；崩解惩罚清晰=白闪+失衡 2-3s；处决是奖励不是补刀）+ 视觉配方（`agents/skills/game-to-issues/references/visual-implementation-path.md` §6.5 反馈配方：GPUParticles2D 火花 burst + hit-stop（Engine.time_scale 0.05-0.1 持续 80-150ms）+ Camera2D 屏震 offset 衰减 2-4px + 慢动作 + §7 处决特写配方）+ 同链 issues（#573 输入 / #574 动画 / #575 战斗实体 / #577 判定 / #580 处决 / #582 氛围 / #583 场景 / #585 组装）+ 开源调研（GitHub API 检索 hit-stop/time_scale/camera shake/impact spark，见 §6.2）
> **来源:** backlog-promotion（`docs/RAW/game-to-issues-shandong-wolf.json` id=8，estimate 3d，priority critical）
> **前置依赖:** #574（merged #612：StickFigureController consume_state + SwordArc 刀光）、#575（merged #618：CombatEntity + 11 态战斗状态机 + 6 信号契约）、#577（merged #626：CombatJudge + AttackWindow 判定层，五结果事件契约 parry_success/block_held/hit_landed/clash/stance_broken 已发射）——全部已满足

---

## 1. 问题定义

### 1.1 现状（2026-08-19 worktree 侦查 @ origin/main 1bdb6c7）

| 文件 | 状态 | 说明 |
|------|:----:|------|
| `shandong-wolf/gdscripts/combat_entity.gd` | ✅ 已交付（#575/#618） | CombatEntity（Node2D）：两段血 hp_1/hp_2 + stance + facing 数据容器、request_transition 唯一转移入口、**6 信号契约**（hp_changed / stance_changed / stance_broken / state_changed / died / revived）——**反馈事件的事实信号源** |
| `shandong-wolf/gdscripts/combat_state_table.gd` | ✅ 已交付（#575/#618） | CANONICAL_STATES 11 态权威集（idle/move/attack/heavy_attack/guard/parry_success/stagger/stance_break/execute/revive/dead）+ TRANSITIONS 转移表；**guard → parry_success 表内**（#577 弹反驱动入口已拓扑预留） |
| `shandong-wolf/gdscripts/combat_states.gd` | ✅ 已交付（#575/#618） | 11 个状态对象（CombatStateBase 派生），含 PARRY_SUCCESS_FRAMES 帧计数自动退出 |
| `shandong-wolf/gdscripts/constants.gd` | ✅ 已交付（#572/#584/#599/#609） | WolfConstants 全量 # DRAFT：战斗时序 5 常量（STAGGER_FRAMES=12 / PARRY_SUCCESS_FRAMES=10 / STANCE_BREAK_RECOVERY_SEC=3.0 / REVIVE_SECONDS=1.0 / INVINCIBLE_SECONDS=1.0）、SLOWMO_COEFF=0.2、颜色（BODY_COLOR #2b2b2b / SWORD_COLOR #c0c8d0）、刀光弧线 4 参（SWORD_ARC_SWEEP_DEG=120 / RADIUS=70 / RINGS=4 / ALPHA_START=0.6）——**反馈参数分区尚不存在，本 issue 追加** |
| `shandong-wolf/gdscripts/sword_arc.gd` | ✅ 已交付（#574/#612） | SwordArc（Polygon2D additive）：扇形弧 + 径向透明度衰减 + trigger_burst() 4 帧淡出——**处决 S 级「刀光弧线」已存在，直接复用** |
| `shandong-wolf/gdscripts/input_controller.gd` | ✅ 已交付（#573/#611） | guard_pressed(timestamp_ms) 意图信号（弹反判定归 #577）；本 issue 不消费输入 |
| `shandong-wolf/scenes/Main.tscn` | ✅ 标题场景（#562/#563/#570） | 纯声明式标题；**本 issue 不修改它（红线）**；战斗场景实例化归 #583/#585 |
| `shandong-wolf/gdscripts/combat_judge.gd` | ✅ 已交付（#577/#626） | CombatJudge 判定协调器：攻击窗口登记 → 命中裁决（弹反→拼刀→格挡→受击）→ 发射**五结果事件**（parry_success / block_held / hit_landed / clash / stance_broken）——**本 issue 反馈层的直接事件源（issue body「ReactionController 统一消费 #6 的反馈信号」= 分解 id 6 / #577 事件契约）** |
| `shandong-wolf/gdscripts/combat_attack_window.gd` | ✅ 已交付（#577/#626） | AttackWindow 纯数据容器：attacker/start_frame/active_frames/hp_damage/stance_damage/direction（攻击方向 -1/1）/windup_frames——**火花方向沿刀面法线的方向数据源** |
| `shandong-wolf/gdscripts/` | ❌ 无反馈层 | 无 ReactionController、无 GPUParticles2D 火花、无 hit-stop/time_scale 管理、无屏震、无白闪、无慢动作执行——**本 issue 全部新建** |
| `shandong-wolf/scenes/` | ❌ 无 Camera2D | 战斗场景（#583）尚未落地，当前无摄像机实例；屏震需 Camera2D 引用——**设计须与场景解耦（@export camera_path + 场景自持 Camera2D）** |
| `shandong-wolf/tests/` | ✅ 七套件（#572/#611/#618） | run_tests.gd 已挂 7 套件；本 issue 追加 test_reaction_controller.gd |
| `shandong-wolf/e2e_shots.json` | ✅ #574 12 态 shot plan | e2e_stick_figure_capture.tscn（CaptureRig.current_state 轮询 + auto_cycle 兜底）——**反馈 E2E 截图像具需独立 rig（见 §7 实验 4）** |

**核心缺口：** shandong-wolf 已有战斗事件的**全部事实信号源**（CombatEntity 6 信号 + 11 态状态机 + CombatJudge 五结果事件契约 + AttackWindow 方向数据 + SwordArc 刀光 + constants 集中地），但**消费这些信号并渲染分级反馈的执行层零存在**——没有 ReactionController 把「弹反成功 / 架势崩解 / 处决 / 受击」翻译成「火花 + hit-stop + 屏震 + 慢动作 + 白闪」的同步组合，玩家打中敌人与挨打时画面上毫无回应。反馈是只狼手感的灵魂（issue body 用户强调 2026-08-19），本层是 #585 组装「可玩战斗闭环」的体验关键件。**#577 判定系统已 merged（#626）——五结果事件是现成的触发入口，本 issue 只需定义消费契约并组合渲染，无判定逻辑负担。**

### 1.2 验收条件（源自 Issue #579 body，映射到本 PRD 保障）

| # | 验收条件 | 本 PRD 的保障措施 |
|---|---------|------------------|
| AC1 | 反馈分级矩阵完整实现：S/A/B/C 六级事件各有独立反馈组合（火花/hit-stop/屏震/慢动作/白闪），参数集中 constants.gd # DRAFT | §4 多子系统方案（4.1 控制器 / 4.2 火花 / 4.3 时间缩放 / 4.4 屏震 / 4.5 白闪/刀光）+ §5.1 AC1：FEEDBACK_ 前缀 # DRAFT 常量全集中，六级事件矩阵驱动 |
| AC2 | 弹反成功四要素同步：火花(16-20粒) + hit-stop(80-100ms) + 屏震(3px) + 敌人白闪/硬直 1.2s——E2E 截图可捕获同一帧 | §4.1 方案 A（ReactionController 单一入口 trigger_feedback 组合触发）+ §7 实验 4（E2E 同帧捕获 rig）；§5.1 AC2 四要素齐发且 settle_frames 覆盖效果窗口 |
| AC3 | 火花碰撞点位于刀与刀交点（非角色中心），方向沿刀面法线，颜色苍白金 #ffd9a0 系 | §4.2 方案 A（spawn 参数化：世界坐标 + 法线方向 + 等级）+ §5.1 AC3：碰撞点由 #577 结果事件携带，spark 不自行猜测中心 |
| AC4 | hit-stop 与慢动作时间缩放可安全嵌套恢复（处决 0.05x 特写结束后恢复正常 time_scale，无卡死） | §4.3 方案 A（时间缩放栈 TimeScaleStack：push/pop + 墙钟恢复）+ §7 实验 1（嵌套恢复）+ §5.1 AC4：嵌套 push 后逐层 pop，墙钟兜底强制恢复 |
| AC5 | 反馈强度与事件奖励成正比（处决>弹反>格挡>命中），滥用慢动作/满屏特效=AC 失败 | §4 分级矩阵（S/A/B/C 参数随等级单调）+ §5.1 AC5：矩阵参数比 + 反页游断言（粒子数/慢动作仅限 S/A 级） |
| AC6 | E2E 截图提交用户裁决：『刀锋相撞』重量感成立，且未破坏雪夜水墨宁静基调（禁止页游光效感） | §7 实验 4 + §8 交接：E2E 截图产出路径 + taste-draft 裁决通道（#584 面板 + 用户实机） |

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 玩家实机操作（MVP 战斗闭环） | 每次游玩 | 玩家弹反敌人攻击：『叮！』瞬间火花 16-20 粒 + 画面顿帧 80-100ms + 屏震 3px + 敌人白闪硬直——四要素 80-100ms 内同步完成形成瞬间爽感；处决：刀光弧线 + 血色粒子 + 150ms 顿帧 + 4px 强震 + 0.05x 特写慢动作；普通命中：小火花 + 50ms 顿帧 + 2px 沿攻击方向屏震 |
| B | 下游系统消费（#577/#580/#585） | 每次 impl PR | 判定系统（#577，已 merged #626）发射结果事件（parry_success / block_held / hit_landed / stance_broken / clash）→ ReactionController 按等级矩阵组合反馈；处决系统（#580）发射 execute 事件 → S 级组合；组装层（#585）把 ReactionController 实例化进战斗场景并接 Camera2D |
| C | 开发者 headless + E2E 验证 | 每次 impl PR | `godot --path shandong-wolf/ --headless --script tests/run_tests.gd`：直接 new ReactionController 断言矩阵映射/时间栈恢复/参数集中；E2E capture 场景注入 parry_success 事件截图同帧四要素 |

### 1.4 范围边界（Patch 14 去冲突 + 状态契约红线）

| PRD / 分解 id | 覆盖范围 | 本 PRD 不重复覆盖 |
|-----|---------|------------------|
| #574（动画，merged） | consume_state 动画契约 + SwordArc 刀光弧线 | ❌ 不重造刀光；处决 S 级直接复用 SwordArc.trigger_burst()（已存在） |
| #575（战斗实体，merged） | CombatEntity 数据容器 + 11 态状态机 + 6 信号 | ❌ 不修改 combat_entity.gd；只订阅其信号（状态转移/崩解/生死） |
| 分解 id 6 / #577（判定，merged #626） | 弹反窗口/拼刀/架势伤害判定，发射结果事件 parry_success/block_held/hit_landed/stance_broken/clash | ❌ 不做判定；本 issue 订阅 #577 已发射的五结果事件 + CombatEntity 状态信号，按 §8.3 契约组合反馈 |
| 分解 id 9 / #580（处决） | 处决触发条件 + 特写演出编排 | ❌ 不做处决判定与演出编排；只对 execute 事件渲染 S 级反馈组合（刀光+血粒子+顿帧+强震+慢动作） |
| #582（氛围，research PRD 已合） | 雪幕/冷月光/水墨晕染/血色 vignette（环境氛围层） | ❌ 不重复氛围层；火花/白闪是**战斗事件瞬态反馈**（事件驱动、≤150ms、局部），与常驻氛围层（#582）上下分层共存；血色 vignette 归 #582，本 issue 的血色粒子是处决 S 级局部粒子 burst |
| #584（数值 DRAFT，merged） | 手感数值集中表 + DebugCanvas 调参面板 | ❌ 不裁决任何 # DRAFT 数值；新增 FEEDBACK_ 常量同样标 # DRAFT + 候补值，定稿通道归 #584/用户 |
| #572（scaffold，merged） | StateMachineBase + Game autoload 锚点 | ❌ 不重写状态机基类；ReactionController 不接状态机，只订阅信号 |

**状态契约红线：** 反馈事件名以 CombatEntity 信号 + #577 结果事件为准（state_changed / stance_broken / died / revived + parry_success / block_held / hit_landed / stance_broken / clash），禁止自造事件名。

### 1.5 预期行为（分级反馈矩阵，本 PRD 的核心语义）

> 参数全部 # DRAFT（候补值来自 issue body 矩阵 + 只狼基准 + 视觉配方 §6.5），**数值定稿归用户**（#584 通道 + E2E 截图裁决）。

| 事件 | 等级 | 火花 | hit-stop | 屏震 | 慢动作 | 白闪 | 事件信号源 |
|------|:----:|------|----------|------|--------|------|-----------|
| 处决 | S | 刀光弧线（复用 SwordArc）+ 血色粒子 10-14 粒 | 150ms | 4px 强 | 0.05x 0.5s | 无（构图留白） | execute 状态（#580 驱动 / 测试注入） |
| 弹反成功 | A | 16-20 粒大火花 | 80-100ms | 3px | 0.3x 0.2s 渐变恢复 | 敌人白闪 | #577 parry_success / guard→parry_success 转移 |
| 架势崩解 | A- | 无火花（全屏淡白闪承担视觉） | 100ms | 3px | 0.5x 0.3s | 敌人持续白闪 + 失衡 | stance_broken 信号 |
| 普通格挡 | B | 6 粒最小火花 | 30ms | 1px | 无 | 无 | #577 block_held / guard 状态进入 |
| 普通命中 | C | 8 粒小火花 | 50ms | 2px 沿攻击方向 | 无 | 敌人硬直（#574 stagger 动画） | #577 hit_landed / attack→stagger |
| 玩家受击 | C | 无火花 | 60ms | 4px | 无 | 玩家后仰（#574 stagger 动画） | state_changed → stagger |

**设计语义（issue body 三原则）：**
1. **分级与奖励成正比**：S>A>A->B>C，参数随等级单调（粒子数/时长/幅度递增），滥用慢动作/满屏特效 = 违反 AC5。
2. **克制即力量**：火花=苍白金 #ffd9a0 系（禁橙色页游爆焰）；hit-stop ≤150ms（普通事件 ≤100ms，超出则黏腻）；慢动作仅限 S/A 级（滥用失去重量）。
3. **碰撞点精准**：火花生成于刀与刀的交点（世界坐标，由事件携带），方向沿刀面法线；粒子 6-20 按等级，不得盖住角色。

### 1.6 Obsidian 知识检索

- **Vault 直接读取成功**（`~/Documents/Obsidian Vault/`，wiki + raw 定向 grep：`只狼|弹反|格挡|架势|打击反馈|顿帧|hit-stop|反馈`）。
- **命中笔记：**
  - **《游戏设计理念》（wiki）**：*「游戏机制是超越文本的修辞手段」*、灵感来源含《只狼》→ 佐证反馈系统作为「手感修辞」的地位：反馈组合（叮！）本身就是表达，不是装饰。
  - **《JRPG 战斗系统研究 - 最终综合报告》（raw/Bear）**：*「弹反/闪避 = 时机判定」动作进阶层* + **分层设计**（基础层→进阶层→策略层）+ FF16 Stagger 系统（破防增伤）→ 支撑「弹反成功反馈必须强于格挡」（时机判定的奖励可感知），与只狼铁律 1 互证。
  - **《体验引擎-glossary》（wiki）**：*Candor（坦诚）— 诚实、直接的反馈* → 设计理念层面佐证「反馈必须诚实 = 分级与事件奖励成正比」，反例 = 反馈与事件价值不符（AC5 理念依据）。
  - **《feedback.md》（raw/Bear）**：反馈设计原始材料（弱相关，游戏内反馈呈现的叙事视角）。
- **Vault 无 hit-stop/屏震/粒子技术笔记**（grep `顿帧|hit-stop|屏震` 命中均无关）→ 技术权威源 = issue body 画面实现路径（GPUParticles2D burst / SceneTree.time_scale / Camera2D offset 噪声 / CanvasItem modulate）+ 配方 `visual-implementation-path.md` §6.5/§7 + 开源调研（§6.2）。

---

## 2. 设计意图

### 2.1 现状为何存在

| 原因 | 细节 |
|------|------|
| 战斗系统分层推进 | #572 地基 → #573 输入 → #574 动画 → #575 数据/状态机 → #577 判定 → **#579 反馈（本层）** → #580 处决 → #585 组装；反馈层依赖信号源（#575）与刀光（#574）先落地，故排在判定之后、组装之前 |
| 反馈被拆为独立 issue | 分解 JSON id=8 明确「画面实现路径：反馈机制实现=mechanical；强度参数=taste-draft」——机制与数值分权，反馈层作为机械 issue 与 #584 数值 DRAFT 分离 |
| 无现成反馈执行层 | mini-pong 时代的视觉反馈（击打特效）未迁移到 shandong-wolf；shandong-wolf 至今只有静态画面（标题场景 + 动画截图像具），无任何战斗瞬态反馈 |

### 2.2 为何现在

1. **信号源已齐**：#575 的 CombatEntity 6 信号（state_changed/stance_broken/died/revived）已 merge，#574 的 SwordArc 刀光已存在，#577 的 CombatJudge 五结果事件（parry_success/block_held/hit_landed/clash/stance_broken）**已 merged（#626）**——反馈层所需的全部事实输入可用，且判定层已按契约发射事件，本 issue 纯消费组合，无任何判定负担。
2. **用户 2026-08-19 强调**：打击反馈是只狼核心，特效效果重点落实——「打铁」节奏是只狼式爽快的 50% 来源，本 issue 是 MVP 手感验证的关键件。
3. **#585 组装在即**：反馈层是组装「可玩战斗闭环」的前置依赖（#585 deps 含 id=8），晚落地会阻塞闭环验收。

### 2.3 之前约束（继承 issue + brief + 配方 + 只狼基准，Patch 19）

| 约束 | 详情 | 来源 |
|------|------|------|
| 引擎/目录 | Godot 4.7.1 / `shandong-wolf/`，路径零 mini-pong 写死 | manifest + #572 |
| 画面实现路径 | 火花=GPUParticles2D burst；hit-stop=SceneTree.time_scale 短暂归零+安全恢复；屏震=Camera2D offset 程序化噪声（沿攻击向量+衰减曲线）；白闪=CanvasItem modulate 动画；刀光=Polygon2D additive 弧线 | issue body 画面实现路径 |
| 禁页游光效 | 禁全屏闪白滥用/光效叠加/粒子盖角色；火花苍白金 #ffd9a0 禁橙色；雪夜水墨宁静基调不可破坏（AC6） | issue body + brief 反例 |
| 只狼基准 | 弹反成功必须比格挡爽（火花+hit-stop+敌人硬直 1.2s 同步）；慢动作只用于弹反/处决/崩解；hit-stop ≤0.1s 否则黏腻（处决 S 级例外 150ms） | sekiro-tuning-reference.md 手感铁律 1/5 |
| 分级与奖励成正比 | 处决>弹反>格挡>命中；滥用慢动作=AC 失败 | issue body + 体验引擎 Candor |
| 参数集中 | 所有反馈参数集中 constants.gd # DRAFT + 候补值 + 情感断言，禁止散落硬编码；定稿归 #584/用户 | #572 红线延续 + issue body |
| 音效预留 | 音效接口预留（v1 音效系统 #593 接入）——本 issue 只留 hook 不发声 | issue body |
| 工程/品味分离 | 机制=mechanical（本 issue）；强度参数=taste-draft（#584 通道 + E2E 截图用户裁决） | issue body + brief 校准偏好 |
| 不修改红线 | Main.tscn（标题场景）不碰；combat_entity.gd 不碰；不引入第三方 addon | #572/#575 裁决延续 |

---

## 3. 影响分析

### 3.1 直接影响文件

| 文件 | 模块 | 变更性质 |
|------|------|---------|
| `shandong-wolf/gdscripts/reaction_controller.gd` | 新增 | ReactionController（class_name，extends Node）：统一消费战斗信号 + 分级矩阵调度 + 组合触发 |
| `shandong-wolf/gdscripts/feedback_spark.gd` | 新增 | 火花粒子发射器（GPUParticles2D 派生或持有）：burst 参数化（位置/方向/等级），颜色 #ffd9a0 系 |
| `shandong-wolf/gdscripts/time_scale_stack.gd` | 新增 | 时间缩放栈（RefCounted）：push/pop + 墙钟兜底恢复（hit-stop 与慢动作嵌套安全，AC4） |
| `shandong-wolf/gdscripts/screen_shake.gd` | 新增 | 屏震组件（Node 持有 Camera2D 引用）：offset 程序化噪声 + 方向 + 衰减曲线 |
| `shandong-wolf/gdscripts/flash_effect.gd` | 新增 | 白闪组件（CanvasItem modulate / CanvasLayer ColorRect）：敌人白闪 + 全屏淡白闪（A- 级） |
| `shandong-wolf/gdscripts/constants.gd` | 修改 | 追加「反馈分区」# DRAFT 常量（FEEDBACK_ 前缀：火花/时序/屏震/慢动作/白闪/颜色，见 §8.3） |
| `shandong-wolf/tests/test_reaction_controller.gd` | 新增 | 单测：矩阵映射/时间栈/屏震衰减/白闪参数（AC1/AC4/AC5） |
| `shandong-wolf/tests/run_tests.gd` | 修改 | 注册 test_reaction_controller.gd |
| `shandong-wolf/scenes/e2e_feedback_capture.tscn` | 新增 | E2E 截图像具场景（CaptureRig 变体 + Camera2D + ReactionController + 注入接口，AC2/AC6） |
| `shandong-wolf/gdscripts/e2e_feedback_capture.gd` | 新增 | E2E rig 脚本：current_state 轮询兼容 + feedback 事件注入（§7 实验 4） |
| `shandong-wolf/e2e_shots.json` | 修改 | 追加反馈 shot group（parry_success / stance_break / execute 三档截图） |

### 3.2 新文件（汇总）

| 文件 | 职责 | 依赖 |
|------|------|------|
| `reaction_controller.gd` | 信号订阅 → 等级矩阵 → 组合触发（火花/时间栈/屏震/白闪/刀光） | combat_entity 信号 + #577 事件接口 |
| `feedback_spark.gd` | GPUParticles2D burst 封装（one_shot，位置/法线/等级参数化） | constants FEEDBACK_SPARK_* |
| `time_scale_stack.gd` | Engine.time_scale 栈式管理（push/pop/墙钟兜底） | 无（纯 RefCounted） |
| `screen_shake.gd` | Camera2D.offset 程序化噪声（trauma 模型） | constants FEEDBACK_SHAKE_* |
| `flash_effect.gd` | modulate/ColorRect 白闪（敌人瞬闪 + 全屏淡闪） | constants FEEDBACK_FLASH_* |
| `test_reaction_controller.gd` | 四组用例（矩阵/时间栈/屏震/白闪） | 其余新文件 |
| `e2e_feedback_capture.gd/.tscn` | E2E 截图 rig（事件注入 + 状态轮询） | reaction_controller + 各效果组件 |

### 3.3 间接影响

| 文件/系统 | 影响 | 说明 |
|-----------|------|------|
| `combat_entity.gd`（#575） | 只读消费 | 订阅 state_changed/stance_broken/died/revived；不改接口（红线） |
| `sword_arc.gd`（#574） | 复用触发 | S 级处决调用 trigger_burst()；不修改 |
| `stick_figure_controller.gd`（#574） | 无 | 白闪作用于实体 modulate 外层（不动动画层） |
| `debug_canvas.gd`（#584） | 可选扩展 | 反馈参数入调参面板属 #584 后续扩展，本 issue 只保证参数集中可读 |
| `scenes/Main.tscn` | 无 | 红线：不修改 |
| `game.gd`（autoload） | 可选锚点 | ReactionController 由战斗场景实例化（#583/#585），不强制挂 autoload（与场景解耦） |

### 3.4 数据流

```
CombatEntity (#575)                      CombatJudge (#577, merged #626)
  ├─ state_changed(from,to) ───────────┐   ├─ parry_success ──────────┐
  ├─ stance_broken(entity) ────────────┤   ├─ block_held ─────────────┤
  ├─ died(entity, final) ──────────────┼──►│  ├─ hit_landed ──────────┼──► ReactionController.trigger_feedback(event, data)
  └─ revived(entity) ──────────────────┘   │  ├─ stance_broken ────────┘        │
                                           └─ clash ────────────────────────────┤
                        （#580 execute 事件 / 测试注入 ──────────────────────────┘
                                                          │  分级矩阵查表（等级 S/A/A-/B/C）
                                                          ▼
        ┌───────────────┬───────────────┬───────────────┬───────────────┬──────────────┐
        ▼               ▼               ▼               ▼               ▼
   feedback_spark   time_scale_stack screen_shake    flash_effect    SwordArc(复用)
   GPUParticles2D   Engine.time_scale Camera2D.offset CanvasItem      trigger_burst()
   burst@交点        push/pop+墙钟     trauma 衰减      modulate        （S 级刀光）
        │               │               │               │               │
        └───────────────┴───────────────┴───────────────┴───────────────┘
                                   ▼
                      E2E 截图（同帧捕获 AC2/AC6）+ 音效 hook（#593 预留）
```

### 3.5 文档更新

- [x] `docs/GAME_DESIGN/shandong-wolf/10-REACTION-FEEDBACK.md`（post-merge agent 落盘：分级矩阵 + 组件契约 + 时间栈设计）
- [x] `docs/GAME_DESIGN/shandong-wolf/INDEX.md`（追加 10 章条目）
- [ ] `docs/PRD/579-combat-feedback-system.md`（本文件）
- [x] `docs/DESIGN/579-...`（plan agent 产出，非本阶段）

---

## 4. 方案对比（多子系统 PRD，Patch 19：4.1–4.5 各子系统独立对比）

### 4.1 ReactionController 架构（组合触发核心）

**方案 A：单控制器 + 事件驱动（推荐）**
- 描述：ReactionController（Node）订阅 CombatEntity 信号 + 暴露 `trigger_feedback(event: String, data: Dictionary)` 公开 API（#577/#580/测试注入统一入口）；内部查分级矩阵表（event → 等级 → 参数包），按参数包并行触发火花/时间栈/屏震/白闪/刀光。
- 优点：单一入口（AC2 四要素同步的保证——同一帧内组合触发）；事件名与 #577 契约对齐；与场景解耦（@export camera_path + 效果组件引用，战斗场景/测试场景都可实例化）。
- 缺点：控制器内部需管理各效果组件的生命周期（可接受，组件均为轻量 Node）。
- 风险：Low。Effort：1-2 天。

**方案 B：每个反馈类型一个独立 autoload 管理器**
- 描述：SparkManager / ShakeManager / TimeScaleManager 各自为 autoload 单例，事件方各自调用。
- 优点：无场景耦合，全局可用。
- 缺点：**四要素同步无统一入口**（AC2 的「同一帧」无法保证——各管理器独立处理有帧偏移风险）；全局单例与 #572 的「Game autoload 锚点 + 场景实例化」惯例冲突；测试注入路径分散。
- 风险：Med（同步问题直接打 AC2）。Effort：2-3 天。

**方案 C：反馈逻辑全部内嵌 CombatEntity**
- 描述：在 combat_entity.gd 内直接写反馈触发。
- 优点：零新文件。
- 缺点：**违反 #575 红线**（本层不做演出）；实体层与渲染层职责耦合；敌人/玩家共用实体导致反馈无法区分方向。
- 风险：High（红线违反 + 耦合）。Effort：1 天（但不可接受）。

**推荐 A：** 单一 ReactionController 入口 = AC2「四要素同步同一帧」的结构性保证；`trigger_feedback(event, data)` 是 #577/#580/测试的唯一注入点（§8.3 契约）。

### 4.2 火花（GPUParticles2D burst）

**方案 A：GPUParticles2D one_shot burst（推荐）**
- 描述：feedback_spark.gd 持有 GPUParticles2D（代码创建，零 .tres），one_shot=true + emitting 触发 burst；参数化：position（刀与刀交点世界坐标）、direction（刀面法线）、level（S/A/B/C → 粒子数 6-20 + 初速 + 寿命）、颜色 #ffd9a0 系（ParticleProcessMaterial color_ramp）。
- 优点：issue body 指定路径；GPUParticles2D 在 2D 像素风下性能优（GPU 模拟）；one_shot burst 语义天然匹配「瞬态事件反馈」；粒子数/寿命全部 # DRAFT 常量可调。
- 缺点：需注意粒子层级（不得盖住角色——z_index 低于角色层，issue 红线）。
- 风险：Low。Effort：1-2 天。

**方案 B：CPUParticles2D**
- 优点：CPU 模拟，逻辑可控性强。
- 缺点：粒子数多时性能劣于 GPU；本项目粒子数上限 20（小规模），GPU 无压力。
- 风险：Low。Effort：1-2 天。

**方案 C：纯 Polygon2D 手绘火花**
- 描述：程序化多边形模拟火花形状。
- 缺点：逐帧手绘动画代码量大、效果难达粒子系统质感；违背「零美术资产 + 程序化」的配方（粒子系统即程序化）。
- 风险：Med。Effort：3+ 天。

**推荐 A：** issue body 指定 + 配方 §6.5 同款；碰撞点/方向由事件 data 传入（AC3 结构保证：位置=刀交点非角色中心）。

### 4.3 hit-stop 与慢动作（时间缩放栈，AC4 核心）

**方案 A：TimeScaleStack 栈式管理 + 墙钟兜底（推荐）**
- 描述：time_scale_stack.gd（RefCounted）：`push(scale, duration_ms)` → Engine.time_scale = 当前栈顶乘积/取最小；`pop()` 恢复上一层；**每层记录墙钟截止（Time.get_ticks_msec，不受 time_scale 影响），到期强制 pop**（防卡死红线，AC4「无卡死」的机械保证）。hit-stop（0.05-0.15s）与慢动作（0.3x/0.5x 长时间）各自 push，嵌套时逐层 pop。
- 优点：嵌套安全有数学保证（栈语义）；墙钟兜底 = 即使逻辑层漏 pop 也不会永久卡死；hit-stop 用极小值（0.05）而非 0（0 会冻结引擎处理，墙钟兜底失效风险）。
- 缺点：需约定所有时间缩放走栈（禁止散落 Engine.time_scale 直接赋值——写进红线）。
- 风险：Low（墙钟兜底 + 实验 1 验证）。Effort：1 天。

**方案 B：直接 Engine.time_scale 赋值 + 手动恢复**
- 描述：hit-stop 时存旧值 → 赋值 → Timer 到期恢复。
- 缺点：**嵌套时旧值覆盖**（处决 0.05x 期间弹反 0.3x → 恢复错乱）；Timer 受 time_scale 影响（缩放期间计时变慢，恢复延迟）；无兜底，漏恢复即永久卡死。
- 风险：High（AC4 直接失败）。Effort：0.5 天（但不可靠）。

**方案 C：godot-timeflow（开源 ⭐21）**
- 描述：引入第三方时钟系统（自定义 clock 路由到 timeline）。
- 优点：功能全（多时钟/独立时间轴）。
- 缺点：**#572 已裁决不引入第三方 addon**；MVP 只需一层栈，重武器；生态风险。
- 风险：Med（红线 + 过度工程）。Effort：1-2 天（含接入成本）。

**推荐 A：** 自研 40 行栈 + 墙钟兜底（与 #575 自研 StateMachineBase 同哲学：地基自研，不引 addon）；实验 1 用嵌套场景验证。

### 4.4 屏震（Camera2D offset）

**方案 A：Camera2D offset + trauma 衰减模型（推荐）**
- 描述：screen_shake.gd（Node）：`@export var camera_path: NodePath`（场景自持 Camera2D，#583 战斗场景 / E2E rig 各挂一个）；trauma 值（0-1）由事件强度映射（S=4px → trauma≈1.0），每帧 `offset = 噪声方向 × trauma² × max_offset`，trauma 按衰减曲线（指数/线性，参数 # DRAFT）回归 0；方向沿攻击向量（data 传入），幅值按等级。
- 优点：issue body 指定（offset 程序化噪声 + 方向沿攻击向量 + 衰减曲线）；trauma² 是业界标准模型（trauma-gd ⭐4 同款），手感成熟；与场景解耦（camera_path 注入）。
- 缺点：需场景提供 Camera2D（当前无——E2E rig 自建一个，战斗场景 #583 挂载）。
- 风险：Low。Effort：1 天。

**方案 B：全局 CanvasLayer offset（无 Camera2D）**
- 描述：把整个画面层平移模拟震屏。
- 缺点：需要重排 CanvasLayer 层级；与 #582 氛围层（CanvasModulate）交互复杂；本质是绕开 Camera2D 的 workaround。
- 风险：Med。Effort：1-2 天。

**方案 C：trauma-gd 插件（开源 ⭐4）**
- 描述：引入第三方屏震插件。
- 缺点：#572 不引 addon 红线；功能与 40 行自研等价。
- 风险：Med。Effort：0.5 天（但违规）。

**推荐 A：** trauma 模型 + camera_path 解耦；E2E rig 自带 Camera2D 验证（实验 2）。

### 4.5 白闪与刀光（CanvasItem modulate / CanvasLayer）

**方案 A：双通道——实体 modulate 闪 + CanvasLayer 全屏淡闪（推荐）**
- 描述：flash_effect.gd 两种模式：① 实体白闪（敌人弹反后 0.1-0.15s modulate 提亮 → 渐回，作用于目标实体，AC2 敌人白闪）；② 全屏淡白闪（A- 架势崩解：CanvasLayer ColorRect 低 alpha 白闪 100ms，不刺眼，issue「全屏淡白闪」语义）。刀光复用 SwordArc（S 级 trigger_burst）。
- 优点：实体闪与全屏闪分离（各自语义清晰：敌人受击反馈 vs 崩解重大事件）；CanvasLayer 层序可控（低于 UI 高于氛围层）；白闪参数 # DRAFT。
- 缺点：实体白闪需目标实体引用（data 传入 entity）。
- 风险：Low。Effort：1 天。

**方案 B：全部 CanvasLayer 全屏闪**
- 缺点：敌人个体白闪无法表达（AC2 敌人白闪失败）；全屏闪滥用 = 页游光效感（AC6 红线）。
- 风险：Med。Effort：0.5 天。

**方案 C：shader 后处理白闪**
- 描述：全屏 canvas_item shader 控制闪白。
- 缺点：与 #582 水墨 shader 叠加管理复杂；MVP 用 ColorRect 足够；过度工程。
- 风险：Med。Effort：2 天。

**推荐 A：** 双通道语义清晰；刀光直接复用现有 SwordArc（零新实现）。

### 4.6 推荐汇总表

| 子系统 | 推荐 | 核心文件 | Effort |
|--------|------|---------|:------:|
| 控制器 | A：单入口事件驱动 | `reaction_controller.gd` | 1-2d |
| 火花 | A：GPUParticles2D one_shot burst | `feedback_spark.gd` | 1-2d |
| 时间缩放 | A：TimeScaleStack + 墙钟兜底 | `time_scale_stack.gd` | 1d |
| 屏震 | A：Camera2D trauma 衰减 | `screen_shake.gd` | 1d |
| 白闪/刀光 | A：实体闪 + 全屏淡闪 + SwordArc 复用 | `flash_effect.gd` | 1d |
| **合计** | | | **3d**（与 estimate 3d 对齐） |

---

## 5. 边界条件与验收标准

### 5.1 验收条件（AC checklist，源自 issue body）

- [x] **AC1: 反馈分级矩阵完整实现** — S/A/B/C 六级事件各有独立反馈组合（火花/hit-stop/屏震/慢动作/白闪），参数集中 constants.gd # DRAFT（FEEDBACK_ 前缀全量集中，见 §8.3）
  - 验证：单测遍历矩阵表（6 事件 × 6 维度参数非空且随等级单调）；grep 断言无散落硬编码
- [x] **AC2: 弹反成功四要素同步** — 火花(16-20粒) + hit-stop(80-100ms) + 屏震(3px) + 敌人白闪/硬直 1.2s，E2E 截图可捕获同一帧
  - 验证：`trigger_feedback("parry_success", {pos, normal, target_entity})` 单帧组合触发；E2E rig 注入后 settle_frames 覆盖效果窗口截图（实验 4）
- [x] **AC3: 火花碰撞点精准** — 刀与刀交点（非角色中心），方向沿刀面法线，颜色苍白金 #ffd9a0 系
  - 验证：data.position/data.normal 直传 GPUParticles2D.position/direction（无中心猜测代码路径）；color_ramp 断言 #ffd9a0 ±10%；单测断言 spark 位置 == 注入位置
- [x] **AC4: 时间缩放嵌套安全** — 处决 0.05x 特写结束恢复正常 time_scale，无卡死
  - 验证：实验 1（hit-stop push → 慢动作 push → 逐层 pop → 终值 1.0）；墙钟兜底用例（模拟漏 pop → 到期强制恢复）；单测 time_scale_stack.gd 三路径
- [x] **AC5: 反馈强度与事件奖励成正比** — 处决>弹反>格挡>命中，滥用慢动作/满屏特效=AC 失败
  - 验证：矩阵参数单调性断言（粒子数/时长/幅度 S≥A≥B≥C）；慢动作仅 S/A 级启用断言；反页游断言（无全屏闪白滥用路径——全屏淡闪仅 A- 级 100ms 低 alpha）
- [x] **AC6: E2E 截图用户裁决** — 『刀锋相撞』重量感成立，未破坏雪夜水墨宁静基调（禁止页游光效感）
  - 验证：实验 4 截图产出（parry_success/stance_break/execute 三档）；review agent 提交用户裁决；taste-draft 数值通道 #584

### 5.2 边缘情形（≥5）

1. **重复事件连发**（连招中连续 hit_landed）——同一事件 50ms 内重复触发：火花 one_shot 重触发覆盖（不叠加粒子池爆量）；时间栈 push 次数限制（MAX_STACK_DEPTH=3，超限丢弃新 push 保旧恢复）；屏震 trauma 取 max 不叠加
2. **事件发生时场景无 Camera2D**（headless 测试 / 标题场景）——screen_shake 对 null camera no-op + push_warning，不崩
3. **hit-stop 期间新事件到达**（0.05x 中弹反）——时间栈嵌套 push（AC4 主场景），火花/屏震照常（视觉不冻结，time_scale 只影响逻辑 delta）
4. **处决慢动作 0.05x 期间玩家死亡**（died 事件）——C 级玩家受击反馈 + 时间栈外层恢复；died 本身不触发慢动作（防叠加卡顿）
5. **粒子层级盖角色**（AC3 粒子 20 粒上限附近）——z_index 硬约束（火花层 < 角色层）+ 粒子数上限 # DRAFT 常量，单测断言 z_index 配置
6. **event 未知/无等级映射**——trigger_feedback 对未知事件 push_warning + no-op（矩阵表外拒绝），状态不漂移
7. **实体引用失效**（敌人已 free 后白闪）——flash_effect 对 is_instance_valid() 检查，失效则跳过实体闪只保留屏震/火花
8. **屏震方向 data 缺失**（#577 早期版本未传 normal）——默认攻击方向（攻击者 facing 方向），不崩

### 5.3 失败路径（≥3）

1. **时间栈漏 pop → 永久卡死**——墙钟兜底：每层 push 记录 deadline（Time.get_ticks_msec + duration），_process 轮询到期强制 pop（AC4 机械保证，实验 1 验证）
2. **GPUParticles2D one_shot 不触发**（emitting 时序错误）——feedback_spark 用 `restart()` + emitting=true 标准序列；单测断言 particles.emitting == true（实验 3 验证）
3. **E2E 截图抓不到同帧**（效果窗口 < settle_frames）——E2E rig 的 shot 定义中 hit-stop 窗口 > 截图 settle 间隔；或 rig 提供「冻结效果帧」模式（实验 4 兜底：把时间栈暂停，让火花/白闪停留在画面中供截图）
4. **#577 事件未连接时反馈无输入**——降级路径：ReactionController 由 CombatEntity 状态信号驱动（state_changed→guard 触发 B 级、→parry_success 触发 A 级、stance_broken 触发 A-、→stagger 触发 C）；#577 事件接口连接后自动增强。**#626 已实现 CombatJudge，组装层（#585）绑定 judge 信号即可；本 issue 提供 bind_judge() 连接方法**

---

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 | 说明 |
|------|------|:----:|------|
| #574（动画 + SwordArc） | ✅ merged #612 | 无 | 刀光复用；stagger/parry_success 动画已存在 |
| #575（CombatEntity + 11 态） | ✅ merged #618 | 无 | 6 信号契约 = 反馈事件事实源 |
| #577（判定系统） | ✅ merged #626 | 无 | CombatJudge 五结果事件 = 反馈主输入（parry_success/block_held/hit_landed/clash/stance_broken）；本 issue 提供 bind_judge() 连接 |
| #580（处决系统） | ⏳ backlog | Low | execute 事件触发 S 级；**非阻塞**（测试注入可验证 S 级） |
| #582（氛围层） | ⏳ research PRD 已合 | Low | 分层共存（氛围常驻 vs 反馈瞬态）；#582 落地后视觉叠加验证 |
| #583（战斗场景） | ⏳ backlog | Med | Camera2D 实例归属；本 PRD 用 @export camera_path 解耦 + E2E rig 自带 Camera2D |
| #584（数值面板） | ✅ merged #609 | 无 | FEEDBACK_ 常量同样走 # DRAFT 通道；DebugCanvas 扩展可选 |
| #585（组装） | ⏳ backlog | 无 | 消费本层：实例化 ReactionController + 接 Camera2D + 接 #577 事件 |
| #593（音效系统） | ⏳ backlog | Low | 音效 hook 预留（§8.3 audio_hook），本 issue 不发声 |

### 6.2 开源调研结果（issue 🔍 段要求——PR 必须说明）

GitHub API 检索（2026-08-19）：

| 检索词 | 结果 | 结论 |
|--------|------|------|
| godot hitstop / hit-stop | 0 个成熟仓库 | 无直接可复用方案；hit-stop 在 Godot 社区通常以 Engine.time_scale 手写实现 |
| godot time_scale | `zekostudio/godot-timeflow` ⭐21（自定义时钟路由） | 功能强但引入第三方时钟系统；MVP 只需一层栈，自研 40 行足够（#572 不引 addon 红线） |
| godot camera shake 2d | `filipbasara/trauma-gd` ⭐4（trauma 模型 2D 屏震） | **trauma 模型采纳**（offset 噪声 + trauma² 衰减），实现自研不引插件 |
| godot impact spark / parry | 0 个成熟仓库（parry 相关均 0-2⭐ 个人习作） | 无成熟火花方案；GPUParticles2D burst 为 Godot 原生标准做法 |

**结论：** 无成熟 addon 可直接复用（hit-stop/spark 无成熟仓库；timeflow/trauma-gd 与 #572「不引第三方 addon」裁决冲突或功能过剩）。**采纳 trauma 屏震模型思想 + Godot 原生 GPUParticles2D/Engine.time_scale/Camera2D，全部自研**（与 #575 自研状态机同哲学：地基自研，模型借鉴）。

### 6.3 依赖链图

```
#574 动画+SwordArc ──┐
                     ├──► #579 打击反馈（本 issue）──► #585 组装闭环
#575 CombatEntity ───┘        │
                              ├──（增强输入，非阻塞）── #577 判定
                              ├──（S 级触发）────────── #580 处决
                              └──（Camera2D 归属）──── #583 战斗场景
```

---

## 7. Spike / 实验（deep 深度必填，≥3 实验）

### 实验 1：时间缩放栈嵌套恢复（AC4 决定性实验）

- **问题**：hit-stop（0.05x 150ms）与慢动作（0.3x 200ms / 0.5x 300ms）嵌套 push/pop 后，Engine.time_scale 能否逐层正确恢复且无卡死？
- **方法**：headless 单测 time_scale_stack.gd：① 单层 push→pop；② 两层嵌套（hit-stop push → 慢动作 push → pop → pop）断言中间值与终值；③ 漏 pop 模拟：push 后不 pop，推进墙钟超 deadline，断言强制恢复 1.0。另跑真实帧循环：Engine.time_scale 赋值后在 _process 观察 delta 恢复。
- **预期结果**：栈语义 + 墙钟兜底下，三种路径终值均 = 1.0；嵌套中间值 = 栈顶缩放；无卡死。
- **影响**：确认 §4.3 方案 A 成立；若失败则回退「事件互斥」（同帧只允许一个时间缩放，S 级优先）。

### 实验 2：屏震衰减曲线与方向（AC5 视觉手感）

- **问题**：trauma² 指数衰减 vs 线性衰减，哪个在 3px/4px 幅值下更有『刀锋入肉』的顿挫感且不晕？
- **方法**：E2E rig 注入 S/C 两级屏震，各衰减曲线截 3 帧（t=0/中/末），对比 offset 位移量；用户/审查肉眼裁决 + 数值断言（offset 单调衰减、终值 0）。
- **预期结果**：trauma²（指数）衰减更符合只狼顿挫手感；C 级 2px 沿攻击方向可感知。
- **影响**：确认 §4.4 方案 A 衰减曲线参数（# DRAFT）。

### 实验 3：GPUParticles2D one_shot burst 时序（AC3 碰撞点）

- **问题**：one_shot + restart() 触发序列能否在注入帧内可靠爆发，且粒子位置 == 注入的世界坐标（刀交点）？
- **方法**：headless 单测：new feedback_spark → 注入 position/direction/level → 断言 emitting==true、position==注入值、粒子数 ∈ 等级区间；E2E 截图验证粒子出现在刀交点而非角色中心（AC3）。
- **预期结果**：burst 时序稳定；位置精确；粒子数 6-20 按等级。
- **影响**：确认 §4.2 方案 A；若 one_shot 时序不稳则改用 CPUParticles2D（方案 B 备选）。

### 实验 4：E2E 同帧截图 rig（AC2/AC6 决定性实验）

- **问题**：『弹反成功四要素同步』如何被 E2E 截图捕获到同一帧（火花 16-20 粒 + hit-stop + 屏震 3px + 敌人白闪）？
- **方法**：新建 e2e_feedback_capture.tscn（CaptureRig 变体）：自带 Camera2D + ReactionController + 两个火柴人（攻/防）；rig 暴露 `inject_feedback(event)`（供 shot plan autoplay.tweaks 调用或 digit 键映射）；shot plan 增加 parry_success/stance_break/execute 三档（settle_frames 覆盖效果窗口）；**兜底「冻结效果帧」模式**：注入后暂停时间栈（hit-stop 保持 0.05x 且墙钟不推进），让火花/白闪停留画面供截图。
- **预期结果**：三档截图可捕获：A 级四要素同帧（火花亮斑 + 顿帧时间标签 + 屏震 offset 非零 + 敌人白闪亮）；S 级刀光 + 血粒子 + 特写慢动作；A- 全屏淡白闪。
- **影响**：确认 §3.1 E2E 文件清单 + §5.1 AC2/AC6 验证通道；产出截图供用户裁决（AC6 定稿输入）。

---

## 8. 交接上下文（给 plan agent）

### 8.1 系统状态（交接时点）

- shandong-wolf 战斗事件信号源全部就绪：CombatEntity 6 信号（#618）、11 态状态机（#618）、CombatJudge 五结果事件（#626）、SwordArc 刀光（#612）、constants # DRAFT 全量（#609）。
- 反馈层零存在；Camera2D 场景实例缺失（E2E rig 自带 + #583 战斗场景挂载）。
- #580（处决）/ #583（战斗场景）/ #585（组装）/ #593（音效）未实现；#582 氛围 PRD 已合未实现。

### 8.2 交付物清单（按实现顺序）

| 顺序 | 文件 | 内容 |
|:----:|------|------|
| 1 | `constants.gd`（修改） | 追加「反馈分区」FEEDBACK_ # DRAFT 常量（见 §8.3 参数包：火花粒子数/初速/寿命、hit-stop 时长、屏震幅值/衰减、慢动作系数/时长、白闪 alpha/时长、颜色 #ffd9a0 系、MAX_STACK_DEPTH=3），注释含候补值+影响+情感断言，定稿归 #584 |
| 2 | `time_scale_stack.gd`（新增） | RefCounted 栈：push(scale, duration_ms)/pop()/墙钟 deadline 强制恢复；Engine.time_scale 唯一写入口（红线：禁止散落赋值） |
| 3 | `feedback_spark.gd`（新增） | GPUParticles2D 封装：one_shot burst + position/direction/level 参数化 + z_index < 角色层 |
| 4 | `screen_shake.gd`（新增） | Camera2D offset trauma 模型：@export camera_path + shake(amplitude, direction) + 衰减曲线 |
| 5 | `flash_effect.gd`（新增） | 双通道：实体 modulate 白闪（目标 entity）+ CanvasLayer 全屏淡白闪（A- 级）；is_instance_valid 防护 |
| 6 | `reaction_controller.gd`（新增） | class_name ReactionController：矩阵表（event→等级→参数包）、订阅 CombatEntity 信号、trigger_feedback(event, data) 公开 API、组合触发（火花/时间栈/屏震/白闪/刀光）、audio_hook 预留、未知事件 no-op |
| 7 | `test_reaction_controller.gd`（新增） | 矩阵单调性（AC5）/时间栈三路径（AC4）/火花位置与 z_index（AC3）/屏震衰减（实验 2）/白闪参数 + 边界 8 例 + 失败 4 例 |
| 8 | `run_tests.gd`（修改） | 注册新套件 |
| 9 | `e2e_feedback_capture.gd/.tscn`（新增） | E2E rig：Camera2D + ReactionController + 双火柴人 + inject_feedback + 冻结效果帧模式 |
| 10 | `e2e_shots.json`（修改） | 追加反馈 shot group（parry_success/stance_break/execute 三档，settle_frames 覆盖效果窗口） |

### 8.3 接口契约（下游系统的消费面）

```gdscript
## ReactionController（class_name，extends Node）
## 事件注入唯一入口（#577 判定 / #580 处决 / 测试 / E2E rig 共用）
func trigger_feedback(event: String, data: Dictionary = {}) -> void
#   event ∈ {"parry_success", "block_held", "hit_landed", "stance_broken",
#            "clash", "execute", "player_hit", "revive", "death"}
#   data 键约定:
#     position: Vector2      # 刀与刀交点（火花碰撞点，AC3）——#577 事件无位置参数，
#                            #   由 ReactionController 从 combat_attack_window.direction
#                            #   + 实体 SwordPivot 全局位置推导（见下方 _derive_impact_point）
#     normal: Vector2        # 刀面法线（火花方向，AC3）——同上推导（facing 方向）
#     target_entity: Node    # 受击实体（敌人白闪用）——#577 事件参数 defender 直传
#     attacker_entity: Node  # 攻击方（方向兜底用）——#577 事件参数 attacker 直传
#     source: String         # 来源标记（"combat_entity" | "judgment" | "test"）

## 绑定 #577 判定器（#626 已实现；组装层 #585 调用）——五结果事件直连矩阵
func bind_judge(judge: Node) -> void
#   内部: judge.parry_success.connect(...) / block_held / hit_landed / clash / stance_broken
#   → 每个 handler 转 trigger_feedback(event, {target_entity, attacker_entity, source: "judgment"})

## 信号（#593 音效系统消费，音效接口预留）
signal feedback_played(event: String, level: String, data: Dictionary)
#   level ∈ {"S", "A", "A-", "B", "C"}

## CombatEntity 信号订阅（#575 已存在，无需改实体）
#   state_changed(from, to)      → guard 进入=B；parry_success 进入=A；stagger 进入=C(玩家受击)
#   stance_broken(entity)        → A-（全屏淡白闪 + 敌人持续白闪）
#   died(entity, final)          → C(玩家受击)（不触发慢动作）
#   revived(entity)              → 复活演出反馈（轻量，参数 # DRAFT）

## 火花碰撞点推导（AC3 结构保证：刀与刀交点，非角色中心）
#   _derive_impact_point(attacker, defender, attack_window_direction) -> Dictionary{position, normal}
#   实现: attacker.get_pivot("SwordPivot").global_position 与 defender 同名 pivot 取中点
#         → position；normal = attack_window_direction 的法线旋转（±90° 按 facing）；
#         推导失败（无 pivot）→ 回退 attacker.global_position + facing 方向，push_warning

## TimeScaleStack（RefCounted）
func push(scale: float, duration_ms: int) -> void   # Engine.time_scale = 栈顶语义
func pop() -> void                                   # 恢复上一层；墙钟到期强制恢复
const MAX_STACK_DEPTH: int = 3                       # 超限丢弃新 push（§5.2-1）

## 效果组件参数包（constants.gd # DRAFT，FEEDBACK_ 前缀全量集中）
# FEEDBACK_SPARK_COUNT:     {S: 14, A: 18, B: 6, C: 8}         # 粒子数（A 16-20 取 18）
# FEEDBACK_HITSTOP_MS:      {S: 150, A: 90, A_: 100, B: 30, C: 50, PH: 60}
# FEEDBACK_SHAKE_PX:        {S: 4.0, A: 3.0, A_: 3.0, B: 1.0, C: 2.0, PH: 4.0}
# FEEDBACK_SLOWMO:          {S: {scale: 0.05, ms: 500}, A: {scale: 0.3, ms: 200}, A_: {scale: 0.5, ms: 300}}
# FEEDBACK_FLASH:           {A: {alpha: 0.35, ms: 120}, A_: {alpha: 0.25, ms: 100}}
# FEEDBACK_SPARK_COLOR:     Color("#ffd9a0")  # 苍白金（禁橙色）
# FEEDBACK_TIME_MAX_STACK:  3
```

### 8.4 主要风险与裁决点

1. **#577 事件契约对齐**（已缓解）：#577 已 merged（#626），五结果事件（parry_success/block_held/hit_landed/clash/stance_broken）与 §8.3 事件名完全一致（issue body 同源契约）；差异点仅在**事件无位置参数**——本 PRD 已定义 _derive_impact_point 推导（§8.3），无需改 #577。组装层 #585 调用 bind_judge() 完成连接。
2. **Camera2D 归属**：#583 战斗场景落地前，反馈层在 E2E rig 自带 Camera2D 下验证；#585 组装时接战斗场景相机（@export camera_path 已解耦）。
3. **hit-stop 用 0.05 而非 0**：Engine.time_scale=0 冻结全部处理（含墙钟兜底轮询），用极小值 0.05 保留恢复通道（实验 1 验证）。
4. **粒子层级**：z_index 硬约束（火花 < 角色）写进单测，防粒子盖角色（issue 红线）。
5. **处决 S 级慢动作 0.05x 与 hit-stop 150ms 的叠加**：时间栈两层嵌套（S 级 hit-stop 先 push、慢动作后 push、逐层 pop），实验 1 覆盖。

### 8.5 红线（implement agent 禁止）

- ❌ 不修改 combat_entity.gd / combat_states.gd / combat_state_table.gd（#575 契约红线）
- ❌ 不修改 sword_arc.gd（复用 trigger_burst，不改实现）
- ❌ 不修改 scenes/Main.tscn（标题场景红线）
- ❌ 不引入第三方 addon（#572 裁决；timeflow/trauma-gd 只借鉴模型不自研即不引）
- ❌ 不裁决任何 # DRAFT 数值（新增 FEEDBACK_ 常量同样 # DRAFT + 候补值；定稿归 #584/用户）
- ❌ 不做判定/处决逻辑（#577/#580 职责）；不做音效发声（#593 职责，只留 hook）
- ❌ Engine.time_scale 只经 TimeScaleStack 写入（禁止散落赋值——AC4 卡死红线）
- ❌ 不修改 mini-pong/ 任何文件（游戏隔离红线）
- ❌ 全屏闪白仅限 A- 级 100ms 低 alpha（禁止滥用 = AC5/AC6 页游感红线）
