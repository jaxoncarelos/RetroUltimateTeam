extends GutTest
## Music: the synthesized loops are audible, not clipped, loop-length exact, and different.

func _stats(w: AudioStreamWAV) -> Dictionary:
	var n := w.data.size() / 2
	var peak := 0.0
	var sq := 0.0
	for i in n:
		var v := float(w.data.decode_s16(i * 2)) / 32768.0
		peak = maxf(peak, absf(v))
		sq += v * v
	return {"n": n, "peak": peak, "rms": sqrt(sq / maxf(n, 1))}


func test_tracks_are_audible_and_loop_exactly() -> void:
	var lens := {}
	for name in ["menu", "game", "clutch"]:
		var spec: Dictionary = Music.TRACKS[name]
		var w := Music._track(spec)
		var s := _stats(w)
		assert_gt(s["rms"], 0.03, "%s is audible" % name)
		assert_lt(s["peak"], 0.99, "%s does not clip" % name)
		assert_eq(w.loop_mode, AudioStreamWAV.LOOP_FORWARD)
		assert_eq(w.loop_end, s["n"])
		var sps := int(Music.RATE * 60.0 / float(spec["bpm"]) / 4.0)
		assert_eq(s["n"], sps * 16 * (spec["bars"] as Array).size(), "%s is whole bars" % name)
		lens[name] = s["n"]
	assert_ne(lens["menu"], lens["game"])


func test_jingles_and_crowd() -> void:
	var win := Music._jingle([[72, 0.0], [76, 0.11]], 1.0, 1.0)
	assert_gt(_stats(win)["rms"], 0.01)
	assert_eq(win.loop_mode, AudioStreamWAV.LOOP_DISABLED)
	var crowd := Music._crowd()
	assert_gt(_stats(crowd)["rms"], 0.02)
	assert_eq(crowd.loop_mode, AudioStreamWAV.LOOP_FORWARD)
