extends RefCounted
class_name GameGateChecker

const GameState = preload("res://data/game_state.gd")
const UATypes = preload("res://core/ua_types.gd")

## Check if the game has a winner
static func has_winner(state: GameState) -> bool:
	return state.winner_player_id != ""

## Check if there are pending life triggers
static func has_pending_life_triggers(state: GameState) -> bool:
	return not state.pending_life_triggers.is_empty()

## Check if there is pending life reveal
static func has_pending_life_reveal(state: GameState) -> bool:
	return not state.pending_life_reveal.is_empty()

## Check if there are pending decisions
static func has_pending_decisions(state: GameState) -> bool:
	return not state.pending_decisions.is_empty()

## Check if there is any pending gate (life triggers, life reveal, or decisions)
static func has_pending_gate(state: GameState) -> bool:
	return has_pending_life_triggers(state) or has_pending_life_reveal(state) or has_pending_decisions(state)

## Get the current priority player ID based on pending game states
static func current_priority_player_id(state: GameState) -> String:
	if not state.pending_decisions.is_empty():
		return str((state.pending_decisions[0] as Dictionary).get("owner_player_id", state.active_player_id))
	if not state.pending_life_triggers.is_empty():
		return str((state.pending_life_triggers[0] as Dictionary).get("player_id", state.active_player_id))
	if not state.pending_life_reveal.is_empty():
		return str(state.pending_life_reveal.get("player_id", state.active_player_id))
	if not state.battle_context.is_empty():
		var battle_context: Dictionary = state.battle_context
		if str(battle_context.get("target_kind", "PLAYER")) == "PLAYER" and not bool(battle_context.get("is_sniper_attack", false)):
			return str(battle_context.get("defender_player_id", state.active_player_id))
	return state.active_player_id