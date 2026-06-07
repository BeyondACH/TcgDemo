extends RefCounted
class_name EffectUtils

## 共享工具类 — 统一 effect 相关工具函数
## Phase 1 Task 1.1: 从 effect_resolver / step_executor / target_selector / requirement_matcher 提取

const UATypes = preload("res://core/ua_types.gd")
const CardDef = preload("res://data/card_def.gd")
const GameState = preload("res://data/game_state.gd")
const PlayerState = preload("res://data/player_state.gd")

# ============================================================
# 解析函数
# ============================================================

## 解析卡牌状态字符串/整数为 CardState 枚举
## 无效输入返回 -1，调用方必须检查
static func parse_card_state(value: Variant) -> int:
	if value is int:
		return int(value)
	var state_name := str(value).to_upper()
	match state_name:
		"ACTIVE": return UATypes.CardState.ACTIVE
		"RESTED": return UATypes.CardState.RESTED
	return -1

# ============================================================
# 数组/集合工具
# ============================================================

## 将值包装为数组（若已为数组则直接返回）
## 语义: null/空串 → []，其他非数组值 → [value]
static func ensure_array(value: Variant) -> Array:
	if value is Array:
		return value
	if value == null or str(value) == "":
		return []
	return [value]

## 返回 src 中移除 values_to_remove 后的新数组（保持顺序，逐元素匹配）
static func array_without_values(source: Array, values_to_remove: Array) -> Array:
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

## 判断 context 值是否为"非空"
static func context_value_is_non_empty(value: Variant) -> bool:
	if value == null:
		return false
	if value is Array:
		return not value.is_empty()
	return str(value) != ""

# ============================================================
# 格式化函数
# ============================================================

## 格式化目标选择候选项的标签文本
static func format_target_choice_label(card_def: CardDef) -> String:
	if card_def == null:
		return ""
	var parts: Array[String] = [str(card_def.name)]
	var number := str(card_def.number)
	if number != "":
		parts.append("编号:%s" % number)
	parts.append("所需能量:%s" % format_energy_cost_text(card_def.cost_energy))
	return " | ".join(parts)

## 格式化能量需求文本
static func format_energy_cost_text(energy_map: Dictionary) -> String:
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

## 格式化修饰符过期描述文本
static func format_modifier_expiry_text(expires: String) -> String:
	match expires:
		"UNTIL_NEXT_SELF_TURN_START":
			return "until the next turn start of its source controller"
		_:
			return "until end of turn"

# ============================================================
# 步骤/效果解析
# ============================================================

## 解析步骤/效果的目标 uid
static func resolve_step_target_uid(effect: Dictionary, context: Dictionary, source_card_uid: String) -> String:
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

# ============================================================
# 卡牌属性计算
# ============================================================

## 计算卡牌能量成本总和
static func card_energy_cost_total(card_def: CardDef) -> int:
	if card_def == null:
		return 0
	var total := 0
	for amount_variant in card_def.cost_energy.values():
		total += int(amount_variant)
	return total

## 判断卡牌是否包含指定颜色（通过 cost_energy 或 energy_provided）
static func card_matches_color(card_def: CardDef, color: String) -> bool:
	if card_def == null or color == "":
		return false
	var normalized := color.to_upper()
	return int(card_def.cost_energy.get(normalized, 0)) > 0 or int(card_def.energy_provided.get(normalized, 0)) > 0

# ============================================================
# 区域与数值解析
# ============================================================

## 根据 zone_key 获取玩家对应区域的卡牌数组
static func zone_cards_for_player(player: PlayerState, zone_key: String) -> Array:
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

## 解析数值提供者（从 context / 静态值 / 条件计算中获取数值）
## requirement_matcher 用于 CONDITIONAL 分支的条件判断（不可为空时传入）
static func resolve_numeric_value(state: GameState, provider_variant: Variant, context: Dictionary, source_card_uid: String, candidate_card_uid := "", requirement_matcher = null) -> int:
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
		if requirement_matcher != null and requirement_matcher.all_met(state, source_card_uid, when_requirements, context, candidate_card_uid):
			return resolve_numeric_value(state, provider.get("then", provider.get("value", 0)), context, source_card_uid, candidate_card_uid, requirement_matcher)
		return resolve_numeric_value(state, provider.get("default", 0), context, source_card_uid, candidate_card_uid, requirement_matcher)
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
		var PlayerUtils = preload("res://core/player_utils.gd")
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
			var zone_cards = zone_cards_for_player(count_player, str(zone_variant))
			var required_card_type := str(provider.get("card_type", ""))
			for zone_card_uid_variant in zone_cards:
				var zone_card_uid := str(zone_card_uid_variant)
				if zone_card_uid == "":
					continue
				var zone_card = state.get_card(zone_card_uid)
				var zone_def = state.get_card_def(zone_card.def_id) if zone_card != null else null
				if zone_def == null:
					continue
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
			if card_energy_cost_total(front_def) > int(provider.get("cost_energy_lte", 0)):
				continue
			count_front += 1
		return int(provider.get("value", 0)) + count_front * int(provider.get("multiplier", 1))
	if provider_type == "SOURCE_BP_MINUS":
		var source_bp_card = state.get_card(source_card_uid)
		if source_bp_card == null:
			return 0
		return int(source_bp_card.current_bp) - int(provider.get("value", 0))
	return int(provider.get("value", 0))
