extends CanvasLayer
## UpgradePickUI — 波间 3 选 1 升级选择层（#388）。
## 监听 GameManager.wave_settled（#386 挂点）→ UpgradePool.get_candidates(3)（#387，AC5 唯一
## 来源）→ 焦点环选择（ui_left/ui_right 循环切换、ui_accept 确认）→ apply(id) → reveal 稀有度
## （AC3，确认后展示）→ 关闭并恢复游戏时间（AC4，get_tree().paused）→ 显式通知 WaveController
## 推进下一波（#386 边界 2 接管：settle_hold / advance_settlement）。
##
## 三态状态机: CLOSED → SELECTING → REVEALING → CLOSED。仅 SELECTING 响应输入（REVEALING 输入锁定）。
## 容错: group wave_controllers 寻址 + has_method/"in" 守卫——#393 组装前 Main.tscn 无
## WaveController 节点时 open/close 的接管调用 no-op 不崩。
##
## 所有权: content_ownership: mechanical（交互机械层；稀有度色值/卡片文案为 taste 占位，
## 映射键机械定稿——沿 #387 先例）。
## Design: docs/DESIGN/388-upgrade-pick-ui.md §3.1
## Parent Issue: #388

signal upgrade_chosen(upgrade_id: String)   # 可选扩展锚点（#393 E2E 断言/未来 HUD 消费）

const CONSTS = preload("res://gdscripts/constants.gd")

enum UIState { CLOSED, SELECTING, REVEALING }

var _state: int = UIState.CLOSED      # 状态机；仅 SELECTING 响应输入
var _focus_index: int = 0             # 焦点卡下标（循环切换）
var _candidates: Array = []           # open() 时 get_candidates(3) 的结果缓存
var _wave_index: int = 0              # 本次升级窗口的波次号（wave_settled 载荷）
var _reveal_hold: float = CONSTS.UPGRADE_UI_REVEAL_HOLD   # reveal 展示时长（测试可注入缩短）

@onready var _cards: Array = [
	$CenterContainer/HBoxContainer/Card0,
	$CenterContainer/HBoxContainer/Card1,
	$CenterContainer/HBoxContainer/Card2,
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # AC4 前提：树级暂停下仍处理输入
	visible = false
	GameManager.wave_settled.connect(open)    # #386 挂点（autoload 信号，任意场景/headless 可用）


## AC1/AC5：打开升级窗口。幂等：已打开/REVEALING 中再收到 wave_settled → no-op。
func open(wave_index: int) -> void:
	if not is_inside_tree():
		return                                # 防悬挂：已移出场景的实例收到残留信号（queue_free 前的同帧竞态）
	if visible or _state != UIState.CLOSED:
		return                                # 边界 3：wave_settled 连发幂等
	if GameManager.is_run_over():
		return                                # 边界 5：终局竞态跳过升级窗口
	var candidates: Array = UpgradePool.get_candidates(CONSTS.UPGRADE_CANDIDATE_COUNT)   # AC5 唯一来源
	if candidates.is_empty():
		return                                # 失败路径 1：无候选 → 静默跳过，不暂停
	_candidates = candidates
	_wave_index = wave_index
	_focus_index = 0
	_render_candidates()                      # 按实际张数渲染（<3 时隐藏多余卡）
	visible = true
	_state = UIState.SELECTING
	get_tree().paused = true                  # AC4：游戏时间暂停
	_set_settle_hold(true)                    # 推进接管：WaveController 停止自动推进
	_apply_focus_visual()


## AC2：焦点环 + 确认。仅 SELECTING 态响应。
func _unhandled_input(event: InputEvent) -> void:
	if _state != UIState.SELECTING or not visible:
		return
	if event.is_action_pressed("ui_left"):
		_move_focus(-1)
	elif event.is_action_pressed("ui_right"):
		_move_focus(1)
	elif event.is_action_pressed("ui_accept"):
		_confirm()
	# ui_cancel 不消费（边界 4：保持打开；FSM 在树级暂停下收不到，天然不切 PAUSED）


func _move_focus(delta: int) -> void:
	var n: int = _candidates.size()
	_focus_index = posmod(_focus_index + delta, n)   # 循环 0→1→2→0（AC2；不足 3 张时按 size 环绕）
	_apply_focus_visual()                             # 高亮切换（modulate/边框）


func _confirm() -> void:
	var id: String = _candidates[_focus_index].id
	if UpgradePool.apply(id):                         # AC2：应用选中升级（恰好一次）
		upgrade_chosen.emit(id)
		_start_reveal()
	# apply 返回 false（未知 id / 已达 max_stacks 竞态）→ 保持打开 + push_warning（边界 2）
	else:
		push_warning("UpgradePickUI: apply('%s') 失败 — 保持打开，可重选（边界 2）" % id)


## AC3：确认后 reveal。REVEALING 态锁定输入；短暂展示后关闭。
func _start_reveal() -> void:
	_state = UIState.REVEALING
	var chosen: Dictionary = _candidates[_focus_index]
	_reveal_card(_focus_index, chosen)                # 边框切稀有度色 + RarityLabel 显示名称（其余卡保持中性）
	await get_tree().create_timer(_reveal_hold).timeout   # paused 下 process_always 仍计时（DESIGN §6 边界 7）
	if not is_inside_tree():
		return                                        # 边界 10：场景卸载防悬挂协程泄漏
	close()


## AC2/AC4：关闭并恢复。幂等。
func close() -> void:
	if _state == UIState.CLOSED:
		return                                        # 边界 10：重复调用幂等
	_state = UIState.CLOSED
	visible = false
	get_tree().paused = false                         # AC4：恢复游戏时间
	_advance_settlement()                             # 推进接管：显式通知 WaveController 进下一波


## 推进接管（差异决策 3）：经 group 寻址 WaveController，未挂载时 no-op。
func _advance_settlement() -> void:
	var wc = get_tree().get_first_node_in_group("wave_controllers")
	if wc != null and wc.has_method("advance_settlement"):
		wc.advance_settlement()                       # → _advance_wave() → 下一波


func _set_settle_hold(hold: bool) -> void:
	var wc = get_tree().get_first_node_in_group("wave_controllers")
	if wc != null and "settle_hold" in wc:
		wc.settle_hold = hold


# ── 渲染 ──

func _render_candidates() -> void:
	for i in _cards.size():
		var card: PanelContainer = _cards[i]
		if i >= _candidates.size():
			card.visible = false                      # 候选不足 3 张：隐藏多余卡（边界 1）
			continue
		card.visible = true
		var cand: Dictionary = _candidates[i]
		var display: Dictionary = cand.get("display", {})
		var name_working: String = display.get("name_working", "")
		var short_phrase: String = display.get("short_phrase", "")
		var name_label: Label = card.get_node("VBoxContainer/NameLabel")
		name_label.text = name_working if name_working != "" else cand.get("name", "")   # 兜底链
		var phrase_label: Label = card.get_node("VBoxContainer/ShortPhraseLabel")
		phrase_label.text = short_phrase
		var desc_label: Label = card.get_node("VBoxContainer/EffectDescLabel")
		desc_label.text = cand.get("effect_desc", "")
		var rarity_label: Label = card.get_node("VBoxContainer/RarityLabel")
		rarity_label.text = ""                        # AC3：确认前无稀有度线索
		rarity_label.visible = false
		_reset_card_style(card)


func _apply_focus_visual() -> void:
	for i in _cards.size():
		var card: PanelContainer = _cards[i]
		if not card.visible:
			continue
		var is_focus: bool = (i == _focus_index)
		card.modulate = CONSTS.UPGRADE_UI_FOCUS_MODULATE if is_focus else CONSTS.UPGRADE_UI_IDLE_MODULATE
		_set_card_border(card, CONSTS.UPGRADE_UI_FOCUS_BORDER if is_focus else CONSTS.UPGRADE_UI_NEUTRAL_BORDER)


## AC3：第 i 卡 reveal — 边框切稀有度色 + 稀有度名称；其余卡保持中性。
func _reveal_card(i: int, chosen: Dictionary) -> void:
	var card: PanelContainer = _cards[i]
	var rarity: int = chosen.get("rarity", 0)
	var rarity_color: Color = CONSTS.UPGRADE_RARITY_COLORS.get(rarity, CONSTS.UPGRADE_UI_NEUTRAL_BORDER)
	_set_card_border(card, rarity_color)
	var rarity_label: Label = card.get_node("VBoxContainer/RarityLabel")
	rarity_label.text = CONSTS.UPGRADE_RARITY_NAMES.get(rarity, "")
	rarity_label.visible = true


func _reset_card_style(card: PanelContainer) -> void:
	_set_card_border(card, CONSTS.UPGRADE_UI_NEUTRAL_BORDER)
	card.modulate = CONSTS.UPGRADE_UI_IDLE_MODULATE


func _set_card_border(card: PanelContainer, color: Color) -> void:
	var sb = card.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		sb.border_color = color
