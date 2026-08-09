extends Window
class_name PetDogCompanion

signal dog_clicked
signal home_requested
signal care_message(message: String, emoji: String)

const WINDOW_SIZE := Vector2i(128, 128)
const SPRITE_SCALE := 2.0
const WALK_SPEED := 48.0
const PLAY_WALK_SPEED := 76.0
const DRAG_THRESHOLD := 6.0
const ALPHA_THRESHOLD := 0.04
const IDLE_FRAMES_PATH := "res://assets/dog/source/idle/1786211809628-5htktvepw1s/1786211809628-5htktvepw1s_frames.tres"
const WALK_FRAMES_PATH := "res://assets/dog/source/walk_8dir/sprite-animations/sprite-animations_frames.tres"

const WALK_ANIMATION_MAP := {
	"walk_right": "1786212275164-hmmdbhhvsb4",
	"walk_left": "1786212452832-lk00vpcg9eb",
	"walk_down": "1786212524262-7beqpqrhhq9",
	"walk_down_left": "1786212560196-zqkw5xxdmb",
	"walk_down_right": "1786244060394-3vxjedl7sj",
	"walk_up_left": "1786244074452-igpnqpivex",
	"walk_up": "1786244089872-e75ae95cpq",
	"walk_up_right": "1786244156078-gvvyus8nph"
}

enum State { IDLE, WALK, REST }

var _sprite: AnimatedSprite2D
var _frames: SpriteFrames
var _state: int = State.IDLE
var _state_time := 0.0
var _state_duration := 0.0
var _move_direction := Vector2.ZERO
var _window_position := Vector2.ZERO
var _initial_position := Vector2i(360, 620)
var _screen_index := 0
var _rng := RandomNumberGenerator.new()
var _playful_until := 0.0
var _hidden_for_interaction := false
var _frame_polygons: Dictionary = {}
var _dragging := false
var _did_drag := false
var _drag_mouse_start := Vector2i.ZERO
var _drag_window_start := Vector2i.ZERO
var _click_tween: Tween


func _init() -> void:
	visible = false
	title = "小雪球"
	size = WINDOW_SIZE
	min_size = WINDOW_SIZE
	borderless = true
	transparent_bg = true
	unresizable = true
	always_on_top = true
	force_native = true


func configure(initial_position: Vector2i, screen_index: int) -> void:
	_initial_position = initial_position
	_screen_index = maxi(screen_index, 0)


func _ready() -> void:
	_rng.randomize()
	_frames = _build_frames()
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "DogSprite"
	_sprite.sprite_frames = _frames
	_sprite.position = Vector2(WINDOW_SIZE) * 0.5 + Vector2(0.0, 6.0)
	_sprite.scale = Vector2.ONE * SPRITE_SCALE
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.centered = true
	add_child(_sprite)
	_sprite.frame_changed.connect(_update_passthrough)
	_precompute_passthrough()
	_window_position = Vector2(_clamp_position(_initial_position))
	position = Vector2i(_window_position.round())
	_enter_state(State.IDLE)
	call_deferred("_show_on_desktop")


func _show_on_desktop() -> void:
	mode = Window.MODE_WINDOWED
	show()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true, get_window_id())
	transparent_bg = true
	_update_passthrough()


func _process(delta: float) -> void:
	if _hidden_for_interaction or not visible or _dragging:
		return
	_state_time += delta
	_playful_until = maxf(_playful_until - delta, 0.0)
	match _state:
		State.IDLE, State.REST:
			if _state_time >= _state_duration:
				_enter_state(State.WALK if _state == State.IDLE else State.IDLE)
		State.WALK:
			_move_window(delta)
			if _state_time >= _state_duration:
				_enter_state(State.IDLE)


func get_sprite_frames() -> SpriteFrames:
	return _frames


func hide_for_interaction() -> void:
	_hidden_for_interaction = true
	hide()


func restore_after_interaction(screen_position: Vector2i, screen_index: int) -> void:
	_hidden_for_interaction = false
	_screen_index = maxi(screen_index, 0)
	_window_position = Vector2(_clamp_position(screen_position))
	position = Vector2i(_window_position.round())
	show()
	_enter_state(State.IDLE)
	call_deferred("_update_passthrough")


func perform_care(action: String) -> void:
	match action:
		"feed":
			_enter_state(State.IDLE)
			_state_duration = 5.5
			care_message.emit("小雪球吃得好香，尾巴都摇起来啦 (^_^)", "🍖")
		"drink":
			_enter_state(State.IDLE)
			_state_duration = 4.5
			care_message.emit("咕嘟咕嘟，喝完水精神多啦 (ᵔᴥᵔ)", "💧")
		"play":
			_playful_until = 8.0
			_enter_state(State.WALK)
			_state_duration = 8.0
			care_message.emit("球球飞出去啦，小雪球快追！ (^o^)", "🎾")
		"rest":
			_enter_state(State.REST)
			_state_duration = 8.0
			care_message.emit("小雪球在软软的窝里团成一团啦 (－ω－) zzZ", "💤")


func _enter_state(next_state: int) -> void:
	_state = next_state
	_state_time = 0.0
	match _state:
		State.IDLE:
			_state_duration = _rng.randf_range(3.5, 7.0)
			_play("idle")
		State.WALK:
			_state_duration = _rng.randf_range(3.0, 6.0)
			_choose_walk_direction()
			_update_walk_animation()
		State.REST:
			_state_duration = 8.0
			_play("idle")


func _choose_walk_direction() -> void:
	var directions := [
		Vector2.LEFT,
		Vector2.RIGHT,
		Vector2.UP,
		Vector2.DOWN,
		Vector2(-1.0, -1.0),
		Vector2(1.0, -1.0),
		Vector2(-1.0, 1.0),
		Vector2(1.0, 1.0)
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
	var usable := DisplayServer.screen_get_usable_rect(_screen_index)
	var min_position := Vector2(usable.position)
	var max_position := Vector2(usable.end - WINDOW_SIZE)
	var speed := PLAY_WALK_SPEED if _playful_until > 0.0 else WALK_SPEED
	_window_position += _move_direction * speed * delta
	var bounced := false
	if _window_position.x <= min_position.x or _window_position.x >= max_position.x:
		_window_position.x = clampf(_window_position.x, min_position.x, max_position.x)
		_move_direction.x *= -1.0
		bounced = true
	if _window_position.y <= min_position.y or _window_position.y >= max_position.y:
		_window_position.y = clampf(_window_position.y, min_position.y, max_position.y)
		_move_direction.y *= -1.0
		bounced = true
	position = Vector2i(_window_position.round())
	if bounced:
		_move_direction = _move_direction.normalized()
		_update_walk_animation()


func _input(event: InputEvent) -> void:
	if _hidden_for_interaction:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		home_requested.emit()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_did_drag = false
			_drag_mouse_start = DisplayServer.mouse_get_position()
			_drag_window_start = position
			DisplayServer.window_set_mouse_passthrough(PackedVector2Array(), get_window_id())
		else:
			var was_click := not _did_drag
			_dragging = false
			_window_position = Vector2(position)
			_screen_index = maxi(DisplayServer.window_get_current_screen(get_window_id()), 0)
			if was_click:
				_play_click_motion()
				dog_clicked.emit()
			_update_passthrough()
	elif event is InputEventMouseMotion and _dragging:
		var mouse_delta := DisplayServer.mouse_get_position() - _drag_mouse_start
		if mouse_delta.length() >= DRAG_THRESHOLD:
			_did_drag = true
			position = _clamp_position(_drag_window_start + mouse_delta)


func _play_click_motion() -> void:
	if _click_tween and _click_tween.is_valid():
		_click_tween.kill()
	var resting_position := Vector2(WINDOW_SIZE) * 0.5 + Vector2(0.0, 6.0)
	_click_tween = create_tween()
	_click_tween.tween_property(_sprite, "position", resting_position + Vector2(0.0, -8.0), 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_click_tween.tween_property(_sprite, "position", resting_position, 0.16).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_click_tween.finished.connect(_update_passthrough)


func _build_frames() -> SpriteFrames:
	var target := SpriteFrames.new()
	if target.has_animation("default"):
		target.remove_animation("default")
	var idle_source := load(IDLE_FRAMES_PATH) as SpriteFrames
	if idle_source:
		var idle_names := idle_source.get_animation_names()
		if not idle_names.is_empty():
			_copy_animation(target, "idle", idle_source, idle_names[0])
	var walk_source := load(WALK_FRAMES_PATH) as SpriteFrames
	if walk_source:
		for target_name in WALK_ANIMATION_MAP:
			var source_name: String = WALK_ANIMATION_MAP[target_name]
			if walk_source.has_animation(source_name):
				_copy_animation(target, target_name, walk_source, source_name)
	return target


func _copy_animation(target: SpriteFrames, target_name: String, source: SpriteFrames, source_name: String) -> void:
	target.add_animation(target_name)
	target.set_animation_loop(target_name, true)
	target.set_animation_speed(target_name, source.get_animation_speed(source_name))
	for frame_index in source.get_frame_count(source_name):
		var texture := source.get_frame_texture(source_name, frame_index)
		var duration := source.get_frame_duration(source_name, frame_index)
		if texture:
			target.add_frame(target_name, texture, duration)


func _play(animation_name: String) -> void:
	if _frames and _frames.has_animation(animation_name):
		_sprite.play(animation_name)


func _precompute_passthrough() -> void:
	_frame_polygons.clear()
	for animation_name in _frames.get_animation_names():
		var polygons: Array[PackedVector2Array] = []
		for frame_index in _frames.get_frame_count(animation_name):
			polygons.append(_compute_opaque_polygon(_frames.get_frame_texture(animation_name, frame_index)))
		_frame_polygons[animation_name] = polygons


func _compute_opaque_polygon(texture: Texture2D) -> PackedVector2Array:
	if not texture:
		return PackedVector2Array()
	var image := texture.get_image()
	if image == null or image.is_empty():
		return PackedVector2Array()
	var rows: Array[Vector3] = []
	for y in image.get_height():
		var left := -1
		var right := -1
		for x in image.get_width():
			if image.get_pixel(x, y).a >= ALPHA_THRESHOLD:
				if left < 0:
					left = x
				right = x
		if left >= 0:
			rows.append(Vector3(y, left, right))
	if rows.is_empty():
		return PackedVector2Array()
	var polygon := PackedVector2Array()
	for row in rows:
		polygon.append(_texture_to_window(row.y, row.x, image.get_width(), image.get_height()))
	for index in range(rows.size() - 1, -1, -1):
		var row := rows[index]
		polygon.append(_texture_to_window(row.z + 1.0, row.x, image.get_width(), image.get_height()))
	return polygon


func _texture_to_window(x: float, y: float, texture_width: int, texture_height: int) -> Vector2:
	var top_left := _sprite.position - Vector2(texture_width, texture_height) * SPRITE_SCALE * 0.5
	return top_left + Vector2(x, y) * SPRITE_SCALE


func _update_passthrough() -> void:
	if not is_instance_valid(_sprite) or _dragging or not visible:
		return
	var animation_name := String(_sprite.animation)
	var polygons: Array = _frame_polygons.get(animation_name, [])
	if _sprite.frame >= 0 and _sprite.frame < polygons.size():
		var polygon: PackedVector2Array = polygons[_sprite.frame]
		if not polygon.is_empty():
			DisplayServer.window_set_mouse_passthrough(polygon, get_window_id())
			return
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array(), get_window_id())


func _clamp_position(candidate: Vector2i) -> Vector2i:
	var usable := DisplayServer.screen_get_usable_rect(_screen_index)
	return Vector2i(
		clampi(candidate.x, usable.position.x, usable.end.x - WINDOW_SIZE.x),
		clampi(candidate.y, usable.position.y, usable.end.y - WINDOW_SIZE.y)
	)
