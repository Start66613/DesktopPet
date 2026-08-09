extends SceneTree

const DogCompanion := preload("res://scripts/dog_companion.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var dog := DogCompanion.new()
	dog.configure(Vector2i(120, 120), 0)
	root.add_child(dog)
	await process_frame

	var frames := dog.get_sprite_frames()
	var expected_loops := {
		"sit_enter": false,
		"sit_idle": true,
		"sleep_enter": false,
		"sleep_idle": true,
		"happy": true
	}
	for animation_name in expected_loops:
		_check(frames.has_animation(animation_name), "missing animation: " + animation_name)
		if frames.has_animation(animation_name):
			_check(frames.get_frame_count(animation_name) == 8, animation_name + " should contain 8 frames")
			_check(frames.get_animation_loop(animation_name) == expected_loops[animation_name], animation_name + " loop flag is incorrect")

	_check(dog.adopt("测试小狗", Vector2i(120, 120), 0), "test adoption failed")
	dog.perform_care("feed")
	await create_timer(0.05).timeout
	_check(String(dog._sprite.animation) == "happy", "feeding did not trigger happy")

	dog.perform_care("rest")
	await create_timer(0.05).timeout
	_check(String(dog._sprite.animation) == "sleep_enter", "rest did not trigger sleep transition")
	await create_timer(0.9).timeout
	_check(String(dog._sprite.animation) == "sleep_idle", "sleep transition did not reach sleep idle")
	dog._state_duration = 0.0
	await create_timer(0.05).timeout
	_check(String(dog._sprite.animation) == "sleep_enter" and dog._sprite.is_playing(), "sleep exit did not reverse the transition")
	await create_timer(1.65).timeout
	_check(dog._state in [0, 1], "sleep exit did not return to normal behavior; state=%s animation=%s visible=%s" % [dog._state, dog._sprite.animation, dog.visible])

	dog._enter_state(2)
	await create_timer(0.9).timeout
	_check(String(dog._sprite.animation) == "sit_idle", "sit transition did not reach sit idle")
	dog._state_duration = 0.0
	await create_timer(0.05).timeout
	_check(String(dog._sprite.animation) == "sit_enter" and dog._sprite.is_playing(), "sit exit did not reverse the transition")
	await create_timer(1.65).timeout
	_check(dog._state in [0, 1], "sit exit did not return to normal behavior; state=%s animation=%s visible=%s" % [dog._state, dog._sprite.animation, dog.visible])

	if _failures.is_empty():
		print("DOG_ACTIONS_QA_OK animations=5 frames_each=8 scale=1.7")
		quit()
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
