# TDD test for UATypes.key_to_zone() — Phase 0 Task 0.1
extends SceneTree

const UATypes = preload("res://core/ua_types.gd")

func _init() -> void:
	var passed := 0
	var failed := 0

	# Test uppercase inputs
	for tc in [["DECK", UATypes.Zone.DECK], ["HAND", UATypes.Zone.HAND], ["LIFE", UATypes.Zone.LIFE],
			   ["FRONT_LINE", UATypes.Zone.FRONT_LINE], ["ENERGY_LINE", UATypes.Zone.ENERGY_LINE],
			   ["AP_AREA", UATypes.Zone.AP_AREA], ["OUTSIDE", UATypes.Zone.OUTSIDE], ["REMOVED", UATypes.Zone.REMOVED]]:
		var label: String = str(tc[0])
		var expected: int = int(tc[1])
		var result := UATypes.key_to_zone(label)
		if result == expected:
			passed += 1
		else:
			failed += 1
			print("FAIL: key_to_zone('%s') = %d, expected %d" % [label, result, expected])

	# Test lowercase inputs
	for tc in [["deck", UATypes.Zone.DECK], ["hand", UATypes.Zone.HAND], ["life", UATypes.Zone.LIFE],
			   ["front_line", UATypes.Zone.FRONT_LINE], ["energy_line", UATypes.Zone.ENERGY_LINE],
			   ["ap_area", UATypes.Zone.AP_AREA], ["outside", UATypes.Zone.OUTSIDE], ["removed", UATypes.Zone.REMOVED]]:
		var label: String = str(tc[0])
		var expected: int = int(tc[1])
		var result := UATypes.key_to_zone(label)
		if result == expected:
			passed += 1
		else:
			failed += 1
			print("FAIL: key_to_zone('%s') = %d, expected %d" % [label, result, expected])

	# Test integer pass-through
	var int_result := UATypes.key_to_zone(UATypes.Zone.DECK)
	if int_result == UATypes.Zone.DECK:
		passed += 1
	else:
		failed += 1
		print("FAIL: key_to_zone(UATypes.Zone.DECK) = %d" % int_result)

	int_result = UATypes.key_to_zone(UATypes.Zone.FRONT_LINE)
	if int_result == UATypes.Zone.FRONT_LINE:
		passed += 1
	else:
		failed += 1
		print("FAIL: key_to_zone(UATypes.Zone.FRONT_LINE) = %d" % int_result)

	# Test invalid input returns -1
	for invalid in ["INVALID", "", "battlefield", "ZONE_X"]:
		var result := UATypes.key_to_zone(invalid)
		if result == -1:
			passed += 1
		else:
			failed += 1
			print("FAIL: key_to_zone('%s') = %d, expected -1" % [invalid, result])

	var null_result := UATypes.key_to_zone(null)
	if null_result == -1:
		passed += 1
	else:
		failed += 1
		print("FAIL: key_to_zone(null) = %d, expected -1" % null_result)

	print("UATypes.key_to_zone tests: %d passed, %d failed" % [passed, failed])
	quit(failed)
