class_name PlayerSprites
extends RefCounted
## Builds the shared SpriteFrames from the template sheet and per-player palette materials.
## Sheet layout and key colors are documented in tools/gen_player_sprites.gd.

const SHEET := "res://art/players/player_template.png"
const SHADER := "res://art/shaders/palette_swap.gdshader"
const FRAME := Vector2i(28, 26)
## Sprite offset (centered = false) that puts the feet on the node's origin.
const OFFSET := Vector2(-14, -24)
## name -> [frame indices, fps, loop]. "stance" is the pre-snap crouch (optional to use).
const ANIMS := {
	"idle": [[0, 0, 0, 1, 1, 1], 4.0, true],
	"run": [[2, 3, 4, 5, 6, 7], 14.0, true],
	"throw": [[8, 9, 10], 10.0, false],
	"dive": [[11, 12], 8.0, false],
	"down": [[13], 1.0, false],
	"celebrate": [[14, 15], 4.0, true],
	"block": [[16, 17], 5.0, true],
	"stance": [[18], 1.0, false],
}
const SKIN_TONES := [Color("#8d5524"), Color("#c68642"), Color("#e0ac69"), Color("#5c3a21"), Color("#a86b3c"), Color("#f1c27d")]

static var _frames: SpriteFrames
static var _shader: Shader


static func frames() -> SpriteFrames:
	if _frames == null:
		var tex: Texture2D = load(SHEET)
		_frames = SpriteFrames.new()
		_frames.remove_animation("default")
		for anim_name in ANIMS:
			var spec: Array = ANIMS[anim_name]
			_frames.add_animation(anim_name)
			_frames.set_animation_speed(anim_name, spec[1])
			_frames.set_animation_loop(anim_name, spec[2])
			for idx in spec[0]:
				_frames.add_frame(anim_name, frame_texture(idx, tex))
	return _frames


## One frame of the sheet as an AtlasTexture (e.g. frame 0 = standing idle for UI previews).
static func frame_texture(idx: int, tex: Texture2D = null) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = tex if tex != null else load(SHEET)
	at.region = Rect2(idx * FRAME.x, 0, FRAME.x, FRAME.y)
	return at


## look = PlayerData.look (optional): "skin" 1-6 picks the real player's tone (same scale as the
## card portraits, ArtGen.SKIN), "visor" ("clear"/"tinted") tints the eye line. Without it the
## skin is seeded from `skin_seed` (generated players, crowd).
static func make_material(colors: Dictionary, skin_seed: int, look: Dictionary = {}) -> ShaderMaterial:
	if _shader == null:
		_shader = load(SHADER)
	var m := ShaderMaterial.new()
	m.shader = _shader
	var primary: Color = colors.get("primary", Color.RED)
	var secondary: Color = colors.get("secondary", Color.WHITE)
	var helmet: Color = colors.get("helmet", primary)
	m.set_shader_parameter("primary", primary)
	m.set_shader_parameter("secondary", secondary)
	m.set_shader_parameter("helmet", helmet)
	m.set_shader_parameter("pants", colors.get("pants", Color.WHITE))
	m.set_shader_parameter("skin", skin_color(skin_seed, look))
	m.set_shader_parameter("visor", visor_color(str(look.get("visor", ""))))
	m.set_shader_parameter("stripe", colors.get("stripe", stripe_color(helmet, primary, secondary)))
	m.set_shader_parameter("mask", colors.get("mask", mask_color(helmet)))
	return m


## Field skin tone: the player's known tone (look.skin 1-6) or a seeded random one.
static func skin_color(skin_seed: int, look: Dictionary = {}) -> Color:
	var tone := int(look.get("skin", 0))
	if tone >= 1 and tone <= ArtGen.SKIN.size():
		return ArtGen.SKIN[tone - 1]
	return SKIN_TONES[absi(skin_seed) % SKIN_TONES.size()]


## Visor tint for the shader (alpha 0 = no visor).
static func visor_color(kind: String) -> Color:
	match kind:
		"tinted", "dark", "smoke":
			return Color(0.08, 0.08, 0.11, 1.0)
		"clear":
			return Color(0.78, 0.9, 1.0, 0.45)
		"":
			return Color(0, 0, 0, 0)
	return Color(0.35, 0.55, 0.85, 0.85)   # colored/mirrored visors


## Helmet stripe: the secondary color unless it disappears on the helmet, then the primary.
static func stripe_color(helmet: Color, primary: Color, secondary: Color) -> Color:
	if _dist(helmet, secondary) > 0.25:
		return secondary
	if _dist(helmet, primary) > 0.25:
		return primary
	return helmet.darkened(0.35) if helmet.get_luminance() > 0.5 else helmet.lightened(0.5)


## Gray facemask, darker on very light helmets so it still reads.
static func mask_color(helmet: Color) -> Color:
	return Color("#6b6f78") if helmet.get_luminance() > 0.7 else Color("#b8bcc4")


static func _dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
