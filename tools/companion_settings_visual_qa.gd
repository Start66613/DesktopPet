extends SceneTree

const CompanionSettingsPanel := preload("res://scripts/companion_settings_panel.gd")
const ScreenAwarenessService := preload("res://scripts/screen_awareness_service.gd")


func _init() -> void:
	root.gui_embed_subwindows = false
	var service := ScreenAwarenessService.new()
	root.add_child(service)
	var panel := CompanionSettingsPanel.new()
	panel.configure(ThemeDB.fallback_font, null, null, service)
	root.add_child(panel)
	await process_frame
	var screen := 0
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var panel_position := usable.position + (usable.size - panel.size) / 2
	panel.open_at(panel_position, "awareness")
	for _frame in 12:
		await process_frame
	var screenshot := panel.get_texture().get_image()
	if screenshot and not screenshot.is_empty():
		screenshot.save_png("res://logs/companion_settings_integrated_qa.png")
	print("COMPANION_SETTINGS_VISUAL_QA_OK page=%s size=%dx%d" % [panel.get_current_page(), panel.size.x, panel.size.y])
	panel.hide_panel()
	quit(0)
