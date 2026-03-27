extends RefCounted
class_name SimpleAI

const UATypes = preload("res://core/ua_types.gd")
const ActionTypes = preload("res://core/actions/action_types.gd")

const SCORE_NEG_INF := -2147483647

func choose_action(_game_state, snapshot: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary:
	if legal_actions.is_empty():
		return {}
	var phase := str(snapshot.get("phase", ""))
	match phase:
		"DRAW":
			return _choose_draw_action(legal_actions)
		"MOVE":
			return _choose_move_action(snapshot, legal_actions)
		"MAIN":
			return _choose_main_action(snapshot, legal_actions)
		"ATTACK":
			return _choose_attack_action(snapshot, legal_actions)
		"END":
			return _choose_end_action(legal_actions)
	return _fallback_action(legal_actions)

func choose_pending_decision(_game_state, snapshot: Dictionary, pending: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary:
	if legal_actions.is_empty():
		return {}
	if _has_action_type(legal_actions, ActionTypes.RESOLVE_LIFE_TRIGGER):
		return _choose_life_trigger_action(snapshot, pending, legal_actions)
	if pending.has("attacker_uid"):
		return _choose_block_action(snapshot, legal_actions)
	var pending_type := str(pending.get("type", ""))
	match pending_type:
		"MULLIGAN_CHOICE":
			return _find_choice_action(legal_actions, "keep")
		"STEP_SWAP_CHOICE":
			return _choose_step_swap_action(snapshot, pending, legal_actions)
		"HAND_LIMIT_DISCARD":
			return _choose_hand_limit_discard(snapshot, pending, legal_actions)
		"RAID_ZONE_CHOICE":
			return _find_choice_action(legal_actions, UATypes.Zone.FRONT_LINE)
		"LIFE_TRIGGER_RAID_CHOICE":
			return _find_choice_action(legal_actions, "RAID_NOW", _find_choice_action(legal_actions, "ADD_TO_HAND"))
		"LIFE_TRIGGER_RAID_TARGET":
			return legal_actions[0]
		"ABILITY_TARGET_SELECTION":
			return legal_actions[0]
		"TRIGGER_ORDER":
			return legal_actions[0]
	return _fallback_action(legal_actions)

func _choose_draw_action(legal_actions: Array[Dictionary]) -> Dictionary:
	for action in legal_actions:
		if str(action.get("type", "")) == ActionTypes.ADVANCE_PHASE:
			return action
	return _fallback_action(legal_actions)

func _choose_move_action(snapshot: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary:
	var best_action := {}
	var best_score := SCORE_NEG_INF
	for action in legal_actions:
		var action_type := str(action.get("type", ""))
		var score := SCORE_NEG_INF
		if action_type == ActionTypes.MOVE_CARD:
			score = _score_move_action(snapshot, action)
		elif action_type == ActionTypes.ADVANCE_PHASE:
			score = 12
		else:
			continue
		if best_action.is_empty() or score > best_score:
			best_score = score
			best_action = action
	return best_action if not best_action.is_empty() else _fallback_action(legal_actions)

func _choose_main_action(snapshot: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary:
	var best_action := {}
	var best_score := SCORE_NEG_INF
	for action in legal_actions:
		var action_type := str(action.get("type", ""))
		var score := SCORE_NEG_INF
		if action_type == ActionTypes.PLAY_CARD or action_type == ActionTypes.ACTIVATE_EFFECT:
			score = _score_main_action(snapshot, action)
		elif action_type == ActionTypes.ADVANCE_PHASE:
			score = 10
		else:
			continue
		if best_action.is_empty() or score > best_score:
			best_score = score
			best_action = action
	return best_action if not best_action.is_empty() else _fallback_action(legal_actions)

func _choose_attack_action(snapshot: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary:
	var best_action := {}
	var best_score := SCORE_NEG_INF
	for action in legal_actions:
		var action_type := str(action.get("type", ""))
		var score := SCORE_NEG_INF
		if action_type == ActionTypes.ATTACK:
			score = _score_attack_action(snapshot, action)
		elif action_type == ActionTypes.ADVANCE_PHASE:
			score = 16
		else:
			continue
		if best_action.is_empty() or score > best_score:
			best_score = score
			best_action = action
	return best_action if not best_action.is_empty() else _fallback_action(legal_actions)

func _choose_end_action(legal_actions: Array[Dictionary]) -> Dictionary:
	for action in legal_actions:
		if str(action.get("type", "")) == ActionTypes.END_TURN:
			return action
	return _fallback_action(legal_actions)

func _choose_block_action(snapshot: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary:
	var best_action := {}
	var best_score := SCORE_NEG_INF
	for action in legal_actions:
		var action_type := str(action.get("type", ""))
		var score := SCORE_NEG_INF
		if action_type == ActionTypes.BLOCK or action_type == ActionTypes.NO_BLOCK:
			score = _score_block_action(snapshot, action)
		else:
			continue
		if best_action.is_empty() or score > best_score:
			best_score = score
			best_action = action
	return best_action if not best_action.is_empty() else _fallback_action(legal_actions)

func _choose_step_swap_action(snapshot: Dictionary, pending: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary:
	var best_action := {}
	var best_score := SCORE_NEG_INF
	for action in legal_actions:
		if str(action.get("type", "")) != ActionTypes.RESOLVE_PENDING_DECISION:
			continue
		var score := _score_step_swap_choice(snapshot, pending, action)
		if best_action.is_empty() or score > best_score:
			best_score = score
			best_action = action
	return best_action if not best_action.is_empty() else _fallback_action(legal_actions)

func _choose_hand_limit_discard(snapshot: Dictionary, pending: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary:
	var best_action := {}
	var best_score := SCORE_NEG_INF
	for action in legal_actions:
		if str(action.get("type", "")) != ActionTypes.RESOLVE_PENDING_DECISION:
			continue
		var score := _score_hand_limit_discard(snapshot, pending, action)
		if best_action.is_empty() or score > best_score:
			best_score = score
			best_action = action
	return best_action if not best_action.is_empty() else _fallback_action(legal_actions)

func _choose_life_trigger_action(snapshot: Dictionary, pending: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary:
	var activate_action := {}
	var skip_action := {}
	for action in legal_actions:
		if str(action.get("type", "")) != ActionTypes.RESOLVE_LIFE_TRIGGER:
			continue
		if bool(_action_params(action).get("activate", false)):
			activate_action = action
		else:
			skip_action = action
	if activate_action.is_empty():
		return skip_action if not skip_action.is_empty() else _fallback_action(legal_actions)
	var self_player := _get_self_player_snapshot(snapshot)
	var card_uid := str(_action_params(activate_action).get("card_uid", pending.get("card_uid", "")))
	var card_data := _find_card_by_uid(snapshot, card_uid)
	var activation_score := 40
	if not card_data.is_empty():
		activation_score += _card_keep_value(card_data, self_player) / 8
		if _has_any_keyword(card_data, ["RAID", "SNIPER", "DAMAGE_2", "IMPACT", "IMPACT_PLUS_1", "DOUBLE_ATTACK"]):
			activation_score += 40
	if int(self_player.get("life_count", 0)) <= 2:
		activation_score += 20
	if activation_score >= 0:
		return activate_action
	return skip_action if not skip_action.is_empty() else activate_action

func _find_choice_action(legal_actions: Array[Dictionary], wanted_value, fallback_action := {}) -> Dictionary:
	for action in legal_actions:
		if _action_params(action).get("choice", null) == wanted_value:
			return action
	return fallback_action if not fallback_action.is_empty() else _fallback_action(legal_actions)

func _score_move_action(snapshot: Dictionary, action: Dictionary) -> int:
	var params := _action_params(action)
	var self_player := _get_self_player_snapshot(snapshot)
	var opponent_player := _get_opponent_player_snapshot(snapshot)
	var source_card := _find_move_candidate_card(self_player, params)
	var source_bp := int(params.get("source_bp", int(source_card.get("bp", 0))))
	var front_count := _zone_count(self_player, "front_line")
	var energy_count := _zone_count(self_player, "energy_line")
	var energy_total := _energy_total(_available_energy_pool(self_player))
	var score := source_bp / 20
	if not source_card.is_empty():
		score += _card_keep_value(source_card, self_player) / 12
	var mode := str(params.get("mode", ""))
	if mode == ActionTypes.MOVE_ENERGY_TO_FRONT:
		score += 120
		score += max(0, 4 - front_count) * 35
		if front_count < 3:
			score += 60
		if int(opponent_player.get("life_count", 0)) <= 2:
			score += 60
		if _card_energy_total(source_card) > 0 and energy_total <= 2:
			score -= 100
		if _is_important_unit(snapshot, source_card):
			score -= 40
	elif mode == ActionTypes.MOVE_STEP_TO_ENERGY:
		# Approximate strategy: the snapshot does not expose future curve state, so
		# we bias toward retreating low-value cards while protecting key energy pieces.
		score -= 40
		score -= _card_keep_value(source_card, self_player) / 5
		if _card_energy_total(source_card) > 0:
			score += 90
		score += max(0, 3 - energy_total) * 40
		score += max(0, 4 - energy_count) * 10
		if front_count <= 2:
			score -= 60
		if _is_important_unit(snapshot, source_card):
			score -= 120
	return score

func _score_main_action(snapshot: Dictionary, action: Dictionary) -> int:
	var action_type := str(action.get("type", ""))
	var params := _action_params(action)
	var self_player := _get_self_player_snapshot(snapshot)
	var opponent_player := _get_opponent_player_snapshot(snapshot)
	var source_card := {}
	var score := 0
	if action_type == ActionTypes.PLAY_CARD:
		source_card = _find_play_candidate_card(self_player, params)
		score = _score_play_card_action(snapshot, params, source_card)
	elif action_type == ActionTypes.ACTIVATE_EFFECT:
		source_card = _find_main_activate_candidate(self_player)
		score = _score_activate_effect_action(snapshot, params, source_card)
	else:
		return SCORE_NEG_INF
	if not source_card.is_empty():
		score += _card_keep_value(source_card, self_player) / 16
		if _is_important_unit(snapshot, source_card):
			score += 18
		if int(opponent_player.get("life_count", 0)) <= 2 and str(params.get("card_type", "")) == "CHARACTER":
			score += 20
	return score

func _score_attack_action(snapshot: Dictionary, action: Dictionary) -> int:
	var params := _action_params(action)
	var self_player := _get_self_player_snapshot(snapshot)
	var opponent_player := _get_opponent_player_snapshot(snapshot)
	var source_card := _find_attack_candidate(self_player, params)
	var source_bp := int(params.get("source_bp", int(source_card.get("bp", 0))))
	var target_kind := str(params.get("target_kind", "PLAYER"))
	var score := source_bp / 18
	if not source_card.is_empty():
		score += _card_keep_value(source_card, self_player) / 12
	if target_kind == "PLAYER":
		var damage := _estimate_attack_player_damage(source_card, params)
		score += 360
		score += damage * 320
		if int(opponent_player.get("life_count", 0)) <= damage:
			score += 3000
		elif int(opponent_player.get("life_count", 0)) <= 2:
			score += 420
		if _has_keyword(source_card, "DOUBLE_ATTACK"):
			score += 25
	else:
		var target_card := _find_card_by_uid(snapshot, str(params.get("target_uid", "")))
		var target_bp := int(params.get("target_bp", int(target_card.get("bp", 0))))
		var margin := source_bp - target_bp
		score += 40 + margin / 4
		if not target_card.is_empty():
			if str(target_card.get("state", "")) == "ACTIVE":
				score += 80
			if _is_key_blocker(snapshot, target_card):
				score += 220
			elif _is_important_unit(snapshot, target_card):
				score += 120
			if _card_zone_text(target_card) == "front_line" and _zone_count(opponent_player, "front_line") <= 2:
				score += 60
		if margin >= 0:
			score += 80
			if _has_keyword(source_card, "IMPACT"):
				score += 70
			if _has_keyword(source_card, "IMPACT_PLUS_1"):
				score += 90
		else:
			score -= 80
		if _has_keyword(source_card, "SNIPER"):
			score += 40
	return score

func _score_block_action(snapshot: Dictionary, action: Dictionary) -> int:
	var params := _action_params(action)
	var self_player := _get_self_player_snapshot(snapshot)
	var battle_context: Dictionary = snapshot.get("battle_context", {})
	var attacker_uid := str(params.get("attacker_uid", battle_context.get("attacker_uid", "")))
	var blocker_uid := str(params.get("blocker_uid", ""))
	var attacker_card := _find_card_by_uid(snapshot, attacker_uid)
	var blocker_card := _find_card_by_uid(snapshot, blocker_uid)
	var attacker_damage := _estimate_attack_player_damage(attacker_card, params)
	var life_count := int(self_player.get("life_count", 0))
	if str(action.get("type", "")) == ActionTypes.NO_BLOCK:
		var no_block_score := 260 - attacker_damage * 90
		if life_count <= attacker_damage:
			no_block_score -= 5000
		elif life_count <= 2:
			no_block_score -= 100
		if attacker_damage <= 1:
			no_block_score += 120
		if not attacker_card.is_empty():
			no_block_score -= _card_keep_value(attacker_card, _get_opponent_player_snapshot(snapshot)) / 25
		return no_block_score
	var score := attacker_damage * 120 + 40
	if life_count <= attacker_damage:
		score += 5000
	elif life_count <= 2:
		score += 220
	if not blocker_card.is_empty():
		var blocker_keep := _card_keep_value(blocker_card, self_player)
		score -= int(blocker_keep * 1.1)
		if _is_key_blocker(snapshot, blocker_card):
			score -= 200
		elif _is_important_unit(snapshot, blocker_card):
			score -= 140
		if _card_zone_text(blocker_card) == "front_line":
			score += 40
		if int(blocker_card.get("bp", 0)) >= int(attacker_card.get("bp", 0)):
			score += 120
		else:
			score += 20
		if attacker_damage <= 1:
			score -= 120
	if not attacker_card.is_empty():
		if _is_key_blocker(snapshot, attacker_card):
			score += 120
		elif _is_important_unit(snapshot, attacker_card):
			score += 60
		if int(attacker_card.get("bp", 0)) >= 4000:
			score += 40
	return score

func _score_step_swap_choice(snapshot: Dictionary, pending: Dictionary, action: Dictionary) -> int:
	var self_player := _get_self_player_snapshot(snapshot)
	var params := _action_params(action)
	var choice_uid := str(params.get("choice", ""))
	var choice_card := _find_card_by_uid(snapshot, choice_uid)
	var score := 0
	if not choice_card.is_empty():
		var keep_value := _card_keep_value(choice_card, self_player)
		score = -keep_value
		score -= _choice_protection_penalty(snapshot, choice_card)
		if _card_total_cost(choice_card) > _available_energy_total(self_player) + int(self_player.get("ap_active", 0)):
			score += 50
		if _card_zone_text(choice_card) == "energy_line":
			score += 20
		elif _card_zone_text(choice_card) == "front_line":
			score -= 30
		if _has_keyword(choice_card, "STEP") or _has_keyword(choice_card, "RAID"):
			score -= 60
	else:
		score = -int(params.get("choice_bp", 0))
		score -= _choice_protection_penalty(snapshot, choice_card)
	return score

func _score_hand_limit_discard(snapshot: Dictionary, pending: Dictionary, action: Dictionary) -> int:
	var self_player := _get_self_player_snapshot(snapshot)
	var params := _action_params(action)
	var choice_uid := str(params.get("choice", ""))
	var choice_card := _find_card_by_uid(snapshot, choice_uid)
	var score := 0
	if not choice_card.is_empty():
		var keep_value := _card_keep_value(choice_card, self_player)
		score = -keep_value
		score -= _choice_protection_penalty(snapshot, choice_card)
		if _card_zone_text(choice_card) == "hand":
			score += 12
		if _has_keyword(choice_card, "RAID") or _has_keyword(choice_card, "SNIPER"):
			score -= 120
		if _has_keyword(choice_card, "DAMAGE_2") or _has_keyword(choice_card, "IMPACT") or _has_keyword(choice_card, "IMPACT_PLUS_1"):
			score -= 40
		if _card_total_cost(choice_card) > _available_energy_total(self_player) + int(self_player.get("ap_active", 0)):
			score += 80
		if str(choice_card.get("card_type", "")) == "EVENT":
			score += 10
	else:
		score = -int(params.get("choice_bp", 0))
		score -= _choice_protection_penalty(snapshot, choice_card)
	return score

func _score_play_card_action(snapshot: Dictionary, params: Dictionary, card_data: Dictionary) -> int:
	var self_player := _get_self_player_snapshot(snapshot)
	var opponent_player := _get_opponent_player_snapshot(snapshot)
	var card_type := str(params.get("card_type", ""))
	var target_zone := int(params.get("target_zone", -1))
	var special_mode := str(params.get("special_play_mode", ""))
	var source_bp := int(params.get("source_bp", int(card_data.get("bp", 0))))
	var score := source_bp / 20
	if not card_data.is_empty():
		score += _card_keep_value(card_data, self_player) / 12
	if card_type == "CHARACTER":
		score += 90
		if target_zone == UATypes.Zone.FRONT_LINE:
			score += 160
			score += max(0, 4 - _zone_count(self_player, "front_line")) * 35
			if _zone_count(self_player, "front_line") <= 2:
				score += 60
			if int(opponent_player.get("life_count", 0)) <= 2:
				score += 120
			if _has_any_keyword(card_data, ["RAID", "SNIPER", "DAMAGE_2", "IMPACT", "IMPACT_PLUS_1", "DOUBLE_ATTACK"]):
				score += 60
			if special_mode == "RAID":
				# Approximate strategy: the current params do not expose the full raid
				# resolution text, so we reward immediate board pressure and BP gain only.
				score += 220
				score += max(0, source_bp - int(params.get("target_bp", 0))) / 2
			if _card_energy_total(card_data) > 0 and _available_energy_total(self_player) <= 2:
				score -= 80
		elif target_zone == UATypes.Zone.ENERGY_LINE:
			score += 70
			if _card_energy_total(card_data) > 0:
				score += 120
			if _available_energy_total(self_player) <= 2:
				score += 80
			if _zone_count(self_player, "front_line") >= 3:
				score += 20
			if _is_important_unit(snapshot, card_data):
				score += 20
	elif card_type == "FIELD":
		score += 70
		if target_zone == UATypes.Zone.ENERGY_LINE:
			score += 90
		if _card_energy_total(card_data) > 0:
			score += 130
		if _available_energy_total(self_player) <= 2:
			score += 60
		if _is_important_unit(snapshot, card_data):
			score += 40
	elif card_type == "EVENT":
		score += 30
		score += _card_keep_value(card_data, self_player) / 8
		if int(opponent_player.get("life_count", 0)) <= 2:
			score += 40
	else:
		score += 5
	return score

func _score_activate_effect_action(snapshot: Dictionary, _params: Dictionary, card_data: Dictionary) -> int:
	var self_player := _get_self_player_snapshot(snapshot)
	var score := 15
	if not card_data.is_empty():
		score += _card_keep_value(card_data, self_player) / 10
		if _is_important_unit(snapshot, card_data):
			score += 30
		if _is_key_blocker(snapshot, card_data):
			score += 20
	return score

func _estimate_attack_player_damage(card_data: Dictionary, _params: Dictionary = {}) -> int:
	if _has_keyword(card_data, "DAMAGE_2"):
		return 2
	return 1

func _find_play_candidate_card(player_snapshot: Dictionary, params: Dictionary) -> Dictionary:
	var required_action := _project_play_action_name(params)
	var cards := _zone_cards(player_snapshot, "hand")
	var best_card := {}
	var best_score := SCORE_NEG_INF
	for card_variant in cards:
		var card: Dictionary = card_variant
		if not _card_has_action(card, required_action):
			continue
		var score := 0
		if str(card.get("card_type", "")) == str(params.get("card_type", "")):
			score += 50
		if int(card.get("bp", 0)) == int(params.get("source_bp", int(card.get("bp", 0)))):
			score += 20
		if required_action == "RAID" and _has_keyword(card, "RAID"):
			score += 40
		score += _card_keep_value(card, player_snapshot) / 10
		if best_card.is_empty() or score > best_score:
			best_score = score
			best_card = card
	return best_card

func _find_move_candidate_card(player_snapshot: Dictionary, params: Dictionary) -> Dictionary:
	var required_action := _project_move_action_name(params)
	var cards := _zone_cards(player_snapshot, "energy_line" if required_action == "MOVE_TO_FRONT" else "front_line")
	var best_card := {}
	var best_score := SCORE_NEG_INF
	for card_variant in cards:
		var card: Dictionary = card_variant
		if not _card_has_action(card, required_action):
			continue
		var score := 80
		if int(card.get("bp", 0)) == int(params.get("source_bp", int(card.get("bp", 0)))):
			score += 30
		if required_action == "MOVE_TO_FRONT" and _card_energy_total(card) > 0:
			score += 10
		if required_action == "STEP_TO_ENERGY" and _card_energy_total(card) > 0:
			score += 20
		score += _card_keep_value(card, player_snapshot) / 10
		if best_card.is_empty() or score > best_score:
			best_score = score
			best_card = card
	return best_card

func _find_attack_candidate(player_snapshot: Dictionary, params: Dictionary) -> Dictionary:
	var required_action := _project_attack_action_name(params)
	var cards := _zone_cards(player_snapshot, "front_line")
	var best_card := {}
	var best_score := SCORE_NEG_INF
	for card_variant in cards:
		var card: Dictionary = card_variant
		if not _card_has_action(card, required_action):
			continue
		var score := 90
		if int(card.get("bp", 0)) == int(params.get("source_bp", int(card.get("bp", 0)))):
			score += 30
		if required_action == "SNIPER_ATTACK" and _has_keyword(card, "SNIPER"):
			score += 60
		score += _card_keep_value(card, player_snapshot) / 10
		if best_card.is_empty() or score > best_score:
			best_score = score
			best_card = card
	return best_card

func _find_main_activate_candidate(player_snapshot: Dictionary) -> Dictionary:
	var cards := []
	cards.append_array(_zone_cards(player_snapshot, "front_line"))
	cards.append_array(_zone_cards(player_snapshot, "energy_line"))
	var best_card := {}
	var best_score := SCORE_NEG_INF
	for card_variant in cards:
		var card: Dictionary = card_variant
		if not _card_has_action(card, "MAIN_ACTIVATE"):
			continue
		var score := 60 + _card_keep_value(card, player_snapshot) / 12
		if _is_important_unit({}, card):
			score += 20
		if best_card.is_empty() or score > best_score:
			best_score = score
			best_card = card
	return best_card

func _find_card_by_uid(snapshot: Dictionary, card_uid: String) -> Dictionary:
	if card_uid == "":
		return {}
	var players: Dictionary = snapshot.get("players", {})
	if not (players is Dictionary):
		return {}
	for player_id_variant in players.keys():
		var player_id := str(player_id_variant)
		var player_snapshot: Dictionary = players.get(player_id, {})
		var found := _find_card_by_uid_in_player(player_snapshot, card_uid)
		if not found.is_empty():
			return found
	return {}

func _find_card_by_uid_in_player(player_snapshot: Dictionary, card_uid: String) -> Dictionary:
	for zone_key in ["hand", "front_line", "energy_line", "outside", "removed", "life"]:
		for card_variant in _zone_cards(player_snapshot, zone_key):
			var card: Dictionary = card_variant
			if str(card.get("uid", "")) == card_uid:
				return card
	return {}

func _project_play_action_name(params: Dictionary) -> String:
	var special_mode := str(params.get("special_play_mode", ""))
	if special_mode == "RAID":
		return "RAID"
	match int(params.get("target_zone", -1)):
		UATypes.Zone.FRONT_LINE:
			return "PLAY_FRONT"
		UATypes.Zone.ENERGY_LINE:
			return "PLAY_ENERGY"
		UATypes.Zone.OUTSIDE:
			return "PLAY_EVENT"
	return ""

func _project_move_action_name(params: Dictionary) -> String:
	var mode := str(params.get("mode", ""))
	if mode == ActionTypes.MOVE_ENERGY_TO_FRONT:
		return "MOVE_TO_FRONT"
	if mode == ActionTypes.MOVE_STEP_TO_ENERGY:
		return "STEP_TO_ENERGY"
	return ""

func _project_attack_action_name(params: Dictionary) -> String:
	if str(params.get("target_kind", "PLAYER")) == "FRONT_CHARACTER":
		return "SNIPER_ATTACK"
	return "ATTACK_PLAYER"

func _card_has_action(card_data: Dictionary, action_name: String) -> bool:
	if action_name == "":
		return false
	return _array_has_string_value(_normalize_string_array(card_data.get("available_actions", [])), action_name)

func _card_keep_value(card_data: Dictionary, player_snapshot: Dictionary) -> int:
	if card_data.is_empty():
		return 0
	var value := int(card_data.get("bp", 0)) / 100
	var card_type := str(card_data.get("card_type", ""))
	match card_type:
		"CHARACTER":
			value += 120
		"FIELD":
			value += 90
		"EVENT":
			value += 70
		_:
			value += 30
	var zone := _card_zone_text(card_data)
	match zone:
		"front_line":
			value += 90
		"energy_line":
			value += 60
		"hand":
			value += 20
	if _card_energy_total(card_data) > 0:
		value += 80
	if _has_any_keyword(card_data, ["RAID", "SNIPER", "DAMAGE_2", "IMPACT", "IMPACT_PLUS_1", "DOUBLE_ATTACK", "DOUBLE_BLOCK", "STEP", "NEGATE_IMPACT"]):
		value += 45
	value += _card_total_cost(card_data) * 5
	if zone == "hand":
		var total_resources := _available_energy_total(player_snapshot) + int(player_snapshot.get("ap_active", 0))
		if _card_total_cost(card_data) > total_resources:
			value -= 40
	return value

func _choice_protection_penalty(snapshot: Dictionary, card_data: Dictionary) -> int:
	if card_data.is_empty():
		return 0
	var penalty := 0
	if _is_important_unit(snapshot, card_data):
		penalty += 120
	if _is_key_blocker(snapshot, card_data):
		penalty += 60
	if _card_energy_total(card_data) > 0:
		penalty += 40
	if _has_keyword(card_data, "RAID") or _has_keyword(card_data, "SNIPER"):
		penalty += 60
	return penalty

func _is_important_unit(snapshot: Dictionary, card_data: Dictionary) -> bool:
	if card_data.is_empty():
		return false
	var card_type := str(card_data.get("card_type", ""))
	var zone := _card_zone_text(card_data)
	var bp := int(card_data.get("bp", 0))
	if card_type == "FIELD":
		return _card_energy_total(card_data) > 0 or bp >= 1000
	if card_type == "CHARACTER":
		if zone == "front_line" and bp >= 3000:
			return true
		if _has_any_keyword(card_data, ["RAID", "SNIPER", "DAMAGE_2", "IMPACT", "IMPACT_PLUS_1", "DOUBLE_ATTACK", "STEP"]):
			return true
		if _card_energy_total(card_data) > 0:
			return true
	return false

func _is_key_blocker(snapshot: Dictionary, card_data: Dictionary) -> bool:
	if card_data.is_empty():
		return false
	if _card_zone_text(card_data) != "front_line":
		return false
	var opponent := _get_opponent_player_snapshot(snapshot)
	if _zone_count(opponent, "front_line") <= 1:
		return true
	if int(card_data.get("bp", 0)) >= 4000:
		return true
	return _has_any_keyword(card_data, ["SNIPER", "RAID", "DAMAGE_2", "IMPACT", "IMPACT_PLUS_1"])

func _has_keyword(card_data: Dictionary, keyword: String) -> bool:
	return _array_has_string_value(_normalize_string_array(card_data.get("keywords", [])), keyword)

func _has_any_keyword(card_data: Dictionary, keywords: Array[String]) -> bool:
	var normalized := _normalize_string_array(card_data.get("keywords", []))
	for keyword in keywords:
		if normalized.has(keyword):
			return true
	return false

func _card_energy_total(card_data: Dictionary) -> int:
	var energy: Dictionary = card_data.get("energy_provided", {})
	return _dictionary_int_total(energy)

func _card_total_cost(card_data: Dictionary) -> int:
	var total := int(card_data.get("cost_ap", 0))
	total += _dictionary_int_total(card_data.get("cost_energy", {}))
	return total

func _available_energy_pool(player_snapshot: Dictionary) -> Dictionary:
	var pool: Dictionary = player_snapshot.get("available_energy", {})
	if pool is Dictionary:
		return pool
	return {}

func _available_energy_total(player_snapshot: Dictionary) -> int:
	return _energy_total(_available_energy_pool(player_snapshot))

func _energy_total(pool: Dictionary) -> int:
	return _dictionary_int_total(pool)

func _dictionary_int_total(value) -> int:
	if value is Dictionary:
		var total := 0
		for key in value.keys():
			total += int(value.get(key, 0))
		return total
	if value is Array:
		var array_total := 0
		for item in value:
			array_total += int(item)
		return array_total
	return int(value)

func _zone_cards(player_snapshot: Dictionary, zone_key: String) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	var value = player_snapshot.get(zone_key, [])
	if value is Array:
		for item in value:
			if item is Dictionary:
				cards.append(item)
	return cards

func _zone_count(player_snapshot: Dictionary, zone_key: String) -> int:
	return _zone_cards(player_snapshot, zone_key).size()

func _zone_bp_total(player_snapshot: Dictionary, zone_key: String) -> int:
	var total := 0
	for card_variant in _zone_cards(player_snapshot, zone_key):
		var card: Dictionary = card_variant
		total += int(card.get("bp", 0))
	return total

func _get_self_player_id(snapshot: Dictionary) -> String:
	var preferred := str(snapshot.get("priority_player_id", ""))
	if preferred != "":
		return preferred
	preferred = str(snapshot.get("active_player_id", ""))
	if preferred != "":
		return preferred
	var players: Dictionary = snapshot.get("players", {})
	if players is Dictionary and not players.is_empty():
		return str(players.keys()[0])
	return ""

func _get_self_player_snapshot(snapshot: Dictionary) -> Dictionary:
	var player_id := _get_self_player_id(snapshot)
	return _get_player_snapshot(snapshot, player_id)

func _get_opponent_player_snapshot(snapshot: Dictionary) -> Dictionary:
	var self_player_id := _get_self_player_id(snapshot)
	var opponent_player_id := _get_other_player_id(snapshot, self_player_id)
	return _get_player_snapshot(snapshot, opponent_player_id)

func _get_other_player_id(snapshot: Dictionary, player_id: String) -> String:
	var players: Dictionary = snapshot.get("players", {})
	if not (players is Dictionary):
		return ""
	for key_variant in players.keys():
		var key := str(key_variant)
		if key != player_id:
			return key
	return ""

func _get_player_snapshot(snapshot: Dictionary, player_id: String) -> Dictionary:
	if player_id == "":
		return {}
	var players: Dictionary = snapshot.get("players", {})
	if not (players is Dictionary):
		return {}
	var player_variant: Variant = players.get(player_id, {})
	if player_variant is Dictionary:
		return player_variant
	return {}

func _action_type(action: Dictionary) -> String:
	return str(action.get("type", ""))

func _action_params(action: Dictionary) -> Dictionary:
	var params = action.get("params", {})
	if params is Dictionary:
		return params
	return {}

func _has_action_type(legal_actions: Array[Dictionary], action_type: String) -> bool:
	for action in legal_actions:
		if str(action.get("type", "")) == action_type:
			return true
	return false

func _normalize_string_array(value) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(str(item))
	return result

func _array_has_string_value(values: Array[String], wanted: String) -> bool:
	return values.has(wanted)

func _card_zone_text(card_data: Dictionary) -> String:
	return str(card_data.get("zone", ""))

func _fallback_action(legal_actions: Array[Dictionary]) -> Dictionary:
	for type_name in [ActionTypes.NO_BLOCK, ActionTypes.ADVANCE_PHASE, ActionTypes.END_TURN]:
		for action in legal_actions:
			if str(action.get("type", "")) == type_name:
				return action
	return legal_actions[0]
