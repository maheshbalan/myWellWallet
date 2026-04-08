#!/usr/bin/env python3
"""
Export MyWellWallet SQLite to Markdown + CSV files suitable for Dify Knowledge upload.

Usage:
  python3 scripts/export_sqlite_for_dify.py [path/to.db] [output_dir]

Default DB: fixtures/test_database_export/mywellwallet_phone.sqlite3
Default out: <db_dir>/dify_export

Does not export `users` unless --include-users is passed (PII).
"""

from __future__ import annotations

import argparse
import csv
import json
import sqlite3
import sys
from pathlib import Path


HEALTH_TABLES = [
    "health_glucose",
    "health_heart_rate",
    "health_steps",
    "health_blood_pressure",
    "health_lab_results",
    "health_sync_settings",
]

OPTIONAL_TABLES = ["fetch_summaries"]


def export_fhir_markdown(conn: sqlite3.Connection, out_path: Path) -> int:
    cur = conn.execute(
        """
        SELECT patient_id, resource_type, resource_id, resource_data, updated_at
        FROM fhir_resources
        ORDER BY patient_id, resource_type, resource_id
        """
    )
    rows = cur.fetchall()
    lines: list[str] = [
        "# FHIR resources (exported from MyWellWallet SQLite)",
        "",
        "Each block is one row from `fhir_resources`. JSON is verbatim from `resource_data`.",
        "",
    ]
    for patient_id, rtype, rid, data, updated_at in rows:
        pretty = data
        try:
            pretty = json.dumps(json.loads(data), indent=2)
        except (json.JSONDecodeError, TypeError):
            pass
        lines.append(f"## {rtype} / {rid}")
        lines.append("")
        lines.append(f"- **patient_id:** `{patient_id}`")
        lines.append(f"- **updated_at:** `{updated_at}`")
        lines.append("")
        lines.append("```json")
        lines.append(pretty)
        lines.append("```")
        lines.append("")

    out_path.write_text("\n".join(lines), encoding="utf-8")
    return len(rows)


def export_table_csv(conn: sqlite3.Connection, table: str, out_path: Path) -> int:
    cur = conn.execute(f"SELECT * FROM {table}")
    colnames = [d[0] for d in cur.description]
    rows = cur.fetchall()
    with out_path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(colnames)
        w.writerows(rows)
    return len(rows)


def main() -> int:
    parser = argparse.ArgumentParser(description="Export SQLite to Dify-friendly MD/CSV.")
    parser.add_argument(
        "db_path",
        nargs="?",
        default="fixtures/test_database_export/mywellwallet_phone.sqlite3",
        help="Path to mywellwallet SQLite file",
    )
    parser.add_argument(
        "out_dir",
        nargs="?",
        default="",
        help="Output directory (default: <db_parent>/dify_export)",
    )
    parser.add_argument(
        "--include-users",
        action="store_true",
        help="Also export users.csv (contains PII — do not upload to public Dify)",
    )
    args = parser.parse_args()

    db_path = Path(args.db_path).resolve()
    if not db_path.is_file():
        print(f"Database not found: {db_path}", file=sys.stderr)
        return 1

    out_dir = Path(args.out_dir).resolve() if args.out_dir else db_path.parent / "dify_export"
    out_dir.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(str(db_path))

    md_path = out_dir / "knowledge_fhir_resources.md"
    n_fhir = export_fhir_markdown(conn, md_path)
    print(f"Wrote {n_fhir} resources -> {md_path}")

    total_csv = 0
    for table in HEALTH_TABLES + OPTIONAL_TABLES:
        try:
            n = export_table_csv(conn, table, out_dir / f"{table}.csv")
            print(f"Wrote {n} rows -> {out_dir / f'{table}.csv'}")
            total_csv += n
        except sqlite3.OperationalError as e:
            print(f"Skip {table}: {e}", file=sys.stderr)

    if args.include_users:
        n = export_table_csv(conn, "users", out_dir / "users.csv")
        print(f"Wrote {n} rows -> {out_dir / 'users.csv'} (PII)")

    conn.close()
    print(f"Done. Upload files under {out_dir} to Dify Knowledge (see docs/DATABASE_FIXTURE_TESTING_AND_DIFY.md).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
