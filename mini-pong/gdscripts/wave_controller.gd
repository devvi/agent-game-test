extends Node
## WaveController — 场景侧波次编排（#386）。
## 消费 BreakoutGrid.wall_cleared（#384 契约，容错）→ 驱动 GameManager 波次状态机
## → 难度递增 → generate_wave(更厚) → is_run_over() 停止。与 ScoringManager 同构（#385）。
##
## 容错（#384 实现未落地期）: get_node_or_null 引用 + has_signal/has_method 双守卫；
## grid 未接线时波次状态机照常推进（wave_index 递增可测），生成环节跳过并 push_warning。
## 雨幕波次因子: DESIGN #389 §3.5 指定 #386 为 set_wave_factor 唯一写入口（PRD §8 决策 6）；
## RainCurtain 为场景节点，未接线时静默跳过（契约默认值安全）。
##
## Design: docs/DESIGN/386-wave-cycle.md §3.1
## Parent Issue: #386

const CONSTS = preload("res://gdscripts/constants.gd")

# 注: 不标注类型（Variant）——自定义成员（generate_wave / ai_*）在 Node 类型上会被
# GDScript 静态分析拒绝（"Cannot find member"）；与 DESIGN §3.1 意图一致，访问改动态解析。
@onready var breakout_grid = get_node_or_null("../BreakoutGrid")   # #384 容错：#393 接线前为 null
@onready var ai_paddle = get_node_or_null("../AIPaddle")
@onready var rain_curtain = _find_rain_curtain()                   # #389 契约（Main.tscn: AtmosphereLayer/RainCurtain）

var _settling: bool = false   # 结算中守卫：忽略重复 wall_cleared / 并发信号（边界 4）


func _ready() -> void:
	if breakout_grid != null and breakout_grid.has_signal("wall_cleared"):
		breakout_grid.wall_cleared.connect(_on_wall_cleared)
	else:
		push_warning("WaveController: BreakoutGrid 未接线 (#384/#393)，波次循环暂不激活")


func _on_wall_cleared() -> void:
	if _settling or GameManager.is_run_over():
		return
	_settling = true
	GameManager.settle_wave()                 # SETTLED + wave_settled（#388/#390 挂点）
	if GameManager.is_run_over():
		GameManager.end_wave_cycle()          # AC5：21 分后停止，不生成新墙
		_settling = false
		return
	await get_tree().create_timer(CONSTS.WAVE_SETTLE_DELAY).timeout  # 结算延时（#388 接线后由其接管推进时机）
	_advance_wave()
	_settling = false


func _advance_wave() -> void:
	if GameManager.wave_index >= CONSTS.WAVE_MAX_INDEX:
		push_warning("WaveController: 达到 WAVE_MAX_INDEX(%d)，停止波次推进" % CONSTS.WAVE_MAX_INDEX)
		return
	GameManager.begin_wave()                  # wave_index +1 → RUNNING → wave_started（AC3）
	_apply_difficulty(GameManager.wave_index)
	if rain_curtain != null and rain_curtain.has_method("set_wave_factor"):
		rain_curtain.set_wave_factor(GameManager.wave_index)   # #389 §3.5：雨量波次因子
	if breakout_grid != null and breakout_grid.has_method("generate_wave"):
		breakout_grid.generate_wave(_wave_thickness(GameManager.wave_index), 0, -1)
		# layout=0 = BrickLayout.GAPS（#414 契约；不 preload 未落地脚本，字面量 + 注释对齐）
		# seed=-1 = 随机；generate_wave 内部先 clear_wall() → AC4 单实例清理
	else:
		push_warning("WaveController: generate_wave 不可用（#384 未落地），跳过墙生成")


func _wave_thickness(index: int) -> int:
	return CONSTS.WAVE_START_THICKNESS + (index - 1) * CONSTS.WAVE_THICKNESS_STEP


func _apply_difficulty(index: int) -> void:
	# AC2：AI 反应延迟/位置误差每波收紧（clamp 下限）；厚度杠杆由 _wave_thickness 保证
	if ai_paddle == null:
		push_warning("WaveController: AIPaddle 未接线，跳过 AI 缩放（厚度杠杆仍满足 AC2）")
		return
	ai_paddle.ai_reaction_delay_min = maxf(CONSTS.AI_REACTION_DELAY_MIN_FLOOR,
		float(ai_paddle.ai_reaction_delay_min) * CONSTS.AI_DIFFICULTY_FACTOR)
	ai_paddle.ai_reaction_delay_max = maxf(CONSTS.AI_REACTION_DELAY_MAX_FLOOR,
		float(ai_paddle.ai_reaction_delay_max) * CONSTS.AI_DIFFICULTY_FACTOR)
	ai_paddle.ai_position_error = maxf(CONSTS.AI_POSITION_ERROR_FLOOR,
		float(ai_paddle.ai_position_error) * CONSTS.AI_DIFFICULTY_FACTOR)


func _find_rain_curtain():
	var n = get_node_or_null("../AtmosphereLayer/RainCurtain")   # Main.tscn 实际路径（#393 接线后）
	if n == null:
		n = get_node_or_null("../RainCurtain")                   # 兜底：同级挂载
	return n
