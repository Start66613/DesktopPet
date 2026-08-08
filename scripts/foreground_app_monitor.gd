extends Node
class_name PetForegroundAppMonitor

signal foreground_app_changed(info: Dictionary)

const POLL_INTERVAL := 12.0
const POWERSHELL_QUERY := "Add-Type -Name ForegroundWindow -Namespace DesktopPet -MemberDefinition '[System.Runtime.InteropServices.DllImport(\"user32.dll\")] public static extern System.IntPtr GetForegroundWindow(); [System.Runtime.InteropServices.DllImport(\"user32.dll\")] public static extern uint GetWindowThreadProcessId(System.IntPtr hWnd, out uint processId);'; $handle=[DesktopPet.ForegroundWindow]::GetForegroundWindow(); [uint32]$foregroundPid=0; [DesktopPet.ForegroundWindow]::GetWindowThreadProcessId($handle,[ref]$foregroundPid) | Out-Null; $foreground=(Get-Process -Id $foregroundPid -ErrorAction SilentlyContinue).ProcessName; $visible=(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -ne '' -and $_.ProcessName -notin @('explorer','SearchHost','ShellExperienceHost','ApplicationFrameHost','TextInputHost','sihost','dwm','conhost','powershell','pwsh') } | Select-Object -ExpandProperty ProcessName -Unique | Select-Object -First 8); Write-Output ('FOREGROUND:' + $foreground); Write-Output ('VISIBLE:' + (($visible -join ',') -replace '[\r\n]',''))"

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
	var output: Array = []
	var arguments := PackedStringArray([
		"-NoLogo",
		"-NoProfile",
		"-NonInteractive",
		"-WindowStyle",
		"Hidden",
		"-Command",
		POWERSHELL_QUERY
	])
	var exit_code := OS.execute("powershell.exe", arguments, output, false, false)
	if exit_code != 0 or output.is_empty():
		return ""
	return String(output[0]).strip_edges()


func _apply_process_names(raw_names: String) -> void:
	var lines := raw_names.split("\n", false)
	var process_name := ""
	var visible_processes: Array[String] = []
	for line in lines:
		var clean_line := String(line).strip_edges()
		if clean_line.begins_with("FOREGROUND:"):
			process_name = _sanitize_process_name(clean_line.trim_prefix("FOREGROUND:"))
		elif clean_line.begins_with("VISIBLE:"):
			for raw_visible in clean_line.trim_prefix("VISIBLE:").split(",", false):
				var visible_name := _sanitize_process_name(String(raw_visible))
				if not visible_name.is_empty() and not visible_processes.has(visible_name):
					visible_processes.append(visible_name)
	if process_name.is_empty():
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
