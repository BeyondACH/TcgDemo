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
const RAW_HOMURA_RAID_SUPPORT := "UA31BT_MMM_1_075"
const RAW_HOMURA_OPTIONAL_CHAIN := "UA31ST_MMM_1_102"
const RAW_FIELD_OUTSIDE_SEARCH := "UA31ST_MMM_1_108"
const RAW_RAID_DYNAMIC_REMOVE := "UA31BT_MMM_1_078"
const RAW_EVENT_DYNAMIC_BP_SAYAKA := "UA31BT_MMM_1_093"
const RAW_EVENT_DYNAMIC_BP_MADOKA_BT := "UA31BT_MMM_1_094"
const RAW_EVENT_DYNAMIC_BP_MADOKA_ST := "UA31ST_MMM_1_094"
const RAW_RETURN_OTHER_OR_SELF := "UA31BT_MMM_1_085"
const RAW_RETURN_OTHER_OR_SELF_ST := "UA31ST_MMM_1_085"
const RAW_PREVIEW_MAGIC_GIRL_REWARD := "UA31BT_MMM_1_098"
const RAW_TEMP_ENERGY_SELF_LEAVE_BT := "UA31BT_MMM_1_070"
const RAW_TEMP_ENERGY_SELF_LEAVE_ST := "UA31ST_MMM_1_070"
const RAW_SELF_SPECIAL_PLAY_PERMISSION := "UA31BT_MMM_1_090"

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
	_run_test("Raw On Enter Hand Summon", _test_raw_on_enter_hand_summon)
	_run_test("Raw On Enter Cannot Attack Until Next Self Turn", _test_raw_on_enter_cannot_attack_until_next_self_turn)
	_run_test("Raw Hand Summon Respects Play Validation", _test_raw_hand_summon_respects_play_validation)
	_run_test("Raw Optional Return Then Summon Skip", _test_raw_optional_return_then_summon_skip)
	_run_test("Raw Optional Return Then Summon Success", _test_raw_optional_return_then_summon_success)
	_run_test("Raw Outside Search Optional Branches", _test_raw_outside_search_optional_branches)
	_run_test("Raw RAID Dynamic BP Limit", _test_raw_raid_dynamic_bp_limit)
	_run_test("Raw Return Other Or Self Fallback", _test_raw_return_other_or_self_fallback)
	_run_test("Raw Conditional BP Event Upgrade Sayaka", _test_raw_conditional_bp_event_upgrade_sayaka)
	_run_test("Raw Conditional BP Event Upgrade Madoka", _test_raw_conditional_bp_event_upgrade_madoka)
	_run_test("Raw Preview Reward Magic Girl Branches", _test_raw_preview_reward_magic_girl_branches)
	_run_test("Raw Temporary Energy Bonus Then Self Leave", _test_raw_temporary_energy_bonus_then_self_leave)
	_run_test("Raw Self Special Play Permission After Leave", _test_raw_self_special_play_permission_after_leave)
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
	if defender.outside.size() != defender_outside_before + 2:
		return _fail("Raw life trigger should finalize both the removed target and the damaged life card into the resolver player's outside zone.")
	if target_card.controller_player_id != defender_id:
		return _fail("Raw life trigger should keep the removed target under the resolver player's outside controller.")
	if defender.life.has(life_uid):
		return _fail("Raw life trigger should consume the damaged life card.")
	return _ok()

func _test_raw_on_enter_hand_summon() -> Dictionary:
	var manager := _new_manager()
	var player_id := UATypes.PLAYER_ONE
	manager.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(_player(manager, player_id), 3)
	if not _ensure_red_energy(manager, player_id, 3):
		return _fail("Should be able to prepare 3 raw red energy cards for the hand-summon sample.")
	var source_uid := _move_or_spawn_card_to_zone(manager, player_id, RAW_KYOKO, UATypes.Zone.HAND)
	if source_uid == "":
		return _fail("Raw hand-summon source card should be available.")
	var valid_uid := _spawn_temp_card(manager, player_id, {
		"id": "TMP_HAND_SUMMON_VALID",
		"name": "测试红色魔法少女",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-HAND-SUMMON-1",
		"traits": ["魔法少女"],
		"cost_energy": {"RED": 2},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)
	var invalid_uid := _spawn_temp_card(manager, player_id, {
		"id": "TMP_HAND_SUMMON_INVALID",
		"name": "测试非目标角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-HAND-SUMMON-2",
		"traits": ["其他"],
		"cost_energy": {"BLUE": 2},
		"cost_ap": 2,
		"energy_provided": {"BLUE": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)
	var player := _player(manager, player_id)
	var hand_before := player.hand.size()
	var ap_before := player.ap_active_count()
	manager.play_card(source_uid, UATypes.Zone.FRONT_LINE)
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("Raw hand-summon sample should request an explicit hand target selection.")
	var decision: Dictionary = manager.game_state.pending_decisions[0]
	var choice_values: Array[String] = []
	for choice_variant in decision.get("choices", []):
		choice_values.append(str((choice_variant as Dictionary).get("value", "")))
	if not choice_values.has(valid_uid):
		return _fail("Raw hand-summon sample should expose the valid red magical-girl target.")
	if choice_values.has(invalid_uid):
		return _fail("Raw hand-summon sample should not expose cards failing AP/color/trait filters.")
	manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(decision.get("resolution_id", "")),
		"choice": valid_uid,
	})
	var summoned_card := manager.game_state.get_card(valid_uid)
	if summoned_card == null or summoned_card.zone != UATypes.Zone.FRONT_LINE:
		return _fail("Raw hand-summon sample should move the selected card from hand to front line.")
	if summoned_card.state != UATypes.CardState.RESTED:
		return _fail("Raw hand-summon sample should enter the selected card as rested.")
	if player.hand.size() != hand_before - 2:
		return _fail("Raw hand-summon sample should spend the source card and the selected summon card from hand.")
	if player.ap_active_count() != ap_before - 2:
		return _fail("Raw hand-summon sample should consume AP for both the source play and the summoned card.")
	return _ok()

func _test_raw_on_enter_cannot_attack_until_next_self_turn() -> Dictionary:
	var manager := _new_manager()
	var player_id := UATypes.PLAYER_ONE
	var opponent_id := UATypes.PLAYER_TWO
	manager.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(_player(manager, player_id), 3)
	if not _ensure_red_energy(manager, player_id, 4):
		return _fail("Should be able to prepare 4 raw red energy cards for the cannot-attack sample.")
	var source_uid := _move_or_spawn_card_to_zone(manager, player_id, RAW_HOMURA_RAID_SUPPORT, UATypes.Zone.FRONT_LINE)
	if source_uid == "":
		return _fail("Raw cannot-attack source card should be available.")
	var raid_target_uid := _spawn_temp_card(manager, player_id, {
		"id": "TMP_CANNOT_ATTACK_RAID_TARGET",
		"name": "暁美 ほむら",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-CANNOT-ATTACK-0",
		"traits": ["魔法少女"],
		"cost_energy": {"RED": 2},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 2500,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	_spawn_temp_card(manager, player_id, {
		"id": "TMP_CANNOT_ATTACK_MADOKA",
		"name": "鹿目 まどか",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-CANNOT-ATTACK-1",
		"traits": ["魔法少女"],
		"cost_energy": {"RED": 2},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 2500,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var summon_uid := _spawn_temp_card(manager, player_id, {
		"id": "TMP_CANNOT_ATTACK_SUMMON",
		"name": "测试连带登场角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-CANNOT-ATTACK-2",
		"traits": ["魔法少女"],
		"cost_energy": {"RED": 2},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)
	var locked_uid := _spawn_temp_card(manager, opponent_id, {
		"id": "TMP_CANNOT_ATTACK_TARGET",
		"name": "测试被限制攻击角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-CANNOT-ATTACK-3",
		"traits": ["敌方角色"],
		"cost_energy": {"RED": 2},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 2500,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var source_card = manager.game_state.get_card(source_uid)
	if source_card == null:
		return _fail("Raw cannot-attack source card instance should exist.")
	source_card.flags["entered_via_raid"] = true
	manager.effect_resolver.resolve_trigger(source_uid, UATypes.TriggerType.ON_ENTER, manager.game_state, {"target_player_id": player_id})
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("Raw cannot-attack sample should first request the hand summon selection.")
	var summon_decision: Dictionary = manager.game_state.pending_decisions[0]
	manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(summon_decision.get("resolution_id", "")),
		"choice": summon_uid,
	})
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("Raw cannot-attack sample should then request the opponent front-line target selection.")
	var lock_decision: Dictionary = manager.game_state.pending_decisions[0]
	var lock_choices: Array[String] = []
	for choice_variant in lock_decision.get("choices", []):
		lock_choices.append(str((choice_variant as Dictionary).get("value", "")))
	if not lock_choices.has(locked_uid):
		return _fail("Raw cannot-attack sample should expose the opponent front-line target after Madoka is present.")
	manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(lock_decision.get("resolution_id", "")),
		"choice": locked_uid,
	})
	var locked_card := manager.game_state.get_card(locked_uid)
	if locked_card == null or not (locked_card.flags.get("temp_keywords", []) as Array).has("CANNOT_ATTACK"):
		return _fail("Raw cannot-attack sample should add the temporary CANNOT_ATTACK keyword to the selected target.")
	manager.advance_phase()
	manager.advance_phase()
	manager.advance_phase()
	manager.advance_phase()
	manager.advance_phase()
	manager.advance_phase()
	var attack_validation := manager.rules_engine.can_attack(manager.game_state, opponent_id, locked_uid)
	if bool(attack_validation.get("ok", false)):
		return _fail("Raw cannot-attack sample should prevent the locked target from attacking during the opponent's next attack phase.")
	if str(attack_validation.get("reason", "")) != "cannot_attack":
		return _fail("Raw cannot-attack sample should fail attacks with the cannot_attack reason.")
	manager.advance_phase()
	manager.advance_phase()
	locked_card = manager.game_state.get_card(locked_uid)
	if locked_card == null:
		return _fail("Raw cannot-attack sample should keep the locked target on the field.")
	if (locked_card.flags.get("temp_keywords", []) as Array).has("CANNOT_ATTACK"):
		return _fail("Raw cannot-attack sample should remove the temporary CANNOT_ATTACK keyword at the next self turn start.")
	return _ok()

func _test_raw_hand_summon_respects_play_validation() -> Dictionary:
	var manager := _new_manager()
	var player_id := UATypes.PLAYER_ONE
	manager.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(_player(manager, player_id), 1)
	if not _ensure_red_energy(manager, player_id, 3):
		return _fail("Should be able to prepare 3 raw red energy cards for the hand-summon validation sample.")
	var source_uid := _move_or_spawn_card_to_zone(manager, player_id, RAW_KYOKO, UATypes.Zone.HAND)
	if source_uid == "":
		return _fail("Raw validation source card should be available.")
	var summon_uid := _spawn_temp_card(manager, player_id, {
		"id": "TMP_HAND_SUMMON_BLOCKED",
		"name": "测试待登场角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-HAND-SUMMON-3",
		"traits": ["魔法少女"],
		"cost_energy": {"RED": 2},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)
	manager.play_card(source_uid, UATypes.Zone.FRONT_LINE, {"allow_raid_play": false})
	if not manager.game_state.pending_decisions.is_empty():
		return _fail("Raw hand-summon validation sample should not offer targets when no AP remains for the follow-up play.")
	var summon_card := manager.game_state.get_card(summon_uid)
	if summon_card == null or summon_card.zone != UATypes.Zone.HAND:
		return _fail("Raw hand-summon validation sample should keep the blocked target in hand.")
	return _ok()

func _test_raw_optional_return_then_summon_skip() -> Dictionary:
	var manager := _new_manager()
	var player_id := UATypes.PLAYER_ONE
	manager.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(_player(manager, player_id), 3)
	if not _ensure_red_energy(manager, player_id, 4):
		return _fail("Should be able to prepare 4 raw red energy cards for the optional chain skip sample.")
	var source_uid := _move_or_spawn_card_to_zone(manager, player_id, RAW_HOMURA_OPTIONAL_CHAIN, UATypes.Zone.HAND)
	if source_uid == "":
		return _fail("Raw optional-chain source card should be available.")
	var madoka_uid := _spawn_temp_card(manager, player_id, {
		"id": "TMP_OPTIONAL_MADOKA_SKIP",
		"name": "鹿目 まどか",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-OPTIONAL-1",
		"traits": ["魔法少女"],
		"cost_energy": {"RED": 2},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var summon_uid := _spawn_temp_card(manager, player_id, {
		"id": "TMP_OPTIONAL_SUMMON_SKIP",
		"name": "测试后续登场角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-OPTIONAL-2",
		"traits": ["魔法少女"],
		"cost_energy": {"RED": 4},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 2500,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)
	var player := _player(manager, player_id)
	var hand_before := player.hand.size()
	var deck_before := player.deck.size()
	manager.play_card(source_uid, UATypes.Zone.FRONT_LINE)
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("Raw optional-chain skip sample should first request the optional Madoka selection.")
	var decision: Dictionary = manager.game_state.pending_decisions[0]
	manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(decision.get("resolution_id", "")),
		"choice": "",
	})
	if not manager.game_state.pending_decisions.is_empty():
		return _fail("Raw optional-chain skip sample should stop resolving after skipping the optional action.")
	if player.hand.size() != hand_before - 1:
		return _fail("Raw optional-chain skip sample should only lose the source card from hand.")
	if player.deck.size() != deck_before:
		return _fail("Raw optional-chain skip sample should not draw or move cards into the deck after skipping.")
	var madoka_card := manager.game_state.get_card(madoka_uid)
	if madoka_card == null or madoka_card.zone != UATypes.Zone.FRONT_LINE:
		return _fail("Raw optional-chain skip sample should leave Madoka on the field when the optional action is skipped.")
	var summon_card := manager.game_state.get_card(summon_uid)
	if summon_card == null or summon_card.zone != UATypes.Zone.HAND:
		return _fail("Raw optional-chain skip sample should keep the follow-up summon target in hand.")
	return _ok()

func _test_raw_optional_return_then_summon_success() -> Dictionary:
	var manager := _new_manager()
	var player_id := UATypes.PLAYER_ONE
	manager.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(_player(manager, player_id), 3)
	if not _ensure_red_energy(manager, player_id, 4):
		return _fail("Should be able to prepare 4 raw red energy cards for the optional chain success sample.")
	var source_uid := _move_or_spawn_card_to_zone(manager, player_id, RAW_HOMURA_OPTIONAL_CHAIN, UATypes.Zone.HAND)
	if source_uid == "":
		return _fail("Raw optional-chain source card should be available.")
	var madoka_uid := _spawn_temp_card(manager, player_id, {
		"id": "TMP_OPTIONAL_MADOKA_SUCCESS",
		"name": "鹿目 まどか",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-OPTIONAL-3",
		"traits": ["魔法少女"],
		"cost_energy": {"RED": 2},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var summon_uid := _spawn_temp_card(manager, player_id, {
		"id": "TMP_OPTIONAL_SUMMON_SUCCESS",
		"name": "测试连锁登场角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-OPTIONAL-4",
		"traits": ["魔法少女"],
		"cost_energy": {"RED": 4},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 2500,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)
	var player := _player(manager, player_id)
	var hand_before := player.hand.size()
	var deck_before := player.deck.size()
	manager.play_card(source_uid, UATypes.Zone.FRONT_LINE)
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("Raw optional-chain success sample should first request the optional Madoka selection.")
	var first_decision: Dictionary = manager.game_state.pending_decisions[0]
	manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(first_decision.get("resolution_id", "")),
		"choice": madoka_uid,
	})
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("Raw optional-chain success sample should then request the follow-up summon selection.")
	var second_decision: Dictionary = manager.game_state.pending_decisions[0]
	manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(second_decision.get("resolution_id", "")),
		"choice": summon_uid,
	})
	if player.hand.size() != hand_before - 1:
		return _fail("Raw optional-chain success sample should net -1 hand after draw 1 and follow-up summon.")
	if player.deck.size() != deck_before:
		return _fail("Raw optional-chain success sample should keep deck size stable after returning one card and drawing one card.")
	var deck_tail := player.deck.slice(max(0, player.deck.size() - 1), player.deck.size())
	if deck_tail != [madoka_uid]:
		return _fail("Raw optional-chain success sample should place the selected Madoka on the deck bottom.")
	var summon_card := manager.game_state.get_card(summon_uid)
	if summon_card == null or summon_card.zone != UATypes.Zone.FRONT_LINE:
		return _fail("Raw optional-chain success sample should move the selected follow-up card to front line.")
	if summon_card.state != UATypes.CardState.RESTED:
		return _fail("Raw optional-chain success sample should enter the follow-up card as rested.")
	return _ok()

func _test_raw_outside_search_optional_branches() -> Dictionary:
	var manager_skip := _new_manager()
	var player_id := UATypes.PLAYER_ONE
	manager_skip.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(_player(manager_skip, player_id), 1)
	if not _ensure_red_energy(manager_skip, player_id, 3):
		return _fail("Should be able to prepare 3 raw red energy cards for the outside-search sample.")
	var source_skip_uid := _move_or_spawn_card_to_zone(manager_skip, player_id, RAW_FIELD_OUTSIDE_SEARCH, UATypes.Zone.HAND)
	var discard_skip_uid := _spawn_temp_card(manager_skip, player_id, {
		"id": "TMP_OUTSIDE_SKIP_DISCARD",
		"name": "测试弃牌",
		"card_type": "EVENT",
		"title_code": "TMP",
		"number": "TMP-OUTSIDE-1",
		"traits": [],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {},
		"bp": 0,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)
	var outside_skip_uid := _spawn_temp_card(manager_skip, player_id, {
		"id": "TMP_OUTSIDE_SKIP_TARGET",
		"name": "测试场外角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-OUTSIDE-2",
		"traits": ["魔法少女"],
		"cost_energy": {"RED": 3},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.OUTSIDE, true)
	manager_skip.play_card(source_skip_uid, UATypes.Zone.ENERGY_LINE)
	if manager_skip.game_state.pending_decisions.size() != 1:
		return _fail("Raw outside-search skip sample should first request the optional hand discard.")
	var skip_decision: Dictionary = manager_skip.game_state.pending_decisions[0]
	manager_skip.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(skip_decision.get("resolution_id", "")),
		"choice": "",
	})
	if not manager_skip.game_state.pending_decisions.is_empty():
		return _fail("Raw outside-search skip sample should stop after skipping the discard.")
	var discard_skip_card := manager_skip.game_state.get_card(discard_skip_uid)
	var outside_skip_card := manager_skip.game_state.get_card(outside_skip_uid)
	if discard_skip_card == null or discard_skip_card.zone != UATypes.Zone.HAND:
		return _fail("Raw outside-search skip sample should keep the discard candidate in hand.")
	if outside_skip_card == null or outside_skip_card.zone != UATypes.Zone.OUTSIDE:
		return _fail("Raw outside-search skip sample should leave the outside candidate in outside.")

	var manager_success := _new_manager()
	manager_success.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(_player(manager_success, player_id), 1)
	if not _ensure_red_energy(manager_success, player_id, 3):
		return _fail("Should be able to prepare 3 raw red energy cards for the outside-search success sample.")
	var source_success_uid := _move_or_spawn_card_to_zone(manager_success, player_id, RAW_FIELD_OUTSIDE_SEARCH, UATypes.Zone.HAND)
	var discard_success_uid := _spawn_temp_card(manager_success, player_id, {
		"id": "TMP_OUTSIDE_SUCCESS_DISCARD",
		"name": "测试弃牌成功",
		"card_type": "EVENT",
		"title_code": "TMP",
		"number": "TMP-OUTSIDE-3",
		"traits": [],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {},
		"bp": 0,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)
	var outside_success_uid := _spawn_temp_card(manager_success, player_id, {
		"id": "TMP_OUTSIDE_SUCCESS_TARGET",
		"name": "测试场外检索角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-OUTSIDE-4",
		"traits": ["魔法少女"],
		"cost_energy": {"RED": 3},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.OUTSIDE, true)
	var opponent_outside_uid := _spawn_temp_card(manager_success, UATypes.PLAYER_TWO, {
		"id": "TMP_OUTSIDE_OPPONENT_TARGET",
		"name": "对手场外角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-OUTSIDE-5",
		"traits": ["魔法少女"],
		"cost_energy": {"RED": 3},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.OUTSIDE, true)
	var player_success := _player(manager_success, player_id)
	manager_success.play_card(source_success_uid, UATypes.Zone.ENERGY_LINE)
	if manager_success.game_state.pending_decisions.size() != 1:
		return _fail("Raw outside-search success sample should first request the optional hand discard.")
	var first_decision: Dictionary = manager_success.game_state.pending_decisions[0]
	manager_success.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(first_decision.get("resolution_id", "")),
		"choice": discard_success_uid,
	})
	if manager_success.game_state.pending_decisions.size() != 1:
		return _fail("Raw outside-search success sample should then request the outside retrieval selection.")
	var second_decision: Dictionary = manager_success.game_state.pending_decisions[0]
	var second_values: Array[String] = []
	for choice_variant in second_decision.get("choices", []):
		second_values.append(str((choice_variant as Dictionary).get("value", "")))
	if not second_values.has(outside_success_uid):
		return _fail("Raw outside-search success sample should expose the controller's valid outside target.")
	if second_values.has(opponent_outside_uid):
		return _fail("Raw outside-search success sample should not expose opponent outside cards.")
	manager_success.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(second_decision.get("resolution_id", "")),
		"choice": outside_success_uid,
	})
	var discard_success_card := manager_success.game_state.get_card(discard_success_uid)
	var outside_success_card := manager_success.game_state.get_card(outside_success_uid)
	if discard_success_card == null or discard_success_card.zone != UATypes.Zone.OUTSIDE:
		return _fail("Raw outside-search success sample should move the discarded hand card to outside.")
	if outside_success_card == null or outside_success_card.zone != UATypes.Zone.HAND:
		return _fail("Raw outside-search success sample should move the selected outside card to hand.")
	if not player_success.hand.has(outside_success_uid):
		return _fail("Raw outside-search success sample should add the selected outside card to hand.")
	return _ok()

func _test_raw_raid_dynamic_bp_limit() -> Dictionary:
	var manager := _new_manager()
	var player_id := UATypes.PLAYER_ONE
	var opponent_id := UATypes.PLAYER_TWO
	var source_uid := _move_or_spawn_card_to_zone(manager, player_id, RAW_RAID_DYNAMIC_REMOVE, UATypes.Zone.FRONT_LINE)
	if source_uid == "":
		return _fail("Raw RAID dynamic-BP sample card should be available.")
	var source_card := manager.game_state.get_card(source_uid)
	if source_card == null:
		return _fail("Raw RAID dynamic-BP sample source card should exist.")
	source_card.flags["entered_via_raid"] = true
	_spawn_temp_card(manager, player_id, {
		"id": "TMP_DYNAMIC_SUPPORT_A",
		"name": "动态支援A",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-DYN-1",
		"traits": ["魔法少女"],
		"cost_energy": {"RED": 1},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 1000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	_spawn_temp_card(manager, player_id, {
		"id": "TMP_DYNAMIC_SUPPORT_B1",
		"name": "动态支援B",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-DYN-2",
		"traits": ["魔法少女"],
		"cost_energy": {"RED": 1},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 1000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.ENERGY_LINE, true)
	_spawn_temp_card(manager, player_id, {
		"id": "TMP_DYNAMIC_SUPPORT_B2",
		"name": "动态支援B",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-DYN-3",
		"traits": ["魔法少女"],
		"cost_energy": {"RED": 1},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 1000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var legal_target_uid := _spawn_temp_card(manager, opponent_id, {
		"id": "TMP_DYNAMIC_TARGET_2000",
		"name": "动态合法目标",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-DYN-4",
		"traits": [],
		"cost_energy": {"RED": 2},
		"cost_ap": 1,
		"energy_provided": {},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var illegal_target_uid := _spawn_temp_card(manager, opponent_id, {
		"id": "TMP_DYNAMIC_TARGET_3000",
		"name": "动态非法目标",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-DYN-5",
		"traits": [],
		"cost_energy": {"RED": 2},
		"cost_ap": 1,
		"energy_provided": {},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	manager.effect_resolver.resolve_trigger(source_uid, UATypes.TriggerType.ON_ENTER, manager.game_state, {"target_player_id": opponent_id})
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("Raw RAID dynamic-BP sample should request explicit enemy target selection.")
	var decision: Dictionary = manager.game_state.pending_decisions[0]
	var choice_values: Array[String] = []
	for choice_variant in decision.get("choices", []):
		choice_values.append(str((choice_variant as Dictionary).get("value", "")))
	if not choice_values.has(legal_target_uid):
		return _fail("Raw RAID dynamic-BP sample should expose the 2000-BP legal target.")
	if choice_values.has(illegal_target_uid):
		return _fail("Raw RAID dynamic-BP sample should not expose the 3000-BP target when only two other unique names exist.")
	manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(decision.get("resolution_id", "")),
		"choice": legal_target_uid,
	})
	var legal_target := manager.game_state.get_card(legal_target_uid)
	if legal_target == null or legal_target.zone != UATypes.Zone.OUTSIDE:
		return _fail("Raw RAID dynamic-BP sample should move the chosen legal target to outside.")
	return _ok()

func _test_raw_return_other_or_self_fallback() -> Dictionary:
	var variants := [RAW_RETURN_OTHER_OR_SELF, RAW_RETURN_OTHER_OR_SELF_ST]
	for card_id in variants:
		var manager_success := _new_manager()
		var player_id := UATypes.PLAYER_ONE
		var source_uid := _move_or_spawn_card_to_zone(manager_success, player_id, card_id, UATypes.Zone.FRONT_LINE)
		var other_uid := _spawn_temp_card(manager_success, player_id, {
			"id": "TMP_RETURN_OTHER_%s" % card_id,
			"name": "低费其他角色%s" % card_id,
			"card_type": "CHARACTER",
			"title_code": "TMP",
			"number": "TMP-RET-1-%s" % card_id,
			"traits": [],
			"cost_energy": {"RED": 1},
			"cost_ap": 1,
			"energy_provided": {"RED": 1},
			"bp": 1000,
			"keywords": [],
			"effects": [],
			"trigger_effects": []
		}, UATypes.Zone.FRONT_LINE, true)
		manager_success.effect_resolver.resolve_trigger(source_uid, UATypes.TriggerType.ON_ENTER, manager_success.game_state, {"target_player_id": player_id})
		if manager_success.game_state.pending_decisions.size() != 1:
			return _fail("Raw fallback sample should request primary target selection when another legal character exists for %s." % card_id)
		var success_decision: Dictionary = manager_success.game_state.pending_decisions[0]
		var success_choices: Array[String] = []
		for choice_variant in success_decision.get("choices", []):
			success_choices.append(str((choice_variant as Dictionary).get("value", "")))
		if not success_choices.has(other_uid):
			return _fail("Raw fallback sample should expose the other low-cost character for %s." % card_id)
		if success_choices.has(source_uid):
			return _fail("Raw fallback sample should not expose the source card as 'other' for %s." % card_id)
		manager_success.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
			"resolution_id": str(success_decision.get("resolution_id", "")),
			"choice": other_uid,
		})
		var source_card_success := manager_success.game_state.get_card(source_uid)
		var other_card_success := manager_success.game_state.get_card(other_uid)
		if other_card_success == null or other_card_success.zone != UATypes.Zone.HAND:
			return _fail("Raw fallback sample should return the selected other character to hand for %s." % card_id)
		if source_card_success == null or source_card_success.zone != UATypes.Zone.FRONT_LINE:
			return _fail("Raw fallback sample should keep the source card on the field when the primary branch succeeds for %s." % card_id)

		var manager_fallback := _new_manager()
		var fallback_source_uid := _move_or_spawn_card_to_zone(manager_fallback, player_id, card_id, UATypes.Zone.FRONT_LINE)
		manager_fallback.effect_resolver.resolve_trigger(fallback_source_uid, UATypes.TriggerType.ON_ENTER, manager_fallback.game_state, {"target_player_id": player_id})
		if not manager_fallback.game_state.pending_decisions.is_empty():
			return _fail("Raw fallback sample should not pause for selection when no legal 'other' target exists for %s." % card_id)
		var source_card_fallback := manager_fallback.game_state.get_card(fallback_source_uid)
		if source_card_fallback == null or source_card_fallback.zone != UATypes.Zone.HAND:
			return _fail("Raw fallback sample should return the source card to hand when the primary branch cannot complete for %s." % card_id)
	return _ok()

func _test_raw_conditional_bp_event_upgrade_sayaka() -> Dictionary:
	var player_id := UATypes.PLAYER_ONE
	var opponent_id := UATypes.PLAYER_TWO

	var manager_default := _new_manager()
	manager_default.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(_player(manager_default, player_id), 1)
	if not _ensure_red_energy(manager_default, player_id, 3):
		return _fail("Should be able to prepare 3 raw red energy cards for the conditional 093 default sample.")
	_clear_named_cards_from_field(manager_default, player_id, "美樹 さやか")
	while _count_red_energy(manager_default, player_id) < 3:
		_spawn_generic_red_energy(manager_default, player_id, "TMP_SAFE_093_DEFAULT_%d" % manager_default.game_state.cards.size())
	var source_default_uid := _move_or_spawn_card_to_zone(manager_default, player_id, RAW_EVENT_DYNAMIC_BP_SAYAKA, UATypes.Zone.HAND)
	var target_3000_uid := _spawn_temp_card(manager_default, opponent_id, {
		"id": "TMP_EVENT_093_TARGET_3000",
		"name": "093默认目标3000",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-093-1",
		"traits": [],
		"cost_energy": {"RED": 3},
		"cost_ap": 1,
		"energy_provided": {},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var target_4000_uid := _spawn_temp_card(manager_default, opponent_id, {
		"id": "TMP_EVENT_093_TARGET_4000",
		"name": "093默认目标4000",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-093-2",
		"traits": [],
		"cost_energy": {"RED": 3},
		"cost_ap": 1,
		"energy_provided": {},
		"bp": 4000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	manager_default.play_card(source_default_uid, UATypes.Zone.OUTSIDE)
	if manager_default.game_state.pending_decisions.size() != 1:
		return _fail("Raw conditional 093 default sample should request explicit target selection.")
	var default_decision: Dictionary = manager_default.game_state.pending_decisions[0]
	var default_choices: Array[String] = []
	for choice_variant in default_decision.get("choices", []):
		default_choices.append(str((choice_variant as Dictionary).get("value", "")))
	if not default_choices.has(target_3000_uid):
		return _fail("Raw conditional 093 default sample should expose the 3000-BP target.")
	if default_choices.has(target_4000_uid):
		return _fail("Raw conditional 093 default sample should not expose the 4000-BP target before upgrade conditions are met.")

	var manager_upgraded := _new_manager()
	manager_upgraded.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(_player(manager_upgraded, player_id), 1)
	if not _ensure_red_energy(manager_upgraded, player_id, 3):
		return _fail("Should be able to prepare 3 raw red energy cards for the conditional 093 upgraded sample.")
	var source_upgraded_uid := _move_or_spawn_card_to_zone(manager_upgraded, player_id, RAW_EVENT_DYNAMIC_BP_SAYAKA, UATypes.Zone.HAND)
	_spawn_temp_card(manager_upgraded, player_id, {
		"id": "TMP_EVENT_093_SAYAKA",
		"name": "美樹 さやか",
		"card_type": "CHARACTER",
		"title_code": "MMM",
		"number": "TMP-093-3",
		"traits": ["魔法少女"],
		"cost_energy": {"RED": 1},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 1500,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	_trim_life_to_count(manager_upgraded, player_id, 5)
	var upgraded_target_uid := _spawn_temp_card(manager_upgraded, opponent_id, {
		"id": "TMP_EVENT_093_TARGET_4000_UP",
		"name": "093升级目标4000",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-093-4",
		"traits": [],
		"cost_energy": {"RED": 3},
		"cost_ap": 1,
		"energy_provided": {},
		"bp": 4000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	manager_upgraded.play_card(source_upgraded_uid, UATypes.Zone.OUTSIDE)
	if manager_upgraded.game_state.pending_decisions.size() != 1:
		return _fail("Raw conditional 093 upgraded sample should request explicit target selection.")
	var upgraded_decision: Dictionary = manager_upgraded.game_state.pending_decisions[0]
	var upgraded_choices: Array[String] = []
	for choice_variant in upgraded_decision.get("choices", []):
		upgraded_choices.append(str((choice_variant as Dictionary).get("value", "")))
	if not upgraded_choices.has(upgraded_target_uid):
		return _fail("Raw conditional 093 upgraded sample should expose the 4000-BP target after Sayaka + life<=5 are met.")
	manager_upgraded.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(upgraded_decision.get("resolution_id", "")),
		"choice": upgraded_target_uid,
	})
	var upgraded_target := manager_upgraded.game_state.get_card(upgraded_target_uid)
	if upgraded_target == null or upgraded_target.zone != UATypes.Zone.OUTSIDE:
		return _fail("Raw conditional 093 upgraded sample should move the chosen 4000-BP target to outside.")
	return _ok()

func _test_raw_conditional_bp_event_upgrade_madoka() -> Dictionary:
	for card_id in [RAW_EVENT_DYNAMIC_BP_MADOKA_BT, RAW_EVENT_DYNAMIC_BP_MADOKA_ST]:
		var player_id := UATypes.PLAYER_ONE
		var opponent_id := UATypes.PLAYER_TWO
		var manager_default := _new_manager()
		manager_default.game_state.phase = UATypes.Phase.MAIN
		_fill_ap(_player(manager_default, player_id), 1)
		if not _ensure_red_energy(manager_default, player_id, 4):
			return _fail("Should be able to prepare 4 raw red energy cards for the conditional 094 default sample (%s)." % card_id)
		_clear_named_cards_from_field(manager_default, player_id, "鹿目 まどか")
		while _count_red_energy(manager_default, player_id) < 4:
			_spawn_generic_red_energy(manager_default, player_id, "TMP_SAFE_094_DEFAULT_%s_%d" % [card_id, manager_default.game_state.cards.size()])
		var source_default_uid := _move_or_spawn_card_to_zone(manager_default, player_id, card_id, UATypes.Zone.HAND)
		var default_target_4000_uid := _spawn_temp_card(manager_default, opponent_id, {
			"id": "TMP_EVENT_094_TARGET_4000_%s" % card_id,
			"name": "094默认目标4000%s" % card_id,
			"card_type": "CHARACTER",
			"title_code": "TMP",
			"number": "TMP-094-1-%s" % card_id,
			"traits": [],
			"cost_energy": {"RED": 4},
			"cost_ap": 1,
			"energy_provided": {},
			"bp": 4000,
			"keywords": [],
			"effects": [],
			"trigger_effects": []
		}, UATypes.Zone.FRONT_LINE, true)
		manager_default.play_card(source_default_uid, UATypes.Zone.OUTSIDE)
		if manager_default.game_state.pending_decisions.size() != 0:
			var default_decision: Dictionary = manager_default.game_state.pending_decisions[0]
			var default_choices: Array[String] = []
			for choice_variant in default_decision.get("choices", []):
				default_choices.append(str((choice_variant as Dictionary).get("value", "")))
			if default_choices.has(default_target_4000_uid):
				return _fail("Raw conditional 094 default sample should not expose the 4000-BP target before Madoka is on the field (%s)." % card_id)

		var manager_upgraded := _new_manager()
		manager_upgraded.game_state.phase = UATypes.Phase.MAIN
		_fill_ap(_player(manager_upgraded, player_id), 1)
		if not _ensure_red_energy(manager_upgraded, player_id, 4):
			return _fail("Should be able to prepare 4 raw red energy cards for the conditional 094 upgraded sample (%s)." % card_id)
		_clear_named_cards_from_field(manager_upgraded, player_id, "鹿目 まどか")
		while _count_red_energy(manager_upgraded, player_id) < 4:
			_spawn_generic_red_energy(manager_upgraded, player_id, "TMP_SAFE_094_UP_%s_%d" % [card_id, manager_upgraded.game_state.cards.size()])
		var source_upgraded_uid := _move_or_spawn_card_to_zone(manager_upgraded, player_id, card_id, UATypes.Zone.HAND)
		_spawn_temp_card(manager_upgraded, player_id, {
			"id": "TMP_EVENT_094_MADOKA_%s" % card_id,
			"name": "鹿目 まどか",
			"card_type": "CHARACTER",
			"title_code": "MMM",
			"number": "TMP-094-2-%s" % card_id,
			"traits": ["魔法少女"],
			"cost_energy": {"RED": 1},
			"cost_ap": 1,
			"energy_provided": {"RED": 1},
			"bp": 1500,
			"keywords": [],
			"effects": [],
			"trigger_effects": []
		}, UATypes.Zone.FRONT_LINE, true)
		var upgraded_target_uid := _spawn_temp_card(manager_upgraded, opponent_id, {
			"id": "TMP_EVENT_094_TARGET_4000_UP_%s" % card_id,
			"name": "094升级目标4000%s" % card_id,
			"card_type": "CHARACTER",
			"title_code": "TMP",
			"number": "TMP-094-3-%s" % card_id,
			"traits": [],
			"cost_energy": {"RED": 4},
			"cost_ap": 1,
			"energy_provided": {},
			"bp": 4000,
			"keywords": [],
			"effects": [],
			"trigger_effects": []
		}, UATypes.Zone.FRONT_LINE, true)
		manager_upgraded.play_card(source_upgraded_uid, UATypes.Zone.OUTSIDE)
		if manager_upgraded.game_state.pending_decisions.size() != 1:
			return _fail("Raw conditional 094 upgraded sample should request explicit target selection (%s)." % card_id)
		var upgraded_decision: Dictionary = manager_upgraded.game_state.pending_decisions[0]
		var upgraded_choices: Array[String] = []
		for choice_variant in upgraded_decision.get("choices", []):
			upgraded_choices.append(str((choice_variant as Dictionary).get("value", "")))
		if not upgraded_choices.has(upgraded_target_uid):
			return _fail("Raw conditional 094 upgraded sample should expose the 4000-BP target after Madoka is on the field (%s)." % card_id)
		manager_upgraded.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
			"resolution_id": str(upgraded_decision.get("resolution_id", "")),
			"choice": upgraded_target_uid,
		})
		var upgraded_target := manager_upgraded.game_state.get_card(upgraded_target_uid)
		if upgraded_target == null or upgraded_target.zone != UATypes.Zone.OUTSIDE:
			return _fail("Raw conditional 094 upgraded sample should move the chosen 4000-BP target to outside (%s)." % card_id)
	return _ok()

func _test_raw_preview_reward_magic_girl_branches() -> Dictionary:
	var player_id := UATypes.PLAYER_ONE

	var manager_success := _new_manager()
	manager_success.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(_player(manager_success, player_id), 2)
	_set_ap_active(_player(manager_success, player_id), 1)
	if not _ensure_red_energy(manager_success, player_id, 1):
		return _fail("Should be able to prepare 1 raw red energy card for the preview reward success sample.")
	var source_success_uid := _move_or_spawn_card_to_zone(manager_success, player_id, RAW_PREVIEW_MAGIC_GIRL_REWARD, UATypes.Zone.HAND)
	var reward_magic_uid := _spawn_temp_card(manager_success, player_id, {
		"id": "TMP_PREVIEW_REWARD_MAGIC",
		"name": "预览奖励魔法少女",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-PRE-1",
		"traits": ["魔法少女"],
		"cost_energy": {"RED": 1},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 1000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.DECK, false)
	var reward_filler_1 := _spawn_temp_card(manager_success, player_id, {
		"id": "TMP_PREVIEW_FILLER_1",
		"name": "预览填充1",
		"card_type": "EVENT",
		"title_code": "TMP",
		"number": "TMP-PRE-2",
		"traits": [],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {},
		"bp": 0,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.DECK, false)
	var reward_filler_2 := _spawn_temp_card(manager_success, player_id, {
		"id": "TMP_PREVIEW_FILLER_2",
		"name": "预览填充2",
		"card_type": "EVENT",
		"title_code": "TMP",
		"number": "TMP-PRE-3",
		"traits": [],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {},
		"bp": 0,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.DECK, false)
	var reward_filler_3 := _spawn_temp_card(manager_success, player_id, {
		"id": "TMP_PREVIEW_FILLER_3",
		"name": "预览填充3",
		"card_type": "EVENT",
		"title_code": "TMP",
		"number": "TMP-PRE-4",
		"traits": [],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {},
		"bp": 0,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.DECK, false)
	var reward_filler_4 := _spawn_temp_card(manager_success, player_id, {
		"id": "TMP_PREVIEW_FILLER_4",
		"name": "预览填充4",
		"card_type": "EVENT",
		"title_code": "TMP",
		"number": "TMP-PRE-5",
		"traits": [],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {},
		"bp": 0,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.DECK, false)
	_set_deck_top_order(manager_success, player_id, [reward_magic_uid, reward_filler_1, reward_filler_2, reward_filler_3, reward_filler_4])
	var success_player := _player(manager_success, player_id)
	manager_success.play_card(source_success_uid, UATypes.Zone.OUTSIDE)
	if manager_success.game_state.pending_decisions.size() != 1:
		return _fail("Raw preview reward success sample should first request the revealed card selection.")
	var select_decision: Dictionary = manager_success.game_state.pending_decisions[0]
	manager_success.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(select_decision.get("resolution_id", "")),
		"choice": reward_magic_uid,
	})
	if manager_success.game_state.pending_decisions.size() != 1:
		return _fail("Raw preview reward success sample should then request preview reorder.")
	var reorder_decision: Dictionary = manager_success.game_state.pending_decisions[0]
	manager_success.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(reorder_decision.get("resolution_id", "")),
		"choices": [reward_filler_1, reward_filler_2, reward_filler_3, reward_filler_4],
	})
	if not success_player.hand.has(reward_magic_uid):
		return _fail("Raw preview reward success sample should add the revealed magic-girl card to hand.")
	if success_player.ap_active_count() != 1:
		return _fail("Raw preview reward success sample should end with exactly 1 active AP after spending 1 AP and then readying 1 AP.")
	# 回到底时，最后四张应保持所选顺序。
	var deck_tail: Array[String] = []
	for i in range(max(0, success_player.deck.size() - 4), success_player.deck.size()):
		deck_tail.append(str(success_player.deck[i]))
	if deck_tail != [reward_filler_1, reward_filler_2, reward_filler_3, reward_filler_4]:
		return _fail("Raw preview reward success sample should place the remaining preview cards on the deck bottom in the chosen order.")

	var manager_skip := _new_manager()
	manager_skip.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(_player(manager_skip, player_id), 2)
	_set_ap_active(_player(manager_skip, player_id), 1)
	if not _ensure_red_energy(manager_skip, player_id, 1):
		return _fail("Should be able to prepare 1 raw red energy card for the preview reward skip sample.")
	var source_skip_uid := _move_or_spawn_card_to_zone(manager_skip, player_id, RAW_PREVIEW_MAGIC_GIRL_REWARD, UATypes.Zone.HAND)
	var skip_character_uid := _spawn_temp_card(manager_skip, player_id, {
		"id": "TMP_PREVIEW_SKIP_CHAR",
		"name": "预览普通角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-PRE-6",
		"traits": ["普通人"],
		"cost_energy": {"RED": 1},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 1000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.DECK, false)
	var skip_filler_1 := _spawn_temp_card(manager_skip, player_id, {
		"id": "TMP_PREVIEW_SKIP_FILLER_1",
		"name": "预览跳过填充1",
		"card_type": "EVENT",
		"title_code": "TMP",
		"number": "TMP-PRE-7",
		"traits": [],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {},
		"bp": 0,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.DECK, false)
	var skip_filler_2 := _spawn_temp_card(manager_skip, player_id, {
		"id": "TMP_PREVIEW_SKIP_FILLER_2",
		"name": "预览跳过填充2",
		"card_type": "EVENT",
		"title_code": "TMP",
		"number": "TMP-PRE-8",
		"traits": [],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {},
		"bp": 0,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.DECK, false)
	var skip_filler_3 := _spawn_temp_card(manager_skip, player_id, {
		"id": "TMP_PREVIEW_SKIP_FILLER_3",
		"name": "预览跳过填充3",
		"card_type": "EVENT",
		"title_code": "TMP",
		"number": "TMP-PRE-9",
		"traits": [],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {},
		"bp": 0,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.DECK, false)
	var skip_filler_4 := _spawn_temp_card(manager_skip, player_id, {
		"id": "TMP_PREVIEW_SKIP_FILLER_4",
		"name": "预览跳过填充4",
		"card_type": "EVENT",
		"title_code": "TMP",
		"number": "TMP-PRE-10",
		"traits": [],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {},
		"bp": 0,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.DECK, false)
	_set_deck_top_order(manager_skip, player_id, [skip_character_uid, skip_filler_1, skip_filler_2, skip_filler_3, skip_filler_4])
	var skip_player := _player(manager_skip, player_id)
	manager_skip.play_card(source_skip_uid, UATypes.Zone.OUTSIDE)
	if manager_skip.game_state.pending_decisions.size() != 1:
		return _fail("Raw preview reward skip sample should first request the revealed card selection.")
	var skip_select_decision: Dictionary = manager_skip.game_state.pending_decisions[0]
	manager_skip.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(skip_select_decision.get("resolution_id", "")),
		"choice": skip_character_uid,
	})
	if manager_skip.game_state.pending_decisions.size() != 1:
		return _fail("Raw preview reward skip sample should then request preview reorder.")
	var skip_reorder_decision: Dictionary = manager_skip.game_state.pending_decisions[0]
	manager_skip.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(skip_reorder_decision.get("resolution_id", "")),
		"choices": [skip_filler_1, skip_filler_2, skip_filler_3, skip_filler_4],
	})
	if skip_player.ap_active_count() != 0:
		return _fail("Raw preview reward skip sample should leave all AP rested after spending 1 AP when the revealed card is not a magic-girl card.")
	return _ok()

func _player(manager: GameManager, player_id: String) -> PlayerState:
	return manager.game_state.get_player(player_id)

func _test_raw_temporary_energy_bonus_then_self_leave() -> Dictionary:
	var manager := _new_manager()
	var player_id := UATypes.PLAYER_ONE
	manager.game_state.active_player_id = player_id
	manager.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(_player(manager, player_id), 2)
	var source_uid := _move_or_spawn_card_to_zone(manager, player_id, RAW_TEMP_ENERGY_SELF_LEAVE_BT, UATypes.Zone.ENERGY_LINE)
	if source_uid == "":
		return _fail("Raw temporary energy bonus sample card should be available.")
	var source_card = manager.game_state.get_card(source_uid)
	if source_card == null or source_card.zone != UATypes.Zone.ENERGY_LINE:
		return _fail("Raw temporary energy bonus sample should start in the energy line.")
	var snapshot_before := manager.get_snapshot()
	var energy_before := int(snapshot_before.get("players", {}).get(player_id, {}).get("available_energy", {}).get("RED", 0))
	manager.request_main_activate(source_uid)
	var snapshot_after := manager.get_snapshot()
	var energy_after := int(snapshot_after.get("players", {}).get(player_id, {}).get("available_energy", {}).get("RED", 0))
	if energy_after != energy_before + 1:
		return _fail("Raw temporary energy bonus sample should grant exactly +1 red energy for the turn.")
	manager.advance_phase()
	var moved_card = manager.game_state.get_card(source_uid)
	var player := _player(manager, player_id)
	if moved_card == null or moved_card.zone != UATypes.Zone.OUTSIDE:
		return _fail("Raw temporary energy bonus sample should move itself to outside at end of main phase.")
	if not player.outside.has(source_uid):
		return _fail("Raw temporary energy bonus sample should be recorded in outside after the delayed self-leave.")
	if manager.game_state.phase != UATypes.Phase.ATTACK:
		return _fail("Raw temporary energy bonus sample should still advance to ATTACK after resolving the delayed self-leave.")
	var st_uid := _move_or_spawn_card_to_zone(manager, player_id, RAW_TEMP_ENERGY_SELF_LEAVE_ST, UATypes.Zone.ENERGY_LINE)
	if st_uid == "":
		return _fail("Raw temporary energy bonus ST sample card should also be available.")
	return _ok()

func _test_raw_self_special_play_permission_after_leave() -> Dictionary:
	var manager := _new_manager()
	var player_id := UATypes.PLAYER_ONE
	manager.game_state.active_player_id = player_id
	manager.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(_player(manager, player_id), 3)
	if not _ensure_red_energy(manager, player_id, 4):
		return _fail("Raw self special play permission sample should be able to prepare 4 red energy.")
	var source_uid := _move_or_spawn_card_to_zone(manager, player_id, RAW_SELF_SPECIAL_PLAY_PERMISSION, UATypes.Zone.FRONT_LINE)
	if source_uid == "":
		return _fail("Raw self special play permission sample card should be available.")
	var source_card = manager.game_state.get_card(source_uid)
	if source_card == null:
		return _fail("Raw self special play permission source instance should exist.")
	source_card.flags["entered_via_raid"] = true
	var raid_base_uid := _spawn_temp_card(manager, player_id, {
		"id": "TMP_SAYAKA_RAID_BASE",
		"name": "美樹 さやか",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-SAYAKA-BASE",
		"traits": ["魔法少女"],
		"cost_energy": {},
		"cost_ap": 0,
		"energy_provided": {"RED": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	if raid_base_uid == "":
		return _fail("Raw self special play permission sample should be able to prepare a RAID base.")
	var chosen_life_uid := _ensure_life_card(manager, player_id)
	if chosen_life_uid == "":
		return _fail("Raw self special play permission sample should have a selectable life card.")
	manager.request_main_activate(source_uid)
	if manager.game_state.pending_decisions.is_empty():
		return _fail("Raw self special play permission sample should request explicit life target selection.")
	var decision: Dictionary = manager.game_state.pending_decisions[0]
	manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(decision.get("resolution_id", "")),
		"choice": chosen_life_uid,
	})
	var player := _player(manager, player_id)
	if not player.hand.has(chosen_life_uid):
		return _fail("Raw self special play permission sample should add the selected life card to hand.")
	var permission_found := false
	for modifier_variant in manager.game_state.static_modifiers:
		var modifier: Dictionary = modifier_variant
		if str(modifier.get("modifier_type", "")) != "SPECIAL_PLAY_PERMISSION":
			continue
		if str(modifier.get("granted_card_uid", "")) != source_uid:
			continue
		permission_found = true
		break
	if not permission_found:
		return _fail("Raw self special play permission sample should register a self-bound special play permission.")
	var on_field_actions := manager.rules_engine.get_card_available_actions(manager.game_state, player_id, source_uid)
	if on_field_actions.has("RAID"):
		return _fail("Raw self special play permission sample should not expose a hand RAID action while the source card is still on the field.")
	manager.zone_manager.move_card(manager.game_state, source_uid, UATypes.Zone.HAND, player_id)
	var hand_actions := manager.rules_engine.get_card_available_actions(manager.game_state, player_id, source_uid)
	if not hand_actions.has("PLAY_FRONT"):
		return _fail("Raw self special play permission sample should allow the source card to be played from hand after leaving the field.")
	if not hand_actions.has("RAID"):
		return _fail("Raw self special play permission sample should allow the source card to RAID from hand after leaving the field.")
	manager.effect_resolver.cleanup_start_turn_expirations(manager.game_state, player_id)
	var expired_actions := manager.rules_engine.get_card_available_actions(manager.game_state, player_id, source_uid)
	if expired_actions.has("RAID"):
		return _fail("Raw self special play permission sample should lose the temporary RAID permission at the next self turn start.")
	return _ok()

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

func _clear_named_cards_from_field(manager: GameManager, player_id: String, card_name: String) -> void:
	var player := _player(manager, player_id)
	if player == null:
		return
	for zone in [player.front_line, player.energy_line]:
		var to_move: Array[String] = []
		for card_uid_variant in zone:
			var card_uid := str(card_uid_variant)
			var card := manager.game_state.get_card(card_uid)
			var card_def := manager.game_state.get_card_def(card.def_id) if card != null else null
			if card_def != null and card_def.name == card_name:
				to_move.append(card_uid)
		for card_uid in to_move:
			manager.zone_manager.move_card(manager.game_state, card_uid, UATypes.Zone.OUTSIDE, player_id)

func _spawn_generic_red_energy(manager: GameManager, player_id: String, temp_id: String) -> String:
	return _spawn_temp_card(manager, player_id, {
		"id": temp_id,
		"name": "测试红能量%s" % temp_id,
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-ENERGY-%s" % temp_id,
		"traits": [],
		"cost_energy": {"RED": 1},
		"cost_ap": 1,
		"energy_provided": {"RED": 1},
		"bp": 1000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.ENERGY_LINE, false)

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
