extends Area3D
class_name InteractiveArea

enum FeedbackMode {
	HOVER_ONLY,
	PROXIMITY_ONLY,
	BOTH,
	INDICATOR_ONLY,
}

@export var feedback_mode: FeedbackMode = FeedbackMode.BOTH
@export var is_interactable: bool = true
@export var parent_mesh: NodePath = NodePath("")
@export var decal_size: Vector2 = Vector2(0.8, 0.8)
@export var light_energy: float = 1.5
@export var indicator_texture: Texture2D
@export var indicator_size: float = 0.3
@export var fade_in_duration: float = 0.2
@export var fade_out_duration: float = 0.3
@export var pulse_duration: float = 1.5
@export var scale_pulse_intensity: float = 0.05
@export var glow_color: Color = Color(1.0, 0.667, 0.333, 0.5)
@export var proximity_distance: float = 2.0

signal hovered()
signal unhovered()
signal proximity_entered()
signal proximity_exited()
signal interactable_clicked()

var _hover_decal: Decal
var _proximity_light: OmniLight3D
var _indicator_sprite: Sprite3D
var _parent_node: Node3D
var _is_hovered: bool = false
var _is_nearby: bool = false
var _tween: Tween


func _ready() -> void:
	_parent_node = get_node_or_null(parent_mesh) as Node3D

	match feedback_mode:
		FeedbackMode.HOVER_ONLY:
			_build_hover_decal()
		FeedbackMode.PROXIMITY_ONLY:
			_build_proximity_light()
		FeedbackMode.BOTH:
			_build_hover_decal()
			_build_proximity_light()
		FeedbackMode.INDICATOR_ONLY:
			pass

	if indicator_texture:
		_build_indicator_sprite()

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	input_event.connect(_on_input_event)

	_start_indicator_pulse()

	if not find_children("*", "CollisionShape3D", false):
		push_warning("InteractiveArea: no CollisionShape3D child — mouse/input events will not work")


func _build_hover_decal() -> void:
	_hover_decal = Decal.new()
	_hover_decal.name = "HoverDecal"
	_hover_decal.size = Vector3(decal_size.x, 1.0, decal_size.y)
	_hover_decal.position = Vector3(0, -0.5, 0)
	_hover_decal.visible = false

	var mat := StandardMaterial3D.new()
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = ResourceLoader.load("res://assets/textures/glow_amber.webp")
	mat.albedo_color = Color(glow_color.r, glow_color.g, glow_color.b, 0.0)
	mat.emission_enabled = true
	mat.emission = Color(glow_color.r, glow_color.g, glow_color.b)
	mat.emission_energy_multiplier = 0.5
	mat.no_depth_test = true

	_hover_decal.set_material_override(mat)
	add_child(_hover_decal)


func _build_proximity_light() -> void:
	_proximity_light = OmniLight3D.new()
	_proximity_light.name = "ProximityLight"
	_proximity_light.light_color = glow_color
	_proximity_light.omni_range = proximity_distance
	_proximity_light.light_energy = 0.0
	_proximity_light.visible = false
	add_child(_proximity_light)


func _build_indicator_sprite() -> void:
	_indicator_sprite = Sprite3D.new()
	_indicator_sprite.name = "IndicatorSprite"
	_indicator_sprite.texture = indicator_texture
	_indicator_sprite.position = Vector3(0, 2.0, 0)
	_indicator_sprite.pixel_size = 0.01
	_indicator_sprite.scale = Vector3.ONE * indicator_size
	_indicator_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_indicator_sprite.modulate = Color(1, 1, 1, 0)
	add_child(_indicator_sprite)


func _on_mouse_entered() -> void:
	_is_hovered = true
	match feedback_mode:
		FeedbackMode.HOVER_ONLY, FeedbackMode.BOTH:
			_tween_hover_decal(glow_color.a)
			if _parent_node:
				_tween_scale_pulse(true)
		FeedbackMode.PROXIMITY_ONLY, FeedbackMode.INDICATOR_ONLY:
			pass
	hovered.emit()


func _on_mouse_exited() -> void:
	_is_hovered = false
	match feedback_mode:
		FeedbackMode.HOVER_ONLY, FeedbackMode.BOTH:
			_tween_hover_decal(0.0)
			if _parent_node:
				_tween_scale_pulse(false)
		FeedbackMode.PROXIMITY_ONLY, FeedbackMode.INDICATOR_ONLY:
			pass
	unhovered.emit()


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_is_nearby = true
	match feedback_mode:
		FeedbackMode.PROXIMITY_ONLY, FeedbackMode.BOTH:
			_tween_proximity_light(light_energy)
		FeedbackMode.HOVER_ONLY, FeedbackMode.INDICATOR_ONLY:
			pass
	proximity_entered.emit()


func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_is_nearby = false
	match feedback_mode:
		FeedbackMode.PROXIMITY_ONLY, FeedbackMode.BOTH:
			_tween_proximity_light(0.0)
		FeedbackMode.HOVER_ONLY, FeedbackMode.INDICATOR_ONLY:
			pass
	proximity_exited.emit()


func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and is_interactable:
		interactable_clicked.emit()


func _tween_hover_decal(target_alpha: float) -> void:
	if not _hover_decal:
		return
	if _tween and _tween.is_valid():
		_tween.kill()

	var mat := _hover_decal.material_override as BaseMaterial3D
	if not mat:
		return

	_tween = create_tween().set_parallel(true)
	_tween.tween_method(func(a: float): mat.albedo_color.a = a, mat.albedo_color.a, target_alpha, fade_in_duration if target_alpha > 0 else fade_out_duration)

	if target_alpha > 0:
		_hover_decal.visible = true
		_tween.tween_callback(func(): pass)
	else:
		_tween.tween_callback(func(): _hover_decal.visible = false).set_delay(fade_out_duration)


func _tween_proximity_light(target_energy: float) -> void:
	if not _proximity_light:
		return
	if _tween and _tween.is_valid():
		_tween.kill()

	_proximity_light.visible = target_energy > 0
	_tween = create_tween()
	_tween.tween_property(_proximity_light, "light_energy", target_energy, fade_in_duration if target_energy > 0 else fade_out_duration)


func _tween_scale_pulse(active: bool) -> void:
	if not _parent_node:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	if not active:
		_parent_node.scale = Vector3.ONE
		return

	var base_scale: Vector3 = _parent_node.scale
	var offset: float = scale_pulse_intensity

	_tween = create_tween().set_loops()
	_tween.tween_property(_parent_node, "scale", base_scale * (1.0 + offset), pulse_duration * 0.5).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_parent_node, "scale", base_scale * (1.0 - offset), pulse_duration * 0.5).set_ease(Tween.EASE_IN_OUT)


func _start_indicator_pulse() -> void:
	if not _indicator_sprite:
		return
	if not is_instance_valid(_indicator_sprite):
		return
	var tween := create_tween().set_loops()
	tween.tween_property(_indicator_sprite, "modulate:a", 0.8, pulse_duration * 0.5).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_indicator_sprite, "modulate:a", 0.4, pulse_duration * 0.5).set_ease(Tween.EASE_IN_OUT)


func _exit_tree() -> void:
	if mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.disconnect(_on_mouse_entered)
	if mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.disconnect(_on_mouse_exited)
	if body_entered.is_connected(_on_body_entered):
		body_entered.disconnect(_on_body_entered)
	if body_exited.is_connected(_on_body_exited):
		body_exited.disconnect(_on_body_exited)
	if input_event.is_connected(_on_input_event):
		input_event.disconnect(_on_input_event)

	if _tween and _tween.is_valid():
		_tween.kill()
