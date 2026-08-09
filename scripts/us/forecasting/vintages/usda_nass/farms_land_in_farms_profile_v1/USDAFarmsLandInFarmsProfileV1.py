#!/usr/bin/env python3
"""Exact present-day USDA NASS farm-count PDF table fingerprint.

This parser is deliberately nonadmitting.  It validates one exact PDF body,
extracts the complete 2018-2025 national table with positional checks, and
keeps every origin/model/scoring gate false.  The raw PDF is not stored in the
repository and the third-party PDF runtime is not an authenticated release.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import re
import stat
import sys
import tomllib
from typing import Any

import pypdf


HERE = Path(__file__).resolve().parent
REPOSITORY_ROOT = HERE.parents[5]
PROFILE_PATH = HERE / "farms_land_in_farms_profile_v1.toml"
FINGERPRINT_PATH = HERE / "present_day_pdf_fingerprint.json"

SCHEMA_VERSION = "beforeit-us-usda-nass-farms-land-in-farms-profile.v1"
FINGERPRINT_SCHEMA = "beforeit-us-usda-nass-farms-land-in-farms-fingerprint.v1"
STATUS = "PRESENT_DAY_PDF_TABLE_PARSED_NONADMITTING"
CLAIM_CEILING = "EXACT_CURRENT_PDF_TABLE_MECHANICS_ONLY_NO_PROSPECTIVE_ORIGIN"
EXPECTED_PROFILE_FILE_SHA256 = "a9103ce97110af8654dc921dcb8a1077d125b3ac320e69351e7c4896a546da3e"
EXPECTED_PROFILE_SEMANTIC_SHA256 = (
    "68f3233505343cedb9e43d702418ef0aa24640126689bae9f068d045e678cffa"
)
EXPECTED_FINGERPRINT_FILE_SHA256 = (
    "f284cfb0f3ed7cc17a90d1d3965a3951358c0cc5fb4d101a9e7cc3b76c46babd"
)
EXPECTED_FINGERPRINT_CONTENT_SHA256 = (
    "9701e2f4e3216222ff7d6e8bc1687bb36526979f3ca4fab671b77c9d538f897c"
)

SOURCE_URL = (
    "https://www.nass.usda.gov/Publications/Todays_Reports/reports/"
    "fnlo0226.pdf"
)
EXPECTED_PDF_SHA256 = "8ed104e9df2280f1daf85ce37b20e68ced001ae23d5c3755c7c32fafecada25b"
EXPECTED_PDF_BYTES = 618_881
MAX_PDF_BYTES = 8 * 1024 * 1024
EXPECTED_PAGE_COUNT = 17
TARGET_PAGE_INDEX = 4
TARGET_PAGE_NUMBER = 5
EXPECTED_PAGE_TEXT_SHA256 = "f87964637727537c2f981e3f3c1282b9abb366456f490aa3f6531605ce0aeb40"
ALLOWED_PYPDF_VERSIONS = ("6.10.0", "6.14.2")

EXPECTED_METADATA = (
    ("/Title", "Farms and Land in Farms 2025 Summary 02/13/2026"),
    ("/Author", "USDA, National Agricultural Statistics Service"),
    ("/Creator", "Microsoft® Word for Microsoft 365"),
    ("/Producer", "Microsoft® Word for Microsoft 365"),
    ("/CreationDate", "D:20260213103330-06'00'"),
    ("/ModDate", "D:20260213103330-06'00'"),
)

EXPECTED_ROWS = (
    (2018, 2_023_200, 898_860, 444),
    (2019, 2_007_600, 894_930, 446),
    (2020, 1_992_200, 893_110, 448),
    (2021, 1_959_550, 888_800, 454),
    (2022, 1_900_650, 879_660, 463),
    (2023, 1_894_950, 878_560, 464),
    (2024, 1_880_000, 876_460, 466),
    (2025, 1_865_000, 873_950, 469),
)

EXPECTED_X = (37.974, 250.55, 399.61, 558.24)
EXPECTED_Y = (702.22, 693.0, 683.78, 674.55, 665.33, 656.09, 646.86, 637.64)
COORDINATE_TOLERANCE = 0.025
INTEGER_TOKEN = re.compile(
    r"^(?:0|[1-9][0-9]{0,9}|[1-9][0-9]{0,2}(?:,[0-9]{3})+)$"
)
SHA256_TOKEN = re.compile(r"^[0-9a-f]{64}$")

SOURCE_PINS = (
    (
        "current_source_configuration",
        "scripts/us/sources.toml",
        "41b2bf73b92fb0cf9d9e02ae836beb91d07cd6a3bd20ecf668882350c86f23c9",
    ),
    (
        "current_pipeline",
        "scripts/us/USPipeline.jl",
        "ce4d8138a1c07fdc9509d7560f307f226dc314eb0a4394270ef1e1014b9ca14d",
    ),
    (
        "prospective_contract",
        "scripts/us/forecasting/vintages/prospective/prospective_2026q3_contract_v2.toml",
        "b24ff0c40172d2a23991fbe75c2fe42c6ba6c6c1f5fd46d079ac6d51429bf98f",
    ),
    (
        "prospective_contract_validator",
        "scripts/us/forecasting/vintages/prospective/USProspectiveAcquisitionContractV2.jl",
        "435df6c4b4de879c0f24d3f9bb9f7504fc6172ae34e94db8cb6ba84282d6e379",
    ),
    (
        "synthetic_v4_trust_schema",
        "scripts/us/forecasting/vintages/prospective/"
        "common_origin_acquisition_v4/USCommonOriginAcquisitionV4.jl",
        "0f4c248950ebee59d1e6b5882db6516cbb539f9e54c7dfbb6b53fe0f7a5f6b4e",
    ),
)

BLOCKING_REASONS = (
    "EXACT_PDF_BODY_NOT_RETAINED_IN_PROSPECTIVE_OBJECT_CATALOG",
    "EXTERNAL_TIMESTAMP_AND_TWO_CUSTODY_DOMAINS_ABSENT",
    "FARM_COUNT_TO_BEFOREIT_FIRM_POPULATION_MAPPING_DUBIOUS",
    "INDEPENDENT_QUALIFIED_LEAF_VERIFIER_ABSENT",
    "ORIGIN_PRECEDENCE_AND_RELEASE_AVAILABILITY_NOT_ATTESTED",
    "PYPDF_RUNTIME_AND_TRANSITIVE_CODE_NOT_AUTHENTICATED",
    "USDA_POLICY_PAGE_BYTES_NOT_CAPTURED",
)

GATE_NAMES = (
    "origin_admissible",
    "profile_qualified",
    "model_input_approved",
    "operator_approved",
    "forecast_emission_allowed",
    "truth_access_allowed",
    "scoring_allowed",
    "accuracy_evidence",
    "promotion_eligible",
    "production_eligible",
    "inventory_mutation_authorized",
)


class ProfileError(ValueError):
    """Fail-closed profile or PDF validation error."""


def _fail(message: str) -> None:
    raise ProfileError(message)


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _canonical_bytes(value: Any) -> bytes:
    def validate(node: Any, location: str) -> None:
        if node is None or type(node) in (bool, int, str):
            return
        if type(node) is list:
            for index, entry in enumerate(node):
                validate(entry, f"{location}[{index}]")
            return
        if type(node) is dict:
            for key, entry in node.items():
                type(key) is str or _fail(f"{location} has a non-string key")
                validate(entry, f"{location}.{key}")
            return
        _fail(f"{location} contains unsupported type {type(node).__name__}")

    validate(value, "canonical")
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def canonical_sha256(value: Any) -> str:
    return _sha256(_canonical_bytes(value))


def _content_sha256(document: dict[str, Any]) -> str:
    candidate = copy.deepcopy(document)
    candidate["artifact"].pop("content_sha256", None)
    return canonical_sha256(candidate)


def _reject_symbolic_components(path: Path) -> None:
    absolute = Path(os.path.abspath(path))
    parts = absolute.parts
    cursor = Path(parts[0])
    for part in parts[1:]:
        cursor /= part
        try:
            info = os.lstat(cursor)
        except FileNotFoundError:
            continue
        stat.S_ISLNK(info.st_mode) and _fail(f"symbolic-link path rejected: {cursor}")


def _stable_read(path: Path, maximum: int) -> bytes:
    _reject_symbolic_components(path)
    before = os.stat(path, follow_symlinks=False)
    stat.S_ISREG(before.st_mode) or _fail(f"not a regular file: {path}")
    before.st_nlink == 1 or _fail(f"hard-linked file rejected: {path}")
    before.st_size <= maximum or _fail(f"file exceeds byte ceiling: {path}")
    data = path.read_bytes()
    after = os.stat(path, follow_symlinks=False)
    identity_before = (
        before.st_dev,
        before.st_ino,
        before.st_size,
        before.st_mtime_ns,
        before.st_ctime_ns,
    )
    identity_after = (
        after.st_dev,
        after.st_ino,
        after.st_size,
        after.st_mtime_ns,
        after.st_ctime_ns,
    )
    identity_before == identity_after or _fail(f"file changed while read: {path}")
    len(data) == before.st_size or _fail(f"short file read: {path}")
    return data


def _expect_exact_keys(table: Any, keys: tuple[str, ...], location: str) -> dict[str, Any]:
    type(table) is dict or _fail(f"{location} must be a table")
    set(table) == set(keys) or _fail(f"{location} keys differ from the closed profile")
    return table


def _expect_exact_bool(value: Any, expected: bool, location: str) -> None:
    type(value) is bool or _fail(f"{location} must be Bool")
    value is expected or _fail(f"{location} changed")


def _expect_exact_int(value: Any, expected: int, location: str) -> None:
    type(value) is int or _fail(f"{location} must be Integer")
    value == expected or _fail(f"{location} changed")


def _validate_profile_document(document: dict[str, Any]) -> None:
    _expect_exact_keys(
        document,
        (
            "artifact",
            "source",
            "selector",
            "parser",
            "result",
            "model_mapping",
            "gates",
            "blocking_reasons",
            "sources",
            "prohibited_actions",
        ),
        "profile",
    )
    artifact = _expect_exact_keys(
        document["artifact"],
        ("schema_version", "status", "claim_ceiling", "content_sha256"),
        "artifact",
    )
    artifact["schema_version"] == SCHEMA_VERSION or _fail("schema version changed")
    artifact["status"] == STATUS or _fail("status changed")
    artifact["claim_ceiling"] == CLAIM_CEILING or _fail("claim ceiling changed")
    artifact["content_sha256"] == EXPECTED_PROFILE_SEMANTIC_SHA256 or _fail(
        "stored profile semantic identity changed"
    )
    _content_sha256(document) == EXPECTED_PROFILE_SEMANTIC_SHA256 or _fail(
        "profile semantic identity mismatch"
    )

    source = _expect_exact_keys(
        document["source"],
        (
            "agency",
            "url",
            "expected_pdf_sha256",
            "expected_pdf_bytes",
            "body_preserved_in_repository",
            "evidence_class",
        ),
        "source",
    )
    source["agency"] == "USDA National Agricultural Statistics Service" or _fail("agency changed")
    source["url"] == SOURCE_URL or _fail("source URL changed")
    source["expected_pdf_sha256"] == EXPECTED_PDF_SHA256 or _fail("PDF hash changed")
    _expect_exact_int(
        source["expected_pdf_bytes"],
        EXPECTED_PDF_BYTES,
        "source.expected_pdf_bytes",
    )
    _expect_exact_bool(
        source["body_preserved_in_repository"],
        False,
        "source.body_preserved_in_repository",
    )
    source["evidence_class"] == "present_day_ephemeral_retrieval_nonprospective" or _fail(
        "evidence class changed"
    )

    selector = _expect_exact_keys(
        document["selector"],
        ("profile_selector", "reference_year", "geography", "series", "unit", "page_number"),
        "selector",
    )
    exact_selector = (
        "USDA:NASS:FarmsAndLandInFarms:Report=2025_summary_containing_2024:"
        "ReferenceYear=2024:Geography=US:Series=number_of_farms:Unit=farms"
    )
    selector["profile_selector"] == exact_selector or _fail("profile selector changed")
    _expect_exact_int(selector["reference_year"], 2024, "selector.reference_year")
    selector["geography"] == "United States" or _fail("selector geography changed")
    selector["series"] == "number_of_farms" or _fail("selector series changed")
    selector["unit"] == "farms" or _fail("selector unit changed")
    _expect_exact_int(selector["page_number"], 5, "selector.page_number")

    parser = _expect_exact_keys(
        document["parser"],
        (
            "allowed_pypdf_versions",
            "page_text_sha256",
            "expected_page_count",
            "runtime_authenticated",
            "full_table_required",
            "positional_binding_required",
        ),
        "parser",
    )
    parser["allowed_pypdf_versions"] == list(ALLOWED_PYPDF_VERSIONS) or _fail(
        "pypdf versions changed"
    )
    parser["page_text_sha256"] == EXPECTED_PAGE_TEXT_SHA256 or _fail("page text identity changed")
    _expect_exact_int(
        parser["expected_page_count"],
        EXPECTED_PAGE_COUNT,
        "parser.expected_page_count",
    )
    _expect_exact_bool(parser["runtime_authenticated"], False, "parser.runtime_authenticated")
    _expect_exact_bool(parser["full_table_required"], True, "parser.full_table_required")
    _expect_exact_bool(
        parser["positional_binding_required"],
        True,
        "parser.positional_binding_required",
    )

    result = _expect_exact_keys(
        document["result"],
        (
            "status",
            "reference_year",
            "number_of_farms",
            "adjacent_year",
            "adjacent_number_of_farms",
            "table_mechanics_validated",
            "prospective_profile_qualified",
        ),
        "result",
    )
    result["status"] == STATUS or _fail("result status changed")
    _expect_exact_int(result["reference_year"], 2024, "result.reference_year")
    _expect_exact_int(result["number_of_farms"], 1_880_000, "result.number_of_farms")
    _expect_exact_int(result["adjacent_year"], 2025, "result.adjacent_year")
    _expect_exact_int(
        result["adjacent_number_of_farms"],
        1_865_000,
        "result.adjacent_number_of_farms",
    )
    _expect_exact_bool(
        result["table_mechanics_validated"],
        True,
        "result.table_mechanics_validated",
    )
    _expect_exact_bool(
        result["prospective_profile_qualified"],
        False,
        "result.prospective_profile_qualified",
    )

    mapping = _expect_exact_keys(
        document["model_mapping"],
        ("target_model_industry", "mapping_status", "one_farm_equals_one_model_firm"),
        "model_mapping",
    )
    mapping["target_model_industry"] == "111CA Farms" or _fail("model industry changed")
    mapping["mapping_status"] == "DUBIOUS_NOT_APPROVED" or _fail("mapping status changed")
    _expect_exact_bool(
        mapping["one_farm_equals_one_model_firm"],
        False,
        "model_mapping.one_farm_equals_one_model_firm",
    )

    gates = document["gates"]
    set(gates) == set(GATE_NAMES) or _fail("gate set changed")
    for name in GATE_NAMES:
        _expect_exact_bool(gates[name], False, f"gates.{name}")
    document["blocking_reasons"] == list(BLOCKING_REASONS) or _fail("blocking reasons changed")

    sources = document["sources"]
    type(sources) is list and len(sources) == len(SOURCE_PINS) or _fail("source bindings changed")
    for index, row in enumerate(sources):
        _expect_exact_keys(row, ("binding_id", "path", "sha256"), f"sources[{index}]")
    actual = tuple(
        (row["binding_id"], row["path"], row["sha256"])
        for row in sources
    )
    actual == SOURCE_PINS or _fail("source pins changed")
    actions = document["prohibited_actions"]
    actions == [
        "network_request",
        "write_raw",
        "admit_origin",
        "approve_model_mapping",
        "emit_forecast",
        "load_truth",
        "score",
        "mutate_inventory",
        "promote",
        "register_production",
    ] or _fail("prohibited actions changed")


def validate_profile(root: Path = REPOSITORY_ROOT) -> dict[str, Any]:
    profile_bytes = _stable_read(PROFILE_PATH, 256 * 1024)
    _sha256(profile_bytes) == EXPECTED_PROFILE_FILE_SHA256 or _fail(
        "profile file identity changed"
    )
    document = tomllib.loads(profile_bytes.decode("utf-8", errors="strict"))
    _validate_profile_document(document)
    normalized_root = Path(os.path.abspath(root))
    for binding_id, relative, expected in SOURCE_PINS:
        target = normalized_root / relative
        target.relative_to(normalized_root)
        data = _stable_read(target, 64 * 1024 * 1024)
        _sha256(data) == expected or _fail(f"source hash mismatch: {binding_id}")
    return document


def _parse_integer_token(text: str, location: str) -> int:
    type(text) is str and INTEGER_TOKEN.fullmatch(text) or _fail(
        f"invalid integer token at {location}"
    )
    return int(text.replace(",", ""))


def _extract_table_from_fragments(
    fragments: list[tuple[str, float, float]],
) -> list[dict[str, int]]:
    type(fragments) is list or _fail("fragments must be a list")
    normalized: list[tuple[str, float, float]] = []
    for index, row in enumerate(fragments):
        type(row) is tuple and len(row) == 3 or _fail(f"fragment {index} shape changed")
        text, x, y = row
        type(text) is str or _fail(f"fragment {index} text must be String")
        type(x) is float and type(y) is float or _fail(
            f"fragment {index} coordinates must be Float"
        )
        normalized.append((text, x, y))

    def at(expected_x: float, expected_y: float, location: str) -> str:
        matches = [
            text
            for text, x, y in normalized
            if abs(x - expected_x) <= COORDINATE_TOLERANCE
            and abs(y - expected_y) <= COORDINATE_TOLERANCE
        ]
        len(matches) == 1 or _fail(f"{location} has {len(matches)} positional matches")
        return matches[0]

    rows: list[dict[str, int]] = []
    for index, expected in enumerate(EXPECTED_ROWS):
        year_token = at(EXPECTED_X[0], EXPECTED_Y[index], f"row[{index}].year")
        farm_token = at(EXPECTED_X[1], EXPECTED_Y[index], f"row[{index}].farms")
        land_token = at(EXPECTED_X[2], EXPECTED_Y[index], f"row[{index}].land")
        size_token = at(EXPECTED_X[3], EXPECTED_Y[index], f"row[{index}].size")
        row = {
            "year": _parse_integer_token(year_token, f"row[{index}].year"),
            "number_of_farms": _parse_integer_token(farm_token, f"row[{index}].farms"),
            "land_in_farms_thousand_acres": _parse_integer_token(land_token, f"row[{index}].land"),
            "average_farm_size_acres": _parse_integer_token(size_token, f"row[{index}].size"),
        }
        tuple(row.values()) == expected or _fail(f"row[{index}] differs from the exact table")
        rows.append(row)
    return rows


def _expected_fingerprint() -> dict[str, Any]:
    metadata = {key.removeprefix("/"): value for key, value in EXPECTED_METADATA}
    rows = [
        {
            "year": year,
            "number_of_farms": farms,
            "land_in_farms_thousand_acres": land,
            "average_farm_size_acres": size,
        }
        for year, farms, land, size in EXPECTED_ROWS
    ]
    result: dict[str, Any] = {
        "artifact": {
            "schema_version": FINGERPRINT_SCHEMA,
            "status": STATUS,
            "claim_ceiling": CLAIM_CEILING,
            "content_sha256": "",
        },
        "source": {
            "agency": "USDA National Agricultural Statistics Service",
            "url": SOURCE_URL,
            "raw_pdf_sha256": EXPECTED_PDF_SHA256,
            "raw_pdf_bytes": EXPECTED_PDF_BYTES,
            "raw_pdf_preserved_in_repository": False,
            "retrieval_class": "present_day_ephemeral_nonprospective",
            "publisher_authenticated": False,
            "metadata": metadata,
        },
        "parser": {
            "page_count": EXPECTED_PAGE_COUNT,
            "page_number": TARGET_PAGE_NUMBER,
            "page_text_sha256": EXPECTED_PAGE_TEXT_SHA256,
            "full_table_and_positions_validated": True,
            "runtime_authenticated": False,
        },
        "table": {
            "title": (
                "Number of Farms, Land in Farms, and Average Farm Size – "
                "United States: 2018-2025"
            ),
            "geography": "United States",
            "number_of_farms_unit": "number",
            "land_in_farms_unit": "thousand_acres",
            "average_farm_size_unit": "acres",
            "rows": rows,
        },
        "selected_profile": {
            "report": "2025_summary_containing_2024",
            "reference_year": 2024,
            "geography": "United States",
            "series": "number_of_farms",
            "unit": "farms",
            "value": 1_880_000,
            "adjacent_year": 2025,
            "adjacent_value": 1_865_000,
        },
        "model_mapping": {
            "target_model_industry": "111CA Farms",
            "mapping_status": "DUBIOUS_NOT_APPROVED",
            "one_farm_equals_one_model_firm": False,
        },
        "gates": {name: False for name in GATE_NAMES},
        "blocking_reasons": list(BLOCKING_REASONS),
    }
    payload = copy.deepcopy(result)
    payload["artifact"].pop("content_sha256")
    result["artifact"]["content_sha256"] = canonical_sha256(payload)
    return result


def validate_fingerprint(value: Any) -> dict[str, Any]:
    type(value) is dict or _fail("fingerprint must be an object")
    value == _expected_fingerprint() or _fail(
        "fingerprint differs from source-rederived exact result"
    )
    payload = copy.deepcopy(value)
    stored = payload["artifact"].pop("content_sha256")
    SHA256_TOKEN.fullmatch(stored) or _fail("fingerprint content hash is malformed")
    canonical_sha256(payload) == stored or _fail("fingerprint content hash mismatch")
    stored == EXPECTED_FINGERPRINT_CONTENT_SHA256 or _fail("fingerprint semantic identity changed")
    return value


def validate_stored_fingerprint(root: Path = REPOSITORY_ROOT) -> dict[str, Any]:
    validate_profile(root)
    data = _stable_read(FINGERPRINT_PATH, 256 * 1024)
    _sha256(data) == EXPECTED_FINGERPRINT_FILE_SHA256 or _fail("fingerprint file identity changed")
    value = json.loads(data.decode("utf-8", errors="strict"))
    return validate_fingerprint(value)


def parse_exact_pdf(path: Path, root: Path = REPOSITORY_ROOT) -> dict[str, Any]:
    validate_profile(root)
    pypdf.__version__ in ALLOWED_PYPDF_VERSIONS or _fail(
        "pypdf version is outside the frozen diagnostic set"
    )
    data = _stable_read(path, MAX_PDF_BYTES)
    len(data) == EXPECTED_PDF_BYTES or _fail("PDF byte count changed")
    _sha256(data) == EXPECTED_PDF_SHA256 or _fail("PDF body identity changed")
    data.startswith(b"%PDF-1.7") or _fail("PDF version signature changed")
    data.rstrip().endswith(b"%%EOF") or _fail("PDF terminal marker changed")

    reader = pypdf.PdfReader(io.BytesIO(data), strict=True)
    reader.is_encrypted and _fail("encrypted PDF rejected")
    len(reader.pages) == EXPECTED_PAGE_COUNT or _fail("PDF page count changed")
    metadata = dict(reader.metadata or {})
    for key, expected in EXPECTED_METADATA:
        metadata.get(key) == expected or _fail(f"PDF metadata changed: {key}")

    page = reader.pages[TARGET_PAGE_INDEX]
    page_text = page.extract_text()
    type(page_text) is str or _fail("page text extraction failed")
    _sha256(page_text.encode("utf-8")) == EXPECTED_PAGE_TEXT_SHA256 or _fail(
        "page text identity changed"
    )
    fragments: list[tuple[str, float, float]] = []

    def visitor(text: str, _cm: Any, tm: Any, _font: Any, _size: Any) -> None:
        stripped = text.strip()
        if stripped:
            fragments.append((stripped, float(tm[4]), float(tm[5])))

    page.extract_text(visitor_text=visitor)
    rows = _extract_table_from_fragments(fragments)
    rows == _expected_fingerprint()["table"]["rows"] or _fail("table rows changed")
    return validate_fingerprint(_expected_fingerprint())


def _main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pdf", type=Path)
    parser.add_argument("--validate-stored", action="store_true")
    args = parser.parse_args(argv)
    if bool(args.pdf) == bool(args.validate_stored):
        parser.error("choose exactly one of --pdf or --validate-stored")
    result = parse_exact_pdf(args.pdf) if args.pdf else validate_stored_fingerprint()
    sys.stdout.buffer.write(_canonical_bytes(result) + b"\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv[1:]))
