extends Control
class_name BattleScene

const BoardTargetSelectionHelper = preload("res://ui/board_target_selection_helper.gd")
const AIActionHint = preload("res://ui/ai_action_hint.gd")
const DeckSelector = preload("res://ui/deck_selector.gd")
const BoardPanel = preload("res://ui/board_panel.gd")
const SelectionStateMachine = preload("res://ui/selection_state_machine.gd")
const BoardController = preload("res://ui/board_controller.gd")
const HUDController = preload("res://ui/hud_controller.gd")
const HandController = preload("res://ui/hand_controller.gd")
const ModalController = preload("res://ui/modal_controller.gd")
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

@onready var game_manager: GameManager = $GameManager
@onready var background_texture_rect: TextureRect = $BackgroundLayer/Background
@onready var selection_highlight: TextureRect = $EffectLayer/SelectionHighlight
@onready var slot_highlight: TextureRect = $EffectLayer/SlotHighlight
@onready var board_layer: Control = $BoardLayer
@onready var board_vbox: VBoxContainer = $BoardLayer/BoardVBox

# P2: 四个主面板 — 按"敌能量→敌前线→我前线→我能线"排列
var _opponent_energy_panel: BoardPanel
var _opponent_front_panel: BoardPanel
var _player_front_panel: BoardPanel
var _player_energy_panel: BoardPanel

# P2: 附属堆叠（LifeStackView / ZoneStackSummaryView）
const LifeStackView = preload("res://ui/life_stack_view.gd")
const ZoneStackSummaryView = preload("res://ui/zone_stack_summary_view.gd")
var _opponent_life_stack: LifeStackView
var _opponent_deck_stack: ZoneStackSummaryView
var _opponent_outside_stack: ZoneStackSummaryView
var _opponent_removed_stack: ZoneStackSummaryView
var _player_life_stack: LifeStackView
var _player_deck_stack: ZoneStackSummaryView
var _player_outside_stack: ZoneStackSummaryView
var _player_removed_stack: ZoneStackSummaryView
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
var _selected_board_card_uid := ""
var _selected_board_zone_name := ""
var _sniper_attack_source_uid := ""
var _selected_life_trigger_uid := ""
var _selected_pending_decision_index := -1
var _selected_pending_decision_choice_index := 0
var _preview_card_uid := ""
var _preview_player_id := ""
var _preview_zone_name := ""
var _deck_selector: DeckSelector
var _ai_action_hint: AIActionHint
var _state_machine: SelectionStateMachine
var _board_controller: BoardController
var _hud_controller: HUDController
var _hand_controller: HandController
var _modal_controller: ModalController

func _ready() -> void:
	# P0: 加载 v2.0 Theme。字体在 Godot 编辑器首次打开项目时自动导入。
	if not theme:
		theme = load("res://assets/ui/battle_theme.theme")
	_setup_optional_art()
	_ai_action_hint = AIActionHint.new(self, ai_action_label)
	_deck_selector = DeckSelector.new(game_manager, player_one_deck_picker, player_two_deck_picker, deck_selection_modal, start_game_button)
	
	# P1: ModalController（必须在 BoardController 之前创建，因为 BoardController 需要 zone_cards_popup）
	_modal_controller = ModalController.new()
	_modal_controller.setup(game_manager, $UILayer, log_panel, preview_selection_modal, deck_selection_modal, _deck_selector)
	_modal_controller.set_snapshot_provider(func(): return _snapshot)
	_modal_controller.set_human_input_provider(func(): return _human_input_enabled())
	_modal_controller.set_board_target_pending_provider(func(): return _should_allow_board_selection_passthrough())
	_modal_controller.set_current_pending_decision_provider(func(): return _current_pending_decision())
	_modal_controller.set_is_preview_pending_decision_provider(func(d: Dictionary): return _is_preview_pending_decision(d))
	_modal_controller.create_modals()
	
	# P1: SelectionStateMachine
	_state_machine = SelectionStateMachine.new()
	_state_machine.setup(game_manager, action_bar, selected_card_label, card_preview_panel)
	_state_machine.set_snapshot_provider(func(): return _snapshot)
	_setup_state_machine_buttons()
	
	# P2: BoardController (BoardView refs removed — BoardController accesses snapshot directly)
	_board_controller = BoardController.new()
	_board_controller.setup(game_manager, _modal_controller.zone_cards_popup)
	_board_controller.set_snapshot_provider(func(): return _snapshot)
	_board_controller.set_pending_decision_index_provider(func(): return _selected_pending_decision_index)

	# P1: HUDController
	_hud_controller = HUDController.new()
	_hud_controller.setup(game_manager,
		turn_label, active_player_label, phase_indicator,
		hand_count_label, energy_label, ap_label, winner_label,
		next_phase_button, bonus_draw_button, no_block_button,
		selected_card_label, ai_action_label, _ai_action_hint)
	_hud_controller.set_snapshot_provider(func(): return _snapshot)
	_hud_controller.set_human_input_provider(func(): return not _deck_selector.opening_setup_pending)

	# P1: HandController
	_hand_controller = HandController.new()
	_hand_controller.setup(game_manager, hand_view, selected_card_label)
	_hand_controller.set_snapshot_provider(func(): return _snapshot)
	_hand_controller.set_has_pending_gate_provider(func(): return _has_pending_gate())
	_hand_controller.set_human_input_provider(func(): return not _deck_selector.opening_setup_pending and bool(_snapshot.get("human_input_enabled", true)))
	_hand_controller.set_display_hand_player_id_provider(func(): return _display_hand_player_id())
	_hand_controller.set_find_board_card_provider(func(pid: String, cuid: String): return _find_board_card(pid, cuid))
	_hand_controller.set_action_buttons_callback(func(): _update_action_buttons())
	_hand_controller.set_preview_card_callback(func(card_data: Dictionary, context: Dictionary): _set_preview_card(card_data, context))

	# P2: 创建四个主面板实例，挂入 board_vbox
	_create_board_panels()
	# P2: 创建附属堆叠（面板侧边的 Life / Deck / Outside / Removed 堆叠）
	_create_attached_stacks()

	game_manager.state_changed.connect(_on_state_changed)
	game_manager.blockers_requested.connect(_hud_controller.on_blockers_requested)
	game_manager.ai_action_executed.connect(_hud_controller.on_ai_action_executed)
	next_phase_button.pressed.connect(_hud_controller.on_next_phase_pressed)
	bonus_draw_button.pressed.connect(_hud_controller.on_bonus_draw_pressed)
	no_block_button.pressed.connect(_hud_controller.on_no_block_pressed)
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
	preview_selection_modal.submitted.connect(_modal_controller.on_preview_modal_submitted)
	cancel_selection_button.pressed.connect(_clear_selection)
	log_toggle_button.pressed.connect(_modal_controller.on_log_toggle_pressed)
	start_game_button.pressed.connect(_modal_controller.start_game_with_selected_decks)
	hand_view.hand_card_selected.connect(_on_hand_card_selected)
	hand_view.hand_card_hovered.connect(_on_hand_card_hovered)
	# P2: BoardPanel signals — each panel emits card_was_pressed / panel_drop_was_requested
	_connect_panel_signals()
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
	_modal_controller.load_deck_selection_options()
	get_viewport().size_changed.connect(_update_responsive_layout)
	_update_responsive_layout()
	_on_state_changed(game_manager.get_snapshot())
	_modal_controller.show_deck_selection_modal()
	call_deferred("_run_layout_probe_if_requested")

func _setup_state_machine_buttons() -> void:
	_state_machine.register_button("play_front", play_front_button)
	_state_machine.register_button("play_energy", play_energy_button)
	_state_machine.register_button("use_event", use_event_button)
	_state_machine.register_button("raid", raid_button)
	_state_machine.register_button("main_activate", main_activate_button)
	_state_machine.register_button("step", step_button)
	_state_machine.register_button("move_front", move_front_button)
	_state_machine.register_button("sniper_attack", sniper_attack_button)
	_state_machine.register_button("activate_life", activate_life_button)
	_state_machine.register_button("skip_life", skip_life_button)
	_state_machine.register_button("cancel", cancel_selection_button)


func _setup_optional_art() -> void:
	_assign_optional_texture(background_texture_rect, BATTLE_BG_PATH)
	_assign_optional_texture(selection_highlight, SELECTION_HIGHLIGHT_PATH)
	_assign_optional_texture(slot_highlight, SLOT_HIGHLIGHT_PATH)


## P2: 在 BoardLayer 的 VBoxContainer 中创建四个主面板
func _create_board_panels() -> void:
	_opponent_energy_panel = _make_panel(BoardPanel.PanelType.ENERGY_LINE, "ENERGY LINE", UATypes.PLAYER_TWO)
	_opponent_front_panel = _make_panel(BoardPanel.PanelType.FRONT_LINE, "FRONT LINE", UATypes.PLAYER_TWO)
	_player_front_panel = _make_panel(BoardPanel.PanelType.FRONT_LINE, "FRONT LINE", UATypes.PLAYER_ONE)
	_player_energy_panel = _make_panel(BoardPanel.PanelType.ENERGY_LINE, "ENERGY LINE", UATypes.PLAYER_ONE)


func _make_panel(panel_type: BoardPanel.PanelType, title: String, pid: String) -> BoardPanel:
	var panel := BoardPanel.new()
	panel.panel_type = panel_type
	panel.panel_title = title
	panel.player_id = pid
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_vbox.add_child(panel)
	return panel


func _connect_panel_signals() -> void:
	var panels: Array[BoardPanel] = [_opponent_energy_panel, _opponent_front_panel, _player_front_panel, _player_energy_panel]
	for panel in panels:
		panel.card_was_pressed.connect(_on_board_card_pressed.bind(panel))
		panel.panel_drop_was_requested.connect(_on_zone_drop_requested)


## P2: 创建附属堆叠（贴在面板侧边 / 角落）
func _create_attached_stacks() -> void:
	_opponent_life_stack = _make_life_stack()
	_opponent_deck_stack = _make_zone_stack("Deck")
	_opponent_outside_stack = _make_zone_stack("Outside")
	_opponent_removed_stack = _make_zone_stack("Removed")
	_player_life_stack = _make_life_stack()
	_player_deck_stack = _make_zone_stack("Deck")
	_player_outside_stack = _make_zone_stack("Outside")
	_player_removed_stack = _make_zone_stack("Removed")

	# 连接堆叠点击 → zone_stack popup
	_opponent_removed_stack.summary_pressed.connect(func(): _on_zone_stack_requested(UATypes.PLAYER_TWO, "removed"))
	_opponent_outside_stack.summary_pressed.connect(func(): _on_zone_stack_requested(UATypes.PLAYER_TWO, "outside"))
	_player_removed_stack.summary_pressed.connect(func(): _on_zone_stack_requested(UATypes.PLAYER_ONE, "removed"))
	_player_outside_stack.summary_pressed.connect(func(): _on_zone_stack_requested(UATypes.PLAYER_ONE, "outside"))


func _make_life_stack() -> LifeStackView:
	var s := LifeStackView.new()
	s.name = "LifeStack"
	s.set_compact_mode(false)
	board_layer.add_child(s)
	return s


func _make_zone_stack(title: String) -> ZoneStackSummaryView:
	var s := ZoneStackSummaryView.new()
	s.name = title + "Stack"
	s.set_compact_mode(false)
	s.set_summary(title, 0)
	board_layer.add_child(s)
	return s


## P2: 根据面板位置动态放置附属堆叠
func _position_stacks() -> void:
	var stack_gap := 8.0

	# 对手前线面板的 Life (左) / Deck (右)
	_position_stack_beside(_opponent_life_stack, _opponent_front_panel, "left", stack_gap)
	_position_stack_beside(_opponent_deck_stack, _opponent_front_panel, "right", stack_gap)
	# 我能线面板的 Removed (左) / Outside (右)
	_position_stack_beside(_player_removed_stack, _player_energy_panel, "left", stack_gap)
	_position_stack_beside(_player_outside_stack, _player_energy_panel, "right", stack_gap)
	# 我前线面板的 Life (左) / Deck (右)
	_position_stack_beside(_player_life_stack, _player_front_panel, "left", stack_gap)
	_position_stack_beside(_player_deck_stack, _player_front_panel, "right", stack_gap)
	# 敌能量面板的 Removed (左) / Outside (右)
	_position_stack_beside(_opponent_removed_stack, _opponent_energy_panel, "left", stack_gap)
	_position_stack_beside(_opponent_outside_stack, _opponent_energy_panel, "right", stack_gap)


func _position_stack_beside(stack: Control, panel: Control, side: String, gap: float) -> void:
	var panel_rect := panel.get_global_rect()
	var board_layer_origin := board_layer.get_global_rect().position
	var min_size := stack.get_combined_minimum_size() if stack is ZoneStackSummaryView else Vector2(50, 70)
	stack.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	stack.size = min_size

	var x: float
	if side == "left":
		x = (panel_rect.position.x - board_layer_origin.x) - min_size.x - gap
	else:
		x = (panel_rect.position.x - board_layer_origin.x) + panel_rect.size.x + gap
	var y := (panel_rect.position.y - board_layer_origin.y) + (panel_rect.size.y - min_size.y) / 2.0
	stack.position = Vector2(x, y)


## P2: 向附属堆叠填充数据
func _populate_stacks(p1: Dictionary, p2: Dictionary) -> void:
	_opponent_life_stack.set_life_cards(p2.get("life", []))
	_opponent_deck_stack.set_summary("Deck", int(p2.get("deck_count", 0)))
	_opponent_outside_stack.set_summary("Outside", int(p2.get("outside_count", 0)))
	_opponent_removed_stack.set_summary("Removed", int(p2.get("removed_count", 0)))
	_player_life_stack.set_life_cards(p1.get("life", []))
	_player_deck_stack.set_summary("Deck", int(p1.get("deck_count", 0)))
	_player_outside_stack.set_summary("Outside", int(p1.get("outside_count", 0)))
	_player_removed_stack.set_summary("Removed", int(p1.get("removed_count", 0)))

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

	# HUD spacing
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

	# P2: Container 布局 — 四行面板由 VBoxContainer 自动排列
	var top_hud_height := maxf(top_hud.get_combined_minimum_size().y, 48.0)
	top_hud.offset_bottom = top_hud.offset_top + top_hud_height

	var board_margin := 12.0 if very_small else 16.0
	board_vbox.offset_left = board_margin
	board_vbox.offset_top = top_hud.offset_bottom + BOARD_TOP_GAP
	board_vbox.offset_right = -board_margin
	board_vbox.offset_bottom = -BOARD_BOTTOM_GAP

	# 背景图全屏拉伸（不再做比例映射）
	background_texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	# 底部手牌条
	var hand_strip_height := HAND_STRIP_HEIGHT_SMALL if very_small else (HAND_STRIP_HEIGHT_COMPACT if compact else HAND_STRIP_HEIGHT_DEFAULT)
	bottom_hud.offset_left = BOTTOM_HUD_SIDE_MARGIN
	bottom_hud.offset_right = -BOTTOM_HUD_SIDE_MARGIN
	bottom_hud.offset_bottom = -BOTTOM_HUD_BOTTOM_MARGIN
	bottom_hud.offset_top = bottom_hud.offset_bottom - hand_strip_height
	bottom_panel.custom_minimum_size = Vector2(0, hand_strip_height)

	# 手牌宽度
	hand_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var hand_width := maxf(320.0, viewport_width - BOTTOM_HUD_SIDE_MARGIN * 2.0 - HAND_STRIP_INTERNAL_WIDTH_MARGIN)
	hand_view.set_hand_bounds(0.0, hand_width, hand_width)
	hand_view.set_compact_mode(compact, very_small)
	_update_preview_panel_layout()
	_update_log_panel_layout(compact, very_small, viewport_height)
	# P2: 附属堆叠定位
	_position_stacks()

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
	_hud_controller.on_ai_action_executed(action_info)


## P2: BoardPanel 统一点击路由 — 根据 zone_name 分发到原 handler
func _on_board_card_pressed(player_id: String, card_uid: String, zone_name: String, panel: BoardPanel) -> void:
	var card_data := _find_board_card(player_id, card_uid)
	if not card_data.is_empty():
		_set_board_preview(player_id, zone_name, card_data)
	if _resolve_board_target_selection_from_card(player_id, card_uid, zone_name):
		return
	if _has_pending_gate() or not _human_input_enabled():
		return
	# RAID 目标选择
	if _hand_controller.raid_target_selection_mode:
		if player_id == str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE)):
			_hand_controller.execute_raid_play(card_uid)
		return
	var active_player_id := str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE))
	var phase := str(_snapshot.get("phase", ""))
	var board_actions: Array = card_data.get("available_actions", [])
	# 狙击攻击目标选择
	if _sniper_attack_source_uid != "":
		if player_id != active_player_id:
			game_manager.request_attack(_sniper_attack_source_uid, {
				"target_kind": "FRONT_CHARACTER",
				"target_uid": card_uid,
			})
			_sniper_attack_source_uid = ""
			_update_action_buttons()
		return
	# 敌方卡牌点击
	if player_id != active_player_id:
		if board_actions.has("SNIPER_ATTACK") and phase == "ATTACK":
			pass  # 等待玩家先点狙击按钮
		return
	# 己方前线/能量线选中
	_selected_board_card_uid = card_uid
	_selected_board_zone_name = zone_name
	# 如果牌有 SNIPER_ATTACK，自动进入狙击模式
	if board_actions.has("SNIPER_ATTACK"):
		_sniper_attack_source_uid = card_uid
	_update_action_buttons()

func _on_state_changed(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	_modal_controller.hide_zone_popup()
	var active_player_id := str(snapshot.get("active_player_id", UATypes.PLAYER_ONE))
	var display_hand_player_id := _display_hand_player_id()
	var priority_player_id := str(snapshot.get("priority_player_id", active_player_id))
	var controller_types: Dictionary = snapshot.get("controller_types", {})
	var players: Dictionary = snapshot.get("players", {})
	var p1: Dictionary = _board_controller.decorate_board_targets(UATypes.PLAYER_ONE, players.get(UATypes.PLAYER_ONE, {}))
	var p2: Dictionary = _board_controller.decorate_board_targets(UATypes.PLAYER_TWO, players.get(UATypes.PLAYER_TWO, {}))
	var active_player_data: Dictionary = p1 if active_player_id == UATypes.PLAYER_ONE else p2
	var display_hand_player_data: Dictionary = p1 if display_hand_player_id == UATypes.PLAYER_ONE else p2
	var action_controller_type := str(controller_types.get(priority_player_id, snapshot.get("action_player_controller", "HUMAN")))
	_hud_controller.update_hud(snapshot, active_player_data, display_hand_player_data)
	# P2: 直接填充四个 BoardPanel（替代 BoardView.set_board()）
	_opponent_energy_panel.populate(p2.get("energy_line", []), "energy_line")
	_opponent_front_panel.populate(p2.get("front_line", []), "front_line")
	_player_front_panel.populate(p1.get("front_line", []), "front_line")
	_player_energy_panel.populate(p1.get("energy_line", []), "energy_line")
	# P2: 附属堆叠数据填充
	_populate_stacks(p1, p2)
	var active_hand: Array = p2.get("hand", [])
	if display_hand_player_id == UATypes.PLAYER_ONE:
		active_hand = p1.get("hand", [])
	hand_view.set_hand(display_hand_player_id, active_hand)
	_update_hand_playable_states(display_hand_player_id, active_hand)
	_sync_pending_decision_controls()
	_modal_controller.sync_preview_selection_modal()
	_modal_controller.sync_life_reveal_modal()
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
	# 全局门禁：胜局或待处理关卡激活时禁用所有动作按钮（非累积，每次基于当前状态判定）
	if has_winner or has_pending_gate:
		play_front_button.disabled = true
		play_energy_button.disabled = true
		use_event_button.disabled = true
		main_activate_button.disabled = true
		step_button.disabled = true
		move_front_button.disabled = true
		sniper_attack_button.disabled = true
		cancel_selection_button.disabled = true
	elif not human_input_enabled:
		cancel_selection_button.disabled = true
	activate_life_button.disabled = true
	skip_life_button.disabled = true
	pending_decision_panel.visible = has_pending_decisions
	if _is_preview_pending_decision(_current_pending_decision()):
		pending_decision_panel.visible = false
	resolve_pending_decision_button.disabled = has_winner or not has_pending_decisions or _selected_pending_decision_index < 0 or not human_input_enabled
	_modal_controller.refresh_deck_selection_modal_state()

func _on_hand_card_selected(card_uid: String) -> void:
	if _has_pending_gate() or not _human_input_enabled():
		return
	if _hand_controller.raid_target_selection_mode and _hand_controller.raid_source_card_uid != card_uid:
		_hand_controller.clear_raid_selection()
	_selected_board_card_uid = ""
	_selected_board_zone_name = ""
	_sniper_attack_source_uid = ""
	_hand_controller.on_hand_card_selected(card_uid)
	_update_action_buttons()
	var display_hand_player_id := _display_hand_player_id()
	selected_card_label.text = _selected_label_text(display_hand_player_id)

func _on_hand_card_hovered(card_uid: String, is_hovered: bool) -> void:
	_hand_controller.on_hand_card_hovered(card_uid, is_hovered)

func _on_front_card_pressed(player_id: String, card_uid: String, pressed_card_data: Dictionary = {}) -> void:
	var card_data := pressed_card_data if not pressed_card_data.is_empty() else _find_board_card(player_id, card_uid)
	if not card_data.is_empty():
		_set_board_preview(player_id, "front_line", card_data)
	if _resolve_board_target_selection_from_card(player_id, card_uid, "front_line"):
		return
	if _has_pending_gate() or not _human_input_enabled():
		return
	# 处理RAID目标选择
	if _hand_controller.raid_target_selection_mode:
		if player_id == str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE)):
			_hand_controller.execute_raid_play(card_uid)
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
	if _hud_controller.pending_attack_uid != "":
		if player_id == _hud_controller.pending_defender_player_id:
			game_manager.resolve_attack(_hud_controller.pending_attack_uid, card_uid)
			_clear_pending_attack()
		return
	if player_id != active_player_id:
		_hand_controller.clear_raid_selection()
		_selected_board_card_uid = ""
		_selected_board_zone_name = ""
		_update_action_buttons()
		selected_card_label.text = _selected_label_text(_display_hand_player_id())
		return
	_hand_controller.clear_raid_selection()
	_selected_board_card_uid = card_uid
	_selected_board_zone_name = "front_line"
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
	if _hand_controller.raid_target_selection_mode:
		if player_id == str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE)):
			_hand_controller.execute_raid_play(card_uid)
		return
	var active_player_id := str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE))
	if player_id != active_player_id:
		_hand_controller.clear_raid_selection()
		_selected_board_card_uid = ""
		_selected_board_zone_name = ""
		_update_action_buttons()
		selected_card_label.text = _selected_label_text(_display_hand_player_id())
		return
	_hand_controller.clear_raid_selection()
	_selected_board_card_uid = card_uid
	_selected_board_zone_name = "energy_line"
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
	_hand_controller.on_zone_drop_requested(player_id, zone_name, card_uid)
	_clear_selection()

func _on_blockers_requested(request: Dictionary) -> void:
	_hud_controller.on_blockers_requested(request)

func _on_next_phase_pressed() -> void:
	_hud_controller.on_next_phase_pressed()

func _on_no_block_pressed() -> void:
	_hud_controller.on_no_block_pressed()

func _on_bonus_draw_pressed() -> void:
	_hud_controller.on_bonus_draw_pressed()

func _on_play_front_pressed() -> void:
	if _has_pending_gate() or not _human_input_enabled():
		return
	if _hand_controller.selected_hand_card_uid != "":
		_hand_controller.on_play_front_pressed()
		_clear_selection()

func _on_play_energy_pressed() -> void:
	if _has_pending_gate() or not _human_input_enabled():
		return
	if _hand_controller.selected_hand_card_uid != "":
		_hand_controller.on_play_energy_pressed()
		_clear_selection()

func _on_use_event_pressed() -> void:
	if _has_pending_gate() or not _human_input_enabled():
		return
	if _hand_controller.selected_hand_card_uid != "":
		_hand_controller.on_use_event_pressed()
		_clear_selection()

func _on_raid_pressed() -> void:
	if _has_pending_gate() or _hand_controller.selected_hand_card_uid == "" or not _human_input_enabled():
		return
	_hand_controller.on_raid_pressed()

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

## ── 选中状态同步 ──
## BattleScene 是导航状态的权威持有者；StateMachine 和 HandController 是镜像消费者。
## 每次 BattleScene 修改导航变量后，调用本方法将状态推送到消费者。
func _sync_nav_state_to_consumers() -> void:
	_state_machine.selected_hand_card_uid = _hand_controller.selected_hand_card_uid
	_state_machine.selected_board_card_uid = _selected_board_card_uid
	_state_machine.selected_board_zone_name = _selected_board_zone_name
	_state_machine.sniper_attack_source_uid = _sniper_attack_source_uid
	_state_machine.raid_source_card_uid = _hand_controller.raid_source_card_uid
	_state_machine.raid_target_selection_mode = _hand_controller.raid_target_selection_mode
	_state_machine.selected_life_trigger_uid = _selected_life_trigger_uid
	_state_machine.selected_pending_decision_index = _selected_pending_decision_index


func _clear_selection() -> void:
	_hand_controller.clear_selection()
	_sync_nav_state_to_consumers()
	_state_machine.clear_selection()
	# 从 StateMachine 回读清除后的状态
	_hand_controller.clear_selection()
	_selected_board_card_uid = _state_machine.selected_board_card_uid
	_selected_board_zone_name = _state_machine.selected_board_zone_name
	_sniper_attack_source_uid = _state_machine.sniper_attack_source_uid
	_selected_life_trigger_uid = _state_machine.selected_life_trigger_uid
	_preview_card_uid = ""
	_preview_player_id = ""
	_preview_zone_name = ""
	_clear_preview_card()
	_update_action_buttons()
	selected_card_label.text = _state_machine.label_text()

func _clear_pending_attack() -> void:
	_hud_controller.clear_pending_attack()
	bonus_draw_button.visible = false


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
	if _hand_controller.raid_target_selection_mode:
		return "Choose a RAID target on your field"
	if _sniper_attack_source_uid != "":
		return "Choose an enemy front target for sniper attack"
	if _hud_controller.pending_attack_uid != "":
		return "Choose a blocker or click No Block"
	if _selected_board_card_uid != "":
		var board_card: Dictionary = _find_board_card(active_player_id, _selected_board_card_uid)
		if not board_card.is_empty():
			return "Selected: %s" % str(board_card.get("name", "Unknown"))
	if _preview_card_uid != "":
		var preview_card := _find_preview_card()
		if not preview_card.is_empty():
			return "Previewing: %s" % str(preview_card.get("name", "Unknown"))
	if _hand_controller.selected_hand_card_uid == "":
		return "No card selected"
	var card_data: Dictionary = _hand_controller.find_hand_card(active_player_id, _hand_controller.selected_hand_card_uid)
	if card_data.is_empty():
		return "No card selected"
	return "Selected: %s" % str(card_data.get("name", "Unknown"))

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
		return _hand_controller.find_hand_card(_preview_player_id, _preview_card_uid)
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
	_modal_controller.show_zone_stack_popup("%s %s" % [relation_label, zone_label], cards)

func _sync_preview_panel() -> void:
	var active_player_id := str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE))
	var display_hand_player_id := _display_hand_player_id()
	if _hand_controller.selected_hand_card_uid != "":
		var hand_card := _hand_controller.find_hand_card(display_hand_player_id, _hand_controller.selected_hand_card_uid)
		if not hand_card.is_empty():
			_set_preview_card(hand_card, {
				"relation_label": "己方",
				"zone_label": "手牌",
			}, display_hand_player_id, "hand")
			return
		_hand_controller.selected_hand_card_uid = ""
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
	_sync_nav_state_to_consumers()
	var active_player_id := str(_snapshot.get("active_player_id", UATypes.PLAYER_ONE))
	var display_hand_player_id := _display_hand_player_id()
	var input_enabled := _human_input_enabled()
	var card_data: Dictionary = _hand_controller.find_hand_card(display_hand_player_id, _hand_controller.selected_hand_card_uid)
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
	raid_button.disabled = not available_actions.has("RAID") or _hand_controller.raid_target_selection_mode or not input_enabled
	if available_actions.has("RAID"):
		raid_button.tooltip_text = "选择己方场上的符合条件角色作为 RAID 底座。"
	elif is_raid_card and bool(special_play_rule.get("life_trigger_only", false)):
		raid_button.tooltip_text = "这张牌当前只能通过生命触发或临时特殊许可进行 RAID。"
	elif is_raid_card:
		raid_button.tooltip_text = "当前没有满足条件的能量、AP 或 RAID 底座，暂时不能使用 RAID。"
	else:
		raid_button.tooltip_text = ""

	# RAID选择模式时禁用其他打出按钮
	if _hand_controller.raid_target_selection_mode:
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
	cancel_selection_button.disabled = (_hand_controller.selected_hand_card_uid == "" and _selected_board_card_uid == "" and _sniper_attack_source_uid == "" and _hand_controller.raid_source_card_uid == "") or not input_enabled

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
	_modal_controller.sync_preview_selection_modal()
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

func _update_hand_playable_states(_player_id: String, hand_cards: Array) -> void:
	_hand_controller.update_hand_playable_states(hand_cards)

func _human_input_enabled() -> bool:
	return not _deck_selector.opening_setup_pending and bool(_snapshot.get("human_input_enabled", true))

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
		_deck_selector.opening_setup_pending,
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
	if _deck_selector.opening_setup_pending:
		_modal_controller.start_game_with_selected_decks()
	if game_state_has_opening_probe_pending():
		game_manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})
		game_manager.resolve_pending_decision("MULLIGAN_CHOICE", {"choice": "keep"})
	_update_responsive_layout()
	call_deferred("_finish_layout_probe")

func _finish_layout_probe() -> void:
	var label := "%dx%d" % [int(get_viewport_rect().size.x), int(get_viewport_rect().size.y)]
	var hand_rect := hand_view.get_global_rect()
	var error := ""

	# P2: 检查四个面板是否存在且有内容
	if board_vbox.get_child_count() < 4:
		error = "战场面板数量不足 (expected 4, got %d)" % board_vbox.get_child_count()
	elif _player_energy_panel.get_global_rect().size == Vector2.ZERO:
		error = "玩家战场面板区域为空"
	elif hand_rect.position.y < board_vbox.get_global_rect().position.y + board_vbox.get_global_rect().size.y + BOARD_BOTTOM_GAP - 1.0:
		error = "手牌条未与战场面板分离"
	elif _player_energy_panel.get_global_rect().position.y + _player_energy_panel.get_global_rect().size.y > hand_rect.position.y + 1.0:
		error = "玩家战场面板与手牌区域重叠 (panel_bottom=%.1f, hand_top=%.1f)" % [
			_player_energy_panel.get_global_rect().position.y + _player_energy_panel.get_global_rect().size.y,
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
	# P2: 用四个面板的全局 rect 计算合并区域
	var rect := _player_energy_panel.get_global_rect()
	rect = rect.merge(_player_front_panel.get_global_rect())
	return rect

func game_state_has_opening_probe_pending() -> bool:
	return game_manager.game_state.pending_decisions.size() >= 1 and str((game_manager.game_state.pending_decisions[0] as Dictionary).get("type", "")) == "MULLIGAN_CHOICE"
