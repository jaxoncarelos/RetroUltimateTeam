class_name RatingModel
extends RefCounted
## Every attribute -> gameplay formula. Pure functions; constants come from GameplayTuning.

const ATTRS := ["spd", "acc", "str", "awr", "thp", "tha", "cth", "rte", "car", "elu",
		"blk", "tak", "cov", "prs", "kpw", "kac"]

## Per-position offsets from OVR used to fill blank roster attributes.
const POSITION_PROFILE := {
	"QB": {"spd": -22, "acc": -14, "str": -25, "awr": 0, "thp": 0, "tha": 0, "cth": -35, "car": -10, "elu": -20},
	"RB": {"spd": 2, "acc": 3, "str": -8, "awr": -8, "cth": -12, "rte": -15, "car": 0, "elu": 2, "blk": -25},
	"WR": {"spd": 3, "acc": 1, "str": -22, "awr": -6, "cth": 0, "rte": 0, "car": -8, "elu": -4, "blk": -35},
	"TE": {"spd": -12, "acc": -8, "str": -5, "awr": -4, "cth": -2, "rte": -8, "car": -8, "elu": -18, "blk": -6},
	"OL": {"spd": -35, "acc": -25, "str": 2, "awr": -6, "blk": 0},
	"DL": {"spd": -22, "acc": -12, "str": 0, "awr": -8, "tak": -6, "prs": 0},
	"LB": {"spd": -10, "acc": -6, "str": -8, "awr": -2, "tak": 0, "cov": -10, "prs": -15, "cth": -25},
	"CB": {"spd": 2, "acc": 2, "str": -25, "awr": -5, "tak": -14, "cov": 0, "cth": -18},
	"S": {"spd": -3, "acc": -2, "str": -18, "awr": -2, "tak": -6, "cov": -4, "cth": -20},
	"K": {"spd": -40, "acc": -35, "str": -40, "awr": -20, "kpw": 0, "kac": 0},
}
const FLOOR := 35


## Full attribute dictionary for a position/OVR, with explicit values overriding the profile.
static func fill_attrs(pos: String, ovr: int, explicit: Dictionary = {}) -> Dictionary:
	var profile: Dictionary = POSITION_PROFILE.get(pos, {})
	var out := {}
	for a in ATTRS:
		var v: int
		if explicit.has(a) and explicit[a] != null:
			v = int(explicit[a])
		elif profile.has(a):
			v = ovr + int(profile[a])
		else:
			v = FLOOR + (ovr - 60) / 3
		out[a] = clampi(v, 25, 99)
	return out


static func _n(v: float) -> float:
	return clampf(v / 99.0, 0.0, 1.0)


static func sigmoid(x: float) -> float:
	return 1.0 / (1.0 + exp(-x))


static func max_speed(t: GameplayTuning, spd: float) -> float:
	return t.speed_base + _n(spd) * t.speed_range


static func acceleration(t: GameplayTuning, acc: float) -> float:
	return t.accel_base + _n(acc) * t.accel_range


static func reaction_delay(t: GameplayTuning, awr: float) -> float:
	return lerpf(t.reaction_slow, t.reaction_fast, clampf((awr - 60.0) / 39.0, 0.0, 1.0))


static func cut_keep(t: GameplayTuning, rte: float) -> float:
	return lerpf(t.cut_keep_min, t.cut_keep_max, _n(rte))


static func throw_speed(t: GameplayTuning, thp: float) -> float:
	return t.throw_speed_base + _n(thp) * t.throw_speed_range


static func max_throw_distance(t: GameplayTuning, thp: float) -> float:
	return t.throw_dist_base + _n(thp) * t.throw_dist_range


## Flight time and apex height (yards) for an open-lane throw of `dist` yards (automatic
## loft: deep balls are lobbed). See PassModel.plan for lane clearance.
static func throw_arc(t: GameplayTuning, thp: float, dist: float) -> Vector2:
	var loft := PassModel.auto_loft(t, dist)
	var apex := PassModel.apex_for(t, dist, loft)
	return Vector2(PassModel.duration(t, thp, dist, apex, loft), apex)


## Radius (yards) of random aim error. Pressure is 0..1.
static func aim_error(t: GameplayTuning, tha: float, awr: float, dist: float, pressure: float) -> float:
	var skill := 1.0 - _n(tha) * 0.85
	var calm := 1.0 - _n(awr) * 0.5
	return dist * t.aim_error_base * skill * (1.0 + pressure * 1.5 * calm)


## Probability the receiver catches. contest = 0 (open) .. 1 (defender draped on him).
static func catch_prob(t: GameplayTuning, cth: float, contest: float, def_cov: float) -> float:
	var base := lerpf(t.catch_base_low, t.catch_base_high, clampf((cth - 50.0) / 49.0, 0.0, 1.0))
	return clampf(base * (1.0 - t.contest_penalty * contest * (0.5 + 0.5 * _n(def_cov))), 0.05, 0.99)


## Chance a defender who beat the receiver to the ball comes down with it.
static func int_prob(t: GameplayTuning, cov: float, cth: float) -> float:
	return clampf(t.int_base + t.int_cov_scale * (_n(cov) * 0.6 + _n(cth) * 0.4) - 0.15, 0.05, 0.6)


## Chance a defender the ball passes within reach of gets a hand on it.
static func lane_play_prob(t: GameplayTuning, cov: float, awr: float) -> float:
	return clampf(t.lane_play_prob * (0.55 + 0.6 * _n(cov) * 0.7 + 0.6 * _n(awr) * 0.3), 0.05, 0.9)


## Given a hand on a passing ball, the chance he hauls it in (else it is tipped away).
static func lane_int_prob(t: GameplayTuning, cth: float) -> float:
	return clampf(t.lane_int_share * (0.4 + 0.9 * _n(cth)), 0.02, 0.6)


static func tackle_prob(t: GameplayTuning, tak: float, elu: float, carrier_str: float, juking: bool) -> float:
	var edge := (tak - (elu * 0.65 + carrier_str * 0.35)) / t.tackle_k + t.tackle_bias
	var p := sigmoid(edge)
	if juking:
		p *= t.juke_tackle_mult
	return clampf(p, t.tackle_min, t.tackle_max)


## Fumble chance when a carrier with ball security `car` is tackled.
static func fumble_prob(t: GameplayTuning, car: float, tak: float, hit_str: float) -> float:
	var power := tak * 0.5 + hit_str * 0.5
	return clampf(t.fumble_base + t.fumble_scale * (power - car) / 40.0, 0.002, 0.06)


## A leaping defender's INT chance given his timing error (s from the ideal).
static func jump_int_prob(t: GameplayTuning, timing_err: float, cov: float, cth: float) -> float:
	if timing_err > t.jump_perfect:
		return 0.0
	var skill := _n(cov) * 0.5 + _n(cth) * 0.5
	return clampf(t.jump_int_perfect * (0.6 + 0.6 * skill), 0.1, 0.85)


## Chance the leap knocks the ball away (checked after the INT roll).
static func jump_deflect_prob(t: GameplayTuning, timing_err: float) -> float:
	if timing_err <= t.jump_perfect:
		return 1.0
	if timing_err <= t.jump_good:
		return t.jump_deflect_good
	return 0.0


## Seconds a pressed receiver is slowed at the line.
static func press_jam(t: GameplayTuning, cov: float, rte: float) -> float:
	return clampf(t.press_jam_base + (cov - rte) * t.press_jam_per_point, 0.1, t.press_jam_max)


## Seconds an underneath defender bites on a play-action fake (smart defenders bite less).
static func pa_bite(t: GameplayTuning, awr: float) -> float:
	return t.pa_bite_time * (1.0 - 0.6 * clampf((awr - 60.0) / 39.0, 0.0, 1.0))


## Seconds a block holds before the defender sheds it.
static func shed_time(t: GameplayTuning, blk: float, rush: float, jitter: float) -> float:
	return maxf(t.shed_min, t.shed_base + (blk - rush) * t.shed_per_point + jitter * t.shed_jitter)


# ---------------------------------------------------------------- Road to Glory moves

## Speed share an agility rating keeps through a hard plant-and-cut.
static func rtg_cut_keep(t: GameplayTuning, agility: float) -> float:
	return lerpf(t.rtg_cut_keep_min, t.rtg_cut_keep_max, _n(agility))


## Agility for cuts by position: backs cut on elusiveness, receivers on route running,
## defenders on coverage; acceleration always helps.
static func agility(pos: String, attrs: Dictionary) -> float:
	var acc := float(attrs.get("acc", 60))
	match pos:
		"RB", "QB":
			return float(attrs.get("elu", 60)) * 0.6 + acc * 0.4
		"WR", "TE":
			return float(attrs.get("rte", 60)) * 0.6 + acc * 0.4
		"CB", "S", "LB":
			return float(attrs.get("cov", 60)) * 0.5 + acc * 0.5
	return acc


## Tackle chance multiplier of a carrier's move against a tackler (lower = harder to bring
## down). kind: "juke" | "spin" | "stiff" | "truck". 1.0 for anything else.
static func move_tackle_mult(t: GameplayTuning, kind: String, carrier: Dictionary, tackler: Dictionary) -> float:
	var tak := float(tackler.get("tak", 60))
	var elu := float(carrier.get("elu", 60))
	var cstr := float(carrier.get("str", 60))
	match kind:
		"juke":
			return 0.6 - 0.4 * sigmoid((elu - tak) / t.rtg_move_k)
		"spin":
			return 0.7 - 0.5 * sigmoid((elu * 0.6 + cstr * 0.4 - tak) / t.rtg_move_k)
		"stiff":
			return 0.75 - 0.5 * sigmoid((cstr - tak) / t.rtg_move_k)
		"truck":
			return 0.8 - 0.6 * sigmoid((cstr - (tak * 0.5 + float(tackler.get("str", 60)) * 0.5)) / t.rtg_move_k)
	return 1.0


## Seconds a defender loses his read when a carrier jukes in front of him.
static func juke_bite(t: GameplayTuning, elu: float, awr: float) -> float:
	return t.rtg_juke_bite * clampf(0.5 + (elu - awr) / 40.0, 0.2, 1.2)


## Seconds of warning a corner gets before his man breaks (the read telegraph).
static func telegraph_time(t: GameplayTuning, awr: float, rte: float) -> float:
	return clampf(t.rtg_tele_base + (awr - rte) * t.rtg_tele_per_point, 0.08, 0.6)
