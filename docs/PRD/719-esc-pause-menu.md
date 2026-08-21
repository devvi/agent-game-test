# PRD #719 — [Feature] ESC 暂停菜单 + 游戏操作手册（移动/攻击/格挡/闪避/处决说明）

> **Issue:** #719
> **标签:** workflow/research, priority/high, feature, ui, version/mvp（issue 无 `depth/*` 标签，参照 #684 先例取 `depth: standard` → §1–6 + §8 必填；§7 含 2 实验提升交接质量）
> **Agent:** game-research-agent
> **日期:** 2026-08-21
> **所有权:** `content_ownership: mechanical`（暂停状态机/ESC 边沿检测/菜单结构与按钮接线/操作手册自动生成自 InputMap = 机械工程；菜单标题文案、手册措辞、遮罩色值与透明度候选 = taste 通道，全部标 `# DRAFT` 只读，定稿归 human-review 通道）
> **引擎/目录约束:** Godot 4.7.1 / `shandong-wolf/`（manifest `game.active: shandong-wolf` + `default_branch: main` 单一事实源；本 PRD 全部路径前缀 `shandong-wolf/`，零 `mini-pong/` 写死）
> **研究选项:** Obsidian 知识库（`/Volumes/Obsidian/Knowledge Ocean/wiki/`）→ `wiki/游戏设计理念.md` §UI 与交互设计（UI 互动是发力点、「乏味的点点点游戏」变「可把玩的游戏」，引自 `raw/Bear/关于游戏UI的思考.md`）、`wiki/体验引擎-patterns.md` §1 隐形界面（最小化 HUD——「如果界面被注意到，它就失败了」，#576 同源引用；暂停菜单属"短暂离场型 UI"，克制即正义）+ 全库 grep（暂停/ESC/操作手册/键位 关键词）**无直接沉淀**——本功能无审美先例，走机械实现 + taste 候选通道；另读同链 PRD/DESIGN（#573/#576/#580/#585/#684）+ origin/main 源码实测（444e71d，InputMap/InputController/Hud/MainBattle 逐文件核对）
> **来源:** 用户实机体验需求（2026-08-21）：MVP 完成后的收尾体验项
> **前置依赖:** #573（CLOSED，InputController 输入意图层）、#576（草稿 merged，`status/human-review`——v4 规则：human Issue 不进依赖链，视为已满足）、#580（CLOSED，处决系统——手册「处决」条目文案来源）、#585（CLOSED，MVP 装配 13 步——暂停菜单挂接点）、#684（CLOSED，HUD 增量——菜单复用 CanvasLayer + HUD 色板模式）——全部满足，无阻塞

---

## 1. 问题定义

### 1.1 现状（2026-08-21 worktree 侦查 @ origin/main 444e71d）

**一句话现状：** shandong-wolf 目前**没有任何暂停机制**——`get_tree().paused` 全仓库零引用、无 `process_mode` 显式设置（所有节点走 INHERIT 默认）、无 ESC 输入动作、无菜单 UI。MVP 战斗闭环（#585 装配 17 组件）已就绪，玩家一旦进入战斗无法中断/查阅操作说明，实机体验缺口明确。

**输入层现状（#573 InputController，autoload，`_process` 轮询边沿）：**

| 动作（InputMap 实际绑定，勿编造） | 物理键 | 键名 | 信号 |
|------|--------|------|------|
| `game_move_left` | 65 + 4194319 | **A / ←** | 轴（get_move_axis） |
| `game_move_right` | 68 + 4194321 | **D / →** | 轴 |
| `game_light_attack` | 74 + 鼠标左键 | **J / 左键** | `attack_pressed` |
| `game_heavy_attack` | 75 + 鼠标右键 | **K / 右键** | `heavy_attack_pressed` |
| `game_guard` | 76 | **L**（按住=格挡，时机=弹反） | `guard_pressed(ts)` / `guard_held` |
| `game_dash` | 4194325 | **Shift**（轻按=垫步，按住≥200ms=冲刺） | `dash_pressed` |
| `game_jump` | 32 | **空格** | `jump_pressed` |
| `game_interact` | 69 | **E** | `interact_pressed` |
| `game_revive` | 70 | **F**（#578 二命复活） | `revive_pressed` |

**⚠️ 侦查发现（手册必须规避的既有错误）：** `constants.gd` L749 教学提示候选文案 `TUTORIAL_HINT_CANDIDATES[1] = "←→ 移动 · J 攻击 · K 格挡"` 与 InputMap **矛盾**——`K` 实际是重攻击（`game_heavy_attack`），格挡是 `L`（`game_guard`）。本 PRD 的操作手册**以 InputMap 为唯一事实源自动生成**（§4 方案 A），天然规避此矛盾；教学提示文案修正属 taste 通道（`# DRAFT` 只读），仅 flag 不进本 PRD 范围。

**可复用基建：**
- HUD 体系（#576/#684）：`Hud` 为纯代码 CanvasLayer（layer=1），`_HudBar` 自绘，色板 `HUD_MOON_WHITE #e8e6e3` / `HUD_INK_BLACK #141414` / `HUD_BLOOD_RED #8c2f2f`，零贴图零 tscn——菜单沿用同构
- 装配锚点（#585）：`main_battle.gd` 13 步同步装配（`_build_hud()` 先例：`HudLayer`(CanvasLayer) → `Hud`），暂停菜单在第 ⑮ 步同构挂接
- Main.tscn 现有 `CanvasLayer/CenterContainer` 标题卡（`_setup_tutorial_hint()` 首帧隐藏）——菜单不与标题卡复用，独立新层

### 1.2 验收条件（issue body 4 条 → 本 PRD 保障）

| # | 验收条件 | 现状 | 本 PRD 保障 |
|---|---------|:----:|------------|
| AC1 | 游戏进行中 ESC → 暂停 + 菜单弹出（游戏画面冻结） | ❌ 无暂停机制 | §5.1 AC1：`get_tree().paused` 全局冻结 + 菜单 CanvasLayer `PROCESS_MODE_ALWAYS` 弹出 |
| AC2 | 选「继续」或再按 ESC → 恢复游戏 | ❌ 无 | §5.1 AC2：按钮 + ESC 双路径恢复，边沿检测幂等 |
| AC3 | 操作手册显示正确按键（与 InputMap 一致） | ❌ 无手册 | §5.1 AC3：手册条目**运行时从 InputMap 生成**（keycode→键名），结构测试断言一致性 |
| AC4 | 暂停期间敌人/粒子/动画全部冻结，菜单可交互 | ❌ 无 | §5.1 AC4：树暂停覆盖 INHERIT 全部节点（含 Atmosphere 粒子、Tween/Timer），菜单 ALWAYS 保持响应 |

### 1.3 用户场景

| # | 场景 | 频率 | 描述 |
|---|------|------|------|
| A | 战斗中途查键位 | 每次游玩 | 玩家与雪夜刀客接战，忘了弹反键 → 按 ESC → 画面冻结 → 菜单弹出 → 点「操作手册」→ 看到「格挡/弹反：L」→ 再按 ESC 回到战斗，操作不丢帧 |
| B | 临时离席/喘息 | 每次游玩 | 战斗紧张时按 ESC 暂停，画面全冻结（雪/粒子/敌人动作静止），菜单可点「继续」无缝恢复 |
| C | 失败终态防误触 | 边缘 | FAIL 字幕出现后按 ESC：暂停被守卫拦截（终态不弹菜单），不打断失败演出 |

---

## 2. 设计意图

### 2.1 为什么现状如此

| Issue | 贡献 | 为何没做暂停 |
|-------|------|------------|
| #573 | InputController 输入意图层 | 只做战斗意图（attack/guard/dash/jump/interact/revive），ESC 属系统级输入，不在战斗意图范围 |
| #576/#684 | HUD CanvasLayer 体系 | 只做信息展示（血条/架势条/提示），无交互控件先例 |
| #585 | MVP 装配 13 步 | 目标是战斗闭环跑通，暂停是"体验收尾项"（issue 上下文原文） |

### 2.2 为什么现在做

用户实机体验后明确要求（issue 上下文：「MVP 完成后的收尾体验项」）。MVP 战斗闭环（#585）与输入层（#573）均已 CLOSED，暂停菜单是**纯增量**——零组件改动红线内新增一个消费方 + 一个输入动作，风险面可控。

### 2.3 前置约束

| 约束 | 详情 |
|------|------|
| InputController 红线 | 「不接触战斗逻辑/动画/场景状态；消费方独立监听」——暂停菜单作为新消费方监听，不改其判定 |
| 零贴图零 tscn 惯例 | HUD 纯代码创建；菜单沿用（`ColorRect` + `Label` + `Button` 程序化创建） |
| 色板单一来源 | 复用 `HUD_*` 常量，不新增色相（#576 色板收敛） |
| `# DRAFT` 只读 | 菜单文案/色值/时长候选标 `# DRAFT`，实现期禁止裁决 |
| FAIL 终态语义 | `main_battle.gd` FAIL 为终态（`_set_game_state` 守卫），暂停不得打断失败演出 |

---

## 3. 影响分析

### 3.1 直接受影响模块

| 文件（`shandong-wolf/`） | 模块 | 改动性质 |
|------|------|---------|
| `project.godot` | InputMap | **新增** `game_pause` 动作（ESC 物理键 4194305）；不动既有 `game_*` |
| `gdscripts/pause_menu.gd` | 新组件 | **新建**：CanvasLayer（layer=2，PROCESS_MODE_ALWAYS）暂停菜单 + 操作手册面板 |
| `gdscripts/main_battle.gd` | 装配层 | **修改**：第 ⑮ 步实例化 PauseMenu + 注入 FAIL 守卫（`game_state` 只读接口）；零组件改动 |
| `gdscripts/constants.gd` | 常量 | **修改**：新增 `PAUSE_*` 常量（菜单标题候选/遮罩色值/透明度/字体尺寸，全部 `# DRAFT`） |
| `gdscripts/input_controller.gd` | 输入意图层 | **可选（方案 A2 零改动）**：不新增信号——ESC 由 PauseMenu 自检（`_unhandled_key_input` + `game_pause`） |

### 3.2 新建文件

| 文件 | 职责 |
|------|------|
| `gdscripts/pause_menu.gd` | 暂停状态机（toggle）+ 菜单 UI（遮罩/标题/按钮/手册面板）+ ESC 自检 + InputMap→手册文本生成 |
| `tests/test_pause_menu.gd` | 暂停切换/ESC 边沿/冻结语义/FAIL 守卫/手册一致性 用例（静态契约：零贴图 + 手册文本与 InputMap 运行时一致） |

### 3.3 间接受影响的模块

| 模块 | 影响 |
|------|------|
| HUD（#576/#684） | 暂停时 INHERIT 冻结，信号源（CombatEntity）也冻结 → 无更新，恢复后自动续画，零改动 |
| Atmosphere 粒子（雪幕） | 树暂停冻结粒子发射/动画（GPUParticles3D 默认 INHERIT）——§7 实验 2 验证 |
| #579 TimeScaleStack / Reaction 慢动作 | `Engine.time_scale` 与 `get_tree().paused` 独立；暂停不触碰 time_scale，恢复后慢动作续跑——§5.3 边界 7 处理 |
| 输入缓冲（#573 INPUT_BUFFER_WINDOW_MS=150） | 暂停前缓冲的攻击意图可能在恢复瞬间爆发——§5.3 边界 3：暂停时清缓冲 |

### 3.4 数据流（ASCII）

```
物理 ESC 键
    │  Input.is_action_just_pressed("game_pause")（PauseMenu._process，PROCESS_MODE_ALWAYS 常驻）
    ▼
PauseMenu.toggle_pause()
    ├── get_tree().paused = true ──► 全部 INHERIT 节点冻结（战斗 _process/_physics_process/Tween/Timer/粒子/HUD 信号链）
    ├── 菜单可见（本节点 ALWAYS 保持响应）
    │     ├── 「继续」Button.pressed ──► get_tree().paused = false + 菜单隐藏 + 缓冲已清
    │     ├── 「操作手册」Button.pressed ──► 手册面板 visible 翻转（条目文本运行时读 InputMap）
    │     └── ESC（再次）────────────► toggle_pause() 同路径恢复
    └── FAIL 守卫: game_state == FAIL → 忽略 ESC（不弹菜单，幂等）
```

### 3.5 需更新的文档

- [x] `docs/PRD/719-esc-pause-menu.md`（本 PRD）
- [ ] `docs/DESIGN/719-esc-pause-menu.md`（plan agent 产出）
- [ ] `docs/GAME_DESIGN/shandong-wolf/`（post-merge agent 更新——本 PRD 不在其范围）
- [ ] `shandong-wolf/tests/` 新增 `test_pause_menu.gd` 注册（如测试按目录自动发现则免注册）

---

## 4. 方案对比

### Approach A — 树暂停 + 独立菜单层（推荐）

**描述：** `get_tree().paused = true` 全局冻结 + 新建 `pause_menu.gd`（CanvasLayer layer=2，`process_mode = PROCESS_MODE_ALWAYS`）承载菜单与手册。ESC 检测二选一：
- **A1（issue 建议）**：InputController 加 `game_pause` 动作 + `pause_pressed` 信号 + 自身 `PROCESS_MODE_ALWAYS`——**缺陷：InputController 常驻后暂停期间仍轮询边沿，会继续发战斗信号（attack/guard…）→ 暂停中误触发处决/攻击，必须加"暂停抑制开关"**
- **A2（推荐）**：PauseMenu 自检 ESC（`_process` 轮询 `Input.is_action_just_pressed("game_pause")`），InputController **保持 INHERIT**——暂停即自然冻结，战斗信号零泄漏，InputController 零改动（守其红线）

**Pros：** Godot 标准语义，冻结面完整（物理/动画/Tween/Timer/粒子一次覆盖）；AC4 天然满足；菜单 ALWAYS 独立可交互；InputController 零改动（A2）
**Cons：** 全局暂停是"粗粒度"——任何节点若设了 ALWAYS 会漏冻结（当前代码无此设置，零风险）；手册文本需生成逻辑
**Risk：** Low（A2 无输入泄漏路径）
**Effort：** 0.5–1 周

### Approach B — 局部冻结（MainBattle 状态机扩展）

**描述：** 不动 `get_tree().paused`，在 `main_battle.gd` 加 PAUSED 状态，逐个停战斗节点（`set_physics_process(false)` + Tween.pause() + 粒子 emiss 停）。

**Pros：** 精确控制冻结面，可选择性保留演出
**Cons：** 冻结面靠人肉枚举——粒子（Atmosphere）、Tween（Reaction 慢动作/血条动画）、Timer（余韵/失败字幕）各有独立生命周期，**漏一个就违反 AC4**；恢复路径每类都要对称处理；状态机与 #585 的 IDLE/COMBAT/KILL/AFTERGLOW/FAIL 纠缠，侵入装配层红线
**Risk：** High（AC4 全覆盖难证明）
**Effort：** 1–2 周

### Approach C — `Engine.time_scale = 0` + 菜单

**描述：** 用 time_scale 归零"冻结"游戏世界，菜单照常渲染。

**Pros：** 一行冻结
**Cons：** `time_scale=0` 只把 delta 归零，`_process` **仍每帧被调用**（InputController 继续发信号、MainBattle 轮询继续跑）；与 #579 TimeScaleStack 慢动作（`time_scale` 持有者）直接冲突——暂停/恢复会踩慢动作栈；语义不是"暂停"是"时间停止"，恢复时序混乱
**Risk：** High（与 TimeScaleStack 互踩）
**Effort：** 0.5–1 周（但后患大）

### 推荐（Approach A2）

1. **A2 是唯一同时满足 AC1–AC4 且零输入泄漏的方案**——树暂停语义标准、冻结面完整，PauseMenu 自检 ESC 使 InputController 保持 INHERIT（暂停中自然停发战斗信号），守 #573 红线
2. **菜单作为第 ⑮ 步装配**，与 #585 的 13 步同构（HudLayer 先例），零组件改动，additive 增量
3. **操作手册运行时从 InputMap 生成**（遍历 `game_*` 动作的 `InputEventKey.physical_keycode` → 键名），结构测试断言文本与 InputMap 一致——AC3 从"人工核对"升级为"机器保证"，并规避 §1.1 发现的 `TUTORIAL_HINT_CANDIDATES` 矛盾
4. 手册文本由 `# DRAFT` 候选 + InputMap 键名拼接，taste 通道只定措辞不动键位事实

---

## 5. 边界条件与验收标准

### 5.1 正常路径（AC 清单）

- [x] **AC1: 游戏进行中 ESC → 暂停 + 菜单弹出（画面冻结）**
  - `game_pause` 动作按下边沿 → `get_tree().paused = true`
  - 菜单 CanvasLayer（ALWAYS）可见：半透明遮罩 ColorRect 全屏 + 标题 + 按钮
  - 冻结验证：玩家/敌人 `_process` 停、雪幕粒子停、Tween/Timer 停（§7 实验 2 佐证）
- [x] **AC2: 选「继续」或再按 ESC → 恢复游戏**
  - 「继续」`Button.pressed` → `get_tree().paused = false` + 菜单隐藏
  - ESC 再次按下 → 同 toggle 路径恢复（边沿检测，按住不重复触发）
  - 恢复后输入缓冲已清（§5.3 边界 3），不吞键不爆键
- [x] **AC3: 操作手册显示正确按键（与 InputMap 一致）**
  - 「操作手册」按钮 → 手册面板可见：条目 = 动作名 × InputMap 键名（运行时生成）
  - 覆盖全部 `game_*` 动作：移动 A/D←/→ · 轻攻击 J/左键 · 重攻击 K/右键 · 格挡 L · 闪避 Shift · 跳跃 空格 · 处决（崩解后按攻击键，#580）· 互动 E · 复活 F（#578）
  - 测试断言：`test_pause_menu.gd` 遍历手册条目 vs `InputMap.action_get_events()` 键名逐一相等
- [x] **AC4: 暂停期间敌人/粒子/动画全部冻结，菜单可交互**
  - 冻结：树暂停覆盖 INHERIT（全节点默认）；菜单 ALWAYS 可点按钮、可翻手册
  - 菜单交互不泄漏到游戏：暂停中 `attack_pressed` 等战斗信号**零发射**（InputController INHERIT 冻结，A2 语义保证）

### 5.2 边界情况（≥5）

1. **暂停中连按 ESC**：边沿检测 + 状态幂等——已暂停再按 = 恢复；恢复后 1 帧内再按 = 再暂停（正常 toggle，不抖动）
2. **FAIL 终态按 ESC**：`game_state == FAIL` 守卫拦截，不弹菜单（终态演出不被中断；`InputController.set_process(false)` 已冻结输入，双保险）
3. **暂停前输入缓冲未清**：暂停瞬间 `InputController` 清空缓冲队列（`poll_buffer` 残余攻击意图），防恢复瞬间"隔空出刀"
4. **冲刺按住中暂停**：`_sprinting` 状态随暂停冻结；恢复后若 Shift 已松开，`_was_pressed` 下一帧自愈（`_update_dash_hold` 轮询），无粘滞
5. **慢动作（#579 time_scale≠1）中暂停**：暂停只动 `get_tree().paused`，不触碰 `Engine.time_scale`；恢复后慢动作续跑（TimeScaleStack 独立持有者不变）——§7 实验 1 验证
6. **处决特写（#580）中暂停**：执行演出为 Tween/Timer 驱动，树暂停即冻结；恢复后续跑（执行判定在 CombatJudge 信号链，暂停中零输入无新判定）；可接受，不特判
7. **窗口失焦自动暂停**：**超出范围**（deferred，非 issue 验收项），仅记录
8. **手册面板开着时再按 ESC**：先关手册再恢复（两级菜单语义），或 ESC 直接恢复并关手册——取后者（ESC=恢复优先，手册用按钮关闭），`# DRAFT` 语义待用户定稿

### 5.3 失败路径（≥3）

1. **`game_pause` 动作缺失（InputMap 未注册）**：PauseMenu `_ready` 校验 `InputMap.has_action("game_pause")`，缺失则 `push_error` + 菜单禁用（fail-safe：游戏照常运行，不崩溃）
2. **菜单节点创建失败/重复实例**：加入 `hud` 同款 group 去重守卫（`add_to_group("pause_menu")` + 首实例保留），装配重入幂等
3. **暂停恢复后节点处理未对称**：恢复路径唯一入口 `toggle_pause(false)`，禁止散点 `paused=false` 直写（测试断言恢复后 `get_tree().paused == false` 且战斗节点 `is_processing()` 为真）

---

## 6. 依赖与阻塞

### 6.1 依赖

| 依赖 | 状态 | 风险 |
|------|:----:|:----:|
| #573 InputController（输入意图层） | CLOSED | Low——A2 零改动，仅消费其"暂停即冻结"语义 |
| #576 HUD（CanvasLayer 体系 + 色板） | 草稿 merged（human-review） | Low——色板复用，v4 规则视为已满足 |
| #580 处决系统（手册「处决」条目） | CLOSED | Low——仅文案引用（「崩解后按攻击键」） |
| #585 MVP 装配（第 ⑮ 步挂接点） | CLOSED | Low——additive 装配，零组件改动 |
| #684 HUD 增量（菜单样式同构） | CLOSED | Low——程序化 UI 模式先例 |
| #578 二命复活（手册「复活 F」条目） | CLOSED | Low——仅文案引用 |

### 6.2 阻塞（下游）

| 未来工作 | 优先级 |
|---------|:----:|
| 返回标题/退出游戏（issue 可选 ③，需标题场景/场景切换基建，#156 ExitZone 不适用） | 低（deferred，不阻塞本 PRD） |
| 暂停时窗口失焦自动暂停 | 低（deferred） |
| 教学提示文案修正（`TUTORIAL_HINT_CANDIDATES[1]` K/L 矛盾） | 中（taste 通道，本 PRD 仅 flag） |

### 6.3 依赖链

```
#573 InputController（输入意图层，CLOSED）──┐
#575/#576 CombatEntity + HUD（CLOSED/human）┤
#580 处决系统（CLOSED）────────────────────┼─► #585 MVP 装配 13 步（CLOSED）──► #719 ESC 暂停菜单（本 PRD）
#684 HUD 增量（CLOSED）───────────────────┘        （菜单 = 第 ⑮ 步挂接）
```

无未满足依赖，无阻塞。

---

## 7. Spike / 实验

> 按 `depth: standard` 本节省略；但参照 #684 先例含 2 实验提升交接质量（不阻塞实现，实验 2 建议 plan 期先跑）。

### 实验 1：暂停与 `Engine.time_scale` 交互（#579 慢动作共存）

- **问题：** 慢动作（time_scale≠1，Reaction 触发）中暂停再恢复，time_scale 是否保持、慢动作是否续跑？
- **方法：** 构造 `Engine.time_scale=0.3` + `get_tree().paused=true` → 恢复 → 断言 time_scale 仍 0.3、Tween 进度续跑
- **预期结果：** 两者独立（`get_tree().paused` 不影响 time_scale 读写），恢复后无缝续跑
- **对方案影响：** 若互踩 → Approach A 加"暂停时快照/恢复 time_scale"步骤（影响小，方案不变）

### 实验 2：树暂停对 GPUParticles3D（雪幕）与 Tween 的冻结覆盖

- **问题：** AC4「粒子/动画全部冻结」——Atmosphere 雪幕（GPUParticles3D）与 HUD 血条 Tween 在 `paused=true` 下是否确停？
- **方法：** headless 场景置 paused，采样粒子 `emitting`/`particle_count` 与 Tween `is_running()`，对比暂停前后
- **预期结果：** INHERIT 默认全冻结；若有节点显式 ALWAYS（当前源码 grep 无）则漏冻结
- **对方案影响：** 若漏冻结 → 该节点改 INHERIT 或暂停时显式停；方案 A 结构不变

---

## 8. 交接上下文（plan agent）

### 8.1 系统状态

- `game.active: shandong-wolf`，Godot 4.7.1，`default_branch: main`（manifest 单一事实源）
- 输入层：#573 InputController（autoload，`_process` 边沿轮询，INHERIT 默认）——**A2 语义下暂停即自然冻结，零改动**
- 装配层：#585 main_battle.gd 13 步同步装配，第 ⑮ 步新增 PauseMenu 挂接（`_build_hud()` 同构：`PauseLayer`(CanvasLayer) → PauseMenu）
- UI 惯例：纯代码 CanvasLayer + `HUD_*` 色板 + 零贴图 + `# DRAFT` 只读
- ⚠️ 已知矛盾：`TUTORIAL_HINT_CANDIDATES[1]`（K=格挡）与 InputMap（K=重攻击/L=格挡）不符——手册以 InputMap 自动生成为准，不手抄

### 8.2 接口契约（实现红线）

| 接口 | 签名 | 语义 |
|------|------|------|
| `project.godot` InputMap | 新增 `game_pause` = ESC（物理键 4194305） | 唯一新增动作；既有 `game_*` 不动 |
| `PauseMenu.toggle_pause()` | 新 | 唯一暂停/恢复入口（`get_tree().paused` 读写）；FAIL 守卫在内 |
| `PauseMenu._process` | 新 | `Input.is_action_just_pressed("game_pause")` 边沿自检（ALWAYS 常驻） |
| `PauseMenu.manual_text()` | 新 | 遍历 `InputMap` 全部 `game_*` 动作 → `[动作, 键名]` 行数组（AC3 机器保证） |
| `PauseMenu.bind_game_state(getter)` | 新 | 注入 `main_battle.gd` 的 `game_state` 只读接口（FAIL 守卫） |
| `main_battle.gd` 装配 | 修改 | 第 ⑮ 步：`PauseLayer`(CanvasLayer, layer=2, ALWAYS) → `PauseMenu` + bind_game_state |
| `constants.gd` | 修改 | `PAUSE_*` 常量（标题候选/遮罩色值/透明度/手册措辞候选，全 `# DRAFT`） |
| `InputController` | **零改动** | A2 红线：不新增信号、不改 process_mode |

### 8.3 测试与 E2E 计划

- `tests/test_pause_menu.gd`（新）：暂停 toggle 幂等（AC1/AC2）、ESC 边沿、FAIL 守卫、**手册文本 vs InputMap 逐行一致（AC3）**、暂停中战斗信号零发射（AC4，A2 语义断言）、缓冲清空、`game_pause` 缺失 fail-safe
- 既有测试回归：`tests/run_tests.gd` 全绿（暂停默认 off，零行为变化）
- E2E：`e2e_pause_capture.gd`（新，`e2e_hud_capture.gd` 同构）PAUSE_OPEN / MANUAL_OPEN / PAUSE_RESUME 三态；`e2e_shots.json` 追加 pause group
- 红线核对：零贴图、零 tscn、`# DRAFT` 只读、InputController 零改动、恢复路径唯一入口

### 8.4 主要风险

| 风险 | 等级 | 缓解 |
|------|:----:|------|
| 暂停中战斗信号泄漏（若误改 InputController 为 ALWAYS） | Med | A2 红线：InputController 保持 INHERIT；测试断言暂停中零信号 |
| 冻结面遗漏（粒子/Tween 显式 ALWAYS） | Low | 当前源码 grep 无 ALWAYS；§7 实验 2 plan 期先跑 |
| 菜单文案/遮罩审美分歧 | Low | `# DRAFT` 候选 + 默认值，不阻塞结构实现 |
| 并行 agent 冲突（main_battle.gd/constants.gd 共享） | Med | worktree 隔离 + additive 修改 + 提交前 merge main |

### 8.5 下一步（plan agent）

1. 读 `docs/DESIGN/585-mvp-combat-loop-assembly.md` §2.1（装配 13 步上下文）与本 PRD §4 推荐组合（A2）
2. 产出 DESIGN：pause_menu.gd 节点结构（遮罩/标题/按钮/手册面板）、constants `PAUSE_*` 候选、`game_pause` InputMap 条目、test_pause_menu 用例清单、E2E 三态清单
3. 红线核对：InputController 零改动、恢复路径唯一入口、`# DRAFT` 只读、零贴图
