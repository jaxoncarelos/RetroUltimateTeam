class_name IdleBrain
extends Brain
## Stands still (e.g. the QB after a handoff).


func act(_dt: float) -> void:
	agent.stop()
