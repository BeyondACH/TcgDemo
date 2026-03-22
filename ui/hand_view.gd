extends VBoxContainer
class_name HandView

const CardView = preload("res://ui/card_view.gd")
const DEFAULT_HAND_CARD_SIZE := Vector2(220, 168)
const COMPACT_HAND_CARD_SIZE := Vector2(180, 140)
const HAND_IMAGE_FILL_RATIO := 0.8
const HAND_IMAGE_ASPECT_RATIO := 5.0 / 7.0
const HAND_TEXT_WIDTH_DEFAULT := 92.0
const HAND_TEXT_WIDTH_COMPACT := 76.0
const HAND_PADDING_TOTAL := 8.0
const HAND_CONTENT_GAP := 6.0

signal hand_card_selected(card_uid: String)

var _title: Label
var _scroll: ScrollContainer
var _row: HBoxContainer
var _current_card_size := DEFAULT_HAND_CARD_SIZE
var _compact_mode := false
var _current_player_id := ""
var _hand_cards: Array = []

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
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_scroll)

	_row = HBoxContainer.new()
	_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_row.add_theme_constant_override("separation", 6)
	_scroll.add_child(_row)

	resized.connect(_on_resized)
	call_deferred("_refresh_layout")

func set_compact_mode(compact: bool) -> void:
	_compact_mode = compact
	if _title != null:
		_title.visible = not compact
	_refresh_layout()

func set_hand(player_id: String, hand_cards: Array) -> void:
	_current_player_id = player_id
	_hand_cards = hand_cards.duplicate(true)
	_rebuild_hand()

func _on_resized() -> void:
	_refresh_layout()

func _refresh_layout() -> void:
	var target_size := _measure_card_size()
	_current_card_size = target_size
	if _scroll != null:
		_scroll.custom_minimum_size = Vector2(0, target_size.y + (14 if _compact_mode else 20))
	if _row != null:
		_row.add_theme_constant_override("separation", 4 if _compact_mode else 6)
	if _row != null and is_inside_tree():
		_rebuild_hand()

func _measure_card_size() -> Vector2:
	var available_height := _available_hand_height()
	var image_height: float = max(96.0 if _compact_mode else 120.0, floor(available_height * HAND_IMAGE_FILL_RATIO))
	var image_width: float = round(image_height * HAND_IMAGE_ASPECT_RATIO)
	var text_width := HAND_TEXT_WIDTH_COMPACT if _compact_mode else HAND_TEXT_WIDTH_DEFAULT
	var card_width: float = image_width + text_width + HAND_PADDING_TOTAL + HAND_CONTENT_GAP
	var card_height: float = image_height + HAND_PADDING_TOTAL
	return Vector2(card_width, card_height)

func _available_hand_height() -> float:
	if _scroll != null and _scroll.size.y > 0.0:
		return _scroll.size.y
	var title_height := 0.0
	if _title != null and _title.visible:
		title_height = _title.get_combined_minimum_size().y + 4.0
	var fallback_height := size.y - title_height
	if fallback_height > 0.0:
		return fallback_height
	return COMPACT_HAND_CARD_SIZE.y if _compact_mode else DEFAULT_HAND_CARD_SIZE.y

func _rebuild_hand() -> void:
	if _row == null:
		return
	for child in _row.get_children():
		child.queue_free()
	for card_data in _hand_cards:
		var card_view := CardView.new()
		card_view.setup(card_data, _current_player_id, "hand", _current_card_size, CardView.DISPLAY_MODE_HAND)
		card_view.card_pressed.connect(_on_card_pressed)
		_row.add_child(card_view)

func _on_card_pressed(_owner_player_id: String, card_uid: String, _zone_name: String) -> void:
	emit_signal("hand_card_selected", card_uid)
