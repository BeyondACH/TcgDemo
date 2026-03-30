extends SceneTree

const UATypes = preload("res://core/ua_types.gd")
const GameManager = preload("res://core/game_manager.gd")
const PlayerState = preload("res://data/player_state.gd")
const CardInstance = preload("res://data/card_instance.gd")
const CardDef = preload("res://data/card_def.gd")

var _failures: Array[String] = []
var _passes: Array[String] = []

func _init() -> void:
	_run_test("显式目标选择恢复后队列耗尽", _test_target_selection_resume_drains_queue)
	_run_test("延迟效果过期与结算不残留", _test_delayed_effect_cleanup_and_expiration)
	_run_test("战斗后离场与叠放离场不残留 battle_context", _test_battle_context_clears_after_battle_and_stack_leave)
	_run_test("生命触发与显式决策混合链清空运行时状态", _test_life_trigger_and_target_selection_chain_clears_runtime_state)
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

func _advance_to_phase(manager: GameManager, target_phase: int, safety := 32) -> bool:
	while safety > 0 and manager.game_state.phase != target_phase:
		manager.advance_phase()
		safety -= 1
	return manager.game_state.phase == target_phase

func _advance_to_turn_draw(manager: GameManager, player_id: String, min_turn_number := 1, safety := 64) -> bool:
	while safety > 0:
		if manager.game_state.active_player_id == player_id and manager.game_state.phase == UATypes.Phase.DRAW and manager.game_state.turn_number >= min_turn_number:
			return true
		manager.advance_phase()
		safety -= 1
	return manager.game_state.active_player_id == player_id and manager.game_state.phase == UATypes.Phase.DRAW and manager.game_state.turn_number >= min_turn_number

func _is_runtime_state_clean(manager: GameManager) -> bool:
	return manager.game_state.pending_decisions.is_empty() and manager.game_state.effect_queue.is_empty() and manager.game_state.battle_context.is_empty()

func _test_target_selection_resume_drains_queue() -> Dictionary:
	var manager := _new_manager()
	if not _advance_to_phase(manager, UATypes.Phase.MAIN):
		return _fail("未能进入 MAIN 阶段")
	var source_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_RUNTIME_TARGET_SOURCE",
		"name": "目标选择恢复来源",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-RESUME-1",
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
	var target_uid := _spawn_temp_card(manager, UATypes.PLAYER_TWO, {
		"id": "TMP_RUNTIME_TARGET_DEST",
		"name": "目标选择恢复目标",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-RESUME-2",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	if source_uid == "" or target_uid == "":
		return _fail("目标选择测试卡创建失败")
	manager.request_main_activate(source_uid)
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("显式目标选择应进入 1 个待决策")
	if manager.game_state.effect_queue.is_empty():
		return _fail("显式目标选择阶段应保留 effect_queue")
	var decision: Dictionary = manager.game_state.pending_decisions[0]
	if str(decision.get("type", "")) != "ABILITY_TARGET_SELECTION":
		return _fail("待决策类型应为 ABILITY_TARGET_SELECTION")
	manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(decision.get("resolution_id", "")),
		"choice": target_uid,
	})
	var target_card = manager.game_state.get_card(target_uid)
	if target_card == null or target_card.zone != UATypes.Zone.OUTSIDE:
		return _fail("目标选择恢复后应把选中的目标移到场外")
	if not _is_runtime_state_clean(manager):
		return _fail("目标选择恢复后不应残留 pending_decisions、effect_queue 或 battle_context")
	return _ok()

func _test_delayed_effect_cleanup_and_expiration() -> Dictionary:
	var manager := _new_manager()
	manager.game_state.phase = UATypes.Phase.MAIN
	var end_main_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_DELAYED_END_MAIN",
		"name": "结束主阶段延迟一",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-DELAY-1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var end_turn_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_DELAYED_END_TURN",
		"name": "结束回合到期一",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-DELAY-2",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var next_turn_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_DELAYED_NEXT_TURN",
		"name": "下回合开始到期一",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-DELAY-3",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	if end_main_uid == "" or end_turn_uid == "" or next_turn_uid == "":
		return _fail("延迟效果测试卡创建失败")
	manager.game_state.delayed_effects.append({
		"id": "tmp_runtime_end_main",
		"source_card_uid": end_main_uid,
		"owner_player_id": UATypes.PLAYER_ONE,
		"event": "ON_END_MAIN_PHASE",
		"filters": [],
		"steps": [{"type": "MOVE_CARD", "target": "SOURCE_CARD", "to_zone": "OUTSIDE"}],
		"once": true,
		"expires": "",
	})
	manager.game_state.delayed_effects.append({
		"id": "tmp_runtime_end_turn",
		"source_card_uid": end_turn_uid,
		"owner_player_id": UATypes.PLAYER_ONE,
		"event": "ON_NOOP",
		"filters": [],
		"steps": [{"type": "MOVE_CARD", "target": "SOURCE_CARD", "to_zone": "OUTSIDE"}],
		"once": true,
		"expires": "END_OF_TURN",
	})
	manager.game_state.delayed_effects.append({
		"id": "tmp_runtime_next_turn",
		"source_card_uid": next_turn_uid,
		"owner_player_id": UATypes.PLAYER_ONE,
		"event": "ON_NOOP",
		"filters": [],
		"steps": [{"type": "MOVE_CARD", "target": "SOURCE_CARD", "to_zone": "OUTSIDE"}],
		"once": true,
		"expires": "UNTIL_NEXT_SELF_TURN_START",
	})
	manager.advance_phase()
	var end_main_card = manager.game_state.get_card(end_main_uid)
	if end_main_card == null or end_main_card.zone != UATypes.Zone.OUTSIDE:
		return _fail("ON_END_MAIN_PHASE 延迟效果应在进入 ATTACK 前结算并离场")
	if manager.game_state.delayed_effects.size() != 2:
		return _fail("ON_END_MAIN_PHASE 结算后应只剩两条延迟效果")
	if not _is_runtime_state_clean(manager):
		return _fail("ON_END_MAIN_PHASE 结算后不应残留 pending_decisions、effect_queue 或 battle_context")
	manager.advance_phase()
	manager.advance_phase()
	if manager.game_state.active_player_id != UATypes.PLAYER_TWO or manager.game_state.phase != UATypes.Phase.DRAW:
		return _fail("结束回合后应进入 P2 的 DRAW")
	if manager.game_state.delayed_effects.size() != 1:
		return _fail("END_OF_TURN 到期后应只保留 UNTIL_NEXT_SELF_TURN_START 的延迟效果")
	if not _is_runtime_state_clean(manager):
		return _fail("END_OF_TURN 到期后不应残留 pending_decisions、effect_queue 或 battle_context")
	if not _advance_to_turn_draw(manager, UATypes.PLAYER_ONE, 2):
		return _fail("未能推进到 P1 的下个回合开始")
	if not manager.game_state.delayed_effects.is_empty():
		return _fail("UNTIL_NEXT_SELF_TURN_START 到点后不应残留 delayed_effects")
	if not _is_runtime_state_clean(manager):
		return _fail("UNTIL_NEXT_SELF_TURN_START 结算后不应残留运行时脏状态")
	return _ok()

func _test_battle_context_clears_after_battle_and_stack_leave() -> Dictionary:
	var manager := _new_manager()
	manager.game_state.phase = UATypes.Phase.ATTACK
	var attacker_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_BATTLE_ATTACKER",
		"name": "战斗上下文攻击者",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-BATTLE-1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var defender_uid := _spawn_temp_card(manager, UATypes.PLAYER_TWO, {
		"id": "TMP_BATTLE_DEFENDER",
		"name": "战斗上下文防守者",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-BATTLE-2",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	if attacker_uid == "" or defender_uid == "":
		return _fail("战斗上下文测试卡创建失败")
	manager.request_attack(attacker_uid, {"target_kind": "PLAYER"})
	manager.resolve_attack(attacker_uid)
	if not manager.game_state.battle_context.is_empty():
		return _fail("战斗结算后 battle_context 应为空")
	if not _is_runtime_state_clean(manager):
		return _fail("战斗结算后不应残留 pending_decisions 或 effect_queue")

	var stack_manager := _new_manager()
	stack_manager.game_state.phase = UATypes.Phase.MAIN
	var base_uid := _spawn_temp_card(stack_manager, UATypes.PLAYER_ONE, {
		"id": "TMP_STACK_BASE",
		"name": "叠放底牌",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-STACK-1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var top_uid := _spawn_temp_card(stack_manager, UATypes.PLAYER_ONE, {
		"id": "TMP_STACK_TOP",
		"name": "叠放上牌",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-STACK-2",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)
	if base_uid == "" or top_uid == "":
		return _fail("叠放离场测试卡创建失败")
	var stack_result := stack_manager.zone_manager.stack_card_on_target(stack_manager.game_state, top_uid, base_uid, UATypes.Zone.FRONT_LINE)
	if not bool(stack_result.get("ok", false)):
		return _fail("叠放离场测试未能创建叠放结构")
	stack_manager.zone_manager.move_card(stack_manager.game_state, top_uid, UATypes.Zone.OUTSIDE, UATypes.PLAYER_ONE)
	if not stack_manager.game_state.battle_context.is_empty():
		return _fail("叠放离场后 battle_context 不应残留")
	if not _is_runtime_state_clean(stack_manager):
		return _fail("叠放离场后不应残留 pending_decisions 或 effect_queue")
	return _ok()

func _test_life_trigger_and_target_selection_chain_clears_runtime_state() -> Dictionary:
	var manager := _new_manager({
		UATypes.PLAYER_ONE: {"controller": "HUMAN"},
		UATypes.PLAYER_TWO: {"controller": "HUMAN"},
	})
	var target_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_LIFE_CHAIN_TARGET",
		"name": "生命链目标",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-LIFE-2",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, true)
	var life_trigger_uid := _spawn_temp_card(manager, UATypes.PLAYER_TWO, {
		"id": "TMP_LIFE_CHAIN_TRIGGER",
		"name": "生命链触发卡",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-LIFE-3",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": [
			{
				"trigger": "ON_LIFE_TRIGGER",
				"target_specs": [
					{
						"id": "chosen_enemy",
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
						"store_as": "chosen_enemy"
					}
				],
				"steps": [
					{"type": "MOVE_SELECTED_CARDS", "from_var": "chosen_enemy", "to": "OUTSIDE"}
				]
			}
		]
	}, UATypes.Zone.LIFE, true)
	if target_uid == "" or life_trigger_uid == "":
		return _fail("生命链测试卡创建失败")
	var p2 := _player(manager, UATypes.PLAYER_TWO)
	p2.life.clear()
	p2.life = [life_trigger_uid]
	manager.effect_resolver.deal_damage_to_player(manager.game_state, UATypes.PLAYER_TWO, 1)
	if manager.game_state.pending_life_triggers.size() != 1:
		return _fail("受到伤害后应出现 1 个生命触发待决策")
	if manager.game_state.pending_decisions.size() != 0 and str(manager.game_state.pending_decisions[0].get("type", "")) != "ABILITY_TARGET_SELECTION":
		return _fail("生命触发进入显式决策前不应出现其它决策类型")
	manager.resolve_life_trigger_decision(life_trigger_uid, true)
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("生命触发效果应进入 1 个目标选择待决策")
	var decision: Dictionary = manager.game_state.pending_decisions[0]
	if str(decision.get("type", "")) != "ABILITY_TARGET_SELECTION":
		return _fail("生命触发中的显式决策类型应为 ABILITY_TARGET_SELECTION")
	manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(decision.get("resolution_id", "")),
		"choice": target_uid,
	})
	if manager.game_state.pending_life_triggers.size() != 0:
		return _fail("生命触发混合链完成后不应残留 pending_life_triggers")
	if not manager.game_state.pending_decisions.is_empty():
		return _fail("生命触发混合链完成后不应残留 pending_decisions")
	if not manager.game_state.effect_queue.is_empty():
		return _fail("生命触发混合链完成后不应残留 effect_queue")
	if not manager.game_state.battle_context.is_empty():
		return _fail("生命触发混合链完成后不应残留 battle_context")
	var target_card = manager.game_state.get_card(target_uid)
	if target_card == null or target_card.zone != UATypes.Zone.OUTSIDE:
		return _fail("生命触发中的目标选择应把选中的目标移到场外")
	if not manager.game_state.pending_life_reveal.is_empty():
		var current_card_uid := str(manager.game_state.pending_life_reveal.get("current_card_uid", life_trigger_uid))
		manager.acknowledge_life_reveal(current_card_uid)
	if not manager.game_state.pending_life_reveal.is_empty():
		return _fail("生命触发混合链完成后不应残留 pending_life_reveal")
	return _ok()
