#!/usr/bin/env python3
"""Load, derive, and verify the quarantined revised-data U.S. target panel.

This module is intentionally independent of the real-time forecast-origin
registry.  It accepts only the pinned, compact source extracts in ``fixtures``
and rejects metadata that presents the result as bitemporal, origin-admissible,
promotion-eligible, or evidence of ABM forecast accuracy.
"""

from __future__ import annotations

import csv
import hashlib
import io
import json
import math
import re
import tomllib
from collections import defaultdict
from dataclasses import dataclass
from datetime import date, datetime
from decimal import Decimal, InvalidOperation, localcontext
from pathlib import Path
from typing import Iterable, Mapping, Sequence

SCHEMA_VERSION = "beforeit-us-revised-data-quarterly-panel.v1"
RECEIPT_SCHEMA_VERSION = "beforeit-us-revised-data-source-receipts.v1"
INFORMATION_TRACK = "revised_mixed_vintage_diagnostic"
EXPECTED_MANIFEST_SHA256 = (
    "fc5209e35bb0d04986c2f8c96563f0c21ad511680753ecc7e6d77f0d8435fb3f"
)
EXPECTED_BEA_FINGERPRINT_SHA256 = (
    "a08c824620e30d09ebdb9bd35cadd1d9f45e36a7bf5b83e1d4d1551d1310bf33"
)
EXPECTED_START_PERIOD = "2000Q3"
EXPECTED_END_PERIOD = "2025Q3"
EXPECTED_ROW_COUNT = 101
SOURCE_END_PERIOD = "2026Q2"

BASE_DIR = Path(__file__).resolve().parent
FIXTURE_DIR = BASE_DIR / "fixtures"
MANIFEST_PATH = FIXTURE_DIR / "manifest.toml"
PANEL_PATH = FIXTURE_DIR / "quarterly_panel.csv"
RECEIPT_PATH = FIXTURE_DIR / "source_receipts.json"
BEA_SOURCE_PATH = FIXTURE_DIR / "bea_quarterly_levels.csv"
BLS_SOURCE_PATH = FIXTURE_DIR / "bls_monthly_levels.csv"
EFFR_SOURCE_PATH = FIXTURE_DIR / "effr_daily_rates.csv"

TARGET_COLUMNS = (
    "real_gdp",
    "pce_price_index",
    "core_pce_price_index",
    "gdp_deflator",
    "unemployment_rate",
    "payroll_employment",
    "effective_federal_funds_rate",
    "nominal_gdp",
)
PANEL_COLUMNS = ("period", *TARGET_COLUMNS)
BEA_TARGETS = (
    "real_gdp",
    "pce_price_index",
    "core_pce_price_index",
    "gdp_deflator",
    "nominal_gdp",
)
BEA_COLUMNS = ("period", "target_id", "published_value")
BLS_COLUMNS = (
    "month",
    "series_id",
    "published_value",
    "latest",
    "footnote_codes",
)
EFFR_COLUMNS = ("effective_date", "rate_percent", "revision_indicator")
BLS_SERIES = {
    "CES0000000001": "payroll_employment",
    "LNS14000000": "unemployment_rate",
}
PERIOD_PATTERN = re.compile(r"(19|20)[0-9]{2}Q[1-4]\Z")
MONTH_PATTERN = re.compile(r"(19|20)[0-9]{2}-(0[1-9]|1[0-2])\Z")


class RevisedPanelError(RuntimeError):
    """Raised when a source, transformation, or quarantine check fails."""


@dataclass(frozen=True)
class FixtureVerification:
    manifest_sha256: str
    panel_sha256: str
    receipt_sha256: str
    row_count: int
    start_period: str
    end_period: str
    effr_observation_count: int


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def canonical_json_bytes(value: object) -> bytes:
    return (
        json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        + "\n"
    ).encode("utf-8")


def decimal_value(text: str, location: str, *, positive: bool = False) -> Decimal:
    try:
        value = Decimal(text)
    except InvalidOperation as error:
        raise RevisedPanelError(f"{location} is not decimal: {text!r}") from error
    if not value.is_finite():
        raise RevisedPanelError(f"{location} must be finite")
    if positive and value <= 0:
        raise RevisedPanelError(f"{location} must be positive")
    return value


def period_ordinal(period: str) -> int:
    if not PERIOD_PATTERN.fullmatch(period):
        raise RevisedPanelError(f"invalid quarter: {period!r}")
    return 4 * int(period[:4]) + int(period[-1]) - 1


def period_from_ordinal(ordinal: int) -> str:
    year, offset = divmod(ordinal, 4)
    return f"{year:04d}Q{offset + 1}"


def previous_period(period: str) -> str:
    return period_from_ordinal(period_ordinal(period) - 1)


def period_from_month(month: str) -> str:
    if not MONTH_PATTERN.fullmatch(month):
        raise RevisedPanelError(f"invalid month: {month!r}")
    return f"{month[:4]}Q{((int(month[-2:]) - 1) // 3) + 1}"


def period_from_date(value: date) -> str:
    return f"{value.year:04d}Q{((value.month - 1) // 3) + 1}"


def require_contiguous(periods: Sequence[str], location: str) -> None:
    if not periods:
        raise RevisedPanelError(f"{location} is empty")
    ordinals = [period_ordinal(period) for period in periods]
    if len(set(periods)) != len(periods):
        raise RevisedPanelError(f"{location} contains duplicate quarters")
    if ordinals != sorted(ordinals):
        raise RevisedPanelError(f"{location} must be ascending")
    if any(right != left + 1 for left, right in zip(ordinals, ordinals[1:])):
        raise RevisedPanelError(f"{location} is not contiguous")


def read_csv_rows(path: Path, expected_columns: Sequence[str]) -> list[dict[str, str]]:
    raw = path.read_bytes()
    if not raw.endswith(b"\n"):
        raise RevisedPanelError(f"{path.name} must end with LF")
    if b"\r" in raw:
        raise RevisedPanelError(f"{path.name} must use LF line endings")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as error:
        raise RevisedPanelError(f"{path.name} must be UTF-8") from error
    reader = csv.DictReader(io.StringIO(text))
    if tuple(reader.fieldnames or ()) != tuple(expected_columns):
        raise RevisedPanelError(
            f"{path.name} columns changed: {reader.fieldnames!r}"
        )
    rows = [dict(row) for row in reader]
    if any(value is None or value == "" for row in rows for value in row.values()):
        raise RevisedPanelError(f"{path.name} contains a missing field")
    return rows


def csv_bytes(columns: Sequence[str], rows: Iterable[Mapping[str, object]]) -> bytes:
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(
        stream,
        fieldnames=list(columns),
        extrasaction="raise",
        lineterminator="\n",
    )
    writer.writeheader()
    for row in rows:
        writer.writerow(row)
    return stream.getvalue().encode("utf-8")


def load_bea_levels(
    path: Path = BEA_SOURCE_PATH,
) -> dict[str, dict[str, Decimal]]:
    rows = read_csv_rows(path, BEA_COLUMNS)
    levels = {target: {} for target in BEA_TARGETS}
    observed_keys: list[tuple[str, str]] = []
    for index, row in enumerate(rows, start=2):
        period = row["period"]
        period_ordinal(period)
        target = row["target_id"]
        if target not in levels:
            raise RevisedPanelError(f"{path.name}:{index} unexpected target {target}")
        value = decimal_value(
            row["published_value"],
            f"{path.name}:{index}.published_value",
            positive=True,
        )
        if period in levels[target]:
            raise RevisedPanelError(f"{path.name}:{index} duplicate {target}/{period}")
        levels[target][period] = value
        observed_keys.append((period, target))
    if observed_keys != sorted(observed_keys):
        raise RevisedPanelError(f"{path.name} rows must be sorted by period,target_id")
    expected_periods: list[str] | None = None
    for target in BEA_TARGETS:
        periods = list(levels[target])
        require_contiguous(periods, f"{path.name}.{target}")
        if expected_periods is None:
            expected_periods = periods
        elif periods != expected_periods:
            raise RevisedPanelError(f"{path.name} BEA target coverage differs")
    if not expected_periods or expected_periods[0] != "2000Q2":
        raise RevisedPanelError(f"{path.name} must begin at 2000Q2")
    if expected_periods[-1] != SOURCE_END_PERIOD:
        raise RevisedPanelError(
            f"{path.name} must end at {SOURCE_END_PERIOD}"
        )
    return levels


def load_bls_levels(
    path: Path = BLS_SOURCE_PATH,
) -> dict[str, dict[str, Decimal | None]]:
    rows = read_csv_rows(path, BLS_COLUMNS)
    levels = {series: {} for series in BLS_SERIES}
    observed_keys: list[tuple[str, str]] = []
    for index, row in enumerate(rows, start=2):
        month = row["month"]
        if not MONTH_PATTERN.fullmatch(month):
            raise RevisedPanelError(f"{path.name}:{index} invalid month")
        series = row["series_id"]
        if series not in levels:
            raise RevisedPanelError(f"{path.name}:{index} unexpected series {series}")
        if row["published_value"] == "-":
            if not (
                series == "LNS14000000"
                and month == "2025-10"
                and "9" in row["footnote_codes"].split("|")
            ):
                raise RevisedPanelError(
                    f"{path.name}:{index} unexpected unavailable observation"
                )
            value = None
        else:
            value = decimal_value(
                row["published_value"],
                f"{path.name}:{index}.published_value",
                positive=True,
            )
        if month in levels[series]:
            raise RevisedPanelError(f"{path.name}:{index} duplicate {series}/{month}")
        if row["latest"] not in {"false", "true"}:
            raise RevisedPanelError(f"{path.name}:{index}.latest is not boolean text")
        levels[series][month] = value
        observed_keys.append((month, series))
    if observed_keys != sorted(observed_keys):
        raise RevisedPanelError(f"{path.name} rows must be sorted by month,series_id")
    expected_months = [
        f"{year:04d}-{month:02d}"
        for year in range(2000, 2027)
        for month in range(1, 13)
        if (year, month) <= (2026, 6)
    ]
    for series in BLS_SERIES:
        if list(levels[series]) != expected_months:
            raise RevisedPanelError(f"{path.name}.{series} month coverage changed")
    return levels


def load_effr_rates(
    path: Path = EFFR_SOURCE_PATH,
) -> dict[date, Decimal]:
    rows = read_csv_rows(path, EFFR_COLUMNS)
    rates: dict[date, Decimal] = {}
    observed_dates: list[date] = []
    for index, row in enumerate(rows, start=2):
        try:
            effective_date = datetime.strptime(
                row["effective_date"], "%Y-%m-%d"
            ).date()
        except ValueError as error:
            raise RevisedPanelError(
                f"{path.name}:{index} invalid effective date"
            ) from error
        if effective_date.weekday() >= 5:
            raise RevisedPanelError(
                f"{path.name}:{index} contains a weekend EFFR observation"
            )
        if effective_date in rates:
            raise RevisedPanelError(
                f"{path.name}:{index} duplicate EFFR effective date"
            )
        rates[effective_date] = decimal_value(
            row["rate_percent"],
            f"{path.name}:{index}.rate_percent",
            positive=True,
        )
        if row["revision_indicator"] not in {"N", "Y"}:
            raise RevisedPanelError(
                f"{path.name}:{index} invalid revision indicator"
            )
        observed_dates.append(effective_date)
    if observed_dates != sorted(observed_dates):
        raise RevisedPanelError(f"{path.name} rows must be date ascending")
    if not observed_dates or observed_dates[0] != date(2000, 7, 3):
        raise RevisedPanelError(f"{path.name} first effective date changed")
    if observed_dates[-1] != date(2026, 6, 30):
        raise RevisedPanelError(f"{path.name} last effective date changed")
    return rates


def quarterly_mean(
    observations: Mapping[str, Decimal | None],
    location: str,
) -> dict[str, Decimal]:
    grouped: dict[str, list[Decimal]] = defaultdict(list)
    for month, value in observations.items():
        if value is not None:
            grouped[period_from_month(month)].append(value)
    result = {}
    for period, values in sorted(grouped.items()):
        official_shutdown_gap = (
            location == "LNS14000000" and period == "2025Q4" and len(values) == 2
        )
        if official_shutdown_gap:
            continue
        if len(values) != 3:
            raise RevisedPanelError(
                f"{location}.{period} must contain exactly three months"
            )
        result[period] = sum(values, Decimal(0)) / Decimal(3)
    return result


def effr_quarterly_mean(rates: Mapping[date, Decimal]) -> dict[str, Decimal]:
    grouped: dict[str, list[Decimal]] = defaultdict(list)
    for effective_date, rate in rates.items():
        grouped[period_from_date(effective_date)].append(rate)
    result = {}
    for period, values in sorted(grouped.items()):
        if not values:
            raise RevisedPanelError(f"EFFR.{period} is empty")
        result[period] = sum(values, Decimal(0)) / Decimal(len(values))
    return result


def log_change(scale: int, current: Decimal, previous: Decimal) -> Decimal:
    if current <= 0 or previous <= 0:
        raise RevisedPanelError("log-change inputs must be positive")
    with localcontext() as context:
        context.prec = 50
        return Decimal(scale) * (current / previous).ln()


def format_decimal(value: Decimal) -> str:
    if not value.is_finite():
        raise RevisedPanelError("panel contains a non-finite value")
    return format(value, ".12f")


def derive_panel_rows(
    bea_levels: Mapping[str, Mapping[str, Decimal]],
    bls_levels: Mapping[str, Mapping[str, Decimal]],
    effr_rates: Mapping[date, Decimal],
) -> list[dict[str, str]]:
    payroll = quarterly_mean(bls_levels["CES0000000001"], "CES0000000001")
    unemployment = quarterly_mean(bls_levels["LNS14000000"], "LNS14000000")
    effr = effr_quarterly_mean(effr_rates)

    candidates = sorted(
        set(effr)
        & set(unemployment)
        & set(payroll)
        & set(bea_levels["real_gdp"]),
        key=period_ordinal,
    )
    candidates = [
        period for period in candidates if period <= EXPECTED_END_PERIOD
    ]
    rows = []
    for period in candidates:
        previous = previous_period(period)
        if previous not in payroll:
            continue
        if any(
            period not in bea_levels[target]
            or previous not in bea_levels[target]
            for target in BEA_TARGETS
        ):
            continue
        row = {
            "period": period,
            "real_gdp": format_decimal(
                log_change(
                    400,
                    bea_levels["real_gdp"][period],
                    bea_levels["real_gdp"][previous],
                )
            ),
            "pce_price_index": format_decimal(
                log_change(
                    400,
                    bea_levels["pce_price_index"][period],
                    bea_levels["pce_price_index"][previous],
                )
            ),
            "core_pce_price_index": format_decimal(
                log_change(
                    400,
                    bea_levels["core_pce_price_index"][period],
                    bea_levels["core_pce_price_index"][previous],
                )
            ),
            "gdp_deflator": format_decimal(
                log_change(
                    400,
                    bea_levels["gdp_deflator"][period],
                    bea_levels["gdp_deflator"][previous],
                )
            ),
            "unemployment_rate": format_decimal(unemployment[period]),
            "payroll_employment": format_decimal(
                log_change(100, payroll[period], payroll[previous])
            ),
            "effective_federal_funds_rate": format_decimal(effr[period]),
            "nominal_gdp": format_decimal(
                log_change(
                    400,
                    bea_levels["nominal_gdp"][period],
                    bea_levels["nominal_gdp"][previous],
                )
            ),
        }
        rows.append(row)
    periods = [row["period"] for row in rows]
    require_contiguous(periods, "derived panel")
    if periods[0] != EXPECTED_START_PERIOD:
        raise RevisedPanelError(
            f"derived panel starts at {periods[0]}, not {EXPECTED_START_PERIOD}"
        )
    if periods[-1] != EXPECTED_END_PERIOD:
        raise RevisedPanelError(
            f"derived panel ends at {periods[-1]}, not {EXPECTED_END_PERIOD}"
        )
    if len(rows) != EXPECTED_ROW_COUNT:
        raise RevisedPanelError(
            f"derived panel has {len(rows)} rows, not {EXPECTED_ROW_COUNT}"
        )
    return rows


def derive_panel_bytes(
    bea_path: Path = BEA_SOURCE_PATH,
    bls_path: Path = BLS_SOURCE_PATH,
    effr_path: Path = EFFR_SOURCE_PATH,
) -> bytes:
    return csv_bytes(
        PANEL_COLUMNS,
        derive_panel_rows(
            load_bea_levels(bea_path),
            load_bls_levels(bls_path),
            load_effr_rates(effr_path),
        ),
    )


def required_false(mapping: Mapping[str, object], key: str, location: str) -> None:
    if mapping.get(key) is not False:
        raise RevisedPanelError(f"{location}.{key} must be false")


def required_true(mapping: Mapping[str, object], key: str, location: str) -> None:
    if mapping.get(key) is not True:
        raise RevisedPanelError(f"{location}.{key} must be true")


def verify_fixture(
    fixture_dir: Path = FIXTURE_DIR,
    *,
    enforce_manifest_pin: bool = True,
) -> FixtureVerification:
    manifest_path = fixture_dir / "manifest.toml"
    panel_path = fixture_dir / "quarterly_panel.csv"
    receipt_path = fixture_dir / "source_receipts.json"
    manifest_bytes = manifest_path.read_bytes()
    manifest_sha256 = sha256_bytes(manifest_bytes)
    if enforce_manifest_pin and manifest_sha256 != EXPECTED_MANIFEST_SHA256:
        raise RevisedPanelError("manifest SHA-256 is not the compiled fixture pin")
    manifest = tomllib.loads(manifest_bytes.decode("utf-8"))
    if manifest.get("schema_version") != SCHEMA_VERSION:
        raise RevisedPanelError("manifest schema version changed")
    if manifest.get("information_track") != INFORMATION_TRACK:
        raise RevisedPanelError("manifest information track changed")
    for key in (
        "forecast_origin_admissible",
        "promotion_eligible",
        "abm_accuracy_claimed",
        "bitemporal",
        "real_time",
    ):
        required_false(manifest, key, "manifest")
    required_true(manifest, "revised_current_release_snapshot", "manifest")
    if tuple(manifest.get("target_order", ())) != TARGET_COLUMNS:
        raise RevisedPanelError("manifest target order changed")
    if manifest.get("row_count") != EXPECTED_ROW_COUNT:
        raise RevisedPanelError("manifest row count changed")
    if manifest.get("start_period") != EXPECTED_START_PERIOD:
        raise RevisedPanelError("manifest start period changed")
    if manifest.get("end_period") != EXPECTED_END_PERIOD:
        raise RevisedPanelError("manifest end period changed")

    source_paths = {
        "bea_quarterly_levels": fixture_dir / "bea_quarterly_levels.csv",
        "bls_monthly_levels": fixture_dir / "bls_monthly_levels.csv",
        "effr_daily_rates": fixture_dir / "effr_daily_rates.csv",
    }
    source_manifest = manifest.get("sources")
    if not isinstance(source_manifest, dict):
        raise RevisedPanelError("manifest.sources must be a table")
    for source_id, path in source_paths.items():
        source = source_manifest.get(source_id)
        if not isinstance(source, dict):
            raise RevisedPanelError(f"manifest.sources.{source_id} is missing")
        if source.get("file") != path.name:
            raise RevisedPanelError(f"manifest.sources.{source_id}.file changed")
        if source.get("sha256") != sha256_file(path):
            raise RevisedPanelError(f"{path.name} SHA-256 mismatch")

    receipt_bytes = receipt_path.read_bytes()
    receipt_sha256 = sha256_bytes(receipt_bytes)
    if manifest.get("source_receipts_sha256") != receipt_sha256:
        raise RevisedPanelError("source-receipt SHA-256 mismatch")
    receipt = json.loads(receipt_bytes)
    if receipt.get("schema_version") != RECEIPT_SCHEMA_VERSION:
        raise RevisedPanelError("source-receipt schema version changed")
    if canonical_json_bytes(receipt) != receipt_bytes:
        raise RevisedPanelError("source receipt is not canonical JSON")
    if receipt.get("information_track") != INFORMATION_TRACK:
        raise RevisedPanelError("source-receipt information track changed")
    for key in (
        "forecast_origin_admissible",
        "promotion_eligible",
        "abm_accuracy_claimed",
        "bitemporal",
        "real_time",
    ):
        required_false(receipt, key, "source_receipt")
    if receipt.get("bea_content_fingerprint_sha256") != (
        EXPECTED_BEA_FINGERPRINT_SHA256
    ):
        raise RevisedPanelError("BEA content-fingerprint lineage changed")

    panel_bytes = panel_path.read_bytes()
    panel_sha256 = sha256_bytes(panel_bytes)
    if manifest.get("panel_sha256") != panel_sha256:
        raise RevisedPanelError("panel SHA-256 mismatch")
    derived = derive_panel_bytes(*source_paths.values())
    if derived != panel_bytes:
        raise RevisedPanelError("panel bytes do not match source transformations")
    panel_rows = read_csv_rows(panel_path, PANEL_COLUMNS)
    periods = [row["period"] for row in panel_rows]
    require_contiguous(periods, "panel")
    if len(panel_rows) != EXPECTED_ROW_COUNT:
        raise RevisedPanelError("panel row count changed")
    if periods[0] != EXPECTED_START_PERIOD or periods[-1] != EXPECTED_END_PERIOD:
        raise RevisedPanelError("panel boundary changed")
    for row_index, row in enumerate(panel_rows, start=2):
        for target in TARGET_COLUMNS:
            value = float(row[target])
            if not math.isfinite(value):
                raise RevisedPanelError(
                    f"{panel_path.name}:{row_index}.{target} is not finite"
                )

    effr_count = len(load_effr_rates(source_paths["effr_daily_rates"]))
    return FixtureVerification(
        manifest_sha256=manifest_sha256,
        panel_sha256=panel_sha256,
        receipt_sha256=receipt_sha256,
        row_count=len(panel_rows),
        start_period=periods[0],
        end_period=periods[-1],
        effr_observation_count=effr_count,
    )
