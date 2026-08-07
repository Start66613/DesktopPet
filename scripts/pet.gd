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
const DEFAULT_FPS := 8.0
const ALPHA_THRESHOLD := 0.01  # alpha 低于此值视为透明
const WALK_SPEED := 95.0
const DRAG_THRESHOLD := 8.0
const MENU_TALK := 1
const MENU_TOGGLE_WANDER := 2
const MENU_CENTER := 3
const MENU_EXIT := 99
const SpeechBubble := preload("res://scripts/speech_bubble.gd")

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

# ---- 状态机 ----
enum State { IDLE, WALK }
var state: int = State.IDLE
var _state_time := 0.0
var _state_duration := 0.0
var _move_direction := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _wandering_enabled := true
var _window_position := Vector2.ZERO

# ---- 拖动 ----
var _dragging := false
var _did_drag := false
var _drag_mouse_start := Vector2i.ZERO
var _drag_window_start := Vector2i.ZERO

# ---- 互动气泡 ----
var _bubble
var _bubble_layer: CanvasLayer
var _bubble_time_left := 0.0
var _speech_time_left := 0.0
var _bubble_lines := [
	{"text": "喵~ 你来啦！", "emoji": "✨"},
	{"text": "今天也要一起加油！", "emoji": "💪"},
	{"text": "陪我走走嘛～", "emoji": "🎀"},
	{"text": "摸摸我就有好心情！", "emoji": "💕"},
	{"text": "我在这里陪你。", "emoji": ""},
	{"text": "嘿嘿，被你发现了！", "emoji": "😺"}
]
var _cjk_font: Font
var _emoji_font: Font

# ---- 右键菜单 ----
var _context_menu: PopupMenu

# ---- 点击穿透 ----
# anim_name -> Array[PackedVector2Array]，每帧对应一个包围盒多边形
var _frame_polygons: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	_window_position = Vector2(DisplayServer.window_get_position())

	# 让主视口背景真正透明（仅靠项目设置不够）
	get_viewport().transparent_bg = true

	# 扫描文件夹构建动画库
	sprite.sprite_frames = _build_sprite_frames()
	sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = true
	sprite.position = Vector2(get_viewport().get_visible_rect().size) * 0.5
	_create_bubble()
	_create_context_menu()

	# 预计算每帧的点击穿透多边形
	_precompute_passthrough_polygons()

	# 帧切换时实时更新穿透区域
	sprite.frame_changed.connect(_on_frame_changed)

	_enter_state(state)
	# 设置初始帧的穿透多边形
	_update_passthrough()
	_schedule_next_speech()
	call_deferred("_show_bubble", "你好呀，我会陪着你～ ✨", 4.0)


func _process(delta: float) -> void:
	_speech_time_left -= delta
	if _bubble_time_left > 0.0:
		_bubble_time_left -= delta
		if _bubble_time_left <= 0.0:
			_bubble.clear_message()
			_update_passthrough()
	elif _speech_time_left <= 0.0:
		_say_random()

	if _dragging or (_context_menu and _context_menu.visible):
		return
	if not _wandering_enabled:
		return

	_state_time += delta
	if state == State.IDLE:
		if _state_time >= _state_duration:
			_enter_state(State.WALK)
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
	_bubble.position = Vector2(45, 8)
	_bubble.z_index = 100
	_cjk_font = _load_system_font("C:/Windows/Fonts/simhei.ttf")
	_emoji_font = _load_system_font("C:/Windows/Fonts/seguiemj.ttf")
	_bubble.configure_fonts(_cjk_font, _emoji_font)
	_bubble_layer.add_child(_bubble)


func _load_system_font(path: String) -> Font:
	if not FileAccess.file_exists(path):
		return ThemeDB.fallback_font
	var font := FontFile.new()
	font.data = FileAccess.get_file_as_bytes(path)
	return font


func _show_bubble(message: String, duration := 2.8, emoji := "") -> void:
	_bubble.set_message(message, emoji)
	_bubble_time_left = duration
	_update_passthrough()
	_schedule_next_speech()


func _say_random(duration := 3.0) -> void:
	var line: Dictionary = _bubble_lines[_rng.randi_range(0, _bubble_lines.size() - 1)]
	_show_bubble(line["text"], duration, line["emoji"])


func _schedule_next_speech() -> void:
	_speech_time_left = _rng.randf_range(14.0, 28.0)


func _create_context_menu() -> void:
	_context_menu = PopupMenu.new()
	_context_menu.name = "PetContextMenu"
	_context_menu.min_size = Vector2i(190, 0)
	_context_menu.add_item("和她说说话", MENU_TALK)
	_context_menu.add_check_item("自动散步", MENU_TOGGLE_WANDER)
	_context_menu.set_item_checked(_context_menu.get_item_index(MENU_TOGGLE_WANDER), true)
	_context_menu.add_item("回到屏幕中央", MENU_CENTER)
	_context_menu.add_separator()
	_context_menu.add_item("退出桌宠", MENU_EXIT)
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	_context_menu.popup_hide.connect(_on_context_menu_closed)
	add_child(_context_menu)


func _open_context_menu() -> void:
	_dragging = false
	_enter_state(State.IDLE)
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
	_context_menu.position = Vector2i(get_viewport().get_mouse_position())
	_context_menu.popup()


func _on_context_menu_id_pressed(id: int) -> void:
	match id:
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


## 从纹理中提取不透明区域的矩形包围盒
## 返回窗口坐标系下的四边形多边形
func _compute_opaque_polygon(tex: Texture2D) -> PackedVector2Array:
	var img = tex.get_image()
	if img == null:
		return PackedVector2Array()

	var w := img.get_width()
	var h := img.get_height()

	var min_x := w
	var max_x := -1
	var min_y := h
	var max_y := -1

	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > ALPHA_THRESHOLD:
				if x < min_x:
					min_x = x
				if x > max_x:
					max_x = x
				if y < min_y:
					min_y = y
				if y > max_y:
					max_y = y

	if max_x < 0:
		return PackedVector2Array()  # 完全透明

	# 扩展 2 像素，给缩放/抖动留点余量
	min_x = maxi(min_x - 2, 0)
	min_y = maxi(min_y - 2, 0)
	max_x = mini(max_x + 2, w - 1)
	max_y = mini(max_y + 2, h - 1)

	var poly := PackedVector2Array()
	poly.append(_tex_to_window(float(min_x), float(min_y), w, h))
	poly.append(_tex_to_window(float(max_x + 1), float(min_y), w, h))
	poly.append(_tex_to_window(float(max_x + 1), float(max_y + 1), w, h))
	poly.append(_tex_to_window(float(min_x), float(max_y + 1), w, h))
	return poly


## 纹理像素坐标 → 窗口坐标
func _tex_to_window(px: float, py: float, tex_w: int, tex_h: int) -> Vector2:
	var vp_size := get_viewport().get_visible_rect().size
	var center := vp_size * 0.5
	var origin_x := center.x - (float(tex_w) * SPRITE_SCALE) / 2.0
	var origin_y := center.y - (float(tex_h) * SPRITE_SCALE) / 2.0
	return Vector2(origin_x + px * SPRITE_SCALE, origin_y + py * SPRITE_SCALE)


## 更新当前帧的穿透多边形到系统窗口
func _update_passthrough() -> void:
	if _bubble and _bubble.visible:
		DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
		return
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
		DisplayServer.window_set_mouse_passthrough(poly)
	else:
		DisplayServer.window_set_mouse_passthrough(PackedVector2Array())


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
							_copy_animation(frames, direction, source, source_animation)
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


# =====================================================================
#  状态机
# =====================================================================

func _enter_state(s: int) -> void:
	var previous_state := state
	state = s
	_state_time = 0.0
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
			_drag_window_start = DisplayServer.window_get_position()
		else:
			var was_click := not _did_drag
			_dragging = false
			_window_position = Vector2(DisplayServer.window_get_position())
			# 松手后恢复穿透
			_update_passthrough()
			if was_click:
				_on_pet_clicked()
	elif event is InputEventMouseMotion and _dragging:
		var delta := DisplayServer.mouse_get_position() - _drag_mouse_start
		if delta.length() >= DRAG_THRESHOLD:
			_did_drag = true
		var dragged_position := _drag_window_start + delta
		_window_position = Vector2(dragged_position)
		DisplayServer.window_set_position(dragged_position)


func _on_pet_clicked() -> void:
	# 点击后给桌宠一段安静的回应，避免立刻被自动闲逛打断。
	_enter_state(State.IDLE)
	_state_duration = 5.5
	_say_random()
