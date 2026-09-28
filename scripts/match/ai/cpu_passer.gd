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


## Returns the throw it made ({receiver, target, openness}) or {}.
func update(dt: float) -> Dictionary:
	if decided or not ctx.qb_is_passer() or progression.is_empty():
		return {}
	var t := ctx.tuning
	var drop := float(ctx.qb.assignment.get("drop", 2.0))
	if ctx.play_time < t.cpu_min_throw_time + drop * 0.12:
		return {}
	read_timer -= dt
	if read_timer <= 0.0:
		read_timer = read_interval
		read_idx = (read_idx + 1) % progression.size()
	var look := QBReadLogic.evaluate(ctx, progression[read_idx])
	if not look.is_empty() and float(look["openness"]) + rng.randfn(0.0, noise) > t.cpu_open_threshold:
		return _throw(look)
	var pressured := ctx.pressure_on_qb() > 0.85
	if ctx.play_time > t.cpu_max_hold or (pressured and ctx.play_time > t.cpu_min_throw_time + 0.6):
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
