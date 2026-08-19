extends CharacterBody2D
## PlayerController — shandong-wolf 玩家移动实体（#573）。
## 组: "player"（#6 近距探测/处决判定依赖）
## 移动: 加速度模型（冷冽干脆）——velocity.x = move_toward(velocity.x, dir*MAX_SPEED, ACCEL*delta)
## 消费: InputController.get_move_axis()（连续轴）；不消费边沿事件（消费方直接监听 InputController 信号）

const C = preload("res://gdscripts/constants.gd")


func _ready() -> void:
	add_to_group("player")


func _physics_process(delta: float) -> void:
	var dir: float = InputController.get_move_axis()
	velocity.x = move_toward(velocity.x, dir * C.MOVE_MAX_SPEED, C.MOVE_ACCELERATION * delta)
	velocity.y = 0.0
	move_and_slide()
