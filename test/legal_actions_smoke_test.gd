extends SceneTree

const UATypes = preload("res://core/ua_types.gd")
const ActionTypes = preload("res://core/actions/action_types.gd")
const GameManager = preload("res://core/game_manager.gd")
const PlayerState = preload("res://data/player_state.gd")
const CardInstance = preload("res://data/card_instance.gd")
const CardDef = preload("res://data/card_def.gd")

var _failures: Array[String] = []
var _passes: Array[String] = []

func _init() -> void:
	_run_test("opening mulligan exposes legal decision action", _test_opening_legal_action)
	_run_test("main phase returns play actions for hand card", _test_main_phase_play_actions)
	_run_test("block window only exposes block responses", _test_block_response_actions)
	_run_test("attack request snapshot shifts priority to defender", _test_attack_request_updates_block_window_snapshot)
	_run_test("battle window closes after resolve and preserves last result", _test_battle_window_closes_after_resolution)
	_run_test("pending life trigger exposes activate and skip", _test_life_trigger_actions)
	_print_summary()
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

func _ok() -> Dictionary:
	return {"ok": true}

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}

func _print_summary() -> void:
	print("")
	print("=== legal actions smoke test ===")
	print("passed: %d" % _passes.size())
	print("failed: %d" % _failures.size())
	for failure in _failures:
		print(" - %s" % failure)

func _new_manager() -> GameManager:
	var manager := GameManager.new()
	manager.setup_game()
	return manager

func _resolve_opening(manager: GameManager) -> void:
	manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})
	manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})

func _player(manager: GameManager, player_id: String) -> PlayerState:
	return manager.game_state.get_player(player_id)

func _spawn_temp_card(manager: GameManager, player_id: String, card_data: Dictionary, zone: int, active := true) -> String:
	var card_def := CardDef.new()
	card_def.from_dict(card_data)
	manager.game_state.card_defs[card_def.id] = card_def
	var player := _player(manager, player_id)
	if player == null:
		return ""
	var card := CardInstance.new()
	card.uid = "%s_test_%s_%d" % [player_id, card_def.id, manager.game_state.cards.size()]
	card.def_id = card_def.id
	card.owner_player_id = player_id
	card.controller_player_id = player_id
	card.zone = zone
	card.state = UATypes.CardState.ACTIVE if active else UATypes.CardState.RESTED
	card.current_bp = card_def.bp
	manager.game_state.cards[card.uid] = card
	var zone_cards: Array = manager.zone_manager.get_zone_array(player, zone)
	if zone_cards != null:
		zone_cards.append(card.uid)
	return card.uid

func _advance_to_main(manager: GameManager, player_id: String) -> void:
	var safety := 16
	while safety > 0:
		if manager.game_state.active_player_id == player_id and manager.game_state.phase == UATypes.Phase.MAIN:
			return
		manager.advance_phase()
		safety -= 1

func _contains_action(actions: Array[Dictionary], action_type: String, matcher: Callable = Callable()) -> bool:
	for action in actions:
		if str(action.get("type", "")) != action_type:
			continue
		if matcher.is_null() or bool(matcher.call(action)):
			return true
	return false

func _test_opening_legal_action() -> Dictionary:
	var manager := _new_manager()
	var actions := manager.rules_engine.get_legal_actions(manager.game_state, UATypes.PLAYER_ONE)
	if not _contains_action(actions, ActionTypes.RESOLVE_PENDING_DECISION, func(action: Dictionary) -> bool:
		return str(action.get("params", {}).get("decision_type", "")) == "MULLIGAN_CHOICE"
	):
		return _fail("expected mulligan pending decision action for P1 opening")
	return _ok()

func _test_main_phase_play_actions() -> Dictionary:
	var manager := _new_manager()
	_resolve_opening(manager)
	_advance_to_main(manager, UATypes.PLAYER_ONE)
	var p1 := _player(manager, UATypes.PLAYER_ONE)
	p1.ap_area = [{"index": 0, "active": true}]
	var card_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_LEGAL_PLAY",
		"name": "Legal Play Tester",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-LP-1",
		"traits": ["Tester"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3500,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)
	var actions := manager.rules_engine.get_legal_actions(manager.game_state, UATypes.PLAYER_ONE)
	var has_front := _contains_action(actions, ActionTypes.PLAY_CARD, func(action: Dictionary) -> bool:
		return str(action.get("source_card_uid", "")) == card_uid and int(action.get("params", {}).get("target_zone", -1)) == UATypes.Zone.FRONT_LINE
	)
	var has_energy := _contains_action(actions, ActionTypes.PLAY_CARD, func(action: Dictionary) -> bool:
		return str(action.get("source_card_uid", "")) == card_uid and int(action.get("params", {}).get("target_zone", -1)) == UATypes.Zone.ENERGY_LINE
	)
	if not has_front or not has_energy:
		return _fail("expected both front-line and energy-line play actions for test hand card")
	if not manager.rules_engine.get_legal_actions(manager.game_state, UATypes.PLAYER_TWO).is_empty():
		return _fail("non-active player should not receive proactive legal actions")
	return _ok()

func _test_block_response_actions() -> Dictionary:
	var manager := _new_manager()
	_resolve_opening(manager)
	manager.game_state.active_player_id = UATypes.PLAYER_ONE
	manager.game_state.phase = UATypes.Phase.ATTACK
	var attacker_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_ATTACKER",
		"name": "Attacker",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-ATK-1",
		"traits": ["Tester"],
		"cost_energy": {},
		"cost_ap": 0,
		"energy_provided": {"GREEN": 1},
		"bp": 4000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	_spawn_temp_card(manager, UATypes.PLAYER_TWO, {
		"id": "TMP_BLOCKER",
		"name": "Blocker",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-BLK-1",
		"traits": ["Tester"],
		"cost_energy": {},
		"cost_ap": 0,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	manager.request_attack(attacker_uid)
	var actions := manager.rules_engine.get_legal_actions(manager.game_state, UATypes.PLAYER_TWO)
	if actions.is_empty():
		return _fail("expected block response actions for defending player")
	for action in actions:
		var action_type := str(action.get("type", ""))
		if action_type != ActionTypes.BLOCK and action_type != ActionTypes.NO_BLOCK:
			return _fail("expected only BLOCK/NO_BLOCK during block window, got %s" % action_type)
	return _ok()

func _test_attack_request_updates_block_window_snapshot() -> Dictionary:
	var manager := _new_manager()
	_resolve_opening(manager)
	manager.set_controller_config({
		UATypes.PLAYER_ONE: {"controller": "HUMAN"},
		UATypes.PLAYER_TWO: {"controller": "AI_SIMPLE"},
	})
	manager.game_state.active_player_id = UATypes.PLAYER_TWO
	manager.game_state.phase = UATypes.Phase.ATTACK
	var attacker_uid := _spawn_temp_card(manager, UATypes.PLAYER_TWO, {
		"id": "TMP_ATTACKER_SNAPSHOT",
		"name": "Snapshot Attacker",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-ATK-SNAP-1",
		"traits": ["Tester"],
		"cost_energy": {},
		"cost_ap": 0,
		"energy_provided": {"GREEN": 1},
		"bp": 4000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var blocker_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_BLOCKER_SNAPSHOT",
		"name": "Snapshot Blocker",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-BLK-SNAP-1",
		"traits": ["Tester"],
		"cost_energy": {},
		"cost_ap": 0,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var result := manager.request_attack(attacker_uid)
	if not bool(result.get("ok", false)):
		return _fail("expected attack declaration to succeed")
	var snapshot := manager.get_snapshot()
	if str(snapshot.get("priority_player_id", "")) != UATypes.PLAYER_ONE:
		return _fail("expected block window priority to shift to defender")
	if not bool(snapshot.get("human_input_enabled", false)):
		return _fail("expected human input to become enabled for the defending player")
	var legal_actions: Array = snapshot.get("legal_actions", [])
	var has_block_action := false
	for action_variant in legal_actions:
		var action: Dictionary = action_variant
		if str(action.get("type", "")) == ActionTypes.BLOCK and str(action.get("source_card_uid", "")) == blocker_uid:
			has_block_action = true
			break
	if not has_block_action:
		return _fail("expected block window legal actions to include the defending blocker")
	return _ok()

func _test_battle_window_closes_after_resolution() -> Dictionary:
	var manager := _new_manager()
	_resolve_opening(manager)
	manager.game_state.active_player_id = UATypes.PLAYER_ONE
	manager.game_state.phase = UATypes.Phase.ATTACK
	var attacker_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_ATTACKER_RESOLVE",
		"name": "Resolve Attacker",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-ATK-RES-1",
		"traits": ["Tester"],
		"cost_energy": {},
		"cost_ap": 0,
		"energy_provided": {"GREEN": 1},
		"bp": 4000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var blocker_uid := _spawn_temp_card(manager, UATypes.PLAYER_TWO, {
		"id": "TMP_BLOCKER_RESOLVE",
		"name": "Resolve Blocker",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-BLK-RES-1",
		"traits": ["Tester"],
		"cost_energy": {},
		"cost_ap": 0,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var attack_result := manager.request_attack(attacker_uid)
	if not bool(attack_result.get("ok", false)):
		return _fail("expected attack declaration to succeed before resolution")
	manager.resolve_attack(attacker_uid, blocker_uid)
	if not manager.game_state.battle_context.is_empty():
		return _fail("expected battle_context to clear after attack resolution")
	var snapshot := manager.get_snapshot()
	var last_battle_result: Dictionary = snapshot.get("last_battle_result", {})
	if str(last_battle_result.get("attacker_uid", "")) != attacker_uid:
		return _fail("expected last_battle_result to preserve attacker")
	if str(last_battle_result.get("blocker_uid", "")) != blocker_uid:
		return _fail("expected last_battle_result to preserve blocker")
	if str(last_battle_result.get("battle_outcome", "")) != "ATTACKER_WIN":
		return _fail("expected last_battle_result to preserve battle outcome")
	if not manager.rules_engine.get_legal_actions(manager.game_state, UATypes.PLAYER_TWO).is_empty():
		return _fail("expected defender to stop seeing block-only actions after resolution")
	var active_actions := manager.rules_engine.get_legal_actions(manager.game_state, UATypes.PLAYER_ONE)
	for action_variant in active_actions:
		var action: Dictionary = action_variant
		var action_type := str(action.get("type", ""))
		if action_type == ActionTypes.BLOCK or action_type == ActionTypes.NO_BLOCK:
			return _fail("expected resolved attack to remove block window actions")
	return _ok()

func _test_life_trigger_actions() -> Dictionary:
	var manager := _new_manager()
	_resolve_opening(manager)
	manager.game_state.pending.life_triggers.append({
		"player_id": UATypes.PLAYER_TWO,
		"card_uid": "LIFE_TEST_CARD",
		"card_name": "Life Test Card",
	})
	var actions := manager.rules_engine.get_legal_actions(manager.game_state, UATypes.PLAYER_TWO)
	var has_activate := _contains_action(actions, ActionTypes.RESOLVE_LIFE_TRIGGER, func(action: Dictionary) -> bool:
		return bool(action.get("params", {}).get("activate", false))
	)
	var has_skip := _contains_action(actions, ActionTypes.RESOLVE_LIFE_TRIGGER, func(action: Dictionary) -> bool:
		return not bool(action.get("params", {}).get("activate", true))
	)
	if not has_activate or not has_skip:
		return _fail("expected activate and skip actions for pending life trigger")
	return _ok()
