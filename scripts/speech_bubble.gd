extends Node2D
class_name PetSpeechBubble

const ROOT_SIZE := Vector2(250, 88)
const PANEL_RECT := Rect2(0, 0, 230, 64)
const FONT_SIZE := 16
const EMOJI_SIZE := 20
const TEXT_COLOR := Color("2a2430")
const BACKGROUND_COLOR := Color(1.0, 0.96, 0.98, 0.98)
const BORDER_COLOR := Color(0.72, 0.48, 0.62, 0.98)

var _text := ""
var _emoji := ""
var _cjk_font: Font
var _emoji_font: Font
var _bubble_style: StyleBoxFlat


func _ready() -> void:
	z_index = 1000
	_bubble_style = StyleBoxFlat.new()
	_bubble_style.bg_color = BACKGROUND_COLOR
	_bubble_style.border_color = BORDER_COLOR
	_bubble_style.set_border_width_all(2)
	_bubble_style.set_corner_radius_all(15)
	_bubble_style.shadow_color = Color(0, 0, 0, 0.22)
	_bubble_style.shadow_size = 4
	queue_redraw()


func configure_fonts(cjk_font: Font, emoji_font: Font) -> void:
	_cjk_font = cjk_font
	_emoji_font = emoji_font
	queue_redraw()


func set_message(text: String, emoji: String) -> void:
	_text = text
	_emoji = emoji
	visible = true
	queue_redraw()


func clear_message() -> void:
	_text = ""
	_emoji = ""
	visible = false
	queue_redraw()


func _draw() -> void:
	if not visible or _bubble_style == null:
		return

	# Draw the complete bubble in one CanvasItem so transparent windows cannot clip its Control children.
	draw_style_box(_bubble_style, PANEL_RECT)
	var tail_points := PackedVector2Array([
		Vector2(145, 62),
		Vector2(161, 62),
		Vector2(153, 82)
	])
	draw_colored_polygon(tail_points, BACKGROUND_COLOR)
	draw_polyline(PackedVector2Array([
		tail_points[0], tail_points[2], tail_points[1]
	]), BORDER_COLOR, 2.0, true)

	if _cjk_font and not _text.is_empty():
		draw_string(_cjk_font, Vector2(14, 39), _text, HORIZONTAL_ALIGNMENT_CENTER, 170, FONT_SIZE, TEXT_COLOR)
	if _emoji_font and not _emoji.is_empty():
		draw_string(_emoji_font, Vector2(191, 41), _emoji, HORIZONTAL_ALIGNMENT_CENTER, 27, EMOJI_SIZE, TEXT_COLOR)
