extends SceneTree

const UATypes = preload("res://core/ua_types.gd")
const ActionTypes = preload("res://core/actions/action_types.gd")
const GameManager = preload("res://core/game_manager.gd")
const CardDef = preload("res://data/card_def.gd")
const CardInstance = preload("res://data/card_instance.gd")

var _failures: Array[String] = []
var _passes: Array[String] = []

func _init() -> void:
	_run_test("human vs ai can hand off one full ai turn", _test_human_vs_ai_turn)
	_run_test("ai vs ai can auto-progress from opening", _test_ai_vs_ai_progress)
	_run_test("sync drive emits ai action signal", _test_sync_drive_emits_ai_action_signal)
	_run_test("ai life reveal waits for player confirmation then resumes", _test_ai_life_reveal_waits_for_player_confirmation_then_resumes)
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
	print("=== vs ai smoke test ===")
	print("passed: %d" % _passes.size())
	print("failed: %d" % _failures.size())
	for failure in _failures:
		print(" - %s" % failure)

func _new_manager(config: Dictionary) -> GameManager:
	var manager := GameManager.new()
	manager.setup_game(config)
	return manager

func _resolve_human_action(manager: GameManager, player_id: String) -> void:
	var actions := manager.rules_engine.get_legal_actions(manager.game_state, player_id)
	if actions.is_empty():
		return
	var chosen := {}
	for action in actions:
		if str(action.get("type", "")) == ActionTypes.RESOLVE_LIFE_TRIGGER and not bool(action.get("params", {}).get("activate", true)):
			chosen = action
			break
	if chosen.is_empty():
		for action in actions:
			if str(action.get("type", "")) in [ActionTypes.NO_BLOCK, ActionTypes.ADVANCE_PHASE, ActionTypes.END_TURN]:
				chosen = action
				break
	if chosen.is_empty():
		chosen = actions[0]
	manager.execute_action(chosen)

func _advance_human_turn_to_ai(manager: GameManager) -> void:
	var safety := 16
	while safety > 0 and manager.game_state.active_player_id == UATypes.PLAYER_ONE and manager.game_state.winner_player_id == "":
		_resolve_human_action(manager, UATypes.PLAYER_ONE)
		safety -= 1

func _test_human_vs_ai_turn() -> Dictionary:
	var manager := _new_manager({
		UATypes.PLAYER_ONE: {"controller": "HUMAN"},
		UATypes.PLAYER_TWO: {"controller": "AI_SIMPLE"},
	})
	manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})
	manager.drive_controllers(32)
	if not manager.game_state.opening_complete:
		return _fail("opening should complete after human keep and ai mulligan handling")
	var start_turn := manager.game_state.turn_number
	_advance_human_turn_to_ai(manager)
	manager.drive_controllers(96)
	var safety := 32
	while safety > 0 and manager.game_state.winner_player_id == "" and manager.rules_engine.get_legal_actions(manager.game_state, UATypes.PLAYER_ONE).size() > 0 and manager._current_priority_player_id() == UATypes.PLAYER_ONE:
		_resolve_human_action(manager, UATypes.PLAYER_ONE)
		manager.drive_controllers(32)
		safety -= 1
	if manager.game_state.turn_number <= start_turn and manager.game_state.winner_player_id == "":
		return _fail("expected ai turn flow to advance the match state")
	return _ok()

func _test_ai_vs_ai_progress() -> Dictionary:
	var manager := _new_manager({
		UATypes.PLAYER_ONE: {"controller": "AI_SIMPLE"},
		UATypes.PLAYER_TWO: {"controller": "AI_SIMPLE"},
	})
	manager.drive_controllers(160)
	if not manager.game_state.opening_complete:
		return _fail("ai vs ai should resolve opening automatically")
	if manager.game_state.turn_number < 2 and manager.game_state.winner_player_id == "":
		return _fail("ai vs ai should advance beyond the opening turn")
	return _ok()

func _test_sync_drive_emits_ai_action_signal() -> Dictionary:
	var manager := _new_manager({
		UATypes.PLAYER_ONE: {"controller": "HUMAN"},
		UATypes.PLAYER_TWO: {"controller": "AI_SIMPLE"},
	})
	var action_events: Array[Dictionary] = []
	manager.ai_action_executed.connect(func(action_info: Dictionary) -> void:
		action_events.append(action_info.duplicate(true))
	)
	manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})
	manager.drive_controllers(32)
	if action_events.is_empty():
		return _fail("expected sync drive_controllers to emit at least one ai action event")
	var first_event: Dictionary = action_events[0]
	if str(first_event.get("player_id", "")) != UATypes.PLAYER_TWO:
		return _fail("expected the first ai action event to belong to player two")
	if str(first_event.get("action_type", "")) == "":
		return _fail("expected ai action event to include an action type")
	return _ok()


func _test_ai_life_reveal_waits_for_player_confirmation_then_resumes() -> Dictionary:
	var manager := _new_manager({
		UATypes.PLAYER_ONE: {"controller": "HUMAN"},
		UATypes.PLAYER_TWO: {"controller": "AI_SIMPLE"},
	})
	manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})
	manager.drive_controllers(32)
	var p2 := manager.game_state.get_player(UATypes.PLAYER_TWO)
	if p2 == null:
		return _fail("missing ai player state")
	p2.life.clear()
	var trigger_uid := _spawn_temp_trigger_life_card(manager, UATypes.PLAYER_TWO)
	if trigger_uid == "":
		return _fail("expected trigger life card to be created")
	p2.life = [trigger_uid]
	var hand_before := p2.hand.size()
	manager.effect_resolver.deal_damage_to_player(manager.game_state, UATypes.PLAYER_TWO, 1)
	manager.drive_controllers(16)
	if manager.game_state.pending_life_reveal.is_empty():
		return _fail("ai life reveal should pause until the player confirms it")
	manager.acknowledge_life_reveal(trigger_uid)
	manager.drive_controllers(32)
	if p2.hand.size() != hand_before + 1:
		return _fail("after confirmation the ai should resume and resolve its trigger")
	return _ok()

func _spawn_temp_trigger_life_card(manager: GameManager, player_id: String) -> String:
	var card_def := CardDef.new()
	card_def.from_dict({
		"id": "TMP_VS_AI_LIFE_TRIGGER",
		"name": "VS AI Life Trigger",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-VS-AI-LIFE",
		"traits": ["Tester"],
		"cost_energy": {},
		"cost_ap": 0,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": [
			{"trigger": "ON_LIFE_TRIGGER", "steps": [{"type": "DRAW", "value": 1}]}
		],
	})
	manager.game_state.card_defs[card_def.id] = card_def
	var player = manager.game_state.get_player(player_id)
	if player == null:
		return ""
	var card := CardInstance.new()
	card.uid = "%s_vs_ai_life_%d" % [player_id, manager.game_state.cards.size()]
	card.def_id = card_def.id
	card.owner_player_id = player_id
	card.controller_player_id = player_id
	card.zone = UATypes.Zone.LIFE
	card.state = UATypes.CardState.ACTIVE
	card.current_bp = card_def.bp
	manager.game_state.cards[card.uid] = card
	var zone_cards: Array = manager.zone_manager.get_zone_array(player, UATypes.Zone.LIFE)
	if zone_cards != null:
		zone_cards.append(card.uid)
	return card.uid
