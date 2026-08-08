extends Node
class_name PetForegroundAppMonitor

signal foreground_app_changed(info: Dictionary)

const POLL_INTERVAL := 12.0
const PROBE_PATH := "res://tools/foreground_app_probe.exe"
const TASKLIST_QUERY := "tasklist.exe"
const SYSTEM_PROCESSES := [
	"system", "system idle process", "registry", "smss", "csrss", "wininit", "winlogon",
	"services", "lsass", "svchost", "fontdrvhost", "dwm", "conhost", "sihost", "taskhostw",
	"runtimebroker", "searchhost", "shellexperiencehost", "textinputhost", "applicationframehost",
	"startmenuexperiencehost", "explorer", "securityhealthservice", "msmpeng", "nvcontainer",
	"nvdisplay.container", "nvidia overlay", "asusoptimizationstartuptask", "ipf_helper",
	"armourycrate.usersessionhelper"
]

var _enabled := false
var _poll_time := 0.0
var _query_thread: Thread
var _query_running := false
var _current_info: Dictionary = {}


func _process(delta: float) -> void:
	if _query_running and _query_thread and not _query_thread.is_alive():
		var process_names := String(_query_thread.wait_to_finish())
		_query_thread = null
		_query_running = false
		_apply_process_names(process_names)

	if not _enabled or _query_running:
		return
	_poll_time -= delta
	if _poll_time <= 0.0:
		_poll_time = POLL_INTERVAL
		_start_query()


func _exit_tree() -> void:
	if _query_running and _query_thread:
		_query_thread.wait_to_finish()


func set_enabled(value: bool) -> void:
	_enabled = value and OS.get_name() == "Windows" and not OS.get_cmdline_args().has("--headless")
	_poll_time = POLL_INTERVAL
	if not _enabled and not _current_info.is_empty():
		_current_info.clear()
		foreground_app_changed.emit({})


func is_enabled() -> bool:
	return _enabled


func get_current_info() -> Dictionary:
	return _current_info.duplicate(true)


func refresh_now() -> void:
	if _enabled:
		_poll_time = 0.0


func _start_query() -> void:
	_query_thread = Thread.new()
	var error := _query_thread.start(_query_foreground_process)
	if error == OK:
		_query_running = true
	else:
		_query_thread = null


func _query_foreground_process() -> String:
	if FileAccess.file_exists(PROBE_PATH):
		var probe_output: Array = []
		var probe_code := OS.execute(ProjectSettings.globalize_path(PROBE_PATH), PackedStringArray(), probe_output, false, false)
		if probe_code == 0 and not probe_output.is_empty():
			return String(probe_output[0]).strip_edges()

	# The fallback deliberately avoids PowerShell. It only provides a coarse list
	# when the optional native probe was not included in a development checkout.
	var output: Array = []
	var arguments := PackedStringArray(["/fi", "SESSIONNAME eq Console", "/fo", "csv", "/nh"])
	var exit_code := OS.execute(TASKLIST_QUERY, arguments, output, false, false)
	if exit_code != 0 or output.is_empty():
		return ""
	return _format_tasklist_output(String(output[0]))


func _format_tasklist_output(raw_output: String) -> String:
	var process_names: Array[String] = []
	for line in raw_output.split("\n", false):
		var fields := String(line).strip_edges().split(",")
		if fields.is_empty():
			continue
		var process_name := _sanitize_process_name(String(fields[0]).trim_prefix("\"").trim_suffix("\""))
		var key := process_name.to_lower()
		if process_name.is_empty() or SYSTEM_PROCESSES.has(key) or process_names.has(process_name):
			continue
		process_names.append(process_name)
		if process_names.size() >= 8:
			break
	if process_names.is_empty():
		return ""
	return "FOREGROUND:" + process_names[0] + "\nVISIBLE:" + ",".join(process_names)


func _apply_process_names(raw_names: String) -> void:
	var lines := raw_names.split("\n", false)
	var process_name := ""
	var visible_processes: Array[String] = []
	for line in lines:
		var clean_line := String(line).strip_edges()
		if clean_line.begins_with("FOREGROUND:"):
			process_name = _sanitize_process_name(clean_line.trim_prefix("FOREGROUND:"))
			if _is_ignored_process(process_name):
				process_name = ""
		elif clean_line.begins_with("VISIBLE:"):
			for raw_visible in clean_line.trim_prefix("VISIBLE:").split(",", false):
				var visible_name := _sanitize_process_name(String(raw_visible))
				if not visible_name.is_empty() and not _is_ignored_process(visible_name) and not visible_processes.has(visible_name):
					visible_processes.append(visible_name)
	if process_name.is_empty() and not visible_processes.is_empty():
		var previous_process := String(_current_info.get("process", ""))
		process_name = previous_process if visible_processes.has(previous_process) else visible_processes[0]
	if process_name.is_empty():
		if not _current_info.is_empty():
			_current_info.clear()
			foreground_app_changed.emit({})
		return
	var next_info := _classify_process(process_name)
	next_info["visible_processes"] = visible_processes
	next_info["visible_count"] = visible_processes.size()
	var visible_apps: Array[Dictionary] = []
	for visible_name in visible_processes:
		visible_apps.append(_classify_process(visible_name))
	next_info["visible_apps"] = visible_apps
	if next_info == _current_info:
		return
	_current_info = next_info
	foreground_app_changed.emit(get_current_info())


func _is_ignored_process(process_name: String) -> bool:
	var key := process_name.to_lower().trim_suffix(".exe")
	if key.begins_with("godot_v") or key == "desktoppet":
		return true
	return SYSTEM_PROCESSES.has(key)


func _sanitize_process_name(raw_name: String) -> String:
	var line := raw_name.split("\n", false)[0].strip_edges()
	var cleaner := RegEx.new()
	cleaner.compile("[^A-Za-z0-9_.-]")
	return cleaner.sub(line, "", true).left(48)


func _classify_process(process_name: String) -> Dictionary:
	var key := process_name.to_lower()
	var label := process_name
	var activity := "使用电脑"
	if key in ["wps", "wpp", "et", "wpspdf", "winword", "excel", "powerpnt", "libreoffice"]:
		label = "办公软件"
		activity = "工作或学习"
	elif key in ["chrome", "msedge", "firefox", "opera", "brave", "vivaldi"]:
		label = "浏览器"
		activity = "浏览网页"
	elif key in ["code", "devenv", "idea64", "pycharm64", "webstorm64", "rider64", "androidstudio", "godot"]:
		label = "开发工具"
		activity = "编程或创作"
	elif key in ["wechat", "weixin", "qq", "telegram", "discord", "dingtalk", "feishu"]:
		label = "聊天软件"
		activity = "沟通交流"
	elif key in ["cloudmusic", "spotify", "qqmusic", "potplayermini64", "vlc", "mpv"]:
		label = "影音软件"
		activity = "听歌或看视频"
	elif key in ["steam", "steamwebhelper", "epicgameslauncher", "riotclientservices", "leagueclient"]:
		label = "游戏平台"
		activity = "准备玩游戏"
	elif key in ["explorer", "searchhost", "shellexperiencehost"]:
		label = "Windows 桌面"
		activity = "整理电脑"
	return {
		"process": process_name,
		"label": label,
		"activity": activity
	}
