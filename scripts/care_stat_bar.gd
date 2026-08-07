extends Control
class_name PetCareStatBar

var _value := 0.0
var _fill_color := Color.WHITE
var _track_style: StyleBoxFlat
var _fill_style: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func configure(fill_color: Color) -> void:
	_fill_color = fill_color
	_track_style = StyleBoxFlat.new()
	_track_style.bg_color = Color(1.0, 0.975, 0.965, 0.94)
	_track_style.border_color = Color("edd3d1")
	_track_style.set_border_width_all(1)
	_track_style.set_corner_radius_all(5)
	_fill_style = StyleBoxFlat.new()
	_fill_style.bg_color = _fill_color
	_fill_style.set_corner_radius_all(4)
	queue_redraw()


func set_value(next_value: float) -> void:
	_value = clampf(next_value, 0.0, 100.0)
	queue_redraw()


func _draw() -> void:
	if not _track_style or not _fill_style:
		return
	var track_rect := Rect2(Vector2.ZERO, size)
	draw_style_box(_track_style, track_rect)
	if _value <= 0.0:
		return
	var inner_rect := Rect2(Vector2.ONE, size - Vector2(2.0, 2.0))
	var fill_width := inner_rect.size.x * (_value / 100.0)
	fill_width = maxf(fill_width, minf(inner_rect.size.y, inner_rect.size.x))
	var fill_rect := Rect2(inner_rect.position, Vector2(fill_width, inner_rect.size.y))
	draw_style_box(_fill_style, fill_rect)
