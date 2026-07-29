extends SceneTree
## Headless compile checker — loads all .gd files in gdscripts/ and tests/ once.
## Usage: godot --path mini-pong/ --headless --script tests/check_compile.gd
## Exit 0 = all scripts loaded. Exit 1 = one or more failed.
##
## Uses call_deferred to defer the check until autoload singletons are
## initialized, so scripts that reference autoload names (e.g. GameManager)
## can resolve those identifiers during compilation.

var _pass: int = 0
var _fail: int = 0

func _init() -> void:
	# Defer to next idle frame — by then autoloads are registered and
	# their names are available for GDScript identifier resolution.
	call_deferred("_run_check")

func _run_check() -> void:
	var dirs := [
		"res://gdscripts/",
		"res://tests/",
	]
	var scripts: Array[String] = []

	for d in dirs:
		var dir = DirAccess.open(d)
		if dir == null:
			print("SKIP: cannot open %s" % d)
			continue
		dir.list_dir_begin()
		var fname = dir.get_next()
		while fname != "":
			if fname.ends_with(".gd") or fname.ends_with(".gdshader"):
				scripts.append(d + fname)
			fname = dir.get_next()
		dir.list_dir_end()

	scripts.sort()
	for path in scripts:
		var res = load(path)
		if res == null:
			print("FAIL: %s — load returned null" % path)
			_fail += 1
		else:
			print("OK: %s" % path)
			_pass += 1

	print("\nCompile check: %d loaded, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
