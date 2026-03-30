extends RefCounted
class_name BoardTargetSelectionHelper

static func current_pending_decision(snapshot: Dictionary, selected_pending_decision_index: int = -1) -> Dictionary:
	var pending: Array = snapshot.get("pending_decisions", [])
	if pending.is_empty():
		return {}
	var decision_index := selected_pending_decision_index
	if decision_index < 0 or decision_index >= pending.size():
		decision_index = 0
	return pending[decision_index]

static func find_board_target_info(snapshot: Dictionary, card_uid: String) -> Dictionary:
	if card_uid == "":
		return {}
	var players: Dictionary = snapshot.get("players", {})
	for player_id_variant in players.keys():
		var player_id := str(player_id_variant)
		var player_data: Dictionary = players.get(player_id_variant, {})
		for zone_name in ["front_line", "energy_line"]:
			for card_variant in player_data.get(zone_name, []):
				var card_data: Dictionary = card_variant
				if str(card_data.get("uid", "")) == card_uid:
					return {
						"uid": card_uid,
						"player_id": player_id,
						"zone": zone_name,
					}
	return {}

static func board_target_uid_set(snapshot: Dictionary, decision: Dictionary) -> Dictionary:
	var result := {}
	if decision.is_empty():
		return result
	for target_uid_variant in decision.get("board_target_uids", []):
		var target_uid := str(target_uid_variant)
		if target_uid != "":
			result[target_uid] = true
	if not result.is_empty():
		return result
	for choice_variant in decision.get("choices", []):
		var choice: Dictionary = choice_variant
		var target_uid := str(choice.get("value", ""))
		if find_board_target_info(snapshot, target_uid).is_empty():
			continue
		result[target_uid] = true
	return result

static func resolve_pending_click(game_manager, snapshot: Dictionary, opening_setup_pending: bool, player_id: String, card_uid: String, zone_name: String, selected_pending_decision_index: int = -1) -> bool:
	if game_manager == null or opening_setup_pending or not bool(snapshot.get("human_input_enabled", true)):
		return false
	var decision := current_pending_decision(snapshot, selected_pending_decision_index)
	if decision.is_empty():
		return false
	if str(decision.get("type", "")) != "ABILITY_TARGET_SELECTION":
		return false
	if str(decision.get("ui_mode", "")) == "PREVIEW_PICK" or str(decision.get("ui_mode", "")) == "PREVIEW_REORDER":
		return false
	var selectable_uids := board_target_uid_set(snapshot, decision)
	if selectable_uids.is_empty():
		return false
	if not selectable_uids.has(card_uid):
		return false
	var target_meta := find_board_target_info(snapshot, card_uid)
	if target_meta.is_empty():
		return false
	if str(target_meta.get("player_id", "")) != player_id:
		return false
	if str(target_meta.get("zone", "")) != zone_name:
		return false
	game_manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"source_card_uid": str(decision.get("source_card_uid", "")),
		"resolution_id": str(decision.get("resolution_id", "")),
		"choice": card_uid,
	})
	return true
