extends Control
class_name BattleScene

const UATypes = preload("res://core/ua_types.gd")
const GameManager = preload("res://core/game_manager.gd")
const BoardView = preload("res://ui/board_view.gd")
const HandView = preload("res://ui/hand_view.gd")
const CardPreviewPanel = preload("res://ui/card_preview_panel.gd")
const LogPanel = preload("res://ui/log_panel.gd")
const PhaseIndicator = preload("res://ui/phase_indicator.gd")
const ZoneLayoutConfig = preload("res://data/zone_layout_config.gd")

const BATTLE_BG_PATH := "res://assets/battle/backgrounds/battle_bg.jpg"
const SELECTION_HIGHLIGHT_PATH := "res://assets/battle/effects/selection_highlight.png"
const SLOT_HIGHLIGHT_PATH := "res://assets/battle/effects/slot_highlight.png"
const COMPACT_HEIGHT_THRESHOLD := 1120.0
const SMALL_HEIGHT_THRESHOLD := 940.0
const COMPACT_WIDTH_THRESHOLD := 1820.0
const SMALL_WIDTH_THRESHOLD := 1650.0
const BOARD_BOTTOM_GAP := 28.0
const BOARD_TOP_GAP := 18.0
const BOTTOM_HUD_BOTTOM_MARGIN := 12.0
const MIN_BOARD_VISIBLE_HEIGHT_DEFAULT := 520.0
const MIN_BOARD_VISIBLE_HEIGHT_COMPACT := 500.0
const MIN_BOARD_VISIBLE_HEIGHT_SMALL := 520.0

@onready var game_manager: GameManager = $GameManager
@onready var background_texture_rect: TextureRect = $BackgroundLayer/Background
@onready var selection_highlight: TextureRect = $EffectLayer/SelectionHighlight
@onready var slot_highlight: TextureRect = $EffectLayer/SlotHighlight
@onready var board_layer: Control = $BoardLayer
@onready var opponent_board: BoardView = $BoardLayer/OpponentBoard
@onready var player_board: BoardView = $BoardLayer/PlayerBoard
@onready var top_hud: MarginContainer = $UILayer/TopHUD
@onready var bottom_hud: MarginContainer = $UILayer/BottomHUD
@onready var bottom_panel: PanelContainer = $UILayer/BottomHUD/BottomPanel
@onready var top_bar: HFlowContainer = $UILayer/TopHUD/TopBar
@onready var turn_label: Label = $UILayer/TopHUD/TopBar/TurnLabel
@onready var active_player_label: Label = $UILayer/TopHUD/TopBar/ActivePlayerLabel
@onready var phase_indicator: PhaseIndicator = $UILayer/TopHUD/TopBar/PhaseIndicator
@onready var next_phase_button: Button = $UILayer/TopHUD/TopBar/NextPhaseButton
@onready var bonus_draw_button: Button = $UILayer/TopHUD/TopBar/BonusDrawButton
@onready var no_block_button: Button = $UILayer/TopHUD/TopBar/NoBlockButton
@onready var winner_label: Label = $UILayer/TopHUD/TopBar/WinnerLabel
@onready var hand_view: HandView = $UILayer/BottomHUD/BottomPanel/BottomContent/HandView
@onready var card_preview_panel: CardPreviewPanel = $UILayer/BottomHUD/BottomPanel/BottomContent/CardPreviewPanel
@onready var action_bar: HFlowContainer = $UILayer/BottomHUD/BottomPanel/BottomContent/ActionBar
@onready var selected_card_label: Label = $UILayer/BottomHUD/BottomPanel/BottomContent/ActionBar/SelectedCardLabel
@onready var play_front_button: Button = $UILayer/BottomHUD/BottomPanel/BottomContent/ActionBar/PlayFrontButton
@onready var play_energy_button: Button = $UILayer/BottomHUD/BottomPanel/BottomContent/ActionBar/PlayEnergyButton
@onready var raid_button: Button = $UILayer/BottomHUD/BottomPanel/BottomContent/ActionBar/RaidButton
@onready var use_event_button: Button = $UILayer/BottomHUD/BottomPanel/BottomContent/ActionBar/UseEventButton
@onready var main_activate_button: Button = $UILayer/BottomHUD/BottomPanel/BottomContent/ActionBar/MainActivateButton
@onready var step_button: Button = $UILayer/BottomHUD/BottomPanel/BottomContent/ActionBar/StepButton
@onready var move_front_button: Button = $UILayer/BottomHUD/BottomPanel/BottomContent/ActionBar/MoveFrontButton
@onready var sniper_attack_button: Button = $UILayer/BottomHUD/BottomPanel/BottomContent/ActionBar/SniperAttackButton
@onready var life_trigger_picker: OptionButton = $UILayer/BottomHUD/BottomPanel/BottomContent/ActionBar/LifeTriggerPicker
@onready var activate_life_button: Button = $UILayer/BottomHUD/BottomPanel/BottomContent/ActionBar/ActivateLifeButton
@onready var skip_life_button: Button = $UILayer/BottomHUD/BottomPanel/BottomContent/ActionBar/SkipLifeButton
@onready var cancel_selection_button: Button = $UILayer/BottomHUD/BottomPanel/BottomContent/ActionBar/CancelSelectionButton
@onready var pending_decision_panel: VBoxContainer = $UILayer/BottomHUD/BottomPanel/BottomContent/PendingDecisionPanel
@onready var pending_decision_label: Label = $UILayer/BottomHUD/BottomPanel/BottomContent/PendingDecisionPanel/PendingDecisionLabel
@onready var pending_decision_picker: OptionButton = $UILayer/BottomHUD/BottomPanel/BottomContent/PendingDecisionPanel/PendingDecisionPicker
@onready var pending_decision_choice_picker: OptionButton = $UILayer/BottomHUD/BottomPanel/BottomContent/PendingDecisionPanel/PendingDecisionChoicePicker
@onready var resolve_pending_decision_button: Button = $UILayer/BottomHUD/BottomPanel/BottomContent/PendingDecisionPanel/ResolvePendingDecisionButton
@onready var log_panel: LogPanel = $UILayer/LogPanel
@onready var log_toggle_button: Button = $UILayer/TopHUD/TopBar/LogToggleButton

var _snapshot: Dictionary = {}
var _selected_hand_card_uid := ""
var _selected_board_card_uid := ""
var _selected_board_zone_name := ""
var _pending_attack_uid := ""
var _pending_defender_player_id := ""
var _sniper_attack_source_uid := ""
var _selected_life_trigger_uid := ""
var _selected_pending_decision_index := -1
var _selected_pending_decision_choice_index := 0
var _raid_source_card_uid := ""
var _raid_target_selection_mode := false

func _ready() -> void:
	_setup_optional_art()
	game_manager.state_changed.connect(_on_state_changed)
	game_manager.blockers_requested.connect(_on_blockers_requested)
	next_phase_button.pressed.connect(_on_next_phase_pressed)
	bonus_draw_button.pressed.connect(_on_bonus_draw_pressed)
	no_block_button.pressed.connect(_on_no_block_pressed)
	play_front_button.pressed.connect(_on_play_front_pressed)
	play_energy_button.pressed.connect(_on_play_energy_pressed)
	raid_button.pressed.connect(_on_raid_pressed)
	use_event_button.pressed.connect(_on_use_event_pressed)
	main_activate_button.pressed.connect(_on_main_activate_pressed)
	step_button.pressed.connect(_on_step_pressed)
	move_front_button.pressed.connect(_on_move_front_pressed)
	sniper_attack_button.pressed.connect(_on_sniper_attack_pressed)
	activate_life_button.pressed.connect(_on_activate_life_pressed)
	skip_life_button.pressed.connect(_on_skip_life_pressed)
	life_trigger_picker.item_selected.connect(_on_life_trigger_selected)
	pending_decision_picker.item_selected.connect(_on_pending_decision_selected)
	pending_decision_choice_picker.item_selected.connect(_on_pending_decision_choice_selected)
	resolve_pending_decision_button.pressed.connect(_on_resolve_pending_decision_pressed)
	cancel_selection_button.pressed.connect(_clear_selection)
	log_toggle_button.pressed.connect(_on_log_toggle_pressed)
	hand_view.hand_card_selected.connect(_on_hand_card_selected)
	hand_view.hand_card_hovered.connect(_on_hand_card_hovered)
	opponent_board.front_card_pressed.connect(_on_front_card_pressed)
	opponent_board.energy_card_pressed.connect(_on_energy_card_pressed)
	opponent_board.zone_drop_requested.connect(_on_zone_drop_requested)
	player_board.front_card_pressed.connect(_on_front_card_pressed)
	player_board.energy_card_pressed.connect(_on_energy_card_pressed)
	player_board.zone_drop_requested.connect(_on_zone_drop_requested)
	_clear_selection()
	no_block_button.visible = false
	bonus_draw_button.visible = false
	main_activate_button.visible = false
	step_button.visible = false
	move_front_button.visible = false
	sniper_attack_button.visible = false
	raid_button.visible = false
	life_trigger_picker.visible = false
	activate_life_button.visible = false
	skip_life_button.visible = false
	pending_decision_panel.visible = false
	get_viewport().size_changed.connect(_update_responsive_layout)
	_update_responsive_layout()
	_on_state_changed(game_manager.get_snapshot())
	call_deferred("_run_layout_probe_if_requested")

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
	var viewport_size := get_viewport_rect().size
	var viewport_width: float = viewport_size.x
	var viewport_height: float = viewport_size.y

	# Calculate letterboxing for background image
	var bg_transform := ZoneLayoutConfig.calculate_bg_transform(viewport_width, viewport_height)
	var bg_scale_factor: float = bg_transform.scale_factor
	var bg_display_width: float = bg_transform.display_width
	var letterbox_offset: float = bg_transform.letterbox_offset

	# Update background TextureRect to show letterboxing
	background_texture_rect.position.x = letterbox_offset
	background_texture_rect.size.x = bg_display_width
	background_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	var compact := viewport_height < COMPACT_HEIGHT_THRESHOLD or viewport_width < COMPACT_WIDTH_THRESHOLD
	var very_small := viewport_height < SMALL_HEIGHT_THRESHOLD or viewport_width < SMALL_WIDTH_THRESHOLD
	var bottom_height: float = 112.0 if very_small else (160.0 if compact else 180.0)

	top_hud.offset_top = 8.0 if very_small else 12.0
	bottom_hud.offset_top = -(bottom_height + BOTTOM_HUD_BOTTOM_MARGIN)
	bottom_panel.custom_minimum_size = Vector2(0, bottom_height)

	top_bar.alignment = FlowContainer.ALIGNMENT_CENTER
	top_bar.add_theme_constant_override("h_separation", 6 if very_small else (8 if compact else 12))
	top_bar.add_theme_constant_override("v_separation", 4 if very_small else 6)
	action_bar.add_theme_constant_override("h_separation", 4 if very_small else (8 if compact else 10))
	action_bar.add_theme_constant_override("v_separation", 4 if very_small else 6)
	selected_card_label.custom_minimum_size = Vector2(120 if very_small else (180 if compact else 220), 0)
	hand_view.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Update board views with absolute positioning
	opponent_board.update_layout(letterbox_offset, bg_scale_factor)
	player_board.update_layout(letterbox_offset, bg_scale_factor)

	opponent_board.set_compact_mode(compact, very_small)
	player_board.set_compact_mode(compact, very_small)
	hand_view.set_compact_mode(compact, very_small)

	# Calculate hand bounds avoiding remove_area and outside_area
	var remove_rect := ZoneLayoutConfig.get_zone_rect("P1", "remove_area", letterbox_offset, bg_scale_factor)
	var outside_rect := ZoneLayoutConfig.get_zone_rect("P1", "outside_area", letterbox_offset, bg_scale_factor)
	var hand_left := remove_rect.position.x + remove_rect.size.x + 20.0
	var hand_right := outside_rect.position.x - 20.0
	var hand_width := hand_right - hand_left
	hand_view.set_hand_bounds(hand_left, hand_right, hand_width)

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
	_update_hand_playable_states(active_player_id, active_hand)
	_sync_pending_decision_controls()
	_sync_life_trigger_controls()
	selected_card_label.text = _selected_label_text(active_player_id)
	_update_action_buttons()
	log_panel.set_logs(snapshot.get("logs", []))
	var has_winner := str(snapshot.get("winner_player_id", "")) != ""
	var has_pending_life := _has_pending_life_triggers()
	var has_pending_decisions := _has_pending_decisions()
	var has_pending_gate := has_pending_life or has_pending_decisions
	var phase := str(snapshot.get("phase", "START"))
	var can_bonus_draw := bool(snapshot.get("can_bonus_draw", false))
	bonus_draw_button.visible = phase == "DRAW"
	bonus_draw_button.disabled = has_winner or has_pending_gate or not can_bonus_draw
	next_phase_button.disabled = has_winner or has_pending_gate
	play_front_button.disabled = play_front_button.disabled or has_winner or has_pending_gate
	play_energy_button.disabled = play_energy_button.disabled or has_winner or has_pending_gate
	use_event_button.disabled = use_event_button.disabled or has_winner or has_pending_gate
	main_activate_button.disabled = main_activate_button.disabled or has_winner or has_pending_gate
	step_button.disabled = step_button.disabled or has_winner or has_pending_gate
	move_front_button.disabled = move_front_button.disabled or has_winner or has_pending_gate
	sniper_attack_button.disabled = sniper_attack_button.disabled or has_winner or has_pending_gate
	no_block_button.disabled = has_winner or has_pending_gate
	cancel_selection_button.disabled = cancel_selection_button.disabled or has_winner or has_pending_gate
	activate_life_button.disabled = has_winner or not has_pending_life or _selected_life_trigger_uid == ""
	skip_life_button.disabled = has_winner or not has_pending_life or _selected_life_trigger_uid == ""
	pending_decision_panel.visible = has_pending_decisions
	resolve_pending_decision_button.disabled = has_winner or not has_pending_decisions or _selected_pending_decision_index < 0

func _on_hand_card_selected(card_uid: String) -> void:
	if _has_pending_gate():
		return
	_selected_hand_card_uid = card_uid
	_selected_board_card_uid = ""
	_selected_board_zone_name = ""
	_sniper_attack_source_uid = ""
	_update_action_buttons()
	selected_card_label.text = _selected_label_text(str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE)))
	# 更新预览面板
	var active_player_id := str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE))
	var card_data := _find_hand_card(active_player_id, card_uid)
	if not card_data.is_empty():
		card_preview_panel.set_card_data(card_data)

func _on_hand_card_hovered(card_uid: String, is_hovered: bool) -> void:
	if is_hovered:
		var active_player_id := str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE))
		var card_data := _find_hand_card(active_player_id, card_uid)
		if not card_data.is_empty():
			card_preview_panel.set_card_data(card_data)
	else:
		# 如果有选中的牌，保持显示选中的牌
		if _selected_hand_card_uid != "":
			var active_player_id := str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE))
			var card_data := _find_hand_card(active_player_id, _selected_hand_card_uid)
			if not card_data.is_empty():
				card_preview_panel.set_card_data(card_data)
		else:
			card_preview_panel.clear_card()

func _on_front_card_pressed(player_id: String, card_uid: String) -> void:
	if _has_pending_gate():
		return
	# 处理RAID目标选择
	if _raid_target_selection_mode:
		if player_id == str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE)):
			_execute_raid_play(card_uid)
		return
	var active_player_id := str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE))
	var phase := str(_snapshot.get("phase", ""))
	var card_data := _find_board_card(player_id, card_uid)
	var board_actions: Array = card_data.get("available_actions", [])
	if _sniper_attack_source_uid != "":
		if player_id != active_player_id:
			game_manager.request_attack(_sniper_attack_source_uid, {
				"target_kind": "FRONT_CHARACTER",
				"target_uid": card_uid,
			})
			_sniper_attack_source_uid = ""
			_clear_selection()
		return
	if _pending_attack_uid != "":
		if player_id == _pending_defender_player_id:
			game_manager.resolve_attack(_pending_attack_uid, card_uid)
			_clear_pending_attack()
		return
	_selected_board_card_uid = card_uid
	_selected_board_zone_name = "front_line"
	_selected_hand_card_uid = ""
	_update_action_buttons()
	selected_card_label.text = _selected_label_text(str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE)))
	if phase == "ATTACK" and player_id == active_player_id:
		if board_actions.has("SNIPER_ATTACK"):
			_sniper_attack_source_uid = card_uid
			_update_action_buttons()
			selected_card_label.text = _selected_label_text(active_player_id)
			return
		if board_actions.has("ATTACK_PLAYER"):
			game_manager.request_attack(card_uid)
			return

func _on_energy_card_pressed(player_id: String, card_uid: String) -> void:
	if _has_pending_gate():
		return
	# 处理RAID目标选择
	if _raid_target_selection_mode:
		if player_id == str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE)):
			_execute_raid_play(card_uid)
		return
	_selected_board_card_uid = card_uid
	_selected_board_zone_name = "energy_line"
	_selected_hand_card_uid = ""
	_update_action_buttons()
	selected_card_label.text = _selected_label_text(str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE)))
	var active_player_id := str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE))
	var card_data := _find_board_card(player_id, card_uid)
	var card_name := str(card_data.get("name", card_uid))
	var action_text := ", ".join(card_data.get("available_actions", []) as Array)
	if action_text == "":
		action_text = "none"
	game_manager.append_ui_log("Select energy card: %s | owner=%s | active=%s | phase=%s | actions=%s" % [card_name, player_id, active_player_id, str(_snapshot.get("phase", "")), action_text])

func _on_zone_drop_requested(player_id: String, zone_name: String, card_uid: String) -> void:
	if _has_pending_gate():
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
	if _has_pending_gate():
		return
	_clear_pending_attack()
	game_manager.advance_phase()

func _on_no_block_pressed() -> void:
	if _has_pending_gate():
		return
	if _pending_attack_uid == "":
		return
	game_manager.resolve_attack(_pending_attack_uid)
	_clear_pending_attack()

func _on_bonus_draw_pressed() -> void:
	if _has_pending_gate():
		return
	game_manager.request_bonus_draw()

func _on_play_front_pressed() -> void:
	if _has_pending_gate():
		return
	if _selected_hand_card_uid != "":
		game_manager.play_card(_selected_hand_card_uid, UATypes.Zone.FRONT_LINE)
		_clear_selection()

func _on_play_energy_pressed() -> void:
	if _has_pending_gate():
		return
	if _selected_hand_card_uid != "":
		game_manager.play_card(_selected_hand_card_uid, UATypes.Zone.ENERGY_LINE)
		_clear_selection()

func _on_use_event_pressed() -> void:
	if _has_pending_gate():
		return
	if _selected_hand_card_uid != "":
		game_manager.play_card(_selected_hand_card_uid, UATypes.Zone.OUTSIDE)
		_clear_selection()

func _on_raid_pressed() -> void:
	if _has_pending_gate() or _selected_hand_card_uid == "":
		return
	_raid_source_card_uid = _selected_hand_card_uid
	_raid_target_selection_mode = true
	_update_action_buttons()
	selected_card_label.text = "Choose a RAID target on your field"

func _execute_raid_play(target_uid: String) -> void:
	if _raid_source_card_uid == "":
		return
	var target_data := _find_board_card(str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE)), target_uid)
	var target_zone_name := str(target_data.get("zone", "front_line"))
	var target_zone := UATypes.Zone.FRONT_LINE if target_zone_name == "front_line" else UATypes.Zone.ENERGY_LINE

	game_manager.play_card(_raid_source_card_uid, target_zone, {"raid_target_uid": target_uid})
	_clear_raid_selection()
	_clear_selection()

func _clear_raid_selection() -> void:
	_raid_source_card_uid = ""
	_raid_target_selection_mode = false

func _on_main_activate_pressed() -> void:
	if _selected_board_card_uid == "" or _has_pending_gate():
		return
	game_manager.request_main_activate(_selected_board_card_uid)

func _on_step_pressed() -> void:
	if _selected_board_card_uid == "" or _has_pending_gate():
		return
	game_manager.request_step_move(_selected_board_card_uid)

func _on_move_front_pressed() -> void:
	if _selected_board_card_uid == "":
		game_manager.append_ui_log("Move Front ignored: no selected board card.")
		return
	if _has_pending_gate():
		game_manager.append_ui_log("Move Front ignored: pending gate is active.")
		return
	var active_player_id := str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE))
	var card_data := _find_board_card(active_player_id, _selected_board_card_uid)
	if card_data.is_empty():
		game_manager.append_ui_log("Move Front ignored: selected card not found in active player's board snapshot.")
		return
	if _selected_board_zone_name != "energy_line":
		game_manager.append_ui_log("Move Front ignored: selected card is not from energy line.")
		return
	var action_text := ", ".join(card_data.get("available_actions", []) as Array)
	if action_text == "":
		action_text = "none"
	game_manager.append_ui_log("Move Front pressed: %s | phase=%s | actions=%s" % [str(card_data.get("name", _selected_board_card_uid)), str(_snapshot.get("phase", "")), action_text])
	game_manager.move_energy_to_front(_selected_board_card_uid)

func _on_sniper_attack_pressed() -> void:
	if _selected_board_card_uid == "" or _has_pending_gate():
		return
	var active_player_id := str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE))
	var card_data := _find_board_card(active_player_id, _selected_board_card_uid)
	if not (card_data.get("available_actions", []) as Array).has("SNIPER_ATTACK"):
		return
	_sniper_attack_source_uid = _selected_board_card_uid
	selected_card_label.text = "Choose an enemy front target for sniper attack"

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
	_selected_board_card_uid = ""
	_selected_board_zone_name = ""
	_sniper_attack_source_uid = ""
	_clear_raid_selection()
	_update_action_buttons()
	selected_card_label.text = _selected_label_text(str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE)))

func _clear_pending_attack() -> void:
	_pending_attack_uid = ""
	_pending_defender_player_id = ""
	no_block_button.visible = false
	bonus_draw_button.visible = false


func _on_log_toggle_pressed() -> void:
	log_panel.visible = not log_panel.visible

func _selected_label_text(active_player_id: String) -> String:
	if _has_pending_decisions():
		if _selected_pending_decision_index >= 0:
			var pending_decisions: Array = _snapshot.get("pending_decisions", [])
			if _selected_pending_decision_index < pending_decisions.size():
				var decision: Dictionary = pending_decisions[_selected_pending_decision_index]
				return "Pending: %s (%s)" % [str(decision.get("type", "decision")), str(decision.get("source_card_uid", ""))]
		return "Resolve pending decision"
	if _has_pending_life_triggers():
		var owner_id := ""
		for entry_variant in _snapshot.get("pending_life_triggers", []):
			var entry: Dictionary = entry_variant
			owner_id = str(entry.get("player_id", owner_id))
			if str(entry.get("card_uid", "")) == _selected_life_trigger_uid:
				return "Life trigger: %s chooses %s" % [owner_id, str(entry.get("card_name", "Unknown"))]
		return "Resolve pending life triggers"
	if _raid_target_selection_mode:
		return "Choose a RAID target on your field"
	if _sniper_attack_source_uid != "":
		return "Choose an enemy front target for sniper attack"
	if _pending_attack_uid != "":
		return "Choose a blocker or click No Block"
	if _selected_board_card_uid != "":
		var board_card: Dictionary = _find_board_card(active_player_id, _selected_board_card_uid)
		if not board_card.is_empty():
			return "Selected: %s" % str(board_card.get("name", "Unknown"))
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

func _find_board_card(player_id: String, card_uid: String) -> Dictionary:
	var players: Dictionary = _snapshot.get("players", {})
	var player_data: Dictionary = players.get(player_id, {})
	for zone_name in ["front_line", "energy_line"]:
		for card_data in player_data.get(zone_name, []):
			if str(card_data.get("uid", "")) == card_uid:
				return card_data
	return {}

func _update_action_buttons() -> void:
	var active_player_id := str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE))
	var card_data: Dictionary = _find_hand_card(active_player_id, _selected_hand_card_uid)
	var card_type := str(card_data.get("card_type", ""))
	var available_actions: Array = card_data.get("available_actions", [])
	var board_card_data: Dictionary = _find_board_card(active_player_id, _selected_board_card_uid)
	var board_actions: Array = board_card_data.get("available_actions", [])
	play_front_button.disabled = card_type != "CHARACTER"
	play_energy_button.disabled = card_type != "CHARACTER" and card_type != "FIELD"
	use_event_button.disabled = card_type != "EVENT"

	# RAID按钮
	raid_button.visible = available_actions.has("RAID")
	raid_button.disabled = not available_actions.has("RAID") or _raid_target_selection_mode

	# RAID选择模式时禁用其他打出按钮
	if _raid_target_selection_mode:
		play_front_button.disabled = true
		play_energy_button.disabled = true
		use_event_button.disabled = true

	main_activate_button.visible = not board_card_data.is_empty() and board_actions.has("MAIN_ACTIVATE")
	main_activate_button.disabled = not board_actions.has("MAIN_ACTIVATE")
	step_button.visible = not board_card_data.is_empty() and board_actions.has("STEP_TO_ENERGY")
	step_button.disabled = not board_actions.has("STEP_TO_ENERGY")
	move_front_button.visible = not board_card_data.is_empty() and board_actions.has("MOVE_TO_FRONT")
	move_front_button.disabled = not board_actions.has("MOVE_TO_FRONT")
	sniper_attack_button.visible = not board_card_data.is_empty() and board_actions.has("SNIPER_ATTACK")
	sniper_attack_button.disabled = not board_actions.has("SNIPER_ATTACK") or _sniper_attack_source_uid != ""
	cancel_selection_button.disabled = _selected_hand_card_uid == "" and _selected_board_card_uid == "" and _sniper_attack_source_uid == "" and _raid_source_card_uid == ""

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

func _sync_pending_decision_controls() -> void:
	var pending: Array = _snapshot.get("pending_decisions", [])
	pending_decision_picker.clear()
	pending_decision_choice_picker.clear()
	if pending.is_empty():
		_selected_pending_decision_index = -1
		_selected_pending_decision_choice_index = 0
		pending_decision_panel.visible = false
		return
	for i in range(pending.size()):
		var decision: Dictionary = pending[i]
		var summary := str(decision.get("source_card_uid", ""))
		if summary == "":
			summary = str(decision.get("owner_player_id", ""))
		pending_decision_picker.add_item("%s: %s" % [str(decision.get("type", "")), summary])
		pending_decision_picker.set_item_metadata(i, i)
	if _selected_pending_decision_index < 0 or _selected_pending_decision_index >= pending.size():
		_selected_pending_decision_index = 0
	pending_decision_picker.select(_selected_pending_decision_index)
	_rebuild_pending_decision_choices()
	pending_decision_panel.visible = true

func _rebuild_pending_decision_choices() -> void:
	pending_decision_choice_picker.clear()
	var pending: Array = _snapshot.get("pending_decisions", [])
	if _selected_pending_decision_index < 0 or _selected_pending_decision_index >= pending.size():
		return
	var decision: Dictionary = pending[_selected_pending_decision_index]
	var owner_text := str(decision.get("owner_player_id", ""))
	if owner_text == "":
		pending_decision_label.text = "Pending Decision: %s" % str(decision.get("type", "Decision"))
	else:
		pending_decision_label.text = "Pending Decision: %s (%s)" % [str(decision.get("type", "Decision")), owner_text]
	var choices: Array = decision.get("choices", [])
	for i in range(choices.size()):
		var choice: Dictionary = choices[i]
		pending_decision_choice_picker.add_item(str(choice.get("label", choice.get("value", ""))))
		pending_decision_choice_picker.set_item_metadata(i, choice.get("value"))
	if choices.is_empty():
		_selected_pending_decision_choice_index = -1
		return
	if _selected_pending_decision_choice_index < 0 or _selected_pending_decision_choice_index >= choices.size():
		_selected_pending_decision_choice_index = 0
	pending_decision_choice_picker.select(_selected_pending_decision_choice_index)

func _on_pending_decision_selected(index: int) -> void:
	_selected_pending_decision_index = index
	_selected_pending_decision_choice_index = 0
	_rebuild_pending_decision_choices()
	selected_card_label.text = _selected_label_text(str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE)))

func _on_pending_decision_choice_selected(index: int) -> void:
	_selected_pending_decision_choice_index = index

func _on_resolve_pending_decision_pressed() -> void:
	var pending: Array = _snapshot.get("pending_decisions", [])
	if _selected_pending_decision_index < 0 or _selected_pending_decision_index >= pending.size():
		return
	var decision: Dictionary = pending[_selected_pending_decision_index]
	var choice_value = pending_decision_choice_picker.get_item_metadata(_selected_pending_decision_choice_index)
	game_manager.resolve_pending_decision(str(decision.get("type", "")), {
		"source_card_uid": str(decision.get("source_card_uid", "")),
		"choice": choice_value,
	})

func _has_pending_life_triggers() -> bool:
	return not (_snapshot.get("pending_life_triggers", []) as Array).is_empty()

func _has_pending_decisions() -> bool:
	return not (_snapshot.get("pending_decisions", []) as Array).is_empty()

func _has_pending_gate() -> bool:
	return _has_pending_life_triggers() or _has_pending_decisions()

func _update_hand_playable_states(player_id: String, hand_cards: Array) -> void:
	var phase := str(_snapshot.get("phase", ""))
	var playable_map := {}

	# 只有在 MAIN 阶段才标记可打出状态
	if phase != "MAIN":
		hand_view.set_playable_cards(playable_map)
		return

	# 检查每张手牌是否可打出
	for card_data in hand_cards:
		var card_uid := str(card_data.get("uid", ""))
		var available_actions: Array = card_data.get("available_actions", [])

		# 检查是否有可用的打出动作（包括RAID）
		var is_playable := available_actions.has("PLAY_FRONT") or available_actions.has("PLAY_ENERGY") or available_actions.has("PLAY_EVENT") or available_actions.has("RAID")
		playable_map[card_uid] = is_playable

	hand_view.set_playable_cards(playable_map)

func _run_layout_probe_if_requested() -> void:
	if not OS.get_cmdline_user_args().has("--layout-probe"):
		return
	if game_state_has_opening_probe_pending():
		game_manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})
		game_manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})
	_update_responsive_layout()
	call_deferred("_finish_layout_probe")

func _finish_layout_probe() -> void:
	var label := "%dx%d" % [int(get_viewport_rect().size.x), int(get_viewport_rect().size.y)]
	var player_board_rect := player_board.get_global_rect()
	var hand_rect := hand_view.get_global_rect()
	var error := ""

	# Check board layer has expected zone wrappers
	if player_board.get_child_count() < 6:
		error = "玩家战场缺失区域容器 (expected >= 6 zones, got %d)" % player_board.get_child_count()
	elif player_board_rect.position.y + player_board_rect.size.y > hand_rect.position.y + 1.0:
		error = "玩家战场与手牌缩略图区域发生重叠 (board_bottom=%.1f, hand_top=%.1f)" % [
			player_board_rect.position.y + player_board_rect.size.y,
			hand_rect.position.y,
		]
	elif hand_view.get_child_count() == 0:
		error = "手牌容器没有任何卡牌"

	if error == "":
		var card_count := hand_view.get_card_count()
		if card_count > 0:
			print("[PASS] UI 布局 %s (hand cards: %d)" % [label, card_count])
			get_tree().quit(0)
			return
		else:
			error = "手牌区域没有卡牌"

	push_error("[FAIL] UI 布局 %s: %s" % [label, error])
	get_tree().quit(1)

func game_state_has_opening_probe_pending() -> bool:
	return game_manager.game_state.pending_decisions.size() >= 1 and str((game_manager.game_state.pending_decisions[0] as Dictionary).get("type", "")) == "MULLIGAN_CHOICE"
