extends Node
class_name CombatJudge
## CombatJudge — 判定协调器 (#577)。
## 归属: docs/DESIGN/577-parry-clash-stance-break.md §2.3
## 职责: 攻击窗口登记 → 命中裁决（弹反→拼刀→格挡→受击）→ 调用实体接口 →
##   发射五结果事件。不做渲染/演出/音效（#579/#593）/状态机/数据存储（#575）/输入采集（#573）。
## 裁决顺序全部走常量（CLASH_PRIORITY 短路），禁止字面量。
## 事件契约（§2.3）: parry_success / block_held / hit_landed / clash / stance_broken。

const C = preload("res://gdscripts/constants.gd")
const AttackWindowScript = preload("res://gdscripts/combat_attack_window.gd")

## 五结果事件（与 issue body 逐字对齐；实体参数 untyped Object——headless class_name 解析不可靠）
signal parry_success(defender, attacker, stance_damage: float)
signal block_held(defender, attacker, stance_cost: float)
signal hit_landed(defender, attacker, hp_damage: float, stance_damage: float)
signal clash(entity_a, entity_b, stance_cost: float)
signal stance_broken(entity)

var player = null      # bind_entities 注入（防御者=玩家，弹反/格挡/受击裁决对象）
var enemy = null       # bind_entities 注入（攻击者=敌人，MVP 单敌）
var _ic = null         # InputController 引用（bind_input 注入；headless 可 null）
var _frame: int = 0    # 逻辑帧计数（_process 推进；headless 测试手动 tick_frame()）
var _windows: Array = []       # 活跃 AttackWindow 列表（按 attacker 去重）
var _last_guard_press_ms: int = -1   # 最近 guard_pressed 时间戳（弹反窗口比对）
var _forwarded_stance_break: Dictionary = {}   # 实体 → 已转发标记（stance_broken 幂等转发）
var _resolved: Dictionary = {}       # "attacker:defender:frame" → true（防重入/防双罚）


func bind_entities(p, e) -> void:
	## 保存引用 + 订阅双方 state_changed（登记攻击窗口）/ stance_broken（转发）。
	## state_changed 用 .bind(p)：Godot 将绑定参数追加到信号参数之后 → 处理函数收到
	##   (from, to, entity)；stance_broken 处理函数恰为 1 参，直接连接（bind 会多传一参报错）。
	player = p
	enemy = e
	if p != null:
		p.state_changed.connect(_on_entity_state_changed.bind(p))
		p.stance_broken.connect(_on_stance_broken)
	if e != null:
		e.state_changed.connect(_on_entity_state_changed.bind(e))
		e.stance_broken.connect(_on_stance_broken)


func bind_input(ic) -> void:
	## 订阅 guard_pressed(timestamp_ms)（记 _last_guard_press_ms）/ guard_held（MVP 参考）
	_ic = ic
	if ic == null:
		return
	if ic.has_signal("guard_pressed"):
		ic.guard_pressed.connect(_on_guard_pressed)
	if ic.has_signal("guard_held"):
		ic.guard_held.connect(_on_guard_held)


func register_attack_window(w) -> void:
	## 登记窗口：同 attacker 已有窗口 → 旧窗口作废（连段/重攻击覆盖语义）；窗口加入 _windows
	for i in range(_windows.size() - 1, -1, -1):
		if _windows[i].attacker == w.attacker:
			_windows.remove_at(i)
	_windows.append(w)


func resolve_attack(attacker, defender) -> void:
	## 幂等裁决入口（防重入键 "attacker:defender:frame"，已裁决 → no-op）。
	## 裁决顺序（全部走常量，禁止写死）: 弹反 > 拼刀 > 格挡 > 受击（CLASH_PRIORITY 短路）。
	if player == null or enemy == null:
		push_warning("CombatJudge: not bound")
		return
	var key: String = "%d:%d:%d" % [attacker.get_instance_id(), defender.get_instance_id(), _frame]
	if _resolved.has(key):
		return
	var w = _active_window_for(attacker)
	if w == null:
		push_warning("CombatJudge: no active window for attacker")
		_resolved[key] = true
		return
	# 跳过守卫（先于任何伤害/事件）: dead/revive/execute 态 + 无敌期
	if defender.state_name == "dead" or defender.state_name == "revive" or defender.state_name == "execute":
		_resolved[key] = true
		return
	if defender._invincible_until_sec > Time.get_ticks_msec() / 1000.0:
		_resolved[key] = true
		return
	# 距离挥空 / facing 反向（mark resolved + return，不发射任何事件）
	if absf(defender.position.x - attacker.position.x) > float(C.HITBOX_RANGE):
		_resolved[key] = true
		return
	var dx: float = defender.position.x - attacker.position.x
	if dx != 0.0:
		var rel_dir: int = 1 if dx > 0.0 else -1
		if rel_dir != w.direction:
			_resolved[key] = true
			return
	# 弹反判定（仅玩家防御者）: 时间戳窗闭区间 [hit_ms - PARRY_WINDOW_SECONDS*1000, hit_ms] + facing 校验
	var hit_ms: int = int(w.hit_frame() * 1000.0 / float(C.FRAME_RHYTHM_BASE))
	var parry_ok: bool = false
	if defender == player:
		var lower_ms: int = hit_ms - int(C.PARRY_WINDOW_SECONDS * 1000.0)
		parry_ok = _last_guard_press_ms >= 0 and _last_guard_press_ms >= lower_ms and _last_guard_press_ms <= hit_ms
		if parry_ok and int(C.PARRY_DIRECTION_TOLERANCE) == 1:
			parry_ok = defender.facing == -w.direction
	var reversed_key: String = "%d:%d:%d" % [defender.get_instance_id(), attacker.get_instance_id(), _frame]
	var clash_first: bool = int(C.CLASH_PRIORITY) != 0
	if clash_first:
		if _resolve_clash(attacker, defender, key, reversed_key):
			return
		if _resolve_parry(attacker, defender, parry_ok, key, reversed_key):
			return
	else:
		if _resolve_parry(attacker, defender, parry_ok, key, reversed_key):
			return
		if _resolve_clash(attacker, defender, key, reversed_key):
			return
	# 格挡: defender 处于 guard 态（guard_held 语义，含弹反失败后的持续格挡）
	if defender.state_name == "guard":
		defender.take_stance_damage(float(C.POSTURE_BLOCK_COST))
		emit_signal("block_held", defender, attacker, float(C.POSTURE_BLOCK_COST))
		_resolved[key] = true
		return
	# 受击（兜底）
	defender.take_damage(w.hp_damage)
	defender.take_stance_damage(w.stance_damage)
	emit_signal("hit_landed", defender, attacker, w.hp_damage, w.stance_damage)
	_resolved[key] = true


func _process(_delta: float) -> void:
	tick_frame()


func tick_frame() -> void:
	## 逻辑帧推进：命中帧到达 → resolve_attack；过期窗口清理（headless 测试手动调用）
	_frame += 1
	var snapshot: Array = _windows.duplicate()
	for win in snapshot:
		if win.is_active(_frame):
			resolve_attack(win.attacker, _other(win.attacker))
	var i: int = 0
	while i < _windows.size():
		if _windows[i].is_expired(_frame):
			_windows.remove_at(i)
		else:
			i += 1


func _other(attacker) -> Object:
	return enemy if attacker == player else player


func _active_window_for(attacker) -> Object:
	for win in _windows:
		if win.attacker == attacker and win.is_active(_frame):
			return win
	return null


func _resolve_parry(attacker, defender, parry_ok: bool, key: String, reversed_key: String) -> bool:
	## 弹反成功：玩家 0 伤害（不调 take_damage）+ 敌架势扣 PARRY_STANCE_DAMAGE
	##   + 玩家 request_transition("parry_success") + 发射事件；双向键防重入
	if defender != player or not parry_ok:
		return false
	enemy.take_stance_damage(float(C.PARRY_STANCE_DAMAGE))
	player.request_transition("parry_success")
	emit_signal("parry_success", player, enemy, float(C.PARRY_STANCE_DAMAGE))
	_resolved[key] = true
	_resolved[reversed_key] = true
	return true


func _resolve_clash(attacker, defender, key: String, reversed_key: String) -> bool:
	## 拼刀：defender 自身窗口同帧 active → 双方各扣 CLASH_STANCE_COST + clash 事件；双向键防重入
	var clash_window = null
	for win in _windows:
		if win.attacker == defender and win.is_active(_frame):
			clash_window = win
			break
	if clash_window == null:
		return false
	attacker.take_stance_damage(float(C.CLASH_STANCE_COST))
	defender.take_stance_damage(float(C.CLASH_STANCE_COST))
	emit_signal("clash", attacker, defender, float(C.CLASH_STANCE_COST))
	_resolved[key] = true
	_resolved[reversed_key] = true
	return true


func _on_entity_state_changed(_from: String, to: String, entity) -> void:
	## state_changed 订阅（.bind 追加 → Godot 实参顺序 from, to, entity）。
	## to ∈ {attack, heavy_attack} → 自动构造 AttackWindow 登记（玩家；敌人 #581 参数化接入）
	if to != "attack" and to != "heavy_attack":
		return
	var w = AttackWindowScript.new()
	w.attacker = entity
	w.start_frame = _frame
	w.active_frames = int(C.HITBOX_ACTIVE_FRAMES)
	var is_enemy: bool = entity != null and entity.get("is_player") != null and not entity.is_player
	w.hp_damage = float(entity.current_hp_damage) if (entity != null and entity.current_hp_damage >= 0.0) \
		else float(entity.attack_hp_damage) if (entity != null and entity.attack_hp_damage >= 0.0) \
		else float(C.SWORD_DAMAGE_HEAVY if to == "heavy_attack" else C.SWORD_DAMAGE_LIGHT)
	w.stance_damage = float(entity.attack_stance_damage) if (entity != null and entity.attack_stance_damage >= 0.0) \
		else float(C.POSTURE_HIT_COST)
	if is_enemy:
		## 敌人前摇（AC1: 12 帧可弹反）；#682 蓄力重斩 override fallback 链——≥0 用 override，否则默认
		var wu: int = int(entity.current_windup_frames) if (entity.current_windup_frames >= 0) else int(C.ENEMY_ATTACK_WINDUP)
		w.windup_frames = wu
	w.direction = entity.facing
	register_attack_window(w)


func _on_guard_pressed(timestamp_ms: int) -> void:
	## 记录最近 guard_pressed 时间戳（同帧多次按下取最后一次——帧级去抖）
	_last_guard_press_ms = timestamp_ms


func _on_guard_held() -> void:
	## MVP 参考信号（格挡态判定直接读 defender.state_name == "guard"，保留订阅以备 #584 细化）
	pass


func _on_stance_broken(entity) -> void:
	## 幂等转发: 同一实体已转发 → no-op；否则 emit stance_broken(entity)（统一事件出口）
	var id: String = str(entity.get_instance_id())
	if _forwarded_stance_break.has(id):
		return
	_forwarded_stance_break[id] = true
	emit_signal("stance_broken", entity)
