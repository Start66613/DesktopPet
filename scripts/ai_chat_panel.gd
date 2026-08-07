extends Window
class_name PetAIChatPanel

signal assistant_replied(text: String)

const CONFIG_PATH := "user://ai_chat.cfg"
const HISTORY_PATH := "user://ai_chat_history.json"
const CHAT_UI_DIR := "res://assets/chat/runtime/ui"
const BASE_SIZE := Vector2(961, 1378)
const UI_SCALE := 0.53
const PANEL_SIZE := Vector2i(510, 731)
const MAX_HISTORY_MESSAGES := 30
const REQUEST_HISTORY_MESSAGES := 14
const MESSAGE_FONT_SIZE := 25

const PROVIDER_PRESETS := [
	{
		"name": "OpenAI",
		"endpoint": "https://api.openai.com/v1/chat/completions",
		"model": "gpt-4o-mini"
	},
	{
		"name": "DeepSeek",
		"endpoint": "https://api.deepseek.com/chat/completions",
		"model": "deepseek-chat"
	},
	{
		"name": "硅基流动",
		"endpoint": "https://api.siliconflow.cn/v1/chat/completions",
		"model": "Qwen/Qwen2.5-7B-Instruct"
	},
	{
		"name": "自定义",
		"endpoint": "",
		"model": ""
	}
]

var _font: Font
var _care_system: PetCareSystem
var _root: Control
var _scroll: ScrollContainer
var _messages: VBoxContainer
var _input: TextEdit
var _send_button: Button
var _status_label: Label
var _request: HTTPRequest
var _typing_row: Control
var _settings_overlay: Control
var _provider_option: OptionButton
var _endpoint_input: LineEdit
var _model_input: LineEdit
var _key_input: LineEdit
var _remember_key: CheckBox
var _settings_status: Label
var _panel_tween: Tween
var _button_tweens: Dictionary = {}
var _history: Array = []
var _endpoint := ""
var _model := ""
var _api_key := ""
var _provider_index := 0
var _request_pending := false


func _init() -> void:
	visible = false
	title = "和她说说话"
	size = PANEL_SIZE
	min_size = PANEL_SIZE
	borderless = true
	transparent_bg = true
	unresizable = true
	always_on_top = true
	force_native = true


func configure(font: Font, care_system: PetCareSystem) -> void:
	_font = font
	_care_system = care_system


func _ready() -> void:
	close_requested.connect(hide_panel)
	_build_ui()
	_load_settings()
	_load_history()
	if _history.is_empty():
		_add_message("assistant", "终于可以坐下来好好聊聊啦 (´▽｀)", true)
	else:
		_rebuild_history()
	_refresh_status()


func open_at(screen_position: Vector2i) -> void:
	position = screen_position
	_prepare_open_animation()
	show()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true, get_window_id())
	grab_focus()
	call_deferred("_bring_to_front")
	_play_open_animation()
	_input.grab_focus()
	if not _is_configured():
		_show_settings()


func hide_panel() -> void:
	_settings_overlay.visible = false
	hide()


func _bring_to_front() -> void:
	if visible:
		move_to_foreground()
		grab_focus()


func _build_ui() -> void:
	_root = Control.new()
	_root.size = BASE_SIZE
	_root.scale = Vector2.ONE * UI_SCALE
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var background := _make_texture_rect(CHAT_UI_DIR + "/chat_panel.png", Vector2.ZERO, BASE_SIZE)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(background)

	var drag_handle := Control.new()
	drag_handle.position = Vector2(180, 20)
	drag_handle.size = Vector2(470, 105)
	drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	drag_handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	drag_handle.gui_input.connect(_on_drag_handle_gui_input)
	_root.add_child(drag_handle)

	var title_label := Label.new()
	title_label.position = Vector2(295, 38)
	title_label.size = Vector2(370, 58)
	title_label.text = ""
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.add_theme_font_size_override("font_size", 31)
	title_label.add_theme_color_override("font_color", Color("704955"))
	_apply_font(title_label)
	_root.add_child(title_label)

	_status_label = Label.new()
	_status_label.position = Vector2(62, 118)
	_status_label.size = Vector2(540, 32)
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.add_theme_font_size_override("font_size", 19)
	_status_label.add_theme_color_override("font_color", Color("9b6a76"))
	_apply_font(_status_label)
	_root.add_child(_status_label)

	var settings_button := _make_texture_button(CHAT_UI_DIR + "/settings.png", Vector2(664, 43), Vector2(76, 76))
	settings_button.tooltip_text = "API 设置"
	settings_button.pressed.connect(_show_settings)
	_root.add_child(settings_button)
	_bind_button_motion(settings_button, 1.08, 3.0)

	var minimize_button := _make_hit_button(Vector2(720, 24), Vector2(130, 130))
	minimize_button.tooltip_text = "最小化"
	minimize_button.pressed.connect(_minimize_window)
	_root.add_child(minimize_button)

	var close_button := _make_hit_button(Vector2(825, 24), Vector2(130, 130))
	close_button.tooltip_text = "关闭"
	close_button.pressed.connect(hide_panel)
	_root.add_child(close_button)

	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(60, 158)
	_scroll.size = Vector2(840, 962)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_root.add_child(_scroll)

	_messages = VBoxContainer.new()
	_messages.custom_minimum_size = Vector2(815, 0)
	_messages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_messages.add_theme_constant_override("separation", 20)
	_scroll.add_child(_messages)
	_scroll.get_v_scroll_bar().modulate.a = 0.0

	_input = TextEdit.new()
	_input.position = Vector2(112, 1184)
	_input.size = Vector2(622, 94)
	_input.placeholder_text = "想和她说点什么……"
	_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_input.scroll_fit_content_height = false
	_input.add_theme_font_size_override("font_size", 24)
	_input.add_theme_color_override("font_color", Color("5e414a"))
	_input.add_theme_color_override("font_placeholder_color", Color("b9939d"))
	_input.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_input.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_apply_font(_input)
	_input.gui_input.connect(_on_input_gui_input)
	_root.add_child(_input)

	_send_button = _make_hit_button(Vector2(768, 1158), Vector2(148, 154))
	_send_button.tooltip_text = "发送"
	_send_button.pressed.connect(_send_current_message)
	_root.add_child(_send_button)

	_request = HTTPRequest.new()
	_request.timeout = 60.0
	_request.use_threads = true
	_request.request_completed.connect(_on_request_completed)
	add_child(_request)

	_build_settings_overlay()


func _build_settings_overlay() -> void:
	_settings_overlay = Control.new()
	_settings_overlay.position = Vector2.ZERO
	_settings_overlay.size = BASE_SIZE
	_settings_overlay.z_index = 20
	_settings_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_overlay.visible = false
	_root.add_child(_settings_overlay)

	var panel := PanelContainer.new()
	panel.position = Vector2(148, 238)
	panel.size = Vector2(665, 790)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("fff8f3")
	panel_style.border_color = Color("d99aa5")
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(16)
	panel_style.shadow_color = Color(0.24, 0.12, 0.16, 0.24)
	panel_style.shadow_size = 12
	panel.add_theme_stylebox_override("panel", panel_style)
	_settings_overlay.add_child(panel)

	var heading := Label.new()
	heading.position = Vector2(198, 278)
	heading.size = Vector2(565, 52)
	heading.text = "AI 连接设置"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 30)
	heading.add_theme_color_override("font_color", Color("704955"))
	_apply_font(heading)
	_settings_overlay.add_child(heading)

	_provider_option = OptionButton.new()
	_provider_option.position = Vector2(210, 370)
	_provider_option.size = Vector2(540, 60)
	_provider_option.add_theme_font_size_override("font_size", 22)
	_apply_font(_provider_option)
	for preset in PROVIDER_PRESETS:
		_provider_option.add_item(preset["name"])
	_provider_option.item_selected.connect(_on_provider_selected)
	_style_field(_provider_option)
	_add_settings_label("服务商", Vector2(210, 335))
	_settings_overlay.add_child(_provider_option)

	_endpoint_input = LineEdit.new()
	_endpoint_input.position = Vector2(210, 485)
	_endpoint_input.size = Vector2(540, 62)
	_endpoint_input.placeholder_text = "https://.../chat/completions"
	_endpoint_input.add_theme_font_size_override("font_size", 19)
	_apply_font(_endpoint_input)
	_style_field(_endpoint_input)
	_add_settings_label("接口地址", Vector2(210, 449))
	_settings_overlay.add_child(_endpoint_input)

	_model_input = LineEdit.new()
	_model_input.position = Vector2(210, 600)
	_model_input.size = Vector2(540, 62)
	_model_input.placeholder_text = "模型名称"
	_model_input.add_theme_font_size_override("font_size", 21)
	_apply_font(_model_input)
	_style_field(_model_input)
	_add_settings_label("模型", Vector2(210, 564))
	_settings_overlay.add_child(_model_input)

	_key_input = LineEdit.new()
	_key_input.position = Vector2(210, 715)
	_key_input.size = Vector2(540, 62)
	_key_input.placeholder_text = "API Key"
	_key_input.secret = true
	_key_input.add_theme_font_size_override("font_size", 21)
	_apply_font(_key_input)
	_style_field(_key_input)
	_add_settings_label("API Key", Vector2(210, 679))
	_settings_overlay.add_child(_key_input)

	_remember_key = CheckBox.new()
	_remember_key.position = Vector2(210, 793)
	_remember_key.size = Vector2(360, 46)
	_remember_key.text = "在本机保存 API Key"
	_remember_key.button_pressed = true
	_remember_key.add_theme_font_size_override("font_size", 20)
	_remember_key.add_theme_color_override("font_color", Color("704955"))
	_apply_font(_remember_key)
	_settings_overlay.add_child(_remember_key)

	_settings_status = Label.new()
	_settings_status.position = Vector2(210, 842)
	_settings_status.size = Vector2(540, 36)
	_settings_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_status.add_theme_font_size_override("font_size", 18)
	_settings_status.add_theme_color_override("font_color", Color("b35f70"))
	_apply_font(_settings_status)
	_settings_overlay.add_child(_settings_status)

	var cancel_button := _make_text_button("返回", Vector2(235, 900), Vector2(210, 72), false)
	cancel_button.pressed.connect(_hide_settings)
	_settings_overlay.add_child(cancel_button)
	_bind_button_motion(cancel_button, 1.04, -1.5)

	var save_button := _make_text_button("保存", Vector2(516, 900), Vector2(210, 72), true)
	save_button.pressed.connect(_save_settings)
	_settings_overlay.add_child(save_button)
	_bind_button_motion(save_button, 1.04, 1.5)


func _add_settings_label(text: String, label_position: Vector2) -> void:
	var label := Label.new()
	label.position = label_position
	label.size = Vector2(540, 34)
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color("805661"))
	_apply_font(label)
	_settings_overlay.add_child(label)


func _style_field(control: Control) -> void:
	var style := StyleBoxTexture.new()
	style.texture = load(CHAT_UI_DIR + "/settings_field.png") as Texture2D
	style.texture_margin_left = 34.0
	style.texture_margin_top = 34.0
	style.texture_margin_right = 34.0
	style.texture_margin_bottom = 34.0
	style.content_margin_left = 28.0
	style.content_margin_right = 28.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	control.add_theme_stylebox_override("normal", style)
	control.add_theme_stylebox_override("focus", style)
	control.add_theme_stylebox_override("hover", style)
	control.add_theme_color_override("font_color", Color("61434c"))


func _make_text_button(text: String, button_position: Vector2, button_size: Vector2, primary: bool) -> Button:
	var button := Button.new()
	button.position = button_position
	button.size = button_size
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 23)
	button.add_theme_color_override("font_color", Color("684551"))
	_apply_font(button)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f5b3c1") if primary else Color("fff3ef")
	style.border_color = Color("d98b9a")
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	button.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = Color("f7c5cf") if primary else Color("fbe1e2")
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	return button


func _on_drag_handle_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		DisplayServer.window_start_drag(get_window_id())


func _minimize_window() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED, get_window_id())


func _prepare_open_animation() -> void:
	if _panel_tween and _panel_tween.is_valid():
		_panel_tween.kill()
	_root.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_root.scale = Vector2.ONE * (UI_SCALE * 0.97)


func _play_open_animation() -> void:
	_panel_tween = create_tween()
	_panel_tween.set_parallel(true)
	_panel_tween.tween_property(_root, "modulate", Color.WHITE, 0.18)
	_panel_tween.tween_property(_root, "scale", Vector2.ONE * UI_SCALE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _show_settings() -> void:
	_provider_option.select(_provider_index)
	_endpoint_input.text = _endpoint
	_model_input.text = _model
	_key_input.text = _api_key
	_settings_status.text = ""
	_settings_overlay.modulate.a = 0.0
	_settings_overlay.visible = true
	var tween := create_tween()
	tween.tween_property(_settings_overlay, "modulate:a", 1.0, 0.15)


func _hide_settings() -> void:
	_settings_overlay.visible = false


func _on_provider_selected(index: int) -> void:
	_provider_index = index
	var preset: Dictionary = PROVIDER_PRESETS[index]
	if not String(preset["endpoint"]).is_empty():
		_endpoint_input.text = preset["endpoint"]
		_model_input.text = preset["model"]


func _save_settings() -> void:
	var endpoint := _endpoint_input.text.strip_edges()
	var model := _model_input.text.strip_edges()
	var key := _key_input.text.strip_edges()
	if not endpoint.begins_with("https://") and not endpoint.begins_with("http://"):
		_settings_status.text = "接口地址格式不正确"
		return
	if model.is_empty():
		_settings_status.text = "请填写模型名称"
		return
	if key.is_empty():
		_settings_status.text = "请填写 API Key"
		return

	_endpoint = endpoint
	_model = model
	_api_key = key
	_provider_index = _provider_option.selected
	var config := ConfigFile.new()
	config.set_value("api", "provider", _provider_index)
	config.set_value("api", "endpoint", _endpoint)
	config.set_value("api", "model", _model)
	config.set_value("api", "remember_key", _remember_key.button_pressed)
	config.set_value("api", "key", _api_key if _remember_key.button_pressed else "")
	var error := config.save(CONFIG_PATH)
	if error != OK:
		_settings_status.text = "设置保存失败"
		return
	_settings_overlay.visible = false
	_refresh_status()
	_input.grab_focus()


func _load_settings() -> void:
	_provider_index = 0
	_endpoint = PROVIDER_PRESETS[0]["endpoint"]
	_model = PROVIDER_PRESETS[0]["model"]
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	_provider_index = clampi(int(config.get_value("api", "provider", 0)), 0, PROVIDER_PRESETS.size() - 1)
	_endpoint = String(config.get_value("api", "endpoint", _endpoint))
	_model = String(config.get_value("api", "model", _model))
	_api_key = String(config.get_value("api", "key", ""))
	_remember_key.button_pressed = bool(config.get_value("api", "remember_key", true))


func _refresh_status() -> void:
	if _request_pending:
		_status_label.text = "她正在想……"
	elif _is_configured():
		_status_label.text = "已连接 · " + _model
	else:
		_status_label.text = "尚未配置 API"


func _is_configured() -> bool:
	return not _endpoint.is_empty() and not _model.is_empty() and not _api_key.is_empty()


func _on_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and not event.shift_pressed:
			_input.accept_event()
			_send_current_message()


func _send_current_message() -> void:
	if _request_pending:
		return
	var message := _input.text.strip_edges()
	if message.is_empty():
		return
	if not _is_configured():
		_show_settings()
		return

	_input.text = ""
	_add_message("user", message, true)
	_show_typing()
	_set_request_pending(true)

	var request_messages: Array = [{"role": "system", "content": _build_system_prompt()}]
	var start := maxi(_history.size() - REQUEST_HISTORY_MESSAGES, 0)
	for index in range(start, _history.size()):
		var history_message: Dictionary = _history[index]
		request_messages.append({
			"role": history_message.get("role", "user"),
			"content": history_message.get("content", "")
		})

	var payload := {
		"model": _model,
		"messages": request_messages,
		"stream": false
	}
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + _api_key
	])
	var error := _request.request(_endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_finish_with_error("请求没有发出去：" + error_string(error))


func _build_system_prompt() -> String:
	var status_context := ""
	if _care_system:
		var stats := _care_system.get_stats()
		status_context = "\n你现在的状态：饱腹%d，水分%d，心情%d，好感%d，精力%d。" % [
			roundi(float(stats.get("fullness", 0.0))),
			roundi(float(stats.get("hydration", 0.0))),
			roundi(float(stats.get("mood", 0.0))),
			roundi(float(stats.get("affection", 0.0))),
			roundi(float(stats.get("energy", 0.0)))
		]
	return "你是住在用户桌面上的可爱少女桌宠，也是可靠的随身伙伴。用自然、亲近的简体中文回应，保持少女感但不要装幼稚。默认用1到3句，偶尔自然使用一个颜文字或emoji，不要堆叠。不要使用Markdown标题或列表。用户询问知识、工作或游戏问题时应认真给出有用答案；只有在用户明确要求详细说明时才展开。不要声称自己看到了当前屏幕，除非用户在对话中提供了内容。" + status_context


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_finish_with_error("网络请求失败，请检查连接后重试")
		return

	var body_text := body.get_string_from_utf8()
	var parsed = JSON.parse_string(body_text)
	if response_code < 200 or response_code >= 300:
		var api_error := "API 返回错误 %d" % response_code
		if parsed is Dictionary:
			var error_data = parsed.get("error", {})
			if error_data is Dictionary and not String(error_data.get("message", "")).is_empty():
				api_error = String(error_data.get("message", api_error))
		_finish_with_error(api_error)
		return
	if not parsed is Dictionary:
		_finish_with_error("API 返回了无法识别的数据")
		return

	var choices = parsed.get("choices", [])
	if not choices is Array or choices.is_empty() or not choices[0] is Dictionary:
		_finish_with_error("API 返回中没有回复内容")
		return
	var message_data = choices[0].get("message", {})
	if not message_data is Dictionary:
		_finish_with_error("API 回复格式不兼容")
		return
	var content := String(message_data.get("content", "")).strip_edges()
	if content.is_empty():
		_finish_with_error("她想了想，却没有说出话来")
		return

	_hide_typing()
	_set_request_pending(false)
	_add_message("assistant", content, true)
	assistant_replied.emit(content)


func _finish_with_error(message: String) -> void:
	_hide_typing()
	_set_request_pending(false)
	_add_message("assistant", message, false)


func _set_request_pending(value: bool) -> void:
	_request_pending = value
	_send_button.disabled = value
	_input.editable = not value
	_refresh_status()
	if not value:
		_input.grab_focus()


func _show_typing() -> void:
	_hide_typing()
	_typing_row = Control.new()
	_typing_row.custom_minimum_size = Vector2(815, 105)
	var typing := TextureRect.new()
	typing.position = Vector2(0, 0)
	typing.size = Vector2(245, 94)
	typing.texture = load(CHAT_UI_DIR + "/typing_bubble.png") as Texture2D
	typing.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	typing.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	typing.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_typing_row.add_child(typing)
	_messages.add_child(_typing_row)
	_scroll_to_bottom()


func _hide_typing() -> void:
	if _typing_row and is_instance_valid(_typing_row):
		_typing_row.queue_free()
	_typing_row = null


func _add_message(role: String, text: String, store_message: bool) -> void:
	var clean_text := text.strip_edges()
	if clean_text.is_empty():
		return
	if store_message:
		_history.append({"role": role, "content": clean_text})
		while _history.size() > MAX_HISTORY_MESSAGES:
			_history.pop_front()
		_save_history()

	var measured_width := float(clean_text.length()) * float(MESSAGE_FONT_SIZE) * 0.92
	if _font:
		measured_width = _font.get_string_size(clean_text, HORIZONTAL_ALIGNMENT_LEFT, -1, MESSAGE_FONT_SIZE).x
	var bubble_width := clampf(measured_width + 112.0, 285.0, 700.0)
	var content_width := bubble_width - 104.0
	var line_chars := maxi(int(content_width / (float(MESSAGE_FONT_SIZE) * 1.02)), 1)
	var line_count := 0
	for paragraph in clean_text.split("\n"):
		line_count += maxi(ceili(float(String(paragraph).length()) / float(line_chars)), 1)
	var bubble_height := maxf(104.0, 56.0 + float(line_count) * 34.0)

	var row := Control.new()
	row.custom_minimum_size = Vector2(815, bubble_height + 6.0)
	var bubble := NinePatchRect.new()
	bubble.size = Vector2(bubble_width, bubble_height)
	bubble.position.x = 0.0 if role == "assistant" else 815.0 - bubble_width
	bubble.texture = load(CHAT_UI_DIR + ("/assistant_bubble.png" if role == "assistant" else "/user_bubble.png")) as Texture2D
	bubble.set_patch_margin(SIDE_LEFT, 72)
	bubble.set_patch_margin(SIDE_TOP, 62)
	bubble.set_patch_margin(SIDE_RIGHT, 72)
	bubble.set_patch_margin(SIDE_BOTTOM, 72)
	bubble.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bubble)

	var label := Label.new()
	label.position = Vector2(48, 25)
	label.size = Vector2(content_width, bubble_height - 52.0)
	label.text = clean_text
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", MESSAGE_FONT_SIZE)
	label.add_theme_color_override("font_color", Color("5e414a"))
	label.add_theme_constant_override("line_spacing", 5)
	_apply_font(label)
	bubble.add_child(label)

	_messages.add_child(row)
	_scroll_to_bottom()


func _rebuild_history() -> void:
	for message in _history:
		if message is Dictionary:
			_add_message(String(message.get("role", "assistant")), String(message.get("content", "")), false)


func _save_history() -> void:
	var file := FileAccess.open(HISTORY_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_history))


func _load_history() -> void:
	if not FileAccess.file_exists(HISTORY_PATH):
		return
	var file := FileAccess.open(HISTORY_PATH, FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		_history = parsed
		while _history.size() > MAX_HISTORY_MESSAGES:
			_history.pop_front()


func _scroll_to_bottom() -> void:
	_scroll_to_bottom_after_layout.call_deferred()


func _scroll_to_bottom_after_layout() -> void:
	await get_tree().process_frame
	if _scroll:
		_scroll.scroll_vertical = roundi(_scroll.get_v_scroll_bar().max_value)


func _make_texture_rect(path: String, node_position: Vector2, node_size: Vector2) -> TextureRect:
	var texture_rect := TextureRect.new()
	texture_rect.position = node_position
	texture_rect.size = node_size
	texture_rect.texture = load(path) as Texture2D
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	return texture_rect


func _make_texture_button(path: String, node_position: Vector2, node_size: Vector2) -> TextureButton:
	var button := TextureButton.new()
	button.position = node_position
	button.size = node_size
	button.texture_normal = load(path) as Texture2D
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	button.focus_mode = Control.FOCUS_NONE
	return button


func _make_hit_button(node_position: Vector2, node_size: Vector2) -> Button:
	var button := Button.new()
	button.position = node_position
	button.size = node_size
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("hover", empty)
	button.add_theme_stylebox_override("pressed", empty)
	button.add_theme_stylebox_override("focus", empty)
	return button


func _bind_button_motion(button: Control, hover_scale: float, angle_degrees: float) -> void:
	button.pivot_offset = button.size * 0.5
	button.resized.connect(func() -> void: button.pivot_offset = button.size * 0.5)
	button.mouse_entered.connect(_animate_button_motion.bind(button, true, hover_scale, angle_degrees))
	button.mouse_exited.connect(_animate_button_motion.bind(button, false, hover_scale, angle_degrees))


func _animate_button_motion(button: Control, hovered: bool, hover_scale: float, angle_degrees: float) -> void:
	var button_id := button.get_instance_id()
	var previous: Tween = _button_tweens.get(button_id)
	if previous and previous.is_valid():
		previous.kill()
	var tween := create_tween()
	_button_tweens[button_id] = tween
	tween.set_parallel(true)
	tween.tween_property(button, "scale", Vector2.ONE * (hover_scale if hovered else 1.0), 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "rotation", deg_to_rad(angle_degrees if hovered else 0.0), 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _apply_font(control: Control) -> void:
	if _font:
		control.add_theme_font_override("font", _font)
