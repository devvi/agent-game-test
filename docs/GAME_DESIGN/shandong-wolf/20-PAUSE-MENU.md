# 20 — ESC 暂停菜单 + 操作手册（#719）

> 章节由 game-post-merge-agent 在 implement PR #728 merge 后填充（源 PR: `feat(719)` #728，Parent #719）。
> 归属 DESIGN: `docs/DESIGN/719-esc-pause-menu.md`（方案 A2 采纳）+ PRD `docs/PRD/719-esc-pause-menu.md`。
> 一句话设计：**ESC 是系统级输入，暂停是树级状态——新增一个常驻 `PauseMenu`（CanvasLayer, ALWAYS）作为唯一暂停持有者，自检 ESC 边沿，翻转 `get_tree().paused`，并承载菜单 UI + 运行时从 InputMap 生成的操作手册。**

## 1. 设计动机（为什么这样做）

游戏进行中需要 ESC 暂停界面，显示游戏操作手册（用户 2026-08-21 需求）。在已落地的
战斗闭环（#585 MVP 组装）之上，暂停是 MVP 收尾的体验项——玩家需要能随时停下、
查看当前按键。

**核心设计哲学（对齐 PRD §4 三处关键决策）：**

1. **暂停 = 树状态而非组件状态** —— 用 Godot 标准语义 `get_tree().paused = true`，
   冻结面一次覆盖物理/动画/Tween/Timer/粒子，AC4「全部冻结」无需人肉枚举。代价是
   「任何 ALWAYS 节点会漏冻结」——2026-08-21 全仓库 grep 核验：当前源码**无任何显式
   `process_mode` 设置**（全部 INHERIT 默认），风险面为零。
2. **ESC 检测归 PauseMenu 而非 InputController（方案 A2）** —— InputController 是战斗
   意图层（#573 红线），加 ESC 会引入「暂停中仍发战斗信号」的泄漏路径（方案 A1 缺陷）。
   PauseMenu 自检则 InputController 保持 INHERIT，暂停即自然停发，零泄漏、零改动。
   - 否决的方案：A1（InputController 加 `pause_pressed` 信号 + 自身 ALWAYS，暂停中仍
     轮询边沿 → 战斗信号泄漏，需暂停抑制开关）；B（局部冻结，冻结面人肉枚举，AC4 难
     证明）；C（`Engine.time_scale=0`，与 #579 TimeScaleStack 互踩，`_process` 仍每帧调用）。
3. **手册文本运行时从 InputMap 生成** —— AC3 从「人工核对」升级为「机器保证」，并天然
   规避既有 `TUTORIAL_HINT_CANDIDATES[1]`（"K 格挡"）与 InputMap（K=重攻击、L=格挡）的
   矛盾（PRD §1.1 侦查发现）；该教学提示文案修正属 taste 通道，仅 flag 不处理。

**所有权：** `content_ownership: mechanical`（暂停 toggle 状态机 / ESC 边沿检测 / 菜单节点
结构与按钮接线 / 手册文本 InputMap 自动生成 = 机械工程，可自动验证）；菜单标题文案、手册
措辞、遮罩色值与透明度候选 = taste 通道，全部标 `# DRAFT` 只读，定稿归 human-review 通道。

## 2. 新组件 — PauseMenu（`gdscripts/pause_menu.gd`）

- **基类:** `CanvasLayer`（`class_name PauseMenu`）——与 Hud 同构（Hud extends CanvasLayer）。
- **层级:** `layer = 2`（HUD layer=1 之上）；`process_mode = PROCESS_MODE_ALWAYS`（战斗冻结时菜单仍响应）。
- **零 tscn 零贴图**：`_ready` 代码建树（Hud 同构惯例）。

### 2.1 节点结构（_ready 代码创建）

```text
PauseMenu (CanvasLayer, layer=2, process_mode=ALWAYS)      ← 本脚本
├── DimOverlay (ColorRect, 全屏 1280×720, color=C.PAUSE_DIM_COLOR, 初始 visible=false)
├── MenuRoot (VBoxContainer, 居中 anchors, 初始 visible=false)
│   ├── TitleLabel (Label, text=C.PAUSE_TITLE_CANDIDATES[0], 字号 C.PAUSE_TITLE_FONT_SIZE)
│   ├── ResumeButton (Button, text=C.PAUSE_BTN_RESUME_TEXT)
│   ├── ManualButton (Button, text=C.PAUSE_BTN_MANUAL_TEXT)
│   └── HintLabel (Label, text=C.PAUSE_HINT_TEXT)          # 「ESC 恢复」提示，小字号
└── ManualPanel (VBoxContainer + ScrollContainer, 初始 visible=false)   # 操作手册面板
    ├── ManualTitle (Label, text=C.PAUSE_MANUAL_TITLE_TEXT)
    └── ManualLines (VBoxContainer)   # 行 = Label × N，运行时由 manual_text() 填充
```

### 2.2 关键方法（唯一入口 / 边沿检测 / 手册生成）

**唯一暂停/恢复入口（幂等 + FAIL 守卫）：** `toggle_pause()` 无参翻转——「继续」按钮与
再次 ESC 走同一函数同一分支，杜绝两处恢复代码漂移。

```gdscript
func toggle_pause() -> void:
	## FAIL 终态忽略（幂等）；其余按当前 _paused 分支翻转
	if _game_state_getter.is_valid() and int(_game_state_getter.call()) == GAME_STATE_FAIL:
		return                                    # FAIL 终态: 不弹菜单
	if _paused:
		_resume()
	else:
		_pause()
```

**ESC 边沿检测（headless 陷阱规避）：** 用 `is_action_pressed` + `_was_pause_pressed`
（同 input_controller.gd 模式），**不用 `is_action_just_pressed`** —— 后者依赖引擎处理帧计数，
在 `--script` 手动驱动 `_process` 的测试环境下恒为 false（Godot 4.7.1 headless 陷阱，见 #719 CI 失败）。

```gdscript
func _process(_delta: float) -> void:
	## A2: PauseMenu 自检 ESC 边沿（ALWAYS 常驻，暂停中仍响应）
	var now_pressed: bool = Input.is_action_pressed("game_pause")
	if now_pressed and not _was_pause_pressed:
		toggle_pause()
	_was_pause_pressed = now_pressed
```

**恢复路径唯一性（禁止散点直写）：** `_resume()` 是唯一恢复路径——先清缓冲再
`get_tree().paused = false`。恢复瞬间调用 `_clear_input_buffer()`：**InputController 零改动
方案**，走既有公共 API 循环清空（`poll_buffer()` 内含 `_clear_expired`），不新增方法。

```gdscript
func _clear_input_buffer() -> void:
	## 防恢复瞬间「隔空出刀」（PRD §5.3 边界 3）
	if _input_controller == null:
		return
	while _input_controller.buffer_size() > 0:
		_input_controller.poll_buffer()
```

**手册文本运行时生成（AC3 机器保证）：** `manual_text()` 遍历固定有序 9 个战斗/移动动作
（排除 `game_pause`）+ 追加静态「处决」说明行（#580 语义文案，# DRAFT 候选，不参与一致性断言）。
键名经 `action_get_events()` → physical_keycode → 展示名映射表（`KEY_DISPLAY`），映射失败回退
`OS.get_keycode_string`。

### 2.3 状态机（暂停生命周期）

```text
        ┌────────────────────────────────────────────────┐
        │  ESC(edge) / ResumeButton                        │
        ▼                                                  │
  ┌──────────┐   _pause()   ┌──────────────────────┐   _resume()   ┌──────────┐
  │ RUNNING  │ ───────────► │ PAUSED（战斗全冻结） │ ────────────► │ RUNNING  │
  │ paused=F │              │ 菜单 ALWAYS 响应      │               │ paused=F │
  └──────────┘              └──────────────────────┘               └──────────┘
        ▲                        │  ManualButton                       ▲
        │                        ▼                                     │
        │              ┌──────────────────────┐                        │
        │              │ PAUSED+MANUAL（手册开）│── ESC/继续 ──────────────┘
        │              │ ESC=恢复优先，关面板    │
        │              └──────────────────────┘
        └──── ESC 在 FAIL 态被守卫拦截（幂等忽略，不进入任何分支）────┘
```

**幂等性：** 连按 ESC 交替触发（toggle）；恢复后 1 帧内再按 = 再暂停（正常 toggle，无抖动）；
按住 ESC 不重复触发（边沿语义）。手册打开时再按 ESC → 直接恢复并关手册（PRD §5.2 边界 8 取「ESC=恢复优先」）。

## 3. InputMap 变更（`project.godot [input]`）

新增唯一动作 `game_pause` = ESC（物理键 4194305 / KEY_ESCAPE）；既有 9 个 `game_*` 动作零改动。
**与 `input_controller.gd` 的 `ALL_ACTIONS` 不联动**（InputController 不认 `game_pause`——A2 红线，
避免其边沿轮询暂停动作）。

| 动作 | 绑定 | 说明 |
|------|------|------|
| `game_pause` | ESC (physical_keycode 4194305) | 唯一新增动作；菜单自检，不进 InputController |
| `game_move_left/right` | A/D + ←/→ | 移动（既有） |
| `game_light_attack` | J + 鼠标左键 | 轻攻击（既有） |
| `game_heavy_attack` | K + 鼠标右键 | 重攻击（既有） |
| `game_guard` | L | 格挡/弹反（既有） |
| `game_dash` | Shift | 闪避（既有） |
| `game_jump` | 空格 | 跳跃（既有） |
| `game_interact` | E | 互动（既有） |
| `game_revive` | F | 复活（既有，#578） |

## 4. 装配（`main_battle.gd` 第 ⑮ 步）

`_ready()` 末尾（`_sync_visual_facing()` 后）新增 `_build_pause_menu()`（`_build_hud()` 同构），
新增成员 `var pause_menu = null`（装配产物引用，测试断言用）。**零组件改动**：不触碰既有 13 步、
不注入 InputController、不改 `_set_game_state`。

```gdscript
func _build_pause_menu() -> void:
	## ⑮ 暂停菜单: PauseLayer(CanvasLayer, layer=2, ALWAYS) → PauseMenu + FAIL 守卫注入
	var pause_layer: CanvasLayer = CanvasLayer.new()
	pause_layer.name = "PauseLayer"
	add_child(pause_layer)
	pause_menu = PauseMenuScript.new()
	pause_layer.add_child(pause_menu)
	pause_menu.bind_game_state(func() -> int: return game_state)   # 只读闭包注入（FAIL 守卫）
```

## 5. 常量（`constants.gd` 新增 `PAUSE_*` 分区，全 `# DRAFT` 只读）

> 色板收敛：仅从既有 `HUD_MOON_WHITE`/`HUD_INK_BLACK`/`HUD_BLOOD_RED` 派生，不新增色相（#576 色板收敛红线）。

| 常量 | 当前值 | 语义 |
|------|--------|------|
| `PAUSE_TITLE_CANDIDATES` | `["暂停", "雪夜村口 · 暂歇", "歇一歇"]` | 菜单标题（taste 候选，implement 选首项） |
| `PAUSE_BTN_RESUME_TEXT` | `"继续"` | 「继续」按钮文案 |
| `PAUSE_BTN_MANUAL_TEXT` | `"操作手册"` | 手册按钮文案 |
| `PAUSE_MANUAL_TITLE_TEXT` | `"操作手册"` | 手册面板标题 |
| `PAUSE_HINT_TEXT` | `"按 ESC 或「继续」恢复"` | 底部提示 |
| `PAUSE_DIM_COLOR` | `Color(0.08, 0.08, 0.10, 0.6)` | 遮罩色值+透明度（HUD_INK_BLACK 派生） |
| `PAUSE_TITLE_FONT_SIZE` | `32` | 标题字号 |
| `PAUSE_BTN_FONT_SIZE` | `22` | 按钮字号 |
| `PAUSE_MANUAL_FONT_SIZE` | `20` | 手册行字号 |
| `PAUSE_EXECUTE_LINE_CANDIDATES` | `["处决：架势崩解后按攻击键（J）", "处决：崩解后近身按攻击键"]` | 静态处决说明行（taste 候选，implement 选首项） |

> 上述 taste 候选值定稿归 human-review 通道（`content_ownership: taste-draft` 语义），
> 差异记录进 `docs/TASTE.md`。实现期禁止裁决。

## 6. 测试与验收

- `tests/test_pause_menu.gd`（新）：ESC 边沿 / toggle 幂等 / FAIL 守卫 / 缓冲清理 / 手册
  InputMap 一致性（动态部分与 InputMap 一致，静态处决行不参与）/ 节点结构。
- `tests/test_input_controller.gd`（改）：E1 恢复 `game_jump` 事件（#719 CI 失败修复）。
- `tests/run_tests.gd`（改）：挂载新套件。
- **AC1**：游戏进行中 ESC → 暂停 + 菜单弹出（游戏画面冻结）✓
- **AC2**：选「继续」或再按 ESC → 恢复游戏 ✓
- **AC3**：操作手册显示正确按键（与 InputMap 一致，机器保证）✓
- **AC4**：暂停期间敌人/粒子/动画全部冻结，菜单可交互（树级暂停全覆盖）✓

## 7. Issue 记录

| Issue | 说明 |
|------|------|
| #719 | ESC 暂停菜单 + 游戏操作手册（本功能） |
| #728 | 实现 PR（`feat(719)`，已 merge 2026-08-21） |
| #721 | research PRD 源 |
| #724 | plan DESIGN 源 |
| #727/#729 | 并行 #718 的实现/文档 PR（本功能零触碰 combat_judge/combat_state_table） |

**已知边界：** 暂停中 `Engine.time_scale`（#579 慢动作）不触碰——只动 `get_tree().paused`，
恢复后慢动作续跑；FAIL 终态（`GameState.FAIL=4`）按 ESC 被守卫拦截，不弹菜单（双保险：
main_battle FAIL 路径已 `set_process(false)` 冻结 InputController）。
