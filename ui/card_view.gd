extends Button
class_name CardView

signal card_pressed(owner_player_id: String, card_uid: String, zone_name: String)

const DEFAULT_CARD_SIZE := Vector2(150, 96)

var owner_player_id := ""
var card_uid := ""
var zone_name := ""
var _display_text := ""
var _card_size := DEFAULT_CARD_SIZE

func setup(card_data: Dictionary, p_owner_player_id: String, p_zone_name: String, card_size: Vector2 = DEFAULT_CARD_SIZE) -> void:
	owner_player_id = p_owner_player_id
	card_uid = str(card_data.get("uid", ""))
	zone_name = p_zone_name
	_card_size = card_size
	_display_text = _build_text(card_data)
	text = _display_text
	custom_minimum_size = _card_size
	pressed.connect(_on_pressed)

func _build_text(card_data: Dictionary) -> String:
	var lines: Array[String] = [str(card_data.get("name", "Unknown"))]
	lines.append("%s | AP:%s" % [str(card_data.get("card_type", "?")), _format_number(card_data.get("cost_ap", 0))])
	lines.append("Need: %s" % _format_energy_map(card_data.get("cost_energy", {})))
	lines.append("Give: %s" % _format_energy_map(card_data.get("energy_provided", {})))
	if int(card_data.get("bp", 0)) > 0:
		lines.append("BP %d" % int(card_data.get("bp", 0)))
	lines.append("%s / %s" % [str(card_data.get("zone", "?")), str(card_data.get("state", "ACTIVE"))])
	lines.append("KW: %s" % _format_string_list(card_data.get("keywords", [])))
	lines.append("Under: %s" % _format_string_list(card_data.get("stacked_under", [])))
	lines.append("Flags: %s" % _format_flags(card_data.get("flags", {})))
	lines.append("Acts: %s" % _format_string_list(card_data.get("available_actions", [])))
	return "\n".join(lines)

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
	set_drag_preview(preview)
	return {
		"kind": "hand_card",
		"card_uid": card_uid,
		"owner_player_id": owner_player_id,
		"source_zone": zone_name
	}

func _on_pressed() -> void:
	emit_signal("card_pressed", owner_player_id, card_uid, zone_name)
