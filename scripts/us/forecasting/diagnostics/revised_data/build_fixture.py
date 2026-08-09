#!/usr/bin/env python3
"""Acquire and build the quarantined revised/current-data panel fixture.

Network acquisition is explicit (``--acquire``).  Ordinary execution rebuilds
the tracked compact extracts and panel from previously captured raw responses.
The large BEA workbooks and raw BLS/New York Fed responses remain under
``data/us/raw``; hashes and selected HTTP metadata are preserved in the tracked
source receipt.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping

from revised_panel import (
    BEA_COLUMNS,
    BEA_TARGETS,
    BLS_COLUMNS,
    BLS_SERIES,
    EFFR_COLUMNS,
    EXPECTED_BEA_FINGERPRINT_SHA256,
    EXPECTED_END_PERIOD,
    EXPECTED_ROW_COUNT,
    EXPECTED_START_PERIOD,
    FIXTURE_DIR,
    INFORMATION_TRACK,
    PANEL_COLUMNS,
    RECEIPT_SCHEMA_VERSION,
    SCHEMA_VERSION,
    SOURCE_END_PERIOD,
    TARGET_COLUMNS,
    canonical_json_bytes,
    csv_bytes,
    derive_panel_bytes,
    load_bea_levels,
    load_bls_levels,
    load_effr_rates,
    sha256_bytes,
    sha256_file,
)

BASE_DIR = Path(__file__).resolve().parent
REPOSITORY_ROOT = BASE_DIR.parents[4]
DEFAULT_RAW_DIR = (
    REPOSITORY_ROOT
    / "data"
    / "us"
    / "raw"
    / "forecasting"
    / "revised_data"
    / "snapshot_2026-08-06"
)
DEFAULT_BEA_FINGERPRINT = (
    REPOSITORY_ROOT
    / "data"
    / "us"
    / "raw"
    / "bea_nipa"
    / "hmi7"
    / "receipts"
    / "objects"
    / "sha256-9265bc33d7e6ff71eb32e72f792104f982701321a7be16cedf92318aedeccedd"
    / (
        "content-fingerprint-sha256-"
        "a08c824620e30d09ebdb9bd35cadd1d9f45e36a7bf5b83e1d4d1551d1310bf33"
        ".json"
    )
)
BLS_URL = "https://api.bls.gov/publicAPI/v2/timeseries/data/"
BLS_WINDOWS = (("2000", "2009"), ("2010", "2019"), ("2020", "2026"))
EFFR_URL = (
    "https://markets.newyorkfed.org/api/rates/unsecured/effr/search.csv"
    "?startDate=2000-07-01&endDate=2026-06-30&type=rate"
)
USER_AGENT = "BeforeIT-US-revised-data-diagnostic/1.0"
SELECTED_HEADERS = {
    "cache-control",
    "content-disposition",
    "content-length",
    "content-type",
    "date",
    "etag",
    "last-modified",
    "x-correlation-id",
    "x-request-id",
}


class BuildError(RuntimeError):
    """Raised when acquisition or source normalization fails closed."""


def utc_now() -> str:
    return (
        datetime.now(timezone.utc)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z")
    )


def write_generated(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)


def selected_headers(response: Any) -> dict[str, str]:
    return {
        key.lower(): value
        for key, value in response.headers.items()
        if key.lower() in SELECTED_HEADERS
    }


def acquire_one(
    request: urllib.request.Request,
    destination: Path,
    *,
    request_body: bytes | None = None,
) -> dict[str, Any]:
    started_at = utc_now()
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            payload = response.read()
            completed_at = utc_now()
            status = response.status
            effective_url = response.url
            headers = selected_headers(response)
    except urllib.error.URLError as error:
        raise BuildError(
            f"acquisition failed for {request.full_url}: {error}"
        ) from error
    if status != 200:
        raise BuildError(f"HTTP {status} for {request.full_url}")
    write_generated(destination, payload)
    return {
        "requested_url": request.full_url,
        "effective_url": effective_url,
        "method": request.method,
        "request_body_sha256": (
            sha256_bytes(request_body) if request_body is not None else "not_applicable"
        ),
        "request_body_utf8": (
            request_body.decode("utf-8")
            if request_body is not None
            else "not_applicable"
        ),
        "http_status": status,
        "selected_response_headers": headers,
        "acquisition_started_at_utc": started_at,
        "acquisition_completed_at_utc": completed_at,
        "raw_byte_count": len(payload),
        "raw_sha256": sha256_bytes(payload),
        "raw_relative_path": str(destination.relative_to(REPOSITORY_ROOT)),
        "raw_bytes_checked_into_git": False,
    }


def acquire_sources(raw_dir: Path) -> dict[str, Any]:
    raw_dir.mkdir(parents=True, exist_ok=True)
    acquisitions: list[dict[str, Any]] = []
    for start_year, end_year in BLS_WINDOWS:
        body = json.dumps(
            {
                "seriesid": list(BLS_SERIES),
                "startyear": start_year,
                "endyear": end_year,
            },
            separators=(",", ":"),
        ).encode("utf-8")
        request = urllib.request.Request(
            BLS_URL,
            data=body,
            headers={
                "Content-Type": "application/json",
                "User-Agent": USER_AGENT,
            },
            method="POST",
        )
        acquisition = acquire_one(
            request,
            raw_dir / f"bls_{start_year}_{end_year}.json",
            request_body=body,
        )
        acquisition.update(
            {
                "source_id": f"bls_public_api_v2_{start_year}_{end_year}",
                "provider": "U.S. Bureau of Labor Statistics",
                "requested_start_year": start_year,
                "requested_end_year": end_year,
                "series_ids": list(BLS_SERIES),
            }
        )
        acquisitions.append(acquisition)

    effr_request = urllib.request.Request(
        EFFR_URL,
        headers={"Accept": "text/csv", "User-Agent": USER_AGENT},
        method="GET",
    )
    effr_acquisition = acquire_one(
        effr_request,
        raw_dir / "effr_2000-07-01_2026-06-30.csv",
    )
    effr_acquisition.update(
        {
            "source_id": "new_york_fed_effr_20000701_20260630",
            "provider": "Federal Reserve Bank of New York",
            "series_id": "EFFR",
            "requested_start_date": "2000-07-01",
            "requested_end_date": "2026-06-30",
        }
    )
    acquisitions.append(effr_acquisition)
    acquisition_receipt = {
        "schema_version": "beforeit-us-revised-data-raw-acquisition.v1",
        "acquisition_completed_at_utc": utc_now(),
        "raw_bytes_checked_into_git": False,
        "acquisitions": acquisitions,
    }
    write_generated(
        raw_dir / "acquisition_receipt.json",
        canonical_json_bytes(acquisition_receipt),
    )
    return acquisition_receipt


def load_raw_acquisition_receipt(raw_dir: Path) -> dict[str, Any]:
    path = raw_dir / "acquisition_receipt.json"
    payload = path.read_bytes()
    receipt = json.loads(payload)
    if canonical_json_bytes(receipt) != payload:
        raise BuildError("raw acquisition receipt is not canonical JSON")
    if receipt.get("schema_version") != (
        "beforeit-us-revised-data-raw-acquisition.v1"
    ):
        raise BuildError("raw acquisition receipt schema changed")
    if receipt.get("raw_bytes_checked_into_git") is not False:
        raise BuildError("raw acquisition receipt git boundary changed")
    acquisitions = receipt.get("acquisitions")
    if not isinstance(acquisitions, list) or len(acquisitions) != 4:
        raise BuildError("raw acquisition receipt must contain four responses")
    for acquisition in acquisitions:
        raw_path = REPOSITORY_ROOT / acquisition["raw_relative_path"]
        if raw_path.parent != raw_dir:
            raise BuildError("raw acquisition path escaped expected directory")
        if sha256_file(raw_path) != acquisition["raw_sha256"]:
            raise BuildError(f"raw response hash mismatch: {raw_path.name}")
        if raw_path.stat().st_size != acquisition["raw_byte_count"]:
            raise BuildError(f"raw response byte count mismatch: {raw_path.name}")
    return receipt


def normalize_bea(fingerprint_path: Path) -> tuple[bytes, dict[str, Any]]:
    if sha256_file(fingerprint_path) != EXPECTED_BEA_FINGERPRINT_SHA256:
        raise BuildError("BEA content fingerprint SHA-256 changed")
    fingerprint = json.loads(fingerprint_path.read_bytes())
    artifact = fingerprint.get("artifact", {})
    if artifact.get("origin_admissible") is not False:
        raise BuildError("BEA fingerprint origin boundary changed")
    if artifact.get("historical_availability_verified") is not False:
        raise BuildError("BEA fingerprint historical-availability boundary changed")
    targets = fingerprint.get("targets")
    if not isinstance(targets, list):
        raise BuildError("BEA fingerprint targets are missing")
    rows = []
    observed_targets = set()
    for target in targets:
        target_id = target.get("target_id")
        if target_id not in BEA_TARGETS:
            raise BuildError(f"unexpected BEA fingerprint target: {target_id!r}")
        observed_targets.add(target_id)
        observations = target.get("observations")
        if not isinstance(observations, list):
            raise BuildError(f"BEA {target_id} observations are missing")
        for observation in observations:
            period = observation.get("period", "")
            if period < "2000Q2" or period > SOURCE_END_PERIOD:
                continue
            published = observation.get("published_value_text")
            if published in {None, "....."}:
                raise BuildError(f"BEA {target_id}/{period} is missing")
            rows.append(
                {
                    "period": period,
                    "target_id": target_id,
                    "published_value": published,
                }
            )
    if observed_targets != set(BEA_TARGETS):
        raise BuildError("BEA fingerprint target set changed")
    rows.sort(key=lambda row: (row["period"], row["target_id"]))
    payload = csv_bytes(BEA_COLUMNS, rows)
    metadata = {
        "source_id": "bea_hmi7_2026q2_advance_content_fingerprint",
        "provider": "U.S. Bureau of Economic Analysis",
        "fingerprint_sha256": EXPECTED_BEA_FINGERPRINT_SHA256,
        "fingerprint_schema_version": artifact.get("schema_version"),
        "release_id": artifact.get("release_id"),
        "reference_quarter": artifact.get("reference_quarter"),
        "estimate_label": artifact.get("estimate_label"),
        "observation_count": len(rows),
        "first_period": rows[0]["period"],
        "last_period": rows[-1]["period"],
        "target_ids": list(BEA_TARGETS),
        "source_attribution": "Source: U.S. Bureau of Economic Analysis",
        "terms_url": "https://www.bea.gov/index.php/help/faq/145",
        "present_day_archive_content_observation": True,
        "historical_availability_verified": False,
        "forecast_origin_admissible": False,
    }
    return payload, metadata


def normalized_bls(
    raw_dir: Path,
    receipt: Mapping[str, Any],
) -> tuple[bytes, dict[str, Any]]:
    rows = []
    response_metadata = []
    observed_keys: set[tuple[str, str]] = set()
    unavailable_observations = []
    acquisition_by_id = {
        item["source_id"]: item for item in receipt["acquisitions"]
    }
    for start_year, end_year in BLS_WINDOWS:
        source_id = f"bls_public_api_v2_{start_year}_{end_year}"
        acquisition = acquisition_by_id.get(source_id)
        if acquisition is None:
            raise BuildError(f"missing raw receipt entry {source_id}")
        raw_path = raw_dir / f"bls_{start_year}_{end_year}.json"
        response = json.loads(raw_path.read_bytes())
        if response.get("status") != "REQUEST_SUCCEEDED":
            raise BuildError(f"{source_id} did not succeed")
        if response.get("message") not in ([], None):
            raise BuildError(f"{source_id} returned API messages")
        series_rows = response.get("Results", {}).get("series")
        if not isinstance(series_rows, list):
            raise BuildError(f"{source_id} series are missing")
        counts: dict[str, int] = {}
        bounds: dict[str, dict[str, str]] = {}
        seen_series = set()
        for series in series_rows:
            series_id = series.get("seriesID")
            if series_id not in BLS_SERIES:
                raise BuildError(f"{source_id} unexpected series {series_id!r}")
            if series_id in seen_series:
                raise BuildError(f"{source_id} duplicate series {series_id}")
            seen_series.add(series_id)
            series_observations = []
            for observation in series.get("data", []):
                period = observation.get("period", "")
                if not (
                    len(period) == 3
                    and period.startswith("M")
                    and period[1:].isdigit()
                    and 1 <= int(period[1:]) <= 12
                ):
                    continue
                month = f"{observation['year']}-{period[1:]}"
                key = (month, series_id)
                if key in observed_keys:
                    raise BuildError(f"duplicate BLS observation {key}")
                observed_keys.add(key)
                footnotes = observation.get("footnotes") or []
                codes = sorted(
                    {
                        str(footnote["code"])
                        for footnote in footnotes
                        if isinstance(footnote, dict) and footnote.get("code")
                    }
                )
                if observation["value"] == "-":
                    unavailable_observations.append(
                        {
                            "month": month,
                            "series_id": series_id,
                            "published_value": "-",
                            "footnote_codes": codes,
                            "footnote_texts": [
                                str(footnote["text"])
                                for footnote in footnotes
                                if isinstance(footnote, dict)
                                and footnote.get("text")
                            ],
                        }
                    )
                series_observations.append(month)
                rows.append(
                    {
                        "month": month,
                        "series_id": series_id,
                        "published_value": observation["value"].replace(",", ""),
                        "latest": (
                            "true"
                            if observation.get("latest") == "true"
                            else "false"
                        ),
                        "footnote_codes": "|".join(codes) if codes else "none",
                    }
                )
            series_observations.sort()
            counts[series_id] = len(series_observations)
            bounds[series_id] = {
                "first_month": series_observations[0],
                "last_month": series_observations[-1],
            }
        if seen_series != set(BLS_SERIES):
            raise BuildError(f"{source_id} series set changed")
        response_metadata.append(
            {
                **acquisition,
                "observation_counts": counts,
                "observation_bounds": bounds,
            }
        )
    rows.sort(key=lambda row: (row["month"], row["series_id"]))
    payload = csv_bytes(BLS_COLUMNS, rows)
    metadata = {
        "source_id": "bls_public_api_v2_current_revised_snapshot",
        "provider": "U.S. Bureau of Labor Statistics",
        "api_documentation_url": (
            "https://www.bls.gov/developers/api_signature_v2.htm"
        ),
        "series_ids": list(BLS_SERIES),
        "observation_count": len(rows),
        "first_month": rows[0]["month"],
        "last_month": rows[-1]["month"],
        "responses": response_metadata,
        "unavailable_observations": unavailable_observations,
        "unavailable_observation_count": len(unavailable_observations),
        "quarterly_aggregation_exception": (
            "LNS14000000 2025Q4 is not aggregated. October is unavailable "
            "under BLS footnote 9, and official BLS guidance says reliable "
            "2025Q4 quarterly estimates could not be produced with one-third "
            "of the quarter missing. The primary complete-case panel therefore "
            "ends at 2025Q3; no value is imputed."
        ),
        "shutdown_methodology_url": (
            "https://www.bls.gov/cps/methods/"
            "2025-federal-government-shutdown-impact-cps.htm"
        ),
        "current_revised_snapshot": True,
        "historical_release_state_verified": False,
        "forecast_origin_admissible": False,
    }
    return payload, metadata


def normalized_effr(
    raw_dir: Path,
    receipt: Mapping[str, Any],
) -> tuple[bytes, dict[str, Any]]:
    acquisition = next(
        (
            item
            for item in receipt["acquisitions"]
            if item["source_id"] == "new_york_fed_effr_20000701_20260630"
        ),
        None,
    )
    if acquisition is None:
        raise BuildError("EFFR raw receipt entry is missing")
    raw_path = raw_dir / "effr_2000-07-01_2026-06-30.csv"
    raw = raw_path.read_text(encoding="utf-8-sig")
    reader = csv.DictReader(io.StringIO(raw))
    required_columns = {
        "Effective Date",
        "Rate Type",
        "Rate (%)",
        "Revision Indicator (Y/N)",
    }
    if not required_columns.issubset(set(reader.fieldnames or ())):
        raise BuildError("EFFR response columns changed")
    raw_rows = list(reader)
    rows_by_date: dict[str, dict[str, str]] = {}
    for index, row in enumerate(raw_rows, start=2):
        published_date = row["Effective Date"]
        if published_date in rows_by_date:
            raise BuildError(f"duplicate EFFR date {published_date}")
        rows_by_date[published_date] = row

    anomaly_date = "07/20/2003"
    matching_date = "07/21/2003"
    anomaly = rows_by_date.get(anomaly_date)
    matching = rows_by_date.get(matching_date)
    if anomaly is None:
        raise BuildError("expected exact EFFR Sunday anomaly is absent")
    if matching is None:
        raise BuildError("EFFR Sunday anomaly has no adjacent Monday match")
    if anomaly["Rate Type"] != "EFFR" or anomaly["Rate (%)"] != "1.02":
        raise BuildError("expected EFFR Sunday anomaly identity changed")
    if matching["Rate Type"] != "EFFR" or matching["Rate (%)"] != "1.02":
        raise BuildError("EFFR Sunday anomaly Monday match identity changed")
    anomaly_fields = {
        key: value for key, value in anomaly.items() if key != "Effective Date"
    }
    matching_fields = {
        key: value for key, value in matching.items() if key != "Effective Date"
    }
    if anomaly_fields != matching_fields:
        raise BuildError(
            "EFFR Sunday anomaly does not exactly duplicate Monday fields"
        )
    paired_fields_sha256 = sha256_bytes(canonical_json_bytes(anomaly_fields))

    rows = []
    seen_dates = set()
    excluded_nonbusiness_dates = []
    raw_observation_count = 0
    for index, row in enumerate(raw_rows, start=2):
        raw_observation_count += 1
        if row["Rate Type"] != "EFFR":
            raise BuildError(f"EFFR row {index} has another rate type")
        effective_date = datetime.strptime(
            row["Effective Date"], "%m/%d/%Y"
        ).date()
        canonical_date = effective_date.isoformat()
        if canonical_date in seen_dates:
            raise BuildError(f"duplicate EFFR date {canonical_date}")
        seen_dates.add(canonical_date)
        if effective_date.weekday() >= 5:
            if canonical_date != "2003-07-20" or row["Rate (%)"] != "1.02":
                raise BuildError(
                    f"unexpected nonbusiness-date EFFR row {canonical_date}"
                )
            excluded_nonbusiness_dates.append(
                {
                    "effective_date": canonical_date,
                    "weekday": effective_date.strftime("%A"),
                    "rate_percent": row["Rate (%)"],
                    "matching_effective_date": "2003-07-21",
                    "matching_rate_percent": matching["Rate (%)"],
                    "identical_fields_excluding_effective_date": True,
                    "paired_published_fields_sha256": paired_fields_sha256,
                    "rule": (
                        "excluded_exact_known_duplicate_without_reassignment"
                    ),
                }
            )
            continue
        raw_indicator = row["Revision Indicator (Y/N)"].strip()
        rows.append(
            {
                "effective_date": canonical_date,
                "rate_percent": row["Rate (%)"],
                "revision_indicator": "Y" if raw_indicator else "N",
            }
        )
    rows.sort(key=lambda row: row["effective_date"])
    payload = csv_bytes(EFFR_COLUMNS, rows)
    metadata = {
        **acquisition,
        "source_id": "new_york_fed_effr_current_revised_snapshot",
        "series_id": "EFFR",
        "raw_observation_count": raw_observation_count,
        "observation_count": len(rows),
        "first_effective_date": rows[0]["effective_date"],
        "last_effective_date": rows[-1]["effective_date"],
        "aggregation": (
            "equal_weight_mean_of_published_business_date_rates_by_effective_date"
        ),
        "weekend_observations_imputed": False,
        "excluded_nonbusiness_observations": excluded_nonbusiness_dates,
        "excluded_nonbusiness_observation_count": len(
            excluded_nonbusiness_dates
        ),
        "current_revised_snapshot": True,
        "historical_release_state_verified": False,
        "forecast_origin_admissible": False,
        "source_page_url": (
            "https://www.newyorkfed.org/markets/reference-rates/effr"
        ),
        "api_documentation_url": (
            "https://markets.newyorkfed.org/static/docs/markets-api.html"
        ),
        "terms_url": "https://www.newyorkfed.org/privacy/termsofuse",
        "attribution": (
            "© 2026 Federal Reserve Bank of New York. Content from the "
            "New York Fed subject to the Terms of Use at newyorkfed.org."
        ),
        "reference_rate_notice": (
            "The Effective Federal Funds Rate data is subject to the Terms "
            "of Use posted at newyorkfed.org. The New York Fed is not "
            "responsible for publication of the Effective Federal Funds Rate "
            "data by BeforeIT, does not sanction or endorse any particular "
            "republication, and has no liability for your use."
        ),
        "modification_notice": (
            "Modified/derived by BeforeIT: published daily EFFR observations "
            "are equal-weight averaged by calendar quarter; no weekend "
            "observations are imputed."
        ),
    }
    return payload, metadata


def toml_quote(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def toml_string_array(values: list[str] | tuple[str, ...]) -> str:
    return "[" + ", ".join(toml_quote(value) for value in values) + "]"


def build_manifest(
    *,
    panel_sha256: str,
    receipt_sha256: str,
    bea_sha256: str,
    bls_sha256: str,
    effr_sha256: str,
    bea_count: int,
    bls_count: int,
    effr_count: int,
) -> bytes:
    lines = [
        f"schema_version = {toml_quote(SCHEMA_VERSION)}",
        'artifact_id = "beforeit-us-revised-data-eight-target-panel-2026q2.v1"',
        f"information_track = {toml_quote(INFORMATION_TRACK)}",
        "forecast_origin_admissible = false",
        "promotion_eligible = false",
        "abm_accuracy_claimed = false",
        "bitemporal = false",
        "real_time = false",
        "revised_current_release_snapshot = true",
        'evidence_class = "QUARANTINED_REVISED_CURRENT_RELEASE_DIAGNOSTIC_ONLY"',
        'panel_file = "quarterly_panel.csv"',
        f'panel_sha256 = "{panel_sha256}"',
        f"row_count = {EXPECTED_ROW_COUNT}",
        f'start_period = "{EXPECTED_START_PERIOD}"',
        f'end_period = "{EXPECTED_END_PERIOD}"',
        f"target_order = {toml_string_array(TARGET_COLUMNS)}",
        'source_receipts_file = "source_receipts.json"',
        f'source_receipts_sha256 = "{receipt_sha256}"',
        (
            'bea_content_fingerprint_sha256 = "'
            f'{EXPECTED_BEA_FINGERPRINT_SHA256}"'
        ),
        "",
        "[quarantine]",
        (
            'claim = "This current/revised mixed-vintage panel may exercise '
            'benchmark and scoring plumbing only; it cannot establish '
            'pseudo-real-time accuracy."'
        ),
        "historical_release_availability_verified = false",
        "first_release_truth = false",
        "near_mature_truth = false",
        "mature_truth = false",
        "inventory_registered = false",
        "origin_count_added = 0",
        "abm_forecast_scores_added = 0",
        "",
        "[complete_case_boundary]",
        (
            'rule = "Primary eight-target panel ends before the first quarter '
            'without all three monthly CPS unemployment observations."'
        ),
        'first_excluded_period = "2025Q4"',
        'missing_source_observation = "LNS14000000 2025-10"',
        (
            'official_guidance_url = "https://www.bls.gov/cps/methods/'
            '2025-federal-government-shutdown-impact-cps.htm"'
        ),
        (
            'rationale = "BLS states it could not produce reliable 2025Q4 '
            'quarterly estimates with one-third of the quarter missing."'
        ),
        "two_month_mean_used = false",
        "missing_value_imputed = false",
        "post_gap_source_observations_retained = true",
        f'post_gap_source_end_period = "{SOURCE_END_PERIOD}"',
        "",
        "[build]",
        'generator_file = "../build_fixture.py"',
        f'generator_sha256 = "{sha256_file(Path(__file__).resolve())}"',
        'decimal_log_precision = "50 significant decimal digits"',
        'panel_decimal_places = 12',
        'csv_encoding = "UTF-8"',
        'csv_line_endings = "LF"',
        "",
        "[sources.bea_quarterly_levels]",
        'file = "bea_quarterly_levels.csv"',
        f'sha256 = "{bea_sha256}"',
        f"row_count = {bea_count}",
        'start_period = "2000Q2"',
        f'end_period = "{SOURCE_END_PERIOD}"',
        (
            'lineage = "Pinned BEA HMI7 2026Q2 advance present-day content '
            'fingerprint; published values only."'
        ),
        "",
        "[sources.bls_monthly_levels]",
        'file = "bls_monthly_levels.csv"',
        f'sha256 = "{bls_sha256}"',
        f"row_count = {bls_count}",
        'start_month = "2000-01"',
        'end_month = "2026-06"',
        (
            'lineage = "BLS Public Data API v2 present-day current/revised '
            'responses, split into three ten-or-fewer-year requests."'
        ),
        "",
        "[sources.effr_daily_rates]",
        'file = "effr_daily_rates.csv"',
        f'sha256 = "{effr_sha256}"',
        f"row_count = {effr_count}",
        'start_effective_date = "2000-07-03"',
        'end_effective_date = "2026-06-30"',
        (
            'lineage = "New York Fed EFFR search.csv current/revised response; '
            'one row per published effective business date."'
        ),
        "",
        "[transformations.bea_growth_and_prices]",
        (
            'targets = ["real_gdp", "pce_price_index", '
            '"core_pce_price_index", "gdp_deflator", "nominal_gdp"]'
        ),
        'rule = "400 * ln(level_t / level_t_minus_1)"',
        'output_unit = "percentage_points_annual_rate"',
        "",
        "[transformations.payroll_employment]",
        'source_series = "CES0000000001"',
        (
            'rule = "quarterly arithmetic mean of three monthly levels, then '
            '100 * ln(mean_t / mean_t_minus_1)"'
        ),
        'output_unit = "log_points"',
        "",
        "[transformations.unemployment_rate]",
        'source_series = "LNS14000000"',
        (
            'rule = "quarterly arithmetic mean only when all three monthly '
            'percent levels are published"'
        ),
        (
            'missing_month_boundary = "BLS reports LNS14000000 2025-10 as '
            'unavailable under footnote 9 (2025 lapse in appropriations); '
            'the primary complete-case panel stops at 2025Q3."'
        ),
        "two_month_mean_used = false",
        "missing_month_values_imputed = false",
        'output_unit = "percentage_points"',
        "",
        "[transformations.effective_federal_funds_rate]",
        'source_series = "EFFR"',
        (
            'rule = "equal-weight arithmetic mean of all published rates in '
            'the quarter whose effective dates are Monday through Friday"'
        ),
        "weekends_imputed = false",
        (
            'published_nonbusiness_date_exception = "The API response contains '
            'one exact Sunday-labelled row, 2003-07-20 at 1.02, whose published '
            'fields other than date exactly duplicate the adjacent 2003-07-21 '
            'row. It is retained in the pinned raw-response hash but excluded '
            'without reassignment. Any other weekend row or pair drift fails."'
        ),
        'output_unit = "percentage_points"',
        "",
        "[source_terms.bea]",
        'attribution = "Source: U.S. Bureau of Economic Analysis"',
        'terms_url = "https://www.bea.gov/index.php/help/faq/145"',
        "",
        "[source_terms.bls]",
        'attribution = "Source: U.S. Bureau of Labor Statistics"',
        (
            'api_documentation_url = '
            '"https://www.bls.gov/developers/api_signature_v2.htm"'
        ),
        "",
        "[source_terms.new_york_fed]",
        (
            'attribution = "© 2026 Federal Reserve Bank of New York. Content '
            'from the New York Fed subject to the Terms of Use at '
            'newyorkfed.org."'
        ),
        (
            'reference_rate_notice = "The Effective Federal Funds Rate data '
            'is subject to the Terms of Use posted at newyorkfed.org. The New '
            'York Fed is not responsible for publication of the Effective '
            'Federal Funds Rate data by BeforeIT, does not sanction or endorse '
            'any particular republication, and has no liability for your use."'
        ),
        (
            'modification_notice = "Modified/derived by BeforeIT: published '
            'daily EFFR observations are equal-weight averaged by calendar '
            'quarter; no weekend observations are imputed."'
        ),
        'terms_url = "https://www.newyorkfed.org/privacy/termsofuse"',
        (
            'source_page_url = '
            '"https://www.newyorkfed.org/markets/reference-rates/effr"'
        ),
    ]
    return ("\n".join(lines) + "\n").encode("utf-8")


def build_fixture(
    raw_dir: Path,
    fingerprint_path: Path,
    fixture_dir: Path,
) -> dict[str, Any]:
    raw_receipt = load_raw_acquisition_receipt(raw_dir)
    bea_bytes, bea_metadata = normalize_bea(fingerprint_path)
    bls_bytes, bls_metadata = normalized_bls(raw_dir, raw_receipt)
    effr_bytes, effr_metadata = normalized_effr(raw_dir, raw_receipt)

    write_generated(fixture_dir / "bea_quarterly_levels.csv", bea_bytes)
    write_generated(fixture_dir / "bls_monthly_levels.csv", bls_bytes)
    write_generated(fixture_dir / "effr_daily_rates.csv", effr_bytes)
    load_bea_levels(fixture_dir / "bea_quarterly_levels.csv")
    load_bls_levels(fixture_dir / "bls_monthly_levels.csv")
    effr_rates = load_effr_rates(fixture_dir / "effr_daily_rates.csv")

    source_receipt = {
        "schema_version": RECEIPT_SCHEMA_VERSION,
        "artifact_id": (
            "beforeit-us-revised-data-source-receipts-2026-08-06.v1"
        ),
        "information_track": INFORMATION_TRACK,
        "forecast_origin_admissible": False,
        "promotion_eligible": False,
        "abm_accuracy_claimed": False,
        "bitemporal": False,
        "real_time": False,
        "revised_current_release_snapshot": True,
        "raw_bytes_checked_into_git": False,
        "acquisition_completed_at_utc": raw_receipt[
            "acquisition_completed_at_utc"
        ],
        "bea_content_fingerprint_sha256": EXPECTED_BEA_FINGERPRINT_SHA256,
        "sources": {
            "bea": bea_metadata,
            "bls": bls_metadata,
            "new_york_fed_effr": effr_metadata,
        },
    }
    receipt_bytes = canonical_json_bytes(source_receipt)
    write_generated(fixture_dir / "source_receipts.json", receipt_bytes)

    panel_bytes = derive_panel_bytes(
        fixture_dir / "bea_quarterly_levels.csv",
        fixture_dir / "bls_monthly_levels.csv",
        fixture_dir / "effr_daily_rates.csv",
    )
    write_generated(fixture_dir / "quarterly_panel.csv", panel_bytes)

    manifest_bytes = build_manifest(
        panel_sha256=sha256_bytes(panel_bytes),
        receipt_sha256=sha256_bytes(receipt_bytes),
        bea_sha256=sha256_bytes(bea_bytes),
        bls_sha256=sha256_bytes(bls_bytes),
        effr_sha256=sha256_bytes(effr_bytes),
        bea_count=len(bea_bytes.decode("utf-8").splitlines()) - 1,
        bls_count=len(bls_bytes.decode("utf-8").splitlines()) - 1,
        effr_count=len(effr_rates),
    )
    write_generated(fixture_dir / "manifest.toml", manifest_bytes)
    return {
        "fixture_dir": str(fixture_dir),
        "manifest_sha256": sha256_bytes(manifest_bytes),
        "panel_sha256": sha256_bytes(panel_bytes),
        "source_receipts_sha256": sha256_bytes(receipt_bytes),
        "row_count": EXPECTED_ROW_COUNT,
        "start_period": EXPECTED_START_PERIOD,
        "end_period": EXPECTED_END_PERIOD,
        "source_counts": {
            "bea": bea_metadata["observation_count"],
            "bls": bls_metadata["observation_count"],
            "effr": effr_metadata["observation_count"],
        },
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--acquire",
        action="store_true",
        help="acquire fresh BLS and New York Fed responses before building",
    )
    parser.add_argument("--raw-dir", type=Path, default=DEFAULT_RAW_DIR)
    parser.add_argument(
        "--bea-fingerprint",
        type=Path,
        default=DEFAULT_BEA_FINGERPRINT,
    )
    parser.add_argument("--fixture-dir", type=Path, default=FIXTURE_DIR)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.acquire:
        acquire_sources(args.raw_dir)
    result = build_fixture(
        args.raw_dir.resolve(),
        args.bea_fingerprint.resolve(),
        args.fixture_dir.resolve(),
    )
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (BuildError, OSError, ValueError, KeyError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1) from error
