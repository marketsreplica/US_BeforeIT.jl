#!/usr/bin/env python3
"""Generate a hermetic Census M3 inventory-stage evidence fixture.

The default input is the checked-in workbook capture.  Regeneration never
uses the network.  Only Python's standard library is used: the XLSX package is
read as ZIP/XML so the extraction does not depend on an Excel engine.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import zipfile
import xml.etree.ElementTree as ET
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


SCHEMA_VERSION = "beforeit-us-census-m3-inventory-stage-fixture.v1"
CLASSIFICATION = "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
SOURCE_URL = (
    "https://www.census.gov/manufacturing/m3/prel/historical_data/"
    "histshts/naics/naicsinvp.xlsx"
)
HISTORICAL_DOCUMENTATION_URL = (
    "https://www.census.gov/manufacturing/m3/historical_data/"
    "naicshist.pdf"
)
TIME_SERIES_URL = (
    "https://www.census.gov/manufacturing/m3/historical/timeseries.html"
)
METHODOLOGY_URL = (
    "https://www.census.gov/manufacturing/m3/"
    "how_the_data_are_collected/index.html"
)
DEFINITIONS_URL = (
    "https://www.census.gov/manufacturing/m3/definitions/index.html"
)
ABOUT_URL = (
    "https://www.census.gov/manufacturing/m3/about_the_surveys/index.html"
)

EXPECTED_WORKBOOK_SHA256 = (
    "74ee0d3b9d4a9673a39f1f4ece28206dcccca6451f48aee63506c61675373538"
)
EXPECTED_WORKBOOK_BYTE_COUNT = 969_323
EXPECTED_RECEIPT_SHA256 = (
    "8bee49047f315bfedbde66eb3f9ccccd7526726e13c3e0b6857da6a2947cb600"
)
EXPECTED_SHEET_NAME = "m3-outp-invp"
EXPECTED_SOURCE_ROW_COUNT = 11_060
EXPECTED_SERIES_COUNT = 316
EXPECTED_ADJUSTED_SERIES_COUNT = 158
EXPECTED_UNADJUSTED_SERIES_COUNT = 158
EXPECTED_YEAR_MINIMUM = 1992
EXPECTED_YEAR_MAXIMUM = 2026
EXPECTED_SOURCE_CELL_COUNT = 132_720
EXPECTED_NUMERIC_CELL_COUNT = 130_824
EXPECTED_MISSING_CELL_COUNT = 1_896
EXPECTED_STAGE_IDENTITY_SET_COUNT = 48
EXPECTED_IDENTITY_CHECK_COUNT = 20_160
EXPECTED_IDENTITY_OBSERVED_COUNT = 19_872
EXPECTED_IDENTITY_MISSING_COUNT = 288

HERE = Path(__file__).resolve().parent
DEFAULT_RAW_SOURCE = (
    HERE
    / "raw"
    / "census_m3_naicsinvp_2026-08-06_current_vintage"
)
DEFAULT_OUTPUT = (
    HERE
    / "fixtures"
    / "census_m3_naicsinvp_2026-08-06_current_vintage"
)
MONTH_NAMES = (
    "jan",
    "feb",
    "mar",
    "apr",
    "may",
    "jun",
    "jul",
    "aug",
    "sep",
    "oct",
    "nov",
    "dec",
)
ITEM_LABELS = {
    "TI": "TOTAL_INVENTORIES",
    "MI": "MATERIALS_AND_SUPPLIES_INVENTORIES",
    "WI": "WORK_IN_PROCESS_INVENTORIES",
    "FI": "FINISHED_GOODS_INVENTORIES",
}
SERIES_PATTERN = re.compile(
    r"^(?P<adjustment>[AU])(?P<m3_code>[A-Z0-9]{3})"
    r"(?P<item>TI|MI|WI|FI)$"
)
CELL_REFERENCE_PATTERN = re.compile(r"^(?P<column>[A-Z]+)(?P<row>[0-9]+)$")
INTEGER_PATTERN = re.compile(r"^-?[0-9]+$")
XML_NAMESPACE = {
    "m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
    "r": (
        "http://schemas.openxmlformats.org/officeDocument/2006/"
        "relationships"
    ),
}


@dataclass(frozen=True)
class SourceRow:
    source_row: int
    series_id: str
    adjustment_code: str
    m3_series_code: str
    item_code: str
    year: int
    values: tuple[int | None, ...]


def sha256_hex(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def file_sha256(path: Path) -> str:
    return sha256_hex(path.read_bytes())


def excel_column_number(reference: str) -> int:
    result = 0
    for character in reference:
        result = result * 26 + ord(character) - ord("A") + 1
    return result


def shared_strings(archive: zipfile.ZipFile) -> list[str]:
    root = ET.fromstring(archive.read("xl/sharedStrings.xml"))
    strings: list[str] = []
    for item in root.findall("m:si", XML_NAMESPACE):
        pieces = [
            element.text or ""
            for element in item.findall(".//m:t", XML_NAMESPACE)
        ]
        strings.append("".join(pieces))
    return strings


def workbook_sheet_name(archive: zipfile.ZipFile) -> str:
    root = ET.fromstring(archive.read("xl/workbook.xml"))
    sheets = root.findall("m:sheets/m:sheet", XML_NAMESPACE)
    if len(sheets) != 1:
        raise ValueError(f"expected one workbook sheet, found {len(sheets)}")
    return sheets[0].attrib["name"]


def parse_source_rows(workbook_path: Path) -> list[SourceRow]:
    payload = workbook_path.read_bytes()
    if len(payload) != EXPECTED_WORKBOOK_BYTE_COUNT:
        raise ValueError(
            "raw workbook byte count mismatch: "
            f"expected {EXPECTED_WORKBOOK_BYTE_COUNT}, got {len(payload)}"
        )
    if sha256_hex(payload) != EXPECTED_WORKBOOK_SHA256:
        raise ValueError("raw workbook SHA-256 mismatch")

    with zipfile.ZipFile(workbook_path) as archive:
        if archive.testzip() is not None:
            raise ValueError("raw workbook ZIP CRC validation failed")
        if workbook_sheet_name(archive) != EXPECTED_SHEET_NAME:
            raise ValueError("unexpected workbook sheet name")
        strings = shared_strings(archive)
        sheet = ET.fromstring(archive.read("xl/worksheets/sheet1.xml"))

    source_rows: list[SourceRow] = []
    for expected_row, row in enumerate(
        sheet.findall("m:sheetData/m:row", XML_NAMESPACE),
        start=1,
    ):
        source_row = int(row.attrib["r"])
        if source_row != expected_row:
            raise ValueError(
                f"nonconsecutive source row {source_row}, "
                f"expected {expected_row}"
            )
        values: list[str | int | None] = [None] * 14
        for cell in row.findall("m:c", XML_NAMESPACE):
            reference = cell.attrib["r"]
            match = CELL_REFERENCE_PATTERN.fullmatch(reference)
            if match is None or int(match.group("row")) != source_row:
                raise ValueError(f"invalid cell reference {reference!r}")
            column = excel_column_number(match.group("column"))
            if not 1 <= column <= 14:
                raise ValueError(f"cell outside A:N at {reference}")
            value_element = cell.find("m:v", XML_NAMESPACE)
            if value_element is None or value_element.text is None:
                raise ValueError(f"present cell lacks a value at {reference}")
            raw_value = value_element.text
            if cell.attrib.get("t") == "s":
                if column != 1 or not INTEGER_PATTERN.fullmatch(raw_value):
                    raise ValueError(f"invalid shared string at {reference}")
                index = int(raw_value)
                if not 0 <= index < len(strings):
                    raise ValueError(
                        f"shared string index out of range at {reference}"
                    )
                values[column - 1] = strings[index]
            else:
                if not INTEGER_PATTERN.fullmatch(raw_value):
                    raise ValueError(
                        f"noninteger numeric value at {reference}: "
                        f"{raw_value!r}"
                    )
                values[column - 1] = int(raw_value)

        series_id = values[0]
        year = values[1]
        if not isinstance(series_id, str) or not isinstance(year, int):
            raise ValueError(f"missing series identifier or year at row {source_row}")
        match = SERIES_PATTERN.fullmatch(series_id)
        if match is None:
            raise ValueError(f"unknown M3 series code {series_id!r}")
        numeric_values = values[2:]
        if not all(value is None or isinstance(value, int) for value in numeric_values):
            raise ValueError(f"invalid source value type at row {source_row}")
        source_rows.append(
            SourceRow(
                source_row,
                series_id,
                match.group("adjustment"),
                match.group("m3_code"),
                match.group("item"),
                year,
                tuple(numeric_values),
            )
        )
    validate_source_rows(source_rows)
    return source_rows


def validate_source_rows(rows: list[SourceRow]) -> None:
    if len(rows) != EXPECTED_SOURCE_ROW_COUNT:
        raise ValueError(f"unexpected source row count {len(rows)}")
    series_ids = {row.series_id for row in rows}
    if len(series_ids) != EXPECTED_SERIES_COUNT:
        raise ValueError(f"unexpected source series count {len(series_ids)}")
    adjustment_counts = Counter(series_id[0] for series_id in series_ids)
    if adjustment_counts != {
        "A": EXPECTED_ADJUSTED_SERIES_COUNT,
        "U": EXPECTED_UNADJUSTED_SERIES_COUNT,
    }:
        raise ValueError(f"unexpected adjustment counts {adjustment_counts}")
    item_counts = Counter(series_id[-2:] for series_id in series_ids)
    if item_counts != {"TI": 172, "MI": 48, "WI": 48, "FI": 48}:
        raise ValueError(f"unexpected item-code counts {item_counts}")

    rows_by_series: dict[str, list[SourceRow]] = {}
    for row in rows:
        rows_by_series.setdefault(row.series_id, []).append(row)
    expected_years = list(range(EXPECTED_YEAR_MINIMUM, EXPECTED_YEAR_MAXIMUM + 1))
    for series_id, series_rows in rows_by_series.items():
        years = [row.year for row in series_rows]
        if years != expected_years:
            raise ValueError(
                f"unexpected year sequence for {series_id}: {years}"
            )

    values = [value for row in rows for value in row.values]
    numeric_count = sum(value is not None for value in values)
    missing_count = sum(value is None for value in values)
    if len(values) != EXPECTED_SOURCE_CELL_COUNT:
        raise ValueError(f"unexpected source cell count {len(values)}")
    if numeric_count != EXPECTED_NUMERIC_CELL_COUNT:
        raise ValueError(f"unexpected numeric cell count {numeric_count}")
    if missing_count != EXPECTED_MISSING_CELL_COUNT:
        raise ValueError(f"unexpected missing cell count {missing_count}")
    if any(value is not None and value < 0 for value in values):
        raise ValueError("source workbook contains an unexpected negative value")
    if any(value == 0 for value in values):
        raise ValueError("source workbook contains an unexpected explicit zero")

    for row in rows:
        expected_missing = row.year == 2026
        for month, value in enumerate(row.values, start=1):
            if (value is None) != (expected_missing and month >= 7):
                raise ValueError(
                    "unexpected source-missing pattern at "
                    f"{row.series_id}, {row.year}-{month:02d}"
                )


def write_series_rows(rows: Iterable[SourceRow], path: Path) -> None:
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(
            (
                "source_row",
                "series_id",
                "seasonal_adjustment_code",
                "m3_series_code",
                "item_code",
                "year",
                *MONTH_NAMES,
            )
        )
        for row in rows:
            writer.writerow(
                (
                    row.source_row,
                    row.series_id,
                    row.adjustment_code,
                    row.m3_series_code,
                    row.item_code,
                    row.year,
                    *(value if value is not None else "" for value in row.values),
                )
            )


def identity_rows(
    source_rows: list[SourceRow],
) -> tuple[list[tuple[object, ...]], Counter[str], list[str]]:
    lookup = {
        (row.adjustment_code, row.m3_series_code, row.item_code, row.year): row
        for row in source_rows
    }
    stage_sets = {
        (
            row.adjustment_code,
            row.m3_series_code,
        )
        for row in source_rows
        if row.item_code in {"MI", "WI", "FI"}
    }
    complete_sets = {
        key
        for key in stage_sets
        if all(
            any(
                row.adjustment_code == key[0]
                and row.m3_series_code == key[1]
                and row.item_code == item
                for row in source_rows
            )
            for item in ITEM_LABELS
        )
    }
    if complete_sets != stage_sets:
        raise ValueError("stage series exist without an exact total counterpart")
    if len(complete_sets) != EXPECTED_STAGE_IDENTITY_SET_COUNT:
        raise ValueError(
            f"unexpected stage-identity set count {len(complete_sets)}"
        )

    output: list[tuple[object, ...]] = []
    statuses: Counter[str] = Counter()
    for adjustment_code, m3_series_code in sorted(complete_sets):
        for year in range(EXPECTED_YEAR_MINIMUM, EXPECTED_YEAR_MAXIMUM + 1):
            item_rows = {
                item: lookup[
                    (adjustment_code, m3_series_code, item, year)
                ]
                for item in ITEM_LABELS
            }
            for month in range(1, 13):
                values = {
                    item: row.values[month - 1]
                    for item, row in item_rows.items()
                }
                if all(value is None for value in values.values()):
                    status = "NOT_RUN_SOURCE_MISSING"
                    residual: int | str = ""
                elif any(value is None for value in values.values()):
                    raise ValueError(
                        "partial stage identity at "
                        f"{adjustment_code}{m3_series_code}, "
                        f"{year}-{month:02d}"
                    )
                else:
                    residual = (
                        int(values["TI"])
                        - int(values["MI"])
                        - int(values["WI"])
                        - int(values["FI"])
                    )
                    status = (
                        "PASS_EXACT_SOURCE_IDENTITY"
                        if residual == 0
                        else "FAIL_SOURCE_IDENTITY"
                    )
                statuses[status] += 1
                output.append(
                    (
                        (
                            f"{adjustment_code}{m3_series_code}_"
                            f"{year}-{month:02d}"
                        ),
                        adjustment_code,
                        m3_series_code,
                        f"{year}-{month:02d}",
                        f"{adjustment_code}{m3_series_code}TI",
                        f"{adjustment_code}{m3_series_code}MI",
                        f"{adjustment_code}{m3_series_code}WI",
                        f"{adjustment_code}{m3_series_code}FI",
                        values["TI"] if values["TI"] is not None else "",
                        values["MI"] if values["MI"] is not None else "",
                        values["WI"] if values["WI"] is not None else "",
                        values["FI"] if values["FI"] is not None else "",
                        residual,
                        status,
                    )
                )
    expected_statuses = Counter(
        {
            "PASS_EXACT_SOURCE_IDENTITY": EXPECTED_IDENTITY_OBSERVED_COUNT,
            "NOT_RUN_SOURCE_MISSING": EXPECTED_IDENTITY_MISSING_COUNT,
        }
    )
    if len(output) != EXPECTED_IDENTITY_CHECK_COUNT:
        raise ValueError(f"unexpected identity row count {len(output)}")
    if statuses != expected_statuses:
        raise ValueError(f"unexpected identity statuses {statuses}")
    stage_codes = sorted(
        f"{adjustment}{m3_code}"
        for adjustment, m3_code in complete_sets
    )
    return output, statuses, stage_codes


def write_identity_rows(rows: Iterable[tuple[object, ...]], path: Path) -> None:
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(
            (
                "check_id",
                "seasonal_adjustment_code",
                "m3_series_code",
                "reference_period",
                "total_series_id",
                "materials_series_id",
                "work_in_process_series_id",
                "finished_goods_series_id",
                "total_millions",
                "materials_millions",
                "work_in_process_millions",
                "finished_goods_millions",
                "residual_millions",
                "status",
            )
        )
        writer.writerows(rows)


def toml_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=True)


def toml_array(values: Iterable[str]) -> str:
    return "[" + ", ".join(toml_string(value) for value in values) + "]"


def write_manifest(
    path: Path,
    receipt: dict[str, object],
    series_rows_path: Path,
    identity_rows_path: Path,
    stage_codes: list[str],
) -> None:
    headers = receipt["selected_response_headers"]
    if not isinstance(headers, dict):
        raise ValueError("source receipt headers are not an object")
    lines = [
        f"schema_version = {toml_string(SCHEMA_VERSION)}",
        f"classification = {toml_string(CLASSIFICATION)}",
        'promotion_status = "RESEARCH_ONLY_NOT_PROMOTED"',
        f"source_url = {toml_string(SOURCE_URL)}",
        f"retrieved_at_utc = {toml_string(str(receipt['retrieved_at_utc']))}",
        (
            "source_last_modified = "
            f"{toml_string(str(headers.get('last-modified', '')))}"
        ),
        (
            "workbook_internal_period_hint = "
            f"{toml_string(str(receipt['workbook_internal_period_hint']))}"
        ),
        f"source_workbook_sha256 = {toml_string(EXPECTED_WORKBOOK_SHA256)}",
        f"source_workbook_byte_count = {EXPECTED_WORKBOOK_BYTE_COUNT}",
        f"source_receipt_sha256 = {toml_string(EXPECTED_RECEIPT_SHA256)}",
        'source_workbook_vintage = "CURRENT_MUTABLE_CAPTURE_NOT_IMMUTABLE_RELEASE"',
        'source_revision_status = "NOT_ENCODED_PER_CELL_IN_WORKBOOK"',
        "forecast_origin_admissible = false",
        "economy_wide_scope_claimed = false",
        "bea_allocation_applied = false",
        "commodity_holder_crosswalk_applied = false",
        "transition_emitted = false",
        "model_inventory_vector_emitted = false",
        "model_state_write = false",
        'accounting_gate_effect = "NONE"',
        'forecast_score_effect = "NONE"',
        "",
        "[source_semantics]",
        'scope = "DOMESTIC_MANUFACTURING_M3_SURVEY_ONLY"',
        'frequency = "MONTHLY"',
        'time_basis = "END_OF_MONTH_STOCK_LEVEL"',
        (
            'about_page_valuation_basis = '
            '"CURRENT_COST_OR_MARKET_VALUE"'
        ),
        (
            'historical_documentation_valuation_basis = '
            '"MILLIONS_OF_DOLLARS_AT_CURRENT_MARKET"'
        ),
        (
            'definitions_page_valuation_basis = '
            '"COST_USING_ANY_VALUATION_METHOD_OTHER_THAN_LIFO"'
        ),
        'price_adjustment = "NOT_ADJUSTED_FOR_PRICE_CHANGES"',
        'adjusted_code = "A"',
        'unadjusted_code = "U"',
        'total_code = "TI"',
        'materials_code = "MI"',
        'work_in_process_code = "WI"',
        'finished_goods_code = "FI"',
        'missing_value_policy = "ABSENT_CELL_IS_SOURCE_MISSING_NOT_ZERO"',
        'zero_policy = "NUMERIC_ZERO_IS_EXPLICIT_ZERO_DISTINCT_FROM_MISSING"',
        (
            'revision_policy = "CURRENT_WORKBOOK_CAN_REVISE_HISTORY; '
            'NO_PSEUDO_VINTAGE_OR_FIRST_RELEASE_CLAIM"'
        ),
        "",
        "[source_method]",
        "stage_control_allocation_is_census_method = true",
        (
            'unadjusted_stage_method = "THREE_DIGIT_NAICS_TOTAL_INVENTORY_'
            'CONTROL; INITIAL_STAGE_RATIO_ESTIMATES; DIFFERENCE_'
            'PROPORTIONALLY_ALLOCATED_TO_STAGES"'
        ),
        (
            'seasonally_adjusted_stage_method = "STAGES_SEASONALLY_ADJUSTED_'
            'AT_THREE_DIGIT_NAICS; DIFFERENCE_TO_ADJUSTED_TOTAL_'
            'PROPORTIONALLY_ALLOCATED_TO_STAGES"'
        ),
        (
            'reason = "SIGNIFICANT_NUMBER_OF_COMPANIES_REPORT_TOTAL_'
            'INVENTORIES_BUT_CANNOT_REPORT_STAGE_DETAIL"'
        ),
        "independent_stage_measurement_claimed = false",
        "project_allocation_applied = false",
        (
            'identity_interpretation = "PUBLISHED_CONTROLLED_ACCOUNTING_'
            'IDENTITY_NOT_INDEPENDENT_STAGE_VALIDATION"'
        ),
        "",
        "[expected]",
        f"source_row_count = {EXPECTED_SOURCE_ROW_COUNT}",
        f"source_series_count = {EXPECTED_SERIES_COUNT}",
        f"adjusted_series_count = {EXPECTED_ADJUSTED_SERIES_COUNT}",
        f"unadjusted_series_count = {EXPECTED_UNADJUSTED_SERIES_COUNT}",
        "total_series_count = 172",
        "materials_series_count = 48",
        "work_in_process_series_count = 48",
        "finished_goods_series_count = 48",
        f"year_minimum = {EXPECTED_YEAR_MINIMUM}",
        f"year_maximum = {EXPECTED_YEAR_MAXIMUM}",
        f"source_cell_count = {EXPECTED_SOURCE_CELL_COUNT}",
        f"numeric_cell_count = {EXPECTED_NUMERIC_CELL_COUNT}",
        f"missing_cell_count = {EXPECTED_MISSING_CELL_COUNT}",
        "explicit_zero_count = 0",
        "negative_count = 0",
        f"stage_identity_set_count = {EXPECTED_STAGE_IDENTITY_SET_COUNT}",
        f"identity_check_count = {EXPECTED_IDENTITY_CHECK_COUNT}",
        f"identity_exact_pass_count = {EXPECTED_IDENTITY_OBSERVED_COUNT}",
        f"identity_source_missing_count = {EXPECTED_IDENTITY_MISSING_COUNT}",
        "identity_partial_missing_count = 0",
        "identity_failure_count = 0",
        "maximum_absolute_identity_residual_millions = 0",
        'latest_observed_period = "2026-06"',
        'missing_period_start = "2026-07"',
        'missing_period_end = "2026-12"',
        f"stage_identity_series_codes = {toml_array(stage_codes)}",
        "",
        "[citations]",
        f"historical_documentation_url = {toml_string(HISTORICAL_DOCUMENTATION_URL)}",
        f"time_series_url = {toml_string(TIME_SERIES_URL)}",
        f"methodology_url = {toml_string(METHODOLOGY_URL)}",
        f"definitions_url = {toml_string(DEFINITIONS_URL)}",
        f"about_url = {toml_string(ABOUT_URL)}",
        "",
        "[artifacts]",
        (
            "series_rows_sha256 = "
            f"{toml_string(file_sha256(series_rows_path))}"
        ),
        (
            "identity_checks_sha256 = "
            f"{toml_string(file_sha256(identity_rows_path))}"
        ),
        "",
        "[blocked_boundaries]",
        "economy_wide_bea_allocation = true",
        "commodity_holder_crosswalk = true",
        "stage_to_model_stock_scope_bridge = true",
        "stock_flow_transition = true",
        "current_vintage_to_forecast_origin = true",
        "model_state_write = true",
        "accounting_gate = true",
        "forecast_score = true",
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=DEFAULT_RAW_SOURCE)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    source = arguments.source_dir.resolve()
    output = arguments.output_dir.resolve()
    workbook_path = source / "naicsinvp.xlsx"
    receipt_path = source / "source_receipt.json"
    if file_sha256(receipt_path) != EXPECTED_RECEIPT_SHA256:
        raise ValueError("source receipt SHA-256 mismatch")
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    if receipt["request_url"] != SOURCE_URL:
        raise ValueError("source receipt URL mismatch")
    if receipt["sha256"] != EXPECTED_WORKBOOK_SHA256:
        raise ValueError("source receipt workbook SHA-256 mismatch")
    if receipt["byte_count"] != EXPECTED_WORKBOOK_BYTE_COUNT:
        raise ValueError("source receipt workbook byte-count mismatch")
    if receipt["immutable_release_vintage_claimed"]:
        raise ValueError("source receipt falsely claims an immutable vintage")

    rows = parse_source_rows(workbook_path)
    identities, _, stage_codes = identity_rows(rows)
    output.mkdir(parents=True, exist_ok=True)
    series_rows_path = output / "series_rows.csv"
    identity_rows_path = output / "identity_checks.csv"
    manifest_path = output / "manifest.toml"
    write_series_rows(rows, series_rows_path)
    write_identity_rows(identities, identity_rows_path)
    write_manifest(
        manifest_path,
        receipt,
        series_rows_path,
        identity_rows_path,
        stage_codes,
    )
    print(f"source_row_count={len(rows)}")
    print(f"identity_check_count={len(identities)}")
    print(f"series_rows_sha256={file_sha256(series_rows_path)}")
    print(f"identity_checks_sha256={file_sha256(identity_rows_path)}")
    print(f"manifest_sha256={file_sha256(manifest_path)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
