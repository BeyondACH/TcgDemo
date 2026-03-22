extends VBoxContainer
class_name HandView

const CardView = preload("res://ui/card_view.gd")
const DEFAULT_HAND_CARD_SIZE := Vector2(108, 56)
const COMPACT_HAND_CARD_SIZE := Vector2(84, 40)

signal hand_card_selected(card_uid: String)

var _title: Label
var _scroll: ScrollContainer
var _row: HBoxContainer
var _current_card_size := DEFAULT_HAND_CARD_SIZE
var _compact_mode := false

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_title = Label.new()
	_title.text = "Active Hand"
	_title.add_theme_font_size_override("font_size", 12)
	add_child(_title)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0, _current_card_size.y + 2)
	add_child(_scroll)

	_row = HBoxContainer.new()
	_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_row.add_theme_constant_override("separation", 6)
	_scroll.add_child(_row)

func set_compact_mode(compact: bool) -> void:
	_compact_mode = compact
	var target_size := COMPACT_HAND_CARD_SIZE if compact else DEFAULT_HAND_CARD_SIZE
	if _current_card_size.is_equal_approx(target_size):
		_title.visible = not compact
		if _scroll != null:
			_scroll.custom_minimum_size = Vector2(0, _current_card_size.y + (2 if compact else 4))
		if _row != null:
			_row.add_theme_constant_override("separation", 4 if compact else 6)
		return
	_current_card_size = target_size
	if _title != null:
		_title.visible = not compact
	if _scroll != null:
		_scroll.custom_minimum_size = Vector2(0, _current_card_size.y + (2 if compact else 4))
	if _row != null:
		_row.add_theme_constant_override("separation", 4 if compact else 6)

func set_hand(player_id: String, hand_cards: Array) -> void:
	if _row == null:
		return
	for child in _row.get_children():
		child.queue_free()
	for card_data in hand_cards:
		var card_view := CardView.new()
		card_view.setup(card_data, player_id, "hand", _current_card_size, CardView.DISPLAY_MODE_HAND)
		card_view.card_pressed.connect(_on_card_pressed)
		_row.add_child(card_view)

func _on_card_pressed(_owner_player_id: String, card_uid: String, _zone_name: String) -> void:
	emit_signal("hand_card_selected", card_uid)
