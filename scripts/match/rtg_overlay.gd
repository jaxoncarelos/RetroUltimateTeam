class_name RtgOverlay
extends Node2D
## Road to Glory field markings (world space, above the players):
##  - pre-snap corner: a dashed leash to the man you cover, or your zone's outline;
##  - the read telegraph: an arrow flashing at your man's hips just before he breaks;
##  - a receiver's CATCH ring closing on the landing spot (yellow inside the tap window);
##  - pop-up words over the field ("JUKE", "TRUCKED!", "JAM!", ...);
##  - an arrow on the screen edge pointing at you when you are off screen.

var runner: PlayRunner
var control: RtgControl
var _pops: Array = []        ## [{text, at: Vector2 (field), t: float, good: bool}]


func _ready() -> void:
	z_index = 6


## A rising word over a field spot.
func pop(text: String, at: Vector2, good := true) -> void:
	_pops.append({"text": text, "at": at, "t": 0.0, "good": good})
	if _pops.size() > 6:
		_pops.pop_front()


func _process(delta: float) -> void:
	for p in _pops:
		p["t"] = float(p["t"]) + delta
	_pops = _pops.filter(func(p: Dictionary) -> bool: return float(p["t"]) < 1.1)
	queue_redraw()


func _draw() -> void:
	if runner == null or runner.locked == null or not is_instance_valid(runner.locked):
		_draw_pops()
		return
	var me := runner.locked
	if runner.phase == PlayRunner.Phase.PRE_SNAP and me.team == PlayerAgent.Team.DEFENSE:
		_draw_assignment(me)
	if runner.phase == PlayRunner.Phase.LIVE:
		if control != null and control.tele_agent != null and is_instance_valid(control.tele_agent):
			_draw_telegraph(control.tele_agent, control.tele_dir)
		if me.team == PlayerAgent.Team.OFFENSE and me != runner.qb and runner.ball.state == Ball.State.AIR:
			_draw_catch_ring(me)
	_draw_pops()
	_draw_offscreen(me)


func _draw_assignment(me: PlayerAgent) -> void:
	var asg := me.assignment
	var col := Color(UiSkin.YELLOW, 0.85)
	match str(asg.get("type", "")):
		"man":
			var mark: PlayerAgent = runner.off_slots.get(asg.get("target", ""))
			if mark == null:
				return
			var a := FieldProjection.to_screen(me.field_pos)
			var b := FieldProjection.to_screen(mark.field_pos)
			var n := int(a.distance_to(b) / 5.0)
			for i in n:
				if i % 2 == 0:
					draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), col, 1.0)
			draw_set_transform(b.round(), 0.0, Vector2(1.0, 0.5))
			draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 20, col, 2.0)
			draw_set_transform(Vector2.ZERO)
		"zone":
			var c: Vector2 = asg.get("center", Vector2(8, 0))
			var sz: Vector2 = asg.get("size", Vector2(10, 10))
			var center := Vector2(runner.los_x + c.x, clampf(runner.ball_y + c.y, 2.0, FieldGeo.WIDTH - 2.0))
			var r := Rect2(FieldProjection.to_screen(center - sz * 0.5), FieldProjection.to_screen(sz))
			draw_rect(r, Color(UiSkin.YELLOW, 0.12))
			draw_rect(r, col, false, 1.0)


func _draw_telegraph(o: PlayerAgent, dir: Vector2) -> void:
	var at := FieldProjection.to_screen(o.field_pos) + Vector2(0, -6)
	var d := Vector2(dir.x * FieldProjection.PX_X, dir.y * FieldProjection.PX_Y).normalized()
	var flash := int(Time.get_ticks_msec() / 80) % 2 == 0
	var col := Color("#ff4b4b") if flash else UiSkin.YELLOW
	var tip := at + d * 18.0
	var n := Vector2(-d.y, d.x)
	draw_line(at + d * 6.0, tip, Color(0, 0, 0, 0.6), 4.0)
	draw_line(at + d * 6.0, tip, col, 2.0)
	draw_colored_polygon(PackedVector2Array([tip + d * 5.0, tip + n * 4.0, tip - n * 4.0]), col)
	UiSkin.draw_text_c(self, at.x, at.y - 22.0, "!", 8, col)


func _draw_catch_ring(me: PlayerAgent) -> void:
	var b := runner.ball
	if runner.intended != me and me.field_pos.distance_to(b.to) > 5.0:
		return
	var t := runner.tuning
	var left := b.time_left()
	var land := FieldProjection.to_screen(b.to).round()
	var r := 7.0 + clampf(left / 1.2, 0.0, 1.0) * 26.0
	var inside := left <= t.rtg_catch_window
	var col := UiSkin.YELLOW if inside else Color("#3fe071")
	if runner.catch_pressed_at >= 0.0:
		col = Color("#29adff")
	draw_set_transform(land, 0.0, Vector2(1.0, 0.5))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 28, Color(col, 0.95), 2.0)
	draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 20, Color(1, 1, 1, 0.5), 1.0)
	draw_set_transform(Vector2.ZERO)
	if inside and runner.catch_pressed_at == -1.0:
		UiSkin.draw_text_c(self, land.x, land.y - 14.0, "CATCH!", 8, UiSkin.YELLOW)


func _draw_pops() -> void:
	for p in _pops:
		var k := float(p["t"])
		var at := FieldProjection.to_screen(p["at"]) + Vector2(0, -34.0 - k * 22.0)
		var a := clampf(1.4 - k * 1.3, 0.0, 1.0)
		var col := UiSkin.YELLOW if p["good"] else Color("#ff4b4b")
		UiSkin.draw_text_c(self, at.x, at.y, str(p["text"]), 8, Color(col, a), Color(0, 0, 0, 0))


## You are off screen: an arrow on the nearest screen edge points at you.
func _draw_offscreen(me: PlayerAgent) -> void:
	var xf := get_viewport().get_canvas_transform()
	var view := Rect2(xf.affine_inverse() * Vector2.ZERO, get_viewport_rect().size / xf.get_scale())
	var p := FieldProjection.to_screen(me.field_pos) + Vector2(0, -10)
	var inner := view.grow(-14.0)
	if inner.has_point(p):
		return
	var c := Vector2(clampf(p.x, inner.position.x, inner.end.x), clampf(p.y, inner.position.y + 20.0, inner.end.y - 22.0))
	var d := (p - c).normalized()
	var n := Vector2(-d.y, d.x)
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 120.0)
	draw_circle(c, 9.0, Color(UiSkin.NAVY_DEEP, 0.8))
	draw_colored_polygon(PackedVector2Array([c + d * 9.0, c - d * 3.0 + n * 6.0, c - d * 3.0 - n * 6.0]), Color(UiSkin.YELLOW, pulse))
	UiSkin.draw_text_c(self, c.x, c.y + 18.0, "YOU", 8, UiSkin.YELLOW)
