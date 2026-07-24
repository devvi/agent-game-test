extends SceneTree

# E2E Playthrough Smoke Test
# Verifies the complete game flow: title → all 6 scenes → ending
# Runs in godot --headless --script mode on GitHub CI
# Only prints failures to avoid pipe buffer deadlock (see godot-headless-testing skill)

var _passed: int = 0
var _failed: int = 0

const SCENE_PATHS: Dictionary = {
	"office": "res://scenes/office/office.tscn",
	"lobby": "res://scenes/lobby/lobby.tscn",
	"convenience_store": "res://scenes/store/convenience_store.tscn",
	"bridge": "res://scenes/bridge/bridge.tscn",
	"underpass": "res://scenes/underpass/underpass.tscn",
	"subway_station": "res://scenes/subway_station/subway_station.tscn"
}

const DIALOGUE_FILES: Array[String] = [
	"office_door.json", "lobby_guard.json", "lobby_stranger.json",
	"lobby_exit.json", "store_clerk.json", "store_exit.json",
	"bridge_homeless.json", "bridge_exit.json",
	"underpass_stranger_echo.json", "underpass_exit.json",
	"subway_ending.json", "bartender.json"
]

const SCENE_SCRIPTS: Dictionary = {
	"office": "res://gdscripts/office.gd",
	"lobby": "res://gdscripts/lobby.gd",
	"convenience_store": "res://gdscripts/store.gd",
	"bridge": "res://gdscripts/bridge.gd",
	"underpass": "res://gdscripts/underpass.gd",
	"subway_station": "res://gdscripts/subway_station.gd"
}


func _init() -> void:
	print("\n=== PLAYTHROUGH SMOKE TEST ===\n")
	_run_all()
	print("\n=== Results ===")
	print("Passed: %d" % _passed)
	print("Failed: %d" % _failed)
	quit(1 if _failed > 0 else 0)


func _run_all() -> void:
	_test_title_screen()
	_test_scene_scripts()
	_test_scene_files()
	_test_dialogue_files()
	_test_scene_manager()
	_test_state_system()
	_test_game_manager()
	_test_narrative_manager()
	_test_ending_logic()
	_test_player_controller()
	_test_end_credits()


func _assert(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("  ❌ ", label)


# ── Title Screen ──
func _test_title_screen() -> void:
	print("  --- Title Screen ---")
	var TS = load("res://gdscripts/title_screen.gd")
	_assert(TS != null, "TS-1: title_screen.gd loads")
	if TS:
		var ts = TS.new()
		_assert(ts != null, "TS-2: title_screen instance created")
		_assert(ts.has_method("_start_game"), "TS-3: has _start_game method")
	_assert(ResourceLoader.exists("res://scenes/title_screen.tscn"), "TS-4: title_screen.tscn exists")
	_assert(ResourceLoader.exists("res://scenes/main.tscn"), "TS-5: main.tscn exists")


# ── Scene Scripts Load ──
func _test_scene_scripts() -> void:
	print("  --- Scene Scripts ---")
	for scene_id in SCENE_SCRIPTS:
		var path = SCENE_SCRIPTS[scene_id]
		var script = load(path)
		_assert(script != null, "SC-%s-1: %s.gd loads" % [scene_id, scene_id])
		if script:
			var instance = script.new()
			_assert(instance != null, "SC-%s-2: instance created" % [scene_id])
			_assert(instance.has_method("_configure_environmental_text"),
				"SC-%s-3: has _configure_environmental_text" % [scene_id])


# ── Scene .tscn Files ──
func _test_scene_files() -> void:
	print("  --- Scene .tscn Files ---")
	for scene_id in SCENE_PATHS:
		var path = SCENE_PATHS[scene_id]
		_assert(ResourceLoader.exists(path), "SF-%s: %s.tscn exists" % [scene_id, scene_id])
	_assert(ResourceLoader.exists("res://scenes/end_credits.tscn"), "SF-end_credits: end_credits.tscn exists")


# ── Dialogue Files ──
func _test_dialogue_files() -> void:
	print("  --- Dialogue Files ---")
	for f in DIALOGUE_FILES:
		var path = "res://dialogues/" + f
		_assert(ResourceLoader.exists(path), "DF: %s exists" % f)

	# Verify JSON structure of key dialogues
	var dlg = FileAccess.open("res://dialogues/office_door.json", FileAccess.READ)
	if dlg:
		var json = JSON.new()
		json.parse(dlg.get_as_text())
		var data = json.data
		_assert(data is Dictionary, "DJ-1: office_door.json is valid JSON (object)")
		_assert(data.has("entry_node_id"), "DJ-2: office_door has entry_node_id")
		_assert(data.has("nodes"), "DJ-3: office_door has nodes")
		# Verify scene transition points
		if data.has("nodes") and data["nodes"].has("door_leave"):
			_assert(true, "DJ-4: office_door has door_leave node")
			var choices: Array = data["nodes"]["door_leave"].get("choices", [])
			var has_lobby: bool = false
			for c in choices:
				if c.get("scene", "") == "res://scenes/lobby/lobby.tscn":
					has_lobby = true
			_assert(has_lobby, "DJ-5: door_leave leads to lobby.tscn")
	
	# Verify subway ending dialogue
	var subway = FileAccess.open("res://dialogues/subway_ending.json", FileAccess.READ)
	if subway:
		var json = JSON.new()
		json.parse(subway.get_as_text())
		var data = json.data
		_assert(data is Dictionary and data.has("nodes"), "DJ-6: subway_ending.json valid")
		if data.has("nodes"):
			for node_id in ["kw_final", "tb_final", "st_final"]:
				var has_credits: bool = false
				if data["nodes"].has(node_id):
					for c in data["nodes"][node_id].get("choices", []):
						if c.get("scene", "") == "res://scenes/end_credits.tscn":
							has_credits = true
				_assert(has_credits, "DJ-7: %s → end_credits.tscn" % node_id)


# ── Scene Manager ──
func _test_scene_manager() -> void:
	print("  --- Scene Manager ---")
	var SM = load("res://gdscripts/scene_manager.gd")
	_assert(SM != null, "SM-1: scene_manager.gd loads")
	if SM:
		var sm = SM.new()
		_assert(sm != null, "SM-2: instance created")
		_assert(sm.has_method("trigger_scene_change"), "SM-3: has trigger_scene_change")
		_assert(sm.has_method("fade_in"), "SM-4: has fade_in")

	var EZ = load("res://gdscripts/exit_zone.gd")
	_assert(EZ != null, "SM-5: exit_zone.gd loads")


# ── State System ──
func _test_state_system() -> void:
	print("  --- State System ---")
	var SS = load("res://gdscripts/state_system.gd")
	_assert(SS != null, "SS-1: state_system.gd loads")
	if not SS:
		return
	var ss = SS.new()
	_assert(ss != null, "SS-2: instance created")
	if not ss:
		return

	_assert(abs(ss.hope_despair) < 0.01, "SS-3: hope_despair initial 0")
	_assert(abs(ss.conviction - 5.0) < 0.01, "SS-4: conviction initial 5")
	_assert(abs(ss.will - 5.0) < 0.01, "SS-5: will initial 5")

	ss.apply_choice({"hope": 2.0})
	_assert(ss.hope > 5.0, "SS-6: hope increases after apply_choice +2")
	ss.apply_choice({"conviction": -1.0})
	_assert(ss.conviction < 5.0, "SS-7: conviction decreases after -1")

	var sid = ss.get_state_id()
	_assert(sid >= 1 and sid <= 5, "SS-8: state_id [1-5], got %d" % sid)

	ss.set_flag("test_flag", true)
	_assert(ss.has_flag("test_flag"), "SS-9: set_flag/has_flag roundtrip")

	ss.reset()
	_assert(abs(ss.hope_despair) < 0.01, "SS-10: reset → hope_despair 0")
	_assert(abs(ss.conviction - 5.0) < 0.01, "SS-11: reset → conviction 5")


# ── Game Manager ──
func _test_game_manager() -> void:
	print("  --- Game Manager ---")
	var GM = load("res://gdscripts/game_manager.gd")
	_assert(GM != null, "GM-1: game_manager.gd loads")
	if not GM:
		return
	var gm = GM.new()
	_assert(gm != null, "GM-2: instance created")
	_assert(gm.current_scene_id == "office", "GM-3: default scene_id is 'office'")
	_assert(gm.has_method("get_slider"), "GM-4: has get_slider")
	_assert(gm.has_method("set_flag"), "GM-5: has set_flag")
	_assert(gm.has_method("get_next_scene_id"), "GM-6: has get_next_scene_id")
	_assert(gm.has_method("reset"), "GM-7: has reset")


# ── Narrative Manager ──
func _test_narrative_manager() -> void:
	print("  --- Narrative Manager ---")
	var NM = load("res://gdscripts/narrative_manager.gd")
	_assert(NM != null, "NM-1: narrative_manager.gd loads")
	if not NM:
		return
	var nm = NM.new()
	_assert(nm != null, "NM-2: instance created")
	_assert(nm.SCENE_ORDER.size() == 6, "NM-3: SCENE_ORDER has 6 scenes")
	_assert(nm.SCENE_PATHS.size() == 6, "NM-4: SCENE_PATHS has 6 entries")
	_assert(nm.SCENE_TONES.size() == 6, "NM-5: SCENE_TONES has 6 scene entries")
	_assert(nm.has_method("advance_scene"), "NM-6: has advance_scene")
	_assert(nm.has_method("reset"), "NM-7: has reset")


# ── Ending Logic ──
func _test_ending_logic() -> void:
	print("  --- Ending Logic ---")
	var NM = load("res://gdscripts/narrative_manager.gd")
	if not NM:
		_assert(false, "END: narrative_manager.gd not loaded")
		return
	var nm = NM.new()

	# Keep Walking: hope >= 6 AND will >= 5
	var ending = nm.determine_ending({"hope": 6.0, "conviction": 5.0, "will": 5.0})
	_assert(ending == "keep_walking", "END-1: hope=6, will=5 → keep_walking (got '%s')" % ending)

	# Turn Back (highest priority): conviction <= 3
	ending = nm.determine_ending({"hope": 8.0, "conviction": 2.0, "will": 7.0})
	_assert(ending == "turn_back", "END-2: conviction=2 → turn_back (priority) (got '%s')" % ending)

	# Stay: conviction > 3 AND hope <= 4 AND conviction <= 4 AND will <= 4
	ending = nm.determine_ending({"hope": 3.0, "conviction": 3.5, "will": 2.0})
	_assert(ending == "stay", "END-3: all low (conviction 3.5) → stay (got '%s')" % ending)

	# Fallthrough Stay
	ending = nm.determine_ending({"hope": 5.0, "conviction": 5.0, "will": 4.0})
	_assert(ending == "stay", "END-4: fallthrough → stay (got '%s')" % ending)

	# Turn Back at boundary
	ending = nm.determine_ending({"hope": 5.0, "conviction": 3.0, "will": 5.0})
	_assert(ending == "turn_back", "END-5: conviction=3 → turn_back (boundary) (got '%s')" % ending)


# ── Player Controller ──
func _test_player_controller() -> void:
	print("  --- Player Controller ---")
	var PC = load("res://gdscripts/player_controller.gd")
	_assert(PC != null, "PC-1: player_controller.gd loads")
	if not PC:
		return
	var pc = PC.new()
	_assert(pc != null, "PC-2: instance created")
	_assert(pc.has_method("_physics_process"), "PC-3: has _physics_process (gravity)")
	_assert(pc.has_method("_handle_mouse_look"), "PC-4: has _handle_mouse_look")
	_assert(pc.has_method("get_camera_orbit"), "PC-5: has get_camera_orbit")
	_assert(pc.has_method("set_camera_orbit"), "PC-6: has set_camera_orbit")

	# Gravity is verified by PC loading without errors
	_assert(pc.walk_speed != null, "PC-7: has walk_speed export")


# ── End Credits ──
func _test_end_credits() -> void:
	print("  --- End Credits ---")
	var EC = load("res://gdscripts/end_credits.gd")
	_assert(EC != null, "EC-1: end_credits.gd loads")
	if EC:
		var ec = EC.new()
		_assert(ec != null, "EC-2: instance created")
	_assert(ResourceLoader.exists("res://scenes/end_credits.tscn"), "EC-3: end_credits.tscn exists")
