extends SceneTree
## E2E capture driver — state-machine-driven screenshot capture (v2, 2026-07-31).
##
## Runs NON-headless (real rendering) via --script with a display driver. Reads a
## RESOLVED shot plan JSON (produced by run-e2e-review.sh after archetype/diff
## selection), drives the real game loop, and captures frames at state-machine
## milestones. Zero modification of game code: it only READS node properties.
##
## Usage (by run-e2e-review.sh):
##   godot --path <subproject>/ --display-driver macos --rendering-driver opengl3 \
##         --resolution 1280x720 --script /tmp/e2e-<N>/capture.gd \
##         -- /tmp/e2e-<N>/plan.json
##
## Resolved plan schema:
## {
##   "main_scene": "res://scenes/Main.tscn",
##   "out_dir": "/tmp/e2e-<N>/shots",
##   "max_wall_seconds": 120,
##   "state_node": "/root/Main/GameStateMachine",
##   "state_property": "current_state",
##   "states": {"MENU": 0, "SERVING": 1, "PLAYING": 2, "PAUSED": 3, "SCORED": 4, "GAME_OVER": 5},
##   "autoplay": {"tweaks": [{"node": "/root/Main/AIPaddle", "prop": "ai_position_error", "value": 60}]},
##   "transcript": {"node": "/root/Main/GameHUD/DialogueLabel", "prop": "text"} | null,
##   "state_trajectory": true,
##   "shots": [
##     {"name": "01_title", "state": "MENU", "settle_frames": 10},
##     {"name": "02_midgame", "state": "PLAYING",
##      "require": {"node": "/root/Main/GameManager", "prop": "player_score", "min": 1},
##      "settle_frames": 5},
##     {"name": "03_gameover", "state": "GAME_OVER", "settle_frames": 10}
##   ]
## }
##
## Outputs: PNG per shot + results.json (per-shot status) + transcript.txt +
## trajectory.txt (journey mode). Exit 0 = all shots captured, 1 = any missed.

const _PLAN_ARG_INDEX := 0

var _plan: Dictionary = {}
var _out_dir: String = ""
var _deadline_ms: int = 0
var _started_ms: int = 0
var _frame: int = 0
var _results: Array[Dictionary] = []
var _last_state: int = -1
var _last_transcript_text: String = ""
var _transcript_lines: Array[String] = []
var _trajectory_lines: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("❌ no plan path passed after --")
		quit(1)
		return
	var plan_path: String = args[_PLAN_ARG_INDEX]
	if not FileAccess.file_exists(plan_path):
		printerr("❌ plan not found: ", plan_path)
		quit(1)
		return

	var parsed = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		printerr("❌ plan is not a JSON object")
		quit(1)
		return
	_plan = parsed
	_out_dir = str(_plan.get("out_dir", "/tmp/e2e_shots"))
	DirAccess.make_dir_recursive_absolute(_out_dir)

	# ── Load the real main scene ──
	var main_scene_path: String = str(_plan.get("main_scene", "res://scenes/Main.tscn"))
	var packed = load(main_scene_path)
	if packed == null:
		printerr("❌ main scene load failed: ", main_scene_path)
		quit(1)
		return
	var inst = packed.instantiate()
	root.add_child(inst)

	# ── Let the engine settle (autoloads, _ready, first frames) ──
	for i in range(15):
		await process_frame

	# ── Apply autoplay tweaks ──
	_apply_tweaks()

	# ── Deadline ──
	_started_ms = Time.get_ticks_msec()
	_deadline_ms = _started_ms + int(_plan.get("max_wall_seconds", 120)) * 1000

	# ── Main loop: poll state machine, fire shots ──
	var pending: Array = (_plan.get("shots", []) as Array).duplicate()
	var failed_shots: Array[String] = []

	while not pending.is_empty() and Time.get_ticks_msec() < _deadline_ms:
		await process_frame
		_frame += 1
		_track_state_trajectory()
		_track_transcript()

		var still_pending: Array = []
		for shot in pending:
			var d: Dictionary = shot
			var shot_name: String = str(d.get("name", "shot"))
			if _shot_ready(d):
				if d.has("press"):
					Input.action_press(str(d["press"]))
					await process_frame
				var settled := await _settle(int(d.get("settle_frames", 5)))
				if not settled:
					failed_shots.append(shot_name + " (deadline during settle)")
					_results.append({"name": shot_name, "saved": false, "frame": _frame, "reason": "deadline"})
					continue
				var saved := _capture(shot_name)
				if d.has("press"):
					Input.action_release(str(d["press"]))
				_results.append({"name": shot_name, "saved": saved, "frame": _frame, "state": _current_state_name()})
				if not saved:
					failed_shots.append(shot_name)
			else:
				still_pending.append(shot)
		pending = still_pending

	# Anything left = missed (deadline hit)
	for shot in pending:
		var d: Dictionary = shot
		var shot_name: String = str(d.get("name", "shot"))
		failed_shots.append(shot_name)
		_results.append({"name": shot_name, "saved": false, "frame": _frame, "reason": "deadline"})

	_write_results(failed_shots)
	var ok: bool = failed_shots.is_empty()
	print("=== E2E CAPTURE: ", "✅ all ", _results.size(), " shots" if ok
		else "❌ missed: " + ", ".join(failed_shots), " ===")
	quit(0 if ok else 1)


# ── Shot conditions ────────────────────────────────────────────────────────

func _current_state() -> int:
	var node = _state_node()
	if node == null:
		return -1
	var v = node.get(str(_plan.get("state_property", "current_state")))
	if typeof(v) == TYPE_INT:
		return int(v)
	return -1


func _current_state_name() -> String:
	var states: Dictionary = _plan.get("states", {})
	var cur := _current_state()
	for k in states.keys():
		if int(states[k]) == cur:
			return str(k)
	return str(cur)


func _state_node() -> Node:
	return root.get_node_or_null(str(_plan.get("state_node", "")))


func _shot_ready(d: Dictionary) -> bool:
	if d.has("state"):
		var states: Dictionary = _plan.get("states", {})
		var want := states.get(d["state"], -1)
		if typeof(want) == TYPE_INT and _current_state() == int(want):
			return _require_ok(d)
		return false
	if d.has("at_frame"):
		return _frame >= int(d.get("at_frame", 0))
	return false


func _require_ok(d: Dictionary) -> bool:
	if not d.has("require"):
		return true
	var req: Dictionary = d["require"]
	var node = root.get_node_or_null(str(req.get("node", "")))
	if node == null:
		return false
	var v = node.get(str(req.get("prop", "")))
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return float(v) >= float(req.get("min", 1))
	return true


func _settle(frames: int) -> bool:
	for i in range(frames):
		if Time.get_ticks_msec() >= _deadline_ms:
			return false
		await process_frame
		_frame += 1
		_track_state_trajectory()
		_track_transcript()
	return true


# ── Capture ────────────────────────────────────────────────────────────────

func _capture(shot_name: String) -> bool:
	var img = root.get_texture().get_image()
	var path := _out_dir.path_join(shot_name + ".png")
	var err := img.save_png(path)
	if err == OK:
		print("saved ", path, " ", img.get_width(), "x", img.get_height())
		return true
	printerr("❌ save failed (", err, "): ", path)
	return false


# ── Autoplay / tweaks ──────────────────────────────────────────────────────

func _apply_tweaks() -> void:
	var autoplay: Dictionary = _plan.get("autoplay", {})
	var tweaks: Array = autoplay.get("tweaks", [])
	for t in tweaks:
		var d: Dictionary = t
		var node = root.get_node_or_null(str(d.get("node", "")))
		if node == null:
			printerr("⚠ tweak node not found: ", d.get("node", ""))
			continue
		node.set(str(d.get("prop", "")), d.get("value"))
		print("tweak: ", d.get("node"), ".", d.get("prop"), " = ", d.get("value"))


# ── Journey traces (transcript + state trajectory) ─────────────────────────

func _track_state_trajectory() -> void:
	if not bool(_plan.get("state_trajectory", false)):
		return
	var cur := _current_state()
	if cur != _last_state:
		_last_state = cur
		_trajectory_lines.append("frame=%d state=%s" % [_frame, _current_state_name()])


func _track_transcript() -> void:
	if not _plan.has("transcript"):
		return
	var cfg: Dictionary = _plan["transcript"]
	var node = root.get_node_or_null(str(cfg.get("node", "")))
	if node == null:
		return
	var text: String = str(node.get(str(cfg.get("prop", "text")), ""))
	if text != _last_transcript_text and text.strip_edges() != "":
		_last_transcript_text = text
		_transcript_lines.append("[frame=%d] %s" % [_frame, text])


func _write_results(failed: Array) -> void:
	FileAccess.open(_out_dir.path_join("results.json"), FileAccess.WRITE).store_string(
		JSON.stringify({
			"shots": _results,
			"missed": failed,
			"frame": _frame,
			"elapsed_ms": Time.get_ticks_msec() - _started_ms,
		}, "\t"))
	if not _transcript_lines.is_empty():
		FileAccess.open(_out_dir.path_join("transcript.txt"), FileAccess.WRITE).store_string(
			"\n".join(_transcript_lines) + "\n")
	if not _trajectory_lines.is_empty():
		FileAccess.open(_out_dir.path_join("trajectory.txt"), FileAccess.WRITE).store_string(
			"\n".join(_trajectory_lines) + "\n")
