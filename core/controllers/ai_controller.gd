extends "res://core/controllers/player_controller.gd"
class_name AIController

const SimpleAI = preload("res://core/ai/simple_ai.gd")

var strategy := SimpleAI.new()

func request_action(game_state, snapshot: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary:
	return strategy.choose_action(game_state, snapshot, legal_actions)

func request_pending_decision(game_state, snapshot: Dictionary, pending: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary:
	return strategy.choose_pending_decision(game_state, snapshot, pending, legal_actions)
