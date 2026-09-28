class_name PlayerAgent
extends Node2D
## One player on the field. Custom kinematics in yard space; a Brain (or the human) sets
## desired_dir/throttle each frame, step() integrates, _process() renders.

enum Team { OFFENSE, DEFENSE }

var team := Team.OFFENSE
var slot := ""
var pos_code := ""
var display_name := ""
var jersey := 0
var attrs: Dictionary = {}
var assignment: Dictionary = {}

var field_pos := Vector2.ZERO
var start_pos := Vector2.ZERO
var velocity := Vector2.ZERO
var facing := 1.0
var z_height := 0.0

var max_speed := 7.0
var accel := 15.0
var reaction := 0.2

var brain: Brain
var human := false
var desired_dir := Vector2.ZERO
var throttle := 0.0
var speed_mult := 1.0

var engaged_with: PlayerAgent = null
var is_down := false
var stun := 0.0
var tackle_cd := 0.0
var block_cd := 0.0
var shed_timer := 0.0
var juke_timer := 0.0
var juke_cd := 0.0
var juke_dir := 0.0
var dive_timer := 0.0
var dive_recover := -1.0
var throw_anim := 0.0
var tackled_speed := 0.0   ## x speed at the moment of the tackle (fall-forward spot)
var jam_timer := 0.0   ## seconds of slowed release (press coverage)
var jump_timer := 0.0
var jump_target := Vector2.ZERO
var jump_started_at := -1.0   ## play_time of the last jump at the ball (-1 = none)
var celebrating := false
## Pre-snap crouch (linemen) until the ball is snapped (PlayRunner sets/clears it).
var in_stance := false

var highlight := false:
	set(v):
		if v != highlight:
			highlight = v
			queue_redraw()
## Retro Bowl-style field markers: a star under a receiver you can throw to, and a bobbing
## arrow over the ball carrier (alpha 0 = none).
var star := false:
	set(v):
		if v != star:
			star = v
			queue_redraw()
var arrow := Color(0, 0, 0, 0):
	set(v):
		if v != arrow:
			arrow = v
			queue_redraw()

var sprite: AnimatedSprite2D


func setup(p_team: int, p_slot: String, p_pos: String, p_attrs: Dictionary, t: GameplayTuning,
		colors: Dictionary, p_name := "", p_jersey := 0, p_look: Dictionary = {}) -> void:
	team = p_team
	slot = p_slot
	pos_code = p_pos
	attrs = p_attrs
	display_name = p_name
	jersey = p_jersey
	facing = 1.0 if team == Team.OFFENSE else -1.0
	max_speed = RatingModel.max_speed(t, attr("spd"))
	accel = RatingModel.acceleration(t, attr("acc"))
	reaction = RatingModel.reaction_delay(t, attr("awr"))
	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = PlayerSprites.frames()
	sprite.centered = false
	sprite.offset = PlayerSprites.OFFSET
	sprite.material = PlayerSprites.make_material(colors, hash(p_slot + p_name) + jersey, p_look)
	sprite.play("idle")
	add_child(sprite)


func attr(a: String) -> float:
	return float(attrs.get(a, 50))


func is_eligible() -> bool:
	return team == Team.OFFENSE and pos_code in ["WR", "TE", "RB"]


func can_act() -> bool:
	return not is_down and stun <= 0.0 and dive_timer <= 0.0


func move_to(target: Vector2, thr := 1.0, arrive := true) -> void:
	var d := target - field_pos
	var dist := d.length()
	if dist < 0.05:
		stop()
		return
	desired_dir = d / dist
	throttle = thr * (clampf(dist / 1.2, 0.0, 1.0) if arrive else 1.0)


func stop() -> void:
	desired_dir = Vector2.ZERO
	throttle = 0.0


func knock_down(duration := -1.0) -> void:
	## duration < 0 means down for the rest of the play.
	if duration < 0.0:
		is_down = true
	else:
		stun = maxf(stun, duration)
	engaged_with = null


## recover < 0: the diver stays down (a ball carrier's dive ends the play).
func start_dive(t: GameplayTuning, dir: Vector2, recover := -1.0) -> void:
	dive_timer = t.dive_time
	dive_recover = recover
	# A dive is a lunge: current running speed plus a burst, so it can close from behind.
	velocity = dir.normalized() * (velocity.length() + t.dive_distance / t.dive_time)
	engaged_with = null


## Defender leaps at a thrown ball (swat / pick attempt).
func start_jump(t: GameplayTuning, toward: Vector2) -> void:
	jump_timer = t.jump_time
	jump_target = toward


func start_juke(t: GameplayTuning, dir: float) -> bool:
	if juke_cd > 0.0 or not can_act():
		return false
	juke_timer = t.juke_time
	juke_cd = t.juke_cooldown
	juke_dir = signf(dir)
	return true


func step(dt: float, t: GameplayTuning) -> void:
	tackle_cd = maxf(0.0, tackle_cd - dt)
	block_cd = maxf(0.0, block_cd - dt)
	juke_cd = maxf(0.0, juke_cd - dt)
	throw_anim = maxf(0.0, throw_anim - dt)
	if is_down:
		velocity = velocity.move_toward(Vector2.ZERO, t.down_slide_decel * dt)
		field_pos += velocity * dt
		return
	if dive_timer > 0.0:
		dive_timer -= dt
		field_pos += velocity * dt
		z_height = 0.6 * sin(clampf(dive_timer / t.dive_time, 0.0, 1.0) * PI)
		if dive_timer <= 0.0:
			z_height = 0.0
			knock_down(dive_recover)
		return
	if stun > 0.0:
		stun -= dt
		velocity = velocity.move_toward(Vector2.ZERO, 20.0 * dt)
		field_pos += velocity * dt
		return
	if engaged_with != null:
		return
	var target_v := desired_dir * max_speed * throttle * speed_mult
	if jump_timer > 0.0:
		# The leap carries him toward the ball, ignoring his brain until he lands.
		jump_timer -= dt
		z_height = t.jump_height * sin(clampf(1.0 - jump_timer / t.jump_time, 0.0, 1.0) * PI)
		var to_ball := jump_target - field_pos
		target_v = to_ball.limit_length(max_speed * 0.9) if to_ball.length() > 0.2 else Vector2.ZERO
		velocity = target_v
		if jump_timer <= 0.0:
			z_height = 0.0
	if jam_timer > 0.0:
		jam_timer -= dt
		target_v *= t.press_jam_speed
	if juke_timer > 0.0:
		juke_timer -= dt
		target_v.y = juke_dir * t.juke_speed
		velocity.y = target_v.y
	velocity = velocity.move_toward(target_v, accel * dt)
	field_pos += velocity * dt
	if absf(velocity.x) > 0.4:
		facing = signf(velocity.x)


func _process(_delta: float) -> void:
	position = FieldProjection.to_screen(field_pos).round()
	sprite.position = FieldProjection.lift(z_height).round()
	sprite.flip_h = facing < 0.0
	var anim := "idle"
	if in_stance:
		anim = "stance"
	elif is_down or stun > 0.3:
		anim = "down"
	elif dive_timer > 0.0:
		anim = "dive"
	elif jump_timer > 0.0:
		anim = "celebrate"   # arms-up frames double as the leap
	elif throw_anim > 0.0:
		anim = "throw"
	elif celebrating:
		anim = "celebrate"
	elif engaged_with != null:
		anim = "block"
	elif velocity.length() > 0.6:
		anim = "run"
	if sprite.animation != anim:
		sprite.play(anim)
	sprite.speed_scale = clampf(velocity.length() / 6.0, 0.6, 1.6) if anim == "run" else 1.0
	if arrow.a > 0.0:
		queue_redraw()   # the carrier arrow bobs


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 6.0, Color(0, 0, 0, 0.3))
	if star:
		draw_colored_polygon(_star_points(12.0, 5.0), Color(1.0, 0.93, 0.15, 0.55))
		draw_polyline(_star_points(12.0, 5.0) + PackedVector2Array([_star_points(12.0, 5.0)[0]]),
				Color("#ffec27"), 1.0)
	if highlight:
		draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 24, Color("#ffec27"), 2.0)
	draw_set_transform(Vector2.ZERO)
	if arrow.a > 0.0:
		var bob := roundf(sin(Time.get_ticks_msec() / 120.0) * 1.5)
		var tip := Vector2(0, -30 + bob)
		var tri := PackedVector2Array([tip, tip + Vector2(-5, -6), tip + Vector2(5, -6)])
		draw_colored_polygon(tri, arrow)
		draw_polyline(tri + PackedVector2Array([tip]), Color("#141018"), 1.0)


static func _star_points(outer: float, inner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var r := outer if i % 2 == 0 else inner
		pts.append(Vector2.from_angle(-PI / 2.0 + i * PI / 5.0) * r)
	return pts
