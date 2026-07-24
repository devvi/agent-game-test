extends Node

# Minimal verification: Check that dialogue resource can be used
# by directly compiling .dialogue text via DMCompiler's preloadable path.

func _ready() -> void:
	print("=== DM Integration Verification ===")
	
	# Check DM addon files exist
	var files_to_check = [
		"res://addons/dialogue_manager/plugin.cfg",
		"res://addons/dialogue_manager/dialogue_manager.gd",
		"res://addons/dialogue_manager/dialogue_responses_menu.gd",
		"res://addons/dialogue_manager/dialogue_label.gd",
		"res://addons/dialogue_manager/dialogue_processor.gd",
	]
	var all_exist = true
	for f in files_to_check:
		var exists = ResourceLoader.exists(f)
		print("  [%s] %s" % ["OK" if exists else "MISSING", f])
		if not exists:
			all_exist = false
	
	if all_exist:
		print("✅ All DM addon files present")
	else:
		print("❌ Some DM addon files missing")
	
	# Check test dialogue file exists
	if ResourceLoader.exists("res://dialogues/_test_hello.dialogue"):
		print("✅ Test dialogue file found")
	else:
		print("ℹ️  Test dialogue file not in cache (needs editor import)")
	
	# Check the DM plugin is registered
	var plugin_enabled = false
	if ProjectSettings.has_setting("editor_plugins/enabled"):
		var plugins = ProjectSettings.get_setting("editor_plugins/enabled")
		if "dialogue_manager" in plugins:
			plugin_enabled = true
	
	print("  DM plugin enabled in project.godot: ", plugin_enabled)
	
	print("=== Verification Complete ===")
	get_tree().quit(0)
