extends SceneTree

const PetScene := preload("res://scenes/pet.tscn")
const CareSystem := preload("res://scripts/care_system.gd")
const CarePanel := preload("res://scripts/care_panel.gd")
const AIChatPanel := preload("res://scripts/ai_chat_panel.gd")
const ProactiveCompanion := preload("res://scripts/proactive_companion.gd")
const ForegroundAppMonitor := preload("res://scripts/foreground_app_monitor.gd")
const ScreenAwarenessService := preload("res://scripts/screen_awareness_service.gd")
const CompanionSettingsPanel := preload("res://scripts/companion_settings_panel.gd")
const MusicPlayerPanel := preload("res://scripts/music_player_panel.gd")
const BadmintonGamePanel := preload("res://scripts/badminton_game_panel.gd")
const DogCompanion := preload("res://scripts/dog_companion.gd")
const DogHomePanel := preload("res://scripts/dog_home_panel.gd")

const FONT_PATH := "res://assets/fonts/ZCOOLKuaiLe-Regular.ttf"
const PET_FRAMES_PATH := "res://assets/runtime/pet_sprite_frames.tres"
const OUTPUT_DIR := "res://docs/images"


func _init() -> void:
	root.gui_embed_subwindows = false
	call_deferred("_run")


func _run() -> void:
	var target := _get_target()
	var success := false
	match target:
		"pet":
			success = await _capture_pet()
		"care":
			success = await _capture_care()
		"chat":
			success = await _capture_chat()
		"companion":
			success = await _capture_companion()
		"music":
			success = await _capture_music()
		"badminton":
			success = await _capture_badminton()
		"dog":
			success = await _capture_dog_home()
		_:
			push_error("Unknown gallery target: " + target)
	quit(0 if success else 1)


func _get_target() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--target="):
			return argument.trim_prefix("--target=").strip_edges().to_lower()
	return "pet"


func _font() -> Font:
	var loaded := load(FONT_PATH) as Font
	return loaded if loaded else ThemeDB.fallback_font


func _wait_frames(count: int) -> void:
	for _index in count:
		await process_frame


func _save_window(window: Window, file_name: String, wait_count := 12) -> bool:
	await _wait_frames(wait_count)
	var image := window.get_texture().get_image()
	if not image or image.is_empty():
		push_error("Gallery capture returned an empty image: " + file_name)
		return false
	var error := image.save_png(OUTPUT_DIR.path_join(file_name))
	if error != OK:
		push_error("Gallery image save failed: %s (%s)" % [file_name, error_string(error)])
		return false
	print("GITHUB_GALLERY_CAPTURE_OK target=%s size=%dx%d" % [file_name, image.get_width(), image.get_height()])
	return true


func _capture_pet() -> bool:
	var pet = PetScene.instantiate()
	root.add_child(pet)
	await _wait_frames(12)
	pet.set_process(false)
	pet._bubble.set_message("今天也一起加油吧 (´▽｀)", "🌸")
	pet._bubble_time_left = 30.0
	pet._update_passthrough()
	return await _save_window(root, "desktop-pet-interaction.png", 20)


func _capture_care() -> bool:
	var care := CareSystem.new()
	root.add_child(care)
	var panel := CarePanel.new()
	panel.configure(care, _font())
	root.add_child(panel)
	await _wait_frames(2)
	panel.open_at(Vector2i(80, 80), load("res://assets/sprites/idle/idle_01.png") as Texture2D)
	panel._refresh_stats({
		"fullness": 82.0,
		"hydration": 74.0,
		"mood": 91.0,
		"affection": 68.0,
		"energy": 79.0,
	})
	return await _save_window(panel, "care-panel.png")


func _capture_chat() -> bool:
	var care := CareSystem.new()
	root.add_child(care)
	var panel := AIChatPanel.new()
	panel.configure(_font(), care)
	root.add_child(panel)
	await _wait_frames(2)
	panel._endpoint = "https://example.invalid/v1/chat/completions"
	panel._model = "qianqian-demo"
	panel._api_key = "gallery-placeholder"
	panel.open_at(Vector2i(80, 40))
	for child in panel._messages.get_children():
		child.queue_free()
	panel._history.clear()
	await _wait_frames(2)
	panel._add_message("assistant", "欢迎回来呀，今天想和我聊些什么？ (´▽｀)", false)
	panel._add_message("user", "刚写完一部分作业，想休息一会。", false)
	panel._add_message("assistant", "辛苦啦！先伸个懒腰、喝口水，我陪你听一首喜欢的歌吧。", false)
	panel._status_label.text = "已连接 · qianqian-demo"
	return await _save_window(panel, "ai-chat.png", 16)


func _capture_companion() -> bool:
	var care := CareSystem.new()
	root.add_child(care)
	var companion := ProactiveCompanion.new()
	companion.configure(care)
	root.add_child(companion)
	var monitor := ForegroundAppMonitor.new()
	root.add_child(monitor)
	var screen_service := ScreenAwarenessService.new()
	root.add_child(screen_service)
	await _wait_frames(2)
	companion.set_enabled(true)
	companion.set_frequency_minutes(0.5)
	companion.set_foreground_monitoring_enabled(true)
	companion.set_quiet_hours_enabled(true)
	companion.note_interaction("用户刚刚完成了一段学习任务")
	monitor._current_info = {
		"process": "code.exe",
		"label": "VS Code",
		"activity": "编程或创作",
		"recognized": true,
	}
	var panel := CompanionSettingsPanel.new()
	panel.configure(_font(), companion, monitor, screen_service)
	root.add_child(panel)
	await _wait_frames(2)
	panel.open_at(Vector2i(70, 70), "companion")
	return await _save_window(panel, "companion-settings.png")


func _capture_music() -> bool:
	var panel := MusicPlayerPanel.new()
	panel.configure(_font(), null, null)
	root.add_child(panel)
	await _wait_frames(2)
	panel.open_at(Vector2i(70, 70))
	panel._on_session_updated({
		"found": true,
		"track_id": "gallery-track",
		"title": "那些年",
		"artist": "胡夏",
		"album": "那些年，我们一起追的女孩",
		"source_label": "QQ音乐",
		"playback_status": "playing",
		"position_ms": 94000,
		"duration_ms": 371000,
		"can_play": true,
		"can_pause": true,
		"can_previous": true,
		"can_next": true,
		"can_seek": true,
	})
	panel._cover.texture = load("res://release/app_icon.png") as Texture2D
	panel._play_cover_reveal()
	panel._on_lyrics_ready("gallery-track", [
		{"time_ms": 82000, "text": "又回到最初的起点"},
		{"time_ms": 92000, "text": "记忆中你青涩的脸"},
		{"time_ms": 102000, "text": "我们终于来到了这一天"},
	], "QQ音乐歌词")
	panel._update_progress()
	return await _save_window(panel, "music-player.png", 16)


func _capture_badminton() -> bool:
	var frames := load(PET_FRAMES_PATH) as SpriteFrames
	var panel := BadmintonGamePanel.new()
	panel.configure(_font(), frames)
	root.add_child(panel)
	await _wait_frames(2)
	panel.open_at(Vector2i(30, 30))
	panel._start_match()
	panel._player_score = 2
	panel._pet_score = 1
	panel._rally = 4
	panel._best_rally = 7
	panel._combo = 4
	panel._smash_power = 68.0
	panel._update_hud()
	panel._show_status("完美回击！", 30.0)
	panel._launch_to_player()
	return await _save_window(panel, "badminton-gameplay.png", 18)


func _capture_dog_home() -> bool:
	var dog := DogCompanion.new()
	dog.configure(Vector2i(100, 100), 0)
	root.add_child(dog)
	await _wait_frames(2)
	dog.hide()
	var panel := DogHomePanel.new()
	panel.configure(_font(), dog.get_sprite_frames())
	root.add_child(panel)
	await _wait_frames(2)
	panel.open_at(Vector2i(70, 70), true, true, "小雪球")
	return await _save_window(panel, "dog-home.png")
