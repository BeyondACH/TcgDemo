from tools.card_effects_compiler.normalization import normalize_japanese_text as normalize_compiler_text


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


def build_semantic_entry(card_effects: dict) -> dict:
    abilities = []
    unresolved_capabilities = []
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
        reason = normalize_compiler_text(ability.get("unsupported_reason", ""))
        if reason and reason not in unresolved_capabilities:
            unresolved_capabilities.append(reason)

    source_text_jp = {
        "effect": card_effects.get("card_meta", {}).get("text", {}).get("effect", ""),
        "trigger": card_effects.get("card_meta", {}).get("text", {}).get("trigger", ""),
        "rule": card_effects.get("card_meta", {}).get("text", {}).get("rule", ""),
    }
    has_raw_text = any(str(value).strip() not in {"", "-"} for value in source_text_jp.values())
    can_be_expressed = True
    if abilities:
        can_be_expressed = all(entry.get("status") == "SUPPORTED" for entry in abilities)
    elif has_raw_text:
        can_be_expressed = False
        unresolved_capabilities.append(normalize_compiler_text("当前卡牌文本尚未映射为能力对象。"))

    analysis = card_effects.get("analysis", {})
    return {
        "card_id": card_effects.get("id", ""),
        "origin": analysis.get("origin", analysis.get("source", "")),
        "inferred_keywords": card_effects.get("card_meta", {}).get("keywords", []),
        "template_types": template_types,
        "abilities": abilities,
        "can_be_expressed_by_dsl": can_be_expressed,
        "unresolved_capabilities": unresolved_capabilities,
        "source_text_jp": source_text_jp,
    }
