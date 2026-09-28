class_name DefenderBot
extends RefCounted
## "Human-like" autoplay for the human's defender (sandbox `--defend --bot`, sims and
## recordings). It only uses what a player can do — the stick, SWITCH, dive and jump taps
## (HumanDefenseControl) — with a human reaction delay and some sloppiness:
##   QB holding a pass  - hands off: the defender plays his call (most players watch here);
##   ball in the air    - SWITCH if his man can't get there, run to the marker, jump late-ish;
##   ball carried       - SWITCH if his man is out of the play (blocked, down, trailing),
##                        run an intercept angle into the carrier, sometimes dive.
## `skill` 0..1 scales reaction time, pursuit angle and how eagerly he switches.

var ctl: HumanDefenseControl
var runner: PlayRunner
var rng := RandomNumberGenerator.new()
var skill := 0.5

var _state := ""
var _since := 0.0
var _switch_cd := 0.0
var _jumped := false
var _jump_err := 0.0
var _will_jump := false
## Counters for the sim printout.
var stats := {"switches": 0, "dives": 0, "jumps": 0}


func _init(p_ctl: HumanDefenseControl, p_runner: PlayRunner, p_skill := 0.5, p_seed := 0) -> void:
	ctl = p_ctl
	runner = p_runner
	skill = clampf(p_skill, 0.0, 1.0)
	if p_seed != 0:
		rng.seed = p_seed
	else:
		rng.randomize()


## Call every physics frame before the runner steps.
func step(dt: float) -> void:
	if runner.phase != PlayRunner.Phase.LIVE or runner.human_team != PlayerAgent.Team.DEFENSE:
		_state = ""
		return
	var me := runner.controlled
	if me == null:
		return
	_switch_cd -= dt
	var st := _read_state()
	if st != _state:
		_state = st
		_since = 0.0
		_jumped = false
		_jump_err = rng.randfn(0.0, lerpf(0.2, 0.08, skill))
		# Most players only go up for some balls; the rest they just run at.
		_will_jump = rng.randf() < lerpf(0.25, 0.6, skill)
	_since += dt
	# Human reaction: keep doing what you were doing until the new situation registers.
	if _since < lerpf(0.45, 0.2, skill):
		return
	match st:
		"pre":
			ctl.set_stick(Vector2.ZERO)
		"air":
			_play_ball(me)
		"carry":
			_pursue(me)
		_:
			ctl.set_stick(Vector2.ZERO)


func _read_state() -> String:
	if runner.ball.state == Ball.State.AIR:
		return "air"
	var c := runner.carrier
	if c == null or c.team != PlayerAgent.Team.OFFENSE:
		return "return"
	if c == runner.qb and runner.qb_is_passer():
		return "pre"
	return "carry"


func _switch() -> void:
	ctl.switch_to_ball()
	stats["switches"] += 1
	_switch_cd = lerpf(1.6, 0.8, skill)


func _play_ball(me: PlayerAgent) -> void:
	var to := runner.ball.to
	var left := runner.ball.time_left()
	var need := me.field_pos.distance_to(to) / maxf(me.max_speed, 1.0)
	if _switch_cd <= 0.0 and (need > left + 0.4 or not me.can_act()):
		_switch()
		me = runner.controlled
	ctl.set_stick((to - me.field_pos).normalized() if me.field_pos.distance_to(to) > 0.4 else Vector2.ZERO)
	if _will_jump and not _jumped and me.field_pos.distance_to(to) <= runner.tuning.jump_start_range \
			and left <= runner.tuning.jump_time * 0.5 + _jump_err:
		_jumped = true
		if ctl.try_jump():
			stats["jumps"] += 1


func _pursue(me: PlayerAgent) -> void:
	var c := runner.carrier
	var t := runner.tuning
	var dist := me.field_pos.distance_to(c.field_pos)
	var out_of_play := me.is_down or me.engaged_with != null or c.field_pos.x - me.field_pos.x > 3.0
	if _switch_cd <= 0.0 and (out_of_play or dist > 9.0):
		var better := ctl.switcher.best_defender(me)
		if better != null and better.field_pos.distance_to(c.field_pos) < dist - 2.0:
			_switch()
			me = runner.controlled
			dist = me.field_pos.distance_to(c.field_pos)
	var lead := lerpf(0.35, 0.8, skill)
	var aim := c.field_pos + c.velocity * (dist / maxf(me.max_speed, 1.0)) * lead
	ctl.set_stick((aim - me.field_pos).normalized())
	# Tap to dive now and then when he is just out of wrapping range.
	if dist > t.human_tackle_range and dist < t.human_dive_range * 0.75 and rng.randf() < 0.04:
		if ctl.try_dive():
			stats["dives"] += 1
