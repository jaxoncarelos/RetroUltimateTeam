class_name PackCatalog
extends RefCounted
## The pack definitions (explicit list: export-safe, no directory scanning).

const STORE := ["bronze", "silver", "gold", "elite"]
const REWARD_ONLY := ["qb", "receiver", "defense", "franchise"]


static func get_pack(id: String) -> PackDef:
	var path := "res://data/packs/%s.tres" % id
	return load(path) if ResourceLoader.exists(path) else null


static func store_packs() -> Array[PackDef]:
	var out: Array[PackDef] = []
	for id in STORE:
		out.append(get_pack(id))
	return out
