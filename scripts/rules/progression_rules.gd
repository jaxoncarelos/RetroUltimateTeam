class_name ProgressionRules
extends RefCounted
## Coach level (1..MAX_LEVEL): every match, claimed objective and opened pack grants coach
## XP; every level-up pays coins plus a free pack at levels ending in 3 (Bronze), 5 (Silver)
## and 0 (Gold); Elite only at 50.
## Reward packs go to Profile.pending_packs (opened via EconomyRules.open_pending).
## State: Profile.coach = {"xp": total xp, "level": int}. Pure logic.

const MAX_LEVEL := 50
const LEVEL_XP_BASE := 500      ## xp from level L to L+1 = BASE + STEP * (L - 1)
const LEVEL_XP_STEP := 100

## Match XP
const XP_PLAYED := 150
const XP_WIN := 100
const XP_TIE := 40
const XP_PER_TD := 20
const XP_PER_TAKEAWAY := 15     ## sacks + INTs by your defense
## XP for other actions
const XP_PACK := 25
const XP_OBJECTIVE := {"daily": 50, "weekly": 150, "milestone": 50}


static func xp_to_next(level: int) -> int:
	return LEVEL_XP_BASE + LEVEL_XP_STEP * (level - 1)


## Total XP needed to reach `level` from level 1.
static func xp_for_level(level: int) -> int:
	var total := 0
	for l in range(1, clampi(level, 1, MAX_LEVEL)):
		total += xp_to_next(l)
	return total


static func level_from_xp(xp: int) -> int:
	var level := 1
	var need := 0
	while level < MAX_LEVEL:
		need += xp_to_next(level)
		if xp < need:
			break
		level += 1
	return level


## {"level", "into": xp into this level, "needed": xp for the next, "frac": 0..1, "max": bool}
static func level_progress(xp: int) -> Dictionary:
	var level := level_from_xp(xp)
	if level >= MAX_LEVEL:
		return {"level": level, "into": 0, "needed": 0, "frac": 1.0, "max": true}
	var into := xp - xp_for_level(level)
	var needed := xp_to_next(level)
	return {"level": level, "into": into, "needed": needed, "frac": float(into) / needed, "max": false}


## Reward for reaching level `n`: {"coins": int, "pack": pack id or ""}.
static func rewards_for_level(n: int) -> Dictionary:
	var pack := ""
	if n == MAX_LEVEL:
		pack = "elite"
	elif n % 10 == 0:
		pack = "gold"
	elif n % 5 == 0:
		pack = "silver"
	elif n % 5 == 3:
		pack = "bronze"
	return {"coins": 50 + 10 * n, "pack": pack}


## Coach XP for one match. box: GameState.box_score() keys (tds, def_sacks, def_ints, pf, pa)
## Returns {"total": int, "items": [{"id", "label", "xp"}]}.
static func xp_for_match(box: Dictionary, won: bool) -> Dictionary:
	var items: Array = []
	items.append({"id": "played", "label": "GAME PLAYED", "xp": XP_PLAYED})
	var tie := not won and int(box.get("pf", -1)) == int(box.get("pa", -2))
	if won:
		items.append({"id": "win", "label": "WIN", "xp": XP_WIN})
	elif tie:
		items.append({"id": "tie", "label": "TIE", "xp": XP_TIE})
	var tds := int(box.get("tds", int(box.get("pass_td", 0)) + int(box.get("rush_td", 0))))
	if tds > 0:
		items.append({"id": "tds", "label": "%d TOUCHDOWNS" % tds, "xp": tds * XP_PER_TD})
	var take := int(box.get("def_sacks", 0)) + int(box.get("def_ints", 0))
	if take > 0:
		items.append({"id": "defense", "label": "%d SACKS + INTS" % take, "xp": take * XP_PER_TAKEAWAY})
	var total := 0
	for i in items:
		total += int(i["xp"])
	return {"total": total, "items": items}


## Adds coach XP and pays every level reached. Returns the level-ups:
## [{"level": int, "coins": int, "pack": String}] (coins already added, packs queued).
static func add_xp(profile: Profile, amount: int) -> Array[Dictionary]:
	var ups: Array[Dictionary] = []
	if amount <= 0:
		return ups
	var before := maxi(1, int(profile.coach.get("level", 1)))
	profile.coach["xp"] = int(profile.coach.get("xp", 0)) + amount
	var after := level_from_xp(int(profile.coach["xp"]))
	for lv in range(before + 1, after + 1):
		var r := rewards_for_level(lv)
		profile.coins += int(r["coins"])
		profile.stats["coins_earned"] = int(profile.stats.get("coins_earned", 0)) + int(r["coins"])
		if r["pack"] != "":
			profile.pending_packs.append(r["pack"])
		ups.append({"level": lv, "coins": int(r["coins"]), "pack": r["pack"]})
	profile.coach["level"] = maxi(before, after)
	return ups
