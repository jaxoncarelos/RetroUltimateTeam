class_name ManCoverBrain
extends Brain
## Shadows one receiver like a real corner (docs/AI_OVERHAUL_PLAN.md §2):
##  - Cushion over the top, backpedaling (slower) while the receiver comes at him; when the
##    receiver eats the cushion on a vertical stem he flips his hips (losing momentum: where a
##    fast receiver wins a step deep) and runs on his hip.
##  - He mirrors: steers to match the receiver's velocity plus a correction toward his spot
##    (inside leverage: between the receiver and the middle / the ball), instead of running to a
##    point and slowing down there.
##  - A sharp break (the receiver's direction changes) costs him a moment to read it — less the
##    better his coverage is than the receiver's route running; that, and the hip flip, is where
##    separation comes from.

const CUSHION := 1.2
const TRAIL := 0.3
const LEVERAGE := 0.7       ## yards of inside shade
const MIRROR_GAIN := 1.8    ## correction per yard of error (1/s)

var mark: PlayerAgent
var aim := Vector2.ZERO
var flipped := false
var _last_dir := Vector2.ZERO
var _beat := 0.0            ## seconds he is still reacting to a break (keeps his old line)


func _init(p_agent: PlayerAgent, p_ctx: PlayRunner, p_mark: PlayerAgent) -> void:
	super(p_agent, p_ctx)
	mark = p_mark
	if mark != null:
		aim = mark.field_pos + Vector2(CUSHION, 0.0)


func think() -> void:
	if mark == null:
		return
	var t := ctx.tuning
	if not flipped and mark.velocity.x > 2.5 \
			and mark.field_pos.x > agent.field_pos.x - t.flip_distance:
		# Turning the hips costs momentum: this is where the receiver wins his step.
		flipped = true
		agent.velocity *= t.flip_speed_keep
	# A break: the receiver's direction changed sharply since the last look.
	var dir := mark.velocity.normalized() if mark.velocity.length() > 1.5 else Vector2.ZERO
	if _last_dir != Vector2.ZERO and dir != Vector2.ZERO and _last_dir.dot(dir) < 0.75:
		_beat = clampf(0.22 + (mark.attr("rte") - agent.attr("cov")) * 0.006, 0.05, 0.45)
	_last_dir = dir
	var inside := signf(ctx.ball_y - mark.field_pos.y)
	if inside == 0.0:
		inside = 1.0
	var db := agent.pos_code in ["CB", "S"] and mark.pos_code == "WR"
	if not db:
		# A linebacker on a back or a tight end: no cushion, just stay on him, a step inside.
		aim = ctx.anticipate(mark) + Vector2(-TRAIL, inside * LEVERAGE * 0.6)
	else:
		# Trailing a vertical he rides the receiver's hip (barely inside); in off coverage he shades inside.
		aim = ctx.anticipate(mark) + Vector2(-trail_gap() if flipped else CUSHION, inside * LEVERAGE * (0.25 if flipped else 1.0))
	if not flipped and db:
		# Keep the cushion: don't charge the receiver; backpedal as he comes at you.
		aim.x = maxf(aim.x, agent.start_pos.x - 1.0)
		if mark.velocity.x > 2.5 and mark.field_pos.x < agent.field_pos.x:
			aim.x = maxf(aim.x, agent.field_pos.x + 2.0)
	# Don't follow a back into the backfield: wait at the second level (where blockers can
	# reach you) while he is behind the line inside the box; once he releases, go get him.
	var in_box := mark.field_pos.x < ctx.los_x - 0.5 and absf(mark.field_pos.y - ctx.ball_y) < 6.0
	if in_box:
		aim.x = maxf(aim.x, ctx.los_x + ctx.tuning.man_hold_depth)
	else:
		aim.x = maxf(aim.x, ctx.los_x + 0.5)


## How far behind his man he trails on a vertical: a faster, better route runner stays a step
## ahead; a better, faster corner rides his hip.
func trail_gap() -> float:
	var edge := (mark.attr("spd") - agent.attr("spd")) * 0.05 + (mark.attr("rte") - agent.attr("cov")) * 0.012
	return clampf(0.8 + edge, TRAIL, 2.0)


func update(dt: float) -> void:
	_beat = maxf(0.0, _beat - dt)
	super(dt)


func act(_dt: float) -> void:
	if mark == null:
		agent.stop()
		return
	var backpedal := not flipped and agent.desired_dir.x > 0.3
	agent.speed_mult = ctx.tuning.backpedal_speed_mult if backpedal else 1.0
	if _beat > 0.0:
		return   # still reading the break: he keeps going the way he was
	if not flipped and agent.pos_code in ["CB", "S"] and mark.pos_code == "WR":
		# Off coverage before the hip flip: backpedal to the cushion spot (the receiver eats it up).
		agent.move_to(aim, 1.0, true)
		return
	# Mirror: his velocity plus a pull toward his spot.
	var want := mark.velocity + (aim - agent.field_pos) * MIRROR_GAIN
	if want.length() < 0.2:
		agent.stop()
		return
	agent.desired_dir = want.normalized()
	agent.throttle = clampf(want.length() / maxf(agent.max_speed * agent.speed_mult, 0.1), 0.0, 1.0)


func label() -> String:
	return "man:" + (mark.slot if mark != null else "-") + ("/trail" if flipped else "")
