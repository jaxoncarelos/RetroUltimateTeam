class_name TouchInput
extends Node
## Turns raw touches into gestures (viewport pixel coordinates). Tracks one finger.
## Mouse works too via "emulate touch from mouse".

signal pressed(pos: Vector2)
signal drag_started(start: Vector2, pos: Vector2)
signal dragged(start: Vector2, pos: Vector2)
signal released(start: Vector2, pos: Vector2, was_drag: bool)
signal tapped(pos: Vector2)
signal double_tapped(pos: Vector2)
signal flicked(dir: Vector2)

const DRAG_THRESHOLD := 8.0
const TAP_TIME := 0.25
const DOUBLE_TAP_TIME := 0.32
const DOUBLE_TAP_DIST := 28.0
const FLICK_COOLDOWN := 0.25

## Returns true when a screen point is over UI that should swallow the touch.
var ui_blocker: Callable
var flick_speed := 450.0

var _index := -1
var _start := Vector2.ZERO
var _start_t := 0.0
var _last := Vector2.ZERO
var _last_t := 0.0
var _dragging := false
var _last_tap_t := -10.0
var _last_tap_pos := Vector2.ZERO
var _last_flick_t := -10.0


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func is_touching() -> bool:
	return _index != -1


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			if _index != -1:
				return
			if ui_blocker.is_valid() and ui_blocker.call(e.position):
				return
			_index = e.index
			_start = e.position
			_last = e.position
			_start_t = _now()
			_last_t = _start_t
			_dragging = false
			pressed.emit(e.position)
		elif e.index == _index:
			var now := _now()
			if not _dragging and now - _start_t < TAP_TIME:
				if now - _last_tap_t < DOUBLE_TAP_TIME and e.position.distance_to(_last_tap_pos) < DOUBLE_TAP_DIST:
					double_tapped.emit(e.position)
					_last_tap_t = -10.0
				else:
					tapped.emit(e.position)
					_last_tap_t = now
					_last_tap_pos = e.position
			released.emit(_start, e.position, _dragging)
			_index = -1
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index != _index:
			return
		var now := _now()
		if not _dragging and d.position.distance_to(_start) >= DRAG_THRESHOLD:
			_dragging = true
			drag_started.emit(_start, d.position)
		if _dragging:
			dragged.emit(_start, d.position)
		var dt := maxf(now - _last_t, 0.001)
		var v := (d.position - _last) / dt
		if absf(v.y) > flick_speed and absf(v.y) > absf(v.x) * 1.2 and now - _last_flick_t > FLICK_COOLDOWN:
			_last_flick_t = now
			flicked.emit(Vector2(0.0, signf(v.y)))
		_last = d.position
		_last_t = now
