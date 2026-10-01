class_name DefenseMemory
extends RefCounted
## What the CPU defense has learned about the offense's calls: decayed "heat" per play id,
## formation and category, boosted by big gains. Heat drives counter-call weights and the
## "keyed" level that makes defenders react faster and jump the repeated play's routes.
## Pure logic (no nodes) so it is unit-testable.

var tuning: DefenseAITuning
var play_heat: Dictionary = {}       ## play id -> heat
var formation_heat: Dictionary = {}  ## formation id -> heat
var category_heat: Dictionary = {}   ## RUN/SHORT/DEEP -> heat
var play_names: Dictionary = {}      ## play id -> display name (for the HUD warning)
var recent: Array[Dictionary] = []   ## newest last: {play, formation, category, yards}

const RECENT_MAX := 8


func _init(p_tuning: DefenseAITuning = null) -> void:
	tuning = p_tuning if p_tuning != null else DefenseAITuning.new()


func reset() -> void:
	play_heat.clear()
	formation_heat.clear()
	category_heat.clear()
	recent.clear()


## Records one offensive call and the yards it gained (incompletions = 0).
func record(play_id: String, formation_id: String, category: String, yards: int, display_name := "") -> void:
	for d: Dictionary in [play_heat, formation_heat, category_heat]:
		for k in d.keys():
			d[k] = float(d[k]) * tuning.decay
			if d[k] < 0.02:
				d.erase(k)
	var add := tuning.heat_per_call
	if yards >= tuning.big_gain_yards:
		add += tuning.big_gain_heat
	elif yards <= 0:
		add -= tuning.stuffed_relief
	play_heat[play_id] = float(play_heat.get(play_id, 0.0)) + add
	formation_heat[formation_id] = float(formation_heat.get(formation_id, 0.0)) + add
	category_heat[category] = float(category_heat.get(category, 0.0)) + add
	if display_name != "":
		play_names[play_id] = display_name
	recent.append({"play": play_id, "formation": formation_id, "category": category, "yards": yards})
	if recent.size() > RECENT_MAX:
		recent.pop_front()


static func _level(heat: float, threshold: float, full: float) -> float:
	if heat < threshold:
		return 0.0
	return clampf(heat / full, 0.0, 1.0)


## 0..1: how strongly the defense is keyed on this call before it is run.
func key_level(play_id: String, formation_id := "", category := "") -> float:
	var t := tuning
	var lv := _level(float(play_heat.get(play_id, 0.0)), t.key_threshold, t.key_full)
	var f := _level(float(formation_heat.get(formation_id, 0.0)), t.formation_key_threshold, t.key_full * 1.5)
	var c := _level(float(category_heat.get(category, 0.0)), t.category_key_threshold, t.key_full * 1.8)
	return maxf(lv, maxf(f * t.formation_key_weight, c * t.category_key_weight))


## The play the defense is keyed on (highest play heat over the threshold), or "".
func keyed_play() -> String:
	var best := ""
	var best_heat := tuning.key_threshold
	for id in play_heat:
		if float(play_heat[id]) >= best_heat:
			best_heat = float(play_heat[id])
			best = id
	return best


func keyed_play_name() -> String:
	var id := keyed_play()
	return str(play_names.get(id, id)).to_upper()


func total_heat() -> float:
	var s := 0.0
	for k in category_heat:
		s += float(category_heat[k])
	return s


## Share (0..1) of recent calls in a category.
func category_share(category: String) -> float:
	var total := total_heat()
	if total <= 0.0:
		return 0.0
	return maxf(float(category_heat.get(category, 0.0)), 0.0) / total


## Weight multiplier for a defensive call that counters the given offensive categories.
## `expected` optionally biases the shares (situation prior: {"RUN": 0.6, ...}).
func counter_weight(counters: Array, expected: Dictionary = {}) -> float:
	if counters.is_empty():
		return 1.0
	var t := tuning
	var confidence := clampf(total_heat() / t.confidence_heat, 0.0, 1.0)
	var w := 1.0
	for c in counters:
		var share := category_share(c) * confidence
		share += float(expected.get(c, 0.0)) * t.situation_weight * (1.0 - confidence * 0.5)
		w += t.counter_weight * share
	var keyed := keyed_play()
	if keyed != "":
		var cat := _category_of(keyed)
		if cat in counters:
			w += t.keyed_counter_bonus * key_level(keyed)
	return w


func _category_of(play_id: String) -> String:
	for i in range(recent.size() - 1, -1, -1):
		if recent[i]["play"] == play_id:
			return recent[i]["category"]
	return ""
