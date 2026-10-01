class_name GameSim
extends RefCounted
## Drive-by-drive simulation of (the rest of) a game, used by SIM GAME and "sim the rest of
## the game". It carries the game's momentum: each team's scoring rate blends its rating with
## how it has actually played so far (points AND yards per drive), so a team that has been
## dominating keeps dominating, a shootout stays a shootout, and a scoreless offense stays
## cold - with per-game form swings and turnovers so upsets and blowouts still happen.
## Every drive writes real box-score stats (plays, passes, rushes, sacks, TDs, FGs, punts,
## turnovers) so the numbers always add up to the score. Pure logic.

const POSSESSIONS_PER_GAME := 22.0     ## both teams together (~11 each)
const LEAGUE_PPD := 2.0                ## points per drive of an average offense
const PTS_PER_YARD := 0.069
const PASS_YPA := 6.8
const RUSH_YPC := 4.2
const SACK_YARDS := 6
const FORM_SD := 0.14                  ## per-game hot/cold swing of a team's scoring rate
const RATING_PTS := 0.4                ## expected points per game per rating point over the opponent
const FIELD_START := 37.0              ## field x of an average drive start (own 27)
const FIELD_SCALE := 55.0              ## sim_drive scoring rate +100% per this many yards of better field

## Outcome weights of an average drive; tilted by the offense's rating (see _outcome_probs).
const BASE := {"td": 0.215, "fg": 0.125, "miss": 0.02, "punt": 0.43, "turnover": 0.115, "downs": 0.095}


## Plays out everything left in `gs` (score, stats and clock are updated in place).
## strength: team abbr -> overall rating (used as the prior). Returns a small summary.
static func finish(gs: GameState, strength: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var left := _remaining_fraction(gs)
	var elapsed := 1.0 - left
	var teams := [gs.home, gs.away]
	var rate := {}
	var form := {}
	for t in teams:
		var opp := gs.other(t)
		var prior := clampf(22.0 + (float(strength.get(t, 75)) - float(strength.get(opp, 75)) + (1.5 if t == gs.home else -1.5)) * RATING_PTS, 8.0, 40.0) / (POSSESSIONS_PER_GAME * 0.5)
		var obs := _observed_ppd(gs, t)
		var w := clampf(elapsed * 1.5, 0.0, 0.65) if obs >= 0.0 else 0.0
		form[t] = rng.randfn(0.0, FORM_SD)
		rate[t] = maxf(0.25, (prior * (1.0 - w) + maxf(obs, 0.0) * w)) * exp(form[t])
	var summary := {"drives": 0, "momentum": {}}
	for t in teams:
		summary["momentum"][t] = snappedf(rate[t], 0.01)
	# Possessions left (a blowout burns clock: fewer drives), starting with the team that has the ball.
	var lead := absi(int(gs.score[gs.home]) - int(gs.score[gs.away]))
	var drives_f := left * POSSESSIONS_PER_GAME * (0.85 if lead >= 17 and left < 0.5 else 1.0)
	var n := int(drives_f) + (1 if rng.randf() < drives_f - floorf(drives_f) else 0)
	var off := gs.possession if gs.possession != "" else gs.away
	for i in n:
		_drive(gs, off, float(rate[off]), rng)
		summary["drives"] += 1
		off = gs.other(off)
	# Never end tied: overtime possessions until someone scores (first score wins, a stop hands over).
	var guard := 0
	while int(gs.score[gs.home]) == int(gs.score[gs.away]) and guard < 12:
		var before := int(gs.score[off])
		_drive(gs, off, float(rate[off]), rng)
		if int(gs.score[off]) == before:
			off = gs.other(off)
		guard += 1
	if int(gs.score[gs.home]) == int(gs.score[gs.away]):
		_add_fg(gs, gs.home if rng.randf() < 0.5 else gs.away, rng)
	gs.clock.seconds_left = 0.0
	gs.clock.stopped = true
	return summary


## Share of the game still to play (1 = kickoff, 0 = over).
static func _remaining_fraction(gs: GameState) -> float:
	if gs.clock.is_overtime():
		return 0.03
	var q := gs.clock.quarter
	return clampf(((4 - q) * GameClock.QUARTER + gs.clock.seconds_left) / (4.0 * GameClock.QUARTER), 0.0, 1.0)


## Points per drive the team has produced so far (a mix of points and yardage, less noisy than
## points alone), or -1 when there is no sample yet.
static func _observed_ppd(gs: GameState, t: String) -> float:
	var s: Dictionary = gs.stats[t]
	var plays := int(s["plays"])
	if plays < 6:
		return -1.0
	var drives := maxf(1.0, plays / 5.5)
	var pts := float(gs.score[t])
	return 0.5 * pts / drives + 0.5 * float(s["yards"]) * PTS_PER_YARD / drives


static func _outcome_probs(r: float, trailing_big: bool) -> Dictionary:
	var ratio := clampf(r / LEAGUE_PPD, 0.25, 2.6)
	var p := {}
	p["td"] = BASE["td"] * pow(ratio, 1.25)
	p["fg"] = BASE["fg"] * pow(ratio, 0.55)
	p["miss"] = BASE["miss"]
	p["turnover"] = BASE["turnover"] * pow(ratio, -0.45) * (1.25 if trailing_big else 1.0)
	p["downs"] = BASE["downs"] * pow(ratio, -0.3)
	p["punt"] = BASE["punt"] * pow(ratio, -0.9)
	var total := 0.0
	for k in p:
		total += float(p[k])
	for k in p:
		p[k] = float(p[k]) / total
	return p


static func _pick(p: Dictionary, rng: RandomNumberGenerator) -> String:
	var x := rng.randf()
	for k in p:
		x -= float(p[k])
		if x <= 0.0:
			return k
	return "punt"


## Expected points per drive for an offense rated `off_ovr` against a defense rated `def_ovr`
## (same prior as finish()), scaled by where the drive starts (field x, offense attacking +x):
## a short field scores more, a drive from the 5 less.
static func drive_rate(off_ovr: float, def_ovr: float, home: bool, start_x: float) -> float:
	var prior := clampf(22.0 + (off_ovr - def_ovr + (1.5 if home else -1.5)) * RATING_PTS, 8.0, 40.0) \
			/ (POSSESSIONS_PER_GAME * 0.5)
	return maxf(0.25, prior * clampf(1.0 + (start_x - FIELD_START) / FIELD_SCALE, 0.55, 1.9))


## One simulated possession for `off` from field x `start_x` (Retro Bowl-style CPU drives):
## points, stats and box score like finish(); yards fit the field.
## Returns {"outcome": td|fg|miss|punt|turnover|downs, "plays", "yards", "end_x", "int": bool}.
static func sim_drive(gs: GameState, off: String, r: float, start_x: float, rng: RandomNumberGenerator) -> Dictionary:
	return _drive(gs, off, r, rng, start_x)


## One possession for `off`: picks an outcome from the team's rate, then writes plays and yards
## that fit it, and the points. With `start_x` (>= 0) the yards fit the field from there.
static func _drive(gs: GameState, off: String, r: float, rng: RandomNumberGenerator, start_x := -1.0) -> Dictionary:
	var s: Dictionary = gs.stats[off]
	var diff := int(gs.score[off]) - int(gs.score[gs.other(off)])
	var outcome := _pick(_outcome_probs(r, diff <= -14), rng)
	var plays := 0
	var yards := 0
	match outcome:
		"td":
			plays = rng.randi_range(5, 11)
			yards = rng.randi_range(48, 90)
		"fg":
			plays = rng.randi_range(6, 11)
			yards = rng.randi_range(32, 58)
		"miss":
			plays = rng.randi_range(6, 10)
			yards = rng.randi_range(32, 58)
		"punt":
			plays = rng.randi_range(3, 6)
			yards = rng.randi_range(-4, 24)
		"turnover":
			plays = rng.randi_range(2, 7)
			yards = rng.randi_range(0, 42)
		_:
			plays = rng.randi_range(4, 9)
			yards = rng.randi_range(10, 46)
	if start_x >= 0.0:
		var room := int(FieldGeo.OPP_GOAL - start_x)
		match outcome:
			"td":
				yards = room
			"fg", "miss":
				yards = clampi(yards, 0, maxi(room - 3, 0))
				if room - yards > 42:   # out of field goal range: it's a punt after all
					outcome = "punt"
			_:
				yards = clampi(yards, int(FieldGeo.OWN_GOAL + 1.0 - start_x), maxi(room - 2, 0))
	# Style: trailing teams throw more, leading teams run the ball.
	var picked := false
	var pass_rate := clampf(0.56 - diff / 70.0, 0.32, 0.78)
	var passes := 0
	for i in plays:
		if rng.randf() < pass_rate:
			passes += 1
	var sacks := 0
	for i in passes:
		if rng.randf() < 0.055:
			sacks += 1
	var atts := passes - sacks
	var rushes := plays - passes
	var comp_pct := clampf(0.63 + (r - LEAGUE_PPD) * 0.04, 0.5, 0.74)
	var comps := 0
	for i in atts:
		if rng.randf() < comp_pct:
			comps += 1
	var gross := yards + sacks * SACK_YARDS
	var pass_w := atts * PASS_YPA * (1.0 if comps > 0 else 0.0)
	var rush_w := rushes * RUSH_YPC
	var pass_yds := 0
	if pass_w + rush_w > 0.0:
		pass_yds = int(round(gross * pass_w / (pass_w + rush_w)))
	var rush_yds := gross - pass_yds
	if rushes == 0:
		pass_yds = gross
		rush_yds = 0
	if comps == 0:
		rush_yds += pass_yds
		pass_yds = 0
		if rushes == 0:
			# All incompletions / sacks: the yardage is only the sack losses.
			rush_yds = 0
	s["plays"] += plays
	s["pass_att"] += atts
	s["pass_comp"] += comps
	s["pass_yds"] += pass_yds
	s["rush_att"] += rushes
	s["rush_yds"] += rush_yds
	s["sacks"] += sacks
	s["yards"] += pass_yds + rush_yds - sacks * SACK_YARDS
	if comps > 0:
		s["long_pass"] = maxi(int(s["long_pass"]), mini(pass_yds, int(pass_yds * rng.randf_range(0.3, 0.75)) + 3))
	if rushes > 0 and rush_yds > 0:
		s["long_run"] = maxi(int(s["long_run"]), mini(rush_yds, int(rush_yds * rng.randf_range(0.3, 0.8)) + 2))
	match outcome:
		"td":
			var pass_td := comps > 0 and (rushes == 0 or rng.randf() < 0.62)
			if pass_td:
				s["pass_td"] += 1
			else:
				s["rush_td"] += 1
			gs.add_points(off, 6 + (1 if rng.randf() < 0.94 else 0))
		"fg":
			s["fg_att"] += 1
			s["fg_made"] += 1
			s["fg_long"] = maxi(int(s["fg_long"]), int(yards * 0.5) + 17 + rng.randi_range(0, 6))
			gs.add_points(off, 3)
		"miss":
			s["fg_att"] += 1
		"punt":
			s["punts"] += 1
		"turnover":
			if rng.randf() < 0.65:
				s["int"] += 1
				picked = true
			else:
				s["fumbles_lost"] += 1
	return {"outcome": outcome, "plays": plays, "yards": yards, "int": picked,
			"end_x": (start_x if start_x >= 0.0 else FieldGeo.OWN_GOAL + 25.0) + yards}


static func _add_fg(gs: GameState, team: String, rng: RandomNumberGenerator) -> void:
	var s: Dictionary = gs.stats[team]
	s["plays"] += 6
	s["rush_att"] += 3
	s["rush_yds"] += 11
	s["pass_att"] += 3
	s["pass_comp"] += 2
	s["pass_yds"] += 24
	s["yards"] += 35
	s["fg_att"] += 1
	s["fg_made"] += 1
	s["fg_long"] = maxi(int(s["fg_long"]), 30 + rng.randi_range(0, 10))
	gs.add_points(team, 3)
