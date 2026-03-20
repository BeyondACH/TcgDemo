extends Control
class_name BattleScene

const UATypes = preload("res://core/ua_types.gd")
const GameManager = preload("res://core/game_manager.gd")
const BoardView = preload("res://ui/board_view.gd")
const HandView = preload("res://ui/hand_view.gd")
const LogPanel = preload("res://ui/log_panel.gd")
const PhaseIndicator = preload("res://ui/phase_indicator.gd")

const BATTLE_BG_PATH := "res://assets/battle/backgrounds/battle_bg.png"
const SELECTION_HIGHLIGHT_PATH := "res://assets/battle/effects/selection_highlight.png"
const SLOT_HIGHLIGHT_PATH := "res://assets/battle/effects/slot_highlight.png"
const COMPACT_HEIGHT_THRESHOLD := 880.0
const SMALL_HEIGHT_THRESHOLD := 760.0

@onready var game_manager: GameManager = $GameManager
@onready var background_texture_rect: TextureRect = $BackgroundLayer/Background
@onready var selection_highlight: TextureRect = $EffectLayer/SelectionHighlight
@onready var slot_highlight: TextureRect = $EffectLayer/SlotHighlight
@onready var board_margin: MarginContainer = $BoardLayer/BoardMargin
@onready var board_spacer: Control = $BoardLayer/BoardMargin/BoardContent/BoardSpacer
@onready var top_hud: MarginContainer = $UILayer/TopHUD
@onready var bottom_hud: MarginContainer = $UILayer/BottomHUD
@onready var bottom_panel: PanelContainer = $UILayer/BottomHUD/BottomPanel
@onready var turn_label: Label = $UILayer/TopHUD/TopBar/TurnLabel
@onready var active_player_label: Label = $UILayer/TopHUD/TopBar/ActivePlayerLabel
@onready var phase_indicator: PhaseIndicator = $UILayer/TopHUD/TopBar/PhaseIndicator
@onready var next_phase_button: Button = $UILayer/TopHUD/TopBar/NextPhaseButton
@onready var no_block_button: Button = $UILayer/TopHUD/TopBar/NoBlockButton
@onready var winner_label: Label = $UILayer/TopHUD/TopBar/WinnerLabel
@onready var opponent_board: BoardView = $BoardLayer/BoardMargin/BoardContent/OpponentBoard
@onready var player_board: BoardView = $BoardLayer/BoardMargin/BoardContent/PlayerBoard
@onready var hand_view: HandView = $UILayer/BottomHUD/BottomPanel/BottomContent/HandView
@onready var selected_card_label: Label = $UILayer/BottomHUD/BottomPanel/BottomContent/ActionBar/SelectedCardLabel
@onready var play_front_button: Button = $UILayer/BottomHUD/BottomPanel/BottomContent/ActionBar/PlayFrontButton
@onready var play_energy_button: Button = $UILayer/BottomHUD/BottomPanel/BottomContent/ActionBar/PlayEnergyButton
@onready var use_event_button: Button = $UILayer/BottomHUD/BottomPanel/BottomContent/ActionBar/UseEventButton
@onready var life_trigger_picker: OptionButton = $UILayer/BottomHUD/BottomPanel/BottomContent/ActionBar/LifeTriggerPicker
@onready var activate_life_button: Button = $UILayer/BottomHUD/BottomPanel/BottomContent/ActionBar/ActivateLifeButton
@onready var skip_life_button: Button = $UILayer/BottomHUD/BottomPanel/BottomContent/ActionBar/SkipLifeButton
@onready var cancel_selection_button: Button = $UILayer/BottomHUD/BottomPanel/BottomContent/ActionBar/CancelSelectionButton
@onready var log_panel: LogPanel = $UILayer/BottomHUD/BottomPanel/BottomContent/LogPanel

var _snapshot: Dictionary = {}
var _selected_hand_card_uid := ""
var _pending_attack_uid := ""
var _pending_defender_player_id := ""
var _selected_life_trigger_uid := ""

func _ready() -> void:
	_setup_optional_art()
	# UI only consumes GameManager signals and snapshots.
	game_manager.state_changed.connect(_on_state_changed)
	game_manager.blockers_requested.connect(_on_blockers_requested)
	next_phase_button.pressed.connect(_on_next_phase_pressed)
	no_block_button.pressed.connect(_on_no_block_pressed)
	play_front_button.pressed.connect(_on_play_front_pressed)
	play_energy_button.pressed.connect(_on_play_energy_pressed)
	use_event_button.pressed.connect(_on_use_event_pressed)
	activate_life_button.pressed.connect(_on_activate_life_pressed)
	skip_life_button.pressed.connect(_on_skip_life_pressed)
	life_trigger_picker.item_selected.connect(_on_life_trigger_selected)
	cancel_selection_button.pressed.connect(_clear_selection)
	hand_view.hand_card_selected.connect(_on_hand_card_selected)
	opponent_board.front_card_pressed.connect(_on_front_card_pressed)
	opponent_board.energy_card_pressed.connect(_on_energy_card_pressed)
	opponent_board.zone_drop_requested.connect(_on_zone_drop_requested)
	player_board.front_card_pressed.connect(_on_front_card_pressed)
	player_board.energy_card_pressed.connect(_on_energy_card_pressed)
	player_board.zone_drop_requested.connect(_on_zone_drop_requested)
	_clear_selection()
	no_block_button.visible = false
	life_trigger_picker.visible = false
	activate_life_button.visible = false
	skip_life_button.visible = false
	get_viewport().size_changed.connect(_update_responsive_layout)
	_update_responsive_layout()
	_on_state_changed(game_manager.get_snapshot())

func _setup_optional_art() -> void:
	_assign_optional_texture(background_texture_rect, BATTLE_BG_PATH)
	_assign_optional_texture(selection_highlight, SELECTION_HIGHLIGHT_PATH)
	_assign_optional_texture(slot_highlight, SLOT_HIGHLIGHT_PATH)

func _assign_optional_texture(target: TextureRect, resource_path: String) -> void:
	if ResourceLoader.exists(resource_path):
		target.texture = load(resource_path)
	else:
		target.texture = null

func _update_responsive_layout() -> void:
	var viewport_height := get_viewport_rect().size.y
	var compact := viewport_height < COMPACT_HEIGHT_THRESHOLD
	var very_small := viewport_height < SMALL_HEIGHT_THRESHOLD

	top_hud.offset_top = 12.0
	board_margin.offset_top = 60.0 if compact else 72.0
	board_margin.offset_bottom = -160.0 if very_small else (-176.0 if compact else -196.0)
	board_spacer.custom_minimum_size = Vector2(0, 12.0 if very_small else (16.0 if compact else 24.0))
	bottom_hud.offset_top = -148.0 if very_small else (-168.0 if compact else -184.0)
	bottom_panel.custom_minimum_size = Vector2(0, 136.0 if very_small else (152.0 if compact else 172.0))

	opponent_board.set_compact_mode(compact)
	player_board.set_compact_mode(compact)

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
	_sync_life_trigger_controls()
	selected_card_label.text = _selected_label_text(active_player_id)
	_update_action_buttons()
	log_panel.set_logs(snapshot.get("logs", []))
	var has_winner := str(snapshot.get("winner_player_id", "")) != ""
	var has_pending_life := _has_pending_life_triggers()
	next_phase_button.disabled = has_winner or has_pending_life
	play_front_button.disabled = play_front_button.disabled or has_winner or has_pending_life
	play_energy_button.disabled = play_energy_button.disabled or has_winner or has_pending_life
	use_event_button.disabled = use_event_button.disabled or has_winner or has_pending_life
	no_block_button.disabled = has_winner or has_pending_life
	cancel_selection_button.disabled = cancel_selection_button.disabled or has_winner or has_pending_life
	activate_life_button.disabled = has_winner or not has_pending_life or _selected_life_trigger_uid == ""
	skip_life_button.disabled = has_winner or not has_pending_life or _selected_life_trigger_uid == ""

func _on_hand_card_selected(card_uid: String) -> void:
	if _has_pending_life_triggers():
		return
	_selected_hand_card_uid = card_uid
	_update_action_buttons()
	selected_card_label.text = _selected_label_text(str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE)))

func _on_front_card_pressed(player_id: String, card_uid: String) -> void:
	if _has_pending_life_triggers():
		return
	if _pending_attack_uid != "":
		if player_id == _pending_defender_player_id:
			game_manager.resolve_attack(_pending_attack_uid, card_uid)
			_clear_pending_attack()
		return
	if str(_snapshot.get("phase", "")) == "ATTACK" and player_id == str(_snapshot.get("active_player_id", "")):
		game_manager.request_attack(card_uid)

func _on_energy_card_pressed(player_id: String, card_uid: String) -> void:
	if _has_pending_life_triggers():
		return
	if str(_snapshot.get("phase", "")) == "MOVE" and player_id == str(_snapshot.get("active_player_id", "")):
		game_manager.move_energy_to_front(card_uid)

func _on_zone_drop_requested(player_id: String, zone_name: String, card_uid: String) -> void:
	if _has_pending_life_triggers():
		return
	if str(_snapshot.get("phase", "")) != "MAIN":
		return
	if player_id != str(_snapshot.get("active_player_id", "")):
		return
	if zone_name == "front_line":
		game_manager.play_card(card_uid, UATypes.Zone.FRONT_LINE)
	elif zone_name == "energy_line":
		game_manager.play_card(card_uid, UATypes.Zone.ENERGY_LINE)
	_clear_selection()

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
	if _has_pending_life_triggers():
		return
	_clear_pending_attack()
	game_manager.advance_phase()

func _on_no_block_pressed() -> void:
	if _has_pending_life_triggers():
		return
	if _pending_attack_uid == "":
		return
	game_manager.resolve_attack(_pending_attack_uid)
	_clear_pending_attack()

func _on_play_front_pressed() -> void:
	if _has_pending_life_triggers():
		return
	if _selected_hand_card_uid != "":
		game_manager.play_card(_selected_hand_card_uid, UATypes.Zone.FRONT_LINE)
		_clear_selection()

func _on_play_energy_pressed() -> void:
	if _has_pending_life_triggers():
		return
	if _selected_hand_card_uid != "":
		game_manager.play_card(_selected_hand_card_uid, UATypes.Zone.ENERGY_LINE)
		_clear_selection()

func _on_use_event_pressed() -> void:
	if _has_pending_life_triggers():
		return
	if _selected_hand_card_uid != "":
		game_manager.play_card(_selected_hand_card_uid, UATypes.Zone.OUTSIDE)
		_clear_selection()

func _on_activate_life_pressed() -> void:
	if _selected_life_trigger_uid == "":
		return
	game_manager.resolve_life_trigger_decision(_selected_life_trigger_uid, true)

func _on_skip_life_pressed() -> void:
	if _selected_life_trigger_uid == "":
		return
	game_manager.resolve_life_trigger_decision(_selected_life_trigger_uid, false)

func _on_life_trigger_selected(index: int) -> void:
	var pending: Array = _snapshot.get("pending_life_triggers", [])
	if index < 0 or index >= pending.size():
		_selected_life_trigger_uid = ""
		return
	_selected_life_trigger_uid = str((pending[index] as Dictionary).get("card_uid", ""))
	selected_card_label.text = _selected_label_text(str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE)))

func _clear_selection() -> void:
	_selected_hand_card_uid = ""
	_update_action_buttons()
	selected_card_label.text = _selected_label_text(str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE)))

func _clear_pending_attack() -> void:
	_pending_attack_uid = ""
	_pending_defender_player_id = ""
	no_block_button.visible = false

func _selected_label_text(active_player_id: String) -> String:
	if _has_pending_life_triggers():
		var owner_id := ""
		for entry_variant in _snapshot.get("pending_life_triggers", []):
			var entry: Dictionary = entry_variant
			owner_id = str(entry.get("player_id", owner_id))
			if str(entry.get("card_uid", "")) == _selected_life_trigger_uid:
				return "Life trigger: %s chooses %s" % [owner_id, str(entry.get("card_name", "Unknown"))]
		return "Resolve pending life triggers"
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

func _update_action_buttons() -> void:
	var active_player_id := str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE))
	var card_data: Dictionary = _find_hand_card(active_player_id, _selected_hand_card_uid)
	var card_type := str(card_data.get("card_type", ""))
	# Button availability stays coarse-grained and defers final validation to GameManager.
	play_front_button.disabled = card_type != "CHARACTER"
	play_energy_button.disabled = card_type != "CHARACTER" and card_type != "FIELD"
	use_event_button.disabled = card_type != "EVENT"
	cancel_selection_button.disabled = _selected_hand_card_uid == ""

func _sync_life_trigger_controls() -> void:
	var pending: Array = _snapshot.get("pending_life_triggers", [])
	life_trigger_picker.clear()
	if pending.is_empty():
		_selected_life_trigger_uid = ""
		life_trigger_picker.visible = false
		activate_life_button.visible = false
		skip_life_button.visible = false
		return
	var selected_index := 0
	for i in range(pending.size()):
		var entry: Dictionary = pending[i]
		var card_uid := str(entry.get("card_uid", ""))
		var label := "%s: %s" % [str(entry.get("player_id", "")), str(entry.get("card_name", card_uid))]
		life_trigger_picker.add_item(label)
		if card_uid == _selected_life_trigger_uid:
			selected_index = i
	if _selected_life_trigger_uid == "":
		_selected_life_trigger_uid = str((pending[0] as Dictionary).get("card_uid", ""))
	life_trigger_picker.select(selected_index)
	_selected_life_trigger_uid = str((pending[selected_index] as Dictionary).get("card_uid", ""))
	life_trigger_picker.visible = true
	activate_life_button.visible = true
	skip_life_button.visible = true

func _has_pending_life_triggers() -> bool:
	return not (_snapshot.get("pending_life_triggers", []) as Array).is_empty()
