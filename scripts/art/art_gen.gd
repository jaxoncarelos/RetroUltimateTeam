class_name ArtGen
extends RefCounted
## Code-generated original pixel art shared by the UI (cards, matchup screens, title).
## CONTRACT (used by UI code): keep these signatures stable; results are cached textures.
## Every piece is deterministic: a portrait depends only on its arguments (the face is seeded
## by player_id), a helmet only on the team abbreviation and colors.
## The *_image() variants return the raw Image (tools/gen_art_preview.gd dumps them to PNG).

static var _cache: Dictionary = {}

const OUTLINE := Color("#141018")
const HAIR_COLORS := [Color("#1a1412"), Color("#2b1d14"), Color("#4a2f1c"), Color("#6b4423"),
		Color("#c89b52"), Color("#e2c275"), Color("#9c4a22"), Color("#8e8e8e")]
const SKIN := [Color("#f1c9a0"), Color("#e0ac69"), Color("#c68642"), Color("#a86b3c"),
		Color("#8d5524"), Color("#5c3a21")]
const DIGITS := {
	"0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
	"2": ["111", "001", "111", "100", "111"], "3": ["111", "001", "011", "001", "111"],
	"4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"],
	"6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "010", "010", "010"],
	"8": ["111", "101", "111", "101", "111"], "9": ["111", "101", "111", "001", "111"],
}


## Head-and-shoulders card portrait, 32x32 px, transparent background.
## colors = TeamData.uniform_colors() ({primary, secondary, helmet, pants}).
## jersey < 0 hides the chest number.
static func portrait(player_id: String, pos: String, colors: Dictionary, jersey: int) -> Texture2D:
	var key := "p:%s:%s:%d:%s" % [player_id, pos, jersey, _ckey(colors)]
	if _cache.has(key):
		return _cache[key]
	var tex := ImageTexture.create_from_image(portrait_image(player_id, pos, colors, jersey))
	_cache[key] = tex
	return tex


## Side-view team helmet, 64x48 px, facing right unless facing_left. No logos: team colors
## plus an original stripe/shape pattern.
static func helmet(team_abbr: String, colors: Dictionary, facing_left := false) -> Texture2D:
	var key := "h:%s:%s:%s" % [team_abbr, facing_left, _ckey(colors)]
	if _cache.has(key):
		return _cache[key]
	var tex := ImageTexture.create_from_image(helmet_image(team_abbr, colors, facing_left))
	_cache[key] = tex
	return tex


## Full title-screen backdrop (stadium, sky, crowd), sized to the 480x270 canvas.
## Leaves y 20-110 in the middle fairly calm for the title and y 236-262 for "TAP TO START".
static func title_backdrop() -> Texture2D:
	if _cache.has("title"):
		return _cache["title"]
	var tex := ImageTexture.create_from_image(title_image())
	_cache["title"] = tex
	return tex


static func _ckey(colors: Dictionary) -> String:
	var parts := []
	for k in ["primary", "secondary", "helmet", "pants"]:
		var c: Variant = colors.get(k)
		parts.append((c as Color).to_html(false) if c is Color else "-")
	return ",".join(parts)


# ---------------------------------------------------------------- shared pixel helpers

static func _put(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		if c.a >= 1.0:
			img.set_pixel(x, y, c)
		else:
			img.set_pixel(x, y, img.get_pixel(x, y).blend(c))


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_put(img, xx, yy, c)


static func _pget(img: Image, x: int, y: int) -> Color:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		return img.get_pixel(x, y)
	return Color(0, 0, 0, 0)


## 1-px outline around every opaque pixel (4-neighbourhood).
static func _outline(img: Image, c: Color) -> void:
	var src := img.duplicate() as Image
	for y in img.get_height():
		for x in img.get_width():
			if src.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if _pget(src, x + d.x, y + d.y).a > 0.5:
					img.set_pixel(x, y, c)
					break


static func _digits(img: Image, text: String, x: int, y: int, c: Color, shadow := Color(0, 0, 0, 0)) -> void:
	for i in text.length():
		var g: Array = DIGITS.get(text[i], [])
		for r in g.size():
			var row: String = g[r]
			for col in row.length():
				if row[col] == "1":
					if shadow.a > 0.0:
						_put(img, x + i * 4 + col + 1, y + r + 1, shadow)
					_put(img, x + i * 4 + col, y + r, c)


static func _contrast(on: Color, a: Color, b: Color) -> Color:
	var da := absf(on.get_luminance() - a.get_luminance()) + _cdist(on, a) * 0.5
	var db := absf(on.get_luminance() - b.get_luminance()) + _cdist(on, b) * 0.5
	return a if da >= db else b


static func _cdist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


# ---------------------------------------------------------------- portraits

static func portrait_image(player_id: String, pos: String, colors: Dictionary, jersey: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(player_id)
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var primary: Color = colors.get("primary", Color("#c0392b"))
	var secondary: Color = colors.get("secondary", Color.WHITE)
	var big := pos in ["OL", "DL", "LT", "LG", "C", "RG", "RT", "DT", "DE"]
	var skin: Color = SKIN[rng.randi() % SKIN.size()]
	var skin_d := skin.darkened(0.22)
	var skin_l := skin.lightened(0.12)
	var hair: Color = HAIR_COLORS[_weighted(rng, [5, 5, 4, 3, 2, 1, 1, 1])]
	if skin.get_luminance() < 0.35 and hair.get_luminance() > 0.35 and rng.randf() < 0.8:
		hair = HAIR_COLORS[rng.randi() % 2]
	var hair_d := hair.darkened(0.35) if hair.get_luminance() > 0.12 else hair.lightened(0.12)
	var hair_style: int = _weighted(rng, [1, 3, 3, 2, 2, 2, 2, 1, 1])
	var beard: int = _weighted(rng, [5, 2, 2, 2, 1, 1])
	var mouth: int = _weighted(rng, [4, 3, 2, 1])
	var brow: int = rng.randi() % 3
	var eye_black := rng.randf() < 0.18
	var b := 1 if big else 0
	# Half width of the face per row (rows 6..19), center x = 15.5.
	var hw := {6: 4, 7: 5, 8: 6, 9: 6, 10: 6, 11: 6, 12: 6, 13: 6, 14: 6, 15: 6, 16: 6, 17: 5, 18: 4, 19: 3}

	# Back hair (behind the head): afro, long, dreads.
	if hair_style == 6:
		for y in range(0, 17):
			for x in range(4, 28):
				var d := Vector2((x - 15.5) / 11.5, (y - 8.5) / 8.5).length()
				if d < 1.0:
					_put(img, x, y, hair_d if (x + y) % 3 == 0 and d > 0.7 else hair)
	elif hair_style == 7 or hair_style == 8:
		for y in range(3, 25):
			var half := 8.0 + b - (maxf(0.0, 7.0 - y) * 0.9)
			if y > 20:
				half -= (y - 20) * 0.5
			for x in range(int(16 - half), int(16 + half)):
				if y > 18 and absf(x - 15.5) < 5.0:
					continue   # hair falls behind the neck, not through it
				var edge := x == int(16 - half) or x == int(16 + half) - 1
				var c := hair_d if (hair_style == 8 and x % 2 == 0) or edge else hair
				if y == 24 and (x % 2 == 1):
					continue
				_put(img, x, y, c)

	# Jersey: shoulders + chest, shoulder stripes, collar, number.
	var sh_w := 13 + b
	for y in range(22, 32):
		var w := sh_w - (2 if y == 22 else (1 if y == 23 else 0))
		for x in range(16 - w, 16 + w):
			var c := primary
			if x <= 16 - w + 1 or x >= 16 + w - 2:
				c = primary.darkened(0.25)
			elif y <= 23:
				c = primary.lightened(0.12)
			_put(img, x, y, c)
	for y in range(24, 26):
		for x in [16 - sh_w + 2, 16 - sh_w + 3, 16 + sh_w - 4, 16 + sh_w - 3]:
			_put(img, x, y, secondary)
	for y in range(18, 24):
		for x in range(12 - b, 20 + b):
			_put(img, x, y, skin_d if y <= 19 else skin)
	for i in 4:
		_put(img, 12 + i - b, 22 + i, secondary)
		_put(img, 19 - i + b, 22 + i, secondary)
		for x in range(13 + i - b, 19 - i + b):
			_put(img, x, 22 + i, skin_d if i < 2 else skin)
	if jersey >= 0:
		var num := str(jersey % 100)
		var nw := num.length() * 4 - 1
		var nc := _contrast(primary, secondary, Color.WHITE)
		_digits(img, num, 16 - (nw + 1) / 2, 27, nc, primary.darkened(0.4))

	# Head.
	for y in range(6, 20):
		var h: int = hw[y] + b
		for x in range(16 - h, 16 + h):
			var c := skin
			if x >= 16 + h - 2:
				c = skin_d
			elif x <= 16 - h and y > 8:
				c = skin_d
			elif y <= 8 and x < 15:
				c = skin_l
			_put(img, x, y, c)
	for y in range(11, 15):
		_put(img, 9 - b, y, skin_d if y == 11 or y == 14 else skin)
		_put(img, 22 + b, y, skin_d)

	_hair(img, hair_style, hair, hair_d, b, rng)

	# Eyes (white + pupil), brows, nose, mouth.
	var ey := 12
	for e in [[12, 13], [19, 18]]:
		_put(img, e[0], ey, Color("#f4f0e8"))
		_put(img, e[1], ey, Color("#1a1412"))
		_put(img, e[1], ey + 1, Color("#1a1412"))
		_put(img, e[0], ey + 1, skin_d)
	if eye_black:
		for x in [12, 13, 18, 19]:
			_put(img, x, ey + 2, Color("#111111"))
	var bc := hair_d if hair_style != 0 or hair.get_luminance() < 0.3 else skin.darkened(0.45)
	match brow:
		0:
			_rect(img, 11, 10, 3, 1, bc)
			_rect(img, 18, 10, 3, 1, bc)
		1:   # determined: inner ends low
			_rect(img, 11, 10, 2, 1, bc)
			_put(img, 13, 11, bc)
			_rect(img, 19, 10, 2, 1, bc)
			_put(img, 18, 11, bc)
		2:   # thick
			_rect(img, 11, 10, 3, 2, bc)
			_rect(img, 18, 10, 3, 2, bc)
	_put(img, 16, 14, skin_d)
	_put(img, 15, 15, skin_d)
	_put(img, 16, 15, skin_d.darkened(0.15))
	var lip := skin.darkened(0.5)
	match mouth:
		0:   # smile
			_put(img, 13, 16, lip)
			_rect(img, 14, 17, 4, 1, lip)
			_put(img, 18, 16, lip)
		1:   # neutral
			_rect(img, 14, 17, 4, 1, lip)
		2:   # big grin
			_rect(img, 13, 16, 6, 1, lip)
			_rect(img, 14, 17, 4, 1, Color("#f4f0e8"))
			_put(img, 13, 17, lip)
			_put(img, 18, 17, lip)
			_rect(img, 14, 18, 4, 1, lip)
		3:   # smirk
			_rect(img, 14, 17, 3, 1, lip)
			_put(img, 17, 16, lip)
	_beard(img, beard, hair, hair_d, skin_d, b)
	_outline(img, OUTLINE)
	return img


static func _weighted(rng: RandomNumberGenerator, weights: Array) -> int:
	var total := 0
	for w in weights:
		total += int(w)
	var r := rng.randi() % total
	for i in weights.size():
		r -= int(weights[i])
		if r < 0:
			return i
	return 0


## Hair on top of the head. Styles: 0 bald, 1 buzz, 2 short, 3 side part, 4 flat-top,
## 5 curly, 6 afro (mostly drawn behind), 7 long, 8 dreads.
static func _hair(img: Image, style: int, hair: Color, hair_d: Color, b: int, rng: RandomNumberGenerator) -> void:
	var l := 10 - b
	var r := 21 + b
	match style:
		0:
			_put(img, 13, 7, Color(1, 1, 1, 0.35))
			_put(img, 14, 7, Color(1, 1, 1, 0.25))
		1:
			for y in range(6, 9):
				for x in range(l + (1 if y == 6 else 0), r + 1 - (1 if y == 6 else 0)):
					_put(img, x, y, hair_d if (x + y) % 2 == 0 else hair)
		2, 3, 5, 7, 8:
			var top := 4 if style != 5 else 3
			for y in range(top, 10):
				var inset := 2 if y == top else (1 if y == top + 1 else 0)
				for x in range(l - 1 + inset, r + 2 - inset):
					var c := hair
					if y == top or x == l - 1 + inset:
						c = hair_d
					if style == 5 and (x + y * 2) % 3 == 0:
						c = hair_d
					_put(img, x, y, c)
			for y in range(10, 13):
				_put(img, l - 1, y, hair)
				_put(img, r + 1, y, hair_d)
			if style == 3:
				_put(img, 13, 4, hair.lightened(0.2))
				_put(img, 13, 5, hair_d)
				_rect(img, 14, 8, 5, 1, hair)
			if style == 5:
				for x in range(l, r + 1, 2):
					_put(img, x, 2, hair)
			if style == 7 or style == 8:
				_rect(img, l - 1, 8, r - l + 3, 2, hair)
		4:
			for y in range(1, 9):
				for x in range(l, r + 1):
					var c := hair if (x + y) % 2 == 0 else hair_d
					if y == 1:
						c = hair_d
					_put(img, x, y, c)
		6:
			for x in range(l, r + 1):
				_put(img, x, 6, hair)
				_put(img, x, 7, hair_d if x % 2 == 0 else hair)
	if style in [2, 3] and rng.randf() < 0.3:
		_put(img, l - 1, 13, hair_d)
		_put(img, r + 1, 13, hair_d)


## Beards: 0 none, 1 stubble, 2 full, 3 goatee, 4 mustache, 5 chin strap.
static func _beard(img: Image, style: int, hair: Color, hair_d: Color, skin_d: Color, b: int) -> void:
	match style:
		1:
			for y in range(15, 20):
				for x in range(10 - b, 22 + b):
					if (x + y) % 2 == 0 and _pget(img, x, y).a > 0 and not (y == 17 and x >= 13 and x <= 18):
						_put(img, x, y, Color(skin_d.darkened(0.25), 0.8))
		2:
			for y in range(13, 21):
				var h := 6 - maxi(0, y - 17) + b
				for x in range(16 - h, 16 + h):
					if y >= 16 and y <= 18 and x >= 13 and x <= 18:
						continue
					if y < 15 and x > 11 - b and x < 20 + b:
						continue
					_put(img, x, y, hair if (x + y) % 3 != 0 else hair_d)
			_rect(img, 13, 16, 6, 1, hair)
			_put(img, 12, 16, hair)
			_put(img, 19, 16, hair)
		3:
			_rect(img, 14, 18, 4, 2, hair)
			_rect(img, 14, 16, 4, 1, hair_d)
		4:
			_rect(img, 13, 16, 6, 1, hair)
		5:
			for y in range(13, 20):
				var h := 6 - maxi(0, y - 16) + b
				_put(img, 16 - h, y, hair)
				_put(img, 15 + h, y, hair_d)
			_rect(img, 13, 19, 6, 1, hair)


# ---------------------------------------------------------------- helmet

static func helmet_image(team_abbr: String, colors: Dictionary, facing_left := false) -> Image:
	var w := 64
	var h := 48
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var base: Color = colors.get("helmet", colors.get("primary", Color("#c0392b")))
	var primary: Color = colors.get("primary", base)
	var secondary: Color = colors.get("secondary", Color.WHITE)
	var stripe := secondary if _cdist(secondary, base) > 0.25 else primary
	if _cdist(stripe, base) < 0.25:
		stripe = base.darkened(0.35) if base.get_luminance() > 0.5 else base.lightened(0.5)
	var accent := primary if _cdist(primary, base) > 0.25 and _cdist(primary, stripe) > 0.2 else stripe.darkened(0.3)
	var pattern := absi(hash(team_abbr)) % 4
	var mask := Color("#b8bcc4") if base.get_luminance() < 0.7 else Color("#5a5e68")
	if base.get_luminance() > 0.2 and _cdist(secondary, base) > 0.4 and absi(hash(team_abbr + "m")) % 3 == 0:
		mask = secondary
	var cx := 28.0
	var cy := 26.0
	var rx := 25.0
	var ry := 22.0
	var light := Vector2(-0.55, -0.8).normalized()
	for y in h:
		for x in w:
			var nx := (x + 0.5 - cx) / rx
			var ny := (y + 0.5 - cy) / ry
			var d := sqrt(nx * nx + ny * ny)
			if d > 1.0:
				continue
			# Lower edge: the back comes down to the neck, the front is cut for the face.
			var bottom := 42.0 if x < 26 else lerpf(42.0, 36.0, clampf((x - 26) / 14.0, 0.0, 1.0))
			if y > bottom:
				continue
			if x >= 41 and y >= 23:
				continue
			# Lambert-ish lighting on the dome, quantized into bands + dither.
			var nz := sqrt(maxf(0.0, 1.0 - d * d))
			var lit := clampf(nx * light.x + ny * light.y + nz * 0.55, -1.0, 1.0)
			var band := lit * 2.2 + (0.1 if (x + y) % 2 == 0 else -0.1)
			var c := base
			if band > 1.35:
				c = base.lightened(0.35)
			elif band > 0.7:
				c = base.lightened(0.14)
			elif band < -0.6:
				c = base.darkened(0.42)
			elif band < 0.0:
				c = base.darkened(0.2)
			var on_crown := ny < 0.15 and x > 5 and x < 52
			var is_stripe := false
			match pattern:
				0:
					is_stripe = on_crown and d > 0.78 and d < 0.9
				1:
					is_stripe = on_crown and ((d > 0.74 and d < 0.8) or (d > 0.86 and d < 0.92))
				2:
					if on_crown and d > 0.72 and d < 0.94:
						c = stripe if (d < 0.78 or d > 0.88) else accent
						is_stripe = d < 0.78 or d > 0.88
				3:
					if y >= 33 and y <= 36 and x < 42:
						is_stripe = true
					elif y == 37 and x < 40:
						c = accent
			if is_stripe:
				c = stripe.darkened(0.2) if lit < -0.1 else stripe
			_put(img, x, y, c)
	# Specular glint.
	for p in [Vector2i(17, 10), Vector2i(18, 10), Vector2i(16, 11), Vector2i(19, 9), Vector2i(20, 9), Vector2i(15, 13)]:
		_put(img, p.x, p.y, Color(1, 1, 1, 0.85))
	# Face opening interior (padding) just behind the mask.
	for y in range(23, 38):
		for x in range(39, 43):
			_put(img, x, y, Color("#2a2230"))
	# Ear hole with a rim.
	for y in range(24, 34):
		for x in range(21, 31):
			var dd := Vector2(x - 25.5, y - 28.5).length()
			if dd < 2.2:
				_put(img, x, y, Color("#1a1420"))
			elif dd < 3.6:
				_put(img, x, y, base.darkened(0.3))
			elif dd < 4.4:
				_put(img, x, y, base.lightened(0.2))
	# Jaw pad and chin strap.
	_rect(img, 30, 37, 11, 3, base.darkened(0.3))
	_rect(img, 38, 40, 10, 2, Color("#e8e6e0"))
	_rect(img, 38, 42, 10, 1, Color("#9a978f"))
	# Facemask: bars from the brim and jaw to the front upright.
	var mask_d := mask.darkened(0.35)
	for bar_y in [24, 31]:
		_rect(img, 40, bar_y, 17, 2, mask)
		_rect(img, 40, bar_y + 2, 17, 1, mask_d)
	_rect(img, 40, 38, 13, 2, mask)
	for y in range(22, 41):
		var fx := 56 - (1 if y > 34 else 0) - (1 if y > 38 else 0)
		_put(img, fx, y, mask)
		_put(img, fx + 1, y, mask_d)
	for y in range(22, 38):
		_put(img, 46, y, mask)
		_put(img, 47, y, mask_d)
	_outline(img, OUTLINE)
	if facing_left:
		img.flip_x()
	return img


# ---------------------------------------------------------------- title backdrop

static func title_image() -> Image:
	var W := 480
	var H := 270
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2701
	# Sky: vertical gradient in bands with dithered seams.
	var sky := [Color("#2d6fd1"), Color("#3d86e0"), Color("#58a0ea"), Color("#7dbaf0"), Color("#a9d4f5")]
	for y in 120:
		var t := y / 120.0 * (sky.size() - 1)
		var i := int(t)
		var f := t - i
		for x in W:
			var c: Color = sky[i]
			if i + 1 < sky.size() and (f > 0.8 or (f > 0.5 and (x + y) % 2 == 0)):
				c = sky[i + 1]
			img.set_pixel(x, y, c)
	# Sun (behind the stands) with a soft halo and scanline glints.
	var sun := Vector2(240, 66)
	for y in range(0, 120):
		for x in range(120, 360):
			var d := Vector2(x, y).distance_to(sun)
			if d < 30:
				_put(img, x, y, Color("#ffe98a") if d < 26 else Color("#fff4c2"))
			elif d < 46 and (x + y) % 2 == 0:
				_put(img, x, y, Color(1, 0.95, 0.7, 0.35))
	for y in range(44, 76, 6):
		_rect(img, 214, y, 52, 1, Color(1, 1, 1, 0.3))
	for cl in [[40, 26, 1.0], [110, 50, 0.7], [370, 30, 1.1], [430, 58, 0.7], [170, 16, 0.6], [300, 40, 0.6]]:
		_cloud(img, int(cl[0]), int(cl[1]), float(cl[2]), rng)
	var horizon := 150
	# Stadium bowl (upper edge is an arc), tier aisles every 14 px.
	for x in W:
		var arc := _arc(x)
		for y in range(int(arc), horizon):
			var c := Color("#8f1e2a")
			if y < arc + 4:
				c = Color("#5e1420")
			elif int(y - arc) % 14 < 2:
				c = Color("#6d1722")
			img.set_pixel(x, y, c)
	# Crowd: tiny fans, dimmer toward the top.
	var shirts := [Color("#e8e6e0"), Color("#d23a3a"), Color("#2a4fa8"), Color("#f2c230"), Color("#2f8a3a"),
			Color("#7a3fa0"), Color("#ef7d22"), Color("#1d1d2a"), Color("#39b4d8")]
	for x in range(0, W, 3):
		var arc := _arc(x)
		var y := int(arc) + 6
		while y < horizon - 6:
			if int(y - arc) % 14 >= 3 and rng.randf() < 0.85:
				var sc: Color = shirts[rng.randi() % shirts.size()]
				var dim := clampf((horizon - y) / 120.0, 0.0, 0.45)
				_put(img, x, y + 1, sc.darkened(dim))
				_put(img, x + 1, y + 1, sc.darkened(dim + 0.1))
				_put(img, x, y, (SKIN[rng.randi() % SKIN.size()] as Color).darkened(dim))
			y += 3
	# Upper-deck facade band and light towers.
	for x in W:
		var arc := _arc(x)
		for y in range(int(arc) - 6, int(arc)):
			img.set_pixel(x, y, Color("#c42a36") if y > arc - 5 else Color("#e8e6e0"))
	for tx in [26, 454]:
		_rect(img, tx, 20, 3, 70, Color("#3a3f4a"))
		_rect(img, tx - 10, 12, 23, 12, Color("#2a2e38"))
		for lx in range(tx - 8, tx + 12, 4):
			for ly in [14, 19]:
				_rect(img, lx, ly, 3, 3, Color("#fff4c2"))
	# Field wall with padding stripe.
	_rect(img, 0, horizon - 6, W, 6, Color("#1d2b53"))
	_rect(img, 0, horizon - 6, W, 1, Color("#3a5aa8"))
	_rect(img, 0, horizon - 1, W, 1, Color("#10162c"))
	# Field in perspective: mow bands widen toward the viewer, yard lines converge.
	for y in range(horizon, H):
		var t := float(y - horizon) / (H - horizon)
		var band := int(pow(t, 0.7) * 9.0)
		var g := Color("#2f8a3a") if band % 2 == 0 else Color("#3a9a44")
		for x in W:
			img.set_pixel(x, y, g.darkened(0.12) if (x * 7 + y * 13) % 29 == 0 else g)
	for i in range(-6, 7):
		var x_far := 240.0 + i * 46.0
		var x_near := 240.0 + i * 120.0
		for y in range(horizon, H):
			var t := float(y - horizon) / (H - horizon)
			var x := int(lerpf(x_far, x_near, t))
			_put(img, x, y, Color(1, 1, 1, 0.55))
			if t > 0.5:
				_put(img, x + 1, y, Color(1, 1, 1, 0.45))
	_trophy(img, 240, horizon + 4)
	_lineup(img)
	# Soft darkening at the bottom for the TAP TO START text.
	for y in range(232, H):
		var a := (y - 232) / 38.0 * 0.45
		for x in W:
			_put(img, x, y, Color(0, 0, 0.08, a))
	return img


static func _arc(x: int) -> float:
	return 58.0 + pow((x - 240.0) / 240.0, 2.0) * 34.0


static func _cloud(img: Image, x0: int, y0: int, s: float, rng: RandomNumberGenerator) -> void:
	var puffs := []
	for i in 5:
		puffs.append(Vector3(x0 + i * 9 * s + rng.randf_range(-3, 3), y0 + (4 if i % 2 == 0 else 0) * s, (7 + rng.randi() % 5) * s))
	for p in puffs:
		for y in range(int(p.y - p.z), int(p.y + p.z)):
			for x in range(int(p.x - p.z), int(p.x + p.z)):
				var d := Vector2(x, y).distance_to(Vector2(p.x, p.y))
				if d < p.z and y < y0 + 6 * s:
					_put(img, x, y, Color("#ffffff") if y < p.y - p.z * 0.2 else Color("#dde9f6"))


static func _trophy(img: Image, cx: int, base_y: int) -> void:
	var gold := Color("#f2c230")
	var gold_d := Color("#b8861c")
	var gold_l := Color("#fff0a0")
	_rect(img, cx - 22, base_y - 34, 44, 38, Color("#6d1722"))
	_rect(img, cx - 22, base_y - 34, 44, 3, Color("#c42a36"))
	_rect(img, cx + 14, base_y - 31, 8, 35, Color("#4e0f18"))
	var top := base_y - 34
	_rect(img, cx - 9, top - 4, 18, 4, gold_d)
	_rect(img, cx - 7, top - 5, 14, 1, gold)
	_rect(img, cx - 2, top - 14, 4, 9, gold)
	_put(img, cx + 1, top - 12, gold_d)
	for y in range(top - 30, top - 14):
		var w := int(lerpf(9.0, 3.0, float(y - (top - 30)) / 16.0))
		for x in range(cx - w, cx + w):
			var c := gold
			if x < cx - w + 2:
				c = gold_l
			elif x > cx + w - 3:
				c = gold_d
			_put(img, x, y, c)
	for y in range(top - 27, top - 19):
		_put(img, cx - 12, y, gold_d)
		_put(img, cx + 11, y, gold_d)
	_rect(img, cx - 11, top - 28, 3, 1, gold_d)
	_rect(img, cx + 9, top - 28, 3, 1, gold_d)
	_rect(img, cx - 9, top - 31, 18, 1, gold_l)


## Players standing on the field at 2x scale, in original generic color schemes.
static func _lineup(img: Image) -> void:
	var sheet: Texture2D = load(PlayerSprites.SHEET)
	if sheet == null:
		return
	var src := sheet.get_image()
	if src == null:
		return
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	var schemes := [
		[Color("#c8102e"), Color("#ffffff"), Color("#c8102e"), Color("#ffffff")],
		[Color("#1d3f8f"), Color("#f2c230"), Color("#1d3f8f"), Color("#f2c230")],
		[Color("#0f6b3a"), Color("#ffffff"), Color("#c2c3c7"), Color("#ffffff")],
		[Color("#ef7d22"), Color("#1d1d2a"), Color("#ef7d22"), Color("#ffffff")],
		[Color("#6a2c91"), Color("#f2c230"), Color("#6a2c91"), Color("#ffffff")],
		[Color("#12233f"), Color("#39b4d8"), Color("#c2c3c7"), Color("#c2c3c7")],
		[Color("#8f1e2a"), Color("#f2c230"), Color("#f2c230"), Color("#8f1e2a")],
		[Color("#1a1a1a"), Color("#c0a060"), Color("#c0a060"), Color("#c0a060")],
	]
	var fw := PlayerSprites.FRAME.x
	var fh := PlayerSprites.FRAME.y
	var feet := int(-PlayerSprites.OFFSET.y)
	# [x center, feet y, frame, scheme, flip]
	var spots := [
		[40, 226, 14, 0, false], [88, 216, 0, 1, false], [134, 232, 18, 2, false], [178, 214, 16, 3, false],
		[302, 214, 16, 4, true], [346, 232, 18, 5, true], [392, 216, 0, 6, true], [440, 226, 14, 7, true],
	]
	for i in spots.size():
		var s: Array = spots[i]
		var frame := src.get_region(Rect2i(int(s[2]) * fw, 0, fw, fh))
		_swap(frame, schemes[int(s[3])], i)
		if s[4]:
			frame.flip_x()
		frame.resize(fw * 2, fh * 2, Image.INTERPOLATE_NEAREST)
		var fx := int(s[0])
		var fy := int(s[1])
		for x in range(-12, 12):
			_put(img, fx + x, fy + 1, Color(0, 0, 0, 0.28))
			if absi(x) < 9:
				_put(img, fx + x, fy + 2, Color(0, 0, 0, 0.2))
		img.blend_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i(fx - fw, fy - feet * 2))


## CPU twin of palette_swap.gdshader for baked art. scheme = [primary, secondary, helmet, pants].
static func _swap(frame: Image, scheme: Array, skin_i: int) -> void:
	var p: Color = scheme[0]
	var s: Color = scheme[1]
	var hl: Color = scheme[2]
	var pa: Color = scheme[3]
	var skin: Color = PlayerSprites.SKIN_TONES[skin_i % PlayerSprites.SKIN_TONES.size()]
	var map := {
		"ff0000": p, "800000": _shade(p), "00ff00": s, "008000": _shade(s),
		"0000ff": hl, "000080": _shade(hl), "8080ff": hl.lerp(Color.WHITE, 0.55),
		"00ffff": PlayerSprites.stripe_color(hl, p, s),
		"ffff00": pa, "808000": _shade(pa), "ff00ff": skin, "800080": _shade(skin),
		"808080": PlayerSprites.mask_color(hl),
	}
	for y in frame.get_height():
		for x in frame.get_width():
			var c := frame.get_pixel(x, y)
			if c.a == 0.0:
				continue
			var k := c.to_html(false)
			if map.has(k):
				frame.set_pixel(x, y, map[k])


static func _shade(c: Color) -> Color:
	return Color(c.r * 0.66 + 0.02, c.g * 0.66 + 0.02, c.b * 0.74 + 0.05, c.a)
