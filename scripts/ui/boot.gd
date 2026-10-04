extends Node
## Boot router: debug flags go to the drive sandbox or straight into a match; a normal
## launch goes to the title screen (then the team picker on the first run, else the hub).

const SANDBOX := "res://scenes/debug/drive_sandbox.tscn"
const MATCH := "res://scenes/match/match.tscn"
const SANDBOX_FLAGS := ["--sim=", "--autoplay", "--defend", "--sandbox", "--spam=", "--look=", "--grid", "--autosnap"]
const MATCH_FLAGS := ["--ai-vs-ai=", "--watch", "--quick", "--home=", "--away=", "--rtg-game="]


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
	if OS.get_cmdline_user_args().has("--coach-demo"):
		prof.coach["level"] = 9
		prof.coach["perks"] = {"pocket": 2, "payday": 1, "breaker": 3}
	if OS.get_cmdline_user_args().has("--xf"):
		# X-Factor versions of the franchise's best players, starting.
		for pid in ["mahomes_patrick", "kelce_travis", "jones_chris", "mcduffie_trent", "butker_harrison"]:
			if GameData.db.cards.has(CardRules.xf_id(pid)):
				prof.add_card(CardRules.xf_id(pid))
		Collection.auto_lineup(prof, GameData.db)
	if OS.get_cmdline_user_args().has("--legends"):
		# A few LEGEND cards (retired greats), starting: Rice + Megatron, Barry, LT, Deion, Reggie.
		for pid in ["rice_jerry", "johnson_calvin", "sanders_barry", "taylor_lawrence", "sanders_deion", "white_reggie"]:
			if GameData.db.cards.has(CardRules.legend_id(pid)):
				prof.add_card(CardRules.legend_id(pid))
		Collection.auto_lineup(prof, GameData.db)
	if OS.get_cmdline_user_args().has("--champ"):
		EconomyRules.champion_reward(prof, GameData.db)
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
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rtg="):
			_demo_rtg(prof, a.trim_prefix("--rtg=").to_upper(), rng)
	SaveManager.profile = prof
	GameData.register_rtg(prof)


## Debug: a Road to Glory career (`--rtg=WR`): drafted, two games into season 1. Add
## `--rtg-stage=draft` (before the draft, combine done) or `--rtg-stage=offseason` (season over).
func _demo_rtg(prof: Profile, pos: String, rng: RandomNumberGenerator) -> void:
	if not pos in RtgRules.POSITIONS:
		pos = "WR"
	var stage := "season"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rtg-stage="):
			stage = a.trim_prefix("--rtg-stage=")
	var arch: String = RtgRules.ARCHETYPES[pos][0]["id"]
	var player := RtgRules.new_player(pos, arch, "JALEN", "CARTER", 11 if pos in ["WR", "QB"] else 24,
			{"skin": 4, "hair": "dreads", "hair_color": "black", "beard": "stubble", "visor": "tinted"})
	prof.rtg = RtgRules.new_career(player)
	if stage == "draft":
		prof.rtg["combine"] = 78.0
		return
	RtgFlow.draft(prof.rtg, 78.0)
	RtgFlow.sign_rookie(prof.rtg)
	var games := 2 if stage == "season" else 40
	for i in games:
		var r := RtgRules.sim_game(prof.rtg, rng)
		if r.is_empty():
			break
		RtgRules.apply_game(prof.rtg, r, GameData.teams, rng)
	prof.rtg["xp"] = int(prof.rtg["xp"]) + 1500


## Debug configs so `--screen=X` shows something meaningful for screens that need input.
func _demo_config(screen: String) -> Dictionary:
	var prof := SaveManager.profile
	if screen == "rtg_postgame" and not prof.rtg.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var r := RtgRules.sim_game(prof.rtg, rng)
		r["simulated"] = false
		r["rtg"]["highlights"] = [{"text": "34 YD TOUCHDOWN CATCH", "pts": 97.0}, {"text": "DROPPED IT", "pts": 20.0}]
		return {"last_result": r}
	if not prof.has_team():
		return {}
	match screen:
		"pack_open":
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			var pid := "gold"
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--pack="):
					pid = a.get_slice("=", 1)
			if OS.get_cmdline_user_args().has("--elite"):
				pid = "elite"
			var pack := PackCatalog.get_pack(pid)
			var real := EconomyRules.resolve_mystery(pack, rng)
			var uids := EconomyRules.grant_pack(prof, real, GameData.db, rng)
			var cfg := {"uids": uids, "title": real.display_name, "pack": real.id}
			if real != pack:
				cfg["mystery"] = pack.id
			return cfg
		"draft":
			var rng := RandomNumberGenerator.new()
			rng.seed = 11
			var did := "draft"
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--pack="):
					did = a.get_slice("=", 1)
			EconomyRules.start_draft(prof, PackCatalog.get_pack(did), GameData.db, rng)
			return {}
		"prematch":
			var opp := "PHI" if prof.franchise_team != "PHI" else "KC"
			return {"home": prof.franchise_team, "away": opp, "mode": "quick", "from_hub": true}
		"results":
			if OS.get_cmdline_user_args().has("--sim-result"):
				return {"last_result": GameFlow.sim_result(prof, {"away": "PHI"})}
			return {"last_result": {"team": prof.franchise_team, "opponent": "PHI", "pf": 31, "pa": 17, "tds": 4,
					"def_ints": 1, "def_sacks": 2, "difficulty": 1, "mode": "quick", "came_back": true,
					"box": {"pass_yds": 287, "rush_yds": 96, "pass_td": 3, "rush_td": 1, "pass_att": 24, "pass_comp": 18,
							"rush_att": 17, "int": 0, "sacks": 1, "won": true, "longest_pass": 48, "longest_run": 22}}}
	return {}
