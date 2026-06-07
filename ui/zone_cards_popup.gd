extends Control
class_name ZoneCardsPopup

const CardView = preload("res://ui/card_view.gd")

const THUMBNAIL_SIZE := Vector2(92, 128)
const POPUP_MIN_SIZE := Vector2(520, 360)
const POPUP_MAX_SIZE := Vector2(960, 640)
const GRID_COLUMNS := 5

signal popup_closed

var _overlay: ColorRect
var _panel: PanelContainer
var _title_label: Label
var _count_label: Label
var _empty_label: Label
var _grid: GridContainer

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_overlay = ColorRect.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.color = Color(0.03, 0.05, 0.08, 0.7)
	add_child(_overlay)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var panel_margin := MarginContainer.new()
	panel_margin.add_theme_constant_override("margin_left", 16)
	panel_margin.add_theme_constant_override("margin_top", 16)
	panel_margin.add_theme_constant_override("margin_right", 16)
	panel_margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(panel_margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel_margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)

	_title_label = Label.new()
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", 22)
	header.add_child(_title_label)

	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.pressed.connect(hide_popup)
	header.add_child(close_button)

	_count_label = Label.new()
	_count_label.modulate = Color(0.85, 0.88, 0.92, 0.92)
	root.add_child(_count_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 220)
	root.add_child(scroll)

	var scroll_margin := MarginContainer.new()
	scroll_margin.add_theme_constant_override("margin_left", 4)
	scroll_margin.add_theme_constant_override("margin_top", 4)
	scroll_margin.add_theme_constant_override("margin_right", 4)
	scroll_margin.add_theme_constant_override("margin_bottom", 4)
	scroll.add_child(scroll_margin)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll_margin.add_child(content)

	_empty_label = Label.new()
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.text = "该区域当前没有卡牌。"
	content.add_child(_empty_label)

	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	content.add_child(_grid)

	get_viewport().size_changed.connect(_update_panel_layout)
	_update_panel_layout()

func show_zone_cards(title_text: String, cards: Array) -> void:
	_title_label.text = title_text
	_count_label.text = "共 %d 张卡" % cards.size()
	for child in _grid.get_children():
		child.queue_free()
	for card_data_variant in cards:
		var card_data: Dictionary = card_data_variant
		var card_view := CardView.new()
		card_view.setup(card_data, str(card_data.get("owner_player_id", "")), str(card_data.get("zone", "")), THUMBNAIL_SIZE, CardView.DISPLAY_MODE_HAND)
		card_view.disabled = true
		card_view.focus_mode = Control.FOCUS_NONE
		_grid.add_child(card_view)
	_empty_label.visible = cards.is_empty()
	_grid.visible = not cards.is_empty()
	visible = true
	move_to_front()
	_update_panel_layout()

func hide_popup() -> void:
	if not visible:
		return
	visible = false
	popup_closed.emit()

func _update_panel_layout() -> void:
	if _panel == null:
		return
	var viewport_size := get_viewport_rect().size
	var panel_width := clampf(viewport_size.x * 0.68, POPUP_MIN_SIZE.x, minf(POPUP_MAX_SIZE.x, viewport_size.x - 32.0))
	var panel_height := clampf(viewport_size.y * 0.7, POPUP_MIN_SIZE.y, minf(POPUP_MAX_SIZE.y, viewport_size.y - 32.0))
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_panel.size = Vector2(panel_width, panel_height)
	_panel.position = (viewport_size - _panel.size) * 0.5

func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _panel != null and not _panel.get_global_rect().has_point(event.global_position):
			hide_popup()
			accept_event()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		hide_popup()
		accept_event()
