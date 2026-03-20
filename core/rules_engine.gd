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
func can_play_card(state: GameState, player_id: String, card_uid: String, target_zone: int) -> Dictionary:
	var player: PlayerState = state.get_player(player_id)
	var card: CardInstance = state.get_card(card_uid)
	if player == null or card == null:
		return {"ok": false, "reason": "missing_card_or_player"}
	if state.active_player_id != player_id:
		return {"ok": false, "reason": "not_active_player"}
	if state.phase != UATypes.Phase.MAIN:
		return {"ok": false, "reason": "wrong_phase"}
	if card.zone != UATypes.Zone.HAND:
		return {"ok": false, "reason": "not_in_hand"}
	var card_def: CardDef = state.get_card_def(card.def_id)
	if card_def == null:
		return {"ok": false, "reason": "missing_def"}
	if not _can_pay_ap(player, card_def.cost_ap):
		return {"ok": false, "reason": "not_enough_ap"}
	if not _has_required_energy(state, player, card_def.cost_energy):
		return {"ok": false, "reason": "not_enough_energy"}
	match card_def.card_type:
		UATypes.CardType.CHARACTER:
			if target_zone != UATypes.Zone.FRONT_LINE and target_zone != UATypes.Zone.ENERGY_LINE:
				return {"ok": false, "reason": "bad_character_zone"}
			if target_zone == UATypes.Zone.FRONT_LINE and player.front_line.size() >= UATypes.MAX_FRONT_LINE:
				return {"ok": false, "reason": "front_line_full"}
			if target_zone == UATypes.Zone.ENERGY_LINE and player.energy_line.size() >= UATypes.MAX_ENERGY_LINE:
				return {"ok": false, "reason": "energy_line_full"}
		UATypes.CardType.FIELD:
			if target_zone != UATypes.Zone.ENERGY_LINE:
				return {"ok": false, "reason": "field_must_go_energy"}
			if player.energy_line.size() >= UATypes.MAX_ENERGY_LINE:
				return {"ok": false, "reason": "energy_line_full"}
		UATypes.CardType.EVENT:
			if target_zone != UATypes.Zone.OUTSIDE:
				return {"ok": false, "reason": "event_resolves_to_outside"}
	return {"ok": true}

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
