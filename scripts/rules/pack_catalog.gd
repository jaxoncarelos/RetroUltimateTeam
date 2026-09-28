class_name PackCatalog
extends RefCounted
## The pack definitions (explicit list: export-safe, no directory scanning).

const STORE := ["bronze", "silver", "gold", "elite"]
const REWARD_ONLY := ["starter", "qb", "receiver", "defense", "franchise"]


static func get_pack(id: String) -> PackDef:
	var path := "res://data/packs/%s.tres" % id
	return load(path) if ResourceLoader.exists(path) else null


static func store_packs() -> Array[PackDef]:
	var out: Array[PackDef] = []
	for id in STORE:
		out.append(get_pack(id))
	return out


## Odds lines for the store UI: [[tier name, percent int], ...] (tiers with 0% skipped).
static func odds_lines(pack: PackDef) -> Array:
	var out := []
	for t in pack.odds.size():
		if pack.odds[t] > 0.0:
			out.append([CardRules.NAMES[t], int(round(pack.odds[t] * 100.0))])
	return out


## "5 CARDS · 1 GOLD+ GUARANTEED · 80+ OVR" style summary.
static func summary(pack: PackDef) -> String:
	var parts: Array[String] = ["%d CARDS" % pack.card_count]
	if pack.guarantee_tier >= 0:
		parts.append("1 %s+ (%d+ OVR) GUARANTEED" % [CardRules.NAMES[pack.guarantee_tier],
				int(CardRules.TABLE[pack.guarantee_tier][0])])
	return " · ".join(parts)
