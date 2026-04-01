extends RefCounted
class_name CardCatalog

const CARDS_ROOT_PATH := "res://data/cards"
const BASE_CARDS_PATH := "res://data/cards/base_cards.json"


func load_runtime_cards() -> Array:
	var cards: Array = []
	var seen_ids := {}
	for path in list_series_file_paths("cards_effects.json"):
		for item in read_json_array(path):
			var card := item as Dictionary
			var card_id := str(card.get("id", ""))
			if card_id != "":
				seen_ids[card_id] = true
			cards.append(card)
	for item in read_json_array(BASE_CARDS_PATH):
		var card := item as Dictionary
		var card_id := str(card.get("id", ""))
		if card_id != "" and seen_ids.has(card_id):
			continue
		cards.append(card)
	return cards


func list_series_file_paths(file_name: String) -> Array[String]:
	var results: Array[String] = []
	var root := DirAccess.open(CARDS_ROOT_PATH)
	if root == null:
		push_error("Failed to open %s" % CARDS_ROOT_PATH)
		return results
	root.list_dir_begin()
	var entry := root.get_next()
	while entry != "":
		if not root.current_is_dir():
			entry = root.get_next()
			continue
		if entry.begins_with("."):
			entry = root.get_next()
			continue
		var candidate := "%s/%s/%s" % [CARDS_ROOT_PATH, entry, file_name]
		if FileAccess.file_exists(candidate):
			results.append(candidate)
		entry = root.get_next()
	root.list_dir_end()
	results.sort()
	return results


func read_json_array(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open %s" % path)
		return []
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed == null:
		push_error("Failed to parse JSON: %s" % path)
		return []
	if not (parsed is Array):
		push_error("Expected JSON array: %s" % path)
		return []
	return parsed
