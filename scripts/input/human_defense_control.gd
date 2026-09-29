class_name HumanDefenseControl
extends Node
## Defense controls ("fast and fun", PLAN.md §4). You keep the defender you picked until
## YOU switch — nothing switches automatically during a play.
##   pre-snap: tap a defender  - pick him (remembered for the next plays); tap elsewhere = ready
##   SWITCH button (HUD)       - jump to the defender nearest the ball / carrier
##   drag anywhere             - virtual stick anchored where the finger went down; moves your
##                               defender (he plays his assignment on his own when you let go)
##   run into the carrier      - your man wraps up from farther and far more surely than a CPU
##                               defender (GameplayTuning "Human tackling")
##   tap near the carrier      - dive tackle (if your man is in range)
##   tap near the ball's landing marker - leap to swat / pick it (timing matters)
##   tap on a defender         - take control of him
##   interception return       - auto-runs toward the end zone; drag up/down to steer,
##                               flick to juke, double-tap to dive
## PlayRunner calls apply() every physics frame. set_stick() / try_dive() / try_jump() /
## switch_to_ball() are the same actions for bots and tests (DefenderBot).

signal switched(agent: PlayerAgent)
## A pre-snap tap on the field away from the defenders (the owner may snap the CPU offense).
signal ready_tapped

var runner: PlayRunner
var tuning: GameplayTuning
var switcher: DefenseSwitcher
var _dragging := false
var _anchor := Vector2.ZERO
var _stick := Vector2.ZERO      ## field-space direction * throttle (0..1)
var _steer := 0.0               ## return steering, -1..1
var _drawing := false           ## pre-snap: drawing the hero's path
var _path_pts := PackedVector2Array()
const MAX_PATH_YARDS := 34.0
const PATH_STEP := 1.1          ## yards between recorded points


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
	input.swiped.connect(func(_dir: Vector2) -> void: try_duel_move())   # a swipe mid-drag beats the block
	input.extra_tapped.connect(func(_pos: Vector2) -> void: try_duel_move())   # so does a second finger
	# An interception hands you the man who caught it.
	runner.carrier_changed.connect(func(a: PlayerAgent) -> void:
		if _active() and a == _me():
			switched.emit(a))


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


## Each physics frame from the owner. (No auto-switching any more; kept as the hook.)
func update(_dt: float) -> void:
	pass


## New play set up: give the human his remembered pre-snap pick (if the call has that slot).
func on_play_setup() -> void:
	_dragging = false
	_drawing = false
	_stick = Vector2.ZERO
	_steer = 0.0
	if _active():
		switcher.apply_preferred()
		_restore_path()


## The SWITCH button: pre-snap cycles LB/S; live jumps to the defender nearest the play.
func switch_to_ball() -> void:
	if not _active() or _returning():
		return
	var d := switcher.switch_to_ball()
	if d != null:
		switched.emit(d)


## Stick input in field space (direction × throttle 0..1), as a drag would set it.
## Vector2.ZERO lets go (the defender goes back to his assignment).
func set_stick(v: Vector2) -> void:
	if v == Vector2.ZERO:
		_on_released(Vector2.ZERO, Vector2.ZERO, true)
		return
	_dragging = true
	_stick = v.limit_length(1.0)


## Dive at the ball carrier if he is in range. Returns true when the dive started.
func try_dive() -> bool:
	var me := _me()
	var c := runner.carrier
	if not _live() or me == null or _returning() or c == null or c.team != PlayerAgent.Team.OFFENSE:
		return false
	if me.field_pos.distance_to(c.field_pos) > tuning.human_dive_range or not me.can_act():
		return false
	me.start_dive(tuning, c.field_pos + c.velocity * 0.12 - me.field_pos, tuning.dive_recover)
	return true


## Leap at a ball in the air (or sprint to its landing spot when too far). True = leapt.
func try_jump() -> bool:
	var me := _me()
	if not _live() or me == null or _returning() or runner.ball.state != Ball.State.AIR:
		return false
	if me.field_pos.distance_to(runner.ball.to) <= tuning.jump_start_range:
		runner.defender_jump(me)
		return true
	me.brain = BallHawkBrain.new(me, runner, runner.ball.to, 0.0, null)
	return false


func _on_drag_started(start: Vector2, pos: Vector2) -> void:
	if _active() and runner.phase == PlayRunner.Phase.PRE_SNAP:
		_begin_path(start)
		return
	if not _live():
		return
	_dragging = true
	_anchor = start
	_on_dragged(start, pos)


func _on_dragged(_start: Vector2, pos: Vector2) -> void:
	if _drawing:
		_extend_path(pos)
		return
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
	if _drawing:
		_finish_path()
		return
	_dragging = false
	_stick = Vector2.ZERO
	_steer = 0.0
	var me := _me()
	if me != null and me != runner.carrier:
		me.human = false   # hand the defender back to his brain
		me.accel_mult = 1.0


# ---------------------------------------------------------------- draw it up

## Pre-snap drag that starts on a defender (or close to your hero): that man is your hero and
## the drag draws his path. The path is what he runs at the snap (then his own assignment).
func _begin_path(view_start: Vector2) -> void:
	var p := to_field(view_start)
	var pick := _defender_at(p)
	var me := _me()
	if pick == null and me != null and p.distance_to(me.field_pos) <= 4.0:
		pick = me
	if pick == null:
		return
	if pick != me:
		switcher.manual(pick)
		switched.emit(pick)
	_drawing = true
	_path_pts = PackedVector2Array([pick.field_pos])
	runner.hero_path_preview = _path_pts
	runner.hero_path = PackedVector2Array()


func _extend_path(view_pos: Vector2) -> void:
	var p := to_field(view_pos)
	p = Vector2(clampf(p.x, 1.0, FieldGeo.LENGTH - 1.0), clampf(p.y, 1.0, FieldGeo.WIDTH - 1.0))
	if _path_pts.is_empty() or p.distance_to(_path_pts[_path_pts.size() - 1]) < PATH_STEP:
		return
	if _path_length() + p.distance_to(_path_pts[_path_pts.size() - 1]) > MAX_PATH_YARDS:
		return
	_path_pts.append(p)
	runner.hero_path_preview = _path_pts


func _path_length() -> float:
	var n := 0.0
	for i in range(1, _path_pts.size()):
		n += _path_pts[i].distance_to(_path_pts[i - 1])
	return n


## Lifting the finger keeps the path (a tiny scribble clears it) and remembers it for this call.
func _finish_path() -> void:
	_drawing = false
	var me := _me()
	runner.hero_path_preview = PackedVector2Array()
	if me == null:
		return
	var key := switcher.path_key(me)
	if _path_length() < 2.5:
		runner.hero_path = PackedVector2Array()
		switcher.paths.erase(key)
		return
	var pts := PackedVector2Array(_path_pts)
	pts.remove_at(0)   # the start point is where he already stands
	runner.hero_path = pts
	var rel := PackedVector2Array()
	for q in pts:
		rel.append(q - me.start_pos)
	switcher.paths[key] = rel
	Sfx.play("tap")


## A new play: bring back the path drawn for this call and slot last time.
func _restore_path() -> void:
	var me := _me()
	if me == null:
		return
	var key := switcher.path_key(me)
	if not switcher.paths.has(key):
		return
	var pts := PackedVector2Array()
	for q in switcher.paths[key]:
		pts.append(q + me.start_pos)
	runner.hero_path = pts


func _on_tapped(view_pos: Vector2) -> void:
	if not _active():
		return
	var p := to_field(view_pos)
	if runner.phase == PlayRunner.Phase.PRE_SNAP:
		# Tap a defender to pick him; anywhere else = ready (the owner snaps).
		var pick := _defender_at(p)
		if pick == null:
			ready_tapped.emit()
			return
		if pick == _me() and not runner.hero_path.is_empty():
			# Tapping your hero again wipes his drawn path.
			runner.hero_path = PackedVector2Array()
			switcher.paths.erase(switcher.path_key(pick))
			return
		var changed := pick != _me()
		switcher.manual(pick)
		if changed:
			switched.emit(pick)
		return
	if not _live():
		return
	var me := _me()
	if me == null or _returning():
		return
	var t := tuning
	# 0) The TAP! moment of a block duel (swim / spin / bull) beats everything else.
	if try_duel_move():
		return
	# 1) Ball in the air: leap if the tap is near the landing marker and we can get there.
	#    Too far to leap yet: sprint to the spot (tap again to jump).
	if runner.ball.state == Ball.State.AIR and p.distance_to(runner.ball.to) <= t.tap_ball_radius:
		try_jump()
		return
	# 2) Dive at the ball carrier.
	var c := runner.carrier
	if c != null and c.team == PlayerAgent.Team.OFFENSE and p.distance_to(c.field_pos) <= t.tap_carrier_radius:
		if try_dive():
			return
	# 3) Switch to the tapped defender.
	var best := _defender_at(p)
	if best != null and best != me:
		switcher.manual(best)
		switched.emit(best)
		return
	# 4) Nothing else to tap: burst.
	try_burst()


## The TAP! moment of a block duel: true when the tap was spent on the move (win or lose).
func try_duel_move() -> bool:
	var me := _me()
	if not _live() or me == null or _returning():
		return false
	return runner.contact.duel_move(me)


## A short speed burst for the hero (cooldown in GameplayTuning). True when it fired.
func try_burst() -> bool:
	var me := _me()
	if not _live() or me == null or _returning() or me.engaged_with != null:
		return false
	if me.start_burst(tuning):
		runner.hero_event.emit("burst", me.field_pos)
		return true
	return false


## The defender under a tap (within tap_switch_radius), or null.
func _defender_at(p: Vector2) -> PlayerAgent:
	var best: PlayerAgent = null
	var best_d := tuning.tap_switch_radius
	for d in runner.defense:
		# Sprites stand up from the feet (~24 px = 4 "yards" of screen y): a tap on the body counts.
		var body := Geometry2D.get_closest_point_to_segment(p, d.field_pos, d.field_pos + Vector2(0.0, -3.5))
		var dist := body.distance_to(p)
		if dist < best_d:
			best_d = dist
			best = d
	return best


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
		me.accel_mult = tuning.human_accel_mult
		me.desired_dir = _stick.normalized()
		me.throttle = _stick.length()
		# Full pursuit speed (brains leave e.g. a backpedal multiplier behind).
		me.speed_mult = tuning.human_speed_mult
	elif _dragging:
		me.human = true
		me.stop()
