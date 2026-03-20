extends PanelContainer
class_name LogPanel

var _label: RichTextLabel

func _ready() -> void:
	# 直接在代码中创建日志组件，避免原型期频繁改场景树。
	_label = RichTextLabel.new()
	_label.fit_content = false
	_label.scroll_active = true
	_label.bbcode_enabled = false
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_label)

func set_logs(lines: Array) -> void:
	if _label == null:
		return
	_label.clear()
	for line in lines:
		_label.append_text("%s\n" % str(line))
	_label.scroll_to_line(max(0, _label.get_line_count() - 1))
