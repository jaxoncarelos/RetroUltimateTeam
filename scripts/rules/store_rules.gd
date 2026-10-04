class_name StoreRules
extends RefCounted
## The store's FEATURED shelf, Madden Mobile style: offers that rotate on the calendar.
##  - PROGRAM of the week: one limited-time era pack (PackCatalog.ERA_PACKS: a legend from
##    that era + current cards), on sale only this week.
##  - DAILY DEAL: one pack at DEAL_OFF off, once per day.
##  - BUNDLE DEAL of the week: a bundle at BUNDLE_OFF off its own price, once per week.
## Every player sees the same rotation (seeded by the local day / week number).
## Profile.store_buys counts purchases per offer key ("deal:20365"); keys of past days and
## weeks are dropped when you buy. Pure logic.

const DEAL_OFF := 0.3
const BUNDLE_OFF := 0.15
const DEAL_POOL := ["silver", "gold", "pro", "throwback", "xfactor", "team", "draft", "mystery"]
const BUNDLE_POOL := ["bundle_rookie", "bundle_gold", "bundle_silver", "bundle_elite"]


## Local day number (DailyRules) and its Monday-based week number.
static func week_of(day: int) -> int:
	return floori(float(day + 3) / 7.0)   # unix day 0 was a Thursday


## Seconds from `unix_time` until local day `day` starts.
static func _until_day(day: int, unix_time: int) -> int:
	var local := unix_time + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return maxi(0, day * 86400 - local)


## Today's featured offers: [{key, kind, pack (id), price, list_price, limit (0 = none),
## ends_in (seconds), tag}].
static func featured(unix_time: int) -> Array[Dictionary]:
	var day := DailyRules.day_of(unix_time)
	var week := week_of(day)
	var week_ends := _until_day((week + 1) * 7 - 3, unix_time)
	var day_ends := _until_day(day + 1, unix_time)
	var out: Array[Dictionary] = []
	var era := PackCatalog.get_pack(PackCatalog.ERA_PACKS[posmod(week, PackCatalog.ERA_PACKS.size())])
	out.append({"key": "program:%d" % week, "kind": "PROGRAM OF THE WEEK", "pack": era.id, "price": era.price,
			"list_price": era.price, "limit": 0, "ends_in": week_ends, "tag": "LIMITED"})
	var deal := PackCatalog.get_pack(DEAL_POOL[_hash(day, 17) % DEAL_POOL.size()])
	out.append({"key": "deal:%d" % day, "kind": "DAILY DEAL", "pack": deal.id,
			"price": _round(deal.price * (1.0 - DEAL_OFF)), "list_price": deal.price, "limit": 1,
			"ends_in": day_ends, "tag": "-%d%%" % int(round(DEAL_OFF * 100.0))})
	var b := PackCatalog.get_pack(BUNDLE_POOL[_hash(week, 31) % BUNDLE_POOL.size()])
	out.append({"key": "bundle:%d" % week, "kind": "BUNDLE OF THE WEEK", "pack": b.id,
			"price": _round(b.price * (1.0 - BUNDLE_OFF)), "list_price": PackCatalog.bundle_list_price(b),
			"limit": 1, "ends_in": week_ends, "tag": "DEAL"})
	return out


## Purchases of this offer left (-1 = unlimited).
static func left(profile: Profile, offer: Dictionary) -> int:
	var limit := int(offer.get("limit", 0))
	if limit <= 0:
		return -1
	return maxi(0, limit - int(profile.store_buys.get(str(offer["key"]), 0)))


static func can_buy(profile: Profile, offer: Dictionary) -> bool:
	var pack := PackCatalog.get_pack(str(offer["pack"]))
	return pack != null and left(profile, offer) != 0 and EconomyRules.can_buy(profile, pack, int(offer["price"]))


## Buys a featured offer (EconomyRules.buy at the offer price) and counts it. {} if not allowed.
static func buy(profile: Profile, offer: Dictionary, db: RosterDB, rng: RandomNumberGenerator, unix_time: int) -> Dictionary:
	if not can_buy(profile, offer):
		return {}
	var r := EconomyRules.buy(profile, PackCatalog.get_pack(str(offer["pack"])), db, rng, unix_time, int(offer["price"]))
	if r.is_empty():
		return r
	var live := {}
	for o in featured(unix_time):
		live[o["key"]] = true
	for k in profile.store_buys.keys():
		if not live.has(k):
			profile.store_buys.erase(k)
	var key := str(offer["key"])
	profile.store_buys[key] = int(profile.store_buys.get(key, 0)) + 1
	return r


## "2D 5H" / "5H 12M" / "12M".
static func time_left_text(seconds: int) -> String:
	var d := seconds / 86400
	var h := (seconds % 86400) / 3600
	var m := (seconds % 3600) / 60
	if d > 0:
		return "%dD %dH" % [d, h]
	if h > 0:
		return "%dH %dM" % [h, m]
	return "%dM" % maxi(1, m)


static func _round(coins: float) -> int:
	return int(round(coins / 50.0)) * 50


static func _hash(n: int, salt: int) -> int:
	var x := (n * 2654435761 + salt * 40503) & 0x7fffffff
	x = ((x >> 13) ^ x) * 1274126177 & 0x7fffffff
	return x
