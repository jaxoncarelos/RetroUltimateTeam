class_name ContactResolver
extends RefCounted
## Blocks (engage/hold/shed) and tackles, using RatingModel soft probabilities.

var ctx: PlayRunner
## Tackle counters across plays (sims print them): CPU/human tries and tackles, CPU dives.
static var stats := {"tries": 0, "tackles": 0, "human_tries": 0, "human_tackles": 0, "dives": 0, "dive_tries": 0}


func _init(p_ctx: PlayRunner) -> void:
	ctx = p_ctx


func resolve(dt: float) -> void:
	_blocks(dt)
	_tackles()


## Run plays: each blocker fires off the ball into the nearest free defender over him.
func snap_engage() -> void:
	var t := ctx.tuning
	for b in ctx.offense:
		if not (b.brain is BlockBrain) or b.pos_code not in ["OL", "TE"]:
			continue
		var best: PlayerAgent = null
		var best_d := t.snap_engage_range
		for d in ctx.defense:
			if d.engaged_with != null or d.start_pos.x - ctx.los_x > 2.0:
				continue
			var dist := b.field_pos.distance_to(d.field_pos)
			if dist < best_d:
				best_d = dist
				best = d
		if best != null:
			_engage(b, best)


func _engage(b: PlayerAgent, d: PlayerAgent) -> void:
	var t := ctx.tuning
	b.engaged_with = d
	d.engaged_with = b
	var jitter := ctx.rng.randf_range(-1.0, 1.0)
	d.shed_timer = RatingModel.shed_time(t, b.attr("blk"), rush_rating(d), jitter)
	if ctx.carrier != null and ctx.carrier != ctx.qb and not ctx.is_run_play():
		d.shed_timer *= t.open_field_shed_mult
	if _is_pass_pro():
		d.shed_timer *= t.pass_shed_mult
	if ctx.is_run_play():
		d.shed_timer *= 1.0 - ctx.def_ai.shed_cut * ctx.key_level
	if d == ctx.controlled and d.team == ctx.human_team:
		d.shed_timer *= t.human_shed_mult   # your man fights off blocks fast


## True while the offense protects a QB who still holds the ball on a pass play.
func _is_pass_pro() -> bool:
	return not ctx.is_run_play() and ctx.carrier == ctx.qb and not ctx.pass_thrown and not ctx.scrambling


static func rush_rating(d: PlayerAgent) -> float:
	return maxf(d.attr("prs"), d.attr("str") * 0.9)


func _blocks(dt: float) -> void:
	var t := ctx.tuning
	# On an interception return the defense becomes the blocking team.
	var returning := ctx.carrier != null and ctx.carrier.team == PlayerAgent.Team.DEFENSE
	var blockers := ctx.defense if returning else ctx.offense
	var rushers := ctx.offense if returning else ctx.defense
	for b in blockers:
		if b.engaged_with != null:
			_hold(b, b.engaged_with, dt)
			continue
		if b == ctx.carrier or not b.can_act() or b.block_cd > 0.0 or not (b.brain is BlockBrain):
			continue
		for d in rushers:
			if d == ctx.carrier or d.engaged_with != null or not d.can_act() or d.block_cd > 0.0:
				continue
			var reach := t.run_engage_range if ctx.is_run_play() else t.engage_range
			if b.field_pos.distance_to(d.field_pos) < reach:
				_engage(b, d)
				break


func _hold(b: PlayerAgent, d: PlayerAgent, dt: float) -> void:
	var t := ctx.tuning
	d.shed_timer -= dt
	if d.shed_timer <= 0.0 or d.is_down or b.is_down or d == ctx.carrier:
		b.engaged_with = null
		d.engaged_with = null
		var pro := _is_pass_pro()
		d.block_cd = t.pass_rusher_cd if pro else 0.8
		b.block_cd = t.pass_blocker_cd if pro else 0.6
		return
	var edge := rush_rating(d) - b.attr("blk")
	var drift: Vector2
	if ctx.is_run_play() or ctx.carrier != null and ctx.carrier != ctx.qb:
		# Drive him back and wall him off to the side away from the ball carrier.
		var fwd := 1.0 if b.team == PlayerAgent.Team.OFFENSE else -1.0
		drift = Vector2(fwd, 0.0) * clampf(0.5 - edge * 0.03, 0.1, 1.4)
		var c := ctx.carrier
		if c != null and c != b and c.team == b.team:
			var side := signf(d.field_pos.y - c.field_pos.y)
			if side == 0.0:
				side = 1.0
			drift.y = side * t.run_seal_push * clampf(1.0 - edge * 0.03, 0.2, 1.5)
	else:
		drift = d.desired_dir * clampf(0.6 + edge * 0.03, 0.2, 1.6)
	d.field_pos += drift * dt
	d.velocity = drift
	b.velocity = drift
	var sep := b.field_pos - d.field_pos
	if sep.length() < 0.01:
		sep = Vector2(-1.0, 0.0)
	b.field_pos = d.field_pos + sep.normalized() * 0.9


## True for the defender the human controls (ring + name pill): he gets the human tackle
## range and bonus ("Human tackling" in GameplayTuning), steered or not.
func is_human_tackler(d: PlayerAgent) -> bool:
	return d == ctx.controlled and d.team == ctx.human_team and ctx.carrier != d


func _tackles() -> void:
	var c := ctx.carrier
	if c == null or c.is_down or c.dive_timer > 0.0 and c.z_height > 0.3:
		return
	var t := ctx.tuning
	var opponents := ctx.defense if c.team == PlayerAgent.Team.OFFENSE else ctx.offense
	for d in opponents:
		if d.tackle_cd > 0.0 or d.is_down:
			continue
		var diving := d.dive_timer > 0.0
		if not diving and not d.can_act():
			continue
		var human := is_human_tackler(d)
		var dist := d.field_pos.distance_to(c.field_pos)
		if d.engaged_with != null:
			# Blocked: only an arm tackle on a carrier who runs right past him.
			if dist <= t.engaged_tackle_range and _roll(d, c, false, human, t.engaged_tackle_mult):
				return
			continue
		var reach := t.dive_tackle_range if diving else t.tackle_range
		if human:
			reach = t.human_dive_tackle_range if diving else t.human_tackle_range
		if dist > reach:
			# CPU defenders close the last yard with a dive.
			if not diving and not d.human and dist < t.cpu_dive_range:
				d.start_dive(t, c.field_pos + c.velocity * 0.15 - d.field_pos, t.dive_recover)
				stats["dives"] += 1
			continue
		if _roll(d, c, diving, human):
			return


## One tackle attempt by `d` on carrier `c`. Returns true when he brings him down.
func _roll(d: PlayerAgent, c: PlayerAgent, diving: bool, human: bool, mult := 1.0) -> bool:
	var t := ctx.tuning
	var p := RatingModel.tackle_prob(t, d.attr("tak"), c.attr("elu"), c.attr("str"), c.juke_timer > 0.0)
	# Every tackle he already broke this play makes the next one likelier (legs tire, help arrives).
	p += t.broken_tackle_bonus * ctx.broken_tackles
	if diving:
		p += t.dive_tackle_bonus
	var cap := t.tackle_max
	if human:
		p += t.human_tackle_bonus + (t.human_dive_bonus if diving else 0.0)
		p += t.human_assist_bonus * _helpers(d, c)
		cap = t.human_tackle_max
	p = minf(p * mult, cap)
	stats["human_tries" if human else "tries"] += 1
	if diving and not human:
		stats["dive_tries"] += 1
	if ctx.rng.randf() < p:
		stats["human_tackles" if human else "tackles"] += 1
		ctx.on_tackle(d, c)
		return true
	if not diving and d.engaged_with == null:
		d.knock_down(t.human_missed_stun if human else t.missed_tackle_stun)
	d.tackle_cd = t.missed_tackle_cd
	c.velocity *= t.missed_tackle_slow
	ctx.broken_tackles += 1
	return false


## CPU teammates close enough to help wrap up the human's tackle.
func _helpers(d: PlayerAgent, c: PlayerAgent) -> int:
	var n := 0
	for m in ctx.defense if d.team == PlayerAgent.Team.DEFENSE else ctx.offense:
		if m != d and m.can_act() and m.engaged_with == null \
				and m.field_pos.distance_to(c.field_pos) <= ctx.tuning.human_assist_range:
			n += 1
	return n
