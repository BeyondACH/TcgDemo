extends Button
class_name CardView

signal card_pressed(owner_player_id: String, card_uid: String, zone_name: String)

var owner_player_id := ""
var card_uid := ""
var zone_name := ""

func setup(card_data: Dictionary, p_owner_player_id: String, p_zone_name: String) -> void:
	owner_player_id = p_owner_player_id
	card_uid = str(card_data.get("uid", ""))
	zone_name = p_zone_name
	text = _build_text(card_data)
	custom_minimum_size = Vector2(150, 96)
	pressed.connect(_on_pressed)

func _build_text(card_data: Dictionary) -> String:
	var lines: Array[String] = [str(card_data.get("name", "Unknown"))]
	lines.append("%s | AP:%s" % [str(card_data.get("card_type", "?")), _format_number(card_data.get("cost_ap", 0))])
	lines.append("Need: %s" % _format_energy_map(card_data.get("cost_energy", {})))
	lines.append("Give: %s" % _format_energy_map(card_data.get("energy_provided", {})))
	if int(card_data.get("bp", 0)) > 0:
		lines.append("BP %d" % int(card_data.get("bp", 0)))
	lines.append(str(card_data.get("state", "ACTIVE")))
	return "\n".join(lines)

func _format_energy_map(energy_map: Dictionary) -> String:
	if energy_map.is_empty():
		return "0"
	var parts: Array[String] = []
	for color in energy_map.keys():
		parts.append("%s:%s" % [str(color), _format_number(energy_map.get(color, 0))])
	parts.sort()
	return ", ".join(parts)

func _format_number(value) -> String:
	if value is int:
		return str(value)
	if value is float:
		var number: float = value
		if is_equal_approx(number, round(number)):
			return str(int(round(number)))
		return str(number)
	return str(value)

func _on_pressed() -> void:
	emit_signal("card_pressed", owner_player_id, card_uid, zone_name)
