#!/usr/bin/env python3

from __future__ import annotations

import copy
import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest
import warnings
import xml.etree.ElementTree as ET
import zipfile
from dataclasses import replace
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True

MODULE_PATH = Path(__file__).with_name(
    "fingerprint_historical_releases.py"
).resolve()
SPEC = importlib.util.spec_from_file_location(
    "fingerprint_historical_releases",
    MODULE_PATH,
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load historical fingerprint parser")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)

M = MODULE.MAIN_NS
R = MODULE.OFFICE_REL_NS
P = MODULE.PACKAGE_REL_NS
XML_SPACE = "http://www.w3.org/XML/1998/namespace"
SYNTHETIC_END = "1997Q2"
SYNTHETIC_VALUES = {
    "nominal_gdp": "1000",
    "real_gdp": "2000",
    "gdp_deflator": "100.123",
    "pce_price_index": "101.234",
    "core_pce_price_index": "102.345",
}


def xml_bytes(root: ET.Element) -> bytes:
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def text_cell(address: str, value: str) -> ET.Element:
    cell = ET.Element(f"{{{M}}}c", {"r": address, "t": "inlineStr"})
    inline = ET.SubElement(cell, f"{{{M}}}is")
    text = ET.SubElement(
        inline,
        f"{{{M}}}t",
        {f"{{{XML_SPACE}}}space": "preserve"},
    )
    text.text = value
    return cell


def numeric_cell(
    address: str,
    value: str,
    style_index: int,
    *,
    formula: bool = False,
    error: bool = False,
) -> ET.Element:
    attributes = {"r": address, "s": str(style_index)}
    if error:
        attributes["t"] = "e"
    cell = ET.Element(f"{{{M}}}c", attributes)
    if formula:
        formula_node = ET.SubElement(cell, f"{{{M}}}f")
        formula_node.text = "1+1"
    value_node = ET.SubElement(cell, f"{{{M}}}v")
    value_node.text = "#N/A" if error else value
    return cell


def worksheet_bytes(
    targets: tuple[object, ...],
    release: object,
    file_created_text: str,
    *,
    mutation: str | None = None,
) -> bytes:
    root = ET.Element(f"{{{M}}}worksheet")
    last_row = max(target.sheet_last_row for target in targets)
    ET.SubElement(
        root,
        f"{{{M}}}dimension",
        {"ref": f"A1:{release.terminal_column}{last_row}"},
    )
    sheet_data = ET.SubElement(root, f"{{{M}}}sheetData")
    periods = MODULE.quarter_sequence(MODULE.REFERENCE_START, release.reference_end)
    first_target = targets[0]
    cells: dict[int, dict[str, ET.Element]] = {}

    def add(row: int, cell: ET.Element) -> None:
        address = cell.attrib["r"]
        cells.setdefault(row, {})[address] = cell

    headers = {
        "A1": first_target.table_title,
        "A2": first_target.units_text,
        "A3": (
            f"Quarterly data from {MODULE.REFERENCE_START} "
            f"to {release.reference_end}"
        ),
        "A4": MODULE.SOURCE_TEXT,
        "A5": release.data_published_text,
        "A6": file_created_text,
        "A8": "Line",
    }
    for address, value in headers.items():
        add(int(MODULE.CELL_PATTERN.fullmatch(address)[2]), text_cell(address, value))

    for offset, period in enumerate(periods):
        column = MODULE.column_name(MODULE.column_number("D") + offset)
        value = (
            "WRONG_PERIOD"
            if mutation == "period_axis" and offset == len(periods) - 1
            else period
        )
        add(8, text_cell(f"{column}8", value))

    for target in targets:
        row = target.physical_row_number
        add(row, text_cell(f"A{row}", str(target.published_line_number)))
        add(row, text_cell(f"B{row}", target.source_concept_text))
        series_code = (
            "MAPPING_DRIFT"
            if mutation == f"mapping:{target.target_id}"
            else target.series_code
        )
        add(row, text_cell(f"C{row}", series_code))
        for offset in range(len(periods)):
            column = MODULE.column_name(MODULE.column_number("D") + offset)
            address = f"{column}{row}"
            latest = offset == len(periods) - 1
            value = SYNTHETIC_VALUES[target.target_id]
            if mutation == f"missing:{target.target_id}" and latest:
                cell = text_cell(address, MODULE.MISSING_MARKER)
            else:
                style_index = 1 if target.decimal_places == 0 else 2
                if mutation == f"style:{target.target_id}" and latest:
                    style_index = 0
                cell = numeric_cell(
                    address,
                    value,
                    style_index,
                    formula=(
                        mutation == f"formula:{target.target_id}" and latest
                    ),
                    error=(
                        mutation == f"error:{target.target_id}" and latest
                    ),
                )
            add(row, cell)

    for row_number in sorted(cells):
        row = ET.SubElement(
            sheet_data,
            f"{{{M}}}row",
            {"r": str(row_number)},
        )
        for _address, cell in sorted(
            cells[row_number].items(),
            key=lambda item: MODULE.column_number(
                MODULE.CELL_PATTERN.fullmatch(item[0])[1]
            ),
        ):
            row.append(cell)
    return xml_bytes(root)


def styles_bytes() -> bytes:
    root = ET.Element(f"{{{M}}}styleSheet")
    formats = ET.SubElement(root, f"{{{M}}}numFmts", {"count": "1"})
    ET.SubElement(
        formats,
        f"{{{M}}}numFmt",
        {"numFmtId": "165", "formatCode": "#,##0.000"},
    )
    cell_formats = ET.SubElement(root, f"{{{M}}}cellXfs", {"count": "3"})
    for identifier in ("0", "3", "165"):
        ET.SubElement(cell_formats, f"{{{M}}}xf", {"numFmtId": identifier})
    return xml_bytes(root)


def workbook_xml(sheet_names: list[str]) -> bytes:
    root = ET.Element(f"{{{M}}}workbook")
    sheets = ET.SubElement(root, f"{{{M}}}sheets")
    for index, name in enumerate(sheet_names, start=1):
        ET.SubElement(
            sheets,
            f"{{{M}}}sheet",
            {
                "name": name,
                "sheetId": str(index),
                f"{{{R}}}id": f"rId{index}",
            },
        )
    return xml_bytes(root)


def relationship_xml(
    sheet_count: int,
    *,
    alias_first_target: bool,
) -> bytes:
    root = ET.Element(f"{{{P}}}Relationships")
    for index in range(1, sheet_count + 1):
        target_index = 1 if alias_first_target and index == sheet_count else index
        ET.SubElement(
            root,
            f"{{{P}}}Relationship",
            {
                "Id": f"rId{index}",
                "Type": MODULE.WORKSHEET_REL_TYPE,
                "Target": f"worksheets/sheet{target_index}.xml",
            },
        )
    return xml_bytes(root)


def deterministic_zip(parts: list[tuple[str, bytes]]) -> bytes:
    output = io.BytesIO()
    with zipfile.ZipFile(
        output,
        "w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
    ) as archive:
        for name, data in parts:
            info = zipfile.ZipInfo(name, (2020, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100600 << 16
            archive.writestr(info, data)
    return output.getvalue()


def synthetic_workbook(
    section_id: str,
    release: object,
    *,
    mutation: str | None = None,
) -> tuple[bytes, list[tuple[str, str]]]:
    targets_by_sheet: dict[str, list[object]] = {}
    for target in MODULE.TARGET_SPECS:
        if target.section_id == section_id:
            targets_by_sheet.setdefault(target.sheet_name, []).append(target)
    sheet_names = list(targets_by_sheet)
    if mutation == "extra_critical" and section_id == "1":
        sheet_names.append("T20304-Q")
    if mutation == "relationship_alias" and section_id == "1":
        sheet_names.append("Alias")

    manifest = [
        (name, f"xl/worksheets/sheet{index}.xml")
        for index, name in enumerate(sheet_names, start=1)
    ]
    parts = [
        ("[Content_Types].xml", b"<Types/>"),
        ("_rels/.rels", b"<Relationships/>"),
        ("xl/workbook.xml", workbook_xml(sheet_names)),
        (
            "xl/_rels/workbook.xml.rels",
            relationship_xml(
                len(sheet_names),
                alias_first_target=mutation == "relationship_alias",
            ),
        ),
        ("xl/styles.xml", styles_bytes()),
    ]
    for index, name in enumerate(sheet_names, start=1):
        if name in targets_by_sheet:
            targets = tuple(targets_by_sheet[name])
        else:
            targets = (
                next(
                    target
                    for target in MODULE.TARGET_SPECS
                    if target.sheet_name == "T20304-Q"
                ),
            )
        file_created = (
            "Synthetic Section 1"
            if section_id == "1"
            else "Synthetic Section 2"
        )
        parts.append(
            (
                f"xl/worksheets/sheet{index}.xml",
                worksheet_bytes(
                    targets,
                    release,
                    file_created,
                    mutation=mutation,
                ),
            )
        )
    return deterministic_zip(parts), manifest


def provisional_release() -> object:
    terminal = MODULE.column_name(
        MODULE.column_number("D")
        + len(MODULE.quarter_sequence(MODULE.REFERENCE_START, SYNTHETIC_END))
        - 1
    )
    placeholder = MODULE.WorkbookSpec(
        workbook_id="synthetic_s1",
        section_id="1",
        filename="Section1all_xls.xlsx",
        source_url="https://example.test/s1.xlsx",
        sha256="0" * 64,
        byte_count=1,
        expected_sheet_count=3,
        expected_sheet_manifest_sha256="0" * 64,
        file_created_text="Synthetic Section 1",
    )
    return MODULE.ReleaseSpec(
        release_id="synthetic_release",
        capture_id="synthetic_capture",
        reference_quarter=SYNTHETIC_END,
        estimate_label="synthetic",
        archive_directory_id="99999",
        archive_relative_path="synthetic/path",
        release_page_url="https://example.test/release",
        release_event_timestamp_utc="1997-08-01T00:00:00.000Z",
        data_published_text="Synthetic publication",
        reference_end=SYNTHETIC_END,
        terminal_column=terminal,
        annual_update_caveat="SYNTHETIC_NO_SOURCE_SEMANTICS",
        raw_pair_sha256="0" * 64,
        latest_published_values=tuple(SYNTHETIC_VALUES.items()),
        workbooks=(placeholder, replace(placeholder, section_id="2")),
    )


def make_synthetic_pair(
    root: Path,
    *,
    mutation: str | None = None,
) -> tuple[object, dict[str, Path]]:
    release = provisional_release()
    workbooks = []
    paths = {}
    for section_id in ("1", "2"):
        section_mutation = mutation
        data, manifest = synthetic_workbook(
            section_id,
            release,
            mutation=section_mutation,
        )
        path = root / f"section-{section_id}.xlsx"
        path.write_bytes(data)
        paths[section_id] = path
        workbooks.append(
            MODULE.WorkbookSpec(
                workbook_id=f"synthetic_s{section_id}",
                section_id=section_id,
                filename=f"Section{section_id}all_xls.xlsx",
                source_url=f"https://example.test/s{section_id}.xlsx",
                sha256=MODULE.sha256_bytes(data),
                byte_count=len(data),
                expected_sheet_count=len(manifest),
                expected_sheet_manifest_sha256=(
                    MODULE.sheet_manifest_sha256(manifest)
                ),
                file_created_text=(
                    "Synthetic Section 1"
                    if section_id == "1"
                    else "Synthetic Section 2"
                ),
            )
        )
    release = replace(release, workbooks=tuple(workbooks))
    release = replace(
        release,
        raw_pair_sha256=MODULE.expected_pair_sha256(release),
    )
    return release, paths


class HistoricalFingerprintTests(unittest.TestCase):
    def test_pinned_identities_and_profiles(self) -> None:
        self.assertEqual(len(MODULE.RELEASE_SPECS), 2)
        self.assertEqual(
            MODULE.mapping_profile_sha256(),
            "8ed3038e7ea80c7207d57cabad6f2b8a50ea5bbe2e04587b63c7b5d242230171",
        )
        first, second = MODULE.RELEASE_SPECS
        self.assertEqual(first.reference_quarter, "2019Q4")
        self.assertEqual(first.terminal_column, "KI")
        self.assertEqual(first.raw_pair_sha256, MODULE.expected_pair_sha256(first))
        self.assertEqual(
            MODULE.release_profile_sha256(first),
            "c4481a6df9174b756be0257331bd6010cb1e53f698161cd85088f33bf85bf23c",
        )
        self.assertEqual(
            first.release_page_url,
            "https://www.bea.gov/news/2020/"
            "gross-domestic-product-fourth-quarter-and-year-2019-advance-estimate",
        )
        self.assertEqual(
            [workbook.expected_sheet_count for workbook in first.workbooks],
            [107, 39],
        )
        self.assertEqual(second.reference_quarter, "2021Q2")
        self.assertEqual(second.terminal_column, "KO")
        self.assertEqual(
            second.raw_pair_sha256,
            MODULE.expected_pair_sha256(second),
        )
        self.assertEqual(
            MODULE.release_profile_sha256(second),
            "6788c9f35f35f53c3e089085367e8205e06ad48ddebb6d09a601273ef70852e8",
        )
        self.assertEqual(
            second.release_page_url,
            "https://www.bea.gov/news/2021/"
            "gross-domestic-product-second-quarter-2021-advance-estimate-and-"
            "annual-update",
        )
        self.assertEqual(
            [workbook.expected_sheet_count for workbook in second.workbooks],
            [107, 38],
        )
        self.assertIn("ANNUAL_UPDATE", second.annual_update_caveat)
        self.assertEqual(
            {
                workbook.sha256
                for release in MODULE.RELEASE_SPECS
                for workbook in release.workbooks
            },
            {
                "35b170c5c82980a0dfea5cb6db45f2851fc3a3e4dfbbb37773ec71f23b44501a",
                "8f3935eb2ae44fea9066cdac632f38b858cfbd74731756db2461123726fb6028",
                "ccc7a5cf63de4022613404d05bcb2a0a1689875d5c45bcc5f3386ae09eec9ffb",
                "84dff5de137cd3043e0392798875c1bb80a9190c4bddfdb76f495163cdf1ff9a",
            },
        )

    def test_exact_mapping_and_latest_values(self) -> None:
        self.assertEqual(len(MODULE.TARGET_SPECS), 5)
        mappings = {
            target.target_id: (
                target.sheet_name,
                target.published_line_number,
                target.physical_row_number,
                target.series_code,
            )
            for target in MODULE.TARGET_SPECS
        }
        self.assertEqual(
            mappings,
            {
                "nominal_gdp": ("T10105-Q", 1, 9, "A191RC"),
                "real_gdp": ("T10106-Q", 1, 9, "A191RX"),
                "gdp_deflator": ("T10109-Q", 1, 9, "A191RD"),
                "pce_price_index": ("T20304-Q", 1, 9, "DPCERG"),
                "core_pce_price_index": (
                    "T20304-Q",
                    25,
                    34,
                    "DPCCRG",
                ),
            },
        )
        self.assertEqual(
            dict(MODULE.RELEASE_SPECS[0].latest_published_values),
            {
                "nominal_gdp": "21734266",
                "real_gdp": "19219767",
                "gdp_deflator": "113.083",
                "pce_price_index": "110.352",
                "core_pce_price_index": "112.366",
            },
        )
        self.assertEqual(
            dict(MODULE.RELEASE_SPECS[1].latest_published_values)[
                "core_pce_price_index"
            ],
            "116.716",
        )

    def test_synthetic_pair_builds_full_history_and_false_gates(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            release, paths = make_synthetic_pair(root)
            artifact = MODULE._build_artifact(
                release,
                root,
                paths,
                parser_path=MODULE_PATH,
                pinned=False,
            )
        self.assertEqual(len(artifact["workbooks"]), 2)
        self.assertEqual(len(artifact["targets"]), 5)
        self.assertEqual(
            artifact["artifact"]["parser_sha256"],
            MODULE.sha256_file(MODULE_PATH),
        )
        for container in (
            [artifact["artifact"], artifact["release"]]
            + artifact["workbooks"]
            + artifact["targets"]
        ):
            self.assertEqual(container["gates"], MODULE.false_gates())
        for target in artifact["targets"]:
            self.assertEqual(target["reference_period_start"], "1947Q1")
            self.assertEqual(target["reference_period_end"], SYNTHETIC_END)
            self.assertEqual(
                len(target["observations"]),
                target["reference_period_count"],
            )
            self.assertTrue(
                target["complete_numeric_window"]["all_values_numeric"]
            )
            self.assertEqual(
                target["latest_published_value_text"],
                SYNTHETIC_VALUES[target["target_id"]],
            )

    def test_mapping_period_formula_error_missing_and_style_drift_fail(self) -> None:
        mutations = (
            "mapping:nominal_gdp",
            "period_axis",
            "formula:real_gdp",
            "error:gdp_deflator",
            "missing:pce_price_index",
            "style:core_pce_price_index",
        )
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                with tempfile.TemporaryDirectory() as temporary:
                    root = Path(temporary).resolve()
                    release, paths = make_synthetic_pair(
                        root,
                        mutation=mutation,
                    )
                    with self.assertRaises(MODULE.FingerprintError):
                        MODULE._build_artifact(
                            release,
                            root,
                            paths,
                            parser_path=MODULE_PATH,
                            pinned=False,
                        )

    def test_extra_critical_sheet_and_relationship_alias_fail(self) -> None:
        for mutation in ("extra_critical", "relationship_alias"):
            with self.subTest(mutation=mutation):
                with tempfile.TemporaryDirectory() as temporary:
                    root = Path(temporary).resolve()
                    release, paths = make_synthetic_pair(
                        root,
                        mutation=mutation,
                    )
                    with self.assertRaises(MODULE.FingerprintError):
                        MODULE._build_artifact(
                            release,
                            root,
                            paths,
                            parser_path=MODULE_PATH,
                            pinned=False,
                        )

    def test_raw_hash_size_and_partial_pair_fail(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            release, paths = make_synthetic_pair(root)
            with self.assertRaises(MODULE.FingerprintError):
                MODULE._build_artifact(
                    release,
                    root,
                    {"1": paths["1"]},
                    parser_path=MODULE_PATH,
                    pinned=False,
                )
            wrong_size = replace(
                release.workbooks[0],
                byte_count=release.workbooks[0].byte_count + 1,
            )
            size_release = replace(
                release,
                workbooks=(wrong_size, release.workbooks[1]),
            )
            size_release = replace(
                size_release,
                raw_pair_sha256=MODULE.expected_pair_sha256(size_release),
            )
            with self.assertRaises(MODULE.FingerprintError):
                MODULE._build_artifact(
                    size_release,
                    root,
                    paths,
                    parser_path=MODULE_PATH,
                    pinned=False,
                )
            data = bytearray(paths["1"].read_bytes())
            data[-1] ^= 1
            paths["1"].write_bytes(data)
            with self.assertRaises(MODULE.FingerprintError):
                MODULE._build_artifact(
                    release,
                    root,
                    paths,
                    parser_path=MODULE_PATH,
                    pinned=False,
                )

    def test_workbook_swap_after_identity_check_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            release, paths = make_synthetic_pair(root)
            original = MODULE.validate_workbook_identity
            swapped = False

            def validate_then_swap(path: Path, workbook: object) -> bytes:
                nonlocal swapped
                data = original(path, workbook)
                if workbook.section_id == "1" and not swapped:
                    swapped = True
                    with zipfile.ZipFile(path, "a") as archive:
                        archive.writestr("docProps/after-check.xml", b"<x/>")
                return data

            with mock.patch.object(
                MODULE,
                "validate_workbook_identity",
                side_effect=validate_then_swap,
            ):
                with self.assertRaises(MODULE.FingerprintError):
                    MODULE._build_artifact(
                        release,
                        root,
                        paths,
                        parser_path=MODULE_PATH,
                        pinned=False,
                    )

    def test_mapping_profile_drift_is_rejected(self) -> None:
        changed = list(MODULE.TARGET_SPECS)
        changed[0] = replace(changed[0], series_code="DRIFT")
        with self.assertRaises(MODULE.FingerprintError):
            MODULE.validate_canonical_mapping_specs(tuple(changed))
        changed_release = replace(
            MODULE.RELEASE_SPECS[0],
            data_published_text="drift",
        )
        with self.assertRaises(MODULE.FingerprintError):
            MODULE.validate_release_spec(changed_release, pinned=True)

    def test_zip_traversal_duplicates_case_aliases_and_links_fail(self) -> None:
        cases = (
            [("../escape", b"x")],
            [("xl\\evil.xml", b"x")],
            [("A.xml", b"x"), ("a.xml", b"y")],
        )
        for parts in cases:
            with self.subTest(parts=[name for name, _ in parts]):
                data = deterministic_zip(parts)
                with zipfile.ZipFile(io.BytesIO(data)) as archive:
                    with self.assertRaises(MODULE.FingerprintError):
                        MODULE.validate_zip_members(archive)

        output = io.BytesIO()
        with zipfile.ZipFile(output, "w") as archive:
            link = zipfile.ZipInfo("link")
            link.external_attr = 0o120777 << 16
            archive.writestr(link, b"target")
        with zipfile.ZipFile(io.BytesIO(output.getvalue())) as archive:
            with self.assertRaises(MODULE.FingerprintError):
                MODULE.validate_zip_members(archive)

        output = io.BytesIO()
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(output, "w") as archive:
                archive.writestr("same", b"x")
                archive.writestr("same", b"y")
        with zipfile.ZipFile(io.BytesIO(output.getvalue())) as archive:
            with self.assertRaises(MODULE.FingerprintError):
                MODULE.validate_zip_members(archive)

    def test_unsafe_raw_paths_and_path_aliases_fail(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            release, paths = make_synthetic_pair(root)
            with self.assertRaises(MODULE.FingerprintError):
                MODULE.safe_raw_path(Path("relative"), Path("relative/book"))
            outside = root.parent / f"{root.name}-outside.xlsx"
            outside.write_bytes(b"PK\x03\x04outside")
            try:
                with self.assertRaises(MODULE.FingerprintError):
                    MODULE.safe_raw_path(root, outside)
            finally:
                outside.unlink()
            link = root / "link.xlsx"
            link.symlink_to(paths["1"])
            with self.assertRaises(MODULE.FingerprintError):
                MODULE.safe_raw_path(root, link)
            with self.assertRaises(MODULE.FingerprintError):
                MODULE._build_artifact(
                    release,
                    root,
                    {"1": paths["1"], "2": paths["1"]},
                    parser_path=MODULE_PATH,
                    pinned=False,
                )

    def test_content_addressing_rejects_tampering_and_promoted_gates(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            output = root / "fingerprints"
            data = MODULE.canonical_json_bytes({"a": 1})
            path = MODULE.write_content_addressed(
                output,
                "synthetic_release",
                data,
            )
            self.assertEqual(path.read_bytes(), data)
            path.write_bytes(b"tampered\n")
            with self.assertRaises(MODULE.FingerprintError):
                MODULE.write_content_addressed(
                    output,
                    "synthetic_release",
                    data,
                )
            with self.assertRaises(MODULE.FingerprintError):
                MODULE.validate_content_addressed_artifact(path)

            release, paths = make_synthetic_pair(root)
            artifact = MODULE._build_artifact(
                release,
                root,
                paths,
                parser_path=MODULE_PATH,
                pinned=False,
            )
            artifact["release"]["gates"]["origin_admissible"] = True
            promoted = MODULE.canonical_json_bytes(artifact)
            promoted_path = root / (
                "promoted-sha256-"
                f"{MODULE.sha256_bytes(promoted)}.json"
            )
            promoted_path.write_bytes(promoted)
            with self.assertRaises(MODULE.FingerprintError):
                MODULE.validate_content_addressed_artifact(promoted_path)

    def test_rehashed_pinned_semantic_tampering_is_rejected(self) -> None:
        checked_in = sorted(
            Path(__file__).with_name("fingerprints").glob(
                "*r2019q4_*.json"
            )
        )
        self.assertEqual(len(checked_in), 1)
        original = json.loads(checked_in[0].read_bytes())

        def install_mutation(root: Path, document: dict) -> Path:
            data = MODULE.canonical_json_bytes(document)
            release_id = document["release"]["release_id"]
            path = root / (
                f"bea-hmi7-{release_id}-content-fingerprint-"
                f"sha256-{MODULE.sha256_bytes(data)}.json"
            )
            path.write_bytes(data)
            return path

        mutations = []
        history = copy.deepcopy(original)
        target = next(
            record
            for record in history["targets"]
            if record["target_id"] == "nominal_gdp"
        )
        target["observations"][-1]["raw_value_text"] = "999999999"
        target["observations"][-1][
            "published_value_text"
        ] = "999999999"
        target["latest_raw_value_text"] = "999999999"
        target["latest_published_value_text"] = "999999999"
        periods = [
            observation["period"] for observation in target["observations"]
        ]
        raw_values = [
            observation["raw_value_text"]
            for observation in target["observations"]
        ]
        published_values = [
            observation["published_value_text"]
            for observation in target["observations"]
        ]
        target["raw_values_sha256"] = MODULE.values_digest(
            periods,
            raw_values,
        )
        target["published_values_sha256"] = MODULE.values_digest(
            periods,
            published_values,
        )
        mutations.append(history)

        raw_identity = copy.deepcopy(original)
        raw_identity["workbooks"][0]["raw_sha256"] = "0" * 64
        mutations.append(raw_identity)

        parser_binding = copy.deepcopy(original)
        parser_binding["artifact"]["parser_sha256"] = "0" * 64
        mutations.append(parser_binding)

        promotion = copy.deepcopy(original)
        promotion["release"]["gates"]["origin_admissible"] = True
        mutations.append(promotion)

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            for index, document in enumerate(mutations):
                with self.subTest(index=index):
                    path = install_mutation(root, document)
                    with self.assertRaises(MODULE.FingerprintError):
                        MODULE.validate_content_addressed_artifact(path)

    def test_checked_in_fingerprints_are_canonical_and_current(self) -> None:
        fingerprint_dir = Path(__file__).with_name("fingerprints")
        paths = sorted(fingerprint_dir.glob("*.json"))
        self.assertEqual(len(paths), 2)
        expected_releases = set(MODULE.RELEASE_BY_ID)
        observed_releases = set()
        for path in paths:
            document = MODULE.validate_content_addressed_artifact(
                path.resolve()
            )
            observed_releases.add(document["release"]["release_id"])
            self.assertEqual(
                document["artifact"]["parser_sha256"],
                MODULE.sha256_file(MODULE_PATH),
            )
            self.assertEqual(len(document["targets"]), 5)
            for target in document["targets"]:
                self.assertEqual(
                    target["complete_numeric_window"]["start"],
                    "1997Q1",
                )
                self.assertTrue(
                    target["complete_numeric_window"]["all_values_numeric"]
                )
        self.assertEqual(observed_releases, expected_releases)


if __name__ == "__main__":
    unittest.main()
