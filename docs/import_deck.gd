extends SceneTree

const DEFAULT_IMPORT_PATH := "res://import.txt"
const DEFAULT_OUTPUT_DIR := "res://data/decks"
const DeckImporter = preload("res://docs/deck_importer.gd")

func _init() -> void:
	var importer := DeckImporter.new()
	var options := importer.parse_args(OS.get_cmdline_user_args(), DEFAULT_IMPORT_PATH, DEFAULT_OUTPUT_DIR)
	if not bool(options.get("ok", false)):
		push_error(str(options.get("error", "unknown error")))
		_print_usage()
		quit(1)
		return

	var result := importer.import_deck(
		str(options.get("deck_name", "")),
		str(options.get("source_path", DEFAULT_IMPORT_PATH)),
		str(options.get("output_dir", DEFAULT_OUTPUT_DIR))
	)
	if not bool(result.get("ok", false)):
		push_error(str(result.get("error", "import failed")))
		quit(1)
		return

	print("Deck imported: %s" % result.get("output_path", ""))
	print("Matched cards: %d" % int(result.get("card_count", 0)))
	if int(result.get("missing_count", 0)) > 0:
		print("Skipped missing cards: %s" % ", ".join(result.get("missing_cards", [])))
	if int(result.get("card_count", 0)) != 50:
		print("Warning: deck size is %d, expected 50." % int(result.get("card_count", 0)))
	quit(0)

func _print_usage() -> void:
	print("Usage:")
	print("  godot --headless --path <project> --script res://docs/import_deck.gd -- --name <deck_name> [--source <path>] [--output-dir <path>]")
	print("Defaults:")
	print("  source: %s" % DEFAULT_IMPORT_PATH)
	print("  output-dir: %s" % DEFAULT_OUTPUT_DIR)
