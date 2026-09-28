extends SceneTree
## Generates small reusable FX sprites (original pixel art) into res://art/fx/.
## Run:  godot --headless --path . --script res://tools/gen_fx_sprites.gd
## All sprites are white/gray with alpha so the UI tints them with `modulate` (tier colors).
##   confetti.png    6 frames of 6x6 in one row: rect, square, strip twisting (3 frames), dot.
##                   Use AtlasTexture regions (i * 6, 0, 6, 6); spin/fall in code.
##   sparkle.png     4 frames of 9x9: dot -> small cross -> 4-point star -> fading star.
##   light_burst.png 96x96 radial rays (12 rays), centered; rotate slowly behind a card.
##   glow_ring.png   48x48 ring with stepped pixel glow; scale/pulse around a card or badge.

func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://art/fx")
	_save(_confetti(), "confetti")
	_save(_sparkle(), "sparkle")
	_save(_burst(), "light_burst")
	_save(_ring(), "glow_ring")
	quit()


func _save(img: Image, name: String) -> void:
	var err := img.save_png("res://art/fx/%s.png" % name)
	print("art/fx/%s.png err=%d" % [name, err])


func _img(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


func _confetti() -> Image:
	var img := _img(36, 6)
	var hi := Color.WHITE
	var lo := Color(0.72, 0.72, 0.76)
	# 0: rectangle (3x5) with shaded edge
	img.fill_rect(Rect2i(1, 0, 3, 5), hi)
	img.fill_rect(Rect2i(3, 0, 1, 5), lo)
	# 1: square 4x4
	img.fill_rect(Rect2i(7, 1, 4, 4), hi)
	img.fill_rect(Rect2i(7, 4, 4, 1), lo)
	# 2-4: strip twisting (wide, diagonal, thin)
	img.fill_rect(Rect2i(12, 2, 6, 2), hi)
	img.fill_rect(Rect2i(12, 3, 6, 1), lo)
	for i in 5:
		img.set_pixel(19 + i, 4 - i, hi)
		img.set_pixel(19 + i, 5 - i, lo)
	img.fill_rect(Rect2i(26, 0, 1, 6), hi)
	img.fill_rect(Rect2i(27, 1, 1, 4), lo)
	# 5: dot / circle
	img.fill_rect(Rect2i(31, 1, 3, 4), hi)
	img.fill_rect(Rect2i(30, 2, 5, 2), hi)
	img.fill_rect(Rect2i(33, 3, 1, 2), lo)
	return img


func _sparkle() -> Image:
	var img := _img(36, 9)
	var c := Vector2i(4, 4)
	# frame 0: dot
	img.set_pixel(c.x, c.y, Color.WHITE)
	# frame 1: small cross
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		img.set_pixel(9 + c.x + d.x, c.y + d.y, Color.WHITE)
	# frame 2: 4-point star
	_star(img, 18 + c.x, c.y, 4, 1.0)
	# frame 3: fading star
	_star(img, 27 + c.x, c.y, 3, 0.55)
	return img


func _star(img: Image, cx: int, cy: int, r: int, a: float) -> void:
	for i in range(-r, r + 1):
		var fade := 1.0 - absf(i) / float(r + 1) * 0.6
		img.set_pixel(cx + i, cy, Color(1, 1, 1, a * fade))
		img.set_pixel(cx, cy + i, Color(1, 1, 1, a * fade))
	for d in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		img.set_pixel(cx + d.x, cy + d.y, Color(1, 1, 1, a * 0.6))
	img.set_pixel(cx, cy, Color(1, 1, 1, a))


func _burst() -> Image:
	var n := 96
	var img := _img(n, n)
	var c := Vector2(n / 2.0, n / 2.0)
	for y in n:
		for x in n:
			var v := Vector2(x + 0.5, y + 0.5) - c
			var r := v.length() / (n / 2.0)
			if r > 1.0:
				continue
			var ang := fposmod(v.angle(), TAU / 12.0) / (TAU / 12.0)
			var ray := ang < 0.42
			var a := 0.0
			if ray:
				a = (1.0 - r) * 0.9
			a += maxf(0.0, 0.35 - r) * 1.2   # core glow
			# Quantize alpha into 4 steps for a pixel-art look, dithered at the seams.
			var q := floorf(a * 4.0 + (0.25 if (x + y) % 2 == 0 else -0.25)) / 4.0
			if q > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, clampf(q, 0.0, 1.0)))
	return img


func _ring() -> Image:
	var n := 48
	var img := _img(n, n)
	var c := Vector2(n / 2.0, n / 2.0)
	for y in n:
		for x in n:
			var r := (Vector2(x + 0.5, y + 0.5) - c).length()
			var d := absf(r - 17.0)
			var a := 0.0
			if d < 1.5:
				a = 1.0
			elif d < 3.0:
				a = 0.55
			elif d < 5.0:
				a = 0.25 if (x + y) % 2 == 0 else 0.12
			elif d < 7.0 and (x + y) % 2 == 0:
				a = 0.08
			if a > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, a))
	return img
