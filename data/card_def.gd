extends RefCounted
class_name CardDef

const UATypes = preload("res://core/ua_types.gd")

# 静态卡牌定义，直接映射 JSON 中的卡牌原型数据。
var id = ""
var name = ""
var card_type = UATypes.CardType.CHARACTER
var title_code = ""
var number = ""
var source_image = ""
var traits = []
var cost_energy = {}
var cost_ap = 0
var energy_provided = {}
var bp = 0
var keywords = []
var effects = []
var trigger_effects = []
var special_play_rule = {}
var play_rule = {}
var abilities = []
var raw_text = {}

func from_dict(source: Dictionary):
	# 这里做一次深拷贝，避免运行期修改效果配置时反向污染原始字典。
	traits.clear()
	keywords.clear()
	effects.clear()
	trigger_effects.clear()
	special_play_rule.clear()
	play_rule.clear()
	abilities.clear()
	raw_text.clear()
	if source.has("card_meta") or source.has("abilities") or source.has("play_rule"):
		_from_ir_dict(source)
	else:
		_from_legacy_dict(source)
	return self

func _from_legacy_dict(source: Dictionary) -> void:
	id = str(source.get("id", ""))
	name = str(source.get("name", ""))
	card_type = _parse_card_type(str(source.get("card_type", "CHARACTER")))
	title_code = str(source.get("title_code", ""))
	number = str(source.get("number", ""))
	source_image = str(source.get("source_image", ""))
	for value in source.get("traits", []):
		traits.append(str(value))
	cost_energy = _safe_duplicate_dict(source.get("cost_energy", {}))
	cost_ap = int(source.get("cost_ap", 0))
	energy_provided = _safe_duplicate_dict(source.get("energy_provided", {}))
	bp = int(source.get("bp", 0))
	for value in source.get("keywords", []):
		keywords.append(str(value))
	for value in source.get("effects", []):
		effects.append(value.duplicate(true))
	for value in source.get("trigger_effects", []):
		trigger_effects.append(value.duplicate(true))
	special_play_rule = source.get("special_play_rule", {}).duplicate(true)
	raw_text = {
		"effect": str(source.get("raw_effect_text", "")),
		"trigger": str(source.get("raw_trigger_text", "")),
	}
	play_rule = _legacy_play_rule_from_special(special_play_rule)
	abilities = _legacy_abilities_from_source()

func _from_ir_dict(source: Dictionary) -> void:
	var meta: Dictionary = source.get("card_meta", {})
	id = str(source.get("id", meta.get("id", "")))
	name = str(meta.get("name", source.get("name", "")))
	card_type = _parse_card_type(str(meta.get("card_type", source.get("card_type", "CHARACTER"))))
	title_code = str(meta.get("title_code", source.get("title_code", "")))
	number = str(meta.get("number", source.get("number", "")))
	source_image = str(meta.get("source_image", source.get("source_image", "")))
	for value in meta.get("traits", source.get("traits", [])):
		traits.append(str(value))
	cost_energy = _safe_duplicate_dict(meta.get("cost_energy", source.get("cost_energy", {})))
	cost_ap = int(meta.get("cost_ap", source.get("cost_ap", 0)))
	energy_provided = _safe_duplicate_dict(meta.get("energy_provided", source.get("energy_provided", {})))
	bp = int(meta.get("bp", source.get("bp", 0)))
	for value in meta.get("keywords", source.get("keywords", [])):
		keywords.append(str(value))
	raw_text = _safe_duplicate_dict(meta.get("text", source.get("raw_text", {})))
	play_rule = source.get("play_rule", {}).duplicate(true)
	abilities = source.get("abilities", []).duplicate(true)
	special_play_rule = _special_play_rule_from_ir(play_rule)
	for ability_variant in abilities:
		var ability: Dictionary = ability_variant
		var legacy_effect := _legacy_effect_from_ability(ability)
		if legacy_effect.is_empty():
			continue
		var event_name := str(ability.get("timing", {}).get("event", ""))
		if event_name == "ON_PLAY":
			effects.append(legacy_effect)
		else:
			trigger_effects.append(legacy_effect)

func _legacy_abilities_from_source() -> Array:
	var result: Array = []
	for effect_variant in effects:
		var effect: Dictionary = effect_variant
		result.append({
			"id": "%s_on_play_%d" % [id, result.size()],
			"kind": "TRIGGERED",
			"timing": {"event": "ON_PLAY"},
			"requirements": [],
			"target_specs": [],
			"steps": _legacy_steps_from_effect(effect),
			"limits": {},
			"ui": {
				"text": str(effect.get("text", "")),
				"effect_box": str(effect.get("effect_box", "OUTER")),
			},
			"status": "SUPPORTED",
		})
	for effect_variant in trigger_effects:
		var effect: Dictionary = effect_variant
		result.append({
			"id": "%s_%s_%d" % [id, str(effect.get("trigger", "TRIGGER")), result.size()],
			"kind": "ACTIVATED" if str(effect.get("trigger", "")) == "MAIN_ACTIVATE" else "TRIGGERED",
			"timing": {"event": str(effect.get("trigger", ""))},
			"requirements": effect.get("condition", []).duplicate(true),
			"target_specs": [],
			"steps": _legacy_steps_from_effect(effect),
			"limits": {"once_per_turn": bool(effect.get("once_per_turn", false))},
			"ui": {
				"text": str(effect.get("text", "")),
				"effect_box": str(effect.get("effect_box", "OUTER")),
			},
			"status": "SUPPORTED",
		})
	return result

func _legacy_steps_from_effect(effect: Dictionary) -> Array:
	if effect.has("steps"):
		return effect.get("steps", []).duplicate(true)
	var operations = effect.get("operations", effect.get("operation", []))
	if operations is Dictionary:
		return [operations.duplicate(true)]
	var result: Array = []
	for operation_variant in operations:
		result.append(operation_variant.duplicate(true))
	return result

func _legacy_play_rule_from_special(special_rule: Dictionary) -> Dictionary:
	if special_rule.is_empty():
		return {"mode": "NORMAL", "special_modes": []}
	return {
		"mode": "NORMAL",
		"special_modes": [special_rule.duplicate(true)],
	}

func _special_play_rule_from_ir(ir_play_rule: Dictionary) -> Dictionary:
	for mode_variant in ir_play_rule.get("special_modes", []):
		var mode: Dictionary = mode_variant
		if str(mode.get("type", "")) == "RAID":
			return mode.duplicate(true)
	return {}

func matches_reference_name(required_name: String) -> bool:
	if required_name == "":
		return true
	if name == required_name:
		return true
	for alias in _treated_as_names():
		if alias == required_name:
			return true
	return false

func _treated_as_names() -> Array[String]:
	var result: Array[String] = []
	var effect_text := str(raw_text.get("effect", ""))
	if effect_text == "":
		return result
	var regex := RegEx.new()
	var compile_err := regex.compile("〈([^〉]+)〉としても扱う")
	if compile_err != OK:
		return result
	for match in regex.search_all(effect_text):
		var alias := str(match.get_string(1)).strip_edges()
		if alias != "" and not result.has(alias):
			result.append(alias)
	return result

func _legacy_effect_from_ability(ability: Dictionary) -> Dictionary:
	var status := str(ability.get("status", "SUPPORTED"))
	if status != "" and status != "SUPPORTED":
		return {}
	if ability.has("legacy_effect"):
		return ability.get("legacy_effect", {}).duplicate(true)
	return {
		"id": str(ability.get("id", "")),
		"trigger": str(ability.get("timing", {}).get("event", "")),
		"requirements": ability.get("requirements", []).duplicate(true),
		"costs": ability.get("costs", []).duplicate(true),
		"target_specs": ability.get("target_specs", []).duplicate(true),
		"steps": ability.get("steps", []).duplicate(true),
		"once_per_turn": bool(ability.get("limits", {}).get("once_per_turn", false)),
		"text": str(ability.get("ui", {}).get("text", "")),
		"effect_box": str(ability.get("ui", {}).get("effect_box", "OUTER")),
	}

static func _parse_card_type(value: String) -> int:
	match value:
		"FIELD":
			return UATypes.CardType.FIELD
		"EVENT":
			return UATypes.CardType.EVENT
		_:
			return UATypes.CardType.CHARACTER

func _safe_duplicate_dict(value) -> Dictionary:
	if value is Dictionary:
		return value.duplicate(true)
	return {}
