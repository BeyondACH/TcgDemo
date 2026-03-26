extends RefCounted
class_name ActionFactory

const ActionTypes = preload("res://core/actions/action_types.gd")

static func make_action(
	action_id: String,
	action_type: String,
	player_id: String,
	label: String,
	params: Dictionary = {},
	source_card_uid := "",
	priority_hint := 0
) -> Dictionary:
	return {
		"id": action_id,
		"type": action_type,
		"player_id": player_id,
		"label": label,
		"params": params.duplicate(true),
		"source_card_uid": source_card_uid,
		"priority_hint": priority_hint,
	}

static func make_phase_action(player_id: String, phase_text: String) -> Dictionary:
	return make_action(
		"advance_phase:%s:%s" % [player_id, phase_text.to_lower()],
		ActionTypes.ADVANCE_PHASE,
		player_id,
		"Advance to next phase",
		{"phase": phase_text},
		"",
		-100
	)

static func make_end_turn_action(player_id: String) -> Dictionary:
	return make_action(
		"end_turn:%s" % player_id,
		ActionTypes.END_TURN,
		player_id,
		"End turn",
		{},
		"",
		-100
	)
