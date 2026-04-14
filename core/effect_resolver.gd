extends RefCounted
class_name EffectResolver

const UATypes = preload("res://core/ua_types.gd")
const ZoneManager = preload("res://core/zone_manager.gd")
const VictoryChecker = preload("res://core/victory_checker.gd")
const PlayerUtils = preload("res://core/player_utils.gd")
const GameState = preload("res://data/game_state.gd")
const CardInstance = preload("res://data/card_instance.gd")
const RequirementMatcher = preload("res://core/effects/requirement_matcher.gd")
const StepExecutor = preload("res://core/effects/step_executor.gd")
const LifeDamageHandler = preload("res://core/effects/life_damage_handler.gd")
const TargetSelector = preload("res://core/effects/target_selector.gd")

var zone_manager
var victory_checker
var rules_engine
var _requirement_matcher: RequirementMatcher
var _step_executor: StepExecutor
var _life_damage_handler: LifeDamageHandler
var _target_selector: TargetSelector

func _init(p_zone_manager, p_victory_checker, p_rules_engine = null) -> void:
	zone_manager = p_zone_manager
	victory_checker = p_victory_checker
	rules_engine = p_rules_engine
	_requirement_matcher = RequirementMatcher.new(zone_manager, rules_engine, self)
	_target_selector = TargetSelector.new(zone_manager, _requirement_matcher, self)
	_step_executor = StepExecutor.new(zone_manager, victory_checker, rules_engine, self)
	_life_damage_handler = LifeDamageHandler.new(victory_checker, self)

func resolve_operations(state: GameState, source_card_uid: String, effect_list: Array, context: Dictionary = {}) -> Array[String]:
	var logs: Array[String] = []
	for effect in effect_list:
		logs.append_array(_execute_operation(state, source_card_uid, effect, context))
	return logs

func resolve_effect(state: GameState, source_card_uid: String, effect: Dictionary, context: Dictionary = {}) -> Array[String]:
	state.effect_queue.append(_build_effect_queue_entry(source_card_uid, effect, context))
	return consume_effect_queue(state)

func consume_effect_queue(state: GameState) -> Array[String]:
	var logs: Array[String] = []
	while not state.effect_queue.is_empty():
		if not state.pending_decisions.is_empty() or not state.pending_life_triggers.is_empty():
			break
		var entry: Dictionary = state.effect_queue[0]
		if str(entry.get("kind", "")) == "TARGET_SELECTION":
			break
		state.effect_queue.remove_at(0)
		logs.append_array(_consume_queue_entry(state, entry))
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
			state.effect_queue.append(_build_effect_queue_entry(source_card_uid, effect, trigger_context))
	logs.append_array(consume_effect_queue(state))
	return logs

func resolve_simultaneous_triggers(state: GameState, trigger_entries: Array) -> Array[String]:
	var grouped_by_owner := {}
	var owner_order: Array[String] = []
	for entry_variant in trigger_entries:
		var entry: Dictionary = entry_variant
		var source_card_uid := str(entry.get("source_card_uid", ""))
		var source_card = state.get_card(source_card_uid)
		if source_card == null:
			continue
		var owner_player_id := str(entry.get("owner_player_id", source_card.controller_player_id))
		var normalized_entry := entry.duplicate(true)
		normalized_entry["owner_player_id"] = owner_player_id
		if not grouped_by_owner.has(owner_player_id):
			grouped_by_owner[owner_player_id] = []
			owner_order.append(owner_player_id)
		(grouped_by_owner[owner_player_id] as Array).append(normalized_entry)
	var owner_groups: Array = []
	if grouped_by_owner.has(state.active_player_id):
		owner_groups.append((grouped_by_owner[state.active_player_id] as Array).duplicate(true))
	for owner_player_id in owner_order:
		if owner_player_id == state.active_player_id:
			continue
		owner_groups.append((grouped_by_owner[owner_player_id] as Array).duplicate(true))
	return _resolve_trigger_owner_groups(state, owner_groups)

func resolve_trigger_order_decision(state: GameState, decision: Dictionary, selected_source_card_uid: String) -> Array[String]:
	var context: Dictionary = decision.get("context", {})
	var current_group: Array = context.get("trigger_entries", [])
	var next_groups: Array = context.get("queued_owner_groups", [])
	var chosen_entry := {}
	var remaining_entries: Array = []
	for entry_variant in current_group:
		var entry: Dictionary = entry_variant
		if chosen_entry.is_empty() and str(entry.get("source_card_uid", "")) == selected_source_card_uid:
			chosen_entry = entry.duplicate(true)
			continue
		remaining_entries.append(entry.duplicate(true))
	if chosen_entry.is_empty():
		return ["Trigger order decision failed: selected trigger not found."]
	var logs := resolve_trigger(
		str(chosen_entry.get("source_card_uid", "")),
		int(chosen_entry.get("trigger_type", -1)),
		state,
		chosen_entry.get("context", {}).duplicate(true)
	)
	if not remaining_entries.is_empty():
		var owner_player_id := str(chosen_entry.get("owner_player_id", decision.get("owner_player_id", "")))
		_enqueue_trigger_order_decision(state, owner_player_id, remaining_entries, next_groups)
		logs.append("%s may resolve the remaining simultaneous trigger(s) in any order." % owner_player_id)
		return logs
	logs.append_array(_resolve_trigger_owner_groups(state, next_groups))
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
	var activate_context := {
		"player_id": player_id,
		"source_player_id": player_id,
		"target_player_id": player_id,
		"attacker_uid": str(state.battle_context.get("attacker_uid", "")),
		"blocker_uid": str(state.battle_context.get("blocker_uid", "")),
		"target_uid": str(state.battle_context.get("target_uid", "")),
	}
	var requirements: Array = selected_effect.get("requirements", selected_effect.get("condition", []))
	if not _requirements_met(state, card_uid, requirements, activate_context):
		return ["Main activate failed: requirements not met."]
	var cost_preview := _preview_effect_costs(state, card_uid, selected_effect.get("costs", []), activate_context)
	if not bool(cost_preview.get("ok", true)):
		return ["Main activate failed: %s" % str(cost_preview.get("reason", "cost_unavailable"))]
	if bool(selected_effect.get("once_per_turn", false)) and bool(card.flags.get("activated_main_this_turn", false)):
		return ["Main activate failed: once per turn already used."]
	card.flags["activated_main_this_turn"] = bool(selected_effect.get("once_per_turn", false))
	logs.append("%s activates a main effect." % card_def.name)
	state.effect_queue.append(_build_effect_queue_entry(card_uid, selected_effect, activate_context))
	logs.append_array(consume_effect_queue(state))
	return logs

func resolve_target_selection_decision(state: GameState, resolution_id: String, selected_values) -> Array[String]:
	var logs: Array[String] = []
	if resolution_id == "":
		return ["Target selection failed: missing resolution id."]
	var queued_index := -1
	var queued_effect := {}
	for i in range(state.effect_queue.size()):
		var candidate: Dictionary = state.effect_queue[i]
		if str(candidate.get("id", "")) == resolution_id:
			queued_index = i
			queued_effect = candidate
			break
	if queued_index == -1:
		return ["Target selection failed: queued effect not found."]
	state.effect_queue.remove_at(queued_index)
	var context: Dictionary = queued_effect.get("context", {}).duplicate(true)
	var target_var := str(queued_effect.get("target_var", "selected_targets"))
	var min_count := int(queued_effect.get("min", 0))
	var max_count := int(queued_effect.get("max", 1))
	var normalized := _normalize_selection_payload(selected_values, max_count)
	if normalized.size() < min_count:
		state.effect_queue.insert(queued_index, queued_effect)
		return ["Target selection failed: not enough targets."]
	var validation_reason := _validate_selection_payload(state, normalized, queued_effect)
	if validation_reason != "":
		state.effect_queue.insert(queued_index, queued_effect)
		return ["Target selection failed: %s." % validation_reason]
	if max_count == 1:
		context[target_var] = normalized[0] if not normalized.is_empty() else ""
	else:
		context[target_var] = normalized
	if bool(queued_effect.get("resume_as_effect", false)):
		state.effect_queue.insert(0, _build_effect_queue_entry(
			str(queued_effect.get("source_card_uid", "")),
			queued_effect.get("effect", {}),
			context
		))
	else:
		state.effect_queue.insert(0, _build_effect_queue_entry(
			str(queued_effect.get("source_card_uid", "")),
			{"steps": queued_effect.get("steps", [])},
			context
		))
	logs.append_array(consume_effect_queue(state))
	return logs

func preview_play_modifiers(state: GameState, player_id: String, card_uid: String, context: Dictionary = {}) -> Dictionary:
	var card = state.get_card(card_uid)
	if card == null:
		return {"cost_ap": 0, "cost_energy": {}, "allow_current_zone": false, "consumed_delayed_effect_ids": []}
	var card_def = state.get_card_def(card.def_id)
	if card_def == null:
		return {"cost_ap": 0, "cost_energy": {}, "allow_current_zone": false, "consumed_delayed_effect_ids": []}

	var play_context := context.duplicate(true)
	play_context["player_id"] = player_id
	play_context["played_card_uid"] = card_uid
	play_context["played_card_def_id"] = card.def_id
	play_context["played_from_zone"] = card.zone
	play_context["played_card_name"] = card_def.name
	play_context["played_card_title"] = card_def.title_code

	var ap_delta := 0
	var effective_cost_energy: Dictionary = card_def.cost_energy.duplicate(true)
	var allow_current_zone := false
	var consumed_delayed_effect_ids: Array[String] = []

	for modifier_variant in card_def.play_rule.get("cost_modifiers", []):
		var modifier: Dictionary = modifier_variant
		var modifier_type := str(modifier.get("type", ""))
		var from_zone := _parse_zone(modifier.get("from_zone", -1))
		if from_zone != -1 and card.zone != from_zone:
			continue
		if modifier_type == "SELF_HAND_AP_DELTA":
			if _requirements_met(state, card_uid, modifier.get("requirements", []), play_context, card_uid):
				ap_delta += int(modifier.get("ap_delta", 0))
		elif modifier_type == "SELF_HAND_ENERGY_DELTA":
			if _requirements_met(state, card_uid, modifier.get("requirements", []), play_context, card_uid):
				effective_cost_energy = _apply_energy_delta_map(effective_cost_energy, modifier.get("energy_delta", {}))

	for modifier_variant in state.static_modifiers:
		var modifier: Dictionary = modifier_variant
		if not _is_modifier_active(state, modifier):
			continue
		if str(modifier.get("owner_player_id", "")) != player_id:
			continue
		var modifier_type := str(modifier.get("modifier_type", ""))
		if modifier_type == "PLAY_PERMISSION":
			if _matches_play_permission_modifier(state, modifier, play_context):
				allow_current_zone = true
			continue
		if modifier_type != "HAND_PLAY_COST_ENERGY_DELTA":
			continue
		var from_zone := _parse_zone(modifier.get("from_zone", -1))
		if from_zone != -1 and card.zone != from_zone:
			continue
		if not _matches_filter_list(state, modifier.get("filters", []), play_context, card_uid, _get_source_card_uid(modifier)):
			continue
		var energy_delta: Dictionary = modifier.get("energy_delta", {})
		if not energy_delta.is_empty():
			effective_cost_energy = _apply_energy_delta_map(effective_cost_energy, energy_delta)
		else:
			effective_cost_energy = _apply_energy_scalar_delta(effective_cost_energy, int(modifier.get("value", 0)))

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
		"cost_energy": effective_cost_energy,
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

func consume_timed_delayed_effects(state: GameState, event_name: String, context: Dictionary = {}) -> Array[String]:
	var logs: Array[String] = []
	if event_name == "":
		return logs
	var remaining: Array = []
	for delayed_variant in state.delayed_effects:
		var delayed_effect: Dictionary = delayed_variant
		if str(delayed_effect.get("event", "")) != event_name:
			remaining.append(delayed_effect)
			continue
		if not _is_modifier_active(state, delayed_effect):
			continue
		var delayed_context := context.duplicate(true)
		delayed_context["source_player_id"] = str(delayed_effect.get("owner_player_id", delayed_context.get("source_player_id", "")))
		delayed_context["target_player_id"] = str(delayed_context.get("target_player_id", delayed_context.get("source_player_id", "")))
		if not _matches_filter_list(
			state,
			delayed_effect.get("filters", []),
			delayed_context,
			_get_source_card_uid(delayed_effect),
			_get_source_card_uid(delayed_effect)
		):
			if str(delayed_effect.get("expires", "")) != "END_OF_TURN" and str(delayed_effect.get("expires", "")) != "UNTIL_NEXT_SELF_TURN_START":
				remaining.append(delayed_effect)
			continue
		logs.append_array(_resolve_effect_now(
			state,
			_get_source_card_uid(delayed_effect),
			{"steps": delayed_effect.get("steps", []).duplicate(true)},
			delayed_context
		))
		if not bool(delayed_effect.get("once", false)):
			remaining.append(delayed_effect)
	state.delayed_effects = remaining
	return logs

func cleanup_turn_expirations(state: GameState, ending_player_id: String) -> void:
	_revert_expired_temporary_modifiers(state, ending_player_id, "END_OF_TURN")
	state.delayed_effects = _filter_unexpired_modifiers(state.delayed_effects, ending_player_id, "END_OF_TURN")
	state.static_modifiers = _filter_unexpired_modifiers(state.static_modifiers, ending_player_id, "END_OF_TURN")

func cleanup_start_turn_expirations(state: GameState, starting_player_id: String) -> void:
	_revert_expired_temporary_modifiers(state, starting_player_id, "UNTIL_NEXT_SELF_TURN_START")
	state.delayed_effects = _filter_unexpired_modifiers(state.delayed_effects, starting_player_id, "UNTIL_NEXT_SELF_TURN_START")
	state.static_modifiers = _filter_unexpired_modifiers(state.static_modifiers, starting_player_id, "UNTIL_NEXT_SELF_TURN_START")

func deal_damage_to_player(state: GameState, player_id: String, amount: int) -> Array[String]:
	return _life_damage_handler.deal_damage_to_player(state, player_id, amount)

func resolve_life_trigger_decision(state: GameState, card_uid: String, activate: bool) -> Array[String]:
	return _life_damage_handler.resolve_life_trigger_decision(state, card_uid, activate)

func move_pending_life_card_to_hand(state: GameState, card_uid: String, owner_player_id: String = "") -> bool:
	if card_uid == "":
		return false
	var card = state.get_card(card_uid)
	if card == null:
		return false
	var resolved_owner_player_id := owner_player_id
	if resolved_owner_player_id == "":
		resolved_owner_player_id = card.owner_player_id
	for i in range(state.pending_life_damage_cards.size()):
		var entry: Dictionary = state.pending_life_damage_cards[i]
		if str(entry.get("card_uid", "")) != card_uid:
			continue
		state.pending_life_damage_cards.remove_at(i)
		break
	zone_manager.move_card(state, card_uid, UATypes.Zone.HAND, resolved_owner_player_id)
	return true

func acknowledge_life_reveal(state: GameState, card_uid: String) -> Array[String]:
	return _life_damage_handler.acknowledge_life_reveal(state, card_uid)

func finalize_pending_life_damage(state: GameState) -> Array[String]:
	return _life_damage_handler.finalize_pending_life_damage(state)

func _consume_queue_entry(state: GameState, entry: Dictionary) -> Array[String]:
	if str(entry.get("kind", "")) != "RESOLVE_EFFECT":
		return []
	return _resolve_effect_now(
		state,
		str(entry.get("source_card_uid", "")),
		entry.get("effect", {}),
		entry.get("context", {}).duplicate(true)
	)

func _resolve_effect_now(state: GameState, source_card_uid: String, effect: Dictionary, context: Dictionary = {}) -> Array[String]:
	var logs: Array[String] = []
	if not _can_resolve_effect_once_per_turn(state, source_card_uid, effect):
		return logs
	var requirements: Array = effect.get("requirements", effect.get("condition", []))
	if not _requirements_met(state, source_card_uid, requirements, context):
		return logs
	_mark_effect_once_per_turn_if_needed(state, source_card_uid, effect)
	var target_result := _prepare_effect_targets(state, source_card_uid, effect, context)
	logs.append_array(target_result.get("logs", []))
	if bool(target_result.get("paused", false)) or not bool(target_result.get("ok", true)):
		_unmark_effect_once_per_turn_if_needed(state, source_card_uid, effect)
		return logs
	var cost_result := _pay_effect_costs(state, source_card_uid, effect.get("costs", []), context)
	logs.append_array(cost_result.get("logs", []))
	if not bool(cost_result.get("ok", true)):
		_unmark_effect_once_per_turn_if_needed(state, source_card_uid, effect)
		return logs
	if effect.has("steps"):
		var step_result := _execute_steps(state, source_card_uid, effect.get("steps", []), context, effect)
		logs.append_array(step_result.get("logs", []))
		return logs
	if effect.has("type"):
		logs.append_array(_execute_operation(state, source_card_uid, effect, context))
		return logs
	var operations = effect.get("operations", effect.get("operation", []))
	if operations is Dictionary:
		operations = [operations]
	logs.append_array(resolve_operations(state, source_card_uid, operations, context))
	return logs

func _execute_steps(state: GameState, source_card_uid: String, steps: Array, context: Dictionary, effect: Dictionary = {}) -> Dictionary:
	return _step_executor.execute_steps(state, source_card_uid, steps, context, effect)

func _execute_step(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary, remaining_steps: Array = [], effect: Dictionary = {}) -> Dictionary:
	return _step_executor.execute(state, source_card_uid, step, context, remaining_steps, effect)

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
			zone_manager.move_card(state, target_uid, to_zone, str(context.get("target_player_id", "")), str(effect.get("to_position", "")))
			logs.append("Moved card %s to %s." % [target_uid, UATypes.zone_to_key(to_zone)])
		return logs
	if effect_type == "MOVE_CARD":
		var move_uid := _resolve_step_target_uid(effect, context, source_card_uid)
		var move_to_zone := _parse_zone(effect.get("to_zone", effect.get("to", UATypes.Zone.OUTSIDE)))
		if move_uid != "":
			zone_manager.move_card(state, move_uid, move_to_zone, str(context.get("target_player_id", "")), str(effect.get("to_position", "")))
			logs.append("Moved card %s to %s." % [move_uid, UATypes.zone_to_key(move_to_zone)])
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
	if effect_type == "ACTIVATE_CARD":
		var activate_uid := _resolve_step_target_uid(effect, context, source_card_uid)
		var activate_card = state.get_card(activate_uid)
		if activate_card != null:
			activate_card.state = UATypes.CardState.ACTIVE
			logs.append("%s becomes active." % activate_card.uid)
		return logs
	if effect_type == "DEAL_DAMAGE_TO_PLAYER":
		var target_id := str(context.get("target_player_id", ""))
		var damage := int(effect.get("value", 1))
		logs.append_array(deal_damage_to_player(state, target_id, damage))
		return logs
	if effect_type == "MODIFY_PLAY_COST_AP":
		return logs
	if effect_type == "MODIFY_BP":
		var bp_uid := _resolve_step_target_uid(effect, context, source_card_uid)
		var bp_card = state.get_card(bp_uid)
		if bp_card != null:
			bp_card.current_bp += int(effect.get("value", 0))
			logs.append("%s BP changes by %d." % [bp_uid, int(effect.get("value", 0))])
		return logs
	if effect_type == "QUEUE_EFFECT":
		var queued_effect: Dictionary = effect.get("queued_effect", effect.get("effect", {}))
		if queued_effect.is_empty():
			return logs
		var queued_context := context.duplicate(true)
		var context_patch = effect.get("context", {})
		if context_patch is Dictionary:
			queued_context.merge(context_patch, true)
		state.effect_queue.append(_build_effect_queue_entry(source_card_uid, queued_effect, queued_context))
		return logs
	logs.append("Reserved unsupported effect type: %s" % effect_type)
	return logs

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
	var granted_card_uid := str(step.get("granted_card_uid", ""))
	if granted_card_uid == "SOURCE_CARD":
		granted_card_uid = source_card_uid
	var allowed_modes: Array = []
	for mode_variant in step.get("allowed_modes", []):
		allowed_modes.append(str(mode_variant))
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
		"color": str(step.get("color", "")),
		"value": step.get("value", 0),
		"energy_delta": step.get("energy_delta", {}).duplicate(true),
		"granted_card_uid": granted_card_uid,
		"allowed_modes": allowed_modes,
	})

func _apply_temporary_bp_modifier(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary) -> Array[String]:
	var logs: Array[String] = []
	var target_uid := _resolve_step_target_uid(step, context, source_card_uid)
	var target_card = state.get_card(target_uid)
	if target_card == null:
		return logs
	var delta := int(step.get("value", 0))
	if step.has("value_provider"):
		delta = _resolve_numeric_value(state, step.get("value_provider", 0), context, source_card_uid, target_uid)
	target_card.current_bp += delta
	var source_card = state.get_card(source_card_uid)
	state.static_modifiers.append({
		"id": state.next_runtime_id("temp_bp"),
		"source_card_uid": source_card_uid,
		"owner_player_id": source_card.controller_player_id if source_card != null else str(context.get("source_player_id", "")),
		"modifier_type": "TEMP_BP",
		"target_uid": target_uid,
		"value": delta,
		"expires": str(step.get("expires", "END_OF_TURN")),
	})
	logs.append("%s BP changes by %d until end of turn." % [target_uid, delta])
	return logs

func _swap_source_with_selected_card(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary) -> Array[String]:
	var logs: Array[String] = []
	var source_card = state.get_card(source_card_uid)
	var target_uid := _resolve_step_target_uid(step, context, source_card_uid)
	var target_card = state.get_card(target_uid)
	if source_card == null or target_card == null or source_card.uid == target_card.uid:
		return logs
	var source_zone: int = source_card.zone
	var target_zone: int = target_card.zone
	var source_controller: String = source_card.controller_player_id
	var target_controller: String = target_card.controller_player_id
	zone_manager.move_card(state, target_uid, source_zone, source_controller)
	zone_manager.move_card(state, source_card_uid, target_zone, target_controller)
	logs.append("Swapped %s with %s." % [source_card_uid, target_uid])
	return logs

func _move_source_stacked_under_to_zone(state: GameState, source_card_uid: String, step: Dictionary) -> Array[String]:
	var logs: Array[String] = []
	var source_card = state.get_card(source_card_uid)
	if source_card == null:
		return logs
	var to_zone := _parse_zone(step.get("to_zone", step.get("to", UATypes.Zone.HAND)))
	var count := maxi(0, int(step.get("count", 1)))
	var moved := 0
	while moved < count and not source_card.stacked_under.is_empty():
		var stacked_uid := str(source_card.stacked_under[0])
		source_card.stacked_under.remove_at(0)
		if stacked_uid == "":
			continue
		zone_manager.move_card(state, stacked_uid, to_zone, source_card.controller_player_id)
		logs.append("Moved stacked card %s to %s." % [stacked_uid, UATypes.zone_to_key(to_zone)])
		moved += 1
	return logs

func _apply_temporary_keyword_modifier(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary) -> Array[String]:
	var logs: Array[String] = []
	var target_uid := _resolve_step_target_uid(step, context, source_card_uid)
	var target_card = state.get_card(target_uid)
	if target_card == null:
		return logs
	var keyword := str(step.get("keyword", step.get("value", "")))
	if keyword == "":
		return logs
	_add_runtime_keyword(target_card, keyword)
	var source_card = state.get_card(source_card_uid)
	var expires := str(step.get("expires", "END_OF_TURN"))
	state.static_modifiers.append({
		"id": state.next_runtime_id("temp_keyword"),
		"source_card_uid": source_card_uid,
		"owner_player_id": source_card.controller_player_id if source_card != null else str(context.get("source_player_id", "")),
		"modifier_type": "TEMP_KEYWORD",
		"target_uid": target_uid,
		"keyword": keyword,
		"expires": expires,
	})
	logs.append("%s gains %s %s." % [target_uid, keyword, _format_modifier_expiry_text(expires)])
	return logs

func _resolve_trigger_owner_groups(state: GameState, owner_groups: Array) -> Array[String]:
	var logs: Array[String] = []
	var remaining_groups: Array = []
	for group_variant in owner_groups:
		var group: Array = group_variant
		if not group.is_empty():
			remaining_groups.append(group.duplicate(true))
	while not remaining_groups.is_empty():
		var current_group: Array = remaining_groups[0]
		remaining_groups.remove_at(0)
		if current_group.is_empty():
			continue
		if current_group.size() == 1:
			var entry: Dictionary = current_group[0]
			logs.append_array(resolve_trigger(
				str(entry.get("source_card_uid", "")),
				int(entry.get("trigger_type", -1)),
				state,
				entry.get("context", {}).duplicate(true)
			))
			continue
		var owner_player_id := str((current_group[0] as Dictionary).get("owner_player_id", ""))
		_enqueue_trigger_order_decision(state, owner_player_id, current_group, remaining_groups)
		logs.append("%s may resolve %d simultaneous trigger(s) in any order." % [owner_player_id, current_group.size()])
		break
	return logs

func _enqueue_trigger_order_decision(state: GameState, owner_player_id: String, trigger_entries: Array, queued_owner_groups: Array) -> void:
	var choices: Array[Dictionary] = []
	for entry_variant in trigger_entries:
		var entry: Dictionary = entry_variant
		var source_card_uid := str(entry.get("source_card_uid", ""))
		var card: CardInstance = state.get_card(source_card_uid)
		var card_def = state.get_card_def(card.def_id) if card != null else null
		var trigger_name := _trigger_type_label(int(entry.get("trigger_type", -1)))
		var card_name: String = card_def.name if card_def != null else source_card_uid
		choices.append({
			"label": "%s (%s)" % [card_name, trigger_name],
			"value": source_card_uid,
			"enabled": true,
			"reason": "",
		})
	state.pending_decisions.append({
		"type": "TRIGGER_ORDER",
		"owner_player_id": owner_player_id,
		"source_card_uid": "",
		"choices": choices,
		"context": {
			"trigger_entries": trigger_entries.duplicate(true),
			"queued_owner_groups": queued_owner_groups.duplicate(true),
		},
	})

func _trigger_type_label(trigger_type: int) -> String:
	match trigger_type:
		UATypes.TriggerType.ON_ENTER:
			return "ON_ENTER"
		UATypes.TriggerType.ON_LEAVE:
			return "ON_LEAVE"
		UATypes.TriggerType.ON_ATTACK:
			return "ON_ATTACK"
		UATypes.TriggerType.ON_BLOCK:
			return "ON_BLOCK"
		UATypes.TriggerType.ON_LIFE_TRIGGER:
			return "ON_LIFE_TRIGGER"
		UATypes.TriggerType.MAIN_ACTIVATE:
			return "MAIN_ACTIVATE"
		UATypes.TriggerType.ON_BATTLE_WIN:
			return "ON_BATTLE_WIN"
		UATypes.TriggerType.ON_BATTLE_LOSE:
			return "ON_BATTLE_LOSE"
		UATypes.TriggerType.ON_BATTLE_END:
			return "ON_BATTLE_END"
	return "UNKNOWN_TRIGGER"

func _build_effect_queue_entry(source_card_uid: String, effect: Dictionary, context: Dictionary) -> Dictionary:
	return {
		"kind": "RESOLVE_EFFECT",
		"source_card_uid": source_card_uid,
		"effect": effect.duplicate(true),
		"context": context.duplicate(true),
	}

func _prepare_effect_targets(state: GameState, source_card_uid: String, effect: Dictionary, context: Dictionary) -> Dictionary:
	var steps: Array = effect.get("steps", [])
	for target_spec_variant in effect.get("target_specs", []):
		var target_spec: Dictionary = target_spec_variant
		var selected_var := str(target_spec.get("store_as", target_spec.get("id", "selected_target")))
		if selected_var == "" or context.has(selected_var) or _steps_define_target_var(steps, selected_var):
			continue
		var target := _target_from_spec(target_spec)
		var selected := _resolve_target_set(state, source_card_uid, target, context)
		var min_count := int(target.get("min", 0))
		var max_count := int(target.get("max", selected.size()))
		if bool(target.get("manual", false)) or str(target.get("selection_mode", "AUTO")) == "MANUAL":
			if selected.is_empty() and min_count > 0:
				return {"ok": false, "logs": ["Effect target selection failed: no legal targets."], "paused": false}
			if _enqueue_target_selection(state, source_card_uid, effect, selected_var, target, selected, context, [], true, _build_preview_pick_ui_meta(target, context)):
				return {"ok": true, "logs": [], "paused": true}
		if max_count == 1:
			context[selected_var] = selected[0] if not selected.is_empty() else ""
		else:
			context[selected_var] = selected
	return {"ok": true, "logs": [], "paused": false}

func _target_from_spec(target_spec: Dictionary) -> Dictionary:
	var candidate: Dictionary = target_spec.get("candidate", {})
	var select: Dictionary = target_spec.get("select", {})
	var target_type := "CARD_SET"
	if str(candidate.get("source_var", "")) != "":
		target_type = "CONTEXT_CARD_SET"
	return {
		"type": target_type,
		"owner": str(candidate.get("owner", "SELF")),
		"zones": candidate.get("zones", []),
		"source_var": str(candidate.get("source_var", "")),
		"filters": candidate.get("filters", []).duplicate(true),
		"requirements": candidate.get("requirements", []).duplicate(true),
		"min": int(select.get("min", 0)),
		"max": int(select.get("max", 1)),
		"selection_mode": str(select.get("mode", "AUTO")),
		"manual": str(select.get("mode", "AUTO")) == "MANUAL",
		"selection_constraints": select.get("constraints", {}).duplicate(true),
	}

func _steps_define_target_var(steps: Array, selected_var: String) -> bool:
	for step_variant in steps:
		var step: Dictionary = step_variant
		if str(step.get("type", "")) == "SELECT_TARGETS" and str(step.get("var", "")) == selected_var:
			return true
	return false

func _preview_effect_costs(state: GameState, source_card_uid: String, costs: Array, context: Dictionary) -> Dictionary:
	for cost_variant in costs:
		var cost: Dictionary = cost_variant
		var cost_type := str(cost.get("type", ""))
		if cost_type == "PAY_AP":
			var ap_player_id := _cost_player_id(state, source_card_uid, context, cost)
			var ap_player = state.get_player(ap_player_id)
			var amount := int(cost.get("value", 1))
			if ap_player == null or ap_player.ap_active_count() < amount:
				return {"ok": false, "reason": "insufficient_ap"}
		elif cost_type == "REST_SOURCE" or cost_type == "REST_SELF":
			var source_card = state.get_card(source_card_uid)
			if source_card == null or source_card.state != UATypes.CardState.ACTIVE:
				return {"ok": false, "reason": "source_not_active"}
	return {"ok": true}

func _pay_effect_costs(state: GameState, source_card_uid: String, costs: Array, context: Dictionary) -> Dictionary:
	var logs: Array[String] = []
	var preview := _preview_effect_costs(state, source_card_uid, costs, context)
	if not bool(preview.get("ok", true)):
		logs.append("Effect cost failed: %s." % str(preview.get("reason", "cost_unavailable")))
		return {"ok": false, "logs": logs}
	for cost_variant in costs:
		var cost: Dictionary = cost_variant
		var cost_type := str(cost.get("type", ""))
		if cost_type == "PAY_AP":
			var ap_player_id := _cost_player_id(state, source_card_uid, context, cost)
			var ap_player = state.get_player(ap_player_id)
			var amount := int(cost.get("value", 1))
			if ap_player != null and amount > 0:
				zone_manager.spend_ap(ap_player, amount)
				logs.append("%s pays %d AP." % [ap_player_id, amount])
		elif cost_type == "REST_SOURCE" or cost_type == "REST_SELF":
			var source_card = state.get_card(source_card_uid)
			if source_card != null:
				source_card.state = UATypes.CardState.RESTED
				logs.append("%s is rested to pay a cost." % source_card_uid)
		elif cost_type == "MOVE_SOURCE_TO_ZONE":
			var source_zone := _parse_zone(cost.get("to_zone", cost.get("to", UATypes.Zone.OUTSIDE)))
			if source_zone != -1:
				zone_manager.move_card(state, source_card_uid, source_zone, _cost_player_id(state, source_card_uid, context, cost))
				logs.append("Moved card %s to %s as a cost." % [source_card_uid, UATypes.zone_to_key(source_zone)])
		elif cost_type == "MOVE_SELECTED_CARDS":
			var selected_cards: Array = _ensure_array(context.get(str(cost.get("from_var", "")), []))
			var target_zone := _parse_zone(cost.get("to_zone", cost.get("to", UATypes.Zone.OUTSIDE)))
			var target_player_id := _cost_player_id(state, source_card_uid, context, cost)
			for card_uid_variant in selected_cards:
				var card_uid := str(card_uid_variant)
				if card_uid == "":
					continue
				zone_manager.move_card(state, card_uid, target_zone, target_player_id)
				logs.append("Moved card %s to %s as a cost." % [card_uid, UATypes.zone_to_key(target_zone)])
	return {"ok": true, "logs": logs}

func _cost_player_id(state: GameState, source_card_uid: String, context: Dictionary, cost: Dictionary) -> String:
	var player_mode := str(cost.get("player", "SOURCE"))
	var source_card = state.get_card(source_card_uid)
	if player_mode == "TARGET":
		return str(context.get("target_player_id", ""))
	if player_mode == "ACTIVE":
		return state.active_player_id
	return source_card.controller_player_id if source_card != null else str(context.get("source_player_id", ""))

func _resolve_target_set(state: GameState, source_card_uid: String, target: Dictionary, context: Dictionary) -> Array:
	return _target_selector.resolve_target_set(state, source_card_uid, target, context)

func _resolve_owner_player_ids(state: GameState, owner_mode: String, source_player_id: String) -> Array:
	return _target_selector.resolve_owner_player_ids(state, owner_mode, source_player_id)

func _matches_play_permission_modifier(state: GameState, modifier: Dictionary, context: Dictionary) -> bool:
	var source_card_uid := _get_source_card_uid(modifier)
	if not _matches_filter_list(state, modifier.get("while", []), context, str(context.get("played_card_uid", "")), source_card_uid):
		return false
	var from_zone := _parse_zone(modifier.get("from_zone", -1))
	if from_zone != -1 and int(context.get("played_from_zone", -2)) != from_zone:
		return false
	return _matches_filter_list(state, modifier.get("filters", []), context, str(context.get("played_card_uid", "")), source_card_uid)

func _matches_filter_list(state: GameState, filters: Array, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	return _requirement_matcher.matches_filter_list(state, filters, context, candidate_card_uid, source_card_uid)

func _matches_filter(state: GameState, filter_variant, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	return _requirement_matcher.matches_filter(state, filter_variant, context, candidate_card_uid, source_card_uid)

func _requirements_met(state: GameState, source_card_uid: String, requirements: Array, context: Dictionary, candidate_card_uid := "") -> bool:
	return _requirement_matcher.all_met(state, source_card_uid, requirements, context, candidate_card_uid)

func _matches_requirement(state: GameState, requirement_variant, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	return _requirement_matcher.matches(state, requirement_variant, context, candidate_card_uid, source_card_uid)

func _resolve_numeric_value(state: GameState, provider_variant, context: Dictionary, source_card_uid: String, candidate_card_uid := "") -> int:
	if provider_variant is int or provider_variant is float:
		return int(provider_variant)
	if provider_variant is String:
		return int(provider_variant)
	if not (provider_variant is Dictionary):
		return 0
	var provider: Dictionary = provider_variant
	var provider_type := str(provider.get("type", "FIXED"))
	if provider_type == "FIXED":
		return int(provider.get("value", 0))
	if provider_type == "CONDITIONAL":
		var when_requirements: Array = provider.get("when", [])
		if _requirements_met(state, source_card_uid, when_requirements, context, candidate_card_uid):
			return _resolve_numeric_value(state, provider.get("then", provider.get("value", 0)), context, source_card_uid, candidate_card_uid)
		return _resolve_numeric_value(state, provider.get("default", 0), context, source_card_uid, candidate_card_uid)
	if provider_type == "CONTROLLER_OTHER_FIELD_UNIQUE_NAME_COUNT_MULTIPLIED":
		var source_card = state.get_card(source_card_uid)
		if source_card == null:
			return 0
		var player = state.get_player(source_card.controller_player_id)
		if player == null:
			return 0
		var trait_value := str(provider.get("trait", ""))
		var unique_names: Dictionary = {}
		for zone_cards in [player.front_line, player.energy_line]:
			for card_uid_variant in zone_cards:
				var card_uid := str(card_uid_variant)
				if card_uid == "" or card_uid == source_card_uid:
					continue
				var field_card = state.get_card(card_uid)
				if field_card == null:
					continue
				var field_def = state.get_card_def(field_card.def_id)
				if field_def == null:
					continue
				if trait_value != "" and not field_def.traits.has(trait_value):
					continue
				unique_names[field_def.name] = true
		return unique_names.size() * int(provider.get("multiplier", 1))
	if provider_type == "FIXED_PLUS_CONTROLLER_FIELD_CARD_COUNT_MULTIPLIED":
		var source_card_fixed = state.get_card(source_card_uid)
		if source_card_fixed == null:
			return int(provider.get("value", 0))
		var fixed_player = state.get_player(source_card_fixed.controller_player_id)
		if fixed_player == null:
			return int(provider.get("value", 0))
		var trait_fixed := str(provider.get("trait", ""))
		var count := 0
		for zone_cards in [fixed_player.front_line, fixed_player.energy_line]:
			for fixed_uid_variant in zone_cards:
				var fixed_uid := str(fixed_uid_variant)
				if fixed_uid == "":
					continue
				var fixed_card = state.get_card(fixed_uid)
				var fixed_def = state.get_card_def(fixed_card.def_id) if fixed_card != null else null
				if fixed_def == null:
					continue
				if trait_fixed != "" and not fixed_def.traits.has(trait_fixed):
					continue
				count += 1
		return int(provider.get("value", 0)) + count * int(provider.get("multiplier", 1))
	if provider_type == "PLAYER_ZONE_CARD_COUNT_MULTIPLIED":
		var source_card_counted = state.get_card(source_card_uid)
		var player_mode := str(provider.get("player", "SELF"))
		var player_id := ""
		if player_mode == "SELF":
			player_id = source_card_counted.controller_player_id if source_card_counted != null else str(context.get("source_player_id", ""))
		elif player_mode == "OPPONENT":
			player_id = PlayerUtils.opponent_of(source_card_counted.controller_player_id) if source_card_counted != null else ""
		else:
			player_id = str(context.get("target_player_id", context.get("source_player_id", "")))
		var count_player = state.get_player(player_id)
		if count_player == null:
			return 0
		var total := 0
		for zone_variant in provider.get("zones", []):
			var zone_cards = _zone_cards_for_player(count_player, str(zone_variant))
			for zone_card_uid_variant in zone_cards:
				var zone_card_uid := str(zone_card_uid_variant)
				if zone_card_uid == "":
					continue
				var zone_card = state.get_card(zone_card_uid)
				var zone_def = state.get_card_def(zone_card.def_id) if zone_card != null else null
				if zone_def == null:
					continue
				var required_card_type := str(provider.get("card_type", ""))
				if required_card_type != "" and UATypes.card_type_to_text(zone_def.card_type) != required_card_type:
					continue
				total += 1
		return total * int(provider.get("multiplier", 1))
	if provider_type == "FIXED_PLUS_CONTROLLER_FRONT_LINE_ENERGY_LTE_COUNT_MULTIPLIED":
		var source_card_front = state.get_card(source_card_uid)
		if source_card_front == null:
			return int(provider.get("value", 0))
		var front_player = state.get_player(source_card_front.controller_player_id)
		if front_player == null:
			return int(provider.get("value", 0))
		var count_front := 0
		for front_uid_variant in front_player.front_line:
			var front_uid := str(front_uid_variant)
			if front_uid == "":
				continue
			var front_card = state.get_card(front_uid)
			var front_def = state.get_card_def(front_card.def_id) if front_card != null else null
			if front_def == null:
				continue
			if int(front_def.cost_energy) > int(provider.get("cost_energy_lte", 0)):
				continue
			count_front += 1
		return int(provider.get("value", 0)) + count_front * int(provider.get("multiplier", 1))
	if provider_type == "SOURCE_BP_MINUS":
		var source_bp_card = state.get_card(source_card_uid)
		if source_bp_card == null:
			return 0
		return int(source_bp_card.current_bp) - int(provider.get("value", 0))
	return int(provider.get("value", 0))

func _apply_energy_delta_map(cost_map: Dictionary, delta_map: Dictionary) -> Dictionary:
	var result: Dictionary = cost_map.duplicate(true)
	for color_variant in delta_map.keys():
		var color := str(color_variant)
		var base_value := int(result.get(color, 0))
		result[color] = maxi(0, base_value + int(delta_map.get(color_variant, 0)))
	return result

func _apply_energy_scalar_delta(cost_map: Dictionary, delta: int) -> Dictionary:
	var result: Dictionary = cost_map.duplicate(true)
	for color_variant in result.keys():
		var color := str(color_variant)
		result[color] = maxi(0, int(result.get(color, 0)) + delta)
	return result

func _enqueue_target_selection(state: GameState, source_card_uid: String, effect: Dictionary, selected_var: String, target: Dictionary, candidates: Array, context: Dictionary, remaining_steps: Array, resume_as_effect := false, ui_meta: Dictionary = {}) -> bool:
	return _target_selector.enqueue_target_selection(state, source_card_uid, effect, selected_var, target, candidates, context, remaining_steps, resume_as_effect, ui_meta)

func _enqueue_value_selection(state: GameState, source_card_uid: String, effect: Dictionary, selected_var: String, choices: Array[Dictionary], candidate_values: Array[String], min_count: int, max_count: int, context: Dictionary, remaining_steps: Array, resume_as_effect := false) -> bool:
	return _target_selector.enqueue_value_selection(state, source_card_uid, effect, selected_var, choices, candidate_values, min_count, max_count, context, remaining_steps, resume_as_effect)

func _format_target_choice_label(card_def) -> String:
	return _target_selector._format_target_choice_label(card_def)

func _format_energy_cost_text(energy_map: Dictionary) -> String:
	return _target_selector._format_energy_cost_text(energy_map)

func _register_preview_ui_meta(context: Dictionary, preview_var: String, meta: Dictionary) -> void:
	_target_selector.register_preview_ui_meta(context, preview_var, meta)

func _get_preview_ui_meta(context: Dictionary, preview_var: String) -> Dictionary:
	return _target_selector.get_preview_ui_meta(context, preview_var)

func _build_preview_pick_ui_meta(target: Dictionary, context: Dictionary) -> Dictionary:
	return _target_selector.build_preview_pick_ui_meta(target, context)

func _build_preview_reorder_ui_meta(source_var: String, candidates: Array, context: Dictionary) -> Dictionary:
	return _target_selector.build_preview_reorder_ui_meta(source_var, candidates, context)

func _normalize_selection_payload(selected_values, max_count: int) -> Array:
	return _target_selector.normalize_selection_payload(selected_values, max_count)

func _validate_selection_payload(state: GameState, normalized: Array, queued_effect: Dictionary) -> String:
	return _target_selector.validate_selection_payload(state, normalized, queued_effect)

func _array_without_values(source: Array, values_to_remove: Array) -> Array:
	var result: Array = []
	var remaining: Array = []
	for value_variant in values_to_remove:
		remaining.append(str(value_variant))
	for source_variant in source:
		var source_value := str(source_variant)
		var remove_index := remaining.find(source_value)
		if remove_index != -1:
			remaining.remove_at(remove_index)
			continue
		result.append(source_variant)
	return result

func _ensure_array(value) -> Array:
	if value is Array:
		return value
	if value == null or str(value) == "":
		return []
	return [value]

func _zone_cards_for_player(player, zone_key: String) -> Array:
	match zone_key:
		"FRONT_LINE":
			return player.front_line
		"ENERGY_LINE":
			return player.energy_line
		"HAND":
			return player.hand
		"LIFE":
			return player.life
		"OUTSIDE":
			return player.outside
		"REMOVED":
			return player.removed
		"DECK":
			return player.deck
	return []

func _is_modifier_active(state: GameState, modifier: Dictionary) -> bool:
	var source_card_uid := _get_source_card_uid(modifier)
	var source_card = state.get_card(source_card_uid)
	if source_card == null:
		return false
	return _matches_filter_list(state, modifier.get("while", []), {}, "", source_card_uid)

func _filter_unexpired_modifiers(modifiers: Array, player_id: String, expiry: String) -> Array:
	var keep: Array = []
	for modifier_variant in modifiers:
		var modifier: Dictionary = modifier_variant
		if str(modifier.get("expires", "")) == expiry and str(modifier.get("owner_player_id", "")) == player_id:
			continue
		keep.append(modifier)
	return keep

func _revert_expired_temporary_modifiers(state: GameState, player_id: String, expiry: String) -> void:
	for modifier_variant in state.static_modifiers:
		var modifier: Dictionary = modifier_variant
		if str(modifier.get("expires", "")) != expiry:
			continue
		if str(modifier.get("owner_player_id", "")) != player_id:
			continue
		var target_uid := str(modifier.get("target_uid", ""))
		var target_card = state.get_card(target_uid)
		if target_card == null:
			continue
		match str(modifier.get("modifier_type", "")):
			"TEMP_BP":
				target_card.current_bp -= int(modifier.get("value", 0))
			"TEMP_KEYWORD":
				_remove_runtime_keyword(target_card, str(modifier.get("keyword", "")))

func _add_runtime_keyword(card: CardInstance, keyword: String) -> void:
	if keyword == "":
		return
	var temp_keywords: Array = card.flags.get("temp_keywords", [])
	var temp_keyword_counts: Dictionary = card.flags.get("temp_keyword_counts", {})
	var current_count := int(temp_keyword_counts.get(keyword, 0))
	temp_keyword_counts[keyword] = current_count + 1
	if current_count <= 0 and not temp_keywords.has(keyword):
		temp_keywords.append(keyword)
	card.flags["temp_keywords"] = temp_keywords
	card.flags["temp_keyword_counts"] = temp_keyword_counts

func _context_value_is_non_empty(value) -> bool:
	if value == null:
		return false
	if value is Array:
		return not value.is_empty()
	return str(value) != ""

func _format_modifier_expiry_text(expires: String) -> String:
	match expires:
		"UNTIL_NEXT_SELF_TURN_START":
			return "until the next turn start of its source controller"
		_:
			return "until end of turn"

func _card_energy_cost_total(card_def) -> int:
	if card_def == null:
		return 0
	var total := 0
	for amount_variant in card_def.cost_energy.values():
		total += int(amount_variant)
	return total

func _card_matches_color(card_def, color: String) -> bool:
	if card_def == null or color == "":
		return false
	var normalized := color.to_upper()
	return int(card_def.cost_energy.get(normalized, 0)) > 0 or int(card_def.energy_provided.get(normalized, 0)) > 0

func _play_selected_cards(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary) -> Array[String]:
	var logs: Array[String] = []
	if rules_engine == null:
		logs.append("Play selected cards failed: missing rules engine.")
		return logs
	var selected_cards: Array = _ensure_array(context.get(str(step.get("from_var", "")), []))
	var target_zone := _parse_zone(step.get("to_zone", step.get("to", UATypes.Zone.FRONT_LINE)))
	var target_state := _parse_card_state(step.get("state", UATypes.CardState.RESTED))
	var ignore_play_timing := bool(step.get("ignore_play_timing", true))
	for card_uid_variant in selected_cards:
		var card_uid := str(card_uid_variant)
		if card_uid == "":
			continue
		var card = state.get_card(card_uid)
		if card == null:
			continue
		var entered_from_zone: int = int(card.zone)
		var controller_player_id: String = card.controller_player_id
		var play_modifiers := preview_play_modifiers(state, controller_player_id, card_uid, {
			"target_player_id": controller_player_id,
			"target_zone": target_zone,
		})
		if bool(step.get("ignore_play_costs", false)):
			play_modifiers["cost_ap"] = 0
			play_modifiers["cost_energy"] = {}
		if bool(step.get("allow_current_zone", false)):
			play_modifiers["allow_current_zone"] = true
		var validation: Dictionary = rules_engine.can_play_card(state, controller_player_id, card_uid, target_zone, play_modifiers, {
			"ignore_play_timing": ignore_play_timing,
		})
		if not bool(validation.get("ok", false)):
			logs.append("Play selected card failed: %s." % str(validation.get("reason", "unknown")))
			continue
		var player = state.get_player(controller_player_id)
		if player == null:
			continue
		var effective_cost_ap := int(validation.get("cost_ap", play_modifiers.get("cost_ap", 0)))
		if not bool(step.get("ignore_play_costs", false)):
			zone_manager.spend_ap(player, effective_cost_ap)
		zone_manager.move_card(state, card_uid, target_zone, controller_player_id)
		card.state = target_state
		card.flags["entered_this_turn"] = true
		card.flags["entered_from_zone_this_turn"] = entered_from_zone
		card.flags["entered_via_raid"] = false
		var card_def = state.get_card_def(card.def_id)
		logs.append("%s plays %s to %s." % [
			controller_player_id,
			card_def.name if card_def != null else card_uid,
			UATypes.zone_to_key(target_zone),
		])
		logs.append_array(resolve_trigger(card_uid, UATypes.TriggerType.ON_ENTER, state, {"target_player_id": controller_player_id}))
		commit_play_modifiers(state, play_modifiers)
	return logs

func _remove_runtime_keyword(card: CardInstance, keyword: String) -> void:
	if keyword == "":
		return
	var temp_keywords: Array = card.flags.get("temp_keywords", [])
	var temp_keyword_counts: Dictionary = card.flags.get("temp_keyword_counts", {})
	var current_count := int(temp_keyword_counts.get(keyword, 0))
	if current_count <= 1:
		temp_keyword_counts.erase(keyword)
		temp_keywords.erase(keyword)
	else:
		temp_keyword_counts[keyword] = current_count - 1
	card.flags["temp_keywords"] = temp_keywords
	card.flags["temp_keyword_counts"] = temp_keyword_counts

func _resolve_step_target_uid(effect: Dictionary, context: Dictionary, source_card_uid: String) -> String:
	if effect.has("target_uid"):
		var explicit_target_uid := str(effect.get("target_uid", source_card_uid))
		if explicit_target_uid == "SOURCE_CARD":
			return source_card_uid
		return explicit_target_uid
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

func _parse_card_state(value) -> int:
	if value is int:
		return int(value)
	var state_name := str(value)
	if state_name == "ACTIVE" or state_name == "active":
		return UATypes.CardState.ACTIVE
	if state_name == "RESTED" or state_name == "rested":
		return UATypes.CardState.RESTED
	return UATypes.CardState.RESTED

func _apply_victory(state: GameState, result: Dictionary) -> void:
	state.winner_player_id = str(result.get("winner", ""))
	state.loser_player_id = str(result.get("loser", ""))

func _is_effect_enabled_for_card(source_card, effect: Dictionary) -> bool:
	var effect_box := str(effect.get("effect_box", ""))
	if effect_box == "RAID_INNER":
		return bool(source_card.flags.get("entered_via_raid", false))
	return true

func _can_resolve_effect_once_per_turn(state: GameState, source_card_uid: String, effect: Dictionary) -> bool:
	if not bool(effect.get("once_per_turn", false)):
		return true
	var event_name := str(effect.get("trigger", effect.get("timing", {}).get("event", "")))
	if event_name == "MAIN_ACTIVATE":
		return true
	var source_card = state.get_card(source_card_uid)
	if source_card == null:
		return false
	var used_ids: Array = source_card.flags.get("used_triggered_ability_ids_this_turn", [])
	return not used_ids.has(str(effect.get("id", "")))

func _mark_effect_once_per_turn_if_needed(state: GameState, source_card_uid: String, effect: Dictionary) -> void:
	if not bool(effect.get("once_per_turn", false)):
		return
	var event_name := str(effect.get("trigger", effect.get("timing", {}).get("event", "")))
	if event_name == "MAIN_ACTIVATE":
		return
	var effect_id := str(effect.get("id", ""))
	var source_card = state.get_card(source_card_uid)
	if source_card == null or effect_id == "":
		return
	var used_ids: Array = source_card.flags.get("used_triggered_ability_ids_this_turn", [])
	if not used_ids.has(effect_id):
		used_ids.append(effect_id)
	source_card.flags["used_triggered_ability_ids_this_turn"] = used_ids

func _unmark_effect_once_per_turn_if_needed(state: GameState, source_card_uid: String, effect: Dictionary) -> void:
	if not bool(effect.get("once_per_turn", false)):
		return
	var event_name := str(effect.get("trigger", effect.get("timing", {}).get("event", "")))
	if event_name == "MAIN_ACTIVATE":
		return
	var effect_id := str(effect.get("id", ""))
	var source_card = state.get_card(source_card_uid)
	if source_card == null or effect_id == "":
		return
	var used_ids: Array = source_card.flags.get("used_triggered_ability_ids_this_turn", [])
	used_ids.erase(effect_id)
	source_card.flags["used_triggered_ability_ids_this_turn"] = used_ids

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

func _get_source_card_uid(modifier: Dictionary) -> String:
	return str(modifier.get("source_card_uid", ""))
