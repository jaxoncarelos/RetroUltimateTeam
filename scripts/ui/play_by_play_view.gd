class_name PlayByPlayView
extends Control
## Tap-through play-by-play of a simulated game (full-screen overlay). A 100-yard strip shows a
## ball marker and the first-down marker; each NEXT tap reveals the next play ("Play had 10 yd
## gain") and slides the ball. SKIP jumps to the end, CLOSE (or DONE) emits `closed`.
## Usage: var v := PlayByPlayView.new(); parent.add_child(v); v.setup(PlayByPlay.from_drives(...)).

signal closed

var plays: Array[Dictionary] = []
var _idx := -1
var _strip: _Strip
var _head: Label
var _text: Label
var _sub: Label
var _count: Label
var _next: Button
var _tween: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 40
	var dim := ColorRect.new()
	dim.color = Color(UiSkin.SHADOW, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var box := MarginContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("margin_left", 10 + int(SafeArea.left()))
	box.add_theme_constant_override("margin_right", 10 + int(SafeArea.right()))
	box.add_theme_constant_override("margin_top", 8 + int(SafeArea.top()))
	box.add_theme_constant_override("margin_bottom", 8 + int(SafeArea.bottom()))
	add_child(box)
	var panel := RetroPanel.new("PLAY BY PLAY", UiSkin.PANEL, 6)
	box.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	panel.add_child(col)
	_head = MetaUI.label("", UiSkin.YELLOW, 8, HORIZONTAL_ALIGNMENT_CENTER)
	_head.custom_minimum_size = Vector2(0, 10)
	col.add_child(_head)
	_strip = _Strip.new()
	_strip.custom_minimum_size = Vector2(0, 48)
	col.add_child(_strip)
	_text = MetaUI.label("", UiSkin.WHITE, 8, HORIZONTAL_ALIGNMENT_CENTER)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(0, 28)
	col.add_child(_text)
	_sub = MetaUI.label("", UiSkin.STAR_BLUE, 8, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_sub)
	col.add_child(MetaUI.spacer(false))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	row.add_child(MetaUI.button("SKIP", Vector2(64, 28), _skip))
	_count = MetaUI.label("", UiSkin.MUTED, 8, HORIZONTAL_ALIGNMENT_CENTER)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_count)
	row.add_child(MetaUI.button("CLOSE", Vector2(64, 28), _close))
	_next = MetaUI.yellow("NEXT PLAY >", Vector2(0, 32), _advance)
	col.add_child(_next)
	_show_intro()


func setup(p_plays: Array[Dictionary]) -> void:
	plays = p_plays
	_idx = -1
	if is_inside_tree():
		_show_intro()


func _show_intro() -> void:
	if _head == null:
		return
	_head.text = ""
	_text.text = "NO PLAYS RECORDED" if plays.is_empty() else "TAP NEXT PLAY TO FOLLOW THE GAME"
	_sub.text = ""
	_count.text = "%d PLAYS" % plays.size()
	_strip.ball = 25.0
	_strip.first_down = -1.0
	_strip.queue_redraw()
	_next.disabled = plays.is_empty()


func _advance() -> void:
	if _idx >= plays.size() - 1:
		_close()
		return
	_idx += 1
	_show(_idx, true)


func _skip() -> void:
	if plays.is_empty():
		_close()
		return
	_idx = plays.size() - 1
	_show(_idx, false)


func _show(i: int, animate: bool) -> void:
	var p: Dictionary = plays[i]
	var head := ""
	var j := i
	while j >= 0 and str(plays[j].get("header", "")) == "":
		j -= 1
	if j >= 0:
		head = str(plays[j]["header"])
	_head.text = head.to_upper()
	_text.text = str(p.get("text", ""))
	_sub.text = PlayByPlay.summary(p).to_upper()
	_count.text = "%d / %d" % [i + 1, plays.size()]
	var to_x := clampf(float(p.get("to_x", p.get("from_x", 25.0))), 0.0, 100.0)
	var from_x := clampf(float(p.get("from_x", 25.0)), 0.0, 100.0)
	var fd := from_x + float(p.get("dist", 10))
	_strip.first_down = fd if fd < 100.0 else -1.0
	_strip.line = from_x
	var res := str(p.get("result", ""))
	_strip.flash = UiSkin.YELLOW if res in ["td", "fg", "first_down"] else (UiSkin.RED if res in ["turnover", "downs", "miss"] else UiSkin.WHITE)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if animate and str(p.get("header", "")) == "":
		_strip.ball = from_x
		_tween = create_tween()
		_tween.tween_property(_strip, "ball", to_x, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		_strip.ball = from_x
		if animate:
			_tween = create_tween()
			_tween.tween_interval(0.15)
			_tween.tween_property(_strip, "ball", to_x, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			_strip.ball = to_x
	_strip.queue_redraw()
	var last := i >= plays.size() - 1
	_next.text = "DONE" if last else "NEXT PLAY >"


func _close() -> void:
	closed.emit()
	queue_free()


## The 100-yard strip: end zones, 10-yard lines, line of scrimmage, first-down marker, ball.
class _Strip:
	extends Control
	var ball := 25.0:
		set(v):
			ball = v
			queue_redraw()
	var line := -1.0
	var first_down := -1.0
	var flash := UiSkin.WHITE

	func _draw() -> void:
		var ez := 14.0
		var x0 := ez
		var w := size.x - ez * 2.0
		var h := size.y
		var field := Rect2(x0, 8, w, h - 8)
		draw_rect(Rect2(0, 8, size.x, h - 8), Color("#1f6a35"))
		draw_rect(Rect2(0, 8, ez, h - 8), UiSkin.NAVY)
		draw_rect(Rect2(size.x - ez, 8, ez, h - 8), UiSkin.STAR_RED.darkened(0.4))
		for k in 10:
			if k % 2 == 0:
				draw_rect(Rect2(x0 + w * k / 10.0, 8, w / 10.0, h - 8), Color(1, 1, 1, 0.06))
		for k in range(0, 11):
			var x := x0 + w * k / 10.0
			draw_rect(Rect2(x, 8, 1, h - 8), Color(1, 1, 1, 0.55 if k == 5 else 0.3))
			if k > 0 and k < 10:
				var yd := k * 10 if k <= 5 else (10 - k) * 10
				UiSkin.draw_text_c(self, x, 7, str(yd), 8, UiSkin.MUTED)
		draw_rect(field, UiSkin.BORDER, false, 1.0)
		if line >= 0.0:
			var lx := x0 + w * line / 100.0
			draw_rect(Rect2(lx - 1, 8, 2, h - 8), Color(UiSkin.STAR_BLUE, 0.9))
		if first_down >= 0.0:
			var fx := x0 + w * first_down / 100.0
			draw_rect(Rect2(fx - 1, 8, 2, h - 8), UiSkin.YELLOW)
		# Ball marker: a little football with a highlight ring.
		var bx := x0 + w * clampf(ball, 0.0, 100.0) / 100.0
		var by := 8.0 + (h - 8.0) * 0.5
		draw_circle(Vector2(bx, by), 7.0, Color(flash, 0.35))
		draw_rect(Rect2(bx - 5, by - 3, 10, 6), Color("#8a4a22"))
		draw_rect(Rect2(bx - 3, by - 4, 6, 8), Color("#8a4a22"))
		draw_rect(Rect2(bx - 2, by - 1, 4, 1), UiSkin.WHITE)
