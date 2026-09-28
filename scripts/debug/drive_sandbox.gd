extends Node2D
## Phase 1 test bed: one human offensive drive from the own 25 against the CPU defense.
## Tap a play, tap the field to snap. R restarts the drive (keyboard).
## Debug user args (after "--"):
##   --autoplay   CPU calls plays, snaps and throws (watch a drive without touching)
##   --sim=N      headless batch: autoplay N plays at 4x speed, print stats, quit

enum State { PLAY_CALL, LIVE, RESULT, DRIVE_OVER }

const START_X := 35.0
const OFF_TEAM := "KC"
const DEF_TEAM := "PHI"
const OFF_OVR := 80
const DEF_OVR := 78

@export var tuning: GameplayTuning = preload("res://data/tuning/gameplay_tuning.tres")
@export var offense_book: PlaybookDef = preload("res://data/plays/offense_playbook.tres")
@export var defense_book: PlaybookDef = preload("res://data/plays/defense_playbook.tres")

var state := State.PLAY_CALL
var downs := DownTracker.new()
var selected_play: PlayDef
var def_play: PlayDef
var ball_y := FieldGeo.CENTER_Y
var drive_start_x := START_X
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

var autoplay := false
var sim_target := 0
var stats := {"plays": 0, "yards": 0, "att": 0, "comp": 0, "int": 0, "sack": 0, "td": 0,
		"runs": 0, "run_yds": 0, "pass_yds": 0, "broken": 0}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--autoplay":
			autoplay = true
		elif arg.begins_with("--sim="):
			autoplay = true
			sim_target = int(arg.get_slice("=", 1))
			Engine.time_scale = 4.0
	var teams := TeamData.load_all()
	var off_team: TeamData = teams[OFF_TEAM]
	var def_team: TeamData = teams[DEF_TEAM]

	field = FieldView.new()
	field.left_endzone = off_team.primary
	field.right_endzone = def_team.primary
	field.left_label = off_team.team_name.to_upper()
	field.right_label = def_team.team_name.to_upper()
	add_child(field)

	runner = PlayRunner.new()
	runner.tuning = tuning
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

	camera = CameraRig.new()
	camera.runner = runner
	add_child(camera)
	camera.make_current()

	hud = MatchHUD.new()
	add_child(hud)
	hud.set_playbook(offense_book.plays)
	hud.play_selected.connect(_on_play_selected)
	hud.restart_pressed.connect(_restart_drive)

	touch = TouchInput.new()
	touch.ui_blocker = hud.is_point_over_ui
	add_child(touch)
	touch.tapped.connect(_on_tap)

	control = HumanOffenseControl.new()
	add_child(control)
	control.bind(runner, touch, tuning)
	control.aim_changed.connect(func(on: bool, target: Vector2) -> void:
		aim.aim_active = on
		aim.aim_target = target)

	runner.play_ended.connect(_on_play_ended)
	off_lineup = _generic_lineup(offense_book.plays[0].formation, OFF_OVR)
	def_lineup = _generic_lineup(defense_book.plays[0].formation, DEF_OVR)
	selected_play = offense_book.plays[0]
	_restart_drive()


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


func _start_play_call() -> void:
	state = State.PLAY_CALL
	def_play = defense_book.plays[runner.rng.randi() % defense_book.plays.size()]
	_setup_formation()
	hud.show_play_bar(true)
	hud.set_selected(selected_play)
	hud.set_hint("PICK A PLAY  ·  TAP THE FIELD TO SNAP")
	_update_scorebug()
	if autoplay:
		selected_play = offense_book.plays[runner.rng.randi() % offense_book.plays.size()]
		hud.set_selected(selected_play)
		_setup_formation()
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if state == State.PLAY_CALL:
				_snap())


func _setup_formation() -> void:
	runner.setup_play(selected_play, def_play, downs.los_x, ball_y, off_lineup, def_lineup)
	field.los_x = downs.los_x
	field.first_down_x = downs.first_down_x


func _update_scorebug() -> void:
	var gained := int(downs.los_x - drive_start_x)
	hud.set_scorebug("%s  ·  %s" % [downs.down_text(), FieldGeo.spot_text(downs.los_x)],
			"DRIVE %d PLAYS  %+d YDS" % [downs.plays, gained])


func _on_play_selected(play: PlayDef) -> void:
	if state != State.PLAY_CALL:
		return
	selected_play = play
	hud.set_selected(play)
	_setup_formation()


func _on_tap(_pos: Vector2) -> void:
	match state:
		State.PLAY_CALL:
			_snap()
		State.DRIVE_OVER:
			_restart_drive()


func _snap() -> void:
	state = State.LIVE
	hud.show_play_bar(false)
	runner.snap()
	if selected_play.is_run():
		hud.set_hint("DRAG UP/DOWN TO STEER  ·  FLICK TO JUKE  ·  DOUBLE-TAP TO DIVE")
	else:
		hud.set_hint("DRAG BACK TO AIM, RELEASE TO THROW  ·  DRAG FORWARD TO RUN")


func _physics_process(_dt: float) -> void:
	if autoplay and state == State.LIVE and runner.qb_is_passer() and runner.play_time > 1.0:
		var read := QBReadLogic.best_throw(runner)
		if not read.is_empty() and (read["openness"] > 2.5 or runner.play_time > 2.4):
			runner.throw_ball(read["target"])


func _record(result: Dictionary) -> void:
	var type: String = result["type"]
	stats["plays"] += 1
	stats["yards"] += result["yards"] if type != "incomplete" and type != "int" else 0
	stats["broken"] += result.get("broken_tackles", 0)
	if selected_play.is_run():
		stats["runs"] += 1
		stats["run_yds"] += result["yards"]
	elif type != "sack":
		stats["att"] += 1
		if type in ["tackle", "out", "td"] and runner.pass_thrown:
			stats["comp"] += 1
			stats["pass_yds"] += result["yards"]
	if type in stats:
		stats[type] += 1
	if sim_target > 0 and OS.get_cmdline_user_args().has("--verbose"):
		print("  %-10s %-10s %+3d  bt=%d" % [selected_play.id, type, result["yards"], result.get("broken_tackles", 0)])
	if sim_target > 0 and stats["plays"] >= sim_target:
		_print_stats()
		get_tree().quit()


func _print_stats() -> void:
	var s := stats
	print("SIM %d plays | %.1f yds/play | pass %d/%d (%.0f%%) %d yds, %d INT, %d sacks | run %d for %d (%.1f ypc) | %d TD | %d broken tackles" % [
		s["plays"], float(s["yards"]) / maxf(s["plays"], 1), s["comp"], s["att"],
		100.0 * s["comp"] / maxf(s["att"], 1), s["pass_yds"], s["int"], s["sack"],
		s["runs"], s["run_yds"], float(s["run_yds"]) / maxf(s["runs"], 1), s["td"], s["broken"]])


func _on_play_ended(result: Dictionary) -> void:
	_record(result)
	state = State.RESULT
	hud.set_hint("")
	var type: String = result["type"]
	var yards: int = result["yards"]
	var headline: String = result["text"]
	var outcome: DownTracker.Outcome
	match type:
		"incomplete":
			outcome = downs.apply_spot(downs.los_x)
		"int":
			_drive_over("INTERCEPTED!", "DRIVE OVER")
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
			_drive_over("TOUCHDOWN!", "%d PLAYS  %d YARDS" % [downs.plays, int(FieldGeo.OPP_GOAL - drive_start_x)])
			return
		DownTracker.Outcome.SAFETY:
			_drive_over("SAFETY!", "DRIVE OVER")
			return
		DownTracker.Outcome.TURNOVER_ON_DOWNS:
			_drive_over("TURNOVER ON DOWNS", "DRIVE OVER")
			return
		DownTracker.Outcome.FIRST_DOWN:
			hud.show_banner(headline, "FIRST DOWN!")
		_:
			hud.show_banner(headline, downs.down_text())
	_update_scorebug()
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
	_update_scorebug()
	hud.show_banner(title, sub, 99.0)
	hud.set_hint("TAP TO START A NEW DRIVE")
	hud.show_restart(true)
	if autoplay:
		get_tree().create_timer(1.0).timeout.connect(_restart_drive)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		_restart_drive()
