extends Node2D
class_name PetSpeechBubble

const BUBBLE_BODY_TEXTURE := preload("res://assets/care/runtime/bubbles/speech_body.png")
const BUBBLE_TAIL_TEXTURE := preload("res://assets/care/runtime/bubbles/speech_tail.png")
const BODY_RECT := Rect2(0, 0, 220, 52)
const TAIL_RECT := Rect2(98, 49, 24, 15)
const BUBBLE_BOUNDS := Rect2(0, 0, 220, 64)
const FONT_SIZE := 14
const EMOJI_SIZE := 15
const TEXT_COLOR := Color("573f49")

var _text := ""
var _emoji := ""
var _cjk_font: Font
var _emoji_font: Font


func _ready() -> void:
	z_index = 1000
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
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


func get_local_bounds() -> Rect2:
	return BUBBLE_BOUNDS


func _draw() -> void:
	if not visible:
		return

	draw_texture_rect(BUBBLE_BODY_TEXTURE, BODY_RECT, false)
	draw_texture_rect(BUBBLE_TAIL_TEXTURE, TAIL_RECT, false)

	if _cjk_font and not _text.is_empty():
		if _text.length() > 13:
			draw_multiline_string(_cjk_font, Vector2(14, 20), _text, HORIZONTAL_ALIGNMENT_CENTER, 172, 12, 2, TEXT_COLOR)
		else:
			draw_string(_cjk_font, Vector2(16, 34), _text, HORIZONTAL_ALIGNMENT_CENTER, 168, FONT_SIZE, TEXT_COLOR)
	if _emoji_font and not _emoji.is_empty():
		draw_string(_emoji_font, Vector2(188, 35), _emoji, HORIZONTAL_ALIGNMENT_CENTER, 24, EMOJI_SIZE, TEXT_COLOR)
