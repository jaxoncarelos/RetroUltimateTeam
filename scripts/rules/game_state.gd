class_name GameState
extends RefCounted
## Everything about a game in progress except the live play: teams, score, possession,
## downs (always in the possessing team's coordinates, attacking +x), clock, timeouts,
## overtime and box-score stats. apply_result() turns a PlayRunner result into state
## changes and returns what happens next. Pure logic (no nodes).

enum Next {
	PLAY,          ## next snap
	PAT,           ## touchdown scored: extra point / 2-pt try by `possession`
	KICKOFF,       ## `possession` kicks off (after a score, to start a half)
	FREE_KICK,     ## after a safety: `possession` free-kicks
	END_PERIOD,    ## the clock expired: move to the next period
}

var home := "HOME"
var away := "AWAY"
var score := {}
var possession := ""            ## team with the ball
var downs := DownTracker.new()
var clock: GameClock
var timeouts := {}
var opening_receiver := ""      ## team that received the opening kickoff
var ot_possessions := 0         ## completed overtime possessions
var overtime := false           ## the game went to overtime
var ot_first := ""
var stats := {}                 ## team -> box score dictionary
var drive_start_x := 35.0
var last_event := ""            ## human-readable summary of the last state change


func _init(p_home := "HOME", p_away := "AWAY", real_quarter_seconds := 150.0) -> void:
	home = p_home
	away = p_away
	score = {home: 0, away: 0}
	timeouts = {home: 3, away: 3}
	clock = GameClock.new(real_quarter_seconds)
	for t in [home, away]:
		stats[t] = {"pass_att": 0, "pass_comp": 0, "pass_yds": 0, "pass_td": 0, "int": 0,
				"rush_att": 0, "rush_yds": 0, "rush_td": 0, "sacks": 0, "fumbles_lost": 0,
				"fg_made": 0, "fg_att": 0, "punts": 0, "plays": 0, "yards": 0, "watchdog": 0,
				"long_pass": 0, "long_run": 0, "fg_long": 0, "pick6": 0}


func other(team: String) -> String:
	return away if team == home else home


func defense() -> String:
	return other(possession)


## Gives `team` the ball at `x` (its own coordinates), first and ten.
func start_possession(team: String, x: float) -> void:
	possession = team
	downs.start_drive(clampf(x, FieldGeo.OWN_GOAL + 1.0, FieldGeo.OPP_GOAL - 1.0))
	drive_start_x = downs.los_x


func add_points(team: String, pts: int) -> void:
	score[team] = int(score[team]) + pts


func score_diff(team: String) -> int:
	return int(score[team]) - int(score[other(team)])


## Situation dictionary for play callers (offense's perspective unless `team` given).
func situation(team := "") -> Dictionary:
	var t := possession if team == "" else team
	return {
		"down": downs.down, "to_go": downs.to_go(), "los_x": downs.los_x,
		"score_diff": score_diff(t),
		"seconds_left": clock.game_seconds_left() if not clock.is_overtime() else 999.0,
		"half_seconds_left": clock.half_seconds_left(),
		"quarter": clock.quarter,
	}


## Game seconds that come off between plays for the offense's tempo.
func runoff(t: GameplayTuning) -> float:
	var diff := score_diff(possession)
	if clock.half_seconds_left() <= 120.0 and diff < 0:
		return t.runoff_hurry
	if clock.quarter == 4 and clock.seconds_left <= 240.0 and diff > 0:
		return t.runoff_milk
	return t.runoff_normal


func use_timeout(team: String) -> bool:
	if int(timeouts[team]) <= 0:
		return false
	timeouts[team] = int(timeouts[team]) - 1
	clock.timeout()
	return true


func reset_timeouts() -> void:
	timeouts = {home: 3, away: 3}


## Applies a PlayRunner result. `run_play` = the offense called a run. Returns Next.
## Turnovers flip possession (spots converted to the new offense's coordinates).
func apply_result(r: Dictionary, run_play: bool, seconds_before_play: float) -> Next:
	var off := possession
	var def := other(off)
	var s: Dictionary = stats[off]
	var type: String = r["type"]
	var yards: int = r["yards"]
	var spot_x: float = r["spot_x"]
	var thrown: bool = r.get("pass_thrown", false)
	var stop := false
	s["plays"] += 1
	if int(r.get("watchdog", 0)) > 0:
		s["watchdog"] += 1
	# Box score
	if run_play or (not thrown and type != "sack" and type != "incomplete"):
		if type not in ["int", "int_td"]:
			s["rush_att"] += 1
			s["rush_yds"] += yards
			s["yards"] += yards
			s["long_run"] = maxi(int(s["long_run"]), yards)
	elif type == "sack":
		s["sacks"] += 1
		s["yards"] += yards
	else:
		s["pass_att"] += 1
		if type in ["tackle", "out", "td", "fumble", "safety"]:
			s["pass_comp"] += 1
			s["pass_yds"] += yards
			s["yards"] += yards
			s["long_pass"] = maxi(int(s["long_pass"]), yards)
	match type:
		"incomplete":
			stop = true
			var o := downs.apply_spot(downs.los_x)
			return _after_downs(o, off, stop, seconds_before_play)
		"int", "fumble":
			if type == "int":
				s["int"] += 1
			else:
				s["fumbles_lost"] += 1
			last_event = "TURNOVER"
			finish_drive(true, seconds_before_play)
			var new_x := FieldGeo.LENGTH - spot_x
			if new_x <= FieldGeo.OWN_GOAL:
				new_x = FieldGeo.OWN_GOAL + 20.0   # downed in the end zone: touchback
			start_possession(def, new_x)
			return _period_check()
		"int_td":
			s["int"] += 1
			stats[def]["pick6"] += 1
			add_points(def, 6)
			last_event = "PICK SIX"
			finish_drive(true, seconds_before_play)
			possession = def
			return Next.PAT
		"td":
			add_points(off, 6)
			if run_play or not thrown:
				s["rush_td"] += 1
			else:
				s["pass_td"] += 1
			last_event = "TOUCHDOWN"
			finish_drive(true, seconds_before_play)
			return Next.PAT
		"safety":
			add_points(def, 2)
			last_event = "SAFETY"
			finish_drive(true, seconds_before_play)
			return Next.FREE_KICK
	# tackle / sack / out
	stop = type == "out"
	var outcome := downs.apply_spot(spot_x)
	return _after_downs(outcome, off, stop, seconds_before_play)


func _after_downs(o: DownTracker.Outcome, off: String, stop: bool, before: float) -> Next:
	match o:
		DownTracker.Outcome.TOUCHDOWN:
			add_points(off, 6)
			last_event = "TOUCHDOWN"
			finish_drive(true, before)
			return Next.PAT
		DownTracker.Outcome.SAFETY:
			add_points(other(off), 2)
			last_event = "SAFETY"
			finish_drive(true, before)
			return Next.FREE_KICK
		DownTracker.Outcome.TURNOVER_ON_DOWNS:
			last_event = "TURNOVER ON DOWNS"
			finish_drive(true, before)
			start_possession(other(off), FieldGeo.LENGTH - downs.los_x)
			return _period_check()
		DownTracker.Outcome.FIRST_DOWN:
			last_event = "FIRST DOWN"
		_:
			last_event = ""
	if clock.end_play(stop, before):
		last_event = "TWO-MINUTE WARNING"
	return _period_check()


## Field goal attempt box score (made/attempted/long). Call once per attempt.
func record_field_goal(team: String, made: bool, dist: float) -> void:
	var s: Dictionary = stats[team]
	s["fg_att"] += 1
	if made:
		s["fg_made"] += 1
		s["fg_long"] = maxi(int(s["fg_long"]), int(round(dist)))


## One team's game box score for postgame rewards/objectives (ObjectiveRules.match_values):
## its own stats plus pf, pa, won, tds, def_sacks, def_ints, def_pick6 and the
## longest_pass / longest_run aliases.
func box_score(team: String) -> Dictionary:
	var opp := other(team)
	var b: Dictionary = stats[team].duplicate()
	b["pf"] = int(score[team])
	b["pa"] = int(score[opp])
	b["won"] = int(score[team]) > int(score[opp])
	b["tds"] = int(b["pass_td"]) + int(b["rush_td"])
	b["def_sacks"] = int(stats[opp]["sacks"])
	b["def_ints"] = int(stats[opp]["int"])
	b["def_pick6"] = int(b["pick6"])
	b["longest_pass"] = int(b["long_pass"])
	b["longest_run"] = int(b["long_run"])
	return b


func finish_drive(stop_clock: bool, before: float) -> void:
	clock.end_play(stop_clock, before)
	if clock.is_overtime():
		ot_possessions += 1


func _period_check() -> Next:
	return Next.END_PERIOD if clock.expired() else Next.PLAY


## Overtime is over when, after both teams had the ball once, the score differs,
## or anyone scores in sudden death (called after each OT possession ends).
func overtime_decided() -> bool:
	if ot_possessions < 2:
		return false
	return score[home] != score[away]


func winner() -> String:
	if score[home] == score[away]:
		return ""
	return home if score[home] > score[away] else away
