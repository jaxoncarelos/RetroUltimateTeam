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
## What the choice panel is showing while PAUSED: the pause menu or the leave-game confirm.
enum PauseMenu { MAIN, CONFIRM_QUIT, CONFIRM_SIM }
## A halftime lead this big offers to sim the rest of the game (also in the pause menu).
const SIM_OFFER_LEAD := 28

const DEFENSE_PRESNAP_HINT := "DRAG FROM YOUR PLAYER TO DRAW HIS PATH  ·  TAP THE FIELD WHEN READY"
const DEFENSE_LIVE_HINT := "DRAG TO MOVE  ·  TAP = BURST  ·  TAP THE CARRIER TO DIVE"
const DEFENSE_AIR_HINT := "TAP THE BALL MARKER TO JUMP  ·  SWITCH = MAN NEAREST THE BALL"

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
var abilities := AbilityTracker.new()   ## the human lineup's X-Factor card abilities
var off_play: PlayDef
var def_play: PlayDef
var last_def_call: PlayDef
var passer: CpuPasser
var pace: int = DefensePace.Pace.EVERY_SNAP
## Retro Bowl style: the CPU's possessions are simulated as whole drives (no defense to play).
## Challenges (some are about stopping the opponent) and `--play-defense` keep playable defense.
var play_defense := false
var sim_games := 0                  ## >0: headless batch mode
var watch := false
var rng := RandomNumberGenerator.new()

var _seconds_before_play := 0.0
var _pending_runoff := 0.0
var _two_point := false
var _kick_kind := ""                ## "fg" / "pat" while the kick meter is up
var conditions: Dictionary = {}     ## GameConditions for this game (day/night + weather)
var _queued: Callable               ## sim mode: next transition (instead of a timer)
var _paused_from := Phase.PLAY_CALL
var _pause_menu := PauseMenu.MAIN
var _pause_queued := false           ## back/Esc outside a pausable moment: pause at the next play call
var _quit_on_back_was := true
var _kickoff_pending := ""           ## team that must kick off when the next quarter starts
var _comeback := false               ## the human trailed by 10+ at some point
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
	if config.is_empty():
		config = SceneRouter.take_config()
	var home_abbr: String = config.get("home", "KC")
	var away_abbr: String = config.get("away", "PHI")
	var quarter_min: float = config.get("quarter_minutes", Settings.quarter_minutes)
	pace = DefensePace.Pace.EVERY_SNAP
	var dbg := OS.get_cmdline_user_args()
	play_defense = dbg.has("--play-defense") or dbg.has("--human=away") or dbg.has("--drawtest")
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
	if OS.get_cmdline_user_args().has("--human=away"):   # debug: you play the away team (defend first)
		human = away_abbr
	# Android back opens the pause menu instead of quitting the app (restored on exit).
	_quit_on_back_was = get_tree().quit_on_go_back
	if human != "":
		get_tree().quit_on_go_back = false
	memory = DefenseMemory.new(def_ai)
	_build_scene(teams[home_abbr], teams[away_abbr])
	_resolve_lineups(home_abbr, away_abbr)
	gs = GameState.new(home_abbr, away_abbr, quarter_min * 60.0)
	if sim_games > 0:
		_run_sim_batch.call_deferred()
	else:
		_start_game()
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--show="):
				_debug_show.call_deferred(a.trim_prefix("--show="))
			if a == "--drawtest":
				_debug_drawtest.call_deferred()


# ---------------------------------------------------------------- scene

func _build_scene(home_team: TeamData, away_team: TeamData) -> void:
	field = FieldView.new()
	field.set_teams(home_team, away_team)
	add_child(field)
	runner = PlayRunner.new()
	runner.aim_sens = Settings.aim_mult()
	runner.record_replay = human != "" and Settings.replays and not _sim()
	if human != "" and not (SaveManager.disabled):   # your coach perks tune the match
		tuning = CoachPerks.apply_tuning(tuning, SaveManager.profile)
	conditions = config.get("conditions", {})
	for a in OS.get_cmdline_user_args():   # debug: --weather=rain|snow|fog|night|dome
		if a.begins_with("--weather="):
			var w := a.trim_prefix("--weather=")
			conditions = {"time": "night" if w == "night" else "day", "weather": "clear" if w == "night" else w}
	tuning = GameConditions.apply_tuning(tuning, conditions)
	runner.tuning = tuning
	if not _sim() and not conditions.is_empty():
		var wfx := WeatherFx.new()
		add_child(wfx)
		wfx.setup(conditions, self)
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
	hud.runner = runner
	add_child(hud)
	hud.play_selected.connect(_on_play_selected)
	hud.special_pressed.connect(_on_special)
	hud.pause_pressed.connect(request_pause)
	hud.switch_pressed.connect(func() -> void:
		if _human_defense() and phase in [Phase.PLAY_CALL, Phase.LIVE]:
			dcontrol.switch_to_ball())
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
	ocontrol.pass_kind_changed.connect(func(kind_name: String) -> void:
		Sfx.play("tap")
		hud.set_hint("PASS TYPE: %s  ·  TAP AGAIN TO SWITCH  ·  DRAG BACK TO AIM" % kind_name))
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
	runner.hero_event.connect(_on_hero_event)
	runner.big_hit.connect(func(_at: Vector2, speed: float) -> void:
		if _sim():
			return
		Sfx.play("hit")
		if Settings.shake:
			camera.add_trauma(clampf(speed / 14.0, 0.15, 0.6)))
	runner.ball_thrown.connect(func(_t: Vector2) -> void:
		if not _sim():
			Sfx.play("throw"))
	runner.carrier_changed.connect(func(a: PlayerAgent) -> void:
		if not _sim() and runner.pass_thrown:
			Sfx.play("catch" if a.team == PlayerAgent.Team.OFFENSE else "big"))


## Lineups: config overrides; else your franchise cards (if home is your franchise) vs the
## real opponent rescaled for difficulty; CPU vs CPU uses both teams' real rosters.
func _resolve_lineups(home_abbr: String, away_abbr: String) -> void:
	if config.has("home_lineup") and config.has("away_lineup"):
		lineups[home_abbr] = config["home_lineup"]
		lineups[away_abbr] = config["away_lineup"]
		return
	var prof: Profile = SaveManager.profile
	if human != "" and prof.has_team() and prof.franchise_team == home_abbr and not prof.lineup.is_empty():
		var base_ovr := Collection.team_ovr(prof, GameData.db)
		var chem := Collection.chemistry(prof, GameData.db)
		abilities.setup(Collection.lineup_entries(prof, GameData.db))
		# Franchise Chemistry: your starters play up to +3 OVR better.
		var entries := TeamRating.rescale_entries(Collection.lineup_entries(prof, GameData.db), base_ovr,
				int(round(base_ovr + chem)))
		var mine := TeamRating.match_lineup(entries)
		var your_ovr := int(round(base_ovr + chem))
		mine["ovr"] = your_ovr
		lineups[home_abbr] = mine
		lineups[away_abbr] = GameData.opponent_lineup(away_abbr, your_ovr, int(config.get("difficulty", Settings.difficulty)))
		return
	lineups[home_abbr] = GameData.real_lineup(home_abbr)
	lineups[away_abbr] = GameData.real_lineup(away_abbr)
	# A/B balance runs: --home-ovr=90 --away-ovr=60 rescale the real rosters.
	for arg in OS.get_cmdline_user_args():
		for side in [["--home-ovr=", home_abbr], ["--away-ovr=", away_abbr]]:
			if arg.begins_with(side[0]):
				lineups[side[1]] = _rescaled(side[1], int(arg.get_slice("=", 1)))


func _rescaled(abbr: String, ovr: int) -> Dictionary:
	var entries := GameData.db.team_entries(abbr)
	var out := TeamRating.match_lineup(TeamRating.rescale_entries(entries, TeamRating.team_ovr(entries), ovr))
	out["ovr"] = ovr
	return out


## Placeholder lineups: every slot gets position-profile ratings at one OVR (tests/fallback).
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


func _sims_cpu_drives() -> bool:
	return human != "" and not play_defense and not _is_challenge()


## Team strength for simulated drives: the OVR the team plays at in this game (yours with
## chemistry, the opponent's after the difficulty rescale).
func _team_strength(team: String) -> float:
	return float(lineups.get(team, {}).get("ovr", _sim_strength(team)))


## The CPU has the ball: simulate its whole drive (GameSim) from where it starts, run the
## clock, show the result, then hand the ball back (kickoff after a score, punt, turnover).
func _sim_cpu_drive() -> void:
	phase = Phase.RESULT
	hud.hide_choice()
	hud.show_play_bar(false)
	hud.set_special_actions([] as Array[String])
	hud.show_switch(false)
	hud.set_hint("")
	hud.set_abilities([])
	var cpu := gs.possession
	var start_x := gs.downs.los_x
	var rate := GameSim.drive_rate(_team_strength(cpu), _team_strength(human), cpu == gs.home, start_x)
	var d := GameSim.sim_drive(gs, cpu, rate, start_x, rng)
	var secs := minf(float(d["plays"]) * rng.randf_range(24.0, 34.0), gs.clock.seconds_left)
	gs.clock.seconds_left -= secs
	gs.clock.stopped = true
	var outcome: String = d["outcome"]
	var end_x := clampf(float(d["end_x"]), FieldGeo.OWN_GOAL + 1.0, FieldGeo.OPP_GOAL - 1.0)
	var name := (teams[cpu] as TeamData).team_name.to_upper()
	var head := {"td": "%s TOUCHDOWN" % name, "fg": "%s FIELD GOAL" % name, "miss": "%s MISS THE FG" % name,
			"punt": "DEFENSE HOLDS - %s PUNT" % name, "turnover": "INTERCEPTED!" if d["int"] else "FUMBLE RECOVERED!",
			"downs": "STOPPED ON DOWNS!"}.get(outcome, name)
	var sub := "%s DRIVE: %d PLAYS · %d YDS · %d:%02d" % [cpu, int(d["plays"]), int(d["yards"]), int(secs) / 60,
			int(secs) % 60]
	_update_scorebug()
	if not _sim():
		hud.show_banner(head, sub, 2.4)
		var bad := outcome in ["td", "fg"]
		Sfx.play("bad" if bad else "big")
		Sfx.play("groan" if bad else "cheer")
		if outcome in ["turnover", "downs"]:
			hud.flash(Color("#00e436"), 0.4)
	var after_score := func() -> void:
		if _ot_over():
			_final()
		elif gs.clock.expired():
			_kickoff_pending = cpu
			_end_period()
		else:
			_kickoff(cpu)
	var after_stop := func() -> void:
		if _ot_over():
			_final()
		elif gs.clock.expired():
			_end_period()
		else:
			_start_play_call()
	match outcome:
		"td", "fg":
			gs.finish_drive(true, gs.clock.seconds_left)
			_after(2.6, after_score)
		"punt":
			gs.downs.los_x = end_x
			_after(2.6, _punt)
		_:
			gs.finish_drive(true, gs.clock.seconds_left)
			gs.start_possession(human, FieldGeo.LENGTH - end_x)
			_spot_y = FieldGeo.CENTER_Y
			if not _sim():
				camera.show_spot(gs.downs.los_x)
			_after(2.6, after_stop)


func _human_defense() -> bool:
	return human != "" and gs.possession != human


## Runs `fn` after `delay` seconds (immediately queued in headless sim mode).
func _after(delay: float, fn: Callable) -> void:
	if _sim():
		_queued = fn
		return
	if _replay_next:   # a big play just ended: show it again before moving on
		_replay_next = false
		get_tree().create_timer(delay).timeout.connect(func() -> void: _run_replay(fn))
		return
	get_tree().create_timer(delay).timeout.connect(fn)


func _kicker(team: String) -> Dictionary:
	var k: Dictionary = lineups[team].get("K", RatingModel.fill_attrs("K", 75))
	return abilities.apply_kicker(k, _clutch()) if team == human else k


## Situation for "clutch" X-Factor abilities.
func _clutch() -> Dictionary:
	return {"quarter": gs.clock.quarter, "half_seconds_left": gs.clock.half_seconds_left()}


## X-Factor chips for the side the human is playing: active ones glow, the rest show progress.
func _update_abilities() -> void:
	if human == "" or not abilities.has_any() or _sim():
		return
	var off := gs.possession == human
	var rows: Array = []
	for a in abilities.progress(_clutch()):
		var slot: String = a["slot"]
		var is_off := slot in TeamRating.OFFENSE_SLOTS
		if slot != "K" and is_off != off:
			continue
		if slot == "K" and not a["on"]:
			continue
		var nm := str(a["name"])
		var t := "%s: %s" % [nm.substr(nm.find(". ") + 2) if nm.find(". ") >= 0 else nm, a["ability"]]
		if not a["on"] and int(a["need"]) > 1:
			t += " %d/%d" % [int(a["have"]), int(a["need"])]
		rows.append({"text": t, "on": a["on"]})
	hud.set_abilities(rows)


# ---------------------------------------------------------------- game flow

func _start_game() -> void:
	phase = Phase.PREGAME
	hud.show_pause_button(human != "")
	if not _sim():
		Music.play("game")
		Music.set_crowd(true)
	if config.has("challenge") and human != "":
		_start_challenge(config["challenge"])
		return
	# Coin toss: the human (or the home team) receives the opening kickoff.
	gs.opening_receiver = gs.home
	var h: TeamData = teams[gs.home]
	var a: TeamData = teams[gs.away]
	if not _sim():
		camera.show_spot(FieldGeo.OWN_GOAL + 50.0)
		camera.snap_to_target()
		hud.show_banner("%s  VS  %s" % [h.team_name.to_upper(), a.team_name.to_upper()], "KICKOFF" + ("  -  " + GameConditions.label(conditions) if GameConditions.label(conditions) != "" else ""), 1.8)
	_after(1.8, func() -> void: _kickoff(gs.away))


## `kicker` kicks off; the other team starts a possession.
func _kickoff(kicker: String) -> void:
	if phase == Phase.FINAL:
		return
	var receiver := gs.other(kicker)
	var x := KickModel.kickoff(tuning, rng, float(_kicker(kicker).get("kpw", 75)))
	gs.start_possession(receiver, x)
	gs.clock.stopped = true
	if not _sim():
		var ret := "TOUCHBACK" if is_equal_approx(x, FieldGeo.OWN_GOAL + tuning.touchback_yard) else "RETURNED TO THE %s" % FieldGeo.spot_text(x)
		camera.show_spot(x)
		hud.show_banner("KICKOFF", "%s  ·  %s BALL" % [ret, receiver], 1.4)
	_after(1.4, _start_play_call)


func _situation() -> Dictionary:
	return gs.situation()


func _start_play_call() -> void:
	_replay_next = false
	camera.follow_play()
	if phase == Phase.FINAL or _check_challenge():
		return
	if gs.clock.expired():
		_end_period()
		return
	if _sims_cpu_drives() and gs.possession != human and not _two_point:
		_sim_cpu_drive()
		return
	phase = Phase.PLAY_CALL
	hud.hide_choice()
	var off_team: TeamData = teams[gs.possession]
	var def_team: TeamData = teams[gs.defense()]
	field.set_possession(off_team, def_team)
	runner.off_colors = _jersey(off_team)
	runner.def_colors = _jersey(def_team)
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
		var ranked := PlayAdvisor.suggest(offense_book.plays, situation, rng, memory)
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
		hud.set_hint(DEFENSE_PRESNAP_HINT)
		_offer_specials()
	else:
		off_play = PlayAdvisor.pick(offense_book.plays, situation, rng)
		def_play = AIPlayCaller.pick_defense(defense_book.plays, null, situation, rng, last_def_call)
	if _two_point:
		_restrict_two_point_calls()
	last_def_call = def_play
	_setup_formation()
	hud.show_play_bar(human != "")
	hud.show_switch(_human_defense())
	_update_scorebug()
	if not _sim():
		camera.snap_to_target()
	if human == "":
		_after(0.8, func() -> void:
			if phase == Phase.PLAY_CALL:
				_snap())
	else:
		_coach_tips()
		if _pause_queued:
			_pause()


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
	if human != "" and abilities.has_any():
		abilities.on_drive(gs.drive_no)
		if gs.possession == human:
			off_l = abilities.apply(off_l, _clutch())
		else:
			def_l = abilities.apply(def_l, _clutch())
		_update_abilities()
	runner.setup_play(off_play, def_play, gs.downs.los_x, _ball_y(), off_l, def_l)
	field.los_x = gs.downs.los_x
	field.first_down_x = gs.downs.first_down_x
	field.down = gs.downs.down
	dcontrol.on_play_setup()


var _spot_y := FieldGeo.CENTER_Y


func _ball_y() -> float:
	return _spot_y


func _update_scorebug() -> void:
	if human != "" and gs.score_diff(human) <= -10:
		_comeback = true
	if not _sim():   # close late game: the tense loop
		Music.play("clutch" if (gs.clock.quarter >= 4 and absi(int(gs.score[gs.home]) - int(gs.score[gs.away])) <= 8) else "game")
	var q: String = "OT" if gs.clock.is_overtime() else ["1ST", "2ND", "3RD", "4TH"][clampi(gs.clock.quarter - 1, 0, 3)] + " QTR"
	hud.set_score_bar({"home": gs.home, "away": gs.away, "home_score": int(gs.score[gs.home]),
			"away_score": int(gs.score[gs.away]), "possession": gs.possession, "quarter": q,
			"clock": GameClock.format_time(gs.clock.seconds_left), "home_color": teams[gs.home].helmet, "away_color": teams[gs.away].helmet,
			"down": "2-PT TRY" if _two_point else gs.downs.down_text()})


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
	if _replay != null:
		_end_replay()   # tap to skip the replay
		return
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


var _tagged: PlayerAgent = null


func _process(delta: float) -> void:
	if phase == Phase.LIVE and _human_defense() and runner.human_team == PlayerAgent.Team.DEFENSE:
		var in_air := runner.ball.state == Ball.State.AIR
		hud.set_hint(_defense_live_hint(in_air))
	# Name + number of the player you control.
	var ctrl := runner.controlled if human != "" else null
	if ctrl != _tagged:
		_tagged = ctrl
		hud.set_player_tag("" if ctrl == null else "%s [%s]  #%d" % [ctrl.display_name.to_upper().replace(". ", "."),
				ctrl.pos_code, ctrl.jersey])
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
		hud.show_switch(false)
		_simulate_play()
		return
	if _human_defense():
		hud.set_hint(DEFENSE_LIVE_HINT)
	elif _human_offense():
		hud.set_hint("DRAG UP/DOWN TO STEER  ·  FLICK TO JUKE  ·  DOUBLE-TAP TO DIVE" if off_play.is_run()
				else "DRAG BACK TO AIM, RELEASE TO THROW  ·  TAP = PASS TYPE  ·  DRAG FORWARD TO RUN")
	else:
		hud.set_hint("")


## Defense-pace auto-sim: run the whole play now and just show the result.
func _simulate_play() -> void:
	var guard := int(PlayRunner.WATCHDOG_SECONDS / DT) + 200
	while phase == Phase.LIVE and guard > 0:
		guard -= 1
		_step_live(DT)


func _physics_process(dt: float) -> void:
	if _replay != null:
		camera.focus_override = _replay.focus
		if _replay.step(dt):
			_end_replay()
		return
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
	hud.show_switch(false)
	if int(runner.play_time) >= int(PlayRunner.WATCHDOG_SECONDS):
		r["watchdog"] = 1
	if _human_offense():
		var gained: int = r["yards"] if r["type"] not in ["incomplete", "int", "int_td", "fumble"] else 0
		memory.record(off_play.id, off_play.formation.id, off_play.category,
				-10 if r["turnover"] else gained, off_play.display_name)
	if human != "" and abilities.has_any():
		var ev := r.duplicate()
		ev["side"] = "offense" if gs.possession == human else "defense"
		ev["run_play"] = off_play.is_run()
		ev["down"] = gs.downs.down
		for a in abilities.record(ev):
			if not _sim():
				hud.show_ability(str(a["name"]), str(a["ability"]), str(a["text"]))
				Sfx.play("sparkle")
		_update_abilities()
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
		_play_juice(type, offense)
	_update_scorebug()
	_replay_next = runner.record_replay and not _sim() and _replay_worthy(type, r)
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


## Sound + flash for the result of a play.
func _play_juice(type: String, offense: String) -> void:
	var ours := human != "" and offense == human
	match type:
		"td":
			Sfx.play("td" if ours or human == "" else "bad")
			Sfx.play("cheer" if ours or human == "" else "groan")
			hud.flash(UiTheme.ACCENT if ours else Color("#ff004d"), 0.55)
			if Settings.shake:
				camera.add_trauma(0.35)
		"int", "int_td", "fumble":
			Sfx.play("bad" if ours else "big")
			Sfx.play("groan" if ours else "cheer")
			hud.flash(Color("#ff004d") if ours else Color("#00e436"), 0.45)
		"sack":
			Sfx.play("hit")
			Sfx.play("oh")
		_:
			Sfx.play("whistle")


## First-game coach tips (Settings.tutorial_done once offense and defense were explained).
var _tips_seen: Dictionary = {}


func _coach_tips() -> void:
	if Settings.tutorial_done or _sim():
		return
	var key := ""
	var text := ""
	if _human_offense() and gs.downs.down == 4 and not _tips_seen.has("fourth"):
		key = "fourth"
		text = "4TH DOWN: PUNT OR KICK A FIELD GOAL WITH THE BUTTONS TOP RIGHT, OR PICK A PLAY TO GO FOR IT."
	elif _human_offense() and not _tips_seen.has("offense"):
		key = "offense"
		text = "YOUR BALL. THE BEST CALL IS PRESELECTED (OR TAP ANOTHER / MORE). PRESS THE QB AND DRAG BACK TO AIM, RELEASE TO THROW. DRAG FORWARD TO RUN."
	elif _human_defense() and not _tips_seen.has("defense"):
		key = "defense"
		text = "DEFENSE! THE CALL PICKS YOUR HERO (YELLOW TAG). DRAG FROM HIM TO DRAW HIS PATH, THEN TAP THE FIELD TO SNAP. DRAG TO MOVE: PUSH AT BLOCKERS AND SWIPE (OR TAP WITH A SECOND FINGER) WHEN THE BAR FLASHES TO BEAT THEM, TAP FOR A BURST, TAP THE CARRIER TO DIVE, TAP THE BALL TO LEAP. SWITCH TAKES THE MAN NEAREST THE BALL."
	if key == "":
		return
	_tips_seen[key] = true
	hud.show_tip(text)
	if _tips_seen.has("offense") and _tips_seen.has("defense"):
		Settings.tutorial_done = true
		Settings.save_settings()


# ---------------------------------------------------------------- kicks & tries

func _punt() -> void:
	phase = Phase.RESULT
	if not _sim():
		Sfx.play("kick")
	var kicker := gs.possession
	gs.stats[kicker]["punts"] += 1
	var x := KickModel.punt(tuning, rng, float(_kicker(kicker).get("kpw", 75)), gs.downs.los_x)
	gs.clock.tick_live(6.0 / gs.clock.speed)
	gs.finish_drive(true, gs.clock.seconds_left)
	gs.start_possession(gs.other(kicker), x)
	_spot_y = FieldGeo.CENTER_Y
	if not _sim():
		camera.show_spot(x)
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
	if not _sim():
		Sfx.play("kick")
	var kicker := gs.possession
	gs.record_field_goal(kicker, good, dist)
	gs.clock.tick_live(5.0 / gs.clock.speed)
	gs.finish_drive(true, gs.clock.seconds_left)
	if not _sim():
		hud.show_banner("%d-YARD FIELD GOAL" % int(dist), text, 1.6)
	if good:
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
	if phase == Phase.FINAL:
		return
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
		Phase.BREAK:
			if _half_offer:
				_half_offer = false
				if index == 1:
					_sim_rest_of_game()
				else:
					hud.hide_choice()
					_kickoff(gs.opening_receiver)
		Phase.PAUSED:
			_on_pause_choice(index)
		Phase.FINAL:
			if config.get("from_hub", false):
				SceneRouter.goto(SceneRouter.RESULTS, {"last_result": match_result()})
			else:
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
		camera.show_spot(x)
		hud.show_banner("FREE KICK", "%s BALL" % gs.possession, 1.3)
	_after(1.3, _start_play_call)


# ---------------------------------------------------------------- periods & end

func _ot_over() -> bool:
	return gs.clock.is_overtime() and gs.overtime_decided()


func _end_period() -> void:
	if phase == Phase.BREAK or phase == Phase.FINAL:
		return
	if _check_challenge(true):
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
			# The team that received the opening kick kicks off the second half (a huge lead
			# first offers to sim the rest of the game).
			if human != "" and not _sim() and not _is_challenge() and gs.score_diff(human) >= SIM_OFFER_LEAD:
				_after(2.2, _offer_sim)
			else:
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
	if phase == Phase.FINAL:
		return
	if not _chal.is_empty() and _check_challenge(false, true):
		return
	phase = Phase.FINAL
	hud.show_play_bar(false)
	hud.set_special_actions([] as Array[String])
	hud.set_hint("")
	if _sim():
		_record_sim_game()
		return
	var w := gs.winner()
	Music.set_crowd(false)
	if human != "" and not _sim():
		Music.jingle("win" if w == human else "lose")
	var title := "FINAL" if w == "" else ("YOU WIN!" if w == human else ("%s WIN" % teams[w].team_name.to_upper()))
	if human == "":
		title = "FINAL"
	hud.show_choice(title, _final_summary(),
			["CONTINUE" if config.get("from_hub", false) else "PLAY AGAIN"] as Array[String])


## Summary handed back to the hub (rewards, season results).
func match_result(forfeit := false) -> Dictionary:
	var mine := human if human != "" else gs.home
	var opp := gs.other(mine)
	var s: Dictionary = gs.stats[mine]
	return {"team": mine, "opponent": opp, "pf": int(gs.score[mine]), "pa": int(gs.score[opp]),
			"forfeit": forfeit, "tds": int(s["pass_td"]) + int(s["rush_td"]),
			"def_ints": int(gs.stats[opp]["int"]), "def_sacks": int(gs.stats[opp]["sacks"]),
			"difficulty": int(config.get("difficulty", Settings.difficulty)),
			"mode": str(config.get("mode", "quick")), "extra": config.get("extra", {}),
			"came_back": _comeback, "challenge_won": _chal_won, "box": gs.box_score(mine)}


# ---------------------------------------------------------------- challenges

var _chal: Dictionary = {}
var _chal_base: Dictionary = {}
var _chal_won := false


## Sets up a challenge's start state (no kickoff) and starts play.
func _start_challenge(c: Dictionary) -> void:
	_chal = c
	var st: Dictionary = c["start"]
	var opp := gs.other(human)
	gs.clock.quarter = int(st["quarter"])
	gs.clock.seconds_left = float(st["clock"])
	gs.clock.stopped = true
	gs.score[human] = int(st["you"])
	gs.score[opp] = int(st["opp"])
	gs.opening_receiver = gs.home
	var team := human if st["ball"] == "you" else opp
	gs.start_possession(team, FieldGeo.OWN_GOAL + float(st["yard"]))
	gs.downs.down = int(st["down"])
	gs.downs.first_down_x = minf(gs.downs.los_x + float(st["to_go"]), FieldGeo.OPP_GOAL)
	_chal_base = {"you": gs.score[human], "opp": gs.score[opp], "ints": int(gs.stats[opp]["int"]),
			"you_tds": _tds(human), "ball": team}
	if not _sim():
		hud.show_banner(c["title"], c["desc"], 2.6)
	_after(2.6, _start_play_call)


func _tds(team: String) -> int:
	return int(gs.stats[team]["pass_td"]) + int(gs.stats[team]["rush_td"])


## Checks the challenge goal; ends the match if decided. Returns true when it ended.
func _check_challenge(period_over := false, game_over := false) -> bool:
	if _chal.is_empty() or phase == Phase.FINAL:
		return false
	var opp := gs.other(human)
	var ev := {
		"you_tds": _tds(human) - int(_chal_base["you_tds"]),
		"you_pts": int(gs.score[human]) - int(_chal_base["you"]),
		"opp_pts": int(gs.score[opp]) - int(_chal_base["opp"]),
		"ints": int(gs.stats[opp]["int"]) - int(_chal_base["ints"]),
		"possession_lost": _chal_base["ball"] == human and gs.possession != human,
		"their_drive_over": _chal_base["ball"] == opp and gs.possession != opp,
		"period_over": period_over,
		"game_over": game_over or (period_over and gs.clock.quarter >= 4 and gs.score[human] != gs.score[opp]),
		"you_lead": gs.score[human] > gs.score[opp],
	}
	var res := ChallengeRules.evaluate(_chal["goal"], ev)
	if res == 0:
		return false
	_chal_won = res > 0
	phase = Phase.FINAL
	hud.show_play_bar(false)
	hud.set_special_actions([] as Array[String])
	hud.set_hint("")
	if _chal_won:
		Sfx.play("big")
		hud.flash(UiTheme.ACCENT, 0.5)
	else:
		Sfx.play("bad")
	hud.show_choice("CHALLENGE COMPLETE!" if _chal_won else "CHALLENGE FAILED", _chal["title"],
			["CONTINUE"] as Array[String])
	return true


func _final_summary() -> String:
	var lines: Array[String] = []
	lines.append("%s %d  -  %d %s" % [gs.home, gs.score[gs.home], gs.score[gs.away], gs.away])
	for t in [gs.home, gs.away]:
		var s: Dictionary = gs.stats[t]
		lines.append("%s  PASS %d/%d %d  RUSH %d-%d  INT %d" % [t, s["pass_comp"], s["pass_att"], s["pass_yds"],
				s["rush_att"], s["rush_yds"], s["int"]])
	return "\n".join(lines)


# ---------------------------------------------------------------- pause menu

func _can_pause() -> bool:
	return human != "" and phase in [Phase.PLAY_CALL, Phase.LIVE] and not hud.is_choice_open()


## II button, Esc or the Android back button. Outside a play call / live play (banners,
## kicks, PAT choice) the request waits for the next play call so nothing half-finished
## is frozen; while paused, back/Esc resumes (or backs out of the leave confirm).
func request_pause() -> void:
	if human == "" or phase == Phase.FINAL:
		return
	if phase == Phase.PAUSED:
		if _pause_menu == PauseMenu.CONFIRM_QUIT:
			_show_pause_menu()
		else:
			hud.hide_choice()
			_resume()
		return
	if _can_pause():
		_pause()
	else:
		_pause_queued = true


func _pause() -> void:
	if not _can_pause():
		return
	_pause_queued = false
	_paused_from = phase
	phase = Phase.PAUSED
	runner.set_physics_process(false)
	hud.show_switch(false)
	_show_pause_menu()


func _show_pause_menu() -> void:
	_pause_menu = PauseMenu.MAIN
	hud.show_choice("PAUSED", "%s  ·  %s %d  %s %d" % [gs.clock.label(), gs.home, gs.score[gs.home], gs.away, gs.score[gs.away]],
			pause_options())


## Pause menu entries (index = choice): RESUME, pace, quarter length, [RESTART GAME,] QUIT TO MENU.
func pause_options() -> Array[String]:
	var opts: Array[String] = ["RESUME", "QUARTER: %.1f MIN (NEXT GAME)" % Settings.quarter_minutes]
	if play_defense:
		opts.insert(1, "DEFENSE PACE: %s" % DefensePace.NAMES[pace])
	if not config.get("from_hub", false):
		opts.append("RESTART GAME")
	if not _is_challenge():
		opts.append("SIM REST OF GAME")
	opts.append("QUIT TO MENU")
	return opts


func _is_challenge() -> bool:
	return not _chal.is_empty() or str(config.get("mode", "")) == "challenge"


func _on_pause_choice(index: int) -> void:
	if _pause_menu == PauseMenu.CONFIRM_QUIT:
		if index == 1:
			_quit_to_menu()
		else:
			_show_pause_menu()
		return
	if _pause_menu == PauseMenu.CONFIRM_SIM:
		if index == 1:
			_sim_rest_of_game()
		else:
			_show_pause_menu()
		return
	var opts := pause_options()
	var opt: String = opts[index] if index >= 0 and index < opts.size() else "RESUME"
	match opt.get_slice(":", 0):
		"DEFENSE PACE":
			pace = (pace + 1) % DefensePace.NAMES.size()
			Settings.defense_pace = pace
			Settings.save_settings()
			_show_pause_menu()
		"QUARTER":
			var lengths := [1.5, 2.5, 3.5, 5.0]
			var i := lengths.find(Settings.quarter_minutes)
			Settings.quarter_minutes = lengths[(i + 1) % lengths.size()]
			Settings.save_settings()
			_show_pause_menu()
		"SIM REST OF GAME":
			_pause_menu = PauseMenu.CONFIRM_SIM
			hud.show_choice("SIM THE REST?", "%s %d  %s %d  ·  FINISHES THE GAME NOW" % [gs.home, gs.score[gs.home], gs.away, gs.score[gs.away]],
					["KEEP PLAYING", "SIM IT"] as Array[String])
		"RESTART GAME":
			Engine.time_scale = 1.0
			get_tree().reload_current_scene()
		"QUIT TO MENU":
			_pause_menu = PauseMenu.CONFIRM_QUIT
			if _is_challenge():
				hud.show_choice("LEAVE THE CHALLENGE?", "YOU CAN TRY IT AGAIN ANYTIME", ["STAY", "LEAVE"] as Array[String])
			elif config.get("from_hub", false):
				hud.show_choice("LEAVE THE GAME?", "IT COUNTS AS A LOSS", ["STAY", "LEAVE"] as Array[String])
			else:
				hud.show_choice("LEAVE THE GAME?", "BACK TO THE TITLE SCREEN", ["STAY", "LEAVE"] as Array[String])
		_:
			_resume()


func _resume() -> void:
	phase = _paused_from
	_pause_menu = PauseMenu.MAIN
	runner.set_physics_process(true)
	hud.show_switch(_human_defense() and phase in [Phase.PLAY_CALL, Phase.LIVE]
			and runner.human_team == PlayerAgent.Team.DEFENSE)


## Leaves the match: a normal hub game goes through the results screen as a forfeit (a
## loss); a challenge just goes back to the challenge list; a debug launch to the title.
func _quit_to_menu() -> void:
	phase = Phase.FINAL
	runner.set_physics_process(false)
	hud.hide_choice()
	hud.show_play_bar(false)
	hud.show_switch(false)
	hud.set_special_actions([] as Array[String])
	hud.set_hint("")
	Engine.time_scale = 1.0
	if _is_challenge() and config.get("from_hub", false):
		SceneRouter.goto(SceneRouter.CHALLENGES)
	elif config.get("from_hub", false):
		SceneRouter.goto(SceneRouter.RESULTS, {"last_result": match_result(true)})
	else:
		SceneRouter.goto(SceneRouter.TITLE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		request_pause()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_ESCAPE:
		request_pause()
		get_viewport().set_input_as_handled()
	elif k.keycode in [KEY_TAB, KEY_SPACE] and _human_defense() and phase in [Phase.PLAY_CALL, Phase.LIVE]:
		dcontrol.switch_to_ball()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	get_tree().quit_on_go_back = _quit_on_back_was
	Music.set_crowd(false)


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
	print("AIVSAI %d games | %.1f pts/team (max %d, %d shutouts) | comp %.0f%% (%d/%d) | %.1f pass yds/team | %.2f INT/team | %.1f sacks/team | rush %.1f ypc, %.1f att/team | %.1f plays/team | FG %d/%d | %.1f punts/team | OT %d, ties %d | home wins %.0f%% | stuck plays %d" % [
		t["games"], t["points"] / teams_n, t["max_pts"], t["shutouts"],
		100.0 * t["pass_comp"] / maxf(t["pass_att"], 1), t["pass_comp"], t["pass_att"],
		t["pass_yds"] / teams_n, t["int"] / teams_n, t["sacks"] / teams_n,
		float(t["rush_yds"]) / maxf(t["rush_att"], 1), t["rush_att"] / teams_n, t["plays"] / teams_n,
		t["fg_made"], t["fg_att"], t["punts"] / teams_n, t["ot"], t["ties"],
		100.0 * t["home_wins"] / maxf(t["games"], 1), t["watchdog"]])


## Home team in its colors, visitors in road whites, so the two sides never blend together.
func _jersey(team: TeamData) -> Dictionary:
	return team.uniform_colors() if team.abbr == gs.home else team.away_colors()


## Debug: `-- --show=pause|pat|final|kick|tip|xf` opens that HUD piece after ~6 s (screenshots).
func _debug_show(kind: String) -> void:
	await get_tree().create_timer(6.0).timeout
	match kind:
		"pause":
			_show_pause_menu()
		"pat":
			hud.show_choice("EXTRA POINT", "KC 6  PHI 0", ["KICK PAT (1)", "GO FOR 2"] as Array[String])
		"final":
			hud.show_choice("YOU WIN!", "KC 31  PHI 17", ["PLAY AGAIN"] as Array[String])
		"snap":
			_snap()
		"cpudrive":
			if hud.tip_open():
				hud._tip.visible = false
			gs.start_possession(gs.other(human), FieldGeo.OWN_GOAL + 25.0)
			_sim_cpu_drive()
		"xf":
			# Switch on the first X-Factor ability of the side on the field.
			if hud.tip_open():
				hud._tip.visible = false
				hud.tip_closed.emit()
			for a in abilities.progress(_clutch()):
				if (str(a["slot"]) in TeamRating.OFFENSE_SLOTS) == (gs.possession == human):
					abilities.active[a["slot"]] = true
					var d := AbilityRules.get_def(abilities.cards[a["slot"]]["id"])
					hud.show_ability(str(a["name"]), str(d["name"]), str(d["text"]))
					break
			_update_abilities()
		"simrest":
			_sim_rest_of_game()
		"half":
			gs.score[gs.home] = 35
			phase = Phase.BREAK
			_offer_sim()
		"kick":
			hud.kick_meter.start("FIELD GOAL  38 YD", 0.3, 0.12, 1.0)
		"tip":
			hud.show_tip("YOUR BALL. THE BEST CALL IS PRESELECTED (OR TAP ANOTHER / MORE). PRESS THE QB AND DRAG BACK TO AIM, RELEASE TO THROW. DRAG FORWARD TO RUN.")


# ---------------------------------------------------------------- sim the rest

var _half_offer := false


## Team strength for the quick sim: your lineup (with its cards) or the real team's rating.
func _sim_strength(abbr: String) -> int:
	var prof := SaveManager.profile
	if abbr == human and prof != null and prof.has_team() and prof.franchise_team == abbr:
		return Collection.team_ovr(prof, GameData.db)
	return GameData.db.team_ovr(abbr)


## Finishes the game from the current score: the remaining share of a normal game's scoring
## is drawn with the same model as SIM GAME, never ending tied; then the final screen.
func _sim_rest_of_game() -> void:
	GameSim.finish(gs, {gs.home: _sim_strength(gs.home), gs.away: _sim_strength(gs.away)}, rng)
	_half_offer = false
	_pause_menu = PauseMenu.MAIN
	Engine.time_scale = 1.0
	runner.set_physics_process(false)
	hud.hide_choice()
	hud.show_switch(false)
	gs.clock.seconds_left = 0.0
	gs.clock.stopped = true
	_update_scorebug()
	phase = Phase.BREAK
	_final()


## Halftime with a big lead: offer to skip the second half.
func _offer_sim() -> void:
	if phase != Phase.BREAK:
		return
	_half_offer = true
	hud.show_choice("YOU LEAD BY %d" % gs.score_diff(human), "%s %d  %s %d  ·  SIM THE SECOND HALF?" % [gs.home, gs.score[gs.home], gs.away, gs.score[gs.away]],
			["PLAY 2ND HALF", "SIM REST OF GAME"] as Array[String])


# ---------------------------------------------------------------- hero (defense) feedback

## The hint line for your defender: what to do right now.
func _defense_live_hint(in_air: bool) -> String:
	var me := runner.controlled
	if in_air:
		return DEFENSE_AIR_HINT
	if me != null and me.engaged_with != null and runner.contact.is_hero_rusher(me):
		return "SWIPE NOW TO BEAT THE BLOCK!" if me.duel_window > 0.0 else "PUSH AT THE PLAY  ·  THE BAR FILLS  ·  SWIPE OR TAP WHEN IT FLASHES"
	if me != null and runner.carrier == runner.qb and runner.hero_role(me) == "rush":
		return "DRAG TO RUSH THE QB  ·  SWIPE TO BEAT THE BLOCK  ·  TAP = BURST"
	return DEFENSE_LIVE_HINT


func _on_hero_event(kind: String, _at: Vector2) -> void:
	if _sim():
		return
	match kind:
		"beat":
			Sfx.play("slam")
			hud.flash(Color(1, 0.93, 0.15), 0.25)
			if Settings.shake:
				camera.add_trauma(0.3)
		"fail":
			Sfx.play("tap")
		"burst":
			Sfx.play("whoosh")


## Debug (`--drawtest`): synthetic touches through the real input path draw a path for the hero
## on the first defensive snap, then screenshots can show it (pairs with --human=away --snap).
func _debug_drawtest() -> void:
	while not (phase == Phase.PLAY_CALL and _human_defense()):
		await get_tree().create_timer(0.2).timeout
	await get_tree().create_timer(1.0).timeout
	var hero := runner.controlled
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--drawslot=") and runner.def_slots.has(a.trim_prefix("--drawslot=")):
			hero = runner.def_slots[a.trim_prefix("--drawslot=")]
	if hero == null:
		print("DRAWTEST no hero")
		return
	var xf := get_viewport().get_canvas_transform()
	var win := Vector2(DisplayServer.window_get_size()) / get_viewport().get_visible_rect().size   # events arrive in window pixels
	var start := xf * FieldProjection.to_screen(hero.field_pos + Vector2(0, -1.0)) * win
	var pts: Array[Vector2] = []
	for i in 8:
		pts.append(xf * FieldProjection.to_screen(hero.field_pos + Vector2(-0.6 * i, -1.5 * i)) * win)
	print("DRAWTEST hero ", hero.slot, " at ", start, " ui_blocked=", hud.is_point_over_ui(start))
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = start
	t.pressed = true
	Input.parse_input_event(t)
	await get_tree().process_frame
	for p in pts:
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = p
		Input.parse_input_event(d)
		await get_tree().process_frame
	var r := InputEventScreenTouch.new()
	r.index = 0
	r.position = pts[pts.size() - 1]
	r.pressed = false
	Input.parse_input_event(r)
	await get_tree().process_frame
	print("DRAWTEST hero_path points=", runner.hero_path.size(), " preview=", runner.hero_path_preview.size(), " controlled=", runner.controlled.slot)


# ---------------------------------------------------------------- instant replay

var _replay: ReplayPlayer = null
var _replay_next := false
var _replay_cont := Callable()


## Touchdowns, turnovers and long gains get an instant replay (slow-mo, tap to skip).
func _replay_worthy(type: String, r: Dictionary) -> bool:
	if OS.get_cmdline_user_args().has("--replay-any"):   # debug
		return true
	return type in ["td", "int", "int_td", "fumble"] or (type not in ["incomplete", "sack"] and int(r["yards"]) >= 25)


func _run_replay(cont: Callable) -> void:
	var n := runner.replay_frames.size()
	if n < 40 or phase == Phase.FINAL:
		cont.call()
		return
	_replay_cont = cont
	_replay = ReplayPlayer.new(runner, maxi(0, n - 540), 0.6)   # the last ~9 s, at 0.6x
	hud.show_replay(true)
	camera.snap_to_target()


func _end_replay() -> void:
	if _replay == null:
		return
	_replay = null
	camera.focus_override = Vector2.INF
	hud.show_replay(false)
	var c := _replay_cont
	_replay_cont = Callable()
	c.call()
