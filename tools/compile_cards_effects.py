import hashlib
import json
import re
import sys
from copy import deepcopy
from dataclasses import dataclass
from pathlib import Path

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.card_effects_compiler.normalization import normalize_japanese_text as normalize_compiler_text
from tools.card_effects_compiler.semantic_ir import build_semantic_entry as build_semantic_ir_entry
from tools.card_effects_compiler.template_registry import _dispatch_template_rules
from tools.card_effects_compiler.template_registry import _exact_text_match
from tools.card_effects_compiler.template_registry import _regex_match
from tools.card_effects_compiler.template_registry import dispatch_template_rules
from tools.card_effects_compiler.template_registry import set_trigger_template_rules


ROOT = Path(__file__).resolve().parents[1]
CARDS_DIR = ROOT / "data" / "cards"
LEGACY_SAMPLE_PATH = ROOT / "data" / "cards" / "base_cards.json"
SEMANTIC_OVERRIDE_REQUIRED = "SEMANTIC_OVERRIDE_REQUIRED"


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
        "requirements": _build_play_requirements(card),
        "enter_state": _build_enter_state(card),
    }


def _build_play_requirements(card: dict) -> list[dict]:
    requirements: list[dict] = []
    for effect_entry in card.get("effects", []):
        text = str(effect_entry.get("text", "")).strip()
        if text == "このカードは自分の場に〈鹿目 まどか〉か〈アルティメットまどか〉がある場合のみ使用できる。":
            requirements.append(
                {
                    "type": "OR",
                    "requirements": [
                        {"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": "鹿目 まどか"},
                        {"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": "アルティメットまどか"},
                    ],
                }
            )
        match = re.fullmatch(r"このカードは自分のフロントLに〈(.+)〉がある場合のみ使用できる。", text)
        if match:
            requirements.append({"type": "CONTROLLER_HAS_NAME_IN_FRONT_LINE", "value": match.group(1)})
        match = re.fullmatch(r"このカードは自分の場に〈(.+)〉がある場合のみ使用できる。", text)
        if match:
            requirements.append({"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": match.group(1)})
        match = re.fullmatch(r"〈(.+)〉は1ターンに1枚のみ使用できる。", text)
        if match:
            requirements.append(
                {
                    "type": "NOT",
                    "requirement": {
                        "type": "PLAYER_TURN_FLAG_TRUE",
                        "player": "SELF",
                        "flag": _event_used_turn_flag(match.group(1)),
                    },
                }
            )
    return requirements


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
        continue
    for effect_entry in card.get("effects", []):
        text = str(effect_entry.get("text", "")).strip()
        match = re.fullmatch(r"〈(.+)〉を選んで使用する場合、このカードの消費APを-1する。", text)
        if not match:
            continue
        modifiers.append(
            {
                "type": "SELF_HAND_AP_DELTA",
                "from_zone": "HAND",
                "ap_delta": -1,
                "requirements": [
                    {
                        "type": "CONTEXT_TARGET_NAME_IS",
                        "value": match.group(1),
                    }
                ],
                "ui": {
                    "text": text,
                    "effect_box": str(effect_entry.get("effect_box", "OUTER")),
                },
            }
        )
    for effect_entry in card.get("effects", []):
        text = str(effect_entry.get("text", "")).strip()
        match = re.fullmatch(r"自分の場にカード名に「(.+)」を含むキャラがある場合、手札にあるこのカードの消費APを-1する。", text)
        if not match:
            continue
        modifiers.append(
            {
                "type": "SELF_HAND_AP_DELTA",
                "from_zone": "HAND",
                "ap_delta": -1,
                "requirements": [
                    {
                        "type": "CONTROLLER_HAS_NAME_CONTAINS_IN_FIELD",
                        "value": match.group(1),
                    }
                ],
                "ui": {
                    "text": text,
                    "effect_box": str(effect_entry.get("effect_box", "OUTER")),
                },
            }
        )
    for effect_entry in card.get("effects", []):
        text = str(effect_entry.get("text", "")).strip()
        if text != "相手の場に黄か紫のカードがある場合、手札にあるこのカードの必要エナジーを減らす。":
            continue
        energy_delta = _parse_energy_delta_from_label(str(effect_entry.get("source_label", "")))
        if not energy_delta:
            continue
        modifiers.append(
            {
                "type": "SELF_HAND_ENERGY_DELTA",
                "from_zone": "HAND",
                "energy_delta": energy_delta,
                "requirements": [
                    {
                        "type": "PLAYER_HAS_COLOR_IN_FIELD",
                        "player": "OPPONENT",
                        "colors": ["YELLOW", "PURPLE"],
                    }
                ],
                "ui": {
                    "text": text,
                    "effect_box": str(effect_entry.get("effect_box", "OUTER")),
                },
            }
        )
    return modifiers


def _build_enter_state(card: dict) -> str:
    for effect_entry in card.get("effects", []):
        text = str(effect_entry.get("text", "")).strip()
        if text == "このフィールドはアクティブで場に登場させる。":
            return "ACTIVE"
    return "RESTED"


def _parse_energy_delta_from_label(label: str) -> dict:
    match = re.fullmatch(r"(赤|青|緑|黄|紫|白|黒)×(\d+)", label.strip())
    if not match:
        return {}
    color_map = {
        "赤": "RED",
        "青": "BLUE",
        "緑": "GREEN",
        "黄": "YELLOW",
        "紫": "PURPLE",
        "白": "WHITE",
        "黒": "BLACK",
    }
    color = color_map.get(match.group(1), "")
    if color == "":
        return {}
    return {color: -int(match.group(2))}


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
    filters: list[dict] | None = None,
) -> tuple[list[dict], list[dict]]:
    target_spec = {
        "id": store_as,
        "scope": "CARD",
        "candidate": {
            "owner": owner,
            "zones": zones,
            "filters": filters or [],
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
                "filters": filters or [],
                "requirements": requirements or [],
                "min": min_count,
                "max": max_count,
                "selection_mode": "MANUAL",
                "manual": True,
            },
        }
    ]
    return [target_spec], steps


def _manual_card_set(
    owner: str,
    zones: list[str],
    requirements: list[dict] | None = None,
    min_count: int = 0,
    max_count: int = 1,
    store_as: str = "selected_targets",
    filters: list[dict] | None = None,
    constraints: dict | None = None,
) -> tuple[list[dict], list[dict]]:
    target_spec = {
        "id": store_as,
        "scope": "CARD",
        "candidate": {
            "owner": owner,
            "zones": zones,
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
                "type": "CARD_SET",
                "owner": owner,
                "zones": zones,
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


def _auto_target_set(
    owner: str,
    zones: list[str],
    *,
    requirements: list[dict] | None = None,
    filters: list[dict] | None = None,
    min_count: int = 0,
    max_count: int = -1,
    store_as: str = "selected_targets",
) -> tuple[list[dict], list[dict]]:
    target_spec = {
        "id": store_as,
        "scope": "CARD",
        "candidate": {
            "owner": owner,
            "zones": zones,
            "filters": filters or [],
            "requirements": requirements or [],
        },
        "select": {
            "min": min_count,
            "max": max_count,
            "mode": "AUTO",
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
                "filters": filters or [],
                "requirements": requirements or [],
                "min": min_count,
                "max": max_count,
                "selection_mode": "AUTO",
                "manual": False,
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


def _name_in_zone_requirement(name: str, zones: list[str], owner: str = "SELF") -> dict:
    return {
        "type": "CONTROLLER_HAS_NAME_IN_ZONE",
        "value": name,
        "zones": zones,
        "owner": owner,
    }


def _field_names_all_in_set_requirement(names: list[str], owner: str = "SELF") -> dict:
    return {
        "type": "CONTROLLER_FIELD_ALL_NAMES_IN_SET",
        "names": names,
        "owner": owner,
    }


def _fixed_value_provider(value: int) -> dict:
    return {"type": "FIXED", "value": value}


def _conditional_value_provider(default_value, when: list[dict], then_value) -> dict:
    return {
        "type": "CONDITIONAL",
        "default": default_value,
        "when": when,
        "then": then_value,
    }


def _event_used_turn_flag(card_name: str) -> str:
    return f"event_used_{card_name}"


def _compact_compiler_text(text: str) -> str:
    return normalize_compiler_text(text).replace(" ", "")


def _primary_energy_color(card: dict) -> str:
    for source in [card.get("energy_provided", {}), card.get("card_meta", {}).get("energy_provided", {})]:
        if isinstance(source, dict):
            for color in source.keys():
                return str(color)
    return ""


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
    color: str = "RED",
    traits: list[str] | None = None,
    names: list[str] | None = None,
    state: str = "RESTED",
) -> tuple[list[dict], list[dict]]:
    requirements = [
        {"type": "CARD_TYPE_IS", "value": "CHARACTER"},
        {"type": "CARD_COST_ENERGY_LTE", "value": energy_lte},
        {"type": "CARD_COST_AP_EQ", "value": 1},
        {"type": "CARD_COLOR_IS", "value": color},
        {"type": "CARD_CAN_PLAY_TO_ZONE", "zone": "FRONT_LINE", "ignore_play_timing": True, "allow_current_zone": source_zone != "HAND"},
    ]
    filters: list[dict] = []
    if traits:
        if len(traits) == 1:
            requirements.append({"type": "CARD_HAS_TRAIT", "value": traits[0]})
        else:
            filters.append({"type": "OR", "filters": [{"type": "HAS_TRAIT", "value": trait} for trait in traits]})
    if names:
        if len(names) == 1:
            requirements.append({"type": "CARD_NAME_IS", "value": names[0]})
        else:
            filters.append({"type": "OR", "filters": [{"type": "NAME_IS", "value": name} for name in names]})
    target_specs, steps = _manual_single_target("SELF", [source_zone], requirements, 0, 1, store_as, filters=filters)
    steps.append(
        {
            "type": "PLAY_SELECTED_CARDS",
            "from_var": store_as,
            "to": "FRONT_LINE",
            "state": state,
            "ignore_play_timing": True,
            "allow_current_zone": source_zone != "HAND",
        }
    )
    return target_specs, steps


def _outside_character_summon_steps(
    *,
    energy_lte: int,
    ap_eq: int,
    color: str,
    state: str,
    store_as: str = "selected_outside_summon",
) -> tuple[list[dict], list[dict]]:
    requirements = [
        {"type": "CARD_TYPE_IS", "value": "CHARACTER"},
        {"type": "CARD_COST_ENERGY_LTE", "value": energy_lte},
        {"type": "CARD_COST_AP_EQ", "value": ap_eq},
        {"type": "CARD_COLOR_IS", "value": color},
        {"type": "CARD_CAN_PLAY_TO_ZONE", "zone": "FRONT_LINE", "ignore_play_timing": True, "allow_current_zone": True},
    ]
    target_specs, steps = _manual_single_target("SELF", ["OUTSIDE"], requirements, 0, 1, store_as)
    steps.append(
        {
            "type": "PLAY_SELECTED_CARDS",
            "from_var": store_as,
            "to": "FRONT_LINE",
            "state": state,
            "ignore_play_timing": True,
            "allow_current_zone": True,
        }
    )
    return target_specs, steps


def _preview_add_to_hand_then_reorder_steps(
    *,
    count: int,
    requirements: list[dict] | None = None,
    filters: list[dict] | None = None,
    min_count: int = 0,
    max_count: int = 1,
    store_as: str = "selected_preview_cards",
    distinct_by: str = "",
    discard_after_add: bool = False,
) -> tuple[list[dict], list[dict]]:
    constraints = {"distinct_by": distinct_by} if distinct_by else None
    target_specs, select_steps = _manual_context_target(
        "preview_cards",
        requirements=requirements,
        filters=filters,
        min_count=min_count,
        max_count=max_count,
        store_as=store_as,
        constraints=constraints,
    )
    steps: list[dict] = [{"type": "PREVIEW_TOP_DECK", "count": count, "var": "preview_cards"}]
    steps += select_steps
    steps += [
        {"type": "MOVE_SELECTED_CARDS", "from_var": store_as, "to": "HAND", "remove_from_var": "preview_cards"},
        {"type": "REORDER_CONTEXT_CARDS", "from_var": "preview_cards", "var": "ordered_preview_cards"},
        {"type": "MOVE_SELECTED_CARDS", "from_var": "ordered_preview_cards", "to": "DECK"},
    ]
    if discard_after_add:
        discard_specs, discard_steps = _manual_single_target("SELF", ["HAND"], [], 1, 1, "selected_discard")
        target_specs += discard_specs
        steps += [
            dict(step, requirements=[{"type": "CONTEXT_VAR_NON_EMPTY", "var": store_as}])
            for step in discard_steps
        ]
        steps.append(
            {
                "type": "MOVE_SELECTED_CARDS",
                "from_var": "selected_discard",
                "to": "OUTSIDE",
                "requirements": [{"type": "CONTEXT_VAR_NON_EMPTY", "var": store_as}],
            }
        )
    return target_specs, steps


def _preview_summon_then_reorder_steps(
    *,
    count: int,
    requirements: list[dict] | None = None,
    filters: list[dict] | None = None,
    min_count: int = 0,
    max_count: int = 1,
    store_as: str = "selected_preview_summon",
    state: str = "RESTED",
) -> tuple[list[dict], list[dict]]:
    target_specs, select_steps = _manual_context_target(
        "preview_cards",
        requirements=requirements,
        filters=filters,
        min_count=min_count,
        max_count=max_count,
        store_as=store_as,
    )
    steps: list[dict] = [{"type": "PREVIEW_TOP_DECK", "count": count, "var": "preview_cards"}]
    steps += select_steps
    steps += [
        {
            "type": "PLAY_SELECTED_CARDS",
            "from_var": store_as,
            "to": "FRONT_LINE",
            "state": state,
            "ignore_play_timing": True,
            "allow_current_zone": True,
        },
        {"type": "REMOVE_CONTEXT_VALUES", "from_var": store_as, "target_var": "preview_cards"},
        {"type": "REORDER_CONTEXT_CARDS", "from_var": "preview_cards", "var": "ordered_preview_cards"},
        {"type": "MOVE_SELECTED_CARDS", "from_var": "ordered_preview_cards", "to": "DECK"},
    ]
    return target_specs, steps


def _preview_reorder_keep_top_rest_outside_steps(*, count: int) -> tuple[list[dict], list[dict]]:
    target_specs, steps = _manual_context_target(
        "preview_cards",
        min_count=0,
        max_count=count,
        store_as="selected_top_cards",
    )
    steps = [{"type": "PREVIEW_TOP_DECK", "count": count, "var": "preview_cards"}] + steps + [
        {
            "type": "MOVE_SELECTED_CARDS",
            "from_var": "selected_top_cards",
            "to": "DECK",
            "to_position": "TOP",
            "remove_from_var": "preview_cards",
        },
        {"type": "MOVE_SELECTED_CARDS", "from_var": "preview_cards", "to": "OUTSIDE"},
    ]
    return target_specs, steps


def _supported_ability(
    card: dict,
    event_name: str,
    trigger_entry: dict,
    requirements: list[dict],
    target_specs: list[dict],
    steps: list[dict],
    kind: str | None = None,
    once_per_turn: bool | None = None,
    template_metadata: dict | None = None,
) -> dict:
    digest = hashlib.sha1(str(trigger_entry.get("text", "")).encode("utf-8")).hexdigest()[:10]
    ability = {
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
    if once_per_turn is not None:
        ability["limits"]["once_per_turn"] = once_per_turn
    if template_metadata:
        ability["template_metadata"] = dict(template_metadata)
    return ability


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


def _compile_trigger_legacy(card: dict, trigger_entry: dict, semantic_map: dict[str, dict]) -> dict:
    event_name = str(trigger_entry.get("trigger", ""))
    text = str(trigger_entry.get("text", "")).strip()
    card_id = str(card.get("id", ""))

    if event_name == "ON_LIFE_TRIGGER" and card_id in ["UA31BT_MMM_1_035", "UA31BT_MMM_1_055"]:
        target_specs, steps = _outside_character_summon_steps(
            energy_lte=2,
            ap_eq=1,
            color="PURPLE",
            state="ACTIVE",
            store_as="selected_outside_summon",
        )
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    if event_name == "ON_ENTER" and card_id == "UA31BT_MMM_1_019":
        discard_specs, discard_steps = _manual_single_target("SELF", ["HAND"], [], 1, 1, "discard_from_hand")
        target_specs, steps = _manual_single_target(
            "OPPONENT",
            ["FRONT_LINE"],
            [
                {
                    "type": "CARD_BP_LTE_DYNAMIC",
                    "value_provider": {
                        "type": "PLAYER_ZONE_CARD_COUNT_MULTIPLIED",
                        "player": "SELF",
                        "zones": ["OUTSIDE"],
                        "card_type": "EVENT",
                        "multiplier": 1000,
                    },
                }
            ],
            0,
            1,
            "selected_target",
        )
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [],
            discard_specs + target_specs,
            [
                {"type": "DRAW", "value": 1},
                *discard_steps,
                {"type": "MOVE_SELECTED_CARDS", "from_var": "discard_from_hand", "to": "OUTSIDE"},
                *steps,
                {"type": "MOVE_SELECTED_CARDS", "from_var": "selected_target", "to": "HAND", "target_player_mode": "CARD_CONTROLLER"},
            ],
        )

    if event_name == "MAIN_ACTIVATE" and card_id == "UA31BT_MMM_1_027":
        target_specs, steps = _manual_single_target(
            "SELF",
            ["HAND"],
            [],
            1,
            1,
            "selected_event_discard",
            filters=[{"type": "CARD_TYPE_IS", "value": "EVENT"}],
        )
        steps.extend(
            [
                {"type": "MOVE_SELECTED_CARDS", "from_var": "selected_event_discard", "to": "OUTSIDE"},
                {
                    "type": "REGISTER_STATIC_MODIFIER",
                    "modifier_type": "HAND_PLAY_COST_ENERGY_DELTA",
                    "from_zone": "HAND",
                    "filters": [{"type": "NAME_IS", "value": "巴 マミ"}],
                    "value": -1,
                    "expires": "END_OF_TURN",
                },
            ]
        )
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    if event_name == "ON_ENTER" and card_id == "UA31BT_MMM_1_048":
        target_specs, steps = _preview_reorder_keep_top_rest_outside_steps(count=2)
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    if event_name == "ON_ENTER" and card_id == "UA31BT_MMM_1_042":
        target_specs, steps = _hand_character_summon_steps(
            1,
            color="PURPLE",
            names=["暁美 ほむら", "鹿目 まどか"],
        )
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    if event_name == "ON_ENTER" and card_id == "UA31BT_MMM_1_056":
        target_specs, steps = _preview_summon_then_reorder_steps(
            count=4,
            requirements=[
                {"type": "CARD_TYPE_IS", "value": "CHARACTER"},
                {"type": "CARD_COST_ENERGY_LTE", "value": 2},
                {"type": "CARD_COST_AP_EQ", "value": 1},
                {"type": "CARD_COLOR_IS", "value": "PURPLE"},
                {"type": "CARD_CAN_PLAY_TO_ZONE", "zone": "FRONT_LINE", "ignore_play_timing": True, "allow_current_zone": True},
            ],
            state="RESTED",
        )
        steps.append(
            {
                "type": "ADD_TEMP_KEYWORD",
                "target_uid": "SOURCE_CARD",
                "keyword": "IMPACT",
                "expires": "END_OF_TURN",
                "requirements": [
                    {
                        "type": "CONTROLLER_OTHER_TRAIT_CARD_COUNT_GTE",
                        "trait": "ピュエラ・マギ・ホーリー・クインテット",
                        "value": 4,
                    }
                ],
            }
        )
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [],
            target_specs,
            steps,
        )

    if event_name == "ON_ENTER" and text == "自分の手札を1枚場外に置いてもよい。そうした場合、自分の場外から〈黒咲 芽亜〉を1枚まで手札に加える。":
        discard_specs, discard_steps = _manual_single_target("SELF", ["HAND"], [], 0, 1, "selected_discard")
        target_specs, recover_steps = _manual_single_target(
            "SELF",
            ["OUTSIDE"],
            [{"type": "CARD_NAME_IS", "value": "黒咲 芽亜"}],
            0,
            1,
            "selected_recover",
        )
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [],
            discard_specs + target_specs,
            discard_steps
            + [
                {"type": "MOVE_SELECTED_CARDS", "from_var": "selected_discard", "to": "OUTSIDE"},
            ]
            + [
                dict(step, requirements=[{"type": "CONTEXT_VAR_NON_EMPTY", "var": "selected_discard"}])
                for step in recover_steps
            ]
            + [
                {
                    "type": "MOVE_SELECTED_CARDS",
                    "from_var": "selected_recover",
                    "to": "HAND",
                    "requirements": [{"type": "CONTEXT_VAR_NON_EMPTY", "var": "selected_discard"}],
                }
            ],
        )

    if event_name == "ON_ENTER" and text == "自分の手札を1枚場外に置いてもよい。そうした場合、BP4000以下の相手のフロントLのキャラを1枚まで選び、レストにする。":
        discard_specs, discard_steps = _manual_single_target("SELF", ["HAND"], [], 0, 1, "selected_discard")
        rest_specs, rest_steps = _manual_single_target(
            "OPPONENT",
            ["FRONT_LINE"],
            [{"type": "CARD_BP_LTE", "value": 4000}],
            0,
            1,
            "selected_rest_target",
        )
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [],
            discard_specs + rest_specs,
            discard_steps
            + [{"type": "MOVE_SELECTED_CARDS", "from_var": "selected_discard", "to": "OUTSIDE"}]
            + [
                dict(step, requirements=[{"type": "CONTEXT_VAR_NON_EMPTY", "var": "selected_discard"}])
                for step in rest_steps
            ]
            + [
                {"type": "REST", "target_var": "selected_rest_target", "requirements": [{"type": "CONTEXT_VAR_NON_EMPTY", "var": "selected_discard"}]}
            ],
        )

    if event_name == "ON_ENTER" and text == "自分の手札を全て場外に置き、カードを5枚引く。":
        target_specs, steps = _auto_target_set("SELF", ["HAND"], min_count=0, max_count=-1, store_as="all_hand_cards")
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [],
            target_specs,
            steps + [{"type": "MOVE_SELECTED_CARDS", "from_var": "all_hand_cards", "to": "OUTSIDE"}, {"type": "DRAW", "value": 5}],
        )

    if event_name == "ON_ENTER" and text == "カードを1枚引く。自分の場のキャラを1枚まで選び、このターン中、BP+1000。":
        target_specs, select_steps = _manual_single_target(
            "SELF",
            ["FRONT_LINE", "ENERGY_LINE"],
            [{"type": "CARD_TYPE_IS", "value": "CHARACTER"}],
            0,
            1,
            "selected_target",
        )
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [],
            target_specs,
            [{"type": "DRAW", "value": 1}]
            + select_steps
            + [{"type": "ADD_TEMP_BP_MODIFIER", "target_var": "selected_target", "value": 1000, "expires": "END_OF_TURN"}],
        )

    if event_name == "ON_ATTACK" and text == "自分のフロントLに〈霧崎 恭子〉がある場合、カードを1枚引く。":
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [_name_in_zone_requirement("霧崎 恭子", ["FRONT_LINE"])],
            [],
            [{"type": "DRAW", "value": 1}],
        )

    if event_name == "ON_ENTER" and text == "自分のフロントLに必要エナジーが3以下のキャラが2枚以上ある場合、このキャラをアクティブにする。":
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [
                {
                    "type": "PLAYER_ZONE_CARD_COUNT_GTE",
                    "player": "SELF",
                    "zones": ["FRONT_LINE"],
                    "card_type": "CHARACTER",
                    "value": 2,
                }
            ],
            [],
            [{"type": "ACTIVATE_CARD", "target_uid": "SOURCE_CARD"}],
        )

    if event_name in ["ON_ENTER", "MAIN_ACTIVATE"] and text == "カードを1枚引く。その後、自分の手札から必要エナジーが3以下で消費APが1の赤のキャラカードを1枚まで自分の場にレストで登場させる。":
        target_specs, steps = _hand_character_summon_steps(
            3,
            color="RED",
            state="RESTED",
        )
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, [{"type": "DRAW", "value": 1}] + steps)

    if event_name == "ON_ENTER" and text == "自分の山札の上から3枚見て、［特徴：変身兵器］を1枚まで公開し手札に加える。残りを望む順で山札の下に置く。":
        target_specs, steps = _preview_add_to_hand_then_reorder_steps(
            count=3,
            filters=[{"type": "HAS_TRAIT", "value": "変身兵器"}],
            min_count=0,
            max_count=1,
        )
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    if event_name == "ON_ENTER" and text == "自分の山札の上から3枚見て、［特徴：変身兵器］を1枚まで公開し手札に加える。残りを望む順で山札の下に置く。手札に加えた場合、自分の手札を1枚場外に置く。":
        target_specs, steps = _preview_add_to_hand_then_reorder_steps(
            count=3,
            filters=[{"type": "HAS_TRAIT", "value": "変身兵器"}],
            min_count=0,
            max_count=1,
            discard_after_add=True,
        )
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    if event_name == "ON_ENTER" and text == "自分の手札から必要エナジーが2以下で消費APが1の赤のキャラカードを1枚まで自分の場にレストで登場させる。":
        target_specs, steps = _hand_character_summon_steps(
            2,
            color="RED",
            state="RESTED",
        )
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    if event_name == "ON_ENTER" and text == "カードを1枚引く。その後、自分の手札から必要エナジーが3以下で消費APが1の赤のキャラカードを1枚まで自分の場にレストで登場させる。":
        target_specs, steps = _hand_character_summon_steps(
            3,
            color="RED",
            state="RESTED",
        )
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, [{"type": "DRAW", "value": 1}] + steps)

    if event_name == "ON_ENTER" and text == "カードを1枚引く。自分の場の他のキャラを1枚手札に戻してもよい。そうした場合、自分の手札から必要エナジーが4以下で消費APが1の赤のキャラカードを1枚まで自分の場にレストで登場させる。":
        bounce_specs, bounce_steps = _manual_single_target(
            "SELF",
            ["FRONT_LINE", "ENERGY_LINE"],
            [{"type": "CARD_TYPE_IS", "value": "CHARACTER"}],
            0,
            1,
            "selected_bounce",
        )
        summon_specs, summon_steps = _hand_character_summon_steps(
            4,
            color="RED",
            state="RESTED",
            store_as="selected_summon",
        )
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [],
            bounce_specs + summon_specs,
            [{"type": "DRAW", "value": 1}]
            + bounce_steps
            + [{"type": "MOVE_SELECTED_CARDS", "from_var": "selected_bounce", "to": "HAND"}]
            + [
                dict(step, requirements=[{"type": "CONTEXT_VAR_NON_EMPTY", "var": "selected_bounce"}])
                for step in summon_steps
            ],
        )

    if event_name == "ON_ENTER" and text == "自分の場の他のキャラを1枚手札に戻してもよい。そうした場合、カードを2枚引き、自分の手札を1枚場外に置く。":
        bounce_specs, bounce_steps = _manual_single_target(
            "SELF",
            ["FRONT_LINE", "ENERGY_LINE"],
            [{"type": "CARD_TYPE_IS", "value": "CHARACTER"}],
            0,
            1,
            "selected_bounce",
        )
        discard_specs, discard_steps = _manual_single_target("SELF", ["HAND"], [], 1, 1, "selected_discard")
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [],
            bounce_specs + discard_specs,
            bounce_steps
            + [{"type": "MOVE_SELECTED_CARDS", "from_var": "selected_bounce", "to": "HAND"}]
            + [
                {"type": "DRAW", "value": 2, "requirements": [{"type": "CONTEXT_VAR_NON_EMPTY", "var": "selected_bounce"}]},
            ]
            + [
                dict(step, requirements=[{"type": "CONTEXT_VAR_NON_EMPTY", "var": "selected_bounce"}])
                for step in discard_steps
            ]
            + [
                {
                    "type": "MOVE_SELECTED_CARDS",
                    "from_var": "selected_discard",
                    "to": "OUTSIDE",
                    "requirements": [{"type": "CONTEXT_VAR_NON_EMPTY", "var": "selected_bounce"}],
                }
            ],
        )

    if event_name == "MAIN_ACTIVATE" and text == "〈西連寺 春菜〉以外の自分のフロントLのキャラを1枚選ぶ。そうした場合、そのキャラをこのターン中、BP+1000し、カードを1枚引く。":
        target_specs, select_steps = _manual_single_target(
            "SELF",
            ["FRONT_LINE"],
            [],
            1,
            1,
            "selected_target",
            filters=[{"type": "NAME_NOT", "value": "西連寺 春菜"}],
        )
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [],
            target_specs,
            select_steps + [{"type": "ADD_TEMP_BP_MODIFIER", "target_var": "selected_target", "value": 1000, "expires": "END_OF_TURN"}, {"type": "DRAW", "value": 1}],
        )

    if event_name == "ON_PLAY" and text == "カードを2枚引く。相手は自身の手札を全て公開する。":
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [],
            [],
            [{"type": "DRAW", "value": 2}],
            kind="TRIGGERED",
        )

    if event_name == "ON_PLAY" and text == "自分のフロントLのキャラ全ては、このターン中、BP+1000。カードを1枚引く。":
        target_specs, select_steps = _auto_target_set(
            "SELF",
            ["FRONT_LINE"],
            requirements=[{"type": "CARD_TYPE_IS", "value": "CHARACTER"}],
            min_count=0,
            max_count=-1,
            store_as="all_front_chars",
        )
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [],
            target_specs,
            select_steps
            + [
                {
                    "type": "FOR_EACH",
                    "items_var": "all_front_chars",
                    "current_var": "buff_target",
                    "steps": [{"type": "ADD_TEMP_BP_MODIFIER", "target_var": "buff_target", "value": 1000, "expires": "END_OF_TURN"}],
                },
                {"type": "DRAW", "value": 1},
            ],
            kind="TRIGGERED",
        )

    if event_name == "ON_PLAY" and text == "自分の山札の上から5枚見て、異なるカード名のキャラカードをそれぞれ1枚ずつ合計3枚まで公開し手札に加える。残りを望む順で山札の下に置く。":
        target_specs, steps = _preview_add_to_hand_then_reorder_steps(
            count=5,
            requirements=[{"type": "CARD_TYPE_IS", "value": "CHARACTER"}],
            min_count=0,
            max_count=3,
            distinct_by="CARD_NAME",
        )
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps, kind="TRIGGERED")

    if event_name == "ON_PLAY" and text == "BP5000以下の相手のフロントLのキャラを1枚選び、相手の山札の下に置く。":
        target_specs, steps = _manual_single_target(
            "OPPONENT",
            ["FRONT_LINE"],
            [{"type": "CARD_BP_LTE", "value": 5000}],
            1,
            1,
            "selected_target",
        )
        steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_target", "to": "DECK", "target_player_mode": "CARD_CONTROLLER"})
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps, kind="TRIGGERED")

    if event_name == "ON_ENTER" and text == "自分の場外にあるキャラカードを2枚までリムーブエリアに置く。":
        target_specs, steps = _manual_card_set(
            "SELF",
            ["OUTSIDE"],
            requirements=[{"type": "CARD_TYPE_IS", "value": "CHARACTER"}],
            min_count=0,
            max_count=2,
            store_as="selected_outside_cards",
        )
        steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_outside_cards", "to": "REMOVED"})
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    if event_name == "ON_ENTER" and text == "自分の場外にあるキャラカードを2枚までリムーブエリアに置く。このターン中、次にリムーブエリアから使用するカードの消費APを-1する。":
        target_specs, steps = _manual_card_set(
            "SELF",
            ["OUTSIDE"],
            requirements=[{"type": "CARD_TYPE_IS", "value": "CHARACTER"}],
            min_count=0,
            max_count=2,
            store_as="selected_outside_cards",
        )
        steps.extend(
            [
                {"type": "MOVE_SELECTED_CARDS", "from_var": "selected_outside_cards", "to": "REMOVED"},
                {
                    "type": "REGISTER_DELAYED_EFFECT",
                    "event": "ON_PLAY_CARD",
                    "expires": "END_OF_TURN",
                    "once": True,
                    "filters": [{"type": "PLAYED_FROM_ZONE_IS", "value": "REMOVED"}],
                    "steps": [{"type": "MODIFY_PLAY_COST_AP", "value": -1}],
                },
            ]
        )
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    if event_name == "ON_ENTER" and text == "自分の山札の上から4枚見る。その中からキャラカードを1枚まで場外に置く。残りを望む順で自分の山札の上に置く。":
        target_specs, select_steps = _manual_context_target(
            "preview_cards",
            requirements=[{"type": "CARD_TYPE_IS", "value": "CHARACTER"}],
            min_count=0,
            max_count=1,
            store_as="selected_outside_card",
        )
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [],
            target_specs,
            [
                {"type": "PREVIEW_TOP_DECK", "count": 4, "var": "preview_cards"},
            ]
            + select_steps
            + [
                {"type": "MOVE_SELECTED_CARDS", "from_var": "selected_outside_card", "to": "OUTSIDE", "remove_from_var": "preview_cards"},
                {"type": "REORDER_CONTEXT_CARDS", "from_var": "preview_cards", "var": "ordered_preview_cards"},
                {"type": "MOVE_SELECTED_CARDS", "from_var": "ordered_preview_cards", "to": "DECK", "to_position": "TOP"},
            ],
        )

    if event_name in ["ON_ENTER", "MAIN_ACTIVATE"] and text == "自分の山札の上から1枚見る。そのカードを自分の山札の上か場外に置く。":
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [],
            [],
            [
                {"type": "PREVIEW_TOP_DECK", "count": 1, "var": "preview_cards"},
                {
                    "type": "SELECT_TARGETS",
                    "var": "selected_preview_destination",
                    "target": {
                        "type": "OPTION_SET",
                        "options": ["TOP", "OUTSIDE"],
                        "min": 1,
                        "max": 1,
                        "selection_mode": "MANUAL",
                        "manual": True,
                    },
                },
                {
                    "type": "MOVE_SELECTED_CARDS",
                    "from_var": "preview_cards",
                    "to": "DECK",
                    "to_position": "TOP",
                    "target_player_mode": "SOURCE",
                    "requirements": [{"type": "CONTEXT_VALUE_IS", "var": "selected_preview_destination", "value": "TOP"}],
                },
                {
                    "type": "MOVE_SELECTED_CARDS",
                    "from_var": "preview_cards",
                    "to": "OUTSIDE",
                    "target_player_mode": "SOURCE",
                    "requirements": [{"type": "CONTEXT_VALUE_IS", "var": "selected_preview_destination", "value": "OUTSIDE"}],
                },
            ],
        )

    if event_name == "ON_ENTER" and text == "このキャラがリムーブエリアから登場していた場合、カードを1枚引く。〈百江 なぎさ〉のこの効果は1ターンに1回のみ発動する。":
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [{"type": "SOURCE_ENTERED_FROM_ZONE", "value": "REMOVED"}],
            [],
            [{"type": "DRAW", "value": 1}],
            once_per_turn=True,
        )

    if event_name == "ON_ENTER" and text == "このキャラがリムーブエリアから登場していた場合、自分の山札の上から2枚見る。その中から望む枚数を望む順で自分の山札の上に置き、残りを場外に置く。":
        target_specs, select_steps = _manual_context_target(
            "preview_cards",
            min_count=0,
            max_count=2,
            store_as="selected_top_cards",
        )
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [{"type": "SOURCE_ENTERED_FROM_ZONE", "value": "REMOVED"}],
            target_specs,
            [
                {"type": "PREVIEW_TOP_DECK", "count": 2, "var": "preview_cards"},
            ]
            + select_steps
            + [
                {"type": "MOVE_SELECTED_CARDS", "from_var": "selected_top_cards", "to": "DECK", "to_position": "TOP", "remove_from_var": "preview_cards"},
                {"type": "MOVE_SELECTED_CARDS", "from_var": "preview_cards", "to": "OUTSIDE"},
            ],
        )

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

    if event_name == "ON_ATTACK" and text == "自分のリムーブエリアにある〈アルティメットまどか〉を1枚場外に置いてもよい。そうした場合、このキャラはこのターン中、BP+1000と（アタックしてバトルに勝利した時、相手プレイヤーに1ダメージ）を得る。":
        target_specs, steps = _manual_single_target(
            "SELF",
            ["REMOVED"],
            [{"type": "CARD_NAME_IS", "value": "アルティメットまどか"}],
            0,
            1,
            "selected_removed_card",
        )
        steps.extend(
            [
                {"type": "MOVE_SELECTED_CARDS", "from_var": "selected_removed_card", "to": "OUTSIDE"},
                {
                    "type": "ADD_TEMP_BP_MODIFIER",
                    "target_uid": "SOURCE_CARD",
                    "value": 1000,
                    "expires": "END_OF_TURN",
                    "requirements": [{"type": "CONTEXT_VAR_NON_EMPTY", "var": "selected_removed_card"}],
                },
                {
                    "type": "ADD_TEMP_KEYWORD",
                    "target_uid": "SOURCE_CARD",
                    "keyword": "IMPACT",
                    "expires": "END_OF_TURN",
                    "requirements": [{"type": "CONTEXT_VAR_NON_EMPTY", "var": "selected_removed_card"}],
                },
            ]
        )
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    if event_name == "ON_LEAVE" and text == "このキャラをリムーブエリアに置く。":
        return _supported_ability(card, event_name, trigger_entry, [], [], [{"type": "MOVE_CARD", "target_uid": "SOURCE_CARD", "to": "REMOVED"}])

    if event_name == "ON_LEAVE" and text == "このキャラをリムーブエリアに置き、自分のリムーブエリアから〈鹿目 まどか〉以外の必要エナジーが3以下で消費APが1の異なるカード名の黄の［特徴：魔法少女］を2枚まで自分の場にレストで登場させる。":
        target_specs, select_steps = _manual_card_set(
            "SELF",
            ["REMOVED"],
            requirements=[
                {"type": "CARD_TYPE_IS", "value": "CHARACTER"},
                {"type": "CARD_COST_ENERGY_LTE", "value": 3},
                {"type": "CARD_COST_AP_EQ", "value": 1},
                {"type": "CARD_COLOR_IS", "value": "YELLOW"},
                {"type": "CARD_HAS_TRAIT", "value": "魔法少女"},
                {"type": "CARD_CAN_PLAY_TO_ZONE", "zone": "FRONT_LINE", "ignore_play_timing": True, "allow_current_zone": True},
            ],
            filters=[{"type": "NAME_NOT", "value": "鹿目 まどか"}],
            min_count=0,
            max_count=2,
            store_as="selected_removed_summons",
            constraints={"distinct_by": "CARD_NAME"},
        )
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [],
            target_specs,
            [{"type": "MOVE_CARD", "target_uid": "SOURCE_CARD", "to": "REMOVED"}]
            + select_steps
            + [
                {
                    "type": "PLAY_SELECTED_CARDS",
                    "from_var": "selected_removed_summons",
                    "to": "FRONT_LINE",
                    "state": "RESTED",
                    "ignore_play_timing": True,
                    "allow_current_zone": True,
                    "ignore_play_costs": True,
                }
            ],
        )

    if event_name == "ON_LIFE_TRIGGER" and text == "相手のフロントLのキャラを1枚選び、レストにする。それは次の1回アクティブにならない。":
        target_specs, steps = _manual_single_target("OPPONENT", ["FRONT_LINE"])
        steps.extend(
            [
                {"type": "REST", "target_var": "selected_target"},
                {"type": "SET_CARD_FLAG", "target_var": "selected_target", "flag": "skip_next_ready_once", "value": True},
            ]
        )
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

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

    if text == "自分の場外にイベントカードが2枚以上ある場合、カードを1枚引く。":
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [{"type": "PLAYER_ZONE_CARD_COUNT_GTE", "player": "SELF", "zones": ["OUTSIDE"], "card_type": "EVENT", "value": 2}],
            [],
            [{"type": "DRAW", "value": 1}],
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

    if text == "カードを2枚引き、自分の手札を1枚場外に置く。":
        target_specs, steps = _manual_single_target("SELF", ["HAND"], [], 1, 1, "discard_from_hand")
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [],
            target_specs,
            [{"type": "DRAW", "value": 2}] + steps + [{"type": "MOVE_SELECTED_CARDS", "from_var": "discard_from_hand", "to": "OUTSIDE"}],
        )

    if text == "カードを2枚引き、自分の手札を1枚場外に置く。この効果でイベントカードを場外に置いた場合、自分のAPカードを1枚まで選び、アクティブにする。":
        target_specs, steps = _manual_single_target("SELF", ["HAND"], [], 1, 1, "discard_from_hand")
        steps.extend(
            [
                {"type": "MOVE_SELECTED_CARDS", "from_var": "discard_from_hand", "to": "OUTSIDE"},
                {"type": "ACTIVATE_AP_SLOTS", "value": 1, "requirements": [{"type": "CONTEXT_SELECTED_CARD_TYPE_IS", "context_var": "discard_from_hand", "value": "EVENT"}]},
            ]
        )
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [],
            target_specs,
            [{"type": "DRAW", "value": 2}] + steps,
        )

    if text == "自分のAPカードを2枚まで選び、アクティブにする。":
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [],
            [],
            [{"type": "ACTIVATE_AP_SLOTS", "value": 2}],
        )

    match = re.fullmatch(r"自分のエナジーLに〈(.+)〉がある場合、相手のフロントLのキャラを1枚まで選び、このターン中、BP-(\d+)。", text)
    if match:
        target_specs, steps = _manual_single_target(
            "OPPONENT",
            ["FRONT_LINE"],
            [_name_in_zone_requirement(match.group(1), ["ENERGY_LINE"])],
            0,
            1,
            "selected_target",
        )
        steps.append({"type": "ADD_TEMP_BP_MODIFIER", "target_var": "selected_target", "value": -int(match.group(2)), "expires": "END_OF_TURN"})
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

    if text == "このキャラのBPが5000以上の場合のみ発動できる。このキャラをアクティブにする。":
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [{"type": "SOURCE_BP_GTE", "value": 5000}],
            [],
            [{"type": "ACTIVATE_CARD", "target_uid": "SOURCE_CARD"}],
        )

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

    if text == "自分の場の他のキャラを1枚まで選び、このターン中、BP+1000。":
        target_specs, steps = _manual_single_target(
            "SELF",
            ["FRONT_LINE", "ENERGY_LINE"],
            [],
            0,
            1,
            "selected_target",
            filters=[{"type": "NOT_SOURCE_CARD"}],
        )
        steps.append({"type": "ADD_TEMP_BP_MODIFIER", "target_var": "selected_target", "value": 1000, "expires": "END_OF_TURN"})
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    if text == "自分の場の［特徴：魔法少女］を1枚選び、このターン中、BP+500。":
        requirements = [{"type": "CARD_HAS_TRAIT", "value": "魔法少女"}]
        target_specs, steps = _manual_single_target("SELF", ["FRONT_LINE", "ENERGY_LINE"], requirements, 1, 1, "selected_target")
        steps.append({"type": "ADD_TEMP_BP_MODIFIER", "target_var": "selected_target", "value": 500, "expires": "END_OF_TURN"})
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    if text == "このキャラが登場したターン中のみ発動できる。自分の場の他のキャラを1枚選び、このターン中、（アタックしてバトルに勝利した時、相手プレイヤーに1ダメージ）を与える。":
        target_specs, steps = _manual_single_target(
            "SELF",
            ["FRONT_LINE", "ENERGY_LINE"],
            [],
            1,
            1,
            "selected_target",
            filters=[{"type": "NOT_SOURCE_CARD"}],
        )
        steps.append({"type": "ADD_TEMP_KEYWORD", "target_var": "selected_target", "keyword": "IMPACT", "expires": "END_OF_TURN"})
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [{"type": "SOURCE_ENTERED_THIS_TURN"}],
            target_specs,
            steps,
        )

    if text == "このキャラがアクティブの場合のみ発動できる。自分の場の〈百江 なぎさ〉か他の［特徴：ピュエラ・マギ・ホーリー・クインテット］を1枚選び、このターン中、BP+1000。":
        target_specs, steps = _manual_single_target(
            "SELF",
            ["FRONT_LINE", "ENERGY_LINE"],
            [],
            1,
            1,
            "selected_target",
            filters=[
                {
                    "type": "OR",
                    "filters": [
                        {"type": "NAME_IS", "value": "百江 なぎさ"},
                        {"type": "AND", "filters": [{"type": "HAS_TRAIT", "value": "ピュエラ・マギ・ホーリー・クインテット"}, {"type": "NOT_SOURCE_CARD"}]},
                    ],
                }
            ],
        )
        steps.append({"type": "ADD_TEMP_BP_MODIFIER", "target_var": "selected_target", "value": 1000, "expires": "END_OF_TURN"})
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [{"type": "SOURCE_STATE_IS_ACTIVE"}],
            target_specs,
            steps,
        )

    if text == "自分のフロントLの〈鹿目 まどか〉を1枚選び、このキャラと位置を入れ替える。":
        target_specs, steps = _manual_single_target(
            "SELF",
            ["FRONT_LINE"],
            [{"type": "CARD_NAME_IS", "value": "鹿目 まどか"}],
            1,
            1,
            "selected_madoka_target",
        )
        steps.append({"type": "SWAP_SOURCE_WITH_SELECTED_CARD", "target_var": "selected_madoka_target"})
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    if text == "自分の場の〈鹿目 まどか〉を1枚手札に戻してもよい。そうした場合、相手のフロントLのキャラを1枚まで選び、このターン中、『BP-3000』。自分の場にあるキャラが全て〈暁美 ほむら〉と〈鹿目 まどか〉の場合、『BP-4000』に代わる。":
        return_specs, return_steps = _manual_single_target(
            "SELF",
            ["FRONT_LINE", "ENERGY_LINE"],
            [{"type": "CARD_NAME_IS", "value": "鹿目 まどか"}],
            0,
            1,
            "selected_returned_madoka",
        )
        debuff_specs, debuff_steps = _manual_single_target(
            "OPPONENT",
            ["FRONT_LINE"],
            [],
            0,
            1,
            "selected_enemy_target",
        )
        debuff_value = _conditional_value_provider(
            _fixed_value_provider(-3000),
            [_field_names_all_in_set_requirement(["暁美 ほむら", "鹿目 まどか"])],
            _fixed_value_provider(-4000),
        )
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [],
            return_specs + debuff_specs,
            return_steps
            + [
                {"type": "MOVE_SELECTED_CARDS", "from_var": "selected_returned_madoka", "to": "HAND"},
                {"type": "SET_CONTEXT_FLAG", "var": "returned_madoka_to_hand", "from_var": "selected_returned_madoka"},
            ]
            + [
                dict(step, requirements=[{"type": "CONTEXT_FLAG_TRUE", "var": "returned_madoka_to_hand"}])
                for step in debuff_steps
            ]
            + [
                {
                    "type": "ADD_TEMP_BP_MODIFIER",
                    "target_var": "selected_enemy_target",
                    "value_provider": debuff_value,
                    "expires": "END_OF_TURN",
                    "requirements": [{"type": "CONTEXT_FLAG_TRUE", "var": "returned_madoka_to_hand"}],
                }
            ],
        )

    if text == "自分の場に〈鹿目 まどか〉がある場合、このキャラのレイド元のカードを1枚まで手札に戻す。":
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [{"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": "鹿目 まどか"}],
            [],
            [{"type": "MOVE_SOURCE_STACKED_UNDER_TO_ZONE", "to": "HAND", "count": 1}],
        )

    if text == "自分の場外から紫の［特徴：魔法少女］を1枚まで手札に加える。":
        target_specs, steps = _manual_single_target(
            "SELF",
            ["OUTSIDE"],
            [
                {"type": "CARD_COLOR_IS", "value": "PURPLE"},
                {"type": "CARD_HAS_TRAIT", "value": "魔法少女"},
            ],
            0,
            1,
            "selected_outside_card",
        )
        steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_outside_card", "to": "HAND"})
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

    if text == "このキャラはこのターン中、発生エナジー+と「メインフェイズ終了時、このキャラを退場させる。」を得る。":
        color = _primary_energy_color(card)
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [],
            [],
            [
                {
                    "type": "REGISTER_STATIC_MODIFIER",
                    "modifier_type": "ENERGY_BONUS",
                    "color": color,
                    "value": 1,
                    "expires": "END_OF_TURN",
                },
                {
                    "type": "REGISTER_DELAYED_EFFECT",
                    "event": "ON_END_MAIN_PHASE",
                    "expires": "END_OF_TURN",
                    "once": True,
                    "filters": [
                        {
                            "type": "OR",
                            "filters": [
                                {"type": "SELF_IN_ZONE", "zone": "FRONT_LINE"},
                                {"type": "SELF_IN_ZONE", "zone": "ENERGY_LINE"},
                            ],
                        }
                    ],
                    "steps": [
                        {"type": "MOVE_CARD", "target_uid": "SOURCE_CARD", "to": "OUTSIDE"},
                    ],
                },
            ],
        )

    if text == "自分のライフエリアにあるカードを1枚手札に加える。そうした場合、このキャラは次の自分のターン開始時まで、「このカードを自分の場にレストで登場させるかレイドさせる。」を得る。":
        target_specs, steps = _manual_single_target("SELF", ["LIFE"], [], 1, 1, "selected_life_card")
        steps.extend(
            [
                {"type": "MOVE_SELECTED_CARDS", "from_var": "selected_life_card", "to": "HAND"},
                {"type": "SET_CONTEXT_FLAG", "var": "life_card_added_to_hand", "from_var": "selected_life_card"},
                {
                    "type": "REGISTER_STATIC_MODIFIER",
                    "modifier_type": "SPECIAL_PLAY_PERMISSION",
                    "granted_card_uid": "SOURCE_CARD",
                    "allowed_modes": ["REST_SUMMON", "RAID"],
                    "expires": "UNTIL_NEXT_SELF_TURN_START",
                    "requirements": [{"type": "CONTEXT_FLAG_TRUE", "var": "life_card_added_to_hand"}],
                },
            ]
        )
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    if text == "自分の場の〈百江 なぎさ〉と［特徴：ピュエラ・マギ・ホーリー・クインテット］全ては、このターン中、BP+1000。":
        target_specs, steps = _auto_target_set(
            "SELF",
            ["FRONT_LINE", "ENERGY_LINE"],
            filters=[
                {
                    "type": "OR",
                    "filters": [
                        {"type": "NAME_IS", "value": "百江 なぎさ"},
                        {"type": "HAS_TRAIT", "value": "ピュエラ・マギ・ホーリー・クインテット"},
                    ],
                }
            ],
            store_as="selected_team_targets",
        )
        steps.append(
            {
                "type": "FOR_EACH",
                "items_var": "selected_team_targets",
                "current_var": "current_item",
                "steps": [
                    {
                        "type": "ADD_TEMP_BP_MODIFIER",
                        "target": {"type": "CURRENT_ITEM"},
                        "value": 1000,
                        "expires": "END_OF_TURN",
                    }
                ],
            }
        )
        return _supported_ability(card, event_name, trigger_entry, [], target_specs, steps)

    if text == "自分の山札の上から1枚を公開する。公開したカードが〈百江 なぎさ〉か［特徴：ピュエラ・マギ・ホーリー・クインテット］の場合、そのカードを手札に加える。公開したカードがそれら以外の場合、自分の山札の上か下に置く。":
        matched_specs, matched_steps = _manual_context_target(
            "preview_cards",
            filters=[
                {
                    "type": "OR",
                    "filters": [
                        {"type": "NAME_IS", "value": "百江 なぎさ"},
                        {"type": "HAS_TRAIT", "value": "ピュエラ・マギ・ホーリー・クインテット"},
                    ],
                }
            ],
            min_count=0,
            max_count=1,
            store_as="revealed_match_card",
        )
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [],
            matched_specs,
            [
                {"type": "PREVIEW_TOP_DECK", "count": 1, "var": "preview_cards"},
            ]
            + [
                dict(step, target={**step["target"], "selection_mode": "AUTO", "manual": False})
                if step.get("type") == "SELECT_TARGETS"
                else step
                for step in matched_steps
            ]
            + [
                {
                    "type": "MOVE_SELECTED_CARDS",
                    "from_var": "revealed_match_card",
                    "to": "HAND",
                    "remove_from_var": "preview_cards",
                    "target_player_mode": "SOURCE",
                },
                {"type": "SET_CONTEXT_FLAG", "var": "revealed_match_succeeded", "from_var": "revealed_match_card"},
                {
                    "type": "SELECT_TARGETS",
                    "var": "revealed_nonmatch_position",
                    "requirements": [{"type": "CONTEXT_FLAG_FALSE", "var": "revealed_match_succeeded"}],
                    "target": {
                        "type": "OPTION_SET",
                        "options": ["TOP", "BOTTOM"],
                        "min": 1,
                        "max": 1,
                        "selection_mode": "MANUAL",
                        "manual": True,
                    },
                },
                {
                    "type": "MOVE_SELECTED_CARDS",
                    "from_var": "preview_cards",
                    "to": "DECK",
                    "to_position_from_var": "revealed_nonmatch_position",
                    "target_player_mode": "SOURCE",
                    "requirements": [{"type": "CONTEXT_FLAG_FALSE", "var": "revealed_match_succeeded"}],
                },
            ],
        )

    semantic_entry = semantic_map.get(card["id"])
    if semantic_entry and not semantic_entry.get("can_be_expressed_by_dsl", True):
        reason = " / ".join(semantic_entry.get("unresolved_capabilities", []))
        return _unsupported_ability(card, event_name, trigger_entry, reason)
    return _unsupported_ability(card, event_name, trigger_entry, "当前原子要求/步骤模板尚未覆盖该文本模式。")


def _compile_event_effect_legacy(card: dict, effect_entry: dict, semantic_map: dict[str, dict]) -> dict | None:
    event_name = "ON_PLAY"
    text = str(effect_entry.get("text", "")).strip()
    card_id = str(card.get("id", ""))
    pseudo_trigger = {
        "trigger": event_name,
        "source_label": effect_entry.get("source_label", ""),
        "effect_box": effect_entry.get("effect_box", "OUTER"),
        "text": text,
    }

    if card_id == "UA31BT_MMM_1_027" and text == "自分の手札のイベントカードを1枚場外に置く。そうした場合、このターン中、自分の手札にある全ての〈巴 マミ〉の必要エナジーを減らす。":
        target_specs, steps = _manual_single_target(
            "SELF",
            ["HAND"],
            [],
            1,
            1,
            "selected_event_discard",
            filters=[{"type": "CARD_TYPE_IS", "value": "EVENT"}],
        )
        steps.extend(
            [
                {"type": "MOVE_SELECTED_CARDS", "from_var": "selected_event_discard", "to": "OUTSIDE"},
                {
                    "type": "REGISTER_STATIC_MODIFIER",
                    "modifier_type": "HAND_PLAY_COST_ENERGY_DELTA",
                    "from_zone": "HAND",
                    "filters": [{"type": "NAME_IS", "value": "巴 マミ"}],
                    "value": -1,
                    "expires": "END_OF_TURN",
                },
            ]
        )
        return _supported_ability(card, event_name, pseudo_trigger, [], target_specs, steps, "TRIGGERED")

    if card_id == "UA31BT_MMM_1_029" and text == "自分のフロントLのアクティブのキャラを1枚レストにする。そうした場合、カードを3枚引く。":
        target_specs, steps = _manual_single_target(
            "SELF",
            ["FRONT_LINE"],
            [],
            1,
            1,
            "selected_target",
            filters=[{"type": "CARD_STATE_IS", "value": "ACTIVE"}],
        )
        steps.extend(
            [
                {"type": "REST", "target_var": "selected_target"},
                {"type": "DRAW", "value": 3},
            ]
        )
        return _supported_ability(card, event_name, pseudo_trigger, [], target_specs, steps, "TRIGGERED")

    if card_id == "UA31BT_MMM_1_034" and text == "カードを2枚引き、自分の手札を1枚場外に置く。この効果でイベントカードを場外に置いた場合、自分のAPカードを1枚まで選び、アクティブにする。":
        target_specs, steps = _manual_single_target("SELF", ["HAND"], [], 1, 1, "discard_from_hand")
        steps.extend(
            [
                {"type": "MOVE_SELECTED_CARDS", "from_var": "discard_from_hand", "to": "OUTSIDE"},
                {"type": "ACTIVATE_AP_SLOTS", "value": 1, "requirements": [{"type": "CONTEXT_SELECTED_CARD_TYPE_IS", "context_var": "discard_from_hand", "value": "EVENT"}]},
            ]
        )
        return _supported_ability(
            card,
            event_name,
            pseudo_trigger,
            [],
            target_specs,
            [{"type": "DRAW", "value": 2}] + steps,
            "TRIGGERED",
        )

    if card_id == "UA31BT_MMM_1_028" and text == "このカードは自分の場に〈鹿目 まどか〉か〈アルティメットまどか〉がある場合のみ使用できる。":
        return _supported_ability(
            card,
            event_name,
            pseudo_trigger,
            [
                {
                    "type": "OR",
                    "requirements": [
                        {"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": "鹿目 まどか"},
                        {"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": "アルティメットまどか"},
                    ],
                }
            ],
            [],
            [],
            "TRIGGERED",
        )

    match = re.fullmatch(r"このカードは自分のフロントLに〈(.+)〉がある場合のみ使用できる。", text)
    if match:
        return _supported_ability(
            card,
            event_name,
            pseudo_trigger,
            [{"type": "CONTROLLER_HAS_NAME_IN_FRONT_LINE", "value": match.group(1)}],
            [],
            [],
            "TRIGGERED",
        )

    match = re.fullmatch(r"このカードは自分の場に〈(.+)〉がある場合のみ使用できる。", text)
    if match:
        return _supported_ability(
            card,
            event_name,
            pseudo_trigger,
            [{"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": match.group(1)}],
            [],
            [],
            "TRIGGERED",
        )
    match = re.fullmatch(r"このカードは自分の場にカード名に「(.+)」か「(.+)」を含むキャラがある場合のみ使用できる。", text)
    if match:
        return _supported_ability(
            card,
            event_name,
            pseudo_trigger,
            [
                {
                    "type": "OR",
                    "requirements": [
                        {"type": "CONTROLLER_HAS_NAME_CONTAINS_IN_FIELD", "value": match.group(1)},
                        {"type": "CONTROLLER_HAS_NAME_CONTAINS_IN_FIELD", "value": match.group(2)},
                    ],
                }
            ],
            [],
            [],
            "TRIGGERED",
        )

    match = re.fullmatch(r"〈(.+)〉は1ターンに1枚のみ使用できる。", text)
    if match:
        return _supported_ability(
            card,
            event_name,
            pseudo_trigger,
            [],
            [],
            [{"type": "SET_PLAYER_TURN_FLAG", "player": "SOURCE", "flag": _event_used_turn_flag(match.group(1)), "value": True}],
            "TRIGGERED",
        )

    if text == "自分のAPカードを2枚まで選び、アクティブにする。":
        return _supported_ability(
            card,
            event_name,
            pseudo_trigger,
            [],
            [],
            [{"type": "ACTIVATE_AP_SLOTS", "value": 2}],
            "TRIGGERED",
        )

    if text == "カードを1枚引く。":
        return _supported_ability(card, event_name, pseudo_trigger, [], [], [{"type": "DRAW", "value": 1}], "TRIGGERED")

    if text == "カードを2枚引く。":
        return _supported_ability(card, event_name, pseudo_trigger, [], [], [{"type": "DRAW", "value": 2}], "TRIGGERED")

    if text == "カードを2枚引く。相手は自身の手札を全て公開する。":
        return _supported_ability(card, event_name, pseudo_trigger, [], [], [{"type": "DRAW", "value": 2}], "TRIGGERED")

    if text == "自分のフロントLのキャラ全ては、このターン中、BP+1000。カードを1枚引く。":
        target_specs, select_steps = _auto_target_set(
            "SELF",
            ["FRONT_LINE"],
            requirements=[{"type": "CARD_TYPE_IS", "value": "CHARACTER"}],
            min_count=0,
            max_count=-1,
            store_as="all_front_chars",
        )
        return _supported_ability(
            card,
            event_name,
            pseudo_trigger,
            [],
            target_specs,
            select_steps
            + [
                {
                    "type": "FOR_EACH",
                    "items_var": "all_front_chars",
                    "current_var": "buff_target",
                    "steps": [{"type": "ADD_TEMP_BP_MODIFIER", "target_var": "buff_target", "value": 1000, "expires": "END_OF_TURN"}],
                },
                {"type": "DRAW", "value": 1},
            ],
            "TRIGGERED",
        )

    if text == "自分の山札の上から5枚見て、異なるカード名のキャラカードをそれぞれ1枚ずつ合計3枚まで公開し手札に加える。残りを望む順で山札の下に置く。":
        target_specs, steps = _preview_add_to_hand_then_reorder_steps(
            count=5,
            requirements=[{"type": "CARD_TYPE_IS", "value": "CHARACTER"}],
            min_count=0,
            max_count=3,
            distinct_by="CARD_NAME",
        )
        return _supported_ability(card, event_name, pseudo_trigger, [], target_specs, steps, "TRIGGERED")

    if text == "BP5000以下の相手のフロントLのキャラを1枚選び、相手の山札の下に置く。":
        target_specs, steps = _manual_single_target(
            "OPPONENT",
            ["FRONT_LINE"],
            [{"type": "CARD_BP_LTE", "value": 5000}],
            1,
            1,
            "selected_target",
        )
        steps.append(
            {
                "type": "MOVE_SELECTED_CARDS",
                "from_var": "selected_target",
                "to": "DECK",
                "target_player_mode": "CARD_CONTROLLER",
            }
        )
        return _supported_ability(card, event_name, pseudo_trigger, [], target_specs, steps, "TRIGGERED")

    if text == "BP5000以下の相手のフロントLのキャラを1枚選び、選んだキャラとこのカードをリムーブエリアに置く。自分のリムーブエリアから使用されている場合、このカードはリムーブエリアに置く代わりに自分の山札の下に置く。":
        target_specs, steps = _manual_single_target("OPPONENT", ["FRONT_LINE"], [{"type": "CARD_BP_LTE", "value": 5000}], 1, 1, "selected_target")
        steps.extend(
            [
                {"type": "MOVE_SELECTED_CARDS", "from_var": "selected_target", "to": "REMOVED"},
                {
                    "type": "MOVE_CARD",
                    "target_uid": "SOURCE_CARD",
                    "to": "DECK",
                    "requirements": [{"type": "SOURCE_ENTERED_FROM_ZONE", "value": "REMOVED"}],
                },
                {
                    "type": "MOVE_CARD",
                    "target_uid": "SOURCE_CARD",
                    "to": "REMOVED",
                    "requirements": [{"type": "NOT", "requirement": {"type": "SOURCE_ENTERED_FROM_ZONE", "value": "REMOVED"}}],
                },
            ]
        )
        return _supported_ability(card, event_name, pseudo_trigger, [], target_specs, steps, "TRIGGERED")

    if text == "BP5000以下の相手のフロントLのキャラを1枚選び、『レストにする。それは次の1回アクティブにならない』。自分の場に〈巴 マミ〉がある場合、『退場させる』に代えてもよい。":
        target_specs, steps = _manual_single_target("OPPONENT", ["FRONT_LINE"], [{"type": "CARD_BP_LTE", "value": 5000}], 1, 1, "selected_target")
        steps.extend(
            [
                {
                    "type": "MOVE_SELECTED_CARDS",
                    "from_var": "selected_target",
                    "to": "OUTSIDE",
                    "requirements": [{"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": "巴 マミ"}],
                },
                {
                    "type": "REST",
                    "target_var": "selected_target",
                    "requirements": [{"type": "NOT", "requirement": {"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": "巴 マミ"}}],
                },
                {
                    "type": "SET_CARD_FLAG",
                    "target_var": "selected_target",
                    "flag": "skip_next_ready_once",
                    "value": True,
                    "requirements": [{"type": "NOT", "requirement": {"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": "巴 マミ"}}],
                },
            ]
        )
        return _supported_ability(card, event_name, pseudo_trigger, [], target_specs, steps, "TRIGGERED")

    if text == "相手のフロントLのキャラを1枚選び、『レストにする』。自分の場に〈巴 マミ〉があり、自分の場外にイベントカードが2枚以上ある場合、『レストにする。それは次の1回アクティブにならない』に代わる。":
        target_specs, steps = _manual_single_target("OPPONENT", ["FRONT_LINE"], [], 1, 1, "selected_target")
        steps.extend(
            [
                {"type": "REST", "target_var": "selected_target"},
                {
                    "type": "SET_CARD_FLAG",
                    "target_var": "selected_target",
                    "flag": "skip_next_ready_once",
                    "value": True,
                    "requirements": [
                        {"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": "巴 マミ"},
                        {"type": "PLAYER_ZONE_CARD_COUNT_GTE", "player": "SELF", "zones": ["OUTSIDE"], "card_type": "EVENT", "value": 2},
                    ],
                },
            ]
        )
        return _supported_ability(card, event_name, pseudo_trigger, [], target_specs, steps, "TRIGGERED")

    if text == "カードを1枚引き、自分の手札を1枚場外に置く。その後、自分の場外にあるイベントカードの枚数×1000以下のBPの相手のフロントLのキャラを1枚まで選び、手札に戻す。":
        discard_specs, discard_steps = _manual_single_target("SELF", ["HAND"], [], 1, 1, "discard_from_hand")
        target_specs, steps = _manual_single_target(
            "OPPONENT",
            ["FRONT_LINE"],
            [
                {
                    "type": "CARD_BP_LTE_DYNAMIC",
                    "value_provider": {
                        "type": "PLAYER_ZONE_CARD_COUNT_MULTIPLIED",
                        "player": "SELF",
                        "zones": ["OUTSIDE"],
                        "card_type": "EVENT",
                        "multiplier": 1000,
                    },
                }
            ],
            0,
            1,
            "selected_target",
        )
        return _supported_ability(
            card,
            event_name,
            pseudo_trigger,
            [],
            discard_specs + target_specs,
            [
                {"type": "DRAW", "value": 1},
                *discard_steps,
                {"type": "MOVE_SELECTED_CARDS", "from_var": "discard_from_hand", "to": "OUTSIDE"},
                *steps,
                {"type": "MOVE_SELECTED_CARDS", "from_var": "selected_target", "to": "HAND", "target_player_mode": "CARD_CONTROLLER"},
            ],
            "TRIGGERED",
        )

    if text == "自分の手札のイベントカードを1枚場外に置く。そうした場合、このターン中、自分の手札にある全ての〈巴 マミ〉の必要エナジーを減らす。":
        target_specs, steps = _manual_single_target(
            "SELF",
            ["HAND"],
            [],
            1,
            1,
            "selected_event_discard",
            filters=[{"type": "CARD_TYPE_IS", "value": "EVENT"}],
        )
        steps.extend(
            [
                {"type": "MOVE_SELECTED_CARDS", "from_var": "selected_event_discard", "to": "OUTSIDE"},
                {
                    "type": "REGISTER_STATIC_MODIFIER",
                    "modifier_type": "HAND_PLAY_COST_ENERGY_DELTA",
                    "from_zone": "HAND",
                    "filters": [{"type": "NAME_IS", "value": "巴 マミ"}],
                    "value": -1,
                    "expires": "END_OF_TURN",
                },
            ]
        )
        return _supported_ability(card, event_name, pseudo_trigger, [], target_specs, steps, "TRIGGERED")

    if text == "自分のフロントLのアクティブのキャラを1枚レストにする。そうした場合、カードを3枚引く。":
        target_specs, steps = _manual_single_target(
            "SELF",
            ["FRONT_LINE"],
            [],
            1,
            1,
            "selected_target",
            filters=[{"type": "CARD_STATE_IS", "value": "ACTIVE"}],
        )
        steps.extend(
            [
                {"type": "REST", "target_var": "selected_target"},
                {"type": "DRAW", "value": 3},
            ]
        )
        return _supported_ability(card, event_name, pseudo_trigger, [], target_specs, steps, "TRIGGERED")

    if re.fullmatch(r"自分の場に〈(.+)〉がある場合、手札にあるこのカードの消費APを-1する。", text):
        return None
    if re.fullmatch(r"〈(.+)〉を選んで使用する場合、このカードの消費APを-1する。", text):
        return None
    if re.fullmatch(r"自分の場にカード名に「(.+)」を含むキャラがある場合、手札にあるこのカードの消費APを-1する。", text):
        return None

    if text == "自分のフロントLのキャラを1枚選び、このターン中、BP+2000と（インパクトの与えるダメージが+1され、インパクトを持たない場合、を得る）を与える。自分の場に〈暁美 ほむら〉がある場合、カードを1枚引く。":
        target_specs, steps = _manual_single_target("SELF", ["FRONT_LINE"], [], 1, 1, "selected_target")
        steps.extend(
            [
                {"type": "ADD_TEMP_BP_MODIFIER", "target_var": "selected_target", "value": 2000, "expires": "END_OF_TURN"},
                {"type": "ADD_TEMP_KEYWORD", "target_var": "selected_target", "keyword": "IMPACT_PLUS_1", "expires": "END_OF_TURN"},
                {
                    "type": "DRAW",
                    "value": 1,
                    "requirements": [{"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": "暁美 ほむら"}],
                },
            ]
        )
        return _supported_ability(card, event_name, pseudo_trigger, [], target_specs, steps, "TRIGGERED")

    if text == "『BP2000』以下の相手のフロントLのキャラを1枚選び、退場させる。自分の場の［特徴：ピュエラ・マギ・ホーリー・クインテット］1枚につき、この効果で選べるキャラのBPの範囲+1000。":
        target_specs, steps = _manual_single_target(
            "OPPONENT",
            ["FRONT_LINE"],
            [
                {
                    "type": "CARD_BP_LTE_DYNAMIC",
                    "value_provider": {
                        "type": "FIXED_PLUS_CONTROLLER_FIELD_CARD_COUNT_MULTIPLIED",
                        "value": 2000,
                        "trait": "ピュエラ・マギ・ホーリー・クインテット",
                        "multiplier": 1000,
                    },
                }
            ],
        )
        steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_target", "to": "OUTSIDE"})
        return _supported_ability(card, event_name, pseudo_trigger, [], target_specs, steps, "TRIGGERED")

    if text == "自分のフロントLのキャラを1枚選び、このターン中、BP+1000と（このキャラがこのターン初めてアタックした時、アクティブにする）を与える。":
        target_specs, steps = _manual_single_target("SELF", ["FRONT_LINE"], [], 1, 1, "selected_target")
        steps.extend(
            [
                {"type": "ADD_TEMP_BP_MODIFIER", "target_var": "selected_target", "value": 1000, "expires": "END_OF_TURN"},
                {"type": "ADD_TEMP_KEYWORD", "target_var": "selected_target", "keyword": "DOUBLE_ATTACK", "expires": "END_OF_TURN"},
            ]
        )
        return _supported_ability(card, event_name, pseudo_trigger, [], target_specs, steps, "TRIGGERED")

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
        reason = " / ".join(semantic_entry.get("unresolved_capabilities", []))
        return _unsupported_ability(card, event_name, pseudo_trigger, reason)
    return _unsupported_ability(card, event_name, pseudo_trigger, "当前原子要求/步骤模板尚未覆盖该文本模式。")


def _compile_passive_effect_legacy(card: dict, effect_entry: dict) -> dict | None:
    text = str(effect_entry.get("text", "")).strip()
    pseudo_trigger = {
        "source_label": effect_entry.get("source_label", ""),
        "effect_box": effect_entry.get("effect_box", "OUTER"),
        "text": text,
    }

    if text == "このターン中に自分がライフエリアにあるカードを手札に加えている場合、このキャラは（このキャラがこのターン初めてアタックした時、アクティブにする）を得る。":
        pseudo_trigger["trigger"] = "ON_ATTACK"
        return _supported_ability(
            card,
            "ON_ATTACK",
            pseudo_trigger,
            [{"type": "PLAYER_TURN_FLAG_TRUE", "player": "SELF", "flag": "life_card_added_to_hand"}],
            [],
            [{"type": "ADD_TEMP_KEYWORD", "target_uid": "SOURCE_CARD", "keyword": "DOUBLE_ATTACK", "expires": "END_OF_TURN"}],
        )

    if text == "2種類以上：このキャラがアタックしてブロックされなかった時、カードを1枚引く。":
        pseudo_trigger["trigger"] = "ON_BATTLE_END"
        return _supported_ability(
            card,
            "ON_BATTLE_END",
            pseudo_trigger,
            [
                {"type": "CONTROLLER_TRAIT_NAME_COUNT_GTE", "trait": "魔法少女", "value": 2},
                {"type": "CONTEXT_BATTLE_OUTCOME_IS", "value": "DIRECT_DAMAGE"},
            ],
            [],
            [{"type": "DRAW", "value": 1}],
        )

    if text == "4種類以上：このキャラはBP+1000と（アタックしてバトルに勝利した時、相手プレイヤーに1ダメージ）":
        pseudo_trigger["trigger"] = "ON_ATTACK"
        return _supported_ability(
            card,
            "ON_ATTACK",
            pseudo_trigger,
            [{"type": "CONTROLLER_TRAIT_NAME_COUNT_GTE", "trait": "魔法少女", "value": 4}],
            [],
            [
                {"type": "ADD_TEMP_BP_MODIFIER", "target_uid": "SOURCE_CARD", "value": 1000, "expires": "END_OF_TURN"},
                {"type": "ADD_TEMP_KEYWORD", "target_uid": "SOURCE_CARD", "keyword": "IMPACT", "expires": "END_OF_TURN"},
            ],
        )

    if text == "このキャラがアクティブの場合、このキャラの発生エナジー+。":
        pseudo_trigger["trigger"] = "PASSIVE"
        return _supported_ability(
            card,
            "PASSIVE",
            pseudo_trigger,
            [],
            [],
            [
                {
                    "type": "REGISTER_STATIC_MODIFIER",
                    "modifier_type": "ENERGY_BONUS",
                    "color": _primary_energy_color(card),
                    "value": 1,
                    "while": [{"type": "SOURCE_STATE_IS_ACTIVE"}],
                }
            ],
            "STATIC",
        )

    return None


@dataclass(frozen=True)
class _TemplateRule:
    name: str
    event_filter: str | tuple[str, ...]
    matcher: object
    builder: object
    priority: int = 0
    card_filter: object | None = None
    template_metadata: dict | None = None


_TEMPLATE_TELEMETRY_ENABLED = False
_TEMPLATE_HIT_COUNTS: dict[str, int] = {}
_TEMPLATE_FALLBACK_COUNTS: dict[str, int] = {}


def _record_template_hit(name: str) -> None:
    if not _TEMPLATE_TELEMETRY_ENABLED:
        return
    _TEMPLATE_HIT_COUNTS[name] = _TEMPLATE_HIT_COUNTS.get(name, 0) + 1


def _record_template_fallback(registry_name: str) -> None:
    if not _TEMPLATE_TELEMETRY_ENABLED:
        return
    _TEMPLATE_FALLBACK_COUNTS[registry_name] = _TEMPLATE_FALLBACK_COUNTS.get(registry_name, 0) + 1


def _event_matches(rule_event: str | tuple[str, ...], event_name: str) -> bool:
    if isinstance(rule_event, tuple):
        return event_name in rule_event
    return event_name == rule_event


def _always_match(_card: dict, _entry: dict, _text: str, _card_id: str):
    return {}


def _card_id_in(card_ids: list[str]):
    allowed = set(card_ids)
    return lambda card_id: card_id in allowed


def _build_preview_add_to_hand_template(
    card: dict,
    trigger_entry: dict,
    event_name: str,
    _text: str,
    _card_id: str,
    payload: dict,
) -> dict:
    params = payload["params"]
    target_specs, steps = _preview_add_to_hand_then_reorder_steps(
        count=params["count"],
        requirements=params.get("requirements"),
        filters=params.get("filters"),
        min_count=params.get("min_count", 0),
        max_count=params.get("max_count", 1),
        store_as=params.get("store_as", "selected_preview_cards"),
        distinct_by=params.get("distinct_by", ""),
        discard_after_add=params.get("discard_after_add", False),
    )
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _preview_add_to_hand_builder_factory(*, kind: str | None = None, **params):
    def _builder(card: dict, trigger_entry: dict, event_name: str, text: str, card_id: str, payload: dict) -> dict:
        return _build_preview_add_to_hand_template(
            card,
            trigger_entry,
            event_name,
            text,
            card_id,
            {
                "params": params,
                "kind": kind,
                "template_metadata": payload.get("template_metadata"),
            },
        )

    return _builder


def _preview_add_to_hand_energy_threshold_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    count = int(match.group(1))
    energy_threshold = int(match.group(2))
    return _build_preview_add_to_hand_template(
        card,
        trigger_entry,
        event_name,
        _text,
        _card_id,
        {
            "params": {
                "count": count,
                "requirements": [
                    {"type": "CARD_TYPE_IS", "value": "CHARACTER"},
                    {"type": "CARD_COST_ENERGY_LTE", "value": energy_threshold},
                ],
                "discard_after_add": True,
            },
            "template_metadata": payload.get("template_metadata"),
        },
    )


def _build_bp_remove_ability(
    card: dict,
    trigger_entry: dict,
    event_name: str,
    requirements: list[dict],
    *,
    min_count: int = 1,
    max_count: int = 1,
    kind: str | None = None,
    template_metadata: dict | None = None,
) -> dict:
    target_specs, steps = _manual_single_target("OPPONENT", ["FRONT_LINE"], requirements, min_count, max_count)
    steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_target", "to": "OUTSIDE"})
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        kind,
        template_metadata=template_metadata,
    )


def _build_bp_bounce_to_hand_ability(
    card: dict,
    trigger_entry: dict,
    event_name: str,
    requirements: list[dict],
    *,
    min_count: int = 1,
    max_count: int = 1,
    kind: str | None = None,
    template_metadata: dict | None = None,
) -> dict:
    target_specs, steps = _manual_single_target("OPPONENT", ["FRONT_LINE"], requirements, min_count, max_count)
    steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_target", "to": "HAND", "target_player_mode": "CARD_CONTROLLER"})
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        kind,
        template_metadata=template_metadata,
    )


def _bp_remove_from_match_builder_factory(*, min_count: int = 1, max_count: int = 1, kind: str | None = None):
    def _builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
        requirements = [{"type": "CARD_BP_LTE", "value": int(payload["match"].group(1))}]
        return _build_bp_remove_ability(
            card,
            trigger_entry,
            event_name,
            requirements,
            min_count=min_count,
            max_count=max_count,
            kind=kind,
            template_metadata=payload.get("template_metadata"),
        )

    return _builder


def _life_trigger_raid_choice_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        [],
        [{"type": "LIFE_TRIGGER_RAID_CHOICE"}],
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _bp_bounce_to_hand_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    requirements = [{"type": "CARD_BP_LTE", "value": int(payload["match"].group(1))}]
    max_count = int(payload["match"].group(2))
    return _build_bp_bounce_to_hand_ability(
        card,
        trigger_entry,
        event_name,
        requirements,
        min_count=max_count,
        max_count=max_count,
        kind=payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _bp_remove_dynamic_name_gate_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    requirements = [
        {
            "type": "CARD_BP_LTE_DYNAMIC",
            "value_provider": _conditional_value_provider(
                _fixed_value_provider(int(match.group(1))),
                [{"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": match.group(2)}],
                _fixed_value_provider(int(match.group(3))),
            ),
        }
    ]
    return _build_bp_remove_ability(
        card,
        trigger_entry,
        event_name,
        requirements,
        kind=payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _bp_remove_dynamic_name_contains_gate_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    requirements = [
        {
            "type": "CARD_BP_LTE_DYNAMIC",
            "value_provider": _conditional_value_provider(
                _fixed_value_provider(int(match.group(1))),
                [{"type": "CONTROLLER_HAS_NAME_CONTAINS_IN_FIELD", "value": match.group(2)}],
                _fixed_value_provider(int(match.group(3))),
            ),
        }
    ]
    return _build_bp_remove_ability(
        card,
        trigger_entry,
        event_name,
        requirements,
        kind=payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _build_bp_remove_to_removed_ability(
    card: dict,
    trigger_entry: dict,
    event_name: str,
    requirements: list[dict],
    *,
    min_count: int = 1,
    max_count: int = 1,
    kind: str | None = None,
    template_metadata: dict | None = None,
) -> dict:
    target_specs, steps = _manual_single_target("OPPONENT", ["FRONT_LINE"], requirements, min_count, max_count)
    steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_target", "to": "REMOVED"})
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        kind,
        template_metadata=template_metadata,
    )


def _bp_remove_to_removed_dynamic_name_gate_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    requirements = [
        {
            "type": "CARD_BP_LTE_DYNAMIC",
            "value_provider": _conditional_value_provider(
                _fixed_value_provider(int(match.group(1))),
                [{"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": match.group(2)}],
                _fixed_value_provider(int(match.group(3))),
            ),
        }
    ]
    return _build_bp_remove_to_removed_ability(
        card,
        trigger_entry,
        event_name,
        requirements,
        kind=payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _bp_remove_with_requirements_builder_factory(
    requirements: list[dict],
    *,
    min_count: int = 1,
    max_count: int = 1,
    kind: str | None = None,
):
    def _builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, _payload: dict) -> dict:
        return _build_bp_remove_ability(
            card,
            trigger_entry,
            event_name,
            requirements,
            min_count=min_count,
            max_count=max_count,
            kind=kind,
            template_metadata=_payload.get("template_metadata"),
        )

    return _builder


def _bp_sum_limit_remove_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    max_sum_bp = int(match.group(1))
    max_count = int(match.group(2))
    target_specs, _ = _manual_card_set(
        "OPPONENT",
        ["FRONT_LINE"],
        min_count=0,
        max_count=max_count,
        store_as="selected_targets",
        constraints={"max_count": max_count, "max_sum_bp": max_sum_bp},
    )
    composite_steps: list[dict] = [
        {
            "type": "SELECT_TARGETS_BY_COMBINATION",
            "var": "selected_targets",
            "target": {
                "type": "CARD_SET",
                "owner": "OPPONENT",
                "zones": ["FRONT_LINE"],
                "filters": [],
                "requirements": [],
                "min": 0,
                "max": max_count,
                "selection_mode": "MANUAL",
                "manual": True,
                "selection_constraints": {"max_count": max_count, "max_sum_bp": max_sum_bp},
            },
        },
        {"type": "MOVE_SELECTED_CARDS", "from_var": "selected_targets", "to": "OUTSIDE"},
    ]
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        composite_steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _bp_sum_limit_remove_dynamic_energy_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    multiplier = int(match.group(1))
    max_count = int(match.group(2))
    constraints = {
        "max_count": max_count,
        "max_sum_provider": {
            "type": "PLAYER_ZONE_CARD_COUNT_MULTIPLIED",
            "player": "SELF",
            "zones": ["ENERGY_LINE"],
            "multiplier": multiplier,
        },
    }
    composite_steps: list[dict] = [
        {
            "type": "SELECT_TARGETS_BY_COMBINATION",
            "var": "selected_targets",
            "target": {
                "type": "CARD_SET",
                "owner": "OPPONENT",
                "zones": ["FRONT_LINE"],
                "filters": [],
                "requirements": [],
                "min": 0,
                "max": max_count,
                "selection_mode": "MANUAL",
                "manual": True,
                "selection_constraints": constraints,
            },
        },
        {"type": "MOVE_SELECTED_CARDS", "from_var": "selected_targets", "to": "OUTSIDE"},
    ]
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        [],
        composite_steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _compile_branch_sub_steps(card: dict, trigger_entry: dict, branch_text: str) -> list[dict]:
    branch_text = str(branch_text).strip().lstrip("・").strip()
    if not branch_text:
        return []
    draw_match = re.fullmatch(r"カードを(\d+)枚引く。", branch_text)
    if draw_match:
        return [{"type": "DRAW", "value": int(draw_match.group(1))}]
    damage_match = re.fullmatch(r"相手に(\d+)ダメージ。", branch_text)
    if damage_match:
        return [{"type": "DEAL_DAMAGE", "target_player": "OPPONENT", "value": int(damage_match.group(1))}]
    temp_bp_match = re.fullmatch(r"このターン中、自分のフロントLのキャラ1枚のBP\+(\d+)。", branch_text)
    if temp_bp_match:
        _, select_steps = _manual_single_target("SELF", ["FRONT_LINE"], [], 1, 1)
        return select_steps + [{"type": "ADD_TEMP_BP_MODIFIER", "target_var": "selected_target", "value": int(temp_bp_match.group(1)), "expires": "END_OF_TURN"}]
    compiled = _compile_event_effect(
        card,
        {"source_label": trigger_entry.get("source_label", ""), "effect_box": trigger_entry.get("effect_box", "OUTER"), "text": branch_text},
        {},
    )
    if compiled is None or str(compiled.get("status", "")) != "SUPPORTED":
        compiled = _compile_trigger(
            card,
            {
                "trigger": str(trigger_entry.get("trigger", "ON_ENTER")),
                "source_label": trigger_entry.get("source_label", ""),
                "effect_box": trigger_entry.get("effect_box", "OUTER"),
                "text": branch_text,
            },
            {},
        )
    if compiled is None or str(compiled.get("status", "")) != "SUPPORTED":
        return [{"type": "PENDING_BRANCH_EFFECT", "text": branch_text}]
    steps = deepcopy(compiled.get("steps", []))
    requirements = deepcopy(compiled.get("requirements", []))
    if requirements:
        return [{"type": "RUN_COMPOSITE_IF", "if_requirements": requirements, "steps": steps}]
    return steps or [{"type": "PENDING_BRANCH_EFFECT", "text": branch_text}]


def _preview_add_to_hand_name_contains_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    return _build_preview_add_to_hand_template(
        card,
        trigger_entry,
        event_name,
        _text,
        _card_id,
        {
            "params": {
                "count": int(match.group(1)),
                "requirements": [{"type": "CARD_TYPE_IS", "value": "CHARACTER"}],
                "filters": [{"type": "NAME_CONTAINS", "value": match.group(2)}],
                "discard_after_add": True,
            },
            "template_metadata": payload.get("template_metadata"),
        },
    )


def _preview_top_then_choose_top_or_bottom_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    target_specs = []
    steps = [
        {"type": "PREVIEW_TOP_DECK", "count": 1, "var": "preview_cards"},
        {
            "type": "SELECT_TARGETS",
            "var": "selected_preview_destination",
            "target": {
                "type": "OPTION_SET",
                "options": ["TOP", "BOTTOM"],
                "min": 1,
                "max": 1,
                "selection_mode": "MANUAL",
                "manual": True,
            },
        },
        {
            "type": "MOVE_SELECTED_CARDS",
            "from_var": "preview_cards",
            "to": "DECK",
            "to_position_from_var": "selected_preview_destination",
            "target_player_mode": "SOURCE",
        },
    ]
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _conditional_preview_top_then_choose_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    ability = _preview_top_then_choose_top_or_bottom_builder(card, trigger_entry, event_name, _text, _card_id, payload)
    ability["requirements"] = [{"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": match.group(1)}]
    return ability


def _conditional_draw_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    requirements: list[dict] = []
    if match.group(1):
        requirements.append({"type": "CONTROLLER_OTHER_CARDS_COUNT_GTE", "value": int(match.group(1))})
    elif match.group(2):
        requirements.append({"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": match.group(2)})
    steps = [{"type": "DRAW", "value": int(match.group(3))}]
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        requirements,
        [],
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _bp_debuff_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    threshold = int(match.group(1))
    debuff = int(match.group(2))
    target_specs, steps = _manual_single_target(
        "OPPONENT",
        ["FRONT_LINE"],
        [{"type": "NOT", "requirement": {"type": "CARD_BP_LTE", "value": threshold - 1}}],
        1,
        1,
        "selected_target",
    )
    steps.append({"type": "ADD_TEMP_BP_MODIFIER", "target_var": "selected_target", "value": -debuff, "expires": "END_OF_TURN"})
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _conditional_bp_debuff_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    threshold = int(match.group(2))
    debuff = int(match.group(3))
    target_specs, steps = _manual_single_target(
        "OPPONENT",
        ["FRONT_LINE"],
        [{"type": "NOT", "requirement": {"type": "CARD_BP_LTE", "value": threshold - 1}}],
        0,
        1,
        "selected_target",
    )
    steps.append({"type": "ADD_TEMP_BP_MODIFIER", "target_var": "selected_target", "value": -debuff, "expires": "END_OF_TURN"})
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [{"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": match.group(1)}],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _optional_discard_ready_self_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    discard_count = int(match.group(1))
    target_specs, steps = _manual_single_target("SELF", ["HAND"], [], 0, discard_count, "selected_discard")
    steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_discard", "to": "OUTSIDE"})
    steps.append(
        {
            "type": "ACTIVATE_CARD",
            "target_uid": "SOURCE_CARD",
            "requirements": [{"type": "CONTEXT_VAR_NON_EMPTY", "var": "selected_discard"}],
        }
    )
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _self_other_bp_modifier_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    target_specs, select_steps = _manual_single_target(
        "SELF",
        ["FRONT_LINE", "BACK_LINE"],
        [{"type": "CARD_UID_NE", "value": "SOURCE_CARD"}],
        1,
        1,
    )
    steps = select_steps + [{"type": "ADD_TEMP_BP_MODIFIER", "target_var": "selected_target", "value": int(match.group(1)), "expires": "END_OF_TURN"}]
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _preview_top_two_reorder_top_bottom_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    target_specs, top_steps = _manual_context_target("preview_cards", min_count=0, max_count=2, store_as="selected_top_cards")
    steps = [
        {"type": "PREVIEW_TOP_DECK", "count": 2, "var": "preview_cards"},
    ] + top_steps + [
        {
            "type": "MOVE_SELECTED_CARDS",
            "from_var": "selected_top_cards",
            "to": "DECK",
            "to_position": "TOP",
            "remove_from_var": "preview_cards",
            "target_player_mode": "SOURCE",
        },
        {
            "type": "MOVE_SELECTED_CARDS",
            "from_var": "preview_cards",
            "to": "DECK",
            "to_position": "BOTTOM",
            "target_player_mode": "SOURCE",
        },
    ]
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _preview_add_character_cards_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    return _build_preview_add_to_hand_template(
        card,
        trigger_entry,
        event_name,
        _text,
        _card_id,
        {
            "params": {
                "count": int(match.group(1)),
                "requirements": [{"type": "CARD_TYPE_IS", "value": "CHARACTER"}],
                "max_count": int(match.group(2)),
            },
            "template_metadata": payload.get("template_metadata"),
        },
    )


def _self_other_bp_modifier_conditional_upgrade_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    target_specs, select_steps = _manual_single_target(
        "SELF",
        ["FRONT_LINE", "BACK_LINE"],
        [{"type": "CARD_UID_NE", "value": "SOURCE_CARD"}],
        0,
        1,
    )
    steps = select_steps + [
        {
            "type": "ADD_TEMP_BP_MODIFIER",
            "target_var": "selected_target",
            "value_provider": _conditional_value_provider(
                _fixed_value_provider(int(match.group(1))),
                [{"type": "PLAYER_ZONE_CARD_COUNT_GTE", "player": "SELF", "zones": ["FRONT_LINE", "ENERGY_LINE"], "value": int(match.group(2))}],
                _fixed_value_provider(int(match.group(3))),
            ),
            "expires": "END_OF_TURN",
        }
    ]
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _rest_and_lock_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    target_specs, steps = _manual_single_target("OPPONENT", ["FRONT_LINE"], [], 0, 1, "selected_target")
    steps.extend(
        [
            {"type": "REST", "target_var": "selected_target"},
            {"type": "SET_CARD_FLAG", "target_var": "selected_target", "flag": "skip_next_ready_once", "value": True},
        ]
    )
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _rest_and_lock_then_conditional_debuff_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    target_specs, steps = _manual_single_target("OPPONENT", ["FRONT_LINE"], [], 0, 1, "selected_target")
    steps.extend(
        [
            {"type": "REST", "target_var": "selected_target"},
            {
                "type": "ADD_TEMP_BP_MODIFIER",
                "target_var": "selected_target",
                "value_provider": _conditional_value_provider(
                    _fixed_value_provider(0),
                    [{"type": "NOT", "requirement": {"type": "CARD_BP_LTE", "value": int(match.group(1)) - 1}}],
                    _fixed_value_provider(-int(match.group(2))),
                ),
                "expires": "UNTIL_NEXT_SELF_TURN_START",
            },
        ]
    )
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _conditional_rest_or_remove_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    target_specs, steps = _manual_single_target(
        "OPPONENT",
        ["FRONT_LINE"],
        [{"type": "CARD_BP_LTE", "value": int(match.group(1))}],
        1,
        1,
        "selected_target",
    )
    has_name_req = {"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": match.group(2)}
    steps.extend(
        [
            {"type": "MOVE_SELECTED_CARDS", "from_var": "selected_target", "to": "OUTSIDE", "requirements": [has_name_req]},
            {"type": "REST", "target_var": "selected_target", "requirements": [{"type": "NOT", "requirement": has_name_req}]},
            {
                "type": "SET_CARD_FLAG",
                "target_var": "selected_target",
                "flag": "skip_next_ready_once",
                "value": True,
                "requirements": [{"type": "NOT", "requirement": has_name_req}],
            },
        ]
    )
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _draw_discard_then_outside_summon_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    discard_specs, discard_steps = _manual_single_target("SELF", ["HAND"], [], int(match.group(2)), int(match.group(2)), "selected_discard")
    summon_specs, summon_steps = _manual_single_target(
        "SELF",
        ["OUTSIDE"],
        [
            {"type": "CARD_TYPE_IS", "value": "CHARACTER"},
            {"type": "CARD_COST_ENERGY_LTE", "value": int(match.group(3))},
            {"type": "CARD_COLOR_IS", "value": "YELLOW"},
        ],
        0,
        1,
        "selected_summon",
    )
    steps = [{"type": "DRAW", "value": int(match.group(1))}] + discard_steps + [{"type": "MOVE_SELECTED_CARDS", "from_var": "selected_discard", "to": "OUTSIDE"}] + summon_steps + [
        {
            "type": "PLAY_SELECTED_CARDS",
            "from_var": "selected_summon",
            "to": "FRONT_LINE",
            "state": "RESTED",
            "ignore_play_timing": True,
            "allow_current_zone": False,
        }
    ]
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        discard_specs + summon_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _buff_draw_then_conditional_ready_ap_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    target_specs, steps = _manual_single_target("SELF", ["FRONT_LINE", "BACK_LINE"], [], 0, 1, "selected_target")
    steps.extend(
        [
            {"type": "ADD_TEMP_BP_MODIFIER", "target_var": "selected_target", "value": int(match.group(1)), "expires": "END_OF_TURN"},
            {"type": "DRAW", "value": int(match.group(2))},
            {
                "type": "ACTIVATE_AP_SLOTS",
                "count": 1,
                "requirements": [{"type": "CONTROLLER_TRAIT_NAME_COUNT_GTE", "trait": match.group(3), "value": int(match.group(4))}],
            },
        ]
    )
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _energy_to_front_if_slot_open_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    target_specs, steps = _manual_single_target(
        "SELF",
        ["ENERGY_LINE"],
        [{"type": "NAME_CONTAINS", "value": match.group(1)}, {"type": "NOT_SOURCE_CARD"}],
        0,
        1,
        "selected_target",
    )
    steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_target", "to": "FRONT_LINE"})
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [{"type": "NOT", "requirement": {"type": "PLAYER_ZONE_CARD_COUNT_GTE", "player": "SELF", "zones": ["FRONT_LINE"], "value": 4}}],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _bp_remove_then_choice_branch_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    target_specs, remove_steps = _manual_single_target("OPPONENT", ["FRONT_LINE"], [{"type": "CARD_BP_LTE", "value": int(match.group(1))}], 1, 1, "selected_remove_target")
    remove_steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_remove_target", "to": "OUTSIDE"})
    branch_ability = _branch_choice_builder(card, trigger_entry, event_name, "以下から1つ選ぶ。", _card_id, payload)
    steps = remove_steps + branch_ability.get("steps", [])
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs + branch_ability.get("target_specs", []),
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _buff_then_conditional_activate_named_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    target_specs, steps = _manual_single_target(
        "SELF",
        ["FRONT_LINE", "BACK_LINE"],
        [{"type": "CARD_UID_NE", "value": "SOURCE_CARD"}],
        0,
        1,
        "target_uid",
    )
    steps.extend(
        [
            {"type": "ADD_TEMP_BP_MODIFIER", "target_var": "target_uid", "value": int(match.group(1)), "expires": "END_OF_TURN"},
            {
                "type": "ACTIVATE_CARD",
                "target_var": "target_uid",
                "requirements": [{"type": "CONTEXT_TARGET_NAME_IS", "value": match.group(2)}],
            },
        ]
    )
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _bp_remove_then_optional_pay_ap_add_outside_name_contains_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    remove_specs, remove_steps = _manual_single_target(
        "OPPONENT",
        ["FRONT_LINE"],
        [{"type": "CARD_BP_LTE", "value": int(match.group(1))}],
        1,
        1,
        "selected_remove_target",
    )
    remove_steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_remove_target", "to": "OUTSIDE"})
    gate_requirements = [
        {"type": "CONTROLLER_HAS_NAME_CONTAINS_IN_FRONT_LINE", "value": match.group(2)},
        {"type": "CONTROLLER_HAS_NAME_CONTAINS_IN_FRONT_LINE", "value": match.group(3)},
    ]
    search_specs, search_steps = _manual_single_target(
        "SELF",
        ["OUTSIDE"],
        [
            {"type": "CARD_TYPE_IS", "value": "CHARACTER"},
            {"type": "OR", "filters": [{"type": "NAME_CONTAINS", "value": match.group(5)}, {"type": "NAME_CONTAINS", "value": match.group(6)}]},
        ],
        0,
        1,
        "selected_outside_card",
    )
    steps = remove_steps + [
        {
            "type": "SELECT_TARGETS",
            "var": "selected_optional_ap_payment",
            "target": {
                "type": "OPTION_SET",
                "options": ["PAY_AP", "SKIP"],
                "min": 1,
                "max": 1,
                "selection_mode": "MANUAL",
                "manual": True,
            },
            "requirements": gate_requirements,
        },
        {
            "type": "PAY_AP_COST",
            "value": int(match.group(4)),
            "requirements": gate_requirements + [{"type": "CONTEXT_VALUE_IS", "var": "selected_optional_ap_payment", "value": "PAY_AP"}],
        },
    ] + [
        dict(step, requirements=gate_requirements + [{"type": "CONTEXT_VALUE_IS", "var": "selected_optional_ap_payment", "value": "PAY_AP"}])
        for step in search_steps
    ] + [
        {
            "type": "MOVE_SELECTED_CARDS",
            "from_var": "selected_outside_card",
            "to": "HAND",
            "requirements": gate_requirements + [{"type": "CONTEXT_VALUE_IS", "var": "selected_optional_ap_payment", "value": "PAY_AP"}],
        }
    ]
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        remove_specs + search_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _outside_character_to_hand_optional_rest_named_ready_ap_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    hand_specs, hand_steps = _manual_single_target(
        "SELF",
        ["OUTSIDE"],
        [{"type": "CARD_TYPE_IS", "value": "CHARACTER"}],
        1,
        1,
        "selected_outside_card",
    )
    rest_specs, rest_steps = _manual_single_target(
        "SELF",
        ["FRONT_LINE"],
        [{"type": "CARD_NAME_IS", "value": match.group(1)}, {"type": "CARD_STATE_IS", "state": "ACTIVE"}],
        0,
        1,
        "selected_rest_target",
    )
    steps = hand_steps + [
        {"type": "MOVE_SELECTED_CARDS", "from_var": "selected_outside_card", "to": "HAND"},
    ] + rest_steps + [
        {"type": "REST", "target_var": "selected_rest_target"},
        {
            "type": "ACTIVATE_AP_SLOTS",
            "count": 1,
            "requirements": [{"type": "CONTEXT_VAR_NON_EMPTY", "var": "selected_rest_target"}],
        },
    ]
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        hand_specs + rest_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _preview_name_contains_dual_then_conditional_ready_ap_builder(card: dict, trigger_entry: dict, event_name: str, text: str, card_id: str, payload: dict) -> dict:
    match = payload["match"]
    ability = _build_preview_add_to_hand_template(
        card,
        trigger_entry,
        event_name,
        text,
        card_id,
        {
            "params": {
                "count": int(match.group(1)),
                "requirements": [{"type": "CARD_TYPE_IS", "value": "CHARACTER"}],
                "filters": [{"type": "OR", "filters": [{"type": "NAME_CONTAINS", "value": match.group(2)}, {"type": "NAME_CONTAINS", "value": match.group(3)}]}],
            },
            "template_metadata": payload.get("template_metadata"),
        },
    )
    ability.setdefault("steps", []).append(
        {
            "type": "ACTIVATE_AP_SLOTS",
            "count": 1,
            "requirements": [
                {"type": "CONTROLLER_HAS_NAME_CONTAINS_IN_FIELD", "value": match.group(4)},
                {"type": "CONTROLLER_HAS_NAME_CONTAINS_IN_FIELD", "value": match.group(5)},
            ],
        }
    )
    return ability


def _move_to_deck_top_or_bottom_with_name_gate_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    target_specs, steps = _manual_single_target(
        "OPPONENT",
        ["FRONT_LINE"],
        [{"type": "CARD_BP_LTE", "value": int(match.group(1))}],
        1,
        1,
        "selected_target",
    )
    steps.append(
        {
            "type": "SELECT_TARGETS",
            "var": "selected_deck_position",
            "target": {
                "type": "OPTION_SET",
                "options": ["TOP", "BOTTOM"],
                "min": 1,
                "max": 1,
                "selection_mode": "MANUAL",
                "manual": True,
            },
        }
    )
    steps.append(
        {
            "type": "MOVE_SELECTED_CARDS",
            "from_var": "selected_target",
            "to": "DECK",
            "target_player_mode": "CARD_CONTROLLER",
            "to_position_from_var": "selected_deck_position",
        }
    )
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _named_buff_then_draw_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    target_specs, steps = _manual_single_target(
        "SELF",
        ["FRONT_LINE", "BACK_LINE"],
        [{"type": "CARD_NAME_IS", "value": match.group(1)}],
        0,
        1,
        "selected_target",
    )
    steps.extend(
        [
            {"type": "ADD_TEMP_BP_MODIFIER", "target_var": "selected_target", "value": int(match.group(2)), "expires": "END_OF_TURN"},
            {"type": "DRAW", "value": int(match.group(3))},
        ]
    )
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _conditional_bp_replace_marker_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [{"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": match.group(1)}],
        [],
        [{"type": "SET_CONTEXT_FLAG", "var": "dynamic_bp_threshold_replaced", "value": True}],
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _dual_buff_with_optional_keyword_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    target_specs, steps = _manual_single_target(
        "SELF",
        ["FRONT_LINE"],
        [{"type": "CARD_NAME_IS", "value": match.group(1)}],
        1,
        1,
        "selected_summon",
    )
    steps.extend(
        [
            {"type": "ADD_TEMP_BP_MODIFIER", "target_var": "selected_target", "value": int(match.group(2)), "expires": "END_OF_TURN"},
            {"type": "ADD_TEMP_BP_MODIFIER", "target_uid": "SOURCE_CARD", "value": int(match.group(2)), "expires": "END_OF_TURN"},
        ]
    )
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _rest_active_other_then_source_gain_placeholder_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    target_specs, steps = _manual_single_target(
        "SELF",
        ["FRONT_LINE"],
        [{"type": "NOT_SOURCE_CARD"}, {"type": "CARD_STATE_IS", "state": "ACTIVE"}],
        1,
        1,
        "selected_target",
    )
    steps.append({"type": "REST", "target_var": "selected_target"})
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _draw_activate_name_contains_and_named_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    first_specs, first_steps = _manual_single_target(
        "SELF",
        ["FRONT_LINE"],
        [{"type": "NAME_CONTAINS", "value": match.group(2)}],
        0,
        1,
        "selected_first_target",
    )
    second_specs, second_steps = _manual_single_target(
        "SELF",
        ["FRONT_LINE"],
        [{"type": "CARD_NAME_IS", "value": match.group(4)}],
        0,
        1,
        "selected_second_target",
    )
    steps = [{"type": "DRAW", "value": int(match.group(1))}] + first_steps + [
        {"type": "ACTIVATE_CARD", "target_var": "selected_first_target"},
        {"type": "ADD_TEMP_KEYWORD", "target_var": "selected_first_target", "keyword": "IMPACT_PLUS_1", "expires": "END_OF_TURN"},
    ] + second_steps + [{"type": "ACTIVATE_CARD", "target_var": "selected_second_target"}]
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        first_specs + second_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _bp_remove_then_choice_branch_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    target_specs, remove_steps = _manual_single_target("OPPONENT", ["FRONT_LINE"], [{"type": "CARD_BP_LTE", "value": int(match.group(1))}], 1, 1, "selected_remove_target")
    remove_steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_remove_target", "to": "OUTSIDE"})
    branch_ability = _branch_choice_builder(card, trigger_entry, event_name, "以下から1つ選ぶ。", _card_id, payload)
    steps = remove_steps + branch_ability.get("steps", [])
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs + branch_ability.get("target_specs", []),
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _preview_top_two_reorder_top_bottom_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    target_specs, top_steps = _manual_context_target("preview_cards", min_count=0, max_count=2, store_as="selected_top_cards")
    steps = [
        {"type": "PREVIEW_TOP_DECK", "count": 2, "var": "preview_cards"},
    ] + top_steps + [
        {
            "type": "MOVE_SELECTED_CARDS",
            "from_var": "selected_top_cards",
            "to": "DECK",
            "to_position": "TOP",
            "remove_from_var": "preview_cards",
            "target_player_mode": "SOURCE",
        },
        {
            "type": "MOVE_SELECTED_CARDS",
            "from_var": "preview_cards",
            "to": "DECK",
            "to_position": "BOTTOM",
            "target_player_mode": "SOURCE",
        },
    ]
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _preview_add_character_cards_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    return _build_preview_add_to_hand_template(
        card,
        trigger_entry,
        event_name,
        _text,
        _card_id,
        {
            "params": {
                "count": int(match.group(1)),
                "requirements": [{"type": "CARD_TYPE_IS", "value": "CHARACTER"}],
                "max_count": int(match.group(2)),
            },
            "template_metadata": payload.get("template_metadata"),
        },
    )


def _self_other_bp_modifier_conditional_upgrade_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    target_specs, select_steps = _manual_single_target(
        "SELF",
        ["FRONT_LINE", "BACK_LINE"],
        [{"type": "CARD_UID_NE", "value": "SOURCE_CARD"}],
        0,
        1,
    )
    steps = select_steps + [
        {
            "type": "ADD_TEMP_BP_MODIFIER",
            "target_var": "selected_target",
            "value_provider": _conditional_value_provider(
                _fixed_value_provider(int(match.group(1))),
                [{"type": "PLAYER_ZONE_CARD_COUNT_GTE", "player": "SELF", "zones": ["FRONT_LINE", "ENERGY_LINE"], "value": int(match.group(2))}],
                _fixed_value_provider(int(match.group(3))),
            ),
            "expires": "END_OF_TURN",
        }
    ]
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _rest_and_lock_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    target_specs, steps = _manual_single_target("OPPONENT", ["FRONT_LINE"], [], 0, 1, "selected_target")
    steps.extend(
        [
            {"type": "REST", "target_var": "selected_target"},
            {"type": "SET_CARD_FLAG", "target_var": "selected_target", "flag": "skip_next_ready_once", "value": True},
        ]
    )
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _rest_and_lock_then_conditional_debuff_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    target_specs, steps = _manual_single_target("OPPONENT", ["FRONT_LINE"], [], 0, 1, "selected_target")
    steps.extend(
        [
            {"type": "REST", "target_var": "selected_target"},
            {
                "type": "ADD_TEMP_BP_MODIFIER",
                "target_var": "selected_target",
                "value_provider": _conditional_value_provider(
                    _fixed_value_provider(0),
                    [{"type": "NOT", "requirement": {"type": "CARD_BP_LTE", "value": int(match.group(1)) - 1}}],
                    _fixed_value_provider(-int(match.group(2))),
                ),
                "expires": "UNTIL_NEXT_SELF_TURN_START",
            },
        ]
    )
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _conditional_rest_or_remove_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    target_specs, steps = _manual_single_target(
        "OPPONENT",
        ["FRONT_LINE"],
        [{"type": "CARD_BP_LTE", "value": int(match.group(1))}],
        1,
        1,
        "selected_target",
    )
    has_name_req = {"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": match.group(2)}
    steps.extend(
        [
            {"type": "MOVE_SELECTED_CARDS", "from_var": "selected_target", "to": "OUTSIDE", "requirements": [has_name_req]},
            {"type": "REST", "target_var": "selected_target", "requirements": [{"type": "NOT", "requirement": has_name_req}]},
            {
                "type": "SET_CARD_FLAG",
                "target_var": "selected_target",
                "flag": "skip_next_ready_once",
                "value": True,
                "requirements": [{"type": "NOT", "requirement": has_name_req}],
            },
        ]
    )
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _draw_discard_then_outside_summon_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    discard_specs, discard_steps = _manual_single_target("SELF", ["HAND"], [], int(match.group(2)), int(match.group(2)), "selected_discard")
    summon_specs, summon_steps = _manual_single_target(
        "SELF",
        ["OUTSIDE"],
        [
            {"type": "CARD_TYPE_IS", "value": "CHARACTER"},
            {"type": "CARD_COST_ENERGY_LTE", "value": int(match.group(3))},
            {"type": "CARD_COLOR_IS", "value": "YELLOW"},
        ],
        0,
        1,
        "selected_summon",
    )
    steps = [{"type": "DRAW", "value": int(match.group(1))}] + discard_steps + [{"type": "MOVE_SELECTED_CARDS", "from_var": "selected_discard", "to": "OUTSIDE"}] + summon_steps + [
        {
            "type": "PLAY_SELECTED_CARDS",
            "from_var": "selected_summon",
            "to": "FRONT_LINE",
            "state": "RESTED",
            "ignore_play_timing": True,
            "allow_current_zone": False,
        }
    ]
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        discard_specs + summon_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _buff_draw_then_conditional_ready_ap_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    target_specs, steps = _manual_single_target("SELF", ["FRONT_LINE", "BACK_LINE"], [], 0, 1, "selected_target")
    steps.extend(
        [
            {"type": "ADD_TEMP_BP_MODIFIER", "target_var": "selected_target", "value": int(match.group(1)), "expires": "END_OF_TURN"},
            {"type": "DRAW", "value": int(match.group(2))},
            {
                "type": "ACTIVATE_AP_SLOTS",
                "count": 1,
                "requirements": [{"type": "CONTROLLER_TRAIT_NAME_COUNT_GTE", "trait": match.group(3), "value": int(match.group(4))}],
            },
        ]
    )
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _energy_to_front_if_slot_open_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    target_specs, steps = _manual_single_target(
        "SELF",
        ["ENERGY_LINE"],
        [{"type": "NAME_CONTAINS", "value": match.group(1)}, {"type": "NOT_SOURCE_CARD"}],
        0,
        1,
        "selected_target",
    )
    steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_target", "to": "FRONT_LINE"})
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [{"type": "NOT", "requirement": {"type": "PLAYER_ZONE_CARD_COUNT_GTE", "player": "SELF", "zones": ["FRONT_LINE"], "value": 4}}],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _bp_remove_then_choice_branch_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    target_specs, remove_steps = _manual_single_target("OPPONENT", ["FRONT_LINE"], [{"type": "CARD_BP_LTE", "value": int(match.group(1))}], 1, 1, "selected_remove_target")
    remove_steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_remove_target", "to": "OUTSIDE"})
    branch_ability = _branch_choice_builder(card, trigger_entry, event_name, "以下から1つ選ぶ。", _card_id, payload)
    steps = remove_steps + branch_ability.get("steps", [])
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs + branch_ability.get("target_specs", []),
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _buff_then_conditional_activate_named_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    target_specs, steps = _manual_single_target(
        "SELF",
        ["FRONT_LINE", "BACK_LINE"],
        [{"type": "CARD_UID_NE", "value": "SOURCE_CARD"}],
        0,
        1,
        "target_uid",
    )
    steps.extend(
        [
            {"type": "ADD_TEMP_BP_MODIFIER", "target_var": "target_uid", "value": int(match.group(1)), "expires": "END_OF_TURN"},
            {
                "type": "ACTIVATE_CARD",
                "target_var": "target_uid",
                "requirements": [{"type": "CONTEXT_TARGET_NAME_IS", "value": match.group(2)}],
            },
        ]
    )
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _bp_remove_then_optional_pay_ap_add_outside_name_contains_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    remove_specs, remove_steps = _manual_single_target(
        "OPPONENT",
        ["FRONT_LINE"],
        [{"type": "CARD_BP_LTE", "value": int(match.group(1))}],
        1,
        1,
        "selected_remove_target",
    )
    remove_steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_remove_target", "to": "OUTSIDE"})
    gate_requirements = [
        {"type": "CONTROLLER_HAS_NAME_CONTAINS_IN_FRONT_LINE", "value": match.group(2)},
        {"type": "CONTROLLER_HAS_NAME_CONTAINS_IN_FRONT_LINE", "value": match.group(3)},
    ]
    search_specs, search_steps = _manual_single_target(
        "SELF",
        ["OUTSIDE"],
        [
            {"type": "CARD_TYPE_IS", "value": "CHARACTER"},
            {"type": "OR", "filters": [{"type": "NAME_CONTAINS", "value": match.group(5)}, {"type": "NAME_CONTAINS", "value": match.group(6)}]},
        ],
        0,
        1,
        "selected_outside_card",
    )
    steps = remove_steps + [
        {
            "type": "SELECT_TARGETS",
            "var": "selected_optional_ap_payment",
            "target": {
                "type": "OPTION_SET",
                "options": ["PAY_AP", "SKIP"],
                "min": 1,
                "max": 1,
                "selection_mode": "MANUAL",
                "manual": True,
            },
            "requirements": gate_requirements,
        },
        {
            "type": "PAY_AP_COST",
            "value": int(match.group(4)),
            "requirements": gate_requirements + [{"type": "CONTEXT_VALUE_IS", "var": "selected_optional_ap_payment", "value": "PAY_AP"}],
        },
    ] + [
        dict(step, requirements=gate_requirements + [{"type": "CONTEXT_VALUE_IS", "var": "selected_optional_ap_payment", "value": "PAY_AP"}])
        for step in search_steps
    ] + [
        {
            "type": "MOVE_SELECTED_CARDS",
            "from_var": "selected_outside_card",
            "to": "HAND",
            "requirements": gate_requirements + [{"type": "CONTEXT_VALUE_IS", "var": "selected_optional_ap_payment", "value": "PAY_AP"}],
        }
    ]
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        remove_specs + search_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _outside_character_to_hand_optional_rest_named_ready_ap_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    hand_specs, hand_steps = _manual_single_target(
        "SELF",
        ["OUTSIDE"],
        [{"type": "CARD_TYPE_IS", "value": "CHARACTER"}],
        1,
        1,
        "selected_outside_card",
    )
    rest_specs, rest_steps = _manual_single_target(
        "SELF",
        ["FRONT_LINE"],
        [{"type": "CARD_NAME_IS", "value": match.group(1)}, {"type": "CARD_STATE_IS", "state": "ACTIVE"}],
        0,
        1,
        "selected_rest_target",
    )
    steps = hand_steps + [
        {"type": "MOVE_SELECTED_CARDS", "from_var": "selected_outside_card", "to": "HAND"},
    ] + rest_steps + [
        {"type": "REST", "target_var": "selected_rest_target"},
        {
            "type": "ACTIVATE_AP_SLOTS",
            "count": 1,
            "requirements": [{"type": "CONTEXT_VAR_NON_EMPTY", "var": "selected_rest_target"}],
        },
    ]
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        hand_specs + rest_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _preview_name_contains_dual_then_conditional_ready_ap_builder(card: dict, trigger_entry: dict, event_name: str, text: str, card_id: str, payload: dict) -> dict:
    match = payload["match"]
    ability = _build_preview_add_to_hand_template(
        card,
        trigger_entry,
        event_name,
        text,
        card_id,
        {
            "params": {
                "count": int(match.group(1)),
                "requirements": [{"type": "CARD_TYPE_IS", "value": "CHARACTER"}],
                "filters": [{"type": "OR", "filters": [{"type": "NAME_CONTAINS", "value": match.group(2)}, {"type": "NAME_CONTAINS", "value": match.group(3)}]}],
            },
            "template_metadata": payload.get("template_metadata"),
        },
    )
    ability.setdefault("steps", []).append(
        {
            "type": "ACTIVATE_AP_SLOTS",
            "count": 1,
            "requirements": [
                {"type": "CONTROLLER_HAS_NAME_CONTAINS_IN_FIELD", "value": match.group(4)},
                {"type": "CONTROLLER_HAS_NAME_CONTAINS_IN_FIELD", "value": match.group(5)},
            ],
        }
    )
    return ability


def _move_to_deck_top_or_bottom_with_name_gate_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    target_specs, steps = _manual_single_target(
        "OPPONENT",
        ["FRONT_LINE"],
        [{"type": "CARD_BP_LTE", "value": int(match.group(1))}],
        1,
        1,
        "selected_target",
    )
    steps.append(
        {
            "type": "SELECT_TARGETS",
            "var": "selected_deck_position",
            "target": {
                "type": "OPTION_SET",
                "options": ["TOP", "BOTTOM"],
                "min": 1,
                "max": 1,
                "selection_mode": "MANUAL",
                "manual": True,
            },
        }
    )
    steps.append(
        {
            "type": "MOVE_SELECTED_CARDS",
            "from_var": "selected_target",
            "to": "DECK",
            "target_player_mode": "CARD_CONTROLLER",
            "to_position_from_var": "selected_deck_position",
        }
    )
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _named_buff_then_draw_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    target_specs, steps = _manual_single_target(
        "SELF",
        ["FRONT_LINE", "BACK_LINE"],
        [{"type": "CARD_NAME_IS", "value": match.group(1)}],
        0,
        1,
        "selected_target",
    )
    steps.extend(
        [
            {"type": "ADD_TEMP_BP_MODIFIER", "target_var": "selected_target", "value": int(match.group(2)), "expires": "END_OF_TURN"},
            {"type": "DRAW", "value": int(match.group(3))},
        ]
    )
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _conditional_bp_replace_marker_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [{"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": match.group(1)}],
        [],
        [{"type": "SET_CONTEXT_FLAG", "var": "dynamic_bp_threshold_replaced", "value": True}],
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _dual_buff_with_optional_keyword_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    target_specs, steps = _manual_single_target(
        "SELF",
        ["FRONT_LINE"],
        [{"type": "CARD_NAME_IS", "value": match.group(1)}],
        1,
        1,
        "selected_target",
    )
    steps.extend(
        [
            {"type": "ADD_TEMP_BP_MODIFIER", "target_var": "selected_target", "value": int(match.group(2)), "expires": "END_OF_TURN"},
            {"type": "ADD_TEMP_BP_MODIFIER", "target_uid": "SOURCE_CARD", "value": int(match.group(2)), "expires": "END_OF_TURN"},
        ]
    )
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _rest_active_other_then_source_gain_placeholder_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    target_specs, steps = _manual_single_target(
        "SELF",
        ["FRONT_LINE"],
        [{"type": "NOT_SOURCE_CARD"}, {"type": "CARD_STATE_IS", "state": "ACTIVE"}],
        1,
        1,
        "selected_target",
    )
    steps.append({"type": "REST", "target_var": "selected_target"})
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _draw_activate_name_contains_and_named_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    first_specs, first_steps = _manual_single_target(
        "SELF",
        ["FRONT_LINE"],
        [{"type": "NAME_CONTAINS", "value": match.group(2)}],
        0,
        1,
        "selected_first_target",
    )
    second_specs, second_steps = _manual_single_target(
        "SELF",
        ["FRONT_LINE"],
        [{"type": "CARD_NAME_IS", "value": match.group(4)}],
        0,
        1,
        "selected_second_target",
    )
    steps = [{"type": "DRAW", "value": int(match.group(1))}] + first_steps + [
        {"type": "ACTIVATE_CARD", "target_var": "selected_first_target"},
        {"type": "ADD_TEMP_KEYWORD", "target_var": "selected_first_target", "keyword": "IMPACT_PLUS_1", "expires": "END_OF_TURN"},
    ] + second_steps + [{"type": "ACTIVATE_CARD", "target_var": "selected_second_target"}]
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        first_specs + second_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _optional_pay_ap_deal_damage_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    requirements = [{"type": "PLAYER_LIFE_GTE", "player": "OPPONENT", "value": int(match.group(1))}]
    steps = [
        {
            "type": "SELECT_TARGETS",
            "var": "selected_optional_ap_payment",
            "target": {
                "type": "OPTION_SET",
                "options": ["PAY_AP", "SKIP"],
                "min": 1,
                "max": 1,
                "selection_mode": "MANUAL",
                "manual": True,
            },
        },
        {
            "type": "PAY_AP_COST",
            "value": int(match.group(2)),
            "requirements": [{"type": "CONTEXT_VALUE_IS", "var": "selected_optional_ap_payment", "value": "PAY_AP"}],
        },
        {
            "type": "DEAL_DAMAGE",
            "target_player": "OPPONENT",
            "value": int(match.group(3)),
            "requirements": [{"type": "CONTEXT_VALUE_IS", "var": "selected_optional_ap_payment", "value": "PAY_AP"}],
        },
    ]
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        requirements,
        [],
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _hand_named_character_summon_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    color_map = {"赤": "RED", "青": "BLUE", "緑": "GREEN", "黄": "YELLOW", "紫": "PURPLE", "白": "WHITE", "黒": "BLACK"}
    requirements = [
        {"type": "CARD_TYPE_IS", "value": "CHARACTER"},
        {"type": "CARD_COST_ENERGY_LTE", "value": int(match.group(1))},
        {"type": "CARD_COST_AP_EQ", "value": int(match.group(2))},
        {"type": "CARD_COLOR_IS", "value": color_map[match.group(3)]},
        {"type": "CARD_NAME_IS", "value": match.group(4)},
        {"type": "CARD_CAN_PLAY_TO_ZONE", "zone": "FRONT_LINE", "ignore_play_timing": True, "allow_current_zone": False},
    ]
    target_specs, select_steps = _manual_single_target("SELF", ["HAND"], requirements, 0, 1, "selected_summon_card")
    steps = select_steps + [
        {
            "type": "PLAY_SELECTED_CARDS",
            "from_var": "selected_summon_card",
            "to": "FRONT_LINE",
            "state": "RESTED",
            "ignore_play_timing": True,
            "allow_current_zone": False,
        }
    ]
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _branch_choice_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    branch_texts = [
        str(effect_entry.get("text", "")).strip().lstrip("・").strip()
        for effect_entry in card.get("effects", [])
        if str(effect_entry.get("text", "")).strip().startswith("・")
    ]
    if not branch_texts:
        branch_texts = ["BRANCH_1", "BRANCH_2"]
    options = [f"BRANCH_{index + 1}" for index in range(len(branch_texts))]
    steps = [
        {
            "type": "SELECT_TARGETS",
            "var": "selected_branch_option",
            "target": {
                "type": "OPTION_SET",
                "options": options,
                "min": 1,
                "max": 1,
                "selection_mode": "MANUAL",
                "manual": True,
            },
        },
        {
            "type": "EXECUTE_CHOICE_BRANCH",
            "mode_var": "selected_branch_option",
            "branches": {option: _compile_branch_sub_steps(card, trigger_entry, text) for option, text in zip(options, branch_texts)},
            "default_steps": [],
        },
    ]
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        [],
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _branch_choice_non_repeat_per_turn_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, card_id: str, payload: dict) -> dict:
    branch_texts = [
        str(effect_entry.get("text", "")).strip().lstrip("・").strip()
        for effect_entry in card.get("effects", [])
        if str(effect_entry.get("text", "")).strip().startswith("・")
    ]
    if not branch_texts:
        branch_texts = ["BRANCH_1", "BRANCH_2"]
    options = [f"BRANCH_{index + 1}" for index in range(len(branch_texts))]
    safe_card_id = re.sub(r"[^A-Za-z0-9_]+", "_", card_id or str(card.get("id", "CARD")))
    branches: dict[str, list[dict]] = {}
    for option, text in zip(options, branch_texts):
        flag_name = f"{safe_card_id}_{option.lower()}_used_this_turn"
        branch_steps = _compile_branch_sub_steps(card, trigger_entry, text)
        branches[option] = [
            {
                "type": "RUN_COMPOSITE_IF",
                "if_requirements": [{"type": "NOT", "requirement": {"type": "PLAYER_TURN_FLAG_TRUE", "player": "SELF", "flag": flag_name}}],
                "steps": branch_steps + [{"type": "SET_PLAYER_TURN_FLAG", "player": "SELF", "flag": flag_name, "value": True}],
            }
        ]
    steps = [
        {
            "type": "SELECT_TARGETS",
            "var": "selected_branch_option",
            "target": {
                "type": "OPTION_SET",
                "options": options,
                "min": 1,
                "max": 1,
                "selection_mode": "MANUAL",
                "manual": True,
            },
        },
        {
            "type": "EXECUTE_CHOICE_BRANCH",
            "mode_var": "selected_branch_option",
            "branches": branches,
            "default_steps": [],
        },
    ]
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        [],
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _other_energy_lte_unblockable_bp_gate_builder(card: dict, trigger_entry: dict, event_name: str, text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    min_count = 1 if "1枚選び" in text else 0
    target_specs, steps = _manual_single_target(
        "SELF",
        ["FRONT_LINE", "BACK_LINE"],
        [
            {"type": "CARD_UID_NE", "value": "SOURCE_CARD"},
            {"type": "CARD_COST_ENERGY_LTE", "value": int(match.group(1))},
        ],
        min_count,
        1,
        "selected_target",
    )
    steps.append(
        {
            "type": "ADD_TEMP_KEYWORD",
            "target_var": "selected_target",
            "keyword": f"CANNOT_BE_BLOCKED_BY_BP_GTE_{int(match.group(2))}",
            "expires": "END_OF_TURN",
        }
    )
    once_per_turn_name = match.group(3)
    if once_per_turn_name:
        flag_name = _event_used_turn_flag(once_per_turn_name)
        return _supported_ability(
            card,
            event_name,
            trigger_entry,
            [{"type": "NOT", "requirement": {"type": "PLAYER_TURN_FLAG_TRUE", "player": "SELF", "flag": flag_name}}],
            target_specs,
            steps + [{"type": "SET_PLAYER_TURN_FLAG", "player": "SELF", "flag": flag_name, "value": True}],
            payload.get("kind"),
            template_metadata=payload.get("template_metadata"),
        )
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _bp_remove_dynamic_name_gate_energy_lte_count_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    target_specs, steps = _manual_single_target(
        "OPPONENT",
        ["FRONT_LINE"],
        [
            {
                "type": "CARD_BP_LTE_DYNAMIC",
                "value_provider": {
                    "type": "CONDITIONAL",
                    "when": [{"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": match.group(2)}],
                    "then": {
                        "type": "FIXED_PLUS_CONTROLLER_FRONT_LINE_ENERGY_LTE_COUNT_MULTIPLIED",
                        "value": int(match.group(1)),
                        "cost_energy_lte": int(match.group(3)),
                        "multiplier": int(match.group(4)),
                    },
                    "default": {"type": "FIXED", "value": int(match.group(1))},
                },
            }
        ],
        1,
        1,
    )
    steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_target", "to": "OUTSIDE"})
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _hand_summon_named_or_energy_lte_then_conditional_keyword_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    color_map = {"赤": "RED", "青": "BLUE", "緑": "GREEN", "黄": "YELLOW", "紫": "PURPLE", "白": "WHITE", "黒": "BLACK"}
    target_specs, steps = _manual_single_target(
        "SELF",
        ["HAND"],
        [
            {"type": "CARD_COLOR_IS", "value": color_map[match.group(1)]},
            {
                "type": "OR",
                "filters": [
                    {"type": "NAME_IS", "value": match.group(2)},
                    {"type": "AND", "filters": [{"type": "CARD_TYPE_IS", "value": "CHARACTER"}, {"type": "CARD_COST_ENERGY_LTE", "value": int(match.group(3))}]},
                ],
            },
        ],
        0,
        1,
        "selected_card",
    )
    steps.extend(
        [
            {"type": "PLAY_SELECTED_CARDS", "from_var": "selected_card", "to_zone": "FRONT_LINE", "state": "RESTED", "ignore_play_costs": True},
            {
                "type": "ADD_TEMP_KEYWORD",
                "target_uid": "SOURCE_CARD",
                "keyword": "TLR_SAJI_PLACEHOLDER",
                "expires": "END_OF_TURN",
                "requirements": [{"type": "CONTROLLER_HAS_NAME_IN_FIELD", "value": match.group(4)}],
            },
        ]
    )
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _conditional_bp_gate_grant_cannot_block_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    match = payload["match"]
    target_specs, steps = _manual_single_target(
        "OPPONENT",
        ["FRONT_LINE"],
        [
            {
                "type": "CARD_BP_LTE_DYNAMIC",
                "value_provider": _conditional_value_provider(
                    _fixed_value_provider(int(match.group(1))),
                    [{"type": "PLAYER_ZONE_CARD_COUNT_GTE", "player": "SELF", "zones": ["FRONT_LINE", "ENERGY_LINE"], "value": int(match.group(2))}],
                    _fixed_value_provider(int(match.group(3))),
                ),
            }
        ],
        0,
        1,
        "selected_target",
    )
    steps.append({"type": "ADD_TEMP_KEYWORD", "target_var": "selected_target", "keyword": "CANNOT_BLOCK", "expires": "END_OF_TURN"})
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _self_gain_source_bp_compare_remove_builder(card: dict, trigger_entry: dict, event_name: str, _text: str, _card_id: str, payload: dict) -> dict:
    target_specs, steps = _manual_single_target(
        "OPPONENT",
        ["FRONT_LINE"],
        [{"type": "CARD_BP_LTE_DYNAMIC", "value_provider": {"type": "SOURCE_BP_MINUS", "value": 1}}],
        0,
        1,
        "selected_target",
    )
    steps.append({"type": "MOVE_SELECTED_CARDS", "from_var": "selected_target", "to": "OUTSIDE"})
    return _supported_ability(
        card,
        event_name,
        trigger_entry,
        [],
        target_specs,
        steps,
        payload.get("kind"),
        template_metadata=payload.get("template_metadata"),
    )


def _mcr_sheryl_raid_chain_override_builder(card: dict, trigger_entry: dict, event_name: str, text: str, card_id: str, payload: dict) -> dict:
    ability = _build_preview_add_to_hand_template(
        card,
        trigger_entry,
        event_name,
        text,
        card_id,
        {
            "params": {
                "count": 5,
                "requirements": [{"type": "CARD_NAME_IS", "value": "シェリル・ノーム"}],
                "max_count": 2,
            },
            "template_metadata": payload.get("template_metadata"),
        },
    )
    ability.setdefault("steps", []).append({"type": "REGISTER_STATIC_MODIFIER", "modifier": {"type": "SPECIAL_OVERRIDE_MCR_029_SHERYL_RAID_CHAIN"}})
    return ability


_TRIGGER_TEMPLATE_RULES: tuple[_TemplateRule, ...] = (
    _TemplateRule(
        name="trigger.life_trigger.raid_choice",
        event_filter="ON_LIFE_TRIGGER",
        matcher=_exact_text_match("このカードを手札に加えるか、必要エナジーを満たしている場合、レイドさせる。"),
        builder=_life_trigger_raid_choice_builder,
        priority=260,
        template_metadata={"family": "LIFE_TRIGGER_RAID_CHOICE", "variant": "add_to_hand_or_raid_if_possible"},
    ),
    _TemplateRule(
        name="trigger.choice_branch.select_one",
        event_filter=("ON_ENTER", "MAIN_ACTIVATE", "ON_PLAY", "ON_ATTACK", "ON_BLOCK", "ON_LIFE_TRIGGER"),
        matcher=_exact_text_match("以下から1つ選ぶ。"),
        builder=_branch_choice_builder,
        priority=250,
        template_metadata={"family": "MULTI_BRANCH_CHOICE", "variant": "select_one_from_following"},
    ),
    _TemplateRule(
        name="trigger.choice_branch.non_repeat_per_turn",
        event_filter=("ON_ATTACK", "MAIN_ACTIVATE"),
        matcher=_regex_match(r"以下から1つまで選ぶ。このターン中に〈.+〉が既に選んだ効果は選べない。"),
        builder=_branch_choice_non_repeat_per_turn_builder,
        priority=251,
        template_metadata={"family": "MULTI_BRANCH_CHOICE", "variant": "select_one_non_repeat_per_turn"},
    ),
    _TemplateRule(
        name="trigger.preview_top.choose_top_or_bottom",
        event_filter=("ON_ENTER", "MAIN_ACTIVATE"),
        matcher=_exact_text_match("自分の山札の上から1枚見て、山札の上か下に置く。"),
        builder=_preview_top_then_choose_top_or_bottom_builder,
        priority=210,
        template_metadata={"family": "PREVIEW_TOP_POSITION", "variant": "preview_one_then_choose_top_or_bottom"},
    ),
    _TemplateRule(
        name="trigger.conditional_draw",
        event_filter=("ON_ENTER", "MAIN_ACTIVATE", "ON_PLAY", "ON_ATTACK", "ON_BLOCK", "ON_LIFE_TRIGGER"),
        matcher=_regex_match(r"自分の場に(?:他のカードが(\d+)枚以上ある|〈(.+)〉がある)場合、カードを(\d+)枚引く。"),
        builder=_conditional_draw_builder,
        priority=205,
        template_metadata={"family": "CONDITIONAL_DRAW", "variant": "field_state_conditional_draw"},
    ),
    _TemplateRule(
        name="trigger.bp_debuff",
        event_filter=("ON_ENTER", "MAIN_ACTIVATE"),
        matcher=_regex_match(r"BP(\d+)以上の相手のフロントLのキャラを1枚選び、このターン中、BP-(\d+)。"),
        builder=_bp_debuff_builder,
        priority=204,
        template_metadata={"family": "BP_DEBUFF", "variant": "bp_gte_target_temp_debuff"},
    ),
    _TemplateRule(
        name="trigger.conditional_bp_debuff",
        event_filter=("ON_ENTER", "MAIN_ACTIVATE"),
        matcher=_regex_match(r"自分の場に〈(.+)〉がある場合、BP(\d+)以上の相手のフロントLのキャラを1枚まで選び、このターン中、BP-(\d+)。"),
        builder=_conditional_bp_debuff_builder,
        priority=204,
        template_metadata={"family": "BP_DEBUFF", "variant": "conditional_bp_gte_target_temp_debuff"},
    ),
    _TemplateRule(
        name="trigger.optional_discard_ready_self",
        event_filter="ON_ENTER",
        matcher=_regex_match(r"自分の手札を(\d+)枚場外に置いてもよい。そうした場合、このキャラをアクティブにする。"),
        builder=_optional_discard_ready_self_builder,
        priority=203,
        template_metadata={"family": "OPTIONAL_COST_THEN_EFFECT", "variant": "optional_discard_then_ready_self"},
    ),
    _TemplateRule(
        name="trigger.optional_ap_damage",
        event_filter=("ON_ENTER", "MAIN_ACTIVATE", "ON_PLAY", "ON_ATTACK", "ON_BLOCK", "ON_LIFE_TRIGGER"),
        matcher=_regex_match(r"相手のライフが(\d+)以上の場合、APを(\d+)支払ってもよい。そうした場合、相手に(\d+)ダメージ。"),
        builder=_optional_pay_ap_deal_damage_builder,
        priority=205,
        template_metadata={"family": "OPTIONAL_AP_DAMAGE", "variant": "pay_ap_then_deal_damage"},
    ),
    _TemplateRule(
        name="trigger.hand_named_character_summon",
        event_filter=("ON_ENTER", "MAIN_ACTIVATE", "ON_ATTACK", "ON_BLOCK", "ON_LIFE_TRIGGER"),
        matcher=_regex_match(r"自分の手札から必要エナジーが(\d+)以下で消費APが(\d+)の(赤|青|緑|黄|紫|白|黒)の〈(.+)〉を1枚まで自分の場にレストで登場させる。"),
        builder=_hand_named_character_summon_builder,
        priority=205,
        template_metadata={"family": "HAND_SUMMON", "variant": "summon_named_character_from_hand"},
    ),
    _TemplateRule(
        name="trigger.self_other_bp_modifier",
        event_filter=("ON_ENTER", "MAIN_ACTIVATE", "ON_PLAY", "ON_ATTACK", "ON_BLOCK", "ON_LIFE_TRIGGER"),
        matcher=_regex_match(r"自分の場の他のキャラを1枚選び、このターン中、BP\+(\d+)。"),
        builder=_self_other_bp_modifier_builder,
        priority=200,
        template_metadata={"family": "TEMP_BP_MODIFIER", "variant": "self_other_character_bp_plus"},
    ),
    _TemplateRule(
        name="trigger.self_other_bp_modifier.conditional_upgrade",
        event_filter=("ON_ENTER", "MAIN_ACTIVATE"),
        matcher=_regex_match(r"自分の場の他のキャラを1枚まで選び、このターン中、『BP\+(\d+)』。自分の場に他のカードが(\d+)枚以上ある場合、『BP\+(\d+)』に代わる。"),
        builder=_self_other_bp_modifier_conditional_upgrade_builder,
        priority=201,
        template_metadata={"family": "TEMP_BP_MODIFIER", "variant": "self_other_character_bp_plus_conditional_upgrade"},
    ),
    _TemplateRule(
        name="trigger.rest_and_lock_once",
        event_filter=("ON_ENTER", "MAIN_ACTIVATE", "ON_PLAY", "ON_ATTACK"),
        matcher=_regex_match(r"・?相手のフロントLのキャラを1枚まで選び、レストにする。それは次の1回アクティブにならない。"),
        builder=_rest_and_lock_builder,
        priority=202,
        template_metadata={"family": "REST_CONTROL", "variant": "rest_and_skip_next_ready_once"},
    ),
    _TemplateRule(
        name="trigger.rest_and_lock_with_conditional_debuff",
        event_filter=("ON_ENTER", "MAIN_ACTIVATE"),
        matcher=_regex_match(r"相手のフロントLのキャラを1枚まで選び、レストにする。選んだキャラのBPが(\d+)以上の場合、そのキャラは次の自分のターン開始時まで、BP-(\d+)。"),
        builder=_rest_and_lock_then_conditional_debuff_builder,
        priority=202,
        template_metadata={"family": "REST_CONTROL", "variant": "rest_then_conditional_bp_debuff_until_next_turn"},
    ),
    _TemplateRule(
        name="trigger.conditional_rest_or_remove",
        event_filter=("ON_ENTER", "MAIN_ACTIVATE", "ON_PLAY"),
        matcher=_regex_match(r"BP(\d+)以下の相手のフロントLのキャラを1枚選び、『レストにする。それは次の1回アクティブにならない』。自分の場に〈(.+)〉がある場合、『退場させる』に代わる。"),
        builder=_conditional_rest_or_remove_builder,
        priority=202,
        template_metadata={"family": "BP_THRESHOLD_REMOVE", "variant": "remove_or_rest_lock_by_name_gate"},
    ),
    _TemplateRule(
        name="trigger.draw_discard_then_outside_summon",
        event_filter=("ON_ENTER", "MAIN_ACTIVATE", "ON_PLAY"),
        matcher=_regex_match(r"カードを(\d+)枚引き、自分の手札を(\d+)枚場外に置く。その後、自分の場外から必要エナジーが(\d+)以下の黄のキャラカードを1枚まで自分の場にレストで登場させる。"),
        builder=_draw_discard_then_outside_summon_builder,
        priority=202,
        template_metadata={"family": "OPTIONAL_COST_THEN_EFFECT", "variant": "draw_discard_then_outside_summon"},
    ),
    _TemplateRule(
        name="trigger.buff_draw_then_conditional_ready_ap",
        event_filter=("ON_ENTER", "MAIN_ACTIVATE", "ON_PLAY"),
        matcher=_regex_match(r"自分の場のキャラを1枚まで選び、このターン中、BP\+(\d+)。カードを(\d+)枚引く。自分の場外に黄の［特徴：(.+)］のカード名が(\d+)種類以上ある場合、自分のAPカードを1枚まで選び、アクティブにする。"),
        builder=_buff_draw_then_conditional_ready_ap_builder,
        priority=202,
        template_metadata={"family": "TEMP_BP_MODIFIER", "variant": "buff_draw_then_conditional_ready_ap"},
    ),
    _TemplateRule(
        name="trigger.energy_to_front_if_slot_open",
        event_filter=("ON_ENTER", "MAIN_ACTIVATE"),
        matcher=_regex_match(r"自分のフロントLに空きがある場合、自分のエナジーLのカード名に「(.+)」を含む他のキャラを1枚まで選び、フロントLに移動させる。"),
        builder=_energy_to_front_if_slot_open_builder,
        priority=202,
        template_metadata={"family": "ZONE_MOVE", "variant": "energy_to_front_if_slot_open_name_contains"},
    ),
    _TemplateRule(
        name="trigger.buff_then_conditional_activate_named",
        event_filter=("ON_ENTER", "MAIN_ACTIVATE"),
        matcher=_regex_match(r"自分の場の他のキャラを1枚まで選び、このターン中、BP\+(\d+)。選んだキャラが〈(.+)〉の場合、そのキャラをアクティブにする。"),
        builder=_buff_then_conditional_activate_named_builder,
        priority=202,
        template_metadata={"family": "TEMP_BP_MODIFIER", "variant": "buff_then_conditional_activate_named"},
    ),
    _TemplateRule(
        name="trigger.dual_buff_with_optional_keyword",
        event_filter=("MAIN_ACTIVATE", "ON_ENTER"),
        matcher=_regex_match(r"自分のフロントLの〈(.+)〉を1枚選ぶ。そうした場合、そのキャラとこのキャラはこのターン中、BP\+(\d+)。さらにこのキャラはこのターン中、を得る。"),
        builder=_dual_buff_with_optional_keyword_builder,
        priority=202,
        template_metadata={"family": "TEMP_BP_MODIFIER", "variant": "dual_buff_with_optional_keyword_placeholder"},
    ),
    _TemplateRule(
        name="trigger.other_energy_lte_unblockable_bp_gate",
        event_filter=("ON_ENTER", "MAIN_ACTIVATE"),
        matcher=_regex_match(r"必要エナジーが(\d+)以下の自分の場の他のキャラを1枚(?:まで)?選び、このターン中、「このキャラはBP(\d+)以上のキャラにブロックされない。」を与える。(?:〈(.+)〉のこの効果は1ターンに1回のみ発動できる。)?"),
        builder=_other_energy_lte_unblockable_bp_gate_builder,
        priority=202,
        template_metadata={"family": "TEMP_KEYWORD", "variant": "other_energy_lte_unblockable_bp_gate"},
    ),
    _TemplateRule(
        name="trigger.rest_active_other_then_source_gain_placeholder",
        event_filter=("MAIN_ACTIVATE", "ON_ENTER"),
        matcher=_regex_match(r"自分のフロントLのアクティブの他のキャラを1枚レストにする。そうした場合、このキャラはこのターン中、を得る。"),
        builder=_rest_active_other_then_source_gain_placeholder_builder,
        priority=202,
        template_metadata={"family": "REST_CONTROL", "variant": "rest_active_other_then_source_gain_placeholder"},
    ),
    _TemplateRule(
        name="trigger.bp_remove_then_choice_branch",
        event_filter="ON_PLAY",
        matcher=_regex_match(r"『?BP(\d+)以下』?の相手のフロントLのキャラを1枚選び、退場させる。以下から1つ選ぶ。"),
        builder=_bp_remove_then_choice_branch_builder,
        priority=202,
        template_metadata={"family": "MULTI_BRANCH_CHOICE", "variant": "bp_remove_then_choice_branch"},
    ),
    _TemplateRule(
        name="trigger.hand_summon_named_or_energy_lte_then_conditional_keyword",
        event_filter=("ON_ENTER",),
        matcher=_regex_match(r"自分の手札から(赤|青|緑|黄|紫|白|黒)の〔〈(.+)〉か必要エナジーが(\d+)以下のキャラカード〕を1枚まで自分の場にレストで登場させる。自分の場に〈(.+)〉がある場合、このキャラはこのターン中、を得る。"),
        builder=_hand_summon_named_or_energy_lte_then_conditional_keyword_builder,
        priority=202,
        template_metadata={"family": "OPTIONAL_COST_THEN_EFFECT", "variant": "hand_summon_named_or_energy_lte_then_conditional_keyword_placeholder"},
    ),
    _TemplateRule(
        name="trigger.conditional_bp_gate_grant_cannot_block",
        event_filter=("ON_ENTER",),
        matcher=_regex_match(r"『BP(\d+)以下』の相手のフロントLのキャラを1枚まで選び、このターン中、「このキャラはブロックできない。」を与える。自分の場に他のカードが(\d+)枚以上ある場合、『BP(\d+)以下』に代わる。"),
        builder=_conditional_bp_gate_grant_cannot_block_builder,
        priority=202,
        template_metadata={"family": "TEMP_KEYWORD", "variant": "conditional_bp_gate_grant_cannot_block"},
    ),
    _TemplateRule(
        name="trigger.self_gain_source_bp_compare_remove",
        event_filter=("ON_ENTER",),
        matcher=_exact_text_match("このキャラはこのターン中、「このキャラよりBPが低い相手のフロントLのキャラを1枚まで選び、退場させる。」を得る。"),
        builder=_self_gain_source_bp_compare_remove_builder,
        priority=220,
        template_metadata={"family": "SPECIAL_OVERRIDE", "variant": "self_gain_source_bp_compare_remove"},
    ),
    _TemplateRule(
        name="trigger.preview_top_two_reorder_top_bottom",
        event_filter=("ON_ENTER", "MAIN_ACTIVATE"),
        matcher=_exact_text_match("自分の山札の上から2枚見て、山札の上と下に望む枚数ずつ望む順で置く。"),
        builder=_preview_top_two_reorder_top_bottom_builder,
        priority=206,
        template_metadata={"family": "PREVIEW_TOP_POSITION", "variant": "preview_two_reorder_top_bottom_split"},
    ),
    _TemplateRule(
        name="trigger.preview_add_character_cards",
        event_filter=("ON_ENTER", "MAIN_ACTIVATE", "ON_PLAY", "ON_ATTACK", "ON_BLOCK", "ON_LIFE_TRIGGER"),
        matcher=_regex_match(r"・?自分の山札の上から(\d+)枚見る。その中からキャラカードを(\d+)枚まで公開し手札に加える。残りを望む順で自分の山札の下に置く。"),
        builder=_preview_add_character_cards_builder,
        priority=191,
        template_metadata={"family": "PREVIEW_ADD_TO_HAND", "variant": "preview_add_character_cards_then_reorder_bottom"},
    ),
    _TemplateRule(
        name="trigger.preview_add_to_hand.007_or_trait_discard",
        event_filter="ON_ENTER",
        matcher=_exact_text_match("自分の山札の上から3枚見る。その中から〈アルティメットまどか〉か［特徴：魔法少女］を1枚まで公開し手札に加える。残りを望む順で自分の山札の下に置く。手札に加えた場合、自分の手札を1枚場外に置く。"),
        builder=_preview_add_to_hand_builder_factory(
            count=3,
            filters=[
                {
                    "type": "OR",
                    "filters": [
                        {"type": "NAME_IS", "value": "アルティメットまどか"},
                        {"type": "HAS_TRAIT", "value": "魔法少女"},
                    ],
                }
            ],
            discard_after_add=True,
        ),
        priority=200,
        template_metadata={"family": "PREVIEW_ADD_TO_HAND", "variant": "preview_add_to_hand_discard_on_add"},
    ),
    _TemplateRule(
        name="trigger.preview_add_to_hand.040_name_discard",
        event_filter="ON_ENTER",
        matcher=_exact_text_match("自分の山札の上から5枚見る。その中から〈鹿目 まどか〉を1枚まで公開し手札に加える。残りを望む順で自分の山札の下に置く。手札に加えた場合、自分の手札を1枚場外に置く。"),
        builder=_preview_add_to_hand_builder_factory(
            count=5,
            requirements=[{"type": "CARD_NAME_IS", "value": "鹿目 まどか"}],
            discard_after_add=True,
        ),
        priority=200,
        template_metadata={"family": "PREVIEW_ADD_TO_HAND", "variant": "preview_add_to_hand_discard_on_add"},
    ),
    _TemplateRule(
        name="trigger.preview_add_to_hand.043_name_or_trait_discard",
        event_filter="ON_ENTER",
        matcher=_exact_text_match("自分の山札の上から3枚見る。その中から〈百江 なぎさ〉か［特徴：ピュエラ・マギ・ホーリー・クインテット］を1枚まで公開し手札に加える。残りを望む順で自分の山札の下に置く。手札に加えた場合、自分の手札を1枚場外に置く。"),
        builder=_preview_add_to_hand_builder_factory(
            count=3,
            filters=[
                {
                    "type": "OR",
                    "filters": [
                        {"type": "NAME_IS", "value": "百江 なぎさ"},
                        {"type": "HAS_TRAIT", "value": "ピュエラ・マギ・ホーリー・クインテット"},
                    ],
                }
            ],
            discard_after_add=True,
        ),
        priority=200,
        template_metadata={"family": "PREVIEW_ADD_TO_HAND", "variant": "preview_add_to_hand_discard_on_add"},
    ),
    _TemplateRule(
        name="trigger.preview_add_to_hand.yellow_event_discard",
        event_filter="ON_ENTER",
        matcher=_exact_text_match("自分の山札の上から4枚見る。その中から黄のイベントカードを1枚まで公開し手札に加える。残りを望む順で自分の山札の下に置く。手札に加えた場合、自分の手札を1枚場外に置く。"),
        builder=_preview_add_to_hand_builder_factory(
            count=4,
            requirements=[
                {"type": "CARD_TYPE_IS", "value": "EVENT"},
                {"type": "CARD_COLOR_IS", "value": "YELLOW"},
            ],
            discard_after_add=True,
        ),
        priority=180,
        template_metadata={"family": "PREVIEW_ADD_TO_HAND", "variant": "preview_add_to_hand_discard_on_add"},
    ),
    _TemplateRule(
        name="trigger.preview_add_to_hand.energy_threshold_discard",
        event_filter="ON_ENTER",
        matcher=_regex_match(r"自分の山札の上から(\d+)枚見て、必要エナジーが(\d+)以下のキャラカードを1枚まで公開し手札に加える。残りを望む順で山札の下に置く。手札に加えた場合、自分の手札を1枚場外に置く。"),
        builder=_preview_add_to_hand_energy_threshold_builder,
        priority=190,
        template_metadata={"family": "PREVIEW_ADD_TO_HAND", "variant": "preview_add_to_hand_discard_on_add"},
    ),
    _TemplateRule(
        name="trigger.bp_sum_limit_remove",
        event_filter=("ON_ENTER", "ON_ATTACK", "ON_BLOCK", "ON_LIFE_TRIGGER", "ON_LEAVE"),
        matcher=_regex_match(r"BPの合計が(\d+)以下になるように相手のフロントLのキャラを(\d+)枚まで選び、退場させる。"),
        builder=_bp_sum_limit_remove_builder,
        priority=135,
        template_metadata={"family": "BP_SUM_LIMIT_REMOVE", "variant": "bp_sum_limit_remove_optional"},
    ),
    _TemplateRule(
        name="trigger.bp_sum_limit_remove.dynamic_energy_line",
        event_filter=("ON_ENTER", "ON_ATTACK", "ON_BLOCK", "ON_LIFE_TRIGGER", "ON_LEAVE"),
        matcher=_regex_match(r"BPの合計が自分のエナジーラインのカード枚数×(\d+)以下になるように相手のフロントLのキャラを(\d+)枚まで選び、退場させる。"),
        builder=_bp_sum_limit_remove_dynamic_energy_builder,
        priority=136,
        template_metadata={"family": "BP_SUM_LIMIT_REMOVE", "variant": "bp_sum_limit_remove_dynamic_energy_line"},
    ),
    _TemplateRule(
        name="trigger.bp_bounce_to_hand",
        event_filter=("ON_ENTER", "ON_ATTACK", "ON_BLOCK", "ON_LIFE_TRIGGER", "ON_LEAVE"),
        matcher=_regex_match(r"BP(\d+)以下の相手のフロントLのキャラを(\d+)枚選び、手札に戻す。"),
        builder=_bp_bounce_to_hand_builder,
        priority=134,
        template_metadata={"family": "BP_FILTER_BOUNCE", "variant": "bp_threshold_return_to_hand_required"},
    ),
    _TemplateRule(
        name="trigger.preview_add_to_hand.name_contains_discard",
        event_filter="ON_ENTER",
        matcher=_regex_match(r"自分の山札の上から(\d+)枚見て、カード名に「(.+)」を含むキャラカードを1枚まで公開し手札に加える。残りを望む順で山札の下に置く。手札に加えた場合、自分の手札を1枚場外に置く。"),
        builder=_preview_add_to_hand_name_contains_builder,
        priority=195,
        template_metadata={"family": "PREVIEW_ADD_TO_HAND", "variant": "preview_add_to_hand_name_contains_discard_on_add"},
    ),
    _TemplateRule(
        name="trigger.bp_remove.required",
        event_filter=("ON_ENTER", "ON_ATTACK", "ON_BLOCK", "ON_LIFE_TRIGGER", "ON_LEAVE"),
        matcher=_regex_match(r"BP(\d+)以下の相手のフロントLのキャラを1枚選び、退場させる。"),
        builder=_bp_remove_from_match_builder_factory(min_count=1, max_count=1),
        priority=120,
        template_metadata={"family": "BP_THRESHOLD_REMOVE", "variant": "bp_threshold_remove_required"},
    ),
    _TemplateRule(
        name="trigger.bp_remove.optional",
        event_filter=("ON_ENTER", "ON_ATTACK", "ON_BLOCK", "ON_LIFE_TRIGGER", "ON_LEAVE"),
        matcher=_regex_match(r"BP(\d+)以下の相手のフロントLのキャラを1枚まで選び、退場させる。"),
        builder=_bp_remove_from_match_builder_factory(min_count=0, max_count=1),
        priority=110,
        template_metadata={"family": "BP_THRESHOLD_REMOVE", "variant": "bp_threshold_remove_optional"},
    ),
)

set_trigger_template_rules(_TRIGGER_TEMPLATE_RULES)


_EVENT_TEMPLATE_RULES: tuple[_TemplateRule, ...] = (
    _TemplateRule(
        name="event.choice_branch.select_one",
        event_filter="ON_PLAY",
        matcher=_exact_text_match("以下から1つ選ぶ。"),
        builder=_branch_choice_builder,
        priority=250,
        template_metadata={"family": "MULTI_BRANCH_CHOICE", "variant": "select_one_from_following"},
    ),
    _TemplateRule(
        name="event.conditional_preview_top.choose_top_or_bottom",
        event_filter="ON_PLAY",
        matcher=_regex_match(r"・?自分の場に〈(.+)〉がある場合、自分の山札の上から1枚見る。そのカードを自分の山札の上か下に置く。"),
        builder=_conditional_preview_top_then_choose_builder,
        priority=211,
        template_metadata={"family": "PREVIEW_TOP_POSITION", "variant": "conditional_preview_one_then_choose_top_or_bottom"},
    ),
    _TemplateRule(
        name="event.preview_add_character_cards",
        event_filter="ON_PLAY",
        matcher=_regex_match(r"・?自分の山札の上から(\d+)枚見る。その中からキャラカードを(\d+)枚まで公開し手札に加える。残りを望む順で自分の山札の下に置く。"),
        builder=_preview_add_character_cards_builder,
        priority=200,
        template_metadata={"family": "PREVIEW_ADD_TO_HAND", "variant": "preview_add_character_cards_then_reorder_bottom"},
    ),
    _TemplateRule(
        name="event.rest_and_lock_once",
        event_filter="ON_PLAY",
        matcher=_regex_match(r"・?相手のフロントLのキャラを1枚まで選び、レストにする。それは次の1回アクティブにならない。"),
        builder=_rest_and_lock_builder,
        priority=202,
        template_metadata={"family": "REST_CONTROL", "variant": "rest_and_skip_next_ready_once"},
    ),
    _TemplateRule(
        name="event.conditional_rest_or_remove",
        event_filter="ON_PLAY",
        matcher=_regex_match(r"BP(\d+)以下の相手のフロントLのキャラを1枚選び、『レストにする。それは次の1回アクティブにならない』。自分の場に〈(.+)〉がある場合、『退場させる』に代わる。"),
        builder=_conditional_rest_or_remove_builder,
        priority=202,
        template_metadata={"family": "BP_THRESHOLD_REMOVE", "variant": "remove_or_rest_lock_by_name_gate"},
    ),
    _TemplateRule(
        name="event.draw_discard_then_outside_summon",
        event_filter="ON_PLAY",
        matcher=_regex_match(r"カードを(\d+)枚引き、自分の手札を(\d+)枚場外に置く。その後、自分の場外から必要エナジーが(\d+)以下の黄のキャラカードを1枚まで自分の場にレストで登場させる。"),
        builder=_draw_discard_then_outside_summon_builder,
        priority=202,
        template_metadata={"family": "OPTIONAL_COST_THEN_EFFECT", "variant": "draw_discard_then_outside_summon"},
    ),
    _TemplateRule(
        name="event.buff_draw_then_conditional_ready_ap",
        event_filter="ON_PLAY",
        matcher=_regex_match(r"自分の場のキャラを1枚まで選び、このターン中、BP\+(\d+)。カードを(\d+)枚引く。自分の場外に黄の［特徴：(.+)］のカード名が(\d+)種類以上ある場合、自分のAPカードを1枚まで選び、アクティブにする。"),
        builder=_buff_draw_then_conditional_ready_ap_builder,
        priority=202,
        template_metadata={"family": "TEMP_BP_MODIFIER", "variant": "buff_draw_then_conditional_ready_ap"},
    ),
    _TemplateRule(
        name="event.bp_remove_then_choice_branch",
        event_filter="ON_PLAY",
        matcher=_regex_match(r"『?BP(\d+)以下』?の相手のフロントLのキャラを1枚選び、退場させる。以下から1つ選ぶ。"),
        builder=_bp_remove_then_choice_branch_builder,
        priority=202,
        template_metadata={"family": "MULTI_BRANCH_CHOICE", "variant": "bp_remove_then_choice_branch"},
    ),
    _TemplateRule(
        name="event.bp_remove_then_optional_pay_ap_add_outside_name_contains",
        event_filter="ON_PLAY",
        matcher=_regex_match(r"BP(\d+)以下の相手のフロントLのキャラを1枚選び、退場させる。自分のフロントLにカード名に「(.+)」を含むキャラとカード名に「(.+)」を含むキャラがある場合、APを(\d+)支払ってもよい。そうした場合、自分の場外からカード名に「(.+)」か「(.+)」を含むキャラカードを1枚まで手札に加える。"),
        builder=_bp_remove_then_optional_pay_ap_add_outside_name_contains_builder,
        priority=202,
        template_metadata={"family": "BP_THRESHOLD_REMOVE", "variant": "bp_remove_then_optional_pay_ap_add_outside_name_contains"},
    ),
    _TemplateRule(
        name="event.outside_character_to_hand_optional_rest_named_ready_ap",
        event_filter="ON_PLAY",
        matcher=_regex_match(r"自分の場外からを持つキャラカードを1枚手札に加える。自分のフロントLのアクティブの〈(.+)〉を1枚レストにしてもよい。そうした場合、自分のAPカードを1枚まで選び、アクティブにする。"),
        builder=_outside_character_to_hand_optional_rest_named_ready_ap_builder,
        priority=202,
        template_metadata={"family": "OPTIONAL_COST_THEN_EFFECT", "variant": "outside_to_hand_optional_rest_named_ready_ap"},
    ),
    _TemplateRule(
        name="event.preview_name_contains_dual_then_conditional_ready_ap",
        event_filter="ON_PLAY",
        matcher=_regex_match(r"自分の山札の上から(\d+)枚見る。その中からを持ちカード名に「(.+)」か「(.+)」を含むキャラカードを1枚まで公開し手札に加える。残りを望む順で自分の山札の下に置く。自分の場にカード名に「(.+)」を含むキャラとカード名に「(.+)」を含むキャラがある場合、自分のAPカードを1枚まで選び、アクティブにする。"),
        builder=_preview_name_contains_dual_then_conditional_ready_ap_builder,
        priority=202,
        template_metadata={"family": "PREVIEW_ADD_TO_HAND", "variant": "preview_name_contains_dual_then_conditional_ready_ap"},
    ),
    _TemplateRule(
        name="event.move_to_deck_top_or_bottom_with_name_gate",
        event_filter="ON_PLAY",
        matcher=_regex_match(r"BP(\d+)以下の相手のフロントLのキャラを1枚選び、相手の山札の上か下の『相手が選んだ方』に置く。自分の場にカード名に「(.+)」を含むキャラがある場合、『自分が選んだ方』に代わる。"),
        builder=_move_to_deck_top_or_bottom_with_name_gate_builder,
        priority=202,
        template_metadata={"family": "ZONE_MOVE", "variant": "move_to_deck_top_or_bottom_with_name_gate"},
    ),
    _TemplateRule(
        name="event.named_buff_then_draw",
        event_filter="ON_PLAY",
        matcher=_regex_match(r"・自分の場の〈(.+)〉を1枚まで選び、このターン中、BP\+(\d+)とを与える。カードを(\d+)枚引く。"),
        builder=_named_buff_then_draw_builder,
        priority=202,
        template_metadata={"family": "TEMP_BP_MODIFIER", "variant": "named_buff_then_draw"},
    ),
    _TemplateRule(
        name="event.conditional_bp_replace_marker",
        event_filter="ON_PLAY",
        matcher=_regex_match(r"・?自分の場に〈(.+)〉がある場合、『BP(\d+)以下』に代わる。"),
        builder=_conditional_bp_replace_marker_builder,
        priority=202,
        template_metadata={"family": "BP_THRESHOLD_REMOVE", "variant": "conditional_bp_replace_marker"},
    ),
    _TemplateRule(
        name="event.draw_activate_name_contains_and_named",
        event_filter="ON_PLAY",
        matcher=_regex_match(r"カードを(\d+)枚引く。自分のフロントLのカード名に「(.+)」を含むキャラを1枚まで選び、アクティブにし、このターン中、（インパクトの与えるダメージが\+(\d+)され、インパクトを持たない場合、を得る）を与える。自分のフロントLの〈(.+)〉を1枚まで選び、アクティブにする。"),
        builder=_draw_activate_name_contains_and_named_builder,
        priority=202,
        template_metadata={"family": "TEMP_BP_MODIFIER", "variant": "draw_activate_name_contains_and_named"},
    ),
    _TemplateRule(
        name="event.bp_remove_dynamic_name_gate_energy_lte_count",
        event_filter="ON_PLAY",
        matcher=_regex_match(r"『?BP(\d+)』?以下の相手のフロントLのキャラを1枚選び、退場させる。自分の場に〈(.+)〉がある場合、自分のフロントLの必要エナジーが(\d+)以下のキャラ1枚につき、この効果で選べるキャラのBPの範囲\+(\d+)。"),
        builder=_bp_remove_dynamic_name_gate_energy_lte_count_builder,
        priority=202,
        template_metadata={"family": "BP_THRESHOLD_REMOVE", "variant": "bp_remove_dynamic_name_gate_energy_lte_count"},
    ),
    _TemplateRule(
        name="event.mcr_sheryl_raid_chain_override",
        event_filter="ON_PLAY",
        matcher=_exact_text_match("自分の山札の上から5枚見る。その中から〈シェリル・ノーム〉を2枚まで公開し手札に加える。残りを望む順で自分の山札の下に置く。その後、自分の場のレイド状態の〈シェリル・ノーム〉を1枚選び、レイド状態の上のカードを場外に置いてもよい。そうした場合、カードを1枚引き、自分の手札から必要エナジーを満たしこの効果で場外に置いたカードとカードナンバーが異なる〈シェリル・ノーム〉を1枚まで、選んだキャラのレイド元のカードにレイドさせる。"),
        builder=_mcr_sheryl_raid_chain_override_builder,
        priority=220,
        template_metadata={"family": "SPECIAL_OVERRIDE", "variant": "mcr_sheryl_raid_chain_phase4"},
    ),
    _TemplateRule(
        name="event.preview_add_to_hand.065_trait_distinct",
        event_filter="ON_PLAY",
        matcher=_exact_text_match("自分の山札の上から5枚見る。その中から［特徴：ピュエラ・マギ・ホーリー・クインテット］を2枚まで公開し手札に加える。残りを望む順で自分の山札の下に置く。"),
        builder=_preview_add_to_hand_builder_factory(
            count=5,
            filters=[{"type": "HAS_TRAIT", "value": "ピュエラ・マギ・ホーリー・クインテット"}],
            max_count=2,
            distinct_by="CARD_NAME",
            kind="TRIGGERED",
        ),
        priority=200,
        template_metadata={"family": "PREVIEW_ADD_TO_HAND", "variant": "preview_add_to_hand_distinct_names"},
    ),
    _TemplateRule(
        name="event.bp_remove.required",
        event_filter="ON_PLAY",
        matcher=_regex_match(r"・?『?BP(\d+)以下』?の相手のフロントLのキャラを1枚選び、退場させる。"),
        builder=_bp_remove_from_match_builder_factory(min_count=1, max_count=1, kind="TRIGGERED"),
        priority=120,
        template_metadata={"family": "BP_THRESHOLD_REMOVE", "variant": "bp_threshold_remove_required"},
    ),
    _TemplateRule(
        name="event.bp_remove.optional",
        event_filter="ON_PLAY",
        matcher=_regex_match(r"BP(\d+)以下の相手のフロントLのキャラを1枚まで選び、退場させる。"),
        builder=_bp_remove_from_match_builder_factory(min_count=0, max_count=1, kind="TRIGGERED"),
        priority=110,
        template_metadata={"family": "BP_THRESHOLD_REMOVE", "variant": "bp_threshold_remove_optional"},
    ),
    _TemplateRule(
        name="event.bp_remove.dynamic_name_gate",
        event_filter="ON_PLAY",
        matcher=_regex_match(r"『?BP(\d+)以下』?の相手のフロントLのキャラを1枚選び、退場させる。自分の場に〈(.+)〉がある場合、『?BP(\d+)以下』?に代わる。"),
        builder=_bp_remove_dynamic_name_gate_builder,
        priority=125,
        template_metadata={"family": "BP_THRESHOLD_REMOVE", "variant": "bp_threshold_remove_dynamic_name_gate"},
    ),
    _TemplateRule(
        name="event.bp_remove.dynamic_name_contains_gate",
        event_filter="ON_PLAY",
        matcher=_regex_match(r"『?BP(\d+)以下』?の相手のフロントLのキャラを1枚選び、退場させる。自分の場にカード名に「(.+)」を含むキャラがある場合、『?BP(\d+)以下』?に代わる。"),
        builder=_bp_remove_dynamic_name_contains_gate_builder,
        priority=126,
        template_metadata={"family": "BP_THRESHOLD_REMOVE", "variant": "bp_threshold_remove_dynamic_name_contains_gate"},
    ),
    _TemplateRule(
        name="event.bp_remove_to_removed.dynamic_name_gate",
        event_filter="ON_PLAY",
        matcher=_regex_match(r"『?BP(\d+)以下』?の相手のフロントLのキャラを1枚選び、リムーブエリアに置く。自分の場に〈(.+)〉がある場合、『?BP(\d+)以下』?に代わる。"),
        builder=_bp_remove_to_removed_dynamic_name_gate_builder,
        priority=127,
        template_metadata={"family": "BP_THRESHOLD_REMOVE", "variant": "bp_threshold_remove_to_removed_dynamic_name_gate"},
    ),
    _TemplateRule(
        name="event.bp_remove.dynamic_sayaka_life",
        event_filter="ON_PLAY",
        matcher=_exact_text_match("『BP3000以下』の相手のフロントLのキャラを1枚選び、退場させる。自分の場に〈美樹 さやか〉があり、自分のライフが5以下の場合、『BP5000以下』に代わる。"),
        builder=_bp_remove_with_requirements_builder_factory(
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
            kind="TRIGGERED",
        ),
        priority=130,
        template_metadata={"family": "BP_THRESHOLD_REMOVE", "variant": "bp_threshold_remove_dynamic_sayaka_life"},
    ),
    _TemplateRule(
        name="event.bp_remove.dynamic_madoka",
        event_filter="ON_PLAY",
        matcher=_exact_text_match("『BP3000以下』の相手のフロントLのキャラを1枚選び、退場させる。自分の場に〈鹿目 まどか〉がある場合、『BP5000以下』に代わる。"),
        builder=_bp_remove_with_requirements_builder_factory(
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
            kind="TRIGGERED",
        ),
        priority=130,
        template_metadata={"family": "BP_THRESHOLD_REMOVE", "variant": "bp_threshold_remove_dynamic_madoka"},
    ),
    _TemplateRule(
        name="event.bp_sum_limit_remove.dynamic_energy_line",
        event_filter="ON_PLAY",
        matcher=_regex_match(r"BPの合計が自分のエナジーラインのカード枚数×(\d+)以下になるように相手のフロントLのキャラを(\d+)枚まで選び、退場させる。"),
        builder=_bp_sum_limit_remove_dynamic_energy_builder,
        priority=136,
        template_metadata={"family": "BP_SUM_LIMIT_REMOVE", "variant": "bp_sum_limit_remove_dynamic_energy_line"},
    ),
)


_PASSIVE_TEMPLATE_RULES: tuple[_TemplateRule, ...] = ()


def _compile_trigger(card: dict, trigger_entry: dict, semantic_map: dict[str, dict]) -> dict:
    return dispatch_template_rules(
        "trigger",
        _TRIGGER_TEMPLATE_RULES,
        card,
        trigger_entry,
        lambda current_card, current_entry: _compile_trigger_legacy(current_card, current_entry, semantic_map),
    )


def _compile_event_effect(card: dict, effect_entry: dict, semantic_map: dict[str, dict]) -> dict | None:
    pseudo_trigger = {
        "trigger": "ON_PLAY",
        "source_label": effect_entry.get("source_label", ""),
        "effect_box": effect_entry.get("effect_box", "OUTER"),
        "text": str(effect_entry.get("text", "")).strip(),
    }
    return _dispatch_template_rules(
        "event",
        _EVENT_TEMPLATE_RULES,
        card,
        pseudo_trigger,
        lambda current_card, current_entry: _compile_event_effect_legacy(current_card, effect_entry, semantic_map),
    )


def _compile_passive_effect(card: dict, effect_entry: dict) -> dict | None:
    pseudo_trigger = {
        "trigger": "PASSIVE",
        "source_label": effect_entry.get("source_label", ""),
        "effect_box": effect_entry.get("effect_box", "OUTER"),
        "text": str(effect_entry.get("text", "")).strip(),
    }
    return _dispatch_template_rules(
        "passive",
        _PASSIVE_TEMPLATE_RULES,
        card,
        pseudo_trigger,
        lambda current_card, _current_entry: _compile_passive_effect_legacy(current_card, effect_entry),
    )


def _build_card_effects(card: dict, semantic_map: dict[str, dict], source_label: str) -> dict:
    keywords = _infer_keywords(card)
    abilities = []
    if str(card.get("card_type", "")) != "EVENT":
        for effect_entry in card.get("effects", []):
            ability = _compile_passive_effect(card, effect_entry)
            if ability:
                abilities.append(ability)
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
            "source": source_label,
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


def _template_family_from_ability(ability: dict) -> str:
    template_metadata = ability.get("template_metadata")
    if isinstance(template_metadata, dict):
        family = str(template_metadata.get("family", "")).strip()
        if family:
            return family
    return ""


def _apply_stable_template_metadata(semantic_entry: dict, card_effects: dict) -> dict:
    template_types: list[str] = list(semantic_entry.get("template_types", []))
    for ability_entry, source_ability in zip(semantic_entry.get("abilities", []), card_effects.get("abilities", [])):
        family = _template_family_from_ability(source_ability)
        if not family:
            continue
        ability_entry["template_type"] = family
        if family not in template_types:
            template_types.append(family)
    semantic_entry["template_types"] = template_types
    return semantic_entry


def _requires_semantic_override(source_ability: dict) -> bool:
    if source_ability.get("status") != "UNSUPPORTED":
        return False
    compact_text = _compact_compiler_text(str(source_ability.get("ui", {}).get("text", "")))
    if not compact_text:
        return False
    if re.fullmatch(r"BP\d+以下の相手のフロントLのキャラを1枚選び、相手の山札の下に置く。", compact_text):
        return True
    if re.fullmatch(r"BPの合計が\d+以下になるように相手のフロントLのキャラを\d+枚まで選び、退場させる。", compact_text):
        return True
    if "山札の上から" in compact_text and "手札に加える。" in compact_text and "カード名に「" in compact_text:
        return True
    return False


def _apply_semantic_override_boundaries(semantic_entry: dict, card_effects: dict) -> dict:
    if any(_requires_semantic_override(source_ability) for source_ability in card_effects.get("abilities", [])):
        semantic_entry["unresolved_capabilities"] = [SEMANTIC_OVERRIDE_REQUIRED]
    return semantic_entry


def _build_semantic_entry(card_effects: dict) -> dict:
    semantic_entry = build_semantic_ir_entry(card_effects)
    semantic_entry = _apply_stable_template_metadata(semantic_entry, card_effects)
    return _apply_semantic_override_boundaries(semantic_entry, card_effects)


def _iter_series_raw_paths() -> list[Path]:
    paths = []
    if not CARDS_DIR.exists():
        return paths
    for child in sorted(CARDS_DIR.iterdir()):
        if not child.is_dir():
            continue
        raw_path = child / "cards_raw.json"
        if raw_path.exists():
            paths.append(raw_path)
    return paths


def _source_label_for_path(raw_path: Path) -> str:
    return raw_path.relative_to(CARDS_DIR).as_posix()


def _compile_series_cards(raw_path: Path) -> tuple[list[dict], list[dict]]:
    raw_cards = _load_json(raw_path)
    source_label = _source_label_for_path(raw_path)

    compiled = [_build_card_effects(card, {}, source_label) for card in raw_cards]
    semantic_entries = [_build_semantic_entry(card) for card in compiled]
    semantic_map = {entry.get("card_id", ""): entry for entry in semantic_entries if entry.get("card_id")}

    compiled = [_build_card_effects(card, semantic_map, source_label) for card in raw_cards]
    semantic_entries = [_build_semantic_entry(card) for card in compiled]
    return compiled, semantic_entries


def main() -> None:
    compiled_all = []
    semantic_all = []
    series_raw_paths = _iter_series_raw_paths()
    for raw_path in series_raw_paths:
        compiled, semantic_entries = _compile_series_cards(raw_path)
        semantic_path = raw_path.parent / "cards_semantic.json"
        out_path = raw_path.parent / "cards_effects.json"
        semantic_path.write_text(json.dumps(semantic_entries, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        out_path.write_text(json.dumps(compiled, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        compiled_all.extend(compiled)
        semantic_all.extend(semantic_entries)

    legacy_samples = _load_json(LEGACY_SAMPLE_PATH)
    runtime_cards = list(compiled_all)
    existing_ids = {card["id"] for card in runtime_cards}
    for sample in legacy_samples:
        sample_id = sample.get("id", "")
        if sample_id and sample_id not in existing_ids:
            runtime_cards.append(_legacy_to_effects(sample))
    semantic_all.extend(
        _build_semantic_entry(card) for card in runtime_cards if card.get("analysis", {}).get("source") == "base_cards.json"
    )

    supported = sum(1 for card in runtime_cards for ability in card["abilities"] if ability.get("status") == "SUPPORTED")
    unsupported = sum(1 for card in runtime_cards for ability in card["abilities"] if ability.get("status") == "UNSUPPORTED")
    print(f"Compiled {len(compiled_all)} series cards across {len(series_raw_paths)} directories.")
    print(f"Runtime card total with base samples: {len(runtime_cards)}")
    print(f"Supported abilities: {supported}")
    print(f"Unsupported abilities: {unsupported}")


if __name__ == "__main__":
    main()
