class_name CrowdView
extends Node2D
## Stands beyond both sidelines (animated fans in team colors: home crowd left of midfield,
## away crowd right) plus the sideline team areas: benches and idle players in uniform.

const FRAME_TIME := 0.28
const SIDELINE_PX := 12.0   ## team area between the stands and the sideline

var home_tiles: Array[ImageTexture] = []
var away_tiles: Array[ImageTexture] = []
var home_colors: Dictionary = {}
var away_colors: Dictionary = {}
var _frame := 0
var _t := 0.0


func setup(home: Dictionary, away: Dictionary) -> void:
	home_colors = home
	away_colors = away
	home_tiles = StadiumArt.build_crowd(home.get("primary", Color.RED), home.get("secondary", Color.WHITE), 11)
	away_tiles = StadiumArt.build_crowd(away.get("primary", Color.BLUE), away.get("secondary", Color.WHITE), 29)
	for c in get_children():
		c.queue_free()
	_spawn_sideline(home, 30.0, 52.0, 1)
	_spawn_sideline(away, 68.0, 90.0, 2)
	queue_redraw()


## A handful of idle players in uniform along the top sideline between two yard lines.
func _spawn_sideline(colors: Dictionary, from_x: float, to_x: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := 6
	for i in n:
		var s := AnimatedSprite2D.new()
		s.sprite_frames = PlayerSprites.frames()
		s.centered = false
		s.offset = PlayerSprites.OFFSET
		s.material = PlayerSprites.make_material(colors, seed_value * 31 + i)
		var x := lerpf(from_x, to_x, (i + rng.randf_range(0.1, 0.9)) / n)
		s.position = FieldProjection.to_screen(Vector2(x, -0.9 - rng.randf_range(0.0, 0.4))).round()
		s.flip_h = rng.randf() < 0.5
		s.play("idle")
		s.frame = rng.randi() % 2
		s.speed_scale = rng.randf_range(0.6, 1.2)
		add_child(s)


func _process(delta: float) -> void:
	_t += delta
	if _t >= FRAME_TIME:
		_t = 0.0
		_frame = (_frame + 1) % StadiumArt.CROWD_FRAMES
		queue_redraw()


func _ready() -> void:
	# Stands, border and sideline sit behind the field layer (FieldView draws the chain
	# crew and goalposts over them).
	show_behind_parent = true


func _draw() -> void:
	var world := FieldProjection.world_rect()
	var field_h := FieldGeo.WIDTH * FieldProjection.PX_Y
	draw_rect(world, FieldView.BORDER)
	draw_rect(Rect2(world.position.x, -SIDELINE_PX, world.size.x, SIDELINE_PX), FieldView.TRACK)
	draw_rect(Rect2(world.position.x, field_h, world.size.x, SIDELINE_PX), FieldView.TRACK)
	if home_tiles.is_empty():
		return
	var mid_x := FieldProjection.to_screen(Vector2(FieldGeo.LENGTH * 0.5, 0)).x
	var field_bottom := FieldGeo.WIDTH * FieldProjection.PX_Y
	var h := float(StadiumArt.CROWD_H)
	var top_y := world.position.y
	var bottom_y := world.end.y - h
	# Stands: home crowd left of midfield, away crowd right, top and bottom.
	for y in [top_y, bottom_y]:
		draw_texture_rect(home_tiles[_frame], Rect2(world.position.x, y, mid_x - world.position.x, h), true)
		draw_texture_rect(away_tiles[_frame], Rect2(mid_x, y, world.end.x - mid_x, h), true)
		# Stadium wall in front of the stands.
		var wall_y: float = y + h if y == top_y else y - 3.0
		draw_rect(Rect2(world.position.x, wall_y, world.size.x, 3), Color("#10141f"))
		draw_rect(Rect2(world.position.x, wall_y + (0.0 if y == top_y else 2.0), world.size.x, 1), Color("#29366f"))
	# Team benches on the top sideline.
	_bench(30.0, 52.0, home_colors)
	_bench(68.0, 90.0, away_colors)
	# Bottom sideline: a camera cart track.
	draw_rect(Rect2(world.position.x, field_bottom + 6.0, world.size.x, 1), Color(0, 0, 0, 0.25))


func _bench(from_x: float, to_x: float, colors: Dictionary) -> void:
	var a := FieldProjection.to_screen(Vector2(from_x, 0))
	var b := FieldProjection.to_screen(Vector2(to_x, 0))
	var y := -SIDELINE_PX + 1.0
	draw_rect(Rect2(a.x, y, b.x - a.x, 4), Color(0, 0, 0, 0.3))
	draw_rect(Rect2(a.x, y, b.x - a.x, 2), colors.get("primary", Color.RED).darkened(0.2))
	draw_rect(Rect2(a.x, y + 2, b.x - a.x, 1), colors.get("secondary", Color.WHITE).darkened(0.3))
