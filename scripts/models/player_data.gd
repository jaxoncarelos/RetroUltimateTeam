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
var age := 0             ## 0 = unknown
var pot := 60            ## potential (development ceiling); = ovr for veterans
## Appearance for portraits/sprites (roster.csv skin/hair/hair_color/beard/visor). Only the
## known keys are present: {"skin": 1-6 light->dark, "hair", "hair_color", "beard", "visor"}.
## Missing keys fall back to the seeded random look (ArtGen).
var look: Dictionary = {}

const LOOK_KEYS := ["hair", "hair_color", "beard", "visor"]


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
	p.pot = p_ovr
	return p


## Sets age and potential (pot <= 0 = derived from age via CardRules.default_pot).
func set_development(p_age: int, p_pot := 0) -> void:
	age = p_age
	pot = maxi(ovr, p_pot) if p_pot > 0 else CardRules.default_pot(ovr, p_age)


## Young and not yet at his ceiling (UI "ROOKIE"/"PROSPECT" badge).
func is_prospect() -> bool:
	return pot > ovr


## Appearance dict from a CSV row (blank-safe; invalid skin values are dropped).
static func parse_look(row: Dictionary) -> Dictionary:
	var out := {}
	var skin := str(row.get("skin", "")).strip_edges()
	if skin.is_valid_int() and int(skin) >= 1 and int(skin) <= 6:
		out["skin"] = int(skin)
	for k in LOOK_KEYS:
		var v := str(row.get(k, "")).strip_edges().to_lower()
		if v != "":
			out[k] = v
	return out


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
