extends RefCounted
class_name RulesEngine

const UATypes = preload("res://core/ua_types.gd")
const ZoneManager = preload("res://core/zone_manager.gd")
const PlayerUtils = preload("res://core/player_utils.gd")
const GameState = preload("res://data/game_state.gd")
const PlayerState = preload("res://data/player_state.gd")
const CardInstance = preload("res://data/card_instance.gd")
const CardDef = preload("res://data/card_def.gd")
const ActionTypes = preload("res://core/actions/action_types.gd")
const ActionFactory = preload("res://core/actions/action_factory.gd")

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
	if not _play_requirements_met(state, player_id, card, card_def):
		return {"ok": false, "reason": "play_requirements_not_met"}
	var is_raid_play := str(raid_validation.get("mode", "NORMAL")) == "RAID"
	var effective_cost_ap := int(play_modifiers.get("cost_ap", card_def.cost_ap))
	var effective_cost_energy: Dictionary = play_modifiers.get("cost_energy", card_def.cost_energy)
	if not _can_pay_ap(player, effective_cost_ap):
		return {"ok": false, "reason": "not_enough_ap"}
	if not _has_required_energy(state, player, effective_cost_energy):
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

func _play_requirements_met(state: GameState, player_id: String, card: CardInstance, card_def: CardDef) -> bool:
	var requirements: Array = card_def.play_rule.get("requirements", [])
	for requirement_variant in requirements:
		if not _matches_play_requirement(state, player_id, card, card_def, requirement_variant):
			return false
	return true

func _matches_play_requirement(state: GameState, player_id: String, card: CardInstance, card_def: CardDef, requirement_variant) -> bool:
	var requirement: Dictionary = requirement_variant
	var requirement_type := str(requirement.get("type", ""))
	match requirement_type:
		"":
			return true
		"OR":
			for nested in requirement.get("requirements", requirement.get("filters", [])):
				if _matches_play_requirement(state, player_id, card, card_def, nested):
					return true
			return false
		"NOT":
			var nested = requirement.get("requirement", {})
			if nested.is_empty():
				var nested_list: Array = requirement.get("requirements", [])
				if nested_list.size() == 1:
					nested = nested_list[0]
			return not _matches_play_requirement(state, player_id, card, card_def, nested)
		"CONTROLLER_HAS_NAME_IN_FIELD":
			var player: PlayerState = state.get_player(player_id)
			if player == null:
				return false
			var required_name := str(requirement.get("value", ""))
			for zone_cards in [player.front_line, player.energy_line]:
				for card_uid in zone_cards:
					var field_card = state.get_card(str(card_uid))
					var field_def = state.get_card_def(field_card.def_id) if field_card != null else null
					if field_def != null and field_def.matches_reference_name(required_name):
						return true
			return false
		"PLAYER_TURN_FLAG_TRUE":
			var flags: Dictionary = state.player_turn_flags.get(player_id, {})
			return bool(flags.get(str(requirement.get("flag", "")), false))
	return true

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
	if _card_has_keyword(card, card_def, "CANNOT_ATTACK"):
		return {"ok": false, "reason": "cannot_attack"}
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

func get_legal_actions(state: GameState, player_id: String) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if player_id == "":
		return actions
	if not _player_has_priority(state, player_id):
		return actions
	if not state.pending_decisions.is_empty():
		return _build_pending_decision_actions(state, player_id)
	if not state.pending_life_triggers.is_empty():
		return _build_life_trigger_actions(state, player_id)
	if not state.battle_context.is_empty():
		return _build_battle_response_actions(state, player_id)
	if state.active_player_id != player_id:
		return actions
	match state.phase:
		UATypes.Phase.DRAW:
			actions.append_array(_build_draw_actions(state, player_id))
		UATypes.Phase.MOVE:
			actions.append_array(_build_move_actions(state, player_id))
		UATypes.Phase.MAIN:
			actions.append_array(_build_main_actions(state, player_id))
		UATypes.Phase.ATTACK:
			actions.append_array(_build_attack_actions(state, player_id))
		UATypes.Phase.END:
			actions.append(ActionFactory.make_end_turn_action(player_id))
	return actions

func get_card_available_actions(state: GameState, player_id: String, card_uid: String) -> Array[String]:
	var result: Array[String] = []
	for action in get_legal_actions(state, player_id):
		if str(action.get("source_card_uid", "")) != card_uid:
			continue
		var projected := _project_action_name(action)
		if projected != "" and not result.has(projected):
			result.append(projected)
	return result

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

# Returns the energy pool dictionary for a player (used by UI serialization)
func get_energy_pool_for_player(state: GameState, player: PlayerState) -> Dictionary:
	return _compute_energy_pool(state, player)

func _compute_energy_pool(state: GameState, player: PlayerState) -> Dictionary:
	var pool := {}
	for card_uid in player.energy_line:
		var card: CardInstance = state.get_card(card_uid)
		var card_def: CardDef = null
		if card != null:
			card_def = state.get_card_def(card.def_id)
		if card_def == null:
			continue
		for color in card_def.energy_provided.keys():
			pool[color] = int(pool.get(color, 0)) + int(card_def.energy_provided.get(color, 0))
		for passive_bonus in _passive_energy_bonus_modifiers(state, card, card_def):
			var passive_color := str(passive_bonus.get("color", ""))
			var passive_value := int(passive_bonus.get("value", 0))
			if passive_color != "" and passive_value != 0:
				pool[passive_color] = int(pool.get(passive_color, 0)) + passive_value
	for modifier_variant in state.static_modifiers:
		var modifier: Dictionary = modifier_variant
		if str(modifier.get("modifier_type", "")) != "ENERGY_BONUS":
			continue
		if str(modifier.get("owner_player_id", "")) != player.player_id:
			continue
		var source_uid := str(modifier.get("source_card_uid", ""))
		var source_card: CardInstance = state.get_card(source_uid)
		if source_card == null or source_card.zone != UATypes.Zone.ENERGY_LINE:
			continue
		if not _check_energy_bonus_condition(state, modifier, source_uid):
			continue
		var color := str(modifier.get("color", ""))
		var value := int(modifier.get("value", 0))
		if color != "" and value != 0:
			pool[color] = int(pool.get(color, 0)) + value
	return pool

func _build_draw_actions(state: GameState, player_id: String) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return actions
	if not player.used_bonus_draw and player.ap_active_count() >= 1:
		actions.append(ActionFactory.make_action(
			"bonus_draw:%s:%d" % [player_id, player.turn_count],
			ActionTypes.BONUS_DRAW,
			player_id,
			"Pay 1 AP for bonus draw",
			{},
			"",
			30
		))
	actions.append(ActionFactory.make_phase_action(player_id, "DRAW"))
	return actions

func _build_move_actions(state: GameState, player_id: String) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return actions
	for card_uid in player.front_line:
		var card: CardInstance = state.get_card(card_uid)
		var card_def: CardDef = state.get_card_def(card.def_id) if card != null else null
		if card == null or card_def == null:
			continue
		var step_result := can_step_move_to_energy(state, player_id, card_uid)
		if bool(step_result.get("ok", false)):
			actions.append(ActionFactory.make_action(
				"move:%s:step:%s" % [player_id, card_uid],
				ActionTypes.MOVE_CARD,
				player_id,
				"STEP to energy",
				{
					"mode": ActionTypes.MOVE_STEP_TO_ENERGY,
					"source_bp": card.current_bp,
				},
				card_uid,
				15
			))
		elif str(step_result.get("reason", "")) == "step_swap_required":
			actions.append(ActionFactory.make_action(
				"move:%s:step:%s:swap" % [player_id, card_uid],
				ActionTypes.MOVE_CARD,
				player_id,
				"STEP to energy (choose swap)",
				{
					"mode": ActionTypes.MOVE_STEP_TO_ENERGY,
					"requires_choice": true,
					"source_bp": card.current_bp,
				},
				card_uid,
				15
			))
	for card_uid in player.energy_line:
		var card: CardInstance = state.get_card(card_uid)
		var card_def: CardDef = state.get_card_def(card.def_id) if card != null else null
		if card == null or card_def == null:
			continue
		var move_result := can_move_energy_to_front(state, player_id, card_uid)
		if bool(move_result.get("ok", false)):
			actions.append(ActionFactory.make_action(
				"move:%s:front:%s" % [player_id, card_uid],
				ActionTypes.MOVE_CARD,
				player_id,
				"Move to front line",
				{
					"mode": ActionTypes.MOVE_ENERGY_TO_FRONT,
					"source_bp": card.current_bp,
				},
				card_uid,
				25
			))
	actions.append(ActionFactory.make_phase_action(player_id, "MOVE"))
	return actions

func _build_main_actions(state: GameState, player_id: String) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return actions
	for card_uid in player.hand:
		var card: CardInstance = state.get_card(card_uid)
		var card_def: CardDef = state.get_card_def(card.def_id) if card != null else null
		if card == null or card_def == null:
			continue
		actions.append_array(_build_hand_play_actions(state, player_id, card, card_def))
	for zone_cards in [player.front_line, player.energy_line]:
		for card_uid in zone_cards:
			var card: CardInstance = state.get_card(card_uid)
			var card_def: CardDef = state.get_card_def(card.def_id) if card != null else null
			if card == null or card_def == null:
				continue
			for effect_index in range(card_def.trigger_effects.size()):
				var effect: Dictionary = card_def.trigger_effects[effect_index]
				if str(effect.get("trigger", "")) != "MAIN_ACTIVATE":
					continue
				actions.append(ActionFactory.make_action(
					"activate:%s:%s:%d" % [player_id, card_uid, effect_index],
					ActionTypes.ACTIVATE_EFFECT,
					player_id,
					"Activate main ability",
					{"effect_index": effect_index},
					card_uid,
					20
				))
				break
	actions.append(ActionFactory.make_phase_action(player_id, "MAIN"))
	return actions

func _build_attack_actions(state: GameState, player_id: String) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return actions
	var opponent_id := PlayerUtils.opponent_of(player_id)
	var opponent: PlayerState = state.get_player(opponent_id)
	for card_uid in player.front_line:
		var card: CardInstance = state.get_card(card_uid)
		var card_def: CardDef = state.get_card_def(card.def_id) if card != null else null
		if card == null or card_def == null:
			continue
		var direct_result := can_attack(state, player_id, card_uid)
		if bool(direct_result.get("ok", false)):
			actions.append(ActionFactory.make_action(
				"attack:%s:%s:player" % [player_id, card_uid],
				ActionTypes.ATTACK,
				player_id,
				"Attack opposing player",
				{
					"target_kind": "PLAYER",
					"source_bp": card.current_bp,
				},
				card_uid,
				50
			))
		if opponent == null or not _card_has_keyword(card, card_def, "SNIPER"):
			continue
		for target_uid in opponent.front_line:
			var target_card: CardInstance = state.get_card(target_uid)
			var target_def: CardDef = state.get_card_def(target_card.def_id) if target_card != null else null
			if target_card == null or target_def == null:
				continue
			var sniper_result := can_attack(state, player_id, card_uid, {
				"target_kind": "FRONT_CHARACTER",
				"target_uid": target_uid,
			})
			if not bool(sniper_result.get("ok", false)):
				continue
			actions.append(ActionFactory.make_action(
				"attack:%s:%s:sniper:%s" % [player_id, card_uid, target_uid],
				ActionTypes.ATTACK,
				player_id,
				"Sniper attack %s" % target_def.name,
				{
					"target_kind": "FRONT_CHARACTER",
					"target_uid": target_uid,
					"source_bp": card.current_bp,
					"target_bp": target_card.current_bp,
				},
				card_uid,
				40
			))
	actions.append(ActionFactory.make_phase_action(player_id, "ATTACK"))
	return actions

func _build_battle_response_actions(state: GameState, player_id: String) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var battle_context: Dictionary = state.battle_context
	if battle_context.is_empty():
		return actions
	if str(battle_context.get("defender_player_id", "")) != player_id:
		return actions
	if str(battle_context.get("target_kind", "PLAYER")) != "PLAYER" or bool(battle_context.get("is_sniper_attack", false)):
		return actions
	var attacker_uid := str(battle_context.get("attacker_uid", ""))
	for blocker_uid in get_available_blockers(state, player_id):
		var blocker: CardInstance = state.get_card(blocker_uid)
		var blocker_def: CardDef = state.get_card_def(blocker.def_id) if blocker != null else null
		actions.append(ActionFactory.make_action(
			"block:%s:%s:%s" % [player_id, attacker_uid, blocker_uid],
			ActionTypes.BLOCK,
			player_id,
			"Block with %s" % (blocker_def.name if blocker_def != null else blocker_uid),
			{
				"attacker_uid": attacker_uid,
				"blocker_uid": blocker_uid,
				"source_bp": blocker.current_bp if blocker != null else 0,
			},
			blocker_uid,
			35
		))
	actions.append(ActionFactory.make_action(
		"block:%s:%s:none" % [player_id, attacker_uid],
		ActionTypes.NO_BLOCK,
		player_id,
		"Do not block",
		{"attacker_uid": attacker_uid},
		"",
		-50
	))
	return actions

func _build_pending_decision_actions(state: GameState, player_id: String) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	for decision_variant in state.pending_decisions:
		var decision: Dictionary = decision_variant
		if str(decision.get("owner_player_id", "")) != player_id:
			continue
		var choices: Array = decision.get("choices", [])
		for index in range(choices.size()):
			var choice: Dictionary = choices[index]
			var choice_value = choice.get("value")
			var choice_label := str(choice.get("label", choice_value))
			var params := {
				"decision_type": str(decision.get("type", "")),
				"choice": choice_value,
				"source_card_uid": str(decision.get("source_card_uid", "")),
				"resolution_id": str(decision.get("resolution_id", "")),
				"choice_index": index,
				"choice_label": choice_label,
			}
			var choice_card := state.get_card(str(choice_value))
			if choice_card != null:
				params["choice_bp"] = choice_card.current_bp
			actions.append(ActionFactory.make_action(
				"decision:%s:%s:%s:%d" % [player_id, str(decision.get("type", "")), str(decision.get("source_card_uid", "")), index],
				ActionTypes.RESOLVE_PENDING_DECISION,
				player_id,
				"Resolve %s: %s" % [str(decision.get("type", "decision")), choice_label],
				params,
				str(decision.get("source_card_uid", "")),
				10
			))
		return actions
	return actions

func _build_life_trigger_actions(state: GameState, player_id: String) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	for entry_variant in state.pending_life_triggers:
		var entry: Dictionary = entry_variant
		if str(entry.get("player_id", "")) != player_id:
			continue
		var card_uid := str(entry.get("card_uid", ""))
		var card_name := str(entry.get("card_name", card_uid))
		actions.append(ActionFactory.make_action(
			"life:%s:%s:activate" % [player_id, card_uid],
			ActionTypes.RESOLVE_LIFE_TRIGGER,
			player_id,
			"Activate life trigger: %s" % card_name,
			{"card_uid": card_uid, "activate": true},
			card_uid,
			20
		))
		actions.append(ActionFactory.make_action(
			"life:%s:%s:skip" % [player_id, card_uid],
			ActionTypes.RESOLVE_LIFE_TRIGGER,
			player_id,
			"Skip life trigger: %s" % card_name,
			{"card_uid": card_uid, "activate": false},
			card_uid,
			-20
		))
		return actions
	return actions

func _build_hand_play_actions(state: GameState, player_id: String, card: CardInstance, card_def: CardDef) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var card_type_text := UATypes.card_type_to_text(card_def.card_type)
	if card_def.card_type == UATypes.CardType.CHARACTER:
		for target_zone in [UATypes.Zone.FRONT_LINE, UATypes.Zone.ENERGY_LINE]:
			var validation := can_play_card(state, player_id, card.uid, target_zone)
			if not bool(validation.get("ok", false)):
				continue
			var target_label := "front line" if target_zone == UATypes.Zone.FRONT_LINE else "energy line"
			actions.append(ActionFactory.make_action(
				"play:%s:%s:%d" % [player_id, card.uid, target_zone],
				ActionTypes.PLAY_CARD,
				player_id,
				"Play %s to %s" % [card_def.name, target_label],
				{
					"target_zone": target_zone,
					"card_type": card_type_text,
					"source_bp": card.current_bp,
				},
				card.uid,
				35 if target_zone == UATypes.Zone.FRONT_LINE else 25
			))
	elif card_def.card_type == UATypes.CardType.FIELD:
		var field_validation := can_play_card(state, player_id, card.uid, UATypes.Zone.ENERGY_LINE)
		if bool(field_validation.get("ok", false)):
			actions.append(ActionFactory.make_action(
				"play:%s:%s:%d" % [player_id, card.uid, UATypes.Zone.ENERGY_LINE],
				ActionTypes.PLAY_CARD,
				player_id,
				"Play %s to energy line" % card_def.name,
				{
					"target_zone": UATypes.Zone.ENERGY_LINE,
					"card_type": card_type_text,
					"source_bp": card.current_bp,
				},
				card.uid,
				15
			))
	elif card_def.card_type == UATypes.CardType.EVENT:
		var event_validation := can_play_card(state, player_id, card.uid, UATypes.Zone.OUTSIDE)
		if bool(event_validation.get("ok", false)):
			actions.append(ActionFactory.make_action(
				"play:%s:%s:event" % [player_id, card.uid],
				ActionTypes.PLAY_CARD,
				player_id,
				"Use event %s" % card_def.name,
				{
					"target_zone": UATypes.Zone.OUTSIDE,
					"card_type": card_type_text,
					"source_bp": card.current_bp,
				},
				card.uid,
				18
			))
	if str(card_def.special_play_rule.get("type", "")) == "RAID":
		actions.append_array(_build_raid_actions(state, player_id, card, card_def))
	return actions

func _build_raid_actions(state: GameState, player_id: String, card: CardInstance, card_def: CardDef) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return actions
	var required_name := str(card_def.special_play_rule.get("raid_target_name", ""))
	for zone_cards in [player.front_line, player.energy_line]:
		for target_uid_variant in zone_cards:
			var target_uid := str(target_uid_variant)
			var target_card: CardInstance = state.get_card(target_uid)
			var target_def: CardDef = state.get_card_def(target_card.def_id) if target_card != null else null
			if target_card == null or target_def == null:
				continue
			if target_def.card_type != UATypes.CardType.CHARACTER:
				continue
			if required_name != "" and not target_def.matches_reference_name(required_name):
				continue
			var target_zones := [UATypes.Zone.FRONT_LINE] if target_card.zone == UATypes.Zone.FRONT_LINE else [UATypes.Zone.ENERGY_LINE, UATypes.Zone.FRONT_LINE]
			for target_zone in target_zones:
				var validation := can_play_card(state, player_id, card.uid, target_zone, {}, {
					"raid_target_uid": target_uid,
					"raid_target_zone_choice": target_zone,
				})
				if not bool(validation.get("ok", false)):
					continue
				if str(validation.get("special_play", {}).get("mode", "NORMAL")) != "RAID":
					continue
				actions.append(ActionFactory.make_action(
					"play:%s:%s:raid:%s:%d" % [player_id, card.uid, target_uid, target_zone],
					ActionTypes.PLAY_CARD,
					player_id,
					"RAID %s onto %s" % [card_def.name, target_def.name],
					{
						"target_zone": target_zone,
						"raid_target_uid": target_uid,
						"raid_target_zone_choice": target_zone,
						"card_type": UATypes.card_type_to_text(card_def.card_type),
						"special_play_mode": "RAID",
						"source_bp": card.current_bp,
						"target_bp": target_card.current_bp,
					},
					card.uid,
					45
				))
	return actions

func _player_has_priority(state: GameState, player_id: String) -> bool:
	if not state.pending_decisions.is_empty():
		return str((state.pending_decisions[0] as Dictionary).get("owner_player_id", "")) == player_id
	if not state.pending_life_triggers.is_empty():
		return str((state.pending_life_triggers[0] as Dictionary).get("player_id", "")) == player_id
	if not state.battle_context.is_empty():
		var battle_context: Dictionary = state.battle_context
		if str(battle_context.get("target_kind", "PLAYER")) == "PLAYER" and not bool(battle_context.get("is_sniper_attack", false)):
			return str(battle_context.get("defender_player_id", "")) == player_id
	return state.active_player_id == player_id

func _project_action_name(action: Dictionary) -> String:
	var action_type := str(action.get("type", ""))
	var params: Dictionary = action.get("params", {})
	match action_type:
		ActionTypes.PLAY_CARD:
			var special_mode := str(params.get("special_play_mode", ""))
			if special_mode == "RAID":
				return "RAID"
			var target_zone := int(params.get("target_zone", -1))
			if target_zone == UATypes.Zone.FRONT_LINE:
				return "PLAY_FRONT"
			if target_zone == UATypes.Zone.ENERGY_LINE:
				return "PLAY_ENERGY"
			if target_zone == UATypes.Zone.OUTSIDE:
				return "PLAY_EVENT"
		ActionTypes.MOVE_CARD:
			var mode := str(params.get("mode", ""))
			if mode == ActionTypes.MOVE_STEP_TO_ENERGY:
				return "STEP_TO_ENERGY"
			if mode == ActionTypes.MOVE_ENERGY_TO_FRONT:
				return "MOVE_TO_FRONT"
		ActionTypes.ATTACK:
			if str(params.get("target_kind", "PLAYER")) == "FRONT_CHARACTER":
				return "SNIPER_ATTACK"
			return "ATTACK_PLAYER"
		ActionTypes.ACTIVATE_EFFECT:
			return "MAIN_ACTIVATE"
	return ""

func _can_pay_ap(player: PlayerState, amount: int) -> bool:
	return player.ap_active_count() >= amount

func _has_required_energy(state: GameState, player: PlayerState, cost: Dictionary) -> bool:
	if cost.is_empty():
		return true
	var pool := _compute_energy_pool(state, player)
	for color in cost.keys():
		if int(pool.get(color, 0)) < int(cost.get(color, 0)):
			return false
	return true

func _passive_energy_bonus_modifiers(state: GameState, card: CardInstance, card_def: CardDef) -> Array[Dictionary]:
	var modifiers: Array[Dictionary] = []
	if card == null or card_def == null:
		return modifiers
	for ability_variant in card_def.abilities:
		var ability: Dictionary = ability_variant
		var event_name := str(ability.get("timing", {}).get("event", ""))
		var kind := str(ability.get("kind", ""))
		if event_name != "PASSIVE" and kind != "STATIC":
			continue
		for step_variant in ability.get("steps", []):
			var step: Dictionary = step_variant
			if str(step.get("type", "")) != "REGISTER_STATIC_MODIFIER":
				continue
			if str(step.get("modifier_type", "")) != "ENERGY_BONUS":
				continue
			if not _check_energy_bonus_condition(state, step, card.uid):
				continue
			modifiers.append(step)
	return modifiers

func _check_energy_bonus_condition(state: GameState, modifier: Dictionary, source_uid: String) -> bool:
	var while_reqs: Array = modifier.get("while", [])
	if while_reqs.is_empty():
		return true
	var source_card: CardInstance = state.get_card(source_uid)
	if source_card == null:
		return false
	var player = state.get_player(source_card.controller_player_id)
	if player == null:
		return false
	for req_variant in while_reqs:
		var req: Dictionary = req_variant
		if str(req.get("type", "")) == "CONTROLLER_TRAIT_NAME_COUNT_GTE":
			var trait_value := str(req.get("trait", ""))
			var min_count := int(req.get("value", 0))
			var unique_names: Dictionary = {}
			for zone_cards in [player.front_line, player.energy_line]:
				for cuid_v in zone_cards:
					var cuid := str(cuid_v)
					if cuid == source_uid:
						continue
					var c = state.get_card(cuid)
					if c == null:
						continue
					var d = state.get_card_def(c.def_id)
					if d != null and d.traits.has(trait_value):
						unique_names[d.name] = true
			if unique_names.size() < min_count:
				return false
		elif str(req.get("type", "")) == "SOURCE_STATE_IS_ACTIVE":
			if source_card.state != UATypes.CardState.ACTIVE:
				return false
	return true

func _validate_special_play_rule(state: GameState, player_id: String, card: CardInstance, card_def: CardDef, target_zone: int, options: Dictionary) -> Dictionary:
	if card_def.special_play_rule.is_empty():
		return {"ok": true, "mode": "NORMAL"}
	if str(card_def.special_play_rule.get("type", "")) != "RAID":
		return {"ok": true, "mode": "NORMAL"}
	if card.zone == UATypes.Zone.HAND and not _can_raid_from_hand(state, player_id, card, card_def, options):
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
	if required_name != "" and not raid_target_def.matches_reference_name(required_name):
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

func _can_raid_from_hand(state: GameState, player_id: String, card: CardInstance, card_def: CardDef, options: Dictionary = {}) -> bool:
	if bool(options.get("allow_raid_play", false)):
		return true
	if not bool(card_def.special_play_rule.get("allow_from_hand", false)):
		return false
	return true

func _has_special_play_permission(state: GameState, player_id: String, card_uid: String, mode: String) -> bool:
	for modifier_variant in state.static_modifiers:
		var modifier: Dictionary = modifier_variant
		if str(modifier.get("modifier_type", "")) != "SPECIAL_PLAY_PERMISSION":
			continue
		if str(modifier.get("owner_player_id", "")) != player_id:
			continue
		if str(modifier.get("granted_card_uid", "")) != card_uid:
			continue
		var allowed_modes: Array = modifier.get("allowed_modes", [])
		if not allowed_modes.has(mode):
			continue
		return true
	return false

func _card_has_keyword(card: CardInstance, card_def: CardDef, keyword: String) -> bool:
	if card_def.keywords.has(keyword):
		return true
	var temp_keywords: Array = card.flags.get("temp_keywords", [])
	return temp_keywords.has(keyword)
