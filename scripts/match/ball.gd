class_name Ball
extends Node2D
## The football. Flight is a true x/y/z arc: ground position lerps, height is a parabola.

enum State { DEAD, HELD, AIR }

const HELD_Z := 1.3
const RELEASE_Z := 2.0
const CATCH_Z := 1.3

var state := State.DEAD
var carrier: PlayerAgent = null
var field_pos := Vector2.ZERO
var z := 0.0

var from := Vector2.ZERO
var to := Vector2.ZERO
var duration := 1.0
var apex := 1.0
var t := 0.0
## Recent screen-space offsets of the ball in flight (a short motion trail on lofted balls).
var _trail: Array[Vector2] = []


## Point on the arc at normalized time u (0..1): Vector3(x, y, z).
static func arc_point(p_from: Vector2, p_to: Vector2, p_apex: float, u: float) -> Vector3:
	var g := p_from.lerp(p_to, u)
	return Vector3(g.x, g.y, PassModel.height_at(p_apex, u))


func place(p: Vector2) -> void:
	state = State.DEAD
	carrier = null
	field_pos = p
	z = 0.2


func give_to(agent: PlayerAgent) -> void:
	state = State.HELD
	carrier = agent


func throw_to(p_from: Vector2, p_to: Vector2, p_duration: float, p_apex: float) -> void:
	state = State.AIR
	carrier = null
	from = p_from
	to = p_to
	duration = maxf(p_duration, 0.1)
	apex = p_apex
	t = 0.0
	field_pos = from
	z = RELEASE_Z


func time_left() -> float:
	return (1.0 - t) * duration if state == State.AIR else 0.0


## Advances flight. Returns true on the frame the ball reaches its target.
func step(dt: float) -> bool:
	match state:
		State.HELD:
			if carrier != null:
				field_pos = carrier.field_pos + Vector2(carrier.facing * 0.35, 0.05)
				z = HELD_Z + carrier.z_height
		State.AIR:
			t = minf(1.0, t + dt / duration)
			var p := arc_point(from, to, apex, t)
			field_pos = Vector2(p.x, p.y)
			z = p.z
			if t >= 1.0:
				return true
	return false


func _process(_delta: float) -> void:
	var screen := FieldProjection.to_screen(field_pos) + FieldProjection.lift(z)
	if state == State.AIR:
		_trail.push_front(screen)
		if _trail.size() > 5:
			_trail.pop_back()
	else:
		_trail.clear()
	position = FieldProjection.to_screen(field_pos).round()
	z_index = 1 if state == State.HELD else 0
	queue_redraw()


func _draw() -> void:
	var lift := FieldProjection.lift(z).round()
	if state == State.AIR:
		# Ground shadow: shrinks and fades as the ball climbs, so a lob's height reads clearly.
		var k := clampf(z / 12.0, 0.0, 1.0)
		var w := roundf(lerpf(5.0, 2.0, k))
		draw_rect(Rect2(-w * 0.5, -1, w, 2), Color(0, 0, 0, lerpf(0.4, 0.2, k)))
		# Motion trail (fading dots) so a high lob's path reads against the crowd and turf.
		if z > 3.0:
			for i in range(1, _trail.size()):
				var p := (_trail[i] - position).round()
				draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color(1, 0.95, 0.85, 0.75 - i * 0.13))
	# A high ball is "closer to the camera": one pixel bigger at the top of a lob.
	var big := 1.0 if z > 7.0 else 0.0
	if state == State.AIR:
		# Dark outline so the ball pops against turf and crowd.
		draw_rect(Rect2(lift.x - 3 - big, lift.y - 3 - big, 7 + big * 2.0, 5 + big), Color(0.08, 0.05, 0.03, 0.8))
	draw_rect(Rect2(lift.x - 2 - big, lift.y - 2 - big, 5 + big * 2.0, 3 + big), Color("#7a3b17"))
	draw_rect(Rect2(lift.x - 1 - big, lift.y - 2 - big, 3 + big, 1), Color("#a8582a"))
	draw_rect(Rect2(lift.x, lift.y - 1 - big, 1, 1), Color.WHITE)
