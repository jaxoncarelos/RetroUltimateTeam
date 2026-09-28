class_name CardView
extends Control
## Code-drawn 48x64 player card (times `card_scale`): tier-colored border, team stripe,
## big OVR, position, mini palette-swapped player sprite, name, training boost, lock.
## face_down shows the pack-opening back.

signal tapped(view: CardView)

const W := 48
const H := 64

var card: CardDef
var player: PlayerData
var entry: Dictionary = {}      ## owned-card entry (boost/locked/uid), optional
var card_scale := 1
var face_down := false:
	set(v):
		face_down = v
		if _sprite != null:
			_sprite.visible = not v
		queue_redraw()
var selected := false:
	set(v):
		selected = v
		queue_redraw()
var flash := 0.0
var _sprite: TextureRect


func _init(p_card: CardDef = null, p_entry: Dictionary = {}, p_scale := 1) -> void:
	card = p_card
	entry = p_entry
	card_scale = p_scale
	custom_minimum_size = Vector2(W, H) * p_scale
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	if card != null:
		player = GameData.player(card.player_id)
	var team: TeamData = GameData.team(player.team) if player != null else null
	_sprite = TextureRect.new()
	var at := AtlasTexture.new()
	at.atlas = load(PlayerSprites.SHEET)
	at.region = Rect2(0, 0, PlayerSprites.FRAME.x, PlayerSprites.FRAME.y)
	_sprite.texture = at
	_sprite.stretch_mode = TextureRect.STRETCH_SCALE
	_sprite.size = Vector2(16, 20) * card_scale
	_sprite.position = Vector2(16, 22) * card_scale
	_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if team != null:
		_sprite.material = PlayerSprites.make_material(team.uniform_colors(), hash(card.player_id))
	_sprite.visible = not face_down
	add_child(_sprite)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped.emit(self)
		accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		tapped.emit(self)
		accept_event()


func _process(delta: float) -> void:
	if flash > 0.0:
		flash = maxf(0.0, flash - delta * 1.6)
		queue_redraw()


func _draw() -> void:
	var s := float(card_scale)
	var tier_col: Color = CardRules.COLORS[card.tier] if card != null else UiTheme.DIM
	var r := Rect2(Vector2.ZERO, Vector2(W, H) * s)
	draw_rect(r, tier_col)
	draw_rect(r.grow(-2 * s), UiTheme.INK)
	if face_down:
		# Card back: tier-tinted diamond pattern.
		for y in range(4, H - 4, 6):
			for x in range(4 + (y / 6 % 2) * 3, W - 4, 6):
				draw_rect(Rect2(Vector2(x, y) * s, Vector2(2, 2) * s), Color(tier_col, 0.55))
		draw_rect(Rect2(Vector2(14, 24) * s, Vector2(20, 16) * s), Color(tier_col, 0.9))
		draw_string(PixelFont.get_font(), Vector2(17, 36) * s, "?", HORIZONTAL_ALIGNMENT_LEFT, -1, int(8 * s), UiTheme.INK)
	elif card != null and player != null:
		var team: TeamData = GameData.team(player.team)
		var font := PixelFont.get_font()
		if team != null:
			draw_rect(Rect2(Vector2(2, 2) * s, Vector2(W - 4, 7) * s), team.primary)
			draw_rect(Rect2(Vector2(2, 9) * s, Vector2(W - 4, 1) * s), team.secondary)
			draw_string(font, Vector2(W - 4 - team.abbr.length() * 6, 8) * s, team.abbr, HORIZONTAL_ALIGNMENT_LEFT,
					-1, int(8 * s), Color.WHITE)
		var ovr := mini(card.ovr + int(entry.get("boost", 0)), 99)
		draw_string(font, Vector2(4, 20) * s, str(ovr), HORIZONTAL_ALIGNMENT_LEFT, -1, int(8 * s), tier_col)
		draw_string(font, Vector2(4, 29) * s, player.pos, HORIZONTAL_ALIGNMENT_LEFT, -1, int(8 * s), UiTheme.TEXT)
		var nm := player.last_name().left(7)
		draw_string(font, Vector2(4, 52) * s, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, int(8 * s), UiTheme.TEXT)
		draw_string(font, Vector2(4, 61) * s, CardRules.NAMES[card.tier].left(6), HORIZONTAL_ALIGNMENT_LEFT, -1,
				int(8 * s), Color(tier_col, 0.9))
		var boost := int(entry.get("boost", 0))
		if boost > 0:
			draw_string(font, Vector2(W - 16, 20) * s, "+%d" % boost, HORIZONTAL_ALIGNMENT_LEFT, -1, int(8 * s),
					Color("#00e436"))
		if entry.get("locked", false):
			draw_rect(Rect2(Vector2(W - 9, 24) * s, Vector2(5, 4) * s), UiTheme.ACCENT)
			draw_rect(Rect2(Vector2(W - 8, 21) * s, Vector2(3, 3) * s), UiTheme.ACCENT, false, s)
	if selected:
		draw_rect(r.grow(1 * s), UiTheme.ACCENT, false, 2.0 * s)
	if flash > 0.0:
		draw_rect(r, Color(1, 1, 1, flash))
