extends RefCounted
class_name AIActionHint

## AI 动作提示动画 — Phase 2 Task 2.3
## 从 battle_scene.gd 提取

const UATypes = preload("res://core/ua_types.gd")
const ActionTypes = preload("res://core/actions/action_types.gd")

const HOLD_SECONDS := 0.8
const FADE_SECONDS := 0.35

var _label: Label
var _scene_node: Node
var _tween: Tween

func _init(scene_node: Node, label: Label) -> void:
	_scene_node = scene_node
	_label = label

func show_action(action_info: Dictionary) -> void:
	var action_text := _format_text(action_info)
	if action_text == "":
		return
	if _tween != null and is_instance_valid(_tween):
		_tween.kill()
	_label.text = action_text
	_label.visible = true
	_label.modulate = Color(1, 1, 1, 1)
	_tween = _scene_node.create_tween()
	_tween.tween_interval(HOLD_SECONDS)
	_tween.tween_property(_label, "modulate:a", 0.0, FADE_SECONDS)
	_tween.finished.connect(_clear, CONNECT_ONE_SHOT)

func _clear() -> void:
	if _label == null:
		return
	_label.text = ""
	_label.visible = false
	_label.modulate = Color(1, 1, 1, 1)
	_tween = null

func _format_text(action_info: Dictionary) -> String:
	var player_text := _format_player(str(action_info.get("player_id", "")))
	var action_type := str(action_info.get("action_type", ""))
	var source_name := str(action_info.get("source_card_name", ""))
	var target_name := str(action_info.get("target_name", ""))
	var phase := str(action_info.get("phase", ""))
	match action_type:
		ActionTypes.ADVANCE_PHASE:
			return "%s 进入 %s 阶段" % [player_text, phase]
		ActionTypes.BONUS_DRAW:
			return "%s 支付 1 AP 额外抽牌" % player_text
		ActionTypes.PLAY_CARD:
			var zone_text := _format_zone(int(action_info.get("target_zone", -1)))
			if source_name != "" and zone_text != "":
				return "%s 打出 %s 到 %s" % [player_text, source_name, zone_text]
			if source_name != "":
				return "%s 打出 %s" % [player_text, source_name]
			return "%s 打出卡牌" % player_text
		ActionTypes.MOVE_CARD:
			var move_mode := str(action_info.get("move_mode", ""))
			if move_mode == ActionTypes.MOVE_ENERGY_TO_FRONT:
				return "%s 让 %s 从能量线前移" % [player_text, source_name if source_name != "" else "角色"]
			if move_mode == ActionTypes.MOVE_STEP_TO_ENERGY:
				return "%s 让 %s 撤步回能量线" % [player_text, source_name if source_name != "" else "角色"]
			return "%s 移动卡牌" % player_text
		ActionTypes.ATTACK:
			if str(action_info.get("target_kind", "PLAYER")) == "CHARACTER":
				return "%s 用 %s 攻击 %s" % [player_text, source_name if source_name != "" else "角色", target_name if target_name != "" else "角色"]
			return "%s 用 %s 攻击玩家" % [player_text, source_name if source_name != "" else "角色"]
		ActionTypes.BLOCK:
			return "%s 用 %s 进行阻挡" % [player_text, str(action_info.get("blocker_name", "")) if str(action_info.get("blocker_name", "")) != "" else "角色"]
		ActionTypes.NO_BLOCK:
			return "%s 选择不阻挡" % player_text
		ActionTypes.RESOLVE_PENDING_DECISION:
			return "%s 处理 %s" % [player_text, _format_decision(str(action_info.get("decision_type", "")))]
		ActionTypes.RESOLVE_LIFE_TRIGGER:
			var life_name := target_name if target_name != "" else source_name
			if bool(action_info.get("activate", false)):
				return "%s 发动生命触发 %s" % [player_text, "：" + life_name if life_name != "" else ""]
			return "%s 跳过生命触发 %s" % [player_text, "：" + life_name if life_name != "" else ""]
		ActionTypes.END_TURN:
			return "%s 结束当前回合" % player_text
	return ""

func _format_player(player_id: String) -> String:
	if player_id == UATypes.PLAYER_ONE:
		return "玩家 1（AI）"
	if player_id == UATypes.PLAYER_TWO:
		return "玩家 2（AI）"
	return "%s（AI）" % player_id

func _format_zone(target_zone: int) -> String:
	if target_zone == UATypes.Zone.FRONT_LINE:
		return "前线"
	if target_zone == UATypes.Zone.ENERGY_LINE:
		return "能量线"
	return ""

func _format_decision(decision_type: String) -> String:
	match decision_type:
		"MULLIGAN_CHOICE":
			return "起手换牌决策"
		"RAID_ZONE_CHOICE":
			return "RAID 落点选择"
		"LIFE_TRIGGER_RAID_CHOICE":
			return "生命触发 RAID 选择"
		"LIFE_TRIGGER_RAID_TARGET":
			return "生命触发 RAID 目标选择"
		"STEP_SWAP_CHOICE":
			return "STEP 交换选择"
		"HAND_LIMIT_DISCARD":
			return "手牌上限弃牌"
		"ABILITY_TARGET_SELECTION":
			return "能力目标选择"
	return "待决策"
