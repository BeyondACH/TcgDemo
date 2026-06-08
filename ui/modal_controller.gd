extends RefCounted
class_name ModalController

## 弹窗控制器 — 从 BattleScene 提取
## 管理：LifeRevealModal 生命周期、ZoneCardsPopup、PreviewSelectionModal、
##        DeckSelector 委托、牌组选择弹窗、日志面板开关

# ── 弹窗实例 ──
var life_reveal_modal  # LifeRevealModal
var zone_cards_popup   # ZoneCardsPopup

# ── 引用 ──
var _game_manager: Node
var _ui_layer: Node
var _log_panel: LogPanel
var _preview_selection_modal: PreviewSelectionModal
var _deck_selection_modal: Control
var _deck_selector: DeckSelector

# ── 提供者 ──
var _snapshot_provider: Callable
var _human_input_provider: Callable
var _board_target_pending_provider: Callable
var _current_pending_decision_provider: Callable
var _is_preview_pending_decision_provider: Callable


func setup(gm: Node,
		   ui_layer: Node,
		   log_panel: LogPanel,
		   preview_selection_modal: PreviewSelectionModal,
		   deck_selection_modal: Control,
		   deck_selector: DeckSelector) -> void:
	_game_manager = gm
	_ui_layer = ui_layer
	_log_panel = log_panel
	_preview_selection_modal = preview_selection_modal
	_deck_selection_modal = deck_selection_modal
	_deck_selector = deck_selector


func set_snapshot_provider(provider: Callable) -> void:
	_snapshot_provider = provider


func set_human_input_provider(provider: Callable) -> void:
	_human_input_provider = provider


func set_board_target_pending_provider(provider: Callable) -> void:
	_board_target_pending_provider = provider


func set_current_pending_decision_provider(provider: Callable) -> void:
	_current_pending_decision_provider = provider


func set_is_preview_pending_decision_provider(provider: Callable) -> void:
	_is_preview_pending_decision_provider = provider


func _snapshot() -> Dictionary:
	if _snapshot_provider.is_valid():
		return _snapshot_provider.call()
	return {}


func _human_input_enabled() -> bool:
	if _human_input_provider.is_valid():
		return _human_input_provider.call()
	return true


func _should_allow_board_selection_passthrough() -> bool:
	if _board_target_pending_provider.is_valid():
		return _board_target_pending_provider.call()
	return false


func _current_pending_decision() -> Dictionary:
	if _current_pending_decision_provider.is_valid():
		return _current_pending_decision_provider.call()
	return {}


func _is_preview_pending_decision(decision: Dictionary) -> bool:
	if _is_preview_pending_decision_provider.is_valid():
		return _is_preview_pending_decision_provider.call(decision)
	return false


## ── 动态弹窗创建 ──

func create_modals() -> void:
	# LifeRevealModal
	life_reveal_modal = LifeRevealModal.new()
	life_reveal_modal.name = "LifeRevealModal"
	_ui_layer.add_child(life_reveal_modal)
	life_reveal_modal.activate_requested.connect(_on_life_reveal_activate_requested)
	life_reveal_modal.skip_requested.connect(_on_life_reveal_skip_requested)
	life_reveal_modal.acknowledge_requested.connect(_on_life_reveal_acknowledge_requested)

	# ZoneCardsPopup
	zone_cards_popup = ZoneCardsPopup.new()
	zone_cards_popup.name = "ZoneCardsPopup"
	_ui_layer.add_child(zone_cards_popup)


## ── LifeRevealModal 同步 ──

func sync_life_reveal_modal() -> void:
	var modal_data := _current_life_reveal_modal()
	if not bool(modal_data.get("visible", false)):
		if life_reveal_modal != null:
			life_reveal_modal.hide_modal()
		return
	if _should_allow_board_selection_passthrough():
		if life_reveal_modal != null:
			life_reveal_modal.hide_modal()
		return
	if life_reveal_modal != null:
		life_reveal_modal.show_modal(modal_data)
		life_reveal_modal.set_input_blocking(true)


func _current_life_reveal_modal() -> Dictionary:
	return _snapshot().get("life_reveal_modal", {})


func _on_life_reveal_activate_requested(card_uid: String) -> void:
	var modal_data := _current_life_reveal_modal()
	if not bool(modal_data.get("can_activate", false)):
		return
	_game_manager.resolve_life_trigger_decision(card_uid, true)


func _on_life_reveal_skip_requested(card_uid: String) -> void:
	var modal_data := _current_life_reveal_modal()
	if not bool(modal_data.get("can_skip", false)):
		return
	_game_manager.resolve_life_trigger_decision(card_uid, false)


func _on_life_reveal_acknowledge_requested(card_uid: String) -> void:
	var modal_data := _current_life_reveal_modal()
	if not bool(modal_data.get("can_acknowledge", false)):
		return
	_game_manager.acknowledge_life_reveal(card_uid)


## ── PreviewSelectionModal ──

func sync_preview_selection_modal() -> void:
	var decision := _current_pending_decision()
	if not _human_input_enabled() or decision.is_empty() or not _is_preview_pending_decision(decision):
		_preview_selection_modal.hide_modal()
		return
	_preview_selection_modal.show_decision(decision)


func on_preview_modal_submitted(selected_values: Array) -> void:
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
	_game_manager.resolve_pending_decision(str(decision.get("type", "")), payload)


## ── ZoneCardsPopup ──

func show_zone_stack_popup(title: String, cards: Array) -> void:
	if zone_cards_popup != null:
		zone_cards_popup.show_zone_cards(title, cards)


func hide_zone_popup() -> void:
	if zone_cards_popup != null and zone_cards_popup.visible:
		zone_cards_popup.hide_popup()


## ── 牌组选择弹窗 ──

func show_deck_selection_modal() -> void:
	_deck_selector.show_modal()


func hide_deck_selection_modal() -> void:
	_deck_selector.hide_modal()


func refresh_deck_selection_modal_state() -> void:
	_deck_selector.refresh_state()


func load_deck_selection_options() -> void:
	_deck_selector.load_options()


func start_game_with_selected_decks() -> void:
	_deck_selector.start_game()


## ── 日志面板 ──

func on_log_toggle_pressed() -> void:
	_log_panel.visible = not _log_panel.visible
