class_name ZoneBrain
extends Brain
## Drops to a zone and shades toward the most dangerous receiver inside it.

var zone: Rect2
var aim := Vector2.ZERO


func _init(p_agent: PlayerAgent, p_ctx: PlayRunner, center_rel: Vector2, size: Vector2) -> void:
	super(p_agent, p_ctx)
	var c := Vector2(ctx.los_x + center_rel.x, clampf(ctx.ball_y + center_rel.y, 2.0, FieldGeo.WIDTH - 2.0))
	zone = Rect2(c - size * 0.5, size)
	aim = c


func think() -> void:
	var reach := ctx.jump_reach()
	var watch := zone.grow(2.0 + reach)
	var best: PlayerAgent = null
	var best_d := INF
	for o in ctx.offense:
		if not o.is_eligible() or o.is_down or not watch.has_point(o.field_pos):
			continue
		var d := o.field_pos.distance_to(agent.field_pos)
		if d < best_d:
			best_d = d
			best = o
	if best != null:
		var p := ctx.anticipate(best) + Vector2(1.5, 0.0)
		var lim := zone.grow(3.0 + reach)
		aim = Vector2(clampf(p.x, lim.position.x, lim.end.x), clampf(p.y, lim.position.y, lim.end.y))
	else:
		aim = zone.get_center()


func act(_dt: float) -> void:
	agent.move_to(aim, 0.9, true)


func label() -> String:
	return "zone"
