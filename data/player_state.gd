extends RefCounted
class_name PlayerState

# 玩家持有的各区域状态。区域里保存的是卡牌 uid，具体卡牌数据统一在 GameState.cards 中查。
var player_id := ""
var deck: Array[String] = []
var hand: Array[String] = []
var life: Array[String] = []
var front_line: Array[String] = []
var energy_line: Array[String] = []
var ap_area: Array[Dictionary] = []
var outside: Array[String] = []
var removed: Array[String] = []
var turn_count := 0
var used_bonus_draw := false

func ap_total() -> int:
	return ap_area.size()

func ap_active_count() -> int:
	var count := 0
	for slot in ap_area:
		if bool(slot.get("active", false)):
			count += 1
	return count
