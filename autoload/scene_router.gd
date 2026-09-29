extends CanvasLayer
## Scene transitions with a diagonal pixel wipe, and a config hand-off (e.g. MatchConfig
## dictionary for the match scene: take_config() in the new scene's _ready).

const TITLE := "res://scenes/meta/title.tscn"
const HUB := "res://scenes/meta/hub.tscn"
const MATCH := "res://scenes/match/match.tscn"
const TEAM_PICK := "res://scenes/meta/team_picker.tscn"
const MODE := "res://scenes/meta/mode_select.tscn"
const PREMATCH := "res://scenes/meta/prematch.tscn"
const RESULTS := "res://scenes/meta/results.tscn"
const OBJECTIVES := "res://scenes/meta/objectives.tscn"
const STORE := "res://scenes/meta/store.tscn"
const SQUAD := "res://scenes/meta/collection.tscn"
const LINEUP := "res://scenes/meta/lineup.tscn"
const PACK_OPEN := "res://scenes/meta/pack_open.tscn"
const SEASON := "res://scenes/meta/season.tscn"
const CHALLENGES := "res://scenes/meta/challenges.tscn"
const SETTINGS := "res://scenes/meta/settings.tscn"
const COACH := "res://scenes/meta/coach.tscn"

const WIPE_TIME := 0.22

var pending_config: Dictionary = {}
var _wipe: _Wipe
var _busy := false


## Full-screen grid of squares that grow in along a diagonal (cover) and shrink away.
class _Wipe:
	extends Control
	var progress := 0.0:
		set(v):
			progress = v
			queue_redraw()
	const WCELL := 20.0
	var color := Color("#0f165a")

	func _draw() -> void:
		if progress <= 0.0:
			return
		var cols := int(ceil(size.x / WCELL)) + 1
		var rows := int(ceil(size.y / WCELL)) + 1
		var span := float(cols + rows)
		for y in rows:
			for x in cols:
				var d := float(x + y) / span
				var k := clampf(progress * 2.0 - d, 0.0, 1.0)
				if k <= 0.0:
					continue
				var s := WCELL * k
				var c := Vector2(x, y) * WCELL + Vector2.ONE * WCELL * 0.5
				draw_rect(Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)).grow(0.5), color)


func _ready() -> void:
	layer = 100
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--snap="):
			var parts := a.trim_prefix("--snap=").split(",")
			_snap_after.call_deferred(parts[0], int(parts[1]) if parts.size() > 1 else 60)
	_wipe = _Wipe.new()
	_wipe.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wipe)


func goto(path: String, config: Dictionary = {}) -> void:
	if _busy:
		return
	_busy = true
	pending_config = config
	_wipe.mouse_filter = Control.MOUSE_FILTER_STOP
	Sfx.play("swoosh")
	var tw := create_tween()
	tw.tween_property(_wipe, "progress", 1.0, WIPE_TIME)
	await tw.finished
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	var back := create_tween()
	back.tween_property(_wipe, "progress", 0.0, WIPE_TIME)
	await back.finished
	_wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


func is_busy() -> bool:
	return _busy


func take_config() -> Dictionary:
	var c := pending_config
	pending_config = {}
	return c


## Debug: `-- --snap=out.png[,frames]` saves the viewport (at the window's real aspect, unlike
## --write-movie which crops to 480x270) after N frames and quits.
func _snap_after(path: String, frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	get_tree().quit()
