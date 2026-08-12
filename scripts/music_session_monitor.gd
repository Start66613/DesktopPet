extends Node
class_name PetMusicSessionMonitor

signal session_updated(info: Dictionary)
signal track_changed(info: Dictionary)
signal playback_changed(playing: bool, info: Dictionary)
signal availability_changed(available: bool)
signal bridge_error(message: String)

const BRIDGE_FILE_NAME := "music_session_bridge.exe"
const COVER_PATH := "user://music_session_cover.bin"
const POLL_INTERVAL := 1.5

var _enabled := true
var _poll_time := 0.0
var _worker: Thread
var _worker_running := false
var _worker_kind := ""
var _pending_commands: Array[PackedStringArray] = []
var _session: Dictionary = {"found": false}
var _last_error := ""
var _status_received_at_ms := 0


func _ready() -> void:
	_enabled = OS.get_name() == "Windows" and not OS.get_cmdline_args().has("--headless")
	_poll_time = 0.0


func _process(delta: float) -> void:
	if _worker_running and _worker and not _worker.is_alive():
		var result: Dictionary = _worker.wait_to_finish()
		_worker = null
		_worker_running = false
		_finish_job(result)

	if not _enabled or _worker_running:
		return
	if not _pending_commands.is_empty():
		var command: PackedStringArray = _pending_commands.pop_front()
		_start_job("command", command)
		return
	_poll_time -= delta
	if _poll_time <= 0.0:
		_poll_time = POLL_INTERVAL
		_start_job("status", PackedStringArray(["status", ProjectSettings.globalize_path(COVER_PATH)]))


func _exit_tree() -> void:
	if _worker_running and _worker:
		_worker.wait_to_finish()


func set_enabled(value: bool) -> void:
	_enabled = value and OS.get_name() == "Windows" and not OS.get_cmdline_args().has("--headless")
	_poll_time = 0.0
	if not _enabled:
		_pending_commands.clear()


func is_enabled() -> bool:
	return _enabled


func has_session() -> bool:
	return bool(_session.get("found", false))


func is_playing() -> bool:
	return has_session() and String(_session.get("playback_status", "")) == "playing"


func get_session() -> Dictionary:
	var current := _session.duplicate(true)
	if is_playing():
		var elapsed := maxi(Time.get_ticks_msec() - _status_received_at_ms, 0)
		var duration := int(current.get("duration_ms", 0))
		var estimated := int(current.get("position_ms", 0)) + elapsed
		current["position_ms"] = mini(estimated, duration) if duration > 0 else estimated
	return current


func refresh_now() -> void:
	_poll_time = 0.0


func toggle_play_pause() -> void:
	_queue_command(PackedStringArray(["toggle"]))


func play() -> void:
	_queue_command(PackedStringArray(["play"]))


func pause() -> void:
	_queue_command(PackedStringArray(["pause"]))


func skip_next() -> void:
	_queue_command(PackedStringArray(["next"]))


func skip_previous() -> void:
	_queue_command(PackedStringArray(["previous"]))


func seek_to(position_ms: int) -> void:
	_queue_command(PackedStringArray(["seek", str(maxi(position_ms, 0))]))


func set_play_mode(mode: String) -> void:
	match mode:
		"sequential":
			_queue_command(PackedStringArray(["shuffle", "false"]))
			_queue_command(PackedStringArray(["repeat", "none"]))
		"list":
			_queue_command(PackedStringArray(["shuffle", "false"]))
			_queue_command(PackedStringArray(["repeat", "list"]))
		"single":
			_queue_command(PackedStringArray(["shuffle", "false"]))
			_queue_command(PackedStringArray(["repeat", "track"]))
		"shuffle":
			_queue_command(PackedStringArray(["repeat", "none"]))
			_queue_command(PackedStringArray(["shuffle", "true"]))


func get_cover_bytes() -> PackedByteArray:
	if not bool(_session.get("cover_written", false)) or not FileAccess.file_exists(COVER_PATH):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(COVER_PATH)


func _queue_command(arguments: PackedStringArray) -> void:
	if not _enabled:
		return
	_pending_commands.append(arguments)
	_poll_time = 0.0


func _start_job(kind: String, arguments: PackedStringArray) -> void:
	var bridge_path := _native_helper_path(BRIDGE_FILE_NAME)
	if not FileAccess.file_exists(bridge_path):
		_report_error("音乐检测组件缺失")
		return
	_worker_kind = kind
	_worker = Thread.new()
	var error := _worker.start(_execute_bridge.bind(bridge_path, arguments))
	if error == OK:
		_worker_running = true
	else:
		_worker = null
		_report_error("音乐检测线程启动失败")


func _execute_bridge(bridge_path: String, arguments: PackedStringArray) -> Dictionary:
	var output: Array = []
	var exit_code := OS.execute(bridge_path, arguments, output, false, false)
	return {
		"exit_code": exit_code,
		"output": String(output[0]).strip_edges() if not output.is_empty() else ""
	}


func _native_helper_path(file_name: String) -> String:
	var installed_path := OS.get_executable_path().get_base_dir().path_join(file_name)
	if FileAccess.file_exists(installed_path):
		return installed_path
	return ProjectSettings.globalize_path("res://tools/" + file_name)


func _finish_job(result: Dictionary) -> void:
	var text := String(result.get("output", "")).strip_edges()
	var parsed = JSON.parse_string(text) if not text.is_empty() else null
	if not parsed is Dictionary:
		_report_error("音乐检测暂时没有响应")
		return
	var payload: Dictionary = parsed
	if not bool(payload.get("success", false)) and _worker_kind == "status":
		_report_error(String(payload.get("error", "音乐检测失败")))
		return
	_last_error = ""
	if _worker_kind == "status":
		_apply_status(payload)
	else:
		_poll_time = 0.0


func _apply_status(next: Dictionary) -> void:
	var was_available := has_session()
	var was_playing := is_playing()
	var previous_track := String(_session.get("track_id", ""))
	_session = next.duplicate(true)
	_status_received_at_ms = Time.get_ticks_msec()
	var available := has_session()
	var playing := is_playing()
	if available != was_available:
		availability_changed.emit(available)
	if available and not String(_session.get("track_id", "")).is_empty() and String(_session.get("track_id", "")) != previous_track:
		track_changed.emit(get_session())
	if playing != was_playing:
		playback_changed.emit(playing, get_session())
	session_updated.emit(get_session())


func _report_error(message: String) -> void:
	if message == _last_error:
		return
	_last_error = message
	bridge_error.emit(message)
