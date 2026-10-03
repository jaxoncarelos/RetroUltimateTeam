class_name FreeRunBrain
extends Brain
## Road to Glory: a receiver the human took off his route keeps striding the way he was last
## steered when the stick is let go (bending away from the sideline and the end line), so
## letting go never sends him back to the drawn route.

var heading := Vector2.RIGHT


func _init(p_agent: PlayerAgent, p_ctx: PlayRunner, p_heading: Vector2) -> void:
	super(p_agent, p_ctx)
	if p_heading.length() > 0.01:
		heading = p_heading.normalized()


func act(_dt: float) -> void:
	var p := agent.field_pos
	var h := heading
	if p.y < 3.0 and h.y < 0.0 or p.y > FieldGeo.WIDTH - 3.0 and h.y > 0.0:
		h = Vector2(h.x if absf(h.x) > 0.2 else 1.0, 0.0).normalized()
	if p.x > FieldGeo.LENGTH - 2.0 and h.x > 0.0:
		agent.stop()
		return
	agent.desired_dir = h
	agent.throttle = 1.0


func label() -> String:
	return "free"
