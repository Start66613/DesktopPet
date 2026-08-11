extends Control
class_name PetMusicProgressControl

signal seek_requested(ratio: float)

const ROSE_TEXTURE := preload("res://assets/music/runtime/ui/rose.png")

var value := 0.0:
	set(next_value):
		value = clampf(next_value, 0.0, 1.0)
		queue_redraw()
var interactive := false
var _dragging := false


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "拖动播放进度"
	custom_minimum_size = Vector2(100, 34)
	queue_redraw()


func _draw() -> void:
	var center_y := size.y * 0.5
	var start_x := 16.0
	var end_x := maxf(size.x - 16.0, start_x + 1.0)
	var width := end_x - start_x
	var track_rect := Rect2(start_x, center_y - 4.0, width, 8.0)
	draw_style_box(_rounded_box(Color("f2d9d8"), 4.0), track_rect)
	var fill_width := width * value
	if fill_width > 1.0:
		draw_style_box(_rounded_box(Color("e98f9f"), 4.0), Rect2(start_x, center_y - 4.0, fill_width, 8.0))
	var handle_size := Vector2(31, 25)
	var handle_center := Vector2(start_x + fill_width, center_y)
	draw_texture_rect(ROSE_TEXTURE, Rect2(handle_center - handle_size * 0.5, handle_size), false)


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_set_from_mouse(event.position.x)
		else:
			seek_requested.emit(value)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_set_from_mouse(event.position.x)
		accept_event()


func _set_from_mouse(mouse_x: float) -> void:
	var width := maxf(size.x - 32.0, 1.0)
	value = clampf((mouse_x - 16.0) / width, 0.0, 1.0)


func _rounded_box(color: Color, radius: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(roundi(radius))
	return box
