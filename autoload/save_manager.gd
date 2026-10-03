extends Node
## Loads/saves the Profile to user://save.json. Atomic: write save.tmp, keep the previous
## save as save.bak, then rename tmp -> save.json. A corrupt save falls back to the .bak.
## Autosaves when the app is paused/closed (mobile) — callers save after matches, packs
## and lineup changes.

signal saved

const DIR := "user://"
const FILE := "save.json"

var profile := Profile.new()
var path := DIR + FILE
var disabled := false   ## headless batch runs don't touch the real save


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ai-vs-ai") or arg.begins_with("--sim=") or arg == "--nosave":
			disabled = true
	if not disabled:
		profile = load_profile(path)
	GameData.register_rtg(profile)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not disabled and profile.has_team():
			save()


func save() -> bool:
	if disabled:
		return false
	var ok := write_profile(profile, path)
	if ok:
		saved.emit()
	return ok


## Reads a profile; a missing file gives a fresh profile, a corrupt one the .bak (or fresh).
static func load_profile(p_path: String) -> Profile:
	for candidate in [p_path, p_path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(candidate)) == OK and json.data is Dictionary:
			return Profile.from_dict(json.data)
		print_verbose("save: %s is corrupt, trying backup" % candidate)
	return Profile.new()


static func write_profile(prof: Profile, p_path: String) -> bool:
	var tmp := p_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("save: cannot write %s" % tmp)
		return false
	f.store_string(JSON.stringify(prof.to_dict(), "\t"))
	f.close()
	var dir := DirAccess.open(p_path.get_base_dir())
	if dir == null:
		return false
	var name := p_path.get_file()
	if FileAccess.file_exists(p_path):
		if FileAccess.file_exists(p_path + ".bak"):
			dir.remove(name + ".bak")
		dir.rename(name, name + ".bak")
	return dir.rename(tmp.get_file(), name) == OK


## Wipes the save (debug / "reset career").
func reset() -> void:
	profile = Profile.new()
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
