import re

path = 'ui/battle_scene.gd'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

def replace(old, new, label):
    global content
    assert old in content, f'{label} not found!'
    content = content.replace(old, new)
    print(f'  OK: {label}')

# === 1. Add preload imports ===
replace(
    'const BoardTargetSelectionHelper = preload("res://ui/board_target_selection_helper.gd")',
    'const BoardTargetSelectionHelper = preload("res://ui/board_target_selection_helper.gd")\nconst AIActionHint = preload("res://ui/ai_action_hint.gd")\nconst DeckSelector = preload("res://ui/deck_selector.gd")',
    'preload imports')

# === 2. Remove AI constants ===
replace(
    'const AI_ACTION_HINT_HOLD_SECONDS := 0.8\nconst AI_ACTION_HINT_FADE_SECONDS := 0.35\n',
    '', 'AI constants')

# === 3. Replace AI var ===
replace('var _ai_action_hint_tween: Tween', 'var _ai_action_hint: AIActionHint', 'AI var')

# === 4. Replace deck vars ===
replace(
    'var _available_decks: Array[Dictionary] = []\nvar _opening_setup_pending := true',
    'var _deck_selector: DeckSelector\nvar _opening_setup_pending := true', 'deck vars')

# === 5. Add init in _ready() ===
replace(
    '\t_setup_optional_art()\n\t_load_deck_selection_options()',
    '\t_setup_optional_art()\n\t_ai_action_hint = AIActionHint.new(self, ai_action_label)\n\t_deck_selector = DeckSelector.new(game_manager, player_one_deck_picker, player_two_deck_picker, deck_selection_modal, start_game_button)\n\t_load_deck_selection_options()',
    'ready init')

# === 6. Remove _clear_ai_action_hint() call ===
replace('\t_clear_ai_action_hint()\n\t_on_state_changed', '\t_on_state_changed', 'clear_ai_hint call')

# === 7. Replace _on_ai_action_executed ===
replace(
    'func _on_ai_action_executed(action_info: Dictionary) -> void:\n'
    '\tvar action_text := _format_ai_action_text(action_info)\n'
    '\tif action_text == "":\n'
    '\t\treturn\n'
    '\tif _ai_action_hint_tween != null and is_instance_valid(_ai_action_hint_tween):\n'
    '\t\t_ai_action_hint_tween.kill()\n'
    '\tai_action_label.text = action_text\n'
    '\tai_action_label.visible = true\n'
    '\tai_action_label.modulate = Color(1, 1, 1, 1)\n'
    '\t_ai_action_hint_tween = create_tween()\n'
    '\t_ai_action_hint_tween.tween_interval(AI_ACTION_HINT_HOLD_SECONDS)\n'
    '\t_ai_action_hint_tween.tween_property(ai_action_label, "modulate:a", 0.0, AI_ACTION_HINT_FADE_SECONDS)\n'
    '\t_ai_action_hint_tween.finished.connect(_clear_ai_action_hint, CONNECT_ONE_SHOT)',
    'func _on_ai_action_executed(action_info: Dictionary) -> void:\n'
    '\t_ai_action_hint.show_action(action_info)',
    'on_ai_action_executed')

# === 8. Remove _clear_ai_action_hint ===
replace(
    '\nfunc _clear_ai_action_hint() -> void:\n'
    '\tif ai_action_label == null:\n'
    '\t\treturn\n'
    '\tai_action_label.text = ""\n'
    '\tai_action_label.visible = false\n'
    '\tai_action_label.modulate = Color(1, 1, 1, 1)\n'
    '\t_ai_action_hint_tween = null',
    '', '_clear_ai_action_hint')

# === 9. Remove _format_ai_action_text ===
old = ('\n\nfunc _format_ai_action_text(action_info: Dictionary) -> String:\n'
    '\tvar player_text := _format_ai_player_text(str(action_info.get("player_id", "")))\n'
    '\tvar action_type := str(action_info.get("action_type", ""))\n'
    '\tvar source_name := str(action_info.get("source_card_name", ""))\n'
    '\tvar target_name := str(action_info.get("target_name", ""))\n'
    '\tvar phase := str(action_info.get("phase", ""))\n'
    '\tmatch action_type:\n'
    '\t\tActionTypes.ADVANCE_PHASE:\n'
    '\t\t\treturn "%s进入 %s 阶段" % [player_text, phase]\n'
    '\t\tActionTypes.BONUS_DRAW:\n'
    '\t\t\treturn "%s支付 1 AP 额外抽牌" % player_text\n'
    '\t\tActionTypes.PLAY_CARD:\n'
    '\t\t\tvar zone_text := _format_target_zone_text(int(action_info.get("target_zone", -1)))\n'
    '\t\t\tif source_name != "" and zone_text != "":\n'
    '\t\t\t\treturn "%s打出 %s 到%s" % [player_text, source_name, zone_text]\n'
    '\t\t\tif source_name != "":\n'
    '\t\t\t\treturn "%s打出 %s" % [player_text, source_name]\n'
    '\t\t\treturn "%s打出卡牌" % player_text\n'
    '\t\tActionTypes.MOVE_CARD:\n'
    '\t\t\tvar move_mode := str(action_info.get("move_mode", ""))\n'
    '\t\t\tif move_mode == ActionTypes.MOVE_ENERGY_TO_FRONT:\n'
    '\t\t\t\treturn "%s让 %s 从能量线前移" % [player_text, source_name if source_name != "" else "角色"]\n'
    '\t\t\tif move_mode == ActionTypes.MOVE_STEP_TO_ENERGY:\n'
    '\t\t\t\treturn "%s让 %s 撤步回能量线" % [player_text, source_name if source_name != "" else "角色"]\n'
    '\t\t\treturn "%s移动卡牌" % player_text\n'
    '\t\tActionTypes.ATTACK:\n'
    '\t\t\tif str(action_info.get("target_kind", "PLAYER")) == "CHARACTER":\n'
    '\t\t\t\treturn "%s用 %s 攻击 %s" % [player_text, source_name if source_name != "" else "角色", target_name if target_name != "" else "角色"]\n'
    '\t\t\treturn "%s用 %s 攻击玩家" % [player_text, source_name if source_name != "" else "角色"]\n'
    '\t\tActionTypes.BLOCK:\n'
    '\t\t\treturn "%s用 %s 进行阻挡" % [player_text, str(action_info.get("blocker_name", "")) if str(action_info.get("blocker_name", "")) != "" else "角色"]\n'
    '\t\tActionTypes.NO_BLOCK:\n'
    '\t\t\treturn "%s选择不阻挡" % player_text\n'
    '\t\tActionTypes.RESOLVE_PENDING_DECISION:\n'
    '\t\t\treturn "%s处理%s" % [player_text, _format_pending_decision_text(str(action_info.get("decision_type", "")))]\n'
    '\t\tActionTypes.RESOLVE_LIFE_TRIGGER:\n'
    '\t\t\tvar life_name := target_name if target_name != "" else source_name\n'
    '\t\t\tif bool(action_info.get("activate", false)):\n'
    '\t\t\t\treturn "%s发动生命触发%s" % [player_text, "：%s" % life_name if life_name != "" else ""]\n'
    '\t\t\treturn "%s跳过生命触发%s" % [player_text, "：%s" % life_name if life_name != "" else ""]\n'
    '\t\tActionTypes.END_TURN:\n'
    '\t\t\treturn "%s结束当前回合" % player_text\n'
    '\treturn ""')
assert old in content, '_format_ai_action_text not found!'
content = content.replace(old, '')
print('  OK: _format_ai_action_text')

# === 10. Remove remaining AI helpers ===
for label, func_name in [('_format_ai_player_text', '_format_ai_player_text'),
                           ('_format_target_zone_text', '_format_target_zone_text'),
                           ('_format_pending_decision_text', '_format_pending_decision_text')]:
    pattern = r'\n\nfunc ' + re.escape(func_name) + r'\([^)]*\)[^:]*:.*?(?=\n\nfunc |\n$|\Z)'
    m = re.search(pattern, content, re.DOTALL)
    if m:
        content = content.replace(m.group(), '')
        print(f'  OK: {label}')
    else:
        print(f'  WARN: {label} not found')

# === 11. Replace deck functions ===
replace(
    'func _load_deck_selection_options() -> void:\n'
    '\t_available_decks = game_manager.get_available_decks()\n'
    '\tplayer_one_deck_picker.clear()\n'
    '\tplayer_two_deck_picker.clear()\n'
    '\tfor deck in _available_decks:\n'
    '\t\tvar deck_name := str(deck.get("name", ""))\n'
    '\t\tplayer_one_deck_picker.add_item(deck_name)\n'
    '\t\tplayer_two_deck_picker.add_item(deck_name)\n'
    '\tif _available_decks.is_empty():\n'
    '\t\tdeck_selection_status_label.text = "未在 data/decks 中找到可用的 txt 卡组。"\n'
    '\t\tstart_game_button.disabled = true\n'
    '\t\treturn\n'
    '\tplayer_one_deck_picker.select(_preferred_deck_index("starter_a", 0))\n'
    '\tplayer_two_deck_picker.select(_preferred_deck_index("starter_b", min(1, _available_decks.size() - 1)))\n'
    '\tstart_game_button.disabled = false\n'
    '\tdeck_selection_status_label.text = "请选择双方卡组后开始对局。"',
    'func _load_deck_selection_options() -> void:\n\t_deck_selector.load_options()',
    '_load_deck_selection_options')

replace(
    '\nfunc _preferred_deck_index(preferred_name: String, fallback_index: int) -> int:\n'
    '\tfor i in range(_available_decks.size()):\n'
    '\t\tif str(_available_decks[i].get("file_name", "")).get_basename() == preferred_name:\n'
    '\t\t\treturn i\n'
    '\treturn clampi(fallback_index, 0, max(0, _available_decks.size() - 1))',
    '', '_preferred_deck_index')

replace(
    'func _show_deck_selection_modal() -> void:\n'
    '\t_opening_setup_pending = true\n'
    '\t_refresh_deck_selection_modal_state()\n'
    '\tdeck_selection_modal.visible = true',
    'func _show_deck_selection_modal() -> void:\n\t_deck_selector.show_modal()',
    '_show_deck_selection_modal')

replace(
    'func _hide_deck_selection_modal() -> void:\n'
    '\tdeck_selection_modal.visible = false',
    'func _hide_deck_selection_modal() -> void:\n\t_deck_selector.hide_modal()',
    '_hide_deck_selection_modal')

replace(
    'func _refresh_deck_selection_modal_state() -> void:\n'
    '\tvar can_start := _opening_setup_pending and not _available_decks.is_empty() and player_one_deck_picker.selected >= 0 and player_two_deck_picker.selected >= 0\n'
    '\tplayer_one_deck_picker.disabled = not _opening_setup_pending or _available_decks.is_empty()\n'
    '\tplayer_two_deck_picker.disabled = not _opening_setup_pending or _available_decks.is_empty()\n'
    '\tstart_game_button.disabled = not can_start\n'
    '\tif not _opening_setup_pending:\n'
    '\t\t_hide_deck_selection_modal()\n'
    '\telif _available_decks.is_empty():\n'
    '\t\tdeck_selection_status_label.text = "未在 data/decks 中找到可用的 txt 卡组。"\n'
    '\telse:\n'
    '\t\tdeck_selection_status_label.text = "请选择双方卡组后开始对局。"',
    'func _refresh_deck_selection_modal_state() -> void:\n\t_deck_selector.refresh_state()',
    '_refresh_deck_selection_modal_state')

replace(
    'func _selected_deck_path(picker: OptionButton) -> String:\n'
    '\tvar index := picker.selected\n'
    '\tif index < 0 or index >= _available_decks.size():\n'
    '\t\treturn ""\n'
    '\treturn str(_available_decks[index].get("path", ""))',
    'func _selected_deck_path(picker: OptionButton) -> String:\n\treturn _deck_selector._deck_path(picker)',
    '_selected_deck_path')

replace(
    'func _start_game_with_selected_decks() -> void:\n'
    '\tvar path_p1 := _selected_deck_path(player_one_deck_picker)\n'
    '\tvar path_p2 := _selected_deck_path(player_two_deck_picker)\n'
    '\tif path_p1 == "" or path_p2 == "":\n'
    '\t\treturn\n'
    '\t_opening_setup_pending = false\n'
    '\tgame_manager.setup_game(path_p1, path_p2)',
    'func _start_game_with_selected_decks() -> void:\n\t_deck_selector.start_game()',
    '_start_game_with_selected_decks')

# === 12. Update remaining _available_decks / _opening_setup_pending refs ===
content = content.replace('_available_decks.is_empty()', '_deck_selector.available_decks.is_empty()')
content = content.replace('not _available_decks.is_empty()', 'not _deck_selector.available_decks.is_empty()')
content = content.replace('_opening_setup_pending', '_deck_selector.opening_setup_pending')

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

lines = len(content.splitlines())
print(f'\nDone. 1376 -> {lines} lines (-{1376 - lines})')
