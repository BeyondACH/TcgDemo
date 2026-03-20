extends RefCounted
class_name BattleResolver

const UATypes = preload("res://core/ua_types.gd")
const RulesEngine = preload("res://core/rules_engine.gd")
const ZoneManager = preload("res://core/zone_manager.gd")
const EffectResolver = preload("res://core/effect_resolver.gd")
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

# 攻击宣言阶段只做攻击合法性检查，并把可阻挡者列表返回给 UI。
func declare_attack(state: GameState, attacker_uid: String) -> Dictionary:
	var attacker := state.get_card(attacker_uid)
	if attacker == null:
		return {"ok": false, "reason": "missing_attacker"}
	var result := rules_engine.can_attack(state, attacker.controller_player_id, attacker_uid)
	if not bool(result.get("ok", false)):
		return result
	var defender_player_id := _opponent_of(attacker.controller_player_id)
	var blockers := rules_engine.get_available_blockers(state, defender_player_id)
	return {
		"ok": true,
		"attacker_uid": attacker_uid,
		"defender_player_id": defender_player_id,
		"blockers": blockers,
	}

# 结算当前原型中的最小战斗流程：阻挡可选，阻挡后比 BP，未阻挡则直接打玩家。
func resolve_attack(state: GameState, attacker_uid: String, blocker_uid := "") -> Array[String]:
	var logs: Array[String] = []
	var attacker: CardInstance = state.get_card(attacker_uid)
	if attacker == null:
		return ["Attack failed: attacker missing."]
	var attacker_def: CardDef = state.get_card_def(attacker.def_id)
	if attacker_def == null:
		return ["Attack failed: attacker definition missing."]
	attacker.state = UATypes.CardState.RESTED
	attacker.flags["attacked_this_turn"] = true
	logs.append("%s attacks." % attacker_def.name)
	logs.append_array(effect_resolver.resolve_trigger(attacker_uid, UATypes.TriggerType.ON_ATTACK, state, {"target_player_id": _opponent_of(attacker.controller_player_id)}))
	if blocker_uid != "":
		var defending_player_id := _opponent_of(attacker.controller_player_id)
		var block_validation := rules_engine.can_block(state, defending_player_id, blocker_uid)
		if not bool(block_validation.get("ok", false)):
			logs.append("Selected blocker is invalid, attack hits player instead.")
			logs.append_array(effect_resolver.deal_damage_to_player(state, defending_player_id, 1))
			return logs
		var blocker: CardInstance = state.get_card(blocker_uid)
		var blocker_def: CardDef = null
		if blocker != null:
			blocker_def = state.get_card_def(blocker.def_id)
		if blocker == null or blocker_def == null:
			logs.append("Blocker missing, attack hits player instead.")
			logs.append_array(effect_resolver.deal_damage_to_player(state, defending_player_id, 1))
			return logs
		blocker.state = UATypes.CardState.RESTED
		blocker.flags["blocked_this_turn"] = true
		logs.append("%s blocks." % blocker_def.name)
		logs.append_array(effect_resolver.resolve_trigger(blocker_uid, UATypes.TriggerType.ON_BLOCK, state))
		# 当前实现只有“攻击者 BP 足够则击退阻挡者”这一层，
		# 尚未处理双败、反击伤害或更多关键字规则。
		if attacker.current_bp >= blocker.current_bp:
			zone_manager.move_card(state, blocker_uid, UATypes.Zone.OUTSIDE)
			logs.append("%s wins the battle. %s is moved to outside." % [attacker_def.name, blocker_def.name])
		else:
			logs.append("%s fails to defeat %s." % [attacker_def.name, blocker_def.name])
	else:
		logs.append_array(effect_resolver.deal_damage_to_player(state, _opponent_of(attacker.controller_player_id), 1))
	return logs

func _opponent_of(player_id: String) -> String:
	if player_id == UATypes.PLAYER_ONE:
		return UATypes.PLAYER_TWO
	return UATypes.PLAYER_ONE
