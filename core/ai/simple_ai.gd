extends RefCounted
class_name SimpleAI

const UATypes = preload("res://core/ua_types.gd")
const ActionTypes = preload("res://core/actions/action_types.gd")

func choose_action(_game_state, snapshot: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary:
	if legal_actions.is_empty():
		return {}
	var phase := str(snapshot.get("phase", ""))
	match phase:
		"DRAW":
			return _choose_draw_action(legal_actions)
		"MOVE":
			return _choose_move_action(legal_actions)
		"MAIN":
			return _choose_main_action(snapshot, legal_actions)
		"ATTACK":
			return _choose_attack_action(snapshot, legal_actions)
		"END":
			return _choose_end_action(legal_actions)
	return _fallback_action(legal_actions)

func choose_pending_decision(_game_state, _snapshot: Dictionary, pending: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary:
	if legal_actions.is_empty():
		return {}
	if pending.has("attacker_uid"):
		return _choose_block_action(legal_actions)
	var pending_type := str(pending.get("type", ""))
	match pending_type:
		"MULLIGAN_CHOICE":
			return _find_choice_action(legal_actions, "keep")
		"STEP_SWAP_CHOICE":
			return _choose_step_swap_action(legal_actions)
		"HAND_LIMIT_DISCARD":
			return _choose_hand_limit_discard(legal_actions)
		"RAID_ZONE_CHOICE":
			return _find_choice_action(legal_actions, UATypes.Zone.FRONT_LINE)
		"LIFE_TRIGGER_RAID_CHOICE":
			return _find_choice_action(legal_actions, "RAID_NOW", _find_choice_action(legal_actions, "ADD_TO_HAND"))
		"LIFE_TRIGGER_RAID_TARGET":
			return legal_actions[0]
		"ABILITY_TARGET_SELECTION":
			return legal_actions[0]
	return _fallback_action(legal_actions)

func _choose_draw_action(legal_actions: Array[Dictionary]) -> Dictionary:
	for action in legal_actions:
		if str(action.get("type", "")) == ActionTypes.ADVANCE_PHASE:
			return action
	return _fallback_action(legal_actions)

func _choose_move_action(legal_actions: Array[Dictionary]) -> Dictionary:
	var best_move := {}
	var best_bp := -1
	for action in legal_actions:
		if str(action.get("type", "")) != ActionTypes.MOVE_CARD:
			continue
		var bp := int(action.get("params", {}).get("source_bp", 0))
		if bp > best_bp:
			best_bp = bp
			best_move = action
	if not best_move.is_empty():
		return best_move
	return _fallback_action(legal_actions)

func _choose_main_action(snapshot: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary:
	var best_character := {}
	var best_character_bp := -1
	var best_field := {}
	var best_event := {}
	var best_activate := {}
	for action in legal_actions:
		var action_type := str(action.get("type", ""))
		var params: Dictionary = action.get("params", {})
		if action_type == ActionTypes.PLAY_CARD:
			var card_type := str(params.get("card_type", ""))
			var bp := int(params.get("source_bp", 0))
			if card_type == "CHARACTER":
				if bp > best_character_bp:
					best_character_bp = bp
					best_character = action
			elif card_type == "FIELD" and best_field.is_empty():
				best_field = action
			elif card_type == "EVENT" and best_event.is_empty():
				best_event = action
		elif action_type == ActionTypes.ACTIVATE_EFFECT and best_activate.is_empty():
			best_activate = action
	if not best_character.is_empty():
		return best_character
	if not best_field.is_empty():
		return best_field
	if not best_event.is_empty():
		return best_event
	if not best_activate.is_empty():
		return best_activate
	return _fallback_action(legal_actions)

func _choose_attack_action(_snapshot: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary:
	var best_direct := {}
	var best_sniper := {}
	var best_sniper_margin := -999999
	for action in legal_actions:
		var action_type := str(action.get("type", ""))
		if action_type != ActionTypes.ATTACK:
			continue
		var params: Dictionary = action.get("params", {})
		var target_kind := str(params.get("target_kind", "PLAYER"))
		if target_kind == "PLAYER" and best_direct.is_empty():
			best_direct = action
		elif target_kind == "FRONT_CHARACTER":
			var margin := int(params.get("source_bp", 0)) - int(params.get("target_bp", 0))
			if margin > best_sniper_margin:
				best_sniper_margin = margin
				best_sniper = action
	if not best_direct.is_empty():
		return best_direct
	if not best_sniper.is_empty():
		return best_sniper
	return _fallback_action(legal_actions)

func _choose_end_action(legal_actions: Array[Dictionary]) -> Dictionary:
	for action in legal_actions:
		if str(action.get("type", "")) == ActionTypes.END_TURN:
			return action
	return _fallback_action(legal_actions)

func _choose_block_action(legal_actions: Array[Dictionary]) -> Dictionary:
	var best_block := {}
	var best_bp := -1
	for action in legal_actions:
		if str(action.get("type", "")) != ActionTypes.BLOCK:
			continue
		var bp := int(action.get("params", {}).get("source_bp", 0))
		if bp > best_bp:
			best_bp = bp
			best_block = action
	if not best_block.is_empty():
		return best_block
	return _fallback_action(legal_actions)

func _choose_step_swap_action(legal_actions: Array[Dictionary]) -> Dictionary:
	var best_action := {}
	var best_bp := 999999
	for action in legal_actions:
		var params: Dictionary = action.get("params", {})
		var bp := int(params.get("choice_bp", 0))
		if bp < best_bp:
			best_bp = bp
			best_action = action
	if not best_action.is_empty():
		return best_action
	return _fallback_action(legal_actions)

func _choose_hand_limit_discard(legal_actions: Array[Dictionary]) -> Dictionary:
	var best_action := {}
	var best_bp := -1
	for action in legal_actions:
		var params: Dictionary = action.get("params", {})
		var bp := int(params.get("choice_bp", -1))
		if bp > best_bp:
			best_bp = bp
			best_action = action
	if not best_action.is_empty():
		return best_action
	return _fallback_action(legal_actions)

func _find_choice_action(legal_actions: Array[Dictionary], wanted_value, fallback_action := {}) -> Dictionary:
	for action in legal_actions:
		if action.get("params", {}).get("choice", null) == wanted_value:
			return action
	return fallback_action if not fallback_action.is_empty() else _fallback_action(legal_actions)

func _fallback_action(legal_actions: Array[Dictionary]) -> Dictionary:
	for type_name in [ActionTypes.NO_BLOCK, ActionTypes.ADVANCE_PHASE, ActionTypes.END_TURN]:
		for action in legal_actions:
			if str(action.get("type", "")) == type_name:
				return action
	return legal_actions[0]
