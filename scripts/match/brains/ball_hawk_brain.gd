class_name BallHawkBrain
extends Brain
## Breaks on a thrown ball after a delay (running the previous brain until then).
## Defenders sprint to the landing spot. The intended receiver (`track`) times his run so
## he reaches the spot as the ball comes down: he speeds up for a ball thrown ahead of him
## and eases off for one that hangs, instead of arriving early and stopping.

var point: Vector2
var delay := 0.0
var previous: Brain
var track := false


func _init(p_agent: PlayerAgent, p_ctx: PlayRunner, p_point: Vector2, p_delay: float, p_prev: Brain,
		p_track := false) -> void:
	super(p_agent, p_ctx)
	point = p_point
	delay = p_delay
	previous = p_prev
	track = p_track


func update(dt: float) -> void:
	if delay > 0.0:
		delay -= dt
		if previous != null:
			previous.update(dt)
		return
	if not track:
		agent.speed_mult = maxf(agent.speed_mult, 1.0)   # done backpedaling: turn and run
		agent.move_to(point, 1.0, true)
		return
	var to := point - agent.field_pos
	var dist := to.length()
	if dist < 0.15:
		agent.stop()
		return
	var left := ctx.ball.time_left() - 0.08
	var top := maxf(agent.max_speed * agent.speed_mult, 0.1)
	var needed := dist / maxf(left, 0.05)
	agent.desired_dir = to / dist
	agent.throttle = clampf(needed / top, 0.45, 1.0) if left > 0.0 else 1.0


func label() -> String:
	return "track" if track else "ball"
