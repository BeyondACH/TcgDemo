extends Control
class_name BoardView

const DropZone = preload("res://ui/drop_zone.gd")
const CardView = preload("res://ui/card_view.gd")
const LifeStackView = preload("res://ui/life_stack_view.gd")
const ZoneStackSummaryView = preload("res://ui/zone_stack_summary_view.gd")
const ZoneLayoutConfig = preload("res://data/zone_layout_config.gd")

const MAX_VISIBLE_SLOTS := 4
const SLOT_PLATE_TEXTURE_PATH := "res://assets/battle/slots/slot_plate.png"
const DEFAULT_CARD_SIZE := Vector2(108, 152)
const COMPACT_CARD_SIZE := Vector2(92, 128)
const VERY_SMALL_CARD_SIZE := Vector2(52, 72)

signal front_card_pressed(player_id: String, card_uid: String)
signal energy_card_pressed(player_id: String, card_uid: String)
signal zone_drop_requested(player_id: String, zone_name: String, card_uid: String)

var _player_id := ""
var _current_card_size := DEFAULT_CARD_SIZE
var _last_data: Dictionary = {}
var _display_name := ""
var _very_small_mode := false
var _slot_plate_texture: Texture2D

# Zone containers (absolute positioned)
var _life_stack: LifeStackView
var _removed_stack: ZoneStackSummaryView
var _deck_stack: ZoneStackSummaryView
var _outside_stack: ZoneStackSummaryView
var _front_drop_zone: DropZone
var _energy_drop_zone: DropZone
var _front_slot_backplates: HBoxContainer
var _energy_slot_backplates: HBoxContainer

# Zone wrapper controls for positioning
var _life_wrapper: Control
var _removed_wrapper: Control
var _deck_wrapper: Control
var _outside_wrapper: Control
var _front_wrapper: Control
var _energy_wrapper: Control
var _stats_label: Label

# Layout state
var _bg_offset: float = 0.0
var _bg_scale: float = 1.0
var _bg_top_offset: float = 0.0

func _ready() -> void:
	_slot_plate_texture = _load_optional_texture(SLOT_PLATE_TEXTURE_PATH)

	# Create zone wrappers for absolute positioning
	_life_wrapper = Control.new()
	_life_wrapper.name = "LifeWrapper"
	add_child(_life_wrapper)

	_removed_wrapper = Control.new()
	_removed_wrapper.name = "RemovedWrapper"
	add_child(_removed_wrapper)

	_deck_wrapper = Control.new()
	_deck_wrapper.name = "DeckWrapper"
	add_child(_deck_wrapper)

	_outside_wrapper = Control.new()
	_outside_wrapper.name = "OutsideWrapper"
	add_child(_outside_wrapper)

	_front_wrapper = Control.new()
	_front_wrapper.name = "FrontWrapper"
	add_child(_front_wrapper)

	_energy_wrapper = Control.new()
	_energy_wrapper.name = "EnergyWrapper"
	add_child(_energy_wrapper)

	# Stats label (floating at top)
	_stats_label = Label.new()
	_stats_label.name = "StatsLabel"
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_label.add_theme_font_size_override("font_size", 12)
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_stats_label)

	# Create Life stack
	_life_stack = LifeStackView.new()
	_life_stack.name = "LifeStack"
	_life_stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_life_stack.set_compact_mode(false)
	_life_wrapper.add_child(_life_stack)

	# Create Removed stack
	_removed_stack = ZoneStackSummaryView.new()
	_removed_stack.name = "RemovedStack"
	_removed_stack.set_compact_mode(false)
	_removed_wrapper.add_child(_removed_stack)

	# Create Deck stack
	_deck_stack = ZoneStackSummaryView.new()
	_deck_stack.name = "DeckStack"
	_deck_stack.set_compact_mode(false)
	_deck_wrapper.add_child(_deck_stack)

	# Create Outside stack
	_outside_stack = ZoneStackSummaryView.new()
	_outside_stack.name = "OutsideStack"
	_outside_stack.set_compact_mode(false)
	_outside_wrapper.add_child(_outside_stack)

	# Create Front Line zone
	var front_section := _create_zone_section("front_line")
	_front_wrapper.add_child(front_section.root)
	_front_drop_zone = front_section.drop_zone
	_front_slot_backplates = front_section.slot_backplates

	# Create Energy Line zone
	var energy_section := _create_zone_section("energy_line")
	_energy_wrapper.add_child(energy_section.root)
	_energy_drop_zone = energy_section.drop_zone
	_energy_slot_backplates = energy_section.slot_backplates


func update_layout(bg_offset: float, bg_scale: float, bg_top_offset: float = 0.0) -> void:
	_bg_offset = bg_offset
	_bg_scale = bg_scale
	_bg_top_offset = bg_top_offset
	_reposition_zones()


func _reposition_zones() -> void:
	if _player_id == "":
		return

	# Position each zone based on config
	_position_zone_wrapper(_life_wrapper, "life_area")
	_position_zone_wrapper(_removed_wrapper, "remove_area")
	_position_zone_wrapper(_front_wrapper, "front_line")
	_position_zone_wrapper(_energy_wrapper, "energy_line")
	_position_zone_wrapper(_deck_wrapper, "deck")
	_position_zone_wrapper(_outside_wrapper, "outside_area")

	# Position stats label at top center of player's area
	var top_zone := "life_area" if _player_id == "P1" else "remove_area"
	var top_rect := ZoneLayoutConfig.get_zone_rect(_player_id, top_zone, _bg_offset, _bg_scale, _bg_top_offset)
	_stats_label.position = Vector2(top_rect.position.x, top_rect.position.y - 20)
	_stats_label.size = Vector2(top_rect.size.x, 18)

	# Calculate card sizes based on zone dimensions
	var front_rect := ZoneLayoutConfig.get_zone_rect(_player_id, "front_line", _bg_offset, _bg_scale, _bg_top_offset)
	_current_card_size = ZoneLayoutConfig.calculate_card_size_for_zone(front_rect, MAX_VISIBLE_SLOTS)

	# Calculate dynamic sizes for stack zones based on their zone rects
	var deck_rect := ZoneLayoutConfig.get_zone_rect(_player_id, "deck", _bg_offset, _bg_scale, _bg_top_offset)
	var outside_rect := ZoneLayoutConfig.get_zone_rect(_player_id, "outside_area", _bg_offset, _bg_scale, _bg_top_offset)
	var removed_rect := ZoneLayoutConfig.get_zone_rect(_player_id, "remove_area", _bg_offset, _bg_scale, _bg_top_offset)
	var life_rect := ZoneLayoutConfig.get_zone_rect(_player_id, "life_area", _bg_offset, _bg_scale, _bg_top_offset)

	_deck_stack.set_stack_size(_calc_stack_card_size(deck_rect))
	_outside_stack.set_stack_size(_calc_stack_card_size(outside_rect))
	_removed_stack.set_stack_size(_calc_stack_card_size(removed_rect))
	_life_stack.set_card_size(_calc_life_card_size(life_rect))
	_layout_stack_summaries()

	# Update zone contents with new card sizes
	_update_zone_contents()


func _position_zone_wrapper(wrapper: Control, zone_name: String) -> void:
	var zone_rect := ZoneLayoutConfig.get_zone_rect(_player_id, zone_name, _bg_offset, _bg_scale, _bg_top_offset)
	wrapper.position = zone_rect.position
	wrapper.size = zone_rect.size

	# Set anchors for children to fill
	for child in wrapper.get_children():
		if child is Control:
			if child == _removed_stack or child == _outside_stack or child == _deck_stack:
				continue
			child.set_anchors_preset(Control.PRESET_FULL_RECT)
			child.position = Vector2.ZERO
			child.size = zone_rect.size


func set_board(player_id: String, display_name: String, data: Dictionary) -> void:
	_player_id = player_id
	_display_name = display_name
	_last_data = data.duplicate(true)
	_reposition_zones()
	_apply_board_data()


func set_compact_mode(compact: bool, very_small := false) -> void:
	_very_small_mode = very_small
	var target_size := VERY_SMALL_CARD_SIZE if very_small else (COMPACT_CARD_SIZE if compact else DEFAULT_CARD_SIZE)
	if _current_card_size.is_equal_approx(target_size):
		return
	_current_card_size = target_size

	if _life_stack != null:
		_life_stack.set_compact_mode(compact or very_small)
	if _removed_stack != null:
		_removed_stack.set_compact_mode(compact or very_small)
	if _deck_stack != null:
		_deck_stack.set_compact_mode(compact or very_small)
	if _outside_stack != null:
		_outside_stack.set_compact_mode(compact or very_small)
	if _stats_label != null:
		_stats_label.add_theme_font_size_override("font_size", 10 if very_small else 12)

	if not _last_data.is_empty():
		_apply_board_data()


func _update_zone_contents() -> void:
	# Update drop zones with new card size
	if _front_drop_zone != null:
		_front_drop_zone.setup(_player_id, "front_line", _current_card_size)
	if _energy_drop_zone != null:
		_energy_drop_zone.setup(_player_id, "energy_line", _current_card_size)

	# Rebuild slot backplates and card rows
	_rebuild_slot_backplates(_front_slot_backplates, _last_data.get("front_line", []), "front_line")
	_rebuild_slot_backplates(_energy_slot_backplates, _last_data.get("energy_line", []), "energy_line")
	_rebuild_row(_front_drop_zone.get_row_container(), _last_data.get("front_line", []), "front_line")
	_rebuild_row(_energy_drop_zone.get_row_container(), _last_data.get("energy_line", []), "energy_line")


func _apply_board_data() -> void:
	_stats_label.text = "Life:%d  Hand:%d  AP:%d/%d  Energy:%s" % [
		int(_last_data.get("life_count", 0)),
		int(_last_data.get("hand_count", 0)),
		int(_last_data.get("ap_active", 0)),
		int(_last_data.get("ap_total", 0)),
		_format_energy_map(_last_data.get("available_energy", {})),
	]

	if _front_drop_zone != null:
		_front_drop_zone.setup(_player_id, "front_line", _current_card_size)
	if _energy_drop_zone != null:
		_energy_drop_zone.setup(_player_id, "energy_line", _current_card_size)

	_life_stack.set_life_cards(_last_data.get("life", []))
	_removed_stack.set_summary("Removed", int(_last_data.get("removed_count", 0)))
	_deck_stack.set_summary("Deck", int(_last_data.get("deck_count", 0)))
	_outside_stack.set_summary("Outside", int(_last_data.get("outside_count", 0)))
	_layout_stack_summaries()

	_rebuild_slot_backplates(_front_slot_backplates, _last_data.get("front_line", []), "front_line")
	_rebuild_slot_backplates(_energy_slot_backplates, _last_data.get("energy_line", []), "energy_line")
	_rebuild_row(_front_drop_zone.get_row_container(), _last_data.get("front_line", []), "front_line")
	_rebuild_row(_energy_drop_zone.get_row_container(), _last_data.get("energy_line", []), "energy_line")


func _create_zone_section(zone_name: String) -> Dictionary:
	var overlay_root := Control.new()
	overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var slot_backplates := HBoxContainer.new()
	slot_backplates.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_backplates.alignment = BoxContainer.ALIGNMENT_CENTER
	slot_backplates.add_theme_constant_override("separation", 4)
	slot_backplates.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_root.add_child(slot_backplates)

	var drop_zone := DropZone.new()
	drop_zone.set_anchors_preset(Control.PRESET_FULL_RECT)
	drop_zone.card_dropped.connect(_on_zone_dropped)
	overlay_root.add_child(drop_zone)

	return {
		"root": overlay_root,
		"drop_zone": drop_zone,
		"slot_backplates": slot_backplates,
	}


func _rebuild_slot_backplates(row: HBoxContainer, cards: Array, zone_name: String) -> void:
	if row == null:
		return
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
	if row == null:
		return
	for child in row.get_children():
		child.queue_free()
	for card_data in cards:
		var card_view := CardView.new()
		card_view.setup(card_data, _player_id, zone_name, _current_card_size, CardView.DISPLAY_MODE_BOARD)
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


## Calculate a single card size for stack zones (deck, outside, removed).
## Fits one card inside the zone rect while keeping 5:7 aspect ratio.
func _calc_stack_card_size(zone_rect: Rect2) -> Vector2:
	var aspect := 5.0 / 7.0
	# Reserve space for title label (~18px) and count label (~18px) and padding
	var available_height := zone_rect.size.y * 0.55
	var available_width := zone_rect.size.x * 0.85
	var card_height := minf(available_height, available_width / aspect)
	var card_width := card_height * aspect
	card_width = maxf(card_width, 36.0)
	card_height = maxf(card_height, 50.0)
	return Vector2(card_width, card_height)


func _layout_stack_summaries() -> void:
	if _deck_stack != null and _deck_wrapper != null:
		_position_stack_summary(_deck_stack, _deck_wrapper, "center", "center")
	if _outside_stack != null and _outside_wrapper != null:
		if _player_id == "P1":
			_position_stack_summary(_outside_stack, _outside_wrapper, "right", "bottom")
		else:
			_position_stack_summary(_outside_stack, _outside_wrapper, "left", "top")
	if _removed_stack != null and _removed_wrapper != null:
		if _player_id == "P1":
			_position_stack_summary(_removed_stack, _removed_wrapper, "left", "bottom")
		else:
			_position_stack_summary(_removed_stack, _removed_wrapper, "right", "top")


func _position_stack_summary(stack_view: Control, wrapper: Control, h_align: String, v_align: String) -> void:
	var min_size := stack_view.get_combined_minimum_size()
	stack_view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	stack_view.size = min_size

	var x := 0.0
	if h_align == "right":
		x = maxf(0.0, wrapper.size.x - min_size.x)
	elif h_align == "center":
		x = maxf(0.0, (wrapper.size.x - min_size.x) / 2.0)

	var y := 0.0
	if v_align == "bottom":
		y = maxf(0.0, wrapper.size.y - min_size.y)
	elif v_align == "center":
		y = maxf(0.0, (wrapper.size.y - min_size.y) / 2.0)

	stack_view.position = Vector2(x, y)


## Calculate a single card size for the life zone.
## Needs to fit up to 7 stacked cards vertically.
func _calc_life_card_size(zone_rect: Rect2) -> Vector2:
	var aspect := 5.0 / 7.0
	var y_step_ratio := 0.23
	# Total height = card_h + y_step * 6, where y_step = card_h * y_step_ratio
	# card_h * (1 + 6 * y_step_ratio) = zone_height * 0.95
	var card_height := (zone_rect.size.y * 0.95) / (1.0 + 6.0 * y_step_ratio)
	var card_width := card_height * aspect
	# Also constrain by zone width
	if card_width > zone_rect.size.x * 0.85:
		card_width = zone_rect.size.x * 0.85
		card_height = card_width / aspect
	card_width = maxf(card_width, 30.0)
	card_height = maxf(card_height, 42.0)
	return Vector2(card_width, card_height)


func _format_energy_map(energy_map: Dictionary) -> String:
	if energy_map.is_empty():
		return "0"
	var total := 0
	for color in energy_map.keys():
		total += int(energy_map.get(color, 0))
	return str(total)
