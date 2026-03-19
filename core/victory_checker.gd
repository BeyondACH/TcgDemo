extends RefCounted
class_name VictoryChecker

func check_victory(state: GameState) -> Dictionary:
	for player_id in [UATypes.PLAYER_ONE, UATypes.PLAYER_TWO]:
		var player := state.get_player(player_id)
		if player == null:
			continue
		if player.life.is_empty():
			return {
				"winner": _opponent_of(player_id),
				"loser": player_id,
				"reason": "life_zero"
			}
	return {}

func check_deck_out_loss(state: GameState, player_id: String) -> Dictionary:
	var player := state.get_player(player_id)
	if player != null and player.deck.is_empty():
		return {
			"winner": _opponent_of(player_id),
			"loser": player_id,
			"reason": "deck_out"
		}
	return {}

func _opponent_of(player_id: String) -> String:
	if player_id == UATypes.PLAYER_ONE:
		return UATypes.PLAYER_TWO
	return UATypes.PLAYER_ONE
