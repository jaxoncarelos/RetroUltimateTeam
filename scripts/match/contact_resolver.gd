class_name ContactResolver
extends RefCounted
## Blocks (engage/hold/shed) and tackles, using RatingModel soft probabilities.

var ctx: PlayRunner


func _init(p_ctx: PlayRunner) -> void:
	ctx = p_ctx


func resolve(dt: float) -> void:
	_blocks(dt)
	_tackles()


static func rush_rating(d: PlayerAgent) -> float:
	return maxf(d.attr("prs"), d.attr("str") * 0.9)


func _blocks(dt: float) -> void:
	var t := ctx.tuning
	for b in ctx.offense:
		if b.engaged_with != null:
			_hold(b, b.engaged_with, dt)
			continue
		if b == ctx.carrier or not b.can_act() or b.block_cd > 0.0 or not (b.brain is BlockBrain):
			continue
		for d in ctx.defense:
			if d == ctx.carrier or d.engaged_with != null or not d.can_act() or d.block_cd > 0.0:
				continue
			if b.field_pos.distance_to(d.field_pos) < t.engage_range:
				b.engaged_with = d
				d.engaged_with = b
				var jitter := ctx.rng.randf_range(-1.0, 1.0)
				d.shed_timer = RatingModel.shed_time(t, b.attr("blk"), rush_rating(d), jitter)
				if ctx.carrier != null and ctx.carrier != ctx.qb:
					d.shed_timer *= t.open_field_shed_mult
				break


func _hold(b: PlayerAgent, d: PlayerAgent, dt: float) -> void:
	d.shed_timer -= dt
	if d.shed_timer <= 0.0 or d.is_down or b.is_down or d == ctx.carrier:
		b.engaged_with = null
		d.engaged_with = null
		d.block_cd = 0.8
		b.block_cd = 0.6
		return
	var edge := rush_rating(d) - b.attr("blk")
	var drift: Vector2
	if ctx.is_run_play() or ctx.carrier != null and ctx.carrier != ctx.qb:
		drift = Vector2(1.0, 0.0) * clampf(0.5 - edge * 0.03, 0.1, 1.4)
	else:
		drift = d.desired_dir * clampf(0.6 + edge * 0.03, 0.2, 1.6)
	d.field_pos += drift * dt
	d.velocity = drift
	b.velocity = drift
	var sep := b.field_pos - d.field_pos
	if sep.length() < 0.01:
		sep = Vector2(-1.0, 0.0)
	b.field_pos = d.field_pos + sep.normalized() * 0.9


func _tackles() -> void:
	var c := ctx.carrier
	if c == null or c.is_down or c.dive_timer > 0.0 and c.z_height > 0.3:
		return
	var t := ctx.tuning
	var opponents := ctx.defense if c.team == PlayerAgent.Team.OFFENSE else ctx.offense
	for d in opponents:
		if d.engaged_with != null or d.tackle_cd > 0.0 or d.is_down:
			continue
		var diving := d.dive_timer > 0.0
		if not diving and not d.can_act():
			continue
		var dist := d.field_pos.distance_to(c.field_pos)
		var reach := t.dive_tackle_range if diving else t.tackle_range
		if dist > reach:
			# CPU defenders close the last yard with a dive.
			if not diving and not d.human and dist < t.cpu_dive_range:
				d.start_dive(t, c.field_pos + c.velocity * 0.15 - d.field_pos, t.dive_recover)
			continue
		var p := RatingModel.tackle_prob(t, d.attr("tak"), c.attr("elu"), c.attr("str"), c.juke_timer > 0.0)
		if diving:
			p = minf(p + t.dive_tackle_bonus, t.tackle_max)
		if ctx.rng.randf() < p:
			ctx.on_tackle(d, c)
			return
		if not diving:
			d.knock_down(t.missed_tackle_stun)
		d.tackle_cd = 1.2
		c.velocity *= 0.75
		ctx.broken_tackles += 1
