extends SceneTree
## Dumps ArtGen output to PNGs for eyeballing (not used by the game).
## Run:  godot --headless --path . --script res://tools/gen_art_preview.gd -- <out_dir>
## Writes portraits.png (8x4 sample sheet, 3x), stars.png (real players with their roster.csv
## look, 3x), helmets.png (3x) and title.png (1x).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://art_preview"
	DirAccess.make_dir_recursive_absolute(out)
	var teams := [
		{"primary": Color("#e31837"), "secondary": Color("#ffb81c"), "helmet": Color("#e31837"), "pants": Color.WHITE},
		{"primary": Color("#004c54"), "secondary": Color("#a5acaf"), "helmet": Color("#004c54"), "pants": Color.WHITE},
		{"primary": Color("#0b162a"), "secondary": Color("#c83803"), "helmet": Color("#0b162a"), "pants": Color.WHITE},
		{"primary": Color("#203731"), "secondary": Color("#ffb612"), "helmet": Color("#ffb612"), "pants": Color("#ffb612")},
		{"primary": Color("#ffffff"), "secondary": Color("#003594"), "helmet": Color("#c2c3c7"), "pants": Color("#c2c3c7")},
		{"primary": Color("#4f2683"), "secondary": Color("#ffc62f"), "helmet": Color("#4f2683"), "pants": Color.WHITE},
		{"primary": Color("#101820"), "secondary": Color("#d3bc8d"), "helmet": Color("#101820"), "pants": Color("#101820")},
		{"primary": Color("#fb4f14"), "secondary": Color("#002244"), "helmet": Color("#fb4f14"), "pants": Color.WHITE},
	]
	var pos := ["QB", "RB", "WR", "TE", "OL", "DL", "LB", "CB"]
	var sheet := Image.create(8 * 36, 4 * 36, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#3a5aa8"))
	for i in 32:
		var p := ArtGen.portrait_image("player_%d" % (i * 7919), pos[i % 8], teams[i % 8], (i * 13) % 99)
		sheet.blend_rect(p, Rect2i(0, 0, 32, 32), Vector2i((i % 8) * 36 + 2, (i / 8) * 36 + 2))
	sheet.resize(sheet.get_width() * 3, sheet.get_height() * 3, Image.INTERPOLATE_NEAREST)
	sheet.save_png(out.path_join("portraits.png"))
	_stars(out)
	var hs := Image.create(4 * 68, 2 * 52, false, Image.FORMAT_RGBA8)
	hs.fill(Color("#3a5aa8"))
	var abbrs := ["KC", "PHI", "CHI", "GB", "LAR", "MIN", "NO", "DEN"]
	for i in 8:
		var h := ArtGen.helmet_image(abbrs[i], teams[i], i >= 4)
		hs.blend_rect(h, Rect2i(0, 0, 64, 48), Vector2i((i % 4) * 68 + 2, (i / 4) * 52 + 2))
	hs.resize(hs.get_width() * 3, hs.get_height() * 3, Image.INTERPOLATE_NEAREST)
	hs.save_png(out.path_join("helmets.png"))
	ArtGen.title_image().save_png(out.path_join("title.png"))
	print("art preview written to ", out)
	quit()


## Well-known players rendered with their roster.csv appearance (likeness check).
const STARS := ["mahomes_patrick", "allen_josh", "jackson_lamar", "burrow_joe", "hurts_jalen",
		"lawrence_trevor", "rodgers_aaron", "herbert_justin", "stroud_cj", "daniels_jayden",
		"henry_derrick", "barkley_saquon", "mccaffrey_christian", "robinson_bijan", "chubb_nick",
		"jefferson_justin", "chase_jamarr", "lamb_ceedee", "hill_tyreek", "hopkins_deandre",
		"kelce_travis", "kittle_george", "bowers_brock", "garrett_myles", "watt_tj",
		"crosby_maxx", "parsons_micah", "hunter_danielle", "gardner_sauce", "minshew_gardner",
		"hunter_travis", "mcglinchey_mike", "dalton_andy", "campbell_will", "skattebo_cam", "warner_fred"]


func _stars(out: String) -> void:
	var teams := TeamData.load_all()
	var db := RosterDB.new()
	db.load_file(RosterDB.ROSTER_PATH, teams.keys())
	var cols := 9
	var rows := int(ceil(STARS.size() / float(cols)))
	var sheet := Image.create(cols * 36, rows * 36, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#3a5aa8"))
	for i in STARS.size():
		var pd: PlayerData = db.players.get(STARS[i])
		if pd == null:
			push_warning("unknown star id " + STARS[i])
			continue
		var t: TeamData = teams.get(pd.team)
		var colors: Dictionary = t.uniform_colors() if t != null else {}
		var img := ArtGen.portrait_image(pd.id, pd.pos, colors, pd.jersey, pd.look)
		sheet.blend_rect(img, Rect2i(0, 0, 32, 32), Vector2i((i % cols) * 36 + 2, (i / cols) * 36 + 2))
	sheet.resize(sheet.get_width() * 3, sheet.get_height() * 3, Image.INTERPOLATE_NEAREST)
	sheet.save_png(out.path_join("stars.png"))
