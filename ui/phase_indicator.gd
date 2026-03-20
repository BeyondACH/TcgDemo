extends Label
class_name PhaseIndicator

func set_phase_text(phase_text: String) -> void:
	# 阶段文本由外部统一驱动，避免这个组件自己关心对局状态来源。
	text = "Phase: %s" % phase_text
