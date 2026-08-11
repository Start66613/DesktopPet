extends Window
class_name PetMusicPlayerPanel

const UI_DIR := "res://assets/music/runtime/ui"
const BASE_SIZE := Vector2(1678, 951)
const PANEL_SIZE := Vector2i(820, 465)
const UI_SCALE := 820.0 / 1678.0
const ProgressControl := preload("res://scripts/music_progress_control.gd")
const PREVIOUS_REGION := Rect2(423, 747, 135, 137)
const PLAY_REGION := Rect2(592, 738, 195, 151)
const PAUSE_REGION := Rect2(817, 746, 143, 139)
const NEXT_REGION := Rect2(999, 748, 139, 137)
const PREVIOUS_RECT := Rect2(555, 746, 135, 137)
const PLAY_PAUSE_RECT := Rect2(742, 738, 195, 151)
const NEXT_RECT := Rect2(988, 746, 139, 137)

var _font: Font
var _monitor: PetMusicSessionMonitor
var _lyrics_service: PetMusicLyricsService
var _root: Control
var _text_layer: Control
var _cover: TextureRect
var _title_label: Label
var _artist_label: Label
var _album_label: Label
var _source_label: Label
var _status_label: Label
var _previous_lyric: Label
var _current_lyric: Label
var _next_lyric: Label
var _lyrics_source_label: Label
var _elapsed_label: Label
var _duration_label: Label
var _progress: PetMusicProgressControl
var _previous_button: TextureButton
var _play_pause_button: TextureButton
var _next_button: TextureButton
var _play_texture: AtlasTexture
var _pause_texture: AtlasTexture
var _panel_tween: Tween
var _button_tweens: Dictionary = {}
var _session: Dictionary = {"found": false}
var _lyrics: Array[Dictionary] = []
var _lyrics_track_id := ""
var _current_lyric_index := -1
var _seek_preview_ratio := -1.0
var _seek_preview_until_ms := 0


func _init() -> void:
	visible = false
	title = "音乐中心"
	size = PANEL_SIZE
	min_size = PANEL_SIZE
	borderless = true
	transparent_bg = true
	unresizable = true
	always_on_top = false
	force_native = true


func configure(font: Font, monitor: PetMusicSessionMonitor, lyrics_service: PetMusicLyricsService) -> void:
	_font = font
	_monitor = monitor
	_lyrics_service = lyrics_service


func _ready() -> void:
	close_requested.connect(hide_panel)
	_build_ui()
	if _monitor:
		_monitor.session_updated.connect(_on_session_updated)
		_monitor.track_changed.connect(_on_track_changed)
		_monitor.bridge_error.connect(_on_bridge_error)
		_on_session_updated(_monitor.get_session())
	if _lyrics_service:
		_lyrics_service.lyrics_ready.connect(_on_lyrics_ready)
		_lyrics_service.lyrics_failed.connect(_on_lyrics_failed)


func _process(_delta: float) -> void:
	if not visible or not _monitor:
		return
	_session = _monitor.get_session()
	_update_progress()
	_update_lyrics_for_position(int(_session.get("position_ms", 0)))


func open_at(screen_position: Vector2i) -> void:
	position = screen_position
	mode = Window.MODE_WINDOWED
	if _monitor:
		_monitor.refresh_now()
	_on_session_updated(_monitor.get_session() if _monitor else {"found": false})
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
	_root.pivot_offset = Vector2.ZERO
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var background := TextureRect.new()
	background.size = BASE_SIZE
	background.texture = load(UI_DIR + "/player_panel_clean.png") as Texture2D
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(background)

	var drag_handle := Control.new()
	drag_handle.position = Vector2(115, 25)
	drag_handle.size = Vector2(1285, 155)
	drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	drag_handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	drag_handle.gui_input.connect(_on_drag_handle_gui_input)
	_root.add_child(drag_handle)

	var minimize_button := _make_atlas_button(Rect2(1452, 42, 112, 112), Rect2(1452, 42, 112, 112), "收起")
	minimize_button.pressed.connect(hide_panel)
	_root.add_child(minimize_button)
	var close_button := _make_atlas_button(Rect2(1558, 40, 112, 116), Rect2(1558, 40, 112, 116), "关闭")
	close_button.pressed.connect(hide_panel)
	_root.add_child(close_button)

	_previous_button = _make_atlas_button(PREVIOUS_REGION, PREVIOUS_RECT, "上一首")
	_previous_button.pressed.connect(_on_previous_pressed)
	_root.add_child(_previous_button)
	_play_texture = _make_atlas_texture(PLAY_REGION)
	_pause_texture = _make_atlas_texture(PAUSE_REGION)
	_play_pause_button = _make_atlas_button(PLAY_REGION, PLAY_PAUSE_RECT, "播放")
	_play_pause_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_play_pause_button.pressed.connect(_on_play_pause_pressed)
	_root.add_child(_play_pause_button)
	_next_button = _make_atlas_button(NEXT_REGION, NEXT_RECT, "下一首")
	_next_button.pressed.connect(_on_next_pressed)
	_root.add_child(_next_button)

	_text_layer = Control.new()
	_text_layer.size = Vector2(PANEL_SIZE)
	_text_layer.pivot_offset = Vector2.ZERO
	_text_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_layer.z_index = 20
	add_child(_text_layer)

	_cover = TextureRect.new()
	_cover.position = Vector2(89, 117)
	_cover.size = Vector2(168, 148)
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cover.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_layer.add_child(_cover)

	_title_label = _make_label("等待播放器", Vector2(297, 116), Vector2(280, 42), 27, Color("6f4955"))
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_text_layer.add_child(_title_label)
	_artist_label = _make_label("打开 QQ音乐 或 网易云音乐", Vector2(297, 161), Vector2(300, 31), 19, Color("9f6874"))
	_artist_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_text_layer.add_child(_artist_label)
	_album_label = _make_label("", Vector2(297, 193), Vector2(300, 27), 16, Color("ad858b"))
	_album_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_text_layer.add_child(_album_label)

	_source_label = _make_label("等待播放器", Vector2(55, 68), Vector2(180, 28), 17, Color("a65f70"))
	_text_layer.add_child(_source_label)
	_status_label = _make_label("正在寻找音乐…", Vector2(595, 72), Vector2(165, 26), 15, Color("a77a82"))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_text_layer.add_child(_status_label)

	_previous_lyric = _make_lyric_label(Vector2(292, 225), 16, Color("bd999f"))
	_current_lyric = _make_lyric_label(Vector2(282, 254), 21, Color("7b4b58"))
	_current_lyric.size = Vector2(405, 42)
	_current_lyric.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_next_lyric = _make_lyric_label(Vector2(292, 298), 16, Color("bd999f"))
	_text_layer.add_child(_previous_lyric)
	_text_layer.add_child(_current_lyric)
	_text_layer.add_child(_next_lyric)
	_lyrics_source_label = _make_label("", Vector2(655, 306), Vector2(105, 18), 11, Color("c4a7aa"))
	_lyrics_source_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_text_layer.add_child(_lyrics_source_label)

	_progress = ProgressControl.new()
	_progress.position = Vector2(105, 327)
	_progress.size = Vector2(580, 33)
	_progress.seek_requested.connect(_on_seek_requested)
	_text_layer.add_child(_progress)
	_elapsed_label = _make_label("0:00", Vector2(110, 349), Vector2(65, 18), 12, Color("a77a82"))
	_duration_label = _make_label("0:00", Vector2(625, 349), Vector2(55, 18), 12, Color("a77a82"))
	_duration_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_text_layer.add_child(_elapsed_label)
	_text_layer.add_child(_duration_label)


func _make_atlas_texture(region: Rect2) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = load(UI_DIR + "/player_panel.png") as Texture2D
	atlas.region = region
	return atlas


func _make_atlas_button(source_region: Rect2, display_rect: Rect2, tooltip: String) -> TextureButton:
	var atlas := _make_atlas_texture(source_region)
	var button := TextureButton.new()
	button.position = display_rect.position
	button.size = display_rect.size
	button.texture_normal = atlas
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	button.tooltip_text = tooltip
	button.pivot_offset = display_rect.size * 0.5
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.mouse_entered.connect(_animate_button.bind(button, Vector2.ONE * 1.075, 0.12))
	button.mouse_exited.connect(_animate_button.bind(button, Vector2.ONE, 0.14))
	return button


func _make_label(text: String, position_value: Vector2, size_value: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = position_value
	label.size = size_value
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if _font:
		label.add_theme_font_override("font", _font)
	return label


func _make_lyric_label(position_value: Vector2, font_size: int, color: Color) -> Label:
	var label := _make_label("", position_value, Vector2(390, 28), font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


func _on_session_updated(info: Dictionary) -> void:
	_session = info.duplicate(true)
	var found := bool(_session.get("found", false))
	if not found:
		_title_label.text = "等待播放器"
		_artist_label.text = "打开 QQ音乐 或 网易云音乐"
		_album_label.text = "检测到播放后会自动同步"
		_source_label.text = "等待播放器"
		_status_label.text = "暂无媒体会话"
		_cover.texture = null
		_progress.interactive = false
		_progress.value = 0.0
		_seek_preview_ratio = -1.0
		_set_controls_enabled(false)
		_show_lyric_message("歌词会在播放后出现")
		_update_progress()
		return

	_title_label.text = String(_session.get("title", "未知歌曲"))
	_artist_label.text = String(_session.get("artist", "未知歌手"))
	_album_label.text = String(_session.get("album", ""))
	_source_label.text = String(_session.get("source_label", "本地播放器"))
	var status := String(_session.get("playback_status", "unknown"))
	_status_label.text = "正在播放" if status == "playing" else ("已暂停" if status == "paused" else "等待播放")
	_progress.interactive = int(_session.get("duration_ms", 0)) > 0
	_progress.tooltip_text = "拖动播放进度" if bool(_session.get("can_seek", false)) else "可尝试拖动，部分播放器可能不响应"
	_update_play_pause_state()
	_set_controls_enabled(true)
	_update_progress()


func _on_track_changed(info: Dictionary) -> void:
	_session = info.duplicate(true)
	_lyrics.clear()
	_lyrics_track_id = String(info.get("track_id", ""))
	_current_lyric_index = -1
	_seek_preview_ratio = -1.0
	_show_lyric_message("正在找这首歌的歌词…")
	_load_cover()
	if _lyrics_service:
		_lyrics_service.request_lyrics(info)


func _on_lyrics_ready(track_id: String, lines: Array[Dictionary], source: String) -> void:
	if track_id != String(_session.get("track_id", "")):
		return
	_lyrics = lines.duplicate(true)
	_lyrics_track_id = track_id
	_current_lyric_index = -1
	_lyrics_source_label.text = source
	_update_lyrics_for_position(int(_session.get("position_ms", 0)))


func _on_lyrics_failed(track_id: String, message: String) -> void:
	if track_id != String(_session.get("track_id", "")):
		return
	_lyrics.clear()
	_lyrics_source_label.text = ""
	_show_lyric_message(message)


func _on_bridge_error(message: String) -> void:
	_status_label.text = message


func _update_progress() -> void:
	var position_ms := int(_session.get("position_ms", 0))
	var duration_ms := int(_session.get("duration_ms", 0))
	if _progress.is_dragging():
		position_ms = roundi(float(duration_ms) * _progress.value)
	elif _seek_preview_ratio >= 0.0 and Time.get_ticks_msec() < _seek_preview_until_ms:
		position_ms = roundi(float(duration_ms) * _seek_preview_ratio)
		_progress.value = _seek_preview_ratio
	else:
		_seek_preview_ratio = -1.0
		_progress.value = clampf(float(position_ms) / float(duration_ms), 0.0, 1.0) if duration_ms > 0 else 0.0
	_elapsed_label.text = _format_time(position_ms)
	_duration_label.text = _format_time(duration_ms)


func _update_lyrics_for_position(position_ms: int) -> void:
	if _lyrics.is_empty() or _lyrics_track_id != String(_session.get("track_id", "")):
		return
	var next_index := 0
	for index in _lyrics.size():
		if int(_lyrics[index].get("time_ms", 0)) <= position_ms + 120:
			next_index = index
		else:
			break
	if next_index == _current_lyric_index:
		return
	_current_lyric_index = next_index
	_previous_lyric.text = String(_lyrics[next_index - 1].get("text", "")) if next_index > 0 else ""
	_current_lyric.text = String(_lyrics[next_index].get("text", ""))
	_next_lyric.text = String(_lyrics[next_index + 1].get("text", "")) if next_index + 1 < _lyrics.size() else ""
	_current_lyric.scale = Vector2(0.97, 0.97)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_current_lyric, "scale", Vector2.ONE, 0.18)


func _show_lyric_message(message: String) -> void:
	_previous_lyric.text = ""
	_current_lyric.text = message
	_next_lyric.text = ""
	_lyrics_source_label.text = ""


func _load_cover() -> void:
	if not _monitor:
		return
	var bytes := _monitor.get_cover_bytes()
	if bytes.is_empty():
		_cover.texture = null
		return
	var image := Image.new()
	var error := ERR_FILE_UNRECOGNIZED
	if bytes.size() >= 8 and bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4e and bytes[3] == 0x47:
		error = image.load_png_from_buffer(bytes)
	elif bytes.size() >= 3 and bytes[0] == 0xff and bytes[1] == 0xd8 and bytes[2] == 0xff:
		error = image.load_jpg_from_buffer(bytes)
	elif bytes.size() >= 12 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		error = image.load_webp_from_buffer(bytes)
	if error == OK and not image.is_empty():
		_cover.texture = ImageTexture.create_from_image(image)
	else:
		_cover.texture = null


func _set_controls_enabled(enabled: bool) -> void:
	_previous_button.disabled = not enabled or not bool(_session.get("can_previous", false))
	var playing := String(_session.get("playback_status", "")) == "playing"
	var can_toggle := bool(_session.get("can_pause", true)) if playing else bool(_session.get("can_play", true))
	_play_pause_button.disabled = not enabled or not can_toggle
	_next_button.disabled = not enabled or not bool(_session.get("can_next", false))


func _on_previous_pressed() -> void:
	if _monitor:
		_monitor.skip_previous()


func _on_play_pause_pressed() -> void:
	if _monitor:
		_monitor.toggle_play_pause()


func _on_next_pressed() -> void:
	if _monitor:
		_monitor.skip_next()


func _on_seek_requested(ratio: float) -> void:
	var duration_ms := int(_session.get("duration_ms", 0))
	if _monitor and duration_ms > 0:
		_seek_preview_ratio = clampf(ratio, 0.0, 1.0)
		_seek_preview_until_ms = Time.get_ticks_msec() + 2200
		_monitor.seek_to(roundi(float(duration_ms) * ratio))


func _update_play_pause_state() -> void:
	if not _play_pause_button:
		return
	var playing := String(_session.get("playback_status", "")) == "playing"
	_play_pause_button.texture_normal = _pause_texture if playing else _play_texture
	_play_pause_button.tooltip_text = "暂停" if playing else "播放"


func _on_drag_handle_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		DisplayServer.window_start_drag(get_window_id())


func _animate_button(button: Control, target_scale: Vector2, duration: float) -> void:
	if button is BaseButton and button.disabled:
		return
	if _button_tweens.has(button):
		var previous: Tween = _button_tweens[button]
		if previous and previous.is_valid():
			previous.kill()
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", target_scale, duration)
	_button_tweens[button] = tween


func _play_open_animation() -> void:
	if _panel_tween and _panel_tween.is_valid():
		_panel_tween.kill()
	var start_factor := 0.965
	var root_start_scale := UI_SCALE * start_factor
	_root.scale = Vector2.ONE * root_start_scale
	_root.position = (Vector2(PANEL_SIZE) - BASE_SIZE * root_start_scale) * 0.5
	_text_layer.scale = Vector2.ONE * start_factor
	_text_layer.position = Vector2(PANEL_SIZE) * (1.0 - start_factor) * 0.5
	_panel_tween = create_tween()
	_panel_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_panel_tween.tween_property(_root, "scale", Vector2.ONE * UI_SCALE, 0.2)
	_panel_tween.parallel().tween_property(_root, "position", Vector2.ZERO, 0.2)
	_panel_tween.parallel().tween_property(_text_layer, "scale", Vector2.ONE, 0.2)
	_panel_tween.parallel().tween_property(_text_layer, "position", Vector2.ZERO, 0.2)


func _format_time(milliseconds: int) -> String:
	var total_seconds := maxi(milliseconds / 1000, 0)
	return "%d:%02d" % [total_seconds / 60, total_seconds % 60]
