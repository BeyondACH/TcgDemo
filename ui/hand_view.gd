extends VBoxContainer
class_name HandView

const CardView = preload("res://ui/card_view.gd")

signal hand_card_selected(card_uid: String)

var _title: Label
var _row: HBoxContainer

func _ready() -> void:
	_title = Label.new()
	_title.text = "Active Hand"
	add_child(_title)
	_row = HBoxContainer.new()
	_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_row)

func set_hand(player_id: String, hand_cards: Array) -> void:
	if _row == null:
		return
	# 手牌区每次按快照整体重建，逻辑简单，但后续可优化为增量刷新。
	for child in _row.get_children():
		child.queue_free()
	for card_data in hand_cards:
		var card_view := CardView.new()
		card_view.setup(card_data, player_id, "hand")
		card_view.card_pressed.connect(_on_card_pressed)
		_row.add_child(card_view)

func _on_card_pressed(_owner_player_id: String, card_uid: String, _zone_name: String) -> void:
	emit_signal("hand_card_selected", card_uid)
