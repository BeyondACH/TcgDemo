import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RAW_PATH = ROOT / "data" / "cards" / "cards_raw.json"
SEMANTIC_PATH = ROOT / "data" / "cards" / "cards_semantic.json"
LEGACY_SAMPLE_PATH = ROOT / "data" / "cards" / "base_cards.json"
OUT_PATH = ROOT / "data" / "cards" / "cards_effects.json"


def _load_json(path: Path):
    if not path.exists():
        return []
    text = path.read_text(encoding="utf-8-sig").strip()
    if not text:
        return []
    return json.loads(text)


def _infer_keywords(card: dict) -> list[str]:
    keywords = [str(value) for value in card.get("keywords", []) if str(value).strip()]
    for effect in card.get("effects", []):
        text = str(effect.get("text", ""))
        source_label = str(effect.get("source_label", ""))
        if ("ステップ" in source_label or "このキャラはフロントLからエナジーLに移動できる" in text) and "STEP" not in keywords:
            keywords.append("STEP")
        if ("ダメージ2" in source_label or "相手に2ダメージ" in text) and "DAMAGE_2" not in keywords:
            keywords.append("DAMAGE_2")
    raw_effect_text = str(card.get("raw_effect_text", ""))
    raw_trigger_text = str(card.get("raw_trigger_text", ""))
    if ("レイド" in raw_effect_text or "レイド" in raw_trigger_text) and "RAID" not in keywords:
        keywords.append("RAID")
    return keywords


def _build_play_rule(card: dict) -> dict:
    special_modes = []
    special_play_rule = card.get("special_play_rule") or {}
    if special_play_rule:
        mode = dict(special_play_rule)
        mode["type"] = str(mode.get("type", ""))
        if str(mode.get("type", "")) == "RAID" and _has_life_trigger_raid_text(card):
            mode["life_trigger_only"] = True
        special_modes.append(mode)
    return {
        "mode": "NORMAL",
        "special_modes": special_modes,
        "cost_modifiers": _build_play_cost_modifiers(card),
    }


def _build_play_cost_modifiers(card: dict) -> list[dict]:
    modifiers: list[dict] = []
    for effect_entry in card.get("effects", []):
        text = str(effect_entry.get("text", "")).strip()
        match = re.fullmatch(r"自分の場に〈(.+)〉がある場合、手札にあるこのカードの消費APを-1する。", text)
        if not match:
            continue
        modifiers.append(
            {
                "type": "SELF_HAND_AP_DELTA",
                "from_zone": "HAND",
                "ap_delta": -1,
                "requirements": [
                    {
                        "type": "CONTROLLER_HAS_NAME_IN_FIELD",
                        "value": match.group(1),
                    }
                ],
                "ui": {
                    "text": text,
                    "effect_box": str(effect_entry.get("effect_box", "OUTER")),
                },
            }
        )
    return modifiers


def _has_life_trigger_raid_text(card: dict) -> bool:
    for trigger in card.get("trigger_effects", []):
        if str(trigger.get("trigger", "")) != "RAID_RULE":
            continue
        if str(trigger.get("text", "")).strip() == "このカードを手札に加えるか、必要エナジーを満たしている場合、レイドさせる。":
            return True
    return False


def _manual_single_target(
    owner: str,
    zones: list[str],
    requirements: list[dict] | None = None,
    min_count: int = 1,
    max_count: int = 1,
    store_as: str = "selected_target",
) -> tuple[list[dict], list[dict]]:
    target_spec = {
        "id": store_as,
        "scope": "CARD",
        "candidate": {
            "owner": owner,
            "zones": zones,
            "requirements": requirements or [],
        },
        "select": {
            "min": min_count,
            "max": max_count,
            "mode": "MANUAL",
        },
        "store_as": store_as,
    }
    steps = [
        {
            "type": "SELECT_TARGETS",
            "var": store_as,
            "target": {
                "type": "CARD_SET",
                "owner": owner,
                "zones": zones,
                "requirements": requirements or [],
                "min": min_count,
                "max": max_count,
                "selection_mode": "MANUAL",
                "manual": True,
            },
        }
    ]
    return [target_spec], steps


def _manual_context_target(
    source_var: str,
    requirements: list[dict] | None = None,
    filters: list[dict] | None = None,
    min_count: int = 1,
    max_count: int = 1,
    store_as: str = "selected_target",
    constraints: dict | None = None,
) -> tuple[list[dict], list[dict]]:
    target_spec = {
        "id": store_as,
        "scope": "CARD",
        "candidate": {
            "source_var": source_var,
            "filters": filters or [],
            "requirements": requirements or [],
        },
        "select": {
            "min": min_count,
            "max": max_count,
            "mode": "MANUAL",
            "constraints": constraints or {},
        },
        "store_as": store_as,
    }
    steps = [
        {
            "type": "SELECT_TARGETS",
            "var": store_as,
            "target": {
                "type": "CONTEXT_CARD_SET",
                "source_var": source_var,
                "filters": filters or [],
                "requirements": requirements or [],
                "min": min_count,
                "max": max_count,
                "selection_mode": "MANUAL",
                "manual": True,
                "selection_constraints": constraints or {},
            },
        }
    ]
    return [target_spec], steps


def _fixed_value_provider(value: int) -> dict:
    return {"type": "FIXED", "value": value}


def _conditional_value_provider(default_value, when: list[dict], then_value) -> dict:
    return {
        "type": "CONDITIONAL",
        "default": default_value,
        "when": when,
        "then": then_value,
    }


def _normalize_compiled_abilities(compiled_ability) -> list[dict]:
    if compiled_ability is None:
        return []
    if isinstance(compiled_ability, list):
        return compiled_ability
    return [compiled_ability]


def _hand_character_summon_steps(
    energy_lte: int,
    *,
    source_zone: str = "HAND",
    store_as: str = "selected_summon_card",
) -> tuple[list[dict], list[dict]]:
    requirements = [
        {"type": "CARD_TYPE_IS", "value": "CHARACTER"},
        {"type": "CARD_COST_ENERGY_LTE", "value": energy_lte},
        {"type": "CARD_COST_AP_EQ", "value": 1},
        {"type": "CARD_COLOR_IS", "value": "RED"},
        {"type": "CARD_HAS_TRAIT", "value": "魔法少女"},
        {"type": "CARD_CAN_PLAY_TO_ZONE", "zone": "FRONT_LINE", "ignore_play_timing": True},
    ]
    target_specs, steps = _manual_single_target("SELF", [source_zone], requirements, 0, 1, store_as)
    steps.append(
        {
            "type": "PLAY_SELECTED_CARDS",
            "from_var": store_as,
            "to": "FRONT_LINE",
            "state": "RESTED",
            "ignore_play_timing": True,
        }
    )
    return target_specs, steps


def _supported_ability(
    card: dict,
    event_name: str,
    trigger_entry: dict,
    requirements: list[dict],
    target_specs: list[dict],
    steps: list[dict],
    kind: str | None = None,
) -> dict:
    digest = hashlib.sha1(str(trigger_entry.get("text", "")).encode("utf-8")).hexdigest()[:10]
    return {
        "id": f"{card['id']}_{event_name.lower()}_{digest}",
        "kind": kind or ("ACTIVATED" if event_name == "MAIN_ACTIVATE" else "TRIGGERED"),
        "timing": {"event": event_name},
        "requirements": requirements,
        "target_specs": target_specs,
        "steps": steps,
        "limits": {"once_per_turn": event_name == "MAIN_ACTIVATE"},
        "ui": {
            "label": str(trigger_entry.get("source_label", "")),
            "effect_box": str(trigger_entry.get("effect_box", "OUTER")),
            "text": str(trigger_entry.get("text", "")),
        },
        "status": "SUPPORTED",
    }


def _unsupported_ability(card: dict, event_name: str, trigger_entry: dict, reason: str) -> dict:
    digest = hashlib.sha1(str(trigger_entry.get("text", "")).encode("utf-8")).hexdigest()[:10]
    return {
        "id": f"{card['id']}_{event_name.lower()}_{digest}",
        "kind": "ACTIVATED" if event_name == "MAIN_ACTIVATE" else "TRIGGERED",
        "timing": {"event": event_name},
        "requirements": [],
        "target_specs": [],
        "steps": [],
        "limits": {"once_per_turn": event_name == "MAIN_ACTIVATE"},
        "ui": {
            "label": str(trigger_entry.get("source_label", "")),
            "effect_box": str(trigger_entry.get("effect_box", "OUTER")),
            "text": str(trigger_entry.get("text", "")),
        },
        "status": "UNSUPPORTED",
        "unsupported_reason": reason,
    }


def _partial_unsupported_ability(card: dict, event_name: str, trigger_entry: dict, reason: str, suffix: str) -> dict:
    ability = _unsupported_ability(card, event_name, trigger_entry, reason)
    ability["id"] = f"{ability['id']}_{suffix}"
    return ability


def _compile_trigger(card: dict, trigger_entry: dict, semantic_map: dict[str, dict]) -> dict:
    event_name = str(trigger_entry.get("trigger", ""))
    text = str(trigger_entry.get("text", "")).strip()

    if event_name == "RAID_RULE" and text == "このカードを手札に加えるか、必要エナジーを満たしている場合、レイドさせる。":
        var_ability = _supported_ability(
            card,
            "ON_LIFE_TRIGGER",
            trigger_entry,
            [],
            [],
            [{"type": "LIFE_TRIGGER_RAID_CHOICE"}],
        )
        var_ability["ui"]["effect_box"] = "OUTER"
        return var_ability

    if text == "このカードを手札に加える。":
        return _supported_ability(card, event_name, trigger_entry, [], [], [{"type": "MOVE_CARD", "to": "HAND"}])

    if text == "カードを1枚引く。":
        return _supported_ability(card, event_name, trigger_entry, [], [], [{"type": "DRAW", "value": 1}])

    if text == "カードを2枚引く。":
        return _supported_ability(card, event_name, trigger_entry, [], [], [{"type": "DRAW", "value": 2}])

    match = re.fullmatch(r"自分の場に〈(.+)〉がある場合、カードを1枚引く。", text)
    if match:
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [{"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": match.group(1)}],
            [],
            [{"type": "DRAW", "value": 1}],
        )

    match = re.fullmatch(r"BP(\d+)以下の相手のフロントLのキャラを1枚選び、退場させる。", text)
    if match:
        requirements = [{"type": "CARD_BP_LTE", "value": int(match.group(1))}]
        target_specs, steps = _manual_single_target("OPPONENT", ["FRONT_LINE"], requirements)
        steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_target", "to": "OUTSIDE"})
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    if text == "このカード以外の自分の場の［特徴：魔法少女］のカード名の種類の数×1000以下のBPの相手のフロントLのキャラを1枚まで選び、退場させる。":
        target_specs, steps = _manual_single_target(
            "OPPONENT",
            ["FRONT_LINE"],
            [
                {
                    "type": "CARD_BP_LTE_DYNAMIC",
                    "value_provider": {
                        "type": "CONTROLLER_OTHER_FIELD_UNIQUE_NAME_COUNT_MULTIPLIED",
                        "trait": "魔法少女",
                        "multiplier": 1000,
                    },
                }
            ],
            0,
            1,
        )
        steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_target", "to": "OUTSIDE"})
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    if text == "相手のフロントLのキャラを1枚選び、退場させる。":
        target_specs, steps = _manual_single_target("OPPONENT", ["FRONT_LINE"])
        steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_target", "to": "OUTSIDE"})
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    if text == "自分のライフが無い場合、自分の山札の上から1枚を自分のライフエリアに置く。":
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [{"type": "PLAYER_LIFE_IS_EMPTY", "player": "SELF"}],
            [],
            [{"type": "MOVE_TOP_DECK_TO_LIFE"}],
        )

    if text == "カードを1枚引き、自分の手札を1枚場外に置く。":
        target_specs, steps = _manual_single_target("SELF", ["HAND"], [], 1, 1, "discard_from_hand")
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [],
            target_specs,
            [{"type": "DRAW", "value": 1}] + steps + [{"type": "MOVE_SELECTED_CARDS", "from_var": "discard_from_hand", "to": "OUTSIDE"}],
        )

    if text == "自分のAPカードを2枚まで選び、アクティブにする。":
        return _supported_ability(card, event_name, trigger_entry, [], [], [{"type": "ACTIVATE_AP_SLOTS", "value": 2}])

    match = re.fullmatch(r"BP(\d+)以下の相手のフロントLのキャラを1枚まで選び、退場させる。", text)
    if match:
        requirements = [{"type": "CARD_BP_LTE", "value": int(match.group(1))}]
        target_specs, steps = _manual_single_target("OPPONENT", ["FRONT_LINE"], requirements, 0, 1)
        steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_target", "to": "OUTSIDE"})
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    if text == "自分のライフエリアにあるカードを1枚手札に加える。そうした場合、このキャラをアクティブにする。":
        target_specs, steps = _manual_single_target("SELF", ["LIFE"], [], 1, 1, "selected_life_card")
        steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_life_card", "to": "HAND"})
        steps.append({"type": "ACTIVATE_CARD", "target_uid": "SOURCE_CARD"})
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    if text == "自分のライフエリアにあるカードを1枚手札に加える。そうした場合、カードを2枚引く。":
        target_specs, steps = _manual_single_target("SELF", ["LIFE"], [], 1, 1, "selected_life_card")
        steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_life_card", "to": "HAND"})
        steps.append({"type": "DRAW", "value": 2})
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    if text == "自分の手札から必要エナジーが2以下で消費APが1の赤の［特徴：魔法少女］を1枚まで自分の場にレストで登場させる。":
        target_specs, steps = _hand_character_summon_steps(2)
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    if text == "自分の手札から必要エナジーが2以下で消費APが1の赤の［特徴：魔法少女］を1枚まで自分の場にレストで登場させる。自分の場に〈鹿目 まどか〉がある場合、相手のフロントLのキャラを1枚まで選び、次の自分のターン開始時まで、「このキャラはアタックできない。」を与える。":
        target_specs, steps = _hand_character_summon_steps(2)
        cannot_attack_specs, cannot_attack_steps = _manual_single_target(
            "OPPONENT",
            ["FRONT_LINE"],
            [{"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": "鹿目 まどか"}],
            0,
            1,
            "selected_cannot_attack_target",
        )
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [],
            target_specs + cannot_attack_specs,
            steps
            + cannot_attack_steps
            + [
                {
                    "type": "ADD_TEMP_KEYWORD",
                    "target_var": "selected_cannot_attack_target",
                    "keyword": "CANNOT_ATTACK",
                    "expires": "UNTIL_NEXT_SELF_TURN_START",
                }
            ],
        )

    if text == "自分の場の〈鹿目 まどか〉を1枚自分の山札の下に置いてもよい。そうした場合、カードを1枚引き、自分の手札から必要エナジーが4以下で消費APが1の赤の［特徴：魔法少女］を1枚まで自分の場にレストで登場させる。":
        target_specs, steps = _manual_single_target(
            "SELF",
            ["FRONT_LINE", "ENERGY_LINE"],
            [{"type": "CARD_NAME_IS", "value": "鹿目 まどか"}],
            0,
            1,
            "selected_madoka",
        )
        summon_specs, summon_steps = _hand_character_summon_steps(4, store_as="selected_followup_summon")
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [],
            target_specs + summon_specs,
            steps
            + [
                {"type": "MOVE_SELECTED_CARDS", "from_var": "selected_madoka", "to": "DECK"},
                {"type": "SET_CONTEXT_FLAG", "var": "optional_madoka_return_performed", "from_var": "selected_madoka"},
                {"type": "DRAW", "value": 1, "requirements": [{"type": "CONTEXT_FLAG_TRUE", "var": "optional_madoka_return_performed"}]},
            ]
            + [
                dict(step, requirements=[{"type": "CONTEXT_FLAG_TRUE", "var": "optional_madoka_return_performed"}])
                for step in summon_steps
            ],
        )

    if text == "自分の手札を1枚場外に置いてもよい。そうした場合、自分の場外から必要エナジーが3以下で消費APが1の［特徴：魔法少女］を1枚まで手札に加える。":
        discard_specs, discard_steps = _manual_single_target("SELF", ["HAND"], [], 0, 1, "selected_hand_discard")
        search_requirements = [
            {"type": "CARD_COST_ENERGY_LTE", "value": 3},
            {"type": "CARD_COST_AP_EQ", "value": 1},
            {"type": "CARD_HAS_TRAIT", "value": "魔法少女"},
        ]
        search_specs, search_steps = _manual_single_target("SELF", ["OUTSIDE"], search_requirements, 0, 1, "selected_outside_card")
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [],
            discard_specs + search_specs,
            discard_steps
            + [
                {"type": "MOVE_SELECTED_CARDS", "from_var": "selected_hand_discard", "to": "OUTSIDE"},
                {"type": "SET_CONTEXT_FLAG", "var": "optional_hand_discard_performed", "from_var": "selected_hand_discard"},
            ]
            + [
                dict(step, requirements=[{"type": "CONTEXT_FLAG_TRUE", "var": "optional_hand_discard_performed"}])
                for step in search_steps
            ]
            + [
                {
                    "type": "MOVE_SELECTED_CARDS",
                    "from_var": "selected_outside_card",
                    "to": "HAND",
                    "requirements": [{"type": "CONTEXT_FLAG_TRUE", "var": "optional_hand_discard_performed"}],
                }
            ],
        )

    if text == "自分の場のキャラを1枚選び、アクティブにし、このターン中、BP+3000。":
        target_specs, steps = _manual_single_target("SELF", ["FRONT_LINE"], [], 1, 1, "selected_target")
        steps.append({"type": "ACTIVATE_CARD", "target_var": "selected_target"})
        steps.append({"type": "ADD_TEMP_BP_MODIFIER", "target_var": "selected_target", "value": 3000, "expires": "END_OF_TURN"})
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    if text == "自分の場のキャラを1枚まで選び、このターン中、BP+1000。":
        target_specs, steps = _manual_single_target("SELF", ["FRONT_LINE"], [], 0, 1, "selected_target")
        steps.append({"type": "ADD_TEMP_BP_MODIFIER", "target_var": "selected_target", "value": 1000, "expires": "END_OF_TURN"})
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    if text == "自分の場の［特徴：魔法少女］を1枚選び、このターン中、BP+500。":
        requirements = [{"type": "CARD_HAS_TRAIT", "value": "魔法少女"}]
        target_specs, steps = _manual_single_target("SELF", ["FRONT_LINE", "ENERGY_LINE"], requirements, 1, 1, "selected_target")
        steps.append({"type": "ADD_TEMP_BP_MODIFIER", "target_var": "selected_target", "value": 500, "expires": "END_OF_TURN"})
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    if text == "自分の山札の上から4枚見る。その中から〈鹿目 まどか〉以外の［特徴：魔法少女］を1枚まで公開し手札に加える。残りを望む順で自分の山札の下に置く。手札に加えた場合、自分の手札を1枚場外に置く。":
        target_specs, select_steps = _manual_context_target(
            "preview_cards",
            requirements=[{"type": "CARD_HAS_TRAIT", "value": "魔法少女"}],
            filters=[{"type": "NAME_NOT", "value": "鹿目 まどか"}],
            min_count=0,
            max_count=1,
            store_as="selected_preview_cards",
        )
        discard_specs, discard_steps = _manual_single_target("SELF", ["HAND"], [], 1, 1, "selected_discard")
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [],
            target_specs + discard_specs,
            [
                {"type": "PREVIEW_TOP_DECK", "count": 4, "var": "preview_cards"},
            ]
            + select_steps
            + [
                {"type": "MOVE_SELECTED_CARDS", "from_var": "selected_preview_cards", "to": "HAND", "remove_from_var": "preview_cards"},
                {"type": "REORDER_CONTEXT_CARDS", "from_var": "preview_cards", "var": "ordered_preview_cards"},
                {"type": "MOVE_SELECTED_CARDS", "from_var": "ordered_preview_cards", "to": "DECK"},
            ]
            + [
                dict(step, requirements=[{"type": "CONTEXT_VAR_NON_EMPTY", "var": "selected_preview_cards"}])
                for step in discard_steps
            ]
            + [
                {"type": "MOVE_SELECTED_CARDS", "from_var": "selected_discard", "to": "OUTSIDE", "requirements": [{"type": "CONTEXT_VAR_NON_EMPTY", "var": "selected_preview_cards"}]}
            ],
        )

    if text == "必要エナジーが1以下の自分の場の他のキャラを1枚手札に戻す。戻せない場合、このキャラを手札に戻す。":
        target_specs, steps = _manual_single_target(
            "SELF",
            ["FRONT_LINE", "ENERGY_LINE"],
            [
                {"type": "CARD_TYPE_IS", "value": "CHARACTER"},
                {"type": "CARD_COST_ENERGY_LTE", "value": 1},
                {"type": "NOT_SOURCE_CARD"},
            ],
            0,
            1,
            "selected_primary_target",
        )
        steps.extend(
            [
                {"type": "MOVE_SELECTED_CARDS", "from_var": "selected_primary_target", "to": "HAND"},
                {"type": "SET_CONTEXT_FLAG", "var": "primary_target_moved", "from_var": "selected_primary_target"},
                {
                    "type": "MOVE_CARD",
                    "target_uid": "SOURCE_CARD",
                    "to": "HAND",
                    "requirements": [{"type": "CONTEXT_FLAG_FALSE", "var": "primary_target_moved"}],
                },
            ]
        )
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    semantic_entry = semantic_map.get(card["id"])
    if semantic_entry and not semantic_entry.get("can_be_expressed_by_dsl", True):
        reason = " / ".join(semantic_entry.get("missing_capabilities", []))
        return _unsupported_ability(card, event_name, trigger_entry, reason)
    return _unsupported_ability(card, event_name, trigger_entry, "当前原子要求/步骤模板尚未覆盖该文本模式。")


def _compile_event_effect(card: dict, effect_entry: dict, semantic_map: dict[str, dict]) -> dict | None:
    event_name = "ON_PLAY"
    text = str(effect_entry.get("text", "")).strip()
    pseudo_trigger = {
        "trigger": event_name,
        "source_label": effect_entry.get("source_label", ""),
        "effect_box": effect_entry.get("effect_box", "OUTER"),
        "text": text,
    }

    match = re.fullmatch(r"『?BP(\d+)以下』?の相手のフロントLのキャラを1枚選び、退場させる。", text)
    if match:
        requirements = [{"type": "CARD_BP_LTE", "value": int(match.group(1))}]
        target_specs, steps = _manual_single_target("OPPONENT", ["FRONT_LINE"], requirements)
        steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_target", "to": "OUTSIDE"})
        return _supported_ability(card, event_name, pseudo_trigger, [], target_specs, steps, "TRIGGERED")

    if text == "『BP3000以下』の相手のフロントLのキャラを1枚選び、退場させる。自分の場に〈美樹 さやか〉があり、自分のライフが5以下の場合、『BP5000以下』に代わる。":
        target_specs, steps = _manual_single_target(
            "OPPONENT",
            ["FRONT_LINE"],
            [
                {
                    "type": "CARD_BP_LTE_DYNAMIC",
                    "value_provider": _conditional_value_provider(
                        _fixed_value_provider(3000),
                        [
                            {"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": "美樹 さやか"},
                            {"type": "PLAYER_LIFE_LTE", "player": "SELF", "value": 5},
                        ],
                        _fixed_value_provider(5000),
                    ),
                }
            ],
        )
        steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_target", "to": "OUTSIDE"})
        return _supported_ability(card, event_name, pseudo_trigger, [], target_specs, steps, "TRIGGERED")

    if text == "『BP3000以下』の相手のフロントLのキャラを1枚選び、退場させる。自分の場に〈鹿目 まどか〉がある場合、『BP5000以下』に代わる。":
        target_specs, steps = _manual_single_target(
            "OPPONENT",
            ["FRONT_LINE"],
            [
                {
                    "type": "CARD_BP_LTE_DYNAMIC",
                    "value_provider": _conditional_value_provider(
                        _fixed_value_provider(3000),
                        [{"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": "鹿目 まどか"}],
                        _fixed_value_provider(5000),
                    ),
                }
            ],
        )
        steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_target", "to": "OUTSIDE"})
        return _supported_ability(card, event_name, pseudo_trigger, [], target_specs, steps, "TRIGGERED")

    match = re.fullmatch(r"BP(\d+)以下の相手のフロントLのキャラを1枚まで選び、退場させる。", text)
    if match:
        requirements = [{"type": "CARD_BP_LTE", "value": int(match.group(1))}]
        target_specs, steps = _manual_single_target("OPPONENT", ["FRONT_LINE"], requirements, 0, 1)
        steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_target", "to": "OUTSIDE"})
        return _supported_ability(card, event_name, pseudo_trigger, [], target_specs, steps, "TRIGGERED")

    if text == "自分のAPカードを2枚まで選び、アクティブにする。":
        return _supported_ability(card, event_name, pseudo_trigger, [], [], [{"type": "ACTIVATE_AP_SLOTS", "value": 2}], "TRIGGERED")

    if text == "カードを1枚引く。":
        return _supported_ability(card, event_name, pseudo_trigger, [], [], [{"type": "DRAW", "value": 1}], "TRIGGERED")

    if text == "カードを2枚引く。":
        return _supported_ability(card, event_name, pseudo_trigger, [], [], [{"type": "DRAW", "value": 2}], "TRIGGERED")

    if re.fullmatch(r"自分の場に〈(.+)〉がある場合、手札にあるこのカードの消費APを-1する。", text):
        return None

    if text == "自分のライフエリアにあるカードを1枚手札に加える。そうした場合、カードを2枚引く。":
        target_specs, steps = _manual_single_target("SELF", ["LIFE"], [], 1, 1, "selected_life_card")
        steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_life_card", "to": "HAND"})
        steps.append({"type": "DRAW", "value": 2})
        return _supported_ability(card, event_name, pseudo_trigger, [], target_specs, steps, "TRIGGERED")

    if text == "自分の山札の上から5枚見る。その中から異なるカード名の［特徴：魔法少女］をそれぞれ1枚ずつ合計3枚まで公開し手札に加える。残りを望む順で自分の山札の下に置く。":
        target_specs, steps = _manual_context_target(
            "preview_cards",
            requirements=[{"type": "CARD_HAS_TRAIT", "value": "魔法少女"}],
            min_count=0,
            max_count=3,
            store_as="selected_preview_cards",
            constraints={"distinct_by": "CARD_NAME"},
        )
        return _supported_ability(
            card,
            event_name,
            pseudo_trigger,
            [],
            target_specs,
            [
                {"type": "PREVIEW_TOP_DECK", "count": 5, "var": "preview_cards"},
            ]
            + steps
            + [
                {"type": "MOVE_SELECTED_CARDS", "from_var": "selected_preview_cards", "to": "HAND", "remove_from_var": "preview_cards"},
                {"type": "REORDER_CONTEXT_CARDS", "from_var": "preview_cards", "var": "ordered_preview_cards"},
                {"type": "MOVE_SELECTED_CARDS", "from_var": "ordered_preview_cards", "to": "DECK"},
            ],
            "TRIGGERED",
        )

    if text == "自分の山札の上から5枚見る。その中からキャラカードを1枚まで公開し手札に加える。残りを望む順で自分の山札の下に置く。公開したカードがを持つ［特徴：魔法少女］の場合、自分のAPカードを1枚まで選び、アクティブにする。":
        target_specs, select_steps = _manual_context_target(
            "preview_cards",
            requirements=[{"type": "CARD_TYPE_IS", "value": "CHARACTER"}],
            min_count=0,
            max_count=1,
            store_as="revealed_added_card",
        )
        return _supported_ability(
            card,
            event_name,
            pseudo_trigger,
            [],
            target_specs,
            [
                {"type": "PREVIEW_TOP_DECK", "count": 5, "var": "preview_cards"},
            ]
            + select_steps
            + [
                {"type": "MOVE_SELECTED_CARDS", "from_var": "revealed_added_card", "to": "HAND", "remove_from_var": "preview_cards"},
                {"type": "REORDER_CONTEXT_CARDS", "from_var": "preview_cards", "var": "ordered_preview_cards"},
                {"type": "MOVE_SELECTED_CARDS", "from_var": "ordered_preview_cards", "to": "DECK"},
                {
                    "type": "ACTIVATE_AP_SLOTS",
                    "value": 1,
                    "requirements": [
                        {"type": "CONTEXT_SELECTED_CARD_HAS_TRAIT", "context_var": "revealed_added_card", "value": "魔法少女"}
                    ],
                },
            ],
            "TRIGGERED",
        )

    match = re.fullmatch(
        r"自分の場の〈(.+)〉を1枚退場させる。そうした場合、そのキャラのBP以下の相手のフロントLのキャラを1枚まで選び、退場させ、カードを2枚引く。",
        text,
    )
    if match:
        source_name = match.group(1)
        target_specs = [
            {
                "id": "selected_cost_card",
                "scope": "CARD",
                "candidate": {
                    "owner": "SELF",
                    "zones": ["FRONT_LINE", "ENERGY_LINE"],
                    "requirements": [
                        {"type": "CARD_NAME_IS", "value": source_name},
                    ],
                },
                "select": {
                    "min": 1,
                    "max": 1,
                    "mode": "MANUAL",
                },
                "store_as": "selected_cost_card",
            },
            {
                "id": "selected_target",
                "scope": "CARD",
                "candidate": {
                    "owner": "OPPONENT",
                    "zones": ["FRONT_LINE"],
                    "requirements": [
                        {
                            "type": "CARD_BP_LTE_CONTEXT_CARD",
                            "context_var": "selected_cost_card",
                        }
                    ],
                },
                "select": {
                    "min": 0,
                    "max": 1,
                    "mode": "MANUAL",
                },
                "store_as": "selected_target",
            },
        ]
        steps = [
            {
                "type": "MOVE_SELECTED_CARDS",
                "from_var": "selected_target",
                "to": "OUTSIDE",
            },
            {"type": "DRAW", "value": 2},
        ]
        pseudo_trigger = dict(pseudo_trigger)
        pseudo_trigger["costs"] = [
            {
                "type": "MOVE_SELECTED_CARDS",
                "from_var": "selected_cost_card",
                "to": "OUTSIDE",
            }
        ]
        ability = _supported_ability(card, event_name, pseudo_trigger, [], target_specs, steps, "TRIGGERED")
        ability["costs"] = pseudo_trigger["costs"]
        return ability

    semantic_entry = semantic_map.get(card["id"])
    if semantic_entry and not semantic_entry.get("can_be_expressed_by_dsl", True):
        reason = " / ".join(semantic_entry.get("missing_capabilities", []))
        return _unsupported_ability(card, event_name, pseudo_trigger, reason)
    return _unsupported_ability(card, event_name, pseudo_trigger, "当前原子要求/步骤模板尚未覆盖该文本模式。")


def _build_card_effects(card: dict, semantic_map: dict[str, dict]) -> dict:
    keywords = _infer_keywords(card)
    abilities = []
    for trigger_entry in card.get("trigger_effects", []):
        abilities.extend(_normalize_compiled_abilities(_compile_trigger(card, trigger_entry, semantic_map)))
    if str(card.get("card_type", "")) == "EVENT":
        for effect_entry in card.get("effects", []):
            ability = _compile_event_effect(card, effect_entry, semantic_map)
            if ability:
                abilities.append(ability)

    semantic_entry = semantic_map.get(card["id"], {})
    return {
        "id": card["id"],
        "card_meta": {
            "name": card.get("name", ""),
            "card_type": card.get("card_type", "CHARACTER"),
            "title_code": card.get("title_code", ""),
            "number": card.get("number", ""),
            "source_image": card.get("source_image", ""),
            "traits": card.get("traits", []),
            "cost_energy": card.get("cost_energy", {}),
            "cost_ap": card.get("cost_ap", 0),
            "energy_provided": card.get("energy_provided", {}),
            "bp": card.get("bp", 0),
            "keywords": keywords,
            "text": {
                "effect": card.get("raw_effect_text", ""),
                "trigger": card.get("raw_trigger_text", ""),
                "rule": card.get("special_play_rule", {}).get("text", "") if card.get("special_play_rule") else "",
            },
        },
        "play_rule": _build_play_rule(card),
        "abilities": abilities,
        "analysis": {
            "source": "cards_raw.json",
            "semantic_available": card["id"] in semantic_map,
            "semantic_template_types": semantic_entry.get("template_types", []),
        },
    }


def _legacy_to_effects(card: dict) -> dict:
    abilities = []
    for effect in card.get("effects", []):
        abilities.append(
            {
                "id": f"{card['id']}_on_play_{len(abilities)}",
                "kind": "TRIGGERED",
                "timing": {"event": "ON_PLAY"},
                "requirements": [],
                "target_specs": [],
                "steps": [],
                "limits": {},
                "ui": {
                    "label": "",
                    "effect_box": str(effect.get("effect_box", "OUTER")),
                    "text": str(effect.get("text", "")),
                },
                "status": "SUPPORTED",
                "legacy_effect": effect,
            }
        )
    for trigger in card.get("trigger_effects", []):
        abilities.append(
            {
                "id": f"{card['id']}_{str(trigger.get('trigger', 'TRIGGER')).lower()}_{len(abilities)}",
                "kind": "ACTIVATED" if str(trigger.get("trigger", "")) == "MAIN_ACTIVATE" else "TRIGGERED",
                "timing": {"event": str(trigger.get("trigger", ""))},
                "requirements": trigger.get("condition", []),
                "target_specs": [],
                "steps": trigger.get("steps", []),
                "limits": {"once_per_turn": bool(trigger.get("once_per_turn", False))},
                "ui": {
                    "label": "",
                    "effect_box": str(trigger.get("effect_box", "OUTER")),
                    "text": str(trigger.get("text", "")),
                },
                "status": "SUPPORTED",
                "legacy_effect": trigger,
            }
        )
    return {
        "id": card["id"],
        "card_meta": {
            "name": card.get("name", ""),
            "card_type": card.get("card_type", "CHARACTER"),
            "title_code": card.get("title_code", ""),
            "number": card.get("number", ""),
            "source_image": card.get("source_image", ""),
            "traits": card.get("traits", []),
            "cost_energy": card.get("cost_energy", {}),
            "cost_ap": card.get("cost_ap", 0),
            "energy_provided": card.get("energy_provided", {}),
            "bp": card.get("bp", 0),
            "keywords": card.get("keywords", []),
            "text": {
                "effect": card.get("raw_effect_text", ""),
                "trigger": card.get("raw_trigger_text", ""),
                "rule": "",
            },
        },
        "play_rule": {
            "mode": "NORMAL",
            "special_modes": [card.get("special_play_rule", {})] if card.get("special_play_rule") else [],
        },
        "abilities": abilities,
        "analysis": {
            "source": "base_cards.json",
            "semantic_available": False,
            "semantic_template_types": [],
        },
    }


def _infer_template_type(ability: dict) -> str:
    if ability.get("legacy_effect"):
        return "LEGACY_PASSTHROUGH"
    if ability.get("status") != "SUPPORTED":
        return "UNSUPPORTED"
    steps = ability.get("steps", [])
    if not steps:
        return "NO_OP"
    step_types = [str(step.get("type", "")) for step in steps if isinstance(step, dict)]
    if step_types == ["DRAW"]:
        draw_value = int(steps[0].get("value", 1))
        return f"DRAW_{draw_value}"
    if step_types == ["MOVE_CARD"]:
        return "MOVE_SELF"
    if step_types == ["ACTIVATE_AP_SLOTS"]:
        return "READY_AP"
    if step_types == ["LIFE_TRIGGER_RAID_CHOICE"]:
        return "LIFE_TRIGGER_RAID_CHOICE"
    if "ADD_TEMP_BP_MODIFIER" in step_types and "ACTIVATE_CARD" in step_types:
        return "READY_AND_TEMP_BP"
    if "ADD_TEMP_BP_MODIFIER" in step_types:
        return "TEMP_BP"
    if "ADD_TEMP_KEYWORD" in step_types:
        return "TEMP_KEYWORD"
    if "MOVE_SELECTED_CARDS" in step_types and "SELECT_TARGETS" in step_types and "DRAW" in step_types:
        return "DRAW_THEN_SELECT_AND_MOVE"
    if "MOVE_SELECTED_CARDS" in step_types and "SELECT_TARGETS" in step_types and "ACTIVATE_CARD" in step_types:
        return "LIFE_TO_HAND_AND_READY_SOURCE"
    if "MOVE_SELECTED_CARDS" in step_types and "SELECT_TARGETS" in step_types:
        return "SELECT_AND_MOVE"
    if step_types == ["MOVE_TOP_DECK_TO_LIFE"]:
        return "TOP_DECK_TO_LIFE"
    return "COMPOSITE"


def _build_semantic_entry(card_effects: dict) -> dict:
    abilities = []
    missing_capabilities = []
    template_types = []
    for ability in card_effects.get("abilities", []):
        template_type = _infer_template_type(ability)
        abilities.append(
            {
                "id": ability.get("id", ""),
                "timing": ability.get("timing", {}).get("event", ""),
                "status": ability.get("status", "UNSUPPORTED"),
                "text": ability.get("ui", {}).get("text", ""),
                "reason": ability.get("unsupported_reason", ""),
                "template_type": template_type,
            }
        )
        if template_type and template_type not in template_types:
            template_types.append(template_type)
        reason = str(ability.get("unsupported_reason", "")).strip()
        if reason and reason not in missing_capabilities:
            missing_capabilities.append(reason)
    has_raw_text = any(
        str(card_effects.get("card_meta", {}).get("text", {}).get(key, "")).strip() not in {"", "-"}
        for key in ["effect", "trigger", "rule"]
    )
    can_be_expressed = True
    if abilities:
        can_be_expressed = all(entry.get("status") == "SUPPORTED" for entry in abilities)
    elif has_raw_text:
        can_be_expressed = False
        missing_capabilities.append("当前卡牌文本尚未映射为能力对象。")
    return {
        "card_id": card_effects.get("id", ""),
        "source": card_effects.get("analysis", {}).get("source", ""),
        "inferred_keywords": card_effects.get("card_meta", {}).get("keywords", []),
        "template_types": template_types,
        "abilities": abilities,
        "can_be_expressed_by_dsl": can_be_expressed,
        "missing_capabilities": missing_capabilities,
    }


def main() -> None:
    raw_cards = _load_json(RAW_PATH)
    legacy_samples = _load_json(LEGACY_SAMPLE_PATH)

    compiled = [_build_card_effects(card, {}) for card in raw_cards]
    semantic_entries = [_build_semantic_entry(card) for card in compiled]
    semantic_map = {entry.get("card_id", ""): entry for entry in semantic_entries if entry.get("card_id")}

    compiled = [_build_card_effects(card, semantic_map) for card in raw_cards]
    semantic_entries = [_build_semantic_entry(card) for card in compiled]

    existing_ids = {card["id"] for card in compiled}
    for sample in legacy_samples:
        sample_id = sample.get("id", "")
        if sample_id and sample_id not in existing_ids:
            compiled.append(_legacy_to_effects(sample))
    semantic_entries.extend(
        _build_semantic_entry(card) for card in compiled if card.get("analysis", {}).get("source") == "base_cards.json"
    )

    SEMANTIC_PATH.write_text(json.dumps(semantic_entries, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    OUT_PATH.write_text(json.dumps(compiled, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    supported = sum(1 for card in compiled for ability in card["abilities"] if ability.get("status") == "SUPPORTED")
    unsupported = sum(1 for card in compiled for ability in card["abilities"] if ability.get("status") == "UNSUPPORTED")
    print(f"Compiled {len(compiled)} cards -> {OUT_PATH.name}")
    print(f"Supported abilities: {supported}")
    print(f"Unsupported abilities: {unsupported}")


if __name__ == "__main__":
    main()
