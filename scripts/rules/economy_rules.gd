class_name EconomyRules
extends RefCounted
## Coins, packs, quick-sell, duplicate training, sets, match rewards and the postgame
## payout (PLAN.md §5, rebalanced for real-rating cards). Pure: every function takes the
## Profile / RosterDB / rng it needs.

const MAX_BOOST := 3
const TRAIN_XP := 500            ## development XP a duplicate gives (on top of the boost)
## Match coins: GAME + WIN_BONUS = WIN_COINS (x difficulty multiplier).
const WIN_COINS := 400
const LOSS_COINS := 160
const TIE_COINS := 240
const GAME_COINS := LOSS_COINS
const SIM_GAME_COINS := 400      ## a fully simulated win pays this (loss/tie scale by LOSS/WIN, TIE/WIN)
const SIM_STAT_MULT := 0.1       ## per-stat bonuses / XP weight for simulated stats
const TD_BONUS := 20
const TAKEAWAY_BONUS := 25
const SHUTOUT_BONUS := 50
const COMEBACK_BONUS := 100
const DAILY_WIN_BONUS := 200
const STREAK_STEP := 0.10        ## +10% of the base per consecutive win after the first
const STREAK_CAP := 0.50
const FIRST_WINS_BONUS := [300, 200, 150]   ## career wins 1, 2, 3
const WEAK_POS_WEIGHT := 1.25    ## positions below your lineup average are this much likelier
const PRIME_WEIGHT := 0.05       ## a Prime card vs a base card of the same tier
const IN_TIER_FALLOFF := 0.12    ## higher OVR inside a tier is rarer: weight 1/(1 + k*(ovr - tier min))
## Elite tier: every OVR point above 90 multiplies the weight by this (a 95 is ~4x rarer
## than a 90, a 99 ~13x), so a 99 is the pull of a career.
const ELITE_FALLOFF := 0.75

## Sets: trade cards in for rewards. needs = {tier, count, franchise_only}; reward = pack id
## or "franchise_elite" (a star card of one of your franchise's real players).
const SETS := [
	{"id": "bronze_to_silver", "name": "10 BRONZE -> SILVER PACK", "tier": 0, "count": 10, "franchise_only": false,
			"reward": "silver"},
	{"id": "silver_to_gold", "name": "5 SILVER -> GOLD PACK", "tier": 1, "count": 5, "franchise_only": false,
			"reward": "gold"},
	{"id": "franchise_elite", "name": "3 FRANCHISE GOLDS -> FRANCHISE STAR", "tier": 2, "count": 3,
			"franchise_only": true, "reward": "franchise_elite"},
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


## Card ids a pack contains (not yet added to the profile). The best `xf_guarantee` cards
## are X-Factor versions when the pack's filters allow one.
static func open_pack(pack: PackDef, profile: Profile, db: RosterDB, rng: RandomNumberGenerator) -> Array[String]:
	var weak := weak_positions(profile, db)
	var out: Array[String] = []
	var tiers := roll_pack_tiers(pack, rng)
	for i in tiers.size():
		var tier := tiers[i]
		var xf_only := i >= tiers.size() - pack.xf_guarantee
		var id := ""
		# Filtered packs (a team's roster) may lack a tier: try lower tiers, then higher.
		for want_xf in ([true, false] if xf_only else [false]):
			for t in [tier, tier - 1, tier - 2, tier - 3, tier + 1, tier + 2]:
				if t < 0 or t >= CardRules.TABLE.size():
					continue
				id = pick_card(t, pack, profile, db, rng, weak, want_xf)
				if id != "":
					break
			if id != "":
				break
		if id != "":
			out.append(id)
	return out


## Mystery pack: which pack it really is (by mystery_weights). Other packs: itself.
static func resolve_mystery(pack: PackDef, rng: RandomNumberGenerator) -> PackDef:
	if pack.mystery.is_empty():
		return pack
	var i := AIPlayCaller.weighted_index(pack.mystery_weights, rng)
	var real := PackCatalog.get_pack(pack.mystery[clampi(i, 0, pack.mystery.size() - 1)])
	return real if real != null else pack


## A random real player's card of `tier` (derived from card OVR) that fits the pack's
## filters. Prime cards are rare; higher OVRs inside a tier are rarer; weak positions likelier.
static func pick_card(tier: int, pack: PackDef, profile: Profile, db: RosterDB, rng: RandomNumberGenerator,
		weak: Array[String] = [], xf_only := false) -> String:
	var ids: Array[String] = []
	var weights := PackedFloat32Array()
	var team := profile.franchise_team if pack.team == "FRANCHISE" else pack.team
	var tier_min := int(CardRules.TABLE[tier][0])
	for cid in db.card_ids_of_tier(tier):
		var c: CardDef = db.cards[cid]
		var p: PlayerData = db.players[c.player_id]
		if not pack.positions.is_empty() and p.pos not in pack.positions:
			continue
		if team != "" and p.team != team:
			continue
		if xf_only and not c.is_xfactor():
			continue
		var w := 1.0 / (1.0 + IN_TIER_FALLOFF * maxi(0, c.ovr - maxi(tier_min, 60)))
		if tier >= CardRules.Tier.ELITE:
			w = pow(ELITE_FALLOFF, c.ovr - tier_min)
		if c.is_prime():
			w *= PRIME_WEIGHT
		elif c.is_xfactor():
			w *= pack.xf_weight
		if p.pos in weak:
			w *= WEAK_POS_WEIGHT
		ids.append(cid)
		weights.append(w)
	if ids.is_empty():
		return ""
	return ids[AIPlayCaller.weighted_index(weights, rng)]


static func can_buy(profile: Profile, pack: PackDef) -> bool:
	return pack.price > 0 and profile.coins >= pack.price


## Buys and opens a pack: coins are spent and cards added in one step (so quitting midway
## never loses coins or duplicates cards). Returns the new uids ([] if unaffordable).
## Mystery packs open as the pack they turn out to be; use buy() to learn which, and for
## draft packs (which add nothing until you pick).
static func buy_and_open(profile: Profile, pack: PackDef, db: RosterDB, rng: RandomNumberGenerator,
		unix_time := 0) -> Array[int]:
	var r := buy(profile, pack, db, rng, unix_time)
	return r.get("uids", [] as Array[int])


## Buys any store pack in one saved step. Returns {} if unaffordable, else
## {"pack": PackDef actually opened (a mystery pack's reveal), "mystery": bool,
##  "uids": Array[int] (new cards), "draft": bool (options are waiting in
##  Profile.pending_pick: choose with pick_draft)}.
static func buy(profile: Profile, pack: PackDef, db: RosterDB, rng: RandomNumberGenerator,
		unix_time := 0) -> Dictionary:
	if not can_buy(profile, pack) or has_pending_draft(profile):
		return {}
	profile.coins -= pack.price
	if pack.pick:
		start_draft(profile, pack, db, rng)
		return {"pack": pack, "mystery": false, "uids": [] as Array[int], "draft": true}
	var real := resolve_mystery(pack, rng)
	return {"pack": real, "mystery": real != pack, "uids": grant_pack(profile, real, db, rng, unix_time),
			"draft": false}


## Draft pack: rolls the options (saved in Profile.pending_pick so quitting keeps them).
static func start_draft(profile: Profile, pack: PackDef, db: RosterDB, rng: RandomNumberGenerator) -> Array[String]:
	var ids := open_pack(pack, profile, db, rng)
	profile.pending_pick = {"pack": pack.id, "options": ids}
	return ids


static func has_pending_draft(profile: Profile) -> bool:
	return not profile.pending_pick.is_empty()


## Keeps option `index` of the waiting draft. Returns the new uid (-1 if no draft / bad index).
static func pick_draft(profile: Profile, db: RosterDB, index: int, unix_time := 0) -> int:
	if not has_pending_draft(profile):
		return -1
	var opts: Array = profile.pending_pick.get("options", [])
	if index < 0 or index >= opts.size() or not db.cards.has(str(opts[index])):
		return -1
	var pack := PackCatalog.get_pack(str(profile.pending_pick.get("pack", "")))
	var uid := profile.add_card(str(opts[index]), unix_time)
	profile.pending_pick = {}
	_record_opened(profile, pack, [str(opts[index])] as Array[String], db, unix_time)
	return uid


## Adds a pack's cards to the collection, counts it for objectives and coach XP. A
## draft-style pack (pick one) is queued in Profile.pending_packs instead (returns []) so its
## pick screen opens like any other reward pack.
static func grant_pack(profile: Profile, pack: PackDef, db: RosterDB, rng: RandomNumberGenerator,
		unix_time := 0) -> Array[int]:
	var uids: Array[int] = []
	if pack.pick:
		profile.pending_packs.append(pack.id)
		return uids
	var ids := open_pack(pack, profile, db, rng)
	for id in ids:
		uids.append(profile.add_card(id, unix_time))
	_record_opened(profile, pack, ids, db, unix_time)
	return uids


## Stats, objectives and coach XP for an opened pack.
static func _record_opened(profile: Profile, pack: PackDef, ids: Array[String], db: RosterDB, unix_time: int) -> void:
	var elite := 0
	for id in ids:
		var c: CardDef = db.cards[id]
		if c.tier >= CardRules.Tier.ELITE:
			elite += 1
	profile.stats["packs_opened"] += 1
	var obj_t := unix_time if unix_time > 0 else -1
	ObjectiveRules.record_event(profile, "packs_opened", 1, obj_t)
	if pack != null:
		ObjectiveRules.record_event(profile, "packs_" + pack.id, 1, obj_t)
	if elite > 0:
		ObjectiveRules.record_event(profile, "pulls_elite", elite, obj_t)
	ProgressionRules.add_xp(profile, ProgressionRules.XP_PACK)


## Opens the first reward pack waiting in Profile.pending_packs (starter pack, level-up,
## login streak, objective packs). Returns {"pack": id, "title": display name, "uids": [...],
## "draft": bool} ({} when none are waiting). A draft-style pack (position packs) rolls its
## options into Profile.pending_pick instead ("draft": true, no uids); if a pick is already
## waiting, that one comes first (the queue is left alone).
static func open_pending(profile: Profile, db: RosterDB, rng: RandomNumberGenerator, unix_time := 0) -> Dictionary:
	if has_pending_draft(profile):
		var waiting := str(profile.pending_pick.get("pack", ""))
		var wp := PackCatalog.get_pack(waiting)
		return {"pack": waiting, "title": wp.display_name if wp != null else "DRAFT", "uids": [] as Array[int],
				"draft": true}
	while not profile.pending_packs.is_empty():
		var id := str(profile.pending_packs.pop_front())
		var pack := PackCatalog.get_pack(id)
		if pack == null:
			continue
		if pack.pick:
			start_draft(profile, pack, db, rng)
			return {"pack": id, "title": pack.display_name, "uids": [] as Array[int], "draft": true}
		return {"pack": id, "title": pack.display_name, "uids": grant_pack(profile, pack, db, rng, unix_time),
				"draft": false}
	return {}


static func quicksell_value(db: RosterDB, entry: Dictionary) -> int:
	var c: CardDef = db.cards.get(entry.get("def", ""))
	if c == null:
		return 10
	return c.quicksell   # by the card's own OVR: training/development never inflates the price


## Sells an unlocked card that isn't in the lineup. Returns coins gained (0 = refused).
static func quicksell(profile: Profile, db: RosterDB, uid: int) -> int:
	var e := profile.find(uid)
	if e.is_empty() or e["locked"] or profile.in_lineup(uid):
		return 0
	var value := quicksell_value(db, e)
	profile.remove(uid)
	profile.coins += value
	return value


## Which cards SELL DUPLICATES would quick-sell: for every player you own more than one
## card of, the best copy stays (starting > locked > highest effective OVR > most
## development > oldest uid) and every other unlocked, benched copy goes.
## Returns {"sell_uids": Array[int], "coins": int, "players": int (players trimmed)}.
static func duplicate_plan(profile: Profile, db: RosterDB) -> Dictionary:
	var by_player := {}
	for e in profile.cards:
		var c: CardDef = db.cards.get(e.get("def", ""))
		if c == null:
			continue   # retired: not a duplicate of anything
		if not by_player.has(c.player_id):
			by_player[c.player_id] = []
		by_player[c.player_id].append(e)
	var sell: Array[int] = []
	var coins := 0
	var players := 0
	for pid in by_player:
		var copies: Array = by_player[pid]
		if copies.size() < 2:
			continue
		copies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _keep_first(profile, db, a, b))
		var trimmed := false
		var keep_ovr := Collection.card_ovr(db, copies[0])
		for i in range(1, copies.size()):
			var e: Dictionary = copies[i]
			var uid := int(e["uid"])
			# Never sell starters, locked cards, or a bench copy better than the one starting
			# (that's a lineup upgrade waiting to happen).
			if e.get("locked", false) or profile.in_lineup(uid) or Collection.card_ovr(db, e) > keep_ovr:
				continue
			sell.append(uid)
			coins += quicksell_value(db, e)
			trimmed = true
		if trimmed:
			players += 1
	return {"sell_uids": sell, "coins": coins, "players": players}


## Whether copy `a` is a better keeper than `b` (see duplicate_plan).
static func _keep_first(profile: Profile, db: RosterDB, a: Dictionary, b: Dictionary) -> bool:
	var ka := [1 if profile.in_lineup(int(a["uid"])) else 0, 1 if a.get("locked", false) else 0,
			Collection.card_ovr(db, a), int(a.get("dev", 0)) * 100000 + int(a.get("xp", 0)), -int(a["uid"])]
	var kb := [1 if profile.in_lineup(int(b["uid"])) else 0, 1 if b.get("locked", false) else 0,
			Collection.card_ovr(db, b), int(b.get("dev", 0)) * 100000 + int(b.get("xp", 0)), -int(b["uid"])]
	for i in ka.size():
		if ka[i] != kb[i]:
			return ka[i] > kb[i]
	return false


## Bench cards that would improve a lineup slot (the lineup screen's green "▲+N" badges):
## slot -> {"uid", "ovr", "delta"} for every slot where you own a better card of that
## position whose player isn't already starting elsewhere (a better copy of the slot's own
## player counts). Empty slots count as OVR 0. Effective OVR incl. development.
static func lineup_upgrades(profile: Profile, db: RosterDB) -> Dictionary:
	var starting := {}   # player_id -> slot
	var cur := {}        # slot -> {ovr, player}
	for slot in profile.lineup:
		var e := profile.find(int(profile.lineup[slot]))
		var c: CardDef = db.cards.get(e.get("def", "")) if not e.is_empty() else null
		if c == null:
			continue
		starting[c.player_id] = slot
		cur[slot] = {"ovr": Collection.card_ovr(db, e), "player": c.player_id}
	var out := {}
	for slot in TeamRating.ALL_SLOTS:
		var pos := TeamRating.slot_pos(slot)
		var here: Dictionary = cur.get(slot, {"ovr": 0, "player": ""})
		var best := {}
		for e in profile.cards:
			var uid := int(e["uid"])
			if profile.in_lineup(uid):
				continue
			var c: CardDef = db.cards.get(e.get("def", ""))
			if c == null or db.players[c.player_id].pos != pos:
				continue
			if starting.has(c.player_id) and c.player_id != here["player"]:
				continue
			var o := Collection.card_ovr(db, e)
			if o > int(here["ovr"]) and (best.is_empty() or o > int(best["ovr"])):
				best = {"uid": uid, "ovr": o, "delta": o - int(here["ovr"])}
		if not best.is_empty():
			out[slot] = best
	return out


## Quick-sells every card duplicate_plan() picks. Returns coins gained.
static func sell_duplicates(profile: Profile, db: RosterDB) -> int:
	var total := 0
	for uid: int in duplicate_plan(profile, db)["sell_uids"]:
		total += quicksell(profile, db, uid)
	return total


## Whether `fodder_uid` could train `target_uid` (same player, unlocked, benched, and the
## target still has a boost left or room to develop).
static func can_train(profile: Profile, db: RosterDB, target_uid: int, fodder_uid: int) -> bool:
	if target_uid == fodder_uid:
		return false
	var t := profile.find(target_uid)
	var f := profile.find(fodder_uid)
	if t.is_empty() or f.is_empty() or f["locked"] or profile.in_lineup(fodder_uid):
		return false
	var tc: CardDef = db.cards.get(t["def"])
	var fc: CardDef = db.cards.get(f["def"])
	if tc == null or fc == null or tc.player_id != fc.player_id:
		return false
	return int(t["boost"]) < MAX_BOOST or Collection.dev_room(db, t) > 0


## Feeds a duplicate of the same player into a card: +1 OVR boost (max +3) and TRAIN_XP
## development XP. Returns success.
static func train(profile: Profile, db: RosterDB, target_uid: int, fodder_uid: int) -> bool:
	if not can_train(profile, db, target_uid, fodder_uid):
		return false
	var t := profile.find(target_uid)
	if int(t["boost"]) < MAX_BOOST:
		t["boost"] = int(t["boost"]) + 1
	var lv := Collection.add_card_xp(db, t, TRAIN_XP)
	profile.remove(fodder_uid)
	ObjectiveRules.record_event(profile, "trains")
	if lv > 0:
		ObjectiveRules.record_event(profile, "levelups", lv)
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
	ObjectiveRules.record_event(profile, "sets")
	return set_def["reward"]


## A franchise star card for the franchise set: a random 85+ base card of your franchise
## you don't own yet, else the franchise star's Prime card ("" if none).
static func franchise_elite(profile: Profile, db: RosterDB, rng: RandomNumberGenerator) -> String:
	var owned := {}
	for e in profile.cards:
		owned[str(e["def"])] = true
	var options: Array[String] = []
	for p: PlayerData in db.by_team.get(profile.franchise_team, []):
		if not p.generated and p.ovr >= 85 and not owned.has(CardRules.card_id(p.id)):
			options.append(CardRules.card_id(p.id))
	if options.is_empty():
		var star := db.franchise_star(profile.franchise_team)
		if star != null:
			options.append(CardRules.prime_id(star.id) if db.cards.has(CardRules.prime_id(star.id))
					else CardRules.card_id(star.id))
	return "" if options.is_empty() else options[rng.randi() % options.size()]



## Tester grant (Settings → TESTER COINS) to try new packs on an existing save: claimable
## once per TESTER_ROUND (bump it to hand out another round, e.g. after a pack bug).
const TESTER_COINS := 50000
const TESTER_ROUND := 3


static func can_claim_tester_coins(profile: Profile) -> bool:
	return int(profile.stats.get("tester_coins", 0)) < TESTER_ROUND


## Adds TESTER_COINS once per round. Returns coins added (0 = already claimed).
static func claim_tester_coins(profile: Profile) -> int:
	if not can_claim_tester_coins(profile):
		return 0
	profile.stats["tester_coins"] = TESTER_ROUND
	profile.coins += TESTER_COINS
	return TESTER_COINS


const CHAMP_REPEAT_COINS := 5000

## Super Bowl trophy: a 99-OVR CHAMP card of your franchise's best player, locked so it can't be
## sold by accident. A second title (you already own it) pays coins instead.
## Returns {"card": def id ("" if none), "name": player name, "coins": repeat coins}.
static func champion_reward(profile: Profile, db: RosterDB) -> Dictionary:
	var star := db.franchise_star(profile.franchise_team)
	if star == null or not db.cards.has(CardRules.champ_id(star.id)):
		return {"card": "", "name": "", "coins": 0}
	var id := CardRules.champ_id(star.id)
	for e in profile.cards:
		if str(e["def"]) == id:
			profile.coins += CHAMP_REPEAT_COINS
			return {"card": "", "name": star.short_name(), "coins": CHAMP_REPEAT_COINS}
	var uid := profile.add_card(id)
	profile.find(uid)["locked"] = true
	return {"card": id, "name": star.short_name(), "coins": 0}


## Postgame coins (PLAN.md §5), itemized. r: MatchController.match_result() keys
## (pf, pa, tds, def_ints, def_sacks, difficulty, came_back, forfeit).
## win_streak = consecutive wins including this one; career_wins = wins including this one.
## Returns {"total": int, "lines": [[label, coins], ...], "items": [{"id", "label", "coins"}]}.
## Item ids: base, win, tie, streak, tds, defense, shutout, comeback, daily_win, first_wins.
static func match_rewards(r: Dictionary, first_win_today := false, win_streak := 0, career_wins := 0) -> Dictionary:
	var items: Array = []
	var pf := int(r.get("pf", 0))
	var pa := int(r.get("pa", 0))
	var diff_i := clampi(int(r.get("difficulty", 1)), 0, TeamRating.DIFFICULTY.size() - 1)
	var mult: float = TeamRating.DIFFICULTY[diff_i][2]
	if r.get("forfeit", false):
		return {"total": 0, "lines": [["FORFEIT", 0]], "items": [{"id": "forfeit", "label": "FORFEIT", "coins": 0}]}
	var won := pf > pa
	# Simulated games: result coins scale to SIM_GAME_COINS, stat bonuses are weighted (see sim_counts).
	var k := float(SIM_GAME_COINS) / float(WIN_COINS) if r.get("simulated", false) else 1.0
	var cnt := sim_counts(r)
	var base := int(round(GAME_COINS * mult * k))
	items.append({"id": "base", "label": "GAME PLAYED", "coins": base})
	var result_coins := 0
	if won:
		result_coins = int(round(WIN_COINS * mult * k)) - base
		items.append({"id": "win", "label": "WIN BONUS", "coins": result_coins})
	elif pf == pa:
		result_coins = int(round(TIE_COINS * mult * k)) - base
		items.append({"id": "tie", "label": "TIE BONUS", "coins": result_coins})
	if won and win_streak >= 2:
		var pct := minf(STREAK_STEP * (win_streak - 1), STREAK_CAP)
		items.append({"id": "streak", "label": "WIN STREAK x%d (+%d%%)" % [win_streak, int(round(pct * 100))],
				"coins": int(round((base + result_coins) * pct))})
	if int(r.get("tds", 0)) > 0:
		items.append({"id": "tds", "label": "%d TOUCHDOWNS" % int(r["tds"]), "coins": int(round(float(cnt["tds"]) * TD_BONUS))})
	var takeaways := int(r.get("def_ints", 0)) + int(r.get("def_sacks", 0))
	if takeaways > 0:
		items.append({"id": "defense", "label": "%d INTS + SACKS" % takeaways,
				"coins": int(round(float(cnt["takeaways"]) * TAKEAWAY_BONUS))})
	if pa == 0:
		items.append({"id": "shutout", "label": "SHUTOUT", "coins": int(round(SHUTOUT_BONUS * float(cnt["shutout"])))})
	if won and r.get("came_back", false):
		items.append({"id": "comeback", "label": "COMEBACK WIN", "coins": COMEBACK_BONUS})
	if won and first_win_today:
		items.append({"id": "daily_win", "label": "FIRST WIN TODAY", "coins": DAILY_WIN_BONUS})
	if won and career_wins >= 1 and career_wins <= FIRST_WINS_BONUS.size():
		items.append({"id": "first_wins", "label": "NEW COACH BONUS (WIN %d)" % career_wins,
				"coins": int(FIRST_WINS_BONUS[career_wins - 1])})
	return _total(items)


## Weighted stat counts for the per-stat bonuses: {"tds", "takeaways", "shutout"} (floats).
## Fully played: the real counts (weight 1). Fully simulated (r["simulated"], no "played_box"):
## everything x SIM_STAT_MULT. Played then simmed ("played_box" = box at the moment of the sim):
## played stats at full weight, the simmed remainder at SIM_STAT_MULT.
static func sim_counts(r: Dictionary) -> Dictionary:
	var tds := float(int(r.get("tds", 0)))
	var take := float(int(r.get("def_ints", 0)) + int(r.get("def_sacks", 0)))
	var shut := 1.0
	if r.get("simulated", false):
		if r.has("played_box"):
			var pb: Dictionary = r["played_box"]
			var p_tds := float(int(pb.get("tds", 0)))
			var p_take := float(int(pb.get("def_ints", 0)) + int(pb.get("def_sacks", 0)))
			tds = p_tds + (tds - p_tds) * SIM_STAT_MULT
			take = p_take + (take - p_take) * SIM_STAT_MULT
		else:
			tds *= SIM_STAT_MULT
			take *= SIM_STAT_MULT
		shut = SIM_STAT_MULT
	return {"tds": tds, "takeaways": take, "shutout": shut}


## The box score objectives and coach XP see: a played game's box as is; a partly played game's
## played_box (with the final pf/pa/won); a fully simulated game's counting stats x SIM_STAT_MULT.
static func sim_box(r: Dictionary) -> Dictionary:
	var box: Dictionary = r.get("box", {}).duplicate()
	if not r.get("simulated", false):
		return box
	if r.has("played_box"):
		box = (r["played_box"] as Dictionary).duplicate()
		box["pf"] = int(r.get("pf", 0))
		box["pa"] = int(r.get("pa", 0))
		box["won"] = int(box["pf"]) > int(box["pa"])
		return box
	for key in box.keys():
		if key in ["pf", "pa", "won", "came_back", "forfeit"]:
			continue
		if box[key] is int:
			box[key] = int(round(float(box[key]) * SIM_STAT_MULT))
	return box


static func _total(items: Array) -> Dictionary:
	var total := 0
	var lines: Array = []
	for i in items:
		total += int(i["coins"])
		lines.append([i["label"], int(i["coins"])])
	return {"total": total, "lines": lines, "items": items}


## Everything that happens to the profile after a match, in one call (the hub uses this):
## record W/L/T, win streak, coins (itemized), objectives recorded AND auto-claimed (their
## coins become items with id "objective"), player development XP, coach XP + level-ups.
## r: MatchController.match_result() (optionally with "box": GameState.box_score(team)).
## Returns {"total": coins added, "items": [{"id","label","coins"}], "lines": [[label, coins]],
##  "won": bool, "streak": int, "objectives": [objective dicts completed this match],
##  "level_ups": [{uid,name,from,to}] (players), "coach": {"xp": int, "items": [...],
##  "level_ups": [{level,coins,pack}], "progress": ProgressionRules.level_progress()},
##  "packs": [pack ids queued in Profile.pending_packs]}.
static func postgame(profile: Profile, db: RosterDB, r: Dictionary, unix_time := -1) -> Dictionary:
	var now := unix_time if unix_time >= 0 else int(Time.get_unix_time_from_system())
	var forfeit: bool = r.get("forfeit", false)
	var pf := int(r.get("pf", 0))
	var pa := int(r.get("pa", 0))
	var won := pf > pa and not forfeit
	var tie := pf == pa and not forfeit
	var packs_before := profile.pending_packs.size()
	profile.stats["games"] += 1
	if won:
		profile.stats["wins"] += 1
		profile.stats["win_streak"] = int(profile.stats.get("win_streak", 0)) + 1
		profile.stats["best_streak"] = maxi(int(profile.stats.get("best_streak", 0)), int(profile.stats["win_streak"]))
	else:
		profile.stats["win_streak"] = 0
		if tie:
			profile.stats["ties"] += 1
		else:
			profile.stats["losses"] += 1
	var today := DailyRules.day_of(now)
	var first_win := won and int(profile.stats["last_win_day"]) != today
	if won:
		profile.stats["last_win_day"] = today
	var rw := match_rewards(r, first_win, int(profile.stats["win_streak"]), int(profile.stats["wins"]) if won else 0)
	var items: Array = rw["items"]
	# Objectives: record the box, auto-claim what this match finished.
	var box: Dictionary = sim_box(r)
	for k in ["pf", "pa", "tds", "def_ints", "def_sacks", "came_back", "forfeit"]:
		if r.has(k) and not box.has(k):
			box[k] = r[k]
	box["won"] = won
	var done_objs: Array = []
	var coach_ups: Array = []
	var done_ids := ObjectiveRules.record_match(profile, box, now)
	done_ids.append_array(ObjectiveRules.record_best(profile, "team_ovr", Collection.team_ovr(profile, db), now))
	for id in done_ids:
		var o := ObjectiveRules.find(profile, id, now)
		var c := ObjectiveRules.claim_details(profile, id, now)
		if int(c["coins"]) > 0 or c["pack"] != "":
			done_objs.append(o)
			coach_ups.append_array(c["level_ups"])
			var label := "%s: %s" % [o["kind"].to_upper(), o["title"]]
			items.append({"id": "objective", "label": label, "coins": int(c["coins"]), "pack": c["pack"]})
	# Match coins (objective coins were already added by claim_details).
	var match_coins := int(rw["total"])
	var payday := int(round(match_coins * (CoachPerks.coin_mult(profile) - 1.0)))
	if payday > 0:
		items.append({"id": "payday", "label": "PAYDAY PERK", "coins": payday})
		match_coins += payday
	profile.coins += match_coins
	profile.stats["coins_earned"] += match_coins
	# Player development.
	var dev_ups: Array[Dictionary] = [] if forfeit else Collection.award_xp(profile, db, won)
	if not dev_ups.is_empty():
		ObjectiveRules.record_event(profile, "levelups", dev_ups.size(), now)
	# Coach XP.
	var cxp := {"total": 0, "items": []} if forfeit else ProgressionRules.xp_for_match(box, won)
	coach_ups.append_array(ProgressionRules.add_xp(profile, int(cxp["total"])))
	var out := _total(items)
	out["won"] = won
	out["streak"] = int(profile.stats["win_streak"])
	out["objectives"] = done_objs
	out["level_ups"] = dev_ups
	out["coach"] = {"xp": int(cxp["total"]), "items": cxp["items"], "level_ups": coach_ups,
			"progress": ProgressionRules.level_progress(int(profile.coach["xp"]))}
	out["packs"] = profile.pending_packs.slice(packs_before)
	return out
