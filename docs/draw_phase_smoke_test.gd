extends SceneTree

const UATypes = preload("res://core/ua_types.gd")
const GameManager = preload("res://core/game_manager.gd")
const PlayerState = preload("res://data/player_state.gd")

func _init() -> void:
	var manager := GameManager.new()
	manager.setup_game()
	manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})
	manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})
	var p1: PlayerState = manager.game_state.get_player(UATypes.PLAYER_ONE)
	var p2: PlayerState = manager.game_state.get_player(UATypes.PLAYER_TWO)

	_assert(manager.game_state.phase == UATypes.Phase.DRAW, "setup should enter DRAW")
	_assert(manager.game_state.active_player_id == UATypes.PLAYER_ONE, "setup should start with P1")
	_assert(p1.hand.size() == 7, "P1 should skip first auto draw")
	_assert(p1.ap_active_count() == 1, "P1 should start with 1 active AP")

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

	manager.advance_phase()
	manager.advance_phase()
	manager.advance_phase()
	manager.advance_phase()
	manager.advance_phase()
	_assert(manager.game_state.active_player_id == UATypes.PLAYER_ONE, "turn should pass back to P1")
	_assert(manager.game_state.phase == UATypes.Phase.DRAW, "P1 second turn should start in DRAW")
	_assert(p1.ap_total() == 2, "P1 second turn should grow to 2 AP slots")
	_assert(p1.ap_active_count() == 2, "P1 second turn should refresh to 2 active AP")

	manager.advance_phase()
	manager.advance_phase()
	manager.advance_phase()
	manager.advance_phase()
	manager.advance_phase()

	_assert(manager.game_state.active_player_id == UATypes.PLAYER_TWO, "turn should pass to P2 again")
	_assert(manager.game_state.phase == UATypes.Phase.DRAW, "P2 second turn should start in DRAW")
	_assert(p2.ap_total() == 2, "P2 second turn should remain at 2 AP slots")
	_assert(p2.ap_active_count() == 2, "P2 second turn should refresh to 2 active AP")
		
	print("DRAW_PHASE_SMOKE_OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
		
	push_error(message)
	quit(1)
