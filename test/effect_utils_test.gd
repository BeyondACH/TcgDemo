# TDD test for EffectUtils — Phase 1 Task 1.1
extends SceneTree

const EffectUtils = preload("res://core/effects/effect_utils.gd")
const UATypes = preload("res://core/ua_types.gd")

func _init() -> void:
	var passed := 0
	var failed := 0
	
	# --- parse_card_state ---
	for tc in [["ACTIVE", UATypes.CardState.ACTIVE], ["RESTED", UATypes.CardState.RESTED],
			   ["active", UATypes.CardState.ACTIVE], ["rested", UATypes.CardState.RESTED],
			   [UATypes.CardState.ACTIVE, UATypes.CardState.ACTIVE]]:
		if EffectUtils.parse_card_state(tc[0]) == tc[1]:
			passed += 1
		else:
			failed += 1
			print("FAIL parse_card_state(%s)" % tc[0])
	if EffectUtils.parse_card_state("INVALID") == -1: passed += 1
	else: failed += 1; print("FAIL parse_card_state invalid")
	if EffectUtils.parse_card_state(null) == -1: passed += 1
	else: failed += 1; print("FAIL parse_card_state null")

	# --- ensure_array ---
	var arr := [1, 2, 3]
	if EffectUtils.ensure_array(arr) == arr: passed += 1
	else: failed += 1; print("FAIL ensure_array same array")
	if EffectUtils.ensure_array(null) == []: passed += 1
	else: failed += 1; print("FAIL ensure_array null")
	if EffectUtils.ensure_array("") == []: passed += 1
	else: failed += 1; print("FAIL ensure_array empty str")
	if EffectUtils.ensure_array(42) == [42]: passed += 1
	else: failed += 1; print("FAIL ensure_array scalar")
	if EffectUtils.ensure_array("hello") == ["hello"]: passed += 1
	else: failed += 1; print("FAIL ensure_array string")

	# --- array_without_values ---
	var src := [1, 2, 3, 4, 5]
	var rm := [2, 4]
	if EffectUtils.array_without_values(src, rm) == [1, 3, 5]: passed += 1
	else: failed += 1; print("FAIL array_without_values")
	if EffectUtils.array_without_values([], rm) == []: passed += 1
	else: failed += 1; print("FAIL array_without_values empty")

	# --- context_value_is_non_empty ---
	if EffectUtils.context_value_is_non_empty(null) == false: passed += 1
	else: failed += 1; print("FAIL context_value null")
	if EffectUtils.context_value_is_non_empty([]) == false: passed += 1
	else: failed += 1; print("FAIL context_value empty arr")
	if EffectUtils.context_value_is_non_empty([1]) == true: passed += 1
	else: failed += 1; print("FAIL context_value non-empty arr")
	if EffectUtils.context_value_is_non_empty("") == false: passed += 1
	else: failed += 1; print("FAIL context_value empty str")
	if EffectUtils.context_value_is_non_empty("x") == true: passed += 1
	else: failed += 1; print("FAIL context_value non-empty str")

	# --- format_energy_cost_text ---
	if EffectUtils.format_energy_cost_text({}) == "0": passed += 1
	else: failed += 1; print("FAIL energy_cost empty")
	var txt := EffectUtils.format_energy_cost_text({"RED": 2, "GREEN": 1})
	if txt == "RED:2, GREEN:1": passed += 1
	else: failed += 1; print("FAIL energy_cost multi: ", txt)

	# --- format_modifier_expiry_text ---
	if "end of turn" in EffectUtils.format_modifier_expiry_text("END_OF_TURN"): passed += 1
	else: failed += 1; print("FAIL modifier_expiry EOT")
	if "next turn start" in EffectUtils.format_modifier_expiry_text("UNTIL_NEXT_SELF_TURN_START"): passed += 1
	else: failed += 1; print("FAIL modifier_expiry UNTIL")

	# --- resolve_step_target_uid ---
	var ctx := {"current_item": "card_123", "my_var": "card_456"}
	if EffectUtils.resolve_step_target_uid({"target_uid": "explicit"}, ctx, "src") == "explicit": passed += 1
	else: failed += 1; print("FAIL resolve_step explicit")
	if EffectUtils.resolve_step_target_uid({"target_uid": "SOURCE_CARD"}, ctx, "src") == "src": passed += 1
	else: failed += 1; print("FAIL resolve_step SOURCE_CARD")
	if EffectUtils.resolve_step_target_uid({"target_var": "my_var"}, ctx, "src") == "card_456": passed += 1
	else: failed += 1; print("FAIL resolve_step target_var")
	if EffectUtils.resolve_step_target_uid({}, ctx, "src") == "card_123": passed += 1
	else: failed += 1; print("FAIL resolve_step fallback")

	# --- card_energy_cost_total ---
	var mock_def := {"cost_energy": {"RED": 2, "GREEN": 1}}
	if EffectUtils.card_energy_cost_total(mock_def) == 3: passed += 1
	else: failed += 1; print("FAIL energy_cost_total")
	if EffectUtils.card_energy_cost_total(null) == 0: passed += 1
	else: failed += 1; print("FAIL energy_cost_total null")

	# --- card_matches_color ---
	var color_def := {"cost_energy": {"RED": 1}, "energy_provided": {}}
	if EffectUtils.card_matches_color(color_def, "RED") == true: passed += 1
	else: failed += 1; print("FAIL matches RED")
	if EffectUtils.card_matches_color(color_def, "red") == true: passed += 1
	else: failed += 1; print("FAIL matches red lowercase")
	if EffectUtils.card_matches_color(color_def, "BLUE") == false: passed += 1
	else: failed += 1; print("FAIL matches BLUE (should be false)")
	if EffectUtils.card_matches_color(null, "RED") == false: passed += 1
	else: failed += 1; print("FAIL matches null def")

	print("EffectUtils tests: %d passed, %d failed" % [passed, failed])
	quit(failed)
