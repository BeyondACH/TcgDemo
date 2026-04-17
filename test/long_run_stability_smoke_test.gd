extends SceneTree

const UATypes = preload("res://core/ua_types.gd")
const GameManager = preload("res://core/game_manager.gd")
const PlayerState = preload("res://data/player_state.gd")
const CardInstance = preload("res://data/card_instance.gd")
const CardDef = preload("res://data/card_def.gd")

const RAW_ON_LEAVE_TO_HAND := "UA31BT_MMM_1_069"

var _failures: Array[String] = []
var _passes: Array[String] = []

func _init() -> void:
	_run_test("continuous turn lifecycle remains stable across two full turns", _test_continuous_turn_lifecycle)
	_run_test("stacked delayed effects expire in order without residue", _test_delayed_effect_chain_expires_without_residue)
	_run_test("leave chains stay stable across battle leave and stack leave", _test_leave_chain_stability)
	_run_test("life trigger binary choice fully settles all branches", _test_life_trigger_binary_choice_fully_settles)
	_run_test("ai vs ai can keep advancing without long-run deadlock", _test_ai_long_run_stability)
	_run_test("cross turn delayed leave and ai pacing chain leaves no residue", _test_cross_turn_delayed_leave_and_ai_pacing_chain)
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

func _print_summary() -> void:
	print("")
	print("=== long run stability smoke test ===")
	print("passed: %d" % _passes.size())
	print("failed: %d" % _failures.size())
	for failure in _failures:
		print(" - %s" % failure)

func _ok() -> Dictionary:
	return {"ok": true}

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}

func _assert_runtime_clean(manager: GameManager, label: String) -> Dictionary:
	if not manager.game_state.effect_queue.is_empty():
		return _fail("%s left effect_queue residue" % label)
	if not manager.game_state.pending_decisions.is_empty():
		return _fail("%s left pending_decisions residue" % label)
	if not manager.game_state.pending_life_triggers.is_empty():
		return _fail("%s left pending_life_triggers residue" % label)
	if not manager.game_state.delayed_effects.is_empty():
		return _fail("%s left delayed_effects residue" % label)
	if not manager.game_state.battle_context.is_empty():
		return _fail("%s left battle_context residue" % label)
	return _ok()

func _new_manager(controller_config: Dictionary = {}) -> GameManager:
	var manager := GameManager.new()
	manager.setup_game(controller_config)
	_resolve_opening(manager)
	return manager

func _resolve_opening(manager: GameManager, p1_choice := "keep", p2_choice := "keep") -> void:
	manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": p1_choice})
	manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": p2_choice})

func _player(manager: GameManager, player_id: String) -> PlayerState:
	return manager.game_state.get_player(player_id)

func _register_temp_card_def(manager: GameManager, card_data: Dictionary) -> String:
	var card_def: CardDef = CardDef.new()
	card_def.from_dict(card_data)
	manager.game_state.card_defs[card_def.id] = card_def
	return card_def.id

func _spawn_temp_card(manager: GameManager, player_id: String, card_data: Dictionary, zone: int, active := true) -> String:
	var def_id := _register_temp_card_def(manager, card_data)
	var card := CardInstance.new()
	card.uid = "%s_temp_%s_%d" % [player_id, def_id, manager.game_state.cards.size()]
	card.def_id = def_id
	card.owner_player_id = player_id
	card.controller_player_id = player_id
	card.zone = zone
	card.state = UATypes.CardState.ACTIVE if active and zone != UATypes.Zone.LIFE else UATypes.CardState.RESTED
	card.current_bp = int(card_data.get("bp", 0))
	manager.game_state.cards[card.uid] = card
	var zone_cards: Array = manager.zone_manager.get_zone_array(_player(manager, player_id), zone)
	if zone_cards != null:
		zone_cards.append(card.uid)
	return card.uid

func _spawn_raw_card_copy(manager: GameManager, player_id: String, def_id: String, zone: int, active := true) -> String:
	var card_def = manager.game_state.get_card_def(def_id)
	if card_def == null:
		return ""
	var card := CardInstance.new()
	card.uid = "%s_raw_copy_%s_%d" % [player_id, def_id, manager.game_state.cards.size()]
	card.def_id = def_id
	card.owner_player_id = player_id
	card.controller_player_id = player_id
	card.zone = zone
	card.state = UATypes.CardState.ACTIVE if active and zone != UATypes.Zone.LIFE else UATypes.CardState.RESTED
	card.current_bp = int(card_def.bp)
	manager.game_state.cards[card.uid] = card
	var zone_cards: Array = manager.zone_manager.get_zone_array(_player(manager, player_id), zone)
	if zone_cards != null:
		zone_cards.append(card.uid)
	return card.uid

func _move_or_spawn_card_to_zone(manager: GameManager, player_id: String, def_id: String, zone: int) -> String:
	var player := _player(manager, player_id)
	if player == null:
		return ""
	for card_uid in _all_player_cards(manager, player_id):
		var card := manager.game_state.get_card(card_uid)
		if card == null or card.def_id != def_id:
			continue
		manager.zone_manager.move_card(manager.game_state, card_uid, zone, player_id)
		if zone != UATypes.Zone.LIFE and zone != UATypes.Zone.DECK and zone != UATypes.Zone.HAND:
			card.state = UATypes.CardState.ACTIVE
		return card_uid
	return _spawn_raw_card_copy(manager, player_id, def_id, zone, zone != UATypes.Zone.LIFE)

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
	for zone in [player.deck, player.hand, player.life, player.front_line, player.energy_line, player.outside, player.removed]:
		for card_uid_variant in zone:
			var card_uid := str(card_uid_variant)
			if not result.has(card_uid):
				result.append(card_uid)
	return result

func _fill_ap(player: PlayerState, total: int) -> void:
	player.ap_area.clear()
	for i in range(total):
		player.ap_area.append({"index": i, "active": true})

func _set_ap_active(player: PlayerState, active_count: int) -> void:
	for i in range(player.ap_area.size()):
		player.ap_area[i]["active"] = i < active_count

func _spawn_generic_energy(manager: GameManager, player_id: String, color: String, temp_id: String) -> String:
	var color_key := color.to_upper()
	var cost_energy: Dictionary = {}
	cost_energy[color_key] = 1
	var energy_provided: Dictionary = {}
	energy_provided[color_key] = 1
	return _spawn_temp_card(manager, player_id, {
		"id": temp_id,
		"name": "Energy %s %s" % [color_key, temp_id],
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-ENERGY-%s" % temp_id,
		"traits": ["Tester"],
		"cost_energy": cost_energy,
		"cost_ap": 1,
		"energy_provided": energy_provided,
		"bp": 1000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.ENERGY_LINE, false)

func _count_color_energy(manager: GameManager, player_id: String, color: String) -> int:
	var player := _player(manager, player_id)
	if player == null:
		return 0
	var total := 0
	for card_uid_variant in player.energy_line:
		var card_uid := str(card_uid_variant)
		var card := manager.game_state.get_card(card_uid)
		var card_def := manager.game_state.get_card_def(card.def_id) if card != null else null
		if card_def == null:
			continue
		total += int(card_def.energy_provided.get(color.to_upper(), 0))
	return total

func _ensure_color_energy(manager: GameManager, player_id: String, color: String, count: int) -> bool:
	while _count_color_energy(manager, player_id, color) < count:
		var uid := _spawn_generic_energy(manager, player_id, color, "%s_%d" % [color.to_upper(), manager.game_state.cards.size()])
		if uid == "":
			break
	return _count_color_energy(manager, player_id, color) >= count

func _trim_life_to_count(manager: GameManager, player_id: String, target_count: int) -> void:
	var player := _player(manager, player_id)
	if player == null:
		return
	while player.life.size() > target_count:
		var moved_uid := str(player.life.pop_back())
		player.outside.append(moved_uid)
		var moved_card := manager.game_state.get_card(moved_uid)
		if moved_card != null:
			moved_card.zone = UATypes.Zone.OUTSIDE

func _advance_to_turn_draw(manager: GameManager, player_id: String, min_turn_number := 1, safety := 64) -> bool:
	while safety > 0:
		if manager.game_state.active_player_id == player_id and manager.game_state.phase == UATypes.Phase.DRAW and manager.game_state.turn_number >= min_turn_number:
			return true
		manager.advance_phase()
		safety -= 1
	return manager.game_state.active_player_id == player_id and manager.game_state.phase == UATypes.Phase.DRAW and manager.game_state.turn_number >= min_turn_number

func _drain_pending_life_windows(manager: GameManager, activate_life_triggers := false) -> void:
	var safety := 24
	while safety > 0:
		if not manager.game_state.pending_life_triggers.is_empty():
			var trigger_entry: Dictionary = manager.game_state.pending_life_triggers[0]
			manager.resolve_life_trigger_decision(str(trigger_entry.get("card_uid", "")), activate_life_triggers)
			safety -= 1
			continue
		if not manager.game_state.pending_life_reveal.is_empty():
			var current_uid := str(manager.game_state.pending_life_reveal.get("current_card_uid", ""))
			if current_uid == "":
				break
			manager.acknowledge_life_reveal(current_uid)
			safety -= 1
			continue
		break

func _finalize_pending_life_damage_if_possible(manager: GameManager) -> void:
	if manager.game_state.pending_life_triggers.is_empty() and manager.game_state.pending_decisions.is_empty() and manager.game_state.pending_life_reveal.is_empty() and not manager.game_state.pending_life_damage_cards.is_empty():
		manager.effect_resolver.finalize_pending_life_damage(manager.game_state)

func _runtime_state_error(manager: GameManager) -> String:
	if not manager.game_state.pending_decisions.is_empty():
		return "pending_decisions not empty"
	if not manager.game_state.pending_life_triggers.is_empty():
		return "pending_life_triggers not empty"
	if not manager.game_state.pending_life_reveal.is_empty():
		return "pending_life_reveal not empty"
	if not manager.game_state.pending_life_damage_cards.is_empty():
		return "pending_life_damage_cards not empty"
	if not manager.game_state.effect_queue.is_empty():
		return "effect_queue not empty"
	if not manager.game_state.battle_context.is_empty():
		return "battle_context not empty"
	if not manager.game_state.delayed_effects.is_empty():
		return "delayed_effects not empty"
	return ""

func _test_continuous_turn_lifecycle() -> Dictionary:
	var manager := _new_manager()
	var player_id := UATypes.PLAYER_ONE
	var player := _player(manager, player_id)
	manager.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(player, 1)
	_set_ap_active(player, 0)
	var source_uid := _spawn_temp_card(manager, player_id, {
		"id": "TMP_LONG_RUN_MAIN_ONCE",
		"name": "Long Run Main Once",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-LONG-1",
		"traits": ["Tester"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": [
			{
				"trigger": "MAIN_ACTIVATE",
				"once_per_turn": true,
				"steps": [{"type": "DRAW", "value": 1}]
			}
		]
	}, UATypes.Zone.FRONT_LINE, false)
	if source_uid == "":
		return _fail("expected a temporary once-per-turn source card")
	manager.request_main_activate(source_uid)
	var source_card = manager.game_state.get_card(source_uid)
	if source_card == null or not bool(source_card.flags.get("activated_main_this_turn", false)):
		return _fail("expected activated_main_this_turn to be marked during the current turn")
	var trace: Array[String] = []
	var reached_p2_draw := false
	var safety := 20
	while safety > 0 and not (manager.game_state.active_player_id == UATypes.PLAYER_ONE and manager.game_state.phase == UATypes.Phase.DRAW and manager.game_state.turn_number >= 2):
		trace.append("%s:%s:%d" % [manager.game_state.active_player_id, UATypes.Phase.keys()[manager.game_state.phase], manager.game_state.turn_number])
		manager.advance_phase()
		if not reached_p2_draw and manager.game_state.active_player_id == UATypes.PLAYER_TWO and manager.game_state.phase == UATypes.Phase.DRAW:
			reached_p2_draw = true
			if player.ap_area.is_empty() or bool(player.ap_area[0].get("active", true)):
				return _fail("expected AP to remain rested when the turn passes to the opponent")
			if source_card.state != UATypes.CardState.ACTIVE:
				return _fail("expected rested field cards to ready during the end phase")
		safety -= 1
	if manager.game_state.active_player_id != UATypes.PLAYER_ONE or manager.game_state.phase != UATypes.Phase.DRAW or manager.game_state.turn_number < 2:
		return _fail("expected to reach player one draw on the next full turn cycle")
	if not reached_p2_draw:
		return _fail("expected the lifecycle walk to pass through the opponent draw")
	if bool(source_card.flags.get("activated_main_this_turn", false)):
		return _fail("expected activated_main_this_turn to clear by the next self draw")
	for expected in ["P1:ATTACK:1", "P1:END:1"]:
		if not trace.has(expected):
			return _fail("expected lifecycle trace to include %s" % expected)
	return _ok()

func _test_delayed_effect_chain_expires_without_residue() -> Dictionary:
	var manager := _new_manager()
	manager.game_state.phase = UATypes.Phase.MAIN
	var end_main_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_LONG_DELAY_END_MAIN",
		"name": "Delay End Main",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-LONG-2",
		"traits": ["Tester"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var end_turn_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_LONG_DELAY_END_TURN",
		"name": "Delay End Turn",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-LONG-3",
		"traits": ["Tester"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var next_turn_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_LONG_DELAY_NEXT_TURN",
		"name": "Delay Next Turn",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-LONG-4",
		"traits": ["Tester"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	if end_main_uid == "" or end_turn_uid == "" or next_turn_uid == "":
		return _fail("expected all delayed-effect source cards to be created")
	manager.game_state.delayed_effects.append({
		"id": "long_delay_end_main",
		"source_card_uid": end_main_uid,
		"owner_player_id": UATypes.PLAYER_ONE,
		"event": "ON_END_MAIN_PHASE",
		"once": true,
		"steps": [{"type": "MOVE_CARD", "target": "SOURCE_CARD", "to_zone": "OUTSIDE"}]
	})
	manager.game_state.delayed_effects.append({
		"id": "long_delay_end_turn",
		"source_card_uid": end_turn_uid,
		"owner_player_id": UATypes.PLAYER_ONE,
		"event": "ON_NOOP",
		"filters": [],
		"steps": [{"type": "MOVE_CARD", "target": "SOURCE_CARD", "to_zone": "OUTSIDE"}],
		"once": true,
		"expires": "END_OF_TURN",
	})
	manager.game_state.delayed_effects.append({
		"id": "long_delay_next_turn",
		"source_card_uid": next_turn_uid,
		"owner_player_id": UATypes.PLAYER_ONE,
		"event": "ON_NOOP",
		"filters": [],
		"steps": [{"type": "MOVE_CARD", "target": "SOURCE_CARD", "to_zone": "OUTSIDE"}],
		"once": true,
		"expires": "UNTIL_NEXT_SELF_TURN_START",
	})
	manager.advance_phase()
	if manager.game_state.delayed_effects.size() != 2:
		return _fail("expected the ON_END_MAIN_PHASE delayed effect to expire before attack")
	var end_main_card = manager.game_state.get_card(end_main_uid)
	if end_main_card == null or end_main_card.zone != UATypes.Zone.OUTSIDE:
		return _fail("expected the ON_END_MAIN_PHASE source card to move to outside")
	manager.advance_phase()
	manager.advance_phase()
	if manager.game_state.active_player_id != UATypes.PLAYER_TWO or manager.game_state.phase != UATypes.Phase.DRAW:
		return _fail("expected to advance into the opponent draw after ending the turn")
	if manager.game_state.delayed_effects.size() != 1:
		return _fail("expected END_OF_TURN to expire before the opponent draw")
	if not _advance_to_turn_draw(manager, UATypes.PLAYER_ONE, 2):
		return _fail("expected to reach the source controller next draw for UNTIL_NEXT_SELF_TURN_START")
	var cleanup_error := _runtime_state_error(manager)
	if cleanup_error != "":
		return _fail("expected the delayed chain to end cleanly, but %s" % cleanup_error)
	return _ok()

func _test_leave_chain_stability() -> Dictionary:
	var battle_manager := _new_manager()
	battle_manager.game_state.phase = UATypes.Phase.ATTACK
	var attacker_uid := _spawn_temp_card(battle_manager, UATypes.PLAYER_ONE, {
		"id": "TMP_LONG_LEAVE_ATTACKER",
		"name": "Leave Chain Attacker",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-LONG-5",
		"traits": ["Tester"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 5000,
		"keywords": ["SNIPER"],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var defender_uid := _spawn_raw_card_copy(battle_manager, UATypes.PLAYER_TWO, RAW_ON_LEAVE_TO_HAND, UATypes.Zone.FRONT_LINE, true)
	if attacker_uid == "" or defender_uid == "":
		return _fail("expected both the attacker and official on-leave defender")
	var defender_player := _player(battle_manager, UATypes.PLAYER_TWO)
	var hand_before := defender_player.hand.size()
	var declare_result := battle_manager.request_attack(attacker_uid, {
		"target_kind": "FRONT_CHARACTER",
		"target_uid": defender_uid,
	})
	if not bool(declare_result.get("ok", false)):
		return _fail("expected the targeted attack to be legal")
	battle_manager.resolve_attack(attacker_uid)
	var defender_card = battle_manager.game_state.get_card(defender_uid)
	if defender_card == null or defender_card.zone != UATypes.Zone.HAND:
		return _fail("expected the official on-leave card to return to hand after battle leave resolution")
	if defender_player.hand.size() != hand_before + 1:
		return _fail("expected the on-leave battle chain to add exactly one card to hand")
	if _runtime_state_error(battle_manager) != "":
		return _fail("expected the battle leave chain to finish without runtime residue")
	battle_manager.advance_phase()
	battle_manager.advance_phase()
	if battle_manager.game_state.active_player_id != UATypes.PLAYER_TWO or battle_manager.game_state.phase != UATypes.Phase.DRAW:
		return _fail("expected the battle leave chain to still advance cleanly into the next draw")

	var stack_manager := _new_manager()
	stack_manager.game_state.phase = UATypes.Phase.MAIN
	var base_uid := _spawn_temp_card(stack_manager, UATypes.PLAYER_ONE, {
		"id": "TMP_LONG_STACK_BASE",
		"name": "Stack Base",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-LONG-6",
		"traits": ["Tester"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var top_uid := _spawn_temp_card(stack_manager, UATypes.PLAYER_ONE, {
		"id": "TMP_LONG_STACK_TOP",
		"name": "Stack Top",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-LONG-7",
		"traits": ["Tester"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2500,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)
	if base_uid == "" or top_uid == "":
		return _fail("expected both stack cards to be created")
	var stack_result := stack_manager.zone_manager.stack_card_on_target(stack_manager.game_state, top_uid, base_uid, UATypes.Zone.FRONT_LINE)
	if not bool(stack_result.get("ok", false)):
		return _fail("expected to build a stack before testing stack leave")
	stack_manager.zone_manager.move_card(stack_manager.game_state, top_uid, UATypes.Zone.OUTSIDE, UATypes.PLAYER_ONE)
	var base_card = stack_manager.game_state.get_card(base_uid)
	var top_card = stack_manager.game_state.get_card(top_uid)
	if base_card == null or top_card == null or base_card.zone != UATypes.Zone.OUTSIDE or top_card.zone != UATypes.Zone.OUTSIDE:
		return _fail("expected both top and stacked-under cards to leave together")
	if _runtime_state_error(stack_manager) != "":
		return _fail("expected stack leave cleanup to avoid runtime residue")
	stack_manager.advance_phase()
	if stack_manager.game_state.phase != UATypes.Phase.ATTACK:
		return _fail("expected the stack leave branch to continue into the next phase")
	return _ok()

func _life_trigger_raid_card(id_suffix: String) -> Dictionary:
	return {
		"id": "TMP_LIFE_RAID_%s" % id_suffix,
		"name": "Life Raid %s" % id_suffix,
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-LR-%s" % id_suffix,
		"traits": ["Tester"],
		"cost_energy": {"GREEN": 1},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3500,
		"keywords": ["RAID"],
		"effects": [],
		"trigger_effects": [
			{
				"trigger": "ON_LIFE_TRIGGER",
				"text": "Add this card to hand, or raid it if legal.",
				"steps": [{"type": "LIFE_TRIGGER_RAID_CHOICE"}]
			}
		],
		"special_play_rule": {
			"type": "RAID",
			"raid_target_name": "Life Raid Base %s" % id_suffix,
			"allow_from_hand": true,
			"require_full_energy": true,
			"life_trigger_only": true
		},
	}

func _test_life_trigger_binary_choice_fully_settles() -> Dictionary:
	var add_manager := _new_manager()
	add_manager.game_state.active_player_id = UATypes.PLAYER_ONE
	add_manager.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(_player(add_manager, UATypes.PLAYER_ONE), 1)
	if not _ensure_color_energy(add_manager, UATypes.PLAYER_ONE, "GREEN", 1):
		return _fail("expected the add-to-hand branch to prepare raid-legal green energy")
	var add_source_uid := _spawn_temp_card(add_manager, UATypes.PLAYER_ONE, _life_trigger_raid_card("ADD"), UATypes.Zone.LIFE, true)
	var add_base_uid := _spawn_temp_card(add_manager, UATypes.PLAYER_ONE, {
		"id": "TMP_LIFE_RAID_BASE_ADD",
		"name": "Life Raid Base ADD",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-LRB-ADD",
		"traits": ["Tester"],
		"cost_energy": {"GREEN": 1},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	if add_source_uid == "" or add_base_uid == "":
		return _fail("expected the add-to-hand branch to prepare both the life card and legal raid base")
	var add_player := _player(add_manager, UATypes.PLAYER_ONE)
	add_player.life.erase(add_source_uid)
	add_player.life.push_front(add_source_uid)
	_trim_life_to_count(add_manager, UATypes.PLAYER_ONE, 2)
	add_manager.effect_resolver.deal_damage_to_player(add_manager.game_state, UATypes.PLAYER_ONE, 1)
	add_manager.resolve_life_trigger_decision(add_source_uid, true)
	if add_manager.game_state.pending_decisions.is_empty():
		return _fail("expected the add-to-hand branch to expose the raid-or-hand choice")
	add_manager.resolve_pending_decision("LIFE_TRIGGER_RAID_CHOICE", {"choice": "ADD_TO_HAND"})
	_drain_pending_life_windows(add_manager, false)
	_finalize_pending_life_damage_if_possible(add_manager)
	var add_source_card = add_manager.game_state.get_card(add_source_uid)
	if add_source_card == null or add_source_card.zone != UATypes.Zone.HAND:
		return _fail("expected the add-to-hand branch to move the life trigger card into hand")
	var add_cleanup_error := _runtime_state_error(add_manager)
	if add_cleanup_error != "":
		return _fail("expected the add-to-hand branch to finish cleanly, but %s" % add_cleanup_error)

	var raid_manager := _new_manager()
	raid_manager.game_state.active_player_id = UATypes.PLAYER_ONE
	raid_manager.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(_player(raid_manager, UATypes.PLAYER_ONE), 1)
	if not _ensure_color_energy(raid_manager, UATypes.PLAYER_ONE, "GREEN", 1):
		return _fail("expected the raid-now branch to prepare raid-legal green energy")
	var raid_source_uid := _spawn_temp_card(raid_manager, UATypes.PLAYER_ONE, _life_trigger_raid_card("RAID"), UATypes.Zone.LIFE, true)
	var raid_base_uid := _spawn_temp_card(raid_manager, UATypes.PLAYER_ONE, {
		"id": "TMP_LIFE_RAID_BASE_RAID",
		"name": "Life Raid Base RAID",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-LRB-RAID",
		"traits": ["Tester"],
		"cost_energy": {"GREEN": 1},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	if raid_source_uid == "" or raid_base_uid == "":
		return _fail("expected the raid-now branch to prepare both the life card and legal raid base")
	var raid_player := _player(raid_manager, UATypes.PLAYER_ONE)
	raid_player.life.erase(raid_source_uid)
	raid_player.life.push_front(raid_source_uid)
	_trim_life_to_count(raid_manager, UATypes.PLAYER_ONE, 2)
	raid_manager.effect_resolver.deal_damage_to_player(raid_manager.game_state, UATypes.PLAYER_ONE, 1)
	raid_manager.resolve_life_trigger_decision(raid_source_uid, true)
	raid_manager.resolve_pending_decision("LIFE_TRIGGER_RAID_CHOICE", {"choice": "RAID_NOW"})
	raid_manager.resolve_pending_decision("LIFE_TRIGGER_RAID_TARGET", {"choice": raid_base_uid})
	_drain_pending_life_windows(raid_manager, false)
	_finalize_pending_life_damage_if_possible(raid_manager)
	var raid_source_card = raid_manager.game_state.get_card(raid_source_uid)
	if raid_source_card == null or raid_source_card.zone != UATypes.Zone.FRONT_LINE or not bool(raid_source_card.flags.get("entered_via_raid", false)):
		return _fail("expected the raid-now branch to place the card onto the front line via raid")
	var raid_cleanup_error := _runtime_state_error(raid_manager)
	if raid_cleanup_error != "":
		return _fail("expected the raid-now branch to finish cleanly, but %s" % raid_cleanup_error)
	var phase_before := raid_manager.game_state.phase
	raid_manager.advance_phase()
	if raid_manager.game_state.phase == phase_before:
		return _fail("expected the raid-now branch to continue advancing after settling life damage")

	var fallback_manager := _new_manager()
	fallback_manager.game_state.active_player_id = UATypes.PLAYER_ONE
	fallback_manager.game_state.phase = UATypes.Phase.MAIN
	var fallback_source_uid := _spawn_temp_card(fallback_manager, UATypes.PLAYER_ONE, _life_trigger_raid_card("FALLBACK"), UATypes.Zone.LIFE, true)
	var wrong_base_uid := _spawn_temp_card(fallback_manager, UATypes.PLAYER_ONE, {
		"id": "TMP_LIFE_RAID_WRONG_BASE",
		"name": "Wrong Base",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-LRB-WRONG",
		"traits": ["Tester"],
		"cost_energy": {"GREEN": 1},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	if fallback_source_uid == "" or wrong_base_uid == "":
		return _fail("expected the fallback branch to prepare both the life card and an illegal base")
	var fallback_player := _player(fallback_manager, UATypes.PLAYER_ONE)
	fallback_player.life.erase(fallback_source_uid)
	fallback_player.life.push_front(fallback_source_uid)
	_trim_life_to_count(fallback_manager, UATypes.PLAYER_ONE, 2)
	fallback_manager.effect_resolver.deal_damage_to_player(fallback_manager.game_state, UATypes.PLAYER_ONE, 1)
	fallback_manager.resolve_life_trigger_decision(fallback_source_uid, true)
	_drain_pending_life_windows(fallback_manager, false)
	_finalize_pending_life_damage_if_possible(fallback_manager)
	var fallback_source_card = fallback_manager.game_state.get_card(fallback_source_uid)
	if fallback_source_card == null or fallback_source_card.zone != UATypes.Zone.HAND:
		return _fail("expected the illegal raid-now branch to fall back to hand")
	var fallback_cleanup_error := _runtime_state_error(fallback_manager)
	if fallback_cleanup_error != "":
		return _fail("expected the fallback branch to finish cleanly, but %s" % fallback_cleanup_error)
	return _ok()

func _state_signature(manager: GameManager) -> String:
	return "%s|%s|%d|%d|%d|%d|%d|%d|%s" % [
		manager.game_state.active_player_id,
		UATypes.Phase.keys()[manager.game_state.phase],
		manager.game_state.turn_number,
		manager.game_state.pending_decisions.size(),
		manager.game_state.pending_life_triggers.size(),
		manager.game_state.pending_life_reveal.size(),
		manager.game_state.effect_queue.size(),
		manager.game_state.delayed_effects.size(),
		manager.game_state.winner_player_id,
	]

func _test_ai_long_run_stability() -> Dictionary:
	var manager := GameManager.new()
	manager.setup_game({
		UATypes.PLAYER_ONE: {"controller": "AI_SIMPLE"},
		UATypes.PLAYER_TWO: {"controller": "AI_SIMPLE"},
	})
	var iterations := 0
	while iterations < 60 and manager.game_state.winner_player_id == "" and manager.game_state.turn_number < 4:
		manager.drive_controllers(64)
		if not manager.game_state.pending_life_reveal.is_empty():
			var current_uid := str(manager.game_state.pending_life_reveal.get("current_card_uid", ""))
			if current_uid != "":
				manager.acknowledge_life_reveal(current_uid)
		if not manager.game_state.opening_complete and manager.game_state.turn_number > 1:
			return _fail("expected the opening sequence to finish before later turn progression")
		iterations += 1
	if not manager.game_state.opening_complete:
		return _fail("expected ai vs ai to resolve the opening automatically")
	if manager.game_state.winner_player_id == "" and manager.game_state.turn_number < 4:
		return _fail("expected ai vs ai to either find a winner or advance through multiple full turns")
	return _ok()

func _test_cross_turn_delayed_leave_and_ai_pacing_chain() -> Dictionary:
	var manager := _new_manager({
		UATypes.PLAYER_ONE: {"controller": "AI_SIMPLE"},
		UATypes.PLAYER_TWO: {"controller": "AI_SIMPLE"},
	})
	if not _advance_to_turn_draw(manager, UATypes.PLAYER_ONE, 3, 96):
		return _fail("failed to reach P1 turn 3 draw")
	manager.drive_controllers(64)
	for _i in range(12):
		if manager.game_state.winner_player_id != "":
			break
		manager.advance_phase()
		manager.drive_controllers(64)
	var settle_safety := 8
	while settle_safety > 0:
		var runtime_error := _runtime_state_error(manager)
		if runtime_error == "":
			break
		manager.drive_controllers(64)
		settle_safety -= 1
	var clean := _assert_runtime_clean(manager, "cross turn ai chain")
	if not bool(clean.get("ok", false)):
		var queue_head := {}
		if not manager.game_state.effect_queue.is_empty():
			queue_head = manager.game_state.effect_queue[0]
		var pending_life := {}
		if not manager.game_state.pending_life_triggers.is_empty():
			pending_life = manager.game_state.pending_life_triggers[0]
		var legal_actions: Array = []
		var pending_player_id := str(pending_life.get("player_id", manager.game_state.active_player_id))
		legal_actions = manager.rules_engine.get_legal_actions(manager.game_state, pending_player_id)
		return _fail("%s | runtime=%s | queue_head=%s" % [
			"%s | pending_life=%s | priority=%s | legal_actions=%s" % [
				str(clean.get("error", "runtime residue")),
				str(pending_life),
				manager._current_priority_player_id(),
				str(legal_actions),
			],
			_runtime_state_error(manager),
			str(queue_head),
		])
	if manager.game_state.turn_number < 3:
		return _fail("turn flow regressed before long-run assertions")
	return _ok()
