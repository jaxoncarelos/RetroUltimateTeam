extends Node2D
## Test bed: one drive from the 25. Default: you play offense against the CPU defense.
## With --defend: the CPU offense drives and you play defense.
## R restarts the drive (keyboard); F1 / three-finger tap toggles the AI debug overlay.
## Debug user args (after "--"):
##   --defend     play defense against the CPU offense (Phase 2)
##   --pace=P     defense pace: every | key | highlights (auto-sims the other snaps)
##   --autoplay   CPU plays both sides (watch a drive without touching)
##   --sim=N      headless batch: autoplay N plays (stepped as fast as possible), print stats, quit
##   --spam=ID    autoplay always calls this play (tests the defense keying on repeats)
##   --by-play    also print per-play averages at the end of a sim
##   --nokey      disable the CPU defense's memory (baseline for --spam comparisons)
##   --smart      autoplay calls plays with PlayAdvisor (situational) instead of at random
##   --look=X,Y   pin the camera on a field point (screenshots)   --grid  open the playbook grid
##   --aim-demo   (with --autoplay) the CPU QB shows the human aim preview for ~0.6 s before
##                it throws (screenshots of the arc / reticle / ghost markers)
##   --autosnap   (with --defend) snap automatically so the human-defense view can be recorded
##   --bot[=S]    (with --defend) a "human-like" DefenderBot plays your defender (skill S 0..1,
##                default 0.5); with --sim it measures how a human defense fares
##   --off-ovr=N --def-ovr=N   team strengths (default 80 vs 78)

enum State { PLAY_CALL, LIVE, RESULT, DRIVE_OVER }

const START_X := 35.0
const OFF_TEAM := "KC"
const DEF_TEAM := "PHI"
const OFF_OVR := 80
const DEF_OVR := 78

@export var tuning: GameplayTuning = preload("res://data/tuning/gameplay_tuning.tres")
@export var offense_book: PlaybookDef = preload("res://data/plays/offense_playbook.tres")
@export var defense_book: PlaybookDef = preload("res://data/plays/defense_playbook.tres")
@export var def_ai: DefenseAITuning = preload("res://data/tuning/defense_ai_tuning.tres")

var state := State.PLAY_CALL
var downs := DownTracker.new()
var selected_play: PlayDef
var def_play: PlayDef
var ball_y := FieldGeo.CENTER_Y
var drive_start_x := START_X
var memory: DefenseMemory
var passer: CpuPasser
var off_lineup: Dictionary = {}
var def_lineup: Dictionary = {}

var field: FieldView
var routes: PlayOverlay
var runner: PlayRunner
var aim: PlayOverlay
var camera: CameraRig
var hud: MatchHUD
var touch: TouchInput
var control: HumanOffenseControl
var dcontrol: HumanDefenseControl
var overlay: DebugOverlay

var human_side: int = PlayerAgent.Team.OFFENSE
var pace: int = DefensePace.Pace.EVERY_SNAP
var autoplay := false
var sim_target := 0
var spam_id := ""
var use_memory := true
var smart_calls := false
var autosnap := false
var aim_demo := false
var bot: DefenderBot
var bot_skill := -1.0
var off_ovr := OFF_OVR
var def_ovr := DEF_OVR
var _aim_demo_t := -1.0
var stats := {"plays": 0, "yards": 0, "att": 0, "comp": 0, "int": 0, "sack": 0, "td": 0,
		"runs": 0, "run_yds": 0, "pass_yds": 0, "broken": 0, "keyed": 0, "drives": 0, "fumble": 0}
var by_play: Dictionary = {}   ## play id -> [calls, yards, tds]


func _ready() -> void:
	pace = Settings.defense_pace
	for arg in OS.get_cmdline_user_args():
		if arg == "--autoplay":
			autoplay = true
		elif arg == "--defend":
			human_side = PlayerAgent.Team.DEFENSE
		elif arg.begins_with("--pace="):
			pace = DefensePace.from_name(arg.get_slice("=", 1))
		elif arg.begins_with("--sim="):
			autoplay = true
			sim_target = int(arg.get_slice("=", 1))
		elif arg.begins_with("--spam="):
			spam_id = arg.get_slice("=", 1)
		elif arg == "--nokey":
			use_memory = false
		elif arg == "--smart":
			smart_calls = true
		elif arg == "--autosnap":
			autosnap = true
		elif arg == "--aim-demo":
			aim_demo = true
		elif arg == "--bot":
			bot_skill = 0.5
		elif arg.begins_with("--bot="):
			bot_skill = float(arg.get_slice("=", 1))
		elif arg.begins_with("--off-ovr="):
			off_ovr = int(arg.get_slice("=", 1))
		elif arg.begins_with("--def-ovr="):
			def_ovr = int(arg.get_slice("=", 1))
		elif arg.begins_with("--look="):
			var xy := arg.get_slice("=", 1).split(",")
			(func() -> void: camera.pinned = Vector2(float(xy[0]), float(xy[1]))).call_deferred()
		elif arg == "--grid":
			(func() -> void: hud.show_playbook_grid(true)).call_deferred()
	memory = DefenseMemory.new(def_ai)
	var teams := TeamData.load_all()
	var off_team: TeamData = teams[OFF_TEAM]
	var def_team: TeamData = teams[DEF_TEAM]

	field = FieldView.new()
	field.set_teams(off_team, def_team)
	add_child(field)

	runner = PlayRunner.new()
	runner.aim_sens = Settings.aim_mult()
	runner.tuning = tuning
	runner.def_ai = def_ai
	var bot_on := bot_skill >= 0.0 and human_side == PlayerAgent.Team.DEFENSE
	runner.human_team = human_side if bot_on or not autoplay else -1
	runner.rng.randomize()
	runner.off_colors = off_team.uniform_colors()
	runner.def_colors = def_team.uniform_colors()

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
	hud.restart_pressed.connect(_restart_drive)

	touch = TouchInput.new()
	touch.ui_blocker = hud.is_point_over_ui
	add_child(touch)
	touch.tapped.connect(_on_tap)
	touch.three_finger_tap.connect(overlay.toggle)

	if human_side == PlayerAgent.Team.OFFENSE:
		control = HumanOffenseControl.new()
		add_child(control)
		control.bind(runner, touch, tuning)
		control.snap_requested.connect(func() -> void:
			if state == State.PLAY_CALL:
				_snap())
		control.aim_changed.connect(func(on: bool, target: Vector2) -> void:
			aim.aim_active = on
			aim.aim_target = target)
	else:
		dcontrol = HumanDefenseControl.new()
		add_child(dcontrol)
		dcontrol.bind(runner, touch, tuning)
		runner.human_input = dcontrol
		dcontrol.ready_tapped.connect(func() -> void:
			if state == State.PLAY_CALL:
				_snap())
		hud.switch_pressed.connect(dcontrol.switch_to_ball)
		if bot_on:
			bot = DefenderBot.new(dcontrol, runner, bot_skill)

	runner.play_ended.connect(_on_play_ended)
	off_lineup = _generic_lineup(offense_book.plays[0].formation, off_ovr)
	def_lineup = _generic_lineup(defense_book.plays[0].formation, def_ovr)
	selected_play = offense_book.plays[0]
	def_play = defense_book.plays[0]
	_restart_drive()
	if sim_target > 0:
		_run_sim.call_deferred()


func _human_defense() -> bool:
	return human_side == PlayerAgent.Team.DEFENSE


## Headless batch: steps plays synchronously at a fixed timestep (no timers, no rendering).
func _run_sim() -> void:
	const DT := 1.0 / 60.0
	runner.set_physics_process(false)
	set_physics_process(false)
	var guard := sim_target * 60 * 30   # bail out instead of hanging if plays never end
	while stats["plays"] < sim_target and guard > 0:
		guard -= 1
		match state:
			State.PLAY_CALL:
				_snap()
			State.LIVE:
				_cpu_offense_step(DT)
				if bot != null:
					bot.step(DT)
				runner._physics_process(DT)
			State.RESULT:
				_start_play_call()
			State.DRIVE_OVER:
				_restart_drive()
	_print_stats()
	get_tree().quit()


## Phase 1 placeholder lineup: every slot gets position-profile ratings at one OVR.
func _generic_lineup(form: FormationDef, ovr: int) -> Dictionary:
	var out := {}
	var n := 10
	for slot in form.slots:
		var pos: String = form.slots[slot]["pos"]
		out[slot] = {"name": slot, "jersey": n, "attrs": RatingModel.fill_attrs(pos, ovr)}
		n += 7
	return out


func _restart_drive() -> void:
	drive_start_x = START_X
	downs.start_drive(START_X)
	ball_y = FieldGeo.CENTER_Y
	hud.show_restart(false)
	_start_play_call()
	camera.snap_to_target()


func _situation() -> Dictionary:
	return {"down": downs.down, "to_go": downs.to_go(), "los_x": downs.los_x}


func _start_play_call() -> void:
	state = State.PLAY_CALL
	var situation := _situation()
	if _human_defense():
		# CPU offense calls situationally; you pick the defense (BEST = situational pick).
		selected_play = PlayAdvisor.pick(offense_book.plays, situation, runner.rng)
		var ranked := _ranked_defense(situation)
		def_play = ranked[0]
		_setup_formation()
		hud.show_play_bar(not autoplay)
		hud.set_play_options(ranked, defense_book.plays)
		hud.set_selected(def_play)
		hud.set_keyed(defense_book.plays, "")
		hud.set_hint("TAP A DEFENDER TO PICK HIM  ·  TAP THE FIELD WHEN READY")
		hud.show_switch(not autoplay or bot != null)
		_update_scorebug()
		if (autoplay or autosnap or bot != null) and sim_target == 0:
			get_tree().create_timer(0.5 if autoplay else 1.2).timeout.connect(func() -> void:
				if state == State.PLAY_CALL:
					_snap())
		return
	def_play = AIPlayCaller.pick_defense(defense_book.plays, memory if use_memory else null,
			situation, runner.rng, def_play)
	var ranked_o := PlayAdvisor.rank(offense_book.plays, situation, memory if use_memory else null)
	selected_play = ranked_o[0]
	_setup_formation()
	hud.show_play_bar(true)
	hud.set_play_options(ranked_o, offense_book.plays)
	hud.set_selected(selected_play)
	hud.set_keyed(offense_book.plays, memory.keyed_play() if use_memory else "")
	_update_snap_hint()
	_update_scorebug()
	if autoplay:
		if smart_calls:
			selected_play = PlayAdvisor.pick(offense_book.plays, situation, runner.rng,
					memory if use_memory else null)
		else:
			selected_play = offense_book.plays[runner.rng.randi() % offense_book.plays.size()]
		if spam_id != "":
			for p in offense_book.plays:
				if p.id == spam_id:
					selected_play = p
		hud.set_selected(selected_play)
		_setup_formation()
		if sim_target > 0:
			return
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if state == State.PLAY_CALL:
				_snap())


## Defensive calls ranked by how well they fit the situation (no tendency data for the human).
func _ranked_defense(situation: Dictionary) -> Array[PlayDef]:
	var w := AIPlayCaller.defense_weights(defense_book.plays, null, situation)
	var idx: Array = range(defense_book.plays.size())
	idx.sort_custom(func(a: int, b: int) -> bool: return w[a] > w[b] if w[a] != w[b] else a < b)
	var out: Array[PlayDef] = []
	for i in idx:
		out.append(defense_book.plays[i])
	return out


func _setup_formation() -> void:
	runner.setup_play(selected_play, def_play, downs.los_x, ball_y, off_lineup, def_lineup)
	field.los_x = downs.los_x
	field.first_down_x = downs.first_down_x
	field.down = downs.down
	if dcontrol != null:
		dcontrol.on_play_setup()
		if OS.get_cmdline_user_args().has("--hero-demo") and runner.controlled != null:   # screenshots
			var st := runner.controlled.start_pos
			runner.hero_path = PackedVector2Array([st + Vector2(-0.5, -3.0), st + Vector2(-1.5, -6.5), st + Vector2(-4.5, -8.5)])
			runner.controlled.duel_leverage = 0.8
			runner.controlled.duel_window = 9.0


func _update_scorebug() -> void:
	var gained := int(downs.los_x - drive_start_x)
	if _human_defense():
		hud.set_scorebug("DEFENSE  ·  %s  ·  %s" % [downs.down_text(), FieldGeo.spot_text(FieldGeo.LENGTH - downs.los_x)],
				"THEIR DRIVE %d PLAYS  %+d YDS" % [downs.plays, gained])
		return
	hud.set_scorebug("%s  ·  %s" % [downs.down_text(), FieldGeo.spot_text(downs.los_x)],
			"DRIVE %d PLAYS  %+d YDS" % [downs.plays, gained])


func _on_play_selected(play: PlayDef) -> void:
	if state != State.PLAY_CALL:
		return
	if _human_defense():
		def_play = play
	else:
		selected_play = play
	hud.set_selected(play)
	_setup_formation()
	if not _human_defense():
		_update_snap_hint()


func _update_snap_hint() -> void:
	hud.set_hint("DRAG BACK TO SNAP")


## Taps no longer snap on offense (drag back to snap); defense snaps through its own ready tap.
func _on_tap(_pos: Vector2) -> void:
	match state:
		State.DRIVE_OVER:
			_restart_drive()


func _snap() -> void:
	state = State.LIVE
	hud.show_play_bar(false)
	if use_memory and not _human_defense():
		runner.key_level = memory.key_level(selected_play.id, selected_play.formation.id, selected_play.category)
	if runner.key_level > 0.0:
		stats["keyed"] += 1
	hud.set_keyed(offense_book.plays, "")
	var cpu_offense := autoplay or _human_defense()
	# Defense pace: snaps the human doesn't play are simulated instantly.
	var auto_sim := _human_defense() and not autoplay and bot == null and not DefensePace.human_plays(pace, _situation())
	if auto_sim:
		runner.human_team = -1
	runner.snap()
	passer = CpuPasser.new(runner, runner.rng) if cpu_offense and not selected_play.is_run() else null
	if auto_sim:
		_simulate_current_play()
		return
	if _human_defense():
		hud.set_hint("DRAG TO MOVE  ·  RUN INTO THE CARRIER  ·  TAP HIM TO DIVE")
	elif selected_play.is_run():
		hud.set_hint("DRAG TO STEER  ·  SWIPE ← HESI  → DIVE  ↑↓ JUKE")
	else:
		hud.set_hint("DRAG BACK TO AIM, RELEASE TO THROW  ·  TAP = PASS TYPE  ·  DRAG FORWARD TO RUN")


## Runs the live play to the whistle in one go (Defense Pace auto-sim).
func _simulate_current_play() -> void:
	const DT := 1.0 / 60.0
	var guard := int(PlayRunner.WATCHDOG_SECONDS / DT) + 200
	while state == State.LIVE and guard > 0:
		guard -= 1
		_cpu_offense_step(DT)
		runner._physics_process(DT)
	runner.human_team = human_side


func _physics_process(dt: float) -> void:
	_cpu_offense_step(dt)
	if dcontrol != null and state == State.LIVE:
		dcontrol.update(dt)
		if bot != null:
			bot.step(dt)


func _cpu_offense_step(dt: float) -> void:
	if state == State.LIVE and passer != null and aim_demo and runner.qb_is_passer():
		_aim_demo_step(dt)
		return
	if state == State.LIVE and passer != null:
		passer.update(dt)


## --aim-demo: at 1.0 s show the aim preview on WR1's in-stride spot, throw 0.6 s later.
func _aim_demo_step(dt: float) -> void:
	if runner.play_time < 1.0:
		return
	var wr: PlayerAgent = runner.off_slots.get("WR1")
	if wr == null:
		passer.update(dt)
		return
	var target := runner.lead_point(wr)
	runner.aim_preview = target
	runner.aim_assist_target = wr
	aim.aim_active = true
	aim.aim_target = target
	if runner.play_time >= 1.6:
		aim.aim_active = false
		runner.aim_preview = Vector2.INF
		runner.throw_ball(target)


func _record(result: Dictionary) -> void:
	var type: String = result["type"]
	var gained: int = result["yards"] if type not in ["incomplete", "int", "int_td", "fumble"] else 0
	var bp: Array = by_play.get(selected_play.id, [0, 0, 0])
	bp[0] += 1
	bp[1] += gained
	bp[2] += 1 if type == "td" else 0
	by_play[selected_play.id] = bp
	if not _human_defense():
		memory.record(selected_play.id, selected_play.formation.id, selected_play.category,
				-10 if result["turnover"] else gained, selected_play.display_name)
	stats["plays"] += 1
	stats["yards"] += gained
	stats["broken"] += result.get("broken_tackles", 0)
	if selected_play.is_run():
		stats["runs"] += 1
		stats["run_yds"] += gained
	elif type != "sack":
		stats["att"] += 1
		if type in ["tackle", "out", "td", "fumble"] and result.get("pass_thrown", false):
			stats["comp"] += 1
			stats["pass_yds"] += gained
	if type == "int_td":
		stats["int"] += 1
	elif type in stats:
		stats[type] += 1
	if sim_target > 0 and OS.get_cmdline_user_args().has("--verbose"):
		print("  %-10s vs %-9s key=%.2f %-10s %+3d  bt=%d  air=%d kind=%d" % [selected_play.id, def_play.id,
				runner.key_level, type, result["yards"], result.get("broken_tackles", 0),
				int(result.get("air_yards", 0)), int(result.get("throw_kind", -1))])


func _print_stats() -> void:
	var s := stats
	if OS.get_cmdline_user_args().has("--by-play"):
		var ids := by_play.keys()
		ids.sort()
		for id in ids:
			var bp: Array = by_play[id]
			print("  %-12s %4d calls  %5.1f yds/play  %d TD" % [id, bp[0], float(bp[1]) / maxf(bp[0], 1), bp[2]])
	print("SIM %d plays | %.1f yds/play | pass %d/%d (%.0f%%) %d yds, %d INT, %d sacks | run %d for %d (%.1f ypc) | %d TD | %d fumbles | %d broken tackles | %d keyed | %.2f pts/drive (%d drives)" % [
		s["plays"], float(s["yards"]) / maxf(s["plays"], 1), s["comp"], s["att"],
		100.0 * s["comp"] / maxf(s["att"], 1), s["pass_yds"], s["int"], s["sack"],
		s["runs"], s["run_yds"], float(s["run_yds"]) / maxf(s["runs"], 1), s["td"], s["fumble"],
		s["broken"], s["keyed"], 7.0 * s["td"] / maxf(s["drives"], 1), s["drives"]])
	print(PlayRunner.pass_log_text())
	var cs := ContactResolver.stats
	print("TACKLES cpu %d/%d (%.0f%%), %d dives (%d reached him) | human %d/%d (%.0f%%)%s" % [cs["tackles"], cs["tries"],
			100.0 * cs["tackles"] / maxf(cs["tries"], 1), cs["dives"], cs["dive_tries"], cs["human_tackles"], cs["human_tries"],
			100.0 * cs["human_tackles"] / maxf(cs["human_tries"], 1),
			"" if bot == null else " | bot switches %d, dives %d, jumps %d" % [bot.stats["switches"], bot.stats["dives"], bot.stats["jumps"]]])


func _on_play_ended(result: Dictionary) -> void:
	_record(result)
	state = State.RESULT
	hud.set_hint("")
	hud.show_switch(false)
	var type: String = result["type"]
	var yards: int = result["yards"]
	var headline: String = result["text"]
	var outcome: DownTracker.Outcome
	match type:
		"incomplete":
			outcome = downs.apply_spot(downs.los_x)
		"int", "int_td", "fumble":
			_drive_over(headline, "PICK SIX!" if type == "int_td" else "TURNOVER")
			return
		"td":
			outcome = downs.apply_spot(result["spot_x"], true)
		_:
			outcome = downs.apply_spot(result["spot_x"])
			if headline == "" or type == "out":
				headline = _yards_text(yards)
			elif type == "sack":
				headline = "SACKED  %d" % yards
	ball_y = FieldGeo.clamp_to_hashes(result["spot_y"])
	match outcome:
		DownTracker.Outcome.TOUCHDOWN:
			_drive_over("TOUCHDOWN!" if not _human_defense() else "THEY SCORE",
					"%d PLAYS  %d YARDS" % [downs.plays, int(FieldGeo.OPP_GOAL - drive_start_x)])
			return
		DownTracker.Outcome.SAFETY:
			_drive_over("SAFETY!", "DRIVE OVER")
			return
		DownTracker.Outcome.TURNOVER_ON_DOWNS:
			_drive_over("TURNOVER ON DOWNS" if not _human_defense() else "DEFENSIVE STOP!", "DRIVE OVER")
			return
		DownTracker.Outcome.FIRST_DOWN:
			hud.show_banner(headline, "FIRST DOWN!")
		_:
			hud.show_banner(headline, downs.down_text())
	_update_scorebug()
	if sim_target > 0:
		return
	get_tree().create_timer(1.3).timeout.connect(func() -> void:
		if state == State.RESULT:
			_start_play_call())


func _yards_text(yards: int) -> String:
	if yards > 0:
		return "GAIN OF %d" % yards
	if yards < 0:
		return "LOSS OF %d" % -yards
	return "NO GAIN"


func _drive_over(title: String, sub: String) -> void:
	state = State.DRIVE_OVER
	stats["drives"] += 1
	_update_scorebug()
	hud.show_banner(title, sub, 99.0)
	hud.set_hint("TAP TO START A NEW DRIVE")
	hud.show_restart(true)
	if autoplay and sim_target == 0:
		get_tree().create_timer(1.0).timeout.connect(_restart_drive)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		_restart_drive()
