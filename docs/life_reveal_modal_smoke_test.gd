extends SceneTree

const UATypes = preload("res://core/ua_types.gd")
const GameManager = preload("res://core/game_manager.gd")
const CardInstance = preload("res://data/card_instance.gd")
const CardDef = preload("res://data/card_def.gd")
const PlayerState = preload("res://data/player_state.gd")
const LifeRevealModal = preload("res://ui/life_reveal_modal.gd")

var _failures: Array[String] = []
var _activate_requests: Array[String] = []
var _skip_requests: Array[String] = []
var _ack_requests: Array[String] = []

func _init() -> void:
	_run_test("life reveal snapshot includes trigger and non-trigger cards", _test_life_reveal_snapshot_for_damage)
	_run_test("life reveal acknowledge finalizes non-trigger damage", _test_life_reveal_acknowledge_flow)
	_run_test("human trigger reveal offers activate and skip", _test_human_trigger_reveal_controls)
	_run_test("ai vanilla reveal waits for player acknowledgement", _test_ai_vanilla_reveal_waits_for_player_ack)
	_run_test("ai trigger reveal requires continue before ai resolves", _test_ai_trigger_reveal_requires_continue_before_ai)
	_run_test("life reveal modal toggles actions by current card", _test_life_reveal_modal_ui)
	if _failures.is_empty():
		print("LIFE_REVEAL_MODAL_SMOKE_OK")
	quit(0 if _failures.is_empty() else 1)

func _run_test(name: String, callable: Callable) -> void:
	var result = callable.call()
	if bool(result.get("ok", false)):
		print("[PASS] %s" % name)
		return
	var error := str(result.get("error", "unknown"))
	_failures.append("%s: %s" % [name, error])
	push_error("[FAIL] %s: %s" % [name, error])

func _ok() -> Dictionary:
	return {"ok": true}

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}

func _new_manager() -> GameManager:
	var manager := GameManager.new()
	manager.setup_game({
		UATypes.PLAYER_ONE: {"controller": "HUMAN"},
		UATypes.PLAYER_TWO: {"controller": "HUMAN"},
	})
	manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})
	manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})
	return manager

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
	card.uid = "%s_life_reveal_%s_%d" % [player_id, card_def.id, manager.game_state.cards.size()]
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

func _life_trigger_card(id_suffix: String) -> Dictionary:
	return {
		"id": "TMP_LIFE_TRIGGER_%s" % id_suffix,
		"name": "Life Trigger %s" % id_suffix,
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-LT-%s" % id_suffix,
		"traits": ["Tester"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2500,
		"keywords": [],
		"effects": [],
		"trigger_effects": [
			{
				"trigger": "ON_LIFE_TRIGGER",
				"text": "Draw a card.",
				"steps": [{"type": "DRAW", "value": 1}]
			}
		],
	}

func _vanilla_life_card(id_suffix: String) -> Dictionary:
	return {
		"id": "TMP_LIFE_VANILLA_%s" % id_suffix,
		"name": "Vanilla Life %s" % id_suffix,
		"card_type": "CHARACTER",
		"title_code": "TMP",
		"number": "TMP-LV-%s" % id_suffix,
		"traits": ["Tester"],
		"cost_energy": {},
		"cost_ap": 1,
		"energy_provided": {"GREEN": 1},
		"bp": 2000,
		"keywords": [],
		"effects": [],
		"trigger_effects": [],
	}

func _test_life_reveal_snapshot_for_damage() -> Dictionary:
	var manager := _new_manager()
	var p2 := _player(manager, UATypes.PLAYER_TWO)
	p2.life.clear()
	var trigger_uid := _spawn_temp_card(manager, UATypes.PLAYER_TWO, _life_trigger_card("A"), UATypes.Zone.LIFE, true)
	var vanilla_uid := _spawn_temp_card(manager, UATypes.PLAYER_TWO, _vanilla_life_card("A"), UATypes.Zone.LIFE, true)
	p2.life = [trigger_uid, vanilla_uid]
	manager.effect_resolver.deal_damage_to_player(manager.game_state, UATypes.PLAYER_TWO, 2)
	var snapshot := manager.get_snapshot()
	var modal: Dictionary = snapshot.get("life_reveal_modal", {})
	if not bool(modal.get("visible", false)):
		return _fail("life reveal modal should become visible after life damage.")
	if str(modal.get("current_card_uid", "")) != trigger_uid:
		return _fail("current life reveal card should start from the first damaged life card.")
	if not bool(modal.get("can_activate", false)) or not bool(modal.get("can_skip", false)):
		return _fail("trigger card should expose activate and skip actions.")
	var revealed_cards: Array = modal.get("revealed_cards", [])
	if revealed_cards.size() != 2:
		return _fail("life reveal modal should list all revealed life cards.")
	var saw_trigger := false
	var saw_vanilla := false
	for card_variant in revealed_cards:
		var card_data: Dictionary = card_variant
		if str(card_data.get("uid", "")) == trigger_uid and bool(card_data.get("has_life_trigger", false)):
			saw_trigger = true
		if str(card_data.get("uid", "")) == vanilla_uid and not bool(card_data.get("has_life_trigger", true)):
			saw_vanilla = true
	if not saw_trigger or not saw_vanilla:
		return _fail("life reveal modal should distinguish trigger and non-trigger life cards.")
	return _ok()

func _test_life_reveal_acknowledge_flow() -> Dictionary:
	var manager := _new_manager()
	var p2 := _player(manager, UATypes.PLAYER_TWO)
	p2.life.clear()
	var vanilla_uid := _spawn_temp_card(manager, UATypes.PLAYER_TWO, _vanilla_life_card("B"), UATypes.Zone.LIFE, true)
	p2.life = [vanilla_uid]
	var outside_before := p2.outside.size()
	manager.effect_resolver.deal_damage_to_player(manager.game_state, UATypes.PLAYER_TWO, 1)
	var snapshot := manager.get_snapshot()
	var modal: Dictionary = snapshot.get("life_reveal_modal", {})
	if not bool(modal.get("can_acknowledge", false)):
		return _fail("non-trigger life reveal should expose acknowledge flow.")
	var result := manager.acknowledge_life_reveal(vanilla_uid)
	if not bool(result.get("ok", false)):
		return _fail("acknowledging a non-trigger life reveal should succeed.")
	if not manager.game_state.pending_life_reveal.is_empty():
		return _fail("life reveal batch should clear after acknowledging the last non-trigger card.")
	if p2.outside.size() != outside_before + 1:
		return _fail("acknowledging the reveal should finalize the damaged life card into outside.")
	return _ok()

func _test_human_trigger_reveal_controls() -> Dictionary:
	var manager := _new_manager()
	var p2 := _player(manager, UATypes.PLAYER_TWO)
	p2.life.clear()
	var trigger_uid := _spawn_temp_card(manager, UATypes.PLAYER_TWO, _life_trigger_card("HUMAN"), UATypes.Zone.LIFE, true)
	p2.life = [trigger_uid]
	manager.effect_resolver.deal_damage_to_player(manager.game_state, UATypes.PLAYER_TWO, 1)
	var modal: Dictionary = manager.get_snapshot().get("life_reveal_modal", {})
	if not bool(modal.get("visible", false)):
		return _fail("human trigger reveal should be visible.")
	if not bool(modal.get("can_activate", false)) or not bool(modal.get("can_skip", false)):
		return _fail("human trigger reveal should expose activate and skip.")
	if bool(modal.get("can_acknowledge", false)):
		return _fail("human trigger reveal should not use continue before trigger choice.")
	return _ok()

func _test_ai_vanilla_reveal_waits_for_player_ack() -> Dictionary:
	var manager := GameManager.new()
	manager.setup_game({
		UATypes.PLAYER_ONE: {"controller": "HUMAN"},
		UATypes.PLAYER_TWO: {"controller": "AI_SIMPLE"},
	})
	manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})
	manager.drive_controllers(32)
	var p2 := _player(manager, UATypes.PLAYER_TWO)
	p2.life.clear()
	var vanilla_uid := _spawn_temp_card(manager, UATypes.PLAYER_TWO, _vanilla_life_card("AI"), UATypes.Zone.LIFE, true)
	p2.life = [vanilla_uid]
	manager.effect_resolver.deal_damage_to_player(manager.game_state, UATypes.PLAYER_TWO, 1)
	manager.drive_controllers(16)
	if manager.game_state.pending_life_reveal.is_empty():
		return _fail("ai vanilla reveal should remain pending until the player confirms it.")
	var modal: Dictionary = manager.get_snapshot().get("life_reveal_modal", {})
	if not bool(modal.get("can_acknowledge", false)):
		return _fail("ai vanilla reveal should show continue.")
	manager.acknowledge_life_reveal(vanilla_uid)
	if not manager.game_state.pending_life_reveal.is_empty():
		return _fail("ai vanilla reveal should clear after player acknowledgement.")
	return _ok()

func _test_ai_trigger_reveal_requires_continue_before_ai() -> Dictionary:
	var manager := GameManager.new()
	manager.setup_game({
		UATypes.PLAYER_ONE: {"controller": "HUMAN"},
		UATypes.PLAYER_TWO: {"controller": "AI_SIMPLE"},
	})
	manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})
	manager.drive_controllers(32)
	var p2 := _player(manager, UATypes.PLAYER_TWO)
	p2.life.clear()
	var trigger_uid := _spawn_temp_card(manager, UATypes.PLAYER_TWO, _life_trigger_card("AI"), UATypes.Zone.LIFE, true)
	p2.life = [trigger_uid]
	var hand_before := p2.hand.size()
	manager.effect_resolver.deal_damage_to_player(manager.game_state, UATypes.PLAYER_TWO, 1)
	manager.drive_controllers(16)
	var modal: Dictionary = manager.get_snapshot().get("life_reveal_modal", {})
	if not bool(modal.get("visible", false)):
		return _fail("ai trigger reveal should be visible.")
	if not bool(modal.get("can_acknowledge", false)):
		return _fail("ai trigger reveal should require continue before AI resolves it.")
	if bool(modal.get("can_activate", false)) or bool(modal.get("can_skip", false)):
		return _fail("ai trigger reveal should not expose activate or skip to the player.")
	manager.acknowledge_life_reveal(trigger_uid)
	manager.drive_controllers(32)
	if p2.hand.size() != hand_before + 1:
		return _fail("after continue, AI should resolve its trigger and draw a card.")
	if not manager.game_state.pending_life_reveal.is_empty():
		return _fail("ai trigger reveal should clear after player continue and AI resolution.")
	return _ok()

func _test_life_reveal_modal_ui() -> Dictionary:
	var root := Window.new()
	root.visible = false
	get_root().add_child(root)
	var modal := LifeRevealModal.new()
	root.add_child(modal)
	modal._ready()
	_activate_requests.clear()
	_skip_requests.clear()
	_ack_requests.clear()
	modal.activate_requested.connect(func(card_uid: String) -> void:
		_activate_requests.append(card_uid)
	)
	modal.skip_requested.connect(func(card_uid: String) -> void:
		_skip_requests.append(card_uid)
	)
	modal.acknowledge_requested.connect(func(card_uid: String) -> void:
		_ack_requests.append(card_uid)
	)
	modal.show_modal({
		"visible": true,
		"player_id": UATypes.PLAYER_TWO,
		"current_card_uid": "CARD_TRIGGER",
		"revealed_cards": [
			{"uid": "CARD_TRIGGER", "name": "Trigger Card", "has_life_trigger": true, "resolved": false, "is_current": true},
			{"uid": "CARD_VANILLA", "name": "Vanilla Card", "has_life_trigger": false, "resolved": false, "is_current": false},
		],
		"can_activate": true,
		"can_skip": true,
		"can_acknowledge": false,
		"awaiting_player_confirmation": false,
		"ai_resolves_after_confirmation": false,
		"waiting_for_ai_resolution": false,
	})
	if not modal._activate_button.visible or not modal._skip_button.visible or modal._continue_button.visible:
		return _fail("trigger state should show activate/skip and hide continue.")
	modal._on_activate_pressed()
	modal._on_skip_pressed()
	if _activate_requests != ["CARD_TRIGGER"] or _skip_requests != ["CARD_TRIGGER"]:
		return _fail("trigger state should emit activate and skip for the current card.")
	modal.show_modal({
		"visible": true,
		"player_id": UATypes.PLAYER_TWO,
		"current_card_uid": "CARD_VANILLA",
		"revealed_cards": [
			{"uid": "CARD_TRIGGER", "name": "Trigger Card", "has_life_trigger": true, "resolved": true, "is_current": false},
			{"uid": "CARD_VANILLA", "name": "Vanilla Card", "has_life_trigger": false, "resolved": false, "is_current": true},
		],
		"can_activate": false,
		"can_skip": false,
		"can_acknowledge": true,
		"awaiting_player_confirmation": false,
		"ai_resolves_after_confirmation": false,
		"waiting_for_ai_resolution": false,
	})
	if modal._activate_button.visible or modal._skip_button.visible or not modal._continue_button.visible:
		return _fail("non-trigger state should hide activate/skip and show continue.")
	modal._on_continue_pressed()
	if _ack_requests != ["CARD_VANILLA"]:
		return _fail("continue should acknowledge the current non-trigger card.")
	modal.show_modal({
		"visible": true,
		"player_id": UATypes.PLAYER_TWO,
		"current_card_uid": "CARD_AI_TRIGGER",
		"revealed_cards": [
			{"uid": "CARD_AI_TRIGGER", "name": "AI Trigger Card", "has_life_trigger": true, "resolved": false, "is_current": true},
		],
		"can_activate": false,
		"can_skip": false,
		"can_acknowledge": true,
		"awaiting_player_confirmation": true,
		"ai_resolves_after_confirmation": true,
		"waiting_for_ai_resolution": false,
	})
	if modal._activate_button.visible or modal._skip_button.visible or not modal._continue_button.visible:
		return _fail("ai trigger pre-confirm state should show continue only.")
	return _ok()
