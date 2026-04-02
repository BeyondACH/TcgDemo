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
var _paced_drive_scheduled := false

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

## Runtime pacing dependencies (used only by queue_drive)
var scene_tree: SceneTree = null
var ai_action_delay_seconds := 0.3
var ai_action_emitter: Callable = Callable()


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
	_paced_drive_scheduled = false


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
	if _drive_pending:
		return
	_drive_pending = true
	if _drive_in_progress or _paced_drive_scheduled:
		return
	_process_drive_deferred()


func _process_drive_deferred() -> void:
	if _drive_in_progress:
		return
	if not _drive_pending:
		return
	if _should_use_runtime_pacing():
		_run_runtime_drive_step()
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
		var step := _build_ai_step(player_id, controller, legal_actions, snapshot)
		if step.is_empty():
			break
		_execute_ai_step(step)
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


func _should_use_runtime_pacing() -> bool:
	return scene_tree != null and ai_action_delay_seconds > 0.0


func _run_runtime_drive_step() -> void:
	if not _can_drive():
		_drive_pending = false
		return
	_drive_pending = false
	_drive_in_progress = true
	var executed := false
	if not _check_winner():
		_refresh_life_reveal()
		if not _is_life_reveal_waiting():
			var player_id := _get_priority_player_id()
			var controller: PlayerController = _controllers.get(player_id)
			if controller != null and not controller.is_human():
				var legal_actions := _get_legal_actions(player_id)
				if not legal_actions.is_empty():
					var snapshot := _get_snapshot()
					var step := _build_ai_step(player_id, controller, legal_actions, snapshot)
					if not step.is_empty():
						_execute_ai_step(step)
						executed = true
	_drive_in_progress = false
	if _drive_pending and not _check_winner():
		if _should_use_runtime_pacing() and executed:
			_schedule_runtime_drive()
		else:
			_process_drive_deferred()


func _schedule_runtime_drive() -> void:
	if scene_tree == null or _paced_drive_scheduled:
		return
	_paced_drive_scheduled = true
	_drive_pending = true
	scene_tree.create_timer(ai_action_delay_seconds).timeout.connect(_on_paced_drive_timeout, CONNECT_ONE_SHOT)


func _on_paced_drive_timeout() -> void:
	_paced_drive_scheduled = false
	if _drive_in_progress or not _drive_pending:
		return
	_process_drive_deferred()


func _build_ai_step(player_id: String, controller: PlayerController, legal_actions: Array[Dictionary], snapshot: Dictionary) -> Dictionary:
	var chosen_action := {}
	if _has_pending_gate() or _has_battle_context():
		chosen_action = controller.request_pending_decision(game_state, snapshot, _get_pending_context(), legal_actions)
	else:
		chosen_action = controller.request_action(game_state, snapshot, legal_actions)
	if chosen_action.is_empty():
		return {}
	return {
		"player_id": player_id,
		"snapshot": snapshot,
		"action": chosen_action,
	}


func _execute_ai_step(step: Dictionary) -> void:
	var action: Dictionary = step.get("action", {})
	if action.is_empty():
		return
	if ai_action_emitter.is_valid():
		ai_action_emitter.call(_build_action_info(step))
	_execute_action(action)


func _build_action_info(step: Dictionary) -> Dictionary:
	var action: Dictionary = step.get("action", {})
	var params: Dictionary = action.get("params", {})
	var snapshot: Dictionary = step.get("snapshot", {})
	var source_card_uid := str(action.get("source_card_uid", ""))
	var target_uid := str(params.get("target_uid", ""))
	if target_uid == "":
		target_uid = str(params.get("blocker_uid", ""))
	if target_uid == "":
		target_uid = str(params.get("attacker_uid", ""))
	if target_uid == "":
		target_uid = str(params.get("card_uid", ""))
	var attacker_uid := str(params.get("attacker_uid", ""))
	var blocker_uid := str(params.get("blocker_uid", ""))
	return {
		"player_id": str(step.get("player_id", "")),
		"phase": str(snapshot.get("phase", "")),
		"action_type": str(action.get("type", "")),
		"source_card_uid": source_card_uid,
		"source_card_name": _card_name_for_uid(source_card_uid),
		"target_uid": target_uid,
		"target_name": _card_name_for_uid(target_uid),
		"target_kind": str(params.get("target_kind", "")),
		"target_zone": int(params.get("target_zone", -1)),
		"move_mode": str(params.get("mode", "")),
		"decision_type": str(params.get("decision_type", "")),
		"activate": bool(params.get("activate", false)),
		"attacker_uid": attacker_uid,
		"attacker_name": _card_name_for_uid(attacker_uid),
		"blocker_uid": blocker_uid,
		"blocker_name": _card_name_for_uid(blocker_uid),
	}


func _card_name_for_uid(card_uid: String) -> String:
	if card_uid == "" or game_state == null:
		return ""
	var card = game_state.get_card(card_uid)
	if card == null:
		return ""
	var card_def = game_state.get_card_def(card.def_id)
	if card_def == null:
		return ""
	return str(card_def.name)
