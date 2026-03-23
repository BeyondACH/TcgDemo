extends RefCounted
class_name CardInstance

const UATypes = preload("res://core/ua_types.gd")

# 对局中的具体卡牌实例，和 CardDef 的“静态定义”相对应。
var uid := ""
var def_id := ""
var owner_player_id := ""
var controller_player_id := ""
var zone := UATypes.Zone.DECK
var state := UATypes.CardState.ACTIVE
var current_bp := 0
var flags := {
	"attacked_this_turn": false,
	"blocked_this_turn": false,
	"activated_main_this_turn": false,
	"double_attack_consumed": false,
	"double_block_consumed": false,
	"entered_via_raid": false,
	"is_stacked_under": false,
	"stack_parent_uid": "",
	"temp_keywords": [],
	"temp_keyword_counts": {},
}
var stacked_under: Array[String] = []

func reset_turn_flags() -> void:
	# 每回合开始时清空一次性标记，避免攻击/阻挡状态跨回合残留。
	flags["attacked_this_turn"] = false
	flags["blocked_this_turn"] = false
	flags["activated_main_this_turn"] = false
	flags["double_attack_consumed"] = false
	flags["double_block_consumed"] = false

func clear_runtime_effect_flags() -> void:
	flags["entered_via_raid"] = false
	flags["temp_keywords"] = []
	flags["temp_keyword_counts"] = {}

func mark_as_stacked_under(parent_uid: String) -> void:
	flags["is_stacked_under"] = true
	flags["stack_parent_uid"] = parent_uid
	clear_runtime_effect_flags()
	reset_turn_flags()

func clear_stacked_under_marker() -> void:
	flags["is_stacked_under"] = false
	flags["stack_parent_uid"] = ""
