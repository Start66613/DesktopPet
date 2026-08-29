extends Node2D
## 桌宠主控脚本
## - 自动扫描 res://assets/sprites/<动作>/ 下的 PNG 构建帧动画
## - 简单状态机（IDLE / WALK）
## - 无边框透明窗口：左键拖动、右键菜单、ESC 退出
## - 透明区域点击穿透：根据精灵不透明像素包围盒生成矩形多边形，
##   窗口仅在包围盒内接收鼠标事件，其余穿透到后方窗口

const SPRITES_DIR := "res://assets/sprites"
const MOVEMENT_DIR := "res://assets/movement"
const ACTIVITY_DIR := "res://assets/activities"
const COMPILED_SPRITE_FRAMES_PATH := "res://assets/runtime/pet_sprite_frames.tres"
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
const MENU_TOGGLE_PROACTIVE := 6
const MENU_COMPANION_SETTINGS := 7
const MENU_DOG_HOME := 8
const MENU_DOG_TOGGLE := 9
const MENU_MUSIC := 10
const MENU_EXIT := 99
const BADMINTON_ANIMATION := "badminton"
const MUSIC_ANIMATION := "music"
const HANDHELD_ANIMATION := "handheld"
const DRAGON_RIDE_ANIMATION := "dragon_ride"
const DOG_INTERACTION_ANIMATION := "dog_interaction"
const DOG_INTERACTION_FRAMES_PATH := "res://assets/dog/source/interaction/1786244850725-c1l7byk0gn/1786244850725-c1l7byk0gn_frames.tres"
const DOG_AUTO_INTERACTION_INITIAL_MIN := 9.0
const DOG_AUTO_INTERACTION_INITIAL_MAX := 16.0
const DOG_AUTO_INTERACTION_MIN := 30.0
const DOG_AUTO_INTERACTION_MAX := 55.0
const DOG_APPROACH_TIMEOUT := 11.0
const DRAGON_RIDE_DURATION := 18.0
const DRAGON_LAUNCH_DELAY := 1.65
const DRAGON_FLIGHT_SPEED := 165.0
const DRAGON_FLIGHT_BOB_HEIGHT := 9.0
const DRAGON_FLIGHT_BOB_SPEED := 2.6
const ACTIVITY_DURATIONS := {
	BADMINTON_ANIMATION: 13.0,
	MUSIC_ANIMATION: 22.0,
	HANDHELD_ANIMATION: 24.0,
	DRAGON_RIDE_ANIMATION: DRAGON_RIDE_DURATION,
	DOG_INTERACTION_ANIMATION: 4.8
}
const ACTIVITY_SPEEDS := {
	BADMINTON_ANIMATION: 7.0,
	MUSIC_ANIMATION: 6.0,
	HANDHELD_ANIMATION: 6.0,
	DRAGON_RIDE_ANIMATION: 8.0,
	DOG_INTERACTION_ANIMATION: 8.0
}
const UI_TEXTURE_DIR := "res://assets/ui_source/generated/1-animations/textures"
const CARE_UI_DIR := "res://assets/care/runtime/ui"
const PET_FONT_PATH := "res://assets/fonts/ZCOOLKuaiLe-Regular.ttf"
const SpeechBubble := preload("res://scripts/speech_bubble.gd")
const CareSystem := preload("res://scripts/care_system.gd")
const CarePanel := preload("res://scripts/care_panel.gd")
const CareFeedback := preload("res://scripts/care_feedback.gd")
const AIChatPanel := preload("res://scripts/ai_chat_panel.gd")
const ProactiveCompanion := preload("res://scripts/proactive_companion.gd")
const ForegroundAppMonitor := preload("res://scripts/foreground_app_monitor.gd")
const MusicSessionMonitor := preload("res://scripts/music_session_monitor.gd")
const MusicLyricsService := preload("res://scripts/music_lyrics_service.gd")
const MusicPlayerPanel := preload("res://scripts/music_player_panel.gd")
const CompanionSettingsPanel := preload("res://scripts/companion_settings_panel.gd")
const ScreenAwarenessService := preload("res://scripts/screen_awareness_service.gd")
const BadmintonGamePanel := preload("res://scripts/badminton_game_panel.gd")
const DogCompanion := preload("res://scripts/dog_companion.gd")
const DogHomePanel := preload("res://scripts/dog_home_panel.gd")

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

# ---- 状态机 ----
enum State { IDLE, WALK, SLEEP, WAKE, ACTIVITY }
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
var _active_activity := ""
var _dragon_launch_time_left := 0.0
var _dragon_origin_position := Vector2.ZERO
var _dragon_flight_position := Vector2.ZERO
var _dragon_flight_direction := Vector2.RIGHT
var _dragon_flight_phase := 0.0
var _dragon_flight_screen := 0
var _suppress_next_left_release := false

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
var _scripted_dialogue_time_left := 0.0
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
var _dog_dialogue_lines := [
	{"text": "{dog}刚才又绕着我转圈啦 (≧▽≦)", "emoji": "🐾"},
	{"text": "它一摇尾巴，我就忍不住想抱抱它 (^_^)", "emoji": "💕"},
	{"text": "{dog}今天也有乖乖陪着我们哦 (ᵔᴥᵔ)", "emoji": "🐾"},
	{"text": "嘘，它好像把球藏到桌角去了 (o_o)", "emoji": "🎾"},
	{"text": "有它在旁边跑来跑去，桌面都热闹起来啦 (^o^)", "emoji": "✨"}
]
var _cjk_font: Font
var _emoji_font: Font

# ---- 养成系统 ----
var _care_system: PetCareSystem
var _care_panel: PetCarePanel
var _care_feedback: PetCareFeedback
var _ai_chat_panel: PetAIChatPanel
var _proactive_companion: PetProactiveCompanion
var _foreground_app_monitor: PetForegroundAppMonitor
var _music_session_monitor: PetMusicSessionMonitor
var _music_lyrics_service: PetMusicLyricsService
var _music_player_panel: PetMusicPlayerPanel
var _companion_settings_panel: PetCompanionSettingsPanel
var _screen_awareness_service: PetScreenAwarenessService
var _pending_screen_message: Dictionary = {}
var _badminton_game: PetBadmintonGame
var _dog_companion: PetDogCompanion
var _dog_home_panel: PetDogHomePanel
var _pet_position_before_badminton := Vector2i.ZERO
var _pet_position_beside_badminton := Vector2i.ZERO
var _badminton_position_saved := false
var _comfort_cooldown := 0.0
var _dog_interaction_cooldown := 0.0
var _dog_interaction_pending := false
var _dog_interaction_pending_time := 0.0
var _dog_auto_interaction_time := 0.0
var _music_activity_live := false
var _last_music_track_id := ""
var _last_music_spoken_track_id := ""
var _music_has_greeted := false
var _music_pause_spoken_at := 0
var _music_reflection_time_left := 0.0
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

	# 发布版使用预编译动画库；开发资源缺失时仍可动态构建。
	var compiled_frames := load(COMPILED_SPRITE_FRAMES_PATH) as SpriteFrames
	sprite.sprite_frames = compiled_frames if compiled_frames else _build_sprite_frames()
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
	_schedule_next_dog_interaction(true)
	call_deferred("_show_bubble", "你好呀，我会陪着你 (^_^)", 4.0, "✨")
	var startup_args := OS.get_cmdline_args()
	var user_args := OS.get_cmdline_user_args()
	if startup_args.has("--show-care-panel") or user_args.has("--show-care-panel"):
		call_deferred("_open_care_panel")
	if startup_args.has("--show-chat-panel") or user_args.has("--show-chat-panel"):
		call_deferred("_open_ai_chat_panel")
	if startup_args.has("--show-companion-settings") or user_args.has("--show-companion-settings"):
		call_deferred("_open_companion_settings")
	if startup_args.has("--show-music-player") or user_args.has("--show-music-player"):
		call_deferred("_open_music_player")
	if startup_args.has("--show-music-fullscreen") or user_args.has("--show-music-fullscreen"):
		call_deferred("_debug_open_music_fullscreen")
	if startup_args.has("--show-screen-awareness") or user_args.has("--show-screen-awareness"):
		call_deferred("_open_screen_awareness")
	if startup_args.has("--show-badminton-game") or user_args.has("--show-badminton-game"):
		call_deferred("_open_badminton_game")
	if startup_args.has("--show-dog-home") or user_args.has("--show-dog-home"):
		call_deferred("_open_dog_home_panel")
	if startup_args.has("--reopen-dog-home") or user_args.has("--reopen-dog-home"):
		call_deferred("_debug_reopen_dog_home_panel")
	if startup_args.has("--adopt-dog") or user_args.has("--adopt-dog"):
		call_deferred("_on_dog_adoption_requested")
	if startup_args.has("--show-dog-interaction") or user_args.has("--show-dog-interaction"):
		call_deferred("_request_dog_interaction", false)
	if startup_args.has("--show-dragon-ride") or user_args.has("--show-dragon-ride"):
		call_deferred("_begin_dragon_ride_easter_egg")


func _process(delta: float) -> void:
	_comfort_cooldown = maxf(_comfort_cooldown - delta, 0.0)
	_dog_interaction_cooldown = maxf(_dog_interaction_cooldown - delta, 0.0)
	_scripted_dialogue_time_left = maxf(_scripted_dialogue_time_left - delta, 0.0)
	if state != State.SLEEP:
		if state != State.ACTIVITY:
			_speech_time_left -= delta
		if _bubble_time_left > 0.0:
			_bubble_time_left -= delta
			if _bubble_time_left <= 0.0:
				_bubble.clear_message()
				_update_passthrough()
		elif state != State.ACTIVITY and _speech_time_left <= 0.0:
			_say_random()
	_update_dog_runtime(delta)
	_update_music_runtime(delta)
	_update_proactive_context()
	if _dragon_launch_time_left > 0.0:
		_dragon_launch_time_left -= delta
		if _dragon_launch_time_left <= 0.0:
			_start_dragon_ride()
		return

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
	if state == State.ACTIVITY:
		if _active_activity == DRAGON_RIDE_ANIMATION:
			_update_dragon_flight(delta)
			if _state_duration > 0.0 and _state_time >= _state_duration:
				_finish_dragon_ride(false)
			return
		if _state_duration > 0.0 and _state_time >= _state_duration:
			_finish_activity()
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
	_care_panel.chat_requested.connect(_open_ai_chat_panel)
	add_child(_care_panel)

	_ai_chat_panel = AIChatPanel.new()
	_ai_chat_panel.name = "AIChatPanel"
	_ai_chat_panel.configure(_cjk_font, _care_system)
	_ai_chat_panel.assistant_replied.connect(_on_ai_assistant_replied)
	add_child(_ai_chat_panel)

	_proactive_companion = ProactiveCompanion.new()
	_proactive_companion.name = "ProactiveCompanion"
	_proactive_companion.configure(_care_system)
	_proactive_companion.message_ready.connect(_on_proactive_message)
	_proactive_companion.enabled_changed.connect(_on_proactive_enabled_changed)
	_proactive_companion.settings_changed.connect(_sync_companion_settings)
	add_child(_proactive_companion)

	_foreground_app_monitor = ForegroundAppMonitor.new()
	_foreground_app_monitor.name = "ForegroundAppMonitor"
	add_child(_foreground_app_monitor)
	_foreground_app_monitor.set_enabled(_proactive_companion.is_foreground_monitoring_enabled())

	_music_session_monitor = MusicSessionMonitor.new()
	_music_session_monitor.name = "MusicSessionMonitor"
	_music_session_monitor.track_changed.connect(_on_music_track_changed)
	_music_session_monitor.playback_changed.connect(_on_music_playback_changed)
	add_child(_music_session_monitor)

	_music_lyrics_service = MusicLyricsService.new()
	_music_lyrics_service.name = "MusicLyricsService"
	add_child(_music_lyrics_service)

	_music_player_panel = MusicPlayerPanel.new()
	_music_player_panel.name = "MusicPlayerPanel"
	_music_player_panel.configure(_cjk_font, _music_session_monitor, _music_lyrics_service)
	add_child(_music_player_panel)

	_screen_awareness_service = ScreenAwarenessService.new()
	_screen_awareness_service.name = "ScreenAwarenessService"
	_screen_awareness_service.analysis_ready.connect(_on_screen_analysis_ready)
	_screen_awareness_service.analysis_failed.connect(_on_screen_analysis_failed)
	_screen_awareness_service.settings_changed.connect(_sync_screen_monitoring)
	add_child(_screen_awareness_service)
	_sync_screen_monitoring()

	_companion_settings_panel = CompanionSettingsPanel.new()
	_companion_settings_panel.name = "CompanionSettingsPanel"
	_companion_settings_panel.configure(_cjk_font, _proactive_companion, _foreground_app_monitor, _screen_awareness_service)
	_companion_settings_panel.dragon_easter_egg_requested.connect(_on_dragon_easter_egg_requested)
	add_child(_companion_settings_panel)

	var pet_screen := DisplayServer.window_get_current_screen()
	if pet_screen < 0:
		pet_screen = 0
	_dog_companion = DogCompanion.new()
	_dog_companion.name = "DogCompanion"
	_dog_companion.configure(DisplayServer.window_get_position() + Vector2i(205, 205), pet_screen)
	_dog_companion.dog_clicked.connect(_on_dog_clicked)
	_dog_companion.home_requested.connect(_open_dog_home_panel)
	_dog_companion.owner_reached.connect(_on_dog_owner_reached)
	_dog_companion.availability_changed.connect(_on_dog_availability_changed)
	_dog_companion.name_changed.connect(_on_dog_name_changed)
	_dog_companion.care_message.connect(_on_dog_care_message)
	add_child(_dog_companion)

	_dog_home_panel = DogHomePanel.new()
	_dog_home_panel.name = "DogHomePanel"
	_dog_home_panel.configure(_cjk_font, _dog_companion.get_sprite_frames())
	_dog_home_panel.action_requested.connect(_on_dog_home_action)
	_dog_home_panel.adoption_requested.connect(_on_dog_adoption_requested)
	_dog_home_panel.name_change_requested.connect(_on_dog_name_change_requested)
	_dog_home_panel.home_toggle_requested.connect(_on_dog_home_toggle_requested)
	add_child(_dog_home_panel)

	_badminton_game = BadmintonGamePanel.new()
	_badminton_game.name = "BadmintonGame"
	_badminton_game.configure(_cjk_font, sprite.sprite_frames)
	_badminton_game.game_started.connect(_on_badminton_game_started)
	_badminton_game.game_finished.connect(_on_badminton_game_finished)
	_badminton_game.game_closed.connect(_on_badminton_game_closed)
	add_child(_badminton_game)


func _on_care_action_performed(result: Dictionary) -> void:
	if bool(result.get("success", false)) and _proactive_companion:
		var interaction := _describe_care_interaction(result)
		if not interaction.is_empty():
			_proactive_companion.note_interaction(interaction)
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
	var activity := String(result.get("activity", ""))
	if bool(result.get("success", false)) and not activity.is_empty():
		if activity == BADMINTON_ANIMATION:
			_open_badminton_game()
		else:
			_music_activity_live = false
			_active_activity = activity
			_enter_state(State.ACTIVITY)
	if bool(result.get("success", false)) and _care_feedback:
		_care_feedback.show_feedback(result.get("effect", "sparkle"), result.get("feedback", ""))


func _on_ai_assistant_replied(text: String) -> void:
	if _care_system:
		_care_system.apply_ai_chat_reward()
	if _proactive_companion:
		_proactive_companion.note_interaction("用户刚刚和你认真聊了一会儿")
	if state != State.SLEEP:
		var bubble_text := text.replace("\n", " ").strip_edges()
		if bubble_text.length() > 64:
			bubble_text = bubble_text.substr(0, 64) + "…"
		_show_bubble(bubble_text, 5.0, "💬")


func _on_proactive_message(text: String, emoji: String) -> void:
	if _scripted_dialogue_time_left > 0.0:
		return
	if _music_player_panel and _music_player_panel.is_fullscreen_active():
		_music_player_panel.show_listening_note(text, emoji)
		return
	_show_bubble(text, 8.0, emoji)


func _on_music_track_changed(info: Dictionary) -> void:
	var track_id := String(info.get("track_id", ""))
	var title := String(info.get("title", "")).strip_edges()
	if track_id.is_empty() or title.is_empty() or track_id == _last_music_track_id:
		return
	_last_music_track_id = track_id
	_music_reflection_time_left = _rng.randf_range(35.0, 55.0)
	if String(info.get("playback_status", "")) != "playing" or state == State.SLEEP:
		return
	_last_music_spoken_track_id = track_id
	var short_title := title.left(16) + ("…" if title.length() > 16 else "")
	if not _music_has_greeted:
		_music_has_greeted = true
		_on_proactive_message("原来你也在听《%s》呀，我陪你一起听 (^_^)" % short_title, "🎧")
	elif _rng.randf() < 0.58:
		var lines := [
			"换成《%s》啦，这首我也想听听。" % short_title,
			"《%s》响起来了，一起听吧 (*^_^*)" % short_title,
			"这首是《%s》呀，我来帮你轻轻打拍子。" % short_title
		]
		_on_proactive_message(String(lines[_rng.randi_range(0, lines.size() - 1)]), "🎵")
	if _proactive_companion:
		_proactive_companion.note_interaction("用户正在用%s听《%s》" % [String(info.get("source_label", "音乐播放器")), short_title])
		call_deferred("_request_music_thought_after_lyrics", track_id)


func _on_music_playback_changed(playing: bool, info: Dictionary) -> void:
	var track_id := String(info.get("track_id", ""))
	var title := String(info.get("title", "")).strip_edges()
	if not playing:
		if Time.get_ticks_msec() - _music_pause_spoken_at > 90000 and state != State.SLEEP:
			_music_pause_spoken_at = Time.get_ticks_msec()
			var paused_lines := [
				"暂停一下也好，刚才那句还在脑袋里转呢。",
				"音乐停住啦，我也把耳机轻轻摘下来。",
				"先安静一会儿吧，想继续时我还在。"
			]
			_on_proactive_message(String(paused_lines[_rng.randi_range(0, paused_lines.size() - 1)]), "🎧")
		return
	if track_id.is_empty() or title.is_empty() or track_id == _last_music_spoken_track_id or state == State.SLEEP:
		return
	_last_music_spoken_track_id = track_id
	_music_has_greeted = true
	var short_title := title.left(16) + ("…" if title.length() > 16 else "")
	_on_proactive_message("《%s》开始播放啦，我也戴好耳机了 (^_^)" % short_title, "🎧")
	if _proactive_companion:
		call_deferred("_request_music_thought_after_lyrics", track_id)


func _request_music_thought_after_lyrics(track_id: String) -> void:
	await get_tree().create_timer(5.0).timeout
	if not _proactive_companion or not _music_session_monitor or not _music_session_monitor.is_playing():
		return
	if String(_music_session_monitor.get_session().get("track_id", "")) != track_id:
		return
	_proactive_companion.request_music_thought_now()


func _show_music_companion_beat() -> void:
	if state == State.SLEEP or not _music_player_panel:
		return
	var context := _music_player_panel.get_music_context()
	if not bool(context.get("active", false)):
		return
	var title := String(context.get("title", "")).strip_edges()
	var lyric := String(context.get("current_lyric", "")).replace("\n", " ").strip_edges()
	var message := "我还在陪你听，悄悄跟着节奏晃一晃 ♪"
	var emoji := "🎧"
	if not lyric.is_empty():
		message = "刚才这句我听见啦：“%s” (*^_^*)" % lyric.left(24)
		emoji = "🎵"
	elif not title.is_empty():
		var short_title := title.left(16) + ("…" if title.length() > 16 else "")
		var lines: Array[String] = [
			"《%s》听到这里，心情也跟着软乎乎的。" % short_title,
			"还在听《%s》呀，我一直陪着你呢 (^_^)" % short_title,
			"这段节奏真好，我都忍不住轻轻打拍子啦。"
		]
		message = lines[_rng.randi_range(0, lines.size() - 1)]
	_on_proactive_message(message, emoji)


func _update_music_runtime(delta: float) -> void:
	if not _music_session_monitor:
		return
	var playing := _music_session_monitor.is_playing()
	if playing and _music_reflection_time_left > 0.0:
		_music_reflection_time_left -= delta
		if _music_reflection_time_left <= 0.0:
			_music_reflection_time_left = _rng.randf_range(45.0, 75.0)
			_show_music_companion_beat()
	if _music_activity_live and not playing:
		_music_activity_live = false
		if _active_activity == MUSIC_ANIMATION:
			_active_activity = ""
			if state == State.ACTIVITY:
				_enter_state(State.IDLE)
				_state_duration = 4.0
		return
	if not playing or state == State.SLEEP or state == State.WAKE:
		return
	if state == State.ACTIVITY:
		if _active_activity == MUSIC_ANIMATION and not _music_activity_live:
			_music_activity_live = true
			_state_duration = -1.0
		return
	if state != State.IDLE and state != State.WALK:
		return
	_music_activity_live = true
	_active_activity = MUSIC_ANIMATION
	_enter_state(State.ACTIVITY)
	_state_duration = -1.0


func _dog_display_name() -> String:
	return _dog_companion.get_display_name() if _dog_companion else "小狗"


func _update_dog_runtime(delta: float) -> void:
	if not _dog_companion:
		return
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = 0
	_dog_companion.set_owner_anchor(_get_dog_anchor(false), screen)
	if _dog_interaction_pending:
		_dog_interaction_pending_time -= delta
		if _dog_interaction_pending_time <= 0.0:
			_cancel_pending_dog_interaction()
			_schedule_next_dog_interaction(false)
		return
	if not _dog_companion.is_available():
		return
	_dog_auto_interaction_time -= delta
	if _dog_auto_interaction_time <= 0.0 and _can_start_automatic_dog_interaction():
		_request_dog_interaction(true)


func _get_dog_anchor(for_interaction: bool) -> Vector2i:
	var offset := Vector2i(94, 198) if for_interaction else Vector2i(170, 205)
	return DisplayServer.window_get_position() + offset


func _can_start_automatic_dog_interaction() -> bool:
	if state != State.IDLE or _dragging or _bubble_time_left > 0.0 or _dog_interaction_cooldown > 0.0:
		return false
	if _dragon_launch_time_left > 0.0 or not _active_activity.is_empty():
		return false
	if _context_menu and _context_menu.visible:
		return false
	if _care_panel and _care_panel.visible:
		return false
	if _ai_chat_panel and _ai_chat_panel.visible:
		return false
	if _companion_settings_panel and _companion_settings_panel.visible:
		return false
	if _dog_home_panel and _dog_home_panel.visible:
		return false
	if _badminton_game and _badminton_game.visible:
		return false
	return true


func _schedule_next_dog_interaction(initial: bool) -> void:
	if initial:
		_dog_auto_interaction_time = _rng.randf_range(DOG_AUTO_INTERACTION_INITIAL_MIN, DOG_AUTO_INTERACTION_INITIAL_MAX)
	else:
		_dog_auto_interaction_time = _rng.randf_range(DOG_AUTO_INTERACTION_MIN, DOG_AUTO_INTERACTION_MAX)


func _request_dog_interaction(spontaneous: bool) -> void:
	if not _dog_companion or not _dog_companion.is_available() or _dog_interaction_pending:
		return
	if state == State.ACTIVITY or _dragon_launch_time_left > 0.0:
		return
	if _dog_interaction_cooldown > 0.0 or not sprite.sprite_frames.has_animation(DOG_INTERACTION_ANIMATION):
		if not spontaneous:
			_show_bubble("%s刚玩累了，先让它喘口气吧 (ᵔᴥᵔ)" % _dog_display_name(), 3.2, "🐾")
		return
	_dog_interaction_pending = true
	_dog_interaction_pending_time = DOG_APPROACH_TIMEOUT
	_enter_state(State.IDLE)
	_state_duration = DOG_APPROACH_TIMEOUT + 1.0
	var approach_lines := [
		"%s，来这里～让我抱一下 (^_^)" % _dog_display_name(),
		"跑慢一点呀，过来陪我坐会儿 (≧▽≦)",
		"%s又来找我撒娇啦 (ᵔᴥᵔ)" % _dog_display_name()
	]
	var line: String = approach_lines[_rng.randi_range(0, approach_lines.size() - 1)]
	_show_bubble(line, 4.0, "🐾")
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = 0
	_dog_companion.request_owner_interaction(_get_dog_anchor(true), screen)


func _on_dog_clicked() -> void:
	if _proactive_companion:
		_proactive_companion.mark_user_activity()
		_proactive_companion.note_interaction("用户刚刚摸了摸白色小狗%s" % _dog_display_name())
	if state == State.SLEEP or state == State.WAKE:
		_enter_state(State.IDLE)
		_show_bubble("%s把我也叫醒啦……来一起玩吧 (－ω－)" % _dog_display_name(), 3.6, "🐾")
		return
	if state == State.ACTIVITY or _dragon_launch_time_left > 0.0:
		_show_bubble("%s在旁边乖乖等着呢 (ᵔᴥᵔ)" % _dog_display_name(), 3.2, "🐾")
		return
	_request_dog_interaction(false)


func _on_dog_owner_reached() -> void:
	if not _dog_interaction_pending:
		return
	_dog_interaction_pending = false
	_dog_interaction_pending_time = 0.0
	_start_dog_interaction()


func _cancel_pending_dog_interaction() -> void:
	if not _dog_interaction_pending:
		return
	_dog_interaction_pending = false
	_dog_interaction_pending_time = 0.0
	if _dog_companion:
		_dog_companion.cancel_owner_interaction()


func _start_dog_interaction() -> void:
	if not _dog_companion or not _dog_companion.is_available() or not sprite.sprite_frames.has_animation(DOG_INTERACTION_ANIMATION):
		return
	_dog_interaction_cooldown = 14.0
	_hide_bubble()
	_dog_companion.hide_for_interaction()
	_active_activity = DOG_INTERACTION_ANIMATION
	_enter_state(State.ACTIVITY)


func _restore_dog_after_interaction() -> void:
	if not _dog_companion:
		return
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = 0
	var beside_pet := _get_dog_anchor(false)
	_dog_companion.restore_after_interaction(beside_pet, screen)
	_schedule_next_dog_interaction(false)


func _on_dog_adoption_requested(requested_name: String = "测试小狗") -> void:
	if not _dog_companion or _dog_companion.is_adopted():
		return
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = 0
	if not _dog_companion.adopt(requested_name, _get_dog_anchor(false), screen):
		return
	var dog_name := _dog_companion.get_display_name()
	_dog_home_panel.hide_panel()
	_refresh_context_menu_dog_items()
	_schedule_next_dog_interaction(true)
	_scripted_dialogue_time_left = 5.0
	_enter_state(State.IDLE)
	_state_duration = 6.0
	_show_bubble("以后这里就是你的家啦。欢迎你，%s！ (^_^)" % dog_name, 5.0, "🐾")
	if _proactive_companion:
		_proactive_companion.note_interaction("用户刚刚和你一起领养了白色小狗%s" % dog_name)


func _on_dog_name_change_requested(requested_name: String) -> void:
	if not _dog_companion or not _dog_companion.is_adopted():
		return
	var previous_name := _dog_companion.get_display_name()
	if not _dog_companion.rename(requested_name):
		return
	var dog_name := _dog_companion.get_display_name()
	if dog_name != previous_name:
		_show_bubble("好呀，以后就叫你%s啦！ (^_^)" % dog_name, 4.0, "🐾")
		if _proactive_companion:
			_proactive_companion.note_interaction("用户把白色小狗的名字从%s改成了%s" % [previous_name, dog_name])


func _on_dog_name_changed(_dog_name: String) -> void:
	_refresh_context_menu_dog_items()
	if _dog_home_panel and _dog_companion:
		_dog_home_panel.refresh_state(_dog_companion.is_adopted(), _dog_companion.is_available(), _dog_companion.get_dog_name())


func _on_dog_home_toggle_requested() -> void:
	_toggle_dog_at_home()


func _toggle_dog_at_home() -> void:
	if not _dog_companion:
		return
	if not _dog_companion.is_adopted():
		_open_dog_home_panel()
		return
	_cancel_pending_dog_interaction()
	if _active_activity == DOG_INTERACTION_ANIMATION:
		_finish_activity()
	if _dog_companion.is_available():
		_dog_companion.send_home()
		_show_bubble("%s今天先回窝休息啦，晚点再叫它出来 (－ω－)" % _dog_display_name(), 4.2, "💤")
	else:
		var screen := DisplayServer.window_get_current_screen()
		if screen < 0:
			screen = 0
		_dog_companion.come_out(_get_dog_anchor(false), screen)
		_schedule_next_dog_interaction(true)
		_show_bubble("%s睡醒啦，又来陪我们玩了 (^o^)" % _dog_display_name(), 4.0, "🐾")
	_refresh_context_menu_dog_items()
	if _dog_home_panel:
		_dog_home_panel.refresh_state(_dog_companion.is_adopted(), _dog_companion.is_available(), _dog_companion.get_dog_name())


func _on_dog_availability_changed(adopted: bool, active: bool) -> void:
	_refresh_context_menu_dog_items()
	if _dog_home_panel:
		_dog_home_panel.refresh_state(adopted, active, _dog_companion.get_dog_name() if _dog_companion else "")
	_update_proactive_context()


func _on_dog_home_action(action: String) -> void:
	if _dog_companion:
		_dog_companion.perform_care(action)
	if _proactive_companion:
		_proactive_companion.mark_user_activity()
		_proactive_companion.note_interaction("用户刚刚在%s的小屋里照顾了它" % _dog_display_name())


func _on_dog_care_message(message: String, emoji: String) -> void:
	if state == State.SLEEP or state == State.WAKE:
		_enter_state(State.IDLE)
	_show_bubble(message, 4.0, emoji)


func _open_badminton_game() -> void:
	if not _badminton_game:
		return
	_cancel_pending_dog_interaction()
	if _proactive_companion:
		_proactive_companion.mark_user_activity()
	if _context_menu and _context_menu.visible:
		_context_menu.hide()
	if _care_panel and _care_panel.visible:
		_care_panel.hide_panel()
	if _ai_chat_panel and _ai_chat_panel.visible:
		_ai_chat_panel.hide_panel()
	if _companion_settings_panel and _companion_settings_panel.visible:
		_companion_settings_panel.hide_panel()
	if _dog_home_panel and _dog_home_panel.visible:
		_dog_home_panel.hide_panel()
	if _music_player_panel and _music_player_panel.visible:
		_music_player_panel.hide_panel()
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = 0
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var panel_size: Vector2i = _badminton_game.size
	var panel_position := usable.position + (usable.size - panel_size) / 2
	if not _badminton_game.visible:
		var pet_size := DisplayServer.window_get_size()
		var gap := 14
		var group_width := panel_size.x + gap + pet_size.x
		if group_width <= usable.size.x:
			var group_x := usable.position.x + (usable.size.x - group_width) / 2
			var current_pet_center := DisplayServer.window_get_position().x + pet_size.x / 2
			var pet_on_left := current_pet_center < usable.get_center().x
			panel_position.x = group_x + (pet_size.x + gap if pet_on_left else 0)
			_pet_position_before_badminton = DisplayServer.window_get_position()
			_pet_position_beside_badminton = Vector2i(
				group_x if pet_on_left else panel_position.x + panel_size.x + gap,
				clampi(panel_position.y + panel_size.y - pet_size.y, usable.position.y, usable.end.y - pet_size.y)
			)
			DisplayServer.window_set_position(_pet_position_beside_badminton)
			_window_position = Vector2(_pet_position_beside_badminton)
			_badminton_position_saved = true
	panel_position.x = clampi(panel_position.x, usable.position.x, usable.end.x - panel_size.x)
	panel_position.y = clampi(panel_position.y, usable.position.y, usable.end.y - panel_size.y)
	_badminton_game.open_at(panel_position)


func _on_badminton_game_started() -> void:
	_hide_bubble()
	_music_activity_live = false
	_active_activity = BADMINTON_ANIMATION
	_enter_state(State.ACTIVITY)
	_state_duration = -1.0


func _on_badminton_game_finished(player_won: bool, best_rally: int) -> void:
	if _care_system:
		_care_system.apply_badminton_result(player_won, best_rally)
	if _proactive_companion:
		var result_text := "用户刚刚在羽毛球小游戏里赢了你" if player_won else "你刚刚在羽毛球小游戏里赢了用户"
		_proactive_companion.note_interaction(result_text + "，最长打了%d个回合" % best_rally)
	_finish_badminton_activity()


func _on_badminton_game_closed() -> void:
	_finish_badminton_activity()
	_restore_pet_position_after_badminton()


func _finish_badminton_activity() -> void:
	if _active_activity != BADMINTON_ANIMATION and state != State.ACTIVITY:
		return
	_active_activity = ""
	_enter_state(State.IDLE)
	_state_duration = 4.0


func _restore_pet_position_after_badminton() -> void:
	if not _badminton_position_saved:
		return
	var current_position := DisplayServer.window_get_position()
	if Vector2(current_position).distance_to(Vector2(_pet_position_beside_badminton)) <= 4.0:
		DisplayServer.window_set_position(_pet_position_before_badminton)
		_window_position = Vector2(_pet_position_before_badminton)
	else:
		_window_position = Vector2(current_position)
	_badminton_position_saved = false


func _describe_care_interaction(result: Dictionary) -> String:
	var action := String(result.get("action", ""))
	var item_name := String(result.get("item_name", ""))
	match action:
		"meal":
			return "用户刚刚给你准备了" + item_name
		"drink":
			return "用户刚刚请你喝了" + item_name
		"play":
			return "用户刚刚陪你玩了" + item_name
		"gift":
			return "用户刚刚送给你" + item_name
		"comfort":
			return "用户刚刚温柔地摸了摸你"
		"rest":
			return "用户刚刚让你好好休息"
	return ""


func _update_proactive_context() -> void:
	if not _proactive_companion:
		return
	var menu_open: bool = _context_menu != null and _context_menu.visible
	var care_open: bool = _care_panel != null and _care_panel.visible
	var chat_open: bool = _ai_chat_panel != null and _ai_chat_panel.visible
	var settings_open: bool = _companion_settings_panel != null and _companion_settings_panel.visible
	var music_open: bool = _music_player_panel != null and _music_player_panel.visible
	var music_fullscreen: bool = music_open and _music_player_panel.is_fullscreen_active()
	var dog_home_open: bool = _dog_home_panel != null and _dog_home_panel.visible
	var badminton_open: bool = _badminton_game != null and _badminton_game.visible
	if _screen_awareness_service:
		_screen_awareness_service.set_auto_available(not menu_open and not care_open and not chat_open and not settings_open and not music_open and not dog_home_open and not badminton_open and not _dragging)
	var listening_state: bool = state == State.ACTIVITY and _active_activity == MUSIC_ANIMATION and _music_session_monitor != null and _music_session_monitor.is_playing()
	var quiet_state: bool = state == State.IDLE or state == State.WALK or listening_state
	var available: bool = quiet_state and not _dragging and (_bubble_time_left <= 0.0 or music_fullscreen) and not menu_open and not care_open and not chat_open and not settings_open and (not music_open or music_fullscreen) and not dog_home_open and not badminton_open
	var foreground_info := {}
	if _foreground_app_monitor and _foreground_app_monitor.is_enabled():
		foreground_info = _foreground_app_monitor.get_current_info()
	if _screen_awareness_service:
		_screen_awareness_service.set_foreground_context(foreground_info)
	if available and not _pending_screen_message.is_empty():
		var pending := _pending_screen_message
		_pending_screen_message = {}
		_on_proactive_message(String(pending.get("text", "")), String(pending.get("emoji", "👀")))
		available = false
	var music_info := {}
	if _music_player_panel:
		music_info = _music_player_panel.get_music_context()
	_proactive_companion.set_runtime_context({
		"available": available,
		"state": _proactive_state_name(),
		"foreground_app": foreground_info,
		"music": music_info,
		"dog_companion": {
			"adopted": _dog_companion != null and _dog_companion.is_adopted(),
			"active": _dog_companion != null and _dog_companion.is_available(),
			"name": _dog_companion.get_dog_name() if _dog_companion else ""
		}
	})


func _proactive_state_name() -> String:
	match state:
		State.IDLE:
			return "安静待机"
		State.WALK:
			return "在桌面散步"
		State.SLEEP:
			return "睡觉"
		State.WAKE:
			return "刚刚醒来"
		State.ACTIVITY:
			return "正在娱乐"
	return "待机"


func _open_dog_home_panel() -> void:
	if not _dog_home_panel:
		return
	_cancel_pending_dog_interaction()
	if _proactive_companion:
		_proactive_companion.mark_user_activity()
	if _context_menu and _context_menu.visible:
		_context_menu.hide()
	if _care_panel and _care_panel.visible:
		_care_panel.hide_panel()
	if _ai_chat_panel and _ai_chat_panel.visible:
		_ai_chat_panel.hide_panel()
	if _companion_settings_panel and _companion_settings_panel.visible:
		_companion_settings_panel.hide_panel()
	if _music_player_panel and _music_player_panel.visible:
		_music_player_panel.hide_panel()
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = 0
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var pet_position := DisplayServer.window_get_position()
	var pet_size := DisplayServer.window_get_size()
	var panel_size: Vector2i = _dog_home_panel.size
	var panel_x := pet_position.x + pet_size.x + 12
	if panel_x + panel_size.x > usable.end.x:
		panel_x = pet_position.x - panel_size.x - 12
	panel_x = clampi(panel_x, usable.position.x, usable.end.x - panel_size.x)
	var panel_y := clampi(pet_position.y - 25, usable.position.y, usable.end.y - panel_size.y)
	var adopted := _dog_companion != null and _dog_companion.is_adopted()
	var dog_active := _dog_companion != null and _dog_companion.is_available()
	var dog_name := _dog_companion.get_dog_name() if _dog_companion else ""
	_dog_home_panel.open_at(Vector2i(panel_x, panel_y), adopted, dog_active, dog_name)


func _debug_reopen_dog_home_panel() -> void:
	await get_tree().create_timer(0.35).timeout
	_open_dog_home_panel()


func _open_ai_chat_panel() -> void:
	if not _ai_chat_panel:
		return
	if _proactive_companion:
		_proactive_companion.mark_user_activity()
	if _context_menu and _context_menu.visible:
		_context_menu.hide()
	if _care_panel and _care_panel.visible:
		_care_panel.hide_panel()
	if _companion_settings_panel and _companion_settings_panel.visible:
		_companion_settings_panel.hide_panel()
	if _dog_home_panel and _dog_home_panel.visible:
		_dog_home_panel.hide_panel()
	if _music_player_panel and _music_player_panel.visible:
		_music_player_panel.hide_panel()
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = 0
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var pet_position := DisplayServer.window_get_position()
	var pet_size := DisplayServer.window_get_size()
	var panel_size: Vector2i = _ai_chat_panel.size
	var panel_x := pet_position.x + pet_size.x + 14
	if panel_x + panel_size.x > usable.end.x:
		panel_x = pet_position.x - panel_size.x - 14
	panel_x = clampi(panel_x, usable.position.x, usable.end.x - panel_size.x)
	var panel_y := clampi(pet_position.y - 190, usable.position.y, usable.end.y - panel_size.y)
	_ai_chat_panel.open_at(Vector2i(panel_x, panel_y))


func _open_care_panel() -> void:
	if not _care_panel:
		return
	if _proactive_companion:
		_proactive_companion.mark_user_activity()
	if _ai_chat_panel and _ai_chat_panel.visible:
		_ai_chat_panel.hide_panel()
	if _companion_settings_panel and _companion_settings_panel.visible:
		_companion_settings_panel.hide_panel()
	if _dog_home_panel and _dog_home_panel.visible:
		_dog_home_panel.hide_panel()
	if _music_player_panel and _music_player_panel.visible:
		_music_player_panel.hide_panel()
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


func _open_companion_settings(page := "companion") -> void:
	if not _companion_settings_panel:
		return
	if _proactive_companion:
		_proactive_companion.mark_user_activity()
	if _context_menu and _context_menu.visible:
		_context_menu.hide()
	if _care_panel and _care_panel.visible:
		_care_panel.hide_panel()
	if _ai_chat_panel and _ai_chat_panel.visible:
		_ai_chat_panel.hide_panel()
	if _dog_home_panel and _dog_home_panel.visible:
		_dog_home_panel.hide_panel()
	if _music_player_panel and _music_player_panel.visible:
		_music_player_panel.hide_panel()
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = 0
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var pet_position := DisplayServer.window_get_position()
	var pet_size := DisplayServer.window_get_size()
	var panel_size: Vector2i = _companion_settings_panel.size
	var panel_x := pet_position.x + pet_size.x + 12
	if panel_x + panel_size.x > usable.end.x:
		panel_x = pet_position.x - panel_size.x - 12
	panel_x = clampi(panel_x, usable.position.x, usable.end.x - panel_size.x)
	var panel_y := clampi(pet_position.y - 80, usable.position.y, usable.end.y - panel_size.y)
	_companion_settings_panel.open_at(Vector2i(panel_x, panel_y), page)


func _open_music_player() -> void:
	if not _music_player_panel:
		return
	if _proactive_companion:
		_proactive_companion.mark_user_activity()
	if _context_menu and _context_menu.visible:
		_context_menu.hide()
	if _care_panel and _care_panel.visible:
		_care_panel.hide_panel()
	if _ai_chat_panel and _ai_chat_panel.visible:
		_ai_chat_panel.hide_panel()
	if _companion_settings_panel and _companion_settings_panel.visible:
		_companion_settings_panel.hide_panel()
	if _dog_home_panel and _dog_home_panel.visible:
		_dog_home_panel.hide_panel()
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = 0
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var pet_position := DisplayServer.window_get_position()
	var pet_size := DisplayServer.window_get_size()
	var panel_size: Vector2i = _music_player_panel.size
	var panel_x := pet_position.x + pet_size.x + 14
	if panel_x + panel_size.x > usable.end.x:
		panel_x = pet_position.x - panel_size.x - 14
	panel_x = clampi(panel_x, usable.position.x, usable.end.x - panel_size.x)
	var panel_y := clampi(pet_position.y - 70, usable.position.y, usable.end.y - panel_size.y)
	_music_player_panel.open_at(Vector2i(panel_x, panel_y))


func _debug_open_music_fullscreen() -> void:
	_open_music_player()
	await get_tree().process_frame
	await get_tree().process_frame
	_music_player_panel.enter_fullscreen()


func _open_screen_awareness() -> void:
	_open_companion_settings("awareness")


func _on_screen_analysis_ready(result: Dictionary) -> void:
	var speech := String(result.get("text", "")).strip_edges()
	var suggestion := String(result.get("suggestion", "")).strip_edges()
	if speech.is_empty():
		speech = suggestion
	if bool(result.get("should_speak", result.get("speak", false))) and not speech.is_empty() and state != State.SLEEP:
		_pending_screen_message = {"text": speech, "emoji": String(result.get("emoji", "👀"))}
	if _proactive_companion and not suggestion.is_empty():
		_proactive_companion.note_interaction("画面感知理解了当前任务并给出一条即时建议")


func _on_screen_analysis_failed(message: String) -> void:
	if state != State.SLEEP and _screen_awareness_service and _screen_awareness_service.get_last_observation_reason() == "manual":
		_on_proactive_message(message, "👀")


func _on_dragon_easter_egg_requested() -> void:
	if _companion_settings_panel and _companion_settings_panel.visible:
		_companion_settings_panel.hide_panel()
	if _dog_home_panel and _dog_home_panel.visible:
		_dog_home_panel.hide_panel()
	if _proactive_companion:
		_proactive_companion.mark_user_activity()
		_proactive_companion.note_interaction("用户发现了藏在设置里的骑龙彩蛋")
	_begin_dragon_ride_easter_egg()


func _begin_dragon_ride_easter_egg() -> void:
	if _dragon_launch_time_left > 0.0 or _active_activity == DRAGON_RIDE_ANIMATION:
		return
	_cancel_pending_dog_interaction()
	if not sprite.sprite_frames or not sprite.sprite_frames.has_animation(DRAGON_RIDE_ANIMATION):
		if state == State.SLEEP or state == State.WAKE:
			_enter_state(State.IDLE)
		_show_bubble("唔，龙好像还没睡醒……", 3.2, "?")
		return
	if _badminton_game and _badminton_game.visible:
		return
	if _care_panel and _care_panel.visible:
		_care_panel.hide_panel()
	if _ai_chat_panel and _ai_chat_panel.visible:
		_ai_chat_panel.hide_panel()
	if _context_menu and _context_menu.visible:
		_context_menu.hide()
	if _active_activity == DOG_INTERACTION_ANIMATION:
		_restore_dog_after_interaction()
	_active_activity = ""
	_enter_state(State.IDLE)
	_state_duration = DRAGON_LAUNCH_DELAY + 1.0
	_dragon_launch_time_left = DRAGON_LAUNCH_DELAY
	_scripted_dialogue_time_left = DRAGON_LAUNCH_DELAY + 0.5
	_show_bubble("嘘……你找到秘密通道啦。抓稳咯！", 2.4, "🐉")


func _start_dragon_ride() -> void:
	_dragon_launch_time_left = 0.0
	_hide_bubble()
	_dragon_origin_position = Vector2(DisplayServer.window_get_position())
	_dragon_flight_position = _dragon_origin_position
	_dragon_flight_screen = DisplayServer.window_get_current_screen()
	if _dragon_flight_screen < 0:
		_dragon_flight_screen = 0
	var usable := DisplayServer.screen_get_usable_rect(_dragon_flight_screen)
	var window_center_y := _dragon_flight_position.y + DisplayServer.window_get_size().y * 0.5
	var vertical_direction := -0.16 if window_center_y > usable.get_center().y else 0.16
	_dragon_flight_direction = Vector2(1.0, vertical_direction).normalized()
	_dragon_flight_phase = 0.0
	sprite.rotation = 0.0
	sprite.scale = Vector2.ONE * SPRITE_SCALE
	sprite.flip_h = false
	_active_activity = DRAGON_RIDE_ANIMATION
	_enter_state(State.ACTIVITY)


func _update_dragon_flight(delta: float) -> void:
	var usable := DisplayServer.screen_get_usable_rect(_dragon_flight_screen)
	var window_size := DisplayServer.window_get_size()
	var min_y := float(usable.position.y)
	var max_y := float(usable.end.y - window_size.y)
	_dragon_flight_position += _dragon_flight_direction * DRAGON_FLIGHT_SPEED * delta

	var wrap_left := float(usable.position.x - window_size.x + 20)
	var wrap_right := float(usable.end.x + 20)
	if _dragon_flight_position.x > wrap_right:
		_dragon_flight_position.x = wrap_left
	if _dragon_flight_position.y <= min_y:
		_dragon_flight_position.y = min_y
		_dragon_flight_direction.y = absf(_dragon_flight_direction.y)
	elif _dragon_flight_position.y >= max_y:
		_dragon_flight_position.y = max_y
		_dragon_flight_direction.y = -absf(_dragon_flight_direction.y)
	_dragon_flight_direction = _dragon_flight_direction.normalized()

	_dragon_flight_phase += delta * DRAGON_FLIGHT_BOB_SPEED
	var display_position := _dragon_flight_position + Vector2(0.0, sin(_dragon_flight_phase) * DRAGON_FLIGHT_BOB_HEIGHT)
	display_position.y = clampf(display_position.y, min_y, max_y)
	_window_position = display_position
	DisplayServer.window_set_position(Vector2i(display_position.round()))


func _finish_dragon_ride(interrupted: bool) -> void:
	_dragon_launch_time_left = 0.0
	_active_activity = ""
	sprite.rotation = 0.0
	sprite.scale = Vector2.ONE * SPRITE_SCALE
	sprite.flip_h = false
	var usable := DisplayServer.screen_get_usable_rect(_dragon_flight_screen)
	var window_size := DisplayServer.window_get_size()
	var restored := Vector2i(
		clampi(roundi(_dragon_origin_position.x), usable.position.x, usable.end.x - window_size.x),
		clampi(roundi(_dragon_origin_position.y), usable.position.y, usable.end.y - window_size.y)
	)
	_window_position = Vector2(restored)
	DisplayServer.window_set_position(restored)
	_enter_state(State.IDLE)
	_state_duration = 5.0
	var message := "好啦，提前降落。下次再出发吧！" if interrupted else "平安着陆！刚才是不是超帅的？"
	_scripted_dialogue_time_left = 4.0
	_show_bubble(message, 3.8, "🐉")


func _on_proactive_enabled_changed(enabled: bool) -> void:
	if not _context_menu:
		return
	var index := _context_menu.get_item_index(MENU_TOGGLE_PROACTIVE)
	if index >= 0:
		_context_menu.set_item_checked(index, enabled)


func _sync_companion_settings() -> void:
	_sync_screen_monitoring()
	_on_proactive_enabled_changed(_proactive_companion.is_enabled() if _proactive_companion else false)


func _sync_screen_monitoring() -> void:
	if not _foreground_app_monitor:
		return
	var companion_monitoring := _proactive_companion != null and _proactive_companion.is_foreground_monitoring_enabled()
	var screen_monitoring := _screen_awareness_service != null and _screen_awareness_service.is_enabled()
	_foreground_app_monitor.set_enabled(companion_monitoring or screen_monitoring)


func _show_bubble(message: String, duration := 2.8, emoji := "") -> void:
	if state == State.SLEEP:
		return
	if state == State.ACTIVITY and _active_activity != MUSIC_ANIMATION:
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
	if _dog_companion and _dog_companion.is_available() and _rng.randf() < 0.45:
		var dog_line: Dictionary = _dog_dialogue_lines[_rng.randi_range(0, _dog_dialogue_lines.size() - 1)]
		var dog_text := String(dog_line["text"]).replace("{dog}", _dog_display_name())
		_show_bubble(dog_text, duration + 0.4, dog_line["emoji"])
		return
	var line: Dictionary = _bubble_lines[_rng.randi_range(0, _bubble_lines.size() - 1)]
	_show_bubble(line["text"], duration, line["emoji"])


func _schedule_next_speech() -> void:
	_speech_time_left = _rng.randf_range(70.0, 130.0)


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
	_context_menu.add_item("音乐中心", MENU_MUSIC)
	_context_menu.add_item("小狗的小屋", MENU_DOG_HOME)
	_context_menu.add_item("让小狗回窝", MENU_DOG_TOGGLE)
	_context_menu.add_separator()
	_context_menu.add_item("和她说说话", MENU_TALK)
	_context_menu.add_check_item("自动散步", MENU_TOGGLE_WANDER)
	_context_menu.set_item_checked(_context_menu.get_item_index(MENU_TOGGLE_WANDER), true)
	_context_menu.add_check_item("主动陪伴", MENU_TOGGLE_PROACTIVE)
	_context_menu.set_item_checked(_context_menu.get_item_index(MENU_TOGGLE_PROACTIVE), _proactive_companion != null and _proactive_companion.is_enabled())
	_context_menu.add_item("陪伴设置", MENU_COMPANION_SETTINGS)
	_context_menu.add_item("回到屏幕中央", MENU_CENTER)
	_context_menu.add_item("让她睡觉", MENU_SLEEP)
	_context_menu.add_separator()
	_context_menu.add_item("退出桌宠", MENU_EXIT)
	_style_context_menu()
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	_context_menu.popup_hide.connect(_on_context_menu_closed)
	add_child(_context_menu)
	_refresh_context_menu_dog_items()


func _style_context_menu() -> void:
	var panel := StyleBoxTexture.new()
	panel.texture = load(CARE_UI_DIR + "/context_menu_panel.png") as Texture2D
	panel.texture_margin_left = 24.0
	panel.texture_margin_top = 74.0
	panel.texture_margin_right = 24.0
	panel.texture_margin_bottom = 28.0
	panel.content_margin_left = 24.0
	panel.content_margin_top = 76.0
	panel.content_margin_right = 24.0
	panel.content_margin_bottom = 24.0
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
	_context_menu.set_item_icon(_context_menu.get_item_index(MENU_MUSIC), load("res://assets/care/runtime/items/headphones.png") as Texture2D)
	_context_menu.set_item_icon(_context_menu.get_item_index(MENU_DOG_HOME), load("res://assets/dog/source/blue_ui/1-animations/textures/4_spritesheet.png") as Texture2D)
	_context_menu.set_item_icon(_context_menu.get_item_index(MENU_DOG_TOGGLE), load("res://assets/dog/source/furniture/1-animations/textures/1_spritesheet.png") as Texture2D)
	_context_menu.set_item_icon(_context_menu.get_item_index(MENU_TALK), _load_ui_texture(17))
	_context_menu.set_item_icon(_context_menu.get_item_index(MENU_TOGGLE_WANDER), _load_ui_texture(10))
	_context_menu.set_item_icon(_context_menu.get_item_index(MENU_TOGGLE_PROACTIVE), load(CARE_UI_DIR + "/action_chat.png") as Texture2D)
	_context_menu.set_item_icon(_context_menu.get_item_index(MENU_COMPANION_SETTINGS), load("res://assets/companion/runtime/ui/37_spritesheet.png") as Texture2D)
	_context_menu.set_item_icon(_context_menu.get_item_index(MENU_CENTER), _load_ui_texture(6))
	_context_menu.set_item_icon(_context_menu.get_item_index(MENU_SLEEP), _load_ui_texture(18))
	_context_menu.set_item_icon(_context_menu.get_item_index(MENU_EXIT), _load_ui_texture(28))


func _load_ui_texture(number: int) -> Texture2D:
	return load(UI_TEXTURE_DIR + "/" + str(number) + "_spritesheet.png") as Texture2D


func _refresh_context_menu_dog_items() -> void:
	if not _context_menu or not _dog_companion:
		return
	var home_index := _context_menu.get_item_index(MENU_DOG_HOME)
	var toggle_index := _context_menu.get_item_index(MENU_DOG_TOGGLE)
	if not _dog_companion.is_adopted():
		_context_menu.set_item_text(home_index, "去领养一只小狗")
		_context_menu.set_item_text(toggle_index, "尚未领养小狗")
		_context_menu.set_item_disabled(toggle_index, true)
	else:
		var dog_name := _dog_companion.get_display_name()
		_context_menu.set_item_text(home_index, dog_name + "的小屋")
		_context_menu.set_item_text(toggle_index, ("让%s回窝" % dog_name) if _dog_companion.is_available() else ("叫%s出来" % dog_name))
		_context_menu.set_item_disabled(toggle_index, false)


func _open_context_menu() -> void:
	_cancel_pending_dog_interaction()
	if _active_activity == DOG_INTERACTION_ANIMATION:
		_finish_activity()
	_dragging = false
	_finish_drag_visual()
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
	_refresh_context_menu_dog_items()
	var mouse_position := DisplayServer.mouse_get_position()
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = 0
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var content_size := _context_menu.get_contents_minimum_size()
	var menu_size := Vector2i(maxi(roundi(content_size.x), 224), maxi(roundi(content_size.y), 190))
	var character_bounds := _get_character_screen_bounds()
	var right_position := Vector2i(roundi(character_bounds.end.x + 6.0), mouse_position.y - menu_size.y / 3)
	var left_position := Vector2i(roundi(character_bounds.position.x - menu_size.x - 6.0), mouse_position.y - menu_size.y / 3)
	var popup_position := right_position
	if popup_position.x + menu_size.x > usable.end.x:
		popup_position = left_position
	popup_position.x = mini(popup_position.x, usable.end.x - menu_size.x)
	popup_position.x = maxi(popup_position.x, usable.position.x)
	popup_position.y = clampi(popup_position.y, usable.position.y, usable.end.y - menu_size.y)
	_context_menu.position = popup_position
	_context_menu.popup()
	DisplayServer.window_set_position(popup_position, _context_menu.get_window_id())


func _get_character_screen_bounds() -> Rect2:
	var fallback := Rect2(sprite.position - Vector2(128.0, 128.0) * SPRITE_SCALE, Vector2(256.0, 256.0) * SPRITE_SCALE)
	var anim := sprite.animation
	if not _frame_polygons.has(anim):
		return Rect2(Vector2(DisplayServer.window_get_position()) + fallback.position, fallback.size)
	var polygons: Array = _frame_polygons[anim]
	var frame := sprite.frame
	if frame < 0 or frame >= polygons.size() or polygons[frame].is_empty():
		return Rect2(Vector2(DisplayServer.window_get_position()) + fallback.position, fallback.size)
	var local_bounds := Rect2(polygons[frame][0], Vector2.ZERO)
	for point in polygons[frame]:
		local_bounds = local_bounds.expand(point)
	return Rect2(Vector2(DisplayServer.window_get_position()) + local_bounds.position, local_bounds.size)


func _on_context_menu_id_pressed(id: int) -> void:
	match id:
		MENU_CARE:
			_open_care_panel()
		MENU_MUSIC:
			_open_music_player()
		MENU_DOG_HOME:
			_open_dog_home_panel()
		MENU_DOG_TOGGLE:
			_toggle_dog_at_home()
		MENU_TALK:
			_open_ai_chat_panel()
		MENU_TOGGLE_WANDER:
			_wandering_enabled = not _wandering_enabled
			var index := _context_menu.get_item_index(MENU_TOGGLE_WANDER)
			_context_menu.set_item_checked(index, _wandering_enabled)
			_enter_state(State.IDLE)
			_show_bubble("那就出发吧！" if _wandering_enabled else "好呀，我先在这里休息～")
		MENU_TOGGLE_PROACTIVE:
			if _proactive_companion:
				_proactive_companion.set_enabled(not _proactive_companion.is_enabled())
				var index := _context_menu.get_item_index(MENU_TOGGLE_PROACTIVE)
				_context_menu.set_item_checked(index, _proactive_companion.is_enabled())
				if _proactive_companion.is_enabled():
					_show_bubble("我会偶尔主动来找你说话的～", 3.4, "🌸")
				else:
					_show_bubble("好呀，我先安静陪着你。", 3.4, "🌙")
		MENU_COMPANION_SETTINGS:
			_open_companion_settings()
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
	_load_activity_animations(frames)
	_load_dog_interaction_animation(frames)
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


func _load_activity_animations(frames: SpriteFrames) -> void:
	var root := DirAccess.open(ACTIVITY_DIR)
	if root == null:
		return
	root.list_dir_begin()
	var activity_dir := root.get_next()
	while activity_dir != "":
		if root.current_is_dir() and not activity_dir.begins_with("."):
			var frames_path := _find_frames_resource(ACTIVITY_DIR + "/" + activity_dir)
			if not frames_path.is_empty():
				var source := load(frames_path) as SpriteFrames
				if source:
					for source_animation in source.get_animation_names():
						if source.get_frame_count(source_animation) > 0:
							var target_name := activity_dir.to_lower()
							_copy_animation(frames, target_name, source, source_animation)
							frames.set_animation_loop(target_name, ACTIVITY_DURATIONS.has(target_name))
							frames.set_animation_speed(target_name, float(ACTIVITY_SPEEDS.get(target_name, 7.0)))
							break
		activity_dir = root.get_next()
	root.list_dir_end()


func _load_dog_interaction_animation(frames: SpriteFrames) -> void:
	var source := load(DOG_INTERACTION_FRAMES_PATH) as SpriteFrames
	if not source:
		return
	for source_animation in source.get_animation_names():
		if source.get_frame_count(source_animation) <= 0:
			continue
		_copy_animation(frames, DOG_INTERACTION_ANIMATION, source, source_animation)
		frames.set_animation_loop(DOG_INTERACTION_ANIMATION, true)
		frames.set_animation_speed(DOG_INTERACTION_ANIMATION, float(ACTIVITY_SPEEDS[DOG_INTERACTION_ANIMATION]))
		break


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
		State.ACTIVITY:
			_state_duration = float(ACTIVITY_DURATIONS.get(_active_activity, 0.0))
			_play(_active_activity)


func _finish_activity() -> void:
	if _active_activity == DRAGON_RIDE_ANIMATION:
		_finish_dragon_ride(false)
		return
	var completed_activity := _active_activity
	if completed_activity == MUSIC_ANIMATION:
		_music_activity_live = false
	_active_activity = ""
	_enter_state(State.IDLE)
	_state_duration = 4.0
	if completed_activity == DOG_INTERACTION_ANIMATION:
		_restore_dog_after_interaction()
		var dog_line: Dictionary = _dog_dialogue_lines[_rng.randi_range(0, _dog_dialogue_lines.size() - 1)]
		var dog_text := String(dog_line["text"]).replace("{dog}", _dog_display_name())
		_show_bubble(dog_text, 4.2, dog_line["emoji"])
		if _proactive_companion:
			_proactive_companion.note_interaction("你刚刚主动抱了抱%s，和它玩了一会儿" % _dog_display_name())


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
	elif sprite.sprite_frames:
		var available_animations := sprite.sprite_frames.get_animation_names()
		if not available_animations.is_empty():
			# 找不到指定动画时退回到第一个可用动画，避免黑屏。
			sprite.play(available_animations[0])


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
	if state == State.ACTIVITY and _state_duration <= 0.0:
		_finish_activity()
	elif state == State.SLEEP and sprite.animation == SLEEP_ENTER_ANIMATION:
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
		if _badminton_game and _badminton_game.visible:
			return
		get_tree().quit()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _suppress_next_left_release:
		_suppress_next_left_release = false
		return
	if state == State.ACTIVITY and _active_activity == DRAGON_RIDE_ANIMATION and event is InputEventMouse:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_suppress_next_left_release = true
			_finish_dragon_ride(true)
		return
	if _dragon_launch_time_left > 0.0 and event is InputEventMouse:
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
			_cancel_pending_dog_interaction()
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
	if _active_activity == DOG_INTERACTION_ANIMATION:
		return
	# 点击后给桌宠一段安静的回应，避免立刻被自动闲逛打断。
	if state == State.SLEEP:
		if _proactive_companion:
			_proactive_companion.note_interaction("用户刚刚轻轻把你叫醒")
		_enter_state(State.WAKE)
		_show_bubble("唔……你叫我呀？", 3.0, "💤")
		return
	if state == State.WAKE:
		if _proactive_companion:
			_proactive_companion.mark_user_activity()
		return
	if _proactive_companion:
		_proactive_companion.mark_user_activity()
	if _care_system and _comfort_cooldown <= 0.0:
		_comfort_cooldown = 8.0
		_care_system.perform_action("comfort")
		return
	_enter_state(State.IDLE)
	_state_duration = 5.5
	_say_random()
