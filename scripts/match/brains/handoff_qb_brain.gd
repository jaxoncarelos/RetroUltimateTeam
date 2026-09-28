class_name HandoffQBBrain
extends Brain
## Moves to the mesh point and waits for the runner.

var mesh: Vector2


func _init(p_agent: PlayerAgent, p_ctx: PlayRunner, p_mesh: Vector2) -> void:
	super(p_agent, p_ctx)
	mesh = p_mesh


func act(_dt: float) -> void:
	agent.move_to(mesh, 0.9, true)


func label() -> String:
	return "handoff"
