extends SceneTree

var passed: int = 0
var failed: int = 0

func _init() -> void:
	print("=== GDScript Test Runner ===")
	print("Running tests in SceneTree mode...")

	_test_label_text_setting()
	_test_empty_text()
	_test_long_text()

	print("\n=== Results ===")
	print("Passed: ", passed)
	print("Failed: ", failed)

	if failed > 0:
		print("❌ Some tests FAILED")
		quit(1)
	else:
		print("✅ All tests passed!")
		quit(0)

func _test_label_text_setting() -> void:
	var label = Label.new()
	label.text = "Hello World"
	_assert(label.text == "Hello World", "Label text setting: 'Hello World'")

func _test_empty_text() -> void:
	var label = Label.new()
	label.text = ""
	_assert(label.text == "", "Label empty text: ''")

func _test_long_text() -> void:
	var label = Label.new()
	var long_text = ""
	for i in range(100):
		long_text += "e"
	long_text = "H" + long_text + "!"
	label.text = long_text
	_assert(len(label.text) > 0, "Label long text: length > 0")

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
		print("  ✅ ", name)
	else:
		failed += 1
		print("  ❌ ", name)
