extends RefCounted
## Test suite for neon visual system (#289) — 9 automated + 8 manual-only.
## Runs under godot --headless --script via run_tests.gd.

var passed: int = 0
var failed: int = 0


func run() -> void:
	_test_worldenv_glow_bloom()    # TC2
	_test_worldenv_bg_color()       # TC3
	_test_project_clear_color()     # TC4
	_test_neon_shader_loads()       # TC5
	_test_gradient_loads()          # TC6
	_test_particle_mat_loads()      # TC7
	_test_ball_trail_compiles()     # TC8
	_test_score_flash_compiles()    # TC9
	_print_manual_tests()           # TC10–TC17
	# TC1 (headless exit code 0) is covered by CI — the runner itself compiling
	# and running implies it passes.


func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


# ── Scenario A: WorldEnvironment Config Compilation ──

func _test_worldenv_glow_bloom() -> void:
	var content = FileAccess.get_file_as_string("res://scenes/world_environment.tscn")
	_assert(content != "", "TC2: world_environment.tscn readable")
	_assert(content.contains("glow_bloom = 0.8"), "TC2: glow_bloom = 0.8 present in .tscn")


func _test_worldenv_bg_color() -> void:
	var content = FileAccess.get_file_as_string("res://scenes/world_environment.tscn")
	_assert(content.contains("background_color = Color(0.039, 0.039, 0.071, 1)"), "TC3: background_color present in .tscn")


func _test_project_clear_color() -> void:
	var content = FileAccess.get_file_as_string("res://project.godot")
	_assert(content != "", "TC4: project.godot readable")
	_assert(content.contains("environment/defaults/default_clear_color"), "TC4: default_clear_color in project.godot (no rendering/ prefix)")
	_assert(not content.contains("rendering/environment/defaults/default_clear_color"), "TC4: no double-prefixed rendering/rendering clear_color key")


# ── Scenario B: Resource File Integrity ──

func _test_neon_shader_loads() -> void:
	var shader = load("res://gdscripts/neon_glow.gdshader")
	_assert(shader != null, "TC5: neon_glow.gdshader loads successfully")


func _test_gradient_loads() -> void:
	var gradient = load("res://assets/gradient_neon.tres")
	_assert(gradient != null, "TC6: gradient_neon.tres loads successfully")


func _test_particle_mat_loads() -> void:
	# In --script mode, UID-based ext-resource references (ExtResource("uid://..."))
	# don't resolve because the resource cache isn't fully initialized.
	# Verify file integrity via FileAccess instead of load().
	var content = FileAccess.get_file_as_string("res://assets/particle_material.tres")
	_assert(content != "", "TC7: particle_material.tres readable")
	_assert(content.contains("lifetime = 0.5"), "TC7: lifetime = 0.5 present")
	_assert(content.contains("spread = 15.0"), "TC7: spread = 15.0 present")
	_assert(content.contains("color_ramp"), "TC7: color_ramp reference present")


# ── Scenario C: Script Compilation ──

func _test_ball_trail_compiles() -> void:
	var script = load("res://gdscripts/ball_trail.gd")
	_assert(script != null, "TC8: ball_trail.gd compiles and loads")


func _test_score_flash_compiles() -> void:
	var script = load("res://gdscripts/score_flash.gd")
	_assert(script != null, "TC9: score_flash.gd compiles and loads")


# ── Scenario D: Visual Effects — Manual Only ──

func _print_manual_tests() -> void:
	print("MANUAL ONLY: TC10–TC17 — verify in Godot editor")
	print("  TC10: Dark background (#0a0a12) visible on game run")
	print("  TC11: Player paddle glow (#4a90d9) — ShaderMaterial applied")
	print("  TC12: AI paddle glow (#ff3355) — ShaderMaterial applied")
	print("  TC13: Ball trail (blue→purple gradient) — GPUParticles2D emitting")
	print("  TC14: Ball stationary → no trail — particles stopped")
	print("  TC15: Score flash (0.2s fade) — ColorRect tween")
	print("  TC16: Dashed center line visible")
	print("  TC17: Rapid score flashes don't overlap — old tween killed")
