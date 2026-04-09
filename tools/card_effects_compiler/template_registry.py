from .normalization import normalize_japanese_text

_DEFAULT_TRIGGER_TEMPLATE_RULES = ()


def _compact_japanese_text(text) -> str:
    return normalize_japanese_text(text).replace(" ", "")


def _exact_text_match(expected_text: str):
    normalized_expected_text = _compact_japanese_text(expected_text)

    def _matcher(_card: dict, _entry: dict, text: str, _card_id: str):
        if _compact_japanese_text(text) == normalized_expected_text:
            return {}
        return None

    return _matcher


def _regex_match(pattern: str):
    import re

    compiled = re.compile(pattern)

    def _matcher(_card: dict, _entry: dict, text: str, _card_id: str):
        match = compiled.fullmatch(_compact_japanese_text(text))
        if match:
            return {"match": match}
        return None

    return _matcher


def _dispatch_template_rules(
    registry_name: str,
    rules,
    card: dict,
    trigger_entry: dict,
    fallback,
):
    event_name = str(trigger_entry.get("trigger", ""))
    text = normalize_japanese_text(trigger_entry.get("text", ""))
    card_id = str(card.get("id", ""))
    for rule in rules:
        if not _event_matches(rule.event_filter, event_name):
            continue
        if rule.card_filter is not None and not rule.card_filter(card_id):
            continue
        payload = rule.matcher(card, trigger_entry, text, card_id)
        if payload is None:
            continue
        _record_template_hit(rule.name)
        return rule.builder(card, trigger_entry, event_name, text, card_id, payload)
    _record_template_fallback(registry_name)
    return fallback(card, trigger_entry)


def dispatch_template_rules(
    registry_name: str,
    rules,
    card: dict,
    trigger_entry: dict,
    fallback,
):
    return _dispatch_template_rules(registry_name, rules, card, trigger_entry, fallback)


def set_trigger_template_rules(rules) -> None:
    global _DEFAULT_TRIGGER_TEMPLATE_RULES
    _DEFAULT_TRIGGER_TEMPLATE_RULES = rules


def dispatch_trigger_template(card: dict, trigger_entry: dict, fallback):
    return _dispatch_template_rules("trigger", _DEFAULT_TRIGGER_TEMPLATE_RULES, card, trigger_entry, fallback)


def _event_matches(rule_event, event_name: str) -> bool:
    if isinstance(rule_event, tuple):
        return event_name in rule_event
    return event_name == rule_event


def _record_template_hit(_rule_name: str) -> None:
    return None


def _record_template_fallback(_registry_name: str) -> None:
    return None
