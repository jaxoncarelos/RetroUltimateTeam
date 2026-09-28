class_name CardRules
extends RefCounted
## Card tiers (PLAN.md §3): every player can exist as several tier versions. The tier sets
## the card OVR range; the player's real OVR places the card inside it; attributes scale
## with card OVR / real OVR. Pure logic.

enum Tier { BRONZE, SILVER, GOLD, ELITE }

const NAMES := ["BRONZE", "SILVER", "GOLD", "ELITE"]
const KEYS := ["bronze", "silver", "gold", "elite"]
## tier -> [min card ovr, max card ovr, min real ovr to be eligible, quick-sell coins]
const TABLE := [
	[55, 64, 0, 25],
	[65, 74, 0, 100],
	[75, 84, 75, 500],
	[85, 99, 85, 2500],
]
const COLORS := [Color("#b86f3c"), Color("#c2c3c7"), Color("#ffcf40"), Color("#b13cff")]


static func eligible(tier: int, real_ovr: int) -> bool:
	return real_ovr >= int(TABLE[tier][2])


static func card_ovr(tier: int, real_ovr: int) -> int:
	var row: Array = TABLE[tier]
	var u := clampf((real_ovr - 60.0) / 39.0, 0.0, 1.0)
	return int(round(lerpf(float(row[0]), float(row[1]), u)))


static func card_attrs(real_attrs: Dictionary, real_ovr: int, c_ovr: int, boost := 0) -> Dictionary:
	var f := float(c_ovr + boost) / maxf(real_ovr, 1.0)
	var out := {}
	for k in real_attrs:
		out[k] = clampi(int(round(float(real_attrs[k]) * f)), 40, 99)
	return out


static func quicksell(tier: int) -> int:
	return int(TABLE[tier][3])


static func card_id(player_id: String, tier: int) -> String:
	return "%s_%s" % [player_id, KEYS[tier]]


## Splits "mahomes_patrick_gold" into ["mahomes_patrick", Tier.GOLD] (tier -1 if invalid).
static func parse_card_id(card: String) -> Array:
	for t in KEYS.size():
		var suffix: String = "_" + KEYS[t]
		if card.ends_with(suffix):
			return [card.left(card.length() - suffix.length()), t]
	return [card, -1]
