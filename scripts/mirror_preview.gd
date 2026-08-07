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
	var center := size * 0.5
	var radius_x := maxf(size.x * 0.5 - 4.0, 1.0)
	var radius_y := maxf(size.y * 0.5 - 3.0, 1.0)
	var edge_points := PackedVector2Array()
	for index in range(40):
		var angle := TAU * float(index) / 40.0
		edge_points.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	draw_colored_polygon(edge_points, Color("fff7fa"))

	var outline := PackedVector2Array(edge_points)
	outline.append(edge_points[0])
	draw_polyline(outline, Color("eeb7c2"), 1.0, true)

	for y_offset in [-35.0, -19.0, -3.0, 13.0, 29.0]:
		var offset: float = y_offset
		var normalized: float = offset / radius_y
		var half_width: float = sqrt(maxf(0.0, 1.0 - normalized * normalized)) * radius_x
		var start := center + Vector2(-half_width + 9.0, offset)
		var end := center + Vector2(half_width - 9.0, offset)
		draw_line(start, end, Color("f4d8df"), 1.0, true)
