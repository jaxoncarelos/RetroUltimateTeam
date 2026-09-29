extends GutTest
## Stadium conditions: domes are always fine, climates matter, slick weather changes the ball.

func _rolls(home: String, n := 2000) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var out := {"rain": 0, "snow": 0, "fog": 0, "clear": 0, "dome": 0, "night": 0}
	for i in n:
		var c := GameConditions.roll(home, rng)
		out[c["weather"]] += 1
		if c["time"] == "night":
			out["night"] += 1
	return out


func test_domes_are_always_indoors_by_day() -> void:
	for team in ["DET", "DAL", "MIN"]:
		var r := _rolls(team, 200)
		assert_eq(r["dome"], 200)
		assert_eq(r["night"], 0)


func test_climate_shapes_the_weather() -> void:
	var buf := _rolls("BUF")
	var mia := _rolls("MIA")
	assert_gt(buf["snow"], 200, "Buffalo gets snow")
	assert_eq(mia["snow"], 0, "Miami never does")
	assert_gt(_rolls("SEA")["rain"], _rolls("DEN")["rain"], "Seattle is wetter than Denver")
	assert_between(float(buf["night"]) / 2000.0, 0.34, 0.46, "about 4 in 10 games are at night")


func test_slick_weather_hurts_ball_security_and_accuracy() -> void:
	var base: GameplayTuning = load("res://data/tuning/gameplay_tuning.tres")
	assert_same(GameConditions.apply_tuning(base, {"time": "night", "weather": "clear"}), base, "clear = unchanged")
	var rain := GameConditions.apply_tuning(base, {"time": "day", "weather": "rain"})
	var snow := GameConditions.apply_tuning(base, {"time": "day", "weather": "snow"})
	assert_gt(rain.fumble_base, base.fumble_base)
	assert_gt(rain.aim_error_base, base.aim_error_base)
	assert_gt(rain.fumble_base, snow.fumble_base, "rain is the slickest")
	assert_eq(base.fumble_base, load("res://data/tuning/gameplay_tuning.tres").fumble_base, "the shared resource is untouched")


func test_labels() -> void:
	assert_eq(GameConditions.label({"time": "night", "weather": "rain"}), "NIGHT GAME  -  RAIN")
	assert_eq(GameConditions.label({"time": "day", "weather": "clear"}), "")
	assert_eq(GameConditions.label({"time": "day", "weather": "dome"}), "DOME")
