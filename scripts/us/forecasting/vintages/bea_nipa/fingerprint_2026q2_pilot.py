#!/usr/bin/env python3
"""Validate and fingerprint the pinned 2026Q2 BEA HMI7 XLSX pair.

This parser intentionally supports one exact release. It validates the raw
byte identities before reading OOXML, verifies all five target mappings, and
emits a content-addressed JSON artifact. The artifact is a present-day
content observation only; it cannot establish historical availability or
admit a forecast origin.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from pathlib import Path, PurePosixPath
from typing import Any

MAIN_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
OFFICE_REL_NS = (
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
)
PACKAGE_REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"
NS = {"m": MAIN_NS, "r": OFFICE_REL_NS, "p": PACKAGE_REL_NS}

SCHEMA_VERSION = "beforeit-us-bea-nipa-content-fingerprint.v2"
PARSER_VERSION = "beforeit-us-bea-nipa-ooxml-parser.v2"
STATUS = "PRESENT_DAY_ARCHIVE_BYTES_PARSED_NONADMITTING"
JSON_CANONICALIZATION = "utf8_sorted_keys_compact_json_lf"
SEMANTIC_IDENTITY_SCOPE = (
    "RAW_WORKBOOK_BYTES_RELEASE_MAPPING_PARSED_VALUES_AND_PARSER_BYTES"
)
RELEASE_ID = "r2026q2_advance"
REFERENCE_QUARTER = "2026Q2"
ESTIMATE_LABEL = "advance"
MAPPING_PROFILE_ID = "september_2023_rebase"
RAW_BUNDLE_SHA256 = (
    "9f4152937f58d777feb0f6562c1b1ca3681b0e51c1aa03b486fd5d29d1e794ff"
)
MAPPING_AUDIT_SHA256 = (
    "424e34febc2054a055f8f9495a94f08fd93d8229d035b0a349b0446f0e7c2b5f"
)
SOURCE_AGENCY = "U.S. Bureau of Economic Analysis"
SOURCE_ATTRIBUTION = "Source: U.S. Bureau of Economic Analysis"
DATA_PUBLISHED_TEXT = "Data published July 30, 2026"
SOURCE_TEXT = "Bureau of Economic Analysis"
REFERENCE_START = "1947Q1"
REFERENCE_END = "2026Q2"
MISSING_MARKER = "....."
DECIMAL_PATTERN = re.compile(r"-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?\Z")
CELL_PATTERN = re.compile(r"([A-Z]+)([1-9][0-9]*)\Z")
FOOTNOTE_PATTERN = re.compile(r"\\[0-9]+\\")


class FingerprintError(RuntimeError):
    """Raised when a workbook or mapping fails closed validation."""


@dataclass(frozen=True)
class WorkbookSpec:
    workbook_id: str
    section_id: str
    url: str
    sha256: str
    byte_count: int
    expected_sheet_count: int


@dataclass(frozen=True)
class TargetSpec:
    target_id: str
    workbook_id: str
    section_id: str
    sheet_name: str
    table_number: str
    table_title: str
    units_text: str
    published_line_number: int
    physical_row_number: int
    series_code: str
    concept_label: str
    seasonal_adjustment: str
    unit: str
    base_year: str
    decimal_places: int
    number_format_code: str


@dataclass(frozen=True)
class CellData:
    value: str | None
    style_index: int


WORKBOOK_SPECS = (
    WorkbookSpec(
        workbook_id="r2026q2_advance_s1",
        section_id="1",
        url=(
            "https://apps.bea.gov/HistData/Files/Releases/GDP_and_PI/"
            "2026/Q2/Advance_July-30-2026/Section1all_xls.xlsx"
        ),
        sha256=(
            "ddcd0c5b693cb5d179198e67dda60f817e0e97196e6f1c158152971bbc80b136"
        ),
        byte_count=4_056_562,
        expected_sheet_count=107,
    ),
    WorkbookSpec(
        workbook_id="r2026q2_advance_s2",
        section_id="2",
        url=(
            "https://apps.bea.gov/HistData/Files/Releases/GDP_and_PI/"
            "2026/Q2/Advance_July-30-2026/Section2all_xls.xlsx"
        ),
        sha256=(
            "1d5e3c6e177f6ba818bacf6361b3f21b7996e6cfdf55afb4d2a86a41bd2a4011"
        ),
        byte_count=4_870_580,
        expected_sheet_count=55,
    ),
)

TARGET_SPECS = (
    TargetSpec(
        target_id="nominal_gdp",
        workbook_id="r2026q2_advance_s1",
        section_id="1",
        sheet_name="T10105-Q",
        table_number="1.1.5",
        table_title="Table 1.1.5. Gross Domestic Product",
        units_text="[Millions of dollars] Seasonally adjusted at annual rates",
        published_line_number=1,
        physical_row_number=9,
        series_code="A191RC",
        concept_label="Gross domestic product",
        seasonal_adjustment="seasonally_adjusted_annual_rate",
        unit="millions_of_dollars",
        base_year="not_applicable",
        decimal_places=0,
        number_format_code="#,##0",
    ),
    TargetSpec(
        target_id="real_gdp",
        workbook_id="r2026q2_advance_s1",
        section_id="1",
        sheet_name="T10106-Q",
        table_number="1.1.6",
        table_title="Table 1.1.6. Real Gross Domestic Product, Chained Dollars",
        units_text=(
            "[Millions of chained (2017) dollars] "
            "Seasonally adjusted at annual rates"
        ),
        published_line_number=1,
        physical_row_number=9,
        series_code="A191RX",
        concept_label="Gross domestic product",
        seasonal_adjustment="seasonally_adjusted_annual_rate",
        unit="millions_of_chained_dollars",
        base_year="2017",
        decimal_places=0,
        number_format_code="#,##0",
    ),
    TargetSpec(
        target_id="gdp_deflator",
        workbook_id="r2026q2_advance_s1",
        section_id="1",
        sheet_name="T10109-Q",
        table_number="1.1.9",
        table_title=(
            "Table 1.1.9. Implicit Price Deflators for Gross Domestic Product"
        ),
        units_text="[Index numbers, 2017=100] Seasonally adjusted",
        published_line_number=1,
        physical_row_number=9,
        series_code="A191RD",
        concept_label="Gross domestic product",
        seasonal_adjustment="seasonally_adjusted",
        unit="index",
        base_year="2017",
        decimal_places=3,
        number_format_code="#,##0.000",
    ),
    TargetSpec(
        target_id="pce_price_index",
        workbook_id="r2026q2_advance_s2",
        section_id="2",
        sheet_name="T20304-Q",
        table_number="2.3.4",
        table_title=(
            "Table 2.3.4. Price Indexes for Personal Consumption "
            "Expenditures by Major Type of Product"
        ),
        units_text="[Index numbers, 2017=100] Seasonally adjusted",
        published_line_number=1,
        physical_row_number=9,
        series_code="DPCERG",
        concept_label="Personal consumption expenditures (PCE)",
        seasonal_adjustment="seasonally_adjusted",
        unit="index",
        base_year="2017",
        decimal_places=3,
        number_format_code="#,##0.000",
    ),
    TargetSpec(
        target_id="core_pce_price_index",
        workbook_id="r2026q2_advance_s2",
        section_id="2",
        sheet_name="T20304-Q",
        table_number="2.3.4",
        table_title=(
            "Table 2.3.4. Price Indexes for Personal Consumption "
            "Expenditures by Major Type of Product"
        ),
        units_text="[Index numbers, 2017=100] Seasonally adjusted",
        published_line_number=25,
        physical_row_number=34,
        series_code="DPCCRG",
        concept_label="PCE excluding food and energy",
        seasonal_adjustment="seasonally_adjusted",
        unit="index",
        base_year="2017",
        decimal_places=3,
        number_format_code="#,##0.000",
    ),
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def column_number(name: str) -> int:
    if not re.fullmatch(r"[A-Z]+", name):
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
    match_start = re.fullmatch(r"([0-9]{4})Q([1-4])", start)
    match_end = re.fullmatch(r"([0-9]{4})Q([1-4])", end)
    if match_start is None or match_end is None:
        raise FingerprintError("quarter bounds must use YYYYQ[1-4]")
    start_index = int(match_start[1]) * 4 + int(match_start[2]) - 1
    end_index = int(match_end[1]) * 4 + int(match_end[2]) - 1
    if start_index > end_index:
        raise FingerprintError("quarter bounds are reversed")
    return [
        f"{index // 4}Q{index % 4 + 1}"
        for index in range(start_index, end_index + 1)
    ]


def normalized_concept(value: str) -> str:
    return " ".join(FOOTNOTE_PATTERN.sub("", value).split())


def safe_raw_path(raw_root: Path, path: Path) -> Path:
    root = raw_root.resolve(strict=True)
    if raw_root.is_symlink():
        raise FingerprintError(f"raw root is a symbolic link: {raw_root}")
    if path.is_symlink():
        raise FingerprintError(f"workbook is a symbolic link: {path}")
    resolved = path.resolve(strict=True)
    if not resolved.is_file():
        raise FingerprintError(f"workbook is not a regular file: {path}")
    try:
        resolved.relative_to(root)
    except ValueError as error:
        raise FingerprintError(f"workbook escapes raw root: {path}") from error
    return resolved


def relationship_target(archive: zipfile.ZipFile, relationship_id: str) -> str:
    relationships = ET.fromstring(
        archive.read("xl/_rels/workbook.xml.rels")
    )
    matches = [
        node.attrib["Target"]
        for node in relationships.findall("p:Relationship", NS)
        if node.attrib.get("Id") == relationship_id
    ]
    if len(matches) != 1:
        raise FingerprintError(
            f"workbook relationship {relationship_id!r} is not unique"
        )
    target = PurePosixPath(matches[0])
    if target.is_absolute() or ".." in target.parts:
        raise FingerprintError("worksheet relationship target is unsafe")
    if target.parts and target.parts[0] == "xl":
        return str(target)
    return str(PurePosixPath("xl") / target)


def shared_strings(archive: zipfile.ZipFile) -> list[str]:
    path = "xl/sharedStrings.xml"
    if path not in archive.namelist():
        return []
    root = ET.fromstring(archive.read(path))
    return [
        "".join(text.text or "" for text in item.findall(".//m:t", NS))
        for item in root.findall("m:si", NS)
    ]


def cell_value(cell: ET.Element, strings: list[str]) -> str | None:
    cell_type = cell.attrib.get("t")
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
            return strings[int(value)]
        except (ValueError, IndexError) as error:
            raise FingerprintError("invalid shared-string reference") from error
    if cell_type == "b":
        if value not in {"0", "1"}:
            raise FingerprintError("invalid Boolean cell value")
        return "true" if value == "1" else "false"
    return value


def workbook_sheets(
    archive: zipfile.ZipFile,
) -> dict[str, str]:
    workbook = ET.fromstring(archive.read("xl/workbook.xml"))
    result: dict[str, str] = {}
    for sheet in workbook.findall("m:sheets/m:sheet", NS):
        name = sheet.attrib.get("name")
        relationship_id = sheet.attrib.get(f"{{{OFFICE_REL_NS}}}id")
        if not name or not relationship_id:
            raise FingerprintError("workbook sheet identity is incomplete")
        if name in result:
            raise FingerprintError(f"duplicate workbook sheet name: {name}")
        result[name] = relationship_target(archive, relationship_id)
    return result


def number_formats(archive: zipfile.ZipFile) -> list[str]:
    built_in = {
        0: "General",
        1: "0",
        2: "0.00",
        3: "#,##0",
        4: "#,##0.00",
    }
    root = ET.fromstring(archive.read("xl/styles.xml"))
    custom: dict[int, str] = {}
    for node in root.findall("m:numFmts/m:numFmt", NS):
        try:
            identifier = int(node.attrib["numFmtId"])
            format_code = node.attrib["formatCode"]
        except (KeyError, ValueError) as error:
            raise FingerprintError("invalid custom number format") from error
        if identifier in custom:
            raise FingerprintError("duplicate custom number format")
        custom[identifier] = format_code
    result: list[str] = []
    for style in root.findall("m:cellXfs/m:xf", NS):
        try:
            identifier = int(style.attrib["numFmtId"])
        except (KeyError, ValueError) as error:
            raise FingerprintError("invalid cell number format") from error
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


def sheet_cells(
    archive: zipfile.ZipFile,
    sheet_path: str,
    strings: list[str],
) -> dict[str, CellData]:
    root = ET.fromstring(archive.read(sheet_path))
    result: dict[str, CellData] = {}
    for cell in root.findall(".//m:sheetData/m:row/m:c", NS):
        reference = cell.attrib.get("r")
        if reference is None or CELL_PATTERN.fullmatch(reference) is None:
            raise FingerprintError("worksheet contains an invalid cell address")
        if reference in result:
            raise FingerprintError(f"duplicate worksheet cell: {reference}")
        try:
            style_index = int(cell.attrib.get("s", "0"))
        except ValueError as error:
            raise FingerprintError("worksheet cell has invalid style index") from error
        if style_index < 0:
            raise FingerprintError("worksheet cell has negative style index")
        result[reference] = CellData(
            value=cell_value(cell, strings),
            style_index=style_index,
        )
    return result


def required_cell(cells: dict[str, CellData], address: str) -> CellData:
    if address not in cells or cells[address].value is None:
        raise FingerprintError(f"required cell {address} is empty or absent")
    return cells[address]


def required_text(cells: dict[str, CellData], address: str) -> str:
    return str(required_cell(cells, address).value)


def validate_numeric_or_missing(value: str, address: str) -> None:
    if value == MISSING_MARKER:
        return
    if DECIMAL_PATTERN.fullmatch(value) is None:
        raise FingerprintError(
            f"target value {address} is not a canonical decimal or missing marker"
        )


def published_value(value: str, decimal_places: int, address: str) -> str:
    if value == MISSING_MARKER:
        return value
    try:
        decimal = Decimal(value)
    except InvalidOperation as error:
        raise FingerprintError(f"invalid numeric value at {address}") from error
    quantum = Decimal(1).scaleb(-decimal_places)
    rounded = decimal.quantize(quantum, rounding=ROUND_HALF_UP)
    return format(rounded, f".{decimal_places}f")


def values_digest(periods: list[str], values: list[str]) -> str:
    payload = "".join(
        f"{period}\t{value}\n" for period, value in zip(periods, values)
    ).encode("utf-8")
    return sha256_bytes(payload)


def validate_workbook_identity(path: Path, spec: WorkbookSpec) -> None:
    byte_count = path.stat().st_size
    if byte_count != spec.byte_count:
        raise FingerprintError(
            f"{spec.workbook_id} byte count {byte_count} != {spec.byte_count}"
        )
    digest = sha256_file(path)
    if digest != spec.sha256:
        raise FingerprintError(
            f"{spec.workbook_id} SHA-256 {digest} != {spec.sha256}"
        )
    with path.open("rb") as stream:
        if stream.read(4) != b"PK\x03\x04":
            raise FingerprintError(
                f"{spec.workbook_id} lacks OOXML ZIP magic"
            )


def parse_workbook(
    path: Path,
    spec: WorkbookSpec,
    targets: tuple[TargetSpec, ...],
    raw_root: Path,
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    validate_workbook_identity(path, spec)
    with zipfile.ZipFile(path, "r") as archive:
        corrupt = archive.testzip()
        if corrupt is not None:
            raise FingerprintError(
                f"{spec.workbook_id} has corrupt ZIP member {corrupt}"
            )
        required_parts = {
            "[Content_Types].xml",
            "_rels/.rels",
            "xl/workbook.xml",
            "xl/_rels/workbook.xml.rels",
        }
        missing_parts = sorted(required_parts - set(archive.namelist()))
        if missing_parts:
            raise FingerprintError(
                f"{spec.workbook_id} lacks OOXML parts: {missing_parts}"
            )
        sheets = workbook_sheets(archive)
        if len(sheets) != spec.expected_sheet_count:
            raise FingerprintError(
                f"{spec.workbook_id} sheet count {len(sheets)} "
                f"!= {spec.expected_sheet_count}"
            )
        strings = shared_strings(archive)
        formats = number_formats(archive)
        cache: dict[str, dict[str, CellData]] = {}
        target_records: list[dict[str, Any]] = []
        expected_periods = quarter_sequence(REFERENCE_START, REFERENCE_END)
        first_column = column_number("D")
        last_column = first_column + len(expected_periods) - 1
        if column_name(last_column) != "LI":
            raise FingerprintError("reference-period terminal column drifted")

        for target in targets:
            if target.sheet_name not in sheets:
                raise FingerprintError(
                    f"{spec.workbook_id} lacks sheet {target.sheet_name}"
                )
            cells = cache.setdefault(
                target.sheet_name,
                sheet_cells(
                    archive,
                    sheets[target.sheet_name],
                    strings,
                ),
            )
            if required_text(cells, "A1") != target.table_title:
                raise FingerprintError(f"{target.target_id} table title drifted")
            if required_text(cells, "A2") != target.units_text:
                raise FingerprintError(f"{target.target_id} units text drifted")
            coverage_text = required_text(cells, "A3")
            expected_coverage = (
                f"Quarterly data from {REFERENCE_START} to {REFERENCE_END}"
            )
            if coverage_text != expected_coverage:
                raise FingerprintError(f"{target.target_id} coverage drifted")
            if required_text(cells, "A4") != SOURCE_TEXT:
                raise FingerprintError(f"{target.target_id} source text drifted")
            if required_text(cells, "A5") != DATA_PUBLISHED_TEXT:
                raise FingerprintError(
                    f"{target.target_id} publication text drifted"
                )
            file_created_text = required_text(cells, "A6")
            if not file_created_text.startswith("File created "):
                raise FingerprintError(
                    f"{target.target_id} file-created text is malformed"
                )

            row = target.physical_row_number
            line_text = required_text(cells, f"A{row}")
            if line_text != str(target.published_line_number):
                raise FingerprintError(
                    f"{target.target_id} published line drifted"
                )
            source_concept_text = required_text(cells, f"B{row}")
            if normalized_concept(source_concept_text) != target.concept_label:
                raise FingerprintError(
                    f"{target.target_id} concept label drifted"
                )
            if required_text(cells, f"C{row}") != target.series_code:
                raise FingerprintError(
                    f"{target.target_id} series code drifted"
                )

            periods: list[str] = []
            raw_values: list[str] = []
            published_values: list[str] = []
            for offset, expected_period in enumerate(expected_periods):
                column = column_name(first_column + offset)
                period = required_text(cells, f"{column}8")
                if period != expected_period:
                    raise FingerprintError(
                        f"{target.target_id} reference period "
                        f"{column}8 drifted"
                    )
                address = f"{column}{row}"
                value_cell = required_cell(cells, address)
                value = str(value_cell.value)
                validate_numeric_or_missing(value, address)
                if value != MISSING_MARKER:
                    if value_cell.style_index >= len(formats):
                        raise FingerprintError(
                            f"{target.target_id} style index is out of range"
                        )
                    if formats[value_cell.style_index] != target.number_format_code:
                        raise FingerprintError(
                            f"{target.target_id} number format drifted at {address}"
                        )
                periods.append(period)
                raw_values.append(value)
                published_values.append(
                    published_value(value, target.decimal_places, address)
                )

            target_records.append(
                {
                    "target_id": target.target_id,
                    "workbook_id": target.workbook_id,
                    "raw_sha256": spec.sha256,
                    "section_id": target.section_id,
                    "sheet_name": target.sheet_name,
                    "table_number": target.table_number,
                    "table_title": target.table_title,
                    "published_line_number": target.published_line_number,
                    "physical_row_number": target.physical_row_number,
                    "series_code": target.series_code,
                    "source_concept_text": source_concept_text,
                    "normalized_concept": target.concept_label,
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
                        "line": f"{target.sheet_name}!A{row}",
                        "concept": f"{target.sheet_name}!B{row}",
                        "series": f"{target.sheet_name}!C{row}",
                        "reference_period_range": (
                            f"{target.sheet_name}!D8:LI8"
                        ),
                        "value_range": f"{target.sheet_name}!D{row}:LI{row}",
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
                    "raw_values_sha256": values_digest(periods, raw_values),
                    "published_values_sha256": values_digest(
                        periods,
                        published_values,
                    ),
                    "observations": [
                        {
                            "period": period,
                            "raw_value_text": raw_value,
                            "published_value_text": displayed_value,
                        }
                        for period, raw_value, displayed_value in zip(
                            periods,
                            raw_values,
                            published_values,
                        )
                    ],
                    "historical_availability_verified": False,
                    "origin_admissible": False,
                    "ready": False,
                }
            )

        workbook_record = {
            "workbook_id": spec.workbook_id,
            "release_id": RELEASE_ID,
            "section_id": spec.section_id,
            "requested_locator": spec.url,
            "raw_object_path": str(path.relative_to(raw_root)),
            "raw_sha256": spec.sha256,
            "raw_byte_count": spec.byte_count,
            "file_format": "xlsx",
            "ooxml_zip_integrity_verified": True,
            "sheet_count": len(sheets),
            "data_published_text": DATA_PUBLISHED_TEXT,
            "mapping_profile_id": MAPPING_PROFILE_ID,
            "historical_availability_verified": False,
            "origin_admissible": False,
            "ready": False,
        }
        return workbook_record, target_records


def artifact_metadata(parser_path: Path) -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "parser_version": PARSER_VERSION,
        "status": STATUS,
        "release_id": RELEASE_ID,
        "reference_quarter": REFERENCE_QUARTER,
        "estimate_label": ESTIMATE_LABEL,
        "mapping_profile_id": MAPPING_PROFILE_ID,
        "mapping_audit_sha256": MAPPING_AUDIT_SHA256,
        "raw_bundle_sha256": RAW_BUNDLE_SHA256,
        "source_agency": SOURCE_AGENCY,
        "source_attribution": SOURCE_ATTRIBUTION,
        "parser_sha256": sha256_file(parser_path),
        "canonicalization": JSON_CANONICALIZATION,
        "semantic_identity_scope": SEMANTIC_IDENTITY_SCOPE,
        "execution_environment_included": False,
        "repository_state_included": False,
        "persistence_scope": (
            "SMALL_CONTENT_FINGERPRINT_RAW_WORKBOOKS_EXTERNAL_TO_GIT"
        ),
        "evidence_class": "present_day_archive_content_observation",
        "release_event_evidence_included": False,
        "historical_availability_evidence_included": False,
        "historical_availability_verified": False,
        "inventory_mutated": False,
        "origin_admissible": False,
        "ready": False,
    }


def build_artifact(
    raw_root: Path,
    section_1_path: Path,
    section_2_path: Path,
) -> dict[str, Any]:
    resolved_root = raw_root.resolve(strict=True)
    paths = {
        "r2026q2_advance_s1": safe_raw_path(raw_root, section_1_path),
        "r2026q2_advance_s2": safe_raw_path(raw_root, section_2_path),
    }
    parser_path = Path(__file__).resolve(strict=True)
    workbook_records: list[dict[str, Any]] = []
    target_records: list[dict[str, Any]] = []
    for spec in WORKBOOK_SPECS:
        targets = tuple(
            target
            for target in TARGET_SPECS
            if target.workbook_id == spec.workbook_id
        )
        workbook, parsed_targets = parse_workbook(
            paths[spec.workbook_id],
            spec,
            targets,
            resolved_root,
        )
        workbook_records.append(workbook)
        target_records.extend(parsed_targets)

    expected_targets = {target.target_id for target in TARGET_SPECS}
    actual_targets = {target["target_id"] for target in target_records}
    if actual_targets != expected_targets or len(target_records) != 5:
        raise FingerprintError("parsed target coverage is not exactly five")

    return {
        "artifact": artifact_metadata(parser_path),
        "workbooks": sorted(
            workbook_records,
            key=lambda row: row["workbook_id"],
        ),
        "targets": sorted(
            target_records,
            key=lambda row: row["target_id"],
        ),
    }


def canonical_json_bytes(artifact: dict[str, Any]) -> bytes:
    return (
        json.dumps(
            artifact,
            ensure_ascii=False,
            allow_nan=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        + "\n"
    ).encode("utf-8")


def write_content_addressed(output_dir: Path, data: bytes) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    if output_dir.is_symlink():
        raise FingerprintError(f"output directory is a symlink: {output_dir}")
    digest = sha256_bytes(data)
    destination = output_dir / (
        f"bea-nipa-content-fingerprint-sha256-{digest}.json"
    )
    if destination.exists():
        if destination.is_symlink() or not destination.is_file():
            raise FingerprintError("existing content artifact is unsafe")
        if destination.read_bytes() != data:
            raise FingerprintError("hash-addressed content artifact differs")
        return destination
    descriptor, temporary_name = tempfile.mkstemp(
        dir=output_dir,
        prefix=".fingerprint-",
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
    parser.add_argument("--raw-root", type=Path, required=True)
    parser.add_argument("--section-1", type=Path, required=True)
    parser.add_argument("--section-2", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    artifact = build_artifact(
        arguments.raw_root,
        arguments.section_1,
        arguments.section_2,
    )
    data = canonical_json_bytes(artifact)
    path = write_content_addressed(arguments.output_dir, data)
    print(path)
    print(f"sha256={sha256_bytes(data)}")
    print("targets=5")
    print("historical_availability_verified=false")
    print("origin_admissible=false")
    print("ready=false")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except FingerprintError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
