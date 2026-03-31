extends RefCounted
class_name DeckLoader

const UATypes = preload("res://core/ua_types.gd")
const CardDef = preload("res://data/card_def.gd")

const CARD_DATA_PATH := "res://data/cards/cards_effects.json"
const DECKS_DIR_PATH := "res://data/decks"

var _deck_card_lookup := {}


func load_card_defs() -> Dictionary:
	var card_defs := {}
	_deck_card_lookup.clear()
	var json: Array = _read_json(CARD_DATA_PATH)
	for item in json:
		var item_dict: Dictionary = item
		var card_def: CardDef = CardDef.new().from_dict(item_dict)
		card_defs[card_def.id] = card_def
		_register_deck_lookup(card_def)
	return card_defs


func load_deck_list(path: String) -> Array:
	if path.get_extension().to_lower() == "txt":
		return _read_text_deck(path)
	return _read_json(path)


func get_available_decks() -> Array[Dictionary]:
	var deck_files: Array[String] = []
	for file_name_variant in DirAccess.get_files_at(DECKS_DIR_PATH):
		var file_name := str(file_name_variant)
		if file_name.get_extension().to_lower() != "txt":
			continue
		deck_files.append(file_name)
	deck_files.sort()
	var decks: Array[Dictionary] = []
	for file_name in deck_files:
		decks.append({
			"name": file_name.get_basename(),
			"file_name": file_name,
			"path": "%s/%s" % [DECKS_DIR_PATH, file_name],
		})
	return decks


func _read_text_deck(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open %s" % path)
		return []
	var result: Array = []
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var expanded := _expand_deck_line(line)
		if expanded.is_empty():
			push_error("Failed to parse deck line: %s" % line)
			continue
		result.append_array(expanded)
	return result


func _expand_deck_line(line: String) -> Array:
	var split_index := line.find("x")
	if split_index <= 0:
		return []
	var count := int(line.substr(0, split_index))
	var raw_code := line.substr(split_index + 1).strip_edges()
	if count <= 0 or raw_code == "":
		return []
	var def_id := _resolve_deck_card_id(raw_code)
	if def_id == "":
		push_error("Missing card definition for deck code: %s" % raw_code)
		return []
	var expanded: Array = []
	for i in range(count):
		expanded.append(def_id)
	return expanded


func _resolve_deck_card_id(raw_code: String) -> String:
	var normalized_candidates := [
		raw_code,
		raw_code.replace("/", "_").replace("-", "_"),
		raw_code.replace("_", "/"),
	]
	for candidate_variant in normalized_candidates:
		var candidate := str(candidate_variant)
		if _deck_card_lookup.has(candidate):
			return str(_deck_card_lookup[candidate])
	return ""


func _register_deck_lookup(card_def: CardDef) -> void:
	if card_def.id != "":
		_deck_card_lookup[card_def.id] = card_def.id
		_deck_card_lookup[card_def.id.replace("/", "_").replace("-", "_")] = card_def.id
	if card_def.number != "":
		_deck_card_lookup[card_def.number] = card_def.id
		_deck_card_lookup[card_def.number.replace("/", "_")] = card_def.id
		_deck_card_lookup[card_def.number.replace("/", "_").replace("-", "_")] = card_def.id


func _read_json(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open %s" % path)
		return []
	var data_text := file.get_as_text()
	var parsed = JSON.parse_string(data_text)
	if parsed == null:
		push_error("Failed to parse JSON: %s" % path)
		return []
	return parsed