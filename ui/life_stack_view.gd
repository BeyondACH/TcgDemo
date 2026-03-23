extends Control
class_name LifeStackView

const DEFAULT_CARD_SIZE := Vector2(50, 70)
const COMPACT_CARD_SIZE := Vector2(42, 58)
const DEFAULT_Y_STEP := 16.0
const COMPACT_Y_STEP := 13.0
const MAX_VISIBLE_LIFE := 7

var _card_size := DEFAULT_CARD_SIZE
var _y_step := DEFAULT_Y_STEP
var _life_cards: Array = []
var _card_layer: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_layer = Control.new()
	_card_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_card_layer)
	_refresh()

func set_compact_mode(compact: bool) -> void:
	_card_size = COMPACT_CARD_SIZE if compact else DEFAULT_CARD_SIZE
	_y_step = COMPACT_Y_STEP if compact else DEFAULT_Y_STEP
	_refresh()

func set_life_cards(cards: Array) -> void:
	_life_cards = cards.duplicate(true)
	_refresh()

func _refresh() -> void:
	if _card_layer == null:
		return
	for child in _card_layer.get_children():
		child.queue_free()
	var visible_count := mini(MAX_VISIBLE_LIFE, _life_cards.size())
	var stack_height := _card_size.y
	if visible_count > 1:
		stack_height += _y_step * float(visible_count - 1)
	custom_minimum_size = Vector2(_card_size.x, stack_height)
	for i in range(visible_count):
		var back := PanelContainer.new()
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back.custom_minimum_size = _card_size
		back.size = _card_size
		back.position = Vector2(0, _y_step * float(i))
		back.add_theme_stylebox_override("panel", _create_card_back_style(i))

		var label := Label.new()
		label.text = "LIFE"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		back.add_child(label)
		_card_layer.add_child(back)

func _create_card_back_style(index: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16 + float(index) * 0.01, 0.20, 0.26, 0.96)
	style.border_color = Color(0.85, 0.89, 0.94, 0.85)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	style.shadow_color = Color(0, 0, 0, 0.28)
	style.shadow_size = 3
	style.expand_margin_right = 1
	style.expand_margin_bottom = 1
	return style
