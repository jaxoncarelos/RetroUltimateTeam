class_name KickMeter
extends Control
## FG / PAT timing meter: a needle sweeps across the bar; tap (or swipe up) to kick when it
## is inside the green zone. Zone width comes from kick accuracy and distance, sweep speed
## from distance (KickModel). Emits kicked(needle) with needle in -1..1 (0 = dead center).

signal kicked(needle: float)

const W := 180.0
const H := 14.0

var zone := 0.2          ## half-width of the green zone (fraction of the half bar)
var doink := 0.05
var speed := 1.0         ## sweeps per second
var title := "FIELD GOAL"
var _t := 0.0
var _active := false
var _needle := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func start(p_title: String, p_zone: float, p_doink: float, p_speed: float) -> void:
	title = p_title
	zone = p_zone
	doink = p_doink
	speed = p_speed
	_t = 0.0
	_active = true
	visible = true


func stop_and_kick() -> void:
	if not _active:
		return
	_active = false
	kicked.emit(_needle)


func hide_meter() -> void:
	_active = false
	visible = false


func is_active() -> bool:
	return _active


func _process(delta: float) -> void:
	if not visible:
		return
	if _active:
		_t += delta * speed
		# Ping-pong -1..1 with a slight ease so the ends linger.
		_needle = sin(_t * PI)
	queue_redraw()


func _draw() -> void:
	var vp := get_viewport_rect().size
	var origin := Vector2(roundf((vp.x - W) * 0.5), roundf(vp.y * 0.30))
	var frame := Rect2(origin - Vector2(10, 24), Vector2(W + 20, H + 46))
	UiSkin.draw_frame(self, frame, Color(UiSkin.PANEL, 0.94), UiSkin.BORDER)
	UiSkin.draw_text_c(self, origin.x + W * 0.5, origin.y - 9, title, 8, UiSkin.YELLOW, Color(0, 0, 0, 0), UiSkin.SHADOW)
	draw_rect(Rect2(origin - Vector2(1, 1), Vector2(W + 2, H + 2)), UiSkin.BORDER)
	draw_rect(Rect2(origin, Vector2(W, H)), Color("#7e2553"))
	var cx := origin.x + W * 0.5
	var half := W * 0.5
	var dz := (zone + doink) * half
	draw_rect(Rect2(cx - dz, origin.y, dz * 2.0, H), Color("#ffa300"))
	var gz := zone * half
	draw_rect(Rect2(cx - gz, origin.y, gz * 2.0, H), UiSkin.GREEN)
	draw_rect(Rect2(cx - gz, origin.y, gz * 2.0, 2), UiSkin.GREEN.lightened(0.4))
	draw_rect(Rect2(cx - 1, origin.y - 2, 2, H + 4), Color(1, 1, 1, 0.6))
	var nx := roundf(cx + _needle * half)
	draw_rect(Rect2(nx - 2, origin.y - 5, 5, H + 10), UiSkin.SHADOW)
	draw_rect(Rect2(nx - 1, origin.y - 4, 3, H + 8), UiSkin.WHITE)
	if _active and fmod(_t, 0.6) < 0.45:
		UiSkin.draw_text_c(self, cx, origin.y + H + 13, "TAP TO KICK!", 8, UiSkin.WHITE)
