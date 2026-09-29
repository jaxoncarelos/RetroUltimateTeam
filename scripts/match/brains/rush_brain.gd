class_name RushBrain
extends Brain
## Pass rusher: attacks the QB, or the ball carrier once someone else has the ball. On a
## play-action fake he holds `hold` seconds reading the run first.

var aim := Vector2.ZERO
var hold := 0.0


func think() -> void:
	var tgt := ctx.carrier if ctx.carrier != null else ctx.qb
	if tgt == null or tgt.team == agent.team:
		aim = Vector2.ZERO
		return
	var t := clampf(agent.field_pos.distance_to(tgt.field_pos) / agent.max_speed, 0.0, 0.8)
	aim = tgt.field_pos + tgt.velocity * t


func act(dt: float) -> void:
	if hold > 0.0:
		hold -= dt
		agent.stop()
		return
	if aim == Vector2.ZERO:
		agent.stop()
	else:
		agent.move_to(aim, 1.0, false)


func label() -> String:
	return "rush"
