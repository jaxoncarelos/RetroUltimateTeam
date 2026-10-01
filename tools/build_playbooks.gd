extends SceneTree
## Bootstrap generator for formations/plays/playbooks (.tres).
## Run:  godot --headless --path . --script res://tools/build_playbooks.gd
## After generation the .tres files are the source of truth (edit them in the editor);
## re-running this script overwrites them.



func _init() -> void:
	# ---------------------------------------------------------------- offense formations
	# Slots never change (they are lineup slots); formations only move them.
	var line := {
		"OL1": {"pos": "OL", "at": Vector2(-1, -3.6)},
		"OL2": {"pos": "OL", "at": Vector2(-1, -1.2)},
		"OL3": {"pos": "OL", "at": Vector2(-1, 1.2)},
		"OL4": {"pos": "OL", "at": Vector2(-1, 3.6)},
	}
	var shotgun := _formation("off_shotgun", "Shotgun", "offense", _merge(line, {
		"QB": {"pos": "QB", "at": Vector2(-4, 0)},
		"RB": {"pos": "RB", "at": Vector2(-4, 1.6)},
		"TE": {"pos": "TE", "at": Vector2(-1, 6.2)},
		"WR1": {"pos": "WR", "at": Vector2(-0.5, -15)},
		"WR2": {"pos": "WR", "at": Vector2(-0.5, 13)},
	}))
	var iform := _formation("off_iform", "I-Form", "offense", _merge(line, {
		"QB": {"pos": "QB", "at": Vector2(-1, 0)},
		"RB": {"pos": "RB", "at": Vector2(-6, 0)},
		"TE": {"pos": "TE", "at": Vector2(-1, 6.2)},
		"WR1": {"pos": "WR", "at": Vector2(-0.5, -15)},
		"WR2": {"pos": "WR", "at": Vector2(-0.5, 14)},
	}))
	var single := _formation("off_singleback", "Singleback", "offense", _merge(line, {
		"QB": {"pos": "QB", "at": Vector2(-1, 0)},
		"RB": {"pos": "RB", "at": Vector2(-5.5, 0)},
		"TE": {"pos": "TE", "at": Vector2(-1, 6.2)},
		"WR1": {"pos": "WR", "at": Vector2(-0.5, -14)},
		"WR2": {"pos": "WR", "at": Vector2(-0.5, 12)},
	}))
	var trips := _formation("off_trips", "Trips", "offense", _merge(line, {
		"QB": {"pos": "QB", "at": Vector2(-4, 0)},
		"RB": {"pos": "RB", "at": Vector2(-4, -1.6)},
		"TE": {"pos": "TE", "at": Vector2(-1, 9)},
		"WR1": {"pos": "WR", "at": Vector2(-0.5, -15)},
		"WR2": {"pos": "WR", "at": Vector2(-0.5, 16)},
	}))
	var jumbo := _formation("off_goal_line", "Goal Line", "offense", _merge(line, {
		"QB": {"pos": "QB", "at": Vector2(-1, 0)},
		"RB": {"pos": "RB", "at": Vector2(-5, 0)},
		"TE": {"pos": "TE", "at": Vector2(-1, 6.2)},
		"WR1": {"pos": "WR", "at": Vector2(-1, -6.2)},
		"WR2": {"pos": "WR", "at": Vector2(-2, 8.2)},
	}))

	# ---------------------------------------------------------------- defense formations
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
	var nickel := _formation("def_nickel", "Nickel", "defense", {
		"DL1": {"pos": "DL", "at": Vector2(1, -2.5)},
		"DL2": {"pos": "DL", "at": Vector2(1, 0)},
		"DL3": {"pos": "DL", "at": Vector2(1, 2.5)},
		"LB1": {"pos": "LB", "at": Vector2(5, -2)},
		"LB2": {"pos": "LB", "at": Vector2(4, 0), "align": "TE"},
		"CB1": {"pos": "CB", "at": Vector2(7, 0), "align": "WR1"},
		"CB2": {"pos": "CB", "at": Vector2(7, 0), "align": "WR2"},
		"S1": {"pos": "S", "at": Vector2(14, -9)},
		"S2": {"pos": "S", "at": Vector2(14, 9)},
	})
	var dime := _formation("def_dime", "Dime", "defense", {
		"DL1": {"pos": "DL", "at": Vector2(1, -2)},
		"DL2": {"pos": "DL", "at": Vector2(1.5, 0)},
		"DL3": {"pos": "DL", "at": Vector2(1, 2)},
		"LB1": {"pos": "LB", "at": Vector2(8, -6)},
		"LB2": {"pos": "LB", "at": Vector2(8, 6)},
		"CB1": {"pos": "CB", "at": Vector2(10, 0), "align": "WR1"},
		"CB2": {"pos": "CB", "at": Vector2(10, 0), "align": "WR2"},
		"S1": {"pos": "S", "at": Vector2(20, -8)},
		"S2": {"pos": "S", "at": Vector2(20, 8)},
	})
	var goal_d := _formation("def_goal_line", "Goal Line", "defense", {
		"DL1": {"pos": "DL", "at": Vector2(1, -3)},
		"DL2": {"pos": "DL", "at": Vector2(1, 0)},
		"DL3": {"pos": "DL", "at": Vector2(1, 3)},
		"LB1": {"pos": "LB", "at": Vector2(3, -4)},
		"LB2": {"pos": "LB", "at": Vector2(3, 4)},
		"CB1": {"pos": "CB", "at": Vector2(2.5, 0), "align": "WR1"},
		"CB2": {"pos": "CB", "at": Vector2(2.5, 0), "align": "WR2"},
		"S1": {"pos": "S", "at": Vector2(5, -2)},
		"S2": {"pos": "S", "at": Vector2(5, 3)},
	})

	# ---------------------------------------------------------------- offense plays
	var blockers := {"OL1": _b(), "OL2": _b(), "OL3": _b(), "OL4": _b()}
	var off_plays: Array[PlayDef] = []
	# Runs
	off_plays.append(_play("qb_sneak", "QB Sneak", "offense", "RUN", jumbo, _merge(blockers, {
		"QB": {"type": "sneak", "path": _v([Vector2(3, 0), Vector2(10, 0)])},
		"RB": _b(), "TE": _b(), "WR1": _b(), "WR2": _b(),
	}), [], ["short_yardage", "goal_line"]))
	off_plays.append(_play("hb_dive", "HB Dive", "offense", "RUN", iform, _merge(blockers, {
		"QB": {"type": "handoff", "to": "RB", "mesh": Vector2(-2.6, 0.6)},
		"RB": {"type": "carry", "path": _v([Vector2(3, 0), Vector2(14, 0)])},
		"TE": _b(), "WR1": _b(), "WR2": _b(),
	}), [], ["short_yardage"]))
	off_plays.append(_play("gl_power", "GL Power", "offense", "RUN", jumbo, _merge(blockers, {
		"QB": {"type": "handoff", "to": "RB", "mesh": Vector2(-2.4, 0.8)},
		"RB": {"type": "carry", "path": _v([Vector2(2.5, 1.2), Vector2(5, 4.5), Vector2(14, 5.5)])},
		"TE": _b(), "WR1": _b(), "WR2": _b(),
	}), [], ["short_yardage", "goal_line"]))
	off_plays.append(_play("hb_draw", "HB Draw", "offense", "RUN", shotgun, _merge(blockers, {
		"QB": {"type": "handoff", "to": "RB", "mesh": Vector2(-5.6, 0.9), "delay": 0.5},
		"RB": {"type": "carry", "delay": 0.45, "path": _v([Vector2(-1.4, -0.6), Vector2(3, -1.6), Vector2(16, -1.6)])},
		"TE": _b(),
		"WR1": _route(_v([Vector2(14, 0)])),
		"WR2": _route(_v([Vector2(14, 0)])),
	}), [], ["draw"]))
	off_plays.append(_play("counter", "Counter", "offense", "RUN", single, _merge(blockers, {
		"QB": {"type": "handoff", "to": "RB", "mesh": Vector2(-3.6, 0.3)},
		"RB": {"type": "carry", "path": _v([Vector2(0.6, -1.2), Vector2(2.4, 1.8), Vector2(5.5, 3.5), Vector2(18, 4)])},
		"TE": _b(), "WR1": _b(), "WR2": _b(),
	})))
	off_plays.append(_play("toss", "Toss Stretch", "offense", "RUN", single, _merge(blockers, {
		"QB": {"type": "handoff", "to": "RB", "mesh": Vector2(-2.6, 1.4), "range": 4.5},
		"RB": {"type": "carry", "path": _v([Vector2(1.5, 3), Vector2(4, 7), Vector2(8, 9), Vector2(22, 10)])},
		"TE": _b(), "WR1": _b(), "WR2": _b(),
	}), [], ["outside"]))
	off_plays.append(_play("hb_sweep", "HB Sweep", "offense", "RUN", iform, _merge(blockers, {
		"QB": {"type": "handoff", "to": "RB", "mesh": Vector2(-2.6, 1.2)},
		"RB": {"type": "carry", "path": _v([Vector2(2, 2), Vector2(5, 7), Vector2(8, 9), Vector2(25, 9)])},
		"TE": _b(), "WR1": _b(), "WR2": _b(),
	}), [], ["outside"]))
	# Short passes
	off_plays.append(_play("screen", "HB Screen", "offense", "SHORT", shotgun, _merge(blockers, {
		"QB": {"type": "pass", "drop": 3.0},
		"RB": _route(_v([Vector2(0.5, -2.5), Vector2(-0.5, -8)]), "sit", 0.5),
		"WR1": _route(_v([Vector2(12, 0)])),
		"WR2": _route(_v([Vector2(12, 0)])),
		"TE": _b(),
	}), [], ["screen"]))
	off_plays.append(_play("slants", "Slants", "offense", "SHORT", shotgun, _merge(blockers, {
		"QB": {"type": "pass", "drop": 2.0},
		"WR1": _route(_v([Vector2(2, 0), Vector2(7, 5)])),
		"WR2": _route(_v([Vector2(2, 0), Vector2(7, -5)])),
		"TE": _route(_v([Vector2(3, 0), Vector2(5, 5)])),
		"RB": _b(),
	}), [], ["quick"]))
	off_plays.append(_play("mesh", "Mesh", "offense", "SHORT", trips, _merge(blockers, {
		"QB": {"type": "pass", "drop": 2.0},
		"WR1": _route(_v([Vector2(2, 0), Vector2(4, 8), Vector2(5, 24)])),
		"TE": _route(_v([Vector2(3, 0), Vector2(5, -8), Vector2(6, -24)])),
		"WR2": _route(_v([Vector2(10, 0), Vector2(10, -6)]), "sit"),
		"RB": _route(_v([Vector2(0, 3), Vector2(3, 8)])),
	}), [], ["quick"]))
	off_plays.append(_play("smash", "Smash", "offense", "SHORT", single, _merge(blockers, {
		"QB": {"type": "pass", "drop": 3.0},
		"WR1": _route(_v([Vector2(5, 0), Vector2(4, 0.5)]), "sit"),
		"WR2": _route(_v([Vector2(5, 0), Vector2(4, -0.5)]), "sit"),
		"TE": _route(_v([Vector2(8, 0), Vector2(15, 6)])),
		"RB": _route(_v([Vector2(1, -2), Vector2(3, -7)])),
	})))
	off_plays.append(_play("curls", "Curl Flat", "offense", "SHORT", shotgun, _merge(blockers, {
		"QB": {"type": "pass", "drop": 2.0},
		"WR1": _route(_v([Vector2(11, 0), Vector2(9, 1)]), "sit"),
		"WR2": _route(_v([Vector2(8, 0), Vector2(8, 6)])),
		"TE": _route(_v([Vector2(6, 0), Vector2(6, -5)]), "sit"),
		"RB": _route(_v([Vector2(0, -3), Vector2(4, -9)])),
	})))
	# Deep passes
	off_plays.append(_play("four_verts", "Four Verts", "offense", "DEEP", trips, _merge(blockers, {
		"QB": {"type": "pass", "drop": 3.0},
		"WR1": _route(_v([Vector2(40, 0)])),
		"WR2": _route(_v([Vector2(40, 0)])),
		"TE": _route(_v([Vector2(4, -3), Vector2(40, -3)])),
		"RB": _route(_v([Vector2(1, -4), Vector2(6, -8), Vector2(30, -10)])),
	}), [], ["deep"]))
	off_plays.append(_play("post_wheel", "Post Wheel", "offense", "DEEP", shotgun, _merge(blockers, {
		"QB": {"type": "pass", "drop": 3.0},
		"WR1": _route(_v([Vector2(10, 0), Vector2(26, 9)])),
		"RB": _route(_v([Vector2(1, 4), Vector2(3, 9), Vector2(30, 11)])),
		"WR2": _route(_v([Vector2(12, 0), Vector2(10, -1)]), "sit"),
		"TE": _b(),
	}), [], ["deep"]))
	off_plays.append(_play("flood", "Flood", "offense", "DEEP", trips, _merge(blockers, {
		"QB": {"type": "pass", "drop": 3.0},
		"WR2": _route(_v([Vector2(30, 0)])),
		"TE": _route(_v([Vector2(12, 0), Vector2(13, 6)])),
		"RB": _route(_v([Vector2(0, 5), Vector2(3, 15)])),
		"WR1": _route(_v([Vector2(12, 0), Vector2(14, 12)])),
	})))
	off_plays.append(_play("pa_cross", "PA Cross", "offense", "DEEP", iform, _merge(blockers, {
		"QB": {"type": "pass", "drop": 4.0, "fake": true},
		"WR1": _route(_v([Vector2(12, 0), Vector2(12, 16)])),
		"WR2": _route(_v([Vector2(5, 0), Vector2(5, -22)])),
		"TE": _route(_v([Vector2(10, 0), Vector2(20, 8)])),
		"RB": _route(_v([Vector2(1, -2), Vector2(4, -8)])),
	}), [], ["play_action"]))
	off_plays.append(_play("deep_shot", "Deep Shot", "offense", "DEEP", shotgun, _merge(blockers, {
		"QB": {"type": "pass", "drop": 3.0},
		"WR1": _route(_v([Vector2(40, 0)])),
		"WR2": _route(_v([Vector2(10, 0), Vector2(28, -9)])),
		"TE": _route(_v([Vector2(25, 0)])),
		"RB": _b(),
	}), [], ["deep"]))
	off_plays.append(_play("fade", "Fade", "offense", "DEEP", jumbo, _merge(blockers, {
		"QB": {"type": "pass", "drop": 2.5},
		"WR1": _route(_v([Vector2(2, -2), Vector2(14, -8)])),
		"WR2": _route(_v([Vector2(2, 2), Vector2(14, 9)])),
		"TE": _route(_v([Vector2(4, 0), Vector2(4, -5)]), "sit"),
		"RB": _b(),
	}), [], ["goal_line", "red_zone"]))
	# Pass concepts that spread the ball: every eligible runs a route on most of them.
	off_plays.append(_play("inside_zone", "Inside Zone", "offense", "RUN", shotgun, _merge(blockers, {
		"QB": {"type": "handoff", "to": "RB", "mesh": Vector2(-4.4, 0.6)},
		"RB": {"type": "carry", "path": _v([Vector2(2.5, -1.4), Vector2(5, -2), Vector2(16, -2.5)])},
		"TE": _b(),
		"WR1": _route(_v([Vector2(12, 0)])),
		"WR2": _route(_v([Vector2(12, 0)])),
	})))
	off_plays.append(_play("stick", "Stick", "offense", "SHORT", single, _merge(blockers, {
		"QB": {"type": "pass", "drop": 2.0},
		"WR1": _route(_v([Vector2(6, 0), Vector2(6, -5)])),
		"TE": _route(_v([Vector2(6, 0), Vector2(5, -1)]), "sit"),
		"WR2": _route(_v([Vector2(35, 0)])),
		"RB": _route(_v([Vector2(1, 4), Vector2(3, 10)])),
	}), [], ["quick", "red_zone"]))
	off_plays.append(_play("levels", "Levels", "offense", "SHORT", trips, _merge(blockers, {
		"QB": {"type": "pass", "drop": 2.5},
		"WR2": _route(_v([Vector2(5, 0), Vector2(5, -12)])),
		"TE": _route(_v([Vector2(12, 0), Vector2(12, -14)])),
		"WR1": _route(_v([Vector2(35, 0)])),
		"RB": _route(_v([Vector2(0, -4), Vector2(2, -10)])),
	})))
	off_plays.append(_play("drive", "Drive", "offense", "SHORT", shotgun, _merge(blockers, {
		"QB": {"type": "pass", "drop": 2.5},
		"WR1": _route(_v([Vector2(3, 0), Vector2(4, 26)])),
		"TE": _route(_v([Vector2(12, 0), Vector2(12, -14)])),
		"WR2": _route(_v([Vector2(35, 0)])),
		"RB": _route(_v([Vector2(2, -2), Vector2(4, -4)]), "sit"),
	}), [], ["red_zone"]))
	off_plays.append(_play("comebacks", "Comebacks", "offense", "SHORT", shotgun, _merge(blockers, {
		"QB": {"type": "pass", "drop": 3.0},
		"WR1": _route(_v([Vector2(14, 0), Vector2(12, -2)]), "sit"),
		"WR2": _route(_v([Vector2(14, 0), Vector2(12, 2)]), "sit"),
		"TE": _route(_v([Vector2(25, 0)])),
		"RB": _route(_v([Vector2(2, -3), Vector2(4, -5)]), "sit"),
	})))
	off_plays.append(_play("hb_angle", "HB Angle", "offense", "SHORT", shotgun, _merge(blockers, {
		"QB": {"type": "pass", "drop": 2.0},
		"RB": _route(_v([Vector2(2, 3), Vector2(4, 1), Vector2(6, -4)])),
		"WR1": _route(_v([Vector2(30, 0)])),
		"WR2": _route(_v([Vector2(2, 0), Vector2(7, -5)])),
		"TE": _route(_v([Vector2(2, 0), Vector2(4, -14)])),
	}), [], ["quick"]))
	off_plays.append(_play("bubble", "WR Bubble", "offense", "SHORT", trips, _merge(blockers, {
		"QB": {"type": "pass", "drop": 1.0},
		"WR2": _route(_v([Vector2(-1.5, -2), Vector2(-1, -5)]), "sit"),
		"TE": _b(),
		"WR1": _route(_v([Vector2(30, 0)])),
		"RB": _route(_v([Vector2(2, -3), Vector2(4, -6)]), "sit"),
	}), [], ["screen", "quick"]))
	off_plays.append(_play("dagger", "Dagger", "offense", "DEEP", single, _merge(blockers, {
		"QB": {"type": "pass", "drop": 3.0},
		"TE": _route(_v([Vector2(28, 0)])),
		"WR2": _route(_v([Vector2(14, 0), Vector2(14, -14)])),
		"WR1": _route(_v([Vector2(13, 0), Vector2(11, 1)]), "sit"),
		"RB": _route(_v([Vector2(2, 3), Vector2(4, 6)]), "sit"),
	}), [], ["deep"]))
	off_plays.append(_play("y_cross", "Y Cross", "offense", "DEEP", trips, _merge(blockers, {
		"QB": {"type": "pass", "drop": 3.0},
		"TE": _route(_v([Vector2(6, 0), Vector2(16, -20), Vector2(18, -34)])),
		"WR1": _route(_v([Vector2(12, 0), Vector2(26, 10)])),
		"WR2": _route(_v([Vector2(10, 0), Vector2(8, -1)]), "sit"),
		"RB": _route(_v([Vector2(1, 4), Vector2(3, 9)])),
	})))
	off_plays.append(_play("sail", "Sail", "offense", "DEEP", trips, _merge(blockers, {
		"QB": {"type": "pass", "drop": 3.0},
		"WR2": _route(_v([Vector2(35, 0)])),
		"TE": _route(_v([Vector2(10, 0), Vector2(18, 8)])),
		"RB": _route(_v([Vector2(1, 5), Vector2(3, 14)])),
		"WR1": _route(_v([Vector2(12, 0), Vector2(12, 14)])),
	})))
	off_plays.append(_play("sluggo", "Slant & Go", "offense", "DEEP", shotgun, _merge(blockers, {
		"QB": {"type": "pass", "drop": 3.5},
		"WR1": _route(_v([Vector2(3, 0), Vector2(5, 3), Vector2(32, 2)])),
		"WR2": _route(_v([Vector2(6, 0), Vector2(5, 0)]), "sit"),
		"TE": _route(_v([Vector2(7, 0), Vector2(7, 6)])),
		"RB": _b(),
	}), [], ["deep"]))
	off_plays.append(_play("pa_seam", "PA TE Seam", "offense", "DEEP", single, _merge(blockers, {
		"QB": {"type": "pass", "drop": 4.0, "fake": true},
		"TE": _route(_v([Vector2(30, -1)])),
		"WR1": _route(_v([Vector2(15, 0), Vector2(15, 14)])),
		"WR2": _route(_v([Vector2(35, 0)])),
		"RB": _b(),
	}), [], ["play_action", "deep"]))

	# ---------------------------------------------------------------- defense plays
	var rush := {"DL1": _r(), "DL2": _r(), "DL3": _r()}
	var def_plays: Array[PlayDef] = []
	def_plays.append(_play("cover0", "Cover 0 Blitz", "defense", "BLITZ", base_d, _merge(rush, {
		"LB1": _r(), "LB2": _r(),
		"CB1": _m("WR1", true), "CB2": _m("WR2", true), "S1": _m("TE"), "S2": _m("RB"),
	}), ["RUN", "SHORT"], ["blitz"]))
	def_plays.append(_play("cover1", "Cover 1 Man", "defense", "MAN", base_d, _merge(rush, {
		"CB1": _m("WR1"), "CB2": _m("WR2"), "LB1": _m("TE"), "LB2": _m("RB"),
		"S1": _z(Vector2(16, 0), Vector2(22, 30)),
		"S2": _z(Vector2(7, 0), Vector2(10, 16)),
	}), ["DEEP"]))
	def_plays.append(_play("press", "Cover 1 Press", "defense", "MAN", nickel, _merge(rush, {
		"CB1": _m("WR1", true), "CB2": _m("WR2", true), "LB2": _m("TE", true), "LB1": _m("RB"),
		"S1": _z(Vector2(17, 0), Vector2(24, 30)),
		"S2": _z(Vector2(6, 0), Vector2(10, 16)),
	}), ["SHORT"]))
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
	}), ["DEEP"], ["deep"]))
	def_plays.append(_play("cover4", "Cover 4", "defense", "ZONE", nickel, _merge(rush, {
		"CB1": _z(Vector2(16, -17), Vector2(22, 13)),
		"CB2": _z(Vector2(16, 17), Vector2(22, 13)),
		"S1": _z(Vector2(17, -6), Vector2(22, 12)),
		"S2": _z(Vector2(17, 6), Vector2(22, 12)),
		"LB1": _z(Vector2(6, -5), Vector2(9, 12)),
		"LB2": _z(Vector2(6, 5), Vector2(9, 12)),
	}), ["DEEP"], ["deep"]))
	def_plays.append(_play("zone_blitz", "Zone Blitz", "defense", "BLITZ", base_d, {
		"DL1": _r(), "DL3": _r(), "LB1": _r(), "LB2": _r(),
		"DL2": _z(Vector2(5, 0), Vector2(8, 10)),
		"CB1": _z(Vector2(14, -15), Vector2(20, 16)),
		"CB2": _z(Vector2(14, 15), Vector2(20, 16)),
		"S1": _z(Vector2(19, 0), Vector2(22, 20)),
		"S2": _z(Vector2(6, -6), Vector2(10, 14)),
	}, ["SHORT", "RUN"], ["blitz"]))
	def_plays.append(_play("lb_blitz", "LB Blitz", "defense", "BLITZ", base_d, _merge(rush, {
		"LB1": _r(), "LB2": _r(),
		"CB1": _m("WR1"), "CB2": _m("WR2"), "S1": _m("TE"),
		"S2": _z(Vector2(16, 0), Vector2(22, 30)),
	}), ["RUN"], ["blitz"]))
	def_plays.append(_play("prevent", "Prevent", "defense", "ZONE", dime, {
		"DL1": _r(), "DL3": _r(),
		"DL2": _z(Vector2(5, 0), Vector2(8, 12)),
		"LB1": _z(Vector2(11, -8), Vector2(12, 14)),
		"LB2": _z(Vector2(11, 8), Vector2(12, 14)),
		"CB1": _z(Vector2(22, -16), Vector2(22, 16)),
		"CB2": _z(Vector2(22, 16), Vector2(22, 16)),
		"S1": _z(Vector2(28, -6), Vector2(24, 16)),
		"S2": _z(Vector2(28, 6), Vector2(24, 16)),
	}, ["DEEP"], ["prevent", "deep"]))
	def_plays.append(_play("goal_line", "Goal Line", "defense", "BLITZ", goal_d, _merge(rush, {
		"LB1": _r(), "LB2": _r(),
		"CB1": _m("WR1", true), "CB2": _m("WR2", true), "S1": _m("TE"),
		"S2": _z(Vector2(3, 0), Vector2(6, 16)),
	}), ["RUN"], ["goal_line"]))

	var ob := PlaybookDef.new()
	ob.id = "offense_full"
	ob.plays = off_plays
	_save(ob, "res://data/plays/offense_playbook.tres")
	var db := PlaybookDef.new()
	db.id = "defense_full"
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


func _m(target: String, press := false) -> Dictionary:
	if press:
		return {"type": "man", "target": target, "press": true}
	return {"type": "man", "target": target}


func _z(center: Vector2, size: Vector2) -> Dictionary:
	return {"type": "zone", "center": center, "size": size}


func _route(path: PackedVector2Array, end := "continue", delay := 0.0) -> Dictionary:
	if delay > 0.0:
		return {"type": "route", "path": path, "end": end, "delay": delay}
	return {"type": "route", "path": path, "end": end}


func _v(points: Array) -> PackedVector2Array:
	return PackedVector2Array(points)
