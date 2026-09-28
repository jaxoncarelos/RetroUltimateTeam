class_name StadiumArt
extends RefCounted
## Original stadium pixel art generated in code: textured turf with mow stripes, and
## animated crowd tiles in team colors. Deterministic (seeded) so it never flickers.

const GRASS_A := Color("#2f8a3a")
const GRASS_B := Color("#2a7d34")
const SKIN_TONES := [Color("#8d5524"), Color("#c68642"), Color("#e0ac69"), Color("#5c3a21"), Color("#a86b3c")]
const NEUTRAL_SHIRTS := [Color("#c2c3c7"), Color("#5f574f"), Color("#1d2b53"), Color("#fff1e8"), Color("#83769c")]
const SEAT_A := Color("#2b2f3a")
const SEAT_B := Color("#232631")
const CROWD_H := 30        ## px: five rows of fans
const CROWD_TILE_W := 256
const CROWD_FRAMES := 3

static var _turf_cache: Dictionary = {}


## Turf for the whole field (end zones included), 1 px = FieldProjection scale.
## Baked in: 5-yard mow stripes, grain, team-colored end zones, yard lines, hash marks, big
## outlined yard numbers (top row upside down, like a real field) with goal arrows, and a
## faint original midfield emblem in the home colors.
static func build_turf(left_endzone: Color, right_endzone: Color,
		emblem_primary := Color(0, 0, 0, 0), emblem_secondary := Color.WHITE) -> ImageTexture:
	var key := "%s|%s|%s|%s" % [left_endzone.to_html(), right_endzone.to_html(), emblem_primary.to_html(), emblem_secondary.to_html()]
	if _turf_cache.has(key):
		return _turf_cache[key]
	if _turf_cache.size() > 6:
		_turf_cache.clear()
	var px := FieldProjection.PX_X
	var py := FieldProjection.PX_Y
	var w := int(FieldGeo.LENGTH * px)
	var h := int(FieldGeo.WIDTH * py)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var stripe_px := int(5.0 * px)
	var i := 0
	var x := 0
	while x < w:
		img.fill_rect(Rect2i(x, 0, stripe_px, h), GRASS_A if i % 2 == 0 else GRASS_B)
		x += stripe_px
		i += 1
	var ez := int(FieldGeo.OWN_GOAL * px)
	_endzone(img, Rect2i(0, 0, ez, h), left_endzone)
	_endzone(img, Rect2i(w - ez, 0, ez, h), right_endzone)
	var grain := _grain_tile()
	for ty in range(0, h, grain.get_height()):
		for tx in range(0, w, grain.get_width()):
			img.blend_rect(grain, Rect2i(Vector2i.ZERO, grain.get_size()), Vector2i(tx, ty))
	if emblem_primary.a > 0.0:
		_emblem(img, Vector2i(w / 2, h / 2), emblem_primary, emblem_secondary)
	_lines(img)
	var tex := ImageTexture.create_from_image(img)
	_turf_cache[key] = tex
	return tex


static func _endzone(img: Image, r: Rect2i, c: Color) -> void:
	var base := c.darkened(0.1)
	img.fill_rect(r, base)
	# Diagonal pinstripes, very faint.
	for y in r.size.y:
		for x in r.size.x:
			if (x + y * 2) % 12 == 0:
				img.set_pixel(r.position.x + x, y, base.lightened(0.06))


const LINE_C := Color(0.96, 0.96, 0.96, 0.92)
const NUM_OUTLINE := Color(0.05, 0.12, 0.06, 0.35)
## 5x7 block digits used for the yard numbers (drawn 2x).
const NUM_GLYPHS := {
	"0": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
	"3": ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
	"4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
	"5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
}


static func _lines(img: Image) -> void:
	var px := FieldProjection.PX_X
	var py := FieldProjection.PX_Y
	var h := img.get_height()
	for yd in range(int(FieldGeo.OWN_GOAL), int(FieldGeo.OPP_GOAL) + 1):
		var sx := int(yd * px)
		if yd % 5 == 0:
			var goal := yd == int(FieldGeo.OWN_GOAL) or yd == int(FieldGeo.OPP_GOAL)
			_blend_rect(img, Rect2i(sx - (1 if goal else 0), 0, 2 if goal else 1, h), LINE_C)
			# Soft shadow on the right edge makes the line crisp on light stripes.
			_blend_rect(img, Rect2i(sx + 1, 0, 1, h), Color(0, 0, 0, 0.08))
		else:
			for hy in [0.9, FieldGeo.HASH_TOP, FieldGeo.HASH_BOTTOM, FieldGeo.WIDTH - 0.9]:
				_blend_rect(img, Rect2i(sx, int(hy * py) - 2, 1, 4), Color(LINE_C, 0.85))
	# Big yard numbers: bottom row upright, top row rotated 180 degrees.
	for yd in range(20, 110, 10):
		var n := str(FieldGeo.yard_line_number(yd))
		var cx := int(yd * px)
		var bottom_top := int((FieldGeo.WIDTH - 9.5) * py)
		var top_top := int(7.2 * py)
		for row in [top_top, bottom_top]:
			var flip: bool = row == top_top
			_number(img, n, cx, row, flip)
			if n != "50":
				var toward_left := yd < 60
				var dir := -1 if toward_left else 1
				if flip:
					pass
				var ax := cx + dir * 17
				_arrow(img, ax, row + 7, dir)


## Two digits straddling the yard line (1-px gap each side), 10x14 px each, outlined.
static func _number(img: Image, text: String, cx: int, top: int, flip: bool) -> void:
	var glyph_w := 10
	var positions := []
	if text.length() == 2:
		positions = [cx - 2 - glyph_w, cx + 3]
	else:
		positions = [cx - glyph_w / 2]
	var chars := text
	if flip and text.length() == 2:
		chars = text[1] + text[0]   # upside-down reading order
	var layer := Image.create(img.get_width(), 16, false, Image.FORMAT_RGBA8)
	layer.fill(Color(0, 0, 0, 0))
	for i in chars.length():
		var g: Array = NUM_GLYPHS.get(chars[i], [])
		for r in g.size():
			var row: String = g[r]
			for c in row.length():
				if row[c] != "#":
					continue
				var gx: int = c if not flip else 4 - c
				var gy: int = r if not flip else 6 - r
				for dy in 2:
					for dx in 2:
						var x: int = positions[i] + gx * 2 + dx
						var y: int = 1 + gy * 2 + dy
						if x >= 0 and x < layer.get_width():
							layer.set_pixel(x, y, LINE_C)
	# Outline ring (dark, translucent) then composite.
	var x0 := maxi(0, positions[0] - 2)
	var x1 := mini(layer.get_width(), positions[0] + 2 * glyph_w + 8)
	for y in 16:
		for x in range(x0, x1):
			if layer.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.x < layer.get_width() and q.y >= 0 and q.y < 16 and layer.get_pixel(q.x, q.y) == LINE_C:
					layer.set_pixel(x, y, NUM_OUTLINE)
					break
	img.blend_rect(layer, Rect2i(x0, 0, x1 - x0, 16), Vector2i(x0, top - 1))


static func _arrow(img: Image, x: int, y: int, dir: int) -> void:
	for i in 4:
		for dy in range(-i, i + 1):
			_blend_rect(img, Rect2i(x + dir * (3 - i), y + dy, 1, 1), Color(LINE_C, 0.85))


static func _blend_rect(img: Image, r: Rect2i, c: Color) -> void:
	var cl := r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	for y in range(cl.position.y, cl.end.y):
		for x in range(cl.position.x, cl.end.x):
			img.set_pixel(x, y, img.get_pixel(x, y).blend(c))


## Original midfield emblem: a crest (shield) with a tilted football and wing chevrons,
## painted translucent and light like field paint, squashed like the field projection.
static func _emblem(img: Image, c: Vector2i, primary: Color, secondary: Color) -> void:
	var fill := Color(primary.lerp(Color.WHITE, 0.4), 0.34)
	var ring := Color(secondary.lerp(Color.WHITE, 0.35), 0.6)
	var edge := Color(Color.WHITE, 0.35)
	var rx := 36.0
	var top := -28
	var bottom := 32
	for y in range(top - 1, bottom + 1):
		var t := float(y - top) / float(bottom - top)
		var half := rx if t < 0.45 else rx * (1.0 - (t - 0.45) / 0.55)
		if y < top + 3:
			half = rx - (top + 3 - y) * 2.0
		for x in range(-int(half) - 1, int(half) + 2):
			var inside := absf(x) <= half and y >= top and y <= bottom
			var dist_edge := half - absf(x)
			var col := Color(0, 0, 0, 0)
			if inside:
				if dist_edge < 1.0 or y < top + 1 or y > bottom - 1:
					col = edge
				elif dist_edge < 4.0 or y < top + 3:
					col = ring
				else:
					col = fill
			if col.a > 0.0:
				_blend_px(img, c.x + x, c.y + y, col)
	# Tilted football with laces.
	var ball := Color(secondary.lerp(Color.WHITE, 0.2), 0.75)
	var lace := Color(primary.darkened(0.2), 0.7)
	var ang := -0.45
	var ca := cos(ang)
	var sa := sin(ang)
	for y in range(-20, 21):
		for x in range(-30, 31):
			var u := x * ca + y * sa * 1.6
			var v := -x * sa + y * ca * 1.6
			var d := Vector2(u / 24.0, v / 12.0).length()
			if d <= 1.0:
				var col := ball
				if absf(v) < 1.0 and absf(u) < 11.0:
					col = lace
				elif absf(v) < 3.5 and absf(u) < 11.0 and int(absf(u)) % 4 == 0:
					col = lace
				elif d > 0.86:
					col = Color(primary.darkened(0.3), 0.6)
				_blend_px(img, c.x + x, c.y - 3 + y, col)


static func _blend_px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, img.get_pixel(x, y).blend(c))


## 64x64 tile of translucent light/dark pixels: grass grain, blades and specks.
static func _grain_tile() -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var t := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	t.fill(Color(0, 0, 0, 0))
	for y in 64:
		for x in 64:
			var r := rng.randf()
			if r < 0.10:
				t.set_pixel(x, y, Color(1, 1, 1, 0.05))
			elif r < 0.20:
				t.set_pixel(x, y, Color(0, 0, 0, 0.06))
			elif r < 0.215:
				# A blade: two light pixels stacked.
				t.set_pixel(x, y, Color(0.8, 1, 0.6, 0.10))
				t.set_pixel(x, (y + 1) % 64, Color(0.8, 1, 0.6, 0.07))
			elif r < 0.222:
				t.set_pixel(x, y, Color(0.1, 0.05, 0, 0.14))
	# Faint mow rows every 4 px.
	for y in range(0, 64, 4):
		for x in 64:
			var c := t.get_pixel(x, y)
			t.set_pixel(x, y, Color(1, 1, 1, maxf(c.a, 0.025)) if c.a < 0.03 else c)
	return t


## Crowd tiles: CROWD_FRAMES frames of CROWD_TILE_W x CROWD_H, fans mostly in the given
## team's colors. Frames differ only in which fans are standing/cheering.
static func build_crowd(primary: Color, secondary: Color, seed_value: int) -> Array[ImageTexture]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var fans: Array = []
	var rows := CROWD_H / 6
	for row in rows:
		for col in range(0, CROWD_TILE_W, 4):
			var r := rng.randf()
			var shirt: Color
			if r < 0.45:
				shirt = primary
			elif r < 0.7:
				shirt = secondary
			elif r < 0.93:
				shirt = NEUTRAL_SHIRTS[rng.randi() % NEUTRAL_SHIRTS.size()]
			else:
				continue   # empty seat
			fans.append({
				"x": col + (row % 2) * 2,
				"y": row * 6,
				"shirt": shirt.lightened(rng.randf_range(-0.08, 0.08)),
				"skin": SKIN_TONES[rng.randi() % SKIN_TONES.size()],
				"phase": rng.randi() % CROWD_FRAMES,
				"cheer": rng.randf() < 0.3,
			})
	var out: Array[ImageTexture] = []
	for f in CROWD_FRAMES:
		var img := Image.create(CROWD_TILE_W, CROWD_H, false, Image.FORMAT_RGBA8)
		for row in rows:
			img.fill_rect(Rect2i(0, row * 6, CROWD_TILE_W, 6), SEAT_A if row % 2 == 0 else SEAT_B)
		for fan in fans:
			var up: int = 1 if fan["cheer"] and fan["phase"] == f else 0
			var fx: int = fan["x"] % CROWD_TILE_W
			var fy: int = fan["y"] + 1 - up
			_put(img, Rect2i(fx, fy, 2, 2), fan["skin"])             # head
			_put(img, Rect2i(fx, fy + 2, 3, 3), fan["shirt"])         # body
			if up == 1:
				_put(img, Rect2i(fx - 1, fy - 1, 1, 2), fan["skin"])  # arms up
				_put(img, Rect2i(fx + 3, fy - 1, 1, 2), fan["skin"])
		out.append(ImageTexture.create_from_image(img))
	return out


static func _put(img: Image, r: Rect2i, c: Color) -> void:
	var clipped := r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if clipped.size.x > 0 and clipped.size.y > 0:
		img.fill_rect(clipped, c)
