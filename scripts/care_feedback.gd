extends Node2D
class_name PetCareFeedback

signal bounds_changed

const EFFECT_DIR := "res://assets/care/runtime/effects"
const EFFECT_ORIGIN := Vector2(244, 148)
const EFFECT_BOUNDS := Rect2(190, 78, 112, 118)
const EFFECT_PATHS := {
	"fullness": EFFECT_DIR + "/fullness.png",
	"hydration": EFFECT_DIR + "/hydration.png",
	"mood": EFFECT_DIR + "/mood.png",
	"affection": EFFECT_DIR + "/affection.png",
	"energy": EFFECT_DIR + "/energy.png",
	"sparkle": EFFECT_DIR + "/sparkle.png"
}

var _font: Font
var _content: Node2D
var _sprite: Sprite2D
var _label: Label
var _tween: Tween


func configure_font(font: Font) -> void:
	_font = font
	if _label and _font:
		_label.add_theme_font_override("font", _font)


func _ready() -> void:
	visible = false
	z_index = 900
	_content = Node2D.new()
	add_child(_content)

	_sprite = Sprite2D.new()
	_sprite.centered = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_content.add_child(_sprite)

	_label = Label.new()
	_label.position = Vector2(-66, 31)
	_label.size = Vector2(132, 24)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color("684551"))
	_label.add_theme_color_override("font_outline_color", Color(1.0, 0.97, 0.95, 0.96))
	_label.add_theme_constant_override("outline_size", 5)
	if _font:
		_label.add_theme_font_override("font", _font)
	_content.add_child(_label)


func show_feedback(effect: String, text: String) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	var path: String = EFFECT_PATHS.get(effect, EFFECT_PATHS["sparkle"])
	var texture := load(path) as Texture2D
	if texture == null:
		return
	_sprite.texture = texture
	var texture_size := texture.get_size()
	var scale_factor := minf(54.0 / maxf(texture_size.x, 1.0), 54.0 / maxf(texture_size.y, 1.0))
	_sprite.scale = Vector2.ONE * scale_factor
	_label.text = text
	_content.position = EFFECT_ORIGIN
	_content.modulate = Color.WHITE
	visible = true
	bounds_changed.emit()

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_content, "position", EFFECT_ORIGIN + Vector2(0, -38), 1.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_content, "modulate:a", 0.0, 1.25).set_delay(0.45)
	_tween.set_parallel(false)
	_tween.tween_callback(_finish_feedback)


func get_local_bounds() -> Rect2:
	return EFFECT_BOUNDS


func _finish_feedback() -> void:
	visible = false
	bounds_changed.emit()
