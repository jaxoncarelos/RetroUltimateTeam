extends GutTest
## AI LAB (not part of the unit suite): batches of plays through the real engine with stats
## that say whether the AI plays smart. Run:
##   $GODOT --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/lab -gprefix=lab_ -gexit  (LAB=cpu,runs filters)
## Scenarios:
##   cpu        CPU offense vs CPU defense, the whole playbook, equal 78s
##   wr_bot     Road to Glory receiver run by a human-like bot (follows the route with a lag and
##              wobble, CALLs when open, taps CATCH) -> target share / completion / INT on him
##   wr_idle    the RTG receiver never moves (worst case): the QB must not feed picks to him
##   runs       run plays only -> ypc, stuffs, explosives

const DT := 1.0 / 60.0
const N := 300

var t: GameplayTuning
var off_book: PlaybookDef
var def_book: PlaybookDef


func before_all() -> void:
	t = load("res://data/tuning/gameplay_tuning.tres")
	off_book = load("res://data/plays/offense_playbook.tres")
	def_book = load("res://data/plays/defense_playbook.tres")


func _lineup(form: FormationDef, ovr: int) -> Dictionary:
	var out := {}
	for slot in form.slots:
		out[slot] = {"name": slot, "attrs": RatingModel.fill_attrs(form.slots[slot]["pos"], ovr)}
	return out


func _new_stats() -> Dictionary:
	return {"plays": 0, "att": 0, "comp": 0, "int": 0, "sack": 0, "pass_yds": 0, "runs": 0, "run_yds": 0,
			"stuffs": 0, "explosive": 0, "throwaway": 0, "throw_time": 0.0, "sep": 0.0, "sep_n": 0, "td": 0,
			"my_tgt": 0, "my_comp": 0, "my_int": 0, "my_yds": 0, "lane_int": 0, "air": 0.0, "broken": 0}


## One batch. mode: "cpu" | "wr_bot" | "wr_idle" | "runs".
var calib: Array = []
var by_def: Dictionary = {}   ## def play id -> [att, comp, sep_sum, yds, int]


func _batch(mode: String, n := N) -> Dictionary:
	calib = [[0, 0, 0, 0.0], [0, 0, 0, 0.0], [0, 0, 0, 0.0], [0, 0, 0, 0.0], [0, 0, 0, 0.0]]
	by_def = {}
	var st := _new_stats()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	PlayRunner.pass_log = {"att": 0, "comp": 0, "int": 0, "deep_att": 0, "deep_comp": 0, "deep_int": 0,
			"lane_tips": 0, "lane_ints": 0, "lob": 0, "touch": 0, "bullet": 0}
	for i in n:
		var runner := PlayRunner.new()
		runner.tuning = t
		runner.rng.seed = 7000 + i
		add_child(runner)
		var pad := RtgPad.new()
		var ctl := RtgControl.new()
		add_child(pad)
		add_child(ctl)
		ctl.bind(runner, pad, t)
		var ended: Array = []
		runner.play_ended.connect(func(r: Dictionary) -> void: ended.append(r))
		var sit := {"down": rng.randi_range(1, 3), "to_go": rng.randi_range(2, 10), "los_x": rng.randf_range(25.0, 75.0),
				"score_diff": 0, "seconds_left": 999.0}
		var off: PlayDef
		if mode == "runs":
			var runs: Array[PlayDef] = []
			for p in off_book.plays:
				if p.is_run():
					runs.append(p)
			off = runs[rng.randi() % runs.size()]
		elif mode.begins_with("wr"):
			var passes: Array[PlayDef] = []
			for p in off_book.plays:
				if not p.is_run() and RtgPlay.features(p, "WR1"):
					passes.append(p)
			off = passes[rng.randi() % passes.size()]
		else:
			off = PlayAdvisor.pick(off_book.plays, sit, rng)
		var def: PlayDef = AIPlayCaller.pick_defense(def_book.plays, null, sit, rng, null)
		var rtg := mode.begins_with("wr")
		runner.human_team = PlayerAgent.Team.OFFENSE if rtg else -1
		runner.lock_slot = "WR1" if rtg else ""
		runner.human_input = ctl if rtg else null
		var off_ovr := int(OS.get_environment("LAB_OFF")) if OS.get_environment("LAB_OFF") != "" else 78
		var def_ovr := int(OS.get_environment("LAB_DEF")) if OS.get_environment("LAB_DEF") != "" else 78
		var ol := _lineup(off.formation, off_ovr)
		if rtg:
			var rookie := OS.get_environment("LAB_ROOKIE") != ""
			ol["WR1"] = {"name": "ME", "attrs": RtgRules.start_attrs("WR", "deep_threat") if rookie else RtgRules.debug_match_rtg("WR")["player"]["attrs"]}
		runner.setup_play(off, def, sit["los_x"], FieldGeo.CENTER_Y, ol, _lineup(def.formation, def_ovr))
		ctl.on_play_setup()
		runner.snap()
		var passer: CpuPasser = null
		if not off.is_run():
			passer = CpuPasser.new(runner, rng)
			if rtg:
				passer.set_favorite(runner.locked, t.rtg_favor_base + t.rtg_favor_trust * 0.5)
		var thrown_at := -1.0
		var bot := _Bot.new(rng)
		for k in 1200:
			if passer != null:
				passer.update(DT)
			if mode == "wr_bot":
				bot.drive(runner, ctl, pad)
			elif mode == "wr_wild":
				bot.wild(runner, ctl, pad)
			runner._physics_process(DT)
			if runner.pass_thrown and thrown_at < 0.0:
				thrown_at = runner.play_time
				if runner.intended != null:
					var sep := 99.0
					for d in runner.defense:
						sep = minf(sep, d.field_pos.distance_to(runner.intended.field_pos))
					st["sep"] += minf(sep, 15.0)
					st["sep_n"] += 1
			if not ended.is_empty():
				break
		if not ended.is_empty():
			_tally(st, ended[0], off, thrown_at, rtg)
			var r1: Dictionary = ended[0]
			if r1["pass_thrown"]:
				if not by_def.has(def.id):
					by_def[def.id] = [0, 0, 0.0, 0, 0]
				var bd: Array = by_def[def.id]
				bd[0] += 1
				bd[1] += 1 if str(r1["type"]) not in ["incomplete", "int", "int_td"] else 0
				bd[3] += int(r1["yards"]) if str(r1["type"]) not in ["incomplete", "int", "int_td"] else 0
				bd[4] += 1 if str(r1["type"]) in ["int", "int_td"] else 0
			if passer != null and not passer.thrown.is_empty():
				var tp: Dictionary = passer.thrown
				var r0: Dictionary = ended[0]
				var b := clampi(int(float(tp["p_comp"]) * 5.0), 0, 4)
				calib[b][0] += 1
				calib[b][1] += 1 if str(r0["type"]) not in ["incomplete", "int", "int_td"] else 0
				calib[b][2] += 1 if str(r0["type"]) in ["int", "int_td"] else 0
				calib[b][3] += float(tp["p_int"])
				if str(r0["type"]) in ["int", "int_td"] and OS.get_environment("LAB_V") != "":
					print("INT: pc %.2f pi %.2f adv %.2f late %.2f air %.1f %s" % [tp["p_comp"], tp["p_int"], tp["adv"], tp["late"], float(tp["spot"].x) - runner.los_x, r0["text"]])
		runner.queue_free()
		pad.queue_free()
		ctl.queue_free()
	st["lane_int"] = int(PlayRunner.pass_log["lane_ints"])
	return st


func _tally(st: Dictionary, r: Dictionary, off: PlayDef, thrown_at: float, rtg: bool) -> void:
	var type := str(r["type"])
	var yards := int(r["yards"])
	st["plays"] += 1
	if type == "td" or type == "int_td":
		st["td"] += 1 if type == "td" else 0
	if r["pass_thrown"]:
		st["att"] += 1
		st["throw_time"] += thrown_at
		if str(r.get("target_slot", "")) == "":
			st["throwaway"] += 1
		if type in ["int", "int_td"]:
			st["int"] += 1
		elif type not in ["incomplete"]:
			st["comp"] += 1
			st["pass_yds"] += yards
			st["air"] += float(r.get("air_yards", 0.0))
			st["broken"] += int(r.get("broken_tackles", 0))
		if rtg and str(r.get("target_slot", "")) == "WR1":
			st["my_tgt"] += 1
			if type in ["int", "int_td"]:
				st["my_int"] += 1
			elif type != "incomplete":
				st["my_comp"] += 1
				st["my_yds"] += yards
	elif type == "sack":
		st["sack"] += 1
	elif off.is_run() or not r["pass_thrown"]:
		st["runs"] += 1
		st["run_yds"] += yards
		if yards <= 0:
			st["stuffs"] += 1
		if yards >= 12:
			st["explosive"] += 1


static func line(name: String, s: Dictionary) -> String:
	var att := maxf(s["att"], 1)
	var dropbacks := maxf(s["att"] + s["sack"], 1)
	var txt := "%-8s plays %d | pass %d/%d %.0f%% %.1f ypa INT %.1f%% sack %.1f%% away %d | ttt %.2fs sep %.1f yd | run %d %.1f ypc stuff %.0f%% exp %.0f%% | td %d lane-int %d" % [
		name, s["plays"], s["comp"], s["att"], 100.0 * s["comp"] / att, s["pass_yds"] / att, 100.0 * s["int"] / att,
		100.0 * s["sack"] / dropbacks, s["throwaway"], s["throw_time"] / att, s["sep"] / maxf(s["sep_n"], 1),
		s["runs"], float(s["run_yds"]) / maxf(s["runs"], 1), 100.0 * s["stuffs"] / maxf(s["runs"], 1),
		100.0 * s["explosive"] / maxf(s["runs"], 1), s["td"], s["lane_int"]]
	if int(s["comp"]) > 0:
		txt += " | air %.1f yac %.1f per comp, broken %.2f" % [s["air"] / s["comp"], (s["pass_yds"] - s["air"]) / s["comp"], float(s["broken"]) / s["comp"]]
	if int(s["my_tgt"]) > 0 or name.begins_with("wr"):
		txt += " | YOU tgt %d (%.0f%% of att) comp %d INT %d yds %d" % [s["my_tgt"], 100.0 * s["my_tgt"] / att,
				s["my_comp"], s["my_int"], s["my_yds"]]
	return txt


func test_lab() -> void:
	var only := OS.get_environment("LAB")
	for mode in ["cpu", "wr_bot", "wr_wild", "wr_idle", "runs"]:
		if only != "" and not mode in only.split(","):
			continue
		gut.p(line(mode, _batch(mode)))
		gut.p("   " + PlayRunner.pass_log_text())
		var cl: Array[String] = []
		for i in 5:
			var c: Array = calib[i]
			if int(c[0]) > 0:
				cl.append("p%.1f-%.1f: n%d comp %.0f%% int %.0f%% (pred %.0f%%)" % [i * 0.2, i * 0.2 + 0.2, c[0], 100.0 * c[1] / c[0], 100.0 * c[2] / c[0], 100.0 * c[3] / c[0]])
		gut.p("   calib " + " | ".join(cl))
		var dl: Array[String] = []
		for k in by_def:
			var a: Array = by_def[k]
			dl.append("%s %d/%d %.1fypa i%d" % [k, a[1], a[0], float(a[3]) / maxf(a[0], 1), a[4]])
		gut.p("   by coverage: " + "  ".join(dl))
	assert_true(true)


## A human-like receiver: runs his route with a reaction lag and some wobble, cuts a bit
## late, CALLs when nobody is near him, goes to the ball's landing spot and taps CATCH.
class _Bot:
	var rng: RandomNumberGenerator
	var lag := 0.0
	var wobble := Vector2.ZERO

	func _init(p_rng: RandomNumberGenerator) -> void:
		rng = p_rng
		lag = rng.randf_range(0.1, 0.35)

	func drive(r: PlayRunner, ctl: RtgControl, pad: RtgPad) -> void:
		var me := r.locked
		if me == null or r.phase != PlayRunner.Phase.LIVE:
			return
		if r.play_time < lag:
			pad.stick = Vector2.ZERO
			return
		var target := Vector2.INF
		if r.ball.state == Ball.State.AIR and (r.intended == me or me.field_pos.distance_to(r.ball.to) < 6.0):
			target = r.ball.to
			if r.ball.time_left() <= t_window(r):
				ctl.press("catch")
		elif me == r.carrier:
			target = me.field_pos + Vector2(6.0, 0.0)
		else:
			var path: PackedVector2Array = me.assignment.get("path", PackedVector2Array())
			var pts := PackedVector2Array([me.start_pos])
			for p in path:
				pts.append(me.start_pos + p)
			if str(me.assignment.get("end", "continue")) != "sit" and pts.size() >= 2:
				pts.append(pts[pts.size() - 1] + (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized() * 40.0)
			# Aim at the next route point he hasn't reached (with a sloppy radius).
			for i in range(1, pts.size()):
				if me.field_pos.distance_to(pts[i]) > 1.6 and (pts[i] - me.field_pos).dot(pts[i] - pts[i - 1]) > 0.0:
					target = pts[i]
					break
			var near := 99.0
			for d in r.defense:
				near = minf(near, d.field_pos.distance_to(me.field_pos))
			if near > 3.5 and r.play_time > 1.2 and rng.randf() < 0.02:
				ctl.press("call")
		if target == Vector2.INF:
			pad.stick = Vector2.ZERO
			return
		if rng.randf() < 0.05:
			wobble = Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4))
		var d := (target - me.field_pos)
		var screen := Vector2(d.x * FieldProjection.PX_X, d.y * FieldProjection.PX_Y).normalized() + wobble
		pad.stick = screen.normalized() if d.length() > 0.4 else Vector2.ZERO

	var heading := Vector2.RIGHT
	var turn_at := 0.0

	## A player who freelances: sprints, changes direction every so often (often after the
	## QB has started his throw), spams CALL, chases the ball late.
	func wild(r: PlayRunner, ctl: RtgControl, pad: RtgPad) -> void:
		var me := r.locked
		if me == null or r.phase != PlayRunner.Phase.LIVE:
			return
		if r.play_time >= turn_at:
			turn_at = r.play_time + rng.randf_range(0.4, 1.3)
			heading = Vector2.from_angle(rng.randf_range(-1.6, 1.6))
		if rng.randf() < 0.03:
			ctl.press("call")
		var target := me.field_pos + Vector2(heading.x * 5.0, heading.y * 5.0)
		if r.ball.state == Ball.State.AIR and r.ball.time_left() < 0.5 and rng.randf() < 0.5:
			target = r.ball.to
			ctl.press("catch")
		var d := target - me.field_pos
		pad.stick = Vector2(d.x * FieldProjection.PX_X, d.y * FieldProjection.PX_Y).normalized()

	func t_window(r: PlayRunner) -> float:
		return r.tuning.rtg_catch_window * 0.7
