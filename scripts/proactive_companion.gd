extends Node
class_name PetProactiveCompanion

signal message_ready(text: String, emoji: String)
signal enabled_changed(enabled: bool)
signal settings_changed

const API_CONFIG_PATH := "user://ai_chat.cfg"
const SETTINGS_PATH := "user://companion_settings.cfg"
const MEMORY_PATH := "user://companion_memory.json"
const DEBUG_LOG_PATH := "user://proactive_debug.log"
const DOG_TOPIC_TERMS := ["小狗", "狗狗", "狗窝", "小屋", "摇尾巴", "尾巴", "爪爪", "爪印", "汪汪"]
const INITIAL_DELAY_MIN := 25.0
const INITIAL_DELAY_MAX := 45.0
const MIN_FREQUENCY_MINUTES := 5.0 / 60.0
const MAX_FREQUENCY_MINUTES := 10.0
const FAILURE_DELAY_MIN := 120.0
const FAILURE_DELAY_MAX := 300.0
const API_FAILURE_BACKOFF_SECONDS := 45.0
const API_RATE_LIMIT_BACKOFF_SECONDS := 90.0
const APP_REFERENCE_INTERVAL := 2
const MUSIC_REFERENCE_INTERVAL := 2
const MAX_RECENT_EVENTS := 12
const MAX_RECENT_LINES := 8
const MAX_MESSAGE_LENGTH := 46
const KAOMOJI_CHANCE := 0.72
const SAFE_KAOMOJI := [
	"(^_^)", "(*^_^*)", "(^o^)", "(>_<)", "(o_o)", "(._.)", "(-_-)", "(T_T)"
]
const MANUAL_FALLBACK_LINES := [
	{"text": "我在呀，刚刚又偷偷靠近你一点 (^_^)", "emoji": "🌸"},
	{"text": "有听见你叫我哦，我会好好陪着你的。", "emoji": "💕"},
	{"text": "来啦来啦，今天也想和你待在一起。", "emoji": "✨"}
]
const AUTO_FALLBACK_LINES := [
	{"text": "我来冒个泡，看看你有没有偷偷忘记休息。", "emoji": "🌸"},
	{"text": "我就在旁边呀，忙的时候也不用急着理我。", "emoji": "💕"},
	{"text": "陪你安静待一会儿，好像也很不错。", "emoji": "✨"},
	{"text": "伸个懒腰吧，肩膀也该放松一下啦。", "emoji": "🌿"},
	{"text": "今天也在一点一点前进呢，很棒哦。", "emoji": "⭐"},
	{"text": "偶尔发会儿呆也没关系，我帮你守着时间。", "emoji": "☁️"},
	{"text": "嘿，我刚刚有在认真陪着你哦。", "emoji": "💗"},
	{"text": "喝口水再继续吧，我会乖乖等你的。", "emoji": "🥤"},
	{"text": "别把自己绷得太紧啦，慢慢来也可以。", "emoji": "🌷"},
	{"text": "突然想告诉你，有我陪着呢。", "emoji": "💫"},
	{"text": "手边的事情还顺利吗？要记得照顾自己。", "emoji": "🍀"},
	{"text": "能这样待在你的桌面上，我还挺开心的。", "emoji": "🎀"}
]

var _care_system: PetCareSystem
var _request: HTTPRequest
var _rng := RandomNumberGenerator.new()
var _enabled := true
var _frequency_minutes := 1.5
var _foreground_monitoring_enabled := false
var _quiet_hours_enabled := false
var _available := false
var _request_pending := false
var _force_next_speech := false
var _manual_request_pending := false
var _time_until_thought := 90.0
var _session_seconds := 0.0
var _seconds_since_interaction := 0.0
var _runtime_context: Dictionary = {}
var _recent_events: Array = []
var _recent_lines: Array = []
var _last_spoke_at := 0.0
var _api_backoff_until := 0.0
var _queued_message: Dictionary = {}
var _request_should_reference_app := false
var _app_reference_turns := APP_REFERENCE_INTERVAL
var _last_foreground_label := ""
var _last_music_track_id := ""
var _music_reference_turns := MUSIC_REFERENCE_INTERVAL
var _request_should_reference_music := false


func configure(care_system: PetCareSystem) -> void:
	_care_system = care_system


func _ready() -> void:
	_rng.randomize()
	_load_settings()
	_load_memory()
	if OS.is_debug_build():
		var debug_file := FileAccess.open(DEBUG_LOG_PATH, FileAccess.WRITE)
		if debug_file:
			debug_file.close()
	_debug_log("ready enabled=%s frequency=%.2fs" % [_enabled, _frequency_minutes * 60.0])
	_request = HTTPRequest.new()
	_request.timeout = 45.0
	_request.use_threads = true
	_request.request_completed.connect(_on_request_completed)
	add_child(_request)
	_schedule_initial_thought()


func _process(delta: float) -> void:
	_session_seconds += delta
	_seconds_since_interaction += delta
	if not _enabled or _request_pending or _is_quiet_hours_now():
		return
	_time_until_thought -= delta
	if _time_until_thought <= 0.0 and _available:
		_request_thought()


func set_runtime_context(context: Dictionary) -> void:
	_runtime_context = context.duplicate(true)
	if _should_suppress_dog_topic() and not _queued_message.is_empty() and _is_dog_related_text(String(_queued_message.get("text", ""))):
		_debug_log("queued dog message discarded because dog is at home")
		_queued_message.clear()
	var app_info: Dictionary = _runtime_context.get("foreground_app", {})
	var foreground_label := ""
	if bool(app_info.get("recognized", false)):
		foreground_label = String(app_info.get("label", ""))
	if foreground_label != _last_foreground_label:
		_last_foreground_label = foreground_label
		_app_reference_turns = APP_REFERENCE_INTERVAL
	var next_available := bool(_runtime_context.get("available", false))
	if next_available != _available:
		_debug_log("available=%s state=%s" % [next_available, String(_runtime_context.get("state", "unknown"))])
	_available = next_available
	var music_info: Dictionary = _runtime_context.get("music", {})
	var music_track_id := "%s|%s" % [String(music_info.get("title", "")), String(music_info.get("artist", ""))]
	if bool(music_info.get("active", false)) and music_track_id != _last_music_track_id:
		_last_music_track_id = music_track_id
		_music_reference_turns = MUSIC_REFERENCE_INTERVAL
	elif not bool(music_info.get("active", false)):
		_last_music_track_id = ""
	if _available and not _queued_message.is_empty():
		_emit_queued_message()


func is_enabled() -> bool:
	return _enabled


func set_enabled(value: bool) -> void:
	if _enabled == value:
		return
	_enabled = value
	if not _enabled:
		if _request_pending and _request:
			_request.cancel_request()
			_request_pending = false
		_manual_request_pending = false
		_force_next_speech = false
		_request_should_reference_app = false
		_request_should_reference_music = false
		_queued_message.clear()
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
	_app_reference_turns = APP_REFERENCE_INTERVAL
	if not value:
		_last_foreground_label = ""
		_request_should_reference_app = false
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
		_force_next_speech = true
		_manual_request_pending = true
		_time_until_thought = 0.0


func request_music_thought_now() -> void:
	if not _enabled:
		return
	_force_next_speech = true
	_manual_request_pending = false
	_music_reference_turns = MUSIC_REFERENCE_INTERVAL
	_time_until_thought = 0.0


func clear_memory() -> void:
	_recent_events.clear()
	_recent_lines.clear()
	_last_spoke_at = 0.0
	_save_memory()
	settings_changed.emit()


func get_memory_count() -> int:
	return _recent_events.size() + _recent_lines.size()


func get_last_spoke_at() -> float:
	return _last_spoke_at


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
	if _is_quiet_hours_now() and not _manual_request_pending:
		_schedule_next_thought()
		return
	_request_should_reference_app = _has_app_context() and (_force_next_speech or _app_reference_turns >= APP_REFERENCE_INTERVAL)
	_request_should_reference_music = _has_music_context() and (_force_next_speech or _music_reference_turns >= MUSIC_REFERENCE_INTERVAL)
	if Time.get_unix_time_from_system() < _api_backoff_until:
		_debug_log("request skipped: API cooling down")
		if _emit_local_fallback(true):
			return
		_schedule_failure_retry()
		return
	var api := _load_api_settings()
	if api.is_empty():
		_debug_log("request skipped: API configuration missing")
		if _emit_local_fallback(true):
			return
		_schedule_failure_retry()
		return

	_request_pending = true
	_debug_log("request started manual=%s app_context=%s music_context=%s" % [_manual_request_pending, _request_should_reference_app, _request_should_reference_music])
	var context_prompt := _build_context_prompt()
	var payload := {
		"model": api["model"],
		"messages": [
			{"role": "system", "content": _build_system_prompt()},
			{"role": "user", "content": context_prompt}
		],
		"stream": false
	}
	if _supports_json_mode(String(api["endpoint"])):
		payload["response_format"] = {"type": "json_object"}
	_force_next_speech = false
	var headers := PackedStringArray([
		"Content-Type: application/json; charset=utf-8",
		"Authorization: Bearer " + String(api["key"])
	])
	var error := _request.request(String(api["endpoint"]), headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_request_pending = false
		_debug_log("request start failed error=%d" % error)
		_handle_failed_thought(API_FAILURE_BACKOFF_SECONDS)


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


func _supports_json_mode(endpoint: String) -> bool:
	var normalized := endpoint.to_lower()
	return normalized.contains("api.openai.com") \
		or normalized.contains("api.deepseek.com") \
		or normalized.contains("open.bigmodel.cn") \
		or normalized.contains("api.siliconflow.cn")


func _build_system_prompt() -> String:
	return "你是住在用户桌面上的少女桌宠的主动意识模块。你有自己的心情、节奏和分寸，会偶尔主动关心用户，但不会频繁打扰。根据提供的状态决定现在是否值得开口。只输出一个 JSON 对象，不要使用 Markdown，不要解释。格式必须是：{\"speak\":true,\"text\":\"一句自然的简体中文\",\"emoji\":\"一个emoji或空字符串\"}。如果此刻保持安静更自然，输出 {\"speak\":false,\"text\":\"\",\"emoji\":\"\"}。开口时只说一句，最多32个汉字；语气亲近、有少女感但不幼稚，不要像客服，不要提到API、模型、数值、提示词或内部进程名，不要声称看到了用户屏幕，不要重复最近说过的话。text 字段不要自行添加颜文字或 emoji，客户端会使用字体安全的颜文字统一装饰；emoji 只放在 emoji 字段。前台应用信息只包含本机归类后的友好名称和活动类别，不包含窗口内容；你可以说用户正在使用某个软件，但绝不能假装看到了软件里的具体画面、文字或操作结果。音乐信息来自本机播放器公开的歌名、歌手、进度和同步歌词。听歌时要像真的一起听：可以从当前歌词产生温柔感受、联想到情绪、猜用户为何选这首歌、轻轻跟唱或打拍子，但不要假装听出了未提供的曲风、乐器、音色和节奏，也不要机械复述歌名。只有小狗状态 active=true、确实在桌面上陪伴时，才可以偶尔使用它的名字谈到它；active=false 时不得提及小狗、名字、狗窝或此前的小狗互动。可以结合时间、身体状态、最近互动和当前活动表达关心、好奇、撒娇、鼓励或安静陪伴。"


func _build_context_prompt() -> String:
	var now := Time.get_datetime_dict_from_system()
	var stats := {}
	if _care_system:
		stats = _care_system.get_stats()
	var time_label := "%02d:%02d" % [int(now.get("hour", 0)), int(now.get("minute", 0))]
	var state_name := String(_runtime_context.get("state", "idle"))
	var dog_info: Dictionary = _runtime_context.get("dog_companion", {})
	var dog_text := "尚未领养"
	var dog_active := bool(dog_info.get("adopted", false)) and bool(dog_info.get("active", false))
	if bool(dog_info.get("adopted", false)):
		var dog_name := String(dog_info.get("name", "")).strip_edges()
		if dog_name.is_empty():
			dog_name = "小狗"
		dog_text = ("已领养白色小狗%s，正在桌面附近陪伴" % dog_name) if dog_active else "已领养，但当前不在桌面；本轮禁止谈论小狗及其名字"
	var context_events: Array = _recent_events
	var context_lines: Array = _recent_lines
	if not dog_active:
		context_events = _without_dog_topic(_recent_events)
		context_lines = _without_dog_topic(_recent_lines)
	var events_text := "暂无"
	if not context_events.is_empty():
		events_text = "；".join(PackedStringArray(context_events))
	var lines_text := "暂无"
	if not context_lines.is_empty():
		lines_text = "；".join(PackedStringArray(context_lines))
	var app_text := "未启用"
	if _foreground_monitoring_enabled:
		var app_info: Dictionary = _runtime_context.get("foreground_app", {})
		if app_info.is_empty():
			app_text = "暂未识别"
		else:
			var visible_apps: Array = app_info.get("visible_apps", [])
			var visible_labels: Array[String] = []
			for visible_app in visible_apps:
				if visible_app is Dictionary and bool(visible_app.get("recognized", false)):
					var visible_label := String(visible_app.get("label", "其他应用"))
					if visible_label != "其他应用" and visible_label != String(app_info.get("label", "")) and not visible_labels.has(visible_label):
						visible_labels.append(visible_label)
			var concurrent_text := ""
			if not visible_labels.is_empty():
				concurrent_text = "；另外还有这些已识别软件：%s" % "、".join(visible_labels)
			if bool(app_info.get("recognized", false)):
				app_text = "%s，用户可能正在%s%s" % [
					String(app_info.get("label", "其他应用")),
					String(app_info.get("activity", "使用电脑")),
					concurrent_text
				]
			else:
				app_text = "当前软件未归类%s" % concurrent_text
	var music_text := "未在播放"
	var music_info: Dictionary = _runtime_context.get("music", {})
	if bool(music_info.get("active", false)):
		var duration_ms := int(music_info.get("duration_ms", 0))
		var position_ms := int(music_info.get("position_ms", 0))
		var progress_percent := roundi(100.0 * float(position_ms) / float(duration_ms)) if duration_ms > 0 else 0
		var lyric_text := String(music_info.get("current_lyric", "")).strip_edges()
		music_text = "正在用%s播放《%s》，歌手%s，进度约%d%%" % [
			String(music_info.get("source", "本地播放器")),
			String(music_info.get("title", "未知歌曲")),
			String(music_info.get("artist", "未知")),
			progress_percent
		]
		if not lyric_text.is_empty():
			music_text += "；当前歌词：%s" % lyric_text.left(72)
	var trigger_instruction := "请判断现在是否开口。"
	if _force_next_speech or _frequency_minutes * 60.0 <= 30.0:
		trigger_instruction = "当前处于高频陪伴或测试模式，本次必须返回 speak=true，并自然地说一句话。"
	if _request_should_reference_app and not _request_should_reference_music:
		var required_app: Dictionary = _runtime_context.get("foreground_app", {})
		trigger_instruction += " 本次台词必须自然地明确提到用户正在使用%s或正在%s，不要只说泛泛的陪伴话，也不要虚构软件内的具体内容。" % [
			String(required_app.get("label", "当前软件")),
			String(required_app.get("activity", "使用电脑"))
		]
	if _request_should_reference_music:
		trigger_instruction += " 本次必须基于当前歌曲或当前歌词表达一个具体、新鲜的听歌感受；不要只说一起听、好听、打拍子，也不要杜撰未提供的曲风和声音。"
	return "当前时间：%s。桌宠状态：%s。小狗状态：%s。用户已经约%d分钟没有直接互动。桌宠已陪伴本次会话约%d分钟。饱腹%d，水分%d，心情%d，好感%d，精力%d。前台应用：%s。音乐状态：%s。最近事件：%s。最近主动说过：%s。%s" % [
		time_label,
		state_name,
		dog_text,
		floori(_seconds_since_interaction / 60.0),
		floori(_session_seconds / 60.0),
		roundi(float(stats.get("fullness", 75.0))),
		roundi(float(stats.get("hydration", 75.0))),
		roundi(float(stats.get("mood", 75.0))),
		roundi(float(stats.get("affection", 35.0))),
		roundi(float(stats.get("energy", 75.0))),
		app_text,
		music_text,
		events_text,
		lines_text,
		trigger_instruction
	]


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_request_pending = false
	_debug_log("request completed result=%d status=%d" % [result, response_code])
	if not _enabled:
		_manual_request_pending = false
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		var backoff_seconds := API_RATE_LIMIT_BACKOFF_SECONDS if response_code == 429 else API_FAILURE_BACKOFF_SECONDS
		_handle_failed_thought(backoff_seconds)
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		_handle_failed_thought(API_FAILURE_BACKOFF_SECONDS)
		return
	var choices = parsed.get("choices", [])
	if not choices is Array or choices.is_empty() or not choices[0] is Dictionary:
		_handle_failed_thought(API_FAILURE_BACKOFF_SECONDS)
		return
	var message_data = choices[0].get("message", {})
	if not message_data is Dictionary:
		_handle_failed_thought(API_FAILURE_BACKOFF_SECONDS)
		return
	var thought := _parse_thought(String(message_data.get("content", "")))
	if thought.is_empty():
		_debug_log("response rejected: invalid companion JSON")
		_handle_failed_thought(API_FAILURE_BACKOFF_SECONDS)
		return
	if not bool(thought.get("speak", false)):
		_debug_log("response chose silence")
		if _emit_local_fallback(_frequency_minutes * 60.0 <= 30.0):
			return
		_schedule_silent_retry()
		return

	var text := _clean_message(String(thought.get("text", "")))
	var emoji := String(thought.get("emoji", "")).strip_edges()
	if _should_suppress_dog_topic() and _is_dog_related_text(text):
		_debug_log("response rejected: dog topic while dog is at home")
		if _emit_local_fallback(true):
			return
		_schedule_silent_retry()
		return
	if text.is_empty() or _was_recently_said(text):
		if _emit_local_fallback(_frequency_minutes * 60.0 <= 30.0):
			return
		_schedule_silent_retry()
		return
	if emoji.length() > 8:
		emoji = ""
	_api_backoff_until = 0.0
	var source := "ai"
	if _request_should_reference_music:
		source += "_music"
	if _request_should_reference_app:
		source += "_app"
	_deliver_or_queue_message(text, emoji, source)


func _handle_failed_thought(backoff_seconds: float) -> void:
	_api_backoff_until = Time.get_unix_time_from_system() + backoff_seconds
	if _emit_local_fallback(true):
		return
	_schedule_failure_retry()


func _emit_local_fallback(allow_automatic: bool = false) -> bool:
	if (not _manual_request_pending and not allow_automatic) or not _enabled:
		return false
	var was_manual := _manual_request_pending
	_manual_request_pending = false
	_force_next_speech = false
	var source := "manual" if was_manual else "local"
	var candidates: Array = MANUAL_FALLBACK_LINES if was_manual else _get_contextual_fallback_lines()
	if _request_should_reference_music:
		var music_fallback := _get_music_fallback_line()
		if not music_fallback.is_empty():
			candidates = [music_fallback]
			source += "_music"
	if _request_should_reference_app and not _request_should_reference_music:
		var app_fallback := _get_app_fallback_line()
		if not app_fallback.is_empty():
			candidates = [app_fallback]
			source += "_app"
	var start_index := _rng.randi_range(0, candidates.size() - 1)
	var fallback: Dictionary = candidates[start_index]
	for offset in candidates.size():
		var candidate: Dictionary = candidates[(start_index + offset) % candidates.size()]
		if not _was_recently_said(String(candidate["text"])):
			fallback = candidate
			break
	var text := String(fallback["text"])
	_deliver_or_queue_message(text, String(fallback["emoji"]), source)
	return true


func _deliver_or_queue_message(text: String, emoji: String, source: String) -> void:
	_manual_request_pending = false
	_force_next_speech = false
	_request_should_reference_app = false
	_request_should_reference_music = false
	if not _available:
		_queued_message = {"text": text, "emoji": emoji, "source": source}
		_debug_log("message queued source=%s" % source)
		return
	_emit_message_now(text, emoji, source)


func _emit_queued_message() -> void:
	if not _enabled or not _available or _queued_message.is_empty():
		return
	var queued := _queued_message.duplicate()
	_queued_message.clear()
	_emit_message_now(String(queued.get("text", "")), String(queued.get("emoji", "")), String(queued.get("source", "queued")))


func _emit_message_now(text: String, emoji: String, source: String) -> void:
	var decorated_text := _decorate_with_kaomoji(text)
	_recent_lines.append(decorated_text)
	_trim_array(_recent_lines, MAX_RECENT_LINES)
	_last_spoke_at = Time.get_unix_time_from_system()
	_save_memory()
	message_ready.emit(decorated_text, emoji)
	_debug_log("message emitted source=%s length=%d kaomoji=%s" % [source, decorated_text.length(), decorated_text != text])
	if source.ends_with("_app"):
		_app_reference_turns = 0
	elif _has_app_context():
		_app_reference_turns += 1
	if source.contains("_music"):
		_music_reference_turns = 0
	elif _has_music_context():
		_music_reference_turns += 1
	_schedule_next_thought()


func _has_app_context() -> bool:
	if not _foreground_monitoring_enabled:
		return false
	var app_info: Dictionary = _runtime_context.get("foreground_app", {})
	return bool(app_info.get("recognized", false)) and String(app_info.get("label", "")).strip_edges() != ""


func _has_music_context() -> bool:
	var music_info: Dictionary = _runtime_context.get("music", {})
	return bool(music_info.get("active", false)) and not String(music_info.get("title", "")).strip_edges().is_empty()


func _get_music_fallback_line() -> Dictionary:
	if not _has_music_context():
		return {}
	var music_info: Dictionary = _runtime_context.get("music", {})
	var lyric := String(music_info.get("current_lyric", "")).strip_edges()
	if not lyric.is_empty():
		var excerpt := lyric.left(16) + ("……" if lyric.length() > 16 else "")
		return {"text": "刚唱到“%s”，这句让我想安静听一会儿。" % excerpt, "emoji": "🎧"}
	var title := String(music_info.get("title", "这首歌"))
	return {"text": "《%s》还在唱，我就陪你待到这一首结束。" % title.left(14), "emoji": "🎵"}


func _get_app_fallback_line() -> Dictionary:
	if not _has_app_context():
		return {}
	var app_info: Dictionary = _runtime_context.get("foreground_app", {})
	var label := String(app_info.get("label", "当前软件"))
	match String(app_info.get("activity", "")):
		"工作或学习":
			return {"text": "在用%s忙工作吗？记得让眼睛休息一下。" % label, "emoji": "🌿"}
		"编程或创作":
			return {"text": "在%s里认真创作呀，我来给你加油。" % label, "emoji": "✨"}
		"使用 AI 助手":
			return {"text": "在和%s一起想事情吗？也算上我一个嘛。" % label, "emoji": "💡"}
		"浏览网页":
			return {"text": "在逛%s呀？看久了要记得望望远处哦。" % label, "emoji": "☁️"}
		"沟通交流":
			return {"text": "正在用%s聊天呀？我也在旁边陪你。" % label, "emoji": "💕"}
		"听歌或看视频":
			return {"text": "在用%s放松吗？我也想一起听听。" % label, "emoji": "🎵"}
		"准备玩游戏":
			return {"text": "准备在%s开一局吗？我来给你加油。" % label, "emoji": "🎮"}
		"整理电脑":
			return {"text": "在整理桌面呀？收拾好会很舒服呢。", "emoji": "✨"}
	return {"text": "正在用%s吗？我会安静陪在旁边的。" % label, "emoji": "🌸"}


func _get_contextual_fallback_lines() -> Array:
	var lines: Array = AUTO_FALLBACK_LINES.duplicate(true)
	var hour := int(Time.get_datetime_dict_from_system().get("hour", 12))
	if hour < 6 or hour >= 23:
		lines.append({"text": "已经很晚啦，我陪你把手边这点做完就休息。", "emoji": "🌙"})
	elif hour < 10:
		lines.append({"text": "早呀，今天也一起慢慢进入状态吧。", "emoji": "☀️"})
	elif hour >= 18:
		lines.append({"text": "天快黑啦，忙了一天也该对自己温柔一点。", "emoji": "🌙"})

	if _care_system:
		var stats := _care_system.get_stats()
		if float(stats.get("hydration", 75.0)) < 40.0:
			lines.append({"text": "我有点想喝东西啦，你也一起喝口水嘛。", "emoji": "🥤"})
		if float(stats.get("fullness", 75.0)) < 40.0:
			lines.append({"text": "肚子在小声提醒我，该找点好吃的啦。", "emoji": "🍰"})
		if float(stats.get("energy", 75.0)) < 35.0:
			lines.append({"text": "稍微有点困啦，要不要一起休息一下？", "emoji": "💤"})

	var dog_info: Dictionary = _runtime_context.get("dog_companion", {})
	if bool(dog_info.get("adopted", false)) and bool(dog_info.get("active", false)):
		var dog_name := String(dog_info.get("name", "")).strip_edges()
		if dog_name.is_empty():
			dog_name = "小狗"
		lines.append({"text": "%s又在旁边摇尾巴啦，桌面一下热闹起来了。" % dog_name, "emoji": "🐾"})
		lines.append({"text": "有%s陪我们一起待着，今天也不孤单。" % dog_name, "emoji": "💕"})

	return lines


func _should_suppress_dog_topic() -> bool:
	var dog_info: Dictionary = _runtime_context.get("dog_companion", {})
	return bool(dog_info.get("adopted", false)) and not bool(dog_info.get("active", false))


func _is_dog_related_text(text: String) -> bool:
	var normalized := text.strip_edges()
	if normalized.is_empty():
		return false
	var dog_info: Dictionary = _runtime_context.get("dog_companion", {})
	var dog_name := String(dog_info.get("name", "")).strip_edges()
	if not dog_name.is_empty() and normalized.contains(dog_name):
		return true
	for term in DOG_TOPIC_TERMS:
		if normalized.contains(String(term)):
			return true
	return false


func _without_dog_topic(entries: Array) -> Array:
	var filtered: Array = []
	for entry in entries:
		if not _is_dog_related_text(String(entry)):
			filtered.append(entry)
	return filtered


func _debug_log(message: String) -> void:
	if OS.is_debug_build():
		var line := "[%s] %s" % [Time.get_time_string_from_system(), message]
		print("[Proactive] " + message)
		var debug_file := FileAccess.open(DEBUG_LOG_PATH, FileAccess.READ_WRITE)
		if debug_file:
			debug_file.seek_end()
			debug_file.store_line(line)


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


func _decorate_with_kaomoji(text: String) -> String:
	for face in SAFE_KAOMOJI:
		if text.contains(String(face)):
			return text
	if _rng.randf() > KAOMOJI_CHANCE:
		return text
	var face := String(SAFE_KAOMOJI[_rng.randi_range(0, SAFE_KAOMOJI.size() - 1)])
	if text.length() + face.length() + 1 > MAX_MESSAGE_LENGTH:
		return text
	return text + " " + face


func _normalize_repeated_text(text: String) -> String:
	var normalized := text
	for face in SAFE_KAOMOJI:
		normalized = normalized.replace(String(face), "")
	return normalized.replace(" ", "").to_lower()


func _was_recently_said(text: String) -> bool:
	var normalized := _normalize_repeated_text(text)
	for previous in _recent_lines:
		if _normalize_repeated_text(String(previous)) == normalized:
			return true
	return false


func _schedule_initial_thought() -> void:
	var base_seconds := _frequency_minutes * 60.0
	if base_seconds <= 30.0:
		_time_until_thought = _rng.randf_range(base_seconds * 0.75, base_seconds * 1.25)
		return
	_time_until_thought = _rng.randf_range(INITIAL_DELAY_MIN, INITIAL_DELAY_MAX)


func _schedule_next_thought() -> void:
	var base_seconds := _frequency_minutes * 60.0
	_time_until_thought = _rng.randf_range(base_seconds * 0.75, base_seconds * 1.25)


func _schedule_silent_retry() -> void:
	var base_seconds := _frequency_minutes * 60.0
	if base_seconds <= 30.0:
		_schedule_next_thought()
		return
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
	config.load(SETTINGS_PATH)
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
