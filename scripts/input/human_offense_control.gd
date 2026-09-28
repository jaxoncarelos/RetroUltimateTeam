class_name HumanOffenseControl
extends Node
## Offense controls:
##   QB with the ball: drag BACK to aim (slingshot), release to throw; drag FORWARD to scramble.
##   Ball carrier: auto-runs forward; hold + drag up/down to steer, drag back to slow,
##   flick up/down to juke, double-tap to dive.

signal aim_changed(active: bool, target: Vector2)

enum Mode { NONE, AIM, STEER }

var runner: PlayRunner
var tuning: GameplayTuning
var mode := Mode.NONE
var aim_target := Vector2.ZERO
var steer_lateral := 0.0
var steer_throttle := 1.0


func bind(p_runner: PlayRunner, input: TouchInput, p_tuning: GameplayTuning) -> void:
	runner = p_runner
	tuning = p_tuning
	runner.human_input = self
	input.flick_speed = tuning.flick_speed
	input.drag_started.connect(_on_drag_started)
	input.dragged.connect(_on_dragged)
	input.released.connect(_on_released)
	input.flicked.connect(_on_flicked)
	input.double_tapped.connect(_on_double_tapped)
	runner.carrier_changed.connect(func(_a: PlayerAgent) -> void: _cancel_aim())


func _live() -> bool:
	return runner != null and runner.phase == PlayRunner.Phase.LIVE


func _human_carrier() -> PlayerAgent:
	var c := runner.carrier
	return c if c != null and c.human else null


func _on_drag_started(start: Vector2, pos: Vector2) -> void:
	if not _live():
		return
	var d := pos - start
	if runner.qb_is_passer():
		if d.x > 0.0 and absf(d.x) > absf(d.y):
			runner.start_scramble()
			mode = Mode.STEER
		else:
			mode = Mode.AIM
	elif _human_carrier() != null:
		mode = Mode.STEER
	_on_dragged(start, pos)


func _on_dragged(start: Vector2, pos: Vector2) -> void:
	if not _live():
		return
	match mode:
		Mode.AIM:
			if not runner.qb_is_passer():
				_cancel_aim()
				return
			aim_target = runner.aim_point(start, pos)
			aim_changed.emit(true, aim_target)
		Mode.STEER:
			var dy := pos.y - start.y
			var mag := maxf(absf(dy) - tuning.steer_deadzone, 0.0) / (tuning.steer_full - tuning.steer_deadzone)
			steer_lateral = signf(dy) * clampf(mag, 0.0, 1.0)
			steer_throttle = 0.55 if pos.x - start.x < -20.0 else 1.0


func _on_released(start: Vector2, pos: Vector2, was_drag: bool) -> void:
	if mode == Mode.AIM and was_drag and _live() and runner.qb_is_passer() \
			and pos.distance_to(start) >= tuning.aim_min_drag:
		runner.throw_ball(runner.aim_point(start, pos))
	_cancel_aim()
	mode = Mode.NONE
	steer_lateral = 0.0
	steer_throttle = 1.0


func _cancel_aim() -> void:
	if mode == Mode.AIM:
		mode = Mode.NONE
	aim_changed.emit(false, Vector2.ZERO)


func _on_flicked(dir: Vector2) -> void:
	var c := _human_carrier()
	if _live() and c != null:
		c.start_juke(tuning, dir.y)


func _on_double_tapped(_pos: Vector2) -> void:
	var c := _human_carrier()
	if _live() and c != null and c.can_act():
		c.start_dive(tuning, Vector2(1.0, steer_lateral * 0.5))


## Called by PlayRunner every physics frame before the brains.
func apply(_dt: float) -> void:
	var c := _human_carrier()
	if c == null:
		return
	var lateral := steer_lateral if mode == Mode.STEER else 0.0
	c.desired_dir = Vector2(1.0, lateral * 1.2).normalized()
	c.throttle = steer_throttle if mode == Mode.STEER else 1.0
