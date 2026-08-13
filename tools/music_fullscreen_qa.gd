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
	var screen := DisplayServer.window_get_current_screen(panel.get_window_id())
	if screen < 0:
		screen = 0
	var expected := DisplayServer.screen_get_size(screen)
	var actual := DisplayServer.window_get_size(panel.get_window_id())
	assert(panel.is_fullscreen_active())
	assert(actual == expected)
	assert(panel.mode == Window.MODE_FULLSCREEN or panel.borderless)
	var screenshot := panel.get_texture().get_image()
	if screenshot and not screenshot.is_empty():
		screenshot.save_png("res://logs/music_fullscreen_fixed_qa.png")
	print("MUSIC_FULLSCREEN_QA_OK window_id=%d size=%dx%d" % [panel.get_window_id(), actual.x, actual.y])
	panel._exit_fullscreen()
	for _frame in 4:
		await process_frame
	assert(not panel.is_fullscreen_active())
	assert(DisplayServer.window_get_size(panel.get_window_id()) == Vector2i(820, 465))
	assert(DisplayServer.window_get_position(panel.get_window_id()) == Vector2i(40, 40))
	print("MUSIC_FULLSCREEN_RESTORE_QA_OK size=820x465 position=40,40")
	panel.hide_panel()
	quit(0)
