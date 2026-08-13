extends Node
## AudioEngine — autoload for real-time audio synthesis via AudioStreamGenerator.
## 5 sound effects: paddle_hit, wall_bounce, score, game_over, brick_break (#450).
## Tone synthesis uses sin waves with attack/decay envelopes; brick_break (#450)
## uses a fixed-seed noise burst with exponential decay envelope.
## Gracefully degrades when AudioServer is unavailable (headless mode).
##
## Design: docs/DESIGN/296-pause-and-sound.md §2.2
## Parent Issue: #296

const SAMPLE_RATE := 44100
const CONSTS = preload("res://gdscripts/constants.gd")

var _playback = null
var _enabled: bool = false
var _stream_player = null  # AudioStreamPlayer node


func _ready() -> void:
	# Guard: AudioServer unavailable in headless mode
	if not AudioServer:
		push_warning("AudioEngine: AudioServer unavailable — audio disabled")
		return

	# Signal connections for event-driven sounds
	# Use get_singleton_list() instead of has_singleton() to avoid
	# Godot 4.7.1 engine ERROR log when singleton doesn't exist (breaks CI grep).
	var slist := Engine.get_singleton_list()
	if not slist.has("GameManager"):
		push_warning("AudioEngine: GameManager singleton not available — signal connections skipped")
		return
	var gm = Engine.get_singleton("GameManager")
	if is_instance_valid(gm):
		if gm.has_signal("scored"):
			gm.scored.connect(_on_scored)
		if gm.has_signal("match_over"):
			gm.match_over.connect(_on_match_over)

	_setup_generator()
	_enabled = true


func _setup_generator() -> void:
	var generator = AudioStreamGenerator.new()
	generator.mix_rate = SAMPLE_RATE
	generator.buffer_length = 0.5  # 500ms buffer, enough for all sound effects

	var player = AudioStreamPlayer.new()
	player.stream = generator
	player.name = "AudioStreamGenerator"
	add_child(player)
	player.play()
	_playback = player.get_stream_playback()
	_stream_player = player
	# Pause until first sound plays — saves CPU by not filling silence
	player.stream_paused = true


## ── Public API ──

func play_paddle_hit() -> void:
	"""High-frequency short blip (~200Hz, 50ms, fast decay)."""
	_play_tone(200.0, 0.05, 0.8)


func play_wall_bounce() -> void:
	"""Low-frequency thud (~100Hz, 120ms, slow decay)."""
	_play_tone(100.0, 0.12, 0.6)


func play_score() -> void:
	"""3-note ascending arpeggio: C5→E5→G5, 80ms each."""
	_play_tone(523.25, 0.08, 0.7)  # C5
	_play_tone(659.25, 0.08, 0.7)  # E5
	_play_tone(783.99, 0.08, 0.7)  # G5


func play_game_over() -> void:
	"""Long fade-out tone (~440Hz, 1s, linear decay)."""
	_play_tone(440.0, 1.0, 0.5, true)


func play_brick_break() -> void:
	"""拆砖碎裂音: 噪声突发 + 快速指数衰减 (~80ms)。#450"""
	_play_noise_burst(
		CONSTS.BRICK_BREAK_DURATION,
		CONSTS.BRICK_BREAK_VOLUME,
		CONSTS.BRICK_BREAK_SEED
	)


## ── Internal ──

func _play_tone(freq: float, duration: float, volume: float, fade_out: bool = false) -> void:
	if not _enabled or not _playback:
		return

	var samples := int(SAMPLE_RATE * duration)
	var frame: Vector2

	# Resume the stream for this sound
	if _stream_player:
		_stream_player.stream_paused = false

	for i in range(samples):
		var t := float(i) / SAMPLE_RATE
		var envelope = volume
		if fade_out:
			envelope = volume * (1.0 - t / duration)  # linear fade
		else:
			# Fast decay envelope: attack first 5%, sustain middle, decay last 30%
			if t < duration * 0.05:
				envelope = volume * (t / (duration * 0.05))  # attack
			elif t > duration * 0.7:
				envelope = volume * (1.0 - (t - duration * 0.7) / (duration * 0.3))  # decay

		var sample_val = envelope * sin(2.0 * PI * freq * t)
		frame = Vector2(sample_val, sample_val)
		_playback.push_frame(frame)

	# Pause stream after sound completes (silence = no CPU)
	if _stream_player:
		_stream_player.stream_paused = true


func _play_noise_burst(duration: float, volume: float, seed: int) -> void:
	"""固定种子白噪声 × 指数衰减包络 exp(-t/τ)，τ = duration/4。"""
	if not _enabled or not _playback:
		return

	var samples := int(SAMPLE_RATE * duration)
	var tau := duration / 4.0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	if _stream_player:
		_stream_player.stream_paused = false

	for i in range(samples):
		var t := float(i) / SAMPLE_RATE
		var envelope := volume * exp(-t / tau)
		var sample_val := (rng.randf() * 2.0 - 1.0) * envelope
		_playback.push_frame(Vector2(sample_val, sample_val))

	if _stream_player:
		_stream_player.stream_paused = true


func pause_stream() -> void:
	if not _enabled:
		return
	if _stream_player:
		_stream_player.stream_paused = true


func resume_stream() -> void:
	pass  # Stream auto-resumes on next _play_tone() call; no-op here


## ── Signal Handlers ──

func _on_scored(_winner: String) -> void:
	play_score()


func _on_match_over(_winner: String) -> void:
	play_game_over()
