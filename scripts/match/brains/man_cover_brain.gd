class_name ManCoverBrain
extends Brain
## Shadows one receiver from a cushion over the top. Reaction lag comes from think().

const CUSHION := 1.2

var mark: PlayerAgent
var aim := Vector2.ZERO


func _init(p_agent: PlayerAgent, p_ctx: PlayRunner, p_mark: PlayerAgent) -> void:
	super(p_agent, p_ctx)
	mark = p_mark
	if mark != null:
		aim = mark.field_pos + Vector2(CUSHION, 0.0)


func think() -> void:
	if mark != null:
		aim = mark.field_pos + mark.velocity * 0.3 + Vector2(CUSHION, 0.0)


func act(_dt: float) -> void:
	if mark == null:
		agent.stop()
	else:
		agent.move_to(aim, 1.0, true)


func label() -> String:
	return "man:" + (mark.slot if mark != null else "-")
