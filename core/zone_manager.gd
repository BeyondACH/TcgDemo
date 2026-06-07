extends RefCounted
class_name ZoneManager

const UATypes = preload("res://core/ua_types.gd")
const PlayerState = preload("res://data/player_state.gd")
const GameState = preload("res://data/game_state.gd")
const CardInstance = preload("res://data/card_instance.gd")

# 根据区域枚举返回玩家对应的卡牌列表引用，供移动和查询复用。
func get_zone_array(player: PlayerState, zone: int):
	match zone:
		UATypes.Zone.DECK:
			return player.deck
		UATypes.Zone.HAND:
			return player.hand
		UATypes.Zone.LIFE:
			return player.life
		UATypes.Zone.FRONT_LINE:
			return player.front_line
		UATypes.Zone.ENERGY_LINE:
			return player.energy_line
		UATypes.Zone.OUTSIDE:
			return player.outside
		UATypes.Zone.REMOVED:
			return player.removed
	return null

func shuffle_zone(player: PlayerState, zone: int) -> void:
	var zone_array = get_zone_array(player, zone)
	if zone_array != null:
		zone_array.shuffle()

func move_card(state: GameState, card_uid: String, to_zone: int, to_player_id := "", to_position := "") -> void:
	var card: CardInstance = state.get_card(card_uid)
	if card == null:
		return
	var from_zone := card.zone
	_release_stacked_under_if_leaving_field(state, card, to_zone)
	var from_player: PlayerState = state.get_player(card.controller_player_id)
	var target_player_id := card.controller_player_id
	if to_player_id != "":
		target_player_id = to_player_id
	var to_player: PlayerState = state.get_player(target_player_id)
	if from_player == null or to_player == null:
		return
	var from_array = get_zone_array(from_player, card.zone)
	if from_array != null:
		from_array.erase(card_uid)
	var to_array = get_zone_array(to_player, to_zone)
	if to_array != null:
		var normalized_position := str(to_position).to_upper()
		if to_zone == UATypes.Zone.DECK and normalized_position == "TOP":
			to_array.push_front(card_uid)
		else:
			to_array.append(card_uid)
	card.zone = to_zone as UATypes.Zone
	card.controller_player_id = target_player_id
	card.clear_stacked_under_marker()
	if from_zone == UATypes.Zone.LIFE and to_zone == UATypes.Zone.HAND:
		var flags: Dictionary = state.player_turn_flags.get(target_player_id, {})
		flags["life_card_added_to_hand"] = true
		state.player_turn_flags[target_player_id] = flags

func stack_card_on_target(state: GameState, top_card_uid: String, base_card_uid: String, target_zone: int) -> Dictionary:
	var top_card: CardInstance = state.get_card(top_card_uid)
	var base_card: CardInstance = state.get_card(base_card_uid)
	if top_card == null or base_card == null:
		return {"ok": false, "reason": "missing_card"}
	var top_player: PlayerState = state.get_player(top_card.controller_player_id)
	var base_player: PlayerState = state.get_player(base_card.controller_player_id)
	if top_player == null or base_player == null:
		return {"ok": false, "reason": "missing_player"}
	var top_from_array = get_zone_array(top_player, top_card.zone)
	if top_from_array != null:
		top_from_array.erase(top_card_uid)
	var base_from_array = get_zone_array(base_player, base_card.zone)
	var base_zone := base_card.zone
	var base_state := base_card.state
	if base_from_array != null:
		base_from_array.erase(base_card_uid)
	var target_array = get_zone_array(base_player, target_zone)
	if target_array != null:
		target_array.append(top_card_uid)
	top_card.zone = target_zone
	top_card.controller_player_id = base_card.controller_player_id
	top_card.owner_player_id = top_card.owner_player_id
	top_card.clear_stacked_under_marker()
	top_card.state = UATypes.CardState.ACTIVE if base_state == UATypes.CardState.RESTED else base_state
	top_card.stacked_under.append(base_card_uid)
	top_card.stacked_under.append_array(base_card.stacked_under)
	for stacked_uid in top_card.stacked_under:
		var stacked_card: CardInstance = state.get_card(str(stacked_uid))
		if stacked_card != null:
			_prepare_card_for_stacked_under(state, stacked_card, top_card_uid, target_zone, base_card.controller_player_id)
	base_card.stacked_under.clear()
	return {"ok": true, "target_zone": target_zone}

func step_move_to_energy(state: GameState, step_card_uid: String, swap_uid := "") -> Dictionary:
	var step_card: CardInstance = state.get_card(step_card_uid)
	if step_card == null:
		return {"ok": false, "reason": "missing_step_card"}
	var player: PlayerState = state.get_player(step_card.controller_player_id)
	if player == null:
		return {"ok": false, "reason": "missing_player"}
	if player.energy_line.size() < UATypes.MAX_ENERGY_LINE:
		move_card(state, step_card_uid, UATypes.Zone.ENERGY_LINE, step_card.controller_player_id)
		return {"ok": true, "swapped": false}
	if swap_uid == "":
		return {"ok": false, "reason": "step_swap_required"}
	var swap_card: CardInstance = state.get_card(swap_uid)
	if swap_card == null or swap_card.zone != UATypes.Zone.ENERGY_LINE:
		return {"ok": false, "reason": "invalid_step_swap_target"}
	move_card(state, swap_uid, UATypes.Zone.FRONT_LINE, swap_card.controller_player_id)
	move_card(state, step_card_uid, UATypes.Zone.ENERGY_LINE, step_card.controller_player_id)
	return {"ok": true, "swapped": true, "swap_uid": swap_uid}

# 抽牌只负责从牌库移到手牌，不在这里处理抽空牌库导致的败北。
func draw_card(state: GameState, player_id: String) -> String:
	var player: PlayerState = state.get_player(player_id)
	if player == null or player.deck.is_empty():
		return ""
	var card_uid: String = player.deck.pop_front()
	player.hand.append(card_uid)
	var card: CardInstance = state.get_card(card_uid)
	if card != null:
		card.zone = UATypes.Zone.HAND
	return card_uid

func mill_life_to_outside(state: GameState, player_id: String, amount: int) -> Array[String]:
	var moved: Array[String] = []
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return moved
	for i in range(amount):
		if player.life.is_empty():
			break
		var card_uid: String = player.life.pop_front()
		player.outside.append(card_uid)
		var card: CardInstance = state.get_card(card_uid)
		if card != null:
			card.zone = UATypes.Zone.OUTSIDE
		moved.append(card_uid)
	return moved

func add_ap(player: PlayerState, total_slots: int) -> void:
	while player.ap_area.size() < mini(total_slots, UATypes.MAX_AP):
		player.ap_area.append({"index": player.ap_area.size(), "active": true})

func ready_ap(player: PlayerState) -> void:
	for slot in player.ap_area:
		slot["active"] = true

# AP 消耗按顺序横置可用槽位，当前不区分不同来源的 AP。
func spend_ap(player: PlayerState, amount: int) -> bool:
	if player.ap_active_count() < amount:
		return false
	var remaining := amount
	for slot in player.ap_area:
		if remaining <= 0:
			break
		if bool(slot.get("active", false)):
			slot["active"] = false
			remaining -= 1
	return remaining == 0

func ready_field_cards(state: GameState, player_id: String) -> void:
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return
	for card_uid in player.front_line:
		var card: CardInstance = state.get_card(card_uid)
		if card != null:
			if bool(card.flags.get("skip_next_ready_once", false)):
				card.flags["skip_next_ready_once"] = false
			else:
				card.state = UATypes.CardState.ACTIVE
	for card_uid in player.energy_line:
		var card: CardInstance = state.get_card(card_uid)
		if card != null:
			if bool(card.flags.get("skip_next_ready_once", false)):
				card.flags["skip_next_ready_once"] = false
			else:
				card.state = UATypes.CardState.ACTIVE

func reset_turn_flags(state: GameState, player_id: String) -> void:
	var player: PlayerState = state.get_player(player_id)
	if player == null:
		return
	for zone_cards in [player.hand, player.life, player.front_line, player.energy_line, player.outside, player.removed, player.deck]:
		for card_uid in zone_cards:
			var card: CardInstance = state.get_card(card_uid)
			if card != null:
				card.reset_turn_flags()

func _release_stacked_under_if_leaving_field(state: GameState, card: CardInstance, to_zone: int) -> void:
	if card.stacked_under.is_empty():
		return
	var from_field := card.zone == UATypes.Zone.FRONT_LINE or card.zone == UATypes.Zone.ENERGY_LINE
	var to_field := to_zone == UATypes.Zone.FRONT_LINE or to_zone == UATypes.Zone.ENERGY_LINE
	if not from_field or to_field:
		return
	var stacked_copy: Array[String] = card.stacked_under.duplicate()
	card.stacked_under.clear()
	for stacked_uid in stacked_copy:
		move_card(state, stacked_uid, UATypes.Zone.OUTSIDE, card.controller_player_id)

func _prepare_card_for_stacked_under(state: GameState, card: CardInstance, parent_uid: String, target_zone: int, controller_player_id: String) -> void:
	_clear_runtime_bindings_for_card(state, card.uid)
	var card_def = state.get_card_def(card.def_id)
	card.current_bp = card_def.bp if card_def != null else card.current_bp
	card.controller_player_id = controller_player_id
	card.zone = target_zone
	card.state = UATypes.CardState.RESTED
	card.mark_as_stacked_under(parent_uid)

func _clear_runtime_bindings_for_card(state: GameState, card_uid: String) -> void:
	var remaining_modifiers: Array = []
	for modifier_variant in state.static_modifiers:
		var modifier: Dictionary = modifier_variant
		var source_uid := str(modifier.get("source_card_uid", ""))
		var target_uid := str(modifier.get("target_uid", ""))
		if source_uid != card_uid and target_uid != card_uid:
			remaining_modifiers.append(modifier)
			continue
		_revert_static_modifier(state, modifier)
	state.static_modifiers = remaining_modifiers

	var remaining_delayed: Array = []
	for delayed_variant in state.delayed_effects:
		var delayed: Dictionary = delayed_variant
		if str(delayed.get("source_card_uid", "")) == card_uid:
			continue
		remaining_delayed.append(delayed)
	state.delayed_effects = remaining_delayed

func _revert_static_modifier(state: GameState, modifier: Dictionary) -> void:
	var target_uid := str(modifier.get("target_uid", ""))
	if target_uid == "":
		return
	var target_card: CardInstance = state.get_card(target_uid)
	if target_card == null:
		return
	match str(modifier.get("modifier_type", "")):
		"TEMP_BP":
			target_card.current_bp -= int(modifier.get("value", 0))
		"TEMP_KEYWORD":
			target_card.remove_temp_keyword(str(modifier.get("keyword", "")))
