extends SceneTree

const ScreenAwarenessService := preload("res://scripts/screen_awareness_service.gd")


func _init() -> void:
	var service := ScreenAwarenessService.new()
	root.add_child(service)
	await process_frame
	service._enabled = true
	service._paused = false
	service._daily_request_count = 0
	service._use_separate_vision_api = true
	service._vision_endpoint = "https://api.deepseek.com/chat/completions"
	service._vision_model = "deepseek-chat"
	service._vision_api_key = "qa-placeholder"
	var failures: Array[String] = []
	service.analysis_failed.connect(func(message: String) -> void: failures.append(message))
	service.request_analysis("manual", true)
	await process_frame
	assert(failures.size() == 1)
	assert(failures[0].contains("DeepSeek"))
	assert(not service._capture_pending)
	assert(not service._request_pending)
	assert(service.get_daily_usage() == 0)
	service._evaluate_local_screen_change()
	assert(service.get_status_summary().contains("DeepSeek"))
	assert(not service._capture_pending)
	assert(not service._request_pending)
	assert(service.get_daily_usage() == 0)
	print("SCREEN_DEEPSEEK_GUARD_QA_OK captured=false local_sample=false uploaded=false usage=0")
	quit(0)
