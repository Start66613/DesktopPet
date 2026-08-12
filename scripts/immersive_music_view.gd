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

var _font: Font
var _background: ColorRect
var _backdrop: TextureRect
var _veil: ColorRect
var _cover_frame: Panel
var _cover: TextureRect
var _title_label: Label
var _artist_label: Label
var _source_label: Label
var _lyric_labels: Array[Label] = []
var _lyrics_source_label: Label
var _progress: PetMusicProgressControl
var _elapsed_label: Label
var _duration_label: Label
var _previous_button: Button
var _play_pause_button: Button
var _next_button: Button
var _mode_button: Button
var _exit_button: Button
var _companion_note: Label
var _companion_emoji: Label
var _note_tween: Tween
var _lyric_tween: Tween
var _cover_tween: Tween
var _last_lyric_index := -1
var _session: Dictionary = {"found": false}


func configure(font: Font) -> void:
	_font = font


func _ready() -> void:
	set_process_input(true)
	_build_ui()
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


func set_cover(texture: Texture2D) -> void:
	_cover.texture = texture
	_backdrop.texture = texture
	if texture:
		_play_cover_motion()


func set_session(info: Dictionary, mode_name: String) -> void:
	_session = info.duplicate(true)
	var found := bool(info.get("found", false))
	_title_label.text = String(info.get("title", "等待播放器")) if found else "等待播放器"
	_artist_label.text = String(info.get("artist", "打开 QQ音乐 或 网易云音乐")) if found else "打开 QQ音乐 或 网易云音乐"
	_source_label.text = "%s  ·  %s" % [
		String(info.get("source_label", "本地播放器")) if found else "音乐中心",
		"正在播放" if String(info.get("playback_status", "")) == "playing" else ("已暂停" if found else "等待连接")
	]
	var playing := String(info.get("playback_status", "")) == "playing"
	_play_pause_button.text = "Ⅱ" if playing else "▶"
	_play_pause_button.tooltip_text = "暂停" if playing else "播放"
	_previous_button.disabled = not found or not bool(info.get("can_previous", false))
	_next_button.disabled = not found or not bool(info.get("can_next", false))
	_play_pause_button.disabled = not found
	_mode_button.disabled = not found
	_mode_button.text = _mode_symbol(mode_name)
	_mode_button.tooltip_text = "播放顺序：" + _mode_display_name(mode_name)


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
		_animate_lyrics(1.0 if _last_lyric_index < 0 or current_index > _last_lyric_index else -1.0)
		_last_lyric_index = current_index


func show_lyric_message(message: String) -> void:
	_show_lyric_message(message)


func show_companion_note(text: String, emoji: String) -> void:
	_companion_note.text = text
	_companion_emoji.text = emoji if not emoji.is_empty() else "♪"
	if _note_tween and _note_tween.is_valid():
		_note_tween.kill()
	_companion_note.modulate.a = 0.0
	_companion_emoji.modulate.a = 0.0
	_companion_note.position.y += 12.0
	_companion_emoji.position.y += 12.0
	_note_tween = create_tween()
	_note_tween.set_parallel(true)
	_note_tween.tween_property(_companion_note, "modulate:a", 1.0, 0.24)
	_note_tween.tween_property(_companion_emoji, "modulate:a", 1.0, 0.24)
	_note_tween.tween_property(_companion_note, "position:y", _companion_note.position.y - 12.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_note_tween.tween_property(_companion_emoji, "position:y", _companion_emoji.position.y - 12.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_note_tween.chain().tween_interval(6.0)
	_note_tween.chain().tween_property(_companion_note, "modulate:a", 0.0, 0.5)
	_note_tween.parallel().tween_property(_companion_emoji, "modulate:a", 0.0, 0.5)


func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_background = ColorRect.new()
	_background.color = Color("21191f")
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	_backdrop = TextureRect.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_backdrop.modulate = Color(1.0, 0.86, 0.9, 0.16)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)

	_veil = ColorRect.new()
	_veil.color = Color(0.12, 0.08, 0.11, 0.76)
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)

	_add_decoration("bow_wide.png", Vector2.ZERO, Vector2(300, 90), 2)
	_add_decoration("rose.png", Vector2.ZERO, Vector2(82, 64), 2)
	_add_decoration("rose.png", Vector2.ZERO, Vector2(82, 64), 2)

	_cover_frame = Panel.new()
	_cover_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cover_style := StyleBoxFlat.new()
	cover_style.bg_color = Color("fff8f4")
	cover_style.border_color = Color("e7b2bd")
	cover_style.set_border_width_all(4)
	cover_style.set_corner_radius_all(18)
	cover_style.shadow_color = Color(0, 0, 0, 0.32)
	cover_style.shadow_size = 18
	_cover_frame.add_theme_stylebox_override("panel", cover_style)
	add_child(_cover_frame)

	_cover = TextureRect.new()
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cover.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover_frame.add_child(_cover)

	_title_label = _make_label("等待播放器", 34, Color("fff2f2"), HORIZONTAL_ALIGNMENT_CENTER)
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_title_label)
	_artist_label = _make_label("打开 QQ音乐 或 网易云音乐", 21, Color("e5bcc5"), HORIZONTAL_ALIGNMENT_CENTER)
	_artist_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_artist_label)
	_source_label = _make_label("音乐中心", 16, Color("c9a3aa"), HORIZONTAL_ALIGNMENT_LEFT)
	add_child(_source_label)

	for row in 5:
		var size_px := 23 if row != 2 else 38
		var color := Color("a98790") if row in [0, 4] else (Color("d3aeb7") if row in [1, 3] else Color("fff4f1"))
		var lyric := _make_label("", size_px, color, HORIZONTAL_ALIGNMENT_CENTER)
		lyric.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_lyric_labels.append(lyric)
		add_child(lyric)
	_lyrics_source_label = _make_label("", 13, Color("a98790"), HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_lyrics_source_label)

	_progress = ProgressControl.new()
	_progress.seek_requested.connect(func(ratio: float) -> void: seek_requested.emit(ratio))
	add_child(_progress)
	_elapsed_label = _make_label("0:00", 14, Color("d8b6be"), HORIZONTAL_ALIGNMENT_LEFT)
	_duration_label = _make_label("0:00", 14, Color("d8b6be"), HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_elapsed_label)
	add_child(_duration_label)

	_previous_button = _make_control_button("⏮", "上一首")
	_previous_button.pressed.connect(func() -> void: previous_requested.emit())
	_play_pause_button = _make_control_button("▶", "播放", true)
	_play_pause_button.pressed.connect(func() -> void: play_pause_requested.emit())
	_next_button = _make_control_button("⏭", "下一首")
	_next_button.pressed.connect(func() -> void: next_requested.emit())
	_mode_button = _make_control_button("↻", "播放顺序")
	_mode_button.pressed.connect(func() -> void: mode_requested.emit())
	add_child(_previous_button)
	add_child(_play_pause_button)
	add_child(_next_button)
	add_child(_mode_button)

	_exit_button = _make_control_button("⛶", "退出全屏")
	_exit_button.pressed.connect(func() -> void: exit_requested.emit())
	add_child(_exit_button)

	_companion_emoji = _make_label("♪", 28, Color("f1b6c3"), HORIZONTAL_ALIGNMENT_CENTER)
	_companion_emoji.modulate.a = 0.0
	add_child(_companion_emoji)
	_companion_note = _make_label("", 19, Color("f9dfe4"), HORIZONTAL_ALIGNMENT_LEFT)
	_companion_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_companion_note.modulate.a = 0.0
	add_child(_companion_note)


func _layout() -> void:
	if not is_instance_valid(_cover_frame):
		return
	var viewport := size
	var cover_side := clampf(minf(viewport.y * 0.46, viewport.x * 0.31), 280.0, 520.0)
	var left_center_x := viewport.x * 0.25
	var cover_position := Vector2(left_center_x - cover_side * 0.5, maxf(105.0, viewport.y * 0.16))
	_cover_frame.position = cover_position
	_cover_frame.size = Vector2.ONE * cover_side
	_cover.position = Vector2(10, 10)
	_cover.size = Vector2.ONE * (cover_side - 20.0)
	_cover.pivot_offset = _cover.size * 0.5

	_title_label.position = Vector2(cover_position.x - 40.0, cover_position.y + cover_side + 24.0)
	_title_label.size = Vector2(cover_side + 80.0, 52.0)
	_artist_label.position = _title_label.position + Vector2(0, 47)
	_artist_label.size = Vector2(cover_side + 80.0, 34.0)
	_source_label.position = Vector2(viewport.x * 0.055, viewport.y * 0.055)
	_source_label.size = Vector2(viewport.x * 0.38, 30)

	var lyric_left := viewport.x * 0.46
	var lyric_width := viewport.x * 0.45
	var lyric_center_y := viewport.y * 0.43
	var spacing := clampf(viewport.y * 0.078, 52.0, 78.0)
	for row in _lyric_labels.size():
		var label := _lyric_labels[row]
		label.position = Vector2(lyric_left, lyric_center_y + (row - 2) * spacing - 32.0)
		label.size = Vector2(lyric_width, 64.0)
		label.pivot_offset = label.size * 0.5
	_lyrics_source_label.position = Vector2(lyric_left, lyric_center_y + spacing * 2.7)
	_lyrics_source_label.size = Vector2(lyric_width, 24)

	var progress_left := viewport.x * 0.13
	var progress_width := viewport.x * 0.74
	var progress_y := viewport.y * 0.79
	_progress.position = Vector2(progress_left, progress_y)
	_progress.size = Vector2(progress_width, 34)
	_elapsed_label.position = Vector2(progress_left, progress_y + 31)
	_elapsed_label.size = Vector2(80, 24)
	_duration_label.position = Vector2(progress_left + progress_width - 80, progress_y + 31)
	_duration_label.size = Vector2(80, 24)

	var controls_y := viewport.y * 0.875
	var button_size := clampf(viewport.y * 0.065, 54.0, 76.0)
	var gap := button_size * 0.35
	var total_width := button_size * 4.0 + gap * 3.0
	var controls_x := (viewport.x - total_width) * 0.5
	for index in 4:
		var button: Button = [_previous_button, _play_pause_button, _next_button, _mode_button][index]
		button.position = Vector2(controls_x + index * (button_size + gap), controls_y)
		button.size = Vector2.ONE * button_size
		button.pivot_offset = button.size * 0.5
	_exit_button.position = Vector2(viewport.x - 86, 34)
	_exit_button.size = Vector2(54, 54)

	_companion_emoji.position = Vector2(viewport.x * 0.46, viewport.y * 0.68)
	_companion_emoji.size = Vector2(48, 42)
	_companion_note.position = Vector2(viewport.x * 0.46 + 52, viewport.y * 0.67)
	_companion_note.size = Vector2(viewport.x * 0.39, 70)

	var decorations := get_tree().get_nodes_in_group("immersive_music_decoration")
	if decorations.size() >= 3:
		decorations[0].position = Vector2((viewport.x - 300.0) * 0.5, 18)
		decorations[1].position = Vector2(30, viewport.y - 78)
		decorations[2].position = Vector2(viewport.x - 112, viewport.y - 78)


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


func _make_control_button(symbol: String, tooltip: String, emphasized: bool = false) -> Button:
	var button := Button.new()
	button.text = symbol
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 28 if emphasized else 23)
	button.add_theme_color_override("font_color", Color("704a56"))
	button.add_theme_color_override("font_hover_color", Color("704a56"))
	button.add_theme_color_override("font_pressed_color", Color("704a56"))
	var symbol_font := SystemFont.new()
	symbol_font.font_names = PackedStringArray(["Segoe UI Symbol", "Segoe UI"])
	button.add_theme_font_override("font", symbol_font)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("f8e9e6")
	normal.border_color = Color("dc9faa")
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(36)
	var hover := normal.duplicate()
	hover.bg_color = Color("f5cbd2")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", normal)
	button.mouse_entered.connect(_animate_control.bind(button, true))
	button.mouse_exited.connect(_animate_control.bind(button, false))
	return button


func _add_decoration(texture_name: String, node_position: Vector2, node_size: Vector2, layer: int) -> void:
	var decoration := TextureRect.new()
	decoration.position = node_position
	decoration.size = node_size
	decoration.texture = load(UI_DIR + "/" + texture_name) as Texture2D
	decoration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	decoration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	decoration.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decoration.z_index = layer
	decoration.add_to_group("immersive_music_decoration")
	add_child(decoration)


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


func _mode_symbol(mode_name: String) -> String:
	match mode_name:
		"single":
			return "1"
		"shuffle":
			return "⇄"
		"sequential":
			return "→"
	return "↻"


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
