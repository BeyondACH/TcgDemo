extends RefCounted
class_name UATypes

enum CardType {
	CHARACTER,
	FIELD,
	EVENT,
}

enum Zone {
	DECK,
	HAND,
	LIFE,
	FRONT_LINE,
	ENERGY_LINE,
	AP_AREA,
	OUTSIDE,
	REMOVED,
}

enum CardState {
	ACTIVE,
	RESTED,
}

enum Phase {
	START,
	DRAW,
	MOVE,
	MAIN,
	ATTACK,
	END,
}

enum TriggerType {
	ON_ENTER,
	ON_LEAVE,
	ON_ATTACK,
	ON_BLOCK,
	ON_LIFE_TRIGGER,
	MAIN_ACTIVATE,
	ON_BATTLE_WIN,
	ON_BATTLE_LOSE,
	ON_BATTLE_END,
}

const PLAYER_ONE := "P1"
const PLAYER_TWO := "P2"

const MAX_FRONT_LINE := 4
const MAX_ENERGY_LINE := 4
const MAX_AP := 3
const STARTING_HAND := 7
const STARTING_LIFE := 7
const MAIN_DECK_SIZE := 50
const HAND_LIMIT := 8

static func zone_to_key(zone: int) -> String:
	match zone:
		Zone.DECK:
			return "deck"
		Zone.HAND:
			return "hand"
		Zone.LIFE:
			return "life"
		Zone.FRONT_LINE:
			return "front_line"
		Zone.ENERGY_LINE:
			return "energy_line"
		Zone.AP_AREA:
			return "ap_area"
		Zone.OUTSIDE:
			return "outside"
		Zone.REMOVED:
			return "removed"
	return ""

static func phase_to_text(phase: int) -> String:
	match phase:
		Phase.START:
			return "START"
		Phase.DRAW:
			return "DRAW"
		Phase.MOVE:
			return "MOVE"
		Phase.MAIN:
			return "MAIN"
		Phase.ATTACK:
			return "ATTACK"
		Phase.END:
			return "END"
	return "UNKNOWN"

static func state_to_text(state: int) -> String:
	if state == CardState.RESTED:
		return "REST"
	return "ACTIVE"

static func card_type_to_text(card_type: int) -> String:
	match card_type:
		CardType.CHARACTER:
			return "CHARACTER"
		CardType.FIELD:
			return "FIELD"
		CardType.EVENT:
			return "EVENT"
	return "UNKNOWN"
