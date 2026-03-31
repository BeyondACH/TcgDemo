extends RefCounted
class_name SnapshotSerializer

const UATypes = preload("res://core/ua_types.gd")
const GameState = preload("res://data/game_state.gd")
const PlayerState = preload("res://data/player_state.gd")
const CardInstance = preload("res://data/card_instance.gd")
const CardDef = preload("res://data/card_def.gd")

var _rules_engine  # Reference for action availability and energy pool
var _game_manager  # Reference for controller type queries and helper methods

func _init(p_rules_engine, p_game_manager) -> void:
	_rules_engine = p_rules_engine
	_game_manager = p_game_manager

# Public API - main entry point
func get_snapshot(state: GameState, action_player_id: String, display_hand_player_id: String, legal_actions: Array[Dictionary]) -> Dictionary:
	return {
		"turn_number": state.turn_number,
		"active_player_id": state.active_player_id,
		"priority_player_id": action_player_id,
		"display_hand_player_id": display_hand_player_id,
		"phase": UATypes.phase_to_text(state.phase),
		"opening_complete": state.opening_complete,
		"can_bonus_draw": _game_manager._can_active_player_bonus_draw(),
		"winner_player_id": state.winner_player_id,
		"battle_context": state.battle_context.duplicate(true),
		"last_battle_result": state.last_battle_result.duplicate(true),
		"effect_queue_count": state.effect_queue.size(),
		"pending_decisions": serialize_pending_decisions(state, action_player_id),
		"pending_life_triggers": state.pending_life_triggers.duplicate(true),
		"life_reveal_modal": serialize_life_reveal_modal(state, action_player_id),
		"controller_types": {
			UATypes.PLAYER_ONE: _game_manager.get_controller_type(UATypes.PLAYER_ONE),
			UATypes.PLAYER_TWO: _game_manager.get_controller_type(UATypes.PLAYER_TWO),
		},
		"action_player_controller": _game_manager.get_controller_type(action_player_id),
		"human_input_enabled": _game_manager.get_controller_type(action_player_id) == "HUMAN",
		"legal_actions": legal_actions.duplicate(true),
		"players": {
			UATypes.PLAYER_ONE: serialize_player(state, UATypes.PLAYER_ONE, action_player_id),
			UATypes.PLAYER_TWO: serialize_player(state, UATypes.PLAYER_TWO, action_player_id)
		},
		"logs": state.logs.duplicate(),
	}

# Serialization methods
func serialize_player(state: GameState, player_id: String, action_player_id: String) -> Dictionary:
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return {}
	return {
		"player_id": player.player_id,
		"controller_type": _game_manager.get_controller_type(player_id),
		"deck_count": player.deck.size(),
		"hand_count": player.hand.size(),
		"life_count": player.life.size(),
		"ap_total": player.ap_total(),
		"ap_active": player.ap_active_count(),
		"used_bonus_draw": player.used_bonus_draw,
		"available_energy": _rules_engine.get_energy_pool_for_player(state, player),
		"hand": serialize_cards(state, player.hand, action_player_id),
		"life": serialize_life_cards(player.life),
		"front_line": serialize_cards(state, player.front_line, action_player_id),
		"energy_line": serialize_cards(state, player.energy_line, action_player_id),
		"outside": serialize_cards(state, player.outside, action_player_id),
		"removed": serialize_cards(state, player.removed, action_player_id),
		"outside_count": player.outside.size(),
		"removed_count": player.removed.size(),
	}

func serialize_card(state: GameState, card_uid: String, action_player_id: String, include_actions: bool) -> Dictionary:
	var card: CardInstance = state.get_card(card_uid)
	var card_def: CardDef = null
	if card != null:
		card_def = state.get_card_def(card.def_id)
	if card == null or card_def == null:
		return {}
	var serialized := {
		"uid": card.uid,
		"name": card_def.name,
		"card_type": UATypes.card_type_to_text(card_def.card_type),
		"number": card_def.number,
		"source_image": card_def.source_image,
		"zone": UATypes.zone_to_key(card.zone),
		"state": UATypes.state_to_text(card.state),
		"base_bp": card_def.bp,
		"bp": card.current_bp,
		"cost_ap": card_def.cost_ap,
		"cost_energy": card_def.cost_energy.duplicate(true),
		"energy_provided": card_def.energy_provided.duplicate(true),
		"keywords": _runtime_keywords_for(card, card_def),
		"special_play_rule": card_def.special_play_rule.duplicate(true),
		"stacked_under": card.stacked_under.duplicate(),
		"flags": card.flags.duplicate(true),
	}
	if include_actions:
		serialized["available_actions"] = _rules_engine.get_card_available_actions(state, action_player_id, card.uid)
	return serialized

func serialize_pending_decisions(state: GameState, action_player_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for pending_variant in state.pending_decisions:
		var pending: Dictionary = (pending_variant as Dictionary).duplicate(true)
		var preview_card_uids: Array = pending.get("preview_card_uids", [])
		if not preview_card_uids.is_empty():
			pending["preview_cards"] = _serialize_card_list_for_ui(state, preview_card_uids, action_player_id)
		if str(pending.get("type", "")) == "ABILITY_TARGET_SELECTION":
			var board_targets: Array[Dictionary] = []
			var board_target_uids: Array[String] = []
			for choice_variant in pending.get("choices", []):
				var choice: Dictionary = choice_variant
				var card_uid := str(choice.get("value", ""))
				if card_uid == "":
					continue
				var card: CardInstance = state.get_card(card_uid)
				if card == null:
					continue
				if card.zone != UATypes.Zone.FRONT_LINE and card.zone != UATypes.Zone.ENERGY_LINE:
					continue
				board_target_uids.append(card_uid)
				board_targets.append({
					"uid": card_uid,
					"player_id": card.controller_player_id,
					"zone": UATypes.zone_to_key(card.zone),
				})
			pending["ui_allows_board_selection"] = not board_targets.is_empty()
			pending["board_target_uids"] = board_target_uids
			pending["board_targets"] = board_targets
		result.append(pending)
	return result

func serialize_cards(state: GameState, card_uids: Array[String], action_player_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for card_uid in card_uids:
		var serialized := serialize_card(state, card_uid, action_player_id, true)
		if not serialized.is_empty():
			result.append(serialized)
	return result

func serialize_life_cards(card_uids: Array[String]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in range(card_uids.size()):
		result.append({
			"uid": str(card_uids[i]),
			"zone": "life",
			"is_face_down": true,
			"index": i,
		})
	return result

func serialize_life_reveal_modal(state: GameState, action_player_id: String) -> Dictionary:
	if state.pending_life_reveal.is_empty():
		return {
			"visible": false,
			"player_id": "",
			"current_card_uid": "",
			"revealed_cards": [],
			"can_activate": false,
			"can_skip": false,
			"can_acknowledge": false,
			"awaiting_player_confirmation": false,
			"ai_resolves_after_confirmation": false,
			"waiting_for_ai_resolution": false,
		}
	var reveal: Dictionary = state.pending_life_reveal
	var current_card_uid := str(reveal.get("current_card_uid", ""))
	var result_cards: Array[Dictionary] = []
	var current_view_confirmed := false
	for entry_variant in reveal.get("revealed_cards", []):
		var entry: Dictionary = entry_variant
		var card_uid := str(entry.get("card_uid", ""))
		var serialized := serialize_card(state, card_uid, action_player_id, false)
		if serialized.is_empty():
			continue
		serialized["has_life_trigger"] = bool(entry.get("has_life_trigger", false))
		serialized["view_confirmed"] = bool(entry.get("view_confirmed", false))
		serialized["resolved"] = bool(entry.get("resolved", false))
		serialized["order_index"] = int(entry.get("order_index", result_cards.size()))
		serialized["is_current"] = card_uid == current_card_uid
		if card_uid == current_card_uid:
			current_view_confirmed = bool(entry.get("view_confirmed", false))
		result_cards.append(serialized)
	var current_has_trigger := false
	for card_data_variant in result_cards:
		var card_data: Dictionary = card_data_variant
		if str(card_data.get("uid", "")) != current_card_uid:
			continue
		current_has_trigger = bool(card_data.get("has_life_trigger", false))
		break
	var reveal_player_id := str(reveal.get("player_id", ""))
	var reveal_controller_is_human: bool = _game_manager.controller_manager.is_human(reveal_player_id)
	var awaiting_player_confirmation: bool = current_card_uid != "" and _game_manager.life_reveal_requires_view_confirmation(current_card_uid)
	var ai_resolves_after_confirmation: bool = current_card_uid != "" and current_has_trigger and not reveal_controller_is_human
	var waiting_for_ai_resolution: bool = current_card_uid != "" and current_has_trigger and ai_resolves_after_confirmation and current_view_confirmed
	return {
		"visible": true,
		"player_id": reveal_player_id,
		"current_card_uid": current_card_uid,
		"revealed_cards": result_cards,
		"can_activate": current_card_uid != "" and current_has_trigger and reveal_controller_is_human,
		"can_skip": current_card_uid != "" and current_has_trigger and reveal_controller_is_human,
		"can_acknowledge": current_card_uid != "" and (not current_has_trigger or awaiting_player_confirmation),
		"awaiting_player_confirmation": awaiting_player_confirmation,
		"ai_resolves_after_confirmation": ai_resolves_after_confirmation,
		"waiting_for_ai_resolution": waiting_for_ai_resolution,
	}

# Private helpers
func _runtime_keywords_for(card: CardInstance, card_def: CardDef) -> Array:
	var keywords: Array = card_def.keywords.duplicate()
	for value in card.flags.get("temp_keywords", []):
		var keyword := str(value)
		if keyword != "" and not keywords.has(keyword):
			keywords.append(keyword)
	return keywords

func _serialize_card_list_for_ui(state: GameState, card_uids: Array, action_player_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for card_uid_variant in card_uids:
		var serialized := serialize_card(state, str(card_uid_variant), action_player_id, false)
		if not serialized.is_empty():
			result.append(serialized)
	return result
