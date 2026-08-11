extends SceneTree

const BRIDGE_PATH := "res://tools/music_session_bridge.exe"


func _init() -> void:
	var output: Array = []
	var cover_path := ProjectSettings.globalize_path("user://music_bridge_qa_cover.bin")
	var exit_code := OS.execute(ProjectSettings.globalize_path(BRIDGE_PATH), PackedStringArray(["status", cover_path]), output, false, false)
	if exit_code != 0 or output.is_empty():
		push_error("Music bridge did not return a status payload")
		quit(1)
		return
	var payload = JSON.parse_string(String(output[0]).strip_edges())
	if not payload is Dictionary:
		push_error("Music bridge returned invalid JSON")
		quit(1)
		return
	if bool(payload.get("found", false)):
		var source_label := String(payload.get("source_label", ""))
		if source_label not in ["QQ音乐", "网易云音乐", "本地播放器"]:
			push_error("Music bridge text encoding is invalid: " + source_label)
			quit(1)
			return
		for key in ["repeat_mode", "shuffle_active", "can_repeat", "can_shuffle"]:
			if not payload.has(key):
				push_error("Music bridge mode field is missing: " + key)
				quit(1)
				return
		print("MUSIC_BRIDGE_QA_OK source=%s title=%s repeat=%s shuffle=%s" % [source_label, payload.get("title", ""), payload.get("repeat_mode", "unknown"), payload.get("shuffle_active", false)])
	else:
		print("MUSIC_BRIDGE_QA_OK no_session=true")
	quit()
