class_name PlayerData
extends RefCounted
## One real (or generated depth) player, built from a roster.csv row. Blank attributes are
## filled from the position profile (RatingModel.fill_attrs).

var id := ""
var name := ""
var team := ""
var pos := ""
var jersey := 0
var ovr := 60
var attrs: Dictionary = {}
var generated := false   ## depth filler created by GameData (not in the CSV)


static func create(p_id: String, p_name: String, p_team: String, p_pos: String, p_jersey: int,
		p_ovr: int, explicit: Dictionary = {}) -> PlayerData:
	var p := PlayerData.new()
	p.id = p_id
	p.name = p_name
	p.team = p_team
	p.pos = p_pos
	p.jersey = p_jersey
	p.ovr = p_ovr
	p.attrs = RatingModel.fill_attrs(p_pos, p_ovr, explicit)
	return p


const SUFFIXES := ["JR.", "JR", "SR.", "II", "III", "IV"]


## Surname without generational suffixes ("HARRISON" for "Marvin Harrison Jr.").
func last_name() -> String:
	var parts := name.to_upper().split(" ", false)
	while parts.size() > 1 and parts[parts.size() - 1] in SUFFIXES:
		parts.remove_at(parts.size() - 1)
	return parts[parts.size() - 1] if parts.size() > 0 else name.to_upper()


## "P. MAHOMES" style label for the HUD.
func short_name() -> String:
	var parts := name.split(" ", false)
	if parts.size() < 2:
		return name.to_upper()
	return ("%s. %s" % [parts[0].left(1), " ".join(parts.slice(1))]).to_upper()
