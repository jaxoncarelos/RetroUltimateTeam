extends Node
## Player settings (persisted to user://settings.cfg). Read anywhere as `Settings.<name>`.

const PATH := "user://settings.cfg"

signal changed

var defense_pace: int = DefensePace.Pace.EVERY_SNAP
var quarter_minutes := 2.5           ## game minutes per quarter (1.5 .. 5.0)
var difficulty := 1                  ## 0 Rookie, 1 Pro, 2 All-Pro, 3 Legend
var sfx_volume := 0.8
var music_volume := 0.6
var left_handed := false
var shake := true                    ## screen shake on big hits
var tutorial_done := false
var season_games := 8                ## 8 (short) or 17
var aim_sens := 1                   ## throw aim sensitivity index into AIM_NAMES / AIM_MULT (default MEDIUM)


const AIM_NAMES := ["LOW", "MEDIUM", "HIGH"]
## Multiplier on the slingshot pull -> throw distance (GameplayTuning.aim_gain). HIGH = the old feel.
const AIM_MULT := [0.55, 0.75, 1.0]


func aim_mult() -> float:
	return AIM_MULT[clampi(aim_sens, 0, AIM_MULT.size() - 1)]


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ai-vs-ai") or arg.begins_with("--sim="):
			return   # batch runs use defaults, not the player's settings
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	defense_pace = int(cfg.get_value("game", "defense_pace", defense_pace))
	quarter_minutes = float(cfg.get_value("game", "quarter_minutes", quarter_minutes))
	difficulty = int(cfg.get_value("game", "difficulty", difficulty))
	sfx_volume = float(cfg.get_value("audio", "sfx", sfx_volume))
	music_volume = float(cfg.get_value("audio", "music", music_volume))
	left_handed = bool(cfg.get_value("controls", "left_handed", left_handed))
	shake = bool(cfg.get_value("video", "shake", shake))
	tutorial_done = bool(cfg.get_value("game", "tutorial_done", tutorial_done))
	season_games = int(cfg.get_value("game", "season_games", season_games))
	aim_sens = clampi(int(cfg.get_value("controls", "aim_sens", aim_sens)), 0, AIM_MULT.size() - 1)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "defense_pace", defense_pace)
	cfg.set_value("game", "quarter_minutes", quarter_minutes)
	cfg.set_value("game", "difficulty", difficulty)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("controls", "left_handed", left_handed)
	cfg.set_value("video", "shake", shake)
	cfg.set_value("game", "tutorial_done", tutorial_done)
	cfg.set_value("game", "season_games", season_games)
	cfg.set_value("controls", "aim_sens", aim_sens)
	cfg.save(PATH)
	changed.emit()
