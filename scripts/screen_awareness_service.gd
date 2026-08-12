extends Node
class_name PetScreenAwarenessService

signal analysis_started
signal analysis_ready(result: Dictionary)
signal analysis_failed(message: String)
signal settings_changed

const API_CONFIG_PATH := "user://ai_chat.cfg"
const SETTINGS_PATH := "user://companion_settings.cfg"
const MAX_IMAGE_EDGE := 1280
const JPEG_QUALITY := 0.72
const AUTO_INTERVAL_SECONDS := 10.0 * 60.0

var _request: HTTPRequest
var _enabled := false
var _auto_enabled := false
var _model_override := ""
var _request_pending := false
var _auto_time_left := AUTO_INTERVAL_SECONDS
var _last_result: Dictionary = {}
var _last_analysis_at := 0.0
var _auto_available := true


func _ready() -> void:
	_load_settings()
	_request = HTTPRequest.new()
	_request.timeout = 60.0
	_request.use_threads = true
	_request.request_completed.connect(_on_request_completed)
	add_child(_request)
	set_process(true)


func _process(delta: float) -> void:
	if not _enabled or not _auto_enabled or not _auto_available or _request_pending:
		return
	_auto_time_left -= delta
	if _auto_time_left <= 0.0:
		request_analysis()


func is_enabled() -> bool:
	return _enabled


func set_enabled(value: bool) -> void:
	if _enabled == value:
		return
	_enabled = value
	if not _enabled:
		_auto_enabled = false
		if _request_pending:
			_request.cancel_request()
			_request_pending = false
	_save_settings()
	settings_changed.emit()


func is_auto_enabled() -> bool:
	return _auto_enabled


func set_auto_enabled(value: bool) -> void:
	var next_value := value and _enabled
	if _auto_enabled == next_value:
		return
	_auto_enabled = next_value
	_auto_time_left = AUTO_INTERVAL_SECONDS
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
	return _request_pending


func set_auto_available(value: bool) -> void:
	_auto_available = value


func get_last_result() -> Dictionary:
	return _last_result.duplicate(true)


func get_last_analysis_at() -> float:
	return _last_analysis_at


func request_analysis() -> void:
	if not _enabled:
		analysis_failed.emit("要先允许我看看当前屏幕哦。")
		return
	if _request_pending:
		analysis_failed.emit("我还在认真看刚才的画面呢。")
		return
	var api := _load_api_settings()
	if api.is_empty():
		analysis_failed.emit("还没有配置 AI API，我暂时看不懂画面呀。")
		return
	var screen_image := DisplayServer.screen_get_image(DisplayServer.window_get_current_screen())
	if not screen_image or screen_image.is_empty():
		analysis_failed.emit("我刚才眨了下眼，没截到屏幕画面，再试一次吧。")
		return
	var width := screen_image.get_width()
	var height := screen_image.get_height()
	var longest := maxi(width, height)
	if longest > MAX_IMAGE_EDGE:
		var ratio := float(MAX_IMAGE_EDGE) / float(longest)
		screen_image.resize(maxi(1, roundi(width * ratio)), maxi(1, roundi(height * ratio)), Image.INTERPOLATE_LANCZOS)
	var image_bytes := screen_image.save_jpg_to_buffer(JPEG_QUALITY)
	if image_bytes.is_empty():
		analysis_failed.emit("画面压缩失败啦，我再整理一下眼镜。")
		return

	_request_pending = true
	_auto_time_left = AUTO_INTERVAL_SECONDS
	analysis_started.emit()
	var image_url := "data:image/jpeg;base64," + Marshalls.raw_to_base64(image_bytes)
	var payload := {
		"model": api["model"],
		"messages": [
			{
				"role": "system",
				"content": "你是桌面少女助手的屏幕感知模块。只根据截图做高层次判断，忽略截图中的桌宠自身、设置面板、气泡和播放器悬浮窗。不要逐字抄录密码、密钥、聊天内容、账号、私人文件名或其他敏感文本。只输出一个 JSON 对象，不使用 Markdown：{\"scene\":\"用户大概在做什么\",\"suggestion\":\"一条具体且有帮助的建议\",\"speak\":true,\"text\":\"桌宠自然说的一句话\",\"emoji\":\"一个emoji\"}。不确定时要明确说大概或可能，不得编造具体内容。text 最多40个简体中文字符，亲近但不幼稚。"
			},
			{
				"role": "user",
				"content": [
					{"type": "text", "text": "请看看我现在的屏幕，判断我大概在做什么，并给一个真正有用但不打扰的建议。"},
					{"type": "image_url", "image_url": {"url": image_url, "detail": "low"}}
				]
			}
		],
		"stream": false,
		"max_tokens": 320
	}
	var headers := PackedStringArray([
		"Content-Type: application/json; charset=utf-8",
		"Authorization: Bearer " + String(api["key"])
	])
	var error := _request.request(String(api["endpoint"]), headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_request_pending = false
		analysis_failed.emit("我没能把画面看清楚，网络好像晃了一下。")


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


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_request_pending = false
	if result != HTTPRequest.RESULT_SUCCESS:
		analysis_failed.emit("网络刚才断了一下，我没看清屏幕。")
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if response_code < 200 or response_code >= 300:
		analysis_failed.emit(_friendly_api_error(response_code, parsed))
		return
	if not parsed is Dictionary:
		analysis_failed.emit("我看到了画面，可是一下没组织好语言。")
		return
	var choices = parsed.get("choices", [])
	if not choices is Array or choices.is_empty() or not choices[0] is Dictionary:
		analysis_failed.emit("这个模型没有告诉我它看到了什么。")
		return
	var message = choices[0].get("message", {})
	if not message is Dictionary:
		analysis_failed.emit("这个模型暂时不会看图片，换个视觉模型试试吧。")
		return
	var content := String(message.get("content", "")).strip_edges()
	var awareness := _parse_json_object(content)
	if awareness.is_empty():
		analysis_failed.emit("我看懂了一点，但回答格式有点乱，换个视觉模型会更稳哦。")
		return
	var scene := _clean_text(String(awareness.get("scene", "")), 80)
	var suggestion := _clean_text(String(awareness.get("suggestion", "")), 100)
	var speech := _clean_text(String(awareness.get("text", "")), 46)
	if scene.is_empty() and suggestion.is_empty() and speech.is_empty():
		analysis_failed.emit("这张画面里暂时没有识别出可用信息。")
		return
	_last_result = {
		"scene": scene,
		"suggestion": suggestion,
		"speak": bool(awareness.get("speak", true)),
		"text": speech,
		"emoji": String(awareness.get("emoji", "👀")).strip_edges().left(8)
	}
	_last_analysis_at = Time.get_unix_time_from_system()
	analysis_ready.emit(get_last_result())


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


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	_enabled = bool(config.get_value("screen_awareness", "enabled", false))
	_auto_enabled = bool(config.get_value("screen_awareness", "auto_enabled", false)) and _enabled
	_model_override = String(config.get_value("screen_awareness", "model", "")).strip_edges()


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("screen_awareness", "enabled", _enabled)
	config.set_value("screen_awareness", "auto_enabled", _auto_enabled)
	config.set_value("screen_awareness", "model", _model_override)
	config.save(SETTINGS_PATH)
