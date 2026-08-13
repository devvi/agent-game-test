extends ColorRect
## Background neon breath — L0 atmosphere layer (#449).
## 背景光晕缓慢正弦呼吸：color.a = compute_alpha(t)。色调 BG_PULSE_TINT（霓虹蓝同系），
## WorldEnvironment 既有 glow(0.6)/bloom(0.8) 放大为「光晕」。氛围层 FSM-independent。
## Design: docs/DESIGN/449-bg-neon-breath.md

const CONSTS = preload("res://gdscripts/constants.gd")

var _t: float = 0.0

## 纯函数：alpha = clamp(base + amplitude·sin(TAU·t/period), 0, 1)。
## period <= 0 时返回 base（防除零 NaN，沿用 #287/#389 NaN 防护先例）。
static func compute_alpha(t: float, period: float, base: float, amplitude: float) -> float:
	if period <= 0.0:
		return base
	return clamp(base + amplitude * sin(TAU * t / period), 0.0, 1.0)

func _process(delta: float) -> void:
	_t += delta
	color.a = compute_alpha(_t, CONSTS.BG_PULSE_PERIOD,
		CONSTS.BG_PULSE_BASE_ALPHA, CONSTS.BG_PULSE_AMPLITUDE)
