extends RefCounted
class_name EffectResolver

const UATypes = preload("res://core/ua_types.gd")
const ZoneManager = preload("res://core/zone_manager.gd")
const VictoryChecker = preload("res://core/victory_checker.gd")
const GameState = preload("res://data/game_state.gd")

var zone_manager
var victory_checker

func _init(p_zone_manager, p_victory_checker) -> void:
	zone_manager = p_zone_manager
	victory_checker = p_victory_checker

func resolve_operations(state: GameState, source_card_uid: String, effect_list: Array, context: Dictionary = {}) -> Array[String]:
	var logs: Array[String] = []
	for effect in effect_list:
		logs.append_array(_execute_operation(state, source_card_uid, effect, context))
	return logs

func resolve_effect(state: GameState, source_card_uid: String, effect: Dictionary, context: Dictionary = {}) -> Array[String]:
	var logs: Array[String] = []
	if effect.has("steps"):
		logs.append_array(_execute_steps(state, source_card_uid, effect.get("steps", []), context.duplicate(true)))
		return logs
	var operations = effect.get("operations", effect.get("operation", []))
	if operations is Dictionary:
		operations = [operations]
	logs.append_array(resolve_operations(state, source_card_uid, operations, context))
	return logs

func resolve_trigger(source_card_uid: String, trigger_type: int, state: GameState, context: Dictionary = {}) -> Array[String]:
	var logs: Array[String] = []
	var source_card = state.get_card(source_card_uid)
	if source_card == null:
		return logs
	var card_def = state.get_card_def(source_card.def_id)
	if card_def == null:
		return logs
	var trigger_context := context.duplicate(true)
	trigger_context["source_player_id"] = source_card.controller_player_id
	for effect in card_def.trigger_effects:
		if _trigger_matches(effect, trigger_type) and _is_effect_enabled_for_card(source_card, effect):
			logs.append_array(resolve_effect(state, source_card_uid, effect, trigger_context))
	return logs

func activate_main_effect(state: GameState, player_id: String, card_uid: String, effect_index := 0) -> Array[String]:
	var logs: Array[String] = []
	var card = state.get_card(card_uid)
	if card == null:
		return ["Main activate failed: missing card."]
	if state.active_player_id != player_id or state.phase != UATypes.Phase.MAIN:
		return ["Main activate failed: wrong phase."]
	if card.controller_player_id != player_id:
		return ["Main activate failed: wrong controller."]
	if card.zone != UATypes.Zone.FRONT_LINE and card.zone != UATypes.Zone.ENERGY_LINE:
		return ["Main activate failed: card is not on the field."]
	var card_def = state.get_card_def(card.def_id)
	if card_def == null:
		return ["Main activate failed: missing definition."]
	var main_effects: Array[Dictionary] = []
	for effect_variant in card_def.trigger_effects:
		var effect: Dictionary = effect_variant
		if _trigger_matches(effect, UATypes.TriggerType.MAIN_ACTIVATE) and _is_effect_enabled_for_card(card, effect):
			main_effects.append(effect)
	if effect_index < 0 or effect_index >= main_effects.size():
		return ["Main activate failed: effect index out of range."]
	var selected_effect: Dictionary = main_effects[effect_index]
	if bool(selected_effect.get("once_per_turn", false)) and bool(card.flags.get("activated_main_this_turn", false)):
		return ["Main activate failed: once per turn already used."]
	card.flags["activated_main_this_turn"] = bool(selected_effect.get("once_per_turn", false))
	logs.append("%s activates a main effect." % card_def.name)
	logs.append_array(resolve_effect(state, card_uid, selected_effect, {
		"player_id": player_id,
		"target_player_id": player_id,
		"attacker_uid": str(state.battle_context.get("attacker_uid", "")),
		"blocker_uid": str(state.battle_context.get("blocker_uid", "")),
		"target_uid": str(state.battle_context.get("target_uid", "")),
	}))
	return logs

func preview_play_modifiers(state: GameState, player_id: String, card_uid: String, context: Dictionary = {}) -> Dictionary:
	var card = state.get_card(card_uid)
	if card == null:
		return {"cost_ap": 0, "allow_current_zone": false, "consumed_delayed_effect_ids": []}
	var card_def = state.get_card_def(card.def_id)
	if card_def == null:
		return {"cost_ap": 0, "allow_current_zone": false, "consumed_delayed_effect_ids": []}

	var play_context := context.duplicate(true)
	play_context["player_id"] = player_id
	play_context["played_card_uid"] = card_uid
	play_context["played_card_def_id"] = card.def_id
	play_context["played_from_zone"] = card.zone
	play_context["played_card_name"] = card_def.name
	play_context["played_card_title"] = card_def.title_code

	var ap_delta := 0
	var allow_current_zone := false
	var consumed_delayed_effect_ids: Array[String] = []

	for modifier_variant in state.static_modifiers:
		var modifier: Dictionary = modifier_variant
		if not _is_modifier_active(state, modifier):
			continue
		if str(modifier.get("modifier_type", "")) != "PLAY_PERMISSION":
			continue
		if str(modifier.get("owner_player_id", "")) != player_id:
			continue
		if _matches_play_permission_modifier(state, modifier, play_context):
			allow_current_zone = true

	for delayed_variant in state.delayed_effects:
		var delayed_effect: Dictionary = delayed_variant
		if not _is_modifier_active(state, delayed_effect):
			continue
		if str(delayed_effect.get("owner_player_id", "")) != player_id:
			continue
		if str(delayed_effect.get("event", "")) != "ON_PLAY_CARD":
			continue
		if not _matches_filter_list(state, delayed_effect.get("filters", []), play_context, card_uid, _get_source_card_uid(delayed_effect)):
			continue
		for step_variant in delayed_effect.get("steps", []):
			var step: Dictionary = step_variant
			if str(step.get("type", "")) == "MODIFY_PLAY_COST_AP":
				ap_delta += int(step.get("value", 0))
		if bool(delayed_effect.get("once", false)):
			consumed_delayed_effect_ids.append(str(delayed_effect.get("id", "")))

	var base_cost_ap := int(card_def.cost_ap)
	return {
		"cost_ap": max(0, base_cost_ap + ap_delta),
		"allow_current_zone": allow_current_zone,
		"consumed_delayed_effect_ids": consumed_delayed_effect_ids,
	}

func commit_play_modifiers(state: GameState, modifier_result: Dictionary) -> void:
	var consumed: Array = modifier_result.get("consumed_delayed_effect_ids", [])
	if consumed.is_empty():
		return
	var keep: Array = []
	for delayed_variant in state.delayed_effects:
		var delayed_effect: Dictionary = delayed_variant
		if consumed.has(str(delayed_effect.get("id", ""))):
			continue
		keep.append(delayed_effect)
	state.delayed_effects = keep

func cleanup_turn_expirations(state: GameState, ending_player_id: String) -> void:
	state.delayed_effects = _filter_unexpired_modifiers(state.delayed_effects, ending_player_id)
	state.static_modifiers = _filter_unexpired_modifiers(state.static_modifiers, ending_player_id)

func deal_damage_to_player(state: GameState, player_id: String, amount: int) -> Array[String]:
	var logs: Array[String] = []
	if player_id == "":
		return logs
	var moved: Array[String] = _collect_life_damage_cards(state, player_id, amount)
	logs.append("%s takes %d damage." % [player_id, amount])
	if moved.is_empty():
		var defeat_now: Dictionary = victory_checker.check_victory(state)
		if not defeat_now.is_empty():
			_apply_victory(state, defeat_now)
		return logs
	var queued_count := 0
	for life_uid in moved:
		if _card_has_trigger(state, life_uid, UATypes.TriggerType.ON_LIFE_TRIGGER):
			var entry := _build_life_trigger_entry(state, player_id, life_uid)
			state.pending_life_triggers.append(entry)
			queued_count += 1
	if queued_count > 0:
		logs.append("%s may resolve %d life trigger(s) in any order." % [player_id, queued_count])
	elif not moved.is_empty():
		logs.append_array(_finalize_pending_life_damage(state))
	return logs

func resolve_life_trigger_decision(state: GameState, card_uid: String, activate: bool) -> Array[String]:
	var logs: Array[String] = []
	var pending_index := -1
	var pending_entry := {}
	for i in range(state.pending_life_triggers.size()):
		var candidate: Dictionary = state.pending_life_triggers[i]
		if str(candidate.get("card_uid", "")) == card_uid:
			pending_index = i
			pending_entry = candidate
			break
	if pending_index == -1:
		return ["Life trigger decision failed: missing pending card."]
	state.pending_life_triggers.remove_at(pending_index)
	var owner_player_id := str(pending_entry.get("player_id", ""))
	var card_name := str(pending_entry.get("card_name", card_uid))
	if activate:
		logs.append("%s activates life trigger of %s." % [owner_player_id, card_name])
		logs.append_array(resolve_trigger(card_uid, UATypes.TriggerType.ON_LIFE_TRIGGER, state, {"target_player_id": owner_player_id}))
	else:
		logs.append("%s skips life trigger of %s." % [owner_player_id, card_name])
	if state.pending_life_triggers.is_empty():
		logs.append_array(_finalize_pending_life_damage(state))
	return logs

func _execute_steps(state: GameState, source_card_uid: String, steps: Array, context: Dictionary) -> Array[String]:
	var logs: Array[String] = []
	for step_variant in steps:
		var step: Dictionary = step_variant
		logs.append_array(_execute_step(state, source_card_uid, step, context))
	return logs

func _execute_step(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary) -> Array[String]:
	var step_type := str(step.get("type", ""))
	if step_type == "SELECT_TARGETS":
		var selected := _resolve_target_set(state, source_card_uid, step.get("target", {}), context)
		context[str(step.get("var", "selected_targets"))] = selected
		return []
	if step_type == "FOR_EACH":
		var logs: Array[String] = []
		var values: Array = context.get(str(step.get("items_var", "")), [])
		var current_var := str(step.get("current_var", "current_item"))
		for item in values:
			context[current_var] = item
			logs.append_array(_execute_steps(state, source_card_uid, step.get("steps", []), context))
		context.erase(current_var)
		return logs
	if step_type == "REGISTER_DELAYED_EFFECT":
		_register_delayed_effect(state, source_card_uid, step)
		return []
	if step_type == "REGISTER_STATIC_MODIFIER":
		_register_static_modifier(state, source_card_uid, step)
		return []
	return _execute_operation(state, source_card_uid, step, context)

func _execute_operation(state: GameState, source_card_uid: String, effect: Dictionary, context: Dictionary = {}) -> Array[String]:
	var logs: Array[String] = []
	var effect_type := str(effect.get("type", ""))
	if effect_type == "DRAW":
		var target_player_id := str(context.get("draw_player_id", context.get("source_player_id", context.get("target_player_id", state.active_player_id))))
		var amount := int(effect.get("value", 1))
		for i in range(amount):
			var draw_uid: String = zone_manager.draw_card(state, target_player_id)
			if draw_uid == "":
				var defeat: Dictionary = victory_checker.check_deck_out_loss(state, target_player_id)
				if not defeat.is_empty():
					_apply_victory(state, defeat)
				logs.append("%s attempted to draw from an empty deck." % target_player_id)
				break
			logs.append("%s draws 1 card." % target_player_id)
		return logs
	if effect_type == "MOVE_ZONE":
		var target_uid := _resolve_step_target_uid(effect, context, source_card_uid)
		var to_zone := _parse_zone(effect.get("to_zone", effect.get("to", UATypes.Zone.OUTSIDE)))
		if target_uid != "":
			zone_manager.move_card(state, target_uid, to_zone, str(context.get("target_player_id", "")))
			logs.append("Moved card %s to %s." % [target_uid, UATypes.zone_to_key(to_zone)])
		return logs
	if effect_type == "REST":
		var rest_uid := _resolve_step_target_uid(effect, context, source_card_uid)
		var rest_card = state.get_card(rest_uid)
		if rest_card != null:
			rest_card.state = UATypes.CardState.RESTED
			logs.append("%s becomes rested." % rest_card.uid)
		return logs
	if effect_type == "ACTIVATE":
		var active_uid := _resolve_step_target_uid(effect, context, source_card_uid)
		var active_card = state.get_card(active_uid)
		if active_card != null:
			active_card.state = UATypes.CardState.ACTIVE
			logs.append("%s becomes active." % active_card.uid)
		return logs
	if effect_type == "DEAL_DAMAGE_TO_PLAYER":
		var target_id := str(context.get("target_player_id", ""))
		var damage := int(effect.get("value", 1))
		logs.append_array(deal_damage_to_player(state, target_id, damage))
		return logs
	if effect_type == "MODIFY_PLAY_COST_AP":
		return logs
	if effect_type == "QUEUE_EFFECT":
		state.effect_queue.append({
			"source_card_uid": source_card_uid,
			"effect": effect.duplicate(true),
			"context": context.duplicate(true),
		})
		return logs
	logs.append("Reserved unsupported effect type: %s" % effect_type)
	return logs

func _collect_life_damage_cards(state: GameState, player_id: String, amount: int) -> Array[String]:
	var moved: Array[String] = []
	var player = state.get_player(player_id)
	if player == null:
		return moved
	for i in range(amount):
		if player.life.is_empty():
			break
		var card_uid: String = player.life.pop_front()
		moved.append(card_uid)
		state.pending_life_damage_cards.append({
			"player_id": player_id,
			"card_uid": card_uid,
		})
	return moved

func _finalize_pending_life_damage(state: GameState) -> Array[String]:
	var logs: Array[String] = []
	for entry_variant in state.pending_life_damage_cards:
		var entry: Dictionary = entry_variant
		var player_id := str(entry.get("player_id", ""))
		var card_uid := str(entry.get("card_uid", ""))
		var player = state.get_player(player_id)
		if player == null or card_uid == "":
			continue
		if not player.outside.has(card_uid):
			player.outside.append(card_uid)
		var card = state.get_card(card_uid)
		if card != null:
			card.zone = UATypes.Zone.OUTSIDE
	state.pending_life_damage_cards.clear()
	var defeat: Dictionary = victory_checker.check_victory(state)
	if not defeat.is_empty():
		_apply_victory(state, defeat)
	return logs

func _build_life_trigger_entry(state: GameState, player_id: String, card_uid: String) -> Dictionary:
	var card_name := card_uid
	var card = state.get_card(card_uid)
	if card != null:
		var card_def = state.get_card_def(card.def_id)
		if card_def != null:
			card_name = card_def.name
	return {
		"player_id": player_id,
		"card_uid": card_uid,
		"card_name": card_name,
	}

func _register_delayed_effect(state: GameState, source_card_uid: String, step: Dictionary) -> void:
	var source_card = state.get_card(source_card_uid)
	if source_card == null:
		return
	state.delayed_effects.append({
		"id": state.next_runtime_id("delayed"),
		"source_card_uid": source_card_uid,
		"owner_player_id": source_card.controller_player_id,
		"event": str(step.get("event", "")),
		"filters": step.get("filters", []).duplicate(true),
		"steps": step.get("steps", []).duplicate(true),
		"once": bool(step.get("once", false)),
		"expires": str(step.get("expires", "")),
	})

func _register_static_modifier(state: GameState, source_card_uid: String, step: Dictionary) -> void:
	var source_card = state.get_card(source_card_uid)
	if source_card == null:
		return
	state.static_modifiers.append({
		"id": state.next_runtime_id("static"),
		"source_card_uid": source_card_uid,
		"owner_player_id": source_card.controller_player_id,
		"modifier_type": str(step.get("modifier_type", "")),
		"while": step.get("while", []).duplicate(true),
		"from_zone": step.get("from_zone", null),
		"owner": str(step.get("owner", "SELF")),
		"filters": step.get("filters", []).duplicate(true),
		"expires": str(step.get("expires", "")),
	})

func _resolve_target_set(state: GameState, source_card_uid: String, target: Dictionary, context: Dictionary) -> Array:
	var result: Array = []
	if str(target.get("type", "")) != "CARD_SET":
		return result
	var source_card = state.get_card(source_card_uid)
	if source_card == null:
		return result
	var zone := _parse_zone(target.get("from_zone", UATypes.Zone.OUTSIDE))
	var owner_mode := str(target.get("owner", "SELF"))
	var owner_player_ids := _resolve_owner_player_ids(state, owner_mode, source_card.controller_player_id)
	var filters: Array = target.get("filters", [])
	for player_id in owner_player_ids:
		var player = state.get_player(player_id)
		if player == null:
			continue
		var zone_cards = zone_manager.get_zone_array(player, zone)
		if zone_cards == null:
			continue
		for card_uid in zone_cards:
			if _matches_filter_list(state, filters, context, str(card_uid), source_card_uid):
				result.append(card_uid)
	var min_count := int(target.get("min", 0))
	if result.size() < min_count:
		return []
	var max_count := int(target.get("max", result.size()))
	if max_count >= 0 and result.size() > max_count:
		return result.slice(0, max_count)
	return result

func _resolve_owner_player_ids(state: GameState, owner_mode: String, source_player_id: String) -> Array:
	if owner_mode == "SELF":
		return [source_player_id]
	if owner_mode == "OPPONENT":
		return [_opponent_of(source_player_id)]
	if owner_mode == "ANY":
		return [UATypes.PLAYER_ONE, UATypes.PLAYER_TWO]
	if owner_mode == "ACTIVE_PLAYER":
		return [state.active_player_id]
	if owner_mode == "TARGET_PLAYER":
		return [str(state.battle_context.get("defender_player_id", source_player_id))]
	return [source_player_id]

func _matches_play_permission_modifier(state: GameState, modifier: Dictionary, context: Dictionary) -> bool:
	var source_card_uid := _get_source_card_uid(modifier)
	if not _matches_filter_list(state, modifier.get("while", []), context, str(context.get("played_card_uid", "")), source_card_uid):
		return false
	var from_zone := _parse_zone(modifier.get("from_zone", -1))
	if from_zone != -1 and int(context.get("played_from_zone", -2)) != from_zone:
		return false
	return _matches_filter_list(state, modifier.get("filters", []), context, str(context.get("played_card_uid", "")), source_card_uid)

func _matches_filter_list(state: GameState, filters: Array, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	for filter_variant in filters:
		if not _matches_filter(state, filter_variant, context, candidate_card_uid, source_card_uid):
			return false
	return true

func _matches_filter(state: GameState, filter_variant, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var filter: Dictionary = filter_variant
	var filter_type := str(filter.get("type", ""))
	var candidate_card = state.get_card(candidate_card_uid)
	var candidate_def = null
	if candidate_card != null:
		candidate_def = state.get_card_def(candidate_card.def_id)
	var source_card = state.get_card(source_card_uid)

	if filter_type == "CARD_TYPE_IS":
		return candidate_def != null and UATypes.card_type_to_text(candidate_def.card_type) == str(filter.get("value", ""))
	if filter_type == "NAME_NOT":
		return candidate_def != null and candidate_def.name != str(filter.get("value", ""))
	if filter_type == "NOT_HAS_KEYWORD":
		return candidate_def != null and not candidate_def.keywords.has(str(filter.get("value", "")))
	if filter_type == "HAS_TRAIT":
		return candidate_def != null and candidate_def.traits.has(str(filter.get("value", "")))
	if filter_type == "TITLE_IS":
		return candidate_def != null and candidate_def.title_code == str(filter.get("value", ""))
	if filter_type == "PLAYED_FROM_ZONE_IS":
		return int(context.get("played_from_zone", -1)) == _parse_zone(filter.get("value", -1))
	if filter_type == "OWNER_IS":
		if candidate_card == null or source_card == null:
			return false
		var owner_value := str(filter.get("value", ""))
		if owner_value == "SELF":
			return candidate_card.owner_player_id == source_card.owner_player_id
		if owner_value == "OPPONENT":
			return candidate_card.owner_player_id != source_card.owner_player_id
		if owner_value == "ACTIVE_PLAYER":
			return candidate_card.owner_player_id == str(context.get("player_id", state.active_player_id))
		return false
	if filter_type == "OR":
		for nested in filter.get("filters", []):
			if _matches_filter(state, nested, context, candidate_card_uid, source_card_uid):
				return true
		return false
	if filter_type == "SELF_IN_ZONE":
		return source_card != null and source_card.zone == _parse_zone(filter.get("zone", filter.get("value", -1)))
	return true

func _is_modifier_active(state: GameState, modifier: Dictionary) -> bool:
	var source_card_uid := _get_source_card_uid(modifier)
	var source_card = state.get_card(source_card_uid)
	if source_card == null:
		return false
	return _matches_filter_list(state, modifier.get("while", []), {}, "", source_card_uid)

func _filter_unexpired_modifiers(modifiers: Array, ending_player_id: String) -> Array:
	var keep: Array = []
	for modifier_variant in modifiers:
		var modifier: Dictionary = modifier_variant
		if str(modifier.get("expires", "")) == "END_OF_TURN" and str(modifier.get("owner_player_id", "")) == ending_player_id:
			continue
		keep.append(modifier)
	return keep

func _resolve_step_target_uid(effect: Dictionary, context: Dictionary, source_card_uid: String) -> String:
	if effect.has("target_uid"):
		return str(effect.get("target_uid", source_card_uid))
	if effect.has("target_var"):
		return str(context.get(str(effect.get("target_var", "")), source_card_uid))
	if effect.has("target"):
		var target_value = effect.get("target")
		if target_value is Dictionary:
			var target_dict: Dictionary = target_value
			if str(target_dict.get("type", "")) == "CURRENT_ITEM":
				return str(context.get("current_item", source_card_uid))
	return str(context.get("current_item", source_card_uid))

func _parse_zone(value) -> int:
	if value is int:
		return int(value)
	var zone_name := str(value)
	if zone_name == "DECK" or zone_name == "deck":
		return UATypes.Zone.DECK
	if zone_name == "HAND" or zone_name == "hand":
		return UATypes.Zone.HAND
	if zone_name == "LIFE" or zone_name == "life":
		return UATypes.Zone.LIFE
	if zone_name == "FRONT_LINE" or zone_name == "front_line":
		return UATypes.Zone.FRONT_LINE
	if zone_name == "ENERGY_LINE" or zone_name == "energy_line":
		return UATypes.Zone.ENERGY_LINE
	if zone_name == "AP_AREA" or zone_name == "ap_area":
		return UATypes.Zone.AP_AREA
	if zone_name == "OUTSIDE" or zone_name == "outside":
		return UATypes.Zone.OUTSIDE
	if zone_name == "REMOVED" or zone_name == "removed":
		return UATypes.Zone.REMOVED
	return -1

func _apply_victory(state: GameState, result: Dictionary) -> void:
	state.winner_player_id = str(result.get("winner", ""))
	state.loser_player_id = str(result.get("loser", ""))

func _is_effect_enabled_for_card(source_card, effect: Dictionary) -> bool:
	var effect_box := str(effect.get("effect_box", ""))
	if effect_box == "RAID_INNER":
		return bool(source_card.flags.get("entered_via_raid", false))
	return true

func _trigger_matches(effect: Dictionary, trigger_type: int) -> bool:
	var name := str(effect.get("trigger", ""))
	match trigger_type:
		UATypes.TriggerType.ON_ENTER:
			return name == "ON_ENTER"
		UATypes.TriggerType.ON_LEAVE:
			return name == "ON_LEAVE"
		UATypes.TriggerType.ON_ATTACK:
			return name == "ON_ATTACK"
		UATypes.TriggerType.ON_BLOCK:
			return name == "ON_BLOCK"
		UATypes.TriggerType.ON_LIFE_TRIGGER:
			return name == "ON_LIFE_TRIGGER"
		UATypes.TriggerType.MAIN_ACTIVATE:
			return name == "MAIN_ACTIVATE"
		UATypes.TriggerType.ON_BATTLE_WIN:
			return name == "ON_BATTLE_WIN"
		UATypes.TriggerType.ON_BATTLE_LOSE:
			return name == "ON_BATTLE_LOSE"
		UATypes.TriggerType.ON_BATTLE_END:
			return name == "ON_BATTLE_END"
	return false

func _card_has_trigger(state: GameState, card_uid: String, trigger_type: int) -> bool:
	var source_card = state.get_card(card_uid)
	if source_card == null:
		return false
	var card_def = state.get_card_def(source_card.def_id)
	if card_def == null:
		return false
	for effect_variant in card_def.trigger_effects:
		var effect: Dictionary = effect_variant
		if _trigger_matches(effect, trigger_type) and _is_effect_enabled_for_card(source_card, effect):
			return true
	return false

func _opponent_of(player_id: String) -> String:
	if player_id == UATypes.PLAYER_ONE:
		return UATypes.PLAYER_TWO
	return UATypes.PLAYER_ONE

func _get_source_card_uid(modifier: Dictionary) -> String:
	return str(modifier.get("source_card_uid", ""))
