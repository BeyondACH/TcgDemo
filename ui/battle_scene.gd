extends Control
class_name BattleScene

const BoardTargetSelectionHelper = preload("res://ui/board_target_selection_helper.gd")
const BATTLE_BG_PATH := "res://assets/battle/backgrounds/battle_bg.jpg"
const SELECTION_HIGHLIGHT_PATH := "res://assets/battle/effects/selection_highlight.png"
const SLOT_HIGHLIGHT_PATH := "res://assets/battle/effects/slot_highlight.png"
const COMPACT_HEIGHT_THRESHOLD := 1120.0
const SMALL_HEIGHT_THRESHOLD := 940.0
const COMPACT_WIDTH_THRESHOLD := 1820.0
const SMALL_WIDTH_THRESHOLD := 1650.0
const BOARD_BOTTOM_GAP := 18.0
const BOARD_TOP_GAP := 18.0
const BOTTOM_HUD_BOTTOM_MARGIN := 12.0
const BOTTOM_HUD_SIDE_MARGIN := 12.0
const HAND_STRIP_HEIGHT_DEFAULT := 176.0
const HAND_STRIP_HEIGHT_COMPACT := 160.0
const HAND_STRIP_HEIGHT_SMALL := 148.0
const HAND_STRIP_INTERNAL_WIDTH_MARGIN := 24.0
const PREVIEW_PANEL_LEFT_MARGIN := 12.0
const PREVIEW_PANEL_TOP_GAP := 12.0
const PREVIEW_PANEL_BOTTOM_CLEARANCE := 16.0
const LOG_PANEL_TOP_GAP := 10.0
const LOG_PANEL_RIGHT_MARGIN := 12.0
const LOG_PANEL_DEFAULT_WIDTH := 340.0
const LOG_PANEL_COMPACT_WIDTH := 300.0
const LOG_PANEL_SMALL_WIDTH := 280.0
const LOG_PANEL_MIN_HEIGHT := 180.0
const LOG_PANEL_BOTTOM_CLEARANCE := 16.0
const MIN_BOARD_VISIBLE_HEIGHT_DEFAULT := 520.0
const MIN_BOARD_VISIBLE_HEIGHT_COMPACT := 500.0
const MIN_BOARD_VISIBLE_HEIGHT_SMALL := 520.0
const AI_ACTION_HINT_HOLD_SECONDS := 0.8
const AI_ACTION_HINT_FADE_SECONDS := 0.35

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
@onready var top_bar: HBoxContainer = $UILayer/TopHUD/TopBar
@onready var status_row: HFlowContainer = $UILayer/TopHUD/TopBar/StatusRow
@onready var action_row: VBoxContainer = $UILayer/TopHUD/TopBar/ActionRow
@onready var action_button_row: HBoxContainer = $UILayer/TopHUD/TopBar/ActionRow/ActionButtonRow
@onready var ai_action_label: Label = $UILayer/TopHUD/TopBar/ActionRow/AIActionLabel
@onready var phase_controls: VBoxContainer = $UILayer/TopHUD/TopBar/PhaseControls
@onready var turn_label: Label = $UILayer/TopHUD/TopBar/StatusRow/TurnLabel
@onready var active_player_label: Label = $UILayer/TopHUD/TopBar/StatusRow/ActivePlayerLabel
@onready var player_info_row: HFlowContainer = $UILayer/TopHUD/TopBar/ActionRow/PlayerInfoPanel/PlayerInfoRow
@onready var phase_indicator: PhaseIndicator = $UILayer/TopHUD/TopBar/ActionRow/PlayerInfoPanel/PlayerInfoRow/PhaseIndicator
@onready var hand_count_label: Label = $UILayer/TopHUD/TopBar/ActionRow/PlayerInfoPanel/PlayerInfoRow/HandCountLabel
@onready var energy_label: Label = $UILayer/TopHUD/TopBar/ActionRow/PlayerInfoPanel/PlayerInfoRow/EnergyLabel
@onready var ap_label: Label = $UILayer/TopHUD/TopBar/ActionRow/PlayerInfoPanel/PlayerInfoRow/ApLabel
@onready var next_phase_button: Button = $UILayer/TopHUD/TopBar/PhaseControls/NextPhaseButton
@onready var bonus_draw_button: Button = $UILayer/TopHUD/TopBar/ActionRow/ActionButtonRow/BonusDrawButton
@onready var no_block_button: Button = $UILayer/TopHUD/TopBar/ActionRow/ActionButtonRow/NoBlockButton
@onready var winner_label: Label = $UILayer/TopHUD/TopBar/StatusRow/WinnerLabel
@onready var hand_view: HandView = $UILayer/BottomHUD/BottomPanel/BottomContent/HandView
@onready var card_preview_panel: CardPreviewPanel = $UILayer/CardPreviewPanel
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
@onready var preview_selection_modal: PreviewSelectionModal = $UILayer/PreviewSelectionModal
@onready var log_toggle_button: Button = $UILayer/TopHUD/TopBar/PhaseControls/LogToggleButton
@onready var deck_selection_modal: Control = $UILayer/DeckSelectionModal
@onready var deck_selection_status_label: Label = $UILayer/DeckSelectionModal/CenterContainer/DeckSelectionPanel/DeckSelectionContent/DeckSelectionStatusLabel
@onready var player_one_deck_picker: OptionButton = $UILayer/DeckSelectionModal/CenterContainer/DeckSelectionPanel/DeckSelectionContent/PlayerOneDeckPicker
@onready var player_two_deck_picker: OptionButton = $UILayer/DeckSelectionModal/CenterContainer/DeckSelectionPanel/DeckSelectionContent/PlayerTwoDeckPicker
@onready var start_game_button: Button = $UILayer/DeckSelectionModal/CenterContainer/DeckSelectionPanel/DeckSelectionContent/StartGameButton

var _snapshot: Dictionary = {}
var _life_reveal_modal: LifeRevealModal
var _zone_cards_popup: ZoneCardsPopup
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
var _preview_card_uid := ""
var _preview_player_id := ""
var _preview_zone_name := ""
var _available_decks: Array[Dictionary] = []
var _opening_setup_pending := true
var _ai_action_hint_tween: Tween

func _ready() -> void:
	_setup_optional_art()
	game_manager.state_changed.connect(_on_state_changed)
	game_manager.blockers_requested.connect(_on_blockers_requested)
	game_manager.ai_action_executed.connect(_on_ai_action_executed)
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
	preview_selection_modal.submitted.connect(_on_preview_modal_submitted)
	_life_reveal_modal = LifeRevealModal.new()
	_life_reveal_modal.name = "LifeRevealModal"
	$UILayer.add_child(_life_reveal_modal)
	_life_reveal_modal.activate_requested.connect(_on_life_reveal_activate_requested)
	_life_reveal_modal.skip_requested.connect(_on_life_reveal_skip_requested)
	_life_reveal_modal.acknowledge_requested.connect(_on_life_reveal_acknowledge_requested)
	_zone_cards_popup = ZoneCardsPopup.new()
	_zone_cards_popup.name = "ZoneCardsPopup"
	$UILayer.add_child(_zone_cards_popup)
	cancel_selection_button.pressed.connect(_clear_selection)
	log_toggle_button.pressed.connect(_on_log_toggle_pressed)
	start_game_button.pressed.connect(_on_start_game_pressed)
	hand_view.hand_card_selected.connect(_on_hand_card_selected)
	hand_view.hand_card_hovered.connect(_on_hand_card_hovered)
	opponent_board.front_card_pressed.connect(_on_front_card_pressed)
	opponent_board.energy_card_pressed.connect(_on_energy_card_pressed)
	opponent_board.zone_drop_requested.connect(_on_zone_drop_requested)
	opponent_board.zone_stack_requested.connect(_on_zone_stack_requested)
	player_board.front_card_pressed.connect(_on_front_card_pressed)
	player_board.energy_card_pressed.connect(_on_energy_card_pressed)
	player_board.zone_drop_requested.connect(_on_zone_drop_requested)
	player_board.zone_stack_requested.connect(_on_zone_stack_requested)
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
	deck_selection_modal.visible = false
	_load_deck_selection_options()
	get_viewport().size_changed.connect(_update_responsive_layout)
	_update_responsive_layout()
	_clear_ai_action_hint()
	_on_state_changed(game_manager.get_snapshot())
	_show_deck_selection_modal()
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

	var compact := viewport_height < COMPACT_HEIGHT_THRESHOLD or viewport_width < COMPACT_WIDTH_THRESHOLD
	var very_small := viewport_height < SMALL_HEIGHT_THRESHOLD or viewport_width < SMALL_WIDTH_THRESHOLD

	top_hud.offset_top = 8.0 if very_small else 12.0
	top_bar.add_theme_constant_override("separation", 8 if compact else 12)
	status_row.add_theme_constant_override("h_separation", 6 if very_small else (8 if compact else 12))
	status_row.add_theme_constant_override("v_separation", 4 if very_small else 6)
	action_row.add_theme_constant_override("separation", 4 if very_small else (6 if compact else 8))
	action_button_row.add_theme_constant_override("separation", 6 if very_small else (8 if compact else 12))
	phase_controls.add_theme_constant_override("separation", 4 if very_small else 6)
	player_info_row.add_theme_constant_override("h_separation", 6 if very_small else (8 if compact else 10))
	player_info_row.add_theme_constant_override("v_separation", 4 if very_small else 6)
	bottom_panel.get_child(0).add_theme_constant_override("separation", 6 if very_small else (8 if compact else 10))
	action_bar.add_theme_constant_override("h_separation", 4 if very_small else (8 if compact else 10))
	action_bar.add_theme_constant_override("v_separation", 4 if very_small else 6)
	selected_card_label.custom_minimum_size = Vector2(120 if very_small else (180 if compact else 220), 0)
	action_bar.custom_minimum_size = Vector2(0, 36 if very_small else 40)
	hand_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var hand_strip_height := HAND_STRIP_HEIGHT_SMALL if very_small else (HAND_STRIP_HEIGHT_COMPACT if compact else HAND_STRIP_HEIGHT_DEFAULT)
	var top_hud_height := maxf(top_hud.get_combined_minimum_size().y, 48.0)
	top_hud.offset_bottom = top_hud.offset_top + top_hud_height

	var background_top := top_hud.offset_bottom + BOARD_TOP_GAP
	var available_battle_height := viewport_height - background_top - hand_strip_height - BOARD_BOTTOM_GAP - BOTTOM_HUD_BOTTOM_MARGIN
	var minimum_board_height := MIN_BOARD_VISIBLE_HEIGHT_SMALL if very_small else (MIN_BOARD_VISIBLE_HEIGHT_COMPACT if compact else MIN_BOARD_VISIBLE_HEIGHT_DEFAULT)
	var battle_height := minf(maxf(minimum_board_height, available_battle_height), viewport_height - background_top)
	var bg_transform := ZoneLayoutConfig.calculate_bg_transform(viewport_width, battle_height, background_top)
	var bg_scale_factor: float = bg_transform.scale_factor
	var bg_display_width: float = bg_transform.display_width
	var bg_display_height: float = bg_transform.display_height
	var letterbox_offset: float = bg_transform.letterbox_offset
	var bg_top_offset: float = bg_transform.top_offset

	background_texture_rect.position = Vector2(letterbox_offset, bg_top_offset)
	background_texture_rect.size = Vector2(bg_display_width, bg_display_height)
	background_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	var bottom_strip_top := bg_top_offset + bg_display_height + BOARD_BOTTOM_GAP
	bottom_hud.offset_left = BOTTOM_HUD_SIDE_MARGIN
	bottom_hud.offset_right = -BOTTOM_HUD_SIDE_MARGIN
	bottom_hud.offset_top = bottom_strip_top
	bottom_hud.offset_bottom = bottom_strip_top + hand_strip_height
	bottom_panel.custom_minimum_size = Vector2(0, hand_strip_height)

	# Update board views with absolute positioning
	opponent_board.update_layout(letterbox_offset, bg_scale_factor, bg_top_offset)
	player_board.update_layout(letterbox_offset, bg_scale_factor, bg_top_offset)

	opponent_board.set_compact_mode(compact, very_small)
	player_board.set_compact_mode(compact, very_small)
	hand_view.set_compact_mode(compact, very_small)

	var hand_width := maxf(320.0, viewport_width - BOTTOM_HUD_SIDE_MARGIN * 2.0 - HAND_STRIP_INTERNAL_WIDTH_MARGIN)
	hand_view.set_hand_bounds(0.0, hand_width, hand_width)
	_update_preview_panel_layout()
	_update_log_panel_layout(compact, very_small, viewport_height)

func _update_preview_panel_layout() -> void:
	var top_hud_rect := top_hud.get_global_rect()
	var bottom_hud_rect := bottom_hud.get_global_rect()
	var panel_top := top_hud_rect.position.y + top_hud_rect.size.y + PREVIEW_PANEL_TOP_GAP
	var available_panel_height := bottom_hud_rect.position.y - panel_top - PREVIEW_PANEL_BOTTOM_CLEARANCE
	card_preview_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	card_preview_panel.apply_layout(available_panel_height)
	card_preview_panel.position = Vector2(PREVIEW_PANEL_LEFT_MARGIN, panel_top)

func _update_log_panel_layout(compact: bool, very_small: bool, viewport_height: float) -> void:
	var toggle_rect := log_toggle_button.get_global_rect()
	var bottom_hud_rect := bottom_hud.get_global_rect()
	var panel_width := LOG_PANEL_SMALL_WIDTH if very_small else (LOG_PANEL_COMPACT_WIDTH if compact else LOG_PANEL_DEFAULT_WIDTH)
	var panel_top := toggle_rect.position.y + toggle_rect.size.y + LOG_PANEL_TOP_GAP
	var panel_height := maxf(LOG_PANEL_MIN_HEIGHT, bottom_hud_rect.position.y - panel_top - LOG_PANEL_BOTTOM_CLEARANCE)
	var panel_left := minf(
		get_viewport_rect().size.x - panel_width - LOG_PANEL_RIGHT_MARGIN,
		toggle_rect.position.x + toggle_rect.size.x - panel_width
	)
	log_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	log_panel.position = Vector2(maxf(12.0, panel_left), panel_top)
	log_panel.size = Vector2(panel_width, minf(panel_height, viewport_height - panel_top - LOG_PANEL_BOTTOM_CLEARANCE))

func _on_ai_action_executed(action_info: Dictionary) -> void:
	var action_text := _format_ai_action_text(action_info)
	if action_text == "":
		return
	if _ai_action_hint_tween != null and is_instance_valid(_ai_action_hint_tween):
		_ai_action_hint_tween.kill()
	ai_action_label.text = action_text
	ai_action_label.visible = true
	ai_action_label.modulate = Color(1, 1, 1, 1)
	_ai_action_hint_tween = create_tween()
	_ai_action_hint_tween.tween_interval(AI_ACTION_HINT_HOLD_SECONDS)
	_ai_action_hint_tween.tween_property(ai_action_label, "modulate:a", 0.0, AI_ACTION_HINT_FADE_SECONDS)
	_ai_action_hint_tween.finished.connect(_clear_ai_action_hint, CONNECT_ONE_SHOT)


func _clear_ai_action_hint() -> void:
	if ai_action_label == null:
		return
	ai_action_label.text = ""
	ai_action_label.visible = false
	ai_action_label.modulate = Color(1, 1, 1, 1)
	_ai_action_hint_tween = null


func _format_ai_action_text(action_info: Dictionary) -> String:
	var player_text := _format_ai_player_text(str(action_info.get("player_id", "")))
	var action_type := str(action_info.get("action_type", ""))
	var source_name := str(action_info.get("source_card_name", ""))
	var target_name := str(action_info.get("target_name", ""))
	var phase := str(action_info.get("phase", ""))
	match action_type:
		ActionTypes.ADVANCE_PHASE:
			return "%s进入 %s 阶段" % [player_text, phase]
		ActionTypes.BONUS_DRAW:
			return "%s支付 1 AP 额外抽牌" % player_text
		ActionTypes.PLAY_CARD:
			var zone_text := _format_target_zone_text(int(action_info.get("target_zone", -1)))
			if source_name != "" and zone_text != "":
				return "%s打出 %s 到%s" % [player_text, source_name, zone_text]
			if source_name != "":
				return "%s打出 %s" % [player_text, source_name]
			return "%s打出卡牌" % player_text
		ActionTypes.MOVE_CARD:
			var move_mode := str(action_info.get("move_mode", ""))
			if move_mode == ActionTypes.MOVE_ENERGY_TO_FRONT:
				return "%s让 %s 从能量线前移" % [player_text, source_name if source_name != "" else "角色"]
			if move_mode == ActionTypes.MOVE_STEP_TO_ENERGY:
				return "%s让 %s 撤步回能量线" % [player_text, source_name if source_name != "" else "角色"]
			return "%s移动卡牌" % player_text
		ActionTypes.ATTACK:
			if str(action_info.get("target_kind", "PLAYER")) == "CHARACTER":
				return "%s用 %s 攻击 %s" % [player_text, source_name if source_name != "" else "角色", target_name if target_name != "" else "角色"]
			return "%s用 %s 攻击玩家" % [player_text, source_name if source_name != "" else "角色"]
		ActionTypes.BLOCK:
			return "%s用 %s 进行阻挡" % [player_text, str(action_info.get("blocker_name", "")) if str(action_info.get("blocker_name", "")) != "" else "角色"]
		ActionTypes.NO_BLOCK:
			return "%s选择不阻挡" % player_text
		ActionTypes.RESOLVE_PENDING_DECISION:
			return "%s处理%s" % [player_text, _format_pending_decision_text(str(action_info.get("decision_type", "")))]
		ActionTypes.RESOLVE_LIFE_TRIGGER:
			var life_name := target_name if target_name != "" else source_name
			if bool(action_info.get("activate", false)):
				return "%s发动生命触发%s" % [player_text, "：%s" % life_name if life_name != "" else ""]
			return "%s跳过生命触发%s" % [player_text, "：%s" % life_name if life_name != "" else ""]
		ActionTypes.END_TURN:
			return "%s结束当前回合" % player_text
	return ""


func _format_ai_player_text(player_id: String) -> String:
	if player_id == UATypes.PLAYER_ONE:
		return "玩家 1（AI）"
	if player_id == UATypes.PLAYER_TWO:
		return "玩家 2（AI）"
	return "%s（AI）" % player_id


func _format_target_zone_text(target_zone: int) -> String:
	if target_zone == UATypes.Zone.FRONT_LINE:
		return "前线"
	if target_zone == UATypes.Zone.ENERGY_LINE:
		return "能量线"
	return ""


func _format_pending_decision_text(decision_type: String) -> String:
	match decision_type:
		"MULLIGAN_CHOICE":
			return "起手换牌决策"
		"RAID_ZONE_CHOICE":
			return "RAID 落点选择"
		"LIFE_TRIGGER_RAID_CHOICE":
			return "生命触发 RAID 选择"
		"LIFE_TRIGGER_RAID_TARGET":
			return "生命触发 RAID 目标选择"
		"STEP_SWAP_CHOICE":
			return "STEP 交换选择"
		"HAND_LIMIT_DISCARD":
			return "手牌上限弃牌"
		"ABILITY_TARGET_SELECTION":
			return "效果目标选择"
	return "待决策"

func _on_state_changed(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	if _zone_cards_popup != null and _zone_cards_popup.visible:
		_zone_cards_popup.hide_popup()
	var active_player_id := str(snapshot.get("active_player_id", UATypes.PLAYER_ONE))
	var display_hand_player_id := _display_hand_player_id()
	var priority_player_id := str(snapshot.get("priority_player_id", active_player_id))
	var controller_types: Dictionary = snapshot.get("controller_types", {})
	var players: Dictionary = snapshot.get("players", {})
	var p1: Dictionary = _decorate_board_targets(UATypes.PLAYER_ONE, players.get(UATypes.PLAYER_ONE, {}))
	var p2: Dictionary = _decorate_board_targets(UATypes.PLAYER_TWO, players.get(UATypes.PLAYER_TWO, {}))
	var active_player_data: Dictionary = p1 if active_player_id == UATypes.PLAYER_ONE else p2
	var display_hand_player_data: Dictionary = p1 if display_hand_player_id == UATypes.PLAYER_ONE else p2
	var action_controller_type := str(controller_types.get(priority_player_id, snapshot.get("action_player_controller", "HUMAN")))
	turn_label.text = "Turn %d" % int(snapshot.get("turn_number", 1))
	active_player_label.text = "Action: %s (%s)" % [priority_player_id, action_controller_type]
	phase_indicator.set_phase_text(str(snapshot.get("phase", "START")))
	hand_count_label.text = "Hand: %d" % int(display_hand_player_data.get("hand_count", 0))
	energy_label.text = "Energy: %s" % _format_energy_total(active_player_data.get("available_energy", {}))
	ap_label.text = "AP: %d/%d" % [int(active_player_data.get("ap_active", 0)), int(active_player_data.get("ap_total", 0))]
	winner_label.text = "Winner: %s" % str(snapshot.get("winner_player_id", "-"))
	opponent_board.set_board(UATypes.PLAYER_TWO, "Player 2", p2)
	player_board.set_board(UATypes.PLAYER_ONE, "Player 1", p1)
	var active_hand: Array = p2.get("hand", [])
	if display_hand_player_id == UATypes.PLAYER_ONE:
		active_hand = p1.get("hand", [])
	hand_view.set_hand(display_hand_player_id, active_hand)
	_update_hand_playable_states(display_hand_player_id, active_hand)
	_sync_pending_decision_controls()
	_sync_preview_selection_modal()
	_sync_life_reveal_modal()
	_sync_life_trigger_controls()
	_sync_preview_panel()
	selected_card_label.text = _selected_label_text(display_hand_player_id)
	_update_action_buttons()
	log_panel.set_logs(snapshot.get("logs", []))
	var has_winner := str(snapshot.get("winner_player_id", "")) != ""
	var has_pending_life := _has_pending_life_triggers()
	var has_pending_life_reveal := _has_pending_life_reveal()
	var has_pending_decisions := _has_pending_decisions()
	var has_pending_gate := has_pending_life or has_pending_life_reveal or has_pending_decisions
	var phase := str(snapshot.get("phase", "START"))
	var can_bonus_draw := bool(snapshot.get("can_bonus_draw", false))
	var human_input_enabled := _human_input_enabled()
	bonus_draw_button.visible = phase == "DRAW"
	bonus_draw_button.disabled = has_winner or has_pending_gate or not can_bonus_draw or not human_input_enabled
	next_phase_button.disabled = has_winner or has_pending_gate or not human_input_enabled
	play_front_button.disabled = play_front_button.disabled or has_winner or has_pending_gate
	play_energy_button.disabled = play_energy_button.disabled or has_winner or has_pending_gate
	use_event_button.disabled = use_event_button.disabled or has_winner or has_pending_gate
	main_activate_button.disabled = main_activate_button.disabled or has_winner or has_pending_gate
	step_button.disabled = step_button.disabled or has_winner or has_pending_gate
	move_front_button.disabled = move_front_button.disabled or has_winner or has_pending_gate
	sniper_attack_button.disabled = sniper_attack_button.disabled or has_winner or has_pending_gate
	no_block_button.disabled = has_winner or has_pending_gate or not human_input_enabled
	cancel_selection_button.disabled = cancel_selection_button.disabled or has_winner or has_pending_gate or not human_input_enabled
	activate_life_button.disabled = true
	skip_life_button.disabled = true
	pending_decision_panel.visible = has_pending_decisions
	if _is_preview_pending_decision(_current_pending_decision()):
		pending_decision_panel.visible = false
	resolve_pending_decision_button.disabled = has_winner or not has_pending_decisions or _selected_pending_decision_index < 0 or not human_input_enabled
	_refresh_deck_selection_modal_state()

func _load_deck_selection_options() -> void:
	_available_decks = game_manager.get_available_decks()
	player_one_deck_picker.clear()
	player_two_deck_picker.clear()
	for deck in _available_decks:
		var deck_name := str(deck.get("name", ""))
		player_one_deck_picker.add_item(deck_name)
		player_two_deck_picker.add_item(deck_name)
	if _available_decks.is_empty():
		deck_selection_status_label.text = "未在 data/decks 中找到可用的 txt 卡组。"
		start_game_button.disabled = true
		return
	player_one_deck_picker.select(_preferred_deck_index("starter_a", 0))
	player_two_deck_picker.select(_preferred_deck_index("starter_b", min(1, _available_decks.size() - 1)))
	start_game_button.disabled = false
	deck_selection_status_label.text = "请选择双方卡组后开始对局。"

func _preferred_deck_index(preferred_name: String, fallback_index: int) -> int:
	for i in range(_available_decks.size()):
		if str(_available_decks[i].get("file_name", "")).get_basename() == preferred_name:
			return i
	return clampi(fallback_index, 0, max(0, _available_decks.size() - 1))

func _show_deck_selection_modal() -> void:
	_opening_setup_pending = true
	_refresh_deck_selection_modal_state()
	deck_selection_modal.visible = true

func _hide_deck_selection_modal() -> void:
	deck_selection_modal.visible = false

func _refresh_deck_selection_modal_state() -> void:
	if deck_selection_modal == null:
		return
	var can_start := _opening_setup_pending and not _available_decks.is_empty() and player_one_deck_picker.selected >= 0 and player_two_deck_picker.selected >= 0
	player_one_deck_picker.disabled = not _opening_setup_pending or _available_decks.is_empty()
	player_two_deck_picker.disabled = not _opening_setup_pending or _available_decks.is_empty()
	start_game_button.disabled = not can_start
	if not _opening_setup_pending:
		_hide_deck_selection_modal()
	elif _available_decks.is_empty():
		deck_selection_status_label.text = "未在 data/decks 中找到可用的 txt 卡组。"

func _selected_deck_path(picker: OptionButton) -> String:
	var index := picker.selected
	if index < 0 or index >= _available_decks.size():
		return ""
	return str(_available_decks[index].get("path", ""))

func _start_game_with_selected_decks() -> void:
	var player_one_deck_path := _selected_deck_path(player_one_deck_picker)
	var player_two_deck_path := _selected_deck_path(player_two_deck_picker)
	if player_one_deck_path == "" or player_two_deck_path == "":
		deck_selection_status_label.text = "请先为双方选择卡组。"
		return
	_opening_setup_pending = false
	_hide_deck_selection_modal()
	_clear_selection()
	game_manager.setup_game({
		"player_decks": {
			UATypes.PLAYER_ONE: player_one_deck_path,
			UATypes.PLAYER_TWO: player_two_deck_path,
		}
	})

func _on_start_game_pressed() -> void:
	_start_game_with_selected_decks()

func _on_hand_card_selected(card_uid: String) -> void:
	if _has_pending_gate() or not _human_input_enabled():
		return
	if _raid_target_selection_mode and _raid_source_card_uid != card_uid:
		_clear_raid_selection()
	_selected_hand_card_uid = card_uid
	_selected_board_card_uid = ""
	_selected_board_zone_name = ""
	_sniper_attack_source_uid = ""
	_update_action_buttons()
	var display_hand_player_id := _display_hand_player_id()
	selected_card_label.text = _selected_label_text(display_hand_player_id)
	var card_data := _find_hand_card(display_hand_player_id, card_uid)
	if not card_data.is_empty():
		_set_preview_card(card_data, {
			"relation_label": "己方",
			"zone_label": "手牌",
		})

func _on_hand_card_hovered(card_uid: String, is_hovered: bool) -> void:
	# 悬停不再驱动底部预览面板显隐，避免 BottomContent 因新增预览面板高度而整体上抬。
	if _selected_hand_card_uid == "":
		return
	if not is_hovered and card_uid == _selected_hand_card_uid:
		var display_hand_player_id := _display_hand_player_id()
		var card_data := _find_hand_card(display_hand_player_id, _selected_hand_card_uid)
		if not card_data.is_empty():
			_set_preview_card(card_data, {
				"relation_label": "己方",
				"zone_label": "手牌",
			})

func _on_front_card_pressed(player_id: String, card_uid: String, pressed_card_data: Dictionary = {}) -> void:
	var card_data := pressed_card_data if not pressed_card_data.is_empty() else _find_board_card(player_id, card_uid)
	if not card_data.is_empty():
		_set_board_preview(player_id, "front_line", card_data)
	if _resolve_board_target_selection_from_card(player_id, card_uid, "front_line"):
		return
	if _has_pending_gate() or not _human_input_enabled():
		return
	# 处理RAID目标选择
	if _raid_target_selection_mode:
		if player_id == str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE)):
			_execute_raid_play(card_uid)
		return
	var active_player_id := str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE))
	var phase := str(_snapshot.get("phase", ""))
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
	if player_id != active_player_id:
		_clear_raid_selection()
		_selected_board_card_uid = ""
		_selected_board_zone_name = ""
		_selected_hand_card_uid = ""
		_update_action_buttons()
		selected_card_label.text = _selected_label_text(_display_hand_player_id())
		return
	_clear_raid_selection()
	_selected_board_card_uid = card_uid
	_selected_board_zone_name = "front_line"
	_selected_hand_card_uid = ""
	_update_action_buttons()
	selected_card_label.text = _selected_label_text(_display_hand_player_id())
	if phase == "ATTACK" and player_id == active_player_id:
		if board_actions.has("SNIPER_ATTACK"):
			_sniper_attack_source_uid = card_uid
			_update_action_buttons()
			selected_card_label.text = _selected_label_text(active_player_id)
			return
		if board_actions.has("ATTACK_PLAYER"):
			game_manager.request_attack(card_uid)
			return

func _on_energy_card_pressed(player_id: String, card_uid: String, pressed_card_data: Dictionary = {}) -> void:
	var card_data := pressed_card_data if not pressed_card_data.is_empty() else _find_board_card(player_id, card_uid)
	if not card_data.is_empty():
		_set_board_preview(player_id, "energy_line", card_data)
	if _resolve_board_target_selection_from_card(player_id, card_uid, "energy_line"):
		return
	if _has_pending_gate() or not _human_input_enabled():
		return
	# 处理RAID目标选择
	if _raid_target_selection_mode:
		if player_id == str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE)):
			_execute_raid_play(card_uid)
		return
	var active_player_id := str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE))
	if player_id != active_player_id:
		_clear_raid_selection()
		_selected_board_card_uid = ""
		_selected_board_zone_name = ""
		_selected_hand_card_uid = ""
		_update_action_buttons()
		selected_card_label.text = _selected_label_text(_display_hand_player_id())
		return
	_clear_raid_selection()
	_selected_board_card_uid = card_uid
	_selected_board_zone_name = "energy_line"
	_selected_hand_card_uid = ""
	_update_action_buttons()
	selected_card_label.text = _selected_label_text(_display_hand_player_id())
	var card_name := str(card_data.get("name", card_uid))
	var action_text := ", ".join(card_data.get("available_actions", []) as Array)
	if action_text == "":
		action_text = "none"
	game_manager.append_ui_log("Select energy card: %s | owner=%s | active=%s | phase=%s | actions=%s" % [card_name, player_id, active_player_id, str(_snapshot.get("phase", "")), action_text])

func _on_zone_drop_requested(player_id: String, zone_name: String, card_uid: String) -> void:
	if _has_pending_gate() or not _human_input_enabled():
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
	var controller_types: Dictionary = _snapshot.get("controller_types", {})
	var defender_player_id := str(request.get("defender_player_id", ""))
	if str(controller_types.get(defender_player_id, "HUMAN")) != "HUMAN":
		return
	var blockers: Array = request.get("blockers", [])
	if blockers.is_empty():
		game_manager.resolve_attack(str(request.get("attacker_uid", "")))
		return
	_pending_attack_uid = str(request.get("attacker_uid", ""))
	_pending_defender_player_id = defender_player_id
	no_block_button.visible = true
	selected_card_label.text = "Choose a blocker or click No Block"

func _on_next_phase_pressed() -> void:
	if _has_pending_gate() or not _human_input_enabled():
		return
	_clear_pending_attack()
	game_manager.advance_phase()

func _on_no_block_pressed() -> void:
	if _has_pending_gate() or not _human_input_enabled():
		return
	if _pending_attack_uid == "":
		return
	game_manager.resolve_attack(_pending_attack_uid)
	_clear_pending_attack()

func _on_bonus_draw_pressed() -> void:
	if _has_pending_gate() or not _human_input_enabled():
		return
	game_manager.request_bonus_draw()

func _on_play_front_pressed() -> void:
	if _has_pending_gate() or not _human_input_enabled():
		return
	if _selected_hand_card_uid != "":
		game_manager.play_card(_selected_hand_card_uid, UATypes.Zone.FRONT_LINE)
		_clear_selection()

func _on_play_energy_pressed() -> void:
	if _has_pending_gate() or not _human_input_enabled():
		return
	if _selected_hand_card_uid != "":
		game_manager.play_card(_selected_hand_card_uid, UATypes.Zone.ENERGY_LINE)
		_clear_selection()

func _on_use_event_pressed() -> void:
	if _has_pending_gate() or not _human_input_enabled():
		return
	if _selected_hand_card_uid != "":
		game_manager.play_card(_selected_hand_card_uid, UATypes.Zone.OUTSIDE)
		_clear_selection()

func _on_raid_pressed() -> void:
	if _has_pending_gate() or _selected_hand_card_uid == "" or not _human_input_enabled():
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
	if _selected_board_card_uid == "" or _has_pending_gate() or not _human_input_enabled():
		return
	game_manager.request_main_activate(_selected_board_card_uid)

func _on_step_pressed() -> void:
	if _selected_board_card_uid == "" or _has_pending_gate() or not _human_input_enabled():
		return
	game_manager.request_step_move(_selected_board_card_uid)

func _on_move_front_pressed() -> void:
	if not _human_input_enabled():
		return
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
	if _selected_board_card_uid == "" or _has_pending_gate() or not _human_input_enabled():
		return
	var active_player_id := str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE))
	var card_data := _find_board_card(active_player_id, _selected_board_card_uid)
	if not (card_data.get("available_actions", []) as Array).has("SNIPER_ATTACK"):
		return
	_sniper_attack_source_uid = _selected_board_card_uid
	selected_card_label.text = "Choose an enemy front target for sniper attack"

func _on_activate_life_pressed() -> void:
	if _selected_life_trigger_uid == "" or not _human_input_enabled():
		return
	game_manager.resolve_life_trigger_decision(_selected_life_trigger_uid, true)

func _on_skip_life_pressed() -> void:
	if _selected_life_trigger_uid == "" or not _human_input_enabled():
		return
	game_manager.resolve_life_trigger_decision(_selected_life_trigger_uid, false)

func _on_life_trigger_selected(index: int) -> void:
	var pending: Array = _snapshot.get("pending_life_triggers", [])
	if index < 0 or index >= pending.size():
		_selected_life_trigger_uid = ""
		return
	_selected_life_trigger_uid = str((pending[index] as Dictionary).get("card_uid", ""))
	selected_card_label.text = _selected_label_text(_display_hand_player_id())

func _clear_selection() -> void:
	_selected_hand_card_uid = ""
	_selected_board_card_uid = ""
	_selected_board_zone_name = ""
	_sniper_attack_source_uid = ""
	_clear_preview_card()
	_clear_raid_selection()
	_update_action_buttons()
	selected_card_label.text = _selected_label_text(_display_hand_player_id())

func _clear_pending_attack() -> void:
	_pending_attack_uid = ""
	_pending_defender_player_id = ""
	no_block_button.visible = false
	bonus_draw_button.visible = false


func _on_log_toggle_pressed() -> void:
	log_panel.visible = not log_panel.visible

func _selected_label_text(active_player_id: String) -> String:
	if _is_board_target_selection_pending(_current_pending_decision()):
		return "Choose a battlefield target"
	var life_reveal_modal: Dictionary = _current_life_reveal_modal()
	if bool(life_reveal_modal.get("visible", false)):
		var current_card_uid := str(life_reveal_modal.get("current_card_uid", ""))
		if current_card_uid == "":
			return "Life reveal complete"
		for card_variant in life_reveal_modal.get("revealed_cards", []):
			var revealed_card: Dictionary = card_variant
			if str(revealed_card.get("uid", "")) == current_card_uid:
				return "Life reveal: %s" % str(revealed_card.get("name", current_card_uid))
		return "Life reveal in progress"
	if _has_pending_decisions():
		var decision := _current_pending_decision()
		if not decision.is_empty():
			if _is_board_target_selection_pending(decision):
				return "Choose a battlefield target"
			if _is_preview_pending_decision(decision):
				return str(decision.get("title", "处理看牌堆顶"))
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
	if _preview_card_uid != "":
		var preview_card := _find_preview_card()
		if not preview_card.is_empty():
			return "Previewing: %s" % str(preview_card.get("name", "Unknown"))
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

func _find_zone_cards(player_id: String, zone_name: String) -> Array:
	var players: Dictionary = _snapshot.get("players", {})
	var player_data: Dictionary = players.get(player_id, {})
	var cards_variant = player_data.get(zone_name, [])
	if cards_variant is Array:
		var cards: Array = []
		for card_data_variant in cards_variant:
			var card_data: Dictionary = (card_data_variant as Dictionary).duplicate(true)
			card_data["owner_player_id"] = player_id
			cards.append(card_data)
		return cards
	return []

func _find_preview_card() -> Dictionary:
	if _preview_card_uid == "":
		return {}
	if _preview_zone_name == "hand":
		return _find_hand_card(_preview_player_id, _preview_card_uid)
	return _find_board_card(_preview_player_id, _preview_card_uid)

func _set_preview_card(card_data: Dictionary, preview_context: Dictionary, player_id: String = "", zone_name: String = "") -> void:
	_preview_card_uid = str(card_data.get("uid", ""))
	_preview_player_id = player_id
	_preview_zone_name = zone_name
	card_preview_panel.set_preview(card_data, preview_context)

func _set_board_preview(player_id: String, zone_name: String, card_data: Dictionary) -> void:
	var active_player_id := str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE))
	_set_preview_card(card_data, {
		"relation_label": "己方" if player_id == active_player_id else "对手",
		"zone_label": "前线" if zone_name == "front_line" else "能量线",
	}, player_id, zone_name)

func _clear_preview_card() -> void:
	_preview_card_uid = ""
	_preview_player_id = ""
	_preview_zone_name = ""
	card_preview_panel.clear_card()

func _on_zone_stack_requested(player_id: String, zone_name: String) -> void:
	var cards := _find_zone_cards(player_id, zone_name)
	var active_player_id := str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE))
	var relation_label := "己方" if player_id == active_player_id else "对手"
	var zone_label := "除外区" if zone_name == "removed" else "场外区"
	_zone_cards_popup.show_zone_cards("%s %s" % [relation_label, zone_label], cards)

func _sync_preview_panel() -> void:
	var active_player_id := str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE))
	var display_hand_player_id := _display_hand_player_id()
	if _selected_hand_card_uid != "":
		var hand_card := _find_hand_card(display_hand_player_id, _selected_hand_card_uid)
		if not hand_card.is_empty():
			_set_preview_card(hand_card, {
				"relation_label": "己方",
				"zone_label": "手牌",
			}, display_hand_player_id, "hand")
			return
		_selected_hand_card_uid = ""
	if _selected_board_card_uid != "":
		var board_card := _find_board_card(active_player_id, _selected_board_card_uid)
		if not board_card.is_empty():
			_set_board_preview(active_player_id, _selected_board_zone_name, board_card)
			return
		_selected_board_card_uid = ""
		_selected_board_zone_name = ""
	if _preview_card_uid != "":
		var preview_card := _find_preview_card()
		if not preview_card.is_empty():
			if _preview_zone_name == "hand":
				_set_preview_card(preview_card, {
					"relation_label": "己方" if _preview_player_id == display_hand_player_id else "对手",
					"zone_label": "手牌",
				}, _preview_player_id, _preview_zone_name)
			else:
				_set_board_preview(_preview_player_id, _preview_zone_name, preview_card)
			return
	_clear_preview_card()

func _update_action_buttons() -> void:
	var active_player_id := str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE))
	var display_hand_player_id := _display_hand_player_id()
	var input_enabled := _human_input_enabled()
	var card_data: Dictionary = _find_hand_card(display_hand_player_id, _selected_hand_card_uid)
	var card_type := str(card_data.get("card_type", ""))
	var available_actions: Array = card_data.get("available_actions", [])
	var special_play_rule: Dictionary = card_data.get("special_play_rule", {})
	var is_raid_card := str(special_play_rule.get("type", "")) == "RAID"
	var board_card_data: Dictionary = _find_board_card(active_player_id, _selected_board_card_uid)
	var board_actions: Array = board_card_data.get("available_actions", [])
	play_front_button.disabled = card_type != "CHARACTER" or not input_enabled
	play_energy_button.disabled = (card_type != "CHARACTER" and card_type != "FIELD") or not input_enabled
	use_event_button.disabled = card_type != "EVENT" or not input_enabled

	# Keep RAID cards discoverable even when the current state makes RAID illegal.
	raid_button.visible = is_raid_card
	raid_button.disabled = not available_actions.has("RAID") or _raid_target_selection_mode or not input_enabled
	if available_actions.has("RAID"):
		raid_button.tooltip_text = "选择己方场上的符合条件角色作为 RAID 底座。"
	elif is_raid_card and bool(special_play_rule.get("life_trigger_only", false)):
		raid_button.tooltip_text = "这张牌当前只能通过生命触发或临时特殊许可进行 RAID。"
	elif is_raid_card:
		raid_button.tooltip_text = "当前没有满足条件的能量、AP 或 RAID 底座，暂时不能使用 RAID。"
	else:
		raid_button.tooltip_text = ""

	# RAID选择模式时禁用其他打出按钮
	if _raid_target_selection_mode:
		play_front_button.disabled = true
		play_energy_button.disabled = true
		use_event_button.disabled = true

	main_activate_button.visible = not board_card_data.is_empty() and board_actions.has("MAIN_ACTIVATE")
	main_activate_button.disabled = not board_actions.has("MAIN_ACTIVATE") or not input_enabled
	step_button.visible = not board_card_data.is_empty() and board_actions.has("STEP_TO_ENERGY")
	step_button.disabled = not board_actions.has("STEP_TO_ENERGY") or not input_enabled
	move_front_button.visible = not board_card_data.is_empty() and board_actions.has("MOVE_TO_FRONT")
	move_front_button.disabled = not board_actions.has("MOVE_TO_FRONT") or not input_enabled
	sniper_attack_button.visible = not board_card_data.is_empty() and board_actions.has("SNIPER_ATTACK")
	sniper_attack_button.disabled = not board_actions.has("SNIPER_ATTACK") or _sniper_attack_source_uid != "" or not input_enabled
	cancel_selection_button.disabled = (_selected_hand_card_uid == "" and _selected_board_card_uid == "" and _sniper_attack_source_uid == "" and _raid_source_card_uid == "") or not input_enabled

func _sync_life_trigger_controls() -> void:
	_selected_life_trigger_uid = ""
	life_trigger_picker.clear()
	life_trigger_picker.visible = false
	activate_life_button.visible = false
	skip_life_button.visible = false

func _sync_pending_decision_controls() -> void:
	var pending: Array = _snapshot.get("pending_decisions", [])
	pending_decision_picker.clear()
	pending_decision_choice_picker.clear()
	if pending.is_empty() or not _human_input_enabled():
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
	var selected_decision: Dictionary = pending[_selected_pending_decision_index]
	if _is_preview_pending_decision(selected_decision):
		pending_decision_panel.visible = false
		return
	pending_decision_picker.select(_selected_pending_decision_index)
	_rebuild_pending_decision_choices()
	pending_decision_panel.visible = true

func _rebuild_pending_decision_choices() -> void:
	pending_decision_choice_picker.clear()
	var decision := _current_pending_decision()
	if decision.is_empty() or _is_preview_pending_decision(decision):
		return
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
	_sync_preview_selection_modal()
	selected_card_label.text = _selected_label_text(_display_hand_player_id())

func _on_pending_decision_choice_selected(index: int) -> void:
	_selected_pending_decision_choice_index = index

func _on_resolve_pending_decision_pressed() -> void:
	if not _human_input_enabled():
		return
	var pending: Array = _snapshot.get("pending_decisions", [])
	if _selected_pending_decision_index < 0 or _selected_pending_decision_index >= pending.size():
		return
	var decision: Dictionary = pending[_selected_pending_decision_index]
	var choice_value = pending_decision_choice_picker.get_item_metadata(_selected_pending_decision_choice_index)
	game_manager.resolve_pending_decision(str(decision.get("type", "")), {
		"source_card_uid": str(decision.get("source_card_uid", "")),
		"choice": choice_value,
	})

func _on_preview_modal_submitted(selected_values: Array) -> void:
	if not _human_input_enabled():
		return
	var decision := _current_pending_decision()
	if decision.is_empty():
		return
	var payload := {
		"source_card_uid": str(decision.get("source_card_uid", "")),
		"resolution_id": str(decision.get("resolution_id", "")),
	}
	if int(decision.get("max", 1)) == 1:
		payload["choice"] = str(selected_values[0]) if not selected_values.is_empty() else ""
	else:
		payload["choices"] = selected_values.duplicate()
	game_manager.resolve_pending_decision(str(decision.get("type", "")), payload)

func _has_pending_life_triggers() -> bool:
	return not (_snapshot.get("pending_life_triggers", []) as Array).is_empty()

func _has_pending_life_reveal() -> bool:
	return bool((_snapshot.get("life_reveal_modal", {}) as Dictionary).get("visible", false))

func _has_pending_decisions() -> bool:
	return not (_snapshot.get("pending_decisions", []) as Array).is_empty()

func _has_pending_gate() -> bool:
	return _has_pending_life_triggers() or _has_pending_life_reveal() or _has_pending_decisions()

func _current_life_reveal_modal() -> Dictionary:
	return _snapshot.get("life_reveal_modal", {})

func _current_pending_decision() -> Dictionary:
	var pending: Array = _snapshot.get("pending_decisions", [])
	if pending.is_empty():
		return {}
	if _selected_pending_decision_index < 0 or _selected_pending_decision_index >= pending.size():
		_selected_pending_decision_index = 0
	return pending[_selected_pending_decision_index]

func _is_preview_pending_decision(decision: Dictionary) -> bool:
	return str(decision.get("ui_mode", "")) == "PREVIEW_PICK" or str(decision.get("ui_mode", "")) == "PREVIEW_REORDER"

func _sync_preview_selection_modal() -> void:
	var decision := _current_pending_decision()
	if not _human_input_enabled() or decision.is_empty() or not _is_preview_pending_decision(decision):
		preview_selection_modal.hide_modal()
		return
	preview_selection_modal.show_decision(decision)

func _sync_life_reveal_modal() -> void:
	var modal_data := _current_life_reveal_modal()
	if not bool(modal_data.get("visible", false)):
		if _life_reveal_modal != null:
			_life_reveal_modal.hide_modal()
		return
	if _should_allow_board_selection_passthrough():
		if _life_reveal_modal != null:
			_life_reveal_modal.hide_modal()
		return
	if _life_reveal_modal != null:
		_life_reveal_modal.show_modal(modal_data)
		_life_reveal_modal.set_input_blocking(true)

func _on_life_reveal_activate_requested(card_uid: String) -> void:
	var modal_data := _current_life_reveal_modal()
	if not bool(modal_data.get("can_activate", false)):
		return
	game_manager.resolve_life_trigger_decision(card_uid, true)

func _on_life_reveal_skip_requested(card_uid: String) -> void:
	var modal_data := _current_life_reveal_modal()
	if not bool(modal_data.get("can_skip", false)):
		return
	game_manager.resolve_life_trigger_decision(card_uid, false)

func _on_life_reveal_acknowledge_requested(card_uid: String) -> void:
	var modal_data := _current_life_reveal_modal()
	if not bool(modal_data.get("can_acknowledge", false)):
		return
	game_manager.acknowledge_life_reveal(card_uid)

func _update_hand_playable_states(_player_id: String, hand_cards: Array) -> void:
	var phase := str(_snapshot.get("phase", ""))
	var playable_map := {}
	if phase != "MAIN" or not _human_input_enabled():
		hand_view.set_playable_cards(playable_map)
		return

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

func _human_input_enabled() -> bool:
	return not _opening_setup_pending and bool(_snapshot.get("human_input_enabled", true))

func _display_hand_player_id() -> String:
	return str(_snapshot.get("display_hand_player_id", _snapshot.get("priority_player_id", UATypes.PLAYER_ONE)))

func _decorate_board_targets(player_id: String, player_data_variant) -> Dictionary:
	var player_data: Dictionary = (player_data_variant as Dictionary).duplicate(true)
	var selectable_uids := _current_board_target_uid_set()
	if selectable_uids.is_empty():
		return player_data
	for zone_name in ["front_line", "energy_line"]:
		var cards: Array = player_data.get(zone_name, [])
		var decorated_cards: Array = []
		for card_variant in cards:
			var card_data: Dictionary = (card_variant as Dictionary).duplicate(true)
			var card_uid := str(card_data.get("uid", ""))
			var target_meta := _board_target_meta_for(card_uid)
			card_data["pending_target_selectable"] = selectable_uids.has(card_uid) \
				and str(target_meta.get("player_id", player_id)) == player_id \
				and str(target_meta.get("zone", zone_name)) == zone_name
			decorated_cards.append(card_data)
		player_data[zone_name] = decorated_cards
	return player_data

func _current_board_target_selection() -> Dictionary:
	if not _human_input_enabled():
		return {}
	var decision := _current_pending_decision()
	if decision.is_empty():
		return {}
	if not _is_board_target_selection_pending(decision):
		return {}
	return decision

func _is_board_target_selection_pending(decision: Dictionary) -> bool:
	if decision.is_empty():
		return false
	if str(decision.get("type", "")) != "ABILITY_TARGET_SELECTION":
		return false
	if _is_preview_pending_decision(decision):
		return false
	return bool(decision.get("ui_allows_board_selection", false)) or not _current_board_target_uid_set_for(decision).is_empty()

func _current_board_target_uid_set() -> Dictionary:
	return _current_board_target_uid_set_for(_current_pending_decision())

func _current_board_target_uid_set_for(decision: Dictionary) -> Dictionary:
	var result := {}
	if decision.is_empty():
		return result
	for target_uid_variant in decision.get("board_target_uids", []):
		var target_uid := str(target_uid_variant)
		if target_uid != "":
			result[target_uid] = true
	if not result.is_empty():
		return result
	for choice_variant in decision.get("choices", []):
		var choice: Dictionary = choice_variant
		var target_uid := str(choice.get("value", ""))
		if _find_board_target_info(target_uid).is_empty():
			continue
		result[target_uid] = true
	return result

func _board_target_meta_for(card_uid: String) -> Dictionary:
	var decision := _current_pending_decision()
	if decision.is_empty():
		return {}
	for target_variant in decision.get("board_targets", []):
		var target: Dictionary = target_variant
		if str(target.get("uid", "")) == card_uid:
			return target
	return _find_board_target_info(card_uid)

func _find_board_target_info(card_uid: String) -> Dictionary:
	if card_uid == "":
		return {}
	var players: Dictionary = _snapshot.get("players", {})
	for player_id_variant in players.keys():
		var player_id := str(player_id_variant)
		var player_data: Dictionary = players.get(player_id_variant, {})
		for zone_name in ["front_line", "energy_line"]:
			for card_variant in player_data.get(zone_name, []):
				var card_data: Dictionary = card_variant
				if str(card_data.get("uid", "")) == card_uid:
					return {
						"uid": card_uid,
						"player_id": player_id,
						"zone": zone_name,
					}
	return {}

func _resolve_board_target_selection_from_card(player_id: String, card_uid: String, zone_name: String) -> bool:
	return BoardTargetSelectionHelper.resolve_pending_click(
		game_manager,
		_snapshot,
		_opening_setup_pending,
		player_id,
		card_uid,
		zone_name,
		_selected_pending_decision_index
	)

func _should_allow_board_selection_passthrough() -> bool:
	return not _current_board_target_selection().is_empty()

func _run_layout_probe_if_requested() -> void:
	if not OS.get_cmdline_user_args().has("--layout-probe"):
		return
	if _opening_setup_pending:
		_start_game_with_selected_decks()
	if game_state_has_opening_probe_pending():
		game_manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})
		game_manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})
	_update_responsive_layout()
	call_deferred("_finish_layout_probe")

func _finish_layout_probe() -> void:
	var label := "%dx%d" % [int(get_viewport_rect().size.x), int(get_viewport_rect().size.y)]
	var hand_rect := hand_view.get_global_rect()
	var background_rect := background_texture_rect.get_global_rect()
	var error := ""
	var player_board_rect := _get_player_board_content_rect()

	# Check board layer has expected zone wrappers
	if player_board.get_child_count() < 6:
		error = "玩家战场缺失区域容器 (expected >= 6 zones, got %d)" % player_board.get_child_count()
	elif player_board_rect.size == Vector2.ZERO:
		error = "玩家战场内容区域为空"
	elif player_board_rect.position.x < background_rect.position.x - 1.0 or player_board_rect.position.y < background_rect.position.y - 1.0:
		error = "Board content exceeds the background top-left bounds."
	elif player_board_rect.position.x + player_board_rect.size.x > background_rect.position.x + background_rect.size.x + 1.0 or player_board_rect.position.y + player_board_rect.size.y > background_rect.position.y + background_rect.size.y + 1.0:
		error = "Board content exceeds the background bottom-right bounds."
	elif not _zone_stack_rect_within_background(player_board, "OutsideStack", background_rect) or not _zone_stack_rect_within_background(player_board, "RemovedStack", background_rect) or not _zone_stack_rect_within_background(opponent_board, "OutsideStack", background_rect) or not _zone_stack_rect_within_background(opponent_board, "RemovedStack", background_rect):
		error = "Outside/Removed stack content exceeds the battlefield background."
	elif hand_rect.position.y < background_rect.position.y + background_rect.size.y + BOARD_BOTTOM_GAP - 1.0:
		error = "Hand strip is not separated from the battlefield background."
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

func _get_player_board_content_rect() -> Rect2:
	var wrapper_names := [
		"LifeWrapper",
		"RemovedWrapper",
		"DeckWrapper",
		"OutsideWrapper",
		"FrontWrapper",
		"EnergyWrapper",
	]
	var has_rect := false
	var combined_rect := Rect2()

	for wrapper_name in wrapper_names:
		var wrapper := player_board.get_node_or_null(wrapper_name) as Control
		if wrapper == null:
			continue
		var rect := wrapper.get_global_rect()
		if not has_rect:
			combined_rect = rect
			has_rect = true
		else:
			combined_rect = combined_rect.merge(rect)

	return combined_rect if has_rect else Rect2()

func _zone_stack_rect_within_background(board: BoardView, node_name: String, background_rect: Rect2) -> bool:
	var node := board.get_node_or_null("%sWrapper/%s" % [node_name.replace("Stack", ""), node_name]) as Control
	if node == null:
		return false
	var rect := node.get_global_rect()
	return rect.position.x >= background_rect.position.x - 1.0 \
		and rect.position.y >= background_rect.position.y - 1.0 \
		and rect.position.x + rect.size.x <= background_rect.position.x + background_rect.size.x + 1.0 \
		and rect.position.y + rect.size.y <= background_rect.position.y + background_rect.size.y + 1.0

func _format_energy_total(energy_map: Dictionary) -> String:
	if energy_map.is_empty():
		return "0"
	var total := 0
	for color in energy_map.keys():
		total += int(energy_map.get(color, 0))
	return str(total)

func game_state_has_opening_probe_pending() -> bool:
	return game_manager.game_state.pending_decisions.size() >= 1 and str((game_manager.game_state.pending_decisions[0] as Dictionary).get("type", "")) == "MULLIGAN_CHOICE"
