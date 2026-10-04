class_name RtgControl
extends Node
## Road to Glory controls for the one player you are (PlayRunner.locked), driven by RtgPad:
##   stick      - 360° analog movement; full stick = full speed. A turn sharper than
##                rtg_cut_angle at speed is a plant-and-cut (keeps speed by agility).
##                Let go: a ball carrier keeps his heading (or the designed lane until you
##                first steer), a receiver who left his route keeps striding, anyone else
##                goes back to his assignment AI (route / coverage / block).
##   buttons    - context: carrier JUKE / BURST / SPIN / POWER (stiff arm or truck) / DIVE;
##                receiver CALL (QB looks your way) and CATCH (tap as it arrives: high-point);
##                corner JAM (right after the snap), BALL (leap at the pass), TACKLE (dive).
##   pre-snap   - a corner can shade his alignment with the stick (press = line up close).
## The QB keeps the classic right-thumb aim (HumanOffenseControl in aim-only mode); the stick
## moves him in the pocket. PlayRunner calls apply() every physics frame before the brains.

## Text pop for the HUD (move used, jam landed, ...): text, where (field), good/bad.
signal action(text: String, at: Vector2, good: bool)

var runner: PlayRunner
var pad: RtgPad
var tuning: GameplayTuning
## 0..1 coach trust (how much the CPU QB looks for you).
var trust := 0.5
## Receivers run everything themselves: no auto route, no auto ball tracking; let go of the
## stick and he pulls up. Following the drawn route keeps the QB's trust (CpuPasser).
var manual_routes := true

var took_over := false            ## steered at least once this play
var last_dir := Vector2.RIGHT
var call_cd := 0.0
## Corner read telegraph: the receiver about to break and the direction of his break.
var tele_agent: PlayerAgent = null
var tele_dir := Vector2.ZERO
## The jam was tried this play (it is offered once).
var _jam_tried := false


func bind(p_runner: PlayRunner, p_pad: RtgPad, p_tuning: GameplayTuning) -> void:
	runner = p_runner
	pad = p_pad
	tuning = p_tuning
	pad.radius = tuning.rtg_stick_radius
	pad.dead = tuning.rtg_stick_dead
	pad.button_pressed.connect(press)


## A new play is set up: forget the last one.
func on_play_setup() -> void:
	took_over = false
	last_dir = Vector2.RIGHT if _me() == null or _me().team == PlayerAgent.Team.OFFENSE else Vector2.LEFT
	tele_agent = null
	_jam_tried = false
	if pad != null:
		pad.reset()
		pad.show_hint = true


func _me() -> PlayerAgent:
	return runner.locked if runner != null else null


func _live() -> bool:
	return runner != null and runner.phase == PlayRunner.Phase.LIVE and _me() != null


## Screen stick -> field direction (the field's y axis is squashed on screen).
static func stick_to_field(s: Vector2) -> Vector2:
	var d := Vector2(s.x / FieldProjection.PX_X, s.y / FieldProjection.PX_Y)
	return d.normalized() if d.length() > 0.0001 else Vector2.ZERO


func _process(delta: float) -> void:
	call_cd = maxf(0.0, call_cd - delta)
	if pad != null:
		pad.buttons = buttons()
		var me := _me()
		pad.stick_enabled = me != null and (runner.phase == PlayRunner.Phase.LIVE
				or runner.phase == PlayRunner.Phase.PRE_SNAP and me.team == PlayerAgent.Team.DEFENSE)


## Pre-snap (called by the owner each physics frame): a corner shades his alignment.
func pre_snap_step(dt: float) -> void:
	var me := _me()
	if runner == null or me == null or runner.phase != PlayRunner.Phase.PRE_SNAP or me.team != PlayerAgent.Team.DEFENSE:
		return
	var dir := stick_to_field(pad.stick)
	if dir == Vector2.ZERO:
		return
	var origin_y := float(me.get_meta("align_y", me.field_pos.y))
	if not me.has_meta("align_y"):
		me.set_meta("align_y", origin_y)
	var p := me.field_pos + dir * tuning.rtg_align_speed * pad.stick.length() * dt
	p.x = clampf(p.x, runner.los_x + 0.8, runner.los_x + 14.0)
	p.y = clampf(p.y, maxf(origin_y - tuning.rtg_align_max_y, 1.0), minf(origin_y + tuning.rtg_align_max_y, FieldGeo.WIDTH - 1.0))
	me.field_pos = p
	me.start_pos = p
	me.facing = -1.0


func apply(dt: float) -> void:
	if not _live():
		return
	var me := _me()
	_update_telegraph()
	if not me.can_act() or runner.handoff_to == me:
		return   # down / diving, or the back is still taking the handoff
	if me == runner.qb and runner.handoff_to != null:
		# A called run: the QB opens to the mesh and hands it off on his own (holding the ball
		# isn't carrying it yet; running upfield would leave the back chasing him).
		me.human = false
		me.accel_mult = 1.0
		return
	var carrier := me == runner.carrier
	var passer := me == runner.qb and runner.qb_is_passer()
	var dir := stick_to_field(pad.stick)
	if dir != Vector2.ZERO:
		_steer(me, dir, pad.stick.length(), carrier)
		took_over = true
		last_dir = dir
		if not carrier and not passer and me.team == PlayerAgent.Team.OFFENSE:
			if me.brain is FreeRunBrain:
				(me.brain as FreeRunBrain).heading = dir
			elif not (me.brain is BallHawkBrain):
				me.brain = FreeRunBrain.new(me, runner, dir)   # off script for the rest of the play
		return
	if passer and took_over:
		# You moved him in the pocket: he stays where you left him (no walking back to the drop spot).
		me.human = true
		me.stop()
		return
	if carrier and not passer:
		me.human = true
		me.accel_mult = tuning.rtg_accel_mult
		me.throttle = 1.0
		if not took_over and me.team == PlayerAgent.Team.OFFENSE:
			me.desired_dir = _lane_dir(me)
		else:
			me.desired_dir = last_dir if took_over else Vector2(-1.0 if me.team == PlayerAgent.Team.DEFENSE else 1.0, 0.0)
		return
	if manual_routes and _manual_receiver(me):
		me.human = true   # hands off the stick: he pulls up (no autopilot route)
		me.accel_mult = tuning.rtg_accel_mult
		me.stop()
		return
	# Hands off: his assignment AI plays (route, coverage, pocket, block, ball tracking).
	me.human = false
	me.accel_mult = 1.0


## A receiver you play by hand (not the QB, not carrying it).
func _manual_receiver(me: PlayerAgent) -> bool:
	return me.team == PlayerAgent.Team.OFFENSE and me.pos_code in ["WR", "TE"] and me != runner.carrier


func _steer(me: PlayerAgent, dir: Vector2, mag: float, carrier: bool) -> void:
	me.human = true
	me.accel_mult = tuning.rtg_accel_mult
	me.speed_mult = tuning.carrier_speed_mult if carrier else 1.0
	var v := me.velocity
	if me.cut_cd <= 0.0 and v.length() >= tuning.rtg_cut_min_speed \
			and absf(rad_to_deg(v.angle_to(dir))) >= tuning.rtg_cut_angle:
		# Plant and cut: the new direction right now, at the speed his agility keeps.
		var keep := RatingModel.rtg_cut_keep(tuning, RatingModel.agility(me.pos_code, me.attrs))
		me.velocity = dir * v.length() * keep
		me.cut_cd = tuning.rtg_cut_cooldown
	me.desired_dir = dir
	me.throttle = clampf(mag, 0.0, 1.0)


## The designed run lane until you take over (like the classic carrier), else straight ahead.
func _lane_dir(me: PlayerAgent) -> Vector2:
	var lane := runner.carrier_lane
	while not lane.is_empty() and (me.field_pos.distance_to(lane[0]) < 1.2 or lane[0].x < me.field_pos.x - 0.3):
		lane.remove_at(0)
	runner.carrier_lane = lane
	return (lane[0] - me.field_pos).normalized() if not lane.is_empty() else Vector2.RIGHT


func _heading(me: PlayerAgent) -> Vector2:
	if me.velocity.length() > 0.8:
		return me.velocity.normalized()
	return Vector2(me.facing, 0.0)


func _opponents(me: PlayerAgent) -> Array[PlayerAgent]:
	return runner.defense if me.team == PlayerAgent.Team.OFFENSE else runner.offense


func _nearest_opponent(me: PlayerAgent, within: float) -> PlayerAgent:
	var best: PlayerAgent = null
	var best_d := within
	for d in _opponents(me):
		if d.is_down or d.engaged_with != null:
			continue
		var dd := d.field_pos.distance_to(me.field_pos)
		if dd < best_d:
			best_d = dd
			best = d
	return best


# ---------------------------------------------------------------- buttons

## The buttons for this moment: [{id, label, cd, hot}] (slot 0 = the big one).
func buttons() -> Array:
	var me := _me()
	if not _live() or not me.can_act() and me.dive_timer <= 0.0:
		return []
	var t := tuning
	var burst := {"id": "burst", "label": "BURST", "cd": me.burst_cd / t.rtg_burst_cooldown}
	var carrier := me == runner.carrier
	var passer := me == runner.qb and runner.qb_is_passer()
	if carrier and not passer:
		var gcd := me.move_cd / t.rtg_move_cooldown
		return [
			{"id": "juke", "label": "JUKE", "cd": maxf(me.juke_cd / t.rtg_juke_cooldown, gcd)},
			burst,
			{"id": "spin", "label": "SPIN", "cd": maxf(me.spin_cd / t.rtg_spin_cooldown, gcd)},
			{"id": "power", "label": "POWER", "cd": maxf(me.power_cd / t.rtg_power_cooldown, gcd)},
			{"id": "dive", "label": "DIVE", "cd": 0.0},
		]
	var ball := runner.ball
	if me.team == PlayerAgent.Team.OFFENSE:
		if passer or me == runner.qb:
			return []   # the right thumb aims
		if ball.state == Ball.State.AIR:
			var mine := runner.intended == me or me.field_pos.distance_to(ball.to) < 4.0
			var hot := mine and ball.time_left() <= t.rtg_catch_window + 0.1
			return [{"id": "catch", "label": "CATCH", "cd": 0.0 if runner.catch_pressed_at < 0.0 else 1.0, "hot": hot}, burst]
		if runner.qb_is_passer() and runner.handoff_to == null:
			return [{"id": "call", "label": "CALL", "cd": call_cd / t.rtg_call_cooldown,
					"hot": runner.play_time > 1.0 and call_cd <= 0.0}, burst]
		return [burst]
	# Defense.
	if ball.state == Ball.State.AIR:
		var near := me.field_pos.distance_to(ball.to) <= t.jump_start_range
		return [{"id": "ball", "label": "BALL", "cd": 0.0 if me.jump_timer <= 0.0 else 1.0,
				"hot": near and ball.time_left() <= t.jump_time + 0.15}, burst]
	var c := runner.carrier
	if c != null and c.team == PlayerAgent.Team.OFFENSE and (c != runner.qb or runner.scrambling or runner.pass_thrown):
		var in_range := me.field_pos.distance_to(c.field_pos) <= t.human_dive_range
		return [{"id": "tackle", "label": "TACKLE", "cd": 0.0, "hot": in_range}, burst]
	if not _jam_tried and runner.play_time <= t.rtg_jam_window:
		var close := false
		for o in runner.offense:
			if o.is_eligible() and o.field_pos.distance_to(me.field_pos) <= t.rtg_press_range:
				close = true
		if close:
			return [{"id": "jam", "label": "JAM", "cd": 0.0, "hot": true}, burst]
	if c != null and c == runner.qb:
		return [{"id": "tackle", "label": "TACKLE", "cd": 0.0,
				"hot": me.field_pos.distance_to(c.field_pos) <= t.human_dive_range}, burst]
	return [burst]


## A button went down (RtgPad), or a test / bot presses it.
func press(id: String) -> void:
	if not _live():
		return
	var me := _me()
	var t := tuning
	match id:
		"burst":
			me.burst_scale = t.rtg_burst_mult
			if me.start_burst(t, t.rtg_burst_time):
				me.burst_cd = t.rtg_burst_cooldown
				Sfx.play("whoosh")
		"juke":
			var head := _heading(me)
			var lat := Vector2(-head.y, head.x)
			var side := 0.0
			var s := stick_to_field(pad.stick) if pad != null else Vector2.ZERO
			if absf(s.dot(lat)) > 0.25:
				side = signf(s.dot(lat))
			else:
				var d := _nearest_opponent(me, 6.0)
				side = -signf((d.field_pos - me.field_pos).dot(lat)) if d != null else 1.0
				if side == 0.0:
					side = 1.0
			if me.start_rtg_juke(t, lat * side):
				_bite(me, head)
				action.emit("JUKE", me.field_pos, true)
				Sfx.play("whoosh")
		"spin":
			if me.start_spin(t):
				_bite(me, _heading(me), 0.6)
				action.emit("SPIN", me.field_pos, true)
				Sfx.play("whoosh")
		"power":
			var head := _heading(me)
			var d := _nearest_opponent(me, 3.5)
			var kind := "stiff"
			if d != null and head.dot((d.field_pos - me.field_pos).normalized()) >= 0.45:
				kind = "truck"
			if me.start_power(t, kind):
				action.emit("TRUCK" if kind == "truck" else "STIFF ARM", me.field_pos, true)
		"dive":
			if me.can_act() and me == runner.carrier:
				var fwd := Vector2(1.0 if me.team == PlayerAgent.Team.OFFENSE else -1.0, 0.0)
				me.start_dive(t, (fwd * 2.0 + _heading(me)).normalized())
		"call":
			if call_cd <= 0.0 and runner.qb_is_passer():
				runner.call_for_ball()
				call_cd = t.rtg_call_cooldown
				action.emit("I'M OPEN!", me.field_pos, true)
		"catch":
			# Only a tap inside the window counts; an early one is simply ignored (tap again).
			if runner.ball.state == Ball.State.AIR and runner.catch_pressed_at < 0.0 \
					and runner.ball.time_left() <= t.rtg_catch_window:
				runner.catch_pressed_at = runner.play_time
				action.emit("MOSSED!" if me.field_pos.distance_to(runner.ball.to) < 3.0 else "HIGH POINT!", me.field_pos, true)
				if me.can_act() and me.field_pos.distance_to(runner.ball.to) <= t.rtg_catch_reach + t.catch_radius + 1.0:
					me.start_jump(t, runner.ball.to)   # go up and get it
		"jam":
			_jam_tried = true
			if runner.rtg_jam(me):
				action.emit("JAM!", me.field_pos, true)
				Sfx.play("hit")
		"ball":
			if runner.ball.state == Ball.State.AIR:
				if me.field_pos.distance_to(runner.ball.to) <= t.jump_start_range:
					runner.defender_jump(me)
				else:
					me.brain = BallHawkBrain.new(me, runner, runner.ball.to, 0.0, me.brain)
		"tackle":
			var c := runner.carrier
			if c != null and c.team != me.team and me.can_dive() \
					and me.field_pos.distance_to(c.field_pos) <= t.human_dive_range:
				me.start_dive(t, c.field_pos + c.velocity * 0.12 - me.field_pos, t.dive_recover)


## Defenders close in front of a juking / spinning carrier lose their read for a moment.
func _bite(me: PlayerAgent, head: Vector2, scale := 1.0) -> void:
	for d in _opponents(me):
		if d.is_down or d.engaged_with != null or d.brain == null:
			continue
		var to := d.field_pos - me.field_pos
		if to.length() > tuning.rtg_juke_bite_range or head.dot(to.normalized()) < 0.1:
			continue
		var bite := RatingModel.juke_bite(tuning, me.attr("elu"), d.attr("awr")) * scale
		d.brain._think_timer = maxf(d.brain._think_timer, bite)


# ---------------------------------------------------------------- corner read

## The receiver you cover about to break: tele_agent / tele_dir (null when none).
func _update_telegraph() -> void:
	tele_agent = null
	var me := _me()
	if me == null or me.team != PlayerAgent.Team.DEFENSE or runner.pass_thrown or runner.carrier != runner.qb:
		return
	var mark: PlayerAgent = (me.brain as ManCoverBrain).mark if me.brain is ManCoverBrain else null
	if mark == null:
		var best_d := 9.0
		for o in runner.offense:
			if o.is_eligible() and not o.is_down and o.field_pos.distance_to(me.field_pos) < best_d:
				best_d = o.field_pos.distance_to(me.field_pos)
				mark = o
	if mark == null or not (mark.brain is RouteBrain) or mark.human:
		return
	var rb := mark.brain as RouteBrain
	if rb.delay > 0.0 or rb.idx >= rb.points.size() - 1:
		return
	var at := rb.points[rb.idx]
	var prev := mark.start_pos if rb.idx == 0 else rb.points[rb.idx - 1]
	var cur := (at - prev).normalized()
	var nxt := (rb.points[rb.idx + 1] - at).normalized()
	if cur.dot(nxt) > 0.87:
		return   # no real break (under ~30°)
	var eta := mark.field_pos.distance_to(at) / maxf(mark.velocity.length(), 1.0)
	if eta <= RatingModel.telegraph_time(tuning, me.attr("awr"), mark.attr("rte")):
		tele_agent = mark
		tele_dir = nxt
