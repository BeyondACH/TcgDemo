extends PanelContainer
class_name CardPreviewPanel

# 卡牌预览面板，优先展示完整原图；仅在原图缺失时回退到文字详情。
const PREVIEW_CARD_SIZE := Vector2(440, 616)
const PADDING := 12.0

var _card_image: TextureRect
var _details_box: VBoxContainer
var _card_name_label: Label
var _cost_label: Label
var _stats_label: Label
var _temp_status_label: Label
var _keywords_label: Label
var _effect_label: Label
var _current_card_data: Dictionary = {}

func _ready() -> void:
	custom_minimum_size = Vector2(
		PREVIEW_CARD_SIZE.x + PADDING * 2.0,
		PREVIEW_CARD_SIZE.y + PADDING * 2.0
	)
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

	_card_image = TextureRect.new()
	_card_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_card_image.custom_minimum_size = PREVIEW_CARD_SIZE
	_card_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_card_image)

	_details_box = VBoxContainer.new()
	_details_box.add_theme_constant_override("separation", 6)
	vbox.add_child(_details_box)

	_card_name_label = Label.new()
	_card_name_label.add_theme_font_size_override("font_size", 14)
	_card_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_details_box.add_child(_card_name_label)

	_cost_label = Label.new()
	_cost_label.add_theme_font_size_override("font_size", 12)
	_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_details_box.add_child(_cost_label)

	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 11)
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_details_box.add_child(_stats_label)

	_temp_status_label = Label.new()
	_temp_status_label.add_theme_font_size_override("font_size", 10)
	_temp_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_temp_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_temp_status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	_details_box.add_child(_temp_status_label)

	_keywords_label = Label.new()
	_keywords_label.add_theme_font_size_override("font_size", 10)
	_keywords_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_keywords_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_keywords_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	_details_box.add_child(_keywords_label)

	_effect_label = Label.new()
	_effect_label.add_theme_font_size_override("font_size", 10)
	_effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_effect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_effect_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_details_box.add_child(_effect_label)

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
		_temp_status_label.text = ""
		_keywords_label.text = ""
		_effect_label.text = ""
		_details_box.visible = false
		visible = false
		return

	visible = true

	var texture := _resolve_card_texture(_current_card_data, true)
	if texture != null:
		_card_image.texture = texture
		_card_image.custom_minimum_size = PREVIEW_CARD_SIZE
		_details_box.visible = true
		_card_name_label.visible = true
		_stats_label.visible = true
		_temp_status_label.visible = true
		_cost_label.visible = false
		_keywords_label.visible = false
		_effect_label.visible = false
	else:
		_card_image.texture = null
		_details_box.visible = true
		_card_name_label.visible = true
		_stats_label.visible = true
		_temp_status_label.visible = true
		_cost_label.visible = true
		_keywords_label.visible = true
		_effect_label.visible = true

	_card_name_label.text = str(_current_card_data.get("name", "Unknown"))

	var ap_cost := _format_number(_current_card_data.get("cost_ap", 0))
	var energy_cost := _format_energy_map(_current_card_data.get("cost_energy", {}))
	var energy_give := _format_energy_map(_current_card_data.get("energy_provided", {}))
	_cost_label.text = "AP: %s | Cost: %s | Give: %s" % [ap_cost, energy_cost, energy_give]

	var card_type := str(_current_card_data.get("card_type", "?"))
	var bp := int(_current_card_data.get("bp", 0))
	var base_bp := int(_current_card_data.get("base_bp", bp))
	var state := str(_current_card_data.get("state", "ACTIVE"))
	var stats_parts: Array[String] = [card_type]
	if bp > 0:
		stats_parts.append("BP: %d" % bp)
	if state != "ACTIVE":
		stats_parts.append(state)
	_stats_label.text = " | ".join(stats_parts)
	_temp_status_label.text = _build_temp_status_text(state, bp, base_bp, _current_card_data.get("flags", {}))

	var keywords: Array = _current_card_data.get("keywords", [])
	if keywords.is_empty():
		_keywords_label.text = ""
	else:
		var kw_text := ", ".join(keywords)
		_keywords_label.text = "[ %s ]" % kw_text

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

func _resolve_card_texture(card_data: Dictionary, prefer_original: bool = false) -> Texture2D:
	for image_path in _card_image_candidates(card_data, prefer_original):
		if ResourceLoader.exists(image_path):
			var texture := load(image_path)
			if texture is Texture2D:
				return texture
	return null

func _card_image_candidates(card_data: Dictionary, prefer_original: bool = false) -> Array[String]:
	var candidates: Array[String] = []
	var source_image := str(card_data.get("source_image", "")).strip_edges()
	if source_image != "":
		_append_card_image_candidate(candidates, source_image, prefer_original)
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
		_append_card_image_candidate(candidates, filename, prefer_original)
	return candidates

func _append_card_image_candidate(candidates: Array[String], filename: String, prefer_original: bool = false) -> void:
	var normalized := filename.strip_edges()
	if normalized == "":
		return
	var ordered_paths := [
		"res://pic/%s" % normalized,
		"res://pic/micro/%s" % normalized,
	] if prefer_original else [
		"res://pic/micro/%s" % normalized,
		"res://pic/%s" % normalized,
	]
	for path in ordered_paths:
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

func _build_temp_status_text(state: String, current_bp: int, base_bp: int, flags: Dictionary) -> String:
	var parts: Array[String] = []
	parts.append("状态: %s" % ("REST" if state == "RESTED" else state))

	if base_bp > 0:
		var delta := current_bp - base_bp
		if delta > 0:
			parts.append("BP %+d (%d -> %d)" % [delta, base_bp, current_bp])
		elif delta < 0:
			parts.append("BP %d (%d -> %d)" % [delta, base_bp, current_bp])
		else:
			parts.append("BP 无变化 (%d)" % current_bp)
	elif current_bp > 0:
		parts.append("当前 BP: %d" % current_bp)

	var temp_keywords: Array = flags.get("temp_keywords", [])
	if not temp_keywords.is_empty():
		parts.append("临时关键词: %s" % ", ".join(temp_keywords))

	if bool(flags.get("entered_via_raid", false)):
		parts.append("本回合通过 RAID 登场")

	return "\n".join(parts)
