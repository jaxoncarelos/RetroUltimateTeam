extends GutTest
## Smoke tests: every meta screen builds and survives a few frames with a starter profile.

var _saved: Profile


func before_all() -> void:
	_saved = SaveManager.profile
	SaveManager.disabled = true
	var prof := Profile.new()
	Collection.grant_starters(prof, GameData.db, "KC")
	SaveManager.profile = prof


func after_all() -> void:
	SaveManager.profile = _saved


func _smoke(path: String) -> void:
	var scene: PackedScene = load(path)
	assert_not_null(scene, path)
	var node := scene.instantiate()
	add_child_autofree(node)
	await wait_process_frames(3)
	assert_true(is_instance_valid(node), path)


func test_team_picker() -> void:
	await _smoke("res://scenes/meta/team_picker.tscn")


func test_hub() -> void:
	await _smoke("res://scenes/meta/hub.tscn")
