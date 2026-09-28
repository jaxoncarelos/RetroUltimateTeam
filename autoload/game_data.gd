extends Node
## Loads roster.csv + teams.json once at boot. Lookups for players, teams, cards and lineups.
## Bad roster rows are reported with push_warning, never crash the game.

var teams: Dictionary = {}   ## abbr -> TeamData
var db := RosterDB.new()
var _league_avg := -1


func _ready() -> void:
	teams = TeamData.load_all()
	db.load_file(RosterDB.ROSTER_PATH, teams.keys())
	for e in db.errors:
		push_warning("roster.csv: " + e)
	db.fill_depth(teams.keys())
	db.build_catalog()
	ArtGen.register_looks(db.players)


func player(id: String) -> PlayerData:
	return db.players.get(id)


func card(id: String) -> CardDef:
	return db.cards.get(id)


func team(abbr: String) -> TeamData:
	return teams.get(abbr)


func team_players(abbr: String) -> Array:
	return db.by_team.get(abbr, [])


## What picking `abbr` gives you (team picker): {"star": PlayerData (franchise star card),
## "ovr": starting team OVR, "count": number of starter cards}.
func starter_preview(abbr: String) -> Dictionary:
	var ids := Collection.starter_card_ids(db, abbr)
	return {"star": db.franchise_star(abbr), "ovr": Collection.squad_ovr(db, ids), "count": ids.size()}


func league_avg_ovr() -> int:
	if _league_avg < 0:
		_league_avg = db.league_avg_ovr()
	return _league_avg


## Match lineup for a CPU opponent, rescaled for difficulty against `your_ovr`.
func opponent_lineup(abbr: String, your_ovr: int, difficulty: int) -> Dictionary:
	var entries := db.team_entries(abbr)
	var real := TeamRating.team_ovr(entries)
	var eff := TeamRating.opponent_effective_ovr(your_ovr, difficulty, real, league_avg_ovr())
	var scaled := TeamRating.rescale_entries(entries, real, eff)
	var out := TeamRating.match_lineup(scaled)
	out["ovr"] = eff
	return out


## Match lineup of a team's real players (no rescaling) — CPU vs CPU and the sandbox.
func real_lineup(abbr: String) -> Dictionary:
	var entries := db.team_entries(abbr)
	var out := TeamRating.match_lineup(entries)
	out["ovr"] = TeamRating.team_ovr(entries)
	return out
