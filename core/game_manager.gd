extends Node
class_name GameManager

signal state_changed(snapshot: Dictionary)
signal blockers_requested(request: Dictionary)
signal log_added(text: String)

const CARD_DATA_PATH := "res://data/cards/base_cards.json"
const STARTER_A_PATH := "res://data/decks/starter_a.json"
const STARTER_B_PATH := "res://data/decks/starter_b.json"

var game_state := GameState.new()
var zone_manager := ZoneManager.new()
var victory_checker := VictoryChecker.new()
var rules_engine := RulesEngine.new(zone_manager)
var effect_resolver := EffectResolver.new(zone_manager, victory_checker)
var battle_resolver := BattleResolver.new(rules_engine, zone_manager, effect_resolver)
var turn_manager := TurnManager.new(zone_manager, victory_checker)

func _ready() -> void:
	randomize()
	setup_game()

# Loads data, builds both players and starts the opening turn.
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
	if _has_winner():
		return
	_apply_logs(turn_manager.advance_phase(game_state))
	emit_state_changed()

# Entry point for hand play requests coming from the UI.
func play_card(card_uid: String, target_zone: int) -> void:
	if _has_winner():
		return
	var card: CardInstance = game_state.get_card(card_uid)
	if card == null:
		return
	var validation: Dictionary = rules_engine.can_play_card(game_state, game_state.active_player_id, card_uid, target_zone)
	if not bool(validation.get("ok", false)):
		_apply_logs(["Cannot play card: %s" % validation.get("reason", "unknown")])
		emit_state_changed()
		return
	var player: PlayerState = game_state.get_player(game_state.active_player_id)
	var card_def: CardDef = game_state.get_card_def(card.def_id)
	zone_manager.spend_ap(player, card_def.cost_ap)
	match card_def.card_type:
		UATypes.CardType.CHARACTER, UATypes.CardType.FIELD:
			zone_manager.move_card(game_state, card_uid, target_zone)
			card.state = UATypes.CardState.RESTED
			_apply_logs(["%s plays %s to %s." % [game_state.active_player_id, card_def.name, UATypes.zone_to_key(target_zone)]])
			_apply_logs(effect_resolver.resolve_trigger(card_uid, UATypes.TriggerType.ON_ENTER, game_state, {"target_player_id": game_state.active_player_id}))
		UATypes.CardType.EVENT:
			_apply_logs(["%s uses event %s." % [game_state.active_player_id, card_def.name]])
			_apply_logs(effect_resolver.resolve_operations(game_state, card_uid, card_def.effects, {"target_player_id": game_state.active_player_id}))
			zone_manager.move_card(game_state, card_uid, UATypes.Zone.OUTSIDE)
	emit_state_changed()

func move_energy_to_front(card_uid: String) -> void:
	if _has_winner():
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

func request_attack(attacker_uid: String) -> void:
	if _has_winner():
		return
	var result: Dictionary = battle_resolver.declare_attack(game_state, attacker_uid)
	if not bool(result.get("ok", false)):
		_apply_logs(["Cannot attack: %s" % result.get("reason", "unknown")])
		emit_state_changed()
		return
	emit_signal("blockers_requested", result)

func resolve_attack(attacker_uid: String, blocker_uid := "") -> void:
	if _has_winner():
		return
	_apply_logs(battle_resolver.resolve_attack(game_state, attacker_uid, blocker_uid))
	emit_state_changed()

func get_snapshot() -> Dictionary:
	return {
		"turn_number": game_state.turn_number,
		"active_player_id": game_state.active_player_id,
		"phase": UATypes.phase_to_text(game_state.phase),
		"winner_player_id": game_state.winner_player_id,
		"players": {
			UATypes.PLAYER_ONE: _serialize_player(UATypes.PLAYER_ONE),
			UATypes.PLAYER_TWO: _serialize_player(UATypes.PLAYER_TWO)
		},
		"logs": game_state.logs.duplicate(),
	}

func emit_state_changed() -> void:
	emit_signal("state_changed", get_snapshot())

func _load_card_defs() -> void:
	var json: Array = _read_json(CARD_DATA_PATH)
	for item in json:
		var item_dict: Dictionary = item
		var card_def: CardDef = CardDef.from_dict(item_dict)
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
			"zone": UATypes.zone_to_key(card.zone),
			"state": UATypes.state_to_text(card.state),
			"bp": card.current_bp,
			"cost_ap": card_def.cost_ap,
			"cost_energy": card_def.cost_energy.duplicate(true),
			"energy_provided": card_def.energy_provided.duplicate(true),
		})
	return result

func _apply_logs(logs: Array[String]) -> void:
	for line in logs:
		game_state.add_log(line)
		emit_signal("log_added", line)

func _load_deck_list(path: String) -> Array:
	return _read_json(path)

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
