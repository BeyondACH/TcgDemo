extends VBoxContainer
class_name BoardView

const DropZone = preload("res://ui/drop_zone.gd")
const CardView = preload("res://ui/card_view.gd")

signal front_card_pressed(player_id: String, card_uid: String)
signal energy_card_pressed(player_id: String, card_uid: String)
signal zone_drop_requested(player_id: String, zone_name: String, card_uid: String)

var _player_id := ""
var _name_label: Label
var _stats_label: Label
var _front_drop_zone: DropZone
var _energy_drop_zone: DropZone

func _ready() -> void:
	# 面板内容完全由代码动态构建，便于原型期快速调整布局。
	_name_label = Label.new()
	_stats_label = Label.new()
	add_child(_name_label)
	add_child(_stats_label)
	var front_title := Label.new()
	front_title.text = "Front Line"
	add_child(front_title)
	_front_drop_zone = DropZone.new()
	_front_drop_zone.card_dropped.connect(_on_zone_dropped)
	add_child(_front_drop_zone)
	var energy_title := Label.new()
	energy_title.text = "Energy Line"
	add_child(energy_title)
	_energy_drop_zone = DropZone.new()
	_energy_drop_zone.card_dropped.connect(_on_zone_dropped)
	add_child(_energy_drop_zone)

func set_board(player_id: String, display_name: String, data: Dictionary) -> void:
	_player_id = player_id
	_name_label.text = display_name
	_stats_label.text = "Life:%d  Deck:%d  Hand:%d  AP:%d/%d  Outside:%d" % [
		int(data.get("life_count", 0)),
		int(data.get("deck_count", 0)),
		int(data.get("hand_count", 0)),
		int(data.get("ap_active", 0)),
		int(data.get("ap_total", 0)),
		int(data.get("outside_count", 0)),
	]
	_front_drop_zone.setup(_player_id, "front_line")
	_energy_drop_zone.setup(_player_id, "energy_line")
	_rebuild_row(_front_drop_zone.get_row_container(), data.get("front_line", []), "front_line")
	_rebuild_row(_energy_drop_zone.get_row_container(), data.get("energy_line", []), "energy_line")

func _rebuild_row(row: HBoxContainer, cards: Array, zone_name: String) -> void:
	for child in row.get_children():
		child.queue_free()
	for card_data in cards:
		var card_view := CardView.new()
		card_view.setup(card_data, _player_id, zone_name)
		card_view.card_pressed.connect(_on_card_pressed)
		row.add_child(card_view)
	for i in range(max(0, 4 - cards.size())):
		# 用占位文本维持固定槽位感，后续可以替换成更明确的空位组件。
		var placeholder := Label.new()
		placeholder.text = "[Drop Here]"
		placeholder.custom_minimum_size = Vector2(120, 72)
		row.add_child(placeholder)

func _on_card_pressed(owner_player_id: String, card_uid: String, zone_name: String) -> void:
	if zone_name == "front_line":
		emit_signal("front_card_pressed", owner_player_id, card_uid)
	elif zone_name == "energy_line":
		emit_signal("energy_card_pressed", owner_player_id, card_uid)

func _on_zone_dropped(player_id: String, zone_name: String, card_uid: String) -> void:
	emit_signal("zone_drop_requested", player_id, zone_name, card_uid)
