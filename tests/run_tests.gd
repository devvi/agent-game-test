extends Node

# GDScript test runner for Godot headless mode
# Uses direct OS.exit() since --script mode has no SceneTree

var passed: int = 0
var failed: int = 0

func _init() -> void:
	# _init runs before _ready in --script mode
	print("=== GDScript Test Runner ===")
	print("Running tests...")

	_test_placeholder()

	print("\n=== Results ===")
	print("Passed: ", passed)
	print("Failed: ", failed)

	if failed > 0:
		print("❌ Some tests FAILED")
		OS.call_deferred("exit", 1)
	else:
		print("✅ All tests passed!")
		OS.call_deferred("exit", 0)

func _test_placeholder() -> void:
	# Placeholder test — always passes
	_assert(true, "Placeholder test (remove me!)")

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
		print("  ✅ ", name)
	else:
		failed += 1
		print("  ❌ ", name)
