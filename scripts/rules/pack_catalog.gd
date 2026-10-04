class_name PackCatalog
extends RefCounted
## The pack definitions (explicit list: export-safe, no directory scanning).

## Store shelves (tabs after FEATURED, which StoreRules rotates): [title, pack ids]. Legends
## are baked into the normal packs (a small chance per card) and the program packs.
const SHELVES := [
	["PACKS", ["bronze", "silver", "gold", "pro", "elite"]],
	["PROGRAMS", ["throwback", "legends", "xfactor", "team", "mystery"]],
	["BUNDLES", ["bundle_bronze", "bundle_silver", "bundle_rookie", "bundle_gold", "bundle_elite", "bundle_legacy"]],
	["DRAFTS", ["draft", "qb", "receiver", "defense", "trenches", "legend_draft"]],
]
## Limited-time program packs (only on the FEATURED shelf, one per week: StoreRules).
const ERA_PACKS := ["era_90s", "era_vintage", "era_2000s"]
const STORE := ["bronze", "silver", "gold", "pro", "elite", "throwback", "legends", "xfactor", "team", "mystery",
		"bundle_bronze", "bundle_silver", "bundle_rookie", "bundle_gold", "bundle_elite", "bundle_legacy",
		"draft", "qb", "receiver", "defense", "trenches", "legend_draft", "era_90s", "era_vintage", "era_2000s"]
const REWARD_ONLY := ["starter", "franchise"]


static func get_pack(id: String) -> PackDef:
	var path := "res://data/packs/%s.tres" % id
	return load(path) if ResourceLoader.exists(path) else null


static func store_packs() -> Array[PackDef]:
	var out: Array[PackDef] = []
	for id in STORE:
		out.append(get_pack(id))
	return out


## Odds lines for the store UI: [[tier name, percent int], ...] (tiers with 0% skipped). A
## legends-only pack lists just "LEGEND 100"; legend chances show as a "LEGEND" line (per
## card, one decimal when under 1%).
static func odds_lines(pack: PackDef) -> Array:
	var out := []
	if not pack.bundle.is_empty():
		return out
	if pack.legend_guarantee >= pack.card_count:
		return [["LEGEND", 100]]
	if pack.legend_chance > 0.0:
		out.append(["LEGEND", snappedf(pack.legend_chance * 100.0, 0.1)])
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
	if not pack.bundle.is_empty():
		return bundle_text(pack)
	var parts: Array[String] = ["KEEP 1 OF %d" % pack.card_count if pack.pick else "%d CARDS" % pack.card_count]
	if pack.legend_guarantee >= pack.card_count:
		parts.append("ALL LEGENDS")
	elif pack.legend_guarantee > 0:
		parts.append("%d LEGEND" % pack.legend_guarantee)
	if pack.xf_guarantee > 0:
		parts.append("%d X-FACTOR" % pack.xf_guarantee)
	if pack.guarantee_tier >= 0:
		parts.append("1 %s+ (%d+ OVR) GUARANTEED" % [CardRules.NAMES[pack.guarantee_tier],
				int(CardRules.TABLE[pack.guarantee_tier][0])])
	return " · ".join(parts)


## "3x SILVER PACK + GOLD PACK" for a bundle.
static func bundle_text(pack: PackDef) -> String:
	var counts := {}
	var order: Array[String] = []
	for id in pack.bundle:
		if not counts.has(id):
			order.append(id)
		counts[id] = int(counts.get(id, 0)) + 1
	var parts: Array[String] = []
	for id in order:
		var p := get_pack(id)
		var n: String = p.display_name if p != null else id.to_upper()
		parts.append(("%dx %s" % [counts[id], n]) if int(counts[id]) > 1 else n)
	return " + ".join(parts)


## What a bundle's packs cost one at a time.
static func bundle_list_price(pack: PackDef) -> int:
	var sum := 0
	for id in pack.bundle:
		var p := get_pack(id)
		if p != null:
			sum += p.price
	return sum
