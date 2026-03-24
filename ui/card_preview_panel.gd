extends PanelContainer
class_name CardPreviewPanel

# 卡牌预览面板 - 显示选中/悬停卡牌的详细信息

const CardView = preload("res://ui/card_view.gd")
const PREVIEW_CARD_SIZE := Vector2(140, 196)
const CARD_IMAGE_ASPECT_RATIO := 5.0 / 7.0
const PADDING := 12.0

var _card_image: TextureRect
var _card_name_label: Label
var _cost_label: Label
var _stats_label: Label
var _keywords_label: Label
var _effect_label: Label
var _current_card_data: Dictionary = {}

func _ready() -> void:
	custom_minimum_size = Vector2(220, 360)
	_setup_ui()

func _setup_ui() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", PADDING)
	margin.add_theme_constant_override("margin_top", PADDING)
	margin.add_theme_constant_override("margin_right", PADDING)
	margin.add_theme_constant_override("margin_bottom", PADDING)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# 卡图区域
	_card_image = TextureRect.new()
	_card_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_card_image.custom_minimum_size = PREVIEW_CARD_SIZE
	_card_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_card_image)

	# 卡名
	_card_name_label = Label.new()
	_card_name_label.add_theme_font_size_override("font_size", 14)
	_card_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_card_name_label)

	# 费用信息
	_cost_label = Label.new()
	_cost_label.add_theme_font_size_override("font_size", 12)
	_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_cost_label)

	# BP/类型/状态
	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 11)
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_stats_label)

	# 关键字
	_keywords_label = Label.new()
	_keywords_label.add_theme_font_size_override("font_size", 10)
	_keywords_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_keywords_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_keywords_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	vbox.add_child(_keywords_label)

	# 效果文本
	_effect_label = Label.new()
	_effect_label.add_theme_font_size_override("font_size", 10)
	_effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_effect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_effect_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	vbox.add_child(_effect_label)

func set_card_data(card_data: Dictionary) -> void:
	_current_card_data = card_data.duplicate(true)
	_refresh_display()

func clear_card() -> void:
	_current_card_data = {}
	_refresh_display()

func _refresh_display() -> void:
	if _current_card_data.is_empty():
		_card_image.texture = null
		_card_name_label.text = ""
		_cost_label.text = ""
		_stats_label.text = ""
		_keywords_label.text = ""
		_effect_label.text = ""
		visible = false
		return

	visible = true

	# 设置卡图
	var texture := _resolve_card_texture(_current_card_data)
	if texture != null:
		_card_image.texture = texture
		_card_image.custom_minimum_size = PREVIEW_CARD_SIZE
	else:
		_card_image.texture = null

	# 卡名
	_card_name_label.text = str(_current_card_data.get("name", "Unknown"))

	# 费用信息
	var ap_cost := _format_number(_current_card_data.get("cost_ap", 0))
	var energy_cost := _format_energy_map(_current_card_data.get("cost_energy", {}))
	var energy_give := _format_energy_map(_current_card_data.get("energy_provided", {}))
	_cost_label.text = "AP: %s | Cost: %s | Give: %s" % [ap_cost, energy_cost, energy_give]

	# BP/类型/状态
	var card_type := str(_current_card_data.get("card_type", "?"))
	var bp := int(_current_card_data.get("bp", 0))
	var state := str(_current_card_data.get("state", "ACTIVE"))
	var stats_parts: Array[String] = [card_type]
	if bp > 0:
		stats_parts.append("BP: %d" % bp)
	if state != "ACTIVE":
		stats_parts.append(state)
	_stats_label.text = " | ".join(stats_parts)

	# 关键字
	var keywords: Array = _current_card_data.get("keywords", [])
	if keywords.is_empty():
		_keywords_label.text = ""
	else:
		var kw_text := ", ".join(keywords)
		_keywords_label.text = "[ %s ]" % kw_text

	# 效果文本（简化显示）
	var effects: Array = _current_card_data.get("effects", [])
	var trigger_effects: Array = _current_card_data.get("trigger_effects", [])
	var effect_texts: Array[String] = []
	for effect in effects:
		var text := str(effect.get("description", ""))
		if text != "":
			effect_texts.append(text)
	for trigger in trigger_effects:
		var trigger_type := str(trigger.get("trigger", "?"))
		var text := str(trigger.get("description", ""))
		if text != "":
			effect_texts.append("[%s] %s" % [trigger_type, text])
	_effect_label.text = "\n".join(effect_texts)

func _resolve_card_texture(card_data: Dictionary) -> Texture2D:
	for image_path in _card_image_candidates(card_data):
		if ResourceLoader.exists(image_path):
			var texture := load(image_path)
			if texture is Texture2D:
				return texture
	return null

func _card_image_candidates(card_data: Dictionary) -> Array[String]:
	var candidates: Array[String] = []
	var source_image := str(card_data.get("source_image", "")).strip_edges()
	if source_image != "":
		_append_card_image_candidate(candidates, source_image)
	var number := str(card_data.get("number", "")).strip_edges()
	if number == "":
		return candidates
	var normalized_values := [
		number.replace("/", "-"),
		number.replace("/", "_").replace("-", "_"),
		number.replace("/", "-").replace("_", "-"),
	]
	for value in normalized_values:
		var normalized := str(value).strip_edges()
		if normalized == "":
			continue
		var filename := normalized if normalized.to_lower().ends_with(".png") else "%s.png" % normalized
		_append_card_image_candidate(candidates, filename)
	return candidates

func _append_card_image_candidate(candidates: Array[String], filename: String) -> void:
	var normalized := filename.strip_edges()
	if normalized == "":
		return
	for path in [
		"res://pic/micro/%s" % normalized,
		"res://pic/%s" % normalized,
	]:
		if not candidates.has(path):
			candidates.append(path)

func _format_number(value) -> String:
	if value is int:
		return str(value)
	if value is float:
		var number: float = value
		if is_equal_approx(number, round(number)):
			return str(int(round(number)))
		return str(number)
	return str(value)

func _format_energy_map(energy_map: Dictionary) -> String:
	if energy_map.is_empty():
		return "0"
	var parts: Array[String] = []
	for color in energy_map.keys():
		parts.append("%s:%s" % [str(color), _format_number(energy_map.get(color, 0))])
	parts.sort()
	return ", ".join(parts)