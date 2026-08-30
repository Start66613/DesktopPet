extends Control
class_name PetImmersiveMusicView

signal exit_requested
signal previous_requested
signal play_pause_requested
signal next_requested
signal mode_requested
signal seek_requested(ratio: float)

const UI_DIR := "res://assets/music/runtime/ui"
const ProgressControl := preload("res://scripts/music_progress_control.gd")
const BASE_SIZE := Vector2(1678, 951)
const PREVIOUS_REGION := Rect2(423, 747, 135, 137)
const PLAY_REGION := Rect2(592, 738, 195, 151)
const PAUSE_REGION := Rect2(817, 746, 143, 139)
const NEXT_REGION := Rect2(999, 748, 139, 137)
const SHUFFLE_REGION := Rect2(1170, 774, 88, 88)
const REPEAT_REGION := Rect2(1292, 773, 91, 89)
const PREVIOUS_RECT := Rect2(650, 783, 86, 86)
const PLAY_PAUSE_RECT := Rect2(780, 774, 112, 96)
const NEXT_RECT := Rect2(936, 783, 86, 86)
const MODE_RECT := Rect2(1080, 793, 68, 68)
const MINIMIZE_RECT := Rect2(1452, 42, 112, 112)
const EXIT_RECT := Rect2(1558, 40, 112, 116)

var _font: Font
var _background: ColorRect
var _skin: TextureRect
var _content_wash: Panel
var _column_divider: ColorRect
var _cover_frame: Panel
var _cover: TextureRect
var _cover_decorations: Array[TextureRect] = []
var _title_label: Label
var _artist_label: Label
var _album_label: Label
var _source_label: Label
var _lyric_labels: Array[Label] = []
var _lyrics_source_label: Label
var _progress: PetMusicProgressControl
var _elapsed_label: Label
var _duration_label: Label
var _previous_button: TextureButton
var _play_pause_button: TextureButton
var _next_button: TextureButton
var _mode_button: TextureButton
var _mode_badge: Label
var _minimize_button: TextureButton
var _exit_button: TextureButton
var _companion_panel: Panel
var _companion_title: Label
var _companion_note: Label
var _companion_emoji: Label
var _companion_sprite: AnimatedSprite2D
var _play_texture: AtlasTexture
var _pause_texture: AtlasTexture
var _shuffle_texture: AtlasTexture
var _repeat_texture: AtlasTexture
var _note_tween: Tween
var _lyric_tween: Tween
var _cover_tween: Tween
var _last_lyric_index := -1
var _lyric_reaction_counter := 0
var _last_track_id := ""
var _last_playing := false
var _native_seek_dragging := false
var _session: Dictionary = {"found": false}


func configure(font: Font) -> void:
	_font = font


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	_build_ui()
	_companion_panel.visible = false
	_companion_title.visible = false
	_companion_note.visible = false
	_companion_emoji.visible = false
	_companion_sprite.visible = false
	resized.connect(_layout)
	_layout()


func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode in [KEY_ESCAPE, KEY_F11]:
		exit_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_SPACE:
		play_pause_requested.emit()
		get_viewport().set_input_as_handled()


func handle_pointer_event(event: InputEvent, pointer_position: Vector2) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _button_hit(_previous_button, pointer_position):
				previous_requested.emit()
				return true
			if _button_hit(_play_pause_button, pointer_position):
				play_pause_requested.emit()
				return true
			if _button_hit(_next_button, pointer_position):
				next_requested.emit()
				return true
			if _button_hit(_mode_button, pointer_position):
				mode_requested.emit()
				return true
			if _progress.get_global_rect().has_point(pointer_position):
				_native_seek_dragging = true
				_emit_native_seek(pointer_position)
				return true
		elif _native_seek_dragging:
			_native_seek_dragging = false
			_emit_native_seek(pointer_position)
			return true
	elif event is InputEventMouseMotion and _native_seek_dragging:
		_emit_native_seek(pointer_position)
		return true
	return false


func _button_hit(button: BaseButton, pointer_position: Vector2) -> bool:
	return is_instance_valid(button) and not button.disabled and button.get_global_rect().has_point(pointer_position)


func _emit_native_seek(pointer_position: Vector2) -> void:
	var rect := _progress.get_global_rect()
	if rect.size.x <= 0.0:
		return
	seek_requested.emit(clampf((pointer_position.x - rect.position.x) / rect.size.x, 0.0, 1.0))


func set_cover(texture: Texture2D) -> void:
	_cover.texture = texture
	if texture:
		_play_cover_motion()


func set_session(info: Dictionary, mode_name: String) -> void:
	var previous_track := _last_track_id
	var was_playing := _last_playing
	_session = info.duplicate(true)
	var found := bool(info.get("found", false))
	var track_id := String(info.get("track_id", ""))
	_title_label.text = String(info.get("title", "等待播放器")) if found else "等待播放器"
	_artist_label.text = String(info.get("artist", "打开 QQ音乐 或 网易云音乐")) if found else "打开 QQ音乐 或 网易云音乐"
	_album_label.text = String(info.get("album", "")) if found else "检测到播放后会自动同步"
	_source_label.text = "%s  ·  %s" % [
		String(info.get("source_label", "本地播放器")) if found else "音乐中心",
		"正在播放" if String(info.get("playback_status", "")) == "playing" else ("已暂停" if found else "等待连接")
	]
	_companion_title.text = "陪你听歌 · %s" % ("正在播放" if String(info.get("playback_status", "")) == "playing" else ("暂停中" if found else "等待音乐"))
	if not found and _companion_note.text.strip_edges().is_empty():
		_companion_note.text = "放一首歌吧，我会认真陪你听。"
	var playing := String(info.get("playback_status", "")) == "playing"
	_last_track_id = track_id
	_last_playing = playing
	_play_pause_button.texture_normal = _pause_texture if playing else _play_texture
	_play_pause_button.tooltip_text = "暂停" if playing else "播放"
	_previous_button.disabled = not found or not bool(info.get("can_previous", false))
	_next_button.disabled = not found or not bool(info.get("can_next", false))
	_play_pause_button.disabled = not found
	_mode_button.disabled = not found
	_mode_button.texture_normal = _shuffle_texture if mode_name == "shuffle" else _repeat_texture
	_mode_badge.text = _mode_badge_text(mode_name)
	_mode_button.tooltip_text = "播放顺序：" + _mode_display_name(mode_name)
	if found and playing and not track_id.is_empty() and track_id != previous_track:
		show_companion_note("《%s》开始啦，我陪你一起听。" % String(info.get("title", "这首歌")).left(18), "🎧")
	elif found and playing and not was_playing:
		show_companion_note("音乐继续啦，我也回来陪你听。", "♪")
	elif found and not playing and was_playing:
		show_companion_note("暂停一下也好，我就在这里等你。", "♡")


func set_progress(position_ms: int, duration_ms: int) -> void:
	if not _progress.is_dragging():
		_progress.value = clampf(float(position_ms) / float(duration_ms), 0.0, 1.0) if duration_ms > 0 else 0.0
	_elapsed_label.text = _format_time(position_ms)
	_duration_label.text = _format_time(duration_ms)
	_progress.interactive = duration_ms > 0


func set_lyrics(lines: Array[Dictionary], current_index: int, source: String) -> void:
	if lines.is_empty() or current_index < 0:
		_show_lyric_message("歌词会在播放后出现")
		return
	for row in _lyric_labels.size():
		var line_index := current_index + row - 2
		_lyric_labels[row].text = String(lines[line_index].get("text", "")) if line_index >= 0 and line_index < lines.size() else ""
	_lyrics_source_label.text = source
	if current_index != _last_lyric_index:
		if _last_lyric_index >= 0:
			_lyric_reaction_counter += 1
		_animate_lyrics(1.0 if _last_lyric_index < 0 or current_index > _last_lyric_index else -1.0)
		_last_lyric_index = current_index
		if _lyric_reaction_counter >= 5:
			_lyric_reaction_counter = 0
			var current_line := String(lines[current_index].get("text", "")).strip_edges()
			if not current_line.is_empty():
				show_companion_note("刚才这句我记住了：“%s”" % current_line.left(20), "🎵")


func show_lyric_message(message: String) -> void:
	_show_lyric_message(message)


func show_companion_note(text: String, emoji: String) -> void:
	_companion_note.text = text
	_companion_emoji.text = emoji if not emoji.is_empty() else "♪"
	if _note_tween and _note_tween.is_valid():
		_note_tween.kill()
	_companion_panel.modulate.a = 0.72
	_companion_note.modulate.a = 0.0
	_companion_emoji.modulate.a = 0.0
	_companion_note.position.y += 8.0
	_companion_emoji.position.y += 8.0
	_note_tween = create_tween()
	_note_tween.set_parallel(true)
	_note_tween.tween_property(_companion_panel, "modulate:a", 1.0, 0.28)
	_note_tween.tween_property(_companion_note, "modulate:a", 1.0, 0.24)
	_note_tween.tween_property(_companion_emoji, "modulate:a", 1.0, 0.24)
	_note_tween.tween_property(_companion_note, "position:y", _companion_note.position.y - 8.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_note_tween.tween_property(_companion_emoji, "position:y", _companion_emoji.position.y - 8.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_background = ColorRect.new()
	_background.color = Color("f8ece8")
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	_skin = TextureRect.new()
	_skin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_skin.texture = load(UI_DIR + "/player_panel_clean.png") as Texture2D
	_skin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_skin.stretch_mode = TextureRect.STRETCH_SCALE
	_skin.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_skin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_skin)

	_content_wash = Panel.new()
	_content_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wash_style := StyleBoxFlat.new()
	wash_style.bg_color = Color(1.0, 0.975, 0.96, 0.9)
	wash_style.border_color = Color(0.88, 0.68, 0.7, 0.55)
	wash_style.set_border_width_all(2)
	wash_style.set_corner_radius_all(20)
	_content_wash.add_theme_stylebox_override("panel", wash_style)
	add_child(_content_wash)

	_column_divider = ColorRect.new()
	_column_divider.color = Color(0.86, 0.65, 0.68, 0.32)
	_column_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column_divider)

	_cover_frame = Panel.new()
	_cover_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cover_style := StyleBoxFlat.new()
	cover_style.bg_color = Color("fff9f5")
	cover_style.border_color = Color("e7c2c0")
	cover_style.set_border_width_all(3)
	cover_style.set_corner_radius_all(14)
	_cover_frame.add_theme_stylebox_override("panel", cover_style)
	add_child(_cover_frame)

	_cover = TextureRect.new()
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cover.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.material = _make_cover_material(Vector2(344, 340), 20.0)
	_cover_frame.add_child(_cover)
	_add_cover_decoration("rose.png")
	_add_cover_decoration("rose.png")
	_add_cover_decoration("bow_large.png")

	_title_label = _make_label("等待播放器", 38, Color("6f4955"), HORIZONTAL_ALIGNMENT_LEFT)
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_title_label)
	_artist_label = _make_label("打开 QQ音乐 或 网易云音乐", 25, Color("9f6874"), HORIZONTAL_ALIGNMENT_LEFT)
	_artist_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_artist_label)
	_album_label = _make_label("检测到播放后会自动同步", 20, Color("ad858b"), HORIZONTAL_ALIGNMENT_LEFT)
	_album_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_album_label)
	_source_label = _make_label("音乐中心", 20, Color("a65f70"), HORIZONTAL_ALIGNMENT_LEFT)
	add_child(_source_label)

	for row in 5:
		var size_px := 22 if row != 2 else 34
		var color := Color("c3a3a8") if row in [0, 4] else (Color("9f7b83") if row in [1, 3] else Color("714a56"))
		var lyric := _make_label("", size_px, color, HORIZONTAL_ALIGNMENT_CENTER)
		lyric.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_lyric_labels.append(lyric)
		add_child(lyric)
	_lyrics_source_label = _make_label("", 13, Color("b18c93"), HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_lyrics_source_label)

	_progress = ProgressControl.new()
	_progress.seek_requested.connect(func(ratio: float) -> void: seek_requested.emit(ratio))
	add_child(_progress)
	_elapsed_label = _make_label("0:00", 15, Color("a77a82"), HORIZONTAL_ALIGNMENT_LEFT)
	_duration_label = _make_label("0:00", 15, Color("a77a82"), HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_elapsed_label)
	add_child(_duration_label)

	_previous_button = _make_atlas_button(PREVIOUS_REGION, "上一首")
	_previous_button.pressed.connect(func() -> void: previous_requested.emit())
	_play_texture = _make_atlas_texture(PLAY_REGION)
	_pause_texture = _make_atlas_texture(PAUSE_REGION)
	_play_pause_button = _make_atlas_button(PLAY_REGION, "播放")
	_play_pause_button.pressed.connect(func() -> void: play_pause_requested.emit())
	_next_button = _make_atlas_button(NEXT_REGION, "下一首")
	_next_button.pressed.connect(func() -> void: next_requested.emit())
	_shuffle_texture = _make_atlas_texture(SHUFFLE_REGION)
	_repeat_texture = _make_atlas_texture(REPEAT_REGION)
	_mode_button = _make_atlas_button(REPEAT_REGION, "播放顺序")
	_mode_button.pressed.connect(func() -> void: mode_requested.emit())
	add_child(_previous_button)
	add_child(_play_pause_button)
	add_child(_next_button)
	add_child(_mode_button)
	_mode_badge = _make_label(">", 21, Color("6f9478"), HORIZONTAL_ALIGNMENT_CENTER)
	_mode_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode_button.add_child(_mode_badge)

	_minimize_button = _make_atlas_button(MINIMIZE_RECT, "返回窗口")
	_minimize_button.pressed.connect(func() -> void: exit_requested.emit())
	add_child(_minimize_button)
	_exit_button = _make_atlas_button(EXIT_RECT, "退出全屏（Esc / F11）")
	_exit_button.pressed.connect(func() -> void: exit_requested.emit())
	add_child(_exit_button)

	_companion_panel = Panel.new()
	_companion_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var companion_style := StyleBoxFlat.new()
	companion_style.bg_color = Color(1.0, 0.92, 0.92, 0.82)
	companion_style.border_color = Color(0.86, 0.57, 0.63, 0.75)
	companion_style.set_border_width_all(2)
	companion_style.set_corner_radius_all(18)
	companion_style.shadow_color = Color(0.54, 0.29, 0.34, 0.12)
	companion_style.shadow_size = 9
	_companion_panel.add_theme_stylebox_override("panel", companion_style)
	add_child(_companion_panel)

	_companion_title = _make_label("陪你听歌 · 等待音乐", 18, Color("9d5f6e"), HORIZONTAL_ALIGNMENT_LEFT)
	add_child(_companion_title)
	_companion_emoji = _make_label("♪", 28, Color("db8294"), HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_companion_emoji)
	_companion_note = _make_label("放一首歌吧，我会认真陪你听。", 19, Color("754a55"), HORIZONTAL_ALIGNMENT_LEFT)
	_companion_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_companion_note)

	_companion_sprite = AnimatedSprite2D.new()
	_companion_sprite.sprite_frames = load("res://assets/runtime/pet_sprite_frames.tres") as SpriteFrames
	if _companion_sprite.sprite_frames and not _companion_sprite.sprite_frames.get_animation_names().is_empty():
		var animation: StringName = &"music" if _companion_sprite.sprite_frames.has_animation(&"music") else _companion_sprite.sprite_frames.get_animation_names()[0]
		_companion_sprite.play(animation)
	_companion_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_companion_sprite)


func has_visible_companion() -> bool:
	return is_instance_valid(_companion_panel) and _companion_panel.visible \
		and is_instance_valid(_companion_note) and _companion_note.visible \
		and not _companion_note.text.strip_edges().is_empty()


func get_companion_note_text() -> String:
	return _companion_note.text if is_instance_valid(_companion_note) else ""


func _layout() -> void:
	if not is_inside_tree() or not is_instance_valid(_cover_frame):
		return
	_set_control_rect(_content_wash, Rect2(72, 145, 1534, 745))
	_set_control_rect(_column_divider, Rect2(600, 205, 2, 475))

	var cover_frame_rect := _scaled_rect(Rect2(155, 225, 390, 390))
	_cover_frame.position = cover_frame_rect.position
	_cover_frame.size = cover_frame_rect.size
	var cover_inset := _scaled_vector(Vector2(4, 4))
	_cover.position = cover_inset
	_cover.size = cover_frame_rect.size - cover_inset * 2.0
	_cover.pivot_offset = _cover.size * 0.5
	if _cover.material:
		_cover.material.set_shader_parameter("rect_size", _cover.size)
		_cover.material.set_shader_parameter("corner_radius", 18.0 * minf(size.x / BASE_SIZE.x, size.y / BASE_SIZE.y))

	_set_control_rect(_cover_decorations[0], Rect2(128, 556, 123, 96))
	_set_control_rect(_cover_decorations[1], Rect2(449, 556, 123, 96))
	_set_control_rect(_cover_decorations[2], Rect2(242, 520, 217, 168))
	_set_control_rect(_source_label, Rect2(650, 165, 805, 32))
	_set_control_rect(_title_label, Rect2(650, 198, 805, 54))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_set_control_rect(_artist_label, Rect2(650, 248, 805, 34))
	_artist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_set_control_rect(_album_label, Rect2(650, 278, 805, 28))
	_album_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	for row in _lyric_labels.size():
		var label := _lyric_labels[row]
		_set_control_rect(label, Rect2(645, 330 + row * 58, 810, 52))
		label.pivot_offset = label.size * 0.5
	_set_control_rect(_lyrics_source_label, Rect2(1160, 630, 295, 24))

	_set_control_rect(_companion_panel, Rect2(650, 555, 805, 124))
	_set_control_rect(_companion_title, Rect2(700, 570, 520, 28))
	_set_control_rect(_companion_emoji, Rect2(686, 608, 44, 40))
	_set_control_rect(_companion_note, Rect2(736, 602, 520, 52))
	var companion_scale := minf(size.x / BASE_SIZE.x, size.y / BASE_SIZE.y)
	_companion_sprite.position = _scaled_vector(Vector2(1370, 617))
	_companion_sprite.scale = Vector2.ONE * companion_scale * 0.42

	_set_control_rect(_progress, Rect2(240, 700, 1138, 48))
	_set_control_rect(_elapsed_label, Rect2(250, 738, 100, 26))
	_set_control_rect(_duration_label, Rect2(1280, 738, 90, 26))

	_set_control_rect(_previous_button, PREVIOUS_RECT)
	_set_control_rect(_play_pause_button, PLAY_PAUSE_RECT)
	_set_control_rect(_next_button, NEXT_RECT)
	_set_control_rect(_mode_button, MODE_RECT)
	_mode_badge.position = Vector2(_mode_button.size.x * 0.56, 0)
	_mode_badge.size = Vector2(_mode_button.size.x * 0.38, _mode_button.size.y * 0.4)
	_set_control_rect(_minimize_button, MINIMIZE_RECT)
	_set_control_rect(_exit_button, EXIT_RECT)



func _make_label(text_value: String, font_size: int, color: Color, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if _font:
		label.add_theme_font_override("font", _font)
	return label


func _make_atlas_button(region: Rect2, tooltip: String) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = _make_atlas_texture(region)
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.z_index = 100
	button.tooltip_text = tooltip
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.mouse_entered.connect(_animate_control.bind(button, true))
	button.mouse_exited.connect(_animate_control.bind(button, false))
	return button


func _make_atlas_texture(region: Rect2) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = load(UI_DIR + "/player_panel.png") as Texture2D
	atlas.region = region
	return atlas


func _add_cover_decoration(texture_name: String) -> void:
	var decoration := TextureRect.new()
	decoration.texture = load(UI_DIR + "/" + texture_name) as Texture2D
	decoration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	decoration.stretch_mode = TextureRect.STRETCH_SCALE
	decoration.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decoration.z_index = 5
	_cover_decorations.append(decoration)
	add_child(decoration)


func _make_cover_material(rect_size: Vector2, radius: float) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec2 rect_size = vec2(344.0, 340.0);
uniform float corner_radius = 20.0;
varying vec2 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	vec2 half_size = rect_size * 0.5;
	vec2 rounded = abs(local_position - half_size) - (half_size - vec2(corner_radius));
	float distance_to_edge = length(max(rounded, vec2(0.0))) + min(max(rounded.x, rounded.y), 0.0) - corner_radius;
	color.a *= 1.0 - smoothstep(-1.0, 1.0, distance_to_edge);
	COLOR = color;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("rect_size", rect_size)
	material.set_shader_parameter("corner_radius", radius)
	return material


func _scaled_rect(base_rect: Rect2) -> Rect2:
	return Rect2(_scaled_vector(base_rect.position), _scaled_vector(base_rect.size))


func _scaled_vector(base_value: Vector2) -> Vector2:
	return Vector2(base_value.x * size.x / BASE_SIZE.x, base_value.y * size.y / BASE_SIZE.y)


func _set_control_rect(control: Control, base_rect: Rect2) -> void:
	var scaled := _scaled_rect(base_rect)
	control.position = scaled.position
	control.size = scaled.size
	control.pivot_offset = scaled.size * 0.5


func uses_player_skin() -> bool:
	return is_instance_valid(_skin) and _skin.texture != null


func get_exit_button_rect() -> Rect2:
	return Rect2(_exit_button.position, _exit_button.size) if is_instance_valid(_exit_button) else Rect2()


func is_window_control_position(local_position: Vector2) -> bool:
	if not is_instance_valid(_minimize_button) or not is_instance_valid(_exit_button):
		return false
	var padding := maxf(10.0, size.y * 0.012)
	var minimize_hit := Rect2(_minimize_button.position, _minimize_button.size).grow(padding)
	var exit_hit := Rect2(_exit_button.position, _exit_button.size).grow(padding)
	if minimize_hit.has_point(local_position) or exit_hit.has_point(local_position):
		return true
	# Native Windows input can report physical pixels while the viewport is DPI-scaled.
	return Rect2(size.x * 0.84, 0.0, size.x * 0.16, size.y * 0.18).has_point(local_position)


func _show_lyric_message(message: String) -> void:
	for label in _lyric_labels:
		label.text = ""
	_lyric_labels[2].text = message
	_lyrics_source_label.text = ""
	_last_lyric_index = -1


func _animate_lyrics(direction: float) -> void:
	if _lyric_tween and _lyric_tween.is_valid():
		_lyric_tween.kill()
	for label in _lyric_labels:
		label.modulate.a = 0.15
		label.position.y += 16.0 * direction
	_lyric_labels[2].scale = Vector2(0.96, 0.96)
	_lyric_tween = create_tween()
	_lyric_tween.set_parallel(true)
	for label in _lyric_labels:
		_lyric_tween.tween_property(label, "position:y", label.position.y - 16.0 * direction, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_lyric_tween.tween_property(label, "modulate:a", 1.0, 0.27)
	_lyric_tween.tween_property(_lyric_labels[2], "scale", Vector2.ONE, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _play_cover_motion() -> void:
	if _cover_tween and _cover_tween.is_valid():
		_cover_tween.kill()
	_cover.scale = Vector2.ONE
	_cover_tween = create_tween().set_loops()
	_cover_tween.tween_property(_cover, "scale", Vector2.ONE * 1.018, 4.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cover_tween.tween_property(_cover, "scale", Vector2.ONE, 4.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _animate_control(button: Control, hovered: bool) -> void:
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2.ONE * (1.08 if hovered else 1.0), 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _mode_badge_text(mode_name: String) -> String:
	match mode_name:
		"single":
			return "1"
		"sequential":
			return ">"
		"list":
			return "A"
	return ""


func _mode_display_name(mode_name: String) -> String:
	match mode_name:
		"single":
			return "单曲循环"
		"shuffle":
			return "随机播放"
		"list":
			return "列表循环"
	return "顺序播放"


func _format_time(milliseconds: int) -> String:
	var total_seconds := maxi(milliseconds / 1000, 0)
	return "%d:%02d" % [total_seconds / 60, total_seconds % 60]
