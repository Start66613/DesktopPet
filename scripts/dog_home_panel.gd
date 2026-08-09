extends Window
class_name PetDogHomePanel

signal action_requested(action: String)
signal adoption_requested
signal home_toggle_requested

const UI_DIR := "res://assets/dog/source/blue_ui/1-animations/textures"
const FURNITURE_DIR := "res://assets/dog/source/furniture/1-animations/textures"
const BASE_SIZE := Vector2(1602, 960)
const UI_SCALE := 0.36
const PANEL_SIZE := Vector2i(577, 346)

const ACTIONS := [
	{"key": "feed", "label": "喂点心", "texture": 6, "position": Vector2(720, 275)},
	{"key": "drink", "label": "喝水", "texture": 7, "position": Vector2(1090, 275)},
	{"key": "play", "label": "玩球球", "texture": 12, "position": Vector2(720, 545)},
	{"key": "rest", "label": "回窝休息", "texture": 2, "position": Vector2(1090, 545)}
]

var _font: Font
var _dog_frames: SpriteFrames
var _root: Control
var _preview: AnimatedSprite2D
var _title_label: Label
var _name_label: Label
var _status_label: Label
var _home_toggle_button: TextureButton
var _home_toggle_label: Label
var _action_controls: Array[CanvasItem] = []
var _adoption_controls: Array[CanvasItem] = []
var _panel_tween: Tween
var _button_tweens: Dictionary = {}
var _adopted := false
var _dog_active := false


func _init() -> void:
	visible = false
	title = "小雪球的小屋"
	size = PANEL_SIZE
	min_size = PANEL_SIZE
	borderless = true
	transparent_bg = true
	unresizable = true
	always_on_top = false
	force_native = true


func configure(font: Font, dog_frames: SpriteFrames) -> void:
	_font = font
	_dog_frames = dog_frames


func _ready() -> void:
	close_requested.connect(hide_panel)
	_build_ui()


func open_at(screen_position: Vector2i, adopted: bool, dog_active: bool) -> void:
	position = screen_position
	mode = Window.MODE_WINDOWED
	_refresh_mode(adopted, dog_active)
	if _preview and _dog_frames and _dog_frames.has_animation("idle"):
		_preview.play("idle")
	_restore_visual_state()
	if visible:
		grab_focus()
		DisplayServer.window_set_mouse_passthrough(PackedVector2Array(), get_window_id())
		return
	_prepare_open_animation()
	show()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true, get_window_id())
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array(), get_window_id())
	transparent_bg = true
	grab_focus()
	_play_open_animation()


func refresh_state(adopted: bool, dog_active: bool) -> void:
	_refresh_mode(adopted, dog_active)


func hide_panel() -> void:
	_restore_visual_state()
	hide()


func _build_ui() -> void:
	_root = Control.new()
	_root.size = BASE_SIZE
	_root.scale = Vector2.ONE * UI_SCALE
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var background := _make_texture_rect(UI_DIR + "/1_spritesheet.png", Vector2.ZERO, BASE_SIZE)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(background)

	var drag_handle := Control.new()
	drag_handle.position = Vector2(220, 35)
	drag_handle.size = Vector2(1040, 145)
	drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	drag_handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	drag_handle.gui_input.connect(_on_drag_handle_gui_input)
	_root.add_child(drag_handle)

	_title_label = _make_label("小雪球的小屋", Vector2(490, 122), Vector2(620, 72), 50, Color("55748c"))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_title_label)

	var preview_frame := _make_texture_rect(UI_DIR + "/3_spritesheet.png", Vector2(105, 220), Vector2(500, 465))
	preview_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(preview_frame)

	_preview = AnimatedSprite2D.new()
	_preview.sprite_frames = _dog_frames
	_preview.position = Vector2(355, 442)
	_preview.scale = Vector2.ONE * 4.25
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_root.add_child(_preview)
	if _dog_frames and _dog_frames.has_animation("idle"):
		_preview.play("idle")

	_name_label = _make_label("小雪球", Vector2(185, 545), Vector2(340, 50), 34, Color("5f7587"))
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_name_label)

	var status_bar := _make_texture_rect(UI_DIR + "/11_spritesheet.png", Vector2(670, 192), Vector2(710, 124))
	status_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(status_bar)
	_status_label = _make_label("今天也精神满满，正在陪你巡逻呢", Vector2(715, 220), Vector2(615, 55), 28, Color("55748c"))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_status_label)

	for action in ACTIONS:
		_create_action_button(action)

	_build_adoption_controls()
	_build_home_toggle()

	var close_button := TextureButton.new()
	close_button.position = Vector2(1428, 56)
	close_button.size = Vector2(110, 110)
	close_button.texture_normal = load(UI_DIR + "/7_spritesheet.png") as Texture2D
	close_button.ignore_texture_size = true
	close_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	close_button.tooltip_text = "关闭"
	close_button.pressed.connect(hide_panel)
	_root.add_child(close_button)
	_bind_button_motion(close_button, 1.08, 3.0)


func _create_action_button(action: Dictionary) -> void:
	var button := TextureButton.new()
	button.position = action["position"]
	button.size = Vector2(235, 185)
	button.texture_normal = load(FURNITURE_DIR + "/" + str(action["texture"]) + "_spritesheet.png") as Texture2D
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	button.tooltip_text = action["label"]
	button.pressed.connect(_on_action_pressed.bind(String(action["key"]), String(action["label"])))
	_root.add_child(button)
	_action_controls.append(button)
	_bind_button_motion(button, 1.1, 4.0)

	var label := _make_label(action["label"], action["position"] + Vector2(-25, 184), Vector2(285, 52), 31, Color("5c7183"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(label)
	_action_controls.append(label)


func _build_adoption_controls() -> void:
	var message := _make_label("它好像一直在等你。\n愿意带它回家吗？", Vector2(720, 330), Vector2(610, 150), 38, Color("5c7183"))
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(message)
	_adoption_controls.append(message)

	var adopt_button := TextureButton.new()
	adopt_button.position = Vector2(900, 495)
	adopt_button.size = Vector2(255, 250)
	adopt_button.texture_normal = load(UI_DIR + "/4_spritesheet.png") as Texture2D
	adopt_button.ignore_texture_size = true
	adopt_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	adopt_button.tooltip_text = "领养回家"
	adopt_button.pressed.connect(_on_adoption_pressed)
	_root.add_child(adopt_button)
	_adoption_controls.append(adopt_button)
	_bind_button_motion(adopt_button, 1.1, 3.0)

	var label := _make_label("领养回家", Vector2(835, 740), Vector2(385, 65), 40, Color("55748c"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(label)
	_adoption_controls.append(label)


func _build_home_toggle() -> void:
	_home_toggle_button = TextureButton.new()
	_home_toggle_button.position = Vector2(1285, 54)
	_home_toggle_button.size = Vector2(112, 105)
	_home_toggle_button.texture_normal = load(FURNITURE_DIR + "/1_spritesheet.png") as Texture2D
	_home_toggle_button.ignore_texture_size = true
	_home_toggle_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_home_toggle_button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_home_toggle_button.tooltip_text = "让小雪球回窝"
	_home_toggle_button.pressed.connect(_on_home_toggle_pressed)
	_root.add_child(_home_toggle_button)
	_bind_button_motion(_home_toggle_button, 1.08, 2.0)

	_home_toggle_label = _make_label("回窝", Vector2(1265, 148), Vector2(150, 40), 26, Color("5c7183"))
	_home_toggle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_home_toggle_label)


func _refresh_mode(adopted: bool, dog_active: bool) -> void:
	_adopted = adopted
	_dog_active = dog_active
	for control in _action_controls:
		control.visible = adopted
	for control in _adoption_controls:
		control.visible = not adopted
	_home_toggle_button.visible = adopted
	_home_toggle_label.visible = adopted
	if adopted:
		_title_label.text = "小雪球的小屋"
		_name_label.text = "小雪球"
		_status_label.text = "正在桌面陪你巡逻呢" if dog_active else "正在窝里安静休息"
		_home_toggle_label.text = "回窝" if dog_active else "叫出来"
		_home_toggle_button.tooltip_text = "让小雪球回窝" if dog_active else "叫小雪球出来"
	else:
		_title_label.text = "流浪小狗领养处"
		_name_label.text = "等待一个名字"
		_status_label.text = "一只白色小狗正在等待新的家"


func _on_action_pressed(action: String, label: String) -> void:
	_status_label.text = "正在" + label + "，看起来很开心"
	action_requested.emit(action)


func _on_adoption_pressed() -> void:
	adoption_requested.emit()


func _on_home_toggle_pressed() -> void:
	home_toggle_requested.emit()


func _on_drag_handle_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		DisplayServer.window_start_drag(get_window_id())


func _restore_visual_state() -> void:
	if _panel_tween and _panel_tween.is_valid():
		_panel_tween.kill()
	_root.visible = true
	_root.modulate = Color.WHITE
	_root.scale = Vector2.ONE * UI_SCALE


func _prepare_open_animation() -> void:
	_restore_visual_state()
	_root.scale = Vector2.ONE * (UI_SCALE * 0.975)


func _play_open_animation() -> void:
	_panel_tween = create_tween()
	_panel_tween.tween_property(_root, "scale", Vector2.ONE * UI_SCALE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _bind_button_motion(button: Control, hover_scale: float, angle_degrees: float) -> void:
	button.pivot_offset = button.size * 0.5
	button.mouse_entered.connect(_animate_button.bind(button, true, hover_scale, angle_degrees))
	button.mouse_exited.connect(_animate_button.bind(button, false, hover_scale, angle_degrees))


func _animate_button(button: Control, hovered: bool, hover_scale: float, angle_degrees: float) -> void:
	var button_id := button.get_instance_id()
	var previous: Tween = _button_tweens.get(button_id)
	if previous and previous.is_valid():
		previous.kill()
	var tween := create_tween()
	_button_tweens[button_id] = tween
	tween.set_parallel(true)
	tween.tween_property(button, "scale", Vector2.ONE * (hover_scale if hovered else 1.0), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "rotation", deg_to_rad(angle_degrees if hovered else 0.0), 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _make_texture_rect(path: String, rect_position: Vector2, rect_size: Vector2) -> TextureRect:
	var rect := TextureRect.new()
	rect.position = rect_position
	rect.size = rect_size
	rect.texture = load(path) as Texture2D
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	return rect


func _make_label(text: String, label_position: Vector2, label_size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = label_position
	label.size = label_size
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if _font:
		label.add_theme_font_override("font", _font)
	return label
