class_name SafeArea
extends RefCounted
## Screen insets in viewport units (the 480x270 canvas, stretched with "expand") so UI stays
## clear of the iPhone's rounded corners, notch and home indicator. Uses the OS-reported safe
## area, with a minimum margin on phones (corner radius is not part of the reported area).

## Minimum margins on touch devices (viewport units): rounded corners eat ~15 units diagonally.
const MIN_MOBILE := {"left": 14.0, "top": 4.0, "right": 14.0, "bottom": 6.0}
const MAX_INSET := 60.0

static var _override: Dictionary = {}   ## debug / tests: {"left","top","right","bottom"}


## Force insets (screenshots, tests). Pass {} to go back to the device values.
static func set_override(d: Dictionary) -> void:
	_override = d


static func insets() -> Dictionary:
	if not _override.is_empty():
		return _override
	var out := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	var mobile := OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--fake-notch")
	if OS.get_cmdline_user_args().has("--fake-notch"):
		return {"left": 30.0, "top": 4.0, "right": 30.0, "bottom": 10.0}
	if not mobile:
		return out
	for k in out:
		out[k] = MIN_MOBILE[k]
	var win := DisplayServer.window_get_size()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null or win.x <= 0 or win.y <= 0:
		return out
	var vp := tree.root.get_visible_rect().size
	var sc := Vector2(vp.x / win.x, vp.y / win.y)
	var safe := DisplayServer.get_display_safe_area()
	var scr := DisplayServer.screen_get_size()
	if safe.size.x <= 0 or scr.x <= 0:
		return out
	out["left"] = maxf(out["left"], safe.position.x * sc.x)
	out["top"] = maxf(out["top"], safe.position.y * sc.y)
	out["right"] = maxf(out["right"], (scr.x - safe.end.x) * sc.x)
	out["bottom"] = maxf(out["bottom"], (scr.y - safe.end.y) * sc.y)
	for k in out:
		out[k] = clampf(out[k], 0.0, MAX_INSET)
	out["bottom"] = minf(out["bottom"], 10.0)   # the home indicator is thin; keep the nav row usable
	return out


static func left() -> float:
	return insets()["left"]


static func right() -> float:
	return insets()["right"]


static func top() -> float:
	return insets()["top"]


static func bottom() -> float:
	return insets()["bottom"]


## Make `c` (child of an inset parent) cover the whole screen, including the margins.
static func bleed(c: Control) -> void:
	var i := insets()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = -i["left"]
	c.offset_top = -i["top"]
	c.offset_right = i["right"]
	c.offset_bottom = i["bottom"]


## Inset `c` (a full-rect control) to the safe area.
static func apply(c: Control) -> void:
	var i := insets()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = i["left"]
	c.offset_top = i["top"]
	c.offset_right = -i["right"]
	c.offset_bottom = -i["bottom"]
