extends VBoxContainer
class_name ZoneStackSummaryView

signal summary_pressed

const DEFAULT_STACK_SIZE := Vector2(58, 82)
const COMPACT_STACK_SIZE := Vector2(48, 68)
const DEFAULT_Y_STEP := 8.0
const COMPACT_Y_STEP := 6.0
const MAX_VISIBLE_CARDS := 4
const Y_STEP_RATIO := 0.1  # y_step as fraction of card height

var _stack_size := DEFAULT_STACK_SIZE
var _y_step := DEFAULT_Y_STEP
var _custom_size_set := false
var _title_label: Label
var _count_label: Label
var _stack_root: Control
var _stack_layer: Control
var _title_text := ""
var _count := 0

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 13)
	add_child(_title_label)

	_stack_root = Control.new()
	_stack_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stack_root)

	_stack_layer = Control.new()
	_stack_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stack_root.add_child(_stack_layer)

	_count_label = Label.new()
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.add_theme_font_size_override("font_size", 12)
	add_child(_count_label)

	_refresh()

func set_compact_mode(compact: bool) -> void:
	if _custom_size_set:
		return
	_stack_size = COMPACT_STACK_SIZE if compact else DEFAULT_STACK_SIZE
	_y_step = COMPACT_Y_STEP if compact else DEFAULT_Y_STEP
	_refresh()


## Set stack card size dynamically based on zone rect.
## card_size: Vector2 with width and height (5:7 aspect ratio expected).
func set_stack_size(card_size: Vector2) -> void:
	_stack_size = card_size
	_y_step = maxf(4.0, card_size.y * Y_STEP_RATIO)
	_custom_size_set = true
	_refresh()

func set_summary(title_text: String, count: int) -> void:
	_title_text = title_text
	_count = maxi(0, count)
	_refresh()

func _refresh() -> void:
	if _title_label == null or _count_label == null or _stack_root == null or _stack_layer == null:
		return

	_title_label.text = _title_text
	_count_label.text = "x%d" % _count

	for child in _stack_layer.get_children():
		child.queue_free()

	var visible_cards := clampi(_count, 1, MAX_VISIBLE_CARDS)
	var stack_height := _stack_size.y
	if visible_cards > 1:
		stack_height += _y_step * float(visible_cards - 1)
	_stack_root.custom_minimum_size = Vector2(_stack_size.x + 8.0, stack_height + 4.0)
	custom_minimum_size = Vector2(_stack_size.x + 12.0, stack_height + 40.0)

	for i in range(visible_cards):
		var card_back := PanelContainer.new()
		card_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_back.custom_minimum_size = _stack_size
		card_back.size = _stack_size
		card_back.position = Vector2(4.0, _y_step * float(i))
		card_back.add_theme_stylebox_override("panel", _create_card_back_style(i))

		var label := Label.new()
		label.text = _title_text.to_upper()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card_back.add_child(label)
		_stack_layer.add_child(card_back)

func _create_card_back_style(index: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18 + float(index) * 0.015, 0.16, 0.22, 0.96)
	style.border_color = Color(0.88, 0.9, 0.95, 0.82)
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

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		summary_pressed.emit()
		accept_event()
