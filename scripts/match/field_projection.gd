class_name FieldProjection
extends RefCounted
## Field yards -> screen pixels. The vertical axis is compressed for the retro side view,
## and height (z, yards) lifts sprites upward.

const PX_X := 12.0
const PX_Y := 6.0
const PX_Z := 6.0
const BORDER_YD := 4.0
## Extra sideline area so the HUD strips at the top/bottom never cover the field itself.
const BORDER_YD_Y := 7.0


static func to_screen(p: Vector2) -> Vector2:
	return Vector2(p.x * PX_X, p.y * PX_Y)


static func to_field(s: Vector2) -> Vector2:
	return Vector2(s.x / PX_X, s.y / PX_Y)


static func lift(z: float) -> Vector2:
	return Vector2(0.0, -z * PX_Z)


static func world_rect() -> Rect2:
	return Rect2(-BORDER_YD * PX_X, -BORDER_YD_Y * PX_Y,
			(FieldGeo.LENGTH + BORDER_YD * 2.0) * PX_X, (FieldGeo.WIDTH + BORDER_YD_Y * 2.0) * PX_Y)
