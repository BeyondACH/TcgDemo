extends RefCounted
class_name TurnManager

const UATypes = preload("res://core/ua_types.gd")
const ZoneManager = preload("res://core/zone_manager.gd")
const VictoryChecker = preload("res://core/victory_checker.gd")
const GameState = preload("res://data/game_state.gd")
const PlayerState = preload("res://data/player_state.gd")
const CardInstance = preload("res://data/card_instance.gd")

var zone_manager: ZoneManager
var victory_checker: VictoryChecker
var effect_resolver

func _init(p_zone_manager: ZoneManager, p_victory_checker: VictoryChecker, p_effect_resolver = null) -> void:
	zone_manager = p_zone_manager
	victory_checker = p_victory_checker
	effect_resolver = p_effect_resolver

func begin_game(state: GameState) -> Array[String]:
	state.turn_number = 1
	state.active_player_id = UATypes.PLAYER_ONE
	state.priority_player_id = UATypes.PLAYER_ONE
	state.phase = UATypes.Phase.START
	return begin_turn(state)

func begin_turn(state: GameState) -> Array[String]:
	var logs: Array[String] = []
	var player: PlayerState = state.get_player(state.active_player_id)
	if player == null:
		return logs
	if effect_resolver != null:
		effect_resolver.cleanup_start_turn_expirations(state, state.active_player_id)
	player.turn_count += 1
	player.used_bonus_draw = false
	state.player_turn_flags[state.active_player_id] = {}
	zone_manager.reset_turn_flags(state, state.active_player_id)
	var ap_target: int = _ap_target_for_player(player, state.active_player_id)
	zone_manager.add_ap(player, ap_target)
	zone_manager.ready_ap(player)
	logs.append("%s turn %d starts." % [state.active_player_id, player.turn_count])
	logs.append("%s AP is now %d/%d." % [state.active_player_id, player.ap_active_count(), player.ap_total()])
	state.phase = UATypes.Phase.DRAW
	var skip_draw := state.active_player_id == UATypes.PLAYER_ONE and player.turn_count == 1
	if skip_draw:
		logs.append("First player skips the first turn draw.")
	else:
		var draw_uid: String = zone_manager.draw_card(state, state.active_player_id)
		if draw_uid == "":
			var defeat: Dictionary = victory_checker.check_deck_out_loss(state, state.active_player_id)
			if not defeat.is_empty():
				_apply_victory(state, defeat)
				logs.append("%s loses by deck out." % state.active_player_id)
				return logs
		logs.append("%s draws 1 card." % state.active_player_id)
	return logs

func advance_phase(state: GameState) -> Array[String]:
	var logs: Array[String] = []
	match state.phase:
		UATypes.Phase.DRAW:
			state.phase = UATypes.Phase.MOVE
			logs.append("Phase advances to MOVE.")
		UATypes.Phase.MOVE:
			state.phase = UATypes.Phase.MAIN
			logs.append("Phase advances to MAIN.")
		UATypes.Phase.MAIN:
			if effect_resolver != null:
				logs.append_array(effect_resolver.consume_timed_delayed_effects(state, "ON_END_MAIN_PHASE", {
					"player_id": state.active_player_id,
					"source_player_id": state.active_player_id,
					"target_player_id": state.active_player_id,
				}))
			state.phase = UATypes.Phase.ATTACK
			logs.append("Phase advances to ATTACK.")
		UATypes.Phase.ATTACK:
			state.phase = UATypes.Phase.END
			logs.append("Phase advances to END.")
		UATypes.Phase.END:
			logs.append_array(end_turn(state))
		_:
			state.phase = UATypes.Phase.DRAW
			logs.append("Phase advances to DRAW.")
	return logs

func request_bonus_draw(state: GameState) -> Array[String]:
	var player: PlayerState = state.get_player(state.active_player_id)
	if player == null:
		return ["Bonus draw failed: missing active player."]
	if state.phase != UATypes.Phase.DRAW:
		return ["Bonus draw failed: wrong phase."]
	if player.used_bonus_draw:
		return ["Bonus draw failed: already used this turn."]
	if not zone_manager.spend_ap(player, 1):
		return ["Bonus draw failed: not enough AP."]
	player.used_bonus_draw = true
	var draw_uid: String = zone_manager.draw_card(state, state.active_player_id)
	if draw_uid == "":
		var defeat: Dictionary = victory_checker.check_deck_out_loss(state, state.active_player_id)
		if not defeat.is_empty():
			_apply_victory(state, defeat)
			return ["%s loses by deck out." % state.active_player_id]
		return ["%s paid 1 AP for a bonus draw but deck was empty." % state.active_player_id]
	return [
		"%s pays 1 AP for a bonus draw." % state.active_player_id,
		"%s draws 1 card." % state.active_player_id,
	]

func end_turn(state: GameState) -> Array[String]:
	var logs: Array[String] = []
	zone_manager.ready_field_cards(state, state.active_player_id)
	logs.append("All front line and energy line cards become active.")
	if state.active_player_id == UATypes.PLAYER_ONE:
		state.active_player_id = UATypes.PLAYER_TWO
	else:
		state.active_player_id = UATypes.PLAYER_ONE
	state.priority_player_id = state.active_player_id
	state.turn_number += 1
	state.phase = UATypes.Phase.START
	logs.append_array(begin_turn(state))
	return logs

func _ap_target_for_player(player: PlayerState, player_id: String) -> int:
	if player.turn_count == 1:
		if player_id == UATypes.PLAYER_ONE:
			return 1
		return 2
	if player.turn_count == 2:
		return 2
	return UATypes.MAX_AP

func needs_hand_limit_discard(state: GameState, player_id: String) -> bool:
	var player: PlayerState = state.get_player(player_id)
	return player != null and player.hand.size() > UATypes.HAND_LIMIT

func build_hand_limit_choices(state: GameState, player_id: String) -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return choices
	for card_uid in player.hand:
		var card: CardInstance = state.get_card(card_uid)
		var label := str(card_uid)
		if card != null:
			var card_def = state.get_card_def(card.def_id)
			if card_def != null:
				label = "%s [%s]" % [card_def.name, card_uid]
		choices.append({
			"label": label,
			"value": card_uid,
		})
	return choices

func discard_for_hand_limit(state: GameState, player_id: String, card_uid: String) -> Array[String]:
	var logs: Array[String] = []
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return ["Hand limit discard failed: missing player."]
	if not player.hand.has(card_uid):
		return ["Hand limit discard failed: card is not in hand."]
	zone_manager.move_card(state, card_uid, UATypes.Zone.OUTSIDE, player_id)
	var card: CardInstance = state.get_card(card_uid)
	var card_name := card_uid
	if card != null:
		var card_def = state.get_card_def(card.def_id)
		if card_def != null:
			card_name = card_def.name
	logs.append("%s discards %s to outside for hand limit." % [player_id, card_name])
	return logs

func _apply_victory(state: GameState, result: Dictionary) -> void:
	state.winner_player_id = str(result.get("winner", ""))
	state.loser_player_id = str(result.get("loser", ""))
