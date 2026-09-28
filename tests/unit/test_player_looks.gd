extends GutTest
## Player appearance: roster.csv look columns -> PlayerData.look -> portraits and field sprites.

const HEADER := "id,name,team,pos,jersey,ovr,skin,hair,hair_color,beard,visor\n"


func _db(rows: String) -> RosterDB:
	var db := RosterDB.new()
	db.parse(HEADER + rows)
	return db


func test_parse_look_is_blank_safe() -> void:
	var db := _db("a,A One,KC,QB,15,90,3,Curly,Dark_Brown,stubble,\nb,B Two,KC,RB,20,80,,,,,\nc,C Three,KC,WR,11,80,9,dreads,,,tinted\n")
	assert_eq(db.errors.size(), 0, str(db.errors))
	assert_eq(db.players["a"].look, {"skin": 3, "hair": "curly", "hair_color": "dark_brown", "beard": "stubble"})
	assert_eq(db.players["b"].look, {}, "blank columns = no look")
	assert_false(db.players["c"].look.has("skin"), "out-of-range skin is dropped")
	assert_eq(db.players["c"].look.get("visor"), "tinted")


func test_csv_without_look_columns_still_parses() -> void:
	var db := RosterDB.new()
	db.parse("id,name,team,pos,jersey,ovr\nx,X,KC,QB,1,70\n")
	assert_eq(db.errors.size(), 0)
	assert_eq(db.players["x"].look, {})


func test_roster_looks_are_valid_keywords() -> void:
	var db := GameData.db
	var n := 0
	for id in db.players:
		var lk: Dictionary = db.players[id].look
		if lk.is_empty():
			continue
		n += 1
		if lk.has("skin"):
			assert_between(int(lk["skin"]), 1, 6, id)
		if lk.has("hair"):
			assert_has(ArtGen.HAIR_STYLES, ArtGen._alias(lk["hair"]), "%s hair" % id)
		if lk.has("hair_color"):
			assert_has(ArtGen.HAIR_COLOR_NAMES, ArtGen._alias(lk["hair_color"]), "%s hair_color" % id)
		if lk.has("beard"):
			assert_has(ArtGen.BEARDS, ArtGen._alias(lk["beard"]), "%s beard" % id)
		if lk.has("visor"):
			assert_has(["clear", "tinted"], lk["visor"], "%s visor" % id)
	assert_gt(n, 300, "most starters and stars have a look")
	assert_eq(db.players["mahomes_patrick"].look.get("hair"), "curly")


func test_face_uses_look_and_is_seeded_otherwise() -> void:
	var f := ArtGen.face("someone", {"skin": 6, "hair": "dreads", "hair_color": "black", "beard": "full"})
	assert_eq(f["skin"], 5)
	assert_eq(f["hair_style"], ArtGen.HAIR_STYLES.find("dreads"))
	assert_eq(f["hair_color"], 0)
	assert_eq(f["beard"], ArtGen.BEARDS.find("full"))
	var seeded := ArtGen.face("someone")
	assert_eq(seeded, ArtGen.face("someone"), "deterministic")
	var partial := ArtGen.face("someone", {"skin": 1})
	assert_eq(partial["mouth"], seeded["mouth"], "a known field doesn't reshuffle the seeded ones")
	assert_eq(partial["hair_style"], seeded["hair_style"])
	assert_eq(ArtGen.face("x", {"hair": "locs"})["hair_style"], ArtGen.HAIR_STYLES.find("dreads"), "aliases")


func test_portraits_are_deterministic_and_follow_the_look() -> void:
	var colors := {"primary": Color("#e31837"), "secondary": Color("#ffb81c")}
	var look := {"skin": 2, "hair": "mohawk", "hair_color": "red", "beard": "long"}
	var a := ArtGen.portrait_image("p1", "QB", colors, 15, look)
	var b := ArtGen.portrait_image("p1", "QB", colors, 15, look)
	assert_eq(a.get_data(), b.get_data(), "same look -> same pixels")
	var c := ArtGen.portrait_image("p1", "QB", colors, 15, {"skin": 6, "hair": "bald"})
	assert_ne(a.get_data(), c.get_data(), "look changes the portrait")
	# Every hair style and beard renders without errors.
	for hs in ArtGen.HAIR_STYLES:
		for bd in ArtGen.BEARDS:
			var img := ArtGen.portrait_image("p2", "OL", colors, 70, {"hair": hs, "beard": bd})
			assert_eq(img.get_size(), Vector2i(32, 32))


func test_portrait_by_id_uses_the_registered_look() -> void:
	# GameData registers every roster look at boot, so card code that only passes the id works.
	var p: PlayerData = GameData.player("mahomes_patrick")
	assert_eq(ArtGen.resolve_look(p.id), p.look)
	var colors := {"primary": Color("#e31837"), "secondary": Color("#ffb81c")}
	var by_id := ArtGen.portrait_image(p.id, p.pos, colors, p.jersey)
	var explicit := ArtGen.portrait_image(p.id, p.pos, colors, p.jersey, p.look)
	assert_eq(by_id.get_data(), explicit.get_data())
	assert_eq(ArtGen.portrait(p.id, p.pos, colors, p.jersey), ArtGen.portrait(p.id, p.pos, colors, p.jersey), "cached")


func test_lineups_carry_the_look() -> void:
	var db := GameData.db
	var entries := db.team_entries("KC")
	assert_eq(entries["QB"]["look"], db.players["mahomes_patrick"].look)
	var cpu := GameData.opponent_lineup("KC", 75, 1)
	assert_eq(cpu["offense"]["QB"]["look"], db.players["mahomes_patrick"].look, "survives rescaling")
	var prof := Profile.new()
	Collection.grant_starters(prof, db, "KC")
	Collection.auto_lineup(prof, db)
	var mine := Collection.lineup_entries(prof, db)
	for slot in mine:
		assert_true(mine[slot].has("look"), slot)


func test_field_skin_matches_the_look() -> void:
	assert_eq(PlayerSprites.skin_color(3, {"skin": 6}), ArtGen.SKIN[5])
	assert_eq(PlayerSprites.skin_color(3, {}), PlayerSprites.SKIN_TONES[3], "seeded without a look")
	assert_eq(PlayerSprites.visor_color("").a, 0.0)
	assert_gt(PlayerSprites.visor_color("tinted").a, 0.9)
	var m := PlayerSprites.make_material({}, 7, {"skin": 1, "visor": "clear"})
	assert_eq(m.get_shader_parameter("skin"), ArtGen.SKIN[0])
	assert_gt((m.get_shader_parameter("visor") as Color).a, 0.0)
	var legacy := PlayerSprites.make_material({}, 7)
	assert_eq((legacy.get_shader_parameter("visor") as Color).a, 0.0, "old call sites keep working")
