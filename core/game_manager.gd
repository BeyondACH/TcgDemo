extends Node
class_name GameManager

const UATypes = preload("res://core/ua_types.gd")
const GameState = preload("res://data/game_state.gd")
const ZoneManager = preload("res://core/zone_manager.gd")
const VictoryChecker = preload("res://core/victory_checker.gd")
const RulesEngine = preload("res://core/rules_engine.gd")
const EffectResolver = preload("res://core/effect_resolver.gd")
const BattleResolver = preload("res://core/battle_resolver.gd")
const TurnManager = preload("res://core/turn_manager.gd")
const PlayerState = preload("res://data/player_state.gd")
const CardInstance = preload("res://data/card_instance.gd")
const CardDef = preload("res://data/card_def.gd")
const ActionTypes = preload("res://core/actions/action_types.gd")
const PlayerController = preload("res://core/controllers/player_controller.gd")
const HumanController = preload("res://core/controllers/human_controller.gd")
const AIController = preload("res://core/controllers/ai_controller.gd")

signal state_changed(snapshot: Dictionary)
signal blockers_requested(request: Dictionary)
signal log_added(text: String)

const CARD_DATA_PATH := "res://data/cards/cards_effects.json"
const STARTER_A_PATH := "res://data/decks/starter_a.txt"
const STARTER_B_PATH := "res://data/decks/starter_b.txt"

@export_enum("HUMAN", "AI_SIMPLE") var player_one_controller_type := PlayerController.CONTROLLER_HUMAN
@export_enum("HUMAN", "AI_SIMPLE") var player_two_controller_type := PlayerController.CONTROLLER_AI_SIMPLE

var game_state := GameState.new()
var zone_manager := ZoneManager.new()
var victory_checker := VictoryChecker.new()
var rules_engine := RulesEngine.new(zone_manager)
var effect_resolver := EffectResolver.new(zone_manager, victory_checker, rules_engine)
var battle_resolver := BattleResolver.new(rules_engine, zone_manager, effect_resolver)
var turn_manager := TurnManager.new(zone_manager, victory_checker, effect_resolver)
var _deck_card_lookup := {}
var _controller_config := {}
var _controllers := {}
var _controller_drive_pending := false
var _controller_drive_in_progress := false

func _ready() -> void:
	randomize()
	setup_game()

# Initialize a fresh game state, decks, starting hands, and opening turn.
func setup_game(controller_config: Dictionary = {}) -> void:
	game_state = GameState.new()
	_reset_controller_state(controller_config)
	_load_card_defs()
	var starter_a: Array = _load_deck_list(STARTER_A_PATH)
	var starter_b: Array = _load_deck_list(STARTER_B_PATH)
	_create_player(UATypes.PLAYER_ONE, starter_a)
	_create_player(UATypes.PLAYER_TWO, starter_b)
	_prepare_opening_hand(UATypes.PLAYER_ONE)
	_prepare_opening_hand(UATypes.PLAYER_TWO)
	_enqueue_mulligan_decision(UATypes.PLAYER_ONE)
	emit_state_changed()

func set_controller_config(controller_config: Dictionary) -> void:
	_reset_controller_state(controller_config)

func get_controller_type(player_id: String) -> String:
	var controller: PlayerController = _controllers.get(player_id)
	if controller == null:
		return PlayerController.CONTROLLER_HUMAN
	return controller.controller_type

func _reset_controller_state(controller_config: Dictionary = {}) -> void:
	_controller_config = {
		UATypes.PLAYER_ONE: {"controller": player_one_controller_type},
		UATypes.PLAYER_TWO: {"controller": player_two_controller_type},
	}
	for player_id in controller_config.keys():
		_controller_config[player_id] = (controller_config[player_id] as Dictionary).duplicate(true)
	_controllers.clear()
	_controllers[UATypes.PLAYER_ONE] = _build_controller_for(UATypes.PLAYER_ONE)
	_controllers[UATypes.PLAYER_TWO] = _build_controller_for(UATypes.PLAYER_TWO)
	_controller_drive_pending = false
	_controller_drive_in_progress = false

func _build_controller_for(player_id: String) -> PlayerController:
	var config: Dictionary = _controller_config.get(player_id, {})
	var controller_type := str(config.get("controller", PlayerController.CONTROLLER_HUMAN))
	match controller_type:
		PlayerController.CONTROLLER_AI_SIMPLE:
			var ai_controller := AIController.new()
			ai_controller.controller_type = PlayerController.CONTROLLER_AI_SIMPLE
			return ai_controller
		_:
			var human_controller := HumanController.new()
			human_controller.controller_type = PlayerController.CONTROLLER_HUMAN
			return human_controller

func advance_phase() -> Dictionary:
	if _has_winner() or _has_pending_gate():
		return {"ok": false, "reason": "blocked"}
	if game_state.phase == UATypes.Phase.END:
		effect_resolver.cleanup_turn_expirations(game_state, game_state.active_player_id)
		game_state.battle_context = {}
		if _enqueue_hand_limit_discard_if_needed(game_state.active_player_id):
			emit_state_changed()
			return {"ok": true, "pending_gate": true}
	_apply_logs(turn_manager.advance_phase(game_state))
	emit_state_changed()
	return {"ok": true}

func request_bonus_draw() -> Dictionary:
	if _has_winner() or _has_pending_gate():
		return {"ok": false, "reason": "blocked"}
	_apply_logs(turn_manager.request_bonus_draw(game_state))
	emit_state_changed()
	return {"ok": true}

# Unified card-play entry point used by the UI.
func play_card(card_uid: String, target_zone: int, options: Dictionary = {}) -> Dictionary:
	if _has_winner() or (_has_pending_gate() and not bool(options.get("ignore_pending_gate", false))):
		return {"ok": false, "reason": "blocked"}
	var acting_player_id := str(options.get("player_id", game_state.active_player_id))
	var card: CardInstance = game_state.get_card(card_uid)
	if card == null:
		return {"ok": false, "reason": "missing_card"}
	var card_def: CardDef = game_state.get_card_def(card.def_id)
	if card_def == null:
		return {"ok": false, "reason": "missing_def"}
	var play_options := options.duplicate(true)
	if str(play_options.get("raid_target_uid", "")) != "":
		var raid_target: CardInstance = game_state.get_card(str(play_options.get("raid_target_uid", "")))
		if raid_target != null and raid_target.zone == UATypes.Zone.ENERGY_LINE and not play_options.has("raid_target_zone_choice"):
			_enqueue_pending_decision({
				"type": "RAID_ZONE_CHOICE",
				"owner_player_id": acting_player_id,
				"source_card_uid": card_uid,
				"choices": [
					{"label": "Stay Energy", "value": UATypes.Zone.ENERGY_LINE},
					{"label": "Move Front", "value": UATypes.Zone.FRONT_LINE},
				],
				"context": {
					"target_zone": target_zone,
					"raid_target_uid": str(play_options.get("raid_target_uid", "")),
				}
			})
			_apply_logs(["Choose raid destination for %s." % card_def.name])
			emit_state_changed()
			return {"ok": true, "pending_gate": true}
		if raid_target != null and raid_target.zone == UATypes.Zone.ENERGY_LINE and not play_options.has("raid_target_zone_choice"):
			play_options["raid_target_zone_choice"] = target_zone
	var play_modifiers := effect_resolver.preview_play_modifiers(game_state, acting_player_id, card_uid, {
		"target_player_id": acting_player_id,
		"target_zone": target_zone,
	})
	if bool(options.get("force_allow_current_zone", false)):
		play_modifiers["allow_current_zone"] = true
	var validation: Dictionary = rules_engine.can_play_card(game_state, acting_player_id, card_uid, target_zone, play_modifiers, play_options)
	if not bool(validation.get("ok", false)):
		_apply_logs(["Cannot play card: %s" % validation.get("reason", "unknown")])
		emit_state_changed()
		return validation
	var player: PlayerState = game_state.get_player(acting_player_id)
	var effective_cost_ap := int(validation.get("cost_ap", play_modifiers.get("cost_ap", card_def.cost_ap)))
	zone_manager.spend_ap(player, effective_cost_ap)
	var special_play: Dictionary = validation.get("special_play", {})
	match card_def.card_type:
		UATypes.CardType.CHARACTER, UATypes.CardType.FIELD:
			if str(special_play.get("mode", "NORMAL")) == "RAID":
				var raid_target_uid := str(special_play.get("raid_target_uid", ""))
				var raid_target_zone := int(special_play.get("target_zone", target_zone))
				var raid_result := zone_manager.stack_card_on_target(game_state, card_uid, raid_target_uid, raid_target_zone)
				if not bool(raid_result.get("ok", false)):
					_apply_logs(["Cannot play card: %s" % str(raid_result.get("reason", "raid_failed"))])
					emit_state_changed()
					return raid_result
				card.flags["entered_via_raid"] = true
				_apply_logs(["%s raids onto %s and stays in %s." % [card_def.name, raid_target_uid, UATypes.zone_to_key(raid_target_zone)]])
			else:
				zone_manager.move_card(game_state, card_uid, target_zone)
				card.state = UATypes.CardState.RESTED
				card.flags["entered_via_raid"] = false
				_apply_logs(["%s plays %s to %s." % [acting_player_id, card_def.name, UATypes.zone_to_key(target_zone)]])
			_apply_logs(effect_resolver.resolve_trigger(card_uid, UATypes.TriggerType.ON_ENTER, game_state, {"target_player_id": acting_player_id}))
		UATypes.CardType.EVENT:
			_apply_logs(["%s uses event %s." % [acting_player_id, card_def.name]])
			for effect_variant in card_def.effects:
				_apply_logs(effect_resolver.resolve_effect(game_state, card_uid, effect_variant, {"target_player_id": acting_player_id}))
			zone_manager.move_card(game_state, card_uid, UATypes.Zone.OUTSIDE)
	effect_resolver.commit_play_modifiers(game_state, play_modifiers)
	emit_state_changed()
	return {"ok": true}

func move_energy_to_front(card_uid: String) -> Dictionary:
	if _has_winner() or _has_pending_gate():
		return {"ok": false, "reason": "blocked"}
	var validation: Dictionary = rules_engine.can_move_energy_to_front(game_state, game_state.active_player_id, card_uid)
	if not bool(validation.get("ok", false)):
		_apply_logs(["Cannot move card: %s" % validation.get("reason", "unknown")])
		emit_state_changed()
		return validation
	zone_manager.move_card(game_state, card_uid, UATypes.Zone.FRONT_LINE)
	var card: CardInstance = game_state.get_card(card_uid)
	var card_def: CardDef = null
	if card != null:
		card_def = game_state.get_card_def(card.def_id)
	if card_def != null:
		_apply_logs(["%s moves %s from energy to front line." % [game_state.active_player_id, card_def.name]])
	emit_state_changed()
	return {"ok": true}

func request_attack(attacker_uid: String, options: Dictionary = {}) -> Dictionary:
	if _has_winner() or _has_pending_gate():
		return {"ok": false, "reason": "blocked"}
	var result: Dictionary = battle_resolver.declare_attack(game_state, attacker_uid, options)
	if not bool(result.get("ok", false)):
		_apply_logs(["Cannot attack: %s" % result.get("reason", "unknown")])
		emit_state_changed()
		return result
	# Entering the block window changes priority to the defender, so the UI must
	# receive a fresh snapshot before it decides whether human input is allowed.
	emit_state_changed()
	emit_signal("blockers_requested", result)
	return result

func resolve_attack(attacker_uid: String, blocker_uid := "") -> Dictionary:
	if _has_winner() or _has_pending_gate():
		return {"ok": false, "reason": "blocked"}
	_apply_logs(battle_resolver.resolve_attack(game_state, attacker_uid, blocker_uid))
	emit_state_changed()
	return {"ok": true}

func request_main_activate(card_uid: String, effect_index := 0) -> Dictionary:
	if _has_winner() or _has_pending_gate():
		return {"ok": false, "reason": "blocked"}
	_apply_logs(effect_resolver.activate_main_effect(game_state, game_state.active_player_id, card_uid, effect_index))
	emit_state_changed()
	return {"ok": true}

func request_step_move(card_uid: String, options: Dictionary = {}) -> Dictionary:
	if _has_winner() or _has_pending_gate():
		return {"ok": false, "reason": "blocked"}
	var swap_uid := str(options.get("swap_uid", ""))
	var validation := rules_engine.can_step_move_to_energy(game_state, game_state.active_player_id, card_uid, swap_uid)
	if not bool(validation.get("ok", false)):
		if str(validation.get("reason", "")) == "step_swap_required":
			var player: PlayerState = game_state.get_player(game_state.active_player_id)
			if player != null:
				var choices: Array[Dictionary] = []
				for energy_uid in player.energy_line:
					var energy_card := game_state.get_card(energy_uid)
					if energy_card == null:
						continue
					var energy_def := game_state.get_card_def(energy_card.def_id)
					choices.append({
						"label": energy_def.name if energy_def != null else energy_uid,
						"value": energy_uid,
					})
				_enqueue_pending_decision({
					"type": "STEP_SWAP_CHOICE",
					"owner_player_id": game_state.active_player_id,
					"source_card_uid": card_uid,
					"choices": choices,
					"context": {},
				})
				_apply_logs(["Choose an energy character to swap with STEP."])
				emit_state_changed()
				return {"ok": true, "pending_gate": true}
		_apply_logs(["Cannot step move: %s" % validation.get("reason", "unknown")])
		emit_state_changed()
		return validation
	var result := zone_manager.step_move_to_energy(game_state, card_uid, swap_uid)
	if not bool(result.get("ok", false)):
		_apply_logs(["Cannot step move: %s" % result.get("reason", "unknown")])
	else:
		var card := game_state.get_card(card_uid)
		var card_def := game_state.get_card_def(card.def_id) if card != null else null
		if bool(result.get("swapped", false)):
			var swap_card := game_state.get_card(str(result.get("swap_uid", "")))
			var swap_def := game_state.get_card_def(swap_card.def_id) if swap_card != null else null
			_apply_logs(["%s steps back to energy and swaps with %s." % [
				card_def.name if card_def != null else card_uid,
				swap_def.name if swap_def != null else str(result.get("swap_uid", "")),
			]])
		else:
			_apply_logs(["%s steps back to energy." % [card_def.name if card_def != null else card_uid]])
	emit_state_changed()
	return {"ok": true}

func execute_action(action: Dictionary) -> Dictionary:
	var action_type := str(action.get("type", ""))
	var params: Dictionary = action.get("params", {})
	match action_type:
		ActionTypes.PLAY_CARD:
			var play_options := {}
			for key in ["raid_target_uid", "raid_target_zone_choice", "allow_raid_play", "force_allow_current_zone", "ignore_pending_gate", "ignore_play_timing"]:
				if params.has(key):
					play_options[key] = params.get(key)
			play_options["player_id"] = str(action.get("player_id", game_state.active_player_id))
			return play_card(str(action.get("source_card_uid", "")), int(params.get("target_zone", UATypes.Zone.OUTSIDE)), play_options)
		ActionTypes.MOVE_CARD:
			var mode := str(params.get("mode", ""))
			if mode == ActionTypes.MOVE_ENERGY_TO_FRONT:
				return move_energy_to_front(str(action.get("source_card_uid", "")))
			if mode == ActionTypes.MOVE_STEP_TO_ENERGY:
				var step_options := {}
				if params.has("swap_uid"):
					step_options["swap_uid"] = str(params.get("swap_uid", ""))
				return request_step_move(str(action.get("source_card_uid", "")), step_options)
			return {"ok": false, "reason": "unsupported_move_mode"}
		ActionTypes.ATTACK:
			var attack_options := {}
			for key in ["target_kind", "target_uid"]:
				if params.has(key):
					attack_options[key] = params.get(key)
			return request_attack(str(action.get("source_card_uid", "")), attack_options)
		ActionTypes.BLOCK:
			return resolve_attack(str(params.get("attacker_uid", "")), str(params.get("blocker_uid", "")))
		ActionTypes.NO_BLOCK:
			return resolve_attack(str(params.get("attacker_uid", "")), "")
		ActionTypes.ACTIVATE_EFFECT:
			return request_main_activate(str(action.get("source_card_uid", "")), int(params.get("effect_index", 0)))
		ActionTypes.RESOLVE_PENDING_DECISION:
			var payload := {
				"source_card_uid": str(params.get("source_card_uid", "")),
				"choice": params.get("choice"),
			}
			if str(params.get("resolution_id", "")) != "":
				payload["resolution_id"] = str(params.get("resolution_id", ""))
			return resolve_pending_decision(str(params.get("decision_type", "")), payload)
		ActionTypes.RESOLVE_LIFE_TRIGGER:
			return resolve_life_trigger_decision(str(params.get("card_uid", "")), bool(params.get("activate", false)))
		ActionTypes.ADVANCE_PHASE:
			return advance_phase()
		ActionTypes.END_TURN:
			return advance_phase()
		ActionTypes.BONUS_DRAW:
			return request_bonus_draw()
	return {"ok": false, "reason": "unsupported_action_type"}

func resolve_pending_decision(decision_type: String, payload: Dictionary = {}) -> Dictionary:
	if _has_winner():
		return {"ok": false, "reason": "winner_exists"}
	var decision := _take_pending_decision(decision_type, payload)
	if decision.is_empty():
		_apply_logs(["Pending decision not found: %s" % decision_type])
		emit_state_changed()
		return {"ok": false, "reason": "pending_decision_not_found"}
	match decision_type:
		"MULLIGAN_CHOICE":
			_resolve_mulligan_decision(decision, payload)
			return {"ok": true}
		"RAID_ZONE_CHOICE":
			var play_options := {
				"raid_target_uid": str(decision.get("context", {}).get("raid_target_uid", "")),
				"raid_target_zone_choice": int(payload.get("choice", UATypes.Zone.ENERGY_LINE)),
				"allow_raid_play": bool(decision.get("context", {}).get("allow_raid_play", false)),
				"force_allow_current_zone": bool(decision.get("context", {}).get("force_allow_current_zone", false)),
				"ignore_pending_gate": bool(decision.get("context", {}).get("ignore_pending_gate", false)),
				"ignore_play_timing": bool(decision.get("context", {}).get("ignore_play_timing", false)),
				"player_id": str(decision.get("context", {}).get("player_id", game_state.active_player_id)),
			}
			play_card(str(decision.get("source_card_uid", "")), int(decision.get("context", {}).get("target_zone", UATypes.Zone.ENERGY_LINE)), play_options)
			if bool(decision.get("context", {}).get("finalize_life_damage", false)) and game_state.pending_life_triggers.is_empty() and game_state.pending_decisions.is_empty() and _life_reveal_fully_resolved():
				_apply_logs(effect_resolver.finalize_pending_life_damage(game_state))
				emit_state_changed()
			return {"ok": true}
		"LIFE_TRIGGER_RAID_CHOICE":
			_apply_logs(_resolve_life_trigger_raid_choice(decision, str(payload.get("choice", "ADD_TO_HAND"))))
			_maybe_finalize_life_damage_after_pending_resolution()
			emit_state_changed()
			return {"ok": true}
		"LIFE_TRIGGER_RAID_TARGET":
			_apply_logs(_resolve_life_trigger_raid_target(decision, str(payload.get("choice", ""))))
			_maybe_finalize_life_damage_after_pending_resolution()
			emit_state_changed()
			return {"ok": true}
		"STEP_SWAP_CHOICE":
			return request_step_move(str(decision.get("source_card_uid", "")), {"swap_uid": str(payload.get("choice", ""))})
		"HAND_LIMIT_DISCARD":
			_apply_logs(_resolve_hand_limit_discard(decision, str(payload.get("choice", ""))))
			_maybe_finalize_life_damage_after_pending_resolution()
			emit_state_changed()
			return {"ok": true}
		"ABILITY_TARGET_SELECTION":
			_apply_logs(effect_resolver.resolve_target_selection_decision(
				game_state,
				str(decision.get("resolution_id", "")),
				payload.get("choice", payload.get("choices", []))
			))
			_maybe_finalize_life_damage_after_pending_resolution()
			emit_state_changed()
			return {"ok": true}
		"TRIGGER_ORDER":
			_apply_logs(effect_resolver.resolve_trigger_order_decision(
				game_state,
				decision,
				str(payload.get("choice", ""))
			))
			_maybe_finalize_life_damage_after_pending_resolution()
			emit_state_changed()
			return {"ok": true}
	_apply_logs(["Unsupported decision type: %s" % decision_type])
	emit_state_changed()
	return {"ok": false, "reason": "unsupported_decision_type"}

func resolve_life_trigger_decision(card_uid: String, activate: bool) -> Dictionary:
	if _has_winner():
		return {"ok": false, "reason": "winner_exists"}
	_apply_logs(effect_resolver.resolve_life_trigger_decision(game_state, card_uid, activate))
	emit_state_changed()
	return {"ok": true}

func acknowledge_life_reveal(card_uid: String) -> Dictionary:
	if _has_winner():
		return {"ok": false, "reason": "winner_exists"}
	_apply_logs(effect_resolver.acknowledge_life_reveal(game_state, card_uid))
	emit_state_changed()
	return {"ok": true}

func get_snapshot() -> Dictionary:
	# Return a UI-facing snapshot instead of exposing raw runtime state.
	var action_player_id := _current_priority_player_id()
	var legal_actions := rules_engine.get_legal_actions(game_state, action_player_id)
	return {
		"turn_number": game_state.turn_number,
		"active_player_id": game_state.active_player_id,
		"priority_player_id": action_player_id,
		"phase": UATypes.phase_to_text(game_state.phase),
		"opening_complete": game_state.opening_complete,
		"can_bonus_draw": _can_active_player_bonus_draw(),
		"winner_player_id": game_state.winner_player_id,
		"battle_context": game_state.battle_context.duplicate(true),
		"last_battle_result": game_state.last_battle_result.duplicate(true),
		"effect_queue_count": game_state.effect_queue.size(),
		"pending_decisions": _serialize_pending_decisions(action_player_id),
		"pending_life_triggers": game_state.pending_life_triggers.duplicate(true),
		"life_reveal_modal": _serialize_life_reveal_modal(action_player_id),
		"controller_types": {
			UATypes.PLAYER_ONE: get_controller_type(UATypes.PLAYER_ONE),
			UATypes.PLAYER_TWO: get_controller_type(UATypes.PLAYER_TWO),
		},
		"action_player_controller": get_controller_type(action_player_id),
		"human_input_enabled": get_controller_type(action_player_id) == PlayerController.CONTROLLER_HUMAN,
		"legal_actions": legal_actions.duplicate(true),
		"players": {
			UATypes.PLAYER_ONE: _serialize_player(UATypes.PLAYER_ONE, action_player_id),
			UATypes.PLAYER_TWO: _serialize_player(UATypes.PLAYER_TWO, action_player_id)
		},
		"logs": game_state.logs.duplicate(),
	}

func emit_state_changed() -> void:
	emit_signal("state_changed", get_snapshot())
	_queue_controller_drive()

func append_ui_log(text: String) -> void:
	_apply_logs([text])
	emit_state_changed()
func _load_card_defs() -> void:
	_deck_card_lookup.clear()
	var json: Array = _read_json(CARD_DATA_PATH)
	for item in json:
		var item_dict: Dictionary = item
		var card_def: CardDef = CardDef.new().from_dict(item_dict)
		game_state.card_defs[card_def.id] = card_def
		_register_deck_lookup(card_def)

func _create_player(player_id: String, deck_list: Array) -> void:
	var player := PlayerState.new()
	player.player_id = player_id
	game_state.players[player_id] = player
	var counter := 0
	for def_id_variant in deck_list:
		var def_id := str(def_id_variant)
		var card_def: CardDef = game_state.get_card_def(def_id)
		if card_def == null:
			continue
		var card := CardInstance.new()
		card.uid = "%s_%03d" % [player_id, counter]
		card.def_id = def_id
		card.owner_player_id = player_id
		card.controller_player_id = player_id
		card.zone = UATypes.Zone.DECK
		card.state = UATypes.CardState.ACTIVE
		card.current_bp = card_def.bp
		game_state.cards[card.uid] = card
		player.deck.append(card.uid)
		counter += 1
	zone_manager.shuffle_zone(player, UATypes.Zone.DECK)
	if player.deck.size() != UATypes.MAIN_DECK_SIZE:
		_apply_logs(["Deck size warning for %s: expected 50, got %d." % [player_id, player.deck.size()]])

func _prepare_opening_hand(player_id: String) -> void:
	var player: PlayerState = game_state.get_player(player_id)
	if player == null:
		return
	for i in range(UATypes.STARTING_HAND):
		zone_manager.draw_card(game_state, player_id)
	_apply_logs(["%s draws %d cards for the opening hand." % [player_id, player.hand.size()]])

func _enqueue_mulligan_decision(player_id: String) -> void:
	var player: PlayerState = game_state.get_player(player_id)
	if player == null:
		return
	game_state.active_player_id = player_id
	game_state.priority_player_id = player_id
	game_state.phase = UATypes.Phase.START
	_enqueue_pending_decision({
		"type": "MULLIGAN_CHOICE",
		"owner_player_id": player_id,
		"source_card_uid": "",
		"choices": [
			{"label": "保留", "value": "keep"},
			{"label": "换牌", "value": "mulligan"},
		],
		"context": {},
	})
	_apply_logs(["%s chooses whether to mulligan the opening hand." % player_id])

func _resolve_mulligan_decision(decision: Dictionary, payload: Dictionary) -> void:
	var player_id := str(decision.get("owner_player_id", ""))
	var choice := str(payload.get("choice", "keep"))
	_apply_logs(_apply_mulligan_choice(player_id, choice == "mulligan"))
	if player_id == UATypes.PLAYER_ONE:
		_enqueue_mulligan_decision(UATypes.PLAYER_TWO)
	else:
		_finalize_opening_setup()
	emit_state_changed()

func _apply_mulligan_choice(player_id: String, wants_mulligan: bool) -> Array[String]:
	var logs: Array[String] = []
	var player: PlayerState = game_state.get_player(player_id)
	if player == null:
		return logs
	if not wants_mulligan:
		game_state.opening_mulligan_hands.erase(player_id)
		logs.append("%s keeps the opening hand." % player_id)
		return logs
	var old_hand: Array[String] = player.hand.duplicate()
	game_state.opening_mulligan_hands[player_id] = old_hand.duplicate()
	player.hand.clear()
	for i in range(UATypes.STARTING_HAND):
		zone_manager.draw_card(game_state, player_id)
	for old_uid in old_hand:
		player.deck.append(old_uid)
		var old_card: CardInstance = game_state.get_card(old_uid)
		if old_card != null:
			old_card.zone = UATypes.Zone.DECK
	zone_manager.shuffle_zone(player, UATypes.Zone.DECK)
	logs.append("%s mulligans, redraws 7, then shuffles the original hand back into the deck." % player_id)
	return logs

func _finalize_opening_setup() -> void:
	var logs: Array[String] = []
	for player_id in [UATypes.PLAYER_ONE, UATypes.PLAYER_TWO]:
		logs.append_array(_place_starting_life(player_id))
	game_state.opening_complete = true
	game_state.opening_mulligan_hands.clear()
	_apply_logs(logs)
	_apply_logs(turn_manager.begin_game(game_state))

func _place_starting_life(player_id: String) -> Array[String]:
	var logs: Array[String] = []
	var player: PlayerState = game_state.get_player(player_id)
	if player == null:
		return logs
	for i in range(UATypes.STARTING_LIFE):
		if player.deck.is_empty():
			break
		var card_uid: String = player.deck.pop_front()
		player.life.append(card_uid)
		var card: CardInstance = game_state.get_card(card_uid)
		if card != null:
			card.zone = UATypes.Zone.LIFE
	logs.append("%s places %d cards face down into life." % [player_id, player.life.size()])
	logs.append("%s starts with %d hand and %d life." % [player_id, player.hand.size(), player.life.size()])
	return logs

func _serialize_player(player_id: String, action_player_id: String) -> Dictionary:
	var player: PlayerState = game_state.get_player(player_id)
	if player == null:
		return {}
	return {
		"player_id": player.player_id,
		"controller_type": get_controller_type(player_id),
		"deck_count": player.deck.size(),
		"hand_count": player.hand.size(),
		"life_count": player.life.size(),
		"ap_total": player.ap_total(),
		"ap_active": player.ap_active_count(),
		"used_bonus_draw": player.used_bonus_draw,
		"available_energy": _energy_pool_for_player(player),
		"hand": _serialize_cards(player.hand, action_player_id),
		"life": _serialize_life_cards(player.life),
		"front_line": _serialize_cards(player.front_line, action_player_id),
		"energy_line": _serialize_cards(player.energy_line, action_player_id),
		"outside": _serialize_cards(player.outside, action_player_id),
		"removed": _serialize_cards(player.removed, action_player_id),
		"outside_count": player.outside.size(),
		"removed_count": player.removed.size(),
	}

func _serialize_cards(card_uids: Array[String], action_player_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for card_uid in card_uids:
		var serialized := _serialize_card(card_uid, action_player_id, true)
		if not serialized.is_empty():
			result.append(serialized)
	return result

func _serialize_pending_decisions(action_player_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for pending_variant in game_state.pending_decisions:
		var pending: Dictionary = (pending_variant as Dictionary).duplicate(true)
		var preview_card_uids: Array = pending.get("preview_card_uids", [])
		if not preview_card_uids.is_empty():
			pending["preview_cards"] = _serialize_card_list_for_ui(preview_card_uids, action_player_id)
		result.append(pending)
	return result

func _serialize_card_list_for_ui(card_uids: Array, action_player_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for card_uid_variant in card_uids:
		var serialized := _serialize_card(str(card_uid_variant), action_player_id, false)
		if not serialized.is_empty():
			result.append(serialized)
	return result

func _serialize_life_reveal_modal(action_player_id: String) -> Dictionary:
	if game_state.pending_life_reveal.is_empty():
		return {
			"visible": false,
			"player_id": "",
			"current_card_uid": "",
			"revealed_cards": [],
			"can_activate": false,
			"can_skip": false,
			"can_acknowledge": false,
		}
	var reveal: Dictionary = game_state.pending_life_reveal
	var current_card_uid := str(reveal.get("current_card_uid", ""))
	var result_cards: Array[Dictionary] = []
	for entry_variant in reveal.get("revealed_cards", []):
		var entry: Dictionary = entry_variant
		var card_uid := str(entry.get("card_uid", ""))
		var serialized := _serialize_card(card_uid, action_player_id, false)
		if serialized.is_empty():
			continue
		serialized["has_life_trigger"] = bool(entry.get("has_life_trigger", false))
		serialized["resolved"] = bool(entry.get("resolved", false))
		serialized["order_index"] = int(entry.get("order_index", result_cards.size()))
		serialized["is_current"] = card_uid == current_card_uid
		result_cards.append(serialized)
	var current_has_trigger := false
	for card_data_variant in result_cards:
		var card_data: Dictionary = card_data_variant
		if str(card_data.get("uid", "")) != current_card_uid:
			continue
		current_has_trigger = bool(card_data.get("has_life_trigger", false))
		break
	return {
		"visible": true,
		"player_id": str(reveal.get("player_id", "")),
		"current_card_uid": current_card_uid,
		"revealed_cards": result_cards,
		"can_activate": current_card_uid != "" and current_has_trigger,
		"can_skip": current_card_uid != "" and current_has_trigger,
		"can_acknowledge": current_card_uid != "" and not current_has_trigger,
	}

func _serialize_card(card_uid: String, action_player_id: String, include_actions: bool) -> Dictionary:
	var card: CardInstance = game_state.get_card(card_uid)
	var card_def: CardDef = null
	if card != null:
		card_def = game_state.get_card_def(card.def_id)
	if card == null or card_def == null:
		return {}
	var serialized := {
		"uid": card.uid,
		"name": card_def.name,
		"card_type": UATypes.card_type_to_text(card_def.card_type),
		"number": card_def.number,
		"source_image": card_def.source_image,
		"zone": UATypes.zone_to_key(card.zone),
		"state": UATypes.state_to_text(card.state),
		"base_bp": card_def.bp,
		"bp": card.current_bp,
		"cost_ap": card_def.cost_ap,
		"cost_energy": card_def.cost_energy.duplicate(true),
		"energy_provided": card_def.energy_provided.duplicate(true),
		"keywords": _runtime_keywords_for(card, card_def),
		"stacked_under": card.stacked_under.duplicate(),
		"flags": card.flags.duplicate(true),
	}
	if include_actions:
		serialized["available_actions"] = rules_engine.get_card_available_actions(game_state, action_player_id, card.uid)
	return serialized

func _serialize_life_cards(card_uids: Array[String]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in range(card_uids.size()):
		result.append({
			"uid": str(card_uids[i]),
			"zone": "life",
			"is_face_down": true,
			"index": i,
		})
	return result

func _apply_logs(logs: Array[String]) -> void:
	for line in logs:
		game_state.add_log(line)
		emit_signal("log_added", line)

func _load_deck_list(path: String) -> Array:
	if path.get_extension().to_lower() == "txt":
		return _read_text_deck(path)
	return _read_json(path)

func _read_text_deck(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open %s" % path)
		return []
	var result: Array = []
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var expanded := _expand_deck_line(line)
		if expanded.is_empty():
			push_error("Failed to parse deck line: %s" % line)
			continue
		result.append_array(expanded)
	return result

func _expand_deck_line(line: String) -> Array:
	var split_index := line.find("x")
	if split_index <= 0:
		return []
	var count := int(line.substr(0, split_index))
	var raw_code := line.substr(split_index + 1).strip_edges()
	if count <= 0 or raw_code == "":
		return []
	var def_id := _resolve_deck_card_id(raw_code)
	if def_id == "":
		push_error("Missing card definition for deck code: %s" % raw_code)
		return []
	var expanded: Array = []
	for i in range(count):
		expanded.append(def_id)
	return expanded

func _resolve_deck_card_id(raw_code: String) -> String:
	var normalized_candidates := [
		raw_code,
		raw_code.replace("/", "_").replace("-", "_"),
		raw_code.replace("_", "/"),
	]
	for candidate_variant in normalized_candidates:
		var candidate := str(candidate_variant)
		if _deck_card_lookup.has(candidate):
			return str(_deck_card_lookup[candidate])
	return ""

func _register_deck_lookup(card_def: CardDef) -> void:
	if card_def.id != "":
		_deck_card_lookup[card_def.id] = card_def.id
		_deck_card_lookup[card_def.id.replace("/", "_").replace("-", "_")] = card_def.id
	if card_def.number != "":
		_deck_card_lookup[card_def.number] = card_def.id
		_deck_card_lookup[card_def.number.replace("/", "_")] = card_def.id
		_deck_card_lookup[card_def.number.replace("/", "_").replace("-", "_")] = card_def.id

func _read_json(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open %s" % path)
		return []
	var data_text := file.get_as_text()
	var parsed = JSON.parse_string(data_text)
	if parsed == null:
		push_error("Failed to parse JSON: %s" % path)
		return []
	return parsed

func _has_winner() -> bool:
	return game_state.winner_player_id != ""

func _has_pending_life_triggers() -> bool:
	return not game_state.pending_life_triggers.is_empty()

func _has_pending_life_reveal() -> bool:
	return not game_state.pending_life_reveal.is_empty()

func _has_pending_decisions() -> bool:
	return not game_state.pending_decisions.is_empty()

func _life_reveal_fully_resolved() -> bool:
	if game_state.pending_life_reveal.is_empty():
		return true
	for entry_variant in game_state.pending_life_reveal.get("revealed_cards", []):
		var entry: Dictionary = entry_variant
		if not bool(entry.get("resolved", false)):
			return false
	return true

func _maybe_finalize_life_damage_after_pending_resolution() -> void:
	if not _life_reveal_fully_resolved():
		return
	if not game_state.pending_life_triggers.is_empty() or not game_state.pending_decisions.is_empty():
		return
	_apply_logs(effect_resolver.finalize_pending_life_damage(game_state))

func _has_pending_gate() -> bool:
	return _has_pending_life_triggers() or _has_pending_life_reveal() or _has_pending_decisions()

func _current_priority_player_id() -> String:
	if not game_state.pending_decisions.is_empty():
		return str((game_state.pending_decisions[0] as Dictionary).get("owner_player_id", game_state.active_player_id))
	if not game_state.pending_life_triggers.is_empty():
		return str((game_state.pending_life_triggers[0] as Dictionary).get("player_id", game_state.active_player_id))
	if not game_state.pending_life_reveal.is_empty():
		return str(game_state.pending_life_reveal.get("player_id", game_state.active_player_id))
	if not game_state.battle_context.is_empty():
		var battle_context: Dictionary = game_state.battle_context
		if str(battle_context.get("target_kind", "PLAYER")) == "PLAYER" and not bool(battle_context.get("is_sniper_attack", false)):
			return str(battle_context.get("defender_player_id", game_state.active_player_id))
	return game_state.active_player_id

func _queue_controller_drive() -> void:
	if _controller_drive_in_progress or _controller_drive_pending:
		return
	_controller_drive_pending = true
	call_deferred("_process_controller_drive")

func drive_controllers(max_steps := 64) -> void:
	_drive_controllers(max_steps)

func _process_controller_drive() -> void:
	if _controller_drive_in_progress:
		return
	_controller_drive_pending = false
	_drive_controllers(64)

func _drive_controllers(max_steps: int) -> void:
	_controller_drive_in_progress = true
	var safety := max_steps
	while safety > 0:
		if _has_winner():
			break
		var player_id := _current_priority_player_id()
		var controller: PlayerController = _controllers.get(player_id)
		if controller == null or controller.is_human():
			break
		if _has_pending_life_reveal() and not _has_pending_life_triggers():
			var current_card_uid := str(game_state.pending_life_reveal.get("current_card_uid", ""))
			if current_card_uid == "":
				break
			acknowledge_life_reveal(current_card_uid)
			safety -= 1
			continue
		var legal_actions := rules_engine.get_legal_actions(game_state, player_id)
		if legal_actions.is_empty():
			break
		var snapshot := get_snapshot()
		var chosen_action := {}
		if _has_pending_gate() or not game_state.battle_context.is_empty():
			chosen_action = controller.request_pending_decision(game_state, snapshot, _current_pending_context(), legal_actions)
		else:
			chosen_action = controller.request_action(game_state, snapshot, legal_actions)
		if chosen_action.is_empty():
			break
		execute_action(chosen_action)
		safety -= 1
	_controller_drive_in_progress = false
	if _controller_drive_pending and not _has_winner():
		call_deferred("_process_controller_drive")

func _current_pending_context() -> Dictionary:
	if not game_state.pending_decisions.is_empty():
		return (game_state.pending_decisions[0] as Dictionary).duplicate(true)
	if not game_state.pending_life_triggers.is_empty():
		return (game_state.pending_life_triggers[0] as Dictionary).duplicate(true)
	if not game_state.pending_life_reveal.is_empty():
		return game_state.pending_life_reveal.duplicate(true)
	if not game_state.battle_context.is_empty():
		return game_state.battle_context.duplicate(true)
	return {}

func _can_active_player_bonus_draw() -> bool:
	if game_state.phase != UATypes.Phase.DRAW:
		return false
	var player: PlayerState = game_state.get_player(game_state.active_player_id)
	if player == null:
		return false
	return not player.used_bonus_draw and player.ap_active_count() >= 1

func _enqueue_pending_decision(decision: Dictionary) -> void:
	game_state.pending_decisions.append(decision)

func _take_pending_decision(decision_type: String, payload: Dictionary) -> Dictionary:
	var source_card_uid := str(payload.get("source_card_uid", ""))
	var resolution_id := str(payload.get("resolution_id", ""))
	for i in range(game_state.pending_decisions.size()):
		var decision: Dictionary = game_state.pending_decisions[i]
		if str(decision.get("type", "")) != decision_type:
			continue
		if resolution_id != "" and str(decision.get("resolution_id", "")) != resolution_id:
			continue
		if source_card_uid != "" and str(decision.get("source_card_uid", "")) != source_card_uid:
			continue
		game_state.pending_decisions.remove_at(i)
		return decision
	return {}

func _energy_pool_for_player(player: PlayerState) -> Dictionary:
	var pool := {}
	for card_uid in player.energy_line:
		var card: CardInstance = game_state.get_card(card_uid)
		var card_def: CardDef = game_state.get_card_def(card.def_id) if card != null else null
		if card_def == null:
			continue
		for color in card_def.energy_provided.keys():
			pool[color] = int(pool.get(color, 0)) + int(card_def.energy_provided.get(color, 0))
	for modifier_variant in game_state.static_modifiers:
		var modifier: Dictionary = modifier_variant
		if str(modifier.get("modifier_type", "")) != "ENERGY_BONUS":
			continue
		if str(modifier.get("owner_player_id", "")) != player.player_id:
			continue
		var source_uid := str(modifier.get("source_card_uid", ""))
		var source_card: CardInstance = game_state.get_card(source_uid)
		if source_card == null or source_card.zone != UATypes.Zone.ENERGY_LINE:
			continue
		if not _check_energy_bonus_condition(modifier, source_uid):
			continue
		var color := str(modifier.get("color", ""))
		var value := int(modifier.get("value", 0))
		if color != "" and value != 0:
			pool[color] = int(pool.get(color, 0)) + value
	return pool

func _check_energy_bonus_condition(modifier: Dictionary, source_uid: String) -> bool:
	var while_reqs: Array = modifier.get("while", [])
	if while_reqs.is_empty():
		return true
	var source_card: CardInstance = game_state.get_card(source_uid)
	if source_card == null:
		return false
	var player = game_state.get_player(source_card.controller_player_id)
	if player == null:
		return false
	for req_variant in while_reqs:
		var req: Dictionary = req_variant
		if str(req.get("type", "")) == "CONTROLLER_TRAIT_NAME_COUNT_GTE":
			var trait_value := str(req.get("trait", ""))
			var min_count := int(req.get("value", 0))
			var unique_names: Dictionary = {}
			for zone_cards in [player.front_line, player.energy_line]:
				for cuid_v in zone_cards:
					var cuid := str(cuid_v)
					if cuid == source_uid:
						continue
					var c = game_state.get_card(cuid)
					if c == null:
						continue
					var d = game_state.get_card_def(c.def_id)
					if d != null and d.traits.has(trait_value):
						unique_names[d.name] = true
			if unique_names.size() < min_count:
				return false
	return true

func _available_actions_for_card(card: CardInstance, card_def: CardDef) -> Array[String]:
	var actions: Array[String] = []
	if card.controller_player_id != game_state.active_player_id:
		return actions

	# 处理手牌
	if card.zone == UATypes.Zone.HAND and game_state.phase == UATypes.Phase.MAIN:
		match card_def.card_type:
			UATypes.CardType.CHARACTER:
				if _can_play_to_front_line(card, card_def):
					actions.append("PLAY_FRONT")
				if _can_play_to_energy_line(card, card_def):
					actions.append("PLAY_ENERGY")
			UATypes.CardType.FIELD:
				if _can_play_to_energy_line(card, card_def):
					actions.append("PLAY_ENERGY")
			UATypes.CardType.EVENT:
				actions.append("PLAY_EVENT")
		# RAID打出检查
		if _can_play_raid_from_hand(card, card_def):
			actions.append("RAID")
		return actions

	# 处理场上卡牌
	if card.zone == UATypes.Zone.FRONT_LINE and game_state.phase == UATypes.Phase.ATTACK:
		var attack_result := rules_engine.can_attack(game_state, card.controller_player_id, card.uid)
		if bool(attack_result.get("ok", false)):
			actions.append("ATTACK_PLAYER")
		if _card_has_runtime_keyword(card, card_def, "SNIPER"):
			actions.append("SNIPER_ATTACK")
	if card.zone == UATypes.Zone.FRONT_LINE and game_state.phase == UATypes.Phase.MOVE:
		var step_result := rules_engine.can_step_move_to_energy(game_state, card.controller_player_id, card.uid)
		if bool(step_result.get("ok", false)) or str(step_result.get("reason", "")) == "step_swap_required":
			actions.append("STEP_TO_ENERGY")
	if card.zone == UATypes.Zone.ENERGY_LINE and game_state.phase == UATypes.Phase.MOVE:
		var move_result := rules_engine.can_move_energy_to_front(game_state, card.controller_player_id, card.uid)
		if bool(move_result.get("ok", false)):
			actions.append("MOVE_TO_FRONT")
	if game_state.phase == UATypes.Phase.MAIN:
		for effect_variant in card_def.trigger_effects:
			var effect: Dictionary = effect_variant
			if str(effect.get("trigger", "")) == "MAIN_ACTIVATE":
				actions.append("MAIN_ACTIVATE")
				break
	return actions

func _resolve_life_trigger_raid_choice(decision: Dictionary, choice: String) -> Array[String]:
	var logs: Array[String] = []
	var card_uid := str(decision.get("source_card_uid", ""))
	var owner_player_id := str(decision.get("owner_player_id", ""))
	if card_uid == "" or owner_player_id == "":
		return ["Life trigger raid choice failed: missing card or owner."]
	if choice == "ADD_TO_HAND":
		_move_pending_life_card_to_hand(card_uid, owner_player_id)
		var card = game_state.get_card(card_uid)
		var card_def = game_state.get_card_def(card.def_id) if card != null else null
		logs.append("%s adds %s to hand." % [owner_player_id, card_def.name if card_def != null else card_uid])
		if game_state.pending_life_triggers.is_empty() and _life_reveal_fully_resolved():
			logs.append_array(effect_resolver.finalize_pending_life_damage(game_state))
		return logs
	if choice != "RAID_NOW":
		return ["Life trigger raid choice failed: unsupported choice."]
	var raid_choices := _build_life_trigger_raid_target_choices(card_uid, owner_player_id)
	var enabled_choices: Array[Dictionary] = []
	for choice_variant in raid_choices:
		var raid_choice: Dictionary = choice_variant
		if bool(raid_choice.get("enabled", true)):
			enabled_choices.append(raid_choice)
	if enabled_choices.is_empty():
		return ["Life trigger raid choice failed: no legal raid target."]
	_enqueue_pending_decision({
		"type": "LIFE_TRIGGER_RAID_TARGET",
		"owner_player_id": owner_player_id,
		"source_card_uid": card_uid,
		"choices": raid_choices,
		"context": {
			"allow_raid_play": true,
		},
	})
	logs.append("Choose a raid target.")
	return logs

func _resolve_life_trigger_raid_target(decision: Dictionary, raid_target_uid: String) -> Array[String]:
	var logs: Array[String] = []
	var card_uid := str(decision.get("source_card_uid", ""))
	if card_uid == "" or raid_target_uid == "":
		return ["Life trigger raid target failed: missing card or target."]
	var raid_target = game_state.get_card(raid_target_uid)
	if raid_target == null:
		return ["Life trigger raid target failed: target not found."]
	if raid_target.zone == UATypes.Zone.ENERGY_LINE:
		_move_pending_life_card_to_hand(card_uid, str(decision.get("owner_player_id", "")))
		_enqueue_pending_decision({
			"type": "RAID_ZONE_CHOICE",
			"owner_player_id": str(decision.get("owner_player_id", "")),
			"source_card_uid": card_uid,
			"choices": [
				{"label": "Stay Energy", "value": UATypes.Zone.ENERGY_LINE},
				{"label": "Move Front", "value": UATypes.Zone.FRONT_LINE},
			],
			"context": {
				"target_zone": UATypes.Zone.ENERGY_LINE,
				"raid_target_uid": raid_target_uid,
				"allow_raid_play": true,
				"force_allow_current_zone": true,
				"ignore_pending_gate": true,
				"ignore_play_timing": true,
				"player_id": str(decision.get("owner_player_id", "")),
				"finalize_life_damage": true,
			}
		})
		logs.append("Choose raid destination.")
		return logs
	_move_pending_life_card_to_hand(card_uid, str(decision.get("owner_player_id", "")))
	play_card(card_uid, UATypes.Zone.FRONT_LINE, {
		"raid_target_uid": raid_target_uid,
		"raid_target_zone_choice": UATypes.Zone.FRONT_LINE,
		"allow_raid_play": true,
		"force_allow_current_zone": true,
		"ignore_pending_gate": true,
		"ignore_play_timing": true,
		"player_id": str(decision.get("owner_player_id", "")),
	})
	if game_state.pending_life_triggers.is_empty() and game_state.pending_decisions.is_empty() and _life_reveal_fully_resolved():
		logs.append_array(effect_resolver.finalize_pending_life_damage(game_state))
	return logs

func _build_life_trigger_raid_target_choices(card_uid: String, owner_player_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var card = game_state.get_card(card_uid)
	var card_def = game_state.get_card_def(card.def_id) if card != null else null
	if card == null or card_def == null:
		return result
	var required_name := str(card_def.special_play_rule.get("raid_target_name", ""))
	var player: PlayerState = game_state.get_player(owner_player_id)
	if player == null:
		return result
	for zone_cards in [player.front_line, player.energy_line]:
		for candidate_uid_variant in zone_cards:
			var candidate_uid := str(candidate_uid_variant)
			var candidate_card = game_state.get_card(candidate_uid)
			var candidate_def = game_state.get_card_def(candidate_card.def_id) if candidate_card != null else null
			if candidate_card == null or candidate_def == null:
				continue
			if candidate_def.card_type != UATypes.CardType.CHARACTER:
				continue
			if required_name != "" and candidate_def.name != required_name:
				continue
			var validation := rules_engine.can_play_card(game_state, owner_player_id, card_uid, UATypes.Zone.FRONT_LINE, {"allow_current_zone": true}, {
				"raid_target_uid": candidate_uid,
				"raid_target_zone_choice": UATypes.Zone.FRONT_LINE if candidate_card.zone == UATypes.Zone.FRONT_LINE else UATypes.Zone.ENERGY_LINE,
				"allow_raid_play": true,
				"ignore_play_timing": true,
			})
			result.append({
				"label": candidate_def.name,
				"value": candidate_uid,
				"enabled": bool(validation.get("ok", false)),
				"reason": "" if bool(validation.get("ok", false)) else str(validation.get("reason", "")),
			})
	return result

func _move_pending_life_card_to_hand(card_uid: String, owner_player_id: String) -> void:
	for i in range(game_state.pending_life_damage_cards.size()):
		var entry: Dictionary = game_state.pending_life_damage_cards[i]
		if str(entry.get("card_uid", "")) != card_uid:
			continue
		game_state.pending_life_damage_cards.remove_at(i)
		break
	zone_manager.move_card(game_state, card_uid, UATypes.Zone.HAND, owner_player_id)

func _runtime_keywords_for(card: CardInstance, card_def: CardDef) -> Array:
	var keywords: Array = card_def.keywords.duplicate()
	for value in card.flags.get("temp_keywords", []):
		var keyword := str(value)
		if keyword != "" and not keywords.has(keyword):
			keywords.append(keyword)
	return keywords

func _card_has_runtime_keyword(card: CardInstance, card_def: CardDef, keyword: String) -> bool:
	if card_def.keywords.has(keyword):
		return true
	var temp_keywords: Array = card.flags.get("temp_keywords", [])
	return temp_keywords.has(keyword)

func _enqueue_hand_limit_discard_if_needed(player_id: String) -> bool:
	if not turn_manager.needs_hand_limit_discard(game_state, player_id):
		return false
	var player: PlayerState = game_state.get_player(player_id)
	if player == null:
		return false
	var excess := player.hand.size() - UATypes.HAND_LIMIT
	_enqueue_pending_decision({
		"type": "HAND_LIMIT_DISCARD",
		"owner_player_id": player_id,
		"source_card_uid": "",
		"choices": turn_manager.build_hand_limit_choices(game_state, player_id),
		"context": {
			"remaining_discards": excess,
		},
	})
	_apply_logs(["%s must discard %d card(s) to outside for hand limit." % [player_id, excess]])
	return true

func _resolve_hand_limit_discard(decision: Dictionary, chosen_card_uid: String) -> Array[String]:
	var logs: Array[String] = []
	var player_id := str(decision.get("owner_player_id", ""))
	if player_id == "" or chosen_card_uid == "":
		return ["Hand limit discard failed: missing player or choice."]
	logs.append_array(turn_manager.discard_for_hand_limit(game_state, player_id, chosen_card_uid))
	if turn_manager.needs_hand_limit_discard(game_state, player_id):
		_enqueue_hand_limit_discard_if_needed(player_id)
		return logs
	logs.append_array(turn_manager.end_turn(game_state))
	return logs

func _can_play_raid_from_hand(card: CardInstance, card_def: CardDef) -> bool:
	if card_def.special_play_rule.is_empty():
		return false
	if str(card_def.special_play_rule.get("type", "")) != "RAID":
		return false
	if not bool(card_def.special_play_rule.get("allow_from_hand", false)):
		return false
	if bool(card_def.special_play_rule.get("life_trigger_only", false)) and not _has_special_play_permission(card.controller_player_id, card.uid, "RAID"):
		return false
	var player: PlayerState = game_state.get_player(card.controller_player_id)
	if player == null:
		return false
	if not _can_pay_ap_for_card(player, card_def):
		return false
	if not _has_required_energy_for_card(card_def):
		return false
	return _has_valid_raid_target(card, card_def)

func _has_special_play_permission(player_id: String, card_uid: String, mode: String) -> bool:
	for modifier_variant in game_state.static_modifiers:
		var modifier: Dictionary = modifier_variant
		if str(modifier.get("modifier_type", "")) != "SPECIAL_PLAY_PERMISSION":
			continue
		if str(modifier.get("owner_player_id", "")) != player_id:
			continue
		if str(modifier.get("granted_card_uid", "")) != card_uid:
			continue
		var allowed_modes: Array = modifier.get("allowed_modes", [])
		if not allowed_modes.has(mode):
			continue
		return true
	return false

func _has_valid_raid_target(card: CardInstance, card_def: CardDef) -> bool:
	var player: PlayerState = game_state.get_player(card.controller_player_id)
	if player == null:
		return false
	var required_name := str(card_def.special_play_rule.get("raid_target_name", ""))
	for zone_cards in [player.front_line, player.energy_line]:
		for candidate_uid in zone_cards:
			var candidate = game_state.get_card(str(candidate_uid))
			var candidate_def = game_state.get_card_def(candidate.def_id) if candidate != null else null
			if candidate == null or candidate_def == null:
				continue
			if candidate_def.card_type != UATypes.CardType.CHARACTER:
				continue
			if required_name != "" and candidate_def.name != required_name:
				continue
			return true
	return false

func _can_play_to_front_line(card: CardInstance, card_def: CardDef) -> bool:
	var player: PlayerState = game_state.get_player(card.controller_player_id)
	if player == null:
		return false
	if player.front_line.size() >= UATypes.MAX_FRONT_LINE:
		return false
	if not _can_pay_ap_for_card(player, card_def):
		return false
	if not _has_required_energy_for_card(card_def):
		return false
	return true

func _can_play_to_energy_line(card: CardInstance, card_def: CardDef) -> bool:
	var player: PlayerState = game_state.get_player(card.controller_player_id)
	if player == null:
		return false
	if player.energy_line.size() >= UATypes.MAX_ENERGY_LINE:
		return false
	if not _can_pay_ap_for_card(player, card_def):
		return false
	if not _has_required_energy_for_card(card_def):
		return false
	return true

func _can_pay_ap_for_card(player: PlayerState, card_def: CardDef) -> bool:
	return player.ap_active_count() >= card_def.cost_ap

func _has_required_energy_for_card(card_def: CardDef) -> bool:
	return rules_engine._has_required_energy(game_state, game_state.get_player(game_state.active_player_id), card_def.cost_energy)
