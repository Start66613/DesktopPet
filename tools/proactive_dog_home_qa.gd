extends SceneTree

const ProactiveCompanion := preload("res://scripts/proactive_companion.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var companion := ProactiveCompanion.new()
	root.add_child(companion)
	await process_frame

	companion._recent_events = [
		"12:00 用户刚刚摸了摸白色小狗小雪球",
		"12:01 用户正在整理文档"
	]
	companion._recent_lines = [
		"小雪球又在旁边摇尾巴啦。",
		"今天也在一点一点前进呢。"
	]
	companion._queued_message = {"text": "小雪球想和你一起玩。", "emoji": "", "source": "qa"}
	companion.set_runtime_context({
		"available": true,
		"state": "安静待机",
		"dog_companion": {"adopted": true, "active": false, "name": "小雪球"}
	})

	_check(companion._queued_message.is_empty(), "queued dog message was not discarded")
	var home_context := companion._build_context_prompt()
	_check(not home_context.contains("用户刚刚摸了摸白色小狗小雪球"), "dog event leaked into home context")
	_check(not home_context.contains("小雪球又在旁边摇尾巴"), "dog line leaked into home context")
	_check(home_context.contains("用户正在整理文档"), "non-dog event was incorrectly filtered")
	for line in companion._get_contextual_fallback_lines():
		_check(not companion._is_dog_related_text(String(line.get("text", ""))), "home fallback still contains a dog topic")

	companion.set_runtime_context({
		"available": true,
		"state": "安静待机",
		"dog_companion": {"adopted": true, "active": true, "name": "小雪球"}
	})
	var has_active_dog_line := false
	for line in companion._get_contextual_fallback_lines():
		if String(line.get("text", "")).contains("小雪球"):
			has_active_dog_line = true
			break
	_check(has_active_dog_line, "dog topic did not return after calling the dog out")

	if _failures.is_empty():
		print("PROACTIVE_DOG_HOME_QA_OK inactive_suppressed=true active_restored=true")
		quit()
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
