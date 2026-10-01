class_name BlockBrain
extends Brain
## mode "pass": protect the QB from a pocket - a cup around him (guards in front, tackles wide
## and deeper, a blocking TE/RB on the edge), each blocker sliding to stay between the QB and
## the rusher PlayRunner.pocket_assignments() gives him. "run": drive into nearby defenders.
## "escort": block for the ball carrier. Engagement itself is resolved by ContactResolver.

## Pocket spot of each blocking slot around the QB: angle (degrees from straight upfield,
## negative = top sideline side) and distance (yards). RB picks the side he lines up on.
const POCKET := {"OL2": [-22.0, 2.4], "OL3": [22.0, 2.4], "OL1": [-62.0, 3.0], "OL4": [62.0, 3.0],
		"TE": [95.0, 3.2], "RB": [100.0, 2.2]}

var mode := "pass"
var target: PlayerAgent = null
var anchor: Vector2


func _init(p_agent: PlayerAgent, p_ctx: PlayRunner, p_mode := "pass") -> void:
	super(p_agent, p_ctx)
	mode = p_mode
	anchor = p_agent.start_pos + (Vector2(-1.5, 0.0) if mode == "pass" else Vector2(1.5, 0.0))


## This blocker's spot in the cup around the QB (null = no pocket spot: block the nearest man).
func pocket_spot() -> Variant:
	if not POCKET.has(agent.slot) or ctx.qb == null:
		return null
	var a: float = POCKET[agent.slot][0]
	if agent.slot == "RB" and agent.start_pos.y < ctx.qb.start_pos.y:
		a = -a
	return ctx.qb.field_pos + Vector2.from_angle(deg_to_rad(a)) * float(POCKET[agent.slot][1])


## Pass pro while the QB holds the ball in the pocket.
func _pocket_active() -> bool:
	return mode == "pass" and ctx.qb != null and ctx.carrier == ctx.qb and not ctx.pass_thrown \
			and not ctx.scrambling and pocket_spot() != null


func think() -> void:
	if _pocket_active():
		target = ctx.pocket_assignments().get(agent, null)
		return
	# Run blocks are sticky: keep driving the man you picked until he is free of you and gone.
	if mode == "run" and target != null and not target.is_down and target.engaged_with == null \
			and target.field_pos.distance_to(agent.field_pos) < 9.0:
		return
	target = null
	var best := INF
	var focus := agent.field_pos
	if mode == "escort" and ctx.carrier != null:
		focus = ctx.carrier.field_pos
	var reach := 4.5 if mode == "pass" else (8.0 if mode == "escort" else 7.0)
	var opponents := ctx.defense if agent.team == PlayerAgent.Team.OFFENSE else ctx.offense
	for d in opponents:
		if d.is_down or d.engaged_with != null or d.block_cd > 0.0:
			continue
		var dist := d.field_pos.distance_to(agent.field_pos)
		if dist > reach:
			continue
		var score := dist + d.field_pos.distance_to(focus) * 0.5
		if score < best:
			best = score
			target = d


func act(_dt: float) -> void:
	if _pocket_active():
		var spot: Vector2 = pocket_spot()
		if target != null and not target.is_down and target.engaged_with == null:
			# Mirror him: stay on the line between the rusher and the QB, at the cup's edge.
			var qb := ctx.qb.field_pos
			var to := target.field_pos - qb
			var r := minf(qb.distance_to(spot), maxf(to.length() - 0.6, 0.8))
			agent.move_to(qb + to.normalized() * r, 1.0, false)
		else:
			agent.move_to(spot, 0.8, true)
		return
	if target != null and not target.is_down and target.engaged_with == null:
		agent.move_to(target.field_pos, 1.0, false)
	elif mode == "escort" and ctx.carrier != null:
		var fwd := 1.0 if ctx.carrier.team == PlayerAgent.Team.OFFENSE else -1.0
		agent.move_to(ctx.carrier.field_pos + Vector2(3.0 * fwd, 0.0), 0.9, true)
	else:
		agent.move_to(anchor, 0.7, true)


func label() -> String:
	return "block-" + mode
