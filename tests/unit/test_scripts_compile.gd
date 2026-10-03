extends GutTest
## Every script and scene in the game loads (a parse error in a screen nobody tests would
## otherwise only show up on the phone as a blank screen).


func _files(dir: String, ext: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(ext):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_files(dir.path_join(d), ext, out)


func test_every_script_parses() -> void:
	var paths: Array[String] = []
	for root in ["res://scripts", "res://autoload"]:
		_files(root, ".gd", paths)
	assert_gt(paths.size(), 50)
	for p in paths:
		var s: GDScript = load(p)
		assert_not_null(s, p)
		if s != null:
			assert_true(s.can_instantiate(), "%s compiles" % p)


func test_every_scene_loads() -> void:
	var paths: Array[String] = []
	_files("res://scenes", ".tscn", paths)
	for p in paths:
		var sc: PackedScene = load(p)
		assert_not_null(sc, p)
		if sc != null:
			assert_true(sc.can_instantiate(), p)
