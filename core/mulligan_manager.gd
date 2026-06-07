extends RefCounted
class_name MulliganManager

## 起手调度管理器 — 负责开局换牌流程
## Phase 2 Task 2.1 Step C: 从 game_manager.gd 提取

const UATypes = preload("res://core/ua_types.gd")
const GameState = preload("res://data/game_state.gd")
const CardInstance = preload("res://data/card_instance.gd")
const PlayerState = preload("res://data/player_state.gd")
const ZoneManager = preload("res://core/zone_manager.gd")

var _zone_manager: ZoneManager

func _init(p_zone_manager: ZoneManager) -> void:
	_zone_manager = p_zone_manager

func enqueue_mulligan_decision(state: GameState) -> Dictionary:
	var player_id := str(state.active_player_id)
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return {"ok": false, "reason": "missing_player"}
	state.phase = UATypes.Phase.START
	return {
		"ok": true,
		"decision": {
			"type": "MULLIGAN_CHOICE",
			"owner_player_id": player_id,
			"source_card_uid": "",
			"choices": [
				{"label": "保留", "value": "keep"},
				{"label": "换牌", "value": "mulligan"},
			],
			"context": {},
		},
		"log": "%s chooses whether to mulligan the opening hand." % player_id,
	}

func resolve_mulligan_decision(state: GameState, decision: Dictionary, payload: Dictionary) -> Dictionary:
	var player_id := str(decision.get("owner_player_id", ""))
	var choice := str(payload.get("choice", "keep"))
	var logs := apply_mulligan_choice(state, player_id, choice == "mulligan")
	var next: String = ""
	if player_id == UATypes.PLAYER_ONE:
		next = UATypes.PLAYER_TWO
	return {"ok": true, "logs": logs, "next_player": next}

func apply_mulligan_choice(state: GameState, player_id: String, wants_mulligan: bool) -> Array[String]:
	var logs: Array[String] = []
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return logs
	if not wants_mulligan:
		state.opening_mulligan_hands.erase(player_id)
		logs.append("%s keeps the opening hand." % player_id)
		return logs
	var old_hand: Array[String] = player.hand.duplicate()
	state.opening_mulligan_hands[player_id] = old_hand.duplicate()
	player.hand.clear()
	for i in range(UATypes.STARTING_HAND):
		_zone_manager.draw_card(state, player_id)
	for old_uid in old_hand:
		player.deck.append(old_uid)
		var old_card: CardInstance = state.get_card(old_uid)
		if old_card != null:
			old_card.zone = UATypes.Zone.DECK
	_zone_manager.shuffle_zone(player, UATypes.Zone.DECK)
	logs.append("%s mulligans, redraws 7, then shuffles the original hand back into the deck." % player_id)
	return logs
