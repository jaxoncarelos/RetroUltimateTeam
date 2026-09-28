class_name CoinPill
extends Control
## Coin counter pill (top-left of every menu): "6,400 (coin)". set_coins() counts up/down
## with a pop so earning coins always feels like something.

var coins := 0
var shown := 0.0:
	set(v):
		shown = v
		queue_redraw()
var _tw: Tween


func _init(p_coins := 0) -> void:
	coins = p_coins
	shown = p_coins
	custom_minimum_size = Vector2(66, 15)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_coins(v: int, animate := true) -> void:
	var from := shown
	coins = v
	if _tw != null and _tw.is_valid():
		_tw.kill()
	if not animate or not is_inside_tree():
		shown = v
		return
	_tw = create_tween()
	_tw.tween_property(self, "shown", float(v), clampf(absf(v - from) / 1500.0, 0.35, 1.2)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pivot_offset = size * 0.5
	var pop := create_tween()
	pop.tween_property(self, "scale", Vector2(1.15, 1.15), 0.08)
	pop.tween_property(self, "scale", Vector2.ONE, 0.2)


## Viewport position of the coin icon (target for flying coins).
func coin_global() -> Vector2:
	return global_position + Vector2(size.x - 7, 7)


static func fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	UiSkin.draw_frame(self, r, UiSkin.NAVY_DEEP, UiSkin.BORDER)
	var t := fmt(int(roundf(shown)))
	var w := PixelFont.text_width(t)
	UiSkin.draw_text(self, Vector2(size.x - 14 - w, 11), t, 8, UiSkin.WHITE)
	UiSkin.draw_coin(self, Vector2(size.x - 10, 4))
