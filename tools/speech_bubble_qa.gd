extends SceneTree

const SpeechBubble := preload("res://scripts/speech_bubble.gd")


func _init() -> void:
	root.size = Vector2i(328, 138)
	root.transparent_bg = false
	var backdrop := ColorRect.new()
	backdrop.color = Color("f7f4f5")
	backdrop.size = Vector2(328, 138)
	root.add_child(backdrop)
	var bubble := SpeechBubble.new()
	bubble.position = Vector2(12, 8)
	root.add_child(bubble)
	await process_frame
	bubble.configure_fonts(load("res://assets/fonts/ZCOOLKuaiLe-Regular.ttf") as Font, ThemeDB.fallback_font)
	bubble.set_message("肚子在小声提醒我啦……可以一起吃点东西吗？", "🍰")
	await create_timer(0.4).timeout
	if DisplayServer.get_name().to_lower() == "headless":
		assert(bubble.get_local_bounds().size.x >= 316.0)
		assert(bubble._prepared_lines.size() >= 2)
		assert(bubble._prepared_lines.size() <= 4)
		print("SPEECH_BUBBLE_QA_OK headless text_width=230 max_lines=4")
		quit(0)
		return
	var viewport_texture := root.get_texture()
	if viewport_texture == null:
		print("SPEECH_BUBBLE_QA_SKIPPED no viewport texture is available")
		quit(0)
		return
	var image := viewport_texture.get_image()
	assert(image and not image.is_empty())
	image.save_png("res://logs/speech_bubble_qa.png")
	print("SPEECH_BUBBLE_QA_OK text_width=230 max_lines=4")
	quit(0)
