class_name DefenseSwitcher
extends RefCounted
## Which defender the human controls. There is NO automatic switching during a play: you
## keep the man you picked until you switch yourself (playtest feedback: auto-switching
## yanked control away mid-pursuit).
##   pre-snap  - default = the best-placed linebacker (or your last pick's slot); tap a
##               defender to take him, SWITCH cycles through the second level;
##   live      - SWITCH jumps to the defender nearest the play (landing spot while the ball
##               is in the air, else the one with the quickest intercept on the carrier);
##               tapping any defender still takes him.
## The only forced change is an interception: you run the return with the man who caught it.

var ctx: PlayRunner
## Slot the human last picked pre-snap; reused on the next play when the formation has it.
var preferred_slot := ""


func _init(p_ctx: PlayRunner) -> void:
	ctx = p_ctx


## Human tapped a defender: take him. A pre-snap pick is remembered for later plays.
func manual(d: PlayerAgent) -> void:
	ctx.set_controlled_defender(d)
	if ctx.phase == PlayRunner.Phase.PRE_SNAP and ctx.controlled == d:
		preferred_slot = d.slot


## Pre-snap default: your last pick's slot if the defense has it, else the runner's pick.
func apply_preferred() -> void:
	if preferred_slot != "" and ctx.def_slots.has(preferred_slot):
		ctx.set_controlled_defender(ctx.def_slots[preferred_slot])


## The SWITCH button. Live: the defender nearest the play (never the current man unless
## he is the only choice). Pre-snap: cycles linebackers and safeties front to back.
func switch_to_ball() -> PlayerAgent:
	if ctx.human_team != PlayerAgent.Team.DEFENSE:
		return null
	var cur := ctx.controlled
	if cur != null and cur == ctx.carrier:
		return null   # returning an interception
	var pick: PlayerAgent = null
	if ctx.phase == PlayRunner.Phase.PRE_SNAP:
		pick = _next_presnap(cur)
		if pick != null:
			preferred_slot = pick.slot
	elif ctx.phase == PlayRunner.Phase.LIVE:
		pick = best_defender(cur)
	if pick != null:
		ctx.set_controlled_defender(pick)
	return pick


func _next_presnap(cur: PlayerAgent) -> PlayerAgent:
	var order: Array[PlayerAgent] = []
	for d in ctx.defense:
		if d.pos_code in ["LB", "S"]:
			order.append(d)
	if order.is_empty():
		order = ctx.defense.duplicate()
	order.sort_custom(func(a: PlayerAgent, b: PlayerAgent) -> bool:
		if not is_equal_approx(a.field_pos.x, b.field_pos.x):
			return a.field_pos.x < b.field_pos.x
		return a.field_pos.y < b.field_pos.y)
	var i := order.find(cur)
	return order[(i + 1) % order.size()] if not order.is_empty() else null


## The defender best placed to make a play now, skipping `exclude`.
func best_defender(exclude: PlayerAgent = null) -> PlayerAgent:
	var best: PlayerAgent = null
	var best_s := INF
	for d in ctx.defense:
		if d == exclude:
			continue
		var s := score(d)
		if s < best_s:
			best_s = s
			best = d
	return best


## Lower is better: roughly "seconds until this defender can affect the play".
func score(d: PlayerAgent) -> float:
	var penalty := 0.0
	if d.is_down:
		penalty += 3.0
	if d.engaged_with != null:
		penalty += 1.0
	var spd := maxf(d.max_speed, 1.0)
	if ctx.ball.state == Ball.State.AIR:
		return d.field_pos.distance_to(ctx.ball.to) / spd + penalty
	var c := ctx.carrier
	if c != null and (c != ctx.qb or ctx.scrambling or ctx.is_run_play()):
		# Pursuit: time to an intercept point a little ahead of the carrier.
		var t := d.field_pos.distance_to(c.field_pos) / spd
		var aim := c.field_pos + c.velocity * t * 0.6
		var behind := c.field_pos.x - d.field_pos.x   # >0: the defender trails the play
		if behind > 1.5:
			penalty += 1.0 + behind * 0.15
		return d.field_pos.distance_to(aim) / spd + penalty
	# QB still has it: shadow the receiver he is reading (or the most dangerous one).
	var target := ctx.qb_target_hint
	if target == null:
		var read := QBReadLogic.best_throw(ctx) if ctx.qb != null else {}
		target = read.get("receiver") as PlayerAgent if not read.is_empty() else null
	if target == null:
		return d.field_pos.distance_to(Vector2(ctx.los_x + 5.0, ctx.ball_y)) / spd + penalty
	if d.brain is RushBrain:
		penalty += 3.0   # pre-throw the human covers; rushers rush on their own
	return d.field_pos.distance_to(target.field_pos) / spd + penalty
