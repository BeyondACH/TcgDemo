import json
import re
import sys
from pathlib import Path
from typing import Any, Iterable
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, unquote, urlencode, urlparse, urlunparse
from urllib.request import Request, urlopen


SOURCE_URL = (
    "https://uapcapi.windoent.com/card/card/weblist?name=&onlyName=&good=%E9%AD%94%E6%B3%95%E5%B0%91%E5%A5%B3%E5%B0%8F%E5%9C%86+%E8%A1%A5%E5%85%85%E5%8C%85+%E3%80%90UA31BT%E3%80%91&parallel=&cardType=&color=%E7%B4%AB&energyStart=&energyEnd=&energyNumColor=&energyNum=&consumerAp=&BPStart=&BPEnd=&keyWord=&triggerType=&feature=&rarity=&works=&page=1&limit=50"
)
OUTPUT_DIR = Path(__file__).resolve().parent / "purple"
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) CardScraper/1.0"


def fetch_json(url: str) -> dict:
    request = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(request, timeout=30) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        return json.loads(response.read().decode(charset))


def find_first_list_of_dicts(node: Any) -> list[dict]:
    if isinstance(node, list):
        dict_items = [item for item in node if isinstance(item, dict)]
        if dict_items:
            return dict_items
        for item in node:
            result = find_first_list_of_dicts(item)
            if result:
                return result

    if isinstance(node, dict):
        for preferred_key in ("list", "rows", "result", "records", "data"):
            value = node.get(preferred_key)
            result = find_first_list_of_dicts(value)
            if result:
                return result
        for value in node.values():
            result = find_first_list_of_dicts(value)
            if result:
                return result

    return []


def extract_total_pages(payload: dict, page_size: int) -> int | None:
    candidates = (
        payload.get("pages"),
        payload.get("totalPage"),
        payload.get("pageCount"),
    )
    for candidate in candidates:
        if isinstance(candidate, int) and candidate > 0:
            return candidate

    total_candidates = (
        payload.get("total"),
        payload.get("count"),
        payload.get("totalCount"),
    )
    for candidate in total_candidates:
        if isinstance(candidate, int) and candidate > 0:
            return (candidate + page_size - 1) // page_size
    return None


def find_image_urls(node: Any) -> list[str]:
    found: list[str] = []

    if isinstance(node, str):
        value = node.strip()
        lower_value = value.lower()
        if lower_value.startswith(("http://", "https://")) and re.search(
            r"\.(png|jpe?g|webp)(?:$|[?#])", lower_value
        ):
            found.append(value)
        return found

    if isinstance(node, list):
        for item in node:
            found.extend(find_image_urls(item))
        return found

    if isinstance(node, dict):
        for key, value in node.items():
            key_text = str(key).lower()
            if "image" in key_text or "img" in key_text or "pic" in key_text:
                found.extend(find_image_urls(value))
                continue
            if isinstance(value, (dict, list)):
                found.extend(find_image_urls(value))
            elif isinstance(value, str):
                found.extend(find_image_urls(value))
        return found

    return found


def build_page_url(url: str, page: int) -> str:
    parsed = urlparse(url)
    params = parse_qs(parsed.query, keep_blank_values=True)
    params["page"] = [str(page)]
    new_query = urlencode(params, doseq=True)
    return urlunparse(parsed._replace(query=new_query))


def iter_image_urls(source_url: str) -> Iterable[str]:
    parsed = urlparse(source_url)
    params = parse_qs(parsed.query)
    page_size = int(params.get("limit", ["20"])[0])
    current_page = int(params.get("page", ["1"])[0])
    total_pages = None

    while True:
        page_url = build_page_url(source_url, current_page)
        payload = fetch_json(page_url)
        items = find_first_list_of_dicts(payload)
        if not items:
            break

        for item in items:
            for image_url in find_image_urls(item):
                yield image_url

        total_pages = total_pages or extract_total_pages(payload, page_size)
        current_page += 1

        if total_pages is not None and current_page > total_pages:
            break


def filename_from_image_url(image_url: str) -> str:
    path_name = Path(unquote(urlparse(image_url).path)).name
    match = re.search(r"(UA[^/?#]+)", path_name, flags=re.IGNORECASE)
    return match.group(1) if match else path_name


def download_file(url: str, destination: Path) -> None:
    request = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(request, timeout=60) as response:
        destination.write_bytes(response.read())


def main() -> int:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    seen: set[str] = set()
    downloaded = 0
    skipped_existing = 0
    failed: list[tuple[str, str]] = []

    try:
        for image_url in iter_image_urls(SOURCE_URL):
            if image_url in seen:
                continue
            seen.add(image_url)

            file_name = filename_from_image_url(image_url)
            target = OUTPUT_DIR / file_name
            if target.exists() and target.stat().st_size > 0:
                skipped_existing += 1
                print(f"Skipped existing: {target.name}")
                continue

            try:
                download_file(image_url, target)
                downloaded += 1
                print(f"Downloaded: {target.name}")
            except HTTPError as exc:
                failed.append((image_url, f"HTTP {exc.code}"))
                print(f"Skipped failed: {file_name} ({exc.code})", file=sys.stderr)
            except URLError as exc:
                failed.append((image_url, f"URL error: {exc.reason}"))
                print(f"Skipped failed: {file_name} ({exc.reason})", file=sys.stderr)
    except Exception as exc:  # pragma: no cover
        print(f"Download failed: {exc}", file=sys.stderr)
        return 1

    if downloaded == 0 and skipped_existing == 0:
        print(
            "No images found in the response. The API fields may have changed; "
            "please save one page of JSON and inspect it.",
            file=sys.stderr,
        )
        return 1

    print(
        f"Finished. Downloaded {downloaded} images to: {OUTPUT_DIR}. "
        f"Skipped existing: {skipped_existing}. Failed: {len(failed)}."
    )
    if failed:
        print("Failed URLs:", file=sys.stderr)
        for url, reason in failed:
            print(f"- {reason}: {url}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
