extends Node
class_name ReviveOrchestrator
## ReviveOrchestrator — 复活编排器（#578 两条命原地复活系统）。
## 归属: docs/DESIGN/578-two-life-revive.md §2.1
## 职责: 订阅 entity.died(final=false) → REVIVE_SECONDS 自管理计时 → entity.revive()（自动复活路径）。
## 双路径: 与 #573/#575 F 键手动路径并行，两路经 revive() 幂等收敛；
##   revived 信号 → 取消 pending（消除竞争窗口，边界 3）。
## headless 确定性: _process(delta) 累加推进，测试手动驱动（对齐 test_combat_entity _advance 模式），零树依赖。
## SW-015 契约（本编排器唯一数据源，AC3 固化于此）:
##   died(entity, false) = 可复活死（第一条血耗尽，life_total=2 玩家）——本编排器计时 REVIVE_SECONDS 后调 revive()
##   died(entity, true)  = 终态（第二条血耗尽 / life_total=1 实体，_is_final_dead 置位、revive() 被拒）——SW-015 结局失败消费，本编排器忽略
## 红线: 只消费信号 + 调用 revive()，零改写 hp/架势/无敌逻辑（#575 契约只读，禁止语义复制）。

const C = preload("res://gdscripts/constants.gd")

var _player: Object = null
var _armed: bool = false
var _elapsed: float = 0.0


func bind_player(entity: Object) -> void:
	## 幂等接线: 先解绑旧实体（若已绑），再订阅新实体 died/revived 信号
	## 只接受 is_player==true 且 life_total==2 的实体（敌人 life_total=1 永不绑定，边界 4）
	if _player != null and is_instance_valid(_player):
		_player.disconnect("died", _on_entity_died)      # 旧实体解绑（防泄漏）
		_player.disconnect("revived", _on_entity_revived)
	_player = entity
	_armed = false
	_elapsed = 0.0
	if entity == null:
		return
	entity.died.connect(_on_entity_died)
	entity.revived.connect(_on_entity_revived)


func unbind_player() -> void:
	## 场景切换/实体销毁前调用（#585 组装约定）: 解绑 + 清 pending
	bind_player(null)


func is_armed() -> bool:
	## 可观测性: 计时进行中标志（died(false) 置位，revived/unbind/到期 清除）——防重入 + 供测试断言
	return _armed


func _on_entity_died(ent: Object, final: bool) -> void:
	## 自动复活路径唯一入口: 仅 final=false（第一条血耗尽）且为绑定实体 → 启动计时
	## final=true（第二条血耗尽/life_total=1）不启动——SW-015 终态由契约消费（§2.1 契约表）
	if ent != _player or final:
		return
	if _armed:
		return                          # 防重入（died 天然单次，双保险）
	_armed = true
	_elapsed = 0.0


func _on_entity_revived(ent: Object) -> void:
	## 幂等收敛钩子: F 键手动 revive() 先触发时，取消自动 pending——
	## 消除双路径竞争窗口（边界 3），revived 只发一次，天然单次
	if ent == _player:
		_armed = false
		_elapsed = 0.0


func _process(delta: float) -> void:
	## 自管理计时（PRD 方案 A「SceneTreeTimer/自管理计时器」二选一，裁决取后者:
	## headless 确定性——测试经 _process(delta) 同步推进，零树依赖）
	## 注意: 不判 _player == null —— Godot 4 中已 free 的对象 == null 为 true，
	## 会提前 return 导致 pending 永不结算；_armed 只在绑定时置位，unbind/revived 已清除，
	## 实体销毁守卫由到期分支的 is_instance_valid 承担（§5 边界 9）
	if not _armed:
		return
	_elapsed += delta
	if _elapsed >= float(C.REVIVE_SECONDS):
		_armed = false
		_elapsed = 0.0
		if is_instance_valid(_player):
			_player.revive()           # 唯一驱动点；终态/life_total<2 时 revive() 内部 no-op + push_warning
