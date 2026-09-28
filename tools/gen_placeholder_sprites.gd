extends SceneTree
## Generates the original placeholder player sprite sheet (color-keyed for palette swap).
## Run:  godot --headless --path . --script res://tools/gen_placeholder_sprites.gd
## Output: res://art/players/player_template.png — 16x20 frames in one row, facing right.
## Redraw frames in Pixelorama/Aseprite on the same grid; keep the key colors:
##   jersey primary FF0000 · jersey secondary 00FF00 · helmet 0000FF · pants FFFF00 · skin FF00FF

const FW := 16
const FH := 20
const PRIMARY := Color8(255, 0, 0)
const SECONDARY := Color8(0, 255, 0)
const HELMET := Color8(0, 0, 255)
const PANTS := Color8(255, 255, 0)
const SKIN := Color8(255, 0, 255)
const MASK := Color8(170, 170, 170)
const SHOE := Color8(34, 32, 52)
const OUTLINE := Color8(20, 16, 24)

## Frame order is mirrored in PlayerSprites.ANIMS.
const FRAMES := ["idle0", "idle1", "run0", "run1", "run2", "run3", "throw0", "throw1",
		"dive0", "dive1", "down", "cel0", "cel1", "block"]

var img: Image
var ox := 0


func _init() -> void:
	img = Image.create(FW * FRAMES.size(), FH, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in FRAMES.size():
		ox = i * FW
		_draw_frame(FRAMES[i])
		_outline_frame()
	DirAccess.make_dir_recursive_absolute("res://art/players")
	var err := img.save_png("res://art/players/player_template.png")
	print("player_template.png saved (%d frames), err=%d" % [FRAMES.size(), err])
	quit()


func _px(x: int, y: int, c: Color) -> void:
	if x >= 0 and x < FW and y >= 0 and y < FH:
		img.set_pixel(ox + x, y, c)


func _rect(x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(xx, yy, c)


func _draw_frame(name: String) -> void:
	match name:
		"idle0": _upright(0, [0, 0, 0, 0], "down")
		"idle1": _upright(1, [0, 0, 0, 0], "down")
		"run0": _upright(0, [2, -2, 0, 0], "swing_a")
		"run1": _upright(1, [1, 0, 0, 1], "down")
		"run2": _upright(0, [-2, 2, 0, 0], "swing_b")
		"run3": _upright(1, [0, 1, 1, 0], "down")
		"throw0": _upright(0, [1, -1, 0, 0], "throw_back")
		"throw1": _upright(0, [2, -2, 0, 0], "throw_fwd")
		"cel0": _upright(0, [0, 0, 0, 0], "up")
		"cel1": _upright(1, [-1, 1, 1, 0], "up")
		"block": _upright(1, [2, -1, 0, 0], "forward")
		"dive0": _flat(7, true)
		"dive1": _flat(13, true)
		"down": _flat(14, false)


## legs = [left_dx, right_dx, left_lift, right_lift]
func _upright(bob: int, legs: Array, arms: String) -> void:
	var b := bob
	# Helmet with facemask + face
	_rect(5, 1 + b, 6, 5, HELMET)
	_px(5, 1 + b, Color(0, 0, 0, 0))
	_px(10, 1 + b, Color(0, 0, 0, 0))
	_px(7, 1 + b, SECONDARY)
	_px(8, 1 + b, SECONDARY)
	_px(10, 3 + b, SKIN)
	_px(10, 4 + b, SKIN)
	_px(11, 3 + b, MASK)
	_px(11, 4 + b, MASK)
	# Neck + shoulder pads + jersey
	_rect(7, 6 + b, 2, 1, SKIN)
	_rect(3, 7 + b, 10, 1, PRIMARY)
	_px(3, 7 + b, SECONDARY)
	_px(12, 7 + b, SECONDARY)
	_rect(4, 8 + b, 8, 4, PRIMARY)
	_rect(7, 9 + b, 2, 2, SECONDARY)
	# Pants
	_rect(5, 12 + b, 6, 3, PANTS)
	# Legs
	_leg(5, int(legs[0]), int(legs[2]), b)
	_leg(9, int(legs[1]), int(legs[3]), b)
	# Arms
	match arms:
		"down":
			_rect(3, 8 + b, 1, 2, SKIN); _px(3, 10 + b, SKIN)
			_rect(12, 8 + b, 1, 2, SKIN); _px(12, 10 + b, SKIN)
		"swing_a":
			_px(3, 8 + b, SKIN); _px(2, 9 + b, SKIN)
			_px(12, 8 + b, SKIN); _px(13, 9 + b, SKIN)
		"swing_b":
			_px(3, 8 + b, SKIN); _px(4, 10 + b, SKIN)
			_px(12, 8 + b, SKIN); _px(11, 10 + b, SKIN)
		"throw_back":
			_px(3, 6 + b, SKIN); _px(2, 5 + b, SKIN); _px(2, 4 + b, SKIN)
			_px(12, 8 + b, SKIN); _px(13, 8 + b, SKIN)
		"throw_fwd":
			_px(12, 6 + b, SKIN); _px(13, 5 + b, SKIN); _px(14, 4 + b, SKIN)
			_px(3, 8 + b, SKIN); _px(3, 9 + b, SKIN)
		"up":
			_px(3, 6 + b, SKIN); _px(3, 5 + b, SKIN); _px(3, 4 + b, SKIN)
			_px(12, 6 + b, SKIN); _px(12, 5 + b, SKIN); _px(12, 4 + b, SKIN)
		"forward":
			_px(12, 8 + b, SKIN); _px(13, 8 + b, SKIN); _px(14, 8 + b, SKIN)
			_px(12, 9 + b, SKIN); _px(13, 9 + b, SKIN)


func _leg(hip_x: int, dx: int, lift: int, b: int) -> void:
	# Two-pixel-wide leg from the hip (row 15) to the foot, leaning by dx; sock above the shoe.
	var top := 15 + b
	var foot_y := 18 - lift
	for y in range(top, foot_y + 1):
		var t := float(y - top) / maxf(1.0, float(foot_y - top))
		var x := hip_x + int(round(dx * t))
		var c := PANTS if y < foot_y else SECONDARY
		_px(x, y, c)
		_px(x + 1, y, c)
	var fx := hip_x + dx
	_px(fx, foot_y + 1, SHOE)
	_px(fx + 1, foot_y + 1, SHOE)
	_px(fx + 2, foot_y + 1, SHOE)


## Horizontal body (diving / lying), head to the right. h = top row.
func _flat(h: int, arms_forward: bool) -> void:
	_rect(11, h, 4, 4, HELMET)
	_px(11, h, Color(0, 0, 0, 0))
	_px(14, h + 2, SKIN)
	_px(15, h + 2, MASK)
	_px(12, h, SECONDARY)
	_rect(5, h + 1, 6, 3, PRIMARY)
	_rect(7, h + 1, 2, 2, SECONDARY)
	_rect(2, h + 2, 3, 2, PANTS)
	_px(1, h + 2, SKIN)
	_px(0, h + 3, SHOE)
	_px(1, h + 3, SHOE)
	if arms_forward:
		_px(15, h + 1, SKIN)
		_px(15, h + 0, SKIN)
	else:
		_px(9, h + 4, SKIN)
		_px(10, h + 4, SKIN)


func _outline_frame() -> void:
	var solid := {}
	for y in FH:
		for x in FW:
			if img.get_pixel(ox + x, y).a > 0.0:
				solid[Vector2i(x, y)] = true
	for y in FH:
		for x in FW:
			if solid.has(Vector2i(x, y)):
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if solid.has(Vector2i(x, y) + d):
					img.set_pixel(ox + x, y, OUTLINE)
					break
