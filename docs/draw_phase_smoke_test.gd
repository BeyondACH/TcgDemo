extends SceneTree

const UATypes = preload("res://core/ua_types.gd")
const GameManager = preload("res://core/game_manager.gd")
const PlayerState = preload("res://data/player_state.gd")

func _init() -> void:
	var manager := GameManager.new()
	manager.setup_game()
	var p1: PlayerState = manager.game_state.get_player(UATypes.PLAYER_ONE)
	var p2: PlayerState = manager.game_state.get_player(UATypes.PLAYER_TWO)

	_assert(manager.game_state.phase == UATypes.Phase.DRAW, "setup should enter DRAW")
	_assert(manager.game_state.active_player_id == UATypes.PLAYER_ONE, "setup should start with P1")
	_assert(p1.hand.size() == 7, "P1 should skip first auto draw")
	_assert(p1.ap_active_count() == 1, "P1 should start with 1 active AP")

	var p1_hand_before := p1.hand.size()
	var p1_deck_before := p1.deck.size()
	manager.request_bonus_draw()
	_assert(p1.hand.size() == p1_hand_before + 1, "P1 bonus draw should add 1 card")
	_assert(p1.deck.size() == p1_deck_before - 1, "P1 bonus draw should consume 1 deck card")
	_assert(p1.ap_active_count() == 0, "P1 bonus draw should spend 1 AP")
	manager.request_bonus_draw()
	_assert(p1.hand.size() == p1_hand_before + 1, "P1 bonus draw should only happen once")

	manager.advance_phase()
	_assert(manager.game_state.phase == UATypes.Phase.MOVE, "DRAW should advance to MOVE")
	manager.advance_phase()
	manager.advance_phase()
	manager.advance_phase()
	manager.advance_phase()

	_assert(manager.game_state.active_player_id == UATypes.PLAYER_TWO, "turn should pass to P2")
	_assert(manager.game_state.phase == UATypes.Phase.DRAW, "P2 turn should start in DRAW")
	_assert(p2.hand.size() == 8, "P2 should auto draw during own DRAW")
	_assert(p2.ap_active_count() == 2, "P2 should have 2 active AP on first turn")

	var p2_hand_before := p2.hand.size()
	manager.request_bonus_draw()
	_assert(p2.hand.size() == p2_hand_before + 1, "P2 bonus draw should add 1 card")

	print("DRAW_PHASE_SMOKE_OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
		
	push_error(message)
	quit(1)
