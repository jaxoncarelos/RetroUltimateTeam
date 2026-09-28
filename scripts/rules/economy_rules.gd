class_name EconomyRules
extends RefCounted
## Coins, packs, quick-sell, duplicate training, sets and match rewards (PLAN.md §5).
## Pure: every function takes the Profile / RosterDB / rng it needs.

const MAX_BOOST := 3
const WIN_COINS := 400
const LOSS_COINS := 160
const TIE_COINS := 240
const TD_BONUS := 20
const TAKEAWAY_BONUS := 25
const SHUTOUT_BONUS := 50
const COMEBACK_BONUS := 100
const DAILY_WIN_BONUS := 200
const WEAK_POS_WEIGHT := 1.6   ## positions below your lineup average are this much likelier

## Sets: trade cards in for rewards. needs = {tier, count, franchise_only}; reward = pack id
## or "franchise_elite" (an Elite card of one of your franchise's real players).
const SETS := [
	{"id": "bronze_to_silver", "name": "10 BRONZE -> SILVER PACK", "tier": 0, "count": 10, "franchise_only": false,
			"reward": "silver"},
	{"id": "silver_to_gold", "name": "5 SILVER -> GOLD PACK", "tier": 1, "count": 5, "franchise_only": false,
			"reward": "gold"},
	{"id": "franchise_elite", "name": "3 FRANCHISE GOLDS -> ELITE STAR", "tier": 2, "count": 3, "franchise_only": true,
			"reward": "franchise_elite"},
]


## One card's tier from the pack odds.
static func roll_tier(odds: PackedFloat32Array, rng: RandomNumberGenerator) -> int:
	var r := rng.randf()
	for t in odds.size():
		r -= odds[t]
		if r < 0.0:
			return t
	# Rounding: fall back to the best tier with non-zero odds.
	for t in range(odds.size() - 1, -1, -1):
		if odds[t] > 0.0:
			return t
	return 0


## Tiers for a whole pack, with the guarantee applied (the best card is upgraded if needed).
static func roll_pack_tiers(pack: PackDef, rng: RandomNumberGenerator) -> Array[int]:
	var tiers: Array[int] = []
	for i in pack.card_count:
		tiers.append(roll_tier(pack.odds, rng))
	if pack.guarantee_tier >= 0 and tiers.max() < pack.guarantee_tier:
		tiers[tiers.find(tiers.max())] = pack.guarantee_tier
	tiers.sort()   # reveal in ascending rarity
	return tiers


## Positions where your lineup is below its own average (packs lean toward them).
static func weak_positions(profile: Profile, db: RosterDB) -> Array[String]:
	var entries := Collection.lineup_entries(profile, db)
	if entries.is_empty():
		return []
	var sum := 0
	for s in entries:
		sum += int(entries[s]["ovr"])
	var avg := float(sum) / entries.size()
	var out: Array[String] = []
	for s in entries:
		var pos := TeamRating.slot_pos(s)
		if int(entries[s]["ovr"]) < avg - 2 and pos not in out:
			out.append(pos)
	return out


## Card ids a pack contains (not yet added to the profile).
static func open_pack(pack: PackDef, profile: Profile, db: RosterDB, rng: RandomNumberGenerator) -> Array[String]:
	var weak := weak_positions(profile, db)
	var out: Array[String] = []
	for tier in roll_pack_tiers(pack, rng):
		var id := pick_card(tier, pack, profile, db, rng, weak)
		if id == "":
			id = pick_card(tier - 1 if tier > 0 else 0, pack, profile, db, rng, weak)
		if id != "":
			out.append(id)
	return out


## A random real player's card at `tier` that fits the pack's filters.
static func pick_card(tier: int, pack: PackDef, profile: Profile, db: RosterDB, rng: RandomNumberGenerator,
		weak: Array[String] = []) -> String:
	var ids: Array[String] = []
	var weights := PackedFloat32Array()
	var team := profile.franchise_team if pack.team == "FRANCHISE" else pack.team
	for pid in db.players:
		var p: PlayerData = db.players[pid]
		if p.generated or not CardRules.eligible(tier, p.ovr):
			continue
		if not pack.positions.is_empty() and p.pos not in pack.positions:
			continue
		if team != "" and p.team != team:
			continue
		ids.append(CardRules.card_id(p.id, tier))
		weights.append(WEAK_POS_WEIGHT if p.pos in weak else 1.0)
	if ids.is_empty():
		return ""
	return ids[AIPlayCaller.weighted_index(weights, rng)]


static func can_buy(profile: Profile, pack: PackDef) -> bool:
	return pack.price > 0 and profile.coins >= pack.price


## Buys and opens a pack: coins are spent and cards added in one step (so quitting midway
## never loses coins or duplicates cards). Returns the new uids ([] if unaffordable).
static func buy_and_open(profile: Profile, pack: PackDef, db: RosterDB, rng: RandomNumberGenerator,
		unix_time := 0) -> Array[int]:
	if not can_buy(profile, pack):
		return []
	profile.coins -= pack.price
	return grant_pack(profile, pack, db, rng, unix_time)


static func grant_pack(profile: Profile, pack: PackDef, db: RosterDB, rng: RandomNumberGenerator,
		unix_time := 0) -> Array[int]:
	var uids: Array[int] = []
	for id in open_pack(pack, profile, db, rng):
		uids.append(profile.add_card(id, unix_time))
	profile.stats["packs_opened"] += 1
	return uids


static func quicksell_value(db: RosterDB, entry: Dictionary) -> int:
	var c: CardDef = db.cards.get(entry.get("def", ""))
	return 10 if c == null else c.quicksell


## Sells an unlocked card that isn't in the lineup. Returns coins gained (0 = refused).
static func quicksell(profile: Profile, db: RosterDB, uid: int) -> int:
	var e := profile.find(uid)
	if e.is_empty() or e["locked"] or profile.in_lineup(uid):
		return 0
	var value := quicksell_value(db, e)
	profile.remove(uid)
	profile.coins += value
	return value


## Feeds a duplicate of the same player into a card for +1 OVR (max +3). Returns success.
static func train(profile: Profile, db: RosterDB, target_uid: int, fodder_uid: int) -> bool:
	if target_uid == fodder_uid:
		return false
	var t := profile.find(target_uid)
	var f := profile.find(fodder_uid)
	if t.is_empty() or f.is_empty() or f["locked"] or profile.in_lineup(fodder_uid):
		return false
	var tc: CardDef = db.cards.get(t["def"])
	var fc: CardDef = db.cards.get(f["def"])
	if tc == null or fc == null or tc.player_id != fc.player_id or int(t["boost"]) >= MAX_BOOST:
		return false
	t["boost"] = int(t["boost"]) + 1
	profile.remove(fodder_uid)
	return true


## Cards that could go into a set (right tier, unlocked, not starting).
static func set_candidates(profile: Profile, db: RosterDB, set_def: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for e in profile.cards:
		var c: CardDef = db.cards.get(e["def"])
		if c == null or c.tier != int(set_def["tier"]) or e["locked"] or profile.in_lineup(int(e["uid"])):
			continue
		if set_def["franchise_only"] and db.players[c.player_id].team != profile.franchise_team:
			continue
		out.append(int(e["uid"]))
	return out


## Completes a set with the first eligible cards. Returns the reward id ("" = not enough cards).
static func complete_set(profile: Profile, db: RosterDB, set_def: Dictionary) -> String:
	var cands := set_candidates(profile, db, set_def)
	if cands.size() < int(set_def["count"]):
		return ""
	for i in int(set_def["count"]):
		profile.remove(cands[i])
	profile.sets_done[set_def["id"]] = int(profile.sets_done.get(set_def["id"], 0)) + 1
	return set_def["reward"]


## Best Elite card of a franchise player you don't own at Elite yet ("" if none).
static func franchise_elite(profile: Profile, db: RosterDB, rng: RandomNumberGenerator) -> String:
	var options: Array[String] = []
	for p: PlayerData in db.by_team.get(profile.franchise_team, []):
		if CardRules.eligible(CardRules.Tier.ELITE, p.ovr):
			options.append(CardRules.card_id(p.id, CardRules.Tier.ELITE))
	if options.is_empty():
		for p: PlayerData in db.by_team.get(profile.franchise_team, []):
			if CardRules.eligible(CardRules.Tier.GOLD, p.ovr):
				options.append(CardRules.card_id(p.id, CardRules.Tier.GOLD))
	return "" if options.is_empty() else options[rng.randi() % options.size()]


## Postgame coins (PLAN.md §5). Returns {"total": int, "lines": [[label, coins], ...]}.
static func match_rewards(r: Dictionary, first_win_today := false) -> Dictionary:
	var lines: Array = []
	var forfeit: bool = r.get("forfeit", false)
	var pf := int(r.get("pf", 0))
	var pa := int(r.get("pa", 0))
	var diff_i := clampi(int(r.get("difficulty", 1)), 0, TeamRating.DIFFICULTY.size() - 1)
	var mult: float = TeamRating.DIFFICULTY[diff_i][2]
	if forfeit:
		return {"total": 0, "lines": [["FORFEIT", 0]]}
	var base := WIN_COINS if pf > pa else (TIE_COINS if pf == pa else LOSS_COINS)
	lines.append(["WIN" if pf > pa else ("TIE" if pf == pa else "LOSS"), int(round(base * mult))])
	if int(r.get("tds", 0)) > 0:
		lines.append(["%d TOUCHDOWNS" % int(r["tds"]), int(r["tds"]) * TD_BONUS])
	var takeaways := int(r.get("def_ints", 0)) + int(r.get("def_sacks", 0))
	if takeaways > 0:
		lines.append(["%d INTS + SACKS" % takeaways, takeaways * TAKEAWAY_BONUS])
	if pa == 0:
		lines.append(["SHUTOUT", SHUTOUT_BONUS])
	if pf > pa and r.get("came_back", false):
		lines.append(["COMEBACK WIN", COMEBACK_BONUS])
	if pf > pa and first_win_today:
		lines.append(["FIRST WIN TODAY", DAILY_WIN_BONUS])
	var total := 0
	for l in lines:
		total += int(l[1])
	return {"total": total, "lines": lines}
