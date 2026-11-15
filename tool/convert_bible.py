"""성경 역본 JSON을 앱 형식(assets/bible/*.json)으로 변환합니다.

원본: https://github.com/thiagobodruk/bible (json/ 폴더)
  - ko_krv.json : 개역한글 (Korean Revised Version, 1961)
  - en_kjv.json : King James Version

앱 형식은 [{"abbrev", "name", "chapters": [[절, ...], ...]}, ...] 66권 배열입니다.
책 이름은 앱에서 한글 이름으로 통일하므로 여기서는 원본 값을 그대로 둡니다.

사용법:
  python3 tool/convert_bible.py <원본.json> <출력.json>
"""

import json
import sys


def convert(src_path: str, out_path: str) -> None:
    with open(src_path, encoding="utf-8-sig") as f:
        data = json.load(f)

    if not isinstance(data, list) or len(data) != 66:
        raise SystemExit(f"66권 배열이 아닙니다: {src_path}")

    books = []
    for i, book in enumerate(data):
        chapters = book.get("chapters")
        if not isinstance(chapters, list) or not chapters:
            raise SystemExit(f"{i + 1}번째 권에 장 데이터가 없습니다")
        books.append(
            {
                "abbrev": str(book.get("abbrev", "")),
                "name": str(book.get("name", "")),
                "chapters": [
                    [str(v or "").strip() for v in chapter] for chapter in chapters
                ],
            }
        )

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(books, f, ensure_ascii=False, separators=(",", ":"))

    chapter_count = sum(len(b["chapters"]) for b in books)
    verse_count = sum(len(c) for b in books for c in b["chapters"])
    print(f"{out_path}: 66권, {chapter_count}장, {verse_count}절")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    convert(sys.argv[1], sys.argv[2])
