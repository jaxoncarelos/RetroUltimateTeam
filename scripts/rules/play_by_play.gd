class_name PlayByPlay
extends RefCounted
## Play-by-play for simulated games. GameSim only decides a drive's outcome, plays, yards and
## points; `synthesize` invents a plausible, deterministic (seeded) list of plays that adds up
## to exactly those yards and ends in the real outcome. `from_log` normalises a real played-play
## log recorded by the match controller into the same shape. Pure logic.
##
## Play dict: {team, drive, down, dist, from_x, to_x, yards, text, result, header}
##   from_x/to_x: 0-100 yard scale from the offense's own goal line (100 = the end zone).
##   result: "gain" | "first_down" | "td" | "fg" | "miss" | "punt" | "turnover" | "downs".
##   header: non-empty only on a drive's first play ("KC drive 3 - TD, 8 plays 75 yd").
##   yards: net yards gained by the snap (0 for kicks and turnovers).
##   kick_yards (kicks only): length of the punt / field goal.

const OUTCOME_LABEL := {"td": "TD", "fg": "FG", "miss": "MISSED FG", "punt": "PUNT", "turnover": "TURNOVER",
		"downs": "DOWNS", "end": "END"}


## Whole game: every drive of `drive_log` (GameSim.finish()["drive_log"]) back to back.
static func from_drives(drive_log: Array, rng_seed: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var counts := {}
	for i in drive_log.size():
		var d: Dictionary = drive_log[i]
		var team := str(d.get("team", ""))
		counts[team] = int(counts.get(team, 0)) + 1
		var plays := synthesize(d, rng_seed + i * 7919)
		if plays.is_empty():
			continue
		plays[0]["header"] = drive_header(d, int(counts[team]))
		for p in plays:
			p["drive"] = i
			out.append(p)
	return out


static func drive_header(d: Dictionary, number: int) -> String:
	return "%s drive %d - %s, %d plays %d yd" % [str(d.get("team", "")), number,
			str(OUTCOME_LABEL.get(str(d.get("outcome", "end")), "END")), int(d.get("plays", 0)), int(d.get("yards", 0))]


## One drive {team, outcome, plays, yards, points, start_x} -> its plays. The scrimmage yards
## sum to drive["yards"]; the last play carries the real outcome.
static func synthesize(drive: Dictionary, rng_seed: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var team := str(drive.get("team", ""))
	var outcome := str(drive.get("outcome", "end"))
	var total_plays := maxi(1, int(drive.get("plays", 1)))
	var total_yards := int(drive.get("yards", 0))
	var start := float(drive.get("start_x", 25.0))
	var spot := int(round(start))
	# Scrimmage snaps (the rest of the plays are the kick / the turnover / the failed 4th down).
	var k := total_plays if outcome in ["td", "end"] else maxi(1, total_plays - 1)
	var remaining := total_yards
	var down := 1
	var dist := mini(10, 100 - spot)
	var out: Array[Dictionary] = []
	for i in k:
		var left := k - i
		var last := left == 1
		var gain: int
		if last:
			gain = remaining
		else:
			var mean := float(remaining) / float(left)
			gain = int(round(mean + rng.randfn(0.0, maxf(2.5, absf(mean) * 0.8))))
			if rng.randf() < 0.18:
				gain = mini(gain, rng.randi_range(-6, 1))
			gain = clampi(gain, -9, 40)
			# Mid-drive 4th downs have to convert (the drive goes on).
			if down == 4 and gain < dist and remaining - dist >= left - 1:
				gain = dist
			if outcome == "td" and spot + gain >= 100 and left > 1:
				gain = maxi(1, 100 - spot - 1)
		var is_pass := rng.randf() < 0.55
		var p := _snap_play(team, down, dist, spot, gain, is_pass, rng)
		var scoring := last and outcome == "td"
		var first := gain >= dist
		p["result"] = "td" if scoring else ("first_down" if first else "gain")
		if scoring:
			p["text"] = _lead(p) + ("Pass complete, %d yd TOUCHDOWN!" if is_pass else "Run, %d yd TOUCHDOWN!") % maxi(gain, 0)
		out.append(p)
		remaining -= gain
		spot += gain
		if first:
			down = 1
			dist = mini(10, maxi(1, 100 - spot))
		else:
			down += 1
			dist -= gain
		if down > 4 and not last:
			down = 4   # cannot happen after the forced conversion; keep labels sane
	# The closing play.
	match outcome:
		"fg", "miss":
			var len := clampi(100 - spot + 17, 18, 62)
			var made := outcome == "fg"
			var p := _base(team, 4, maxi(dist, 1), spot)
			p["to_x"] = float(spot)
			p["kick_yards"] = len
			p["result"] = "fg" if made else "miss"
			p["text"] = _lead(p) + ("Field goal GOOD, %d yd" if made else "Field goal NO GOOD, %d yd") % len
			out.append(p)
		"punt":
			var len2 := clampi(rng.randi_range(36, 54), 20, maxi(20, 100 - spot + 10))
			var p2 := _base(team, 4, maxi(dist, 1), spot)
			p2["to_x"] = float(spot)
			p2["kick_yards"] = len2
			p2["result"] = "punt"
			p2["text"] = "4th & %d - Punt, %d yd" % [maxi(dist, 1), len2]
			out.append(p2)
		"turnover":
			var d3 := mini(down, 4)
			var p3 := _base(team, d3, maxi(dist, 1), spot)
			p3["to_x"] = float(spot)
			p3["result"] = "turnover"
			p3["text"] = _lead(p3) + ("Pass INTERCEPTED!" if rng.randf() < 0.65 else "Ball FUMBLED, defense recovers!")
			out.append(p3)
		"downs":
			var p4 := _base(team, 4, maxi(dist, 1), spot)
			p4["to_x"] = float(spot)
			p4["result"] = "downs"
			p4["text"] = _lead(p4) + "No good, turnover on downs"
			out.append(p4)
	return out


## Normalises a real played-play log ({quarter, clock, down, dist, spot, text, yards, team,
## result?}) into play dicts. Drives are split where the team changes; `header` is filled.
static func from_log(log: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var drive := -1
	var last_team := "\u0000"
	var counts := {}
	for e in log:
		var d: Dictionary = (e as Dictionary).duplicate()
		var team := str(d.get("team", ""))
		d["header"] = ""
		if team != last_team:
			drive += 1
			last_team = team
			counts[team] = int(counts.get(team, 0)) + 1
			d["header"] = "%s drive %d" % [team, int(counts[team])]
		d["drive"] = drive
		d["down"] = int(d.get("down", 1))
		d["dist"] = int(d.get("dist", 10))
		d["from_x"] = float(d.get("from_x", d.get("spot", 25.0)))
		d["yards"] = int(d.get("yards", 0))
		d["to_x"] = float(d.get("to_x", float(d["from_x"]) + int(d["yards"])))
		d["result"] = str(d.get("result", "gain"))
		d["text"] = str(d.get("text", ""))
		d["team"] = team
		out.append(d)
	return out


## "Play had 10 yd gain" style summary shown after each tap.
static func summary(p: Dictionary) -> String:
	var y := int(p.get("yards", 0))
	match str(p.get("result", "gain")):
		"td":
			return "TOUCHDOWN!"
		"fg":
			return "Field goal is good!"
		"miss":
			return "Field goal missed"
		"punt":
			return "Punt, %d yd" % int(p.get("kick_yards", 0))
		"turnover":
			return "TURNOVER!"
		"downs":
			return "Turnover on downs"
	if y > 0:
		return "Play had %d yd gain" % y
	if y == 0:
		return "Play had no gain"
	return "Play lost %d yd" % -y


# ---------------------------------------------------------------- helpers

static func _spot_name(spot: int) -> String:
	if spot == 50:
		return "the 50"
	return "own %d" % spot if spot < 50 else "opp %d" % (100 - spot)


static func _ordinal(d: int) -> String:
	return ["1st", "2nd", "3rd", "4th"][clampi(d - 1, 0, 3)]


static func _lead(p: Dictionary) -> String:
	return "%s & %d at %s - " % [_ordinal(int(p["down"])), int(p["dist"]), _spot_name(int(p["from_x"]))]


static func _base(team: String, down: int, dist: int, spot: int) -> Dictionary:
	return {"team": team, "drive": 0, "down": down, "dist": dist, "from_x": float(spot), "to_x": float(spot),
			"yards": 0, "text": "", "result": "gain", "header": ""}


static func _snap_play(team: String, down: int, dist: int, spot: int, gain: int, is_pass: bool,
		rng: RandomNumberGenerator) -> Dictionary:
	var p := _base(team, down, dist, spot)
	p["yards"] = gain
	p["to_x"] = float(spot + gain)
	var t: String
	if is_pass:
		if gain < 0:
			t = "Sacked, %d yd loss" % -gain
		elif gain == 0:
			t = "Pass incomplete" if rng.randf() < 0.8 else "Pass complete, no gain"
		else:
			t = "Pass complete, %d yd gain" % gain
	else:
		if gain < 0:
			t = "Run stopped, %d yd loss" % -gain
		elif gain == 0:
			t = "Run, no gain"
		else:
			t = "Run, %d yd gain" % gain
	if gain > 0 and gain >= dist:
		t += " - FIRST DOWN"
	p["text"] = _lead(p) + t
	return p

