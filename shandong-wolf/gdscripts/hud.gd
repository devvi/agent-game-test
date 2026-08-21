extends CanvasLayer
class_name Hud
## Hud — 极简 HUD 层（#576）：两段式血条 / 玩家与敌人架势条 / 击杀与处决提示。
## 归属: docs/DESIGN/576-hud-stance-bars.md §2.2
## 职责: 纯消费方——只读信号画条 + 发 low_health_changed 边沿信号，零判定零轮询零贴图。
## 信号源: #575 CombatEntity（hp_changed / stance_changed / stance_broken / state_changed / died / revived）。
## 组装: #585 bind_player(player) + set_target_enemy(enemy)；low_health_changed → #582 vignette。
## 静态契约（test_hud.gd T25/T26）: 零贴图资源引用 + 零帧轮询——所有更新由信号 + Tween/Timer 驱动。

const C = preload("res://gdscripts/constants.gd")
const CombatEntityScript = preload("res://gdscripts/combat_entity.gd")

signal low_health_changed(enabled: bool)   # 边沿触发（活性条 < HUD_LOW_HP_RATIO 时恰好一次 true/false）

## 处决提示文案（B2 候选 5 选 1 草稿，implement 选 1，候选清单进 PR 待用户定稿）
const EXECUTE_HINTS: Array = [
	"按攻击键处决", "趁势处决", "了结他", "就地正法", "下手吧",
]
## 击杀提示文案（B2 候选 5 选 1 草稿，implement 选 1，候选清单进 PR 待用户定稿）
const KILL_HINTS: Array = [
	"击毙", "斩杀", "击杀", "肃清", "取敌",
]

## 战斗实体订阅（bind_player / set_target_enemy 注入；_exit_tree 双保险断开）
var _player: CombatEntityScript = null
var _target_enemy: CombatEntityScript = null
var _low_health: bool = false                # 当前低血态（边沿触发基准，防每帧重发）

var _execute_hint_tween: Tween = null
var _kill_hint_tween: Tween = null

## 公有节点成员（_ready 代码创建，tests 直接访问）
var PlayerBarGroup: Control
var PlayerHealthBar: _HudBar
var PlayerStanceBar: _HudBar
var EnemyHealthBar: _HudBar
var EnemyStanceBar: _HudBar
var ExecutePromptLabel: Label
var KillPromptLabel: Label

var _execute_hint_timer: Timer
var _kill_hint_timer: Timer


func _ready() -> void:
	layer = 1
	_create_nodes()
	add_to_group("hud")
	var first: Node = get_tree().get_first_node_in_group("hud")
	if first != null and first != self:
		queue_free()
		return
	_create_timers()


func _exit_tree() -> void:
	_disconnect_player()
	_disconnect_enemy()


# ── 节点创建（零 tscn 零贴图，纯代码）─────────────────────────────────────

func _create_nodes() -> void:
	PlayerBarGroup = Control.new()
	PlayerBarGroup.position = C.HUD_PLAYER_MARGIN
	add_child(PlayerBarGroup)

	PlayerHealthBar = _HudBar.new()
	PlayerHealthBar.position = Vector2(0.0, 0.0)
	PlayerHealthBar.size = Vector2(C.HUD_BAR_WIDTH, C.HUD_BAR_HEIGHT)
	PlayerBarGroup.add_child(PlayerHealthBar)

	PlayerStanceBar = _HudBar.new()
	PlayerStanceBar.position = Vector2(0.0, C.HUD_BAR_HEIGHT + C.HUD_STANCE_GAP)
	PlayerStanceBar.size = Vector2(C.HUD_BAR_WIDTH, C.HUD_STANCE_HEIGHT)
	PlayerBarGroup.add_child(PlayerStanceBar)

	EnemyHealthBar = _HudBar.new()
	EnemyHealthBar.anchor_left = 0.5
	EnemyHealthBar.anchor_right = 0.5
	EnemyHealthBar.offset_left = -C.HUD_ENEMY_BAR_WIDTH / 2.0
	EnemyHealthBar.offset_right = C.HUD_ENEMY_BAR_WIDTH / 2.0
	EnemyHealthBar.offset_top = C.HUD_ENEMY_BAR_TOP
	EnemyHealthBar.offset_bottom = C.HUD_ENEMY_BAR_TOP + C.HUD_BAR_HEIGHT
	EnemyHealthBar.visible = false
	EnemyHealthBar.set_fill_color(C.HUD_BLOOD_RED)
	add_child(EnemyHealthBar)

	EnemyStanceBar = _HudBar.new()
	EnemyStanceBar.anchor_left = 0.5
	EnemyStanceBar.anchor_right = 0.5
	EnemyStanceBar.offset_left = -C.HUD_ENEMY_BAR_WIDTH / 2.0
	EnemyStanceBar.offset_right = C.HUD_ENEMY_BAR_WIDTH / 2.0
	EnemyStanceBar.offset_top = C.HUD_ENEMY_BAR_TOP + C.HUD_BAR_HEIGHT + C.HUD_ENEMY_HP_GAP
	EnemyStanceBar.offset_bottom = C.HUD_ENEMY_BAR_TOP + C.HUD_BAR_HEIGHT + C.HUD_ENEMY_HP_GAP + C.HUD_STANCE_HEIGHT
	EnemyStanceBar.visible = false
	add_child(EnemyStanceBar)

	ExecutePromptLabel = _make_hint_label(220.0, 44.0)
	KillPromptLabel = _make_hint_label(120.0, 44.0)


func _make_hint_label(width: float, top: float) -> Label:
	var label: Label = Label.new()
	label.add_theme_font_size_override("font_size", C.HUD_HINT_FONT_SIZE)
	label.add_theme_color_override("font_color", C.HUD_MOON_WHITE)
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = C.HUD_INK_BLACK
	bg.border_color = C.HUD_MOON_WHITE
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(0)
	bg.content_margin_left = 8.0
	bg.content_margin_right = 8.0
	bg.content_margin_top = 2.0
	bg.content_margin_bottom = 2.0
	label.add_theme_stylebox_override("normal", bg)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.offset_left = -width / 2.0
	label.offset_right = width / 2.0
	label.offset_top = top
	label.offset_bottom = top + 28.0
	label.visible = false
	add_child(label)
	return label


func _create_timers() -> void:
	_execute_hint_timer = Timer.new()
	_execute_hint_timer.one_shot = true
	_execute_hint_timer.timeout.connect(_on_execute_hint_timeout)
	add_child(_execute_hint_timer)

	_kill_hint_timer = Timer.new()
	_kill_hint_timer.one_shot = true
	_kill_hint_timer.timeout.connect(_on_kill_hint_timeout)
	add_child(_kill_hint_timer)


# ── 公有 API（#585 组装 + E2E/单测驱动）──────────────────────────────────

func bind_player(entity: CombatEntityScript) -> void:
	## 幂等绑定玩家实体：同实体早退；换实体先断开旧订阅；null 仅断开。
	if entity == _player:
		return
	_disconnect_player()
	_player = entity
	if entity == null:
		return
	entity.hp_changed.connect(_on_player_hp_changed, CONNECT_REFERENCE_COUNTED)
	entity.stance_changed.connect(_on_player_stance_changed, CONNECT_REFERENCE_COUNTED)
	entity.state_changed.connect(_on_player_state_changed, CONNECT_REFERENCE_COUNTED)
	entity.died.connect(_on_player_died, CONNECT_REFERENCE_COUNTED)
	entity.revived.connect(_on_player_revived, CONNECT_REFERENCE_COUNTED)


func set_target_enemy(entity: CombatEntityScript) -> void:
	## 幂等注入战斗目标：同实体早退；换目标先断开旧敌人订阅；null → 隐藏敌人血条/架势条；
	## 有效实体 → 订阅 hp/stance/died + 立即按当前血量/架势初始化（MVP 无锁定系统，「当前锁定敌人」= 注入目标）。
	if entity == _target_enemy:
		return
	_disconnect_enemy()
	_target_enemy = entity
	if entity == null:
		EnemyHealthBar.visible = false
		EnemyStanceBar.visible = false
		return
	entity.hp_changed.connect(_on_enemy_hp_changed, CONNECT_REFERENCE_COUNTED)
	entity.stance_changed.connect(_on_enemy_stance_changed, CONNECT_REFERENCE_COUNTED)
	entity.stance_broken.connect(_on_enemy_stance_broken, CONNECT_REFERENCE_COUNTED)
	entity.died.connect(_on_enemy_died, CONNECT_REFERENCE_COUNTED)
	EnemyHealthBar.visible = true
	EnemyHealthBar.set_segments([entity.hp_1], [entity.life_1_max], 0)
	EnemyStanceBar.visible = true
	EnemyStanceBar.set_segments([entity.stance], [entity.stance_max], 0)


func set_debug_hp(hp_1: float, hp_2: float, active_life: int) -> void:
	## E2E/单测驱动：与 _on_player_hp_changed 同一处理路径（画条 + 低血边沿判定）
	_on_player_hp_changed(hp_1, hp_2, active_life)


func set_debug_stance(stance: float, stance_max: float) -> void:
	## E2E/单测驱动：玩家架势条直接更新
	PlayerStanceBar.set_segments([stance], [stance_max], 0)


func show_debug_hint(kind: String) -> void:
	## E2E/单测驱动："execute" → 处决提示；"kill" → 击杀提示（走同一显隐逻辑）
	if kind == "execute":
		_show_execute_hint()
	elif kind == "kill":
		_show_kill_hint()


# ── 信号处理（#575 契约逐条订阅）──────────────────────────────────────────

func _on_player_hp_changed(hp_1: float, hp_2: float, active_life: int) -> void:
	## ①两段条重绘（段1 [hp_1/LIFE_1_MAX] + 段2 [hp_2/LIFE_2_ABS] 同轴，活性段 = active_life）
	## ②低血边沿：活性条占比严格小于 HUD_LOW_HP_RATIO 时恰好一次 true/false 发射
	PlayerHealthBar.set_segments([hp_1, hp_2], [C.LIFE_1_MAX, C.LIFE_2_ABS], active_life - 1)
	var active_hp: float = hp_1 if active_life == 1 else hp_2
	var active_max: float = C.LIFE_1_MAX if active_life == 1 else C.LIFE_2_ABS
	var ratio: float = 1.0
	if active_max > 0.0:
		ratio = active_hp / active_max
	if not is_finite(ratio):
		ratio = 1.0
	var low: bool = ratio < C.HUD_LOW_HP_RATIO
	if low != _low_health:
		_low_health = low
		low_health_changed.emit(low)
		PlayerHealthBar.set_low_hp_mode(low)


func _on_player_stance_changed(stance: float, stance_max: float) -> void:
	PlayerStanceBar.set_segments([stance], [stance_max], 0)


func _on_enemy_stance_changed(stance: float, stance_max: float) -> void:
	EnemyStanceBar.set_segments([stance], [stance_max], 0)


func _on_enemy_hp_changed(hp_1: float, _hp_2: float, _active_life: int) -> void:
	## 敌人血量（#682）: 单段血条（段1 [hp_1 / life_1_max]），hp_changed 信号驱动
	EnemyHealthBar.set_segments([hp_1], [_target_enemy.life_1_max], 0)


func _on_enemy_stance_broken(_entity: CombatEntityScript) -> void:
	_show_execute_hint()


func _on_player_state_changed(_from: String, to: String) -> void:
	## 玩家攻击/处决 → 处决提示提前隐藏（PRD §4.4）
	if to in ["attack", "heavy_attack", "execute"]:
		_hide_execute_hint()


func _on_enemy_died(_entity: CombatEntityScript, is_final: bool) -> void:
	## 击杀 > 处决：final=true → 击杀提示 + 处决让位 + 敌人血条/架势条隐藏；
	## final=false（MVP 无复活敌人，防御）→ 仅隐藏处决提示 + 清空敌人血条/架势条
	if is_final:
		_show_kill_hint()
		_hide_execute_hint()
		EnemyHealthBar.visible = false
		EnemyStanceBar.visible = false
	else:
		_hide_execute_hint()
		EnemyHealthBar.set_segments([0.0], [1.0], 0)
		EnemyStanceBar.set_segments([0.0], [1.0], 0)


func _on_player_died(_entity: CombatEntityScript, _is_final: bool) -> void:
	## 无操作：血条表现由 hp_changed 自动驱动（died 时 hp 已归零）；不显示任何提示
	pass


func _on_player_revived(_entity: CombatEntityScript) -> void:
	## 无操作：revived 后 hp_changed(0, 50, 2) 到达驱动段2 半管亮起
	pass


# ── 提示显隐状态机（Tween 淡入淡出 + Timer 超时隐藏）────────────────────────

func _show_execute_hint() -> void:
	ExecutePromptLabel.text = _pick_hint(EXECUTE_HINTS)
	ExecutePromptLabel.modulate.a = 0.0
	ExecutePromptLabel.visible = true
	_kill_tween(_execute_hint_tween)
	_execute_hint_tween = create_tween()
	_execute_hint_tween.tween_property(ExecutePromptLabel, "modulate:a", 1.0, 0.15)
	_execute_hint_timer.start(C.STANCE_BREAK_RECOVERY_SEC)


func _show_kill_hint() -> void:
	KillPromptLabel.text = _pick_hint(KILL_HINTS)
	KillPromptLabel.modulate.a = 0.0
	KillPromptLabel.visible = true
	_kill_tween(_kill_hint_tween)
	_kill_hint_tween = create_tween()
	_kill_hint_tween.tween_property(KillPromptLabel, "modulate:a", 1.0, 0.15)
	_kill_hint_timer.start(C.HUD_KILL_HINT_SECONDS)


func _hide_execute_hint() -> void:
	_kill_tween(_execute_hint_tween)
	ExecutePromptLabel.visible = false


func _on_execute_hint_timeout() -> void:
	_kill_tween(_execute_hint_tween)
	_execute_hint_tween = create_tween()
	_execute_hint_tween.tween_property(ExecutePromptLabel, "modulate:a", 0.0, 0.3)
	_execute_hint_tween.finished.connect(_finish_execute_hide)


func _on_kill_hint_timeout() -> void:
	_kill_tween(_kill_hint_tween)
	_kill_hint_tween = create_tween()
	_kill_hint_tween.tween_property(KillPromptLabel, "modulate:a", 0.0, 0.3)
	_kill_hint_tween.finished.connect(_finish_kill_hide)


func _finish_execute_hide() -> void:
	ExecutePromptLabel.visible = false


func _finish_kill_hide() -> void:
	KillPromptLabel.visible = false


func _kill_tween(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()


func _pick_hint(candidates: Array) -> String:
	## B2 文案候选 5 选 1 草稿（implement 选首个，候选清单进 PR 待用户定稿）
	return str(candidates[0])


# ── 订阅管理（CONNECT_REFERENCE_COUNTED + 主动断开双保险）──────────────────

func _disconnect_player() -> void:
	if _player == null:
		return
	if not is_instance_valid(_player):
		_player = null
		return
	if _player.hp_changed.is_connected(_on_player_hp_changed):
		_player.hp_changed.disconnect(_on_player_hp_changed)
	if _player.stance_changed.is_connected(_on_player_stance_changed):
		_player.stance_changed.disconnect(_on_player_stance_changed)
	if _player.state_changed.is_connected(_on_player_state_changed):
		_player.state_changed.disconnect(_on_player_state_changed)
	if _player.died.is_connected(_on_player_died):
		_player.died.disconnect(_on_player_died)
	if _player.revived.is_connected(_on_player_revived):
		_player.revived.disconnect(_on_player_revived)


func _disconnect_enemy() -> void:
	if _target_enemy == null:
		return
	if not is_instance_valid(_target_enemy):
		_target_enemy = null
		return
	if _target_enemy.hp_changed.is_connected(_on_enemy_hp_changed):
		_target_enemy.hp_changed.disconnect(_on_enemy_hp_changed)
	if _target_enemy.stance_changed.is_connected(_on_enemy_stance_changed):
		_target_enemy.stance_changed.disconnect(_on_enemy_stance_changed)
	if _target_enemy.stance_broken.is_connected(_on_enemy_stance_broken):
		_target_enemy.stance_broken.disconnect(_on_enemy_stance_broken)
	if _target_enemy.died.is_connected(_on_enemy_died):
		_target_enemy.died.disconnect(_on_enemy_died)


# ── 内部类：_HudBar（Control _draw() 自绘条，零贴图）────────────────────────

class _HudBar:
	extends Control
	## 单条/多段同轴条：bg(墨黑 60% alpha) + 1px 月白描边(无圆角) + 逐段填充。
	## 段数组与活性索引由 set_segments() 注入；queue_redraw() 驱动重绘（零 _process）。
	## 常量复用外层 Hud 的 C（GDScript 内层类禁止重名 const 遮蔽，直接访问外层）。

	var _values: Array = []
	var _maxes: Array = []
	var _active_index: int = 0      # 活性段（高亮月白）；非活性段暗显墨黑
	var _low_hp_mode: bool = false  # 低血：活性段填充+描边转 HUD_BLOOD_RED
	var _fill_override: Color = Color.TRANSPARENT  # #682: 填充色覆写（EnemyHealthBar 暗红条）
	var _use_fill_override: bool = false           # #682: 覆写开关（默认关闭 → 既有行为零变化）

	func set_segments(values: Array, maxes: Array, active_index: int) -> void:
		_values = values
		_maxes = maxes
		_active_index = active_index
		queue_redraw()

	func set_fill_color(color: Color) -> void:
		## #682 additive: 覆写活性段填充色（EnemyHealthBar 用 HUD_BLOOD_RED；玩家条不调用 → 默认零变化）
		_fill_override = color
		_use_fill_override = true
		queue_redraw()

	func set_low_hp_mode(enabled: bool) -> void:
		_low_hp_mode = enabled
		queue_redraw()

	func get_segment_fractions() -> Array:
		## 逐段 value/max 夹取 [0,1]；max<=0 防御返回 1.0；非有限值（NaN/Inf）返回 0.0
		var out: Array = []
		for i in _values.size():
			var v: float = _values[i]
			var m: float = _maxes[i]
			var frac: float = 1.0
			if m > 0.0:
				frac = v / m
			if not is_finite(frac):
				frac = 0.0
			out.append(clampf(frac, 0.0, 1.0))
		return out

	func get_segment_shares() -> Array:
		## 逐段宽度占比 = maxes[i] / sum(maxes)（[100,50] → 2:1 严格比）；sum<=0 防御均分
		var sum: float = 0.0
		for m in _maxes:
			sum += m
		var out: Array = []
		if sum <= 0.0:
			var eq: float = 1.0 / float(maxi(_maxes.size(), 1))
			for i in _maxes.size():
				out.append(eq)
			return out
		for m in _maxes:
			out.append(m / sum)
		return out

	func get_active_index() -> int:
		return _active_index

	func _draw() -> void:
		var rect: Rect2 = Rect2(Vector2.ZERO, size)
		draw_rect(rect, Color(C.HUD_INK_BLACK, 0.6), true)
		var border_color: Color = C.HUD_BLOOD_RED if _low_hp_mode else C.HUD_MOON_WHITE
		draw_rect(rect, border_color, false, 1.0)
		var shares: Array = get_segment_shares()
		var fracs: Array = get_segment_fractions()
		var x: float = 0.0
		for i in _maxes.size():
			var seg_w: float = size.x * shares[i] * fracs[i]
			if seg_w > 0.0:
				var fill_color: Color
				if i == _active_index:
					## #682 additive: fill_override（EnemyHealthBar 暗红）优先，默认走既有低血/月白逻辑
					fill_color = _fill_override if _use_fill_override else (C.HUD_BLOOD_RED if _low_hp_mode else C.HUD_MOON_WHITE)
				else:
					fill_color = _inactive_color()
				draw_rect(Rect2(Vector2(x, 0.0), Vector2(seg_w, size.y)), fill_color, true)
			x += size.x * shares[i]

	func _inactive_color() -> Color:
		## 非活性段暗显：墨黑提亮（细条内可读，不抢活性段）
		return C.HUD_INK_BLACK.lightened(0.4)
