extends RefCounted
class_name GameState

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
