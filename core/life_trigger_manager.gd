extends RefCounted
class_name LifeTriggerManager

## 生命触发/揭示管理器 - 负责管理生命触发和揭示流程
## 从 game_manager.gd 提取

const UATypes = preload("res://core/ua_types.gd")
const GameState = preload("res://data/game_state.gd")
const CardInstance = preload("res://data/card_instance.gd")
const CardDef = preload("res://data/card_def.gd")
const PlayerState = preload("res://data/player_state.gd")
const ZoneManager = preload("res://core/zone_manager.gd")
const RulesEngine = preload("res://core/rules_engine.gd")

var _effect_resolver
var _zone_manager
var _rules_engine

# 回调函数，由 GameManager 设置
var _enqueue_decision_callback: Callable
var _play_card_callback: Callable


func _init(p_effect_resolver: EffectResolver, p_zone_manager: ZoneManager, p_rules_engine: RulesEngine) -> void:
	_effect_resolver = p_effect_resolver
	_zone_manager = p_zone_manager
	_rules_engine = p_rules_engine


func set_callbacks(
	enqueue_decision: Callable,
	play_card: Callable
) -> void:
	_enqueue_decision_callback = enqueue_decision
	_play_card_callback = play_card


# ============================================================
# 状态检查
# ============================================================

func has_pending_life_triggers(state: GameState) -> bool:
	return not state.pending.life_triggers.is_empty()


func has_pending_life_reveal(state: GameState) -> bool:
	return not state.pending.life_reveal.is_empty()


func life_reveal_fully_resolved(state: GameState) -> bool:
	if state.pending.life_reveal.is_empty():
		return true
	for entry_variant in state.pending.life_reveal.get("revealed_cards", []):
		var entry: Dictionary = entry_variant
		if not bool(entry.get("resolved", false)):
			return false
	return true


func is_life_reveal_waiting_for_player(state: GameState) -> bool:
	return state.pending.life_reveal_waiting_for_player


func life_reveal_requires_view_confirmation(state: GameState, card_uid: String, is_human: Callable) -> bool:
	if state.pending.life_reveal.is_empty() or card_uid == "":
		return false
	var reveal_player_id := str(state.pending.life_reveal.get("player_id", ""))
	var reveal_controller_is_human: bool = is_human.call(reveal_player_id)
	for entry_variant in state.pending.life_reveal.get("revealed_cards", []):
		var entry: Dictionary = entry_variant
		if str(entry.get("card_uid", "")) != card_uid:
			continue
		if bool(entry.get("resolved", false)) or bool(entry.get("view_confirmed", false)):
			return false
		var has_trigger := bool(entry.get("has_life_trigger", false))
		if not has_trigger:
			return true
		return not reveal_controller_is_human
	return false


func refresh_life_reveal_waiting_for_player(state: GameState, is_human: Callable) -> void:
	if state.pending.life_reveal.is_empty():
		state.pending.life_reveal_waiting_for_player = false
		return
	var current_card_uid := str(state.pending.life_reveal.get("current_card_uid", ""))
	state.pending.life_reveal_waiting_for_player = life_reveal_requires_view_confirmation(state, current_card_uid, is_human)


# ============================================================
# 解析入口
# ============================================================

func resolve_life_trigger_decision(state: GameState, card_uid: String, activate: bool) -> Array[String]:
	return _effect_resolver.resolve_life_trigger_decision(state, card_uid, activate)


func acknowledge_life_reveal(state: GameState, card_uid: String, is_human: Callable) -> Array[String]:
	var logs: Array[String] = []
	if _life_reveal_requires_continue_then_ai(state, card_uid, is_human):
		_mark_life_reveal_view_confirmed(state, card_uid)
		state.pending.life_reveal_waiting_for_player = false
		return logs
	logs.append_array(_effect_resolver.acknowledge_life_reveal(state, card_uid))
	return logs


# ============================================================
# RAID 选择处理
# ============================================================

func resolve_life_trigger_raid_choice(state: GameState, decision: Dictionary, choice: String) -> Array[String]:
	var logs: Array[String] = []
	var card_uid := str(decision.get("source_card_uid", ""))
	var owner_player_id := str(decision.get("owner_player_id", ""))
	if card_uid == "" or owner_player_id == "":
		return ["Life trigger raid choice failed: missing card or owner."]
	if choice == "ADD_TO_HAND":
		return fallback_life_trigger_raid_to_hand(state, card_uid, owner_player_id)
	if choice != "RAID_NOW":
		return ["Life trigger raid choice failed: unsupported choice."]
	var raid_choices := build_life_trigger_raid_target_choices(state, card_uid, owner_player_id)
	var enabled_choices: Array[Dictionary] = []
	for choice_variant in raid_choices:
		var raid_choice: Dictionary = choice_variant
		if bool(raid_choice.get("enabled", true)):
			enabled_choices.append(raid_choice)
	if enabled_choices.is_empty():
		logs.append("%s cannot raid now because requirements are not met, so the card is added to hand instead." % owner_player_id)
		logs.append_array(fallback_life_trigger_raid_to_hand(state, card_uid, owner_player_id))
		return logs
	_enqueue_decision_callback.call({
		"type": "LIFE_TRIGGER_RAID_TARGET",
		"owner_player_id": owner_player_id,
		"source_card_uid": card_uid,
		"choices": raid_choices,
		"context": {
			"allow_raid_play": true,
		},
	})
	logs.append("Choose a raid target.")
	return logs


func resolve_life_trigger_raid_target(state: GameState, decision: Dictionary, raid_target_uid: String) -> Array[String]:
	var logs: Array[String] = []
	var card_uid := str(decision.get("source_card_uid", ""))
	var owner_player_id := str(decision.get("owner_player_id", ""))
	if card_uid == "" or raid_target_uid == "":
		return ["Life trigger raid target failed: missing card or target."]
	var raid_target = state.get_card(raid_target_uid)
	if raid_target == null:
		logs.append("%s cannot complete raid now because the selected target is no longer legal, so the card is added to hand instead." % owner_player_id)
		logs.append_array(fallback_life_trigger_raid_to_hand(state, card_uid, owner_player_id))
		return logs
	if raid_target.zone == UATypes.Zone.ENERGY_LINE:
		move_pending_life_card_to_hand(state, card_uid, owner_player_id)
		_enqueue_decision_callback.call({
			"type": "RAID_ZONE_CHOICE",
			"owner_player_id": owner_player_id,
			"source_card_uid": card_uid,
			"choices": [
				{"label": "Stay Energy", "value": UATypes.Zone.ENERGY_LINE},
				{"label": "Move Front", "value": UATypes.Zone.FRONT_LINE},
			],
			"context": {
				"target_zone": UATypes.Zone.ENERGY_LINE,
				"raid_target_uid": raid_target_uid,
				"allow_raid_play": true,
				"force_allow_current_zone": true,
				"ignore_pending_gate": true,
				"ignore_play_timing": true,
				"player_id": owner_player_id,
				"finalize_life_damage": true,
			}
		})
		logs.append("Choose raid destination.")
		return logs
	move_pending_life_card_to_hand(state, card_uid, owner_player_id)
	var play_result: Dictionary = _play_card_callback.call(card_uid, UATypes.Zone.FRONT_LINE, {
		"raid_target_uid": raid_target_uid,
		"raid_target_zone_choice": UATypes.Zone.FRONT_LINE,
		"allow_raid_play": true,
		"force_allow_current_zone": true,
		"ignore_pending_gate": true,
		"ignore_play_timing": true,
		"player_id": owner_player_id,
	})
	if not bool(play_result.get("ok", false)):
		_zone_manager.move_card(state, card_uid, UATypes.Zone.HAND, owner_player_id)
		logs.append("%s cannot complete raid now because requirements are not met, so the card is added to hand instead." % owner_player_id)
		if state.pending.life_triggers.is_empty() and state.pending.decisions.is_empty() and life_reveal_fully_resolved(state):
			logs.append_array(_effect_resolver.finalize_pending_life_damage(state))
		return logs
	if state.pending.life_triggers.is_empty() and state.pending.decisions.is_empty() and life_reveal_fully_resolved(state):
		logs.append_array(_effect_resolver.finalize_pending_life_damage(state))
	return logs


func build_life_trigger_raid_target_choices(state: GameState, card_uid: String, owner_player_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var card = state.get_card(card_uid)
	var card_def = state.get_card_def(card.def_id) if card != null else null
	if card == null or card_def == null:
		return result
	var required_name := str(card_def.special_play_rule.get("raid_target_name", ""))
	var player: PlayerState = state.get_player(owner_player_id)
	if player == null:
		return result
	for zone_cards in [player.front_line, player.energy_line]:
		for candidate_uid_variant in zone_cards:
			var candidate_uid := str(candidate_uid_variant)
			var candidate_card = state.get_card(candidate_uid)
			var candidate_def = state.get_card_def(candidate_card.def_id) if candidate_card != null else null
			if candidate_card == null or candidate_def == null:
				continue
			if candidate_def.card_type != UATypes.CardType.CHARACTER:
				continue
			if required_name != "" and not candidate_def.matches_reference_name(required_name):
				continue
			var validation: Dictionary = _rules_engine.can_play_card(state, owner_player_id, card_uid, UATypes.Zone.FRONT_LINE, {"allow_current_zone": true}, {
				"raid_target_uid": candidate_uid,
				"raid_target_zone_choice": UATypes.Zone.FRONT_LINE if candidate_card.zone == UATypes.Zone.FRONT_LINE else UATypes.Zone.ENERGY_LINE,
				"allow_raid_play": true,
				"ignore_play_timing": true,
			})
			result.append({
				"label": candidate_def.name,
				"value": candidate_uid,
				"enabled": bool(validation.get("ok", false)),
				"reason": "" if bool(validation.get("ok", false)) else str(validation.get("reason", "")),
			})
	return result


func move_pending_life_card_to_hand(state: GameState, card_uid: String, owner_player_id: String) -> void:
	_effect_resolver.move_pending_life_card_to_hand(state, card_uid, owner_player_id)


func fallback_life_trigger_raid_to_hand(state: GameState, card_uid: String, owner_player_id: String) -> Array[String]:
	var logs: Array[String] = []
	move_pending_life_card_to_hand(state, card_uid, owner_player_id)
	var card = state.get_card(card_uid)
	var card_def = state.get_card_def(card.def_id) if card != null else null
	logs.append("%s adds %s to hand." % [owner_player_id, card_def.name if card_def != null else card_uid])
	if state.pending.life_triggers.is_empty() and state.pending.decisions.is_empty() and life_reveal_fully_resolved(state):
		logs.append_array(_effect_resolver.finalize_pending_life_damage(state))
	return logs


# ============================================================
# 内部辅助函数
# ============================================================

func _mark_life_reveal_view_confirmed(state: GameState, card_uid: String) -> void:
	if state.pending.life_reveal.is_empty() or card_uid == "":
		return
	var entries: Array = state.pending.life_reveal.get("revealed_cards", [])
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		if str(entry.get("card_uid", "")) != card_uid:
			continue
		entry["view_confirmed"] = true
		entries[i] = entry
		state.pending.life_reveal["revealed_cards"] = entries
		return


func _life_reveal_requires_continue_then_ai(state: GameState, card_uid: String, is_human: Callable) -> bool:
	if not life_reveal_requires_view_confirmation(state, card_uid, is_human):
		return false
	for entry_variant in state.pending.life_reveal.get("revealed_cards", []):
		var entry: Dictionary = entry_variant
		if str(entry.get("card_uid", "")) != card_uid:
			continue
		return bool(entry.get("has_life_trigger", false))
	return false
