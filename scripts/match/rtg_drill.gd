class_name RtgDrill
extends Node2D
## Road to Glory drills: three live reps of your position in the real engine with the Road to
## Glory controls (the combine before the draft, and weekly practice for XP). Each rep is a
## fixed call against a fixed coverage; RtgTracker grades it; the average is the drill grade.
## config: {pos, player (RtgRules player), purpose: "combine" | "practice", back: scene path}.
## Finishing goes to `back` with {"drill": {purpose, points, letter, grades}}.

const DT := 1.0 / 60.0
const REPS := {
	"RB": [["hb_dive", "cover2"], ["toss", "cover3"], ["inside_zone", "lb_blitz"]],
	"WR": [["slants", "cover1"], ["four_verts", "cover3"], ["comebacks", "press"]],
	"CB": [["slants", "cover1"], ["four_verts", "press"], ["curls", "cover1"]],
	"QB": [["slants", "cover3"], ["flood", "cover2"], ["deep_shot", "cover1"]],
}
const TIPS := {
	"RB": "LEFT THUMB RUNS. TRY THE BUTTONS: JUKE, SPIN, POWER (STIFF ARM / TRUCK), DIVE, BURST.",
	"WR": "YOU RUN EVERYTHING: FOLLOW THE GOLD ROUTE WITH THE STICK (WANDER OFF IT AND THE QB WON'T TRUST IT). TAP CALL WHEN OPEN, GET UNDER THE BALL AND TAP CATCH TO GO UP AND MOSS THEM.",
	"CB": "STICK = YOUR CORNER (LET GO AND HE COVERS ON HIS OWN). JAM AT THE SNAP, WATCH FOR THE ! BREAK, TAP BALL TO LEAP.",
	"QB": "RIGHT THUMB: DRAG BACK TO SNAP, KEEP PULLING TO AIM, RELEASE TO THROW. LEFT THUMB MOVES YOU IN THE POCKET.",
}

@export var tuning: GameplayTuning = preload("res://data/tuning/gameplay_tuning.tres")

var config: Dictionary = {}
var pos := "WR"
var slot := "WR1"
var rep := 0
var tracker: RtgTracker
var grades: Array[float] = []
var _passer: CpuPasser
var _waiting := false
var _done := false
var _rng := RandomNumberGenerator.new()

var field: FieldView
var runner: PlayRunner
var routes: PlayOverlay
var aim: PlayOverlay
var overlay: RtgOverlay
var camera: CameraRig
var hud: MatchHUD
var touch: TouchInput
var ocontrol: HumanOffenseControl
var pad: RtgPad
var ctl: RtgControl


func _ready() -> void:
	if config.is_empty():
		config = SceneRouter.take_config()
	_rng.randomize()
	var p: Dictionary = config.get("player", {})
	if p.is_empty():
		p = RtgRules.new_player(str(config.get("pos", "WR")), "", "ROOKIE", "PROSPECT", 11, {})
		p["arch"] = RtgRules.ARCHETYPES[p["pos"]][0]["id"]
	config["player"] = p
	pos = str(p["pos"])
	slot = RtgRules.SLOT[pos]
	tracker = RtgTracker.new(pos, slot)
	_build()
	Music.play("game")
	hud.show_banner("THE COMBINE" if config.get("purpose", "combine") == "combine" else "PRACTICE",
			"3 REPS  ·  SHOW THEM WHAT YOU'VE GOT", 1.8)
	hud.show_tip(TIPS[pos])
	_setup_rep.call_deferred()


func _build() -> void:
	field = FieldView.new()
	field.left_label = "COMBINE"
	field.right_label = "DRILLS"
	add_child(field)
	runner = PlayRunner.new()
	runner.tuning = tuning
	runner.rng = _rng
	runner.aim_sens = Settings.aim_mult()
	runner.off_colors = RtgCard.colors("") if pos != "CB" else {"primary": Color("#a12b2b"), "secondary": Color.WHITE, "helmet": Color("#7a1f1f"), "pants": Color.WHITE}
	runner.def_colors = RtgCard.colors("") if pos == "CB" else {"primary": Color("#1f3f8f"), "secondary": Color.WHITE, "helmet": Color("#18306b"), "pants": Color.WHITE}
	runner.lock_slot = slot
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
	hud.runner = runner
	add_child(hud)
	hud.set_scorebug("", "DRILL")
	hud.rtg_action.connect(_on_action)
	hud.choice_made.connect(func(_i: int) -> void: _finish())
	touch = TouchInput.new()
	touch.ui_blocker = hud.is_point_over_ui
	add_child(touch)
	ocontrol = HumanOffenseControl.new()
	add_child(ocontrol)
	ocontrol.bind(runner, touch, tuning)
	ocontrol.enabled = pos == "QB"
	ocontrol.aim_only = true
	ocontrol.snap_requested.connect(func() -> void:
		if runner.phase == PlayRunner.Phase.PRE_SNAP and not _waiting:
			_snap())
	ocontrol.aim_changed.connect(func(on: bool, target: Vector2) -> void:
		aim.aim_active = on
		aim.aim_target = target)
	pad = RtgPad.new()
	pad.left_handed = Settings.left_handed
	pad.blocker = hud.is_point_over_ui
	hud.add_rtg_pad(pad)
	ctl = RtgControl.new()
	add_child(ctl)
	ctl.bind(runner, pad, tuning)
	ctl.trust = 1.0
	overlay = RtgOverlay.new()
	overlay.runner = runner
	overlay.control = ctl
	add_child(overlay)
	ctl.action.connect(func(text: String, at: Vector2, good: bool) -> void: overlay.pop(text, at, good))
	runner.move_event.connect(func(kind: String, at: Vector2, agent: PlayerAgent) -> void:
		if agent == runner.locked:
			overlay.pop({"truck": "TRUCKED!", "stiff": "STIFF ARM!", "spin": "SPUN OFF!", "juke": "ANKLES!"}.get(kind, "BROKE IT!"), at)
			Sfx.play("slam"))
	runner.play_ended.connect(_on_play_ended)
	runner.big_hit.connect(func(_at: Vector2, _s: float) -> void: Sfx.play("hit"))
	runner.ball_thrown.connect(func(_t: Vector2) -> void: Sfx.play("throw"))


## Drill lineups: college-gray 72s on both sides, you in your slot.
func _lineups(off: PlayDef, def: PlayDef) -> Array:
	var o := {}
	var d := {}
	var n := 2
	for s in off.formation.slots:
		o[s] = {"name": "PROSPECT", "jersey": n, "attrs": RatingModel.fill_attrs(off.formation.slots[s]["pos"], 72)}
		n += 7
	for s in def.formation.slots:
		d[s] = {"name": "PROSPECT", "jersey": n % 99, "attrs": RatingModel.fill_attrs(def.formation.slots[s]["pos"], 72)}
		n += 5
	var p: Dictionary = config["player"]
	var me := {"name": str(p.get("name", "YOU")), "jersey": int(p.get("jersey", 0)), "attrs": p["attrs"], "look": p.get("look", {})}
	if pos == "CB":
		d[slot] = me
	else:
		o[slot] = me
	return [o, d]


func _setup_rep() -> void:
	var r: Array = REPS[pos][rep]
	var off: PlayDef = load("res://data/plays/offense/%s.tres" % r[0])
	var def: PlayDef = load("res://data/plays/defense/%s.tres" % r[1])
	var l := _lineups(off, def)
	runner.human_team = PlayerAgent.Team.DEFENSE if pos == "CB" else PlayerAgent.Team.OFFENSE
	runner.human_input = ctl
	runner.setup_play(off, def, FieldGeo.OWN_GOAL + 30.0, FieldGeo.CENTER_Y, l[0], l[1])
	ctl.on_play_setup()
	field.los_x = runner.los_x
	field.first_down_x = runner.los_x + 10.0
	field.down = 1
	camera.snap_to_target()
	var call := off if pos != "CB" else def
	var job := RtgPlay.job_text(call, slot, runner.locked.start_pos.y, runner.ball_y)
	_waiting = false
	if pos == "QB":
		hud.show_rtg_call("REP %d OF 3: %s" % [rep + 1, off.display_name.to_upper()], "DRAG BACK ON THE RIGHT TO SNAP", [])
		hud.set_hint("RIGHT: DRAG BACK TO SNAP AND AIM  ·  LEFT: MOVE")
	else:
		hud.show_rtg_call("REP %d OF 3: %s" % [rep + 1, call.display_name.to_upper()], "YOUR JOB: " + job,
				[{"id": "go", "text": "SNAP ▶" if pos != "CB" else "READY ▶", "yellow": true}])
		hud.set_hint("STICK MOVES YOU  ·  BUTTONS ON THE RIGHT")


func _on_action(id: String) -> void:
	if id == "go" and runner.phase == PlayRunner.Phase.PRE_SNAP and not _waiting:
		Sfx.play("tap")
		_snap()


func _snap() -> void:
	hud.hide_rtg_call()
	hud.set_hint("")
	runner.snap()
	_passer = null
	if not runner.is_run_play() and pos != "QB":
		_passer = CpuPasser.new(runner, _rng)
		var fav: PlayerAgent = runner.locked
		if pos == "CB":
			fav = (runner.locked.brain as ManCoverBrain).mark if runner.locked.brain is ManCoverBrain else null
		if fav != null:
			_passer.set_favorite(fav, 3.0)   # the drill is about you: the ball comes your way


func _physics_process(dt: float) -> void:
	if runner == null:
		return
	if runner.phase == PlayRunner.Phase.PRE_SNAP:
		ctl.pre_snap_step(dt)
	elif runner.phase == PlayRunner.Phase.LIVE and _passer != null:
		_passer.update(dt)


func _on_play_ended(r: Dictionary) -> void:
	var g := tracker.record(r, {"side": "defense" if pos == "CB" else "offense", "run_play": runner.is_run_play()})
	if g.is_empty():
		g = {"pts": 55.0, "letter": RtgTracker.letter(55.0), "note": "NOT INVOLVED"}
	grades.append(float(g["pts"]))
	hud.show_grade(str(g["letter"]), str(g["note"]))
	Sfx.play("whistle")
	_waiting = true
	rep += 1
	get_tree().create_timer(1.8).timeout.connect(func() -> void:
		if rep >= 3:
			_results()
		else:
			_setup_rep())


func points() -> float:
	if grades.is_empty():
		return 55.0
	var s := 0.0
	for g in grades:
		s += g
	return s / grades.size()


func _results() -> void:
	var pts := points()
	var l := RtgTracker.letter(pts)
	var lines: Array[String] = []
	for i in grades.size():
		lines.append("REP %d: %s" % [i + 1, RtgTracker.letter(grades[i])])
	var what := "COMBINE GRADE" if config.get("purpose", "combine") == "combine" else "PRACTICE GRADE"
	Sfx.play("big" if RtgTracker.tier(l) == 2 else "reveal")
	hud.show_choice("%s: %s" % [what, l], "  ·  ".join(lines), ["CONTINUE"] as Array[String])


func _finish() -> void:
	if _done:
		return
	_done = true
	var back: String = config.get("back", SceneRouter.RTG_DRAFT)
	SceneRouter.goto(back, {"drill": {"purpose": config.get("purpose", "combine"), "points": points(),
			"letter": RtgTracker.letter(points()), "grades": grades.duplicate()}})
