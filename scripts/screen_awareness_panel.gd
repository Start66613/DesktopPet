extends Window
class_name PetScreenAwarenessPanel

const UI_DIR := "res://assets/companion/runtime/ui"
const BASE_SIZE := Vector2(1478, 1037)
const UI_SCALE := 0.4
const PANEL_SIZE := Vector2i(591, 415)

var _font: Font
var _service: PetScreenAwarenessService
var _root: Control
var _text_layer: Control
var _enabled_toggle: Button
var _auto_toggle: Button
var _model_input: LineEdit
var _status_label: Label
var _toggle_labels: Dictionary = {}
var _panel_tween: Tween
var _button_tweens: Dictionary = {}


func _init() -> void:
	visible = false
	title = "屏幕画面感知"
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
		_service.analysis_started.connect(func() -> void: _status_label.text = "我正在看当前屏幕……")
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
	hide()


func _build_ui() -> void:
	_root = Control.new()
	_root.size = BASE_SIZE
	_root.scale = Vector2.ONE * UI_SCALE
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_text_layer = Control.new()
	_text_layer.size = Vector2(PANEL_SIZE)
	_text_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_layer.z_index = 20
	_text_layer.pivot_offset = Vector2(PANEL_SIZE) * 0.5
	add_child(_text_layer)

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

	var title_label := _make_label("屏幕画面感知", Vector2(430, 185), Vector2(620, 68), 43, Color("714b57"))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text_layer.add_child(title_label)

	_root.add_child(_make_icon(12, Vector2(115, 280), Vector2(90, 90)))
	_text_layer.add_child(_make_label("允许查看当前屏幕", Vector2(225, 282), Vector2(360, 54), 32, Color("654650")))
	_enabled_toggle = _make_toggle(Vector2(535, 278))
	_enabled_toggle.toggled.connect(_on_enabled_toggled)
	_text_layer.add_child(_enabled_toggle)

	_root.add_child(_make_icon(11, Vector2(115, 405), Vector2(84, 84)))
	var privacy := _make_label("截图只在内存中缩放，分析后立即释放", Vector2(225, 400), Vector2(525, 55), 25, Color("8d6871"))
	_text_layer.add_child(privacy)

	_root.add_child(_make_icon(29, Vector2(785, 280), Vector2(86, 86)))
	_text_layer.add_child(_make_label("每 10 分钟自动观察", Vector2(895, 282), Vector2(350, 54), 31, Color("654650")))
	_auto_toggle = _make_toggle(Vector2(1215, 278))
	_auto_toggle.toggled.connect(_on_auto_toggled)
	_text_layer.add_child(_auto_toggle)

	_text_layer.add_child(_make_label("视觉模型", Vector2(785, 410), Vector2(220, 48), 29, Color("704d57")))
	_model_input = LineEdit.new()
	_model_input.position = Vector2(785, 468)
	_model_input.size = Vector2(555, 82)
	_model_input.placeholder_text = "留空则使用聊天模型"
	_model_input.tooltip_text = "例如支持图片输入的视觉模型名称"
	_model_input.add_theme_font_size_override("font_size", 30)
	_model_input.add_theme_color_override("font_color", Color("654650"))
	_model_input.add_theme_color_override("font_placeholder_color", Color("ad8a92"))
	if _font:
		_model_input.add_theme_font_override("font", _font)
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color("fff7f3")
	input_style.border_color = Color("dda1ac")
	input_style.set_border_width_all(2)
	input_style.set_corner_radius_all(12)
	input_style.content_margin_left = 12
	input_style.content_margin_right = 12
	_model_input.add_theme_stylebox_override("normal", input_style)
	_model_input.add_theme_stylebox_override("focus", input_style)
	_model_input.text_submitted.connect(func(_value: String) -> void: _save_model())
	_model_input.focus_exited.connect(_save_model)
	_root.add_child(_model_input)

	_status_label = _make_label("", Vector2(145, 585), Vector2(1180, 80), 27, Color("a25e6c"))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_layer.add_child(_status_label)

	var look_button := _make_action_button("立即看看", Vector2(275, 760), Vector2(390, 195))
	look_button.tooltip_text = "隐藏窗口后截取当前显示器一次"
	look_button.pressed.connect(_on_look_now_pressed)
	_root.add_child(look_button)
	var done_button := _make_action_button("完成", Vector2(815, 760), Vector2(390, 195))
	done_button.pressed.connect(hide_panel)
	_root.add_child(done_button)


func _refresh_controls() -> void:
	if not _service or not is_instance_valid(_enabled_toggle):
		return
	_enabled_toggle.set_pressed_no_signal(_service.is_enabled())
	_auto_toggle.set_pressed_no_signal(_service.is_auto_enabled())
	_style_toggle(_enabled_toggle, _enabled_toggle.button_pressed)
	_style_toggle(_auto_toggle, _auto_toggle.button_pressed)
	_auto_toggle.disabled = not _service.is_enabled()
	_model_input.editable = not _service.is_busy()
	if not _model_input.has_focus():
		_model_input.text = _service.get_model_override()
	var last_result := _service.get_last_result()
	if _service.is_busy():
		_status_label.text = "我正在看当前屏幕……"
	elif not _service.is_enabled():
		_status_label.text = "默认关闭，开启后才会截取画面"
	elif not last_result.is_empty():
		_status_label.text = "上次看到：" + String(last_result.get("scene", "已完成分析"))
	else:
		_status_label.text = "已授权 · 点击“立即看看”测试"


func _on_enabled_toggled(value: bool) -> void:
	_style_toggle(_enabled_toggle, value)
	if _service:
		_service.set_enabled(value)
	_refresh_controls()


func _on_auto_toggled(value: bool) -> void:
	_style_toggle(_auto_toggle, value)
	if _service:
		_service.set_auto_enabled(value)


func _save_model() -> void:
	if _service:
		_service.set_model_override(_model_input.text)


func _on_look_now_pressed() -> void:
	_save_model()
	if not _service or not _service.is_enabled():
		_status_label.text = "先开启屏幕画面感知哦"
		return
	hide_panel()
	await get_tree().create_timer(0.28).timeout
	_service.request_analysis()


func _on_analysis_ready(result: Dictionary) -> void:
	_status_label.text = "上次看到：" + String(result.get("scene", "已完成分析"))


func _on_analysis_failed(message: String) -> void:
	_status_label.text = message


func _on_drag_handle_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		DisplayServer.window_start_drag(get_window_id())


func _play_open_animation() -> void:
	if _panel_tween and _panel_tween.is_valid():
		_panel_tween.kill()
	_root.scale = Vector2.ONE * (UI_SCALE * 0.94)
	_text_layer.scale = Vector2.ONE * 0.94
	_panel_tween = create_tween()
	_panel_tween.set_parallel(true)
	_panel_tween.tween_property(_root, "scale", Vector2.ONE * UI_SCALE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_panel_tween.tween_property(_text_layer, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _make_label(text: String, node_position: Vector2, node_size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = node_position * UI_SCALE
	label.size = node_size * UI_SCALE
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", maxi(1, roundi(font_size * UI_SCALE)))
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
	button.position = node_position * UI_SCALE
	button.size = Vector2(180, 68) * UI_SCALE
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	var label := _make_label("", node_position, Vector2(180, 68), 27, Color("684650"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toggle_labels[button.get_instance_id()] = label
	_text_layer.add_child(label)
	return button


func _style_toggle(button: Button, enabled: bool) -> void:
	var label: Label = _toggle_labels.get(button.get_instance_id())
	if label:
		label.text = "已开启" if enabled else "已关闭"
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("f5b7c3") if enabled else Color("e8e4dc")
	normal.border_color = Color("d98799") if enabled else Color("b6ab9b")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(11)
	var hover := normal.duplicate()
	hover.bg_color = Color("f8c7d0") if enabled else Color("f0ece5")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", normal)


func _make_action_button(text: String, node_position: Vector2, node_size: Vector2) -> Button:
	var button := Button.new()
	button.position = node_position
	button.size = node_size
	button.text = ""
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", _make_button_texture(40))
	button.add_theme_stylebox_override("hover", _make_button_texture(41))
	button.add_theme_stylebox_override("pressed", _make_button_texture(42))
	button.add_theme_stylebox_override("focus", _make_button_texture(40))
	button.pivot_offset = button.size * 0.5
	button.mouse_entered.connect(_animate_button.bind(button, true))
	button.mouse_exited.connect(_animate_button.bind(button, false))
	var label := _make_label(text, node_position, node_size, 34, Color("714651"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text_layer.add_child(label)
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
