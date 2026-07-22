extends Node

# ClockManager — 90-day deadline tracker
# Each dialogue choice consumes 1–3 days
# Emits deadline_approaching when ≤14 days remain, deadline_reached at 90

signal day_passed(day: int, remaining: int)
signal deadline_approaching(days_left: int)
signal deadline_reached()

const MAX_DAYS: int = 90

var current_day: int = 0

func consume_days(amount: int = 1) -> void:
	current_day += amount
	var remaining = MAX_DAYS - current_day
	day_passed.emit(current_day, remaining)

	if current_day >= MAX_DAYS:
		deadline_reached.emit()
	elif remaining <= 14:
		deadline_approaching.emit(remaining)

func get_remaining() -> int:
	return MAX_DAYS - current_day

func reset() -> void:
	current_day = 0
	day_passed.emit(current_day, MAX_DAYS)
