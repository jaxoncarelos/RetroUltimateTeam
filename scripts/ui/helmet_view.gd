class_name HelmetView
extends Control
## A team's side-view helmet: ArtGen.helmet at an integer scale (>= 1), or the small
## code-drawn helmet (UiSkin.mini_helmet) for list rows. Optional pulsing glow behind it.

var team: TeamData
var facing_left := false
var helmet_scale := 1.0      ## >= 1: ArtGen helmet scale; < 1: mini helmet
var glow := false
var glow_color := UiSkin.GREEN
var _t := 0.0


func _init(p_team: TeamData = null, p_scale := 1.0, p_facing_left := false) -> void:
	team = p_team
	helmet_scale = p_scale
	facing_left = p_facing_left
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(64, 48) * p_scale if p_scale >= 1.0 else Vector2(16, 12)


func _process(delta: float) -> void:
	if glow:
		_t += delta
		queue_redraw()


func _draw() -> void:
	if team == null:
		return
	if glow:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.62
		for i in 4:
			draw_circle(c, r * (1.0 - i * 0.14) + sin(_t * 3.0) * 1.5, Color(glow_color, 0.08 + i * 0.04))
	if helmet_scale >= 1.0:
		var tex := ArtGen.helmet(team.abbr, team.uniform_colors(), facing_left)
		var sz := tex.get_size() * roundf(helmet_scale)
		draw_texture_rect(tex, Rect2(((size - sz) * 0.5).round(), sz), false)
	else:
		var tex2 := UiSkin.mini_helmet(team.abbr, team.helmet, team.secondary, facing_left)
		var sz2 := tex2.get_size()
		draw_texture_rect(tex2, Rect2(((size - sz2) * 0.5).round(), sz2), false)
