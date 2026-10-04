class_name RunnerBrain
extends Brain
## CPU ball carrier: follows the play's designed lane (carry path) first, sliding off it
## when a defender fills it, then reads the field: it fans candidate directions around the
## lane (or straight ahead), probes each at two depths for the nearest free defender, and
## takes the one with the best mix of space and forward progress. Cutbacks happen when the
## backside is the open side. Engaged defenders still count a little (they can shed).

const FAN: Array[float] = [-1.3, -0.85, -0.45, 0.0, 0.45, 0.85, 1.3]

var aim := Vector2.ZERO
var lane := PackedVector2Array()
var lane_idx := 0


func _init(p_agent: PlayerAgent, p_ctx: PlayRunner, p_lane := PackedVector2Array()) -> void:
	super(p_agent, p_ctx)
	lane = p_lane


func think() -> void:
	var t := ctx.tuning
	var opponents := ctx.defense if agent.team == PlayerAgent.Team.OFFENSE else ctx.offense
	var fwd := 1.0 if agent.team == PlayerAgent.Team.OFFENSE else -1.0
	# Drop lane points already reached or already behind him (never double back to one).
	while lane_idx < lane.size() and (agent.field_pos.distance_to(lane[lane_idx]) < 1.3
			or (lane[lane_idx].x - agent.field_pos.x) * fwd < -0.3):
		lane_idx += 1
	var base_dir := Vector2(fwd, 0.0)
	var on_lane := lane_idx < lane.size()
	if on_lane:
		base_dir = (lane[lane_idx] - agent.field_pos).normalized()
	var best_score := -INF
	for lat: float in FAN:
		var dir := base_dir.rotated(lat * 0.6)
		if dir.x * fwd < -0.2:
			continue
		var near := agent.field_pos + dir * t.run_probe_near
		var far := agent.field_pos + dir * t.run_probe_far
		if far.y < 1.0 or far.y > FieldGeo.WIDTH - 1.0:
			continue
		var space := 99.0
		for d in opponents:
			if d.is_down:
				continue
			var slack := t.run_engaged_slack if d.engaged_with != null else 0.0
			if d.engaged_with == null and _shielded(d, near):
				slack += t.run_shield_slack   # a blocker stands between him and that lane
			space = minf(space, minf(d.field_pos.distance_to(near), d.field_pos.distance_to(far) + 1.0) + slack)
		# Stick to the designed lane unless it is clearly filled; keep the current heading
		# (hysteresis) so the runner doesn't wobble between equal lanes.
		var score := minf(space, 8.0) + dir.x * fwd * t.run_progress_weight \
				- absf(lat) * (t.run_lane_stick if on_lane else 0.5)
		if aim != Vector2.ZERO and (aim - agent.field_pos).normalized().dot(dir) > 0.95:
			score += 0.8
		if score > best_score:
			best_score = score
			aim = agent.field_pos + dir * 4.0


## True when one of the carrier's blockers stands between defender `d` and the point `p`
## (he will have to get past him: run off the blocker's hip).
func _shielded(d: PlayerAgent, p: Vector2) -> bool:
	var mates := ctx.offense if agent.team == PlayerAgent.Team.OFFENSE else ctx.defense
	for m in mates:
		if m == agent or m.is_down or not (m.brain is BlockBrain):
			continue
		if PassModel.seg_dist(m.field_pos, d.field_pos, p) < 1.2 and m.field_pos.distance_to(d.field_pos) < 4.0:
			return true
	return false


func act(_dt: float) -> void:
	if aim != Vector2.ZERO:
		agent.move_to(aim, 1.0, false)


func label() -> String:
	return "run"
