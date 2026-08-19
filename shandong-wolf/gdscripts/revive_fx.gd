extends Node2D
class_name ReviveFX
## ReviveFX — 复活演出层（#578 两条命原地复活系统）。
## 归属: docs/DESIGN/578-two-life-revive.md §2.2
## 职责: 订阅 entity.revived → 演出四件套——
##   ① 墨点 burst（GPUParticles2D one_shot，径向爆开）
##   ② 闪屏（瞬态 CanvasModulate Tween: 白 → 血 → 复原）
##   ③ 慢动作（Engine.time_scale 短促降速）
##   ④ 无敌闪烁（_visual_root modulate.a 循环，父节点传播到全部 Line2D 子肢体）
## _ready() 代码构建全部子节点（零 tscn / 零美术资产，对齐 stick_figure.gd 模式；headless 可 new + 入树断言）。
## 演出全参数化: 全部数值读 constants.gd「复活 FX 分区」# DRAFT，零硬编码字面量。
## 瞬态与常驻解耦: 闪屏 Tween 结束恢复自身默认 color（Color.WHITE），零残留，不覆盖 #582 常驻色温（红线）。

const C = preload("res://gdscripts/constants.gd")

var _entity: Object = null
var _visual_root: Node2D = null
var _flash_layer: CanvasModulate = null
var _ink_burst: GPUParticles2D = null
var _flash_tween: Tween = null
var _flicker_elapsed: float = 0.0
var _flicker_active: bool = false
var _slowmo_until_sec: float = 0.0
var _slowmo_set: bool = false


func _ready() -> void:
	_build_nodes()


func _build_nodes() -> void:
	## 零 tscn 代码构建: FlashLayer（瞬态闪屏）+ InkBurst（one_shot 墨点 burst）
	_flash_layer = CanvasModulate.new()
	_flash_layer.name = "FlashLayer"
	_flash_layer.color = C.FLASH_WHITE
	add_child(_flash_layer)

	_ink_burst = GPUParticles2D.new()
	_ink_burst.name = "InkBurst"
	_ink_burst.one_shot = true
	_ink_burst.emitting = false
	_ink_burst.amount = int(C.INK_BURST_COUNT)
	_ink_burst.lifetime = float(C.INK_BURST_LIFETIME)
	_ink_burst.spread = float(C.INK_BURST_SPREAD_DEG)
	_ink_burst.color = C.INK_COLOR
	_ink_burst.direction = Vector2(0, -1)  # 朝上半球——墨点从脚底/刀尖向上爆开（结构语义）
	_ink_burst.initial_velocity_min = float(C.INK_BURST_SPEED)
	_ink_burst.initial_velocity_max = float(C.INK_BURST_SPEED)
	_ink_burst.gravity = Vector2.ZERO  # 墨点向外爆开、不受重力下落（结构语义）
	_ink_burst.texture = _build_ink_texture()
	add_child(_ink_burst)


func bind_player(entity: Object) -> void:
	## 订阅 revived → trigger()（编排器/FX 各自独立订阅，零耦合）
	if _entity != null and is_instance_valid(_entity):
		_entity.disconnect("revived", _on_entity_revived)
	_entity = entity
	if entity != null:
		entity.revived.connect(_on_entity_revived)


func bind_player_visual(root: Node2D) -> void:
	## 注入无敌闪烁目标（#585 组装传 Player/StickFigure 根节点；#574 骨架根节点 modulate
	## 传播到全部 Line2D 子肢体——替代逐 Line2D 遍历，原子且零遍历成本）
	_visual_root = root


func _on_entity_revived(ent: Object) -> void:
	if ent == _entity:
		trigger()


func trigger() -> void:
	## 演出四件套（全部参数读 constants，零字面量；各节点缺失时降级不崩溃）
	if _ink_burst != null:
		if _visual_root != null and is_instance_valid(_visual_root):
			_ink_burst.global_position = _visual_root.global_position
		_ink_burst.emitting = true
	_start_flash_tween()
	_start_slowmo()
	_flicker_active = true
	_flicker_elapsed = 0.0


func _start_flash_tween() -> void:
	## 白 → 血（FLASH_SECONDS）→ 停留（FLASH_HOLD_SECONDS）→ 复原（FLASH_SECONDS）
	## 瞬态语义: Tween 结束必须恢复自身默认 color（白=恒等），不残留覆盖 #582 常驻色温（红线）
	if _flash_layer == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_layer, "color", C.FLASH_BLOOD, float(C.FLASH_SECONDS))
	_flash_tween.tween_interval(float(C.FLASH_HOLD_SECONDS))
	_flash_tween.tween_property(_flash_layer, "color", Color.WHITE, float(C.FLASH_SECONDS))


func _start_slowmo() -> void:
	## 全局 time_scale 短促降速（复用 SLOWMO_COEFF=0.2，与 #577 处决慢动作同源节奏语言）
	## clamp 下限 0.1 防冻结（#584 注释既有约束）；重叠触发防嵌套: 仅首次设置 _slowmo_set，末次恢复 1.0
	if not _slowmo_set:
		Engine.time_scale = maxf(float(C.SLOWMO_COEFF), 0.1)
		_slowmo_set = true
	_slowmo_until_sec = Time.get_ticks_msec() / 1000.0 + float(C.SLOWMO_HOLD_SECONDS)


func _process(delta: float) -> void:
	## ① 慢动作到期恢复 1.0（仅设置者恢复，防覆盖他人 time_scale，边界 8）
	## ② 无敌闪烁: modulate.a = lerp(1.0, ALPHA_MIN, |sin(2π·HZ·t)|) 循环；
	##    INVINCIBLE_SECONDS 到期复原 1.0（硬汉第二次机会可读性，禁止残留半透明，边界 12）
	if _slowmo_set and Time.get_ticks_msec() / 1000.0 >= _slowmo_until_sec:
		Engine.time_scale = 1.0
		_slowmo_set = false
	if not _flicker_active:
		return
	if _visual_root == null or not is_instance_valid(_visual_root):
		_flicker_active = false
		return
	_flicker_elapsed += delta
	if _flicker_elapsed >= float(C.INVINCIBLE_SECONDS):
		_flicker_active = false
		_visual_root.modulate.a = 1.0
		return
	var phase: float = _flicker_elapsed * float(C.INVINCIBLE_FLICKER_HZ) * TAU
	_visual_root.modulate.a = lerpf(1.0, float(C.INVINCIBLE_FLICKER_ALPHA_MIN), absf(sin(phase)))


func _build_ink_texture() -> Texture2D:
	## 程序化 8x8 圆点 texture（零美术资产；失败 → null → GPUParticles2D 退化为默认方形粒子，不阻塞 trigger）
	var img = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	if img == null:
		return null
	img.fill(Color(0, 0, 0, 0))
	img.draw_circle(Vector2(3.5, 3.5), 3.0, Color.WHITE)
	var tex = ImageTexture.create_from_image(img)
	if tex == null:
		return null
	return tex
