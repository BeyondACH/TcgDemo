extends Control
class_name BoardPanel

## 通用战场面板 — 前线/能量线复用
## @export 参数化面板类型、标题、强调色
## P2 增强：内建 DropZone，由 BattleScene 通过 populate() 填充卡牌

signal card_was_pressed(player_id: String, card_uid: String, zone_name: String)
signal panel_drop_was_requested(player_id: String, zone_name: String, card_uid: String)
signal card_was_hovered(player_id: String, card_uid: String, zone_name: String, is_hovered: bool, card_data: Dictionary)

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
const ENTER_EXIT_DURATION := 0.18
const ICON_SWORD := preload("res://assets/ui/icons/slot_sword.svg")
const ICON_DIAMOND := preload("res://assets/ui/icons/slot_diamond.svg")
const DropZone = preload("res://ui/drop_zone.gd")
const CardView = preload("res://ui/card_view.gd")

# Nodes
var _title_label: Label
var _slot_count_label: Label
var _hint_label: Label
var _title_bar: Control
var _slot_container: HBoxContainer
var _drop_zone: DropZone
var _cards: Array[Dictionary] = []
var _zone_name := ""
# P3: 预建的阻挡高亮 StyleBox（避免每次 set_block_highlight 重复构造）
var _block_highlight_style: StyleBoxFlat
# P4: 预建的空槽 StyleBox（避免每次 _make_empty_slot 重复构造）
var _empty_slot_style: StyleBoxFlat


func _ready() -> void:
	_build_ui()
	_update_style()
	_build_block_highlight_style()
	_build_empty_slot_style()


func _build_ui() -> void:
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

	# P3: Inline 错误提示 — 标题条右侧，默认隐藏
	_hint_label = Label.new()
	_hint_label.name = "HintLabel"
	_hint_label.text = ""
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color", Color("#D95A5A"))
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.visible = false
	_hint_label.modulate.a = 0.0
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_hint_label.offset_right = -8
	_title_bar.add_child(_hint_label)

	_title_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_slot_count_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	# 槽位容器
	_slot_container = HBoxContainer.new()
	_slot_container.name = "SlotContainer"
	_slot_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_slot_container.add_theme_constant_override("separation", 14)
	_slot_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slot_container.offset_top = 32
	_slot_container.offset_bottom = 0
	add_child(_slot_container)

	# DropZone 覆盖层（在槽位容器之上，接收拖拽）
	_drop_zone = DropZone.new()
	_drop_zone.name = "DropZone"
	_drop_zone.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drop_zone.offset_top = 32
	_drop_zone.card_dropped.connect(_on_panel_dropped)
	add_child(_drop_zone)

	# 创建 4 个空槽位占位
	for i in range(MAX_SLOTS):
		var slot_placeholder := _make_empty_slot(Vector2(108, 152))
		slot_placeholder.name = "Slot" + str(i)
		_slot_container.add_child(slot_placeholder)


func _make_empty_slot_style() -> StyleBoxFlat:
	return _empty_slot_style


func _build_empty_slot_style() -> void:
	_empty_slot_style = StyleBoxFlat.new()
	_empty_slot_style.bg_color = Color(1, 1, 1, 0.02)
	_empty_slot_style.set_corner_radius_all(10)
	_empty_slot_style.border_width_left = 2
	_empty_slot_style.border_width_right = 2
	_empty_slot_style.border_width_top = 2
	_empty_slot_style.border_width_bottom = 2
	_empty_slot_style.border_color = Color(0.824, 0.863, 0.922, 0.14)
	_empty_slot_style.shadow_color = Color(0, 0, 0, 0.12)
	_empty_slot_style.shadow_size = 10
	_empty_slot_style.shadow_offset = Vector2(0, 4)


## P4: 创建带区域图标的空槽位占位
func _make_empty_slot(card_size: Vector2) -> Control:
	var c := Control.new()
	c.custom_minimum_size = card_size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_theme_stylebox_override("panel", _make_empty_slot_style())

	var icon_tex := ICON_SWORD if panel_type == PanelType.FRONT_LINE else ICON_DIAMOND
	var icon := TextureRect.new()
	icon.texture = icon_tex
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate.a = 0.14
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(icon)
	return c


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

func populate(cards_data: Array, zone_name: String) -> void:
	set_cards(cards_data, zone_name)


func clear() -> void:
	set_cards([], _zone_name)


## P3: 显示 inline 错误提示 — 标题条右侧闪现红色文案，2 秒后淡出
func show_inline_hint(text: String) -> void:
	if not _hint_label:
		return
	# 杀掉旧 tween
	if _hint_label.has_meta("_hint_tween"):
		var old_tw: Tween = _hint_label.get_meta("_hint_tween")
		if old_tw and old_tw.is_valid():
			old_tw.kill()
	_hint_label.text = text
	_hint_label.visible = true
	_hint_label.modulate.a = 1.0
	var tw := _hint_label.create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.5)
	tw.tween_property(_hint_label, "modulate:a", 0.0, 1.5)
	tw.tween_callback(func():
		_hint_label.visible = false
		_hint_label.text = ""
	)
	_hint_label.set_meta("_hint_tween", tw)


## P3: 阻挡高亮 — 面板边框变金色，可阻挡角色脉冲描边
func set_block_highlight(enabled: bool, blockable_uids: Array[String] = []) -> void:
	if enabled:
		add_theme_stylebox_override("panel", _block_highlight_style)
		_start_block_glow()
	else:
		_update_style()
		_kill_block_glow()
	# 标记可阻挡的卡牌
	for child in _slot_container.get_children():
		if child is CardView:
			child.set_blockable(enabled and (blockable_uids.is_empty() or child.card_uid in blockable_uids))


func _build_block_highlight_style() -> void:
	_block_highlight_style = StyleBoxFlat.new()
	_block_highlight_style.bg_color = Color(0.078, 0.102, 0.141, 0.88)
	_block_highlight_style.set_corner_radius_all(14)
	_block_highlight_style.border_width_left = 2
	_block_highlight_style.border_width_right = 2
	_block_highlight_style.border_width_top = 2
	_block_highlight_style.border_width_bottom = 2
	_block_highlight_style.border_color = Color("#D4A843")
	_block_highlight_style.shadow_color = Color(0, 0, 0, 0.32)
	_block_highlight_style.shadow_size = 28
	_block_highlight_style.shadow_offset = Vector2(0, 10)


func _start_block_glow() -> void:
	_kill_block_glow()
	var tw := create_tween()
	tw.set_loops(0)
	tw.tween_property(self, "modulate:a", 0.85, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	set_meta("_block_glow_tween", tw)


func _kill_block_glow() -> void:
	if has_meta("_block_glow_tween"):
		var tw: Tween = get_meta("_block_glow_tween")
		if tw and tw.is_valid():
			tw.kill()
		remove_meta("_block_glow_tween")
	modulate.a = 1.0


## P3: 动画化 set_cards — 新旧卡 uid 对比，离场动画 + 入场动画
func set_cards(cards_data: Array, zone_name: String) -> void:
	_cards = cards_data
	_zone_name = zone_name
	_drop_zone.setup(player_id, zone_name, _calculate_card_size())

	var card_size := _calculate_card_size()

	# 收集当前槽位容器中的 uid
	var old_uid_to_view: Dictionary = {}
	for child in _slot_container.get_children():
		if child is CardView:
			old_uid_to_view[child.card_uid] = child

	# 收集新数据中的 uid（同时建立 uid→data 映射）
	var new_uid_to_data: Dictionary = {}
	for cd in cards_data:
		var uid: String = str(cd.get("uid", ""))
		if uid.is_empty():
			continue
		new_uid_to_data[uid] = cd

	# 计算三类 uid 集合
	var exiting_uids: Array[String] = []
	var staying_uids: Array[String] = []
	for uid in old_uid_to_view:
		if new_uid_to_data.has(uid):
			staying_uids.append(uid)
		else:
			exiting_uids.append(uid)

	var entering_uids: Array[String] = []
	for uid in new_uid_to_data:
		if not old_uid_to_view.has(uid):
			entering_uids.append(uid)

	# ── 离场动画：exiting 的 CardView → scale 0 + fade out, 然后 queue_free ──
	for uid in exiting_uids:
		var view: CardView = old_uid_to_view[uid]
		_kill_card_tween(view)
		var tw := view.create_tween()
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.set_parallel(true)
		tw.tween_property(view, "scale", Vector2.ZERO, ENTER_EXIT_DURATION)
		tw.tween_property(view, "modulate:a", 0.0, ENTER_EXIT_DURATION)
		tw.chain().tween_callback(view.queue_free)
		_store_card_tween(view, tw)

	# ── 清空槽位容器（先移除旧节点，但不释放 — 离场 tween 持有引用）─
	for child in _slot_container.get_children():
		_slot_container.remove_child(child)

	# ── 重建槽位内容 ─
	for i in range(MAX_SLOTS):
		if i < cards_data.size():
			var card_data: Dictionary = cards_data[i]
			var uid: String = str(card_data.get("uid", ""))

			if uid in staying_uids and old_uid_to_view.has(uid):
				# 复用不变卡牌（不销毁、不重建、不重做动画）
				var view: CardView = old_uid_to_view[uid]
				_kill_card_tween(view)
				view.scale = Vector2.ONE
				view.modulate.a = 1.0
				_slot_container.add_child(view)
			else:
				# 新入场卡牌：创建 → 设 scale 0 + alpha 0 → add_child → 播放入场动画
				var card_view := CardView.new()
				card_view.setup(card_data, player_id, zone_name, card_size, CardView.DISPLAY_MODE_BOARD)
				card_view.card_pressed.connect(_on_inner_card_pressed)
				card_view.card_hovered.connect(_on_inner_card_hovered)
				card_view.scale = Vector2.ZERO
				card_view.modulate.a = 0.0
				_slot_container.add_child(card_view)
				# call_deferred 确保 add_child 后 scale 归零生效，再启 tween
				card_view.call_deferred(&"_start_enter_tween")
		else:
			# 空槽位占位（带区域图标）
			var placeholder := _make_empty_slot(card_size)
			_slot_container.add_child(placeholder)

	_slot_count_label.text = str(cards_data.size()) + "/" + str(MAX_SLOTS)
	if cards_data.size() >= MAX_SLOTS:
		_slot_count_label.add_theme_color_override("font_color", Color("#A8454A"))
	else:
		_slot_count_label.add_theme_color_override("font_color", Color("#A8B2C2"))


## 杀掉 CardView 上正在运行的 tween（避免竞争）
func _kill_card_tween(view: CardView) -> void:
	if view.has_meta("_enter_tween"):
		var tw: Tween = view.get_meta("_enter_tween")
		if tw and tw.is_valid():
			tw.kill()
		view.remove_meta("_enter_tween")


## 存储 CardView 上的 tween 引用
func _store_card_tween(view: CardView, tw: Tween) -> void:
	view.set_meta("_enter_tween", tw)


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


func _on_inner_card_hovered(card_uid: String, is_hovered: bool, card_data: Dictionary) -> void:
	card_was_hovered.emit(player_id, card_uid, _zone_name, is_hovered, card_data)


func _on_panel_dropped(p_player_id: String, p_zone_name: String, card_uid: String) -> void:
	panel_drop_was_requested.emit(p_player_id, p_zone_name, card_uid)
