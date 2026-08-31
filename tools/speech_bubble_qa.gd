extends SceneTree

const SpeechBubble := preload("res://scripts/speech_bubble.gd")


func _init() -> void:
	root.size = Vector2i(260, 124)
	root.transparent_bg = false
	var backdrop := ColorRect.new()
	backdrop.color = Color("f7f4f5")
	backdrop.size = Vector2(260, 124)
	root.add_child(backdrop)
	var bubble := SpeechBubble.new()
	bubble.position = Vector2(20, 14)
	root.add_child(bubble)
	await process_frame
	bubble.configure_fonts(load("res://assets/fonts/ZCOOLKuaiLe-Regular.ttf") as Font, ThemeDB.fallback_font)
	bubble.set_message("今天快累啦，忙了一整天也该对自己好一点，先喝口水再慢慢继续吧，我会陪着你的", "")
	await create_timer(0.4).timeout
	var image := root.get_texture().get_image()
	assert(image and not image.is_empty())
	image.save_png("res://logs/speech_bubble_qa.png")
	print("SPEECH_BUBBLE_QA_OK text_inset=27 width=153 max_lines=3")
	quit(0)
