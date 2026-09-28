class_name ChallengeRules
extends RefCounted
## Challenge scenarios (PLAN.md §6): a deterministic start state and a goal, played with
## the full match engine. Plus a Daily Challenge generated from the date.
##
## start: {quarter, clock (game seconds left in the quarter), you, opp (scores),
##         ball: "you"|"opp", yard (yard line of the team with the ball, own goal = 0),
##         down, to_go}
## goal: "win" | "td" (score a TD on this drive) | "score" (any points on this drive)
##       | "stop" (their drive ends without points) | "tds:N" (N TDs before the period ends)
##       | "ints:N" (N interceptions before the game ends)

const LIST := [
	{"id": "two_minute_drill", "title": "TWO-MINUTE DRILL", "desc": "DOWN 4 WITH 1:45 LEFT. DRIVE 70 YARDS AND WIN.",
			"start": {"quarter": 4, "clock": 105, "you": 17, "opp": 21, "ball": "you", "yard": 30, "down": 1, "to_go": 10},
			"goal": "win", "coins": 400, "pack": "silver", "opponent": "BUF"},
	{"id": "goal_line_stand", "title": "GOAL LINE STAND", "desc": "UP 3, THEY HAVE 1ST & GOAL AT YOUR 5. NO POINTS.",
			"start": {"quarter": 4, "clock": 40, "you": 24, "opp": 21, "ball": "opp", "yard": 95, "down": 1, "to_go": 5},
			"goal": "stop", "coins": 350, "pack": "defense", "opponent": "BAL"},
	{"id": "protect_the_lead", "title": "PROTECT THE LEAD", "desc": "UP 4 WITH 3:00 LEFT. THEY START AT THEIR 25.",
			"start": {"quarter": 4, "clock": 180, "you": 21, "opp": 17, "ball": "opp", "yard": 25, "down": 1, "to_go": 10},
			"goal": "win", "coins": 400, "pack": "", "opponent": "CIN"},
	{"id": "comeback_kids", "title": "COMEBACK KIDS", "desc": "DOWN 14 WITH 5:00 LEFT. YOUR BALL AT YOUR 25. WIN IT.",
			"start": {"quarter": 4, "clock": 300, "you": 7, "opp": 21, "ball": "you", "yard": 25, "down": 1, "to_go": 10},
			"goal": "win", "coins": 800, "pack": "gold", "opponent": "DET"},
	{"id": "fourth_and_goal", "title": "4TH AND GOAL", "desc": "DOWN 4, 0:10 LEFT, 4TH & GOAL AT THE 3. SCORE A TD.",
			"start": {"quarter": 4, "clock": 10, "you": 20, "opp": 24, "ball": "you", "yard": 97, "down": 4, "to_go": 3},
			"goal": "td", "coins": 300, "pack": "", "opponent": "SF"},
	{"id": "air_raid", "title": "AIR RAID", "desc": "SCORE 2 TOUCHDOWNS BEFORE HALFTIME (3:00 LEFT IN Q2).",
			"start": {"quarter": 2, "clock": 180, "you": 0, "opp": 0, "ball": "you", "yard": 20, "down": 1, "to_go": 10},
			"goal": "tds:2", "coins": 500, "pack": "receiver", "opponent": "MIA"},
	{"id": "hail_mary", "title": "HAIL MARY", "desc": "DOWN 5, 0:05 LEFT, BALL AT MIDFIELD. ONE PLAY. SCORE.",
			"start": {"quarter": 4, "clock": 5, "you": 16, "opp": 21, "ball": "you", "yard": 55, "down": 1, "to_go": 10},
			"goal": "td", "coins": 400, "pack": "qb", "opponent": "GB"},
	{"id": "red_zone_regular", "title": "RED ZONE REGULAR", "desc": "1ST & 10 AT THEIR 20. FINISH THE DRIVE WITH A TD.",
			"start": {"quarter": 1, "clock": 900, "you": 0, "opp": 0, "ball": "you", "yard": 80, "down": 1, "to_go": 10},
			"goal": "td", "coins": 250, "pack": "", "opponent": "PIT"},
	{"id": "ice_the_kicker", "title": "WALK-OFF KICK", "desc": "TIED, 0:04 LEFT, 4TH & 5 AT THEIR 30. PUT POINTS UP.",
			"start": {"quarter": 4, "clock": 4, "you": 20, "opp": 20, "ball": "you", "yard": 70, "down": 4, "to_go": 5},
			"goal": "score", "coins": 300, "pack": "", "opponent": "DAL"},
	{"id": "shutdown", "title": "SHUTDOWN", "desc": "UP 7 WITH 4:00 LEFT. THEY START AT THEIR 20. NO POINTS.",
			"start": {"quarter": 4, "clock": 240, "you": 24, "opp": 17, "ball": "opp", "yard": 20, "down": 1, "to_go": 10},
			"goal": "stop", "coins": 400, "pack": "defense", "opponent": "LAR"},
	{"id": "pick_party", "title": "PICK PARTY", "desc": "Q4, 8:00 LEFT. GET 2 INTERCEPTIONS BEFORE THE END.",
			"start": {"quarter": 4, "clock": 480, "you": 14, "opp": 14, "ball": "opp", "yard": 25, "down": 1, "to_go": 10},
			"goal": "ints:2", "coins": 600, "pack": "defense", "opponent": "HOU"},
]

const DAILY_TEMPLATES := [
	["DAILY: CLUTCH DRIVE", "win", "you", 4, -3],
	["DAILY: STOP THEM", "stop", "opp", 4, 3],
	["DAILY: SCORING DRIVE", "td", "you", 2, 0],
	["DAILY: HOLD ON", "win", "opp", 4, 5],
]


static func daily_seed(unix_time: float) -> int:
	var d := Time.get_date_dict_from_unix_time(int(unix_time))
	return int(d["year"]) * 10000 + int(d["month"]) * 100 + int(d["day"])


## The daily challenge for a date seed (e.g. 20260928). Same seed, same challenge.
static func daily(seed_value: int, teams: Array) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var t: Array = DAILY_TEMPLATES[rng.randi() % DAILY_TEMPLATES.size()]
	var sorted := teams.duplicate()
	sorted.sort()
	var clock := rng.randi_range(60, 300)
	var diff: int = t[4]
	var base := rng.randi_range(7, 24)
	var yard := rng.randi_range(20, 45) if t[2] == "you" else rng.randi_range(25, 60)
	return {"id": "daily_%d" % seed_value, "daily": true, "title": t[0],
			"desc": "%s WITH %s LEFT." % [_goal_text(t[1]), GameClock.format_time(clock)],
			"start": {"quarter": t[3], "clock": clock, "you": base + diff, "opp": base, "ball": t[2], "yard": yard,
					"down": 1, "to_go": 10},
			"goal": t[1], "coins": 300, "pack": "silver" if rng.randf() < 0.3 else "bronze",
			"opponent": sorted[rng.randi() % sorted.size()]}


static func _goal_text(goal: String) -> String:
	match goal:
		"win":
			return "WIN THE GAME"
		"td":
			return "SCORE A TOUCHDOWN"
		"stop":
			return "KEEP THEM OFF THE BOARD"
	return goal.to_upper()


static func find(id: String, seed_value := 0) -> Dictionary:
	for c in LIST:
		if c["id"] == id:
			return c
	if id.begins_with("daily_"):
		return daily(int(id.get_slice("_", 1)) if seed_value == 0 else seed_value, TeamData.load_all().keys())
	return {}


## Goal check. `ev` = {"you_tds", "you_pts", "opp_pts", "ints", "possession_lost",
## "their_drive_over", "period_over", "game_over", "you_lead"} — progress since the start.
## Returns 1 success, -1 failure, 0 undecided.
static func evaluate(goal: String, ev: Dictionary) -> int:
	var kind := goal.get_slice(":", 0)
	var n := int(goal.get_slice(":", 1)) if ":" in goal else 1
	match kind:
		"win":
			if ev.get("game_over", false):
				return 1 if ev.get("you_lead", false) else -1
		"td":
			if int(ev.get("you_tds", 0)) >= 1:
				return 1
			if ev.get("possession_lost", false) or ev.get("period_over", false) or ev.get("game_over", false):
				return -1
		"score":
			if int(ev.get("you_pts", 0)) > 0:
				return 1
			if ev.get("possession_lost", false) or ev.get("period_over", false) or ev.get("game_over", false):
				return -1
		"stop":
			if int(ev.get("opp_pts", 0)) > 0:
				return -1
			if ev.get("their_drive_over", false) or ev.get("period_over", false) or ev.get("game_over", false):
				return 1
		"tds":
			if int(ev.get("you_tds", 0)) >= n:
				return 1
			if ev.get("period_over", false) or ev.get("game_over", false):
				return -1
		"ints":
			if int(ev.get("ints", 0)) >= n:
				return 1
			if ev.get("game_over", false):
				return -1
	return 0
