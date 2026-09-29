class_name CoachPerks
extends RefCounted
## Coach skill tree: every coach level (from 2) gives 1 point; each point buys one rank of a
## perk. Perks nudge the match feel (QB time, block-beating window, aim assist, kick zone,
## quicker feet, sure hands) and the economy (coins per game, card XP). State lives in
## Profile.coach["perks"] = {perk id: rank}. Pure logic.

const RESPEC_COST := 300

## id, name, description of one rank, max rank.
const PERKS := [
	{"id": "pocket", "name": "POCKET PRESENCE", "desc": "+0.2 S BEFORE YOUR QB CAN BE SACKED", "max": 4},
	{"id": "breaker", "name": "BLOCK BREAKER", "desc": "LONGER, EASIER SWIPE WINDOW ON BLOCKS", "max": 4},
	{"id": "focus", "name": "LASER FOCUS", "desc": "STRONGER AIM ASSIST ON YOUR THROWS", "max": 4},
	{"id": "hands", "name": "SURE HANDS", "desc": "YOUR RECEIVERS CATCH MORE OF YOUR THROWS", "max": 3},
	{"id": "feet", "name": "QUICK FEET", "desc": "FASTER DEFENDER, SHORTER BURST COOLDOWN", "max": 3},
	{"id": "kicker", "name": "ICE IN THE VEINS", "desc": "+8% WIDER KICK METER ZONE", "max": 3},
	{"id": "payday", "name": "PAYDAY", "desc": "+6% COINS FROM EVERY GAME", "max": 5},
	{"id": "film", "name": "FILM STUDY", "desc": "+10% XP FOR ALL YOUR CARDS", "max": 5},
]


static func find(id: String) -> Dictionary:
	for p in PERKS:
		if p["id"] == id:
			return p
	return {}


static func perks_of(profile: Profile) -> Dictionary:
	return profile.coach.get("perks", {})


static func rank(profile: Profile, id: String) -> int:
	return int(perks_of(profile).get(id, 0))


## One point per coach level above 1.
static func points_earned(profile: Profile) -> int:
	return maxi(0, int(profile.coach.get("level", 1)) - 1)


static func points_spent(profile: Profile) -> int:
	var n := 0
	for id in perks_of(profile):
		n += int(perks_of(profile)[id])
	return n


static func available(profile: Profile) -> int:
	return maxi(0, points_earned(profile) - points_spent(profile))


static func can_buy(profile: Profile, id: String) -> bool:
	var p := find(id)
	return not p.is_empty() and rank(profile, id) < int(p["max"]) and available(profile) >= 1


static func buy(profile: Profile, id: String) -> bool:
	if not can_buy(profile, id):
		return false
	var perks: Dictionary = perks_of(profile).duplicate()
	perks[id] = rank(profile, id) + 1
	profile.coach["perks"] = perks
	return true


## Refund every point for a small coin fee. False when nothing is spent or coins are short.
static func respec(profile: Profile) -> bool:
	if points_spent(profile) == 0 or profile.coins < RESPEC_COST:
		return false
	profile.coins -= RESPEC_COST
	profile.coach["perks"] = {}
	return true


static func has_any(profile: Profile) -> bool:
	return points_spent(profile) > 0


## A copy of the match tuning with the coach's perks applied (the original when there are none).
static func apply_tuning(t: GameplayTuning, profile: Profile) -> GameplayTuning:
	if profile == null or not has_any(profile):
		return t
	var out := t.duplicate() as GameplayTuning
	var pocket := rank(profile, "pocket")
	out.qb_free_time += 0.2 * pocket
	out.qb_evade_time += 0.2 * pocket
	var breaker := rank(profile, "breaker")
	out.duel_window_time += 0.1 * breaker
	out.duel_move_base += 0.03 * breaker
	var focus := rank(profile, "focus")
	out.aim_assist_strength = minf(out.aim_assist_strength + 0.05 * focus, 0.85)
	out.aim_assist_radius += 0.3 * focus
	out.human_catch_bonus += 0.1 * rank(profile, "hands")
	var feet := rank(profile, "feet")
	out.human_speed_mult += 0.012 * feet
	out.burst_cooldown = maxf(1.5, out.burst_cooldown - 0.4 * feet)
	out.meter_zone_base *= 1.0 + 0.08 * rank(profile, "kicker")
	return out


static func coin_mult(profile: Profile) -> float:
	return 1.0 + 0.06 * rank(profile, "payday")


static func card_xp_mult(profile: Profile) -> float:
	return 1.0 + 0.1 * rank(profile, "film")
