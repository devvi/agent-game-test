extends CanvasLayer
class_name SceneTitleOverlay

# SceneTitleOverlay — Scene-title card shown during fade transitions.
# Attached to the old scene before scene change, persists visually during the
# scene file swap, and self-destructs after display duration.
#
# Node structure:
#   SceneTitleOverlay (CanvasLayer)
#   ├── ColorRect (full-screen black, modulate.a controlled by animation)
#   ├── TitleLabel (Label — scene name, centered)
#   ├── SubtitleLabel (Label — route context / tone text)
#   └── AnimationPlayer (fade_in_title, fade_out_title animations)

const Constants = preload("res://gdscripts/constants.gd")

var scene_id: String = ""              # Set by SceneManager before display
var route_context: String = ""         # Route-aware subtitle text
var display_duration: float = Constants.NAV_TITLE_DISPLAY_DURATION

var _title_label: Label
var _subtitle_label: Label
var _color_rect: ColorRect
var _anim_player: AnimationPlayer


func _init(p_scene_id: String = "", p_route_context: String = "") -> void:
	scene_id = p_scene_id
	route_context = p_route_context
	layer = 129  # Above FadeCurtain (layer 128)

	# Build node structure
	_color_rect = ColorRect.new()
	_color_rect.name = "ColorRect"
	_color_rect.color = Color.BLACK
	_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_color_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_color_rect.modulate = Color(0, 0, 0, 0)  # Start transparent
	add_child(_color_rect)

	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE, 0)
	_title_label.size = Vector2(600, 60)
	_title_label.position = Vector2(-300, -40)
	_title_label.add_theme_font_size_override("font_size", 36)
	_title_label.add_theme_color_override("font_color", Color.WHITE)
	_title_label.modulate = Color(1, 1, 1, 0)  # Start transparent
	_title_label.text = _get_scene_display_name()
	add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.name = "SubtitleLabel"
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE, 0)
	_subtitle_label.size = Vector2(600, 40)
	_subtitle_label.position = Vector2(-300, 20)
	_subtitle_label.add_theme_font_size_override("font_size", 18)
	_subtitle_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1.0))
	_subtitle_label.modulate = Color(1, 1, 1, 0)  # Start transparent
	_subtitle_label.text = route_context
	add_child(_subtitle_label)

	# Create AnimationPlayer
	_anim_player = AnimationPlayer.new()
	_anim_player.name = "AnimationPlayer"
	add_child(_anim_player)
	_build_animations()


func _build_animations() -> void:
	var library := AnimationLibrary.new()

	# fade_in_title: fade in title (0.5s) — syncs with curtain fade-out
	var anim_in := Animation.new()
	anim_in.length = 0.5
	var track_in_color := anim_in.add_track(Animation.TYPE_VALUE)
	anim_in.track_set_path(track_in_color, "ColorRect:modulate")
	anim_in.track_insert_key(track_in_color, 0.0, Color(0, 0, 0, 0))
	anim_in.track_insert_key(track_in_color, 0.5, Color(0, 0, 0, 0.6))

	var track_in_title := anim_in.add_track(Animation.TYPE_VALUE)
	anim_in.track_set_path(track_in_title, "TitleLabel:modulate")
	anim_in.track_insert_key(track_in_title, 0.2, Color(1, 1, 1, 0))
	anim_in.track_insert_key(track_in_title, 0.5, Color(1, 1, 1, 1))

	var track_in_sub := anim_in.add_track(Animation.TYPE_VALUE)
	anim_in.track_set_path(track_in_sub, "SubtitleLabel:modulate")
	anim_in.track_insert_key(track_in_sub, 0.3, Color(1, 1, 1, 0))
	anim_in.track_insert_key(track_in_sub, 0.5, Color(1, 1, 1, 0.8))

	library.add_animation("fade_in_title", anim_in)

	# fade_out_title: fade out from current state (0.5s)
	var anim_out := Animation.new()
	anim_out.length = 0.5

	var track_out_color := anim_out.add_track(Animation.TYPE_VALUE)
	anim_out.track_set_path(track_out_color, "ColorRect:modulate")
	anim_out.track_insert_key(track_out_color, 0.0, Color(0, 0, 0, 0.6))
	anim_out.track_insert_key(track_out_color, 0.5, Color(0, 0, 0, 0))

	var track_out_title := anim_out.add_track(Animation.TYPE_VALUE)
	anim_out.track_set_path(track_out_title, "TitleLabel:modulate")
	anim_out.track_insert_key(track_out_title, 0.0, Color(1, 1, 1, 1))
	anim_out.track_insert_key(track_out_title, 0.5, Color(1, 1, 1, 0))

	var track_out_sub := anim_out.add_track(Animation.TYPE_VALUE)
	anim_out.track_set_path(track_out_sub, "SubtitleLabel:modulate")
	anim_out.track_insert_key(track_out_sub, 0.0, Color(1, 1, 1, 0.8))
	anim_out.track_insert_key(track_out_sub, 0.5, Color(1, 1, 1, 0))

	library.add_animation("fade_out_title", anim_out)

	_anim_player.add_animation_library("", library)


## Show the title card with fade-in animation.
## Optionally specify a custom scene_id and route_context.
func show_title(p_scene_id: String = "", p_route_context: String = "") -> void:
	if p_scene_id:
		scene_id = p_scene_id
		_title_label.text = _get_scene_display_name()
	if p_route_context:
		route_context = p_route_context
		_subtitle_label.text = route_context
	_anim_player.play("fade_in_title")


## Hide the title card with fade-out, then queue_free.
func hide_title() -> void:
	_anim_player.play("fade_out_title")
	await _anim_player.animation_finished
	queue_free()


## Auto-destroy after display_duration. Called after show_title().
func start_auto_dismiss() -> void:
	await get_tree().create_timer(display_duration).timeout
	hide_title()


## Get Chinese display name for a scene_id.
func _get_scene_display_name() -> String:
	match scene_id:
		"office": return "办公室"
		"lobby": return "大厅"
		"convenience_store": return "便利店"
		"street": return "街道"
		"bridge": return "天桥"
		"underpass": return "地下通道"
		"subway_station": return "地铁站"
		_: return scene_id.capitalize()
