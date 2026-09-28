class_name CardView
extends Control
## Code-drawn 56x80 player card (times `card_scale`), Retro Bowl roster style with an
## ultimate-team twist: tier-colored art panel with the portrait (ArtGen), position chip,
## big OVR, navy name plate with star rating and a team-color strip. Gold and Elite cards
## get an animated sheen (Elite also sparkles). face_down shows the pack card back.

signal tapped(view: CardView)

const W := 56
const H := 80
const ART_H := 54

var card: CardDef
var player: PlayerData
var entry: Dictionary = {}      ## owned-card entry (boost/locked/uid), optional
var card_scale := 1
var face_down := false:
	set(v):
		face_down = v
		queue_redraw()
var selected := false:
	set(v):
		selected = v
		queue_redraw()
var is_new := false:
	set(v):
		is_new = v
		queue_redraw()
var glow := 0.0:                ## 0..1 outer glow in the tier color (pack reveals)
	set(v):
		glow = v
		queue_redraw()
var flash := 0.0
var dim := false:               ## greyed out (not usable here)
	set(v):
		dim = v
		queue_redraw()
var caption := ""               ## optional text under the card (e.g. "+25")
var _t := 0.0
var _portrait: Texture2D


func _init(p_card: CardDef = null, p_entry: Dictionary = {}, p_scale := 1) -> void:
	card = p_card
	entry = p_entry
	card_scale = p_scale
	custom_minimum_size = Vector2(W, H) * p_scale
	mouse_filter = Control.MOUSE_FILTER_STOP
	_t = randf() * 3.0


func _ready() -> void:
	if card != null:
		player = GameData.player(card.player_id)
	if player != null:
		var team: TeamData = GameData.team(player.team)
		var colors: Dictionary = team.uniform_colors() if team != null else {}
		_portrait = ArtGen.portrait(player.id, player.pos, colors, player.jersey)


func tier() -> int:
	if card == null:
		return 0
	return Collection.card_tier(GameData.db, entry) if entry.has("def") else card.tier


## Effective OVR (card + development + training) of an owned card, else the card's OVR.
func ovr() -> int:
	if card == null:
		return 0
	return Collection.card_ovr(GameData.db, entry) if entry.has("def") else card.ovr


func is_prime() -> bool:
	return card != null and card.has_method("is_prime") and card.is_prime()


## Mouse only: touches arrive as emulated mouse clicks (and project.godot also emulates
## touch from the mouse, so handling both would fire twice per tap). Squishes while held.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press(true)
			tapped.emit(self)
		else:
			_press(false)
		accept_event()


func _press(down: bool) -> void:
	if card_scale > 1 or not is_inside_tree():
		return
	pivot_offset = size * 0.5
	var tw := create_tween()
	if down:
		tw.tween_property(self, "scale", Vector2(0.94, 0.94), 0.05)
	else:
		tw.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_t += delta
	if flash > 0.0:
		flash = maxf(0.0, flash - delta * 1.6)
	if flash > 0.0 or (not face_down and tier() >= CardRules.Tier.GOLD) or glow > 0.0:
		queue_redraw()


static func tier_color(t: int) -> Color:
	return CardRules.COLORS[clampi(t, 0, CardRules.COLORS.size() - 1)]


func _draw() -> void:
	var s := float(card_scale)
	var tc := tier_color(tier())
	if glow > 0.0:
		for i in 4:
			var g := 2.0 + i * 2.0
			draw_rect(Rect2(Vector2(-g, -g) * s, (Vector2(W, H) + Vector2(g, g) * 2.0) * s),
					Color(tc.lightened(0.3), glow * (0.28 - i * 0.06)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	var r := Rect2(0, 0, W, H)
	draw_rect(r, UiSkin.SHADOW)
	draw_rect(r.grow(-1), tc.lightened(0.25))
	if face_down:
		_draw_back(tc)
	elif card != null and player != null:
		_draw_front(tc)
	if selected:
		draw_rect(r.grow(1), UiSkin.YELLOW, false, 2.0)
	if dim:
		draw_rect(r, Color(0.05, 0.07, 0.2, 0.6))
	if flash > 0.0:
		draw_rect(r, Color(1, 1, 1, flash))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_back(tc: Color) -> void:
	var inner := Rect2(2, 2, W - 4, H - 4)
	draw_rect(inner, UiSkin.NAVY)
	for y in range(4, H - 4, 6):
		for x in range(4 + (y / 6 % 2) * 3, W - 4, 6):
			draw_rect(Rect2(x, y, 2, 2), Color(tc, 0.35))
	draw_rect(Rect2(8, 8, W - 16, H - 16), Color(tc, 0.9), false, 1.0)
	var em := UiSkin.emblem()
	draw_texture_rect(em, Rect2(Vector2(W * 0.5 - 15, H * 0.5 - 16), Vector2(30, 32)), false)


func _draw_front(tc: Color) -> void:
	var font := PixelFont.get_font()
	var t := tier()
	# Art panel: two-tone tier gradient with scanlines.
	var art := Rect2(2, 2, W - 4, ART_H - 2)
	var top := tc.lightened(0.35)
	var bottom := tc.darkened(0.15)
	for y in int(art.size.y):
		var u := float(y) / art.size.y
		var c := top.lerp(bottom, u)
		if y % 2 == 1:
			c = c.darkened(0.04)
		draw_rect(Rect2(art.position.x, art.position.y + y, art.size.x, 1), c)
	if t >= CardRules.Tier.GOLD:
		# Diagonal pinstripes.
		for i in range(-60, 60, 8):
			draw_line(Vector2(art.position.x + i, art.end.y), Vector2(art.position.x + i + art.size.y, art.position.y),
					Color(1, 1, 1, 0.08), 1.0)
	var team: TeamData = GameData.team(player.team)
	if team != null:
		# Team-colored halo behind the portrait.
		draw_circle(Vector2(W * 0.5, 38), 15.0, Color(team.primary, 0.55))
		draw_circle(Vector2(W * 0.5, 38), 12.0, Color(team.secondary, 0.25))
	if _portrait != null:
		draw_texture_rect(_portrait, Rect2(W * 0.5 - 16, ART_H - 33, 32, 32), false)
	# Sheen sweep on Gold / Elite.
	if t >= CardRules.Tier.GOLD:
		var period := 2.6 if t == CardRules.Tier.GOLD else 1.8
		var ph := fmod(_t, period) / period
		var sx := lerpf(-30.0, W + 10.0, ph)
		var slope := 20.0 / art.size.y
		for yy in range(0, int(art.size.y), 1):
			var y := art.end.y - 1.0 - yy
			for k in 3:
				var x := sx + k * 3.0 + yy * slope
				if x >= art.position.x and x + 2.0 <= art.end.x:
					draw_rect(Rect2(x, y, 2, 1), Color(1, 1, 1, 0.22 - k * 0.06))
		if t == CardRules.Tier.ELITE:
			for i in 4:
				var sp := fmod(_t * 0.7 + i * 0.37, 1.0)
				var px := 6.0 + fmod(i * 17.0 + floor(_t * 0.7 + i * 0.37) * 11.0, W - 12.0)
				var py := 8.0 + fmod(i * 23.0 + floor(_t * 0.7 + i * 0.37) * 7.0, ART_H - 16.0)
				var a := sin(sp * PI)
				draw_rect(Rect2(px, py - 1, 1, 3), Color(1, 1, 1, a))
				draw_rect(Rect2(px - 1, py, 3, 1), Color(1, 1, 1, a))
	# Position chip (top-left) and OVR (top-right).
	var pos := player.pos
	var pw := PixelFont.text_width(pos) + 4
	draw_rect(Rect2(3, 3, pw, 10), UiSkin.SHADOW)
	draw_string(font, Vector2(5, 11), pos, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
	var o := str(ovr())
	var ow := PixelFont.text_width(o)
	UiSkin.draw_text(self, Vector2(W - 4 - ow, 11), o, 8, Color.WHITE, UiSkin.SHADOW)
	var boost := int(entry.get("boost", 0)) + int(entry.get("dev", 0))
	if is_prime():
		draw_rect(Rect2(3, 14, 29, 9), Color("#29adff"))
		draw_string(font, Vector2(5, 21), "PRIME", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
	if boost > 0:
		var bt := "+%d" % boost
		draw_rect(Rect2(W - 5 - PixelFont.text_width(bt), 14, PixelFont.text_width(bt) + 2, 9), Color("#0d5a2a"))
		draw_string(font, Vector2(W - 4 - PixelFont.text_width(bt), 21), bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiSkin.GREEN)
	if entry.get("locked", false):
		UiSkin.draw_icon(self, "lock", Vector2(4, ART_H - 10), UiSkin.YELLOW, 1.0)
	if is_new:
		var blink := 0.75 + 0.25 * sin(_t * 8.0)
		draw_rect(Rect2(W - 24, ART_H - 11, 21, 9), Color(UiSkin.RED, blink))
		draw_string(font, Vector2(W - 22, ART_H - 4), "NEW", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
	# Name plate.
	var plate := Rect2(2, ART_H, W - 4, H - ART_H - 2)
	draw_rect(plate, UiSkin.NAVY)
	draw_rect(Rect2(plate.position.x, plate.position.y, plate.size.x, 1), tc.lightened(0.25))
	UiSkin.draw_text_fit(self, W * 0.5, ART_H + 10, player.last_name().to_upper(), W - 6, Color.WHITE)
	var stars := UiSkin.ovr_stars(ovr())
	for i in 5:
		UiSkin.draw_star(self, Vector2(W * 0.5 - 22 + i * 9, ART_H + 13), UiSkin.YELLOW, clampf(stars - i, 0.0, 1.0),
				1.0, Color(0.04, 0.06, 0.25))
	if team != null:
		draw_rect(Rect2(plate.position.x + 2, H - 6, plate.size.x - 4, 3), team.primary)
		draw_rect(Rect2(plate.position.x + 2, H - 5, plate.size.x - 4, 1), team.secondary)
