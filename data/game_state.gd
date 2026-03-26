extends RefCounted
class_name GameState

const UATypes = preload("res://core/ua_types.gd")
const PlayerState = preload("res://data/player_state.gd")
const CardInstance = preload("res://data/card_instance.gd")
const CardDef = preload("res://data/card_def.gd")

var turn_number := 1
var active_player_id := UATypes.PLAYER_ONE
var priority_player_id := UATypes.PLAYER_ONE
var phase := UATypes.Phase.START
var players := {}
var cards := {}
var card_defs := {}
var logs: Array[String] = []
var winner_player_id := ""
var loser_player_id := ""
var delayed_effects: Array = []
var static_modifiers: Array = []
var effect_queue: Array[Dictionary] = []
var battle_context := {}
var last_battle_result := {}
var opening_complete := false
var opening_mulligan_hands := {}
var pending_decisions: Array[Dictionary] = []
var pending_life_damage_cards: Array[Dictionary] = []
var pending_life_triggers: Array[Dictionary] = []
var _runtime_id_seed := 1

func get_player(player_id: String) -> PlayerState:
	return players.get(player_id)

func get_card(card_uid: String) -> CardInstance:
	return cards.get(card_uid)

func get_card_def(def_id: String) -> CardDef:
	return card_defs.get(def_id)

func add_log(text: String) -> void:
	logs.append(text)
	if logs.size() > 100:
		logs.pop_front()

func next_runtime_id(prefix := "runtime") -> String:
	var result := "%s_%d" % [prefix, _runtime_id_seed]
	_runtime_id_seed += 1
	return result
