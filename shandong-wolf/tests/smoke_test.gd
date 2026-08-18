extends SceneTree
## Smoke test for shandong-wolf — verifies project loads headless.
## Usage: godot --path shandong-wolf/ --headless --script tests/smoke_test.gd
## Exit 0 = OK.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("SMOKE OK: shandong-wolf skeleton loads")
	quit(0)
