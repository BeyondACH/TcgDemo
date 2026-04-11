#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from html import unescape
from pathlib import Path
from typing import Dict, List
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

DETAIL_IFRAME_URL = "https://www.unionarena-tcg.com/jp/cardlist/detail_iframe.php?card_no={card_no}"
DETAIL_URL = "https://www.unionarena-tcg.com/jp/cardlist/detail.php?card_no={card_no}"
HEADERS = {
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
    "Accept-Language": "ja,en-US;q=0.9,en;q=0.8",
    "Referer": "https://www.unionarena-tcg.com/jp/cardlist/",
    "User-Agent": "Mozilla/5.0",
}

TYPE_MAP = {
    "キャラクター": "CHARACTER",
    "イベント": "EVENT",
    "フィールド": "FIELD",
}
TRIGGER_MAP = {
    "登場時": "ON_ENTER",
    "アタック時": "ON_ATTACK",
    "ブロック時": "ON_BLOCK",
    "退場時": "ON_LEAVE",
    "メイン": "MAIN_ACTIVATE",
    "起動メイン": "MAIN_ACTIVATE",
}
COLOR_MAP = {
    "赤": "RED",
    "青": "BLUE",
    "緑": "GREEN",
    "紫": "PURPLE",
    "黄": "YELLOW",
    "白": "WHITE",
}

KEYWORDS = {
    "レイド": "RAID",
    "2回攻撃": "DOUBLE_ATTACK",
    "2回ブロック": "DOUBLE_BLOCK",
    "狙い撃ち": "SNIPER",
    "ダメージ2": "DAMAGE_2",
    "インパクト+1": "IMPACT_PLUS_1",
    "インパクト無効": "NEGATE_IMPACT",
    "インパクト": "IMPACT",
    "ステップ": "STEP",
}


def normalize_space(text: str) -> str:
    return re.sub(r"\s+", " ", text.replace("\r", " ").replace("\n", " ")).strip()


def strip_tags(html: str) -> str:
    html = re.sub(r"(?is)<br\s*/?>", "\n", html)
    html = re.sub(r"(?is)<[^>]+>", "", html)
    html = unescape(html)
    lines = [re.sub(r"[ \t]+", " ", x).strip() for x in html.replace("\r", "").split("\n")]
    lines = [x for x in lines if x and x != "-"]
    return "\n".join(lines).strip()


def get_single(html: str, pattern: str) -> str:
    m = re.search(pattern, html, flags=re.S)
    return unescape(m.group(1).strip()) if m else ""


def get_block_html(html: str, class_name: str) -> str:
    pattern = rf'<dl class="cardDataCol {re.escape(class_name)}">.*?<dd class="cardDataContents">(.*?)</dd>'
    return get_single(html, pattern)


def parse_int(text: str) -> int:
    m = re.search(r"\d+", text or "")
    return int(m.group(0)) if m else 0


def parse_energy_map(block_html: str) -> Dict[str, int]:
    out: Dict[str, int] = {}
    for alt in re.findall(r'alt="([^"]+)"', block_html or ""):
        alt = unescape(alt)
        for jp, code in COLOR_MAP.items():
            m = re.fullmatch(re.escape(jp) + r"(\d+|\+)?", alt)
            if m:
                suffix = m.group(1)
                v = 1 if not suffix or suffix == "+" else int(suffix)
                out[code] = out.get(code, 0) + v
                break
            if re.fullmatch(f"(?:{re.escape(jp)})+", alt):
                cnt = len(re.findall(re.escape(jp), alt))
                out[code] = out.get(code, 0) + cnt
                break
    return out


def parse_cost_energy(block_html: str) -> Dict[str, int]:
    parsed = parse_energy_map(block_html)
    if parsed:
        return parsed
    scalar = parse_int(strip_tags(block_html))
    if scalar <= 0:
        return {}
    return {"COLORLESS": scalar}


def parse_labeled_lines(block_html: str) -> List[dict]:
    out = []
    if not block_html:
        return out
    for line in re.sub(r"(?is)<br\s*/?>", "\n", block_html).split("\n"):
        line = line.strip()
        if not line or line == "-":
            continue
        labels = []
        for alt in re.findall(r'alt="([^"]+)"', line):
            alt = unescape(alt)
            if re.fullmatch(r"(赤|青|緑|紫|黄|白)(?:×|x|X)?\d+", alt):
                continue
            labels.append(alt)
        out.append({"labels": labels, "inline_labels": labels.copy(), "text": strip_tags(line)})
    return out


def split_effect_and_trigger_entries(entries: List[dict]) -> tuple[List[dict], List[dict]]:
    effects: List[dict] = []
    triggers: List[dict] = []
    for entry in entries:
        trigger_name = ""
        for lb in entry.get("labels", []):
            if lb in TRIGGER_MAP:
                trigger_name = TRIGGER_MAP[lb]
                break
        if trigger_name:
            routed = dict(entry)
            routed["trigger"] = trigger_name
            triggers.append(routed)
            continue
        effects.append(entry)
    return effects, triggers


def convert_number_to_id(number: str) -> str:
    return number.replace("/", "_").replace("-", "_")


def candidates_from_file(stem: str) -> List[str]:
    stem = re.sub(r"_\d+$", "", stem)
    m = re.fullmatch(r"(UA\d+(?:BT|ST))-([A-Z0-9]+)-(.+)", stem)
    if not m:
        return [stem]
    set_code, title_code, suffix = m.groups()
    cands = [f"{set_code}/{title_code}-{suffix}"]
    if re.fullmatch(r"\d{3}", suffix):
        cands.append(f"{set_code}/{title_code}-1-{suffix}")
    return cands


def parse_card_page(html: str, source_image: str) -> dict:
    name = get_single(html, r'<h2 class="cardNameCol">\s*(.*?)\s*<span class="rubyData">')
    ruby = get_single(html, r'<span class="rubyData">(.*?)</span>')
    number = get_single(html, r'<span class="cardNumData">(.*?)</span>')
    rarity = get_single(html, r'<span class="rareData">(.*?)</span>')
    series_title = get_single(html, r'<dd class="cardDataTitleCol[^>]*><img[^>]+alt="([^"]+)"')

    category_text = strip_tags(get_block_html(html, "categoryData"))
    card_type = TYPE_MAP.get(category_text, "CHARACTER")

    traits_text = strip_tags(get_block_html(html, "attributeData"))
    traits = [normalize_space(x) for x in re.split(r"[／/]", traits_text) if normalize_space(x) and normalize_space(x) != "-"]

    parsed_effects = parse_labeled_lines(get_block_html(html, "effectData"))
    effects, triggers = split_effect_and_trigger_entries(parsed_effects)
    triggers.extend(parse_labeled_lines(get_block_html(html, "triggerData")))
    for t in triggers:
        trigger_name = ""
        for lb in t.get("labels", []):
            if lb in TRIGGER_MAP:
                trigger_name = TRIGGER_MAP[lb]
                break
        t["trigger"] = trigger_name or "ON_LIFE_TRIGGER"

    text_pool = "\n".join([x.get("text", "") for x in effects + triggers] + [" ".join(sum([x.get("labels", []) for x in effects + triggers], []))])
    keywords: List[str] = []
    for jp, key in KEYWORDS.items():
        if jp in text_pool and key not in keywords:
            keywords.append(key)

    title_code = ""
    m = re.match(r"^UA\d+(?:BT|ST)/([A-Z0-9]+)-", number)
    if m:
        title_code = m.group(1)

    card = {
        "id": convert_number_to_id(number),
        "name": name,
        "card_type": card_type,
        "title_code": title_code,
        "number": number,
        "traits": traits,
        "cost_energy": parse_cost_energy(get_block_html(html, "needEnergyData")),
        "cost_ap": parse_int(strip_tags(get_block_html(html, "apData"))),
        "energy_provided": parse_energy_map(get_block_html(html, "generatedEnergyData")),
        "bp": parse_int(strip_tags(get_block_html(html, "bpData"))),
        "keywords": keywords,
        "effects": effects,
        "trigger_effects": triggers,
        "rarity": rarity,
        "series_title": series_title,
        "source_image": source_image,
        "source_url": DETAIL_URL.format(card_no=number),
        "raw_effect_text": "\n".join([x.get("text", "") for x in effects if x.get("text")]).strip(),
        "raw_trigger_text": "\n".join([x.get("text", "") for x in triggers if x.get("text")]).strip(),
        "ruby": ruby,
    }
    if "RAID" in keywords:
        raid_target = ""
        raid_match = re.search(r"[〈《]([^〉》]+)[〉》]", card["raw_effect_text"] or "")
        if raid_match:
            raid_target = raid_match.group(1)
        card["special_play_rule"] = {
            "type": "RAID",
            "raid_target_name": raid_target,
            "allow_from_hand": True,
            "require_full_energy": True,
        }
    return card


def fetch_html(card_no: str) -> str:
    url = DETAIL_IFRAME_URL.format(card_no=quote(card_no, safe="/"))
    req = Request(url, headers=HEADERS)
    with urlopen(req, timeout=20) as resp:
        return resp.read().decode("utf-8", errors="ignore")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pic-root", default="pic")
    ap.add_argument("--cards-root", default="data/cards")
    ap.add_argument("--series", default="MCR")
    args = ap.parse_args()

    pic_dir = Path(args.pic_root) / args.series
    cards_path = Path(args.cards_root) / args.series / "cards_raw.json"
    cards_path.parent.mkdir(parents=True, exist_ok=True)

    existing = []
    if cards_path.exists():
        existing = json.loads(cards_path.read_text(encoding="utf-8"))

    by_number = {c.get("number"): c for c in existing if c.get("number")}
    by_id = {c.get("id"): c for c in existing if c.get("id")}

    imgs = [p for p in sorted(pic_dir.iterdir()) if p.is_file() and p.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp"}]
    added = 0
    for img in imgs:
        cands = candidates_from_file(img.stem)
        hit = None
        for cand in cands:
            try:
                html = fetch_html(cand)
            except (HTTPError, URLError, TimeoutError):
                continue
            parsed_num = get_single(html, r'<span class="cardNumData">(.*?)</span>')
            if parsed_num != cand:
                continue
            card = parse_card_page(html, img.name)
            if not card.get("id") or not card.get("number"):
                continue
            hit = card
            break
        if not hit:
            continue
        if hit["number"] in by_number or hit["id"] in by_id:
            continue
        by_number[hit["number"]] = hit
        by_id[hit["id"]] = hit
        added += 1

    out = sorted(by_number.values(), key=lambda x: x.get("number", ""))
    cards_path.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"series={args.series} total={len(out)} added={added} file={cards_path}")


if __name__ == "__main__":
    main()
