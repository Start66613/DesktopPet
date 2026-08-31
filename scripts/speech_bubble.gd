extends Node2D
class_name PetSpeechBubble

const BUBBLE_BODY_TEXTURE := preload("res://assets/care/runtime/bubbles/speech_body.png")
const BUBBLE_TAIL_TEXTURE := preload("res://assets/care/runtime/bubbles/speech_tail.png")
const BODY_RECT := Rect2(0, 0, 220, 72)
const TAIL_RECT := Rect2(98, 69, 24, 15)
const BUBBLE_BOUNDS := Rect2(0, 0, 220, 84)
const FONT_SIZE := 14
const LONG_TEXT_FONT_SIZE := 12
const EMOJI_SIZE := 15
const TEXT_COLOR := Color("573f49")
const TEXT_LEFT := 27.0
const TEXT_WIDTH := 153.0

var _text := ""
var _emoji := ""
var _cjk_font: Font
var _emoji_font: Font
var _show_tween: Tween


func _ready() -> void:
	z_index = 1000
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	visible = false
	modulate = Color.WHITE
	scale = Vector2.ONE
	queue_redraw()


func configure_fonts(cjk_font: Font, emoji_font: Font) -> void:
	_cjk_font = cjk_font
	_emoji_font = emoji_font
	queue_redraw()


func set_message(text: String, emoji: String) -> void:
	_text = text
	_emoji = emoji
	if _show_tween and _show_tween.is_valid():
		_show_tween.kill()
	visible = true
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	scale = Vector2.ONE * 0.96
	queue_redraw()
	_show_tween = create_tween().set_parallel(true)
	_show_tween.tween_property(self, "modulate:a", 1.0, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_show_tween.tween_property(self, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func clear_message() -> void:
	if _show_tween and _show_tween.is_valid():
		_show_tween.kill()
	_text = ""
	_emoji = ""
	modulate = Color.WHITE
	scale = Vector2.ONE
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
		var measured_width := _cjk_font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		if measured_width > TEXT_WIDTH:
			draw_multiline_string(_cjk_font, Vector2(TEXT_LEFT, 18), _text, HORIZONTAL_ALIGNMENT_CENTER, TEXT_WIDTH, LONG_TEXT_FONT_SIZE, 3, TEXT_COLOR)
		else:
			draw_string(_cjk_font, Vector2(TEXT_LEFT, 44), _text, HORIZONTAL_ALIGNMENT_CENTER, TEXT_WIDTH, FONT_SIZE, TEXT_COLOR)
	if _emoji_font and not _emoji.is_empty():
		draw_string(_emoji_font, Vector2(188, 45), _emoji, HORIZONTAL_ALIGNMENT_CENTER, 24, EMOJI_SIZE, TEXT_COLOR)
