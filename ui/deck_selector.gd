extends RefCounted
class_name DeckSelector

## 卡组选择管理 — Phase 2 Task 2.3
## 从 battle_scene.gd 提取

const UATypes = preload("res://core/ua_types.gd")

var available_decks: Array[Dictionary] = []
var opening_setup_pending := true
var _picker_p1: OptionButton
var _picker_p2: OptionButton
var _modal: Control
var _start_button: Button
var _game_manager: GameManager

func _init(game_manager: GameManager, picker_p1: OptionButton, picker_p2: OptionButton, modal: Control, start_button: Button) -> void:
	_game_manager = game_manager
	_picker_p1 = picker_p1
	_picker_p2 = picker_p2
	_modal = modal
	_start_button = start_button

func load_options() -> void:
	available_decks = _game_manager.get_available_decks()
	_picker_p1.clear()
	_picker_p2.clear()
	for deck in available_decks:
		var deck_name := str(deck.get("name", ""))
		_picker_p1.add_item(deck_name)
		_picker_p2.add_item(deck_name)
	if available_decks.is_empty():
		_picker_p1.add_item("(no decks available)")
		_picker_p2.add_item("(no decks available)")
		return
	_picker_p1.select(_preferred_index("starter_a", 0))
	_picker_p2.select(_preferred_index("starter_b", min(1, available_decks.size() - 1)))

func _preferred_index(preferred_name: String, fallback_index: int) -> int:
	for i in range(available_decks.size()):
		if str(available_decks[i].get("file_name", "")).get_basename() == preferred_name:
			return i
	return clampi(fallback_index, 0, max(0, available_decks.size() - 1))

func show_modal() -> void:
	opening_setup_pending = true
	if _modal != null:
		_modal.show()
	refresh_state()

func hide_modal() -> void:
	if _modal != null:
		_modal.hide()

func refresh_state() -> void:
	if _picker_p1 == null or _picker_p2 == null:
		return
	if not opening_setup_pending:
		hide_modal()
		return
	var can_start := opening_setup_pending and not available_decks.is_empty() and _picker_p1.selected >= 0 and _picker_p2.selected >= 0
	_picker_p1.disabled = not opening_setup_pending or available_decks.is_empty()
	_picker_p2.disabled = not opening_setup_pending or available_decks.is_empty()
	if _start_button != null:
		_start_button.disabled = not can_start
		if not opening_setup_pending:
			_start_button.text = "已开始"
		elif available_decks.is_empty():
			_start_button.text = "无可用卡组"
		else:
			_start_button.text = "开始游戏"

func start_game() -> void:
	if _game_manager == null:
		return
	var path_p1 := _deck_path(_picker_p1)
	var path_p2 := _deck_path(_picker_p2)
	if path_p1 == "" or path_p2 == "":
		return
	opening_setup_pending = false
	hide_modal()
	_game_manager.setup_game({"player_decks": {UATypes.PLAYER_ONE: path_p1, UATypes.PLAYER_TWO: path_p2}})

func _deck_path(picker: OptionButton) -> String:
	if picker == null:
		return ""
	var index := picker.selected
	if index < 0 or index >= available_decks.size():
		return ""
	return str(available_decks[index].get("path", ""))
