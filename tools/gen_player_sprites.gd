extends SceneTree
## Generates the player sprite sheet (original art, color-keyed for palette swap).
## Run:  godot --headless --path . --script res://tools/gen_player_sprites.gd
## Output: res://art/players/player_template.png
##
## LAYOUT: one row of FW x FH (28x26) frames, facing right. The feet touch row GROUND (24),
## horizontally centered on column 14, so the sprite offset is (-14, -24) (PlayerSprites.OFFSET).
##   0 idle0   1 idle1   2-7 run0..run5   8 throw0 (wind-up)  9 throw1 (release)
##  10 throw2 (follow-through)  11 dive0 (launch)  12 dive1 (flat, airborne)  13 down (lying)
##  14 cel0   15 cel1   16 block0  17 block1  18 stance (pre-snap crouch)
## Frame order is mirrored in PlayerSprites.ANIMS.
##
## KEY COLORS (swapped by art/shaders/palette_swap.gdshader):
##   jersey primary FF0000 (shade 800000) · secondary 00FF00 (shade 008000)
##   helmet 0000FF (shade 000080, highlight 8080FF) · helmet stripe 00FFFF
##   pants FFFF00 (shade 808000) · skin FF00FF (shade 800080) · facemask 808080
##   visor band FF80FF (eye line inside the facemask: skin, or tinted by the player's visor)
## Everything else (outline, eyes, shoes) is a fixed color.
##
## The figure is a tiny rig: helmet and torso are hand-drawn stamps (ASCII below); arms and
## legs are 2-3 px limbs drawn between joints listed per frame. Lying frames render an upright
## pose and rotate it 90 degrees.

const FW := 28
const FH := 26
const GROUND := 24
const OUTLINE := Color8(20, 16, 24)

const PAL := {
	"R": Color8(255, 0, 0), "r": Color8(128, 0, 0),
	"G": Color8(0, 255, 0), "g": Color8(0, 128, 0),
	"H": Color8(0, 0, 255), "h": Color8(0, 0, 128), "W": Color8(128, 128, 255),
	"C": Color8(0, 255, 255),
	"Y": Color8(255, 255, 0), "y": Color8(128, 128, 0),
	"S": Color8(255, 0, 255), "s": Color8(128, 0, 128), "V": Color8(255, 128, 255),
	"M": Color8(128, 128, 128),
	"E": Color8(26, 22, 30), "D": Color8(40, 36, 48),
	"K": Color8(30, 28, 38), "k": Color8(232, 232, 236),
}

## Side-view helmet facing right: crown stripe, shine, ear hole, face opening and facemask.
const HEAD := [
	"..CCCC..",
	".HHHHWH.",
	"HHHHHHHH",
	"hHHHHVVM",
	".hHHHSEM",
	"..hhhMM.",
]
## Shoulder pads + jersey (three-quarter view) with a number patch and shoulder stripes.
const TORSO := [
	".rRRRRRRRR.",
	"rRGRRRRRRGR",
	"rRGRRGGGRRR",
	".rRRRGgGRr.",
	".rRRRGGGRr.",
	"..rRRRRRRr.",
	"...rrRRRr..",
]
const PELVIS := [
	"yYYYYYYY",
	"yYYYYYYY",
]

## Default placements (bob 0): torso top-left, head relative to torso, hip, shoulders.
const TORSO_AT := Vector2i(8, 10)
const HEAD_REL := Vector2i(2, -5)

var img: Image
var ox := 0


func _init() -> void:
	var names := ["idle0", "idle1", "run0", "run1", "run2", "run3", "run4", "run5",
			"throw0", "throw1", "throw2", "dive0", "dive1", "down", "cel0", "cel1",
			"block0", "block1", "stance"]
	img = Image.create(FW * names.size(), FH, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in names.size():
		ox = i * FW
		var frame := _frame(names[i])
		_outline(frame)
		img.blit_rect(frame, Rect2i(0, 0, FW, FH), Vector2i(ox, 0))
	DirAccess.make_dir_recursive_absolute("res://art/players")
	var err := img.save_png("res://art/players/player_template.png")
	print("player_template.png saved (%d frames), err=%d" % [names.size(), err])
	quit()


## Pose fields (all optional): bob (int, body shift down), lean (int, head/torso shift
## forward), crouch (hip drop), legs [[knee, ankle] back, [knee, ankle] front] relative to the
## hip, arms [[elbow, hand] back, [elbow, hand] front] relative to the shoulders.
func _frame(n: String) -> Image:
	var L_STAND := [[Vector2i(-1, 3), Vector2i(-2, 5)], [Vector2i(1, 3), Vector2i(2, 5)]]
	var A_DOWN := [[Vector2i(-1, 3), Vector2i(-1, 5)], [Vector2i(1, 3), Vector2i(1, 5)]]
	match n:
		"idle0":
			return _upright({"legs": L_STAND, "arms": A_DOWN})
		"idle1":
			return _upright({"bob": 1, "legs": _bent(L_STAND),
					"arms": [[Vector2i(-1, 2), Vector2i(-1, 4)], [Vector2i(1, 2), Vector2i(1, 4)]]})
		"run0", "run1", "run2", "run3", "run4", "run5":
			return _run(int(n.substr(3)))
		"throw0":
			return _upright({"lean": -1, "legs": [[Vector2i(-2, 3), Vector2i(-3, 5)], [Vector2i(2, 3), Vector2i(3, 5)]],
					"arms": [[Vector2i(2, 2), Vector2i(4, 1)], [Vector2i(-3, -1), Vector2i(-4, -4)]]})
		"throw1":
			return _upright({"lean": 1, "legs": [[Vector2i(-2, 3), Vector2i(-4, 5)], [Vector2i(2, 3), Vector2i(3, 5)]],
					"arms": [[Vector2i(-2, 2), Vector2i(-3, 4)], [Vector2i(2, -3), Vector2i(4, -5)]]})
		"throw2":
			return _upright({"lean": 2, "bob": 1, "legs": [[Vector2i(-2, 2), Vector2i(-4, 4)], [Vector2i(2, 2), Vector2i(3, 4)]],
					"arms": [[Vector2i(-2, 2), Vector2i(-3, 4)], [Vector2i(3, 1), Vector2i(5, 3)]]})
		"dive0":
			return _upright({"lean": 3, "bob": 2, "legs": [[Vector2i(-2, 2), Vector2i(-5, 3)], [Vector2i(2, 1), Vector2i(1, 3)]],
					"arms": [[Vector2i(3, 0), Vector2i(6, -1)], [Vector2i(3, 1), Vector2i(6, 0)]]})
		"dive1":
			return _lying({"legs": [[Vector2i(-1, 3), Vector2i(-1, 6)], [Vector2i(0, 3), Vector2i(1, 6)]],
					"arms": [[Vector2i(0, -3), Vector2i(1, -6)], [Vector2i(1, -3), Vector2i(2, -6)]]}, GROUND - 5)
		"down":
			return _lying({"legs": [[Vector2i(-1, 3), Vector2i(-1, 6)], [Vector2i(1, 3), Vector2i(1, 6)]],
					"arms": [[Vector2i(0, 3), Vector2i(1, 5)], [Vector2i(0, 3), Vector2i(-1, 5)]]}, GROUND)
		"cel0":
			return _upright({"legs": L_STAND,
					"arms": [[Vector2i(-2, -2), Vector2i(-2, -5)], [Vector2i(2, -2), Vector2i(3, -5)]]})
		"cel1":
			return _upright({"bob": -2, "legs": [[Vector2i(-1, 2), Vector2i(-2, 4)], [Vector2i(1, 3), Vector2i(1, 5)]],
					"arms": [[Vector2i(-2, -3), Vector2i(-3, -6)], [Vector2i(2, -3), Vector2i(3, -6)]]})
		"block0":
			return _upright({"lean": 2, "bob": 1, "legs": [[Vector2i(-2, 2), Vector2i(-4, 4)], [Vector2i(2, 2), Vector2i(3, 4)]],
					"arms": [[Vector2i(2, 1), Vector2i(5, 0)], [Vector2i(3, 1), Vector2i(6, 1)]]})
		"block1":
			return _upright({"lean": 2, "bob": 1, "legs": [[Vector2i(-2, 2), Vector2i(-3, 4)], [Vector2i(2, 2), Vector2i(4, 4)]],
					"arms": [[Vector2i(3, 0), Vector2i(5, -1)], [Vector2i(2, 1), Vector2i(5, 2)]]})
		"stance":
			return _upright({"lean": 2, "bob": 3, "legs": [[Vector2i(-2, 1), Vector2i(-3, 2)], [Vector2i(3, 0), Vector2i(2, 2)]],
					"arms": [[Vector2i(1, 2), Vector2i(2, 3)], [Vector2i(2, 2), Vector2i(3, 3)]]})
	return Image.create(FW, FH, false, Image.FORMAT_RGBA8)


## Six-frame run: legs cycle half a phase apart, arms swing against the legs, body bobs on
## the compressed contact frames.
func _run(i: int) -> Image:
	# [knee, ankle] per phase for one leg (0 = reaching forward, 3 = trailing behind).
	var legs := [
		[Vector2i(2, 2), Vector2i(4, 5)],
		[Vector2i(2, 2), Vector2i(1, 4)],
		[Vector2i(0, 3), Vector2i(-2, 4)],
		[Vector2i(-1, 3), Vector2i(-4, 3)],
		[Vector2i(-1, 2), Vector2i(-3, 1)],
		[Vector2i(3, 1), Vector2i(2, 3)],
	]
	var arm_fwd := [Vector2i(1, 2), Vector2i(3, 1)]
	var arm_mid := [Vector2i(0, 3), Vector2i(1, 4)]
	var arm_back := [Vector2i(-1, 2), Vector2i(-3, 3)]
	var arms_cycle := [arm_back, arm_mid, arm_fwd, arm_fwd, arm_mid, arm_back]
	var front: Array = legs[i]
	var back: Array = legs[(i + 3) % 6]
	var bob: int = [0, 1, 0, 0, 1, 0][i]
	var front_arm: Array = arms_cycle[i]
	var back_arm: Array = arms_cycle[(i + 3) % 6]
	var lift := 0
	# Feet never go below the ground: shift the whole pose up when needed.
	return _upright({"bob": bob - lift, "lean": 1, "legs": [back, front], "arms": [back_arm, front_arm]})


func _bent(legs: Array) -> Array:
	var out := []
	for l in legs:
		out.append([l[0] + Vector2i(0, 0), l[1] + Vector2i(0, -1)])
	return out


func _upright(p: Dictionary) -> Image:
	var bob: int = p.get("bob", 0)
	var lean: int = p.get("lean", 0)
	var t := TORSO_AT + Vector2i(lean / 2, bob)
	var hd := t + HEAD_REL + Vector2i(lean - lean / 2, 0)
	var hip := Vector2i(t.x + 5, GROUND - 6 + bob)
	var sh_back := t + Vector2i(1, 2)
	var sh_front := t + Vector2i(9, 2)
	var legs: Array = p.get("legs", [])
	var arms: Array = p.get("arms", [])
	# The head gets its own outline so it separates from the shoulders even when helmet and
	# jersey share a color; the final pass in _init outlines the whole silhouette.
	var f := _blank()
	if arms.size() == 2:
		_arm(f, sh_back, arms[0], true)
	if legs.size() == 2:
		_leg(f, hip + Vector2i(-1, 0), legs[0], true)
	_stamp(f, PELVIS, hip + Vector2i(-4, -1))
	if legs.size() == 2:
		_leg(f, hip + Vector2i(1, 0), legs[1], false)
	_stamp(f, TORSO, t)
	var head := _blank()
	_stamp(head, HEAD, hd)
	_layer(f, head)
	if arms.size() == 2:
		_arm(f, sh_front, arms[1], false)
	return f


func _blank() -> Image:
	var f := Image.create(FW, FH, false, Image.FORMAT_RGBA8)
	f.fill(Color(0, 0, 0, 0))
	return f


## Outlines a part and composites it over the frame (its outline covers what is beneath).
func _layer(f: Image, part: Image) -> void:
	_outline(part)
	f.blend_rect(part, Rect2i(0, 0, FW, FH), Vector2i.ZERO)


## Upright pose rotated 90 degrees clockwise (head to the right, face down), bottom at y.
func _lying(p: Dictionary, bottom: int) -> Image:
	var up := _upright(p)
	var used := up.get_used_rect()
	var body := up.get_region(used)
	body.rotate_90(CLOCKWISE)
	var f := Image.create(FW, FH, false, Image.FORMAT_RGBA8)
	f.fill(Color(0, 0, 0, 0))
	var at := Vector2i((FW - body.get_width()) / 2, bottom + 1 - body.get_height())
	f.blend_rect(body, Rect2i(Vector2i.ZERO, body.get_size()), at)
	return f


func _stamp(f: Image, rows: Array, at: Vector2i) -> void:
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			if PAL.has(ch):
				_px(f, at.x + x, at.y + y, PAL[ch])


func _px(f: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and x < FW and y >= 0 and y < FH:
		f.set_pixel(x, y, c)


## Thick line: stamps a w x w square along a -> b; color_at(t) picks the color per step.
func _limb(f: Image, a: Vector2i, b: Vector2i, w: int, colors: Array, split := 1.0) -> void:
	var d := Vector2(b - a)
	var n := int(maxf(absf(d.x), absf(d.y))) * 2 + 1
	for s in n + 1:
		var tt := float(s) / float(n)
		var q := (Vector2(a) + d * tt).round()
		var c: Color = colors[0] if tt < split else colors[1]
		for yy in w:
			for xx in w:
				_px(f, int(q.x) - w / 2 + xx, int(q.y) - w / 2 + yy, c)


func _leg(f: Image, hip: Vector2i, spec: Array, back: bool) -> void:
	var knee: Vector2i = hip + spec[0]
	var ankle: Vector2i = hip + spec[1]
	var pants: Color = PAL["y"] if back else PAL["Y"]
	var sock: Color = PAL["r"] if back else PAL["R"]
	_limb(f, hip, knee, 3, [pants, pants])
	_limb(f, knee, ankle, 2, [pants, sock], 0.3)
	# Cleat, toe forward; white sole flash on the front foot.
	for x in range(-1, 3):
		_px(f, ankle.x + x, ankle.y + 1, PAL["K"])
	_px(f, ankle.x - 1, ankle.y, PAL["K"])
	if not back:
		_px(f, ankle.x, ankle.y + 1, PAL["k"])


func _arm(f: Image, shoulder: Vector2i, spec: Array, back: bool) -> void:
	var elbow: Vector2i = shoulder + spec[0]
	var hand: Vector2i = shoulder + spec[1]
	var sleeve: Color = PAL["r"] if back else PAL["R"]
	var skin: Color = PAL["s"] if back else PAL["S"]
	_limb(f, shoulder, elbow, 2, [sleeve, skin], 0.55)
	_limb(f, elbow, hand, 2, [skin, skin])


## Colored (non-outline) pixel.
func _solid(c: Color) -> bool:
	return c.a > 0.0 and not c.is_equal_approx(OUTLINE)


## 1-px dark outline around the silhouette (4-neighbourhood).
func _outline(f: Image) -> void:
	var src := f.duplicate() as Image
	for y in FH:
		for x in FW:
			if src.get_pixel(x, y).a > 0.0:
				continue   # already an outline or a colored pixel
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.x < FW and q.y >= 0 and q.y < FH and _solid(src.get_pixel(q.x, q.y)):
					f.set_pixel(x, y, OUTLINE)
					break
