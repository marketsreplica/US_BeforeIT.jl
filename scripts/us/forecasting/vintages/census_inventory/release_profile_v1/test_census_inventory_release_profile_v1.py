#!/usr/bin/env python3
"""Hermetic and adversarial tests for the Census inventory release profile."""

from __future__ import annotations

import copy
import hashlib
import importlib.util
import inspect
import json
import os
import shutil
import sys
import tempfile
import unittest
import warnings
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

HERE = Path(__file__).resolve().parent
MODULE_PATH = HERE / "census_inventory_release_profile_v1.py"
EXPECTED_MODULE_PHYSICAL_SHA256 = (
    "8633647b13b3e795b3d09f1e6503b00b381753c788e12cb5d5e1428b62841788"
)
SPEC = importlib.util.spec_from_file_location("census_inventory_profile", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
Census = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = Census
SPEC.loader.exec_module(Census)

MAIN_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PKG_REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"
CT_NS = "http://schemas.openxmlformats.org/package/2006/content-types"
MAIN = "{" + MAIN_NS + "}"
REL = "{" + REL_NS + "}"
PKG_REL = "{" + PKG_REL_NS + "}"
CT = "{" + CT_NS + "}"

M3_FULL_LABELS = (
    "  All manufacturing industries..........……..…..",
    "    Durable goods industries.....................…..",
    "      Wood products…………..…………………",
    "      Nonmetallic mineral products……………..",
    "      Primary metals……………….…..…………",
    "      Fabricated metal products……………………..      ",
    "      Machinery……………………………………",
    "      Computers and electronic products……..",
    "      Electrical equipment, appliances,",
    "         and components………………………….",
    "      Transportation equipment…………………",
    "      Furniture and related products……………",
    "      Miscellaneous products………...………….",
    "   Nondurable goods industries..............……..",
    "      Food  products...…...........………..……..",
    "      Beverage and tobacco products.....................…",
    "      Textiles.............….....…...…….......……",
    "      Textile products……..………..…………….",
    "      Apparel……………….……………………..",
    "      Leather and allied products…….………….",
    "      Paper products..…………..….….....……..",
    "      Printing ………….………………...………..",
    "      Petroleum and coal products……………..",
    "      Chemical products…………………..………",
    "      Plastics and rubber products……..….……",
)
M3_ADVANCE_LABELS = (
    "All manufacturing industries......……………….",
    "Durable goods industries………….…………...",
    "Nondurable goods industries…….…………...",
    "Food products…..................……………….",
    "Beverage & tobacco products……………..",
    "Textile mills……………….........................",
    "Textile products………………...................",
    "Apparel….............………………...............",
    "Leather & allied products….............……",
    "Paper products….............………............",
    "Printing….............………......................",
    "Petroleum and coal products……………….",
    "Chemical products………………...............",
    "Plastics & rubber prod.……………….........",
)
MRTS_INVENTORY_ROWS = (
    ("", "Retail Inventories, total"),
    ("44,45 excl. 441", "Total excluding  motor vehicle and parts dealers"),
    ("441", "Motor vehicle and parts dealers"),
    (
        "442,443",
        "Furniture, home furn, electronics, and appliance stores",
    ),
    ("444", "Building materials, garden equip. and supplies dealers"),
    ("445", "Food and beverage stores"),
    ("448", "Clothing and clothing access. stores"),
    ("452", "General merchandise stores"),
    ("4522", "Department stores"),
)
MRTS_RATIO_ROWS = (
    ("", "Retail Trade, total"),
    *MRTS_INVENTORY_ROWS[1:],
)
MWTS_CODES_ADJUSTED = (
    "42",
    "423",
    "4231",
    "4232",
    "4233",
    "4234",
    "42343",
    "4235",
    "4236",
    "4237",
    "4238",
    "4239",
    "424",
    "4241 2",
    "4242",
    "4243",
    "4244",
    "4245",
    "4246 3",
    "4247",
    "4248",
    "4249",
)
MWTS_CODES_NOT_ADJUSTED = tuple(
    code.split(" ", 1)[0] for code in MWTS_CODES_ADJUSTED
)
MWTS_DESCRIPTIONS = (
    "Total Merchant\nWholesalers,\nExcept\nManufacturers'\nSales Branches\nand Offices",
    ".Durable\nGoods",
    "..Motor\nVehicle &\nMotor\nVehicle\nParts &\nSupplies",
    "..Furniture\n& Home\nFurnishings",
    "..Lumber &\nOther\nConstruction\nMaterials",
    "..Professional\n& Commercial\nEquipment &\nSupplies",
    "...Computer\n& Computer\nPeripheral\nEquipment\n& Software",
    "..Metals &\nMinerals,\nExcept\nPetroleum",
    "..Household\nAppliances\n& Electrical\n& Electronic\nGoods",
    "..Hardware,\n& Plumbing\n& Heating\nEquipment\n& Supplies",
    "..Machinery,\nEquipment,\n& Supplies",
    "..Miscellaneous\nDurable Goods",
    ".Nondurable\nGoods",
    "..Paper &\nPaper\nProducts",
    "..Drugs &\nDruggists'\nSundries",
    "..Apparel,\nPiece\nGoods, &\nNotions",
    "..Grocery &\nRelated\nProducts",
    "..Farm\nProduct Raw\nMaterials",
    "..Chemicals\n& Allied\nProducts",
    "..Petroleum\n&\nPetroleum\nProducts",
    "..Beer,\nWine, &\nDistilled\nAlcoholic\nBeverages",
    "..Miscellaneous\nNondurable\nGoods",
)


def cell_column(reference: str) -> int:
    letters = "".join(character for character in reference if character.isalpha())
    return Census.excel_column_number(letters)


class WorkbookBuilder:
    def __init__(self, sheet_names: list[str]) -> None:
        self.sheet_names = sheet_names
        self.sheets: dict[str, dict[str, tuple[str, str]]] = {
            name: {} for name in sheet_names
        }
        self.shared: list[str] = []
        self.shared_index: dict[str, int] = {}
        self.shared_occurrences = 0

    def text(self, sheet: str, reference: str, value: str) -> None:
        self.sheets[sheet][reference] = ("s", value)

    def number(self, sheet: str, reference: str, value: int | str) -> None:
        self.sheets[sheet][reference] = ("n", str(value))

    def _shared_id(self, value: str) -> int:
        self.shared_occurrences += 1
        if value not in self.shared_index:
            self.shared_index[value] = len(self.shared)
            self.shared.append(value)
        return self.shared_index[value]

    def _sheet_xml(self, cells: dict[str, tuple[str, str]]) -> bytes:
        root = ET.Element(MAIN + "worksheet")
        if cells:
            max_row = max(int("".join(filter(str.isdigit, key))) for key in cells)
            max_col = max(cell_column(key) for key in cells)
            end = Census.excel_column_letters(max_col) + str(max_row)
            ET.SubElement(root, MAIN + "dimension", {"ref": "A1:" + end})
        else:
            ET.SubElement(root, MAIN + "dimension", {"ref": "A1"})
        sheet_data = ET.SubElement(root, MAIN + "sheetData")
        by_row: dict[int, list[tuple[str, tuple[str, str]]]] = {}
        for reference, record in cells.items():
            row = int("".join(filter(str.isdigit, reference)))
            by_row.setdefault(row, []).append((reference, record))
        for row_number in sorted(by_row):
            row = ET.SubElement(sheet_data, MAIN + "row", {"r": str(row_number)})
            for reference, (cell_type, value) in sorted(
                by_row[row_number], key=lambda item: cell_column(item[0])
            ):
                cell = ET.SubElement(
                    row,
                    MAIN + "c",
                    {"r": reference, "s": "0", "t": cell_type},
                )
                stored = str(self._shared_id(value)) if cell_type == "s" else value
                ET.SubElement(cell, MAIN + "v").text = stored
        return ET.tostring(root, encoding="utf-8", xml_declaration=True)

    def write(self, path: Path) -> None:
        worksheet_payloads = [
            self._sheet_xml(self.sheets[name]) for name in self.sheet_names
        ]
        workbook = ET.Element(MAIN + "workbook")
        sheets = ET.SubElement(workbook, MAIN + "sheets")
        for index, name in enumerate(self.sheet_names, start=1):
            ET.SubElement(
                sheets,
                MAIN + "sheet",
                {
                    "name": name,
                    "sheetId": str(index),
                    REL + "id": "rId" + str(index),
                },
            )
        workbook_rels = ET.Element(PKG_REL + "Relationships")
        for index in range(1, len(self.sheet_names) + 1):
            ET.SubElement(
                workbook_rels,
                PKG_REL + "Relationship",
                {
                    "Id": "rId" + str(index),
                    "Type": REL_NS + "/worksheet",
                    "Target": "worksheets/sheet" + str(index) + ".xml",
                },
            )
        ET.SubElement(
            workbook_rels,
            PKG_REL + "Relationship",
            {
                "Id": "rId" + str(len(self.sheet_names) + 1),
                "Type": REL_NS + "/sharedStrings",
                "Target": "sharedStrings.xml",
            },
        )
        ET.SubElement(
            workbook_rels,
            PKG_REL + "Relationship",
            {
                "Id": "rId" + str(len(self.sheet_names) + 2),
                "Type": REL_NS + "/styles",
                "Target": "styles.xml",
            },
        )
        root_rels = ET.Element(PKG_REL + "Relationships")
        ET.SubElement(
            root_rels,
            PKG_REL + "Relationship",
            {
                "Id": "rId1",
                "Type": REL_NS + "/officeDocument",
                "Target": "xl/workbook.xml",
            },
        )
        shared = ET.Element(
            MAIN + "sst",
            {
                "count": str(self.shared_occurrences),
                "uniqueCount": str(len(self.shared)),
            },
        )
        for value in self.shared:
            item = ET.SubElement(shared, MAIN + "si")
            ET.SubElement(item, MAIN + "t").text = value
        styles = ET.Element(MAIN + "styleSheet")
        cell_xfs = ET.SubElement(styles, MAIN + "cellXfs", {"count": "1"})
        ET.SubElement(cell_xfs, MAIN + "xf", {"numFmtId": "0"})
        content_types = ET.Element(CT + "Types")
        ET.SubElement(
            content_types,
            CT + "Default",
            {
                "Extension": "rels",
                "ContentType": (
                    "application/vnd.openxmlformats-package.relationships+xml"
                ),
            },
        )
        ET.SubElement(
            content_types,
            CT + "Default",
            {"Extension": "xml", "ContentType": "application/xml"},
        )
        overrides = [
            (
                "/xl/workbook.xml",
                "application/vnd.openxmlformats-officedocument."
                "spreadsheetml.sheet.main+xml",
            ),
            (
                "/xl/sharedStrings.xml",
                "application/vnd.openxmlformats-officedocument."
                "spreadsheetml.sharedStrings+xml",
            ),
            (
                "/xl/styles.xml",
                "application/vnd.openxmlformats-officedocument."
                "spreadsheetml.styles+xml",
            ),
        ]
        overrides.extend(
            (
                "/xl/worksheets/sheet" + str(index) + ".xml",
                "application/vnd.openxmlformats-officedocument."
                "spreadsheetml.worksheet+xml",
            )
            for index in range(1, len(self.sheet_names) + 1)
        )
        for part, content_type in overrides:
            ET.SubElement(
                content_types,
                CT + "Override",
                {"PartName": part, "ContentType": content_type},
            )
        payloads = {
            "[Content_Types].xml": ET.tostring(
                content_types, encoding="utf-8", xml_declaration=True
            ),
            "_rels/.rels": ET.tostring(
                root_rels, encoding="utf-8", xml_declaration=True
            ),
            "xl/workbook.xml": ET.tostring(
                workbook, encoding="utf-8", xml_declaration=True
            ),
            "xl/_rels/workbook.xml.rels": ET.tostring(
                workbook_rels, encoding="utf-8", xml_declaration=True
            ),
            "xl/sharedStrings.xml": ET.tostring(
                shared, encoding="utf-8", xml_declaration=True
            ),
            "xl/styles.xml": ET.tostring(
                styles, encoding="utf-8", xml_declaration=True
            ),
        }
        for index, payload in enumerate(worksheet_payloads, start=1):
            payloads["xl/worksheets/sheet" + str(index) + ".xml"] = payload
        with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for name, payload in payloads.items():
                info = zipfile.ZipInfo(name, (2020, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.create_system = 0
                archive.writestr(info, payload)


def make_m3_full(path: Path) -> None:
    profile = Census.load_profile()
    names = profile["structures"]["m3_full_table6"]["sheet_names"]
    builder = WorkbookBuilder(names)
    sheet = "Table 6"
    builder.text(
        sheet,
        "A2",
        "Table 6.  Value of Manufacturers' Inventories, by Stage of "
        "Fabrication, by Industry Group1  ",
    )
    builder.text(
        sheet,
        "A5",
        "[Estimates are shown in millions of dollars and are based on data "
        "from the Manufacturers' Shipments, Inventories, and Orders Survey.]  ",
    )
    for reference, value in {
        "C6": "Seasonally Adjusted",
        "I6": "Not Seasonally Adjusted",
        "C7": "Monthly",
        "F7": "Percent Change",
        "I7": "Monthly",
        "M7": "% Change",
        "A8": "Industry",
        "C9": "Aug.",
        "D9": "July",
        "E9": "June",
        "C10": "2026p",
        "D10": "2026r",
        "I9": "Aug.",
        "J9": "July",
        "K9": "June",
        "I10": "2026p",
        "J10": "2026r",
        "L9": "Aug.",
        "M8": "Aug.",
        "M9": "2026/",
    }.items():
        builder.text(sheet, reference, value)
    for reference, value in {
        "E10": 2026,
        "K10": 2026,
        "L10": 2025,
        "M10": 2025,
    }.items():
        builder.number(sheet, reference, value)
    for stage_index, (offset, header) in enumerate(
        ((0, "MATERIALS AND SUPPLIES"), (30, "WORK IN PROCESS"), (60, "FINISHED GOODS"))
    ):
        builder.text(sheet, f"A{13 + offset}", header)
        for index, (row, label) in enumerate(
            zip(Census.M3_FULL_LABEL_ROWS, M3_FULL_LABELS)
        ):
            builder.text(sheet, f"A{row + offset}", label)
            if index != 8:
                builder.number(
                    sheet,
                    f"C{row + offset}",
                    100000 * (stage_index + 1) + row,
                )
                builder.number(
                    sheet,
                    f"I{row + offset}",
                    200000 * (stage_index + 1) + row,
                )
    builder.text(
        sheet,
        "A106",
        "Estimates of total inventories are for the end of the period. "
        "Estimates are not adjusted for price changes. Source: U.S. Census "
        "Bureau, Manufacturers’ Shipments, Inventories, and Orders (M3) "
        "Survey, August Full Report, October 2, 2026.",
    )
    builder.write(path)


def make_m3_advance(path: Path) -> None:
    builder = WorkbookBuilder(["Total mfg"])
    sheet = "Total mfg"
    builder.text(sheet, "A44", "Table 2.  Total Manufacturers' Inventories")
    builder.text(
        sheet,
        "A46",
        "[Estimates are shown in millions of dollars and are based on data "
        "from the Manufacturers' Shipments, Inventories, and Orders Survey.]  ",
    )
    for reference, value in {
        "C47": "Seasonally Adjusted",
        "I47": "Not Seasonally Adjusted ",
        "C48": "Monthly",
        "F48": "Percent Change",
        "I48": "Monthly",
        "L48": "Percent Change",
        "A49": "Industry",
        "C50": "Sep.",
        "D50": "Aug.",
        "E50": "Sep.",
        "C51": "2026p",
        "D51": "2026r",
        "I50": "Sep.",
        "J50": "Aug.",
        "K50": "Sep.",
        "I51": "2026p",
        "J51": "2026r",
    }.items():
        builder.text(sheet, reference, value)
    builder.number(sheet, "E51", 2025)
    builder.number(sheet, "K51", 2025)
    for row, label in zip(Census.M3_ADVANCE_ROWS, M3_ADVANCE_LABELS):
        builder.text(sheet, f"A{row}", label)
        builder.number(sheet, f"C{row}", 900000 + row)
        builder.number(sheet, f"I{row}", 910000 + row)
    builder.text(
        sheet,
        "A83",
        "Source: U.S. Census Bureau, Manufacturers’ Shipments, Inventories, "
        "and Orders (M3) Survey, September Advance Report, October 27, 2026.",
    )
    builder.write(path)


def make_mrts(path: Path) -> None:
    profile = Census.load_profile()
    names = profile["structures"]["mrts"]["sheet_names"]
    builder = WorkbookBuilder(names)
    sheet = "2026"
    builder.text(
        sheet,
        "A1",
        "Estimates of End-of-Month Retail Inventories and Inventories/Sales "
        "Ratios by Kind of Business: 2026",
    )
    builder.text(
        sheet,
        "A2",
        "[Estimates are shown in millions of dollars and are based on data "
        "from the Monthly Retail Trade Survey, Annual Retail Trade Survey, "
        "and administrative records]",
    )
    builder.text(sheet, "A4", "NAICS  Code")
    builder.text(sheet, "B4", "Kind of Business")
    for month in range(1, 9):
        column = Census.excel_column_letters(month + 2)
        builder.text(
            sheet,
            column + "5",
            Census._mrts_header_text(2026, month, month == 8),
        )
    blocks = (
        (6, "NOT ADJUSTED", MRTS_INVENTORY_ROWS, "inventory"),
        (16, "ADJUSTED(1)", MRTS_INVENTORY_ROWS, "inventory"),
        (26, "INVENTORIES/SALES, RATIOS NOT ADJUSTED", MRTS_RATIO_ROWS, "ratio"),
        (36, "INVENTORIES/SALES, RATIOS ADJUSTED(1)", MRTS_RATIO_ROWS, "ratio"),
    )
    for header_row, header, rows, metric in blocks:
        builder.text(sheet, f"B{header_row}", header)
        for offset, (code, label) in enumerate(rows, start=1):
            row = header_row + offset
            builder.text(sheet, f"A{row}", code)
            builder.text(sheet, f"B{row}", label)
            for month in range(1, 9):
                column = Census.excel_column_letters(month + 2)
                if metric == "inventory":
                    builder.number(sheet, f"{column}{row}", 500000 + row * 10 + month)
                else:
                    builder.number(sheet, f"{column}{row}", f"1.{row % 10}{month}")
    builder.text(
        sheet,
        "A49",
        "(1) Estimates are adjusted for seasonal variation and trading-day "
        "differences. Estimates are not adjusted for price changes.",
    )
    builder.text(sheet, "A51", "Note: Estimates exclude food services.")
    builder.write(path)


def make_mwts(path: Path, adjusted: bool) -> None:
    profile = Census.load_profile()
    key = "mwts_adjusted" if adjusted else "mwts_not_adjusted"
    names = profile["structures"][key]["sheet_names"]
    builder = WorkbookBuilder(names)
    codes = MWTS_CODES_ADJUSTED if adjusted else MWTS_CODES_NOT_ADJUSTED
    adjustment = "adjusted" if adjusted else "not_adjusted"
    for sheet, metric in (
        ("Inventories", "inventory"),
        ("Inventories to Sales Ratios", "inventory_sales_ratio"),
    ):
        builder.text(
            sheet,
            "A1",
            Census._mwts_title(adjustment, metric, 2026, 8),
        )
        if metric == "inventory":
            unit = (
                "Inventories estimates are in millions of dollars.  Estimates "
                "are based on data from the Monthly Wholesale Trade Survey, "
                "and have been benchmarked using the results of the Annual "
                "Wholesale Trade Survey."
                if adjusted
                else "Inventories estimates are in millions of dollars. "
                "Estimates are based on data from the Monthly Wholesale Trade "
                "Survey, and have been benchmarked using the results of the "
                "Annual Wholesale Trade Survey."
            )
        else:
            unit = (
                "Ratios are in units. Estimates are based on data from the "
                "Monthly Wholesale Trade Survey, and have been benchmarked "
                "using the results of the Annual Wholesale Trade Survey."
            )
        builder.text(sheet, "A3", unit)
        if adjusted:
            note = (
                "inventories estimates are adjusted for seasonal variation. "
                "Estimates are adjusted for trading day differences, but not "
                "for price changes."
                if metric == "inventory"
                else "sales and inventories estimates are adjusted for "
                "seasonal variation. Estimates of inventories are also "
                "adjusted for trading day differences. "
                "Estimates are not adjusted for price changes."
            )
            builder.text(sheet, "A7", note)
        builder.text(sheet, "A17", "Month")
        builder.text(sheet, "B17", "Year")
        for column_number, (code, description) in enumerate(
            zip(codes, MWTS_DESCRIPTIONS), start=3
        ):
            column = Census.excel_column_letters(column_number)
            builder.text(sheet, column + "16", description)
            if code.isdigit():
                builder.number(sheet, column + "17", code)
            else:
                builder.text(sheet, column + "17", code)
        axis = list(reversed(Census._month_axis("1992-01", "2026-08")))
        for offset, (year, month) in enumerate(axis):
            row = 18 + offset
            month_text = Census.MONTHS[month - 1]
            if offset == 0:
                month_text += " \u00a0 p"
            elif offset == 1 or (adjusted and offset == 12):
                month_text += " \u00a0 r"
            builder.text(sheet, f"A{row}", month_text)
            builder.number(sheet, f"B{row}", year)
            for column_number in range(3, 25):
                column = Census.excel_column_letters(column_number)
                if metric == "inventory":
                    builder.number(
                        sheet,
                        f"{column}{row}",
                        100000 + row * 30 + column_number,
                    )
                else:
                    builder.number(sheet, f"{column}{row}", f"1.{column_number:02d}")
    builder.write(path)


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def binding_document(paths: dict[str, Path]) -> dict[str, object]:
    profile = Census.load_profile()
    profile_records = {record["profile_id"]: record for record in profile["profiles"]}
    records = []
    for profile_id in Census.EXPECTED_PROFILE_IDS:
        source = profile_records[profile_id]
        records.append(
            {
                "profile_id": profile_id,
                "requirement_id": source["requirement_id"],
                "event_id": source["event_id"],
                "reference_period": source["reference_period"],
                "scheduled_timestamp_utc": source["scheduled_timestamp_utc"],
                "capture_deadline_utc": source["capture_deadline_utc"],
                "source_url": source["source_url"],
                "effective_url": source["source_url"],
                "http_status": 200,
                "content_type": (
                    "application/vnd.openxmlformats-officedocument."
                    "spreadsheetml.sheet"
                ),
                "raw_sha256": sha256_file(paths[profile_id]),
                "raw_byte_count": paths[profile_id].stat().st_size,
                "retrieved_at_utc": source["scheduled_timestamp_utc"],
                "claim": "CALLER_ASSERTED_LOCAL_INTEGRITY_NOT_PROVIDER_AUTHENTICATION",
            }
        )
    result: dict[str, object] = {
        "artifact": {
            "schema_version": Census.BINDING_SCHEMA_VERSION,
            "status": Census.STATUS,
            "role": "UNAUTHENTICATED_LOCAL_CAPTURE_BINDING_NONADMITTING",
            "canonicalization": Census.CANONICALIZATION,
            "profile_content_sha256": profile["artifact"]["content_sha256"],
            "prospective_contract_sha256": Census.EXPECTED_CONTRACT_PHYSICAL_SHA256,
            "content_sha256": "",
        },
        "records": records,
    }
    result["artifact"]["content_sha256"] = Census._binding_semantic_hash(result)
    return result


def write_json(path: Path, value: object) -> None:
    path.write_bytes(Census.canonical_json_bytes(value))


def rewrite_zip(path: Path, mutation) -> None:
    with zipfile.ZipFile(path, "r") as source:
        payloads = [(info.filename, source.read(info)) for info in source.infolist()]
    payloads = mutation(payloads)
    replacement = path.with_suffix(".replacement")
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", UserWarning)
        with zipfile.ZipFile(
            replacement,
            "w",
            compression=zipfile.ZIP_DEFLATED,
        ) as target:
            for name, payload in payloads:
                info = zipfile.ZipInfo(name, (2020, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.create_system = 0
                target.writestr(info, payload)
    os.replace(replacement, path)


class CensusInventoryReleaseProfileTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temporary.name).resolve()
        cls.paths = {
            profile_id: cls.root / (profile_id + ".xlsx")
            for profile_id in Census.EXPECTED_PROFILE_IDS
        }
        make_m3_full(cls.paths["m3_2026_08_stage_table"])
        make_mwts(cls.paths["mwts_2026_08_adjusted_inventory"], True)
        make_mwts(cls.paths["mwts_2026_08_not_adjusted_inventory"], False)
        make_mrts(cls.paths["mrts_2026_08_inventory"])
        make_m3_advance(cls.paths["m3_2026_09_advance_total"])
        cls.binding_path = cls.root / "binding.json"
        write_json(cls.binding_path, binding_document(cls.paths))

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def copied_bundle(self) -> tuple[Path, dict[str, Path]]:
        directory = Path(tempfile.mkdtemp(dir=self.root)).resolve()
        paths: dict[str, Path] = {}
        for profile_id, source in self.paths.items():
            destination = directory / source.name
            shutil.copyfile(source, destination)
            paths[profile_id] = destination
        return directory, paths

    def restamped_binding(self, directory: Path, paths: dict[str, Path]) -> Path:
        path = directory / "binding.json"
        write_json(path, binding_document(paths))
        return path

    def assert_rejected(self, function, message: str) -> None:
        with self.assertRaisesRegex(Census.ProfileError, message):
            function()

    def test_profile_self_hash_contract_and_exact_topology(self) -> None:
        profile = Census.load_profile()
        self.assertEqual(sha256_file(MODULE_PATH), EXPECTED_MODULE_PHYSICAL_SHA256)
        self.assertEqual(profile["artifact"]["status"], "CANNOT_RUN")
        self.assertEqual(profile["artifact"]["role"], Census.ROLE)
        self.assertEqual(
            Census.sha256_bytes(Census.PROFILE_PATH.read_bytes()),
            Census.EXPECTED_PROFILE_PHYSICAL_SHA256,
        )
        self.assertEqual(
            Census._canonical_semantic_hash(profile),
            profile["artifact"]["content_sha256"],
        )
        self.assertEqual(
            Census.sha256_bytes(Census.CONTRACT_PATH.read_bytes()),
            Census.EXPECTED_CONTRACT_PHYSICAL_SHA256,
        )
        self.assertEqual(
            [record["profile_id"] for record in profile["profiles"]],
            list(Census.EXPECTED_PROFILE_IDS),
        )
        self.assertTrue(all(value is False for value in profile["gates"].values()))

    def test_planned_bundle_parses_all_five_profiles_fail_closed(self) -> None:
        result = Census.parse_planned_local_bundle(self.paths, self.binding_path)
        self.assertEqual(result["status"], "CANNOT_RUN")
        self.assertEqual(result["role"], Census.ROLE)
        self.assertEqual(result["profile_count"], 5)
        self.assertTrue(result["full_five_profile_topology_verified"])
        self.assertTrue(result["source_verification_performed"])
        self.assertFalse(result["origin_evidence_claimed"])
        self.assertFalse(result["self_accepted"])
        self.assertTrue(all(value is False for value in result["gates"].values()))
        for record in result["records"]:
            self.assertNotIn("source_url_binding_verified", record)
            self.assertTrue(record["source_body_hash_and_size_verified"])
            self.assertTrue(
                record["declared_source_url_contract_binding_verified"]
            )
            self.assertTrue(record["caller_binding_url_fields_validated"])
            self.assertFalse(
                record["body_to_declared_url_provenance_verified"]
            )
            self.assertFalse(record["provider_provenance_verified"])
        self.assertEqual(
            Census.validate_planned_result_bytes(
                Census.canonical_json_bytes(result), self.paths, self.binding_path
            ),
            result,
        )

    def test_exact_integer_ratio_and_semantic_boundaries(self) -> None:
        result = Census.parse_planned_local_bundle(self.paths, self.binding_path)
        records = {record["profile_id"]: record for record in result["records"]}
        full = records["m3_2026_08_stage_table"]["parsed"]
        self.assertEqual(len(full["rows"]), 24)
        self.assertTrue(full["derived_total_is_not_a_published_table6_cell"])
        total = full["rows"][0]["total"]
        self.assertIs(type(total["seasonally_adjusted"]), int)
        self.assertFalse(total["published_in_table_6"])
        advance = records["m3_2026_09_advance_total"]["parsed"]
        self.assertIs(
            type(advance["selector_selected_row"]["seasonally_adjusted"]), int
        )
        self.assertFalse(advance["selector_metadata_complete"])
        adjusted = records["mwts_2026_08_adjusted_inventory"]["parsed"]
        self.assertIs(type(adjusted["rows"][0]["inventory"]), int)
        self.assertIs(type(adjusted["rows"][0]["inventory_sales_ratio"]), str)
        self.assertTrue(adjusted["selector_metadata_complete"])
        not_adjusted = records["mwts_2026_08_not_adjusted_inventory"]["parsed"]
        self.assertFalse(not_adjusted["selector_metadata_complete"])
        mrts = records["mrts_2026_08_inventory"]["parsed"]
        self.assertEqual(mrts["kind_of_business_row_count"], 9)
        self.assertFalse(mrts["geography_explicit_in_workbook"])

    def test_public_apis_have_no_source_verification_bypass(self) -> None:
        for function in (
            Census.load_profile,
            Census.parse_workbook,
            Census.parse_observed_current_bundle,
            Census.parse_planned_local_bundle,
            Census.validate_observed_result_bytes,
            Census.validate_planned_result_bytes,
        ):
            self.assertNotIn("verify_sources", inspect.signature(function).parameters)
            self.assertNotIn("source_verifier", inspect.signature(function).parameters)
        with self.assertRaises(TypeError):
            Census.parse_planned_local_bundle(
                self.paths, self.binding_path, verify_sources=False
            )

    def test_profile_state_and_policy_mapping_are_not_poisonable(self) -> None:
        self.assertFalse(any(name.endswith("_RE") for name in vars(Census)))
        with self.assertRaises(TypeError):
            Census.EXPECTED_BINDINGS["m3_2026_08_stage_table"] = {}
        with self.assertRaises(TypeError):
            Census.EXPECTED_BINDINGS["m3_2026_08_stage_table"]["source_url"] = "x"
        first = Census.load_profile()
        first["profiles"][0]["source_url"] = "poison"
        first["gates"]["model_input_allowed"] = True
        second = Census.load_profile()
        self.assertEqual(
            second["profiles"][0]["source_url"],
            Census.EXPECTED_BINDINGS["m3_2026_08_stage_table"]["source_url"],
        )
        self.assertFalse(second["gates"]["model_input_allowed"])
        self.assert_rejected(
            lambda: Census._exact_nonnegative_integer(
                Census.Sheet(
                    "x",
                    "x",
                    "A1",
                    {(1, 1): Census.Cell("A1", 1, 1, "n", 0, "NaN", "NaN")},
                    "0" * 64,
                ),
                "A1",
            ),
            "exact integer",
        )

    def test_result_rehash_and_restamp_cannot_replace_replay(self) -> None:
        result = Census.parse_planned_local_bundle(self.paths, self.binding_path)
        changed = copy.deepcopy(result)
        changed["records"][0]["parsed"]["rows"][0]["total"][
            "seasonally_adjusted"
        ] += 1
        del changed["content_sha256"]
        changed["content_sha256"] = Census.sha256_bytes(
            Census.canonical_json_bytes(changed)
        )
        self.assert_rejected(
            lambda: Census.validate_planned_result_bytes(
                Census.canonical_json_bytes(changed), self.paths, self.binding_path
            ),
            "does not exactly replay",
        )
        changed = copy.deepcopy(result)
        changed["profile_count"] = True
        del changed["content_sha256"]
        changed["content_sha256"] = Census.sha256_bytes(
            Census.canonical_json_bytes(changed)
        )
        self.assert_rejected(
            lambda: Census.validate_planned_result_bytes(
                Census.canonical_json_bytes(changed), self.paths, self.binding_path
            ),
            "topology drifted",
        )
        changed = copy.deepcopy(result)
        changed["records"][0][
            "body_to_declared_url_provenance_verified"
        ] = True
        del changed["content_sha256"]
        changed["content_sha256"] = Census.sha256_bytes(
            Census.canonical_json_bytes(changed)
        )
        self.assert_rejected(
            lambda: Census.validate_planned_result_bytes(
                Census.canonical_json_bytes(changed),
                self.paths,
                self.binding_path,
            ),
            "falsely binds local bytes",
        )

    def test_stale_body_hash_and_binding_field_restamps_fail(self) -> None:
        directory, paths = self.copied_bundle()
        try:
            with paths["m3_2026_08_stage_table"].open("ab") as stream:
                stream.write(b"X")
            self.assert_rejected(
                lambda: Census.parse_planned_local_bundle(paths, self.binding_path),
                "mandatory source pin",
            )
            binding = binding_document(paths)
            binding["records"][0]["source_url"] = "https://example.invalid/x.xlsx"
            binding["artifact"]["content_sha256"] = Census._binding_semantic_hash(
                binding
            )
            binding_path = directory / "bad-binding.json"
            write_json(binding_path, binding)
            self.assert_rejected(
                lambda: Census.parse_planned_local_bundle(paths, binding_path),
                "source_url drifted",
            )
            binding = binding_document(paths)
            binding["records"][0]["raw_byte_count"] = True
            binding["artifact"]["content_sha256"] = Census._binding_semantic_hash(
                binding
            )
            write_json(binding_path, binding)
            self.assert_rejected(
                lambda: Census.parse_planned_local_bundle(paths, binding_path),
                "exact nonnegative integer",
            )
        finally:
            shutil.rmtree(directory)

    def test_formula_error_and_wrong_integer_type_fail(self) -> None:
        cases = (
            ("formula", "forbidden formula"),
            ("error", "forbidden error cell"),
            ("decimal", "exact integer cell"),
        )
        for kind, message in cases:
            with self.subTest(kind=kind):
                directory, paths = self.copied_bundle()
                try:
                    target = paths["m3_2026_09_advance_total"]

                    def mutation(payloads):
                        output = []
                        for name, payload in payloads:
                            if name == "xl/worksheets/sheet1.xml":
                                root = ET.fromstring(payload)
                                cell = next(
                                    item
                                    for item in root.iter(MAIN + "c")
                                    if item.get("r") == "C54"
                                )
                                if kind == "formula":
                                    ET.SubElement(cell, MAIN + "f").text = "1+1"
                                elif kind == "error":
                                    cell.set("t", "e")
                                    cell.find(MAIN + "v").text = "#VALUE!"
                                else:
                                    cell.find(MAIN + "v").text = "900054.0"
                                payload = ET.tostring(
                                    root, encoding="utf-8", xml_declaration=True
                                )
                            output.append((name, payload))
                        return output

                    rewrite_zip(target, mutation)
                    binding = self.restamped_binding(directory, paths)
                    self.assert_rejected(
                        lambda: Census.parse_planned_local_bundle(paths, binding),
                        message,
                    )
                finally:
                    shutil.rmtree(directory)

    def test_duplicate_case_duplicate_and_unsafe_zip_members_fail(self) -> None:
        cases = (
            ("duplicate", "not unique"),
            ("case", "not case-unique"),
            ("unsafe", "unsafe or forbidden"),
        )
        for kind, message in cases:
            with self.subTest(kind=kind):
                directory, paths = self.copied_bundle()
                try:
                    target = paths["m3_2026_09_advance_total"]

                    def mutation(payloads):
                        if kind == "duplicate":
                            return payloads + [payloads[0]]
                        if kind == "case":
                            return payloads + [("XL/WORKBOOK.XML", b"x")]
                        return payloads + [("../escape.xml", b"x")]

                    rewrite_zip(target, mutation)
                    binding = self.restamped_binding(directory, paths)
                    self.assert_rejected(
                        lambda: Census.parse_planned_local_bundle(paths, binding),
                        message,
                    )
                finally:
                    shutil.rmtree(directory)

    def test_external_relationship_and_content_type_decoys_fail(self) -> None:
        cases = (
            ("external", "external OOXML relationship"),
            ("content", "wrong OOXML content type"),
            ("orphan", "unreachable or unbound substantive part"),
            ("relation_mime", "target content type is not exact"),
            ("rels_mime", "relationship part content type is not exact"),
        )
        for kind, message in cases:
            with self.subTest(kind=kind):
                directory, paths = self.copied_bundle()
                try:
                    target = paths["m3_2026_09_advance_total"]

                    def mutation(payloads):
                        if kind == "orphan":
                            return payloads + [("decoy.xml", b"<decoy />")]
                        output = []
                        for name, payload in payloads:
                            if kind == "external" and name == "_rels/.rels":
                                root = ET.fromstring(payload)
                                ET.SubElement(
                                    root,
                                    PKG_REL + "Relationship",
                                    {
                                        "Id": "evil",
                                        "Type": REL_NS + "/hyperlink",
                                        "Target": "https://example.invalid/",
                                        "TargetMode": "External",
                                    },
                                )
                                payload = ET.tostring(
                                    root, encoding="utf-8", xml_declaration=True
                                )
                            if (
                                kind == "relation_mime"
                                and name == "xl/_rels/workbook.xml.rels"
                            ):
                                root = ET.fromstring(payload)
                                ET.SubElement(
                                    root,
                                    PKG_REL + "Relationship",
                                    {
                                        "Id": "rIdThemeMimeDecoy",
                                        "Type": REL_NS + "/theme",
                                        "Target": "styles.xml",
                                    },
                                )
                                payload = ET.tostring(
                                    root, encoding="utf-8", xml_declaration=True
                                )
                            if kind == "content" and name == "[Content_Types].xml":
                                payload = payload.replace(
                                    b"spreadsheetml.sheet.main+xml",
                                    b"spreadsheetml.template.main+xml",
                                )
                            if kind == "rels_mime" and name == "[Content_Types].xml":
                                root = ET.fromstring(payload)
                                relation_default = next(
                                    item
                                    for item in root.findall(CT + "Default")
                                    if item.get("Extension") == "rels"
                                )
                                relation_default.set(
                                    "ContentType", "application/octet-stream"
                                )
                                payload = ET.tostring(
                                    root, encoding="utf-8", xml_declaration=True
                                )
                            output.append((name, payload))
                        return output

                    rewrite_zip(target, mutation)
                    binding = self.restamped_binding(directory, paths)
                    self.assert_rejected(
                        lambda: Census.parse_planned_local_bundle(paths, binding),
                        message,
                    )
                finally:
                    shutil.rmtree(directory)

    def test_all_xml_parts_require_safe_bom_free_utf8(self) -> None:
        expandable = (
            b"<?xml version='1.0' encoding='utf-8'?>"
            b'<!DOCTYPE x [<!ENTITY decoy "expanded">]>'
            b"<x>&decoy;</x>"
        )
        self.assertEqual(ET.fromstring(expandable).text, "expanded")
        self.assert_rejected(
            lambda: Census._xml_root(expandable, "entity decoy"),
            "forbidden DTD or entity declaration",
        )
        cases = (
            ("utf16", "BOM-free UTF-8 XML"),
            ("utf16le", "forbidden XML control character"),
            ("utf8_bom", "BOM-free UTF-8 XML"),
            ("entity", "forbidden DTD or entity declaration"),
            ("pi", "forbidden processing instruction"),
        )
        for kind, message in cases:
            with self.subTest(kind=kind):
                directory, paths = self.copied_bundle()
                try:
                    target = paths["m3_2026_09_advance_total"]

                    def mutation(payloads):
                        output = []
                        for name, payload in payloads:
                            if name == "xl/styles.xml":
                                if kind == "utf16":
                                    text = payload.decode("utf-8").replace(
                                        "encoding='utf-8'",
                                        "encoding='utf-16'",
                                    )
                                    payload = text.encode("utf-16")
                                elif kind == "utf16le":
                                    payload = payload.decode("utf-8").encode(
                                        "utf-16le"
                                    )
                                elif kind == "utf8_bom":
                                    payload = b"\xef\xbb\xbf" + payload
                                elif kind == "pi":
                                    text = payload.decode("utf-8")
                                    declaration_end = text.index("?>") + 2
                                    payload = (
                                        text[:declaration_end]
                                        + "<?decoy expanded?>"
                                        + text[declaration_end:]
                                    ).encode("utf-8")
                                else:
                                    text = payload.decode("utf-8")
                                    declaration_end = text.index("?>") + 2
                                    payload = (
                                        text[:declaration_end]
                                        + "<!DOCTYPE styleSheet ["
                                        '<!ENTITY x "expanded">]>'
                                        + text[declaration_end:].replace(
                                            "</ns0:styleSheet>",
                                            "&x;</ns0:styleSheet>",
                                        )
                                    ).encode("utf-8")
                            output.append((name, payload))
                        return output

                    rewrite_zip(target, mutation)
                    binding = self.restamped_binding(directory, paths)
                    self.assert_rejected(
                        lambda: Census.parse_planned_local_bundle(
                            paths, binding
                        ),
                        message,
                    )
                finally:
                    shutil.rmtree(directory)

        directory, paths = self.copied_bundle()
        try:
            target = paths["m3_2026_09_advance_total"]
            renamed_xml = (
                "<?xml version='1.0' encoding='utf-16'?>"
                '<!DOCTYPE theme [<!ENTITY decoy "expanded">]>'
                "<theme>&decoy;</theme>"
            ).encode("utf-16")

            def renamed_theme_mutation(payloads):
                output = []
                for name, payload in payloads:
                    if name == "[Content_Types].xml":
                        root = ET.fromstring(payload)
                        ET.SubElement(
                            root,
                            CT + "Override",
                            {
                                "PartName": "/xl/theme/theme1.dat",
                                "ContentType": Census.THEME_CONTENT_TYPE,
                            },
                        )
                        payload = ET.tostring(
                            root, encoding="utf-8", xml_declaration=True
                        )
                    elif name == "xl/_rels/workbook.xml.rels":
                        root = ET.fromstring(payload)
                        ET.SubElement(
                            root,
                            PKG_REL + "Relationship",
                            {
                                "Id": "rIdRenamedTheme",
                                "Type": REL_NS + "/theme",
                                "Target": "theme/theme1.dat",
                            },
                        )
                        payload = ET.tostring(
                            root, encoding="utf-8", xml_declaration=True
                        )
                    output.append((name, payload))
                output.append(("xl/theme/theme1.dat", renamed_xml))
                return output

            rewrite_zip(target, renamed_theme_mutation)
            binding = self.restamped_binding(directory, paths)
            self.assert_rejected(
                lambda: Census.parse_planned_local_bundle(paths, binding),
                "BOM-free UTF-8 XML",
            )
        finally:
            shutil.rmtree(directory)

    def test_reference_axis_row_universe_and_duplicate_cell_decoys_fail(self) -> None:
        cases = (
            ("reference", "text drifted"),
            ("row", "row universe drifted"),
            ("duplicate_cell", "duplicated or out of order"),
            ("dimension", "outside its declared dimension"),
        )
        for kind, message in cases:
            with self.subTest(kind=kind):
                directory, paths = self.copied_bundle()
                try:
                    target = paths["mrts_2026_08_inventory"]

                    def mutation(payloads):
                        output = []
                        for name, payload in payloads:
                            if name == "xl/sharedStrings.xml" and kind in (
                                "reference",
                                "row",
                            ):
                                root = ET.fromstring(payload)
                                for node in root.iter(MAIN + "t"):
                                    if (
                                        kind == "reference"
                                        and node.text == "Aug. 2026(p)"
                                    ):
                                        node.text = "Jul. 2026(p)"
                                        break
                                    if (
                                        kind == "row"
                                        and node.text == "Department stores"
                                    ):
                                        node.text = "Department store decoy"
                                        break
                                payload = ET.tostring(
                                    root, encoding="utf-8", xml_declaration=True
                                )
                            if (
                                name == "xl/worksheets/sheet1.xml"
                                and kind == "duplicate_cell"
                            ):
                                root = ET.fromstring(payload)
                                row = next(
                                    item
                                    for item in root.iter(MAIN + "row")
                                    if item.get("r") == "7"
                                )
                                original = next(
                                    item
                                    for item in row.findall(MAIN + "c")
                                    if item.get("r") == "C7"
                                )
                                row.append(copy.deepcopy(original))
                                payload = ET.tostring(
                                    root, encoding="utf-8", xml_declaration=True
                                )
                            if (
                                name == "xl/worksheets/sheet1.xml"
                                and kind == "dimension"
                            ):
                                root = ET.fromstring(payload)
                                root.find(MAIN + "dimension").set("ref", "A1")
                                payload = ET.tostring(
                                    root, encoding="utf-8", xml_declaration=True
                                )
                            output.append((name, payload))
                        return output

                    rewrite_zip(target, mutation)
                    binding = self.restamped_binding(directory, paths)
                    self.assert_rejected(
                        lambda: Census.parse_planned_local_bundle(paths, binding),
                        message,
                    )
                finally:
                    shutil.rmtree(directory)

    def test_duplicate_mwts_period_and_naics_axis_decoys_fail(self) -> None:
        for kind, message in (
            ("period", "unreferenced item"),
            ("naics", "NAICS header universe drifted"),
        ):
            with self.subTest(kind=kind):
                directory, paths = self.copied_bundle()
                try:
                    target = paths["mwts_2026_08_adjusted_inventory"]

                    def mutation(payloads):
                        output = []
                        for name, payload in payloads:
                            if name in (
                                "xl/worksheets/sheet2.xml",
                                "xl/worksheets/sheet3.xml",
                            ):
                                root = ET.fromstring(payload)
                                wanted = "A19" if kind == "period" else "D17"
                                source = "A18" if kind == "period" else "C17"
                                cells = {
                                    cell.get("r"): cell
                                    for cell in root.iter(MAIN + "c")
                                }
                                source_value = cells[source].find(MAIN + "v")
                                cells[wanted].find(MAIN + "v").text = (
                                    source_value.text
                                )
                                payload = ET.tostring(
                                    root, encoding="utf-8", xml_declaration=True
                                )
                            output.append((name, payload))
                        return output

                    rewrite_zip(target, mutation)
                    binding = self.restamped_binding(directory, paths)
                    self.assert_rejected(
                        lambda: Census.parse_planned_local_bundle(paths, binding),
                        message,
                    )
                finally:
                    shutil.rmtree(directory)

    def test_relative_symlink_hardlink_and_duplicate_path_fail(self) -> None:
        relative = dict(self.paths)
        relative["m3_2026_08_stage_table"] = Path("relative.xlsx")
        self.assert_rejected(
            lambda: Census.parse_planned_local_bundle(relative, self.binding_path),
            "absolute Path",
        )
        noncanonical = dict(self.paths)
        original = self.paths["m3_2026_08_stage_table"]
        noncanonical["m3_2026_08_stage_table"] = (
            original.parent / "absent" / ".." / original.name
        )
        self.assert_rejected(
            lambda: Census.parse_planned_local_bundle(
                noncanonical, self.binding_path
            ),
            "canonical absolute spelling",
        )
        directory, paths = self.copied_bundle()
        try:
            original = paths["m3_2026_08_stage_table"]
            symlink = directory / "symlink.xlsx"
            symlink.symlink_to(original)
            symlinked = dict(paths)
            symlinked["m3_2026_08_stage_table"] = symlink
            self.assert_rejected(
                lambda: Census.parse_planned_local_bundle(symlinked, self.binding_path),
                "unsafe",
            )
            hard_source = directory / "hard-source.xlsx"
            shutil.copyfile(original, hard_source)
            hardlink = directory / "hard-link.xlsx"
            os.link(hard_source, hardlink)
            linked = dict(paths)
            linked["m3_2026_08_stage_table"] = hard_source
            binding = self.restamped_binding(directory, linked)
            self.assert_rejected(
                lambda: Census.parse_planned_local_bundle(linked, binding),
                "single-link regular file",
            )
            duplicate = dict(paths)
            duplicate["m3_2026_09_advance_total"] = original
            self.assert_rejected(
                lambda: Census.parse_planned_local_bundle(duplicate, self.binding_path),
                "same external workbook",
            )
        finally:
            shutil.rmtree(directory)

    def test_duplicate_json_keys_and_binding_symlink_fail(self) -> None:
        duplicate = b'{"artifact":{},"artifact":{},"records":[]}'
        path = self.root / "duplicate-binding.json"
        path.write_bytes(duplicate)
        self.assert_rejected(
            lambda: Census.parse_planned_local_bundle(self.paths, path),
            "duplicate JSON key",
        )
        self.assert_rejected(
            lambda: Census.parse_json_bytes(b'{"value":NaN}', "decoy"),
            "non-finite JSON constant",
        )
        symlink = self.root / "binding-symlink.json"
        symlink.symlink_to(self.binding_path)
        try:
            self.assert_rejected(
                lambda: Census.parse_planned_local_bundle(self.paths, symlink),
                "symbolic-link or alias",
            )
        finally:
            symlink.unlink()

    def test_present_day_external_bodies_when_supplied(self) -> None:
        audit = Path("/private/tmp/census-inventory-workbook-audit.43VSN2")
        if not audit.is_dir():
            self.skipTest("caller-supplied present-day audit bodies are absent")
        paths = {
            "m3_2026_08_stage_table": audit / "m3_table6p.xlsx",
            "mwts_2026_08_adjusted_inventory": audit / "mwts_adjusted.xlsx",
            "mwts_2026_08_not_adjusted_inventory": audit / "mwts_not_adjusted.xlsx",
            "mrts_2026_08_inventory": audit / "mrts_inventory.xlsx",
            "m3_2026_09_advance_total": audit / "m3_tabletm.xlsx",
        }
        result = Census.parse_observed_current_bundle(paths)
        for record in result["records"]:
            self.assertTrue(
                record["declared_source_url_contract_binding_verified"]
            )
            self.assertFalse(record["caller_binding_url_fields_validated"])
            self.assertFalse(
                record["body_to_declared_url_provenance_verified"]
            )
        records = {record["profile_id"]: record for record in result["records"]}
        self.assertEqual(
            records["m3_2026_08_stage_table"]["parsed"]["rows"][0]["total"][
                "seasonally_adjusted"
            ],
            962917,
        )
        self.assertEqual(
            records["mwts_2026_08_adjusted_inventory"]["parsed"]["rows"][0][
                "inventory"
            ],
            944710,
        )
        self.assertEqual(
            records["mwts_2026_08_adjusted_inventory"]["parsed"]["rows"][0][
                "inventory_sales_ratio"
            ],
            "1.19",
        )
        self.assertEqual(
            records["mwts_2026_08_not_adjusted_inventory"]["parsed"]["rows"][0][
                "inventory"
            ],
            936901,
        )
        self.assertEqual(
            records["m3_2026_09_advance_total"]["parsed"][
                "selector_selected_row"
            ]["seasonally_adjusted"],
            962786,
        )
        self.assertEqual(
            Census.validate_observed_result_bytes(
                Census.canonical_json_bytes(result), paths
            ),
            result,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
