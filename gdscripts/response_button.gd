extends Button

var response: DialogueResponse:
	set(value):
		response = value
		text = response.text
		if not response.is_allowed:
			disabled = true
			modulate = Color(0.5, 0.5, 0.5, 0.5)
