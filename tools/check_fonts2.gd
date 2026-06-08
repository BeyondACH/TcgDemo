extends SceneTree

func _init() -> void:
	print("Attempting font load via ResourceLoader with type hint ...")
	
	# Try explicit type loading
	for path in [
		"res://assets/ui/fonts/NotoSansSC-Regular.ttf",
	]:
		var res = ResourceLoader.load(path, "FontFile", ResourceLoader.CACHE_MODE_IGNORE)
		if res:
			print("  LOADED: ", path, " -> ", res.get_class())
		else:
			print("  FAILED: ", path)
	
	# Try checking if freetype is available
	print("Checking TextServer features ...")
	var ts = TextServerManager.get_primary_interface()
	print("  TextServer: ", ts.get_name())
	print("  Has feature(shaping): ", ts.has_feature(TextServer.FEATURE_BIDI_LAYOUT))
	
	# Check if there are any existing font resources in the project
	print("Checking for existing font resources...")
	var dir = DirAccess.open("res://")
	if dir:
		_list_fonts(dir, "res://")
	
	quit(0)

func _list_fonts(dir: DirAccess, base: String) -> void:
	dir.list_dir_begin()
	var fn = dir.get_next()
	while fn != "":
		if fn.ends_with(".fontdata") or fn.ends_with(".tres"):
			print("  Found: ", base + fn)
		fn = dir.get_next()
	dir.list_dir_end()
