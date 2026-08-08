extends Window
class_name PetBadmintonGame

signal game_started
signal game_finished(player_won: bool, best_rally: int)
signal game_closed

const GAME_SIZE := Vector2i(960, 720)
const ASSET_DIR := "res://assets/minigames/badminton/runtime"
const UI_DIR := ASSET_DIR + "/ui"
const WIN_SCORE := 5
const PLAYER_DEPTH := 0.04
const PET_DEPTH := 0.86
const PET_SCALE := 0.68
const DIFFICULTIES := {
	"easy": {
		"label": "轻松局",
		"pet_speed": 1.45,
		"return_chance": 0.73,
		"shot_time": 1.32,
		"shot_spread": 0.48
	},
	"normal": {
		"label": "认真局",
		"pet_speed": 2.05,
		"return_chance": 0.88,
		"shot_time": 1.10,
		"shot_spread": 0.72
	},
	"hard": {
		"label": "挑战局",
		"pet_speed": 2.75,
		"return_chance": 0.96,
		"shot_time": 0.91,
		"shot_spread": 0.90
	}
}

enum Phase { MENU, SERVE_DELAY, TO_PLAYER, TO_PET, POINT_DELAY, PAUSED, FINISHED }

var _font: Font
var _pet_frames: SpriteFrames
var _rng := RandomNumberGenerator.new()
var _root: Control
var _background: TextureRect
var _play_layer: Node2D
var _effect_layer: Node2D
var _hud: Control
var _modal: Control
var _pet_sprite: AnimatedSprite2D
var _shuttle: Sprite2D
var _landing_marker: Sprite2D
var _racket: Sprite2D
var _score_player: Label
var _score_pet: Label
var _round_label: Label
var _status_panel: TextureRect
var _status_label: Label
var _combo_panel: TextureRect
var _combo_label: Label
var _smash_meter: TextureProgressBar
var _smash_label: Label
var _difficulty_buttons: Dictionary = {}
var _difficulty_selected_label: Label
var _button_tweens: Dictionary = {}

var _phase: int = Phase.MENU
var _phase_before_pause: int = Phase.MENU
var _difficulty := "normal"
var _game_active := false
var _result_emitted := false
var _match_over_pending := false
var _player_score := 0
var _pet_score := 0
var _rally := 0
var _best_rally := 0
var _combo := 0
var _smash_power := 0.0
var _serve_delay := 0.0
var _point_delay := 0.0
var _status_time := 0.0
var _swing_cooldown := 0.0
var _pet_swing_time := 0.0

var _flight_elapsed := 0.0
var _flight_duration := 1.0
var _flight_from_x := 0.0
var _flight_target_x := 0.0
var _flight_from_depth := PET_DEPTH
var _flight_target_depth := PLAYER_DEPTH
var _flight_start_height := 0.35
var _flight_end_height := 0.04
var _flight_peak := 0.78
var _flight_power := 0.5
var _flight_smash := false

var _pet_x := 0.0
var _pet_target_x := 0.0
var _racket_position := Vector2(480, 575)
var _last_racket_position := Vector2(480, 575)
var _racket_velocity := Vector2.ZERO


func _init() -> void:
	visible = false
	title = "桌面羽毛球"
	size = GAME_SIZE
	min_size = GAME_SIZE
	content_scale_size = GAME_SIZE
	content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	content_scale_factor = 1.0
	borderless = true
	transparent_bg = false
	unresizable = true
	always_on_top = false
	force_native = true


func configure(font: Font, pet_frames: SpriteFrames) -> void:
	_font = font
	_pet_frames = pet_frames


func _ready() -> void:
	_rng.randomize()
	close_requested.connect(_close_game)
	_build_ui()
	_show_start_menu()


func open_at(screen_position: Vector2i) -> void:
	position = screen_position
	mode = Window.MODE_WINDOWED
	show()
	grab_focus()
	if _phase == Phase.FINISHED or _phase == Phase.MENU:
		_show_start_menu()
	_play_open_animation()


func hide_game() -> void:
	_close_game()


func is_match_active() -> bool:
	return _game_active


func _process(delta: float) -> void:
	if not visible:
		return
	_update_racket(delta)
	_update_pet(delta)
	_update_status(delta)
	_swing_cooldown = maxf(_swing_cooldown - delta, 0.0)
	if _pet_swing_time > 0.0:
		_pet_swing_time -= delta
		if _pet_swing_time <= 0.0:
			_play_pet_idle()

	match _phase:
		Phase.SERVE_DELAY:
			_serve_delay -= delta
			if _serve_delay <= 0.0:
				_pet_swing()
				_launch_to_player()
		Phase.TO_PLAYER, Phase.TO_PET:
			_update_flight(delta)
		Phase.POINT_DELAY:
			_point_delay -= delta
			if _point_delay <= 0.0:
				if _match_over_pending:
					_finish_match()
				else:
					_begin_point()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "BadmintonRoot"
	_root.size = Vector2(GAME_SIZE)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_root_gui_input)
	add_child(_root)

	_background = TextureRect.new()
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.texture = load(ASSET_DIR + "/court.png") as Texture2D
	_background.position = Vector2.ZERO
	_background.stretch_mode = TextureRect.STRETCH_SCALE
	_background.size = Vector2(GAME_SIZE)
	_background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_background)

	var shade := ColorRect.new()
	shade.position = Vector2.ZERO
	shade.size = Vector2(GAME_SIZE)
	shade.color = Color(0.08, 0.06, 0.08, 0.06)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)

	_play_layer = Node2D.new()
	_play_layer.name = "PlayLayer"
	_root.add_child(_play_layer)
	_effect_layer = Node2D.new()
	_effect_layer.name = "EffectLayer"
	_root.add_child(_effect_layer)
	_build_play_sprites()

	_hud = Control.new()
	_hud.name = "HUD"
	_hud.size = Vector2(GAME_SIZE)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hud)
	_build_hud()

	_modal = Control.new()
	_modal.name = "Modal"
	_modal.size = Vector2(GAME_SIZE)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_modal)


func _build_play_sprites() -> void:
	_pet_sprite = AnimatedSprite2D.new()
	_pet_sprite.name = "PetOpponent"
	_pet_sprite.sprite_frames = _pet_frames
	_pet_sprite.scale = Vector2.ONE * PET_SCALE
	_pet_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_play_layer.add_child(_pet_sprite)
	_play_pet_idle()

	_landing_marker = Sprite2D.new()
	_landing_marker.texture = _ui_texture("landing_marker.png")
	_landing_marker.scale = Vector2(0.23, 0.23)
	_landing_marker.modulate = Color(1, 1, 1, 0.72)
	_landing_marker.visible = false
	_play_layer.add_child(_landing_marker)

	_shuttle = Sprite2D.new()
	_shuttle.texture = _ui_texture("shuttle_down.png")
	_shuttle.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shuttle.visible = false
	_play_layer.add_child(_shuttle)

	_racket = Sprite2D.new()
	_racket.texture = _ui_texture("racket.png")
	_racket.scale = Vector2.ONE * 0.20
	_racket.position = _racket_position
	_racket.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_racket.visible = false
	_play_layer.add_child(_racket)


func _build_hud() -> void:
	var scoreboard := _make_texture_rect(_hud, "scoreboard.png", Vector2(155, 12), Vector2(650, 96))
	scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_player = _make_label(_hud, "你  0", Vector2(218, 39), Vector2(190, 42), 25, Color("7d4757"))
	_score_pet = _make_label(_hud, "她  0", Vector2(552, 39), Vector2(190, 42), 25, Color("48635d"))
	_round_label = _make_label(_hud, "5", Vector2(445, 39), Vector2(70, 42), 23, Color("7a5260"))

	var pause_button := _make_icon_button(_root, "pause.png", Vector2(852, 18), Vector2(58, 58), "暂停", _toggle_pause)
	pause_button.mouse_filter = Control.MOUSE_FILTER_STOP
	var exit_button := _make_icon_button(_root, "exit.png", Vector2(906, 18), Vector2(48, 48), "结束游戏", _close_game)
	exit_button.mouse_filter = Control.MOUSE_FILTER_STOP

	# Keep match callouts away from the opponent and preserve the source panel ratio.
	_status_panel = _make_texture_rect(_hud, "small_panel.png", Vector2(18, 108), Vector2(218, 142))
	_status_label = _make_label(_status_panel, "准备发球", Vector2(21, 48), Vector2(176, 42), 20, Color("754b59"))
	_status_panel.visible = false

	_combo_panel = _make_texture_rect(_hud, "small_panel.png", Vector2(770, 596), Vector2(174, 114))
	_combo_label = _make_label(_combo_panel, "连击  0", Vector2(18, 38), Vector2(138, 36), 19, Color("754b59"))

	_smash_meter = TextureProgressBar.new()
	_smash_meter.position = Vector2(18, 636)
	_smash_meter.min_value = 0.0
	_smash_meter.max_value = 100.0
	_smash_meter.value = 0.0
	_smash_meter.texture_under = _ui_texture("smash_meter.png")
	_smash_meter.texture_progress = _ui_texture("smash_meter.png")
	_smash_meter.size = Vector2(921, 192)
	_smash_meter.scale = Vector2.ONE * 0.39
	_smash_meter.tint_under = Color(0.66, 0.61, 0.64, 0.68)
	_smash_meter.tint_progress = Color.WHITE
	_smash_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_smash_meter)
	_smash_label = _make_label(_hud, "扣杀  0%", Vector2(108, 651), Vector2(210, 36), 18, Color("754b59"))


func _show_start_menu() -> void:
	_phase = Phase.MENU
	_game_active = false
	_result_emitted = false
	_shuttle.visible = false
	_landing_marker.visible = false
	_racket.visible = false
	_combo_panel.visible = false
	_smash_meter.visible = false
	_smash_label.visible = false
	_clear_effects()
	_build_modal_base("桌面羽毛球", "先到 5 分，选好状态来认真打一局吧")
	var panel := _modal.get_node("Panel") as Control
	_difficulty_buttons.clear()
	var options := [
		{"key": "easy", "texture": "difficulty_easy.png", "x": 74.0},
		{"key": "normal", "texture": "difficulty_normal.png", "x": 183.0},
		{"key": "hard", "texture": "difficulty_hard.png", "x": 292.0}
	]
	for option in options:
		var key := String(option["key"])
		var button := _make_icon_button(panel, String(option["texture"]), Vector2(float(option["x"]), 196), Vector2(92, 96), String(DIFFICULTIES[key]["label"]), _select_difficulty.bind(key))
		_difficulty_buttons[key] = button
		_make_label(panel, String(DIFFICULTIES[key]["label"]), Vector2(float(option["x"]) - 3, 294), Vector2(98, 32), 17, Color("76515d"))
	_difficulty_selected_label = _make_label(panel, "", Vector2(90, 333), Vector2(280, 34), 18, Color("986070"))
	_make_text_button(panel, "开始对打", Vector2(93, 376), Vector2(274, 106), _start_match)
	_refresh_difficulty_display()
	_modal.visible = true


func _build_modal_base(title_text: String, subtitle_text: String) -> void:
	_clear_control(_modal)
	var dim := ColorRect.new()
	dim.position = Vector2.ZERO
	dim.size = Vector2(GAME_SIZE)
	dim.color = Color(0.12, 0.09, 0.12, 0.48)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.add_child(dim)

	var panel := _make_texture_rect(_modal, "modal_panel.png", Vector2(250, 94), Vector2(460, 522))
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_make_label(panel, title_text, Vector2(65, 78), Vector2(330, 55), 34, Color("6d4654"))
	var subtitle := _make_label(panel, subtitle_text, Vector2(56, 137), Vector2(348, 54), 19, Color("9a6b76"))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _show_pause_menu() -> void:
	_build_modal_base("暂停一下", "喝口水再回来也没关系，我会等你")
	var panel := _modal.get_node("Panel") as Control
	_make_text_button(panel, "继续比赛", Vector2(92, 236), Vector2(276, 104), _resume_match)
	_make_text_button(panel, "重新开始", Vector2(92, 340), Vector2(276, 104), _restart_match)
	var end_button := _make_icon_button(panel, "exit.png", Vector2(199, 446), Vector2(62, 62), "结束游戏", _close_game)
	end_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.visible = true


func _show_result_menu(player_won: bool) -> void:
	var title_text := "这局你赢啦" if player_won else "这局归我啦"
	var comment := "唔，再来一局我一定会接住的 (>_<)" if player_won else "嘿嘿，抓到你的挥拍节奏啦 (^_^)"
	_build_modal_base(title_text, comment)
	var panel := _modal.get_node("Panel") as Control
	_make_label(panel, "%d  :  %d" % [_player_score, _pet_score], Vector2(90, 210), Vector2(280, 64), 43, Color("cf768d"))
	_make_label(panel, "最长连击  %d" % _best_rally, Vector2(90, 282), Vector2(280, 42), 21, Color("80606a"))
	_make_text_button(panel, "再来一局", Vector2(92, 350), Vector2(276, 104), _restart_match)
	var end_button := _make_icon_button(panel, "exit.png", Vector2(199, 458), Vector2(62, 62), "结束游戏", _close_game)
	end_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.visible = true


func _select_difficulty(key: String) -> void:
	if not DIFFICULTIES.has(key):
		return
	_difficulty = key
	_refresh_difficulty_display()


func _refresh_difficulty_display() -> void:
	if _difficulty_selected_label:
		_difficulty_selected_label.text = "已选择：" + String(DIFFICULTIES[_difficulty]["label"])
	for key in _difficulty_buttons:
		var button: TextureButton = _difficulty_buttons[key]
		button.modulate = Color.WHITE if key == _difficulty else Color(0.76, 0.76, 0.76, 1.0)
		button.scale = Vector2.ONE * (1.08 if key == _difficulty else 1.0)


func _start_match() -> void:
	_modal.visible = false
	_game_active = true
	_result_emitted = false
	_match_over_pending = false
	_player_score = 0
	_pet_score = 0
	_rally = 0
	_best_rally = 0
	_combo = 0
	_smash_power = 0.0
	_pet_x = 0.0
	_pet_target_x = 0.0
	_racket_position = Vector2(480, 575)
	_last_racket_position = _racket_position
	_racket.visible = true
	_combo_panel.visible = true
	_smash_meter.visible = true
	_smash_label.visible = true
	_update_hud()
	_play_pet_idle()
	game_started.emit()
	_begin_point()


func _restart_match() -> void:
	_start_match()


func _begin_point() -> void:
	_phase = Phase.SERVE_DELAY
	_serve_delay = 1.05
	_rally = 0
	_combo = 0
	_landing_marker.visible = false
	_shuttle.visible = false
	_show_status("她要发球啦", 1.0)
	_update_hud()


func _launch_to_player() -> void:
	var config: Dictionary = DIFFICULTIES[_difficulty]
	var spread := float(config["shot_spread"])
	var target_x := _rng.randf_range(-spread, spread)
	_start_flight(false, _pet_x, target_x, float(config["shot_time"]), 0.54, false)
	_landing_marker.position = _project_court(target_x, PLAYER_DEPTH, 0.0)
	_landing_marker.visible = true


func _launch_to_pet(power: float, target_x: float, smash: bool) -> void:
	var duration := lerpf(1.16, 0.82, power)
	if smash:
		duration = 0.68
	_start_flight(true, _flight_target_x, target_x, duration, power, smash)
	_pet_target_x = target_x
	_landing_marker.visible = false


func _start_flight(to_pet: bool, from_x: float, target_x: float, duration: float, power: float, smash: bool) -> void:
	_phase = Phase.TO_PET if to_pet else Phase.TO_PLAYER
	_flight_elapsed = 0.0
	_flight_duration = duration
	_flight_from_x = from_x
	_flight_target_x = clampf(target_x, -0.95, 0.95)
	_flight_from_depth = PLAYER_DEPTH if to_pet else PET_DEPTH
	_flight_target_depth = PET_DEPTH if to_pet else PLAYER_DEPTH
	_flight_start_height = 0.16 if to_pet else 0.38
	_flight_end_height = 0.36 if to_pet else 0.03
	_flight_peak = 0.76 + power * 0.18
	_flight_power = power
	_flight_smash = smash
	_shuttle.texture = _ui_texture("shuttle_left.png" if to_pet and target_x < from_x else ("shuttle_right.png" if to_pet else "shuttle_down.png"))
	_shuttle.visible = true
	_update_shuttle_transform(0.0)
	if smash:
		_show_effect("swing_trail.png", _racket_hit_position(), 0.62, 0.32)
		_show_status("扣杀！", 0.72)


func _update_flight(delta: float) -> void:
	_flight_elapsed += delta
	var t := clampf(_flight_elapsed / _flight_duration, 0.0, 1.0)
	_update_shuttle_transform(t)
	if _phase == Phase.TO_PLAYER and t >= 0.62 and _racket_velocity.length() >= 290.0:
		_try_player_hit(false)
	if t < 1.0:
		return
	if _phase == Phase.TO_PLAYER:
		_player_missed()
	elif _phase == Phase.TO_PET:
		_resolve_pet_return()


func _update_shuttle_transform(t: float) -> void:
	var depth := lerpf(_flight_from_depth, _flight_target_depth, t)
	var x := lerpf(_flight_from_x, _flight_target_x, t)
	var height := lerpf(_flight_start_height, _flight_end_height, t) + sin(t * PI) * _flight_peak
	_shuttle.position = _project_court(x, depth, height)
	var perspective := lerpf(1.0, 0.58, depth)
	_shuttle.scale = Vector2.ONE * 0.17 * perspective * (1.0 + height * 0.08)
	_shuttle.rotation = lerpf(-0.24, 0.32, t) * (-1.0 if _phase == Phase.TO_PET else 1.0)
	if _phase == Phase.TO_PLAYER and _landing_marker.visible:
		_landing_marker.modulate.a = 0.58 + sin(Time.get_ticks_msec() * 0.009) * 0.18
		_landing_marker.scale = Vector2.ONE * (0.22 + sin(Time.get_ticks_msec() * 0.008) * 0.018)


func _try_player_hit(from_click: bool) -> void:
	if _phase != Phase.TO_PLAYER or _swing_cooldown > 0.0:
		return
	var t := clampf(_flight_elapsed / _flight_duration, 0.0, 1.0)
	if t < 0.58:
		_animate_racket_swing()
		return
	var distance := _racket_hit_position().distance_to(_shuttle.position)
	var radius := 142.0 if from_click else 116.0
	_animate_racket_swing()
	if distance > radius:
		return
	_swing_cooldown = 0.24
	var timing := 1.0 - clampf(absf(t - 0.84) / 0.26, 0.0, 1.0)
	var accuracy := 1.0 - clampf(distance / radius, 0.0, 1.0)
	var motion_power := clampf(_racket_velocity.length() / 1150.0, 0.0, 1.0)
	if from_click:
		motion_power = maxf(motion_power, 0.48)
	var quality := clampf(accuracy * 0.48 + timing * 0.34 + motion_power * 0.28, 0.18, 1.0)
	var perfect := quality >= 0.78
	var smash := _smash_power >= 99.0 and quality >= 0.55
	if smash:
		quality = 1.0
		_smash_power = 0.0
	elif perfect:
		_smash_power = minf(_smash_power + 30.0, 100.0)
	else:
		_smash_power = minf(_smash_power + 16.0, 100.0)
	_combo += 1
	_rally += 1
	_best_rally = maxi(_best_rally, _rally)
	var target_x := clampf((_racket_position.x - 480.0) / 360.0 + _racket_velocity.x / 1900.0, -0.92, 0.92)
	_show_effect("perfect_burst.png" if perfect or smash else "impact_burst.png", _shuttle.position, 0.72 if perfect else 0.42, 0.36)
	_show_status("完美回击！" if perfect else "接到了！", 0.68)
	_update_hud()
	_launch_to_pet(quality, target_x, smash)


func _resolve_pet_return() -> void:
	var config: Dictionary = DIFFICULTIES[_difficulty]
	var distance := absf(_pet_x - _flight_target_x)
	var reach_factor := clampf(1.0 - distance / 0.40, 0.0, 1.0)
	var chance := float(config["return_chance"]) * (0.50 + reach_factor * 0.50)
	if _flight_smash:
		chance -= 0.22
	if _rng.randf() > chance:
		_show_effect("miss_puff.png", _project_court(_pet_x, PET_DEPTH, 0.20), 0.34, 0.45)
		_award_point(true)
		return
	_pet_swing()
	_rally += 1
	_best_rally = maxi(_best_rally, _rally)
	var spread := float(config["shot_spread"])
	var target_x := _rng.randf_range(-spread, spread)
	_start_flight(false, _pet_x, target_x, float(config["shot_time"]), 0.58, false)
	_landing_marker.position = _project_court(target_x, PLAYER_DEPTH, 0.0)
	_landing_marker.visible = true
	_update_hud()


func _player_missed() -> void:
	_show_effect("miss_puff.png", _project_court(_flight_target_x, PLAYER_DEPTH, 0.02), 0.38, 0.48)
	_award_point(false)


func _award_point(player_scored: bool) -> void:
	_shuttle.visible = false
	_landing_marker.visible = false
	if player_scored:
		_player_score += 1
		_show_status("漂亮！你得分啦", 1.35)
		_show_effect("score_burst.png", Vector2(285, 66), 1.10, 0.55)
	else:
		_pet_score += 1
		_combo = 0
		_smash_power = maxf(_smash_power - 20.0, 0.0)
		_show_status("嘿嘿，这球归我", 1.35)
		_show_effect("heart_glow.png", Vector2(678, 64), 0.78, 0.55)
	_update_hud()
	_bump_score(player_scored)
	_match_over_pending = _player_score >= WIN_SCORE or _pet_score >= WIN_SCORE
	_phase = Phase.POINT_DELAY
	_point_delay = 1.55


func _finish_match() -> void:
	_phase = Phase.FINISHED
	_game_active = false
	_shuttle.visible = false
	_landing_marker.visible = false
	_racket.visible = false
	_combo_panel.visible = false
	_smash_meter.visible = false
	_smash_label.visible = false
	_status_panel.visible = false
	var player_won := _player_score > _pet_score
	if player_won:
		_show_effect("score_burst.png", Vector2(480, 320), 2.0, 0.9)
	if not _result_emitted:
		_result_emitted = true
		game_finished.emit(player_won, _best_rally)
	_show_result_menu(player_won)


func _toggle_pause() -> void:
	if not _game_active:
		return
	if _phase == Phase.PAUSED:
		_resume_match()
		return
	_phase_before_pause = _phase
	_phase = Phase.PAUSED
	_show_pause_menu()


func _resume_match() -> void:
	if _phase != Phase.PAUSED:
		return
	_phase = _phase_before_pause
	_modal.visible = false
	_show_status("继续！", 0.55)


func _close_game() -> void:
	_game_active = false
	_phase = Phase.MENU
	_shuttle.visible = false
	_landing_marker.visible = false
	_racket.visible = false
	_status_panel.visible = false
	_combo_panel.visible = false
	_smash_meter.visible = false
	_smash_label.visible = false
	hide()
	game_closed.emit()


func _update_racket(delta: float) -> void:
	if not _game_active or _phase == Phase.PAUSED:
		return
	var mouse := get_mouse_position()
	var inside := Rect2(Vector2.ZERO, Vector2(GAME_SIZE)).has_point(mouse)
	if inside:
		_racket_position = Vector2(clampf(mouse.x, 80.0, 880.0), clampf(mouse.y, 355.0, 675.0))
	var instantaneous := (_racket_position - _last_racket_position) / maxf(delta, 0.001)
	_racket_velocity = _racket_velocity.lerp(instantaneous, 1.0 - exp(-delta * 18.0))
	_last_racket_position = _racket_position
	_racket.position = _racket_position + Vector2(24, 32)
	_racket.rotation = clampf(_racket_velocity.x / 2200.0, -0.28, 0.28)


func _update_pet(delta: float) -> void:
	if _phase == Phase.TO_PET:
		var speed := float(DIFFICULTIES[_difficulty]["pet_speed"])
		_pet_x = move_toward(_pet_x, _pet_target_x, speed * delta)
	else:
		_pet_x = move_toward(_pet_x, 0.0, 0.42 * delta)
	_pet_sprite.position = _project_court(_pet_x, PET_DEPTH, 0.0) - Vector2(0, 69)


func _project_court(x: float, depth: float, height: float) -> Vector2:
	var curved_depth := pow(clampf(depth, 0.0, 1.0), 0.62)
	var ground_y := lerpf(610.0, 240.0, curved_depth)
	var half_width := lerpf(370.0, 182.0, pow(clampf(depth, 0.0, 1.0), 0.76))
	return Vector2(480.0 + x * half_width, ground_y - height * 172.0)


func _racket_hit_position() -> Vector2:
	return _racket.position + Vector2(-22, -38).rotated(_racket.rotation)


func _pet_swing() -> void:
	if _pet_frames and _pet_frames.has_animation(&"badminton"):
		_pet_sprite.play(&"badminton")
		_pet_sprite.speed_scale = 1.15
		_pet_swing_time = 0.92
	_show_effect("spark_bright.png", _pet_sprite.position + Vector2(-24, -28), 1.20, 0.28)


func _play_pet_idle() -> void:
	if not _pet_sprite:
		return
	_pet_sprite.speed_scale = 1.0
	if _pet_frames and _pet_frames.has_animation(&"idle"):
		_pet_sprite.play(&"idle")
	elif _pet_frames and _pet_frames.has_animation(&"badminton"):
		_pet_sprite.animation = &"badminton"
		_pet_sprite.frame = 0
		_pet_sprite.pause()


func _animate_racket_swing() -> void:
	if not _racket:
		return
	var tween := _racket.create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_racket, "rotation", _racket.rotation - 0.48, 0.07)
	tween.tween_property(_racket, "rotation", _racket.rotation + 0.12, 0.11)


func _show_effect(texture_name: String, effect_position: Vector2, effect_scale: float, duration: float) -> void:
	var effect := Sprite2D.new()
	effect.texture = _ui_texture(texture_name)
	effect.position = effect_position
	effect.scale = Vector2.ONE * effect_scale * 0.72
	effect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_effect_layer.add_child(effect)
	var tween := effect.create_tween()
	tween.set_parallel(true)
	tween.tween_property(effect, "scale", Vector2.ONE * effect_scale, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(effect, "modulate:a", 0.0, duration).set_delay(duration * 0.34)
	tween.chain().tween_callback(effect.queue_free)


func _clear_effects() -> void:
	if not _effect_layer:
		return
	for child in _effect_layer.get_children():
		child.queue_free()


func _show_status(text: String, duration: float) -> void:
	_status_label.text = text
	_status_panel.visible = true
	_status_panel.modulate = Color.WHITE
	_status_panel.scale = Vector2.ONE * 0.92
	_status_panel.pivot_offset = _status_panel.size * 0.5
	_status_time = duration
	var tween := _status_panel.create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_status_panel, "scale", Vector2.ONE, 0.18)


func _update_status(delta: float) -> void:
	if _status_time <= 0.0:
		return
	_status_time -= delta
	if _status_time <= 0.0:
		_status_panel.visible = false


func _update_hud() -> void:
	_score_player.text = "你  %d" % _player_score
	_score_pet.text = "她  %d" % _pet_score
	_round_label.text = str(WIN_SCORE)
	_combo_label.text = "连击  %d" % _combo
	_smash_meter.value = _smash_power
	_smash_label.text = "扣杀  %d%%" % roundi(_smash_power)


func _bump_score(player_scored: bool) -> void:
	var label := _score_player if player_scored else _score_pet
	label.pivot_offset = label.size * 0.5
	var tween := label.create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2.ONE * 1.28, 0.11)
	tween.tween_property(label, "scale", Vector2.ONE, 0.18)


func _on_root_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	if event.position.y <= 105.0:
		DisplayServer.window_start_drag(get_window_id())
		return
	if _game_active and _phase == Phase.TO_PLAYER:
		_try_player_hit(true)
	elif _game_active and _phase != Phase.PAUSED:
		_animate_racket_swing()


func _play_open_animation() -> void:
	_root.modulate = Color.WHITE
	_root.scale = Vector2.ONE * 0.96
	_root.pivot_offset = Vector2(GAME_SIZE) * 0.5
	var tween := _root.create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_root, "scale", Vector2.ONE, 0.24)


func _make_texture_rect(parent: Node, texture_name: String, rect_position: Vector2, rect_size: Vector2) -> TextureRect:
	var rect := TextureRect.new()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.texture = _ui_texture(texture_name)
	rect.position = rect_position
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size = rect_size
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect


func _make_label(parent: Node, text: String, label_position: Vector2, label_size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = label_position
	label.size = label_size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", _font if _font else ThemeDB.fallback_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.72))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(label)
	return label


func _make_icon_button(parent: Node, texture_name: String, button_position: Vector2, button_size: Vector2, tooltip: String, callback: Callable) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = _ui_texture(texture_name)
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.position = button_position
	button.size = button_size
	button.pivot_offset = button_size * 0.5
	button.tooltip_text = tooltip
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	button.mouse_entered.connect(_animate_button.bind(button, 1.08))
	button.mouse_exited.connect(_animate_button.bind(button, 1.0))
	parent.add_child(button)
	return button


func _make_text_button(parent: Node, text: String, button_position: Vector2, button_size: Vector2, callback: Callable) -> TextureButton:
	var button := _make_icon_button(parent, "small_panel.png", button_position, button_size, text, callback)
	var label := _make_label(button, text, Vector2(18, 22), button_size - Vector2(36, 44), 24, Color("754b59"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return button


func _animate_button(button: Control, target_scale: float) -> void:
	if _button_tweens.has(button) and is_instance_valid(_button_tweens[button]):
		var old_tween: Tween = _button_tweens[button]
		if old_tween.is_valid():
			old_tween.kill()
	var tween := button.create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE * target_scale, 0.14)
	_button_tweens[button] = tween


func _ui_texture(name: String) -> Texture2D:
	return load(UI_DIR + "/" + name) as Texture2D


func _clear_control(control: Control) -> void:
	for child in control.get_children():
		child.free()
