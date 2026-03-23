extends SceneTree

const UATypes = preload("res://core/ua_types.gd")
const GameManager = preload("res://core/game_manager.gd")
const PlayerState = preload("res://data/player_state.gd")
const CardInstance = preload("res://data/card_instance.gd")
const CardDef = preload("res://data/card_def.gd")

const RAW_ENTER_DRAW_TWO := "UA31ST_MMM_1_106"
const RAW_PLAY_LIFE_TO_HAND_DRAW_TWO := "UA31BT_MMM_1_092"
const RAW_PREVIEW_DISCARD := "UA31ST_MMM_1_103"
const RAW_PREVIEW_DISTINCT := "UA31ST_MMM_1_109"
const RAW_ON_LEAVE_TO_HAND := "UA31BT_MMM_1_069"
const RAW_KYOKO := "UA31BT_MMM_1_082"
const RAW_EVENT_AP_DISCOUNT := "UA31BT_MMM_1_099"
const RAW_EVENT_COMPLEX_COST := "UA31BT_MMM_1_100"
const RAW_TARGET_REMOVE := "UA31BT_MMM_1_077"
const RAW_LIFE_TRIGGER_TARGET := "UA31BT_MMM_1_084"
const RAW_MAIN_ACTIVATE := "UA31BT_MMM_1_089"
const RAW_EVENT_READY_AP := "UA31BT_MMM_1_095"

var _failures: Array[String] = []
var _passes: Array[String] = []

func _init() -> void:
	_run_test("Raw ON_ENTER Draw 2", _test_raw_on_enter_draw_two)
	_run_test("Raw ON_PLAY Life To Hand Draw 2", _test_raw_on_play_life_to_hand_draw_two)
	_run_test("Raw Hand AP Discount", _test_raw_hand_ap_discount)
	_run_test("Raw ON_LEAVE Return To Hand", _test_raw_on_leave_return_to_hand)
	_run_test("Raw Complex Cost Combo", _test_raw_complex_cost_combo)
	_run_test("Raw Preview Add Then Discard", _test_raw_preview_add_then_discard)
	_run_test("Raw Preview Distinct Names", _test_raw_preview_distinct_names)
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

func _test_raw_on_enter_draw_two() -> Dictionary:
	var manager := _new_manager()
	var player_id := UATypes.PLAYER_ONE
	manager.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(_player(manager, player_id), 3)
	if not _place_red_energy(manager, player_id, 3):
		return _fail("Should be able to prepare 3 raw red energy cards for ON_ENTER.")
	var source_uid := _move_or_spawn_card_to_zone(manager, player_id, RAW_ENTER_DRAW_TWO, UATypes.Zone.HAND)
	if source_uid == "":
		return _fail("Raw ON_ENTER draw-2 sample card should be available.")
	var player := _player(manager, player_id)
	var hand_before := player.hand.size()
	var deck_before := player.deck.size()
	manager.play_card(source_uid, UATypes.Zone.FRONT_LINE)
	if player.hand.size() != hand_before + 1:
		return _fail("Raw ON_ENTER draw-2 should increase hand by exactly 1 after playing from hand.")
	if player.deck.size() != deck_before - 2:
		return _fail("Raw ON_ENTER draw-2 should draw exactly 2 cards.")
	return _ok()

func _test_raw_on_play_life_to_hand_draw_two() -> Dictionary:
	var manager := _new_manager()
	var player_id := UATypes.PLAYER_ONE
	manager.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(_player(manager, player_id), 3)
	if not _place_red_energy(manager, player_id, 2):
		return _fail("Should be able to prepare 2 raw red energy cards for ON_PLAY.")
	var source_uid := _move_or_spawn_card_to_zone(manager, player_id, RAW_PLAY_LIFE_TO_HAND_DRAW_TWO, UATypes.Zone.HAND)
	if source_uid == "":
		return _fail("Raw ON_PLAY sample card should be available.")
	var chosen_life_uid := _ensure_life_card(manager, player_id)
	if chosen_life_uid == "":
		return _fail("Raw ON_PLAY sample should have a selectable life card.")
	var player := _player(manager, player_id)
	var hand_before := player.hand.size()
	var life_before := player.life.size()
	var deck_before := player.deck.size()
	manager.play_card(source_uid, UATypes.Zone.OUTSIDE)
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("Raw ON_PLAY sample should request explicit life target selection.")
	var decision: Dictionary = manager.game_state.pending_decisions[0]
	if str(decision.get("type", "")) != "ABILITY_TARGET_SELECTION":
		return _fail("Raw ON_PLAY sample should use ability target selection.")
	manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(decision.get("resolution_id", "")),
		"choice": chosen_life_uid,
	})
	if not player.hand.has(chosen_life_uid):
		return _fail("Raw ON_PLAY sample should move the selected life card to hand.")
	if player.hand.size() != hand_before + 2:
		return _fail("Raw ON_PLAY sample should add the life card and draw 2.")
	if player.life.size() != life_before - 1:
		return _fail("Raw ON_PLAY sample should reduce life by exactly 1.")
	if player.deck.size() != deck_before - 2:
		return _fail("Raw ON_PLAY sample should draw exactly 2 cards.")
	return _ok()

func _test_raw_hand_ap_discount() -> Dictionary:
	var manager := _new_manager()
	var player_id := UATypes.PLAYER_ONE
	var opponent_id := UATypes.PLAYER_TWO
	manager.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(_player(manager, player_id), 3)
	if not _ensure_red_energy(manager, player_id, 4):
		return _fail("Should be able to prepare 4 raw red energy cards for the AP discount event.")
	var discount_uid := _move_or_spawn_card_to_zone(manager, player_id, RAW_EVENT_AP_DISCOUNT, UATypes.Zone.HAND)
	var kyoko_uid := _move_or_spawn_card_to_zone(manager, player_id, RAW_KYOKO, UATypes.Zone.FRONT_LINE)
	var target_uid := _move_or_spawn_card_to_zone(manager, opponent_id, RAW_ON_LEAVE_TO_HAND, UATypes.Zone.FRONT_LINE)
	if discount_uid == "" or kyoko_uid == "" or target_uid == "":
		return _fail("Raw AP discount sample cards should be available.")
	var player := _player(manager, player_id)
	var ap_before := player.ap_active_count()
	manager.play_card(discount_uid, UATypes.Zone.OUTSIDE)
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("Raw AP discount event should request explicit target selection.")
	var decision: Dictionary = manager.game_state.pending_decisions[0]
	if str(decision.get("type", "")) != "ABILITY_TARGET_SELECTION":
		return _fail("Raw AP discount event should use ability target selection.")
	manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(decision.get("resolution_id", "")),
		"choice": target_uid,
	})
	if player.ap_active_count() != ap_before - 1:
		return _fail("Raw AP discount event should reduce the play cost by exactly 1 AP while Kyoko is on the field.")
	if not player.outside.has(discount_uid):
		return _fail("Raw AP discount event should move itself to outside after resolution.")
	return _ok()

func _test_raw_on_leave_return_to_hand() -> Dictionary:
	var manager := _new_manager()
	var player_id := UATypes.PLAYER_ONE
	var source_uid := _move_or_spawn_card_to_zone(manager, player_id, RAW_ON_LEAVE_TO_HAND, UATypes.Zone.FRONT_LINE)
	if source_uid == "":
		return _fail("Raw ON_LEAVE sample card should be available.")
	var player := _player(manager, player_id)
	var hand_before := player.hand.size()
	manager.effect_resolver.resolve_trigger(source_uid, UATypes.TriggerType.ON_LEAVE, manager.game_state, {"target_player_id": player_id})
	if not player.hand.has(source_uid):
		return _fail("Raw ON_LEAVE sample should move itself back to hand.")
	if player.hand.size() != hand_before + 1:
		return _fail("Raw ON_LEAVE sample should add exactly 1 card to hand.")
	return _ok()

func _test_raw_complex_cost_combo() -> Dictionary:
	var manager := _new_manager()
	var player_id := UATypes.PLAYER_ONE
	var opponent_id := UATypes.PLAYER_TWO
	manager.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(_player(manager, player_id), 3)
	if not _ensure_red_energy(manager, player_id, 4):
		return _fail("Should be able to prepare 4 raw red energy cards for the complex event.")
	var source_uid := _move_or_spawn_card_to_zone(manager, player_id, RAW_EVENT_COMPLEX_COST, UATypes.Zone.HAND)
	var kyoko_uid := _move_or_spawn_card_to_zone(manager, player_id, RAW_KYOKO, UATypes.Zone.FRONT_LINE)
	var target_uid := _move_or_spawn_card_to_zone(manager, opponent_id, RAW_ON_LEAVE_TO_HAND, UATypes.Zone.FRONT_LINE)
	if source_uid == "" or kyoko_uid == "" or target_uid == "":
		return _fail("Raw complex cost sample cards should be available.")
	var player := _player(manager, player_id)
	var hand_before := player.hand.size()
	var deck_before := player.deck.size()
	manager.play_card(source_uid, UATypes.Zone.OUTSIDE)
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("Raw complex cost event should first request the cost card selection.")
	var first_decision: Dictionary = manager.game_state.pending_decisions[0]
	manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(first_decision.get("resolution_id", "")),
		"choice": kyoko_uid,
	})
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("Raw complex cost event should then request the enemy target selection.")
	var second_decision: Dictionary = manager.game_state.pending_decisions[0]
	manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(second_decision.get("resolution_id", "")),
		"choice": target_uid,
	})
	var kyoko_card := manager.game_state.get_card(kyoko_uid)
	var target_card := manager.game_state.get_card(target_uid)
	if kyoko_card == null or kyoko_card.zone != UATypes.Zone.OUTSIDE:
		return _fail("Raw complex cost event should move the selected Kyoko to outside as a cost.")
	if target_card == null or target_card.zone != UATypes.Zone.OUTSIDE:
		return _fail("Raw complex cost event should move the selected enemy to outside.")
	if player.hand.size() != hand_before + 1:
		return _fail("Raw complex cost event should net +1 hand after drawing 2 from hand.")
	if deck_before - player.deck.size() != 2:
		return _fail("Raw complex cost event should draw exactly 2 cards.")
	if not player.outside.has(source_uid):
		return _fail("Raw complex cost event should move itself to outside after resolution.")
	return _ok()

func _test_raw_preview_add_then_discard() -> Dictionary:
	var manager := _new_manager()
	var player_id := UATypes.PLAYER_ONE
	manager.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(_player(manager, player_id), 3)
	if not _ensure_red_energy(manager, player_id, 1):
		return _fail("Should be able to prepare 1 raw red energy card for the preview-discard sample.")
	var source_uid := _move_or_spawn_card_to_zone(manager, player_id, RAW_PREVIEW_DISCARD, UATypes.Zone.HAND)
	if source_uid == "":
		return _fail("Raw preview-discard sample card should be available.")
	var preview_magic_uid := _spawn_temp_card(manager, player_id, {
		"id": "TMP_PREVIEW_MAGIC",
		"name": "测试魔法少女A",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-PREVIEW-1",
		"traits": ["魔法少女"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 1500,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.DECK, true)
	var preview_madoka_uid := _spawn_temp_card(manager, player_id, {
		"id": "TMP_PREVIEW_MADOKA",
		"name": "鹿目 まどか",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-PREVIEW-2",
		"traits": ["魔法少女"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 1500,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.DECK, true)
	var preview_other_uid := _spawn_temp_card(manager, player_id, {
		"id": "TMP_PREVIEW_OTHER",
		"name": "测试辅助牌",
		"card_type": "EVENT",
		"title_code": "TMP",
		"number": "TMP-PREVIEW-3",
		"traits": [],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {},
		"bp": 0,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.DECK, true)
	var preview_fourth_uid := _spawn_temp_card(manager, player_id, {
		"id": "TMP_PREVIEW_FOURTH",
		"name": "测试魔法少女B",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-PREVIEW-4",
		"traits": ["魔法少女"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 1500,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.DECK, true)
	_set_deck_top_order(manager, player_id, [preview_madoka_uid, preview_magic_uid, preview_other_uid, preview_fourth_uid])
	var player := _player(manager, player_id)
	var hand_before := player.hand.size()
	var outside_before := player.outside.size()
	manager.play_card(source_uid, UATypes.Zone.FRONT_LINE)
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("Raw preview-discard sample should first request a preview selection.")
	var first_decision: Dictionary = manager.game_state.pending_decisions[0]
	manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(first_decision.get("resolution_id", "")),
		"choice": preview_magic_uid,
	})
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("Raw preview-discard sample should then request preview reorder.")
	var second_decision: Dictionary = manager.game_state.pending_decisions[0]
	manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(second_decision.get("resolution_id", "")),
		"choices": [preview_fourth_uid, preview_other_uid, preview_madoka_uid],
	})
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("Raw preview-discard sample should request a hand discard after adding the previewed card.")
	var third_decision: Dictionary = manager.game_state.pending_decisions[0]
	var discard_uid := str(third_decision.get("choices", [])[0].get("value", "")) if not third_decision.get("choices", []).is_empty() else ""
	if discard_uid == "":
		return _fail("Raw preview-discard sample should expose a discard choice.")
	manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(third_decision.get("resolution_id", "")),
		"choice": discard_uid,
	})
	if not player.hand.has(preview_magic_uid):
		return _fail("Raw preview-discard sample should move the chosen preview card to hand.")
	if player.hand.size() != hand_before - 1:
		return _fail("Raw preview-discard sample should net -1 hand after playing from hand, adding 1, then discarding 1.")
	if player.outside.size() != outside_before + 1:
		return _fail("Raw preview-discard sample should discard exactly 1 hand card to outside.")
	var deck_tail := player.deck.slice(max(0, player.deck.size() - 3), player.deck.size())
	if deck_tail != [preview_fourth_uid, preview_other_uid, preview_madoka_uid]:
		return _fail("Raw preview-discard sample should place the remaining preview cards on the deck bottom in the chosen order.")
	return _ok()

func _test_raw_preview_distinct_names() -> Dictionary:
	var manager := _new_manager()
	var player_id := UATypes.PLAYER_ONE
	manager.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(_player(manager, player_id), 3)
	if not _ensure_red_energy(manager, player_id, 4):
		return _fail("Should be able to prepare 4 raw red energy cards for the distinct preview sample.")
	var source_uid := _move_or_spawn_card_to_zone(manager, player_id, RAW_PREVIEW_DISTINCT, UATypes.Zone.HAND)
	if source_uid == "":
		return _fail("Raw distinct preview sample card should be available.")
	var preview_a1_uid := _spawn_temp_card(manager, player_id, {
		"id": "TMP_DISTINCT_A1",
		"name": "测试魔法少女甲",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-DISTINCT-1",
		"traits": ["魔法少女"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 1500,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.DECK, true)
	var preview_a2_uid := _spawn_temp_card(manager, player_id, {
		"id": "TMP_DISTINCT_A2",
		"name": "测试魔法少女甲",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-DISTINCT-2",
		"traits": ["魔法少女"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 1500,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.DECK, true)
	var preview_b_uid := _spawn_temp_card(manager, player_id, {
		"id": "TMP_DISTINCT_B",
		"name": "测试魔法少女乙",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-DISTINCT-3",
		"traits": ["魔法少女"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 1500,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.DECK, true)
	var preview_c_uid := _spawn_temp_card(manager, player_id, {
		"id": "TMP_DISTINCT_C",
		"name": "测试魔法少女丙",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-DISTINCT-4",
		"traits": ["魔法少女"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 1500,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.DECK, true)
	var preview_non_magic_uid := _spawn_temp_card(manager, player_id, {
		"id": "TMP_DISTINCT_OTHER",
		"name": "测试普通角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-DISTINCT-5",
		"traits": ["其他"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 1500,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.DECK, true)
	_set_deck_top_order(manager, player_id, [preview_a1_uid, preview_a2_uid, preview_b_uid, preview_c_uid, preview_non_magic_uid])
	var player := _player(manager, player_id)
	var hand_before := player.hand.size()
	manager.play_card(source_uid, UATypes.Zone.OUTSIDE)
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("Raw distinct preview sample should first request a preview selection.")
	var first_decision: Dictionary = manager.game_state.pending_decisions[0]
	manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(first_decision.get("resolution_id", "")),
		"choices": [preview_a1_uid, preview_b_uid, preview_c_uid],
	})
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("Raw distinct preview sample should then request preview reorder.")
	var second_decision: Dictionary = manager.game_state.pending_decisions[0]
	manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(second_decision.get("resolution_id", "")),
		"choices": [preview_non_magic_uid, preview_a2_uid],
	})
	if player.hand.size() != hand_before + 2:
		return _fail("Raw distinct preview sample should net +2 hand after adding 3 from hand-play event.")
	for required_uid in [preview_a1_uid, preview_b_uid, preview_c_uid]:
		if not player.hand.has(required_uid):
			return _fail("Raw distinct preview sample should add the chosen distinct-name preview cards to hand.")
	var deck_tail := player.deck.slice(max(0, player.deck.size() - 2), player.deck.size())
	if deck_tail != [preview_non_magic_uid, preview_a2_uid]:
		return _fail("Raw distinct preview sample should place the remaining preview cards on the deck bottom in the chosen order.")
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

func _ensure_red_energy(manager: GameManager, player_id: String, count: int) -> bool:
	if _place_red_energy(manager, player_id, count):
		return true
	while _count_red_energy(manager, player_id) < count:
		var card_uid := _move_or_spawn_card_to_zone(manager, player_id, RAW_ON_LEAVE_TO_HAND, UATypes.Zone.ENERGY_LINE)
		if card_uid == "":
			break
		var card := manager.game_state.get_card(card_uid)
		if card != null:
			card.state = UATypes.CardState.RESTED
	return _count_red_energy(manager, player_id) >= count

func _count_red_energy(manager: GameManager, player_id: String) -> int:
	var total := 0
	for card_uid in _player(manager, player_id).energy_line:
		var card := manager.game_state.get_card(card_uid)
		var card_def := manager.game_state.get_card_def(card.def_id) if card != null else null
		if card_def == null:
			continue
		total += int(card_def.energy_provided.get("RED", 0))
	return total

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

func _set_deck_top_order(manager: GameManager, player_id: String, ordered_uids: Array) -> void:
	var player := _player(manager, player_id)
	if player == null:
		return
	for uid_variant in ordered_uids:
		player.deck.erase(str(uid_variant))
	for i in range(ordered_uids.size() - 1, -1, -1):
		player.deck.push_front(str(ordered_uids[i]))

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
