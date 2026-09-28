class_name GameClock
extends RefCounted
## Game clock in NFL seconds (15:00 quarters are displayed), running `speed` times faster
## than real time during live plays so a quarter lasts `real_quarter_seconds` of real play
## (Settings.quarter_minutes). Between plays a runoff is applied unless the clock stopped.
## Pure logic: the match controller feeds it live time and play outcomes.

const QUARTER := 900.0
const OT_PERIOD := 600.0
const TWO_MINUTE := 120.0

var quarter := 1              ## 1..4, 5+ = overtime
var seconds_left := QUARTER
var speed := 6.0              ## game seconds per real second while the ball is live
var stopped := true           ## true: no runoff before the next snap
var warned: Dictionary = {}   ## quarter -> true once the two-minute warning was given


func _init(real_quarter_seconds := 150.0) -> void:
	speed = QUARTER / maxf(real_quarter_seconds, 30.0)


func is_overtime() -> bool:
	return quarter > 4


func period_length() -> float:
	return OT_PERIOD if is_overtime() else QUARTER


## Live ball: game time passes at `speed`.
func tick_live(real_dt: float) -> void:
	seconds_left = maxf(0.0, seconds_left - real_dt * speed)


## Between plays. Returns true if the two-minute warning fires now.
## `runoff` game seconds come off unless the clock is stopped.
func apply_runoff(runoff: float) -> bool:
	if stopped:
		return false
	var before := seconds_left
	seconds_left = maxf(0.0, seconds_left - runoff)
	return _check_warning(before)


## Called after a play: stops the clock (incompletion, out of bounds, score, turnover…)
## or lets it run. Also fires the two-minute warning if the play crossed 2:00.
func end_play(stop_clock: bool, seconds_before_play: float) -> bool:
	stopped = stop_clock
	var warn := _check_warning(seconds_before_play)
	if warn:
		stopped = true
	return warn


func _check_warning(before: float) -> bool:
	if quarter != 2 and quarter != 4:
		return false
	if warned.has(quarter) or before <= TWO_MINUTE or seconds_left > TWO_MINUTE:
		return false
	warned[quarter] = true
	seconds_left = maxf(seconds_left, 0.0)
	stopped = true
	return true


func timeout() -> void:
	stopped = true


func expired() -> bool:
	return seconds_left <= 0.0


## Starts the next period. Returns "q2", "half", "q4", "regulation_over" or "ot".
func next_period() -> String:
	var ended := quarter
	quarter += 1
	seconds_left = period_length()
	stopped = true
	match ended:
		1:
			return "q2"
		2:
			return "half"
		3:
			return "q4"
		4:
			return "regulation_over"
	return "ot"


## Game seconds left in the current half (for two-minute situations).
func half_seconds_left() -> float:
	if quarter == 1 or quarter == 3:
		return seconds_left + QUARTER
	return seconds_left


## Game seconds left in regulation (0 in overtime).
func game_seconds_left() -> float:
	if is_overtime():
		return seconds_left
	return seconds_left + (4 - quarter) * QUARTER


static func format_time(s: float) -> String:
	var t := int(ceil(s))
	return "%d:%02d" % [t / 60, t % 60]


func label() -> String:
	var q := "OT" if is_overtime() else "Q%d" % quarter
	return "%s %s" % [q, format_time(seconds_left)]
