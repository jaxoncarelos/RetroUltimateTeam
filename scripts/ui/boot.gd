extends Node
## Boot router: debug flags go to the drive sandbox or straight into a match; a normal
## launch goes to the team picker (first run) or the hub.

const SANDBOX := "res://scenes/debug/drive_sandbox.tscn"
const MATCH := "res://scenes/match/match.tscn"
const SANDBOX_FLAGS := ["--sim=", "--autoplay", "--defend", "--sandbox", "--spam=", "--look=", "--grid", "--autosnap"]
const MATCH_FLAGS := ["--ai-vs-ai=", "--watch", "--quick", "--home=", "--away="]


func _ready() -> void:
	var target := ""
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
	if target == "":
		target = SceneRouter.HUB if SaveManager.profile.has_team() else SceneRouter.TEAM_PICK
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
	SaveManager.profile = prof
