class_name BlockBrain
extends Brain
## mode "pass": protect the QB. "run": drive into nearby defenders. "escort": block for
## the ball carrier. Engagement itself is resolved by ContactResolver.

var mode := "pass"
var target: PlayerAgent = null
var anchor: Vector2


func _init(p_agent: PlayerAgent, p_ctx: PlayRunner, p_mode := "pass") -> void:
	super(p_agent, p_ctx)
	mode = p_mode
	anchor = p_agent.start_pos + (Vector2(-1.5, 0.0) if mode == "pass" else Vector2(1.5, 0.0))


func think() -> void:
	# Run blocks are sticky: keep driving the man you picked until he is free of you and gone.
	if mode == "run" and target != null and not target.is_down and target.engaged_with == null \
			and target.field_pos.distance_to(agent.field_pos) < 9.0:
		return
	target = null
	var best := INF
	var focus := agent.field_pos
	if mode == "escort" and ctx.carrier != null:
		focus = ctx.carrier.field_pos
	var reach := 4.5 if mode == "pass" else (8.0 if mode == "escort" else 7.0)
	for d in ctx.defense:
		if d.is_down or d.engaged_with != null or d.block_cd > 0.0:
			continue
		var dist := d.field_pos.distance_to(agent.field_pos)
		if dist > reach:
			continue
		var score := dist + d.field_pos.distance_to(focus) * 0.5
		if score < best:
			best = score
			target = d


func act(_dt: float) -> void:
	if target != null and not target.is_down and target.engaged_with == null:
		agent.move_to(target.field_pos, 1.0, false)
	elif mode == "escort" and ctx.carrier != null:
		agent.move_to(ctx.carrier.field_pos + Vector2(3.0, 0.0), 0.9, true)
	else:
		agent.move_to(anchor, 0.7, true)


func label() -> String:
	return "block-" + mode
