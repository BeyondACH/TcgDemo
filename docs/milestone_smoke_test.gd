extends SceneTree

const UATypes = preload("res://core/ua_types.gd")
const GameManager = preload("res://core/game_manager.gd")
const PlayerState = preload("res://data/player_state.gd")
const CardInstance = preload("res://data/card_instance.gd")
const CardDef = preload("res://data/card_def.gd")

var _failures: Array[String] = []
var _passes: Array[String] = []

func _init() -> void:
	_run_test("Effect Queue", _test_effect_queue_consumption)
	_run_test("IR Target Cost", _test_ir_target_specs_and_costs)
	_run_test("对局初始化", _test_setup_game)
	_run_test("开局换牌与待决策", _test_opening_mulligan_flow)
	_run_test("阶段推进与换手", _test_phase_advance_and_turn_switch)
	_run_test("END 阶段 AP 不会恢复", _test_ap_does_not_refresh_in_end_phase)
	_run_test("结束阶段超手牌显式弃牌", _test_end_phase_hand_limit_discard)
	_run_test("角色出牌与移动", _test_play_and_move_character)
	_run_test("事件牌抽牌效果", _test_event_draw)
	_run_test("攻击造成伤害", _test_attack_damage)
	_run_test("攻击失败攻击方不退场", _test_failed_attacker_stays_on_field)
	_run_test("生命触发需要显式决策", _test_life_trigger_requires_decision)
	_run_test("生命触发可选跳过但伤害流程继续", _test_life_trigger_skip_keeps_damage_flow)
	_run_test("MAIN 主动技一次且可重置", _test_main_activate_once_per_turn)
	_run_test("STEP 回退与交换", _test_step_move_and_swap)
	_run_test("SNIPER 指定角色不可阻挡", _test_sniper_attack_cannot_block)
	_run_test("DAMAGE_2 造成两点伤害", _test_damage_two)
	_run_test("冲击与无效", _test_impact_and_negate_impact)
	_run_test("普通阻挡者会在自己回合开始时恢复 ACTIVE", _test_blocker_recovers_at_own_turn_start)
	_run_test("双次攻击与双次阻挡", _test_double_attack_and_double_block)
	_run_test("战斗触发", _test_battle_triggers)
	_run_test("同时触发顺序", _test_simultaneous_trigger_order)
	_run_test("直到下个自己回合开始的效果仅在来源方回合开始失效", _test_until_next_self_turn_start_expires_only_for_source_controller)
	_run_test("本回合临时关键词会在结束时清理且不残留运行时脏状态", _test_end_of_turn_temp_keyword_cleanup_leaves_no_runtime_residue)
	_run_test("本回合登场标记会在下个自己回合开始时清理", _test_entered_this_turn_flag_clears_on_next_turn_start)
	_run_test("多个结束主阶段延迟效果不会残留运行时脏状态", _test_multiple_end_main_delayed_effects_leave_no_runtime_residue)
	_run_test("RAID 显式落点选择", _test_raid_zone_choice)
	_run_test("RAID 生命触发二选一", _test_life_trigger_raid_choice)
	_run_test("生命归零胜负", _test_life_zero_victory)
	_run_test("空牌库抽牌败北", _test_deck_out_loss)
	_run_test("RAID 突进叠放", _test_raid_stack_play)
	_run_test("RAID 框内效果门控", _test_raid_inner_effect_gate)
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
	print("=== 冒烟测试结果 ===")
	print("通过: %d" % _passes.size())
	print("失败: %d" % _failures.size())
	if not _failures.is_empty():
		for failure in _failures:
			print(" - %s" % failure)

func _ok() -> Dictionary:
	return {"ok": true}

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}

func _new_manager(controller_config: Dictionary = {}) -> GameManager:
	var manager := GameManager.new()
	manager.setup_game(controller_config)
	_resolve_opening(manager)
	return manager

func _new_opening_manager() -> GameManager:
	var manager := GameManager.new()
	manager.setup_game()
	return manager

func _resolve_opening(manager: GameManager, p1_choice := "keep", p2_choice := "keep") -> void:
	manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": p1_choice})
	manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": p2_choice})

func _player(manager: GameManager, player_id: String) -> PlayerState:
	return manager.game_state.get_player(player_id)

func _find_card_in_zones(manager: GameManager, player_id: String, def_id: String, zones: Array) -> String:
	var player: PlayerState = _player(manager, player_id)
	if player == null:
		return ""
	for zone_name in zones:
		var zone_cards = player.get(zone_name)
		if zone_cards == null:
			continue
		for card_uid in zone_cards:
			var card = manager.game_state.get_card(card_uid)
			if card != null and card.def_id == def_id:
				return card_uid
	return ""

func _ensure_card_in_hand(manager: GameManager, player_id: String, def_id: String) -> String:
	var card_uid := _find_card_in_zones(manager, player_id, def_id, ["hand"])
	if card_uid != "":
		return card_uid
	card_uid = _find_card_in_zones(manager, player_id, def_id, ["deck", "life", "energy_line", "front_line", "outside", "removed"])
	if card_uid == "":
		return ""
	manager.zone_manager.move_card(manager.game_state, card_uid, UATypes.Zone.HAND, player_id)
	return card_uid

func _put_card_on_front(manager: GameManager, player_id: String, def_id: String, active := true) -> String:
	var card_uid := _ensure_card_in_hand(manager, player_id, def_id)
	if card_uid == "":
		return ""
	manager.zone_manager.move_card(manager.game_state, card_uid, UATypes.Zone.FRONT_LINE, player_id)
	var card = manager.game_state.get_card(card_uid)
	if card != null:
		card.state = UATypes.CardState.ACTIVE if active else UATypes.CardState.RESTED
	return card_uid

func _spawn_card(manager: GameManager, player_id: String, def_id: String, zone: int, active := true) -> String:
	var player: PlayerState = _player(manager, player_id)
	var card_def: CardDef = manager.game_state.get_card_def(def_id)
	if player == null or card_def == null:
		return ""
	var card := CardInstance.new()
	card.uid = "%s_custom_%s_%d" % [player_id, def_id, manager.game_state.cards.size()]
	card.def_id = def_id
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

func _register_temp_card_def(manager: GameManager, card_data: Dictionary) -> String:
	var card_def: CardDef = CardDef.new()
	card_def.from_dict(card_data)
	manager.game_state.card_defs[card_def.id] = card_def
	return card_def.id

func _spawn_temp_card(manager: GameManager, player_id: String, card_data: Dictionary, zone: int, active := true) -> String:
	var def_id := _register_temp_card_def(manager, card_data)
	return _spawn_card(manager, player_id, def_id, zone, active)

func _advance_to_turn_main(manager: GameManager, player_id: String, min_turn_number := 1) -> void:
	var safety := 32
	while safety > 0:
		if manager.game_state.active_player_id == player_id and manager.game_state.phase == UATypes.Phase.MAIN and manager.game_state.turn_number >= min_turn_number:
			return
		manager.advance_phase()
		safety -= 1

func _test_setup_game() -> Dictionary:
	var manager := _new_manager()
	var p1 := _player(manager, UATypes.PLAYER_ONE)
	var p2 := _player(manager, UATypes.PLAYER_TWO)
	if manager.game_state.turn_number != 1:
		return _fail("turn_number 应为 1")
	if manager.game_state.active_player_id != UATypes.PLAYER_ONE:
		return _fail("首个行动玩家应为 P1")
	if manager.game_state.phase != UATypes.Phase.DRAW:
		return _fail("初始化后阶段应进入 DRAW")
	if p1.hand.size() != 7 or p2.hand.size() != 7:
		return _fail("双方起手手牌都应为 7")
	if p1.life.size() != 7 or p2.life.size() != 7:
		return _fail("双方生命区都应为 7")
	if p1.deck.size() != 36 or p2.deck.size() != 36:
		return _fail("初始化后牌库应剩 36")
	if p1.ap_total() != 1 or p1.ap_active_count() != 1:
		return _fail("P1 首回合开始时 AP 应为 1/1")
	return _ok()

func _test_opening_mulligan_flow() -> Dictionary:
	var opening_manager := _new_opening_manager()
	if opening_manager.game_state.opening_complete:
		return _fail("开局换牌决策前不应标记 opening_complete")
	if opening_manager.game_state.pending_decisions.size() != 1:
		return _fail("初始化后应先出现 1 个起手换牌待决策")
	var first_decision: Dictionary = opening_manager.game_state.pending_decisions[0]
	if str(first_decision.get("type", "")) != "MULLIGAN_CHOICE":
		return _fail("第一个待决策应为起手换牌")
	if str(first_decision.get("owner_player_id", "")) != UATypes.PLAYER_ONE:
		return _fail("起手换牌应先轮到 P1")
	var phase_before := opening_manager.game_state.phase
	opening_manager.advance_phase()
	if opening_manager.game_state.phase != phase_before:
		return _fail("开局待决策存在时不应推进阶段")
	var p1 := _player(opening_manager, UATypes.PLAYER_ONE)
	var p1_life_top_expected: Array = []
	for i in range(UATypes.STARTING_LIFE):
		p1_life_top_expected.append(str(p1.deck[i]))
	opening_manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})
	if opening_manager.game_state.pending_decisions.size() != 1:
		return _fail("P1 处理后应继续等待 P2 的起手换牌决策")
	var second_decision: Dictionary = opening_manager.game_state.pending_decisions[0]
	if str(second_decision.get("owner_player_id", "")) != UATypes.PLAYER_TWO:
		return _fail("第二个起手换牌决策应轮到 P2")
	opening_manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})
	if not opening_manager.game_state.opening_complete:
		return _fail("双方处理完起手换牌后应完成开局")
	if p1.life != p1_life_top_expected:
		return _fail("不换牌时，生命区应按牌库当前顶部顺序放置 7 张")

	var mulligan_manager := _new_opening_manager()
	var mulligan_p1 := _player(mulligan_manager, UATypes.PLAYER_ONE)
	var opening_hand_before: Array = mulligan_p1.hand.duplicate()
	var redraw_expected: Array = []
	for i in range(UATypes.STARTING_HAND):
		redraw_expected.append(str(mulligan_p1.deck[i]))
	mulligan_manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "mulligan"})
	if mulligan_p1.hand != redraw_expected:
		return _fail("换牌时应先按顺序重抽新的 7 张手牌")
	for old_uid_variant in opening_hand_before:
		if mulligan_p1.hand.has(old_uid_variant):
			return _fail("换牌后的新手牌不应包含原有那 7 张牌")
	if mulligan_manager.game_state.pending_decisions.size() != 1:
		return _fail("P1 换牌后仍应继续等待 P2 决策")
	mulligan_manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})
	if mulligan_p1.life.size() != 7:
		return _fail("换牌完成后仍应放置 7 张生命牌")
	if mulligan_p1.deck.size() != 36:
		return _fail("换牌完成后牌库应剩余 36 张")
	return _ok()

func _test_phase_advance_and_turn_switch() -> Dictionary:
	var manager := _new_manager()
	manager.advance_phase()
	if manager.game_state.phase != UATypes.Phase.MOVE:
		return _fail("DRAW 后应进入 MOVE")
	manager.advance_phase()
	if manager.game_state.phase != UATypes.Phase.MAIN:
		return _fail("MOVE 后应进入 MAIN")
	manager.advance_phase()
	if manager.game_state.phase != UATypes.Phase.ATTACK:
		return _fail("MAIN 后应进入 ATTACK")
	manager.advance_phase()
	if manager.game_state.phase != UATypes.Phase.END:
		return _fail("ATTACK 后应进入 END")
	manager.advance_phase()
	var p2 := _player(manager, UATypes.PLAYER_TWO)
	if manager.game_state.active_player_id != UATypes.PLAYER_TWO:
		return _fail("结束 P1 回合后应轮到 P2")
	if manager.game_state.phase != UATypes.Phase.DRAW:
		return _fail("新回合开始后应处于 DRAW")
	if manager.game_state.turn_number != 2:
		return _fail("换手后 turn_number 应为 2")
	if p2.ap_total() != 2 or p2.ap_active_count() != 2:
		return _fail("P2 首回合开始时 AP 应为 2/2")
	if p2.hand.size() != 8:
		return _fail("P2 首回合应抽 1 张，手牌应为 8")
	return _ok()

func _test_ap_does_not_refresh_in_end_phase() -> Dictionary:
	var manager := _new_manager()
	var p1 := _player(manager, UATypes.PLAYER_ONE)
	var p2 := _player(manager, UATypes.PLAYER_TWO)
	if p1 == null or p2 == null:
		return _fail("AP 回归测试玩家初始化失败")
	if p1.ap_total() != 1 or p1.ap_active_count() != 1:
		return _fail("P1 首回合开始时 AP 应为 1/1")
	var bonus_result := manager.request_bonus_draw()
	if not bool(bonus_result.get("ok", false)):
		return _fail("DRAW 阶段额外抽 1 应可成功执行")
	if p1.ap_active_count() != 0:
		return _fail("使用额外抽 1 后，P1 活跃 AP 应为 0")
	manager.advance_phase()
	manager.advance_phase()
	manager.advance_phase()
	manager.advance_phase()
	if manager.game_state.phase != UATypes.Phase.END:
		return _fail("P1 连续推进后应进入 END")
	if p1.ap_active_count() != 0:
		return _fail("END 阶段不应恢复 P1 AP")
	manager.advance_phase()
	if manager.game_state.active_player_id != UATypes.PLAYER_TWO or manager.game_state.phase != UATypes.Phase.DRAW:
		return _fail("结束 P1 回合后应进入 P2 的 DRAW")
	if p1.ap_active_count() != 0:
		return _fail("进入对手回合时，P1 AP 不应被跨回合恢复")
	if p2.ap_total() != 2 or p2.ap_active_count() != 2:
		return _fail("P2 首回合开始时 AP 应为 2/2")
	manager.advance_phase()
	manager.advance_phase()
	manager.advance_phase()
	manager.advance_phase()
	manager.advance_phase()
	if manager.game_state.active_player_id != UATypes.PLAYER_ONE or manager.game_state.phase != UATypes.Phase.DRAW:
		return _fail("完成 P2 回合后应回到 P1 的 DRAW")
	if p1.ap_total() != 2 or p1.ap_active_count() != 2:
		return _fail("P1 应只在自己下个回合开始时恢复 AP 到 2/2")
	return _ok()

func _test_end_phase_hand_limit_discard() -> Dictionary:
	var manager := _new_manager()
	var p1 := _player(manager, UATypes.PLAYER_ONE)
	manager.game_state.phase = UATypes.Phase.END
	var outside_before := p1.outside.size()
	var removed_before := p1.removed.size()
	var extra_uids: Array[String] = []
	for i in range(3):
		var extra_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
			"id": "TMP_HAND_LIMIT_%d" % i,
			"name": "超手牌测试牌%d" % i,
			"card_type": "CHARACTER",
			"title_code": "TMP",
			"number": "TMP-HL-%d" % i,
			"traits": ["测试角色"],
			"cost_energy": {},
			"cost_ap": 1,
			"energy_provided": {"GREEN": 1},
			"bp": 2000,
			"keywords": [],
			"effects": [],
			"trigger_effects": []
		}, UATypes.Zone.HAND, true)
		if extra_uid == "":
			return _fail("超手牌测试卡创建失败")
		extra_uids.append(extra_uid)
	if p1.hand.size() != UATypes.HAND_LIMIT + 2:
		return _fail("测试前 P1 手牌应为上限加 2")
	manager.advance_phase()
	if manager.game_state.phase != UATypes.Phase.END:
		return _fail("超手牌待决策出现时应仍停留在 END")
	if manager.game_state.active_player_id != UATypes.PLAYER_ONE:
		return _fail("超手牌未处理前不应切换行动方")
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("超手牌时应进入 1 个弃牌待决策")
	var first_decision: Dictionary = manager.game_state.pending_decisions[0]
	if str(first_decision.get("type", "")) != "HAND_LIMIT_DISCARD":
		return _fail("超手牌待决策类型应为 HAND_LIMIT_DISCARD")
	manager.resolve_pending_decision("HAND_LIMIT_DISCARD", {"choice": extra_uids[0]})
	if p1.outside.size() != outside_before + 1:
		return _fail("第一次超手牌弃牌后应进入场外")
	if p1.removed.size() != removed_before:
		return _fail("超手牌显式弃牌不应进入移除区")
	if manager.game_state.active_player_id != UATypes.PLAYER_ONE or manager.game_state.phase != UATypes.Phase.END:
		return _fail("仍超手牌时不应提前结束回合")
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("仍超手牌时应继续保留下一次弃牌待决策")
	manager.resolve_pending_decision("HAND_LIMIT_DISCARD", {"choice": extra_uids[1]})
	if p1.outside.size() != outside_before + 2:
		return _fail("第二次超手牌弃牌后场外数量应再增加 1")
	if manager.game_state.active_player_id != UATypes.PLAYER_TWO:
		return _fail("弃到合法手牌数后应切换到 P2")
	if manager.game_state.phase != UATypes.Phase.DRAW:
		return _fail("弃到合法手牌数并换手后应进入 P2 的 DRAW")
	if p1.hand.size() != UATypes.HAND_LIMIT:
		return _fail("完成超手牌弃牌后，P1 手牌应回到上限")
	if not manager.game_state.pending_decisions.is_empty():
		return _fail("弃到合法手牌数后不应残留超手牌待决策")
	return _ok()

func _test_play_and_move_character() -> Dictionary:
	var manager := _new_manager()
	manager.game_state.phase = UATypes.Phase.MAIN
	var character_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_PLAY_MOVE_CHAR",
		"name": "出牌移动测试角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-PM-1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)
	if character_uid == "":
		return _fail("未找到可用于测试的临时角色牌")
	manager.play_card(character_uid, UATypes.Zone.ENERGY_LINE)
	var p1 := _player(manager, UATypes.PLAYER_ONE)
	var card = manager.game_state.get_card(character_uid)
	if p1.energy_line.size() != 1:
		return _fail("角色打到能量区后能量区数量应为 1")
	if card.zone != UATypes.Zone.ENERGY_LINE:
		return _fail("角色出牌后应位于能量区")
	if card.state != UATypes.CardState.RESTED:
		return _fail("打到场上的角色应为 RESTED")
	manager.game_state.phase = UATypes.Phase.MOVE
	manager.move_energy_to_front(character_uid)
	if p1.front_line.size() != 1:
		return _fail("从能量区移动后前线数量应为 1")
	if card.zone != UATypes.Zone.FRONT_LINE:
		return _fail("角色移动后应位于前线")
	return _ok()

func _test_event_draw() -> Dictionary:
	var manager := _new_manager()
	while manager.game_state.active_player_id != UATypes.PLAYER_TWO:
		manager.advance_phase()
	_advance_to_turn_main(manager, UATypes.PLAYER_TWO, 2)
	var p2 := _player(manager, UATypes.PLAYER_TWO)
	if manager.game_state.phase != UATypes.Phase.MAIN:
		return _fail("P2 当前应进入 MAIN")
	var energy_uid := _spawn_temp_card(manager, UATypes.PLAYER_TWO, {
		"id": "TMP_EVENT_ENERGY",
		"name": "事件测试能量角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-EVT-1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)
	var event_uid := _spawn_temp_card(manager, UATypes.PLAYER_TWO, {
		"id": "TMP_DRAW_EVENT",
		"name": "抽牌事件",
		"card_type": "EVENT",
		"title_code": "TMP",
		"number": "TMP-EVT-2",
		"traits": ["测试事件"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {},
		"bp": 0,
		"keywords": [],
		"effects": [
			{"type": "DRAW", "value": 1}
		],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)
	if energy_uid == "" or event_uid == "":
		return _fail("未找到用于测试事件的临时角色牌或事件牌")
	manager.play_card(energy_uid, UATypes.Zone.ENERGY_LINE)
	var hand_before := p2.hand.size()
	var deck_before := p2.deck.size()
	var outside_before := p2.outside.size()
	manager.play_card(event_uid, UATypes.Zone.OUTSIDE)
	if p2.hand.size() != hand_before:
		return _fail("事件牌结算后应抽 1 张，手牌净变化应为 0")
	if p2.deck.size() != deck_before - 1:
		return _fail("事件抽牌后牌库应减少 1")
	if p2.outside.size() != outside_before + 1:
		return _fail("事件牌结算后应进入场外区")
	return _ok()

func _test_attack_damage() -> Dictionary:
	var manager := _new_manager()
	var attacker_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_ATTACK_DAMAGE",
		"name": "攻击测试角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-ATK-1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 5000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	if attacker_uid == "":
		return _fail("未找到可用于测试攻击的临时角色")
	manager.game_state.phase = UATypes.Phase.ATTACK
	var p2 := _player(manager, UATypes.PLAYER_TWO)
	var life_before := p2.life.size()
	manager.battle_resolver.declare_attack(manager.game_state, attacker_uid)
	manager.resolve_attack(attacker_uid)
	var attacker = manager.game_state.get_card(attacker_uid)
	if p2.life.size() != life_before - 1:
		return _fail("未阻挡攻击应使对手生命减少 1")
	if attacker.state != UATypes.CardState.RESTED:
		return _fail("攻击后的角色应变为 RESTED")
	return _ok()

func _test_failed_attacker_stays_on_field() -> Dictionary:
	var manager := _new_manager()
	manager.game_state.phase = UATypes.Phase.ATTACK
	var attacker_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_ATTACK_FAIL_STAY",
		"name": "攻击失败测试角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-ATK-FAIL-1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 1000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var blocker_uid := _spawn_temp_card(manager, UATypes.PLAYER_TWO, {
		"id": "TMP_ATTACK_FAIL_BLOCK",
		"name": "高 BP 阻挡者",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-ATK-FAIL-2",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 5000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	if attacker_uid == "" or blocker_uid == "":
		return _fail("攻击失败不退场测试卡创建失败")
	var p1 := _player(manager, UATypes.PLAYER_ONE)
	var p2 := _player(manager, UATypes.PLAYER_TWO)
	var declared := manager.battle_resolver.declare_attack(manager.game_state, attacker_uid)
	if not bool(declared.get("ok", false)):
		return _fail("攻击失败不退场测试的攻击声明失败")
	manager.resolve_attack(attacker_uid, blocker_uid)
	var attacker = manager.game_state.get_card(attacker_uid)
	var blocker = manager.game_state.get_card(blocker_uid)
	if attacker == null or blocker == null:
		return _fail("攻击失败结算后测试卡丢失")
	if not p1.front_line.has(attacker_uid):
		return _fail("攻击失败后，攻击方应继续留在前线")
	if p1.outside.has(attacker_uid):
		return _fail("攻击失败后，攻击方不应进入场外")
	if not p2.front_line.has(blocker_uid):
		return _fail("攻击失败后，阻挡者应继续留在前线")
	if str(manager.game_state.last_battle_result.get("battle_outcome", "")) != "ATTACKER_FAILS_TO_DEFEAT":
		return _fail("攻击失败后应记录 ATTACKER_FAILS_TO_DEFEAT")
	if attacker.state != UATypes.CardState.RESTED:
		return _fail("攻击失败后，攻击方应保持 RESTED")
	return _ok()

func _test_life_trigger_requires_decision() -> Dictionary:
	var manager := _new_manager({
		UATypes.PLAYER_ONE: {"controller": "HUMAN"},
		UATypes.PLAYER_TWO: {"controller": "HUMAN"},
	})
	var p2 := _player(manager, UATypes.PLAYER_TWO)
	p2.life.clear()
	var trigger_uid := _spawn_card(manager, UATypes.PLAYER_TWO, "UA_LIFE_TRIGGER_DRAW", UATypes.Zone.LIFE, true)
	var basic_uid := _spawn_card(manager, UATypes.PLAYER_TWO, "UA_CHAR_BASIC", UATypes.Zone.LIFE, true)
	if trigger_uid == "" or basic_uid == "":
		return _fail("生命触发测试卡创建失败")
	p2.life = [trigger_uid, basic_uid]
	var hand_before := p2.hand.size()
	var deck_before := p2.deck.size()
	var outside_before := p2.outside.size()
	manager.effect_resolver.deal_damage_to_player(manager.game_state, UATypes.PLAYER_TWO, 2)
	if p2.hand.size() != hand_before:
		return _fail("生命受伤后不应自动发动抽牌效果")
	if p2.outside.size() != outside_before:
		return _fail("生命触发待决策时，生命卡不应提前进入场外")
	if manager.game_state.pending_life_triggers.size() != 1:
		return _fail("应存在 1 个待决策生命触发")
	manager.resolve_life_trigger_decision(trigger_uid, true)
	manager.acknowledge_life_reveal(basic_uid)
	if p2.hand.size() != hand_before + 1:
		return _fail("选择发动生命触发后应抽 1 张牌")
	if p2.deck.size() != deck_before - 1:
		return _fail("生命触发抽牌后牌库应减少 1")
	if p2.outside.size() != outside_before + 2:
		return _fail("生命触发结算完成后，两张受伤生命卡都应进入场外")
	if not manager.game_state.pending_life_triggers.is_empty():
		return _fail("生命触发结算完成后不应残留待决策项")
	if manager.game_state.winner_player_id != UATypes.PLAYER_ONE:
		return _fail("生命触发结算完成且生命归零后，应判定 P1 获胜")
	return _ok()

func _test_life_trigger_skip_keeps_damage_flow() -> Dictionary:
	var manager := _new_manager({
		UATypes.PLAYER_ONE: {"controller": "HUMAN"},
		UATypes.PLAYER_TWO: {"controller": "HUMAN"},
	})
	var p2 := _player(manager, UATypes.PLAYER_TWO)
	if p2 == null:
		return _fail("生命触发跳过测试玩家初始化失败")
	p2.life.clear()
	var trigger_uid := _spawn_card(manager, UATypes.PLAYER_TWO, "UA_LIFE_TRIGGER_DRAW", UATypes.Zone.LIFE, true)
	var basic_uid := _spawn_card(manager, UATypes.PLAYER_TWO, "UA_CHAR_BASIC", UATypes.Zone.LIFE, true)
	if trigger_uid == "" or basic_uid == "":
		return _fail("生命触发跳过测试卡创建失败")
	p2.life = [trigger_uid, basic_uid]
	var hand_before := p2.hand.size()
	var deck_before := p2.deck.size()
	var outside_before := p2.outside.size()
	manager.effect_resolver.deal_damage_to_player(manager.game_state, UATypes.PLAYER_TWO, 2)
	if p2.hand.size() != hand_before:
		return _fail("生命受伤后在显式决策前不应自动抽牌")
	if p2.deck.size() != deck_before:
		return _fail("生命受伤后在显式决策前不应提前消耗牌库")
	if p2.outside.size() != outside_before:
		return _fail("生命触发待决策时，生命卡不应提前进入场外")
	if manager.game_state.pending_life_triggers.size() != 1:
		return _fail("应存在 1 个待决策生命触发")
	if str(manager.game_state.pending_life_reveal.get("current_card_uid", "")) != trigger_uid:
		return _fail("生命伤害 reveal 应先定位到触发牌")
	manager.resolve_life_trigger_decision(trigger_uid, false)
	if p2.hand.size() != hand_before:
		return _fail("跳过生命触发后不应获得抽牌收益")
	if p2.deck.size() != deck_before:
		return _fail("跳过生命触发后不应消耗牌库")
	if not manager.game_state.pending_life_triggers.is_empty():
		return _fail("跳过后应移除对应的生命触发待决策")
	if str(manager.game_state.pending_life_reveal.get("current_card_uid", "")) != basic_uid:
		return _fail("跳过触发牌后，reveal 指针应推进到下一张被翻开的牌")
	manager.acknowledge_life_reveal(basic_uid)
	if p2.outside.size() != outside_before + 2:
		return _fail("生命伤害流程完成后，两张受伤生命卡都应进入场外")
	if not manager.game_state.pending_life_triggers.is_empty():
		return _fail("生命伤害流程完成后不应残留 pending_life_triggers")
	if not manager.game_state.pending_life_reveal.is_empty():
		return _fail("生命伤害流程完成后不应残留 pending_life_reveal")
	if manager.game_state.winner_player_id != UATypes.PLAYER_ONE:
		return _fail("跳过生命触发不应阻塞生命归零后的胜负结算")
	return _ok()

func _test_main_activate_once_per_turn() -> Dictionary:
	var manager := _new_manager()
	_advance_to_turn_main(manager, UATypes.PLAYER_ONE, 1)
	var main_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_MAIN_ACTIVATE",
		"name": "主动技测试角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": [
			{
				"trigger": "MAIN_ACTIVATE",
				"once_per_turn": true,
				"operations": [
					{"type": "DRAW", "value": 1}
				]
			}
		]
	}, UATypes.Zone.FRONT_LINE, true)
	if main_uid == "":
		return _fail("主动技测试卡创建失败")
	var p1 := _player(manager, UATypes.PLAYER_ONE)
	var hand_before := p1.hand.size()
	manager.request_main_activate(main_uid)
	if p1.hand.size() != hand_before + 1:
		return _fail("主动技第一次发动应抽 1 张")
	manager.request_main_activate(main_uid)
	if p1.hand.size() != hand_before + 1:
		return _fail("同回合同一主动技不应再次发动")
	_advance_to_turn_main(manager, UATypes.PLAYER_ONE, 3)
	var hand_before_second_turn := p1.hand.size()
	manager.request_main_activate(main_uid)
	if p1.hand.size() != hand_before_second_turn + 1:
		return _fail("换回合后主动技应重置可再次发动")
	return _ok()

func _run_effect_queue_and_ir_extension_checks() -> Dictionary:
	var queue_manager := _new_manager()
	_advance_to_turn_main(queue_manager, UATypes.PLAYER_ONE, 1)
	var queue_uid := _spawn_temp_card(queue_manager, UATypes.PLAYER_ONE, {
		"id": "TMP_QUEUE_EFFECT",
		"name": "Queue Effect Tester",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-Q-1",
		"traits": ["Test Role"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": [
			{
				"trigger": "MAIN_ACTIVATE",
				"once_per_turn": true,
				"steps": [
					{
						"type": "QUEUE_EFFECT",
						"queued_effect": {
							"type": "DRAW",
							"value": 1
						}
					}
				]
			}
		]
	}, UATypes.Zone.FRONT_LINE, true)
	if queue_uid == "":
		return _fail("Failed to create the queue effect test card.")
	var queue_player := _player(queue_manager, UATypes.PLAYER_ONE)
	var queue_hand_before := queue_player.hand.size()
	queue_manager.request_main_activate(queue_uid)
	if queue_player.hand.size() != queue_hand_before + 1:
		return _fail("QUEUE_EFFECT should resolve the queued draw in the same consumption pass.")
	if queue_manager.game_state.effect_queue.size() != 0:
		return _fail("effect_queue should be empty after queue consumption completes.")

	var ir_manager := _new_manager()
	_advance_to_turn_main(ir_manager, UATypes.PLAYER_ONE, 1)
	var ir_uid := _spawn_temp_card(ir_manager, UATypes.PLAYER_ONE, {
		"id": "TMP_IR_COST_TARGET",
		"name": "IR Target Cost Tester",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-IR-1",
		"traits": ["Test Role"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": [
			{
				"trigger": "MAIN_ACTIVATE",
				"once_per_turn": true,
				"costs": [
					{"type": "PAY_AP", "value": 1},
					{"type": "REST_SOURCE"}
				],
				"target_specs": [
					{
						"id": "picked_enemy",
						"scope": "CARD",
						"candidate": {
							"owner": "OPPONENT",
							"zones": ["FRONT_LINE"],
							"requirements": []
						},
						"select": {
							"min": 1,
							"max": 1,
							"mode": "MANUAL"
						},
						"store_as": "picked_enemy"
					}
				],
				"steps": [
					{"type": "MOVE_SELECTED_CARDS", "from_var": "picked_enemy", "to": "OUTSIDE"}
				]
			}
		]
	}, UATypes.Zone.FRONT_LINE, true)
	var ir_target_uid := _spawn_temp_card(ir_manager, UATypes.PLAYER_TWO, {
		"id": "TMP_IR_COST_TARGET_DEF",
		"name": "IR Target Defender",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-IR-2",
		"traits": ["Test Role"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	if ir_uid == "" or ir_target_uid == "":
		return _fail("Failed to create the IR target test cards.")
	var ir_player := _player(ir_manager, UATypes.PLAYER_ONE)
	var ir_ap_before := ir_player.ap_active_count()
	ir_manager.request_main_activate(ir_uid)
	if ir_manager.game_state.pending_decisions.size() != 1:
		return _fail("target_specs should trigger an explicit target selection.")
	var ir_decision: Dictionary = ir_manager.game_state.pending_decisions[0]
	if str(ir_decision.get("type", "")) != "ABILITY_TARGET_SELECTION":
		return _fail("target_specs should generate an ABILITY_TARGET_SELECTION decision.")
	ir_manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(ir_decision.get("resolution_id", "")),
		"choice": ir_target_uid,
	})
	var ir_card = ir_manager.game_state.get_card(ir_uid)
	var ir_target = ir_manager.game_state.get_card(ir_target_uid)
	if ir_player.ap_active_count() != ir_ap_before - 1:
		return _fail("costs[PAY_AP] should spend exactly 1 AP.")
	if ir_card == null or ir_card.state != UATypes.CardState.RESTED:
		return _fail("costs[REST_SOURCE] should rest the source card.")
	if ir_target == null or ir_target.zone != UATypes.Zone.OUTSIDE:
		return _fail("target_specs + steps should move the chosen target to outside.")

	var ir_fail_manager := _new_manager()
	_advance_to_turn_main(ir_fail_manager, UATypes.PLAYER_ONE, 1)
	var ir_fail_uid := _spawn_temp_card(ir_fail_manager, UATypes.PLAYER_ONE, {
		"id": "TMP_IR_COST_FAIL",
		"name": "IR Insufficient Cost Tester",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-IR-3",
		"traits": ["Test Role"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": [
			{
				"trigger": "MAIN_ACTIVATE",
				"once_per_turn": true,
				"costs": [
					{"type": "PAY_AP", "value": 4}
				],
				"steps": [
					{"type": "DRAW", "value": 1}
				]
			}
		]
	}, UATypes.Zone.FRONT_LINE, true)
	if ir_fail_uid == "":
		return _fail("Failed to create the insufficient-cost IR test card.")
	var ir_fail_player := _player(ir_fail_manager, UATypes.PLAYER_ONE)
	var ir_fail_hand_before := ir_fail_player.hand.size()
	ir_fail_manager.request_main_activate(ir_fail_uid)
	if ir_fail_player.hand.size() != ir_fail_hand_before:
		return _fail("No follow-up draw should resolve when the cost cannot be paid.")
	return _ok()

func _test_effect_queue_consumption() -> Dictionary:
	var result := _run_effect_queue_and_ir_extension_checks()
	if not bool(result.get("ok", false)):
		return result
	return _ok()

func _test_ir_target_specs_and_costs() -> Dictionary:
	var result := _run_effect_queue_and_ir_extension_checks()
	if not bool(result.get("ok", false)):
		return result
	return _ok()

func _test_step_move_and_swap() -> Dictionary:
	var manager := _new_manager()
	manager.game_state.phase = UATypes.Phase.MOVE
	var step_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_STEP_BACK",
		"name": "撤步角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-2",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": ["STEP"],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	if step_uid == "":
		return _fail("STEP 测试卡创建失败")
	manager.request_step_move(step_uid)
	var step_card = manager.game_state.get_card(step_uid)
	if step_card.zone != UATypes.Zone.ENERGY_LINE:
		return _fail("非满位时 STEP 应直接回到能量线")

	var swap_manager := _new_manager()
	swap_manager.game_state.phase = UATypes.Phase.MOVE
	var swap_uid := _spawn_temp_card(swap_manager, UATypes.PLAYER_ONE, {
		"id": "TMP_STEP_SWAP",
		"name": "满位撤步角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-3",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": ["STEP"],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var swap_target_uid := ""
	for i in range(4):
		var energy_uid := _spawn_temp_card(swap_manager, UATypes.PLAYER_ONE, {
			"id": "TMP_STEP_ENERGY_%d" % i,
			"name": "能量角色%d" % i,
			"card_type": "CHARACTER",
			"title_code": "TMP",
			"number": "TMP-E%d" % i,
			"traits": ["测试角色"],
			"cost_energy": {},
			"cost_ap": 1,
			"energy_provided": {"GREEN": 1},
			"bp": 2000 + i,
			"keywords": [],
			"effects": [],
			"trigger_effects": []
		}, UATypes.Zone.ENERGY_LINE, true)
		if i == 0:
			swap_target_uid = energy_uid
	if swap_uid == "" or swap_target_uid == "":
		return _fail("STEP 满位交换测试卡创建失败")
	swap_manager.request_step_move(swap_uid)
	if swap_manager.game_state.pending_decisions.size() != 1:
		return _fail("满位 STEP 应进入待选择状态")
	swap_manager.resolve_pending_decision("STEP_SWAP_CHOICE", {"source_card_uid": swap_uid, "choice": swap_target_uid})
	var swap_card = swap_manager.game_state.get_card(swap_uid)
	var target_card = swap_manager.game_state.get_card(swap_target_uid)
	if swap_card.zone != UATypes.Zone.ENERGY_LINE:
		return _fail("选择交换后 STEP 角色应进入能量线")
	if target_card.zone != UATypes.Zone.FRONT_LINE:
		return _fail("选择交换后能量位角色应被换到前线")
	return _ok()

func _test_sniper_attack_cannot_block() -> Dictionary:
	var manager := _new_manager()
	manager.game_state.phase = UATypes.Phase.ATTACK
	var attacker_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_SNIPER_ATTACKER",
		"name": "狙击角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-4",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 5000,
		"keywords": ["SNIPER"],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var target_uid := _spawn_temp_card(manager, UATypes.PLAYER_TWO, {
		"id": "TMP_SNIPER_TARGET",
		"name": "被狙击角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-5",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var blocker_uid := _spawn_temp_card(manager, UATypes.PLAYER_TWO, {
		"id": "TMP_SNIPER_BLOCKER",
		"name": "可阻挡角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-6",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	if attacker_uid == "" or target_uid == "" or blocker_uid == "":
		return _fail("狙击测试卡创建失败")
	var declared := manager.battle_resolver.declare_attack(manager.game_state, attacker_uid, {
		"target_kind": "FRONT_CHARACTER",
		"target_uid": target_uid,
	})
	if not bool(declared.get("ok", false)):
		return _fail("狙击攻击声明失败")
	if not declared.get("blockers", []).is_empty():
		return _fail("狙击攻击不应提供阻挡者")
	if not manager.rules_engine.get_available_blockers(manager.game_state, UATypes.PLAYER_TWO).is_empty():
		return _fail("狙击攻击不应允许阻挡")
	manager.resolve_attack(attacker_uid)
	var target_card = manager.game_state.get_card(target_uid)
	var blocker_card = manager.game_state.get_card(blocker_uid)
	if target_card.zone != UATypes.Zone.OUTSIDE:
		return _fail("狙击命中后目标角色应离场")
	if blocker_card.zone != UATypes.Zone.FRONT_LINE:
		return _fail("未被指定的前线角色不应受影响")
	return _ok()

func _test_damage_two() -> Dictionary:
	var manager := _new_manager()
	manager.game_state.phase = UATypes.Phase.ATTACK
	var attacker_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_DAMAGE_2",
		"name": "双伤害角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-7",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 5000,
		"keywords": ["DAMAGE_2"],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	if attacker_uid == "":
		return _fail("DAMAGE_2 测试卡创建失败")
	var p2 := _player(manager, UATypes.PLAYER_TWO)
	var life_before := p2.life.size()
	manager.battle_resolver.declare_attack(manager.game_state, attacker_uid)
	manager.resolve_attack(attacker_uid)
	if p2.life.size() != life_before - 2:
		return _fail("DAMAGE_2 应造成 2 点伤害")
	return _ok()

func _test_impact_and_negate_impact() -> Dictionary:
	var manager_impact := _new_manager()
	manager_impact.game_state.phase = UATypes.Phase.ATTACK
	var attacker_uid := _spawn_temp_card(manager_impact, UATypes.PLAYER_ONE, {
		"id": "TMP_IMPACT",
		"name": "冲击角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-8",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 5000,
		"keywords": ["SNIPER", "IMPACT", "IMPACT_PLUS_1"],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var defender_uid := _spawn_temp_card(manager_impact, UATypes.PLAYER_TWO, {
		"id": "TMP_IMPACT_DEF",
		"name": "普通防守者",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-9",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 1000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	if attacker_uid == "" or defender_uid == "":
		return _fail("冲击测试卡创建失败")
	var p2 := _player(manager_impact, UATypes.PLAYER_TWO)
	var life_before := p2.life.size()
	manager_impact.battle_resolver.declare_attack(manager_impact.game_state, attacker_uid, {
		"target_kind": "FRONT_CHARACTER",
		"target_uid": defender_uid,
	})
	manager_impact.resolve_attack(attacker_uid)
	if p2.life.size() != life_before - 2:
		return _fail("IMPACT + IMPACT_PLUS_1 应额外造成 2 点伤害")
	if manager_impact.game_state.get_card(defender_uid).zone != UATypes.Zone.OUTSIDE:
		return _fail("被击败的防守者应离场")

	var manager_negate := _new_manager()
	manager_negate.game_state.phase = UATypes.Phase.ATTACK
	var negate_attacker_uid := _spawn_temp_card(manager_negate, UATypes.PLAYER_ONE, {
		"id": "TMP_IMPACT_NEGATE",
		"name": "被无效冲击",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-10",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 5000,
		"keywords": ["SNIPER", "IMPACT", "IMPACT_PLUS_1"],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var negate_defender_uid := _spawn_temp_card(manager_negate, UATypes.PLAYER_TWO, {
		"id": "TMP_IMPACT_NEGATE_DEF",
		"name": "冲击无效者",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-11",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 1000,
		"keywords": ["NEGATE_IMPACT"],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var negate_life_before := _player(manager_negate, UATypes.PLAYER_TWO).life.size()
	manager_negate.battle_resolver.declare_attack(manager_negate.game_state, negate_attacker_uid, {
		"target_kind": "FRONT_CHARACTER",
		"target_uid": negate_defender_uid,
	})
	manager_negate.resolve_attack(negate_attacker_uid)
	if _player(manager_negate, UATypes.PLAYER_TWO).life.size() != negate_life_before:
		return _fail("NEGATE_IMPACT 应无效化冲击伤害")
	return _ok()

func _test_double_attack_and_double_block() -> Dictionary:
	var manager := _new_manager()
	manager.game_state.phase = UATypes.Phase.ATTACK
	var attacker_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_DOUBLE_ATTACK",
		"name": "双攻角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-12",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 5000,
		"keywords": ["DOUBLE_ATTACK"],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var blocker_uid := _spawn_temp_card(manager, UATypes.PLAYER_TWO, {
		"id": "TMP_DOUBLE_BLOCK",
		"name": "双挡角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-13",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 6000,
		"keywords": ["DOUBLE_BLOCK"],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	if attacker_uid == "" or blocker_uid == "":
		return _fail("双次攻击/阻挡测试卡创建失败")
	var first_attack := manager.battle_resolver.declare_attack(manager.game_state, attacker_uid)
	if not bool(first_attack.get("ok", false)):
		return _fail("第一次攻击声明失败")
	manager.resolve_attack(attacker_uid, blocker_uid)
	var attacker_card = manager.game_state.get_card(attacker_uid)
	var blocker_card = manager.game_state.get_card(blocker_uid)
	if attacker_card.state != UATypes.CardState.ACTIVE:
		return _fail("DOUBLE_ATTACK 第一次攻击后应恢复 ACTIVE")
	if blocker_card.state != UATypes.CardState.ACTIVE:
		return _fail("DOUBLE_BLOCK 第一次阻挡后应恢复 ACTIVE")
	var second_attack := manager.battle_resolver.declare_attack(manager.game_state, attacker_uid)
	if not bool(second_attack.get("ok", false)):
		return _fail("DOUBLE_ATTACK 第二次攻击应可继续")
	manager.resolve_attack(attacker_uid, blocker_uid)
	if bool(manager.battle_resolver.declare_attack(manager.game_state, attacker_uid).get("ok", false)):
		return _fail("DOUBLE_ATTACK 第三次攻击不应再允许")
	if bool(manager.rules_engine.can_block(manager.game_state, UATypes.PLAYER_TWO, blocker_uid).get("ok", false)):
		return _fail("DOUBLE_BLOCK 第二次阻挡后不应再允许第三次")
	return _ok()

func _test_blocker_recovers_at_own_turn_start() -> Dictionary:
	var manager := _new_manager()
	manager.game_state.phase = UATypes.Phase.ATTACK
	var attacker_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_NORMAL_BLOCK_ATTACKER",
		"name": "普通攻击测试角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-NB-1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var blocker_uid := _spawn_temp_card(manager, UATypes.PLAYER_TWO, {
		"id": "TMP_NORMAL_BLOCKER",
		"name": "普通阻挡测试角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-NB-2",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 5000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	if attacker_uid == "" or blocker_uid == "":
		return _fail("普通阻挡恢复测试卡创建失败")
	var declared := manager.battle_resolver.declare_attack(manager.game_state, attacker_uid)
	if not bool(declared.get("ok", false)):
		return _fail("普通阻挡恢复测试的攻击声明失败")
	manager.resolve_attack(attacker_uid, blocker_uid)
	var blocker_card = manager.game_state.get_card(blocker_uid)
	if blocker_card == null:
		return _fail("普通阻挡恢复测试的阻挡者不存在")
	if blocker_card.state != UATypes.CardState.RESTED:
		return _fail("普通阻挡后，阻挡者应转为 RESTED")
	manager.advance_phase()
	if manager.game_state.phase != UATypes.Phase.END:
		return _fail("攻击阶段后应进入 END")
	if blocker_card.state != UATypes.CardState.RESTED:
		return _fail("对手回合结束阶段不应提前恢复阻挡者")
	manager.advance_phase()
	if manager.game_state.active_player_id != UATypes.PLAYER_TWO:
		return _fail("回合结束后应切换到阻挡者控制方")
	if manager.game_state.phase != UATypes.Phase.DRAW:
		return _fail("阻挡者控制方回合开始后应处于 DRAW")
	if blocker_card.state != UATypes.CardState.ACTIVE:
		return _fail("普通阻挡者应在自己回合开始时恢复 ACTIVE")
	return _ok()

func _test_battle_triggers() -> Dictionary:
	var trigger_win_manager := _new_manager()
	var trigger_win_attacker_uid := _spawn_temp_card(trigger_win_manager, UATypes.PLAYER_ONE, {
		"id": "TMP_BATTLE_WIN",
		"name": "战斗胜利触发",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-14",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 5000,
		"keywords": [],
		"effects": [],
		"trigger_effects": [
			{"trigger": "ON_BATTLE_WIN", "operations": [{"type": "DRAW", "value": 1}]}
		]
	}, UATypes.Zone.FRONT_LINE, true)
	var trigger_win_hand_before := _player(trigger_win_manager, UATypes.PLAYER_ONE).hand.size() + _player(trigger_win_manager, UATypes.PLAYER_TWO).hand.size()
	trigger_win_manager.effect_resolver.resolve_trigger(trigger_win_attacker_uid, UATypes.TriggerType.ON_BATTLE_WIN, trigger_win_manager.game_state, {"target_player_id": UATypes.PLAYER_TWO})
	var trigger_win_hand_after := _player(trigger_win_manager, UATypes.PLAYER_ONE).hand.size() + _player(trigger_win_manager, UATypes.PLAYER_TWO).hand.size()
	if trigger_win_hand_after != trigger_win_hand_before + 1:
		return _fail("ON_BATTLE_WIN 应能触发对应效果")

	var trigger_lose_manager := _new_manager()
	var trigger_lose_attacker_uid := _spawn_temp_card(trigger_lose_manager, UATypes.PLAYER_ONE, {
		"id": "TMP_BATTLE_LOSE",
		"name": "战斗失败触发",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-16",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 5000,
		"keywords": [],
		"effects": [],
		"trigger_effects": [
			{"trigger": "ON_BATTLE_LOSE", "operations": [{"type": "DRAW", "value": 1}]}
		]
	}, UATypes.Zone.FRONT_LINE, true)
	var trigger_lose_hand_before := _player(trigger_lose_manager, UATypes.PLAYER_ONE).hand.size() + _player(trigger_lose_manager, UATypes.PLAYER_TWO).hand.size()
	trigger_lose_manager.effect_resolver.resolve_trigger(trigger_lose_attacker_uid, UATypes.TriggerType.ON_BATTLE_LOSE, trigger_lose_manager.game_state, {"target_player_id": UATypes.PLAYER_TWO})
	var trigger_lose_hand_after := _player(trigger_lose_manager, UATypes.PLAYER_ONE).hand.size() + _player(trigger_lose_manager, UATypes.PLAYER_TWO).hand.size()
	if trigger_lose_hand_after != trigger_lose_hand_before + 1:
		return _fail("ON_BATTLE_LOSE 应能触发对应效果")

	var trigger_end_manager := _new_manager()
	var trigger_end_attacker_uid := _spawn_temp_card(trigger_end_manager, UATypes.PLAYER_ONE, {
		"id": "TMP_BATTLE_END",
		"name": "战斗结束触发",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-18",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 5000,
		"keywords": [],
		"effects": [],
		"trigger_effects": [
			{"trigger": "ON_BATTLE_END", "operations": [{"type": "DRAW", "value": 1}]}
		]
	}, UATypes.Zone.FRONT_LINE, true)
	var trigger_end_hand_before := _player(trigger_end_manager, UATypes.PLAYER_ONE).hand.size() + _player(trigger_end_manager, UATypes.PLAYER_TWO).hand.size()
	trigger_end_manager.effect_resolver.resolve_trigger(trigger_end_attacker_uid, UATypes.TriggerType.ON_BATTLE_END, trigger_end_manager.game_state, {"target_player_id": UATypes.PLAYER_TWO})
	var trigger_end_hand_after := _player(trigger_end_manager, UATypes.PLAYER_ONE).hand.size() + _player(trigger_end_manager, UATypes.PLAYER_TWO).hand.size()
	if trigger_end_hand_after != trigger_end_hand_before + 1:
		return _fail("ON_BATTLE_END 应能触发对应效果")
	return _ok()

	var win_manager := _new_manager()
	win_manager.game_state.phase = UATypes.Phase.ATTACK
	var win_attacker_uid := _spawn_temp_card(win_manager, UATypes.PLAYER_ONE, {
		"id": "TMP_BATTLE_WIN",
		"name": "战斗胜利触发",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-14",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 5000,
		"keywords": ["SNIPER"],
		"effects": [],
		"trigger_effects": [
			{"trigger": "ON_BATTLE_WIN", "operations": [{"type": "DRAW", "value": 1}]}
		]
	}, UATypes.Zone.FRONT_LINE, true)
	var win_defender_uid := _spawn_temp_card(win_manager, UATypes.PLAYER_TWO, {
		"id": "TMP_BATTLE_WIN_DEF",
		"name": "战败防守者",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-15",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 1000,
		"keywords": ["SNIPER"],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var win_hand_before := _player(win_manager, UATypes.PLAYER_ONE).hand.size()
	win_manager.battle_resolver.declare_attack(win_manager.game_state, win_attacker_uid, {
		"target_kind": "FRONT_CHARACTER",
		"target_uid": win_defender_uid,
	})
	win_manager.resolve_attack(win_attacker_uid)
	if _player(win_manager, UATypes.PLAYER_ONE).hand.size() != win_hand_before + 1:
		return _fail("ON_BATTLE_WIN 应在胜利后触发")

	var lose_manager := _new_manager()
	lose_manager.game_state.phase = UATypes.Phase.ATTACK
	var lose_attacker_uid := _spawn_temp_card(lose_manager, UATypes.PLAYER_ONE, {
		"id": "TMP_BATTLE_LOSE",
		"name": "战斗失败触发",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-16",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 1000,
		"keywords": [],
		"effects": [],
		"trigger_effects": [
			{"trigger": "ON_BATTLE_LOSE", "operations": [{"type": "DRAW", "value": 1}]}
		]
	}, UATypes.Zone.FRONT_LINE, true)
	var lose_defender_uid := _spawn_temp_card(lose_manager, UATypes.PLAYER_TWO, {
		"id": "TMP_BATTLE_LOSE_DEF",
		"name": "战胜防守者",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-17",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 5000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var lose_hand_before := _player(lose_manager, UATypes.PLAYER_ONE).hand.size()
	lose_manager.battle_resolver.declare_attack(lose_manager.game_state, lose_attacker_uid, {
		"target_kind": "FRONT_CHARACTER",
		"target_uid": lose_defender_uid,
	})
	lose_manager.resolve_attack(lose_attacker_uid)
	if _player(lose_manager, UATypes.PLAYER_ONE).hand.size() != lose_hand_before + 1:
		return _fail("ON_BATTLE_LOSE 应在失败后触发")

	var end_manager := _new_manager()
	end_manager.game_state.phase = UATypes.Phase.ATTACK
	var end_attacker_uid := _spawn_temp_card(end_manager, UATypes.PLAYER_ONE, {
		"id": "TMP_BATTLE_END",
		"name": "战斗结束触发",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-18",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 5000,
		"keywords": [],
		"effects": [],
		"trigger_effects": [
			{"trigger": "ON_BATTLE_END", "operations": [{"type": "DRAW", "value": 1}]}
		]
	}, UATypes.Zone.FRONT_LINE, true)
	var end_hand_before := _player(end_manager, UATypes.PLAYER_ONE).hand.size()
	end_manager.battle_resolver.declare_attack(end_manager.game_state, end_attacker_uid)
	end_manager.resolve_attack(end_attacker_uid)
	if _player(end_manager, UATypes.PLAYER_ONE).hand.size() != end_hand_before + 1:
		return _fail("ON_BATTLE_END 应在战斗结束时触发")
	return _ok()

func _test_raid_zone_choice() -> Dictionary:
	var front_manager := _new_manager()
	front_manager.game_state.phase = UATypes.Phase.MAIN
	var front_target_uid := _spawn_temp_card(front_manager, UATypes.PLAYER_ONE, {
		"id": "TMP_RAID_TARGET",
		"name": "突进目标",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-19",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.ENERGY_LINE, true)
	var front_raid_uid := _spawn_temp_card(front_manager, UATypes.PLAYER_ONE, {
		"id": "TMP_RAID_CARD",
		"name": "突进卡",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-20",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 5000,
		"keywords": ["RAID"],
		"effects": [],
		"trigger_effects": [],
		"special_play_rule": {
			"type": "RAID",
			"raid_target_name": "突进目标",
			"allow_from_hand": true,
			"require_full_energy": true
		}
	}, UATypes.Zone.HAND, true)
	if front_target_uid == "" or front_raid_uid == "":
		return _fail("RAID 显式选择测试卡创建失败")
	front_manager.play_card(front_raid_uid, UATypes.Zone.ENERGY_LINE, {"raid_target_uid": front_target_uid})
	if front_manager.game_state.pending_decisions.size() != 1:
		return _fail("RAID 目标在能量线时应进入待决策")
	front_manager.resolve_pending_decision("RAID_ZONE_CHOICE", {
		"source_card_uid": front_raid_uid,
		"choice": UATypes.Zone.FRONT_LINE,
	})
	var front_raid_card = front_manager.game_state.get_card(front_raid_uid)
	if front_raid_card.zone != UATypes.Zone.FRONT_LINE:
		return _fail("RAID 选择前线时应进入前线")
	if not front_raid_card.stacked_under.has(front_target_uid):
		return _fail("RAID 应保留叠放关系")

	var energy_manager := _new_manager()
	energy_manager.game_state.phase = UATypes.Phase.MAIN
	var energy_target_uid := _spawn_temp_card(energy_manager, UATypes.PLAYER_ONE, {
		"id": "TMP_RAID_TARGET_2",
		"name": "突进目标二",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-21",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.ENERGY_LINE, true)
	var energy_raid_uid := _spawn_temp_card(energy_manager, UATypes.PLAYER_ONE, {
		"id": "TMP_RAID_CARD_2",
		"name": "突进卡二",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-22",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 5000,
		"keywords": ["RAID"],
		"effects": [],
		"trigger_effects": [],
		"special_play_rule": {
			"type": "RAID",
			"raid_target_name": "突进目标二",
			"allow_from_hand": true,
			"require_full_energy": true
		}
	}, UATypes.Zone.HAND, true)
	energy_manager.play_card(energy_raid_uid, UATypes.Zone.ENERGY_LINE, {"raid_target_uid": energy_target_uid})
	if energy_manager.game_state.pending_decisions.size() != 1:
		return _fail("RAID 能量线目标应进入待决策")
	energy_manager.resolve_pending_decision("RAID_ZONE_CHOICE", {
		"source_card_uid": energy_raid_uid,
		"choice": UATypes.Zone.ENERGY_LINE,
	})
	var energy_raid_card = energy_manager.game_state.get_card(energy_raid_uid)
	if energy_raid_card.zone != UATypes.Zone.ENERGY_LINE:
		return _fail("RAID 选择能量线时应继续留在能量线")
	return _ok()

func _test_life_trigger_raid_choice() -> Dictionary:
	var hand_manager := _new_manager()
	var hand_player := _player(hand_manager, UATypes.PLAYER_TWO)
	hand_player.life.clear()
	var hand_target_uid := _spawn_temp_card(hand_manager, UATypes.PLAYER_TWO, {
		"id": "TMP_LIFE_RAID_TARGET",
		"name": "生命触发RAID目标",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-LR-1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var hand_raid_uid := _spawn_temp_card(hand_manager, UATypes.PLAYER_TWO, {
		"id": "TMP_LIFE_RAID_CARD",
		"name": "生命触发RAID牌",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-LR-2",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 5000,
		"keywords": ["RAID"],
		"effects": [],
		"trigger_effects": [
			{
				"trigger": "ON_LIFE_TRIGGER",
				"effect_box": "OUTER",
				"text": "このカードを手札に加えるか、必要エナジーを満たしている場合、レイドさせる。",
				"steps": [{"type": "LIFE_TRIGGER_RAID_CHOICE"}]
			}
		],
		"special_play_rule": {
			"type": "RAID",
			"raid_target_name": "生命触发RAID目标",
			"allow_from_hand": true,
			"require_full_energy": true,
			"life_trigger_only": true
		}
	}, UATypes.Zone.LIFE, true)
	hand_player.life = [hand_raid_uid]
	hand_manager.effect_resolver.deal_damage_to_player(hand_manager.game_state, UATypes.PLAYER_TWO, 1)
	hand_manager.resolve_life_trigger_decision(hand_raid_uid, true)
	if hand_manager.game_state.pending_decisions.is_empty():
		return _fail("生命触发RAID应进入二选一待决策")
	var hand_decision: Dictionary = hand_manager.game_state.pending_decisions[0]
	if str(hand_decision.get("type", "")) != "LIFE_TRIGGER_RAID_CHOICE":
		return _fail("生命触发RAID待决策类型错误")
	hand_manager.resolve_pending_decision("LIFE_TRIGGER_RAID_CHOICE", {"source_card_uid": hand_raid_uid, "choice": "ADD_TO_HAND"})
	var hand_raid_card = hand_manager.game_state.get_card(hand_raid_uid)
	if hand_raid_card == null or hand_raid_card.zone != UATypes.Zone.HAND:
		return _fail("选择加入手牌后，牌应进入手牌")
	if not hand_player.hand.has(hand_raid_uid):
		return _fail("选择加入手牌后，玩家手牌中应包含该牌")

	var raid_manager := _new_manager()
	var raid_player := _player(raid_manager, UATypes.PLAYER_TWO)
	raid_player.life.clear()
	raid_player.ap_area = [
		{"index": 0, "active": true},
		{"index": 1, "active": true},
		{"index": 2, "active": true}
	]
	var raid_target_uid := _spawn_temp_card(raid_manager, UATypes.PLAYER_TWO, {
		"id": "TMP_LIFE_RAID_TARGET_2",
		"name": "生命触发RAID目标二",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-LR-3",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var raid_life_uid := _spawn_temp_card(raid_manager, UATypes.PLAYER_TWO, {
		"id": "TMP_LIFE_RAID_CARD_2",
		"name": "生命触发RAID牌二",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-LR-4",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 5000,
		"keywords": ["RAID"],
		"effects": [],
		"trigger_effects": [
			{
				"trigger": "ON_LIFE_TRIGGER",
				"effect_box": "OUTER",
				"text": "このカードを手札に加えるか、必要エナジーを満たしている場合、レイドさせる。",
				"steps": [{"type": "LIFE_TRIGGER_RAID_CHOICE"}]
			}
		],
		"special_play_rule": {
			"type": "RAID",
			"raid_target_name": "生命触发RAID目标二",
			"allow_from_hand": true,
			"require_full_energy": true,
			"life_trigger_only": true
		}
	}, UATypes.Zone.LIFE, true)
	raid_player.life = [raid_life_uid]
	raid_manager.effect_resolver.deal_damage_to_player(raid_manager.game_state, UATypes.PLAYER_TWO, 1)
	raid_manager.resolve_life_trigger_decision(raid_life_uid, true)
	raid_manager.resolve_pending_decision("LIFE_TRIGGER_RAID_CHOICE", {"source_card_uid": raid_life_uid, "choice": "RAID_NOW"})
	if raid_manager.game_state.pending_decisions.is_empty():
		return _fail("选择立即RAID后，应进入RAID目标选择")
	raid_manager.resolve_pending_decision("LIFE_TRIGGER_RAID_TARGET", {"source_card_uid": raid_life_uid, "choice": raid_target_uid})
	var raid_card = raid_manager.game_state.get_card(raid_life_uid)
	if raid_card == null or raid_card.zone != UATypes.Zone.FRONT_LINE:
		return _fail("选择立即RAID后，牌应叠放到前线")
	if not bool(raid_card.flags.get("entered_via_raid", false)):
		return _fail("生命触发直接RAID后应标记 entered_via_raid")
	if not raid_card.stacked_under.has(raid_target_uid):
		return _fail("生命触发直接RAID后应保留叠放关系")
	return _ok()

func _test_life_zero_victory() -> Dictionary:
	var manager := _new_manager()
	var p2 := _player(manager, UATypes.PLAYER_TWO)
	p2.life.clear()
	for i in range(7):
		var life_uid := _spawn_temp_card(manager, UATypes.PLAYER_TWO, {
			"id": "TMP_LIFE_ZERO_%d" % i,
			"name": "无触发生命牌%d" % i,
			"card_type": "CHARACTER",
			"title_code": "TMP",
			"number": "TMP-LIFE-%d" % i,
			"traits": ["测试角色"],
			"cost_energy": {},
			"cost_ap": 1,
			"energy_provided": {"GREEN": 1},
			"bp": 1000,
			"keywords": [],
			"effects": [],
			"trigger_effects": []
		}, UATypes.Zone.LIFE, true)
		if life_uid == "":
			return _fail("生命归零测试卡创建失败")
	manager.effect_resolver.deal_damage_to_player(manager.game_state, UATypes.PLAYER_TWO, 7)
	while not manager.game_state.pending_life_reveal.is_empty():
		var current_card_uid := str(manager.game_state.pending_life_reveal.get("current_card_uid", ""))
		if current_card_uid == "":
			break
		manager.acknowledge_life_reveal(current_card_uid)
	if manager.game_state.winner_player_id != UATypes.PLAYER_ONE:
		return _fail("P2 生命归零后应判定 P1 获胜")
	return _ok()

func _test_deck_out_loss() -> Dictionary:
	var manager := _new_manager()
	var p1 := _player(manager, UATypes.PLAYER_ONE)
	p1.deck.clear()
	p1.turn_count = 1
	manager.game_state.active_player_id = UATypes.PLAYER_ONE
	manager.game_state.phase = UATypes.Phase.START
	manager.turn_manager.begin_turn(manager.game_state)
	if manager.game_state.winner_player_id != UATypes.PLAYER_TWO:
		return _fail("P1 抽空牌库失败后应判定 P2 获胜")
	return _ok()

func _test_until_next_self_turn_start_expires_only_for_source_controller() -> Dictionary:
	var manager := _new_manager()
	manager.game_state.phase = UATypes.Phase.MAIN
	var source_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_UNTIL_NEXT_SELF_TURN_SOURCE",
		"name": "来源方临时效果",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-UNTIL-SELF-1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var locked_uid := _spawn_temp_card(manager, UATypes.PLAYER_TWO, {
		"id": "TMP_UNTIL_NEXT_SELF_TURN_TARGET",
		"name": "对手受限角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-UNTIL-SELF-2",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	if source_uid == "" or locked_uid == "":
		return _fail("直到下个自己回合开始测试卡创建失败")
	var locked_card = manager.game_state.get_card(locked_uid)
	if locked_card == null:
		return _fail("直到下个自己回合开始测试目标实例不存在")
	locked_card.flags["temp_keywords"] = ["CANNOT_ATTACK"]
	locked_card.flags["temp_keyword_counts"] = {"CANNOT_ATTACK": 1}
	manager.game_state.static_modifiers.append({
		"id": "tmp_until_next_self_turn_keyword",
		"source_card_uid": source_uid,
		"owner_player_id": UATypes.PLAYER_ONE,
		"modifier_type": "TEMP_KEYWORD",
		"target_uid": locked_uid,
		"keyword": "CANNOT_ATTACK",
		"expires": "UNTIL_NEXT_SELF_TURN_START",
	})
	manager.advance_phase()
	manager.advance_phase()
	manager.advance_phase()
	locked_card = manager.game_state.get_card(locked_uid)
	if locked_card == null or not (locked_card.flags.get("temp_keywords", []) as Array).has("CANNOT_ATTACK"):
		return _fail("直到下个自己回合开始的临时效果不应在对手回合开始前提前失效")
	manager.advance_phase()
	manager.advance_phase()
	var attack_check := manager.rules_engine.can_attack(manager.game_state, UATypes.PLAYER_TWO, locked_uid)
	if bool(attack_check.get("ok", false)):
		return _fail("对手回合攻击阶段开始时，受限角色仍应保持不能攻击")
	manager.effect_resolver.cleanup_start_turn_expirations(manager.game_state, UATypes.PLAYER_ONE)
	locked_card = manager.game_state.get_card(locked_uid)
	if locked_card == null:
		return _fail("直到下个自己回合开始测试目标不应离场")
	if (locked_card.flags.get("temp_keywords", []) as Array).has("CANNOT_ATTACK"):
		return _fail("来源方自己的下个回合开始后，应移除临时不能攻击关键词")
	if not manager.game_state.static_modifiers.is_empty():
		return _fail("来源方自己的下个回合开始后，不应残留过期的 TEMP_KEYWORD 修饰")
	return _ok()

func _test_end_of_turn_temp_keyword_cleanup_leaves_no_runtime_residue() -> Dictionary:
	var manager := _new_manager()
	manager.game_state.phase = UATypes.Phase.MAIN
	var source_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_END_OF_TURN_IMPACT_SOURCE",
		"name": "回合结束临时冲击来源",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-END-IMPACT-1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	if source_uid == "":
		return _fail("结束回合临时关键词测试卡创建失败")
	manager.effect_resolver.resolve_effect(manager.game_state, source_uid, {
		"steps": [
			{
				"type": "ADD_TEMP_KEYWORD",
				"target_uid": "SOURCE_CARD",
				"keyword": "IMPACT",
				"expires": "END_OF_TURN",
			}
		]
	}, {"source_player_id": UATypes.PLAYER_ONE})
	var source_card = manager.game_state.get_card(source_uid)
	if source_card == null:
		return _fail("结束回合临时关键词测试来源实例不存在")
	if not (source_card.flags.get("temp_keywords", []) as Array).has("IMPACT"):
		return _fail("ADD_TEMP_KEYWORD 应立即把 IMPACT 加到来源卡的运行时关键词中")
	if manager.game_state.static_modifiers.is_empty():
		return _fail("ADD_TEMP_KEYWORD 应注册一个 END_OF_TURN 的 TEMP_KEYWORD 修饰")
	if not manager.game_state.pending_decisions.is_empty() or not manager.game_state.effect_queue.is_empty() or not manager.game_state.battle_context.is_empty():
		return _fail("临时关键词即时结算后不应残留 pending_decisions、effect_queue 或 battle_context")
	manager.effect_resolver.cleanup_turn_expirations(manager.game_state, UATypes.PLAYER_ONE)
	source_card = manager.game_state.get_card(source_uid)
	if source_card == null:
		return _fail("结束回合临时关键词测试来源卡不应离场")
	if (source_card.flags.get("temp_keywords", []) as Array).has("IMPACT"):
		return _fail("END_OF_TURN 清理后应移除临时 IMPACT 关键词")
	if not manager.game_state.static_modifiers.is_empty():
		return _fail("END_OF_TURN 清理后不应残留 TEMP_KEYWORD 修饰")
	if not manager.game_state.pending_decisions.is_empty() or not manager.game_state.effect_queue.is_empty() or not manager.game_state.battle_context.is_empty():
		return _fail("END_OF_TURN 临时关键词清理后不应残留运行时脏状态")
	return _ok()

func _test_entered_this_turn_flag_clears_on_next_turn_start() -> Dictionary:
	var manager := _new_manager()
	var source_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_ENTERED_THIS_TURN",
		"name": "本回合登场标记测试",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-ENTERED-1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var source_card = manager.game_state.get_card(source_uid)
	if source_card == null:
		return _fail("entered_this_turn 测试来源卡创建失败")
	source_card.flags["entered_this_turn"] = true
	manager.zone_manager.reset_turn_flags(manager.game_state, UATypes.PLAYER_ONE)
	source_card = manager.game_state.get_card(source_uid)
	if source_card == null:
		return _fail("entered_this_turn 测试来源卡不应离场")
	if bool(source_card.flags.get("entered_this_turn", false)):
		return _fail("entered_this_turn 标记应在来源方下个回合开始时被清理")
	return _ok()

func _test_multiple_end_main_delayed_effects_leave_no_runtime_residue() -> Dictionary:
	var manager := _new_manager()
	manager.game_state.phase = UATypes.Phase.MAIN
	var first_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_DELAYED_LEAVE_FIRST",
		"name": "结束主阶段自离场一",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-DELAYED-1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.ENERGY_LINE, false)
	var second_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_DELAYED_LEAVE_SECOND",
		"name": "结束主阶段自离场二",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-DELAYED-2",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.ENERGY_LINE, false)
	if first_uid == "" or second_uid == "":
		return _fail("多个结束主阶段延迟效果测试卡创建失败")
	manager.game_state.delayed_effects.append({
		"id": "tmp_end_main_delayed_1",
		"source_card_uid": first_uid,
		"owner_player_id": UATypes.PLAYER_ONE,
		"event": "ON_END_MAIN_PHASE",
		"filters": [],
		"steps": [{"type": "MOVE_CARD", "target": "SOURCE_CARD", "to_zone": "OUTSIDE"}],
		"once": true,
		"expires": "",
	})
	manager.game_state.delayed_effects.append({
		"id": "tmp_end_main_delayed_2",
		"source_card_uid": second_uid,
		"owner_player_id": UATypes.PLAYER_ONE,
		"event": "ON_END_MAIN_PHASE",
		"filters": [],
		"steps": [{"type": "MOVE_CARD", "target": "SOURCE_CARD", "to_zone": "OUTSIDE"}],
		"once": true,
		"expires": "",
	})
	manager.advance_phase()
	var first_card = manager.game_state.get_card(first_uid)
	var second_card = manager.game_state.get_card(second_uid)
	if first_card == null or first_card.zone != UATypes.Zone.OUTSIDE:
		return _fail("第一个结束主阶段延迟效果应在进入 ATTACK 前把来源卡移到场外")
	if second_card == null or second_card.zone != UATypes.Zone.OUTSIDE:
		return _fail("第二个结束主阶段延迟效果应在进入 ATTACK 前把来源卡移到场外")
	if manager.game_state.phase != UATypes.Phase.ATTACK:
		return _fail("多个结束主阶段延迟效果结算后仍应推进到 ATTACK")
	if not manager.game_state.delayed_effects.is_empty():
		return _fail("多个结束主阶段延迟效果结算后不应残留 delayed_effects")
	if not manager.game_state.pending_decisions.is_empty():
		return _fail("多个结束主阶段延迟效果结算后不应残留 pending_decisions")
	if not manager.game_state.effect_queue.is_empty():
		return _fail("多个结束主阶段延迟效果结算后不应残留 effect_queue")
	if not manager.game_state.battle_context.is_empty():
		return _fail("多个结束主阶段延迟效果结算后不应产生 battle_context 脏状态")
	manager.advance_phase()
	manager.advance_phase()
	if manager.game_state.phase != UATypes.Phase.DRAW or manager.game_state.active_player_id != UATypes.PLAYER_TWO:
		return _fail("多个结束主阶段延迟效果结算后，回合仍应能稳定推进到下回合 DRAW")
	return _ok()

func _test_raid_stack_play() -> Dictionary:
	var manager := _new_manager()
	manager.game_state.phase = UATypes.Phase.MAIN
	var p1 := _player(manager, UATypes.PLAYER_ONE)
	p1.ap_area = [
		{"index": 0, "active": true},
		{"index": 1, "active": true},
		{"index": 2, "active": true}
	]
	for i in range(6):
		_spawn_card(manager, UATypes.PLAYER_ONE, "UA_MMM_BASE_MADOKA", UATypes.Zone.ENERGY_LINE, true)
	var base_uid := _spawn_card(manager, UATypes.PLAYER_ONE, "UA_MMM_BASE_MADOKA", UATypes.Zone.ENERGY_LINE, false)
	var raid_uid := _spawn_card(manager, UATypes.PLAYER_ONE, "UA31BT_MMM_1_002", UATypes.Zone.HAND, true)
	if base_uid == "" or raid_uid == "":
		return _fail("RAID 测试卡牌创建失败")
	manager.play_card(raid_uid, UATypes.Zone.ENERGY_LINE, {"raid_target_uid": base_uid})
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("RAID 突进叠放测试应进入显式落点待决策")
	manager.resolve_pending_decision("RAID_ZONE_CHOICE", {
		"source_card_uid": raid_uid,
		"raid_target_uid": base_uid,
		"choice": UATypes.Zone.ENERGY_LINE,
	})
	var raid_card = manager.game_state.get_card(raid_uid)
	if raid_card == null:
		return _fail("RAID 后未找到上层卡")
	if raid_card.zone != UATypes.Zone.ENERGY_LINE:
		return _fail("选择留在能量线时，RAID 后上层卡应仍在能量线")
	if raid_card.state != UATypes.CardState.ACTIVE:
		return _fail("突进到底层休息角色上时，上层卡应转为 ACTIVE")
	if not raid_card.stacked_under.has(base_uid):
		return _fail("RAID 后应保留 stacked_under")
	if p1.energy_line.count(raid_uid) != 1:
		return _fail("选择留在能量线时，上层卡应在能量线")
	if p1.front_line.has(raid_uid):
		return _fail("选择留在能量线时，上层卡不应进入前线")
	if p1.energy_line.has(base_uid):
		return _fail("RAID 后下层卡不应继续单独留在能量线")
	var base_card = manager.game_state.get_card(base_uid)
	if base_card == null:
		return _fail("RAID 后未找到底牌实例")
	if not bool(base_card.flags.get("is_stacked_under", false)):
		return _fail("RAID 后底牌应显示标记为被叠放")
	if str(base_card.flags.get("stack_parent_uid", "")) != raid_uid:
		return _fail("RAID 后底牌应记录上层卡 UID")
	manager.zone_manager.move_card(manager.game_state, raid_uid, UATypes.Zone.OUTSIDE, UATypes.PLAYER_ONE)
	if not p1.outside.has(raid_uid):
		return _fail("RAID 上层离场后应进入场外")
	if not p1.outside.has(base_uid):
		return _fail("RAID 下层卡在上层离场后应返回场外")
	if bool(base_card.flags.get("is_stacked_under", false)):
		return _fail("RAID 底牌离场后不应继续保留被叠放标记")
	if str(base_card.flags.get("stack_parent_uid", "")) != "":
		return _fail("RAID 底牌离场后应清空上层关联")

	var manager_front := _new_manager()
	manager_front.game_state.phase = UATypes.Phase.MAIN
	var p1_front := _player(manager_front, UATypes.PLAYER_ONE)
	p1_front.ap_area = [
		{"index": 0, "active": true},
		{"index": 1, "active": true},
		{"index": 2, "active": true}
	]
	for i in range(6):
		_spawn_card(manager_front, UATypes.PLAYER_ONE, "UA_MMM_BASE_MADOKA", UATypes.Zone.ENERGY_LINE, true)
	var base_uid_front := _spawn_card(manager_front, UATypes.PLAYER_ONE, "UA_MMM_BASE_MADOKA", UATypes.Zone.ENERGY_LINE, false)
	var raid_uid_front := _spawn_card(manager_front, UATypes.PLAYER_ONE, "UA31BT_MMM_1_002", UATypes.Zone.HAND, true)
	manager_front.play_card(raid_uid_front, UATypes.Zone.FRONT_LINE, {"raid_target_uid": base_uid_front})
	if manager_front.game_state.pending_decisions.size() != 1:
		return _fail("选择转前线时，RAID 应进入显式落点待决策")
	manager_front.resolve_pending_decision("RAID_ZONE_CHOICE", {
		"source_card_uid": raid_uid_front,
		"raid_target_uid": base_uid_front,
		"choice": UATypes.Zone.FRONT_LINE,
	})
	var raid_card_front = manager_front.game_state.get_card(raid_uid_front)
	if raid_card_front == null:
		return _fail("选择转前线时，RAID 后未找到上层卡")
	if raid_card_front.zone != UATypes.Zone.FRONT_LINE:
		return _fail("选择转前线时，RAID 后上层卡应进入前线")
	if p1_front.front_line.count(raid_uid_front) != 1:
		return _fail("选择转前线时，上层卡应在前线")
	if p1_front.energy_line.has(raid_uid_front):
		return _fail("选择转前线时，上层卡不应继续留在能量线")
	return _ok()

func _test_raid_inner_effect_gate() -> Dictionary:
	var manager_normal := _new_manager()
	manager_normal.game_state.phase = UATypes.Phase.MAIN
	var p1_normal := _player(manager_normal, UATypes.PLAYER_ONE)
	p1_normal.ap_area = [
		{"index": 0, "active": true},
		{"index": 1, "active": true},
		{"index": 2, "active": true}
	]
	for i in range(7):
		_spawn_card(manager_normal, UATypes.PLAYER_ONE, "UA_MMM_BASE_MADOKA", UATypes.Zone.ENERGY_LINE, true)
	var outside_uid := _spawn_card(manager_normal, UATypes.PLAYER_ONE, "UA_CHAR_BASIC", UATypes.Zone.OUTSIDE, true)
	var raid_normal_uid := _spawn_card(manager_normal, UATypes.PLAYER_ONE, "UA31BT_MMM_1_002", UATypes.Zone.HAND, true)
	if outside_uid == "" or raid_normal_uid == "":
		return _fail("普通登场门控测试卡牌创建失败")
	manager_normal.play_card(raid_normal_uid, UATypes.Zone.FRONT_LINE)
	var normal_card = manager_normal.game_state.get_card(raid_normal_uid)
	if normal_card == null:
		return _fail("普通登场后未找到 RAID 卡")
	if bool(normal_card.flags.get("entered_via_raid", false)):
		return _fail("普通登场不应标记为 entered_via_raid")
	if p1_normal.outside.has(outside_uid) == false:
		return _fail("普通登场时，框内效果不应把场外角色移除")
	if p1_normal.removed.has(outside_uid):
		return _fail("普通登场时，框内效果不应生效到移除区")

	var manager_raid := _new_manager()
	manager_raid.game_state.phase = UATypes.Phase.MAIN
	var p1_raid := _player(manager_raid, UATypes.PLAYER_ONE)
	p1_raid.ap_area = [
		{"index": 0, "active": true},
		{"index": 1, "active": true},
		{"index": 2, "active": true}
	]
	for i in range(7):
		_spawn_card(manager_raid, UATypes.PLAYER_ONE, "UA_MMM_BASE_MADOKA", UATypes.Zone.ENERGY_LINE, true)
	var base_uid := _spawn_card(manager_raid, UATypes.PLAYER_ONE, "UA_MMM_BASE_MADOKA", UATypes.Zone.FRONT_LINE, true)
	var outside_uid_raid := _spawn_card(manager_raid, UATypes.PLAYER_ONE, "UA_CHAR_BASIC", UATypes.Zone.OUTSIDE, true)
	var raid_uid := _spawn_card(manager_raid, UATypes.PLAYER_ONE, "UA31BT_MMM_1_002", UATypes.Zone.HAND, true)
	if base_uid == "" or outside_uid_raid == "" or raid_uid == "":
		return _fail("突进门控测试卡牌创建失败")
	manager_raid.play_card(raid_uid, UATypes.Zone.FRONT_LINE, {"raid_target_uid": base_uid})
	var raid_card = manager_raid.game_state.get_card(raid_uid)
	if raid_card == null:
		return _fail("突进后未找到 RAID 卡")
	if not bool(raid_card.flags.get("entered_via_raid", false)):
		return _fail("通过突进登场后应标记 entered_via_raid")
	if not p1_raid.removed.has(outside_uid_raid):
		return _fail("通过突进登场时，框内效果应把场外角色移到移除区")
	return _ok()
func _test_simultaneous_trigger_order() -> Dictionary:
	var same_side_manager := _new_manager()
	var first_trigger_uid := _spawn_temp_card(same_side_manager, UATypes.PLAYER_ONE, {
		"id": "TMP_SIMULTANEOUS_ORDER_1",
		"name": "同时触发一",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-SIM-O1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 1000,
		"keywords": [],
		"effects": [],
		"trigger_effects": [
			{"trigger": "ON_BATTLE_END", "operations": [{"type": "DRAW", "value": 1}]}
		]
	}, UATypes.Zone.FRONT_LINE, true)
	var second_trigger_uid := _spawn_temp_card(same_side_manager, UATypes.PLAYER_ONE, {
		"id": "TMP_SIMULTANEOUS_ORDER_2",
		"name": "同时触发二",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-SIM-O2",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 1000,
		"keywords": [],
		"effects": [],
		"trigger_effects": [
			{"trigger": "ON_BATTLE_END", "operations": [{"type": "DRAW", "value": 1}]}
		]
	}, UATypes.Zone.FRONT_LINE, true)
	if first_trigger_uid == "" or second_trigger_uid == "":
		return _fail("同方同时触发顺序测试卡创建失败")
	var same_side_player := _player(same_side_manager, UATypes.PLAYER_ONE)
	var same_side_hand_before := same_side_player.hand.size()
	same_side_manager.effect_resolver.resolve_simultaneous_triggers(same_side_manager.game_state, [
		{
			"source_card_uid": first_trigger_uid,
			"owner_player_id": UATypes.PLAYER_ONE,
			"trigger_type": UATypes.TriggerType.ON_BATTLE_END,
			"context": {
				"source_player_id": UATypes.PLAYER_ONE,
				"target_player_id": UATypes.PLAYER_TWO,
			},
		},
		{
			"source_card_uid": second_trigger_uid,
			"owner_player_id": UATypes.PLAYER_ONE,
			"trigger_type": UATypes.TriggerType.ON_BATTLE_END,
			"context": {
				"source_player_id": UATypes.PLAYER_ONE,
				"target_player_id": UATypes.PLAYER_TWO,
			},
		},
	])
	if same_side_player.hand.size() != same_side_hand_before:
		return _fail("同方多个同时触发存在时，不应在顺序决策前直接结算")
	if same_side_manager.game_state.pending_decisions.size() != 1:
		return _fail("同方多个同时触发应进入显式顺序决策")
	var first_order_decision: Dictionary = same_side_manager.game_state.pending_decisions[0]
	if str(first_order_decision.get("type", "")) != "TRIGGER_ORDER":
		return _fail("同方同时触发的待决策类型应为 TRIGGER_ORDER")
	var first_choices: Array = first_order_decision.get("choices", [])
	if first_choices.size() != 2:
		return _fail("同方同时触发顺序决策应暴露两项可选触发")
	var choice_values: Array[String] = []
	for choice_variant in first_choices:
		choice_values.append(str((choice_variant as Dictionary).get("value", "")))
	if not choice_values.has(first_trigger_uid) or not choice_values.has(second_trigger_uid):
		return _fail("同方同时触发顺序决策应包含全部可选来源")
	same_side_manager.resolve_pending_decision("TRIGGER_ORDER", {"choice": second_trigger_uid})
	if same_side_player.hand.size() != same_side_hand_before + 1:
		return _fail("选择其中一个触发后，应只先结算该触发")
	if same_side_manager.game_state.pending_decisions.size() != 1:
		return _fail("同方同时触发结算一项后，剩余项应继续保留待决策")
	var second_order_decision: Dictionary = same_side_manager.game_state.pending_decisions[0]
	if str(second_order_decision.get("type", "")) != "TRIGGER_ORDER":
		return _fail("剩余同方触发应继续使用 TRIGGER_ORDER 待决策")
	var remaining_choices: Array = second_order_decision.get("choices", [])
	if remaining_choices.size() != 1:
		return _fail("结算一项后，剩余顺序决策应只保留一项触发")
	if str((remaining_choices[0] as Dictionary).get("value", "")) != first_trigger_uid:
		return _fail("同方同时触发应按玩家选择顺序先处理任意一项")
	same_side_manager.resolve_pending_decision("TRIGGER_ORDER", {"choice": first_trigger_uid})
	if same_side_player.hand.size() != same_side_hand_before + 2:
		return _fail("同方同时触发全部处理完成后，应结算两次触发效果")
	if not same_side_manager.game_state.pending_decisions.is_empty():
		return _fail("同方同时触发处理完成后不应残留顺序待决策")

	var turn_player_manager := _new_manager()
	var turn_player_uid := _spawn_temp_card(turn_player_manager, UATypes.PLAYER_ONE, {
		"id": "TMP_SIMULTANEOUS_TURN_PLAYER",
		"name": "回合方触发者",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-SIM-T1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 1000,
		"keywords": [],
		"effects": [],
		"trigger_effects": [
			{"trigger": "ON_BATTLE_END", "operations": [{"type": "DRAW", "value": 1}]}
		]
	}, UATypes.Zone.FRONT_LINE, true)
	var non_turn_player_uid := _spawn_temp_card(turn_player_manager, UATypes.PLAYER_TWO, {
		"id": "TMP_SIMULTANEOUS_NON_TURN_PLAYER",
		"name": "非回合方触发者",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-SIM-T2",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 1000,
		"keywords": [],
		"effects": [],
		"trigger_effects": [
			{"trigger": "ON_BATTLE_END", "operations": [{"type": "DRAW", "value": 1}]}
		]
	}, UATypes.Zone.FRONT_LINE, true)
	if turn_player_uid == "" or non_turn_player_uid == "":
		return _fail("回合方优先顺序测试卡创建失败")
	var p1_turn_player := _player(turn_player_manager, UATypes.PLAYER_ONE)
	var p2_turn_player := _player(turn_player_manager, UATypes.PLAYER_TWO)
	var p1_turn_hand_before := p1_turn_player.hand.size()
	var p2_turn_hand_before := p2_turn_player.hand.size()
	var simultaneous_logs := turn_player_manager.effect_resolver.resolve_simultaneous_triggers(turn_player_manager.game_state, [
		{
			"source_card_uid": turn_player_uid,
			"owner_player_id": UATypes.PLAYER_ONE,
			"trigger_type": UATypes.TriggerType.ON_BATTLE_END,
			"context": {
				"source_player_id": UATypes.PLAYER_ONE,
				"target_player_id": UATypes.PLAYER_TWO,
			},
		},
		{
			"source_card_uid": non_turn_player_uid,
			"owner_player_id": UATypes.PLAYER_TWO,
			"trigger_type": UATypes.TriggerType.ON_BATTLE_END,
			"context": {
				"source_player_id": UATypes.PLAYER_TWO,
				"target_player_id": UATypes.PLAYER_ONE,
			},
		},
	])
	if p1_turn_player.hand.size() != p1_turn_hand_before + 1:
		return _fail("回合方同时触发应先正常结算自己的触发")
	if p2_turn_player.hand.size() != p2_turn_hand_before + 1:
		return _fail("非回合方同时触发应在回合方后继续结算")
	var p1_draw_log := -1
	var p2_draw_log := -1
	for i in range(simultaneous_logs.size()):
		var line := str(simultaneous_logs[i])
		if p1_draw_log == -1 and line == "%s draws 1 card." % UATypes.PLAYER_ONE:
			p1_draw_log = i
		if p2_draw_log == -1 and line == "%s draws 1 card." % UATypes.PLAYER_TWO:
			p2_draw_log = i
	if p1_draw_log == -1 or p2_draw_log == -1:
		return _fail("回合方优先顺序测试未找到双方触发的抽牌日志")
	if p1_draw_log > p2_draw_log:
		return _fail("双方同时触发时，应先处理回合方，再处理非回合方")
	return _ok()
