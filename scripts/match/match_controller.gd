class_name MatchController
extends Node2D
## A full game (PLAN.md §1/§4): kickoff → play calls → live plays → PATs/FGs/punts →
## quarters, halftime, two-minute warnings, overtime → final. The human plays offense when
## his team has the ball and defense otherwise; the CPU calls and plays the other side.
## User args (after "--"):
##   --home=KC --away=PHI   teams (home = the human's team)
##   --watch                CPU vs CPU, rendered (a demo)
##   --ai-vs-ai=N           headless: N CPU-vs-CPU games stepped as fast as possible, print averages
##   --quarter=MIN          real minutes per quarter (default Settings.quarter_minutes)
##   --pace=P               defense pace override (every | key | highlights)

enum Phase { PREGAME, PLAY_CALL, LIVE, RESULT, PAT_CHOICE, KICK_METER, BREAK, FINAL, PAUSED }

const DT := 1.0 / 60.0

@export var tuning: GameplayTuning = preload("res://data/tuning/gameplay_tuning.tres")
@export var offense_book: PlaybookDef = preload("res://data/plays/offense_playbook.tres")
@export var defense_book: PlaybookDef = preload("res://data/plays/defense_playbook.tres")
@export var def_ai: DefenseAITuning = preload("res://data/tuning/defense_ai_tuning.tres")

## Set before adding to the tree to configure the match (Phase 4 hub passes a MatchConfig).
var config: Dictionary = {}

var phase := Phase.PREGAME
var gs: GameState
var teams: Dictionary = {}          ## abbr -> TeamData
var lineups: Dictionary = {}        ## abbr -> {"offense": {...}, "defense": {...}, "K": attrs}
var human := ""                     ## the human's team abbr ("" = CPU vs CPU)
var memory: DefenseMemory           ## CPU defense learning the human offense
var off_play: PlayDef
var def_play: PlayDef
var last_def_call: PlayDef
var passer: CpuPasser
var pace: int = DefensePace.Pace.EVERY_SNAP
var sim_games := 0                  ## >0: headless batch mode
var watch := false
var rng := RandomNumberGenerator.new()

var _seconds_before_play := 0.0
var _pending_runoff := 0.0
var _two_point := false
var _kick_kind := ""                ## "fg" / "pat" while the kick meter is up
var _queued: Callable               ## sim mode: next transition (instead of a timer)
var _paused_from := Phase.PLAY_CALL
var _kickoff_pending := ""           ## team that must kick off when the next quarter starts
var _sim_totals: Dictionary = {}
var _games_done := 0

var field: FieldView
var routes: PlayOverlay
var runner: PlayRunner
var aim: PlayOverlay
var camera: CameraRig
var hud: MatchHUD
var touch: TouchInput
var ocontrol: HumanOffenseControl
var dcontrol: HumanDefenseControl
var overlay: DebugOverlay


func _ready() -> void:
	var home_abbr: String = config.get("home", "KC")
	var away_abbr: String = config.get("away", "PHI")
	var quarter_min: float = config.get("quarter_minutes", Settings.quarter_minutes)
	pace = Settings.defense_pace
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--home="):
			home_abbr = arg.get_slice("=", 1).to_upper()
		elif arg.begins_with("--away="):
			away_abbr = arg.get_slice("=", 1).to_upper()
		elif arg == "--watch":
			watch = true
		elif arg.begins_with("--ai-vs-ai="):
			sim_games = int(arg.get_slice("=", 1))
		elif arg.begins_with("--quarter="):
			quarter_min = float(arg.get_slice("=", 1))
		elif arg.begins_with("--pace="):
			pace = DefensePace.from_name(arg.get_slice("=", 1))
	rng.randomize()
	teams = TeamData.load_all()
	if not teams.has(home_abbr):
		home_abbr = "KC"
	if not teams.has(away_abbr) or away_abbr == home_abbr:
		away_abbr = "PHI" if home_abbr != "PHI" else "KC"
	human = "" if watch or sim_games > 0 else home_abbr
	memory = DefenseMemory.new(def_ai)
	_build_scene(teams[home_abbr], teams[away_abbr])
	lineups[home_abbr] = config.get("home_lineup", _generic_lineups(int(config.get("home_ovr", 78))))
	lineups[away_abbr] = config.get("away_lineup", _generic_lineups(int(config.get("away_ovr", 78))))
	gs = GameState.new(home_abbr, away_abbr, quarter_min * 60.0)
	if sim_games > 0:
		_run_sim_batch.call_deferred()
	else:
		_start_game()


# ---------------------------------------------------------------- scene

func _build_scene(home_team: TeamData, away_team: TeamData) -> void:
	field = FieldView.new()
	field.set_teams(home_team, away_team)
	add_child(field)
	runner = PlayRunner.new()
	runner.tuning = tuning
	runner.def_ai = def_ai
	runner.rng = rng
	routes = PlayOverlay.new()
	routes.kind = PlayOverlay.Kind.ROUTES
	routes.runner = runner
	add_child(routes)
	add_child(runner)
	aim = PlayOverlay.new()
	aim.kind = PlayOverlay.Kind.AIM
	aim.runner = runner
	aim.show_landing = true
	aim.z_index = 5
	add_child(aim)
	overlay = DebugOverlay.new()
	overlay.runner = runner
	add_child(overlay)
	camera = CameraRig.new()
	camera.runner = runner
	add_child(camera)
	camera.make_current()
	hud = MatchHUD.new()
	add_child(hud)
	hud.play_selected.connect(_on_play_selected)
	hud.special_pressed.connect(_on_special)
	hud.pause_pressed.connect(_pause)
	hud.choice_made.connect(_on_choice)
	hud.kick_meter.kicked.connect(_on_kicked)
	touch = TouchInput.new()
	touch.ui_blocker = hud.is_point_over_ui
	add_child(touch)
	touch.tapped.connect(_on_tap)
	touch.three_finger_tap.connect(overlay.toggle)
	ocontrol = HumanOffenseControl.new()
	add_child(ocontrol)
	ocontrol.bind(runner, touch, tuning)
	ocontrol.snap_requested.connect(func() -> void:
		if phase == Phase.PLAY_CALL and _human_offense():
			_snap())
	ocontrol.aim_changed.connect(func(on: bool, target: Vector2) -> void:
		aim.aim_active = on
		aim.aim_target = target)
	dcontrol = HumanDefenseControl.new()
	add_child(dcontrol)
	dcontrol.bind(runner, touch, tuning)
	dcontrol.ready_tapped.connect(func() -> void:
		if phase == Phase.PLAY_CALL and _human_defense():
			_snap())
	runner.play_ended.connect(_on_play_ended)


## Placeholder lineups (Phase 4 replaces them with real roster cards): every slot gets
## position-profile ratings at one OVR.
static func _generic_lineups(ovr: int) -> Dictionary:
	var off := {}
	var def := {}
	var o_form: FormationDef = load("res://data/formations/off_shotgun.tres")
	var d_form: FormationDef = load("res://data/formations/def_base.tres")
	var n := 2
	for slot in o_form.slots:
		off[slot] = {"name": slot, "jersey": n, "attrs": RatingModel.fill_attrs(o_form.slots[slot]["pos"], ovr)}
		n += 9
	for slot in d_form.slots:
		def[slot] = {"name": slot, "jersey": n % 99, "attrs": RatingModel.fill_attrs(d_form.slots[slot]["pos"], ovr)}
		n += 7
	return {"offense": off, "defense": def, "K": RatingModel.fill_attrs("K", ovr)}


func _sim() -> bool:
	return sim_games > 0


func _human_offense() -> bool:
	return human != "" and gs.possession == human


func _human_defense() -> bool:
	return human != "" and gs.possession != human


## Runs `fn` after `delay` seconds (immediately queued in headless sim mode).
func _after(delay: float, fn: Callable) -> void:
	if _sim():
		_queued = fn
		return
	get_tree().create_timer(delay).timeout.connect(fn)


func _kicker(team: String) -> Dictionary:
	return lineups[team].get("K", RatingModel.fill_attrs("K", 75))


# ---------------------------------------------------------------- game flow

func _start_game() -> void:
	phase = Phase.PREGAME
	hud.show_pause_button(human != "")
	# Coin toss: the human (or the home team) receives the opening kickoff.
	gs.opening_receiver = gs.home
	var h: TeamData = teams[gs.home]
	var a: TeamData = teams[gs.away]
	if not _sim():
		hud.show_banner("%s  VS  %s" % [h.team_name.to_upper(), a.team_name.to_upper()], "KICKOFF", 1.8)
	_after(1.8, func() -> void: _kickoff(gs.away))


## `kicker` kicks off; the other team starts a possession.
func _kickoff(kicker: String) -> void:
	var receiver := gs.other(kicker)
	var x := KickModel.kickoff(tuning, rng, float(_kicker(kicker).get("kpw", 75)))
	gs.start_possession(receiver, x)
	gs.clock.stopped = true
	if not _sim():
		var ret := "TOUCHBACK" if is_equal_approx(x, FieldGeo.OWN_GOAL + tuning.touchback_yard) else "RETURNED TO THE %s" % FieldGeo.spot_text(x)
		hud.show_banner("KICKOFF", "%s  ·  %s BALL" % [ret, receiver], 1.4)
	_after(1.4, _start_play_call)


func _situation() -> Dictionary:
	return gs.situation()


func _start_play_call() -> void:
	if gs.clock.expired():
		_end_period()
		return
	phase = Phase.PLAY_CALL
	hud.hide_choice()
	var off_team: TeamData = teams[gs.possession]
	var def_team: TeamData = teams[gs.defense()]
	field.set_possession(off_team, def_team)
	runner.off_colors = off_team.uniform_colors()
	runner.def_colors = def_team.uniform_colors()
	runner.human_team = PlayerAgent.Team.OFFENSE if _human_offense() else (
			PlayerAgent.Team.DEFENSE if _human_defense() else -1)
	runner.human_input = ocontrol if _human_offense() else (dcontrol if _human_defense() else null)
	_pending_runoff = 0.0 if gs.clock.stopped else gs.runoff(tuning)
	_cpu_timeouts()
	var situation := _situation()
	hud.set_special_actions([] as Array[String])
	# CPU 4th-down decisions (punt / field goal) happen before any play is shown.
	if not _human_offense() and gs.downs.down == 4 and not _two_point:
		var k := _kicker(gs.possession)
		var dist := KickModel.fg_distance(gs.downs.los_x)
		var call := AIPlayCaller.fourth_down(situation, dist, KickModel.fg_max_range(tuning, float(k.get("kpw", 75))))
		if call == "punt":
			_punt()
			return
		if call == "fg":
			_field_goal_cpu(dist)
			return
	if _human_offense():
		def_play = AIPlayCaller.pick_defense(defense_book.plays, memory, situation, rng, last_def_call)
		var ranked := PlayAdvisor.rank(offense_book.plays, situation, memory)
		off_play = ranked[0]
		hud.set_play_options(ranked, offense_book.plays)
		hud.set_selected(off_play)
		hud.set_keyed(offense_book.plays, memory.keyed_play())
		_update_snap_hint()
		_offer_specials()
	elif _human_defense():
		off_play = PlayAdvisor.pick(offense_book.plays, situation, rng)
		var ranked_d := _ranked_defense(situation)
		def_play = ranked_d[0]
		hud.set_play_options(ranked_d, defense_book.plays)
		hud.set_selected(def_play)
		hud.set_keyed(defense_book.plays, "")
		hud.set_hint("PICK A DEFENSE  ·  TAP THE FIELD WHEN READY")
		_offer_specials()
	else:
		off_play = PlayAdvisor.pick(offense_book.plays, situation, rng)
		def_play = AIPlayCaller.pick_defense(defense_book.plays, null, situation, rng, last_def_call)
	if _two_point:
		_restrict_two_point_calls()
	last_def_call = def_play
	_setup_formation()
	hud.show_play_bar(human != "")
	_update_scorebug()
	if not _sim():
		camera.snap_to_target()
	if human == "":
		_after(0.8, func() -> void:
			if phase == Phase.PLAY_CALL:
				_snap())


func _ranked_defense(situation: Dictionary) -> Array[PlayDef]:
	var w := AIPlayCaller.defense_weights(defense_book.plays, null, situation)
	var idx: Array = range(defense_book.plays.size())
	idx.sort_custom(func(a: int, b: int) -> bool: return w[a] > w[b] if w[a] != w[b] else a < b)
	var out: Array[PlayDef] = []
	for i in idx:
		out.append(defense_book.plays[i])
	return out


## 2-point try: the CPU offense picks a short-yardage call; the human keeps any call.
func _restrict_two_point_calls() -> void:
	if not _human_offense():
		off_play = PlayAdvisor.pick(offense_book.plays, {"down": 3, "to_go": 2, "los_x": 108.0}, rng)


func _offer_specials() -> void:
	var actions: Array[String] = []
	if _human_offense() and gs.downs.down == 4 and not _two_point:
		actions.append("PUNT")
		var dist := KickModel.fg_distance(gs.downs.los_x)
		if dist <= KickModel.fg_max_range(tuning, float(_kicker(human).get("kpw", 75))) + 3.0:
			actions.append("FG %d" % int(dist))
	if human != "" and int(gs.timeouts[human]) > 0 and not gs.clock.stopped:
		actions.append("TIMEOUT %d" % int(gs.timeouts[human]))
	hud.set_special_actions(actions)


## CPU uses timeouts to save time late in a half when trailing (and on defense, when the
## human offense is milking the clock).
func _cpu_timeouts() -> void:
	for team in [gs.home, gs.away]:
		if team == human or gs.clock.stopped:
			continue
		var late := gs.clock.half_seconds_left() <= 110.0
		if late and gs.score_diff(team) < 0 and int(gs.timeouts[team]) > 0 and _pending_runoff > 0.0:
			gs.use_timeout(team)
			_pending_runoff = 0.0
			if not _sim():
				hud.show_banner("TIMEOUT", teams[team].team_name.to_upper(), 1.0)
			return


func _setup_formation() -> void:
	var off_l: Dictionary = lineups[gs.possession]["offense"]
	var def_l: Dictionary = lineups[gs.defense()]["defense"]
	runner.setup_play(off_play, def_play, gs.downs.los_x, _ball_y(), off_l, def_l)
	field.los_x = gs.downs.los_x
	field.first_down_x = gs.downs.first_down_x
	field.down = gs.downs.down
	dcontrol.switcher.reset()


var _spot_y := FieldGeo.CENTER_Y


func _ball_y() -> float:
	return _spot_y


func _update_scorebug() -> void:
	var h: String = gs.home
	var a: String = gs.away
	# "*" marks the team with the ball.
	var line1 := "%s%s %d  %s%s %d  ·  %s" % ["*" if gs.possession == h else "", h, gs.score[h],
			"*" if gs.possession == a else "", a, gs.score[a], gs.clock.label()]
	var spot := FieldGeo.spot_text(gs.downs.los_x)
	var to := "TO %d-%d" % [gs.timeouts[h], gs.timeouts[a]]
	var line2 := "%s  ·  %s  ·  %s" % [gs.downs.down_text() if not _two_point else "2-PT TRY", spot, to]
	hud.set_scorebug(line1, line2)


func _update_snap_hint() -> void:
	if off_play.is_run():
		hud.set_hint("PRESS THE QB TO SNAP  ·  HOLD + DRAG UP/DOWN TO STEER")
	else:
		hud.set_hint("DRAG FROM THE QB: BACK = AIM  ·  FORWARD = RUN  ·  OR TAP")


func _on_play_selected(play: PlayDef) -> void:
	if phase != Phase.PLAY_CALL:
		return
	if _human_defense():
		def_play = play
	else:
		off_play = play
	hud.set_selected(play)
	_setup_formation()
	if _human_offense():
		_update_snap_hint()


func _on_tap(_pos: Vector2) -> void:
	if phase == Phase.PLAY_CALL and _human_offense():
		_snap()
	elif phase == Phase.KICK_METER:
		hud.kick_meter.stop_and_kick()


func _on_special(action: String) -> void:
	if phase != Phase.PLAY_CALL:
		return
	match action:
		"PUNT":
			if _human_offense() and gs.downs.down == 4:
				_punt()
		"FG":
			if _human_offense() and gs.downs.down == 4:
				_start_kick_meter("fg")
		"TIMEOUT":
			if gs.use_timeout(human):
				_pending_runoff = 0.0
				hud.show_banner("TIMEOUT", "%d LEFT" % gs.timeouts[human], 1.0)
				_offer_specials()
				_update_scorebug()


func _process(delta: float) -> void:
	# The play clock "runs" while the play is called: tick the runoff down in real time.
	if phase == Phase.PLAY_CALL and _pending_runoff > 0.0 and not _sim():
		var step := minf(_pending_runoff, delta * gs.clock.speed * 0.5)
		_pending_runoff -= step
		if gs.clock.apply_runoff(step):
			_pending_runoff = 0.0
			hud.show_banner("TWO-MINUTE WARNING", "", 1.4)
		_update_scorebug()
		if gs.clock.expired():
			_pending_runoff = 0.0
			_end_period()


# ---------------------------------------------------------------- live play

func _snap() -> void:
	if phase != Phase.PLAY_CALL:
		return
	# Whatever runoff is left comes off at the snap.
	if _pending_runoff > 0.0:
		var warn := gs.clock.apply_runoff(_pending_runoff)
		_pending_runoff = 0.0
		if gs.clock.expired():
			_end_period()
			return
		if warn and not _sim():
			hud.show_banner("TWO-MINUTE WARNING", "", 1.4)
	phase = Phase.LIVE
	hud.show_play_bar(false)
	hud.set_special_actions([] as Array[String])
	hud.set_keyed(offense_book.plays, "")
	_seconds_before_play = gs.clock.seconds_left
	gs.clock.stopped = false
	runner.key_level = memory.key_level(off_play.id, off_play.formation.id, off_play.category) \
			if _human_offense() else 0.0
	var auto_sim := _human_defense() and not DefensePace.human_plays(pace, _situation())
	if auto_sim:
		runner.human_team = -1
		runner.human_input = null
	runner.snap()
	var cpu_passing := not _human_offense() and not off_play.is_run()
	passer = CpuPasser.new(runner, rng) if cpu_passing else null
	if auto_sim and not _sim():
		_simulate_play()
		return
	if _human_defense():
		hud.set_hint("DRAG TO MOVE  ·  TAP THE CARRIER TO DIVE  ·  TAP THE BALL MARKER TO JUMP")
	elif _human_offense():
		hud.set_hint("DRAG UP/DOWN TO STEER  ·  FLICK TO JUKE  ·  DOUBLE-TAP TO DIVE" if off_play.is_run()
				else "DRAG BACK TO AIM, RELEASE TO THROW  ·  DRAG FORWARD TO RUN")
	else:
		hud.set_hint("")


## Defense-pace auto-sim: run the whole play now and just show the result.
func _simulate_play() -> void:
	var guard := int(PlayRunner.WATCHDOG_SECONDS / DT) + 200
	while phase == Phase.LIVE and guard > 0:
		guard -= 1
		_step_live(DT)


func _physics_process(dt: float) -> void:
	if _sim() or phase != Phase.LIVE:
		return
	# PlayRunner steps itself; we tick the clock and drive the CPU QB / switcher.
	gs.clock.tick_live(dt)
	if passer != null:
		passer.update(dt)
	if _human_defense():
		dcontrol.update(dt)


## Manual stepping (sim batch and defense-pace auto-sim).
func _step_live(dt: float) -> void:
	gs.clock.tick_live(dt)
	if passer != null:
		passer.update(dt)
	runner._physics_process(dt)


func _on_play_ended(r: Dictionary) -> void:
	if phase != Phase.LIVE:
		return
	phase = Phase.RESULT
	runner.human_team = -1
	hud.set_hint("")
	if int(runner.play_time) >= int(PlayRunner.WATCHDOG_SECONDS):
		r["watchdog"] = 1
	if _human_offense():
		var gained: int = r["yards"] if r["type"] not in ["incomplete", "int", "int_td", "fumble"] else 0
		memory.record(off_play.id, off_play.formation.id, off_play.category,
				-10 if r["turnover"] else gained, off_play.display_name)
	_spot_y = FieldGeo.clamp_to_hashes(r["spot_y"])
	if _two_point:
		_finish_two_point(r)
		return
	var offense := gs.possession
	var next := gs.apply_result(r, off_play.is_run(), _seconds_before_play)
	var headline: String = r["text"]
	var type: String = r["type"]
	if headline == "" or type == "out":
		headline = _yards_text(int(r["yards"]))
	elif type == "sack":
		headline = "SACKED  %d" % int(r["yards"])
	var sub := gs.last_event if gs.last_event != "" else gs.downs.down_text()
	if gs.possession != offense and next == GameState.Next.PLAY:
		sub = "%s BALL" % gs.possession
		_spot_y = FieldGeo.CENTER_Y
	if not _sim():
		hud.show_banner(headline, sub, 1.5)
	_update_scorebug()
	match next:
		GameState.Next.PAT:
			_after(1.6, _pat_phase)
		GameState.Next.FREE_KICK:
			_after(1.6, func() -> void: _free_kick(gs.possession))
		GameState.Next.END_PERIOD:
			_after(1.4, _end_period)
		_:
			if _ot_over():
				_after(1.4, _final)
			else:
				_after(1.4, _start_play_call)


func _yards_text(yards: int) -> String:
	if yards > 0:
		return "GAIN OF %d" % yards
	if yards < 0:
		return "LOSS OF %d" % -yards
	return "NO GAIN"


# ---------------------------------------------------------------- kicks & tries

func _punt() -> void:
	phase = Phase.RESULT
	var kicker := gs.possession
	gs.stats[kicker]["punts"] += 1
	var x := KickModel.punt(tuning, rng, float(_kicker(kicker).get("kpw", 75)), gs.downs.los_x)
	gs.clock.tick_live(6.0 / gs.clock.speed)
	gs.finish_drive(true, gs.clock.seconds_left)
	gs.start_possession(gs.other(kicker), x)
	_spot_y = FieldGeo.CENTER_Y
	if not _sim():
		hud.show_banner("PUNT", "%s BALL AT THE %s" % [gs.possession, FieldGeo.spot_text(x)], 1.5)
	_update_scorebug()
	if gs.clock.expired():
		_after(1.5, _end_period)
	elif _ot_over():
		_after(1.5, _final)
	else:
		_after(1.5, _start_play_call)


func _field_goal_cpu(dist: float) -> void:
	var k := _kicker(gs.possession)
	var good := rng.randf() < KickModel.fg_prob(tuning, dist, float(k.get("kpw", 75)), float(k.get("kac", 75)))
	_resolve_field_goal(good, dist, "GOOD!" if good else "NO GOOD")


func _resolve_field_goal(good: bool, dist: float, text: String) -> void:
	phase = Phase.RESULT
	var kicker := gs.possession
	gs.stats[kicker]["fg_att"] += 1
	gs.clock.tick_live(5.0 / gs.clock.speed)
	gs.finish_drive(true, gs.clock.seconds_left)
	if not _sim():
		hud.show_banner("%d-YARD FIELD GOAL" % int(dist), text, 1.6)
	if good:
		gs.stats[kicker]["fg_made"] += 1
		gs.add_points(kicker, 3)
		_update_scorebug()
		if _ot_over():
			_after(1.6, _final)
		elif gs.clock.expired():
			_kickoff_pending = kicker
			_after(1.6, _end_period)
		else:
			_after(1.6, func() -> void: _kickoff(kicker))
		return
	# Miss: the defense takes over at the spot of the kick (or its 20, whichever is better).
	var spot := maxf(FieldGeo.LENGTH - (gs.downs.los_x - 7.0), FieldGeo.OWN_GOAL + 20.0)
	gs.start_possession(gs.other(kicker), spot)
	_update_scorebug()
	if gs.clock.expired():
		_after(1.6, _end_period)
	elif _ot_over():
		_after(1.6, _final)
	else:
		_after(1.6, _start_play_call)


## After a touchdown: kick the extra point or go for two.
func _pat_phase() -> void:
	var team := gs.possession
	if team == human:
		phase = Phase.PAT_CHOICE
		hud.show_play_bar(false)
		hud.set_special_actions([] as Array[String])
		hud.show_choice("EXTRA POINT", "%s %d  %s %d" % [gs.home, gs.score[gs.home], gs.away, gs.score[gs.away]],
				["KICK PAT (1)", "GO FOR 2"] as Array[String])
		return
	var diff := gs.score_diff(team)
	if AIPlayCaller.go_for_two(diff, gs.clock.quarter):
		_begin_two_point()
	else:
		var k := _kicker(team)
		var good := rng.randf() < KickModel.fg_prob(tuning, 33.0, float(k.get("kpw", 75)), float(k.get("kac", 75)))
		_finish_pat(good, 1)


func _on_choice(index: int) -> void:
	match phase:
		Phase.PAT_CHOICE:
			if index == 0:
				_start_kick_meter("pat")
			else:
				_begin_two_point()
		Phase.PAUSED:
			_on_pause_choice(index)
		Phase.FINAL:
			get_tree().reload_current_scene()


func _begin_two_point() -> void:
	_two_point = true
	gs.downs.start_drive(FieldGeo.OPP_GOAL - 2.0)
	_spot_y = FieldGeo.CENTER_Y
	if not _sim():
		hud.show_banner("2-POINT TRY", "", 1.0)
	_after(1.0, _start_play_call)


func _finish_two_point(r: Dictionary) -> void:
	_two_point = false
	var good: bool = r["type"] == "td" or (r["type"] in ["tackle", "out"] and float(r["spot_x"]) >= FieldGeo.OPP_GOAL)
	gs.clock.stopped = true
	_finish_pat(good, 2)


func _finish_pat(good: bool, pts: int) -> void:
	phase = Phase.RESULT
	var team := gs.possession
	if good:
		gs.add_points(team, pts)
	if not _sim():
		var what := "EXTRA POINT" if pts == 1 else "2-POINT TRY"
		hud.show_banner(what, "GOOD!" if good else "NO GOOD", 1.3)
	_update_scorebug()
	if _ot_over():
		_after(1.3, _final)
	elif gs.clock.expired():
		_kickoff_pending = team
		_after(1.3, _end_period)
	else:
		_after(1.3, func() -> void: _kickoff(team))


func _start_kick_meter(kind: String) -> void:
	phase = Phase.KICK_METER
	_kick_kind = kind
	hud.show_play_bar(false)
	hud.set_special_actions([] as Array[String])
	var k := _kicker(human)
	var dist := 33.0 if kind == "pat" else KickModel.fg_distance(gs.downs.los_x)
	var title := "EXTRA POINT" if kind == "pat" else "%d-YARD FIELD GOAL" % int(dist)
	hud.kick_meter.start(title, KickModel.meter_zone(tuning, dist, float(k.get("kac", 75))), tuning.meter_doink,
			KickModel.meter_speed(tuning, dist))
	hud.set_hint("TAP WHEN THE NEEDLE IS IN THE GREEN")


func _on_kicked(needle: float) -> void:
	if phase != Phase.KICK_METER:
		return
	var k := _kicker(human)
	var dist := 33.0 if _kick_kind == "pat" else KickModel.fg_distance(gs.downs.los_x)
	var res := KickModel.meter_result(tuning, needle, dist, float(k.get("kpw", 75)), float(k.get("kac", 75)))
	var text: String = {"good": "GOOD!", "doink": "DOINK! NO GOOD", "wide": "WIDE - NO GOOD", "short": "SHORT - NO GOOD"}[res]
	_after(0.5, hud.kick_meter.hide_meter)
	hud.set_hint("")
	if _kick_kind == "pat":
		_finish_pat(res == "good", 1)
		if not _sim():
			hud.show_banner("EXTRA POINT", text, 1.3)
	else:
		_resolve_field_goal(res == "good", dist, text)


func _free_kick(kicker: String) -> void:
	var x := KickModel.free_kick(rng)
	gs.start_possession(gs.other(kicker), x)
	if not _sim():
		hud.show_banner("FREE KICK", "%s BALL" % gs.possession, 1.3)
	_after(1.3, _start_play_call)


# ---------------------------------------------------------------- periods & end

func _ot_over() -> bool:
	return gs.clock.is_overtime() and gs.overtime_decided()


func _end_period() -> void:
	if phase == Phase.BREAK or phase == Phase.FINAL:
		return
	phase = Phase.BREAK
	var ended_q := gs.clock.quarter
	var what := gs.clock.next_period()
	match what:
		"q2", "q4":
			if not _sim():
				hud.show_banner("END OF Q%d" % ended_q, "%s %d  %s %d" % [gs.home, gs.score[gs.home], gs.away, gs.score[gs.away]], 1.6)
			var kicker := _kickoff_pending
			_kickoff_pending = ""
			if kicker != "":
				_after(1.6, func() -> void: _kickoff(kicker))
			else:
				_after(1.6, _start_play_call)
		"half":
			_kickoff_pending = ""
			gs.reset_timeouts()
			if not _sim():
				hud.show_banner("HALFTIME", "%s %d  %s %d" % [gs.home, gs.score[gs.home], gs.away, gs.score[gs.away]], 2.2)
			# The team that received the opening kick kicks off the second half.
			_after(2.2, func() -> void: _kickoff(gs.opening_receiver))
		"regulation_over":
			_kickoff_pending = ""
			if gs.score[gs.home] == gs.score[gs.away]:
				gs.reset_timeouts()
				gs.ot_possessions = 0
				gs.overtime = true
				if not _sim():
					hud.show_banner("OVERTIME", "EACH TEAM GETS THE BALL", 2.0)
				_after(2.0, func() -> void: _kickoff(gs.away if gs.opening_receiver == gs.home else gs.home))
			else:
				_final()
		_:
			_final()


func _final() -> void:
	phase = Phase.FINAL
	hud.show_play_bar(false)
	hud.set_special_actions([] as Array[String])
	hud.set_hint("")
	if _sim():
		_record_sim_game()
		return
	var w := gs.winner()
	var title := "FINAL" if w == "" else ("YOU WIN!" if w == human else ("%s WIN" % teams[w].team_name.to_upper()))
	if human == "":
		title = "FINAL"
	hud.show_choice(title, _final_summary(), ["PLAY AGAIN"] as Array[String])


func _final_summary() -> String:
	var lines: Array[String] = []
	lines.append("%s %d  -  %d %s" % [gs.home, gs.score[gs.home], gs.score[gs.away], gs.away])
	for t in [gs.home, gs.away]:
		var s: Dictionary = gs.stats[t]
		lines.append("%s  PASS %d/%d %d  RUSH %d-%d  INT %d" % [t, s["pass_comp"], s["pass_att"], s["pass_yds"],
				s["rush_att"], s["rush_yds"], s["int"]])
	return "\n".join(lines)


# ---------------------------------------------------------------- pause menu

func _pause() -> void:
	if phase not in [Phase.PLAY_CALL, Phase.LIVE] or human == "":
		return
	_paused_from = phase
	phase = Phase.PAUSED
	runner.set_physics_process(false)
	var opts: Array[String] = ["RESUME", "DEFENSE PACE: %s" % DefensePace.NAMES[pace],
			"QUARTER: %.1f MIN (NEXT GAME)" % Settings.quarter_minutes, "RESTART GAME"]
	hud.show_choice("PAUSED", "%s  ·  %s %d  %s %d" % [gs.clock.label(), gs.home, gs.score[gs.home], gs.away, gs.score[gs.away]], opts)


func _on_pause_choice(index: int) -> void:
	match index:
		1:
			pace = (pace + 1) % DefensePace.NAMES.size()
			Settings.defense_pace = pace
			Settings.save_settings()
			phase = _paused_from
			_pause()
			return
		2:
			var lengths := [1.5, 2.5, 3.5, 5.0]
			var i := lengths.find(Settings.quarter_minutes)
			Settings.quarter_minutes = lengths[(i + 1) % lengths.size()]
			Settings.save_settings()
			phase = _paused_from
			_pause()
			return
		3:
			get_tree().reload_current_scene()
			return
	phase = _paused_from
	runner.set_physics_process(true)


# ---------------------------------------------------------------- ai vs ai batch

## Headless: plays `sim_games` CPU-vs-CPU games back to back, prints league averages.
func _run_sim_batch() -> void:
	runner.set_physics_process(false)
	set_physics_process(false)
	set_process(false)
	_sim_totals = {"games": 0, "points": 0, "pass_att": 0, "pass_comp": 0, "int": 0, "sacks": 0,
			"rush_att": 0, "rush_yds": 0, "pass_yds": 0, "plays": 0, "watchdog": 0, "fg_made": 0,
			"fg_att": 0, "punts": 0, "ot": 0, "ties": 0, "home_wins": 0, "max_pts": 0, "shutouts": 0}
	while _games_done < sim_games:
		_new_sim_game()
		var guard := 400000
		while phase != Phase.FINAL and guard > 0:
			guard -= 1
			if _queued.is_valid():
				var f := _queued
				_queued = Callable()
				f.call()
			elif phase == Phase.PLAY_CALL:
				_snap()
			elif phase == Phase.LIVE:
				_step_live(DT)
			else:
				break
		if phase != Phase.FINAL:
			push_error("ai_vs_ai: game %d got stuck in phase %d" % [_games_done, phase])
			_final()
	_print_sim_totals()
	get_tree().quit()


func _new_sim_game() -> void:
	gs = GameState.new(gs.home, gs.away, GameClock.QUARTER / gs.clock.speed)
	_kickoff_pending = ""
	memory.reset()
	last_def_call = null
	_two_point = false
	_queued = Callable()
	_start_game()


func _record_sim_game() -> void:
	_games_done += 1
	var t := _sim_totals
	t["games"] += 1
	if gs.overtime:
		t["ot"] += 1
	var w := gs.winner()
	if w == "":
		t["ties"] += 1
	elif w == gs.home:
		t["home_wins"] += 1
	for team in [gs.home, gs.away]:
		var s: Dictionary = gs.stats[team]
		t["points"] += int(gs.score[team])
		t["max_pts"] = maxi(t["max_pts"], int(gs.score[team]))
		if int(gs.score[team]) == 0:
			t["shutouts"] += 1
		for k in ["pass_att", "pass_comp", "int", "sacks", "rush_att", "rush_yds", "pass_yds", "plays",
				"watchdog", "fg_made", "fg_att", "punts"]:
			t[k] += int(s[k])
	if OS.get_cmdline_user_args().has("--verbose"):
		print("  game %d: %s %d - %d %s%s" % [_games_done, gs.home, gs.score[gs.home], gs.score[gs.away], gs.away,
				" (OT)" if gs.overtime else ""])


func _print_sim_totals() -> void:
	var t := _sim_totals
	var teams_n := maxf(t["games"] * 2, 1)
	print("AIVSAI %d games | %.1f pts/team (max %d, %d shutouts) | comp %.0f%% (%d/%d) | %.1f pass yds/team | %.2f INT/team | %.1f sacks/team | rush %.1f ypc, %.1f att/team | %.1f plays/team | FG %d/%d | %.1f punts/team | OT %d, ties %d | stuck plays %d" % [
		t["games"], t["points"] / teams_n, t["max_pts"], t["shutouts"],
		100.0 * t["pass_comp"] / maxf(t["pass_att"], 1), t["pass_comp"], t["pass_att"],
		t["pass_yds"] / teams_n, t["int"] / teams_n, t["sacks"] / teams_n,
		float(t["rush_yds"]) / maxf(t["rush_att"], 1), t["rush_att"] / teams_n, t["plays"] / teams_n,
		t["fg_made"], t["fg_att"], t["punts"] / teams_n, t["ot"], t["ties"], t["watchdog"]])
