extends GutTest


func test_arc_starts_and_lands_on_target() -> void:
	var from := Vector2(30, 20)
	var to := Vector2(55, 30)
	var start := Ball.arc_point(from, to, 5.0, 0.0)
	var end := Ball.arc_point(from, to, 5.0, 1.0)
	assert_almost_eq(Vector2(start.x, start.y), from, Vector2(0.001, 0.001))
	assert_almost_eq(Vector2(end.x, end.y), to, Vector2(0.001, 0.001))
	assert_almost_eq(end.z, Ball.CATCH_Z, 0.001)


func test_arc_peaks_mid_flight() -> void:
	var mid := Ball.arc_point(Vector2.ZERO, Vector2(20, 0), 6.0, 0.5)
	assert_gt(mid.z, 6.0)


func test_ball_step_arrives_after_duration() -> void:
	var b: Ball = autofree(Ball.new())
	b.throw_to(Vector2(10, 10), Vector2(20, 10), 1.0, 2.0)
	var arrived := false
	for i in 59:
		arrived = b.step(1.0 / 60.0) or arrived
	assert_false(arrived, "not yet")
	assert_true(b.step(2.0 / 60.0), "arrives at t=1")


func test_projection_round_trip() -> void:
	var p := Vector2(47.5, 12.25)
	assert_almost_eq(FieldProjection.to_field(FieldProjection.to_screen(p)), p, Vector2(0.001, 0.001))


func test_spot_text() -> void:
	assert_eq(FieldGeo.spot_text(35.0), "OWN 25")
	assert_eq(FieldGeo.spot_text(60.0), "50")
	assert_eq(FieldGeo.spot_text(80.0), "OPP 30")


func test_hash_clamp() -> void:
	assert_eq(FieldGeo.clamp_to_hashes(2.0), FieldGeo.HASH_TOP)
	assert_eq(FieldGeo.clamp_to_hashes(50.0), FieldGeo.HASH_BOTTOM)
