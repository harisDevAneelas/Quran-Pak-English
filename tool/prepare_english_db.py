#!/usr/bin/env python3
"""Copy duas and mushaf division columns into the English database.

Reads assets/data/database.sqlite. Writes only assets/data/english_db.sqlite.
"""

from __future__ import annotations

import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENGLISH = ROOT / "assets" / "data" / "english_db.sqlite"
URDU = ROOT / "assets" / "data" / "database.sqlite"

QURAN_COLUMNS = ("RukuStart", "ParaStart", "ParaRubaStart")
DROP_TABLES = ("Audio", "Bookmark", "Words", "SearchWords2")


def column_names(conn: sqlite3.Connection, table: str) -> set[str]:
    return {
        row[1]
        for row in conn.execute(f"PRAGMA main.table_info({table})")
    }


def table_names(conn: sqlite3.Connection) -> set[str]:
    rows = conn.execute(
        "SELECT name FROM sqlite_master WHERE type = 'table'"
    ).fetchall()
    return {row[0] for row in rows}


def main() -> None:
    if not ENGLISH.is_file():
        raise SystemExit(f"missing {ENGLISH}")
    if not URDU.is_file():
        raise SystemExit(f"missing {URDU}")

    conn = sqlite3.connect(ENGLISH)
    try:
        conn.execute("ATTACH DATABASE ? AS urdu", (str(URDU),))
        conn.execute("BEGIN")

        # Schema-qualify every name. An unqualified DROP would hit urdu.QuraniDua.
        conn.execute("DROP TABLE IF EXISTS main.QuraniDua")
        conn.execute(
            """
            CREATE TABLE main.QuraniDua (
              QuraniDuaId INTEGER PRIMARY KEY,
              DuaId TEXT NOT NULL,
              DuaNumber INTEGER NOT NULL,
              SuraNum INTEGER NOT NULL,
              AyaFrom INTEGER NOT NULL,
              AyaTo INTEGER NOT NULL,
              DuaText TEXT,
              DuaWords TEXT
            )
            """
        )
        conn.execute(
            """
            INSERT INTO main.QuraniDua (
              QuraniDuaId, DuaId, DuaNumber, SuraNum, AyaFrom, AyaTo,
              DuaText, DuaWords
            )
            SELECT
              QuraniDuaId, DuaId, DuaNumber, SuraNum, AyaFrom, AyaTo,
              DuaText, DuaWords
            FROM urdu.QuraniDua
            """
        )

        quran_cols = column_names(conn, "Quran")
        for column in QURAN_COLUMNS:
            if column not in quran_cols:
                conn.execute(
                    f"ALTER TABLE main.Quran ADD COLUMN {column} NUMERIC"
                )

        # One indexed lookup per ayah. A correlated scan of the Urdu file
        # rereads tens of megabytes for every row.
        conn.execute(
            """
            CREATE TEMP TABLE division (
              SuraNum NUMERIC NOT NULL,
              AyaNum NUMERIC NOT NULL,
              RukuStart NUMERIC,
              ParaStart NUMERIC,
              ParaRubaStart NUMERIC
            )
            """
        )
        conn.execute(
            """
            INSERT INTO division (SuraNum, AyaNum, RukuStart, ParaStart, ParaRubaStart)
            SELECT SuraNum, AyaNum, RukuStart, ParaStart, ParaRubaStart
            FROM urdu.Quran
            """
        )
        conn.execute(
            "CREATE INDEX division_key ON division (SuraNum, AyaNum)"
        )
        conn.execute(
            """
            UPDATE main.Quran
            SET
              RukuStart = (
                SELECT d.RukuStart FROM division AS d
                WHERE d.SuraNum = main.Quran.SuraNum
                  AND d.AyaNum = main.Quran.AyaNum
              ),
              ParaStart = (
                SELECT d.ParaStart FROM division AS d
                WHERE d.SuraNum = main.Quran.SuraNum
                  AND d.AyaNum = main.Quran.AyaNum
              ),
              ParaRubaStart = (
                SELECT d.ParaRubaStart FROM division AS d
                WHERE d.SuraNum = main.Quran.SuraNum
                  AND d.AyaNum = main.Quran.AyaNum
              )
            """
        )

        if "UrduName" not in column_names(conn, "Juz"):
            conn.execute("ALTER TABLE main.Juz ADD COLUMN UrduName TEXT")
        conn.execute(
            """
            UPDATE main.Juz
            SET UrduName = (
              SELECT u.UrduName FROM urdu.Juz AS u
              WHERE u.JuzNum = main.Juz.JuzNum
            )
            """
        )

        for table in DROP_TABLES:
            conn.execute(f"DROP TABLE IF EXISTS main.{table}")

        missing = conn.execute(
            """
            SELECT COUNT(*) FROM main.Quran
            WHERE RukuStart IS NULL OR ParaStart IS NULL OR ParaRubaStart IS NULL
            """
        ).fetchone()[0]
        if missing:
            raise SystemExit(f"{missing} ayahs missing division columns")

        dua_count = conn.execute(
            "SELECT COUNT(*) FROM main.QuraniDua"
        ).fetchone()[0]
        if dua_count != 112:
            raise SystemExit(f"expected 112 duas, got {dua_count}")

        juz_missing = conn.execute(
            """
            SELECT COUNT(*) FROM main.Juz
            WHERE UrduName IS NULL OR UrduName = ''
            """
        ).fetchone()[0]
        if juz_missing:
            raise SystemExit(f"{juz_missing} juz rows missing UrduName")

        conn.commit()
    except BaseException:
        conn.rollback()
        raise

    try:
        conn.execute("VACUUM")
        left = table_names(conn) & set(DROP_TABLES)
        if left:
            raise SystemExit(f"tables still present: {sorted(left)}")
        print(
            f"english db ready: {dua_count} duas, "
            f"division columns filled, dropped {', '.join(DROP_TABLES)}"
        )
    finally:
        conn.close()


if __name__ == "__main__":
    main()
