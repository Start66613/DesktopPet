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
	for _frame in 12:
		await process_frame
	var immersive_window_id := panel.get_immersive_window_id()
	var screen := DisplayServer.window_get_current_screen(immersive_window_id)
	if screen < 0:
		screen = 0
	var expected := DisplayServer.screen_get_size(screen)
	var actual := DisplayServer.window_get_size(immersive_window_id)
	assert(panel.is_fullscreen_active())
	assert(actual == expected)
	assert(panel._immersive_window.borderless)
	assert(panel._immersive_window.always_on_top)
	assert(panel.visible)
	assert(panel.size == Vector2i(820, 465))
	assert(panel.position == Vector2i(40, 40))
	assert(panel.is_fullscreen_button_visible())
	assert(panel._immersive_view.visible)
	assert(panel._immersive_view.size.x >= expected.x - 2)
	assert(panel._immersive_view.size.y >= expected.y - 2)
	var screenshot := panel._immersive_window.get_texture().get_image()
	assert(screenshot and not screenshot.is_empty())
	assert(_image_has_visible_content(screenshot))
	screenshot.save_png("res://logs/music_fullscreen_fixed_qa.png")
	print("MUSIC_FULLSCREEN_QA_OK immersive_window_id=%d size=%dx%d player_covered=true content_visible=true button_visible=true" % [immersive_window_id, actual.x, actual.y])
	panel._exit_fullscreen()
	for _frame in 4:
		await process_frame
	assert(not panel.is_fullscreen_active())
	assert(not panel._immersive_window.visible)
	assert(panel.visible)
	assert(DisplayServer.window_get_size(panel.get_window_id()) == Vector2i(820, 465))
	assert(DisplayServer.window_get_position(panel.get_window_id()) == Vector2i(40, 40))
	print("MUSIC_FULLSCREEN_RESTORE_QA_OK size=820x465 position=40,40")
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
