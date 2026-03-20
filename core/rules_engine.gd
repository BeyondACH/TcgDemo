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
	if state.active_player_id != player_id:
		return {"ok": false, "reason": "not_active_player"}
	if state.phase != UATypes.Phase.MAIN:
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

func can_attack(state: GameState, player_id: String, card_uid: String) -> Dictionary:
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
	return {"ok": true}

func can_block(state: GameState, player_id: String, card_uid: String) -> Dictionary:
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
	var resolved_target_zone := target_zone
	if raid_target.zone == UATypes.Zone.FRONT_LINE:
		if target_zone != UATypes.Zone.FRONT_LINE:
			return {"ok": false, "reason": "raid_target_zone_locked_front"}
		resolved_target_zone = UATypes.Zone.FRONT_LINE
	elif raid_target.zone == UATypes.Zone.ENERGY_LINE:
		if target_zone != UATypes.Zone.FRONT_LINE and target_zone != UATypes.Zone.ENERGY_LINE:
			return {"ok": false, "reason": "raid_bad_target_zone"}
		var player: PlayerState = state.get_player(player_id)
		if target_zone == UATypes.Zone.FRONT_LINE and player != null and player.front_line.size() >= UATypes.MAX_FRONT_LINE:
			return {"ok": false, "reason": "front_line_full"}
	return {
		"ok": true,
		"mode": "RAID",
		"raid_target_uid": raid_target_uid,
		"raid_target_zone": raid_target.zone,
		"target_zone": resolved_target_zone,
	}
