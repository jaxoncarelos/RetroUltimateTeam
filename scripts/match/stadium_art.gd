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


## Turf for the whole field (end zones included), 1 px = FieldProjection scale.
## 5-yard mow stripes, per-pixel grain, darker specks, and team-colored end zones.
static func build_turf(left_endzone: Color, right_endzone: Color) -> ImageTexture:
	var w := int(FieldGeo.LENGTH * FieldProjection.PX_X)
	var h := int(FieldGeo.WIDTH * FieldProjection.PX_Y)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var stripe_px := int(5.0 * FieldProjection.PX_X)
	var i := 0
	var x := 0
	while x < w:
		img.fill_rect(Rect2i(x, 0, stripe_px, h), GRASS_A if i % 2 == 0 else GRASS_B)
		x += stripe_px
		i += 1
	var ez := int(FieldGeo.OWN_GOAL * FieldProjection.PX_X)
	img.fill_rect(Rect2i(0, 0, ez, h), left_endzone.darkened(0.08))
	img.fill_rect(Rect2i(w - ez, 0, ez, h), right_endzone.darkened(0.08))
	var grain := _grain_tile()
	for ty in range(0, h, grain.get_height()):
		for tx in range(0, w, grain.get_width()):
			img.blend_rect(grain, Rect2i(Vector2i.ZERO, grain.get_size()), Vector2i(tx, ty))
	return ImageTexture.create_from_image(img)


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
