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

	panel.open_at(Vector2i(30, 30), "companion")
	await process_frame
	assert(panel.size == Vector2i(740, 520))
	assert(panel.get_current_page() == "companion")
	assert(panel._tabs.size() == 3)
	assert(panel._pages.size() == 3)
	for tab_name in panel._tabs:
		assert(panel._tabs[tab_name].z_index > panel._pages[tab_name].z_index)

	panel.show_page("awareness")
	assert(panel.get_current_page() == "awareness")
	assert(panel._pages["awareness"].visible)
	assert(not panel._pages["companion"].visible)
	panel.show_page("privacy")
	assert(panel.get_current_page() == "privacy")
	assert(panel._pages["privacy"].visible)
	assert(panel._vision_endpoint_input != null)
	assert(panel._vision_model_input != null)
	assert(panel._vision_key_input != null)
	print("COMPANION_SETTINGS_INTEGRATION_QA_OK pages=3 tabs_above_pages=true size=740x520")
	panel.hide_panel()
	quit(0)
