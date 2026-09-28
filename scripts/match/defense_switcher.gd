class_name DefenseSwitcher
extends RefCounted
## Picks which defender the human controls (PLAN.md §4 "Auto-control"):
##   pre-throw  - the defender best placed on the receiver the CPU QB is reading;
##   ball in air - the defender who can reach the landing spot soonest;
##   ball carried - the pursuer with the quickest intercept that is not behind the play.
## A manual pick (tap on a defender) holds for `switch_manual_hold` seconds; auto picks
## need to be better by `switch_margin` seconds so control doesn't flicker.

const THINK_INTERVAL := 0.2

var ctx: PlayRunner
var manual_until := -1.0
var _think := 0.0


func _init(p_ctx: PlayRunner) -> void:
	ctx = p_ctx


func reset() -> void:
	manual_until = -1.0
	_think = 0.0


## Human tapped a defender: take him now and hold the choice for a moment.
func manual(d: PlayerAgent) -> void:
	ctx.set_controlled_defender(d)
	manual_until = ctx.play_time + ctx.tuning.switch_manual_hold


## Call every physics frame while the play is live. `force` re-picks immediately
## (throw, catch, handoff) ignoring the flicker margin but not a fresh manual pick.
func update(dt: float, force := false) -> void:
	if ctx.human_team != PlayerAgent.Team.DEFENSE or ctx.phase != PlayRunner.Phase.LIVE:
		return
	var cur := ctx.controlled
	if cur != null and cur == ctx.carrier:
		return   # the human is returning an interception
	if ctx.play_time < manual_until:
		return
	_think -= dt
	if _think > 0.0 and not force:
		return
	# Pre-throw reads change constantly; re-evaluate them less often than pursuit.
	var pre_throw := ctx.ball.state != Ball.State.AIR and ctx.carrier == ctx.qb and not ctx.scrambling \
			and not ctx.is_run_play()
	_think = THINK_INTERVAL * (2.5 if pre_throw else 1.0)
	var best := best_defender()
	if best == null or best == cur:
		return
	if cur != null and not force and cur.can_act():
		if score(cur) - score(best) < ctx.tuning.switch_margin:
			return
	ctx.set_controlled_defender(best)


func best_defender() -> PlayerAgent:
	var best: PlayerAgent = null
	var best_s := INF
	for d in ctx.defense:
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
		penalty += 1.5
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
