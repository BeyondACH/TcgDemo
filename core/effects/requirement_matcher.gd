extends RefCounted
class_name RequirementMatcher

## 需求匹配器 - 负责检查卡牌效果的需求条件
## 从 effect_resolver.gd 提取，按字典分发模式重构

const UATypes = preload("res://core/ua_types.gd")
const GameState = preload("res://data/game_state.gd")
const CardInstance = preload("res://data/card_instance.gd")
const RulesEngine = preload("res://core/rules_engine.gd")
const PlayerUtils = preload("res://core/player_utils.gd")

var _zone_manager
var _rules_engine: RulesEngine
var _effect_resolver  # 回调引用，用于需要复杂操作的场景

# 处理器字典
var _handlers: Dictionary = {}

func _init(zone_manager, rules_engine: RulesEngine = null, effect_resolver = null) -> void:
	_zone_manager = zone_manager
	_rules_engine = rules_engine
	_effect_resolver = effect_resolver
	_init_handlers()

func _init_handlers() -> void:
	_handlers = {
		"NOT": _req_not,
		"OR": _req_or,
		"CONTROLLER_HAS_NAME_IN_FIELD": _req_controller_has_name_in_field,
		"CONTROLLER_HAS_NAME_IN_ZONE": _req_controller_has_name_in_zone,
		"CONTROLLER_FIELD_ALL_NAMES_IN_SET": _req_controller_field_all_names_in_set,
		"CARD_BP_LTE": _req_card_bp_lte,
		"SOURCE_BP_GTE": _req_source_bp_gte,
		"CARD_BP_LTE_DYNAMIC": _req_card_bp_lte_dynamic,
		"CARD_BP_LTE_CONTEXT_CARD": _req_card_bp_lte_context_card,
		"PLAYER_LIFE_IS_EMPTY": _req_player_life_is_empty,
		"PLAYER_TURN_FLAG_TRUE": _req_player_turn_flag_true,
		"PLAYER_HAS_COLOR_IN_FIELD": _req_player_has_color_in_field,
		"CONTEXT_BATTLE_OUTCOME_IS": _req_context_battle_outcome_is,
		"CARD_NAME_IS": _req_card_name_is,
		"CARD_TYPE_IS": _req_card_type_is,
		"CARD_HAS_TRAIT": _req_card_has_trait,
		"CARD_COST_ENERGY_LTE": _req_card_cost_energy_lte,
		"CARD_COST_AP_EQ": _req_card_cost_ap_eq,
		"CARD_COLOR_IS": _req_card_color_is,
		"CARD_CAN_PLAY_TO_ZONE": _req_card_can_play_to_zone,
		"CONTEXT_VAR_NON_EMPTY": _req_context_var_non_empty,
		"CONTEXT_VALUE_IS": _req_context_value_is,
		"CONTEXT_FLAG_TRUE": _req_context_flag_true,
		"CONTEXT_FLAG_FALSE": _req_context_flag_false,
		"CONTEXT_SELECTED_CARD_HAS_TRAIT": _req_context_selected_card_has_trait,
		"PLAYER_LIFE_LTE": _req_player_life_lte,
		"CONTEXT_SELECTED_CARD_TYPE_IS": _req_context_selected_card_type_is,
		"CONTEXT_TARGET_NAME_IS": _req_context_target_name_is,
		"SOURCE_STATE_IS_ACTIVE": _req_source_state_is_active,
		"SOURCE_ENTERED_THIS_TURN": _req_source_entered_this_turn,
		"SOURCE_ENTERED_FROM_ZONE": _req_source_entered_from_zone,
		"PLAYER_ZONE_CARD_COUNT_GTE": _req_player_zone_card_count_gte,
		"CONTROLLER_TRAIT_NAME_COUNT_GTE": _req_controller_trait_name_count_gte,
		"CONTROLLER_OTHER_TRAIT_CARD_COUNT_GTE": _req_controller_other_trait_card_count_gte,
	}

# ============================================================
# 公共入口
# ============================================================

func all_met(state: GameState, source_card_uid: String, requirements: Array, context: Dictionary, candidate_card_uid := "") -> bool:
	for requirement_variant in requirements:
		if not matches(state, requirement_variant, context, candidate_card_uid, source_card_uid):
			return false
	return true

func matches(state: GameState, requirement_variant, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var requirement: Dictionary = requirement_variant
	var requirement_type := str(requirement.get("type", ""))

	if requirement_type == "":
		return true

	var handler = _handlers.get(requirement_type)
	if handler != null:
		return handler.call(state, requirement, context, candidate_card_uid, source_card_uid)

	# 回退到过滤器匹配
	return matches_filter(state, requirement, context, candidate_card_uid, source_card_uid)

# ============================================================
# 过滤器匹配
# ============================================================

func matches_filter_list(state: GameState, filters: Array, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	for filter_variant in filters:
		if not matches_filter(state, filter_variant, context, candidate_card_uid, source_card_uid):
			return false
	return true

func matches_filter(state: GameState, filter_variant, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var filter: Dictionary = filter_variant
	var filter_type := str(filter.get("type", ""))
	var candidate_card = state.get_card(candidate_card_uid)
	var candidate_def = null
	if candidate_card != null:
		candidate_def = state.get_card_def(candidate_card.def_id)
	var source_card = state.get_card(source_card_uid)

	if filter_type == "CARD_TYPE_IS":
		return candidate_def != null and UATypes.card_type_to_text(candidate_def.card_type) == str(filter.get("value", ""))
	if filter_type == "NAME_IS":
		return candidate_def != null and candidate_def.name == str(filter.get("value", ""))
	if filter_type == "NAME_NOT":
		return candidate_def != null and candidate_def.name != str(filter.get("value", ""))
	if filter_type == "NOT_SOURCE_CARD":
		return candidate_card_uid != "" and candidate_card_uid != source_card_uid
	if filter_type == "NOT_HAS_KEYWORD":
		return candidate_def != null and not candidate_def.keywords.has(str(filter.get("value", "")))
	if filter_type == "HAS_TRAIT":
		return candidate_def != null and candidate_def.traits.has(str(filter.get("value", "")))
	if filter_type == "CARD_COST_ENERGY_LTE":
		return candidate_def != null and _card_energy_cost_total(candidate_def) <= int(filter.get("value", 0))
	if filter_type == "CARD_COST_AP_EQ":
		return candidate_def != null and int(candidate_def.cost_ap) == int(filter.get("value", 0))
	if filter_type == "CARD_COLOR_IS":
		return candidate_def != null and _card_matches_color(candidate_def, str(filter.get("value", "")))
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
			if matches_filter(state, nested, context, candidate_card_uid, source_card_uid):
				return true
		return false
	if filter_type == "AND":
		for nested in filter.get("filters", []):
			if not matches_filter(state, nested, context, candidate_card_uid, source_card_uid):
				return false
		return true
	if filter_type == "SELF_IN_ZONE":
		return source_card != null and source_card.zone == _parse_zone(filter.get("zone", filter.get("value", -1)))
	return true

# ============================================================
# 需求处理器
# ============================================================

func _req_or(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	for nested in requirement.get("requirements", requirement.get("filters", [])):
		if matches(state, nested, context, candidate_card_uid, source_card_uid):
			return true
	return false

func _req_not(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var nested = requirement.get("requirement", {})
	if nested.is_empty():
		var nested_list: Array = requirement.get("requirements", [])
		if nested_list.size() == 1:
			nested = nested_list[0]
	return not matches(state, nested, context, candidate_card_uid, source_card_uid)

func _req_controller_has_name_in_field(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var source_card = state.get_card(source_card_uid)
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

func _req_controller_has_name_in_zone(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var source_card = state.get_card(source_card_uid)
	if source_card == null:
		return false
	var player_mode_zone := str(requirement.get("owner", "SELF"))
	var player_id_zone: String = source_card.controller_player_id
	if player_mode_zone == "OPPONENT":
		player_id_zone = PlayerUtils.opponent_of(source_card.controller_player_id)
	var zone_player = state.get_player(player_id_zone)
	if zone_player == null:
		return false
	var required_zone_name := str(requirement.get("value", ""))
	var zones: Array = requirement.get("zones", [])
	for zone_variant in zones:
		var zone_key := str(zone_variant)
		var zone_cards: Array = []
		match zone_key:
			"FRONT_LINE":
				zone_cards = zone_player.front_line
			"ENERGY_LINE":
				zone_cards = zone_player.energy_line
			"HAND":
				zone_cards = zone_player.hand
			"LIFE":
				zone_cards = zone_player.life
			"OUTSIDE":
				zone_cards = zone_player.outside
			"REMOVED":
				zone_cards = zone_player.removed
			_:
				zone_cards = []
		for zone_card_uid in zone_cards:
			var zone_card = state.get_card(str(zone_card_uid))
			var zone_def = state.get_card_def(zone_card.def_id) if zone_card != null else null
			if zone_def != null and zone_def.name == required_zone_name:
				return true
	return false

func _req_controller_field_all_names_in_set(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var source_card = state.get_card(source_card_uid)
	if source_card == null:
		return false
	var player_mode_names := str(requirement.get("owner", "SELF"))
	var player_id_names: String = source_card.controller_player_id
	if player_mode_names == "OPPONENT":
		player_id_names = PlayerUtils.opponent_of(source_card.controller_player_id)
	var names_player = state.get_player(player_id_names)
	if names_player == null:
		return false
	var allowed_names: Dictionary = {}
	for name_variant in requirement.get("names", []):
		var allowed_name := str(name_variant)
		if allowed_name != "":
			allowed_names[allowed_name] = true
	for zone_cards in [names_player.front_line, names_player.energy_line]:
		for field_uid_variant in zone_cards:
			var field_uid := str(field_uid_variant)
			if field_uid == "":
				continue
			var field_card = state.get_card(field_uid)
			var field_def = state.get_card_def(field_card.def_id) if field_card != null else null
			if field_def == null:
				continue
			if field_def.card_type != UATypes.CardType.CHARACTER:
				continue
			var matched_allowed := false
			for allowed_name_variant in allowed_names.keys():
				var allowed_name := str(allowed_name_variant)
				if field_def.matches_reference_name(allowed_name):
					matched_allowed = true
					break
			if not matched_allowed:
				return false
	return true

func _req_card_bp_lte(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var source_card = state.get_card(source_card_uid)
	var candidate_card = state.get_card(candidate_card_uid)
	var compare_card = candidate_card if candidate_card != null else source_card
	if compare_card == null:
		return false
	return int(compare_card.current_bp) <= int(requirement.get("value", 0))

func _req_source_bp_gte(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var source_card = state.get_card(source_card_uid)
	return source_card != null and int(source_card.current_bp) >= int(requirement.get("value", 0))

func _req_card_bp_lte_dynamic(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var source_card = state.get_card(source_card_uid)
	var candidate_card = state.get_card(candidate_card_uid)
	var compare_dynamic = candidate_card if candidate_card != null else source_card
	if compare_dynamic == null:
		return false
	var dynamic_limit := _resolve_numeric_value(
		state,
		requirement.get("value_provider", requirement.get("value", 0)),
		context,
		source_card_uid,
		candidate_card_uid
	)
	return int(compare_dynamic.current_bp) <= dynamic_limit

func _req_card_bp_lte_context_card(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var source_card = state.get_card(source_card_uid)
	var candidate_card = state.get_card(candidate_card_uid)
	var compare_card = candidate_card if candidate_card != null else source_card
	if compare_card == null:
		return false
	var context_var := str(requirement.get("context_var", ""))
	if context_var == "":
		return false
	var reference_uid := str(context.get(context_var, ""))
	var reference_card = state.get_card(reference_uid)
	if reference_card == null:
		return false
	return int(compare_card.current_bp) <= int(reference_card.current_bp)

func _req_player_life_is_empty(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var source_card = state.get_card(source_card_uid)
	var player_mode := str(requirement.get("player", "SELF"))
	var player_id := str(context.get("target_player_id", context.get("source_player_id", "")))
	if player_mode == "SELF" and source_card != null:
		player_id = source_card.controller_player_id
	elif player_mode == "OPPONENT" and source_card != null:
		player_id = PlayerUtils.opponent_of(source_card.controller_player_id)
	var player_state = state.get_player(player_id)
	return player_state != null and player_state.life.is_empty()

func _req_player_turn_flag_true(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var source_card = state.get_card(source_card_uid)
	var player_mode_flag := str(requirement.get("player", "SELF"))
	var player_id_flag := ""
	if player_mode_flag == "SELF":
		player_id_flag = source_card.controller_player_id if source_card != null else str(context.get("source_player_id", ""))
	elif player_mode_flag == "OPPONENT":
		player_id_flag = PlayerUtils.opponent_of(source_card.controller_player_id) if source_card != null else ""
	else:
		player_id_flag = str(context.get("target_player_id", context.get("source_player_id", "")))
	var flags: Dictionary = state.player_turn_flags.get(player_id_flag, {})
	return bool(flags.get(str(requirement.get("flag", "")), false))

func _req_player_has_color_in_field(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var source_card = state.get_card(source_card_uid)
	var player_mode_color := str(requirement.get("player", "SELF"))
	var player_id_color := ""
	if player_mode_color == "SELF":
		player_id_color = source_card.controller_player_id if source_card != null else str(context.get("source_player_id", ""))
	elif player_mode_color == "OPPONENT":
		player_id_color = PlayerUtils.opponent_of(source_card.controller_player_id) if source_card != null else ""
	else:
		player_id_color = str(context.get("target_player_id", context.get("source_player_id", "")))
	var color_player = state.get_player(player_id_color)
	if color_player == null:
		return false
	var colors: Array[String] = []
	for color_variant in requirement.get("colors", []):
		colors.append(str(color_variant))
	if colors.is_empty():
		var fallback_color := str(requirement.get("value", ""))
		if fallback_color != "":
			colors.append(fallback_color)
	for zone_cards in [color_player.front_line, color_player.energy_line]:
		for color_card_uid_variant in zone_cards:
			var color_card = state.get_card(str(color_card_uid_variant))
			var color_def = state.get_card_def(color_card.def_id) if color_card != null else null
			if color_def == null:
				continue
			for color_name in colors:
				if _card_matches_color(color_def, color_name):
					return true
	return false

func _req_context_battle_outcome_is(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	return str(context.get("battle_outcome", "")) == str(requirement.get("value", ""))

func _req_card_name_is(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var candidate_card = state.get_card(candidate_card_uid)
	var candidate_def = state.get_card_def(candidate_card.def_id) if candidate_card != null else null
	return candidate_def != null and candidate_def.name == str(requirement.get("value", ""))

func _req_card_type_is(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var candidate_card = state.get_card(candidate_card_uid)
	var candidate_def = state.get_card_def(candidate_card.def_id) if candidate_card != null else null
	return candidate_def != null and UATypes.card_type_to_text(candidate_def.card_type) == str(requirement.get("value", ""))

func _req_card_has_trait(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var candidate_card = state.get_card(candidate_card_uid)
	var candidate_def = state.get_card_def(candidate_card.def_id) if candidate_card != null else null
	return candidate_def != null and candidate_def.traits.has(str(requirement.get("value", "")))

func _req_card_cost_energy_lte(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var candidate_card = state.get_card(candidate_card_uid)
	var candidate_def = state.get_card_def(candidate_card.def_id) if candidate_card != null else null
	return candidate_def != null and _card_energy_cost_total(candidate_def) <= int(requirement.get("value", 0))

func _req_card_cost_ap_eq(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var candidate_card = state.get_card(candidate_card_uid)
	var candidate_def = state.get_card_def(candidate_card.def_id) if candidate_card != null else null
	return candidate_def != null and int(candidate_def.cost_ap) == int(requirement.get("value", 0))

func _req_card_color_is(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var candidate_card = state.get_card(candidate_card_uid)
	var candidate_def = state.get_card_def(candidate_card.def_id) if candidate_card != null else null
	return candidate_def != null and _card_matches_color(candidate_def, str(requirement.get("value", "")))

func _req_card_can_play_to_zone(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var candidate_card = state.get_card(candidate_card_uid)
	if candidate_card == null or _rules_engine == null:
		return false
	var controller_player_id: String = candidate_card.controller_player_id
	var target_zone := _parse_zone(requirement.get("zone", requirement.get("target_zone", UATypes.Zone.FRONT_LINE)))
	var play_modifiers := {}
	if _effect_resolver != null:
		play_modifiers = _effect_resolver.preview_play_modifiers(state, controller_player_id, candidate_card.uid, {
			"target_player_id": controller_player_id,
			"target_zone": target_zone,
		})
	if bool(requirement.get("allow_current_zone", false)):
		play_modifiers["allow_current_zone"] = true
	var validation: Dictionary = _rules_engine.can_play_card(state, controller_player_id, candidate_card.uid, target_zone, play_modifiers, {
		"ignore_play_timing": bool(requirement.get("ignore_play_timing", true)),
	})
	return bool(validation.get("ok", false))

func _req_context_var_non_empty(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	return not _ensure_array(context.get(str(requirement.get("var", "")), [])).is_empty()

func _req_context_value_is(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	return str(context.get(str(requirement.get("var", "")), "")) == str(requirement.get("value", ""))

func _req_context_flag_true(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	return bool(context.get(str(requirement.get("var", "")), false))

func _req_context_flag_false(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	return not bool(context.get(str(requirement.get("var", "")), false))

func _req_context_selected_card_has_trait(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var selected_uid := str(context.get(str(requirement.get("context_var", "")), ""))
	var selected_card = state.get_card(selected_uid)
	var selected_def = state.get_card_def(selected_card.def_id) if selected_card != null else null
	return selected_def != null and selected_def.traits.has(str(requirement.get("value", "")))

func _req_player_life_lte(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var source_card = state.get_card(source_card_uid)
	var player_mode := str(requirement.get("player", "SELF"))
	var player_id := ""
	if player_mode == "SELF":
		player_id = source_card.controller_player_id if source_card != null else str(context.get("source_player_id", ""))
	elif player_mode == "OPPONENT":
		player_id = PlayerUtils.opponent_of(source_card.controller_player_id) if source_card != null else ""
	elif player_mode == "TARGET":
		player_id = str(context.get("target_player_id", ""))
	else:
		player_id = str(context.get("player_id", context.get("source_player_id", "")))
	var life_player = state.get_player(player_id)
	return life_player != null and life_player.life.size() <= int(requirement.get("value", 0))

func _req_context_selected_card_type_is(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var selected_uid_type := str(context.get(str(requirement.get("context_var", "")), ""))
	var selected_card_type = state.get_card(selected_uid_type)
	var selected_def_type = state.get_card_def(selected_card_type.def_id) if selected_card_type != null else null
	return selected_def_type != null and UATypes.card_type_to_text(selected_def_type.card_type) == str(requirement.get("value", ""))

func _req_context_target_name_is(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var target_uid := str(context.get("target_uid", ""))
	if target_uid == "":
		return false
	var target_card = state.get_card(target_uid)
	var target_def = state.get_card_def(target_card.def_id) if target_card != null else null
	return target_def != null and target_def.name == str(requirement.get("value", ""))

func _req_source_state_is_active(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var source_card = state.get_card(source_card_uid)
	return source_card != null and source_card.state == UATypes.CardState.ACTIVE

func _req_source_entered_this_turn(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var source_card = state.get_card(source_card_uid)
	return source_card != null and bool(source_card.flags.get("entered_this_turn", false))

func _req_source_entered_from_zone(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var source_card = state.get_card(source_card_uid)
	if source_card == null:
		return false
	return int(source_card.flags.get("entered_from_zone_this_turn", -1)) == _parse_zone(requirement.get("value", requirement.get("zone", -1)))

func _req_player_zone_card_count_gte(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var source_card = state.get_card(source_card_uid)
	var player_mode := str(requirement.get("player", "SELF"))
	var player_id := ""
	if player_mode == "SELF":
		player_id = source_card.controller_player_id if source_card != null else str(context.get("source_player_id", ""))
	elif player_mode == "OPPONENT":
		player_id = PlayerUtils.opponent_of(source_card.controller_player_id) if source_card != null else ""
	else:
		player_id = str(context.get("target_player_id", context.get("source_player_id", "")))
	var player = state.get_player(player_id)
	if player == null:
		return false
	var count := 0
	for zone_variant in requirement.get("zones", []):
		var zone_cards = _zone_cards_for_player(player, str(zone_variant))
		for card_uid_variant in zone_cards:
			var card_uid := str(card_uid_variant)
			if card_uid == "":
				continue
			var card = state.get_card(card_uid)
			var card_def = state.get_card_def(card.def_id) if card != null else null
			if card_def == null:
				continue
			var required_card_type := str(requirement.get("card_type", ""))
			if required_card_type != "" and UATypes.card_type_to_text(card_def.card_type) != required_card_type:
				continue
			count += 1
	return count >= int(requirement.get("value", 0))

func _req_controller_trait_name_count_gte(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var source_card = state.get_card(source_card_uid)
	if source_card == null:
		return false
	var player = state.get_player(source_card.controller_player_id)
	if player == null:
		return false
	var trait_value := str(requirement.get("trait", ""))
	var min_count := int(requirement.get("value", 0))
	var unique_names: Dictionary = {}
	for zone_cards in [player.front_line, player.energy_line]:
		for card_uid_v in zone_cards:
			var cuid := str(card_uid_v)
			if cuid == source_card_uid:
				continue
			var c = state.get_card(cuid)
			if c == null:
				continue
			var d = state.get_card_def(c.def_id)
			if d != null and d.traits.has(trait_value):
				unique_names[d.name] = true
	return unique_names.size() >= min_count

func _req_controller_other_trait_card_count_gte(state: GameState, requirement: Dictionary, context: Dictionary, candidate_card_uid: String, source_card_uid: String) -> bool:
	var source_card = state.get_card(source_card_uid)
	if source_card == null:
		return false
	var count_player = state.get_player(source_card.controller_player_id)
	if count_player == null:
		return false
	var count_trait := str(requirement.get("trait", ""))
	var count_min := int(requirement.get("value", 0))
	var matched_count := 0
	for zone_cards in [count_player.front_line, count_player.energy_line]:
		for card_uid_v in zone_cards:
			var count_uid := str(card_uid_v)
			if count_uid == "" or count_uid == source_card_uid:
				continue
			var count_card = state.get_card(count_uid)
			if count_card == null:
				continue
			var count_def = state.get_card_def(count_card.def_id)
			if count_def != null and count_def.traits.has(count_trait):
				matched_count += 1
	return matched_count >= count_min

# ============================================================
# 辅助函数
# ============================================================

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

func _ensure_array(value) -> Array:
	if value is Array:
		return value
	if value == null or str(value) == "":
		return []
	return [value]

func _zone_cards_for_player(player: PlayerState, zone_key: String) -> Array:
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

func _resolve_numeric_value(state: GameState, provider_variant, context: Dictionary, source_card_uid: String, candidate_card_uid := "") -> int:
	# 委托给 effect_resolver 处理复杂逻辑
	if _effect_resolver != null:
		return _effect_resolver._resolve_numeric_value(state, provider_variant, context, source_card_uid, candidate_card_uid)
	# 简单情况直接处理
	if provider_variant is int or provider_variant is float:
		return int(provider_variant)
	if provider_variant is String:
		return int(provider_variant)
	if provider_variant is Dictionary:
		return int(provider_variant.get("value", 0))
	return 0
