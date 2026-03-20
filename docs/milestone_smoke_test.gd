extends SceneTree

const UATypes = preload("res://core/ua_types.gd")
const GameManager = preload("res://core/game_manager.gd")
const PlayerState = preload("res://data/player_state.gd")
const CardInstance = preload("res://data/card_instance.gd")

var _failures: Array[String] = []
var _passes: Array[String] = []

func _init() -> void:
	_run_test("对局初始化", _test_setup_game)
	_run_test("阶段推进与换手", _test_phase_advance_and_turn_switch)
	_run_test("角色出牌与移动", _test_play_and_move_character)
	_run_test("事件牌抽牌效果", _test_event_draw)
	_run_test("攻击造成伤害", _test_attack_damage)
	_run_test("生命触发需要显式决策", _test_life_trigger_requires_decision)
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

func _new_manager() -> GameManager:
	var manager := GameManager.new()
	manager.setup_game()
	return manager

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
	var card_def = manager.game_state.get_card_def(def_id)
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
	var zone_cards = manager.zone_manager.get_zone_array(player, zone)
	if zone_cards != null:
		zone_cards.append(card.uid)
	return card.uid

func _test_setup_game() -> Dictionary:
	var manager := _new_manager()
	var p1 := _player(manager, UATypes.PLAYER_ONE)
	var p2 := _player(manager, UATypes.PLAYER_TWO)
	if manager.game_state.turn_number != 1:
		return _fail("turn_number 应为 1")
	if manager.game_state.active_player_id != UATypes.PLAYER_ONE:
		return _fail("首个行动玩家应为 P1")
	if manager.game_state.phase != UATypes.Phase.MOVE:
		return _fail("初始化后阶段应进入 MOVE")
	if p1.hand.size() != 7 or p2.hand.size() != 7:
		return _fail("双方起手手牌都应为 7")
	if p1.life.size() != 7 or p2.life.size() != 7:
		return _fail("双方生命区都应为 7")
	if p1.deck.size() != 36 or p2.deck.size() != 36:
		return _fail("初始化后牌库应剩 36")
	if p1.ap_total() != 1 or p1.ap_active_count() != 1:
		return _fail("P1 首回合开始时 AP 应为 1/1")
	return _ok()

func _test_phase_advance_and_turn_switch() -> Dictionary:
	var manager := _new_manager()
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
	if manager.game_state.phase != UATypes.Phase.MOVE:
		return _fail("新回合开始后应处于 MOVE")
	if manager.game_state.turn_number != 2:
		return _fail("换手后 turn_number 应为 2")
	if p2.ap_total() != 2 or p2.ap_active_count() != 2:
		return _fail("P2 首回合开始时 AP 应为 2/2")
	if p2.hand.size() != 8:
		return _fail("P2 首回合应抽 1 张，手牌应为 8")
	return _ok()

func _test_play_and_move_character() -> Dictionary:
	var manager := _new_manager()
	manager.game_state.phase = UATypes.Phase.MAIN
	var character_uid := _ensure_card_in_hand(manager, UATypes.PLAYER_ONE, "UA_CHAR_BASIC")
	if character_uid == "":
		return _fail("未找到可用于测试的基础角色牌")
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
	var p2 := _player(manager, UATypes.PLAYER_TWO)
	manager.advance_phase()
	if manager.game_state.phase != UATypes.Phase.MAIN:
		return _fail("P2 MOVE 后应进入 MAIN")
	var energy_uid := _ensure_card_in_hand(manager, UATypes.PLAYER_TWO, "UA_CHAR_BASIC")
	var event_uid := _ensure_card_in_hand(manager, UATypes.PLAYER_TWO, "UA_EVENT_DRAW")
	if energy_uid == "" or event_uid == "":
		return _fail("未找到用于测试事件的角色牌或事件牌")
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
	var attacker_uid := _put_card_on_front(manager, UATypes.PLAYER_ONE, "UA_CHAR_HEAVY", true)
	if attacker_uid == "":
		return _fail("未找到可用于测试攻击的高 BP 角色")
	manager.game_state.phase = UATypes.Phase.ATTACK
	var p2 := _player(manager, UATypes.PLAYER_TWO)
	var life_before := p2.life.size()
	manager.resolve_attack(attacker_uid)
	var attacker = manager.game_state.get_card(attacker_uid)
	if p2.life.size() != life_before - 1:
		return _fail("未阻挡攻击应使对手生命减少 1")
	if attacker.state != UATypes.CardState.RESTED:
		return _fail("攻击后的角色应变为 RESTED")
	return _ok()

func _test_life_trigger_requires_decision() -> Dictionary:
	var manager := _new_manager()
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

func _test_life_zero_victory() -> Dictionary:
	var manager := _new_manager()
	manager.effect_resolver.deal_damage_to_player(manager.game_state, UATypes.PLAYER_TWO, 7)
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
	manager.zone_manager.move_card(manager.game_state, raid_uid, UATypes.Zone.OUTSIDE, UATypes.PLAYER_ONE)
	if not p1.outside.has(raid_uid):
		return _fail("RAID 上层离场后应进入场外")
	if not p1.outside.has(base_uid):
		return _fail("RAID 下层卡在上层离场后应返回场外")

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
