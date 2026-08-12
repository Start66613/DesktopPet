extends SceneTree

const ChangeDetector := preload("res://scripts/screen_change_detector.gd")
const ContextMemory := preload("res://scripts/screen_context_memory.gd")
const AwarenessService := preload("res://scripts/screen_awareness_service.gd")


func _init() -> void:
	var failures: Array[String] = []
	_test_change_detector(failures)
	_test_context_memory(failures)
	_test_service_policy(failures)
	_test_no_screenshot_persistence(failures)
	if failures.is_empty():
		print("SCREEN_AWARENESS_2_QA_OK change_detection memory budget blacklist confidence no_disk_write")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _test_change_detector(failures: Array[String]) -> void:
	var detector = ChangeDetector.new()
	var dark := Image.create(192, 108, false, Image.FORMAT_RGBA8)
	dark.fill(Color("151515"))
	var bright := Image.create(192, 108, false, Image.FORMAT_RGBA8)
	bright.fill(Color("eeeeee"))
	var baseline: Dictionary = detector.evaluate(dark)
	var unchanged: Dictionary = detector.evaluate(dark)
	var changed: Dictionary = detector.evaluate(bright)
	_expect(not bool(baseline.get("has_baseline", true)), "首次采样应只建立本地基线", failures)
	_expect(float(unchanged.get("score", 1.0)) < 0.001, "相同画面不应触发变化", failures)
	_expect(float(changed.get("score", 0.0)) > 0.5 and float(changed.get("changed_ratio", 0.0)) > 0.9, "大幅变化应被本地检测", failures)


func _test_context_memory(failures: Array[String]) -> void:
	var memory = ContextMemory.new()
	memory.remember({"scene_type": "game", "activity": "正在进行一场比赛", "task_summary": "比分接近", "confidence": 0.9})
	memory.remember({"sensitive": true, "activity": "不应保存"})
	_expect(memory.size() == 1, "敏感结果不得进入短期记忆", failures)
	_expect(not memory.get_prompt_context().contains("不应保存"), "短期摘要不得包含敏感结果", failures)
	memory.clear()
	_expect(memory.size() == 0, "清空短期记忆应立即生效", failures)


func _test_service_policy(failures: Array[String]) -> void:
	var service = AwarenessService.new()
	service._daily_limit = 1
	service._daily_date = service._today_key()
	service._daily_request_count = 1
	_expect(not service._can_start_automatic_request(), "达到每日额度后不得自动上传", failures)

	service._daily_request_count = 0
	service._blacklist_text = "keepass, 银行"
	service.set_foreground_context({"process": "KeePass.exe", "label": "KeePass"})
	_expect(service._is_sensitive_foreground(), "隐私名单命中时应阻止观察", failures)
	service.set_foreground_context({"process": "game.exe", "label": "测试游戏"})
	_expect(not service._is_sensitive_foreground(), "普通应用不应被隐私名单误伤", failures)

	var low := service._normalize_awareness({
		"scene_type": "game", "activity": "正在游戏", "confidence": 0.4,
		"importance": 0.9, "should_speak": true, "text": "这一句不该说"
	})
	service._apply_speech_policy(low)
	_expect(not bool(low.get("should_speak", true)), "低置信度结果必须保持安静", failures)
	var high := service._normalize_awareness({
		"scene_type": "game", "activity": "赢下了一场比赛", "event": "game_result",
		"confidence": 0.92, "importance": 0.9, "should_speak": true, "text": "漂亮！这局拿下啦 (≧▽≦)"
	})
	service._apply_speech_policy(high)
	_expect(bool(high.get("should_speak", false)), "高置信度重要事件应允许回应", failures)
	var duplicate := high.duplicate(true)
	duplicate["importance"] = 0.5
	service._apply_speech_policy(duplicate)
	_expect(not bool(duplicate.get("should_speak", true)), "低优先级重复场景应被抑制", failures)


func _test_no_screenshot_persistence(failures: Array[String]) -> void:
	var source := FileAccess.get_file_as_string("res://scripts/screen_awareness_service.gd")
	_expect(source.contains("save_jpg_to_buffer"), "画面上传前应只写入内存缓冲区", failures)
	_expect(not source.contains("save_jpg("), "画面感知不得把 JPEG 写入磁盘", failures)
	_expect(not source.contains("save_png("), "画面感知不得把 PNG 写入磁盘", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
