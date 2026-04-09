import re


def normalize_japanese_text(text) -> str:
    return re.sub(r"\s+", " ", str(text or "")).strip()


normalize_compiler_text = normalize_japanese_text

