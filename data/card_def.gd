extends RefCounted
class_name CardDef

var id = ""
var name = ""
var card_type = UATypes.CardType.CHARACTER
var title_code = ""
var number = ""
var traits = []
var cost_energy = {}
var cost_ap = 0
var energy_provided = {}
var bp = 0
var keywords = []
var effects = []
var trigger_effects = []

static func from_dict(source: Dictionary):
	var result = CardDef.new()
	result.id = str(source.get("id", ""))
	result.name = str(source.get("name", ""))
	result.card_type = _parse_card_type(str(source.get("card_type", "CHARACTER")))
	result.title_code = str(source.get("title_code", ""))
	result.number = str(source.get("number", ""))
	for value in source.get("traits", []):
		result.traits.append(str(value))
	result.cost_energy = source.get("cost_energy", {}).duplicate(true)
	result.cost_ap = int(source.get("cost_ap", 0))
	result.energy_provided = source.get("energy_provided", {}).duplicate(true)
	result.bp = int(source.get("bp", 0))
	for value in source.get("keywords", []):
		result.keywords.append(str(value))
	for value in source.get("effects", []):
		result.effects.append(value.duplicate(true))
	for value in source.get("trigger_effects", []):
		result.trigger_effects.append(value.duplicate(true))
	return result

static func _parse_card_type(value: String) -> int:
	match value:
		"FIELD":
			return UATypes.CardType.FIELD
		"EVENT":
			return UATypes.CardType.EVENT
		_:
			return UATypes.CardType.CHARACTER
