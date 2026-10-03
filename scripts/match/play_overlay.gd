class_name PlayOverlay
extends Node2D
## Pre-snap route preview (under players) or live aim arc + landing reticle (above players).
## Aim preview: the real flight arc (dots, colored by throw type), its ground shadow and an
## apex stem so the height reads at a glance, the landing reticle with BULLET / TOUCH / LOB,
## and a ghost marker where each receiver will be when the ball lands (the assisted one is
## highlighted). In flight: the landing reticle plus the ball's shadow track.

enum Kind { ROUTES, AIM }

const ROUTE_COLOR := Color(1, 1, 1, 0.75)
const RUN_COLOR := Color("#ffa300")
const AIM_COLOR := Color("#fff1e8")
const RETICLE_COLOR := Color("#ffec27")
const KIND_COLORS: Array[Color] = [Color("#fff1e8"), Color("#ffa300"), Color("#29adff")]
const SHADOW_COLOR := Color(0, 0, 0, 0.35)
const GHOST_COLOR := Color("#fff1e8")

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
		if runner.human_team == PlayerAgent.Team.DEFENSE:
			_draw_hero_path()
	else:
		if runner.phase == PlayRunner.Phase.PRE_SNAP and runner.human_team == PlayerAgent.Team.OFFENSE \
				and runner.human_qb():
			_draw_snap_hint()
		if aim_active and runner.qb_is_passer():
			_draw_aim()
		if show_landing and runner.ball.state == Ball.State.AIR:
			_draw_flight()


## The hero's drawn path (or the one being drawn): dotted cyan line from him with an arrowhead,
## and a pulsing dot on him pre-snap so it is clear where to start the drag.
func _draw_hero_path() -> void:
	var me := runner.controlled
	if me == null:
		return
	var pts := PackedVector2Array()
	if runner.phase == PlayRunner.Phase.PRE_SNAP:
		if not runner.hero_path_preview.is_empty():
			pts = runner.hero_path_preview
		else:
			pts.append(me.field_pos)
			pts.append_array(runner.hero_path)
	elif me.brain is DrawnPathBrain:
		var b := me.brain as DrawnPathBrain
		pts.append(me.field_pos)
		for i in range(b.idx, b.points.size()):
			pts.append(b.points[i])
	if pts.size() < 2:
		return
	var col := Color("#29adff")
	var sp := PackedVector2Array()
	for p in pts:
		sp.append(FieldProjection.to_screen(p).round())
	# Bold line: dark outline under a bright 2 px core, dots at the corners, arrowhead at the end.
	draw_polyline(sp, Color(0.02, 0.04, 0.2, 0.75), 4.0)
	draw_polyline(sp, col, 2.0)
	for i in range(1, sp.size() - 1):
		draw_circle(sp[i], 2.0, Color.WHITE)
	var prev := sp[sp.size() - 1]
	var back := sp[sp.size() - 2]
	var dir := (prev - back).normalized() if prev.distance_to(back) > 0.1 else Vector2.RIGHT
	var n := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([prev + dir * 6.0, prev - dir * 3.0 + n * 4.5, prev - dir * 3.0 - n * 4.5]), Color(0.02, 0.04, 0.2, 0.9))
	draw_colored_polygon(PackedVector2Array([prev + dir * 4.5, prev - dir * 2.0 + n * 3.0, prev - dir * 2.0 - n * 3.0]), col)


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
	var me := runner.locked
	for a in runner.offense:
		var t := str(a.assignment.get("type", ""))
		if t != "route" and t != "carry" and t != "sneak":
			continue
		var color := ROUTE_COLOR if t == "route" else RUN_COLOR
		if me != null and me != runner.qb:
			# Road to Glory: your own job in bold gold, the rest of the play faint.
			if a == me:
				_draw_path_bold(a.start_pos, a.assignment.get("path", PackedVector2Array()), RETICLE_COLOR)
				continue
			color = Color(color, 0.3)
		var prev := FieldProjection.to_screen(a.start_pos)
		var path: PackedVector2Array = a.assignment.get("path", PackedVector2Array())
		for p in path:
			var cur := FieldProjection.to_screen(a.start_pos + p)
			_dotted(prev, cur, color)
			prev = cur
		draw_rect(Rect2(prev - Vector2(1, 1), Vector2(3, 3)), color)


## A thick path with an arrowhead (Road to Glory: your route / run lane).
func _draw_path_bold(start: Vector2, path: PackedVector2Array, col: Color) -> void:
	var sp := PackedVector2Array([FieldProjection.to_screen(start).round()])
	for p in path:
		sp.append(FieldProjection.to_screen(start + p).round())
	if sp.size() < 2:
		return
	draw_polyline(sp, Color(0.02, 0.04, 0.2, 0.75), 4.0)
	draw_polyline(sp, col, 2.0)
	var tip := sp[sp.size() - 1]
	var dir := (tip - sp[sp.size() - 2]).normalized()
	var n := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([tip + dir * 5.0, tip - dir * 3.0 + n * 4.0, tip - dir * 3.0 - n * 4.0]), col)


func _draw_aim() -> void:
	var from := runner.qb.field_pos
	var plan := runner.plan_throw(aim_target)
	var apex := float(plan["apex"])
	var kind := int(plan["kind"])
	var col: Color = KIND_COLORS[kind]
	var land_s := FieldProjection.to_screen(aim_target)
	# Ground shadow of the flight path.
	_dotted(FieldProjection.to_screen(from), land_s, SHADOW_COLOR)
	# The arc itself.
	var steps := clampi(int(from.distance_to(aim_target) * 1.3), 10, 70)
	var top := Vector2.ZERO
	var top_z := -1.0
	for i in range(1, steps + 1):
		var u := float(i) / steps
		var p := Ball.arc_point(from, aim_target, apex, u)
		var s := FieldProjection.to_screen(Vector2(p.x, p.y)) + FieldProjection.lift(p.z)
		draw_rect(Rect2(s.round() - Vector2(0, 1), Vector2(2, 1)), Color(0, 0, 0, 0.35))
		draw_rect(Rect2(s.round(), Vector2(2, 2)), col)
		if p.z > top_z:
			top_z = p.z
			top = Vector2(p.x, p.y)
	# Apex stem: a faint vertical line from the top of the arc down to its shadow.
	if kind != PassModel.Kind.BULLET:
		var g := FieldProjection.to_screen(top).round()
		var h := FieldProjection.lift(top_z).round()
		for y in range(int(h.y), 0, 3):
			draw_rect(Rect2(g + Vector2(0, y), Vector2(1, 1)), Color(col, 0.45))
	_draw_ghosts(float(plan["dur"]))
	_draw_reticle(land_s, RETICLE_COLOR, 1.0)
	var font := ThemeDB.fallback_font
	if font != null:
		var label: String = PassModel.KIND_NAMES[kind]
		var size := ThemeDB.fallback_font_size
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var at := (land_s + Vector2(-w * 0.5, -9)).round()
		draw_string(font, at + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.7))
		draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## Where each eligible receiver will be when a ball thrown now comes down.
func _draw_ghosts(dur: float) -> void:
	for o in runner.offense:
		if not o.is_eligible() or o.is_down:
			continue
		var g := FieldProjection.to_screen(runner.predict(o, dur)).round()
		var hot := o == runner.aim_assist_target
		var c := Color(RETICLE_COLOR if hot else GHOST_COLOR, 0.95 if hot else 0.55)
		if hot:
			_dotted(FieldProjection.to_screen(o.field_pos), g, Color(c, 0.5))
		draw_rect(Rect2(g - Vector2(2, 2), Vector2(5, 5)), c, false, 1.0)


## Ball in the air: pulsing landing reticle and the ball's remaining shadow track.
func _draw_flight() -> void:
	var b := runner.ball
	var land := FieldProjection.to_screen(b.to)
	_dotted(FieldProjection.to_screen(b.field_pos), land, SHADOW_COLOR)
	_draw_reticle(land, RETICLE_COLOR, 0.5 + 0.5 * sin(Time.get_ticks_msec() / 90.0))
	if runner.human_team == PlayerAgent.Team.DEFENSE and runner.controlled != null:
		_draw_jump_ring(land)


## Ball-hawk timing ring (defense): a ring closes in on the landing marker; tap (the leap) as it
## meets the marker for the best chance to pick it. Green = your man is close enough to leap.
func _draw_jump_ring(land: Vector2) -> void:
	var t := runner.tuning
	var left := runner.ball.time_left()
	var ideal := t.jump_time * 0.5
	if left < ideal - t.jump_good:
		return
	var r := 8.0 + clampf((left - ideal) / 0.9, 0.0, 1.0) * 26.0
	var in_range := runner.controlled.field_pos.distance_to(runner.ball.to) <= t.jump_start_range
	var perfect := absf(left - ideal) <= t.jump_perfect
	var col := (Color("#ffec27") if perfect else Color("#3fe071")) if in_range else Color("#93a6e8")
	draw_set_transform(land.round(), 0.0, Vector2(1.0, 0.5))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 28, Color(col, 0.9), 2.0)
	draw_set_transform(Vector2.ZERO)
	if in_range and perfect:
		UiSkin.draw_text_c(self, land.x, land.y - 14.0, "NOW!", 8, Color("#ffec27"))


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
