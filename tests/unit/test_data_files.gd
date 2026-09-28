extends GutTest
## Validates the hand-edited data files so a bad roster/playbook edit fails fast.

const ROSTER := "res://data/roster.csv"
const POSITIONS := ["QB", "RB", "WR", "TE", "OL", "DL", "LB", "CB", "S", "K"]


func _roster_rows() -> Array:
	var rows := []
	var f := FileAccess.open(ROSTER, FileAccess.READ)
	assert_not_null(f, "roster.csv must be readable at runtime (import mode Keep File)")
	if f == null:
		return rows
	var header := PackedStringArray()
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var cols := line.split(",")
		if header.is_empty():
			header = cols
			continue
		rows.append({"cols": cols, "header": header})
	return rows


func test_roster_rows_are_well_formed() -> void:
	var rows := _roster_rows()
	assert_gt(rows.size(), 40)
	var teams := TeamData.load_all()
	var ids := {}
	for r in rows:
		var cols: PackedStringArray = r["cols"]
		assert_eq(cols.size(), r["header"].size(), "column count for %s" % cols[0])
		assert_false(ids.has(cols[0]), "duplicate id %s" % cols[0])
		ids[cols[0]] = true
		assert_true(teams.has(cols[2]), "unknown team %s" % cols[2])
		assert_has(POSITIONS, cols[3], "bad position for %s" % cols[0])
		assert_between(int(cols[5]), 40, 99, "ovr for %s" % cols[0])


func test_all_32_teams_present() -> void:
	var teams := TeamData.load_all()
	assert_eq(teams.size(), 32)
	for abbr in teams:
		var t: TeamData = teams[abbr]
		assert_ne(t.team_name, "")
		assert_has(["AFC", "NFC"], t.conf)


func _check_book(book: PlaybookDef, side: String) -> void:
	assert_gt(book.plays.size(), 0)
	for p in book.plays:
		assert_eq(p.side, side, p.id)
		assert_not_null(p.formation, p.id)
		assert_eq(p.formation.slots.size(), 9, "%s should be 9v9" % p.id)
		for slot in p.assignments:
			assert_true(p.formation.slots.has(slot), "%s assigns unknown slot %s" % [p.id, slot])


func test_offense_playbook() -> void:
	var book: PlaybookDef = load("res://data/plays/offense_playbook.tres")
	_check_book(book, "offense")
	for p in book.plays:
		var has_qb := p.assignments.has("QB")
		assert_true(has_qb, "%s needs a QB assignment" % p.id)


func test_defense_playbook_man_targets_exist() -> void:
	var book: PlaybookDef = load("res://data/plays/defense_playbook.tres")
	_check_book(book, "defense")
	var off_slots := ["QB", "RB", "WR1", "WR2", "TE", "OL1", "OL2", "OL3", "OL4"]
	for p in book.plays:
		for slot in p.assignments:
			var a: Dictionary = p.assignments[slot]
			if a.get("type") == "man":
				assert_has(off_slots, a.get("target"), "%s %s man target" % [p.id, slot])
