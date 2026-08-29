extends Window
class_name PetMusicPlayerPanel

const UI_DIR := "res://assets/music/runtime/ui"
const BASE_SIZE := Vector2(1678, 951)
const PANEL_SIZE := Vector2i(820, 465)
const UI_SCALE := 820.0 / 1678.0
const ProgressControl := preload("res://scripts/music_progress_control.gd")
const ImmersiveMusicView := preload("res://scripts/immersive_music_view.gd")
const PREVIOUS_REGION := Rect2(423, 747, 135, 137)
const PLAY_REGION := Rect2(592, 738, 195, 151)
const PAUSE_REGION := Rect2(817, 746, 143, 139)
const NEXT_REGION := Rect2(999, 748, 139, 137)
const SHUFFLE_REGION := Rect2(1170, 774, 88, 88)
const REPEAT_REGION := Rect2(1292, 773, 91, 89)
const PREVIOUS_RECT := Rect2(555, 746, 135, 137)
const PLAY_PAUSE_RECT := Rect2(742, 738, 195, 151)
const NEXT_RECT := Rect2(988, 746, 139, 137)
const MODE_RECT := Rect2(1230, 773, 91, 89)
const PLAY_MODES := ["sequential", "list", "single", "shuffle"]
const PREVIOUS_LYRIC_POSITION := Vector2(292, 225)
const CURRENT_LYRIC_POSITION := Vector2(282, 254)
const NEXT_LYRIC_POSITION := Vector2(292, 298)
const COVER_POSITION := Vector2(89, 117)
const COVER_SIZE := Vector2(168, 166)

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
var _mode_button: TextureButton
var _mode_badge: Label
var _fullscreen_button: Button
var _immersive_window: Window
var _immersive_view: PetImmersiveMusicView
var _play_texture: AtlasTexture
var _pause_texture: AtlasTexture
var _shuffle_texture: AtlasTexture
var _repeat_texture: AtlasTexture
var _panel_tween: Tween
var _cover_tween: Tween
var _lyric_tween: Tween
var _play_state_tween: Tween
var _button_tweens: Dictionary = {}
var _session: Dictionary = {"found": false}
var _lyrics: Array[Dictionary] = []
var _lyrics_track_id := ""
var _current_lyric_index := -1
var _seek_preview_ratio := -1.0
var _seek_preview_until_ms := 0
var _display_mode := "sequential"
var _requested_mode := ""
var _mode_request_until_ms := 0
var _play_state_initialized := false
var _displayed_playing := false
var _fullscreen_active := false
var _fullscreen_transitioning := false
var _fullscreen_screen := 0
var _player_was_visible_before_fullscreen := false
var _main_window_was_always_on_top := false


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
	if not _monitor:
		return
	_session = _monitor.get_session()
	_update_lyrics_for_position(int(_session.get("position_ms", 0)))
	if visible or _fullscreen_active:
		_update_progress()


func open_at(screen_position: Vector2i) -> void:
	if _fullscreen_active or _fullscreen_transitioning:
		_exit_fullscreen()
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
	if _fullscreen_active or _fullscreen_transitioning:
		_exit_fullscreen()
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

	_fullscreen_button = Button.new()
	_fullscreen_button.position = Vector2(1353, 48)
	_fullscreen_button.size = Vector2(82, 82)
	_fullscreen_button.text = "⛶"
	_fullscreen_button.tooltip_text = "沉浸全屏"
	_fullscreen_button.focus_mode = Control.FOCUS_NONE
	_fullscreen_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_fullscreen_button.add_theme_font_size_override("font_size", 39)
	_fullscreen_button.add_theme_color_override("font_color", Color("9f6874"))
	_fullscreen_button.add_theme_color_override("font_hover_color", Color("6f4955"))
	var fullscreen_symbol_font := SystemFont.new()
	fullscreen_symbol_font.font_names = PackedStringArray(["Segoe UI Symbol", "Segoe UI"])
	_fullscreen_button.add_theme_font_override("font", fullscreen_symbol_font)
	_fullscreen_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_fullscreen_button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	_fullscreen_button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	_fullscreen_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_fullscreen_button.pivot_offset = _fullscreen_button.size * 0.5
	_fullscreen_button.mouse_entered.connect(_animate_button.bind(_fullscreen_button, Vector2.ONE * 1.12, 0.12))
	_fullscreen_button.mouse_exited.connect(_animate_button.bind(_fullscreen_button, Vector2.ONE, 0.14))
	_fullscreen_button.pressed.connect(_enter_fullscreen)
	_root.add_child(_fullscreen_button)

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
	_shuffle_texture = _make_atlas_texture(SHUFFLE_REGION)
	_repeat_texture = _make_atlas_texture(REPEAT_REGION)
	_mode_button = _make_atlas_button(REPEAT_REGION, MODE_RECT, "播放顺序")
	_mode_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_mode_button.pressed.connect(_on_mode_pressed)
	_root.add_child(_mode_button)
	_mode_badge = Label.new()
	_mode_badge.position = Vector2(55, 2)
	_mode_badge.size = Vector2(30, 30)
	_mode_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mode_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode_badge.add_theme_font_size_override("font_size", 23)
	_mode_badge.add_theme_color_override("font_color", Color("6f9478"))
	if _font:
		_mode_badge.add_theme_font_override("font", _font)
	_mode_button.add_child(_mode_badge)

	_text_layer = Control.new()
	_text_layer.size = Vector2(PANEL_SIZE)
	_text_layer.pivot_offset = Vector2.ZERO
	_text_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_layer.z_index = 20
	add_child(_text_layer)

	var cover_inset := Panel.new()
	cover_inset.position = Vector2(87, 115)
	cover_inset.size = Vector2(172, 170)
	cover_inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inset_style := StyleBoxFlat.new()
	inset_style.bg_color = Color("fff9f5")
	inset_style.border_color = Color("e7c2c0")
	inset_style.set_border_width_all(2)
	inset_style.set_corner_radius_all(14)
	cover_inset.add_theme_stylebox_override("panel", inset_style)
	_text_layer.add_child(cover_inset)

	_cover = TextureRect.new()
	_cover.position = COVER_POSITION
	_cover.size = COVER_SIZE
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cover.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.pivot_offset = _cover.size * 0.5
	_cover.material = _make_cover_material(_cover.size, 12.0)
	_text_layer.add_child(_cover)
	_add_cover_foreground()

	_title_label = _make_label("等待播放器", Vector2(297, 116), Vector2(280, 42), 27, Color("6f4955"))
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_text_layer.add_child(_title_label)
	_artist_label = _make_label("打开 QQ音乐 或 网易云音乐", Vector2(297, 161), Vector2(300, 31), 19, Color("9f6874"))
	_artist_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_text_layer.add_child(_artist_label)
	_album_label = _make_label("", Vector2(297, 193), Vector2(300, 27), 16, Color("ad858b"))
	_album_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_text_layer.add_child(_album_label)

	_source_label = _make_label("等待播放器", Vector2(91, 68), Vector2(180, 28), 17, Color("a65f70"))
	var source_font := SystemFont.new()
	source_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Segoe UI"])
	_source_label.add_theme_font_override("font", source_font)
	_text_layer.add_child(_source_label)
	_status_label = _make_label("正在寻找音乐…", Vector2(595, 72), Vector2(165, 26), 15, Color("a77a82"))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_text_layer.add_child(_status_label)

	_previous_lyric = _make_lyric_label(PREVIOUS_LYRIC_POSITION, 16, Color("bd999f"))
	_current_lyric = _make_lyric_label(CURRENT_LYRIC_POSITION, 21, Color("7b4b58"))
	_current_lyric.size = Vector2(405, 42)
	_current_lyric.pivot_offset = _current_lyric.size * 0.5
	_current_lyric.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_next_lyric = _make_lyric_label(NEXT_LYRIC_POSITION, 16, Color("bd999f"))
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

func _create_immersive_window(screen_position: Vector2i, screen_size: Vector2i) -> void:
	if is_instance_valid(_immersive_window) or not is_inside_tree():
		return
	_immersive_window = Window.new()
	_immersive_window.name = "ImmersiveMusicWindow"
	_immersive_window.title = "音乐中心 - 沉浸模式"
	_immersive_window.visible = false
	_immersive_window.borderless = true
	_immersive_window.transparent_bg = false
	_immersive_window.unresizable = false
	_immersive_window.always_on_top = false
	_immersive_window.transient = false
	_immersive_window.force_native = true
	_immersive_window.position = screen_position
	_immersive_window.size = screen_size
	_immersive_window.close_requested.connect(_exit_fullscreen)
	_immersive_window.size_changed.connect(_resize_immersive_view)
	_immersive_window.window_input.connect(_on_immersive_window_input)

	_immersive_view = ImmersiveMusicView.new()
	_immersive_view.configure(_font)
	_immersive_view.visible = true
	_immersive_view.exit_requested.connect(_exit_fullscreen)
	_immersive_view.previous_requested.connect(_on_previous_pressed)
	_immersive_view.play_pause_requested.connect(_on_play_pause_pressed)
	_immersive_view.next_requested.connect(_on_next_pressed)
	_immersive_view.mode_requested.connect(_on_mode_pressed)
	_immersive_view.seek_requested.connect(_on_seek_requested)
	_immersive_window.add_child(_immersive_view)
	get_tree().root.add_child(_immersive_window)
	_resize_immersive_view()


func _make_atlas_texture(region: Rect2) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = load(UI_DIR + "/player_panel.png") as Texture2D
	atlas.region = region
	return atlas


func _make_cover_material(rect_size: Vector2, radius: float) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec2 rect_size = vec2(168.0, 132.0);
uniform float corner_radius = 12.0;
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


func _add_cover_foreground() -> void:
	# Rebuild the decoration above the album art so the cover visibly continues
	# behind the roses and bow instead of stopping before them.
	_add_cover_decoration("rose.png", Vector2(72, 261), Vector2(60, 47), 30)
	_add_cover_decoration("rose.png", Vector2(212, 261), Vector2(60, 47), 30)
	_add_cover_decoration("bow_large.png", Vector2(115, 241), Vector2(106, 82), 31)


func _add_cover_decoration(texture_name: String, decoration_position: Vector2, decoration_size: Vector2, layer: int) -> void:
	var decoration := TextureRect.new()
	decoration.position = decoration_position
	decoration.size = decoration_size
	decoration.texture = load(UI_DIR + "/" + texture_name) as Texture2D
	decoration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	decoration.stretch_mode = TextureRect.STRETCH_SCALE
	decoration.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decoration.z_index = layer
	_text_layer.add_child(decoration)


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
		_requested_mode = ""
		_play_state_initialized = false
		_apply_play_pause_visual(false)
		_update_mode_state()
		_set_controls_enabled(false)
		_show_lyric_message("歌词会在播放后出现")
		_update_progress()
		_sync_immersive_session()
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
	_update_mode_state()
	_set_controls_enabled(true)
	_update_progress()
	_sync_immersive_session()


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
	_sync_immersive_lyrics()


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
	if _immersive_view:
		_immersive_view.set_progress(position_ms, duration_ms)


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
	var previous_index := _current_lyric_index
	_current_lyric_index = next_index
	_previous_lyric.text = String(_lyrics[next_index - 1].get("text", "")) if next_index > 0 else ""
	_current_lyric.text = String(_lyrics[next_index].get("text", ""))
	_next_lyric.text = String(_lyrics[next_index + 1].get("text", "")) if next_index + 1 < _lyrics.size() else ""
	_animate_lyric_change(1.0 if previous_index < 0 or next_index > previous_index else -1.0)
	_sync_immersive_lyrics()


func _show_lyric_message(message: String) -> void:
	_reset_lyric_visuals()
	_previous_lyric.text = ""
	_current_lyric.text = message
	_next_lyric.text = ""
	_lyrics_source_label.text = ""
	if _immersive_view:
		_immersive_view.show_lyric_message(message)


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
		if _immersive_view:
			_immersive_view.set_cover(_cover.texture)
		_play_cover_reveal()
	else:
		_cover.texture = null
		if _immersive_view:
			_immersive_view.set_cover(null)


func _play_cover_reveal() -> void:
	if _cover_tween and _cover_tween.is_valid():
		_cover_tween.kill()
	_cover.modulate.a = 0.0
	_cover_tween = create_tween()
	_cover_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_cover_tween.tween_property(_cover, "modulate:a", 1.0, 0.24)


func _animate_lyric_change(direction: float) -> void:
	if _lyric_tween and _lyric_tween.is_valid():
		_lyric_tween.kill()
	var labels: Array[Label] = [_previous_lyric, _current_lyric, _next_lyric]
	var destinations := [PREVIOUS_LYRIC_POSITION, CURRENT_LYRIC_POSITION, NEXT_LYRIC_POSITION]
	var offset := Vector2(0, 10.0 * direction)
	for index in labels.size():
		labels[index].position = destinations[index] + offset
		labels[index].modulate.a = 0.28 if index != 1 else 0.42
	_current_lyric.scale = Vector2(0.96, 0.96)
	_lyric_tween = create_tween()
	_lyric_tween.set_parallel(true)
	_lyric_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for index in labels.size():
		_lyric_tween.tween_property(labels[index], "position", destinations[index], 0.28)
		_lyric_tween.tween_property(labels[index], "modulate:a", 1.0, 0.22)
	_lyric_tween.tween_property(_current_lyric, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)


func _reset_lyric_visuals() -> void:
	if _lyric_tween and _lyric_tween.is_valid():
		_lyric_tween.kill()
	_previous_lyric.position = PREVIOUS_LYRIC_POSITION
	_current_lyric.position = CURRENT_LYRIC_POSITION
	_next_lyric.position = NEXT_LYRIC_POSITION
	_previous_lyric.modulate.a = 1.0
	_current_lyric.modulate.a = 1.0
	_next_lyric.modulate.a = 1.0
	_current_lyric.scale = Vector2.ONE


func _set_controls_enabled(enabled: bool) -> void:
	_previous_button.disabled = not enabled or not bool(_session.get("can_previous", false))
	var playing := String(_session.get("playback_status", "")) == "playing"
	var can_toggle := bool(_session.get("can_pause", true)) if playing else bool(_session.get("can_play", true))
	_play_pause_button.disabled = not enabled or not can_toggle
	_next_button.disabled = not enabled or not bool(_session.get("can_next", false))
	_mode_button.disabled = not enabled


func _on_previous_pressed() -> void:
	if _monitor:
		_monitor.skip_previous()


func _on_play_pause_pressed() -> void:
	if _monitor:
		_monitor.toggle_play_pause()


func _on_next_pressed() -> void:
	if _monitor:
		_monitor.skip_next()


func _on_mode_pressed() -> void:
	if not _monitor:
		return
	if not bool(_session.get("can_repeat", false)) and not bool(_session.get("can_shuffle", false)):
		_status_label.text = "请在%s中切换" % String(_session.get("source_label", "播放器"))
		return
	var current_index := PLAY_MODES.find(_display_mode)
	var next_mode: String = PLAY_MODES[(current_index + 1) % PLAY_MODES.size()] if current_index >= 0 else "list"
	_requested_mode = next_mode
	_mode_request_until_ms = Time.get_ticks_msec() + 3200
	_set_mode_visual(next_mode)
	_status_label.text = _mode_display_name(next_mode)
	_monitor.set_play_mode(next_mode)
	_sync_immersive_session()


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
	if not _play_state_initialized:
		_play_state_initialized = true
		_apply_play_pause_visual(playing)
		return
	if playing == _displayed_playing:
		_play_pause_button.tooltip_text = "暂停" if playing else "播放"
		return
	if _play_state_tween and _play_state_tween.is_valid():
		_play_state_tween.kill()
	if _button_tweens.has(_play_pause_button):
		var hover_tween: Tween = _button_tweens[_play_pause_button]
		if hover_tween and hover_tween.is_valid():
			hover_tween.kill()
	var turn := deg_to_rad(-6.0 if playing else 6.0)
	_play_state_tween = create_tween()
	_play_state_tween.tween_property(_play_pause_button, "scale", Vector2.ONE * 0.82, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_play_state_tween.parallel().tween_property(_play_pause_button, "rotation", turn, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_play_state_tween.tween_callback(_apply_play_pause_visual.bind(playing))
	_play_state_tween.tween_property(_play_pause_button, "scale", Vector2.ONE * 1.08, 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_play_state_tween.parallel().tween_property(_play_pause_button, "rotation", -turn * 0.3, 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_play_state_tween.tween_property(_play_pause_button, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_play_state_tween.parallel().tween_property(_play_pause_button, "rotation", 0.0, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _apply_play_pause_visual(playing: bool) -> void:
	_displayed_playing = playing
	_play_pause_button.texture_normal = _pause_texture if playing else _play_texture
	_play_pause_button.tooltip_text = "暂停" if playing else "播放"


func _update_mode_state() -> void:
	if not _mode_button:
		return
	if not _requested_mode.is_empty() and Time.get_ticks_msec() < _mode_request_until_ms:
		_set_mode_visual(_requested_mode)
		return
	_requested_mode = ""
	var mode := "sequential"
	if bool(_session.get("shuffle_active", false)):
		mode = "shuffle"
	else:
		match String(_session.get("repeat_mode", "none")):
			"list":
				mode = "list"
			"track":
				mode = "single"
	_set_mode_visual(mode)


func _set_mode_visual(mode: String) -> void:
	_display_mode = mode
	_mode_button.texture_normal = _shuffle_texture if mode == "shuffle" else _repeat_texture
	match mode:
		"sequential":
			_mode_badge.text = ">"
		"list":
			_mode_badge.text = "A"
		"single":
			_mode_badge.text = "1"
		_:
			_mode_badge.text = ""
	var capability_note := ""
	if not bool(_session.get("can_repeat", false)) and not bool(_session.get("can_shuffle", false)):
		capability_note = "（需在播放器内切换）"
	_mode_button.tooltip_text = "播放顺序：" + _mode_display_name(mode) + capability_note
	_sync_immersive_session()


func _mode_display_name(mode: String) -> String:
	match mode:
		"list":
			return "列表循环"
		"single":
			return "单曲循环"
		"shuffle":
			return "随机播放"
		_:
			return "顺序播放"


func _on_drag_handle_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		DisplayServer.window_start_drag(get_window_id())


func _enter_fullscreen() -> void:
	if _fullscreen_active or _fullscreen_transitioning:
		return
	_fullscreen_transitioning = true
	_fullscreen_screen = DisplayServer.window_get_current_screen(get_window_id())
	if _fullscreen_screen < 0:
		_fullscreen_screen = 0
	var screen_position := DisplayServer.screen_get_position(_fullscreen_screen)
	var screen_size := DisplayServer.screen_get_size(_fullscreen_screen)
	_create_immersive_window(screen_position, screen_size)
	await get_tree().process_frame
	if not _fullscreen_transitioning:
		return
	if not is_instance_valid(_immersive_window) or not is_instance_valid(_immersive_view):
		_fullscreen_transitioning = false
		return
	_player_was_visible_before_fullscreen = visible
	var main_window := get_tree().root
	_main_window_was_always_on_top = main_window.always_on_top
	main_window.always_on_top = false
	if not _immersive_view.is_node_ready():
		await get_tree().process_frame
		if not _fullscreen_transitioning:
			return

	# Keep the transparent player untouched. The immersive view owns a separate,
	# non-transparent native window so Windows cannot leave the player half-switched.
	_immersive_window.mode = Window.MODE_WINDOWED
	_immersive_window.current_screen = _fullscreen_screen
	_immersive_window.position = screen_position
	_immersive_window.size = screen_size
	_resize_immersive_view()
	_sync_immersive_session()
	_sync_immersive_lyrics()
	if _cover and _cover.texture:
		_immersive_view.set_cover(_cover.texture)
	_immersive_window.show()
	await get_tree().process_frame
	if not _fullscreen_transitioning:
		return
	DisplayServer.window_set_current_screen(_fullscreen_screen, _immersive_window.get_window_id())
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false, _immersive_window.get_window_id())
	# Godot's Windows fullscreen mode can leave a hidden HWND in multi-window
	# transparent apps. A topmost borderless window covering the physical screen
	# is visually identical and keeps the native window actually visible.
	DisplayServer.window_set_position(screen_position, _immersive_window.get_window_id())
	DisplayServer.window_set_size(screen_size, _immersive_window.get_window_id())
	await get_tree().process_frame
	await get_tree().process_frame
	if not _fullscreen_transitioning:
		return

	if not _immersive_window_fills_screen():
		_exit_fullscreen()
		return

	_resize_immersive_view()
	await get_tree().process_frame
	await get_tree().process_frame
	if not _fullscreen_transitioning:
		return

	_fullscreen_active = true
	_immersive_view.show_companion_note("把音乐铺满整个房间吧，我陪你一起听。", "🎧")
	_fullscreen_transitioning = false
	DisplayServer.window_move_to_foreground(_immersive_window.get_window_id())
	_immersive_window.grab_focus()


func _exit_fullscreen() -> void:
	if not _fullscreen_active and not _fullscreen_transitioning and not is_instance_valid(_immersive_window):
		return
	_fullscreen_active = false
	_fullscreen_transitioning = false
	var immersive_to_close := _immersive_window
	_immersive_window = null
	_immersive_view = null
	if is_instance_valid(immersive_to_close):
		immersive_to_close.mode = Window.MODE_WINDOWED
		immersive_to_close.hide()
		immersive_to_close.queue_free()
	get_tree().root.always_on_top = _main_window_was_always_on_top
	_fullscreen_button.visible = true
	if _player_was_visible_before_fullscreen and not visible:
		show()
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true, get_window_id())
		get_viewport().transparent_bg = true
		_root.visible = true
		grab_focus()
	_player_was_visible_before_fullscreen = false
	_main_window_was_always_on_top = false


func _on_immersive_window_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_F11]:
		_exit_fullscreen()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not is_instance_valid(_immersive_window) or not is_instance_valid(_immersive_view):
			return
		var window_id := _immersive_window.get_window_id()
		var physical_position := Vector2(DisplayServer.mouse_get_position() - DisplayServer.window_get_position(window_id))
		if _immersive_view.is_window_control_position(event.position) or _immersive_view.is_window_control_position(physical_position):
			_exit_fullscreen()


func _exit_tree() -> void:
	if is_instance_valid(_immersive_window) and _immersive_window.get_parent() != self:
		_immersive_window.queue_free()
	_immersive_window = null
	_immersive_view = null


func _resize_immersive_view() -> void:
	if not is_instance_valid(_immersive_window) or not is_instance_valid(_immersive_view):
		return
	_immersive_view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_immersive_view.position = Vector2.ZERO
	_immersive_view.size = Vector2(_immersive_window.size)
	if _immersive_view.is_node_ready() and _immersive_view.is_inside_tree():
		_immersive_view._layout()
	else:
		_immersive_view.call_deferred("_layout")
func _immersive_window_fills_screen() -> bool:
	if not is_instance_valid(_immersive_window):
		return false
	var expected := DisplayServer.screen_get_size(_fullscreen_screen)
	var actual := DisplayServer.window_get_size(_immersive_window.get_window_id())
	return actual.x >= expected.x - 2 and actual.y >= expected.y - 2


func get_immersive_window_id() -> int:
	return _immersive_window.get_window_id() if _immersive_window else DisplayServer.INVALID_WINDOW_ID


func is_fullscreen_button_visible() -> bool:
	return _fullscreen_button != null and _fullscreen_button.visible


func is_fullscreen_active() -> bool:
	return _fullscreen_active


func enter_fullscreen() -> void:
	_enter_fullscreen()


func show_listening_note(text: String, emoji: String = "🎵") -> void:
	if _fullscreen_active and is_instance_valid(_immersive_view):
		_immersive_view.show_companion_note(text, emoji)


func get_music_context() -> Dictionary:
	var current_text := ""
	var previous_text := ""
	var next_text := ""
	if _current_lyric_index >= 0 and _current_lyric_index < _lyrics.size():
		current_text = String(_lyrics[_current_lyric_index].get("text", ""))
	if _current_lyric_index > 0 and _current_lyric_index - 1 < _lyrics.size():
		previous_text = String(_lyrics[_current_lyric_index - 1].get("text", ""))
	if _current_lyric_index >= 0 and _current_lyric_index + 1 < _lyrics.size():
		next_text = String(_lyrics[_current_lyric_index + 1].get("text", ""))
	return {
		"active": bool(_session.get("found", false)) and String(_session.get("playback_status", "")) == "playing",
		"title": String(_session.get("title", "")),
		"artist": String(_session.get("artist", "")),
		"album": String(_session.get("album", "")),
		"source": String(_session.get("source_label", "")),
		"position_ms": int(_session.get("position_ms", 0)),
		"duration_ms": int(_session.get("duration_ms", 0)),
		"previous_lyric": previous_text,
		"current_lyric": current_text,
		"next_lyric": next_text,
		"fullscreen": _fullscreen_active
	}


func _sync_immersive_session() -> void:
	if is_instance_valid(_immersive_view) and _immersive_view.is_node_ready():
		_immersive_view.set_session(_session, _display_mode)


func _sync_immersive_lyrics() -> void:
	if is_instance_valid(_immersive_view) and _immersive_view.is_node_ready():
		_immersive_view.set_lyrics(_lyrics, _current_lyric_index, _lyrics_source_label.text if _lyrics_source_label else "")


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
