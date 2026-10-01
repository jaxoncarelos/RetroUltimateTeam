class_name CardRules
extends RefCounted
## Card model (PLAN.md §3, reworked after the 2026-09 playtest): a player's base card IS his
## real rating (Madden-like: elite 88-99, good starters 80-87, average 74-79, backups and
## rookies 60-73). The tier is derived from the card OVR, never a cap on who can be what.
## A few top players also have a rare "PRIME" program card (+PRIME_BONUS OVR).
## Young players have potential (pot) and develop with XP (Collection.award_xp).
## Card ids: base = the player id ("mahomes_patrick"); prime = "<player id>_prime";
## X-Factor = "<player id>_xf" (+2 OVR and an AbilityRules ability); Core = "<player id>_core"
## (the common, lower-rated version: core_ovr).
## Pure logic.

enum Tier { BRONZE, SILVER, GOLD, ELITE }

const NAMES := ["BRONZE", "SILVER", "GOLD", "ELITE"]
const KEYS := ["bronze", "silver", "gold", "elite"]
## tier -> [min card ovr, max card ovr, min real ovr (legacy, unused), quick-sell coins]
const TABLE := [
	[40, 69, 0, 10],
	[70, 79, 0, 40],
	[80, 89, 0, 150],
	[90, 99, 0, 750],
]
const COLORS := [Color("#b86f3c"), Color("#c2c3c7"), Color("#ffcf40"), Color("#b13cff")]

## Programs (card versions). "base" = the real player; "prime" = rare chase version.
const PROGRAM_BASE := "base"
const PROGRAM_PRIME := "prime"
const PROGRAM_CHAMP := "champ"       ## Super Bowl trophy: a flat 99 of your franchise star
## X-Factor: +XF_BONUS OVR and an in-game ability (AbilityRules) that powers up mid-drive.
const PROGRAM_XFACTOR := "xf"
## Core: the common version of a good player, rated well below his real OVR (core_ovr), so a
## pack usually gives you a 77 Josh Allen and his real 96 card is a rare pull. The real-rating
## card of a player who has a Core version shows a "PRO" chip.
const PROGRAM_CORE := "core"
const PROGRAM_NAMES := {"base": "", "prime": "PRIME", "champ": "CHAMP", "xf": "X-FACTOR", "core": ""}
const PROGRAM_COLORS := {"base": Color(1, 1, 1, 0), "prime": Color("#29adff"), "champ": Color("#ffb000"),
		"xf": Color("#ff2b6e"), "core": Color(1, 1, 1, 0)}
const CORE_MIN_OVR := 80          ## players at or above this get a Core card
const CORE_LOW := 56              ## core OVR of a real 55 ...
const CORE_HIGH := 81             ## ... and of a real 99 (linear in between)
const XF_MIN_OVR := 74            ## players at or above this get an X-Factor card
const XF_BONUS := 2
const XF_QUICKSELL_MULT := 2
const CHAMP_OVR := 99
const CHAMP_QUICKSELL_MULT := 6
const PRIME_MIN_OVR := 86         ## players at or above this get a Prime card
const PRIME_BONUS := 4
const PRIME_QUICKSELL_MULT := 2

## Development: XP needed for the next +1 OVR is XP_BASE + XP_STEP * levels already gained.
const XP_BASE := 600
const XP_STEP := 150
const POT_CAP := 95
## Age -> potential bonus over the current OVR for young players (older = none).
const POT_BY_AGE := {21: 15, 22: 13, 23: 10, 24: 6, 25: 3}


## Tier of a card OVR (Bronze < 70, Silver 70-79, Gold 80-89, Elite 90+).
static func tier_for_ovr(ovr: int) -> int:
	for t in range(TABLE.size() - 1, -1, -1):
		if ovr >= int(TABLE[t][0]):
			return t
	return Tier.BRONZE


## Legacy (PLAN v1 tier versions): true when a player's real OVR falls in `tier`.
static func eligible(tier: int, real_ovr: int) -> bool:
	return tier_for_ovr(real_ovr) == tier


## Card OVR of a program version of a player with real OVR `real_ovr`.
static func program_ovr(program: String, real_ovr: int) -> int:
	if program == PROGRAM_CHAMP:
		return CHAMP_OVR
	if program == PROGRAM_XFACTOR:
		return mini(real_ovr + XF_BONUS, 99)
	if program == PROGRAM_CORE:
		return core_ovr(real_ovr)
	return mini(real_ovr + (PRIME_BONUS if program == PROGRAM_PRIME else 0), 99)


## Legacy: card OVR "at a tier" = the real OVR (tiers no longer rescale ratings).
static func card_ovr(_tier: int, real_ovr: int) -> int:
	return real_ovr


static func has_prime(real_ovr: int) -> bool:
	return real_ovr >= PRIME_MIN_OVR


static func has_xfactor(real_ovr: int) -> bool:
	return real_ovr >= XF_MIN_OVR


static func has_core(real_ovr: int) -> bool:
	return real_ovr >= CORE_MIN_OVR


## Core card OVR: real 80 -> 70, 85 -> 73, 90 -> 76, 96 -> 79, 99 -> 81.
static func core_ovr(real_ovr: int) -> int:
	return int(round(lerpf(CORE_LOW, CORE_HIGH, clampf((real_ovr - 55.0) / 44.0, 0.0, 1.0))))


## Attributes of a card: real attributes scaled by (card OVR + boost) / real OVR, clamped.
static func card_attrs(real_attrs: Dictionary, real_ovr: int, c_ovr: int, boost := 0) -> Dictionary:
	var f := float(c_ovr + boost) / maxf(real_ovr, 1.0)
	var out := {}
	for k in real_attrs:
		out[k] = clampi(int(round(float(real_attrs[k]) * f)), 40, 99)
	return out


## What a card is worth (coins) by card OVR: log-linear between these anchors, with a big
## jump into the 90s (Elite). Selling pays SELL_SHARE of it, so a normal pack sells back for
## roughly a third of its price (selling must not fund the grind) while a banger is a payday
## (a 99 ≈ 1.5 Elite packs).
const VALUE_CURVE := [[50, 10], [60, 20], [65, 30], [69, 50], [70, 120], [75, 350], [79, 500], [80, 600],
		[85, 1000], [89, 1800], [90, 9000], [92, 18000], [95, 40000], [99, 86000]]
const SELL_SHARE := 0.7
## Program premium on the value (X-Factor ability, Prime).
const PROGRAM_VALUE := {"xf": 1.4, "prime": 1.2}


static func card_value(ovr: int, program := PROGRAM_BASE) -> int:
	var v := float(VALUE_CURVE[0][1])
	if ovr >= int(VALUE_CURVE[-1][0]):
		v = float(VALUE_CURVE[-1][1])
	else:
		for i in range(1, VALUE_CURVE.size()):
			var hi: Array = VALUE_CURVE[i]
			var lo: Array = VALUE_CURVE[i - 1]
			if ovr <= int(hi[0]):
				var u := clampf(float(ovr - int(lo[0])) / float(int(hi[0]) - int(lo[0])), 0.0, 1.0)
				v = exp(lerpf(log(float(lo[1])), log(float(hi[1])), u))
				break
	return int(round(v * float(PROGRAM_VALUE.get(program, 1.0))))


## Coins for quick-selling a card of this OVR/program (SELL_SHARE of its value, rounded to 10).
static func sell_price(ovr: int, program := PROGRAM_BASE) -> int:
	return maxi(10, int(round(card_value(ovr, program) * SELL_SHARE / 10.0)) * 10)


## Legacy flat tier price (old saves / tests); the game sells at sell_price().
static func quicksell(tier: int, program := PROGRAM_BASE) -> int:
	var mult := 1
	match program:
		PROGRAM_PRIME:
			mult = PRIME_QUICKSELL_MULT
		PROGRAM_CHAMP:
			mult = CHAMP_QUICKSELL_MULT
		PROGRAM_XFACTOR:
			mult = XF_QUICKSELL_MULT
	return int(TABLE[tier][3]) * mult


## Card id of a player's base card. The int `_tier` is legacy and ignored (one base card per
## player): card_id("mahomes_patrick", x) == "mahomes_patrick".
static func card_id(player_id: String, _tier := -1) -> String:
	return player_id


static func champ_id(player_id: String) -> String:
	return player_id + "_champ"


static func prime_id(player_id: String) -> String:
	return player_id + "_prime"


static func xf_id(player_id: String) -> String:
	return player_id + "_xf"


static func core_id(player_id: String) -> String:
	return player_id + "_core"


## "mahomes_patrick_prime" -> ["mahomes_patrick", "prime"]; "mahomes_patrick" -> [.., "base"].
static func split_card_id(card: String) -> Array:
	if card.ends_with("_champ"):
		return [card.left(card.length() - 6), PROGRAM_CHAMP]
	if card.ends_with("_prime"):
		return [card.left(card.length() - 6), PROGRAM_PRIME]
	if card.ends_with("_xf"):
		return [card.left(card.length() - 3), PROGRAM_XFACTOR]
	if card.ends_with("_core"):
		return [card.left(card.length() - 5), PROGRAM_CORE]
	return [card, PROGRAM_BASE]


## Legacy tier ids from save v1: "mahomes_patrick_gold" -> ["mahomes_patrick", Tier.GOLD]
## (tier -1 when the id has no tier suffix).
static func parse_card_id(card: String) -> Array:
	for t in KEYS.size():
		var suffix: String = "_" + KEYS[t]
		if card.ends_with(suffix):
			return [card.left(card.length() - suffix.length()), t]
	return [card, -1]


## Default potential: veterans = their OVR; young players grow (21 y/o: +15 … 25: +3).
## age <= 0 (unknown) = no growth.
static func default_pot(ovr: int, age: int) -> int:
	if age <= 0:
		return ovr
	var bonus := 0
	if age <= 21:
		bonus = int(POT_BY_AGE[21])
	elif POT_BY_AGE.has(age):
		bonus = int(POT_BY_AGE[age])
	return clampi(ovr + bonus, ovr, maxi(POT_CAP, ovr))


## XP to gain the next development level when `levels` have been gained already.
static func xp_to_next(levels: int) -> int:
	return XP_BASE + XP_STEP * levels
