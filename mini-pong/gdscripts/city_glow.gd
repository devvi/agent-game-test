extends TextureRect
## L0 底部城市光晕 — 雨夜竞技场「城市灯火」意象 (#527)。
## 垂直渐变光带 + 正弦呼吸（复用 bg_pulse.gd::compute_alpha 纯函数，DRY）；
## WorldEnvironment glow(0.6)/bloom(0.8) 将光带放大为「光晕」。氛围层 FSM-independent，
## 随 AtmosphereLayer(game_world 组) 在 MENU 态结构性隐藏 (#508)。
## Design: docs/DESIGN/527-visual-enrichment.md §3.1

const CONSTS = preload("res://gdscripts/constants.gd")
const BgPulse = preload("res://gdscripts/bg_pulse.gd")

var _t: float = 0.0

func _ready() -> void:
	# 程序化垂直渐变（底部光晕色 → 顶部透明）；引擎内建，无外部资产
	var grad = Gradient.new()
	grad.set_color(0, CONSTS.CITY_GLOW_TINT)                 # 底部：光晕色（alpha 由呼吸统一调制）
	grad.set_color(1, Color(CONSTS.CITY_GLOW_TINT.r, CONSTS.CITY_GLOW_TINT.g, CONSTS.CITY_GLOW_TINT.b, 0.0))
	var tex = GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 1)                            # 垂直：下→上
	tex.fill_to = Vector2(0, 0)
	tex.height = int(CONSTS.CITY_GLOW_HEIGHT)
	texture = tex
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	# 首帧即呼吸基线 alpha（防 startup 全透明/全亮闪现）
	modulate.a = BgPulse.compute_alpha(0.0, CONSTS.CITY_GLOW_PERIOD,
		CONSTS.CITY_GLOW_BASE_ALPHA, CONSTS.CITY_GLOW_AMPLITUDE)

func _process(delta: float) -> void:
	_t += delta
	modulate.a = BgPulse.compute_alpha(_t, CONSTS.CITY_GLOW_PERIOD,
		CONSTS.CITY_GLOW_BASE_ALPHA, CONSTS.CITY_GLOW_AMPLITUDE)
