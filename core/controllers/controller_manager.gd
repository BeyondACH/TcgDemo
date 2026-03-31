extends RefCounted
class_name ControllerManager

const UATypes = preload("res://core/ua_types.gd")
const PlayerController = preload("res://core/controllers/player_controller.gd")
const HumanController = preload("res://core/controllers/human_controller.gd")
const AIController = preload("res://core/controllers/ai_controller.gd")

var _controller_config := {}
var _controllers := {}
var _drive_pending := false
var _drive_in_progress := false

## Default controller types for each player (used when not specified in config)
var player_one_controller_type := PlayerController.CONTROLLER_HUMAN
var player_two_controller_type := PlayerController.CONTROLLER_AI_SIMPLE

## Callback for executing actions during drive loop
## Signature: func(action: Dictionary) -> void
var action_executor: Callable = Callable()

## Callback for getting legal actions
## Signature: func(game_state, player_id: String) -> Array[Dictionary]
var legal_actions_provider: Callable = Callable()

## Callback for getting game state snapshot
## Signature: func() -> Dictionary
var snapshot_provider: Callable = Callable()

## Callback for checking if game has winner
## Signature: func() -> bool
var winner_checker: Callable = Callable()

## Callback for checking if there's a pending gate (life triggers, decisions, etc.)
## Signature: func() -> bool
var pending_gate_checker: Callable = Callable()

## Callback for getting current priority player id
## Signature: func() -> String
var priority_player_provider: Callable = Callable()

## Callback for getting current pending context
## Signature: func() -> Dictionary
var pending_context_provider: Callable = Callable()

## Callback for refreshing life reveal waiting state
## Signature: func() -> void
var life_reveal_refresher: Callable = Callable()

## Callback for checking if life reveal is waiting for player
## Signature: func() -> bool
var life_reveal_waiting_checker: Callable = Callable()

## Reference to game state for controller decision making
var game_state: RefCounted = null


func reset_state(controller_config: Dictionary = {}) -> void:
	_controller_config = {
		UATypes.PLAYER_ONE: {"controller": player_one_controller_type},
		UATypes.PLAYER_TWO: {"controller": player_two_controller_type},
	}
	for key_variant in controller_config.keys():
		var key := str(key_variant)
		_controller_config[key] = (controller_config[key_variant] as Dictionary).duplicate(true)
	_controllers.clear()
	_controllers[UATypes.PLAYER_ONE] = build_controller_for(UATypes.PLAYER_ONE)
	_controllers[UATypes.PLAYER_TWO] = build_controller_for(UATypes.PLAYER_TWO)
	_drive_pending = false
	_drive_in_progress = false


func build_controller_for(player_id: String) -> PlayerController:
	var config: Dictionary = _controller_config.get(player_id, {})
	var controller_type := str(config.get("controller", PlayerController.CONTROLLER_HUMAN))
	match controller_type:
		PlayerController.CONTROLLER_AI_SIMPLE:
			var ai_controller := AIController.new()
			ai_controller.controller_type = PlayerController.CONTROLLER_AI_SIMPLE
			return ai_controller
		_:
			var human_controller := HumanController.new()
			human_controller.controller_type = PlayerController.CONTROLLER_HUMAN
			return human_controller


func get_controller_type(player_id: String) -> String:
	var controller: PlayerController = _controllers.get(player_id)
	if controller == null:
		return PlayerController.CONTROLLER_HUMAN
	return controller.controller_type


func is_human(player_id: String) -> bool:
	return get_controller_type(player_id) == PlayerController.CONTROLLER_HUMAN


func get_controller(player_id: String) -> PlayerController:
	return _controllers.get(player_id)


func queue_drive() -> void:
	if _drive_in_progress or _drive_pending:
		return
	_drive_pending = true
	# Use call_deferred equivalent for RefCounted
	_process_drive_deferred()


func _process_drive_deferred() -> void:
	if _drive_in_progress:
		return
	_drive_pending = false
	drive_controllers(64)


func drive_controllers(max_steps: int = 64) -> void:
	if not _can_drive():
		return
	_drive_in_progress = true
	var safety := max_steps
	while safety > 0:
		if _check_winner():
			break
		_refresh_life_reveal()
		if _is_life_reveal_waiting():
			break
		var player_id := _get_priority_player_id()
		var controller: PlayerController = _controllers.get(player_id)
		if controller == null or controller.is_human():
			break
		var legal_actions := _get_legal_actions(player_id)
		if legal_actions.is_empty():
			break
		var snapshot := _get_snapshot()
		var chosen_action := {}
		if _has_pending_gate() or _has_battle_context():
			chosen_action = controller.request_pending_decision(game_state, snapshot, _get_pending_context(), legal_actions)
		else:
			chosen_action = controller.request_action(game_state, snapshot, legal_actions)
		if chosen_action.is_empty():
			break
		_execute_action(chosen_action)
		safety -= 1
	_drive_in_progress = false
	if _drive_pending and not _check_winner():
		_process_drive_deferred()


func _can_drive() -> bool:
	return action_executor.is_valid() and legal_actions_provider.is_valid() and snapshot_provider.is_valid()


func _check_winner() -> bool:
	if winner_checker.is_valid():
		return winner_checker.call()
	return false


func _has_pending_gate() -> bool:
	if pending_gate_checker.is_valid():
		return pending_gate_checker.call()
	return false


func _has_battle_context() -> bool:
	if game_state == null:
		return false
	return not game_state.battle_context.is_empty()


func _get_priority_player_id() -> String:
	if priority_player_provider.is_valid():
		return priority_player_provider.call()
	return UATypes.PLAYER_ONE


func _get_legal_actions(player_id: String) -> Array[Dictionary]:
	if legal_actions_provider.is_valid():
		return legal_actions_provider.call(game_state, player_id)
	return []


func _get_snapshot() -> Dictionary:
	if snapshot_provider.is_valid():
		return snapshot_provider.call()
	return {}


func _get_pending_context() -> Dictionary:
	if pending_context_provider.is_valid():
		return pending_context_provider.call()
	return {}


func _refresh_life_reveal() -> void:
	if life_reveal_refresher.is_valid():
		life_reveal_refresher.call()


func _is_life_reveal_waiting() -> bool:
	if life_reveal_waiting_checker.is_valid():
		return life_reveal_waiting_checker.call()
	return false


func _execute_action(action: Dictionary) -> void:
	if action_executor.is_valid():
		action_executor.call(action)