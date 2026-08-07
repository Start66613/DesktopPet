extends Control
class_name PetMirrorPreview

const IDLE_DIR := "res://assets/sprites/idle"
const IDLE_FPS := 4.0
const FRAME_COUNT := 8

var _sprite: AnimatedSprite2D
var _fallback_texture: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_sprite = AnimatedSprite2D.new()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	_build_idle_animation()
	resized.connect(_layout_sprite)
	_layout_sprite()
	queue_redraw()


func set_fallback_texture(texture: Texture2D) -> void:
	_fallback_texture = texture
	if _sprite and _sprite.sprite_frames.get_frame_count(&"idle") == 0:
		_build_idle_animation()


func _build_idle_animation() -> void:
	if not _sprite:
		return
	var frames := SpriteFrames.new()
	frames.add_animation(&"idle")
	frames.set_animation_loop(&"idle", true)
	frames.set_animation_speed(&"idle", IDLE_FPS)
	for index in range(1, FRAME_COUNT + 1):
		var frame_path := IDLE_DIR + "/idle_%02d.png" % index
		var texture := load(frame_path) as Texture2D
		if texture:
			frames.add_frame(&"idle", texture)
	if frames.get_frame_count(&"idle") == 0 and _fallback_texture:
		frames.add_frame(&"idle", _fallback_texture)
	_sprite.sprite_frames = frames
	if frames.get_frame_count(&"idle") > 0:
		_sprite.play(&"idle")


func _layout_sprite() -> void:
	if not _sprite:
		return
	_sprite.position = size * 0.5 + Vector2(0.0, 3.0)
	var scale_factor := minf(size.x / 256.0, size.y / 256.0) * 0.94
	_sprite.scale = Vector2.ONE * scale_factor


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("fdf1ec"))
