## TooltipManager — 浮动卡牌详情 tooltip
## P3-2: 悬停卡牌 400ms 后，在卡牌附近弹出详情面板。
## 样式遵循 ui_art_style_guide.md §12.4。

const TOOLTIP_DELAY := 0.4
const TOOLTIP_MAX_WIDTH := 260.0
const TOOLTIP_OFFSET_X := 14.0
const TOOLTIP_OFFSET_Y := -8.0

var _parent: Control
var _panel: PanelContainer
var _content: VBoxContainer
var _timer: Timer
var _pending_card_data: Dictionary = {}


func setup(parent: Control) -> void:
	_parent = parent
	_create_panel()
	_create_timer()


func _create_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "TooltipPanel"
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.047, 0.063, 0.086, 0.96)
	sb.set_corner_radius_all(10)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.176, 0.204, 0.251, 1.0)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	sb.shadow_color = Color(0, 0, 0, 0.38)
	sb.shadow_size = 20
	sb.shadow_offset = Vector2(0, 8)
	_panel.add_theme_stylebox_override("panel", sb)

	_content = VBoxContainer.new()
	_content.name = "TooltipContent"
	_content.add_theme_constant_override("separation", 4)
	_panel.add_child(_content)

	_parent.add_child(_panel)


func _create_timer() -> void:
	_timer = Timer.new()
	_timer.name = "TooltipTimer"
	_timer.one_shot = true
	_timer.wait_time = TOOLTIP_DELAY
	_timer.timeout.connect(_show_tooltip)
	_parent.add_child(_timer)


## ── 公共入口 ──


func on_card_hovered(_player_id: String, _card_uid: String, _zone_name: String, is_hovered: bool, card_data: Dictionary) -> void:
	if is_hovered:
		_pending_card_data = card_data
		_timer.stop()
		_timer.start()
	else:
		_timer.stop()
		_hide_tooltip()


## ── 内部方法 ──


func _show_tooltip() -> void:
	if _pending_card_data.is_empty():
		return

	_clear_content()
	_build_content(_pending_card_data)
	_position_tooltip()
	_panel.visible = true


func _hide_tooltip() -> void:
	_panel.visible = false


func _clear_content() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()


func _build_content(card_data: Dictionary) -> void:
	var name_text := str(card_data.get("name", "???"))
	var card_type := str(card_data.get("card_type", "?"))
	var bp := int(card_data.get("bp", 0))
	var cost_ap := int(card_data.get("cost_ap", 0))
	var state := str(card_data.get("state", "ACTIVE"))
	var traits: Array = card_data.get("traits", [])
	var abilities: Array = card_data.get("abilities", [])
	var effect_text := str(card_data.get("effect_text", ""))

	# 名称行
	_add_label(name_text, Color("#EDF0F5"), 14, 600)

	# 类型 + BP + AP 行
	var info_line := card_type
	if bp > 0:
		info_line += "  BP:%d" % bp
	if cost_ap > 0:
		info_line += "  AP:%d" % cost_ap
	if info_line != card_type:
		_add_label(info_line, Color("#A8B2C2"), 11, 400)

	# 状态
	if state != "ACTIVE":
		_add_label(state, Color("#D95A5A"), 11, 600)

	# 特征
	if not traits.is_empty():
		_add_label("特征: %s" % ", ".join(traits), Color("#6B7588"), 10, 400)

	# 关键词
	var keywords: Array[String] = []
	for ab in abilities:
		var kw := str(ab.get("keyword", ""))
		if not kw.is_empty():
			keywords.append(kw)
	if not keywords.is_empty():
		_add_label("关键词: %s" % ", ".join(keywords), Color("#D4A843"), 11, 600)

	# 效果文本
	if not effect_text.is_empty():
		_add_label(effect_text, Color("#A8B2C2"), 10, 400)

	# 能量费
	var cost_energy: Dictionary = card_data.get("cost_energy", {})
	if not cost_energy.is_empty():
		var parts: Array[String] = []
		for color in cost_energy:
			parts.append("%s:%d" % [color, int(cost_energy[color])])
		_add_label("能量费: %s" % ", ".join(parts), Color("#6B7588"), 10, 400)


func _add_label(text: String, color: Color, font_size: int, _weight: int) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = TOOLTIP_MAX_WIDTH - 20
	_content.add_child(label)


func _position_tooltip() -> void:
	# 基于鼠标位置定位 tooltip
	var mouse_pos := _parent.get_local_mouse_position()
	var viewport_size := _parent.get_viewport_rect().size

	_content.reset_size()
	_panel.reset_size()
	var tooltip_size := _panel.get_combined_minimum_size()

	var x := mouse_pos.x + TOOLTIP_OFFSET_X
	var y := mouse_pos.y + TOOLTIP_OFFSET_Y

	# 超出右边界 → 翻到左边
	if x + tooltip_size.x > viewport_size.x - 8:
		x = mouse_pos.x - tooltip_size.x - TOOLTIP_OFFSET_X

	# 超出下边界 → 上移
	if y + tooltip_size.y > viewport_size.y - 8:
		y = viewport_size.y - tooltip_size.y - 8

	# 不超出上边界
	if y < 4:
		y = 4

	_panel.position = Vector2(x, y)
	_panel.size = Vector2(TOOLTIP_MAX_WIDTH, 0)
