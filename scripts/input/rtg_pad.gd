class_name RtgPad
extends Control
## Road to Glory on-screen controls: a floating joystick on the left (it appears where the
## thumb lands and follows it past its rim) and up to five round context buttons on the
## right (labels, cooldown rings, a glow on the one that matters now). Every finger is
## tracked by its touch index, so you can run and press buttons at the same time.
## `Settings.left_handed` mirrors the layout. Touches it uses are marked handled so the
## classic gesture input (TouchInput) never sees them; touches over HUD UI are left alone.
## RtgControl reads `stick` and fills `buttons` every frame.

signal button_pressed(id: String)
signal button_released(id: String)

## Share of the screen width (from the stick side) where a touch grabs the joystick.
const STICK_ZONE := 0.46
## Button centers relative to the bottom-right corner (mirrored when left handed) and radii.
const SLOTS := [Vector2(-38, -46), Vector2(-86, -32), Vector2(-80, -80), Vector2(-36, -96), Vector2(-128, -60)]
const RADII := [20.0, 15.0, 15.0, 15.0, 14.0]
const TOP_GUARD := 34.0      ## the scoreboard / pause strip never grabs the stick

## Returns true for a screen point over HUD UI (the touch is left to the GUI).
var blocker: Callable
var left_handed := false
## Joystick allowed (off e.g. pre-snap for a receiver).
var stick_enabled := true
## Screen-space stick: direction × strength 0..1 (y down).
var stick := Vector2.ZERO
## [{id, label, cd: 0..1 still cooling, hot: bool, on: bool (held)}], max 5, set every frame.
var buttons: Array = []
var radius := 34.0
var dead := 0.14
## Dim hint of where the stick lives (shown until the first touch of a play).
var show_hint := true

var _stick_idx := -1
var _base := Vector2.ZERO
var _knob := Vector2.ZERO
var _btn_touch := {}         ## touch index -> button id
var _flash := {}             ## button id -> seconds of press flash left
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_stick_active() -> bool:
	return _stick_idx != -1


## Drops every touch (between plays) so nothing stays held.
func reset() -> void:
	_stick_idx = -1
	stick = Vector2.ZERO
	for idx in _btn_touch:
		button_released.emit(_btn_touch[idx])
	_btn_touch.clear()


func slot_center(i: int) -> Vector2:
	var o: Vector2 = SLOTS[i]
	return Vector2(o.x + size.x, o.y + size.y) if not left_handed else Vector2(-o.x, o.y + size.y)


func button_at(p: Vector2) -> String:
	for i in mini(buttons.size(), SLOTS.size()):
		if p.distance_to(slot_center(i)) <= RADII[i] + 6.0:
			return str(buttons[i]["id"])
	return ""


func _in_stick_zone(p: Vector2) -> bool:
	if p.y < TOP_GUARD:
		return false
	return p.x > size.x * (1.0 - STICK_ZONE) if left_handed else p.x < size.x * STICK_ZONE


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			if blocker.is_valid() and blocker.call(e.position):
				return
			var id := button_at(e.position)
			if id != "":
				_btn_touch[e.index] = id
				_flash[id] = 0.18
				button_pressed.emit(id)
				_handled()
				return
			if stick_enabled and _stick_idx == -1 and _in_stick_zone(e.position):
				_stick_idx = e.index
				_base = e.position
				_knob = e.position
				stick = Vector2.ZERO
				show_hint = false
				_handled()
		else:
			if e.index == _stick_idx:
				_stick_idx = -1
				stick = Vector2.ZERO
				_handled()
			elif _btn_touch.has(e.index):
				button_released.emit(_btn_touch[e.index])
				_btn_touch.erase(e.index)
				_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index != _stick_idx:
			if _btn_touch.has(d.index):
				_handled()
			return
		var off := d.position - _base
		if off.length() > radius:
			_base = d.position - off.normalized() * radius   # the base follows a thumb past the rim
			off = d.position - _base
		_knob = d.position
		var mag := off.length() / radius
		stick = Vector2.ZERO if mag < dead else off.normalized() * clampf((mag - dead) / (1.0 - dead), 0.0, 1.0)
		_handled()


func _handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_t += delta
	for k in _flash.keys():
		_flash[k] = float(_flash[k]) - delta
		if float(_flash[k]) <= 0.0:
			_flash.erase(k)
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	_draw_stick()
	for i in mini(buttons.size(), SLOTS.size()):
		_draw_button(i, buttons[i])


func _draw_stick() -> void:
	if _stick_idx != -1:
		draw_circle(_base, radius + 2.0, Color(0, 0, 0, 0.25))
		draw_arc(_base, radius, 0.0, TAU, 40, Color(1, 1, 1, 0.55), 2.0)
		var k := _base + (_knob - _base).limit_length(radius)
		draw_circle(k, 11.0, Color(UiSkin.YELLOW, 0.85))
		draw_arc(k, 11.0, 0.0, TAU, 24, UiSkin.NAVY_DEEP, 1.5)
		return
	if not stick_enabled:
		return
	# Idle: a ghost stick where the thumb usually rests.
	var c := Vector2(size.x - 70.0 if left_handed else 70.0, size.y - 64.0)
	var a := 0.22 if not show_hint else 0.3 + 0.12 * sin(_t * 3.0)
	draw_arc(c, radius, 0.0, TAU, 40, Color(1, 1, 1, a), 2.0)
	draw_circle(c, 9.0, Color(1, 1, 1, a * 0.8))
	if show_hint:
		UiSkin.draw_text_c(self, c.x, c.y + radius + 12.0, "MOVE", 8, Color(1, 1, 1, 0.7), Color(0, 0, 0, 0))


func _draw_button(i: int, b: Dictionary) -> void:
	var c := slot_center(i)
	var r: float = RADII[i]
	var cd := clampf(float(b.get("cd", 0.0)), 0.0, 1.0)
	var hot: bool = b.get("hot", false)
	var held: bool = b.get("on", false) or _btn_touch.values().has(b["id"])
	var ready := cd <= 0.0
	var fill := Color(UiSkin.NAVY_DEEP, 0.72)
	if hot and ready:
		fill = Color(UiSkin.YELLOW, 0.35 + 0.25 * (0.5 + 0.5 * sin(_t * 9.0)))
	if held or _flash.has(b["id"]):
		fill = Color(UiSkin.YELLOW, 0.85)
	draw_circle(c + Vector2(0, 2), r, Color(0, 0, 0, 0.35))
	draw_circle(c, r, fill)
	var rim := UiSkin.YELLOW if ready else Color(1, 1, 1, 0.35)
	draw_arc(c, r, 0.0, TAU, 32, rim, 2.0)
	if not ready:
		# Cooldown: the ring fills back in clockwise.
		draw_arc(c, r - 3.0, -PI / 2.0, -PI / 2.0 + TAU * (1.0 - cd), 32, Color(UiSkin.YELLOW, 0.8), 2.0)
	var col := UiSkin.NAVY_DEEP if (held or _flash.has(b["id"])) else (Color.WHITE if ready else Color(1, 1, 1, 0.5))
	UiSkin.draw_text_c(self, c.x, c.y + 4.0, str(b["label"]), 8, col, Color(0, 0, 0, 0))
