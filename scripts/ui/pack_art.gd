class_name PackArt
extends Control
## Code-drawn foil card pack (40x56 times `pack_scale`): tier-colored foil with crimped
## ends, our emblem, a name band and a sheen that sweeps across. `shake` jitters it
## (pack opening), `tear` (0..1) lifts the top strip off.

const W := 44
const H := 56

var color := Color("#ffcf40")
var label := "GOLD"
var pack_scale := 1.0
var shake := 0.0
var tear := 0.0
var glow := 0.0
var _t := 0.0


func _init(p_color := Color("#ffcf40"), p_label := "GOLD", p_scale := 1.0) -> void:
	color = p_color
	label = p_label
	pack_scale = p_scale
	custom_minimum_size = Vector2(W, H) * p_scale
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_t = randf() * 2.0


static func for_pack(pack: PackDef, p_scale := 1.0) -> PackArt:
	var short := pack.display_name.replace(" PACK", "") if pack != null else "PACK"
	return PackArt.new(pack.color if pack != null else UiSkin.YELLOW, short, p_scale)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var s := pack_scale
	var off := Vector2.ZERO
	if shake > 0.0:
		off = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * 3.0
	var base := (size - Vector2(W, H) * s) * 0.5
	draw_set_transform(base + off, sin(_t * 1.6) * 0.02 * (1.0 if shake <= 0.0 else 0.0), Vector2(s, s))
	if glow > 0.0:
		for i in 4:
			var g := 2.0 + i * 2.5
			draw_rect(Rect2(-g, -g, W + g * 2, H + g * 2), Color(color.lightened(0.4), glow * (0.25 - i * 0.05)))
	var dark := color.darkened(0.45)
	# Body with a soft vertical foil gradient.
	for y in range(4, H - 4):
		var u := float(y) / H
		var c := color.lightened(0.25).lerp(color.darkened(0.2), u)
		if (y / 3) % 2 == 0:
			c = c.lightened(0.04)
		draw_rect(Rect2(1, y, W - 2, 1), c)
	draw_rect(Rect2(0, 4, 1, H - 8), dark)
	draw_rect(Rect2(W - 1, 4, 1, H - 8), dark)
	# Crimped ends (the top one tears away).
	for x in range(0, W, 4):
		draw_rect(Rect2(x, H - 4, 4, 3), color.darkened(0.25))
		draw_rect(Rect2(x + 1, H - 1, 2, 1), color.darkened(0.25))
		var ty := 1.0 + (1.0 - tear) * 0.0 - tear * 16.0
		draw_rect(Rect2(x, ty, 4, 3), color.darkened(0.25))
		draw_rect(Rect2(x + 1, ty - 1, 2, 1), color.darkened(0.25))
	if tear > 0.0:
		# Light spilling out of the opened top.
		draw_rect(Rect2(1, 4, W - 2, 3), Color(1, 1, 0.85, minf(1.0, tear * 2.0)))
	# Emblem and name band.
	var em := UiSkin.emblem()
	draw_texture_rect(em, Rect2(W * 0.5 - 7.5, 12, 15, 16), false)
	draw_rect(Rect2(1, 33, W - 2, 11), UiSkin.SHADOW)
	draw_rect(Rect2(1, 34, W - 2, 9), UiSkin.NAVY)
	var lw := PixelFont.text_width(label)
	var fs := 8
	if lw > W - 4:
		label = label.left(7)
		lw = PixelFont.text_width(label)
	draw_string(PixelFont.get_font(), Vector2(roundf((W - lw) * 0.5), 42), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			color.lightened(0.3))
	# Sheen sweep.
	var ph := fmod(_t, 2.2) / 2.2
	var sx := lerpf(-40.0, W + 20.0, ph)
	for k in 3:
		if sx + k * 2 < 1.0 or sx + k * 2 + 14 > W - 1:
			continue
		draw_line(Vector2(sx + k * 2, H - 5), Vector2(sx + k * 2 + 14, 5), Color(1, 1, 1, 0.3 - k * 0.09), 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
