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
##     {"name": "03_gameover", "state": "GAME_OVER", "settle_frames": 10,
##      "deadline_s": 300}
##   ]
## }
##
## Shot schema: "deadline_s" (optional int) overrides the global
## max_wall_seconds for THAT shot (e.g. 03_gameover: 300s for a 5-point
## AI-vs-AI match to reach GAME_OVER). Absent → falls back to the global
## max_wall_seconds (backward compatible, #372). The loop runs until the
## MAX pending shot deadline, so a long-deadline shot extends the run;
## all shots expiring → loop exits naturally.
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

	while not pending.is_empty() and Time.get_ticks_msec() < _pending_deadline(pending):
		await process_frame
		_frame += 1
		_track_state_trajectory()
		_track_transcript()

		var still_pending: Array = []
		for shot in pending:
			var d: Dictionary = shot
			var shot_name: String = str(d.get("name", "shot"))
			# Per-shot deadline (#372): a shot whose OWN deadline (deadline_s or
			# global fallback) has passed fails immediately — record and drop.
			# The loop condition (_pending_deadline) keeps running until the MAX
			# pending deadline, so a 300s gameover shot is still reachable after
			# the 120s global wall.
			if Time.get_ticks_msec() >= _deadline_for(d):
				failed_shots.append(shot_name + " (deadline)")
				_results.append({"name": shot_name, "saved": false, "frame": _frame, "reason": "deadline"})
				continue
			# Inject press BEFORE readiness check — a press DRIVES the game into
			# this shot's state (e.g. MENU→PLAYING via Enter). Checking first
			# would deadlock: state never changes, press never fires.
			if d.has("press"):
				_inject_press(d)
			if _shot_ready(d):
				var settled := await _settle(int(d.get("settle_frames", 5)), _deadline_for(d))
				if not settled:
					failed_shots.append(shot_name + " (deadline during settle)")
					_results.append({"name": shot_name, "saved": false, "frame": _frame, "reason": "deadline"})
					continue
				var saved := _capture(shot_name)
				if d.has("press"):
					_release_press(d)
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


# ── Press injection ────────────────────────────────────────────────────────
# Two modes (shot plan "press" field):
#   {"action": "ui_accept"}  → Input.action_press (games polling Input.*)
#   {"key": "enter"}         → real InputEventKey via parse_input_event
#                             (games driven by _input(event) — action_press
#                             produces NO event, so FSM-style games need this)
func _keycode_for(name: String) -> int:
	match name.to_lower():
		"enter", "return": return KEY_ENTER
		"space": return KEY_SPACE
		"escape", "esc": return KEY_ESCAPE
		"up": return KEY_UP
		"down": return KEY_DOWN
		"left": return KEY_LEFT
		"right": return KEY_RIGHT
	return KEY_ENTER


func _inject_press(d: Dictionary) -> void:
	var press = d.get("press", "")
	if press is Dictionary:
		if press.has("action"):
			Input.action_press(str(press["action"]))
		elif press.has("key"):
			_emit_key(str(press["key"]), true)
	elif press is String:
		Input.action_press(str(press))


func _release_press(d: Dictionary) -> void:
	var press = d.get("press", "")
	if press is Dictionary:
		if press.has("action"):
			Input.action_release(str(press["action"]))
		elif press.has("key"):
			_emit_key(str(press["key"]), false)
	elif press is String:
		Input.action_release(str(press))


func _emit_key(key_name: String, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = _keycode_for(key_name)
	ev.pressed = pressed
	Input.parse_input_event(ev)


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
		if not states.has(d["state"]):
			return false
		# JSON numbers parse as float — compare numerically, never via typeof.
		var want: int = int(states[d["state"]])
		if _current_state() == want and _require_ok(d) and _assert_text_ok(d):
			return true
		return false
	if d.has("at_frame"):
		return _frame >= int(d.get("at_frame", 0))
	return false


func _assert_text_ok(d: Dictionary) -> bool:
	"""Assert the shot's on-screen text actually shows expected content.

	Shot plan: "assert_text": [{"node": "/root/...", "prop": "text",
	"contains": "v1.0.0"}]. This is what proves the ISSUE's deliverable is
	visibly rendered (canary #358: version number), not just that a frame
	exists. All entries must pass or the shot never becomes ready."""
	if not d.has("assert_text"):
		return true
	for a in (d["assert_text"] as Array):
		var spec: Dictionary = a
		var node = root.get_node_or_null(str(spec.get("node", "")))
		if node == null:
			printerr("❌ assert_text: node not found: ", spec.get("node", ""))
			return false
		var v = node.get(str(spec.get("prop", "text")))
		var text := str(v) if v != null else ""
		if not text.contains(str(spec.get("contains", ""))):
			printerr("❌ assert_text: ", spec.get("node", ""), ".",
				spec.get("prop", "text"), " = '", text, "' missing '",
				spec.get("contains", ""), "'")
			return false
	return true


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


func _settle(frames: int, deadline_ms: int) -> bool:
	for i in range(frames):
		if Time.get_ticks_msec() >= deadline_ms:
			return false
		await process_frame
		_frame += 1
		_track_state_trajectory()
		_track_transcript()
	return true


func _deadline_for(d: Dictionary) -> int:
	"""Shot's own deadline in ms; absent deadline_s → global max_wall_seconds."""
	var global_s: int = int(_plan.get("max_wall_seconds", 120))
	var s: int = int(d.get("deadline_s", global_s))
	return _started_ms + s * 1000


func _pending_deadline(pending: Array) -> int:
	"""Loop keeps running while ANY pending shot's deadline is not reached.

	#372: 03_gameover gets deadline_s=300 while 01_title/02_midgame fall back
	to the global 120s — the loop must NOT die at 120s if gameover is still
	pending. Once every shot's own deadline has passed, this returns a past
	timestamp and the loop exits naturally.
	"""
	var d := _started_ms
	for shot in pending:
		d = maxi(d, _deadline_for(shot))
	return d


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
	# Node.get() takes exactly ONE argument — read the prop, then default if null.
	var val = node.get(str(cfg.get("prop", "text")))
	var text: String = str(val) if val != null else ""
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
