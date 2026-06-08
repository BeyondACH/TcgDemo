extends RefCounted
class_name HandController

## 手牌控制器 — 从 BattleScene 提取
## 管理：手牌选中/悬停、出牌（前线/能量线/事件）、RAID 逻辑、手牌可打出状态

# ── 状态（外部可读） ──
var selected_hand_card_uid := ""
var raid_source_card_uid := ""
var raid_target_selection_mode := false

# ── 引用 ──
var _game_manager: Node
var _hand_view: HandView
var _selected_card_label: Label

# ── 提供者 ──
var _snapshot_provider: Callable
var _has_pending_gate_provider: Callable
var _human_input_provider: Callable
var _display_hand_player_id_provider: Callable
var _find_board_card_provider: Callable

# ── 回调 ──
var _action_buttons_callback: Callable
var _preview_card_callback: Callable


func setup(gm: Node,
		   hand_view: HandView,
		   selected_card_label: Label) -> void:
	_game_manager = gm
	_hand_view = hand_view
	_selected_card_label = selected_card_label


func set_snapshot_provider(provider: Callable) -> void:
	_snapshot_provider = provider


func set_has_pending_gate_provider(provider: Callable) -> void:
	_has_pending_gate_provider = provider


func set_human_input_provider(provider: Callable) -> void:
	_human_input_provider = provider


func set_display_hand_player_id_provider(provider: Callable) -> void:
	_display_hand_player_id_provider = provider


func set_find_board_card_provider(provider: Callable) -> void:
	_find_board_card_provider = provider


func set_action_buttons_callback(cb: Callable) -> void:
	_action_buttons_callback = cb


func set_preview_card_callback(cb: Callable) -> void:
	_preview_card_callback = cb


func _snapshot() -> Dictionary:
	if _snapshot_provider.is_valid():
		return _snapshot_provider.call()
	return {}


func _has_pending_gate() -> bool:
	if _has_pending_gate_provider.is_valid():
		return _has_pending_gate_provider.call()
	return false


func _human_input_enabled() -> bool:
	if _human_input_provider.is_valid():
		return _human_input_provider.call()
	return true


func _display_hand_player_id() -> String:
	if _display_hand_player_id_provider.is_valid():
		return _display_hand_player_id_provider.call()
	return ""


func _find_board_card(player_id: String, card_uid: String) -> Dictionary:
	if _find_board_card_provider.is_valid():
		return _find_board_card_provider.call(player_id, card_uid)
	return {}


func _trigger_action_buttons() -> void:
	if _action_buttons_callback.is_valid():
		_action_buttons_callback.call()


func _trigger_preview_card(card_data: Dictionary, context: Dictionary) -> void:
	if _preview_card_callback.is_valid():
		_preview_card_callback.call(card_data, context)


## ── 手牌选中 ──

func on_hand_card_selected(card_uid: String) -> void:
	selected_hand_card_uid = card_uid
	var display_hand_player_id := _display_hand_player_id()
	var card_data := find_hand_card(display_hand_player_id, card_uid)
	if not card_data.is_empty():
		_trigger_preview_card(card_data, {
			"relation_label": "己方",
			"zone_label": "手牌",
		})


func on_hand_card_hovered(card_uid: String, is_hovered: bool) -> void:
	if selected_hand_card_uid == "":
		return
	if not is_hovered and card_uid == selected_hand_card_uid:
		var display_hand_player_id := _display_hand_player_id()
		var card_data := find_hand_card(display_hand_player_id, selected_hand_card_uid)
		if not card_data.is_empty():
			_trigger_preview_card(card_data, {
				"relation_label": "己方",
				"zone_label": "手牌",
			})


## ── 出牌 ──

func on_play_front_pressed() -> void:
	if selected_hand_card_uid != "":
		_game_manager.play_card(selected_hand_card_uid, UATypes.Zone.FRONT_LINE)


func on_play_energy_pressed() -> void:
	if selected_hand_card_uid != "":
		_game_manager.play_card(selected_hand_card_uid, UATypes.Zone.ENERGY_LINE)


func on_use_event_pressed() -> void:
	if selected_hand_card_uid != "":
		_game_manager.play_card(selected_hand_card_uid, UATypes.Zone.OUTSIDE)


func on_zone_drop_requested(player_id: String, zone_name: String, card_uid: String) -> void:
	var phase := str(_snapshot().get("phase", ""))
	if phase != "MAIN":
		return
	if player_id != str(_snapshot().get("active_player_id", "")):
		return
	if zone_name == "front_line":
		_game_manager.play_card(card_uid, UATypes.Zone.FRONT_LINE)
	elif zone_name == "energy_line":
		_game_manager.play_card(card_uid, UATypes.Zone.ENERGY_LINE)


## ── RAID ──

func on_raid_pressed() -> void:
	if selected_hand_card_uid == "":
		return
	raid_source_card_uid = selected_hand_card_uid
	raid_target_selection_mode = true
	_trigger_action_buttons()
	_selected_card_label.text = "Choose a RAID target on your field"


func execute_raid_play(target_uid: String) -> void:
	if raid_source_card_uid == "":
		return
	var active_player_id := str(_snapshot().get("active_player_id", UATypes.PLAYER_ONE))
	var target_data := _find_board_card(active_player_id, target_uid)
	var target_zone_name := str(target_data.get("zone", "front_line"))
	var target_zone := UATypes.Zone.FRONT_LINE if target_zone_name == "front_line" else UATypes.Zone.ENERGY_LINE
	_game_manager.play_card(raid_source_card_uid, target_zone, {"raid_target_uid": target_uid})
	clear_raid_selection()


func clear_raid_selection() -> void:
	raid_source_card_uid = ""
	raid_target_selection_mode = false


## ── 清除手牌选中状态 ──

func clear_selection() -> void:
	selected_hand_card_uid = ""
	clear_raid_selection()


## ── 数据查询 ──

func find_hand_card(player_id: String, card_uid: String) -> Dictionary:
	var snap := _snapshot()
	var players: Dictionary = snap.get("players", {})
	var player_data: Dictionary = players.get(player_id, {})
	for card_variant in player_data.get("hand", []):
		var card_data: Dictionary = card_variant
		if str(card_data.get("uid", "")) == card_uid:
			return card_data
	return {}


## ── 手牌可打出状态 ──

func update_hand_playable_states(hand_cards: Array) -> void:
	var phase := str(_snapshot().get("phase", ""))
	var playable_map := {}
	if phase != "MAIN" or not _human_input_enabled():
		_hand_view.set_playable_cards(playable_map)
		return
	for card_variant in hand_cards:
		var card_data: Dictionary = card_variant
		var card_uid := str(card_data.get("uid", ""))
		var available_actions: Array = card_data.get("available_actions", [])
		var is_playable := available_actions.has("PLAY_FRONT") or available_actions.has("PLAY_ENERGY") or available_actions.has("PLAY_EVENT") or available_actions.has("RAID")
		playable_map[card_uid] = is_playable
	_hand_view.set_playable_cards(playable_map)
