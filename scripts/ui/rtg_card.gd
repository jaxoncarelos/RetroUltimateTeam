class_name RtgCard
extends Control
## Your Road to Glory player as a big code-drawn card (CardView style): tier-colored art panel
## with his portrait in your team's colors (gray college colors before the draft), position
## chip, big OVR, dev-trait chip, name plate, number and team strip.

const W := 56
const H := 80
const ART_H := 54

var player: Dictionary = {}     ## RtgRules player dict
var team := ""                  ## "" = not drafted yet
var card_scale := 2
var _portrait: Texture2D
var _t := 0.0


func _init(p_player: Dictionary = {}, p_team := "", p_scale := 2) -> void:
	player = p_player
	team = p_team
	card_scale = p_scale
	custom_minimum_size = Vector2(W, H) * p_scale
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	refresh()


## Rebuilds the portrait (after a look / team change).
func refresh() -> void:
	if player.is_empty():
		return
	_portrait = ArtGen.portrait("rtg:" + str(player.get("name", "")), str(player["pos"]), colors(team),
			int(player.get("jersey", 0)), player.get("look", {}))
	queue_redraw()


## Team uniform colors, or neutral college grays before the draft.
static func colors(abbr: String) -> Dictionary:
	var t: TeamData = GameData.team(abbr) if abbr != "" else null
	if t != null:
		return t.uniform_colors()
	return {"primary": Color("#5a6378"), "secondary": Color("#d8dce6"), "helmet": Color("#3a4152"), "pants": Color("#d8dce6")}


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if player.is_empty():
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * card_scale)
	var o := RtgRules.ovr(str(player["pos"]), player["attrs"])
	var tc := CardView.tier_color(CardRules.tier_for_ovr(o))
	var c := colors(team)
	# Frame and art panel.
	draw_rect(Rect2(0, 0, W, H), UiSkin.SHADOW)
	draw_rect(Rect2(1, 1, W - 2, H - 2), tc.lightened(0.2))
	var art := Rect2(2, 2, W - 4, ART_H - 2)
	for y in int(art.size.y):
		var u := float(y) / art.size.y
		var col := tc.lightened(0.35).lerp(tc.darkened(0.15), u)
		if y % 2 == 1:
			col = col.darkened(0.04)
		draw_rect(Rect2(art.position.x, art.position.y + y, art.size.x, 1), col)
	draw_circle(Vector2(W * 0.5, 38), 15.0, Color(c["primary"], 0.55))
	draw_circle(Vector2(W * 0.5, 38), 12.0, Color(c["secondary"], 0.25))
	if _portrait != null:
		draw_texture_rect(_portrait, Rect2(W * 0.5 - 16, ART_H - 33, 32, 32), false)
	# Sheen.
	var ph := fmod(_t, 2.8) / 2.8
	var sx := lerpf(-30.0, W + 10.0, ph)
	for yy in range(0, int(art.size.y), 2):
		var x := sx + yy * 0.4
		if x >= art.position.x and x + 2.0 <= art.end.x:
			draw_rect(Rect2(x, art.end.y - 1 - yy, 2, 2), Color(1, 1, 1, 0.16))
	var font := PixelFont.get_font()
	var pos := str(player["pos"])
	draw_rect(Rect2(3, 3, PixelFont.text_width(pos) + 4, 10), UiSkin.SHADOW)
	draw_string(font, Vector2(5, 11), pos, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
	var os := str(o)
	UiSkin.draw_text(self, Vector2(W - 4 - PixelFont.text_width(os), 11), os, 8, Color.WHITE, UiSkin.SHADOW)
	var dev := int(player.get("dev", 0))
	if dev > 0:
		var dn: String = ["", "STAR", "SSTAR", "XF"][dev]
		var dc: Color = RtgRules.DEV_COLORS[dev]
		draw_rect(Rect2(3, 14, PixelFont.text_width(dn) + 4, 9), dc)
		draw_string(font, Vector2(5, 21), dn, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiSkin.SHADOW)
	# Name plate.
	var plate := Rect2(2, ART_H, W - 4, H - ART_H - 2)
	draw_rect(plate, UiSkin.NAVY)
	draw_rect(Rect2(plate.position.x, plate.position.y, plate.size.x, 1), tc.lightened(0.25))
	UiSkin.draw_text_fit(self, W * 0.5, ART_H + 10, str(player.get("last", player.get("name", ""))), W - 6, Color.WHITE)
	var stars := UiSkin.ovr_stars(o)
	for i in 5:
		UiSkin.draw_star(self, Vector2(W * 0.5 - 22 + i * 9, ART_H + 13), UiSkin.YELLOW, clampf(stars - i, 0.0, 1.0),
				1.0, Color(0.04, 0.06, 0.25))
	draw_rect(Rect2(plate.position.x + 2, H - 6, plate.size.x - 4, 3), c["primary"])
	draw_rect(Rect2(plate.position.x + 2, H - 5, plate.size.x - 4, 1), c["secondary"])
	draw_set_transform(Vector2.ZERO)
