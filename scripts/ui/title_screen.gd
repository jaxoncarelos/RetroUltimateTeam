extends Control
## Title screen: stadium backdrop (ArtGen), the POCKET GRIDIRON logo dropping in, a
## blinking TAP TO START. Tapping goes to the team picker on the first run, else the hub.

var _logo: TextureRect
var _tap: Label
var _t := 0.0
var _leaving := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := TextureRect.new()
	bg.texture = ArtGen.title_backdrop()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# Soft vignette so the logo pops.
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.15, 0.25)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var tex := UiSkin.logo(["POCKET", "GRIDIRON"], 4, Color("#ffffff"), Color("#b9c6e8"), UiSkin.STAR_RED, UiSkin.SHADOW)
	_logo = TextureRect.new()
	_logo.texture = tex
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.size = tex.get_size()
	add_child(_logo)
	var em := TextureRect.new()
	em.texture = UiSkin.emblem()
	em.size = Vector2(45, 48)
	em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	em.position = Vector2(-52, 10)
	_logo.add_child(em)
	var sub := MetaUI.label("ULTIMATE TEAM", UiSkin.NAVY_DEEP, 8, HORIZONTAL_ALIGNMENT_CENTER)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiSkin.YELLOW
	sb.border_color = UiSkin.SHADOW
	sb.set_border_width_all(1)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 1
	sub.add_theme_stylebox_override("normal", sb)
	sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	_logo.add_child(sub)
	sub.reset_size()
	sub.position = Vector2(roundf((tex.get_size().x - sub.size.x) * 0.5), tex.get_size().y - 2)
	_tap = MetaUI.label("TAP TO START", UiSkin.WHITE, 8, HORIZONTAL_ALIGNMENT_CENTER)
	_tap.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tap.offset_left = -80
	_tap.offset_right = 80
	_tap.offset_top = -22 - SafeArea.bottom()
	_tap.offset_bottom = -12 - SafeArea.bottom()
	_tap.add_theme_color_override("font_shadow_color", UiSkin.SHADOW)
	add_child(_tap)
	var ver := MetaUI.label("V0.7", Color(1, 1, 1, 0.6))
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_left = -30 - SafeArea.right()
	ver.offset_top = -12 - SafeArea.bottom()
	add_child(ver)
	_intro.call_deferred()


func _intro() -> void:
	var vp := get_viewport_rect().size
	var target := Vector2(roundf((vp.x - _logo.size.x) * 0.5) + 20, 22)
	_logo.position = Vector2(target.x, -90)
	_logo.pivot_offset = _logo.size * 0.5
	var tw := create_tween()
	tw.tween_property(_logo, "position", target, 0.55).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		Sfx.play("slam")
		Fx.burst(self, target + Vector2(_logo.size.x * 0.5, _logo.size.y), UiSkin.YELLOW, 30, 120.0, 0.7))


func _process(delta: float) -> void:
	_t += delta
	_tap.modulate.a = 1.0 if fmod(_t, 1.0) < 0.65 else 0.15


func _gui_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
	if pressed and not _leaving:
		_leaving = true
		Sfx.play("claim")
		Fx.flash(self, Color(1, 1, 1, 0.6), 0.25)
		var dest := SceneRouter.HUB if SaveManager.profile.has_team() else SceneRouter.TEAM_PICK
		SceneRouter.goto(dest, {"from_title": true})
