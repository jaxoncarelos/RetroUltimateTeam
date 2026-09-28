class_name PlayRunner
extends Node2D
## Runs one live play: spawns 18 agents from the play calls, ticks brains/contacts/ball,
## and emits play_ended(result) once the ball is dead.
##
## result = {type, spot_x, spot_y, yards, text, turnover}
##   type ∈ tackle, sack, out, incomplete, td, int, safety

signal play_ended(result: Dictionary)
signal carrier_changed(agent: PlayerAgent)
signal ball_thrown(target: Vector2)
## A tackle landed (for screen shake / sfx): where, and the carrier's speed.
signal big_hit(at: Vector2, speed: float)

enum Phase { IDLE, PRE_SNAP, LIVE, DEAD }

const DEAD_BALL_PAUSE := 0.9
const WATCHDOG_SECONDS := 15.0
const HANDOFF_RANGE := 1.8

var tuning: GameplayTuning
var def_ai: DefenseAITuning = DefenseAITuning.new()
## 0..1: how strongly the CPU defense is keyed on this offensive call (DefenseMemory).
## Set after setup_play(), before snap().
var key_level := 0.0
var rng := RandomNumberGenerator.new()
var phase := Phase.IDLE
## Team the human controls (PlayerAgent.Team), or -1 for none (autoplay / CPU vs CPU).
var human_team: int = PlayerAgent.Team.OFFENSE
## Object with apply(dt) that steers the human-controlled agent (HumanOffenseControl).
var human_input: Object = null

var actors: Node2D
var ball: Ball
var contact: ContactResolver

var agents: Array[PlayerAgent] = []
var offense: Array[PlayerAgent] = []
var defense: Array[PlayerAgent] = []
var off_slots: Dictionary = {}
var def_slots: Dictionary = {}
var off_play: PlayDef
var def_play: PlayDef
var off_colors: Dictionary = {}
var def_colors: Dictionary = {}

var los_x := 35.0
var ball_y := FieldGeo.CENTER_Y
var qb: PlayerAgent
var carrier: PlayerAgent
var controlled: PlayerAgent
var handoff_to: PlayerAgent
var handoff_mesh := Vector2.ZERO
var handoff_delay := 0.0
var handoff_range := HANDOFF_RANGE
## Remaining designed run lane for the current ball carrier (absolute field points).
var carrier_lane := PackedVector2Array()
var pass_thrown := false
var scrambling := false
var play_time := 0.0
var broken_tackles := 0
var fumbled := false
## Receiver the CPU QB is currently reading (DefenseSwitcher uses it pre-throw).
var qb_target_hint: PlayerAgent = null

var _pending_result: Dictionary = {}
var _dead_timer := 0.0


func _init() -> void:
	contact = ContactResolver.new(self)


func _ready() -> void:
	actors = Node2D.new()
	actors.name = "Actors"
	actors.y_sort_enabled = true
	add_child(actors)
	ball = Ball.new()
	ball.name = "Ball"
	actors.add_child(ball)


# ---------------------------------------------------------------- setup / snap

## Lineup dict: slot -> {"name": String, "jersey": int, "attrs": Dictionary}
func setup_play(p_off: PlayDef, p_def: PlayDef, p_los_x: float, p_ball_y: float,
		off_lineup: Dictionary, def_lineup: Dictionary) -> void:
	_clear()
	off_play = p_off
	def_play = p_def
	los_x = p_los_x
	ball_y = p_ball_y
	pass_thrown = false
	scrambling = false
	play_time = 0.0
	broken_tackles = 0
	carrier = null
	handoff_to = null
	key_level = 0.0
	handoff_delay = 0.0
	carrier_lane = PackedVector2Array()
	fumbled = false
	qb_target_hint = null
	_pending_result = {}

	var origin := Vector2(los_x, ball_y)
	for slot in p_off.formation.slots:
		var s: Dictionary = p_off.formation.slots[slot]
		var a := _spawn(PlayerAgent.Team.OFFENSE, slot, s["pos"], origin + s["at"], off_lineup.get(slot, {}), off_colors)
		a.assignment = p_off.assignments.get(slot, {"type": "block"})
		off_slots[slot] = a
		offense.append(a)
	for slot in p_def.formation.slots:
		var s: Dictionary = p_def.formation.slots[slot]
		var at: Vector2 = origin + s["at"]
		var asg: Dictionary = p_def.assignments.get(slot, {"type": "zone", "center": s["at"], "size": Vector2(8, 8)})
		var mark: String = asg.get("target", "") if asg.get("press", false) else ""
		if s.has("align") and off_slots.has(s["align"]):
			at.y = off_slots[s["align"]].field_pos.y
		if mark != "" and off_slots.has(mark):
			# Press: line up in the receiver's face.
			at = off_slots[mark].field_pos + Vector2(tuning.press_depth, 0.0)
		var a := _spawn(PlayerAgent.Team.DEFENSE, slot, s["pos"], at, def_lineup.get(slot, {}), def_colors)
		a.assignment = asg
		def_slots[slot] = a
		defense.append(a)

	qb = off_slots.get("QB")
	ball.place(origin)
	match human_team:
		PlayerAgent.Team.OFFENSE:
			_set_controlled(qb)
		PlayerAgent.Team.DEFENSE:
			_set_controlled(default_defender())
		_:
			_set_controlled(null)
	phase = Phase.PRE_SNAP


func _spawn(team: int, slot: String, pos: String, at: Vector2, info: Dictionary, colors: Dictionary) -> PlayerAgent:
	var a := PlayerAgent.new()
	var attrs: Dictionary = info.get("attrs", RatingModel.fill_attrs(pos, 70))
	a.setup(team, slot, pos, attrs, tuning, colors, info.get("name", slot), info.get("jersey", 0))
	a.field_pos = at
	a.start_pos = at
	a.name = "%s_%s" % ["O" if team == PlayerAgent.Team.OFFENSE else "D", slot]
	actors.add_child(a)
	agents.append(a)
	return a


func _clear() -> void:
	for a in agents:
		a.queue_free()
	agents.clear()
	offense.clear()
	defense.clear()
	off_slots.clear()
	def_slots.clear()
	controlled = null


func snap() -> void:
	if phase != Phase.PRE_SNAP:
		return
	phase = Phase.LIVE
	play_time = 0.0
	ball.give_to(qb)
	carrier = qb
	for a in agents:
		a.brain = _brain_for(a)
	_apply_presnap_reads()
	if is_run_play():
		contact.snap_engage()
	if str(qb.assignment.get("type", "")) == "sneak":
		scrambling = true
		var lane := PackedVector2Array()
		for p in qb.assignment.get("path", PackedVector2Array()):
			lane.append(qb.start_pos + p)
		_set_carrier(qb, lane)
	if key_level > 0.0:
		_cheat_zones_to_routes()
		for d in defense:
			d.reaction *= 1.0 - def_ai.reaction_cut * key_level
			if is_run_play() and d.brain is RushBrain:
				d.speed_mult = 1.0 + def_ai.rush_speed_bonus * key_level
	Events.play_started.emit(off_play.display_name)


func _brain_for(a: PlayerAgent) -> Brain:
	var asg := a.assignment
	match str(asg.get("type", "block")):
		"pass":
			return PassQBBrain.new(a, self, float(asg.get("drop", 2.0)))
		"handoff":
			handoff_to = off_slots.get(asg.get("to", "RB"))
			handoff_mesh = Vector2(los_x, ball_y) + asg.get("mesh", Vector2(-3, 0))
			handoff_delay = float(asg.get("delay", 0.0))
			handoff_range = float(asg.get("range", HANDOFF_RANGE))
			return HandoffQBBrain.new(a, self, handoff_mesh)
		"route", "carry":
			var pts := PackedVector2Array()
			for p in asg.get("path", PackedVector2Array()):
				pts.append(a.start_pos + p)
			var rb := RouteBrain.new(a, self, pts, str(asg.get("end", "continue")))
			rb.delay = float(asg.get("delay", 0.0))
			return rb
		"block":
			return BlockBrain.new(a, self, "run" if is_run_play() else "pass")
		"rush":
			return RushBrain.new(a, self)
		"man":
			return ManCoverBrain.new(a, self, off_slots.get(asg.get("target", "")))
		"zone":
			return ZoneBrain.new(a, self, asg.get("center", Vector2(8, 0)), asg.get("size", Vector2(10, 10)))
	return IdleBrain.new(a, self)


## Keyed defense: each zone defender slides his zone toward the nearest point the
## repeated play's routes (or run lane) will pass through.
func _cheat_zones_to_routes() -> void:
	var hot := PackedVector2Array()
	for o in offense:
		var t := str(o.assignment.get("type", ""))
		if t == "route" or t == "carry" or t == "sneak":
			for p in o.assignment.get("path", PackedVector2Array()):
				hot.append(o.start_pos + p)
	if hot.is_empty():
		return
	for d in defense:
		if not (d.brain is ZoneBrain):
			continue
		var zb := d.brain as ZoneBrain
		var c := zb.zone.get_center()
		var best := Vector2.INF
		for p in hot:
			if p.distance_to(c) < def_ai.zone_shift_reach and p.distance_to(c) < best.distance_to(c):
				best = p
		if best != Vector2.INF:
			zb.shift_zone((best - c) * def_ai.zone_shift * key_level)


## Press jams and play-action bites, applied once at the snap.
func _apply_presnap_reads() -> void:
	for d in defense:
		if d.assignment.get("type") == "man" and d.assignment.get("press", false):
			var mark: PlayerAgent = off_slots.get(d.assignment.get("target", ""))
			if mark != null:
				mark.jam_timer = RatingModel.press_jam(tuning, d.attr("cov"), mark.attr("rte"))
	if qb.assignment.get("fake", false):
		for d in defense:
			var zone_depth: float = (d.assignment.get("center", Vector2(99, 0)) as Vector2).x
			if d.brain is ZoneBrain and zone_depth < 9.0:
				(d.brain as ZoneBrain).bite = RatingModel.pa_bite(tuning, d.attr("awr"))


# ---------------------------------------------------------------- queries

func is_run_play() -> bool:
	return off_play != null and off_play.is_run()


## True while the human (or CPU) may still throw.
func qb_is_passer() -> bool:
	return phase == Phase.LIVE and carrier == qb and qb != null and not pass_thrown \
			and not scrambling and not is_run_play() and not qb.is_down \
			and qb.field_pos.x <= los_x + 0.5


func nearest_free(group: Array[PlayerAgent], p: Vector2) -> PlayerAgent:
	var best: PlayerAgent = null
	var best_d := INF
	for a in group:
		if a.is_down or a.engaged_with != null:
			continue
		var d := a.field_pos.distance_to(p)
		if d < best_d:
			best_d = d
			best = a
	return best


func pressure_on_qb() -> float:
	var r := nearest_free(defense, qb.field_pos)
	if r == null:
		return 0.0
	return clampf(1.0 - (r.field_pos.distance_to(qb.field_pos) - 1.0) / 4.0, 0.0, 1.0)


## Where a receiver is headed. Keyed defenders read the repeated route and aim at the
## next break point instead of trailing the receiver.
func anticipate(o: PlayerAgent) -> Vector2:
	var drift := o.field_pos + o.velocity * 0.3
	if key_level <= 0.0 or not (o.brain is RouteBrain):
		return drift
	var rb := o.brain as RouteBrain
	var next := rb.next_point()
	return drift.lerp(next, def_ai.jump_blend * key_level)


## Extra yards a keyed zone defender will leave his zone to jump a route.
func jump_reach() -> float:
	return def_ai.jump_reach * key_level


## The field point the camera should follow.
func focus_point() -> Vector2:
	if ball.state == Ball.State.AIR:
		return ball.field_pos
	if carrier != null:
		return carrier.field_pos
	return ball.field_pos


## Converts a slingshot drag (screen px) into a clamped throw target.
func aim_point(drag_start: Vector2, drag_now: Vector2) -> Vector2:
	var pull := drag_now - drag_start
	var target := qb.field_pos - pull * tuning.aim_gain
	var max_d := RatingModel.max_throw_distance(tuning, qb.attr("thp"))
	var v := target - qb.field_pos
	if v.length() > max_d:
		target = qb.field_pos + v.normalized() * max_d
	target.y = clampf(target.y, -1.0, FieldGeo.WIDTH + 1.0)
	return target


# ---------------------------------------------------------------- actions

func throw_ball(target: Vector2) -> void:
	if not qb_is_passer():
		return
	var dist := qb.field_pos.distance_to(target)
	var err := RatingModel.aim_error(tuning, qb.attr("tha"), qb.attr("awr"), dist, pressure_on_qb())
	var landing := target + Vector2.from_angle(rng.randf() * TAU) * err * sqrt(rng.randf())
	var arc := RatingModel.throw_arc(tuning, qb.attr("thp"), qb.field_pos.distance_to(landing))
	ball.throw_to(qb.field_pos, landing, arc.x, arc.y)
	pass_thrown = true
	qb.throw_anim = 0.3
	carrier = null
	if human_team == PlayerAgent.Team.OFFENSE:
		_set_controlled(null)

	# Best-placed receiver breaks on the ball; nearby defenders react after their delay.
	var best: PlayerAgent = null
	var best_d := INF
	for o in offense:
		if not o.is_eligible() or not o.can_act():
			continue
		var d := o.field_pos.distance_to(landing)
		if d < best_d and d / o.max_speed <= arc.x + 0.6:
			best_d = d
			best = o
	if best != null:
		best.brain = BallHawkBrain.new(best, self, landing, 0.0, null)
		if human_team == PlayerAgent.Team.OFFENSE:
			_set_controlled(best)
	for d in defense:
		if d.engaged_with != null or not d.can_act() or d.brain is RushBrain:
			continue
		if d.field_pos.distance_to(landing) < 11.0 + def_ai.ball_react_extra * key_level:
			d.brain = BallHawkBrain.new(d, self, landing, d.reaction + 0.1, d.brain)
	ball_thrown.emit(landing)


func start_scramble() -> void:
	if carrier != qb or pass_thrown:
		return
	scrambling = true
	_set_carrier(qb)


## Yards a tackled carrier falls forward (toward his goal) from his momentum.
func fall_forward(a: PlayerAgent) -> float:
	var fwd := 1.0 if a.team == PlayerAgent.Team.OFFENSE else -1.0
	return fwd * clampf(a.tackled_speed * fwd * tuning.fall_forward_time, 0.0, tuning.fall_forward_max)


func on_tackle(tackler: PlayerAgent, runner: PlayerAgent) -> void:
	runner.tackled_speed = runner.velocity.x
	runner.knock_down()
	tackler.knock_down(0.6)
	tackler.velocity = runner.velocity * 0.5
	big_hit.emit(runner.field_pos, runner.velocity.length())
	# Simple fumbles: the ball pops out on the hit and whoever is closest recovers it.
	if runner.team == PlayerAgent.Team.OFFENSE:
		var p := RatingModel.fumble_prob(tuning, runner.attr("car"), tackler.attr("tak"), tackler.attr("str"))
		if rng.randf() < p:
			_fumble(runner)


func _fumble(runner: PlayerAgent) -> void:
	var spot := runner.field_pos
	var best: PlayerAgent = null
	var best_d := tuning.fumble_recover_radius
	for a in agents:
		if a == runner or a.is_down:
			continue
		var d := a.field_pos.distance_to(spot) + rng.randf_range(0.0, 1.0)
		if d < best_d:
			best_d = d
			best = a
	fumbled = true
	if best != null and best.team != runner.team:
		_end_play("fumble", spot, "FUMBLE! TURNOVER")


## The human's defender at the snap: the middle linebacker-ish player (first LB, else nearest
## defender to the ball).
func default_defender() -> PlayerAgent:
	var best: PlayerAgent = null
	var best_d := INF
	for d in defense:
		var dist := d.field_pos.distance_to(Vector2(los_x + 5.0, ball_y)) - (4.0 if d.pos_code == "LB" else 0.0)
		if dist < best_d:
			best_d = dist
			best = d
	return best


## Hands the human a different defender (DefenseSwitcher / tap-to-switch).
func set_controlled_defender(d: PlayerAgent) -> void:
	if human_team != PlayerAgent.Team.DEFENSE or d == controlled or d == null or d.team != PlayerAgent.Team.DEFENSE:
		return
	_set_controlled(d)


func _set_controlled(a: PlayerAgent) -> void:
	if controlled != null:
		controlled.highlight = false
		controlled.human = false
	controlled = a
	if a != null:
		a.highlight = true


func _set_carrier(a: PlayerAgent, lane := PackedVector2Array()) -> void:
	if a.team == PlayerAgent.Team.DEFENSE:
		# Turnover: every block breaks up; the other side starts blocking.
		for x in agents:
			x.engaged_with = null
	carrier_lane = lane
	carrier = a
	ball.give_to(a)
	a.speed_mult = tuning.carrier_speed_mult
	if a.team == human_team:
		_set_controlled(a)
		a.human = true
		a.brain = null
	else:
		a.brain = RunnerBrain.new(a, self, carrier_lane)
	var mates := offense if a.team == PlayerAgent.Team.OFFENSE else defense
	var opps := defense if a.team == PlayerAgent.Team.OFFENSE else offense
	for m in mates:
		if m == a:
			continue
		# Run blockers keep their man through the handoff; everyone else escorts the carrier.
		if m.brain is BlockBrain and (m.brain as BlockBrain).mode == "run":
			continue
		m.brain = BlockBrain.new(m, self, "escort")
	for o in opps:
		o.brain = PursuitBrain.new(o, self)
	carrier_changed.emit(a)
	Events.carrier_changed.emit(a)


# ---------------------------------------------------------------- simulation

func _physics_process(dt: float) -> void:
	if phase == Phase.DEAD:
		for a in agents:
			a.stop()
			a.step(dt, tuning)
		ball.step(dt)
		_dead_timer -= dt
		if _dead_timer <= 0.0 and not _pending_result.is_empty():
			var r := _pending_result
			_pending_result = {}
			phase = Phase.IDLE
			play_ended.emit(r)
			Events.play_ended.emit(r)
		return
	if phase != Phase.LIVE:
		return

	play_time += dt
	if human_input != null:
		human_input.apply(dt)
	for a in agents:
		if not a.human and a.brain != null:
			a.brain.update(dt)
	for a in agents:
		a.step(dt, tuning)
	contact.resolve(dt)
	_check_handoff()
	if ball.step(dt):
		_resolve_arrival()
	_check_carrier()
	if phase == Phase.LIVE and play_time > WATCHDOG_SECONDS:
		var spot := carrier.field_pos if carrier != null else Vector2(los_x, ball_y)
		_end_play("tackle", spot, "WHISTLE")


func _check_handoff() -> void:
	if handoff_to == null or carrier != qb or pass_thrown:
		return
	var close := qb.field_pos.distance_to(handoff_to.field_pos) < handoff_range
	var ready := play_time > maxf(0.2, handoff_delay)
	if (ready and close) or play_time > 2.0 + handoff_delay:
		var rb := handoff_to
		handoff_to = null
		qb.brain = IdleBrain.new(qb, self)
		var lane := PackedVector2Array()
		if rb.brain is RouteBrain:
			var route := rb.brain as RouteBrain
			for i in range(route.idx, route.points.size()):
				lane.append(route.points[i])
		_set_carrier(rb, lane)


func _check_carrier() -> void:
	if phase != Phase.LIVE or carrier == null:
		return
	var p := carrier.field_pos
	if carrier == qb and not scrambling and not pass_thrown and not is_run_play() \
			and p.x > los_x + 0.5:
		start_scramble()
	if carrier.team == PlayerAgent.Team.DEFENSE:
		_check_return(p)
		return
	if p.x >= FieldGeo.OPP_GOAL:
		carrier.celebrating = true
		_end_play("td", p, "TOUCHDOWN!")
		return
	if p.y < 0.0 or p.y > FieldGeo.WIDTH:
		_end_play("out", p, "OUT OF BOUNDS")
		return
	if carrier.is_down:
		if p.x <= FieldGeo.OWN_GOAL:
			_end_play("safety", p, "SAFETY!")
		elif carrier == qb and not pass_thrown and not is_run_play() and p.x < los_x:
			_end_play("sack", p, "SACKED!")
		else:
			_end_play("tackle", p + Vector2(fall_forward(carrier), 0.0), "")


## Interception return (the defense runs toward -x): pick six, or down where tackled.
## Downed in the end zone it came from = touchback (the match controller handles spots).
func _check_return(p: Vector2) -> void:
	if p.x <= FieldGeo.OWN_GOAL:
		carrier.celebrating = true
		_end_play("int_td", p, "PICK SIX!")
	elif p.y < 0.0 or p.y > FieldGeo.WIDTH:
		_end_play("int", p, "INTERCEPTED!")
	elif carrier.is_down:
		_end_play("int", p - Vector2(fall_forward(carrier) * -1.0, 0.0), "INTERCEPTED!")


## Human defender's jump at the ball (swat / pick). Timing is judged at the catch point.
func defender_jump(d: PlayerAgent) -> void:
	if phase != Phase.LIVE or ball.state != Ball.State.AIR or d.jump_timer > 0.0 or not d.can_act():
		return
	d.start_jump(tuning)
	d.jump_started_at = play_time


## The defender whose jump can affect a ball arriving at `landing`, or null.
func _jumper_near(landing: Vector2) -> PlayerAgent:
	var t := tuning
	for d in defense:
		if d.jump_started_at < 0.0 or play_time - d.jump_started_at > t.jump_time + t.jump_good:
			continue
		if d.field_pos.distance_to(landing) <= t.contest_radius + t.jump_reach:
			return d
	return null


func _resolve_arrival() -> void:
	var landing := ball.to
	var t := tuning
	var j := _jumper_near(landing)
	if j != null:
		var err := absf((play_time - j.jump_started_at) - t.jump_time * 0.5)
		var r := rng.randf()
		var p_int := RatingModel.jump_int_prob(t, err, j.attr("cov"), j.attr("cth"))
		if r < p_int:
			_set_carrier(j)
			return
		if r < p_int + RatingModel.jump_deflect_prob(t, err):
			_end_play("incomplete", Vector2(los_x, ball_y), "SWATTED!")
			return
	var o := _nearest_catcher(offense, landing, t.catch_radius, true)
	var d := _nearest_catcher(defense, landing, t.contest_radius, false)
	var od := o.field_pos.distance_to(landing) if o != null else INF
	var dd := d.field_pos.distance_to(landing) if d != null else INF
	if o == null and d == null:
		_end_play("incomplete", Vector2(los_x, ball_y), "INCOMPLETE")
		return
	if d != null and (o == null or dd + 0.3 + def_ai.contest_bonus * key_level < od):
		var p_int := RatingModel.int_prob(t, d.attr("cov"), d.attr("cth")) * (1.0 + def_ai.int_bonus * key_level)
		if rng.randf() < p_int:
			_set_carrier(d)
		else:
			_end_play("incomplete", Vector2(los_x, ball_y), "BROKEN UP!")
		return
	var contest := 0.0 if d == null else clampf(1.0 - dd / t.contest_radius + def_ai.catch_contest_bonus * key_level, 0.0, 1.0)
	var def_cov := d.attr("cov") if d != null else 50.0
	if rng.randf() < RatingModel.catch_prob(t, o.attr("cth"), contest, def_cov):
		_set_carrier(o)
	elif d != null and rng.randf() < 0.15:
		_set_carrier(d)
	else:
		_end_play("incomplete", Vector2(los_x, ball_y), "DROPPED!" if contest < 0.3 else "BROKEN UP!")


func _nearest_catcher(group: Array[PlayerAgent], p: Vector2, radius: float, eligible_only: bool) -> PlayerAgent:
	var best: PlayerAgent = null
	var best_d := radius
	for a in group:
		if not a.can_act() or a.engaged_with != null:
			continue
		if eligible_only and not a.is_eligible():
			continue
		var d := a.field_pos.distance_to(p)
		if d <= best_d:
			best_d = d
			best = a
	return best


func _end_play(type: String, spot: Vector2, text: String) -> void:
	if phase != Phase.LIVE:
		return
	phase = Phase.DEAD
	_dead_timer = DEAD_BALL_PAUSE
	if ball.state == Ball.State.AIR:
		ball.place(ball.to)
	_set_controlled(null)
	for a in agents:
		a.human = false
	var spot_x := clampf(spot.x, 0.0, FieldGeo.LENGTH)
	_pending_result = {
		"type": type,
		"spot_x": spot_x,
		"spot_y": clampf(spot.y, 0.0, FieldGeo.WIDTH),
		"yards": int(round(spot_x) - round(los_x)),
		"text": text,
		"turnover": type in ["int", "int_td", "fumble"],
		"broken_tackles": broken_tackles,
		"pass_thrown": pass_thrown,
	}
