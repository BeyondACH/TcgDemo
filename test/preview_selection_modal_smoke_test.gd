extends SceneTree

const PreviewSelectionModal = preload("res://ui/preview_selection_modal.gd")
const CardView = preload("res://ui/card_view.gd")

var _failures: Array[String] = []
var _received_submission: Array = []

func _init() -> void:
	_run_test("Preview modal card click selects and submits", _test_preview_pick_submission)
	_run_test("Preview modal reorder submits reordered cards", _test_preview_reorder_submission)
	if _failures.is_empty():
		print("PREVIEW_SELECTION_MODAL_SMOKE_OK")
	quit(0 if _failures.is_empty() else 1)

func _run_test(name: String, callable: Callable) -> void:
	var result = callable.call()
	if bool(result.get("ok", false)):
		print("[PASS] %s" % name)
		return
	var error := str(result.get("error", "unknown"))
	_failures.append("%s: %s" % [name, error])
	push_error("[FAIL] %s: %s" % [name, error])

func _ok() -> Dictionary:
	return {"ok": true}

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}

func _test_preview_pick_submission() -> Dictionary:
	var modal := _new_modal()
	_received_submission = []
	modal.submitted.connect(_on_modal_submitted)
	modal.show_decision({
		"ui_mode": "PREVIEW_PICK",
		"title": "查看牌堆顶",
		"preview_cards": [
			{"uid": "CARD_A", "name": "Card A", "number": "A-001", "cost_energy": {}},
			{"uid": "CARD_B", "name": "Card B", "number": "B-001", "cost_energy": {}},
		],
		"choices": [
			{"label": "Card A", "value": "CARD_A"},
			{"label": "Card B", "value": "CARD_B"},
		],
		"min": 1,
		"max": 1,
	})
	var card_view := _first_card_view(modal)
	if card_view == null:
		return _fail("Expected preview modal to create at least one CardView.")
	card_view.card_pressed.emit("", "CARD_A", "preview")
	if modal._confirm_button.disabled:
		return _fail("Confirm button should become enabled after selecting a legal preview card.")
	modal._on_confirm_pressed()
	if _received_submission != ["CARD_A"]:
		return _fail("Preview pick should submit the selected card uid.")
	return _ok()

func _test_preview_reorder_submission() -> Dictionary:
	var modal := _new_modal()
	_received_submission = []
	modal.submitted.connect(_on_modal_submitted)
	modal.show_decision({
		"ui_mode": "PREVIEW_REORDER",
		"title": "调整剩余卡牌顺序",
		"preview_cards": [
			{"uid": "CARD_A", "name": "Card A", "number": "A-001", "cost_energy": {}},
			{"uid": "CARD_B", "name": "Card B", "number": "B-001", "cost_energy": {}},
			{"uid": "CARD_C", "name": "Card C", "number": "C-001", "cost_energy": {}},
		],
		"choices": [],
		"min": 0,
		"max": 3,
	})
	modal._on_move_right_pressed("CARD_A")
	modal._on_confirm_pressed()
	if _received_submission != ["CARD_B", "CARD_A", "CARD_C"]:
		return _fail("Preview reorder should submit the updated order.")
	return _ok()

func _on_modal_submitted(selected_values: Array) -> void:
	_received_submission = selected_values.duplicate()

func _new_modal() -> PreviewSelectionModal:
	var root := Window.new()
	root.title = "test"
	root.visible = false
	get_root().add_child(root)
	var modal := PreviewSelectionModal.new()
	root.add_child(modal)
	modal._ready()
	return modal

func _first_card_view(modal: PreviewSelectionModal) -> CardView:
	for child in modal._cards_row.get_children():
		if child.get_child_count() == 0:
			continue
		var tile_margin := child.get_child(0)
		if tile_margin.get_child_count() == 0:
			continue
		var tile_column := tile_margin.get_child(0)
		if tile_column.get_child_count() == 0:
			continue
		var card_view := tile_column.get_child(0) as CardView
		if card_view != null:
			return card_view
	return null
