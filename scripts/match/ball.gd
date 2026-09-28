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


## Point on the arc at normalized time u (0..1): Vector3(x, y, z).
static func arc_point(p_from: Vector2, p_to: Vector2, p_apex: float, u: float) -> Vector3:
	var g := p_from.lerp(p_to, u)
	var h := lerpf(RELEASE_Z, CATCH_Z, u) + 4.0 * p_apex * u * (1.0 - u)
	return Vector3(g.x, g.y, h)


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
	position = FieldProjection.to_screen(field_pos).round()
	z_index = 1 if state == State.HELD else 0
	queue_redraw()


func _draw() -> void:
	var lift := FieldProjection.lift(z).round()
	if state == State.AIR:
		draw_rect(Rect2(-2, -1, 4, 2), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(lift.x - 2, lift.y - 2, 5, 3), Color("#7a3b17"))
	draw_rect(Rect2(lift.x - 1, lift.y - 2, 3, 1), Color("#a8582a"))
	draw_rect(Rect2(lift.x, lift.y - 1, 1, 1), Color.WHITE)
