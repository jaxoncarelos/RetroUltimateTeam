class_name ArtGen
extends RefCounted
## Code-generated original pixel art shared by the UI (cards, matchup screens, title).
## CONTRACT (used by UI code): keep these signatures stable; results are cached textures.
## STUB: placeholder shapes until the art pass replaces the internals.

static var _cache: Dictionary = {}


## Head-and-shoulders card portrait, 32x32 px, transparent background.
## colors = TeamData.uniform_colors() ({primary, secondary, helmet, pants}).
static func portrait(player_id: String, pos: String, colors: Dictionary, jersey: int) -> Texture2D:
	var key := "p:%s:%s:%d" % [player_id, pos, jersey]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(10, 4, 12, 12), Color("#c68642"))
	img.fill_rect(Rect2i(6, 18, 20, 14), colors.get("primary", Color.RED))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Side-view team helmet, 64x48 px, facing right unless facing_left. No logos: team colors
## plus an original stripe/shape pattern.
static func helmet(team_abbr: String, colors: Dictionary, facing_left := false) -> Texture2D:
	var key := "h:%s:%s" % [team_abbr, facing_left]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(64, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(8, 6, 44, 36), colors.get("helmet", Color.RED))
	if facing_left:
		img.flip_x()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Full title-screen backdrop (stadium, sky, crowd), sized to the 480x270 canvas.
static func title_backdrop() -> Texture2D:
	if _cache.has("title"):
		return _cache["title"]
	var img := Image.create(480, 270, false, Image.FORMAT_RGBA8)
	img.fill(Color("#3a7bd5"))
	img.fill_rect(Rect2i(0, 190, 480, 80), Color("#2f8a3a"))
	var tex := ImageTexture.create_from_image(img)
	_cache["title"] = tex
	return tex
