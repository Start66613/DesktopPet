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
	await process_frame
	await process_frame
	var screen := DisplayServer.window_get_current_screen(panel.get_window_id())
	if screen < 0:
		screen = 0
	var expected := DisplayServer.screen_get_size(screen)
	var actual := DisplayServer.window_get_size(panel.get_window_id())
	assert(panel.is_fullscreen_active())
	assert(actual == expected)
	print("MUSIC_FULLSCREEN_QA_OK window_id=%d size=%dx%d" % [panel.get_window_id(), actual.x, actual.y])
	panel.hide_panel()
	await process_frame
	assert(not panel.visible)
	quit(0)
