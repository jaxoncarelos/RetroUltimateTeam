extends SceneTree
## Bootstrap generator for formations/plays/playbooks (.tres).
## Run:  godot --headless --path . --script res://tools/build_playbooks.gd
## After generation the .tres files are the source of truth (edit them in the editor);
## re-running this script overwrites them.



func _init() -> void:
	var shotgun := _formation("off_shotgun", "Shotgun", "offense", {
		"QB": {"pos": "QB", "at": Vector2(-4, 0)},
		"RB": {"pos": "RB", "at": Vector2(-4, 1.6)},
		"OL1": {"pos": "OL", "at": Vector2(-1, -3.6)},
		"OL2": {"pos": "OL", "at": Vector2(-1, -1.2)},
		"OL3": {"pos": "OL", "at": Vector2(-1, 1.2)},
		"OL4": {"pos": "OL", "at": Vector2(-1, 3.6)},
		"TE": {"pos": "TE", "at": Vector2(-1, 6.2)},
		"WR1": {"pos": "WR", "at": Vector2(-0.5, -15)},
		"WR2": {"pos": "WR", "at": Vector2(-0.5, 13)},
	})
	var iform := _formation("off_iform", "I-Form", "offense", {
		"QB": {"pos": "QB", "at": Vector2(-1, 0)},
		"RB": {"pos": "RB", "at": Vector2(-6, 0)},
		"OL1": {"pos": "OL", "at": Vector2(-1, -3.6)},
		"OL2": {"pos": "OL", "at": Vector2(-1, -1.2)},
		"OL3": {"pos": "OL", "at": Vector2(-1, 1.2)},
		"OL4": {"pos": "OL", "at": Vector2(-1, 3.6)},
		"TE": {"pos": "TE", "at": Vector2(-1, 6.2)},
		"WR1": {"pos": "WR", "at": Vector2(-0.5, -15)},
		"WR2": {"pos": "WR", "at": Vector2(-0.5, 14)},
	})
	var base_d := _formation("def_base", "Base 3-2", "defense", {
		"DL1": {"pos": "DL", "at": Vector2(1, -3)},
		"DL2": {"pos": "DL", "at": Vector2(1, 0)},
		"DL3": {"pos": "DL", "at": Vector2(1, 3)},
		"LB1": {"pos": "LB", "at": Vector2(5, -4)},
		"LB2": {"pos": "LB", "at": Vector2(5, 4)},
		"CB1": {"pos": "CB", "at": Vector2(6, 0), "align": "WR1"},
		"CB2": {"pos": "CB", "at": Vector2(6, 0), "align": "WR2"},
		"S1": {"pos": "S", "at": Vector2(13, -8)},
		"S2": {"pos": "S", "at": Vector2(13, 8)},
	})

	var blockers := {"OL1": _b(), "OL2": _b(), "OL3": _b(), "OL4": _b()}
	var off_plays: Array[PlayDef] = []
	off_plays.append(_play("slants", "Slants", "offense", "SHORT", shotgun, _merge(blockers, {
		"QB": {"type": "pass", "drop": 2.0},
		"WR1": _route(_v([Vector2(2, 0), Vector2(7, 5)])),
		"WR2": _route(_v([Vector2(2, 0), Vector2(7, -5)])),
		"TE": _route(_v([Vector2(3, 0), Vector2(5, 5)])),
		"RB": _b(),
	})))
	off_plays.append(_play("curls", "Curl Flat", "offense", "SHORT", shotgun, _merge(blockers, {
		"QB": {"type": "pass", "drop": 2.0},
		"WR1": _route(_v([Vector2(11, 0), Vector2(9, 1)]), "sit"),
		"WR2": _route(_v([Vector2(8, 0), Vector2(8, 6)])),
		"TE": _route(_v([Vector2(6, 0), Vector2(6, -5)]), "sit"),
		"RB": _route(_v([Vector2(0, -3), Vector2(4, -9)])),
	})))
	off_plays.append(_play("deep_shot", "Deep Shot", "offense", "DEEP", shotgun, _merge(blockers, {
		"QB": {"type": "pass", "drop": 3.0},
		"WR1": _route(_v([Vector2(40, 0)])),
		"WR2": _route(_v([Vector2(10, 0), Vector2(28, -9)])),
		"TE": _route(_v([Vector2(25, 0)])),
		"RB": _b(),
	})))
	off_plays.append(_play("hb_dive", "HB Dive", "offense", "RUN", iform, _merge(blockers, {
		"QB": {"type": "handoff", "to": "RB", "mesh": Vector2(-2.6, 0.6)},
		"RB": {"type": "carry", "path": _v([Vector2(3, 0), Vector2(14, 0)])},
		"TE": _b(), "WR1": _b(), "WR2": _b(),
	})))
	off_plays.append(_play("hb_sweep", "HB Sweep", "offense", "RUN", iform, _merge(blockers, {
		"QB": {"type": "handoff", "to": "RB", "mesh": Vector2(-2.6, 1.2)},
		"RB": {"type": "carry", "path": _v([Vector2(2, 2), Vector2(5, 7), Vector2(8, 9), Vector2(25, 9)])},
		"TE": _b(), "WR1": _b(), "WR2": _b(),
	})))
	off_plays.append(_play("pa_cross", "PA Cross", "offense", "DEEP", iform, _merge(blockers, {
		"QB": {"type": "pass", "drop": 4.0},
		"WR1": _route(_v([Vector2(12, 0), Vector2(12, 16)])),
		"WR2": _route(_v([Vector2(5, 0), Vector2(5, -22)])),
		"TE": _route(_v([Vector2(10, 0), Vector2(20, 8)])),
		"RB": _route(_v([Vector2(1, -2), Vector2(4, -8)])),
	})))

	var rush := {"DL1": _r(), "DL2": _r(), "DL3": _r()}
	var def_plays: Array[PlayDef] = []
	def_plays.append(_play("cover1", "Cover 1 Man", "defense", "MAN", base_d, _merge(rush, {
		"CB1": _m("WR1"), "CB2": _m("WR2"), "LB1": _m("TE"), "LB2": _m("RB"),
		"S1": _z(Vector2(16, 0), Vector2(22, 30)),
		"S2": _z(Vector2(7, 0), Vector2(10, 16)),
	}), ["DEEP", "SHORT"]))
	def_plays.append(_play("cover2", "Cover 2 Zone", "defense", "ZONE", base_d, _merge(rush, {
		"CB1": _z(Vector2(4, -14), Vector2(10, 12)),
		"CB2": _z(Vector2(4, 14), Vector2(10, 12)),
		"LB1": _z(Vector2(7, -5), Vector2(9, 10)),
		"LB2": _z(Vector2(7, 5), Vector2(9, 10)),
		"S1": _z(Vector2(18, -10), Vector2(24, 26)),
		"S2": _z(Vector2(18, 10), Vector2(24, 26)),
	}), ["SHORT"]))
	def_plays.append(_play("cover3", "Cover 3 Zone", "defense", "ZONE", base_d, _merge(rush, {
		"CB1": _z(Vector2(17, -15), Vector2(24, 18)),
		"CB2": _z(Vector2(17, 15), Vector2(24, 18)),
		"S1": _z(Vector2(18, 0), Vector2(24, 18)),
		"S2": _z(Vector2(6, -8), Vector2(10, 12)),
		"LB1": _z(Vector2(6, 0), Vector2(8, 10)),
		"LB2": _z(Vector2(6, 9), Vector2(10, 12)),
	}), ["DEEP"]))
	def_plays.append(_play("lb_blitz", "LB Blitz", "defense", "BLITZ", base_d, _merge(rush, {
		"LB1": _r(), "LB2": _r(),
		"CB1": _m("WR1"), "CB2": _m("WR2"), "S1": _m("TE"),
		"S2": _z(Vector2(16, 0), Vector2(22, 30)),
	}), ["RUN"]))

	var ob := PlaybookDef.new()
	ob.id = "offense_basic"
	ob.plays = off_plays
	_save(ob, "res://data/plays/offense_playbook.tres")
	var db := PlaybookDef.new()
	db.id = "defense_basic"
	db.plays = def_plays
	_save(db, "res://data/plays/defense_playbook.tres")
	print("Playbooks built: %d offense, %d defense" % [off_plays.size(), def_plays.size()])
	quit()


func _formation(id: String, name: String, side: String, slots: Dictionary) -> FormationDef:
	var f := FormationDef.new()
	f.id = id
	f.display_name = name
	f.side = side
	f.slots = slots
	return _save(f, "res://data/formations/%s.tres" % id) as FormationDef


func _play(id: String, name: String, side: String, cat: String, form: FormationDef, asg: Dictionary,
		counters: Array = [], tags: Array = []) -> PlayDef:
	var p := PlayDef.new()
	p.counters = PackedStringArray(counters)
	p.tags = PackedStringArray(tags)
	p.id = id
	p.display_name = name
	p.side = side
	p.category = cat
	p.formation = form
	p.assignments = asg
	return _save(p, "res://data/plays/%s/%s.tres" % [side, id]) as PlayDef


## Saves, then reloads so later references point at the file (ext_resource) instead of embedding.
func _save(res: Resource, path: String) -> Resource:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("Failed to save %s (%d)" % [path, err])
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)


func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate(true)
	out.merge(b, true)
	return out


func _b() -> Dictionary:
	return {"type": "block"}


func _r() -> Dictionary:
	return {"type": "rush"}


func _m(target: String) -> Dictionary:
	return {"type": "man", "target": target}


func _z(center: Vector2, size: Vector2) -> Dictionary:
	return {"type": "zone", "center": center, "size": size}


func _route(path: PackedVector2Array, end := "continue") -> Dictionary:
	return {"type": "route", "path": path, "end": end}


func _v(points: Array) -> PackedVector2Array:
	return PackedVector2Array(points)
