extends SceneTree

const LyricsService := preload("res://scripts/music_lyrics_service.gd")

var _finished := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var service := LyricsService.new()
	root.add_child(service)
	await process_frame
	service.lyrics_ready.connect(_on_lyrics_ready)
	service.lyrics_failed.connect(_on_lyrics_failed)
	service.request_lyrics({
		"track_id": "qa-sunny-day",
		"title": "晴天",
		"artist": "周杰伦",
		"duration_ms": 269000
	})
	await create_timer(15.0).timeout
	if not _finished:
		push_error("Music lyrics QA timed out")
		quit(1)


func _on_lyrics_ready(track_id: String, lines: Array[Dictionary], source: String) -> void:
	_finished = true
	if track_id != "qa-sunny-day" or lines.size() < 12:
		push_error("Music lyrics QA returned incomplete data")
		quit(1)
		return
	for index in range(1, lines.size()):
		if int(lines[index]["time_ms"]) < int(lines[index - 1]["time_ms"]):
			push_error("Music lyrics QA returned unsorted timestamps")
			quit(1)
			return
	print("MUSIC_FEATURE_QA_OK source=%s lines=%d" % [source, lines.size()])
	quit()


func _on_lyrics_failed(_track_id: String, message: String) -> void:
	_finished = true
	push_error("Music lyrics QA failed: " + message)
	quit(1)
