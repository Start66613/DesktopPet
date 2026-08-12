extends SceneTree

const PET_SCRIPT_PATH := "res://scripts/pet.gd"
const OUTPUT_PATH := "res://assets/runtime/pet_sprite_frames.tres"


func _initialize() -> void:
	var pet_script := load(PET_SCRIPT_PATH) as Script
	if pet_script == null:
		push_error("Unable to load pet script: " + PET_SCRIPT_PATH)
		quit(1)
		return

	var pet = pet_script.new()
	var frames = pet.call("_build_sprite_frames") as SpriteFrames
	pet.free()
	if frames == null or frames.get_animation_names().is_empty():
		push_error("Pet SpriteFrames generation produced no animations.")
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_PATH.get_base_dir()))
	var result := ResourceSaver.save(frames, OUTPUT_PATH)
	if result != OK:
		push_error("Unable to save pet SpriteFrames: %s" % error_string(result))
		quit(1)
		return

	var total_frames := 0
	for animation_name in frames.get_animation_names():
		total_frames += frames.get_frame_count(animation_name)
	print("PET_SPRITE_FRAMES_BUILT animations=%d frames=%d path=%s" % [
		frames.get_animation_names().size(),
		total_frames,
		OUTPUT_PATH,
	])
	quit(0)
