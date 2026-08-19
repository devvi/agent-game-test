extends RefCounted
## StateMachineBase — 通用状态机基类（#572）。
## 状态对象（任意 Object）实现 enter()/exit()/update(delta) 三接口；
## 基类提供 transition_to()（同态守卫 + 防重入）与 update() 转发。
## 派生: #575 战斗实体状态机在其上定义具体状态。

class_name StateMachineBase

var current_state: Object = null      # 当前状态对象（可为 null = 空状态）
var _transition_locked: bool = false  # 防重入锁（transition 进行中禁止再 transition）

## 三接口契约（状态对象实现，本基类不实现具体逻辑）:
##   func enter() -> void          # 进入状态：初始化
##   func exit() -> void           # 退出状态：清理
##   func update(delta: float) -> void  # 每帧逻辑（由基类 update() 转发）

func transition_to(new_state: Object) -> void:
	## 转移: 同态守卫（同对象不重复触发）+ 防重入守卫（转移中禁止嵌套转移）
	if _transition_locked:
		push_warning("StateMachineBase: transition blocked — re-entrant call")
		return
	if new_state == current_state:
		return  # 同态守卫: 目标 == 当前，静默忽略（无回调）
	_transition_locked = true
	if current_state != null and current_state.has_method("exit"):
		current_state.exit()
	current_state = new_state
	if current_state != null and current_state.has_method("enter"):
		current_state.enter()
	_transition_locked = false

func update(delta: float) -> void:
	## 转发: 空状态安全（current_state == null 时 no-op）
	if current_state != null and current_state.has_method("update"):
		current_state.update(delta)
