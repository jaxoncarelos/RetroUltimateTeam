class_name CameraRig
extends Camera2D
## Follows the play with look-ahead toward the offense's direction; clamped to the field.
## While the human aims it leads toward the reticle (deep targets stay on screen); with the
## ball in the air it frames the landing spot. Highlights (PlayRunner.big_moment / big
## hits) get a short slow-mo and a zoom punch — skipped headless (sims, tests).

const LOOK_AHEAD_PX := 70.0
## Extra look-ahead while the QB holds the ball on a pass play (see the routes develop).
const PASS_LOOK_AHEAD_PX := 110.0
const FOLLOW_RATE := 5.0
const AIM_FOLLOW_RATE := 3.5

var runner: PlayRunner:
	set(v):
		runner = v
		_hook()
## Debug: when set (field yards), the camera stays on this point (--look=X,Y).
var pinned := Vector2(-1, -1)
## Instant replay: the camera looks here (field yards) instead of following the play (INF = off).
var focus_override := Vector2.INF

## Screen shake: trauma 0..1 decays; offset = trauma² × max shake (whole pixels).
var trauma := 0.0
const SHAKE_PX := 5.0

var _punch := 0.0
var _slowmo_until := -1.0
var _hooked: PlayRunner = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # so slow-mo is always restored, even when paused
	var r := FieldProjection.world_rect()
	limit_left = int(r.position.x)
	limit_top = int(r.position.y)
	limit_right = int(r.end.x)
	limit_bottom = int(r.end.y)
	_hook()


func _exit_tree() -> void:
	_end_slowmo()


func _hook() -> void:
	if runner == null or runner == _hooked or not is_inside_tree():
		return
	_hooked = runner
	runner.big_moment.connect(func(_kind: String, _at: Vector2) -> void: highlight())
	runner.big_hit.connect(func(_at: Vector2, speed: float) -> void:
		if runner.tuning != null and speed >= runner.tuning.slowmo_hit_speed:
			highlight())


func target_position() -> Vector2:
	if focus_override != Vector2.INF:
		return FieldProjection.to_screen(focus_override) + Vector2(LOOK_AHEAD_PX * 0.5, 0.0)
	if pinned.x >= 0.0:
		return FieldProjection.to_screen(pinned)
	if runner == null:
		return global_position
	var ball := runner.ball
	if ball != null and ball.state == Ball.State.AIR:
		# Frame the landing spot; the ball flies into view from the left.
		return FieldProjection.to_screen(ball.field_pos.lerp(ball.to, 0.6)) + Vector2(20.0, 0.0) 				+ FieldProjection.lift(ball.z) * 0.3
	var base := FieldProjection.to_screen(runner.focus_point())
	if runner.aim_preview != Vector2.INF and runner.qb != null:
		var lead := runner.tuning.aim_camera_lead if runner.tuning != null else 130.0
		var reticle := FieldProjection.to_screen(runner.aim_preview)
		var qb := FieldProjection.to_screen(runner.qb.field_pos)
		# Raise the view a little for a high arc so its top stays on screen.
		var apex := float(runner.plan_throw(runner.aim_preview)["apex"])
		var y := lerpf(qb.y, reticle.y, 0.5) + FieldProjection.lift(apex).y * 0.35
		return Vector2(maxf(qb.x + LOOK_AHEAD_PX, reticle.x - lead), y)
	var me := runner.locked
	if me != null and is_instance_valid(me) and me != runner.carrier:
		# Road to Glory: you are the star of the shot; the ball stays in the corner of the frame.
		var share := 0.4 if runner.phase == PlayRunner.Phase.PRE_SNAP else 0.28
		var p := me.field_pos.lerp(runner.focus_point(), share)
		return FieldProjection.to_screen(p) + Vector2(LOOK_AHEAD_PX * 0.5, 0.0)
	if runner.qb_is_passer():
		return base + Vector2(PASS_LOOK_AHEAD_PX, 0.0)
	return base + Vector2(LOOK_AHEAD_PX, 0.0)


func snap_to_target() -> void:
	global_position = target_position()
	reset_smoothing()


## Between plays (kickoffs, punts) there are no players to follow: glide to the spot.
func show_spot(x: float) -> void:
	pinned = Vector2(x, FieldGeo.CENTER_Y)


func follow_play() -> void:
	pinned = Vector2(-1, -1)


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


## Highlight juice: brief slow-mo + zoom punch (no-op headless).
func highlight() -> void:
	if DisplayServer.get_name() == "headless" or runner == null or runner.tuning == null:
		return
	var t := runner.tuning
	_punch = t.camera_punch
	if t.slowmo_time > 0.0:
		Engine.time_scale = t.slowmo_scale
		_slowmo_until = Time.get_ticks_msec() / 1000.0 + t.slowmo_time


func _end_slowmo() -> void:
	if _slowmo_until >= 0.0:
		_slowmo_until = -1.0
		Engine.time_scale = 1.0


func _process(delta: float) -> void:
	# delta is scaled by Engine.time_scale; use real time for camera feel and slow-mo.
	var real := delta / maxf(Engine.time_scale, 0.01)
	if _slowmo_until >= 0.0 and (Time.get_ticks_msec() / 1000.0 >= _slowmo_until or get_tree().paused):
		_end_slowmo()
	if get_tree().paused:
		return
	var rate := AIM_FOLLOW_RATE if runner != null and runner.aim_preview != Vector2.INF else FOLLOW_RATE
	global_position = global_position.lerp(target_position(), 1.0 - exp(-rate * real))
	if _punch > 0.0:
		_punch = maxf(0.0, _punch - real * 0.35)
	var base := runner.tuning.camera_zoom if runner != null and runner.tuning != null else 1.0
	zoom = Vector2.ONE * (base + _punch)
	if trauma > 0.0:
		trauma = maxf(0.0, trauma - real * 1.8)
		var mag := trauma * trauma * SHAKE_PX
		offset = Vector2(randf_range(-mag, mag), randf_range(-mag, mag)).round()
	elif offset != Vector2.ZERO:
		offset = Vector2.ZERO
