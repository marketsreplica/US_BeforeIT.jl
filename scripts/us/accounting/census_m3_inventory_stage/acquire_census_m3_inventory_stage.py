#!/usr/bin/env python3
"""Acquire one exact Census M3 current-vintage inventory workbook.

This command is intentionally separate from fixture regeneration.  The Census
URL names a mutable current workbook rather than an immutable release vintage.
An acquisition therefore writes the exact response bytes beside a receipt and
refuses to overwrite an existing capture.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import urllib.request
import zipfile
from datetime import datetime, timezone
from pathlib import Path


SOURCE_URL = (
    "https://www.census.gov/manufacturing/m3/prel/historical_data/"
    "histshts/naics/naicsinvp.xlsx"
)
DEFAULT_OUTPUT = (
    Path(__file__).resolve().parent
    / "raw"
    / "census_m3_naicsinvp_2026-08-06_current_vintage"
)
EXPECTED_CONTENT_TYPE = (
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
)
REQUIRED_MEMBERS = {
    "[Content_Types].xml",
    "_rels/.rels",
    "xl/workbook.xml",
    "xl/_rels/workbook.xml.rels",
    "xl/worksheets/sheet1.xml",
    "xl/sharedStrings.xml",
}


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    output = arguments.output_dir.resolve()
    workbook_path = output / "naicsinvp.xlsx"
    receipt_path = output / "source_receipt.json"
    if workbook_path.exists() or receipt_path.exists():
        raise FileExistsError(
            "refusing to overwrite an existing source capture: "
            f"{output}"
        )

    request = urllib.request.Request(
        SOURCE_URL,
        headers={
            "Accept": EXPECTED_CONTENT_TYPE,
            "User-Agent": (
                "BeforeIT-US-accounting-evidence/1.0 "
                "(public Census source acquisition)"
            ),
        },
    )
    retrieved_at = datetime.now(timezone.utc).replace(microsecond=0)
    with urllib.request.urlopen(request, timeout=60) as response:
        payload = response.read()
        status = response.status
        final_url = response.geturl()
        headers = {
            name.lower(): response.headers.get(name)
            for name in (
                "Date",
                "Last-Modified",
                "Content-Type",
                "Content-Disposition",
                "Content-Length",
                "ETag",
            )
            if response.headers.get(name) is not None
        }

    if status != 200:
        raise RuntimeError(f"unexpected HTTP status {status}")
    if final_url != SOURCE_URL:
        raise RuntimeError(f"unexpected final URL {final_url!r}")
    content_type = headers.get("content-type", "").split(";", 1)[0]
    if content_type != EXPECTED_CONTENT_TYPE:
        raise RuntimeError(f"unexpected content type {content_type!r}")

    output.mkdir(parents=True, exist_ok=False)
    workbook_path.write_bytes(payload)
    with zipfile.ZipFile(workbook_path) as archive:
        names = set(archive.namelist())
        missing = sorted(REQUIRED_MEMBERS - names)
        if missing:
            raise RuntimeError(
                f"workbook is missing required ZIP members: {missing}"
            )
        bad_member = archive.testzip()
        if bad_member is not None:
            raise RuntimeError(f"workbook ZIP CRC failed at {bad_member}")
        workbook_xml = archive.read("xl/workbook.xml").decode("utf-8")

    period_match = re.search(
        r"Saved-histshts\\(?P<year>[0-9]{4})\\(?P<month>[A-Za-z]{3}[0-9]{2})\\",
        workbook_xml,
    )
    period_hint = (
        f"{period_match.group('year')}/{period_match.group('month')}"
        if period_match is not None
        else None
    )
    receipt = {
        "schema_version": "beforeit-us-census-m3-source-receipt.v1",
        "retrieved_at_utc": retrieved_at.isoformat().replace("+00:00", "Z"),
        "request_url": SOURCE_URL,
        "final_url": final_url,
        "http_status": status,
        "selected_response_headers": headers,
        "byte_count": len(payload),
        "sha256": sha256_hex(payload),
        "zip_member_count": len(names),
        "zip_crc_pass": True,
        "workbook_internal_period_hint": period_hint,
        "source_url_mutability": (
            "OVERWRITTEN_CURRENT_WORKBOOK_URL_NO_RELEASE_VINTAGE_IN_PATH"
        ),
        "immutable_release_vintage_claimed": False,
    }
    receipt_path.write_text(
        json.dumps(receipt, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"workbook_path={workbook_path}")
    print(f"source_receipt_path={receipt_path}")
    print(f"byte_count={len(payload)}")
    print(f"sha256={sha256_hex(payload)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
