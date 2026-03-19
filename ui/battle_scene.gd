extends Control
class_name BattleScene

@onready var game_manager: GameManager = $GameManager
@onready var turn_label: Label = $Root/TopBar/TurnLabel
@onready var active_player_label: Label = $Root/TopBar/ActivePlayerLabel
@onready var phase_indicator: PhaseIndicator = $Root/TopBar/PhaseIndicator
@onready var next_phase_button: Button = $Root/TopBar/NextPhaseButton
@onready var no_block_button: Button = $Root/TopBar/NoBlockButton
@onready var winner_label: Label = $Root/TopBar/WinnerLabel
@onready var opponent_board: BoardView = $Root/OpponentBoard
@onready var player_board: BoardView = $Root/PlayerBoard
@onready var hand_view: HandView = $Root/HandView
@onready var selected_card_label: Label = $Root/ActionBar/SelectedCardLabel
@onready var play_front_button: Button = $Root/ActionBar/PlayFrontButton
@onready var play_energy_button: Button = $Root/ActionBar/PlayEnergyButton
@onready var use_event_button: Button = $Root/ActionBar/UseEventButton
@onready var cancel_selection_button: Button = $Root/ActionBar/CancelSelectionButton
@onready var log_panel: LogPanel = $Root/LogPanel

var _snapshot: Dictionary = {}
var _selected_hand_card_uid := ""
var _pending_attack_uid := ""
var _pending_defender_player_id := ""

func _ready() -> void:
	game_manager.state_changed.connect(_on_state_changed)
	game_manager.blockers_requested.connect(_on_blockers_requested)
	next_phase_button.pressed.connect(_on_next_phase_pressed)
	no_block_button.pressed.connect(_on_no_block_pressed)
	play_front_button.pressed.connect(_on_play_front_pressed)
	play_energy_button.pressed.connect(_on_play_energy_pressed)
	use_event_button.pressed.connect(_on_use_event_pressed)
	cancel_selection_button.pressed.connect(_clear_selection)
	hand_view.hand_card_selected.connect(_on_hand_card_selected)
	opponent_board.front_card_pressed.connect(_on_front_card_pressed)
	opponent_board.energy_card_pressed.connect(_on_energy_card_pressed)
	player_board.front_card_pressed.connect(_on_front_card_pressed)
	player_board.energy_card_pressed.connect(_on_energy_card_pressed)
	_clear_selection()
	no_block_button.visible = false
	_on_state_changed(game_manager.get_snapshot())

func _on_state_changed(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	var active_player_id := str(snapshot.get("active_player_id", UATypes.PLAYER_ONE))
	var players: Dictionary = snapshot.get("players", {})
	var p1: Dictionary = players.get(UATypes.PLAYER_ONE, {})
	var p2: Dictionary = players.get(UATypes.PLAYER_TWO, {})
	turn_label.text = "Turn %d" % int(snapshot.get("turn_number", 1))
	active_player_label.text = "Active: %s" % active_player_id
	phase_indicator.set_phase_text(str(snapshot.get("phase", "START")))
	winner_label.text = "Winner: %s" % str(snapshot.get("winner_player_id", "-"))
	opponent_board.set_board(UATypes.PLAYER_TWO, "Player 2", p2)
	player_board.set_board(UATypes.PLAYER_ONE, "Player 1", p1)
	var active_hand: Array = p2.get("hand", [])
	if active_player_id == UATypes.PLAYER_ONE:
		active_hand = p1.get("hand", [])
	hand_view.set_hand(active_player_id, active_hand)
	selected_card_label.text = _selected_label_text(active_player_id)
	_update_action_buttons()
	log_panel.set_logs(snapshot.get("logs", []))
	if str(snapshot.get("winner_player_id", "")) != "":
		next_phase_button.disabled = true
		play_front_button.disabled = true
		play_energy_button.disabled = true
		use_event_button.disabled = true
		no_block_button.disabled = true

func _on_hand_card_selected(card_uid: String) -> void:
	_selected_hand_card_uid = card_uid
	if _try_auto_play_selected_card():
		_clear_selection()
		return
	_update_action_buttons()
	selected_card_label.text = _selected_label_text(str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE)))

func _on_front_card_pressed(player_id: String, card_uid: String) -> void:
	if _pending_attack_uid != "":
		if player_id == _pending_defender_player_id:
			game_manager.resolve_attack(_pending_attack_uid, card_uid)
			_clear_pending_attack()
		return
	if str(_snapshot.get("phase", "")) == "ATTACK" and player_id == str(_snapshot.get("active_player_id", "")):
		game_manager.request_attack(card_uid)

func _on_energy_card_pressed(player_id: String, card_uid: String) -> void:
	if str(_snapshot.get("phase", "")) == "MOVE" and player_id == str(_snapshot.get("active_player_id", "")):
		game_manager.move_energy_to_front(card_uid)

func _on_blockers_requested(request: Dictionary) -> void:
	var blockers: Array = request.get("blockers", [])
	if blockers.is_empty():
		game_manager.resolve_attack(str(request.get("attacker_uid", "")))
		return
	_pending_attack_uid = str(request.get("attacker_uid", ""))
	_pending_defender_player_id = str(request.get("defender_player_id", ""))
	no_block_button.visible = true
	selected_card_label.text = "Choose a blocker or click No Block"

func _on_next_phase_pressed() -> void:
	_clear_pending_attack()
	game_manager.advance_phase()

func _on_no_block_pressed() -> void:
	if _pending_attack_uid == "":
		return
	game_manager.resolve_attack(_pending_attack_uid)
	_clear_pending_attack()

func _on_play_front_pressed() -> void:
	if _selected_hand_card_uid != "":
		game_manager.play_card(_selected_hand_card_uid, UATypes.Zone.FRONT_LINE)
		_clear_selection()

func _on_play_energy_pressed() -> void:
	if _selected_hand_card_uid != "":
		game_manager.play_card(_selected_hand_card_uid, UATypes.Zone.ENERGY_LINE)
		_clear_selection()

func _on_use_event_pressed() -> void:
	if _selected_hand_card_uid != "":
		game_manager.play_card(_selected_hand_card_uid, UATypes.Zone.OUTSIDE)
		_clear_selection()

func _clear_selection() -> void:
	_selected_hand_card_uid = ""
	_update_action_buttons()
	selected_card_label.text = "No card selected"

func _clear_pending_attack() -> void:
	_pending_attack_uid = ""
	_pending_defender_player_id = ""
	no_block_button.visible = false

func _selected_label_text(active_player_id: String) -> String:
	if _pending_attack_uid != "":
		return "Choose a blocker or click No Block"
	if _selected_hand_card_uid == "":
		return "No card selected"
	var card_data: Dictionary = _find_hand_card(active_player_id, _selected_hand_card_uid)
	if card_data.is_empty():
		return "No card selected"
	return "Selected: %s" % str(card_data.get("name", "Unknown"))

func _find_hand_card(player_id: String, card_uid: String) -> Dictionary:
	var players: Dictionary = _snapshot.get("players", {})
	var player_data: Dictionary = players.get(player_id, {})
	for card_data in player_data.get("hand", []):
		if str(card_data.get("uid", "")) == card_uid:
			return card_data
	return {}

# Single-click hand play: event -> use, field -> energy, character -> front first then energy.
func _try_auto_play_selected_card() -> bool:
	if str(_snapshot.get("phase", "")) != "MAIN":
		return false
	var active_player_id := str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE))
	var players: Dictionary = _snapshot.get("players", {})
	var player_data: Dictionary = players.get(active_player_id, {})
	var card_data: Dictionary = _find_hand_card(active_player_id, _selected_hand_card_uid)
	if card_data.is_empty():
		return false
	var card_type := str(card_data.get("card_type", ""))
	if card_type == "EVENT":
		game_manager.play_card(_selected_hand_card_uid, UATypes.Zone.OUTSIDE)
		return true
	if card_type == "FIELD":
		game_manager.play_card(_selected_hand_card_uid, UATypes.Zone.ENERGY_LINE)
		return true
	if card_type == "CHARACTER":
		var front_line: Array = player_data.get("front_line", [])
		var energy_line: Array = player_data.get("energy_line", [])
		if front_line.size() < UATypes.MAX_FRONT_LINE:
			game_manager.play_card(_selected_hand_card_uid, UATypes.Zone.FRONT_LINE)
			return true
		if energy_line.size() < UATypes.MAX_ENERGY_LINE:
			game_manager.play_card(_selected_hand_card_uid, UATypes.Zone.ENERGY_LINE)
			return true
	return false

func _update_action_buttons() -> void:
	var active_player_id := str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE))
	var card_data: Dictionary = _find_hand_card(active_player_id, _selected_hand_card_uid)
	var card_type := str(card_data.get("card_type", ""))
	play_front_button.disabled = card_type != "CHARACTER"
	play_energy_button.disabled = card_type != "CHARACTER" and card_type != "FIELD"
	use_event_button.disabled = card_type != "EVENT"
	cancel_selection_button.disabled = _selected_hand_card_uid == ""
