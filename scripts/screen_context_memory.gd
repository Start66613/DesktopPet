extends RefCounted
class_name PetScreenContextMemory

const MAX_ENTRIES := 8
const MEMORY_TTL_SECONDS := 30.0 * 60.0

var _entries: Array = []


func remember(result: Dictionary) -> void:
	_prune()
	if bool(result.get("sensitive", false)):
		return
	var entry := {
		"time": Time.get_unix_time_from_system(),
		"scene_type": _clean(String(result.get("scene_type", "other")), 20),
		"activity": _clean(String(result.get("activity", result.get("scene", ""))), 80),
		"event": _clean(String(result.get("event", "none")), 24),
		"task_summary": _clean(String(result.get("task_summary", "")), 100),
		"suggestion": _clean(String(result.get("suggestion", "")), 100),
		"confidence": clampf(float(result.get("confidence", 0.0)), 0.0, 1.0)
	}
	if String(entry["activity"]).is_empty() and String(entry["task_summary"]).is_empty():
		return
	_entries.append(entry)
	while _entries.size() > MAX_ENTRIES:
		_entries.pop_front()


func clear() -> void:
	_entries.clear()


func size() -> int:
	_prune()
	return _entries.size()


func get_recent_entries() -> Array:
	_prune()
	return _entries.duplicate(true)


func get_prompt_context() -> String:
	_prune()
	if _entries.is_empty():
		return "暂无先前画面摘要"
	var compact: Array = []
	for entry in _entries:
		compact.append({
			"scene_type": entry.get("scene_type", "other"),
			"activity": entry.get("activity", ""),
			"event": entry.get("event", "none"),
			"task_summary": entry.get("task_summary", "")
		})
	return JSON.stringify(compact)


func _prune() -> void:
	var cutoff := Time.get_unix_time_from_system() - MEMORY_TTL_SECONDS
	var kept: Array = []
	for entry in _entries:
		if float(entry.get("time", 0.0)) >= cutoff:
			kept.append(entry)
	_entries = kept


func _clean(value: String, maximum: int) -> String:
	var clean := value.replace("\r", " ").replace("\n", " ").strip_edges()
	while clean.contains("  "):
		clean = clean.replace("  ", " ")
	return clean.left(maximum)
