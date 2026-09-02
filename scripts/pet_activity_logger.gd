extends Node
class_name PetActivityLogger

const LOG_DIR := "user://pet_activity_logs"
const RETENTION_DAYS := 14
const CLEANUP_INTERVAL_SECONDS := 600.0
const MAX_TEXT_LENGTH := 360
const SENSITIVE_KEY_PARTS := ["key", "token", "secret", "password", "authorization", "credential"]

var _cleanup_time_left := 0.0


func _ready() -> void:
	_ensure_log_dir()
	_cleanup_old_logs()
	_cleanup_time_left = CLEANUP_INTERVAL_SECONDS
	set_process(true)


func _process(delta: float) -> void:
	_cleanup_time_left -= delta
	if _cleanup_time_left <= 0.0:
		_cleanup_time_left = CLEANUP_INTERVAL_SECONDS
		_cleanup_old_logs()


func record(event_type: String, message: String, metadata: Dictionary = {}) -> void:
	_ensure_log_dir()
	var path := LOG_DIR.path_join(_today_key() + ".jsonl")
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if not file:
		file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return
	file.seek_end()
	file.store_line(JSON.stringify({
		"time": Time.get_datetime_string_from_system(false, true),
		"type": _clean_text(event_type, 80),
		"message": _clean_text(message, MAX_TEXT_LENGTH),
		"metadata": _sanitize_value(metadata)
	}, "\t"))


func _ensure_log_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR))


func _cleanup_old_logs() -> void:
	var dir := DirAccess.open(LOG_DIR)
	if not dir:
		return
	var now := Time.get_unix_time_from_system()
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".jsonl"):
			var day := file_name.get_basename()
			var file_time := _unix_from_day(day)
			if file_time > 0.0 and (now - file_time) > float(RETENTION_DAYS) * 86400.0:
				dir.remove(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()


func _unix_from_day(day: String) -> float:
	var parts := day.split("-")
	if parts.size() != 3:
		return 0.0
	return Time.get_unix_time_from_datetime_dict({
		"year": int(parts[0]),
		"month": int(parts[1]),
		"day": int(parts[2]),
		"hour": 0,
		"minute": 0,
		"second": 0
	})


func _sanitize_value(value):
	if value is Dictionary:
		var output := {}
		for raw_key in value.keys():
			var key := String(raw_key)
			output[key] = "[redacted]" if _is_sensitive_key(key) else _sanitize_value(value[raw_key])
		return output
	if value is Array:
		var output: Array = []
		for index in mini(value.size(), 20):
			output.append(_sanitize_value(value[index]))
		return output
	if value is String:
		return _clean_text(value, MAX_TEXT_LENGTH)
	if value is int or value is float or value is bool:
		return value
	return str(value).left(MAX_TEXT_LENGTH)


func _is_sensitive_key(key: String) -> bool:
	var normalized := key.to_lower()
	for part in SENSITIVE_KEY_PARTS:
		if normalized.contains(part):
			return true
	return false


func _clean_text(text: String, maximum: int) -> String:
	var clean := text.replace("\r", " ").replace("\n", " ").strip_edges()
	while clean.contains("  "):
		clean = clean.replace("  ", " ")
	return clean.left(maximum)


func _today_key() -> String:
	var date := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(date.get("year", 0)), int(date.get("month", 0)), int(date.get("day", 0))]
