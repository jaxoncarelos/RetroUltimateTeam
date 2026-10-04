class_name CpuPasser
extends RefCounted
## The CPU quarterback's brain for one pass play (docs/AI_OVERHAUL_PLAN.md §1).
##  - Pre-snap: counts the rush against his protection -> a HOT read vs. an unblocked blitz.
##  - Progression built from the call: shot plays read deep -> short, everything else
##    intermediate -> short -> deep, the checkdown (backs / flats) last. His eyes move one
##    read at a time at a pace set by his awareness, and he only throws a route once it is
##    "ready" (its break, or its depth for verticals) - smart QBs a beat early (anticipation).
##  - Every look is judged by ThrowRisk: expected yards vs. the chance a defender gets there
##    first. He throws when the value clears a bar that drops the longer he holds it and the
##    more pressure he feels, but never above the INT risk his awareness accepts.
##  - Nothing there: check down when it's safe, throw it away under pressure, scramble when he
##    has the legs and the lane, or eat it.
## Road to Glory: `favorite` (your receiver, or the man your corner covers) is read first;
## a hand-run receiver needs a bigger window (the QB can't read your route), less when you CALL.
## Call update() every physics frame while PlayRunner.qb_is_passer(); it throws via the runner.

const EVAL_EVERY := 0.1

var ctx: PlayRunner
var rng: RandomNumberGenerator
var progression: Array[PlayerAgent] = []
var read_idx := 0
var read_timer := 0.0
var read_interval := 0.4
var noise := 1.0
var decided := false
var hot := false                     ## the rush outnumbers the protection
var max_int := 0.05                  ## the most INT risk he accepts on a throw
var favorite: PlayerAgent = null
var favor := 0.0
var last_eval: Dictionary = {}       ## the last look ({} = none), for debugging and tests
var thrown: Dictionary = {}          ## the throw he made (ThrowRisk result), {} = none / thrown away
var _eval_timer := 0.0


func _init(p_ctx: PlayRunner, p_rng: RandomNumberGenerator) -> void:
	ctx = p_ctx
	rng = p_rng
	var t := ctx.tuning
	var smart := _smart()
	read_interval = lerpf(t.cpu_read_slow, t.cpu_read_fast, smart)
	noise = lerpf(t.cpu_read_noise, t.cpu_read_noise * 0.35, smart)
	max_int = lerpf(t.qb_max_int_dumb, t.qb_max_int_smart, smart)
	var deep_call := ctx.off_play != null and ctx.off_play.category == "DEEP"
	var routes: Array[PlayerAgent] = []
	for o in ctx.offense:
		if o.is_eligible() and str(o.assignment.get("type", "")) == "route":
			routes.append(o)
	# Shot plays: deepest first. Otherwise intermediate first, short next, deep, checkdowns last.
	routes.sort_custom(func(a: PlayerAgent, b: PlayerAgent) -> bool:
		return _read_rank(a, deep_call) < _read_rank(b, deep_call))
	progression = routes
	read_timer = read_interval
	hot = _count_rushers() > _count_blockers()


func _smart() -> float:
	return clampf((ctx.qb.attr("awr") - 60.0) / 39.0, 0.0, 1.0)


## Order in the progression (lower = earlier).
func _read_rank(o: PlayerAgent, deep_call: bool) -> float:
	var depth := route_depth(o)
	var checkdown := o.pos_code == "RB" or depth < 4.0
	if checkdown:
		return 100.0 + depth
	if deep_call:
		return -depth
	return absf(depth - 12.0)   # the intermediate window first


## How far downfield a route goes (yards past his alignment).
static func route_depth(o: PlayerAgent) -> float:
	var path: PackedVector2Array = o.assignment.get("path", PackedVector2Array())
	var d := 0.0
	for p in path:
		d = maxf(d, p.x)
	return d if str(o.assignment.get("end", "continue")) == "sit" else maxf(d, 18.0 if d >= 10.0 else d)


func _count_rushers() -> int:
	var n := 0
	for d in ctx.defense:
		if d.brain is RushBrain:
			n += 1
	return n


func _count_blockers() -> int:
	var n := 0
	for o in ctx.offense:
		if o.brain is BlockBrain:
			n += 1
	return n


## Puts `a` first in the progression and adds `bonus` yards of value to him.
func set_favorite(a: PlayerAgent, bonus: float) -> void:
	favorite = a
	favor = bonus
	if a != null and progression.has(a):
		progression.erase(a)
		progression.push_front(a)
		read_idx = 0


## Is this receiver's route ready to be thrown (the break, or depth on a vertical)?
func is_ready(o: PlayerAgent) -> bool:
	var t := ctx.tuning
	if o.human or o.brain is FreeRunBrain:
		return ctx.play_time >= 0.9   # a hand-run route: whenever he's open
	if not (o.brain is RouteBrain):
		return true   # a back leaking out, a blocker who released: available
	var rb := o.brain as RouteBrain
	if rb.delay > 0.0:
		return false
	var early := t.qb_anticipation * _smart()
	if rb.idx >= 1 and rb.points.size() >= 2:
		# Past his first waypoint: the stem is done (anticipation lets a smart QB go a beat early).
		return true
	var first := rb.points[0] if not rb.points.is_empty() else o.start_pos
	var to_break := o.field_pos.distance_to(first) / maxf(o.max_speed, 1.0)
	if to_break <= early:
		return true
	return o.field_pos.x - ctx.los_x >= t.qb_ready_depth and rb.points.size() <= 1


## The bar a throw must clear right now (expected yards), lower with time and pressure.
func min_value() -> float:
	var t := ctx.tuning
	var k := clampf(ctx.play_time / t.qb_patience, 0.0, 1.0)
	var bar := lerpf(t.qb_min_value_start, t.qb_min_value_end, k)
	return bar * (1.0 - 0.7 * ctx.pressure_on_qb())


## INT risk he accepts now (more when trailing late: desperate).
func int_cap() -> float:
	return max_int * (ctx.tuning.qb_desperate_mult if bool(ctx.get_meta("desperate", false)) else 1.0)


## Judges a throw to `o` (ThrowRisk, plus the RTG favorite's bonus / hand-run slop).
func look_at(o: PlayerAgent) -> Dictionary:
	var t := ctx.tuning
	var slop := 0.0
	var calling := o == favorite and ctx.ball_call_until > ctx.play_time
	if o.human or o.brain is FreeRunBrain:
		slop = t.qb_human_slop - (t.qb_call_slop if calling else 0.0)
		# Off the drawn route he can't be read at all: a bigger window still.
		slop += clampf((ctx.route_offset(o) - t.rtg_off_route) / 3.0, 0.0, 1.0) * t.rtg_off_route_cost
	var e := ThrowRisk.best_for(ctx, o, slop)
	if e.is_empty():
		return e
	var v := float(e["value"]) + rng.randfn(0.0, noise)
	if o == favorite:
		v += favor + (0.8 if calling else 0.0)
	e["score"] = v
	return e


func _ok(e: Dictionary, bar: float) -> bool:
	var min_comp := ctx.tuning.qb_min_comp * (0.6 if bool(ctx.get_meta("desperate", false)) else 1.0)
	if e.is_empty():
		return false
	var t := ctx.tuning
	# A shot play is a shot: no dump-off in the first seconds unless he's about to get hit.
	if ctx.off_play != null and ctx.off_play.category == "DEEP" and ctx.play_time < t.cpu_deep_patience \
			and float((e["spot"] as Vector2).x) - ctx.los_x < t.cpu_deep_min_air and ctx.pressure_on_qb() < 0.8:
		return false
	return float(e["p_int"]) <= int_cap() and float(e["p_comp"]) >= min_comp and float(e["score"]) >= bar


## Returns the throw it made ({receiver, target, ...}) or {}.
func update(dt: float) -> Dictionary:
	if decided or not ctx.qb_is_passer() or progression.is_empty():
		return {}
	var t := ctx.tuning
	var drop := float(ctx.qb.assignment.get("drop", 2.0))
	var earliest := t.qb_hot_time if hot else t.cpu_min_throw_time + drop * 0.12
	# His eyes move through the progression (a CALL turns them to you).
	read_timer -= dt
	var calling := favorite != null and ctx.ball_call_until > ctx.play_time and progression.has(favorite)
	if calling:
		read_idx = progression.find(favorite)
	elif read_timer <= 0.0:
		read_timer = read_interval
		_next_read()
	ctx.qb_target_hint = progression[read_idx]
	if ctx.play_time < earliest:
		return {}
	_eval_timer -= dt
	if _eval_timer > 0.0:
		return {}
	_eval_timer = EVAL_EVERY
	var bar := min_value()
	var pressure := ctx.pressure_on_qb()
	# 1) The receiver he's looking at.
	var cur := progression[read_idx]
	if is_ready(cur):
		last_eval = look_at(cur)
		if _ok(last_eval, bar):
			return _throw(last_eval)
	# 1b) His favorite (your RTG receiver): he keeps an eye on you all play long.
	if favorite != null and favorite != cur and progression.has(favorite) and is_ready(favorite):
		var f := look_at(favorite)
		if _ok(f, bar):
			return _throw(f)
	# 2) Late in the play or feeling it: anything safe that's there (the checkdown).
	if ctx.play_time > t.qb_patience * 0.75 or pressure > 0.55 or hot:
		var best := _best_ready()
		if _ok(best, minf(bar, t.qb_min_value_end)):
			return _throw(best)
	# 3) Nothing there.
	var out_of_time := ctx.play_time > t.cpu_max_hold + 1.2
	if (pressure >= t.qb_throwaway_pressure and ctx.play_time > earliest + 0.6) or out_of_time:
		if _can_scramble() and not out_of_time:
			decided = true
			ctx.start_scramble()
			return {"receiver": null, "scramble": true}
		if pressure >= t.qb_throwaway_pressure + 0.1 * (1.0 - _smart()) or out_of_time:
			return _throw_away()   # live for the next down
	return {}


## Next read: skip receivers who are covered up or not ready yet only after a look.
func _next_read() -> void:
	read_idx = (read_idx + 1) % progression.size()


## The best throw among receivers whose routes are ready.
func _best_ready() -> Dictionary:
	var best := {}
	for o in progression:
		if not is_ready(o):
			continue
		var e := look_at(o)
		if not _ok(e, -INF):
			continue
		if best.is_empty() or float(e["score"]) > float(best["score"]):
			best = e
	return best


## A mobile QB with grass in front of him takes off.
func _can_scramble() -> bool:
	var qb := ctx.qb
	if qb.attr("spd") < ctx.tuning.qb_scramble_speed:
		return false
	var ahead := qb.field_pos + Vector2(4.0, 0.0)
	for d in ctx.defense:
		if not d.is_down and d.engaged_with == null and d.field_pos.distance_to(ahead) < 3.0:
			return false
	return true


func _throw(e: Dictionary) -> Dictionary:
	decided = true
	thrown = e
	ctx.throw_ball(e["spot"])
	e["target"] = e["spot"]
	e["openness"] = float(e.get("adv", 0.0)) * 5.0
	return e


func _throw_away() -> Dictionary:
	decided = true
	var qb := ctx.qb
	var side := -4.0 if qb.field_pos.y < FieldGeo.CENTER_Y else FieldGeo.WIDTH + 4.0
	var target := Vector2(qb.field_pos.x + 12.0, side)
	ctx.throw_ball(target)
	return {"receiver": null, "target": target, "openness": -99.0, "throwaway": true}
