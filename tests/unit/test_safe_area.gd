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
