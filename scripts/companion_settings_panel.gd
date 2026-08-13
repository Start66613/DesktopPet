extends Window
class_name PetCompanionSettingsPanel

signal dragon_easter_egg_requested

const UI_DIR := "res://assets/companion/runtime/ui"
const PANEL_SIZE := Vector2i(740, 520)
const DRAGON_SECRET_CLICK_COUNT := 5
const DRAGON_SECRET_CLICK_WINDOW_MS := 3200

var _font: Font
var _companion: PetProactiveCompanion
var _monitor: PetForegroundAppMonitor
var _screen_service: PetScreenAwarenessService
var _root: Control
var _pages: Dictionary = {}
var _tabs: Dictionary = {}
var _current_page := "companion"
var _panel_tween: Tween
var _button_tweens: Dictionary = {}
var _refresh_secret_clicks := 0
var _refresh_secret_last_click_ms := 0

var _enabled_toggle: Button
var _monitor_toggle: Button
var _quiet_hours_toggle: Button
var _frequency_slider: HSlider
var _frequency_label: Label
var _app_status: Label
var _memory_status: Label

var _screen_enabled_toggle: Button
var _screen_auto_toggle: Button
var _screen_pause_toggle: Button
var _screen_mode_option: OptionButton
var _screen_status: Label
var _screen_detail: Label

var _blacklist_input: LineEdit
var _limit_slider: HSlider
var _limit_label: Label
var _vision_api_toggle: Button
var _vision_endpoint_input: LineEdit
var _vision_model_input: LineEdit
var _vision_key_input: LineEdit
var _remember_vision_key: CheckBox
var _vision_status: Label


func _init() -> void:
	visible = false
	title = "陪伴设置"
	size = PANEL_SIZE
	min_size = PANEL_SIZE
	borderless = true
	transparent_bg = true
	unresizable = true
	always_on_top = false
	force_native = true


func configure(font: Font, companion: PetProactiveCompanion, monitor: PetForegroundAppMonitor, screen_service: PetScreenAwarenessService) -> void:
	_font = font
	_companion = companion
	_monitor = monitor
	_screen_service = screen_service


func _ready() -> void:
	close_requested.connect(hide_panel)
	_build_ui()
	if _companion:
		_companion.settings_changed.connect(_refresh_controls)
	if _monitor:
		_monitor.foreground_app_changed.connect(_on_foreground_app_changed)
	if _screen_service:
		_screen_service.settings_changed.connect(_refresh_controls)
		_screen_service.status_changed.connect(_refresh_controls)
		_screen_service.analysis_started.connect(_on_screen_analysis_started)
		_screen_service.analysis_ready.connect(_on_screen_analysis_ready)
		_screen_service.analysis_failed.connect(_on_screen_analysis_failed)
	_refresh_controls()


func open_at(screen_position: Vector2i, page := "companion") -> void:
	position = screen_position
	mode = Window.MODE_WINDOWED
	_show_page(page)
	_refresh_controls()
	show()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true, get_window_id())
	get_viewport().transparent_bg = true
	_root.visible = true
	grab_focus()
	_play_open_animation()


func hide_panel() -> void:
	_save_privacy_settings()
	_refresh_secret_clicks = 0
	_refresh_secret_last_click_ms = 0
	hide()


func show_page(page: String) -> void:
	_show_page(page)


func get_current_page() -> String:
	return _current_page


func _build_ui() -> void:
	_root = Control.new()
	_root.size = Vector2(PANEL_SIZE)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.pivot_offset = Vector2(PANEL_SIZE) * 0.5
	add_child(_root)

	var background := TextureRect.new()
	background.size = Vector2(PANEL_SIZE)
	background.texture = load(UI_DIR + "/1_spritesheet.png") as Texture2D
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(background)

	var drag_handle := Control.new()
	drag_handle.position = Vector2(45, 14)
	drag_handle.size = Vector2(555, 62)
	drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	drag_handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	drag_handle.gui_input.connect(_on_drag_handle_gui_input)
	drag_handle.z_index = 40
	_root.add_child(drag_handle)

	var title_label := _make_label("陪伴设置", Vector2(245, 64), Vector2(250, 34), 22, Color("714b57"), HORIZONTAL_ALIGNMENT_CENTER)
	title_label.z_index = 35
	_root.add_child(title_label)

	var minimize_button := _make_hit_button(Vector2(626, 24), Vector2(43, 47), "收起")
	minimize_button.pressed.connect(hide_panel)
	minimize_button.z_index = 45
	_root.add_child(minimize_button)
	var close_button := _make_hit_button(Vector2(675, 24), Vector2(43, 47), "关闭")
	close_button.pressed.connect(hide_panel)
	close_button.z_index = 45
	_root.add_child(close_button)

	_build_companion_page()
	_build_awareness_page()
	_build_privacy_page()

	var tab_specs := [
		{"id": "companion", "text": "陪伴", "x": 145.0},
		{"id": "awareness", "text": "画面感知", "x": 300.0},
		{"id": "privacy", "text": "隐私与接口", "x": 455.0}
	]
	for spec in tab_specs:
		var tab := _make_tab_button(String(spec["text"]), Vector2(float(spec["x"]), 110))
		tab.name = "Tab_" + String(spec["id"])
		tab.pressed.connect(_show_page.bind(String(spec["id"])))
		tab.z_index = 50
		_tabs[String(spec["id"])] = tab
		_root.add_child(tab)
	_show_page("companion")


func _new_page(name_value: String) -> Control:
	var page := Control.new()
	page.name = name_value
	page.position = Vector2.ZERO
	page.size = Vector2(PANEL_SIZE)
	page.mouse_filter = Control.MOUSE_FILTER_PASS
	page.z_index = 10
	_pages[name_value] = page
	_root.add_child(page)
	return page


func _build_companion_page() -> void:
	var page := _new_page("companion")
	page.add_child(_make_icon(23, Vector2(68, 163), Vector2(38, 42)))
	page.add_child(_make_label("主动陪伴", Vector2(112, 163), Vector2(100, 38), 16, Color("654650")))
	_enabled_toggle = _make_toggle(Vector2(218, 165))
	_enabled_toggle.toggled.connect(_on_enabled_toggled)
	page.add_child(_enabled_toggle)

	page.add_child(_make_icon(29, Vector2(402, 164), Vector2(38, 38)))
	page.add_child(_make_label("夜间安静", Vector2(447, 163), Vector2(100, 38), 16, Color("654650")))
	_quiet_hours_toggle = _make_toggle(Vector2(552, 165))
	_quiet_hours_toggle.tooltip_text = "23:00 至 08:00 暂停主动表达"
	_quiet_hours_toggle.toggled.connect(_on_quiet_hours_toggled)
	page.add_child(_quiet_hours_toggle)

	page.add_child(_make_label("表达频率", Vector2(70, 218), Vector2(100, 32), 15, Color("704d57")))
	_frequency_label = _make_label("", Vector2(490, 218), Vector2(180, 32), 14, Color("a25e6c"), HORIZONTAL_ALIGNMENT_RIGHT)
	page.add_child(_frequency_label)
	_frequency_slider = HSlider.new()
	_frequency_slider.position = Vector2(70, 250)
	_frequency_slider.size = Vector2(600, 30)
	_frequency_slider.min_value = 5.0 / 60.0
	_frequency_slider.max_value = 10.0
	_frequency_slider.step = 1.0 / 60.0
	_frequency_slider.tooltip_text = "调节主动表达的平均间隔"
	_style_slider(_frequency_slider)
	_frequency_slider.value_changed.connect(_on_frequency_changed)
	page.add_child(_frequency_slider)

	var presets := [
		{"label": "5秒测试", "value": 5.0 / 60.0},
		{"label": "活泼", "value": 0.25},
		{"label": "日常", "value": 3.5},
		{"label": "安静", "value": 7.0}
	]
	for index in presets.size():
		var preset: Dictionary = presets[index]
		var button := _make_small_button(String(preset["label"]), Vector2(70 + index * 150, 291), Vector2(130, 36))
		button.pressed.connect(_on_preset_pressed.bind(float(preset["value"])))
		page.add_child(button)

	page.add_child(_make_icon(12, Vector2(68, 346), Vector2(38, 38)))
	page.add_child(_make_label("前台应用感知", Vector2(112, 346), Vector2(132, 36), 15, Color("654650")))
	_monitor_toggle = _make_toggle(Vector2(247, 347))
	_monitor_toggle.toggled.connect(_on_monitor_toggled)
	page.add_child(_monitor_toggle)
	_app_status = _make_label("", Vector2(370, 346), Vector2(300, 36), 13, Color("a25e6c"), HORIZONTAL_ALIGNMENT_RIGHT)
	_app_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	page.add_child(_app_status)

	page.add_child(_make_icon(9, Vector2(68, 397), Vector2(38, 38)))
	_memory_status = _make_label("", Vector2(112, 397), Vector2(300, 36), 13, Color("8d6871"))
	page.add_child(_memory_status)
	var clear_button := _make_small_button("清空记忆", Vector2(430, 397), Vector2(105, 36))
	clear_button.pressed.connect(_on_clear_memory_pressed)
	page.add_child(clear_button)
	var refresh_button := _make_small_button("重新识别", Vector2(550, 397), Vector2(120, 36))
	refresh_button.tooltip_text = "重新读取当前应用"
	refresh_button.pressed.connect(_on_refresh_app_pressed)
	page.add_child(refresh_button)

	var think_button := _make_action_button("现在来陪我", Vector2(175, 451), Vector2(170, 51))
	think_button.pressed.connect(_on_think_now_pressed)
	page.add_child(think_button)
	var done_button := _make_action_button("完成", Vector2(395, 451), Vector2(170, 51))
	done_button.pressed.connect(hide_panel)
	page.add_child(done_button)


func _build_awareness_page() -> void:
	var page := _new_page("awareness")
	page.add_child(_make_icon(12, Vector2(65, 163), Vector2(35, 35)))
	page.add_child(_make_label("画面授权", Vector2(105, 162), Vector2(85, 36), 15, Color("654650")))
	_screen_enabled_toggle = _make_toggle(Vector2(192, 164))
	_screen_enabled_toggle.toggled.connect(_on_screen_enabled_toggled)
	page.add_child(_screen_enabled_toggle)

	page.add_child(_make_icon(29, Vector2(325, 163), Vector2(35, 35)))
	page.add_child(_make_label("智能观察", Vector2(365, 162), Vector2(85, 36), 15, Color("654650")))
	_screen_auto_toggle = _make_toggle(Vector2(452, 164))
	_screen_auto_toggle.toggled.connect(_on_screen_auto_toggled)
	page.add_child(_screen_auto_toggle)

	page.add_child(_make_label("临时暂停", Vector2(65, 218), Vector2(85, 36), 15, Color("654650")))
	_screen_pause_toggle = _make_toggle(Vector2(152, 220), "已暂停", "未暂停")
	_screen_pause_toggle.toggled.connect(_on_screen_pause_toggled)
	page.add_child(_screen_pause_toggle)
	page.add_child(_make_label("陪伴模式", Vector2(325, 218), Vector2(85, 36), 15, Color("704d57")))
	_screen_mode_option = OptionButton.new()
	_screen_mode_option.position = Vector2(414, 217)
	_screen_mode_option.size = Vector2(205, 38)
	_screen_mode_option.add_item("自动判断")
	_screen_mode_option.add_item("游戏助手")
	_screen_mode_option.add_item("工作助手")
	_screen_mode_option.add_item("日常陪伴")
	_screen_mode_option.item_selected.connect(_on_screen_mode_selected)
	_style_input_control(_screen_mode_option)
	page.add_child(_screen_mode_option)

	var privacy_note := _make_label("平时只在本机比较低清画面变化；明显变化稳定后才上传 3 帧，截图不会保存到磁盘。", Vector2(72, 274), Vector2(596, 46), 12, Color("8d6871"), HORIZONTAL_ALIGNMENT_CENTER)
	privacy_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(privacy_note)
	_screen_status = _make_label("", Vector2(80, 330), Vector2(580, 32), 15, Color("a25e6c"), HORIZONTAL_ALIGNMENT_CENTER)
	_screen_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	page.add_child(_screen_status)
	_screen_detail = _make_label("", Vector2(90, 365), Vector2(560, 48), 12, Color("8d6871"), HORIZONTAL_ALIGNMENT_CENTER)
	_screen_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_screen_detail)

	var look_button := _make_action_button("立即看看", Vector2(175, 451), Vector2(170, 51))
	look_button.tooltip_text = "隐藏设置后取三个低清关键帧进行一次分析"
	look_button.pressed.connect(_on_look_now_pressed)
	page.add_child(look_button)
	var privacy_button := _make_action_button("配置视觉接口", Vector2(395, 451), Vector2(170, 51))
	privacy_button.pressed.connect(_show_page.bind("privacy"))
	page.add_child(privacy_button)


func _build_privacy_page() -> void:
	var page := _new_page("privacy")
	page.add_child(_make_label("敏感应用", Vector2(62, 159), Vector2(90, 34), 14, Color("654650")))
	_blacklist_input = LineEdit.new()
	_blacklist_input.position = Vector2(154, 158)
	_blacklist_input.size = Vector2(520, 36)
	_blacklist_input.placeholder_text = "用逗号分隔进程名或应用名"
	_blacklist_input.text_submitted.connect(func(_value: String) -> void: _save_privacy_settings())
	_style_input_control(_blacklist_input)
	page.add_child(_blacklist_input)

	page.add_child(_make_label("每日视觉额度", Vector2(62, 204), Vector2(105, 34), 14, Color("704d57")))
	_limit_slider = HSlider.new()
	_limit_slider.position = Vector2(171, 204)
	_limit_slider.size = Vector2(330, 30)
	_limit_slider.min_value = 1
	_limit_slider.max_value = 60
	_limit_slider.step = 1
	_style_slider(_limit_slider)
	_limit_slider.value_changed.connect(_on_limit_changed)
	page.add_child(_limit_slider)
	_limit_label = _make_label("", Vector2(515, 204), Vector2(159, 34), 13, Color("a25e6c"), HORIZONTAL_ALIGNMENT_RIGHT)
	page.add_child(_limit_label)

	page.add_child(_make_label("独立视觉接口", Vector2(62, 249), Vector2(112, 34), 14, Color("654650")))
	_vision_api_toggle = _make_toggle(Vector2(177, 250))
	_vision_api_toggle.tooltip_text = "开启后，聊天继续使用 DeepSeek，屏幕图片改用此处的视觉模型"
	_vision_api_toggle.toggled.connect(_on_vision_api_toggled)
	page.add_child(_vision_api_toggle)
	_remember_vision_key = CheckBox.new()
	_remember_vision_key.position = Vector2(492, 249)
	_remember_vision_key.size = Vector2(182, 36)
	_remember_vision_key.text = "在本机保存 Key"
	_remember_vision_key.focus_mode = Control.FOCUS_NONE
	_remember_vision_key.add_theme_font_size_override("font_size", 13)
	_apply_font(_remember_vision_key)
	page.add_child(_remember_vision_key)

	page.add_child(_make_label("接口地址", Vector2(62, 294), Vector2(90, 34), 14, Color("704d57")))
	_vision_endpoint_input = LineEdit.new()
	_vision_endpoint_input.position = Vector2(154, 293)
	_vision_endpoint_input.size = Vector2(520, 36)
	_vision_endpoint_input.placeholder_text = "https://.../chat/completions"
	_style_input_control(_vision_endpoint_input)
	page.add_child(_vision_endpoint_input)

	page.add_child(_make_label("视觉模型", Vector2(62, 338), Vector2(90, 34), 14, Color("704d57")))
	_vision_model_input = LineEdit.new()
	_vision_model_input.position = Vector2(154, 337)
	_vision_model_input.size = Vector2(520, 36)
	_vision_model_input.placeholder_text = "填写支持图片输入的模型名称"
	_style_input_control(_vision_model_input)
	page.add_child(_vision_model_input)

	page.add_child(_make_label("API Key", Vector2(62, 382), Vector2(90, 34), 14, Color("704d57")))
	_vision_key_input = LineEdit.new()
	_vision_key_input.position = Vector2(154, 381)
	_vision_key_input.size = Vector2(520, 36)
	_vision_key_input.placeholder_text = "视觉服务的 API Key"
	_vision_key_input.secret = true
	_style_input_control(_vision_key_input)
	page.add_child(_vision_key_input)

	_vision_status = _make_label("", Vector2(72, 419), Vector2(596, 28), 12, Color("a25e6c"), HORIZONTAL_ALIGNMENT_CENTER)
	_vision_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	page.add_child(_vision_status)
	var clear_screen_memory := _make_small_button("清空画面记忆", Vector2(115, 458), Vector2(150, 39))
	clear_screen_memory.pressed.connect(_on_clear_screen_memory_pressed)
	page.add_child(clear_screen_memory)
	var save_button := _make_action_button("保存接口", Vector2(295, 451), Vector2(150, 51))
	save_button.pressed.connect(_on_save_vision_pressed)
	page.add_child(save_button)
	var done_button := _make_small_button("完成", Vector2(475, 458), Vector2(150, 39))
	done_button.pressed.connect(hide_panel)
	page.add_child(done_button)


func _show_page(page: String) -> void:
	var cleaned := page if _pages.has(page) else "companion"
	_current_page = cleaned
	for page_name in _pages:
		var page_control: Control = _pages[page_name]
		page_control.visible = page_name == cleaned
	for tab_name in _tabs:
		_style_tab(_tabs[tab_name], tab_name == cleaned)
	_refresh_controls()


func _refresh_controls() -> void:
	_refresh_companion_controls()
	_refresh_screen_controls()


func _refresh_companion_controls() -> void:
	if not _companion or not is_instance_valid(_enabled_toggle):
		return
	_enabled_toggle.set_pressed_no_signal(_companion.is_enabled())
	_monitor_toggle.set_pressed_no_signal(_companion.is_foreground_monitoring_enabled())
	_quiet_hours_toggle.set_pressed_no_signal(_companion.is_quiet_hours_enabled())
	_style_toggle(_enabled_toggle, _enabled_toggle.button_pressed)
	_style_toggle(_monitor_toggle, _monitor_toggle.button_pressed)
	_style_toggle(_quiet_hours_toggle, _quiet_hours_toggle.button_pressed)
	_frequency_slider.set_value_no_signal(_companion.get_frequency_minutes())
	_frequency_label.text = "平均约 " + _format_interval(_companion.get_frequency_minutes())
	var last_spoke_at := _companion.get_last_spoke_at()
	if last_spoke_at > 0.0:
		var last_time := Time.get_datetime_dict_from_unix_time(int(last_spoke_at))
		_memory_status.text = "陪伴记忆 %d 条 · 最近 %02d:%02d" % [_companion.get_memory_count(), int(last_time.get("hour", 0)), int(last_time.get("minute", 0))]
	else:
		_memory_status.text = "已记住 %d 条最近片段" % _companion.get_memory_count()
	_update_app_status(_monitor.get_current_info() if _monitor else {})


func _refresh_screen_controls() -> void:
	if not _screen_service or not is_instance_valid(_screen_enabled_toggle):
		return
	_screen_enabled_toggle.set_pressed_no_signal(_screen_service.is_enabled())
	_screen_auto_toggle.set_pressed_no_signal(_screen_service.is_auto_enabled())
	_screen_pause_toggle.set_pressed_no_signal(_screen_service.is_paused())
	_style_toggle(_screen_enabled_toggle, _screen_enabled_toggle.button_pressed)
	_style_toggle(_screen_auto_toggle, _screen_auto_toggle.button_pressed)
	_style_toggle(_screen_pause_toggle, _screen_pause_toggle.button_pressed, "已暂停", "未暂停")
	_screen_auto_toggle.disabled = not _screen_service.is_enabled() or _screen_service.is_paused()
	_screen_pause_toggle.disabled = not _screen_service.is_enabled()
	var modes := ["auto", "game", "work", "general"]
	_screen_mode_option.select(maxi(0, modes.find(_screen_service.get_mode())))
	_screen_status.text = _screen_service.get_status_summary()
	var result := _screen_service.get_last_result()
	if result.is_empty():
		_screen_detail.text = "尚未上传画面 · 短期记忆 %d 条" % _screen_service.get_short_term_memory_count()
	else:
		_screen_detail.text = "最近：%s · %s · 短期记忆 %d 条" % [String(result.get("activity", "已完成分析")), _reason_text(String(result.get("reason", "manual"))), _screen_service.get_short_term_memory_count()]
	if not _blacklist_input.has_focus():
		_blacklist_input.text = _screen_service.get_blacklist_text()
	_limit_slider.set_value_no_signal(_screen_service.get_daily_limit())
	_limit_label.text = "今日 %d / %d 次" % [_screen_service.get_daily_usage(), _screen_service.get_daily_limit()]
	_vision_api_toggle.set_pressed_no_signal(_screen_service.uses_separate_vision_api())
	_style_toggle(_vision_api_toggle, _vision_api_toggle.button_pressed)
	if not _vision_endpoint_input.has_focus():
		_vision_endpoint_input.text = _screen_service.get_vision_endpoint()
	if not _vision_model_input.has_focus():
		_vision_model_input.text = _screen_service.get_vision_model()
	if not _vision_key_input.has_focus():
		_vision_key_input.text = _screen_service.get_vision_api_key()
	_remember_vision_key.set_pressed_no_signal(_screen_service.remembers_vision_key())
	_vision_status.text = _screen_service.get_vision_api_summary()
	_set_vision_fields_editable(_screen_service.uses_separate_vision_api())


func _on_enabled_toggled(value: bool) -> void:
	_style_toggle(_enabled_toggle, value)
	_companion.set_enabled(value)


func _on_monitor_toggled(value: bool) -> void:
	_style_toggle(_monitor_toggle, value)
	_companion.set_foreground_monitoring_enabled(value)
	if _monitor:
		_monitor.set_enabled(value)
	_update_app_status(_monitor.get_current_info() if _monitor else {})


func _on_quiet_hours_toggled(value: bool) -> void:
	_style_toggle(_quiet_hours_toggle, value)
	_companion.set_quiet_hours_enabled(value)


func _on_frequency_changed(value: float) -> void:
	_frequency_label.text = "平均约 " + _format_interval(value)
	_companion.set_frequency_minutes(value)


func _on_preset_pressed(value: float) -> void:
	_frequency_slider.value = value


func _on_clear_memory_pressed() -> void:
	_companion.clear_memory()
	_refresh_controls()


func _on_refresh_app_pressed() -> void:
	var now_ms := Time.get_ticks_msec()
	if now_ms - _refresh_secret_last_click_ms > DRAGON_SECRET_CLICK_WINDOW_MS:
		_refresh_secret_clicks = 0
	_refresh_secret_last_click_ms = now_ms
	_refresh_secret_clicks += 1
	if _refresh_secret_clicks >= DRAGON_SECRET_CLICK_COUNT:
		_refresh_secret_clicks = 0
		_refresh_secret_last_click_ms = 0
		dragon_easter_egg_requested.emit()
	if _monitor and _monitor.is_enabled():
		_app_status.text = "正在重新识别……"
		_monitor.refresh_now()


func _on_think_now_pressed() -> void:
	_companion.request_thought_now()
	hide_panel()


func _on_foreground_app_changed(info: Dictionary) -> void:
	_update_app_status(info)


func _update_app_status(info: Dictionary) -> void:
	if not _monitor_toggle.button_pressed:
		_app_status.text = "当前未开启"
	elif info.is_empty():
		_app_status.text = "正在识别当前软件……"
	else:
		_app_status.text = "当前：%s · 可见应用 %d 个" % [String(info.get("label", "其他应用")), int(info.get("visible_count", 1))]


func _on_screen_enabled_toggled(value: bool) -> void:
	_style_toggle(_screen_enabled_toggle, value)
	_screen_service.set_enabled(value)


func _on_screen_auto_toggled(value: bool) -> void:
	_style_toggle(_screen_auto_toggle, value)
	_screen_service.set_auto_enabled(value)


func _on_screen_pause_toggled(value: bool) -> void:
	_style_toggle(_screen_pause_toggle, value, "已暂停", "未暂停")
	_screen_service.set_paused(value)


func _on_screen_mode_selected(index: int) -> void:
	_screen_service.set_mode(["auto", "game", "work", "general"][clampi(index, 0, 3)])


func _on_limit_changed(value: float) -> void:
	_screen_service.set_daily_limit(roundi(value))
	_limit_label.text = "今日 %d / %d 次" % [_screen_service.get_daily_usage(), roundi(value)]


func _on_vision_api_toggled(value: bool) -> void:
	_style_toggle(_vision_api_toggle, value)
	_set_vision_fields_editable(value)


func _set_vision_fields_editable(value: bool) -> void:
	_vision_endpoint_input.editable = value
	_vision_model_input.editable = value
	_vision_key_input.editable = value
	_remember_vision_key.disabled = not value


func _save_privacy_settings() -> void:
	if not _screen_service or not is_instance_valid(_blacklist_input):
		return
	_screen_service.set_blacklist_text(_blacklist_input.text)
	_screen_service.set_vision_api_settings(
		_vision_api_toggle.button_pressed,
		_vision_endpoint_input.text,
		_vision_model_input.text,
		_vision_key_input.text,
		_remember_vision_key.button_pressed
	)


func _on_save_vision_pressed() -> void:
	_save_privacy_settings()
	_vision_status.text = _screen_service.get_vision_api_summary()


func _on_clear_screen_memory_pressed() -> void:
	_screen_service.clear_short_term_memory()
	_refresh_controls()


func _on_look_now_pressed() -> void:
	_save_privacy_settings()
	if not _screen_service.is_enabled():
		_screen_status.text = "先开启画面授权哦"
		return
	hide()
	await get_tree().create_timer(0.28).timeout
	_screen_service.request_analysis("manual", true)


func _on_screen_analysis_started() -> void:
	_screen_status.text = "正在取关键帧并理解当前任务……"


func _on_screen_analysis_ready(_result: Dictionary) -> void:
	_refresh_controls()


func _on_screen_analysis_failed(message: String) -> void:
	_screen_status.text = message


func _format_interval(minutes: float) -> String:
	if minutes < 1.0:
		return "%d 秒" % roundi(minutes * 60.0)
	if is_equal_approx(minutes, roundf(minutes)):
		return "%d 分钟" % roundi(minutes)
	return "%.1f 分钟" % minutes


func _reason_text(reason: String) -> String:
	match reason:
		"app_switch": return "切换应用"
		"major_change": return "画面变化"
		"scheduled": return "定时复查"
		_: return "手动观察"


func _on_drag_handle_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		DisplayServer.window_start_drag(get_window_id())


func _play_open_animation() -> void:
	if _panel_tween and _panel_tween.is_valid():
		_panel_tween.kill()
	_root.scale = Vector2.ONE * 0.965
	_root.position = Vector2(PANEL_SIZE) * 0.0175
	_panel_tween = create_tween().set_parallel(true)
	_panel_tween.tween_property(_root, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_panel_tween.tween_property(_root, "position", Vector2.ZERO, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _make_label(text_value: String, node_position: Vector2, node_size: Vector2, font_size: int, color: Color, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.position = node_position
	label.size = node_size
	label.text = text_value
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	_apply_font(label)
	return label


func _make_icon(number: int, node_position: Vector2, node_size: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	icon.position = node_position
	icon.size = node_size
	icon.texture = load(UI_DIR + "/%d_spritesheet.png" % number) as Texture2D
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _make_hit_button(node_position: Vector2, node_size: Vector2, tooltip: String) -> Button:
	var button := Button.new()
	button.position = node_position
	button.size = node_size
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = tooltip
	return button


func _make_toggle(node_position: Vector2, on_text := "已开启", off_text := "已关闭") -> Button:
	var button := Button.new()
	button.position = node_position
	button.size = Vector2(98, 34)
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.set_meta("on_text", on_text)
	button.set_meta("off_text", off_text)
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", Color("684650"))
	button.add_theme_color_override("font_hover_color", Color("684650"))
	button.add_theme_color_override("font_pressed_color", Color("684650"))
	_apply_font(button)
	_bind_button_motion(button, 1.035)
	return button


func _style_toggle(button: Button, enabled: bool, on_text := "", off_text := "") -> void:
	var enabled_text := on_text if not on_text.is_empty() else String(button.get_meta("on_text", "已开启"))
	var disabled_text := off_text if not off_text.is_empty() else String(button.get_meta("off_text", "已关闭"))
	button.text = enabled_text if enabled else disabled_text
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("f5b7c3") if enabled else Color("e8e4dc")
	normal.border_color = Color("d98799") if enabled else Color("b6ab9b")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(9)
	var hover := normal.duplicate()
	hover.bg_color = Color("f8c7d0") if enabled else Color("f0ece5")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", normal)


func _make_tab_button(text_value: String, node_position: Vector2) -> Button:
	var button := Button.new()
	button.position = node_position
	button.size = Vector2(140, 34)
	button.text = text_value
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", Color("714b57"))
	button.add_theme_color_override("font_hover_color", Color("714b57"))
	button.add_theme_color_override("font_pressed_color", Color("714b57"))
	_apply_font(button)
	_bind_button_motion(button, 1.025)
	return button


func _style_tab(button: Button, selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f7c3ce") if selected else Color("fff7f3")
	style.border_color = Color("d98b9b") if selected else Color("dfbac1")
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(8)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("focus", style)


func _style_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color("f4dfd7")
	track.border_color = Color("d999a5")
	track.set_border_width_all(1)
	track.set_corner_radius_all(6)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	var fill := track.duplicate()
	fill.bg_color = Color("edacb9")
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)


func _style_input_control(control: Control) -> void:
	control.add_theme_font_size_override("font_size", 13)
	control.add_theme_color_override("font_color", Color("654650"))
	control.add_theme_color_override("font_placeholder_color", Color("b89aa0"))
	_apply_font(control)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fffaf7")
	style.border_color = Color("dda1ac")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 9
	style.content_margin_right = 9
	control.add_theme_stylebox_override("normal", style)
	control.add_theme_stylebox_override("focus", style)


func _make_small_button(text_value: String, node_position: Vector2, node_size: Vector2) -> Button:
	var button := Button.new()
	button.position = node_position
	button.size = node_size
	button.text = text_value
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", Color("714651"))
	button.add_theme_color_override("font_hover_color", Color("714651"))
	button.add_theme_color_override("font_pressed_color", Color("714651"))
	_apply_font(button)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("fff7f3")
	normal.border_color = Color("dda1ac")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	var hover := normal.duplicate()
	hover.bg_color = Color("f9dce1")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", normal)
	_bind_button_motion(button, 1.035)
	return button


func _make_action_button(text_value: String, node_position: Vector2, node_size: Vector2) -> Button:
	var button := Button.new()
	button.position = node_position
	button.size = node_size
	button.text = text_value
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color("714651"))
	button.add_theme_color_override("font_hover_color", Color("714651"))
	button.add_theme_color_override("font_pressed_color", Color("714651"))
	_apply_font(button)
	button.add_theme_stylebox_override("normal", _make_button_texture(40))
	button.add_theme_stylebox_override("hover", _make_button_texture(41))
	button.add_theme_stylebox_override("pressed", _make_button_texture(42))
	button.add_theme_stylebox_override("focus", _make_button_texture(40))
	_bind_button_motion(button, 1.035)
	return button


func _make_button_texture(number: int) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load(UI_DIR + "/%d_spritesheet.png" % number) as Texture2D
	return style


func _apply_font(control: Control) -> void:
	if _font:
		control.add_theme_font_override("font", _font)


func _bind_button_motion(button: Control, hover_scale: float) -> void:
	button.pivot_offset = button.size * 0.5
	button.resized.connect(func() -> void: button.pivot_offset = button.size * 0.5)
	button.mouse_entered.connect(_animate_button.bind(button, true, hover_scale))
	button.mouse_exited.connect(_animate_button.bind(button, false, hover_scale))


func _animate_button(button: Control, hovered: bool, hover_scale: float) -> void:
	var button_id := button.get_instance_id()
	var previous: Tween = _button_tweens.get(button_id)
	if previous and previous.is_valid():
		previous.kill()
	var tween := create_tween()
	_button_tweens[button_id] = tween
	tween.tween_property(button, "scale", Vector2.ONE * (hover_scale if hovered else 1.0), 0.12).set_trans(Tween.TRANS_BACK if hovered else Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
