extends Label
class_name PhaseIndicator

func set_phase_text(phase_text: String) -> void:
	text = "Phase: %s" % phase_text
