extends Node
## Boot router: debug flags go to the drive sandbox or straight into a match; a normal
## launch goes to the title screen (then the team picker on the first run, else the hub).

const SANDBOX := "res://scenes/debug/drive_sandbox.tscn"
const MATCH := "res://scenes/match/match.tscn"
const SANDBOX_FLAGS := ["--sim=", "--autoplay", "--defend", "--sandbox", "--spam=", "--look=", "--grid", "--autosnap"]
const MATCH_FLAGS := ["--ai-vs-ai=", "--watch", "--quick", "--home=", "--away="]


func _ready() -> void:
	var target := ""
	var cfg := {}
	for arg in OS.get_cmdline_user_args():
		for f in SANDBOX_FLAGS:
			if arg.begins_with(f):
				target = SANDBOX
		for f in MATCH_FLAGS:
			if arg.begins_with(f) and target == "":
				target = MATCH
		if arg == "--reset-save":
			SaveManager.reset()
		if arg == "--demo-profile":
			_demo_profile()
		if arg.begins_with("--screen="):
			target = "res://scenes/meta/%s.tscn" % arg.get_slice("=", 1)
			cfg = _demo_config(arg.get_slice("=", 1))
		if arg.begins_with("--coins="):
			# Debug: top up coins (pair with --demo-profile so the real save is untouched).
			SaveManager.profile.coins = int(arg.get_slice("=", 1))
	if target == "":
		target = SceneRouter.TITLE
	SceneRouter.pending_config = cfg
	get_tree().change_scene_to_file.call_deferred(target)


## Debug: an unsaved KC career with a few packs opened (screenshots, quick UI checks).
func _demo_profile() -> void:
	SaveManager.disabled = true
	var prof := Profile.new()
	Collection.grant_starters(prof, GameData.db, "KC")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for id in ["gold", "silver", "silver", "bronze"]:
		EconomyRules.grant_pack(prof, PackCatalog.get_pack(id), GameData.db, rng)
	prof.coins = 6400
	if OS.get_cmdline_user_args().has("--season"):
		var strengths := {}
		for a in GameData.teams:
			strengths[a] = GameData.db.team_ovr(a)
		prof.season = SeasonRules.new_season(GameData.teams, "KC", 8, strengths, rng, 1)
		for i in 3:
			var g := SeasonRules.sim_week(prof.season, rng)
			var sc := SeasonRules.sim_score(75, 75, rng)
			SeasonRules.record_game(prof.season, g[0], g[1], sc[0], sc[1])
			prof.season["week"] = int(prof.season["week"]) + 1
	SaveManager.profile = prof


## Debug configs so `--screen=X` shows something meaningful for screens that need input.
func _demo_config(screen: String) -> Dictionary:
	var prof := SaveManager.profile
	if not prof.has_team():
		return {}
	match screen:
		"pack_open":
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			var pack := PackCatalog.get_pack("elite" if OS.get_cmdline_user_args().has("--elite") else "gold")
			var uids := EconomyRules.grant_pack(prof, pack, GameData.db, rng)
			return {"uids": uids, "title": pack.display_name, "pack": pack.id}
		"prematch":
			var opp := "PHI" if prof.franchise_team != "PHI" else "KC"
			return {"home": prof.franchise_team, "away": opp, "mode": "quick", "from_hub": true}
		"results":
			return {"last_result": {"team": prof.franchise_team, "opponent": "PHI", "pf": 31, "pa": 17, "tds": 4,
					"def_ints": 1, "def_sacks": 2, "difficulty": 1, "mode": "quick", "came_back": true,
					"box": {"pass_yds": 287, "rush_yds": 96, "pass_td": 3, "rush_td": 1, "pass_att": 24, "pass_comp": 18,
							"rush_att": 17, "int": 0, "sacks": 1, "won": true, "longest_pass": 48, "longest_run": 22}}}
	return {}
