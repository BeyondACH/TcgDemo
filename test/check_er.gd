# Quick check of effect_resolver.gd
extends SceneTree

func _init() -> void:
	print("Attempting to load effect_resolver.gd...")
	var er = load("res://core/effect_resolver.gd")
	print("Result: ", er)
	quit(0)
