extends Node2D
class_name PetSpeechBubble

const BUBBLE_BODY_TEXTURE := preload("res://assets/care/runtime/bubbles/speech_body.png")
const BUBBLE_TAIL_TEXTURE := preload("res://assets/care/runtime/bubbles/speech_tail.png")
const BODY_RECT := Rect2(0, 0, 316, 112)
const TAIL_SIZE := Vector2(28, 18)
const TAIL_CENTER_X := 158.0
const TAIL_TOP := 107.0
const BUBBLE_BOUNDS := Rect2(0, 0, 316, 125)
const FONT_SIZE := 14
const LONG_TEXT_FONT_SIZE := 12
const TINY_TEXT_FONT_SIZE := 11
const EMOJI_SIZE := 15
const TEXT_COLOR := Color("573f49")
const TEXT_LEFT := 28.0
const TEXT_RIGHT := 28.0
const TEXT_RIGHT_WITH_EMOJI := 58.0
const TEXT_TOP := 15.0
const MAX_TEXT_LINES := 4
const CJK_UNIT_WIDTH_FACTOR := 1.08
const ASCII_UNIT_WIDTH_FACTOR := 0.58

var _text := ""
var _emoji := ""
var _cjk_font: Font
var _emoji_font: Font
var _show_tween: Tween
var _prepared_lines := PackedStringArray()
var _prepared_font_size := FONT_SIZE
var _prepared_text_width := 0.0


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
	_layout_text()
	queue_redraw()


func set_message(text: String, emoji: String) -> void:
	_text = text.replace("\n", " ").strip_edges()
	_emoji = emoji
	_layout_text()
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
	_prepared_lines.clear()
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
	draw_texture_rect(BUBBLE_TAIL_TEXTURE, Rect2(TAIL_CENTER_X - TAIL_SIZE.x * 0.5, TAIL_TOP, TAIL_SIZE.x, TAIL_SIZE.y), false)

	var font := _get_text_font()
	if font and _prepared_lines.size() > 0:
		var line_height := float(_prepared_font_size) + 4.0
		var block_height := line_height * float(_prepared_lines.size())
		var first_baseline := maxf(TEXT_TOP + float(_prepared_font_size), (BODY_RECT.size.y - block_height) * 0.5 + float(_prepared_font_size))
		for i in range(_prepared_lines.size()):
			draw_string(font, Vector2(TEXT_LEFT, first_baseline + line_height * float(i)), _prepared_lines[i], HORIZONTAL_ALIGNMENT_LEFT, _prepared_text_width, _prepared_font_size, TEXT_COLOR)
	if _emoji_font and not _emoji.is_empty():
		draw_string(_emoji_font, Vector2(281, 61), _emoji, HORIZONTAL_ALIGNMENT_CENTER, 24, EMOJI_SIZE, TEXT_COLOR)


func _layout_text() -> void:
	_prepared_lines.clear()
	_prepared_font_size = FONT_SIZE
	_prepared_text_width = BODY_RECT.size.x - TEXT_LEFT - (TEXT_RIGHT_WITH_EMOJI if not _emoji.is_empty() else TEXT_RIGHT)
	if _text.is_empty():
		return

	var font := _get_text_font()
	for candidate_size in [FONT_SIZE, 13, LONG_TEXT_FONT_SIZE, TINY_TEXT_FONT_SIZE]:
		var lines := _wrap_text(_text, font, candidate_size, _prepared_text_width)
		if lines.size() <= MAX_TEXT_LINES:
			_prepared_font_size = candidate_size
			_prepared_lines = lines
			return

	_prepared_font_size = TINY_TEXT_FONT_SIZE
	_prepared_lines = _wrap_text(_text, font, _prepared_font_size, _prepared_text_width)
	_trim_lines_to_fit(font)


func _get_text_font() -> Font:
	if _cjk_font:
		return _cjk_font
	return ThemeDB.fallback_font


func _wrap_text(text: String, font: Font, font_size: int, max_width: float) -> PackedStringArray:
	var lines := PackedStringArray()
	var current := ""
	var current_units := 0.0
	var max_units := max_width / float(font_size)
	for i in range(text.length()):
		var ch := text.substr(i, 1)
		var candidate := current + ch
		var too_wide := font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width * 0.94
		var char_units := _visual_units(ch)
		var too_many_chars := current_units + char_units > max_units * 0.82
		if not current.is_empty() and (too_wide or too_many_chars):
			lines.append(current.strip_edges())
			current = ch.strip_edges(true, false)
			current_units = _visual_units(current)
		else:
			current = candidate
			current_units += char_units
	if not current.is_empty():
		lines.append(current.strip_edges())
	return lines


func _visual_units(character: String) -> float:
	if character.is_empty() or character == " ":
		return 0.36
	return CJK_UNIT_WIDTH_FACTOR if _is_cjkish(character) or _is_cjk_punctuation(character) else ASCII_UNIT_WIDTH_FACTOR


func _is_cjkish(character: String) -> bool:
	if character.is_empty():
		return false
	var code := character.unicode_at(0)
	return (code >= 0x2e80 and code <= 0x9fff) or (code >= 0xff00 and code <= 0xffef)


func _is_cjk_punctuation(character: String) -> bool:
	if character.is_empty():
		return false
	var code := character.unicode_at(0)
	return (code >= 0x2000 and code <= 0x206f) or (code >= 0x3000 and code <= 0x303f)


func _trim_lines_to_fit(font: Font) -> void:
	if _prepared_lines.size() <= MAX_TEXT_LINES:
		return
	var kept := PackedStringArray()
	for i in range(MAX_TEXT_LINES):
		kept.append(_prepared_lines[i])
	var overflow := ""
	for i in range(MAX_TEXT_LINES, _prepared_lines.size()):
		overflow += _prepared_lines[i]
	kept[MAX_TEXT_LINES - 1] = _ellipsize_to_width((kept[MAX_TEXT_LINES - 1] + overflow).strip_edges(), font, _prepared_font_size, _prepared_text_width)
	_prepared_lines = kept


func _ellipsize_to_width(text: String, font: Font, font_size: int, max_width: float) -> String:
	const SUFFIX := "..."
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
		return text
	var result := ""
	for i in range(text.length()):
		var candidate := result + text.substr(i, 1) + SUFFIX
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
			return result.strip_edges() + SUFFIX
		result += text.substr(i, 1)
	return result
