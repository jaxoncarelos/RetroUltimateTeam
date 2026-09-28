class_name TeamData
extends RefCounted
## One NFL team's identity and colors, loaded from res://data/teams.json.

const PATH := "res://data/teams.json"

var abbr := ""
var city := ""
var team_name := ""
var conf := ""
var div := ""
var primary := Color.RED
var secondary := Color.WHITE
var helmet := Color.RED
var pants := Color.WHITE


static func load_all() -> Dictionary:
	var out := {}
	var text := FileAccess.get_file_as_string(PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Array:
		push_error("teams.json failed to parse")
		return out
	for row in parsed:
		var t := TeamData.new()
		t.abbr = row.get("abbr", "")
		t.city = row.get("city", "")
		t.team_name = row.get("name", "")
		t.conf = row.get("conf", "")
		t.div = row.get("div", "")
		t.primary = Color(row.get("primary", "#ff0000"))
		t.secondary = Color(row.get("secondary", "#ffffff"))
		t.helmet = Color(row.get("helmet", row.get("primary", "#ff0000")))
		t.pants = Color(row.get("pants", "#ffffff"))
		out[t.abbr] = t
	return out


func uniform_colors() -> Dictionary:
	return {"primary": primary, "secondary": secondary, "helmet": helmet, "pants": pants}


## Road whites: white jersey trimmed in the team color, same helmet. The away team wears these
## on the field so both sides always read apart (KC red vs TB red, etc.).
func away_colors() -> Dictionary:
	var trim := primary if primary.get_luminance() < 0.8 else secondary
	return {"primary": Color("#f2f2f2"), "secondary": trim, "helmet": helmet, "pants": pants}
