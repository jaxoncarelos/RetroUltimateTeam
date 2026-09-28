extends CanvasLayer
## Scene transitions with a quick pixel fade, and a config hand-off (e.g. MatchConfig
## dictionary for the match scene: take_config() in the new scene's _ready).

const HUB := "res://scenes/meta/hub.tscn"
const MATCH := "res://scenes/match/match.tscn"
const TEAM_PICK := "res://scenes/meta/team_picker.tscn"

var pending_config: Dictionary = {}
var _fade: ColorRect
var _busy := false


func _ready() -> void:
	layer = 100
	_fade = ColorRect.new()
	_fade.color = Color(0.06, 0.08, 0.12, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


func goto(path: String, config: Dictionary = {}) -> void:
	if _busy:
		return
	_busy = true
	pending_config = config
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.18)
	await tw.finished
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	var back := create_tween()
	back.tween_property(_fade, "color:a", 0.0, 0.18)
	_busy = false


func take_config() -> Dictionary:
	var c := pending_config
	pending_config = {}
	return c
