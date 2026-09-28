class_name Fx
extends RefCounted
## Juice helpers shared by every screen: pops, pulses, count-ups, shakes, pixel particle
## bursts, confetti and flying coins. All tween/CPUParticles2D based (Compatibility-safe).


## Quick scale pop (Control pivot is centered first).
static func pop(c: CanvasItem, amount := 1.25, dur := 0.28) -> Tween:
	if c is Control:
		(c as Control).pivot_offset = (c as Control).size * 0.5
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(amount, amount), dur * 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE, dur * 0.65).set_trans(Tween.TRANS_QUAD)
	return tw


## Endless gentle breathing (badges, claimable things, the PLAY button).
static func pulse(c: Control, amount := 1.08, period := 0.9) -> Tween:
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween().set_loops()
	tw.tween_property(c, "scale", Vector2(amount, amount), period * 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(c, "scale", Vector2.ONE, period * 0.5).set_trans(Tween.TRANS_SINE)
	c.resized.connect(func() -> void: c.pivot_offset = c.size * 0.5)
	return tw


## Counts a label from `from` to `to` (formatted with CoinPill.fmt), ticking a sound.
static func count_up(label: Label, from: int, to: int, dur := 0.8, prefix := "", suffix := "", sound := true) -> Tween:
	var last := [from]
	var step := maxi(1, absi(to - from) / 8)
	var setter := func(v: float) -> void:
		var n := int(roundf(v))
		if not is_instance_valid(label):
			return
		label.text = prefix + CoinPill.fmt(n) + suffix
		if sound and n / step != int(last[0]) / step:
			Sfx.play("tick")
		last[0] = n
	var tw := label.create_tween()
	tw.tween_method(setter, float(from), float(to), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return tw


## Positional shake of a Control / Node2D around its current position.
static func shake(c: CanvasItem, strength := 4.0, dur := 0.35) -> void:
	var base: Vector2 = c.get("position")
	var tw := c.create_tween()
	var steps := int(dur / 0.03)
	for i in steps:
		var k := 1.0 - float(i) / steps
		tw.tween_property(c, "position", base + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * k, 0.03)
	tw.tween_property(c, "position", base, 0.03)


## One-shot burst of chunky pixel particles at `pos` (parent coordinates).
static func burst(parent: Node, pos: Vector2, color: Color, amount := 24, speed := 90.0, life := 0.8,
		px := 2.0, gravity := 120.0, spread := 180.0) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = life
	p.spread = spread
	p.direction = Vector2(0, -1)
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, gravity)
	p.damping_min = 10.0
	p.damping_max = 40.0
	p.scale_amount_min = px
	p.scale_amount_max = px + 1.0
	p.color = color
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	p.z_index = 20
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


## Fireworks: several bursts in random colors around `rect` over `dur` seconds.
static func fireworks(parent: Node, rect: Rect2, colors: Array, count := 6, dur := 1.6) -> void:
	for i in count:
		var t := parent.get_tree().create_timer(dur * float(i) / count)
		t.timeout.connect(func() -> void:
			if not is_instance_valid(parent):
				return
			var at := rect.position + Vector2(randf() * rect.size.x, randf() * rect.size.y)
			var c: Color = colors[randi() % colors.size()]
			burst(parent, at, c, 40, 110.0, 1.0, 2.0, 60.0)
			burst(parent, at, Color.WHITE, 10, 60.0, 0.5, 1.0, 30.0)
			Sfx.play("firework"))


## Confetti raining down across `width` from y = top.
static func confetti(parent: Node, width: float, colors: Array, amount := 60, top := -4.0) -> void:
	for c in colors:
		var p := CPUParticles2D.new()
		p.position = Vector2(width * 0.5, top)
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = Vector2(width * 0.5, 2)
		p.one_shot = true
		p.explosiveness = 0.6
		p.amount = maxi(4, amount / colors.size())
		p.lifetime = 2.4
		p.direction = Vector2(0, 1)
		p.spread = 25.0
		p.initial_velocity_min = 20.0
		p.initial_velocity_max = 60.0
		p.gravity = Vector2(0, 40)
		p.angular_velocity_min = -200
		p.angular_velocity_max = 200
		p.scale_amount_min = 2.0
		p.scale_amount_max = 3.0
		p.color = c
		p.z_index = 20
		parent.add_child(p)
		p.emitting = true
		p.finished.connect(p.queue_free)


## Coins that pop out of `from` and fly into `to` (viewport coords under `layer`).
## `on_arrive` is called once per coin (e.g. to bump the counter).
static func fly_coins(layer: Control, from: Vector2, to: Vector2, n := 10, on_arrive := Callable()) -> void:
	for i in n:
		var coin := TextureRect.new()
		coin.texture = UiSkin.coin_tex()
		coin.size = Vector2(7, 7)
		coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		coin.z_index = 30
		var start := from - layer.global_position - Vector2(3.5, 3.5)
		coin.position = start
		layer.add_child(coin)
		var out := start + Vector2(randf_range(-26, 26), randf_range(-24, 4))
		var tw := coin.create_tween()
		tw.tween_interval(i * 0.035)
		tw.tween_property(coin, "position", out, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(coin, "position", to - layer.global_position - Vector2(3.5, 3.5), 0.35 + randf() * 0.1) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			coin.queue_free()
			if i % 2 == 0:
				Sfx.play("coin_tick")
			if on_arrive.is_valid():
				on_arrive.call())


## Full-rect color flash on `layer` that fades out.
static func flash(layer: Control, color: Color, dur := 0.35) -> void:
	var r := ColorRect.new()
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.z_index = 25
	layer.add_child(r)
	var tw := r.create_tween()
	tw.tween_property(r, "color:a", 0.0, dur)
	tw.tween_callback(r.queue_free)
