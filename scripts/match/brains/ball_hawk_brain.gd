class_name BallHawkBrain
extends Brain
## Breaks on a thrown ball after a reaction delay; runs the previous brain until then.

var point: Vector2
var delay := 0.0
var previous: Brain


func _init(p_agent: PlayerAgent, p_ctx: PlayRunner, p_point: Vector2, p_delay: float, p_prev: Brain) -> void:
	super(p_agent, p_ctx)
	point = p_point
	delay = p_delay
	previous = p_prev


func update(dt: float) -> void:
	if delay > 0.0:
		delay -= dt
		if previous != null:
			previous.update(dt)
		return
	agent.move_to(point, 1.0, true)


func label() -> String:
	return "ball"
