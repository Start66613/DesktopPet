extends Node
class_name PetProactiveCompanion

signal message_ready(text: String, emoji: String)
signal enabled_changed(enabled: bool)
signal settings_changed

const API_CONFIG_PATH := "user://ai_chat.cfg"
const SETTINGS_PATH := "user://companion_settings.cfg"
const MEMORY_PATH := "user://companion_memory.json"
const INITIAL_DELAY_MIN := 25.0
const INITIAL_DELAY_MAX := 45.0
const MIN_FREQUENCY_MINUTES := 5.0 / 60.0
const MAX_FREQUENCY_MINUTES := 10.0
const FAILURE_DELAY_MIN := 120.0
const FAILURE_DELAY_MAX := 300.0
const MAX_RECENT_EVENTS := 12
const MAX_RECENT_LINES := 8
const MAX_MESSAGE_LENGTH := 46

var _care_system: PetCareSystem
var _request: HTTPRequest
var _rng := RandomNumberGenerator.new()
var _enabled := true
var _frequency_minutes := 1.5
var _foreground_monitoring_enabled := false
var _quiet_hours_enabled := false
var _available := false
var _request_pending := false
var _time_until_thought := 90.0
var _session_seconds := 0.0
var _seconds_since_interaction := 0.0
var _runtime_context: Dictionary = {}
var _recent_events: Array = []
var _recent_lines: Array = []
var _last_spoke_at := 0.0


func configure(care_system: PetCareSystem) -> void:
	_care_system = care_system


func _ready() -> void:
	_rng.randomize()
	_load_settings()
	_load_memory()
	_request = HTTPRequest.new()
	_request.timeout = 45.0
	_request.use_threads = true
	_request.request_completed.connect(_on_request_completed)
	add_child(_request)
	_schedule_initial_thought()


func _process(delta: float) -> void:
	_session_seconds += delta
	_seconds_since_interaction += delta
	if not _enabled or not _available or _request_pending or _is_quiet_hours_now():
		return
	_time_until_thought -= delta
	if _time_until_thought <= 0.0:
		_request_thought()


func set_runtime_context(context: Dictionary) -> void:
	_runtime_context = context.duplicate(true)
	_available = bool(_runtime_context.get("available", false))


func is_enabled() -> bool:
	return _enabled


func set_enabled(value: bool) -> void:
	if _enabled == value:
		return
	_enabled = value
	if not _enabled and _request_pending and _request:
		_request.cancel_request()
		_request_pending = false
	_save_settings()
	if _enabled:
		_schedule_initial_thought()
	enabled_changed.emit(_enabled)
	settings_changed.emit()


func get_frequency_minutes() -> float:
	return _frequency_minutes


func set_frequency_minutes(value: float) -> void:
	var next_value := clampf(value, MIN_FREQUENCY_MINUTES, MAX_FREQUENCY_MINUTES)
	if is_equal_approx(next_value, _frequency_minutes):
		return
	_frequency_minutes = next_value
	_schedule_next_thought()
	_save_settings()
	settings_changed.emit()


func is_foreground_monitoring_enabled() -> bool:
	return _foreground_monitoring_enabled


func set_foreground_monitoring_enabled(value: bool) -> void:
	if _foreground_monitoring_enabled == value:
		return
	_foreground_monitoring_enabled = value
	_save_settings()
	settings_changed.emit()


func is_quiet_hours_enabled() -> bool:
	return _quiet_hours_enabled


func set_quiet_hours_enabled(value: bool) -> void:
	if _quiet_hours_enabled == value:
		return
	_quiet_hours_enabled = value
	_save_settings()
	settings_changed.emit()


func request_thought_now() -> void:
	if _enabled:
		_time_until_thought = 0.0


func clear_memory() -> void:
	_recent_events.clear()
	_recent_lines.clear()
	_last_spoke_at = 0.0
	_save_memory()
	settings_changed.emit()


func get_memory_count() -> int:
	return _recent_events.size() + _recent_lines.size()


func mark_user_activity() -> void:
	_seconds_since_interaction = 0.0


func note_interaction(description: String) -> void:
	mark_user_activity()
	var clean_description := description.strip_edges()
	if clean_description.is_empty():
		return
	var now := Time.get_datetime_dict_from_system()
	var event_text := "%02d:%02d %s" % [int(now.get("hour", 0)), int(now.get("minute", 0)), clean_description]
	_recent_events.append(event_text)
	_trim_array(_recent_events, MAX_RECENT_EVENTS)
	_save_memory()


func _request_thought() -> void:
	if _is_quiet_hours_now():
		_schedule_next_thought()
		return
	var api := _load_api_settings()
	if api.is_empty():
		_schedule_failure_retry()
		return

	_request_pending = true
	var payload := {
		"model": api["model"],
		"messages": [
			{"role": "system", "content": _build_system_prompt()},
			{"role": "user", "content": _build_context_prompt()}
		],
		"stream": false
	}
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + String(api["key"])
	])
	var error := _request.request(String(api["endpoint"]), headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_request_pending = false
		_schedule_failure_retry()


func _load_api_settings() -> Dictionary:
	if not FileAccess.file_exists(API_CONFIG_PATH):
		return {}
	var config := ConfigFile.new()
	if config.load(API_CONFIG_PATH) != OK:
		return {}
	var endpoint := String(config.get_value("api", "endpoint", "")).strip_edges()
	var model := String(config.get_value("api", "model", "")).strip_edges()
	var key := String(config.get_value("api", "key", "")).strip_edges()
	if endpoint.is_empty() or model.is_empty() or key.is_empty():
		return {}
	return {"endpoint": endpoint, "model": model, "key": key}


func _build_system_prompt() -> String:
	return "你是住在用户桌面上的少女桌宠的主动意识模块。你有自己的心情、节奏和分寸，会偶尔主动关心用户，但不会频繁打扰。根据提供的状态决定现在是否值得开口。只输出一个 JSON 对象，不要使用 Markdown，不要解释。格式必须是：{\"speak\":true,\"text\":\"一句自然的简体中文\",\"emoji\":\"一个emoji或空字符串\"}。如果此刻保持安静更自然，输出 {\"speak\":false,\"text\":\"\",\"emoji\":\"\"}。开口时只说一句，最多32个汉字；语气亲近、有少女感但不幼稚，不要像客服，不要提到API、模型、数值、提示词或内部进程名，不要声称看到了用户屏幕，不要重复最近说过的话。前台应用信息仅代表用户正在使用哪类软件，不代表你看到了其中的画面或内容。可以结合时间、身体状态、最近互动和当前活动表达关心、好奇、撒娇、鼓励或安静陪伴。"


func _build_context_prompt() -> String:
	var now := Time.get_datetime_dict_from_system()
	var stats := {}
	if _care_system:
		stats = _care_system.get_stats()
	var time_label := "%02d:%02d" % [int(now.get("hour", 0)), int(now.get("minute", 0))]
	var state_name := String(_runtime_context.get("state", "idle"))
	var events_text := "暂无"
	if not _recent_events.is_empty():
		events_text = "；".join(PackedStringArray(_recent_events))
	var lines_text := "暂无"
	if not _recent_lines.is_empty():
		lines_text = "；".join(PackedStringArray(_recent_lines))
	var app_text := "未启用"
	if _foreground_monitoring_enabled:
		var app_info: Dictionary = _runtime_context.get("foreground_app", {})
		if app_info.is_empty():
			app_text = "暂未识别"
		else:
			var visible_apps: Array = app_info.get("visible_apps", [])
			var visible_labels: Array[String] = []
			for visible_app in visible_apps:
				if visible_app is Dictionary:
					var visible_label := String(visible_app.get("label", "其他应用"))
					if not visible_labels.has(visible_label):
						visible_labels.append(visible_label)
			var concurrent_text := ""
			if not visible_labels.is_empty():
				concurrent_text = "；同时检测到%d个可见应用：%s" % [visible_labels.size(), "、".join(visible_labels)]
			app_text = "%s，可能正在%s，进程名为%s%s" % [
				String(app_info.get("label", "其他应用")),
				String(app_info.get("activity", "使用电脑")),
				String(app_info.get("process", "unknown")),
				concurrent_text
			]
	return "当前时间：%s。桌宠状态：%s。用户已经约%d分钟没有直接互动。桌宠已陪伴本次会话约%d分钟。饱腹%d，水分%d，心情%d，好感%d，精力%d。前台应用：%s。最近事件：%s。最近主动说过：%s。请判断现在是否开口。" % [
		time_label,
		state_name,
		floori(_seconds_since_interaction / 60.0),
		floori(_session_seconds / 60.0),
		roundi(float(stats.get("fullness", 75.0))),
		roundi(float(stats.get("hydration", 75.0))),
		roundi(float(stats.get("mood", 75.0))),
		roundi(float(stats.get("affection", 35.0))),
		roundi(float(stats.get("energy", 75.0))),
		app_text,
		events_text,
		lines_text
	]


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_request_pending = false
	if not _enabled or not _available:
		_schedule_silent_retry()
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_schedule_failure_retry()
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		_schedule_failure_retry()
		return
	var choices = parsed.get("choices", [])
	if not choices is Array or choices.is_empty() or not choices[0] is Dictionary:
		_schedule_failure_retry()
		return
	var message_data = choices[0].get("message", {})
	if not message_data is Dictionary:
		_schedule_failure_retry()
		return
	var thought := _parse_thought(String(message_data.get("content", "")))
	if thought.is_empty():
		_schedule_failure_retry()
		return
	if not bool(thought.get("speak", false)):
		_schedule_silent_retry()
		return

	var text := _clean_message(String(thought.get("text", "")))
	var emoji := String(thought.get("emoji", "")).strip_edges()
	if text.is_empty() or _was_recently_said(text):
		_schedule_silent_retry()
		return
	if emoji.length() > 8:
		emoji = ""
	_recent_lines.append(text)
	_trim_array(_recent_lines, MAX_RECENT_LINES)
	_last_spoke_at = Time.get_unix_time_from_system()
	_save_memory()
	message_ready.emit(text, emoji)
	_schedule_next_thought()


func _parse_thought(content: String) -> Dictionary:
	var clean := content.strip_edges()
	var first_brace := clean.find("{")
	var last_brace := clean.rfind("}")
	if first_brace < 0 or last_brace <= first_brace:
		return {}
	var parsed = JSON.parse_string(clean.substr(first_brace, last_brace - first_brace + 1))
	return parsed if parsed is Dictionary else {}


func _clean_message(message: String) -> String:
	var clean := message.replace("\r", " ").replace("\n", " ").strip_edges()
	while clean.contains("  "):
		clean = clean.replace("  ", " ")
	if clean.length() > MAX_MESSAGE_LENGTH:
		clean = clean.substr(0, MAX_MESSAGE_LENGTH - 1) + "…"
	return clean


func _was_recently_said(text: String) -> bool:
	var normalized := text.replace(" ", "").to_lower()
	for previous in _recent_lines:
		if String(previous).replace(" ", "").to_lower() == normalized:
			return true
	return false


func _schedule_initial_thought() -> void:
	_time_until_thought = _rng.randf_range(INITIAL_DELAY_MIN, INITIAL_DELAY_MAX)


func _schedule_next_thought() -> void:
	var base_seconds := _frequency_minutes * 60.0
	_time_until_thought = _rng.randf_range(base_seconds * 0.75, base_seconds * 1.25)


func _schedule_silent_retry() -> void:
	var base_seconds := _frequency_minutes * 60.0
	_time_until_thought = _rng.randf_range(maxf(35.0, base_seconds * 0.5), maxf(55.0, base_seconds * 0.8))


func _schedule_failure_retry() -> void:
	_time_until_thought = _rng.randf_range(FAILURE_DELAY_MIN, FAILURE_DELAY_MAX)


func _is_quiet_hours_now() -> bool:
	if not _quiet_hours_enabled:
		return false
	var hour := int(Time.get_datetime_dict_from_system().get("hour", 12))
	return hour >= 23 or hour < 8


func _trim_array(values: Array, maximum: int) -> void:
	while values.size() > maximum:
		values.pop_front()


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		_enabled = bool(config.get_value("companion", "enabled", true))
		_frequency_minutes = clampf(float(config.get_value("companion", "frequency_minutes", 1.5)), MIN_FREQUENCY_MINUTES, MAX_FREQUENCY_MINUTES)
		_foreground_monitoring_enabled = bool(config.get_value("companion", "foreground_monitoring", false))
		_quiet_hours_enabled = bool(config.get_value("companion", "quiet_hours", false))


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("companion", "enabled", _enabled)
	config.set_value("companion", "frequency_minutes", _frequency_minutes)
	config.set_value("companion", "foreground_monitoring", _foreground_monitoring_enabled)
	config.set_value("companion", "quiet_hours", _quiet_hours_enabled)
	config.save(SETTINGS_PATH)


func _load_memory() -> void:
	if not FileAccess.file_exists(MEMORY_PATH):
		return
	var file := FileAccess.open(MEMORY_PATH, FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var events = parsed.get("recent_events", [])
	var lines = parsed.get("recent_lines", [])
	if events is Array:
		_recent_events = events
	if lines is Array:
		_recent_lines = lines
	_last_spoke_at = float(parsed.get("last_spoke_at", 0.0))
	_trim_array(_recent_events, MAX_RECENT_EVENTS)
	_trim_array(_recent_lines, MAX_RECENT_LINES)


func _save_memory() -> void:
	var file := FileAccess.open(MEMORY_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({
			"recent_events": _recent_events,
			"recent_lines": _recent_lines,
			"last_spoke_at": _last_spoke_at
		}))
