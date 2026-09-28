class_name CoinPill
extends Control
## Coin counter pill (top-left of every menu): "6,400 (coin)". set_coins() counts up/down
## with a pop so earning coins always feels like something. The pill sizes itself to the
## number (fmt() compacts millions: "1.25M"), so big balances never spill out of the box.

const MIN_W := 44.0
const PAD := 5.0

var coins := 0
var shown := 0.0:
	set(v):
		shown = v
		queue_redraw()
var _tw: Tween


func _init(p_coins := 0) -> void:
	coins = p_coins
	shown = p_coins
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit(p_coins)


func set_coins(v: int, animate := true) -> void:
	var from := shown
	coins = v
	# Wide enough for both ends of the count so the pill doesn't jitter while it ticks.
	_fit(v if PixelFont.text_width(fmt(v)) >= PixelFont.text_width(fmt(int(from))) else int(from))
	if _tw != null and _tw.is_valid():
		_tw.kill()
	if not animate or not is_inside_tree():
		shown = v
		_fit(v)
		return
	_tw = create_tween()
	_tw.tween_property(self, "shown", float(v), clampf(absf(v - from) / 1500.0, 0.35, 1.2)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tw.tween_callback(_fit.bind(v))
	pivot_offset = size * 0.5
	var pop := create_tween()
	pop.tween_property(self, "scale", Vector2(1.15, 1.15), 0.08)
	pop.tween_property(self, "scale", Vector2.ONE, 0.2)


## Viewport position of the coin icon (target for flying coins).
func coin_global() -> Vector2:
	var w := PixelFont.text_width(fmt(int(roundf(shown))))
	return global_position + Vector2(roundf((size.x - (w + 10.0)) * 0.5) + w + 6.5, 7.5)


## Width that fits `n` (text + coin icon + padding).
func _fit(n: int) -> void:
	var w := maxf(MIN_W, PAD + PixelFont.text_width(fmt(n)) + 3.0 + 7.0 + PAD)
	custom_minimum_size = Vector2(w, 15)
	size = custom_minimum_size


## Display format for coins and other counts: "12,450" below a million, then compact
## "1.25M" / "5M" / "2.5B" (truncated, never rounded up, so it never overstates).
static func fmt(n: int) -> String:
	var a := absi(n)
	var sign := "-" if n < 0 else ""
	if a >= 1_000_000_000:
		return sign + _short(a, 1_000_000_000) + "B"
	if a >= 1_000_000:
		return sign + _short(a, 1_000_000) + "M"
	return fmt_full(n)


static func _short(a: int, unit: int) -> String:
	var hundredths := a / (unit / 100)
	var whole := hundredths / 100
	var frac := hundredths % 100
	if whole >= 100 or frac == 0:
		return str(whole)
	var f := "%02d" % frac
	return "%d.%s" % [whole, f.rstrip("0")]


## Every digit, comma-grouped ("5,000,000").
static func fmt_full(n: int) -> String:
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
	# Centered group (text + coin) so short numbers don't leave a hole on the left.
	var x0 := roundf((size.x - (w + 3.0 + 7.0)) * 0.5)
	UiSkin.draw_text(self, Vector2(x0, 11), t, 8, UiSkin.WHITE)
	UiSkin.draw_coin(self, Vector2(x0 + w + 3.0, 4))
