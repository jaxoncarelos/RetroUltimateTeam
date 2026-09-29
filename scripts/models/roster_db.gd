class_name RosterDB
extends RefCounted
## Parses data/roster.csv (skipping '#' comments and blank lines; blank cells = position
## defaults; optional `age`/`pot` columns drive development, optional skin/hair/hair_color/
## beard/visor columns the look), reports bad rows instead of
## crashing, fills a team's thin spots with generated depth players only as a last resort,
## and builds the card catalog (one base card per player + Prime cards for stars).
## Node-free (unit-tested).

const ROSTER_PATH := "res://data/roster.csv"
const POSITIONS := ["QB", "RB", "WR", "TE", "OL", "DL", "LB", "CB", "S", "K"]
## Players each team needs per position to fill a lineup (+ a little depth).
const NEEDED := {"QB": 1, "RB": 1, "WR": 2, "TE": 1, "OL": 4, "DL": 3, "LB": 2, "CB": 2, "S": 2, "K": 1}
const JERSEY_RANGES := {"QB": [2, 19], "RB": [20, 39], "WR": [10, 19], "TE": [80, 89], "OL": [60, 79],
		"DL": [90, 99], "LB": [40, 59], "CB": [20, 39], "S": [20, 49], "K": [1, 9]}

var players: Dictionary = {}     ## id -> PlayerData
var by_team: Dictionary = {}     ## abbr -> Array[PlayerData]
var cards: Dictionary = {}       ## card id -> CardDef
var errors: Array[String] = []


## Parses CSV text; valid rows are added, invalid ones recorded in `errors`.
func parse(text: String, team_abbrs: Array = []) -> void:
	var header := PackedStringArray()
	var line_no := 0
	for raw in text.split("\n"):
		line_no += 1
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var cols := line.split(",")
		if header.is_empty():
			header = cols
			continue
		if cols.size() != header.size():
			errors.append("line %d: %d columns, expected %d" % [line_no, cols.size(), header.size()])
			continue
		var row := {}
		for i in header.size():
			row[header[i]] = cols[i].strip_edges()
		var pos: String = row.get("pos", "")
		var team: String = row.get("team", "")
		var id: String = row.get("id", "")
		if id == "" or players.has(id):
			errors.append("line %d: missing or duplicate id '%s'" % [line_no, id])
			continue
		if pos not in POSITIONS:
			errors.append("line %d: bad position '%s'" % [line_no, pos])
			continue
		if not team_abbrs.is_empty() and team not in team_abbrs:
			errors.append("line %d: unknown team '%s'" % [line_no, team])
			continue
		if not str(row.get("ovr", "")).is_valid_int():
			errors.append("line %d: bad ovr" % line_no)
			continue
		var explicit := {}
		for a in RatingModel.ATTRS:
			var v: String = row.get(a, "")
			if v != "" and v.is_valid_int():
				explicit[a] = int(v)
		var p := PlayerData.create(id, row.get("name", id), team, pos, int(row.get("jersey", "0")),
				clampi(int(row["ovr"]), 40, 99), explicit)
		var age_s: String = row.get("age", "")
		var pot_s: String = row.get("pot", "")
		p.set_development(int(age_s) if age_s.is_valid_int() else 0, int(pot_s) if pot_s.is_valid_int() else 0)
		p.look = PlayerData.parse_look(row)
		_add(p)


func load_file(path := ROSTER_PATH, team_abbrs: Array = []) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("cannot open %s" % path)
		return
	parse(f.get_as_text(), team_abbrs)


func _add(p: PlayerData) -> void:
	players[p.id] = p
	if not by_team.has(p.team):
		by_team[p.team] = []
	by_team[p.team].append(p)


## Average OVR of a team's real (CSV) players, or `fallback`.
func real_core_ovr(abbr: String, fallback := 74) -> int:
	var sum := 0
	var n := 0
	for p: PlayerData in by_team.get(abbr, []):
		if not p.generated:
			sum += p.ovr
			n += 1
	return fallback if n == 0 else int(round(float(sum) / n))


## Last-resort generated depth players ("KC OL1") for positions where the CSV is too thin
## to field a lineup. Never granted as starters, never in packs.
func fill_depth(team_abbrs: Array) -> void:
	for abbr in team_abbrs:
		var have := {}
		for p: PlayerData in by_team.get(abbr, []):
			have[p.pos] = int(have.get(p.pos, 0)) + 1
		var base := real_core_ovr(abbr) - 8
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(abbr)
		var used_numbers := {}
		for p: PlayerData in by_team.get(abbr, []):
			used_numbers[p.jersey] = true
		for pos in NEEDED:
			for i in range(int(have.get(pos, 0)), int(NEEDED[pos])):
				var r: Array = JERSEY_RANGES[pos]
				var num := rng.randi_range(r[0], r[1])
				var tries := 0
				while used_numbers.has(num) and tries < 30:
					num = rng.randi_range(r[0], r[1])
					tries += 1
				used_numbers[num] = true
				var ovr := clampi(base + rng.randi_range(-4, 4), 58, 84)
				var id := "gen_%s_%s_%d" % [abbr.to_lower(), pos.to_lower(), i + 1]
				var p := PlayerData.create(id, "%s %s%d" % [abbr, pos, i + 1], abbr, pos, num, ovr)
				p.generated = true
				_add(p)


## Base card of every player (generated depth included, so a thin team can still field a
## lineup; packs never pull them) plus a Prime card for real stars (CardRules.has_prime).
func build_catalog() -> void:
	cards.clear()
	for id in players:
		var p: PlayerData = players[id]
		var b := CardDef.build_program(p, CardRules.PROGRAM_BASE)
		cards[b.id] = b
		if not p.generated and CardRules.has_prime(p.ovr):
			var pr := CardDef.build_program(p, CardRules.PROGRAM_PRIME)
			cards[pr.id] = pr
	# One CHAMP (99) card per team: the Super Bowl reward for that franchise's star.
	for abbr in by_team:
		var star := franchise_star(abbr)
		if star != null:
			var ch := CardDef.build_program(star, CardRules.PROGRAM_CHAMP)
			cards[ch.id] = ch


## Card ids at `tier` (derived from card OVR), real players only.
func card_ids_of_tier(tier: int) -> Array[String]:
	var out: Array[String] = []
	for cid in cards:
		var c: CardDef = cards[cid]
		if c.tier == tier and not c.is_champ() and not players[c.player_id].generated:
			out.append(cid)
	return out


## A team's best real player (highest OVR; ties go to the higher-value position).
func franchise_star(abbr: String) -> PlayerData:
	var best: PlayerData = null
	for p: PlayerData in by_team.get(abbr, []):
		if p.generated:
			continue
		if best == null or p.ovr > best.ovr or (p.ovr == best.ovr and
				POSITIONS.find(p.pos) < POSITIONS.find(best.pos)):
			best = p
	return best


## A team's real lineup (auto-best by real OVR): slot -> {id, name, jersey, attrs, ovr, pos, look}.
func team_entries(abbr: String) -> Dictionary:
	var cands := []
	for p: PlayerData in by_team.get(abbr, []):
		cands.append({"key": p, "pos": p.pos, "ovr": p.ovr})
	var best := TeamRating.auto_best(cands)
	var out := {}
	for slot in best:
		var p: PlayerData = best[slot]["key"]
		out[slot] = {"id": p.id, "name": p.short_name(), "jersey": p.jersey, "attrs": p.attrs, "ovr": p.ovr,
				"pos": p.pos, "look": p.look}
	return out


func team_ovr(abbr: String) -> int:
	return TeamRating.team_ovr(team_entries(abbr))


func league_avg_ovr() -> int:
	var sum := 0
	var n := 0
	for abbr in by_team:
		sum += team_ovr(abbr)
		n += 1
	return 70 if n == 0 else int(round(float(sum) / n))
