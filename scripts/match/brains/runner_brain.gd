class_name RunnerBrain
extends Brain
## CPU ball carrier: samples a few lanes ahead and takes the one with the most space.

var aim := Vector2.ZERO


func think() -> void:
	var best_score := -INF
	var opponents := ctx.defense if agent.team == PlayerAgent.Team.OFFENSE else ctx.offense
	var fwd := 1.0 if agent.team == PlayerAgent.Team.OFFENSE else -1.0
	for lat in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		var dir := Vector2(fwd, lat).normalized()
		var probe := agent.field_pos + dir * 4.0
		if probe.y < 1.0 or probe.y > FieldGeo.WIDTH - 1.0:
			continue
		var space := 99.0
		for d in opponents:
			if not d.is_down:
				space = minf(space, d.field_pos.distance_to(probe))
		var score := space - absf(lat) * 0.8
		if score > best_score:
			best_score = score
			aim = probe


func act(_dt: float) -> void:
	if aim != Vector2.ZERO:
		agent.move_to(aim, 1.0, false)


func label() -> String:
	return "run"
