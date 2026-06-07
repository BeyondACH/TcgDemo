extends RefCounted
class_name BattleResolver

const UATypes = preload("res://core/ua_types.gd")
const RulesEngine = preload("res://core/rules_engine.gd")
const ZoneManager = preload("res://core/zone_manager.gd")
const EffectResolver = preload("res://core/effect_resolver.gd")
const PlayerUtils = preload("res://core/player_utils.gd")
const GameState = preload("res://data/game_state.gd")
const CardInstance = preload("res://data/card_instance.gd")
const CardDef = preload("res://data/card_def.gd")

var rules_engine: RulesEngine
var zone_manager: ZoneManager
var effect_resolver: EffectResolver

func _init(p_rules_engine: RulesEngine, p_zone_manager: ZoneManager, p_effect_resolver: EffectResolver) -> void:
	rules_engine = p_rules_engine
	zone_manager = p_zone_manager
	effect_resolver = p_effect_resolver

func declare_attack(state: GameState, attacker_uid: String, options: Dictionary = {}) -> Dictionary:
	var attacker := state.get_card(attacker_uid)
	if attacker == null:
		return {"ok": false, "reason": "missing_attacker"}
	var attacker_def: CardDef = state.get_card_def(attacker.def_id)
	if attacker_def == null:
		return {"ok": false, "reason": "missing_attacker_definition"}
	var result := rules_engine.can_attack(state, attacker.controller_player_id, attacker_uid, options)
	if not bool(result.get("ok", false)):
		return result
	var defender_player_id := PlayerUtils.opponent_of(attacker.controller_player_id)
	var target_kind := str(result.get("target_kind", "PLAYER"))
	var blockers: Array[String] = []
	if target_kind == "PLAYER" and not bool(result.get("is_sniper_attack", false)):
		blockers = rules_engine.get_available_blockers(state, defender_player_id)
	var target_uid := str(result.get("target_uid", ""))
	state.battle_context = {
		"attacker_uid": attacker_uid,
		"attacker_player_id": attacker.controller_player_id,
		"defender_player_id": defender_player_id,
		"target_kind": target_kind,
		"target_uid": target_uid,
		"blocker_uid": "",
		"is_direct_attack": target_kind == "PLAYER",
		"is_sniper_attack": bool(result.get("is_sniper_attack", false)),
		"damage_to_player": 0,
		"impact_damage": 0,
		"battle_outcome": "",
	}
	return {
		"ok": true,
		"attacker_uid": attacker_uid,
		"attack_log": _format_attack_log(attacker, attacker_def),
		"defender_player_id": defender_player_id,
		"target_kind": target_kind,
		"target_uid": target_uid,
		"is_sniper_attack": bool(result.get("is_sniper_attack", false)),
		"blockers": blockers,
	}

func resolve_attack(state: GameState, attacker_uid: String, blocker_uid := "") -> Array[String]:
	var logs: Array[String] = []
	var attacker: CardInstance = state.get_card(attacker_uid)
	if attacker == null:
		return ["Attack failed: attacker missing."]
	var attacker_def: CardDef = state.get_card_def(attacker.def_id)
	if attacker_def == null:
		return ["Attack failed: attacker definition missing."]
	var battle_context: Dictionary = state.battle_context.duplicate(true)
	if battle_context.is_empty():
		return ["Attack failed: missing battle context."]
	var defender_player_id := str(battle_context.get("defender_player_id", PlayerUtils.opponent_of(attacker.controller_player_id)))
	var target_kind := str(battle_context.get("target_kind", "PLAYER"))
	var target_uid := str(battle_context.get("target_uid", ""))
	var is_sniper_attack := bool(battle_context.get("is_sniper_attack", false))
	var resolved_battle_result: Dictionary = battle_context.duplicate(true)
	var was_repeat_attack := bool(attacker.flags.get("attacked_this_turn", false))
	attacker.state = UATypes.CardState.RESTED
	attacker.flags["attacked_this_turn"] = true
	logs.append_array(effect_resolver.resolve_trigger(attacker_uid, UATypes.TriggerType.ON_ATTACK, state, {
		"target_player_id": defender_player_id,
		"attacker_uid": attacker_uid,
		"target_uid": target_uid,
	}))
	var impact_damage := _impact_damage(attacker, attacker_def)
	if target_kind == "FRONT_CHARACTER":
		var target_card: CardInstance = state.get_card(target_uid)
		if target_card == null:
			state.battle_context = {}
			return ["Attack failed: missing target character."]
		var target_def: CardDef = state.get_card_def(target_card.def_id)
		if target_def == null:
			state.battle_context = {}
			return ["Attack failed: missing target character definition."]
		if attacker.current_bp >= target_card.current_bp:
			resolved_battle_result["battle_outcome"] = "ATTACKER_WIN"
			if target_card.zone == UATypes.Zone.FRONT_LINE:
				zone_manager.move_card(state, target_uid, UATypes.Zone.OUTSIDE)
			logs.append("%s defeats %s." % [attacker_def.name, target_def.name])
			logs.append_array(effect_resolver.resolve_simultaneous_triggers(state, [
				{
					"source_card_uid": attacker_uid,
					"owner_player_id": attacker.controller_player_id,
					"trigger_type": UATypes.TriggerType.ON_BATTLE_WIN,
					"context": {
						"target_player_id": defender_player_id,
						"attacker_uid": attacker_uid,
						"target_uid": target_uid,
					},
				},
				{
					"source_card_uid": target_uid,
					"owner_player_id": target_card.controller_player_id,
					"trigger_type": UATypes.TriggerType.ON_LEAVE,
					"context": {
						"target_player_id": target_card.controller_player_id,
						"attacker_uid": attacker_uid,
						"target_uid": target_uid,
					},
				},
			]))
			if impact_damage > 0 and not _impact_negated(state, target_uid):
				resolved_battle_result["impact_damage"] = impact_damage
				logs.append_array(effect_resolver.deal_damage_to_player(state, defender_player_id, impact_damage))
			elif impact_damage > 0:
				logs.append("%s negates impact damage." % target_def.name)
		else:
			resolved_battle_result["battle_outcome"] = "ATTACKER_FAILS_TO_DEFEAT"
			logs.append("%s fails to defeat %s." % [attacker_def.name, target_def.name])
			logs.append_array(effect_resolver.resolve_trigger(attacker_uid, UATypes.TriggerType.ON_BATTLE_LOSE, state, {
				"target_player_id": defender_player_id,
				"attacker_uid": attacker_uid,
				"target_uid": target_uid,
			}))
		logs.append_array(effect_resolver.resolve_trigger(attacker_uid, UATypes.TriggerType.ON_BATTLE_END, state, {
			"target_player_id": defender_player_id,
			"attacker_uid": attacker_uid,
			"target_uid": target_uid,
			"battle_outcome": str(resolved_battle_result.get("battle_outcome", "")),
		}))
		_after_attack_state_change(attacker, attacker_def, was_repeat_attack)
		state.last_battle_result = resolved_battle_result
		state.battle_context = {}
		return logs
	if blocker_uid != "" and not is_sniper_attack:
		var block_validation := rules_engine.can_block(state, defender_player_id, blocker_uid)
		if not bool(block_validation.get("ok", false)):
			logs.append("Selected blocker is invalid, attack hits player instead.")
			var fallback_damage := _direct_attack_damage(attacker, attacker_def)
			resolved_battle_result["damage_to_player"] = fallback_damage
			resolved_battle_result["battle_outcome"] = "DIRECT_DAMAGE"
			logs.append_array(effect_resolver.deal_damage_to_player(state, defender_player_id, fallback_damage))
			_after_attack_state_change(attacker, attacker_def, was_repeat_attack)
			state.last_battle_result = resolved_battle_result
			state.battle_context = {}
			return logs
		var blocker: CardInstance = state.get_card(blocker_uid)
		var blocker_def: CardDef = null
		if blocker != null:
			blocker_def = state.get_card_def(blocker.def_id)
		if blocker == null or blocker_def == null:
			logs.append("Blocker missing, attack hits player instead.")
			var fallback_damage_missing := _direct_attack_damage(attacker, attacker_def)
			resolved_battle_result["damage_to_player"] = fallback_damage_missing
			resolved_battle_result["battle_outcome"] = "DIRECT_DAMAGE"
			logs.append_array(effect_resolver.deal_damage_to_player(state, defender_player_id, fallback_damage_missing))
			_after_attack_state_change(attacker, attacker_def, was_repeat_attack)
			state.last_battle_result = resolved_battle_result
			state.battle_context = {}
			return logs
		var was_repeat_block := bool(blocker.flags.get("blocked_this_turn", false))
		blocker.state = UATypes.CardState.RESTED
		blocker.flags["blocked_this_turn"] = true
		resolved_battle_result["blocker_uid"] = blocker_uid
		logs.append("%s blocks." % blocker_def.name)
		logs.append_array(effect_resolver.resolve_trigger(blocker_uid, UATypes.TriggerType.ON_BLOCK, state, {
			"target_player_id": defender_player_id,
			"attacker_uid": attacker_uid,
			"blocker_uid": blocker_uid,
		}))
		if attacker.current_bp >= blocker.current_bp:
			resolved_battle_result["battle_outcome"] = "ATTACKER_WIN"
			if blocker.zone == UATypes.Zone.FRONT_LINE:
				zone_manager.move_card(state, blocker_uid, UATypes.Zone.OUTSIDE)
				logs.append("%s wins the battle. %s is moved to outside." % [attacker_def.name, blocker_def.name])
			else:
				logs.append("%s wins the battle. %s leaves the field." % [attacker_def.name, blocker_def.name])
			logs.append_array(effect_resolver.resolve_simultaneous_triggers(state, [
				{
					"source_card_uid": attacker_uid,
					"owner_player_id": attacker.controller_player_id,
					"trigger_type": UATypes.TriggerType.ON_BATTLE_WIN,
					"context": {
						"target_player_id": defender_player_id,
						"attacker_uid": attacker_uid,
						"blocker_uid": blocker_uid,
					},
				},
				{
					"source_card_uid": blocker_uid,
					"owner_player_id": blocker.controller_player_id,
					"trigger_type": UATypes.TriggerType.ON_LEAVE,
					"context": {
						"target_player_id": blocker.controller_player_id,
						"attacker_uid": attacker_uid,
						"blocker_uid": blocker_uid,
					},
				},
			]))
			if impact_damage > 0 and not _impact_negated(state, blocker_uid):
				resolved_battle_result["impact_damage"] = impact_damage
				logs.append_array(effect_resolver.deal_damage_to_player(state, defender_player_id, impact_damage))
			elif impact_damage > 0:
				logs.append("%s negates impact damage." % blocker_def.name)
		else:
			resolved_battle_result["battle_outcome"] = "ATTACKER_FAILS_TO_DEFEAT"
			logs.append("%s fails to defeat %s." % [attacker_def.name, blocker_def.name])
			logs.append_array(effect_resolver.resolve_trigger(attacker_uid, UATypes.TriggerType.ON_BATTLE_LOSE, state, {
				"target_player_id": defender_player_id,
				"attacker_uid": attacker_uid,
				"blocker_uid": blocker_uid,
			}))
		logs.append_array(effect_resolver.resolve_trigger(attacker_uid, UATypes.TriggerType.ON_BATTLE_END, state, {
			"target_player_id": defender_player_id,
			"attacker_uid": attacker_uid,
			"blocker_uid": blocker_uid,
			"battle_outcome": str(resolved_battle_result.get("battle_outcome", "")),
		}))
		_after_block_state_change(blocker, blocker_def, was_repeat_block)
	else:
		var direct_damage := _direct_attack_damage(attacker, attacker_def)
		resolved_battle_result["damage_to_player"] = direct_damage
		resolved_battle_result["battle_outcome"] = "DIRECT_DAMAGE"
		logs.append_array(effect_resolver.deal_damage_to_player(state, defender_player_id, direct_damage))
		logs.append_array(effect_resolver.resolve_trigger(attacker_uid, UATypes.TriggerType.ON_BATTLE_END, state, {
			"target_player_id": defender_player_id,
			"attacker_uid": attacker_uid,
			"battle_outcome": str(resolved_battle_result.get("battle_outcome", "")),
		}))
	_after_attack_state_change(attacker, attacker_def, was_repeat_attack)
	state.last_battle_result = resolved_battle_result
	state.battle_context = {}
	return logs

func _direct_attack_damage(attacker: CardInstance, attacker_def: CardDef) -> int:
	if _card_has_keyword(attacker, attacker_def, "DAMAGE_2"):
		return 2
	return 1

func _impact_damage(attacker: CardInstance, attacker_def: CardDef) -> int:
	var base := 1 if _card_has_keyword(attacker, attacker_def, "IMPACT") else 0
	if _card_has_keyword(attacker, attacker_def, "IMPACT_PLUS_1"):
		base += 1
	return base

func _impact_negated(state: GameState, card_uid: String) -> bool:
	var card: CardInstance = state.get_card(card_uid)
	if card == null:
		return false
	var card_def: CardDef = state.get_card_def(card.def_id)
	if card_def == null:
		return false
	return _card_has_keyword(card, card_def, "NEGATE_IMPACT")

func _after_attack_state_change(attacker: CardInstance, attacker_def: CardDef, was_repeat_attack: bool) -> void:
	if not _card_has_keyword(attacker, attacker_def, "DOUBLE_ATTACK"):
		return
	if was_repeat_attack:
		attacker.flags["double_attack_consumed"] = true
	else:
		attacker.state = UATypes.CardState.ACTIVE

func _after_block_state_change(blocker: CardInstance, blocker_def: CardDef, was_repeat_block: bool) -> void:
	if not _card_has_keyword(blocker, blocker_def, "DOUBLE_BLOCK"):
		return
	if was_repeat_block:
		blocker.flags["double_block_consumed"] = true
	else:
		blocker.state = UATypes.CardState.ACTIVE

func _card_has_keyword(card: CardInstance, card_def: CardDef, keyword: String) -> bool:
	return card_def.keywords.has(keyword) or card.has_temp_keyword(keyword)

func _format_attack_log(attacker: CardInstance, attacker_def: CardDef) -> String:
	if attacker == null or attacker_def == null:
		return "Unknown attacker attacks."
	var labels: Array[String] = []
	var instance_uid := attacker.uid.strip_edges()
	if instance_uid != "":
		labels.append(instance_uid)
	var card_number := attacker_def.number.strip_edges()
	if card_number != "":
		labels.append(card_number)
	if not labels.is_empty():
		return "%s [%s] attacks." % [attacker_def.name, " | ".join(labels)]
	return "%s attacks." % attacker_def.name
