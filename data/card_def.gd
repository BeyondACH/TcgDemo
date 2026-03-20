extends RefCounted
class_name CardDef

const UATypes = preload("res://core/ua_types.gd")

# 静态卡牌定义，直接映射 JSON 中的卡牌原型数据。
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

func from_dict(source: Dictionary):
	# 这里做一次深拷贝，避免运行期修改效果配置时反向污染原始字典。
	id = str(source.get("id", ""))
	name = str(source.get("name", ""))
	card_type = _parse_card_type(str(source.get("card_type", "CHARACTER")))
	title_code = str(source.get("title_code", ""))
	number = str(source.get("number", ""))
	traits.clear()
	keywords.clear()
	effects.clear()
	trigger_effects.clear()
	for value in source.get("traits", []):
		traits.append(str(value))
	cost_energy = source.get("cost_energy", {}).duplicate(true)
	cost_ap = int(source.get("cost_ap", 0))
	energy_provided = source.get("energy_provided", {}).duplicate(true)
	bp = int(source.get("bp", 0))
	for value in source.get("keywords", []):
		keywords.append(str(value))
	for value in source.get("effects", []):
		effects.append(value.duplicate(true))
	for value in source.get("trigger_effects", []):
		trigger_effects.append(value.duplicate(true))
	return self

static func _parse_card_type(value: String) -> int:
	match value:
		"FIELD":
			return UATypes.CardType.FIELD
		"EVENT":
			return UATypes.CardType.EVENT
		_:
			return UATypes.CardType.CHARACTER
