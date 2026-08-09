#!/usr/bin/env python3
"""Parse one pinned 2017-era BEA HMI7 pair without relaxing later profiles.

This module accepts only the exact present-day sequence-25 capture bundle for
the 2017Q3 advance estimate.  Its result describes archive content.  It does
not establish the bytes served at the historical release time and cannot
admit a forecast origin, truth record, model input, or score.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import os
import posixpath
import re
import stat
import tempfile
import xml.etree.ElementTree as ET
import zipfile
import zlib
from dataclasses import asdict, dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Set, Tuple


MAIN_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
OFFICE_REL_NS = (
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
)
PACKAGE_REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"
CONTENT_TYPE_NS = "http://schemas.openxmlformats.org/package/2006/content-types"
XML_NS = "http://www.w3.org/XML/1998/namespace"
NS = {"m": MAIN_NS, "p": PACKAGE_REL_NS, "ct": CONTENT_TYPE_NS}
REL_ID_ATTRIBUTE = "{%s}id" % OFFICE_REL_NS
RELATIONSHIP_TAG = "{%s}Relationship" % PACKAGE_REL_NS
SHEET_TAG = "{%s}sheet" % MAIN_NS
SHARED_STRING_TAG = "{%s}si" % MAIN_NS
TEXT_TAG = "{%s}t" % MAIN_NS

SCHEMA_VERSION = "beforeit-us-bea-hmi7-2017-era-content-fingerprint.v1"
PARSER_VERSION = "beforeit-us-bea-hmi7-2017-era-ooxml-parser.v1"
PROFILE_ID = "bea_hmi7_2017q3_advance_shared_string_general.v1"
STATUS = "PRESENT_DAY_ARCHIVE_BYTES_PARSED_NONADMITTING_2017_ERA_PROFILE"
EVIDENCE_CLASS = "OFFICIAL_BEA_HMI7_PRESENT_DAY_ARCHIVE_SNAPSHOT"
CANONICALIZATION = "utf8_sorted_keys_compact_json_lf"
PAIR_HASH = "e46bf665a69799c3f98cd2dff29263fe30b8b616163f5f97281a0fc82b720ee9"
PAIR_HASH_DOMAIN = "beforeit-us-bea-hmi7-advance-present-day-pair.v1"
METADATA_CONTENT_SHA256 = (
    "186903041b649480b34a130f8c7518fb53a875e5b02ce4d6c3ee674080d5b824"
)
RECEIPT_SEMANTIC_SHA256 = (
    "1ed6435ae6be6a2a9e629bab2d0b3f3112117926cf3d365fac3e0dc1ef8b312d"
)
RECEIPT_FILE_SHA256 = (
    "56f99f2a5630226d94ce45cd111d5990c61b35069c9ed65bce2e0509af2b0d71"
)
RECEIPT_BYTE_COUNT = 8_065
RECEIPT_NAME = "receipt-self-sha256-%s.toml" % RECEIPT_SEMANTIC_SHA256
BUNDLE_NAME = "receipt-sha256-%s" % RECEIPT_SEMANTIC_SHA256
REFERENCE_START = "1947Q1"
REFERENCE_END = "2017Q3"
PREVIOUS_PERIOD = "2017Q2"
CURRENT_PERIOD = "2017Q3"
FIRST_CORE_NUMERIC_PERIOD = "1959Q1"
SOURCE_MISSING = "....."
TERMINAL_COLUMN = "JZ"
PREVIOUS_COLUMN = "JY"
RELEASE_EVENT_TIMESTAMP_UTC = "2017-10-27T12:30:00Z"
PRESENT_DAY_CAPTURE_INTERVAL_UTC = (
    "2026-08-07T22:20:19.781Z/2026-08-07T22:20:22.296Z"
)
EXPECTED_PROFILE_SHA256 = (
    "717566dfd4219a726c70acf0dc6a7600a3a8456e3dc5e227d1c023c0e2add82e"
)

HASH_PATTERN = re.compile(r"[0-9a-f]{64}\Z", re.ASCII)
CELL_PATTERN = re.compile(r"([A-Z]+)([1-9][0-9]*)\Z", re.ASCII)
CANONICAL_UINT_PATTERN = re.compile(r"(?:0|[1-9][0-9]*)\Z", re.ASCII)
GROUPED_INTEGER_PATTERN = re.compile(
    r"[1-9][0-9]{0,2}(?:,[0-9]{3})+\Z", re.ASCII
)
INDEX_DECIMAL_PATTERN = re.compile(r"[1-9][0-9]*\.[0-9]{3}\Z", re.ASCII)
REL_ID_PATTERN = re.compile(r"rId[1-9][0-9]*\Z", re.ASCII)
REL_TYPE_PATTERN = re.compile(
    r"http://schemas\.(?:openxmlformats\.org|microsoft\.com)/[^\s]+\Z",
    re.ASCII,
)
XLSX_MAGIC = b"PK\x03\x04"
MAX_ARCHIVE_MEMBERS = 512
MAX_MEMBER_BYTES = 32_000_000
MAX_TOTAL_UNCOMPRESSED_BYTES = 160_000_000

WORKSHEET_REL_TYPE = "%s/worksheet" % OFFICE_REL_NS
ALLOWED_RELATIONSHIP_TYPES = {
    "%s/extended-properties" % OFFICE_REL_NS,
    "%s/officeDocument" % OFFICE_REL_NS,
    "%s/worksheet" % OFFICE_REL_NS,
    "%s/sharedStrings" % OFFICE_REL_NS,
    "%s/styles" % OFFICE_REL_NS,
    "%s/theme" % OFFICE_REL_NS,
    "%s/customProperty" % OFFICE_REL_NS,
    "%s/metadata/core-properties" % PACKAGE_REL_NS,
}


class ProfileError(RuntimeError):
    """Raised when a pinned identity or closed-profile invariant fails."""


@dataclass(frozen=True)
class WorkbookSpec:
    workbook_id: str
    section_id: str
    object_name: str
    raw_sha256: str
    byte_count: int
    source_url: str
    expected_sheet_count: int
    expected_sheet_manifest_sha256: str
    expected_member_count: int
    expected_member_manifest_sha256: str
    expected_relationship_count: int
    expected_relationship_manifest_sha256: str
    expected_shared_string_count: int
    expected_shared_string_unique_count: int
    expected_shared_string_manifest_sha256: str
    data_published_text: str
    file_created_text: str
    http_last_modified: str


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
    lexical_class: str
    decimal_scale: int
    sheet_last_row: int
    first_numeric_period: str
    history_sha256: str
    previous_display: str
    current_display: str
    release_statement_1dp: Optional[str]


@dataclass(frozen=True)
class CellData:
    resolved_value: Optional[str]
    raw_value: Optional[str]
    style_index: int
    cell_type: Optional[str]
    has_formula: bool


WORKBOOK_SPECS = (
    WorkbookSpec(
        workbook_id="r2017q3_advance_section1_present_day",
        section_id="1",
        object_name=(
            "sha256-b6461337a1438e36a232d7b1a86fe3bf75df5c190f8b7900ad732c4fe56e03d5.xlsx"
        ),
        raw_sha256=(
            "b6461337a1438e36a232d7b1a86fe3bf75df5c190f8b7900ad732c4fe56e03d5"
        ),
        byte_count=4_311_139,
        source_url=(
            "https://apps.bea.gov/HistData/Files/Releases/GDP_and_PI/2017/Q3/"
            "Advance_October-27-2017/Section1all_xls.xlsx"
        ),
        expected_sheet_count=114,
        expected_sheet_manifest_sha256=(
            "1fbdcef3d8f84a981546e33263bdfd95e7c303a9aeb05fcf1a61fd6493254a7d"
        ),
        expected_member_count=351,
        expected_member_manifest_sha256=(
            "196ec833cb42ea1f08c28e1fcfd9c37a0a7eaa0de48e2d6a9efe3d1d4cbb9ae8"
        ),
        expected_relationship_count=234,
        expected_relationship_manifest_sha256=(
            "7ab06a74078da081333cc68e9c94521b6720b3d7367f0920d31b96b1096ee4af"
        ),
        expected_shared_string_count=546_249,
        expected_shared_string_unique_count=168_151,
        expected_shared_string_manifest_sha256=(
            "dd2cf26da442354e9be4072bd0347061e26056c5e15d68869c10513a3ff8a0de"
        ),
        data_published_text="Data published Oct 27 2017  8:30AM",
        file_created_text="File created Oct 26 2017  2:25PM",
        http_last_modified="Fri, 27 Oct 2017 17:34:50 GMT",
    ),
    WorkbookSpec(
        workbook_id="r2017q3_advance_section2_present_day",
        section_id="2",
        object_name=(
            "sha256-4cb8c738fdc1785a701be314ec2809e3e74628ea5b6aae6c1ccb783af286b1b0.xlsx"
        ),
        raw_sha256=(
            "4cb8c738fdc1785a701be314ec2809e3e74628ea5b6aae6c1ccb783af286b1b0"
        ),
        byte_count=2_155_367,
        source_url=(
            "https://apps.bea.gov/HistData/Files/Releases/GDP_and_PI/2017/Q3/"
            "Advance_October-27-2017/Section2all_xls.xlsx"
        ),
        expected_sheet_count=39,
        expected_sheet_manifest_sha256=(
            "c458880fda8d2ddd64d350b72bd6f9b49ad6192c482cd8529397980a1127cfdc"
        ),
        expected_member_count=126,
        expected_member_manifest_sha256=(
            "a19a5bcf7c37e053966f0755a2e2b5280c6d63cc93134483534eb61072b953b9"
        ),
        expected_relationship_count=84,
        expected_relationship_manifest_sha256=(
            "0342b1a944a8607e841f4ceb2b157150be85d066a510f385af0607d1eaa4cd04"
        ),
        expected_shared_string_count=240_335,
        expected_shared_string_unique_count=118_861,
        expected_shared_string_manifest_sha256=(
            "a74d1369270bdb4f872f4c014e0df8e56e6e2aea0245843bea02b0748870b83b"
        ),
        data_published_text="Data published Oct 27 2017  8:30AM",
        file_created_text="File created Oct 29 2017  1:23PM",
        http_last_modified="Tue, 31 Oct 2017 15:29:36 GMT",
    ),
)

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
        lexical_class="grouped_integer_saar_level",
        decimal_scale=0,
        sheet_last_row=35,
        first_numeric_period=REFERENCE_START,
        history_sha256=(
            "c4e0125883a42a487ecb418df7e6e8947719785490454f3a7e4f1585a7a8676b"
        ),
        previous_display="19,250,009",
        current_display="19,495,476",
        release_statement_1dp=None,
    ),
    TargetSpec(
        target_id="real_gdp",
        section_id="1",
        sheet_name="T10106-Q",
        table_number="1.1.6",
        table_title="Table 1.1.6. Real Gross Domestic Product, Chained Dollars",
        units_text=(
            "[Millions of chained (2009) dollars] "
            "Seasonally adjusted at annual rates"
        ),
        published_line_number=1,
        physical_row_number=9,
        source_concept_text="    Gross domestic product",
        normalized_concept="Gross domestic product",
        series_code="A191RX",
        seasonal_adjustment="seasonally_adjusted_annual_rate",
        unit="millions_of_chained_2009_dollars",
        base_year="2009",
        lexical_class="grouped_integer_saar_level",
        decimal_scale=0,
        sheet_last_row=37,
        first_numeric_period=REFERENCE_START,
        history_sha256=(
            "d1eca004c257eb4299460e1b92087292ec41a4aa6fb9c7f840602aedf2c44ddc"
        ),
        previous_display="17,031,085",
        current_display="17,156,946",
        release_statement_1dp="3.0",
    ),
    TargetSpec(
        target_id="gdp_deflator",
        section_id="1",
        sheet_name="T10109-Q",
        table_number="1.1.9",
        table_title=(
            "Table 1.1.9. Implicit Price Deflators for Gross Domestic Product"
        ),
        units_text="[Index numbers, 2009=100] Seasonally adjusted",
        published_line_number=1,
        physical_row_number=9,
        source_concept_text="    Gross domestic product",
        normalized_concept="Gross domestic product",
        series_code="A191RD",
        seasonal_adjustment="seasonally_adjusted",
        unit="index",
        base_year="2009",
        lexical_class="positive_index_decimal_3dp",
        decimal_scale=3,
        sheet_last_row=37,
        first_numeric_period=REFERENCE_START,
        history_sha256=(
            "a3a8c95292d45a0a085404764d1dba286656d9cf14467bcd95b3b9bbbfca186e"
        ),
        previous_display="113.029",
        current_display="113.630",
        release_statement_1dp=None,
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
        units_text="[Index numbers, 2009=100] Seasonally adjusted",
        published_line_number=1,
        physical_row_number=9,
        source_concept_text="    Personal consumption expenditures (PCE)",
        normalized_concept="Personal consumption expenditures (PCE)",
        series_code="DPCERG",
        seasonal_adjustment="seasonally_adjusted",
        unit="index",
        base_year="2009",
        lexical_class="positive_index_decimal_3dp",
        decimal_scale=3,
        sheet_last_row=44,
        first_numeric_period=REFERENCE_START,
        history_sha256=(
            "f292d4bbd3bbdce196404688b374e351a1147d0d88e14a409124d2896926da68"
        ),
        previous_display="112.273",
        current_display="112.693",
        release_statement_1dp="1.5",
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
        units_text="[Index numbers, 2009=100] Seasonally adjusted",
        published_line_number=25,
        physical_row_number=34,
        source_concept_text="  PCE excluding food and energy\\4\\",
        normalized_concept="PCE excluding food and energy",
        series_code="DPCCRG",
        seasonal_adjustment="seasonally_adjusted",
        unit="index",
        base_year="2009",
        lexical_class="positive_index_decimal_3dp",
        decimal_scale=3,
        sheet_last_row=44,
        first_numeric_period=FIRST_CORE_NUMERIC_PERIOD,
        history_sha256=(
            "737372566d6a0f74506c27aa0ea8a12e1cbe7c8f1eec01961c4fdba21e431ddd"
        ),
        previous_display="112.847",
        current_display="113.217",
        release_statement_1dp="1.3",
    ),
)

WORKBOOK_BY_SECTION = {item.section_id: item for item in WORKBOOK_SPECS}
TARGET_BY_ID = {item.target_id: item for item in TARGET_SPECS}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


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


def false_gates() -> Dict[str, bool]:
    return {
        "historical_first_state_verified": False,
        "historical_availability_verified": False,
        "intraday_availability_verified": False,
        "strict_origin_admissible": False,
        "origin_admissible": False,
        "target_admissible": False,
        "truth_admissible": False,
        "model_input_allowed": False,
        "forecast_execution_allowed": False,
        "empirical_execution_allowed": False,
        "production_scoring_allowed": False,
        "score_allowed": False,
        "promotion_eligible": False,
        "inventory_mutation_authorized": False,
        "production_authorized": False,
        "ready": False,
    }


def profile_payload() -> Dict[str, Any]:
    return {
        "profile_id": PROFILE_ID,
        "status": STATUS,
        "evidence_class": EVIDENCE_CLASS,
        "receipt_semantic_sha256": RECEIPT_SEMANTIC_SHA256,
        "receipt_file_sha256": RECEIPT_FILE_SHA256,
        "raw_pair_sha256": PAIR_HASH,
        "metadata_content_sha256": METADATA_CONTENT_SHA256,
        "reference_start": REFERENCE_START,
        "reference_end": REFERENCE_END,
        "terminal_column": TERMINAL_COLUMN,
        "source_missing_token": SOURCE_MISSING,
        "workbooks": [asdict(item) for item in WORKBOOK_SPECS],
        "targets": [asdict(item) for item in TARGET_SPECS],
        "gates": false_gates(),
    }


def profile_sha256() -> str:
    return sha256_bytes(canonical_json_bytes(profile_payload()))


def _hash_field(buffer: bytearray, name: str, value: Any) -> None:
    name_bytes = name.encode("utf-8")
    value_bytes = str(value).encode("utf-8")
    buffer.extend(str(len(name_bytes)).encode("ascii"))
    buffer.extend(b":")
    buffer.extend(name_bytes)
    buffer.extend(str(len(value_bytes)).encode("ascii"))
    buffer.extend(b":")
    buffer.extend(value_bytes)


def expected_pair_sha256() -> str:
    buffer = bytearray()
    _hash_field(buffer, "domain", PAIR_HASH_DOMAIN)
    _hash_field(buffer, "metadata_content_sha256", METADATA_CONTENT_SHA256)
    _hash_field(buffer, "sequence", 25)
    _hash_field(buffer, "reference_period", "2017Q3")
    for index, workbook in enumerate(WORKBOOK_SPECS, start=1):
        _hash_field(buffer, "workbook_index", index)
        _hash_field(buffer, "section_id", workbook.section_id)
        _hash_field(buffer, "source_url", workbook.source_url)
        _hash_field(buffer, "raw_sha256", workbook.raw_sha256)
        _hash_field(buffer, "raw_byte_count", workbook.byte_count)
    return sha256_bytes(bytes(buffer))


def _validate_profile() -> None:
    if len(WORKBOOK_SPECS) != 2 or tuple(
        item.section_id for item in WORKBOOK_SPECS
    ) != ("1", "2"):
        raise ProfileError("profile must contain ordered Section1 and Section2")
    if len(TARGET_SPECS) != 5 or len(TARGET_BY_ID) != 5:
        raise ProfileError("profile must contain exactly five unique targets")
    for workbook in WORKBOOK_SPECS:
        for digest in (
            workbook.raw_sha256,
            workbook.expected_sheet_manifest_sha256,
            workbook.expected_member_manifest_sha256,
            workbook.expected_relationship_manifest_sha256,
            workbook.expected_shared_string_manifest_sha256,
        ):
            if HASH_PATTERN.fullmatch(digest) is None:
                raise ProfileError("workbook profile contains an unfrozen digest")
    for target in TARGET_SPECS:
        if HASH_PATTERN.fullmatch(target.history_sha256) is None:
            raise ProfileError("target profile contains an invalid history digest")
        if target.section_id not in WORKBOOK_BY_SECTION:
            raise ProfileError("target profile references an unknown section")
    if expected_pair_sha256() != PAIR_HASH:
        raise ProfileError("raw pair SHA-256 does not rederive from pinned inputs")
    if profile_sha256() != EXPECTED_PROFILE_SHA256:
        raise ProfileError("2017-era profile SHA-256 drifted")


def column_number(name: str) -> int:
    if re.fullmatch(r"[A-Z]+", name, re.ASCII) is None:
        raise ProfileError("invalid Excel column name: %r" % name)
    result = 0
    for character in name:
        result = result * 26 + ord(character) - ord("A") + 1
    return result


def column_name(number: int) -> str:
    if number < 1:
        raise ProfileError("Excel column number must be positive")
    characters: List[str] = []
    while number:
        number, remainder = divmod(number - 1, 26)
        characters.append(chr(ord("A") + remainder))
    return "".join(reversed(characters))


def quarter_sequence(start: str, end: str) -> List[str]:
    pattern = re.compile(r"([0-9]{4})Q([1-4])\Z", re.ASCII)
    start_match = pattern.fullmatch(start)
    end_match = pattern.fullmatch(end)
    if start_match is None or end_match is None:
        raise ProfileError("quarter bounds must use YYYYQ[1-4]")
    start_index = int(start_match[1]) * 4 + int(start_match[2]) - 1
    end_index = int(end_match[1]) * 4 + int(end_match[2]) - 1
    if start_index > end_index:
        raise ProfileError("quarter bounds are reversed")
    return [
        "%dQ%d" % (index // 4, index % 4 + 1)
        for index in range(start_index, end_index + 1)
    ]


def _parse_xml(data: bytes, location: str) -> ET.Element:
    upper = data[:4096].upper()
    if b"<!DOCTYPE" in upper or b"<!ENTITY" in upper:
        raise ProfileError("%s contains a forbidden XML declaration" % location)
    try:
        return ET.fromstring(data)
    except ET.ParseError as error:
        raise ProfileError("%s is malformed XML" % location) from error


def _canonical_uint(value: str, location: str) -> int:
    if CANONICAL_UINT_PATTERN.fullmatch(value) is None:
        raise ProfileError("%s is not a canonical unsigned integer" % location)
    return int(value)


def _normalized_member_name(name: str) -> str:
    if not name or "\x00" in name or "\\" in name or name.endswith("/"):
        raise ProfileError("ZIP member name is unsafe")
    path = PurePosixPath(name)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        raise ProfileError("ZIP member path is unsafe: %r" % name)
    if str(path) != name:
        raise ProfileError("ZIP member path is not canonical: %r" % name)
    return name


def validate_zip_members(archive: zipfile.ZipFile) -> Tuple[Set[str], str]:
    infos = archive.infolist()
    if not infos or len(infos) > MAX_ARCHIVE_MEMBERS:
        raise ProfileError("ZIP member count is outside the allowed range")
    names: Set[str] = set()
    folded_names: Set[str] = set()
    total = 0
    manifest = bytearray()
    for index, info in enumerate(infos, start=1):
        name = _normalized_member_name(info.filename)
        folded = name.casefold()
        if name in names or folded in folded_names:
            raise ProfileError("ZIP member alias or duplicate: %s" % name)
        names.add(name)
        folded_names.add(folded)
        if info.flag_bits & 0x1:
            raise ProfileError("encrypted ZIP members are forbidden")
        if info.compress_type not in {zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED}:
            raise ProfileError("unsupported ZIP compression method")
        mode = (info.external_attr >> 16) & 0xFFFF
        if stat.S_IFMT(mode) == stat.S_IFLNK:
            raise ProfileError("ZIP symbolic-link members are forbidden")
        if info.file_size < 0 or info.file_size > MAX_MEMBER_BYTES:
            raise ProfileError("ZIP member is too large")
        total += info.file_size
        if total > MAX_TOTAL_UNCOMPRESSED_BYTES:
            raise ProfileError("ZIP uncompressed size limit exceeded")
        line = "%d\t%s\t%08x\t%d\t%d\t%d\t%d\n" % (
            index,
            name,
            info.CRC,
            info.file_size,
            info.compress_size,
            info.compress_type,
            info.flag_bits,
        )
        manifest.extend(line.encode("utf-8"))
    return names, sha256_bytes(bytes(manifest))


def _relationship_source(rel_part: str, members: Set[str]) -> str:
    if rel_part == "_rels/.rels":
        return ""
    marker = "/_rels/"
    if marker not in rel_part or not rel_part.endswith(".rels"):
        raise ProfileError("relationship part path is malformed")
    prefix, basename = rel_part.split(marker, 1)
    if "/" in basename or basename == ".rels":
        raise ProfileError("relationship part path is malformed")
    source = "%s/%s" % (prefix, basename[:-5])
    if source not in members:
        raise ProfileError("relationship source part is absent")
    return source


def _resolve_relationship_target(source: str, target: str) -> str:
    if (
        not target
        or target != target.strip()
        or "\\" in target
        or "\x00" in target
        or "?" in target
        or "#" in target
        or "%" in target
        or ":" in target
        or target.startswith("/")
    ):
        raise ProfileError("relationship target is unsafe")
    base = posixpath.dirname(source)
    resolved = posixpath.normpath(posixpath.join(base, target))
    if resolved in {"", ".", ".."} or resolved.startswith("../"):
        raise ProfileError("relationship target escapes the package")
    _normalized_member_name(resolved)
    return resolved


def validate_relationships(
    archive: zipfile.ZipFile,
    members: Set[str],
) -> Tuple[Dict[Tuple[str, str], Dict[str, str]], int, str]:
    rel_parts = sorted(name for name in members if name.endswith(".rels"))
    records: Dict[Tuple[str, str], Dict[str, str]] = {}
    manifest = bytearray()
    count = 0
    for rel_part in rel_parts:
        source = _relationship_source(rel_part, members)
        root = _parse_xml(archive.read(rel_part), rel_part)
        if root.tag != "{%s}Relationships" % PACKAGE_REL_NS or root.attrib:
            raise ProfileError("relationship root drifted in %s" % rel_part)
        seen_ids: Set[str] = set()
        for index, node in enumerate(list(root), start=1):
            if node.tag != RELATIONSHIP_TAG or list(node) or node.text:
                raise ProfileError("relationship entry is malformed")
            if set(node.attrib) != {"Id", "Type", "Target"}:
                raise ProfileError("relationship attributes drifted")
            relationship_id = node.attrib["Id"]
            relationship_type = node.attrib["Type"]
            target = node.attrib["Target"]
            if REL_ID_PATTERN.fullmatch(relationship_id) is None:
                raise ProfileError("relationship ID is noncanonical")
            if relationship_id in seen_ids:
                raise ProfileError("duplicate relationship ID")
            seen_ids.add(relationship_id)
            if (
                REL_TYPE_PATTERN.fullmatch(relationship_type) is None
                or relationship_type not in ALLOWED_RELATIONSHIP_TYPES
            ):
                raise ProfileError("relationship type is outside the profile")
            resolved = _resolve_relationship_target(source, target)
            if resolved not in members:
                raise ProfileError("relationship target is absent: %s" % resolved)
            key = (rel_part, relationship_id)
            if key in records:
                raise ProfileError("duplicate relationship identity")
            records[key] = {
                "source": source,
                "type": relationship_type,
                "target": target,
                "resolved": resolved,
            }
            manifest.extend(
                ("%s\t%d\t%s\t%s\t%s\t%s\n" % (
                    rel_part,
                    index,
                    relationship_id,
                    relationship_type,
                    target,
                    resolved,
                )).encode("utf-8")
            )
            count += 1
    if "_rels/.rels" not in rel_parts or "xl/_rels/workbook.xml.rels" not in rel_parts:
        raise ProfileError("required package relationships are absent")
    return records, count, sha256_bytes(bytes(manifest))


def validate_content_types(archive: zipfile.ZipFile, members: Set[str]) -> None:
    path = "[Content_Types].xml"
    root = _parse_xml(archive.read(path), path)
    if root.tag != "{%s}Types" % CONTENT_TYPE_NS or root.attrib:
        raise ProfileError("content-types root drifted")
    defaults: Dict[str, str] = {}
    overrides: Dict[str, str] = {}
    for node in list(root):
        local = node.tag.rsplit("}", 1)[-1]
        if list(node) or node.text:
            raise ProfileError("content-type entry is malformed")
        if local == "Default" and node.tag == "{%s}Default" % CONTENT_TYPE_NS:
            if set(node.attrib) != {"Extension", "ContentType"}:
                raise ProfileError("default content type attributes drifted")
            extension = node.attrib["Extension"]
            if not extension or extension != extension.lower() or extension in defaults:
                raise ProfileError("default content type is duplicated or invalid")
            defaults[extension] = node.attrib["ContentType"]
        elif local == "Override" and node.tag == "{%s}Override" % CONTENT_TYPE_NS:
            if set(node.attrib) != {"PartName", "ContentType"}:
                raise ProfileError("override content type attributes drifted")
            part_name = node.attrib["PartName"]
            if not part_name.startswith("/") or part_name == "/":
                raise ProfileError("override part name is invalid")
            member = _normalized_member_name(part_name[1:])
            folded = member.casefold()
            if folded in overrides:
                raise ProfileError("override content type is duplicated or aliased")
            if member not in members:
                raise ProfileError("content type references an absent part")
            if member == "xl/workbook.xml":
                expected_type = (
                    "application/vnd.openxmlformats-officedocument."
                    "spreadsheetml.sheet.main+xml"
                )
            elif re.fullmatch(r"xl/worksheets/sheet[1-9][0-9]*\.xml", member):
                expected_type = (
                    "application/vnd.openxmlformats-officedocument."
                    "spreadsheetml.worksheet+xml"
                )
            elif member == "xl/theme/theme1.xml":
                expected_type = (
                    "application/vnd.openxmlformats-officedocument.theme+xml"
                )
            elif member == "xl/styles.xml":
                expected_type = (
                    "application/vnd.openxmlformats-officedocument."
                    "spreadsheetml.styles+xml"
                )
            elif member == "xl/sharedStrings.xml":
                expected_type = (
                    "application/vnd.openxmlformats-officedocument."
                    "spreadsheetml.sharedStrings+xml"
                )
            elif member == "docProps/core.xml":
                expected_type = "application/vnd.openxmlformats-package.core-properties+xml"
            elif member == "docProps/app.xml":
                expected_type = (
                    "application/vnd.openxmlformats-officedocument."
                    "extended-properties+xml"
                )
            else:
                raise ProfileError("override part is outside the closed profile")
            if node.attrib["ContentType"] != expected_type:
                raise ProfileError("override content type drifted")
            overrides[folded] = expected_type
        else:
            raise ProfileError("unsupported content-type entry")
    if defaults != {
        "bin": "application/vnd.openxmlformats-officedocument.spreadsheetml.customProperty",
        "rels": "application/vnd.openxmlformats-package.relationships+xml",
        "xml": "application/xml",
    }:
        raise ProfileError("default content-type profile drifted")
    expected_override_members = {
        member.casefold()
        for member in members
        if member
        in {
            "xl/workbook.xml",
            "xl/theme/theme1.xml",
            "xl/styles.xml",
            "xl/sharedStrings.xml",
            "docProps/core.xml",
            "docProps/app.xml",
        }
        or re.fullmatch(r"xl/worksheets/sheet[1-9][0-9]*\.xml", member)
    }
    if set(overrides) != expected_override_members:
        raise ProfileError("override content-type coverage drifted")
    for member in members:
        if member == path:
            continue
        extension = member.rsplit(".", 1)[-1].lower() if "." in member else ""
        if member.casefold() not in overrides and extension not in defaults:
            raise ProfileError("package part lacks a content type: %s" % member)


def workbook_sheets(
    archive: zipfile.ZipFile,
    relationship_records: Mapping[Tuple[str, str], Mapping[str, str]],
) -> List[Tuple[str, str]]:
    path = "xl/workbook.xml"
    root = _parse_xml(archive.read(path), path)
    sheets_node = root.find("m:sheets", NS)
    if sheets_node is None:
        raise ProfileError("workbook sheet collection is absent")
    result: List[Tuple[str, str]] = []
    names: Set[str] = set()
    folded_names: Set[str] = set()
    targets: Set[str] = set()
    ids: Set[int] = set()
    used_relationships: Set[str] = set()
    rel_part = "xl/_rels/workbook.xml.rels"
    for node in list(sheets_node):
        if node.tag != SHEET_TAG or set(node.attrib) != {"name", "sheetId", REL_ID_ATTRIBUTE}:
            raise ProfileError("workbook sheet identity attributes drifted")
        name = node.attrib["name"]
        if not name or name != name.strip():
            raise ProfileError("workbook sheet name is invalid")
        folded = name.casefold()
        if name in names or folded in folded_names:
            raise ProfileError("workbook sheet name is duplicated or aliased")
        sheet_id = _canonical_uint(node.attrib["sheetId"], "sheetId")
        if sheet_id < 1 or sheet_id in ids:
            raise ProfileError("workbook sheetId is duplicated or invalid")
        relationship_id = node.attrib[REL_ID_ATTRIBUTE]
        record = relationship_records.get((rel_part, relationship_id))
        if record is None or record["type"] != WORKSHEET_REL_TYPE:
            raise ProfileError("sheet relationship is absent or has the wrong type")
        target = record["resolved"]
        if target in targets:
            raise ProfileError("worksheet relationship target is aliased")
        names.add(name)
        folded_names.add(folded)
        ids.add(sheet_id)
        targets.add(target)
        used_relationships.add(relationship_id)
        result.append((name, target))
    worksheet_relationships = {
        key[1]
        for key, value in relationship_records.items()
        if key[0] == rel_part and value["type"] == WORKSHEET_REL_TYPE
    }
    if not result or used_relationships != worksheet_relationships:
        raise ProfileError("workbook worksheet relationships are not bijective")
    return result


def sheet_manifest_sha256(sheets: Iterable[Tuple[str, str]]) -> str:
    payload = "".join(
        "%d\t%s\t%s\n" % (index, name, target)
        for index, (name, target) in enumerate(sheets, start=1)
    ).encode("utf-8")
    return sha256_bytes(payload)


def parse_shared_strings(
    archive: zipfile.ZipFile,
    spec: WorkbookSpec,
) -> Tuple[List[str], str]:
    path = "xl/sharedStrings.xml"
    root = _parse_xml(archive.read(path), path)
    if root.tag != "{%s}sst" % MAIN_NS:
        raise ProfileError("shared-string root drifted")
    if set(root.attrib) != {"count", "uniqueCount"}:
        raise ProfileError("shared-string count attributes drifted")
    count = _canonical_uint(root.attrib["count"], "sharedStrings.count")
    unique_count = _canonical_uint(
        root.attrib["uniqueCount"], "sharedStrings.uniqueCount"
    )
    strings: List[str] = []
    manifest = bytearray()
    for index, item in enumerate(list(root)):
        if item.tag != SHARED_STRING_TAG or item.attrib or len(item) != 1:
            raise ProfileError("shared-string item is outside the closed profile")
        text_node = item[0]
        if text_node.tag != TEXT_TAG or list(text_node):
            raise ProfileError("shared-string text is outside the closed profile")
        if set(text_node.attrib) not in (set(), {"{%s}space" % XML_NS}):
            raise ProfileError("shared-string text attributes drifted")
        if text_node.attrib and text_node.attrib["{%s}space" % XML_NS] != "preserve":
            raise ProfileError("shared-string xml:space value drifted")
        value = text_node.text or ""
        if (value.startswith(" ") or value.endswith(" ")) and not text_node.attrib:
            raise ProfileError("shared-string boundary whitespace lacks xml:space")
        strings.append(value)
        encoded = value.encode("utf-8")
        manifest.extend(("%d\t%d\t" % (index, len(encoded))).encode("ascii"))
        manifest.extend(encoded)
        manifest.extend(b"\n")
    if count != spec.expected_shared_string_count:
        raise ProfileError("shared-string total count drifted")
    if unique_count != spec.expected_shared_string_unique_count:
        raise ProfileError("shared-string unique count drifted")
    if unique_count != len(strings):
        raise ProfileError("shared-string uniqueCount disagrees with the table")
    return strings, sha256_bytes(bytes(manifest))


def validate_styles(archive: zipfile.ZipFile) -> List[str]:
    path = "xl/styles.xml"
    root = _parse_xml(archive.read(path), path)
    cell_xfs = root.find("m:cellXfs", NS)
    if cell_xfs is None or cell_xfs.attrib != {"count": "2"}:
        raise ProfileError("cellXfs count drifted")
    styles = list(cell_xfs)
    expected = (
        (
            {"numFmtId": "0", "fontId": "0", "fillId": "0", "borderId": "0", "xfId": "0"},
            [],
        ),
        (
            {
                "numFmtId": "0",
                "fontId": "0",
                "fillId": "0",
                "borderId": "0",
                "xfId": "0",
                "applyAlignment": "1",
            },
            [("{%s}alignment" % MAIN_NS, {"horizontal": "right"})],
        ),
    )
    if len(styles) != len(expected):
        raise ProfileError("cell style count drifted")
    for index, (style, (expected_attributes, expected_children)) in enumerate(
        zip(styles, expected)
    ):
        if style.tag != "{%s}xf" % MAIN_NS or style.attrib != expected_attributes:
            raise ProfileError("style %d is outside the 2017 profile" % index)
        children = [(child.tag, child.attrib) for child in list(style)]
        if children != expected_children or any(list(child) for child in list(style)):
            raise ProfileError("style %d children drifted" % index)
    return ["General", "General"]


def _cell_value(
    cell: ET.Element,
    strings: Sequence[str],
    location: str,
) -> Tuple[Optional[str], Optional[str]]:
    values = cell.findall("m:v", NS)
    if len(values) > 1:
        raise ProfileError("%s contains duplicate value nodes" % location)
    raw_value = None if not values else (values[0].text or "")
    cell_type = cell.attrib.get("t")
    if cell_type == "s":
        if raw_value is None:
            raise ProfileError("%s shared-string cell has no index" % location)
        index = _canonical_uint(raw_value, "%s shared-string index" % location)
        if index >= len(strings):
            raise ProfileError("%s shared-string index is out of range" % location)
        return strings[index], raw_value
    if cell_type in {None, "n"}:
        return raw_value, raw_value
    if cell_type == "e":
        raise ProfileError("%s contains an error cell" % location)
    raise ProfileError("%s uses an unsupported cell type" % location)


def sheet_cells(
    archive: zipfile.ZipFile,
    sheet_path: str,
    strings: Sequence[str],
) -> Tuple[str, Dict[str, CellData]]:
    root = _parse_xml(archive.read(sheet_path), sheet_path)
    if root.tag != "{%s}worksheet" % MAIN_NS:
        raise ProfileError("worksheet root drifted")
    dimension = root.find("m:dimension", NS)
    if dimension is None or set(dimension.attrib) != {"ref"}:
        raise ProfileError("worksheet dimension is absent or malformed")
    dimension_ref = dimension.attrib["ref"]
    dimension_match = re.fullmatch(
        r"A1:([A-Z]+)([1-9][0-9]*)\Z", dimension_ref, re.ASCII
    )
    if dimension_match is None:
        raise ProfileError("worksheet dimension is outside the closed profile")
    max_column = column_number(dimension_match[1])
    max_row = int(dimension_match[2])
    sheet_data = root.find("m:sheetData", NS)
    if sheet_data is None:
        raise ProfileError("worksheet sheetData is absent")
    result: Dict[str, CellData] = {}
    previous_row = 0
    for row in list(sheet_data):
        if row.tag != "{%s}row" % MAIN_NS or "r" not in row.attrib:
            raise ProfileError("worksheet row identity is invalid")
        row_number = _canonical_uint(row.attrib["r"], "worksheet row")
        if row_number < 1 or row_number <= previous_row or row_number > max_row:
            raise ProfileError("worksheet rows are duplicated, unordered, or out of bounds")
        previous_row = row_number
        previous_column = 0
        for cell in list(row):
            if cell.tag != "{%s}c" % MAIN_NS:
                raise ProfileError("worksheet row contains a non-cell child")
            reference = cell.attrib.get("r")
            match = CELL_PATTERN.fullmatch(reference or "")
            if match is None or int(match[2]) != row_number:
                raise ProfileError("worksheet contains an invalid cell address")
            column = column_number(match[1])
            if column <= previous_column or column > max_column or reference in result:
                raise ProfileError("worksheet cells are duplicated, unordered, or out of bounds")
            previous_column = column
            style_text = cell.attrib.get("s", "0")
            style_index = _canonical_uint(style_text, "%s style index" % reference)
            if style_index > 1:
                raise ProfileError("%s style index is outside the profile" % reference)
            formulas = cell.findall("m:f", NS)
            if formulas:
                raise ProfileError("%s contains a formula" % reference)
            resolved, raw = _cell_value(cell, strings, reference)
            result[reference] = CellData(
                resolved_value=resolved,
                raw_value=raw,
                style_index=style_index,
                cell_type=cell.attrib.get("t"),
                has_formula=False,
            )
    return dimension_ref, result


def required_shared_text(
    cells: Mapping[str, CellData],
    address: str,
    expected_style: int,
) -> str:
    cell = cells.get(address)
    if cell is None or cell.resolved_value is None:
        raise ProfileError("required cell %s is empty or absent" % address)
    if cell.cell_type != "s" or cell.style_index != expected_style or cell.has_formula:
        raise ProfileError("required cell %s type/style/formula profile drifted" % address)
    return cell.resolved_value


def parse_canonical_number(value: str, target: TargetSpec, address: str) -> Dict[str, str]:
    if target.lexical_class == "grouped_integer_saar_level":
        if GROUPED_INTEGER_PATTERN.fullmatch(value) is None:
            raise ProfileError("%s is not an exact grouped positive integer" % address)
        ungrouped = value.replace(",", "")
        if len(ungrouped) < 4 or format(int(ungrouped), ",d") != value:
            raise ProfileError("%s comma grouping is noncanonical" % address)
        coefficient = ungrouped
        canonical = ungrouped
    elif target.lexical_class == "positive_index_decimal_3dp":
        if INDEX_DECIMAL_PATTERN.fullmatch(value) is None:
            raise ProfileError("%s is not an exact positive 3-decimal index" % address)
        whole, fraction = value.split(".")
        coefficient = whole + fraction
        canonical = value
    else:
        raise ProfileError("unsupported numeric lexical class")
    if CANONICAL_UINT_PATTERN.fullmatch(coefficient) is None or int(coefficient) <= 0:
        raise ProfileError("%s canonical coefficient is invalid" % address)
    return {
        "canonical_decimal": canonical,
        "coefficient": coefficient,
        "scale": str(target.decimal_scale),
    }


def history_digest(periods: Sequence[str], values: Sequence[str]) -> str:
    if len(periods) != len(values):
        raise ProfileError("history period/value lengths differ")
    payload = "".join(
        "%s\t%s\n" % (period, value)
        for period, value in zip(periods, values)
    ).encode("utf-8")
    return sha256_bytes(payload)


def _rounded_ratio(numerator: int, denominator: int, digits: int) -> str:
    if denominator <= 0 or digits < 0:
        raise ProfileError("invalid exact-ratio rounding request")
    sign = "-" if numerator < 0 else ""
    scaled = abs(numerator) * (10 ** digits)
    quotient, remainder = divmod(scaled, denominator)
    if remainder * 2 >= denominator:
        quotient += 1
    if digits == 0:
        return sign + str(quotient)
    whole, fraction = divmod(quotient, 10 ** digits)
    return "%s%d.%0*d" % (sign, whole, digits, fraction)


def _group_decimal_whole(value: str) -> str:
    if re.fullmatch(r"[0-9]+\.[0-9]+", value, re.ASCII) is None:
        raise ProfileError("decimal grouping input is noncanonical")
    whole, fraction = value.split(".")
    return "%s.%s" % (format(int(whole), ",d"), fraction)


def annualized_percent_change(
    previous: Mapping[str, str],
    current: Mapping[str, str],
) -> Dict[str, str]:
    if previous["scale"] != current["scale"]:
        raise ProfileError("annualized change inputs have unequal scales")
    previous_coefficient = int(previous["coefficient"])
    current_coefficient = int(current["coefficient"])
    numerator = 100 * (current_coefficient ** 4 - previous_coefficient ** 4)
    denominator = previous_coefficient ** 4
    divisor = math.gcd(abs(numerator), denominator)
    reduced_numerator = numerator // divisor
    reduced_denominator = denominator // divisor
    return {
        "formula": "100*((current_level/previous_level)^4-1)",
        "exact_ratio_numerator": str(reduced_numerator),
        "exact_ratio_denominator": str(reduced_denominator),
        "rounded_decimal_12dp": _rounded_ratio(numerator, denominator, 12),
        "rounded_release_statement_1dp": _rounded_ratio(numerator, denominator, 1),
    }


def _expected_headers(target: TargetSpec, workbook: WorkbookSpec) -> Dict[str, str]:
    row = target.physical_row_number
    return {
        "A1": target.table_title,
        "A2": target.units_text,
        "A3": "Quarterly data from 1947Q1 to 2017Q3",
        "A4": "Bureau of Economic Analysis",
        "A5": workbook.data_published_text,
        "A6": workbook.file_created_text,
        "A8": "Line",
        "A%d" % row: str(target.published_line_number),
        "B%d" % row: target.source_concept_text,
        "C%d" % row: target.series_code,
    }


def _target_record(
    target: TargetSpec,
    workbook: WorkbookSpec,
    dimension: str,
    cells: Mapping[str, CellData],
) -> Dict[str, Any]:
    for address, expected in _expected_headers(target, workbook).items():
        actual = required_shared_text(cells, address, 0)
        if actual != expected:
            raise ProfileError("%s mapping/header drifted at %s" % (target.target_id, address))
    expected_dimension = "A1:%s%d" % (TERMINAL_COLUMN, target.sheet_last_row)
    if dimension != expected_dimension:
        raise ProfileError("%s worksheet dimension drifted" % target.target_id)

    periods = quarter_sequence(REFERENCE_START, REFERENCE_END)
    if len(periods) != 283:
        raise ProfileError("2017 profile period count drifted")
    first_numeric_index = periods.index(target.first_numeric_period)
    observations: List[Dict[str, Any]] = []
    display_values: List[str] = []
    for offset, period in enumerate(periods):
        column = column_name(column_number("D") + offset)
        header_address = "%s8" % column
        if required_shared_text(cells, header_address, 0) != period:
            raise ProfileError(
                "%s period axis drifted at %s" % (target.target_id, header_address)
            )
        address = "%s%d" % (column, target.physical_row_number)
        display = required_shared_text(cells, address, 1)
        display_values.append(display)
        if offset < first_numeric_index:
            if display != SOURCE_MISSING:
                raise ProfileError(
                    "%s pre-history state drifted at %s" % (target.target_id, address)
                )
            source_state = "SOURCE_MISSING"
            canonical_number = None
        else:
            if display == SOURCE_MISSING:
                raise ProfileError(
                    "%s numeric history is incomplete at %s" % (target.target_id, address)
                )
            source_state = "OBSERVED"
            canonical_number = parse_canonical_number(display, target, address)
        observations.append(
            {
                "period": period,
                "source_cell": "%s!%s" % (target.sheet_name, address),
                "source_state": source_state,
                "source_display_text": display,
                "canonical_number": canonical_number,
            }
        )
    digest = history_digest(periods, display_values)
    if digest != target.history_sha256:
        raise ProfileError("%s complete history digest drifted" % target.target_id)
    if display_values[-2:] != [target.previous_display, target.current_display]:
        raise ProfileError("%s Q2/Q3 displayed values drifted" % target.target_id)
    previous_number = observations[-2]["canonical_number"]
    current_number = observations[-1]["canonical_number"]
    if previous_number is None or current_number is None:
        raise ProfileError("terminal annualization inputs are missing")
    annualized = annualized_percent_change(previous_number, current_number)
    if target.release_statement_1dp is None:
        semantic_check: Dict[str, Any] = {
            "performed": False,
            "reason": "NO_ROUNDED_RELEASE_STATEMENT_PINNED_FOR_THIS_TARGET",
            "origin_evidence": False,
        }
    else:
        actual_statement = annualized["rounded_release_statement_1dp"]
        if actual_statement != target.release_statement_1dp:
            raise ProfileError("%s release-statement cross-check failed" % target.target_id)
        semantic_check = {
            "performed": True,
            "expected_release_statement_1dp": target.release_statement_1dp,
            "computed_release_statement_1dp": actual_statement,
            "matches": True,
            "role": "NON_ORIGIN_SEMANTIC_CHECK_ONLY",
            "origin_evidence": False,
        }
    missing_count = sum(item["source_state"] == "SOURCE_MISSING" for item in observations)
    return {
        "status": STATUS,
        "target_id": target.target_id,
        "workbook_id": workbook.workbook_id,
        "raw_sha256": workbook.raw_sha256,
        "section_id": target.section_id,
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
        "storage_profile": {
            "cell_type": "s",
            "style_index": 1,
            "number_format": "General",
            "lexical_class": target.lexical_class,
            "decimal_scale": target.decimal_scale,
            "source_missing_token": SOURCE_MISSING,
        },
        "reference_period_start": periods[0],
        "reference_period_end": periods[-1],
        "reference_period_count": len(periods),
        "first_numeric_period": target.first_numeric_period,
        "observed_value_count": len(periods) - missing_count,
        "source_missing_count": missing_count,
        "history_display_sha256": digest,
        "previous_quarter": observations[-2],
        "current_quarter": observations[-1],
        "annualized_percent_change": annualized,
        "release_statement_cross_check": semantic_check,
        "observations": observations,
        "gates": false_gates(),
    }


def _critical_sheet_names(section_id: str) -> Set[str]:
    return {
        target.sheet_name for target in TARGET_SPECS if target.section_id == section_id
    }


def _parse_workbook_bytes(
    data: bytes,
    spec: WorkbookSpec,
    *,
    enforce_pinned_manifests: bool,
) -> Tuple[Dict[str, Any], List[Dict[str, Any]]]:
    if data[:4] != XLSX_MAGIC:
        raise ProfileError("%s lacks OOXML ZIP magic" % spec.workbook_id)
    try:
        context = zipfile.ZipFile(io.BytesIO(data), "r")
    except (OSError, zipfile.BadZipFile) as error:
        raise ProfileError("workbook is not a valid ZIP archive") from error
    with context as archive:
        members, member_manifest = validate_zip_members(archive)
        required = {
            "[Content_Types].xml",
            "_rels/.rels",
            "xl/workbook.xml",
            "xl/_rels/workbook.xml.rels",
            "xl/styles.xml",
            "xl/sharedStrings.xml",
        }
        missing = sorted(required - members)
        if missing:
            raise ProfileError("workbook lacks required OOXML parts: %s" % missing)
        try:
            corrupt = archive.testzip()
        except (zipfile.BadZipFile, RuntimeError, EOFError, zlib.error) as error:
            raise ProfileError("workbook ZIP CRC/decompression validation failed") from error
        if corrupt is not None:
            raise ProfileError("workbook has corrupt ZIP member: %s" % corrupt)
        if len(members) != spec.expected_member_count:
            raise ProfileError("workbook ZIP member count drifted")
        if enforce_pinned_manifests and member_manifest != spec.expected_member_manifest_sha256:
            raise ProfileError("workbook ZIP member manifest drifted")

        validate_content_types(archive, members)
        relationships, relationship_count, relationship_manifest = validate_relationships(
            archive, members
        )
        if relationship_count != spec.expected_relationship_count:
            raise ProfileError("workbook relationship count drifted")
        if (
            enforce_pinned_manifests
            and relationship_manifest != spec.expected_relationship_manifest_sha256
        ):
            raise ProfileError("workbook relationship manifest drifted")

        sheets = workbook_sheets(archive, relationships)
        if len(sheets) != spec.expected_sheet_count:
            raise ProfileError("workbook sheet count drifted")
        sheet_manifest = sheet_manifest_sha256(sheets)
        if sheet_manifest != spec.expected_sheet_manifest_sha256:
            raise ProfileError("workbook sheet manifest drifted")
        paths_by_name = dict(sheets)
        actual_critical = set(paths_by_name) & {
            target.sheet_name for target in TARGET_SPECS
        }
        if actual_critical != _critical_sheet_names(spec.section_id):
            raise ProfileError("critical worksheet coverage drifted")

        formats = validate_styles(archive)
        if formats != ["General", "General"]:
            raise ProfileError("2017 General-style profile drifted")
        strings, string_manifest = parse_shared_strings(archive, spec)
        if (
            enforce_pinned_manifests
            and string_manifest != spec.expected_shared_string_manifest_sha256
        ):
            raise ProfileError("shared-string semantic manifest drifted")

        cache: Dict[str, Tuple[str, Dict[str, CellData]]] = {}
        targets: List[Dict[str, Any]] = []
        for target in TARGET_SPECS:
            if target.section_id != spec.section_id:
                continue
            if target.sheet_name not in paths_by_name:
                raise ProfileError("critical sheet is absent: %s" % target.sheet_name)
            if target.sheet_name not in cache:
                cache[target.sheet_name] = sheet_cells(
                    archive, paths_by_name[target.sheet_name], strings
                )
            dimension, cells = cache[target.sheet_name]
            targets.append(_target_record(target, spec, dimension, cells))

        workbook_record = {
            "status": STATUS,
            "workbook_id": spec.workbook_id,
            "section_id": spec.section_id,
            "source_url": spec.source_url,
            "object_name": spec.object_name,
            "raw_sha256": spec.raw_sha256,
            "raw_byte_count": spec.byte_count,
            "zip_member_count": len(members),
            "zip_member_manifest_sha256": member_manifest,
            "zip_crc_verified": True,
            "all_relationships_validated": True,
            "relationship_count": relationship_count,
            "relationship_manifest_sha256": relationship_manifest,
            "sheet_count": len(sheets),
            "sheet_manifest_sha256": sheet_manifest,
            "shared_string_count": spec.expected_shared_string_count,
            "shared_string_unique_count": len(strings),
            "shared_string_manifest_sha256": string_manifest,
            "cell_formats": formats,
            "data_published_text": spec.data_published_text,
            "file_created_text": spec.file_created_text,
            "http_last_modified": spec.http_last_modified,
            "gates": false_gates(),
        }
        return workbook_record, targets


def _normalized_absolute(path: Path, location: str) -> Path:
    text = os.fspath(path)
    if not path.is_absolute() or os.path.normpath(text) != text:
        raise ProfileError("%s must be an absolute, lexically normalized path" % location)
    return path


def _safe_existing_directory(path: Path, location: str) -> Path:
    _normalized_absolute(path, location)
    if path.is_symlink():
        raise ProfileError("%s is a symbolic link" % location)
    try:
        resolved = path.resolve(strict=True)
    except OSError as error:
        raise ProfileError("%s is absent" % location) from error
    if resolved != path or not path.is_dir():
        raise ProfileError("%s is not a canonical directory" % location)
    return path


def _read_pinned_file(path: Path, byte_count: int, digest: str, location: str) -> bytes:
    _normalized_absolute(path, location)
    if path.is_symlink() or path.resolve(strict=True) != path:
        raise ProfileError("%s path is unsafe" % location)
    flags = os.O_RDONLY
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise ProfileError("%s could not be opened safely" % location) from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            raise ProfileError("%s is not a single-link regular file" % location)
        if before.st_size != byte_count:
            raise ProfileError("%s byte count drifted" % location)
        with os.fdopen(descriptor, "rb", closefd=False) as stream:
            data = stream.read(byte_count + 1)
        after = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    identity = ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_nlink")
    if any(getattr(before, item) != getattr(after, item) for item in identity):
        raise ProfileError("%s changed while being read" % location)
    if len(data) != byte_count or sha256_bytes(data) != digest:
        raise ProfileError("%s exact identity drifted" % location)
    return data


def _receipt_required_text(receipt: bytes) -> None:
    try:
        text = receipt.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ProfileError("receipt is not UTF-8") from error
    if "\r" in text or not text.endswith("\n"):
        raise ProfileError("receipt newline canonicalization drifted")
    exact_once = (
        'pair_sha256 = "%s"' % PAIR_HASH,
        'receipt_sha256 = "%s"' % RECEIPT_SEMANTIC_SHA256,
        'reference_period = "2017Q3"',
        'sequence = 25',
        'event_timestamp_utc = "%s"' % RELEASE_EVENT_TIMESTAMP_UTC,
        'capture_started_at_utc = "2026-08-07T22:20:19.781Z"',
        'capture_completed_at_utc = "2026-08-07T22:20:22.296Z"',
        'present_day_retrieval_only = true',
        'snapshot_boundary = "PRESENT_DAY_HMI7_ARCHIVE_RETRIEVAL_NOT_HISTORICAL_FIRST_STATE"',
        'source_mode_attested = "INJECTED_FETCHER_OUTPUT"',
        'network_transport_verified = false',
        'metadata_content_sha256 = "%s"' % METADATA_CONTENT_SHA256,
        'historical_availability_status = "UNKNOWN_NOT_ESTABLISHED_BY_PRESENT_DAY_CAPTURE"',
        'last-modified"\n    sequence = 4\n    value = "Fri, 27 Oct 2017 17:34:50 GMT"',
        'last-modified"\n    sequence = 4\n    value = "Tue, 31 Oct 2017 15:29:36 GMT"',
    )
    for snippet in exact_once:
        if text.count(snippet) != 1:
            raise ProfileError("receipt semantic binding drifted: %s" % snippet[:48])
    expected_gate_block = """[gates]
empirical_forecast_execution_allowed = false
historical_first_state_proven = false
historical_workbook_availability_proven = false
production_scoring_allowed = false
promotion_eligible = false
ready = false
source_inventory_mutation_allowed = false
strict_origin_admissible = false
"""
    if text.count(expected_gate_block) != 1:
        raise ProfileError("receipt gate block drifted")
    for spec in WORKBOOK_SPECS:
        if text.count('observed_raw_sha256 = "%s"' % spec.raw_sha256) != 1:
            raise ProfileError("receipt raw-workbook identity drifted")
        if text.count('object_relative_path = "objects/%s"' % spec.object_name) != 1:
            raise ProfileError("receipt object path drifted")
        if text.count('requested_url = "%s"' % spec.source_url) != 1:
            raise ProfileError("receipt source URL drifted")


def validate_bundle(bundle_path: Path) -> Tuple[Dict[str, bytes], bytes]:
    bundle = _safe_existing_directory(bundle_path, "bundle")
    if bundle.name != BUNDLE_NAME:
        raise ProfileError("bundle content-addressed directory name drifted")
    objects = _safe_existing_directory(bundle / "objects", "bundle objects")
    root_names = {entry.name for entry in os.scandir(bundle)}
    if root_names != {"objects", RECEIPT_NAME}:
        raise ProfileError("bundle root file set drifted")
    object_names = {entry.name for entry in os.scandir(objects)}
    expected_object_names = {spec.object_name for spec in WORKBOOK_SPECS}
    if object_names != expected_object_names:
        raise ProfileError("bundle object file set drifted")
    receipt = _read_pinned_file(
        bundle / RECEIPT_NAME,
        RECEIPT_BYTE_COUNT,
        RECEIPT_FILE_SHA256,
        "receipt",
    )
    _receipt_required_text(receipt)
    workbook_bytes = {
        spec.section_id: _read_pinned_file(
            objects / spec.object_name,
            spec.byte_count,
            spec.raw_sha256,
            "%s raw object" % spec.workbook_id,
        )
        for spec in WORKBOOK_SPECS
    }
    return workbook_bytes, receipt


def _revalidate_bundle(bundle_path: Path) -> None:
    validate_bundle(bundle_path)


def build_artifact(bundle_path: Path) -> Dict[str, Any]:
    parser_path = Path(__file__).resolve(strict=True)
    parser_hash_before = sha256_bytes(parser_path.read_bytes())
    _validate_profile()
    workbook_bytes, _receipt = validate_bundle(bundle_path)
    workbook_records: List[Dict[str, Any]] = []
    target_records: List[Dict[str, Any]] = []
    for spec in WORKBOOK_SPECS:
        workbook_record, targets = _parse_workbook_bytes(
            workbook_bytes[spec.section_id],
            spec,
            enforce_pinned_manifests=True,
        )
        workbook_records.append(workbook_record)
        target_records.extend(targets)
    if sorted(record["target_id"] for record in target_records) != sorted(TARGET_BY_ID):
        raise ProfileError("parsed target coverage is not exactly five")
    _revalidate_bundle(bundle_path)
    parser_hash_after = sha256_bytes(parser_path.read_bytes())
    if parser_hash_after != parser_hash_before:
        raise ProfileError("parser source changed during execution")
    cross_checks = {
        record["target_id"]: record["release_statement_cross_check"]
        for record in target_records
        if record["release_statement_cross_check"]["performed"]
    }
    if set(cross_checks) != {"real_gdp", "pce_price_index", "core_pce_price_index"}:
        raise ProfileError("release-statement semantic-check coverage drifted")
    target_by_id = {record["target_id"]: record for record in target_records}
    nominal_number = target_by_id["nominal_gdp"]["current_quarter"][
        "canonical_number"
    ]
    if nominal_number is None:
        raise ProfileError("nominal GDP release-level cross-check input is absent")
    nominal_billions_1dp = _group_decimal_whole(
        _rounded_ratio(int(nominal_number["coefficient"]), 1_000, 1)
    )
    if nominal_billions_1dp != "19,495.5":
        raise ProfileError("nominal GDP release-level semantic check failed")
    return {
        "artifact": {
            "schema_version": SCHEMA_VERSION,
            "parser_version": PARSER_VERSION,
            "parser_sha256": parser_hash_before,
            "profile_id": PROFILE_ID,
            "profile_sha256": profile_sha256(),
            "status": STATUS,
            "evidence_class": EVIDENCE_CLASS,
            "canonicalization": CANONICALIZATION,
            "source_agency": "U.S. Bureau of Economic Analysis",
            "source_attribution": "Source: U.S. Bureau of Economic Analysis",
            "local_raw_paths_included": False,
            "execution_environment_included": False,
            "repository_state_included": False,
            "gates": false_gates(),
        },
        "capture": {
            "receipt_semantic_sha256": RECEIPT_SEMANTIC_SHA256,
            "receipt_file_sha256": RECEIPT_FILE_SHA256,
            "receipt_byte_count": RECEIPT_BYTE_COUNT,
            "raw_pair_sha256": PAIR_HASH,
            "capture_interval_utc": PRESENT_DAY_CAPTURE_INTERVAL_UTC,
            "present_day_retrieval_only": True,
            "source_mode_attested": "INJECTED_FETCHER_OUTPUT",
            "source_mode_attestation_authenticated": False,
            "network_transport_verified": False,
            "historical_first_state_proven": False,
            "historical_availability_proven": False,
            "gates": false_gates(),
        },
        "release": {
            "release_id": "bea_17_56_2017q3_advance",
            "reference_period": "2017Q3",
            "estimate_family": "advance",
            "event_timestamp_utc": RELEASE_EVENT_TIMESTAMP_UTC,
            "event_page_url": (
                "https://www.bea.gov/news/2017/"
                "gross-domestic-product-3rd-quarter-2017-advance-estimate"
            ),
            "archive_directory_id": "13049",
            "archive_label": "Advance_October-27-2017",
            "release_event_is_workbook_snapshot": False,
            "snapshot_boundary": (
                "PRESENT_DAY_HMI7_ARCHIVE_RETRIEVAL_NOT_HISTORICAL_FIRST_STATE"
            ),
            "section2_embedded_file_created_text": WORKBOOK_BY_SECTION["2"].file_created_text,
            "section2_http_last_modified": WORKBOOK_BY_SECTION["2"].http_last_modified,
            "section2_embedded_creation_is_post_release": True,
            "section2_http_last_modified_is_post_release": True,
            "section2_temporal_blocker": (
                "SECTION2_PRESENT_ARCHIVE_OBJECT_POSTDATES_2017_RELEASE_EVENT_"
                "AND_CANNOT_PROVE_ORIGIN_TIME_AVAILABILITY"
            ),
            "gates": false_gates(),
        },
        "workbooks": sorted(workbook_records, key=lambda item: item["section_id"]),
        "targets": sorted(target_records, key=lambda item: item["target_id"]),
        "semantic_cross_checks": {
            "role": "NON_ORIGIN_SEMANTIC_CHECKS_ONLY",
            "workbook_terminal_display_values": {
                target.target_id: target.current_display for target in TARGET_SPECS
            },
            "nominal_gdp_release_level": {
                "expected_billions_of_dollars_1dp": "19,495.5",
                "computed_billions_of_dollars_1dp": nominal_billions_1dp,
                "matches": True,
                "origin_evidence": False,
            },
            "rounded_release_statements": cross_checks,
            "origin_evidence": False,
            "gates": false_gates(),
        },
    }


def _safe_output_directory(path: Path) -> Path:
    _normalized_absolute(path, "output directory")
    if path.exists():
        return _safe_existing_directory(path, "output directory")
    parent = _safe_existing_directory(path.parent, "output directory parent")
    path.mkdir(mode=0o700)
    if path.is_symlink() or path.resolve(strict=True) != path or path.parent != parent:
        raise ProfileError("output directory became unsafe")
    return path


def write_content_addressed(output_dir: Path, data: bytes) -> Path:
    output = _safe_output_directory(output_dir)
    digest = sha256_bytes(data)
    destination = output / (
        "bea-hmi7-r2017q3-advance-era-profile-sha256-%s.json" % digest
    )
    if destination.exists():
        if destination.is_symlink() or not destination.is_file():
            raise ProfileError("existing content-addressed artifact is unsafe")
        if destination.read_bytes() != data:
            raise ProfileError("existing content-addressed artifact differs")
        return destination
    descriptor, temporary_name = tempfile.mkstemp(
        dir=output, prefix=".2017-era-fingerprint-"
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


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    artifact = build_artifact(arguments.bundle)
    data = canonical_json_bytes(artifact)
    path = write_content_addressed(arguments.output_dir, data)
    print(path)
    print("sha256=%s" % sha256_bytes(data))
    print("targets=5")
    print("reference_period_count=283")
    print("status=%s" % STATUS)
    for gate, value in false_gates().items():
        print("%s=%s" % (gate, str(value).lower()))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ProfileError as error:
        print("error: %s" % error, file=os.sys.stderr)
        raise SystemExit(1) from error
