extends SceneTree

const ProactiveCompanion := preload("res://scripts/proactive_companion.gd")
const ScreenAwarenessService := preload("res://scripts/screen_awareness_service.gd")


func _init() -> void:
	var companion := ProactiveCompanion.new()
	root.add_child(companion)
	await process_frame
	companion.set_runtime_context({
		"available": true,
		"state": "正在听歌",
		"foreground_app": {},
		"dog_companion": {"adopted": false, "active": false, "name": ""},
		"music": {
			"active": true,
			"title": "晴天",
			"artist": "周杰伦",
			"source": "QQ音乐",
			"position_ms": 62000,
			"duration_ms": 269000,
			"current_lyric": "故事的小黄花"
		}
	})
	var prompt: String = companion._build_context_prompt()
	assert(prompt.contains("晴天"))
	assert(prompt.contains("周杰伦"))
	assert(prompt.contains("故事的小黄花"))
	assert(companion._has_music_context())
	var fallback: Dictionary = companion._get_music_fallback_line()
	assert(String(fallback.get("text", "")).contains("故事的小黄花"))

	var awareness := ScreenAwarenessService.new()
	awareness._enabled = false
	var failed_message := ""
	awareness.analysis_failed.connect(func(message: String) -> void: failed_message = message)
	awareness.request_analysis()
	assert(failed_message.contains("允许"))
	print("COMPANION_MUSIC_SCREEN_QA_OK prompt_music=true lyric=true privacy_gate=true")
	quit(0)
