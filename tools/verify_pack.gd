extends SceneTree
## Checks an exported .pck still carries resource data the game depends on (Godot's
## text->binary export conversion once dropped every PackedStringArray: QB packs pulled any
## position and play tags vanished). Run from an EMPTY project so only the pack is loaded:
##   godot --headless --path <empty dir> --script <this file> -- <pack.pck>
## Exits 1 on failure.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or not ProjectSettings.load_resource_pack(args[0]):
		printerr("verify_pack: cannot mount %s" % [args])
		quit(1)
		return
	var bad: Array[String] = []
	var qb: Resource = load("res://data/packs/qb.tres")
	if qb == null or Array(qb.get("positions")) != ["QB"]:
		bad.append("qb pack positions = %s" % [qb.get("positions") if qb != null else null])
	var mystery: Resource = load("res://data/packs/mystery.tres")
	if mystery == null or (mystery.get("mystery") as PackedStringArray).is_empty():
		bad.append("mystery pack list is empty")
	var fade: Resource = load("res://data/plays/offense/fade.tres")
	if fade == null or not (fade.get("tags") as PackedStringArray).has("goal_line"):
		bad.append("play tags missing (fade)")
	if bad.is_empty():
		print("verify_pack: OK")
		quit(0)
	else:
		printerr("verify_pack: FAILED: " + "; ".join(bad))
		quit(1)
