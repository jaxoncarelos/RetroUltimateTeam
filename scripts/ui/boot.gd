extends Node
## Boot router: debug flags go to the drive sandbox, everything else to the game.
## (Phase 4+ routes a normal launch to the title/hub instead of straight into a match.)

const SANDBOX := "res://scenes/debug/drive_sandbox.tscn"
const MATCH := "res://scenes/match/match.tscn"
const SANDBOX_FLAGS := ["--sim=", "--autoplay", "--defend", "--sandbox", "--spam=", "--look=", "--grid", "--autosnap"]


func _ready() -> void:
	var target := MATCH
	for arg in OS.get_cmdline_user_args():
		for f in SANDBOX_FLAGS:
			if arg.begins_with(f):
				target = SANDBOX
	get_tree().change_scene_to_file.call_deferred(target)
