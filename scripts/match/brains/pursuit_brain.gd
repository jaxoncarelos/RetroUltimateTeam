class_name PursuitBrain
extends Brain
## Chases the ball carrier on a real intercept angle (solves where they meet, not just where
## he is) and keeps leverage: a defender outside the carrier takes his outside shoulder
## (contain: force him back inside to the help), one inside him takes the inside shoulder
## (no cutback), one behind him just runs him down. That spreads the pursuit instead of every
## defender aiming at the same spot.

const LEVERAGE := 0.9   ## yards of shoulder shade

var aim := Vector2.ZERO


func _init(p_agent: PlayerAgent, p_ctx: PlayRunner) -> void:
	super(p_agent, p_ctx)
	agent.speed_mult = maxf(agent.speed_mult, ctx.tuning.pursuit_speed_mult)


func think() -> void:
	var c := ctx.carrier
	if c == null or c.team == agent.team:
		aim = Vector2.ZERO
		return
	var spd := maxf(agent.max_speed * agent.speed_mult, 1.0)
	var p := c.field_pos
	var tt := agent.field_pos.distance_to(p) / spd
	for i in 3:
		p = c.field_pos + c.velocity * tt * 0.85
		tt = agent.field_pos.distance_to(p) / spd
	var fwd := signf(c.velocity.x) if absf(c.velocity.x) > 0.5 else (1.0 if c.team == PlayerAgent.Team.OFFENSE else -1.0)
	var ahead := (agent.field_pos.x - c.field_pos.x) * fwd > -1.0   # not trailing the play
	if ahead:
		# Which side of him am I on (toward the nearer sideline = outside)?
		var outside_dir := -1.0 if c.field_pos.y < FieldGeo.CENTER_Y else 1.0
		var my_side := signf(agent.field_pos.y - c.field_pos.y)
		if my_side == 0.0:
			my_side = outside_dir
		p.y += my_side * LEVERAGE
	p.y = clampf(p.y, 0.5, FieldGeo.WIDTH - 0.5)
	aim = p


func act(_dt: float) -> void:
	if aim == Vector2.ZERO:
		agent.stop()
	else:
		agent.move_to(aim, 1.0, false)


func label() -> String:
	return "pursuit"
