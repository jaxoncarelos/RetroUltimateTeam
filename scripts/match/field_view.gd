class_name FieldView
extends Node2D
## Draws the stadium: textured turf, end zones, yard lines/numbers/arrows, hashes, a midfield
## emblem, pylons, goalposts, the crowd and sideline team areas (CrowdView), and the LOS /
## first-down markers with the sideline chain crew and down box.

const BORDER := Color("#1f5c28")
const TRACK := Color("#1a4f24")
const LINE := Color("#f4f4f4")
const LOS_COLOR := Color("#29adff")
const FIRST_DOWN_COLOR := Color("#ffec27")
const PYLON := Color("#ff7a1a")
const POST := Color("#ffd23f")
const POST_SHADE := Color("#c79a1c")
const CHAIN_ORANGE := Color("#ff7a1a")

var left_endzone := Color("#1d2b53")
var right_endzone := Color("#7e2553")
var left_label := "HOME"
var right_label := "AWAY"
## Midfield emblem colors (home team).
var emblem_primary := Color("#1d2b53")
var emblem_secondary := Color("#fff1e8")

var los_x := -1.0:
	set(v):
		los_x = v
		queue_redraw()
var first_down_x := -1.0:
	set(v):
		first_down_x = v
		queue_redraw()
## Current down (1-4) for the sideline down box; 0 hides it.
var down := 0:
	set(v):
		down = v
		queue_redraw()

var crowd: CrowdView
var _turf: ImageTexture
var _crowd_colors: Array = []


func _ready() -> void:
	crowd = CrowdView.new()
	crowd.name = "Crowd"
	add_child(crowd)
	if not _crowd_colors.is_empty():
		crowd.setup(_crowd_colors[0], _crowd_colors[1])
	_rebuild_turf()


## Sets both teams' look (end zones, emblem, crowd, sideline players) in one call.
func set_teams(home: TeamData, away: TeamData) -> void:
	left_endzone = home.primary
	right_endzone = away.primary
	left_label = home.team_name.to_upper()
	right_label = away.team_name.to_upper()
	emblem_primary = home.primary
	emblem_secondary = home.secondary
	_crowd_colors = [home.uniform_colors(), away.uniform_colors()]
	if is_inside_tree():
		_rebuild_turf()
		crowd.setup(_crowd_colors[0], _crowd_colors[1])
	queue_redraw()


## The offense always attacks +x, so on a change of possession the end zones swap.
func set_possession(off_team: TeamData, def_team: TeamData) -> void:
	left_endzone = off_team.primary
	right_endzone = def_team.primary
	left_label = off_team.team_name.to_upper()
	right_label = def_team.team_name.to_upper()
	if is_inside_tree():
		_rebuild_turf()


func _rebuild_turf() -> void:
	_turf = StadiumArt.build_turf(left_endzone, right_endzone)
	queue_redraw()


func _px(x_yd: float, y_yd: float) -> Vector2:
	return FieldProjection.to_screen(Vector2(x_yd, y_yd))


func _draw() -> void:
	var font := PixelFont.get_font()
	var field_h := FieldGeo.WIDTH * FieldProjection.PX_Y
	# Border, stands and sideline track are drawn behind this layer by CrowdView.
	if _turf != null:
		draw_texture(_turf, Vector2.ZERO)
	_draw_emblem()
	_draw_endzone_text(font, 5.0, left_label)
	_draw_endzone_text(font, 115.0, right_label)
	# Yard lines every 5, hashes every yard
	for yd in range(int(FieldGeo.OWN_GOAL), int(FieldGeo.OPP_GOAL) + 1):
		var sx := int(_px(yd, 0).x)
		if yd % 5 == 0:
			var w := 2 if yd == int(FieldGeo.OWN_GOAL) or yd == int(FieldGeo.OPP_GOAL) else 1
			draw_rect(Rect2(sx, 0, w, field_h), LINE)
		else:
			for hy in [0.6, FieldGeo.HASH_TOP, FieldGeo.HASH_BOTTOM, FieldGeo.WIDTH - 0.6]:
				draw_rect(Rect2(sx, int(_px(0, hy).y) - 1, 1, 2), Color(LINE, 0.8))
	# Numbers with arrows pointing at the nearer goal line.
	for yd in range(20, 110, 10):
		var n := FieldGeo.yard_line_number(yd)
		for ny in [9.0, FieldGeo.WIDTH - 7.0]:
			var p := _px(yd, ny)
			draw_string(font, Vector2(p.x - 6, p.y), str(n), HORIZONTAL_ALIGNMENT_CENTER, 12, 8, Color(LINE, 0.9))
			if n != 50:
				_draw_arrow(Vector2(p.x + (-10.0 if yd < 60 else 10.0), p.y - 4.0), -1.0 if yd < 60 else 1.0)
	# Sidelines and end lines
	draw_rect(Rect2(_px(0, 0) - Vector2(0, 2), Vector2(FieldGeo.LENGTH * FieldProjection.PX_X, 2)), LINE)
	draw_rect(Rect2(_px(0, FieldGeo.WIDTH), Vector2(FieldGeo.LENGTH * FieldProjection.PX_X, 2)), LINE)
	draw_rect(Rect2(_px(0, 0) - Vector2(2, 2), Vector2(2, field_h + 4)), LINE)
	draw_rect(Rect2(_px(FieldGeo.LENGTH, 0) - Vector2(0, 2), Vector2(2, field_h + 4)), LINE)
	_draw_pylons()
	# Markers
	if los_x >= 0.0:
		draw_rect(Rect2(int(_px(los_x, 0).x) - 1, 0, 2, field_h), LOS_COLOR)
	if first_down_x >= 0.0 and first_down_x < FieldGeo.OPP_GOAL:
		draw_rect(Rect2(int(_px(first_down_x, 0).x) - 1, 0, 2, field_h), FIRST_DOWN_COLOR)
	_draw_chains(font)
	_draw_goalpost(0.0, 1.0)
	_draw_goalpost(FieldGeo.LENGTH, -1.0)


func _draw_endzone_text(font: Font, center_x: float, text: String) -> void:
	var step := FieldGeo.WIDTH / float(text.length() + 1)
	for i in text.length():
		var p := _px(center_x, step * (i + 1))
		draw_string(font, Vector2(p.x - 8, p.y + 4), text[i], HORIZONTAL_ALIGNMENT_CENTER, 16, 16, Color(LINE, 0.85))


## Small solid triangle; dir -1 points left (toward the left goal), +1 right.
func _draw_arrow(tip_side: Vector2, dir: float) -> void:
	var tip := tip_side + Vector2(dir * 3.0, 0.0)
	var base_x := tip_side.x - dir * 1.0
	draw_colored_polygon(PackedVector2Array([tip, Vector2(base_x, tip.y - 3.0), Vector2(base_x, tip.y + 3.0)]),
			Color(LINE, 0.9))


## Original midfield emblem: a shield with a four-point star, in the home colors.
func _draw_emblem() -> void:
	var c := _px(FieldGeo.LENGTH * 0.5, FieldGeo.CENTER_Y)
	var w := 34.0
	var h := 26.0
	var shield := PackedVector2Array([
		c + Vector2(-w * 0.5, -h * 0.5), c + Vector2(w * 0.5, -h * 0.5),
		c + Vector2(w * 0.5, h * 0.05), c + Vector2(0.0, h * 0.5), c + Vector2(-w * 0.5, h * 0.05)])
	var outline := PackedVector2Array()
	for p in shield:
		outline.append(c + (p - c) * 1.12)
	draw_colored_polygon(outline, Color(emblem_secondary, 0.55))
	draw_colored_polygon(shield, Color(emblem_primary, 0.6))
	var s := 9.0
	var star := PackedVector2Array([
		c + Vector2(0, -s), c + Vector2(2, -2), c + Vector2(s, 0), c + Vector2(2, 2),
		c + Vector2(0, s * 0.8), c + Vector2(-2, 2), c + Vector2(-s, 0), c + Vector2(-2, -2)])
	draw_colored_polygon(star, Color(emblem_secondary, 0.75))


func _draw_pylons() -> void:
	for x in [0.0, FieldGeo.OWN_GOAL, FieldGeo.OPP_GOAL, FieldGeo.LENGTH]:
		for y in [0.0, FieldGeo.WIDTH]:
			var p := _px(x, y).round()
			draw_rect(Rect2(p.x - 1, p.y - 5, 3, 6), PYLON)
			draw_rect(Rect2(p.x - 1, p.y - 5, 3, 1), Color.WHITE)


## Goalpost at an end line, drawn with height (slightly oblique so the uprights read).
## lean: +1 leans into the left end zone border, -1 the right.
func _draw_goalpost(end_x: float, lean: float) -> void:
	var z := FieldProjection.PX_Z
	# The post stands just behind the end line, in the border.
	var base := _px(end_x, FieldGeo.CENTER_Y).round() + Vector2(-lean * 10.0, 0.0)
	var bar_z := 3.3 * z
	var up_z := 8.0 * z
	var half := 3.1 * FieldProjection.PX_Y
	# Oblique: height also shifts x a little (away from the field) so the parts separate.
	var slant := -lean * 0.45
	# Shadows on the ground: the crossbar's and the uprights' footprint.
	draw_rect(Rect2(base.x - lean * 4.0, base.y - half, 2, half * 2.0), Color(0, 0, 0, 0.28))
	# Gooseneck: padded base, then the post up to the crossbar.
	draw_rect(Rect2(base.x - 2, base.y - 4, 4, 5), Color("#29366f"))
	var bar_c := base + Vector2(slant * bar_z, -bar_z)
	draw_line(base, bar_c, POST_SHADE, 2.0)
	# Crossbar spans the field-y axis at crossbar height.
	var bar_top := bar_c + Vector2(0, -half)
	var bar_bottom := bar_c + Vector2(0, half)
	draw_line(bar_top, bar_bottom, POST, 2.0)
	# Uprights rise from both ends of the crossbar.
	var rise := Vector2(slant * (up_z - bar_z), -(up_z - bar_z))
	draw_line(bar_top, bar_top + rise, POST, 2.0)
	draw_line(bar_bottom, bar_bottom + rise, POST, 2.0)
	draw_line(bar_top + rise + Vector2(1, 0), bar_top + rise * 0.6 + Vector2(1, 0), POST_SHADE, 1.0)


## Sideline chain crew on the top sideline: rods at the LOS and the line to gain joined by
## the chain, plus the down box at the LOS.
func _draw_chains(font: Font) -> void:
	if los_x < 0.0:
		return
	var y := -3.0
	var rod_h := 16.0
	var a := _px(los_x, 0).x
	if first_down_x >= 0.0 and first_down_x <= FieldGeo.OPP_GOAL:
		var b := _px(first_down_x, 0).x
		for x in range(int(a), int(b), 2):
			draw_rect(Rect2(x, y - 1, 1, 1), Color("#c2c3c7"))
		for x in [a, b]:
			draw_rect(Rect2(x - 1, y - rod_h, 1, rod_h), Color("#1d1d1d"))
			draw_rect(Rect2(x - 2, y - rod_h - 2, 3, 4), CHAIN_ORANGE)
	if down > 0:
		var bx := a - 4.0
		draw_rect(Rect2(bx + 3, y - rod_h - 4, 1, rod_h + 4), Color("#1d1d1d"))
		draw_rect(Rect2(bx, y - rod_h - 13, 8, 9), CHAIN_ORANGE)
		draw_string(font, Vector2(bx + 1, y - rod_h - 5), str(down), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.BLACK)
