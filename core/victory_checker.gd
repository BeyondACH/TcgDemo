extends RefCounted
class_name VictoryChecker

const UATypes = preload("res://core/ua_types.gd")
const GameState = preload("res://data/game_state.gd")
const PlayerUtils = preload("res://core/player_utils.gd")

# 常规胜负检查：任意一方生命归零则对手获胜。
func check_victory(state: GameState) -> Dictionary:
	for player_id in [UATypes.PLAYER_ONE, UATypes.PLAYER_TWO]:
		var player := state.get_player(player_id)
		if player == null:
			continue
		if player.life.is_empty():
			return {
				"winner": PlayerUtils.opponent_of(player_id),
				"loser": player_id,
				"reason": "life_zero"
			}
	return {}

func check_deck_out_loss(state: GameState, player_id: String) -> Dictionary:
	var player := state.get_player(player_id)
	if player != null and player.deck.is_empty():
		return {
			"winner": PlayerUtils.opponent_of(player_id),
			"loser": player_id,
			"reason": "deck_out"
		}
	return {}
