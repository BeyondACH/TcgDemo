extends Control
class_name LifeRevealModal

signal activate_requested(card_uid: String)
signal skip_requested(card_uid: String)
signal acknowledge_requested(card_uid: String)

const CardView = preload("res://ui/card_view.gd")

const CARD_SIZE := Vector2(160, 224)
const CURRENT_BORDER := Color(0.96, 0.78, 0.26, 1.0)
const RESOLVED_BORDER := Color(0.34, 0.68, 0.42, 1.0)
const IDLE_BORDER := Color(0.3, 0.35, 0.45, 1.0)
const DIM_COLOR := Color(0.58, 0.58, 0.58, 0.82)
const NORMAL_COLOR := Color(1, 1, 1, 1)

var _title_label: Label
var _subtitle_label: Label
var _cards_row: HBoxContainer
var _activate_button: Button
var _skip_button: Button
var _continue_button: Button

var _modal_data: Dictionary = {}
var _tile_views := {}

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()

func show_modal(modal_data: Dictionary) -> void:
	_modal_data = modal_data.duplicate(true)
	visible = bool(_modal_data.get("visible", false))
	if not visible:
		return
	_render_cards()
	_refresh_state()

func hide_modal() -> void:
	visible = false
	_modal_data = {}
	_tile_views.clear()
	if _cards_row == null:
		return
	for child in _cards_row.get_children():
		child.queue_free()

func set_input_blocking(blocking: bool) -> void:
	_set_mouse_filter_recursive(self, Control.MOUSE_FILTER_STOP if blocking else Control.MOUSE_FILTER_IGNORE)

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
	panel.custom_minimum_size = Vector2(1220, 560)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
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
	_cards_row.add_theme_constant_override("separation", 18)
	scroll.add_child(_cards_row)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 8)
	content.add_child(footer)

	_continue_button = Button.new()
	_continue_button.text = "Continue"
	_continue_button.pressed.connect(_on_continue_pressed)
	footer.add_child(_continue_button)

	_skip_button = Button.new()
	_skip_button.text = "Skip"
	_skip_button.pressed.connect(_on_skip_pressed)
	footer.add_child(_skip_button)

	_activate_button = Button.new()
	_activate_button.text = "Activate"
	_activate_button.pressed.connect(_on_activate_pressed)
	footer.add_child(_activate_button)

func _render_cards() -> void:
	_tile_views.clear()
	for child in _cards_row.get_children():
		child.queue_free()
	for card_variant in _modal_data.get("revealed_cards", []):
		var card_data: Dictionary = card_variant
		var tile := PanelContainer.new()
		tile.custom_minimum_size = Vector2(CARD_SIZE.x + 24, CARD_SIZE.y + 24)
		_cards_row.add_child(tile)

		var tile_margin := MarginContainer.new()
		tile_margin.add_theme_constant_override("margin_left", 10)
		tile_margin.add_theme_constant_override("margin_top", 10)
		tile_margin.add_theme_constant_override("margin_right", 10)
		tile_margin.add_theme_constant_override("margin_bottom", 10)
		tile.add_child(tile_margin)

		var card_view := CardView.new()
		card_view.setup(card_data, "", "life_reveal", CARD_SIZE, CardView.DISPLAY_MODE_HAND)
		card_view.disabled = true
		tile_margin.add_child(card_view)

		_tile_views[str(card_data.get("uid", ""))] = tile

func _refresh_state() -> void:
	if _modal_data.is_empty():
		return
	var current_card_uid := str(_modal_data.get("current_card_uid", ""))
	var player_id := str(_modal_data.get("player_id", ""))
	_title_label.text = "Life Reveal: %s" % player_id
	if current_card_uid == "":
		_subtitle_label.text = "All revealed life cards have been processed."
	elif bool(_modal_data.get("waiting_for_ai_resolution", false)):
		_subtitle_label.text = "You have confirmed this revealed card. AI is now resolving its life trigger."
	elif bool(_modal_data.get("ai_resolves_after_confirmation", false)) and bool(_modal_data.get("awaiting_player_confirmation", false)):
		_subtitle_label.text = "Review the highlighted revealed card, then press Continue to hand resolution back to AI."
	else:
		_subtitle_label.text = "Review the revealed cards. Only the highlighted card can be resolved now."

	for card_variant in _modal_data.get("revealed_cards", []):
		var card_data: Dictionary = card_variant
		var card_uid := str(card_data.get("uid", ""))
		var tile: PanelContainer = _tile_views.get(card_uid)
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
		if bool(card_data.get("resolved", false)):
			style.border_color = RESOLVED_BORDER
			tile.modulate = DIM_COLOR
		elif bool(card_data.get("is_current", false)):
			style.border_color = CURRENT_BORDER
			tile.modulate = NORMAL_COLOR
		else:
			style.border_color = IDLE_BORDER
			tile.modulate = NORMAL_COLOR
		tile.add_theme_stylebox_override("panel", style)

	_activate_button.visible = bool(_modal_data.get("can_activate", false))
	_skip_button.visible = bool(_modal_data.get("can_skip", false))
	_continue_button.visible = bool(_modal_data.get("can_acknowledge", false))

func _on_activate_pressed() -> void:
	var current_card_uid := str(_modal_data.get("current_card_uid", ""))
	if current_card_uid != "":
		activate_requested.emit(current_card_uid)

func _on_skip_pressed() -> void:
	var current_card_uid := str(_modal_data.get("current_card_uid", ""))
	if current_card_uid != "":
		skip_requested.emit(current_card_uid)

func _on_continue_pressed() -> void:
	var current_card_uid := str(_modal_data.get("current_card_uid", ""))
	if current_card_uid != "":
		acknowledge_requested.emit(current_card_uid)

func _set_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter
	for child in node.get_children():
		_set_mouse_filter_recursive(child, filter)
