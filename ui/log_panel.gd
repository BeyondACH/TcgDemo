extends PanelContainer
class_name LogPanel

## P3-3: 日志抽屉 — 右侧滑入/滑出（180ms Tween）、颜色标记、筛选按钮

const SLIDE_DURATION := 0.18

enum LogCategory { ALL, DAMAGE, DRAW, EFFECT, SYSTEM }

var _label: RichTextLabel
var _filter_bar: HFlowContainer
var _all_logs: Array[String] = []
var _current_filter: LogCategory = LogCategory.ALL
var _slide_tween: Tween
var _filter_buttons: Array[Button] = []


func _ready() -> void:
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 4)
	add_child(content)
	_create_filter_bar(content)
	_create_label(content)


func _create_filter_bar(parent: Control) -> void:
	_filter_bar = HFlowContainer.new()
	_filter_bar.name = "FilterBar"
	_filter_bar.add_theme_constant_override("h_separation", 4)
	_filter_bar.add_theme_constant_override("v_separation", 2)
	parent.add_child(_filter_bar)

	var categories := [
		["全部", LogCategory.ALL],
		["伤害", LogCategory.DAMAGE],
		["抽牌", LogCategory.DRAW],
		["效果", LogCategory.EFFECT],
		["系统", LogCategory.SYSTEM],
	]
	for entry in categories:
		var btn := Button.new()
		btn.text = entry[0]
		btn.custom_minimum_size = Vector2(48, 24)
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(_on_filter_pressed.bind(entry[1]))
		_filter_bar.add_child(btn)
		_filter_buttons.append(btn)
	_update_filter_button_styles()


func _create_label(parent: Control) -> void:
	_label = RichTextLabel.new()
	_label.fit_content = false
	_label.scroll_active = true
	_label.bbcode_enabled = true
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(_label)


## ── 公共接口 ──


func set_logs(lines: Array) -> void:
	if _label == null:
		return
	_all_logs = []
	for line in lines:
		_all_logs.append(str(line))
	_render_filtered()


func slide_in() -> void:
	_kill_slide_tween()
	visible = true
	modulate.a = 0.0
	_slide_tween = create_tween()
	_slide_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_slide_tween.tween_property(self, "modulate:a", 1.0, SLIDE_DURATION)


func slide_out() -> void:
	_kill_slide_tween()
	_slide_tween = create_tween()
	_slide_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_slide_tween.tween_property(self, "modulate:a", 0.0, SLIDE_DURATION)
	_slide_tween.tween_callback(func(): visible = false)


## ── 内部方法 ──


func _kill_slide_tween() -> void:
	if _slide_tween and _slide_tween.is_valid():
		_slide_tween.kill()


func _on_filter_pressed(category: LogCategory) -> void:
	_current_filter = category
	_update_filter_button_styles()
	_render_filtered()


func _update_filter_button_styles() -> void:
	for btn in _filter_buttons:
		var is_active := _filter_buttons.find(btn) == _current_filter
		if is_active:
			btn.add_theme_color_override("font_color", Color("#EDF0F5"))
		else:
			btn.add_theme_color_override("font_color", Color("#6B7588"))


func _render_filtered() -> void:
	_label.clear()
	for line in _all_logs:
		if not _line_matches_filter(line):
			continue
		var color := _line_color(line)
		_label.append_text("[color=%s]%s[/color]\n" % [color, line])


func _line_matches_filter(line: String) -> bool:
	match _current_filter:
		LogCategory.ALL:
			return true
		LogCategory.DAMAGE:
			return _is_damage(line)
		LogCategory.DRAW:
			return _is_draw(line)
		LogCategory.EFFECT:
			return _is_effect(line)
		LogCategory.SYSTEM:
			return _is_system(line)
	return true


## ── 颜色分类（关键词匹配） ──


func _is_damage(line: String) -> bool:
	return line.contains("damage") or line.contains("伤害") or line.contains("破坏") or line.contains("退场") or line.contains("败北")


func _is_draw(line: String) -> bool:
	return line.contains("draw") or line.contains("抽牌") or line.contains("抽") or line.contains("手牌") or line.contains("牌库")


func _is_effect(line: String) -> bool:
	return line.contains("effect") or line.contains("效果") or line.contains("触发") or line.contains("登场") or line.contains("激活") or line.contains("RAID") or line.contains("STEP") or line.contains("SNIPER") or line.contains("IMPACT")


func _is_system(line: String) -> bool:
	return not (_is_damage(line) or _is_draw(line) or _is_effect(line))


func _line_color(line: String) -> String:
	if _is_damage(line):
		return "#D95A5A"
	elif _is_draw(line):
		return "#4A90D9"
	elif _is_effect(line):
		return "#D4A843"
	else:
		return "#6B7588"
