extends Node
class_name PetScreenAwarenessService

signal analysis_started
signal analysis_ready(result: Dictionary)
signal analysis_failed(message: String)
signal settings_changed
signal status_changed

const API_CONFIG_PATH := "user://ai_chat.cfg"
const SETTINGS_PATH := "user://companion_settings.cfg"
const MAX_IMAGE_EDGE := 1120
const JPEG_QUALITY := 0.68
const KEYFRAME_COUNT := 3
const KEYFRAME_DELAY_SECONDS := 0.75
const LOCAL_SAMPLE_INTERVAL := 2.5
const SCHEDULED_OBSERVATION_SECONDS := 10.0 * 60.0
const AUTO_REQUEST_COOLDOWN := 75.0
const CHANGE_SCORE_THRESHOLD := 0.035
const CHANGE_RATIO_THRESHOLD := 0.10
const MIN_SPEAK_CONFIDENCE := 0.62
const DEFAULT_DAILY_LIMIT := 24
const DEFAULT_BLACKLIST := "1password, bitwarden, keepass, passwordsafe, authy, 银行, bank"
const VALID_MODES := ["auto", "game", "work", "general"]
const ChangeDetector := preload("res://scripts/screen_change_detector.gd")
const ContextMemory := preload("res://scripts/screen_context_memory.gd")

var _request: HTTPRequest
var _change_detector = ChangeDetector.new()
var _context_memory = ContextMemory.new()
var _enabled := false
var _auto_enabled := false
var _paused := false
var _mode := "auto"
var _daily_limit := DEFAULT_DAILY_LIMIT
var _blacklist_text := DEFAULT_BLACKLIST
var _model_override := ""
var _request_pending := false
var _capture_pending := false
var _auto_available := true
var _local_sample_time_left := 0.0
var _scheduled_time_left := SCHEDULED_OBSERVATION_SECONDS
var _last_auto_request_at := 0.0
var _last_result: Dictionary = {}
var _last_analysis_at := 0.0
var _last_observation_reason := ""
var _last_status := "等待授权"
var _last_foreground_info: Dictionary = {}
var _last_foreground_process := ""
var _change_pending := false
var _change_reason := ""
var _stable_samples := 0
var _daily_date := ""
var _daily_request_count := 0
var _last_scene_signature := ""


func _ready() -> void:
	_load_settings()
	_request = HTTPRequest.new()
	_request.timeout = 75.0
	_request.use_threads = true
	_request.request_completed.connect(_on_request_completed)
	add_child(_request)
	_reset_daily_counter_if_needed()
	set_process(true)


func _process(delta: float) -> void:
	if not _enabled or not _auto_enabled or _paused or not _auto_available or is_busy():
		return
	_local_sample_time_left -= delta
	_scheduled_time_left -= delta
	if _local_sample_time_left <= 0.0:
		_local_sample_time_left = LOCAL_SAMPLE_INTERVAL
		_evaluate_local_screen_change()
	if _scheduled_time_left <= 0.0 and _can_start_automatic_request():
		request_analysis("scheduled", false)


func is_enabled() -> bool:
	return _enabled


func set_enabled(value: bool) -> void:
	if _enabled == value:
		return
	_enabled = value
	if not _enabled:
		_auto_enabled = false
		_cancel_pending_work()
		_change_detector.reset()
		_set_status("画面感知已关闭")
	else:
		_local_sample_time_left = 0.0
		_set_status("已授权，截图仅在内存中处理")
	_save_settings()
	settings_changed.emit()


func is_auto_enabled() -> bool:
	return _auto_enabled


func set_auto_enabled(value: bool) -> void:
	var next_value := value and _enabled
	if _auto_enabled == next_value:
		return
	_auto_enabled = next_value
	_local_sample_time_left = 0.0
	_scheduled_time_left = SCHEDULED_OBSERVATION_SECONDS
	_change_pending = false
	_set_status("正在本地观察画面变化" if _auto_enabled else "仅在你点击时观察")
	_save_settings()
	settings_changed.emit()


func is_paused() -> bool:
	return _paused


func set_paused(value: bool) -> void:
	if _paused == value:
		return
	_paused = value
	if _paused:
		_cancel_pending_work()
		_change_pending = false
		_set_status("已暂停，不会截取或上传画面")
	else:
		_local_sample_time_left = 0.0
		_set_status("已恢复画面感知")
	_save_settings()
	settings_changed.emit()


func get_mode() -> String:
	return _mode


func set_mode(value: String) -> void:
	var cleaned := value.to_lower().strip_edges()
	if not VALID_MODES.has(cleaned):
		cleaned = "auto"
	if cleaned == _mode:
		return
	_mode = cleaned
	_save_settings()
	settings_changed.emit()


func get_daily_limit() -> int:
	return _daily_limit


func set_daily_limit(value: int) -> void:
	var cleaned := clampi(value, 1, 60)
	if cleaned == _daily_limit:
		return
	_daily_limit = cleaned
	_save_settings()
	settings_changed.emit()


func get_daily_usage() -> int:
	_reset_daily_counter_if_needed()
	return _daily_request_count


func get_blacklist_text() -> String:
	return _blacklist_text


func set_blacklist_text(value: String) -> void:
	var cleaned := value.replace("\r", "").replace("\n", ",").strip_edges().left(360)
	if cleaned == _blacklist_text:
		return
	_blacklist_text = cleaned
	_save_settings()
	settings_changed.emit()


func get_model_override() -> String:
	return _model_override


func set_model_override(value: String) -> void:
	var cleaned := value.strip_edges().left(96)
	if cleaned == _model_override:
		return
	_model_override = cleaned
	_save_settings()
	settings_changed.emit()


func is_busy() -> bool:
	return _request_pending or _capture_pending


func set_auto_available(value: bool) -> void:
	_auto_available = value


func set_foreground_context(info: Dictionary) -> void:
	_last_foreground_info = info.duplicate(true)
	var process_name := String(info.get("process", "")).to_lower().trim_suffix(".exe")
	if process_name == _last_foreground_process:
		return
	var had_process := not _last_foreground_process.is_empty()
	_last_foreground_process = process_name
	if had_process and not process_name.is_empty() and _enabled and _auto_enabled and not _paused:
		_change_pending = true
		_change_reason = "app_switch"
		_stable_samples = 0


func get_last_result() -> Dictionary:
	return _last_result.duplicate(true)


func get_last_analysis_at() -> float:
	return _last_analysis_at


func get_last_observation_reason() -> String:
	return _last_observation_reason


func get_status_summary() -> String:
	return _last_status


func get_short_term_memory_count() -> int:
	return _context_memory.size()


func clear_short_term_memory() -> void:
	_context_memory.clear()
	_last_scene_signature = ""
	_set_status("短期画面记忆已清空")
	settings_changed.emit()


func request_analysis(reason := "manual", force := true) -> void:
	_last_observation_reason = reason
	if not _enabled:
		analysis_failed.emit("要先允许我看看当前屏幕哦。")
		return
	if _paused:
		analysis_failed.emit("我现在闭着眼睛呢，先取消暂停吧。")
		return
	if is_busy():
		analysis_failed.emit("我还在认真看刚才的画面呢。")
		return
	if _is_sensitive_foreground():
		_set_status("已跳过隐私名单中的应用")
		if force:
			analysis_failed.emit("这个应用在隐私名单里，我就不偷看啦。")
		return
	_reset_daily_counter_if_needed()
	if _daily_request_count >= _daily_limit:
		_set_status("今日视觉额度已用完 %d/%d" % [_daily_request_count, _daily_limit])
		if force:
			analysis_failed.emit("今天看屏幕的次数用完啦，明天再陪你看哦。")
		return
	var api := _load_api_settings()
	if api.is_empty():
		analysis_failed.emit("还没有配置 AI API，我暂时看不懂画面呀。")
		return
	_capture_pending = true
	_set_status("正在取 3 个短暂关键帧……")
	analysis_started.emit()
	var keyframes := await _capture_keyframes()
	_capture_pending = false
	if _paused or not _enabled:
		return
	if keyframes.is_empty():
		analysis_failed.emit("我刚才眨了下眼，没截到屏幕画面，再试一次吧。")
		return
	_send_analysis_request(api, keyframes, reason)


func _evaluate_local_screen_change() -> void:
	if _is_sensitive_foreground():
		_change_pending = false
		_set_status("已跳过隐私名单中的应用")
		return
	var screen_image := _capture_screen_image()
	if not screen_image:
		return
	var change := _change_detector.evaluate(screen_image)
	if not bool(change.get("valid", false)):
		return
	if not bool(change.get("has_baseline", false)):
		_set_status("本地变化检测已就绪，尚未上传图片")
		return
	var score := float(change.get("score", 0.0))
	var changed_ratio := float(change.get("changed_ratio", 0.0))
	if score >= CHANGE_SCORE_THRESHOLD or changed_ratio >= CHANGE_RATIO_THRESHOLD:
		_change_pending = true
		if _change_reason.is_empty():
			_change_reason = "major_change"
		_stable_samples = 0
		_set_status("检测到画面变化，等待画面稳定")
		return
	if not _change_pending:
		return
	_stable_samples += 1
	if _stable_samples < 2 or not _can_start_automatic_request():
		return
	var reason := _change_reason if not _change_reason.is_empty() else "major_change"
	_change_pending = false
	_change_reason = ""
	_stable_samples = 0
	request_analysis(reason, false)


func _capture_keyframes() -> Array[PackedByteArray]:
	var frames: Array[PackedByteArray] = []
	for index in KEYFRAME_COUNT:
		if not _capture_pending or not _enabled or _paused:
			break
		var image := _capture_screen_image()
		if image:
			_prepare_upload_image(image)
			var bytes := image.save_jpg_to_buffer(JPEG_QUALITY)
			if not bytes.is_empty():
				frames.append(bytes)
		if index < KEYFRAME_COUNT - 1:
			await get_tree().create_timer(KEYFRAME_DELAY_SECONDS).timeout
	return frames


func _capture_screen_image() -> Image:
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = 0
	var image := DisplayServer.screen_get_image(screen)
	return image if image and not image.is_empty() else null


func _prepare_upload_image(image: Image) -> void:
	var longest := maxi(image.get_width(), image.get_height())
	if longest <= MAX_IMAGE_EDGE:
		return
	var ratio := float(MAX_IMAGE_EDGE) / float(longest)
	image.resize(
		maxi(1, roundi(image.get_width() * ratio)),
		maxi(1, roundi(image.get_height() * ratio)),
		Image.INTERPOLATE_LANCZOS
	)


func _send_analysis_request(api: Dictionary, frames: Array[PackedByteArray], reason: String) -> void:
	var content: Array = [{
		"type": "text",
		"text": _build_user_prompt(reason)
	}]
	for index in frames.size():
		content.append({
			"type": "image_url",
			"image_url": {
				"url": "data:image/jpeg;base64," + Marshalls.raw_to_base64(frames[index]),
				"detail": "low"
			}
		})

	var payload := {
		"model": api["model"],
		"messages": [
			{"role": "system", "content": _system_prompt()},
			{"role": "user", "content": content}
		],
		"stream": false,
		"max_tokens": 520
	}
	var headers := PackedStringArray([
		"Content-Type: application/json; charset=utf-8",
		"Authorization: Bearer " + String(api["key"])
	])
	_request_pending = true
	_daily_request_count += 1
	_last_auto_request_at = Time.get_unix_time_from_system()
	_scheduled_time_left = SCHEDULED_OBSERVATION_SECONDS
	_save_settings()
	_set_status("画面已上传，正在理解当前任务……")
	var error := _request.request(String(api["endpoint"]), headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_request_pending = false
		analysis_failed.emit("我没能把画面看清楚，网络好像晃了一下。")


func _system_prompt() -> String:
	return """你是一个住在桌面的少女伙伴，负责克制、可靠的屏幕理解。输入是约1.5秒内的连续关键帧。你的目标不是描述截图，而是判断用户正在进行的任务、是否发生值得回应的事件，并在攻略提示、工作建议、成就赞赏、剧情共情或保持安静之间选择。忽略画面中的桌宠自身、桌宠设置窗、气泡和音乐悬浮窗。绝不能逐字转录密码、密钥、验证码、账号、聊天正文、私人文件名、支付信息或其他敏感文本。若画面含登录、支付、密码管理、私密聊天等敏感内容，sensitive=true，其余描述留空并保持沉默。不要把不确定内容说成事实。
只输出一个 JSON 对象，不要 Markdown：{"scene_type":"game|office|browser|media|communication|other","activity":"用户大概在做什么","event":"app_switch|game_result|task_progress|error|idle|none","confidence":0.0,"importance":0.0,"task_summary":"可供下一次理解的短期任务摘要","suggestion":"一条具体且有帮助的建议","should_speak":true,"text":"桌宠自然说的一句话","emoji":"一个emoji","sensitive":false}。confidence 和 importance 范围 0 到 1。只有重要事件、明确可用的建议、自然赞赏或情绪共鸣才 should_speak=true；普通页面变化应保持安静。text 最多42个简体中文字符，像熟悉的少女伙伴，亲近、活泼但不幼稚，可自然带一个颜文字。"""


func _build_user_prompt(reason: String) -> String:
	var foreground := "未知应用"
	if not _last_foreground_info.is_empty():
		foreground = "%s（%s）" % [String(_last_foreground_info.get("label", "其他应用")), String(_last_foreground_info.get("activity", "使用电脑"))]
	return """观察原因：%s
偏好模式：%s
当前前台应用（仅本机进程分类）：%s
最近30分钟的结构化画面摘要：%s
请比较这些按时间排列的关键帧，识别变化和当前任务。优先给出与正在做的事情直接相关的帮助；没有把握或没有新信息时 should_speak=false。""" % [
		_reason_label(reason), _mode_label(_mode), foreground, _context_memory.get_prompt_context()
	]


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_request_pending = false
	if _paused or not _enabled:
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_status("网络中断，本次未完成分析")
		analysis_failed.emit("网络刚才断了一下，我没看清屏幕。")
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if response_code < 200 or response_code >= 300:
		var friendly := _friendly_api_error(response_code, parsed)
		_set_status(friendly)
		analysis_failed.emit(friendly)
		return
	var awareness := _extract_awareness(parsed)
	if awareness.is_empty():
		_set_status("模型返回格式不完整")
		analysis_failed.emit("我看懂了一点，但回答格式有点乱，换个视觉模型会更稳哦。")
		return
	var normalized := _normalize_awareness(awareness)
	if normalized.is_empty():
		analysis_failed.emit("这组画面里暂时没有识别出可用信息。")
		return
	_last_analysis_at = Time.get_unix_time_from_system()
	if bool(normalized.get("sensitive", false)):
		_last_result = {
			"scene_type": "other", "activity": "敏感画面已跳过", "scene": "敏感画面已跳过",
			"event": "none", "confidence": 1.0, "importance": 0.0,
			"task_summary": "", "suggestion": "", "should_speak": false, "speak": false,
			"text": "", "emoji": "🔒", "sensitive": true,
			"reason": _last_observation_reason, "uploaded": true
		}
		_set_status("模型识别为敏感画面，内容未记忆")
		analysis_ready.emit(get_last_result())
		return

	_apply_speech_policy(normalized)
	_context_memory.remember(normalized)
	_last_result = normalized
	_set_status("理解为：%s · 置信度 %d%%" % [String(normalized.get("activity", "当前任务")), roundi(float(normalized.get("confidence", 0.0)) * 100.0)])
	analysis_ready.emit(get_last_result())


func _extract_awareness(parsed) -> Dictionary:
	if not parsed is Dictionary:
		return {}
	var choices = parsed.get("choices", [])
	if not choices is Array or choices.is_empty() or not choices[0] is Dictionary:
		return {}
	var message = choices[0].get("message", {})
	if not message is Dictionary:
		return {}
	return _parse_json_object(String(message.get("content", "")).strip_edges())


func _normalize_awareness(raw: Dictionary) -> Dictionary:
	var scene_type := String(raw.get("scene_type", "other")).to_lower()
	if not ["game", "office", "browser", "media", "communication", "other"].has(scene_type):
		scene_type = "other"
	var event := String(raw.get("event", "none")).to_lower()
	if not ["app_switch", "game_result", "task_progress", "error", "idle", "none"].has(event):
		event = "none"
	var activity := _clean_text(String(raw.get("activity", raw.get("scene", ""))), 84)
	var suggestion := _clean_text(String(raw.get("suggestion", "")), 110)
	var speech := _clean_text(String(raw.get("text", "")), 48)
	if activity.is_empty() and suggestion.is_empty() and speech.is_empty() and not bool(raw.get("sensitive", false)):
		return {}
	return {
		"scene_type": scene_type,
		"activity": activity,
		"scene": activity,
		"event": event,
		"confidence": clampf(float(raw.get("confidence", 0.5)), 0.0, 1.0),
		"importance": clampf(float(raw.get("importance", 0.4)), 0.0, 1.0),
		"task_summary": _clean_text(String(raw.get("task_summary", "")), 110),
		"suggestion": suggestion,
		"should_speak": bool(raw.get("should_speak", raw.get("speak", false))),
		"speak": bool(raw.get("should_speak", raw.get("speak", false))),
		"text": speech,
		"emoji": String(raw.get("emoji", "👀")).strip_edges().left(8),
		"sensitive": bool(raw.get("sensitive", false)),
		"reason": _last_observation_reason,
		"uploaded": true
	}


func _apply_speech_policy(result: Dictionary) -> void:
	var confidence := float(result.get("confidence", 0.0))
	var importance := float(result.get("importance", 0.0))
	var signature := _scene_signature(result)
	var duplicate := not signature.is_empty() and signature == _last_scene_signature
	var should_speak := bool(result.get("should_speak", false)) and confidence >= MIN_SPEAK_CONFIDENCE
	if duplicate and importance < 0.78:
		should_speak = false
	if String(result.get("text", "")).is_empty():
		should_speak = false
	result["should_speak"] = should_speak
	result["speak"] = should_speak
	result["duplicate"] = duplicate
	if not signature.is_empty():
		_last_scene_signature = signature


func _scene_signature(result: Dictionary) -> String:
	var combined := "%s|%s|%s" % [result.get("scene_type", "other"), result.get("activity", ""), result.get("task_summary", "")]
	return combined.to_lower().replace(" ", "").left(160)


func _can_start_automatic_request() -> bool:
	_reset_daily_counter_if_needed()
	if _daily_request_count >= _daily_limit or _is_sensitive_foreground():
		return false
	return Time.get_unix_time_from_system() - _last_auto_request_at >= AUTO_REQUEST_COOLDOWN


func _is_sensitive_foreground() -> bool:
	var process_name := String(_last_foreground_info.get("process", "")).to_lower().trim_suffix(".exe")
	var label := String(_last_foreground_info.get("label", "")).to_lower()
	if process_name.is_empty() and label.is_empty():
		return false
	for raw_term in _blacklist_text.replace("，", ",").replace(";", ",").split(",", false):
		var term := String(raw_term).to_lower().strip_edges().trim_suffix(".exe")
		if not term.is_empty() and (process_name.contains(term) or label.contains(term)):
			return true
	return false


func _load_api_settings() -> Dictionary:
	if not FileAccess.file_exists(API_CONFIG_PATH):
		return {}
	var config := ConfigFile.new()
	if config.load(API_CONFIG_PATH) != OK:
		return {}
	var endpoint := String(config.get_value("api", "endpoint", "")).strip_edges()
	var chat_model := String(config.get_value("api", "model", "")).strip_edges()
	var key := String(config.get_value("api", "key", "")).strip_edges()
	var model := _model_override if not _model_override.is_empty() else chat_model
	if endpoint.is_empty() or model.is_empty() or key.is_empty():
		return {}
	return {"endpoint": endpoint, "model": model, "key": key}


func _friendly_api_error(response_code: int, parsed) -> String:
	var detail := ""
	if parsed is Dictionary:
		var error_data = parsed.get("error", {})
		if error_data is Dictionary:
			detail = String(error_data.get("message", "")).to_lower()
	if response_code == 401:
		return "我没认出这把 API 钥匙，先检查一下设置吧。"
	if response_code == 403:
		return "这个模型还没有看图权限，换个视觉模型试试吧。"
	if response_code == 404:
		return "找不到这个视觉模型，检查一下模型名吧。"
	if response_code == 429:
		return "我现在有点忙，过一会儿再看屏幕吧。"
	if detail.contains("image") or detail.contains("vision") or detail.contains("multimodal"):
		return "当前模型好像不会看图片，填一个支持视觉的模型吧。"
	if response_code >= 500:
		return "视觉服务打了个盹，等一下再试试吧。"
	return "这次没看成，当前模型可能不支持屏幕图片。"


func _parse_json_object(content: String) -> Dictionary:
	var first := content.find("{")
	var last := content.rfind("}")
	if first < 0 or last <= first:
		return {}
	var parsed = JSON.parse_string(content.substr(first, last - first + 1))
	return parsed if parsed is Dictionary else {}


func _clean_text(value: String, maximum: int) -> String:
	var clean := value.replace("\r", " ").replace("\n", " ").strip_edges()
	while clean.contains("  "):
		clean = clean.replace("  ", " ")
	return clean.left(maximum)


func _today_key() -> String:
	var date := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(date.get("year", 0)), int(date.get("month", 0)), int(date.get("day", 0))]


func _reset_daily_counter_if_needed() -> void:
	var today := _today_key()
	if _daily_date == today:
		return
	_daily_date = today
	_daily_request_count = 0
	_save_settings()


func _cancel_pending_work() -> void:
	_capture_pending = false
	if _request_pending and _request:
		_request.cancel_request()
	_request_pending = false


func _set_status(value: String) -> void:
	if value == _last_status:
		return
	_last_status = value
	status_changed.emit()


func _reason_label(reason: String) -> String:
	match reason:
		"app_switch": return "切换了前台应用"
		"major_change": return "画面发生明显变化并已稳定"
		"scheduled": return "长时间任务复查"
		"game_result": return "可能出现游戏结算或重要事件"
		_: return "用户主动让我看看"


func _mode_label(value: String) -> String:
	match value:
		"game": return "游戏助手：优先攻略、战况、成就和剧情共情"
		"work": return "工作助手：优先错误、进度、排版和效率建议"
		"general": return "日常陪伴：优先情绪共鸣和轻量提醒"
		_: return "自动判断当前场景"


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	_enabled = bool(config.get_value("screen_awareness", "enabled", false))
	_auto_enabled = bool(config.get_value("screen_awareness", "auto_enabled", false)) and _enabled
	_paused = bool(config.get_value("screen_awareness", "paused", false))
	_mode = String(config.get_value("screen_awareness", "mode", "auto"))
	if not VALID_MODES.has(_mode):
		_mode = "auto"
	_daily_limit = clampi(int(config.get_value("screen_awareness", "daily_limit", DEFAULT_DAILY_LIMIT)), 1, 60)
	_blacklist_text = String(config.get_value("screen_awareness", "blacklist", DEFAULT_BLACKLIST)).strip_edges()
	_model_override = String(config.get_value("screen_awareness", "model", "")).strip_edges()
	_daily_date = String(config.get_value("screen_awareness", "daily_date", ""))
	_daily_request_count = maxi(0, int(config.get_value("screen_awareness", "daily_request_count", 0)))


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("screen_awareness", "enabled", _enabled)
	config.set_value("screen_awareness", "auto_enabled", _auto_enabled)
	config.set_value("screen_awareness", "paused", _paused)
	config.set_value("screen_awareness", "mode", _mode)
	config.set_value("screen_awareness", "daily_limit", _daily_limit)
	config.set_value("screen_awareness", "blacklist", _blacklist_text)
	config.set_value("screen_awareness", "model", _model_override)
	config.set_value("screen_awareness", "daily_date", _daily_date)
	config.set_value("screen_awareness", "daily_request_count", _daily_request_count)
	config.save(SETTINGS_PATH)
