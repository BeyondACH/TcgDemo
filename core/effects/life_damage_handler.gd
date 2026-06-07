extends RefCounted
class_name LifeDamageHandler

## 生命伤害处理器 - 负责处理生命伤害流程和触发决策
## 从 effect_resolver.gd 提取

const UATypes = preload("res://core/ua_types.gd")
const GameState = preload("res://data/game_state.gd")
const CardInstance = preload("res://data/card_instance.gd")
const EffectResolver = preload("res://core/effect_resolver.gd")
const VictoryChecker = preload("res://core/victory_checker.gd")

var _victory_checker: VictoryChecker
var _effect_resolver: EffectResolver  # 回调引用，用于 resolve_trigger 等

func _init(victory_checker: VictoryChecker, effect_resolver: EffectResolver) -> void:
	_victory_checker = victory_checker
	_effect_resolver = effect_resolver

# ============================================================
# 公共入口
# ============================================================

func deal_damage_to_player(state: GameState, player_id: String, amount: int) -> Array[String]:
	var logs: Array[String] = []
	if player_id == "":
		return logs
	var moved: Array[String] = _collect_life_damage_cards(state, player_id, amount)
	logs.append("%s takes %d damage." % [player_id, amount])
	if moved.is_empty():
		var defeat_now: Dictionary = _victory_checker.check_victory(state)
		if not defeat_now.is_empty():
			_apply_victory(state, defeat_now)
		return logs
	_begin_life_reveal_batch(state, player_id, moved)
	var queued_count := 0
	for life_uid in moved:
		if _card_has_trigger(state, life_uid, UATypes.TriggerType.ON_LIFE_TRIGGER):
			var entry := _build_life_trigger_entry(state, player_id, life_uid)
			state.pending.life_triggers.append(entry)
			queued_count += 1
	if queued_count > 0:
		logs.append("%s may resolve %d life trigger(s) in any order." % [player_id, queued_count])
	return logs

func resolve_life_trigger_decision(state: GameState, card_uid: String, activate: bool) -> Array[String]:
	var logs: Array[String] = []
	var pending_index := -1
	var pending_entry := {}
	for i in range(state.pending.life_triggers.size()):
		var candidate: Dictionary = state.pending.life_triggers[i]
		if str(candidate.get("card_uid", "")) == card_uid:
			pending_index = i
			pending_entry = candidate
			break
	if pending_index == -1:
		return ["Life trigger decision failed: missing pending card."]
	state.pending.life_triggers.remove_at(pending_index)
	_mark_life_reveal_resolved(state, card_uid)
	var owner_player_id := str(pending_entry.get("player_id", ""))
	var card_name := str(pending_entry.get("card_name", card_uid))
	if activate:
		logs.append("%s activates life trigger of %s." % [owner_player_id, card_name])
		if _effect_resolver != null:
			logs.append_array(_effect_resolver.resolve_trigger(card_uid, UATypes.TriggerType.ON_LIFE_TRIGGER, state, {"target_player_id": owner_player_id}))
	else:
		logs.append("%s skips life trigger of %s." % [owner_player_id, card_name])
	_advance_life_reveal_cursor(state)
	if state.pending.life_triggers.is_empty() and state.pending.decisions.is_empty() and _life_reveal_fully_resolved(state):
		logs.append_array(_finalize_pending_life_damage(state))
	return logs

func acknowledge_life_reveal(state: GameState, card_uid: String) -> Array[String]:
	var logs: Array[String] = []
	if state.pending.life_reveal.is_empty():
		return logs
	var current_card_uid := _current_life_reveal_card_uid(state)
	if current_card_uid == "" or current_card_uid != card_uid:
		return ["Life reveal acknowledgement failed: current card mismatch."]
	if _life_reveal_current_has_trigger(state):
		return ["Life reveal acknowledgement failed: current card still requires a trigger decision."]
	_mark_life_reveal_resolved(state, card_uid)
	_advance_life_reveal_cursor(state)
	if state.pending.life_triggers.is_empty() and state.pending.decisions.is_empty() and _life_reveal_fully_resolved(state):
		logs.append_array(_finalize_pending_life_damage(state))
	return logs

func finalize_pending_life_damage(state: GameState) -> Array[String]:
	return _finalize_pending_life_damage(state)

# ============================================================
# 内部辅助函数
# ============================================================

func _collect_life_damage_cards(state: GameState, player_id: String, amount: int) -> Array[String]:
	var moved: Array[String] = []
	var player = state.get_player(player_id)
	if player == null:
		return moved
	for i in range(amount):
		if player.life.is_empty():
			break
		var card_uid: String = player.life.pop_front()
		moved.append(card_uid)
		state.pending.life_damage_cards.append({
			"player_id": player_id,
			"card_uid": card_uid,
		})
	return moved

func _begin_life_reveal_batch(state: GameState, player_id: String, card_uids: Array[String]) -> void:
	var entries: Array[Dictionary] = []
	for i in range(card_uids.size()):
		var card_uid := str(card_uids[i])
		entries.append({
			"player_id": player_id,
			"card_uid": card_uid,
			"has_life_trigger": _card_has_trigger(state, card_uid, UATypes.TriggerType.ON_LIFE_TRIGGER),
			"view_confirmed": false,
			"resolved": false,
			"order_index": i,
		})
	state.pending.life_reveal = {
		"player_id": player_id,
		"revealed_cards": entries,
	}
	_advance_life_reveal_cursor(state)

func _finalize_pending_life_damage(state: GameState) -> Array[String]:
	var logs: Array[String] = []
	for entry_variant in state.pending.life_damage_cards:
		var entry: Dictionary = entry_variant
		var player_id := str(entry.get("player_id", ""))
		var card_uid := str(entry.get("card_uid", ""))
		var player = state.get_player(player_id)
		if player == null or card_uid == "":
			continue
		if not player.outside.has(card_uid):
			player.outside.append(card_uid)
		var card = state.get_card(card_uid)
		if card != null:
			card.zone = UATypes.Zone.OUTSIDE
	state.pending.life_damage_cards.clear()
	state.pending.life_reveal = {}
	state.pending.life_reveal_waiting_for_player = false
	var defeat: Dictionary = _victory_checker.check_victory(state)
	if not defeat.is_empty():
		_apply_victory(state, defeat)
	return logs

func _build_life_trigger_entry(state: GameState, player_id: String, card_uid: String) -> Dictionary:
	var card_name := card_uid
	var card = state.get_card(card_uid)
	if card != null:
		var card_def = state.get_card_def(card.def_id)
		if card_def != null:
			card_name = card_def.name
	return {
		"player_id": player_id,
		"card_uid": card_uid,
		"card_name": card_name,
	}

func _advance_life_reveal_cursor(state: GameState) -> void:
	if state.pending.life_reveal.is_empty():
		return
	var entries: Array = state.pending.life_reveal.get("revealed_cards", [])
	var current_card_uid := ""
	for entry_variant in entries:
		var entry: Dictionary = entry_variant
		if not bool(entry.get("resolved", false)):
			current_card_uid = str(entry.get("card_uid", ""))
			break
	state.pending.life_reveal["current_card_uid"] = current_card_uid

func _mark_life_reveal_resolved(state: GameState, card_uid: String) -> void:
	if state.pending.life_reveal.is_empty():
		return
	var entries: Array = state.pending.life_reveal.get("revealed_cards", [])
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		if str(entry.get("card_uid", "")) != card_uid:
			continue
		entry["resolved"] = true
		entries[i] = entry
		state.pending.life_reveal["revealed_cards"] = entries
		return

func _current_life_reveal_card_uid(state: GameState) -> String:
	if state.pending.life_reveal.is_empty():
		return ""
	return str(state.pending.life_reveal.get("current_card_uid", ""))

func _life_reveal_current_has_trigger(state: GameState) -> bool:
	var current_card_uid := _current_life_reveal_card_uid(state)
	if current_card_uid == "":
		return false
	for entry_variant in state.pending.life_reveal.get("revealed_cards", []):
		var entry: Dictionary = entry_variant
		if str(entry.get("card_uid", "")) == current_card_uid:
			return bool(entry.get("has_life_trigger", false))
	return false

func _life_reveal_fully_resolved(state: GameState) -> bool:
	if state.pending.life_reveal.is_empty():
		return true
	for entry_variant in state.pending.life_reveal.get("revealed_cards", []):
		var entry: Dictionary = entry_variant
		if not bool(entry.get("resolved", false)):
			return false
	return true

# ============================================================
# 触发匹配辅助函数
# ============================================================

func _card_has_trigger(state: GameState, card_uid: String, trigger_type: int) -> bool:
	var source_card = state.get_card(card_uid)
	if source_card == null:
		return false
	var card_def = state.get_card_def(source_card.def_id)
	if card_def == null:
		return false
	for effect_variant in card_def.trigger_effects:
		var effect: Dictionary = effect_variant
		if _trigger_matches(effect, trigger_type) and _is_effect_enabled_for_card(source_card, effect):
			return true
	return false

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
		UATypes.TriggerType.ON_BATTLE_WIN:
			return name == "ON_BATTLE_WIN"
		UATypes.TriggerType.ON_BATTLE_LOSE:
			return name == "ON_BATTLE_LOSE"
		UATypes.TriggerType.ON_BATTLE_END:
			return name == "ON_BATTLE_END"
	return false

func _is_effect_enabled_for_card(source_card, effect: Dictionary) -> bool:
	var effect_box := str(effect.get("effect_box", ""))
	if effect_box == "RAID_INNER":
		return bool(source_card.flags.get("entered_via_raid", false))
	return true

func _apply_victory(state: GameState, result: Dictionary) -> void:
	state.winner_player_id = str(result.get("winner", ""))
	state.loser_player_id = str(result.get("loser", ""))