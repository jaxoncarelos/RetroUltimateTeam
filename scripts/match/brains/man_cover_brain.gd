class_name ManCoverBrain
extends Brain
## Shadows one receiver. Starts with a cushion over the top, backpedaling (slower) while he
## faces the QB; once the receiver eats up the cushion on a vertical stem he flips his hips
## and trails at the receiver's hip at full speed. That flip is where a fast receiver wins a
## step deep. Reaction lag comes from think().

const CUSHION := 1.2
const TRAIL := 0.3

var mark: PlayerAgent
var aim := Vector2.ZERO
var flipped := false


func _init(p_agent: PlayerAgent, p_ctx: PlayRunner, p_mark: PlayerAgent) -> void:
	super(p_agent, p_ctx)
	mark = p_mark
	if mark != null:
		aim = mark.field_pos + Vector2(CUSHION, 0.0)


func think() -> void:
	if mark == null:
		return
	var t := ctx.tuning
	if not flipped and mark.velocity.x > 2.5 \
			and mark.field_pos.x > agent.field_pos.x - t.flip_distance:
		# Turning the hips costs momentum: this is where the receiver wins his step.
		flipped = true
		agent.velocity *= t.flip_speed_keep
	aim = ctx.anticipate(mark) + Vector2(-TRAIL if flipped else CUSHION, 0.0)
	if not flipped:
		# Keep the cushion: don't charge the receiver; backpedal as he comes at you.
		aim.x = maxf(aim.x, agent.start_pos.x - 1.0)
		if mark.velocity.x > 2.5 and mark.field_pos.x < agent.field_pos.x:
			aim.x = maxf(aim.x, agent.field_pos.x + 2.0)
	# Don't follow a back into the backfield: wait at the second level (where blockers
	# can reach you) until he comes out.
	aim.x = maxf(aim.x, ctx.los_x + ctx.tuning.man_hold_depth)


func act(_dt: float) -> void:
	if mark == null:
		agent.stop()
		return
	var backpedal := not flipped and agent.desired_dir.x > 0.3
	agent.speed_mult = ctx.tuning.backpedal_speed_mult if backpedal else 1.0
	agent.move_to(aim, 1.0, true)


func label() -> String:
	return "man:" + (mark.slot if mark != null else "-") + ("/trail" if flipped else "")
