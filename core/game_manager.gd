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
const DecisionManager = preload("res://core/decision_manager.gd")
const PlayerState = preload("res://data/player_state.gd")
const CardInstance = preload("res://data/card_instance.gd")
const CardDef = preload("res://data/card_def.gd")
const CardCatalog = preload("res://data/card_catalog.gd")
const ActionTypes = preload("res://core/actions/action_types.gd")
const PlayerController = preload("res://core/controllers/player_controller.gd")
const HumanController = preload("res://core/controllers/human_controller.gd")
const AIController = preload("res://core/controllers/ai_controller.gd")
const ControllerManager = preload("res://core/controllers/controller_manager.gd")
const SnapshotSerializer = preload("res://core/ui/snapshot_serializer.gd")
const LifeTriggerManager = preload("res://core/life_trigger_manager.gd")

signal state_changed(snapshot: Dictionary)
signal blockers_requested(request: Dictionary)
signal log_added(text: String)
signal ai_action_executed(action_info: Dictionary)

const STARTER_A_PATH := "res://data/decks/starter_a.txt"
const STARTER_B_PATH := "res://data/decks/starter_b.txt"
const DECKS_DIR_PATH := "res://data/decks"

@export_enum("HUMAN", "AI_SIMPLE") var player_one_controller_type := PlayerController.CONTROLLER_HUMAN
@export_enum("HUMAN", "AI_SIMPLE") var player_two_controller_type := PlayerController.CONTROLLER_AI_SIMPLE
@export var ai_action_delay := 0.3

var game_state := GameState.new()
var zone_manager := ZoneManager.new()
var victory_checker := VictoryChecker.new()
var rules_engine := RulesEngine.new(zone_manager)
var effect_resolver := EffectResolver.new(zone_manager, victory_checker, rules_engine)
var battle_resolver := BattleResolver.new(rules_engine, zone_manager, effect_resolver)
var turn_manager := TurnManager.new(zone_manager, victory_checker, effect_resolver)
var decision_manager := DecisionManager.new()
var controller_manager := ControllerManager.new()
var snapshot_serializer: SnapshotSerializer
var life_trigger_manager: LifeTriggerManager
var _deck_card_lookup := {}
var _card_catalog := CardCatalog.new()

func _ready() -> void:
	randomize()
	_initialize_extracted_managers()
	_initialize_controller_manager()


func _initialize_extracted_managers() -> void:
	snapshot_serializer = SnapshotSerializer.new(rules_engine, self)
	life_trigger_manager = LifeTriggerManager.new(effect_resolver, zone_manager, rules_engine, self)
	life_trigger_manager.set_callbacks(
		_enqueue_pending_decision,
		_play_card_for_life_trigger
	)


func _play_card_for_life_trigger(card_uid: String, target_zone: int, options: Dictionary) -> Dictionary:
	return play_card(card_uid, target_zone, options)


func _ensure_extracted_managers_initialized() -> void:
	if snapshot_serializer == null or life_trigger_manager == null:
		_initialize_extracted_managers()


func _initialize_controller_manager() -> void:
	controller_manager.player_one_controller_type = player_one_controller_type
	controller_manager.player_two_controller_type = player_two_controller_type
	controller_manager.game_state = game_state
	controller_manager.action_executor = _execute_controller_action
	controller_manager.legal_actions_provider = _get_controller_legal_actions
	controller_manager.snapshot_provider = get_snapshot
	controller_manager.winner_checker = _has_winner
	controller_manager.pending_gate_checker = _has_pending_gate
	controller_manager.priority_player_provider = _current_priority_player_id
	controller_manager.pending_context_provider = _current_pending_context
	controller_manager.life_reveal_refresher = _refresh_life_reveal_waiting_for_player
	controller_manager.life_reveal_waiting_checker = _is_life_reveal_waiting_for_player
	controller_manager.scene_tree = get_tree() if is_inside_tree() else null
	controller_manager.ai_action_delay_seconds = ai_action_delay
	controller_manager.ai_action_emitter = _emit_ai_action_executed


func _execute_controller_action(action: Dictionary) -> void:
	execute_action(action)


func _emit_ai_action_executed(action_info: Dictionary) -> void:
	emit_signal("ai_action_executed", action_info)


func _get_controller_legal_actions(_game_state, player_id: String) -> Array[Dictionary]:
	return rules_engine.get_legal_actions(game_state, player_id)


func _is_life_reveal_waiting_for_player() -> bool:
	return life_trigger_manager.is_life_reveal_waiting_for_player(game_state)


func life_reveal_requires_view_confirmation(card_uid: String) -> bool:
	return life_trigger_manager.life_reveal_requires_view_confirmation(game_state, card_uid, controller_manager.is_human)

# Initialize a fresh game state, decks, starting hands, and opening turn.
func setup_game(setup_config: Dictionary = {}) -> void:
	_ensure_extracted_managers_initialized()
	game_state = GameState.new()
	controller_manager.game_state = game_state
	controller_manager.reset_state(_extract_controller_config(setup_config))
	_load_card_defs()
	var player_deck_paths := _extract_player_deck_paths(setup_config)
	var starter_a: Array = _load_deck_list(str(player_deck_paths.get(UATypes.PLAYER_ONE, STARTER_A_PATH)))
	var starter_b: Array = _load_deck_list(str(player_deck_paths.get(UATypes.PLAYER_TWO, STARTER_B_PATH)))
	_create_player(UATypes.PLAYER_ONE, starter_a)
	_create_player(UATypes.PLAYER_TWO, starter_b)
	_prepare_opening_hand(UATypes.PLAYER_ONE)
	_prepare_opening_hand(UATypes.PLAYER_TWO)
	_enqueue_mulligan_decision(UATypes.PLAYER_ONE)
	emit_state_changed()

func get_available_decks() -> Array[Dictionary]:
	var deck_files: Array[String] = []
	for file_name_variant in DirAccess.get_files_at(DECKS_DIR_PATH):
		var file_name := str(file_name_variant)
		if file_name.get_extension().to_lower() != "txt":
			continue
		deck_files.append(file_name)
	deck_files.sort()
	var decks: Array[Dictionary] = []
	for file_name in deck_files:
		decks.append({
			"name": file_name.get_basename(),
			"file_name": file_name,
			"path": "%s/%s" % [DECKS_DIR_PATH, file_name],
		})
	return decks

func set_controller_config(controller_config: Dictionary) -> void:
	controller_manager.reset_state(controller_config)

func get_controller_type(player_id: String) -> String:
	return controller_manager.get_controller_type(player_id)

func _extract_controller_config(setup_config: Dictionary) -> Dictionary:
	var controller_config := {}
	for key_variant in setup_config.keys():
		var key := str(key_variant)
		if key == UATypes.PLAYER_ONE or key == UATypes.PLAYER_TWO:
			controller_config[key] = (setup_config[key_variant] as Dictionary).duplicate(true)
	return controller_config

func _extract_player_deck_paths(setup_config: Dictionary) -> Dictionary:
	var player_deck_paths := {
		UATypes.PLAYER_ONE: STARTER_A_PATH,
		UATypes.PLAYER_TWO: STARTER_B_PATH,
	}
	var deck_config: Dictionary = setup_config.get("player_decks", {})
	for player_id in [UATypes.PLAYER_ONE, UATypes.PLAYER_TWO]:
		var configured_path := str(deck_config.get(player_id, ""))
		if configured_path != "":
			player_deck_paths[player_id] = configured_path
	return player_deck_paths

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
	var played_from_zone := card.zone
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
		"target_uid": str(options.get("target_uid", "")),
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
				card.flags["entered_this_turn"] = true
				card.flags["entered_from_zone_this_turn"] = played_from_zone
				card.flags["entered_via_raid"] = true
				_apply_logs(["%s raids onto %s and stays in %s." % [card_def.name, raid_target_uid, UATypes.zone_to_key(raid_target_zone)]])
			else:
				zone_manager.move_card(game_state, card_uid, target_zone)
				card.state = _play_enter_state_for(card_def)
				card.flags["entered_this_turn"] = true
				card.flags["entered_from_zone_this_turn"] = played_from_zone
				card.flags["entered_via_raid"] = false
				_apply_logs(["%s plays %s to %s." % [acting_player_id, card_def.name, UATypes.zone_to_key(target_zone)]])
			_apply_logs(effect_resolver.resolve_trigger(card_uid, UATypes.TriggerType.ON_ENTER, game_state, {"target_player_id": acting_player_id}))
		UATypes.CardType.EVENT:
			card.flags["entered_from_zone_this_turn"] = played_from_zone
			_apply_logs(["%s uses event %s." % [acting_player_id, card_def.name]])
			for effect_variant in card_def.effects:
				_apply_logs(effect_resolver.resolve_effect(game_state, card_uid, effect_variant, {"target_player_id": acting_player_id}))
			if card.zone == played_from_zone:
				zone_manager.move_card(game_state, card_uid, UATypes.Zone.OUTSIDE)
	effect_resolver.commit_play_modifiers(game_state, play_modifiers)
	emit_state_changed()
	return {"ok": true}

func _play_enter_state_for(card_def: CardDef) -> int:
	if card_def == null:
		return UATypes.CardState.RESTED
	var enter_state := str(card_def.play_rule.get("enter_state", "RESTED"))
	return UATypes.CardState.ACTIVE if enter_state == "ACTIVE" else UATypes.CardState.RESTED

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
	var attack_log := str(result.get("attack_log", "")).strip_edges()
	if attack_log != "":
		_apply_logs([attack_log])
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
			for key in ["raid_target_uid", "raid_target_zone_choice", "allow_raid_play", "force_allow_current_zone", "ignore_pending_gate", "ignore_play_timing", "target_uid"]:
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
	_apply_logs(life_trigger_manager.resolve_life_trigger_decision(game_state, card_uid, activate))
	_resume_effect_queue_if_possible()
	emit_state_changed()
	return {"ok": true}

func acknowledge_life_reveal(card_uid: String) -> Dictionary:
	if _has_winner():
		return {"ok": false, "reason": "winner_exists"}
	var logs := life_trigger_manager.acknowledge_life_reveal(game_state, card_uid, controller_manager.is_human)
	_apply_logs(logs)
	if logs.is_empty() and life_trigger_manager.is_life_reveal_waiting_for_player(game_state):
		emit_state_changed()
		return {"ok": true}
	_resume_effect_queue_if_possible()
	emit_state_changed()
	return {"ok": true}

func get_snapshot() -> Dictionary:
	# Return a UI-facing snapshot instead of exposing raw runtime state.
	var action_player_id := _current_priority_player_id()
	var display_hand_player_id := _current_display_hand_player_id(action_player_id)
	var legal_actions := rules_engine.get_legal_actions(game_state, action_player_id)
	return snapshot_serializer.get_snapshot(game_state, action_player_id, display_hand_player_id, legal_actions)

func emit_state_changed() -> void:
	_refresh_life_reveal_waiting_for_player()
	emit_signal("state_changed", get_snapshot())
	controller_manager.queue_drive()

func append_ui_log(text: String) -> void:
	_apply_logs([text])
	emit_state_changed()
func _load_card_defs() -> void:
	_deck_card_lookup.clear()
	var json: Array = _card_catalog.load_runtime_cards()
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

func _apply_logs(logs: Array[String]) -> void:
	for line in logs:
		game_state.add_log(line)
		emit_signal("log_added", line)

func _load_deck_list(path: String) -> Array:
	if path.get_extension().to_lower() == "txt":
		return _read_text_deck(path)
	return _card_catalog.read_json_array(path)

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

func _has_winner() -> bool:
	return game_state.winner_player_id != ""

func _has_pending_life_triggers() -> bool:
	return life_trigger_manager.has_pending_life_triggers(game_state)

func _has_pending_life_reveal() -> bool:
	return life_trigger_manager.has_pending_life_reveal(game_state)

func _has_pending_decisions() -> bool:
	return decision_manager.has_pending_decisions(game_state)

func _life_reveal_fully_resolved() -> bool:
	return life_trigger_manager.life_reveal_fully_resolved(game_state)

func _maybe_finalize_life_damage_after_pending_resolution() -> void:
	if not _life_reveal_fully_resolved():
		return
	if not game_state.pending_life_triggers.is_empty() or not game_state.pending_decisions.is_empty():
		return
	_apply_logs(effect_resolver.finalize_pending_life_damage(game_state))
	_resume_effect_queue_if_possible()

func _resume_effect_queue_if_possible() -> void:
	if _has_winner() or _has_pending_gate():
		return
	_apply_logs(effect_resolver.consume_effect_queue(game_state))

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

func _current_display_hand_player_id(action_player_id: String) -> String:
	if controller_manager.is_human(action_player_id):
		return action_player_id
	for player_id in [UATypes.PLAYER_ONE, UATypes.PLAYER_TWO]:
		if controller_manager.is_human(player_id):
			return player_id
	return action_player_id

func _queue_controller_drive() -> void:
	controller_manager.queue_drive()

func drive_controllers(max_steps := 64) -> void:
	_initialize_controller_manager()
	controller_manager.drive_controllers(max_steps)

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

func _refresh_life_reveal_waiting_for_player() -> void:
	life_trigger_manager.refresh_life_reveal_waiting_for_player(game_state, controller_manager.is_human)

func _can_active_player_bonus_draw() -> bool:
	if game_state.phase != UATypes.Phase.DRAW:
		return false
	var player: PlayerState = game_state.get_player(game_state.active_player_id)
	if player == null:
		return false
	return not player.used_bonus_draw and player.ap_active_count() >= 1

func _enqueue_pending_decision(decision: Dictionary) -> void:
	decision_manager.enqueue_decision(game_state, decision)

func _take_pending_decision(decision_type: String, payload: Dictionary) -> Dictionary:
	return decision_manager.take_decision(game_state, decision_type, payload)

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
	return life_trigger_manager.resolve_life_trigger_raid_choice(game_state, decision, choice)

func _resolve_life_trigger_raid_target(decision: Dictionary, raid_target_uid: String) -> Array[String]:
	return life_trigger_manager.resolve_life_trigger_raid_target(game_state, decision, raid_target_uid)

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
			if required_name != "" and not candidate_def.matches_reference_name(required_name):
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
