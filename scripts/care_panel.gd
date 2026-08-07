extends Window
class_name PetCarePanel

const PANEL_SIZE := Vector2i(440, 470)
const CARE_UI_DIR := "res://assets/care/runtime/ui"

const STAT_LAYOUT := [
	{"key": "fullness", "label": "饱腹", "y": 94.0, "color": Color("ef9b9c")},
	{"key": "hydration", "label": "水分", "y": 141.0, "color": Color("73b9d6")},
	{"key": "mood", "label": "心情", "y": 189.0, "color": Color("e4b45d")},
	{"key": "affection", "label": "好感", "y": 237.0, "color": Color("ec86a6")},
	{"key": "energy", "label": "精力", "y": 284.0, "color": Color("a68bd4")}
]

const ACTION_LAYOUT := [
	{"key": "meal", "label": "吃饭", "icon": "action_meal.png", "tip": "一起吃点东西"},
	{"key": "drink", "label": "喝水", "icon": "action_drink.png", "tip": "选一杯喜欢的饮料"},
	{"key": "chat", "label": "聊天", "icon": "action_chat.png", "tip": "陪她聊一会儿"},
	{"key": "play", "label": "娱乐", "icon": "action_play.png", "tip": "选一种娱乐活动"},
	{"key": "gift", "label": "送礼", "icon": "action_gift.png", "tip": "送她一份小礼物"},
	{"key": "comfort", "label": "摸摸", "icon": "action_comfort.png", "tip": "摸摸头，安慰一下她"},
	{"key": "rest", "label": "休息", "icon": "action_rest.png", "tip": "让她躺下休息"}
]

const PICKER_TITLES := {
	"meal": "今天想吃什么？",
	"drink": "选一杯喜欢的饮料",
	"play": "一起做点什么吧",
	"gift": "挑一份礼物送给她"
}

var _care_system: PetCareSystem
var _font: Font
var _portrait: TextureRect
var _stat_bars: Dictionary = {}
var _stat_labels: Dictionary = {}
var _picker_overlay: Control
var _picker_title: Label
var _picker_grid: GridContainer
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween


func _init() -> void:
	visible = false
	title = "她的日常"
	size = PANEL_SIZE
	min_size = PANEL_SIZE
	borderless = true
	transparent_bg = true
	unresizable = true
	always_on_top = true
	force_native = true


func configure(care_system: PetCareSystem, font: Font) -> void:
	_care_system = care_system
	_font = font


func _ready() -> void:
	close_requested.connect(hide_panel)
	_build_ui()
	if _care_system:
		_care_system.stats_changed.connect(_on_stats_changed)
		_care_system.action_performed.connect(_on_action_performed)
		_refresh_stats(_care_system.get_stats())


func open_at(screen_position: Vector2i, portrait_texture: Texture2D) -> void:
	position = screen_position
	if portrait_texture:
		_portrait.texture = portrait_texture
	_picker_overlay.visible = false
	show()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true, get_window_id())
	grab_focus()


func hide_panel() -> void:
	_picker_overlay.visible = false
	hide()


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var background := _make_texture_rect(CARE_UI_DIR + "/care_panel.png", Vector2(20, 4), Vector2(400, 382))
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)

	_portrait = TextureRect.new()
	_portrait.position = Vector2(42, 88)
	_portrait.size = Vector2(148, 148)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_portrait)

	for stat in STAT_LAYOUT:
		_create_stat_row(root, stat)

	var close_button := _make_texture_button(CARE_UI_DIR + "/close.png", Vector2(397, 12), Vector2(30, 30))
	close_button.tooltip_text = "关闭"
	close_button.pressed.connect(hide_panel)
	root.add_child(close_button)

	for index in ACTION_LAYOUT.size():
		_create_action_button(root, index, ACTION_LAYOUT[index])

	_build_picker(root)
	_build_toast(root)


func _create_stat_row(root: Control, stat: Dictionary) -> void:
	var key: String = stat["key"]
	var y: float = stat["y"]
	var label := Label.new()
	label.position = Vector2(243, y)
	label.size = Vector2(130, 18)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color("654750"))
	if _font:
		label.add_theme_font_override("font", _font)
	root.add_child(label)
	_stat_labels[key] = label

	var bar := ProgressBar.new()
	bar.position = Vector2(243, y + 19.0)
	bar.size = Vector2(124, 8)
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background_style := StyleBoxFlat.new()
	background_style.bg_color = Color(1.0, 0.97, 0.96, 0.88)
	background_style.border_color = Color("e5c1c1")
	background_style.set_border_width_all(1)
	background_style.set_corner_radius_all(4)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = stat["color"]
	fill_style.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", background_style)
	bar.add_theme_stylebox_override("fill", fill_style)
	root.add_child(bar)
	_stat_bars[key] = bar


func _create_action_button(root: Control, index: int, action: Dictionary) -> void:
	var x := 25.0 + float(index) * 56.0
	var button := _make_texture_button(CARE_UI_DIR + "/" + action["icon"], Vector2(x, 391), Vector2(47, 47))
	button.tooltip_text = action["tip"]
	button.pressed.connect(_on_action_pressed.bind(action["key"]))
	root.add_child(button)

	var label := Label.new()
	label.position = Vector2(x - 4.0, 439)
	label.size = Vector2(55, 22)
	label.text = action["label"]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("694a55"))
	if _font:
		label.add_theme_font_override("font", _font)
	root.add_child(label)


func _build_picker(root: Control) -> void:
	_picker_overlay = Control.new()
	_picker_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picker_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_picker_overlay.visible = false
	root.add_child(_picker_overlay)

	var dimmer := ColorRect.new()
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.28, 0.16, 0.20, 0.22)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_picker_overlay.add_child(dimmer)

	var picker_background := _make_texture_rect(CARE_UI_DIR + "/item_picker.png", Vector2(25, 111), Vector2(390, 264))
	picker_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picker_overlay.add_child(picker_background)

	_picker_title = Label.new()
	_picker_title.position = Vector2(80, 143)
	_picker_title.size = Vector2(280, 30)
	_picker_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_picker_title.add_theme_font_size_override("font_size", 18)
	_picker_title.add_theme_color_override("font_color", Color("684551"))
	if _font:
		_picker_title.add_theme_font_override("font", _font)
	_picker_overlay.add_child(_picker_title)

	_picker_grid = GridContainer.new()
	_picker_grid.columns = 5
	_picker_grid.position = Vector2(47, 192)
	_picker_grid.size = Vector2(346, 145)
	_picker_grid.add_theme_constant_override("h_separation", 5)
	_picker_grid.add_theme_constant_override("v_separation", 4)
	_picker_overlay.add_child(_picker_grid)

	var close_picker := Button.new()
	close_picker.position = Vector2(365, 126)
	close_picker.size = Vector2(40, 40)
	close_picker.flat = true
	close_picker.focus_mode = Control.FOCUS_NONE
	close_picker.tooltip_text = "返回"
	close_picker.pressed.connect(func() -> void: _picker_overlay.visible = false)
	_picker_overlay.add_child(close_picker)


func _build_toast(root: Control) -> void:
	_toast = PanelContainer.new()
	_toast.position = Vector2(105, 347)
	_toast.size = Vector2(230, 34)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f6ccd5")
	style.border_color = Color("d98b9a")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0.25, 0.12, 0.17, 0.18)
	style.shadow_size = 4
	_toast.add_theme_stylebox_override("panel", style)
	root.add_child(_toast)

	_toast_label = Label.new()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_size_override("font_size", 14)
	_toast_label.add_theme_color_override("font_color", Color("684551"))
	if _font:
		_toast_label.add_theme_font_override("font", _font)
	_toast.add_child(_toast_label)


func _on_action_pressed(action: String) -> void:
	if action in ["meal", "drink", "play", "gift"]:
		_open_picker(action)
	elif _care_system:
		_care_system.perform_action(action)


func _open_picker(category: String) -> void:
	if not _care_system:
		return
	_picker_title.text = PICKER_TITLES.get(category, "选一个吧")
	for child in _picker_grid.get_children():
		child.free()

	var items := _care_system.get_items(category)
	for index in items.size():
		var item: Dictionary = items[index]
		var cell := VBoxContainer.new()
		cell.custom_minimum_size = Vector2(64, 132)
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		_picker_grid.add_child(cell)

		var button := TextureButton.new()
		button.custom_minimum_size = Vector2(62, 82)
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		button.texture_normal = load(item["icon"]) as Texture2D
		button.tooltip_text = item["name"]
		button.pressed.connect(_on_item_selected.bind(category, index))
		cell.add_child(button)

		var label := Label.new()
		label.custom_minimum_size = Vector2(64, 36)
		label.text = item["name"]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", Color("684551"))
		if _font:
			label.add_theme_font_override("font", _font)
		cell.add_child(label)
	_picker_overlay.visible = true


func _on_item_selected(category: String, index: int) -> void:
	if _care_system:
		_care_system.perform_action(category, index)


func _on_stats_changed(stats: Dictionary) -> void:
	_refresh_stats(stats)


func _refresh_stats(stats: Dictionary) -> void:
	for stat in STAT_LAYOUT:
		var key: String = stat["key"]
		var value := clampf(float(stats.get(key, 0.0)), 0.0, 100.0)
		(_stat_bars[key] as ProgressBar).value = value
		var suffix := ""
		if key == "affection":
			suffix = "  Lv.%d" % mini(int(value / 20.0) + 1, 5)
		(_stat_labels[key] as Label).text = "%s  %d%s" % [stat["label"], roundi(value), suffix]


func _on_action_performed(result: Dictionary) -> void:
	_picker_overlay.visible = false
	var feedback: String = result.get("feedback", "")
	if feedback.is_empty():
		feedback = "现在先不用这个"
	_show_toast(feedback, bool(result.get("success", false)))


func _show_toast(text: String, success: bool) -> void:
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_label.text = ("♡ " if success else "· ") + text
	_toast.modulate = Color.WHITE
	_toast.position.y = 347.0
	_toast.visible = true
	_toast_tween = create_tween()
	_toast_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_toast_tween.tween_interval(0.8)
	_toast_tween.set_parallel(true)
	_toast_tween.tween_property(_toast, "position:y", 337.0, 0.45)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.45)
	_toast_tween.set_parallel(false)
	_toast_tween.tween_callback(func() -> void: _toast.visible = false)


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
	return button
