extends RefCounted
class_name GameState

const UATypes = preload("res://core/ua_types.gd")
const PlayerState = preload("res://data/player_state.gd")
const CardInstance = preload("res://data/card_instance.gd")
const CardDef = preload("res://data/card_def.gd")

# 对局全局状态容器，负责集中保存玩家、卡牌、回合和日志信息。
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
	# 保持日志长度可控，避免长对局持续堆积文本。
	if logs.size() > 100:
		logs.pop_front()
