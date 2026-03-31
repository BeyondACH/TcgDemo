extends RefCounted
class_name DecisionManager

const UATypes = preload("res://core/ua_types.gd")
const GameState = preload("res://data/game_state.gd")

## Enqueue a pending decision to the game state's decision queue.
func enqueue_decision(state: GameState, decision: Dictionary) -> void:
	state.pending_decisions.append(decision)


## Take (remove and return) a pending decision matching the given type and payload filters.
## Returns empty dictionary if no match found.
func take_decision(state: GameState, decision_type: String, payload: Dictionary) -> Dictionary:
	var source_card_uid := str(payload.get("source_card_uid", ""))
	var resolution_id := str(payload.get("resolution_id", ""))
	for i in range(state.pending_decisions.size()):
		var decision: Dictionary = state.pending_decisions[i]
		if str(decision.get("type", "")) != decision_type:
			continue
		if resolution_id != "" and str(decision.get("resolution_id", "")) != resolution_id:
			continue
		if source_card_uid != "" and str(decision.get("source_card_uid", "")) != source_card_uid:
			continue
		state.pending_decisions.remove_at(i)
		return decision
	return {}


## Check if there are any pending decisions in the queue.
func has_pending_decisions(state: GameState) -> bool:
	return not state.pending_decisions.is_empty()


## Get the owner player ID of the current pending decision, or empty string if none.
func current_decision_owner(state: GameState) -> String:
	if state.pending_decisions.is_empty():
		return ""
	return str(state.pending_decisions[0].get("owner_player_id", ""))


## Get a copy of the current pending decision, or empty dictionary if none.
func peek_current_decision(state: GameState) -> Dictionary:
	if state.pending_decisions.is_empty():
		return {}
	return (state.pending_decisions[0] as Dictionary).duplicate(true)