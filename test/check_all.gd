# Check all core modules
extends SceneTree

func _init() -> void:
	var ok := 0
	var err := 0
	
	var modules := [
		"res://core/ua_types.gd",
		"res://data/card_def.gd",
		"res://data/card_instance.gd",
		"res://data/game_state.gd",
		"res://data/player_state.gd",
		"res://core/effects/requirement_matcher.gd",
		"res://core/effects/target_selector.gd",
		"res://core/effects/step_executor.gd",
		"res://core/effects/life_damage_handler.gd",
		"res://core/zone_manager.gd",
		"res://core/victory_checker.gd",
		"res://core/player_utils.gd",
		"res://core/rules_engine.gd",
		"res://core/effect_resolver.gd",
		"res://core/battle_resolver.gd",
		"res://core/turn_manager.gd",
		"res://core/decision_manager.gd",
		"res://core/life_trigger_manager.gd",
		"res://core/game_manager.gd",
	]
	
	for path in modules:
		var res = load(path)
		if res:
			print("OK: ", path.get_file())
			ok += 1
		else:
			print("FAIL: ", path.get_file())
			err += 1
	
	print("\nResult: %d OK, %d FAIL" % [ok, err])
	quit(err)
