extends Window
class_name PetScreenAwarenessPanel

const UI_DIR := "res://assets/companion/runtime/ui"
const PANEL_SIZE := Vector2i(680, 477)

var _font: Font
var _service: PetScreenAwarenessService
var _root: Control
var _basic_page: Control
var _privacy_page: Control
var _enabled_toggle: Button
var _auto_toggle: Button
var _pause_toggle: Button
var _mode_option: OptionButton
var _limit_slider: HSlider
var _limit_label: Label
var _model_input: LineEdit
var _blacklist_input: LineEdit
var _status_label: Label
var _detail_label: Label
var _basic_tab: Button
var _privacy_tab: Button
var _panel_tween: Tween
var _button_tweens: Dictionary = {}


func _init() -> void:
	visible = false
	title = "画面感知"
	size = PANEL_SIZE
	min_size = PANEL_SIZE
	borderless = true
	transparent_bg = true
	unresizable = true
	always_on_top = false
	force_native = true


func configure(font: Font, service: PetScreenAwarenessService) -> void:
	_font = font
	_service = service


func _ready() -> void:
	close_requested.connect(hide_panel)
	_build_ui()
	if _service:
		_service.settings_changed.connect(_refresh_controls)
		_service.status_changed.connect(_refresh_controls)
		_service.analysis_started.connect(_on_analysis_started)
		_service.analysis_ready.connect(_on_analysis_ready)
		_service.analysis_failed.connect(_on_analysis_failed)
	_refresh_controls()


func open_at(screen_position: Vector2i) -> void:
	position = screen_position
	mode = Window.MODE_WINDOWED
	_refresh_controls()
	show()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true, get_window_id())
	get_viewport().transparent_bg = true
	_root.visible = true
	grab_focus()
	_play_open_animation()


func hide_panel() -> void:
	_save_text_settings()
	hide()


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
	drag_handle.position = Vector2(42, 14)
	drag_handle.size = Vector2(510, 60)
	drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	drag_handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	drag_handle.gui_input.connect(_on_drag_handle_gui_input)
	_root.add_child(drag_handle)

	var minimize_button := _make_hit_button(Vector2(576, 23), Vector2(42, 46), "收起")
	minimize_button.pressed.connect(hide_panel)
	_root.add_child(minimize_button)
	var close_button := _make_hit_button(Vector2(621, 23), Vector2(42, 46), "关闭")
	close_button.pressed.connect(hide_panel)
	_root.add_child(close_button)

	var title_label := _make_label("画面感知", Vector2(210, 76), Vector2(260, 34), 20, Color("714b57"))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(title_label)

	_basic_tab = _make_tab_button("智能观察", Vector2(195, 113))
	_basic_tab.pressed.connect(_show_page.bind(false))
	_root.add_child(_basic_tab)
	_privacy_tab = _make_tab_button("隐私与额度", Vector2(347, 113))
	_privacy_tab.pressed.connect(_show_page.bind(true))
	_root.add_child(_privacy_tab)

	_basic_page = Control.new()
	_basic_page.position = Vector2(0, 0)
	_basic_page.size = Vector2(PANEL_SIZE)
	_root.add_child(_basic_page)
	_build_basic_page()

	_privacy_page = Control.new()
	_privacy_page.position = Vector2(0, 0)
	_privacy_page.size = Vector2(PANEL_SIZE)
	_root.add_child(_privacy_page)
	_build_privacy_page()

	_status_label = _make_label("", Vector2(74, 337), Vector2(532, 28), 13, Color("a25e6c"))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_root.add_child(_status_label)
	_detail_label = _make_label("", Vector2(86, 364), Vector2(508, 23), 11, Color("8d6871"))
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_root.add_child(_detail_label)

	var look_button := _make_action_button("立即看看", Vector2(126, 393), Vector2(180, 70))
	look_button.tooltip_text = "隐藏窗口后取三个低清关键帧进行一次分析"
	look_button.pressed.connect(_on_look_now_pressed)
	_root.add_child(look_button)
	var done_button := _make_action_button("完成", Vector2(374, 393), Vector2(180, 70))
	done_button.pressed.connect(hide_panel)
	_root.add_child(done_button)

	_show_page(false)


func _build_basic_page() -> void:
	_basic_page.add_child(_make_icon(12, Vector2(58, 157), Vector2(34, 34)))
	_basic_page.add_child(_make_label("画面授权", Vector2(100, 157), Vector2(92, 34), 15, Color("654650")))
	_enabled_toggle = _make_toggle(Vector2(198, 157))
	_enabled_toggle.toggled.connect(_on_enabled_toggled)
	_basic_page.add_child(_enabled_toggle)

	_basic_page.add_child(_make_icon(29, Vector2(355, 157), Vector2(34, 34)))
	_basic_page.add_child(_make_label("智能观察", Vector2(397, 157), Vector2(92, 34), 15, Color("654650")))
	_auto_toggle = _make_toggle(Vector2(495, 157))
	_auto_toggle.tooltip_text = "本地检测明显变化，稳定后才调用 API"
	_auto_toggle.toggled.connect(_on_auto_toggled)
	_basic_page.add_child(_auto_toggle)

	_basic_page.add_child(_make_icon(11, Vector2(58, 209), Vector2(34, 34)))
	_basic_page.add_child(_make_label("临时暂停", Vector2(100, 209), Vector2(92, 34), 15, Color("654650")))
	_pause_toggle = _make_toggle(Vector2(198, 209))
	_pause_toggle.tooltip_text = "暂停后不会截取或上传画面"
	_pause_toggle.toggled.connect(_on_pause_toggled)
	_basic_page.add_child(_pause_toggle)

	_basic_page.add_child(_make_label("陪伴模式", Vector2(355, 209), Vector2(92, 34), 15, Color("704d57")))
	_mode_option = OptionButton.new()
	_mode_option.position = Vector2(449, 207)
	_mode_option.size = Vector2(166, 38)
	_mode_option.add_item("自动判断", 0)
	_mode_option.add_item("游戏助手", 1)
	_mode_option.add_item("工作助手", 2)
	_mode_option.add_item("日常陪伴", 3)
	_mode_option.item_selected.connect(_on_mode_selected)
	_style_input_control(_mode_option)
	_basic_page.add_child(_mode_option)

	_basic_page.add_child(_make_label("视觉模型", Vector2(58, 261), Vector2(82, 36), 15, Color("704d57")))
	_model_input = LineEdit.new()
	_model_input.position = Vector2(142, 259)
	_model_input.size = Vector2(473, 39)
	_model_input.placeholder_text = "留空则沿用聊天模型；也可以填写支持图片输入的模型名称"
	_model_input.tooltip_text = "当前聊天模型不支持图片时，请填写单独的视觉模型"
	_style_input_control(_model_input)
	_model_input.text_submitted.connect(func(_value: String) -> void: _save_text_settings())
	_model_input.focus_exited.connect(_save_text_settings)
	_basic_page.add_child(_model_input)

	var local_privacy := _make_label("平时只在本机比较低清灰度画面；明显变化稳定后才上传 3 帧。截图不会保存到磁盘。", Vector2(64, 301), Vector2(552, 35), 11, Color("8d6871"))
	local_privacy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	local_privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_basic_page.add_child(local_privacy)


func _build_privacy_page() -> void:
	_privacy_page.add_child(_make_label("敏感应用名单", Vector2(58, 157), Vector2(116, 36), 15, Color("654650")))
	_blacklist_input = LineEdit.new()
	_blacklist_input.position = Vector2(176, 155)
	_blacklist_input.size = Vector2(439, 39)
	_blacklist_input.placeholder_text = "用逗号分隔进程名或应用名"
	_blacklist_input.tooltip_text = "命中名单时，本地检测和截图上传都会跳过"
	_style_input_control(_blacklist_input)
	_blacklist_input.text_submitted.connect(func(_value: String) -> void: _save_text_settings())
	_blacklist_input.focus_exited.connect(_save_text_settings)
	_privacy_page.add_child(_blacklist_input)

	_privacy_page.add_child(_make_label("每日视觉额度", Vector2(58, 215), Vector2(116, 34), 15, Color("704d57")))
	_limit_slider = HSlider.new()
	_limit_slider.position = Vector2(176, 211)
	_limit_slider.size = Vector2(290, 42)
	_limit_slider.min_value = 1
	_limit_slider.max_value = 60
	_limit_slider.step = 1
	_limit_slider.tooltip_text = "自动和手动分析共用此上限"
	_style_slider(_limit_slider)
	_limit_slider.value_changed.connect(_on_limit_changed)
	_privacy_page.add_child(_limit_slider)
	_limit_label = _make_label("", Vector2(474, 215), Vector2(141, 34), 13, Color("a25e6c"))
	_limit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_privacy_page.add_child(_limit_label)

	var memory_label := _make_label("短期记忆只保留任务摘要，最多 8 条，30 分钟自动过期；不保存图片或画面正文。", Vector2(58, 265), Vector2(386, 58), 12, Color("8d6871"))
	memory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_privacy_page.add_child(memory_label)
	var clear_button := _make_small_button("清空短期记忆", Vector2(465, 271), Vector2(150, 43))
	clear_button.pressed.connect(_on_clear_memory_pressed)
	_privacy_page.add_child(clear_button)


func _show_page(show_privacy: bool) -> void:
	if _basic_page:
		_basic_page.visible = not show_privacy
	if _privacy_page:
		_privacy_page.visible = show_privacy
	_style_tab(_basic_tab, not show_privacy)
	_style_tab(_privacy_tab, show_privacy)


func _refresh_controls() -> void:
	if not _service or not is_instance_valid(_enabled_toggle):
		return
	_enabled_toggle.set_pressed_no_signal(_service.is_enabled())
	_auto_toggle.set_pressed_no_signal(_service.is_auto_enabled())
	_pause_toggle.set_pressed_no_signal(_service.is_paused())
	_style_toggle(_enabled_toggle, _enabled_toggle.button_pressed)
	_style_toggle(_auto_toggle, _auto_toggle.button_pressed)
	_style_toggle(_pause_toggle, _pause_toggle.button_pressed, "已暂停", "未暂停")
	_auto_toggle.disabled = not _service.is_enabled() or _service.is_paused()
	_pause_toggle.disabled = not _service.is_enabled()
	_model_input.editable = not _service.is_busy()
	_blacklist_input.editable = not _service.is_busy()
	if not _model_input.has_focus():
		_model_input.text = _service.get_model_override()
	if not _blacklist_input.has_focus():
		_blacklist_input.text = _service.get_blacklist_text()
	var modes := ["auto", "game", "work", "general"]
	_mode_option.select(maxi(0, modes.find(_service.get_mode())))
	_limit_slider.set_value_no_signal(_service.get_daily_limit())
	_limit_label.text = "今日 %d / %d 次" % [_service.get_daily_usage(), _service.get_daily_limit()]
	_status_label.text = _service.get_status_summary()
	var result := _service.get_last_result()
	if not result.is_empty():
		_detail_label.text = "最近：%s · %s · 短期记忆 %d 条" % [String(result.get("activity", "已完成分析")), _reason_text(String(result.get("reason", "manual"))), _service.get_short_term_memory_count()]
	else:
		_detail_label.text = "尚未上传画面 · 短期记忆 %d 条" % _service.get_short_term_memory_count()


func _on_enabled_toggled(value: bool) -> void:
	_style_toggle(_enabled_toggle, value)
	_service.set_enabled(value)
	_refresh_controls()


func _on_auto_toggled(value: bool) -> void:
	_style_toggle(_auto_toggle, value)
	_service.set_auto_enabled(value)


func _on_pause_toggled(value: bool) -> void:
	_style_toggle(_pause_toggle, value, "已暂停", "未暂停")
	_service.set_paused(value)


func _on_mode_selected(index: int) -> void:
	_service.set_mode(["auto", "game", "work", "general"][clampi(index, 0, 3)])


func _on_limit_changed(value: float) -> void:
	_service.set_daily_limit(roundi(value))
	_limit_label.text = "今日 %d / %d 次" % [_service.get_daily_usage(), roundi(value)]


func _save_text_settings() -> void:
	if not _service:
		return
	_service.set_model_override(_model_input.text)
	_service.set_blacklist_text(_blacklist_input.text)


func _on_clear_memory_pressed() -> void:
	_service.clear_short_term_memory()
	_refresh_controls()


func _on_look_now_pressed() -> void:
	_save_text_settings()
	if not _service.is_enabled():
		_status_label.text = "先开启画面授权哦"
		return
	hide()
	await get_tree().create_timer(0.28).timeout
	_service.request_analysis("manual", true)


func _on_analysis_started() -> void:
	_status_label.text = "正在取关键帧并理解当前任务……"


func _on_analysis_ready(_result: Dictionary) -> void:
	_refresh_controls()


func _on_analysis_failed(message: String) -> void:
	_status_label.text = message


func _on_drag_handle_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		DisplayServer.window_start_drag(get_window_id())


func _play_open_animation() -> void:
	if _panel_tween and _panel_tween.is_valid():
		_panel_tween.kill()
	_root.scale = Vector2.ONE * 0.96
	_root.position = Vector2(PANEL_SIZE) * 0.02
	_panel_tween = create_tween()
	_panel_tween.set_parallel(true)
	_panel_tween.tween_property(_root, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_panel_tween.tween_property(_root, "position", Vector2.ZERO, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _make_label(text: String, node_position: Vector2, node_size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = node_position
	label.size = node_size
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if _font:
		label.add_theme_font_override("font", _font)
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


func _make_toggle(node_position: Vector2) -> Button:
	var button := Button.new()
	button.position = node_position
	button.size = Vector2(104, 34)
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", Color("684650"))
	button.add_theme_color_override("font_hover_color", Color("684650"))
	button.add_theme_color_override("font_pressed_color", Color("684650"))
	if _font:
		button.add_theme_font_override("font", _font)
	return button


func _style_toggle(button: Button, enabled: bool, on_text := "已开启", off_text := "已关闭") -> void:
	button.text = on_text if enabled else off_text
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("f5b7c3") if enabled else Color("e8e4dc")
	normal.border_color = Color("d98799") if enabled else Color("b6ab9b")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	var hover := normal.duplicate()
	hover.bg_color = Color("f8c7d0") if enabled else Color("f0ece5")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", normal)


func _make_tab_button(text: String, node_position: Vector2) -> Button:
	var button := Button.new()
	button.position = node_position
	button.size = Vector2(138, 30)
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", Color("714b57"))
	button.add_theme_color_override("font_hover_color", Color("714b57"))
	button.add_theme_color_override("font_pressed_color", Color("714b57"))
	if _font:
		button.add_theme_font_override("font", _font)
	return button


func _style_tab(button: Button, selected: bool) -> void:
	if not button:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f7c3ce") if selected else Color("fff7f3")
	style.border_color = Color("d98b9b") if selected else Color("dfbac1")
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(8)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("focus", style)


func _style_input_control(control: Control) -> void:
	control.add_theme_font_size_override("font_size", 13)
	control.add_theme_color_override("font_color", Color("654650"))
	if _font:
		control.add_theme_font_override("font", _font)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fff7f3")
	style.border_color = Color("dda1ac")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 8
	style.content_margin_right = 8
	control.add_theme_stylebox_override("normal", style)
	control.add_theme_stylebox_override("focus", style)


func _style_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color("f2d2d6")
	track.set_corner_radius_all(5)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("e696a6")
	fill.set_corner_radius_all(5)
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)


func _make_small_button(text: String, node_position: Vector2, node_size: Vector2) -> Button:
	var button := Button.new()
	button.position = node_position
	button.size = node_size
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", Color("714651"))
	button.add_theme_color_override("font_hover_color", Color("714651"))
	button.add_theme_color_override("font_pressed_color", Color("714651"))
	if _font:
		button.add_theme_font_override("font", _font)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("fff7f3")
	normal.border_color = Color("dda1ac")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
	button.add_theme_stylebox_override("pressed", normal)
	button.pivot_offset = button.size * 0.5
	button.mouse_entered.connect(_animate_button.bind(button, true))
	button.mouse_exited.connect(_animate_button.bind(button, false))
	return button


func _make_action_button(text: String, node_position: Vector2, node_size: Vector2) -> Button:
	var button := Button.new()
	button.position = node_position
	button.size = node_size
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Color("714651"))
	button.add_theme_color_override("font_hover_color", Color("714651"))
	button.add_theme_color_override("font_pressed_color", Color("714651"))
	if _font:
		button.add_theme_font_override("font", _font)
	button.add_theme_stylebox_override("normal", _make_button_texture(40))
	button.add_theme_stylebox_override("hover", _make_button_texture(41))
	button.add_theme_stylebox_override("pressed", _make_button_texture(42))
	button.add_theme_stylebox_override("focus", _make_button_texture(40))
	button.pivot_offset = button.size * 0.5
	button.mouse_entered.connect(_animate_button.bind(button, true))
	button.mouse_exited.connect(_animate_button.bind(button, false))
	return button


func _make_button_texture(number: int) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load(UI_DIR + "/%d_spritesheet.png" % number) as Texture2D
	return style


func _animate_button(button: Control, hovered: bool) -> void:
	var previous: Tween = _button_tweens.get(button.get_instance_id())
	if previous and previous.is_valid():
		previous.kill()
	var tween := create_tween()
	_button_tweens[button.get_instance_id()] = tween
	tween.tween_property(button, "scale", Vector2.ONE * (1.035 if hovered else 1.0), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _reason_text(reason: String) -> String:
	match reason:
		"app_switch": return "切换应用"
		"major_change": return "画面变化"
		"scheduled": return "定时复查"
		_: return "手动观察"
