#!/usr/bin/env python3
"""Semantically fingerprint two pinned historical BEA HMI7 workbook pairs.

Only the exact present-day archive bytes pinned below are supported.  Parsing
those bytes does not establish their historical first state or availability
and cannot admit a forecast origin.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import re
import stat
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from dataclasses import asdict, dataclass
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from pathlib import Path, PurePosixPath
from typing import Any, Iterable, Mapping

MAIN_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
OFFICE_REL_NS = (
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
)
PACKAGE_REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"
WORKSHEET_REL_TYPE = f"{OFFICE_REL_NS}/worksheet"
NS = {"m": MAIN_NS, "p": PACKAGE_REL_NS}

SCHEMA_VERSION = "beforeit-us-bea-hmi7-historical-content-fingerprint.v1"
PARSER_VERSION = "beforeit-us-bea-hmi7-historical-ooxml-parser.v1"
STATUS = "PRESENT_DAY_ARCHIVE_BYTES_PARSED_NONADMITTING"
JSON_CANONICALIZATION = "utf8_sorted_keys_compact_json_lf"
SEMANTIC_IDENTITY_SCOPE = (
    "PINNED_RAW_PAIR_RELEASE_PROFILE_MAPPING_PROFILE_PARSER_AND_ALL_TARGET_HISTORY"
)
MAPPING_PROFILE_ID = "bea_hmi7_nipa_2012_base_dual_release.v1"
EXPECTED_MAPPING_PROFILE_SHA256 = (
    "8ed3038e7ea80c7207d57cabad6f2b8a50ea5bbe2e04587b63c7b5d242230171"
)
SOURCE_AGENCY = "U.S. Bureau of Economic Analysis"
SOURCE_ATTRIBUTION = "Source: U.S. Bureau of Economic Analysis"
SOURCE_TEXT = "Bureau of Economic Analysis"
PAIR_HASH_DOMAIN = "beforeit-us-bea-hmi7-historical-pair-sha256.v1"
MISSING_MARKER = "....."
COMPLETE_NUMERIC_START = "1997Q1"
REFERENCE_START = "1947Q1"
MAX_ARCHIVE_MEMBERS = 512
MAX_MEMBER_BYTES = 32_000_000
MAX_TOTAL_UNCOMPRESSED_BYTES = 128_000_000
XLSX_MAGIC = b"PK\x03\x04"

HASH_PATTERN = re.compile(r"[0-9a-f]{64}\Z")
ID_PATTERN = re.compile(r"[a-z0-9][a-z0-9._-]*\Z")
DECIMAL_PATTERN = re.compile(r"-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?\Z")
CELL_PATTERN = re.compile(r"([A-Z]+)([1-9][0-9]*)\Z")


class FingerprintError(RuntimeError):
    """Raised when a pinned identity or semantic invariant fails closed."""


@dataclass(frozen=True)
class WorkbookSpec:
    workbook_id: str
    section_id: str
    filename: str
    source_url: str
    sha256: str
    byte_count: int
    expected_sheet_count: int
    expected_sheet_manifest_sha256: str
    file_created_text: str


@dataclass(frozen=True)
class TargetSpec:
    target_id: str
    section_id: str
    sheet_name: str
    table_number: str
    table_title: str
    units_text: str
    published_line_number: int
    physical_row_number: int
    source_concept_text: str
    normalized_concept: str
    series_code: str
    seasonal_adjustment: str
    unit: str
    base_year: str
    decimal_places: int
    number_format_code: str
    sheet_last_row: int


@dataclass(frozen=True)
class ReleaseSpec:
    release_id: str
    capture_id: str
    reference_quarter: str
    estimate_label: str
    archive_directory_id: str
    archive_relative_path: str
    release_page_url: str
    release_event_timestamp_utc: str
    data_published_text: str
    reference_end: str
    terminal_column: str
    annual_update_caveat: str
    raw_pair_sha256: str
    latest_published_values: tuple[tuple[str, str], ...]
    workbooks: tuple[WorkbookSpec, WorkbookSpec]


@dataclass(frozen=True)
class CellData:
    value: str | None
    style_index: int
    cell_type: str | None
    has_formula: bool


TARGET_SPECS = (
    TargetSpec(
        target_id="nominal_gdp",
        section_id="1",
        sheet_name="T10105-Q",
        table_number="1.1.5",
        table_title="Table 1.1.5. Gross Domestic Product",
        units_text="[Millions of dollars] Seasonally adjusted at annual rates",
        published_line_number=1,
        physical_row_number=9,
        source_concept_text="    Gross domestic product",
        normalized_concept="Gross domestic product",
        series_code="A191RC",
        seasonal_adjustment="seasonally_adjusted_annual_rate",
        unit="millions_of_dollars",
        base_year="not_applicable",
        decimal_places=0,
        number_format_code="#,##0",
        sheet_last_row=34,
    ),
    TargetSpec(
        target_id="real_gdp",
        section_id="1",
        sheet_name="T10106-Q",
        table_number="1.1.6",
        table_title="Table 1.1.6. Real Gross Domestic Product, Chained Dollars",
        units_text=(
            "[Millions of chained (2012) dollars] "
            "Seasonally adjusted at annual rates"
        ),
        published_line_number=1,
        physical_row_number=9,
        source_concept_text="    Gross domestic product",
        normalized_concept="Gross domestic product",
        series_code="A191RX",
        seasonal_adjustment="seasonally_adjusted_annual_rate",
        unit="millions_of_chained_2012_dollars",
        base_year="2012",
        decimal_places=0,
        number_format_code="#,##0",
        sheet_last_row=37,
    ),
    TargetSpec(
        target_id="gdp_deflator",
        section_id="1",
        sheet_name="T10109-Q",
        table_number="1.1.9",
        table_title=(
            "Table 1.1.9. Implicit Price Deflators for Gross Domestic Product"
        ),
        units_text="[Index numbers, 2012=100] Seasonally adjusted",
        published_line_number=1,
        physical_row_number=9,
        source_concept_text="    Gross domestic product",
        normalized_concept="Gross domestic product",
        series_code="A191RD",
        seasonal_adjustment="seasonally_adjusted",
        unit="index",
        base_year="2012",
        decimal_places=3,
        number_format_code="#,##0.000",
        sheet_last_row=36,
    ),
    TargetSpec(
        target_id="pce_price_index",
        section_id="2",
        sheet_name="T20304-Q",
        table_number="2.3.4",
        table_title=(
            "Table 2.3.4. Price Indexes for Personal Consumption "
            "Expenditures by Major Type of Product"
        ),
        units_text="[Index numbers, 2012=100] Seasonally adjusted",
        published_line_number=1,
        physical_row_number=9,
        source_concept_text="    Personal consumption expenditures (PCE)",
        normalized_concept="Personal consumption expenditures (PCE)",
        series_code="DPCERG",
        seasonal_adjustment="seasonally_adjusted",
        unit="index",
        base_year="2012",
        decimal_places=3,
        number_format_code="#,##0.000",
        sheet_last_row=44,
    ),
    TargetSpec(
        target_id="core_pce_price_index",
        section_id="2",
        sheet_name="T20304-Q",
        table_number="2.3.4",
        table_title=(
            "Table 2.3.4. Price Indexes for Personal Consumption "
            "Expenditures by Major Type of Product"
        ),
        units_text="[Index numbers, 2012=100] Seasonally adjusted",
        published_line_number=25,
        physical_row_number=34,
        source_concept_text="  PCE excluding food and energy\\4\\",
        normalized_concept="PCE excluding food and energy",
        series_code="DPCCRG",
        seasonal_adjustment="seasonally_adjusted",
        unit="index",
        base_year="2012",
        decimal_places=3,
        number_format_code="#,##0.000",
        sheet_last_row=44,
    ),
)

RELEASE_SPECS = (
    ReleaseSpec(
        release_id="r2019q4_advance_hmi7_monthly_snapshot",
        capture_id="bea_hmi7_2019q4_advance_monthly_snapshot",
        reference_quarter="2019Q4",
        estimate_label="advance",
        archive_directory_id="13075",
        archive_relative_path=(
            "Files/Releases/GDP_and_PI/2019/Q4/"
            "Advance_January-31-2020"
        ),
        release_page_url=(
            "https://www.bea.gov/news/2020/"
            "gross-domestic-product-fourth-quarter-and-year-2019-advance-estimate"
        ),
        release_event_timestamp_utc="2020-01-30T13:30:00.000Z",
        data_published_text="Data published January 30, 2020",
        reference_end="2019Q4",
        terminal_column="KI",
        annual_update_caveat="NOT_AN_ANNUAL_UPDATE_RELEASE",
        raw_pair_sha256=(
            "6752afcae4b6882f2c723f8e8ef6e87e93d1102e3beac79b657f159b0056f4ef"
        ),
        latest_published_values=(
            ("nominal_gdp", "21734266"),
            ("real_gdp", "19219767"),
            ("gdp_deflator", "113.083"),
            ("pce_price_index", "110.352"),
            ("core_pce_price_index", "112.366"),
        ),
        workbooks=(
            WorkbookSpec(
                workbook_id="r2019q4_advance_s1",
                section_id="1",
                filename="Section1all_xls.xlsx",
                source_url=(
                    "https://apps.bea.gov/HistData/Files/Releases/GDP_and_PI/"
                    "2019/Q4/Advance_January-31-2020/Section1all_xls.xlsx"
                ),
                sha256=(
                    "35b170c5c82980a0dfea5cb6db45f2851fc3a3e4dfbbb37773ec71f23b44501a"
                ),
                byte_count=3_743_559,
                expected_sheet_count=107,
                expected_sheet_manifest_sha256=(
                    "1e19d83c3a3661ecf8e6976f8e16304d42c118d90a1a86744623af2cdbb228c4"
                ),
                file_created_text="File created Jan 29 2020  4:00PM",
            ),
            WorkbookSpec(
                workbook_id="r2019q4_advance_s2",
                section_id="2",
                filename="Section2all_xls.xlsx",
                source_url=(
                    "https://apps.bea.gov/HistData/Files/Releases/GDP_and_PI/"
                    "2019/Q4/Advance_January-31-2020/Section2all_xls.xlsx"
                ),
                sha256=(
                    "8f3935eb2ae44fea9066cdac632f38b858cfbd74731756db2461123726fb6028"
                ),
                byte_count=1_759_752,
                expected_sheet_count=39,
                expected_sheet_manifest_sha256=(
                    "c458880fda8d2ddd64d350b72bd6f9b49ad6192c482cd8529397980a1127cfdc"
                ),
                file_created_text="File created Jan 30 2020 10:43AM",
            ),
        ),
    ),
    ReleaseSpec(
        release_id="r2021q2_advance_annual_update_hmi7_monthly_snapshot",
        capture_id=(
            "bea_hmi7_2021q2_advance_annual_update_monthly_snapshot"
        ),
        reference_quarter="2021Q2",
        estimate_label="advance",
        archive_directory_id="13091",
        archive_relative_path=(
            "Files/Releases/GDP_and_PI/2021/Q2/Advance_July-30-2021"
        ),
        release_page_url=(
            "https://www.bea.gov/news/2021/"
            "gross-domestic-product-second-quarter-2021-advance-estimate-and-"
            "annual-update"
        ),
        release_event_timestamp_utc="2021-07-29T12:30:00.000Z",
        data_published_text="Data published July 29, 2021",
        reference_end="2021Q2",
        terminal_column="KO",
        annual_update_caveat=(
            "THIS_RELEASE_INCLUDES_THE_2021_ANNUAL_UPDATE_AND_REVISED_HISTORY_"
            "MUST_NOT_BE_TREATED_AS_A_STANDARD_WITHIN_DEFINITION_VINTAGE"
        ),
        raw_pair_sha256=(
            "79b8ce7f2f096bcd0177350381e0bef81bc8b77b0df374c411c7d07b582e5b50"
        ),
        latest_published_values=(
            ("nominal_gdp", "22722581"),
            ("real_gdp", "19358176"),
            ("gdp_deflator", "117.380"),
            ("pce_price_index", "114.758"),
            ("core_pce_price_index", "116.716"),
        ),
        workbooks=(
            WorkbookSpec(
                workbook_id="r2021q2_advance_annual_update_s1",
                section_id="1",
                filename="Section1all_xls.xlsx",
                source_url=(
                    "https://apps.bea.gov/HistData/Files/Releases/GDP_and_PI/"
                    "2021/Q2/Advance_July-30-2021/Section1all_xls.xlsx"
                ),
                sha256=(
                    "ccc7a5cf63de4022613404d05bcb2a0a1689875d5c45bcc5f3386ae09eec9ffb"
                ),
                byte_count=3_816_200,
                expected_sheet_count=107,
                expected_sheet_manifest_sha256=(
                    "1e19d83c3a3661ecf8e6976f8e16304d42c118d90a1a86744623af2cdbb228c4"
                ),
                file_created_text="File created Jul 29 2021  4:55PM",
            ),
            WorkbookSpec(
                workbook_id="r2021q2_advance_annual_update_s2",
                section_id="2",
                filename="Section2all_xls.xlsx",
                source_url=(
                    "https://apps.bea.gov/HistData/Files/Releases/GDP_and_PI/"
                    "2021/Q2/Advance_July-30-2021/Section2all_xls.xlsx"
                ),
                sha256=(
                    "84dff5de137cd3043e0392798875c1bb80a9190c4bddfdb76f495163cdf1ff9a"
                ),
                byte_count=1_784_998,
                expected_sheet_count=38,
                expected_sheet_manifest_sha256=(
                    "7b1fe66c5ea99061ca0b47d303cad58046fe2c4264e31f9e27cdb524003c5ab8"
                ),
                file_created_text="File created Jul 29 2021  5:00PM",
            ),
        ),
    ),
)

RELEASE_BY_ID = {release.release_id: release for release in RELEASE_SPECS}
CANONICAL_TARGET_SPECS = TARGET_SPECS
PINNED_RELEASE_PROFILE_SHA256 = {
    "r2019q4_advance_hmi7_monthly_snapshot": (
        "c4481a6df9174b756be0257331bd6010cb1e53f698161cd85088f33bf85bf23c"
    ),
    "r2021q2_advance_annual_update_hmi7_monthly_snapshot": (
        "6788c9f35f35f53c3e089085367e8205e06ad48ddebb6d09a601273ef70852e8"
    ),
}
PINNED_HISTORY_DIGESTS = {
    "r2019q4_advance_hmi7_monthly_snapshot": {
        "core_pce_price_index": (
            "f4f0c64c97b1e8abdadafd8a741b6f90080804e3028e8cba14178cc21278d4f3",
            "7d3ff3937ac33cf0498efd5277e835dfe918aa09e6d4339e45aaecb287ad85fe",
        ),
        "gdp_deflator": (
            "e259e9cafb4f6ccc1831fcfa57480457f25299ee4890db6ee2816740cd19a83c",
            "19860ded0c06b503aaddd4e12839704ff0b895f39ed111e0238fe988b6774f84",
        ),
        "nominal_gdp": (
            "f0dd7d9f73c541da1aee105c41d763adf8bc6fefa5bb446870eb4b498a6e1565",
            "f0dd7d9f73c541da1aee105c41d763adf8bc6fefa5bb446870eb4b498a6e1565",
        ),
        "pce_price_index": (
            "f09a9f9d35e9bc252e57649cd1446779bf64e78a421c1bac5aac90897b848d5a",
            "72dcb355736d6aa20767535a245cd27ca91bab5917360b82685cebe15f1d90a5",
        ),
        "real_gdp": (
            "836394dea0dbf17a4e8ab62deb53607558cbbf179d547cc20a3de400f4f0ad3e",
            "836394dea0dbf17a4e8ab62deb53607558cbbf179d547cc20a3de400f4f0ad3e",
        ),
    },
    "r2021q2_advance_annual_update_hmi7_monthly_snapshot": {
        "core_pce_price_index": (
            "552442dc8524f4f7be628856938de0b65ef0a0bf388fcd7fc8845bc3f8150cd8",
            "f0b1df6206ab1959ff521696c3091be300d79363aa067b48b12f00d3a0eb8b45",
        ),
        "gdp_deflator": (
            "2df077f6ef2ef7406c75a7fb205fa62378db2dbc008079b72c6c05703f61f5de",
            "be22a36ed5f676005d209e41f5428bb7749bbf797bd4ed4dc3a092242b8d5f07",
        ),
        "nominal_gdp": (
            "15ddf37d3594dcebf9857f18f64af93a8404a674bcf73806192aea9cfdba0f68",
            "15ddf37d3594dcebf9857f18f64af93a8404a674bcf73806192aea9cfdba0f68",
        ),
        "pce_price_index": (
            "1d26e21fe01cfe541155c630dd00cb13e116cc1b4dcffa16187e9521b733eeb8",
            "e3702fbe637a599cd18fa786aebaa21ff0888c72e2a9a28ae96e3ff18581b2e1",
        ),
        "real_gdp": (
            "2782329124f5e8bce7c1cdb8d5ac176c7d77c1d7c7b62019e9bbb0a189583bd6",
            "2782329124f5e8bce7c1cdb8d5ac176c7d77c1d7c7b62019e9bbb0a189583bd6",
        ),
    },
}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


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


def mapping_profile_payload(
    targets: tuple[TargetSpec, ...] = TARGET_SPECS,
) -> dict[str, Any]:
    return {
        "mapping_profile_id": MAPPING_PROFILE_ID,
        "frequency": "quarterly",
        "reference_period_start": REFERENCE_START,
        "complete_numeric_start": COMPLETE_NUMERIC_START,
        "targets": [asdict(target) for target in targets],
    }


def mapping_profile_sha256(
    targets: tuple[TargetSpec, ...] = TARGET_SPECS,
) -> str:
    return sha256_bytes(canonical_json_bytes(mapping_profile_payload(targets)))


def release_profile_payload(release: ReleaseSpec) -> dict[str, Any]:
    return {
        "release_id": release.release_id,
        "capture_id": release.capture_id,
        "reference_quarter": release.reference_quarter,
        "estimate_label": release.estimate_label,
        "archive_directory_id": release.archive_directory_id,
        "archive_relative_path": release.archive_relative_path,
        "release_page_url": release.release_page_url,
        "release_event_timestamp_utc": release.release_event_timestamp_utc,
        "data_published_text": release.data_published_text,
        "reference_start": REFERENCE_START,
        "reference_end": release.reference_end,
        "terminal_column": release.terminal_column,
        "annual_update_caveat": release.annual_update_caveat,
        "raw_pair_sha256": release.raw_pair_sha256,
        "latest_published_values": dict(release.latest_published_values),
        "workbooks": [asdict(workbook) for workbook in release.workbooks],
        "mapping_profile_sha256": mapping_profile_sha256(),
    }


def release_profile_sha256(release: ReleaseSpec) -> str:
    return sha256_bytes(canonical_json_bytes(release_profile_payload(release)))


def _hash_field(buffer: bytearray, name: str, value: Any) -> None:
    name_bytes = name.encode("utf-8")
    value_bytes = str(value).encode("utf-8")
    buffer.extend(str(len(name_bytes)).encode("ascii"))
    buffer.extend(b":")
    buffer.extend(name_bytes)
    buffer.extend(str(len(value_bytes)).encode("ascii"))
    buffer.extend(b":")
    buffer.extend(value_bytes)


def expected_pair_sha256(release: ReleaseSpec) -> str:
    buffer = bytearray()
    _hash_field(buffer, "domain", PAIR_HASH_DOMAIN)
    _hash_field(buffer, "capture_id", release.capture_id)
    for index, workbook in enumerate(release.workbooks, start=1):
        _hash_field(buffer, "workbook_index", index)
        _hash_field(buffer, "section_id", workbook.section_id)
        _hash_field(buffer, "source_url", workbook.source_url)
        _hash_field(buffer, "raw_sha256", workbook.sha256)
        _hash_field(buffer, "raw_byte_count", workbook.byte_count)
    return sha256_bytes(bytes(buffer))


def column_number(name: str) -> int:
    if re.fullmatch(r"[A-Z]+", name) is None:
        raise FingerprintError(f"invalid Excel column name: {name!r}")
    result = 0
    for character in name:
        result = result * 26 + ord(character) - ord("A") + 1
    return result


def column_name(number: int) -> str:
    if number < 1:
        raise FingerprintError("Excel column number must be positive")
    characters: list[str] = []
    while number:
        number, remainder = divmod(number - 1, 26)
        characters.append(chr(ord("A") + remainder))
    return "".join(reversed(characters))


def quarter_sequence(start: str, end: str) -> list[str]:
    start_match = re.fullmatch(r"([0-9]{4})Q([1-4])", start)
    end_match = re.fullmatch(r"([0-9]{4})Q([1-4])", end)
    if start_match is None or end_match is None:
        raise FingerprintError("quarter bounds must use YYYYQ[1-4]")
    start_index = int(start_match[1]) * 4 + int(start_match[2]) - 1
    end_index = int(end_match[1]) * 4 + int(end_match[2]) - 1
    if start_index > end_index:
        raise FingerprintError("quarter bounds are reversed")
    return [
        f"{index // 4}Q{index % 4 + 1}"
        for index in range(start_index, end_index + 1)
    ]


def normalized_lexical_path(path: Path) -> Path:
    return Path(os.path.normpath(os.fspath(path)))


def require_absolute_normalized(path: Path, location: str) -> Path:
    if not path.is_absolute():
        raise FingerprintError(f"{location} must be absolute")
    if normalized_lexical_path(path) != path:
        raise FingerprintError(f"{location} must be lexically normalized")
    return path


def safe_raw_path(raw_root: Path, path: Path) -> Path:
    require_absolute_normalized(raw_root, "raw root")
    require_absolute_normalized(path, "workbook path")
    if raw_root.is_symlink():
        raise FingerprintError(f"raw root is a symbolic link: {raw_root}")
    root = raw_root.resolve(strict=True)
    if root != raw_root or not root.is_dir():
        raise FingerprintError(f"raw root is not canonical: {raw_root}")
    if path.is_symlink():
        raise FingerprintError(f"workbook is a symbolic link: {path}")
    resolved = path.resolve(strict=True)
    if resolved != path:
        raise FingerprintError(f"workbook path is not canonical: {path}")
    if not resolved.is_file():
        raise FingerprintError(f"workbook is not a regular file: {path}")
    try:
        resolved.relative_to(root)
    except ValueError as error:
        raise FingerprintError(f"workbook escapes raw root: {path}") from error
    return resolved


def _safe_output_directory(output_dir: Path) -> Path:
    require_absolute_normalized(output_dir, "output directory")
    if output_dir.exists():
        if output_dir.is_symlink() or not output_dir.is_dir():
            raise FingerprintError("output directory is unsafe")
        resolved = output_dir.resolve(strict=True)
        if resolved != output_dir:
            raise FingerprintError("output directory is not canonical")
        return resolved
    parent = output_dir.parent.resolve(strict=True)
    if parent != output_dir.parent or not parent.is_dir():
        raise FingerprintError("output directory parent is not canonical")
    output_dir.mkdir()
    if output_dir.is_symlink():
        raise FingerprintError("output directory became a symlink")
    return output_dir.resolve(strict=True)


def _validate_identifier(value: str, location: str) -> None:
    if ID_PATTERN.fullmatch(value) is None:
        raise FingerprintError(f"{location} is not a canonical identifier")


def validate_canonical_mapping_specs(
    targets: tuple[TargetSpec, ...],
) -> None:
    if targets != CANONICAL_TARGET_SPECS:
        raise FingerprintError("target mapping/profile drifted")
    target_ids = [target.target_id for target in targets]
    if len(target_ids) != 5 or len(set(target_ids)) != 5:
        raise FingerprintError("mapping must contain exactly five unique targets")
    for target in targets:
        _validate_identifier(target.target_id, "target_id")
        if target.section_id not in {"1", "2"}:
            raise FingerprintError("mapping contains an unsupported section")
    if mapping_profile_sha256(targets) != EXPECTED_MAPPING_PROFILE_SHA256:
        raise FingerprintError("mapping/profile SHA-256 drifted")


def validate_release_spec(release: ReleaseSpec, *, pinned: bool = True) -> None:
    _validate_identifier(release.release_id, "release_id")
    _validate_identifier(release.capture_id, "capture_id")
    if len(release.workbooks) != 2:
        raise FingerprintError("release must contain exactly two workbooks")
    if tuple(workbook.section_id for workbook in release.workbooks) != ("1", "2"):
        raise FingerprintError("release workbook order must be Section1, Section2")
    if len({workbook.workbook_id for workbook in release.workbooks}) != 2:
        raise FingerprintError("release workbook IDs are aliased")
    if len({workbook.source_url for workbook in release.workbooks}) != 2:
        raise FingerprintError("release workbook URLs are aliased")
    if len({workbook.sha256 for workbook in release.workbooks}) != 2:
        raise FingerprintError("release raw identities are aliased")
    for workbook in release.workbooks:
        _validate_identifier(workbook.workbook_id, "workbook_id")
        if HASH_PATTERN.fullmatch(workbook.sha256) is None:
            raise FingerprintError("workbook SHA-256 is malformed")
        if HASH_PATTERN.fullmatch(workbook.expected_sheet_manifest_sha256) is None:
            raise FingerprintError("sheet-manifest SHA-256 is malformed")
        if workbook.byte_count <= 0 or workbook.expected_sheet_count <= 0:
            raise FingerprintError("workbook counts must be positive")
    if expected_pair_sha256(release) != release.raw_pair_sha256:
        raise FingerprintError("release raw pair SHA-256 drifted")
    expected_periods = quarter_sequence(REFERENCE_START, release.reference_end)
    expected_terminal = column_name(column_number("D") + len(expected_periods) - 1)
    if expected_terminal != release.terminal_column:
        raise FingerprintError("release terminal column drifted")
    if len(release.latest_published_values) != 5 or set(
        dict(release.latest_published_values)
    ) != {
        target.target_id for target in TARGET_SPECS
    }:
        raise FingerprintError("release latest-value coverage drifted")
    if pinned and release not in RELEASE_SPECS:
        raise FingerprintError("release profile is not one of the two pinned profiles")
    if pinned and release_profile_sha256(release) != (
        PINNED_RELEASE_PROFILE_SHA256.get(release.release_id)
    ):
        raise FingerprintError("pinned release profile SHA-256 drifted")
    if pinned:
        history_digests = PINNED_HISTORY_DIGESTS.get(release.release_id)
        if history_digests is None or set(history_digests) != {
            target.target_id for target in TARGET_SPECS
        }:
            raise FingerprintError("pinned history-digest coverage drifted")
        if any(
            HASH_PATTERN.fullmatch(digest) is None
            for pair in history_digests.values()
            for digest in pair
        ):
            raise FingerprintError("pinned history digest is malformed")


def _parse_xml(data: bytes, location: str) -> ET.Element:
    upper = data[:4096].upper()
    if b"<!DOCTYPE" in upper or b"<!ENTITY" in upper:
        raise FingerprintError(f"{location} contains a forbidden XML declaration")
    try:
        return ET.fromstring(data)
    except ET.ParseError as error:
        raise FingerprintError(f"{location} is malformed XML") from error


def _normalized_member_name(name: str) -> str:
    if not name or "\x00" in name or "\\" in name:
        raise FingerprintError("ZIP member name is unsafe")
    path = PurePosixPath(name)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        raise FingerprintError(f"ZIP member path is unsafe: {name!r}")
    normalized = str(path)
    if normalized != name.rstrip("/"):
        raise FingerprintError(f"ZIP member path is not canonical: {name!r}")
    return normalized


def validate_zip_members(archive: zipfile.ZipFile) -> set[str]:
    infos = archive.infolist()
    if not infos or len(infos) > MAX_ARCHIVE_MEMBERS:
        raise FingerprintError("ZIP member count is outside the allowed range")
    names: set[str] = set()
    casefolded: set[str] = set()
    total = 0
    for info in infos:
        name = _normalized_member_name(info.filename)
        folded = name.casefold()
        if name in names or folded in casefolded:
            raise FingerprintError(f"ZIP member alias or duplicate: {name}")
        names.add(name)
        casefolded.add(folded)
        if info.flag_bits & 0x1:
            raise FingerprintError("encrypted ZIP members are forbidden")
        mode = (info.external_attr >> 16) & 0xFFFF
        if stat.S_IFMT(mode) == stat.S_IFLNK:
            raise FingerprintError("ZIP symbolic-link members are forbidden")
        if info.file_size < 0 or info.file_size > MAX_MEMBER_BYTES:
            raise FingerprintError("ZIP member is too large")
        total += info.file_size
        if total > MAX_TOTAL_UNCOMPRESSED_BYTES:
            raise FingerprintError("ZIP uncompressed size limit exceeded")
    return names


def _relationship_target(target: str) -> str:
    if "\\" in target:
        raise FingerprintError("worksheet relationship target is unsafe")
    path = PurePosixPath(target)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        raise FingerprintError("worksheet relationship target is unsafe")
    if path.parts and path.parts[0] == "xl":
        normalized = path
    else:
        normalized = PurePosixPath("xl") / path
    return str(normalized)


def workbook_sheets(
    archive: zipfile.ZipFile,
    members: set[str],
) -> list[tuple[str, str]]:
    workbook = _parse_xml(
        archive.read("xl/workbook.xml"),
        "xl/workbook.xml",
    )
    relationships = _parse_xml(
        archive.read("xl/_rels/workbook.xml.rels"),
        "xl/_rels/workbook.xml.rels",
    )
    by_id: dict[str, tuple[str, str, str | None]] = {}
    for node in relationships.findall("p:Relationship", NS):
        try:
            relationship_id = node.attrib["Id"]
            relationship_type = node.attrib["Type"]
            target = node.attrib["Target"]
        except KeyError as error:
            raise FingerprintError("workbook relationship is incomplete") from error
        if relationship_id in by_id:
            raise FingerprintError("duplicate workbook relationship ID")
        by_id[relationship_id] = (
            relationship_type,
            target,
            node.attrib.get("TargetMode"),
        )

    result: list[tuple[str, str]] = []
    names: set[str] = set()
    targets: set[str] = set()
    for sheet in workbook.findall("m:sheets/m:sheet", NS):
        name = sheet.attrib.get("name")
        relationship_id = sheet.attrib.get(f"{{{OFFICE_REL_NS}}}id")
        if not name or not relationship_id or relationship_id not in by_id:
            raise FingerprintError("workbook sheet identity is incomplete")
        relationship_type, target, target_mode = by_id[relationship_id]
        if relationship_type != WORKSHEET_REL_TYPE or target_mode is not None:
            raise FingerprintError("sheet relationship is not an internal worksheet")
        normalized_target = _relationship_target(target)
        if normalized_target not in members:
            raise FingerprintError("worksheet relationship target is absent")
        if name in names or name.casefold() in {
            existing.casefold() for existing in names
        }:
            raise FingerprintError(f"duplicate or aliased sheet name: {name}")
        if normalized_target in targets:
            raise FingerprintError("worksheet relationship target is aliased")
        names.add(name)
        targets.add(normalized_target)
        result.append((name, normalized_target))
    if not result:
        raise FingerprintError("workbook defines no sheets")
    return result


def sheet_manifest_sha256(sheets: Iterable[tuple[str, str]]) -> str:
    payload = "".join(
        f"{index}\t{name}\t{target}\n"
        for index, (name, target) in enumerate(sheets, start=1)
    ).encode("utf-8")
    return sha256_bytes(payload)


def shared_strings(archive: zipfile.ZipFile) -> list[str]:
    path = "xl/sharedStrings.xml"
    if path not in archive.namelist():
        return []
    root = _parse_xml(archive.read(path), path)
    return [
        "".join(text.text or "" for text in item.findall(".//m:t", NS))
        for item in root.findall("m:si", NS)
    ]


def _cell_value(cell: ET.Element, strings: list[str]) -> str | None:
    cell_type = cell.attrib.get("t")
    if cell_type == "e":
        raise FingerprintError("worksheet contains an error cell")
    if cell_type == "inlineStr":
        return "".join(
            text.text or "" for text in cell.findall(".//m:t", NS)
        )
    value_node = cell.find("m:v", NS)
    if value_node is None:
        return None
    value = value_node.text or ""
    if cell_type == "s":
        try:
            index = int(value)
            if index < 0:
                raise ValueError
            return strings[index]
        except (ValueError, IndexError) as error:
            raise FingerprintError("invalid shared-string reference") from error
    if cell_type == "b":
        if value not in {"0", "1"}:
            raise FingerprintError("invalid Boolean cell value")
        return "true" if value == "1" else "false"
    if cell_type not in {None, "n", "str", "d"}:
        raise FingerprintError(f"unsupported worksheet cell type: {cell_type}")
    return value


def sheet_cells(
    archive: zipfile.ZipFile,
    sheet_path: str,
    strings: list[str],
) -> tuple[str, dict[str, CellData]]:
    root = _parse_xml(archive.read(sheet_path), sheet_path)
    dimension = root.find("m:dimension", NS)
    if dimension is None or not dimension.attrib.get("ref"):
        raise FingerprintError("worksheet dimension is absent")
    result: dict[str, CellData] = {}
    seen_rows: set[int] = set()
    previous_row = 0
    for row in root.findall(".//m:sheetData/m:row", NS):
        try:
            row_number = int(row.attrib["r"])
        except (KeyError, ValueError) as error:
            raise FingerprintError("worksheet row identity is invalid") from error
        if row_number <= previous_row or row_number in seen_rows:
            raise FingerprintError("worksheet rows are duplicated or unordered")
        seen_rows.add(row_number)
        previous_row = row_number
        previous_column = 0
        for cell in row.findall("m:c", NS):
            reference = cell.attrib.get("r")
            match = CELL_PATTERN.fullmatch(reference or "")
            if match is None or int(match[2]) != row_number:
                raise FingerprintError("worksheet contains an invalid cell address")
            column = column_number(match[1])
            if column <= previous_column or reference in result:
                raise FingerprintError("worksheet cells are duplicated or unordered")
            previous_column = column
            try:
                style_index = int(cell.attrib.get("s", "0"))
            except ValueError as error:
                raise FingerprintError("worksheet style index is invalid") from error
            if style_index < 0:
                raise FingerprintError("worksheet style index is negative")
            result[reference] = CellData(
                value=_cell_value(cell, strings),
                style_index=style_index,
                cell_type=cell.attrib.get("t"),
                has_formula=cell.find("m:f", NS) is not None,
            )
    return dimension.attrib["ref"], result


def number_formats(archive: zipfile.ZipFile) -> list[str]:
    built_in = {
        0: "General",
        1: "0",
        2: "0.00",
        3: "#,##0",
        4: "#,##0.00",
    }
    root = _parse_xml(archive.read("xl/styles.xml"), "xl/styles.xml")
    custom: dict[int, str] = {}
    for node in root.findall("m:numFmts/m:numFmt", NS):
        try:
            identifier = int(node.attrib["numFmtId"])
            format_code = node.attrib["formatCode"]
        except (KeyError, ValueError) as error:
            raise FingerprintError("custom number format is invalid") from error
        if identifier in custom:
            raise FingerprintError("custom number format is duplicated")
        custom[identifier] = format_code
    result: list[str] = []
    for style in root.findall("m:cellXfs/m:xf", NS):
        try:
            identifier = int(style.attrib["numFmtId"])
        except (KeyError, ValueError) as error:
            raise FingerprintError("cell number format is invalid") from error
        if identifier in custom:
            result.append(custom[identifier])
        elif identifier in built_in:
            result.append(built_in[identifier])
        else:
            raise FingerprintError(
                f"unsupported workbook number format ID {identifier}"
            )
    if not result:
        raise FingerprintError("workbook defines no cell formats")
    return result


def required_cell(cells: Mapping[str, CellData], address: str) -> CellData:
    if address not in cells or cells[address].value is None:
        raise FingerprintError(f"required cell {address} is empty or absent")
    cell = cells[address]
    if cell.has_formula:
        raise FingerprintError(f"required cell {address} contains a formula")
    if cell.cell_type == "e":
        raise FingerprintError(f"required cell {address} contains an error")
    return cell


def required_text(cells: Mapping[str, CellData], address: str) -> str:
    return str(required_cell(cells, address).value)


def validate_numeric(value: str, address: str, *, allow_missing: bool) -> None:
    if allow_missing and value == MISSING_MARKER:
        return
    if len(value) > 128:
        raise FingerprintError(f"target value {address} is too long")
    if DECIMAL_PATTERN.fullmatch(value) is None:
        raise FingerprintError(
            f"target value {address} is not a canonical decimal"
        )


def published_value(value: str, decimal_places: int, address: str) -> str:
    if value == MISSING_MARKER:
        return value
    try:
        decimal = Decimal(value)
    except InvalidOperation as error:
        raise FingerprintError(f"invalid numeric value at {address}") from error
    if not decimal.is_finite():
        raise FingerprintError(f"non-finite numeric value at {address}")
    quantum = Decimal(1).scaleb(-decimal_places)
    rounded = decimal.quantize(quantum, rounding=ROUND_HALF_UP)
    return format(rounded, f".{decimal_places}f")


def values_digest(periods: list[str], values: list[str]) -> str:
    if len(periods) != len(values):
        raise FingerprintError("period/value lengths differ")
    payload = "".join(
        f"{period}\t{value}\n" for period, value in zip(periods, values)
    ).encode("utf-8")
    return sha256_bytes(payload)


def validate_workbook_identity(path: Path, spec: WorkbookSpec) -> bytes:
    flags = os.O_RDONLY
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise FingerprintError(
            f"{spec.workbook_id} could not be opened safely"
        ) from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise FingerprintError(
                f"{spec.workbook_id} is not a regular file"
            )
        if before.st_size != spec.byte_count:
            raise FingerprintError(
                f"{spec.workbook_id} byte count drifted"
            )
        with os.fdopen(descriptor, "rb", closefd=False) as stream:
            data = stream.read(spec.byte_count + 1)
        after = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    identity_fields = ("st_dev", "st_ino", "st_size", "st_mtime_ns")
    if any(
        getattr(before, field) != getattr(after, field)
        for field in identity_fields
    ):
        raise FingerprintError(
            f"{spec.workbook_id} changed while being read"
        )
    if len(data) != spec.byte_count:
        raise FingerprintError(f"{spec.workbook_id} byte count drifted")
    if sha256_bytes(data) != spec.sha256:
        raise FingerprintError(f"{spec.workbook_id} SHA-256 drifted")
    if data[:4] != XLSX_MAGIC:
        raise FingerprintError(f"{spec.workbook_id} lacks OOXML ZIP magic")
    return data


def validate_path_still_pinned(path: Path, spec: WorkbookSpec) -> None:
    try:
        changed = (
            path.is_symlink()
            or path.resolve(strict=True) != path
            or not path.is_file()
            or path.stat().st_size != spec.byte_count
            or sha256_file(path) != spec.sha256
        )
    except OSError as error:
        raise FingerprintError(
            f"{spec.workbook_id} disappeared during parsing"
        ) from error
    if changed:
        raise FingerprintError(
            f"{spec.workbook_id} changed during parsing"
        )


def _critical_sheet_names(section_id: str) -> set[str]:
    return {
        target.sheet_name
        for target in TARGET_SPECS
        if target.section_id == section_id
    }


def parse_workbook(
    path: Path,
    workbook_spec: WorkbookSpec,
    release: ReleaseSpec,
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    workbook_bytes = validate_workbook_identity(path, workbook_spec)
    try:
        archive_context = zipfile.ZipFile(io.BytesIO(workbook_bytes), "r")
    except (OSError, zipfile.BadZipFile) as error:
        raise FingerprintError("workbook is not a valid ZIP archive") from error
    with archive_context as archive:
        members = validate_zip_members(archive)
        required_parts = {
            "[Content_Types].xml",
            "_rels/.rels",
            "xl/workbook.xml",
            "xl/_rels/workbook.xml.rels",
            "xl/styles.xml",
        }
        missing = sorted(required_parts - members)
        if missing:
            raise FingerprintError(f"workbook lacks OOXML parts: {missing}")
        corrupt = archive.testzip()
        if corrupt is not None:
            raise FingerprintError(f"workbook has corrupt ZIP member: {corrupt}")

        sheets = workbook_sheets(archive, members)
        if len(sheets) != workbook_spec.expected_sheet_count:
            raise FingerprintError("workbook sheet count drifted")
        manifest_digest = sheet_manifest_sha256(sheets)
        if manifest_digest != workbook_spec.expected_sheet_manifest_sha256:
            raise FingerprintError("workbook sheet manifest drifted")
        sheet_paths = dict(sheets)
        actual_critical = set(sheet_paths) & {
            target.sheet_name for target in TARGET_SPECS
        }
        if actual_critical != _critical_sheet_names(workbook_spec.section_id):
            raise FingerprintError("critical worksheet coverage drifted")

        formats = number_formats(archive)
        strings = shared_strings(archive)
        cache: dict[str, tuple[str, dict[str, CellData]]] = {}
        periods = quarter_sequence(REFERENCE_START, release.reference_end)
        terminal_column = column_name(
            column_number("D") + len(periods) - 1
        )
        if terminal_column != release.terminal_column:
            raise FingerprintError("computed terminal column drifted")
        complete_start_index = periods.index(COMPLETE_NUMERIC_START)
        latest_expected = dict(release.latest_published_values)
        target_records: list[dict[str, Any]] = []

        for target in TARGET_SPECS:
            if target.section_id != workbook_spec.section_id:
                continue
            if target.sheet_name not in sheet_paths:
                raise FingerprintError(f"missing sheet {target.sheet_name}")
            dimension, cells = cache.setdefault(
                target.sheet_name,
                sheet_cells(archive, sheet_paths[target.sheet_name], strings),
            )
            expected_dimension = (
                f"A1:{release.terminal_column}{target.sheet_last_row}"
            )
            if dimension != expected_dimension:
                raise FingerprintError(
                    f"{target.target_id} worksheet dimension drifted"
                )
            expected_headers = {
                "A1": target.table_title,
                "A2": target.units_text,
                "A3": (
                    f"Quarterly data from {REFERENCE_START} "
                    f"to {release.reference_end}"
                ),
                "A4": SOURCE_TEXT,
                "A5": release.data_published_text,
                "A6": workbook_spec.file_created_text,
                "A8": "Line",
                f"A{target.physical_row_number}": str(
                    target.published_line_number
                ),
                f"B{target.physical_row_number}": target.source_concept_text,
                f"C{target.physical_row_number}": target.series_code,
            }
            for address, expected in expected_headers.items():
                if required_text(cells, address) != expected:
                    raise FingerprintError(
                        f"{target.target_id} mapping/header drifted at {address}"
                    )

            raw_values: list[str] = []
            published_values: list[str] = []
            for offset, expected_period in enumerate(periods):
                column = column_name(column_number("D") + offset)
                header_address = f"{column}8"
                if required_text(cells, header_address) != expected_period:
                    raise FingerprintError(
                        f"{target.target_id} period axis drifted at "
                        f"{header_address}"
                    )
                address = f"{column}{target.physical_row_number}"
                cell = required_cell(cells, address)
                value = str(cell.value)
                allow_missing = offset < complete_start_index
                validate_numeric(value, address, allow_missing=allow_missing)
                if value != MISSING_MARKER:
                    if cell.cell_type not in {None, "n"}:
                        raise FingerprintError(
                            f"{target.target_id} numeric cell type drifted"
                        )
                    if cell.style_index >= len(formats):
                        raise FingerprintError(
                            f"{target.target_id} style index is out of range"
                        )
                    if formats[cell.style_index] != target.number_format_code:
                        raise FingerprintError(
                            f"{target.target_id} number format drifted at "
                            f"{address}"
                        )
                raw_values.append(value)
                published_values.append(
                    published_value(value, target.decimal_places, address)
                )

            if any(
                value == MISSING_MARKER
                for value in raw_values[complete_start_index:]
            ):
                raise FingerprintError(
                    f"{target.target_id} is incomplete from "
                    f"{COMPLETE_NUMERIC_START}"
                )
            latest_cell = (
                f"{release.terminal_column}{target.physical_row_number}"
            )
            latest_value = published_values[-1]
            if latest_value != latest_expected[target.target_id]:
                raise FingerprintError(
                    f"{target.target_id} latest published value drifted"
                )
            raw_values_sha256 = values_digest(periods, raw_values)
            published_values_sha256 = values_digest(
                periods,
                published_values,
            )
            pinned_histories = PINNED_HISTORY_DIGESTS.get(release.release_id)
            if pinned_histories is not None and (
                raw_values_sha256,
                published_values_sha256,
            ) != pinned_histories.get(target.target_id):
                raise FingerprintError(
                    f"{target.target_id} pinned history digest drifted"
                )
            target_records.append(
                {
                    "status": STATUS,
                    "target_id": target.target_id,
                    "workbook_id": workbook_spec.workbook_id,
                    "section_id": target.section_id,
                    "raw_sha256": workbook_spec.sha256,
                    "mapping_profile_id": MAPPING_PROFILE_ID,
                    "mapping_profile_sha256": mapping_profile_sha256(),
                    "sheet_name": target.sheet_name,
                    "worksheet_dimension": dimension,
                    "table_number": target.table_number,
                    "table_title": target.table_title,
                    "units_text": target.units_text,
                    "published_line_number": target.published_line_number,
                    "physical_row_number": target.physical_row_number,
                    "source_concept_text": target.source_concept_text,
                    "normalized_concept": target.normalized_concept,
                    "series_code": target.series_code,
                    "frequency": "quarterly",
                    "seasonal_adjustment": target.seasonal_adjustment,
                    "unit": target.unit,
                    "base_year": target.base_year,
                    "number_format_code": target.number_format_code,
                    "decimal_places": target.decimal_places,
                    "source_cells": {
                        "table_title": f"{target.sheet_name}!A1",
                        "units": f"{target.sheet_name}!A2",
                        "coverage": f"{target.sheet_name}!A3",
                        "publication": f"{target.sheet_name}!A5",
                        "file_created": f"{target.sheet_name}!A6",
                        "line": (
                            f"{target.sheet_name}!"
                            f"A{target.physical_row_number}"
                        ),
                        "concept": (
                            f"{target.sheet_name}!"
                            f"B{target.physical_row_number}"
                        ),
                        "series": (
                            f"{target.sheet_name}!"
                            f"C{target.physical_row_number}"
                        ),
                        "reference_period_range": (
                            f"{target.sheet_name}!D8:"
                            f"{release.terminal_column}8"
                        ),
                        "value_range": (
                            f"{target.sheet_name}!"
                            f"D{target.physical_row_number}:"
                            f"{release.terminal_column}"
                            f"{target.physical_row_number}"
                        ),
                        "latest_value": f"{target.sheet_name}!{latest_cell}",
                    },
                    "reference_period_start": periods[0],
                    "reference_period_end": periods[-1],
                    "reference_period_count": len(periods),
                    "available_value_count": sum(
                        value != MISSING_MARKER for value in raw_values
                    ),
                    "missing_value_count": sum(
                        value == MISSING_MARKER for value in raw_values
                    ),
                    "complete_numeric_window": {
                        "start": COMPLETE_NUMERIC_START,
                        "end": periods[-1],
                        "observation_count": len(periods) - complete_start_index,
                        "all_values_numeric": True,
                    },
                    "latest_cell": latest_cell,
                    "latest_raw_value_text": raw_values[-1],
                    "latest_published_value_text": latest_value,
                    "raw_values_sha256": raw_values_sha256,
                    "published_values_sha256": published_values_sha256,
                    "observations": [
                        {
                            "period": period,
                            "raw_value_text": raw,
                            "published_value_text": published,
                        }
                        for period, raw, published in zip(
                            periods,
                            raw_values,
                            published_values,
                        )
                    ],
                    "gates": false_gates(),
                }
            )

        validate_path_still_pinned(path, workbook_spec)
        workbook_record = _workbook_record(release, workbook_spec)
        return workbook_record, target_records


def artifact_metadata(parser_path: Path) -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "parser_version": PARSER_VERSION,
        "status": STATUS,
        "canonicalization": JSON_CANONICALIZATION,
        "semantic_identity_scope": SEMANTIC_IDENTITY_SCOPE,
        "parser_sha256": sha256_file(parser_path),
        "mapping_profile_id": MAPPING_PROFILE_ID,
        "mapping_profile_sha256": mapping_profile_sha256(),
        "source_agency": SOURCE_AGENCY,
        "source_attribution": SOURCE_ATTRIBUTION,
        "evidence_class": "present_day_archive_content_observation",
        "release_event_evidence_included": False,
        "historical_first_state_evidence_included": False,
        "historical_availability_evidence_included": False,
        "execution_environment_included": False,
        "repository_state_included": False,
        "local_raw_paths_included": False,
        "persistence_scope": (
            "SMALL_CONTENT_FINGERPRINT_RAW_WORKBOOKS_EXTERNAL_TO_GIT"
        ),
        "gates": false_gates(),
    }


def _release_record(release: ReleaseSpec) -> dict[str, Any]:
    return {
        "status": STATUS,
        "release_id": release.release_id,
        "capture_id": release.capture_id,
        "reference_quarter": release.reference_quarter,
        "estimate_label": release.estimate_label,
        "archive_directory_id": release.archive_directory_id,
        "archive_relative_path": release.archive_relative_path,
        "release_page_url": release.release_page_url,
        "release_event_timestamp_utc": release.release_event_timestamp_utc,
        "release_event_is_workbook_snapshot": False,
        "data_published_text": release.data_published_text,
        "reference_period_start": REFERENCE_START,
        "reference_period_end": release.reference_end,
        "terminal_column": release.terminal_column,
        "annual_update_caveat": release.annual_update_caveat,
        "raw_pair_sha256": release.raw_pair_sha256,
        "release_profile_sha256": release_profile_sha256(release),
        "workbook_snapshot_boundary": (
            "HMI7_NEXT_DAY_MONTHLY_TABLE_SNAPSHOT_NOT_EXACT_RELEASE_TIME_CAPTURE"
        ),
        "gates": false_gates(),
    }


def _workbook_record(
    release: ReleaseSpec,
    workbook: WorkbookSpec,
) -> dict[str, Any]:
    return {
        "status": STATUS,
        "workbook_id": workbook.workbook_id,
        "release_id": release.release_id,
        "section_id": workbook.section_id,
        "filename": workbook.filename,
        "source_url": workbook.source_url,
        "expected_content_addressed_filename": (
            f"section-{workbook.section_id}-raw-sha256-"
            f"{workbook.sha256}.xlsx"
        ),
        "raw_sha256": workbook.sha256,
        "raw_byte_count": workbook.byte_count,
        "file_format": "xlsx",
        "ooxml_zip_integrity_verified": True,
        "sheet_count": workbook.expected_sheet_count,
        "sheet_manifest_sha256": workbook.expected_sheet_manifest_sha256,
        "data_published_text": release.data_published_text,
        "file_created_text": workbook.file_created_text,
        "mapping_profile_id": MAPPING_PROFILE_ID,
        "mapping_profile_sha256": mapping_profile_sha256(),
        "gates": false_gates(),
    }


def _target_source_cells(
    target: TargetSpec,
    release: ReleaseSpec,
) -> dict[str, str]:
    row = target.physical_row_number
    latest_cell = f"{release.terminal_column}{row}"
    return {
        "table_title": f"{target.sheet_name}!A1",
        "units": f"{target.sheet_name}!A2",
        "coverage": f"{target.sheet_name}!A3",
        "publication": f"{target.sheet_name}!A5",
        "file_created": f"{target.sheet_name}!A6",
        "line": f"{target.sheet_name}!A{row}",
        "concept": f"{target.sheet_name}!B{row}",
        "series": f"{target.sheet_name}!C{row}",
        "reference_period_range": (
            f"{target.sheet_name}!D8:{release.terminal_column}8"
        ),
        "value_range": (
            f"{target.sheet_name}!D{row}:"
            f"{release.terminal_column}{row}"
        ),
        "latest_value": f"{target.sheet_name}!{latest_cell}",
    }


def _target_static_record(
    target: TargetSpec,
    release: ReleaseSpec,
    workbook: WorkbookSpec,
) -> dict[str, Any]:
    periods = quarter_sequence(REFERENCE_START, release.reference_end)
    complete_start_index = periods.index(COMPLETE_NUMERIC_START)
    latest_cell = (
        f"{release.terminal_column}{target.physical_row_number}"
    )
    return {
        "status": STATUS,
        "target_id": target.target_id,
        "workbook_id": workbook.workbook_id,
        "section_id": target.section_id,
        "raw_sha256": workbook.sha256,
        "mapping_profile_id": MAPPING_PROFILE_ID,
        "mapping_profile_sha256": mapping_profile_sha256(),
        "sheet_name": target.sheet_name,
        "worksheet_dimension": (
            f"A1:{release.terminal_column}{target.sheet_last_row}"
        ),
        "table_number": target.table_number,
        "table_title": target.table_title,
        "units_text": target.units_text,
        "published_line_number": target.published_line_number,
        "physical_row_number": target.physical_row_number,
        "source_concept_text": target.source_concept_text,
        "normalized_concept": target.normalized_concept,
        "series_code": target.series_code,
        "frequency": "quarterly",
        "seasonal_adjustment": target.seasonal_adjustment,
        "unit": target.unit,
        "base_year": target.base_year,
        "number_format_code": target.number_format_code,
        "decimal_places": target.decimal_places,
        "source_cells": _target_source_cells(target, release),
        "reference_period_start": periods[0],
        "reference_period_end": periods[-1],
        "reference_period_count": len(periods),
        "complete_numeric_window": {
            "start": COMPLETE_NUMERIC_START,
            "end": periods[-1],
            "observation_count": len(periods) - complete_start_index,
            "all_values_numeric": True,
        },
        "latest_cell": latest_cell,
        "latest_published_value_text": dict(
            release.latest_published_values
        )[target.target_id],
        "gates": false_gates(),
    }


def _validate_target_record(
    record: Any,
    target: TargetSpec,
    release: ReleaseSpec,
    workbook: WorkbookSpec,
) -> None:
    location = f"targets.{target.target_id}"
    if not isinstance(record, dict):
        raise FingerprintError(f"{location} must be an object")
    static = _target_static_record(target, release, workbook)
    dynamic_keys = {
        "available_value_count",
        "missing_value_count",
        "latest_raw_value_text",
        "raw_values_sha256",
        "published_values_sha256",
        "observations",
    }
    if set(record) != set(static) | dynamic_keys:
        raise FingerprintError(f"{location} keys drifted")
    for key, expected in static.items():
        if record[key] != expected:
            raise FingerprintError(f"{location}.{key} drifted")

    observations = record["observations"]
    periods = quarter_sequence(REFERENCE_START, release.reference_end)
    if not isinstance(observations, list) or len(observations) != len(periods):
        raise FingerprintError(f"{location}.observations length drifted")
    complete_start_index = periods.index(COMPLETE_NUMERIC_START)
    raw_values: list[str] = []
    published_values: list[str] = []
    for index, (observation, period) in enumerate(
        zip(observations, periods)
    ):
        if not isinstance(observation, dict) or set(observation) != {
            "period",
            "raw_value_text",
            "published_value_text",
        }:
            raise FingerprintError(
                f"{location}.observations[{index}] keys drifted"
            )
        if observation["period"] != period:
            raise FingerprintError(
                f"{location}.observations[{index}].period drifted"
            )
        raw = observation["raw_value_text"]
        published = observation["published_value_text"]
        if not isinstance(raw, str) or not isinstance(published, str):
            raise FingerprintError(
                f"{location}.observations[{index}] values must be strings"
            )
        validate_numeric(
            raw,
            f"{location}.observations[{index}].raw_value_text",
            allow_missing=index < complete_start_index,
        )
        expected_published = published_value(
            raw,
            target.decimal_places,
            f"{location}.observations[{index}].raw_value_text",
        )
        if published != expected_published:
            raise FingerprintError(
                f"{location}.observations[{index}] published value drifted"
            )
        raw_values.append(raw)
        published_values.append(published)

    available_count = sum(value != MISSING_MARKER for value in raw_values)
    missing_count = len(raw_values) - available_count
    if record["available_value_count"] != available_count:
        raise FingerprintError(f"{location}.available_value_count drifted")
    if record["missing_value_count"] != missing_count:
        raise FingerprintError(f"{location}.missing_value_count drifted")
    if record["latest_raw_value_text"] != raw_values[-1]:
        raise FingerprintError(f"{location}.latest_raw_value_text drifted")
    raw_digest = values_digest(periods, raw_values)
    published_digest = values_digest(periods, published_values)
    if record["raw_values_sha256"] != raw_digest:
        raise FingerprintError(f"{location}.raw_values_sha256 drifted")
    if record["published_values_sha256"] != published_digest:
        raise FingerprintError(f"{location}.published_values_sha256 drifted")
    if (raw_digest, published_digest) != PINNED_HISTORY_DIGESTS[
        release.release_id
    ][target.target_id]:
        raise FingerprintError(f"{location} pinned history drifted")


def _build_artifact(
    release: ReleaseSpec,
    raw_root: Path,
    paths_by_section: Mapping[str, Path],
    *,
    parser_path: Path,
    pinned: bool,
) -> dict[str, Any]:
    parser_sha256_before = sha256_file(parser_path)
    validate_canonical_mapping_specs(TARGET_SPECS)
    validate_release_spec(release, pinned=pinned)
    if set(paths_by_section) != {"1", "2"}:
        raise FingerprintError("a complete Section1+Section2 pair is required")
    paths = {
        section: safe_raw_path(raw_root, path)
        for section, path in paths_by_section.items()
    }
    if len(set(paths.values())) != 2:
        raise FingerprintError("workbook paths are aliased")

    workbook_records: list[dict[str, Any]] = []
    target_records: list[dict[str, Any]] = []
    for workbook in release.workbooks:
        record, targets = parse_workbook(
            paths[workbook.section_id],
            workbook,
            release,
        )
        workbook_records.append(record)
        target_records.extend(targets)

    if len({record["raw_sha256"] for record in workbook_records}) != 2:
        raise FingerprintError("parsed raw workbook identities are aliased")
    actual_targets = [record["target_id"] for record in target_records]
    expected_targets = [target.target_id for target in TARGET_SPECS]
    if sorted(actual_targets) != sorted(expected_targets) or len(actual_targets) != 5:
        raise FingerprintError("parsed target coverage is not exactly five")
    if expected_pair_sha256(release) != release.raw_pair_sha256:
        raise FingerprintError("parsed raw pair identity drifted")
    for workbook in release.workbooks:
        validate_path_still_pinned(
            paths[workbook.section_id],
            workbook,
        )
    parser_sha256_after = sha256_file(parser_path)
    if parser_sha256_after != parser_sha256_before:
        raise FingerprintError("parser source changed during execution")
    metadata = artifact_metadata(parser_path)
    if metadata["parser_sha256"] != parser_sha256_before:
        raise FingerprintError("parser source changed during metadata binding")
    return {
        "artifact": metadata,
        "release": _release_record(release),
        "workbooks": sorted(
            workbook_records,
            key=lambda record: record["section_id"],
        ),
        "targets": sorted(
            target_records,
            key=lambda record: record["target_id"],
        ),
    }


def build_artifact(
    release_id: str,
    raw_root: Path,
    section_1_path: Path,
    section_2_path: Path,
) -> dict[str, Any]:
    if release_id not in RELEASE_BY_ID:
        raise FingerprintError(f"unsupported release_id: {release_id}")
    return _build_artifact(
        RELEASE_BY_ID[release_id],
        raw_root,
        {"1": section_1_path, "2": section_2_path},
        parser_path=Path(__file__).resolve(strict=True),
        pinned=True,
    )


def write_content_addressed(
    output_dir: Path,
    release_id: str,
    data: bytes,
) -> Path:
    _validate_identifier(release_id, "release_id")
    output = _safe_output_directory(output_dir)
    digest = sha256_bytes(data)
    destination = output / (
        f"bea-hmi7-{release_id}-content-fingerprint-sha256-{digest}.json"
    )
    if destination.exists():
        if destination.is_symlink() or not destination.is_file():
            raise FingerprintError("existing content artifact is unsafe")
        if destination.read_bytes() != data:
            raise FingerprintError("hash-addressed content artifact differs")
        return destination
    descriptor, temporary_name = tempfile.mkstemp(
        dir=output,
        prefix=".historical-fingerprint-",
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, destination)
    finally:
        if temporary.exists():
            temporary.unlink()
    return destination


def validate_content_addressed_artifact(path: Path) -> dict[str, Any]:
    require_absolute_normalized(path, "artifact path")
    if path.is_symlink() or not path.is_file() or path.resolve() != path:
        raise FingerprintError("artifact path is unsafe")
    match = re.search(r"-sha256-([0-9a-f]{64})\.json\Z", path.name)
    if match is None:
        raise FingerprintError("artifact filename is not content addressed")
    data = path.read_bytes()
    if sha256_bytes(data) != match[1]:
        raise FingerprintError("artifact content hash does not match filename")
    try:
        document = json.loads(data)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise FingerprintError("artifact is not valid UTF-8 JSON") from error
    if canonical_json_bytes(document) != data:
        raise FingerprintError("artifact is not canonical JSON")
    if not isinstance(document, dict) or set(document) != {
        "artifact",
        "release",
        "workbooks",
        "targets",
    }:
        raise FingerprintError("artifact top-level structure drifted")
    parser_path = Path(__file__).resolve(strict=True)
    if document["artifact"] != artifact_metadata(parser_path):
        raise FingerprintError("artifact metadata or parser binding drifted")
    release_record = document["release"]
    if not isinstance(release_record, dict):
        raise FingerprintError("release record must be an object")
    release_id = release_record.get("release_id")
    if release_id not in RELEASE_BY_ID:
        raise FingerprintError("artifact release_id is not pinned")
    release = RELEASE_BY_ID[release_id]
    validate_canonical_mapping_specs(TARGET_SPECS)
    validate_release_spec(release, pinned=True)
    if release_record != _release_record(release):
        raise FingerprintError("artifact release profile drifted")
    expected_filename = (
        f"bea-hmi7-{release.release_id}-content-fingerprint-"
        f"sha256-{match[1]}.json"
    )
    if path.name != expected_filename:
        raise FingerprintError("artifact filename release binding drifted")

    workbooks = document["workbooks"]
    expected_workbooks = [
        _workbook_record(release, workbook)
        for workbook in release.workbooks
    ]
    if workbooks != expected_workbooks:
        raise FingerprintError("artifact workbook identities drifted")

    records = document["targets"]
    if not isinstance(records, list) or len(records) != 5:
        raise FingerprintError("artifact target count drifted")
    if any(not isinstance(record, dict) for record in records):
        raise FingerprintError("artifact target must be an object")
    target_ids = [record.get("target_id") for record in records]
    expected_target_ids = sorted(
        target.target_id for target in TARGET_SPECS
    )
    if target_ids != expected_target_ids:
        raise FingerprintError("artifact target order or identity drifted")
    workbook_by_section = {
        workbook.section_id: workbook for workbook in release.workbooks
    }
    target_by_id = {
        target.target_id: target for target in TARGET_SPECS
    }
    for record in records:
        target = target_by_id[record["target_id"]]
        _validate_target_record(
            record,
            target,
            release,
            workbook_by_section[target.section_id],
        )
    return document


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--release-id",
        choices=tuple(RELEASE_BY_ID),
        required=True,
    )
    parser.add_argument("--raw-root", type=Path, required=True)
    parser.add_argument("--section-1", type=Path, required=True)
    parser.add_argument("--section-2", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    artifact = build_artifact(
        arguments.release_id,
        arguments.raw_root,
        arguments.section_1,
        arguments.section_2,
    )
    data = canonical_json_bytes(artifact)
    path = write_content_addressed(
        arguments.output_dir,
        arguments.release_id,
        data,
    )
    print(path)
    print(f"sha256={sha256_bytes(data)}")
    print("targets=5")
    print(f"status={STATUS}")
    for gate, value in false_gates().items():
        print(f"{gate}={str(value).lower()}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except FingerprintError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
