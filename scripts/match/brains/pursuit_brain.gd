class_name PursuitBrain
extends Brain
## Takes an intercept angle on the ball carrier.

var aim := Vector2.ZERO


func think() -> void:
	var c := ctx.carrier
	if c == null or c.team == agent.team:
		aim = Vector2.ZERO
		return
	var t := agent.field_pos.distance_to(c.field_pos) / maxf(agent.max_speed, 1.0)
	aim = c.field_pos + c.velocity * t * 0.75


func act(_dt: float) -> void:
	if aim == Vector2.ZERO:
		agent.stop()
	else:
		agent.move_to(aim, 1.0, false)


func label() -> String:
	return "pursuit"
