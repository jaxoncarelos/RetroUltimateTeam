class_name DrawnPathBrain
extends Brain
## The hero defender's pre-snap drawn path (draw-it-up): runs the points at full speed, then
## hands back to the play's own assignment (rush / coverage). Blockers still engage him on the way.

var points := PackedVector2Array()
var idx := 0
var fallback: Brain


func _init(p_agent: PlayerAgent, p_ctx: PlayRunner, p_points: PackedVector2Array, p_fallback: Brain) -> void:
	super(p_agent, p_ctx)
	points = p_points
	fallback = p_fallback


func think() -> void:
	pass


func act(_dt: float) -> void:
	while idx < points.size() and agent.field_pos.distance_to(points[idx]) < 0.9:
		idx += 1
	if idx >= points.size():
		agent.brain = fallback if fallback != null else IdleBrain.new(agent, ctx)
		return
	agent.speed_mult = 1.0
	agent.move_to(points[idx], 1.0, false)


func label() -> String:
	return "drawn-path"
