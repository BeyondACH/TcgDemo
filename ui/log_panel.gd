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
		var idx: int = _filter_buttons.find(btn)
		var is_active := (idx == int(_current_filter))
		if is_active:
			btn.add_theme_color_override("font_color", Color("#EDF0F5"))
		else:
			btn.add_theme_color_override("font_color", Color("#6B7588"))


func _render_filtered() -> void:
	_label.clear()
	for line in _all_logs:
		var cat: LogCategory = _classify_log(line)
		if _current_filter != LogCategory.ALL and cat != _current_filter:
			continue
		var color := _category_color(cat)
		_label.append_text("[color=%s]%s[/color]\n" % [color, line])


## ── 颜色分类（单次关键词扫描，避免重复 contains 调用）──


func _classify_log(line: String) -> LogCategory:
	if _contains_any(line, ["damage", "伤害", "破坏", "退场", "败北"]):
		return LogCategory.DAMAGE
	if _contains_any(line, ["draw", "抽牌", "抽", "手牌", "牌库"]):
		return LogCategory.DRAW
	if _contains_any(line, ["effect", "效果", "触发", "登场", "激活", "RAID", "STEP", "SNIPER", "IMPACT"]):
		return LogCategory.EFFECT
	return LogCategory.SYSTEM


func _contains_any(line: String, keywords: Array) -> bool:
	for kw in keywords:
		if line.contains(kw):
			return true
	return false


func _category_color(cat: LogCategory) -> String:
	match cat:
		LogCategory.DAMAGE: return "#D95A5A"
		LogCategory.DRAW:   return "#4A90D9"
		LogCategory.EFFECT: return "#D4A843"
		_:                  return "#6B7588"
