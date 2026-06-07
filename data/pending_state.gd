extends RefCounted
class_name PendingState

## 待处理状态 — 封装所有 pending 相关字段与查询方法
## Phase 3 Task 3.2: 从 GameState 提取

var decisions: Array[Dictionary] = []
var life_damage_cards: Array[Dictionary] = []
var life_triggers: Array[Dictionary] = []
var life_reveal := {}
var life_reveal_waiting_for_player := false

func is_empty() -> bool:
	return decisions.is_empty() and life_triggers.is_empty() and life_reveal.is_empty()

func has_any() -> bool:
	return not decisions.is_empty() or not life_triggers.is_empty() or not life_reveal.is_empty()

func clear() -> void:
	decisions.clear()
	life_damage_cards.clear()
	life_triggers.clear()
	life_reveal = {}
	life_reveal_waiting_for_player = false

func get_life_reveal_player_id() -> String:
	return str(life_reveal.get("player_id", ""))

func get_life_reveal_current_card_uid() -> String:
	return str(life_reveal.get("current_card_uid", ""))

func get_life_reveal_cards() -> Array:
	return life_reveal.get("revealed_cards", []) as Array

func set_life_reveal_current_card(uid: String) -> void:
	life_reveal["current_card_uid"] = uid

func enqueue_decision(decision: Dictionary) -> void:
	decisions.append(decision)

func take_decision(decision_type: String, payload: Dictionary) -> Dictionary:
	for i in range(decisions.size()):
		var decision: Dictionary = decisions[i]
		if str(decision.get("type", "")) != decision_type:
			continue
		var source_card_uid := str(payload.get("source_card_uid", ""))
		if source_card_uid != "" and str(decision.get("source_card_uid", "")) != source_card_uid:
			continue
		if str(payload.get("resolution_id", "")) != "" and str(decision.get("resolution_id", "")) != str(payload.get("resolution_id", "")):
			continue
		decisions.remove_at(i)
		return decision
	return {}

func has_decisions() -> bool:
	return not decisions.is_empty()

func peek_decision_owner() -> String:
	if decisions.is_empty():
		return ""
	return str(decisions[0].get("owner_player_id", ""))

func peek_decision() -> Dictionary:
	if decisions.is_empty():
		return {}
	return (decisions[0] as Dictionary).duplicate(true)
