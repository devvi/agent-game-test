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
##   - #683 重摆（docs/DESIGN/683-stick-figure-structure-fix.md §2.3/§2.4/§2.5）:
##     * REST_POSE 公共基准 + 首尾帧衔接规约（R1 动作型首/尾帧 = REST_POSE；R2 hold 型
##       尾部追加 FRAME_ANIM_*_EXIT 归位段收敛 REST_POSE）→ AC3 姿态差 ≤ POSE_DELTA_MAX_DEG
##     * anim_move 重排为 FRAME_ANIM_MOVE_CYCLE=24 帧完整步态（contact/pass 关键姿态）
##       + 2 条膝 rotation track + 摆臂与对侧腿同相符号相反
##     * 新增 set_move_speed(v)（§2.4）: 仅 anim_move 生效，speed_scale = clamp(|v|/MOVE_MAX_SPEED)
##     * 全部 clip 新增 9 关节 rotation track（含膝 + NeckPivot 前缀的 HeadPivot）
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

## REST_POSE 公共基准姿态（#683 §2.3）: 自然站姿。动作型 clip 首/尾帧、hold 型 clip 首帧
## 与尾部归位段终点均收敛到此姿态（各关节差 ≤5°），配合 FRAME_ANIM_*_EXIT 归位段实现
## 任意合法转移对的关节角差 ≤ POSE_DELTA_MAX_DEG（AC3-T1 枚举断言）。
## 约定: ArmRPivot 取 -172（≡188°，镜像垂臂）——AC2-T5 要求 move 首帧两臂符号相反，
##   而 AC3 要求两臂都贴近 REST_POSE；唯一同时满足两者的解是右臂基准取负值镜像（视觉等价）。
## 键 = clip rotation track 路径（不含 StickFigure 前缀，_build_clip 会拼接）；值 = 度。
const REST_POSE: Dictionary = {
	"TorsoPivot": 0.0,
	"TorsoPivot/NeckPivot/HeadPivot": 0.0,
	"TorsoPivot/ArmLPivot": 178.0,
	"TorsoPivot/ArmRPivot": -172.0,
	"TorsoPivot/SwordPivot": 160.0,
	"LegLPivot": 0.0,
	"LegRPivot": 0.0,
	"LegLPivot/LegKPivot": 0.0,
	"LegRPivot/LegKPivot": 0.0,
}

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


func set_move_speed(v: float) -> void:
	## 步频速度同步（#683 §2.4）: 仅 anim_move 生效（非 move clip 调用 = no-op）。
	## speed_scale = clamp(|v| / MOVE_MAX_SPEED, MOVE_PLAYBACK_SPEED_MIN, MOVE_PLAYBACK_SPEED_MAX)
	if _anim == null or _anim.current_animation != "anim_move":
		return
	var ratio: float = absf(v) / C.MOVE_MAX_SPEED
	_anim.speed_scale = clampf(ratio, C.MOVE_PLAYBACK_SPEED_MIN, C.MOVE_PLAYBACK_SPEED_MAX)


func get_animation_position() -> float:
	## 供动画状态对象 / E2E 截图像具查询 AnimationPlayer 当前播放位置（秒）
	if _anim == null:
		return 0.0
	return _anim.current_animation_position


func is_animation_playing() -> bool:
	## 供 E2E 截图像具查询动画是否在播（null-guard）
	if _anim == null:
		return false
	return _anim.is_playing()




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
	## 呼吸待机（R1 动作型）: 首/尾帧 = REST_POSE，中间微摆；9 关节 rotation track 全含
	return {
		"name": "anim_idle",
		"frames": 60,
		"loop": true,
		"rotations": {
			"TorsoPivot": [[0, 0], [30, -2], [60, 0]],
			"TorsoPivot/NeckPivot/HeadPivot": [[0, 0], [30, 3], [60, 0]],
			"TorsoPivot/ArmLPivot": [[0, 178], [30, 176], [60, 178]],
			"TorsoPivot/ArmRPivot": [[0, -172], [30, -174], [60, -172]],
			"TorsoPivot/SwordPivot": [[0, 160], [30, 158], [60, 160]],
			"LegLPivot": [[0, 0], [60, 0]],
			"LegRPivot": [[0, 0], [60, 0]],
			"LegLPivot/LegKPivot": [[0, 0], [60, 0]],
			"LegRPivot/LegKPivot": [[0, 0], [60, 0]],
		},
		"positions": {
			"TorsoPivot": [[0, Vector2(0, 0)], [30, Vector2(0, -3)], [60, Vector2(0, 0)]],
		},
	}


func _build_move_spec() -> Dictionary:
	## 步态循环（R1 动作型 + #683 §2.5）: FRAME_ANIM_MOVE_CYCLE=24 帧
	##   contact(0)→pass(6)→contact(12)→pass(18)，loop。
	## 首关键帧 = contact 摆姿（AC2-T3/T5 断言依据: LegL=±MOVE_SWING_LEG_DEG、膝=0、
	##   摆臂与对侧腿同相符号相反）；pass 帧摆动腿屈膝抬脚（MOVE_KNEE_BEND_DEG）。
	## 摆臂以 REST_POSE 为基准 ±MOVE_SWING_ARM_DEG（self-correct 起: 原绝对 ±25° 与垂臂 178/-172
	##   相差 ~180° 致 AC3 姿态差爆表；改 REST_POSE 相对偏移且摆幅 12° ≤ POSE_DELTA_MAX_DEG）。
	## 末关键帧收敛到 REST_POSE 衔接 move→X（AC3-T1: 臂回摆位 178/-172、膝归位 0）。
	var swing_leg: float = C.MOVE_SWING_LEG_DEG
	var swing_arm: float = C.MOVE_SWING_ARM_DEG
	var knee_bend: float = C.MOVE_KNEE_BEND_DEG
	return {
		"name": "anim_move",
		"frames": C.FRAME_ANIM_MOVE_CYCLE,
		"loop": true,
		"rotations": {
			"TorsoPivot": [[0, 0], [6, -2], [12, 0], [18, -2]],
			"TorsoPivot/NeckPivot/HeadPivot": [[0, 2], [6, -2], [12, 2], [18, -2]],
			"TorsoPivot/ArmLPivot": [[0, REST_POSE["TorsoPivot/ArmLPivot"] - swing_arm], [6, REST_POSE["TorsoPivot/ArmLPivot"]], [12, REST_POSE["TorsoPivot/ArmLPivot"] + swing_arm], [18, REST_POSE["TorsoPivot/ArmLPivot"]]],
			"TorsoPivot/ArmRPivot": [[0, REST_POSE["TorsoPivot/ArmRPivot"] + swing_arm], [6, REST_POSE["TorsoPivot/ArmRPivot"]], [12, REST_POSE["TorsoPivot/ArmRPivot"] - swing_arm], [18, REST_POSE["TorsoPivot/ArmRPivot"]]],
			"TorsoPivot/SwordPivot": [[0, 152], [6, 160], [12, 152], [18, 160]],
			"LegLPivot": [[0, swing_leg], [6, 0], [12, -swing_leg], [18, 0]],
			"LegRPivot": [[0, -swing_leg], [6, 0], [12, swing_leg], [18, 0]],
			"LegLPivot/LegKPivot": [[0, 0], [6, knee_bend], [12, 0], [18, 0]],
			"LegRPivot/LegKPivot": [[0, 0], [6, 0], [12, 0], [18, knee_bend], [20, 0]],
		},
		"positions": {
			"TorsoPivot": [[0, Vector2(0, 0)], [6, Vector2(0, -4)], [12, Vector2(0, 0)], [18, Vector2(0, -4)]],
		},
	}


func _build_attack_spec() -> Dictionary:
	## 三段（R1 动作型）: 前摇 [0,w] 蓄力下沉 → 暴发 [w,w+b] 挥砍 + 刀光 → 收招 [w+b,w+b+r] 滞刀回位。
	## 首/尾帧 = REST_POSE；膝 track 前摇微屈蓄力、暴发后回收 0（帧间距不对称 = 力度感）。
	var w: int = C.FRAME_ANIM_ATTACK_WINDUP
	var b: int = C.FRAME_ANIM_ATTACK_BURST
	var r: int = C.FRAME_ANIM_ATTACK_RECOVERY
	return {
		"name": "anim_attack",
		"frames": w + b + r,
		"loop": false,
		"rotations": {
			"TorsoPivot": [[0, 0], [w, -6], [w + b, 10], [w + b + r, 0]],
			"TorsoPivot/NeckPivot/HeadPivot": [[0, 0], [w, 6], [w + b, -8], [w + b + r, 0]],
			"TorsoPivot/ArmLPivot": [[0, 178], [w, 150], [w + b, 200], [w + b + r, 178]],
			"TorsoPivot/ArmRPivot": [[0, -172], [w, -30], [w + b, 110], [w + b + r, -172]],
			"TorsoPivot/SwordPivot": [[0, 160], [w, -40], [w + b, 100], [w + b + r, 160]],
			"LegLPivot": [[0, 0], [w, -10], [w + b, 10], [w + b + r, 0]],
			"LegRPivot": [[0, 0], [w, 10], [w + b, -10], [w + b + r, 0]],
			"LegLPivot/LegKPivot": [[0, 0], [w, 15], [w + b, 0], [w + b + r, 0]],
			"LegRPivot/LegKPivot": [[0, 0], [w, 15], [w + b, 0], [w + b + r, 0]],
		},
		"positions": {
			"TorsoPivot": [[0, Vector2(0, 0)], [w, Vector2(0, 4)], [w + b, Vector2(0, -2)], [w + b + r, Vector2(0, 0)]],
		},
		"burst_frame": w,
	}


func _build_heavy_attack_spec() -> Dictionary:
	## 重砍（R1 动作型）: 蓄力感更强（摆姿更深），三段帧数沿用 attack 同分区 DRAFT 值；
	## 首/尾帧 = REST_POSE；膝 track 前摇蓄力更深、暴发后回收 0
	var w: int = C.FRAME_ANIM_ATTACK_WINDUP
	var b: int = C.FRAME_ANIM_ATTACK_BURST
	var r: int = C.FRAME_ANIM_ATTACK_RECOVERY
	return {
		"name": "anim_heavy_attack",
		"frames": w + b + r,
		"loop": false,
		"rotations": {
			"TorsoPivot": [[0, 0], [w, -10], [w + b, 14], [w + b + r, 0]],
			"TorsoPivot/NeckPivot/HeadPivot": [[0, 0], [w, 8], [w + b, -10], [w + b + r, 0]],
			"TorsoPivot/ArmLPivot": [[0, 178], [w, 140], [w + b, 210], [w + b + r, 178]],
			"TorsoPivot/ArmRPivot": [[0, -172], [w, -50], [w + b, 130], [w + b + r, -172]],
			"TorsoPivot/SwordPivot": [[0, 160], [w, -70], [w + b, 120], [w + b + r, 160]],
			"LegLPivot": [[0, 0], [w, -14], [w + b, 14], [w + b + r, 0]],
			"LegRPivot": [[0, 0], [w, 14], [w + b, -14], [w + b + r, 0]],
			"LegLPivot/LegKPivot": [[0, 0], [w, 20], [w + b, 0], [w + b + r, 0]],
			"LegRPivot/LegKPivot": [[0, 0], [w, 20], [w + b, 0], [w + b + r, 0]],
		},
		"positions": {
			"TorsoPivot": [[0, Vector2(0, 0)], [w, Vector2(0, 6)], [w + b, Vector2(0, -3)], [w + b + r, Vector2(0, 0)]],
		},
		"burst_frame": w,
	}


func _build_guard_spec() -> Dictionary:
	## 横刀胸前（R2 hold 型，parry 别名）: 首帧 REST_POSE → 2 帧内横刀保持 →
	## 尾部 FRAME_ANIM_GUARD_EXIT 帧归位段收敛回 REST_POSE（R2 规约，AC3-T1 衔接）
	var exit: int = C.FRAME_ANIM_GUARD_EXIT
	var hold_end: int = 60 - exit
	return {
		"name": "anim_guard",
		"frames": 60,
		"loop": false,
		"rotations": {
			"TorsoPivot": [[0, 0], [2, -4], [hold_end, -4], [60, 0]],
			"TorsoPivot/NeckPivot/HeadPivot": [[0, 0], [2, 4], [hold_end, 4], [60, 0]],
			"TorsoPivot/ArmLPivot": [[0, 178], [2, 160], [hold_end, 160], [60, 178]],
			"TorsoPivot/ArmRPivot": [[0, -172], [2, -5], [hold_end, -5], [60, -172]],
			"TorsoPivot/SwordPivot": [[0, 160], [2, -85], [hold_end, -85], [60, 160]],
			"LegLPivot": [[0, 0], [2, -8], [hold_end, -8], [60, 0]],
			"LegRPivot": [[0, 0], [2, 8], [hold_end, 8], [60, 0]],
			"LegLPivot/LegKPivot": [[0, 0], [2, 6], [hold_end, 6], [60, 0]],
			"LegRPivot/LegKPivot": [[0, 0], [2, 6], [hold_end, 6], [60, 0]],
		},
		"positions": {
			"TorsoPivot": [[0, Vector2(0, 0)], [2, Vector2(0, 2)], [hold_end, Vector2(0, 2)], [60, Vector2(0, 0)]],
		},
	}


func _build_parry_success_spec() -> Dictionary:
	## 弹反成功硬直帧（R2 hold 型，#577 结果事件的视觉回报）: 首帧 REST_POSE → 2 帧内后仰
	## 摆姿保持 → 尾部 FRAME_ANIM_PARRY_SUCCESS_EXIT 帧归位段收敛回 REST_POSE
	var exit: int = C.FRAME_ANIM_PARRY_SUCCESS_EXIT
	var hold_end: int = 24 - exit
	return {
		"name": "anim_parry_success",
		"frames": 24,
		"loop": false,
		"rotations": {
			"TorsoPivot": [[0, 0], [2, 14], [hold_end, 14], [24, 0]],
			"TorsoPivot/NeckPivot/HeadPivot": [[0, 0], [2, -12], [hold_end, -12], [24, 0]],
			"TorsoPivot/ArmLPivot": [[0, 178], [2, 140], [hold_end, 140], [24, 178]],
			"TorsoPivot/ArmRPivot": [[0, -172], [2, -30], [hold_end, -30], [24, -172]],
			"TorsoPivot/SwordPivot": [[0, 160], [2, -120], [hold_end, -120], [24, 160]],
			"LegLPivot": [[0, 0], [2, -15], [hold_end, -15], [24, 0]],
			"LegRPivot": [[0, 0], [2, 15], [hold_end, 15], [24, 0]],
			"LegLPivot/LegKPivot": [[0, 0], [2, 10], [hold_end, 10], [24, 0]],
			"LegRPivot/LegKPivot": [[0, 0], [2, 10], [hold_end, 10], [24, 0]],
		},
		"positions": {
			"TorsoPivot": [[0, Vector2(0, 0)], [2, Vector2(0, -2)], [hold_end, Vector2(0, -2)], [24, Vector2(0, 0)]],
		},
	}


func _build_stagger_spec() -> Dictionary:
	## 受击后仰（R2 hold 型）: 首帧 REST_POSE → 2 帧内后仰摆姿保持 → 尾部
	## FRAME_ANIM_STAGGER_EXIT 帧归位段收敛回 REST_POSE（idle→stagger→idle 双向衔接）
	var exit: int = C.FRAME_ANIM_STAGGER_EXIT
	var hold_end: int = 24 - exit
	return {
		"name": "anim_stagger",
		"frames": 24,
		"loop": false,
		"rotations": {
			"TorsoPivot": [[0, 0], [2, 22], [hold_end, 22], [24, 0]],
			"TorsoPivot/NeckPivot/HeadPivot": [[0, 0], [2, -20], [hold_end, -20], [24, 0]],
			"TorsoPivot/ArmLPivot": [[0, 178], [2, 130], [hold_end, 130], [24, 178]],
			"TorsoPivot/ArmRPivot": [[0, -172], [2, 30], [hold_end, 30], [24, -172]],
			"TorsoPivot/SwordPivot": [[0, 160], [2, -30], [hold_end, -30], [24, 160]],
			"LegLPivot": [[0, 0], [2, -20], [hold_end, -20], [24, 0]],
			"LegRPivot": [[0, 0], [2, 20], [hold_end, 20], [24, 0]],
			"LegLPivot/LegKPivot": [[0, 0], [2, 15], [hold_end, 15], [24, 0]],
			"LegRPivot/LegKPivot": [[0, 0], [2, 15], [hold_end, 15], [24, 0]],
		},
		"positions": {
			"TorsoPivot": [[0, Vector2(0, 0)], [2, Vector2(0, -6)], [hold_end, Vector2(0, -6)], [24, Vector2(0, 0)]],
		},
	}


func _build_stance_break_spec() -> Dictionary:
	## 架势崩解失衡（R2 hold 型，前倾失衡）: 首帧 REST_POSE → 2 帧内失衡摆姿保持 → 尾部
	## FRAME_ANIM_STANCE_BREAK_EXIT 帧归位段收敛回 REST_POSE
	var exit: int = C.FRAME_ANIM_STANCE_BREAK_EXIT
	var hold_end: int = 24 - exit
	return {
		"name": "anim_stance_break",
		"frames": 24,
		"loop": false,
		"rotations": {
			"TorsoPivot": [[0, 0], [2, -18], [hold_end, -18], [24, 0]],
			"TorsoPivot/NeckPivot/HeadPivot": [[0, 0], [2, 18], [hold_end, 18], [24, 0]],
			"TorsoPivot/ArmLPivot": [[0, 178], [2, 220], [hold_end, 220], [24, 178]],
			"TorsoPivot/ArmRPivot": [[0, -172], [2, 60], [hold_end, 60], [24, -172]],
			"TorsoPivot/SwordPivot": [[0, 160], [2, -150], [hold_end, -150], [24, 160]],
			"LegLPivot": [[0, 0], [2, 15], [hold_end, 15], [24, 0]],
			"LegRPivot": [[0, 0], [2, -15], [hold_end, -15], [24, 0]],
			"LegLPivot/LegKPivot": [[0, 0], [2, 15], [hold_end, 15], [24, 0]],
			"LegRPivot/LegKPivot": [[0, 0], [2, 15], [hold_end, 15], [24, 0]],
		},
		"positions": {
			"TorsoPivot": [[0, Vector2(0, 0)], [2, Vector2(0, 8)], [hold_end, Vector2(0, 8)], [24, Vector2(0, 0)]],
		},
	}


func _build_execute_spec() -> Dictionary:
	## 处决上撩→斩落（R1 动作型，FRAME_ANIM_EXECUTE_TOTAL=5 帧；流程驱动归 #580）。
	## 首/尾帧 = REST_POSE
	var total: int = C.FRAME_ANIM_EXECUTE_TOTAL
	var mid: int = max(total / 2, 1)
	return {
		"name": "anim_execute",
		"frames": total,
		"loop": false,
		"rotations": {
			"TorsoPivot": [[0, 0], [mid, -12], [total, 0]],
			"TorsoPivot/NeckPivot/HeadPivot": [[0, 0], [mid, 8], [total, 0]],
			"TorsoPivot/ArmLPivot": [[0, 178], [mid, 150], [total, 178]],
			"TorsoPivot/ArmRPivot": [[0, -172], [mid, -50], [total, -172]],
			"TorsoPivot/SwordPivot": [[0, 160], [mid, -120], [total, 160]],
			"LegLPivot": [[0, 0], [mid, -12], [total, 0]],
			"LegRPivot": [[0, 0], [mid, 12], [total, 0]],
			"LegLPivot/LegKPivot": [[0, 0], [mid, 10], [total, 0]],
			"LegRPivot/LegKPivot": [[0, 0], [mid, 10], [total, 0]],
		},
		"positions": {
			"TorsoPivot": [[0, Vector2(0, 0)], [mid, Vector2(0, 6)], [total, Vector2(0, 0)]],
		},
		"burst_frame": mid,
	}


func _build_revive_spec() -> Dictionary:
	## 起身（R1 动作型，驱动归 #578）: 首帧 REST_POSE（接 dead 尾帧归位段）→ 起身动画 →
	## 尾帧 REST_POSE
	return {
		"name": "anim_revive",
		"frames": 30,
		"loop": false,
		"rotations": {
			"TorsoPivot": [[0, 0], [15, -40], [30, 0]],
			"TorsoPivot/NeckPivot/HeadPivot": [[0, 0], [15, 10], [30, 0]],
			"TorsoPivot/ArmLPivot": [[0, 178], [15, 120], [30, 178]],
			"TorsoPivot/ArmRPivot": [[0, -172], [15, 130], [30, -172]],
			"TorsoPivot/SwordPivot": [[0, 160], [15, 100], [30, 160]],
			"LegLPivot": [[0, 0], [15, -30], [30, 0]],
			"LegRPivot": [[0, 0], [15, 30], [30, 0]],
			"LegLPivot/LegKPivot": [[0, 0], [15, 20], [30, 0]],
			"LegRPivot/LegKPivot": [[0, 0], [15, 20], [30, 0]],
		},
		"positions": {
			"TorsoPivot": [[0, Vector2(0, 0)], [15, Vector2(0, 30)], [30, Vector2(0, 0)]],
		},
	}


func _build_dead_spec() -> Dictionary:
	## 倒地（R2 hold 型，驱动归 #578）: 首帧 REST_POSE → 2 帧内倒地摆姿保持（30 帧）→
	## 尾部 FRAME_ANIM_DEAD_EXIT 帧归位段收敛回 REST_POSE（接 revive 首帧 REST_POSE）
	var exit: int = C.FRAME_ANIM_DEAD_EXIT
	var hold_end: int = 30
	var total: int = hold_end + exit
	return {
		"name": "anim_dead",
		"frames": total,
		"loop": false,
		"rotations": {
			"TorsoPivot": [[0, 0], [2, -75], [hold_end, -75], [total, 0]],
			"TorsoPivot/NeckPivot/HeadPivot": [[0, 0], [2, 25], [hold_end, 25], [total, 0]],
			"TorsoPivot/ArmLPivot": [[0, 178], [2, 210], [hold_end, 210], [total, 178]],
			"TorsoPivot/ArmRPivot": [[0, -172], [2, 120], [hold_end, 120], [total, -172]],
			"TorsoPivot/SwordPivot": [[0, 160], [2, 60], [hold_end, 60], [total, 160]],
			"LegLPivot": [[0, 0], [2, -35], [hold_end, -35], [total, 0]],
			"LegRPivot": [[0, 0], [2, 35], [hold_end, 35], [total, 0]],
			"LegLPivot/LegKPivot": [[0, 0], [2, 10], [hold_end, 10], [total, 0]],
			"LegRPivot/LegKPivot": [[0, 0], [2, 10], [hold_end, 10], [total, 0]],
		},
		"positions": {
			"TorsoPivot": [[0, Vector2(0, 0)], [2, Vector2(0, 20)], [hold_end, Vector2(0, 20)], [total, Vector2(0, 0)]],
		},
	}
