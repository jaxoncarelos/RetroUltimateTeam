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


func test_title_screen() -> void:
	await _smoke("res://scenes/meta/title.tscn")


func test_mode_select() -> void:
	await _smoke("res://scenes/meta/mode_select.tscn")


func test_objectives_screen() -> void:
	await _smoke("res://scenes/meta/objectives.tscn")


func test_prematch_screen() -> void:
	SceneRouter.pending_config = GameFlow.next_quick_config(SaveManager.profile)
	await _smoke("res://scenes/meta/prematch.tscn")


func test_results_screen_applies_match() -> void:
	var prof := SaveManager.profile
	var games := int(prof.stats["games"])
	var coins := prof.coins
	SceneRouter.pending_config = {"last_result": {"team": "KC", "opponent": "BUF", "pf": 28, "pa": 10, "tds": 4,
			"difficulty": 1, "mode": "quick", "box": {"pass_td": 3, "rush_td": 1, "pass_comp": 12, "pass_att": 20}}}
	var node: Control = load("res://scenes/meta/results.tscn").instantiate()
	add_child_autofree(node)
	await wait_process_frames(3)
	assert_eq(int(prof.stats["games"]), games + 1, "the match counted once")
	assert_gt(prof.coins, coins + EconomyRules.WIN_COINS)


func test_next_game_is_quick_without_season() -> void:
	var cfg := GameFlow.next_game_config(SaveManager.profile)
	assert_eq(cfg.get("mode", ""), "quick")
	assert_ne(cfg.get("away", ""), SaveManager.profile.franchise_team)
