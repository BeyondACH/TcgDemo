extends SceneTree

const UATypes = preload("res://core/ua_types.gd")
const GameManager = preload("res://core/game_manager.gd")
const CardInstance = preload("res://data/card_instance.gd")

const PURPLE_CARD := "UA31BT_MMM_1_046"
const RED_BT_CARD := "UA31BT_MMM_1_081"
const RED_ST_CARD := "UA31ST_MMM_1_081"
const PLAYER_ONE_DECK := "res://data/decks/红小圆.txt"
const PLAYER_TWO_DECK := "res://data/decks/红小圆.txt"

func _init() -> void:
	var purple_result := _verify_single_card(PURPLE_CARD, "PURPLE")
	if not purple_result.get("ok", false):
		push_error("[FAIL] %s" % purple_result.get("error", "Unknown purple verification failure."))
		quit(1)
		return

	var red_result := _verify_two_cards(RED_BT_CARD, RED_ST_CARD, "RED")
	if not red_result.get("ok", false):
		push_error("[FAIL] %s" % red_result.get("error", "Unknown red verification failure."))
		quit(1)
		return

	print("[PASS] Active-state energy bonus cards grant +1 only while ACTIVE.")
	quit()

func _new_manager() -> GameManager:
	var manager := GameManager.new()
	manager.setup_game({
		"player_decks": {
			UATypes.PLAYER_ONE: PLAYER_ONE_DECK,
			UATypes.PLAYER_TWO: PLAYER_TWO_DECK,
		}
	})
	manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})
	manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})
	manager.game_state.active_player_id = UATypes.PLAYER_ONE
	manager.game_state.phase = UATypes.Phase.MAIN
	return manager

func _verify_single_card(def_id: String, color: String) -> Dictionary:
	var manager := _new_manager()
	var card_uid := _spawn_card_copy(manager, def_id, UATypes.Zone.ENERGY_LINE, true)
	if card_uid == "":
		return _fail("Could not spawn %s into the energy line." % def_id)
	var card = manager.game_state.get_card(card_uid)
	card.state = UATypes.CardState.ACTIVE
	var active_value := _available_energy(manager, color)
	if active_value != 2:
		return _fail("%s should provide 2 %s energy while ACTIVE, got %d." % [def_id, color, active_value])
	card.state = UATypes.CardState.RESTED
	var rested_value := _available_energy(manager, color)
	if rested_value != 1:
		return _fail("%s should provide only base 1 %s energy while RESTED, got %d." % [def_id, color, rested_value])
	return {"ok": true}

func _verify_two_cards(first_def_id: String, second_def_id: String, color: String) -> Dictionary:
	var manager := _new_manager()
	var first_uid := _spawn_card_copy(manager, first_def_id, UATypes.Zone.ENERGY_LINE, true)
	var second_uid := _spawn_card_copy(manager, second_def_id, UATypes.Zone.ENERGY_LINE, false)
	if first_uid == "" or second_uid == "":
		return _fail("Could not spawn both red active-energy cards into the energy line.")
	var first_card = manager.game_state.get_card(first_uid)
	var second_card = manager.game_state.get_card(second_uid)
	first_card.state = UATypes.CardState.ACTIVE
	second_card.state = UATypes.CardState.RESTED
	var mixed_value := _available_energy(manager, color)
	if mixed_value != 3:
		return _fail("Expected 3 %s energy with one ACTIVE and one RESTED red sample, got %d." % [color, mixed_value])
	second_card.state = UATypes.CardState.ACTIVE
	var active_value := _available_energy(manager, color)
	if active_value != 4:
		return _fail("Expected 4 %s energy with both red samples ACTIVE, got %d." % [color, active_value])
	return {"ok": true}

func _spawn_card_copy(manager: GameManager, def_id: String, zone: int, active := true) -> String:
	var card_def = manager.game_state.get_card_def(def_id)
	if card_def == null:
		return ""
	var player = manager.game_state.get_player(UATypes.PLAYER_ONE)
	if player == null:
		return ""
	var card := CardInstance.new()
	card.uid = "%s_probe_%s_%d" % [UATypes.PLAYER_ONE, def_id, manager.game_state.cards.size()]
	card.def_id = def_id
	card.owner_player_id = UATypes.PLAYER_ONE
	card.controller_player_id = UATypes.PLAYER_ONE
	card.zone = zone
	card.state = UATypes.CardState.ACTIVE if active else UATypes.CardState.RESTED
	card.current_bp = int(card_def.bp)
	manager.game_state.cards[card.uid] = card
	var zone_cards: Array = manager.zone_manager.get_zone_array(player, zone)
	if zone_cards == null:
		return ""
	zone_cards.append(card.uid)
	return card.uid

func _available_energy(manager: GameManager, color: String) -> int:
	return int(manager.get_snapshot().get("players", {}).get(UATypes.PLAYER_ONE, {}).get("available_energy", {}).get(color, 0))

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
