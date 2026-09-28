class_name HumanDefenseControl
extends Node
## Defense controls ("fast and fun", PLAN.md §4):
##   drag anywhere        - virtual stick anchored where the finger went down; moves your
##                          defender (he plays his assignment on his own when you let go)
##   tap near the carrier - dive tackle (if your man is in range)
##   tap near the ball's landing marker - leap to swat / pick it (timing matters)
##   tap on a defender    - take control of him
##   interception return  - auto-runs toward the end zone; drag up/down to steer,
##                          flick to juke, double-tap to dive
## The owner calls update() every physics frame (auto-switching) — PlayRunner calls apply().

signal switched(agent: PlayerAgent)
## A pre-snap tap on the field (the owner may snap the CPU offense).
signal ready_tapped

var runner: PlayRunner
var tuning: GameplayTuning
var switcher: DefenseSwitcher
var _dragging := false
var _anchor := Vector2.ZERO
var _stick := Vector2.ZERO      ## field-space direction * throttle (0..1)
var _steer := 0.0               ## return steering, -1..1


func bind(p_runner: PlayRunner, input: TouchInput, p_tuning: GameplayTuning) -> void:
	runner = p_runner
	tuning = p_tuning
	switcher = DefenseSwitcher.new(runner)
	input.drag_started.connect(_on_drag_started)
	input.dragged.connect(_on_dragged)
	input.released.connect(_on_released)
	input.tapped.connect(_on_tapped)
	input.flicked.connect(_on_flicked)
	input.double_tapped.connect(_on_double_tapped)
	runner.ball_thrown.connect(func(_t: Vector2) -> void: switcher.update(0.0, true))
	runner.carrier_changed.connect(func(_a: PlayerAgent) -> void: switcher.update(0.0, true))


func _active() -> bool:
	return runner != null and runner.human_team == PlayerAgent.Team.DEFENSE


func _live() -> bool:
	return _active() and runner.phase == PlayRunner.Phase.LIVE


func _me() -> PlayerAgent:
	return runner.controlled


func _returning() -> bool:
	var me := _me()
	return me != null and me == runner.carrier


## Viewport point -> field yards, through the current camera.
func to_field(view_pos: Vector2) -> Vector2:
	return FieldProjection.to_field(get_viewport().get_canvas_transform().affine_inverse() * view_pos)


## Each physics frame from the owner: auto-switch.
func update(dt: float) -> void:
	if _live() and not _dragging:
		var before := _me()
		switcher.update(dt)
		if _me() != before:
			switched.emit(_me())


func _on_drag_started(start: Vector2, pos: Vector2) -> void:
	if not _live():
		return
	_dragging = true
	_anchor = start
	_on_dragged(start, pos)


func _on_dragged(_start: Vector2, pos: Vector2) -> void:
	if not _live() or not _dragging:
		return
	var d := pos - _anchor
	if _returning():
		var mag := maxf(absf(d.y) - tuning.steer_deadzone, 0.0) / (tuning.steer_full - tuning.steer_deadzone)
		_steer = signf(d.y) * clampf(mag, 0.0, 1.0)
		return
	var len := d.length()
	if len < tuning.stick_deadzone:
		_stick = Vector2.ZERO
		return
	# Screen -> field direction (the field's y axis is compressed on screen).
	var dir := Vector2(d.x / FieldProjection.PX_X, d.y / FieldProjection.PX_Y).normalized()
	_stick = dir * clampf((len - tuning.stick_deadzone) / (tuning.stick_full - tuning.stick_deadzone), 0.3, 1.0)


func _on_released(_start: Vector2, _pos: Vector2, _was_drag: bool) -> void:
	_dragging = false
	_stick = Vector2.ZERO
	_steer = 0.0
	var me := _me()
	if me != null and me != runner.carrier:
		me.human = false   # hand the defender back to his brain


func _on_tapped(view_pos: Vector2) -> void:
	if not _active():
		return
	if runner.phase == PlayRunner.Phase.PRE_SNAP:
		ready_tapped.emit()
		return
	if not _live():
		return
	var p := to_field(view_pos)
	var me := _me()
	if me == null or _returning():
		return
	var t := tuning
	# 1) Ball in the air: leap if the tap is near the landing marker and we can get there.
	#    Too far to leap yet: sprint to the spot (tap again to jump).
	if runner.ball.state == Ball.State.AIR and p.distance_to(runner.ball.to) <= t.tap_ball_radius:
		if me.field_pos.distance_to(runner.ball.to) <= t.jump_start_range:
			runner.defender_jump(me)
		else:
			me.brain = BallHawkBrain.new(me, runner, runner.ball.to, 0.0, null)
		return
	# 2) Dive at the ball carrier.
	var c := runner.carrier
	if c != null and c.team == PlayerAgent.Team.OFFENSE and p.distance_to(c.field_pos) <= t.tap_carrier_radius:
		if me.field_pos.distance_to(c.field_pos) <= t.human_dive_range and me.can_act():
			me.start_dive(t, c.field_pos + c.velocity * 0.12 - me.field_pos, t.dive_recover)
			return
	# 3) Switch to the tapped defender.
	var best: PlayerAgent = null
	var best_d := t.tap_switch_radius
	for d in runner.defense:
		var dist := d.field_pos.distance_to(p)
		if dist < best_d:
			best_d = dist
			best = d
	if best != null:
		switcher.manual(best)   # tapping your own man locks him in, too
		if best != me:
			switched.emit(best)


func _on_flicked(dir: Vector2) -> void:
	if _live() and _returning():
		_me().start_juke(tuning, dir.y)


func _on_double_tapped(_pos: Vector2) -> void:
	if _live() and _returning() and _me().can_act():
		_me().start_dive(tuning, Vector2(-1.0, _steer * 0.5))


## Called by PlayRunner every physics frame before the brains.
func apply(_dt: float) -> void:
	if not _live():
		return
	var me := _me()
	if me == null:
		return
	if _returning():
		me.human = true
		me.desired_dir = Vector2(-1.0, _steer * 1.2).normalized()
		me.throttle = 1.0
		return
	if _dragging and _stick != Vector2.ZERO:
		me.human = true
		me.desired_dir = _stick.normalized()
		me.throttle = _stick.length()
	elif _dragging:
		me.human = true
		me.stop()
