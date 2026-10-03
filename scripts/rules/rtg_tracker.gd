class_name RtgTracker
extends RefCounted
## Road to Glory: your stat line and per-play grades in one game. MatchController feeds
## every finished play you were on the field for (PlayRunner result + context); record()
## returns the play's grade ({} when the play didn't involve you enough to grade).
## Grade points are 0..100 (C = 60, B = 73, A = 87). Pure logic.

const LETTERS := [[93.0, "A+"], [87.0, "A"], [82.0, "A-"], [78.0, "B+"], [73.0, "B"], [69.0, "B-"],
		[65.0, "C+"], [60.0, "C"], [55.0, "C-"], [50.0, "D+"], [45.0, "D"], [40.0, "D-"], [0.0, "F"]]

var pos := "WR"
var slot := "WR1"
var stats: Dictionary = {}
var grades: Array[float] = []
## Notable moments for the postgame screen: [{text, pts}].
var highlights: Array = []


func _init(p_pos := "WR", p_slot := "WR1") -> void:
	pos = p_pos
	slot = p_slot
	stats = empty_stats()


static func empty_stats() -> Dictionary:
	return {"plays": 0, "rush_att": 0, "rush_yds": 0, "rush_td": 0, "long_rush": 0, "targets": 0, "rec": 0,
			"rec_yds": 0, "rec_td": 0, "long_rec": 0, "yac": 0, "drops": 0, "fumbles": 0, "broken": 0,
			"pass_att": 0, "pass_comp": 0, "pass_yds": 0, "pass_td": 0, "ints_thrown": 0, "sacked": 0,
			"def_targets": 0, "comp_allowed": 0, "yds_allowed": 0, "td_allowed": 0, "ints": 0, "pbu": 0,
			"tackles": 0, "stops": 0, "def_td": 0}


static func letter(points: float) -> String:
	for l in LETTERS:
		if points >= float(l[0]):
			return l[1]
	return "F"


## Letter grade color tier: 2 good (A/B), 1 ok (C), 0 bad (D/F).
static func tier(l: String) -> int:
	if l.begins_with("A") or l.begins_with("B"):
		return 2
	return 1 if l.begins_with("C") else 0


## One play. ctx: {run_play: bool, side: "offense"/"defense"}. Returns {pts, letter, note}
## or {} when the play is not graded (you were not involved).
func record(r: Dictionary, ctx: Dictionary) -> Dictionary:
	stats["plays"] += 1
	var g: Dictionary = {}
	if str(ctx.get("side", "offense")) == "offense":
		g = _offense(r, bool(ctx.get("run_play", false)))
	else:
		g = _defense(r, bool(ctx.get("run_play", false)))
	if g.is_empty():
		return {}
	var pts := clampf(float(g["pts"]), 0.0, 100.0)
	grades.append(pts)
	var out := {"pts": pts, "letter": letter(pts), "note": str(g.get("note", ""))}
	if pts >= 90.0 or pts <= 25.0:
		highlights.append({"text": out["note"], "pts": pts})
	return out


func _offense(r: Dictionary, run_play: bool) -> Dictionary:
	var type := str(r.get("type", ""))
	var yards := int(r.get("yards", 0))
	var thrown: bool = r.get("pass_thrown", false)
	var mine_carry := str(r.get("carrier_slot", "")) == slot
	var targeted := thrown and str(r.get("target_slot", "")) == slot
	var td := type == "td"
	var broken := int(r.get("broken_tackles", 0)) if mine_carry else 0
	if pos == "QB":
		return _qb(r, run_play)
	if mine_carry and not thrown:
		# A run (or a reverse / pitch) with you carrying.
		stats["rush_att"] += 1
		stats["rush_yds"] += yards
		stats["long_rush"] = maxi(int(stats["long_rush"]), yards)
		stats["broken"] += broken
		if td:
			stats["rush_td"] += 1
		if type == "fumble":
			stats["fumbles"] += 1
			return {"pts": 15.0, "note": "FUMBLE"}
		var p := _run_points(yards) + broken * 3.0 + (8.0 if td else 0.0)
		return {"pts": p, "note": "TOUCHDOWN RUN" if td else _yds("RUN", yards)}
	if targeted:
		stats["targets"] += 1
		var caught := type in ["tackle", "td", "out", "fumble", "safety"] and mine_carry
		if caught:
			stats["rec"] += 1
			stats["rec_yds"] += yards
			stats["long_rec"] = maxi(int(stats["long_rec"]), yards)
			stats["broken"] += broken
			var cx := float(r.get("catch_x", -1.0))
			if cx >= 0.0:
				stats["yac"] += maxi(0, int(round(float(r.get("spot_x", cx)) - cx)))
			if td:
				stats["rec_td"] += 1
			if type == "fumble":
				stats["fumbles"] += 1
				return {"pts": 20.0, "note": "FUMBLE AFTER THE CATCH"}
			var p := 72.0 + yards * 1.2 + broken * 4.0 + (14.0 if td else 0.0)
			return {"pts": minf(p, 99.0), "note": "TOUCHDOWN CATCH" if td else _yds("CATCH", yards)}
		if r.get("drop", false):
			stats["drops"] += 1
			return {"pts": 20.0, "note": "DROPPED IT"}
		if type in ["int", "int_td"]:
			return {"pts": 42.0, "note": "PICKED OFF"}
		var contested := str(r.get("cover_slot", "")) != ""
		return {"pts": 56.0 if contested else 46.0, "note": "BROKEN UP" if contested else "INCOMPLETE"}
	return {}


func _qb(r: Dictionary, _run_play: bool) -> Dictionary:
	var type := str(r.get("type", ""))
	var yards := int(r.get("yards", 0))
	var thrown: bool = r.get("pass_thrown", false)
	var td := type == "td"
	if type == "sack":
		stats["sacked"] += 1
		return {"pts": 32.0, "note": "SACKED"}
	if thrown:
		stats["pass_att"] += 1
		if type in ["int", "int_td"]:
			stats["ints_thrown"] += 1
			return {"pts": 10.0 if type == "int_td" else 14.0, "note": "INTERCEPTION"}
		if type == "incomplete":
			return {"pts": 48.0, "note": "INCOMPLETE"}
		stats["pass_comp"] += 1
		stats["pass_yds"] += yards
		if td:
			stats["pass_td"] += 1
		var air := float(r.get("air_yards", 0.0))
		return {"pts": minf(70.0 + air * 0.8 + yards * 0.35 + (16.0 if td else 0.0), 99.0),
				"note": "TOUCHDOWN PASS" if td else _yds("COMPLETION", yards)}
	if str(r.get("carrier_slot", "")) == "QB":
		stats["rush_att"] += 1
		stats["rush_yds"] += yards
		stats["long_rush"] = maxi(int(stats["long_rush"]), yards)
		if td:
			stats["rush_td"] += 1
		if type == "fumble":
			stats["fumbles"] += 1
			return {"pts": 15.0, "note": "FUMBLE"}
		return {"pts": _run_points(yards) + 4.0 + (8.0 if td else 0.0), "note": "TOUCHDOWN RUN" if td else _yds("SCRAMBLE", yards)}
	return {}   # a handoff: the back's play, not yours


func _defense(r: Dictionary, run_play: bool) -> Dictionary:
	var type := str(r.get("type", ""))
	var yards := int(r.get("yards", 0))
	var thrown: bool = r.get("pass_thrown", false)
	var covered := thrown and str(r.get("cover_slot", "")) == slot
	var tackled := str(r.get("tackler_slot", "")) == slot
	if type in ["int", "int_td"] and str(r.get("carrier_slot", "")) == slot:
		stats["ints"] += 1
		stats["def_targets"] += 1
		if type == "int_td":
			stats["def_td"] += 1
		return {"pts": 99.0, "note": "PICK SIX!" if type == "int_td" else "INTERCEPTION!"}
	if covered:
		stats["def_targets"] += 1
		if type == "incomplete":
			if str(r.get("ball_def_slot", "")) == slot:
				stats["pbu"] += 1
				return {"pts": 92.0, "note": "PASS BREAKUP"}
			return {"pts": 82.0, "note": "BLANKET COVERAGE"}
		if type in ["int", "int_td"]:
			return {"pts": 88.0, "note": "TIGHT COVERAGE - PICKED"}
		stats["comp_allowed"] += 1
		stats["yds_allowed"] += yards
		if tackled:
			stats["tackles"] += 1
		if type == "td":
			stats["td_allowed"] += 1
			return {"pts": 10.0, "note": "GAVE UP A TOUCHDOWN"}
		return {"pts": clampf(64.0 - yards * 1.6 + (6.0 if tackled else 0.0), 20.0, 70.0), "note": _yds("CATCH ALLOWED", yards)}
	if tackled:
		stats["tackles"] += 1
		if type == "sack":
			return {"pts": 95.0, "note": "SACK!"}
		if yards <= 2 and run_play:
			stats["stops"] += 1
			return {"pts": 86.0, "note": "RUN STOP"}
		return {"pts": maxf(74.0 - maxf(yards - 6, 0) * 1.2, 55.0), "note": _yds("TACKLE", yards)}
	return {}


static func _run_points(yards: int) -> float:
	if yards <= 0:
		return 35.0 + maxf(yards, -5) * 2.0
	if yards <= 2:
		return 52.0
	if yards <= 4:
		return 64.0
	if yards <= 9:
		return 74.0 + (yards - 5) * 1.0
	if yards <= 19:
		return 86.0 + (yards - 10) * 0.4
	return 96.0


static func _yds(what: String, yards: int) -> String:
	return "%d YD %s" % [yards, what] if yards >= 0 else "%s FOR A LOSS" % what


## Game grade points: the average play grade, nudged by the size of the day (TDs, yards,
## picks), a little toward C when you barely played.
func game_points() -> float:
	if grades.is_empty():
		return 60.0
	var sum := 0.0
	for g in grades:
		sum += g
	var avg := sum / grades.size()
	var bonus := 0.0
	bonus += 2.5 * (int(stats["rush_td"]) + int(stats["rec_td"]) + int(stats["pass_td"]) + int(stats["def_td"]))
	bonus += 3.0 * int(stats["ints"])
	bonus += minf((int(stats["rush_yds"]) + int(stats["rec_yds"])) / 40.0, 4.0)
	bonus -= 3.0 * (int(stats["fumbles"]) + int(stats["ints_thrown"]))
	var weight := clampf(grades.size() / 6.0, 0.3, 1.0)
	return clampf(lerpf(60.0, avg, weight) + bonus, 0.0, 100.0)


func game_letter() -> String:
	return letter(game_points())


## Adds a simulated share of a game (the rest of a game you left, or a SIM game).
func add_sim(line: Dictionary, sim_points: float, plays := 6) -> void:
	for k in line:
		if stats.has(k):
			if str(k).begins_with("long_"):
				stats[k] = maxi(int(stats[k]), int(line[k]))
			else:
				stats[k] += int(line[k])
	for i in plays:
		grades.append(sim_points)


## What the match hands back (match_result()["rtg"]).
func summary() -> Dictionary:
	return {"pos": pos, "slot": slot, "stats": stats.duplicate(), "grade": game_letter(),
			"points": game_points(), "graded": grades.size(), "highlights": highlights.duplicate()}


## One-line stat line for the HUD / results ("6 REC 84 YDS 1 TD").
static func line_text(pos: String, s: Dictionary) -> String:
	match pos:
		"QB":
			var t := "%d/%d %d YDS" % [s["pass_comp"], s["pass_att"], s["pass_yds"]]
			if int(s["pass_td"]) > 0:
				t += " %d TD" % s["pass_td"]
			if int(s["ints_thrown"]) > 0:
				t += " %d INT" % s["ints_thrown"]
			if int(s["rush_att"]) > 0:
				t += " · %d RUSH YDS" % s["rush_yds"]
			return t
		"RB":
			var t := "%d CAR %d YDS" % [s["rush_att"], s["rush_yds"]]
			if int(s["rush_td"]) + int(s["rec_td"]) > 0:
				t += " %d TD" % (int(s["rush_td"]) + int(s["rec_td"]))
			if int(s["rec"]) > 0:
				t += " · %d REC %d YDS" % [s["rec"], s["rec_yds"]]
			return t
		"WR", "TE":
			var t := "%d REC %d YDS" % [s["rec"], s["rec_yds"]]
			if int(s["rec_td"]) > 0:
				t += " %d TD" % s["rec_td"]
			if int(s["targets"]) > int(s["rec"]):
				t += " (%d TGT)" % s["targets"]
			return t
	var d := "%d TKL" % s["tackles"]
	if int(s["ints"]) > 0:
		d += " %d INT" % s["ints"]
	if int(s["pbu"]) > 0:
		d += " %d PD" % s["pbu"]
	d += " · %d/%d ALLOWED" % [s["comp_allowed"], s["def_targets"]]
	return d
