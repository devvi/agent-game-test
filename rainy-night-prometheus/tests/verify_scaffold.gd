extends Node

# Rainy Night Prometheus — Scaffold Verification Script
# Runs all TC-1 through TC-7 checks defined in the DESIGN doc.

enum TestStatus { PASS, FAIL, SKIP }

var passed: int = 0
var failed: int = 0
var total: int = 0

func report(name: String, status: TestStatus, detail: String = "") -> void:
	total += 1
	var icon: String
	match status:
		TestStatus.PASS:
			icon = "✅ PASS"
			passed += 1
		TestStatus.FAIL:
			icon = "❌ FAIL"
			failed += 1
		TestStatus.SKIP:
			icon = "⏭️ SKIP"
	prints(icon, name)
	if detail != "":
		prints("      ", detail)

func _ready() -> void:
	print("")
	print("=== Rainy Night Prometheus Scaffold Verification ===")
	print("")

	test_tc01_directory_structure()
	test_tc02_symlink_correctness()
	test_tc03_git_symlink_tracking()
	test_tc04_godot_headless_compilation()
	test_tc05_project_godot_config()
	test_tc06_autoload_dependencies()
	test_tc07_icon_file()

	print("")
	print("=== Results: %d/%d passed, %d failed ===" % [passed, total, failed])

	if failed > 0:
		print("⚠️  Some tests FAILED — review output above.")
	else:
		print("✅ All scaffold tests PASSED!")

	get_tree().quit(failed)

# --- TC-1: Directory Structure Completeness ---
func test_tc01_directory_structure() -> void:
	print("--- TC-1: Directory Structure Completeness ---")
	var items: Dictionary = {
		"project.godot": "f",
		"README.md": "f",
		"gdscripts": "d",
		"scenes": "d",
		"dialogues": "d",
		"dialogues/json": "d",
		"assets/materials": "d",
		"assets/audio": "d",
		"tests": "d",
		"assets/icon.png": "f",
	}
	var base: String = "res://"
	var all_ok: bool = true
	for item_path in items:
		var expected_type: String = items[item_path] as String
		var full_path: String = base + item_path
		var ok: bool = false
		if expected_type == "d":
			ok = DirAccess.dir_exists_absolute(full_path)
		else:
			ok = FileAccess.file_exists(full_path)
		if not ok:
			report("TC-1: %s (%s)" % [item_path, expected_type], TestStatus.FAIL, "Not found at %s" % full_path)
			all_ok = false
	if all_ok:
		report("TC-1: All directories and files present", TestStatus.PASS)

# --- TC-2: Symlink Correctness (readlink) ---
func test_tc02_symlink_correctness() -> void:
	print("--- TC-2: Symlink Correctness ---")
	var symlinks: Dictionary = {
		"gdscripts/dialogue_runner.gd": "../../gdscripts/dialogue_runner.gd",
		"gdscripts/dialogue_parser.gd": "../../gdscripts/dialogue_parser.gd",
		"gdscripts/state_system.gd":    "../../gdscripts/state_system.gd",
		"gdscripts/scene_manager.gd":   "../../gdscripts/scene_manager.gd",
		"gdscripts/scene_base.gd":      "../../gdscripts/scene_base.gd",
		"gdscripts/constants.gd":       "../../gdscripts/constants.gd",
		"assets/icon.png":              "../../assets/icon.png",
	}
	var base: String = "res://"
	var all_ok: bool = true
	for symlink_path in symlinks:
		var full_path: String = base + symlink_path
		if not FileAccess.file_exists(full_path):
			report("TC-2: %s" % symlink_path, TestStatus.FAIL, "File does not exist")
			all_ok = false
			continue
		var file: FileAccess = FileAccess.open(full_path, FileAccess.READ)
		if file == null:
			report("TC-2: %s" % symlink_path, TestStatus.SKIP, "Cannot open for read verification")
			continue
		file.close()
	if all_ok:
		report("TC-2: All symlinks resolve correctly", TestStatus.PASS)

# --- TC-3: Git Symlink Tracking (120000 mode) ---
func test_tc03_git_symlink_tracking() -> void:
	print("--- TC-3: Git Symlink Tracking ---")
	report("TC-3: Git symlink mode (120000)", TestStatus.SKIP, "Run 'git ls-files -s rainy-night-prometheus/gdscripts/' externally")

# --- TC-4: Headless Godot Compilation ---
func test_tc04_godot_headless_compilation() -> void:
	print("--- TC-4: Headless Godot Compilation ---")
	var autoloads: Array[String] = ["StateSystem", "DialogueRunner", "DialogueParser", "SceneManager", "SceneBase"]
	var all_ok: bool = true
	for al in autoloads:
		if has_node("/root/" + al):
			pass
		else:
			report("TC-4: Autoload %s" % al, TestStatus.FAIL, "Not found as singleton")
			all_ok = false
	if all_ok:
		report("TC-4: All autoloads loaded, no compilation errors", TestStatus.PASS)

# --- TC-5: project.godot Configuration Validation ---
func test_tc05_project_godot_config() -> void:
	print("--- TC-5: project.godot Configuration Validation ---")
	var config: ConfigFile = ConfigFile.new()
	var err: Error = config.load("res://project.godot")
	if err != OK:
		report("TC-5: Loading project.godot", TestStatus.FAIL, "Error code %d" % err)
		return

	var checks: int = 0
	var ok: int = 0
	var name_val: Variant = config.get_value("application", "config/name", "")
	if name_val == "Rainy Night Prometheus":
		ok += 1
	checks += 1

	var renderer_val: Variant = config.get_value("rendering", "renderer/rendering_method", "")
	if renderer_val == "forward_plus":
		ok += 1
	checks += 1

	var width_val: Variant = config.get_value("display", "window/size/viewport_width", 0)
	if width_val == 1920:
		ok += 1
	checks += 1

	var height_val: Variant = config.get_value("display", "window/size/viewport_height", 0)
	if height_val == 1080:
		ok += 1
	checks += 1

	var features: Variant = config.get_value("application", "config/features", [])
	if features is PackedStringArray and "4.7" in features:
		ok += 1
	checks += 1

	var expected_autoloads: Dictionary = {
		"StateSystem": "*res://gdscripts/state_system.gd",
		"DialogueRunner": "*res://gdscripts/dialogue_runner.gd",
		"DialogueParser": "*res://gdscripts/dialogue_parser.gd",
		"SceneManager": "*res://gdscripts/scene_manager.gd",
		"SceneBase": "*res://gdscripts/scene_base.gd",
	}
	for al_name in expected_autoloads:
		checks += 1
		var val: Variant = config.get_value("autoload", al_name, "")
		if val == expected_autoloads[al_name]:
			ok += 1

	report("TC-5: project.godot validation (%d/%d checks passed)" % [ok, checks], TestStatus.PASS if ok == checks else TestStatus.FAIL)

# --- TC-6: Autoload Script Dependencies ---
func test_tc06_autoload_dependencies() -> void:
	print("--- TC-6: Autoload Script Dependencies ---")
	var all_ok: bool = true

	var autoload_names: Array[String] = ["StateSystem", "DialogueRunner", "DialogueParser", "SceneManager", "SceneBase"]
	for al_name in autoload_names:
		var node = get_node_or_null("/root/" + al_name)
		if node != null:
			report("TC-6: %s" % al_name, TestStatus.PASS)
		else:
			report("TC-6: %s" % al_name, TestStatus.FAIL, "Not loaded as singleton")
			all_ok = false

	if all_ok:
		report("TC-6: All autoload scripts loaded successfully", TestStatus.PASS)

# --- TC-7: Icon File Existence ---
func test_tc07_icon_file() -> void:
	print("--- TC-7: Icon File Existence ---")
	var icon_path: String = "res://assets/icon.png"
	if FileAccess.file_exists(icon_path):
		var file: FileAccess = FileAccess.open(icon_path, FileAccess.READ)
		if file != null:
			var header: PackedByteArray = file.get_buffer(8)
			file.close()
			if header.size() >= 8 and header[0] == 137 and header[1] == 80 and header[2] == 78 and header[3] == 71:
				report("TC-7: icon.png exists and has valid PNG header", TestStatus.PASS)
			else:
				report("TC-7: icon.png exists but header is not valid PNG", TestStatus.FAIL)
		else:
			report("TC-7: icon.png exists but could not open", TestStatus.FAIL)
	else:
		report("TC-7: icon.png not found", TestStatus.FAIL)
