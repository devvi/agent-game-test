extends Node2D
class_name ReactionController
## ReactionController — 打击反馈组合触发核心（#579，AC2）。
## 归属: docs/DESIGN/579-combat-feedback-system.md §2.1
## 职责: 单一入口 trigger_feedback(event, data) 在同一帧内组合触发五效果组件
##   （火花 / hit-stop 时间栈 / 屏震 / 白闪双通道 / S 级刀光）—— AC2「四要素同帧」的结构性保证。
##   只消费信号，不做判定（#577/#580 职责）；只发 feedback_played 信号不发声（#593 职责）。
## 事件源:
##   - CombatJudge 五结果事件（bind_judge 直连，source:"judgment"）
##   - CombatEntity 6 信号（subscribe_entity，state_changed 闭包捕获实体 D2/D4，source:"combat_entity"）
##   - execute（#580 未来 / 测试 / E2E rig 注入）
## FEEDBACK_MATRIX 全部指向 constants FEEDBACK_*（# DRAFT 候补值，定稿归 #584/用户，禁止实现期定稿）。
## 红线: Engine.time_scale 只经 TimeScaleStack 写入；全屏淡白闪仅 A- 级路径可达。

const C = preload("res://gdscripts/constants.gd")

## #593 音效 hook 契约（本 issue 只发信号，不发声）
signal feedback_played(event: String, level: String, data: Dictionary)

## 分级矩阵（event → 参数包）: 数据全部指向 constants FEEDBACK_*（# DRAFT）。
## 闪/慢动作字典直接引用常量；flash 字面值必须与 FEEDBACK_FLASH 常量一致（A4 anti-arcade 断言）。
const FEEDBACK_MATRIX: Dictionary = {
	"execute": {"level": "S", "spark": true, "hitstop": C.FEEDBACK_HITSTOP_MS, "shake": C.FEEDBACK_SHAKE_PX, "slowmo": C.FEEDBACK_SLOWMO, "flash": {}},
	"parry_success": {"level": "A", "spark": true, "hitstop": C.FEEDBACK_HITSTOP_MS, "shake": C.FEEDBACK_SHAKE_PX, "slowmo": C.FEEDBACK_SLOWMO, "flash": C.FEEDBACK_FLASH["A"]},
	"stance_broken": {"level": "A_", "spark": false, "hitstop": C.FEEDBACK_HITSTOP_MS, "shake": C.FEEDBACK_SHAKE_PX, "slowmo": C.FEEDBACK_SLOWMO, "flash": {"screen": true, "alpha": C.FEEDBACK_FLASH["A_"]["alpha"], "ms": C.FEEDBACK_FLASH["A_"]["ms"]}},
	"block_held": {"level": "B", "spark": true, "hitstop": C.FEEDBACK_HITSTOP_MS, "shake": C.FEEDBACK_SHAKE_PX, "slowmo": {}, "flash": {}},
	"hit_landed": {"level": "C", "spark": true, "hitstop": C.FEEDBACK_HITSTOP_MS, "shake": C.FEEDBACK_SHAKE_PX, "slowmo": {}, "flash": {}},
	"player_hit": {"level": "C", "tier": "PH", "spark": false, "hitstop": C.FEEDBACK_HITSTOP_MS, "shake": C.FEEDBACK_SHAKE_PX, "slowmo": {}, "flash": {}},
	"clash": {"level": "B", "spark": true, "hitstop": C.FEEDBACK_HITSTOP_MS, "shake": C.FEEDBACK_SHAKE_PX, "slowmo": {}, "flash": {}},
	"revive": {"level": "C", "spark": false, "hitstop": C.FEEDBACK_HITSTOP_MS, "shake": C.FEEDBACK_SHAKE_PX, "slowmo": {}, "flash": {}},
	"death": {"level": "C", "tier": "PH", "spark": false, "hitstop": C.FEEDBACK_HITSTOP_MS, "shake": C.FEEDBACK_SHAKE_PX, "slowmo": {}, "flash": {}},
}

## 屏震目标相机（战斗场景 #583 / E2E rig 注入；null 时 ScreenShake no-op）
@export var camera_path: NodePath
## E2E 冻结效果帧模式: 开启后 _process 跳过时间栈 tick（hit-stop 保持冻结供截图，AC2 兜底）
@export var freeze_time_stack: bool = false

var _spark = null          # FeedbackSpark
var _shake = null          # ScreenShake
var _flash = null          # FlashEffect
var _time_stack = null     # TimeScaleStack（RefCounted，非 Node）
var _judge_bound: bool = false
var _entities: Array = []


func _ready() -> void:
	## 代码创建子组件（零 .tres；TimeScaleStack 为 RefCounted，不挂节点树）
	var spark_script: GDScript = load("res://gdscripts/feedback_spark.gd")
	if spark_script != null:
		_spark = spark_script.new()
		add_child(_spark)
	var shake_script: GDScript = load("res://gdscripts/screen_shake.gd")
	if shake_script != null:
		_shake = shake_script.new()
		_shake.camera_path = camera_path
		add_child(_shake)
	var flash_script: GDScript = load("res://gdscripts/flash_effect.gd")
	if flash_script != null:
		_flash = flash_script.new()
		add_child(_flash)
	var stack_script: GDScript = load("res://gdscripts/time_scale_stack.gd")
	if stack_script != null:
		_time_stack = stack_script.new()


func trigger_feedback(event: String, data: Dictionary = {}) -> void:
	## 事件注入唯一入口（#577/#580/测试/E2E rig 共用）。未知事件 → push_warning + no-op（边界 6）。
	## data 键约定: position/normal（AC3 碰撞点直传，缺省 → _derive_impact_point 推导）/
	##   target_entity（受击实体，白闪用）/ attacker_entity（方向兜底）/ direction（facing）/
	##   direction_vec（屏震方向覆盖）/ source。
	## 组合触发单帧完成（AC2）: spark → hit-stop → slowmo（嵌套，D1 min）→ shake → flash → S 级刀光。
	if not FEEDBACK_MATRIX.has(event):
		push_warning("ReactionController: unknown event '%s' — no-op" % event)
		return
	var pack: Dictionary = FEEDBACK_MATRIX[event]
	var level: String = str(pack.get("level", ""))
	var position: Vector2 = Vector2.ZERO
	var normal: Vector2 = Vector2.ZERO
	if data.has("position") and data.has("normal"):
		position = data["position"]
		normal = data["normal"]
	else:
		var attacker_entity: Node = data.get("attacker_entity", null)
		var target_entity: Node = data.get("target_entity", null)
		var direction: int = int(data.get("direction", 1))
		var derived: Dictionary = _derive_impact_point(attacker_entity, target_entity, direction)
		position = derived["position"]
		normal = derived["normal"]
	var hitstop_ms: int = int(C.FEEDBACK_HITSTOP_MS.get(level, int(C.FEEDBACK_HITSTOP_MS.get("C", 0))))
	var shake_px: float = float(C.FEEDBACK_SHAKE_PX.get(level, 1.0))
	var slowmo: Variant = C.FEEDBACK_SLOWMO.get(level, {})
	# 参数 tier: 默认 = 等级；player_hit/death 走 PH 档（矩阵「60ms / 4px」= FEEDBACK_* 的 PH 键，非 C 档）
	var tier: String = str(pack.get("tier", level))
	if tier != level:
		hitstop_ms = int(C.FEEDBACK_HITSTOP_MS.get(tier, hitstop_ms))
		shake_px = float(C.FEEDBACK_SHAKE_PX.get(tier, shake_px))
	# ── 同帧并行组合（AC2）──────────────────────────────────────────────
	if bool(pack.get("spark", false)) and _spark != null:
		_spark.burst_at(position, normal, level)
	if hitstop_ms > 0 and _time_stack != null:
		_time_stack.push(0.05, hitstop_ms)
	if slowmo is Dictionary and not (slowmo as Dictionary).is_empty() and _time_stack != null:
		_time_stack.push(float((slowmo as Dictionary)["scale"]), int((slowmo as Dictionary)["ms"]))
	var shake_dir: Vector2 = data.get("direction_vec", normal if normal != Vector2.ZERO else Vector2(1, 0))
	if _shake != null:
		_shake.shake(shake_px, shake_dir)
	var flash: Variant = pack.get("flash", {})
	if flash is Dictionary and not (flash as Dictionary).is_empty():
		if (flash as Dictionary).has("screen"):
			if _flash != null:
				_flash.flash_screen(float((flash as Dictionary)["alpha"]), int((flash as Dictionary)["ms"]))
		elif data.has("target_entity"):
			var target: Node = data["target_entity"]
			if is_instance_valid(target) and _flash != null:
				_flash.flash_entity(target, float((flash as Dictionary)["alpha"]), int((flash as Dictionary)["ms"]))
	if event == "execute":
		_trigger_execute_arc(data)
	emit_signal("feedback_played", event, level, data)


func bind_judge(judge: Node) -> void:
	## 五结果事件直连（#577）: has_signal 防护，handler → trigger_feedback(source:"judgment")。
	if judge == null:
		return
	if judge.has_signal("parry_success"):
		judge.parry_success.connect(_on_parry_success)
	if judge.has_signal("block_held"):
		judge.block_held.connect(_on_block_held)
	if judge.has_signal("hit_landed"):
		judge.hit_landed.connect(_on_hit_landed)
	if judge.has_signal("clash"):
		judge.clash.connect(_on_clash)
	if judge.has_signal("stance_broken"):
		judge.stance_broken.connect(_on_judge_stance_broken)
	_judge_bound = true


func subscribe_entity(entity: Node) -> void:
	## 6 信号订阅（#575）: _entities 查重（边界 10）；state_changed 闭包捕获实体（D2/D4）。
	if entity == null or _entities.has(entity):
		return
	_entities.append(entity)
	if entity.has_signal("state_changed"):
		entity.state_changed.connect(func(from, to): _on_state_changed(from, to, entity))
	if entity.has_signal("stance_broken"):
		entity.stance_broken.connect(func(e): _on_stance_broken(e))
	if entity.has_signal("died"):
		entity.died.connect(func(e, final): _on_died(e, final))
	if entity.has_signal("revived"):
		entity.revived.connect(func(e): _on_revived(e))


func _process(_delta: float) -> void:
	## 墙钟兜底轮询（AC4 机械保证）: 冻结模式下跳过（hit-stop 保持冻结供截图）。
	if not freeze_time_stack and _time_stack != null:
		_time_stack.tick(Time.get_ticks_msec())


# ── 判定事件 handler（bind_judge）────────────────────────────────────────

func _on_parry_success(defender, attacker, stance_damage) -> void:
	trigger_feedback("parry_success", {"target_entity": defender, "attacker_entity": attacker, "source": "judgment"})


func _on_block_held(defender, attacker, stance_cost) -> void:
	trigger_feedback("block_held", {"target_entity": defender, "attacker_entity": attacker, "source": "judgment"})


func _on_hit_landed(defender, attacker, hp_damage, stance_damage) -> void:
	trigger_feedback("hit_landed", {"target_entity": defender, "attacker_entity": attacker, "source": "judgment"})


func _on_clash(a, b, stance_cost) -> void:
	trigger_feedback("clash", {"target_entity": a, "attacker_entity": b, "source": "judgment"})


func _on_judge_stance_broken(entity) -> void:
	trigger_feedback("stance_broken", {"target_entity": entity, "source": "judgment"})


# ── 实体信号 handler（subscribe_entity，降级路径 Flow 3）──────────────────

func _on_state_changed(from: String, to: String, entity: Node) -> void:
	## 降级路径（#577 未连接时驱动）: guard→block_held / parry_success→parry_success /
	##   stagger→player_hit|hit_landed（D4 身份判定）/ stance_break→stance_broken。
	if to == "guard":
		trigger_feedback("block_held", {"target_entity": entity, "source": "combat_entity"})
	elif to == "parry_success":
		trigger_feedback("parry_success", {"target_entity": entity, "source": "combat_entity"})
	elif to == "stagger":
		var is_player: bool = false
		if entity != null and entity.get("is_player") != null:
			is_player = bool(entity.get("is_player"))
		if is_player:
			trigger_feedback("player_hit", {"target_entity": entity, "source": "combat_entity"})
		else:
			trigger_feedback("hit_landed", {"target_entity": entity, "source": "combat_entity"})
	elif to == "stance_break":
		trigger_feedback("stance_broken", {"target_entity": entity, "source": "combat_entity"})


func _on_stance_broken(entity: Node) -> void:
	trigger_feedback("stance_broken", {"target_entity": entity, "source": "combat_entity"})


func _on_died(entity: Node, final: bool) -> void:
	if final:
		trigger_feedback("death", {"target_entity": entity, "source": "combat_entity"})


func _on_revived(entity: Node) -> void:
	trigger_feedback("revive", {"target_entity": entity, "source": "combat_entity"})


# ── 碰撞点推导（AC3 / 边界 8）───────────────────────────────────────────

func _derive_impact_point(attacker: Node, defender: Node, direction: int) -> Dictionary:
	## 刀与刀交点: 两 SwordPivot 全局位置中点（非角色中心，AC3）+ 法线 Vector2(0, -direction)。
	## 推导失败（无 pivot / 攻击方失效）→ 回退 attacker.global_position + facing 方向 + push_warning。
	if attacker == null or not is_instance_valid(attacker):
		var fallback: Vector2 = defender.global_position if (defender != null and is_instance_valid(defender)) else Vector2.ZERO
		push_warning("ReactionController: attacker missing/invalid, fallback to defender position")
		return {"position": fallback, "normal": Vector2(0, -1)}
	var a_pivot: Node = attacker.get_node_or_null("TorsoPivot/SwordPivot")
	if a_pivot == null:
		a_pivot = attacker.get_node_or_null("StickFigure/TorsoPivot/SwordPivot")
	var d_pivot: Node = null
	if defender != null and is_instance_valid(defender):
		d_pivot = defender.get_node_or_null("TorsoPivot/SwordPivot")
		if d_pivot == null:
			d_pivot = defender.get_node_or_null("StickFigure/TorsoPivot/SwordPivot")
	if a_pivot != null and d_pivot != null:
		var midpoint: Vector2 = (a_pivot.global_position + d_pivot.global_position) / 2.0
		return {"position": midpoint, "normal": Vector2(0, -direction)}
	push_warning("ReactionController: SwordPivot missing, fallback to attacker position + facing")
	return {"position": attacker.global_position, "normal": Vector2(direction, 0)}


# ── S 级处决刀光复用（#574）─────────────────────────────────────────────

func _trigger_execute_arc(data: Dictionary) -> void:
	## S 级处决: 触发目标刀身上的 SwordArc.trigger_burst()（只调用不改实现）。
	var target: Node = data.get("target_entity", null)
	if target == null or not is_instance_valid(target):
		return
	var arc: Node = target.get_node_or_null("StickFigure/TorsoPivot/SwordPivot/SwordArc")
	if arc == null:
		arc = target.get_node_or_null("TorsoPivot/SwordPivot/SwordArc")
	if arc != null and arc.has_method("trigger_burst"):
		arc.call("trigger_burst")
