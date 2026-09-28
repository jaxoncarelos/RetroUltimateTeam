class_name PlayOverlay
extends Node2D
## Pre-snap route preview (under players) or live aim arc + landing reticle (above players).

enum Kind { ROUTES, AIM }

const ROUTE_COLOR := Color(1, 1, 1, 0.75)
const RUN_COLOR := Color("#ffa300")
const AIM_COLOR := Color("#fff1e8")
const RETICLE_COLOR := Color("#ffec27")

var kind := Kind.ROUTES
var runner: PlayRunner
var aim_active := false
var aim_target := Vector2.ZERO
var landing_marker := Vector2.ZERO
var show_landing := false


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if runner == null:
		return
	if kind == Kind.ROUTES:
		# Only the offense's own player gets the route preview (no peeking on defense).
		if runner.phase == PlayRunner.Phase.PRE_SNAP and runner.human_team != PlayerAgent.Team.DEFENSE:
			_draw_routes()
	else:
		if runner.phase == PlayRunner.Phase.PRE_SNAP and runner.human_team == PlayerAgent.Team.OFFENSE:
			_draw_snap_hint()
		if aim_active and runner.qb_is_passer():
			_draw_aim()
		if show_landing and runner.ball.state == Ball.State.AIR:
			_draw_reticle(FieldProjection.to_screen(runner.ball.to), RETICLE_COLOR, 0.5 + 0.5 * sin(Time.get_ticks_msec() / 90.0))


## Pre-snap: a pulsing grab ring on the QB with a "pull back" chevron trail behind him.
func _draw_snap_hint() -> void:
	if runner.qb == null:
		return
	var c := FieldProjection.to_screen(runner.qb.field_pos).round() + Vector2(0, -8)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0)
	draw_arc(c, 13.0 + pulse * 3.0, 0.0, TAU, 20, Color(RETICLE_COLOR, 0.45 + 0.4 * pulse), 1.0)
	if runner.is_run_play():
		return
	var shift := int(Time.get_ticks_msec() / 90) % 6
	for i in 3:
		var x := c.x - 20.0 - i * 7.0 - shift
		var a := Color(AIM_COLOR, 0.8 - i * 0.22)
		# "<" chevron: pull the QB back to aim.
		draw_rect(Rect2(x, c.y - 1, 2, 2), a)
		draw_rect(Rect2(x + 2, c.y - 3, 2, 2), a)
		draw_rect(Rect2(x + 2, c.y + 1, 2, 2), a)


func _draw_routes() -> void:
	for a in runner.offense:
		var t := str(a.assignment.get("type", ""))
		if t != "route" and t != "carry" and t != "sneak":
			continue
		var color := ROUTE_COLOR if t == "route" else RUN_COLOR
		var prev := FieldProjection.to_screen(a.start_pos)
		var path: PackedVector2Array = a.assignment.get("path", PackedVector2Array())
		for p in path:
			var cur := FieldProjection.to_screen(a.start_pos + p)
			_dotted(prev, cur, color)
			prev = cur
		draw_rect(Rect2(prev - Vector2(1, 1), Vector2(3, 3)), color)


func _draw_aim() -> void:
	var from := runner.qb.field_pos
	var dist := from.distance_to(aim_target)
	var arc := RatingModel.throw_arc(runner.tuning, runner.qb.attr("thp"), dist)
	var steps := 14
	for i in range(1, steps + 1):
		var u := float(i) / steps
		var p := Ball.arc_point(from, aim_target, arc.y, u)
		var s := FieldProjection.to_screen(Vector2(p.x, p.y)) + FieldProjection.lift(p.z)
		draw_rect(Rect2(s.round(), Vector2(2, 2)), AIM_COLOR)
	_draw_reticle(FieldProjection.to_screen(aim_target), RETICLE_COLOR, 1.0)


func _draw_reticle(center: Vector2, color: Color, alpha: float) -> void:
	var c := Color(color, alpha)
	draw_set_transform(center.round(), 0.0, Vector2(1.0, 0.5))
	draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 16, c, 2.0)
	draw_set_transform(Vector2.ZERO)
	draw_rect(Rect2(center.round() - Vector2(1, 1), Vector2(2, 2)), c)


func _dotted(a: Vector2, b: Vector2, color: Color) -> void:
	var len := a.distance_to(b)
	var n := int(len / 4.0)
	for i in n:
		var p := a.lerp(b, float(i) / maxf(n, 1))
		draw_rect(Rect2(p.round(), Vector2(2, 1)), color)
