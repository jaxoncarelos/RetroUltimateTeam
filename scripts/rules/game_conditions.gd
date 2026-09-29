class_name GameConditions
extends RefCounted
## Stadium conditions for one game: day or night, and weather (clear, rain, snow, fog) or an
## indoor dome. Rolled from the HOME team's climate; rain and snow make the ball slick (more
## fumbles, looser throws). Pure logic; the look is WeatherFx.
##   {"time": "day" | "night", "weather": "clear" | "rain" | "snow" | "fog" | "dome"}

const DOMES := ["ATL", "DET", "DAL", "HOU", "IND", "LV", "MIN", "NO", "ARI", "LAR"]
const COLD := ["BUF", "GB", "CHI", "NE", "DEN", "PIT", "CLE", "CIN", "KC", "NYG", "NYJ", "PHI", "TEN", "BAL", "WAS", "SEA"]
const WET := {"SEA": 0.30, "MIA": 0.24, "TB": 0.24, "JAX": 0.22, "NO": 0.2, "CAR": 0.18, "GB": 0.16}
const NIGHT_CHANCE := 0.4
const RAIN_BASE := 0.13
const SNOW_COLD := 0.15
const FOG_CHANCE := 0.05


static func roll(home: String, rng: RandomNumberGenerator) -> Dictionary:
	if home in DOMES:
		return {"time": "day", "weather": "dome"}
	var time := "night" if rng.randf() < NIGHT_CHANCE else "day"
	var x := rng.randf()
	var rain := float(WET.get(home, RAIN_BASE))
	var snow := SNOW_COLD if home in COLD else 0.0
	var weather := "clear"
	if x < snow:
		weather = "snow"
	elif x < snow + rain:
		weather = "rain"
	elif x < snow + rain + FOG_CHANCE:
		weather = "fog"
	return {"time": time, "weather": weather}


static func is_slick(c: Dictionary) -> bool:
	return str(c.get("weather", "clear")) in ["rain", "snow"]


## "NIGHT GAME  -  RAIN" (empty for a clear afternoon).
static func label(c: Dictionary) -> String:
	var parts: Array[String] = []
	if str(c.get("weather", "clear")) == "dome":
		return "DOME"
	if str(c.get("time", "day")) == "night":
		parts.append("NIGHT GAME")
	match str(c.get("weather", "clear")):
		"rain":
			parts.append("RAIN")
		"snow":
			parts.append("SNOW")
		"fog":
			parts.append("FOG")
	return "  -  ".join(parts)


## What the weather does to play, for the prematch screen ("" when nothing).
static func effect_text(c: Dictionary) -> String:
	if is_slick(c):
		return "SLICK BALL: MORE FUMBLES, LOOSER THROWS"
	if str(c.get("weather", "clear")) == "fog":
		return "FOG: HARD TO SEE DOWNFIELD"
	return ""


## Match tuning with the weather applied (the original resource when nothing changes).
static func apply_tuning(t: GameplayTuning, c: Dictionary) -> GameplayTuning:
	if not is_slick(c):
		return t
	var out := t.duplicate() as GameplayTuning
	var snow := str(c["weather"]) == "snow"
	out.fumble_base *= 1.3 if snow else 1.5
	out.aim_error_base *= 1.1 if snow else 1.15
	out.lob_catch_penalty += 0.04
	return out
