extends RefCounted
class_name TargetSelector

## 目标选择器 - 负责目标选择逻辑和决策队列管理
## 从 effect_resolver.gd 提取

const UATypes = preload("res://core/ua_types.gd")
const GameState = preload("res://data/game_state.gd")
const CardInstance = preload("res://data/card_instance.gd")
const ZoneManager = preload("res://core/zone_manager.gd")
const PlayerUtils = preload("res://core/player_utils.gd")

var _zone_manager: ZoneManager
var _requirement_matcher  # RequirementMatcher 引用
var _effect_resolver  # 回调引用

func _init(zone_manager: ZoneManager, requirement_matcher, effect_resolver) -> void:
	_zone_manager = zone_manager
	_requirement_matcher = requirement_matcher
	_effect_resolver = effect_resolver

# ============================================================
# 公共入口
# ============================================================

func resolve_target_set(state: GameState, source_card_uid: String, target: Dictionary, context: Dictionary) -> Array:
	var result: Array = []
	var target_type := str(target.get("type", ""))
	if target_type == "CONTEXT_CARD_SET":
		return _resolve_context_card_set(state, source_card_uid, target, context)
	if target_type == "OPTION_SET":
		return _resolve_option_set(target)
	if target_type != "CARD_SET":
		return result
	return _resolve_card_set(state, source_card_uid, target, context)

func enqueue_target_selection(state: GameState, source_card_uid: String, effect: Dictionary, selected_var: String, target: Dictionary, candidates: Array, context: Dictionary, remaining_steps: Array, resume_as_effect := false, ui_meta: Dictionary = {}) -> bool:
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

func enqueue_value_selection(state: GameState, source_card_uid: String, effect: Dictionary, selected_var: String, choices: Array[Dictionary], candidate_values: Array[String], min_count: int, max_count: int, context: Dictionary, remaining_steps: Array, resume_as_effect := false) -> bool:
	var source_card = state.get_card(source_card_uid)
	var owner_player_id = source_card.controller_player_id if source_card != null else str(context.get("source_player_id", ""))
	var resolution_id := state.next_runtime_id("target_select")
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
		"candidate_values": candidate_values.duplicate(),
		"selection_constraints": {},
	})
	state.pending_decisions.append({
		"type": "ABILITY_TARGET_SELECTION",
		"owner_player_id": owner_player_id,
		"source_card_uid": source_card_uid,
		"resolution_id": resolution_id,
		"target_var": selected_var,
		"choices": choices.duplicate(true),
		"min": min_count,
		"max": max_count,
	})
	return true

# ============================================================
# 内部解析函数
# ============================================================

func _resolve_context_card_set(state: GameState, source_card_uid: String, target: Dictionary, context: Dictionary) -> Array:
	var result: Array = []
	var source_var := str(target.get("source_var", ""))
	var context_candidates: Array = _ensure_array(context.get(source_var, []))
	var filters: Array = target.get("filters", [])
	var requirements: Array = target.get("requirements", [])
	for candidate_uid_variant in context_candidates:
		var candidate_uid := str(candidate_uid_variant)
		if candidate_uid == "":
			continue
		if not _matches_filter_list(state, filters, context, candidate_uid, source_card_uid):
			continue
		if not _requirements_met(state, source_card_uid, requirements, context, candidate_uid):
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

func _resolve_option_set(target: Dictionary) -> Array:
	var result: Array = []
	for option_variant in target.get("options", []):
		var option_value := str(option_variant)
		if option_value == "":
			continue
		result.append(option_value)
	return result

func _resolve_card_set(state: GameState, source_card_uid: String, target: Dictionary, context: Dictionary) -> Array:
	var result: Array = []
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
	var owner_player_ids := resolve_owner_player_ids(state, owner_mode, source_card.controller_player_id)
	var filters: Array = target.get("filters", [])
	var requirements: Array = target.get("requirements", [])
	for player_id in owner_player_ids:
		var player = state.get_player(player_id)
		if player == null:
			continue
		for zone in zones:
			var zone_cards = _zone_manager.get_zone_array(player, zone)
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

func resolve_owner_player_ids(state: GameState, owner_mode: String, source_player_id: String) -> Array:
	if owner_mode == "SELF":
		return [source_player_id]
	if owner_mode == "OPPONENT":
		return [PlayerUtils.opponent_of(source_player_id)]
	if owner_mode == "ANY":
		return [UATypes.PLAYER_ONE, UATypes.PLAYER_TWO]
	if owner_mode == "ACTIVE_PLAYER":
		return [state.active_player_id]
	if owner_mode == "TARGET_PLAYER":
		return [str(state.battle_context.get("defender_player_id", source_player_id))]
	return [source_player_id]

# ============================================================
# UI 元数据构建
# ============================================================

func register_preview_ui_meta(context: Dictionary, preview_var: String, meta: Dictionary) -> void:
	var preview_ui_meta: Dictionary = context.get("_preview_ui_meta", {})
	preview_ui_meta = preview_ui_meta.duplicate(true)
	preview_ui_meta[preview_var] = meta.duplicate(true)
	context["_preview_ui_meta"] = preview_ui_meta

func get_preview_ui_meta(context: Dictionary, preview_var: String) -> Dictionary:
	var preview_ui_meta: Dictionary = context.get("_preview_ui_meta", {})
	if not preview_ui_meta.has(preview_var):
		return {}
	return (preview_ui_meta.get(preview_var, {}) as Dictionary).duplicate(true)

func build_preview_pick_ui_meta(target: Dictionary, context: Dictionary) -> Dictionary:
	if str(target.get("type", "")) != "CONTEXT_CARD_SET":
		return {}
	var source_var := str(target.get("source_var", ""))
	if source_var == "":
		return {}
	var preview_meta := get_preview_ui_meta(context, source_var)
	if preview_meta.is_empty():
		return {}
	return {
		"ui_mode": "PREVIEW_PICK",
		"preview_card_uids": _ensure_array(context.get(source_var, [])).duplicate(),
		"title": str(preview_meta.get("title", "查看牌堆顶")),
	}

func build_preview_reorder_ui_meta(source_var: String, candidates: Array, context: Dictionary) -> Dictionary:
	if source_var == "":
		return {}
	var preview_meta := get_preview_ui_meta(context, source_var)
	if preview_meta.is_empty():
		return {}
	return {
		"ui_mode": "PREVIEW_REORDER",
		"preview_card_uids": candidates.duplicate(),
		"title": "调整剩余卡牌回到底部的顺序",
	}

# ============================================================
# 选择载荷处理
# ============================================================

func normalize_selection_payload(selected_values, max_count: int) -> Array:
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

func validate_selection_payload(state: GameState, normalized: Array, queued_effect: Dictionary) -> String:
	var max_count := int(queued_effect.get("max", -1))
	if max_count >= 0 and normalized.size() > max_count:
		return "too_many_targets"
	var candidate_values: Array = queued_effect.get("candidate_values", [])
	for value_variant in normalized:
		var value := str(value_variant)
		if not candidate_values.has(value):
			return "invalid_choice"
	var constraints: Dictionary = queued_effect.get("selection_constraints", {})
	var threshold := _resolve_sum_threshold(state, constraints, queued_effect)
	if threshold >= 0:
		var running_bp := 0
		for card_uid_variant in normalized:
			var card_uid := str(card_uid_variant)
			var card = state.get_card(card_uid)
			var card_bp := int(card.current_bp) if card != null else 0
			running_bp += card_bp
			if running_bp > threshold:
				return "selection_sum_exceeded"
	if str(constraints.get("distinct_by", "")) == "CARD_NAME":
		var seen_names: Dictionary = {}
		for card_uid_variant in normalized:
			var card_uid := str(card_uid_variant)
			var card = state.get_card(card_uid)
			if card == null:
				continue
			var card_def = state.get_card_def(card.def_id)
			if card_def == null:
				continue
			if seen_names.has(card_def.name):
				return "duplicate_card_name"
			seen_names[card_def.name] = true
	return ""

func _resolve_sum_threshold(state: GameState, constraints: Dictionary, queued_effect: Dictionary) -> int:
	if constraints.is_empty():
		return -1
	var max_sum_provider = constraints.get("max_sum_provider", null)
	if max_sum_provider != null and _effect_resolver != null and _effect_resolver.has_method("_resolve_numeric_value"):
		var context: Dictionary = queued_effect.get("context", {})
		var source_card_uid := str(queued_effect.get("source_card_uid", ""))
		return int(_effect_resolver._resolve_numeric_value(state, max_sum_provider, context, source_card_uid))
	var max_sum_bp = constraints.get("max_sum_bp", null)
	if max_sum_bp != null:
		return int(max_sum_bp)
	return -1

# ============================================================
# 辅助函数
# ============================================================

func _matches_filter_list(state: GameState, filters: Array, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	if _requirement_matcher != null:
		return _requirement_matcher.matches_filter_list(state, filters, context, candidate_card_uid, source_card_uid)
	return true

func _requirements_met(state: GameState, source_card_uid: String, requirements: Array, context: Dictionary, candidate_card_uid := "") -> bool:
	if _requirement_matcher != null:
		return _requirement_matcher.all_met(state, source_card_uid, requirements, context, candidate_card_uid)
	return true

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

func _parse_zone(value) -> int:
	if value is int:
		return int(value)
	var zone_name := str(value)
	if zone_name == "DECK" or zone_name == "deck":
		return UATypes.Zone.DECK
	if zone_name == "HAND" or zone_name == "hand":
		return UATypes.Zone.HAND
	if zone_name == "FRONT_LINE" or zone_name == "front_line":
		return UATypes.Zone.FRONT_LINE
	if zone_name == "ENERGY_LINE" or zone_name == "energy_line":
		return UATypes.Zone.ENERGY_LINE
	if zone_name == "LIFE" or zone_name == "life":
		return UATypes.Zone.LIFE
	if zone_name == "OUTSIDE" or zone_name == "outside":
		return UATypes.Zone.OUTSIDE
	if zone_name == "AP_AREA" or zone_name == "ap_area":
		return UATypes.Zone.AP_AREA
	if zone_name == "REMOVED" or zone_name == "removed":
		return UATypes.Zone.REMOVED
	return UATypes.Zone.OUTSIDE

func _ensure_array(value) -> Array:
	if value is Array:
		return value
	return []
