extends SceneTree
## Headless compile checker — loads all .gd files in gdscripts/ and tests/ once.
## Usage: godot --path shandong-wolf/ --headless --script tests/check_compile.gd
## Exit 0 = all scripts loaded. Exit 1 = one or more failed.
##
## Uses call_deferred to defer the check until autoload singletons are
## initialized, so scripts that reference autoload names can resolve
## those identifiers during compilation.

var _pass: int = 0
var _fail: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for dir in ["res://gdscripts/", "res://tests/"]:
		_check_dir(dir)
	print("COMPILE CHECK: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check_dir(dir_path: String) -> void:
	var files: Array = DirAccess.get_files_at(dir_path)
	files.sort()
	for f in files:
		if not f.ends_with(".gd"):
			continue
		var path: String = dir_path + f
		if load(path) != null:
			_pass += 1
		else:
			_fail += 1
			push_error("FAILED to load: %s" % path)
