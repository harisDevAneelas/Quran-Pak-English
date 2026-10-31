#!/usr/bin/env python3
"""Split quran.colored.json into per-surah files under assets/data/surahs/."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/data/quran.colored.json"
OUT_DIR = ROOT / "assets/data/surahs"


def main() -> None:
    data = json.loads(SRC.read_text(encoding="utf-8"))
    by_surah: dict[int, dict] = {}
    for key, value in data.items():
        surah = int(key.split(":")[0])
        by_surah.setdefault(surah, {})[key] = value

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for surah in range(1, 115):
        path = OUT_DIR / f"{surah:03d}.json"
        path.write_text(
            json.dumps(
                by_surah.get(surah, {}),
                ensure_ascii=False,
                separators=(",", ":"),
            ),
            encoding="utf-8",
        )
    print(f"Wrote {OUT_DIR} ({len(list(OUT_DIR.glob('*.json')))} files)")


if __name__ == "__main__":
    main()
