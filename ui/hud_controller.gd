extends RefCounted
class_name HUDController

## 顶部 HUD 控制器 — 从 BattleScene 提取
## 管理：顶部状态栏标签更新、阶段控制按钮、阻挡请求、AI 动作提示

# ── UI 节点引用 ──
var _turn_label: Label
var _active_player_label: Label
var _phase_indicator: Node
var _hand_count_label: Label
var _energy_label: Label
# P4: 能量彩色圆点容器（程序化创建，替代纯文本能量显示）
var _energy_dots_container: HFlowContainer
var _last_energy_map: Dictionary = {}
var _ap_label: Label
var _winner_label: Label
var _next_phase_button: Button
var _bonus_draw_button: Button
var _no_block_button: Button
var _selected_card_label: Label
var _ai_action_label: Label

# ── 游戏引用 ──
var _game_manager: Node
var _snapshot_provider: Callable
var _human_input_provider: Callable
var _ai_action_hint  # AIActionHint instance

# ── 状态 ──
var pending_attack_uid := ""
var pending_defender_player_id := ""


func setup(gm: Node,
		   turn_label: Label,
		   active_player_label: Label,
		   phase_indicator,
		   hand_count_label: Label,
		   energy_label: Label,
		   ap_label: Label,
		   winner_label: Label,
		   next_phase_button: Button,
		   bonus_draw_button: Button,
		   no_block_button: Button,
		   selected_card_label: Label,
		   ai_action_label: Label,
		   ai_action_hint) -> void:
	_game_manager = gm
	_turn_label = turn_label
	_active_player_label = active_player_label
	_phase_indicator = phase_indicator
	_hand_count_label = hand_count_label
	_energy_label = energy_label
	_create_energy_dots_container()
	_ap_label = ap_label
	_winner_label = winner_label
	_next_phase_button = next_phase_button
	_bonus_draw_button = bonus_draw_button
	_no_block_button = no_block_button
	_selected_card_label = selected_card_label
	_ai_action_label = ai_action_label
	_ai_action_hint = ai_action_hint


func set_snapshot_provider(provider: Callable) -> void:
	_snapshot_provider = provider


func set_human_input_provider(provider: Callable) -> void:
	_human_input_provider = provider


func _snapshot() -> Dictionary:
	if _snapshot_provider.is_valid():
		return _snapshot_provider.call()
	return {}


func _human_input_enabled() -> bool:
	if _human_input_provider.is_valid():
		return _human_input_provider.call()
	return true


## ── 标签更新 ──

func update_hud(snapshot: Dictionary, active_player_data: Dictionary, display_hand_player_data: Dictionary) -> void:
	var has_winner := str(snapshot.get("winner_player_id", "")) != ""
	var has_pending_life := not (snapshot.get("pending_life_triggers", []) as Array).is_empty()
	var has_pending_life_reveal := bool((snapshot.get("life_reveal_modal", {}) as Dictionary).get("visible", false))
	var has_pending_decisions := not (snapshot.get("pending_decisions", []) as Array).is_empty()
	var has_pending_gate := has_pending_life or has_pending_life_reveal or has_pending_decisions
	var phase := str(snapshot.get("phase", "START"))
	var can_bonus_draw := bool(snapshot.get("can_bonus_draw", false))
	var human_input := _human_input_enabled()
	var priority_player_id := str(snapshot.get("priority_player_id", ""))
	var controller_types: Dictionary = snapshot.get("controller_types", {})
	var action_controller_type := str(controller_types.get(priority_player_id, snapshot.get("action_player_controller", "HUMAN")))

	# 标签更新
	_turn_label.text = "Turn %d" % int(snapshot.get("turn_number", 1))
	_active_player_label.text = "Action: %s (%s)" % [priority_player_id, action_controller_type]
	_phase_indicator.set_phase_text(phase)
	_hand_count_label.text = "Hand: %d" % int(display_hand_player_data.get("hand_count", 0))
	_energy_label.text = ""  # P4: 文本标签改为空，由彩色圆点替代
	_populate_energy_dots(active_player_data.get("available_energy", {}))
	_ap_label.text = "AP: %d/%d" % [int(active_player_data.get("ap_active", 0)), int(active_player_data.get("ap_total", 0))]
	_winner_label.text = "Winner: %s" % str(snapshot.get("winner_player_id", "-"))

	# 阶段控制按钮
	_bonus_draw_button.visible = phase == "DRAW"
	_bonus_draw_button.disabled = has_winner or has_pending_gate or not can_bonus_draw or not human_input
	_next_phase_button.disabled = has_winner or has_pending_gate or not human_input
	_no_block_button.disabled = has_winner or has_pending_gate or not human_input


## ── 阻挡请求 ──

func on_blockers_requested(request: Dictionary) -> void:
	var snap := _snapshot()
	var controller_types: Dictionary = snap.get("controller_types", {})
	var defender_player_id := str(request.get("defender_player_id", ""))
	if str(controller_types.get(defender_player_id, "HUMAN")) != "HUMAN":
		return
	var blockers: Array = request.get("blockers", [])
	if blockers.is_empty():
		_game_manager.resolve_attack(str(request.get("attacker_uid", "")))
		return
	pending_attack_uid = str(request.get("attacker_uid", ""))
	pending_defender_player_id = defender_player_id
	_no_block_button.visible = true
	_selected_card_label.text = "Choose a blocker or click No Block"


func clear_pending_attack() -> void:
	pending_attack_uid = ""
	pending_defender_player_id = ""
	_no_block_button.visible = false


## ── 阶段按钮处理 ──

func on_next_phase_pressed() -> void:
	if _has_pending_gate() or not _human_input_enabled():
		return
	clear_pending_attack()
	_game_manager.advance_phase()


func on_no_block_pressed() -> void:
	if _has_pending_gate() or not _human_input_enabled():
		return
	if pending_attack_uid == "":
		return
	_game_manager.resolve_attack(pending_attack_uid)
	clear_pending_attack()


func on_bonus_draw_pressed() -> void:
	if _has_pending_gate() or not _human_input_enabled():
		return
	_game_manager.request_bonus_draw()


## ── AI 动作提示 ──

func on_ai_action_executed(action_info: Dictionary) -> void:
	_ai_action_hint.show_action(action_info)


## ── 辅助 ──

func _has_pending_gate() -> bool:
	var snap := _snapshot()
	return not (snap.get("pending_life_triggers", []) as Array).is_empty() \
		or bool((snap.get("life_reveal_modal", {}) as Dictionary).get("visible", false)) \
		or not (snap.get("pending_decisions", []) as Array).is_empty()


func _format_energy_total(energy_map: Dictionary) -> String:
	if energy_map.is_empty():
		return "0"
	var total := 0
	for color in energy_map.keys():
		total += int(energy_map.get(color, 0))
	return str(total)


## P4: 创建能量彩色圆点容器（HFlowContainer，放在 energy_label 旁边）
func _create_energy_dots_container() -> void:
	_energy_dots_container = HFlowContainer.new()
	_energy_dots_container.name = "EnergyDots"
	_energy_dots_container.add_theme_constant_override("h_separation", 4)
	_energy_dots_container.add_theme_constant_override("v_separation", 2)
	var parent := _energy_label.get_parent()
	if parent:
		parent.add_child(_energy_dots_container)
		parent.move_child(_energy_dots_container, _energy_label.get_index() + 1)


## P4: 填充能量彩色圆点
func _populate_energy_dots(energy_map: Dictionary) -> void:
	if not _energy_dots_container:
		return
	# 能量值未变化则跳过重建
	if _energy_map_equals(_last_energy_map, energy_map):
		return
	_last_energy_map = energy_map.duplicate()

	for child in _energy_dots_container.get_children():
		child.queue_free()

	var order := ["red", "blue", "green", "purple", "yellow", "white"]
	for color in order:
		var count := int(energy_map.get(color, 0))
		if count <= 0:
			continue
		var dot := _make_dot(color, count)
		_energy_dots_container.add_child(dot)


func _energy_map_equals(a: Dictionary, b: Dictionary) -> bool:
	if a.keys().size() != b.keys().size():
		return false
	for key in a:
		if int(a.get(key, -1)) != int(b.get(key, -2)):
			return false
	return true


func _make_dot(color: String, count: int) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 2)

	var tex := _dot_texture(color)
	if tex:
		var rect := TextureRect.new()
		rect.texture = tex
		rect.custom_minimum_size = Vector2(14, 14)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hbox.add_child(rect)
	else:
		var fallback := ColorRect.new()
		fallback.custom_minimum_size = Vector2(14, 14)
		fallback.color = _dot_fallback_color(color)
		hbox.add_child(fallback)

	var label := Label.new()
	label.text = str(count)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color("#EDF0F5"))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(label)

	return hbox


func _dot_fallback_color(color: String) -> Color:
	match color:
		"red":    return Color("#D95A5A")
		"blue":   return Color("#4A90D9")
		"green":  return Color("#5C9A6E")
		"purple": return Color("#8E6BBF")
		"yellow": return Color("#D4A843")
		_:        return Color("#D0D5DE")


func _dot_texture(color: String) -> Texture2D:
	const DOT_RED    := preload("res://assets/ui/dots/energy_red.png")
	const DOT_BLUE   := preload("res://assets/ui/dots/energy_blue.png")
	const DOT_GREEN  := preload("res://assets/ui/dots/energy_green.png")
	const DOT_PURPLE := preload("res://assets/ui/dots/energy_purple.png")
	const DOT_YELLOW := preload("res://assets/ui/dots/energy_yellow.png")
	const DOT_WHITE  := preload("res://assets/ui/dots/energy_white.png")
	match color:
		"red":    return DOT_RED
		"blue":   return DOT_BLUE
		"green":  return DOT_GREEN
		"purple": return DOT_PURPLE
		"yellow": return DOT_YELLOW
		"white":  return DOT_WHITE
	return null
