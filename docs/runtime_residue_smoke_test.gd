extends SceneTree

const UATypes = preload("res://core/ua_types.gd")
const GameManager = preload("res://core/game_manager.gd")
const PlayerState = preload("res://data/player_state.gd")
const CardInstance = preload("res://data/card_instance.gd")
const CardDef = preload("res://data/card_def.gd")
const RAW_REMOVED_CHAIN_002 := "UA31BT_MMM_1_002"
const RAW_ENTER_FROM_REMOVED_022 := "UA31BT_MMM_1_022"
const RAW_MAIN_ACTIVATE_MAMI_DISCOUNT_027 := "UA31BT_MMM_1_027"
const RAW_OUTSIDE_EVENT_BOUNCE_019 := "UA31BT_MMM_1_019"
const RAW_EVENT_ONCE_DRAW_READY_034 := "UA31BT_MMM_1_034"

var _failures: Array[String] = []
var _passes: Array[String] = []

func _init() -> void:
	_run_test("显式目标选择恢复后队列耗尽", _test_target_selection_resume_drains_queue)
	_run_test("延迟效果过期与结算不残留", _test_delayed_effect_cleanup_and_expiration)
	_run_test("战斗后离场与叠放离场不残留 battle_context", _test_battle_context_clears_after_battle_and_stack_leave)
	_run_test("生命触发与显式决策混合链清空运行时状态", _test_life_trigger_and_target_selection_chain_clears_runtime_state)
	_run_test("skip_next_ready_once 消费后不残留", _test_skip_next_ready_once_consumes_cleanly)
	_run_test("触发式 once_per_turn 标记跨回合清空", _test_triggered_once_per_turn_flags_clear_on_next_turn)
	_run_test("手牌玛米减费跨回合清理", _test_hand_mami_discount_expires_on_next_turn)
	_run_test("事件每回合限制跨回合清理", _test_event_once_per_turn_flag_clears_on_next_turn)
	_run_test("一次性移除区 AP 减免消费后不残留", _test_removed_ap_discount_does_not_residue)
	_run_test("ai drive long chain leaves no pending gate residue", _test_ai_drive_finishes_without_pending_gate_residue)
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

func _test_skip_next_ready_once_consumes_cleanly() -> Dictionary:
	var manager := _new_manager()
	var target_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_RESIDUE_SKIP_READY",
		"name": "残留跳过起身目标",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-RESIDUE-1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.FRONT_LINE, false)
	var target_card = manager.game_state.get_card(target_uid)
	if target_card == null:
		return _fail("skip_next_ready_once 残留测试卡创建失败")
	target_card.flags["skip_next_ready_once"] = true
	manager.zone_manager.ready_field_cards(manager.game_state, UATypes.PLAYER_ONE)
	if target_card.state != UATypes.CardState.RESTED:
		return _fail("skip_next_ready_once 首次 ready 时应保持 RESTED")
	if bool(target_card.flags.get("skip_next_ready_once", false)):
		return _fail("skip_next_ready_once 首次 ready 后应立即清零")
	manager.zone_manager.ready_field_cards(manager.game_state, UATypes.PLAYER_ONE)
	if target_card.state != UATypes.CardState.ACTIVE:
		return _fail("skip_next_ready_once 消费后下一次 ready 应恢复 ACTIVE")
	return _ok()

func _test_triggered_once_per_turn_flags_clear_on_next_turn() -> Dictionary:
	var manager := _new_manager()
	var player_id := UATypes.PLAYER_ONE
	manager.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(_player(manager, player_id), 3)
	if not _ensure_color_energy(manager, player_id, "YELLOW", 3):
		return _fail("触发式 once_per_turn 残留测试应能准备足够黄能量")
	var source_uid := _move_or_spawn_raw_card(manager, player_id, RAW_ENTER_FROM_REMOVED_022, UATypes.Zone.REMOVED)
	if source_uid == "":
		return _fail("触发式 once_per_turn 残留测试卡创建失败")
	var play_result := manager.play_card(source_uid, UATypes.Zone.FRONT_LINE, {"force_allow_current_zone": true})
	if not bool(play_result.get("ok", false)):
		return _fail("触发式 once_per_turn 残留测试未能从 REMOVED 打出 022")
	var source_card = manager.game_state.get_card(source_uid)
	if source_card == null:
		return _fail("触发式 once_per_turn 残留测试找不到已打出的 022")
	var used_ids: Array = source_card.flags.get("used_triggered_ability_ids_this_turn", [])
	if used_ids.is_empty():
		return _fail("触发式 once_per_turn 首次结算后应写入 used_triggered_ability_ids_this_turn")
	if not _advance_to_turn_draw(manager, player_id, 2):
		return _fail("未能推进到下个己方回合开始以验证 once_per_turn 清理")
	if not source_card.flags.get("used_triggered_ability_ids_this_turn", []).is_empty():
		return _fail("used_triggered_ability_ids_this_turn 应在下个己方回合开始时清空")
	if int(source_card.flags.get("entered_from_zone_this_turn", -1)) != -1:
		return _fail("entered_from_zone_this_turn 也应在回合开始时重置")
	return _ok()

func _test_hand_mami_discount_expires_on_next_turn() -> Dictionary:
	var manager := _new_manager()
	var player_id := UATypes.PLAYER_ONE
	manager.game_state.active_player_id = player_id
	manager.game_state.phase = UATypes.Phase.MAIN
	var source_uid := _move_or_spawn_raw_card(manager, player_id, RAW_MAIN_ACTIVATE_MAMI_DISCOUNT_027, UATypes.Zone.FRONT_LINE)
	var mami_uid := _move_or_spawn_raw_card(manager, player_id, RAW_OUTSIDE_EVENT_BOUNCE_019, UATypes.Zone.HAND)
	var event_uid := _spawn_temp_card(manager, player_id, {
		"id": "TMP_RESIDUE_027_EVENT",
		"name": "残留测试027事件",
		"card_type": "EVENT",
		"title_code": "TMP",
		"number": "TMP-RESIDUE-027",
		"traits": [],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {},
		"bp": 0,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)
	if source_uid == "" or mami_uid == "" or event_uid == "":
		return _fail("027 残留测试应能准备来源、玛米手牌和事件弃牌")
	manager.request_main_activate(source_uid)
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("027 残留测试应进入显式弃牌决策")
	var discard_decision: Dictionary = manager.game_state.pending_decisions[0]
	manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(discard_decision.get("resolution_id", "")),
		"choice": event_uid,
	})
	var discounted := manager.effect_resolver.preview_play_modifiers(manager.game_state, player_id, mami_uid, {
		"target_player_id": player_id,
		"target_zone": UATypes.Zone.FRONT_LINE,
	})
	if int((discounted.get("cost_energy", {}) as Dictionary).get("YELLOW", 0)) != 3:
		return _fail("027 残留测试应在本回合内看到玛米手牌减费生效")
	if not _advance_to_turn_draw(manager, player_id, 2):
		return _fail("未能推进到下个己方回合开始以验证 027 减费过期")
	var reset_preview := manager.effect_resolver.preview_play_modifiers(manager.game_state, player_id, mami_uid, {
		"target_player_id": player_id,
		"target_zone": UATypes.Zone.FRONT_LINE,
	})
	if int((reset_preview.get("cost_energy", {}) as Dictionary).get("YELLOW", 0)) != 4:
		return _fail("027 的手牌减费应在下个己方回合开始前完全清理")
	return _ok()

func _test_event_once_per_turn_flag_clears_on_next_turn() -> Dictionary:
	var manager := _new_manager()
	var player_id := UATypes.PLAYER_ONE
	manager.game_state.active_player_id = player_id
	manager.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(_player(manager, player_id), 3)
	if not _ensure_color_energy(manager, player_id, "YELLOW", 3):
		return _fail("034 残留测试应能准备足够黄能量")
	var source_uid := _move_or_spawn_raw_card(manager, player_id, RAW_EVENT_ONCE_DRAW_READY_034, UATypes.Zone.HAND)
	var second_uid := _spawn_raw_card_copy(manager, player_id, RAW_EVENT_ONCE_DRAW_READY_034, UATypes.Zone.HAND, true)
	var discard_event_uid := _spawn_temp_card(manager, player_id, {
		"id": "TMP_RESIDUE_034_EVENT",
		"name": "残留测试034事件",
		"card_type": "EVENT",
		"title_code": "TMP",
		"number": "TMP-RESIDUE-034",
		"traits": [],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {},
		"bp": 0,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)
	if source_uid == "" or second_uid == "" or discard_event_uid == "":
		return _fail("034 残留测试应能准备两张事件与弃牌事件")
	for hand_uid_variant in _player(manager, player_id).hand.duplicate():
		var hand_uid := str(hand_uid_variant)
		if hand_uid in [source_uid, second_uid, discard_event_uid]:
			continue
		manager.zone_manager.move_card(manager.game_state, hand_uid, UATypes.Zone.OUTSIDE, player_id)
	var play_result := manager.play_card(source_uid, UATypes.Zone.OUTSIDE)
	if not bool(play_result.get("ok", false)):
		return _fail("034 残留测试首张事件应能成功使用")
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("034 残留测试应进入显式弃牌决策")
	var discard_decision: Dictionary = manager.game_state.pending_decisions[0]
	manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(discard_decision.get("resolution_id", "")),
		"choice": discard_event_uid,
	})
	var blocked_same_turn := manager.rules_engine.can_play_card(manager.game_state, player_id, second_uid, UATypes.Zone.OUTSIDE)
	if bool(blocked_same_turn.get("ok", false)):
		return _fail("034 在同一回合内应继续被每回合一次限制阻止")
	if not _advance_to_turn_draw(manager, player_id, 2):
		return _fail("未能推进到下个己方回合开始以验证 034 标记清理")
	if not _advance_to_phase(manager, UATypes.Phase.MAIN):
		return _fail("未能进入下个己方 MAIN 阶段以验证 034 可再次使用")
	var allowed_next_turn := manager.rules_engine.can_play_card(manager.game_state, player_id, second_uid, UATypes.Zone.OUTSIDE)
	if not bool(allowed_next_turn.get("ok", false)):
		return _fail("034 在下个己方回合开始后应可再次使用")
	return _ok()

func _test_removed_ap_discount_does_not_residue() -> Dictionary:
	var manager := _new_manager()
	var player_id := UATypes.PLAYER_ONE
	manager.game_state.phase = UATypes.Phase.MAIN
	_fill_ap(_player(manager, player_id), 3)
	var source_uid := _move_or_spawn_raw_card(manager, player_id, RAW_REMOVED_CHAIN_002, UATypes.Zone.FRONT_LINE)
	if source_uid == "":
		return _fail("移除区 AP 减免残留测试卡创建失败")
	var source_card = manager.game_state.get_card(source_uid)
	if source_card == null:
		return _fail("移除区 AP 减免残留测试找不到 002 来源卡")
	source_card.flags["entered_via_raid"] = true
	var outside_uid := _spawn_temp_card(manager, player_id, {
		"id": "TMP_RESIDUE_002_OUTSIDE",
		"name": "残留测试场外角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-RESIDUE-2",
		"traits": ["测试角色"],
		"cost_energy": {"YELLOW": 1},
		"cost_ap": 1,
		"energy_provided": {"YELLOW": 1},
		"bp": 1000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.OUTSIDE, true)
	manager.effect_resolver.resolve_trigger(source_uid, UATypes.TriggerType.ON_ENTER, manager.game_state, {"target_player_id": player_id})
	if manager.game_state.pending_decisions.size() != 1:
		return _fail("移除区 AP 减免残留测试应先出现一次场外选择决策")
	var decision: Dictionary = manager.game_state.pending_decisions[0]
	manager.resolve_pending_decision("ABILITY_TARGET_SELECTION", {
		"resolution_id": str(decision.get("resolution_id", "")),
		"choice": outside_uid,
	})
	if manager.game_state.delayed_effects.size() != 1:
		return _fail("移除区 AP 减免残留测试应只登记一条 delayed_effect")
	var discounted_uid := _spawn_temp_card(manager, player_id, {
		"id": "TMP_RESIDUE_002_EVENT_A",
		"name": "残留测试事件A",
		"card_type": "EVENT",
		"title_code": "TMP",
		"number": "TMP-RESIDUE-3",
		"traits": [],
		"cost_energy": {},
		"cost_ap": 2,
		"energy_provided": {},
		"bp": 0,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.REMOVED, true)
	var full_cost_uid := _spawn_temp_card(manager, player_id, {
		"id": "TMP_RESIDUE_002_EVENT_B",
		"name": "残留测试事件B",
		"card_type": "EVENT",
		"title_code": "TMP",
		"number": "TMP-RESIDUE-4",
		"traits": [],
		"cost_energy": {},
		"cost_ap": 2,
		"energy_provided": {},
		"bp": 0,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.REMOVED, true)
	var player := _player(manager, player_id)
	manager.play_card(discounted_uid, UATypes.Zone.OUTSIDE, {"force_allow_current_zone": true})
	if player.ap_active_count() != 2:
		return _fail("移除区 AP 减免残留测试的首张 REMOVED 牌应只消耗 1 AP")
	if not manager.game_state.delayed_effects.is_empty():
		return _fail("一次性 REMOVED AP 减免在首张匹配牌后应被消费，不应残留 delayed_effect")
	manager.play_card(full_cost_uid, UATypes.Zone.OUTSIDE, {"force_allow_current_zone": true})
	if player.ap_active_count() != 0:
		return _fail("一次性 REMOVED AP 减免消费后不应继续影响第二张牌")
	return _ok()

func _test_ai_drive_finishes_without_pending_gate_residue() -> Dictionary:
	var manager := _new_manager({
		UATypes.PLAYER_ONE: {"controller": "AI_SIMPLE"},
		UATypes.PLAYER_TWO: {"controller": "AI_SIMPLE"},
	})
	for _i in range(10):
		if manager.game_state.winner_player_id != "":
			break
		manager.drive_controllers(64)
		manager.advance_phase()
	manager.drive_controllers(64)
	if not manager.game_state.pending_decisions.is_empty():
		return _fail("ai drive left pending decisions behind")
	if not manager.game_state.pending_life_triggers.is_empty():
		return _fail("ai drive left pending life triggers behind")
	if not manager.game_state.pending_life_reveal.is_empty():
		return _fail("ai drive left pending life reveal behind")
	if not manager.game_state.effect_queue.is_empty():
		return _fail("ai drive left effect_queue behind")
	return _ok()

func _fill_ap(player: PlayerState, total: int) -> void:
	player.ap_area.clear()
	for i in range(total):
		player.ap_area.append({"index": i, "active": true})

func _count_color_energy(manager: GameManager, player_id: String, color: String) -> int:
	var player: PlayerState = _player(manager, player_id)
	if player == null:
		return 0
	var total := 0
	for card_uid_variant in player.energy_line:
		var card_uid := str(card_uid_variant)
		var card = manager.game_state.get_card(card_uid)
		var card_def = manager.game_state.get_card_def(card.def_id) if card != null else null
		if card_def == null:
			continue
		total += int(card_def.energy_provided.get(color.to_upper(), 0))
	return total

func _spawn_generic_energy(manager: GameManager, player_id: String, color: String, temp_id: String) -> String:
	return _spawn_temp_card(manager, player_id, {
		"id": temp_id,
		"name": "残留测试能量%s" % temp_id,
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-ENERGY-%s" % temp_id,
		"traits": [],
		"cost_energy": {color.to_upper(): 1},
		"cost_ap": 1,
		"energy_provided": {color.to_upper(): 1},
		"bp": 1000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.ENERGY_LINE, false)

func _ensure_color_energy(manager: GameManager, player_id: String, color: String, count: int) -> bool:
	while _count_color_energy(manager, player_id, color) < count:
		var uid := _spawn_generic_energy(manager, player_id, color, "RUNTIME_%s_%d" % [color.to_upper(), manager.game_state.cards.size()])
		if uid == "":
			break
	return _count_color_energy(manager, player_id, color) >= count

func _move_or_spawn_raw_card(manager: GameManager, player_id: String, def_id: String, zone: int, active := true) -> String:
	var existing_uid := _find_card_in_zones(manager, player_id, def_id, ["hand", "deck", "life", "energy_line", "front_line", "outside", "removed"])
	if existing_uid != "":
		manager.zone_manager.move_card(manager.game_state, existing_uid, zone, player_id)
		var existing_card = manager.game_state.get_card(existing_uid)
		if existing_card != null and zone != UATypes.Zone.LIFE:
			existing_card.state = UATypes.CardState.ACTIVE if active else UATypes.CardState.RESTED
		return existing_uid
	var card_def = manager.game_state.get_card_def(def_id)
	if card_def == null:
		return ""
	var card := CardInstance.new()
	card.uid = "%s_runtime_raw_%s_%d" % [player_id, def_id, manager.game_state.cards.size()]
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

func _spawn_raw_card_copy(manager: GameManager, player_id: String, def_id: String, zone: int, active := true) -> String:
	var card_def = manager.game_state.get_card_def(def_id)
	if card_def == null:
		return ""
	var card := CardInstance.new()
	card.uid = "%s_runtime_raw_copy_%s_%d" % [player_id, def_id, manager.game_state.cards.size()]
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
