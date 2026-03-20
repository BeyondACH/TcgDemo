extends RefCounted
class_name EffectResolver

const UATypes = preload("res://core/ua_types.gd")
const ZoneManager = preload("res://core/zone_manager.gd")
const VictoryChecker = preload("res://core/victory_checker.gd")
const GameState = preload("res://data/game_state.gd")

var zone_manager: ZoneManager
var victory_checker: VictoryChecker

func _init(p_zone_manager: ZoneManager, p_victory_checker: VictoryChecker) -> void:
	zone_manager = p_zone_manager
	victory_checker = p_victory_checker

# 结算当前原型支持的少量效果类型。
func resolve_operations(state: GameState, source_card_uid: String, effect_list: Array[Dictionary], context: Dictionary = {}) -> Array[String]:
	var logs: Array[String] = []
	for effect in effect_list:
		var effect_type := str(effect.get("type", ""))
		match effect_type:
			"DRAW":
				var target_player_id := str(context.get("target_player_id", state.active_player_id))
				var amount := int(effect.get("value", 1))
				for i in range(amount):
					var draw_uid := zone_manager.draw_card(state, target_player_id)
					if draw_uid == "":
						var defeat := victory_checker.check_deck_out_loss(state, target_player_id)
						if not defeat.is_empty():
							_apply_victory(state, defeat)
						logs.append("%s attempted to draw from an empty deck." % target_player_id)
						break
					logs.append("%s draws 1 card." % target_player_id)
			"MOVE_ZONE":
				var target_uid := str(effect.get("target_uid", source_card_uid))
				var to_zone := int(effect.get("to_zone", UATypes.Zone.OUTSIDE))
				zone_manager.move_card(state, target_uid, to_zone, str(context.get("target_player_id", "")))
				logs.append("Moved card %s to %s." % [target_uid, UATypes.zone_to_key(to_zone)])
			"REST":
				var rest_card := state.get_card(str(effect.get("target_uid", source_card_uid)))
				if rest_card != null:
					rest_card.state = UATypes.CardState.RESTED
					logs.append("%s becomes rested." % rest_card.uid)
			"ACTIVATE":
				var active_card := state.get_card(str(effect.get("target_uid", source_card_uid)))
				if active_card != null:
					active_card.state = UATypes.CardState.ACTIVE
					logs.append("%s becomes active." % active_card.uid)
			"DEAL_DAMAGE_TO_PLAYER":
				var target_id := str(context.get("target_player_id", ""))
				var damage := int(effect.get("value", 1))
				logs.append_array(deal_damage_to_player(state, target_id, damage))
			_:
				logs.append("Reserved unsupported effect type: %s" % effect_type)
	return logs

# 触发器本身只负责筛选匹配的触发项，实际操作仍复用统一的效果结算入口。
func resolve_trigger(source_card_uid: String, trigger_type: int, state: GameState, context: Dictionary = {}) -> Array[String]:
	var logs: Array[String] = []
	var source_card := state.get_card(source_card_uid)
	if source_card == null:
		return logs
	var card_def := state.get_card_def(source_card.def_id)
	if card_def == null:
		return logs
	for effect in card_def.trigger_effects:
		if _trigger_matches(effect, trigger_type):
			logs.append_array(resolve_operations(state, source_card_uid, effect.get("operations", []), context))
	return logs

func deal_damage_to_player(state: GameState, player_id: String, amount: int) -> Array[String]:
	var logs: Array[String] = []
	if player_id == "":
		return logs
	# 当前“受伤”表现为从生命区翻入场外区，并为这些牌补触发生命触发。
	var moved := zone_manager.mill_life_to_outside(state, player_id, amount)
	logs.append("%s takes %d damage." % [player_id, amount])
	for life_uid in moved:
		logs.append_array(resolve_trigger(life_uid, UATypes.TriggerType.ON_LIFE_TRIGGER, state, {"target_player_id": player_id}))
	var defeat := victory_checker.check_victory(state)
	if not defeat.is_empty():
		_apply_victory(state, defeat)
	return logs

func _apply_victory(state: GameState, result: Dictionary) -> void:
	state.winner_player_id = str(result.get("winner", ""))
	state.loser_player_id = str(result.get("loser", ""))

func _trigger_matches(effect: Dictionary, trigger_type: int) -> bool:
	var name := str(effect.get("trigger", ""))
	match trigger_type:
		UATypes.TriggerType.ON_ENTER:
			return name == "ON_ENTER"
		UATypes.TriggerType.ON_LEAVE:
			return name == "ON_LEAVE"
		UATypes.TriggerType.ON_ATTACK:
			return name == "ON_ATTACK"
		UATypes.TriggerType.ON_BLOCK:
			return name == "ON_BLOCK"
		UATypes.TriggerType.ON_LIFE_TRIGGER:
			return name == "ON_LIFE_TRIGGER"
		UATypes.TriggerType.MAIN_ACTIVATE:
			return name == "MAIN_ACTIVATE"
	return false
