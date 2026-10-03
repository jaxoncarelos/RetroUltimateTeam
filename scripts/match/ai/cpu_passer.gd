class_name CpuPasser
extends RefCounted
## CPU quarterback decision-making for one pass play: reads the progression one receiver
## at a time (read speed and perception noise from awareness), throws to the first open
## man, checks down under pressure, and throws it away (or eats the sack) when nothing is there.
## Call update() every physics frame while PlayRunner.qb_is_passer(); it throws via the runner.

const ORDER := ["WR1", "TE", "WR2", "RB"]

var ctx: PlayRunner
var rng: RandomNumberGenerator
var progression: Array[PlayerAgent] = []
var read_idx := 0
var read_timer := 0.0
var read_interval := 0.4
var noise := 1.0
var decided := false
## Road to Glory: the receiver this QB likes (your player, or the man your corner covers) is
## read first and judged `favor` yards more open; a CALL for the ball turns his eyes to him.
var favorite: PlayerAgent = null
var favor := 0.0


func _init(p_ctx: PlayRunner, p_rng: RandomNumberGenerator) -> void:
	ctx = p_ctx
	rng = p_rng
	var t := ctx.tuning
	var awr := ctx.qb.attr("awr")
	var smart := clampf((awr - 60.0) / 39.0, 0.0, 1.0)
	read_interval = lerpf(t.cpu_read_slow, t.cpu_read_fast, smart)
	noise = lerpf(t.cpu_read_noise, t.cpu_read_noise * 0.35, smart)
	for slot in ORDER:
		var a: PlayerAgent = ctx.off_slots.get(slot)
		if a != null and str(a.assignment.get("type", "")) == "route":
			progression.append(a)
	read_timer = read_interval


## Puts `a` first in the progression and adds `bonus` yards of openness to him.
func set_favorite(a: PlayerAgent, bonus: float) -> void:
	favorite = a
	favor = bonus
	if a != null and progression.has(a):
		progression.erase(a)
		progression.push_front(a)
		read_idx = 0


## Returns the throw it made ({receiver, target, openness}) or {}.
func update(dt: float) -> Dictionary:
	if decided or not ctx.qb_is_passer() or progression.is_empty():
		return {}
	var t := ctx.tuning
	var drop := float(ctx.qb.assignment.get("drop", 2.0))
	if ctx.play_time < t.cpu_min_throw_time + drop * 0.12:
		return {}
	read_timer -= dt
	var calling := favorite != null and ctx.ball_call_until > ctx.play_time and progression.has(favorite)
	if calling:
		read_idx = progression.find(favorite)   # he heard the call: eyes on your man
	elif read_timer <= 0.0:
		read_timer = read_interval
		read_idx = (read_idx + 1) % progression.size()
	ctx.qb_target_hint = progression[read_idx]
	var look := QBReadLogic.evaluate(ctx, progression[read_idx])
	if not look.is_empty() and progression[read_idx] == favorite:
		look["openness"] = float(look["openness"]) + favor + (0.6 if calling else 0.0)
		if favorite.human:
			# A hand-run route: the QB throws to the route he drew; wander off it and he hesitates.
			var off := ctx.route_offset(favorite)
			look["openness"] = float(look["openness"]) - clampf((off - t.rtg_off_route) / 3.0, 0.0, 1.0) * t.rtg_off_route_cost
	# A deep call is a shot: he waits for the deep man instead of dumping it short right away.
	var patient := ctx.off_play != null and ctx.off_play.category == "DEEP" and ctx.play_time < t.cpu_deep_patience
	var too_short := not look.is_empty() and float(look["target"].x) - ctx.los_x < t.cpu_deep_min_air
	if not look.is_empty() and not (patient and too_short) \
			and float(look["openness"]) + rng.randfn(0.0, noise) > t.cpu_open_threshold:
		return _throw(look)
	var pressured := ctx.pressure_on_qb() > 0.85
	if ctx.play_time > t.cpu_max_hold or (pressured and ctx.play_time > t.cpu_bail_time):
		var best := QBReadLogic.best_throw(ctx)
		if not best.is_empty() and float(best["openness"]) > t.cpu_checkdown_open:
			return _throw(best)
		if pressured or ctx.play_time > t.cpu_max_hold + 0.4:
			return _throw_away()
	return {}


func _throw(read: Dictionary) -> Dictionary:
	decided = true
	ctx.throw_ball(read["target"])
	return read


func _throw_away() -> Dictionary:
	decided = true
	var qb := ctx.qb
	var side := -2.0 if qb.field_pos.y < FieldGeo.CENTER_Y else FieldGeo.WIDTH + 2.0
	var target := Vector2(qb.field_pos.x + 12.0, side)
	ctx.throw_ball(target)
	return {"receiver": null, "target": target, "openness": -99.0}
