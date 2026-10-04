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


## Is this a deep zone (keeps everything in front of it)?
func is_deep() -> bool:
	return zone.get_center().x - ctx.los_x >= 12.0


## Where this defender looks for receivers, and how far he may chase one.
func watch_rect(extra := 2.0) -> Rect2:
	var reach := ctx.jump_reach()
	var r := zone.grow(extra + reach)
	if not is_deep():
		# Underneath zones squeeze down to the line and out to the flat (the checkdown is theirs).
		r = r.merge(Rect2(Vector2(ctx.los_x - 3.0, r.position.y - 4.0), Vector2(r.end.x - ctx.los_x + 3.0, r.size.y + 8.0)))
	return r


## How much he wants receiver `o` (lower = more; INF = not his business).
func score(o: PlayerAgent) -> float:
	if not o.is_eligible() or o.is_down or not watch_rect().has_point(o.field_pos):
		return INF
	var d := o.field_pos.distance_to(agent.field_pos)
	if is_deep():
		# Deep zones, deep to short: a receiver level with or behind you outranks one underneath.
		if o.field_pos.x < agent.field_pos.x - 1.0:
			d += ctx.tuning.zone_underneath_penalty
	elif o.field_pos.x > zone.end.x + 2.0:
		# Underneath zones carry a vertical only so far, then hand him to the deep help.
		d += ctx.tuning.zone_underneath_penalty
	if o == ctx.qb_target_hint and ctx.qb_is_passer():
		d -= 3.0 * clampf((agent.attr("awr") - 60.0) / 39.0, 0.0, 1.0)   # he reads the QB's eyes
	return d


func think() -> void:
	var deep := is_deep()
	var lim := watch_rect(3.0)
	# The defense matches its zone players to receivers together (no two on one man while
	# another runs free). A deep defender with nobody matched still sits over the deepest
	# threat in his area; an underneath one sinks to the middle of his zone.
	var best: PlayerAgent = ctx.zone_matches().get(agent)
	if best == null and deep:
		var best_d := INF
		for o in ctx.offense:
			var sc := score(o)
			if sc < best_d:
				best_d = sc
				best = o
	if best != null:
		# Deep: stay over the top of him (more the faster he is coming); underneath: sit on him.
		var cushion := 0.8
		if deep:
			cushion = 1.6 + clampf(best.velocity.x, 0.0, 9.0) * 0.15
		var p := ctx.anticipate(best) + Vector2(cushion, 0.0)
		aim = Vector2(clampf(p.x, lim.position.x, lim.end.x), clampf(p.y, lim.position.y, lim.end.y))
		# Against a vertical stem, keep your depth and let him come to you: stepping downhill
		# is how he gets behind you.
		if deep and best.velocity.x > 2.0 and best.field_pos.x < agent.field_pos.x:
			aim.x = maxf(aim.x, agent.field_pos.x)
	else:
		aim = zone.get_center()
	if not deep:
		return
	# A receiver who ran past a deep defender (or past the back of his zone) is still his
	# problem: never drift back up toward the line while he is behind you.
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
