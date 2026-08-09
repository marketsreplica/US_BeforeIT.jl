#!/usr/bin/env python3
"""Build a sealed, non-admitting BEA cross-archive revision diagnostic.

The only accepted inputs are the two exact checked-in historical semantic
fingerprints pinned below.  The later source is a 2021 annual-update release,
so the result is revision-sensitivity evidence only: it is not a standard
within-definition revision comparison, truth, a forecast origin, a score, or
accuracy evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import sys
import tempfile
from dataclasses import dataclass
from decimal import (
    Context,
    Decimal,
    DivisionByZero,
    InvalidOperation,
    Overflow,
    ROUND_HALF_EVEN,
    localcontext,
)
from pathlib import Path
from typing import Any, Iterable, Mapping

SCHEMA_VERSION = "beforeit-us-bea-hmi7-revision-diagnostic.v1"
GENERATOR_VERSION = "beforeit-us-bea-hmi7-revision-diagnostic-generator.v1"
STATUS = "PRESENT_DAY_CROSS_ARCHIVE_REVISION_DIAGNOSTIC_NONADMITTING"
JSON_CANONICALIZATION = "utf8_sorted_keys_compact_json_lf"
COMPARISON_START = "1997Q1"
COMPARISON_END = "2019Q4"
LAG_SUPPORT_PERIOD = "1996Q4"
DECIMAL_PRECISION = 80
DECIMAL_ROUNDING = ROUND_HALF_EVEN
EXPECTED_SOURCE_SCHEMA = (
    "beforeit-us-bea-hmi7-historical-content-fingerprint.v1"
)
EXPECTED_SOURCE_STATUS = "PRESENT_DAY_ARCHIVE_BYTES_PARSED_NONADMITTING"
EXPECTED_MAPPING_PROFILE_ID = "bea_hmi7_nipa_2012_base_dual_release.v1"
EXPECTED_MAPPING_PROFILE_SHA256 = (
    "8ed3038e7ea80c7207d57cabad6f2b8a50ea5bbe2e04587b63c7b5d242230171"
)
EXPECTED_PARSER_VERSION = "beforeit-us-bea-hmi7-historical-ooxml-parser.v1"
EXPECTED_PARSER_SHA256 = (
    "d0a261248d5448a82f9e1b729c1cb65ca6e2ae64ff4095405d3dc5fcb7dc351e"
)
EXPECTED_LATER_CAVEAT = (
    "THIS_RELEASE_INCLUDES_THE_2021_ANNUAL_UPDATE_AND_REVISED_HISTORY_"
    "MUST_NOT_BE_TREATED_AS_A_STANDARD_WITHIN_DEFINITION_VINTAGE"
)
EXPECTED_EARLIER_CAVEAT = "NOT_AN_ANNUAL_UPDATE_RELEASE"
HASH_PATTERN = re.compile(r"[0-9a-f]{64}\Z")
DECIMAL_PATTERN = re.compile(r"(?:0|[1-9][0-9]*)(?:\.[0-9]+)?\Z")
PERIOD_PATTERN = re.compile(r"([0-9]{4})Q([1-4])\Z")


class DiagnosticError(RuntimeError):
    """Raised when an input, semantic binding, or output fails closed."""


@dataclass(frozen=True)
class SourceSpec:
    role: str
    filename: str
    sha256: str
    release_id: str
    release_profile_sha256: str
    raw_pair_sha256: str
    reference_end: str
    annual_update_caveat: str
    history_class: str


@dataclass(frozen=True)
class TargetSpec:
    target_id: str
    section_id: str
    sheet_name: str
    published_line_number: int
    physical_row_number: int
    series_code: str
    unit: str
    base_year: str
    primary_transformation: str


SOURCES = (
    SourceSpec(
        role="earlier_archive_observation",
        filename=(
            "bea-hmi7-r2019q4_advance_hmi7_monthly_snapshot-"
            "content-fingerprint-sha256-"
            "f6c60ba8eccda00b197dc6d915abc77575bd073ef1e4f6bf598d4ade9ea2e2a4"
            ".json"
        ),
        sha256=(
            "f6c60ba8eccda00b197dc6d915abc77575bd073ef1e4f6bf598d4ade9ea2e2a4"
        ),
        release_id="r2019q4_advance_hmi7_monthly_snapshot",
        release_profile_sha256=(
            "c4481a6df9174b756be0257331bd6010cb1e53f698161cd85088f33bf85bf23c"
        ),
        raw_pair_sha256=(
            "6752afcae4b6882f2c723f8e8ef6e87e93d1102e3beac79b657f159b0056f4ef"
        ),
        reference_end="2019Q4",
        annual_update_caveat=EXPECTED_EARLIER_CAVEAT,
        history_class="ADVANCE_RELEASE_ASSOCIATED_MONTHLY_TABLE_HISTORY",
    ),
    SourceSpec(
        role="later_archive_observation",
        filename=(
            "bea-hmi7-r2021q2_advance_annual_update_hmi7_monthly_snapshot-"
            "content-fingerprint-sha256-"
            "889d080250ffe5d9e3ff4e8bea35195b7ba521f4a48f79a7609ab1facde57711"
            ".json"
        ),
        sha256=(
            "889d080250ffe5d9e3ff4e8bea35195b7ba521f4a48f79a7609ab1facde57711"
        ),
        release_id="r2021q2_advance_annual_update_hmi7_monthly_snapshot",
        release_profile_sha256=(
            "6788c9f35f35f53c3e089085367e8205e06ad48ddebb6d09a601273ef70852e8"
        ),
        raw_pair_sha256=(
            "79b8ce7f2f096bcd0177350381e0bef81bc8b77b0df374c411c7d07b582e5b50"
        ),
        reference_end="2021Q2",
        annual_update_caveat=EXPECTED_LATER_CAVEAT,
        history_class="ANNUAL_UPDATE_REVISED_HISTORY",
    ),
)

TARGETS = (
    TargetSpec(
        "nominal_gdp",
        "1",
        "T10105-Q",
        1,
        9,
        "A191RC",
        "millions_of_dollars",
        "not_applicable",
        "annualized_qoq_log_growth",
    ),
    TargetSpec(
        "real_gdp",
        "1",
        "T10106-Q",
        1,
        9,
        "A191RX",
        "millions_of_chained_2012_dollars",
        "2012",
        "annualized_qoq_log_growth",
    ),
    TargetSpec(
        "gdp_deflator",
        "1",
        "T10109-Q",
        1,
        9,
        "A191RD",
        "index",
        "2012",
        "annualized_qoq_log_inflation",
    ),
    TargetSpec(
        "pce_price_index",
        "2",
        "T20304-Q",
        1,
        9,
        "DPCERG",
        "index",
        "2012",
        "annualized_qoq_log_inflation",
    ),
    TargetSpec(
        "core_pce_price_index",
        "2",
        "T20304-Q",
        25,
        34,
        "DPCCRG",
        "index",
        "2012",
        "annualized_qoq_log_inflation",
    ),
)


def false_gates() -> dict[str, bool]:
    return {
        "historical_first_state_verified": False,
        "historical_availability_verified": False,
        "origin_admissible": False,
        "empirical_execution_allowed": False,
        "inventory_mutation_authorized": False,
        "production_authorized": False,
        "ready": False,
    }


def canonical_json_bytes(value: Any) -> bytes:
    return (
        json.dumps(
            value,
            ensure_ascii=False,
            allow_nan=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        + "\n"
    ).encode("utf-8")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DiagnosticError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def parse_canonical_json(data: bytes, location: str) -> dict[str, Any]:
    try:
        text = data.decode("utf-8")
        value = json.loads(text, object_pairs_hook=_reject_duplicate_keys)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise DiagnosticError(f"{location} is not valid UTF-8 JSON") from error
    if not isinstance(value, dict):
        raise DiagnosticError(f"{location} must contain a JSON object")
    if canonical_json_bytes(value) != data:
        raise DiagnosticError(f"{location} is not canonical JSON")
    return value


def quarter_sequence(start: str, end: str) -> list[str]:
    start_match = PERIOD_PATTERN.fullmatch(start)
    end_match = PERIOD_PATTERN.fullmatch(end)
    if start_match is None or end_match is None:
        raise DiagnosticError("quarter boundary is malformed")
    start_index = int(start_match[1]) * 4 + int(start_match[2]) - 1
    end_index = int(end_match[1]) * 4 + int(end_match[2]) - 1
    if end_index < start_index:
        raise DiagnosticError("quarter boundary is reversed")
    return [
        f"{index // 4}Q{index % 4 + 1}"
        for index in range(start_index, end_index + 1)
    ]


def _require_dict(value: Any, location: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise DiagnosticError(f"{location} must be an object")
    return value


def _require_list(value: Any, location: str) -> list[Any]:
    if not isinstance(value, list):
        raise DiagnosticError(f"{location} must be an array")
    return value


def _expect_equal(actual: Any, expected: Any, location: str) -> None:
    if actual != expected or type(actual) is not type(expected):
        raise DiagnosticError(f"{location} drifted")


def _validate_gate_record(value: Any, location: str) -> None:
    gates = _require_dict(value, location)
    if gates != false_gates():
        raise DiagnosticError(f"{location} must contain exactly the hard-false gates")
    if any(type(item) is not bool or item for item in gates.values()):
        raise DiagnosticError(f"{location} contains a non-false Boolean")


def _target_records(document: Mapping[str, Any]) -> dict[str, dict[str, Any]]:
    records = _require_list(document.get("targets"), "targets")
    result: dict[str, dict[str, Any]] = {}
    for index, value in enumerate(records):
        record = _require_dict(value, f"targets[{index}]")
        target_id = record.get("target_id")
        if not isinstance(target_id, str) or target_id in result:
            raise DiagnosticError("target identity is absent or duplicated")
        result[target_id] = record
    expected = {target.target_id for target in TARGETS}
    if set(result) != expected or len(records) != len(TARGETS):
        raise DiagnosticError(
            "source target coverage is not exactly the five pinned targets"
        )
    return result


def _observation_values(
    target: Mapping[str, Any],
    location: str,
) -> dict[str, str]:
    observations = _require_list(target.get("observations"), f"{location}.observations")
    result: dict[str, str] = {}
    previous_index: int | None = None
    for index, value in enumerate(observations):
        record = _require_dict(value, f"{location}.observations[{index}]")
        if set(record) != {"period", "published_value_text", "raw_value_text"}:
            raise DiagnosticError(f"{location}.observations[{index}] keys drifted")
        period = record["period"]
        match = PERIOD_PATTERN.fullmatch(period) if isinstance(period, str) else None
        if match is None:
            raise DiagnosticError(
                f"{location}.observations[{index}].period is malformed"
            )
        period_index = int(match[1]) * 4 + int(match[2]) - 1
        if previous_index is not None and period_index != previous_index + 1:
            raise DiagnosticError(f"{location}.observations period axis drifted")
        previous_index = period_index
        if period in result:
            raise DiagnosticError(f"{location}.observations period is duplicated")
        published = record["published_value_text"]
        if not isinstance(published, str):
            raise DiagnosticError(f"{location}.{period} published value is not text")
        result[period] = published
    return result


def _positive_decimal(value: str, location: str) -> Decimal:
    if DECIMAL_PATTERN.fullmatch(value) is None:
        raise DiagnosticError(f"{location} is not a canonical nonnegative decimal")
    try:
        result = Decimal(value)
    except InvalidOperation as error:
        raise DiagnosticError(f"{location} is not a decimal") from error
    if not result.is_finite() or result <= 0:
        raise DiagnosticError(f"{location} must be finite and strictly positive")
    return result


def validate_source_document(document: Mapping[str, Any], spec: SourceSpec) -> None:
    if set(document) != {"artifact", "release", "targets", "workbooks"}:
        raise DiagnosticError(f"{spec.role} top-level structure drifted")
    artifact = _require_dict(document["artifact"], f"{spec.role}.artifact")
    release = _require_dict(document["release"], f"{spec.role}.release")
    workbooks = _require_list(document["workbooks"], f"{spec.role}.workbooks")
    targets = _target_records(document)

    expected_artifact = {
        "schema_version": EXPECTED_SOURCE_SCHEMA,
        "status": EXPECTED_SOURCE_STATUS,
        "canonicalization": JSON_CANONICALIZATION,
        "mapping_profile_id": EXPECTED_MAPPING_PROFILE_ID,
        "mapping_profile_sha256": EXPECTED_MAPPING_PROFILE_SHA256,
        "parser_version": EXPECTED_PARSER_VERSION,
        "parser_sha256": EXPECTED_PARSER_SHA256,
    }
    for key, expected in expected_artifact.items():
        _expect_equal(artifact.get(key), expected, f"{spec.role}.artifact.{key}")
    for key in (
        "historical_availability_evidence_included",
        "historical_first_state_evidence_included",
        "release_event_evidence_included",
        "execution_environment_included",
        "repository_state_included",
        "local_raw_paths_included",
    ):
        _expect_equal(artifact.get(key), False, f"{spec.role}.artifact.{key}")
    _validate_gate_record(artifact.get("gates"), f"{spec.role}.artifact.gates")

    expected_release = {
        "release_id": spec.release_id,
        "release_profile_sha256": spec.release_profile_sha256,
        "raw_pair_sha256": spec.raw_pair_sha256,
        "reference_period_end": spec.reference_end,
        "annual_update_caveat": spec.annual_update_caveat,
        "status": EXPECTED_SOURCE_STATUS,
        "release_event_is_workbook_snapshot": False,
        "workbook_snapshot_boundary": (
            "HMI7_NEXT_DAY_MONTHLY_TABLE_SNAPSHOT_NOT_EXACT_RELEASE_TIME_CAPTURE"
        ),
    }
    for key, expected in expected_release.items():
        _expect_equal(release.get(key), expected, f"{spec.role}.release.{key}")
    _validate_gate_record(release.get("gates"), f"{spec.role}.release.gates")

    if len(workbooks) != 2:
        raise DiagnosticError(f"{spec.role} must bind exactly two workbooks")
    section_ids: set[str] = set()
    for index, value in enumerate(workbooks):
        workbook = _require_dict(value, f"{spec.role}.workbooks[{index}]")
        section_id = workbook.get("section_id")
        if section_id not in {"1", "2"} or section_id in section_ids:
            raise DiagnosticError(f"{spec.role} workbook sections drifted")
        section_ids.add(section_id)
        _expect_equal(
            workbook.get("status"),
            EXPECTED_SOURCE_STATUS,
            f"{spec.role}.workbooks[{index}].status",
        )
        _expect_equal(
            workbook.get("mapping_profile_id"),
            EXPECTED_MAPPING_PROFILE_ID,
            f"{spec.role}.workbooks[{index}].mapping_profile_id",
        )
        _expect_equal(
            workbook.get("mapping_profile_sha256"),
            EXPECTED_MAPPING_PROFILE_SHA256,
            f"{spec.role}.workbooks[{index}].mapping_profile_sha256",
        )
        raw_sha256 = workbook.get("raw_sha256")
        if (
            not isinstance(raw_sha256, str)
            or HASH_PATTERN.fullmatch(raw_sha256) is None
        ):
            raise DiagnosticError(f"{spec.role} workbook SHA-256 is malformed")
        _validate_gate_record(
            workbook.get("gates"),
            f"{spec.role}.workbooks[{index}].gates",
        )

    required_periods = [LAG_SUPPORT_PERIOD] + quarter_sequence(
        COMPARISON_START,
        COMPARISON_END,
    )
    for target_spec in TARGETS:
        location = f"{spec.role}.targets.{target_spec.target_id}"
        target = targets[target_spec.target_id]
        expected_target = {
            "target_id": target_spec.target_id,
            "section_id": target_spec.section_id,
            "sheet_name": target_spec.sheet_name,
            "published_line_number": target_spec.published_line_number,
            "physical_row_number": target_spec.physical_row_number,
            "series_code": target_spec.series_code,
            "unit": target_spec.unit,
            "base_year": target_spec.base_year,
            "mapping_profile_id": EXPECTED_MAPPING_PROFILE_ID,
            "mapping_profile_sha256": EXPECTED_MAPPING_PROFILE_SHA256,
            "status": EXPECTED_SOURCE_STATUS,
        }
        for key, expected in expected_target.items():
            _expect_equal(target.get(key), expected, f"{location}.{key}")
        _validate_gate_record(target.get("gates"), f"{location}.gates")
        values = _observation_values(target, location)
        if any(period not in values for period in required_periods):
            raise DiagnosticError(
                f"{location} does not cover the fixed comparison window"
            )
        for period in required_periods:
            _positive_decimal(values[period], f"{location}.{period}")


def _safe_source_directory(path: Path) -> Path:
    if not path.is_absolute():
        raise DiagnosticError("source directory must be absolute")
    if path.is_symlink():
        raise DiagnosticError("source directory is unsafe")
    try:
        resolved = path.resolve(strict=True)
    except OSError as error:
        raise DiagnosticError("source directory is absent") from error
    if not resolved.is_dir():
        raise DiagnosticError("source directory is unsafe")
    path = resolved
    discovered = {item.name for item in path.iterdir() if item.suffix == ".json"}
    expected = {spec.filename for spec in SOURCES}
    if discovered != expected:
        raise DiagnosticError("source JSON filenames are not exactly the pinned pair")
    return path


def load_pinned_sources(source_dir: Path) -> dict[str, dict[str, Any]]:
    directory = _safe_source_directory(source_dir)
    result: dict[str, dict[str, Any]] = {}
    for spec in SOURCES:
        path = directory / spec.filename
        if path.is_symlink() or not path.is_file() or path.resolve() != path:
            raise DiagnosticError(f"{spec.role} source path is unsafe")
        data = path.read_bytes()
        if sha256_bytes(data) != spec.sha256:
            raise DiagnosticError(f"{spec.role} source SHA-256 drifted")
        document = parse_canonical_json(data, spec.role)
        validate_source_document(document, spec)
        result[spec.role] = document
    return result


def _decimal_context() -> Context:
    context = Context(
        prec=DECIMAL_PRECISION,
        rounding=DECIMAL_ROUNDING,
        Emin=-999999,
        Emax=999999,
        capitals=1,
        clamp=0,
    )
    context.traps[InvalidOperation] = True
    context.traps[DivisionByZero] = True
    context.traps[Overflow] = True
    return context


def decimal_text(value: Decimal) -> str:
    if not value.is_finite():
        raise DiagnosticError("derived decimal is non-finite")
    if value.is_zero():
        return "0"
    result = format(value, "f")
    if "." in result:
        result = result.rstrip("0").rstrip(".")
    return result


def _summary(periods: list[str], revisions: list[Decimal]) -> dict[str, Any]:
    if not revisions or len(periods) != len(revisions):
        raise DiagnosticError("revision summary input is empty or misaligned")
    with localcontext(_decimal_context()):
        count = Decimal(len(revisions))
        mean = sum(revisions, Decimal(0)) / count
        rmse = (
            sum((revision * revision for revision in revisions), Decimal(0))
            / count
        ).sqrt()
        max_index = max(
            range(len(revisions)),
            key=lambda index: (abs(revisions[index]), -index),
        )
        return {
            "observation_count": len(revisions),
            "mean_revision": decimal_text(+mean),
            "rmse_revision": decimal_text(+rmse),
            "max_absolute_revision": {
                "period": periods[max_index],
                "revision": decimal_text(+revisions[max_index]),
                "absolute_revision": decimal_text(+abs(revisions[max_index])),
            },
            "endpoint_revision": {
                "period": periods[-1],
                "revision": decimal_text(+revisions[-1]),
            },
        }


def _row_sha256(rows: Iterable[Mapping[str, Any]]) -> str:
    return sha256_bytes(canonical_json_bytes(list(rows)))


def _source_target_values(
    document: Mapping[str, Any],
    target_id: str,
) -> tuple[dict[str, str], Mapping[str, Any]]:
    target = _target_records(document)[target_id]
    return _observation_values(target, f"targets.{target_id}"), target


def _target_diagnostic(
    target_spec: TargetSpec,
    earlier_document: Mapping[str, Any],
    later_document: Mapping[str, Any],
) -> dict[str, Any]:
    earlier_text, earlier_target = _source_target_values(
        earlier_document,
        target_spec.target_id,
    )
    later_text, later_target = _source_target_values(
        later_document,
        target_spec.target_id,
    )
    periods = quarter_sequence(COMPARISON_START, COMPARISON_END)
    level_rows: list[dict[str, str]] = []
    level_revisions: list[Decimal] = []
    relative_revisions: list[Decimal] = []
    transform_rows: list[dict[str, str]] = []
    transform_revisions: list[Decimal] = []

    with localcontext(_decimal_context()):
        for period in periods:
            earlier = _positive_decimal(
                earlier_text[period],
                f"earlier.{target_spec.target_id}.{period}",
            )
            later = _positive_decimal(
                later_text[period],
                f"later.{target_spec.target_id}.{period}",
            )
            revision = +(later - earlier)
            relative_revision = +(Decimal(100) * revision / earlier)
            level_revisions.append(revision)
            relative_revisions.append(relative_revision)
            level_rows.append(
                {
                    "period": period,
                    "earlier_level": earlier_text[period],
                    "later_level": later_text[period],
                    "revision_later_minus_earlier": decimal_text(revision),
                    "relative_revision_percent": decimal_text(relative_revision),
                }
            )

        transform_input_periods = [LAG_SUPPORT_PERIOD] + periods
        earlier_levels = [
            _positive_decimal(
                earlier_text[period],
                f"earlier.{target_spec.target_id}.{period}",
            )
            for period in transform_input_periods
        ]
        later_levels = [
            _positive_decimal(
                later_text[period],
                f"later.{target_spec.target_id}.{period}",
            )
            for period in transform_input_periods
        ]
        for index, period in enumerate(periods, start=1):
            earlier_transform = +(
                Decimal(400)
                * (earlier_levels[index] / earlier_levels[index - 1]).ln()
            )
            later_transform = +(
                Decimal(400)
                * (later_levels[index] / later_levels[index - 1]).ln()
            )
            revision = +(later_transform - earlier_transform)
            transform_revisions.append(revision)
            transform_rows.append(
                {
                    "period": period,
                    "earlier_transform": decimal_text(earlier_transform),
                    "later_transform": decimal_text(later_transform),
                    "revision_later_minus_earlier": decimal_text(revision),
                }
            )

    level_summary = _summary(periods, level_revisions)
    relative_summary = _summary(periods, relative_revisions)
    transform_summary = _summary(periods, transform_revisions)
    return {
        "target_id": target_spec.target_id,
        "mapping_binding": {
            "section_id": target_spec.section_id,
            "sheet_name": target_spec.sheet_name,
            "published_line_number": target_spec.published_line_number,
            "physical_row_number": target_spec.physical_row_number,
            "series_code": target_spec.series_code,
            "unit": target_spec.unit,
            "base_year": target_spec.base_year,
            "mapping_profile_id": EXPECTED_MAPPING_PROFILE_ID,
            "mapping_profile_sha256": EXPECTED_MAPPING_PROFILE_SHA256,
        },
        "source_vector_bindings": {
            SOURCES[0].role: earlier_target["published_values_sha256"],
            SOURCES[1].role: later_target["published_values_sha256"],
        },
        "level_revision": {
            "definition": "later_archive_level_minus_earlier_archive_level",
            "unit": target_spec.unit,
            "rows": level_rows,
            "rows_sha256": _row_sha256(level_rows),
            "summary": level_summary,
            "relative_percent_summary": relative_summary,
        },
        "primary_transform_revision": {
            "transformation": target_spec.primary_transformation,
            "formula": "400*ln(level_t/level_t_minus_1)",
            "unit": "percentage_points_annual_rate",
            "lag_support_period": LAG_SUPPORT_PERIOD,
            "rows": transform_rows,
            "rows_sha256": _row_sha256(transform_rows),
            "summary": transform_summary,
        },
        "gates": false_gates(),
    }


def _comparison_profile() -> dict[str, Any]:
    return {
        "comparison_start": COMPARISON_START,
        "comparison_end": COMPARISON_END,
        "comparison_period_count": len(
            quarter_sequence(COMPARISON_START, COMPARISON_END)
        ),
        "lag_support_period": LAG_SUPPORT_PERIOD,
        "decimal_precision": DECIMAL_PRECISION,
        "decimal_rounding": str(DECIMAL_ROUNDING),
        "revision_sign": "later_archive_observation_minus_earlier_archive_observation",
        "primary_transform_formula": "400*ln(level_t/level_t_minus_1)",
        "target_order": [target.target_id for target in TARGETS],
        "target_transformations": {
            target.target_id: target.primary_transformation for target in TARGETS
        },
    }


def _source_binding(spec: SourceSpec, document: Mapping[str, Any]) -> dict[str, Any]:
    release = _require_dict(document["release"], f"{spec.role}.release")
    workbooks = _require_list(document["workbooks"], f"{spec.role}.workbooks")
    artifact = _require_dict(document["artifact"], f"{spec.role}.artifact")
    return {
        "role": spec.role,
        "filename": spec.filename,
        "file_sha256": spec.sha256,
        "release_id": spec.release_id,
        "release_profile_sha256": spec.release_profile_sha256,
        "raw_pair_sha256": spec.raw_pair_sha256,
        "release_event_timestamp_utc": release["release_event_timestamp_utc"],
        "workbook_snapshot_boundary": release["workbook_snapshot_boundary"],
        "history_class": spec.history_class,
        "annual_update_caveat": spec.annual_update_caveat,
        "mapping_profile_id": artifact["mapping_profile_id"],
        "mapping_profile_sha256": artifact["mapping_profile_sha256"],
        "parser_version": artifact["parser_version"],
        "parser_sha256": artifact["parser_sha256"],
        "raw_workbook_sha256s": {
            workbook["section_id"]: workbook["raw_sha256"]
            for workbook in workbooks
        },
        "gates": false_gates(),
    }


def build_diagnostic(
    source_dir: Path,
    *,
    generator_path: Path | None = None,
) -> dict[str, Any]:
    documents = load_pinned_sources(source_dir)
    generator = (
        Path(__file__).resolve(strict=True)
        if generator_path is None
        else generator_path.resolve(strict=True)
    )
    profile = _comparison_profile()
    source_bindings = [
        _source_binding(spec, documents[spec.role]) for spec in SOURCES
    ]
    return {
        "artifact": {
            "schema_version": SCHEMA_VERSION,
            "generator_version": GENERATOR_VERSION,
            "generator_sha256": sha256_file(generator),
            "canonicalization": JSON_CANONICALIZATION,
            "status": STATUS,
            "evidence_class": (
                "present_day_cross_archive_revision_sensitivity_diagnostic"
            ),
            "persistence_scope": (
                "CONTENT_ADDRESSED_DIAGNOSTIC_SOURCE_FINGERPRINTS_CHECKED_IN_"
                "RAW_WORKBOOKS_EXTERNAL_TO_GIT"
            ),
            "source_agency": "U.S. Bureau of Economic Analysis",
            "source_attribution": "Source: U.S. Bureau of Economic Analysis",
            "comparison_profile_sha256": sha256_bytes(
                canonical_json_bytes(profile)
            ),
            "gates": false_gates(),
        },
        "classification": {
            "later_history_class": "ANNUAL_UPDATE_REVISED_HISTORY",
            "present_day_diagnostic": True,
            "standard_within_definition_revision": False,
            "truth_artifact": False,
            "forecast_origin": False,
            "score_artifact": False,
            "accuracy_evidence": False,
            "historical_first_state_evidence": False,
            "historical_availability_evidence": False,
            "inventory_mutation": False,
            "production_use": False,
        },
        "comparison_profile": profile,
        "source_bindings": source_bindings,
        "targets": [
            _target_diagnostic(
                target,
                documents[SOURCES[0].role],
                documents[SOURCES[1].role],
            )
            for target in TARGETS
        ],
    }


def _safe_output_directory(path: Path) -> Path:
    if not path.is_absolute():
        raise DiagnosticError("output directory must be absolute")
    if path.exists():
        if path.is_symlink() or not path.is_dir() or path.resolve() != path:
            raise DiagnosticError("output directory is unsafe")
        return path
    parent = path.parent.resolve(strict=True)
    if parent.is_symlink() or not parent.is_dir():
        raise DiagnosticError("output parent is unsafe")
    path.mkdir(mode=0o755)
    return path.resolve(strict=True)


def _existing_content_address_matches(path: Path, data: bytes) -> bool:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0)
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(path, flags)
    except FileNotFoundError:
        return False
    except OSError as error:
        raise DiagnosticError("existing diagnostic artifact is unsafe") from error
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
            raise DiagnosticError("existing diagnostic artifact is unsafe")
        chunks: list[bytes] = []
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        try:
            path_metadata = os.stat(path, follow_symlinks=False)
        except FileNotFoundError as error:
            raise DiagnosticError(
                "existing diagnostic artifact changed during validation"
            ) from error
        if (
            not stat.S_ISREG(path_metadata.st_mode)
            or path_metadata.st_nlink != 1
            or (path_metadata.st_dev, path_metadata.st_ino)
            != (metadata.st_dev, metadata.st_ino)
        ):
            raise DiagnosticError(
                "existing diagnostic artifact changed during validation"
            )
        if b"".join(chunks) != data:
            raise DiagnosticError("hash-addressed diagnostic content differs")
        return True
    finally:
        os.close(descriptor)


def write_content_addressed(output_dir: Path, data: bytes) -> Path:
    output = _safe_output_directory(output_dir)
    digest = sha256_bytes(data)
    destination = output / (
        f"bea-hmi7-cross-archive-revision-diagnostic-sha256-{digest}.json"
    )
    if _existing_content_address_matches(destination, data):
        return destination
    descriptor, temporary_name = tempfile.mkstemp(
        dir=output,
        prefix=".revision-diagnostic-",
    )
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        remaining = memoryview(data)
        while remaining:
            written = os.write(descriptor, remaining)
            if written <= 0:
                raise DiagnosticError("temporary diagnostic write made no progress")
            remaining = remaining[written:]
        os.fsync(descriptor)
        temporary_metadata = os.fstat(descriptor)
        path_metadata = os.stat(temporary, follow_symlinks=False)
        if (
            not stat.S_ISREG(temporary_metadata.st_mode)
            or temporary_metadata.st_nlink != 1
            or (path_metadata.st_dev, path_metadata.st_ino)
            != (temporary_metadata.st_dev, temporary_metadata.st_ino)
        ):
            raise DiagnosticError("temporary diagnostic artifact is unsafe")
        try:
            os.link(temporary, destination, follow_symlinks=False)
        except FileExistsError:
            if not _existing_content_address_matches(destination, data):
                raise DiagnosticError(
                    "exclusive diagnostic publication lost an empty-target race"
                )
            return destination
        except OSError as error:
            raise DiagnosticError(
                "exclusive diagnostic publication failed"
            ) from error
        linked_metadata = os.stat(destination, follow_symlinks=False)
        pinned_metadata = os.fstat(descriptor)
        if (
            not stat.S_ISREG(linked_metadata.st_mode)
            or (linked_metadata.st_dev, linked_metadata.st_ino)
            != (pinned_metadata.st_dev, pinned_metadata.st_ino)
            or pinned_metadata.st_nlink != 2
        ):
            raise DiagnosticError(
                "temporary diagnostic source changed during publication"
            )
        os.lseek(descriptor, 0, os.SEEK_SET)
        published_chunks: list[bytes] = []
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            published_chunks.append(chunk)
        if b"".join(published_chunks) != data:
            raise DiagnosticError(
                "temporary diagnostic bytes changed during publication"
            )
        os.fchmod(descriptor, 0o644)
        os.fsync(descriptor)
    finally:
        try:
            pinned_metadata = os.fstat(descriptor)
            current_metadata = os.stat(temporary, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            if (
                current_metadata.st_dev,
                current_metadata.st_ino,
            ) == (
                pinned_metadata.st_dev,
                pinned_metadata.st_ino,
            ):
                temporary.unlink()
        os.close(descriptor)
    if not _existing_content_address_matches(destination, data):
        raise DiagnosticError("published diagnostic artifact is absent")
    return destination


def validate_content_addressed(
    path: Path,
    source_dir: Path,
    *,
    generator_path: Path | None = None,
) -> dict[str, Any]:
    if not path.is_absolute() or path.is_symlink():
        raise DiagnosticError("diagnostic artifact path is unsafe")
    resolved = path.resolve(strict=True)
    if not resolved.is_file():
        raise DiagnosticError("diagnostic artifact path is unsafe")
    path = resolved
    match = re.fullmatch(
        r"bea-hmi7-cross-archive-revision-diagnostic-sha256-"
        r"([0-9a-f]{64})\.json",
        path.name,
    )
    if match is None:
        raise DiagnosticError("diagnostic filename is not content addressed")
    data = path.read_bytes()
    if sha256_bytes(data) != match[1]:
        raise DiagnosticError("diagnostic filename hash does not match content")
    document = parse_canonical_json(data, "diagnostic artifact")
    expected = build_diagnostic(source_dir, generator_path=generator_path)
    if document != expected:
        raise DiagnosticError("diagnostic content does not match sealed regeneration")
    return document


def default_source_dir() -> Path:
    return Path(__file__).resolve().parent.parent / "fingerprints"


def default_output_dir() -> Path:
    return Path(__file__).resolve().parent / "artifacts"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=default_source_dir())
    parser.add_argument("--output-dir", type=Path, default=default_output_dir())
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    diagnostic = build_diagnostic(arguments.source_dir)
    data = canonical_json_bytes(diagnostic)
    output_dir = arguments.output_dir
    if not output_dir.is_absolute():
        output_dir = output_dir.resolve()
    path = write_content_addressed(output_dir, data)
    validate_content_addressed(path, arguments.source_dir)
    print(path)
    print(f"sha256={sha256_bytes(data)}")
    print(f"targets={len(TARGETS)}")
    print(
        "comparison_periods="
        f"{len(quarter_sequence(COMPARISON_START, COMPARISON_END))}"
    )
    print(f"status={STATUS}")
    for gate, value in false_gates().items():
        print(f"{gate}={str(value).lower()}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except DiagnosticError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
