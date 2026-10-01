extends SceneTree
## Checks an exported .pck still carries resource data the game depends on (Godot's
## text->binary export conversion drops PackedStringArray properties, so data uses
## Array[String]; once QB packs pulled any position and play tags vanished).
## Also: pass the installed build's pack first to check the update overrides it. Run from an EMPTY project so only the pack is loaded:
##   godot --headless --path <empty dir> --script <this file> -- [<older.pck>] <new.pck>
## Exits 1 on failure.


func _init() -> void:
	# Packs mount in order (installed build's data first, the new update last), like the phone.
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("verify_pack: no pack given")
		quit(1)
		return
	for a in args:
		if not ProjectSettings.load_resource_pack(a):
			printerr("verify_pack: cannot mount %s" % a)
			quit(1)
			return
	var bad: Array[String] = []
	var qb: Resource = load("res://data/packs/qb.tres")
	if qb == null or Array(qb.get("positions")) != ["QB"]:
		bad.append("qb pack positions = %s" % [qb.get("positions") if qb != null else null])
	# The update must win over the installed build's copies (an export-format change once
	# left the phone reading the old QB PACK while the new data sat unused in the update).
	if qb != null and OS.get_environment("EXPECT_QB_NAME") != "" \
			and str(qb.get("display_name")) != OS.get_environment("EXPECT_QB_NAME"):
		bad.append("qb pack is the old one (%s)" % qb.get("display_name"))
	var mystery: Resource = load("res://data/packs/mystery.tres")
	if mystery == null or (mystery.get("mystery") as Array).is_empty():
		bad.append("mystery pack list is empty")
	var fade: Resource = load("res://data/plays/offense/fade.tres")
	if fade == null or not (fade.get("tags") as Array).has("goal_line"):
		bad.append("play tags missing (fade)")
	if bad.is_empty():
		print("verify_pack: OK")
		quit(0)
	else:
		printerr("verify_pack: FAILED: " + "; ".join(bad))
		quit(1)
