class_name PackCatalog
extends RefCounted
## The pack definitions (explicit list: export-safe, no directory scanning).

## Store shelves (tabs): [title, pack ids].
const SHELVES := [
	["CLASSIC", ["bronze", "silver", "gold", "elite"]],
	["SPECIAL", ["mystery", "draft", "xfactor"]],
	["POSITION", ["qb", "receiver", "defense", "trenches"]],
]
const STORE := ["bronze", "silver", "gold", "elite", "mystery", "draft", "xfactor", "qb", "receiver", "defense",
		"trenches"]
const REWARD_ONLY := ["starter", "franchise"]


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


## Packs on one store shelf.
static func shelf(index: int) -> Array[PackDef]:
	var out: Array[PackDef] = []
	for id in SHELVES[clampi(index, 0, SHELVES.size() - 1)][1]:
		var p := get_pack(id)
		if p != null:
			out.append(p)
	return out


## "5 CARDS · 1 GOLD+ GUARANTEED · 80+ OVR" style summary.
static func summary(pack: PackDef) -> String:
	if not pack.mystery.is_empty():
		return "SECRETLY ONE OF: " + ", ".join(PackedStringArray(Array(pack.mystery).map(
				func(id: String) -> String: return id.to_upper())))
	var parts: Array[String] = ["KEEP 1 OF %d" % pack.card_count if pack.pick else "%d CARDS" % pack.card_count]
	if pack.xf_guarantee > 0:
		parts.append("%d X-FACTOR" % pack.xf_guarantee)
	if pack.guarantee_tier >= 0:
		parts.append("1 %s+ (%d+ OVR) GUARANTEED" % [CardRules.NAMES[pack.guarantee_tier],
				int(CardRules.TABLE[pack.guarantee_tier][0])])
	return " · ".join(parts)
