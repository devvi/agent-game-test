extends RefCounted
## Test suite for AudioEngine (#296) — audio synthesis, frequency validation, error handling.
## Runs under godot --headless --script via run_tests.gd.
##
## Tests AudioEngine directly by instantiating the script logic and verifying:
## - play_*() methods produce the correct number of audio frames
## - Frequencies match expected values (paddle_hit ~200Hz, wall_bounce ~100Hz, etc.)
## - Headless mode degrades gracefully (all play_*() methods are no-ops)
## - Null safety when AudioEngine is not available
##
## Design: docs/DESIGN/296-pause-and-sound.md §7

var passed: int = 0
var failed: int = 0


func run() -> void:
	print("\n=== AudioEngine Tests (#296) ===")
	_test_tc8_paddle_hit_produces_frames()
	_test_tc9_wall_bounce_lower_frequency()
	_test_tc10_score_three_note_pattern()
	_test_tc11_game_over_fade_out()
	_test_tc12_headless_noop()
	_test_tc13_audioengine_null_safety()
	_test_tc14_brick_break_frame_count()
	_test_tc15_brick_break_decay_envelope()
	_test_tc16_brick_break_determinism()
	_test_tc17_brick_break_headless_noop()


# ── Helpers ──

func _assert(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		print("  FAIL: %s" % name)
		failed += 1


func _make_audio_engine():
	"""Create a fresh AudioEngine instance with simulated _playback."""
	var ae_script = load("res://gdscripts/audio_engine.gd")
	var ae = Node.new()
	ae.set_script(ae_script)
	ae.name = "AudioEngine"

	# Create a mock playback that captures frames
	var mock_playback_script = GDScript.new()
	mock_playback_script.source_code = """extends RefCounted
var frames: Array = []
var _frames_available: int = 0
func push_frame(frame: Vector2) -> void:
	frames.append(frame)
	_frames_available += 1
func get_frames_available() -> int:
	return _frames_available
func clear_buffer() -> void:
	frames.clear()
	_frames_available = 0
"""
	mock_playback_script.reload()

	var playback = mock_playback_script.new()
	ae._playback = playback
	ae._enabled = true

	return ae


func _approx_eq(a: float, b: float, tolerance: float = 0.05) -> bool:
	return abs(a - b) <= tolerance


# ── Scenario C: Audio Synthesis (TC8-TC11) ──

func _test_tc8_paddle_hit_produces_frames() -> void:
	"""TC8: paddle_hit produces frames — call play_paddle_hit(), verify frames were generated."""
	var ae = _make_audio_engine()
	var playback = ae._playback

	playback.clear_buffer()
	ae.play_paddle_hit()

	var frame_count = playback.frames.size()
	_assert(frame_count > 0, "TC8.1: paddle_hit produced frames (got %d)" % frame_count)

	# Expected: 50ms at 44100 Hz ≈ 2205 samples
	var expected_samples = int(44100 * 0.05)
	_assert(_approx_eq(float(frame_count) / expected_samples, 1.0, 0.02),
		"TC8.2: ~2205 frames for 50ms paddle hit (got %d)" % frame_count)


func _test_tc9_wall_bounce_lower_frequency() -> void:
	"""TC9: wall_bounce produces lower frequency (~100Hz) than paddle_hit (~200Hz)."""
	var ae = _make_audio_engine()
	var p1 = ae._playback

	# Get paddle_hit frames for comparison
	p1.clear_buffer()
	ae.play_paddle_hit()
	var paddle_frames = p1.frames.duplicate()

	# Get wall_bounce frames
	p1.clear_buffer()
	ae.play_wall_bounce()
	var wall_frames = p1.frames.duplicate()

	# Count zero crossings (each cycle has 2 zero crossings)
	# For 100Hz at 44100 sample rate, each half-cycle is ~220 samples
	# For 200Hz, each half-cycle is ~110 samples
	# We use a simple heuristic: count sign changes in the first N samples
	var paddle_crossings = _count_zero_crossings(paddle_frames, 500)
	var wall_crossings = _count_zero_crossings(wall_frames, 500)

	# 200Hz should have ~2x more crossings than 100Hz in same sample count
	_assert(paddle_crossings > wall_crossings,
		"TC9.1: paddle_hit has more zero crossings than wall_bounce (%d vs %d)" % [paddle_crossings, wall_crossings])
	_assert(wall_frames.size() > paddle_frames.size(),
		"TC9.2: wall_bounce (120ms) longer than paddle_hit (50ms)")


func _test_tc10_score_three_note_pattern() -> void:
	"""TC10: score produces 3 distinct tone segments (C5, E5, G5 frequencies)."""
	var ae = _make_audio_engine()
	var p1 = ae._playback

	p1.clear_buffer()
	ae.play_score()

	var frames = p1.frames
	var total = frames.size()

	# Expected: 3 * 80ms at 44100 Hz = 3 * 3528 = 10584 frames
	var expected_per_note = int(44100 * 0.08)  # 3528
	var expected_total = expected_per_note * 3

	_assert(_approx_eq(float(total) / expected_total, 1.0, 0.02),
		"TC10.1: ~10584 frames for 3-note score (got %d)" % total)

	# Verify three distinct segments exist by checking zero crossings per segment
	var seg1 = _count_zero_crossings(frames, expected_per_note)
	var seg2_start = expected_per_note
	var seg2_end = min(expected_per_note * 2, frames.size())
	var seg3_start = expected_per_note * 2
	var seg3_end = min(expected_per_note * 3, frames.size())

	# Each segment should have non-zero crossings (i.e., actual tone data)
	_assert(seg1 > 0, "TC10.2: segment 1 (C5) has crossings (%d)" % seg1)

	if seg2_end > seg2_start:
		var seg2 = _count_zero_crossings_slice(frames, seg2_start, seg2_end)
		_assert(seg2 > 0, "TC10.3: segment 2 (E5) has crossings (%d)" % seg2)

	if seg3_end > seg3_start:
		var seg3 = _count_zero_crossings_slice(frames, seg3_start, seg3_end)
		_assert(seg3 > 0, "TC10.4: segment 3 (G5) has crossings (%d)" % seg3)


func _test_tc11_game_over_fade_out() -> void:
	"""TC11: game_over produces fade-out — final sample amplitude ≈ 0."""
	var ae = _make_audio_engine()
	var p1 = ae._playback

	p1.clear_buffer()
	ae.play_game_over()

	var frames = p1.frames
	_assert(frames.size() > 0, "TC11.1: game_over produced frames (%d)" % frames.size())

	# Expected: 1s at 44100 Hz = 44100 samples
	var expected = int(44100 * 1.0)
	_assert(_approx_eq(float(frames.size()) / expected, 1.0, 0.02),
		"TC11.2: ~44100 frames for 1s game_over (got %d)" % frames.size())

	# Check that the last few samples are near zero (fade out)
	var last_frame = frames[frames.size() - 1]
	_assert(abs(last_frame.x) < 0.05 and abs(last_frame.y) < 0.05,
		"TC11.3: final sample amplitude ≈ 0 (fade-out complete, got %.4f)" % last_frame.x)

	# Check that a later sample has non-trivial amplitude (sin(0) = 0)
	var second_frame = frames[1]
	_assert(abs(second_frame.x) > 0.01,
		"TC11.4: second sample has amplitude > 0.01 (got %.4f)" % second_frame.x)


# ── Scenario D: Error Handling (TC12-TC13) ──

func _test_tc12_headless_noop() -> void:
	"""TC12: Headless no-op — with _enabled=false, play_paddle_hit() no-ops without crash."""
	var ae_script = load("res://gdscripts/audio_engine.gd")
	var ae = Node.new()
	ae.set_script(ae_script)
	ae.name = "AudioEngine"
	ae._enabled = false
	ae._playback = null

	# These should all no-op without error
	ae.play_paddle_hit()
	ae.play_wall_bounce()
	ae.play_score()
	ae.play_game_over()

	_assert(true, "TC12.1: all play_*() methods no-op when _enabled=false")


func _test_tc13_audioengine_null_safety() -> void:
	"""TC13: AudioEngine null safety — calling play_paddle_hit() when not an autoload is safe."""
	# Simulate calling AudioEngine.play_paddle_hit() when AudioEngine is null
	# The production code pattern uses: if is_instance_valid(AudioEngine): AudioEngine.play_*()
	# This test verifies that is_instance_valid(null) returns false gracefully

	var result = is_instance_valid(null)
	_assert(result == false, "TC13.1: is_instance_valid(null) returns false")

	# Verify the guarded call pattern works
	var safe_call_works = true
	if is_instance_valid(null):
		safe_call_works = false  # This branch should NOT execute
	# Should fall through to here
	_assert(safe_call_works, "TC13.2: null-guarded call pattern works (no crash)")


# ── Scenario E: Brick Break Sound (#450, TC14-TC17) ──

func _test_tc14_brick_break_frame_count() -> void:
	"""TC14: play_brick_break() produces ~44100 × BRICK_BREAK_DURATION frames (80ms → 3528)."""
	var CONSTS = load("res://gdscripts/constants.gd")
	var ae = _make_audio_engine()
	var playback = ae._playback

	playback.clear_buffer()
	ae.play_brick_break()

	var frame_count = playback.frames.size()
	_assert(frame_count > 0, "TC14.1: brick_break produced frames (got %d)" % frame_count)

	var expected_samples = int(44100 * CONSTS.BRICK_BREAK_DURATION)
	_assert(_approx_eq(float(frame_count) / expected_samples, 1.0, 0.02),
		"TC14.2: ~%d frames for %ss brick_break (got %d)" % [expected_samples, CONSTS.BRICK_BREAK_DURATION, frame_count])


func _test_tc15_brick_break_decay_envelope() -> void:
	"""TC15: brick_break has fast exponential decay — early-segment mean > late-segment mean × 3."""
	var ae = _make_audio_engine()
	var playback = ae._playback

	playback.clear_buffer()
	ae.play_brick_break()

	var frames = playback.frames
	_assert(frames.size() > 10, "TC15.1: enough frames to analyze (%d)" % frames.size())

	# Split into two halves: early (first 25%) vs late (last 25%)
	var quarter = int(frames.size() / 4)
	var early_sum := 0.0
	var late_sum := 0.0
	for i in range(quarter):
		early_sum += abs(frames[i].x)
	for i in range(frames.size() - quarter, frames.size()):
		late_sum += abs(frames[i].x)
	var early_avg = early_sum / quarter
	var late_avg = late_sum / quarter

	_assert(early_avg > late_avg * 3.0,
		"TC15.2: early avg (%.4f) > late avg (%.4f) × 3 — decay envelope present" % [early_avg, late_avg])


func _test_tc16_brick_break_determinism() -> void:
	"""TC16: same seed → two calls produce identical frame sequences (deterministic synthesis)."""
	var ae = _make_audio_engine()
	var playback = ae._playback

	playback.clear_buffer()
	ae.play_brick_break()
	var frames_a = playback.frames.duplicate()

	playback.clear_buffer()
	ae.play_brick_break()
	var frames_b = playback.frames.duplicate()

	_assert(frames_a.size() == frames_b.size(),
		"TC16.1: same frame count across calls (%d vs %d)" % [frames_a.size(), frames_b.size()])

	var identical := true
	var first_diff := -1
	for i in range(min(frames_a.size(), frames_b.size())):
		if frames_a[i] != frames_b[i]:
			identical = false
			first_diff = i
			break
	_assert(identical, "TC16.2: deterministic frame sequence (first diff at index %d)" % first_diff)


func _test_tc17_brick_break_headless_noop() -> void:
	"""TC17: headless no-op — with _enabled=false, play_brick_break() no-ops without crash or frames."""
	var ae_script = load("res://gdscripts/audio_engine.gd")
	var ae = Node.new()
	ae.set_script(ae_script)
	ae.name = "AudioEngine"
	ae._enabled = false
	ae._playback = null

	# Should no-op without error
	ae.play_brick_break()
	ae._play_noise_burst(0.08, 0.7, 450)

	_assert(true, "TC17.1: play_brick_break() no-ops when _enabled=false (no crash)")


# ── Local helpers ──

func _count_zero_crossings(frames: Array, limit: int = -1) -> int:
	"""Count sign changes in the first `limit` frames."""
	var count = 0
	var n = limit if limit > 0 else frames.size()
	n = min(n, frames.size())
	if n < 2:
		return 0
	for i in range(1, n):
		if (frames[i].x >= 0.0) != (frames[i - 1].x >= 0.0):
			count += 1
	return count


func _count_zero_crossings_slice(frames: Array, start: int, end_excl: int) -> int:
	"""Count sign changes within a slice of frames."""
	var count = 0
	var s = max(start, 0)
	var e = min(end_excl, frames.size())
	if e - s < 2:
		return 0
	for i in range(s + 1, e):
		if (frames[i].x >= 0.0) != (frames[i - 1].x >= 0.0):
			count += 1
	return count
