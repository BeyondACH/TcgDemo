extends RefCounted
class_name PlayerUtils

const UATypes = preload("res://core/ua_types.gd")

static func opponent_of(player_id: String) -> String:
	if player_id == UATypes.PLAYER_ONE:
		return UATypes.PLAYER_TWO
	return UATypes.PLAYER_ONE