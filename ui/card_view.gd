extends Button
class_name CardView

signal card_pressed(owner_player_id: String, card_uid: String, zone_name: String)
signal card_hovered(card_uid: String, is_hovered: bool)

const DEFAULT_CARD_SIZE := Vector2(120, 168)
const DISPLAY_MODE_BOARD := "board"
const DISPLAY_MODE_HAND := "hand"
const HAND_PADDING := 4
const HAND_IMAGE_ASPECT_RATIO := 5.0 / 7.0
const BOARD_PADDING := 4
const BOARD_INFO_HEIGHT_RATIO := 0.28
const PLAYABLE_BORDER_COLOR := Color(0.2, 0.8, 0.3, 0.9)
const PLAYABLE_BORDER_WIDTH := 3.0

var owner_player_id := ""
var card_uid := ""
var zone_name := ""
var _display_text := ""
var _card_size := DEFAULT_CARD_SIZE
var _display_mode := DISPLAY_MODE_BOARD
var _card_data: Dictionary = {}
var _is_hovered := false
var _is_playable := false

var _content_root: Control
var _fallback_label: Label
var _hand_image: TextureRect
var _board_column: VBoxContainer
var _board_image: TextureRect
var _board_text: Label

func _ready() -> void:
	_ensure_ui()
	_refresh_view()

func setup(card_data: Dictionary, p_owner_player_id: String, p_zone_name: String, card_size: Vector2 = DEFAULT_CARD_SIZE, display_mode := DISPLAY_MODE_BOARD) -> void:
	owner_player_id = p_owner_player_id
	card_uid = str(card_data.get("uid", ""))
	zone_name = p_zone_name
	_card_data = card_data.duplicate(true)
	_card_size = card_size
	_display_mode = display_mode
	_display_text = _build_text(_card_data)
	custom_minimum_size = _card_size
	clip_contents = true
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	text = ""
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ensure_ui()
	_refresh_view()

func _ensure_ui() -> void:
	if _content_root != null:
		return
	_content_root = Control.new()
	_content_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content_root)

	_fallback_label = Label.new()
	_fallback_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fallback_label.offset_left = HAND_PADDING
	_fallback_label.offset_top = HAND_PADDING
	_fallback_label.offset_right = -HAND_PADDING
	_fallback_label.offset_bottom = -HAND_PADDING
	_fallback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fallback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_fallback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fallback_label.clip_text = true
	_content_root.add_child(_fallback_label)

	_hand_image = TextureRect.new()
	_hand_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hand_image.offset_left = HAND_PADDING
	_hand_image.offset_top = HAND_PADDING
	_hand_image.offset_right = -HAND_PADDING
	_hand_image.offset_bottom = -HAND_PADDING
	_hand_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hand_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_content_root.add_child(_hand_image)

	_board_column = VBoxContainer.new()
	_board_column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board_column.offset_left = BOARD_PADDING
	_board_column.offset_top = BOARD_PADDING
	_board_column.offset_right = -BOARD_PADDING
	_board_column.offset_bottom = -BOARD_PADDING
	_board_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_column.add_theme_constant_override("separation", 4)
	_content_root.add_child(_board_column)

	_board_image = TextureRect.new()
	_board_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_board_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_board_image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board_column.add_child(_board_image)

	_board_text = Label.new()
	_board_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_board_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_board_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_board_text.clip_text = true
	_board_column.add_child(_board_text)

func _refresh_view() -> void:
	if _content_root == null:
		return
	var font_size: int = 10 if _card_size.y <= 44 else (11 if _card_size.y <= 60 else (12 if _card_size.y <= 72 else 14))
	var board_font_size: int = maxi(8, font_size - 1)
	add_theme_font_size_override("font_size", font_size)
	_fallback_label.add_theme_font_size_override("font_size", font_size)
	_board_text.add_theme_font_size_override("font_size", board_font_size)
	_fallback_label.visible = true
	_hand_image.visible = false
	_board_column.visible = false
	if _display_mode == DISPLAY_MODE_HAND:
		var hand_texture := _resolve_card_texture(_card_data)
		if hand_texture != null:
			_display_text = _build_hand_text(_card_data)
			_fallback_label.visible = false
			_hand_image.visible = true
			_hand_image.texture = hand_texture
			_hand_image.custom_minimum_size = _hand_image_size()
			return
	elif _display_mode == DISPLAY_MODE_BOARD:
		var board_texture := _resolve_card_texture(_card_data)
		if board_texture != null:
			_display_text = _build_board_text(_card_data)
			_fallback_label.visible = false
			_board_column.visible = true
			_board_image.texture = board_texture
			_board_image.custom_minimum_size = _board_image_size()
			_board_text.custom_minimum_size = Vector2(0, _board_info_height())
			_board_text.text = _build_board_thumbnail_text(_card_data)
			return
	_fallback_label.text = _build_text(_card_data)

func _build_text(card_data: Dictionary) -> String:
	if _display_mode == DISPLAY_MODE_HAND:
		return _build_hand_text(card_data)
	return _build_board_text(card_data)

func _build_hand_text(card_data: Dictionary) -> String:
	var name := str(card_data.get("name", "Unknown"))
	var card_type := str(card_data.get("card_type", "?"))
	var ap_text := _format_number(card_data.get("cost_ap", 0))
	var need_text := _format_energy_map(card_data.get("cost_energy", {}))
	if _card_size.y <= 44:
		return "%s\nAP:%s N:%s" % [_shorten(name, 10), ap_text, need_text]
	if _card_size.y <= 60:
		var line_two := "%s | AP:%s | N:%s" % [_short_type(card_type), ap_text, need_text]
		return "%s\n%s" % [_shorten(name, 12), line_two]
	var lines: Array[String] = [name]
	lines.append("%s | AP:%s" % [card_type, ap_text])
	lines.append("Need:%s  Give:%s" % [
		_format_energy_map(card_data.get("cost_energy", {})),
		_format_energy_map(card_data.get("energy_provided", {})),
	])
	lines.append(str(card_data.get("state", "ACTIVE")))
	return "\n".join(lines)

func _build_board_text(card_data: Dictionary) -> String:
	var lines: Array[String] = [str(card_data.get("name", "Unknown"))]
	lines.append("%s | AP:%s" % [str(card_data.get("card_type", "?")), _format_number(card_data.get("cost_ap", 0))])
	if _card_size.y <= 80:
		if int(card_data.get("bp", 0)) > 0:
			lines.append("BP %d | %s" % [
				int(card_data.get("bp", 0)),
				str(card_data.get("state", "ACTIVE")),
			])
		else:
			lines.append(str(card_data.get("state", "ACTIVE")))
		var compact_hint := _compact_hint(card_data)
		if compact_hint != "":
			lines.append(compact_hint)
		return "\n".join(lines)

	lines.append("Need: %s" % _format_energy_map(card_data.get("cost_energy", {})))
	lines.append("Give: %s" % _format_energy_map(card_data.get("energy_provided", {})))
	if int(card_data.get("bp", 0)) > 0:
		lines.append("BP %d | %s" % [
			int(card_data.get("bp", 0)),
			str(card_data.get("state", "ACTIVE")),
		])
	else:
		lines.append(str(card_data.get("state", "ACTIVE")))
	var detail_hint := _compact_hint(card_data)
	if detail_hint != "":
		lines.append(detail_hint)
	return "\n".join(lines)

func _build_board_thumbnail_text(card_data: Dictionary) -> String:
	var name := _shorten(str(card_data.get("name", "Unknown")), 10)
	var lines: Array[String] = [name]
	if int(card_data.get("bp", 0)) > 0:
		lines.append("BP %d" % int(card_data.get("bp", 0)))
	lines.append("AP:%s" % _format_number(card_data.get("cost_ap", 0)))
	var state := str(card_data.get("state", "ACTIVE"))
	if state != "ACTIVE":
		lines.append(state)
	return "\n".join(lines)

func _resolve_card_texture(card_data: Dictionary) -> Texture2D:
	for image_path in _card_image_candidates(card_data):
		if ResourceLoader.exists(image_path):
			var texture := load(image_path)
			if texture is Texture2D:
				return texture
	return null

func _card_image_candidates(card_data: Dictionary) -> Array[String]:
	var candidates: Array[String] = []
	var source_image := str(card_data.get("source_image", "")).strip_edges()
	if source_image != "":
		_append_card_image_candidate(candidates, source_image)
	var number := str(card_data.get("number", "")).strip_edges()
	if number == "":
		return candidates
	var normalized_values := [
		number.replace("/", "-"),
		number.replace("/", "_").replace("-", "_"),
		number.replace("/", "-").replace("_", "-"),
	]
	for value in normalized_values:
		var normalized := str(value).strip_edges()
		if normalized == "":
			continue
		var filename := normalized if normalized.to_lower().ends_with(".png") else "%s.png" % normalized
		_append_card_image_candidate(candidates, filename)
	return candidates

func _append_card_image_candidate(candidates: Array[String], filename: String) -> void:
	var normalized := filename.strip_edges()
	if normalized == "":
		return
	for path in [
		"res://pic/micro/%s" % normalized,
		"res://pic/%s" % normalized,
	]:
		if not candidates.has(path):
			candidates.append(path)

func _hand_image_size() -> Vector2:
	var content_height: float = maxi(24.0, _card_size.y - float(HAND_PADDING * 2))
	var image_width: float = round(content_height * HAND_IMAGE_ASPECT_RATIO)
	return Vector2(image_width, content_height)

func _board_image_size() -> Vector2:
	var image_height: float = maxi(48.0, _card_size.y - _board_info_height() - float(BOARD_PADDING * 2))
	var image_width: float = round(image_height * HAND_IMAGE_ASPECT_RATIO)
	return Vector2(minf(_card_size.x - float(BOARD_PADDING * 2), image_width), image_height)

func _board_info_height() -> float:
	return round(_card_size.y * BOARD_INFO_HEIGHT_RATIO)

func _compact_hint(card_data: Dictionary) -> String:
	var actions := _format_string_list(card_data.get("available_actions", []))
	if actions != "-":
		return "Acts: %s" % actions
	var keywords := _format_string_list(card_data.get("keywords", []))
	if keywords != "-":
		return "KW: %s" % keywords
	var stacked := _format_string_list(card_data.get("stacked_under", []))
	if stacked != "-":
		return "Under: %s" % stacked
	var flags := _format_flags(card_data.get("flags", {}))
	if flags != "-":
		return "Flags: %s" % flags
	return ""

func _short_type(card_type: String) -> String:
	match card_type:
		"CHARACTER":
			return "CH"
		"EVENT":
			return "EV"
		"FIELD":
			return "FD"
		_:
			return card_type.left(2)

func _shorten(value: String, max_chars: int) -> String:
	if value.length() <= max_chars:
		return value
	return value.substr(0, max_chars - 1) + "~"

func _format_energy_map(energy_map: Dictionary) -> String:
	if energy_map.is_empty():
		return "0"
	var parts: Array[String] = []
	for color in energy_map.keys():
		parts.append("%s:%s" % [str(color), _format_number(energy_map.get(color, 0))])
	parts.sort()
	return ", ".join(parts)

func _format_string_list(values) -> String:
	if values is Array and not values.is_empty():
		var items: Array[String] = []
		for value in values:
			items.append(str(value))
		return ", ".join(items)
	return "-"

func _format_flags(flags) -> String:
	if not (flags is Dictionary):
		return "-"
	var parts: Array[String] = []
	if bool(flags.get("attacked_this_turn", false)):
		parts.append("ATK")
	if bool(flags.get("blocked_this_turn", false)):
		parts.append("BLK")
	if bool(flags.get("activated_main_this_turn", false)):
		parts.append("MAIN")
	if bool(flags.get("double_attack_consumed", false)):
		parts.append("2A")
	if bool(flags.get("double_block_consumed", false)):
		parts.append("2B")
	if bool(flags.get("entered_via_raid", false)):
		parts.append("RAID")
	return ", ".join(parts) if not parts.is_empty() else "-"

func _format_number(value) -> String:
	if value is int:
		return str(value)
	if value is float:
		var number: float = value
		if is_equal_approx(number, round(number)):
			return str(int(round(number)))
		return str(number)
	return str(value)

func _get_drag_data(_at_position: Vector2):
	if zone_name != "hand":
		return null
	var preview = TextureRect.new()
	preview.custom_minimum_size = _card_size
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture = _resolve_card_texture(_card_data)
	set_drag_preview(preview)
	return {
		"kind": "hand_card",
		"card_uid": card_uid,
		"owner_player_id": owner_player_id,
		"source_zone": zone_name
	}

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_pressed()
		accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		if zone_name == "hand" and not _is_hovered:
			_is_hovered = true
			emit_signal("card_hovered", card_uid, true)
	elif what == NOTIFICATION_MOUSE_EXIT:
		if _is_hovered:
			_is_hovered = false
			emit_signal("card_hovered", card_uid, false)

func set_playable(playable: bool) -> void:
	_is_playable = playable
	queue_redraw()

func _draw() -> void:
	if _is_playable and zone_name == "hand":
		# 绘制可打出状态边框
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, PLAYABLE_BORDER_COLOR, false, PLAYABLE_BORDER_WIDTH)

func _on_pressed() -> void:
	emit_signal("card_pressed", owner_player_id, card_uid, zone_name)
