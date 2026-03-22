extends SceneTree

func _init() -> void:
	var file := FileAccess.open("user://probe_result.txt", FileAccess.WRITE)
	if file != null:
		file.store_string("probe_ok")
		file.close()
	quit(0)
