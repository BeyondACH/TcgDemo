extends SceneTree

## 手牌 Available Actions 冒烟测试
## 测试手牌卡牌的 available_actions 计算逻辑
## 包括 PLAY_FRONT、PLAY_ENERGY、PLAY_EVENT、RAID 能力标识

const UATypes = preload("res://core/ua_types.gd")
const GameManager = preload("res://core/game_manager.gd")
const PlayerState = preload("res://data/player_state.gd")
const CardInstance = preload("res://data/card_instance.gd")
const CardDef = preload("res://data/card_def.gd")

var _failures: Array[String] = []
var _passes: Array[String] = []

func _init() -> void:
	_run_test("角色卡 MAIN 阶段有 PLAY_FRONT", _test_character_play_front_available)
	_run_test("角色卡 MAIN 阶段有 PLAY_ENERGY", _test_character_play_energy_available)
	_run_test("场地卡 MAIN 阶段有 PLAY_ENERGY", _test_field_play_energy_available)
	_run_test("事件卡 MAIN 阶段有 PLAY_EVENT", _test_event_play_event_available)
	_run_test("AP 不足时 PLAY_FRONT 不可用", _test_character_play_front_no_ap)
	_run_test("AP 不足时 PLAY_ENERGY 不可用", _test_character_play_energy_no_ap)
	_run_test("前线满员时 PLAY_FRONT 不可用", _test_character_play_front_front_full)
	_run_test("能量线满员时 PLAY_ENERGY 不可用", _test_character_play_energy_energy_full)
	_run_test("非 MAIN 阶段手牌无打出动作", _test_no_play_actions_outside_main)
	_run_test("RAID 卡有有效目标时显示 RAID", _test_raid_available_with_valid_target)
	_run_test("RAID 卡无有效目标时不显示 RAID", _test_raid_unavailable_no_valid_target)
	_run_test("RAID 卡 life_trigger_only 仍可从手牌显示", _test_raid_life_trigger_only_still_available_from_hand)
	_run_test("对手卡牌无 available_actions", _test_opponent_card_no_actions)
	_run_test("能量不足时打出动作不可用", _test_play_unavailable_no_energy)
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
	print("=== 手牌 Available Actions 冒烟测试结果 ===")
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
	_resolve_opening(manager)
	return manager

func _resolve_opening(manager: GameManager, p1_choice := "keep", p2_choice := "keep") -> void:
	manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": p1_choice})
	manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": p2_choice})

func _player(manager: GameManager, player_id: String) -> PlayerState:
	return manager.game_state.get_player(player_id)

func _spawn_temp_card(manager: GameManager, player_id: String, card_data: Dictionary, zone: int, active := true) -> String:
	var card_def: CardDef = CardDef.new()
	card_def.from_dict(card_data)
	manager.game_state.card_defs[card_def.id] = card_def
	var player: PlayerState = _player(manager, player_id)
	if player == null:
		return ""
	var card := CardInstance.new()
	card.uid = "%s_custom_%s_%d" % [player_id, card_def.id, manager.game_state.cards.size()]
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

func _advance_to_main(manager: GameManager, player_id: String) -> void:
	var safety := 32
	while safety > 0:
		if manager.game_state.active_player_id == player_id and manager.game_state.phase == UATypes.Phase.MAIN:
			return
		manager.advance_phase()
		safety -= 1

func _get_hand_card_actions(manager: GameManager, player_id: String, card_uid: String) -> Array:
	var snapshot := manager.get_snapshot()
	var players: Dictionary = snapshot.get("players", {})
	var player_data: Dictionary = players.get(player_id, {})
	var hand: Array = player_data.get("hand", [])
	for card_data in hand:
		if str(card_data.get("uid", "")) == card_uid:
			return card_data.get("available_actions", [])
	return []

## 测试：角色卡在 MAIN 阶段有 PLAY_FRONT 动作
func _test_character_play_front_available() -> Dictionary:
	var manager := _new_manager()
	_advance_to_main(manager, UATypes.PLAYER_ONE)
	var p1 := _player(manager, UATypes.PLAYER_ONE)
	# 确保有足够AP
	p1.ap_area = [{"index": 0, "active": true}]

	# 创建一个需要1 AP的角色卡
	var char_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_CHAR_PLAY_FRONT",
		"name": "测试角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-PF-1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)

	if char_uid == "":
		return _fail("测试角色卡创建失败")

	var actions := _get_hand_card_actions(manager, UATypes.PLAYER_ONE, char_uid)
	if not actions.has("PLAY_FRONT"):
		return _fail("角色卡在 MAIN 阶段应有 PLAY_FRONT 动作，实际动作: %s" % str(actions))

	return _ok()

## 测试：角色卡在 MAIN 阶段有 PLAY_ENERGY 动作
func _test_character_play_energy_available() -> Dictionary:
	var manager := _new_manager()
	_advance_to_main(manager, UATypes.PLAYER_ONE)
	var p1 := _player(manager, UATypes.PLAYER_ONE)
	p1.ap_area = [{"index": 0, "active": true}]

	var char_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_CHAR_PLAY_ENERGY",
		"name": "测试角色能量",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-PE-1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)

	if char_uid == "":
		return _fail("测试角色卡创建失败")

	var actions := _get_hand_card_actions(manager, UATypes.PLAYER_ONE, char_uid)
	if not actions.has("PLAY_ENERGY"):
		return _fail("角色卡在 MAIN 阶段应有 PLAY_ENERGY 动作，实际动作: %s" % str(actions))

	return _ok()

## 测试：场地卡在 MAIN 阶段有 PLAY_ENERGY 动作
func _test_field_play_energy_available() -> Dictionary:
	var manager := _new_manager()
	_advance_to_main(manager, UATypes.PLAYER_ONE)
	var p1 := _player(manager, UATypes.PLAYER_ONE)
	p1.ap_area = [{"index": 0, "active": true}]

	var field_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_FIELD_PLAY",
		"name": "测试场地",
		"card_type": "FIELD",
		"title_code": "TMP",
		"number": "TMP-FLD-1",
		"traits": ["测试场地"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {},
		"bp": 0,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)

	if field_uid == "":
		return _fail("测试场地卡创建失败")

	var actions := _get_hand_card_actions(manager, UATypes.PLAYER_ONE, field_uid)
	if not actions.has("PLAY_ENERGY"):
		return _fail("场地卡在 MAIN 阶段应有 PLAY_ENERGY 动作，实际动作: %s" % str(actions))
	if actions.has("PLAY_FRONT"):
		return _fail("场地卡不应有 PLAY_FRONT 动作")

	return _ok()

## 测试：事件卡在 MAIN 阶段有 PLAY_EVENT 动作
func _test_event_play_event_available() -> Dictionary:
	var manager := _new_manager()
	_advance_to_main(manager, UATypes.PLAYER_ONE)
	var p1 := _player(manager, UATypes.PLAYER_ONE)
	p1.ap_area = [{"index": 0, "active": true}]

	var event_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_EVENT_PLAY",
		"name": "测试事件",
		"card_type": "EVENT",
		"title_code": "TMP",
		"number": "TMP-EVT-1",
		"traits": ["测试事件"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {},
		"bp": 0,
		"keywords": [],
		"effects": [{"type": "DRAW", "value": 1}],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)

	if event_uid == "":
		return _fail("测试事件卡创建失败")

	var actions := _get_hand_card_actions(manager, UATypes.PLAYER_ONE, event_uid)
	if not actions.has("PLAY_EVENT"):
		return _fail("事件卡在 MAIN 阶段应有 PLAY_EVENT 动作，实际动作: %s" % str(actions))
	if actions.has("PLAY_FRONT") or actions.has("PLAY_ENERGY"):
		return _fail("事件卡不应有 PLAY_FRONT 或 PLAY_ENERGY 动作")

	return _ok()

## 测试：AP 不足时 PLAY_FRONT 不可用
func _test_character_play_front_no_ap() -> Dictionary:
	var manager := _new_manager()
	_advance_to_main(manager, UATypes.PLAYER_ONE)
	var p1 := _player(manager, UATypes.PLAYER_ONE)
	# 清空AP
	p1.ap_area = []

	# 创建需要1 AP的角色卡
	var char_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_CHAR_NO_AP",
		"name": "测试角色无AP",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-NAP-1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)

	if char_uid == "":
		return _fail("测试角色卡创建失败")

	var actions := _get_hand_card_actions(manager, UATypes.PLAYER_ONE, char_uid)
	if actions.has("PLAY_FRONT"):
		return _fail("AP 不足时不应有 PLAY_FRONT 动作")

	return _ok()

## 测试：AP 不足时 PLAY_ENERGY 不可用
func _test_character_play_energy_no_ap() -> Dictionary:
	var manager := _new_manager()
	_advance_to_main(manager, UATypes.PLAYER_ONE)
	var p1 := _player(manager, UATypes.PLAYER_ONE)
	p1.ap_area = []

	var char_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_CHAR_ENERGY_NO_AP",
		"name": "测试角色能量无AP",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-ENAP-1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)

	if char_uid == "":
		return _fail("测试角色卡创建失败")

	var actions := _get_hand_card_actions(manager, UATypes.PLAYER_ONE, char_uid)
	if actions.has("PLAY_ENERGY"):
		return _fail("AP 不足时不应有 PLAY_ENERGY 动作")

	return _ok()

## 测试：前线满员时 PLAY_FRONT 不可用
func _test_character_play_front_front_full() -> Dictionary:
	var manager := _new_manager()
	_advance_to_main(manager, UATypes.PLAYER_ONE)
	var p1 := _player(manager, UATypes.PLAYER_ONE)
	p1.ap_area = [{"index": 0, "active": true}]

	# 填满前线 (最多4张)
	for i in range(UATypes.MAX_FRONT_LINE):
		_spawn_temp_card(manager, UATypes.PLAYER_ONE, {
			"id": "TMP_FILL_FRONT_%d" % i,
			"name": "填充角色%d" % i,
			"card_type": "CHARACTER",
			"title_code": "TMP",
			"number": "TMP-FF-%d" % i,
			"traits": ["测试角色"],
			"cost_energy": {},
			"cost_ap": 0,
			"energy_provided": {},
			"bp": 1000,
			"keywords": [],
			"effects": [],
			"trigger_effects": []
		}, UATypes.Zone.FRONT_LINE, true)

	var char_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_CHAR_FRONT_FULL",
		"name": "测试角色前线满",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-FFL-1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)

	if char_uid == "":
		return _fail("测试角色卡创建失败")

	var actions := _get_hand_card_actions(manager, UATypes.PLAYER_ONE, char_uid)
	if actions.has("PLAY_FRONT"):
		return _fail("前线满员时不应有 PLAY_FRONT 动作")
	# 但应该仍能打入能量线
	if not actions.has("PLAY_ENERGY"):
		return _fail("前线满员时仍应有 PLAY_ENERGY 动作")

	return _ok()

## 测试：能量线满员时 PLAY_ENERGY 不可用
func _test_character_play_energy_energy_full() -> Dictionary:
	var manager := _new_manager()
	_advance_to_main(manager, UATypes.PLAYER_ONE)
	var p1 := _player(manager, UATypes.PLAYER_ONE)
	p1.ap_area = [{"index": 0, "active": true}]

	# 填满能量线 (最多4张)
	for i in range(UATypes.MAX_ENERGY_LINE):
		_spawn_temp_card(manager, UATypes.PLAYER_ONE, {
			"id": "TMP_FILL_ENERGY_%d" % i,
			"name": "填充能量%d" % i,
			"card_type": "CHARACTER",
			"title_code": "TMP",
			"number": "TMP-FE-%d" % i,
			"traits": ["测试角色"],
			"cost_energy": {},
			"cost_ap": 0,
			"energy_provided": {"GREEN": 1},
			"bp": 1000,
			"keywords": [],
			"effects": [],
			"trigger_effects": []
		}, UATypes.Zone.ENERGY_LINE, true)

	var char_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_CHAR_ENERGY_FULL",
		"name": "测试角色能量满",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-EFL-1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)

	if char_uid == "":
		return _fail("测试角色卡创建失败")

	var actions := _get_hand_card_actions(manager, UATypes.PLAYER_ONE, char_uid)
	if actions.has("PLAY_ENERGY"):
		return _fail("能量线满员时不应有 PLAY_ENERGY 动作")
	# 但应该仍能打入前线
	if not actions.has("PLAY_FRONT"):
		return _fail("能量线满员时仍应有 PLAY_FRONT 动作")

	return _ok()

## 测试：非 MAIN 阶段手牌无打出动作
func _test_no_play_actions_outside_main() -> Dictionary:
	var manager := _new_manager()
	# 停留在 DRAW 阶段
	var p1 := _player(manager, UATypes.PLAYER_ONE)
	p1.ap_area = [{"index": 0, "active": true}]

	var char_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_CHAR_DRAW_PHASE",
		"name": "测试角色抽牌阶段",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-DP-1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)

	if char_uid == "":
		return _fail("测试角色卡创建失败")

	var actions := _get_hand_card_actions(manager, UATypes.PLAYER_ONE, char_uid)
	if actions.has("PLAY_FRONT") or actions.has("PLAY_ENERGY"):
		return _fail("非 MAIN 阶段不应有打出动作，实际动作: %s" % str(actions))

	return _ok()

## 测试：RAID 卡有有效目标时显示 RAID 动作
func _test_raid_available_with_valid_target() -> Dictionary:
	var manager := _new_manager()
	_advance_to_main(manager, UATypes.PLAYER_ONE)
	var p1 := _player(manager, UATypes.PLAYER_ONE)
	p1.ap_area = [{"index": 0, "active": true}]

	# 创建一个RAID目标角色在能量线
	var target_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_RAID_TARGET",
		"name": "RAID目标角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-RT-1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 0,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.ENERGY_LINE, true)

	# 创建一个具有RAID能力的卡牌在手牌
	var raid_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_RAID_CARD",
		"name": "RAID卡牌",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-RD-1",
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
			"allow_from_hand": true,
			"raid_target_name": ""  # 空字符串表示任意角色
		}
	}, UATypes.Zone.HAND, true)

	if target_uid == "" or raid_uid == "":
		return _fail("RAID测试卡牌创建失败")

	var actions := _get_hand_card_actions(manager, UATypes.PLAYER_ONE, raid_uid)
	if not actions.has("RAID"):
		return _fail("RAID卡有有效目标时应有 RAID 动作，实际动作: %s" % str(actions))

	return _ok()

## 测试：RAID 卡无有效目标时不显示 RAID 动作
func _test_raid_unavailable_no_valid_target() -> Dictionary:
	var manager := _new_manager()
	_advance_to_main(manager, UATypes.PLAYER_ONE)
	var p1 := _player(manager, UATypes.PLAYER_ONE)
	p1.ap_area = [{"index": 0, "active": true}]

	# 不创建任何场上角色

	# 创建一个具有RAID能力的卡牌在手牌
	var raid_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_RAID_NO_TARGET",
		"name": "RAID卡牌无目标",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-RNT-1",
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
			"allow_from_hand": true,
			"raid_target_name": ""
		}
	}, UATypes.Zone.HAND, true)

	if raid_uid == "":
		return _fail("RAID测试卡牌创建失败")

	var actions := _get_hand_card_actions(manager, UATypes.PLAYER_ONE, raid_uid)
	if actions.has("RAID"):
		return _fail("RAID卡无有效目标时不应有 RAID 动作，实际动作: %s" % str(actions))

	return _ok()

## 测试：RAID 卡 life_trigger_only=true 且 allow_from_hand=true 时仍显示 RAID
func _test_raid_life_trigger_only_still_available_from_hand() -> Dictionary:
	var manager := _new_manager()
	_advance_to_main(manager, UATypes.PLAYER_ONE)
	var p1 := _player(manager, UATypes.PLAYER_ONE)
	p1.ap_area = [{"index": 0, "active": true}]

	# 创建一个RAID目标角色
	var target_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_RAID_LIFE_TARGET",
		"name": "RAID生命目标",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-RLT-1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 0,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.ENERGY_LINE, true)

	# 创建一个 life_trigger_only=true 的 RAID 卡牌
	var raid_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_RAID_LIFE_ONLY",
		"name": "RAID生命限定",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-RLO-1",
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
			"allow_from_hand": true,
			"life_trigger_only": true,
			"raid_target_name": ""
		}
	}, UATypes.Zone.HAND, true)

	if target_uid == "" or raid_uid == "":
		return _fail("RAID生命触发测试卡牌创建失败")

	var actions := _get_hand_card_actions(manager, UATypes.PLAYER_ONE, raid_uid)
	if not actions.has("RAID"):
		return _fail("life_trigger_only=true 且 allow_from_hand=true 的 RAID 卡应继续从手牌显示 RAID 动作，实际动作: %s" % str(actions))

	return _ok()

## 测试：对手卡牌无 available_actions
func _test_opponent_card_no_actions() -> Dictionary:
	var manager := _new_manager()
	_advance_to_main(manager, UATypes.PLAYER_ONE)

	# 创建一个属于 P2 的卡牌在 P2 手牌中
	var opponent_uid := _spawn_temp_card(manager, UATypes.PLAYER_TWO, {
		"id": "TMP_OPPONENT_CARD",
		"name": "对手卡牌",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-OPP-1",
		"traits": ["测试角色"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)

	if opponent_uid == "":
		return _fail("对手测试卡牌创建失败")

	var actions := _get_hand_card_actions(manager, UATypes.PLAYER_TWO, opponent_uid)
	# P2 的卡牌在 P1 的回合不应有动作
	if not actions.is_empty():
		return _fail("对手回合的卡牌不应有 available_actions，实际动作: %s" % str(actions))

	return _ok()

## 测试：能量不足时打出动作不可用
func _test_play_unavailable_no_energy() -> Dictionary:
	var manager := _new_manager()
	_advance_to_main(manager, UATypes.PLAYER_ONE)
	var p1 := _player(manager, UATypes.PLAYER_ONE)
	p1.ap_area = [{"index": 0, "active": true}]
	# 不提供能量

	# 创建一个需要能量的角色卡
	var char_uid := _spawn_temp_card(manager, UATypes.PLAYER_ONE, {
		"id": "TMP_CHAR_NEED_ENERGY",
		"name": "需要能量的角色",
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-NE-1",
		"traits": ["测试角色"],
		"cost_energy": {"GREEN": 1},  # 需要1绿色能量
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 3000,
		"keywords": [],
		"effects": [],
		"trigger_effects": []
	}, UATypes.Zone.HAND, true)

	if char_uid == "":
		return _fail("测试角色卡创建失败")

	var actions := _get_hand_card_actions(manager, UATypes.PLAYER_ONE, char_uid)
	if actions.has("PLAY_FRONT") or actions.has("PLAY_ENERGY"):
		return _fail("能量不足时不应有打出动作，实际动作: %s" % str(actions))

	return _ok()
