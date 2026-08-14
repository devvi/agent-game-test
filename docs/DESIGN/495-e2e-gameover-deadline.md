# DESIGN: [Fix] e2e 03_gameover deadline 校准 — capture 升级窗口自动确认（根因修复，非 deadline 延长）

> **Parent Issue:** #495
> **Agent:** game-plan-agent
> **Date:** 2026-08-15
> **Approach:** A — capture harness 升级窗口自动确认（配置驱动 `autoplay.confirm_upgrade`）—— 确认 PRD §4 推荐方案；**注入机制修正**：PRD §8 建议复用 `_inject_press`/`Input.action_press`，本设计改为 `InputEventAction` + `parse_input_event`（镜像 `playthrough_driver.gd._feed_accept`），证据链见 §1.2/§1.3 裁决 1
> **Reference PRD:** docs/PRD/495-e2e-gameover-deadline.md（research PR #496，已合并）
> **上游方案:** docs/DESIGN/394-e2e-playability.md §3.2（L2 playthrough_driver 自动确认先例，:176-177 `Input.parse_input_event(InputEventAction("ui_accept"))`）、#388 三态机（REVEALING 输入锁定 = 幂等依据）、#372 per-shot deadline（deadline 语义保留不动）
> **所有权:** `content_ownership: mechanical`（harness 行为 = 机械可测；无品味决策）
> **深度:** depth/standard（Issue 无 depth 标签，按 #491 惯例）—— 文件域 3（e2e_capture.gd / e2e_shots.json / test_e2e_resolve.py）、无新文件、无迁移、无弃用 → **不产 TASKS 文档**（低于 § 阈值：<10 文件、<5 迁移、<5 子系统）
> **并行上下文:** 改动落在 framework/templates/ + mini-pong/e2e_shots.json（autoplay 块）+ tests/pipeline/。PR #494（impl/491，OPEN）改动面 = e2e_shots.json **shots 组**（加 2 个 rain shot）+ runner missed 检查，与本设计的 **autoplay 块** 不重叠（§7 集成点核对）；合并顺序冲突风险低，冲突时以 merge 后为准 rebase

---

## 1. 架构概述

### 1.1 设计核心

**在 capture 主循环加一个「每帧升级窗口检测」，visible 时注入一次 `ui_accept`，使游戏能自己打完升级窗口 → 继续推进 → GAME_OVER 自然到达。** 不延长 deadline、不改 autoplay 参数、不改任何游戏代码。

```
e2e_shots.json autoplay.confirm_upgrade（配置驱动，显式开启）
    │  resolve_plan.py _PASSTHROUGH 已含 "autoplay"（:24）→ 整块透传，零改动
    ▼
e2e_capture.gd 主循环（每帧，_run() :113 之后新增 1 个调用）
    ├── _confirm_upgrade_if_visible()
    │     ├── cfg 为空 → 直接返回（缺省 = 现状逐字节一致，模板消费者零影响）
    │     ├── 节点不存在 → printerr 告警一次（不崩，fail-open）
    │     └── 节点 visible == true → _emit_action_event("ui_accept")
    │           └── InputEventAction(pressed=true) + Input.parse_input_event
    │                 └── UpgradePickUI._unhandled_input（PROCESS_MODE_ALWAYS，
    │                     paused 下仍收事件）SELECTING → _confirm() → apply(id)
    │                     → _start_reveal()（REVEALING 输入锁定，0.8s）→ close()
    │                     → paused=false + advance_settlement() → 下一波
    ▼
游戏推进 → FSM 到达 GAME_OVER → 03_gameover shot ready → 捕获 PNG（实测 93.7s < 300s）
```

设计哲学：
1. **根因修复而非症状规避** — 冻结 = `UpgradePickUI.open()` 置 `get_tree().paused=true` 等玩家；capture 无人确认 → 永久暂停。喂 `ui_accept` 是解除冻结的唯一正解（PRD §7 实验 2 证明 deadline 延长对冻结无效；实验 3 证明自动确认后 93.7s 达 GAME_OVER）。
2. **镜像 L2 已验证行为，零新机制发明** — `playthrough_driver.gd:30-34 _feed_accept()`（InputEventAction + parse_input_event）已在 L2 层运行 3 个月（#394 起），research 实验 3 以同机制实证。capture 只是把 L2 已有能力补到 L3。
3. **配置驱动向后兼容** — `confirm_upgrade` 字段显式开启；缺省时模板行为与现状逐字节一致（class A 模板红线，防其他项目回归）。
4. **幂等由既有机制保证，不新增去抖** — #388 REVEALING 态输入锁定：每帧喂 `ui_accept` 只在 SELECTING 生效一次，REVEALING/CLOSED 忽略 → 不会重复确认。

### 1.2 PRD 断言 vs 实际代码交叉对照（plan agent 已逐条核实源码）

| PRD 断言 | 实际代码（main @ ea526c7） | 设计裁决 |
|---------|--------------------------|---------|
| 升级窗口节点路径 `/root/Game/UpgradePickUI` | ✅ Main.tscn:161 `[node name="UpgradePickUI" parent="." instance=ExtResource("12_upgrade_pick")]`（Main.tscn 根节点名 = Game，与 state_node 一致） | 路径成立，写入 e2e_shots.json 配置 |
| capture 从不喂 ui_accept → 冻结 | ✅ e2e_capture.gd 主循环（:109-147）仅 `if d.has("press")` 时注入（shot 级、一次性）；无全局每帧注入设施 | 主循环新增每帧检测（§2） |
| 复用 `_inject_press` / `Input.action_press`（PRD §8 步骤 2） | ⚠️ **机制不匹配**：`_inject_press` 的 `{"action": ...}` 模式走 `Input.action_press`，而模板自身注释（:164-168）写明 *"action_press produces NO event, so FSM-style games need this [key mode]"*；UpgradePickUI 消费方式是 `_unhandled_input(event)` + `event.is_action_pressed("ui_accept")`（upgrade_pick_ui.gd:65-73）—— 事件驱动，非轮询 | **裁决 1**：注入必须用 `InputEventAction` + `parse_input_event`（§1.3），`_inject_press` 只作 shot 级 press 保留不动 |
| L2 先例 `playthrough_driver.gd:57-59` 已实现自动确认 | ✅ :57-59 `if ui != null and ui.visible: _feed_accept()`；`_feed_accept()`（:30-34）= `InputEventAction` + `parse_input_event` | 新 helper `_emit_action_event` 逐字节镜像 `_feed_accept` |
| `resolve_plan.py` 白名单第 24 行已含 autoplay，大概率无需改动 | ✅ scripts/e2e/resolve_plan.py:22-25 `_PASSTHROUGH = ("game", ..., "autoplay", ...)`；`resolve()`（:55）整块透传 | **零改动**；新增 1 个透传锁定用例（§3.3） |
| UpgradePickUI paused 下仍处理输入 | ✅ upgrade_pick_ui.gd:37 `process_mode = Node.PROCESS_MODE_ALWAYS`（AC4 前提）；#394 设计已验 | 注入在 paused 下照常被消费 |
| REVEALING 输入锁定保证幂等 | ✅ upgrade_pick_ui.gd:66 `if _state != UIState.SELECTING or not visible: return`；`_confirm()` → `_start_reveal()` 切 REVEALING（:95） | 每帧注入只确认一次，无需额外去抖 |
| 21 分后无新窗口（终局竞态守卫） | ✅ upgrade_pick_ui.gd:48-49 `if GameManager.is_run_over(): return`（边界 5） | 自动确认不影响终局捕获 |
| test_e2e_runner.py 8 用例、fake godot 不执行 capture 逻辑 | ✅ 8 个 `def test_`（含 missed → fail 用例）；fake_godot 只写 PNG/results.json（FAKE_CONFIG 驱动） | 模板改动不破坏既有用例；runner 文件零改动 |
| 升级窗口打开期间 FSM 仍为 PLAYING | ✅ 冻结观察（research 实验 2）：`state=2 paused=true`；窗口期间 02_midgame 若 ready 会捕获窗口帧（仍是合法 PLAYING 帧） | 可接受；确认在下一主循环帧生效 |

### 1.3 设计裁决（PRD 缺口闭合 — plan agent 独立发现）

**裁决 1（注入机制）：必须用 `InputEventAction` + `parse_input_event`，不能用 `Input.action_press`。** PRD §8 建议「复用 `_inject_press`/`Input.action_press`」，但：
- `_inject_press` 的 action 模式 = `Input.action_press`（e2e_capture.gd:185），只置全局 action 状态、**不产生 InputEvent 分发**（模板自身注释 :164-168 明确写了这一点，02_midgame 因此改用 key 模式驱动 FSM）；
- `UpgradePickUI._unhandled_input` 是**事件驱动**（`event.is_action_pressed`），收不到 `action_press` 的状态变更；
- L2 `_feed_accept`（playthrough_driver.gd:30-34）与 DESIGN 394 §3.2:176-177 均以 `Input.parse_input_event(InputEventAction("ui_accept"))` 实现—— 这是本仓库已验证 3 个月的机制。
**定案**：新增 `_emit_action_event(action_name)`（镜像 `_feed_accept` 逐字节），`confirm_upgrade.action` 配置驱动。也可考虑 key 模式（ui_accept 默认绑 Enter），但 action 级事件更贴近 L2 先例且不依赖键位映射，选它。

**裁决 2（检测位置）：主循环每帧，独立于 shot 级 press。** shot 级 `press` 只在处理该 shot 时注入一次；升级窗口可能在任何帧打开（墙清空是 RNG 赛跑），必须每帧检测。放置点：`_run()` 主循环 `_track_transcript()`（:113）之后、shot 遍历之前—— 保证「先解除冻结，再检查 shot ready」。

**裁决 3（不放入 `_settle()`）：** settle ≤ 10 帧且 03_gameover settle 时 `is_run_over()` 守卫使窗口不可能新开；02_midgame settle 期间若窗口恰好打开，捕获的是窗口帧（仍为 PLAYING 合法帧），主循环下一帧即确认。主循环单独覆盖已完备，settle 内重复调用增加模板复杂度但无收益。

**裁决 4（幂等零新增）：** REVEALING 输入锁定（#388）+ `_confirm` 恰好一次（upgrade_pick_ui.gd:83-91）已保证每帧注入只确认一次；`apply()` 失败路径（未知 id/max_stacks 竞态）保持窗口打开 → 下帧重试，最终成功或 300s deadline 兜底。不需要 cooldown/one-shot 标志。

**裁决 5（缺省兼容即测试）：** 模板消费者（其他项目）不配置 `confirm_upgrade` → `cfg.is_empty()` 直接返回，行为逐字节不变。这是向后兼容红线，也是验收的一部分（§9 Scenario D）。

---

## 2. 新组件

无新文件。`framework/templates/e2e_capture.gd` 新增 2 个函数 + 1 个调用点（模板级能力扩展，配置驱动开关）：

### 2.1 `_emit_action_event(action_name: String)`（e2e_capture.gd 新增，Autoplay 段）

镜像 `playthrough_driver.gd:30-34 _feed_accept()` 逐字节：

```gdscript
## 注入一次 action 级 InputEvent（pressed=true，momentary）。
## #495 裁决 1：不能用 Input.action_press —— 只置状态不发事件，事件驱动
## 的 _unhandled_input 收不到（模板 :164-168 既有注释 + L2 _feed_accept 先例）。
func _emit_action_event(action_name: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action_name
	ev.pressed = true
	Input.parse_input_event(ev)
```

- 无 release 需求：`is_action_pressed(event)` 按事件本身判定（UpgradePickUI:72），momentary 事件即触发一次确认；与 `_feed_accept` 一致。

### 2.2 `_confirm_upgrade_if_visible()`（e2e_capture.gd 新增）

```gdscript
## #495 Approach A：配置驱动的升级窗口自动确认。
## 每帧调用；plan.autoplay.confirm_upgrade = {"node": ..., "action": ...}。
## 缺省（未配置）→ 直接返回，行为与现状逐字节一致（模板兼容红线）。
## 节点不可达 → printerr 告警一次（fail-open，不崩）。
func _confirm_upgrade_if_visible() -> void:
	var cfg: Dictionary = _plan.get("autoplay", {}).get("confirm_upgrade", {})
	if cfg.is_empty():
		return
	var node = root.get_node_or_null(str(cfg.get("node", "")))
	if node == null:
		printerr("⚠ confirm_upgrade node not found: ", cfg.get("node", ""))
		return
	var v = node.get("visible")
	if v != null and bool(v):
		_emit_action_event(str(cfg.get("action", "ui_accept")))
```

- `node.get("visible")` 一次参数形式（模板 :367 既有注释约束）；`bool(v)` 兼容 CanvasLayer.visible 及任意带 visible 的节点。
- 调用点：`_run()` 主循环 :113 `_track_transcript()` 之后、shot 遍历之前，与 shot 级 press 注入（:131）互不干扰。

---

## 3. 既有组件修改

### 3.1 `framework/templates/e2e_capture.gd`（修改）

| 位置 | 变更 | 动机 |
|------|------|------|
| 头部注释 schema 文档（:14-33） | `autoplay` 示例块补 `confirm_upgrade` 字段说明 | 模板自文档（既有 convention：schema 注释即契约） |
| `_run()` 主循环（:113 后） | 新增 `_confirm_upgrade_if_visible()` 调用 | 每帧解除升级窗口冻结（裁决 2） |
| Autoplay 段（`_apply_tweaks` 附近） | 新增 `_emit_action_event` + `_confirm_upgrade_if_visible`（§2） | 配置驱动能力 |

### 3.2 `mini-pong/e2e_shots.json`（修改）

autoplay 块新增 1 字段（tweaks 不动）：

```json
"autoplay": {
  "mode": "ai",
  "confirm_upgrade": { "node": "/root/Game/UpgradePickUI", "action": "ui_accept" },
  "tweaks": [
    { "node": "/root/Game/PlayerPaddle", "prop": "mode", "value": 1 },
    { "node": "/root/Game/AIPaddle", "prop": "mode", "value": 1 },
    { "node": "/root/Game/AIPaddle", "prop": "ai_position_error", "value": 200 }
  ]
}
```

- 节点路径按 Main.tscn:161 核实；action = `ui_accept`（UpgradePickUI._unhandled_input:72 消费）。
- **shots 组零改动**（01_title/02_midgame/03_gameover 及 #491 的 rain shots 原样）—— 与 PR #494 改动面不重叠。

### 3.3 `tests/pipeline/test_e2e_resolve.py`（修改，+1 用例）

`resolve_plan.py` 零改动（autoplay 已在 `_PASSTHROUGH` :24）。但按本仓库「passthrough 行为必须被测试锁定」先例（`test_deadline_s_passthrough`，#372 T6），补 1 个透传锁定用例：plan 含 `autoplay.confirm_upgrade` → `resolve()` 输出 `resolved["autoplay"]["confirm_upgrade"]` 原样保留。防未来 refactor 剥离未知键静默破坏 capture（§9 Scenario A Test 1）。

### 3.4 确认不改的文件

| 文件 | 为何不改 |
|------|---------|
| `scripts/e2e/resolve_plan.py` | `_PASSTHROUGH` 已含 autoplay（:24），整块透传（已核实 resolve() :55 逐键复制） |
| `tests/pipeline/test_e2e_runner.py` | fake godot 不执行 capture 逻辑（只写 PNG/results.json），8 用例不受模板影响 |
| `mini-pong/tests/playthrough_driver.gd` | L2 参照先例，行为已一致，零改动 |
| `scripts/run-e2e-review.sh` / `analyze_bmp.py` / runner missed 检查 | #491/#494 已落地，capture 行为变化自动被现有链路消费 |

### 3.5 文件清单汇总

- **新文件:** 无
- **修改文件:** 3 — framework/templates/e2e_capture.gd / mini-pong/e2e_shots.json / tests/pipeline/test_e2e_resolve.py
- **删除/弃用:** 无
- **受影响测试:** test_e2e_resolve.py（+1 用例，既有 10 用例不回归）；test_e2e_runner.py（不改，8 用例保持绿）

---

## 4. 数据流

### Flow 1: 修复后正常路径（目标行为）

```
某波砖墙清空 → WaveController._on_wall_cleared → GameManager.settle_wave()
    → wave_settled → UpgradePickUI.open() → paused=true + settle_hold=true（窗口打开）
    ▼
capture 主循环下一帧：_confirm_upgrade_if_visible()
    → UpgradePickUI.visible == true → _emit_action_event("ui_accept")
    → Input.parse_input_event(InputEventAction) → _unhandled_input（PROCESS_MODE_ALWAYS）
    → SELECTING → _confirm() → UpgradePool.apply(id) → _start_reveal()（REVEALING 锁定）
    → 0.8s 后 close() → paused=false + advance_settlement() → 下一波
    ▼
循环至 21 分 → FSM GAME_OVER → 03_gameover shot ready → PNG 捕获
    （research 实验 3 实测：1 次确认，GAME_OVER @ 93.7s，21:7，<< 300s deadline）
```

### Flow 2: 修复前冻结路径（现状，根因）

```
同入口 open() → paused=true → capture 无确认设施 → 游戏永久暂停
    → FSM 停在 PLAYING → GAME_OVER 永不进入 → 03_gameover 300s deadline 到
    → results.json missed → L3 fail（#494 missed 检查诚实暴露）—— 间歇 ~1/3
```

### Flow 3: 缺省兼容路径（模板其他消费者 / 未配置）

```
plan.autoplay 无 confirm_upgrade → cfg.is_empty() → _confirm_upgrade_if_visible 直接返回
    → capture 行为与现状逐字节一致（零回归）
    → 若其游戏无升级窗口机制，本就不需要该能力
```

### Flow 4: 多窗口连开（波次连续推进）

```
波 1 清空 → 窗口 → 确认 → close + advance → 波 2 清空 → 窗口 → 确认 → ...
    → 每帧检测天然串行处理，每窗口恰好确认一次（REVEALING 锁定保证）
    → 全部打完 → GAME_OVER（实验 3 场景即含该路径，93.7s 含 1 次确认）
```

---

## 5. 边界情况与错误处理

| 边界情况 | 缓解措施 |
|---------|---------|
| 21 分先到、墙未清空（~2/3 现状正常局） | 无窗口打开 → confirm 无操作 → GAME_OVER 正常捕获（现状路径，行为不变） |
| 墙清空先到（~1/3 冻结局） | 每帧检测 → 窗口可见即确认 → 冻结解除（根因修复） |
| REVEALING 期间继续喂 ui_accept | #388 输入锁定（upgrade_pick_ui.gd:66 仅 SELECTING 响应）→ 幂等，无重复确认 |
| 窗口打开瞬间已 run_over（同帧竞态） | `open()` 的 `is_run_over()` 守卫（:48-49）跳过 → 无窗口无冻结 |
| `apply()` 返回 false（未知 id / max_stacks 竞态） | 窗口保持打开（:89-90 push_warning）→ 下帧继续喂 → 重试直至成功或 300s 兜底 |
| 候选不足 3 张 | `open()` 失败路径静默跳过不暂停（:51-52）→ confirm 无操作（现状一致） |
| confirm_upgrade 未配置 / 节点路径不存在 | 缺省返回 / printerr 告警一次（fail-open 不崩）；配置错误由 L3 诚实失败暴露 |
| 自动确认后极端 RNG 仍超时（多波拖时） | 300s deadline 兜底 → missed 诚实报 fail（门不删除，PRD 失败路径 2） |
| 窗口打开时 02_midgame 恰好 ready | 捕获窗口帧（仍为 PLAYING 合法 midgame 帧，require score≥1 语义不变）；下一主循环帧确认 |
| headless 跑 capture（理论场景） | paused 语义不变，PROCESS_MODE_ALWAYS 注入照常（与 L2 同机制，已验证） |
| 模板其他项目回归 | 配置驱动缺省关闭（Flow 3）→ 逐字节兼容 |

---

## 6. 逐组件配置（implement 契约速查）

| 位置 | 配置 | 值 |
|------|------|-----|
| e2e_capture.gd `_run()` 主循环 | 调用点 | `_track_transcript()` 之后新增 `_confirm_upgrade_if_visible()`（每帧） |
| e2e_capture.gd Autoplay 段 | `_emit_action_event(action)` | `InputEventAction` + `Input.parse_input_event`（镜像 _feed_accept，**非** action_press） |
| e2e_capture.gd Autoplay 段 | `_confirm_upgrade_if_visible()` | 读 `autoplay.confirm_upgrade`；cfg 空→return；node null→printerr；visible→注入 |
| e2e_shots.json autoplay 块 | `"confirm_upgrade"` | `{"node": "/root/Game/UpgradePickUI", "action": "ui_accept"}` |
| e2e_shots.json | tweaks / shots / deadline | **零改动**（300s 保留；两档 rain shot 不动） |
| test_e2e_resolve.py | 新增用例 | autoplay.confirm_upgrade 透传锁定（§9 Scenario A Test 1） |

---

## 7. 集成点

> **状态约定:** ⬜ = 待 implement agent 接线；✅ = implement agent 验证后更新。review agent 合并前核验无 ⬜ 残留。

| 集成 | 我方组件 | 目标 Issue/系统 | 方式 | 状态 |
|------|:---:|:---:|------|:---:|
| capture → UpgradePickUI | `_confirm_upgrade_if_visible` + `_emit_action_event` | #388 三态机 | 每帧 visible 检测 → InputEventAction(ui_accept) → `_unhandled_input` SELECTING 确认 | ✅ 已接线（PR #498） |
| e2e_shots.json → resolve_plan | `autoplay.confirm_upgrade` | resolve_plan.py `_PASSTHROUGH`（:24 已含 autoplay） | 整块透传，零改动（implement 验证） | ✅ 已有 |
| resolve → capture plan.json | 透传的 confirm_upgrade | e2e_capture.gd `_plan` | capture 读取 `autoplay.confirm_upgrade` | ✅ 已接线（PR #498） |
| 冻结解除 → 03_gameover | 主循环每帧确认 | #372 per-shot deadline | GAME_OVER 可达（实测 27.9s/38s/56s 三次全捕获 < 300s）→ shot ready | ✅ 已接线（PR #498） |
| pipeline 测试 | test_e2e_resolve.py +1 用例 | resolve_plan.py 契约 | 透传锁定（§9 Scenario A） | ✅ 已接线（PR #498） |
| 文档回填 | docs/DESIGN/394 L3 一行 + docs/PROJECT.md known-issue | PRD §3.5 | 实现 PR merge 后 review agent 增量更新 | ⬜ 延后 |

**并行安全（PR #494）：** #494 改 e2e_shots.json 的 shots 组（+02_rain_light/heavy）与 run-e2e-review.sh（missed 检查）；本设计改 autoplay 块 + 模板 + 测试文件。JSON 同文件不同键区，git 三路合并可自动处理；冲突时以 merge 后为准 rebase（PRD §6.3）。

---

## 8. 实施阶段

| 阶段 | 优先级 | 组件 | 估算 |
|:----:|:------:|------|:----:|
| Phase 1 | P0 | e2e_capture.gd 模板：`_emit_action_event` + `_confirm_upgrade_if_visible` + 主循环调用点 + schema 注释 | 0.5 天 |
| Phase 2 | P0 | e2e_shots.json autoplay.confirm_upgrade + test_e2e_resolve.py 透传用例 + pipeline 测试全绿（`python3 -m unittest discover -s tests/pipeline`） | 0.5 天 |
| Phase 3 | P0 | 本地 run-e2e-review.sh 连跑 3 次验证 AC1（3/3 全捕获；每次含 300s deadline 上限 ≈ 5min+，3 次预算 15-20min）+ trajectory 证据（AC2） | 0.5 天 |
| Phase 4 | P1 | L0 编译 + L1 静态 + L2 运行时三层 + pipeline 全绿（AC3/AC4）；review agent 本地 E2E 验收（AC5 两档断言） | 0.5 天 |

依赖序：Phase 1 → 2 → 3 → 4（模板先行，配置与测试跟随，真实验证最后）。

---

## 9. 测试用例描述

### Scenario A: pipeline 透传锁定（test_e2e_resolve.py +1 用例）

- **Test 1**（confirm_upgrade 透传）：plan 含 `autoplay.confirm_upgrade = {"node": "/root/Game/UpgradePickUI", "action": "ui_accept"}` + 触发 loop 组 diff → `resolve()` 输出 `resolved["autoplay"]["confirm_upgrade"]` 与输入逐键相等；缺该字段的 plan → 输出不新增键（镜像 `test_deadline_s_passthrough` 模式，防未来 refactor 剥离未知键）
- **Test 2**（既有回归）：既有 10 用例保持绿（resolve 未动，天然通过）

### Scenario B: L2 既有回归（不改动，验证网）

- `tests/playthrough_test.tscn` + `playthrough_driver.gd` 照跑（其自动确认机制未变）→ L2 PASS；升级窗口确认路径（DESIGN 394 §9 Scenario G）继续覆盖游戏侧机制

### Scenario C: 本地 e2e 3/3（AC1 + AC2）

- **Test 1**（3/3 全捕获）：run-e2e-review.sh 连跑 3 次 → 3 次 `results.json` missed 均为空；P5-visual.log 含 `saved ...03_gameover.png`
- **Test 2**（自动确认生效证据）：trajectory.txt / 日志显示升级窗口出现后被确认（paused 恢复、波次推进不冻结）；或 GAME_OVER 到达时间 < 120s（实测基线 93.7s）
- **Test 3**（诚实时长）：单次 capture 总时长 ≈ 终局时间（~94s）+ 余量，远小于 300s deadline（非等待 deadline 到期）

### Scenario D: 兼容性与既有门（AC5）

- **Test 1**（缺省兼容）：构造不含 confirm_upgrade 的 plan → capture 行为与现状一致（模板消费者零回归；以代码审查 + pipeline 用例保障）
- **Test 2**（两档断言不受影响）：02_rain_heavy（current_rain≥0.55）与 02_rain_light 在 GAME_OVER 之前早已捕获（诚实 run: frame 257/1492，PRD §2.3）→ 修复只影响 03_gameover 之后的推进，Δluma 差异断言 pass
- **Test 3**（门不删除）：03_gameover 保留 deadline_s=300 + missed 诚实报 fail（#494 机制不动）

---

## 10. 验收条件映射（AC checklist，源自 Issue #495 body）

| AC | 内容 | 设计落实 |
|----|------|---------|
| 完成定义 1 | 03_gameover 在本地 e2e 中 3/3 次可靠捕获（或按 DESIGN §5 校准路径调整，**不得删除门**） | 方案 A 校准路径（PRD §4 已实证）：§3.1 模板 + §3.2 配置；§9 Scenario C Test 1（3 连跑 missed 全空） |
| 完成定义 2 | 校准方案：capture harness 升级窗口自动确认（镜像 L2 playthrough_driver） | §2.1/§2.2（_emit_action_event 逐字节镜像 _feed_accept）；§9 Scenario C Test 2（轨迹证据） |
| 完成定义 3 | pipeline 测试覆盖：test_e2e_runner.py 用例保持绿 | §3.3/§3.4：runner 8 用例不动 + test_e2e_resolve.py +1 透传锁定；Phase 2 全绿 |
| 完成定义 4 | L0/L1/L2 + pipeline 全绿 | §8 Phase 4：check_compile.gd / run_tests.gd / playthrough_test.tscn / pipeline 全通过 |
| 验收 | 02_rain_heavy（current_rain≥0.55）与 02_rain_light 两档差异断言不受影响 | 修复推进的是 03_gameover 之后的路径，两档 shot 早已捕获（PRD §2.3 证据 + §9 Scenario D Test 2） |

### 明确不修改（继承 PRD §2.3/§3.1/§8）

- `mini-pong/gdscripts/**`、`mini-pong/scenes/**`、`project.godot` —— 游戏代码零改动（class A 基建红线）
- 03_gameover `deadline_s` 300 —— 不改 deadline 语义（PRD 实验 2 证伪 600s：冻结 = 暂停非慢速）
- autoplay tweaks（mode=1/1、ai_position_error=200）—— 不改测试环境参数（方案 C 否决理由）
- `scripts/e2e/resolve_plan.py` —— autoplay 已在 `_PASSTHROUGH` 整块透传，零改动
- `scripts/run-e2e-review.sh` / `analyze_bmp.py` / runner missed 检查 —— #491/#494 已落地，不动
- `mini-pong/tests/playthrough_driver.gd` —— L2 参照先例，零改动
- 不新增任何游戏/模板之外的文件；不引入新依赖
- missed 检查不删除（诚实报 fail 是防假绿生命线，Issue 明确「不得删除门」）
