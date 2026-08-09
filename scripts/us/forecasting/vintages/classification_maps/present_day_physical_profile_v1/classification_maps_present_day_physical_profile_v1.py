#!/usr/bin/env python3
"""Strict present-day OOXML diagnostics for six classification-map profiles.

This stdlib-only module verifies six exact external workbook bodies and one
repository-local bridge receipt.  Its result is a physical-layout derivative,
never provider provenance, an admitted origin, a model input, or evidence that
the accepted logical profile is compatible with the observed bodies.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import posixpath
import stat
import struct
import sys
import tomllib
import zipfile
import zlib
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Mapping, Sequence
from urllib.parse import urlsplit
from xml.etree import ElementTree as ET

sys.dont_write_bytecode = True

SCHEMA_VERSION = "beforeit-us-classification-maps-physical-derivative.v1"
PROFILE_SCHEMA_VERSION = (
    "beforeit-us-classification-maps-present-day-physical-profile.v1"
)
GENERATOR_VERSION = "beforeit-us-classification-maps-ooxml-parser.v1"
STATUS = "CANNOT_RUN"
ROLE = "PRESENT_DAY_PHYSICAL_LAYOUT_DIAGNOSTIC_NONADMITTING"
CANONICALIZATION = "utf8-sorted-keys-compact-json-lf.v1"
MODULE_PATH = Path(os.path.abspath(__file__))
PROFILE_PATH = MODULE_PATH.with_name(
    "classification_maps_present_day_physical_profile_v1.json"
)
EXPECTED_PROFILE_PHYSICAL_SHA256 = (
    "57eefdcb3421a5f63ec8214b6c55feb0700fda4018340ea584863e55f89398fc"
)

MAX_RAW_BYTES = 16 * 1024 * 1024
MAX_ZIP_MEMBERS = 256
MAX_MEMBER_BYTES = 32 * 1024 * 1024
MAX_TOTAL_UNCOMPRESSED_BYTES = 128 * 1024 * 1024
MAX_COMPRESSION_RATIO = 1000
MAX_XML_CHARACTERS = 64 * 1024 * 1024
MAX_XML_ELEMENTS = 1_000_000
MAX_XML_DEPTH = 128
MAX_XML_ATTRIBUTES = 64
MAX_WORKSHEET_ROWS = 100_000
MAX_WORKSHEET_COLUMNS = 4_096

MAIN = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
DOC_REL = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"
DOC_REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PKG_REL = "{http://schemas.openxmlformats.org/package/2006/relationships}"
PKG_REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"
CONTENT_TYPES = "{http://schemas.openxmlformats.org/package/2006/content-types}"
RELATIONSHIPS_CONTENT_TYPE = (
    "application/vnd.openxmlformats-package.relationships+xml"
)
WORKBOOK_CONTENT_TYPE = (
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"
)
WORKSHEET_CONTENT_TYPE = (
    "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"
)
SHARED_STRINGS_CONTENT_TYPE = (
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"
)
STYLES_CONTENT_TYPE = (
    "application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"
)
THEME_CONTENT_TYPE = "application/vnd.openxmlformats-officedocument.theme+xml"
CORE_CONTENT_TYPE = "application/vnd.openxmlformats-package.core-properties+xml"
APP_CONTENT_TYPE = (
    "application/vnd.openxmlformats-officedocument.extended-properties+xml"
)
CUSTOM_CONTENT_TYPE = (
    "application/vnd.openxmlformats-officedocument.custom-properties+xml"
)
PRINTER_CONTENT_TYPE = (
    "application/vnd.openxmlformats-officedocument.spreadsheetml.printerSettings"
)

SOURCE_IDS = (
    "bea_summary_use_2024",
    "bea_summary_make_2024",
    "bea_industry_commodity_naics_concordance",
    "naics_2017_structure",
    "naics_2017_to_2022_concordance",
    "naics_2022_structure",
)
PROFILE_IDS = (
    "bea_summary_codes",
    "bea_industry_commodity_naics_concordance",
    "beforeit_bea71_model_bridge",
    "naics_2017",
    "naics_2017_to_2022",
    "naics_2022",
)
HARD_FALSE_GATES = (
    "accuracy_claim_allowed",
    "forecast_execution_allowed",
    "inventory_mutation_authorized",
    "model_input_allowed",
    "origin_admissible",
    "production_allowed",
    "promotion_allowed",
    "provider_provenance_verified",
    "ready",
    "scoring_allowed",
    "transport_authenticated",
    "truth_access_allowed",
)
ALLOWED_RELATION_TYPES = (
    DOC_REL_NS + "/extended-properties",
    PKG_REL_NS + "/metadata/core-properties",
    DOC_REL_NS + "/officeDocument",
    DOC_REL_NS + "/worksheet",
    DOC_REL_NS + "/styles",
    DOC_REL_NS + "/theme",
    DOC_REL_NS + "/sharedStrings",
    DOC_REL_NS + "/printerSettings",
    DOC_REL_NS + "/custom-properties",
)
RELATION_CONTENT_TYPE_RULES = (
    (DOC_REL_NS + "/extended-properties", APP_CONTENT_TYPE),
    (PKG_REL_NS + "/metadata/core-properties", CORE_CONTENT_TYPE),
    (DOC_REL_NS + "/officeDocument", WORKBOOK_CONTENT_TYPE),
    (DOC_REL_NS + "/worksheet", WORKSHEET_CONTENT_TYPE),
    (DOC_REL_NS + "/styles", STYLES_CONTENT_TYPE),
    (DOC_REL_NS + "/theme", THEME_CONTENT_TYPE),
    (DOC_REL_NS + "/sharedStrings", SHARED_STRINGS_CONTENT_TYPE),
    (DOC_REL_NS + "/printerSettings", PRINTER_CONTENT_TYPE),
    (DOC_REL_NS + "/custom-properties", CUSTOM_CONTENT_TYPE),
)


class ProfileError(ValueError):
    """A fail-closed profile or workbook validation failure."""


@dataclass(frozen=True)
class SourcePin:
    source_id: str
    parser_kind: str
    sha256: str
    byte_count: int


SOURCE_PINS = (
    SourcePin(
        "bea_summary_use_2024",
        "bea_summary_use_axis",
        "9e3791d657909843ce202161bae00cf8a425d7e1bf866cc8a0462810f0ae00c7",
        1_163_798,
    ),
    SourcePin(
        "bea_summary_make_2024",
        "bea_summary_make_axis",
        "073b87c7e52e76fb78ad7ddafb0c2e60f9188fc5a4e56dc0094f4a7ae3f529c6",
        598_989,
    ),
    SourcePin(
        "bea_industry_commodity_naics_concordance",
        "bea_industry_commodity_naics_concordance",
        "6e25267ff60ccedc0808c14153b0cdeb566a7f5e9097536c70c2b9694ef5ff47",
        61_081,
    ),
    SourcePin(
        "naics_2017_structure",
        "naics_structure_2017",
        "662b5a2bdff10938997acd7f59f84331527d6f06ff24d5533331581a00a94aad",
        95_610,
    ),
    SourcePin(
        "naics_2017_to_2022_concordance",
        "naics_2017_to_2022_concordance",
        "4662cc7ed9e7f3fb8a968e9504a7d06e448f5b65a349996a5627439df193eb30",
        59_656,
    ),
    SourcePin(
        "naics_2022_structure",
        "naics_structure_2022",
        "217c9e0d4d74e7517bc288f5f308b73aa0de5ee787976a6dd222412be28ada22",
        88_218,
    ),
)


@dataclass(frozen=True)
class Cell:
    coordinate: str
    row: int
    column: int
    cell_type: str
    style: int
    raw_value: str | None
    display: str | None


@dataclass(frozen=True)
class SharedString:
    index: int
    text: str
    run_count: int
    text_node_count: int


@dataclass(frozen=True)
class Sheet:
    name: str
    sheet_id: int
    relationship_id: str
    part_name: str
    state: str
    dimension: str
    row_element_count: int
    cell_count: int
    cell_manifest_sha256: str
    xml_sha256: str
    shared_reference_count: int
    shared_indexes: frozenset[int]
    cells: tuple[Cell, ...]


@dataclass(frozen=True)
class Workbook:
    raw_sha256: str
    raw_byte_count: int
    members: tuple[dict[str, Any], ...]
    content_types: tuple[dict[str, str], ...]
    resolved_content_types: tuple[tuple[str, str], ...]
    relationships: tuple[dict[str, str], ...]
    shared_strings: tuple[SharedString, ...]
    shared_count: int
    shared_unique_count: int
    shared_semantic_sha256: str
    style_count: int
    styles_xml_sha256: str
    styles_semantic_sha256: str
    defined_names: tuple[dict[str, Any], ...]
    sheets: tuple[Sheet, ...]


def fail(message: str) -> None:
    raise ProfileError(message)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_json_bytes(value: Any) -> bytes:
    try:
        text = json.dumps(
            value,
            ensure_ascii=False,
            allow_nan=False,
            sort_keys=True,
            separators=(",", ":"),
        )
    except (TypeError, ValueError) as error:
        raise ProfileError("value is not canonical-JSON serializable") from error
    return (text + "\n").encode("utf-8")


def _reject_duplicate_json_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            fail("duplicate JSON key: " + key)
        result[key] = value
    return result


def _reject_nonfinite_json_constant(value: str) -> None:
    fail("non-finite JSON constant is forbidden: " + value)


def parse_json_bytes(data: bytes, location: str) -> dict[str, Any]:
    if data.startswith(b"\xef\xbb\xbf"):
        fail(location + " must be BOM-free strict UTF-8 JSON")
    try:
        text = data.decode("utf-8")
        value = json.loads(
            text,
            object_pairs_hook=_reject_duplicate_json_keys,
            parse_constant=_reject_nonfinite_json_constant,
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ProfileError(location + " is not strict UTF-8 JSON") from error
    if type(value) is not dict:
        fail(location + " must contain one exact JSON object")
    return value


def _is_sha256_text(value: Any) -> bool:
    return (
        type(value) is str
        and len(value) == 64
        and all(character in "0123456789abcdef" for character in value)
    )


def _is_uint_text(value: Any, *, positive: bool = False) -> bool:
    if type(value) is not str or not value or not value.isascii():
        return False
    if not all("0" <= character <= "9" for character in value):
        return False
    if len(value) > 1 and value[0] == "0":
        return False
    return not positive or value != "0"


def _hard_false_gates() -> dict[str, bool]:
    return {name: False for name in HARD_FALSE_GATES}


def _exact_json_tree(value: Any, location: str = "document") -> None:
    value_type = type(value)
    if value_type is dict:
        for key, child in value.items():
            if type(key) is not str:
                fail(location + " contains a non-string JSON object key")
            _exact_json_tree(child, location + "." + key)
        return
    if value_type is list:
        for index, child in enumerate(value):
            _exact_json_tree(child, f"{location}[{index}]")
        return
    if value_type not in (str, int, bool, type(None)):
        fail(location + " contains a non-exact JSON concrete type")


def _profile_semantic_hash(document: Mapping[str, Any]) -> str:
    copied = parse_json_bytes(canonical_json_bytes(document), "profile copy")
    artifact = copied.get("artifact")
    if type(artifact) is not dict or "content_sha256" not in artifact:
        fail("profile semantic hash field is missing")
    del artifact["content_sha256"]
    return sha256_bytes(canonical_json_bytes(copied))


def _path_components_are_not_links(path: Path, location: str) -> None:
    current = Path(path.anchor)
    for component in path.parts[1:]:
        current /= component
        try:
            state = os.lstat(current)
        except OSError as error:
            raise ProfileError(location + " path component is unavailable") from error
        if stat.S_ISLNK(state.st_mode):
            fail(location + " path contains a symbolic-link component")


def _read_stable_regular_file(
    path: Path,
    location: str,
    *,
    max_bytes: int = MAX_RAW_BYTES,
) -> tuple[bytes, tuple[int, int]]:
    if type(path) is not type(Path()) or not path.is_absolute():
        fail(location + " path must be pathlib.Path and absolute")
    absolute = Path(os.path.abspath(os.fspath(path)))
    if absolute != path:
        fail(location + " path must use canonical absolute spelling")
    _path_components_are_not_links(absolute, location)
    try:
        if absolute.resolve(strict=True) != absolute:
            fail(location + " path contains an alias component")
    except OSError as error:
        raise ProfileError(location + " path cannot be resolved") from error
    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(absolute, flags)
    except OSError as error:
        raise ProfileError(location + " cannot be opened safely") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            fail(location + " must be a single-link regular file")
        if before.st_size > max_bytes:
            fail(location + " exceeds its raw-byte bound")
        chunks: list[bytes] = []
        total = 0
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > max_bytes:
                fail(location + " exceeds its raw-byte bound")
            chunks.append(chunk)
        after = os.fstat(descriptor)
        _path_components_are_not_links(absolute, location)
        path_state = os.stat(absolute, follow_symlinks=False)
        stable_fields = (
            "st_dev",
            "st_ino",
            "st_size",
            "st_mode",
            "st_nlink",
            "st_mtime_ns",
            "st_ctime_ns",
        )
        if any(
            getattr(before, field) != getattr(after, field)
            or getattr(before, field) != getattr(path_state, field)
            for field in stable_fields
        ):
            fail(location + " changed during its stable read")
        data = b"".join(chunks)
        if len(data) != before.st_size:
            fail(location + " size changed during its stable read")
        if absolute.resolve(strict=True) != absolute:
            fail(location + " path identity changed during its stable read")
        return data, (before.st_dev, before.st_ino)
    finally:
        os.close(descriptor)


def _load_profile_bytes() -> tuple[bytes, dict[str, Any]]:
    data, _ = _read_stable_regular_file(PROFILE_PATH, "physical profile")
    if sha256_bytes(data) != EXPECTED_PROFILE_PHYSICAL_SHA256:
        fail("physical profile SHA-256 drifted")
    document = parse_json_bytes(data, "physical profile")
    validate_profile_document(document)
    return data, document


def load_profile() -> dict[str, Any]:
    """Return a detached exact-JSON copy after mandatory profile verification."""

    _, document = _load_profile_bytes()
    return parse_json_bytes(canonical_json_bytes(document), "detached profile")


def validate_profile_document(document: Mapping[str, Any]) -> None:
    """Validate the exact immutable profile boundary without a bypass."""

    if type(document) is not dict:
        fail("profile must be an exact dict")
    _exact_json_tree(document, "profile")
    if set(document) != {
        "artifact",
        "boundary",
        "gates",
        "local_bridge",
        "logical_profile_pins",
        "mismatch_contract",
        "object_profiles",
        "ooxml_policy",
        "runtime_ceiling",
        "sources",
    }:
        fail("profile top-level schema drifted")
    artifact = document["artifact"]
    if (
        type(artifact) is not dict
        or set(artifact)
        != {"schema_version", "status", "role", "canonicalization", "content_sha256"}
        or artifact.get("schema_version") != PROFILE_SCHEMA_VERSION
    ):
        fail("profile artifact schema drifted")
    if (
        artifact.get("status") != STATUS
        or artifact.get("role") != ROLE
        or artifact.get("canonicalization") != CANONICALIZATION
        or not _is_sha256_text(artifact.get("content_sha256"))
        or _profile_semantic_hash(document) != artifact["content_sha256"]
    ):
        fail("profile artifact ceiling or semantic hash drifted")
    boundary = document["boundary"]
    expected_boundary_keys = {
        "artifact_tool_corroboration_available_in_candidate_runtime",
        "body_to_provider_provenance_verified",
        "body_to_url_provenance_verified",
        "current_bodies_claimed_as_forecast_origin",
        "current_bodies_claimed_as_model_input",
        "current_bodies_claimed_as_truth",
        "external_bodies_committed_to_repository",
        "logical_profile_compatible",
        "observation_date",
        "physically_qualified_profile_count",
        "profile_count",
        "self_accepted",
        "source_claim",
        "status_reason",
    }
    if (
        type(boundary) is not dict
        or set(boundary) != expected_boundary_keys
        or boundary.get("profile_count") != 6
        or boundary.get("physically_qualified_profile_count") != 0
        or boundary.get("logical_profile_compatible") is not False
        or boundary.get("self_accepted") is not False
        or boundary.get("observation_date") != "2026-08-08"
        or boundary.get("artifact_tool_corroboration_available_in_candidate_runtime")
        is not False
        or boundary.get("external_bodies_committed_to_repository") is not False
        or boundary.get("source_claim")
        != "EXACT_LOCAL_SERVER_BODY_BYTES_ONLY_NO_URL_OR_PROVIDER_PROVENANCE"
        or boundary.get("status_reason")
        != "OFFICIAL_CURRENT_WORKBOOK_BODIES_AND_CURRENT_ORIGIN_RECEIPTS_REQUIRED_FOR_QUALIFICATION"
    ):
        fail("profile boundary rose above CANNOT_RUN")
    for key, value in boundary.items():
        if key.endswith("_verified") or key.startswith("current_bodies_claimed_"):
            if value is not False:
                fail("profile boundary contains a raised evidence claim")
    if type(document["gates"]) is not dict or document["gates"] != _hard_false_gates():
        fail("profile gates are not exactly hard false")
    pins = document["logical_profile_pins"]
    expected_logical = (
        ("module_sha256", "f5890e959dc80c8fdda1507d73dba3658d4fa5720daaa3adc7cfb8e64732cfb1"),
        ("profile_physical_sha256", "abef7ace9ecc5799a0f09c060a3ee6371e45330b2d6dbac21a09c3b6f97598f8"),
        ("profile_semantic_sha256", "1ea4517532226a4d7026fd5e2061f32a2866e057a73e1064351ffb55ac33c992"),
        ("tests_sha256", "4237ec1aba9dfd89d0d63c1995c3c20aa557bed3f42e275bf1eeb20764763dff"),
    )
    if type(pins) is not dict or tuple(pins.items()) != expected_logical:
        fail("accepted logical-profile pins drifted")
    bridge = document["local_bridge"]
    if (
        type(bridge) is not dict
        or set(bridge) != {"byte_count", "claim", "path_from_repository_root", "sha256"}
        or bridge.get("byte_count") != 8146
        or bridge.get("sha256")
        != "2e0fb0a6d8190e4488810653a2638edeff9ceae2a1ea463f28730106752b183f"
        or bridge.get("claim") != "REPOSITORY_LOCAL_RECEIPT_BYTES_ONLY_NONORIGIN"
        or bridge.get("path_from_repository_root") != "scripts/us/bea71.toml"
    ):
        fail("local bea71 bridge pin drifted")
    records = document["object_profiles"]
    if type(records) is not list or len(records) != 6:
        fail("profile must contain exactly six object profiles")
    if tuple(record.get("profile_id") for record in records) != PROFILE_IDS:
        fail("six prospective profile identifiers drifted")
    if any(
        type(record) is not dict
        or set(record)
        != {
            "diagnostic_object_id",
            "physically_qualified",
            "profile_id",
            "qualification_blocker",
            "source_ids",
        }
        or record.get("physically_qualified") is not False
        or type(record.get("diagnostic_object_id")) is not str
        or not record["diagnostic_object_id"]
        or type(record.get("qualification_blocker")) is not str
        or not record["qualification_blocker"]
        or type(record.get("source_ids")) is not list
        or any(type(item) is not str for item in record["source_ids"])
        for record in records
    ):
        fail("an object profile falsely became physically qualified")
    expected_object_sources = (
        ["bea_summary_use_2024", "bea_summary_make_2024"],
        ["bea_industry_commodity_naics_concordance"],
        [],
        ["naics_2017_structure"],
        ["naics_2017_to_2022_concordance"],
        ["naics_2022_structure"],
    )
    if tuple(record["source_ids"] for record in records) != expected_object_sources:
        fail("six object-profile source projections drifted")
    sources = document["sources"]
    if type(sources) is not list or len(sources) != len(SOURCE_PINS):
        fail("profile source set drifted")
    expected_source_metadata = (
        {
            "body_filename_label": "IOUse_After_Redefinitions_PRO_Summary.xlsx",
            "expected_2024_dimension": "A1:CR90",
            "expected_2024_sheet_name": "2024",
        },
        {
            "body_filename_label": "IOMake_After_Redefinitions_PRO_Summary.xlsx",
            "expected_2024_dimension": "A1:BX84",
            "expected_2024_sheet_name": "2024",
        },
        {
            "local_audit_transport_filename": "bea.xlsx",
            "planned_official_filename": "BEA-Industry-and-Commodity-Codes-and-NAICS-Concordance.xlsx",
            "expected_dimension": "A1:N510",
            "expected_sheet_name": "NAICS Codes",
        },
        {
            "local_audit_transport_filename": "naics2017.xlsx",
            "planned_official_filename": "2017_NAICS_Structure.xlsx",
            "expected_dimension": "A1:F2218",
            "expected_sheet_name": "Sheet1",
        },
        {
            "local_audit_transport_filename": "conc.xlsx",
            "planned_official_filename": "2017_to_2022_NAICS.xlsx",
            "expected_dimension": "A1:I1153",
            "expected_sheet_name": "2017 to 2022 NAICS U.S.",
        },
        {
            "local_audit_transport_filename": "naics2022.xlsx",
            "planned_official_filename": "2022_NAICS_Structure.xlsx",
            "expected_dimension": "A1:F2147",
            "expected_sheet_name": "2022 NAICS Structure",
        },
    )
    for record, pin, expected_metadata in zip(
        sources, SOURCE_PINS, expected_source_metadata
    ):
        expected_source_keys = (
            {
                "body_filename_label",
                "byte_count",
                "expected_2024_dimension",
                "expected_2024_sheet_name",
                "parser_kind",
                "sha256",
                "source_id",
            }
            if pin.parser_kind in ("bea_summary_use_axis", "bea_summary_make_axis")
            else {
                "local_audit_transport_filename",
                "planned_official_filename",
                "byte_count",
                "expected_dimension",
                "expected_sheet_name",
                "parser_kind",
                "sha256",
                "source_id",
            }
        )
        if (
            type(record) is not dict
            or set(record) != expected_source_keys
            or record.get("source_id") != pin.source_id
            or record.get("parser_kind") != pin.parser_kind
            or record.get("sha256") != pin.sha256
            or record.get("byte_count") != pin.byte_count
            or any(record.get(key) != value for key, value in expected_metadata.items())
        ):
            fail("profile exact source pin drifted: " + pin.source_id)
    mismatch = document["mismatch_contract"]
    if (
        type(mismatch) is not dict
        or set(mismatch)
        != {
            "accepted_logical_special_order",
            "axis_projection_compatible",
            "bea_concordance_explicit_row_axis_available",
            "bea_concordance_projection_invented",
            "bea_summary_title_trailing_space_mismatches",
            "make_other_title",
            "make_used_title",
            "physical_commodity_count",
            "physical_industry_count",
            "physical_special_order",
            "special_accounts_are_naics",
            "successor_requirement",
            "use_other_title",
            "use_used_title",
        }
        or mismatch.get("physical_special_order") != ["Used", "Other"]
        or mismatch.get("accepted_logical_special_order") != ["Other", "Used"]
        or mismatch.get("successor_requirement")
        != "VERSIONED_LOGICAL_SUCCESSOR_REQUIRED"
        or mismatch.get("axis_projection_compatible") is not False
        or mismatch.get("bea_concordance_explicit_row_axis_available") is not False
        or mismatch.get("bea_concordance_projection_invented") is not False
        or mismatch.get("special_accounts_are_naics") is not False
        or mismatch.get("physical_industry_count") != 71
        or mismatch.get("physical_commodity_count") != 73
        or mismatch.get("use_used_title") != "Scrap, used and secondhand goods"
        or mismatch.get("use_other_title")
        != "Noncomparable imports and rest-of-the-world adjustment [1]"
        or mismatch.get("make_used_title")
        != "Scrap, used and secondhand goods /1/"
        or mismatch.get("make_other_title")
        != "Noncomparable imports and rest-of-the-world adjustment /2/"
        or mismatch.get("bea_summary_title_trailing_space_mismatches")
        != [
            {"code": "481", "trailing_space_count": 2},
            {"code": "482", "trailing_space_count": 1},
            {"code": "485", "trailing_space_count": 1},
        ]
    ):
        fail("physical/logical mismatch contract drifted")
    policy = document["ooxml_policy"]
    expected_policy_keys = {
        "absolute_canonical_single_link_paths_required",
        "bom_free_strict_utf8_xml_required",
        "case_unique_safe_zip_members_required",
        "central_local_zip_records_must_match",
        "content_type_driven_xml_preflight_required",
        "content_types_required",
        "crc_and_compression_metadata_required",
        "duplicate_xml_attributes_rejected_by_parser",
        "dtd_entity_and_nondeclaration_pi_forbidden",
        "error_cells_forbidden",
        "external_relationships_forbidden",
        "cell_formulas_forbidden",
        "defined_name_ref_errors_preserved_not_executed",
        "hard_links_forbidden",
        "local_header_contiguity_required",
        "raw_character_data_close_token_forbidden",
        "relationship_part_mime_exact",
        "relationship_target_mime_exact",
        "relationships_required",
        "source_verification_always_on",
        "strict_json_duplicate_type_and_nonfinite_rejection",
        "xml_1_0_scalar_validity_required",
        "zip64_multidisk_descriptor_prefix_suffix_and_gaps_forbidden",
    }
    if (
        type(policy) is not dict
        or set(policy) != expected_policy_keys
        or any(value is not True for value in policy.values())
    ):
        fail("OOXML fail-closed policy drifted")
    runtime = document["runtime_ceiling"]
    if (
        type(runtime) is not dict
        or set(runtime)
        != {
            "implementation",
            "minimum_python",
            "same_user_concurrent_rewrite_fully_excluded",
            "same_user_race_ceiling",
            "spreadsheet_runtime_corroboration",
        }
        or runtime.get("implementation") != "PYTHON_STDLIB_ONLY"
        or runtime.get("minimum_python") != "3.11"
        or runtime.get("same_user_concurrent_rewrite_fully_excluded") is not False
        or runtime.get("spreadsheet_runtime_corroboration")
        != "UNAVAILABLE_AFTER_TWO_BUNDLED_RUNTIME_DISCOVERY_ATTEMPTS"
    ):
        fail("runtime evidence ceiling drifted")


def _safe_member_name(raw_name: bytes, flags: int) -> str:
    if flags & 0x800:
        try:
            name = raw_name.decode("utf-8")
        except UnicodeDecodeError as error:
            raise ProfileError("ZIP member name is not strict UTF-8") from error
    else:
        try:
            name = raw_name.decode("ascii")
        except UnicodeDecodeError as error:
            raise ProfileError("ZIP member name must be unambiguous ASCII") from error
    pure = PurePosixPath(name)
    if (
        not name
        or name.endswith("/")
        or name.startswith("/")
        or "\\" in name
        or "\x00" in name
        or pure.is_absolute()
        or any(part in ("", ".", "..") for part in pure.parts)
        or posixpath.normpath(name) != name
    ):
        fail("ZIP member name is unsafe: " + repr(name))
    return name


def _raw_zip_directory(raw: bytes) -> tuple[list[dict[str, Any]], int]:
    if not raw.startswith(b"PK\x03\x04"):
        fail("workbook has a ZIP prefix or lacks its first local header")
    eocd_offset = raw.rfind(b"PK\x05\x06")
    if eocd_offset < 0 or eocd_offset + 22 > len(raw):
        fail("ZIP end-of-central-directory record is missing")
    (
        signature,
        disk_number,
        directory_disk,
        entries_disk,
        entries_total,
        directory_size,
        directory_offset,
        comment_length,
    ) = struct.unpack_from("<I4H2IH", raw, eocd_offset)
    if signature != 0x06054B50:
        fail("ZIP end-of-central-directory signature is malformed")
    if eocd_offset + 22 + comment_length != len(raw) or comment_length != 0:
        fail("ZIP archive has a comment or trailing suffix")
    if (
        disk_number != 0
        or directory_disk != 0
        or entries_disk != entries_total
        or entries_total in (0, 0xFFFF)
        or directory_size == 0xFFFFFFFF
        or directory_offset == 0xFFFFFFFF
    ):
        fail("ZIP64 or multi-disk ZIP is forbidden")
    if entries_total > MAX_ZIP_MEMBERS:
        fail("ZIP member count exceeds its closed bound")
    if directory_offset + directory_size != eocd_offset:
        fail("ZIP central directory has a gap or overlap")
    cursor = directory_offset
    records: list[dict[str, Any]] = []
    names: set[str] = set()
    folded: set[str] = set()
    for index in range(entries_total):
        if cursor + 46 > eocd_offset:
            fail("ZIP central-directory entry is truncated")
        values = struct.unpack_from("<I6H3I5H2I", raw, cursor)
        if values[0] != 0x02014B50:
            fail("ZIP central-directory entry signature is malformed")
        (
            _, made_by, needed, flags, method, mod_time, mod_date,
            crc, compressed_size, uncompressed_size, name_length,
            extra_length, member_comment_length, start_disk, internal_attr,
            external_attr, local_offset,
        ) = values
        record_end = cursor + 46 + name_length + extra_length + member_comment_length
        if record_end > eocd_offset:
            fail("ZIP central-directory variable data is truncated")
        raw_name = raw[cursor + 46 : cursor + 46 + name_length]
        name = _safe_member_name(raw_name, flags)
        if extra_length or member_comment_length:
            fail("ZIP member extras and comments are forbidden")
        if start_disk != 0 or needed >= 45:
            fail("ZIP64 or multi-disk member is forbidden")
        if flags & ~0x0806 or flags & (0x0001 | 0x0008):
            fail("ZIP member uses forbidden flags or a data descriptor")
        if method not in (0, 8):
            fail("ZIP member compression method is unsupported")
        create_system = made_by >> 8
        unix_mode = (external_attr >> 16) & 0xFFFF
        unix_file_type = stat.S_IFMT(unix_mode)
        if create_system == 3 and unix_file_type not in (0, stat.S_IFREG):
            fail("ZIP contains a non-regular Unix member")
        if name in names or name.casefold() in folded:
            fail("ZIP member names are not case-unique")
        names.add(name)
        folded.add(name.casefold())
        if uncompressed_size > MAX_MEMBER_BYTES:
            fail("ZIP member exceeds its uncompressed size bound")
        if compressed_size == 0:
            if uncompressed_size != 0:
                fail("ZIP member compression sizes are inconsistent")
        elif uncompressed_size / compressed_size > MAX_COMPRESSION_RATIO:
            fail("ZIP member exceeds its compression-ratio bound")
        records.append(
            {
                "index": index,
                "name": name,
                "raw_name": raw_name,
                "made_by": made_by,
                "extract_version": needed,
                "flags": flags,
                "compression_method": method,
                "mod_time": mod_time,
                "mod_date": mod_date,
                "crc32_int": crc,
                "compressed_bytes": compressed_size,
                "uncompressed_bytes": uncompressed_size,
                "internal_attr": internal_attr,
                "external_attr": external_attr,
                "local_header_offset": local_offset,
            }
        )
        cursor = record_end
    if cursor != eocd_offset:
        fail("ZIP central-directory byte count is inconsistent")
    next_local = 0
    total_uncompressed = 0
    for record in records:
        local_offset = record["local_header_offset"]
        if local_offset != next_local or local_offset + 30 > directory_offset:
            fail("ZIP local records have a prefix, gap, overlap, or reordering")
        values = struct.unpack_from("<I5H3I2H", raw, local_offset)
        if values[0] != 0x04034B50:
            fail("ZIP local header signature is malformed")
        (
            _, needed, flags, method, mod_time, mod_date, crc,
            compressed_size, uncompressed_size, name_length, extra_length,
        ) = values
        name_start = local_offset + 30
        raw_name = raw[name_start : name_start + name_length]
        data_start = name_start + name_length + extra_length
        data_end = data_start + compressed_size
        local_extra = raw[name_start + name_length : data_start]
        if local_extra:
            if len(local_extra) < 8:
                fail("ZIP local-header padding extra is truncated")
            field_id, field_size, padding_id, padding_size = struct.unpack_from(
                "<4H", local_extra, 0
            )
            if (
                field_id != 0xA220
                or field_size != len(local_extra) - 4
                or padding_id != 0xA028
                or padding_size != len(local_extra) - 8
                or any(local_extra[8:])
            ):
                fail("ZIP local-header extra is not exact zero alignment padding")
        if (
            needed != record["extract_version"]
            or flags != record["flags"]
            or method != record["compression_method"]
            or mod_time != record["mod_time"]
            or mod_date != record["mod_date"]
            or crc != record["crc32_int"]
            or compressed_size != record["compressed_bytes"]
            or uncompressed_size != record["uncompressed_bytes"]
            or raw_name != record["raw_name"]
        ):
            fail("ZIP central and local records disagree")
        if data_end > directory_offset:
            fail("ZIP compressed member data overlaps its directory")
        record["local_extra_bytes"] = len(local_extra)
        record["local_extra_sha256"] = sha256_bytes(local_extra)
        next_local = data_end
        total_uncompressed += uncompressed_size
        if total_uncompressed > MAX_TOTAL_UNCOMPRESSED_BYTES:
            fail("ZIP total uncompressed size exceeds its closed bound")
    if next_local != directory_offset:
        fail("ZIP local-data region has a suffix or gap")
    return records, directory_offset


def _safe_zip_payloads(raw: bytes) -> tuple[dict[str, bytes], tuple[dict[str, Any], ...]]:
    raw_records, directory_offset = _raw_zip_directory(raw)
    try:
        archive = zipfile.ZipFile(io.BytesIO(raw), "r")
    except (zipfile.BadZipFile, OSError) as error:
        raise ProfileError("workbook is not a readable ZIP archive") from error
    payloads: dict[str, bytes] = {}
    manifest: list[dict[str, Any]] = []
    with archive:
        if archive.comment != b"" or archive.start_dir != directory_offset:
            fail("ZIP directory/comment differs from the raw directory")
        infos = archive.infolist()
        if len(infos) != len(raw_records):
            fail("ZIP library and raw member counts disagree")
        try:
            bad_member = archive.testzip()
        except (zipfile.BadZipFile, RuntimeError, EOFError, zlib.error) as error:
            raise ProfileError("ZIP CRC/decompression verification failed") from error
        if bad_member is not None:
            fail("ZIP CRC verification failed")
        for raw_record, info in zip(raw_records, infos):
            if (
                info.filename != raw_record["name"]
                or info.header_offset != raw_record["local_header_offset"]
                or info.flag_bits != raw_record["flags"]
                or info.compress_type != raw_record["compression_method"]
                or info.CRC != raw_record["crc32_int"]
                or info.compress_size != raw_record["compressed_bytes"]
                or info.file_size != raw_record["uncompressed_bytes"]
                or info.create_system != raw_record["made_by"] >> 8
                or info.create_version != raw_record["made_by"] & 0xFF
                or info.extract_version != raw_record["extract_version"]
                or info.internal_attr != raw_record["internal_attr"]
                or info.external_attr != raw_record["external_attr"]
                or info.extra != b""
                or info.comment != b""
            ):
                fail("ZIP library metadata disagrees with raw records")
            try:
                payload = archive.read(info)
            except (zipfile.BadZipFile, RuntimeError, EOFError) as error:
                raise ProfileError("ZIP member could not be read safely") from error
            if len(payload) != info.file_size:
                fail("ZIP member decompressed size drifted")
            payloads[info.filename] = payload
            manifest.append(
                {
                    "index": raw_record["index"],
                    "name": info.filename,
                    "crc32": f"{info.CRC:08x}",
                    "compression_method": info.compress_type,
                    "flags": info.flag_bits,
                    "create_system": info.create_system,
                    "create_version": info.create_version,
                    "extract_version": info.extract_version,
                    "dos_mod_time": raw_record["mod_time"],
                    "dos_mod_date": raw_record["mod_date"],
                    "internal_attr": info.internal_attr,
                    "external_attr": info.external_attr,
                    "local_extra_bytes": raw_record["local_extra_bytes"],
                    "local_extra_sha256": raw_record["local_extra_sha256"],
                    "compressed_bytes": info.compress_size,
                    "uncompressed_bytes": info.file_size,
                    "payload_sha256": sha256_bytes(payload),
                }
            )
    return payloads, tuple(manifest)


def _is_xml_scalar(character: str) -> bool:
    codepoint = ord(character)
    return (
        codepoint in (0x9, 0xA, 0xD)
        or 0x20 <= codepoint <= 0xD7FF
        or 0xE000 <= codepoint <= 0xFFFD
        or 0x10000 <= codepoint <= 0x10FFFF
    )


def _xml_root(
    data: bytes,
    location: str,
    expected_tag: str | None = None,
) -> ET.Element:
    if data.startswith(
        (b"\xef\xbb\xbf", b"\xff\xfe", b"\xfe\xff", b"\x00\x00\xfe\xff", b"\xff\xfe\x00\x00")
    ):
        fail(location + " must be BOM-free UTF-8 XML")
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ProfileError(location + " must be strict UTF-8 XML") from error
    if len(text) > MAX_XML_CHARACTERS:
        fail(location + " exceeds the XML character bound")
    if any(not _is_xml_scalar(character) for character in text):
        fail(location + " contains an invalid XML 1.0 scalar")
    if "]]>" in text:
        fail(location + " contains a raw character-data close token")
    remainder = text
    if text.startswith("<?xml"):
        if len(text) == 5 or text[5] not in " \t\r\n":
            fail(location + " contains a malformed XML declaration")
        declaration_end = text.find("?>")
        if declaration_end < 0:
            fail(location + " contains an unterminated XML declaration")
        declaration = text[: declaration_end + 2].casefold()
        if (
            'encoding="utf-8"' not in declaration
            and "encoding='utf-8'" not in declaration
        ):
            fail(location + " XML declaration does not require UTF-8")
        remainder = text[declaration_end + 2 :]
    lowered = remainder.casefold()
    if "<!doctype" in lowered or "<!entity" in lowered:
        fail(location + " contains a forbidden DTD or entity declaration")
    if "<?" in remainder:
        fail(location + " contains a forbidden processing instruction")
    try:
        root = ET.fromstring(text)
    except ET.ParseError as error:
        raise ProfileError(location + " is not well-formed XML") from error
    if expected_tag is not None and root.tag != expected_tag:
        fail(location + " has an unexpected XML root")
    count = 0
    pending: list[tuple[ET.Element, int]] = [(root, 1)]
    while pending:
        element, depth = pending.pop()
        count += 1
        if count > MAX_XML_ELEMENTS or depth > MAX_XML_DEPTH:
            fail(location + " exceeds an XML topology bound")
        if len(element.attrib) > MAX_XML_ATTRIBUTES:
            fail(location + " element exceeds the XML attribute bound")
        scalar_values = [element.tag, element.text or "", element.tail or ""]
        scalar_values.extend(element.attrib.keys())
        scalar_values.extend(element.attrib.values())
        if any(
            any(not _is_xml_scalar(character) for character in value)
            for value in scalar_values
        ):
            fail(location + " contains an invalid decoded XML 1.0 scalar")
        pending.extend((child, depth + 1) for child in element)
    return root


def _content_types(
    payloads: Mapping[str, bytes],
) -> tuple[dict[str, str], tuple[dict[str, str], ...]]:
    data = payloads.get("[Content_Types].xml")
    if data is None:
        fail("OOXML package lacks [Content_Types].xml")
    root = _xml_root(data, "[Content_Types].xml", CONTENT_TYPES + "Types")
    if root.attrib:
        fail("content-types root has unsupported attributes")
    defaults: dict[str, str] = {}
    overrides: dict[str, str] = {}
    folded_overrides: set[str] = set()
    manifest: list[dict[str, str]] = []
    for child in root:
        if child.tag == CONTENT_TYPES + "Default":
            if set(child.attrib) != {"Extension", "ContentType"} or list(child):
                fail("content-type default is malformed")
            extension = child.get("Extension")
            content_type = child.get("ContentType")
            if not extension or not content_type or extension != extension.strip():
                fail("content-type default is incomplete")
            key = extension.casefold()
            if key in defaults:
                fail("content-type default extension is duplicated")
            expected_default_mime = {
                "rels": RELATIONSHIPS_CONTENT_TYPE,
                "xml": "application/xml",
                "bin": PRINTER_CONTENT_TYPE,
            }.get(key)
            if expected_default_mime is None or content_type != expected_default_mime:
                fail("content-type default is outside the closed OOXML set")
            defaults[key] = content_type
            manifest.append(
                {"kind": "default", "name": extension, "content_type": content_type}
            )
        elif child.tag == CONTENT_TYPES + "Override":
            if set(child.attrib) != {"PartName", "ContentType"} or list(child):
                fail("content-type override is malformed")
            part_name = child.get("PartName")
            content_type = child.get("ContentType")
            if (
                not part_name
                or not content_type
                or not part_name.startswith("/")
                or part_name != part_name.strip()
            ):
                fail("content-type override is incomplete")
            name = part_name[1:]
            if (
                not name
                or "\\" in name
                or any(part in ("", ".", "..") for part in PurePosixPath(name).parts)
                or posixpath.normpath(name) != name
                or name.casefold() in folded_overrides
            ):
                fail("content-type override has an unsafe or duplicate part")
            if content_type not in {
                WORKBOOK_CONTENT_TYPE,
                WORKSHEET_CONTENT_TYPE,
                THEME_CONTENT_TYPE,
                STYLES_CONTENT_TYPE,
                SHARED_STRINGS_CONTENT_TYPE,
                CORE_CONTENT_TYPE,
                APP_CONTENT_TYPE,
                CUSTOM_CONTENT_TYPE,
            }:
                fail("content-type override is outside the closed OOXML set")
            overrides[name] = content_type
            folded_overrides.add(name.casefold())
            manifest.append(
                {"kind": "override", "name": part_name, "content_type": content_type}
            )
        else:
            fail("content-types XML contains an unsupported child")
    resolved: dict[str, str] = {}
    for name in payloads:
        if name == "[Content_Types].xml":
            continue
        if name in overrides:
            resolved[name] = overrides[name]
            continue
        extension = (
            "rels"
            if name.endswith(".rels")
            else PurePosixPath(name).suffix[1:].casefold()
        )
        if not extension or extension not in defaults:
            fail("ZIP member lacks a resolvable content type: " + name)
        resolved[name] = defaults[extension]
    for name in overrides:
        if name not in payloads:
            fail("content-type override targets an absent part")
    if resolved.get("xl/workbook.xml") != WORKBOOK_CONTENT_TYPE:
        fail("xl/workbook.xml has the wrong content type")
    relationship_mime_parts = {
        name for name, content_type in resolved.items() if content_type == RELATIONSHIPS_CONTENT_TYPE
    }
    suffix_parts = {name for name in resolved if name.endswith(".rels")}
    if relationship_mime_parts != suffix_parts:
        fail("relationship parts and exact relationship MIME parts differ")
    if any("macroenabled" in value.casefold() for value in resolved.values()):
        fail("macro-enabled content type is forbidden")
    return resolved, tuple(manifest)


def _is_xml_content_type(content_type: str) -> bool:
    if content_type != content_type.strip() or ";" in content_type:
        return False
    lowered = content_type.casefold()
    return lowered in ("application/xml", "text/xml") or lowered.endswith("+xml")


def _preflight_xml_typed_parts(
    payloads: Mapping[str, bytes],
    content_types: Mapping[str, str],
) -> None:
    for name, content_type in content_types.items():
        if _is_xml_content_type(content_type):
            _xml_root(payloads[name], name)


def _relationship_source_part(part_name: str) -> str:
    if part_name == "_rels/.rels":
        return ""
    path = PurePosixPath(part_name)
    if len(path.parts) < 3 or path.parts[-2] != "_rels" or not path.name.endswith(".rels"):
        fail("relationship part has an invalid location")
    source = str(path.parent.parent / path.name[: -len(".rels")])
    if not source:
        fail("relationship part has an empty source")
    return source


def _resolve_relationship_target(source: str, target: str) -> str:
    parsed = urlsplit(target)
    if (
        parsed.scheme
        or parsed.netloc
        or parsed.query
        or parsed.fragment
        or not parsed.path
        or parsed.path.startswith("/")
        or "\\" in parsed.path
        or "%" in parsed.path
    ):
        fail("relationship target is unsafe")
    resolved = posixpath.normpath(posixpath.join(posixpath.dirname(source), parsed.path))
    if resolved in ("", ".", "..") or resolved.startswith("../"):
        fail("relationship target escapes the package")
    return resolved


def _relationships(
    payloads: Mapping[str, bytes],
    content_types: Mapping[str, str],
) -> tuple[dict[str, dict[str, tuple[str, str]]], tuple[dict[str, str], ...]]:
    parts = [
        name
        for name in payloads
        if content_types.get(name) == RELATIONSHIPS_CONTENT_TYPE
    ]
    if "_rels/.rels" not in parts:
        fail("OOXML package lacks its root relationships")
    by_source: dict[str, dict[str, tuple[str, str]]] = {}
    manifest: list[dict[str, str]] = []
    for part_name in parts:
        source = _relationship_source_part(part_name)
        if source in by_source:
            fail("OOXML source has duplicate relationship parts")
        if source and source not in payloads:
            fail("relationship part belongs to an absent source")
        root = _xml_root(payloads[part_name], part_name, PKG_REL + "Relationships")
        if root.attrib:
            fail("relationships root has unsupported attributes")
        records: dict[str, tuple[str, str]] = {}
        for relation in root:
            if relation.tag != PKG_REL + "Relationship" or list(relation):
                fail("relationship XML contains an unsupported child")
            allowed_attributes = {"Id", "Target", "Type", "TargetMode"}
            if not set(relation.attrib).issubset(allowed_attributes):
                fail("relationship contains an unsupported attribute")
            relation_id = relation.get("Id")
            target = relation.get("Target")
            relation_type = relation.get("Type")
            target_mode = relation.get("TargetMode", "Internal")
            if not relation_id or not target or not relation_type:
                fail("relationship is incomplete")
            if relation_id in records:
                fail("relationship Id is duplicated")
            if target_mode != "Internal":
                fail("external relationship is forbidden")
            if relation_type not in ALLOWED_RELATION_TYPES:
                fail("relationship type is outside the closed set")
            resolved = _resolve_relationship_target(source, target)
            if resolved not in payloads:
                fail("relationship targets an absent package part")
            expected_mime = next(
                mime for candidate, mime in RELATION_CONTENT_TYPE_RULES if candidate == relation_type
            )
            if content_types.get(resolved) != expected_mime:
                fail("relationship target MIME is not exact")
            records[relation_id] = (resolved, relation_type)
            manifest.append(
                {
                    "part": part_name,
                    "source": source,
                    "id": relation_id,
                    "raw_target": target,
                    "resolved_target": resolved,
                    "type": relation_type,
                    "target_mode": target_mode,
                }
            )
        by_source[source] = records
    office_targets = [
        target
        for target, relation_type in by_source.get("", {}).values()
        if relation_type == DOC_REL_NS + "/officeDocument"
    ]
    if office_targets != ["xl/workbook.xml"]:
        fail("root office-document relationship is not exact")
    reachable: set[str] = set()
    pending = [target for target, _ in by_source.get("", {}).values()]
    while pending:
        target = pending.pop()
        if target in reachable:
            continue
        reachable.add(target)
        pending.extend(child for child, _ in by_source.get(target, {}).values())
    substantive = set(payloads) - set(parts) - {"[Content_Types].xml"}
    if reachable != substantive:
        fail("package contains an unreachable or unbound substantive part")
    return by_source, tuple(manifest)


def _shared_strings(data: bytes) -> tuple[tuple[SharedString, ...], int, int, str]:
    root = _xml_root(data, "xl/sharedStrings.xml", MAIN + "sst")
    if not set(root.attrib).issubset({"count", "uniqueCount"}):
        fail("shared-strings root has unsupported attributes")
    values: list[SharedString] = []
    for child in root:
        if child.tag != MAIN + "si" or child.attrib:
            fail("shared-strings XML contains an unsupported item")
        if not list(child):
            fail("shared-string item is empty")
        for item in child:
            if item.tag == MAIN + "t":
                if (
                    list(item)
                    or not set(item.attrib).issubset(
                        {"{http://www.w3.org/XML/1998/namespace}space"}
                    )
                    or item.get(
                        "{http://www.w3.org/XML/1998/namespace}space", "preserve"
                    )
                    != "preserve"
                ):
                    fail("shared-string text node is malformed")
            elif item.tag == MAIN + "r":
                run_children = list(item)
                text_children = [node for node in run_children if node.tag == MAIN + "t"]
                if len(text_children) != 1 or any(
                    node.tag not in (MAIN + "rPr", MAIN + "t") for node in run_children
                ) or sum(node.tag == MAIN + "rPr" for node in run_children) > 1:
                    fail("shared-string rich run is malformed")
                if run_children[-1].tag != MAIN + "t":
                    fail("shared-string rich run text is not last")
                text_node = text_children[0]
                if (
                    list(text_node)
                    or not set(text_node.attrib).issubset(
                        {"{http://www.w3.org/XML/1998/namespace}space"}
                    )
                    or text_node.get(
                        "{http://www.w3.org/XML/1998/namespace}space", "preserve"
                    )
                    != "preserve"
                ):
                    fail("shared-string rich text node is malformed")
            else:
                fail("shared-string item contains unsupported structure")
        text_nodes = list(child.iter(MAIN + "t"))
        if not text_nodes:
            fail("shared-string item lacks text")
        text = "".join(node.text or "" for node in text_nodes)
        values.append(
            SharedString(
                index=len(values),
                text=text,
                run_count=sum(item.tag == MAIN + "r" for item in child),
                text_node_count=len(text_nodes),
            )
        )
    count_text = root.get("count")
    unique_text = root.get("uniqueCount")
    if (
        not _is_uint_text(count_text)
        or not _is_uint_text(unique_text)
        or int(unique_text) != len(values)
        or int(count_text) < len(values)
    ):
        fail("shared-strings counts are inconsistent")
    semantic = [
        {
            "index": item.index,
            "text": item.text,
            "run_count": item.run_count,
            "text_node_count": item.text_node_count,
        }
        for item in values
    ]
    return tuple(values), int(count_text), int(unique_text), sha256_bytes(canonical_json_bytes(semantic))


def _styles(data: bytes) -> tuple[int, str]:
    root = _xml_root(data, "xl/styles.xml", MAIN + "styleSheet")
    cell_formats = root.findall(MAIN + "cellXfs")
    if len(cell_formats) != 1:
        fail("styles XML must contain exactly one cellXfs")
    formats = cell_formats[0].findall(MAIN + "xf")
    count = cell_formats[0].get("count")
    if not formats or (count is not None and (not _is_uint_text(count) or int(count) != len(formats))):
        fail("styles cellXfs count is inconsistent")
    semantic = [
        {
            "attributes": dict(sorted(item.attrib.items())),
            "children": ET.tostring(item, encoding="unicode", short_empty_elements=True),
        }
        for item in formats
    ]
    return len(formats), sha256_bytes(canonical_json_bytes(semantic))


def excel_column_number(letters: str) -> int:
    if type(letters) is not str or not letters or not all("A" <= character <= "Z" for character in letters):
        fail("Excel column letters are malformed")
    number = 0
    for character in letters:
        number = number * 26 + ord(character) - ord("A") + 1
    return number


def excel_column_letters(number: int) -> str:
    if type(number) is not int or number < 1:
        fail("Excel column number must be an exact positive integer")
    result = ""
    while number:
        number, remainder = divmod(number - 1, 26)
        result = chr(ord("A") + remainder) + result
    return result


def split_cell_reference(reference: str) -> tuple[int, int]:
    if type(reference) is not str or not reference:
        fail("worksheet cell reference is malformed")
    split = 0
    while split < len(reference) and "A" <= reference[split] <= "Z":
        split += 1
    letters = reference[:split]
    row_text = reference[split:]
    if not letters or not _is_uint_text(row_text, positive=True):
        fail("worksheet cell reference is malformed: " + repr(reference))
    return excel_column_number(letters), int(row_text)


def _is_finite_decimal_lexeme(value: str) -> bool:
    if type(value) is not str or not value:
        return False
    index = 0
    if value[index] in "+-":
        index += 1
    digit_start = index
    while index < len(value) and "0" <= value[index] <= "9":
        index += 1
    before_digits = index - digit_start
    after_digits = 0
    if index < len(value) and value[index] == ".":
        index += 1
        fractional_start = index
        while index < len(value) and "0" <= value[index] <= "9":
            index += 1
        after_digits = index - fractional_start
    if before_digits + after_digits == 0:
        return False
    if index < len(value) and value[index] in "eE":
        index += 1
        if index < len(value) and value[index] in "+-":
            index += 1
        exponent_start = index
        while index < len(value) and "0" <= value[index] <= "9":
            index += 1
        if index == exponent_start:
            return False
    return index == len(value)


def _parse_dimension(dimension: str, location: str) -> tuple[int, int, int, int]:
    if dimension.count(":") == 1:
        start, end = dimension.split(":", 1)
    elif ":" not in dimension:
        start = end = dimension
    else:
        fail(location + " worksheet dimension is malformed")
    start_column, start_row = split_cell_reference(start)
    end_column, end_row = split_cell_reference(end)
    if start_column > end_column or start_row > end_row:
        fail(location + " worksheet dimension is reversed")
    if end_column > MAX_WORKSHEET_COLUMNS or end_row > MAX_WORKSHEET_ROWS:
        fail(location + " worksheet dimension exceeds a closed axis bound")
    return start_column, start_row, end_column, end_row


def _parse_sheet(
    name: str,
    sheet_id: int,
    relationship_id: str,
    part_name: str,
    state: str,
    data: bytes,
    shared_strings: Sequence[SharedString],
    style_count: int,
    *,
    retain_cells: bool,
) -> Sheet:
    root = _xml_root(data, part_name, MAIN + "worksheet")
    dimensions = root.findall(MAIN + "dimension")
    if len(dimensions) != 1 or set(dimensions[0].attrib) != {"ref"}:
        fail(name + " must contain exactly one worksheet dimension")
    dimension = dimensions[0].get("ref")
    if not dimension:
        fail(name + " worksheet dimension is missing")
    start_column, start_row, end_column, end_row = _parse_dimension(dimension, name)
    sheet_data_nodes = root.findall(MAIN + "sheetData")
    if len(sheet_data_nodes) != 1:
        fail(name + " must contain exactly one sheetData")
    retained: list[Cell] = []
    manifest_hash = hashlib.sha256()
    previous_row = 0
    row_count = 0
    cell_count = 0
    shared_count = 0
    shared_indexes: set[int] = set()
    for row_element in sheet_data_nodes[0]:
        if row_element.tag != MAIN + "row":
            fail(name + " sheetData contains an unsupported child")
        row_text = row_element.get("r")
        if not _is_uint_text(row_text, positive=True):
            fail(name + " row has a malformed index")
        row_number = int(row_text)
        if row_number <= previous_row:
            fail(name + " row order is not strictly increasing")
        previous_row = row_number
        row_count += 1
        previous_column = 0
        for cell_element in row_element:
            if cell_element.tag != MAIN + "c":
                fail(name + " row contains an unsupported child")
            if not set(cell_element.attrib).issubset({"r", "s", "t"}):
                fail(name + " cell has unsupported attributes")
            reference = cell_element.get("r")
            if reference is None:
                fail(name + " cell lacks a coordinate")
            column, referenced_row = split_cell_reference(reference)
            if referenced_row != row_number or column <= previous_column:
                fail(name + " cell order or coordinate is invalid")
            previous_column = column
            if not (start_row <= row_number <= end_row and start_column <= column <= end_column):
                fail(name + " contains a cell outside its dimension")
            formula_nodes = cell_element.findall(MAIN + "f")
            if formula_nodes:
                fail(name + " contains a forbidden cell formula")
            if cell_element.find(MAIN + "is") is not None:
                fail(name + " contains a forbidden inline string")
            if any(child.tag != MAIN + "v" for child in cell_element):
                fail(name + " cell contains an unsupported child")
            cell_type = cell_element.get("t", "n")
            if cell_type == "e":
                fail(name + " contains a forbidden error cell")
            if cell_type not in ("n", "s"):
                fail(name + " contains an unsupported cell type")
            style_text = cell_element.get("s", "0")
            if not _is_uint_text(style_text):
                fail(name + " contains a malformed style index")
            style = int(style_text)
            if style >= style_count:
                fail(name + " refers to an absent cell style")
            values = cell_element.findall(MAIN + "v")
            if len(values) > 1:
                fail(name + " cell contains duplicate value nodes")
            raw_value: str | None = None
            display: str | None = None
            if values:
                raw_value = values[0].text
                if raw_value is None:
                    fail(name + " cell contains an empty value node")
                if cell_type == "s":
                    if not _is_uint_text(raw_value):
                        fail(name + " shared-string index is malformed")
                    shared_index = int(raw_value)
                    if shared_index >= len(shared_strings):
                        fail(name + " shared-string index is out of range")
                    shared_count += 1
                    shared_indexes.add(shared_index)
                    display = shared_strings[shared_index].text
                else:
                    if not _is_finite_decimal_lexeme(raw_value):
                        fail(name + " numeric value is not a finite decimal lexeme")
                    display = raw_value
            elif cell_type == "s":
                fail(name + " shared-string cell lacks an index")
            cell = Cell(
                coordinate=reference,
                row=row_number,
                column=column,
                cell_type=cell_type,
                style=style,
                raw_value=raw_value,
                display=display,
            )
            record = {
                "coordinate": reference,
                "cell_type": cell_type,
                "style": style,
                "raw_value": raw_value,
                "display": display,
            }
            manifest_hash.update(canonical_json_bytes(record))
            if retain_cells:
                retained.append(cell)
            cell_count += 1
    return Sheet(
        name=name,
        sheet_id=sheet_id,
        relationship_id=relationship_id,
        part_name=part_name,
        state=state,
        dimension=dimension,
        row_element_count=row_count,
        cell_count=cell_count,
        cell_manifest_sha256=manifest_hash.hexdigest(),
        xml_sha256=sha256_bytes(data),
        shared_reference_count=shared_count,
        shared_indexes=frozenset(shared_indexes),
        cells=tuple(retained),
    )


def _defined_names(root: ET.Element) -> tuple[dict[str, Any], ...]:
    containers = root.findall(MAIN + "definedNames")
    if len(containers) > 1:
        fail("workbook contains duplicate definedNames containers")
    if not containers:
        return ()
    result: list[dict[str, Any]] = []
    for child in containers[0]:
        if child.tag != MAIN + "definedName" or list(child):
            fail("workbook defined-name structure is unsupported")
        result.append(
            {
                "attributes": dict(child.attrib.items()),
                "text": child.text or "",
            }
        )
    return tuple(result)


def parse_workbook_bytes(raw: bytes, parser_kind: str) -> Workbook:
    """Parse raw XLSX bytes under the closed physical parser policy."""

    if type(raw) is not bytes:
        fail("raw workbook must be exact bytes")
    if type(parser_kind) is not str:
        fail("parser kind must be exact text")
    payloads, members = _safe_zip_payloads(raw)
    required = {
        "[Content_Types].xml",
        "_rels/.rels",
        "xl/workbook.xml",
        "xl/_rels/workbook.xml.rels",
        "xl/sharedStrings.xml",
        "xl/styles.xml",
    }
    if not required.issubset(payloads):
        fail("OOXML workbook lacks a required package part")
    content_types, content_manifest = _content_types(payloads)
    _preflight_xml_typed_parts(payloads, content_types)
    relationships, relationship_manifest = _relationships(payloads, content_types)
    if content_types.get("xl/sharedStrings.xml") != SHARED_STRINGS_CONTENT_TYPE:
        fail("sharedStrings content type is not exact")
    if content_types.get("xl/styles.xml") != STYLES_CONTENT_TYPE:
        fail("styles content type is not exact")
    shared, shared_count, shared_unique, shared_hash = _shared_strings(
        payloads["xl/sharedStrings.xml"]
    )
    style_count, styles_hash = _styles(payloads["xl/styles.xml"])
    workbook_root = _xml_root(
        payloads["xl/workbook.xml"], "xl/workbook.xml", MAIN + "workbook"
    )
    sheet_containers = workbook_root.findall(MAIN + "sheets")
    if len(sheet_containers) != 1:
        fail("workbook must contain exactly one sheets container")
    sheet_records = sheet_containers[0].findall(MAIN + "sheet")
    if not sheet_records:
        fail("workbook contains no sheets")
    workbook_rels = relationships.get("xl/workbook.xml", {})
    names: set[str] = set()
    folded_names: set[str] = set()
    relation_ids: set[str] = set()
    sheet_ids: set[int] = set()
    targets: set[str] = set()
    sheets: list[Sheet] = []
    for record in sheet_records:
        allowed_attributes = {"name", "sheetId", DOC_REL + "id", "state"}
        if not set(record.attrib).issubset(allowed_attributes) or list(record):
            fail("workbook sheet record is malformed")
        name = record.get("name")
        sheet_id_text = record.get("sheetId")
        relation_id = record.get(DOC_REL + "id")
        state = record.get("state", "visible")
        if (
            not name
            or not relation_id
            or not _is_uint_text(sheet_id_text, positive=True)
            or state not in ("visible", "hidden", "veryHidden")
        ):
            fail("workbook sheet identity is incomplete")
        sheet_id = int(sheet_id_text)
        if (
            name in names
            or name.casefold() in folded_names
            or relation_id in relation_ids
            or sheet_id in sheet_ids
        ):
            fail("workbook sheet identity is duplicated")
        relation = workbook_rels.get(relation_id)
        if relation is None or relation[1] != DOC_REL_NS + "/worksheet":
            fail("workbook worksheet relationship is unresolved")
        target = relation[0]
        if content_types.get(target) != WORKSHEET_CONTENT_TYPE or target in targets:
            fail("workbook worksheet target is invalid or duplicated")
        retain = parser_kind not in ("bea_summary_use_axis", "bea_summary_make_axis") or name == "2024"
        sheet = _parse_sheet(
            name,
            sheet_id,
            relation_id,
            target,
            state,
            payloads[target],
            shared,
            style_count,
            retain_cells=retain,
        )
        names.add(name)
        folded_names.add(name.casefold())
        relation_ids.add(relation_id)
        sheet_ids.add(sheet_id)
        targets.add(target)
        sheets.append(sheet)
    worksheet_relation_ids = {
        relation_id
        for relation_id, (_, relation_type) in workbook_rels.items()
        if relation_type == DOC_REL_NS + "/worksheet"
    }
    if worksheet_relation_ids != relation_ids:
        fail("workbook has an unbound worksheet relationship")
    worksheet_parts = {
        name for name, content_type in content_types.items() if content_type == WORKSHEET_CONTENT_TYPE
    }
    if worksheet_parts != targets:
        fail("worksheet content-type parts differ from workbook topology")
    for relation_type, expected_target in (
        (DOC_REL_NS + "/sharedStrings", "xl/sharedStrings.xml"),
        (DOC_REL_NS + "/styles", "xl/styles.xml"),
    ):
        support_targets = [
            target
            for target, candidate_type in workbook_rels.values()
            if candidate_type == relation_type
        ]
        if support_targets != [expected_target]:
            fail("workbook support-part relationship is not exact")
    reference_count = sum(sheet.shared_reference_count for sheet in sheets)
    referenced_indexes = set().union(*(sheet.shared_indexes for sheet in sheets))
    if reference_count != shared_count:
        fail("shared-strings count differs from all worksheet references")
    if referenced_indexes != set(range(len(shared))):
        fail("shared-strings table contains an unreferenced item")
    return Workbook(
        raw_sha256=sha256_bytes(raw),
        raw_byte_count=len(raw),
        members=members,
        content_types=content_manifest,
        resolved_content_types=tuple(content_types.items()),
        relationships=relationship_manifest,
        shared_strings=shared,
        shared_count=shared_count,
        shared_unique_count=shared_unique,
        shared_semantic_sha256=shared_hash,
        style_count=style_count,
        styles_xml_sha256=sha256_bytes(payloads["xl/styles.xml"]),
        styles_semantic_sha256=styles_hash,
        defined_names=_defined_names(workbook_root),
        sheets=tuple(sheets),
    )


def parse_workbook(path: Path, parser_kind: str) -> Workbook:
    """Read and parse one absolute single-link workbook without a bypass."""

    raw, _ = _read_stable_regular_file(path, "external workbook")
    return parse_workbook_bytes(raw, parser_kind)


def _sheet(workbook: Workbook, name: str) -> Sheet:
    matches = [sheet for sheet in workbook.sheets if sheet.name == name]
    if len(matches) != 1:
        fail("workbook lacks exactly one expected sheet: " + name)
    return matches[0]


def _cell_map(sheet: Sheet) -> dict[tuple[int, int], Cell]:
    return {(cell.row, cell.column): cell for cell in sheet.cells}


def _required_cell(cells: Mapping[tuple[int, int], Cell], row: int, column: int, location: str) -> Cell:
    cell = cells.get((row, column))
    if cell is None:
        fail(location + " lacks an explicit required cell")
    return cell


def _cell_dict(cell: Cell) -> dict[str, Any]:
    return {
        "coordinate": cell.coordinate,
        "row": cell.row,
        "column": cell.column,
        "cell_type": cell.cell_type,
        "style": cell.style,
        "raw_value": cell.raw_value,
        "display": cell.display,
    }


def _pair_record(code: Cell, title: Cell) -> dict[str, Any]:
    if code.display is None or title.display is None:
        fail("classification axis pair contains an empty value")
    return {
        "code": code.display,
        "title": title.display,
        "code_cell": _cell_dict(code),
        "title_cell": _cell_dict(title),
    }


def _nul_field_rows_sha256(rows: Sequence[Sequence[str | None]]) -> str:
    digest = hashlib.sha256()
    for row in rows:
        encoded = "\0".join("" if field is None else field for field in row)
        digest.update(encoded.encode("utf-8") + b"\n")
    return digest.hexdigest()


def _ordered_zip_metadata_sha256(members: Sequence[Mapping[str, Any]]) -> str:
    digest = hashlib.sha256()
    for member in members:
        fields = (
            str(member["index"]),
            member["name"],
            member["crc32"],
            str(member["compression_method"]),
            str(member["compressed_bytes"]),
            str(member["uncompressed_bytes"]),
        )
        digest.update("\0".join(fields).encode("utf-8") + b"\n")
    return digest.hexdigest()


def _validate_exact_package_traits(workbook: Workbook, expected_metadata_hash: str) -> str:
    metadata_hash = _ordered_zip_metadata_sha256(workbook.members)
    if metadata_hash != expected_metadata_hash:
        fail("ordered ZIP metadata hash drifted")
    for member in workbook.members:
        if (
            member["compression_method"] != 8
            or member["flags"] != 6
            or member["dos_mod_time"] != 0
            or member["dos_mod_date"] != 33
            or member["create_system"] != 0
            or member["external_attr"] != 0
        ):
            fail("exact observed ZIP member traits drifted")
    return metadata_hash


def _summary_axis_diagnostic(
    use: Workbook,
    make: Workbook,
) -> tuple[dict[str, Any], dict[str, tuple[Cell, ...]]]:
    years = tuple(str(year) for year in range(1997, 2025))
    if tuple(sheet.name for sheet in use.sheets) != years or tuple(sheet.name for sheet in make.sheets) != years:
        fail("summary workbook year-sheet order drifted")
    if tuple(sheet.sheet_id for sheet in use.sheets) != tuple(range(2, 30)) or tuple(
        sheet.sheet_id for sheet in make.sheets
    ) != tuple(range(2, 30)):
        fail("summary workbook sheet IDs drifted")
    for workbook, dimension, cells, rows in (
        (use, "A1:CR90", 7776, 88),
        (make, "A1:BX84", 5629, 82),
    ):
        if any(
            sheet.dimension != dimension
            or sheet.cell_count != cells
            or sheet.row_element_count != rows
            or sheet.state != "visible"
            for sheet in workbook.sheets
        ):
            fail("summary workbook repeated physical sheet contract drifted")
    use_sheet = _sheet(use, "2024")
    make_sheet = _sheet(make, "2024")
    if (
        use.shared_strings[204].text != "..."
        or make.shared_strings[155].text != "..."
        or sum(
            cell.cell_type == "s" and cell.raw_value == "204"
            for cell in use_sheet.cells
        )
        != 2409
        or sum(
            cell.cell_type == "s" and cell.raw_value == "155"
            for cell in make_sheet.cells
        )
        != 4682
    ):
        fail("summary literal suppression-token preservation drifted")
    use_cells = _cell_map(use_sheet)
    make_cells = _cell_map(make_sheet)
    use_industry_cells: list[Cell] = []
    use_industry: list[dict[str, Any]] = []
    for column in range(3, 74):
        code = _required_cell(use_cells, 6, column, "use industry axis")
        title = _required_cell(use_cells, 7, column, "use industry axis")
        use_industry_cells.extend((code, title))
        use_industry.append(_pair_record(code, title))
    make_industry_cells: list[Cell] = []
    make_industry: list[dict[str, Any]] = []
    for row in range(8, 79):
        code = _required_cell(make_cells, row, 1, "make industry axis")
        title = _required_cell(make_cells, row, 2, "make industry axis")
        make_industry_cells.extend((code, title))
        make_industry.append(_pair_record(code, title))
    use_commodity_cells: list[Cell] = []
    use_commodity: list[dict[str, Any]] = []
    for row in range(8, 81):
        code = _required_cell(use_cells, row, 1, "use commodity axis")
        title = _required_cell(use_cells, row, 2, "use commodity axis")
        use_commodity_cells.extend((code, title))
        use_commodity.append(_pair_record(code, title))
    make_commodity_cells: list[Cell] = []
    make_commodity: list[dict[str, Any]] = []
    for column in range(3, 76):
        code = _required_cell(make_cells, 6, column, "make commodity axis")
        title = _required_cell(make_cells, 7, column, "make commodity axis")
        make_commodity_cells.extend((code, title))
        make_commodity.append(_pair_record(code, title))
    use_industry_pairs = [(item["code"], item["title"]) for item in use_industry]
    make_industry_pairs = [(item["code"], item["title"]) for item in make_industry]
    use_commodity_pairs = [(item["code"], item["title"]) for item in use_commodity]
    make_commodity_pairs = [(item["code"], item["title"]) for item in make_commodity]
    if use_industry_pairs != make_industry_pairs:
        fail("use/make industry axes are not exact shared projections")
    if use_commodity_pairs[:71] != make_commodity_pairs[:71]:
        fail("use/make ordinary commodity axes are not exact shared projections")
    if use_industry_pairs != use_commodity_pairs[:71]:
        fail("ordinary summary industry and commodity axes drifted")
    if use_commodity_pairs[-2:] != [
        ("Used", "Scrap, used and secondhand goods"),
        ("Other", "Noncomparable imports and rest-of-the-world adjustment [1]"),
    ]:
        fail("use summary special-account order or titles drifted")
    if make_commodity_pairs[-2:] != [
        ("Used", "Scrap, used and secondhand goods /1/"),
        ("Other", "Noncomparable imports and rest-of-the-world adjustment /2/"),
    ]:
        fail("make summary special-account order or titles drifted")
    all_axis_cells = (
        use_industry_cells
        + make_industry_cells
        + use_commodity_cells
        + make_commodity_cells
    )
    if any(cell.style != 0 for cell in all_axis_cells):
        fail("2024 summary axis style drifted")
    industry_hash = _nul_field_rows_sha256(use_industry_pairs)
    use_commodity_hash = _nul_field_rows_sha256(use_commodity_pairs)
    make_commodity_hash = _nul_field_rows_sha256(make_commodity_pairs)
    if (
        industry_hash != "6f53fca11a762278d5cfe0f7a9672ebaaffc2afc2751ec5577905984a4077c4d"
        or use_commodity_hash != "4f0805653ca3754fb90e0ebc30d9050198c7a7ed6abcf91a2bdf7c16ab16f5ca"
        or make_commodity_hash != "0c13177b9490ba62701c051cc42240f1791352f427fe7b07e6c004bdad33d6e9"
    ):
        fail("summary classification axis semantic hash drifted")
    diagnostic = {
        "industry_count": 71,
        "commodity_count": 73,
        "industry_pair_sha256": industry_hash,
        "use_commodity_pair_sha256": use_commodity_hash,
        "make_commodity_pair_sha256": make_commodity_hash,
        "industry_axes_exact": True,
        "ordinary_commodity_axes_exact": True,
        "use_industry_axis": use_industry,
        "make_industry_axis": make_industry,
        "use_commodity_axis": use_commodity,
        "make_commodity_axis": make_commodity,
        "physical_special_order": ["Used", "Other"],
        "accepted_logical_special_order": ["Other", "Used"],
        "logical_profile_compatible": False,
        "successor_requirement": "VERSIONED_LOGICAL_SUCCESSOR_REQUIRED",
        "special_accounts_are_naics": False,
        "literal_suppression_token": "...",
        "use_2024_suppression_reference_count": 2409,
        "make_2024_suppression_reference_count": 4682,
    }
    selected = {
        "bea_summary_use_2024": tuple(use_industry_cells + use_commodity_cells),
        "bea_summary_make_2024": tuple(make_industry_cells + make_commodity_cells),
    }
    return diagnostic, selected


def _bea_concordance_diagnostic(workbook: Workbook) -> tuple[dict[str, Any], tuple[Cell, ...]]:
    if (
        len(workbook.sheets) != 1
        or workbook.sheets[0].name != "NAICS Codes"
        or workbook.sheets[0].dimension != "A1:N510"
        or workbook.sheets[0].cell_count != 7102
        or workbook.sheets[0].row_element_count != 510
    ):
        fail("BEA concordance sheet topology drifted")
    if (
        workbook.shared_count != 4965
        or workbook.shared_unique_count != 1153
        or workbook.style_count != 41
        or workbook.styles_xml_sha256
        != "7d6bdfc646dd6a211a61fa9e402c2a0d2e5a9c0f3f67e5797681c4a1cac62082"
        or workbook.shared_strings[-1].index != 1152
        or workbook.shared_strings[-1].text != ""
    ):
        fail("BEA concordance shared-string/style contract drifted")
    sheet = workbook.sheets[0]
    cells = _cell_map(sheet)
    header = [
        _required_cell(cells, 5, column, "BEA concordance header").display
        for column in range(1, 14)
    ]
    expected_header = [
        "Sector",
        "Description",
        "Summary",
        "Description",
        "U. Summary",
        "Description",
        "Detail",
        "Description",
        "GO Detail",
        "Description",
        "Notes",
        "Related 2017 NAICS Codes",
        "Description",
    ]
    if header != expected_header:
        fail("BEA concordance five-level hierarchy header drifted")
    phantom = [
        _required_cell(cells, row, 14, "BEA phantom column N")
        for row in range(5, 505)
    ]
    if any(
        cell.cell_type != "s"
        or cell.style != 8
        or cell.raw_value != "1152"
        or cell.display != ""
        for cell in phantom
    ):
        fail("BEA phantom N5:N504 shared-string artifact drifted")
    final_index_references = [
        cell for cell in sheet.cells if cell.cell_type == "s" and cell.raw_value == "1152"
    ]
    k_references = [cell for cell in final_index_references if cell.column == 11]
    if len(final_index_references) != 979 or len(k_references) != 479:
        fail("BEA final empty shared-string reference counts drifted")
    row_values: list[list[str | None]] = []
    row_records: list[dict[str, Any]] = []
    for row in range(6, 505):
        row_cells = [
            _required_cell(cells, row, column, "BEA concordance data row")
            for column in range(1, 14)
        ]
        row_values.append([cell.display for cell in row_cells])
        row_records.append({"row": row, "cells": [_cell_dict(cell) for cell in row_cells]})
    row_hash = _nul_field_rows_sha256(row_values)
    if row_hash != "835c54607e77aa0ce3d4629fae2e201335f1707c34d0278363d778085f5b479b":
        fail("BEA A:M row tuple hash drifted")
    hierarchy_counts: list[int] = []
    for column in (1, 3, 5, 7, 9):
        ordered: list[str] = []
        seen: set[str] = set()
        for row in range(6, 505):
            value = _required_cell(cells, row, column, "BEA hierarchy").display
            if value is None:
                fail("BEA hierarchy cell unexpectedly lacks a value")
            if value not in seen:
                seen.add(value)
                ordered.append(value)
        hierarchy_counts.append(len(ordered))
    if hierarchy_counts != [23, 73, 141, 406, 418]:
        fail("BEA hierarchy cardinalities drifted")
    special_expectations = (
        (501, "Used", "S004 ", "S00401", "Scrap"),
        (502, "Used", "S004 ", "S00402", "Used and secondhand goods"),
        (503, "Other", "S003 ", "S00300", "Noncomparable imports"),
        (504, "Other", "S009 ", "S00900", "Rest of the world adjustment"),
    )
    for row, summary, underlying, detail, detail_title in special_expectations:
        observed = (
            _required_cell(cells, row, 3, "BEA special row").display,
            _required_cell(cells, row, 5, "BEA special row").display,
            _required_cell(cells, row, 7, "BEA special row").display,
            _required_cell(cells, row, 8, "BEA special row").display,
        )
        if observed != (summary, underlying, detail, detail_title):
            fail("BEA special-account row drifted")
    title_space_mismatches = [
        {
            "code": code,
            "bea_title": next(values[3] for values in row_values if values[2] == code),
            "trailing_space_count": count,
        }
        for code, count in (("481", 2), ("482", 1), ("485", 1))
    ]
    if any(
        type(item["bea_title"]) is not str
        or len(item["bea_title"]) - len(item["bea_title"].rstrip(" "))
        != item["trailing_space_count"]
        for item in title_space_mismatches
    ):
        fail("BEA trailing-space title mismatches drifted")
    diagnostic = {
        "data_row_count": 499,
        "data_row_range": "6:504",
        "hierarchy_columns": ["Sector", "Summary", "U. Summary", "Detail", "GO Detail"],
        "hierarchy_unique_counts": hierarchy_counts,
        "row_tuple_a_m_sha256": row_hash,
        "rows": row_records,
        "phantom_column": {
            "range": "N5:N504",
            "explicit_cell_count": 500,
            "shared_string_index": 1152,
            "decoded_value": "",
            "artifact_tool_misrendered_as_index": True,
        },
        "final_empty_shared_string_total_references": 979,
        "final_empty_shared_string_column_k_references": 479,
        "special_row_order": ["Used", "Used", "Other", "Other"],
        "special_accounts_are_naics": False,
        "explicit_industry_vs_commodity_row_axis_available": False,
        "axis_projection_invented": False,
        "ordinary_title_trailing_space_mismatches": title_space_mismatches,
    }
    return diagnostic, sheet.cells


def _naics_structure_diagnostic(
    workbook: Workbook,
    year: int,
) -> tuple[dict[str, Any], tuple[Cell, ...]]:
    if year == 2017:
        expected_name = "Sheet1"
        expected_dimension = "A1:F2218"
        expected_cells = 6660
        expected_last_row = 2218
        expected_rows = 2196
        expected_hash = "8a05871f270ceb80831232ccd6d263e218d2f6af9a9cf0a647fef7819dcda1a6"
        expected_style_count = 38
        expected_style_hash = "1c5c3165d62bbb205eaaab9c847c423269597a7a4542c7546c7624599333eab6"
        expected_shared = (2238, 1965)
        expected_separators = (
            135, 184, 210, 284, 933, 1099, 1263, 1404, 1479, 1569,
            1623, 1719, 1727, 1815, 1854, 1947, 2009, 2044, 2143,
        )
        expected_extra_coordinates = (
            "E5", "F5", "D129", "D979", "E979", "E980",
        )
        expected_range_rows = (285, 1100, 1264)
        expected_range_styles = (11, 14, 14)
        exceptional_separator_row = 1569
        ordinary_separator_styles = (17, 2, 2)
        exceptional_separator_styles = (17, 2, 21)
        if tuple(sheet.name for sheet in workbook.sheets) != ("Sheet1", "Sheet2", "Sheet3"):
            fail("2017 NAICS workbook sheet topology drifted")
        if any(
            sheet.dimension != "A1" or sheet.cell_count != 0 or sheet.state != "visible"
            for sheet in workbook.sheets[1:]
        ):
            fail("2017 NAICS empty visible sheets drifted")
    elif year == 2022:
        expected_name = "2022 NAICS Structure"
        expected_dimension = "A1:F2147"
        expected_cells = 6470
        expected_last_row = 2147
        expected_rows = 2125
        expected_hash = "7480e712cc34b40b5688c972b8ff7931fbfaa00ddd626d3f899bdaa9f1f571ae"
        expected_style_count = 41
        expected_style_hash = "f884511ac0c5505655b0e5807929129ea433654c3a78cc67a00a0f63d31fe648"
        expected_shared = (2362, 1910)
        expected_separators = (
            135, 177, 203, 277, 908, 1070, 1210, 1351, 1423, 1503,
            1557, 1653, 1661, 1749, 1788, 1881, 1943, 1978, 2072,
        )
        expected_extra_coordinates = (
            "D2", "E5", "F5", "D129", "D400", "D504", "D786", "D910",
            "D953", "D954", "E954", "D955", "E955", "D1066", "D1067",
            "D1071", "D1072", "D1093", "D1094", "D1105", "D1106",
            "D1107", "D1112", "D1113", "D1118", "D1119", "D1120",
            "D1399", "D1417",
        )
        expected_range_rows = (278, 1071, 1211)
        expected_range_styles = (14, 11, 11)
        exceptional_separator_row = 1503
        ordinary_separator_styles = (14, 2, 2)
        exceptional_separator_styles = (14, 2, 18)
        if len(workbook.sheets) != 1:
            fail("2022 NAICS workbook sheet topology drifted")
    else:
        fail("unsupported NAICS structure year")
    sheet = _sheet(workbook, expected_name)
    if (
        sheet.dimension != expected_dimension
        or sheet.cell_count != expected_cells
        or workbook.style_count != expected_style_count
        or workbook.styles_xml_sha256 != expected_style_hash
        or (workbook.shared_count, workbook.shared_unique_count) != expected_shared
    ):
        fail(str(year) + " NAICS physical contract drifted")
    cells = _cell_map(sheet)
    semantic_rows: list[list[str | None]] = []
    records: list[dict[str, Any]] = []
    separators: list[dict[str, Any]] = []
    for row in range(4, expected_last_row + 1):
        triple = [
            _required_cell(cells, row, column, str(year) + " NAICS row")
            for column in range(1, 4)
        ]
        if all(cell.display is None for cell in triple):
            separators.append({"row": row, "cells": [_cell_dict(cell) for cell in triple]})
        else:
            if triple[1].display is None or triple[2].display is None:
                fail(str(year) + " NAICS code/title row is partially empty")
            if triple[1].display in ("Other", "Used"):
                fail("BEA special accounts may not be treated as NAICS")
            semantic_rows.append([cell.display for cell in triple])
            records.append({"row": row, "cells": [_cell_dict(cell) for cell in triple]})
    semantic_hash = _nul_field_rows_sha256(semantic_rows)
    if (
        len(records) != expected_rows
        or tuple(item["row"] for item in separators) != expected_separators
        or semantic_hash != expected_hash
    ):
        fail(str(year) + " NAICS rows/separators/order/hash drifted")
    if any(
        tuple(cell["style"] for cell in item["cells"])
        != (
            exceptional_separator_styles
            if item["row"] == exceptional_separator_row
            else ordinary_separator_styles
        )
        for item in separators
    ):
        fail(str(year) + " NAICS separator styles drifted")
    extra_coordinates = tuple(
        cell.coordinate for cell in sheet.cells if cell.column > 3
    )
    if extra_coordinates != expected_extra_coordinates:
        fail(str(year) + " NAICS extra physical cells drifted")
    expected_range_codes = ("31-33", "44-45", "48-49")
    for row, code in zip(expected_range_rows, expected_range_codes):
        triple = tuple(
            _required_cell(cells, row, column, str(year) + " NAICS range row")
            for column in range(1, 4)
        )
        if (
            triple[1].display != code
            or tuple(cell.style for cell in triple) != expected_range_styles
        ):
            fail(str(year) + " NAICS range-code preservation drifted")
    return (
        {
            "year": year,
            "semantic_row_count": len(records),
            "separator_row_count": len(separators),
            "separator_rows": separators,
            "semantic_tuple_sha256": semantic_hash,
            "records": records,
            "range_codes_preserved_as_text": True,
            "other_or_used_treated_as_naics": False,
        },
        sheet.cells,
    )


def _naics_concordance_diagnostic(workbook: Workbook) -> tuple[dict[str, Any], tuple[Cell, ...]]:
    if (
        len(workbook.sheets) != 1
        or workbook.sheets[0].name != "2017 to 2022 NAICS U.S."
        or workbook.sheets[0].dimension != "A1:I1153"
        or workbook.sheets[0].cell_count != 4639
        or workbook.shared_count != 2325
        or workbook.shared_unique_count != 1164
        or workbook.style_count != 17
        or workbook.styles_xml_sha256
        != "c12b7b506aeb7ef8bda2a7b9c2ea4cf3114522e6873811776fcf3d0dc0ac373f"
    ):
        fail("NAICS concordance physical contract drifted")
    sheet = workbook.sheets[0]
    cells = _cell_map(sheet)
    rows: list[list[str | None]] = []
    records: list[dict[str, Any]] = []
    pairs: list[tuple[str, str]] = []
    for row in range(4, 1154):
        row_cells = [
            _required_cell(cells, row, column, "NAICS concordance row")
            for column in range(1, 5)
        ]
        if any(cell.display is None for cell in row_cells):
            fail("NAICS concordance row is partially empty")
        fields = [cell.display for cell in row_cells]
        rows.append(fields)
        source = fields[0]
        target = fields[2]
        if source in ("Other", "Used") or target in ("Other", "Used"):
            fail("BEA special accounts may not be treated as NAICS")
        pairs.append((source or "", target or ""))
        records.append({"row": row, "cells": [_cell_dict(cell) for cell in row_cells]})
    if len(set(pairs)) != 1150:
        fail("NAICS concordance contains duplicate source-target pairs")
    source_targets: dict[str, set[str]] = {}
    target_sources: dict[str, set[str]] = {}
    for source, target in pairs:
        source_targets.setdefault(source, set()).add(target)
        target_sources.setdefault(target, set()).add(source)
    classes = {
        "one_to_one": 0,
        "one_to_many": 0,
        "many_to_one": 0,
        "many_to_many": 0,
    }
    for source, target in pairs:
        out_degree = len(source_targets[source])
        in_degree = len(target_sources[target])
        if out_degree == 1 and in_degree == 1:
            classes["one_to_one"] += 1
        elif out_degree > 1 and in_degree == 1:
            classes["one_to_many"] += 1
        elif out_degree == 1 and in_degree > 1:
            classes["many_to_one"] += 1
        else:
            classes["many_to_many"] += 1
    if classes != {
        "one_to_one": 928,
        "one_to_many": 5,
        "many_to_one": 120,
        "many_to_many": 97,
    }:
        fail("NAICS concordance cardinality classes drifted")
    row_hash = _nul_field_rows_sha256(rows)
    pair_hash = _nul_field_rows_sha256(pairs)
    if (
        row_hash != "35c13e6623b8eb6ff56039191a24995fb3cc1c6f6a80f50e8e81f52df48eb9b1"
        or pair_hash != "84922efc6ded3cd0c526b56f37b63430a372046678c9d99c43999ff75c2b9040"
        or len(source_targets) != 1057
        or len(target_sources) != 1012
    ):
        fail("NAICS concordance row/pair graph hash drifted")
    extras = [cell for cell in sheet.cells if cell.column >= 5]
    space_cells = [cell for cell in extras if cell.display is not None]
    blank_cells = [cell for cell in extras if cell.display is None]
    expected_space_coordinates = (
        "E36", "F55", "E69", "F76", "I238", "F390", "E392", "E399",
        "F434", "E624", "H625", "F680", "E682", "G793", "E795", "E801",
        "E879", "E916", "E917",
    )
    expected_blank_coordinates = (
        "F111", "F112", "F113", "F1021", "F1022", "F1023", "F1024", "F1025",
    )
    if (
        tuple(cell.coordinate for cell in space_cells) != expected_space_coordinates
        or tuple(cell.coordinate for cell in blank_cells) != expected_blank_coordinates
        or any(cell.display != ("  " if cell.coordinate == "I238" else " ") for cell in space_cells)
        or sum(cell.style == 2 for cell in space_cells) != 12
        or sum(cell.style == 7 for cell in space_cells) != 7
        or any(cell.style not in (2, 7) for cell in space_cells)
        or any(
            cell.style
            != (9 if cell.coordinate in ("F1023", "F1024") else 8)
            for cell in blank_cells
        )
    ):
        fail("NAICS concordance stray spaces or styled blanks drifted")
    return (
        {
            "direction": "NAICS_2017_TO_NAICS_2022",
            "reverse_concordance_in_place": False,
            "row_count": 1150,
            "unique_pair_count": 1150,
            "source_code_count": 1057,
            "target_code_count": 1012,
            "cardinality_row_counts": classes,
            "four_field_tuple_sha256": row_hash,
            "source_target_pair_sha256": pair_hash,
            "records": records,
            "space_valued_cells": [_cell_dict(cell) for cell in space_cells],
            "styled_blank_cells": [_cell_dict(cell) for cell in blank_cells],
            "other_or_used_treated_as_naics": False,
        },
        sheet.cells,
    )


def _verify_repository_bindings(profile: Mapping[str, Any]) -> dict[str, Any]:
    repository_root = MODULE_PATH.parents[6]
    logical_dir = (
        repository_root
        / "scripts/us/forecasting/vintages/classification_maps/profile_v1"
    )
    expected = (
        (
            "logical_module",
            logical_dir / "USClassificationMapsProfileV1.jl",
            "f5890e959dc80c8fdda1507d73dba3658d4fa5720daaa3adc7cfb8e64732cfb1",
        ),
        (
            "logical_profile",
            logical_dir / "classification_maps_profile_v1.toml",
            "abef7ace9ecc5799a0f09c060a3ee6371e45330b2d6dbac21a09c3b6f97598f8",
        ),
        (
            "logical_tests",
            logical_dir / "test_classification_maps_profile_v1.jl",
            "4237ec1aba9dfd89d0d63c1995c3c20aa557bed3f42e275bf1eeb20764763dff",
        ),
        (
            "local_bea71_bridge",
            repository_root / "scripts/us/bea71.toml",
            "2e0fb0a6d8190e4488810653a2638edeff9ceae2a1ea463f28730106752b183f",
        ),
    )
    records: list[dict[str, Any]] = []
    logical_profile_bytes: bytes | None = None
    for binding_id, path, expected_hash in expected:
        data, _ = _read_stable_regular_file(path, binding_id, max_bytes=2 * 1024 * 1024)
        physical_hash = sha256_bytes(data)
        if physical_hash != expected_hash:
            fail(binding_id + " physical SHA-256 drifted")
        if binding_id == "local_bea71_bridge" and len(data) != 8146:
            fail("local bea71 bridge byte count drifted")
        if binding_id == "logical_profile":
            logical_profile_bytes = data
        records.append(
            {
                "binding_id": binding_id,
                "physical_sha256": physical_hash,
                "byte_count": len(data),
                "fixity_verified": True,
                "provider_origin_verified": False,
            }
        )
    if logical_profile_bytes is None:
        fail("logical profile bytes were not verified")
    try:
        logical_profile = tomllib.loads(logical_profile_bytes.decode("utf-8"))
    except (UnicodeDecodeError, tomllib.TOMLDecodeError) as error:
        raise ProfileError("accepted logical profile is not strict TOML") from error
    semantic_hash = logical_profile.get("artifact", {}).get("content_sha256")
    if semantic_hash != "1ea4517532226a4d7026fd5e2061f32a2866e057a73e1064351ffb55ac33c992":
        fail("accepted logical profile semantic hash field drifted")
    if profile["logical_profile_pins"]["profile_semantic_sha256"] != semantic_hash:
        fail("physical profile logical semantic binding drifted")
    return {
        "records": records,
        "logical_profile_semantic_sha256": semantic_hash,
        "local_bridge_claim": "REPOSITORY_LOCAL_RECEIPT_BYTES_ONLY_NONORIGIN",
    }


def _workbook_record(
    pin: SourcePin,
    workbook: Workbook,
    metadata_hash: str,
    selected_cells: Sequence[Cell],
    diagnostic: Mapping[str, Any],
) -> dict[str, Any]:
    sheets = [
        {
            "name": sheet.name,
            "sheet_id": sheet.sheet_id,
            "relationship_id": sheet.relationship_id,
            "part_name": sheet.part_name,
            "state": sheet.state,
            "dimension": sheet.dimension,
            "row_element_count": sheet.row_element_count,
            "explicit_cell_count": sheet.cell_count,
            "cell_manifest_sha256": sheet.cell_manifest_sha256,
            "xml_sha256": sheet.xml_sha256,
        }
        for sheet in workbook.sheets
    ]
    return {
        "source_id": pin.source_id,
        "parser_kind": pin.parser_kind,
        "body_sha256": workbook.raw_sha256,
        "body_byte_count": workbook.raw_byte_count,
        "body_hash_size_verified": True,
        "body_to_url_provenance_verified": False,
        "body_to_provider_provenance_verified": False,
        "transport_authenticated": False,
        "claim": "EXACT_LOCAL_SERVER_BODY_BYTES_ONLY_NO_URL_OR_PROVIDER_PROVENANCE",
        "ordered_zip_metadata_sha256": metadata_hash,
        "zip_members": [dict(member) for member in workbook.members],
        "content_types_in_document_order": [dict(item) for item in workbook.content_types],
        "resolved_content_types_in_member_order": [
            {"part_name": name, "content_type": content_type}
            for name, content_type in workbook.resolved_content_types
        ],
        "relationships_in_part_and_element_order": [
            dict(item) for item in workbook.relationships
        ],
        "shared_strings": {
            "count": workbook.shared_count,
            "unique_count": workbook.shared_unique_count,
            "semantic_sha256": workbook.shared_semantic_sha256,
            "items": [
                {
                    "index": item.index,
                    "text": item.text,
                    "run_count": item.run_count,
                    "text_node_count": item.text_node_count,
                }
                for item in workbook.shared_strings
            ],
        },
        "styles": {
            "cell_xf_count": workbook.style_count,
            "xml_sha256": workbook.styles_xml_sha256,
            "semantic_sha256": workbook.styles_semantic_sha256,
        },
        "defined_names": [dict(item) for item in workbook.defined_names],
        "sheets_in_workbook_order": sheets,
        "classification_cells_in_source_order": [
            _cell_dict(cell) for cell in selected_cells
        ],
        "diagnostic": parse_json_bytes(
            canonical_json_bytes(diagnostic), "detached source diagnostic"
        ),
        "zero_cell_formulas_verified": True,
        "zero_error_cells_verified": True,
        "defined_name_ref_errors_preserved_not_executed": True,
    }


def _result_semantic_sha256(document: Mapping[str, Any]) -> str:
    copied = parse_json_bytes(canonical_json_bytes(document), "derivative copy")
    artifact = copied.get("artifact")
    if type(artifact) is not dict or "content_sha256" not in artifact:
        fail("derivative content hash field is missing")
    del artifact["content_sha256"]
    return sha256_bytes(canonical_json_bytes(copied))


def compile_derivative(source_paths: Mapping[str, Path]) -> dict[str, Any]:
    """Compile the deterministic diagnostic after mandatory exact-source checks."""

    if type(source_paths) is not dict or set(source_paths) != set(SOURCE_IDS):
        fail("source_paths must be an exact dict containing the six source IDs")
    profile_bytes, profile = _load_profile_bytes()
    repository_bindings = _verify_repository_bindings(profile)
    module_bytes, module_identity = _read_stable_regular_file(
        MODULE_PATH, "generator module", max_bytes=4 * 1024 * 1024
    )
    identities: set[tuple[int, int]] = {module_identity}
    workbooks: dict[str, Workbook] = {}
    for pin in SOURCE_PINS:
        path = source_paths[pin.source_id]
        raw, identity = _read_stable_regular_file(path, pin.source_id)
        if identity in identities:
            fail("source files and generator module must have distinct identities")
        identities.add(identity)
        if len(raw) != pin.byte_count or sha256_bytes(raw) != pin.sha256:
            fail(pin.source_id + " exact source size or SHA-256 drifted")
        workbook = parse_workbook_bytes(raw, pin.parser_kind)
        if workbook.raw_sha256 != pin.sha256 or workbook.raw_byte_count != pin.byte_count:
            fail(pin.source_id + " parser body identity drifted")
        workbooks[pin.source_id] = workbook
    expected_package_hashes = (
        ("bea_summary_use_2024", "5e2a70c6b7488f11ba6316e0ea52e7b6e5c4a95e2ea7f11e19468a86b078ebee"),
        ("bea_summary_make_2024", "666970b263077a1d31027b41593391ac9762fa11b26f1fb8f6a8e9410a1662e8"),
        ("bea_industry_commodity_naics_concordance", "1e4141c35285b1d89a912811813dfd9eae92401d18901c25e13f274b9078f95d"),
        ("naics_2017_structure", "8145fc670df72b728720b92b2755b2a39906172497c65a0395014c569865c0cb"),
        ("naics_2017_to_2022_concordance", "f850f8850f4361fe3908f4d219fce50f17ea5b6b87aee9d7b07e6f53bedae20f"),
        ("naics_2022_structure", "cea797988f012fe2fe7e5dc77a725cf3d34299ab12c184119c04f8c413ff7f82"),
    )
    package_hashes = {
        source_id: _validate_exact_package_traits(workbooks[source_id], expected_hash)
        for source_id, expected_hash in expected_package_hashes
    }
    use = workbooks["bea_summary_use_2024"]
    make = workbooks["bea_summary_make_2024"]
    if (
        (use.shared_count, use.shared_unique_count, use.style_count)
        != (78441, 235, 2)
        or (make.shared_count, make.shared_unique_count, make.style_count)
        != (140211, 187, 2)
        or use.styles_xml_sha256
        != "3a4d9de77e1dc446f777e9de6dad575533dd2f774aaa1be85239d6b81c838aa2"
        or make.styles_xml_sha256 != use.styles_xml_sha256
    ):
        fail("summary workbook shared-string/style contract drifted")
    summary_diagnostic, summary_cells = _summary_axis_diagnostic(use, make)
    bea_diagnostic, bea_cells = _bea_concordance_diagnostic(
        workbooks["bea_industry_commodity_naics_concordance"]
    )
    naics_2017_diagnostic, naics_2017_cells = _naics_structure_diagnostic(
        workbooks["naics_2017_structure"], 2017
    )
    naics_concordance_diagnostic, naics_concordance_cells = (
        _naics_concordance_diagnostic(
            workbooks["naics_2017_to_2022_concordance"]
        )
    )
    naics_2022_diagnostic, naics_2022_cells = _naics_structure_diagnostic(
        workbooks["naics_2022_structure"], 2022
    )
    diagnostics: dict[str, Mapping[str, Any]] = {
        "bea_summary_use_2024": {
            "shared_axis": summary_diagnostic,
            "projection": "USE_2024_AXIS",
        },
        "bea_summary_make_2024": {
            "shared_axis": summary_diagnostic,
            "projection": "MAKE_2024_AXIS",
        },
        "bea_industry_commodity_naics_concordance": bea_diagnostic,
        "naics_2017_structure": naics_2017_diagnostic,
        "naics_2017_to_2022_concordance": naics_concordance_diagnostic,
        "naics_2022_structure": naics_2022_diagnostic,
    }
    selected: dict[str, Sequence[Cell]] = {
        **summary_cells,
        "bea_industry_commodity_naics_concordance": bea_cells,
        "naics_2017_structure": naics_2017_cells,
        "naics_2017_to_2022_concordance": naics_concordance_cells,
        "naics_2022_structure": naics_2022_cells,
    }
    source_records = [
        _workbook_record(
            pin,
            workbooks[pin.source_id],
            package_hashes[pin.source_id],
            selected[pin.source_id],
            diagnostics[pin.source_id],
        )
        for pin in SOURCE_PINS
    ]
    result: dict[str, Any] = {
        "artifact": {
            "schema_version": SCHEMA_VERSION,
            "generator_version": GENERATOR_VERSION,
            "status": STATUS,
            "role": ROLE,
            "canonicalization": CANONICALIZATION,
            "content_sha256": "0" * 64,
            "generator_module_sha256": sha256_bytes(module_bytes),
            "profile_physical_sha256": sha256_bytes(profile_bytes),
            "profile_semantic_sha256": profile["artifact"]["content_sha256"],
        },
        "boundary": {
            "profile_count": 6,
            "physically_qualified_profile_count": 0,
            "status": STATUS,
            "current_bodies_claimed_as_origin": False,
            "current_bodies_claimed_as_model_input": False,
            "current_bodies_claimed_as_truth": False,
            "body_to_url_provenance_verified": False,
            "body_to_provider_provenance_verified": False,
            "logical_profile_compatible": False,
            "self_accepted": False,
            "claim_ceiling": "PRESENT_DAY_PHYSICAL_LAYOUT_DIAGNOSTIC_ONLY",
        },
        "gates": _hard_false_gates(),
        "repository_bindings": repository_bindings,
        "sources": source_records,
        "cross_source_contract": {
            "summary": summary_diagnostic,
            "bea_concordance_has_explicit_industry_commodity_axis": False,
            "bea_concordance_projection_invented": False,
            "naics_concordance_direction": "NAICS_2017_TO_NAICS_2022",
            "reverse_concordance_in_place": False,
            "other_or_used_treated_as_naics": False,
            "successor_requirement": "VERSIONED_LOGICAL_SUCCESSOR_REQUIRED",
        },
        "limitations": {
            "external_bodies_remain_outside_repository": True,
            "provider_and_url_provenance_unverified": True,
            "local_self_hashes_are_unauthenticated_fixity_assertions": True,
            "python_runtime_not_a_provider_authenticator": True,
            "same_user_concurrent_rewrite_fully_excluded": False,
            "artifact_tool_corroboration_available_in_candidate_runtime": False,
            "no_claim_that_temp_transport_filenames_are_provider_filenames": True,
        },
    }
    result["artifact"]["content_sha256"] = _result_semantic_sha256(result)
    validate_derivative_shape(result)
    return result


def validate_derivative_shape(document: Mapping[str, Any]) -> None:
    """Validate exact result types, self-hash, ceilings, and closed topology."""

    if type(document) is not dict:
        fail("derivative must be an exact dict")
    _exact_json_tree(document, "derivative")
    if set(document) != {
        "artifact",
        "boundary",
        "gates",
        "repository_bindings",
        "sources",
        "cross_source_contract",
        "limitations",
    }:
        fail("derivative top-level schema drifted")
    artifact = document["artifact"]
    if (
        type(artifact) is not dict
        or set(artifact)
        != {
            "schema_version",
            "generator_version",
            "status",
            "role",
            "canonicalization",
            "content_sha256",
            "generator_module_sha256",
            "profile_physical_sha256",
            "profile_semantic_sha256",
        }
        or artifact.get("schema_version") != SCHEMA_VERSION
        or artifact.get("generator_version") != GENERATOR_VERSION
        or artifact.get("status") != STATUS
        or artifact.get("role") != ROLE
        or artifact.get("canonicalization") != CANONICALIZATION
        or not _is_sha256_text(artifact.get("content_sha256"))
        or not _is_sha256_text(artifact.get("generator_module_sha256"))
        or artifact.get("profile_physical_sha256")
        != EXPECTED_PROFILE_PHYSICAL_SHA256
        or artifact.get("profile_semantic_sha256")
        != "aad29e6493ab7d0d03e2da32b9be36ce1632ecce8bdf920c7bd3888454ac1147"
        or _result_semantic_sha256(document) != artifact["content_sha256"]
    ):
        fail("derivative artifact or self-hash drifted")
    if type(document["gates"]) is not dict or document["gates"] != _hard_false_gates():
        fail("derivative gates are not exactly hard false")
    boundary = document["boundary"]
    if (
        type(boundary) is not dict
        or set(boundary)
        != {
            "profile_count",
            "physically_qualified_profile_count",
            "status",
            "current_bodies_claimed_as_origin",
            "current_bodies_claimed_as_model_input",
            "current_bodies_claimed_as_truth",
            "body_to_url_provenance_verified",
            "body_to_provider_provenance_verified",
            "logical_profile_compatible",
            "self_accepted",
            "claim_ceiling",
        }
        or boundary.get("profile_count") != 6
        or boundary.get("physically_qualified_profile_count") != 0
        or boundary.get("status") != STATUS
        or boundary.get("logical_profile_compatible") is not False
        or boundary.get("self_accepted") is not False
        or boundary.get("current_bodies_claimed_as_origin") is not False
        or boundary.get("current_bodies_claimed_as_model_input") is not False
        or boundary.get("current_bodies_claimed_as_truth") is not False
        or boundary.get("body_to_url_provenance_verified") is not False
        or boundary.get("body_to_provider_provenance_verified") is not False
        or boundary.get("claim_ceiling")
        != "PRESENT_DAY_PHYSICAL_LAYOUT_DIAGNOSTIC_ONLY"
    ):
        fail("derivative boundary rose above CANNOT_RUN")
    sources = document["sources"]
    if type(sources) is not list or len(sources) != 6:
        fail("derivative source set drifted")
    if tuple(record.get("source_id") for record in sources) != SOURCE_IDS:
        fail("derivative source order drifted")
    source_keys = {
        "source_id",
        "parser_kind",
        "body_sha256",
        "body_byte_count",
        "body_hash_size_verified",
        "body_to_url_provenance_verified",
        "body_to_provider_provenance_verified",
        "transport_authenticated",
        "claim",
        "ordered_zip_metadata_sha256",
        "zip_members",
        "content_types_in_document_order",
        "resolved_content_types_in_member_order",
        "relationships_in_part_and_element_order",
        "shared_strings",
        "styles",
        "defined_names",
        "sheets_in_workbook_order",
        "classification_cells_in_source_order",
        "diagnostic",
        "zero_cell_formulas_verified",
        "zero_error_cells_verified",
        "defined_name_ref_errors_preserved_not_executed",
    }
    for record, pin in zip(sources, SOURCE_PINS):
        if (
            type(record) is not dict
            or set(record) != source_keys
            or record.get("parser_kind") != pin.parser_kind
            or record.get("body_sha256") != pin.sha256
            or record.get("body_byte_count") != pin.byte_count
            or record.get("body_hash_size_verified") is not True
            or record.get("body_to_url_provenance_verified") is not False
            or record.get("body_to_provider_provenance_verified") is not False
            or record.get("transport_authenticated") is not False
            or record.get("claim")
            != "EXACT_LOCAL_SERVER_BODY_BYTES_ONLY_NO_URL_OR_PROVIDER_PROVENANCE"
            or record.get("zero_cell_formulas_verified") is not True
            or record.get("zero_error_cells_verified") is not True
            or record.get("defined_name_ref_errors_preserved_not_executed")
            is not True
        ):
            fail("derivative source claim semantics drifted")
    cross = document["cross_source_contract"]
    if (
        type(cross) is not dict
        or set(cross)
        != {
            "summary",
            "bea_concordance_has_explicit_industry_commodity_axis",
            "bea_concordance_projection_invented",
            "naics_concordance_direction",
            "reverse_concordance_in_place",
            "other_or_used_treated_as_naics",
            "successor_requirement",
        }
        or cross.get("naics_concordance_direction")
        != "NAICS_2017_TO_NAICS_2022"
        or cross.get("reverse_concordance_in_place") is not False
        or cross.get("bea_concordance_has_explicit_industry_commodity_axis")
        is not False
        or cross.get("bea_concordance_projection_invented") is not False
        or cross.get("other_or_used_treated_as_naics") is not False
        or cross.get("successor_requirement")
        != "VERSIONED_LOGICAL_SUCCESSOR_REQUIRED"
    ):
        fail("derivative direction/special-account/successor contract drifted")
    summary = cross.get("summary")
    if (
        type(summary) is not dict
        or summary.get("industry_count") != 71
        or summary.get("commodity_count") != 73
        or summary.get("physical_special_order") != ["Used", "Other"]
        or summary.get("accepted_logical_special_order") != ["Other", "Used"]
        or summary.get("logical_profile_compatible") is not False
        or summary.get("special_accounts_are_naics") is not False
    ):
        fail("derivative summary mismatch ceiling drifted")
    repository = document["repository_bindings"]
    if (
        type(repository) is not dict
        or set(repository)
        != {
            "records",
            "logical_profile_semantic_sha256",
            "local_bridge_claim",
        }
        or repository.get("logical_profile_semantic_sha256")
        != "1ea4517532226a4d7026fd5e2061f32a2866e057a73e1064351ffb55ac33c992"
        or repository.get("local_bridge_claim")
        != "REPOSITORY_LOCAL_RECEIPT_BYTES_ONLY_NONORIGIN"
        or type(repository.get("records")) is not list
        or len(repository["records"]) != 4
    ):
        fail("derivative repository-binding schema drifted")
    expected_binding_ids = (
        "logical_module",
        "logical_profile",
        "logical_tests",
        "local_bea71_bridge",
    )
    for record, binding_id in zip(repository["records"], expected_binding_ids):
        if (
            type(record) is not dict
            or set(record)
            != {
                "binding_id",
                "physical_sha256",
                "byte_count",
                "fixity_verified",
                "provider_origin_verified",
            }
            or record.get("binding_id") != binding_id
            or not _is_sha256_text(record.get("physical_sha256"))
            or record.get("fixity_verified") is not True
            or record.get("provider_origin_verified") is not False
        ):
            fail("derivative repository-binding record drifted")
    limitations = document["limitations"]
    if (
        type(limitations) is not dict
        or set(limitations)
        != {
            "external_bodies_remain_outside_repository",
            "provider_and_url_provenance_unverified",
            "local_self_hashes_are_unauthenticated_fixity_assertions",
            "python_runtime_not_a_provider_authenticator",
            "same_user_concurrent_rewrite_fully_excluded",
            "artifact_tool_corroboration_available_in_candidate_runtime",
            "no_claim_that_temp_transport_filenames_are_provider_filenames",
        }
        or limitations.get("same_user_concurrent_rewrite_fully_excluded")
        is not False
        or limitations.get("artifact_tool_corroboration_available_in_candidate_runtime")
        is not False
        or any(
            limitations.get(key) is not True
            for key in (
                "external_bodies_remain_outside_repository",
                "provider_and_url_provenance_unverified",
                "local_self_hashes_are_unauthenticated_fixity_assertions",
                "python_runtime_not_a_provider_authenticator",
                "no_claim_that_temp_transport_filenames_are_provider_filenames",
            )
        )
    ):
        fail("derivative limitations ceiling drifted")


def validate_derivative_document(
    document: Mapping[str, Any],
    source_paths: Mapping[str, Path],
) -> None:
    """Rebuild from exact sources and compare every result field."""

    validate_derivative_shape(document)
    expected = compile_derivative(source_paths)
    if canonical_json_bytes(document) != canonical_json_bytes(expected):
        fail("derivative does not exactly replay from source/profile evidence")


def validate_derivative_bytes(
    data: bytes,
    source_paths: Mapping[str, Path],
) -> dict[str, Any]:
    """Strictly parse and source-replay one serialized derivative."""

    document = parse_json_bytes(data, "derivative")
    if canonical_json_bytes(document) != data:
        fail("derivative bytes are not exact canonical JSON")
    validate_derivative_document(document, source_paths)
    return document


def _argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Compile the nonadmitting classification-map physical diagnostic."
    )
    parser.add_argument("--bea-summary-use", required=True, type=Path)
    parser.add_argument("--bea-summary-make", required=True, type=Path)
    parser.add_argument("--bea-concordance", required=True, type=Path)
    parser.add_argument("--naics-2017", required=True, type=Path)
    parser.add_argument("--naics-concordance", required=True, type=Path)
    parser.add_argument("--naics-2022", required=True, type=Path)
    parser.add_argument("--validate-result", type=Path)
    return parser


def _source_paths_from_args(args: argparse.Namespace) -> dict[str, Path]:
    return {
        "bea_summary_use_2024": args.bea_summary_use,
        "bea_summary_make_2024": args.bea_summary_make,
        "bea_industry_commodity_naics_concordance": args.bea_concordance,
        "naics_2017_structure": args.naics_2017,
        "naics_2017_to_2022_concordance": args.naics_concordance,
        "naics_2022_structure": args.naics_2022,
    }


def main(argv: Sequence[str] | None = None) -> int:
    args = _argument_parser().parse_args(argv)
    source_paths = _source_paths_from_args(args)
    try:
        if args.validate_result is None:
            document = compile_derivative(source_paths)
        else:
            data, _ = _read_stable_regular_file(
                args.validate_result, "derivative input", max_bytes=64 * 1024 * 1024
            )
            document = validate_derivative_bytes(data, source_paths)
        sys.stdout.buffer.write(canonical_json_bytes(document))
    except ProfileError as error:
        print("classification physical profile error: " + str(error), file=sys.stderr)
        return 1
    return 0


__all__ = (
    "ProfileError",
    "SOURCE_IDS",
    "canonical_json_bytes",
    "compile_derivative",
    "load_profile",
    "parse_json_bytes",
    "parse_workbook",
    "parse_workbook_bytes",
    "validate_derivative_bytes",
    "validate_derivative_document",
    "validate_derivative_shape",
    "validate_profile_document",
)


if __name__ == "__main__":
    raise SystemExit(main())
