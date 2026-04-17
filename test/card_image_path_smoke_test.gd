extends SceneTree

const UATypes = preload("res://core/ua_types.gd")
const GameManager = preload("res://core/game_manager.gd")
const CardView = preload("res://ui/card_view.gd")
const CardPreviewPanel = preload("res://ui/card_preview_panel.gd")

var _failures: Array[String] = []

func _init() -> void:
	_run_test("Snapshot includes title_code for visible cards", _test_snapshot_includes_title_code)
	_run_test("CardView only resolves title_code image folders", _test_card_view_candidates)
	_run_test("CardPreviewPanel only resolves title_code image folders", _test_preview_panel_candidates)
	if _failures.is_empty():
		print("CARD_IMAGE_PATH_SMOKE_OK")
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

func _test_snapshot_includes_title_code() -> Dictionary:
	var manager := GameManager.new()
	manager.setup_game()
	manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})
	manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})
	var snapshot := manager.get_snapshot()
	var p1: Dictionary = snapshot.get("players", {}).get(UATypes.PLAYER_ONE, {})
	var hand: Array = p1.get("hand", [])
	if hand.is_empty():
		return _fail("Expected player one hand to contain visible cards.")
	var card_data: Dictionary = hand[0]
	if str(card_data.get("title_code", "")) == "":
		return _fail("Expected serialized visible card to include title_code.")
	return _ok()

func _test_card_view_candidates() -> Dictionary:
	var card_view := CardView.new()
	var candidates: Array[String] = card_view._card_image_candidates({
		"title_code": "MMM",
		"source_image": "UA31BT-MMM-1-001.png",
	}, false)
	var expected := [
		"res://pic/MMM/micro/UA31BT-MMM-1-001.png",
		"res://pic/MMM/UA31BT-MMM-1-001.png",
	]
	if candidates != expected:
		return _fail("Unexpected CardView candidates: %s" % str(candidates))
	var missing_code: Array[String] = card_view._card_image_candidates({
		"source_image": "UA31BT-MMM-1-001.png",
	}, false)
	if not missing_code.is_empty():
		return _fail("Expected missing title_code to produce no image candidates.")
	return _ok()

func _test_preview_panel_candidates() -> Dictionary:
	var panel := CardPreviewPanel.new()
	var candidates: Array[String] = panel._card_image_candidates({
		"title_code": "TLR",
		"source_image": "UA45BT-TLR-1-001.png",
	}, true)
	var expected := [
		"res://pic/TLR/UA45BT-TLR-1-001.png",
		"res://pic/TLR/micro/UA45BT-TLR-1-001.png",
	]
	if candidates != expected:
		return _fail("Unexpected CardPreviewPanel candidates: %s" % str(candidates))
	return _ok()
