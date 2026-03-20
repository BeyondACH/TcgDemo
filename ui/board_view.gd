extends VBoxContainer
class_name BoardView

const DropZone = preload("res://ui/drop_zone.gd")
const CardView = preload("res://ui/card_view.gd")

const MAX_VISIBLE_SLOTS := 4
const SLOT_PLATE_TEXTURE_PATH := "res://assets/battle/slots/slot_plate.png"
const DEFAULT_CARD_SIZE := Vector2(150, 96)
const COMPACT_CARD_SIZE := Vector2(124, 82)

signal front_card_pressed(player_id: String, card_uid: String)
signal energy_card_pressed(player_id: String, card_uid: String)
signal zone_drop_requested(player_id: String, zone_name: String, card_uid: String)

var _player_id := ""
var _name_label: Label
var _stats_label: Label
var _front_drop_zone: DropZone
var _energy_drop_zone: DropZone
var _front_slot_backplates: HBoxContainer
var _energy_slot_backplates: HBoxContainer
var _slot_plate_texture: Texture2D
var _current_card_size := DEFAULT_CARD_SIZE
var _last_data: Dictionary = {}
var _display_name := ""

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_slot_plate_texture = _load_optional_texture(SLOT_PLATE_TEXTURE_PATH)
	_name_label = Label.new()
	_stats_label = Label.new()
	add_child(_name_label)
	add_child(_stats_label)

	var front_section := _create_zone_section("Front Line")
	add_child(front_section.get("root"))
	_front_drop_zone = front_section.get("drop_zone")
	_front_slot_backplates = front_section.get("slot_backplates")

	var energy_section := _create_zone_section("Energy Line")
	add_child(energy_section.get("root"))
	_energy_drop_zone = energy_section.get("drop_zone")
	_energy_slot_backplates = energy_section.get("slot_backplates")

func set_board(player_id: String, display_name: String, data: Dictionary) -> void:
	_player_id = player_id
	_display_name = display_name
	_last_data = data.duplicate(true)
	_apply_board_data()

func set_compact_mode(compact: bool) -> void:
	var target_size := COMPACT_CARD_SIZE if compact else DEFAULT_CARD_SIZE
	if _current_card_size.is_equal_approx(target_size):
		return
	_current_card_size = target_size
	if not _last_data.is_empty():
		_apply_board_data()

func _apply_board_data() -> void:
	_name_label.text = _display_name
	_stats_label.text = "Life:%d  Deck:%d  Hand:%d  AP:%d/%d  Outside:%d" % [
		int(_last_data.get("life_count", 0)),
		int(_last_data.get("deck_count", 0)),
		int(_last_data.get("hand_count", 0)),
		int(_last_data.get("ap_active", 0)),
		int(_last_data.get("ap_total", 0)),
		int(_last_data.get("outside_count", 0)),
	]
	_front_drop_zone.setup(_player_id, "front_line", _current_card_size)
	_energy_drop_zone.setup(_player_id, "energy_line", _current_card_size)
	_rebuild_slot_backplates(_front_slot_backplates, _last_data.get("front_line", []), "front_line")
	_rebuild_slot_backplates(_energy_slot_backplates, _last_data.get("energy_line", []), "energy_line")
	_rebuild_row(_front_drop_zone.get_row_container(), _last_data.get("front_line", []), "front_line")
	_rebuild_row(_energy_drop_zone.get_row_container(), _last_data.get("energy_line", []), "energy_line")

func _create_zone_section(title_text: String) -> Dictionary:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = title_text
	section.add_child(title)

	var overlay_root := Control.new()
	overlay_root.custom_minimum_size = Vector2(0, _current_card_size.y)
	overlay_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(overlay_root)

	var slot_backplates := HBoxContainer.new()
	slot_backplates.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_backplates.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_backplates.alignment = BoxContainer.ALIGNMENT_CENTER
	slot_backplates.add_theme_constant_override("separation", 8)
	slot_backplates.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_root.add_child(slot_backplates)

	var drop_zone := DropZone.new()
	drop_zone.set_anchors_preset(Control.PRESET_FULL_RECT)
	drop_zone.card_dropped.connect(_on_zone_dropped)
	overlay_root.add_child(drop_zone)

	return {
		"root": section,
		"drop_zone": drop_zone,
		"slot_backplates": slot_backplates,
	}

func _rebuild_slot_backplates(row: HBoxContainer, cards: Array, zone_name: String) -> void:
	if row.get_parent() is Control:
		row.get_parent().custom_minimum_size = Vector2(0, _current_card_size.y)
	for child in row.get_children():
		child.queue_free()
	for i in range(MAX_VISIBLE_SLOTS):
		row.add_child(_create_slot_backplate(zone_name, i < cards.size()))

func _create_slot_backplate(zone_name: String, occupied: bool) -> Control:
	var slot_root := Control.new()
	slot_root.custom_minimum_size = _current_card_size
	slot_root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if _slot_plate_texture != null:
		var texture_rect := TextureRect.new()
		texture_rect.texture = _slot_plate_texture
		texture_rect.self_modulate = Color(1, 1, 1, 0.95 if occupied else 0.45)
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot_root.add_child(texture_rect)
	else:
		var slot_panel := PanelContainer.new()
		slot_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_panel.add_theme_stylebox_override("panel", _create_slot_stylebox(zone_name, occupied))
		slot_root.add_child(slot_panel)

	return slot_root

func _create_slot_stylebox(zone_name: String, occupied: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.2, 0.24, 0.78)
	if zone_name == "energy_line":
		style.bg_color = Color(0.16, 0.22, 0.26, 0.78)
	if occupied:
		style.bg_color = style.bg_color.lightened(0.08)
	style.border_color = Color(0.82, 0.86, 0.92, 0.55)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	return style

func _rebuild_row(row: HBoxContainer, cards: Array, zone_name: String) -> void:
	for child in row.get_children():
		child.queue_free()
	for card_data in cards:
		var card_view := CardView.new()
		card_view.setup(card_data, _player_id, zone_name, _current_card_size)
		card_view.card_pressed.connect(_on_card_pressed)
		row.add_child(card_view)
	for i in range(max(0, MAX_VISIBLE_SLOTS - cards.size())):
		var placeholder := Control.new()
		placeholder.custom_minimum_size = _current_card_size
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(placeholder)

func _load_optional_texture(resource_path: String) -> Texture2D:
	if ResourceLoader.exists(resource_path):
		return load(resource_path)
	return null

func _on_card_pressed(owner_player_id: String, card_uid: String, zone_name: String) -> void:
	if zone_name == "front_line":
		emit_signal("front_card_pressed", owner_player_id, card_uid)
	elif zone_name == "energy_line":
		emit_signal("energy_card_pressed", owner_player_id, card_uid)

func _on_zone_dropped(player_id: String, zone_name: String, card_uid: String) -> void:
	emit_signal("zone_drop_requested", player_id, zone_name, card_uid)
