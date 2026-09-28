class_name CameraRig
extends Camera2D
## Follows the play with look-ahead toward the offense's direction; clamped to the field.

const LOOK_AHEAD_PX := 70.0
const FOLLOW_RATE := 5.0

var runner: PlayRunner
## Debug: when set (field yards), the camera stays on this point (--look=X,Y).
var pinned := Vector2(-1, -1)


func _ready() -> void:
	var r := FieldProjection.world_rect()
	limit_left = int(r.position.x)
	limit_top = int(r.position.y)
	limit_right = int(r.end.x)
	limit_bottom = int(r.end.y)


func target_position() -> Vector2:
	if pinned.x >= 0.0:
		return FieldProjection.to_screen(pinned)
	if runner == null:
		return global_position
	return FieldProjection.to_screen(runner.focus_point()) + Vector2(LOOK_AHEAD_PX, 0.0)


func snap_to_target() -> void:
	global_position = target_position()
	reset_smoothing()


func _process(delta: float) -> void:
	global_position = global_position.lerp(target_position(), 1.0 - exp(-FOLLOW_RATE * delta))
