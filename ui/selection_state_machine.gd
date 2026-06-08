extends RefCounted
class_name SelectionStateMachine

## 交互模式状态机 — 从 BattleScene 提取
## 管理：选中状态、交互模式切换、动作按钮启用/禁用、上下文标签

# 状态枚举
enum Mode {
	NORMAL,             # 正常选牌
	SNIPER_TARGETING,   # 狙击攻击选目标
	RAID_TARGETING,     # RAID 叠放选目标
	BLOCKER_SELECTION,  # 选择阻挡者
	LIFE_TRIGGER,       # 生命触发待处理
	PENDING_DECISION,   # 待决策
	LIFE_REVEAL,        # 生命翻牌弹窗
	BOARD_TARGET,       # 战场目标选择
}

# ── 状态变量 ──
var selected_hand_card_uid := ""
var selected_board_card_uid := ""
var selected_board_zone_name := ""
var sniper_attack_source_uid := ""
var raid_source_card_uid := ""
var raid_target_selection_mode := false
var pending_attack_uid := ""
var pending_defender_player_id := ""
var selected_life_trigger_uid := ""
var selected_pending_decision_index := -1
var selected_pending_decision_choice_index := 0
var preview_card_uid := ""
var preview_player_id := ""
var preview_zone_name := ""

# ── 引用 ──
var _game_manager: Node
var _action_bar: Control
var _selected_card_label: Label
var _card_preview_panel
var _buttons: Dictionary = {}
var _snapshot_provider: Callable

# Button names
const BTN_PLAY_FRONT = "play_front"
const BTN_PLAY_ENERGY = "play_energy"
const BTN_USE_EVENT = "use_event"
const BTN_RAID = "raid"
const BTN_MAIN_ACTIVATE = "main_activate"
const BTN_STEP = "step"
const BTN_MOVE_FRONT = "move_front"
const BTN_SNIPER_ATTACK = "sniper_attack"
const BTN_ACTIVATE_LIFE = "activate_life"
const BTN_SKIP_LIFE = "skip_life"
const BTN_CANCEL = "cancel"


func setup(gm: Node, action_bar: Control, label: Label, preview_panel) -> void:
	_game_manager = gm
	_action_bar = action_bar
	_selected_card_label = label
	_card_preview_panel = preview_panel


func set_snapshot_provider(provider: Callable) -> void:
	_snapshot_provider = provider


func register_button(name: String, btn: Button) -> void:
	_buttons[name] = btn


func _snapshot() -> Dictionary:
	if _snapshot_provider.is_valid():
		return _snapshot_provider.call()
	return {}


func current_mode() -> Mode:
	var snap := _snapshot()
	# Life reveal modal takes priority
	var lr: Dictionary = snap.get("life_reveal_modal", {})
	if bool(lr.get("visible", false)):
		return Mode.LIFE_REVEAL
	# Pending board target selection
	if _is_board_target_selection_pending():
		return Mode.BOARD_TARGET
	# Pending decisions
	if not (snap.get("pending_decisions", []) as Array).is_empty():
		return Mode.PENDING_DECISION
	# Life triggers
	if not (snap.get("pending_life_triggers", []) as Array).is_empty():
		return Mode.LIFE_TRIGGER
	# RAID targeting
	if raid_target_selection_mode:
		return Mode.RAID_TARGETING
	# Sniper targeting
	if sniper_attack_source_uid != "":
		return Mode.SNIPER_TARGETING
	# Blocker selection
	if pending_attack_uid != "":
		return Mode.BLOCKER_SELECTION
	return Mode.NORMAL


func _is_board_target_selection_pending() -> bool:
	var snap := _snapshot()
	var decisions: Array = snap.get("pending_decisions", [])
	if decisions.is_empty():
		return false
	var idx := selected_pending_decision_index
	if idx < 0:
		idx = 0
	if idx >= decisions.size():
		return false
	var decision: Dictionary = decisions[idx]
	if str(decision.get("type", "")) != "ABILITY_TARGET_SELECTION":
		return false
	var targets: Array = decision.get("board_targets", [])
	if not targets.is_empty():
		return true
	# Also check if any choice has "board" as source
	for choice in decision.get("choices", []):
		var c: Dictionary = choice
		if str(c.get("source", "")) == "board":
			return true
	return false


## 清除所有选中状态
func clear_selection() -> void:
	selected_hand_card_uid = ""
	selected_board_card_uid = ""
	selected_board_zone_name = ""
	sniper_attack_source_uid = ""
	preview_card_uid = ""
	preview_player_id = ""
	preview_zone_name = ""
	clear_raid_selection()
	update_action_buttons()


func clear_raid_selection() -> void:
	raid_source_card_uid = ""
	raid_target_selection_mode = false


func clear_pending_attack() -> void:
	pending_attack_uid = ""
	pending_defender_player_id = ""
	# Buttons will be updated by update_action_buttons


## 生成上下文标签文案
func label_text() -> String:
	var snap := _snapshot()
	match current_mode():
		Mode.BOARD_TARGET:
			return "Choose a battlefield target"
		Mode.LIFE_REVEAL:
			return _life_reveal_label(snap)
		Mode.PENDING_DECISION:
			return _pending_decision_label(snap)
		Mode.LIFE_TRIGGER:
			return _life_trigger_label(snap)
		Mode.RAID_TARGETING:
			return "Choose a RAID target on your field"
		Mode.SNIPER_TARGETING:
			return "Choose an enemy front target for sniper attack"
		Mode.BLOCKER_SELECTION:
			return "Choose a blocker or click No Block"
		_:
			if selected_board_card_uid != "":
				return "Selected: " + _board_card_name()
			if preview_card_uid != "":
				return "Previewing: " + _preview_card_name()
			if selected_hand_card_uid != "":
				return "Selected: " + _hand_card_name()
			return "No card selected"


func _life_reveal_label(snap: Dictionary) -> String:
	var lr: Dictionary = snap.get("life_reveal_modal", {})
	var current_uid := str(lr.get("current_card_uid", ""))
	if current_uid == "":
		return "Life reveal complete"
	for card in lr.get("revealed_cards", []):
		var c: Dictionary = card
		if str(c.get("uid", "")) == current_uid:
			return "Life reveal: %s" % str(c.get("name", current_uid))
	return "Life reveal in progress"


func _pending_decision_label(snap: Dictionary) -> String:
	var decisions: Array = snap.get("pending_decisions", [])
	var idx := selected_pending_decision_index
	if idx < 0 or idx >= decisions.size():
		return "Resolve pending decision"
	var decision: Dictionary = decisions[idx]
	if str(decision.get("ui_mode", "")) in ["PREVIEW_PICK", "PREVIEW_REORDER"]:
		return str(decision.get("title", "处理看牌堆顶"))
	if _is_board_target_selection_pending():
		return "Choose a battlefield target"
	return "Pending: %s" % str(decision.get("type", "decision"))


func _life_trigger_label(snap: Dictionary) -> String:
	var triggers: Array = snap.get("pending_life_triggers", [])
	for entry in triggers:
		var e: Dictionary = entry
		if str(e.get("card_uid", "")) == selected_life_trigger_uid:
			return "Life trigger: %s" % str(e.get("card_name", "Unknown"))
	return "Resolve pending life triggers"


func _board_card_name() -> String:
	var snap := _snapshot()
	var players: Dictionary = snap.get("players", {})
	var active_id := str(snap.get("active_player_id", "P1"))
	var player_data: Dictionary = players.get(active_id, {})
	for zone_name in ["front_line", "energy_line"]:
		for card in player_data.get(zone_name, []):
			if str(card.get("uid", "")) == selected_board_card_uid:
				return str(card.get("name", "Unknown"))
	return "Unknown"


func _preview_card_name() -> String:
	var snap := _snapshot()
	var players: Dictionary = snap.get("players", {})
	var player_data: Dictionary = players.get(preview_player_id, {})
	var source: Array
	if preview_zone_name == "hand":
		source = player_data.get("hand", [])
	else:
		source = player_data.get(preview_zone_name, [])
	for card in source:
		if str(card.get("uid", "")) == preview_card_uid:
			return str(card.get("name", "Unknown"))
	return "Unknown"


func _hand_card_name() -> String:
	var snap := _snapshot()
	var active_id := str(snap.get("active_player_id", "P1"))
	var players: Dictionary = snap.get("players", {})
	var player_data: Dictionary = players.get(active_id, {})
	for card in player_data.get("hand", []):
		if str(card.get("uid", "")) == selected_hand_card_uid:
			return str(card.get("name", "Unknown"))
	return "Unknown"


## 更新动作按钮启用/禁用（核心状态机逻辑）
func update_action_buttons() -> void:
	var snap := _snapshot()
	var active_id := str(snap.get("active_player_id", "P1"))
	var phase := str(snap.get("phase", ""))
	var can_input := _can_input(snap)

	# 按钮默认隐藏
	_hide_all_action_buttons()

	if not can_input:
		return

	match current_mode():
		Mode.BOARD_TARGET, Mode.PENDING_DECISION, Mode.LIFE_REVEAL:
			return  # 特殊模式，隐藏所有动作按钮
		Mode.LIFE_TRIGGER:
			_show([BTN_ACTIVATE_LIFE, BTN_SKIP_LIFE])
			return
		Mode.SNIPER_TARGETING:
			_show([BTN_CANCEL])
			return
		Mode.RAID_TARGETING:
			_show([BTN_CANCEL])
			return
		Mode.BLOCKER_SELECTION:
			_show([BTN_CANCEL])
			return

	# NORMAL mode — 根据阶段和选中状态决定按钮
	if phase != "MAIN" and phase != "ATTACK":
		return

	# 手牌选中的动作
	if selected_hand_card_uid != "":
		var card := _find_hand_card(active_id)
		if not card.is_empty():
			var actions: Array = card.get("available_actions", [])
			if _has_action(actions, "PLAY_FRONT"):
				_show([BTN_PLAY_FRONT])
			if _has_action(actions, "PLAY_ENERGY"):
				_show([BTN_PLAY_ENERGY])
			if _has_action(actions, "PLAY_EVENT"):
				_show([BTN_USE_EVENT])
			if _has_action(actions, "RAID"):
				_show([BTN_RAID])
			_show([BTN_CANCEL])
		return

	# 战场卡牌选中的动作
	if selected_board_card_uid != "":
		var card := _find_board_card(active_id)
		if not card.is_empty():
			var actions: Array = card.get("available_actions", [])
			if _has_action(actions, "ACTIVATE_MAIN"):
				_show([BTN_MAIN_ACTIVATE])
			if _has_action(actions, "STEP"):
				_show([BTN_STEP])
			if _has_action(actions, "MOVE_TO_FRONT"):
				_show([BTN_MOVE_FRONT])
			if _has_action(actions, "SNIPER_ATTACK"):
				_show([BTN_SNIPER_ATTACK])
			_show([BTN_CANCEL])
		return


func _hide_all_action_buttons() -> void:
	for btn in _buttons.values():
		btn.visible = false


func _show(names: Array) -> void:
	for name in names:
		var btn: Button = _buttons.get(name)
		if btn:
			btn.visible = true


func _can_input(snap: Dictionary) -> bool:
	if bool(snap.get("winner_player_id", "")):
		return false
	if bool(snap.get("pending_game_setup", false)):
		return false
	if not bool(snap.get("human_input_enabled", true)):
		return false
	return true


func _find_hand_card(player_id: String) -> Dictionary:
	var snap := _snapshot()
	var players: Dictionary = snap.get("players", {})
	var player_data: Dictionary = players.get(player_id, {})
	for card in player_data.get("hand", []):
		if str(card.get("uid", "")) == selected_hand_card_uid:
			return card
	return {}


func _find_board_card(player_id: String) -> Dictionary:
	var snap := _snapshot()
	var players: Dictionary = snap.get("players", {})
	var player_data: Dictionary = players.get(player_id, {})
	for zone_name in ["front_line", "energy_line"]:
		for card in player_data.get(zone_name, []):
			if str(card.get("uid", "")) == selected_board_card_uid:
				return card
	return {}


func _has_action(actions: Array, action_name: String) -> bool:
	for a in actions:
		if str(a) == action_name:
			return true
	return false
