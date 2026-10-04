class_name Collection
extends RefCounted
## Collection/lineup logic over a Profile and the card catalog (RosterDB): the starting
## squad, effective card OVR (base + development + training), player development XP,
## lineups and chemistry. Pure.

const STARTER_SILVER := 5          ## legacy (v1 starter scheme), unused
const STARTER_CAP_MAX := 77        ## franchise players at or below this OVR join the starting squad
const STARTER_CAP_MIN := 64
const STARTER_TARGET_MAX := 70     ## starting team OVR target (lowers the cap until reached)
const FILL_MAX_OVR := 69           ## league-wide fill players (rookies / free-agent types)
const FILL_TARGET_OVR := 66
const STARTER_PACK := "starter"    ## free pack queued for a new career
## Development XP per game: lineup cards; bench cards earn a share.
const XP_PER_GAME := 60
const XP_WIN_BONUS := 30
const XP_BENCH_SHARE := 0.25


## Starter card ids for a franchise: its real players rated <= a cap (backups, rookies,
## role players), ONE franchise star (the team's best player, as his Core card), and low-rated real players
## from other teams for any lineup slot still empty. The cap starts at STARTER_CAP_MAX and
## drops until the squad's team OVR <= STARTER_TARGET_MAX. Never generated players.
static func starter_card_ids(db: RosterDB, abbr: String) -> Array[String]:
	var star := db.franchise_star(abbr)
	var out: Array[String] = []
	for cap in range(STARTER_CAP_MAX, STARTER_CAP_MIN - 1, -1):
		out = _squad(db, abbr, star, cap)
		if squad_ovr(db, out) <= STARTER_TARGET_MAX:
			break
	return out


static func _squad(db: RosterDB, abbr: String, star: PlayerData, cap: int) -> Array[String]:
	var mine: Array[PlayerData] = []
	for p: PlayerData in db.by_team.get(abbr, []):
		if p.generated:
			continue
		if p == star or p.ovr <= cap:
			mine.append(p)
	var have := {}
	for p in mine:
		have[p.pos] = int(have.get(p.pos, 0)) + 1
	var ids: Array[String] = []
	for p in mine:
		# The franchise star starts as his Core card: his real card is something to chase.
		var core := CardRules.core_id(p.id)
		ids.append(core if p == star and db.cards.has(core) else CardRules.card_id(p.id))
	# Fill empty lineup slots with low-rated real players from anywhere else.
	var need := {}
	for slot in TeamRating.ALL_SLOTS:
		var pos := TeamRating.slot_pos(slot)
		need[pos] = int(need.get(pos, 0)) + 1
	for pos in need:
		var missing := int(need[pos]) - int(have.get(pos, 0))
		if missing <= 0:
			continue
		for p in fill_players(db, abbr, pos, missing):
			ids.append(CardRules.card_id(p.id))
	return ids


## `count` low-rated real players at `pos` from teams other than `abbr` (closest to
## FILL_TARGET_OVR, varied per franchise, deterministic).
static func fill_players(db: RosterDB, abbr: String, pos: String, count: int) -> Array[PlayerData]:
	var pool: Array = []
	for pid in db.players:
		var p: PlayerData = db.players[pid]
		if p.generated or p.legend or p.team == abbr or p.pos != pos:
			continue
		pool.append(p)
	pool.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		var ka := _fill_key(a, abbr)
		var kb := _fill_key(b, abbr)
		return ka < kb if ka != kb else a.id < b.id)
	var out: Array[PlayerData] = []
	for i in mini(count, pool.size()):
		out.append(pool[i])
	return out


static func _fill_key(p: PlayerData, abbr: String) -> float:
	var over := maxi(0, p.ovr - FILL_MAX_OVR) * 10.0
	return over + absf(p.ovr - FILL_TARGET_OVR) + float(hash(abbr + p.id) % 1000) / 400.0


## Team OVR of the best lineup a set of card ids can field.
static func squad_ovr(db: RosterDB, ids: Array[String]) -> int:
	var cands := []
	for id in ids:
		var c: CardDef = db.cards.get(id)
		if c != null:
			cands.append({"key": id, "pos": db.players[c.player_id].pos, "ovr": c.ovr, "player": c.player_id})
	var best := TeamRating.auto_best(cands)
	return TeamRating.team_ovr(best)


## Sets the franchise, grants the starting squad, builds the lineup and queues the free
## starter pack (Profile.pending_packs) for the first session.
static func grant_starters(profile: Profile, db: RosterDB, abbr: String, unix_time := 0) -> void:
	profile.franchise_team = abbr
	for id in starter_card_ids(db, abbr):
		profile.add_card(id, unix_time)
	auto_lineup(profile, db)
	if STARTER_PACK not in profile.pending_packs:
		profile.pending_packs.append(STARTER_PACK)


## Effective OVR of an owned card: card OVR + development + training boosts (max 99).
static func card_ovr(db: RosterDB, entry: Dictionary) -> int:
	var c: CardDef = db.cards.get(entry["def"])
	return 0 if c == null else mini(c.ovr + int(entry.get("dev", 0)) + int(entry.get("boost", 0)), 99)


## Tier of an owned card from its effective OVR (a developed rookie can turn Gold).
static func card_tier(db: RosterDB, entry: Dictionary) -> int:
	return CardRules.tier_for_ovr(card_ovr(db, entry))


## Development ceiling of an owned card (its potential + training boosts).
static func card_pot(db: RosterDB, entry: Dictionary) -> int:
	var c: CardDef = db.cards.get(entry["def"])
	return 0 if c == null else mini(c.pot + int(entry.get("boost", 0)), 99)


## OVR levels an owned card can still gain from XP.
static func dev_room(db: RosterDB, entry: Dictionary) -> int:
	var c: CardDef = db.cards.get(entry["def"])
	return 0 if c == null else maxi(0, c.pot - c.ovr - int(entry.get("dev", 0)))


## Everything the UI shows about an owned card:
## {uid, def, player_id, name, short, pos, team, jersey, age, ovr, base_ovr, tier, program,
##  ability, pot, dev, boost, xp, xp_next (0 = maxed), locked, in_lineup, prospect, retired,
##  legend, era ("" unless a legend)}
static func card_info(profile: Profile, db: RosterDB, entry: Dictionary) -> Dictionary:
	var c: CardDef = db.cards.get(entry.get("def", ""))
	var uid := int(entry.get("uid", 0))
	if c == null:
		return {"uid": uid, "def": entry.get("def", ""), "retired": true, "name": "RETIRED", "ovr": 0, "tier": 0}
	var p: PlayerData = db.players[c.player_id]
	var dev := int(entry.get("dev", 0))
	var room := dev_room(db, entry)
	return {"uid": uid, "def": c.id, "player_id": p.id, "name": p.name, "short": p.short_name(), "pos": p.pos,
			"team": p.team, "jersey": p.jersey, "age": p.age, "ovr": card_ovr(db, entry), "base_ovr": c.ovr,
			"tier": card_tier(db, entry), "program": c.program, "ability": c.ability, "pot": card_pot(db, entry), "dev": dev,
			"boost": int(entry.get("boost", 0)), "xp": int(entry.get("xp", 0)),
			"xp_next": CardRules.xp_to_next(dev) if room > 0 else 0, "locked": bool(entry.get("locked", false)),
			"in_lineup": profile.in_lineup(uid), "prospect": room > 0, "retired": false, "legend": c.is_legend(),
			"era": p.era}


## Adds development XP to one owned card; levels it up (+1 OVR each) while XP allows and
## it has room below its potential. Returns levels gained.
static func add_card_xp(db: RosterDB, entry: Dictionary, amount: int) -> int:
	if amount <= 0 or dev_room(db, entry) <= 0:
		return 0
	entry["xp"] = int(entry.get("xp", 0)) + amount
	var gained := 0
	while dev_room(db, entry) > 0:
		var need := CardRules.xp_to_next(int(entry.get("dev", 0)))
		if int(entry["xp"]) < need:
			break
		entry["xp"] = int(entry["xp"]) - need
		entry["dev"] = int(entry.get("dev", 0)) + 1
		gained += 1
	if dev_room(db, entry) <= 0:
		entry["xp"] = 0
	return gained


## Postgame development: every lineup card gets XP_PER_GAME (+XP_WIN_BONUS on a win), bench
## cards XP_BENCH_SHARE of it. Returns level-ups [{uid, name, from, to}].
static func award_xp(profile: Profile, db: RosterDB, won: bool) -> Array[Dictionary]:
	var ups: Array[Dictionary] = []
	var xp := int(round((XP_PER_GAME + (XP_WIN_BONUS if won else 0)) * CoachPerks.card_xp_mult(profile)))
	for e in profile.cards:
		var amount := xp if profile.in_lineup(int(e["uid"])) else int(xp * XP_BENCH_SHARE)
		var before := card_ovr(db, e)
		var gained := add_card_xp(db, e, amount)
		if gained > 0:
			var c: CardDef = db.cards[e["def"]]
			ups.append({"uid": int(e["uid"]), "name": db.players[c.player_id].short_name(), "from": before,
					"to": card_ovr(db, e)})
	return ups


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


## slot -> {name, jersey, attrs, ovr, pos, uid, look, ability} for the profile's lineup (look =
## PlayerData.look, used for the field sprite's skin tone/visor).
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
		var extra := int(e.get("boost", 0)) + int(e.get("dev", 0))
		var ovr := card_ovr(db, e)
		out[slot] = {"name": p.short_name(), "jersey": p.jersey, "pos": p.pos, "uid": int(e["uid"]),
				"attrs": CardRules.card_attrs(p.attrs, p.ovr, c.ovr, ovr - c.ovr if extra > 0 else 0), "ovr": ovr,
				"look": p.look, "ability": c.ability}
	return out


static func team_ovr(profile: Profile, db: RosterDB) -> int:
	return TeamRating.team_ovr(lineup_entries(profile, db))


## Franchise Chemistry (PLAN.md §5): +0.5 OVR per starter who really plays for your
## franchise, max +3. Legends never count (their team is only their iconic franchise).
static func chemistry(profile: Profile, db: RosterDB) -> float:
	var n := 0
	for slot in profile.lineup:
		var e := profile.find(int(profile.lineup[slot]))
		var c: CardDef = db.cards.get(e.get("def", ""))
		if c != null and not c.is_legend() and db.players[c.player_id].team == profile.franchise_team:
			n += 1
	return minf(n * 0.5, 3.0)
