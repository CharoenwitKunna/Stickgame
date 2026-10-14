class_name SaveStore
extends RefCounted

const SAVE_PATH := "user://army.json"

static func save_army(roster: Array[String], stage: int, path: String = SAVE_PATH) -> bool:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": 1, "stage": stage, "roster": roster}))
	file.flush()
	file.close()
	return DirAccess.rename_absolute(temporary, path) == OK

static func load_army(path: String = SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	var parsed: Variant = json.data
	if not parsed is Dictionary or parsed.get("version", 0) != 1:
		return {}
	var raw_roster: Variant = parsed.get("roster", null)
	if not raw_roster is Array or raw_roster.is_empty():
		return {}
	var roster: Array[String] = []
	for kind in raw_roster:
		if not kind is String or kind not in ["sword", "archer", "shield"]:
			return {}
		roster.append(kind)
	var raw_stage: Variant = parsed.get("stage", 0)
	if not (raw_stage is int or raw_stage is float) or raw_stage < 1 or raw_stage > 100000:
		return {}
	return {"roster": roster, "stage": int(raw_stage)}
