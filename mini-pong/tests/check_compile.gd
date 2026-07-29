extends SceneTree
## Headless compile checker — loads all .gd files in gdscripts/ and tests/ once.
## Usage: godot --path mini-pong/ --headless --script tests/check_compile.gd
## Exit 0 = all scripts loaded. Exit 1 = one or more failed.

var _pass: int = 0
var _fail: int = 0

func _init() -> void:
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
