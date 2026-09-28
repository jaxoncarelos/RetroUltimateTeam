class_name KickModel
extends RefCounted
## Kickoffs, punts, field goals and the FG/PAT timing meter. Pure functions; constants in
## GameplayTuning ("Kicking"). Spots are in the receiving/kicking offense's own coordinates
## (attacking +x; own goal line x=10).


## Kickoff: returns the receiving team's starting x.
static func kickoff(t: GameplayTuning, rng: RandomNumberGenerator, kpw: float) -> float:
	var touchback := lerpf(t.kickoff_touchback_low, t.kickoff_touchback_high, clampf(kpw / 99.0, 0.0, 1.0))
	if rng.randf() < touchback:
		return FieldGeo.OWN_GOAL + t.touchback_yard
	if rng.randf() < t.kickoff_big_return:
		return FieldGeo.OWN_GOAL + rng.randf_range(45.0, 65.0)
	return FieldGeo.OWN_GOAL + rng.randf_range(15.0, 35.0)


## Free kick after a safety (from the kicking team's 20): receiving team's starting x.
static func free_kick(rng: RandomNumberGenerator) -> float:
	return FieldGeo.OWN_GOAL + rng.randf_range(32.0, 45.0)


## Punt from `los_x` (kicking offense coords). Returns the receiving team's starting x
## in its own coordinates.
static func punt(t: GameplayTuning, rng: RandomNumberGenerator, kpw: float, los_x: float) -> float:
	var gross := t.punt_base + clampf(kpw / 99.0, 0.0, 1.0) * t.punt_power + rng.randf_range(-t.punt_spread, t.punt_spread)
	var land := los_x + gross
	if land >= FieldGeo.OPP_GOAL:
		return FieldGeo.OWN_GOAL + t.touchback_yard - 5.0   # punt touchback = own 20
	var ret := rng.randf_range(0.0, t.punt_return_max)
	var spot := minf(land - ret, FieldGeo.OPP_GOAL - 1.0)
	return FieldGeo.LENGTH - spot


## Kick distance (yards) for a field goal snapped from `los_x`.
static func fg_distance(los_x: float) -> float:
	return (FieldGeo.OPP_GOAL - los_x) + 17.0


static func fg_max_range(t: GameplayTuning, kpw: float) -> float:
	return t.fg_range_base + clampf(kpw / 99.0, 0.0, 1.0) * t.fg_range_power


## CPU kicker success chance.
static func fg_prob(t: GameplayTuning, dist: float, kpw: float, kac: float) -> float:
	var max_r := fg_max_range(t, kpw)
	if dist > max_r:
		return 0.0
	var acc := clampf(kac / 99.0, 0.0, 1.0)
	var x := (dist - 20.0) / maxf(max_r - 20.0, 1.0)   # 0 at chip shot, 1 at max range
	return clampf(0.99 - x * x * (0.75 - 0.35 * acc), 0.05, 0.99)


## Meter: half-width (0..1 of the bar) of the green zone.
static func meter_zone(t: GameplayTuning, dist: float, kac: float) -> float:
	var hard := clampf((dist - 20.0) / 45.0, 0.0, 1.0)
	return clampf(t.meter_zone_base * (0.6 + 0.6 * clampf(kac / 99.0, 0.0, 1.0)) * (1.0 - 0.55 * hard), 0.04, 0.4)


## Meter: needle sweeps per second (full bar), faster for longer kicks.
static func meter_speed(t: GameplayTuning, dist: float) -> float:
	return t.meter_speed_base + clampf((dist - 20.0) / 45.0, 0.0, 1.0) * t.meter_speed_range


## Meter result for a needle stopped at `needle` (-1..1, 0 = center).
## Returns "good", "doink" (off the upright, no good) or "wide". Out of range = "short".
static func meter_result(t: GameplayTuning, needle: float, dist: float, kpw: float, kac: float) -> String:
	if dist > fg_max_range(t, kpw):
		return "short"
	var zone := meter_zone(t, dist, kac)
	var off := absf(needle)
	if off <= zone:
		return "good"
	if off <= zone + t.meter_doink:
		return "doink"
	return "wide"
