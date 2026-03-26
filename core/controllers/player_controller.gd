extends RefCounted
class_name PlayerController

const CONTROLLER_HUMAN := "HUMAN"
const CONTROLLER_AI_SIMPLE := "AI_SIMPLE"

var controller_type := CONTROLLER_HUMAN

func is_human() -> bool:
	return controller_type == CONTROLLER_HUMAN

func request_action(_game_state, _snapshot: Dictionary, _legal_actions: Array[Dictionary]) -> Dictionary:
	return {}

func request_pending_decision(_game_state, _snapshot: Dictionary, _pending: Dictionary, _legal_actions: Array[Dictionary]) -> Dictionary:
	return {}
