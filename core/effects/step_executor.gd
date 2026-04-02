extends RefCounted
class_name StepExecutor

## 步骤执行器 - 负责执行卡牌效果的步骤
## 从 effect_resolver.gd 提取，按字典分发模式重构

const UATypes = preload("res://core/ua_types.gd")
const GameState = preload("res://data/game_state.gd")
const CardInstance = preload("res://data/card_instance.gd")
const ZoneManager = preload("res://core/zone_manager.gd")
const RulesEngine = preload("res://core/rules_engine.gd")
const VictoryChecker = preload("res://core/victory_checker.gd")

var _zone_manager
var _victory_checker: VictoryChecker
var _rules_engine: RulesEngine
var _effect_resolver  # 回调引用

# 处理器字典
var _handlers: Dictionary = {}

func _init(zone_manager, victory_checker: VictoryChecker, rules_engine: RulesEngine, effect_resolver) -> void:
	_zone_manager = zone_manager
	_victory_checker = victory_checker
	_rules_engine = rules_engine
	_effect_resolver = effect_resolver
	_init_handlers()

func _init_handlers() -> void:
	_handlers = {
		"PREVIEW_TOP_DECK": _step_preview_top_deck,
		"SELECT_TARGETS": _step_select_targets,
		"SET_CONTEXT_FLAG": _step_set_context_flag,
		"SET_PLAYER_TURN_FLAG": _step_set_player_turn_flag,
		"SET_CARD_FLAG": _step_set_card_flag,
		"REMOVE_CONTEXT_VALUES": _step_remove_context_values,
		"MOVE_SELECTED_CARDS": _step_move_selected_cards,
		"PLAY_SELECTED_CARDS": _step_play_selected_cards,
		"REORDER_CONTEXT_CARDS": _step_reorder_context_cards,
		"MOVE_TOP_DECK_TO_LIFE": _step_move_top_deck_to_life,
		"ACTIVATE_AP_SLOTS": _step_activate_ap_slots,
		"LIFE_TRIGGER_RAID_CHOICE": _step_life_trigger_raid_choice,
		"ADD_TEMP_BP_MODIFIER": _step_add_temp_bp_modifier,
		"ADD_TEMP_KEYWORD": _step_add_temp_keyword,
		"SWAP_SOURCE_WITH_SELECTED_CARD": _step_swap_source_with_selected_card,
		"MOVE_SOURCE_STACKED_UNDER_TO_ZONE": _step_move_source_stacked_under_to_zone,
		"FOR_EACH": _step_for_each,
		"REGISTER_DELAYED_EFFECT": _step_register_delayed_effect,
		"REGISTER_STATIC_MODIFIER": _step_register_static_modifier,
		"STORE_CARD_INFO": _step_store_card_info,
	}

# ============================================================
# 公共入口
# ============================================================

func execute_steps(state: GameState, source_card_uid: String, steps: Array, context: Dictionary, effect: Dictionary = {}) -> Dictionary:
	var logs: Array[String] = []
	for step_index in range(steps.size()):
		var step: Dictionary = steps[step_index]
		var step_result := execute(state, source_card_uid, step, context, steps.slice(step_index + 1), effect)
		logs.append_array(step_result.get("logs", []))
		if bool(step_result.get("paused", false)):
			return {"logs": logs, "paused": true}
	return {"logs": logs, "paused": false}

func execute(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary, remaining_steps: Array = [], effect: Dictionary = {}) -> Dictionary:
	var step_type := str(step.get("type", ""))
	var step_requirements: Array = step.get("requirements", [])

	# 检查步骤需求
	if not step_requirements.is_empty():
		if _effect_resolver != null and not _effect_resolver._requirements_met(state, source_card_uid, step_requirements, context):
			return {"logs": [], "paused": false}

	# 字典分发
	var handler = _handlers.get(step_type)
	if handler != null:
		return handler.call(state, source_card_uid, step, context, remaining_steps, effect)

	# 回退到操作执行
	if _effect_resolver != null:
		return {"logs": _effect_resolver._execute_operation(state, source_card_uid, step, context), "paused": false}
	return {"logs": [], "paused": false}

# ============================================================
# 步骤处理器
# ============================================================

func _step_preview_top_deck(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary, remaining_steps: Array, effect: Dictionary) -> Dictionary:
	var preview_logs: Array[String] = []
	var player_mode := str(step.get("player", "SOURCE"))
	var source_card = state.get_card(source_card_uid)
	var player_id: String = str(context.get("source_player_id", ""))
	if source_card != null:
		player_id = source_card.controller_player_id
	if player_mode == "TARGET":
		player_id = str(context.get("target_player_id", player_id))
	elif player_mode == "ACTIVE":
		player_id = state.active_player_id
	var player = state.get_player(player_id)
	var preview_var := str(step.get("var", "preview_cards"))
	var count := int(step.get("count", 0))
	var preview_cards: Array = []
	if player != null and count > 0:
		var preview_count := mini(count, player.deck.size())
		preview_cards = player.deck.slice(0, preview_count)
	context[preview_var] = preview_cards
	_register_preview_ui_meta(context, preview_var, {
		"title": str(step.get("title", "查看牌堆顶")),
		"player_id": player_id,
		"count": count,
	})
	preview_logs.append("%s previews %d card(s) from the top of the deck." % [player_id, preview_cards.size()])
	return {"logs": preview_logs, "paused": false}

func _step_select_targets(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary, remaining_steps: Array, effect: Dictionary) -> Dictionary:
	var target: Dictionary = step.get("target", {})
	var selected := _resolve_target_set(state, source_card_uid, target, context)
	var selected_var := str(step.get("var", "selected_targets"))
	if bool(target.get("manual", false)) or str(target.get("selection_mode", "AUTO")) == "MANUAL":
		if context.has(selected_var):
			return {"logs": [], "paused": false}
		if _enqueue_target_selection(state, source_card_uid, effect, selected_var, target, selected, context, remaining_steps, false, _build_preview_pick_ui_meta(target, context)):
			return {"logs": [], "paused": true}
	if int(target.get("max", selected.size())) == 1:
		context[selected_var] = selected[0] if not selected.is_empty() else ""
	else:
		context[selected_var] = selected
	return {"logs": [], "paused": false}

func _step_set_context_flag(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary, remaining_steps: Array, effect: Dictionary) -> Dictionary:
	var flag_var := str(step.get("var", ""))
	if flag_var == "":
		return {"logs": [], "paused": false}
	if step.has("value"):
		context[flag_var] = bool(step.get("value", false))
		return {"logs": [], "paused": false}
	var source_var := str(step.get("from_var", ""))
	context[flag_var] = _context_value_is_non_empty(context.get(source_var, null))
	return {"logs": [], "paused": false}

func _step_set_player_turn_flag(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary, remaining_steps: Array, effect: Dictionary) -> Dictionary:
	var flag_name := str(step.get("flag", ""))
	if flag_name == "":
		return {"logs": [], "paused": false}
	var source_card = state.get_card(source_card_uid)
	var player_mode := str(step.get("player", "SOURCE"))
	var player_id := str(context.get("source_player_id", ""))
	if source_card != null:
		player_id = source_card.controller_player_id
	if player_mode == "TARGET":
		player_id = str(context.get("target_player_id", player_id))
	elif player_mode == "ACTIVE":
		player_id = state.active_player_id
	var flags: Dictionary = state.player_turn_flags.get(player_id, {})
	flags[flag_name] = step.get("value", true)
	state.player_turn_flags[player_id] = flags
	return {"logs": [], "paused": false}

func _step_set_card_flag(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary, remaining_steps: Array, effect: Dictionary) -> Dictionary:
	var flag_name := str(step.get("flag", ""))
	if flag_name == "":
		return {"logs": [], "paused": false}
	var target_uid := _resolve_step_target_uid(step, context, source_card_uid)
	var target_card = state.get_card(target_uid)
	if target_card == null:
		return {"logs": [], "paused": false}
	target_card.flags[flag_name] = step.get("value", true)
	return {"logs": [], "paused": false}

func _step_remove_context_values(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary, remaining_steps: Array, effect: Dictionary) -> Dictionary:
	var remove_source_var := str(step.get("from_var", ""))
	var remove_target_var := str(step.get("target_var", remove_source_var))
	var values_to_remove: Array = _ensure_array(context.get(remove_source_var, []))
	context[remove_target_var] = _array_without_values(_ensure_array(context.get(remove_target_var, [])), values_to_remove)
	return {"logs": [], "paused": false}

func _step_move_selected_cards(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary, remaining_steps: Array, effect: Dictionary) -> Dictionary:
	var move_logs: Array[String] = []
	var selected_cards: Array = _ensure_array(context.get(str(step.get("from_var", "")), []))
	var to_zone := _parse_zone(step.get("to_zone", step.get("to", UATypes.Zone.OUTSIDE)))
	var target_player_mode := str(step.get("target_player_mode", ""))
	var target_player_id := str(step.get("target_player_id", context.get("target_player_id", "")))
	if target_player_mode == "SOURCE":
		var move_source_card = state.get_card(source_card_uid)
		target_player_id = move_source_card.controller_player_id if move_source_card != null else str(context.get("source_player_id", target_player_id))
	elif target_player_mode == "TARGET":
		target_player_id = str(context.get("target_player_id", target_player_id))
	var to_position := str(step.get("to_position", context.get(str(step.get("to_position_from_var", "")), "")))
	for card_uid_variant in selected_cards:
		var card_uid := str(card_uid_variant)
		if card_uid == "":
			continue
		var per_card_target_player_id := target_player_id
		if target_player_mode == "CARD_CONTROLLER":
			var target_card = state.get_card(card_uid)
			per_card_target_player_id = target_card.controller_player_id if target_card != null else target_player_id
		_zone_manager.move_card(state, card_uid, to_zone, per_card_target_player_id, to_position)
		move_logs.append("Moved card %s to %s." % [card_uid, UATypes.zone_to_key(to_zone)])
	var remove_from_var := str(step.get("remove_from_var", ""))
	if remove_from_var != "":
		context[remove_from_var] = _array_without_values(_ensure_array(context.get(remove_from_var, [])), selected_cards)
	return {"logs": move_logs, "paused": false}

func _step_play_selected_cards(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary, remaining_steps: Array, effect: Dictionary) -> Dictionary:
	return {"logs": _play_selected_cards(state, source_card_uid, step, context), "paused": false}

func _step_reorder_context_cards(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary, remaining_steps: Array, effect: Dictionary) -> Dictionary:
	var source_var := str(step.get("from_var", "preview_cards"))
	var ordered_var := str(step.get("var", source_var))
	var candidates: Array = _ensure_array(context.get(source_var, []))
	if context.has(ordered_var):
		return {"logs": [], "paused": false}
	if candidates.is_empty():
		context[ordered_var] = []
		return {"logs": [], "paused": false}
	var reorder_target := {
		"type": "CONTEXT_CARD_SET",
		"source_var": source_var,
		"filters": step.get("filters", []).duplicate(true),
		"requirements": step.get("requirements", []).duplicate(true),
		"min": candidates.size(),
		"max": candidates.size(),
		"selection_mode": "MANUAL",
		"manual": true,
	}
	if _enqueue_target_selection(state, source_card_uid, effect, ordered_var, reorder_target, candidates, context, remaining_steps, false, _build_preview_reorder_ui_meta(source_var, candidates, context)):
		return {"logs": [], "paused": true}
	return {"logs": [], "paused": false}

func _step_move_top_deck_to_life(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary, remaining_steps: Array, effect: Dictionary) -> Dictionary:
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

func _step_activate_ap_slots(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary, remaining_steps: Array, effect: Dictionary) -> Dictionary:
	var ap_logs: Array[String] = []
	var ap_player_id := str(context.get("target_player_id", context.get("source_player_id", "")))
	var ap_player = state.get_player(ap_player_id)
	if ap_player != null:
		var remaining := int(step.get("value", 1))
		for i in range(ap_player.ap_area.size()):
			if remaining <= 0:
				break
			if bool(ap_player.ap_area[i].get("active", false)):
				continue
			ap_player.ap_area[i]["active"] = true
			remaining -= 1
		ap_logs.append("%s readies up to %d AP slot(s)." % [ap_player_id, int(step.get("value", 1))])
	return {"logs": ap_logs, "paused": false}

func _step_life_trigger_raid_choice(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary, remaining_steps: Array, effect: Dictionary) -> Dictionary:
	return {"logs": _enqueue_life_trigger_raid_choice(state, source_card_uid), "paused": false}

func _step_add_temp_bp_modifier(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary, remaining_steps: Array, effect: Dictionary) -> Dictionary:
	return {"logs": _apply_temporary_bp_modifier(state, source_card_uid, step, context), "paused": false}

func _step_add_temp_keyword(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary, remaining_steps: Array, effect: Dictionary) -> Dictionary:
	return {"logs": _apply_temporary_keyword_modifier(state, source_card_uid, step, context), "paused": false}

func _step_swap_source_with_selected_card(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary, remaining_steps: Array, effect: Dictionary) -> Dictionary:
	return {"logs": _swap_source_with_selected_card(state, source_card_uid, step, context), "paused": false}

func _step_move_source_stacked_under_to_zone(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary, remaining_steps: Array, effect: Dictionary) -> Dictionary:
	return {"logs": _move_source_stacked_under_to_zone(state, source_card_uid, step), "paused": false}

func _step_for_each(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary, remaining_steps: Array, effect: Dictionary) -> Dictionary:
	var logs: Array[String] = []
	var values: Array = _ensure_array(context.get(str(step.get("items_var", "")), []))
	var current_var := str(step.get("current_var", "current_item"))
	for item in values:
		context[current_var] = item
		var nested_result := execute_steps(state, source_card_uid, step.get("steps", []), context, effect)
		logs.append_array(nested_result.get("logs", []))
		if bool(nested_result.get("paused", false)):
			return {"logs": logs, "paused": true}
	context.erase(current_var)
	return {"logs": logs, "paused": false}

func _step_register_delayed_effect(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary, remaining_steps: Array, effect: Dictionary) -> Dictionary:
	_register_delayed_effect(state, source_card_uid, step)
	return {"logs": [], "paused": false}

func _step_register_static_modifier(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary, remaining_steps: Array, effect: Dictionary) -> Dictionary:
	_register_static_modifier(state, source_card_uid, step)
	return {"logs": [], "paused": false}

func _step_store_card_info(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary, remaining_steps: Array, effect: Dictionary) -> Dictionary:
	var card_uid := str(context.get(str(step.get("from_var", "")), ""))
	if card_uid == "":
		return {"logs": [], "paused": false}
	var card = state.get_card(card_uid)
	var card_def = state.get_card_def(card.def_id) if card != null else null
	var info_var := str(step.get("var", "stored_card_info"))
	context[info_var] = {
		"uid": card_uid,
		"card_type": UATypes.card_type_to_text(card_def.card_type) if card_def != null else "",
		"name": card_def.name if card_def != null else "",
	}
	return {"logs": [], "paused": false}

# ============================================================
# 辅助函数 - 目标选择
# ============================================================

func _resolve_target_set(state: GameState, source_card_uid: String, target: Dictionary, context: Dictionary) -> Array:
	var result: Array = []
	var target_type := str(target.get("type", ""))
	if target_type == "CONTEXT_CARD_SET":
		var source_var := str(target.get("source_var", ""))
		var context_candidates: Array = _ensure_array(context.get(source_var, []))
		var filters: Array = target.get("filters", [])
		var requirements: Array = target.get("requirements", [])
		for candidate_uid_variant in context_candidates:
			var candidate_uid := str(candidate_uid_variant)
			if candidate_uid == "":
				continue
			if _effect_resolver != null:
				if not _effect_resolver._matches_filter_list(state, filters, context, candidate_uid, source_card_uid):
					continue
				if not _effect_resolver._requirements_met(state, source_card_uid, requirements, context, candidate_uid):
					continue
			result.append(candidate_uid)
		var min_count := int(target.get("min", 0))
		if result.size() < min_count:
			return []
		var max_count := int(target.get("max", result.size()))
		if (bool(target.get("manual", false)) or str(target.get("selection_mode", "AUTO")) == "MANUAL"):
			return result
		if max_count >= 0 and result.size() > max_count:
			return result.slice(0, max_count)
		return result
	if target_type == "OPTION_SET":
		for option_variant in target.get("options", []):
			var option_value := str(option_variant)
			if option_value == "":
				continue
			result.append(option_value)
		return result
	# CARD_SET 类型委托给 effect_resolver
	if _effect_resolver != null:
		return _effect_resolver._resolve_target_set(state, source_card_uid, target, context)
	return result

func _enqueue_target_selection(state: GameState, source_card_uid: String, effect: Dictionary, selected_var: String, target: Dictionary, candidates: Array, context: Dictionary, remaining_steps: Array, resume_as_effect: bool, ui_meta: Dictionary) -> bool:
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
	var candidate_values: Array[String] = []
	for candidate_uid_variant in candidates:
		var candidate_uid := str(candidate_uid_variant)
		var label := candidate_uid
		var candidate_card = state.get_card(candidate_uid)
		if candidate_card != null:
			var candidate_def = state.get_card_def(candidate_card.def_id)
			if candidate_def != null:
				label = _format_target_choice_label(candidate_def)
		choices.append({"label": label, "value": candidate_uid})
		candidate_values.append(candidate_uid)
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
		"candidate_values": candidate_values,
		"selection_constraints": target.get("selection_constraints", {}).duplicate(true),
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
		"selection_constraints": target.get("selection_constraints", {}).duplicate(true),
		"ui_mode": str(ui_meta.get("ui_mode", "")),
		"preview_card_uids": _ensure_array(ui_meta.get("preview_card_uids", [])).duplicate(),
		"title": str(ui_meta.get("title", "")),
	})
	return true

# ============================================================
# 辅助函数 - 临时效果
# ============================================================

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
	_zone_manager.move_card(state, target_uid, source_zone, source_controller)
	_zone_manager.move_card(state, source_card_uid, target_zone, target_controller)
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
		_zone_manager.move_card(state, stacked_uid, to_zone, source_card.controller_player_id)
		logs.append("Moved stacked card %s to %s." % [stacked_uid, UATypes.zone_to_key(to_zone)])
		moved += 1
	return logs

# ============================================================
# 辅助函数 - 延迟效果与静态修正
# ============================================================

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

# ============================================================
# 辅助函数 - 生命触发 RAID
# ============================================================

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
					if required_name != "" and not candidate_def.matches_reference_name(required_name):
						continue
					raid_enabled = true
					raid_reason = ""
					break
				if raid_enabled:
					break
	if source_def != null and str(source_def.special_play_rule.get("type", "")) == "RAID" and not raid_enabled:
		if _effect_resolver != null and _effect_resolver.move_pending_life_card_to_hand(state, source_card_uid, owner_player_id):
			logs.append("%s cannot raid now because requirements are not met, so the card is added to hand instead." % owner_player_id)
			var card_name: String = source_def.name if source_def != null else source_card_uid
			logs.append("%s adds %s to hand." % [owner_player_id, card_name])
			return logs
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

# ============================================================
# 辅助函数 - 打出选中卡牌
# ============================================================

func _play_selected_cards(state: GameState, source_card_uid: String, step: Dictionary, context: Dictionary) -> Array[String]:
	var logs: Array[String] = []
	if _rules_engine == null:
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
		var play_modifiers := {}
		if _effect_resolver != null:
			play_modifiers = _effect_resolver.preview_play_modifiers(state, controller_player_id, card_uid, {
				"target_player_id": controller_player_id,
				"target_zone": target_zone,
			})
		if bool(step.get("ignore_play_costs", false)):
			play_modifiers["cost_ap"] = 0
			play_modifiers["cost_energy"] = {}
		if bool(step.get("allow_current_zone", false)):
			play_modifiers["allow_current_zone"] = true
		var validation: Dictionary = _rules_engine.can_play_card(state, controller_player_id, card_uid, target_zone, play_modifiers, {
			"ignore_play_timing": ignore_play_timing,
		})
		if not bool(validation.get("ok", false)):
			logs.append("Play selected card failed: %s." % str(validation.get("reason", "unknown")))
			continue
		var effective_cost_ap := int(validation.get("cost_ap", play_modifiers.get("cost_ap", 0)))
		var player = state.get_player(controller_player_id)
		if player != null and effective_cost_ap > 0 and not bool(step.get("ignore_play_costs", false)):
			_zone_manager.spend_ap(player, effective_cost_ap)
		_zone_manager.move_card(state, card_uid, target_zone)
		card.state = target_state
		card.flags["entered_this_turn"] = true
		card.flags["entered_from_zone_this_turn"] = entered_from_zone
		if _effect_resolver != null:
			_effect_resolver.commit_play_modifiers(state, play_modifiers)
		var card_def = state.get_card_def(card.def_id)
		logs.append("%s plays %s to %s." % [controller_player_id, card_def.name if card_def != null else card_uid, UATypes.zone_to_key(target_zone)])
	return logs

# ============================================================
# 辅助函数 - UI 元数据
# ============================================================

func _register_preview_ui_meta(context: Dictionary, preview_var: String, meta: Dictionary) -> void:
	var preview_ui_meta: Dictionary = context.get("_preview_ui_meta", {})
	preview_ui_meta = preview_ui_meta.duplicate(true)
	preview_ui_meta[preview_var] = meta.duplicate(true)
	context["_preview_ui_meta"] = preview_ui_meta

func _get_preview_ui_meta(context: Dictionary, preview_var: String) -> Dictionary:
	var preview_ui_meta: Dictionary = context.get("_preview_ui_meta", {})
	if not preview_ui_meta.has(preview_var):
		return {}
	return (preview_ui_meta.get(preview_var, {}) as Dictionary).duplicate(true)

func _build_preview_pick_ui_meta(target: Dictionary, context: Dictionary) -> Dictionary:
	if str(target.get("type", "")) != "CONTEXT_CARD_SET":
		return {}
	var source_var := str(target.get("source_var", ""))
	if source_var == "":
		return {}
	var preview_meta := _get_preview_ui_meta(context, source_var)
	if preview_meta.is_empty():
		return {}
	return {
		"ui_mode": "PREVIEW_PICK",
		"preview_card_uids": _ensure_array(context.get(source_var, [])).duplicate(),
		"title": str(preview_meta.get("title", "查看牌堆顶")),
	}

func _build_preview_reorder_ui_meta(source_var: String, candidates: Array, context: Dictionary) -> Dictionary:
	if source_var == "":
		return {}
	var preview_meta := _get_preview_ui_meta(context, source_var)
	if preview_meta.is_empty():
		return {}
	return {
		"ui_mode": "PREVIEW_REORDER",
		"preview_card_uids": candidates.duplicate(),
		"title": "调整剩余卡牌回到底部的顺序",
	}

# ============================================================
# 辅助函数 - 通用
# ============================================================

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
		return value
	if value is String:
		match value:
			"DECK": return UATypes.Zone.DECK
			"HAND": return UATypes.Zone.HAND
			"LIFE": return UATypes.Zone.LIFE
			"FRONT_LINE": return UATypes.Zone.FRONT_LINE
			"ENERGY_LINE": return UATypes.Zone.ENERGY_LINE
			"AP_AREA": return UATypes.Zone.AP_AREA
			"OUTSIDE": return UATypes.Zone.OUTSIDE
			"REMOVED": return UATypes.Zone.REMOVED
	return -1

func _parse_card_state(value) -> int:
	if value is int:
		return value
	if value is String:
		match value:
			"ACTIVE": return UATypes.CardState.ACTIVE
			"RESTED": return UATypes.CardState.RESTED
	return UATypes.CardState.RESTED

func _ensure_array(value) -> Array:
	if value is Array:
		return value
	if value == null or str(value) == "":
		return []
	return [value]

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

func _context_value_is_non_empty(value) -> bool:
	if value == null:
		return false
	if value is Array:
		return not value.is_empty()
	return str(value) != ""

func _format_target_choice_label(card_def) -> String:
	if card_def == null:
		return ""
	var parts: Array[String] = [str(card_def.name)]
	var number := str(card_def.number)
	if number != "":
		parts.append("编号:%s" % number)
	parts.append("所需能量:%s" % _format_energy_cost_text(card_def.cost_energy))
	return " | ".join(parts)

func _format_energy_cost_text(energy_map: Dictionary) -> String:
	if energy_map.is_empty():
		return "0"
	var parts: Array[String] = []
	var ordered_colors := ["RED", "BLUE", "GREEN", "YELLOW", "PURPLE", "BLACK", "WHITE", "COLORLESS"]
	for color in ordered_colors:
		var amount := int(energy_map.get(color, 0))
		if amount > 0:
			parts.append("%s:%d" % [color, amount])
	for color_variant in energy_map.keys():
		var color := str(color_variant)
		if ordered_colors.has(color):
			continue
		var amount := int(energy_map.get(color_variant, 0))
		if amount > 0:
			parts.append("%s:%d" % [color, amount])
	return ", ".join(parts) if not parts.is_empty() else "0"

func _format_modifier_expiry_text(expires: String) -> String:
	match expires:
		"UNTIL_NEXT_SELF_TURN_START":
			return "until the next turn start of its source controller"
		_:
			return "until end of turn"

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

func _resolve_numeric_value(state: GameState, provider_variant, context: Dictionary, source_card_uid: String, candidate_card_uid := "") -> int:
	if _effect_resolver != null:
		return _effect_resolver._resolve_numeric_value(state, provider_variant, context, source_card_uid, candidate_card_uid)
	if provider_variant is int or provider_variant is float:
		return int(provider_variant)
	if provider_variant is String:
		return int(provider_variant)
	if provider_variant is Dictionary:
		return int(provider_variant.get("value", 0))
	return 0
