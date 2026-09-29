extends Node
## Over-the-air content updates for sideloaded builds. CI attaches `update-e<epoch>-<sha>.pck` to the
## private `latest` release; on launch this downloads a newer one to user:// and applies it on the
## NEXT launch (must stay the FIRST autoload so the pack is mounted before the other autoloads load).
##
## Never reference `BuildInfo` statically here: that would cache the base script and the patched one
## could not replace it. Read it through `load()` after the pack is mounted.
## Only this script, `project.godot` and the engine need a new IPA (bump `pocket_gridiron/engine_epoch`).

signal status_changed

enum State { IDLE, CHECKING, DOWNLOADING, READY, UP_TO_DATE, NEEDS_IPA, FAILED, DISABLED }

const META_PATH := "user://update_meta.json"
const PACK_PATH := "user://update.pck"
const API_URL := "https://api.github.com/repos/%s/releases/tags/latest"

var state: State = State.IDLE
var detail := ""
var applied_id := ""  ## commit id of the mounted pack ("" = running the IPA's own content)

var _meta: Dictionary = {}
var _repo := ""
var _token := ""
var _current_id := "dev"
var _http: HTTPRequest


func _init() -> void:
	_meta = _read_meta()
	if _meta.is_empty() or not FileAccess.file_exists(PACK_PATH):
		return
	if _meta.get("pending", false):
		_discard("previous launch never reached the title")
	elif _meta.get("base", "") != _base_build() or int(_meta.get("epoch", -1)) != _epoch():
		_discard("a newer IPA was installed")
	else:
		_meta["pending"] = true  # cleared by mark_good() once the title screen is up
		_write_meta()
		if ProjectSettings.load_resource_pack(PACK_PATH):
			applied_id = str(_meta.get("id", ""))
		else:
			_discard("pack failed to mount")


func _ready() -> void:
	var info: GDScript = load("res://scripts/build_info.gd")
	var consts := info.get_script_constant_map()
	_current_id = str(consts.get("ID", "dev"))
	_repo = str(consts.get("REPO", ""))
	_token = str(consts.get("TOKEN", ""))
	if _token.is_empty() or _repo.is_empty() or DisplayServer.get_name() == "headless":
		_set_state(State.DISABLED, "updates off in dev builds")
		return
	_http = HTTPRequest.new()
	_http.max_redirects = 0  # the asset redirect goes to a signed URL that must not get our token
	_http.timeout = 30.0
	add_child(_http)
	check()


## Called by the title screen: this launch worked, so keep the pack.
func mark_good() -> void:
	if _meta.get("pending", false):
		_meta["pending"] = false
		_write_meta()


func check() -> void:
	if _http == null or state in [State.CHECKING, State.DOWNLOADING]:
		return
	_set_state(State.CHECKING, "checking for updates")
	_http.download_file = ""
	var err := _http.request(API_URL % _repo, _auth_headers("application/vnd.github+json"))
	if err != OK:
		_set_state(State.FAILED, "offline")
		return
	var res: Array = await _http.request_completed
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		_set_state(State.FAILED, "offline" if res[0] != HTTPRequest.RESULT_SUCCESS else "check failed (%d)" % res[1])
		return
	var release: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	var asset := _pick_asset(release)
	if asset.is_empty():
		_set_state(State.NEEDS_IPA, "new version needs a fresh IPA")
		return
	var sha := str(asset["sha"])
	if sha == _current_id or sha == str(_meta.get("id", "")):
		var ready_state: bool = sha == str(_meta.get("id", "")) and sha != _current_id
		_set_state(State.READY if ready_state else State.UP_TO_DATE,
				"restart to apply" if ready_state else "up to date")
		return
	await _download(asset)


func _pick_asset(release: Variant) -> Dictionary:
	if not (release is Dictionary):
		return {}
	var rx := RegEx.create_from_string("^update-e(\\d+)-([0-9a-f]+)\\.pck$")
	for a: Variant in release.get("assets", []):
		var m := rx.search(str(a.get("name", "")))
		if m != null and int(m.get_string(1)) == _epoch():
			return {"url": str(a["url"]), "sha": m.get_string(2)}
	return {}


func _download(asset: Dictionary) -> void:
	_set_state(State.DOWNLOADING, "downloading update")
	if _http.request(str(asset["url"]), _auth_headers("application/octet-stream")) != OK:
		_set_state(State.FAILED, "download failed")
		return
	var res: Array = await _http.request_completed
	var location := ""
	for h: String in res[2]:
		if h.to_lower().begins_with("location:"):
			location = h.substr(9).strip_edges()
	if res[1] != 302 or location.is_empty():
		_set_state(State.FAILED, "download failed (%d)" % res[1])
		return
	var part := PACK_PATH + ".part"
	_http.download_file = part
	if _http.request(location) != OK:
		_set_state(State.FAILED, "download failed")
		return
	res = await _http.request_completed
	_http.download_file = ""
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		DirAccess.remove_absolute(part)
		_set_state(State.FAILED, "download failed (%d)" % res[1])
		return
	# A pack already mounted this session is open, so only swap the file in for the next launch.
	DirAccess.rename_absolute(part, PACK_PATH)
	_meta = {"id": str(asset["sha"]), "epoch": _epoch(), "base": _base_build(), "pending": false}
	_write_meta()
	_set_state(State.READY, "restart to apply")


func _auth_headers(accept: String) -> PackedStringArray:
	return PackedStringArray(["Authorization: Bearer " + _token, "Accept: " + accept,
			"User-Agent: PocketGridiron", "X-GitHub-Api-Version: 2022-11-28"])


func _set_state(s: State, text: String) -> void:
	state = s
	detail = text
	status_changed.emit()


func _discard(reason: String) -> void:
	push_warning("Updater: dropping update pack (%s)" % reason)
	DirAccess.remove_absolute(PACK_PATH)
	_meta = {}
	_write_meta()


func _base_build() -> String:
	return str(ProjectSettings.get_setting("pocket_gridiron/base_build", "dev"))


func _epoch() -> int:
	return int(ProjectSettings.get_setting("pocket_gridiron/engine_epoch", 1))


func _read_meta() -> Dictionary:
	if not FileAccess.file_exists(META_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
	return parsed if parsed is Dictionary else {}


func _write_meta() -> void:
	var f := FileAccess.open(META_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_meta))
