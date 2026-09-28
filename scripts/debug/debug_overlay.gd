class_name DebugOverlay
extends Node2D
## Brain/AI debug view (toggle: F1 or a three-finger tap): every agent's brain label,
## zone rectangles, man-coverage lines, route targets, and each receiver's openness score
## as the CPU QB would see it. Drawn in world space above the players.

const ZONE_COLOR := Color(0.16, 0.68, 1.0, 0.8)
const MAN_COLOR := Color(1.0, 0.47, 0.66, 0.8)
const ROUTE_COLOR := Color(1.0, 0.93, 0.15, 0.7)

var runner: PlayRunner


func _ready() -> void:
	z_index = 20
	visible = false


func toggle() -> void:
	visible = not visible


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		toggle()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if runner == null or runner.agents.is_empty():
		return
	var font := PixelFont.get_font()
	var reading_qb := runner.phase == PlayRunner.Phase.LIVE and runner.qb_is_passer()
	for a in runner.agents:
		if not is_instance_valid(a):
			continue
		var s := FieldProjection.to_screen(a.field_pos)
		var b := a.brain
		if b is ZoneBrain:
			var z := (b as ZoneBrain).zone
			var r := Rect2(FieldProjection.to_screen(z.position), FieldProjection.to_screen(z.size))
			draw_rect(r, Color(ZONE_COLOR, 0.12))
			draw_rect(r, ZONE_COLOR, false, 1.0)
			draw_line(s, FieldProjection.to_screen((b as ZoneBrain).aim), ZONE_COLOR, 1.0)
		elif b is ManCoverBrain and (b as ManCoverBrain).mark != null:
			draw_line(s, FieldProjection.to_screen((b as ManCoverBrain).mark.field_pos), MAN_COLOR, 1.0)
		elif b is RouteBrain:
			draw_line(s, FieldProjection.to_screen((b as RouteBrain).next_point()), ROUTE_COLOR, 1.0)
		var label := b.label() if b != null else ("HUMAN" if a.human else "-")
		draw_string(font, s + Vector2(-12, 8), label.to_upper().left(8), HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
				Color(1, 1, 1, 0.85))
		if reading_qb and a.is_eligible():
			var e := QBReadLogic.evaluate(runner, a)
			if not e.is_empty():
				var open: float = e["openness"]
				var c := Color("#00e436") if open > 2.4 else (Color("#ffec27") if open > 0.5 else Color("#ff004d"))
				draw_string(font, s + Vector2(-8, -24), "%.1f" % open, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, c)
	if runner.key_level > 0.0:
		var qb_s := FieldProjection.to_screen(runner.qb.field_pos) if runner.qb != null else Vector2.ZERO
		draw_string(font, qb_s + Vector2(-20, 20), "KEY %.2f" % runner.key_level, HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
				Color("#ff004d"))
