import argparse
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from typing import Any, Iterable
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, unquote, urlencode, urlparse, urlunparse
from urllib.request import Request, urlopen


API_BASE_URL = "https://uapcapi.windoent.com/card/card/weblist"
ATTR_WEBLIST_URL = "https://uapcapi.windoent.com/card/card/attrweblist"
DEFAULT_WORK = "魔法少女小圆"
DEFAULT_PRODUCT = "魔法少女小圆 补充包【UA31BT】"
DEFAULT_COLOR = "紫"
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) CardScraper/1.0"
SOURCE_URL = ""


def prepare_text_stream(stream: Any) -> Any:
    reconfigure = getattr(stream, "reconfigure", None)
    if callable(reconfigure):
        try:
            reconfigure(errors="backslashreplace")
        except ValueError:
            pass
    return stream


def console_print(*args: Any, sep: str = " ", end: str = "\n", file: Any = None) -> None:
    stream = prepare_text_stream(sys.stdout if file is None else file)
    print(*args, sep=sep, end=end, file=stream)


def fetch_json(url: str) -> dict:
    request = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(request, timeout=30) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        return json.loads(response.read().decode(charset))


def build_source_url(
    *,
    product: str = DEFAULT_PRODUCT,
    works: str = "",
    page: int = 1,
    limit: int = 50,
) -> str:
    params = {"page": str(page), "limit": str(limit)}
    normalized_works = normalize_text(works)
    if normalized_works:
        params["works"] = normalized_works
    else:
        params["good"] = product
    return f"{API_BASE_URL}?{urlencode(params)}"


def sanitize_path_component(text: str) -> str:
    cleaned = re.sub(r'[\\/:*?"<>|]+', "_", text).strip()
    cleaned = re.sub(r"\s+", "_", cleaned)
    return cleaned or "images"


def default_output_dir(title_code: str, color: str | None = None) -> Path:
    base_dir = Path(__file__).resolve().parent / "pic"
    return base_dir / sanitize_path_component(title_code)


def infer_title_code_from_local_data(work: str) -> str | None:
    normalized_work = normalize_text(work)
    if not normalized_work:
        return None
    cards_root = Path(__file__).resolve().parent / "data" / "cards"
    if not cards_root.exists():
        return None
    for series_dir in sorted(path for path in cards_root.iterdir() if path.is_dir()):
        raw_path = series_dir / "cards_raw.json"
        if not raw_path.exists():
            continue
        try:
            payload = json.loads(raw_path.read_text(encoding="utf-8"))
        except Exception:
            continue
        if not isinstance(payload, list):
            continue
        for item in payload:
            if not isinstance(item, dict):
                continue
            if normalize_text(str(item.get("series_title", ""))) != normalized_work:
                continue
            title_code = normalize_text(str(item.get("title_code", "")))
            if title_code:
                return title_code
    return None


def normalize_text(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


class SelectOptionParser(HTMLParser):
    def __init__(self, *, select_id: str) -> None:
        super().__init__(convert_charrefs=True)
        self.select_id = select_id
        self._select_depth = 0
        self._capture_option = False
        self._current_value = ""
        self._current_text: list[str] = []
        self.options: list[dict[str, str]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attr_map = dict(attrs)

        if tag == "select" and attr_map.get("id") == self.select_id:
            self._select_depth = 1
            return

        if self._select_depth:
            if tag == "option":
                self._capture_option = True
                self._current_value = (attr_map.get("value") or "").strip()
                self._current_text = []
            else:
                self._select_depth += 1

    def handle_endtag(self, tag: str) -> None:
        if not self._select_depth:
            return

        if tag == "option" and self._capture_option:
            self.options.append(
                {
                    "value": self._current_value,
                    "text": normalize_text("".join(self._current_text)),
                }
            )
            self._capture_option = False
            self._current_value = ""
            self._current_text = []
            return

        self._select_depth -= 1

    def handle_data(self, data: str) -> None:
        if self._capture_option:
            self._current_text.append(data)


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


def extract_products_from_attr_data(data: dict[str, Any]) -> list[dict[str, str]]:
    goods = data.get("goods")
    if not isinstance(goods, list):
        raise RuntimeError("Failed to parse goods from attrweblist.")

    seen_ids: set[str] = set()
    products: list[dict[str, str]] = []
    for item in goods:
        if not isinstance(item, dict):
            continue
        product_id = str(item.get("id", "")).strip()
        product_name = normalize_text(str(item.get("name", "")))
        if not product_id or not product_name:
            continue
        if product_id in seen_ids:
            continue
        seen_ids.add(product_id)
        products.append({"id": product_id, "name": product_name})
    if not products:
        raise RuntimeError("Failed to parse goods from attrweblist.")
    return products


def extract_titles_from_attr_data(data: dict[str, Any]) -> list[str]:
    works = data.get("works")
    if not isinstance(works, list):
        raise RuntimeError("Failed to parse works from attrweblist.")

    titles: list[str] = []
    for item in works:
        if not isinstance(item, dict):
            continue
        work_id = str(item.get("id", "")).strip()
        work_name = normalize_text(str(item.get("name", "")))
        if not work_id or not work_name:
            continue
        titles.append(work_name)
    if not titles:
        raise RuntimeError("Failed to parse works from attrweblist.")
    return titles


def fetch_attr_data() -> dict[str, Any]:
    try:
        payload = fetch_json(ATTR_WEBLIST_URL)
    except Exception as exc:  # pragma: no cover
        raise RuntimeError(f"Failed to fetch attrweblist: {exc}") from exc

    data = payload.get("data")
    if not isinstance(data, dict):
        raise RuntimeError("Failed to parse attrweblist payload.")
    return data


def get_attr_goods() -> list[dict[str, str]]:
    return extract_products_from_attr_data(fetch_attr_data())


def get_attr_works() -> list[str]:
    return extract_titles_from_attr_data(fetch_attr_data())


def infer_work_from_product_name(product_name: str, works: list[str]) -> str | None:
    normalized_product = normalize_text(product_name)
    matching_works = [
        work for work in works if work and normalize_text(work) in normalized_product
    ]
    if not matching_works:
        return None
    return max(matching_works, key=len)


def prompt_for_product_selection(products: list[dict[str, str]]) -> dict[str, str]:
    console_print("Official products:")
    for index, product in enumerate(products, start=1):
        console_print(f"{index}. {product['name']} [{product['id']}]")

    selected = input("Enter product number to download: ").strip()
    if not selected.isdigit():
        raise ValueError(f"Invalid product number: {selected or '<empty>'}")

    selected_index = int(selected)
    if selected_index < 1 or selected_index > len(products):
        raise ValueError(f"Invalid product number: {selected_index}")

    return products[selected_index - 1]


def prompt_for_work_selection(works: list[str]) -> str:
    console_print("Official works:")
    for index, work in enumerate(works, start=1):
        console_print(f"{index}. {work}")

    selected = input("Enter work number to download: ").strip()
    if not selected.isdigit():
        raise ValueError(f"Invalid work number: {selected or '<empty>'}")

    selected_index = int(selected)
    if selected_index < 1 or selected_index > len(works):
        raise ValueError(f"Invalid work number: {selected_index}")

    return works[selected_index - 1]


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


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Download UNION ARENA card images for a selected work."
    )
    parser.add_argument("--work", default=DEFAULT_WORK, help="Official work title.")
    parser.add_argument(
        "--title-code",
        help="Title code used for the output directory, for example MMM or TLR.",
    )
    parser.add_argument(
        "--product",
        default=DEFAULT_PRODUCT,
        help="Optional product name filter from the official card list.",
    )
    parser.add_argument("--color", default=DEFAULT_COLOR, help="Card color filter.")
    parser.add_argument(
        "--limit", type=int, default=50, help="API page size. Default: 50."
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="Directory for downloaded images. Defaults to pic/<title_code>.",
    )
    parser.add_argument(
        "--print-url",
        action="store_true",
        help="Print the resolved SOURCE_URL before downloading.",
    )
    parser.add_argument(
        "--list-products",
        action="store_true",
        help="List product names and IDs from the official Japanese card list page.",
    )
    parser.add_argument(
        "--list-works",
        action="store_true",
        help="List official works, pick one by number, then download all images for it.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    global SOURCE_URL
    args = parse_args(argv)

    if args.list_products:
        try:
            products = get_attr_goods()
            works = get_attr_works()
        except Exception as exc:
            console_print(exc, file=sys.stderr)
            return 1

        try:
            selected_product = prompt_for_product_selection(products)
        except ValueError as exc:
            console_print(exc, file=sys.stderr)
            return 1

        inferred_work = infer_work_from_product_name(selected_product["name"], works)
        if not inferred_work:
            console_print(
                f"Could not infer work for selected product: {selected_product['name']}",
                file=sys.stderr,
            )
            return 1

        args.product = selected_product["name"]
        args.work = inferred_work

    if args.list_works:
        try:
            works = get_attr_works()
        except Exception as exc:
            console_print(exc, file=sys.stderr)
            return 1

        try:
            args.work = prompt_for_work_selection(works)
        except ValueError as exc:
            console_print(exc, file=sys.stderr)
            return 1

        args.product = ""

    SOURCE_URL = build_source_url(
        product=args.product,
        works=args.work if args.list_works else "",
        limit=args.limit,
    )
    title_code = normalize_text(str(args.title_code or ""))
    if not title_code:
        inferred_title_code = infer_title_code_from_local_data(args.work)
        if inferred_title_code:
            title_code = inferred_title_code
    if not title_code:
        title_code = sanitize_path_component(args.work)
    output_dir = args.output_dir or default_output_dir(title_code)
    output_dir.mkdir(parents=True, exist_ok=True)

    if args.print_url:
        console_print(f"SOURCE_URL={SOURCE_URL}")

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
            target = output_dir / file_name
            if target.exists() and target.stat().st_size > 0:
                skipped_existing += 1
                console_print(f"Skipped existing: {target.name}")
                continue

            try:
                download_file(image_url, target)
                downloaded += 1
                console_print(f"Downloaded: {target.name}")
            except HTTPError as exc:
                failed.append((image_url, f"HTTP {exc.code}"))
                console_print(f"Skipped failed: {file_name} ({exc.code})", file=sys.stderr)
            except URLError as exc:
                failed.append((image_url, f"URL error: {exc.reason}"))
                console_print(
                    f"Skipped failed: {file_name} ({exc.reason})", file=sys.stderr
                )
    except Exception as exc:  # pragma: no cover
        console_print(f"Download failed: {exc}", file=sys.stderr)
        return 1

    if downloaded == 0 and skipped_existing == 0:
        console_print(
            "No images found in the response. The API fields may have changed; "
            "please save one page of JSON and inspect it.",
            file=sys.stderr,
        )
        return 1

    console_print(
        f"Finished. Downloaded {downloaded} images to: {output_dir}. "
        f"Skipped existing: {skipped_existing}. Failed: {len(failed)}."
    )
    if failed:
        console_print("Failed URLs:", file=sys.stderr)
        for url, reason in failed:
            console_print(f"- {reason}: {url}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
