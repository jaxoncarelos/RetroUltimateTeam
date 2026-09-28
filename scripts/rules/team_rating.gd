class_name TeamRating
extends RefCounted
## Lineup slots, team OVR (PLAN.md §5 weights), auto-best lineups, conversion to the
## PlayRunner lineup format, and the difficulty rescaling of CPU opponents (§4). Pure.

const OFFENSE_SLOTS := ["QB", "RB", "WR1", "WR2", "TE", "OL1", "OL2", "OL3", "OL4"]
const DEFENSE_SLOTS := ["DL1", "DL2", "DL3", "LB1", "LB2", "CB1", "CB2", "S1", "S2"]
const ALL_SLOTS := ["QB", "RB", "WR1", "WR2", "TE", "OL1", "OL2", "OL3", "OL4",
		"DL1", "DL2", "DL3", "LB1", "LB2", "CB1", "CB2", "S1", "S2", "K"]
## slot -> weight share of team OVR
const WEIGHTS := {
	"QB": 0.20, "RB": 0.08, "WR1": 0.06, "WR2": 0.06, "TE": 0.06,
	"OL1": 0.035, "OL2": 0.035, "OL3": 0.035, "OL4": 0.035,
	"DL1": 0.14 / 3.0, "DL2": 0.14 / 3.0, "DL3": 0.14 / 3.0, "LB1": 0.045, "LB2": 0.045,
	"CB1": 0.0375, "CB2": 0.0375, "S1": 0.0375, "S2": 0.0375, "K": 0.02,
}
## Difficulty tiers: name, opponent OVR offset vs your team, coin multiplier.
const DIFFICULTY := [["ROOKIE", -8, 0.75], ["PRO", -2, 1.0], ["ALL-PRO", 3, 1.3], ["LEGEND", 7, 1.6]]


static func slot_pos(slot: String) -> String:
	return slot.rstrip("0123456789")


## entries: slot -> {"ovr": int, ...}. Missing slots count as 50.
static func team_ovr(entries: Dictionary) -> int:
	var total := 0.0
	for slot in WEIGHTS:
		var e: Dictionary = entries.get(slot, {})
		total += float(e.get("ovr", 50)) * float(WEIGHTS[slot])
	return int(round(total))


## Best lineup from candidates: Array of {"key": any, "pos": String, "ovr": int,
## "player": optional id}. Returns slot -> candidate (highest OVR first; each candidate,
## and each real player when "player" is given, used once).
static func auto_best(candidates: Array) -> Dictionary:
	var sorted := candidates.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["ovr"]) > int(b["ovr"]))
	var out := {}
	var used := {}
	var used_players := {}
	for slot in ALL_SLOTS:
		var pos := slot_pos(slot)
		for i in sorted.size():
			var c: Dictionary = sorted[i]
			if used.has(i) or c["pos"] != pos or used_players.has(c.get("player", i)):
				continue
			out[slot] = c
			used[i] = true
			used_players[c.get("player", i)] = true
			break
	return out


## entries: slot -> {"name", "jersey", "attrs"} -> {"offense": {...}, "defense": {...}, "K": attrs}
static func match_lineup(entries: Dictionary) -> Dictionary:
	var off := {}
	var def := {}
	for slot in OFFENSE_SLOTS:
		if entries.has(slot):
			off[slot] = entries[slot]
	for slot in DEFENSE_SLOTS:
		if entries.has(slot):
			def[slot] = entries[slot]
	var k: Dictionary = entries.get("K", {})
	return {"offense": off, "defense": def, "K": k.get("attrs", RatingModel.fill_attrs("K", 70))}


## OVR the CPU opponent plays at: your OVR + difficulty offset + 30% of how much better or
## worse the real team is than the league average.
static func opponent_effective_ovr(your_ovr: int, difficulty: int, opp_real_ovr: int, league_avg: int) -> int:
	var offset: int = DIFFICULTY[clampi(difficulty, 0, DIFFICULTY.size() - 1)][1]
	return clampi(int(round(your_ovr + offset + (opp_real_ovr - league_avg) * 0.3)), 50, 99)


## Scales every attribute of a lineup's entries by effective/real OVR (keeps each team's
## identity: who is fast, who throws well).
static func rescale_entries(entries: Dictionary, real_ovr: int, effective_ovr: int) -> Dictionary:
	var f := float(effective_ovr) / maxf(real_ovr, 1.0)
	var out := {}
	for slot in entries:
		var e: Dictionary = entries[slot].duplicate()
		var a := {}
		for k in e["attrs"]:
			a[k] = clampi(int(round(float(e["attrs"][k]) * f)), 25, 99)
		e["attrs"] = a
		e["ovr"] = clampi(int(round(float(e.get("ovr", real_ovr)) * f)), 25, 99)
		out[slot] = e
	return out
