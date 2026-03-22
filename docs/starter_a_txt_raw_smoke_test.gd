extends SceneTree

const UATypes = preload("res://core/ua_types.gd")
const GameManager = preload("res://core/game_manager.gd")
const PlayerState = preload("res://data/player_state.gd")
const CardInstance = preload("res://data/card_instance.gd")
const CardDef = preload("res://data/card_def.gd")

func _init() -> void:
	var manager := GameManager.new()
	manager.setup_game()
	var p1: PlayerState = manager.game_state.get_player(UATypes.PLAYER_ONE)
	var p2: PlayerState = manager.game_state.get_player(UATypes.PLAYER_TWO)
	_assert(p1 != null, "P1 should exist.")
	_assert(p2 != null, "P2 should exist.")
	_assert(_player_total_cards(p1) == 50, "starter_a.txt should expand to a 50-card main deck.")
	_assert(_player_total_cards(p2) == 50, "starter_b.txt should expand to a 50-card main deck.")
	_assert(p1.hand.size() == 7, "P1 should start with 7 hand cards.")
	_assert(p1.life.size() == 7, "P1 should start with 7 life cards.")
	_assert(p1.deck.size() == 36, "P1 deck should have 36 cards after setup.")
	_assert(p2.hand.size() == 7, "P2 should start with 7 hand cards.")
	_assert(p2.life.size() == 7, "P2 should start with 7 life cards.")
	_assert(p2.deck.size() == 36, "P2 deck should have 36 cards after setup.")

	_assert(_first_visible_card_def(manager, p1) != null, "P1 visible card should resolve to a raw card definition.")
	_assert(_first_visible_card_def(manager, p2) != null, "P2 visible card should resolve to a raw card definition.")

	print("STARTER_TXT_RAW_SMOKE_OK")
	quit(0)

func _player_total_cards(player: PlayerState) -> int:
	return player.hand.size() + player.life.size() + player.deck.size()

func _first_visible_card_def(manager: GameManager, player: PlayerState) -> CardDef:
	var visible_uid := str(player.hand[0])
	var visible_card: CardInstance = manager.game_state.get_card(visible_uid)
	_assert(visible_card != null, "Visible card should exist as a runtime instance.")
	var visible_def: CardDef = manager.game_state.get_card_def(visible_card.def_id)
	_assert(visible_def != null, "Visible card should resolve to a card definition.")
	_assert(visible_def.id.begins_with("UA31"), "Visible card should use cards_raw id.")
	_assert(visible_def.number != "", "Visible card should preserve raw card number.")
	_assert(visible_def.name != "", "Visible card should preserve raw card name.")
	return visible_def

func _assert(condition: bool, message: String) -> void:
	if condition:
		return

	push_error(message)
	quit(1)