extends RefCounted
class_name DeckImporter

const CardCatalog = preload("res://data/card_catalog.gd")

var _card_catalog := CardCatalog.new()

func import_deck(deck_name: String, source_path: String, output_dir: String) -> Dictionary:
	if deck_name.strip_edges().is_empty():
		return {"ok": false, "error": "Deck name is required."}

	var base_cards: Array = _card_catalog.load_runtime_cards()
	if base_cards.is_empty():
		return {"ok": false, "error": "Failed to load runtime cards from series directories."}

	var import_lines: Array = _read_lines(source_path)
	if import_lines == null:
		return {"ok": false, "error": "Failed to read import file: %s." % source_path}

	var lookup: Dictionary = _build_card_lookup(base_cards)
	var output_cards: Array[String] = []
	var missing: Array[String] = []
	var invalid_lines: Array[String] = []

	for raw_line_variant in import_lines:
		var raw_line := str(raw_line_variant)
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("#") or line.begins_with("//"):
			continue

		var parsed: Dictionary = _parse_import_line(line)
		if not bool(parsed.get("ok", false)):
			invalid_lines.append(line)
			continue

		var quantity := int(parsed.get("quantity", 0))
		var import_id := str(parsed.get("card_id", ""))
		var normalized := _normalize_card_code(import_id)
		if not lookup.has(normalized):
			missing.append(import_id)
			continue

		var matched_def_id := str(lookup.get(normalized, ""))
		for i in range(quantity):
			output_cards.append(matched_def_id)

	if not invalid_lines.is_empty():
		return {"ok": false, "error": "Invalid import lines: %s" % ", ".join(invalid_lines)}

	var safe_name := _sanitize_file_name(deck_name)
	var output_path := "%s/%s.json" % [output_dir.trim_suffix("/"), safe_name]
	if not _write_json_array(output_path, output_cards):
		return {"ok": false, "error": "Failed to write deck file: %s." % output_path}

	return {
		"ok": true,
		"output_path": output_path,
		"card_count": output_cards.size(),
		"missing_cards": missing,
		"missing_count": missing.size(),
	}

func parse_args(args: Array, default_import_path: String, default_output_dir: String) -> Dictionary:
	var deck_name := ""
	var source_path := default_import_path
	var output_dir := default_output_dir

	var index := 0
	while index < args.size():
		var arg := str(args[index])
		match arg:
			"--name":
				index += 1
				if index >= args.size():
					return {"ok": false, "error": "Missing value for --name"}
				deck_name = str(args[index])
			"--source":
				index += 1
				if index >= args.size():
					return {"ok": false, "error": "Missing value for --source"}
				source_path = str(args[index])
			"--output-dir":
				index += 1
				if index >= args.size():
					return {"ok": false, "error": "Missing value for --output-dir"}
				output_dir = str(args[index])
			_:
				if deck_name == "":
					deck_name = arg
				elif source_path == default_import_path:
					source_path = arg
				else:
					return {"ok": false, "error": "Unexpected argument: %s" % arg}
		index += 1

	if deck_name == "":
		return {"ok": false, "error": "Deck name is required."}

	return {
		"ok": true,
		"deck_name": deck_name,
		"source_path": source_path,
		"output_dir": output_dir,
	}

func _parse_import_line(line: String) -> Dictionary:
	var compact := line.replace(" ", "").replace("\t", "")
	var separator_index: int = compact.find("x")
	if separator_index < 0:
		separator_index = compact.find("X")
	if separator_index <= 0:
		return {"ok": false}

	var quantity_text := compact.substr(0, separator_index)
	var card_id := compact.substr(separator_index + 1)
	if quantity_text.is_empty() or card_id.is_empty() or not quantity_text.is_valid_int():
		return {"ok": false}

	var quantity := int(quantity_text)
	if quantity <= 0:
		return {"ok": false}

	return {"ok": true, "quantity": quantity, "card_id": card_id}

func _build_card_lookup(base_cards: Array) -> Dictionary:
	var lookup := {}
	for item_variant in base_cards:
		var item: Dictionary = item_variant
		var def_id := str(item.get("id", ""))
		var number := str(item.get("number", ""))
		if def_id != "":
			lookup[_normalize_card_code(def_id)] = def_id
		if number != "":
			lookup[_normalize_card_code(number)] = def_id
	return lookup

func _normalize_card_code(value: String) -> String:
	var result := ""
	for ch in value.to_upper():
		var code := ch.unicode_at(0)
		var is_digit := code >= 48 and code <= 57
		var is_upper := code >= 65 and code <= 90
		if is_digit or is_upper:
			result += ch
	return result

func _sanitize_file_name(value: String) -> String:
	var name := value.strip_edges()
	for invalid_char in ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]:
		name = name.replace(invalid_char, "_")
	name = name.replace(" ", "_")
	if name.is_empty():
		return "imported_deck"
	return name

func _read_lines(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	return file.get_as_text().split("\n")

func _write_json_array(path: String, data: Array[String]) -> bool:
	var absolute_dir := ProjectSettings.globalize_path(path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.store_string("\n")
	return true
