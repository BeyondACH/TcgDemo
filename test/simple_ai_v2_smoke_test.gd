extends SceneTree

const UATypes = preload("res://core/ua_types.gd")
const ActionTypes = preload("res://core/actions/action_types.gd")
const GameManager = preload("res://core/game_manager.gd")
const SimpleAI = preload("res://core/ai/simple_ai.gd")
const PlayerState = preload("res://data/player_state.gd")
const CardInstance = preload("res://data/card_instance.gd")
const CardDef = preload("res://data/card_def.gd")

var _failures: Array[String] = []
var _passes: Array[String] = []
var _ai := SimpleAI.new()

func _init() -> void:
	_run_test("direct attack beats low-value sniper attack", _test_direct_attack_beats_low_value_sniper)
	_run_test("lethal attack is prioritized", _test_lethal_attack_is_prioritized)
	_run_test("ai attack rests attacker and logs name plus number", _test_attack_rests_attacker_and_logs_name_number)
	_run_test("block compares no block for low damage", _test_block_prefers_no_block_for_low_damage)
	_run_test("block when lethal is prevented", _test_blocks_when_attack_is_lethal)
	_run_test("life trigger prefers activation", _test_life_trigger_prefers_activation)
	_run_test("hand limit discard chooses low-value card", _test_hand_limit_discard_prefers_low_value_card)
	_run_test("step swap chooses low-value card", _test_step_swap_prefers_low_value_card)
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
	print("=== simple ai v2 smoke test ===")
	print("passed: %d" % _passes.size())
	print("failed: %d" % _failures.size())
	for failure in _failures:
		print(" - %s" % failure)

func _new_manager() -> GameManager:
	var manager := GameManager.new()
	manager.setup_game()
	_resolve_opening(manager)
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
	card.uid = "%s_ai_%s_%d" % [player_id, card_def.id, manager.game_state.cards.size()]
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

func _advance_to_phase(manager: GameManager, player_id: String, phase: int) -> void:
	var safety := 24
	while safety > 0:
		if manager.game_state.active_player_id == player_id and manager.game_state.phase == phase:
			return
		manager.advance_phase()
		safety -= 1

func _legal_actions(manager: GameManager, player_id: String) -> Array[Dictionary]:
	return manager.rules_engine.get_legal_actions(manager.game_state, player_id)

func _snapshot(manager: GameManager) -> Dictionary:
	return manager.get_snapshot()

func _test_direct_attack_beats_low_value_sniper() -> Dictionary:
	var manager := _new_manager()
	advance_to_attack(manager, UATypes.PLAYER_ONE)
	_player(manager, UATypes.PLAYER_TWO).life = ["L1", "L2", "L3", "L4", "L5", "L6", "L7"]
	_spawn_temp_card(manager, UATypes.PLAYER_TWO, _character_card("TMP_SNIPER_TARGET", "Sniper Target", 8000), UATypes.Zone.FRONT_LINE, false)
	_spawn_temp_card(manager, UATypes.PLAYER_ONE, _character_card("TMP_SNIPER_ATTACKER", "Sniper Attacker", 3500, ["SNIPER"]), UATypes.Zone.FRONT_LINE, true)
	var snapshot := _snapshot(manager)
	var chosen := _ai.choose_action(manager.game_state, snapshot, _legal_actions(manager, UATypes.PLAYER_ONE))
	if str(chosen.get("type", "")) != ActionTypes.ATTACK:
		return _fail("expected an attack action, got %s" % str(chosen.get("type", "")))
	if str(chosen.get("params", {}).get("target_kind", "")) != "PLAYER":
		return _fail("expected direct attack to beat low-value sniper attack")
	return _ok()

func _test_lethal_attack_is_prioritized() -> Dictionary:
	var manager := _new_manager()
	advance_to_attack(manager, UATypes.PLAYER_ONE)
	_player(manager, UATypes.PLAYER_TWO).life = ["L1", "L2"]
	_spawn_temp_card(manager, UATypes.PLAYER_TWO, _character_card("TMP_LETHAL_SNIPER_TARGET", "Guard", 8000), UATypes.Zone.FRONT_LINE, false)
	_spawn_temp_card(manager, UATypes.PLAYER_ONE, _character_card("TMP_LETHAL_ATTACKER", "Lethal", 3000, ["SNIPER"]), UATypes.Zone.FRONT_LINE, true)
	var snapshot := _snapshot(manager)
	var chosen := _ai.choose_action(manager.game_state, snapshot, _legal_actions(manager, UATypes.PLAYER_ONE))
	if str(chosen.get("type", "")) != ActionTypes.ATTACK or str(chosen.get("params", {}).get("target_kind", "")) != "PLAYER":
		return _fail("expected lethal direct attack to be prioritized")
	return _ok()

func _test_attack_rests_attacker_and_logs_name_number() -> Dictionary:
	var manager := _new_manager()
	manager.game_state.active_player_id = UATypes.PLAYER_TWO
	manager.game_state.priority_player_id = UATypes.PLAYER_TWO
	manager.game_state.phase = UATypes.Phase.ATTACK
	_player(manager, UATypes.PLAYER_ONE).life = ["L1", "L2", "L3"]
	var attacker_uid := _spawn_temp_card(manager, UATypes.PLAYER_TWO, _character_card("TMP_ATTACK_LOG", "Attack Logger", 3200), UATypes.Zone.FRONT_LINE, true)
	if attacker_uid == "":
		return _fail("expected attack logger test card to be created")
	var snapshot := _snapshot(manager)
	var chosen := _ai.choose_action(manager.game_state, snapshot, _legal_actions(manager, UATypes.PLAYER_TWO))
	if str(chosen.get("type", "")) != ActionTypes.ATTACK:
		return _fail("expected AI to choose an attack action, got %s" % str(chosen.get("type", "")))
	manager.execute_action(chosen)
	var response_actions := _legal_actions(manager, UATypes.PLAYER_ONE)
	var no_block := {}
	for action in response_actions:
		if str(action.get("type", "")) == ActionTypes.NO_BLOCK:
			no_block = action
			break
	if no_block.is_empty():
		return _fail("expected defending player to receive a NO_BLOCK action after attack declaration")
	manager.execute_action(no_block)
	var attacker := manager.game_state.get_card(attacker_uid)
	if attacker == null:
		return _fail("expected attacker to remain in game state after direct attack")
	if attacker.state != UATypes.CardState.RESTED:
		return _fail("expected AI attacker to become RESTED after attacking")
	var expected_log := "Attack Logger [TMP_ATTACK_LOG] attacks."
	if not manager.game_state.logs.has(expected_log):
		return _fail("expected attack log to include card name and number, logs: %s" % str(manager.game_state.logs))
	return _ok()

func _test_block_prefers_no_block_for_low_damage() -> Dictionary:
	var manager := _new_manager()
	manager.game_state.active_player_id = UATypes.PLAYER_TWO
	manager.game_state.phase = UATypes.Phase.ATTACK
	_player(manager, UATypes.PLAYER_ONE).life = ["L1", "L2", "L3"]
	var attacker_uid := _spawn_temp_card(manager, UATypes.PLAYER_TWO, _character_card("TMP_LOW_DAMAGE_ATTACKER", "Chip", 2500), UATypes.Zone.FRONT_LINE, true)
	_spawn_temp_card(manager, UATypes.PLAYER_ONE, _character_card("TMP_IMPORTANT_BLOCKER", "Important", 8000, ["RAID", "SNIPER"]), UATypes.Zone.FRONT_LINE, true)
	manager.request_attack(attacker_uid)
	var snapshot := _snapshot(manager)
	var pending: Dictionary = snapshot.get("battle_context", {})
	var chosen := _ai.choose_pending_decision(manager.game_state, snapshot, pending, _legal_actions(manager, UATypes.PLAYER_ONE))
	if str(chosen.get("type", "")) != ActionTypes.NO_BLOCK:
		return _fail("expected NO_BLOCK for low-value damage against important blocker")
	return _ok()

func _test_blocks_when_attack_is_lethal() -> Dictionary:
	var manager := _new_manager()
	manager.game_state.active_player_id = UATypes.PLAYER_TWO
	manager.game_state.phase = UATypes.Phase.ATTACK
	_player(manager, UATypes.PLAYER_ONE).life = ["L1"]
	var attacker_uid := _spawn_temp_card(manager, UATypes.PLAYER_TWO, _character_card("TMP_FATAL_ATTACKER", "Fatal", 2500, ["DAMAGE_2"]), UATypes.Zone.FRONT_LINE, true)
	_spawn_temp_card(manager, UATypes.PLAYER_ONE, _character_card("TMP_CHUMP_BLOCKER", "Chump", 1500), UATypes.Zone.FRONT_LINE, true)
	manager.request_attack(attacker_uid)
	var snapshot := _snapshot(manager)
	var pending: Dictionary = snapshot.get("battle_context", {})
	var chosen := _ai.choose_pending_decision(manager.game_state, snapshot, pending, _legal_actions(manager, UATypes.PLAYER_ONE))
	if str(chosen.get("type", "")) != ActionTypes.BLOCK:
		return _fail("expected BLOCK when attack would be lethal")
	return _ok()

func _test_life_trigger_prefers_activation() -> Dictionary:
	var manager := _new_manager()
	manager.game_state.active_player_id = UATypes.PLAYER_TWO
	manager.game_state.priority_player_id = UATypes.PLAYER_ONE
	var life_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_LIFE_TRIGGER",
		"name": "Life Trigger",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP_LIFE_TRIGGER",
		"traits": ["Tester"],
		"cost_energy": {},
		"cost_ap": 0,
		"energy_provided": {"GREEN": 1},
		"bp": 2500,
		"keywords": ["RAID"],
		"effects": [],
		"trigger_effects": [{"trigger": "ON_LIFE_TRIGGER", "operations": [{"type": "DRAW", "value": 1}]}],
	}, UATypes.Zone.LIFE, true)
	if life_uid == "":
		return _fail("expected life trigger test card to be created")
	manager.game_state.pending_life_triggers = [{
		"player_id": UATypes.PLAYER_ONE,
		"card_uid": life_uid,
		"card_name": "Life Trigger",
	}]
	var snapshot := _snapshot(manager)
	var pending_entries: Array = snapshot.get("pending_life_triggers", [])
	var pending: Dictionary = pending_entries[0]
	var chosen := _ai.choose_pending_decision(manager.game_state, snapshot, pending, _legal_actions(manager, UATypes.PLAYER_ONE))
	if str(chosen.get("type", "")) != ActionTypes.RESOLVE_LIFE_TRIGGER:
		return _fail("expected a RESOLVE_LIFE_TRIGGER action")
	if not bool(chosen.get("params", {}).get("activate", false)):
		return _fail("expected AI to activate the life trigger by default")
	return _ok()

func _test_hand_limit_discard_prefers_low_value_card() -> Dictionary:
	var manager := _new_manager()
	manager.game_state.active_player_id = UATypes.PLAYER_ONE
	manager.game_state.priority_player_id = UATypes.PLAYER_ONE
	var low_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, _character_card("TMP_DISCARD_LOW", "Low", 1000), UATypes.Zone.HAND, true)
	var high_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, _character_card("TMP_DISCARD_HIGH", "High", 4500, ["RAID"]), UATypes.Zone.HAND, true)
	var pending := {
		"type": "HAND_LIMIT_DISCARD",
		"owner_player_id": UATypes.PLAYER_ONE,
		"source_card_uid": "",
		"choices": [
			{"label": "Low", "value": low_uid},
			{"label": "High", "value": high_uid},
		],
		"context": {},
	}
	manager.game_state.pending_decisions = [pending]
	var snapshot := _snapshot(manager)
	var chosen := _ai.choose_pending_decision(manager.game_state, snapshot, pending, _legal_actions(manager, UATypes.PLAYER_ONE))
	if str(chosen.get("params", {}).get("choice", "")) != low_uid:
		return _fail("expected hand limit discard to choose the lower-value card")
	return _ok()

func _test_step_swap_prefers_low_value_card() -> Dictionary:
	var manager := _new_manager()
	manager.game_state.active_player_id = UATypes.PLAYER_ONE
	manager.game_state.priority_player_id = UATypes.PLAYER_ONE
	var low_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, _character_card("TMP_STEP_LOW", "Step Low", 1000), UATypes.Zone.ENERGY_LINE, true)
	var high_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, _character_card("TMP_STEP_HIGH", "Step High", 4500, ["STEP"]), UATypes.Zone.ENERGY_LINE, true)
	var pending := {
		"type": "STEP_SWAP_CHOICE",
		"owner_player_id": UATypes.PLAYER_ONE,
		"source_card_uid": "",
		"choices": [
			{"label": "Low", "value": low_uid},
			{"label": "High", "value": high_uid},
		],
		"context": {},
	}
	manager.game_state.pending_decisions = [pending]
	var snapshot := _snapshot(manager)
	var chosen := _ai.choose_pending_decision(manager.game_state, snapshot, pending, _legal_actions(manager, UATypes.PLAYER_ONE))
	if str(chosen.get("params", {}).get("choice", "")) != low_uid:
		return _fail("expected step swap to choose the lower-value card")
	return _ok()

func advance_to_attack(manager: GameManager, player_id: String) -> void:
	_advance_to_phase(manager, player_id, UATypes.Phase.ATTACK)

func _character_card(id: String, name: String, bp: int, keywords: Array = []) -> Dictionary:
	return {
		"id": id,
		"name": name,
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": id,
		"traits": ["Tester"],
		"cost_energy": {},
		"cost_ap": 0,
		"energy_provided": {"GREEN": 1},
		"bp": bp,
		"keywords": keywords,
		"effects": [],
		"trigger_effects": [],
	}
