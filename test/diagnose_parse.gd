# Diagnose parse errors in core modules
extends SceneTree

func _init() -> void:
	var failed := 0
	
	# Test 1: Core types
	const UATypes = preload("res://core/ua_types.gd")
	print("OK: UATypes loaded")
	
	# Test 2: Data classes
	const CardInstance = preload("res://data/card_instance.gd")
	print("OK: CardInstance loaded")
	const CardDef = preload("res://data/card_def.gd")
	print("OK: CardDef loaded")
	const GameState = preload("res://data/game_state.gd")
	print("OK: GameState loaded")
	const PlayerState = preload("res://data/player_state.gd")
	print("OK: PlayerState loaded")
	const CardCatalog = preload("res://data/card_catalog.gd")
	print("OK: CardCatalog loaded")
	
	# Test 3: Core managers
	const ZoneManager = preload("res://core/zone_manager.gd")
	print("OK: ZoneManager loaded")
	const VictoryChecker = preload("res://core/victory_checker.gd")
	print("OK: VictoryChecker loaded")
	const PlayerUtils = preload("res://core/player_utils.gd")
	print("OK: PlayerUtils loaded")
	const RulesEngine = preload("res://core/rules_engine.gd")
	print("OK: RulesEngine loaded")
	const ActionTypes = preload("res://core/actions/action_types.gd")
	print("OK: ActionTypes loaded")
	
	# Test 4: Effect submodules
	const RequirementMatcher = preload("res://core/effects/requirement_matcher.gd")
	print("OK: RequirementMatcher loaded")
	const TargetSelector = preload("res://core/effects/target_selector.gd")
	print("OK: TargetSelector loaded")
	const StepExecutor = preload("res://core/effects/step_executor.gd")
	print("OK: StepExecutor loaded")
	const LifeDamageHandler = preload("res://core/effects/life_damage_handler.gd")
	print("OK: LifeDamageHandler loaded")
	
	# Test 5: EffectResolver
	const EffectResolver = preload("res://core/effect_resolver.gd")
	print("OK: EffectResolver loaded")
	
	# Test 6: BattleResolver
	const BattleResolver = preload("res://core/battle_resolver.gd")
	print("OK: BattleResolver loaded")
	
	# Test 7: TurnManager
	const TurnManager = preload("res://core/turn_manager.gd")
	print("OK: TurnManager loaded")
	const DecisionManager = preload("res://core/decision_manager.gd")
	print("OK: DecisionManager loaded")
	const ControllerManager = preload("res://core/controllers/controller_manager.gd")
	print("OK: ControllerManager loaded")
	
	# Test 8: LifeTriggerManager
	const LifeTriggerManager = preload("res://core/life_trigger_manager.gd")
	print("OK: LifeTriggerManager loaded")
	
	# Test 9: GameManager
	const GameManager = preload("res://core/game_manager.gd")
	print("OK: GameManager loaded")
	
	# Test 10: Smoke tests
	const milestone = preload("res://test/milestone_smoke_test.gd")
	print("OK: milestone_smoke_test loaded")
	const duel = preload("res://test/cards_raw_minimal_duel_smoke_test.gd")
	print("OK: duel_smoke_test loaded")
	const residue = preload("res://test/runtime_residue_smoke_test.gd")
	print("OK: residue_smoke_test loaded")
	
	print("\nALL OK - %d modules loaded" % 14)
	quit(0)
