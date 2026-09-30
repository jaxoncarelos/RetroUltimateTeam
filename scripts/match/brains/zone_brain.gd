class_name ZoneBrain
extends Brain
## Drops to a zone and shades toward the most dangerous receiver inside it.

var zone: Rect2
var aim := Vector2.ZERO
var bite := 0.0   ## seconds spent stepping up on a play-action fake


func _init(p_agent: PlayerAgent, p_ctx: PlayRunner, center_rel: Vector2, size: Vector2) -> void:
	super(p_agent, p_ctx)
	var c := Vector2(ctx.los_x + center_rel.x, clampf(ctx.ball_y + center_rel.y, 2.0, FieldGeo.WIDTH - 2.0))
	zone = Rect2(c - size * 0.5, size)
	aim = c


## Keyed defense: slide the zone toward where the repeated play's receivers will be.
func shift_zone(offset: Vector2) -> void:
	zone.position += offset
	aim += offset


func think() -> void:
	var reach := ctx.jump_reach()
	var watch := zone.grow(2.0 + reach)
	var best: PlayerAgent = null
	var best_d := INF
	for o in ctx.offense:
		if not o.is_eligible() or o.is_down or not watch.has_point(o.field_pos):
			continue
		# Deep to short: a receiver level with or behind you outranks one underneath.
		var d := o.field_pos.distance_to(agent.field_pos)
		if o.field_pos.x < agent.field_pos.x - 1.0:
			d += ctx.tuning.zone_underneath_penalty
		if d < best_d:
			best_d = d
			best = o
	if best != null:
		var p := ctx.anticipate(best) + Vector2(1.5, 0.0)
		var lim := zone.grow(3.0 + reach)
		aim = Vector2(clampf(p.x, lim.position.x, lim.end.x), clampf(p.y, lim.position.y, lim.end.y))
		# Against a vertical stem, keep your depth and let him come to you: stepping downhill
		# is how he gets behind you.
		if best.velocity.x > 2.0 and best.field_pos.x < agent.field_pos.x:
			aim.x = maxf(aim.x, agent.field_pos.x)
	else:
		aim = zone.get_center()
	# A receiver who ran past you (or past the back of the zone) is still your problem:
	# never drift back up toward the line while he is behind you.
	for o in ctx.offense:
		if o.is_eligible() and not o.is_down and o.field_pos.x > agent.field_pos.x \
				and absf(o.field_pos.y - agent.field_pos.y) < zone.size.y * 0.5 + 4.0:
			aim.x = maxf(aim.x, agent.field_pos.x)
			break


func act(dt: float) -> void:
	if bite > 0.0:
		bite -= dt
		agent.move_to(Vector2(ctx.los_x + 1.0, agent.field_pos.y), 1.0, false)
		return
	agent.move_to(aim, 0.9, true)


func label() -> String:
	return "zone"
