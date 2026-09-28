extends GutTest
## Generated stadium art: sizes, determinism, and animation frames.


func test_turf_covers_the_field() -> void:
	var tex := StadiumArt.build_turf(Color.RED, Color.BLUE)
	assert_eq(tex.get_width(), int(FieldGeo.LENGTH * FieldProjection.PX_X))
	assert_eq(tex.get_height(), int(FieldGeo.WIDTH * FieldProjection.PX_Y))
	var img := tex.get_image()
	# End zones carry the team colors (red-ish on the left, blue-ish on the right).
	var left := img.get_pixel(20, 100)
	var right := img.get_pixel(img.get_width() - 20, 100)
	assert_gt(left.r, left.b)
	assert_gt(right.b, right.r)
	# Midfield is grass.
	var mid := img.get_pixel(img.get_width() / 2 + 3, 100)
	assert_gt(mid.g, mid.r)


func test_crowd_frames_are_animated_and_deterministic() -> void:
	var a := StadiumArt.build_crowd(Color.RED, Color.YELLOW, 7)
	var b := StadiumArt.build_crowd(Color.RED, Color.YELLOW, 7)
	assert_eq(a.size(), StadiumArt.CROWD_FRAMES)
	assert_eq(a[0].get_width(), StadiumArt.CROWD_TILE_W)
	assert_eq(a[0].get_height(), StadiumArt.CROWD_H)
	assert_eq(a[0].get_image().get_data(), b[0].get_image().get_data(), "same seed, same crowd")
	assert_ne(a[0].get_image().get_data(), a[1].get_image().get_data(), "frames differ (cheering fans)")
