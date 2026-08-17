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

# ── 2P 双游标状态（#543 §3.5）──
var _p1_focus_index: int = 0          # P1 游标（A/D + E）
var _p2_focus_index: int = 0          # P2 游标（←/→ + Shift）
var _locked_cards: Array = []         # 已确认锁定的卡下标（对方不可选）
var _p1_confirmed: bool = false
var _p2_confirmed: bool = false
var _confirm_timeout: float = 0.0     # 单方确认后等待超时（UPGRADE_2P_CONFIRM_TIMEOUT）
var _is_2p: bool = false              # open() 时按 GameManager 模式判定
var _pick_rng: RandomNumberGenerator = RandomNumberGenerator.new()   # 超时代选确定性

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
## #543: 2P 判定 + 候选池 allow_opponent=_is_2p + 双游标/锁定/超时状态复位。
func open(wave_index: int) -> void:
	if not is_inside_tree():
		return                                # 防悬挂：已移出场景的实例收到残留信号（queue_free 前的同帧竞态）
	if visible or _state != UIState.CLOSED:
		return                                # 边界 3：wave_settled 连发幂等
	if GameManager.is_run_over():
		return                                # 边界 5：终局竞态跳过升级窗口
	_is_2p = is_instance_valid(GameManager) and GameManager.has_method("get_game_mode") \
		and GameManager.get_game_mode() == GameManager.GameMode.LOCAL_2P
	var candidates: Array = UpgradePool.get_candidates(CONSTS.UPGRADE_CANDIDATE_COUNT, _is_2p)   # AC5 唯一来源；2P 含 debuff
	if candidates.is_empty():
		return                                # 失败路径 1：无候选 → 静默跳过，不暂停
	_candidates = candidates
	_wave_index = wave_index
	_focus_index = 0
	_p1_focus_index = 0
	_p2_focus_index = 0
	_locked_cards = []
	_p1_confirmed = false
	_p2_confirmed = false
	_confirm_timeout = CONSTS.UPGRADE_2P_CONFIRM_TIMEOUT
	_render_candidates()                      # 按实际张数渲染（<3 时隐藏多余卡）
	visible = true
	_state = UIState.SELECTING
	get_tree().paused = true                  # AC4：游戏时间暂停
	_set_settle_hold(true)                    # 推进接管：WaveController 停止自动推进
	_apply_focus_visual()


## AC2：焦点环 + 确认。仅 SELECTING 态响应。
## #543: 2P 分支双游标独立裁决（P1 先、P2 后 — 同帧同卡 P1 胜，F3 确定性）；不落入单游标路径。
func _unhandled_input(event: InputEvent) -> void:
	if _state != UIState.SELECTING or not visible:
		return
	if _is_2p:
		if event.is_action_pressed(CONSTS.P1_LEFT_ACTION):
			_p1_focus_index = posmod(_p1_focus_index - 1, _candidates.size())
			_apply_focus_visual()
		elif event.is_action_pressed(CONSTS.P1_RIGHT_ACTION):
			_p1_focus_index = posmod(_p1_focus_index + 1, _candidates.size())
			_apply_focus_visual()
		elif event.is_action_pressed(CONSTS.P1_CONFIRM_ACTION):
			_confirm_2p(0)
		elif event.is_action_pressed(CONSTS.P2_LEFT_ACTION):
			_p2_focus_index = posmod(_p2_focus_index - 1, _candidates.size())
			_apply_focus_visual()
		elif event.is_action_pressed(CONSTS.P2_RIGHT_ACTION):
			_p2_focus_index = posmod(_p2_focus_index + 1, _candidates.size())
			_apply_focus_visual()
		elif event.is_action_pressed(CONSTS.P2_CONFIRM_ACTION):
			_confirm_2p(1)
		return                                # 2P 窗口不消费单游标路径（F5 单人键无动作）
	if event.is_action_pressed("ui_left"):
		_move_focus(-1)
	elif event.is_action_pressed("ui_right"):
		_move_focus(1)
	elif event.is_action_pressed("ui_accept"):
		_confirm()
	# ui_cancel 不消费（边界 4：保持打开；FSM 在树级暂停下收不到，天然不切 PAUSED）


## #543: 2P 确认裁决（先锁后选）。目标卡已锁 → 「已锁」提示 + 不 apply（PRD §5.2-1/2）。
func _confirm_2p(player_index: int) -> void:
	var focus: int = _p1_focus_index if player_index == 0 else _p2_focus_index
	if _locked_cards.has(focus):
		push_warning("UpgradePickUI: 已锁 — 该卡已被对方锁定，请重选")
		return
	var id: String = _candidates[focus].id
	if not UpgradePool.apply(id, player_index):
		push_warning("UpgradePickUI: apply('%s') 失败 — 保持打开，可重选" % id)
		return
	_locked_cards.append(focus)
	_reveal_card(focus, _candidates[focus])
	if player_index == 0:
		_p1_confirmed = true
	else:
		_p2_confirmed = true
	_apply_focus_visual()
	if _p1_confirmed and _p2_confirmed:
		_finish_2p()


## #543: 超时代选 — 单方确认后 10s 无操作 → 未确认方以剩余卡随机代选（PRD §5.3-3）。
func _process(delta: float) -> void:
	if not _is_2p or _state != UIState.SELECTING:
		return
	if _p1_confirmed == _p2_confirmed:
		return                                # 双方均未确认 / 均已确认
	_confirm_timeout -= delta
	if _confirm_timeout <= 0.0:
		var unconfirmed: int = 0 if not _p1_confirmed else 1
		_auto_pick_2p(unconfirmed)


## #543: 超时代选辅助 — 未锁定卡中随机代选并推进。
func _auto_pick_2p(player_index: int) -> void:
	var available: Array = []
	for i in _candidates.size():
		if not _locked_cards.has(i):
			available.append(i)
	if available.is_empty():
		_finish_2p()
		return
	var pick: int = available[_pick_rng.randi_range(0, available.size() - 1)]
	var id: String = _candidates[pick].id
	if UpgradePool.apply(id, player_index):
		_locked_cards.append(pick)
		_reveal_card(pick, _candidates[pick])
		if player_index == 0:
			_p1_confirmed = true
		else:
			_p2_confirmed = true
	_finish_2p()


## #543: 双方确认完成 → 统一关闭（close 已接管 _advance_settlement 推进）。
func _finish_2p() -> void:
	close()


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
	if _is_2p:
		for i in _cards.size():
			var card: PanelContainer = _cards[i]
			if not card.visible:
				continue
			if _locked_cards.has(i):
				card.modulate = CONSTS.UPGRADE_UI_IDLE_MODULATE       # 已锁置灰
			elif i == _p1_focus_index or i == _p2_focus_index:
				card.modulate = CONSTS.UPGRADE_UI_FOCUS_MODULATE      # 任一游标聚焦
			else:
				card.modulate = CONSTS.UPGRADE_UI_IDLE_MODULATE
		return
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
