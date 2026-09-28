class_name Collection
extends RefCounted
## Collection/lineup logic over a Profile and the card catalog (RosterDB). Pure.

const STARTER_SILVER := 5


## Starter cards for a franchise: its real players' top 5 as Silver, everyone else Bronze.
static func starter_card_ids(db: RosterDB, abbr: String) -> Array[String]:
	var roster: Array = db.by_team.get(abbr, []).duplicate()
	roster.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.ovr > b.ovr)
	var out: Array[String] = []
	var silver := 0
	for p: PlayerData in roster:
		var tier := CardRules.Tier.BRONZE
		if not p.generated and silver < STARTER_SILVER:
			tier = CardRules.Tier.SILVER
			silver += 1
		out.append(CardRules.card_id(p.id, tier))
	return out


static func grant_starters(profile: Profile, db: RosterDB, abbr: String, unix_time := 0) -> void:
	profile.franchise_team = abbr
	for id in starter_card_ids(db, abbr):
		profile.add_card(id, unix_time)
	auto_lineup(profile, db)


## Effective OVR of an owned card (card OVR + training boosts).
static func card_ovr(db: RosterDB, entry: Dictionary) -> int:
	var c: CardDef = db.cards.get(entry["def"])
	return 0 if c == null else mini(c.ovr + int(entry.get("boost", 0)), 99)


static func auto_lineup(profile: Profile, db: RosterDB) -> void:
	var cands := []
	for e in profile.cards:
		var c: CardDef = db.cards.get(e["def"])
		if c == null:
			continue   # retired player (no longer in the CSV)
		var p: PlayerData = db.players.get(c.player_id)
		cands.append({"key": int(e["uid"]), "pos": p.pos, "ovr": card_ovr(db, e), "player": c.player_id})
	var best := TeamRating.auto_best(cands)
	profile.lineup = {}
	for slot in best:
		profile.lineup[slot] = best[slot]["key"]


## slot -> {name, jersey, attrs, ovr, pos, uid} for the profile's lineup.
static func lineup_entries(profile: Profile, db: RosterDB) -> Dictionary:
	var out := {}
	for slot in profile.lineup:
		var e := profile.find(int(profile.lineup[slot]))
		if e.is_empty():
			continue
		var c: CardDef = db.cards.get(e["def"])
		if c == null:
			continue
		var p: PlayerData = db.players.get(c.player_id)
		var boost := int(e.get("boost", 0))
		out[slot] = {"name": p.short_name(), "jersey": p.jersey, "pos": p.pos, "uid": int(e["uid"]),
				"attrs": CardRules.card_attrs(p.attrs, p.ovr, c.ovr, boost), "ovr": mini(c.ovr + boost, 99)}
	return out


static func team_ovr(profile: Profile, db: RosterDB) -> int:
	return TeamRating.team_ovr(lineup_entries(profile, db))


## Franchise Chemistry (PLAN.md §5): +0.5 OVR per starter who really plays for your
## franchise, max +3.
static func chemistry(profile: Profile, db: RosterDB) -> float:
	var n := 0
	for slot in profile.lineup:
		var e := profile.find(int(profile.lineup[slot]))
		var c: CardDef = db.cards.get(e.get("def", ""))
		if c != null and db.players[c.player_id].team == profile.franchise_team:
			n += 1
	return minf(n * 0.5, 3.0)
