extends Sprite3D

@export var pulse_speed: float = 1.5
@export var bob_height: float = 0.1
@export var min_alpha: float = 0.4
@export var max_alpha: float = 0.8


func _ready() -> void:
	var alpha_tween := create_tween().set_loops()
	alpha_tween.tween_property(self, "modulate:a", max_alpha, pulse_speed * 0.5).set_ease(Tween.EASE_IN_OUT)
	alpha_tween.tween_property(self, "modulate:a", min_alpha, pulse_speed * 0.5).set_ease(Tween.EASE_IN_OUT)

	var base_y: float = position.y
	var bob_tween := create_tween().set_loops()
	bob_tween.tween_property(self, "position:y", base_y + bob_height, pulse_speed * 0.5).set_ease(Tween.EASE_IN_OUT)
	bob_tween.tween_property(self, "position:y", base_y - bob_height, pulse_speed * 0.5).set_ease(Tween.EASE_IN_OUT)
