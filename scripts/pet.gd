extends Node2D
## 桌宠主控脚本
## - 自动扫描 res://assets/sprites/<动作>/ 下的 PNG 构建帧动画
## - 简单状态机（IDLE / WALK）
## - 无边框透明窗口：左键拖动、右键菜单、ESC 退出
## - 透明区域点击穿透：根据精灵不透明像素包围盒生成矩形多边形，
##   窗口仅在包围盒内接收鼠标事件，其余穿透到后方窗口

const SPRITES_DIR := "res://assets/sprites"
const MOVEMENT_DIR := "res://assets/movement"
const SPRITE_SCALE := 1.0
const PET_VERTICAL_OFFSET := 20.0
const DEFAULT_FPS := 8.0
const SLEEP_ANIMATION := "sleep"
const SLEEP_ENTER_ANIMATION := "sleep_enter"
const SLEEP_IDLE_ANIMATION := "sleep_idle"
const SLEEP_TURN_ANIMATION := "sleep_turn"
const SLEEP_IDLE_FPS := 3.0
const SLEEP_CHANCE := 0.28
const SLEEP_MIN_DURATION := 12.0
const SLEEP_MAX_DURATION := 22.0
const SLEEP_TURN_MIN_INTERVAL := 4.5
const SLEEP_TURN_MAX_INTERVAL := 8.0
const SLEEP_TURN_CHANCE := 0.62
const SLEEP_TURN_MIN_HOLD := 0.85
const SLEEP_TURN_MAX_HOLD := 1.25
const DRAG_CURSOR_ANCHOR_OFFSET := Vector2(0, -30)
const DRAG_SWAY_MAX := 0.36
const DRAG_SWAY_RESPONSE := 16.0
const DRAG_SWAY_DAMPING := 2.6
const ALPHA_THRESHOLD := 0.01  # alpha 低于此值视为透明
const PASSTHROUGH_ROW_STEP := 3
const PASSTHROUGH_MARGIN := 2
const WALK_SPEED := 95.0
const DRAG_THRESHOLD := 8.0
const MENU_TALK := 1
const MENU_TOGGLE_WANDER := 2
const MENU_CENTER := 3
const MENU_SLEEP := 4
const MENU_CARE := 5
const MENU_EXIT := 99
const UI_TEXTURE_DIR := "res://assets/ui_source/generated/1-animations/textures"
const CARE_UI_DIR := "res://assets/care/runtime/ui"
const PET_FONT_PATH := "res://assets/fonts/ZCOOLKuaiLe-Regular.ttf"
const SpeechBubble := preload("res://scripts/speech_bubble.gd")
const CareSystem := preload("res://scripts/care_system.gd")
const CarePanel := preload("res://scripts/care_panel.gd")
const CareFeedback := preload("res://scripts/care_feedback.gd")

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

# ---- 状态机 ----
enum State { IDLE, WALK, SLEEP, WAKE }
enum SleepTurnPhase { NONE, FORWARD, HOLD, BACKWARD }
var state: int = State.IDLE
var _state_time := 0.0
var _state_duration := 0.0
var _move_direction := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _wandering_enabled := true
var _window_position := Vector2.ZERO
var _sleep_turn_phase: int = SleepTurnPhase.NONE
var _sleep_turn_hold_time := 0.0
var _next_sleep_turn_time := 0.0
var _wake_after_sleep_turn := false

# ---- 拖动 ----
var _dragging := false
var _did_drag := false
var _drag_mouse_start := Vector2i.ZERO
var _drag_last_mouse_position := Vector2i.ZERO
var _drag_sway_target := 0.0

# ---- 互动气泡 ----
var _bubble
var _bubble_layer: CanvasLayer
var _bubble_time_left := 0.0
var _speech_time_left := 0.0
var _bubble_lines := [
	{"text": "见到你真好 (^_^)", "emoji": "✨"},
	{"text": "今天也要加油 (>_<)", "emoji": "💪"},
	{"text": "陪我待会儿嘛 (*^_^*)", "emoji": "🎀"},
	{"text": "摸摸会开心 (^o^)", "emoji": "💕"},
	{"text": "我在这里陪你 (._.)", "emoji": ""},
	{"text": "被你发现啦 (^-^)", "emoji": "😺"},
	{"text": "偷偷看你一眼 (o_o)", "emoji": "🌸"},
	{"text": "今天也很可爱呀 (^_^)", "emoji": "💗"}
]
var _cjk_font: Font
var _emoji_font: Font

# ---- 养成系统 ----
var _care_system: PetCareSystem
var _care_panel: PetCarePanel
var _care_feedback: PetCareFeedback
var _comfort_cooldown := 0.0
var _need_lines := {
	"fullness": {"text": "肚子在小声提醒我啦……可以一起吃点东西吗？", "emoji": "🍰"},
	"hydration": {"text": "有一点口渴，想喝杯甜甜的饮料。", "emoji": "💧"},
	"mood": {"text": "陪我玩一会儿嘛，我想和你待在一起。", "emoji": "🎮"},
	"energy": {"text": "眼睛有点睁不开啦……让我靠一会儿。", "emoji": "💤"}
}

# ---- 右键菜单 ----
var _context_menu: PopupMenu

# ---- 点击穿透 ----
# anim_name -> Array[PackedVector2Array]，每帧对应一个包围盒多边形
var _frame_polygons: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	_window_position = Vector2(DisplayServer.window_get_position())
	get_viewport().gui_embed_subwindows = false

	# 让主视口背景真正透明（仅靠项目设置不够）
	get_viewport().transparent_bg = true

	# 扫描文件夹构建动画库
	sprite.sprite_frames = _build_sprite_frames()
	sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = true
	var viewport_size := get_viewport().get_visible_rect().size
	sprite.position = Vector2(viewport_size.x * 0.5, viewport_size.y * 0.5 + PET_VERTICAL_OFFSET)
	_create_bubble()
	_create_care_features()
	_create_context_menu()

	# 预计算每帧的点击穿透多边形
	_precompute_passthrough_polygons()

	# 帧切换时实时更新穿透区域
	sprite.frame_changed.connect(_on_frame_changed)
	sprite.animation_finished.connect(_on_animation_finished)

	_enter_state(state)
	# 设置初始帧的穿透多边形
	_update_passthrough()
	_schedule_next_speech()
	call_deferred("_show_bubble", "你好呀，我会陪着你 (^_^)", 4.0, "✨")
	if OS.get_cmdline_user_args().has("--show-care-panel"):
		call_deferred("_open_care_panel")


func _process(delta: float) -> void:
	_comfort_cooldown = maxf(_comfort_cooldown - delta, 0.0)
	if state != State.SLEEP:
		_speech_time_left -= delta
		if _bubble_time_left > 0.0:
			_bubble_time_left -= delta
			if _bubble_time_left <= 0.0:
				_bubble.clear_message()
				_update_passthrough()
		elif _speech_time_left <= 0.0:
			_say_random()

	if _dragging:
		_update_drag_sway(delta)
		return
	if _context_menu and _context_menu.visible:
		return

	_state_time += delta
	if state == State.SLEEP:
		_update_sleep_turn(delta)
		if _state_time >= _state_duration:
			if _sleep_turn_phase == SleepTurnPhase.NONE:
				_enter_state(State.WAKE)
			else:
				_wake_after_sleep_turn = true
		return
	if state == State.WAKE or not _wandering_enabled:
		return
	if state == State.IDLE:
		if _state_time >= _state_duration:
			_enter_state(State.SLEEP if _rng.randf() < SLEEP_CHANCE else State.WALK)
	elif state == State.WALK:
		_move_window(delta)
		if _state_time >= _state_duration:
			_enter_state(State.IDLE)


func _create_bubble() -> void:
	_bubble_layer = CanvasLayer.new()
	_bubble_layer.name = "SpeechBubbleLayer"
	_bubble_layer.layer = 20
	add_child(_bubble_layer)

	_bubble = SpeechBubble.new()
	_bubble.name = "SpeechBubble"
	_bubble.position = Vector2(50, 1)
	_bubble.z_index = 100
	_cjk_font = _load_system_font(PET_FONT_PATH)
	_emoji_font = _load_system_font("C:/Windows/Fonts/seguiemj.ttf")
	_bubble.configure_fonts(_cjk_font, _emoji_font)
	_bubble_layer.add_child(_bubble)


func _load_system_font(path: String) -> Font:
	if not FileAccess.file_exists(path):
		return ThemeDB.fallback_font
	var font := FontFile.new()
	font.data = FileAccess.get_file_as_bytes(path)
	return font


func _create_care_features() -> void:
	_care_system = CareSystem.new()
	_care_system.name = "CareSystem"
	_care_system.action_performed.connect(_on_care_action_performed)
	add_child(_care_system)

	_care_feedback = CareFeedback.new()
	_care_feedback.name = "CareFeedback"
	_care_feedback.configure_font(_cjk_font)
	_care_feedback.bounds_changed.connect(_update_passthrough)
	add_child(_care_feedback)

	_care_panel = CarePanel.new()
	_care_panel.name = "CarePanel"
	_care_panel.configure(_care_system, _cjk_font)
	add_child(_care_panel)


func _on_care_action_performed(result: Dictionary) -> void:
	if bool(result.get("request_sleep", false)):
		_enter_state(State.SLEEP)
		return

	if state == State.SLEEP:
		_enter_state(State.WAKE)
	elif state != State.WAKE:
		_enter_state(State.IDLE)
		_state_duration = 5.5

	var message: String = result.get("message", "")
	var emoji: String = result.get("emoji", "")
	if not message.is_empty():
		_show_bubble(message, 3.6, emoji)
	if bool(result.get("success", false)) and _care_feedback:
		_care_feedback.show_feedback(result.get("effect", "sparkle"), result.get("feedback", ""))


func _open_care_panel() -> void:
	if not _care_panel:
		return
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = 0
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var pet_position := DisplayServer.window_get_position()
	var pet_size := DisplayServer.window_get_size()
	var panel_size := _care_panel.size
	var panel_x := pet_position.x + pet_size.x + 10
	if panel_x + panel_size.x > usable.end.x:
		panel_x = pet_position.x - panel_size.x - 10
	panel_x = clampi(panel_x, usable.position.x, usable.end.x - panel_size.x)
	var panel_y := clampi(pet_position.y - 70, usable.position.y, usable.end.y - panel_size.y)
	var portrait: Texture2D
	if sprite.sprite_frames and sprite.frame >= 0 and sprite.frame < sprite.sprite_frames.get_frame_count(sprite.animation):
		portrait = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	_care_panel.open_at(Vector2i(panel_x, panel_y), portrait)


func _show_bubble(message: String, duration := 2.8, emoji := "") -> void:
	if state == State.SLEEP:
		return
	_bubble.set_message(message, emoji)
	_bubble_time_left = duration
	_update_passthrough()
	_schedule_next_speech()


func _say_random(duration := 3.0) -> void:
	if _care_system and _rng.randf() < 0.7:
		var need := _care_system.get_lowest_need()
		if float(need["value"]) < 28.0 and _need_lines.has(need["key"]):
			var need_line: Dictionary = _need_lines[need["key"]]
			_show_bubble(need_line["text"], duration + 0.6, need_line["emoji"])
			return
	var line: Dictionary = _bubble_lines[_rng.randi_range(0, _bubble_lines.size() - 1)]
	_show_bubble(line["text"], duration, line["emoji"])


func _schedule_next_speech() -> void:
	_speech_time_left = _rng.randf_range(14.0, 28.0)


func _hide_bubble() -> void:
	_bubble_time_left = 0.0
	if _bubble and _bubble.visible:
		_bubble.clear_message()
		_update_passthrough()


func _create_context_menu() -> void:
	_context_menu = PopupMenu.new()
	_context_menu.name = "PetContextMenu"
	_context_menu.min_size = Vector2i(224, 0)
	_context_menu.add_item("打开她的日常", MENU_CARE)
	_context_menu.add_separator()
	_context_menu.add_item("和她说说话", MENU_TALK)
	_context_menu.add_check_item("自动散步", MENU_TOGGLE_WANDER)
	_context_menu.set_item_checked(_context_menu.get_item_index(MENU_TOGGLE_WANDER), true)
	_context_menu.add_item("回到屏幕中央", MENU_CENTER)
	_context_menu.add_item("让她睡觉", MENU_SLEEP)
	_context_menu.add_separator()
	_context_menu.add_item("退出桌宠", MENU_EXIT)
	_style_context_menu()
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	_context_menu.popup_hide.connect(_on_context_menu_closed)
	add_child(_context_menu)


func _style_context_menu() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("fff8f4")
	panel.border_color = Color("d89aa3")
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(14)
	panel.shadow_color = Color(0.18, 0.10, 0.14, 0.28)
	panel.shadow_size = 7
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color("f9c7d0")
	hover.border_color = Color("e7a2ad")
	hover.set_border_width_all(1)
	hover.set_corner_radius_all(9)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color("f7d9de")
	focus.set_corner_radius_all(9)
	var separator := StyleBoxFlat.new()
	separator.bg_color = Color("ecc5c3")
	separator.content_margin_top = 1.0
	separator.content_margin_bottom = 1.0
	_context_menu.add_theme_stylebox_override("panel", panel)
	_context_menu.add_theme_stylebox_override("hover", hover)
	_context_menu.add_theme_stylebox_override("focus", focus)
	_context_menu.add_theme_stylebox_override("separator", separator)
	_context_menu.add_theme_color_override("font_color", Color("573f49"))
	_context_menu.add_theme_color_override("font_hover_color", Color("422b36"))
	_context_menu.add_theme_color_override("font_focus_color", Color("422b36"))
	_context_menu.add_theme_color_override("font_pressed_color", Color("422b36"))
	_context_menu.add_theme_color_override("font_disabled_color", Color("bdaab0"))
	_context_menu.add_theme_font_override("font", _cjk_font)
	_context_menu.add_theme_font_size_override("font_size", 17)
	_context_menu.add_theme_constant_override("icon_max_width", 25)
	_context_menu.add_theme_constant_override("item_start_padding", 12)
	_context_menu.add_theme_constant_override("item_end_padding", 12)
	_context_menu.add_theme_constant_override("h_separation", 8)
	_context_menu.add_theme_constant_override("v_separation", 5)
	_context_menu.set_item_icon(_context_menu.get_item_index(MENU_CARE), load(CARE_UI_DIR + "/action_comfort.png") as Texture2D)
	_context_menu.set_item_icon(_context_menu.get_item_index(MENU_TALK), _load_ui_texture(17))
	_context_menu.set_item_icon(_context_menu.get_item_index(MENU_TOGGLE_WANDER), _load_ui_texture(10))
	_context_menu.set_item_icon(_context_menu.get_item_index(MENU_CENTER), _load_ui_texture(6))
	_context_menu.set_item_icon(_context_menu.get_item_index(MENU_SLEEP), _load_ui_texture(18))
	_context_menu.set_item_icon(_context_menu.get_item_index(MENU_EXIT), _load_ui_texture(28))


func _load_ui_texture(number: int) -> Texture2D:
	return load(UI_TEXTURE_DIR + "/" + str(number) + "_spritesheet.png") as Texture2D


func _open_context_menu() -> void:
	_dragging = false
	_finish_drag_visual()
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
	_context_menu.position = Vector2i(get_viewport().get_mouse_position())
	_context_menu.popup()


func _on_context_menu_id_pressed(id: int) -> void:
	match id:
		MENU_CARE:
			_open_care_panel()
		MENU_TALK:
			_say_random(3.5)
		MENU_TOGGLE_WANDER:
			_wandering_enabled = not _wandering_enabled
			var index := _context_menu.get_item_index(MENU_TOGGLE_WANDER)
			_context_menu.set_item_checked(index, _wandering_enabled)
			_enter_state(State.IDLE)
			_show_bubble("那就出发吧！" if _wandering_enabled else "好呀，我先在这里休息～")
		MENU_CENTER:
			_center_on_current_screen()
			_show_bubble("我回来啦！")
		MENU_SLEEP:
			_enter_state(State.SLEEP)
		MENU_EXIT:
			get_tree().quit()


func _on_context_menu_closed() -> void:
	_update_passthrough()


func _center_on_current_screen() -> void:
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = 0
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var window_size := DisplayServer.window_get_size()
	_window_position = Vector2(usable.position) + (Vector2(usable.size) - Vector2(window_size)) * 0.5
	DisplayServer.window_set_position(Vector2i(_window_position.round()))


# =====================================================================
#  点击穿透
# =====================================================================

## 预计算所有动画所有帧的穿透多边形
func _precompute_passthrough_polygons() -> void:
	var frames = sprite.sprite_frames
	if not frames:
		return
	for anim_name in frames.get_animation_names():
		var count = frames.get_frame_count(anim_name)
		var polys: Array = []
		for i in count:
			var tex = frames.get_frame_texture(anim_name, i) as Texture2D
			if tex:
				polys.append(_compute_opaque_polygon(tex))
			else:
				polys.append(PackedVector2Array())
		_frame_polygons[anim_name] = polys


## 按行提取不透明像素的左右边界，生成贴近角色轮廓的穿透多边形。
func _compute_opaque_polygon(tex: Texture2D) -> PackedVector2Array:
	var img = tex.get_image()
	if img == null:
		return PackedVector2Array()

	var w := img.get_width()
	var h := img.get_height()
	var opaque_rows: Array[Vector3] = []

	for y in range(h):
		var left := -1
		var right := -1
		for x in range(w):
			if img.get_pixel(x, y).a > ALPHA_THRESHOLD:
				if left < 0:
					left = x
				right = x
		if left >= 0:
			opaque_rows.append(Vector3(y, left, right))

	if opaque_rows.is_empty():
		return PackedVector2Array()  # 完全透明

	var sampled_rows: Array[Vector3] = []
	for row_index in range(0, opaque_rows.size(), PASSTHROUGH_ROW_STEP):
		sampled_rows.append(opaque_rows[row_index])
	if sampled_rows.back() != opaque_rows.back():
		sampled_rows.append(opaque_rows.back())

	var poly := PackedVector2Array()
	for index in sampled_rows.size():
		var row := sampled_rows[index]
		var row_y := float(row.x)
		if index == 0:
			row_y = maxf(row_y - PASSTHROUGH_MARGIN, 0.0)
		elif index == sampled_rows.size() - 1:
			row_y = minf(row_y + 1.0 + PASSTHROUGH_MARGIN, float(h))
		poly.append(_tex_to_window(maxf(float(row.y) - PASSTHROUGH_MARGIN, 0.0), row_y, w, h))
	for index in range(sampled_rows.size() - 1, -1, -1):
		var row := sampled_rows[index]
		var row_y := float(row.x)
		if index == 0:
			row_y = maxf(row_y - PASSTHROUGH_MARGIN, 0.0)
		elif index == sampled_rows.size() - 1:
			row_y = minf(row_y + 1.0 + PASSTHROUGH_MARGIN, float(h))
		poly.append(_tex_to_window(minf(float(row.z) + 1.0 + PASSTHROUGH_MARGIN, float(w)), row_y, w, h))
	return poly


## 纹理像素坐标 → 窗口坐标
func _tex_to_window(px: float, py: float, tex_w: int, tex_h: int) -> Vector2:
	var center := sprite.position
	var origin_x := center.x - (float(tex_w) * SPRITE_SCALE) / 2.0
	var origin_y := center.y - (float(tex_h) * SPRITE_SCALE) / 2.0
	return Vector2(origin_x + px * SPRITE_SCALE, origin_y + py * SPRITE_SCALE)


## 更新当前帧的穿透多边形到系统窗口
func _update_passthrough() -> void:
	if _dragging or (_context_menu and _context_menu.visible):
		return  # 拖动或菜单显示时保持全窗口可接收事件

	var anim := sprite.animation
	if not _frame_polygons.has(anim):
		# 没有预计算数据 → 空多边形 = 不穿透（全窗口可点击）
		DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
		return

	var polys: Array = _frame_polygons[anim]
	var frame := sprite.frame
	if frame >= 0 and frame < polys.size():
		var poly: PackedVector2Array = polys[frame]
		if _bubble and _bubble.visible:
			poly = _merge_bubble_polygon(poly)
		if _care_feedback and _care_feedback.visible:
			poly = _merge_rect_polygon(poly, _care_feedback.get_local_bounds())
		DisplayServer.window_set_mouse_passthrough(poly)
	else:
		DisplayServer.window_set_mouse_passthrough(PackedVector2Array())


func _merge_bubble_polygon(character_poly: PackedVector2Array) -> PackedVector2Array:
	var local_bounds: Rect2 = _bubble.get_local_bounds()
	var bounds := Rect2(_bubble.position + local_bounds.position, local_bounds.size)
	return _merge_rect_polygon(character_poly, bounds)


func _merge_rect_polygon(base_polygon: PackedVector2Array, bounds: Rect2) -> PackedVector2Array:
	var rect_polygon := PackedVector2Array([
		bounds.position,
		bounds.position + Vector2(0, bounds.size.y),
		bounds.end,
		bounds.position + Vector2(bounds.size.x, 0)
	])
	var merged := Geometry2D.merge_polygons(base_polygon, rect_polygon)
	if merged.size() == 1:
		return merged[0]

	# Windows 会同时按穿透区域裁剪透明窗口；不相交时用凸包保证临时 UI 完整可见。
	var all_points := PackedVector2Array(base_polygon)
	all_points.append_array(rect_polygon)
	return Geometry2D.convex_hull(all_points)


func _on_frame_changed() -> void:
	_update_passthrough()


# =====================================================================
#  动画构建
# =====================================================================

func _build_sprite_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	var dir := DirAccess.open(SPRITES_DIR)
	if dir == null:
		push_warning("找不到精灵目录: " + SPRITES_DIR)
		return frames

	# 收集所有动作文件夹
	var actions: Array = []
	dir.list_dir_begin()
	var n: String = dir.get_next()
	while n != "":
		if dir.current_is_dir() and not n.begins_with("."):
			actions.append(n)
		n = dir.get_next()
	dir.list_dir_end()
	actions.sort()

	# 每个文件夹 → 一个动画
	for action in actions:
		var files: Array = []
		var ad := DirAccess.open(SPRITES_DIR + "/" + action)
		ad.list_dir_begin()
		var f: String = ad.get_next()
		while f != "":
			if not ad.current_is_dir() and f.get_extension().to_lower() == "png":
				files.append(f)
			f = ad.get_next()
		ad.list_dir_end()
		files.sort()
		if files.is_empty():
			continue

		if frames.has_animation(action):
			frames.remove_animation(action)
		frames.add_animation(action)
		frames.set_animation_loop(action, true)
		frames.set_animation_speed(action, DEFAULT_FPS)
		for ff in files:
			var tex := load(SPRITES_DIR + "/" + action + "/" + ff) as Texture2D
			if tex:
				frames.add_frame(action, tex)

	_load_movement_animations(frames)
	return frames


## 读取资源包里的 SpriteFrames，并映射成项目内部的英文动作名。
## 资源包可以继续保留原来的中文动作名和 spritesheet 结构。
func _load_movement_animations(frames: SpriteFrames) -> void:
	var root := DirAccess.open(MOVEMENT_DIR)
	if root == null:
		return

	root.list_dir_begin()
	var direction := root.get_next()
	while direction != "":
		if root.current_is_dir() and not direction.begins_with("."):
			var frames_path := _find_frames_resource(MOVEMENT_DIR + "/" + direction)
			if not frames_path.is_empty():
				var source := load(frames_path) as SpriteFrames
				if source:
					for source_animation in source.get_animation_names():
						if source.get_frame_count(source_animation) > 0:
							if direction == "sleep":
								_load_sleep_animations(frames, source, source_animation)
							else:
								_copy_animation(frames, direction, source, source_animation)
								if direction == SLEEP_IDLE_ANIMATION:
									frames.set_animation_speed(SLEEP_IDLE_ANIMATION, SLEEP_IDLE_FPS)
								elif direction == SLEEP_TURN_ANIMATION:
									frames.set_animation_loop(SLEEP_TURN_ANIMATION, false)
		direction = root.get_next()
	root.list_dir_end()


func _find_frames_resource(path: String) -> String:
	var dir := DirAccess.open(path)
	if dir == null:
		return ""

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var child_path := path + "/" + entry
			if dir.current_is_dir():
				var nested := _find_frames_resource(child_path)
				if not nested.is_empty():
					dir.list_dir_end()
					return nested
			elif entry.ends_with("_frames.tres"):
				dir.list_dir_end()
				return child_path
		entry = dir.get_next()
	dir.list_dir_end()
	return ""


func _copy_animation(target: SpriteFrames, animation_name: String, source: SpriteFrames, source_animation: String) -> void:
	if target.has_animation(animation_name):
		target.remove_animation(animation_name)
	target.add_animation(animation_name)
	target.set_animation_loop(animation_name, source.get_animation_loop(source_animation))
	target.set_animation_speed(animation_name, source.get_animation_speed(source_animation))
	for index in source.get_frame_count(source_animation):
		var texture := source.get_frame_texture(source_animation, index)
		var duration := source.get_frame_duration(source_animation, index)
		if texture:
			target.add_frame(animation_name, texture, duration)


func _load_sleep_animations(target: SpriteFrames, source: SpriteFrames, source_animation: String) -> void:
	var frame_count := source.get_frame_count(source_animation)
	var sleep_start := maxi(frame_count - 4, 0)
	_copy_animation_range(target, SLEEP_ENTER_ANIMATION, source, source_animation, 0, sleep_start + 1, false, source.get_animation_speed(source_animation))
	_copy_animation_range(target, SLEEP_ANIMATION, source, source_animation, sleep_start, frame_count, true, 2.0)


func _copy_animation_range(target: SpriteFrames, animation_name: String, source: SpriteFrames, source_animation: String, start: int, end: int, loop: bool, speed: float) -> void:
	if target.has_animation(animation_name):
		target.remove_animation(animation_name)
	target.add_animation(animation_name)
	target.set_animation_loop(animation_name, loop)
	target.set_animation_speed(animation_name, speed)
	for index in range(start, end):
		var texture := source.get_frame_texture(source_animation, index)
		var duration := source.get_frame_duration(source_animation, index)
		if texture:
			target.add_frame(animation_name, texture, duration)


# =====================================================================
#  状态机
# =====================================================================

func _enter_state(s: int) -> void:
	var previous_state := state
	state = s
	_state_time = 0.0
	if _care_system:
		_care_system.set_sleeping(s == State.SLEEP)
	match s:
		State.IDLE:
			_state_duration = _rng.randf_range(4.0, 8.0)
			_play("idle")
			if previous_state == State.WALK and _wandering_enabled:
				_say_random(3.2)
		State.WALK:
			_state_duration = _rng.randf_range(4.5, 8.5)
			_choose_walk_direction()
			_update_walk_animation()
		State.SLEEP:
			_state_duration = _rng.randf_range(SLEEP_MIN_DURATION, SLEEP_MAX_DURATION)
			_sleep_turn_phase = SleepTurnPhase.NONE
			_sleep_turn_hold_time = 0.0
			_wake_after_sleep_turn = false
			_schedule_next_sleep_turn()
			_schedule_next_speech()
			_hide_bubble()
			_play(SLEEP_ENTER_ANIMATION)
		State.WAKE:
			_state_duration = 0.0
			if sprite.sprite_frames.has_animation(SLEEP_ENTER_ANIMATION):
				sprite.play_backwards(SLEEP_ENTER_ANIMATION)
			else:
				_enter_state(State.IDLE)


func _choose_walk_direction() -> void:
	var directions := [
		Vector2.LEFT,
		Vector2.RIGHT,
		Vector2.UP,
		Vector2.DOWN,
		Vector2(-1, -1),
		Vector2(1, -1),
		Vector2(-1, 1),
		Vector2(1, 1)
	]
	_move_direction = directions[_rng.randi_range(0, directions.size() - 1)].normalized()


func _schedule_next_sleep_turn() -> void:
	_next_sleep_turn_time = _rng.randf_range(SLEEP_TURN_MIN_INTERVAL, SLEEP_TURN_MAX_INTERVAL)


func _update_sleep_turn(delta: float) -> void:
	if _sleep_turn_phase == SleepTurnPhase.HOLD:
		_sleep_turn_hold_time -= delta
		if _sleep_turn_hold_time <= 0.0:
			_sleep_turn_phase = SleepTurnPhase.BACKWARD
			sprite.play_backwards(SLEEP_TURN_ANIMATION)
		return

	if _sleep_turn_phase != SleepTurnPhase.NONE or sprite.animation != SLEEP_IDLE_ANIMATION:
		return

	_next_sleep_turn_time -= delta
	if _next_sleep_turn_time > 0.0:
		return

	_schedule_next_sleep_turn()
	if sprite.sprite_frames.has_animation(SLEEP_TURN_ANIMATION) and _rng.randf() <= SLEEP_TURN_CHANCE:
		_sleep_turn_phase = SleepTurnPhase.FORWARD
		_play(SLEEP_TURN_ANIMATION)


func _update_walk_animation() -> void:
	var animation_name := "walk_right"
	if _move_direction.y < -0.35:
		if _move_direction.x < -0.35:
			animation_name = "walk_up_left"
		elif _move_direction.x > 0.35:
			animation_name = "walk_up_right"
		else:
			animation_name = "walk_up"
	elif _move_direction.y > 0.35:
		if _move_direction.x < -0.35:
			animation_name = "walk_down_left"
		elif _move_direction.x > 0.35:
			animation_name = "walk_down_right"
		else:
			animation_name = "walk_down"
	elif _move_direction.x < 0.0:
		animation_name = "walk_left"

	_play(animation_name)


func _move_window(delta: float) -> void:
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = 0
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var window_size := DisplayServer.window_get_size()
	var min_position := Vector2(usable.position)
	var max_position := Vector2(usable.position + usable.size - window_size)
	_window_position += _move_direction * WALK_SPEED * delta
	var bounced := false

	if _window_position.x <= min_position.x:
		_window_position.x = min_position.x
		if _move_direction.x < 0.0:
			_move_direction.x = abs(_move_direction.x)
			bounced = true
	elif _window_position.x >= max_position.x:
		_window_position.x = max_position.x
		if _move_direction.x > 0.0:
			_move_direction.x = -abs(_move_direction.x)
			bounced = true

	if _window_position.y <= min_position.y:
		_window_position.y = min_position.y
		if _move_direction.y < 0.0:
			_move_direction.y = abs(_move_direction.y)
			bounced = true
	elif _window_position.y >= max_position.y:
		_window_position.y = max_position.y
		if _move_direction.y > 0.0:
			_move_direction.y = -abs(_move_direction.y)
			bounced = true

	DisplayServer.window_set_position(Vector2i(_window_position.round()))
	if bounced:
		_move_direction = _move_direction.normalized()
		_update_walk_animation()


func _play(anim: String) -> void:
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)
	elif sprite.sprite_frames and sprite.sprite_frames.get_animation_count() > 0:
		# 找不到指定动画时退回到第一个可用动画，避免黑屏
		sprite.play(sprite.sprite_frames.get_animation_names()[0])


func _begin_drag_visual() -> void:
	# 拖动不再切换专用姿势，保持原角色外观，仅通过旋转产生跟手感。
	state = State.IDLE
	_state_time = 0.0
	_state_duration = 3.0
	_play("idle")
	if _bubble and _bubble.visible:
		_bubble.clear_message()
		_bubble_time_left = 0.0
		_schedule_next_speech()
	_drag_sway_target = 0.0
	_drag_last_mouse_position = DisplayServer.mouse_get_position()
	sprite.rotation = 0.0
	sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	_position_window_at_drag_anchor()


func _finish_drag_visual() -> void:
	_drag_sway_target = 0.0
	sprite.rotation = 0.0
	sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	_enter_state(State.IDLE)
	_state_duration = 3.0


func _on_animation_finished() -> void:
	if state == State.SLEEP and sprite.animation == SLEEP_ENTER_ANIMATION:
		if sprite.sprite_frames.has_animation(SLEEP_IDLE_ANIMATION):
			_play(SLEEP_IDLE_ANIMATION)
		else:
			_play(SLEEP_ANIMATION)
	elif state == State.SLEEP and sprite.animation == SLEEP_TURN_ANIMATION:
		if _sleep_turn_phase == SleepTurnPhase.FORWARD:
			sprite.frame = sprite.sprite_frames.get_frame_count(SLEEP_TURN_ANIMATION) - 1
			sprite.pause()
			_sleep_turn_phase = SleepTurnPhase.HOLD
			_sleep_turn_hold_time = _rng.randf_range(SLEEP_TURN_MIN_HOLD, SLEEP_TURN_MAX_HOLD)
		elif _sleep_turn_phase == SleepTurnPhase.BACKWARD:
			_sleep_turn_phase = SleepTurnPhase.NONE
			if _wake_after_sleep_turn:
				_enter_state(State.WAKE)
			else:
				_schedule_next_sleep_turn()
				_play(SLEEP_IDLE_ANIMATION)
	elif state == State.WAKE and sprite.animation == SLEEP_ENTER_ANIMATION:
		_enter_state(State.IDLE)


func _update_drag_sway(delta: float) -> void:
	_drag_sway_target = lerpf(_drag_sway_target, 0.0, minf(delta * DRAG_SWAY_DAMPING, 1.0))
	sprite.rotation = lerp_angle(sprite.rotation, _drag_sway_target, minf(delta * DRAG_SWAY_RESPONSE, 1.0))
	_position_window_at_drag_anchor()


func _position_window_at_drag_anchor() -> void:
	var shoulder_offset := (DRAG_CURSOR_ANCHOR_OFFSET * sprite.scale.x).rotated(sprite.rotation)
	var anchor_in_window := sprite.position + shoulder_offset
	var mouse_position := DisplayServer.mouse_get_position()
	var next_position := Vector2i((Vector2(mouse_position) - anchor_in_window).round())
	_window_position = Vector2(next_position)
	DisplayServer.window_set_position(next_position)


# =====================================================================
#  输入
# =====================================================================

func _input(event: InputEvent) -> void:
	# ESC 退出（调试用）
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
		return

	# 菜单打开时把鼠标事件留给 PopupMenu 自己处理。
	if _context_menu and _context_menu.visible and event is InputEventMouse:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_open_context_menu()
		return

	# 左键拖动无边框窗口
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_did_drag = false
			# 拖动时禁用穿透（空多边形=不穿透），确保鼠标移到透明区也能持续拖动
			DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
			_drag_mouse_start = DisplayServer.mouse_get_position()
		else:
			var was_click := not _did_drag
			_dragging = false
			_window_position = Vector2(DisplayServer.window_get_position())
			if was_click:
				_on_pet_clicked()
			else:
				_finish_drag_visual()
			# 松手后恢复穿透
			_update_passthrough()
	elif event is InputEventMouseMotion and _dragging:
		var delta := DisplayServer.mouse_get_position() - _drag_mouse_start
		if delta.length() >= DRAG_THRESHOLD:
			if not _did_drag:
				_did_drag = true
				_begin_drag_visual()
			else:
				var mouse_position := DisplayServer.mouse_get_position()
				var mouse_delta := mouse_position - _drag_last_mouse_position
				_drag_last_mouse_position = mouse_position
				_drag_sway_target = clampf(float(mouse_delta.x) * 0.022, -DRAG_SWAY_MAX, DRAG_SWAY_MAX)
			_position_window_at_drag_anchor()


func _on_pet_clicked() -> void:
	# 点击后给桌宠一段安静的回应，避免立刻被自动闲逛打断。
	if state == State.SLEEP:
		_enter_state(State.WAKE)
		_show_bubble("唔……你叫我呀？", 3.0, "💤")
		return
	if state == State.WAKE:
		return
	if _care_system and _comfort_cooldown <= 0.0:
		_comfort_cooldown = 8.0
		_care_system.perform_action("comfort")
		return
	_enter_state(State.IDLE)
	_state_duration = 5.5
	_say_random()
