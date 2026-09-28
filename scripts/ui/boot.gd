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
	if target == "":
		target = SceneRouter.HUB if SaveManager.profile.has_team() else SceneRouter.TEAM_PICK
	get_tree().change_scene_to_file.call_deferred(target)
