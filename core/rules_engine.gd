extends RefCounted
class_name RulesEngine

const UATypes = preload("res://core/ua_types.gd")
const ZoneManager = preload("res://core/zone_manager.gd")
const GameState = preload("res://data/game_state.gd")
const PlayerState = preload("res://data/player_state.gd")
const CardInstance = preload("res://data/card_instance.gd")
const CardDef = preload("res://data/card_def.gd")

var zone_manager: ZoneManager

func _init(p_zone_manager: ZoneManager) -> void:
	zone_manager = p_zone_manager

# 校验手牌能否被打到目标区域。
func can_play_card(state: GameState, player_id: String, card_uid: String, target_zone: int, play_modifiers: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	var player: PlayerState = state.get_player(player_id)
	var card: CardInstance = state.get_card(card_uid)
	if player == null or card == null:
		return {"ok": false, "reason": "missing_card_or_player"}
	var ignore_play_timing := bool(options.get("ignore_play_timing", false))
	if state.active_player_id != player_id and not ignore_play_timing:
		return {"ok": false, "reason": "not_active_player"}
	if state.phase != UATypes.Phase.MAIN and not ignore_play_timing:
		return {"ok": false, "reason": "wrong_phase"}
	var allow_current_zone := bool(play_modifiers.get("allow_current_zone", false))
	if card.zone != UATypes.Zone.HAND and not allow_current_zone:
		return {"ok": false, "reason": "not_in_playable_zone"}
	var card_def: CardDef = state.get_card_def(card.def_id)
	if card_def == null:
		return {"ok": false, "reason": "missing_def"}
	var raid_validation := _validate_special_play_rule(state, player_id, card, card_def, target_zone, options)
	if not bool(raid_validation.get("ok", false)):
		return raid_validation
	var is_raid_play := str(raid_validation.get("mode", "NORMAL")) == "RAID"
	var effective_cost_ap := int(play_modifiers.get("cost_ap", card_def.cost_ap))
	if not _can_pay_ap(player, effective_cost_ap):
		return {"ok": false, "reason": "not_enough_ap"}
	if not _has_required_energy(state, player, card_def.cost_energy):
		return {"ok": false, "reason": "not_enough_energy"}
	match card_def.card_type:
		UATypes.CardType.CHARACTER:
			if target_zone != UATypes.Zone.FRONT_LINE and target_zone != UATypes.Zone.ENERGY_LINE:
				return {"ok": false, "reason": "bad_character_zone"}
			if not is_raid_play and target_zone == UATypes.Zone.FRONT_LINE and player.front_line.size() >= UATypes.MAX_FRONT_LINE:
				return {"ok": false, "reason": "front_line_full"}
			if not is_raid_play and target_zone == UATypes.Zone.ENERGY_LINE and player.energy_line.size() >= UATypes.MAX_ENERGY_LINE:
				return {"ok": false, "reason": "energy_line_full"}
		UATypes.CardType.FIELD:
			if target_zone != UATypes.Zone.ENERGY_LINE:
				return {"ok": false, "reason": "field_must_go_energy"}
			if player.energy_line.size() >= UATypes.MAX_ENERGY_LINE:
				return {"ok": false, "reason": "energy_line_full"}
		UATypes.CardType.EVENT:
			if target_zone != UATypes.Zone.OUTSIDE:
				return {"ok": false, "reason": "event_resolves_to_outside"}
	return {"ok": true, "cost_ap": effective_cost_ap, "special_play": raid_validation}

# 移动阶段允许把能量区里的角色移到前线，场地牌和事件牌都不适用该规则。
func can_move_energy_to_front(state: GameState, player_id: String, card_uid: String) -> Dictionary:
	var player: PlayerState = state.get_player(player_id)
	var card: CardInstance = state.get_card(card_uid)
	if player == null or card == null:
		return {"ok": false, "reason": "missing_card_or_player"}
	if state.active_player_id != player_id or state.phase != UATypes.Phase.MOVE:
		return {"ok": false, "reason": "wrong_phase"}
	if card.zone != UATypes.Zone.ENERGY_LINE:
		return {"ok": false, "reason": "not_in_energy"}
	var card_def: CardDef = state.get_card_def(card.def_id)
	if card_def == null or card_def.card_type != UATypes.CardType.CHARACTER:
		return {"ok": false, "reason": "only_character_can_move"}
	if player.front_line.size() >= UATypes.MAX_FRONT_LINE:
		return {"ok": false, "reason": "front_line_full"}
	return {"ok": true}

func can_step_move_to_energy(state: GameState, player_id: String, card_uid: String, swap_uid := "") -> Dictionary:
	var player: PlayerState = state.get_player(player_id)
	var card: CardInstance = state.get_card(card_uid)
	if player == null or card == null:
		return {"ok": false, "reason": "missing_card_or_player"}
	if state.active_player_id != player_id or state.phase != UATypes.Phase.MOVE:
		return {"ok": false, "reason": "wrong_phase"}
	if card.zone != UATypes.Zone.FRONT_LINE:
		return {"ok": false, "reason": "not_in_front"}
	var card_def: CardDef = state.get_card_def(card.def_id)
	if card_def == null or card_def.card_type != UATypes.CardType.CHARACTER:
		return {"ok": false, "reason": "only_character_can_step"}
	if not _card_has_keyword(card, card_def, "STEP"):
		return {"ok": false, "reason": "missing_step_keyword"}
	if player.energy_line.size() < UATypes.MAX_ENERGY_LINE:
		return {"ok": true, "swap_required": false}
	if swap_uid == "":
		return {"ok": false, "reason": "step_swap_required"}
	var swap_card: CardInstance = state.get_card(swap_uid)
	if swap_card == null or swap_card.controller_player_id != player_id:
		return {"ok": false, "reason": "invalid_step_swap_target"}
	if swap_card.zone != UATypes.Zone.ENERGY_LINE:
		return {"ok": false, "reason": "step_swap_target_not_in_energy"}
	var swap_def: CardDef = state.get_card_def(swap_card.def_id)
	if swap_def == null or swap_def.card_type != UATypes.CardType.CHARACTER:
		return {"ok": false, "reason": "step_swap_target_not_character"}
	return {"ok": true, "swap_required": true, "swap_uid": swap_uid}

func can_attack(state: GameState, player_id: String, card_uid: String, options: Dictionary = {}) -> Dictionary:
	var player: PlayerState = state.get_player(player_id)
	var card: CardInstance = state.get_card(card_uid)
	if player == null or card == null:
		return {"ok": false, "reason": "missing_card_or_player"}
	if state.active_player_id != player_id or state.phase != UATypes.Phase.ATTACK:
		return {"ok": false, "reason": "wrong_phase"}
	if card.zone != UATypes.Zone.FRONT_LINE:
		return {"ok": false, "reason": "not_in_front"}
	if card.state != UATypes.CardState.ACTIVE:
		return {"ok": false, "reason": "not_active"}
	var card_def: CardDef = state.get_card_def(card.def_id)
	if card_def == null or card_def.card_type != UATypes.CardType.CHARACTER:
		return {"ok": false, "reason": "only_character_can_attack"}
	if bool(card.flags.get("attacked_this_turn", false)):
		if not _card_has_keyword(card, card_def, "DOUBLE_ATTACK") or bool(card.flags.get("double_attack_consumed", false)):
			return {"ok": false, "reason": "already_attacked"}
	var target_kind := str(options.get("target_kind", "PLAYER"))
	var target_uid := str(options.get("target_uid", ""))
	var is_sniper := target_kind == "FRONT_CHARACTER"
	if is_sniper:
		if not _card_has_keyword(card, card_def, "SNIPER"):
			return {"ok": false, "reason": "missing_sniper_keyword"}
		if target_uid == "":
			return {"ok": false, "reason": "missing_target_uid"}
		var target_card: CardInstance = state.get_card(target_uid)
		if target_card == null:
			return {"ok": false, "reason": "missing_target_card"}
		if target_card.controller_player_id == player_id:
			return {"ok": false, "reason": "cannot_attack_own_character"}
		if target_card.zone != UATypes.Zone.FRONT_LINE:
			return {"ok": false, "reason": "sniper_target_not_in_front"}
	return {
		"ok": true,
		"target_kind": "FRONT_CHARACTER" if is_sniper else "PLAYER",
		"target_uid": target_uid,
		"is_sniper_attack": is_sniper,
	}

func can_block(state: GameState, player_id: String, card_uid: String) -> Dictionary:
	if bool(state.battle_context.get("is_sniper_attack", false)):
		return {"ok": false, "reason": "cannot_block_sniper"}
	var card: CardInstance = state.get_card(card_uid)
	if card == null or card.zone != UATypes.Zone.FRONT_LINE:
		return {"ok": false, "reason": "not_in_front"}
	if card.controller_player_id != player_id:
		return {"ok": false, "reason": "wrong_controller"}
	if card.state != UATypes.CardState.ACTIVE:
		return {"ok": false, "reason": "not_active"}
	var card_def: CardDef = state.get_card_def(card.def_id)
	if card_def == null or card_def.card_type != UATypes.CardType.CHARACTER:
		return {"ok": false, "reason": "only_character_can_block"}
	if bool(card.flags.get("blocked_this_turn", false)):
		if not _card_has_keyword(card, card_def, "DOUBLE_BLOCK") or bool(card.flags.get("double_block_consumed", false)):
			return {"ok": false, "reason": "already_blocked"}
	return {"ok": true}

func get_available_blockers(state: GameState, defender_player_id: String) -> Array[String]:
	var blockers: Array[String] = []
	var player: PlayerState = state.get_player(defender_player_id)
	if player == null:
		return blockers
	for card_uid in player.front_line:
		var result: Dictionary = can_block(state, defender_player_id, card_uid)
		if bool(result.get("ok", false)):
			blockers.append(card_uid)
	return blockers

func _can_pay_ap(player: PlayerState, amount: int) -> bool:
	return player.ap_active_count() >= amount

func _has_required_energy(state: GameState, player: PlayerState, cost: Dictionary) -> bool:
	if cost.is_empty():
		return true
	var pool := {}
	# 当前按能量区已提供的颜色做静态汇总，不区分横置消耗或更复杂的支付方式。
	for card_uid in player.energy_line:
		var card: CardInstance = state.get_card(card_uid)
		var card_def: CardDef = null
		if card != null:
			card_def = state.get_card_def(card.def_id)
		if card_def == null:
			continue
		for color in card_def.energy_provided.keys():
			pool[color] = int(pool.get(color, 0)) + int(card_def.energy_provided.get(color, 0))
	for color in cost.keys():
		if int(pool.get(color, 0)) < int(cost.get(color, 0)):
			return false
	return true

func _validate_special_play_rule(state: GameState, player_id: String, card: CardInstance, card_def: CardDef, target_zone: int, options: Dictionary) -> Dictionary:
	if card_def.special_play_rule.is_empty():
		return {"ok": true, "mode": "NORMAL"}
	if str(card_def.special_play_rule.get("type", "")) != "RAID":
		return {"ok": true, "mode": "NORMAL"}
	if bool(card_def.special_play_rule.get("life_trigger_only", false)) and not bool(options.get("allow_raid_play", false)):
		return {"ok": true, "mode": "NORMAL"}
	var raid_target_uid := str(options.get("raid_target_uid", ""))
	if raid_target_uid == "":
		return {"ok": true, "mode": "NORMAL"}
	var raid_target: CardInstance = state.get_card(raid_target_uid)
	if raid_target == null:
		return {"ok": false, "reason": "raid_target_missing"}
	if raid_target.controller_player_id != player_id:
		return {"ok": false, "reason": "raid_target_wrong_controller"}
	if raid_target.zone != UATypes.Zone.FRONT_LINE and raid_target.zone != UATypes.Zone.ENERGY_LINE:
		return {"ok": false, "reason": "raid_target_bad_zone"}
	var raid_target_def: CardDef = state.get_card_def(raid_target.def_id)
	if raid_target_def == null:
		return {"ok": false, "reason": "raid_target_missing_def"}
	if raid_target_def.card_type != UATypes.CardType.CHARACTER:
		return {"ok": false, "reason": "raid_target_not_character"}
	var required_name := str(card_def.special_play_rule.get("raid_target_name", ""))
	if required_name != "" and raid_target_def.name != required_name:
		return {"ok": false, "reason": "raid_target_name_mismatch"}
	var requested_zone := int(options.get("raid_target_zone_choice", target_zone))
	var resolved_target_zone := requested_zone
	if raid_target.zone == UATypes.Zone.FRONT_LINE:
		if requested_zone != UATypes.Zone.FRONT_LINE:
			return {"ok": false, "reason": "raid_target_zone_locked_front"}
		resolved_target_zone = UATypes.Zone.FRONT_LINE
	elif raid_target.zone == UATypes.Zone.ENERGY_LINE:
		if requested_zone == -1:
			return {
				"ok": false,
				"reason": "raid_zone_choice_required",
				"needs_choice": true,
				"raid_target_uid": raid_target_uid,
				"raid_target_zone": raid_target.zone,
			}
		if requested_zone != UATypes.Zone.FRONT_LINE and requested_zone != UATypes.Zone.ENERGY_LINE:
			return {"ok": false, "reason": "raid_bad_target_zone"}
		var player: PlayerState = state.get_player(player_id)
		if requested_zone == UATypes.Zone.FRONT_LINE and player != null and player.front_line.size() >= UATypes.MAX_FRONT_LINE:
			return {"ok": false, "reason": "front_line_full"}
	return {
		"ok": true,
		"mode": "RAID",
		"raid_target_uid": raid_target_uid,
		"raid_target_zone": raid_target.zone,
		"target_zone": resolved_target_zone,
	}

func _card_has_keyword(card: CardInstance, card_def: CardDef, keyword: String) -> bool:
	if card_def.keywords.has(keyword):
		return true
	var temp_keywords: Array = card.flags.get("temp_keywords", [])
	return temp_keywords.has(keyword)
