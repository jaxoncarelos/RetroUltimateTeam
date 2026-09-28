class_name DailyRules
extends RefCounted
## Daily login streak: day 1..7 escalating rewards (day 7 = Gold pack), then the cycle
## repeats; missing a day resets to day 1. Profile.login = {"day": unix day of the last
## check-in, "streak": consecutive days}. Pack rewards go to Profile.pending_packs.
## Days use the device's local midnight (day_of). Pure logic.

## Streak day (1..7) -> {"coins", "pack"}
const REWARDS := [
	{"coins": 150, "pack": ""},
	{"coins": 250, "pack": ""},
	{"coins": 0, "pack": "bronze"},
	{"coins": 400, "pack": ""},
	{"coins": 0, "pack": "silver"},
	{"coins": 600, "pack": ""},
	{"coins": 0, "pack": "gold"},
]


## Local calendar day number of a unix time (-1 = now).
static func day_of(unix_time := -1) -> int:
	var t := unix_time if unix_time >= 0 else int(Time.get_unix_time_from_system())
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return floori(float(t + bias) / 86400.0)


static func reward_for_day(day: int) -> Dictionary:
	return REWARDS[(maxi(day, 1) - 1) % REWARDS.size()].duplicate()


## Checks in for today. Returns {"day": 1..7, "streak": int, "reward": {"coins", "pack"},
## "already_claimed": bool}. The reward is paid (coins added, pack queued) only when not
## already claimed today.
static func check_in(profile: Profile, unix_time := -1) -> Dictionary:
	var today := day_of(unix_time)
	var last := int(profile.login.get("day", 0))
	var streak := int(profile.login.get("streak", 0))
	if last == today and streak > 0:
		var d := (streak - 1) % REWARDS.size() + 1
		return {"day": d, "streak": streak, "reward": reward_for_day(d), "already_claimed": true}
	streak = streak + 1 if last == today - 1 else 1
	profile.login = {"day": today, "streak": streak}
	var day := (streak - 1) % REWARDS.size() + 1
	var r := reward_for_day(day)
	profile.coins += int(r["coins"])
	profile.stats["coins_earned"] = int(profile.stats.get("coins_earned", 0)) + int(r["coins"])
	if r["pack"] != "":
		profile.pending_packs.append(r["pack"])
	return {"day": day, "streak": streak, "reward": r, "already_claimed": false}


## The 7-day calendar for the UI: [{"day", "reward", "claimed": bool, "today": bool}].
## Assumes check_in() already ran today (otherwise "today" is the next day to claim).
static func calendar(profile: Profile, unix_time := -1) -> Array[Dictionary]:
	var today := day_of(unix_time)
	var last := int(profile.login.get("day", 0))
	var streak := int(profile.login.get("streak", 0))
	var checked := last == today and streak > 0
	if not checked and last != today - 1:
		streak = 0   # the streak will reset at the next check-in
	var cur := ((streak - 1) % REWARDS.size() + 1) if checked else (streak % REWARDS.size() + 1)
	var out: Array[Dictionary] = []
	for d in range(1, REWARDS.size() + 1):
		out.append({"day": d, "reward": reward_for_day(d), "claimed": d < cur or (checked and d == cur),
				"today": d == cur})
	return out
