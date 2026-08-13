#!/usr/bin/env python3
"""Build the hermetic OECD USA 2024 SUT valuation diagnostic fixture.

The generator has two input modes:

* ``--live`` downloads the exact public SDMX 2.0 responses listed below.
* ``--source-dir`` reads an already downloaded response bundle.

Every response is checked byte-for-byte against a pinned size and SHA-256
before any projection is produced.  Generated files are canonical and do not
contain the invocation time or input mode, so the two modes produce identical
bytes.  No credential, cookie, or personalized endpoint is used.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path
from typing import Iterable


CAPTURED_AT_UTC = "2026-08-06T15:10:26Z"
SCHEMA_VERSION = "beforeit-us-oecd-sut-source-axis-valuation-fixture.v2"
CLASSIFICATION = "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
SOURCE_BASE = "https://sdmx.oecd.org/public/rest"
SOURCE_DATASET_URL = (
    "https://www.oecd.org/en/data/datasets/supply-and-use-tables.html"
)
SOURCE_API_DOCUMENTATION_URL = (
    "https://www.oecd.org/en/data/insights/data-explainers/2024/09/api.html"
)
SOURCE_TERMS_URL = "https://www.oecd.org/en/about/terms-conditions.html"
ROOT = Path(__file__).resolve().parents[4]
PROJECT_PATH = ROOT / "scripts" / "us" / "Project.toml"
JULIA_MANIFEST_PATH = ROOT / "scripts" / "us" / "Manifest.toml"
DEFAULT_OUTPUT = (
    Path(__file__).resolve().parent
    / "fixtures"
    / "oecd_sut_usa_2024_v2"
)
DEFAULT_RAW_SOURCE = (
    Path(__file__).resolve().parent
    / "raw"
    / "oecd_sut_usa_2024_v2"
)

EXPECTED_PROJECT_SHA256 = (
    "72cec6cb6dc64dc71b9e342890b78afbf8fd66cb97dd8603e4fe905ad137dc1c"
)
EXPECTED_JULIA_MANIFEST_SHA256 = (
    "c2e596cf8452c5b890bb0ef66c05bc72a57fa25ab6f8fe790f8db4600b035263"
)


@dataclass(frozen=True)
class ResponseSpec:
    name: str
    local_name: str
    kind: str
    url: str
    accept: str
    byte_count: int
    sha256: str


def data_url(dataflow: str, table_identifier: str) -> str:
    key = f"A.USA......V.{table_identifier}"
    query = (
        "startPeriod=2024&endPeriod=2024"
        "&dimensionAtObservation=AllDimensions"
    )
    return (
        f"{SOURCE_BASE}/data/OECD.SDD.NAD,DSD_NASU@{dataflow},2.0/"
        f"{key}?{query}"
    )


def structure_url(dataflow: str) -> str:
    return (
        f"{SOURCE_BASE}/dataflow/OECD.SDD.NAD/"
        f"DSD_NASU@{dataflow}/2.0?references=all"
    )


def codelist_url(agency: str, identifier: str, version: str) -> str:
    return (
        f"{SOURCE_BASE}/codelist/{agency}/{identifier}/{version}"
        "?references=none"
    )


def hierarchy_url(identifier: str) -> str:
    return (
        f"{SOURCE_BASE}/hierarchicalcodelist/OECD.SDD.NAD/"
        f"{identifier}/1.0?references=none"
    )


RESPONSES = (
    ResponseSpec(
        "data_T1600",
        "oecd-T1600.csv",
        "data",
        data_url("DF_USEPP", "T1600"),
        "text/csv",
        1_102_993,
        "961ea4cae5e3ea78973516699e92d6bd76fcd9c396efa3bf60a8384e672bdbb1",
    ),
    ResponseSpec(
        "data_T1610",
        "oecd-T1610.csv",
        "data",
        data_url("DF_USEBP", "T1610"),
        "text/csv",
        1_146_576,
        "e0c242ead52ca3f816d2f0c245f3cbb046e6f5bc9d06cd53b9271f79f271223c",
    ),
    ResponseSpec(
        "data_T1620",
        "oecd-T1620.csv",
        "data",
        data_url("DF_VALUATION", "T1620"),
        "text/csv",
        488_046,
        "8743aaa213f26de35413e2975d61868e27a2270cb6e492b7ca2e3a344619ac60",
    ),
    ResponseSpec(
        "data_T1630",
        "oecd-T1630.csv",
        "data",
        data_url("DF_VALUATION", "T1630"),
        "text/csv",
        1_045_951,
        "36c729a04b0106cf9ac7740df068536a465ccf60fd5016aca9d34f590728c9fd",
    ),
    ResponseSpec(
        "data_T1633",
        "oecd-T1633.csv",
        "data",
        data_url("DF_VALUATION", "T1633"),
        "text/csv",
        1_027_581,
        "b57e43c00378982a7780faf3ac178ebe85d6403bc60451b668ab385c02178fb0",
    ),
    ResponseSpec(
        "data_T1634",
        "oecd-T1634.csv",
        "data",
        data_url("DF_VALUATION", "T1634"),
        "text/csv",
        151_383,
        "05c7d0e34d1fa4587942b3d029f37160cbb3b1676050c794ab18dd8e0b4eb66f",
    ),
    ResponseSpec(
        "structure_DF_USEPP",
        "oecd-DF_USEPP-structure.xml",
        "structure",
        structure_url("DF_USEPP"),
        "application/xml",
        3_225_259,
        "184835095e95201bd28ffd7873f2c28bed50ba56b51e92f5465f3b9f6df68fd7",
    ),
    ResponseSpec(
        "structure_DF_USEBP",
        "oecd-DF_USEBP-structure.xml",
        "structure",
        structure_url("DF_USEBP"),
        "application/xml",
        3_225_052,
        "822a507dc3b82bde9ac367cf56ec9e36c24b5a2f16625fd9ce073ed098b53a04",
    ),
    ResponseSpec(
        "structure_DF_VALUATION",
        "oecd-DF_VALUATION-structure.xml",
        "structure",
        structure_url("DF_VALUATION"),
        "application/xml",
        3_224_211,
        "9c6bcdd976fdaf9595049c84bbf6650f54b5e163899109ea6ce4c53149dbe0d0",
    ),
    ResponseSpec(
        "hierarchy_ACTIVITY",
        "oecd-HCL_ACTIVITY_ISIC4_SUT.xml",
        "hierarchy",
        hierarchy_url("HCL_ACTIVITY_ISIC4_SUT"),
        "application/xml",
        39_491,
        "aaa4bab3b591752815aefc34994989b6eb01937f76595b24e59eee58f9d7a8be",
    ),
    ResponseSpec(
        "hierarchy_PRODUCT",
        "oecd-HCL_PRODUCT_CPA2008_SUT.xml",
        "hierarchy",
        hierarchy_url("HCL_PRODUCT_CPA2008_SUT"),
        "application/xml",
        40_104,
        "a237755ce1b03a5f3fe183de3770ad4d45dcff759b793d9381fc54193cd220b8",
    ),
    ResponseSpec(
        "hierarchy_TRANSACTION",
        "oecd-HCL_TRANSACTION_SUT.xml",
        "hierarchy",
        hierarchy_url("HCL_TRANSACTION_SUT"),
        "application/xml",
        11_186,
        "a71c40f48880e215d825becfda5500fb08dfeec1f9dbe8d001108e8b38766f94",
    ),
    ResponseSpec(
        "hierarchy_VALUATION",
        "oecd-HCL_VALUATION_SUT.xml",
        "hierarchy",
        hierarchy_url("HCL_VALUATION_SUT"),
        "application/xml",
        3_384,
        "4dfa1711728f343f32296e718a490635aa5d36834a80fcb740e07b6271e7ddde",
    ),
    ResponseSpec(
        "codelist_ACTIVITY",
        "oecd-CL_ACTIVITY_ISIC4.xml",
        "codelist",
        codelist_url("OECD", "CL_ACTIVITY_ISIC4", "1.0"),
        "application/xml",
        821_502,
        "5a591e0b1cc90f2f11499956a576fdcf66f53f7355413d9754e73e1683523bcd",
    ),
    ResponseSpec(
        "codelist_PRODUCT",
        "oecd-CL_PRODUCT_CPA2008.xml",
        "codelist",
        codelist_url("OECD", "CL_PRODUCT_CPA2008", "1.1"),
        "application/xml",
        462_541,
        "486244079b890e405837cd58c03245a8caeef73d70d8a9e34ca656b803865866",
    ),
    ResponseSpec(
        "codelist_TRANSACTION",
        "oecd-CL_TRANSACTION.xml",
        "codelist",
        codelist_url("OECD.SDD.NAD", "CL_TRANSACTION", "1.0"),
        "application/xml",
        179_857,
        "39f82dc031abb83a4d0a6ec240ea07ebaeaf49ba83d8284417bb38734dd01046",
    ),
    ResponseSpec(
        "codelist_VALUATION",
        "oecd-CL_VALUATION.xml",
        "codelist",
        codelist_url("OECD.SDD.NAD", "CL_VALUATION", "1.0"),
        "application/xml",
        10_175,
        "bf0202aa38f934acda5ba8e672562b387ab704cc393d8314bac2cb0e40e94280",
    ),
    ResponseSpec(
        "codelist_TABLE_IDENTIFIER",
        "oecd-CL_TABLEID.xml",
        "codelist",
        codelist_url("OECD.SDD.NAD", "CL_TABLEID", "1.0"),
        "application/xml",
        21_139,
        "e269a17b7712f5a3301198e0fd3a235407cb4eb116fcf6b74e150803ca0057ba",
    ),
    ResponseSpec(
        "codelist_UNIT_MEASURE",
        "oecd-CL_UNIT_MEASURE.xml",
        "codelist",
        codelist_url("OECD", "CL_UNIT_MEASURE", "1.1"),
        "application/xml",
        362_881,
        "c1f1329169f8d7be9cb70fd21042541e2430b712e8f60a48969de740194080b2",
    ),
    ResponseSpec(
        "codelist_OBS_STATUS",
        "oecd-CL_OBS_STATUS.xml",
        "codelist",
        codelist_url("SDMX", "CL_OBS_STATUS", "2.2"),
        "application/xml",
        11_133,
        "16d7b617565b3092c729092c20d4bf068f444174d4e52046c3aa59f5925f41f3",
    ),
    ResponseSpec(
        "codelist_UNIT_MULT",
        "oecd-CL_UNIT_MULT.xml",
        "codelist",
        codelist_url("SDMX", "CL_UNIT_MULT", "1.1"),
        "application/xml",
        9_867,
        "a612348dc8c66484619180873269e0a5c11f7e6aec7f7e4d5801ff42035982fe",
    ),
    ResponseSpec(
        "codelist_CURRENCY",
        "oecd-CL_CURRENCY.xml",
        "codelist",
        codelist_url("OECD", "CL_CURRENCY", "1.1"),
        "application/xml",
        136_696,
        "33f248061109577c51eadf52772f161dabac720bad748963afa5df7f01cb779e",
    ),
    ResponseSpec(
        "codelist_PRICE_BASE",
        "oecd-CL_PRICES.xml",
        "codelist",
        codelist_url("OECD", "CL_PRICES", "1.0"),
        "application/xml",
        9_093,
        "0a123e8e993ddf0e7bf3f9c157c8fe54dd8a584a5ee00197ad28d3076efd8303",
    ),
    ResponseSpec(
        "codelist_CONF_STATUS",
        "oecd-CL_CONF_STATUS.xml",
        "codelist",
        codelist_url("SDMX", "CL_CONF_STATUS", "1.2"),
        "application/xml",
        8_637,
        "efabaf0b3c9710e9583cdb791cab0e63f2613b099828567e8ba615cb0d224b1f",
    ),
    ResponseSpec(
        "codelist_DECIMALS",
        "oecd-CL_DECIMALS.xml",
        "codelist",
        codelist_url("SDMX", "CL_DECIMALS", "1.0"),
        "application/xml",
        3_306,
        "69057e4c6fc19fe82cb5a7c8ee5ee810aaaa7ec10859a26dec703c6279f2a2cc",
    ),
)

TABLE_COMPONENT = {
    "T1600": "purchasers",
    "T1610": "basic",
    "T1620": "combined_margin",
    "T1630": "net_product_tax",
    "T1633": "gross_product_tax",
    "T1634": "subsidy_magnitude",
}
TABLE_DATAFLOW = {
    "T1600": "OECD.SDD.NAD:DSD_NASU@DF_USEPP(2.0)",
    "T1610": "OECD.SDD.NAD:DSD_NASU@DF_USEBP(2.0)",
    "T1620": "OECD.SDD.NAD:DSD_NASU@DF_VALUATION(2.0)",
    "T1630": "OECD.SDD.NAD:DSD_NASU@DF_VALUATION(2.0)",
    "T1633": "OECD.SDD.NAD:DSD_NASU@DF_VALUATION(2.0)",
    "T1634": "OECD.SDD.NAD:DSD_NASU@DF_VALUATION(2.0)",
}
TABLE_VALUATION = {
    "T1600": "O",
    "T1610": "B",
    "T1620": "O",
    "T1630": "O",
    "T1633": "O",
    "T1634": "O",
}
EXPECTED_RAW_ROW_COUNTS = {
    "T1600": 10_495,
    "T1610": 10_918,
    "T1620": 4_500,
    "T1630": 9_723,
    "T1633": 9_555,
    "T1634": 1_425,
}
EXPECTED_SELECTED_ROW_COUNTS = {
    "T1600": 10_495,
    "T1610": 10_673,
    "T1620": 4_500,
    "T1630": 9_723,
    "T1633": 9_555,
    "T1634": 1_425,
}
EXPECTED_SOURCE_TOTALS = {
    "T1600": 5_456_842_235,
    "T1610": 5_355_809_681,
    "T1620": -4,
    "T1630": 101_032_558,
    "T1633": 109_968_166,
    "T1634": 8_935_607,
}

CSV_HEADER = (
    "DATAFLOW",
    "FREQ",
    "REF_AREA",
    "TRANSACTION",
    "ACTIVITY",
    "PRODUCT",
    "UNIT_MEASURE",
    "VALUATION",
    "PRICE_BASE",
    "TABLE_IDENTIFIER",
    "TIME_PERIOD",
    "OBS_VALUE",
    "COUNTERPART_AREA",
    "SECTOR",
    "ACCOUNTING_ENTRY",
    "CONF_STATUS",
    "DECIMALS",
    "OBS_STATUS",
    "UNIT_MULT",
    "CURRENCY",
)
KEY_FIELDS = (
    "TRANSACTION",
    "ACTIVITY",
    "PRODUCT",
    "COUNTERPART_AREA",
    "SECTOR",
    "ACCOUNTING_ENTRY",
)
COMPONENT_ORDER = tuple(TABLE_COMPONENT.values())
XML_LANG = "{http://www.w3.org/XML/1998/namespace}lang"
DECIMAL_RE = re.compile(r"^-?\d+(?:\.\d+)?$")


def fail(message: str) -> None:
    raise RuntimeError(message)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def checked_bytes(spec: ResponseSpec, data: bytes) -> bytes:
    if len(data) != spec.byte_count:
        fail(
            f"{spec.name} byte count changed: "
            f"{len(data)} != {spec.byte_count}"
        )
    actual = sha256(data)
    if actual != spec.sha256:
        fail(f"{spec.name} SHA-256 changed: {actual} != {spec.sha256}")
    return data


def acquire(spec: ResponseSpec, source_dir: Path | None) -> bytes:
    if source_dir is not None:
        return checked_bytes(spec, (source_dir / spec.local_name).read_bytes())
    request = urllib.request.Request(
        spec.url,
        headers={
            "Accept": spec.accept,
            "User-Agent": "BeforeIT-US-OECD-source-axis-fixture/1.0",
        },
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        if response.status != 200:
            fail(f"{spec.name} returned HTTP {response.status}")
        data = response.read()
    return checked_bytes(spec, data)


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def english_name(element: ET.Element) -> str:
    names = [
        child
        for child in element
        if local_name(child.tag) == "Name"
    ]
    for name in names:
        if name.attrib.get(XML_LANG) == "en":
            return (name.text or "").strip()
    return (names[0].text or "").strip() if names else ""


def parse_codelist(data: bytes) -> dict[str, str]:
    root = ET.fromstring(data)
    codelists = [
        element
        for element in root.iter()
        if local_name(element.tag) == "Codelist"
    ]
    if len(codelists) != 1:
        fail(f"expected one codelist, found {len(codelists)}")
    result: dict[str, str] = {}
    for element in codelists[0]:
        if local_name(element.tag) != "Code":
            continue
        code = element.attrib["id"]
        if code in result:
            fail(f"duplicate codelist code {code}")
        label = english_name(element)
        if not label:
            fail(f"codelist code {code} has no label")
        result[code] = label
    return result


@dataclass(frozen=True)
class HierarchyEntry:
    code: str
    parent_code: str
    depth: int
    child_count: int


def parse_hierarchy(data: bytes) -> dict[str, HierarchyEntry]:
    root = ET.fromstring(data)
    hierarchies = [
        element
        for element in root.iter()
        if local_name(element.tag) == "Hierarchy"
    ]
    if len(hierarchies) != 1:
        fail(f"expected one hierarchy, found {len(hierarchies)}")
    result: dict[str, HierarchyEntry] = {}

    def visit(element: ET.Element, parent: str, depth: int) -> None:
        code = element.attrib["id"]
        children = [
            child
            for child in element
            if local_name(child.tag) == "HierarchicalCode"
        ]
        if code in result:
            fail(f"duplicate hierarchy code {code}")
        result[code] = HierarchyEntry(
            code=code,
            parent_code=parent,
            depth=depth,
            child_count=len(children),
        )
        for child in children:
            visit(child, code, depth + 1)

    roots = [
        child
        for child in hierarchies[0]
        if local_name(child.tag) == "HierarchicalCode"
    ]
    if not roots:
        fail("hierarchy has no roots")
    for root_code in roots:
        visit(root_code, "", 0)
    return result


def decimal_hundredths(text: str) -> int:
    if not DECIMAL_RE.match(text):
        fail(f"invalid decimal observation {text!r}")
    value = Decimal(text) * 100
    if value != value.to_integral_value():
        fail(f"observation has more than two decimals: {text}")
    return int(value)


def parse_data(data: bytes, table: str) -> list[dict[str, str | int]]:
    text = data.decode("utf-8")
    reader = csv.DictReader(io.StringIO(text, newline=""))
    if tuple(reader.fieldnames or ()) != CSV_HEADER:
        fail(f"{table} CSV header changed")
    rows: list[dict[str, str | int]] = []
    for source_row in reader:
        if source_row["TABLE_IDENTIFIER"] != table:
            fail(f"{table} response contains {source_row['TABLE_IDENTIFIER']}")
        if source_row["DATAFLOW"] != TABLE_DATAFLOW[table]:
            fail(f"{table} dataflow changed")
        expected = {
            "FREQ": "A",
            "REF_AREA": "USA",
            "UNIT_MEASURE": "XDC",
            "PRICE_BASE": "V",
            "TIME_PERIOD": "2024",
            "CONF_STATUS": "F",
            "DECIMALS": "2",
            "OBS_STATUS": "A",
            "UNIT_MULT": "6",
            "CURRENCY": "USD",
        }
        for field, value in expected.items():
            if source_row[field] != value:
                fail(
                    f"{table} {field} changed: "
                    f"{source_row[field]!r} != {value!r}"
                )
        row: dict[str, str | int] = dict(source_row)
        row["VALUE_HUNDREDTHS_MILLION_USD"] = decimal_hundredths(
            source_row["OBS_VALUE"]
        )
        rows.append(row)
    if len(rows) != EXPECTED_RAW_ROW_COUNTS[table]:
        fail(f"{table} row count changed: {len(rows)}")
    return rows


def key(row: dict[str, str | int]) -> tuple[str, ...]:
    return tuple(str(row[field]) for field in KEY_FIELDS)


def recipient_type(transaction: str, activity: str) -> str:
    if transaction == "TU":
        return "total_use"
    if transaction == "P2" and activity == "_T":
        return "intermediate_use_total"
    if transaction == "P2":
        return "industry_intermediate_use"
    if activity != "_Z":
        fail(
            "final-use transaction has an activity recipient: "
            f"{transaction}/{activity}"
        )
    return "final_use"


def axis_role(
    axis: str,
    code: str,
    hierarchy: dict[str, HierarchyEntry],
) -> str:
    if code == "_Z":
        return "not_applicable"
    if code == "_T":
        return "published_total"
    entry = hierarchy.get(code)
    if entry is None:
        fail(f"{axis} code {code} is absent from its hierarchy")
    return "aggregate" if entry.child_count else "leaf"


def csv_bytes(fieldnames: Iterable[str], rows: Iterable[dict[str, object]]) -> bytes:
    buffer = io.StringIO(newline="")
    writer = csv.DictWriter(
        buffer,
        fieldnames=list(fieldnames),
        lineterminator="\n",
    )
    writer.writeheader()
    writer.writerows(rows)
    return buffer.getvalue().encode("utf-8")


def json_bytes(value: object) -> bytes:
    return (
        json.dumps(
            value,
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
        + "\n"
    ).encode("utf-8")


def quoted(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def source_bundle_sha256() -> str:
    canonical = "".join(
        f"{spec.name}\0{spec.sha256}\0{spec.byte_count}\n"
        for spec in sorted(RESPONSES, key=lambda item: item.name)
    ).encode()
    return sha256(canonical)


def build_fixture(
    response_bytes: dict[str, bytes],
    output_directory: Path,
) -> None:
    codelists = {
        "activity": parse_codelist(response_bytes["codelist_ACTIVITY"]),
        "product": parse_codelist(response_bytes["codelist_PRODUCT"]),
        "transaction": parse_codelist(
            response_bytes["codelist_TRANSACTION"]
        ),
        "valuation": parse_codelist(response_bytes["codelist_VALUATION"]),
        "table_identifier": parse_codelist(
            response_bytes["codelist_TABLE_IDENTIFIER"]
        ),
        "unit_measure": parse_codelist(
            response_bytes["codelist_UNIT_MEASURE"]
        ),
        "obs_status": parse_codelist(
            response_bytes["codelist_OBS_STATUS"]
        ),
        "unit_mult": parse_codelist(response_bytes["codelist_UNIT_MULT"]),
        "currency": parse_codelist(response_bytes["codelist_CURRENCY"]),
        "price_base": parse_codelist(
            response_bytes["codelist_PRICE_BASE"]
        ),
        "conf_status": parse_codelist(
            response_bytes["codelist_CONF_STATUS"]
        ),
        "decimals": parse_codelist(response_bytes["codelist_DECIMALS"]),
    }
    hierarchies = {
        "activity": parse_hierarchy(response_bytes["hierarchy_ACTIVITY"]),
        "product": parse_hierarchy(response_bytes["hierarchy_PRODUCT"]),
        "transaction": parse_hierarchy(
            response_bytes["hierarchy_TRANSACTION"]
        ),
        "valuation": parse_hierarchy(
            response_bytes["hierarchy_VALUATION"]
        ),
    }

    raw_rows = {
        table: parse_data(response_bytes[f"data_{table}"], table)
        for table in TABLE_COMPONENT
    }
    selected_rows: dict[str, list[dict[str, str | int]]] = {}
    excluded_t1610: list[dict[str, str | int]] = []
    for table, rows in raw_rows.items():
        selected = [
            row
            for row in rows
            if row["VALUATION"] == TABLE_VALUATION[table]
        ]
        excluded = [
            row
            for row in rows
            if row["VALUATION"] != TABLE_VALUATION[table]
        ]
        if table == "T1610":
            excluded_t1610 = excluded
            excluded_counts: dict[str, int] = {}
            for row in excluded:
                valuation = str(row["VALUATION"])
                excluded_counts[valuation] = (
                    excluded_counts.get(valuation, 0) + 1
                )
            if excluded_counts != {"O": 123, "Y": 122}:
                fail(
                    "T1610 non-basic valuation counts changed: "
                    f"{excluded_counts}"
                )
        elif excluded:
            fail(f"{table} contains an unexpected valuation")
        if len(selected) != EXPECTED_SELECTED_ROW_COUNTS[table]:
            fail(f"{table} selected row count changed")
        if len({key(row) for row in selected}) != len(selected):
            fail(f"{table} contains duplicate source-axis keys")
        selected_rows[table] = selected

    by_component: dict[str, dict[tuple[str, ...], dict[str, str | int]]] = {}
    for table, component in TABLE_COMPONENT.items():
        by_component[component] = {
            key(row): row for row in selected_rows[table]
        }
    all_keys = sorted(
        set().union(
            *(set(rows_by_key) for rows_by_key in by_component.values())
        )
    )
    if len(all_keys) != 10_675:
        fail(f"source-axis union count changed: {len(all_keys)}")

    used_axis_codes = {
        "transaction": {source_key[0] for source_key in all_keys},
        "activity": {source_key[1] for source_key in all_keys},
        "product": {source_key[2] for source_key in all_keys},
        "valuation": set(TABLE_VALUATION.values()) | {"Y"},
    }
    for axis, codes in used_axis_codes.items():
        missing_labels = codes - set(codelists[axis])
        if missing_labels:
            fail(f"{axis} labels missing for {sorted(missing_labels)}")

    cell_fields = [
        "cell_index",
        "transaction",
        "activity",
        "product",
        "counterpart_area",
        "sector",
        "accounting_entry",
        "recipient_type",
        "transaction_axis_role",
        "activity_axis_role",
        "product_axis_role",
        "unit_measure",
        "unit_mult",
        "currency",
        "decimals",
        "obs_status",
    ]
    for component in COMPONENT_ORDER:
        cell_fields.extend(
            (
                f"{component}_present",
                f"{component}_value_hundredths_million_usd",
                f"{component}_obs_status",
            )
        )

    cell_rows = []
    explicit_zero_counts = {component: 0 for component in COMPONENT_ORDER}
    missing_counts = {component: 0 for component in COMPONENT_ORDER}
    for index, source_key in enumerate(all_keys, start=1):
        transaction, activity, product, counterpart, sector, entry = (
            source_key
        )
        output: dict[str, object] = {
            "cell_index": index,
            "transaction": transaction,
            "activity": activity,
            "product": product,
            "counterpart_area": counterpart,
            "sector": sector,
            "accounting_entry": entry,
            "recipient_type": recipient_type(transaction, activity),
            "transaction_axis_role": axis_role(
                "transaction",
                transaction,
                hierarchies["transaction"],
            ),
            "activity_axis_role": axis_role(
                "activity",
                activity,
                hierarchies["activity"],
            ),
            "product_axis_role": axis_role(
                "product",
                product,
                hierarchies["product"],
            ),
            "unit_measure": "XDC",
            "unit_mult": "6",
            "currency": "USD",
            "decimals": "2",
            "obs_status": "A",
        }
        for component in COMPONENT_ORDER:
            observation = by_component[component].get(source_key)
            if observation is None:
                output[f"{component}_present"] = 0
                output[
                    f"{component}_value_hundredths_million_usd"
                ] = ""
                output[f"{component}_obs_status"] = ""
                missing_counts[component] += 1
            else:
                value = int(observation["VALUE_HUNDREDTHS_MILLION_USD"])
                output[f"{component}_present"] = 1
                output[
                    f"{component}_value_hundredths_million_usd"
                ] = value
                output[f"{component}_obs_status"] = observation["OBS_STATUS"]
                if value == 0:
                    explicit_zero_counts[component] += 1
        cell_rows.append(output)

    identity_specs = (
        (
            "purchasers_equals_basic_plus_margin_plus_net_tax",
            (
                "purchasers",
                "basic",
                "combined_margin",
                "net_product_tax",
            ),
            lambda values: (
                values["purchasers"]
                - values["basic"]
                - values["combined_margin"]
                - values["net_product_tax"]
            ),
        ),
        (
            "net_tax_equals_gross_tax_minus_subsidy",
            (
                "net_product_tax",
                "gross_product_tax",
                "subsidy_magnitude",
            ),
            lambda values: (
                values["net_product_tax"]
                - values["gross_product_tax"]
                + values["subsidy_magnitude"]
            ),
        ),
    )
    identity_rows = []
    evaluated_residuals = {
        identity: [] for identity, _, _ in identity_specs
    }
    not_evaluable_counts = {
        identity: 0 for identity, _, _ in identity_specs
    }
    for identity, components, residual_function in identity_specs:
        for row in cell_rows:
            missing_components = [
                component
                for component in components
                if row[f"{component}_present"] != 1
            ]
            if missing_components:
                status = "NOT_EVALUABLE_SOURCE_MISSING"
                residual: int | str = ""
                not_evaluable_counts[identity] += 1
            else:
                values = {
                    component: int(
                        row[
                            f"{component}_value_hundredths_million_usd"
                        ]
                    )
                    for component in components
                }
                residual = residual_function(values)
                evaluated_residuals[identity].append(residual)
                status = "PASS_AT_SOURCE_ROUNDING"
            identity_rows.append(
                {
                    "cell_index": row["cell_index"],
                    "identity": identity,
                    "status": status,
                    "residual_hundredths_million_usd": residual,
                    "missing_components": ";".join(missing_components),
                }
            )
    valuation_identity = identity_specs[0][0]
    tax_identity = identity_specs[1][0]
    equation_residuals = evaluated_residuals[valuation_identity]
    tax_residuals = evaluated_residuals[tax_identity]
    if max(map(abs, equation_residuals)) > 1:
        fail("P = B + M + T fails source rounding")
    if max(map(abs, tax_residuals)) > 1:
        fail("T = gross tax - subsidy fails source rounding")

    total_key = ("TU", "_Z", "_T", "D", "S1", "D")
    controls = []
    for table, component in TABLE_COMPONENT.items():
        observation = by_component[component].get(total_key)
        if observation is None:
            fail(f"{table} omits the published TU/_Z/_T control")
        total = int(observation["VALUE_HUNDREDTHS_MILLION_USD"])
        if total != EXPECTED_SOURCE_TOTALS[table]:
            fail(f"{table} published source total changed: {total}")
        controls.append(
            {
                "table_identifier": table,
                "component": component,
                "transaction": "TU",
                "activity": "_Z",
                "product": "_T",
                "value_hundredths_million_usd": total,
                "obs_status": observation["OBS_STATUS"],
                "aggregation_policy": "published_total_cell_only",
            }
        )

    axis_rows = []
    for axis in ("transaction", "activity", "product", "valuation"):
        hierarchy = hierarchies[axis]
        for code in sorted(used_axis_codes[axis]):
            entry = hierarchy.get(code)
            if entry is None:
                if code != "_Z":
                    fail(f"{axis} hierarchy missing {code}")
                parent = ""
                depth: int | str = ""
                children: int | str = ""
                leaf: int | str = ""
            else:
                parent = entry.parent_code
                depth = entry.depth
                children = entry.child_count
                leaf = int(entry.child_count == 0)
            axis_rows.append(
                {
                    "axis": axis,
                    "code": code,
                    "label": codelists[axis][code],
                    "parent_code": parent,
                    "depth": depth,
                    "child_count": children,
                    "is_hierarchy_leaf": leaf,
                    "axis_role": axis_role(axis, code, hierarchy),
                }
            )

    nonbasic_fields = [
        "table_identifier",
        "valuation",
        "transaction",
        "activity",
        "product",
        "counterpart_area",
        "sector",
        "accounting_entry",
        "value_hundredths_million_usd",
        "obs_status",
        "quarantine_reason",
    ]
    nonbasic_rows = []
    for row in sorted(
        excluded_t1610,
        key=lambda item: (
            str(item["VALUATION"]),
            key(item),
        ),
    ):
        nonbasic_rows.append(
            {
                "table_identifier": "T1610",
                "valuation": row["VALUATION"],
                "transaction": row["TRANSACTION"],
                "activity": row["ACTIVITY"],
                "product": row["PRODUCT"],
                "counterpart_area": row["COUNTERPART_AREA"],
                "sector": row["SECTOR"],
                "accounting_entry": row["ACCOUNTING_ENTRY"],
                "value_hundredths_million_usd": row[
                    "VALUE_HUNDREDTHS_MILLION_USD"
                ],
                "obs_status": row["OBS_STATUS"],
                "quarantine_reason": (
                    "not_basic_valuation_for_T1610_source_axis_identity"
                ),
            }
        )

    receipts = {
        "schema_version": (
            "beforeit-us-oecd-sut-source-response-receipts.v1"
        ),
        "captured_at_utc": CAPTURED_AT_UTC,
        "credentials_required": False,
        "http_method": "GET",
        "oecd_api_documentation_url": SOURCE_API_DOCUMENTATION_URL,
        "oecd_attribution": (
            "OECD (2026), Supply and Use Tables, OECD Data Explorer "
            f"(accessed {CAPTURED_AT_UTC[:10]})."
        ),
        "oecd_dataset_url": SOURCE_DATASET_URL,
        "oecd_terms_url": SOURCE_TERMS_URL,
        "response_hash_policy": "exact_raw_response_bytes",
        "sdmx_version": "2.0",
        "source_bundle_sha256": source_bundle_sha256(),
        "responses": [
            {
                "accept": spec.accept,
                "byte_count": spec.byte_count,
                "kind": spec.kind,
                "local_name": spec.local_name,
                "name": spec.name,
                "query_parameters": spec.url.partition("?")[2],
                "response_content_type": (
                    "text/csv; charset=utf-8"
                    if spec.kind == "data"
                    else (
                        "application/vnd.sdmx.structure+xml; "
                        "charset=utf-8; version=2.1"
                    )
                ),
                "retrieved_at_utc": CAPTURED_AT_UTC,
                "sha256": spec.sha256,
                "url": spec.url,
            }
            for spec in sorted(RESPONSES, key=lambda item: item.name)
        ],
    }

    output_directory.mkdir(parents=True, exist_ok=True)
    generated: dict[str, bytes] = {
        "cells.csv": csv_bytes(cell_fields, cell_rows),
        "axis_codes.csv": csv_bytes(
            (
                "axis",
                "code",
                "label",
                "parent_code",
                "depth",
                "child_count",
                "is_hierarchy_leaf",
                "axis_role",
            ),
            axis_rows,
        ),
        "source_totals.csv": csv_bytes(
            (
                "table_identifier",
                "component",
                "transaction",
                "activity",
                "product",
                "value_hundredths_million_usd",
                "obs_status",
                "aggregation_policy",
            ),
            controls,
        ),
        "identity_evaluations.csv": csv_bytes(
            (
                "cell_index",
                "identity",
                "status",
                "residual_hundredths_million_usd",
                "missing_components",
            ),
            identity_rows,
        ),
        "t1610_nonbasic_quarantine.csv": csv_bytes(
            nonbasic_fields,
            nonbasic_rows,
        ),
        "source_receipts.json": json_bytes(receipts),
    }
    for filename, data in generated.items():
        (output_directory / filename).write_bytes(data)

    generator_sha = sha256(Path(__file__).read_bytes())
    project_sha = sha256(PROJECT_PATH.read_bytes())
    julia_manifest_sha = sha256(JULIA_MANIFEST_PATH.read_bytes())
    if project_sha != EXPECTED_PROJECT_SHA256:
        fail(f"scripts/us/Project.toml changed: {project_sha}")
    if julia_manifest_sha != EXPECTED_JULIA_MANIFEST_SHA256:
        fail(f"scripts/us/Manifest.toml changed: {julia_manifest_sha}")

    artifact_hashes = {
        filename: sha256(data) for filename, data in generated.items()
    }
    manifest_lines = [
        f"schema_version = {quoted(SCHEMA_VERSION)}",
        f"classification = {quoted(CLASSIFICATION)}",
        'promotion_status = "RESEARCH_ONLY_NOT_PROMOTED"',
        "forecast_origin_admissible = false",
        "model_state_write = false",
        "accounting_gate_effect = \"NONE\"",
        "source_year = 2024",
        "sdmx_version = \"2.0\"",
        f"captured_at_utc = {quoted(CAPTURED_AT_UTC)}",
        f"source_response_count = {len(RESPONSES)}",
        f"source_bundle_sha256 = {quoted(source_bundle_sha256())}",
        (
            "raw_response_path = "
            f"{quoted('scripts/us/accounting/oecd_valuation/raw/oecd_sut_usa_2024_v2')}"
        ),
        f"generator_sha256 = {quoted(generator_sha)}",
        f"project_sha256 = {quoted(project_sha)}",
        f"julia_manifest_sha256 = {quoted(julia_manifest_sha)}",
        f"source_axis_cell_count = {len(cell_rows)}",
        f"axis_code_count = {len(axis_rows)}",
        f"t1610_nonbasic_quarantine_count = {len(nonbasic_rows)}",
        "rounding_tolerance_hundredths_million_usd = 1",
        (
            'source_missing_identity_policy = '
            '"NOT_EVALUABLE_SOURCE_MISSING"'
        ),
        'structural_zero_metadata_status = "ABSENT"',
        "combined_margin_split_status = \"NOT_RUN_BLOCKED\"",
        "model_mapping_status = \"NOT_RUN_BLOCKED\"",
        "state_write_status = \"NOT_RUN_BLOCKED\"",
        "",
        "[fixture_files]",
    ]
    for filename in sorted(artifact_hashes):
        key_name = filename.replace(".", "_")
        manifest_lines.append(
            f"{key_name}_sha256 = {quoted(artifact_hashes[filename])}"
        )
    manifest_lines.extend(
        (
            "",
            "[selected_rows]",
            *(
                f"{table} = {EXPECTED_SELECTED_ROW_COUNTS[table]}"
                for table in TABLE_COMPONENT
            ),
            "",
            "[explicit_zero_counts]",
            *(
                f"{component} = {explicit_zero_counts[component]}"
                for component in COMPONENT_ORDER
            ),
            "",
            "[missing_counts]",
            *(
                f"{component} = {missing_counts[component]}"
                for component in COMPONENT_ORDER
            ),
            "",
            "[equation_diagnostics]",
            (
                "valuation_identity_evaluated_count = "
                f"{len(equation_residuals)}"
            ),
            (
                "valuation_identity_not_evaluable_source_missing_count = "
                f"{not_evaluable_counts[valuation_identity]}"
            ),
            (
                "tax_identity_evaluated_count = "
                f"{len(tax_residuals)}"
            ),
            (
                "tax_identity_not_evaluable_source_missing_count = "
                f"{not_evaluable_counts[tax_identity]}"
            ),
            (
                "maximum_valuation_identity_residual_"
                f"hundredths_million_usd = {max(map(abs, equation_residuals))}"
            ),
            (
                "maximum_tax_identity_residual_"
                f"hundredths_million_usd = {max(map(abs, tax_residuals))}"
            ),
            "",
        )
    )
    (output_directory / "manifest.toml").write_bytes(
        ("\n".join(manifest_lines)).encode("utf-8")
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    source = parser.add_mutually_exclusive_group()
    source.add_argument(
        "--live",
        action="store_true",
        help="download exact public OECD SDMX responses",
    )
    source.add_argument(
        "--source-dir",
        type=Path,
        help=(
            "directory containing the exact response local_name files; "
            "defaults to the checked-in raw response bundle"
        ),
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT,
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source_dir = (
        None
        if args.live
        else (
            args.source_dir.resolve()
            if args.source_dir is not None
            else DEFAULT_RAW_SOURCE.resolve()
        )
    )
    response_bytes = {
        spec.name: acquire(spec, source_dir) for spec in RESPONSES
    }
    build_fixture(response_bytes, args.output_dir.resolve())
    print(f"wrote OECD valuation fixture to {args.output_dir.resolve()}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        raise
