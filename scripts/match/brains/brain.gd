class_name Brain
extends RefCounted
## Base AI behavior. update() runs every physics frame; think() re-plans at the agent's
## reaction interval (awareness rating) so low-awareness players react late.

var agent: PlayerAgent
var ctx: PlayRunner
var _think_timer := 0.0


func _init(p_agent: PlayerAgent, p_ctx: PlayRunner) -> void:
	agent = p_agent
	ctx = p_ctx


func update(dt: float) -> void:
	_think_timer -= dt
	if _think_timer <= 0.0:
		_think_timer = agent.reaction
		think()
	act(dt)


func think() -> void:
	pass


func act(_dt: float) -> void:
	pass


func label() -> String:
	return "idle"
