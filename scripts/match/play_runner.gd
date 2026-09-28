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
## A highlight moment for juice (slow-mo, camera punch): "deep_catch", "pick" or "td".
signal big_moment(kind: String, at: Vector2)

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
## Live aim reticle while the human is aiming (Vector2.INF otherwise); the camera leads to it.
var aim_preview := Vector2.INF
## Receiver the aim assist is pulling the reticle toward (or null).
var aim_assist_target: PlayerAgent = null
## PassModel plan of the ball in the air ({} before a throw).
var throw_plan: Dictionary = {}
## The receiver the ball is thrown to (tracks the landing spot).
var intended: PlayerAgent = null
var _human_throw := false
var _lane_checked: Dictionary = {}
var _ball_prev := Vector2.ZERO

## Headless pass log across plays (sandbox sim / --pass-log): attempts/completions by depth.
static var pass_log := {"att": 0, "comp": 0, "int": 0, "deep_att": 0, "deep_comp": 0, "deep_int": 0,
		"lane_tips": 0, "lane_ints": 0, "lob": 0, "touch": 0, "bullet": 0}

var _pending_result: Dictionary = {}
var _dead_timer := 0.0
## The dead-ball spot is read off the ball once the downed carrier's slide stops.
var _spot_at_ball := false


func _init() -> void:
	contact = ContactResolver.new(self)


## One line summary of pass_log (sandbox sim prints it; --pass-log prints it on exit).
static func pass_log_text() -> String:
	var l := pass_log
	return "PASSLOG %d att, %.0f%% comp, %.1f%% INT | deep (20+ air yds) %d att, %.0f%% comp, %.1f%% INT | lane tips %d (%d INT) | bullet %d, touch %d, lob %d" % [
		l["att"], 100.0 * l["comp"] / maxf(l["att"], 1), 100.0 * l["int"] / maxf(l["att"], 1),
		l["deep_att"], 100.0 * l["deep_comp"] / maxf(l["deep_att"], 1), 100.0 * l["deep_int"] / maxf(l["deep_att"], 1),
		l["lane_tips"], l["lane_ints"], l["bullet"], l["touch"], l["lob"]]


func _exit_tree() -> void:
	if OS.get_cmdline_user_args().has("--pass-log"):
		print(pass_log_text())


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
	aim_preview = Vector2.INF
	aim_assist_target = null
	throw_plan = {}
	intended = null
	_human_throw = false
	_lane_checked = {}
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
	a.setup(team, slot, pos, attrs, tuning, colors, info.get("name", slot), info.get("jersey", 0), info.get("look", {}))
	a.field_pos = at
	a.start_pos = at
	a.in_stance = pos in ["OL", "DL", "TE"]
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
		a.in_stance = false
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
	if human_team == PlayerAgent.Team.OFFENSE:
		key_level = clampf(key_level * _key_scale(), 0.0, 1.0)
	if key_level > 0.0:
		_cheat_zones_to_routes()
		for d in defense:
			d.reaction *= 1.0 - def_ai.reaction_cut * key_level
			if is_run_play() and d.brain is RushBrain:
				d.speed_mult = 1.0 + def_ai.rush_speed_bonus * key_level
	Events.play_started.emit(off_play.display_name)


## Keying strength vs the human for the current difficulty (Settings autoload if present).
func _key_scale() -> float:
	var scales := def_ai.key_scale_by_difficulty
	var settings: Node = get_tree().root.get_node_or_null("Settings") if is_inside_tree() else null
	if settings == null or scales.is_empty():
		return 1.0
	return scales[clampi(int(settings.get("difficulty")), 0, scales.size() - 1)]


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


## Converts a slingshot drag (screen px) into a clamped throw target (landing point).
## Pull direction = throw direction, pull length = distance (progressive), then a light aim
## assist toward a receiver's lead point (aim_assist_target is set for the preview).
func aim_point(drag_start: Vector2, drag_now: Vector2) -> Vector2:
	var pull := drag_now - drag_start
	var max_d := RatingModel.max_throw_distance(tuning, qb.attr("thp"))
	var raw := qb.field_pos - pull * tuning.aim_gain
	var dir := (raw - qb.field_pos).normalized() if pull.length() > 0.01 else Vector2.RIGHT
	var yards := minf(PassModel.pull_to_yards(tuning, pull.length()), max_d)
	var target := qb.field_pos + dir * yards
	aim_assist_target = null
	var leads := PackedVector2Array()
	var recs: Array[PlayerAgent] = []
	for o in offense:
		if o.is_eligible() and o.can_act() and o.engaged_with == null and o != qb:
			leads.append(lead_point(o))
			recs.append(o)
	var a := PassModel.assist(tuning, target, leads)
	if int(a["index"]) >= 0:
		target = a["point"]
		aim_assist_target = recs[int(a["index"])]
	var v := target - qb.field_pos
	if v.length() > max_d:
		target = qb.field_pos + v.normalized() * max_d
	target.y = clampf(target.y, -1.0, FieldGeo.WIDTH + 1.0)
	return target


## Defenders' ground positions a throw to `target` must pass over (projected a little ahead).
func lane_blockers(target: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var look := minf(0.45, qb.field_pos.distance_to(target) / 60.0)
	for d in defense:
		if d.is_down or d.engaged_with != null:
			continue
		out.append(d.field_pos + d.velocity * look)
	return out


## PassModel plan for a throw from the QB to `target` (what the aim preview shows).
func plan_throw(target: Vector2) -> Dictionary:
	return PassModel.plan(tuning, qb.attr("thp"), qb.field_pos, target, lane_blockers(target))


## Where a receiver will be `secs` from now if he keeps running his route at full speed.
func predict(o: PlayerAgent, secs: float) -> Vector2:
	if not (o.brain is RouteBrain):
		return _on_field(o.field_pos + o.velocity * secs)
	var rb := o.brain as RouteBrain
	var spd := o.max_speed * o.speed_mult
	var cur := o.velocity.length()
	var budget := spd * maxf(secs - rb.delay - o.jam_timer * (1.0 - tuning.press_jam_speed), 0.0)
	budget = maxf(budget - (spd - cur) * (spd - cur) / (2.0 * o.accel), 0.0)
	var p := o.field_pos
	var dir := rb.last_dir
	for i in range(rb.idx, rb.points.size()):
		var seg := rb.points[i] - p
		if seg.length() >= budget:
			return _on_field(p + seg.normalized() * budget)
		budget -= seg.length()
		if seg.length() > 0.01:
			dir = seg.normalized()
		p = rb.points[i]
	if rb.end_mode == "sit":
		return _on_field(p)
	return _on_field(p + dir * budget)


func _on_field(p: Vector2) -> Vector2:
	return Vector2(minf(p.x, FieldGeo.LENGTH - 1.0), clampf(p.y, 1.0, FieldGeo.WIDTH - 1.0))


## The landing spot that hits a receiver in stride (flight time from the plan, iterated),
## pushed a little further ahead on lofted balls so he runs under it, away from a trailer.
func lead_point(o: PlayerAgent) -> Vector2:
	var p := o.field_pos
	var plan := {}
	for i in 3:
		plan = plan_throw(p)
		p = predict(o, float(plan["dur"]))
	var ahead := predict(o, float(plan["dur"]) + 0.3) - p
	if ahead.length() > 0.05:
		p += ahead.normalized() * tuning.lob_lead_extra * float(plan["loft"])
	p.y = clampf(p.y, 1.5, FieldGeo.WIDTH - 1.5)
	return p


# ---------------------------------------------------------------- actions

func throw_ball(target: Vector2) -> void:
	if not qb_is_passer():
		return
	var dist := qb.field_pos.distance_to(target)
	var err := RatingModel.aim_error(tuning, qb.attr("tha"), qb.attr("awr"), dist, pressure_on_qb())
	var landing := target + Vector2.from_angle(rng.randf() * TAU) * err * sqrt(rng.randf())
	throw_plan = plan_throw(landing)
	var dur := float(throw_plan["dur"])
	ball.throw_to(qb.field_pos, landing, dur, float(throw_plan["apex"]))
	_ball_prev = qb.field_pos
	_lane_checked = {}
	_human_throw = human_team == PlayerAgent.Team.OFFENSE
	pass_thrown = true
	aim_preview = Vector2.INF
	qb.throw_anim = 0.3
	carrier = null
	if human_team == PlayerAgent.Team.OFFENSE:
		_set_controlled(null)
	pass_log[["bullet", "touch", "lob"][int(throw_plan["kind"])]] += 1

	# The receiver who can get there with the least to spare tracks the ball to its landing.
	var best: PlayerAgent = null
	var best_d := INF
	for o in offense:
		if not o.is_eligible() or not o.can_act():
			continue
		var d := o.field_pos.distance_to(landing)
		if d < best_d and d / o.max_speed <= dur + 0.6:
			best_d = d
			best = o
	intended = best
	if best != null:
		best.brain = BallHawkBrain.new(best, self, landing, 0.0, null, true)
		if human_team == PlayerAgent.Team.OFFENSE:
			_set_controlled(best)
	# Defenders: zone defenders read the QB and break on the ball after their reaction;
	# man defenders run with their man (backs to the ball) and only turn late to find it.
	for d in defense:
		if d.engaged_with != null or not d.can_act() or d.brain is RushBrain or d.human:
			continue
		var dd := d.field_pos.distance_to(landing)
		var react := d.reaction + 0.1
		if d.brain is ManCoverBrain and (d.brain as ManCoverBrain).mark != null:
			var mark := (d.brain as ManCoverBrain).mark
			if mark == best or dd < tuning.ball_react_radius:
				d.brain = BallHawkBrain.new(d, self, landing, maxf(react, dur - tuning.man_look_back), d.brain)
		elif dd < tuning.ball_react_radius + def_ai.ball_react_extra * key_level:
			d.brain = BallHawkBrain.new(d, self, landing, react, d.brain)
	ball_thrown.emit(landing)


func start_scramble() -> void:
	if carrier != qb or pass_thrown:
		return
	scrambling = true
	_set_carrier(qb)


## Yards a tackled carrier falls forward (toward his goal) from his momentum. It is a
## visible slide (on_tackle), never hidden yardage: the spot is where the ball comes to rest.
func fall_forward(a: PlayerAgent) -> float:
	var fwd := 1.0 if a.team == PlayerAgent.Team.OFFENSE else -1.0
	var yards := clampf(a.tackled_speed * fwd * tuning.fall_forward_time, 0.0, tuning.fall_forward_max)
	# The slide never carries the ball over the goal line he is running at.
	var ball_x := a.field_pos.x + a.facing * Ball.HOLD_AHEAD
	var room := (FieldGeo.OPP_GOAL - 0.3 - ball_x) if fwd > 0.0 else (ball_x - FieldGeo.OWN_GOAL - 0.3)
	return fwd * clampf(yards, 0.0, maxf(room, 0.0))


func on_tackle(tackler: PlayerAgent, runner: PlayerAgent) -> void:
	runner.tackled_speed = runner.velocity.x
	var speed := runner.velocity.length()
	var slide := fall_forward(runner)
	runner.knock_down()
	tackler.knock_down(0.6)
	tackler.velocity = runner.velocity * 0.5
	# He goes down straight ahead, sliding exactly `slide` yards (v² = 2·a·d).
	runner.velocity = Vector2(signf(slide) * sqrt(2.0 * tuning.down_slide_decel * absf(slide)), 0.0)
	big_hit.emit(runner.field_pos, speed)
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


## The human's defender at the snap: the best-placed second-level player — the linebacker
## nearest the ball (safeties next), else the nearest defender.
func default_defender() -> PlayerAgent:
	var best: PlayerAgent = null
	var best_d := INF
	for d in defense:
		var bonus := 4.0 if d.pos_code == "LB" else (2.0 if d.pos_code == "S" else 0.0)
		var dist := d.field_pos.distance_to(Vector2(los_x + 5.0, ball_y)) - bonus
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
		if a.team == human_team and a.engaged_with != null and phase == Phase.LIVE:
			a.shed_timer *= tuning.human_shed_mult   # your man fights off his block fast


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

func _process(_delta: float) -> void:
	_update_markers()


## Who is who at a glance: stars under your receivers until the ball is thrown, and an arrow
## over the ball carrier (yellow = yours, red = theirs).
func _update_markers() -> void:
	var human_off := human_team == PlayerAgent.Team.OFFENSE
	var show_stars := human_off and (phase == Phase.PRE_SNAP or qb_is_passer())
	for a in agents:
		a.star = show_stars and a.is_eligible() and a != carrier
		var mark := Color(0, 0, 0, 0)
		if phase == Phase.LIVE and a == carrier and not qb_is_passer():
			mark = Color("#ffec27") if a.team == human_team else Color("#ff4b4b")
		a.arrow = mark


func _physics_process(dt: float) -> void:
	if phase == Phase.DEAD:
		for a in agents:
			a.stop()
			a.step(dt, tuning)
		ball.step(dt)
		_dead_timer -= dt
		if _dead_timer <= 0.0 and not _pending_result.is_empty():
			if _spot_at_ball:
				_set_spot(_pending_result, ball.field_pos)
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
	elif ball.state == Ball.State.AIR:
		_check_lane()
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
		big_moment.emit("td", p)
		_end_play("td", p, "TOUCHDOWN!")
		return
	if p.y < 0.0 or p.y > FieldGeo.WIDTH:
		# Out where the ball crossed the sideline; it stays there (the runner coasts on).
		var at := Vector2(ball.field_pos.x, clampf(ball.field_pos.y, 0.0, FieldGeo.WIDTH))
		_end_play("out", at, "OUT OF BOUNDS")
		ball.place(at)
		return
	if carrier.is_down:
		if p.x <= FieldGeo.OWN_GOAL:
			_end_play("safety", p, "SAFETY!")
		elif carrier == qb and not pass_thrown and not is_run_play() and p.x < los_x:
			_end_play("sack", ball.field_pos, "SACKED!")
			_spot_at_ball = true
		else:
			# Spotted where the ball comes to rest after his slide (finalized when the play
			# ends); a runner downed short of the goal line is never a touchdown.
			_end_play("tackle", ball.field_pos, "")
			_spot_at_ball = true


## Interception return (the defense runs toward -x): pick six, or down where tackled.
## Downed in the end zone it came from = touchback (the match controller handles spots).
func _check_return(p: Vector2) -> void:
	if p.x <= FieldGeo.OWN_GOAL:
		carrier.celebrating = true
		big_moment.emit("td", p)
		_end_play("int_td", p, "PICK SIX!")
	elif p.y < 0.0 or p.y > FieldGeo.WIDTH:
		_end_play("int", ball.field_pos, "INTERCEPTED!")
		ball.place(ball.field_pos)
	elif carrier.is_down:
		_end_play("int", ball.field_pos, "INTERCEPTED!")
		_spot_at_ball = true


## Human defender's jump at the ball (swat / pick). Timing is judged at the catch point.
func defender_jump(d: PlayerAgent) -> void:
	if phase != Phase.LIVE or ball.state != Ball.State.AIR or d.jump_timer > 0.0 or not d.can_act():
		return
	d.start_jump(tuning, ball.to)
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


## A defender whose hands the low part of the ball's flight passes within reach of gets a
## chance to tip or pick it (bullets thrown through a defender; lobs sail over them).
## The last contest_radius yards belong to the catch-point contest instead.
func _check_lane() -> void:
	var t := tuning
	var p := ball.field_pos
	var prev := _ball_prev
	_ball_prev = p
	if ball.from.distance_to(p) < t.lane_skip_near or ball.to.distance_to(p) < t.contest_radius:
		return
	if ball.z > t.reach_height + t.jump_height:
		return
	for d in defense:
		if _lane_checked.has(d) or d.engaged_with != null or (not d.can_act() and d.jump_timer <= 0.0):
			continue
		var gd := PassModel.seg_dist(d.field_pos, prev, p)
		if not PassModel.can_reach(t, gd, ball.z, d.z_height):
			continue
		_lane_checked[d] = true
		if rng.randf() >= RatingModel.lane_play_prob(t, d.attr("cov"), d.attr("awr")):
			continue
		pass_log["lane_tips"] += 1
		if rng.randf() < RatingModel.lane_int_prob(t, d.attr("cth")) * (1.0 + def_ai.int_bonus * key_level):
			pass_log["lane_ints"] += 1
			_log_pass(false, true)
			_set_carrier(d)
		else:
			_log_pass(false, false)
			_end_play("incomplete", Vector2(los_x, ball_y), "TIPPED!")
		return


func _log_pass(caught: bool, picked: bool) -> void:
	var deep := ball.to.x - los_x >= 20.0
	pass_log["att"] += 1
	pass_log["comp"] += 1 if caught else 0
	pass_log["int"] += 1 if picked else 0
	if deep:
		pass_log["deep_att"] += 1
		pass_log["deep_comp"] += 1 if caught else 0
		pass_log["deep_int"] += 1 if picked else 0


func _resolve_arrival() -> void:
	var landing := ball.to
	var t := tuning
	var j := _jumper_near(landing)
	if j != null:
		var err := absf((play_time - j.jump_started_at) - t.jump_time * 0.5)
		var r := rng.randf()
		var p_int := RatingModel.jump_int_prob(t, err, j.attr("cov"), j.attr("cth"))
		if r < p_int:
			_log_pass(false, true)
			_set_carrier(j)
			big_moment.emit("pick", landing)
			return
		if r < p_int + RatingModel.jump_deflect_prob(t, err):
			_log_pass(false, false)
			_end_play("incomplete", Vector2(los_x, ball_y), "SWATTED!")
			return
	var reach := t.catch_radius + (t.human_catch_bonus if _human_throw else 0.0)
	var o := _nearest_catcher(offense, landing, reach, true)
	var d := _nearest_catcher(defense, landing, t.contest_radius + t.lob_contest_extra * float(throw_plan.get("loft", 0.0)), false)
	var od := o.field_pos.distance_to(landing) if o != null else INF
	var dd := d.field_pos.distance_to(landing) if d != null else INF
	if o == null and d == null:
		_log_pass(false, false)
		_end_play("incomplete", Vector2(los_x, ball_y), "INCOMPLETE")
		return
	var loft := float(throw_plan.get("loft", 0.0))
	if d != null and (o == null or dd + 0.3 + def_ai.contest_bonus * key_level < od):
		# The defender beat the receiver to the spot. Under a hanging ball he has time to
		# settle under it (undercut); a bullet he can only get a hand on.
		var p_int := RatingModel.int_prob(t, d.attr("cov"), d.attr("cth")) * (1.0 + def_ai.int_bonus * key_level)
		if loft >= t.lob_threshold and dd < 0.9:
			p_int = minf(p_int * t.undercut_int_mult, 0.75)
		if rng.randf() < p_int:
			_log_pass(false, true)
			_set_carrier(d)
			big_moment.emit("pick", landing)
		else:
			_log_pass(false, false)
			_end_play("incomplete", Vector2(los_x, ball_y), "BROKEN UP!")
		return
	var contest := 0.0
	if d != null:
		contest = clampf(PassModel.contest(t, landing, o.field_pos, d.field_pos, loft)
				+ def_ai.catch_contest_bonus * key_level, 0.0, 1.0)
	var def_cov := d.attr("cov") if d != null else 50.0
	var p_catch := RatingModel.catch_prob(t, o.attr("cth"), contest, def_cov) * (1.0 - t.lob_catch_penalty * loft)
	if rng.randf() < p_catch:
		_log_pass(true, false)
		_set_carrier(o)
		if landing.x - los_x >= tuning.slowmo_deep_yards:
			big_moment.emit("deep_catch", landing)
	elif d != null and contest > 0.3 and rng.randf() < t.tip_int_chance:
		_log_pass(false, true)
		_set_carrier(d)
	else:
		_log_pass(false, false)
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
	_spot_at_ball = false
	_pending_result = {
		"type": type,
		"text": text,
		"turnover": type in ["int", "int_td", "fumble"],
		"broken_tackles": broken_tackles,
		"pass_thrown": pass_thrown,
		"air_yards": ball.to.x - los_x if pass_thrown else 0.0,
		"throw_kind": int(throw_plan.get("kind", -1)),
	}
	_set_spot(_pending_result, spot)


## Dead-ball spot and yards. "yards" is exactly the change in the line of scrimmage the
## down tracker will make (whole-yard spot, never past the 1 unless the play scored), so
## the result banner always matches the markers.
func _set_spot(r: Dictionary, spot: Vector2) -> void:
	var spot_x := clampf(spot.x, 0.0, FieldGeo.LENGTH)
	r["spot_x"] = spot_x
	r["spot_y"] = clampf(spot.y, 0.0, FieldGeo.WIDTH)
	var type: String = r["type"]
	if type == "td":
		r["yards"] = int(FieldGeo.OPP_GOAL - los_x)
	elif type == "incomplete":
		r["yards"] = 0
	else:
		r["yards"] = int(DownTracker.spot_yard(spot_x) - roundf(los_x))
