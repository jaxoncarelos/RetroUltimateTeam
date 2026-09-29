class_name ReplayPlayer
extends RefCounted
## Plays back the frames PlayRunner recorded (`record_replay`): every agent's position, motion
## and pose flags plus the ball, interpolated at a slower speed. The agents are the play's own
## nodes, so the sprites, ring markers and animations are exactly what happened.
## step() returns true when the replay is over (the last frame is left on screen).

var runner: PlayRunner
var frames: Array[PackedFloat32Array] = []
var speed := 0.6           ## recorded frames per real frame (0.6 = slow-mo)
var cursor := 0.0
## Where the camera should look this frame (field yards): the ball.
var focus := Vector2.ZERO


func _init(p_runner: PlayRunner, from_frame := 0, p_speed := 0.6) -> void:
	runner = p_runner
	frames = runner.replay_frames
	cursor = float(clampi(from_frame, 0, maxi(frames.size() - 1, 0)))
	speed = p_speed
	if not frames.is_empty():
		_apply(frames[int(cursor)], frames[int(cursor)], 0.0)


func frame_count() -> int:
	return frames.size()


func step(dt: float) -> bool:
	if frames.size() < 2:
		return true
	cursor += dt * 60.0 * speed
	var i := int(cursor)
	if i >= frames.size() - 1:
		_apply(frames[frames.size() - 1], frames[frames.size() - 1], 0.0)
		return true
	_apply(frames[i], frames[i + 1], cursor - float(i))
	return false


func _apply(a: PackedFloat32Array, b: PackedFloat32Array, k: float) -> void:
	var stride := PlayRunner.REPLAY_STRIDE
	var idx := 0
	for ag in runner.agents:
		ag.field_pos = Vector2(lerpf(a[idx], b[idx], k), lerpf(a[idx + 1], b[idx + 1], k))
		ag.velocity = Vector2(lerpf(a[idx + 2], b[idx + 2], k), lerpf(a[idx + 3], b[idx + 3], k))
		ag.z_height = lerpf(a[idx + 4], b[idx + 4], k)
		ag.facing = a[idx + 5]
		var flags := int(a[idx + 6])
		ag.is_down = flags & 1 != 0
		ag.dive_timer = 0.2 if flags & 2 != 0 else 0.0
		ag.jump_timer = 0.2 if flags & 4 != 0 else 0.0
		ag.engaged_with = ag if flags & 8 != 0 else null
		ag.celebrating = flags & 16 != 0
		ag.throw_anim = 0.2 if flags & 32 != 0 else 0.0
		ag.stun = 0.5 if flags & 64 != 0 else 0.0
		idx += stride
	var ball := runner.ball
	ball.field_pos = Vector2(lerpf(a[idx], b[idx], k), lerpf(a[idx + 1], b[idx + 1], k))
	ball.z = lerpf(a[idx + 2], b[idx + 2], k)
	ball.state = int(a[idx + 3])
	focus = ball.field_pos
