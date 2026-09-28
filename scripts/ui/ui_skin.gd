class_name UiSkin
extends RefCounted
## Retro-arcade UI look, all generated in code: palette, 9-slice button/panel textures,
## the tiled emblem background, pixel icons (home, gear, info, crown, coin…), stars and
## outlined text. Everything is our own art (an original shield-and-football emblem).

# ---------------------------------------------------------------- palette
const BLUE := Color("#2b5fe0")          ## screen background (center)
const BLUE_DARK := Color("#1d43b8")     ## screen background (edges)
const BLUE_LINE := Color("#7aa2ff")     ## thin highlight lines on the background
const NAVY := Color("#18216b")          ## buttons
const NAVY_HI := Color("#26349a")       ## hover / alternate rows
const NAVY_DEEP := Color("#0f165a")
const PANEL := Color("#152078")         ## framed panels
const ROW := Color("#1c2c8e")           ## list row highlight
const BORDER := Color("#e8eeff")
const SHADOW := Color("#070b2e")
const YELLOW := Color("#ffd21f")
const YELLOW_DARK := Color("#b88a00")
const WHITE := Color("#f6f8ff")
const MUTED := Color("#93a6e8")
const GREY := Color("#6f7aa6")
const STAR_BLUE := Color("#62ccff")
const STAR_RED := Color("#ff4d5e")
const STAR_EMPTY := Color("#0b1447")
const COIN := Color("#ffcf40")
const GREEN := Color("#3fe071")
const RED := Color("#ff2e57")
const BAR_BG := Color("#05081f")

# ---------------------------------------------------------------- bitmaps
## Our emblem: a shield with a star over a football (15x16).
const EMBLEM := [
	"ooooooooooooooo",
	"owwwwwwwwwwwwwo",
	"ownnnnnnnnnnnwo",
	"ownnnnnwnnnnnwo",
	"ownnnnwwwnnnnwo",
	"ownwwwwwwwwwnwo",
	"ownnwwwwwwwnnwo",
	"ownnnwwwwwnnnwo",
	"ownnwwnnnwwnnwo",
	"owrrrrrrrrrrrwo",
	"owrrkkkkkkkrrwo",
	".owkkwkwkwkkwo.",
	"..owrkkkkkrwo..",
	"...owrrrrrwo...",
	"....owwwwwo....",
	".....ooooo.....",
]
const EMBLEM_PAL := {"o": Color("#070b2e"), "w": Color("#f6f8ff"), "n": Color("#1b2a8a"), "r": Color("#e02a44"),
		"k": Color("#8a4a22")}

const ICONS := {
	"home": [
		".....x.....",
		"....xxx....",
		"...xxxxx...",
		"..xxxxxxx..",
		".xxxxxxxxx.",
		"xxxxxxxxxxx",
		".xxxxxxxxx.",
		".xxx...xxx.",
		".xxx...xxx.",
		".xxx...xxx.",
	],
	"gear": [
		"....xx....",
		".x.xxxx.x.",
		"..xxxxxx..",
		".xxx..xxx.",
		"xxx....xxx",
		"xxx....xxx",
		".xxx..xxx.",
		"..xxxxxx..",
		".x.xxxx.x.",
		"....xx....",
	],
	"info": [
		".xxxxxxx.",
		"x.......x",
		"x...x...x",
		"x.......x",
		"x..xx...x",
		"x...x...x",
		"x...x...x",
		"x..xxx..x",
		".xxxxxxx.",
	],
	"back": [
		"...x.....",
		"..xx.....",
		".xxxxxxxx",
		"xxxxxxxxx",
		".xxxxxxxx",
		"..xx.....",
		"...x.....",
	],
	"crown": [
		"x...x...x",
		"xx.xxx.xx",
		"xxxxxxxxx",
		"xxdxxxdxx",
		"xxxxxxxxx",
		".........",
		"xxxxxxxxx",
	],
	"lock": [
		"..xxx..",
		".x...x.",
		".x...x.",
		"xxxxxxx",
		"xxxdxxx",
		"xxxdxxx",
		"xxxxxxx",
	],
	"trophy": [
		"xxxxxxxxx",
		"x.xxxxx.x",
		"x.xxxxx.x",
		".xxxxxxx.",
		"..xxxxx..",
		"...xxx...",
		"....x....",
		"...xxx...",
		"..xxxxx..",
	],
	"cards": [
		"...xxxxxx",
		"...x....x",
		"xxxxxx..x",
		"x....x..x",
		"x....x..x",
		"x....x..x",
		"x....xxxx",
		"x....x...",
		"xxxxxx...",
	],
	"ball": [
		"...xxxxx...",
		".xxxxxxxxx.",
		"xxxx.x.xxxx",
		"xxx.....xxx",
		"xxxx.x.xxxx",
		".xxxxxxxxx.",
		"...xxxxx...",
	],
	"pause": [
		"xx..xx",
		"xx..xx",
		"xx..xx",
		"xx..xx",
		"xx..xx",
		"xx..xx",
		"xx..xx",
	],
	"play": [
		"x.....",
		"xxx...",
		"xxxxx.",
		"xxxxxx",
		"xxxxx.",
		"xxx...",
		"x.....",
	],
	"check": [
		"......x",
		".....xx",
		"x...xx.",
		"xx.xx..",
		".xxx...",
		"..x....",
	],
	"calendar": [
		".x...x.",
		"xxxxxxx",
		"x.....x",
		"x.x.x.x",
		"x.....x",
		"x.x.x.x",
		"xxxxxxx",
	],
	"flame": [
		"...x...",
		"..xx...",
		"..xxx.x",
		".xxxxxx",
		"xxxdxxx",
		"xxdddxx",
		".xxdxx.",
	],
	"face": [
		".xxxxx.",
		"xxxxxxx",
		"xdxxxdx",
		"xxxxxxx",
		"xdxxxdx",
		"xxdddxx",
		".xxxxx.",
	],
}

const STAR := [
	"...x...",
	"...x...",
	"xxxxxxx",
	".xxxxx.",
	"..xxx..",
	".xx.xx.",
	"xx...xx",
]

const COIN_BMP := [
	".ooooo.",
	"oyyyyyo",
	"oywyydo",
	"oyyyydo",
	"oyyyydo",
	"odddddo",
	".ooooo.",
]

## Small side-view helmet (14x11), facing right: h = shell, s = team mark, m = facemask.
const MINI_HELMET := [
	"....oooooo....",
	"..oohhhhhhoo..",
	".ohhhhhhhhhho.",
	"ohhhhsshhhhhho",
	"ohhhssssshhhho",
	"ohhhhsshhhhmmm",
	"ohhhhhhhhhmo.m",
	".ohhhhhhhhmmmm",
	"..ohhhoohhmo.m",
	"...oo..oohmmm.",
	"........oo....",
]

static var _tex: Dictionary = {}


## Texture from a bitmap: each char maps to a palette color ("." = transparent; "x" white
## by default so the texture can be tinted with modulate).
static func bitmap(key: String, rows: Array, pal: Dictionary = {}) -> ImageTexture:
	if _tex.has(key):
		return _tex[key]
	var w := 0
	for r in rows:
		w = maxi(w, (r as String).length())
	var img := Image.create(maxi(w, 1), maxi(rows.size(), 1), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in rows.size():
		var line: String = rows[y]
		for x in line.length():
			var ch := line[x]
			if ch == "." or ch == " ":
				continue
			var c: Color = pal.get(ch, Color.WHITE if ch == "x" else Color(0.55, 0.55, 0.6))
			img.set_pixel(x, y, c)
	var t := ImageTexture.create_from_image(img)
	_tex[key] = t
	return t


static func icon(name: String) -> ImageTexture:
	return bitmap("icon_" + name, ICONS.get(name, ICONS["info"]), {"d": Color(0, 0, 0, 0.45)})


static func emblem() -> ImageTexture:
	return bitmap("emblem", EMBLEM, EMBLEM_PAL)


static func star_tex() -> ImageTexture:
	return bitmap("star", STAR)


static func coin_tex() -> ImageTexture:
	return bitmap("coin", COIN_BMP, {"o": Color("#6b4a00"), "y": COIN, "w": Color("#fff6c0"), "d": Color("#d69a10")})


static func mini_helmet(key: String, shell: Color, mark: Color, facing_left := false) -> ImageTexture:
	var k := "mh_%s_%s" % [key, facing_left]
	if _tex.has(k):
		return _tex[k]
	var rows: Array = []
	for r in MINI_HELMET:
		rows.append((r as String).reverse() if facing_left else r)
	var t := bitmap(k, rows, {"o": Color("#070b2e"), "h": shell, "s": mark, "m": Color("#c9ced8")})
	return t


## Tile for the screen background: two faint emblems (staggered) and a fine dither.
static func bg_tile() -> ImageTexture:
	if _tex.has("bg_tile"):
		return _tex["bg_tile"]
	var w := 96
	var h := 80
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			if (x + y) % 4 == 0:
				img.set_pixel(x, y, Color(0, 0, 0.1, 0.07))
	var faint := Color(1, 1, 1, 0.07)
	var edge := Color(0.02, 0.05, 0.3, 0.12)
	for spot in [Vector2i(8, 6), Vector2i(56, 46)]:
		for y in EMBLEM.size():
			var line: String = EMBLEM[y]
			for x in line.length():
				var ch := line[x]
				if ch == ".":
					continue
				var c := edge if ch == "o" else faint
				for dy in 2:
					for dx in 2:
						var px: int = (spot.x + x * 2 + dx) % w
						var py: int = (spot.y + y * 2 + dy) % h
						img.set_pixel(px, py, c)
	var t := ImageTexture.create_from_image(img)
	_tex["bg_tile"] = t
	return t


# ---------------------------------------------------------------- 9-slice boxes

## Chunky button: 1px light border, fill, 2px dark drop shadow to the lower left.
## `pressed` draws the body shifted onto its shadow.
static func button_tex(fill: Color, border: Color, pressed := false) -> ImageTexture:
	var key := "btn_%s_%s_%s" % [fill.to_html(), border.to_html(), pressed]
	if _tex.has(key):
		return _tex[key]
	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var body := Rect2i(1, 2, 10, 10) if pressed else Rect2i(2, 0, 10, 10)
	if not pressed:
		img.fill_rect(Rect2i(0, 2, 10, 10), SHADOW)
	img.fill_rect(body, border)
	img.fill_rect(body.grow(-1), fill)
	# Top inner highlight for a little depth.
	img.fill_rect(Rect2i(body.position.x + 1, body.position.y + 1, body.size.x - 2, 1), fill.lightened(0.12))
	# Rounded corners (1px).
	for c in [body.position, Vector2i(body.end.x - 1, body.position.y), Vector2i(body.position.x, body.end.y - 1),
			body.end - Vector2i.ONE]:
		img.set_pixel(c.x, c.y, Color(0, 0, 0, 0) if pressed else img.get_pixel(c.x, c.y))
	var t := ImageTexture.create_from_image(img)
	_tex[key] = t
	return t


static func button_box(fill: Color, border: Color, pressed := false) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = button_tex(fill, border, pressed)
	sb.texture_margin_left = 3
	sb.texture_margin_right = 3
	sb.texture_margin_top = 3
	sb.texture_margin_bottom = 3
	sb.content_margin_left = 6
	sb.content_margin_right = 4
	sb.content_margin_top = 3 if not pressed else 5
	sb.content_margin_bottom = 5 if not pressed else 3
	return sb


## Framed panel: navy fill, 1px light border with cut corners.
static func panel_tex(fill: Color, border: Color) -> ImageTexture:
	var key := "pnl_%s_%s" % [fill.to_html(), border.to_html()]
	if _tex.has(key):
		return _tex[key]
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(border)
	img.fill_rect(Rect2i(1, 1, 6, 6), fill)
	for c in [Vector2i(0, 0), Vector2i(7, 0), Vector2i(0, 7), Vector2i(7, 7)]:
		img.set_pixel(c.x, c.y, Color(0, 0, 0, 0))
	var t := ImageTexture.create_from_image(img)
	_tex[key] = t
	return t


static func panel_box(fill := PANEL, border := BORDER, pad := 4) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = panel_tex(fill, border)
	sb.texture_margin_left = 2
	sb.texture_margin_right = 2
	sb.texture_margin_top = 2
	sb.texture_margin_bottom = 2
	sb.set_content_margin_all(pad)
	return sb


# ---------------------------------------------------------------- draw helpers

## Text with a 1-pixel (per font scale) outline and an optional drop shadow.
static func draw_text(ci: CanvasItem, pos: Vector2, text: String, size: int, color: Color,
		outline := Color(0, 0, 0, 0), shadow := Color(0, 0, 0, 0)) -> void:
	var font := PixelFont.get_font()
	var px := float(maxi(1, size / 8))
	if shadow.a > 0.0:
		for o in [Vector2(0, 2), Vector2(-1, 2), Vector2(1, 2)]:
			ci.draw_string(font, pos + o * px, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, shadow)
	if outline.a > 0.0:
		for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1), Vector2(-1, -1), Vector2(1, 1),
				Vector2(-1, 1), Vector2(1, -1)]:
			ci.draw_string(font, pos + o * px, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## Centered variant: `center_x` is the horizontal middle, `baseline_y` the text baseline.
static func draw_text_c(ci: CanvasItem, center_x: float, baseline_y: float, text: String, size: int, color: Color,
		outline := Color(0, 0, 0, 0), shadow := Color(0, 0, 0, 0)) -> void:
	var w := PixelFont.text_width(text, size)
	draw_text(ci, Vector2(roundf(center_x - w * 0.5), baseline_y), text, size, color, outline, shadow)


## Size-8 text centered on `center_x` that never exceeds `max_w`: switches to the condensed
## face (then cuts with ".") for long names. Optional 1 px drop shadow.
static func draw_text_fit(ci: CanvasItem, center_x: float, baseline_y: float, text: String, max_w: int, color: Color,
		shadow := Color(0, 0, 0, 0)) -> void:
	var f := PixelFont.fit(text, max_w)
	var x := roundf(center_x - float(f["width"]) * 0.5)
	if not f["condensed"]:
		if shadow.a > 0.0:
			ci.draw_string(PixelFont.get_font(), Vector2(x, baseline_y + 1), f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, shadow)
		ci.draw_string(PixelFont.get_font(), Vector2(x, baseline_y), f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, color)
		return
	if shadow.a > 0.0:
		PixelFont.draw_condensed(ci, Vector2(x, baseline_y - 6), f["text"], shadow)
	PixelFont.draw_condensed(ci, Vector2(x, baseline_y - 7), f["text"], color)


## A 7x7 pixel star (times `s`), `frac` 0..1 of it filled with `col` from the left.
static func draw_star(ci: CanvasItem, at: Vector2, col: Color, frac := 1.0, s := 1.0, empty := STAR_EMPTY,
		outline := Color(0.02, 0.03, 0.15, 1.0)) -> void:
	var tex := star_tex()
	var sz := Vector2(7, 7) * s
	for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		ci.draw_texture_rect(tex, Rect2(at + o * s, sz), false, outline)
	ci.draw_texture_rect(tex, Rect2(at, sz), false, empty)
	if frac >= 1.0:
		ci.draw_texture_rect(tex, Rect2(at, sz), false, col)
	elif frac > 0.0:
		var w := roundf(7.0 * frac)
		ci.draw_texture_rect_region(tex, Rect2(at, Vector2(w, 7) * s), Rect2(0, 0, w, 7), col)


static func draw_icon(ci: CanvasItem, name: String, at: Vector2, col := WHITE, s := 1.0, shadow := true) -> void:
	var tex := icon(name)
	var sz := tex.get_size() * s
	if shadow:
		ci.draw_texture_rect(tex, Rect2(at + Vector2(0, s), sz), false, Color(SHADOW, 0.8))
	ci.draw_texture_rect(tex, Rect2(at, sz), false, col)


static func draw_coin(ci: CanvasItem, at: Vector2, s := 1.0) -> void:
	ci.draw_texture_rect(coin_tex(), Rect2(at, Vector2(7, 7) * s), false)


## Framed box (panel look) drawn directly.
static func draw_frame(ci: CanvasItem, r: Rect2, fill := PANEL, border := BORDER) -> void:
	ci.draw_rect(r, border)
	ci.draw_rect(r.grow(-1), fill)
	for c in [r.position, Vector2(r.end.x - 1, r.position.y), Vector2(r.position.x, r.end.y - 1), r.end - Vector2.ONE]:
		ci.draw_rect(Rect2(c, Vector2.ONE), fill.darkened(0.5) if fill.a >= 1.0 else Color(0, 0, 0, 0))


## Yellow bar meter on black (Retro Bowl style), optional segment ticks.
static func draw_bar(ci: CanvasItem, r: Rect2, frac: float, col := YELLOW, segments := 0) -> void:
	ci.draw_rect(r, BORDER)
	ci.draw_rect(r.grow(-1), BAR_BG)
	var inner := r.grow(-2)
	var w := floorf(inner.size.x * clampf(frac, 0.0, 1.0))
	if w > 0.0:
		ci.draw_rect(Rect2(inner.position, Vector2(w, inner.size.y)), col)
		ci.draw_rect(Rect2(inner.position, Vector2(w, 1)), col.lightened(0.35))
	if segments > 1:
		for i in range(1, segments):
			var x := inner.position.x + floorf(inner.size.x * i / segments)
			ci.draw_rect(Rect2(x, inner.position.y, 1, inner.size.y), BAR_BG)


## OVR -> star rating (0.5 .. 5 in halves), Retro Bowl style.
static func ovr_stars(ovr: float) -> float:
	return clampf(roundf((ovr - 50.0) / 9.0 * 2.0) / 2.0, 0.5, 5.0)


## Big logo lettering rasterized from the pixel font: vertical fill gradient, an inner
## accent outline and a thick dark outline (title screen). `lines` are centered.
static func logo(lines: Array, px: int, fill_top: Color, fill_bottom: Color, accent: Color, outline: Color) -> ImageTexture:
	var key := "logo_%s_%d_%s" % ["|".join(lines), px, accent.to_html()]
	if _tex.has(key):
		return _tex[key]
	var pad := 3
	var line_h := PixelFont.GLYPH_H * px
	var gap := 2 * px
	var widest := 0
	for l in lines:
		widest = maxi(widest, PixelFont.text_width(l, 8) * px)
	var w := widest + pad * 2
	var h := lines.size() * line_h + (lines.size() - 1) * gap + pad * 2 + 2
	var mask := PackedByteArray()
	mask.resize(w * h)
	for li in lines.size():
		var text: String = lines[li]
		var x0 := pad + (widest - PixelFont.text_width(text, 8) * px) / 2
		var y0 := pad + li * (line_h + gap)
		var cx := x0
		for ch in text:
			if ch == " ":
				cx += 4 * px
				continue
			var g: Array = PixelFont.GLYPHS.get(ch.to_upper(), [])
			for gy in g.size():
				var row: String = g[gy]
				for gx in row.length():
					if row[gx] != "1":
						continue
					for yy in px:
						for xx in px:
							mask[(y0 + gy * px + yy) * w + cx + gx * px + xx] = 1
			cx += PixelFont.ADVANCE * px
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Thick outline (radius 3), accent ring (radius 1), then the gradient fill.
	for y in h:
		for x in w:
			if mask[y * w + x] == 1:
				continue
			var near := 99
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					if mask[ny * w + nx] == 1:
						near = mini(near, maxi(absi(dx), absi(dy)))
			if near <= 1:
				img.set_pixel(x, y, accent)
			elif near <= 3:
				img.set_pixel(x, y, outline)
	for li in lines.size():
		var y0 := pad + li * (line_h + gap)
		for y in range(y0, y0 + line_h):
			var u := float(y - y0) / line_h
			var c := fill_top.lerp(fill_bottom, u)
			if u > 0.55:
				c = c.darkened(0.12)
			for x in w:
				if mask[y * w + x] == 1:
					img.set_pixel(x, y, c)
	# Drop shadow under everything.
	var out := Image.create(w, h + 2, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.0:
				out.set_pixel(x, y + 2, Color(0, 0, 0, 0.45))
	out.blend_rect(img, Rect2i(0, 0, w, h), Vector2i.ZERO)
	var t := ImageTexture.create_from_image(out)
	_tex[key] = t
	return t
