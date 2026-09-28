extends SceneTree
## Dumps ArtGen output to PNGs for eyeballing (not used by the game).
## Run:  godot --headless --path . --script res://tools/gen_art_preview.gd -- <out_dir>
## Writes portraits.png (8x4 sample sheet, 3x), helmets.png (3x) and title.png (1x).

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
