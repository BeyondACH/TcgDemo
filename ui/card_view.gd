extends Button
class_name CardView

signal card_pressed(owner_player_id: String, card_uid: String, zone_name: String)

const DEFAULT_CARD_SIZE := Vector2(150, 96)
const DISPLAY_MODE_BOARD := "board"
const DISPLAY_MODE_HAND := "hand"

var owner_player_id := ""
var card_uid := ""
var zone_name := ""
var _display_text := ""
var _card_size := DEFAULT_CARD_SIZE
var _display_mode := DISPLAY_MODE_BOARD

func setup(card_data: Dictionary, p_owner_player_id: String, p_zone_name: String, card_size: Vector2 = DEFAULT_CARD_SIZE, display_mode := DISPLAY_MODE_BOARD) -> void:
	owner_player_id = p_owner_player_id
	card_uid = str(card_data.get("uid", ""))
	zone_name = p_zone_name
	_card_size = card_size
	_display_mode = display_mode
	_display_text = _build_text(card_data)
	text = _display_text
	custom_minimum_size = _card_size
	clip_contents = true
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var font_size := 10 if _card_size.y <= 44 else (11 if _card_size.y <= 60 else (12 if _card_size.y <= 72 else 14))
	add_theme_font_size_override("font_size", font_size)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _build_text(card_data: Dictionary) -> String:
	if _display_mode == DISPLAY_MODE_HAND:
		return _build_hand_text(card_data)
	return _build_board_text(card_data)

func _build_hand_text(card_data: Dictionary) -> String:
	var name := str(card_data.get("name", "Unknown"))
	var card_type := str(card_data.get("card_type", "?"))
	var ap_text := _format_number(card_data.get("cost_ap", 0))
	if _card_size.y <= 44:
		return "%s\n%s/%s" % [_shorten(name, 10), _short_type(card_type), ap_text]
	if _card_size.y <= 60:
		var line_two := "%s | AP:%s" % [_short_type(card_type), ap_text]
		if int(card_data.get("bp", 0)) > 0:
			line_two += " | %s" % _format_number(card_data.get("bp", 0))
		return "%s\n%s" % [_shorten(name, 12), line_two]
	var lines: Array[String] = [name]
	lines.append("%s | AP:%s" % [card_type, ap_text])
	lines.append("Need:%s  Give:%s" % [
		_format_energy_map(card_data.get("cost_energy", {})),
		_format_energy_map(card_data.get("energy_provided", {})),
	])
	if int(card_data.get("bp", 0)) > 0:
		lines.append("BP %d | %s" % [
			int(card_data.get("bp", 0)),
			str(card_data.get("state", "ACTIVE")),
		])
	else:
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
	var preview := Label.new()
	preview.text = _display_text
	preview.custom_minimum_size = _card_size
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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

func _on_pressed() -> void:
	emit_signal("card_pressed", owner_player_id, card_uid, zone_name)
