extends PanelContainer
class_name DropZone

signal card_dropped(player_id: String, zone_name: String, card_uid: String)

const DEFAULT_ZONE_HEIGHT := 152.0

var player_id := ""
var zone_name := ""
var _row: HBoxContainer

func _ready() -> void:
	custom_minimum_size = Vector2(0, DEFAULT_ZONE_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_row = HBoxContainer.new()
	_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 8)
	add_child(_row)

func setup(p_player_id: String, p_zone_name: String, card_size: Vector2 = Vector2(150, DEFAULT_ZONE_HEIGHT)) -> void:
	player_id = p_player_id
	zone_name = p_zone_name
	custom_minimum_size = Vector2(0, card_size.y)
	if _row != null:
		_row.add_theme_constant_override("separation", 4 if card_size.x <= 84.0 else (6 if card_size.x <= 96.0 else 8))

func get_row_container() -> HBoxContainer:
	return _row

func _can_drop_data(_at_position: Vector2, data) -> bool:
	if not (data is Dictionary):
		return false
	if str(data.get("kind", "")) != "hand_card":
		return false
	return true

func _drop_data(_at_position: Vector2, data) -> void:
	if not _can_drop_data(_at_position, data):
		return
	card_dropped.emit(player_id, zone_name, str(data.get("card_uid", "")))
