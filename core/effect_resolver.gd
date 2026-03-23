extends RefCounted
class_name EffectResolver

const UATypes = preload("res://core/ua_types.gd")
const ZoneManager = preload("res://core/zone_manager.gd")
const VictoryChecker = preload("res://core/victory_checker.gd")
const GameState = preload("res://data/game_state.gd")
const CardInstance = preload("res://data/card_instance.gd")

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
		return ["Target selection failed: not enough targets."]
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
	_revert_expired_temporary_modifiers(state, ending_player_id)
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
	if state.pending_life_triggers.is_empty() and state.pending_decisions.is_empty():
		logs.append_array(_finalize_pending_life_damage(state))
	return logs

func finalize_pending_life_damage(state: GameState) -> Array[String]:
	return _finalize_pending_life_damage(state)

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
	var requirements: Array = effect.get("requirements", effect.get("condition", []))
	if not _requirements_met(state, source_card_uid, requirements, context):
		return logs
	var target_result := _prepare_effect_targets(state, source_card_uid, effect, context)
	logs.append_array(target_result.get("logs", []))
	if bool(target_result.get("paused", false)) or not bool(target_result.get("ok", true)):
		return logs
	var cost_result := _pay_effect_costs(state, source_card_uid, effect.get("costs", []), context)
	logs.append_array(cost_result.get("logs", []))
	if not bool(cost_result.get("ok", true)):
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
	var logs: Array[String] = []
	for step_index in range(steps.size()):
		var step: Dictionary = steps[step_index]
		var step_result := _execute_step(state, source_card_uid, step, context, steps.slice(step_index + 1), effect)
		logs.append_array(step_result.get("logs", []))
		if bool(step_result.get("paused", false)):
			return {"logs": logs, "paused": true}
	return {"logs": logs, "paused": false}

func _execute_step(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary, remaining_steps: Array = [], effect: Dictionary = {}) -> Dictionary:
	var step_type := str(step.get("type", ""))
	if step_type == "SELECT_TARGETS":
		var target: Dictionary = step.get("target", {})
		var selected := _resolve_target_set(state, source_card_uid, target, context)
		var selected_var := str(step.get("var", "selected_targets"))
		if bool(target.get("manual", false)) or str(target.get("selection_mode", "AUTO")) == "MANUAL":
			if context.has(selected_var):
				return {"logs": [], "paused": false}
			if _enqueue_target_selection(state, source_card_uid, effect, selected_var, target, selected, context, remaining_steps):
				return {"logs": [], "paused": true}
		if int(target.get("max", selected.size())) == 1:
			context[selected_var] = selected[0] if not selected.is_empty() else ""
		else:
			context[selected_var] = selected
		return {"logs": [], "paused": false}
	if step_type == "MOVE_SELECTED_CARDS":
		var move_logs: Array[String] = []
		var selected_cards: Array = _ensure_array(context.get(str(step.get("from_var", "")), []))
		var to_zone := _parse_zone(step.get("to_zone", step.get("to", UATypes.Zone.OUTSIDE)))
		var target_player_id := str(step.get("target_player_id", context.get("target_player_id", "")))
		for card_uid_variant in selected_cards:
			var card_uid := str(card_uid_variant)
			if card_uid == "":
				continue
			zone_manager.move_card(state, card_uid, to_zone, target_player_id)
			move_logs.append("Moved card %s to %s." % [card_uid, UATypes.zone_to_key(to_zone)])
		return {"logs": move_logs, "paused": false}
	if step_type == "MOVE_TOP_DECK_TO_LIFE":
		var life_logs: Array[String] = []
		var player_id := str(context.get("target_player_id", context.get("source_player_id", "")))
		var player = state.get_player(player_id)
		if player != null and not player.deck.is_empty():
			var top_uid: String = player.deck.pop_front()
			player.life.append(top_uid)
			var top_card = state.get_card(top_uid)
			if top_card != null:
				top_card.zone = UATypes.Zone.LIFE
			life_logs.append("%s moves the top card of the deck to life." % player_id)
		return {"logs": life_logs, "paused": false}
	if step_type == "ACTIVATE_AP_SLOTS":
		var ap_logs: Array[String] = []
		var ap_player_id := str(context.get("target_player_id", context.get("source_player_id", "")))
		var ap_player = state.get_player(ap_player_id)
		if ap_player != null:
			var remaining := int(step.get("value", 1))
			for slot in ap_player.ap_area:
				if remaining <= 0:
					break
				if not bool(slot.get("active", false)):
					slot["active"] = true
					remaining -= 1
			ap_logs.append("%s readies up to %d AP slot(s)." % [ap_player_id, int(step.get("value", 1))])
		return {"logs": ap_logs, "paused": false}
	if step_type == "LIFE_TRIGGER_RAID_CHOICE":
		return {"logs": _enqueue_life_trigger_raid_choice(state, source_card_uid), "paused": false}
	if step_type == "ADD_TEMP_BP_MODIFIER":
		return {"logs": _apply_temporary_bp_modifier(state, source_card_uid, step, context), "paused": false}
	if step_type == "ADD_TEMP_KEYWORD":
		return {"logs": _apply_temporary_keyword_modifier(state, source_card_uid, step, context), "paused": false}
	if step_type == "FOR_EACH":
		var logs: Array[String] = []
		var values: Array = _ensure_array(context.get(str(step.get("items_var", "")), []))
		var current_var := str(step.get("current_var", "current_item"))
		for item in values:
			context[current_var] = item
			var nested_result := _execute_steps(state, source_card_uid, step.get("steps", []), context, effect)
			logs.append_array(nested_result.get("logs", []))
			if bool(nested_result.get("paused", false)):
				return {"logs": logs, "paused": true}
		context.erase(current_var)
		return {"logs": logs, "paused": false}
	if step_type == "REGISTER_DELAYED_EFFECT":
		_register_delayed_effect(state, source_card_uid, step)
		return {"logs": [], "paused": false}
	if step_type == "REGISTER_STATIC_MODIFIER":
		_register_static_modifier(state, source_card_uid, step)
		return {"logs": [], "paused": false}
	return {"logs": _execute_operation(state, source_card_uid, step, context), "paused": false}

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
	if effect_type == "MOVE_CARD":
		var move_uid := _resolve_step_target_uid(effect, context, source_card_uid)
		var move_to_zone := _parse_zone(effect.get("to_zone", effect.get("to", UATypes.Zone.OUTSIDE)))
		if move_uid != "":
			zone_manager.move_card(state, move_uid, move_to_zone, str(context.get("target_player_id", "")))
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

func _apply_temporary_bp_modifier(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary) -> Array[String]:
	var logs: Array[String] = []
	var target_uid := _resolve_step_target_uid(step, context, source_card_uid)
	var target_card = state.get_card(target_uid)
	if target_card == null:
		return logs
	var delta := int(step.get("value", 0))
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
	state.static_modifiers.append({
		"id": state.next_runtime_id("temp_keyword"),
		"source_card_uid": source_card_uid,
		"owner_player_id": source_card.controller_player_id if source_card != null else str(context.get("source_player_id", "")),
		"modifier_type": "TEMP_KEYWORD",
		"target_uid": target_uid,
		"keyword": keyword,
		"expires": str(step.get("expires", "END_OF_TURN")),
	})
	logs.append("%s gains %s until end of turn." % [target_uid, keyword])
	return logs

func _enqueue_life_trigger_raid_choice(state: GameState, source_card_uid: String) -> Array[String]:
	var logs: Array[String] = []
	var source_card: CardInstance = state.get_card(source_card_uid)
	if source_card == null:
		return logs
	var source_def = state.get_card_def(source_card.def_id)
	var owner_player_id: String = source_card.controller_player_id
	var raid_enabled := false
	var raid_reason := "raid_not_available"
	if source_def != null and str(source_def.special_play_rule.get("type", "")) == "RAID":
		raid_reason = "no_legal_raid_target"
		var player = state.get_player(owner_player_id)
		var required_name := str(source_def.special_play_rule.get("raid_target_name", ""))
		if player != null:
			for zone_cards in [player.front_line, player.energy_line]:
				for candidate_uid_variant in zone_cards:
					var candidate_card = state.get_card(str(candidate_uid_variant))
					var candidate_def = state.get_card_def(candidate_card.def_id) if candidate_card != null else null
					if candidate_card == null or candidate_def == null:
						continue
					if candidate_def.card_type != UATypes.CardType.CHARACTER:
						continue
					if required_name != "" and candidate_def.name != required_name:
						continue
					raid_enabled = true
					raid_reason = ""
					break
				if raid_enabled:
					break
	state.pending_decisions.append({
		"type": "LIFE_TRIGGER_RAID_CHOICE",
		"owner_player_id": owner_player_id,
		"source_card_uid": source_card_uid,
		"choices": [
			{"label": "Add To Hand", "value": "ADD_TO_HAND", "enabled": true, "reason": ""},
			{"label": "Raid Now", "value": "RAID_NOW", "enabled": raid_enabled, "reason": raid_reason},
		],
		"context": {},
	})
	logs.append("%s may add the card to hand or raid immediately." % owner_player_id)
	return logs

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
			if _enqueue_target_selection(state, source_card_uid, effect, selected_var, target, selected, context, [], true):
				return {"ok": true, "logs": [], "paused": true}
		if max_count == 1:
			context[selected_var] = selected[0] if not selected.is_empty() else ""
		else:
			context[selected_var] = selected
	return {"ok": true, "logs": [], "paused": false}

func _target_from_spec(target_spec: Dictionary) -> Dictionary:
	var candidate: Dictionary = target_spec.get("candidate", {})
	var select: Dictionary = target_spec.get("select", {})
	return {
		"type": "CARD_SET",
		"owner": str(candidate.get("owner", "SELF")),
		"zones": candidate.get("zones", []),
		"filters": candidate.get("filters", []).duplicate(true),
		"requirements": candidate.get("requirements", []).duplicate(true),
		"min": int(select.get("min", 0)),
		"max": int(select.get("max", 1)),
		"selection_mode": str(select.get("mode", "AUTO")),
		"manual": str(select.get("mode", "AUTO")) == "MANUAL",
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
	var result: Array = []
	if str(target.get("type", "")) != "CARD_SET":
		return result
	var source_card = state.get_card(source_card_uid)
	if source_card == null:
		return result
	var zones: Array = []
	if target.has("zones"):
		for zone_variant in target.get("zones", []):
			zones.append(_parse_zone(zone_variant))
	else:
		zones.append(_parse_zone(target.get("from_zone", UATypes.Zone.OUTSIDE)))
	var owner_mode := str(target.get("owner", "SELF"))
	var owner_player_ids := _resolve_owner_player_ids(state, owner_mode, source_card.controller_player_id)
	var filters: Array = target.get("filters", [])
	var requirements: Array = target.get("requirements", [])
	for player_id in owner_player_ids:
		var player = state.get_player(player_id)
		if player == null:
			continue
		for zone in zones:
			var zone_cards = zone_manager.get_zone_array(player, zone)
			if zone_cards == null:
				continue
			for card_uid in zone_cards:
				if not _matches_filter_list(state, filters, context, str(card_uid), source_card_uid):
					continue
				if not _requirements_met(state, source_card_uid, requirements, context, str(card_uid)):
					continue
				result.append(card_uid)
	var min_count := int(target.get("min", 0))
	if result.size() < min_count:
		return []
	var max_count := int(target.get("max", result.size()))
	if (bool(target.get("manual", false)) or str(target.get("selection_mode", "AUTO")) == "MANUAL"):
		return result
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

func _requirements_met(state: GameState, source_card_uid: String, requirements: Array, context: Dictionary, candidate_card_uid := "") -> bool:
	for requirement_variant in requirements:
		if not _matches_requirement(state, requirement_variant, context, candidate_card_uid, source_card_uid):
			return false
	return true

func _matches_requirement(state: GameState, requirement_variant, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var requirement: Dictionary = requirement_variant
	var requirement_type := str(requirement.get("type", ""))
	var candidate_card = state.get_card(candidate_card_uid)
	var candidate_def = null
	if candidate_card != null:
		candidate_def = state.get_card_def(candidate_card.def_id)
	var source_card = state.get_card(source_card_uid)
	var source_def = null
	if source_card != null:
		source_def = state.get_card_def(source_card.def_id)
	if requirement_type == "":
		return true
	if requirement_type == "OR":
		for nested in requirement.get("requirements", requirement.get("filters", [])):
			if _matches_requirement(state, nested, context, candidate_card_uid, source_card_uid):
				return true
		return false
	if requirement_type == "CONTROLLER_HAS_NAME_IN_FIELD":
		if source_card == null:
			return false
		var player = state.get_player(source_card.controller_player_id)
		if player == null:
			return false
		var required_name := str(requirement.get("value", ""))
		for zone_cards in [player.front_line, player.energy_line]:
			for card_uid in zone_cards:
				var field_card = state.get_card(str(card_uid))
				if field_card == null:
					continue
				var field_def = state.get_card_def(field_card.def_id)
				if field_def != null and field_def.name == required_name:
					return true
		return false
	if requirement_type == "CARD_BP_LTE":
		var compare_card = candidate_card if candidate_card != null else source_card
		if compare_card == null:
			return false
		return int(compare_card.current_bp) <= int(requirement.get("value", 0))
	if requirement_type == "PLAYER_LIFE_IS_EMPTY":
		var player_mode := str(requirement.get("player", "SELF"))
		var player_id := str(context.get("target_player_id", context.get("source_player_id", "")))
		if player_mode == "SELF" and source_card != null:
			player_id = source_card.controller_player_id
		elif player_mode == "OPPONENT" and source_card != null:
			player_id = _opponent_of(source_card.controller_player_id)
		var player_state = state.get_player(player_id)
		return player_state != null and player_state.life.is_empty()
	if requirement_type == "CARD_NAME_IS":
		return candidate_def != null and candidate_def.name == str(requirement.get("value", ""))
	if requirement_type == "CARD_HAS_TRAIT":
		return candidate_def != null and candidate_def.traits.has(str(requirement.get("value", "")))
	if requirement_type == "SOURCE_STATE_IS_ACTIVE":
		return source_card != null and source_card.state == UATypes.CardState.ACTIVE
	return _matches_filter(state, requirement, context, candidate_card_uid, source_card_uid)

func _enqueue_target_selection(state: GameState, source_card_uid: String, effect: Dictionary, selected_var: String, target: Dictionary, candidates: Array, context: Dictionary, remaining_steps: Array, resume_as_effect := false) -> bool:
	var min_count := int(target.get("min", 0))
	var max_count := int(target.get("max", 1))
	if candidates.is_empty():
		if min_count <= 0:
			context[selected_var] = [] if max_count != 1 else ""
			return false
		return false
	var source_card = state.get_card(source_card_uid)
	var owner_player_id = source_card.controller_player_id if source_card != null else str(context.get("source_player_id", ""))
	var resolution_id := state.next_runtime_id("target_select")
	var choices: Array[Dictionary] = []
	for candidate_uid_variant in candidates:
		var candidate_uid := str(candidate_uid_variant)
		var label := candidate_uid
		var candidate_card = state.get_card(candidate_uid)
		if candidate_card != null:
			var candidate_def = state.get_card_def(candidate_card.def_id)
			if candidate_def != null:
				label = candidate_def.name
		choices.append({"label": label, "value": candidate_uid})
	state.effect_queue.append({
		"kind": "TARGET_SELECTION",
		"id": resolution_id,
		"source_card_uid": source_card_uid,
		"target_var": selected_var,
		"min": min_count,
		"max": max_count,
		"steps": remaining_steps.duplicate(true),
		"context": context.duplicate(true),
		"effect": effect.duplicate(true),
		"resume_as_effect": resume_as_effect,
	})
	state.pending_decisions.append({
		"type": "ABILITY_TARGET_SELECTION",
		"owner_player_id": owner_player_id,
		"source_card_uid": source_card_uid,
		"resolution_id": resolution_id,
		"target_var": selected_var,
		"choices": choices,
		"min": min_count,
		"max": max_count,
	})
	return true

func _normalize_selection_payload(selected_values, max_count: int) -> Array:
	var result: Array = []
	if selected_values is Array:
		for value_variant in selected_values:
			var value := str(value_variant)
			if value != "":
				result.append(value)
	else:
		var single := str(selected_values)
		if single != "":
			result.append(single)
	if max_count >= 0 and result.size() > max_count:
		return result.slice(0, max_count)
	return result

func _ensure_array(value) -> Array:
	if value is Array:
		return value
	if value == null or str(value) == "":
		return []
	return [value]

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

func _revert_expired_temporary_modifiers(state: GameState, ending_player_id: String) -> void:
	for modifier_variant in state.static_modifiers:
		var modifier: Dictionary = modifier_variant
		if str(modifier.get("expires", "")) != "END_OF_TURN":
			continue
		if str(modifier.get("owner_player_id", "")) != ending_player_id:
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
