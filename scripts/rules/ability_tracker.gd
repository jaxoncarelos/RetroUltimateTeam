class_name AbilityTracker
extends RefCounted
## Runs the human team's X-Factor abilities during a match: counts each play toward every
## ability in the lineup, switches them on (returning activation events for the HUD), resets
## drive/series counters when possessions change, and boosts the lineup's attributes before
## each snap. Pure logic (MatchController feeds it results; AbilityRules has the rules).

## slot -> {"id": ability id, "name": player short name}
var cards: Dictionary = {}
var counters: Dictionary = {}    ## slot -> progress toward the trigger
var active: Dictionary = {}      ## slot -> true while the ability is on (non-clutch)
var _drive := -1                 ## GameState.drive_no seen last (resets drive/series scopes)


## Reads the abilities out of lineup entries (slot -> {name, ability, ...}).
func setup(entries: Dictionary) -> void:
	cards.clear()
	counters.clear()
	active.clear()
	for slot in entries:
		var id := str(entries[slot].get("ability", ""))
		if id != "" and not AbilityRules.get_def(id).is_empty():
			cards[slot] = {"id": id, "name": str(entries[slot].get("name", slot))}


func has_any() -> bool:
	return not cards.is_empty()


## Call before every snap with the current drive number: a new possession ends "drive" and
## "series" abilities (both reset whenever the ball changes hands).
func on_drive(drive_no: int) -> void:
	if drive_no == _drive:
		return
	_drive = drive_no
	for slot in cards:
		var scope := str(AbilityRules.get_def(cards[slot]["id"])["scope"])
		if scope == "drive" or scope == "series":
			counters.erase(slot)
			active.erase(slot)


## Counts one finished play (see AbilityRules.count for `ev`). Returns the abilities that
## switched on: [{slot, id, ability (display name), name (player), text}].
func record(ev: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot in cards:
		var id: String = cards[slot]["id"]
		var d := AbilityRules.get_def(id)
		if d["scope"] == "clutch" or active.has(slot):
			continue
		var c := AbilityRules.count(id, slot, ev)
		if c < 0 and d.get("streak", false):
			counters[slot] = 0
			continue
		if c <= 0:
			continue
		counters[slot] = int(counters.get(slot, 0)) + c
		if int(counters[slot]) >= int(d["need"]):
			active[slot] = true
			out.append({"slot": slot, "id": id, "ability": d["name"], "name": cards[slot]["name"], "text": d["text"]})
	return out


## Whether the ability in `slot` is boosting right now. situation: {quarter, half_seconds_left}.
func is_on(slot: String, situation: Dictionary = {}) -> bool:
	if not cards.has(slot):
		return false
	var id: String = cards[slot]["id"]
	return active.has(slot) or AbilityRules.clutch_on(id, situation)


## A lineup side (slot -> {attrs, ...}) with the active abilities' boosts applied.
func apply(side: Dictionary, situation: Dictionary = {}) -> Dictionary:
	var out := {}
	for slot in side:
		var e: Dictionary = side[slot]
		if is_on(slot, situation):
			e = e.duplicate()
			e["attrs"] = AbilityRules.boosted(e["attrs"], cards[slot]["id"])
		out[slot] = e
	return out


## Kicker attributes with his clutch ability (if any) applied.
func apply_kicker(attrs: Dictionary, situation: Dictionary = {}) -> Dictionary:
	if is_on("K", situation):
		return AbilityRules.boosted(attrs, cards["K"]["id"])
	return attrs


## HUD list of what is on: [{slot, ability, name}].
func active_list(situation: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot in cards:
		if is_on(slot, situation):
			out.append({"slot": slot, "ability": AbilityRules.get_def(cards[slot]["id"])["name"],
					"name": cards[slot]["name"]})
	return out


## Progress of every ability: [{slot, ability, name, have, need, on}] (pre-snap HUD).
func progress(situation: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot in cards:
		var d := AbilityRules.get_def(cards[slot]["id"])
		out.append({"slot": slot, "ability": d["name"], "name": cards[slot]["name"],
				"have": int(counters.get(slot, 0)), "need": int(d.get("need", 0)), "on": is_on(slot, situation)})
	return out
