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

signal state_changed(snapshot: Dictionary)
signal blockers_requested(request: Dictionary)
signal log_added(text: String)

const CARD_DATA_PATH := "res://data/cards/cards_raw.json"
const LEGACY_CARD_DATA_PATH := "res://data/cards/base_cards.json"
const STARTER_A_PATH := "res://data/decks/starter_a.txt"
const STARTER_B_PATH := "res://data/decks/starter_b.txt"

var game_state := GameState.new()
var zone_manager := ZoneManager.new()
var victory_checker := VictoryChecker.new()
var rules_engine := RulesEngine.new(zone_manager)
var effect_resolver := EffectResolver.new(zone_manager, victory_checker)
var battle_resolver := BattleResolver.new(rules_engine, zone_manager, effect_resolver)
var turn_manager := TurnManager.new(zone_manager, victory_checker)
var _deck_card_lookup := {}

func _ready() -> void:
	randomize()
	setup_game()

# Initialize a fresh game state, decks, starting hands, and opening turn.
func setup_game() -> void:
	game_state = GameState.new()
	_load_card_defs()
	var starter_a: Array = _load_deck_list(STARTER_A_PATH)
	var starter_b: Array = _load_deck_list(STARTER_B_PATH)
	_create_player(UATypes.PLAYER_ONE, starter_a)
	_create_player(UATypes.PLAYER_TWO, starter_b)
	_prepare_starting_zones(UATypes.PLAYER_ONE)
	_prepare_starting_zones(UATypes.PLAYER_TWO)
	_apply_logs(turn_manager.begin_game(game_state))
	emit_state_changed()

func advance_phase() -> void:
	if _has_winner() or _has_pending_gate():
		return
	if game_state.phase == UATypes.Phase.END:
		effect_resolver.cleanup_turn_expirations(game_state, game_state.active_player_id)
		game_state.battle_context = {}
	_apply_logs(turn_manager.advance_phase(game_state))
	emit_state_changed()

func request_bonus_draw() -> void:
	if _has_winner() or _has_pending_gate():
		return
	_apply_logs(turn_manager.request_bonus_draw(game_state))
	emit_state_changed()

# Unified card-play entry point used by the UI.
func play_card(card_uid: String, target_zone: int, options: Dictionary = {}) -> void:
	if _has_winner() or _has_pending_gate():
		return
	var card: CardInstance = game_state.get_card(card_uid)
	if card == null:
		return
	var card_def: CardDef = game_state.get_card_def(card.def_id)
	if card_def == null:
		return
	var play_options := options.duplicate(true)
	if str(play_options.get("raid_target_uid", "")) != "":
		var raid_target: CardInstance = game_state.get_card(str(play_options.get("raid_target_uid", "")))
		if raid_target != null and raid_target.zone == UATypes.Zone.ENERGY_LINE and not play_options.has("raid_target_zone_choice"):
			_enqueue_pending_decision({
				"type": "RAID_ZONE_CHOICE",
				"owner_player_id": game_state.active_player_id,
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
			return
		if raid_target != null and raid_target.zone == UATypes.Zone.ENERGY_LINE and not play_options.has("raid_target_zone_choice"):
			play_options["raid_target_zone_choice"] = target_zone
	var play_modifiers := effect_resolver.preview_play_modifiers(game_state, game_state.active_player_id, card_uid, {
		"target_player_id": game_state.active_player_id,
		"target_zone": target_zone,
	})
	var validation: Dictionary = rules_engine.can_play_card(game_state, game_state.active_player_id, card_uid, target_zone, play_modifiers, play_options)
	if not bool(validation.get("ok", false)):
		_apply_logs(["Cannot play card: %s" % validation.get("reason", "unknown")])
		emit_state_changed()
		return
	var player: PlayerState = game_state.get_player(game_state.active_player_id)
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
					return
				card.flags["entered_via_raid"] = true
				_apply_logs(["%s raids onto %s and stays in %s." % [card_def.name, raid_target_uid, UATypes.zone_to_key(raid_target_zone)]])
			else:
				zone_manager.move_card(game_state, card_uid, target_zone)
				card.state = UATypes.CardState.RESTED
				card.flags["entered_via_raid"] = false
				_apply_logs(["%s plays %s to %s." % [game_state.active_player_id, card_def.name, UATypes.zone_to_key(target_zone)]])
			_apply_logs(effect_resolver.resolve_trigger(card_uid, UATypes.TriggerType.ON_ENTER, game_state, {"target_player_id": game_state.active_player_id}))
		UATypes.CardType.EVENT:
			_apply_logs(["%s uses event %s." % [game_state.active_player_id, card_def.name]])
			_apply_logs(effect_resolver.resolve_operations(game_state, card_uid, card_def.effects, {"target_player_id": game_state.active_player_id}))
			zone_manager.move_card(game_state, card_uid, UATypes.Zone.OUTSIDE)
	effect_resolver.commit_play_modifiers(game_state, play_modifiers)
	emit_state_changed()

func move_energy_to_front(card_uid: String) -> void:
	if _has_winner() or _has_pending_gate():
		return
	var validation: Dictionary = rules_engine.can_move_energy_to_front(game_state, game_state.active_player_id, card_uid)
	if not bool(validation.get("ok", false)):
		_apply_logs(["Cannot move card: %s" % validation.get("reason", "unknown")])
		emit_state_changed()
		return
	zone_manager.move_card(game_state, card_uid, UATypes.Zone.FRONT_LINE)
	var card: CardInstance = game_state.get_card(card_uid)
	var card_def: CardDef = null
	if card != null:
		card_def = game_state.get_card_def(card.def_id)
	if card_def != null:
		_apply_logs(["%s moves %s from energy to front line." % [game_state.active_player_id, card_def.name]])
	emit_state_changed()

func request_attack(attacker_uid: String, options: Dictionary = {}) -> void:
	if _has_winner() or _has_pending_gate():
		return
	var result: Dictionary = battle_resolver.declare_attack(game_state, attacker_uid, options)
	if not bool(result.get("ok", false)):
		_apply_logs(["Cannot attack: %s" % result.get("reason", "unknown")])
		emit_state_changed()
		return
	emit_signal("blockers_requested", result)

func resolve_attack(attacker_uid: String, blocker_uid := "") -> void:
	if _has_winner() or _has_pending_gate():
		return
	_apply_logs(battle_resolver.resolve_attack(game_state, attacker_uid, blocker_uid))
	emit_state_changed()

func request_main_activate(card_uid: String, effect_index := 0) -> void:
	if _has_winner() or _has_pending_gate():
		return
	_apply_logs(effect_resolver.activate_main_effect(game_state, game_state.active_player_id, card_uid, effect_index))
	emit_state_changed()

func request_step_move(card_uid: String, options: Dictionary = {}) -> void:
	if _has_winner() or _has_pending_gate():
		return
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
				return
		_apply_logs(["Cannot step move: %s" % validation.get("reason", "unknown")])
		emit_state_changed()
		return
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

func resolve_pending_decision(decision_type: String, payload: Dictionary = {}) -> void:
	if _has_winner():
		return
	var decision := _take_pending_decision(decision_type, payload)
	if decision.is_empty():
		_apply_logs(["Pending decision not found: %s" % decision_type])
		emit_state_changed()
		return
	match decision_type:
		"RAID_ZONE_CHOICE":
			var play_options := {
				"raid_target_uid": str(decision.get("context", {}).get("raid_target_uid", "")),
				"raid_target_zone_choice": int(payload.get("choice", UATypes.Zone.ENERGY_LINE)),
			}
			play_card(str(decision.get("source_card_uid", "")), int(decision.get("context", {}).get("target_zone", UATypes.Zone.ENERGY_LINE)), play_options)
			return
		"STEP_SWAP_CHOICE":
			request_step_move(str(decision.get("source_card_uid", "")), {"swap_uid": str(payload.get("choice", ""))})
			return
	_apply_logs(["Unsupported decision type: %s" % decision_type])
	emit_state_changed()

func resolve_life_trigger_decision(card_uid: String, activate: bool) -> void:
	if _has_winner():
		return
	_apply_logs(effect_resolver.resolve_life_trigger_decision(game_state, card_uid, activate))
	emit_state_changed()

func get_snapshot() -> Dictionary:
	# Return a UI-facing snapshot instead of exposing raw runtime state.
	return {
		"turn_number": game_state.turn_number,
		"active_player_id": game_state.active_player_id,
		"phase": UATypes.phase_to_text(game_state.phase),
		"can_bonus_draw": _can_active_player_bonus_draw(),
		"winner_player_id": game_state.winner_player_id,
		"battle_context": game_state.battle_context.duplicate(true),
		"pending_decisions": game_state.pending_decisions.duplicate(true),
		"pending_life_triggers": game_state.pending_life_triggers.duplicate(true),
		"players": {
			UATypes.PLAYER_ONE: _serialize_player(UATypes.PLAYER_ONE),
			UATypes.PLAYER_TWO: _serialize_player(UATypes.PLAYER_TWO)
		},
		"logs": game_state.logs.duplicate(),
	}

func emit_state_changed() -> void:
	emit_signal("state_changed", get_snapshot())

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
	var legacy_json: Array = _read_json(LEGACY_CARD_DATA_PATH)
	for item in legacy_json:
		var item_dict: Dictionary = item
		var card_def: CardDef = CardDef.new().from_dict(item_dict)
		if card_def.id == "":
			continue
		if game_state.card_defs.has(card_def.id):
			continue
		game_state.card_defs[card_def.id] = card_def

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

func _prepare_starting_zones(player_id: String) -> void:
	var player: PlayerState = game_state.get_player(player_id)
	if player == null:
		return
	# Draw the opening hand first, then place starting life cards.
	for i in range(UATypes.STARTING_HAND):
		zone_manager.draw_card(game_state, player_id)
	for i in range(UATypes.STARTING_LIFE):
		if player.deck.is_empty():
			break
		var card_uid: String = player.deck.pop_front()
		player.life.append(card_uid)
		var card: CardInstance = game_state.get_card(card_uid)
		if card != null:
			card.zone = UATypes.Zone.LIFE
	_apply_logs(["%s starts with %d hand and %d life." % [player_id, player.hand.size(), player.life.size()]])

func _serialize_player(player_id: String) -> Dictionary:
	var player: PlayerState = game_state.get_player(player_id)
	if player == null:
		return {}
	return {
		"player_id": player.player_id,
		"deck_count": player.deck.size(),
		"hand_count": player.hand.size(),
		"life_count": player.life.size(),
		"ap_total": player.ap_total(),
		"ap_active": player.ap_active_count(),
		"used_bonus_draw": player.used_bonus_draw,
		"available_energy": _energy_pool_for_player(player),
		"hand": _serialize_cards(player.hand),
		"front_line": _serialize_cards(player.front_line),
		"energy_line": _serialize_cards(player.energy_line),
		"outside_count": player.outside.size(),
		"removed_count": player.removed.size(),
	}

func _serialize_cards(card_uids: Array[String]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for card_uid in card_uids:
		var card: CardInstance = game_state.get_card(card_uid)
		var card_def: CardDef = null
		if card != null:
			card_def = game_state.get_card_def(card.def_id)
		if card == null or card_def == null:
			continue
		result.append({
			"uid": card.uid,
			"name": card_def.name,
			"card_type": UATypes.card_type_to_text(card_def.card_type),
			"number": card_def.number,
			"source_image": card_def.source_image,
			"zone": UATypes.zone_to_key(card.zone),
			"state": UATypes.state_to_text(card.state),
			"bp": card.current_bp,
			"cost_ap": card_def.cost_ap,
			"cost_energy": card_def.cost_energy.duplicate(true),
			"energy_provided": card_def.energy_provided.duplicate(true),
			"keywords": card_def.keywords.duplicate(),
			"stacked_under": card.stacked_under.duplicate(),
			"flags": card.flags.duplicate(true),
			"available_actions": _available_actions_for_card(card, card_def),
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

func _has_pending_decisions() -> bool:
	return not game_state.pending_decisions.is_empty()

func _has_pending_gate() -> bool:
	return _has_pending_life_triggers() or _has_pending_decisions()

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
	for i in range(game_state.pending_decisions.size()):
		var decision: Dictionary = game_state.pending_decisions[i]
		if str(decision.get("type", "")) != decision_type:
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
	return pool

func _available_actions_for_card(card: CardInstance, card_def: CardDef) -> Array[String]:
	var actions: Array[String] = []
	if card.controller_player_id != game_state.active_player_id:
		return actions
	if card.zone == UATypes.Zone.FRONT_LINE and game_state.phase == UATypes.Phase.ATTACK:
		var attack_result := rules_engine.can_attack(game_state, card.controller_player_id, card.uid)
		if bool(attack_result.get("ok", false)):
			actions.append("ATTACK_PLAYER")
		if card_def.keywords.has("SNIPER"):
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
