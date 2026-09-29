class_name WeatherFx
extends CanvasLayer
## Night, rain, snow and fog for a match: a world tint (CanvasModulate) plus a screen-space layer
## of falling rain / drifting snow / fog banks, and stadium floodlight glows at night. Sits above
## the field and below the HUD. Cosmetic only (GameConditions holds the gameplay effect).

var conditions: Dictionary = {}
var _tint: CanvasModulate
var _fx: _Fx


func setup(p_conditions: Dictionary, world_parent: Node) -> void:
	conditions = p_conditions
	layer = 5
	var night := str(conditions.get("time", "day")) == "night"
	var weather := str(conditions.get("weather", "clear"))
	var col := Color.WHITE
	if night:
		col = Color(0.52, 0.58, 0.84)
	match weather:
		"rain":
			col = col * Color(0.86, 0.9, 0.98)
		"snow":
			col = col.lerp(Color(1.0, 1.0, 1.08), 0.5) * Color(0.98, 1.0, 1.06)
		"fog":
			col = col.lerp(Color(0.9, 0.93, 0.98), 0.4)
	if col != Color.WHITE:
		_tint = CanvasModulate.new()
		_tint.color = col
		world_parent.add_child(_tint)
	_fx = _Fx.new()
	_fx.kind = weather
	_fx.night = night
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx)


func _exit_tree() -> void:
	if is_instance_valid(_tint):
		_tint.queue_free()


class _Fx:
	extends Control
	var kind := "clear"
	var night := false
	var _drops: Array[Vector3] = []   # x, y, speed
	var _t := 0.0

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 12
		var n := 0
		match kind:
			"rain":
				n = 190
			"snow":
				n = 90
		for i in n:
			_drops.append(Vector3(rng.randf() * 700.0, rng.randf() * 300.0, rng.randf_range(0.7, 1.3)))
		set_process(kind in ["rain", "snow", "fog"] or night)

	func _process(delta: float) -> void:
		_t += delta
		var w := maxf(size.x, 480.0)
		var h := maxf(size.y, 270.0)
		for i in _drops.size():
			var d := _drops[i]
			if kind == "rain":
				d.y += 260.0 * d.z * delta
				d.x -= 70.0 * d.z * delta
			else:
				d.y += 30.0 * d.z * delta
				d.x += sin(_t * 1.3 + i) * 12.0 * delta
			if d.y > h + 6.0:
				d.y = -6.0
			if d.x < -6.0:
				d.x = w + 6.0
			if d.x > w + 6.0:
				d.x = -6.0
			_drops[i] = d
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		match kind:
			"rain":
				draw_rect(Rect2(0, 0, w, h), Color(0.05, 0.1, 0.2, 0.10))
				for d in _drops:
					var p := Vector2(d.x, d.y).round()
					var rc := Color(0.82, 0.9, 1.0, 0.8)
					draw_rect(Rect2(p.x, p.y, 1, 4), rc)
					draw_rect(Rect2(p.x - 1, p.y + 4, 1, 4), Color(rc, 0.6))
			"snow":
				draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.07))
				for d in _drops:
					var p := Vector2(d.x, d.y).round()
					var s := 2.0 if d.z > 1.0 else 1.0
					draw_rect(Rect2(p, Vector2(s, s)), Color(1, 1, 1, 0.85))
			"fog":
				draw_rect(Rect2(0, 0, w, h), Color(0.86, 0.9, 0.95, 0.20))
				for i in 5:
					var y := h * (0.1 + 0.2 * i) + sin(_t * 0.35 + i) * 10.0
					draw_rect(Rect2(0, y, w, 26.0), Color(0.9, 0.93, 0.98, 0.10))
		if night:
			# Floodlights: warm glows in the corners and a soft vignette.
			for corner in [Vector2(0, 0), Vector2(w, 0)]:
				for k in 5:
					draw_circle(corner + Vector2(sign(w * 0.5 - corner.x) * 26.0, 18.0), 90.0 - k * 16.0, Color(1.0, 0.95, 0.72, 0.035))
			for k in 6:
				var m := 6.0 * k
				draw_rect(Rect2(m, m, w - m * 2.0, h - m * 2.0), Color(0, 0, 0.06, 0.05), false, 6.0)
