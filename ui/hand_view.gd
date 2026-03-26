extends Control
class_name HandView

# 手牌视图 - 支持半收起、底部固定、动态重叠
const CardView = preload("res://ui/card_view.gd")

# 布局常量
const DEFAULT_CARD_SIZE := Vector2(100, 140)
const COMPACT_CARD_SIZE := Vector2(88, 124)
const VERY_SMALL_CARD_SIZE := Vector2(72, 100)
const COLLAPSED_VISIBLE_RATIO := 0.6  # 半收起时显示 60%
const MIN_OVERLAP_RATIO := 0.3        # 最小重叠 30%
const MAX_OVERLAP_RATIO := 0.7        # 最大重叠 70%
const ANIMATION_DURATION := 0.15      # 动画时长(秒)
const CARD_SPACING := 4.0             # 卡牌最小间距

signal hand_card_selected(card_uid: String)
signal hand_card_hovered(card_uid: String, is_hovered: bool)

var _card_views: Array[CardView] = []
var _current_player_id := ""
var _hand_cards: Array = []
var _current_card_size := DEFAULT_CARD_SIZE
var _compact_mode := false
var _very_small_mode := false
var _hand_bounds: Rect2 = Rect2(0, 0, 700, 150)
var _playable_cards: Dictionary = {}  # card_uid -> bool

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = false

func set_compact_mode(compact: bool, very_small := false) -> void:
	_compact_mode = compact
	_very_small_mode = very_small
	_update_card_size()
	_recalculate_hand_positions()

func set_hand_bounds(left: float, right: float, width: float) -> void:
	_hand_bounds = Rect2(left, 0, width, 150)
	_recalculate_hand_positions()

func set_hand(player_id: String, hand_cards: Array) -> void:
	_current_player_id = player_id
	_hand_cards = hand_cards.duplicate(true)
	_rebuild_hand()

func set_playable_cards(playable_map: Dictionary) -> void:
	_playable_cards = playable_map.duplicate()
	_update_playable_states()

func _update_card_size() -> void:
	if _very_small_mode:
		_current_card_size = VERY_SMALL_CARD_SIZE
	elif _compact_mode:
		_current_card_size = COMPACT_CARD_SIZE
	else:
		_current_card_size = DEFAULT_CARD_SIZE

func _rebuild_hand() -> void:
	# 清理旧卡牌
	for card in _card_views:
		card.queue_free()
	_card_views.clear()

	# 创建新卡牌
	for card_data in _hand_cards:
		var card := CardView.new()
		card.setup(card_data, _current_player_id, "hand", _current_card_size, CardView.DISPLAY_MODE_HAND)
		card.card_pressed.connect(_on_card_pressed)
		card.card_hovered.connect(_on_card_hovered)
		add_child(card)
		_card_views.append(card)

	# 更新可打出状态
	_update_playable_states()

	# 计算布局
	_recalculate_hand_positions()

func _update_playable_states() -> void:
	for card in _card_views:
		var uid := card.card_uid
		var is_playable: bool = _playable_cards.get(uid, false)
		card.set_playable(is_playable)

func _recalculate_hand_positions() -> void:
	var count := _card_views.size()
	if count == 0:
		return

	_update_card_size()
	var available_width := _hand_bounds.size.x
	var card_width := _current_card_size.x
	var card_height := _current_card_size.y

	# 动态重叠计算
	var overlap := _calculate_overlap(count, card_width, available_width)
	var step := card_width * (1.0 - overlap)

	# 居中
	var total_width := card_width + step * (count - 1)
	var start_x := (_hand_bounds.size.x - total_width) / 2.0

	# 基础 Y 位置（半收起状态）
	var base_y := size.y - card_height * COLLAPSED_VISIBLE_RATIO

	for i in range(count):
		var card := _card_views[i]
		var x := start_x + i * step
		var y := base_y
		var z := i

		# 手牌始终保持统一基线，只在数据或布局变化时重排。
		_animate_card_to(card, x, y, z)

func _calculate_overlap(count: int, card_width: float, available_width: float) -> float:
	if count <= 1:
		return 0.0

	# 计算需要的最小步长
	var min_spacing := CARD_SPACING
	var needed_total := card_width + (card_width + min_spacing) * (count - 1)

	if needed_total <= available_width:
		# 不需要重叠
		return 0.0

	# 需要重叠
	var max_total := available_width - card_width
	var needed_step := max_total / (count - 1)
	var overlap := 1.0 - (needed_step / card_width)

	return clamp(overlap, MIN_OVERLAP_RATIO, MAX_OVERLAP_RATIO)

func _animate_card_to(card: CardView, x: float, y: float, z: int) -> void:
	var target_pos := Vector2(x, y)
	var target_scale := Vector2.ONE

	# 检查是否需要动画
	if card.position.distance_to(target_pos) < 1.0 and card.scale.distance_to(target_scale) < 0.01:
		card.z_index = z
		return

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(card, "position", target_pos, ANIMATION_DURATION)
	tween.tween_property(card, "scale", target_scale, ANIMATION_DURATION)
	card.z_index = z

func _on_card_pressed(_owner_player_id: String, card_uid: String, _zone_name: String) -> void:
	emit_signal("hand_card_selected", card_uid)

func _on_card_hovered(card_uid: String, is_hovered: bool) -> void:
	emit_signal("hand_card_hovered", card_uid, is_hovered)

func get_card_uid_at(index: int) -> String:
	if index < 0 or index >= _card_views.size():
		return ""
	return _card_views[index].card_uid

func get_card_count() -> int:
	return _card_views.size()
