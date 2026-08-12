extends Node
class_name PetForegroundAppMonitor

signal foreground_app_changed(info: Dictionary)

const POLL_INTERVAL := 12.0
const PROBE_FILE_NAME := "foreground_app_probe.exe"
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
	_poll_time = 0.0 if _enabled else POLL_INTERVAL
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
	var probe_path := _native_helper_path(PROBE_FILE_NAME)
	if FileAccess.file_exists(probe_path):
		var probe_output: Array = []
		var probe_code := OS.execute(probe_path, PackedStringArray(), probe_output, false, false)
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


func _native_helper_path(file_name: String) -> String:
	var installed_path := OS.get_executable_path().get_base_dir().path_join(file_name)
	if FileAccess.file_exists(installed_path):
		return installed_path
	return ProjectSettings.globalize_path("res://tools/" + file_name)


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
	var segments := raw_name.split("\n", false)
	if segments.is_empty():
		return ""
	var line := String(segments[0]).strip_edges()
	if line.is_empty():
		return ""
	var cleaner := RegEx.new()
	cleaner.compile("[^A-Za-z0-9_.-]")
	return cleaner.sub(line, "", true).left(48)


func _classify_process(process_name: String) -> Dictionary:
	var key := process_name.to_lower().trim_suffix(".exe")
	var label := "其他应用"
	var activity := "使用电脑"
	var recognized := true
	if key in ["wps", "wpp", "et", "wpspdf", "winword", "excel", "powerpnt", "libreoffice"]:
		match key:
			"wps", "wpp", "et", "wpspdf":
				label = "WPS"
			"winword":
				label = "Word"
			"excel":
				label = "Excel"
			"powerpnt":
				label = "PowerPoint"
			_:
				label = "办公软件"
		activity = "工作或学习"
	elif key in ["chrome", "msedge", "firefox", "opera", "brave", "vivaldi"]:
		var browser_labels := {
			"chrome": "Chrome", "msedge": "Edge", "firefox": "Firefox",
			"opera": "Opera", "brave": "Brave", "vivaldi": "Vivaldi"
		}
		label = String(browser_labels.get(key, "浏览器"))
		activity = "浏览网页"
	elif key in ["code", "cursor", "devenv", "idea64", "pycharm64", "webstorm64", "rider64", "androidstudio"]:
		var development_labels := {
			"code": "VS Code", "cursor": "Cursor", "devenv": "Visual Studio",
			"idea64": "IntelliJ IDEA", "pycharm64": "PyCharm", "webstorm64": "WebStorm",
			"rider64": "Rider", "androidstudio": "Android Studio"
		}
		label = String(development_labels.get(key, "开发工具"))
		activity = "编程或创作"
	elif key in ["chatgpt", "claude"]:
		label = "ChatGPT" if key == "chatgpt" else "Claude"
		activity = "使用 AI 助手"
	elif key in ["wechat", "weixin", "qq", "telegram", "discord", "dingtalk", "feishu"]:
		var chat_labels := {
			"wechat": "微信", "weixin": "微信", "qq": "QQ", "telegram": "Telegram",
			"discord": "Discord", "dingtalk": "钉钉", "feishu": "飞书"
		}
		label = String(chat_labels.get(key, "聊天软件"))
		activity = "沟通交流"
	elif key in ["cloudmusic", "spotify", "qqmusic", "potplayermini64", "vlc", "mpv"]:
		var media_labels := {
			"cloudmusic": "网易云音乐", "spotify": "Spotify", "qqmusic": "QQ音乐",
			"potplayermini64": "PotPlayer", "vlc": "VLC", "mpv": "MPV"
		}
		label = String(media_labels.get(key, "影音软件"))
		activity = "听歌或看视频"
	elif key in ["steam", "steamwebhelper", "epicgameslauncher", "riotclientservices", "leagueclient"]:
		label = "Steam" if key in ["steam", "steamwebhelper"] else "游戏平台"
		activity = "准备玩游戏"
	elif key in ["explorer", "searchhost", "shellexperiencehost"]:
		label = "Windows 桌面"
		activity = "整理电脑"
	else:
		recognized = false
	return {
		"process": process_name,
		"label": label,
		"activity": activity,
		"recognized": recognized
	}
