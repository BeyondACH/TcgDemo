extends SceneTree

const DeckImporter = preload("res://docs/deck_importer.gd")

func _init() -> void:
	var temp_dir := "user://deck_import_test"
	var import_path := "%s/import.txt" % temp_dir
	var output_dir := "%s/out" % temp_dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(temp_dir))

	var file := FileAccess.open(import_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to create temp import file.")
		quit(1)
		return

	file.store_string("2xUA_CHAR_BASIC\n")
	file.store_string("3xTST-1-002\n")
	file.store_string("5xUA_DOES_NOT_EXIST\n")
	file.store_string("1xUA_EVENT_DRAW\n")
	file.store_string("4xTST-2-001\n")
	file.close()

	var importer = DeckImporter.new()
	var result := importer.import_deck("smoke_deck", import_path, output_dir)
	if not bool(result.get("ok", false)):
		push_error("Import failed: %s" % result.get("error", "unknown"))
		quit(1)
		return

	if int(result.get("missing_count", 0)) != 1:
		push_error("Expected 1 missing card entry, got %d." % int(result.get("missing_count", 0)))
		quit(1)
		return

	var output_path := str(result.get("output_path", ""))
	var output_file := FileAccess.open(output_path, FileAccess.READ)
	if output_file == null:
		push_error("Output deck file not found: %s" % output_path)
		quit(1)
		return

	var parsed = JSON.parse_string(output_file.get_as_text())
	if not (parsed is Array):
		push_error("Output deck file is not a JSON array.")
		quit(1)
		return

	var cards: Array = parsed
	if cards.size() != 10:
		push_error("Expected 10 cards, got %d." % cards.size())
		quit(1)
		return

	if cards.count("UA_CHAR_BASIC") != 2:
		push_error("Expected 2 UA_CHAR_BASIC cards.")
		quit(1)
		return

	if cards.count("UA_FIELD_BASIC") != 3:
		push_error("Expected 3 UA_FIELD_BASIC cards.")
		quit(1)
		return

	if cards.count("UA_EVENT_DRAW") != 1:
		push_error("Expected 1 UA_EVENT_DRAW card.")
		quit(1)
		return

	if cards.count("UA_CHAR_HEAVY") != 4:
		push_error("Expected 4 UA_CHAR_HEAVY cards.")
		quit(1)
		return

	print("[PASS] deck import smoke test")
	quit(0)
