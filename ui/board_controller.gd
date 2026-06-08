extends RefCounted
class_name BoardController

## 战场控制器 — 从 BattleScene 提取
## 管理：战场目标选择、目标装饰、战场数据查询

const BoardTargetSelectionHelper = preload("res://ui/board_target_selection_helper.gd")

var _snapshot_provider: Callable
var _opponent_board
var _player_board
var _zone_cards_popup
var _game_manager: Node
var _selected_pending_decision_index_provider: Callable


func setup(gm: Node, opponent_board, player_board, zone_popup) -> void:
	_game_manager = gm
	_opponent_board = opponent_board
	_player_board = player_board
	_zone_cards_popup = zone_popup


func set_snapshot_provider(provider: Callable) -> void:
	_snapshot_provider = provider


func set_pending_decision_index_provider(provider: Callable) -> void:
	_selected_pending_decision_index_provider = provider


func _snapshot() -> Dictionary:
	if _snapshot_provider.is_valid():
		return _snapshot_provider.call()
	return {}


func _pending_index() -> int:
	if _selected_pending_decision_index_provider.is_valid():
		return _selected_pending_decision_index_provider.call()
	return -1


## ── 战场目标选择 ──

func current_board_target_selection() -> Dictionary:
	return BoardTargetSelectionHelper.current_pending_decision(_snapshot(), _pending_index())


func is_board_target_selection_pending() -> bool:
	var decision := current_board_target_selection()
	if decision.is_empty():
		return false
	return _is_board_target_selection(decision)


func _is_board_target_selection(decision: Dictionary) -> bool:
	if str(decision.get("type", "")) != "ABILITY_TARGET_SELECTION":
		return false
	var targets: Array = decision.get("board_targets", [])
	if not targets.is_empty():
		return true
	for choice in decision.get("choices", []):
		var c: Dictionary = choice
		if str(c.get("source", "")) == "board":
			return true
	return false


func current_board_target_uid_set() -> Dictionary:
	var decision := current_board_target_selection()
	if decision.is_empty():
		return {}
	return _current_board_target_uid_set_for(decision)


func _current_board_target_uid_set_for(decision: Dictionary) -> Dictionary:
	var result := {}
	var board_targets: Array = decision.get("board_targets", [])
	for entry in board_targets:
		var e: Dictionary = entry
		result[str(e.get("uid", ""))] = true
	if result.is_empty():
		for choice in decision.get("choices", []):
			var c: Dictionary = choice
			if str(c.get("source", "")) == "board":
				result[str(c.get("value", ""))] = true
	return result


func board_target_meta_for(card_uid: String) -> Dictionary:
	var decision := current_board_target_selection()
	if decision.is_empty():
		return _find_board_target_info(card_uid)
	var board_targets: Array = decision.get("board_targets", [])
	for entry in board_targets:
		var e: Dictionary = entry
		if str(e.get("uid", "")) == card_uid:
			return {"player_id": str(e.get("player_id", "")), "zone": str(e.get("zone", ""))}
	return _find_board_target_info(card_uid)


## ── 战场目标装饰 ──

func decorate_board_targets(player_id: String, data: Dictionary) -> Dictionary:
	var decorated := data.duplicate(true)
	var uid_set := current_board_target_uid_set()
	if uid_set.is_empty():
		return decorated
	var zone_names := ["front_line", "energy_line"]
	for zone_name in zone_names:
		var cards: Array = decorated.get(zone_name, [])
		var new_cards: Array = []
		for card_variant in cards:
			var card_data: Dictionary = card_variant.duplicate(true)
			card_data["pending_target_selectable"] = uid_set.has(str(card_data.get("uid", "")))
			new_cards.append(card_data)
		decorated[zone_name] = new_cards
	return decorated


## ── 战场数据查询 ──

func find_board_card(player_id: String, card_uid: String) -> Dictionary:
	var snap := _snapshot()
	var players: Dictionary = snap.get("players", {})
	var player_data: Dictionary = players.get(player_id, {})
	for zone_name in ["front_line", "energy_line"]:
		for card in player_data.get(zone_name, []):
			if str(card.get("uid", "")) == card_uid:
				return card
	return {}


func find_zone_cards(player_id: String, zone_name: String) -> Array:
	var snap := _snapshot()
	var players: Dictionary = snap.get("players", {})
	var player_data: Dictionary = players.get(player_id, {})
	var cards_variant = player_data.get(zone_name, [])
	if cards_variant is Array:
		var cards: Array = []
		for card_variant in cards_variant:
			var card_data: Dictionary = (card_variant as Dictionary).duplicate(true)
			card_data["owner_player_id"] = player_id
			cards.append(card_data)
		return cards
	return []


func resolve_board_target_selection_from_card(card_uid: String, player_id: String, zone_name: String) -> void:
	var snap := _snapshot()
	var opening_setup := false  # P1 is never in opening during gameplay
	BoardTargetSelectionHelper.resolve_pending_click(_game_manager, snap, opening_setup, player_id, card_uid, zone_name, _pending_index())


## ── Zone Stack Popup ──

func show_zone_stack_popup(player_id: String, zone_name: String) -> void:
	var cards := find_zone_cards(player_id, zone_name)
	var snap := _snapshot()
	var active_player_id := str(snap.get("active_player_id", "P1"))
	var relation_label := "己方" if player_id == active_player_id else "对手"
	var zone_label := "除外区" if zone_name == "removed" else "场外区"
	_zone_cards_popup.show_zone_cards("%s %s" % [relation_label, zone_label], cards)


## ── 辅助 ──

func _find_board_target_info(card_uid: String) -> Dictionary:
	var snap := _snapshot()
	var players: Dictionary = snap.get("players", {})
	for pid in players.keys():
		var player_data: Dictionary = players.get(pid, {})
		for zone_name in ["front_line", "energy_line"]:
			for card in player_data.get(zone_name, []):
				if str(card.get("uid", "")) == card_uid:
					return {"player_id": str(pid), "zone": zone_name}
	return {}


func should_allow_board_selection_passthrough() -> bool:
	return is_board_target_selection_pending()
