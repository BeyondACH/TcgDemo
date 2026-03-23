extends SceneTree

const UATypes = preload("res://core/ua_types.gd")
const GameManager = preload("res://core/game_manager.gd")
const PlayerState = preload("res://data/player_state.gd")
const CardInstance = preload("res://data/card_instance.gd")

const RAW_ENTER_DRAW := "UA31BT_MMM_1_074"
const RAW_TARGET_REMOVE := "UA31BT_MMM_1_077"
const RAW_LIFE_TRIGGER_TARGET := "UA31BT_MMM_1_084"
const RAW_MAIN_ACTIVATE := "UA31BT_MMM_1_089"
const RAW_EVENT_READY_AP := "UA31BT_MMM_1_095"

var _failures: Array[String] = []
var _passes: Array[String] = []

func _init() -> void:
	_run_test("Raw ON_ENTER Draw", _test_raw_on_enter_draw)
	_run_test("Raw MAIN_ACTIVATE Life To Hand", _test_raw_main_activate_life_to_hand)
	_run_test("Raw Event Ready AP", _test_raw_event_ready_ap)
	_run_test("Raw Life Trigger Target Selection", _test_raw_life_trigger_target_selection)
	_print_summary()
	if _failures.is_empty():
		print("CARDS_RAW_MINIMAL_DUEL_SMOKE_OK")
	quit(0 if _failures.is_empty() else 1)

func _run_test(name: String, callable: Callable) -> void:
	var error := ""
	var ok := false
	var result = callable.call()
	if result is Dictionary:
		ok = bool(result.get("ok", false))
		error = str(result.get("error", ""))
	else:
		ok = bool(result)
	if ok:
		_passes.append(name)
		print("[PASS] %s" % name)
	else:
		_failures.append("%s: %s" % [name, error])
		push_error("[FAIL] %s: %s" % [name, error])

func _print_summary() -> void:
	print("")
	print("=== cards_raw 最小对局样例结果 ===")
	print("通过: %d" % _passes.size())
	print("失败: %d" % _failures.size())
	if not _failures.is_empty():
		for failure in _failures:
			print(" - %s" % failure)

func _ok() -> Dictionary:
	return {"ok": true}

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}

func _new_manager() -> GameManager:
	var manager := GameManager.new()
	manager.setup_game()
	manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})
	manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})
	return manager

func _test_raw_on_enter_draw() -> Dictionary:
	var manager := _new_manager()
	var player_id := UATypes.PLAYER_ONE
	manager.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(_player(manager, player_id), 3)
	if not _place_red_energy(manager, player_id, 2):
		return _fail("Should be able to prepare 2 raw red energy cards for ON_ENTER.")
	var target_uid := _move_card_to_zone(manager, player_id, RAW_TARGET_REMOVE, UATypes.Zone.FRONT_LINE)
	var source_uid := _move_card_to_zone(manager, player_id, RAW_ENTER_DRAW, UATypes.Zone.HAND)
	if target_uid == "" or source_uid == "":
		return _fail("Raw ON_ENTER sample cards should be available.")
	var player := _player(manager, player_id)
	var hand_before := player.hand.size()
	var deck_before := player.deck.size()
	manager.play_card(source_uid, UATypes.Zone.FRONT_LINE)
	if player.hand.size() != hand_before:
		return _fail("Raw ON_ENTER draw should offset the played card.")
	if player.deck.size() != deck_before - 1:
		return _fail("Raw ON_ENTER draw should draw exactly 1 card.")
	return _ok()

func _test_raw_main_activate_life_to_hand() -> Dictionary:
	var manager := _new_manager()
	var player_id := UATypes.PLAYER_ONE
	manager.game_state.phase = UATypes.Phase.MAIN
	var source_uid := _move_or_spawn_card_to_zone(manager, player_id, RAW_MAIN_ACTIVATE, UATypes.Zone.FRONT_LINE)
	var chosen_life_uid := _ensure_life_card(manager, player_id)
	if source_uid == "" or chosen_life_uid == "":
		return _fail("Raw MAIN_ACTIVATE sample cards should be available.")
	var player := _player(manager, player_id)
	var hand_before := player.hand.size()
	var life_before := player.life.size()
	manager.request_main_activate(source_uid)
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("Raw MAIN_ACTIVATE should request explicit life target selection.")
	var decision: Dictionary = manager.game_state.pending_decisions[0]
	if str(decision.get("type", "")) != "ABILITY_TARGET_SELECTION":
		return _fail("Raw MAIN_ACTIVATE should use ability target selection.")
	manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(decision.get("resolution_id", "")),
		"choice": chosen_life_uid,
	})
	var source_card := manager.game_state.get_card(source_uid)
	if not player.hand.has(chosen_life_uid):
		return _fail("Raw MAIN_ACTIVATE should move the selected life card to hand.")
	if player.hand.size() != hand_before + 1:
		return _fail("Raw MAIN_ACTIVATE should increase hand by exactly 1.")
	if player.life.size() != life_before - 1:
		return _fail("Raw MAIN_ACTIVATE should reduce life by exactly 1.")
	if source_card == null or source_card.state != UATypes.CardState.ACTIVE:
		return _fail("Raw MAIN_ACTIVATE should ready the source card.")
	return _ok()

func _test_raw_event_ready_ap() -> Dictionary:
	var manager := _new_manager()
	var player_id := UATypes.PLAYER_ONE
	manager.game_state.phase = UATypes.Phase.MAIN
	var player := _player(manager, player_id)
	_fill_ap(player, 3)
	_set_ap_active(player, 1)
	if not _place_red_energy(manager, player_id, 3):
		return _fail("Should be able to prepare 3 raw red energy cards for the event.")
	var event_uid := _move_card_to_zone(manager, player_id, RAW_EVENT_READY_AP, UATypes.Zone.HAND)
	if event_uid == "":
		return _fail("Raw event sample card should be available.")
	manager.play_card(event_uid, UATypes.Zone.OUTSIDE)
	if player.ap_active_count() != 2:
		return _fail("Raw event should ready up to 2 AP after paying 1 AP.")
	if not player.outside.has(event_uid):
		return _fail("Raw event should move to outside after resolution.")
	return _ok()

func _test_raw_life_trigger_target_selection() -> Dictionary:
	var manager := _new_manager()
	var defender_id := UATypes.PLAYER_TWO
	var attacker_id := UATypes.PLAYER_ONE
	var life_uid := _move_card_to_life_top(manager, defender_id, RAW_TARGET_REMOVE)
	var target_uid := _move_card_to_zone(manager, attacker_id, RAW_LIFE_TRIGGER_TARGET, UATypes.Zone.FRONT_LINE)
	if life_uid == "" or target_uid == "":
		return _fail("Raw life trigger sample cards should be available.")
	var defender := _player(manager, defender_id)
	var attacker := _player(manager, attacker_id)
	var defender_outside_before := defender.outside.size()
	manager.effect_resolver.deal_damage_to_player(manager.game_state, defender_id, 1)
	manager.resolve_life_trigger_decision(life_uid, true)
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("Raw life trigger should request explicit target selection.")
	var decision: Dictionary = manager.game_state.pending_decisions[0]
	if str(decision.get("type", "")) != "ABILITY_TARGET_SELECTION":
		return _fail("Raw life trigger should use ability target selection.")
	manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(decision.get("resolution_id", "")),
		"choice": target_uid,
	})
	var target_card := manager.game_state.get_card(target_uid)
	if target_card == null or target_card.zone != UATypes.Zone.OUTSIDE:
		return _fail("Raw life trigger should move the selected enemy to outside.")
	if defender.outside.size() != defender_outside_before + 1:
		return _fail("Raw life trigger should append the removed target into the resolver player's outside zone.")
	if target_card.controller_player_id != defender_id:
		return _fail("Raw life trigger should keep the removed target under the resolver player's outside controller.")
	if defender.life.has(life_uid):
		return _fail("Raw life trigger should consume the damaged life card.")
	return _ok()

func _player(manager: GameManager, player_id: String) -> PlayerState:
	return manager.game_state.get_player(player_id)

func _fill_ap(player: PlayerState, total: int) -> void:
	player.ap_area.clear()
	for i in range(total):
		player.ap_area.append({"index": i, "active": true})

func _set_ap_active(player: PlayerState, active_count: int) -> void:
	for i in range(player.ap_area.size()):
		player.ap_area[i]["active"] = i < active_count

func _place_red_energy(manager: GameManager, player_id: String, count: int) -> bool:
	var moved := 0
	for card_uid in _all_player_cards(manager, player_id):
		if moved >= count:
			return true
		var card := manager.game_state.get_card(card_uid)
		var card_def := manager.game_state.get_card_def(card.def_id) if card != null else null
		if card == null or card_def == null:
			continue
		if int(card_def.energy_provided.get("RED", 0)) <= 0:
			continue
		if card.zone == UATypes.Zone.ENERGY_LINE:
			moved += 1
			continue
		manager.zone_manager.move_card(manager.game_state, card_uid, UATypes.Zone.ENERGY_LINE, player_id)
		card.state = UATypes.CardState.RESTED
		moved += 1
	return moved >= count

func _ensure_life_card(manager: GameManager, player_id: String) -> String:
	var player := _player(manager, player_id)
	if player == null:
		return ""
	if not player.life.is_empty():
		return str(player.life[0])
	for card_uid in _all_player_cards(manager, player_id):
		var card := manager.game_state.get_card(card_uid)
		if card == null or card.zone == UATypes.Zone.LIFE:
			continue
		manager.zone_manager.move_card(manager.game_state, card_uid, UATypes.Zone.LIFE, player_id)
		return card_uid
	return ""

func _move_card_to_zone(manager: GameManager, player_id: String, def_id: String, zone: int) -> String:
	for card_uid in _all_player_cards(manager, player_id):
		var card := manager.game_state.get_card(card_uid)
		if card == null or card.def_id != def_id:
			continue
		manager.zone_manager.move_card(manager.game_state, card_uid, zone, player_id)
		if zone != UATypes.Zone.LIFE and zone != UATypes.Zone.DECK and zone != UATypes.Zone.HAND:
			card.state = UATypes.CardState.ACTIVE
		return card_uid
	return ""

func _move_or_spawn_card_to_zone(manager: GameManager, player_id: String, def_id: String, zone: int) -> String:
	var existing_uid := _move_card_to_zone(manager, player_id, def_id, zone)
	if existing_uid != "":
		return existing_uid
	var card_def = manager.game_state.get_card_def(def_id)
	if card_def == null:
		return ""
	var card := CardInstance.new()
	card.uid = "%s_raw_spawn_%s_%d" % [player_id, def_id, manager.game_state.cards.size()]
	card.def_id = def_id
	card.owner_player_id = player_id
	card.controller_player_id = player_id
	card.zone = zone
	card.state = UATypes.CardState.ACTIVE if zone != UATypes.Zone.LIFE else UATypes.CardState.RESTED
	card.current_bp = int(card_def.bp)
	manager.game_state.cards[card.uid] = card
	var zone_cards: Array = manager.zone_manager.get_zone_array(_player(manager, player_id), zone)
	if zone_cards != null:
		zone_cards.append(card.uid)
	return card.uid

func _move_card_to_life_top(manager: GameManager, player_id: String, def_id: String) -> String:
	var card_uid := _move_or_spawn_card_to_zone(manager, player_id, def_id, UATypes.Zone.LIFE)
	if card_uid == "":
		return ""
	var player := _player(manager, player_id)
	if player == null:
		return ""
	player.life.erase(card_uid)
	player.life.push_front(card_uid)
	var card := manager.game_state.get_card(card_uid)
	if card != null:
		card.zone = UATypes.Zone.LIFE
	return card_uid

func _all_player_cards(manager: GameManager, player_id: String) -> Array[String]:
	var player := _player(manager, player_id)
	if player == null:
		return []
	var result: Array[String] = []
	for zone_name in ["hand", "life", "deck", "front_line", "energy_line", "outside", "removed"]:
		var zone_cards: Array = player.get(zone_name)
		if zone_cards == null:
			continue
		for card_uid in zone_cards:
			result.append(str(card_uid))
	return result
