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


func test_store() -> void:
	await _smoke("res://scenes/meta/store.tscn")


func test_collection() -> void:
	await _smoke("res://scenes/meta/collection.tscn")


func test_lineup() -> void:
	await _smoke("res://scenes/meta/lineup.tscn")


func test_sets() -> void:
	await _smoke("res://scenes/meta/sets.tscn")


func test_pack_open_reveals_cards() -> void:
	var prof := SaveManager.profile
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var uids := EconomyRules.grant_pack(prof, PackCatalog.get_pack("gold"), GameData.db, rng)
	SceneRouter.pending_config = {"uids": uids, "title": "GOLD PACK"}
	var node: Control = load("res://scenes/meta/pack_open.tscn").instantiate()
	add_child_autofree(node)
	await wait_process_frames(2)
	node._flip_all()
	assert_eq(node._next, uids.size())


func test_hub_processes_rewards() -> void:
	var prof := SaveManager.profile
	var coins := prof.coins
	SceneRouter.pending_config = {"last_result": {"team": "KC", "opponent": "BUF", "pf": 21, "pa": 14, "tds": 3,
			"difficulty": 1, "mode": "quick"}}
	var node: Control = load("res://scenes/meta/hub.tscn").instantiate()
	add_child_autofree(node)
	await wait_process_frames(2)
	assert_gt(prof.coins, coins + EconomyRules.WIN_COINS)


func test_season_screen() -> void:
	await _smoke("res://scenes/meta/season.tscn")


func test_challenges_screen() -> void:
	await _smoke("res://scenes/meta/challenges.tscn")


func test_settings_screen() -> void:
	await _smoke("res://scenes/meta/settings.tscn")
