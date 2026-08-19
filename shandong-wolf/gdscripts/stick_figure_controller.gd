extends Node2D
## StickFigureController — 火柴人动画调度 + consume_state 契约（#574）。
## 归属: docs/DESIGN/574-stick-figure-silhouette-animation.md §2.3（consume_state + 动画资源动态生成）
## 设计要点:
##   - 场景根（player_stick_figure.tscn 根节点）: 持有 StickFigure + AnimationPlayer
##   - consume_state(state) 唯一动画入口（issue 输入驱动契约: 不读 Input、不订阅 #573 信号）
##     * state 先过映射表（canonical 11 态 + run→move / parry→guard 别名）
##     * 未知状态 → 降级 anim_idle + push_warning（§5-1）
##     * 同态重入（当前 clip 相同）→ 重置到该 clip 前摇首帧（连招语义，§5-3）
##     * 播放前 stop 旧 clip（防叠播，§5-8）
##   - 动画资源运行时动态生成（零 .tres，AC3/AC5）: 11 个 anim_* clip 关键帧时间戳全部
##     从 FRAME_ANIM_* 常量派生（帧数 / FRAME_RHYTHM_BASE=60）
##   - attack 三段: 前摇 [0,8/60] 蓄力下沉 → 暴发 [8/60,12/60] 挥砍 + SwordArc.trigger_burst()
##     → 收招 [12/60,22/60] 滞刀回位（帧间距不对称 = 「起势慢→爆发快→收招滞」，配方 §6.5）
##   - 过渡 ≤2 帧策略（AC1）: 直接 play() + 「clip 首帧姿态 = 上一状态尾帧姿态」设计约定；
##     跳变大的转移以 clip 首帧衔接为主（C2 可回归），不引入额外插值复杂度
##   - 动画状态对象集: stick_figure_anim_states.gd（派生 StateMachineBase，§2.4）——
##     战斗状态机权威归 #575，本文件只做镜像映射 + 最小调度

class_name StickFigureController

const C = preload("res://gdscripts/constants.gd")
const AnimStatesScript = preload("res://gdscripts/stick_figure_anim_states.gd")
const StateMachineBaseScript = preload("res://gdscripts/state_machine.gd")

## 状态名→clip 映射表（canonical 11 态，权威源 = #575 战斗状态机；本层为镜像映射，单点同步）
const STATE_TO_CLIP: Dictionary = {
	"idle": "anim_idle",
	"move": "anim_move",
	"attack": "anim_attack",
	"heavy_attack": "anim_heavy_attack",
	"guard": "anim_guard",
	"parry_success": "anim_parry_success",
	"stagger": "anim_stagger",
	"stance_break": "anim_stance_break",
	"execute": "anim_execute",
	"revive": "anim_revive",
	"dead": "anim_dead",
}

## 别名（issue body 明文声明）: run → move（移动共用步态）；parry → guard（格挡/弹反共用姿态）
const STATE_ALIASES: Dictionary = {
	"run": "move",
	"parry": "guard",
}

const FIGURE_PATH_PREFIX: String = "StickFigure"

var _figure: Node2D = null
var _anim: AnimationPlayer = null
var _anim_fsm: Object = null

# attack 三段时间边界（秒，供动画状态对象 / E2E 截图像具消费；constants 派生）
var attack_windup_end: float = 0.0
var attack_burst_end: float = 0.0
var attack_total_end: float = 0.0


func _ready() -> void:
	_figure = get_node_or_null("StickFigure")
	_anim = get_node_or_null("AnimationPlayer")
	if _figure == null:
		push_warning("StickFigureController: missing child 'StickFigure'")
	if _anim == null:
		push_warning("StickFigureController: missing child 'AnimationPlayer'")
	_attack_bounds_from_constants()
	_build_all_clips()
	_anim_fsm = StateMachineBaseScript.new()


func _process(delta: float) -> void:
	## 最小调度: 转发给当前动画状态对象（Attack 态推进 phase）
	if _anim_fsm != null:
		_anim_fsm.update(delta)


func _attack_bounds_from_constants() -> void:
	var rhythm: float = float(C.FRAME_RHYTHM_BASE)
	attack_windup_end = float(C.FRAME_ANIM_ATTACK_WINDUP) / rhythm
	attack_burst_end = float(C.FRAME_ANIM_ATTACK_WINDUP + C.FRAME_ANIM_ATTACK_BURST) / rhythm
	attack_total_end = float(C.FRAME_ANIM_ATTACK_WINDUP + C.FRAME_ANIM_ATTACK_BURST + C.FRAME_ANIM_ATTACK_RECOVERY) / rhythm


# ── consume_state 契约（唯一动画入口）──────────────────────────────────────

func consume_state(state: String) -> void:
	## 唯一动画入口: 映射（canonical + 别名 + 未知降级）→ 同态重入重置 → play
	var canonical: String = _resolve_canonical(state)
	var clip: String = STATE_TO_CLIP[canonical]
	if _anim != null and _anim.current_animation == clip:
		play_clip(clip)  # 同态重入: 重置到该 clip 前摇首帧（连招语义，§5-3）
		return
	if _anim_fsm != null:
		var state_obj: Object = AnimStatesScript.make_state(canonical, self)
		_anim_fsm.transition_to(state_obj)  # enter() → play_clip(clip)
	else:
		play_clip(clip)


func _resolve_canonical(state: String) -> String:
	## 映射表只认 canonical 11 态；别名显式映射；未知 → 降级 idle + push_warning（§5-1）
	if STATE_TO_CLIP.has(state):
		return state
	if STATE_ALIASES.has(state):
		return STATE_ALIASES[state]
	push_warning("StickFigureController: unknown state '%s', fallback idle" % state)
	return "idle"


func play_clip(clip: String) -> void:
	## 供动画状态对象调用（§2.4）: 播放前 stop 旧 clip（防叠播，§5-8）；clip 缺失 → 降级 idle（§5-9）
	if _anim == null:
		return
	_anim.stop()
	if not _anim.has_animation(clip):
		push_warning("StickFigureController: clip '%s' missing, fallback idle" % clip)
		clip = "anim_idle"
	_anim.play(clip)
	_anim.seek(0.0)


func trigger_sword_arc() -> void:
	## 暴发段刀光入口（#579 打击反馈可复用；本层由 attack clip method track 触发）
	if _figure == null:
		return
	var arc: Polygon2D = _figure.get_node_or_null("TorsoPivot/SwordPivot/SwordArc")
	if arc != null and arc.has_method("trigger_burst"):
		arc.call("trigger_burst")


# ── 动画资源动态生成（零 .tres，AC3/AC5）───────────────────────────────────

func _build_all_clips() -> void:
	if _anim == null:
		return
	var lib: AnimationLibrary = null
	if _anim.has_animation_library(""):
		lib = _anim.get_animation_library("")
	else:
		lib = AnimationLibrary.new()
		_anim.add_animation_library("", lib)
	var specs: Array = [
		_build_idle_spec(),
		_build_move_spec(),
		_build_attack_spec(),
		_build_heavy_attack_spec(),
		_build_guard_spec(),
		_build_parry_success_spec(),
		_build_stagger_spec(),
		_build_stance_break_spec(),
		_build_execute_spec(),
		_build_revive_spec(),
		_build_dead_spec(),
	]
	for spec in specs:
		var anim: Animation = _build_clip(spec)
		lib.add_animation(str(spec["name"]), anim)


func _build_clip(spec: Dictionary) -> Animation:
	## 运行时构建 Animation 对象（零 .tres 文件）: 关键帧时间戳 = 帧数 / FRAME_RHYTHM_BASE
	var anim: Animation = Animation.new()
	var frames: int = int(spec["frames"])
	anim.length = float(frames) / float(C.FRAME_RHYTHM_BASE)
	if bool(spec.get("loop", false)):
		anim.loop_mode = Animation.LOOP_LINEAR
	var rotations: Dictionary = spec.get("rotations", {})
	for pivot_path in rotations.keys():
		var keys: Array = rotations[pivot_path]
		var track: int = anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(track, "%s/%s:rotation" % [FIGURE_PATH_PREFIX, str(pivot_path)])
		for key in keys:
			var f: int = int(key[0])
			var deg: float = float(key[1])
			anim.track_insert_key(track, float(f) / float(C.FRAME_RHYTHM_BASE), deg_to_rad(deg))
	var positions: Dictionary = spec.get("positions", {})
	for pivot_path in positions.keys():
		var keys: Array = positions[pivot_path]
		var track: int = anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(track, "%s/%s:position" % [FIGURE_PATH_PREFIX, str(pivot_path)])
		for key in keys:
			var f: int = int(key[0])
			anim.track_insert_key(track, float(f) / float(C.FRAME_RHYTHM_BASE), key[1])
	var burst_frame: int = int(spec.get("burst_frame", -1))
	if burst_frame >= 0:
		var m_track: int = anim.add_track(Animation.TYPE_METHOD)
		anim.track_set_path(m_track, "%s/TorsoPivot/SwordPivot/SwordArc" % FIGURE_PATH_PREFIX)
		anim.track_insert_key(m_track, float(burst_frame) / float(C.FRAME_RHYTHM_BASE), {"method": "trigger_burst", "args": []})
	return anim


# ── clip 摆姿规格（# DRAFT 候补摆姿，用户裁决；帧数全部来自 FRAME_ANIM_* 常量）──
## 摆姿约定: 角色面向 +X；rotation 正值 = 逆时针；肢体 Line2D 自 pivot 向 -Y 延伸
##   （arms/sword rotation≈180° 即自然下垂；legs rotation=0 即直立）

func _build_idle_spec() -> Dictionary:
	return {
		"name": "anim_idle",
		"frames": 60,
		"loop": true,
		"rotations": {
			"TorsoPivot": [[0, 0], [30, -2], [60, 0]],
			"TorsoPivot/HeadPivot": [[0, 0], [30, 3], [60, 0]],
			"TorsoPivot/ArmLPivot": [[0, 178], [30, 176], [60, 178]],
			"TorsoPivot/ArmRPivot": [[0, 172], [30, 174], [60, 172]],
			"TorsoPivot/SwordPivot": [[0, 160], [30, 158], [60, 160]],
			"LegLPivot": [[0, 0], [60, 0]],
			"LegRPivot": [[0, 0], [60, 0]],
		},
		"positions": {
			"TorsoPivot": [[0, Vector2(0, 0)], [30, Vector2(0, -3)], [60, Vector2(0, 0)]],
		},
	}


func _build_move_spec() -> Dictionary:
	return {
		"name": "anim_move",
		"frames": C.FRAME_ANIM_MOVE_STEP,
		"loop": true,
		"rotations": {
			"TorsoPivot": [[0, 0], [2, -3], [4, 0]],
			"TorsoPivot/HeadPivot": [[0, 2], [2, -2], [4, 2]],
			"TorsoPivot/ArmLPivot": [[0, 170], [2, 190], [4, 170]],
			"TorsoPivot/ArmRPivot": [[0, 190], [2, 170], [4, 190]],
			"TorsoPivot/SwordPivot": [[0, 160], [2, 152], [4, 160]],
			"LegLPivot": [[0, -25], [2, 25], [4, -25]],
			"LegRPivot": [[0, 25], [2, -25], [4, 25]],
		},
		"positions": {
			"TorsoPivot": [[0, Vector2(0, 0)], [2, Vector2(0, -4)], [4, Vector2(0, 0)]],
		},
	}


func _build_attack_spec() -> Dictionary:
	## 三段: 前摇 [0,w] 蓄力下沉 → 暴发 [w,w+b] 挥砍 + 刀光 → 收招 [w+b,w+b+r] 滞刀回位
	var w: int = C.FRAME_ANIM_ATTACK_WINDUP
	var b: int = C.FRAME_ANIM_ATTACK_BURST
	var r: int = C.FRAME_ANIM_ATTACK_RECOVERY
	return {
		"name": "anim_attack",
		"frames": w + b + r,
		"loop": false,
		"rotations": {
			"TorsoPivot": [[0, 0], [w, -6], [w + b, 10], [w + b + r, 0]],
			"TorsoPivot/HeadPivot": [[0, 0], [w, 6], [w + b, -8], [w + b + r, 0]],
			"TorsoPivot/ArmLPivot": [[0, 178], [w, 150], [w + b, 200], [w + b + r, 178]],
			"TorsoPivot/ArmRPivot": [[0, 172], [w, -30], [w + b, 110], [w + b + r, 172]],
			"TorsoPivot/SwordPivot": [[0, 160], [w, -40], [w + b, 100], [w + b + r, 160]],
			"LegLPivot": [[0, 0], [w, -10], [w + b, 10], [w + b + r, 0]],
			"LegRPivot": [[0, 0], [w, 10], [w + b, -10], [w + b + r, 0]],
		},
		"positions": {
			"TorsoPivot": [[0, Vector2(0, 0)], [w, Vector2(0, 4)], [w + b, Vector2(0, -2)], [w + b + r, Vector2(0, 0)]],
		},
		"burst_frame": w,
	}


func _build_heavy_attack_spec() -> Dictionary:
	## 重砍: 蓄力感更强（摆姿更深），帧数沿用 attack 同分区 DRAFT 值
	var w: int = C.FRAME_ANIM_ATTACK_WINDUP
	var b: int = C.FRAME_ANIM_ATTACK_BURST
	var r: int = C.FRAME_ANIM_ATTACK_RECOVERY
	return {
		"name": "anim_heavy_attack",
		"frames": w + b + r,
		"loop": false,
		"rotations": {
			"TorsoPivot": [[0, 0], [w, -10], [w + b, 14], [w + b + r, 0]],
			"TorsoPivot/HeadPivot": [[0, 0], [w, 8], [w + b, -10], [w + b + r, 0]],
			"TorsoPivot/ArmLPivot": [[0, 178], [w, 140], [w + b, 210], [w + b + r, 178]],
			"TorsoPivot/ArmRPivot": [[0, 172], [w, -50], [w + b, 130], [w + b + r, 172]],
			"TorsoPivot/SwordPivot": [[0, 160], [w, -70], [w + b, 120], [w + b + r, 160]],
			"LegLPivot": [[0, 0], [w, -14], [w + b, 14], [w + b + r, 0]],
			"LegRPivot": [[0, 0], [w, 14], [w + b, -14], [w + b + r, 0]],
		},
		"positions": {
			"TorsoPivot": [[0, Vector2(0, 0)], [w, Vector2(0, 6)], [w + b, Vector2(0, -3)], [w + b + r, Vector2(0, 0)]],
		},
		"burst_frame": w,
	}


func _build_guard_spec() -> Dictionary:
	## 横刀胸前（格挡/弹反共用姿态，parry 别名）
	return {
		"name": "anim_guard",
		"frames": 60,
		"loop": false,
		"rotations": {
			"TorsoPivot": [[0, -4], [60, -4]],
			"TorsoPivot/HeadPivot": [[0, 4], [60, 4]],
			"TorsoPivot/ArmLPivot": [[0, 160], [60, 160]],
			"TorsoPivot/ArmRPivot": [[0, -5], [60, -5]],
			"TorsoPivot/SwordPivot": [[0, -85], [60, -85]],
			"LegLPivot": [[0, -8], [60, -8]],
			"LegRPivot": [[0, 8], [60, 8]],
		},
		"positions": {
			"TorsoPivot": [[0, Vector2(0, 2)], [60, Vector2(0, 2)]],
		},
	}


func _build_parry_success_spec() -> Dictionary:
	## 弹反成功硬直帧（#577 结果事件的视觉回报）
	return {
		"name": "anim_parry_success",
		"frames": 24,
		"loop": false,
		"rotations": {
			"TorsoPivot": [[0, 14], [24, 14]],
			"TorsoPivot/HeadPivot": [[0, -12], [24, -12]],
			"TorsoPivot/ArmLPivot": [[0, 140], [24, 140]],
			"TorsoPivot/ArmRPivot": [[0, -30], [24, -30]],
			"TorsoPivot/SwordPivot": [[0, -120], [24, -120]],
			"LegLPivot": [[0, -15], [24, -15]],
			"LegRPivot": [[0, 15], [24, 15]],
		},
		"positions": {
			"TorsoPivot": [[0, Vector2(0, -2)], [24, Vector2(0, -2)]],
		},
	}


func _build_stagger_spec() -> Dictionary:
	## 受击后仰（与 idle 尾帧跳变大 → C2 以首帧衔接主策略回归）
	return {
		"name": "anim_stagger",
		"frames": 24,
		"loop": false,
		"rotations": {
			"TorsoPivot": [[0, 22], [24, 22]],
			"TorsoPivot/HeadPivot": [[0, -20], [24, -20]],
			"TorsoPivot/ArmLPivot": [[0, 130], [24, 130]],
			"TorsoPivot/ArmRPivot": [[0, 30], [24, 30]],
			"TorsoPivot/SwordPivot": [[0, -30], [24, -30]],
			"LegLPivot": [[0, -20], [24, -20]],
			"LegRPivot": [[0, 20], [24, 20]],
		},
		"positions": {
			"TorsoPivot": [[0, Vector2(0, -6)], [24, Vector2(0, -6)]],
		},
	}


func _build_stance_break_spec() -> Dictionary:
	## 架势崩解失衡（前倾失衡）
	return {
		"name": "anim_stance_break",
		"frames": 24,
		"loop": false,
		"rotations": {
			"TorsoPivot": [[0, -18], [24, -18]],
			"TorsoPivot/HeadPivot": [[0, 18], [24, 18]],
			"TorsoPivot/ArmLPivot": [[0, 220], [24, 220]],
			"TorsoPivot/ArmRPivot": [[0, 60], [24, 60]],
			"TorsoPivot/SwordPivot": [[0, -150], [24, -150]],
			"LegLPivot": [[0, 15], [24, 15]],
			"LegRPivot": [[0, -15], [24, -15]],
		},
		"positions": {
			"TorsoPivot": [[0, Vector2(0, 8)], [24, Vector2(0, 8)]],
		},
	}


func _build_execute_spec() -> Dictionary:
	## 处决上撩→斩落（FRAME_ANIM_EXECUTE_TOTAL=5 帧；流程驱动归 #580）
	var total: int = C.FRAME_ANIM_EXECUTE_TOTAL
	return {
		"name": "anim_execute",
		"frames": total,
		"loop": false,
		"rotations": {
			"TorsoPivot": [[0, 10], [total, -15]],
			"TorsoPivot/HeadPivot": [[0, -8], [total, 8]],
			"TorsoPivot/ArmLPivot": [[0, 150], [total, 210]],
			"TorsoPivot/ArmRPivot": [[0, -50], [total, 130]],
			"TorsoPivot/SwordPivot": [[0, -120], [total, 120]],
			"LegLPivot": [[0, -12], [total, 12]],
			"LegRPivot": [[0, 12], [total, -12]],
		},
		"positions": {
			"TorsoPivot": [[0, Vector2(0, -2)], [total, Vector2(0, 6)]],
		},
		"burst_frame": max(total / 2, 1),
	}


func _build_revive_spec() -> Dictionary:
	## 起身关键帧（驱动归 #578）
	return {
		"name": "anim_revive",
		"frames": 30,
		"loop": false,
		"rotations": {
			"TorsoPivot": [[0, -80], [15, -40], [30, 0]],
			"TorsoPivot/HeadPivot": [[0, 20], [15, 10], [30, 0]],
			"TorsoPivot/ArmLPivot": [[0, 120], [15, 150], [30, 178]],
			"TorsoPivot/ArmRPivot": [[0, 80], [15, 130], [30, 172]],
			"TorsoPivot/SwordPivot": [[0, 100], [15, 130], [30, 160]],
			"LegLPivot": [[0, -30], [15, -15], [30, 0]],
			"LegRPivot": [[0, 30], [15, 15], [30, 0]],
		},
		"positions": {
			"TorsoPivot": [[0, Vector2(0, 30)], [15, Vector2(0, 15)], [30, Vector2(0, 0)]],
		},
	}


func _build_dead_spec() -> Dictionary:
	## 倒地帧（驱动归 #578）
	return {
		"name": "anim_dead",
		"frames": 30,
		"loop": false,
		"rotations": {
			"TorsoPivot": [[0, -75], [30, -75]],
			"TorsoPivot/HeadPivot": [[0, 25], [30, 25]],
			"TorsoPivot/ArmLPivot": [[0, 210], [30, 210]],
			"TorsoPivot/ArmRPivot": [[0, 120], [30, 120]],
			"TorsoPivot/SwordPivot": [[0, 60], [30, 60]],
			"LegLPivot": [[0, -35], [30, -35]],
			"LegRPivot": [[0, 35], [30, 35]],
		},
		"positions": {
			"TorsoPivot": [[0, Vector2(0, 20)], [30, Vector2(0, 20)]],
		},
	}
