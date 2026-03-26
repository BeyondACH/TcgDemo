extends Control
class_name PreviewSelectionModal

signal submitted(selected_values: Array)

const CardView = preload("res://ui/card_view.gd")

const CARD_SIZE := Vector2(110, 154)
const ACCENT_COLOR := Color(0.25, 0.78, 0.98, 1.0)
const DIM_COLOR := Color(0.55, 0.55, 0.55, 0.9)
const NORMAL_COLOR := Color(1, 1, 1, 1)

var _title_label: Label
var _subtitle_label: Label
var _cards_row: HBoxContainer
var _confirm_button: Button

var _decision: Dictionary = {}
var _selected_uids: Array[String] = []
var _ordered_uids: Array[String] = []
var _tile_views: Dictionary = {}
var _move_left_buttons: Dictionary = {}
var _move_right_buttons: Dictionary = {}

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()

func show_decision(decision: Dictionary) -> void:
	_decision = decision.duplicate(true)
	_selected_uids.clear()
	_ordered_uids.clear()
	var preview_cards: Array = _decision.get("preview_cards", [])
	for card_variant in preview_cards:
		var card_data: Dictionary = card_variant
		var card_uid := str(card_data.get("uid", ""))
		if card_uid != "":
			_ordered_uids.append(card_uid)
	visible = true
	_render_cards()
	_refresh_state()

func hide_modal() -> void:
	visible = false
	_decision = {}
	_selected_uids.clear()
	_ordered_uids.clear()
	_tile_views.clear()
	_move_left_buttons.clear()
	_move_right_buttons.clear()
	for child in _cards_row.get_children():
		child.queue_free()

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.05, 0.07, 0.1, 0.72)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(920, 420)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 20)
	content.add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_subtitle_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)

	_cards_row = HBoxContainer.new()
	_cards_row.add_theme_constant_override("separation", 12)
	scroll.add_child(_cards_row)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	content.add_child(footer)

	_confirm_button = Button.new()
	_confirm_button.text = "确认"
	_confirm_button.pressed.connect(_on_confirm_pressed)
	footer.add_child(_confirm_button)

func _render_cards() -> void:
	_tile_views.clear()
	_move_left_buttons.clear()
	_move_right_buttons.clear()
	for child in _cards_row.get_children():
		child.queue_free()
	var preview_cards: Array = _decision.get("preview_cards", [])
	for card_variant in preview_cards:
		var card_data: Dictionary = card_variant
		var tile := PanelContainer.new()
		tile.custom_minimum_size = Vector2(CARD_SIZE.x + 20, CARD_SIZE.y + 74)
		_cards_row.add_child(tile)

		var tile_margin := MarginContainer.new()
		tile_margin.add_theme_constant_override("margin_left", 8)
		tile_margin.add_theme_constant_override("margin_top", 8)
		tile_margin.add_theme_constant_override("margin_right", 8)
		tile_margin.add_theme_constant_override("margin_bottom", 8)
		tile.add_child(tile_margin)

		var tile_column := VBoxContainer.new()
		tile_column.add_theme_constant_override("separation", 6)
		tile_margin.add_child(tile_column)

		var card_view := CardView.new()
		card_view.setup(card_data, "", "preview", CARD_SIZE, CardView.DISPLAY_MODE_HAND)
		card_view.pressed.connect(_on_card_pressed.bind(str(card_data.get("uid", ""))))
		tile_column.add_child(card_view)

		var name_label := Label.new()
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.text = str(card_data.get("name", "Unknown"))
		tile_column.add_child(name_label)

		var controls := HBoxContainer.new()
		controls.alignment = BoxContainer.ALIGNMENT_CENTER
		controls.add_theme_constant_override("separation", 6)
		tile_column.add_child(controls)

		var left_button := Button.new()
		left_button.text = "←"
		left_button.custom_minimum_size = Vector2(34, 0)
		left_button.pressed.connect(_on_move_left_pressed.bind(str(card_data.get("uid", ""))))
		controls.add_child(left_button)

		var right_button := Button.new()
		right_button.text = "→"
		right_button.custom_minimum_size = Vector2(34, 0)
		right_button.pressed.connect(_on_move_right_pressed.bind(str(card_data.get("uid", ""))))
		controls.add_child(right_button)

		var card_uid := str(card_data.get("uid", ""))
		_tile_views[card_uid] = tile
		_move_left_buttons[card_uid] = left_button
		_move_right_buttons[card_uid] = right_button

func _refresh_state() -> void:
	if _decision.is_empty():
		return
	var ui_mode := str(_decision.get("ui_mode", ""))
	var preview_cards: Array = _decision.get("preview_cards", [])
	var legal_choices: Dictionary = {}
	for choice_variant in _decision.get("choices", []):
		var choice: Dictionary = choice_variant
		legal_choices[str(choice.get("value", ""))] = true

	_title_label.text = str(_decision.get("title", "查看牌堆顶"))
	if ui_mode == "PREVIEW_REORDER":
		_subtitle_label.text = "调整剩余卡牌回到底部的顺序，然后点击确认。"
	else:
		var min_count := int(_decision.get("min", 0))
		var max_count := int(_decision.get("max", 1))
		_subtitle_label.text = "点击缩略图选择卡牌，当前已选 %d 张（最少 %d，最多 %d）。" % [_selected_uids.size(), min_count, max_count]

	for card_variant in preview_cards:
		var card_data: Dictionary = card_variant
		var card_uid := str(card_data.get("uid", ""))
		var tile: PanelContainer = _tile_views.get(card_uid)
		var left_button: Button = _move_left_buttons.get(card_uid)
		var right_button: Button = _move_right_buttons.get(card_uid)
		if tile == null:
			continue
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.13, 0.16, 0.22, 0.96)
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		var disabled := false
		if ui_mode == "PREVIEW_PICK":
			disabled = not legal_choices.has(card_uid) or _is_blocked_by_distinct_constraint(card_uid)
			style.border_color = ACCENT_COLOR if _selected_uids.has(card_uid) else Color(0.3, 0.35, 0.45, 1.0)
		else:
			style.border_color = Color(0.3, 0.35, 0.45, 1.0)
		tile.add_theme_stylebox_override("panel", style)
		tile.modulate = DIM_COLOR if disabled else NORMAL_COLOR
		var card_view := tile.get_child(0).get_child(0).get_child(0) as CardView
		if card_view != null:
			card_view.disabled = disabled
		if left_button != null and right_button != null:
			var order_index := _ordered_uids.find(card_uid)
			left_button.visible = ui_mode == "PREVIEW_REORDER"
			right_button.visible = ui_mode == "PREVIEW_REORDER"
			left_button.disabled = ui_mode != "PREVIEW_REORDER" or order_index <= 0
			right_button.disabled = ui_mode != "PREVIEW_REORDER" or order_index < 0 or order_index >= _ordered_uids.size() - 1

	_confirm_button.disabled = not _can_confirm()

func _can_confirm() -> bool:
	var ui_mode := str(_decision.get("ui_mode", ""))
	if ui_mode == "PREVIEW_REORDER":
		return not _ordered_uids.is_empty()
	var min_count := int(_decision.get("min", 0))
	var max_count := int(_decision.get("max", 1))
	if _selected_uids.size() < min_count or _selected_uids.size() > max_count:
		return false
	return not _has_duplicate_name_selection()

func _on_card_pressed(card_uid: String) -> void:
	if str(_decision.get("ui_mode", "")) != "PREVIEW_PICK":
		return
	var legal_choices: Dictionary = {}
	for choice_variant in _decision.get("choices", []):
		var choice: Dictionary = choice_variant
		legal_choices[str(choice.get("value", ""))] = true
	if not legal_choices.has(card_uid) or _is_blocked_by_distinct_constraint(card_uid):
		return
	var max_count := int(_decision.get("max", 1))
	var selected_index := _selected_uids.find(card_uid)
	if selected_index >= 0:
		_selected_uids.remove_at(selected_index)
	elif max_count == 1:
		_selected_uids = [card_uid]
	else:
		_selected_uids.append(card_uid)
	_refresh_state()

func _on_move_left_pressed(card_uid: String) -> void:
	var index := _ordered_uids.find(card_uid)
	if index <= 0:
		return
	_ordered_uids[index] = _ordered_uids[index - 1]
	_ordered_uids[index - 1] = card_uid
	_reorder_tiles()

func _on_move_right_pressed(card_uid: String) -> void:
	var index := _ordered_uids.find(card_uid)
	if index < 0 or index >= _ordered_uids.size() - 1:
		return
	_ordered_uids[index] = _ordered_uids[index + 1]
	_ordered_uids[index + 1] = card_uid
	_reorder_tiles()

func _reorder_tiles() -> void:
	for card_uid in _ordered_uids:
		var tile: Control = _tile_views.get(card_uid)
		if tile != null:
			_cards_row.move_child(tile, _cards_row.get_child_count() - 1)
	for i in range(_ordered_uids.size()):
		var tile: Control = _tile_views.get(_ordered_uids[i])
		if tile != null:
			_cards_row.move_child(tile, i)
	_refresh_state()

func _on_confirm_pressed() -> void:
	if not _can_confirm():
		return
	if str(_decision.get("ui_mode", "")) == "PREVIEW_REORDER":
		submitted.emit(_ordered_uids.duplicate())
		return
	submitted.emit(_selected_uids.duplicate())

func _is_blocked_by_distinct_constraint(card_uid: String) -> bool:
	var constraints: Dictionary = _decision.get("selection_constraints", {})
	if str(constraints.get("distinct_by", "")) != "CARD_NAME":
		return false
	if _selected_uids.has(card_uid):
		return false
	var card_name := _card_name_for_uid(card_uid)
	if card_name == "":
		return false
	for selected_uid in _selected_uids:
		if _card_name_for_uid(selected_uid) == card_name:
			return true
	return false

func _has_duplicate_name_selection() -> bool:
	var constraints: Dictionary = _decision.get("selection_constraints", {})
	if str(constraints.get("distinct_by", "")) != "CARD_NAME":
		return false
	var seen_names: Dictionary = {}
	for card_uid in _selected_uids:
		var card_name := _card_name_for_uid(card_uid)
		if card_name == "":
			continue
		if seen_names.has(card_name):
			return true
		seen_names[card_name] = true
	return false

func _card_name_for_uid(card_uid: String) -> String:
	for card_variant in _decision.get("preview_cards", []):
		var card_data: Dictionary = card_variant
		if str(card_data.get("uid", "")) == card_uid:
			return str(card_data.get("name", ""))
	return ""
