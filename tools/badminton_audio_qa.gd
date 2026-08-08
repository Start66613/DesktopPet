extends SceneTree

const AUDIO_DIR := "res://assets/minigames/badminton/runtime/audio"
const AUDIO_STEMS := [
	"badminton_bgm",
	"ui_confirm",
	"serve",
	"hit",
	"perfect",
	"smash",
	"score_player",
	"score_pet",
	"win",
	"lose",
]


func _initialize() -> void:
	var failed := false
	for stem in AUDIO_STEMS:
		var path := "%s/%s.mp3" % [AUDIO_DIR, stem]
		var stream := load(path) as AudioStream
		if not stream:
			push_error("Missing or invalid badminton audio: %s" % path)
			failed = true
			continue
		var length := stream.get_length()
		if length <= 0.0:
			push_error("Invalid badminton audio duration: %s" % path)
			failed = true
		print("[BadmintonAudioQA] %s length=%.3fs" % [stem, length])

	var bgm := load(AUDIO_DIR + "/badminton_bgm.mp3") as AudioStreamMP3
	if bgm:
		bgm.loop = true
		if not bgm.loop:
			push_error("Badminton BGM loop flag could not be enabled")
			failed = true

	quit(1 if failed else 0)
