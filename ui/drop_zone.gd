extends PanelContainer
class_name DropZone

signal card_dropped(player_id: String, zone_name: String, card_uid: String)

var player_id := ""
var zone_name := ""
var _row: HBoxContainer

func _ready() -> void:
	custom_minimum_size = Vector2(0, 84)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_row = HBoxContainer.new()
	_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_row)

func setup(p_player_id: String, p_zone_name: String) -> void:
	player_id = p_player_id
	zone_name = p_zone_name

func get_row_container() -> HBoxContainer:
	return _row

func _can_drop_data(_at_position: Vector2, data) -> bool:
	# 这里只做最基础的数据结构校验，具体规则限制仍由 GameManager 再判一次。
	if not (data is Dictionary):
		return false
	if str(data.get("kind", "")) != "hand_card":
		return false
	return true

func _drop_data(_at_position: Vector2, data) -> void:
	if not _can_drop_data(_at_position, data):
		return
	emit_signal("card_dropped", player_id, zone_name, str(data.get("card_uid", "")))
