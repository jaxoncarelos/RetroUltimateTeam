extends GutTest
## SafeArea: desktop has no insets; overrides drive apply()/bleed() so menus stay clear of
## the iPhone's rounded corners while backgrounds still cover the whole screen.

func after_each() -> void:
	SafeArea.set_override({})


func test_desktop_has_no_insets() -> void:
	if OS.has_feature("mobile"):
		return
	var i := SafeArea.insets()
	assert_eq(i["left"], 0.0)
	assert_eq(i["bottom"], 0.0)


func test_apply_insets_and_bleed_covers_margins() -> void:
	SafeArea.set_override({"left": 20.0, "top": 4.0, "right": 24.0, "bottom": 8.0})
	var c := Control.new()
	SafeArea.apply(c)
	assert_eq(c.offset_left, 20.0)
	assert_eq(c.offset_top, 4.0)
	assert_eq(c.offset_right, -24.0)
	assert_eq(c.offset_bottom, -8.0)
	var bg := Control.new()
	SafeArea.bleed(bg)
	assert_eq(bg.offset_left, -20.0)
	assert_eq(bg.offset_right, 24.0)
	assert_eq(bg.offset_bottom, 8.0)
	c.free()
	bg.free()


func test_iphone_landscape_numbers() -> void:
	# iPhone 15: 2556x1179 px, landscape safe area 59pt (177 px) on the sides, 21pt (63 px) bottom.
	var scr := Vector2(2556, 1179)
	var vp := Vector2(270.0 * scr.x / scr.y, 270.0)
	var i := SafeArea.compute(scr, vp, Rect2(177, 0, 2556 - 354, 1179 - 63), scr)
	assert_almost_eq(i["left"], 177.0 * vp.x / scr.x, 0.01)   # ~40 units: clears the ~47pt corner radius
	assert_almost_eq(i["right"], i["left"], 0.01)
	assert_eq(i["top"], SafeArea.MIN_MOBILE["top"])
	assert_eq(i["bottom"], 10.0)                                 # capped
	assert_gt(i["left"], 30.0)


func test_missing_safe_area_falls_back_to_minimums() -> void:
	var i := SafeArea.compute(Vector2(800, 400), Vector2(585, 270), Rect2(), Vector2(800, 400))
	assert_eq(i["left"], SafeArea.MIN_MOBILE["left"])
