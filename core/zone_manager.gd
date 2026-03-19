extends RefCounted
class_name ZoneManager

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

func move_card(state: GameState, card_uid: String, to_zone: int, to_player_id := "") -> void:
	var card: CardInstance = state.get_card(card_uid)
	if card == null:
		return
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
		to_array.append(card_uid)
	card.zone = to_zone as UATypes.Zone
	card.controller_player_id = target_player_id

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
			card.state = UATypes.CardState.ACTIVE
	for card_uid in player.energy_line:
		var card: CardInstance = state.get_card(card_uid)
		if card != null:
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
