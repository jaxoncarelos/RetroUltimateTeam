class_name TeamBadge
extends Control
## Original team badge: a pixel shield in the team's colors with its abbreviation (no logos).

var team: TeamData
var badge_scale := 2


func _init(p_team: TeamData = null, p_scale := 2) -> void:
	team = p_team
	badge_scale = p_scale
	custom_minimum_size = Vector2(16, 18) * p_scale
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if team == null:
		return
	draw_badge(self, Vector2.ZERO, team, badge_scale)


## Draws a badge onto any CanvasItem at `at` (top-left), 16x18 px times `s`.
static func draw_badge(ci: CanvasItem, at: Vector2, t: TeamData, s: int) -> void:
	var outline := PackedVector2Array([Vector2(0, 0), Vector2(16, 0), Vector2(16, 10), Vector2(8, 18), Vector2(0, 10)])
	var inner := PackedVector2Array([Vector2(1, 1), Vector2(15, 1), Vector2(15, 10), Vector2(8, 17), Vector2(1, 10)])
	var pts := PackedVector2Array()
	for p in outline:
		pts.append(at + p * s)
	ci.draw_colored_polygon(pts, t.secondary)
	pts = PackedVector2Array()
	for p in inner:
		pts.append(at + p * s)
	ci.draw_colored_polygon(pts, t.primary)
	# A stripe in the secondary color.
	ci.draw_rect(Rect2(at + Vector2(1, 4) * s, Vector2(14, 1) * s), Color(t.secondary, 0.8))
	var font := PixelFont.get_font()
	var fs := 8 * maxi(1, s / 2)
	var w := t.abbr.length() * 6 * maxi(1, s / 2)
	var tp := at + Vector2((16 * s - w) * 0.5 + 1, 13 * s)
	ci.draw_string(font, tp + Vector2(1, 1), t.abbr, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.8))
	ci.draw_string(font, tp, t.abbr, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
