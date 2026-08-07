extends Node2D
class_name PetSpeechBubble

const BUBBLE_TEXTURE := preload("res://assets/ui_source/generated/1-animations/textures/37_spritesheet.png")
const PANEL_RECT := Rect2(0, 0, 220, 90)
const FONT_SIZE := 15
const EMOJI_SIZE := 16
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


func _draw() -> void:
	if not visible:
		return

	draw_texture_rect(BUBBLE_TEXTURE, PANEL_RECT, false)

	if _cjk_font and not _text.is_empty():
		draw_string(_cjk_font, Vector2(16, 53), _text, HORIZONTAL_ALIGNMENT_CENTER, 168, FONT_SIZE, TEXT_COLOR)
	if _emoji_font and not _emoji.is_empty():
		draw_string(_emoji_font, Vector2(188, 55), _emoji, HORIZONTAL_ALIGNMENT_CENTER, 24, EMOJI_SIZE, TEXT_COLOR)
