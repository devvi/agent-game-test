extends Node2D

## Ball trail particle controller for mini-pong neon visual system.
## Mounted on the ball scene — controls GPUParticles2D emission based on velocity.

@onready var particles: GPUParticles2D = $TrailParticles

# Speed threshold: below this speed no particles are emitted (no trail when ball is still)
const MIN_SPEED_FOR_TRAIL: float = 20.0
# Max speed for normalizing emission rate
const MAX_SPEED_FOR_TRAIL: float = 600.0


func _ready() -> void:
	if not particles:
		push_warning("ball_trail.gd: GPUParticles2D node not found, trail disabled")
		return
	particles.emitting = false


func _process(_delta: float) -> void:
	if not particles:
		return
	# Get parent (ball) velocity — duck-typed: works with Area2D + ball.gd
	var parent := get_parent()
	var parent_velocity: Vector2 = parent.get("velocity") if parent else Vector2.ZERO

	var speed: float = parent_velocity.length()

	if speed < MIN_SPEED_FOR_TRAIL:
		particles.emitting = false
	else:
		particles.emitting = true
		# Emission rate proportional to speed (normalized 0.0 ~ 1.0)
		particles.amount_ratio = clamp(speed / MAX_SPEED_FOR_TRAIL, 0.3, 1.0)
