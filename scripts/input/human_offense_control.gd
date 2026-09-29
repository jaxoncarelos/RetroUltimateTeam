class_name HumanOffenseControl
extends Node
## Offense controls (Retro Bowl style, one continuous gesture):
##   Pre-snap: press on/near the QB -> snaps at once; keep the finger down and the same drag
##     aims (drag BACK, slingshot) or scrambles (drag FORWARD). A tap anywhere also snaps.
##     Dragging from anywhere else snaps too and starts aiming.
##   QB with the ball: drag BACK to aim, release to throw; drag FORWARD to scramble.
##     Aim = slingshot: the pull's direction is the throw direction and its length the
##     distance (the reticle is where the ball lands). Loft is automatic and previewed:
##     short = BULLET, 13+ yards rising to a full LOB by ~32 yards, and a TOUCH/LOB arc over
##     any defender standing in the throwing lane. A light aim assist pulls the reticle onto a
##     receiver's in-stride spot when it is close (GameplayTuning.aim_assist_*).
##   Ball carrier: auto-runs the play's lane, then straight; drag up/down to steer (relative
##   to where steering began), drag back to slow, flick up/down to juke, double-tap to dive.

signal aim_changed(active: bool, target: Vector2)
## Emitted when a pre-snap gesture should snap the ball (the owner decides and calls snap).
signal snap_requested
## The pass type changed by a tap (name: AUTO / BULLET / TOUCH / LOB).
signal pass_kind_changed(kind_name: String)

enum Mode { NONE, AIM, STEER }

## Viewport pixels around the QB that count as "pressing the QB".
const QB_GRAB_RADIUS := 40.0

var runner: PlayRunner
var tuning: GameplayTuning
var mode := Mode.NONE
var aim_target := Vector2.ZERO
var steer_lateral := 0.0
var steer_throttle := 1.0
var _steer_anchor := Vector2.ZERO
var _aim_anchor := Vector2.ZERO
## True while the finger that snapped the ball is still down.
var _snap_gesture := false


func bind(p_runner: PlayRunner, input: TouchInput, p_tuning: GameplayTuning) -> void:
	runner = p_runner
	tuning = p_tuning
	runner.human_input = self
	input.flick_speed = tuning.flick_speed
	input.pressed.connect(_on_pressed)
	input.drag_started.connect(_on_drag_started)
	input.dragged.connect(_on_dragged)
	input.released.connect(_on_released)
	input.flicked.connect(_on_flicked)
	input.double_tapped.connect(_on_double_tapped)
	input.tapped.connect(_on_tapped)
	input.extra_tapped.connect(_on_extra_tapped)
	runner.carrier_changed.connect(func(_a: PlayerAgent) -> void: _cancel_aim())


## Only while the human has the ball team; on defense these gestures belong to HumanDefenseControl.
func _live() -> bool:
	return runner != null and runner.phase == PlayRunner.Phase.LIVE \
			and runner.human_team == PlayerAgent.Team.OFFENSE


func _pre_snap() -> bool:
	return runner != null and runner.phase == PlayRunner.Phase.PRE_SNAP \
			and runner.human_team == PlayerAgent.Team.OFFENSE


func _human_carrier() -> PlayerAgent:
	var c := runner.carrier
	return c if c != null and c.human else null


## Screen (viewport) position of a field point, through the current camera.
func _to_view(field_p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * FieldProjection.to_screen(field_p)


func is_near_qb(view_pos: Vector2) -> bool:
	return runner.qb != null and _to_view(runner.qb.field_pos).distance_to(view_pos) <= QB_GRAB_RADIUS


func _request_snap() -> void:
	_snap_gesture = true
	snap_requested.emit()


func _on_pressed(pos: Vector2) -> void:
	if _pre_snap() and is_near_qb(pos):
		_request_snap()


func _on_drag_started(start: Vector2, pos: Vector2) -> void:
	if _pre_snap():
		_request_snap()
	if not _live():
		return
	var d := pos - start
	if runner.qb_is_passer():
		if d.x > 0.0 and absf(d.x) > absf(d.y):
			runner.start_scramble()
			_begin_steer(pos)
		else:
			mode = Mode.AIM
			_aim_anchor = start
	elif _human_carrier() != null:
		_begin_steer(pos)
	_on_dragged(start, pos)


func _begin_steer(anchor: Vector2) -> void:
	mode = Mode.STEER
	_steer_anchor = anchor
	steer_lateral = 0.0
	steer_throttle = 1.0


func _on_dragged(_start: Vector2, pos: Vector2) -> void:
	if not _live():
		return
	# A run play's handoff (or a catch) arrives mid-gesture: start steering from here.
	if mode == Mode.NONE and _snap_gesture and _human_carrier() != null:
		_begin_steer(pos)
	match mode:
		Mode.AIM:
			if not runner.qb_is_passer():
				_cancel_aim()
				return
			aim_target = runner.aim_point(_aim_anchor, pos)
			runner.aim_preview = aim_target
			aim_changed.emit(true, aim_target)
		Mode.STEER:
			var dy := pos.y - _steer_anchor.y
			var mag := maxf(absf(dy) - tuning.steer_deadzone, 0.0) / (tuning.steer_full - tuning.steer_deadzone)
			steer_lateral = signf(dy) * clampf(mag, 0.0, 1.0)
			steer_throttle = 0.55 if pos.x - _steer_anchor.x < -20.0 else 1.0


func _on_released(_start: Vector2, pos: Vector2, was_drag: bool) -> void:
	if mode == Mode.AIM and was_drag and _live() and runner.qb_is_passer() \
			and pos.distance_to(_aim_anchor) >= tuning.aim_min_drag:
		runner.throw_ball(runner.aim_point(_aim_anchor, pos))
	_cancel_aim()
	mode = Mode.NONE
	_snap_gesture = false
	steer_lateral = 0.0
	steer_throttle = 1.0


func _cancel_aim() -> void:
	if mode == Mode.AIM:
		mode = Mode.NONE
	if runner != null:
		runner.aim_preview = Vector2.INF
		runner.aim_assist_target = null
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
## Until the player actually steers, the carrier follows the play's lane, then runs straight.
func apply(_dt: float) -> void:
	var c := _human_carrier()
	if c == null:
		return
	if mode == Mode.STEER and (steer_lateral != 0.0 or steer_throttle < 1.0):
		runner.carrier_lane = PackedVector2Array()   # the player took over; drop the lane
		c.desired_dir = Vector2(1.0, steer_lateral * 1.2).normalized()
		c.throttle = steer_throttle
		return
	var lane := runner.carrier_lane
	while not lane.is_empty() and (c.field_pos.distance_to(lane[0]) < 1.2 or lane[0].x < c.field_pos.x - 0.3):
		lane.remove_at(0)
	runner.carrier_lane = lane
	c.desired_dir = (lane[0] - c.field_pos).normalized() if not lane.is_empty() else Vector2.RIGHT
	c.throttle = 1.0


## Tap to switch the pass type: a second finger while you aim, or a plain tap while the QB
## holds the ball (the tap that snapped it doesn't count).
func _on_tapped(_pos: Vector2) -> void:
	if _live() and runner.qb_is_passer() and runner.play_time > 0.3:
		_cycle_kind()


func _on_extra_tapped(_pos: Vector2) -> void:
	if _live() and runner.qb_is_passer():
		_cycle_kind()


func _cycle_kind() -> void:
	runner.cycle_pass_kind()
	if mode == Mode.AIM:
		aim_changed.emit(true, aim_target)   # the preview arc re-plans with the new type
	pass_kind_changed.emit(runner.pass_kind_name())
