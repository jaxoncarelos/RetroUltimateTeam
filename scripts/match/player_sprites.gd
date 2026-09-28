class_name PlayerSprites
extends RefCounted
## Builds the shared SpriteFrames from the template sheet and per-player palette materials.

const SHEET := "res://art/players/player_template.png"
const SHADER := "res://art/shaders/palette_swap.gdshader"
const FRAME := Vector2i(16, 20)
## name -> [frame indices, fps, loop]
const ANIMS := {
	"idle": [[0, 1], 2.0, true],
	"run": [[2, 3, 4, 5], 10.0, true],
	"throw": [[6, 7], 8.0, false],
	"dive": [[8, 9], 8.0, false],
	"down": [[10], 1.0, false],
	"celebrate": [[11, 12], 4.0, true],
	"block": [[13], 1.0, false],
}
const SKIN_TONES := [Color("#8d5524"), Color("#c68642"), Color("#e0ac69"), Color("#5c3a21"), Color("#a86b3c")]

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
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(idx * FRAME.x, 0, FRAME.x, FRAME.y)
				_frames.add_frame(anim_name, at)
	return _frames


static func make_material(colors: Dictionary, skin_seed: int) -> ShaderMaterial:
	if _shader == null:
		_shader = load(SHADER)
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("primary", colors.get("primary", Color.RED))
	m.set_shader_parameter("secondary", colors.get("secondary", Color.WHITE))
	m.set_shader_parameter("helmet", colors.get("helmet", colors.get("primary", Color.RED)))
	m.set_shader_parameter("pants", colors.get("pants", Color.WHITE))
	m.set_shader_parameter("skin", SKIN_TONES[absi(skin_seed) % SKIN_TONES.size()])
	return m
