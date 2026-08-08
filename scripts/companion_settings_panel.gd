extends Window
class_name PetCompanionSettingsPanel

const UI_DIR := "res://assets/companion/runtime/ui"
const BASE_SIZE := Vector2(1478, 1037)
const UI_SCALE := 0.4
const PANEL_SIZE := Vector2i(591, 415)

var _font: Font
var _companion: PetProactiveCompanion
var _monitor: PetForegroundAppMonitor
var _root: Control
var _enabled_toggle: Button
var _monitor_toggle: Button
var _quiet_hours_toggle: Button
var _frequency_slider: HSlider
var _frequency_label: Label
var _app_status: Label
var _memory_status: Label
var _panel_tween: Tween
var _button_tweens: Dictionary = {}


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


func configure(font: Font, companion: PetProactiveCompanion, monitor: PetForegroundAppMonitor) -> void:
	_font = font
	_companion = companion
	_monitor = monitor


func _ready() -> void:
	close_requested.connect(hide_panel)
	_build_ui()
	if _companion:
		_companion.settings_changed.connect(_refresh_controls)
	if _monitor:
		_monitor.foreground_app_changed.connect(_on_foreground_app_changed)
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
	hide()


func _build_ui() -> void:
	_root = Control.new()
	_root.size = BASE_SIZE
	_root.scale = Vector2.ONE * UI_SCALE
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var background := TextureRect.new()
	background.size = BASE_SIZE
	background.texture = load(UI_DIR + "/1_spritesheet.png") as Texture2D
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(background)

	var drag_handle := Control.new()
	drag_handle.position = Vector2(90, 30)
	drag_handle.size = Vector2(1110, 155)
	drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	drag_handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	drag_handle.gui_input.connect(_on_drag_handle_gui_input)
	_root.add_child(drag_handle)

	var minimize_button := _make_hit_button(Vector2(1252, 50), Vector2(92, 100), "收起")
	minimize_button.pressed.connect(hide_panel)
	_root.add_child(minimize_button)
	var close_button := _make_hit_button(Vector2(1350, 50), Vector2(92, 100), "关闭")
	close_button.pressed.connect(hide_panel)
	_root.add_child(close_button)

	var title_label := _make_label("陪伴设置", Vector2(470, 190), Vector2(540, 64), 43, Color("714b57"))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(title_label)

	_build_companion_controls()
	_build_awareness_controls()
	_build_action_buttons()


func _build_companion_controls() -> void:
	_root.add_child(_make_icon(23, Vector2(112, 260), Vector2(92, 103)))
	_root.add_child(_make_label("主动陪伴", Vector2(225, 260), Vector2(290, 54), 34, Color("654650")))
	_enabled_toggle = _make_toggle(Vector2(520, 255))
	_enabled_toggle.toggled.connect(_on_enabled_toggled)
	_root.add_child(_enabled_toggle)

	_root.add_child(_make_label("表达频率", Vector2(135, 385), Vector2(250, 48), 30, Color("704d57")))
	_frequency_label = _make_label("", Vector2(460, 385), Vector2(260, 48), 28, Color("a25e6c"))
	_frequency_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_frequency_label)

	_frequency_slider = HSlider.new()
	_frequency_slider.position = Vector2(145, 448)
	_frequency_slider.size = Vector2(560, 54)
	_frequency_slider.min_value = 5.0 / 60.0
	_frequency_slider.max_value = 10.0
	_frequency_slider.step = 0.25
	_frequency_slider.tooltip_text = "调节主动表达的平均间隔"
	_style_slider(_frequency_slider)
	_frequency_slider.value_changed.connect(_on_frequency_changed)
	_root.add_child(_frequency_slider)

	var presets := [
		{"label": "5秒测试", "value": 5.0 / 60.0},
		{"label": "活泼", "value": 0.25},
		{"label": "日常", "value": 3.5},
		{"label": "安静", "value": 7.0}
	]
	for index in presets.size():
		var preset: Dictionary = presets[index]
		var button := _make_preset_button(String(preset["label"]), Vector2(135 + index * 147, 525))
		button.pressed.connect(_on_preset_pressed.bind(float(preset["value"])))
		_root.add_child(button)

	_root.add_child(_make_icon(29, Vector2(116, 650), Vector2(88, 88)))
	_root.add_child(_make_label("夜间安静", Vector2(225, 662), Vector2(280, 50), 31, Color("654650")))
	_quiet_hours_toggle = _make_toggle(Vector2(520, 652))
	_quiet_hours_toggle.tooltip_text = "23:00 至 08:00 暂停主动表达"
	_quiet_hours_toggle.toggled.connect(_on_quiet_hours_toggled)
	_root.add_child(_quiet_hours_toggle)


func _build_awareness_controls() -> void:
	_root.add_child(_make_icon(12, Vector2(782, 260), Vector2(92, 92)))
	_root.add_child(_make_label("前台应用感知", Vector2(895, 260), Vector2(330, 54), 34, Color("654650")))
	_monitor_toggle = _make_toggle(Vector2(1225, 255))
	_monitor_toggle.toggled.connect(_on_monitor_toggled)
	_root.add_child(_monitor_toggle)

	_root.add_child(_make_icon(11, Vector2(785, 390), Vector2(82, 82)))
	var privacy_label := _make_label("仅读取最多 8 个可见应用进程名", Vector2(895, 388), Vector2(430, 48), 27, Color("8d6871"))
	_root.add_child(privacy_label)
	_app_status = _make_label("", Vector2(895, 438), Vector2(430, 48), 27, Color("a25e6c"))
	_root.add_child(_app_status)

	_root.add_child(_make_icon(9, Vector2(782, 535), Vector2(92, 92)))
	_root.add_child(_make_label("陪伴记忆", Vector2(895, 535), Vector2(280, 50), 31, Color("654650")))
	_memory_status = _make_label("", Vector2(895, 586), Vector2(430, 44), 25, Color("8d6871"))
	_root.add_child(_memory_status)

	var clear_button := _make_small_button("清空记忆", Vector2(895, 654), Vector2(215, 72))
	clear_button.pressed.connect(_on_clear_memory_pressed)
	_root.add_child(clear_button)
	var refresh_button := _make_small_button("重新识别", Vector2(1130, 654), Vector2(215, 72))
	refresh_button.pressed.connect(_on_refresh_app_pressed)
	_root.add_child(refresh_button)


func _build_action_buttons() -> void:
	var think_button := _make_action_button("现在来陪我", Vector2(275, 790), Vector2(390, 145))
	think_button.tooltip_text = "关闭设置并立即进行一次主动判断"
	think_button.pressed.connect(_on_think_now_pressed)
	_root.add_child(think_button)

	var done_button := _make_action_button("完成", Vector2(815, 790), Vector2(390, 145))
	done_button.pressed.connect(hide_panel)
	_root.add_child(done_button)


func _refresh_controls() -> void:
	if not is_instance_valid(_enabled_toggle) or not _companion:
		return
	_enabled_toggle.set_pressed_no_signal(_companion.is_enabled())
	_monitor_toggle.set_pressed_no_signal(_companion.is_foreground_monitoring_enabled())
	_quiet_hours_toggle.set_pressed_no_signal(_companion.is_quiet_hours_enabled())
	_style_toggle(_enabled_toggle, _enabled_toggle.button_pressed)
	_style_toggle(_monitor_toggle, _monitor_toggle.button_pressed)
	_style_toggle(_quiet_hours_toggle, _quiet_hours_toggle.button_pressed)
	_frequency_slider.set_value_no_signal(_companion.get_frequency_minutes())
	_frequency_label.text = "平均约 " + _format_interval(_companion.get_frequency_minutes())
	_memory_status.text = "已记住 %d 条最近片段" % _companion.get_memory_count()
	_update_app_status(_monitor.get_current_info() if _monitor else {})


func _on_enabled_toggled(value: bool) -> void:
	_style_toggle(_enabled_toggle, value)
	if _companion:
		_companion.set_enabled(value)


func _on_monitor_toggled(value: bool) -> void:
	_style_toggle(_monitor_toggle, value)
	if _companion:
		_companion.set_foreground_monitoring_enabled(value)
	if _monitor:
		_monitor.set_enabled(value)
	_update_app_status(_monitor.get_current_info() if _monitor else {})


func _on_quiet_hours_toggled(value: bool) -> void:
	_style_toggle(_quiet_hours_toggle, value)
	if _companion:
		_companion.set_quiet_hours_enabled(value)


func _on_frequency_changed(value: float) -> void:
	_frequency_label.text = "平均约 " + _format_interval(value)
	if _companion:
		_companion.set_frequency_minutes(value)


func _on_preset_pressed(value: float) -> void:
	_frequency_slider.value = value


func _on_clear_memory_pressed() -> void:
	if _companion:
		_companion.clear_memory()
	_refresh_controls()


func _on_refresh_app_pressed() -> void:
	if _monitor and _monitor.is_enabled():
		_app_status.text = "正在重新识别……"
		_monitor.refresh_now()


func _on_think_now_pressed() -> void:
	if _companion:
		_companion.request_thought_now()
	hide_panel()


func _on_foreground_app_changed(info: Dictionary) -> void:
	_update_app_status(info)


func _update_app_status(info: Dictionary) -> void:
	if not _monitor_toggle or not _monitor_toggle.button_pressed:
		_app_status.text = "当前未开启"
	elif info.is_empty():
		_app_status.text = "正在识别当前软件……"
	else:
		_app_status.text = "当前：%s · 可见应用 %d 个" % [String(info.get("label", "其他应用")), int(info.get("visible_count", 1))]


func _format_interval(minutes: float) -> String:
	if minutes < 1.0:
		return "%d 秒" % roundi(minutes * 60.0)
	if is_equal_approx(minutes, roundf(minutes)):
		return "%d 分钟" % roundi(minutes)
	return "%.1f 分钟" % minutes


func _on_drag_handle_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		DisplayServer.window_start_drag(get_window_id())


func _play_open_animation() -> void:
	if _panel_tween and _panel_tween.is_valid():
		_panel_tween.kill()
	_root.scale = Vector2.ONE * (UI_SCALE * 0.94)
	_panel_tween = create_tween()
	_panel_tween.tween_property(_root, "scale", Vector2.ONE * UI_SCALE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
	button.size = Vector2(180, 68)
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 27)
	button.add_theme_color_override("font_color", Color("684650"))
	button.add_theme_color_override("font_hover_color", Color("684650"))
	button.add_theme_color_override("font_pressed_color", Color("684650"))
	if _font:
		button.add_theme_font_override("font", _font)
	return button


func _style_toggle(button: Button, enabled: bool) -> void:
	button.text = "已开启" if enabled else "已关闭"
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("f5b7c3") if enabled else Color("e8e4dc")
	normal.border_color = Color("d98799") if enabled else Color("b6ab9b")
	normal.set_border_width_all(3)
	normal.set_corner_radius_all(28)
	var hover := normal.duplicate()
	hover.bg_color = Color("f8c7d0") if enabled else Color("f0ece5")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", normal)


func _style_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color("f4dfd7")
	track.border_color = Color("d999a5")
	track.set_border_width_all(2)
	track.set_corner_radius_all(10)
	track.content_margin_top = 10.0
	track.content_margin_bottom = 10.0
	var fill := track.duplicate()
	fill.bg_color = Color("efa7b7")
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	var sparkle := load(UI_DIR + "/22_spritesheet.png") as Texture2D
	slider.add_theme_icon_override("grabber", sparkle)
	slider.add_theme_icon_override("grabber_highlight", sparkle)


func _make_preset_button(text: String, node_position: Vector2) -> Button:
	var button := _make_small_button(text, node_position, Vector2(128, 62))
	_bind_button_motion(button, 1.05)
	return button


func _make_small_button(text: String, node_position: Vector2, node_size: Vector2) -> Button:
	var button := Button.new()
	button.position = node_position
	button.size = node_size
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 25)
	button.add_theme_color_override("font_color", Color("684650"))
	button.add_theme_color_override("font_hover_color", Color("684650"))
	button.add_theme_color_override("font_pressed_color", Color("684650"))
	if _font:
		button.add_theme_font_override("font", _font)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("fae9e4")
	normal.border_color = Color("dea0aa")
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(18)
	var hover := normal.duplicate()
	hover.bg_color = Color("f8ccd3")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", normal)
	return button


func _make_action_button(text: String, node_position: Vector2, node_size: Vector2) -> Button:
	var button := Button.new()
	button.position = node_position
	button.size = node_size
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 34)
	button.add_theme_color_override("font_color", Color("714651"))
	button.add_theme_color_override("font_hover_color", Color("714651"))
	button.add_theme_color_override("font_pressed_color", Color("714651"))
	if _font:
		button.add_theme_font_override("font", _font)
	button.add_theme_stylebox_override("normal", _make_button_texture(40))
	button.add_theme_stylebox_override("hover", _make_button_texture(41))
	button.add_theme_stylebox_override("pressed", _make_button_texture(42))
	button.add_theme_stylebox_override("focus", _make_button_texture(40))
	_bind_button_motion(button, 1.035)
	return button


func _make_button_texture(number: int) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load(UI_DIR + "/%d_spritesheet.png" % number) as Texture2D
	style.texture_margin_left = 90.0
	style.texture_margin_top = 90.0
	style.texture_margin_right = 90.0
	style.texture_margin_bottom = 90.0
	style.content_margin_left = 50.0
	style.content_margin_right = 50.0
	return style


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
