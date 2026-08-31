extends SceneTree

const MusicPlayerPanel := preload("res://scripts/music_player_panel.gd")


func _init() -> void:
	root.gui_embed_subwindows = false
	var panel := MusicPlayerPanel.new()
	panel.configure(ThemeDB.fallback_font, null, null)
	root.add_child(panel)
	await process_frame
	panel.open_at(Vector2i(40, 40))
	await process_frame
	assert(panel.visible)
	assert(panel.size == Vector2i(820, 465))
	panel.enter_fullscreen()
	for _frame in 8:
		await process_frame
	var immersive_window_id := panel.get_immersive_window_id()
	var screen := DisplayServer.window_get_current_screen(immersive_window_id)
	if screen < 0:
		screen = 0
	var expected := DisplayServer.screen_get_size(screen)
	var actual := DisplayServer.window_get_size(immersive_window_id)
	assert(panel.is_fullscreen_active())
	assert(immersive_window_id != DisplayServer.INVALID_WINDOW_ID)
	assert(panel._immersive_view.get_parent() == panel)
	assert(actual.x >= expected.x - 2 and actual.y >= expected.y - 2)
	assert(panel.borderless)
	assert(not panel.always_on_top)
	assert(not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, immersive_window_id))
	assert(not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, immersive_window_id))
	assert(panel.visible)
	assert(panel.transparent_bg == panel._windowed_transparent_bg)
	assert(not panel._root.visible)
	assert(not panel._text_layer.visible)
	assert(panel.is_fullscreen_button_visible())
	assert(panel._immersive_view.visible)
	assert(panel._immersive_view.size.x >= expected.x - 2)
	assert(panel._immersive_view.size.y >= expected.y - 2)
	assert(panel._immersive_view.uses_player_skin())
	assert(not panel._immersive_view.has_visible_companion())
	assert(root.always_on_top)
	await create_timer(0.3).timeout
	panel._immersive_view.set_session({"found": true, "track_id": "qa-track", "title": "测试歌曲", "artist": "测试歌手", "playback_status": "playing", "can_previous": true, "can_next": true}, "list")
	panel._immersive_view.set_lyrics([{"text": "上一句"}, {"text": "正在播放的歌词"}, {"text": "下一句"}], 1, "测试歌词")
	var native_events := {"previous": 0}
	panel._immersive_view.previous_requested.connect(func() -> void: native_events["previous"] = int(native_events["previous"]) + 1)
	var previous_press := InputEventMouseButton.new()
	previous_press.button_index = MOUSE_BUTTON_LEFT
	previous_press.pressed = true
	previous_press.position = panel._immersive_view._previous_button.get_global_rect().get_center()
	panel.push_input(previous_press, true)
	for _input_frame in 2:
		await process_frame
	assert(int(native_events["previous"]) == 1)
	var exit_rect: Rect2 = panel._immersive_view.get_exit_button_rect()
	assert(exit_rect.size.x >= float(expected.x) * 0.025 and exit_rect.size.y >= float(expected.y) * 0.045)
	assert(exit_rect.end.x <= expected.x + 1 and exit_rect.end.y <= expected.y + 1)
	var screenshot := panel.get_texture().get_image()
	assert(screenshot and not screenshot.is_empty())
	assert(_image_has_visible_content(screenshot))
	assert(_image_has_player_palette(screenshot))
	screenshot.save_png("res://logs/music_fullscreen_fixed_qa.png")
	print("MUSIC_FULLSCREEN_QA_OK window_id=%d size=%dx%d skin=player_panel controls_visible=true" % [immersive_window_id, actual.x, actual.y])
	var pointer_press := InputEventMouseButton.new()
	pointer_press.button_index = MOUSE_BUTTON_LEFT
	pointer_press.pressed = true
	pointer_press.position = exit_rect.get_center()
	panel.push_input(pointer_press, true)
	await create_timer(0.35).timeout
	assert(not panel.is_fullscreen_active())
	assert(panel.get_window_id() != DisplayServer.INVALID_WINDOW_ID)
	assert(panel.visible)
	assert(panel.transparent_bg)
	assert(panel._root.visible)
	assert(panel._text_layer.visible)
	print("MUSIC_FULLSCREEN_RESTORE_STATE size=%s position=%s saved_size=%s saved_position=%s mode=%s native_mode=%s transitioning=%s" % [DisplayServer.window_get_size(panel.get_window_id()), DisplayServer.window_get_position(panel.get_window_id()), panel._windowed_size, panel._windowed_position, panel.mode, DisplayServer.window_get_mode(panel.get_window_id()), panel._fullscreen_transitioning])
	assert(DisplayServer.window_get_size(panel.get_window_id()) == Vector2i(820, 465))
	assert(DisplayServer.window_get_position(panel.get_window_id()) == Vector2i(40, 40))
	print("MUSIC_FULLSCREEN_RESTORE_QA_OK same_window_node=true size=820x465 position=40,40 pointer_exit=true")
	panel.enter_fullscreen()
	for _frame in 8:
		await process_frame
	assert(panel.is_fullscreen_active())
	var second_window_id := panel.get_immersive_window_id()
	assert(second_window_id != DisplayServer.INVALID_WINDOW_ID)
	assert(panel._immersive_view.get_parent() == panel)
	await create_timer(0.3).timeout
	var second_image := panel.get_texture().get_image()
	assert(second_image and not second_image.is_empty())
	assert(_image_has_visible_content(second_image))
	assert(_image_has_player_palette(second_image))
	print("MUSIC_FULLSCREEN_REENTER_QA_OK same_window_node=true content_visible=true")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	panel.push_input(escape, true)
	await create_timer(0.35).timeout
	assert(not panel.is_fullscreen_active())
	assert(panel.get_window_id() != DisplayServer.INVALID_WINDOW_ID)
	panel.hide_panel()
	quit(0)


func _image_has_visible_content(image: Image) -> bool:
	var first := image.get_pixel(0, 0)
	for row in 9:
		for column in 16:
			var x := mini(roundi(float(column) * float(image.get_width() - 1) / 15.0), image.get_width() - 1)
			var y := mini(roundi(float(row) * float(image.get_height() - 1) / 8.0), image.get_height() - 1)
			var sample := image.get_pixel(x, y)
			var color_delta := absf(sample.r - first.r) + absf(sample.g - first.g) + absf(sample.b - first.b)
			if color_delta > 0.08:
				return true
	return false


func _image_has_player_palette(image: Image) -> bool:
	var light_samples := 0
	for point in [Vector2(0.25, 0.5), Vector2(0.5, 0.5), Vector2(0.75, 0.5), Vector2(0.5, 0.72)]:
		var pixel := image.get_pixel(
			clampi(roundi(point.x * float(image.get_width() - 1)), 0, image.get_width() - 1),
			clampi(roundi(point.y * float(image.get_height() - 1)), 0, image.get_height() - 1)
		)
		if pixel.r > 0.75 and pixel.g > 0.68 and pixel.b > 0.68:
			light_samples += 1
	return light_samples >= 3
