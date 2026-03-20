extends SceneTree

const UATypes = preload("res://core/ua_types.gd")
const GameManager = preload("res://core/game_manager.gd")
const PlayerState = preload("res://data/player_state.gd")

var _failures: Array[String] = []
var _passes: Array[String] = []

func _init() -> void:
	_run_test("对局初始化", _test_setup_game)
	_run_test("阶段推进与换手", _test_phase_advance_and_turn_switch)
	_run_test("角色出牌与移动", _test_play_and_move_character)
	_run_test("事件牌抽牌效果", _test_event_draw)
	_run_test("攻击造成伤害", _test_attack_damage)
	_run_test("生命归零胜负", _test_life_zero_victory)
	_run_test("空牌库抽牌败北", _test_deck_out_loss)
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
	var player: PlayerState = _player(manager, player_id)
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
