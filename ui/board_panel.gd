extends Control
class_name BoardPanel

## 通用战场面板 — 前线/能量线复用
## @export 参数化面板类型、标题、强调色
## P2 增强：内建 DropZone + 暴露堆叠锚点供 BattleScene 挂载附属堆叠

signal card_was_pressed(player_id: String, card_uid: String, zone_name: String)
signal panel_drop_was_requested(player_id: String, zone_name: String, card_uid: String)

enum PanelType { FRONT_LINE, ENERGY_LINE }

@export var panel_type: PanelType = PanelType.FRONT_LINE:
	set(v):
		panel_type = v
		_update_style()

@export var panel_title: String = "FRONT LINE":
	set(v):
		panel_title = v
		if _title_label:
			_title_label.text = v

@export var player_id: String = "P1":
	set(v):
		player_id = v
		if _drop_zone:
			_drop_zone.player_id = v

const MAX_SLOTS := 4
const DropZone = preload("res://ui/drop_zone.gd")
const CardView = preload("res://ui/card_view.gd")

# Nodes
var _title_label: Label
var _slot_count_label: Label
var _title_bar: Control
var _slot_container: HBoxContainer
var _drop_zone: DropZone
var _cards: Array = []
var _zone_name := ""

## 堆叠锚点：BattleScene 向这些 Control 下挂载 LifeStackView / ZoneStackSummaryView
var left_stack_anchor: Control   ## 面板左侧外缘，挂载 Life / Removed 堆叠
var right_stack_anchor: Control  ## 面板右侧外缘，挂载 Deck / Outside 堆叠


func _ready() -> void:
	_build_ui()
	_update_style()


func _build_ui() -> void:
	# 面板整体
	custom_minimum_size = Vector2(600, 200)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 标题条
	_title_bar = Control.new()
	_title_bar.name = "TitleBar"
	_title_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_bar.custom_minimum_size.y = 28
	_title_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title_bar.offset_bottom = 28
	add_child(_title_bar)

	# 标题文字
	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.text = panel_title
	_title_label.add_theme_font_size_override("font_size", 14)
	_title_label.add_theme_color_override("font_color", Color("#EDF0F5"))
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_title_label.offset_left = 12
	_title_label.offset_right = 12
	_title_bar.add_child(_title_label)

	# 槽位计数
	_slot_count_label = Label.new()
	_slot_count_label.name = "SlotCountLabel"
	_slot_count_label.text = "0/" + str(MAX_SLOTS)
	_slot_count_label.add_theme_font_size_override("font_size", 12)
	_slot_count_label.add_theme_color_override("font_color", Color("#A8B2C2"))
	_slot_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_slot_count_label.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_slot_count_label.offset_left = 12
	_title_bar.add_child(_slot_count_label)

	_title_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_slot_count_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	# ── 槽位容器 (在 DropZone 之下) ──
	_slot_container = HBoxContainer.new()
	_slot_container.name = "SlotContainer"
	_slot_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_slot_container.add_theme_constant_override("separation", 14)
	_slot_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slot_container.offset_top = 32
	_slot_container.offset_bottom = 0
	add_child(_slot_container)

	# ── DropZone 覆盖层（在槽位容器之上，接收拖拽） ──
	_drop_zone = DropZone.new()
	_drop_zone.name = "DropZone"
	_drop_zone.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drop_zone.offset_top = 32
	_drop_zone.card_dropped.connect(_on_panel_dropped)
	add_child(_drop_zone)

	# ── 堆叠锚点（面板外部，由 BattleScene 挂载堆叠视图） ──
	left_stack_anchor = Control.new()
	left_stack_anchor.name = "LeftStackAnchor"
	left_stack_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 默认贴在面板左侧外缘，BattleScene 会在 panel 外部设置实际位置
	add_child(left_stack_anchor)

	right_stack_anchor = Control.new()
	right_stack_anchor.name = "RightStackAnchor"
	right_stack_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right_stack_anchor)

	# 创建 4 个空槽位占位
	for i in range(MAX_SLOTS):
		var slot_placeholder := Control.new()
		slot_placeholder.name = "Slot" + str(i)
		slot_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_placeholder.add_theme_stylebox_override("panel", _make_empty_slot_style())
		_slot_container.add_child(slot_placeholder)


func _make_empty_slot_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.02)
	sb.set_corner_radius_all(10)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.824, 0.863, 0.922, 0.14)
	sb.shadow_color = Color(0, 0, 0, 0.12)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 4)
	return sb


func _make_card_back_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.078, 0.102, 0.141, 1.0)
	sb.set_corner_radius_all(10)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.824, 0.863, 0.922, 0.20)
	return sb


func _update_style() -> void:
	if not _title_bar:
		return

	match panel_type:
		PanelType.FRONT_LINE:
			_title_bar.add_theme_stylebox_override("panel", _make_title_style(Color(0.659, 0.271, 0.290, 0.42)))
		PanelType.ENERGY_LINE:
			_title_bar.add_theme_stylebox_override("panel", _make_title_style(Color(0.290, 0.565, 0.851, 0.32)))

	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.078, 0.102, 0.141, 0.88)
	panel_sb.set_corner_radius_all(14)
	panel_sb.border_width_left = 1
	panel_sb.border_width_right = 1
	panel_sb.border_width_top = 1
	panel_sb.border_width_bottom = 1
	panel_sb.border_color = Color(0.824, 0.863, 0.922, 0.10)
	panel_sb.shadow_color = Color(0, 0, 0, 0.32)
	panel_sb.shadow_size = 28
	panel_sb.shadow_offset = Vector2(0, 10)
	add_theme_stylebox_override("panel", panel_sb)


func _make_title_style(bg_color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.set_corner_radius_all(14)
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	return sb


## ── 外部接口 ──

## 设置面板卡牌数据 — BoardController / BattleScene 调用
func populate(cards_data: Array, zone_name: String) -> void:
	set_cards(cards_data, zone_name)


## 清除面板内容
func clear() -> void:
	set_cards([], _zone_name)


func set_cards(cards_data: Array, zone_name: String) -> void:
	_cards = cards_data
	_zone_name = zone_name
	_drop_zone.setup(player_id, zone_name, _calculate_card_size())

	# 清空并重建卡牌行
	for child in _slot_container.get_children():
		_slot_container.remove_child(child)
		child.queue_free()

	var card_size := _calculate_card_size()

	for i in range(MAX_SLOTS):
		if i < cards_data.size():
			var card_data: Dictionary = cards_data[i]
			var card_view := CardView.new()
			card_view.setup(card_data, player_id, zone_name, card_size, CardView.DISPLAY_MODE_BOARD)
			card_view.card_pressed.connect(_on_inner_card_pressed)
			_slot_container.add_child(card_view)
		else:
			var placeholder := Control.new()
			placeholder.custom_minimum_size = card_size
			placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
			placeholder.add_theme_stylebox_override("panel", _make_empty_slot_style())
			_slot_container.add_child(placeholder)

	_slot_count_label.text = str(cards_data.size()) + "/" + str(MAX_SLOTS)
	if cards_data.size() >= MAX_SLOTS:
		_slot_count_label.add_theme_color_override("font_color", Color("#A8454A"))
	else:
		_slot_count_label.add_theme_color_override("font_color", Color("#A8B2C2"))


func _calculate_card_size() -> Vector2:
	if size.x <= 0.0 or size.y <= 0.0:
		return Vector2(108, 152)
	var available_width: float = size.x - 12.0 * 2.0
	var slot_width: float = (available_width - 14.0 * 3.0) / 4.0
	var slot_height: float = size.y - 32.0 - 8.0
	var card_w: float = minf(slot_width, slot_height * 5.0 / 7.0)
	var card_h: float = card_w * 7.0 / 5.0
	return Vector2(card_w, card_h)


func _on_inner_card_pressed(owner_id: String, card_uid: String, zone: String) -> void:
	card_was_pressed.emit(owner_id, card_uid, zone)


func _on_panel_dropped(p_player_id: String, p_zone_name: String, card_uid: String) -> void:
	panel_drop_was_requested.emit(p_player_id, p_zone_name, card_uid)
