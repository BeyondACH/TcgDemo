extends RefCounted
class_name CardInstance

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
}
var stacked_under: Array[String] = []

func reset_turn_flags() -> void:
	flags["attacked_this_turn"] = false
	flags["blocked_this_turn"] = false
	flags["activated_main_this_turn"] = false
