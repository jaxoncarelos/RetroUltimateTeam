class_name RunnerBrain
extends Brain
## CPU ball carrier: follows the play's designed lane (carry path) first, sliding off it
## when a defender fills it, then samples lanes ahead and takes the one with the most space.

var aim := Vector2.ZERO
var lane := PackedVector2Array()
var lane_idx := 0


func _init(p_agent: PlayerAgent, p_ctx: PlayRunner, p_lane := PackedVector2Array()) -> void:
	super(p_agent, p_ctx)
	lane = p_lane


func think() -> void:
	var opponents := ctx.defense if agent.team == PlayerAgent.Team.OFFENSE else ctx.offense
	var fwd := 1.0 if agent.team == PlayerAgent.Team.OFFENSE else -1.0
	while lane_idx < lane.size() and agent.field_pos.distance_to(lane[lane_idx]) < 1.3:
		lane_idx += 1
	var base_dir := Vector2(fwd, 0.0)
	var on_lane := lane_idx < lane.size()
	if on_lane:
		base_dir = (lane[lane_idx] - agent.field_pos).normalized()
	var best_score := -INF
	for lat: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		var dir := (base_dir + base_dir.orthogonal() * lat).normalized()
		var probe := agent.field_pos + dir * 4.0
		if probe.y < 1.0 or probe.y > FieldGeo.WIDTH - 1.0:
			continue
		var space := 99.0
		for d in opponents:
			if not d.is_down and d.engaged_with == null:
				space = minf(space, d.field_pos.distance_to(probe))
		# Stick to the designed lane unless it is clearly filled; keep the current heading
		# (hysteresis) so the runner doesn't wobble between equal lanes.
		var score := minf(space, 8.0) - absf(lat) * (2.0 if on_lane else 0.8)
		if aim != Vector2.ZERO and (aim - agent.field_pos).normalized().dot(dir) > 0.95:
			score += 0.8
		if score > best_score:
			best_score = score
			aim = probe


func act(_dt: float) -> void:
	if aim != Vector2.ZERO:
		agent.move_to(aim, 1.0, false)


func label() -> String:
	return "run"
