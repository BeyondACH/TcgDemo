extends SceneTree

## Trigger font imports and verify theme
func _init() -> void:
	print("Checking font imports ...")
	
	# Try loading fonts with ResourceLoader
	var rl_ok := 0
	var rl_fail := 0
	for path in [
		"res://assets/ui/fonts/NotoSansSC-Regular.ttf",
		"res://assets/ui/fonts/NotoSansSC-SemiBold.ttf",
		"res://assets/ui/fonts/NotoSansSC-Bold.ttf",
		"res://assets/ui/fonts/BarlowCondensed-Regular.ttf",
		"res://assets/ui/fonts/BarlowCondensed-SemiBold.ttf",
		"res://assets/ui/fonts/BarlowCondensed-Bold.ttf",
	]:
		var res = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if res:
			print("  OK: ", path, " -> ", res.get_class())
			rl_ok += 1
		else:
			print("  FAIL: ", path)
			rl_fail += 1
	
	print("Loaded: ", rl_ok, "/", rl_ok + rl_fail)
	
	# Verify theme
	var theme: Theme = load("res://assets/ui/battle_theme.theme")
	if theme:
		print("Theme loaded OK")
		print("  Colors: ", theme.get_color_list("Control").size())
		print("  StyleBoxes: ", theme.get_stylebox_list("Control").size())
		print("  Constants: ", theme.get_constant_list("Control").size())
		# Test a color
		var c = theme.get_color("accent_cyan", "Control")
		print("  accent_cyan: ", c)
	
	quit(0)
